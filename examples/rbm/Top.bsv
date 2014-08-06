// bsv libraries
import SpecialFIFOs::*;
import Vector::*;
import StmtFSM::*;
import FIFO::*;
import Connectable::*;

// portz libraries
import Directory::*;
import CtrlMux::*;
import Portal::*;
import Leds::*;
import PortalMemory::*;
import MemServer::*;
import MemUtils::*;
import PortalMemory::*;
import MemTypes::*;
import HostInterface::*;

// generated by tool
import DmaConfigWrapper::*;
import DmaIndicationProxy::*;
import MmIndicationProxy::*;
import TimerIndicationProxy::*;
import TimerRequestWrapper::*;
import MmDebugRequestWrapper::*;
import MmDebugIndicationProxy::*;
import RbmRequestWrapper::*;
import RbmIndicationProxy::*;
import SigmoidRequestWrapper::*;
import SigmoidIndicationProxy::*;
`ifdef MATRIX_TN
import MmRequestTNWrapper::*;
`else
`ifdef MATRIX_NT
import MmRequestNTWrapper::*;
`endif
`endif

import RbmTypes::*;
import Sigmoid::*;
import Rbm::*;


module  mkPortalTop#(HostType host) (PortalTop#(PhysAddrWidth,TMul#(32,N),Empty,NumberOfMasters));

   DmaIndicationProxy dmaIndicationProxy <- mkDmaIndicationProxy(DmaIndicationPortal);

   RbmIndicationProxy rbmIndicationProxy <- mkRbmIndicationProxy(RbmIndicationPortal);
   MmDebugIndicationProxy mmDebugIndicationProxy <- mkMmDebugIndicationProxy(MmDebugIndicationPortal);
   MmIndicationProxy   mmIndicationProxy <- mkMmIndicationProxy(MmIndicationPortal);
   SigmoidIndicationProxy   sigmoidIndicationProxy <- mkSigmoidIndicationProxy(SigmoidIndicationPortal);
   TimerIndicationProxy timerIndicationProxy <- mkTimerIndicationProxy(TimerIndicationPortal);
   Rbm#(N) rbm <- mkRbm(host, 
			rbmIndicationProxy.ifc, mmIndicationProxy.ifc,
			mmDebugIndicationProxy.ifc,
			sigmoidIndicationProxy.ifc, timerIndicationProxy.ifc);
   RbmRequestWrapper rbmRequestWrapper <- mkRbmRequestWrapper(RbmRequestPortal,rbm.rbmRequest);
`ifdef MATRIX_TN
   MmRequestTNWrapper mmRequestWrapper <- mkMmRequestTNWrapper(MmRequestPortal,rbm.mmRequest);
`else
`ifdef MATRIX_NT
   MmRequestNTWrapper mmRequestWrapper <- mkMmRequestNTWrapper(MmRequestPortal,rbm.mmRequest);
`endif
`endif
   MmDebugRequestWrapper mmDebugRequestWrapper <- mkMmDebugRequestWrapper(MmDebugRequestPortal,rbm.mmDebugRequest);
   SigmoidRequestWrapper   sigmoidRequestWrapper <- mkSigmoidRequestWrapper(SigmoidRequestPortal,rbm.sigmoidRequest);
   TimerRequestWrapper timerRequestWrapper <- mkTimerRequestWrapper(TimerRequestPortal,rbm.timerRequest);

   Vector#(12,ObjectReadClient#(TMul#(32,N))) readClients = rbm.readClients;
   Vector#(6,ObjectWriteClient#(TMul#(32,N))) writeClients = rbm.writeClients;

   MemServer#(PhysAddrWidth, TMul#(32,N), NumberOfMasters) dma <- mkMemServer(dmaIndicationProxy.ifc, readClients, writeClients);
   DmaConfigWrapper dmaConfigWrapper <- mkDmaConfigWrapper(DmaConfigPortal,dma.request);

   Vector#(12,StdPortal) portals;
   portals[0] = mmRequestWrapper.portalIfc;
   portals[1] = mmIndicationProxy.portalIfc; 
   portals[2] = dmaConfigWrapper.portalIfc;
   portals[3] = dmaIndicationProxy.portalIfc; 
   portals[4] = timerRequestWrapper.portalIfc;
   portals[5] = timerIndicationProxy.portalIfc; 
   portals[6] = mmDebugIndicationProxy.portalIfc;
   portals[7] = mmDebugRequestWrapper.portalIfc;
   portals[8] = sigmoidRequestWrapper.portalIfc;
   portals[9] = sigmoidIndicationProxy.portalIfc;
   portals[10] = rbmRequestWrapper.portalIfc;
   portals[11] = rbmIndicationProxy.portalIfc;
   StdDirectory dir <- mkStdDirectory(portals);
   let ctrl_mux <- mkSlaveMux(dir,portals);
   
   interface interrupt = getInterruptVector(portals);
   interface slave = ctrl_mux;
   interface masters = dma.masters;

endmodule : mkPortalTop
