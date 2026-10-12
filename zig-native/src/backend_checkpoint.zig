//! Optional portable candidates for a later compiler process. Checkpoints own
//! neither Core nor runtime values. Consumers still validate current source,
//! dynamic semantic inputs and complete optimizer dependencies.
const std = @import("std");
const capture = @import("artifact_capture.zig");
const principals = @import("principal_archive.zig");
const optimized = @import("optimized_archive.zig");
const semantic = @import("semantic_archive.zig");
const format = @import("dependency_format.zig");
const A = std.mem.Allocator;
const Wire = struct { principal: []const u8, optimizer: []const u8, semantic: []const u8 };
fn key(compiler: format.Digest) format.Key {
    // Version five adds owned associated declaration and projection recipes.
    return .{ .compiler = compiler, .settings = format.digest("blot-backend-checkpoint-v5:associated-types"), .source = @splat(0), .dependencies = @splat(0) };
}
pub fn encode(a: A, compiler: format.Digest, source: *const capture.Capture) format.Error![]u8 {
    if (!source.emission.sealed) return error.InvalidArtifact;
    const principal = try principals.encode(a, compiler, &source.metadata);
    defer a.free(principal);
    const optimizer = if (source.optimized) |*bodies| try optimized.encode(a, compiler, bodies) else &.{};
    defer a.free(optimizer);
    // An unsupported or oversized semantic owner is omitted, never partial.
    const owner = try semantic.encode(a, compiler, source) orelse &.{};
    defer a.free(owner);
    return format.encodeWithLimits(a, key(compiler), Wire{ .principal = principal, .optimizer = optimizer, .semantic = owner }, .{ .elements = 64 * 1024 * 1024 });
}
pub const Checkpoint = struct {
    principal: principals.Archive,
    optimizer: ?@import("optimized_bodies.zig").Capture,
    semantic: ?semantic.Archive = null,
    pub fn deinit(self: *Checkpoint) void {
        self.principal.deinit();
        if (self.optimizer) |*bodies| bodies.deinit();
        if (self.semantic) |*owner| owner.deinit();
        self.* = undefined;
    }
};
pub fn decode(a: A, compiler: format.Digest, bytes: []const u8) format.Error!Checkpoint {
    var wire = try format.decodeWithLimits(Wire, a, bytes, key(compiler), .{ .elements = 64 * 1024 * 1024 });
    defer format.deinit(a, &wire);
    var principal = try principals.decode(a, compiler, wire.principal);
    errdefer principal.deinit();
    var optimizer: ?@import("optimized_bodies.zig").Capture = if (wire.optimizer.len != 0) try optimized.decode(a, compiler, wire.optimizer) else null;
    errdefer if (optimizer) |*bodies| bodies.deinit();
    return .{ .principal = principal, .optimizer = optimizer, .semantic = if (wire.semantic.len != 0) try semantic.decode(a, compiler, wire.semantic) else null };
}
