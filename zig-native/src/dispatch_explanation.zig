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
pub const Side = enum { left, builtin, right, destination, receiver, implementation };
pub const Outcome = enum {
    head_mismatch,
    requires_evidence,
    incompatible_type,
    incompatible_effect,
    selected,
    overlap,
    limit,
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
pub const max_steps = 8;
pub const max_bytes = 2048;
pub const Origin = struct {
    name: ?[]const u8 = null,
    path: ?[]const u8 = null,
    span: ?@import("ast.zig").Span = null,
    fn deinit(self: Origin, allocator: Allocator) void {
        if (self.name) |text| allocator.free(text);
        if (self.path) |text| allocator.free(text);
    }
    fn clone(self: Origin, allocator: Allocator) Allocator.Error!Origin {
        var result: Origin = .{ .span = self.span };
        errdefer result.deinit(allocator);
        if (self.name) |text| result.name = try allocator.dupe(u8, text);
        if (self.path) |text| result.path = try allocator.dupe(u8, text);
        return result;
    }
};
pub const Step = struct {
    member: ?[]const u8 = null,
    ty: ?[]const u8 = null,
    outcome: Outcome,
    fn deinit(self: Step, allocator: Allocator) void {
        if (self.member) |text| allocator.free(text);
        if (self.ty) |text| allocator.free(text);
    }
};
pub const Candidate = struct {
    side: Side,
    origin: ?Origin = null,
    /// The candidate's type as diagnostics spell it; null for an unnamed shape.
    operand: ?[]const u8 = null,
    outcome: Outcome,
    pub fn jsonStringify(self: Candidate, writer: anytype) !void {
        if (self.origin) |origin| return writer.write(.{ .side = self.side, .origin = origin, .operand = self.operand, .outcome = self.outcome });
        try writer.write(.{ .side = self.side, .operand = self.operand, .outcome = self.outcome });
    }
};
pub const Explanation = struct {
    /// The operator symbol, such as `+`, when the member implements one.
    operation: ?[]const u8 = null,
    /// The member name looked up, such as `add` or `from`, when known.
    member: ?[]const u8 = null,
    candidates: []Candidate = &.{},
    steps: []Step = &.{},
    /// A spelling was cut to `max_text` bytes or a candidate was dropped.
    truncated: bool = false,

    pub fn jsonStringify(self: Explanation, writer: anytype) !void {
        if (self.steps.len != 0) return writer.write(.{ .operation = self.operation, .member = self.member, .candidates = self.candidates, .steps = self.steps, .truncated = self.truncated });
        try writer.write(.{ .operation = self.operation, .member = self.member, .candidates = self.candidates, .truncated = self.truncated });
    }

    pub fn deinit(self: Explanation, allocator: Allocator) void {
        for (self.candidates) |candidate| {
            if (candidate.operand) |text| allocator.free(text);
            if (candidate.origin) |origin| origin.deinit(allocator);
        }
        for (self.steps) |step| step.deinit(allocator);
        allocator.free(self.steps);
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
        for (candidates) |*candidate| candidate.* = .{ .side = .left, .outcome = .no_member };
        result.candidates = candidates;
        for (self.candidates, candidates) |old, *new| {
            new.* = .{ .side = old.side, .outcome = old.outcome };
            if (old.operand) |text| new.operand = try allocator.dupe(u8, text);
            if (old.origin) |origin| new.origin = try origin.clone(allocator);
        }
        result.steps = try allocator.alloc(Step, self.steps.len);
        for (result.steps) |*step| step.* = .{ .outcome = .selected };
        for (self.steps, result.steps) |old, *step| {
            step.outcome = old.outcome;
            if (old.member) |text| step.member = try allocator.dupe(u8, text);
            if (old.ty) |text| step.ty = try allocator.dupe(u8, text);
        }
        return result;
    }
    fn fit(self: *Explanation, allocator: Allocator) Allocator.Error!void {
        var needs_bound = self.steps.len != 0;
        for (self.candidates) |candidate| if (candidate.side == .implementation) {
            needs_bound = true;
        };
        if (!needs_bound) return;
        while (true) {
            const bytes = try std.json.Stringify.valueAlloc(allocator, self.*, .{});
            const fits = bytes.len <= max_bytes;
            allocator.free(bytes);
            if (fits) return;
            self.truncated = true;
            var removed = false;
            for (self.steps) |*step| {
                if (step.ty) |text| {
                    allocator.free(text);
                    step.ty = null;
                    removed = true;
                    break;
                }
                if (step.member) |text| {
                    allocator.free(text);
                    step.member = null;
                    removed = true;
                    break;
                }
            }
            if (removed) continue;
            for (self.candidates) |*candidate| {
                if (candidate.operand) |text| {
                    allocator.free(text);
                    candidate.operand = null;
                    removed = true;
                    break;
                }
                if (candidate.origin) |*origin| {
                    if (origin.path) |text| {
                        allocator.free(text);
                        origin.path = null;
                        removed = true;
                        break;
                    }
                    if (origin.name) |text| {
                        allocator.free(text);
                        origin.name = null;
                        removed = true;
                        break;
                    }
                }
            }
            if (!removed) return;
        }
    }
};

/// Collects candidates in order, owning their text until `finish`.
pub const Builder = struct {
    allocator: Allocator,
    candidates: [max_candidates]Candidate = undefined,
    len: usize = 0,
    steps: [max_steps]Step = undefined,
    step_len: usize = 0,
    truncated: bool = false,

    pub fn deinit(self: *Builder) void {
        for (self.candidates[0..self.len]) |candidate| {
            if (candidate.operand) |text| self.allocator.free(text);
            if (candidate.origin) |origin| origin.deinit(self.allocator);
        }
        for (self.steps[0..self.step_len]) |step| step.deinit(self.allocator);
        self.step_len = 0;
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
    pub fn ownText(self: *Builder, value: []const u8) Allocator.Error![]u8 {
        if (value.len > max_text) self.truncated = true;
        return self.allocator.dupe(u8, value[0..boundary(value, max_text)]);
    }
    pub fn makeOrigin(self: *Builder, name: []const u8, path: ?[]const u8, span: ?@import("ast.zig").Span) Allocator.Error!Origin {
        var value: Origin = .{ .span = span };
        errdefer value.deinit(self.allocator);
        value.name = try self.ownText(name);
        if (path) |bytes| value.path = try self.ownText(bytes);
        return value;
    }
    pub fn addOrigin(self: *Builder, operand: ?[]u8, outcome: Outcome, value: Origin) void {
        if (self.len == max_candidates) {
            if (operand) |bytes| self.allocator.free(bytes);
            value.deinit(self.allocator);
            self.truncated = true;
            return;
        }
        self.candidates[self.len] = .{ .side = .implementation, .operand = operand, .outcome = outcome, .origin = value };
        self.len += 1;
    }
    pub fn addStep(self: *Builder, member: ?[]const u8, ty: ?[]u8, outcome: Outcome) Allocator.Error!void {
        var value: Step = .{ .ty = ty, .outcome = outcome };
        errdefer value.deinit(self.allocator);
        if (self.step_len == max_steps) {
            value.deinit(self.allocator);
            self.truncated = true;
            return;
        }
        if (member) |name| value.member = try self.ownText(name);
        self.steps[self.step_len] = value;
        self.step_len += 1;
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
        const candidates = try self.allocator.dupe(Candidate, self.candidates[0..self.len]);
        const steps = self.allocator.dupe(Step, self.steps[0..self.step_len]) catch |err| {
            self.allocator.free(candidates);
            return err;
        };
        var result: Explanation = .{ .candidates = candidates, .steps = steps, .truncated = self.truncated };
        self.len = 0;
        self.step_len = 0;
        errdefer result.deinit(self.allocator);
        if (operation) |text| result.operation = try self.allocator.dupe(u8, text[0..boundary(text, max_text)]);
        if (member) |text| {
            if (text.len > max_text) self.truncated = true;
            result.member = try self.allocator.dupe(u8, text[0..boundary(text, max_text)]);
        }
        try result.fit(self.allocator);
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
