// Private original-source signature wrapper; not public interface authority.
namespace common_decl_core;
import unified_core;
struct Header {ok:bool=false,let_start:i64=0,type_start:i64=0,type_end:i64=0,effect_start:i64=0,resources_end:i64=0,argument:i64=0,result:i64=0,depth:u32=0,frame:u32=0,form:i64=0}
struct Program {source:u8[]=[],header:Header=Header {},body:unified_core::Program=unified_core::Program {}}
struct Result {status:i64=0,program:Program=Program {}}
