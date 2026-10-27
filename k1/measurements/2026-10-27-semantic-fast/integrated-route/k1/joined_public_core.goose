// A private public-shaped declaration candidate. No public eligibility.
namespace joined_public_core;
import compiler_core;
struct Header {ok:bool=false,let_start:i64=0,effect_start:i64=0,resources_end:i64=0,depth:u32=0,frame:u32=0}
struct Program {source:u8[]=[],head:Header=Header {},body:compiler_core::Program=compiler_core::Program {}}
struct Result {status:i64=0,program:Program=Program {}}
