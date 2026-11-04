//! Read-only substitution across independently owned staged producer graphs.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const Error = error{InvalidArtifact};
const ComparisonError = Error || error{ComparisonLimit};
fn require(ok: bool) Error!void {
    if (!ok) return error.InvalidArtifact;
}
fn identity(m: *const core.Module, value: T.NominalIdentity) T.NominalIdentity {
    var result = value;
    if (result.unit == 0 and result.decl != 0) result.unit = m.unit;
    return result;
}
pub fn sameIdentity(left: *const core.Module, a: T.NominalIdentity, right: *const core.Module, b: T.NominalIdentity) bool {
    return std.meta.eql(identity(left, a), identity(right, b));
}
fn step(remaining: *usize, depth: usize) ComparisonError!void {
    if (depth >= 128 or remaining.* == 0) return error.ComparisonLimit;
    remaining.* -= 1;
}
pub fn row(left: *const core.Module, a: T.Effects.Id, right: *const core.Module, b: T.Effects.Id, remaining: *usize, depth: usize) Error!void {
    rowDepth(left, a, right, b, remaining, depth) catch return error.InvalidArtifact;
}
fn rowDepth(left: *const core.Module, a: T.Effects.Id, right: *const core.Module, b: T.Effects.Id, remaining: *usize, depth: usize) ComparisonError!void {
    try step(remaining, depth);
    const first = left.types.rowLabels(a);
    const second = right.types.rowLabels(b);
    try require(first.len == second.len and first.len <= 256);
    var consumed: [256]bool = @splat(false);
    for (first) |label| {
        const operation = left.types.operations[label];
        var matched = false;
        for (second, 0..) |other, index| {
            try step(remaining, depth);
            if (consumed[index]) continue;
            const candidate = right.types.operations[other];
            if (!std.meta.eql(identity(left, operation.identity), identity(right, candidate.identity)) or !std.meta.eql(identity(left, operation.instance), identity(right, candidate.instance))) continue;
            const xs = left.types.list(operation.arguments);
            const ys = right.types.list(candidate.arguments);
            if (xs.len != ys.len) continue;
            var arguments_match = true;
            for (xs, ys) |x, y| matchDepth(left, x, right, y, &.{}, &.{}, remaining, depth + 1) catch |err| {
                if (err == error.ComparisonLimit) return err;
                arguments_match = false;
                break;
            };
            if (!arguments_match) continue;
            matched = true;
            consumed[index] = true;
            break;
        }
        try require(matched);
    }
}
pub fn match(left: *const core.Module, a: T.Id, right: *const core.Module, b: T.Id, variables: []const T.Id, substitutions: []T.Id, remaining: *usize, depth: usize) Error!void {
    matchDepth(left, a, right, b, variables, substitutions, remaining, depth) catch return error.InvalidArtifact;
}
fn matchDepth(left: *const core.Module, a: T.Id, right: *const core.Module, b: T.Id, variables: []const T.Id, substitutions: []T.Id, remaining: *usize, depth: usize) ComparisonError!void {
    try step(remaining, depth);
    const first = left.types.node(a);
    if (first.tag == .variable) {
        const index = std.mem.findScalar(T.Id, variables, a) orelse {
            try require(left == right and a == b);
            return;
        };
        try require(index < substitutions.len);
        if (substitutions[index] == 0) substitutions[index] = b else try matchDepth(right, substitutions[index], right, b, &.{}, &.{}, remaining, depth + 1);
        return;
    }
    const second = right.types.node(b);
    try require(first.tag == second.tag);
    switch (first.tag) {
        .unit, .boolean, .u32, .f32, .never => {},
        .array, .list => try matchDepth(left, first.a, right, second.a, variables, substitutions, remaining, depth + 1),
        .usage => {
            try require(first.b == second.b);
            if (first.c == 0 or second.c == 0) {
                try require(first.c == second.c);
            } else try matchDepth(left, first.c, right, second.c, variables, substitutions, remaining, depth + 1);
            try matchDepth(left, first.a, right, second.a, variables, substitutions, remaining, depth + 1);
        },
        .product => {
            try require(first.b == second.b);
            for (left.types.list(.{ .start = first.a, .len = first.b }), right.types.list(.{ .start = second.a, .len = second.b })) |x, y| try matchDepth(left, x, right, y, variables, substitutions, remaining, depth + 1);
        },
        .record => {
            try require(first.b == second.b);
            for (0..first.b) |index| {
                const field = left.types.recordField(first, index);
                var found = false;
                for (0..second.b) |other| {
                    try step(remaining, depth);
                    const candidate = right.types.recordField(second, other);
                    if (field.name != candidate.name) continue;
                    try matchDepth(left, field.ty, right, candidate.ty, variables, substitutions, remaining, depth + 1);
                    found = true;
                    break;
                }
                try require(found);
            }
        },
        .nominal => {
            try require(std.meta.eql(identity(left, .{ .unit = first.a, .decl = first.b }), identity(right, .{ .unit = second.a, .decl = second.b })));
            const xs = left.types.nominalArguments(first);
            const ys = right.types.nominalArguments(second);
            try require(xs.len == ys.len);
            for (xs, ys) |x, y| try matchDepth(left, x, right, y, variables, substitutions, remaining, depth + 1);
        },
        .function => {
            try require(left.types.row(first.c).tail == .closed and right.types.row(second.c).tail == .closed);
            try rowDepth(left, first.c, right, second.c, remaining, depth + 1);
            try matchDepth(left, first.a, right, second.a, variables, substitutions, remaining, depth + 1);
            try matchDepth(left, first.b, right, second.b, variables, substitutions, remaining, depth + 1);
        },
        else => return error.InvalidArtifact,
    }
}
