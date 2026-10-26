// Owned, fixed-size private control fixture. No source or solver pointer survives.
namespace control_core;

// Atom tags: 1 parameter, 2 #True, 3 #False. op: 0 atom, 1 &&, 2 ||.
struct Program {
    name_start: i64 = 0, name_end: i64 = 0,
    param_start: i64 = 0, param_end: i64 = 0,
    function_start: i64 = 0, function_end: i64 = 0,
    if_start: i64 = 0, if_end: i64 = 0,
    left_start: i64 = 0, left_end: i64 = 0, left_kind: i64 = 0,
    op_start: i64 = 0, op_end: i64 = 0, op: i64 = 0,
    right_start: i64 = 0, right_end: i64 = 0, right_kind: i64 = 0,
    yes_start: i64 = 0, yes_end: i64 = 0, yes: u32 = 0,
    no_start: i64 = 0, no_end: i64 = 0, no: u32 = 0,
    yes_return_start: i64 = 0, yes_return_end: i64 = 0,
    no_return_start: i64 = 0, no_return_end: i64 = 0,
    // One-based local structural function target. Both explicit returns
    // target the same innermost function in this single-function subset.
    yes_target: i64 = 0, no_target: i64 = 0
}
struct Result { status: i64 = 0, start: i64 = 0, end: i64 = 0, program: Program = Program {} }

fn span(start: i64, end: i64, limit: i64) -> bool { return start >= 0 && end > start && end <= limit; }
// Source spelling, lexical targets, identifier equality and literal bytes need
// the independent validator; this only checks closed shape before indexing.
fn shape(p: Program, source_len: i64) -> bool {
    if source_len < 0 || source_len > 16777216 ||
       !span(p.name_start,p.name_end,source_len) || !span(p.param_start,p.param_end,source_len) ||
       !span(p.function_start,p.function_end,source_len) || !span(p.if_start,p.if_end,source_len) ||
       !span(p.left_start,p.left_end,source_len) || !span(p.yes_start,p.yes_end,source_len) ||
       !span(p.no_start,p.no_end,source_len) || !span(p.yes_return_start,p.yes_return_end,source_len) ||
       !span(p.no_return_start,p.no_return_end,source_len) || p.yes_target != 1 || p.no_target != 1 ||
       p.left_kind < 1 || p.left_kind > 3 ||
       p.op < 0 || p.op > 2 { return false; }
    if p.name_end > p.function_start || p.function_end > p.param_start || p.param_end > p.if_start ||
       p.if_end > p.left_start || p.left_end > p.yes_return_start || p.yes_return_end > p.yes_start ||
       p.yes_end > p.no_return_start || p.no_return_end > p.no_start { return false; }
    if p.op == 0 { return p.op_start == 0 && p.op_end == 0 && p.right_start == 0 && p.right_end == 0 && p.right_kind == 0; }
    return span(p.op_start,p.op_end,source_len) && span(p.right_start,p.right_end,source_len) &&
        p.right_kind >= 1 && p.right_kind <= 3 && p.left_end <= p.op_start && p.op_end <= p.right_start && p.right_end <= p.yes_start;
}
