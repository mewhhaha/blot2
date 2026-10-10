//! Complete selected judgments owned by one live Session. Immutable source,
//! evidence, record-layout and closure-mapping handles stay in that owner.
//! Capture handles never enter equality: graph ordinals preserve aliases, and
//! replay maps every input edge to the current graph before publishing facts.
const std = @import("std");
const inputs = @import("lexical_capture_inputs.zig");
const receipt = @import("specialization_receipt.zig");
const eval = @import("core_eval.zig");
const Allocator = std.mem.Allocator;

pub const Mode = enum { selected, inferred, entry };

const Entry = struct {
    mode: Mode,
    input: inputs.Inputs,
    proof: receipt.Record,
    values: []eval.ValueInfo,
    evidence: []u32,
    records: []u32,
    children: []u32,
    fixed: []u32,
};

pub const Cache = struct {
    buckets: std.AutoHashMapUnmanaged(u64, std.ArrayList(Entry)) = .empty,
    retained_words: usize = 0,
    examined_words: usize = 0,
    reused: usize = 0,
    enabled: bool = true,
    /// A collision law can exercise the exact equality path deterministically.
    force_collision: bool = false,
    pub fn deinit(self: *Cache, a: Allocator) void {
        var iterator = self.buckets.valueIterator();
        while (iterator.next()) |bucket| {
            for (bucket.items) |*entry| {
                entry.input.deinit(a);
                entry.proof.deinit(a);
                a.free(entry.values);
                a.free(entry.evidence);
                a.free(entry.records);
                a.free(entry.children);
                a.free(entry.fixed);
            }
            bucket.deinit(a);
        }
        self.buckets.deinit(a);
    }
    fn hash(self: *const Cache, words: []const u64) u64 {
        return if (self.force_collision) 0 else std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(words));
    }
    pub fn eligible(self: *const Cache, session: anytype, value: u32) bool {
        // Nested inquiries, unusual quotas and incomplete observation modes
        // retain their ordinary collector and its precise failure boundary.
        var ordinary = session.options;
        // Backend tracing modes are supported, but remain exact key inputs.
        // Nonstandard budgets and alternative reuse policies decline sharing.
        ordinary.trace_runtime_dependencies = false;
        ordinary.retain_source_suspensions = false;
        return self.enabled and session.receipt_tape == null and session.principal_reads == null and
            session.inquiry_regions == 0 and std.meta.eql(ordinary, eval.Options{}) and
            session.valueInfo(value).kind == .closure and
            self.examined_words < session.options.max_children and
            self.retained_words < session.options.max_children;
    }
    pub fn key(self: *Cache, session: anytype, value: u32) Allocator.Error!?inputs.Inputs {
        if (!self.eligible(session, value)) return null;
        session.counters.canonical_specialization_queries += 1;
        var examined: usize = 0;
        defer self.examined_words += examined;
        var result = try inputs.buildCanonicalBudget(session.allocator, session, value, session.options.max_children - self.examined_words, &examined) orelse return null;
        for (result.values) |id| switch (session.valueInfo(id).kind) {
            .scalar, .product, .record, .nominal, .array, .list, .cursor, .closure => {},
            else => {
                result.deinit(session.allocator);
                return null;
            },
        };
        return result;
    }
    pub fn remember(self: *Cache, session: anytype, input: inputs.Inputs, proof: receipt.Record, mode: Mode) Allocator.Error!void {
        const a = session.allocator;
        // Ownership always transfers, even when this optional proof declines.
        var owned_input = input;
        defer owned_input.deinit(a);
        if (!proof.complete or proof.steps != 0 or session.valueEvidence(proof.selected) == 0) return;
        const size = input.words.len +| input.values.len +| input.mappings.len *| 2 +| input.rows.len *| 2 +| input.slots.len *| 3 +|
            proof.values_added *| 4 +| proof.children_added +| proof.sources.len *| 2 +| proof.scalar_reads.len *| 3 +|
            proof.call_reads.len *| 4 +| proof.call_publications.len *| 4 +| proof.views.len *| 4 +| proof.plain_facts.len *| 3;
        if (size > session.options.max_children -| self.retained_words) return;
        for (session.values.items[proof.values_before..]) |value| switch (value.kind) {
            .scalar, .product, .record, .nominal, .array, .list, .cursor, .closure => {},
            // Creation and mutable demand/provider state need a stronger plan.
            else => return,
        };
        var entry: Entry = .{
            .mode = mode,
            .input = undefined,
            .proof = try proof.clone(a),
            .values = &.{},
            .evidence = &.{},
            .records = &.{},
            .children = &.{},
            .fixed = &.{},
        };
        errdefer {
            entry.proof.deinit(a);
            a.free(entry.values);
            a.free(entry.evidence);
            a.free(entry.records);
            a.free(entry.children);
            a.free(entry.fixed);
        }
        entry.values = try a.dupe(eval.ValueInfo, session.values.items[proof.values_before..]);
        entry.evidence = try a.dupe(u32, session.value_evidence.items[proof.values_before..]);
        entry.records = try a.dupe(u32, session.value_records.items[proof.values_before..]);
        entry.children = try a.dupe(u32, session.children.items[proof.children_before..]);
        var fixed: std.ArrayList(u32) = .empty;
        defer fixed.deinit(a);
        for (proof.values_before..session.values.items.len) |position| {
            const id: u32 = @intCast(position);
            if (session.valueInfo(id).kind == .closure and session.specialized_closures.get(.{ .value = id, .evidence = session.valueEvidence(id) }) == id)
                try fixed.append(a, id);
        }
        entry.fixed = try fixed.toOwnedSlice(a);
        const bucket = try self.buckets.getOrPut(a, self.hash(input.words));
        if (!bucket.found_existing) bucket.value_ptr.* = .empty;
        try bucket.value_ptr.ensureUnusedCapacity(a, 1);
        entry.input = owned_input;
        bucket.value_ptr.appendAssumeCapacity(entry);
        self.retained_words += size;
        // Cancel the input defer without borrowing a growable Session slice.
        owned_input.mappings = &.{};
        owned_input.rows = &.{};
        owned_input.slots = &.{};
        owned_input.words = &.{};
        owned_input.values = &.{};
    }
    pub fn lookup(self: *Cache, session: anytype, input: *const inputs.Inputs, expected: u32, mode: Mode) Allocator.Error!?u32 {
        const bucket = self.buckets.get(self.hash(input.words)) orelse return null;
        for (bucket.items) |*entry| {
            const proof = &entry.proof;
            if (entry.mode != mode or proof.expected != expected or proof.depth != session.depth or
                !std.meta.eql(proof.options, session.options) or
                !std.mem.eql(u64, entry.input.words, input.words)) continue;
            if (try replay(session, entry, input)) |selected| {
                self.reused += 1;
                session.counters.canonical_specialization_hits += 1;
                return selected;
            }
        }
        return null;
    }
};

fn mapped(anchors: std.AutoHashMapUnmanaged(u32, u32), proof: *const receipt.Record, before: u32, value: u32) u32 {
    if (value >= proof.values_before and value - proof.values_before < proof.values_added)
        return before + @as(u32, @intCast(value - proof.values_before));
    return anchors.get(value) orelse value;
}

fn unitIndex(session: anytype, unit: u32) ?usize {
    for (session.units, 0..) |module, index| if (module.unit == unit or (module.unit == 0 and index + 1 == unit)) return index;
    return null;
}

fn replay(session: anytype, entry: *const Entry, input: *const inputs.Inputs) Allocator.Error!?u32 {
    const a = session.allocator;
    const proof = &entry.proof;
    if (proof.values_added > session.options.max_values -| session.values.items.len or
        proof.children_added > session.options.max_children -| session.children.items.len) return null;
    var anchors: std.AutoHashMapUnmanaged(u32, u32) = .empty;
    defer anchors.deinit(a);
    for (entry.input.values, input.values) |old, current| try anchors.put(a, old, current);
    // Revalidate each observed persistent fact before allocating visible output.
    for (proof.scalar_reads) |read| {
        var owner: ?usize = null;
        for (session.units, 0..) |module, index| if (module.unit == read.target.unit or (module.unit == 0 and index + 1 == read.target.unit)) {
            owner = index;
            break;
        };
        const index = owner orelse return null;
        const body = session.units[index].body(read.target.binding) orelse return null;
        const slot = session.slots[session.binding_offsets[index] + read.target.binding];
        const actual = if (!body.runtime and slot.state == .complete and session.valueInfo(slot.value).kind == .scalar) session.valueEvidence(slot.value) else 0;
        if (actual != read.evidence) return null;
    }
    for (proof.call_reads) |read| {
        const owner = unitIndex(session, read.unit) orelse return null;
        if (session.validated_calls.contains(.{ .target = .{ .unit = owner, .binding = read.binding }, .evidence = read.evidence }) != read.present) return null;
    }
    for (proof.call_publications) |call| if (unitIndex(session, call.unit) == null) return null;
    var plain: std.AutoHashMapUnmanaged(u64, bool) = .empty;
    defer plain.deinit(a);
    for (proof.plain_facts) |fact| {
        if (fact.read) {
            const actual = plain.get(fact.key) orelse session.plain_nominals.get(fact.key);
            if (fact.present) {
                if (actual == null or actual.? != fact.plain) return null;
            } else if (actual != null) return null;
        } else try plain.put(a, fact.key, fact.plain);
    }
    for (proof.views) |view| if (view.value < proof.values_before) {
        const base = anchors.get(view.value) orelse view.value;
        const existing = session.typed_views.get(.{ .value = base, .evidence = view.evidence });
        if (view.existed) {
            if (existing != (anchors.get(view.selected) orelse view.selected)) return null;
        } else if (existing != null) return null;
    };
    const before: u32 = @intCast(session.values.items.len);
    const child_before: u32 = @intCast(session.children.items.len);
    const values = try a.dupe(eval.ValueInfo, entry.values);
    defer a.free(values);
    // Shared input child spans must follow the current input, just like edges.
    for (values) |*value| {
        if (value.len == 0) continue;
        if (value.start >= proof.children_before) {
            value.start = child_before + @as(u32, @intCast(value.start - proof.children_before));
            continue;
        }
        var found = false;
        for (entry.input.values, input.values) |old, current| {
            const old_info = session.valueInfo(old);
            if (old_info.start == value.start and old_info.len == value.len) {
                value.start = session.valueInfo(current).start;
                found = true;
                break;
            }
        }
        if (!found) for (session.children.items[value.start..][0..value.len]) |child| if ((anchors.get(child) orelse child) != child) return null;
    }
    // Reserve every publication first. Allocation failure changes capacities
    // only; graph lengths, facts and proof memos remain untouched.
    try session.values.ensureUnusedCapacity(a, values.len);
    try session.value_evidence.ensureUnusedCapacity(a, values.len);
    try session.value_records.ensureUnusedCapacity(a, values.len);
    try session.children.ensureUnusedCapacity(a, entry.children.len);
    try session.typed_views.ensureUnusedCapacity(a, @intCast(proof.views.len));
    try session.validated_calls.ensureUnusedCapacity(a, @intCast(proof.call_publications.len));
    try session.plain_nominals.ensureUnusedCapacity(a, plain.count());
    try session.specialized_closures.ensureUnusedCapacity(a, @intCast(entry.fixed.len + 2));
    var next: ?receipt.Record = null;
    defer if (next) |*owned| owned.deinit(a);
    if (session.retain_specialization_receipts and entry.mode == .selected) {
        try session.specialization_receipts.ensureUnusedCapacity(a, 1);
        next = try proof.clone(a);
        next.?.input = input.values[0];
        next.?.selected = mapped(anchors, proof, before, proof.selected);
        next.?.values_before = before;
        next.?.children_before = child_before;
        for (next.?.views) |*view| {
            view.value = mapped(anchors, proof, before, view.value);
            view.selected = mapped(anchors, proof, before, view.selected);
        }
    }
    session.values.appendSliceAssumeCapacity(values);
    session.value_evidence.appendSliceAssumeCapacity(entry.evidence);
    session.value_records.appendSliceAssumeCapacity(entry.records);
    for (entry.children) |child| session.children.appendAssumeCapacity(mapped(anchors, proof, before, child));
    for (proof.views) |view| if (!view.existed) session.typed_views.putAssumeCapacity(.{ .value = mapped(anchors, proof, before, view.value), .evidence = view.evidence }, mapped(anchors, proof, before, view.selected));
    for (proof.call_publications) |call| {
        const key: eval.CallProofKey = .{ .target = .{ .unit = unitIndex(session, call.unit).?, .binding = call.binding }, .evidence = call.evidence };
        if (!session.validated_calls.contains(key)) session.proofs.proof_published += 1;
        session.validated_calls.putAssumeCapacity(key, {});
    }
    var facts = plain.iterator();
    while (facts.next()) |fact| session.plain_nominals.putAssumeCapacity(fact.key_ptr.*, fact.value_ptr.*);
    const selected = mapped(anchors, proof, before, proof.selected);
    session.specialized_closures.putAssumeCapacity(.{ .value = input.values[0], .evidence = proof.expected, .entry_interface = entry.mode == .entry }, selected);
    if (entry.mode == .selected) session.specialized_closures.putAssumeCapacity(.{ .value = selected, .evidence = proof.expected }, selected);
    for (entry.fixed) |old| {
        const current = mapped(anchors, proof, before, old);
        session.specialized_closures.putAssumeCapacity(.{ .value = current, .evidence = session.valueEvidence(current) }, current);
    }
    if (next) |owned| {
        session.specialization_receipts.appendAssumeCapacity(owned);
        next = null;
    }
    for (proof.call_reads) |read| if (read.present) {
        session.proofs.proof_reused += 1;
    };
    return selected;
}
