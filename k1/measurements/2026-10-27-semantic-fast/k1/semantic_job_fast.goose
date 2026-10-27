// Scratch-only resolver-owned private job. No cache or C09 receipt.
namespace semantic_job_fast;
import source_resolver;
import source_identity;
import semantic_owner;
import semantic_owner_fast;
struct Output {status:i64=1,wasm:u8[]=[]}
fn compile(root:source_resolver::Root&,module:u8[:],name:u8[:],depth_used:u32,depth_limit:u32,frame_used:u32,frame_limit:u32,failpoint:u32)->Output {
 if failpoint>3 {return Output {};}
 let read=source_resolver::read(root,module,name);if read.status!=0 {return Output {status:10+read.status};}
 if failpoint==1{return Output {status:20};}
 if !source_identity::verify(read.source,root.package,module,name,read.source.bytes) {return Output {};}
 var built=semantic_owner::build(root.package,module,name,read.source.bytes);if built.status!=0 {return Output {};}
 if failpoint==2{return Output {status:20};}
 let staged=semantic_owner_fast::emit(root.package,module,name,read.source.bytes,built.owner,depth_used,depth_limit,frame_used,frame_limit);
 if staged.status!=0 {return Output {status:staged.status};}
 // Unlike the original job, do not decode the unchanged staged target again:
 // fast emission has just independently decoded it before returning it.
 if failpoint==3{return Output {status:20};}
 return Output {status:0,wasm:copy(staged.wasm)};
}
