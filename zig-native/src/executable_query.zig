//! Complete executable inquiries within one immutable capture lease. Numeric
//! graph ordinals refer only to that capture's owned source/evidence/emission
//! pools; the existing executable gates still compare those graphs on reuse.
const std = @import("std");
const queries = @import("semantic_query_table.zig");
const artifacts = @import("code_artifacts.zig");
const core = @import("core.zig");
const wasm = @import("wasm.zig");
const lifetime = @import("wasm_lifetimes.zig");
const A = std.mem.Allocator;

/// Check the whole separately owned read set before allocating either array.
pub fn dependencyBytes(comptime Left: type, left: usize, comptime Right: type, right: usize) ?usize {
    const left_bytes = std.math.mul(usize, left, @sizeOf(Left)) catch return null;
    const right_bytes = std.math.mul(usize, right, @sizeOf(Right)) catch return null;
    return std.math.add(usize, left_bytes, right_bytes) catch null;
}

pub const FragmentKey = struct {
    request: artifacts.Request,
    pub fn deinit(_: *FragmentKey, _: A) void {}
};
pub const FragmentDependencies = struct {
    inline_bodies: []core.BindingRef,
    static_reads: []artifacts.StaticRead,
    /// The complete chronological job subtree and its ordered publications
    /// belong to the pinned capture, including nested executable consumers.
    replay_job: u32,
    reusable: bool,
    pub fn deinit(self: *FragmentDependencies, a: A) void {
        a.free(self.inline_bodies);
        a.free(self.static_reads);
    }
};
pub const FragmentResult = struct {
    function: u32,
    job: u32,
    pub fn deinit(_: *FragmentResult, _: A) void {}
};
const FragmentAdapter = struct {
    pub const kind: queries.Kind = .executable;
    pub const Key = FragmentKey;
    pub const Dependencies = FragmentDependencies;
    pub const Result = FragmentResult;
    pub fn fingerprint(key: Key) u64 {
        return fragmentFingerprint(key.request);
    }
    pub fn complete(record: FragmentTable.Record) bool {
        return (record.key.request == .named or record.key.request == .closure) and
            record.dependencies.reusable and record.value.job != 0 and record.dependencies.replay_job == record.value.job;
    }
    pub fn bytes(record: FragmentTable.Record) usize {
        return dependencyBytes(core.BindingRef, record.dependencies.inline_bodies.len, artifacts.StaticRead, record.dependencies.static_reads.len) orelse std.math.maxInt(usize);
    }
};
pub const FragmentTable = queries.Table(FragmentAdapter);
/// Owner translation and complete imported request equality happen after this
/// coarse bucket selection. A source ordinal alone never certifies a hit.
pub fn fragmentFingerprint(request: artifacts.Request) u64 {
    var hash = std.hash.Wyhash.init(0);
    std.hash.autoHash(&hash, std.meta.activeTag(request));
    switch (request) {
        .named => |key| std.hash.autoHash(&hash, key.target.binding),
        .closure => |key| std.hash.autoHash(&hash, key.catalog),
        else => {},
    }
    return hash.final();
}

pub const OptimizerKey = struct {
    /// The complete machine input belongs to Capture.entries[source].
    source: u32,
    local_fingerprint: u64,
    tier: @import("compilation_tier.zig").Tier,
    arena: ?wasm.Arena,
    pub fn deinit(_: *OptimizerKey, _: A) void {}
};
pub const OptimizerDependencies = struct {
    /// Ordered direct-call ordinals root the recursively checked body graph.
    callees: []u32,
    parameters: []lifetime.Parameter,
    invalidates: bool,
    owned_result_bytes: ?u32,
    /// Signatures, imports and global machine types are exact capture-owned
    /// graph inputs checked by Matcher, never portable ordinal identities.
    context_complete: bool,
    pub fn deinit(self: *OptimizerDependencies, a: A) void {
        a.free(self.callees);
        a.free(self.parameters);
    }
};
pub const OptimizerResult = struct {
    function: u32,
    /// A ready null body means use the captured source, not an incomplete job.
    ready: bool,
    pub fn deinit(_: *OptimizerResult, _: A) void {}
};
const OptimizerAdapter = struct {
    pub const kind: queries.Kind = .executable;
    pub const Key = OptimizerKey;
    pub const Dependencies = OptimizerDependencies;
    pub const Result = OptimizerResult;
    pub fn fingerprint(key: Key) u64 {
        return key.local_fingerprint;
    }
    pub fn complete(record: OptimizerTable.Record) bool {
        return record.value.ready and record.dependencies.context_complete and record.key.source == record.value.function;
    }
    pub fn bytes(record: OptimizerTable.Record) usize {
        return dependencyBytes(u32, record.dependencies.callees.len, lifetime.Parameter, record.dependencies.parameters.len) orelse std.math.maxInt(usize);
    }
};
pub const OptimizerTable = queries.Table(OptimizerAdapter);
