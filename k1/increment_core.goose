// Private transient source-bound guarded U32 increment evidence. No artifact
// identity, general proof algebra, callable ABI or source authority is implied.
namespace increment_core;
struct Span { start: i64 = 0, end: i64 = 0 }
struct Term { kind: u32 = 0, value: u32 = 0, version: u32 = 0, literal: u32 = 0 }
// rule 1: true-edge x < MAX; rule 2: AddFits(x,1) by that exact prior.
struct Evidence { rule: u32 = 0, scope: u32 = 0, left: u32 = 0, right: u32 = 0,
                  prior: u32 = 0, result: u32 = 0, result_version: u32 = 0 }
struct Core {
    source: u8[] = [], function: Span = Span {}, parameter: Span = Span {},
    guard_use: Span = Span {}, limit: Span = Span {}, add_use: Span = Span {},
    one: Span = Span {}, else_use: Span = Span {}, schema: u32 = 0,
    parameter_version: u32 = 0, result_version: u32 = 0,
    true_scope: u32 = 0, false_scope: u32 = 0,
    terms: Term[3] = [Term {}; 3], evidence: Evidence[2] = [Evidence {}; 2]
}
fn same_term(a: Term, b: Term) -> bool {
    return a.kind == b.kind && a.value == b.value && a.version == b.version && a.literal == b.literal;
}
fn same_evidence(a: Evidence, b: Evidence) -> bool {
    return a.rule == b.rule && a.scope == b.scope && a.left == b.left && a.right == b.right &&
           a.prior == b.prior && a.result == b.result && a.result_version == b.result_version;
}
