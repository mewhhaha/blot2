//! Complete selected answers pinned to one artifact's evaluator snapshot.
//! IDs are owner-local; cross-revision replay still validates/imports its graph.
const std = @import("std");
const eval = @import("core_eval.zig");
const receipt = @import("specialization_receipt.zig");
const queries = @import("semantic_query_table.zig");
const A = std.mem.Allocator;
pub const Source = struct { unit: u32, identity: u32, origin: eval.ClosureOrigin, applied: u32 };
pub fn source(value: eval.ClosureValue) Source {
    return .{ .unit = value.unit, .identity = value.identity, .origin = value.origin, .applied = value.applied };
}
pub fn fingerprint(value: Source) u64 {
    var hash = std.hash.Wyhash.init(0);
    std.hash.autoHash(&hash, value);
    return hash.final();
}
const Key = struct {
    source: Source,
    input: u32,
    expected: u32,
    options: eval.Options,
    depth: usize,
    pub fn deinit(_: *Key, _: A) void {}
};
const Result = struct {
    selected: u32,
    pub fn deinit(_: *Result, _: A) void {}
};
pub const Adapter = struct {
    pub const kind: queries.Kind = .specialization;
    pub const Key = @import("selected_query.zig").Key;
    pub const Dependencies = receipt.Record;
    pub const Result = @import("selected_query.zig").Result;
    pub fn fingerprint(key: @This().Key) u64 {
        return @import("selected_query.zig").fingerprint(key.source);
    }
    pub fn complete(record: Table.Record) bool {
        const proof = record.dependencies;
        return proof.complete and proof.steps == 0 and proof.input == record.key.input and
            proof.expected == record.key.expected and proof.selected == record.value.selected and
            proof.depth == record.key.depth and std.meta.eql(proof.options, record.key.options);
    }
    pub fn bytes(record: Table.Record) usize {
        return receipt.ownedBytes(record.dependencies);
    }
};
pub const Table = queries.Table(Adapter);
/// Takes ownership even when an incomplete or saturated observation declines.
pub fn remember(table: *Table, a: A, closure: eval.ClosureValue, owned: receipt.Record) A.Error!void {
    var builder = Table.begin(a, .{ .source = source(closure), .input = owned.input, .expected = owned.expected, .options = owned.options, .depth = owned.depth });
    defer builder.abort();
    builder.read(owned);
    builder.stage(.{ .selected = owned.selected });
    var candidate = builder.complete() orelse return;
    defer candidate.abort();
    const prepared = try table.prepare(a, &candidate) orelse return;
    _ = table.publish(prepared, &candidate);
}
