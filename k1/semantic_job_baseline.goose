// Resolver-bound private single-module compilation job. Trusted caller owns
// one live non-copied Root/package mapping; paths are checked by the resolver.
// This is not public K1 authority, a filesystem snapshot, or a retained cache.
namespace semantic_job_baseline;
import source_resolver;
import source_identity;
import semantic_owner;
struct Output {status:i64=1,wasm:u8[]=[]}
// Status 0 success; 1 bad source/identity/target; 2 depth; 3 frame;
// 10..14 resolver failure (10 + its nonzero status); 20 cancellation.
// No output escapes on any failure. Exactly one file read supplies every check.
fn compile(root:source_resolver::Root&,module:u8[:],name:u8[:],depth_used:u32,depth_limit:u32,frame_used:u32,frame_limit:u32,failpoint:u32)->Output {
 if failpoint>3 {return Output {};}
 let read=source_resolver::read(root,module,name);if read.status!=0 {return Output {status:10+read.status};}
 if failpoint==1{return Output {status:20};}
 // Compare against the original live root and exact resolver-owned snapshot;
 // all subsequent steps use the same bytes and no externally supplied hash.
 if !source_identity::verify(read.source,root.package,module,name,read.source.bytes) {return Output {};}
 var built=semantic_owner::build(root.package,module,name,read.source.bytes);if built.status!=0 {return Output {};}
 if failpoint==2{return Output {status:20};}
 let staged=semantic_owner::emit(root.package,module,name,read.source.bytes,built.owner,depth_used,depth_limit,frame_used,frame_limit);
 if staged.status!=0 {return Output {status:staged.status};}
 if !semantic_owner::verify(root.package,module,name,read.source.bytes,built.owner,staged.wasm) {return Output {};}
 if failpoint==3{return Output {status:20};}
 return Output {status:0,wasm:copy(staged.wasm)};
}
