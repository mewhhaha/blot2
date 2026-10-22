const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("check.zig");
const A = std.mem.Allocator;

fn checkedSource(allocator: A, text: []const u8) !check.Checked {
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    return check.check(allocator, &tree, &pool);
}
fn sourceLaw(allocator: A, text: []const u8, expected: ?check.Code) !void {
    var checked = try checkedSource(allocator, text);
    defer checked.deinit(allocator);
    if (expected) |code| {
        for (checked.diagnostics) |diagnostic| if (diagnostic.code == code) return;
        for (checked.diagnostics) |diagnostic| std.debug.print("unexpected {s}\n", .{@tagName(diagnostic.code)});
        return error.ExpectedProofDiagnostic;
    }
    for (checked.diagnostics) |diagnostic| std.debug.print("unexpected {s} at {}\n", .{ @tagName(diagnostic.code), diagnostic.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 1), checked.proof_contracts.len);
    const contract = checked.proof_contracts[0];
    try std.testing.expect(contract.binding != 0);
    try contract.header.signature().validate(allocator, .{});
    try std.testing.expectEqualSlices(u32, &.{0}, contract.header.value_slots);
    try std.testing.expectEqualSlices(u32, &.{1}, contract.header.proof_slots);
}

fn declaredProofLaw(allocator: A) !void {
    try sourceLaw(allocator, "const f: (x: U32) -> (@proof.U32Le 0 x) -> U32 = fn x => fn proof => x", null);
}
test "numeric proof checking owns resolved public header contracts through OOM" {
    try declaredProofLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, declaredProofLaw, .{});
}

test "numeric proof checking rejects contradictions hidden kinds and unavailable operands" {
    try sourceLaw(std.testing.allocator, "const f: (x: U32) -> (@proof.U32Lt x x) -> U32 = fn x => fn proof => x", .contradictory_proof);
    try sourceLaw(std.testing.allocator, "const f: (@proof.U32Le 0 later) -> (later: U32) -> U32 = fn proof => fn later => later", .proof_scope_escape);
    try sourceLaw(std.testing.allocator, "const f: (x: Bool) -> (@proof.U32Eq x 0) -> U32 = fn x => fn proof => 0", .invalid_proof_operand);
    try sourceLaw(std.testing.allocator, "const f: (Bool, @proof.U32Eq 0 0) -> U32 = fn packed => 0", .proof_runtime_use);
}

fn runtimeProofLaw(allocator: A) !void {
    const header = "const f: (x: U32) -> (@proof.U32Le 0 x) -> U32 = fn x => fn proof => ";
    try sourceLaw(allocator, "const identity = fn value => value\n" ++ header ++ "identity proof", .proof_runtime_use);
    try sourceLaw(allocator, header ++ "do:\n  let stored = (proof, x)\n  break x", .proof_runtime_use);
    try sourceLaw(allocator, header ++ "do:\n  let stored = #[proof]\n  break x", .proof_runtime_use);
    try sourceLaw(allocator, header ++ "do:\n  let stored = {value: proof}\n  break x", .proof_runtime_use);
}
test "numeric proof checking rejects data polymorphism and aggregate storage through OOM" {
    try runtimeProofLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, runtimeProofLaw, .{});
}

fn introductions(allocator: A) !void {
    const text =
        \\const inspect = fn (values: Array U32) => fn (other: Array U32) => fn (index: U32) => fn (right: U32) => do:
        \\  let alias = values
        \\  let first = @proof.index values index
        \\  let same = @proof.index alias index
        \\  let separate = @proof.index other index
        \\  let old_index = index
        \\  index := @u32.add self 1
        \\  let rebound = @proof.index values index
        \\  let original = @proof.index values old_index
        \\  let length = @proof.lt index (@array.length values)
        \\  let impossible = @proof.lt 1 0
        \\  let equality = @proof.eq index right
        \\  let weak = @proof.le index right
        \\  let addition = @proof.add_fits index right
        \\  let subtraction = @proof.sub_fits index right
        \\  let copy = first
        \\  break 0
    ;
    var checked = try checkedSource(allocator, text);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("unexpected introduction {s} at {}\n", .{ @tagName(diagnostic.code), diagnostic.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const body = checked.proof_bodies;
    try std.testing.expectEqual(@as(usize, 11), body.introductions.len);
    const values: @import("numeric_proof_terms.zig").View = .{ .terms = body.operands };
    try values.validate(.{ .formals = &.{}, .local_versions = true }, .{});
    const proofs = body.introductions;
    try std.testing.expectEqualDeep(proofs[0].proposition, proofs[1].proposition);
    try std.testing.expect(proofs[0].proposition.left != proofs[2].proposition.left);
    try std.testing.expect(proofs[0].proposition.right != proofs[3].proposition.right);
    try std.testing.expectEqualDeep(proofs[0].proposition, proofs[4].proposition);
    const length = try values.get(proofs[5].proposition.right);
    try std.testing.expectEqual(@import("numeric_proof_terms.zig").Tag.length, length.tag);
    try std.testing.expectEqual(proofs[0].proposition.left, length.a);
    const false_proof = proofs[6].proposition;
    try std.testing.expect(!@import("numeric_proof_terms.zig").holds(false_proof.relation, (try values.get(false_proof.left)).a, (try values.get(false_proof.right)).a));
    for (proofs) |proof| {
        try std.testing.expect(proof.owner != 0);
        try std.testing.expect(proof.arguments[0] < proof.arguments[1]);
        try std.testing.expect(proof.arguments[1] < proof.source);
    }
}
test "numeric proof introductions retain exact aliases versions lengths and false guards through OOM" {
    try introductions(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, introductions, .{});
}

test "numeric proof introductions reject invalid operands arity storage and inferred results" {
    try sourceLaw(std.testing.allocator, "const f = fn (x: U32) => @proof.le 0 x", .proof_scope_escape);
    try sourceLaw(std.testing.allocator, "const f = fn (x: U32) => do:\n  let invalid = @proof.eq #True x\n  break x", .invalid_proof_operand);
    try sourceLaw(std.testing.allocator, "const f = fn (x: U32) => do:\n  let invalid = @proof.index x 0\n  break x", .invalid_proof_operand);
    try sourceLaw(std.testing.allocator, "const f = fn (x: U32) => do:\n  let invalid = @proof.le x\n  break x", .call_arity);
    try sourceLaw(std.testing.allocator, "const f = fn (x: U32) => do:\n  let invalid = @proof.le 0 x x\n  break x", .call_arity);
    try sourceLaw(std.testing.allocator, "const f = fn (x: U32) => do:\n  let invalid = #[@proof.le 0 x]\n  break x", .proof_runtime_use);
}

const at_source = "const at: (values: Array U32) -> (index: U32) -> (@proof.Index values index) -> U32 = fn values => fn index => fn proof => @array.get values index\n";
fn exactProofCalls(allocator: A) !void {
    var checked = try checkedSource(allocator, at_source ++
        \\const forward: (values: Array U32) -> (index: U32) -> (@proof.Index values index) -> U32 = fn values => fn index => fn proof => do:
        \\  let valid = proof
        \\  break do:
        \\    break at values index valid
        \\const inspect = fn (values: Array U32) => fn (index: U32) => do:
        \\  let alias = values
        \\  let valid = @proof.index alias index
        \\  break do:
        \\    let witness = valid
        \\    break forward values index witness
    );
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("unexpected proof call {s} at {}\n", .{ @tagName(diagnostic.code), diagnostic.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 2), checked.proof_contracts.len);
    try std.testing.expectEqual(@as(usize, 2), checked.proof_bodies.parameters.len);
    try std.testing.expectEqual(@as(usize, 1), checked.proof_bodies.introductions.len);
    try std.testing.expectEqual(@as(usize, 2), checked.proof_bodies.uses.len);
    try std.testing.expectEqualDeep(checked.proof_bodies.parameters[1].proposition, checked.proof_bodies.uses[0].proposition);
    try std.testing.expectEqualDeep(checked.proof_bodies.introductions[0].proposition, checked.proof_bodies.uses[1].proposition);
}
test "numeric proof calls substitute exact public operands and preserve witness aliases through OOM" {
    try exactProofCalls(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, exactProofCalls, .{});
}
test "numeric proof calls reject other collections rebound indexes mismatched facts and Unit" {
    const caller = at_source ++ "const inspect = fn (values: Array U32) => fn (other: Array U32) => fn (index: U32) => do:\n  let valid = @proof.index values index\n";
    try sourceLaw(std.testing.allocator, caller ++ "  break at other index valid", .proof_mismatch);
    try sourceLaw(std.testing.allocator, caller ++ "  index := @u32.add self 1\n  break at values index valid", .proof_mismatch);
    try sourceLaw(std.testing.allocator, caller ++ "  let different = @proof.le 0 index\n  break at values index different", .proof_mismatch);
    try sourceLaw(std.testing.allocator, caller ++ "  break at values index ()", .proof_mismatch);
    try sourceLaw(std.testing.allocator, caller ++ "  let closure = fn () => at values index valid\n  break 0", .proof_scope_escape);
    try sourceLaw(std.testing.allocator, caller ++ "  let closure = fn () => do:\n    let alias = valid\n    break 0\n  break 0", .proof_scope_escape);
    try sourceLaw(std.testing.allocator, at_source ++ "const forged: (values: Array U32) -> (index: U32) -> (@proof.U32Eq index 0) -> U32 = at", .proof_runtime_use);
    try sourceLaw(std.testing.allocator, at_source ++ "const forged: (values: Array U32) -> (index: U32) -> (@proof.U32Eq index 0) -> U32 = fn values => at values", .proof_runtime_use);
}

fn publicProofResults(allocator: A) !void {
    const text =
        \\const index: (values: Array U32) -> (at: U32) -> @proof.Index values at = fn values => fn at => @proof.index values at
        \\const forward: (values: Array U32) -> (at: U32) -> (@proof.Index values at) -> @proof.Index values at = fn values => fn at => fn proof => do:
        \\  let alias = proof
        \\  break do:
        \\    break alias
        \\const at: (values: Array U32) -> (index: U32) -> (@proof.Index values index) -> U32 = fn values => fn index => fn proof => @array.get values index
        \\const lookup = fn (values: Array U32) => fn (i: U32) => do:
        \\  let valid = index values i
        \\  break at values i (forward values i valid)
    ;
    var checked = try checkedSource(allocator, text);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("public proof result {s} at {}\n", .{ @tagName(diagnostic.code), diagnostic.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 3), checked.proof_contracts.len);
}
test "numeric proof public results bind complete recipes through aliases calls and nested returns through OOM" {
    try publicProofResults(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, publicProofResults, .{});
}
test "numeric proof public results reject changed local operands and a different proposition" {
    try sourceLaw(std.testing.allocator, "const f: (x: U32) -> @proof.U32Le x 0 = fn x => @proof.le x 1", .proof_mismatch);
    try sourceLaw(std.testing.allocator, "const f: (x: U32) -> @proof.U32Lt x 10 = fn x => do:\n  x := @u32.add self 1\n  break @proof.lt x 10", .proof_mismatch);
}
