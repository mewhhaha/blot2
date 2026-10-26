// Scratch source-bound U32 finite-loop candidate. Not a K1 artifact, host
// bridge, optimizer, metered proof, or general language admission.
namespace compiler_core;
import iteration_core;
import unified_core;
// Variant 1 is the existing checked unified scalar path, 2 is the new
// exact-source iteration path. An inactive variant must be entirely empty.
struct Program {source:u8[]=[],variant:i64=0,scalar:unified_core::Program=unified_core::Program {},
    name_start:i64=0,name_end:i64=0,fn_start:i64=0,body:iteration_core::Tree=iteration_core::Tree {}}
struct Result {status:i64=0,program:Program=Program {}}
