// Copyright (c) 2013 Quanta Research Cambridge, Inc.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
import Vector::*;
import BuildVector::*;
import Cntrs::*;
import FIFOF::*;
import FIFO::*;
import GetPut::*;
import Assert::*;
import ClientServer::*;
import BRAM::*;
import BRAMFIFO::*;
import ConfigCounter::*;
import Connectable::*;
import ConnectalMemory::*;
import ConnectalBramFifo::*;
import MemTypes::*;
import Pipe::*;
import MemUtils::*;
import ConnectalConfig::*;

`include "ConnectalProjectConfig.bsv"

module mkMemReadEngine(MemReadEngine#(busWidth, userWidth, cmdQDepth, numServers))
   provisos( Mul#(TDiv#(busWidth, 8), 8, busWidth)
	    ,Add#(1, a__, numServers)
	    ,Add#(busWidth, 0, userWidth)
	    ,FunnelPipesPipelined#(1, numServers, MemTypes::MemData#(userWidth), 2)
	    ,Pipe::FunnelPipesPipelined#(1, numServers, MemTypes::MemRequest, 2)
	    ,Add#(b__, TLog#(numServers), 6)
      	    );
   let rv <- mkMemReadEngineBuff(valueOf(cmdQDepth) * valueOf(TExp#(BurstLenSize)));
   return rv;
endmodule

typedef struct {
    Bit#(BurstLenSize) len;
    Bool               last;
} NextReq deriving (Bits, Eq);

function NextReq getNext(Bit#(32) len, Bit#(BurstLenSize) burst);
   NextReq v;
   v.last = (len <= extend(burst));
   v.len = v.last ? truncate(len) : burst;
   return v;
endfunction

typedef struct {
   Bit#(indexSize)    idx;
   SGLId              sglId;
   Bit#(32)           base;
   Bit#(MemTagSize)   tag;
   Bool               last;
   Bit#(BurstLenSize) burstLen;
} ServerRequest#(numeric type indexSize) deriving (Bits, Eq);

interface MemReadChannel#(numeric type busWidth, numeric type userWidth, numeric type cmdQDepth);
   interface PipeOut#(MemRequest)        readReq;
   interface PipeIn#(MemData#(busWidth)) readData;
   interface MemReadEngineServer#(userWidth) readServer;
endinterface

module mkMemReadChannel#(Integer bufferSizeBytes, Integer channelNumber) (MemReadChannel#(busWidth, userWidth, cmdQDepth))
   provisos (Div#(busWidth,8,busWidthBytes),
	     Mul#(busWidthBytes,8,busWidth),
	     Log#(busWidthBytes,beatShift),
	     Log#(cmdQDepth,logCmdQDepth),
	     Log#(cmdQDepth, cmdBuffAddrSz),
	     Log#(1, serverIdxSz),
	     Add#(busWidth, 0, userWidth),
	     Add#(1,logCmdQDepth, outCntSz),
	     Add#(1, c__, 1),
	     Add#(b__, TLog#(1), cmdBuffAddrSz),
	     Add#(e__, TLog#(1), TAdd#(1, cmdBuffAddrSz)),
	     Add#(a__, serverIdxSz, cmdBuffAddrSz),
	     Min#(2,TLog#(1),bpc),
	     Add#(d__, TLog#(1), TAdd#(1, serverIdxSz)),
	     Add#(f__, serverIdxSz, MemTagSize));
   let verbose = False;
   let beatShift = fromInteger(valueOf(beatShift));

   let clock <- exposeCurrentClock();
   let reset <- exposeCurrentReset();

   Integer bufferSizeBeats = bufferSizeBytes/valueOf(busWidthBytes);
   Reg#(Bool)          clientInFlight <- mkReg(False);
   ConfigCounter#(16)  clientAvail <- mkConfigCounter(fromInteger(bufferSizeBeats));
   Reg#(MemengineCmd)  clientCommand <- mkReg(unpack(0));
`ifdef USE_DUAL_CLOCK_FIFOF
   FIFOF#(MemDataF#(userWidth)) clientDataFifo <- mkDualClockBramFIFOF(clock, reset, clock, reset);
`else
   FIFOF#(MemDataF#(userWidth)) clientDataFifo <- mkSizedBRAMFIFOF(bufferSizeBeats);
`endif
   FIFO#(MemengineCmd) clientRequest <- mkFIFO();
   Reg#(Bit#(32))      clientLen <- mkReg(unpack(0));
   Reg#(Bit#(32))      clientBase <- mkReg(unpack(0));
   Reg#(NextReq)       clientNext <- mkReg(unpack(0));
   Count#(Bit#(32))    clientCycles <- mkCount(0);
   FIFOF#(MemRequestCycles) clientCyclesFifo <- mkFIFOF();
   
   FIFO#(Tuple3#(Bool,Bool,Bit#(BurstLenSize))) serverCheckAvail <- mkSizedFIFO(1);
   FIFOF#(ServerRequest#(serverIdxSz))      serverRequest <- mkFIFOF();
   FIFOF#(MemRequest)                          dmaRequest <- mkSizedFIFOF(valueOf(cmdQDepth));
   FIFO#(Tuple3#(Bit#(8),Bit#(serverIdxSz),Bool)) serverProcessing <- mkSizedFIFO(valueOf(cmdQDepth));
   FIFOF#(MemData#(busWidth))                       serverDataFifo <- mkFIFOF;

   Reg#(Bit#(8))                    respCnt <- mkReg(0);
   Reg#(Bit#(32)) counter <- mkReg(0);

   rule incCounter;
      counter <= counter + 1;
   endrule
         
   rule rule_cycles;
      clientCycles.incr(1);
   endrule
   rule rule_startNew if (!clientInFlight);
      let cmd <- toGet(clientRequest).get();
      clientInFlight <= True;
      clientCommand <= cmd;
      clientLen <= cmd.len - extend(cmd.burstLen);
      clientBase <= cmd.base;
      clientNext <= getNext(cmd.len, cmd.burstLen);
      clientCycles <= 0;
      if (verbose) $display("mkMemReadEngineBuff::%d rule_startNew %d", counter, clientAvail.read);
   endrule
   rule rule_checkAvail if (clientInFlight);
      let cmd_len = clientNext.len;
      let last_burst = clientNext.last;
      let cond0 <- clientAvail.maybeDecrement(unpack(extend(cmd_len>>beatShift)));
      serverCheckAvail.enq(tuple3(cond0,last_burst,cmd_len));
      if (verbose) $display("mkMemReadEngineBuff::%d rule_checkAvail avail %d burstLen %d cond0 %d last_burst %d", counter, clientAvail.read(), cmd_len>>beatShift, cond0, last_burst);
   endrule

   rule rule_requestServer if (clientInFlight);
      match {.cond0,.last_burst,.cmd_len} <- toGet(serverCheckAvail).get;
      if  (cond0) begin
	 if (verbose) $display("mkMemReadEngineBuff::%d rule_requestServer clientLen %d cond0 %d last_burst %d", counter, clientLen, cond0, last_burst);
	 serverRequest.enq(ServerRequest{
	    idx:fromInteger(0),sglId:clientCommand.sglId,base:clientBase,
	    tag:clientCommand.tag,last:last_burst,burstLen:cmd_len});
         clientBase <= clientBase + extend(cmd_len);
         clientLen <= clientLen - extend(cmd_len);
         clientNext <= getNext(clientLen, clientCommand.burstLen);
	 if (last_burst) begin
	    if (verbose) $display("mkMemReadEngineBuff::%d rule_requestServer last_burst %d", counter, last_burst);
	    clientInFlight <= False;
	    `ifdef MEMENGINE_REQUEST_CYCLES
	    $display("clientCycles = %d", clientCycles);
	    clientCyclesFifo.enq(MemRequestCycles { tag:clientCommand.tag, cycles: clientCycles });
	    `endif
	 end
      end
   endrule
   
   rule rl_serverRequest;
      let sr <- toGet(serverRequest).get;
      serverProcessing.enq(tuple3(truncate(sr.burstLen>>beatShift), sr.idx, sr.last));
      if (verbose) $display("MemReadEngine::%d readReq idx %d offset %h burstLenBytes %h last %d", counter, sr.idx, sr.base, sr.burstLen, sr.last);

      dmaRequest.enq(MemRequest { sglId: sr.sglId, offset: extend(sr.base),
	 burstLen:sr.burstLen, tag: fromInteger(channelNumber)
`ifdef BYTE_ENABLES
				 , firstbe: maxBound, lastbe: maxBound
`endif
	       });
   endrule

   rule read_data_rule;
      let d <- toGet(serverDataFifo).get();
      match {.rc, .idx, .last_burst} = serverProcessing.first;
      let new_respCnt = respCnt+1;
      let l = False;
      if (verbose) $display("mkMemReadEngineBuff::%d data %h new_respCnt %d rc %d last_burst %d idx %d clientInFlight %d eob %d", counter, d.data, new_respCnt, rc, last_burst, idx, clientInFlight, d.last);
      if (new_respCnt == rc) begin
	 respCnt <= 0;
	 serverProcessing.deq;
	 //$display("eob %d", idx);
	 l = last_burst;
      end
      else begin
	 respCnt <= new_respCnt;
      end
      clientDataFifo.enq(MemDataF { data: d.data, tag: d.tag >> valueOf(serverIdxSz), first: (respCnt == 0), last: l});
   endrule

   MemReadEngineServer#(userWidth) rs = (interface MemReadEngineServer#(userWidth);
		  interface Put request;
		     method Action put(MemengineCmd cmd);
`ifdef SIMULATION
			Bit#(32) bsb = fromInteger(bufferSizeBytes);
			Bit#(32) dw = fromInteger(valueOf(busWidthBytes));
			let mdw = ((cmd.len)/dw)*dw != cmd.len;
			let bbl = extend(cmd.burstLen) > bsb;
			if(bbl || mdw) begin
			   if (bbl)
			      $display("XXXXXXXXXX mkMemReadEngineBuff::unsupported burstLen %d %d", bsb, cmd.burstLen);
			   if (mdw)
			      $display("XXXXXXXXXX mkMemReadEngineBuff::unsupported len %d", cmd.len);
			end
			else
`endif
                           begin
			   clientRequest.enq(cmd);
			   end
 		     endmethod
		  endinterface
                  interface data = interface PipeOut;
	             method MemDataF#(userWidth) first;
	                return clientDataFifo.first;
	             endmethod
	             method Action deq;
	                if (verbose) $display("mkMemReadEngineBuff::check_out: data %h clientAvail %d eob %d", clientDataFifo.first.data, clientAvail.read(), clientDataFifo.first.last);
	                clientDataFifo.deq;
	                clientAvail.increment(1);
	             endmethod
	             method Bool notEmpty = clientDataFifo.notEmpty;
                  endinterface;
	       interface requestCycles = toPipeOut(clientCyclesFifo);
               endinterface);
   interface readServer = rs;
   interface PipeOut readReq = toPipeOut(dmaRequest);
   interface PipeIn readData = toPipeIn(serverDataFifo);
endmodule

module mkMemReadEngineBuff#(Integer bufferSizeBytes) (MemReadEngine#(busWidth, userWidth, cmdQDepth, numServers))
   provisos (Div#(busWidth,8,busWidthBytes),
	     Mul#(busWidthBytes,8,busWidth),
	     Add#(busWidth, 0, userWidth),
	     FunnelPipesPipelined#(1, numServers, MemTypes::MemData#(userWidth), 2),
	     FunnelPipesPipelined#(1, numServers, MemTypes::MemRequest, 2),
	     Add#(a__, TLog#(numServers), 6)
	     );
   let verbose = False;

   let clock <- exposeCurrentClock();
   let reset <- exposeCurrentReset();

   Integer bufferSizeBeats = bufferSizeBytes/valueOf(busWidthBytes);

   Vector#(numServers, MemReadChannel#(busWidth,userWidth,cmdQDepth)) readChannels <- genWithM(mkMemReadChannel(bufferSizeBytes));
   Vector#(numServers, FIFOF#(Bit#(MemTagSize))) readtagFifos <- replicateM(mkSizedFIFOF(valueOf(cmdQDepth)));
   function PipeOut#(MemRequest) readChannelDmaReadReq(Integer i);
      return readChannels[i].readReq;
   endfunction
   function MemReadEngineServer#(userWidth) readChannelServer(Integer i);
      return readChannels[i].readServer;
   endfunction

   FIFOF#(MemRequest) reqFifo <- mkFIFOF();
   FunnelPipe#(1,numServers,MemRequest,2) reqFunnel <- mkFunnelPipesPipelined(genWith(readChannelDmaReadReq));
   FIFOF#(MemData#(busWidth)) readDataFifo <- mkFIFOF();
   function Tuple2#(Bit#(TLog#(numServers)),MemData#(userWidth)) tagData(MemData#(userWidth) md);
      return tuple2(truncate(md.tag), md);
   endfunction
   UnFunnelPipe#(1,numServers,MemData#(userWidth),2) dataPipes <- mkUnFunnelPipesPipelined(vec(mapPipe(tagData, toPipeOut(readDataFifo))));
   // FIXME: pass this a parameter to mkMemReadChannel
   for (Integer channel = 0; channel < valueOf(numServers); channel = channel + 1)
      mkConnection(dataPipes[channel], readChannels[channel].readData);

   interface Vector  readServers = genWith(readChannelServer);
   interface MemReadClient dmaClient;
      interface Get    readReq = toGet(reqFunnel[0]);
      interface Put   readData = toPut(readDataFifo);
   endinterface

endmodule
