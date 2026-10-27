// Private scalar/finite-loop resource summary; not a portable capability.
namespace leaf_resource_core;
struct Summary {source:u8[]=[],declared_depth:u32=0,declared_frame:u32=0,body_depth:u32=0,body_frame:u32=0,loops:u32=0}
struct Result {status:i64=1,summary:Summary=Summary {}}
struct Admission {status:i64=1,wasm:u8[]=[]}
