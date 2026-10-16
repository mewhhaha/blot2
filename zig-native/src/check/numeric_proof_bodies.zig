//! Source-checked introductions own exact operands. Lowering must preserve the
//! recorded guard and evaluation order before these descriptions grant authority.
const std = @import("std");
const terms = @import("numeric_proof_terms.zig");
const A = std.mem.Allocator;
pub const Introduction = struct {
    source: u32,
    owner: u32,
    arguments: [2]u32,
    proposition: terms.Proposition,
};
pub const Parameter = struct { binding: u32, contract: u32, proposition: terms.Proposition };
pub const Use = struct { source: u32, callee: u32, witness: u32, proposition: terms.Proposition };
pub const Frontier = struct { headers: u32, terms: u32, introductions: u32, parameters: u32, uses: u32, aliases: u32, expressions: u32 };
pub const Debit = struct { binding: u32, visits: u32, frontier: Frontier, output: Frontier };
pub const Owned = struct {
    debits: []const Debit = &.{},
    operands: []const terms.Term = &.{},
    introductions: []const Introduction = &.{},
    parameters: []const Parameter = &.{},
    uses: []const Use = &.{},
    pub fn deinit(self: *Owned, allocator: A) void {
        allocator.free(self.debits);
        allocator.free(self.operands);
        allocator.free(self.introductions);
        allocator.free(self.parameters);
        allocator.free(self.uses);
        self.* = undefined;
    }
};
pub const Builder = struct {
    values: terms.Store = .{},
    debits: std.ArrayList(Debit) = .empty,
    // Lexical aliases are checked bindings, never spelling-based identities.
    sources: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    introductions: std.ArrayList(Introduction) = .empty,
    expressions: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    parameters: std.ArrayList(Parameter) = .empty,
    uses: std.ArrayList(Use) = .empty,
    pub fn deinit(self: *Builder, allocator: A) void {
        self.values.deinit(allocator);
        self.debits.deinit(allocator);
        self.sources.deinit(allocator);
        self.introductions.deinit(allocator);
        self.expressions.deinit(allocator);
        self.parameters.deinit(allocator);
        self.uses.deinit(allocator);
    }
    pub fn introduce(self: *Builder, allocator: A, value: Introduction) terms.Error!void {
        try self.values.charge(1);
        try self.values.view().proposition(value.proposition);
        if (self.introductions.items.len >= self.values.limits.terms) return error.ProofAnalysisLimit;
        const slot = try self.expressions.getOrPut(allocator, value.source);
        if (slot.found_existing) {
            if (!std.meta.eql(self.introductions.items[slot.value_ptr.*], value)) return error.InvalidProofOperand;
            return;
        }
        errdefer std.debug.assert(self.expressions.remove(value.source));
        slot.value_ptr.* = @intCast(self.introductions.items.len);
        try self.introductions.append(allocator, value);
    }
    pub fn parameter(self: *Builder, allocator: A, value: Parameter) terms.Error!void {
        try self.values.charge(1);
        try self.values.view().proposition(value.proposition);
        if (self.parameters.items.len >= self.values.limits.terms) return error.ProofAnalysisLimit;
        try self.parameters.append(allocator, value);
    }
    pub fn use(self: *Builder, allocator: A, value: Use) terms.Error!void {
        try self.values.charge(1);
        try self.values.view().proposition(value.proposition);
        if (self.uses.items.len >= self.values.limits.terms) return error.ProofAnalysisLimit;
        try self.uses.append(allocator, value);
    }
    pub fn alias(self: *Builder, allocator: A, binding: u32, source: u32) terms.Error!void {
        try self.values.charge(1);
        if (!self.sources.contains(binding) and self.sources.count() >= self.values.limits.terms) return error.ProofAnalysisLimit;
        try self.sources.put(allocator, binding, source);
    }
    pub fn frontier(self: *const Builder, headers: usize) Frontier {
        return .{ .headers = @intCast(headers), .terms = @intCast(self.values.terms.items.len), .introductions = @intCast(self.introductions.items.len), .parameters = @intCast(self.parameters.items.len), .uses = @intCast(self.uses.items.len), .aliases = self.sources.count(), .expressions = self.expressions.count() };
    }
    pub fn take(self: *Builder, allocator: A) A.Error!Owned {
        var result: Owned = .{};
        errdefer result.deinit(allocator);
        result.debits = try self.debits.toOwnedSlice(allocator);
        result.operands = try self.values.terms.toOwnedSlice(allocator);
        result.introductions = try self.introductions.toOwnedSlice(allocator);
        result.parameters = try self.parameters.toOwnedSlice(allocator);
        result.uses = try self.uses.toOwnedSlice(allocator);
        return result;
    }
};

fn boundedBody(allocator: A) !void {
    var body: Builder = .{ .values = .{ .limits = .{ .terms = 2, .visits = 128 } } };
    defer body.deinit(allocator);
    const left = try body.values.intern(allocator, .{ .tag = .literal, .a = 0 });
    const right = try body.values.intern(allocator, .{ .tag = .literal, .a = 1 });
    const proposition: terms.Proposition = .{ .relation = .lt, .left = left, .right = right };
    for (1..3) |index| {
        const id: u32 = @intCast(index);
        try body.introduce(allocator, .{ .source = id, .owner = 1, .arguments = .{ 3, 4 }, .proposition = proposition });
        try body.parameter(allocator, .{ .binding = id, .contract = 1, .proposition = proposition });
        try body.use(allocator, .{ .source = id, .callee = 1, .witness = 1, .proposition = proposition });
        try body.alias(allocator, id, id + 2);
    }
    try std.testing.expectError(error.ProofAnalysisLimit, body.introduce(allocator, .{ .source = 3, .owner = 1, .arguments = .{ 3, 4 }, .proposition = proposition }));
    try std.testing.expectError(error.ProofAnalysisLimit, body.parameter(allocator, .{ .binding = 3, .contract = 1, .proposition = proposition }));
    try std.testing.expectError(error.ProofAnalysisLimit, body.use(allocator, .{ .source = 3, .callee = 1, .witness = 1, .proposition = proposition }));
    try std.testing.expectError(error.ProofAnalysisLimit, body.alias(allocator, 3, 5));
    body.values.visits = body.values.limits.visits;
    try std.testing.expectError(error.ProofAnalysisLimit, body.alias(allocator, 1, 9));
    try std.testing.expectEqual(@as(u32, 3), body.sources.get(1).?);
    var owned = try body.take(allocator);
    defer owned.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), owned.operands.len);
    try std.testing.expectEqual(@as(usize, 2), owned.introductions.len);
    try std.testing.expectEqual(@as(usize, 2), owned.parameters.len);
    try std.testing.expectEqual(@as(usize, 2), owned.uses.len);
}
test "numeric proof body metadata bounds every table and releases partial owners through OOM" {
    try boundedBody(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, boundedBody, .{});
}
