//! Optional portable candidates for a later compiler process. Checkpoints own
//! neither Core nor runtime values. Consumers still validate current source,
//! dynamic semantic inputs and complete optimizer dependencies.
const std = @import("std");
const capture = @import("artifact_capture.zig");
const principals = @import("principal_archive.zig");
const optimized = @import("optimized_archive.zig");
const format = @import("dependency_format.zig");
const A = std.mem.Allocator;
const Wire = struct { principal: []const u8, optimizer: []const u8 };
fn key(compiler: format.Digest) format.Key {
    return .{ .compiler = compiler, .settings = format.digest("blot-backend-checkpoint-v1"), .source = @splat(0), .dependencies = @splat(0) };
}
pub fn encode(a: A, compiler: format.Digest, source: *const capture.Capture) format.Error![]u8 {
    if (!source.emission.sealed) return error.InvalidArtifact;
    const principal = try principals.encode(a, compiler, &source.metadata);
    defer a.free(principal);
    const optimizer = if (source.optimized) |*bodies| try optimized.encode(a, compiler, bodies) else &.{};
    defer a.free(optimizer);
    return format.encodeWithLimits(a, key(compiler), Wire{ .principal = principal, .optimizer = optimizer }, .{ .elements = 64 * 1024 * 1024 });
}
pub const Checkpoint = struct {
    principal: principals.Archive,
    optimizer: ?@import("optimized_bodies.zig").Capture,
    pub fn deinit(self: *Checkpoint) void {
        self.principal.deinit();
        if (self.optimizer) |*bodies| bodies.deinit();
        self.* = undefined;
    }
};
pub fn decode(a: A, compiler: format.Digest, bytes: []const u8) format.Error!Checkpoint {
    var wire = try format.decodeWithLimits(Wire, a, bytes, key(compiler), .{ .elements = 64 * 1024 * 1024 });
    defer format.deinit(a, &wire);
    var principal = try principals.decode(a, compiler, wire.principal);
    errdefer principal.deinit();
    return .{ .principal = principal, .optimizer = if (wire.optimizer.len != 0) try optimized.decode(a, compiler, wire.optimizer) else null };
}
