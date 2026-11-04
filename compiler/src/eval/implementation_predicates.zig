//! An omitted legacy invocation annotation owns a fresh inference row at each
//! use. It is not an additional implementation-head quantifier.
const T = @import("../check/types.zig");
const E = @import("type_evidence.zig");
pub fn failureOutcome(kind: T.ObligationKind) @import("../reuse/dispatch_explanation.zig").Outcome {
    if (kind == .contract) return .requires_evidence;
    if (kind == .effect_operation or kind == .effect_rep or kind == .effect_handler) return .incompatible_effect;
    return .incompatible_type;
}
pub fn primitiveResult(evidence: *const E.Store, operator: T.Operator, left: E.Id, right: E.Id) ?E.Id {
    if (operator == .none or left != right) return null;
    const tag = evidence.node(left).tag;
    if (tag != .u32 and tag != .f32 and tag != .boolean) return null;
    const equality = operator == .equal or operator == .not_equal;
    const comparison = equality or operator == .less or operator == .less_equal or operator == .greater or operator == .greater_equal;
    const integer = operator == .rem or operator == .bit_and or operator == .bit_or or operator == .bit_xor or operator == .shift_left or operator == .shift_right;
    if ((tag == .boolean and !equality) or (tag == .f32 and integer)) return null;
    if (comparison) return T.boolean;
    return left;
}
pub fn inferredCarrier(source: anytype, predicate: T.Obligation, rows: T.List) bool {
    if (predicate.kind != .dispatch and predicate.kind != .receiver and predicate.kind != .update) return false;
    if (predicate.signature == 0) return false;
    const node = source.node(predicate.signature);
    if (node.tag != .function or node.a != T.unit or node.b != T.unit) return false;
    const row = currentRow(source, node.c);
    if (row.labels.len != 0 or row.tail != .variable) return false;
    for (source.list(rows)) |parameter| {
        const declared = currentRow(source, parameter);
        if (declared.tail == .variable and row.tail.variable == declared.tail.variable) return false;
    }
    return true;
}
fn currentRow(source: anytype, id: T.Effects.Id) T.Effects.Row {
    var row = source.row(id);
    if (comptime @hasDecl(@TypeOf(source.effects), "replacementAt")) {
        var at = row.cursor;
        var depth: usize = 0;
        while (row.tail == .variable and row.labels.len == 0 and depth < 256) : (depth += 1) {
            const write = source.effects.replacementAt(row.tail.variable, at) orelse break;
            row = source.row(write.replacement);
            at = write.position + 1;
        }
    }
    return row;
}
