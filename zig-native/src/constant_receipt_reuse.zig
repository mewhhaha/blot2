//! Request-scoped admission for dedicated constant receipts. Representation
//! transport cannot authorize this slot, its source fuel or resource charges.
const std = @import("std");
const core = @import("core.zig");
const artifacts = @import("code_artifacts.zig");
const receipt = @import("constant_receipt.zig");
const graph = @import("source_value_template.zig");
const importer = @import("artifact_import.zig");
const admission = @import("principal_reuse_gate.zig");
const A = std.mem.Allocator;

pub const State = struct {
    allocator: A,
    old: *const artifacts.Pools,
    gate: admission.Gate,
    semantic: ?importer.Importer = null,
    pub fn deinit(self: *State) void {
        if (self.semantic) |*maps| maps.deinit();
        self.gate.deinit();
    }
    fn pairedImporter(self: *State) A.Error!*importer.Importer {
        if (self.semantic == null) {
            self.semantic = (try importer.Importer.initCheckedQuery(self.allocator, self.old, self.gate.units, &self.gate)) orelse try importer.Importer.init(self.allocator, self.old, self.gate.units, self.old.identity.?.view(), self.gate.units.len);
        }
        return &self.semantic.?;
    }
    pub fn lookup(self: *State, g: anytype, target: core.BindingRef, inputs: receipt.Inputs) A.Error!?u32 {
        const session = &g.evaluator;
        session.constant_stats.lookups += 1;
        if (!self.gate.enabled or self.old.constant_records.len > 4096) return null;
        for (self.old.constant_records) |*record| {
            session.constant_stats.lookup_comparisons += 1;
            if (!std.meta.eql(record.target, target)) continue;
            session.constant_stats.candidates += 1;
            const result = try self.replay(g, record, inputs);
            if (result == null) session.constant_stats.declined += 1;
            return result;
        }
        return null;
    }
    fn reject(_: *State, g: anytype, reason: receipt.Reason) ?u32 {
        g.evaluator.constant_stats.reasons[@backingInt(reason)] += 1;
        return null;
    }
    fn scalarInputs(self: *const State, record: *const receipt.Record) bool {
        if (graph.scalarRoot(self.old.evaluator, record.value) == null) return false;
        for (record.events) |event| switch (event) {
            .read => |read| if (graph.scalarRoot(self.old.evaluator, read.value) == null) return false,
            .work => {},
        };
        return true;
    }
    fn replayScalar(self: *State, g: anytype, record: *const receipt.Record, total: receipt.Resources, inputs: receipt.Inputs) A.Error!?u32 {
        const session = &g.evaluator;
        var anchor: u32 = 0;
        for (record.events) |event| switch (event) {
            .read => |read| {
                const current = session.readyConstantAnchor(read.target).?;
                const before = graph.scalarRoot(self.old.evaluator, read.value).?;
                const after = graph.scalarRoot(session.snapshot(), current) orelse return self.reject(g, .read);
                if (before.scalar != after.scalar or before.bits != after.bits) return self.reject(g, .read);
                if (read.value == record.value) anchor = current;
            },
            .work => {},
        };
        if (anchor == 0 and total.values == 0) return self.reject(g, .resource);
        var owned = try record.clone(self.allocator);
        @memcpy(@constCast(owned.inputs.types), inputs.types);
        @memcpy(@constCast(owned.inputs.rows), inputs.rows);
        var live = true;
        defer if (live) owned.deinit(self.allocator);
        try session.constant_records.ensureUnusedCapacity(self.allocator, 1);
        var added: usize = 0;
        if (anchor == 0) {
            anchor = graph.materializeScalarRoot(session, graph.scalarRoot(self.old.evaluator, record.value).?) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return self.reject(g, .imported);
            };
            added = 1;
        }
        owned.value = anchor;
        for (owned.events) |*event| switch (event.*) {
            .read => |*read| read.value = session.readyConstantAnchor(read.target).?,
            .work => {},
        };
        session.steps += total.steps;
        session.constant_value_debt += total.values - added;
        session.constant_child_debt += total.children;
        session.constant_records.appendAssumeCapacity(owned);
        live = false;
        session.constant_stats.reused += 1;
        session.constant_stats.scalar_reused += 1;
        session.constant_stats.source_steps_replayed += total.steps;
        session.constant_stats.values_imported += added;
        session.constant_stats.owned_payload_bytes += owned.ownedBytes();
        return anchor;
    }
    fn replay(self: *State, g: anytype, record: *const receipt.Record, inputs: receipt.Inputs) A.Error!?u32 {
        const session = &g.evaluator;
        if (record.sourceSteps() < session.minimum_constant_steps) return null;
        if (!receipt.admittedGraph(self.old.evaluator, record.value)) return self.reject(g, .graph);
        for (record.events) |event| switch (event) {
            .read => |dependency| if (dependency.value >= self.old.evaluator.values.len or self.old.evaluator.values[dependency.value].kind != .scalar) return self.reject(g, .graph),
            .work => {},
        };
        if (!std.meta.eql(record.options, session.options) or !self.gate.admitsLocalSource(record.target) or !self.gate.admitsCallIdentity(record.target)) return self.reject(g, .source);
        for (record.sources) |source| switch (source) {
            .named => |target| if (!self.gate.admitsLocalSource(target)) return self.reject(g, .source),
            .anonymous => |closure| if (!self.gate.admitsClosure(closure.unit, closure.catalog)) return self.reject(g, .source),
        };
        if (record.inputs.types.len != inputs.types.len or record.inputs.rows.len != inputs.rows.len) return self.reject(g, .source);
        if (inputs.types.len != 0 or inputs.rows.len != 0) {
            const maps = try self.pairedImporter();
            const old_module = self.old.modules[record.target.unit - 1].module;
            const current_module = &self.gate.units[record.target.unit - 1];
            for (record.inputs.types, inputs.types) |before, after| {
                if (before.variable != after.variable or before.variable == 0 or before.variable >= old_module.types.nodes.len or after.variable >= current_module.types.nodes.len) return self.reject(g, .source);
                if (old_module.types.nodes[before.variable].tag != .variable or current_module.types.nodes[after.variable].tag != .variable) return self.reject(g, .source);
                if (before.evidence == 0 or after.evidence == 0) {
                    if (before.evidence != after.evidence) return self.reject(g, .source);
                    continue;
                }
                const current = (try maps.importEvidence(g, before.evidence)) orelse return self.reject(g, .source);
                if (current != after.evidence) return self.reject(g, .source);
            }
            for (record.inputs.rows, inputs.rows) |before, after| {
                if (before.variable != after.variable or before.variable >= old_module.types.effects.variable_count or after.variable >= current_module.types.effects.variable_count) return self.reject(g, .source);
                const current = (try maps.importSemanticRow(g, before.evidence)) orelse return self.reject(g, .source);
                if (current != after.evidence) return self.reject(g, .source);
            }
        }
        var roots: std.ArrayList(u32) = .empty;
        defer roots.deinit(self.allocator);
        var total: receipt.Resources = .{};
        for (record.events) |event| switch (event) {
            .work => |work| {
                if (work.steps > session.options.max_steps -| session.steps -| total.steps or work.values > session.options.max_values -| session.constantValueCount() -| total.values or work.children > session.options.max_children -| session.constantChildCount() -| total.children or work.depth > session.options.max_depth -| session.depth or work.call_depth > session.options.max_call_depth -| session.call_depth) return self.reject(g, .resource);
                total.steps += work.steps;
                total.values += work.values;
                total.children += work.children;
            },
            .read => |read| {
                // No speculative demand: a not-yet-ready read retains ordinary
                // evaluation and its original diagnostic/fuel position.
                if (session.readyConstantAnchor(read.target) == null) return self.reject(g, .ready);
            },
        };
        if (self.scalarInputs(record)) return self.replayScalar(g, record, total, inputs);
        try roots.append(self.allocator, record.value);
        for (record.events) |event| switch (event) {
            .read => |read| try roots.append(self.allocator, read.value),
            .work => {},
        };
        const found = try graph.Plan.inspectRootsWithRows(self.allocator, self.old, &self.gate, roots.items, .source_declared);
        var plan = found.plan orelse return self.reject(g, .graph);
        defer plan.deinit(self.allocator);
        session.constant_stats.graph_values_examined += plan.order.len;
        // Dense graph indexes are private proof scratch. Report their known
        // allocation widths separately from transported values and receipts.
        session.constant_stats.graph_index_bytes += self.old.evaluator.values.len + self.old.evaluator.evidence.nodes.len;
        const semantic = try self.pairedImporter();
        const seeds = try self.allocator.alloc(u32, self.old.evaluator.values.len);
        session.constant_stats.graph_index_bytes += seeds.len * @sizeOf(u32);
        defer self.allocator.free(seeds);
        @memset(seeds, 0);
        for (record.events) |event| switch (event) {
            .work => {},
            .read => |read| {
                const current = (session.readyConstantAnchor(read.target)).?;
                session.constant_stats.graph_index_bytes += seeds.len * (@sizeOf(usize) + @sizeOf(u32)) + session.values.items.len * @sizeOf(u32) + plan.order.len * @sizeOf(u32);
                const matched = plan.matchInto(g, semantic, read.value, current, seeds) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return self.reject(g, .imported);
                };
                if (!matched) return self.reject(g, .read);
            },
        };
        const positions = try self.allocator.alloc(bool, self.old.evaluator.children.len);
        session.constant_stats.graph_index_bytes += positions.len * @sizeOf(bool);
        defer self.allocator.free(positions);
        @memset(positions, false);
        for (plan.order) |id| if (seeds[id] != 0) {
            const info = self.old.evaluator.values[id];
            @memset(positions[info.start..][0..info.len], true);
        };
        var values: usize = 0;
        var children: usize = 0;
        for (plan.order) |id| if (seeds[id] == 0) {
            values += 1;
            const info = self.old.evaluator.values[id];
            for (positions[info.start..][0..info.len]) |*present| if (!present.*) {
                present.* = true;
                children += 1;
            };
        };
        if (values > total.values or children > total.children) return self.reject(g, .resource);
        var owned = try record.clone(self.allocator);
        @memcpy(@constCast(owned.inputs.types), inputs.types);
        @memcpy(@constCast(owned.inputs.rows), inputs.rows);
        var live = true;
        defer if (live) owned.deinit(self.allocator);
        try session.constant_records.ensureUnusedCapacity(self.allocator, 1);
        const before_values = session.values.items.len;
        const before_children = session.children.items.len;
        session.constant_stats.graph_index_bytes += seeds.len * (@sizeOf(u32) + @sizeOf(bool)) + self.old.evaluator.children.len * @sizeOf(u32) + plan.order.len * @sizeOf(u32);
        const mapped = plan.materializeReachableMapped(g, semantic, seeds) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.reject(g, .imported);
        };
        defer self.allocator.free(mapped);
        const added_values = session.values.items.len - before_values;
        const added_children = session.children.items.len - before_children;
        std.debug.assert(added_values <= total.values and added_children <= total.children);
        owned.value = mapped[record.value];
        for (owned.events) |*event| switch (event.*) {
            .read => |*read| read.value = mapped[read.value],
            .work => {},
        };
        session.steps += total.steps;
        session.constant_value_debt += total.values - added_values;
        session.constant_child_debt += total.children - added_children;
        session.constant_records.appendAssumeCapacity(owned);
        live = false;
        session.constant_stats.reused += 1;
        session.constant_stats.source_steps_replayed += total.steps;
        session.constant_stats.values_imported += added_values;
        session.constant_stats.owned_payload_bytes += owned.ownedBytes();
        return owned.value;
    }
};
