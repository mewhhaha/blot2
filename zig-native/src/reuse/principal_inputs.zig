//! Dynamic inputs for the principal constraint query. The source
//! image is checked separately; this key never certifies an evaluated value.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const evidence = @import("../eval/type_evidence.zig");
const Allocator = std.mem.Allocator;
pub const ScalarRead = struct { target: core.BindingRef, evidence: u32 };
pub const PlainRead = struct { key: u64, value: ?bool };
pub const PlainPublication = struct { key: u64, value: bool };
pub const CallPublication = struct { target: core.BindingRef, evidence: u32 };
pub const CallRead = struct { target: core.BindingRef, evidence: u32, present: bool };
pub const SummaryKey = struct { target: core.BindingRef, inputs: u32, deferred_member: bool = false };
pub const Summary = struct { key: SummaryKey, result: u32 };
pub const Key = struct {
    empty_call_inputs: bool = true,
    source_complete: bool = false,
    sources: []const core.BindingRef = &.{},
    /// Only a freshly checked, obligation-free scheme was consumed.
    interfaces: []const core.BindingRef = &.{},
    /// Anonymous/local bodies without a named declaration observation retain
    /// the complete principal input image of their source module instead.
    source_units: []const u32 = &.{},
    scalar_reads: []const ScalarRead,
    plain_reads: []const PlainRead = &.{},
    plain_publications: []const PlainPublication = &.{},
    call_publications: []CallPublication = &.{},
    call_reads: []CallRead = &.{},
    summary_reads: []Summary = &.{},
    summary_publications: []Summary = &.{},
    pub fn clone(self: Key, a: Allocator) Allocator.Error!Key {
        const sources = try a.dupe(core.BindingRef, self.sources);
        errdefer a.free(sources);
        const interfaces = try a.dupe(core.BindingRef, self.interfaces);
        errdefer a.free(interfaces);
        const source_units = try a.dupe(u32, self.source_units);
        errdefer a.free(source_units);
        const scalar_reads = try a.dupe(ScalarRead, self.scalar_reads);
        errdefer a.free(scalar_reads);
        const plain_reads = try a.dupe(PlainRead, self.plain_reads);
        errdefer a.free(plain_reads);
        const plain_publications = try a.dupe(PlainPublication, self.plain_publications);
        errdefer a.free(plain_publications);
        const call_publications = try a.dupe(CallPublication, self.call_publications);
        errdefer a.free(call_publications);
        const call_reads = try a.dupe(CallRead, self.call_reads);
        errdefer a.free(call_reads);
        const summary_reads = try a.dupe(Summary, self.summary_reads);
        errdefer a.free(summary_reads);
        return .{ .empty_call_inputs = self.empty_call_inputs, .source_complete = self.source_complete, .sources = sources, .interfaces = interfaces, .source_units = source_units, .scalar_reads = scalar_reads, .plain_reads = plain_reads, .plain_publications = plain_publications, .call_publications = call_publications, .call_reads = call_reads, .summary_reads = summary_reads, .summary_publications = try a.dupe(Summary, self.summary_publications) };
    }
    pub fn deinit(self: *Key, a: Allocator) void {
        a.free(self.sources);
        a.free(self.interfaces);
        a.free(self.source_units);
        a.free(self.scalar_reads);
        a.free(self.plain_reads);
        a.free(self.plain_publications);
        a.free(self.call_publications);
        a.free(self.call_reads);
        a.free(self.summary_reads);
        a.free(self.summary_publications);
        self.* = undefined;
    }
    pub fn matches(self: Key, session: anytype) bool {
        if (!self.matchesBase(session)) return false;
        for (self.call_reads) |read| {
            if (read.target.unit == 0 or read.target.unit > session.units.len or read.target.binding == 0 or read.target.binding >= session.units[read.target.unit - 1].bindings.len) return false;
            const key: @import("../eval/core_eval.zig").CallProofKey = .{ .target = .{ .unit = read.target.unit - 1, .binding = read.target.binding }, .evidence = read.evidence };
            if (session.specializations.validated_calls.contains(key) != read.present) return false;
        }
        for (self.summary_reads) |read| if (!session.principalSummaryMatches(read)) return false;
        return true;
    }
    /// Scalar/nominal inputs carry stable source IDs. Call evidence must first
    /// be translated into this session; an old numeric ID is never a key here.
    pub fn matchesBase(self: Key, session: anytype) bool {
        if (self.empty_call_inputs and session.specializations.validated_calls.count() != 0) return false;
        const tags = [_]evidence.Tag{ .absent, .unit, .boolean, .u32, .f32, .never };
        if (session.storage.evidence.nodes.items.len < tags.len) return false;
        for (session.storage.evidence.nodes.items[0..tags.len], tags) |node, tag|
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
        for (self.plain_reads) |read| if (session.specializations.plain_nominals.get(read.key) != read.value) return false;
        return true;
    }
    /// Source-image and dynamic-input admission must precede this operation.
    /// Reserve first: allocation failure cannot leave a partially replayed memo.
    pub fn publish(self: Key, session: anytype) Allocator.Error!void {
        try session.specializations.plain_nominals.ensureUnusedCapacity(session.allocator, @intCast(self.plain_publications.len));
        try session.specializations.validated_calls.ensureUnusedCapacity(session.allocator, @intCast(self.call_publications.len));
        try session.reservePrincipalSummaries(self.summary_publications.len);
        for (self.plain_publications) |fact| session.specializations.plain_nominals.putAssumeCapacity(fact.key, fact.value);
        for (self.call_publications) |call| {
            const key: @import("../eval/core_eval.zig").CallProofKey = .{ .target = .{ .unit = call.target.unit - 1, .binding = call.target.binding }, .evidence = call.evidence };
            if (!session.specializations.validated_calls.contains(key)) session.proofs.proof_published += 1;
            session.specializations.validated_calls.putAssumeCapacity(key, {});
        }
        for (self.summary_publications) |summary| session.publishPrincipalSummary(summary);
    }
};

pub const Reason = enum(u4) { unsupported, runtime_source, call_read, call_publication, evaluate, specialize, suspension, scalar_domain, changed_input, read_limit };
pub const Recorder = struct {
    rejected: u16 = 0,
    eligible: bool,
    empty_call_inputs: bool = true,
    source_complete: bool = true,
    root: core.BindingRef = .{ .unit = 0, .binding = 0 },
    sources: std.ArrayList(core.BindingRef) = .empty,
    sources_seen: std.AutoHashMapUnmanaged(core.BindingRef, void) = .empty,
    interfaces: std.ArrayList(core.BindingRef) = .empty,
    interfaces_seen: std.AutoHashMapUnmanaged(core.BindingRef, void) = .empty,
    source_units: std.ArrayList(u32) = .empty,
    source_units_seen: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Session-unique and nonzero for a recorder attached to a session.
    serial: u64 = 0,
    max_reads: usize,
    reads: std.ArrayList(ScalarRead) = .empty,
    seen: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    plain_reads: std.ArrayList(PlainRead) = .empty,
    plain_publications: std.ArrayList(PlainPublication) = .empty,
    plain_seen: std.AutoHashMapUnmanaged(u64, struct { initial: ?bool, publication: ?usize = null }) = .empty,
    call_publications: std.ArrayList(CallPublication) = .empty,
    calls_seen: std.AutoHashMapUnmanaged(CallPublication, void) = .empty,
    call_reads: std.ArrayList(CallRead) = .empty,
    call_reads_seen: std.AutoHashMapUnmanaged(CallPublication, bool) = .empty,
    summary_reads: std.ArrayList(Summary) = .empty,
    summary_publications: std.ArrayList(Summary) = .empty,
    summaries_seen: std.AutoHashMapUnmanaged(SummaryKey, u32) = .empty,
    summary_reads_seen: std.AutoHashMapUnmanaged(SummaryKey, u32) = .empty,
    pub fn deinit(self: *Recorder, a: Allocator) void {
        self.sources.deinit(a);
        self.sources_seen.deinit(a);
        self.interfaces.deinit(a);
        self.interfaces_seen.deinit(a);
        self.source_units.deinit(a);
        self.source_units_seen.deinit(a);
        self.reads.deinit(a);
        self.seen.deinit(a);
        self.plain_reads.deinit(a);
        self.plain_publications.deinit(a);
        self.plain_seen.deinit(a);
        self.call_publications.deinit(a);
        self.calls_seen.deinit(a);
        self.call_reads.deinit(a);
        self.call_reads_seen.deinit(a);
        self.summary_reads.deinit(a);
        self.summary_publications.deinit(a);
        self.summaries_seen.deinit(a);
        self.summary_reads_seen.deinit(a);
        self.* = undefined;
    }
    pub fn invalidate(self: *Recorder, reason: Reason) void {
        self.eligible = false;
        self.rejected |= @as(u16, 1) << @backingInt(reason);
    }
    pub fn scalar(self: *Recorder, a: Allocator, target: core.BindingRef, actual: u32) Allocator.Error!void {
        if (!self.eligible) return;
        try self.source(a, target);
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
    pub fn callRead(self: *Recorder, a: Allocator, target: core.BindingRef, actual: u32, present: bool) Allocator.Error!void {
        if (!self.eligible) return;
        const call: CallPublication = .{ .target = target, .evidence = actual };
        if (self.calls_seen.contains(call)) {
            if (!present) self.invalidate(.changed_input);
            return;
        }
        // An empty initial table proves every external negative, without
        // transporting deep optional signatures just to establish absence.
        if (self.empty_call_inputs) {
            if (present) self.invalidate(.call_read);
            return;
        }
        if (self.call_reads_seen.get(call)) |previous| {
            if (previous != present) self.invalidate(.changed_input);
            return;
        }
        if (self.call_reads.items.len >= self.max_reads) {
            self.invalidate(.read_limit);
            return;
        }
        try self.call_reads.ensureUnusedCapacity(a, 1);
        try self.call_reads_seen.put(a, call, present);
        self.call_reads.appendAssumeCapacity(.{ .target = target, .evidence = actual, .present = present });
    }
    pub fn summaryRead(self: *Recorder, a: Allocator, value: Summary) Allocator.Error!void {
        if (!self.eligible) return;
        if (self.summaries_seen.get(value.key) orelse self.summary_reads_seen.get(value.key)) |previous| {
            if (previous != value.result) self.invalidate(.changed_input);
            return;
        }
        if (self.summary_reads.items.len >= self.max_reads) {
            self.invalidate(.read_limit);
            return;
        }
        try self.summary_reads.ensureUnusedCapacity(a, 1);
        try self.summary_reads_seen.put(a, value.key, value.result);
        self.summary_reads.appendAssumeCapacity(value);
    }
    pub fn summaryPublish(self: *Recorder, a: Allocator, value: Summary) Allocator.Error!void {
        if (!self.eligible) return;
        if (self.summaries_seen.get(value.key)) |previous| {
            if (previous != value.result) self.invalidate(.changed_input);
            return;
        }
        if (self.summary_publications.items.len >= self.max_reads) {
            self.invalidate(.read_limit);
            return;
        }
        try self.summary_publications.ensureUnusedCapacity(a, 1);
        try self.summaries_seen.put(a, value.key, value.result);
        self.summary_publications.appendAssumeCapacity(value);
    }
    pub fn source(self: *Recorder, a: Allocator, target: core.BindingRef) Allocator.Error!void {
        if (!self.eligible or !self.source_complete) return;
        if (self.sources_seen.contains(target)) return;
        if (target.unit == 0 or target.binding == 0 or self.sources.items.len + self.source_units.items.len + self.interfaces.items.len >= self.max_reads) {
            self.source_complete = false;
            return;
        }
        try self.sources.ensureUnusedCapacity(a, 1);
        try self.sources_seen.put(a, target, {});
        self.sources.appendAssumeCapacity(target);
    }
    pub fn interface(self: *Recorder, a: Allocator, target: core.BindingRef) Allocator.Error!void {
        if (!self.eligible or !self.source_complete or self.interfaces_seen.contains(target)) return;
        if (target.unit == 0 or target.binding == 0 or self.sources.items.len + self.source_units.items.len + self.interfaces.items.len >= self.max_reads) {
            self.source_complete = false;
            return;
        }
        try self.interfaces.ensureUnusedCapacity(a, 1);
        try self.interfaces_seen.put(a, target, {});
        self.interfaces.appendAssumeCapacity(target);
    }
    pub fn sourceUnit(self: *Recorder, a: Allocator, unit: u32) Allocator.Error!void {
        if (!self.eligible or !self.source_complete or self.source_units_seen.contains(unit)) return;
        if (unit == 0 or self.sources.items.len + self.source_units.items.len + self.interfaces.items.len >= self.max_reads) {
            self.source_complete = false;
            return;
        }
        try self.source_units.ensureUnusedCapacity(a, 1);
        try self.source_units_seen.put(a, unit, {});
        self.source_units.appendAssumeCapacity(unit);
    }
    /// The borrowed key lives only until the next record or recorder teardown.
    pub fn key(self: *const Recorder) ?Key {
        return if (self.eligible) .{ .empty_call_inputs = self.empty_call_inputs, .source_complete = self.source_complete, .sources = self.sources.items, .interfaces = self.interfaces.items, .source_units = self.source_units.items, .scalar_reads = self.reads.items, .plain_reads = self.plain_reads.items, .plain_publications = self.plain_publications.items, .call_publications = self.call_publications.items, .call_reads = self.call_reads.items, .summary_reads = self.summary_reads.items, .summary_publications = self.summary_publications.items } else null;
    }
};
