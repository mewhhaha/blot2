//! Complete selected judgments owned by one live Session. Immutable source,
//! evidence, record-layout and closure-mapping handles stay in that owner.
//! Capture handles never enter equality: graph ordinals preserve aliases, and
//! replay maps every input edge to the current graph before publishing facts.
const std = @import("std");
const inputs = @import("lexical_capture_inputs.zig");
const receipt = @import("../reuse/specialization_receipt.zig");
const eval = @import("core_eval.zig");
const Allocator = std.mem.Allocator;

pub const Mode = enum { selected, inferred, entry };

const queries = @import("../reuse/semantic_query_table.zig");
const Key = struct {
    mode: Mode,
    input: inputs.Inputs,
    fingerprint_: u64,
    expected: u32,
    options: eval.Options,
    depth: usize,
    pub fn deinit(self: *Key, a: Allocator) void {
        self.input.deinit(a);
    }
};
const Replay = struct {
    selected: u32,
    values: []eval.ValueInfo = &.{},
    evidence: []u32 = &.{},
    records: []u32 = &.{},
    children: []u32 = &.{},
    fixed: []u32 = &.{},
    pub fn deinit(self: *Replay, a: Allocator) void {
        inline for (.{ "values", "evidence", "records", "children", "fixed" }) |field| a.free(@field(self, field));
    }
};
pub const Adapter = struct {
    pub const kind: queries.Kind = .specialization;
    pub const Key = @import("canonical_specialization.zig").Key;
    pub const Dependencies = receipt.Record;
    pub const Result = Replay;
    pub fn fingerprint(key_: @This().Key) u64 {
        return key_.fingerprint_;
    }
    pub fn complete(record: Entry) bool {
        const proof = record.dependencies;
        return proof.complete and proof.steps == 0 and proof.expected == record.key.expected and proof.selected == record.value.selected and
            proof.depth == record.key.depth and std.meta.eql(proof.options, record.key.options) and
            proof.values_added == record.value.values.len and proof.children_added == record.value.children.len and
            record.value.evidence.len == record.value.values.len and record.value.records.len == record.value.values.len;
    }
    pub fn bytes(record: Entry) usize {
        var total = receipt.ownedBytes(record.dependencies);
        inline for (.{ "words", "values", "mappings", "rows", "slots" }) |field| {
            const entries = @field(record.key.input, field);
            total +|= entries.len *| @sizeOf(@TypeOf(entries[0]));
        }
        inline for (.{ "values", "evidence", "records", "children", "fixed" }) |field| {
            const entries = @field(record.value, field);
            total +|= entries.len *| @sizeOf(@TypeOf(entries[0]));
        }
        return total;
    }
};
pub const Table = queries.Table(Adapter);
const Entry = Table.Record;

pub const Cache = struct {
    table: Table = .{},
    retained_words: usize = 0,
    examined_words: usize = 0,
    reused: usize = 0,
    enabled: bool = true,
    /// A collision law can exercise the exact equality path deterministically.
    force_collision: bool = false,
    pub fn deinit(self: *Cache, a: Allocator) void {
        self.table.deinit(a);
    }
    fn hash(self: *const Cache, words: []const u64, expected: u32, mode: Mode, options: eval.Options, depth: usize) u64 {
        if (self.force_collision) return 0;
        var value = std.hash.Wyhash.init(0);
        value.update(std.mem.sliceAsBytes(words));
        std.hash.autoHash(&value, .{ expected, mode, options, depth });
        return value.final();
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
        var owns_input = true;
        defer if (owns_input) owned_input.deinit(a);
        if (!proof.complete or proof.steps != 0 or session.valueEvidence(proof.selected) == 0) return;
        const size = input.words.len +| input.values.len +| input.mappings.len *| 2 +| input.rows.len *| 2 +| input.slots.len *| 3 +|
            proof.values_added *| 4 +| proof.children_added +| proof.sources.len *| 2 +| proof.scalar_reads.len *| 3 +|
            proof.call_reads.len *| 4 +| proof.call_publications.len *| 4 +| proof.views.len *| 4 +| proof.plain_facts.len *| 3;
        if (size > session.options.max_children -| self.retained_words) return;
        var minimum_bytes = receipt.ownedBytes(proof);
        inline for (.{ "words", "values", "mappings", "rows", "slots" }) |field| {
            const values = @field(input, field);
            minimum_bytes +|= values.len *| @sizeOf(@TypeOf(values[0]));
        }
        minimum_bytes +|= proof.values_added *| (@sizeOf(eval.ValueInfo) + 2 * @sizeOf(u32));
        minimum_bytes +|= proof.children_added *| @sizeOf(u32);
        if (!self.table.canAdmit(minimum_bytes)) {
            self.table.saturated +|= 1;
            return;
        }
        for (session.storage.values.items[proof.values_before..]) |value| switch (value.kind) {
            .scalar, .product, .record, .nominal, .array, .list, .cursor, .closure => {},
            // Creation and mutable demand/provider state need a stronger plan.
            else => return,
        };
        var result: Replay = .{ .selected = proof.selected };
        var owns_result = true;
        defer if (owns_result) result.deinit(a);
        result.values = try a.dupe(eval.ValueInfo, session.storage.values.items[proof.values_before..]);
        result.evidence = try a.dupe(u32, session.storage.value_evidence.items[proof.values_before..]);
        result.records = try a.dupe(u32, session.storage.value_records.items[proof.values_before..]);
        result.children = try a.dupe(u32, session.storage.children.items[proof.children_before..]);
        var fixed: std.ArrayList(u32) = .empty;
        defer fixed.deinit(a);
        for (proof.values_before..session.storage.values.items.len) |position| {
            const id: u32 = @intCast(position);
            if (session.valueInfo(id).kind == .closure and session.storage.specialized_closures.get(.{ .value = id, .evidence = session.valueEvidence(id) }) == id)
                try fixed.append(a, id);
        }
        result.fixed = try fixed.toOwnedSlice(a);
        var builder = Table.begin(a, .{ .mode = mode, .input = owned_input, .fingerprint_ = self.hash(input.words, proof.expected, mode, proof.options, proof.depth), .expected = proof.expected, .options = proof.options, .depth = proof.depth });
        owns_input = false;
        defer builder.abort();
        builder.read(try proof.clone(a));
        builder.stage(result);
        owns_result = false;
        var candidate = builder.complete() orelse return;
        defer candidate.abort();
        const prepared = try self.table.prepare(a, &candidate) orelse return;
        _ = self.table.publish(prepared, &candidate);
        self.retained_words += size;
    }
    pub fn lookup(self: *Cache, session: anytype, input: *const inputs.Inputs, expected: u32, mode: Mode) Allocator.Error!?u32 {
        session.counters.canonical_specialization_lookups += 1;
        var cursor = self.table.candidates(self.hash(input.words, expected, mode, session.options, session.depth), .oldest_first);
        while (cursor.next()) |position| {
            session.counters.canonical_specialization_candidates += 1;
            const entry = &self.table.records.items[position];
            const proof = &entry.dependencies;
            if (entry.key.mode != mode or proof.expected != expected or proof.depth != session.depth or
                !std.meta.eql(proof.options, session.options) or
                !std.mem.eql(u64, entry.key.input.words, input.words)) continue;
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
    if (comptime @hasDecl(@TypeOf(session.*), "unitIndex")) return session.unitIndex(unit);
    for (session.units, 0..) |module, index| if (module.unit == unit or (module.unit == 0 and index + 1 == unit)) return index;
    return null;
}

fn replay(session: anytype, entry: *const Entry, input: *const inputs.Inputs) Allocator.Error!?u32 {
    const a = session.allocator;
    const proof = &entry.dependencies;
    if (proof.values_added > session.options.max_values -| session.storage.values.items.len or
        proof.children_added > session.options.max_children -| session.storage.children.items.len) return null;
    var anchors: std.AutoHashMapUnmanaged(u32, u32) = .empty;
    defer anchors.deinit(a);
    for (entry.key.input.values, input.values) |old, current| try anchors.put(a, old, current);
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
        if (session.specializations.validated_calls.contains(.{ .target = .{ .unit = owner, .binding = read.binding }, .evidence = read.evidence }) != read.present) return null;
    }
    for (proof.call_publications) |call| if (unitIndex(session, call.unit) == null) return null;
    var plain: std.AutoHashMapUnmanaged(u64, bool) = .empty;
    defer plain.deinit(a);
    for (proof.plain_facts) |fact| {
        if (fact.read) {
            const actual = plain.get(fact.key) orelse session.specializations.plain_nominals.get(fact.key);
            if (fact.present) {
                if (actual == null or actual.? != fact.plain) return null;
            } else if (actual != null) return null;
        } else try plain.put(a, fact.key, fact.plain);
    }
    for (proof.views) |view| if (view.value < proof.values_before) {
        const base = anchors.get(view.value) orelse view.value;
        const existing = session.storage.typed_views.get(.{ .value = base, .evidence = view.evidence });
        if (view.existed) {
            if (existing != (anchors.get(view.selected) orelse view.selected)) return null;
        } else if (existing != null) return null;
    };
    const before: u32 = @intCast(session.storage.values.items.len);
    const child_before: u32 = @intCast(session.storage.children.items.len);
    const values = try a.dupe(eval.ValueInfo, entry.value.values);
    defer a.free(values);
    // Shared input child spans must follow the current input, just like edges.
    for (values) |*value| {
        if (value.len == 0) continue;
        if (value.start >= proof.children_before) {
            value.start = child_before + @as(u32, @intCast(value.start - proof.children_before));
            continue;
        }
        var found = false;
        for (entry.key.input.values, input.values) |old, current| {
            const old_info = session.valueInfo(old);
            if (old_info.start == value.start and old_info.len == value.len) {
                value.start = session.valueInfo(current).start;
                found = true;
                break;
            }
        }
        if (!found) for (session.storage.children.items[value.start..][0..value.len]) |child| if ((anchors.get(child) orelse child) != child) return null;
    }
    // Reserve every publication first. Allocation failure changes capacities
    // only; graph lengths, facts and proof memos remain untouched.
    try session.storage.values.ensureUnusedCapacity(a, values.len);
    try session.storage.value_evidence.ensureUnusedCapacity(a, values.len);
    try session.storage.value_records.ensureUnusedCapacity(a, values.len);
    try session.storage.children.ensureUnusedCapacity(a, entry.value.children.len);
    try session.storage.typed_views.ensureUnusedCapacity(a, @intCast(proof.views.len));
    try session.specializations.validated_calls.ensureUnusedCapacity(a, @intCast(proof.call_publications.len));
    try session.specializations.plain_nominals.ensureUnusedCapacity(a, plain.count());
    try session.storage.specialized_closures.ensureUnusedCapacity(a, @intCast(entry.value.fixed.len + 2));
    var next: ?receipt.Record = null;
    defer if (next) |*owned| owned.deinit(a);
    if (session.retain_specialization_receipts and entry.key.mode == .selected) {
        try session.retained.specialization_receipts.ensureUnusedCapacity(a, 1);
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
    session.storage.values.appendSliceAssumeCapacity(values);
    session.storage.value_evidence.appendSliceAssumeCapacity(entry.value.evidence);
    session.storage.value_records.appendSliceAssumeCapacity(entry.value.records);
    for (entry.value.children) |child| session.storage.children.appendAssumeCapacity(mapped(anchors, proof, before, child));
    for (proof.views) |view| if (!view.existed) session.storage.typed_views.putAssumeCapacity(.{ .value = mapped(anchors, proof, before, view.value), .evidence = view.evidence }, mapped(anchors, proof, before, view.selected));
    for (proof.call_publications) |call| {
        const key: eval.CallProofKey = .{ .target = .{ .unit = unitIndex(session, call.unit).?, .binding = call.binding }, .evidence = call.evidence };
        if (!session.specializations.validated_calls.contains(key)) session.proofs.proof_published += 1;
        session.specializations.validated_calls.putAssumeCapacity(key, {});
    }
    var facts = plain.iterator();
    while (facts.next()) |fact| session.specializations.plain_nominals.putAssumeCapacity(fact.key_ptr.*, fact.value_ptr.*);
    const selected = mapped(anchors, proof, before, proof.selected);
    session.storage.specialized_closures.putAssumeCapacity(.{ .value = input.values[0], .evidence = proof.expected, .entry_interface = entry.key.mode == .entry }, selected);
    if (entry.key.mode == .selected) session.storage.specialized_closures.putAssumeCapacity(.{ .value = selected, .evidence = proof.expected }, selected);
    for (entry.value.fixed) |old| {
        const current = mapped(anchors, proof, before, old);
        session.storage.specialized_closures.putAssumeCapacity(.{ .value = current, .evidence = session.valueEvidence(current) }, current);
    }
    if (next) |owned| {
        session.retained.specialization_receipts.appendAssumeCapacity(owned);
        next = null;
    }
    for (proof.call_reads) |read| if (read.present) {
        session.proofs.proof_reused += 1;
    };
    return selected;
}
