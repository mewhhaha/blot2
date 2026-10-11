//! Structured flow beside immutable Core. Symbolic edges belong to an owned
//! resolved body; emission binds their source scope to invocation-local labels
//! and cleanups. Core lists remain immutable borrows pinned by that body.
const std = @import("std");
const core = @import("core.zig");
const runtime_cleanup = @import("runtime_cleanup.zig");
const wasm = @import("wasm.zig");

/// An edge leaving one or more structured scopes.
pub const Exit = struct {
    pub const Kind = enum {
        /// `return` from a source `do` block to the block's result.
        return_,
        /// `break` from a loop or request loop to its exit.
        break_,
        /// A request loop whose handler returned from the enclosing block.
        request_return,
        /// A request loop whose handler broke out of it with new carries.
        request_break,
    };
    kind: Kind,
    /// The exiting statement or request loop, for its source span.
    source: core.Id,
    /// The block or loop the edge leaves.
    target: core.Id,
    /// The target's Wasm label, counted from the function body.
    label: u32,
    /// The target scope's cleanup mark. Actions above it belong to the scopes
    /// this edge leaves and run, innermost first, before the branch.
    cleanup: runtime_cleanup.Mark,
    /// The target block's result is a callable template, not a value.
    template_result: bool = false,
    /// A `return`'s value, evaluated before the edge.
    value: core.Id = 0,
    result_role: @import("runtime_ir.zig").Role = .scalar,
    /// A `break`'s values, evaluated in source order before the edge.
    values: []const core.Id = &.{},
    /// Loop carries the values replace, assigned last to first.
    carries: []const core.LoopCarry = &.{},

    /// The Wasm `br` depth from an exit point with `labels` open labels.
    pub fn depthAt(self: Exit, labels: u32) u32 {
        return labels - 1 - self.label;
    }
};

/// A semantic edge has no machine label or runtime cleanup handle. Its source
/// target names the scope that encoding must bind before emitting a branch.
pub const SymbolicExit = struct {
    kind: Exit.Kind,
    source: core.Id,
    target: core.Id,
    template_result: bool = false,
    value: core.Id = 0,
    result_role: @import("runtime_ir.zig").Role = .scalar,
    values: []const core.Id = &.{},
    carries: []const core.LoopCarry = &.{},
    pub fn bind(self: SymbolicExit, label: u32, cleanup: runtime_cleanup.Mark) Exit {
        return .{ .kind = self.kind, .source = self.source, .target = self.target, .label = label, .cleanup = cleanup, .template_result = self.template_result, .value = self.value, .result_role = self.result_role, .values = self.values, .carries = self.carries };
    }
};

/// Request edges keep source scopes; their invocation binds runtime labels.
pub const RequestLoop = struct {
    node: core.Id,
    arms: []const core.RequestArm,
    operations: []const @import("type_evidence.zig").Effects.Label,
    exited: SymbolicExit,
    broken: SymbolicExit,
    completion_pattern: core.PatternId,
    completion_body: core.Id,
};

/// Arms that rejoin with a value or with updated local versions.
pub const Join = struct {
    node: core.Id,
    /// Machine type of the joined value; null when the join is a statement.
    result: ?wasm.ValueType,
    /// Local versions each arm hands to the code after the join.
    merges: []const core.Merge,
    /// An `if` statement emits its else arm when it has one or must merge.
    else_arm: bool = false,
};

/// A source `case`. Inputs are evaluated once, in order. Within an arm, a row
/// whose pattern fails falls to the next row; a rejected guard falls to the
/// next arm; a completed arm joins the result. No arm matching traps, because
/// the checker proved coverage.
pub const Match = struct {
    join: Join,
    inputs: []const core.Id,
    arms: []const core.MatchArm,
    statement: bool,
};

/// A source loop's iteration edges and carried local versions.
pub const Loop = struct {
    node: core.Id,
    kind: core.LoopKind,
    /// Each carry enters as `incoming`, iterates as `iteration`, returns on
    /// the backedge as `backedge` and leaves as `outgoing` on every exit.
    carries: []const core.LoopCarry,
    carry_roles: u64 = 0,
    roots: bool = true,
    /// The element pattern tests at runtime and traps when it fails.
    refutable: bool,
    /// A `forever` loop without a `break` never reaches the code after it.
    diverges: bool,
};

test "exit plans name targets, depths and carries independently of emission" {
    const carries = [_]core.LoopCarry{.{ .incoming = 1, .iteration = 2, .backedge = 3, .outgoing = 4 }};
    const values = [_]core.Id{7};
    const exit: Exit = .{ .kind = .break_, .source = 9, .target = 5, .label = 2, .cleanup = @fromBackingInt(@intCast(0)), .values = &values, .carries = &carries };
    try std.testing.expectEqual(exit.values.len, exit.carries.len);
    try std.testing.expectEqual(@as(u32, 1), exit.depthAt(4));
    try std.testing.expectEqual(@as(core.BindingId, 4), exit.carries[0].outgoing);
}

test "symbolic exits acquire distinct labels and cleanup scopes per invocation" {
    const symbolic: SymbolicExit = .{ .kind = .return_, .source = 7, .target = 3, .value = 9 };
    const first = symbolic.bind(2, @fromBackingInt(4));
    const second = symbolic.bind(5, @fromBackingInt(8));
    try std.testing.expectEqual(symbolic.target, first.target);
    try std.testing.expectEqual(symbolic.value, second.value);
    try std.testing.expectEqual(@as(u32, 1), first.depthAt(4));
    try std.testing.expectEqual(@as(u32, 0), second.depthAt(6));
    try std.testing.expect(first.cleanup != second.cleanup);
}
