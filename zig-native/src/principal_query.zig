//! Source-inferred principal results, distinct from selected specialization.
const std = @import("std");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const inputs = @import("principal_inputs.zig");
const queries = @import("semantic_query_table.zig");
const A = std.mem.Allocator;
const Key = struct {
    target: core.BindingRef,
    options: eval.Options,
    pub fn deinit(_: *Key, _: A) void {}
};
const Dependencies = struct {
    inputs: ?inputs.Key = null,
    pub fn deinit(self: *Dependencies, a: A) void {
        if (self.inputs) |*owned| owned.deinit(a);
    }
};
pub fn fingerprint(target: core.BindingRef) u64 {
    var hash = std.hash.Wyhash.init(0);
    std.hash.autoHash(&hash, target);
    return hash.final();
}
pub const Adapter = struct {
    pub const kind: queries.Kind = .principal;
    pub const Key = @import("principal_query.zig").Key;
    pub const Dependencies = @import("principal_query.zig").Dependencies;
    pub const Result = eval.SolvedEvidence;
    pub fn fingerprint(key: @This().Key) u64 {
        return @import("principal_query.zig").fingerprint(key.target);
    }
    /// Successful source inference can be empty. Optional projected observations
    /// affect admission/carry-forward, not whether its exact-source proof exists.
    pub fn complete(record: Table.Record) bool {
        return record.value.selected.len == 0;
    }
    pub fn bytes(record: Table.Record) usize {
        var total: usize = 0;
        if (record.dependencies.inputs) |observed| inline for (.{ "scalar_reads", "plain_reads", "plain_publications", "call_publications" }) |field| {
            const entries = @field(observed, field);
            total +|= entries.len *| @sizeOf(@TypeOf(entries[0]));
        };
        inline for (.{ "types", "rows", "selected" }) |field| {
            const entries = @field(record.value, field);
            total +|= entries.len *| @sizeOf(@TypeOf(entries[0]));
        }
        return total;
    }
};
pub const Table = queries.Table(Adapter);
