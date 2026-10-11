//! Bounded explanations of operator, associated and receiver dispatch for one
//! diagnostic: the member looked up, each candidate owner in the order
//! dispatch considered it, and what happened to it. Text is owned and spelled
//! for people; nothing names inference tables, and building an explanation
//! never reruns inference or changes which candidate dispatch selects.
const std = @import("std");
const T = @import("types.zig");
const Allocator = std.mem.Allocator;

/// Left operand, built-in scalar operation, right operand, plus one spare.
pub const max_candidates = 4;
/// Longest member or operand spelling kept; longer text is cut and marked.
pub const max_text = 256;

/// Where a candidate came from. Binary dispatch considers the left operand's
/// type, then a built-in scalar operation, then the right operand's type when
/// it differs from the left. Result dispatch looks only at its destination
/// type, and member access only at its receiver, never at argument types.
pub const Side = enum { left, builtin, right, destination, receiver };
pub const Outcome = enum {
    /// The type is still unknown, so it names no owner to search.
    unknown_operand,
    /// The type declares no member with this name.
    no_member,
    /// The type declares the member, but its signature rejects the operands.
    incompatible,
    /// Both operands are this scalar type, which has no such operation.
    unsupported_scalar,
    /// Dispatch selected this candidate from its operands. Its result then
    /// conflicted with the expected type; later candidates were not tried.
    result_mismatch,
};
pub const Candidate = struct {
    side: Side,
    /// The candidate's type as diagnostics spell it; null for an unnamed shape.
    operand: ?[]const u8 = null,
    outcome: Outcome,
};
pub const Explanation = struct {
    /// The operator symbol, such as `+`, when the member implements one.
    operation: ?[]const u8 = null,
    /// The member name looked up, such as `add` or `from`, when known.
    member: ?[]const u8 = null,
    candidates: []Candidate = &.{},
    /// A spelling was cut to `max_text` bytes or a candidate was dropped.
    truncated: bool = false,

    pub fn deinit(self: Explanation, allocator: Allocator) void {
        for (self.candidates) |candidate| if (candidate.operand) |text| allocator.free(text);
        allocator.free(self.candidates);
        if (self.operation) |text| allocator.free(text);
        if (self.member) |text| allocator.free(text);
    }
    pub fn clone(self: Explanation, allocator: Allocator) Allocator.Error!Explanation {
        var result: Explanation = .{ .truncated = self.truncated };
        errdefer result.deinit(allocator);
        if (self.operation) |text| result.operation = try allocator.dupe(u8, text);
        if (self.member) |text| result.member = try allocator.dupe(u8, text);
        const candidates = try allocator.alloc(Candidate, self.candidates.len);
        for (candidates) |*candidate| candidate.operand = null;
        result.candidates = candidates;
        for (self.candidates, candidates) |old, *new| {
            new.* = .{ .side = old.side, .outcome = old.outcome };
            if (old.operand) |text| new.operand = try allocator.dupe(u8, text);
        }
        return result;
    }
};

/// Collects candidates in order, owning their text until `finish`.
pub const Builder = struct {
    allocator: Allocator,
    candidates: [max_candidates]Candidate = undefined,
    len: usize = 0,
    truncated: bool = false,

    pub fn deinit(self: *Builder) void {
        for (self.candidates[0..self.len]) |candidate| if (candidate.operand) |text| self.allocator.free(text);
        self.len = 0;
    }
    /// Takes ownership of `operand`, which `own` produced.
    pub fn add(self: *Builder, side: Side, operand: ?[]u8, outcome: Outcome) void {
        if (self.len == max_candidates) {
            if (operand) |text| self.allocator.free(text);
            self.truncated = true;
            return;
        }
        self.candidates[self.len] = .{ .side = side, .operand = operand, .outcome = outcome };
        self.len += 1;
    }
    /// Owns `bytes` as text, cut to `max_text` on a UTF-8 boundary. `bytes`
    /// is left empty and reusable.
    pub fn own(self: *Builder, bytes: *std.ArrayList(u8)) Allocator.Error![]u8 {
        if (bytes.items.len > max_text) {
            bytes.shrinkRetainingCapacity(boundary(bytes.items, max_text));
            self.truncated = true;
        }
        return bytes.toOwnedSlice(self.allocator);
    }
    pub fn finish(self: *Builder, operation: ?[]const u8, member: ?[]const u8) Allocator.Error!Explanation {
        var result: Explanation = .{};
        errdefer result.deinit(self.allocator);
        if (operation) |text| result.operation = try self.allocator.dupe(u8, text[0..boundary(text, max_text)]);
        if (member) |text| {
            if (text.len > max_text) self.truncated = true;
            result.member = try self.allocator.dupe(u8, text[0..boundary(text, max_text)]);
        }
        result.candidates = try self.allocator.dupe(Candidate, self.candidates[0..self.len]);
        result.truncated = self.truncated;
        self.len = 0;
        return result;
    }
};

/// The source symbol of a binary operator, or null for an ordinary member.
pub fn operatorSymbol(operator: T.Operator) ?[]const u8 {
    return switch (operator) {
        .add => "+",
        .sub => "-",
        .mul => "*",
        .div => "/",
        .rem => "%",
        .equal => "==",
        .not_equal => "!=",
        .less => "<",
        .less_equal => "<=",
        .greater => ">",
        .greater_equal => ">=",
        .bit_and => "&",
        .bit_or => "|",
        .bit_xor => "^",
        .shift_left => "<<",
        .shift_right => ">>",
        .none => null,
    };
}
/// The member that implements an operator, as in `Vec.add`.
pub fn operatorMember(operator: T.Operator) ?[]const u8 {
    return switch (operator) {
        .add => "add",
        .sub => "sub",
        .mul => "mul",
        .div => "div",
        .rem => "rem",
        .equal => "eq",
        .not_equal => "ne",
        .less => "lt",
        .less_equal => "le",
        .greater => "gt",
        .greater_equal => "ge",
        .bit_and => "bit_and",
        .bit_or => "bit_or",
        .bit_xor => "bit_xor",
        .shift_left => "shl",
        .shift_right => "shr",
        .none => null,
    };
}

/// The longest prefix of at most `limit` bytes that ends on a UTF-8 boundary.
fn boundary(text: []const u8, limit: usize) usize {
    if (text.len <= limit) return text.len;
    var end = limit;
    while (end > 0 and (text[end] & 0xc0) == 0x80) end -= 1;
    return end;
}

test "explanations bound text on UTF-8 boundaries and clone independently" {
    const allocator = std.testing.allocator;
    var builder: Builder = .{ .allocator = allocator };
    defer builder.deinit();
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(allocator);
    const prefix: [max_text - 1]u8 = @splat('a');
    try bytes.appendSlice(allocator, &prefix);
    try bytes.appendSlice(allocator, "é");
    builder.add(.left, try builder.own(&bytes), .no_member);
    for (0..max_candidates) |_| builder.add(.right, null, .incompatible);
    const explanation = try builder.finish("+", "add");
    defer explanation.deinit(allocator);
    try std.testing.expect(explanation.truncated);
    try std.testing.expectEqual(max_candidates, explanation.candidates.len);
    try std.testing.expectEqual(max_text - 1, explanation.candidates[0].operand.?.len);
    try std.testing.expect(std.unicode.utf8ValidateSlice(explanation.candidates[0].operand.?));
    const copy = try explanation.clone(allocator);
    defer copy.deinit(allocator);
    try std.testing.expectEqualStrings(explanation.candidates[0].operand.?, copy.candidates[0].operand.?);
    try std.testing.expect(explanation.candidates[0].operand.?.ptr != copy.candidates[0].operand.?.ptr);
}

test "explanation ownership survives every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: Allocator) !void {
            var builder: Builder = .{ .allocator = allocator };
            defer builder.deinit();
            var bytes: std.ArrayList(u8) = .empty;
            defer bytes.deinit(allocator);
            try bytes.appendSlice(allocator, "main::Box");
            builder.add(.left, try builder.own(&bytes), .no_member);
            builder.add(.builtin, null, .unsupported_scalar);
            const explanation = try builder.finish("+", "add");
            defer explanation.deinit(allocator);
            const copy = try explanation.clone(allocator);
            copy.deinit(allocator);
        }
    }.run, .{});
}
