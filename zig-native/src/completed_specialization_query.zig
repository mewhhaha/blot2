//! PRIVATE exact completed specialization, never a principal or startup proof.
const std = @import("std");
const eval = @import("core_eval.zig");
const core = @import("core.zig");
const capture = @import("artifact_capture.zig");
const admission = @import("principal_reuse_gate.zig");
const graph = @import("source_value_template.zig");
const importer = @import("artifact_import.zig");
const receipt = @import("specialization_receipt.zig");
const identity = @import("runtime_identity.zig");
const independent = @import("independent_call_proof.zig");
const Allocator = std.mem.Allocator;
pub const Reason = enum { mode, source, domain, expected, input, scalar, call, view, plain, resource, imported };
pub const Stats = struct {
    independent_rechecked: usize = 0,
    independent_reused: usize = 0,
    independent_declined: usize = 0,
    parallel_batches: usize = 0,
    parallel_jobs: usize = 0,
    parallel_workers: usize = 1,
    recorded: usize = 0,
    complete_records: usize = 0,
    lookups: usize = 0,
    candidates: usize = 0,
    reused: usize = 0,
    reasons: [@typeInfo(Reason).@"enum".field_names.len]usize = @splat(0),
    collected_visits_removed: usize = 0,
    source_scopes_removed: usize = 0,
    solver_nodes_removed: usize = 0,
    values_imported: usize = 0,
    plain_revalidated: usize = 0,
    enumerated_records: usize = 0,
    root_preflight_declined: usize = 0,
    owner_importers: usize = 0,
    prepared_importers: usize = 0,
    fresh_importers: usize = 0,
    shared_gates: usize = 0,
    gate_fresh: usize = 0,
    /// Validation arrays borrowed by this lease, not additional allocated bytes.
    shared_gate_bytes: usize = 0,
    plan_inspections: usize = 0,
    plan_cache_hits: usize = 0,
    graph_scratch: graph.ScratchStats = .{},
};
const SourceKey = struct { unit: u32, identity: u32, origin: eval.ClosureOrigin, applied: u32 };
const CachedPlan = struct { checked: bool = false, plan: ?graph.Plan = null };
pub const State = struct {
    allocator: Allocator,
    old: *const capture.Capture,
    gate: admission.Gate,
    stats: Stats = .{},
    independent_calls: std.ArrayList(independent.Record) = .empty,
    /// PRIVATE execution policy, outside semantic Session.Options. The old
    /// Capture/receipts and current Core/Gate are immutable until deinit.
    recover_call_proofs: bool = true,
    io: ?std.Io = null,
    semantic_workers: u8 = 1,
    revalidate_plain_facts: bool = true,
    graph_scratch: graph.QueryScratch,
    buckets: std.AutoHashMapUnmanaged(SourceKey, std.ArrayList(usize)) = .empty,
    plans: ?[]CachedPlan = null,
    semantic: ?importer.Importer = null,
    state_owner: ?usize = null,
    generator_owner: ?usize = null,
    session_owner: ?usize = null,
    pub fn init(a: Allocator, old: *const capture.Capture, units: []const core.Module, names: ?identity.View) Allocator.Error!State {
        return .{ .allocator = a, .old = old, .graph_scratch = .{ .allocator = a }, .gate = try admission.Gate.init(a, &old.metadata.pools.?, units, names) };
    }
    pub fn deinit(self: *State) void {
        for (self.independent_calls.items) |*record| record.deinit(self.allocator);
        self.independent_calls.deinit(self.allocator);
        self.graph_scratch.deinit();
        if (self.semantic) |*maps| maps.deinit();
        if (self.plans) |plans| {
            for (plans) |*cached| if (cached.plan) |*plan| plan.deinit(self.allocator);
            self.allocator.free(plans);
        }
        var buckets = self.buckets.valueIterator();
        while (buckets.next()) |bucket| bucket.deinit(self.allocator);
        self.buckets.deinit(self.allocator);
        self.gate.deinit();
    }
    fn sourceKey(value: eval.ClosureValue) SourceKey {
        return .{ .unit = value.unit, .identity = value.identity, .origin = value.origin, .applied = value.applied };
    }
    fn index(self: *State) Allocator.Error!void {
        if (self.plans != null) return;
        var buckets: std.AutoHashMapUnmanaged(SourceKey, std.ArrayList(usize)) = .empty;
        errdefer {
            var entries = buckets.valueIterator();
            while (entries.next()) |bucket| bucket.deinit(self.allocator);
            buckets.deinit(self.allocator);
        }
        const pools = &self.old.metadata.pools.?;
        for (self.old.metadata.specialization_receipts.items, 0..) |record, position| {
            if (record.input >= pools.evaluator.values.len) continue;
            const value = pools.evaluator.values[record.input];
            if (value.kind != .closure or value.bits >= pools.evaluator.closures.len) continue;
            const entry = try buckets.getOrPut(self.allocator, sourceKey(pools.evaluator.closures[value.bits]));
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            // Appending in original receipt order preserves first-match order.
            try entry.value_ptr.append(self.allocator, position);
        }
        const plans = try self.allocator.alloc(CachedPlan, self.old.metadata.specialization_receipts.items.len);
        @memset(plans, .{});
        self.buckets = buckets;
        self.plans = plans;
    }
    pub fn pairedImporter(self: *State) Allocator.Error!*importer.Importer {
        if (self.semantic == null) {
            const pools = &self.old.metadata.pools.?;
            const prepared = try importer.Importer.initCheckedQuery(self.allocator, pools, self.gate.units, &self.gate);
            const maps = prepared orelse try importer.Importer.init(self.allocator, pools, self.gate.units, pools.identity.?.view(), self.gate.units.len);
            for (maps.stable, self.gate.structural_units) |*stable, exact| stable.* = exact;
            self.semantic = maps;
            self.stats.owner_importers += 1;
            if (prepared != null) self.stats.prepared_importers += 1 else self.stats.fresh_importers += 1;
        }
        return &self.semantic.?;
    }
    fn cachedPlan(self: *State, position: usize) Allocator.Error!?*graph.Plan {
        const cached = &self.plans.?[position];
        if (cached.checked) {
            self.stats.plan_cache_hits += 1;
            return if (cached.plan) |*plan| plan else null;
        }
        const record = &self.old.metadata.specialization_receipts.items[position];
        var roots: std.ArrayList(u32) = .empty;
        defer roots.deinit(self.allocator);
        try roots.appendSlice(self.allocator, &.{ record.selected, record.input });
        for (record.views) |view| try roots.appendSlice(self.allocator, &.{ view.value, view.selected });
        const inspection = try graph.Plan.inspectRootsWithRows(self.allocator, &self.old.metadata.pools.?, &self.gate, roots.items, .source_declared);
        self.stats.plan_inspections += 1;
        cached.plan = inspection.plan;
        cached.checked = true;
        return if (cached.plan) |*plan| plan else null;
    }
    fn rootMatches(self: *const State, g: anytype, old_input: u32, input: u32) bool {
        const snapshot = &self.old.metadata.pools.?.evaluator;
        const left = snapshot.values[old_input];
        const right = g.evaluator.valueInfo(input);
        const before = snapshot.closures[left.bits];
        const current = g.evaluator.closureInfo(input);
        // These are necessary exact predicates from matchesAnchor, not a
        // certificate. All evidence/capture/alias/state checks still follow.
        if (left.scalar != right.scalar or left.nominal != right.nominal or left.len != right.len or before.ty != current.ty or before.mappings.len != current.mappings.len or before.row_mappings.len != current.row_mappings.len) return false;
        if ((snapshot.value_evidence[old_input] == 0) != (g.evaluator.valueEvidence(input) == 0)) return false;
        const old_types = snapshot.type_mappings[before.mappings.start..][0..before.mappings.len];
        const current_types = g.evaluator.type_mappings.items[current.mappings.start..][0..current.mappings.len];
        for (old_types, current_types) |prior, fresh| if (prior.variable != fresh.variable) return false;
        for (snapshot.row_mappings[before.row_mappings.start..][0..before.row_mappings.len], g.evaluator.row_mappings.items[current.row_mappings.start..][0..current.row_mappings.len]) |prior, fresh| {
            if (prior.variable != fresh.variable) return false;
            // Rich row IDs belong to separate semantic owners; matchInto
            // compares imported operation identities and arguments afterward.
        }
        return true;
    }
    fn reject(self: *State, reason: Reason) void {
        self.stats.reasons[@backingInt(reason)] += 1;
    }
    fn evidence(g: anytype, maps: *importer.Importer, old: u32) Allocator.Error!?u32 {
        return if (old == 0) @as(u32, 0) else try maps.importEvidence(g, old);
    }
    pub fn lookup(self: *State, g: anytype, input: u32, expected: u32) Allocator.Error!?u32 {
        defer self.stats.graph_scratch = self.graph_scratch.stats;
        self.stats.lookups += 1;
        if (!self.gate.enabled or g.evaluator.units.ptr != self.gate.units.ptr or g.evaluator.units.len != self.gate.units.len or self.allocator.ptr != g.evaluator.allocator.ptr or self.allocator.vtable != g.evaluator.allocator.vtable) return null;
        if (input >= g.evaluator.values.items.len or g.evaluator.valueInfo(input).kind != .closure or expected == 0 or expected >= g.evaluator.evidence.nodes.items.len or g.evaluator.evidence.node(expected).tag != .function) return null;
        const current = g.evaluator.closureInfo(input);
        const pools = &self.old.metadata.pools.?;
        const ordinary = eval.Options{};
        // Exact low-quota/error/depth behavior stays on the ordinary collector.
        if (g.evaluator.options.max_values != ordinary.max_values or g.evaluator.options.max_children != ordinary.max_children or g.evaluator.options.max_depth != ordinary.max_depth or g.evaluator.options.max_type_depth != ordinary.max_type_depth or g.evaluator.options.max_steps != ordinary.max_steps) {
            self.reject(.resource);
            return null;
        }
        if (self.state_owner) |owner| if (owner != @intFromPtr(self)) return null;
        if (self.generator_owner) |owner| if (owner != @intFromPtr(g)) return null;
        if (self.session_owner) |owner| if (owner != @intFromPtr(&g.evaluator)) return null;
        // The session already owns this answer. Replaying its publication a
        // second time would allocate another graph and replace the memo.
        if (g.evaluator.specialized_closures.contains(.{ .value = input, .evidence = expected })) return null;
        self.state_owner = @intFromPtr(self);
        self.generator_owner = @intFromPtr(g);
        self.session_owner = @intFromPtr(&g.evaluator);
        try self.index();
        const records = self.old.metadata.specialization_receipts.items;
        const bucket = self.buckets.get(sourceKey(current)) orelse return null;
        for (bucket.items) |position| {
            const record = &records[position];
            self.stats.enumerated_records += 1;
            if (record.input >= pools.evaluator.values.len or pools.evaluator.values[record.input].kind != .closure) continue;
            const old_source = pools.evaluator.closures[pools.evaluator.values[record.input].bits];
            if (old_source.unit != current.unit or old_source.identity != current.identity or old_source.origin != current.origin or old_source.applied != current.applied) continue;
            self.stats.candidates += 1;
            if (!record.complete or record.steps != 0 or record.depth != g.evaluator.depth or !std.meta.eql(record.options, g.evaluator.options)) {
                self.reject(.mode);
                continue;
            }
            if (g.evaluator.values.items.len > g.evaluator.options.max_values or record.values_added > g.evaluator.options.max_values - g.evaluator.values.items.len or g.evaluator.children.items.len > g.evaluator.options.max_children or record.children_added > g.evaluator.options.max_children - g.evaluator.children.items.len) {
                self.reject(.resource);
                continue;
            }
            if (!self.gate.admitsReceipt(record)) {
                self.reject(.source);
                continue;
            }
            if (!self.rootMatches(g, record.input, input)) {
                self.stats.root_preflight_declined += 1;
                self.reject(.input);
                continue;
            }
            const maps = try self.pairedImporter();
            if (!maps.enabled) {
                self.reject(.source);
                continue;
            }
            for (maps.stable, self.gate.structural_units) |*stable, exact| stable.* = exact;
            if ((try evidence(g, maps, record.expected)) != expected) {
                self.reject(.expected);
                continue;
            }
            const plan = (try self.cachedPlan(position)) orelse {
                self.reject(.domain);
                continue;
            };
            const anchors = self.graph_scratch.begin(plan, g) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Declined => {
                    self.reject(.source);
                    continue;
                },
            };
            const input_match = plan.matchIntoWithScratch(g, maps, record.input, input, anchors, &self.graph_scratch);
            if (!(input_match catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Declined => false,
            })) {
                self.reject(.input);
                continue;
            }
            var valid = true;
            for (record.scalar_reads) |read| {
                const module = &self.gate.units[read.target.unit - 1];
                const body = module.body(read.target.binding).?;
                const slot = g.evaluator.slots[g.evaluator.binding_offsets[read.target.unit - 1] + read.target.binding];
                const actual = if (!body.runtime and slot.state == .complete and g.evaluator.valueInfo(slot.value).kind == .scalar) g.evaluator.valueEvidence(slot.value) else 0;
                if ((try evidence(g, maps, read.evidence)) != actual) {
                    valid = false;
                    break;
                }
            }
            if (!valid) {
                self.reject(.scalar);
                continue;
            }
            var proofs: std.ArrayList(independent.Record) = .empty;
            defer {
                for (proofs.items) |*proof| proof.deinit(self.allocator);
                proofs.deinit(self.allocator);
            }
            var batch = try self.prepareCallProofs(g, maps, record.call_reads);
            defer if (batch) |*parallel| parallel.deinit();
            for (record.call_reads, 0..) |read, read_index| {
                const actual = (try evidence(g, maps, read.evidence)) orelse {
                    valid = false;
                    break;
                };
                const key: eval.CallProofKey = .{ .target = .{ .unit = read.unit - 1, .binding = read.binding }, .evidence = actual };
                var present = g.evaluator.validated_calls.contains(key);
                if (!present) for (proofs.items) |proof| {
                    if (std.meta.eql(proof.target, core.BindingRef{ .unit = read.unit, .binding = read.binding }) and proof.evidence == actual) {
                        present = true;
                        break;
                    }
                };
                if (!present and read.present and self.recover_call_proofs) {
                    const recovered = if (batch != null and batch.?.attempted(read_index)) batch.?.take(read_index, &self.stats) else try independent.acquire(self, g, read, actual);
                    if (recovered) |proof| {
                        var owned = proof;
                        errdefer owned.deinit(self.allocator);
                        try proofs.append(self.allocator, owned);
                        present = true;
                    }
                }
                if (present != read.present) {
                    valid = false;
                    break;
                }
            }
            if (!valid) {
                self.reject(.call);
                continue;
            }
            for (record.views) |view| if (view.value < record.values_before) {
                if (view.value != 0 and anchors[view.value] == 0) {
                    valid = false;
                    break;
                }
                const actual = (try evidence(g, maps, view.evidence)) orelse {
                    valid = false;
                    break;
                };
                const existing = g.evaluator.typed_views.get(.{ .value = anchors[view.value], .evidence = actual });
                if (view.existed) {
                    const selected = existing orelse {
                        valid = false;
                        break;
                    };
                    const view_match = plan.matchIntoWithScratch(g, maps, view.selected, selected, anchors, &self.graph_scratch);
                    if (!(view_match catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        error.Declined => false,
                    })) {
                        valid = false;
                        break;
                    }
                } else if (existing != null) {
                    valid = false;
                    break;
                }
            };
            if (!valid) {
                self.reject(.view);
                continue;
            }
            var plain: std.AutoHashMapUnmanaged(u64, bool) = .empty;
            defer plain.deinit(self.allocator);
            for (record.plain_facts) |fact| {
                const unit: u32 = @intCast(fact.key >> 32);
                if (unit == 0 or unit > self.gate.units.len or !self.gate.structural_units[unit - 1]) {
                    valid = false;
                    break;
                }
                if (fact.read) {
                    var present = plain.get(fact.key) orelse g.evaluator.plain_nominals.get(fact.key);
                    if (self.revalidate_plain_facts and present == null and fact.present and fact.plain and
                        @import("plain_catalog.zig").prove(self.gate.units, unit, @truncate(fact.key), g.evaluator.options.max_type_depth))
                    {
                        // This immutable source fact is safe to rederive. Stage
                        // it locally; publish only after the whole query commits.
                        // Existing negatives and absence reads stay authoritative.
                        try plain.put(self.allocator, fact.key, true);
                        present = true;
                        self.stats.plain_revalidated += 1;
                    }
                    if (fact.present) {
                        if (present == null or present.? != fact.plain) {
                            valid = false;
                            break;
                        }
                    } else if (present != null) {
                        valid = false;
                        break;
                    }
                } else try plain.put(self.allocator, fact.key, fact.plain);
            }
            if (!valid) {
                self.reject(.plain);
                continue;
            }
            // Prepare all semantic keys and map capacity before graph publication.
            const view_evidence = try self.allocator.alloc(u32, record.views.len);
            defer self.allocator.free(view_evidence);
            for (record.views, view_evidence) |view, *actual| actual.* = (try evidence(g, maps, view.evidence)) orelse {
                valid = false;
                break;
            };
            const calls = try self.allocator.alloc(u32, record.call_publications.len);
            defer self.allocator.free(calls);
            for (record.call_publications, calls) |call, *actual| actual.* = (try evidence(g, maps, call.evidence)) orelse {
                valid = false;
                break;
            };
            if (!valid) {
                self.reject(.domain);
                continue;
            }
            try g.evaluator.typed_views.ensureUnusedCapacity(self.allocator, @intCast(record.views.len));
            try g.evaluator.validated_calls.ensureUnusedCapacity(self.allocator, @intCast(record.call_publications.len + proofs.items.len));
            const collect_proofs = self.semantic_workers > 1;
            if (collect_proofs) try self.independent_calls.ensureUnusedCapacity(self.allocator, proofs.items.len);
            try g.evaluator.plain_nominals.ensureUnusedCapacity(self.allocator, @intCast(plain.count()));
            try g.evaluator.specialized_closures.ensureUnusedCapacity(self.allocator, 1);
            var next = try record.clone(self.allocator);
            var next_owned = true;
            defer if (next_owned) next.deinit(self.allocator);
            for (next.scalar_reads) |*read| read.evidence = (try evidence(g, maps, read.evidence)) orelse {
                valid = false;
                break;
            };
            for (next.call_reads) |*read| read.evidence = (try evidence(g, maps, read.evidence)) orelse {
                valid = false;
                break;
            };
            if (!valid) {
                self.reject(.domain);
                continue;
            }
            if (g.evaluator.retain_specialization_receipts) try g.evaluator.specialization_receipts.ensureUnusedCapacity(self.allocator, 1);
            const before_children = g.evaluator.children.items.len;
            const before = g.evaluator.values.items.len;
            const storage: graph.Plan.QueryStorage = .{ .values_before = record.values_before, .values_added = record.values_added, .children_added = record.children_added };
            const imported = plan.materializeReceiptWithScratch(g, maps, anchors, storage, &self.graph_scratch);
            const mapped = imported catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Declined => {
                    self.reject(.resource);
                    continue;
                },
            };
            for (record.views, view_evidence) |view, actual| if (!view.existed) g.evaluator.typed_views.putAssumeCapacity(.{ .value = mapped[view.value], .evidence = actual }, mapped[view.selected]);
            for (proofs.items) |proof| {
                const key: eval.CallProofKey = .{ .target = .{ .unit = proof.target.unit - 1, .binding = proof.target.binding }, .evidence = proof.evidence };
                if (!g.evaluator.validated_calls.contains(key)) g.evaluator.proofs.proof_published += 1;
                g.evaluator.validated_calls.putAssumeCapacity(key, {});
                if (collect_proofs) self.independent_calls.appendAssumeCapacity(proof) else {
                    var owned = proof;
                    owned.deinit(self.allocator);
                }
            }
            proofs.clearRetainingCapacity();
            for (record.call_publications, calls) |call, actual| {
                const key: eval.CallProofKey = .{ .target = .{ .unit = @as(usize, call.unit - 1), .binding = call.binding }, .evidence = actual };
                if (!g.evaluator.validated_calls.contains(key)) g.evaluator.proofs.proof_published += 1;
                g.evaluator.validated_calls.putAssumeCapacity(key, {});
            }
            var facts = plain.iterator();
            while (facts.next()) |fact| g.evaluator.plain_nominals.putAssumeCapacity(fact.key_ptr.*, fact.value_ptr.*);
            g.evaluator.specialized_closures.putAssumeCapacity(.{ .value = input, .evidence = expected }, mapped[record.selected]);
            if (g.evaluator.retain_specialization_receipts) {
                next.input = input;
                next.expected = expected;
                next.selected = mapped[record.selected];
                next.values_before = before;
                next.children_before = before_children;
                for (next.views, view_evidence) |*view, actual| {
                    view.value = mapped[view.value];
                    view.selected = mapped[view.selected];
                    view.evidence = actual;
                }
                for (next.call_publications, calls) |*call, actual| call.evidence = actual;
                g.evaluator.specialization_receipts.appendAssumeCapacity(next);
                next_owned = false;
            }
            for (record.call_reads) |read| if (read.present) {
                g.evaluator.proofs.proof_reused += 1;
            };
            self.stats.reused += 1;
            self.stats.reasons[@backingInt(Reason.imported)] += 1;
            self.stats.collected_visits_removed += record.collected;
            self.stats.source_scopes_removed += record.source_scopes;
            self.stats.solver_nodes_removed += record.solver_nodes;
            self.stats.values_imported += g.evaluator.values.items.len - before;
            return mapped[record.selected];
        }
        return null;
    }
    fn prepareCallProofs(self: *State, g: anytype, maps: *importer.Importer, reads: []const receipt.CallRead) Allocator.Error!?@import("semantic_parallel.zig").Batch {
        if (!self.recover_call_proofs or self.semantic_workers <= 1 or reads.len < 4) return null;
        const io = self.io orelse return null;
        const parallel = @import("semantic_parallel.zig");
        var requests: std.ArrayList(parallel.Request) = .empty;
        defer requests.deinit(self.allocator);
        var source_bytes: usize = 0;
        for (reads, 0..) |read, read_index| {
            if (!read.present) continue;
            const actual = (try evidence(g, maps, read.evidence)) orelse continue;
            if (g.evaluator.validated_calls.contains(.{ .target = .{ .unit = read.unit - 1, .binding = read.binding }, .evidence = actual })) continue;
            if (!self.gate.admits(.{ .unit = read.unit, .binding = read.binding })) continue;
            const body = self.gate.units[read.unit - 1].body(read.binding).?;
            source_bytes +|= body.span.end -| body.span.start;
            try requests.append(self.allocator, .{ .index = read_index, .read = read, .actual = actual });
        }
        if (requests.items.len < 4 or source_bytes < 4096) return null;
        const batch = try parallel.run(self.allocator, io, self, g, requests.items, self.semantic_workers);
        self.stats.parallel_batches += 1;
        self.stats.parallel_jobs += requests.items.len;
        self.stats.parallel_workers = @max(self.stats.parallel_workers, batch.workers);
        return batch;
    }
};
