// Partial inspection accounting on the actual private emission path. All
// other required traversals are unmetered; results are NOT C09 receipts and
// must not be cached or treated as public admission evidence.
namespace semantic_owner_metered;
import semantic_owner;
import semantic_contract_metered;
import source_identity;
import short_emit;
import short_target;
import work;
struct Output {status:i64=1,bytes:u8[]=[],receipt:work::Receipt=work::Receipt {}}
// Compiler-owned only; neither this record nor its counters are an artifact
// or host-controlled receipt. A failed job cannot resume or reset its meter.
struct Job {meter:work::Meter=work::Meter {},failed:bool=false}
// 1 invalid input/target, 2 semantic limit, 3 accounting, 4 depth, 5 frame.
// The same compiler-owned declaration meter must be passed to every phase.
fn emit_inner(package:u8[:],module:u8[:],name:u8[:],source:u8[:],o:semantic_owner::Owner&,m:work::Meter&,phase:u32,depth_used:u32,depth_limit:u32,frame_used:u32,frame_limit:u32)->Output {
 if phase!=5{return Output {status:3};}
 if !source_identity::verify(o.origin,package,module,name,source) {return Output {};}
 let checked=semantic_contract_metered::check(source,o.core,m,phase);
 if checked.status!=0 {return Output {status:checked.status,receipt:checked.receipt};}
 if !semantic_owner::declaration(source,o.core,name){return Output {};}
 let c=o.core;
 if depth_limit>128 || depth_used>depth_limit || c.declared_depth>depth_limit-depth_used{return Output {status:4};}
 if frame_used>frame_limit || c.declared_frame>frame_limit-frame_used{return Output {status:5};}
 let bytes=short_emit::emit(source,o.core.program);
 if bytes.len==0 || !short_target::verify(source,o.core.program,bytes){return Output {};}
 return Output {status:0,bytes:copy(bytes)};
}
fn emit(package:u8[:],module:u8[:],name:u8[:],source:u8[:],o:semantic_owner::Owner&,job:Job&,phase:u32,depth_used:u32,depth_limit:u32,frame_used:u32,frame_limit:u32)->Output {
 if job.failed {return Output {status:3};}
 let out=emit_inner(package,module,name,source,o,job.meter,phase,depth_used,depth_limit,frame_used,frame_limit);
 if out.status!=0 {job.failed=true;if job.meter.gate!=0 {job.meter.gate=9;}}
 return out;
}
