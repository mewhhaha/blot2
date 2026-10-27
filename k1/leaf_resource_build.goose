namespace leaf_resource_build;
import typed_canonical_core;
import typed_canonical_check;
import typed_canonical_target;
import leaf_resource_core;
import leaf_resource_verify;
fn build(source:u8[:],p:typed_canonical_core::Program&,target:u8[:])->leaf_resource_core::Result {
 if !typed_canonical_check::verify(source,p) || !typed_canonical_target::verify(source,p,target){return leaf_resource_core::Result {};}
 var loops:u32=0;for n in p.tree.nodes {if n.tag==15 {loops+=1;}}
 var s=leaf_resource_core::Summary {source:source,declared_depth:p.head.depth,declared_frame:p.head.frame,body_depth:1,body_frame:0,loops:loops};
 if !leaf_resource_verify::verify(source,p,target,s){return leaf_resource_core::Result {};}
 return leaf_resource_core::Result {status:0,summary:s};
}
