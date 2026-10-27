// Private source-bound semantic owner for the short scalar/finite-loop path.
// The trusted caller supplies immutable original source and invocation-local
// capacity. Records are not authenticated capabilities or portable evidence.
namespace semantic_leaf;
import short_core;
import short_frontend;
import short_check;
import short_target;
import short_emit;

struct Core {
 program:short_core::Program=short_core::Program {},
 effects:u32=0, declared_depth:u32=0, declared_frame:u32=0,
 actual_depth:u32=0, actual_frame:u32=0, loops:u32=0
}
struct Build {status:i64=1,core:Core=Core {}}
struct Output {status:i64=1,wasm:u8[]=[]}

// Replay source, type/proof and lexical structure before consulting metadata.
// Every accepted node belongs to the closed local-scalar language: no call,
// host operation, ownership operation, aggregate or K1 frame access. Its
// target verifier independently enforces the same restriction on emitted code.
fn valid(source:u8[:],c:Core&)->bool {
 if !short_check::verify(source,c.program) {return false;}
 if c.effects!=0 || c.actual_depth!=1 || c.actual_frame!=0 ||
    c.declared_depth!=c.program.head.depth || c.declared_frame!=c.program.head.frame ||
    c.declared_depth<1 || c.declared_depth>128 {return false;}
 if c.program.binding_types.len!=c.program.tree.bindings.len || c.program.types.len!=c.program.tree.nodes.len {return false;}
 for t in c.program.binding_types {if t!=1 && t!=2{return false;}}
 var loops:u32=0;
 for n,i in c.program.tree.nodes {
  if n.tag==15 {loops+=1;}
  if n.tag!=1 && n.tag!=2 && n.tag!=3 && n.tag!=4 && n.tag!=6 && n.tag!=9 && n.tag!=10 && n.tag!=11 && n.tag!=12 && n.tag!=13 && n.tag!=14 && n.tag!=15 && n.tag!=16 && n.tag!=17 && n.tag!=18 && n.tag!=19 && n.tag!=20 && n.tag!=21 && n.tag!=22 && n.tag!=23 && n.tag!=24 && n.tag!=25 && n.tag!=26 && n.tag!=27 && n.tag!=28 {return false;}
  if c.program.types[i]<1 || c.program.types[i]>4{return false;}
 }
 return loops==c.loops && loops<=128;
}
fn build(source:u8[:])->Build {
 var r=short_frontend::parse(source);if r.status!=0 {return Build {};}
 var loops:u32=0;for n in r.program.tree.nodes {if n.tag==15 {loops+=1;}}
 var c=Core {program:copy(r.program),effects:0,declared_depth:r.program.head.depth,declared_frame:r.program.head.frame,actual_depth:1,actual_frame:0,loops:loops};
 if !valid(source,c){return Build {};}
 return Build {status:0,core:copy(c)};
}
// Exact source and target are both replayed; summaries never authenticate them.
fn verify(source:u8[:],c:Core&,target:u8[:])->bool {
 return valid(source,c) && short_target::verify(source,c.program,target);
}
// Status 1 invalid Core/target, 2 depth, 3 frame; failure returns no bytes.
// The wider declared bound, not merely the body requirement, consumes capacity.
fn emit(source:u8[:],c:Core&,depth_used:u32,depth_limit:u32,frame_used:u32,frame_limit:u32)->Output {
 if !valid(source,c){return Output {};}
 if depth_limit>128 || depth_used>depth_limit || c.declared_depth>depth_limit-depth_used {return Output {status:2};}
 if frame_used>frame_limit || c.declared_frame>frame_limit-frame_used {return Output {status:3};}
 let target=short_emit::emit(source,c.program);if target.len==0 || !verify(source,c,target){return Output {};}
 return Output {status:0,wasm:copy(target)};
}
