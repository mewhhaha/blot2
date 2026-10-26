import work;
import proofgraph_engine;
fn main() {
 let s="pub let f: (U32,U32)->U32 ! {} requires [Lt(arg.0,arg.0)] resources {depth:1,frame:0} = fn (a,b) => return a";
 var baseline=proofgraph_engine::Job {}; assert(proofgraph_engine::begin(s,baseline).status==6);
 let pv=baseline.meter.proof_visits; let sem=baseline.meter.semantic;
 assert(pv>0 && sem>0);
 var exact=proofgraph_engine::Job {}; exact.meter.proof_visits=65536-pv;
 assert(proofgraph_engine::begin(s,exact).status==6 && exact.meter.proof_visits==65536 && exact.failed && !exact.active);
 var short=proofgraph_engine::Job {}; short.meter.proof_visits=65537-pv;
 let denied=proofgraph_engine::begin(s,short); assert(denied.status==2 && denied.receipt.quantity==2 && short.failed && !short.active);
 var semexact=proofgraph_engine::Job {}; semexact.meter.semantic=1048576-sem;
 assert(proofgraph_engine::begin(s,semexact).status==6 && semexact.meter.semantic==1048576 && semexact.failed && !semexact.active);
 var semshort=proofgraph_engine::Job {}; semshort.meter.semantic=1048577-sem;
 let deniedsem=proofgraph_engine::begin(s,semshort); assert(deniedsem.status==3 && deniedsem.receipt.quantity==1 && semshort.failed && !semshort.active);
 var both=proofgraph_engine::Job {}; both.meter.semantic=1048576; both.meter.proof_visits=65536;
 let simultaneous=proofgraph_engine::begin(s,both); assert(simultaneous.status==3 && simultaneous.receipt.quantity==1 && both.failed && !both.active);
 print("contradiction budget boundaries passed");
}
