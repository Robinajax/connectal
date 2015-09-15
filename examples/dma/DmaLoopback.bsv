// Copyright (c) 2015 Connectal Project

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
import Connectable::*;
import MemTypes::*;
import HostInterface::*;
import DmaController::*;

interface DmaLoopback;
   interface DmaRequest request0;
   interface DmaRequest request1;
   interface Vector#(1,MemReadClient#(DataBusWidth))      readClient;
   interface Vector#(1,MemWriteClient#(DataBusWidth))     writeClient;
endinterface

module mkLoopback#(DmaController#(numChannels) dma)(Empty);
   mkConnection(dma.readData, dma.writeData);
endmodule

module mkDmaLoopback#(DmaIndication indication0, DmaIndication indication1)(DmaLoopback);
   DmaController#(2) dma <- mkDmaController(vec(indication0,indication1));
   let app <- mkLoopback(dma);
   
   interface request0    = dma.request[0];
   interface request1    = dma.request[1];
   interface readClient  = dma.readClient;
   interface writeClient = dma.writeClient;
endmodule