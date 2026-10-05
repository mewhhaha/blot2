//! Dynamic inputs for the empty-result principal constraint query. The source
//! image is checked separately; this key never certifies an evaluated value.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const evidence = @import("type_evidence.zig");
const Allocator = std.mem.Allocator;
pub const ScalarRead = struct { target: core.BindingRef, evidence: u32 };
pub const Key = struct {
    scalar_reads: []const ScalarRead,
    pub fn clone(self: Key, a: Allocator) Allocator.Error!Key {
        return .{ .scalar_reads = try a.dupe(ScalarRead, self.scalar_reads) };
    }
    pub fn deinit(self: *Key, a: Allocator) void {
        a.free(self.scalar_reads);
        self.* = undefined;
    }
    pub fn matches(self: Key, session: anytype) bool {
        if (session.validated_calls.count() != 0) return false;
        const tags = [_]evidence.Tag{ .absent, .unit, .boolean, .u32, .f32, .never };
        if (session.evidence.nodes.items.len < tags.len) return false;
        for (session.evidence.nodes.items[0..tags.len], tags) |node, tag|
            if (!std.meta.eql(node, evidence.Node{ .tag = tag })) return false;
        for (self.scalar_reads) |read| {
            if (read.evidence > T.never or read.target.unit == 0 or read.target.unit > session.units.len) return false;
            const module = &session.units[read.target.unit - 1];
            if (read.target.binding == 0 or read.target.binding >= module.bindings.len) return false;
            const body = module.body(read.target.binding) orelse return false;
            const slot = session.slots[session.binding_offsets[read.target.unit - 1] + read.target.binding];
            const actual = if (!body.runtime and slot.state == .complete and session.valueInfo(slot.value).kind == .scalar) session.valueEvidence(slot.value) else 0;
            if (actual != read.evidence) return false;
        }
        return true;
    }
};

pub const Recorder = struct {
    eligible: bool,
    max_reads: usize,
    reads: std.ArrayList(ScalarRead) = .empty,
    seen: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    pub fn deinit(self: *Recorder, a: Allocator) void {
        self.reads.deinit(a);
        self.seen.deinit(a);
        self.* = undefined;
    }
    pub fn invalidate(self: *Recorder) void {
        self.eligible = false;
    }
    pub fn scalar(self: *Recorder, a: Allocator, target: core.BindingRef, actual: u32) Allocator.Error!void {
        if (!self.eligible) return;
        if (actual > T.never or target.unit == 0 or target.binding == 0) {
            self.invalidate();
            return;
        }
        const read_id = (@as(u64, target.unit) << 32) | target.binding;
        if (self.seen.get(read_id)) |previous| {
            if (previous != actual) self.invalidate();
            return;
        }
        if (self.reads.items.len >= self.max_reads) {
            self.invalidate();
            return;
        }
        try self.reads.ensureUnusedCapacity(a, 1);
        try self.seen.put(a, read_id, actual);
        self.reads.appendAssumeCapacity(.{ .target = target, .evidence = actual });
    }
    /// The borrowed key lives only until the next record or recorder teardown.
    pub fn key(self: *const Recorder) ?Key {
        return if (self.eligible) .{ .scalar_reads = self.reads.items } else null;
    }
};
