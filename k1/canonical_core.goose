// Private canonical source-owned scalar/finite-loop arena; no public ABI.
namespace canonical_core;
import joined_public_core;
import mixed_core;
struct Program {source:u8[]=[],head:joined_public_core::Header=joined_public_core::Header {},name_start:i64=0,name_end:i64=0,fn_start:i64=0,tree:mixed_core::Tree=mixed_core::Tree {},types:u8[]=[]}
struct Result {status:i64=0,program:Program=Program {}}
