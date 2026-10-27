// Private Bool -> U32 declaration and source-bound flow Core.
namespace generic_bool_core;
import generic_fn_core;
import flow_decl;
struct Program {source:u8[]=[],head:generic_fn_core::Header=generic_fn_core::Header {},body:flow_decl::Declaration=flow_decl::Declaration {}}
struct Result {status:i64=0,program:Program=Program {}}
