// Private source-owned scalar Owned callable, no general ABI authority.
namespace source_owned_core;
import ownership_syntax;
struct Header {ok:bool=false,body:i64=0,owner_start:i64=0,owner_end:i64=0,flag_start:i64=0,flag_end:i64=0,mode:i64=0}
struct Program {source:u8[]=[],head:Header=Header {},tree:ownership_syntax::Tree=ownership_syntax::Tree {}}
struct Result {status:i64=1,program:Program=Program {}}
