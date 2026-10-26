// Private source-bound U32/Bool control subset. The complete K1 type, proof,
// lexical-scope and work policies are not represented by these records.
namespace unified_core;
// Node tags: binding reference 1, U32 literal 2, checked add 3, explicit
// wrapping add/sub/mul 4..6, U32 and 7, group 8, unsigned less-than 9,
// #True/#False 10/11, &&/|| 12/13, let 14, return 15, if 16, sequence 17.
// Child IDs are one-based postorder. A binding reference's a is a binding
// index: 0 parameter, k>0 bindings[k-1]. A let has a=initializer and b=its
// binding index. Node types: 1 U32, 2 Bool, 3 statement. Other unused fields
// must be zero. Spans are half-open source bytes.
struct Node { tag:i64=0, start:i64=0, end:i64=0, a:i64=0, b:i64=0, c:i64=0, literal:u32=0, ty:i64=0 }
struct Binding { start:i64=0, end:i64=0 }
struct Program { source:u8[] = [], name_start:i64=0, name_end:i64=0, param_start:i64=0, param_end:i64=0,
                 nodes:Node[] = [], bindings:Binding[] = [], root:i64=0 }
struct Result { status:i64=0, program:Program = Program {} }
