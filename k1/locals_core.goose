// Private candidate records for one narrow U32 -> U32 source fixture.
// One-based value IDs are postorder; binding 0 is the parameter, binding k>0
// is bindings[k-1]. Proof or source authority is never carried by these IDs.
namespace locals_core;
// kind 1 binding reference (a=binding index), 2 U32 literal, 3 ordinary
// checked add, 4/5/6 explicit wrapping add/sub/mul, 7 total bitwise AND,
// 8 transparent parenthesized value (a is child and b is zero).
// Value spans are half-open source bytes. A nonliteral has literal=0; only
// kinds 3..7 use b. Prefix operations cover their full source spelling.
struct Value { kind: i64 = 0, start: i64 = 0, end: i64 = 0, a: i64 = 0, b: i64 = 0, literal: u32 = 0 }
struct Binding { start: i64 = 0, end: i64 = 0, value: i64 = 0 }
// Values in each binding initializer precede the binding; the binding cannot
// refer to itself. `cond_a==0` means direct return `yes` and all of cond_b/no
// are zero. Otherwise condition is `cond_a < cond_b`, and `yes`/`no` are the
// explicit return values in the true/false paths. No branch-local lets yet.
struct Program {
    source: u8[] = [], name_start: i64 = 0, name_end: i64 = 0,
    param_start: i64 = 0, param_end: i64 = 0,
    values: Value[] = [], bindings: Binding[] = [],
    cond_a: i64 = 0, cond_b: i64 = 0, yes: i64 = 0, no: i64 = 0
}
struct Result { status: i64 = 0, program: Program = Program {} }
