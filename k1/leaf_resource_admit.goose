// Caller-supplied limits are only comparison inputs, not runtime authority.
// Failure never publishes target bytes. Depth exhaustion has priority.
namespace leaf_resource_admit;
import typed_canonical_core;
import leaf_resource_core;
import leaf_resource_verify;
fn admit(source:u8[:],p:typed_canonical_core::Program&,target:u8[:],s:leaf_resource_core::Summary&,depth_used:u32,depth_limit:u32,frame_used:u32,frame_limit:u32)->leaf_resource_core::Admission {
 if !leaf_resource_verify::verify(source,p,target,s){return leaf_resource_core::Admission {};}
 if depth_limit>128 || depth_used>depth_limit || s.declared_depth>depth_limit-depth_used{return leaf_resource_core::Admission {status:2};}
 if frame_used>frame_limit || s.declared_frame>frame_limit-frame_used{return leaf_resource_core::Admission {status:3};}
 var bytes:u8[>..]=[];bytes.append(target);return leaf_resource_core::Admission {status:0,wasm:copy(bytes)};
}
