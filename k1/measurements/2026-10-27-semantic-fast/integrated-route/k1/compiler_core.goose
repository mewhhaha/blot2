// Scratch source-bound U32 finite-loop candidate. Not a K1 artifact, host
// bridge, optimizer, metered proof, or general language admission.
namespace compiler_core;
import iteration_core;
import unified_core;
import mixed_compiler_core;
// Variant 1 is the checked unified scalar path, 2 is the exact-source
// iteration path, and 3 is the bounded mixed scalar/loop path. Inactive
// variants must be entirely empty.
struct Program {source:u8[]=[],variant:i64=0,scalar:unified_core::Program=unified_core::Program {},
    name_start:i64=0,name_end:i64=0,fn_start:i64=0,body:iteration_core::Tree=iteration_core::Tree {},
    mixed:mixed_compiler_core::Program=mixed_compiler_core::Program {}}
struct Result {status:i64=0,program:Program=Program {}}
