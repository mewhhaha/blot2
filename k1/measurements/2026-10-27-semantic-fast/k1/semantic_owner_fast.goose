// Private experimental fused owner emission. A trusted job must keep the
// source, identity, owner and capacities immutable and nonconcurrently owned
// through this call. No C09 receipt or warm-cache authority is established.
namespace semantic_owner_fast;
import semantic_owner;
import semantic_leaf;
import short_emit;
fn emit(package:u8[:],module:u8[:],name:u8[:],source:u8[:],o:semantic_owner::Owner&,depth_used:u32,depth_limit:u32,frame_used:u32,frame_limit:u32)->semantic_leaf::Output {
 // This retains the complete source/identity/contract consumer check before
 // reading the declared bounds. `short_emit` independently rechecks source
 // and Core, then decodes the entire target with `short_target::verify`.
 if !semantic_owner::valid(package,module,name,source,o){return semantic_leaf::Output {};}
 let c=o.core;
 if depth_limit>128 || depth_used>depth_limit || c.declared_depth>depth_limit-depth_used {return semantic_leaf::Output {status:2};}
 if frame_used>frame_limit || c.declared_frame>frame_limit-frame_used {return semantic_leaf::Output {status:3};}
 let bytes=short_emit::emit(source,o.core.program);if bytes.len==0{return semantic_leaf::Output {};}
 return semantic_leaf::Output {status:0,wasm:copy(bytes)};
}
