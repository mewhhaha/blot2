//! Dynamic inputs for the empty-result principal constraint query. The source
//! image is checked separately; this key never certifies an evaluated value.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const evidence = @import("type_evidence.zig");
const Allocator = std.mem.Allocator;
pub const ScalarRead = struct { target: core.BindingRef, evidence: u32 };
pub const PlainRead = struct { key: u64, value: ?bool };
pub const PlainPublication = struct { key: u64, value: bool };
pub const CallPublication = struct { target: core.BindingRef, evidence: u32 };
pub const Key = struct {
    scalar_reads: []const ScalarRead,
    plain_reads: []const PlainRead = &.{},
    plain_publications: []const PlainPublication = &.{},
    call_publications: []CallPublication = &.{},
    pub fn clone(self: Key, a: Allocator) Allocator.Error!Key {
        const scalar_reads = try a.dupe(ScalarRead, self.scalar_reads);
        errdefer a.free(scalar_reads);
        const plain_reads = try a.dupe(PlainRead, self.plain_reads);
        errdefer a.free(plain_reads);
        const plain_publications = try a.dupe(PlainPublication, self.plain_publications);
        errdefer a.free(plain_publications);
        return .{ .scalar_reads = scalar_reads, .plain_reads = plain_reads, .plain_publications = plain_publications, .call_publications = try a.dupe(CallPublication, self.call_publications) };
    }
    pub fn deinit(self: *Key, a: Allocator) void {
        a.free(self.scalar_reads);
        a.free(self.plain_reads);
        a.free(self.plain_publications);
        a.free(self.call_publications);
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
        // Absence is an input too. A cached negative can reflect a depth limit,
        // so do not replace these observations with a source-only "plain" test.
        for (self.plain_reads) |read| if (session.plain_nominals.get(read.key) != read.value) return false;
        return true;
    }
    /// Source-image and dynamic-input admission must precede this operation.
    /// Reserve first: allocation failure cannot leave a partially replayed memo.
    pub fn publish(self: Key, session: anytype) Allocator.Error!void {
        try session.plain_nominals.ensureUnusedCapacity(session.allocator, @intCast(self.plain_publications.len));
        try session.validated_calls.ensureUnusedCapacity(session.allocator, @intCast(self.call_publications.len));
        for (self.plain_publications) |fact| session.plain_nominals.putAssumeCapacity(fact.key, fact.value);
        for (self.call_publications) |call| {
            const key: @import("core_eval.zig").CallProofKey = .{ .target = .{ .unit = call.target.unit - 1, .binding = call.target.binding }, .evidence = call.evidence };
            if (!session.validated_calls.contains(key)) session.proofs.proof_published += 1;
            session.validated_calls.putAssumeCapacity(key, {});
        }
    }
};

pub const Reason = enum(u4) { unsupported, runtime_source, call_read, call_publication, evaluate, specialize, suspension, scalar_domain, changed_input, read_limit };
pub const Recorder = struct {
    rejected: u16 = 0,
    eligible: bool,
    max_reads: usize,
    reads: std.ArrayList(ScalarRead) = .empty,
    seen: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    plain_reads: std.ArrayList(PlainRead) = .empty,
    plain_publications: std.ArrayList(PlainPublication) = .empty,
    plain_seen: std.AutoHashMapUnmanaged(u64, struct { initial: ?bool, publication: ?usize = null }) = .empty,
    call_publications: std.ArrayList(CallPublication) = .empty,
    calls_seen: std.AutoHashMapUnmanaged(CallPublication, void) = .empty,
    pub fn deinit(self: *Recorder, a: Allocator) void {
        self.reads.deinit(a);
        self.seen.deinit(a);
        self.plain_reads.deinit(a);
        self.plain_publications.deinit(a);
        self.plain_seen.deinit(a);
        self.call_publications.deinit(a);
        self.calls_seen.deinit(a);
        self.* = undefined;
    }
    pub fn invalidate(self: *Recorder, reason: Reason) void {
        self.eligible = false;
        self.rejected |= @as(u16, 1) << @backingInt(reason);
    }
    pub fn scalar(self: *Recorder, a: Allocator, target: core.BindingRef, actual: u32) Allocator.Error!void {
        if (!self.eligible) return;
        if (actual > T.never or target.unit == 0 or target.binding == 0) {
            self.invalidate(.scalar_domain);
            return;
        }
        const read_id = (@as(u64, target.unit) << 32) | target.binding;
        if (self.seen.get(read_id)) |previous| {
            if (previous != actual) self.invalidate(.changed_input);
            return;
        }
        if (self.reads.items.len >= self.max_reads -| self.plain_reads.items.len) {
            self.invalidate(.read_limit);
            return;
        }
        try self.reads.ensureUnusedCapacity(a, 1);
        try self.seen.put(a, read_id, actual);
        self.reads.appendAssumeCapacity(.{ .target = target, .evidence = actual });
    }
    pub fn plainRead(self: *Recorder, a: Allocator, key_: u64, actual: ?bool) Allocator.Error!void {
        if (!self.eligible) return;
        if (self.plain_seen.get(key_)) |previous| {
            const expected: ?bool = if (previous.publication) |index| self.plain_publications.items[index].value else previous.initial;
            if (expected != actual) self.invalidate(.changed_input);
            return;
        }
        if (self.reads.items.len >= self.max_reads -| self.plain_reads.items.len) {
            self.invalidate(.read_limit);
            return;
        }
        try self.plain_reads.ensureUnusedCapacity(a, 1);
        try self.plain_seen.put(a, key_, .{ .initial = actual });
        self.plain_reads.appendAssumeCapacity(.{ .key = key_, .value = actual });
    }
    pub fn plainPublish(self: *Recorder, a: Allocator, key_: u64, value: bool) Allocator.Error!void {
        if (!self.eligible) return;
        const observed = self.plain_seen.getPtr(key_) orelse {
            self.invalidate(.changed_input);
            return;
        };
        if (observed.publication) |index| {
            self.plain_publications.items[index].value = value;
        } else {
            try self.plain_publications.append(a, .{ .key = key_, .value = value });
            observed.publication = self.plain_publications.items.len - 1;
        }
    }
    pub fn callPublish(self: *Recorder, a: Allocator, target: core.BindingRef, actual: u32) Allocator.Error!void {
        if (!self.eligible) return;
        const call: CallPublication = .{ .target = target, .evidence = actual };
        if (self.calls_seen.contains(call)) return;
        if (self.call_publications.items.len >= self.max_reads) {
            self.invalidate(.read_limit);
            return;
        }
        try self.call_publications.ensureUnusedCapacity(a, 1);
        try self.calls_seen.put(a, call, {});
        self.call_publications.appendAssumeCapacity(call);
    }
    /// The borrowed key lives only until the next record or recorder teardown.
    pub fn key(self: *const Recorder) ?Key {
        return if (self.eligible) .{ .scalar_reads = self.reads.items, .plain_reads = self.plain_reads.items, .plain_publications = self.plain_publications.items, .call_publications = self.call_publications.items } else null;
    }
};
