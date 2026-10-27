// Private canonical source-owned scalar/finite-loop arena; no public ABI.
namespace poly_canonical_core;
import common_decl_core;
import mixed_core;
struct Program {source:u8[]=[],head:common_decl_core::Header=common_decl_core::Header {},name_start:i64=0,name_end:i64=0,fn_start:i64=0,tree:mixed_core::Tree=mixed_core::Tree {},types:u8[]=[],binding_types:u8[]=[]}
struct Result {status:i64=0,program:Program=Program {}}
