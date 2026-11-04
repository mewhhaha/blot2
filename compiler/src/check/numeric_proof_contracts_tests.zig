const std = @import("std");
const terms = @import("numeric_proof_terms.zig");
const production = @import("numeric_proof_contracts.zig");
const A = std.mem.Allocator;
const Contract = production.Contract;
const Signature = production.Signature;
const Requirement = production.Requirement;
const entails = production.entails;

const numeric: Contract = .{
    .values = &.{ .u32, .u32, .u32 },
    .operands = &.{ .{ .tag = .formal, .a = 0 }, .{ .tag = .formal, .a = 1 }, .{ .tag = .formal, .a = 2 } },
    .requirements = &.{
        .{ .before = 2, .proposition = .{ .relation = .lt, .left = 1, .right = 2 } },
        .{ .before = 3, .proposition = .{ .relation = .le, .left = 2, .right = 3 } },
    },
};
fn contractOwnership(allocator: A) !void {
    const format = @import("../reuse/dependency_format.zig");
    const digest: format.Digest = @splat(1);
    const key: format.Key = .{ .compiler = digest, .settings = digest, .source = digest, .dependencies = digest };
    var bytes = try format.encode(allocator, key, numeric);
    defer allocator.free(bytes);
    var decoded = try format.decode(Contract, allocator, bytes, key);
    defer format.deinit(allocator, &decoded);
    allocator.free(bytes);
    bytes = &.{};
    try decoded.validate(allocator, .{});
}
test "numeric proof contracts own portable scopes and consistency after producer teardown through OOM" {
    try contractOwnership(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, contractOwnership, .{});
}
test "numeric proof contracts reject contradictory paths escaping operands and exhausted work" {
    var contract = numeric;
    contract.result = .{ .relation = .le, .left = 3, .right = 1 };
    try std.testing.expectError(error.ContradictoryProof, contract.validate(std.testing.allocator, .{}));
    contract = numeric;
    contract.requirements = &.{.{ .before = 1, .proposition = .{ .relation = .lt, .left = 1, .right = 2 } }};
    try std.testing.expectError(error.ProofScopeEscape, contract.validate(std.testing.allocator, .{}));
    contract = numeric;
    contract.operands = &.{ .{ .tag = .formal, .a = 0 }, .{ .tag = .formal, .a = 1 }, .{ .tag = .version, .a = 9, .b = 7 } };
    try std.testing.expectError(error.ProofScopeEscape, contract.validate(std.testing.allocator, .{}));
    try std.testing.expectError(error.ProofAnalysisLimit, numeric.validate(std.testing.allocator, .{ .visits = 8 }));
}
test "numeric proof contracts retain exact collections and reject wrapping arithmetic claims" {
    var contract: Contract = .{
        .values = &.{ .array, .array, .u32 },
        .operands = &.{ .{ .tag = .formal, .kind = .array, .a = 0 }, .{ .tag = .formal, .kind = .array, .a = 1 }, .{ .tag = .formal, .a = 2 }, .{ .tag = .length, .a = 2 } },
        .requirements = &.{.{ .before = 3, .proposition = .{ .relation = .index, .left = 1, .right = 3 } }},
        .result = .{ .relation = .le, .left = 4, .right = 3 },
    };
    try contract.validate(std.testing.allocator, .{});
    contract.operands = &.{ .{ .tag = .formal, .kind = .array, .a = 0 }, .{ .tag = .formal, .kind = .array, .a = 0 }, .{ .tag = .formal, .a = 2 }, .{ .tag = .length, .a = 2 } };
    try std.testing.expectError(error.ContradictoryProof, contract.validate(std.testing.allocator, .{}));
    contract = .{ .values = &.{}, .operands = &.{ .{ .tag = .literal, .a = std.math.maxInt(u32) }, .{ .tag = .literal, .a = 1 } }, .requirements = &.{}, .result = .{ .relation = .add_fits, .left = 1, .right = 2 } };
    try std.testing.expectError(error.ContradictoryProof, contract.validate(std.testing.allocator, .{}));
    contract.result = .{ .relation = .sub_fits, .left = 2, .right = 1 };
    try std.testing.expectError(error.ContradictoryProof, contract.validate(std.testing.allocator, .{}));
}

fn boundedChain(allocator: A) !void {
    const kinds: [257]terms.Kind = @splat(.u32);
    var operands: [257]terms.Term = undefined;
    var requirements: [256]Requirement = undefined;
    for (&operands, 0..) |*operand, index| operand.* = .{ .tag = .formal, .a = @intCast(index) };
    for (&requirements, 0..) |*requirement, index| requirement.* = .{ .before = @intCast(index + 2), .proposition = .{ .relation = .le, .left = @intCast(index + 1), .right = @intCast(index + 2) } };
    var contract: Contract = .{ .values = &kinds, .operands = &operands, .requirements = &requirements };
    const measured = try contract.validateMeasured(allocator, .{});
    try std.testing.expectEqual(@as(usize, 259), measured.terms);
    try std.testing.expect(measured.edges < 800);
    try std.testing.expect(measured.visits < 5000);
    // A non-strict cycle is consistent; adding one strict reverse edge is not.
    contract.result = .{ .relation = .le, .left = 257, .right = 1 };
    try contract.validate(allocator, .{});
    contract.result = .{ .relation = .lt, .left = 257, .right = 1 };
    const result = contract.validate(allocator, .{});
    if (result) |_| return error.TestUnexpectedResult else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.ContradictoryProof, err);
    }
}
test "numeric proof contracts check maximum requirement chains with linear work through OOM" {
    try boundedChain(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, boundedChain, .{});
}

test "numeric proof calls share consistency work across repeated instantiations" {
    const allocator = std.testing.allocator;
    const kinds: [257]terms.Kind = @splat(.u32);
    var operands: [257]terms.Term = undefined;
    var value_slots: [257]u32 = undefined;
    var proof_slots: [256]u32 = undefined;
    var requirements: [256]Requirement = undefined;
    var arguments: [257]terms.Id = undefined;
    var target: terms.Store = .{ .limits = .{ .visits = 10_000 } };
    defer target.deinit(allocator);
    for (&operands, &value_slots, &arguments, 0..) |*operand, *slot, *argument, index| {
        slot.* = @intCast(index);
        operand.* = .{ .tag = .formal, .a = @intCast(index) };
        argument.* = try target.intern(allocator, .{ .tag = .version, .a = @intCast(index + 1), .b = 1 });
    }
    for (&requirements, &proof_slots, 0..) |*requirement, *slot, index| {
        slot.* = @intCast(257 + index);
        requirement.* = .{ .before = 257, .proposition = .{ .relation = .le, .left = @intCast(index + 1), .right = @intCast(index + 2) } };
    }
    const signature: Signature = .{ .arity = 513, .value_slots = &value_slots, .proof_slots = &proof_slots, .contract = .{ .values = &kinds, .operands = &operands, .requirements = &requirements } };
    _ = try signature.instantiateRequirement(allocator, &target, 257, &arguments);
    try std.testing.expect(target.visits > 5_000);
    try std.testing.expectError(error.ProofAnalysisLimit, signature.instantiateRequirement(allocator, &target, 257, &arguments));
    try std.testing.expectEqual(@as(usize, 257), target.terms.items.len);
}

fn substitutedComparison(allocator: A, left: u32, right: u32, relation: terms.Relation) !void {
    const operands = [_]terms.Term{
        .{ .tag = .formal, .a = 0 },     .{ .tag = .formal, .a = 1 },
        .{ .tag = .literal, .a = left }, .{ .tag = .literal, .a = right },
    };
    const required = [_]Requirement{
        .{ .before = 2, .proposition = .{ .relation = .eq, .left = 1, .right = 3 } },
        .{ .before = 2, .proposition = .{ .relation = .eq, .left = 2, .right = 4 } },
    };
    const contract: Contract = .{ .values = &.{ .u32, .u32 }, .operands = &operands, .requirements = &required, .result = .{ .relation = relation, .left = 1, .right = 2 } };
    const result = contract.validate(allocator, .{});
    if (result) |_| {
        try std.testing.expect(terms.holds(relation, left, right));
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expect(!terms.holds(relation, left, right));
        try std.testing.expectEqual(error.ContradictoryProof, err);
    }
}
fn substitutedComplements(allocator: A) !void {
    try substitutedComparison(allocator, 1, std.math.maxInt(u32) - 1, .add_fits);
    try substitutedComparison(allocator, 1, std.math.maxInt(u32), .add_fits);
}
test "numeric proof contracts substitute unsigned boundary equalities into fit complements through OOM" {
    const maximum = std.math.maxInt(u32);
    for ([_]u32{ 0, 1, maximum - 1, maximum }) |left| {
        for ([_]u32{ 0, 1, maximum - 1, maximum }) |right| {
            for ([_]terms.Relation{ .eq, .lt, .le, .add_fits, .sub_fits }) |relation| try substitutedComparison(std.testing.allocator, left, right, relation);
        }
    }
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, substitutedComplements, .{});
}

fn finiteEntailment(allocator: A) !void {
    var store: terms.Store = .{};
    defer store.deinit(allocator);
    const first = try store.intern(allocator, .{ .tag = .version, .a = 1, .b = 1 });
    const second = try store.intern(allocator, .{ .tag = .version, .a = 2, .b = 1 });
    const third = try store.intern(allocator, .{ .tag = .version, .a = 3, .b = 1 });
    const next_first = try store.intern(allocator, .{ .tag = .version, .a = 1, .b = 2 });
    const collection = try store.intern(allocator, .{ .tag = .version, .kind = .array, .a = 4, .b = 1 });
    const other = try store.intern(allocator, .{ .tag = .version, .kind = .array, .a = 5, .b = 1 });
    const length = try store.intern(allocator, .{ .tag = .length, .a = collection });
    const facts = [_]terms.Proposition{
        .{ .relation = .lt, .left = first, .right = second },
        .{ .relation = .le, .left = second, .right = third },
    };
    try std.testing.expect(try entails(allocator, &store, &facts, .{ .relation = .lt, .left = first, .right = third }));
    try std.testing.expect(try entails(allocator, &store, &facts, .{ .relation = .sub_fits, .left = third, .right = first }));
    try std.testing.expect(!try entails(allocator, &store, &facts, .{ .relation = .lt, .left = next_first, .right = third }));
    try std.testing.expect(!try entails(allocator, &store, &facts, .{ .relation = .lt, .left = third, .right = first }));
    const index: terms.Proposition = .{ .relation = .index, .left = collection, .right = first };
    const bounded: terms.Proposition = .{ .relation = .lt, .left = first, .right = length };
    try std.testing.expect(try entails(allocator, &store, &.{index}, bounded));
    try std.testing.expect(try entails(allocator, &store, &.{bounded}, index));
    try std.testing.expect(!try entails(allocator, &store, &.{bounded}, .{ .relation = .index, .left = other, .right = first }));
    const maximum = try store.intern(allocator, .{ .tag = .literal, .a = std.math.maxInt(u32) });
    const zero = try store.intern(allocator, .{ .tag = .literal, .a = 0 });
    const one = try store.intern(allocator, .{ .tag = .literal, .a = 1 });
    try std.testing.expect(try entails(allocator, &store, &.{}, .{ .relation = .add_fits, .left = zero, .right = first }));
    try std.testing.expect(!try entails(allocator, &store, &.{}, .{ .relation = .add_fits, .left = maximum, .right = one }));
    const contrary = facts ++ [_]terms.Proposition{.{ .relation = .le, .left = third, .right = first }};
    if (entails(allocator, &store, &contrary, .{ .relation = .le, .left = first, .right = maximum })) |_| {
        return error.TestUnexpectedResult;
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.ContradictoryProof, err);
    }
}
test "numeric proof finite entailment keeps strict paths versions collection identities and unsigned fit through OOM" {
    try finiteEntailment(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, finiteEntailment, .{});
    var store: terms.Store = .{ .limits = .{ .visits = 8 } };
    defer store.deinit(std.testing.allocator);
    const value = try store.intern(std.testing.allocator, .{ .tag = .version, .a = 1, .b = 1 });
    try std.testing.expectError(error.ProofAnalysisLimit, entails(std.testing.allocator, &store, &.{}, .{ .relation = .le, .left = value, .right = value }));
}
