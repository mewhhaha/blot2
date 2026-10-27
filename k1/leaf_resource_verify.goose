// Independently source-replay this closed scalar/loop arena and its entire
// target. The only operations in this subset are local scalars, finite loops
// and compiler intrinsics; no aggregates, user calls, captures or K1 frame IO.
namespace leaf_resource_verify;
import typed_canonical_core;
import typed_canonical_check;
import typed_canonical_target;
import leaf_resource_core;
fn verify(source:u8[:],p:typed_canonical_core::Program&,target:u8[:],s:leaf_resource_core::Summary&)->bool {
 if s.source[..]!=source || !typed_canonical_check::verify(source,p) || !typed_canonical_target::verify(source,p,target){return false;}
 if s.declared_depth!=p.head.depth || s.declared_frame!=p.head.frame || s.body_depth!=1 || s.body_frame!=0 || s.declared_depth<1 || s.declared_depth>128{return false;}
 if p.binding_types.len!=p.tree.bindings.len || p.types.len!=p.tree.nodes.len{return false;}
 for t in p.binding_types {if t!=1 && t!=2{return false;}}
 var loops:u32=0;
 for n,i in p.tree.nodes {
  if n.tag==15 {loops+=1;}
  if n.tag!=1 && n.tag!=2 && n.tag!=3 && n.tag!=4 && n.tag!=6 && n.tag!=9 && n.tag!=10 && n.tag!=11 && n.tag!=12 && n.tag!=13 && n.tag!=14 && n.tag!=15 && n.tag!=16 && n.tag!=17 && n.tag!=18 && n.tag!=19 && n.tag!=20 && n.tag!=21 && n.tag!=22{return false;}
  let ty=p.types[i];if ty<1 || ty>4{return false;}
 }
 return loops==s.loops && loops<=128;
}
fn public_eligible(source:u8[:],p:typed_canonical_core::Program&,target:u8[:],s:leaf_resource_core::Summary&)->bool {let _=source;let _=p;let _=target;let _=s;return false;}
