//! Optional portable candidates for a later compiler process. Checkpoints own
//! neither Core nor runtime values. Consumers still validate current source,
//! dynamic semantic inputs and complete optimizer dependencies.
const std = @import("std");
const capture = @import("../reuse/artifact_capture.zig");
const principals = @import("../reuse/principal_archive.zig");
const optimized = @import("../reuse/optimized_archive.zig");
const semantic = @import("../reuse/semantic_archive.zig");
const format = @import("../reuse/dependency_format.zig");
const A = std.mem.Allocator;
const Wire = struct { principal: []const u8, optimizer: []const u8, semantic: []const u8 };
fn key(compiler: format.Digest) format.Key {
    // Version six adds owned implementations and complete selected proof recipes.
    return .{ .compiler = compiler, .settings = format.digest("blot-backend-checkpoint-v6:selected-implementations"), .source = @splat(0), .dependencies = @splat(0) };
}
/// What an encoding left out for size, so a cache can say so.
pub const Report = struct { semantic_over_limit: bool = false };
pub fn encode(a: A, compiler: format.Digest, source: *const capture.Capture) format.Error![]u8 {
    var report: Report = .{};
    return encodeReporting(a, compiler, source, &report);
}
/// `error.ArtifactLimit` means an archive or the whole checkpoint is too large.
pub fn encodeReporting(a: A, compiler: format.Digest, source: *const capture.Capture, report: *Report) format.Error![]u8 {
    if (!source.emission.sealed) return error.InvalidArtifact;
    // Both archives record each pinned Core's digest; compute it once.
    const pins = if (source.metadata.pools) |*pools| pools.modules else return error.InvalidArtifact;
    const digests = try a.alloc(format.Digest, pins.len);
    defer a.free(digests);
    for (pins, digests) |pin, *digest| digest.* = pin.stamp orelse @import("../reuse/code_artifacts.zig").stamp(pin.module.*);
    const principal = try principals.encodeWithDigests(a, compiler, &source.metadata, digests);
    defer a.free(principal);
    const optimizer = if (source.optimized) |*bodies| try optimized.encode(a, compiler, bodies) else &.{};
    defer a.free(optimizer);
    // An unsupported or oversized semantic owner is omitted, never partial.
    const owner = try semantic.encodeWithDigests(a, compiler, source, digests, &report.semantic_over_limit) orelse &.{};
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
