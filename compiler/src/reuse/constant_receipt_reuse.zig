//! Request-scoped admission for dedicated constant receipts. Representation
//! transport cannot authorize this slot, its source fuel or resource charges.
const std = @import("std");
const core = @import("../check/core.zig");
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
    scratch: ?graph.QueryScratch = null,
    pub fn deinit(self: *State) void {
        if (self.scratch) |*buffers| buffers.deinit();
        if (self.semantic) |*maps| maps.deinit();
        self.gate.deinit();
    }
    fn pairedImporter(self: *State) A.Error!*importer.Importer {
        if (self.semantic == null) {
            self.semantic = (try importer.Importer.initCheckedQuery(self.allocator, self.old, self.gate.units, &self.gate)) orelse try importer.Importer.init(self.allocator, self.old, self.gate.units, self.old.identity.?.view(), self.gate.units.len);
        }
        return &self.semantic.?;
    }
    pub fn lookup(self: *State, g: anytype, target: core.BindingRef, inputs: receipt.Inputs) A.Error!?receipt.Lookup {
        const session = &g.evaluator;
        session.constant_stats.lookups += 1;
        if (!self.gate.enabled or self.old.constant_records.len > 4096) return null;
        for (self.old.constant_records) |*record| {
            session.constant_stats.lookup_comparisons += 1;
            if (!std.meta.eql(record.target, target)) continue;
            session.constant_stats.candidates += 1;
            const result = try self.replay(g, record, inputs);
            if (result == null) session.constant_stats.declined += 1;
            const value = result orelse return null;
            const published = session.retained.constant_records.items[session.retained.constant_records.items.len - 1];
            var outputs = published.inputs;
            if (published.outputs) |changed| outputs = changed.*;
            return .{ .value = value, .outputs = outputs };
        }
        return null;
    }
    fn mappedInputs(self: *State, g: anytype, unit: u32, before: receipt.Inputs) A.Error!?receipt.Inputs {
        if (before.types.len == 0 and before.rows.len == 0) return try before.clone(self.allocator);
        if (unit == 0 or unit > self.gate.units.len or !self.gate.structural_units[unit - 1]) return null;
        const module = &self.gate.units[unit - 1];
        const maps = try self.pairedImporter();
        var result = try before.clone(self.allocator);
        var live = true;
        defer if (live) result.deinit(self.allocator);
        for (@constCast(result.types)) |*mapping| {
            if (!receipt.sourceMappingKey(module, mapping.variable)) return null;
            if (mapping.evidence != 0) mapping.evidence = (try maps.importEvidence(g, mapping.evidence)) orelse return null;
        }
        for (@constCast(result.rows)) |*mapping| {
            if (mapping.variable >= module.types.effects.variable_count) return null;
            mapping.evidence = (try maps.importSemanticRow(g, mapping.evidence)) orelse return null;
        }
        live = false;
        return result;
    }
    fn mapOutputs(self: *State, g: anytype, record: *const receipt.Record, owned: *receipt.Record) A.Error!bool {
        const before = record.outputs orelse return true;
        const mapped = (try self.mappedInputs(g, record.target.unit, before.*)) orelse return false;
        owned.outputs.?.deinit(self.allocator);
        owned.outputs.?.* = mapped;
        return true;
    }
    fn replayJudgment(self: *State, g: anytype, query: *const receipt.Judgment, expected: u32) A.Error!?*receipt.Judgment {
        if (query.unit == 0 or query.unit > self.gate.units.len or !self.gate.structural_units[query.unit - 1]) return null;
        const owner = &self.gate.units[query.unit - 1];
        if (query.source == 0 or query.source >= owner.nodes.len) return null;
        const producer = if (query.producer == 0) query.unit else query.producer;
        if (producer > self.gate.units.len or !self.gate.structural_units[producer - 1]) return null;
        if (query.root >= self.gate.units[producer - 1].types.nodes.len) return null;
        const lists = owner.types.extra.len;
        for ([_]@import("../check/types.zig").List{ query.scheme.variables, query.scheme.row_variables, query.scheme.closed_rows, query.scheme.generative, query.closed_rows }) |list| {
            if (list.start > lists or list.len > lists - list.start) return null;
        }
        if (query.scheme.root >= owner.types.nodes.len or query.scheme.obligations.start > owner.obligations.len or query.scheme.obligations.len > owner.obligations.len - query.scheme.obligations.start) return null;
        var inputs = (try self.mappedInputs(g, producer, query.inputs)) orelse return null;
        defer inputs.deinit(self.allocator);
        var outputs = (try self.mappedInputs(g, producer, query.outputs)) orelse return null;
        defer outputs.deinit(self.allocator);
        var current = query.*;
        current.inputs = inputs;
        var result = g.evaluator.receiptJudgment(&current, expected) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
        defer result.deinit(self.allocator);
        if (result.matched != query.matched or !@import("../structural.zig").equal(outputs.types, result.solved.types) or !@import("../structural.zig").equal(outputs.rows, result.solved.rows) or !@import("../structural.zig").equal(query.selected, result.solved.selected)) return null;
        current.outputs = .{ .types = result.solved.types, .rows = result.solved.rows };
        current.selected = result.solved.selected;
        return try current.clone(self.allocator);
    }
    fn reject(_: *State, g: anytype, reason: receipt.Reason) ?u32 {
        g.evaluator.constant_stats.reasons[@backingInt(reason)] += 1;
        return null;
    }
    fn scalarInputs(self: *const State, record: *const receipt.Record) bool {
        if (graph.scalarRoot(self.old.evaluator, record.value) == null) return false;
        for (record.events) |event| switch (event) {
            .read => |read| if (graph.scalarRoot(self.old.evaluator, read.value) == null) return false,
            .query => return false,
            .work, .growth, .view => {},
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
            .work, .growth, .view, .query => {},
        };
        if (anchor == 0 and total.values == 0) return self.reject(g, .resource);
        var owned = try record.clone(self.allocator);
        owned.values_before = session.storage.values.items.len;
        @memcpy(@constCast(owned.inputs.types), inputs.types);
        @memcpy(@constCast(owned.inputs.rows), inputs.rows);
        var live = true;
        defer if (live) owned.deinit(self.allocator);
        if (!try self.mapOutputs(g, record, &owned)) return self.reject(g, .source);
        try session.retained.constant_records.ensureUnusedCapacity(self.allocator, 1);
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
            .work, .growth, .view, .query => {},
        };
        session.steps += total.steps;
        session.constant_value_debt += total.values - added;
        session.constant_child_debt += total.children;
        session.retained.constant_records.appendAssumeCapacity(owned);
        live = false;
        session.constant_stats.reused += 1;
        session.constant_stats.scalar_reused += 1;
        session.constant_stats.source_steps_replayed += total.steps;
        session.constant_stats.values_imported += added;
        session.constant_stats.owned_payload_bytes += owned.ownedBytes();
        return anchor;
    }
    fn abortDemand(self: *State, g: anytype, reason: receipt.Reason) ?u32 {
        g.evaluator.constant_receipt_retry = true;
        return self.reject(g, reason);
    }
    fn replayDemand(self: *State, g: anytype, record: *const receipt.Record, total: receipt.Resources, inputs: receipt.Inputs) A.Error!?u32 {
        const session = &g.evaluator;
        var roots: std.ArrayList(u32) = .empty;
        defer roots.deinit(self.allocator);
        try roots.append(self.allocator, record.value);
        for (record.events) |event| switch (event) {
            .read => |read| try roots.append(self.allocator, read.value),
            .view => |view| try roots.appendSlice(self.allocator, &.{ view.value, view.selected }),
            .query => |query| {
                if (query.input != 0) try roots.append(self.allocator, query.input);
                if (query.selected != 0) try roots.append(self.allocator, query.selected);
            },
            .work, .growth => {},
        };
        const found = try graph.Plan.inspectConstantRoots(self.allocator, self.old, &self.gate, roots.items);
        var plan = found.plan orelse return self.reject(g, .graph);
        defer plan.deinit(self.allocator);
        session.constant_stats.graph_values_examined += plan.order.len;
        session.constant_stats.graph_index_bytes += found.stats.inspection_index_bytes;
        // Prefix views cannot allocate a compressed copy of a later owned
        // buffer. Such keys retain ordinary evaluation until their prefix
        // storage itself has an exact transport owner.
        for (record.buffers) |effect| {
            if (effect.value < record.values_before or effect.value >= self.old.evaluator.values.len) return self.reject(g, .graph);
            const info = self.old.evaluator.values[effect.value];
            const frontier = effect.frontier;
            if (frontier.offset > info.start or frontier.capacity < info.len or frontier.offset > frontier.capacity - info.len) return self.reject(g, .graph);
            const start = info.start - frontier.offset;
            if (start > self.old.evaluator.children.len or frontier.capacity > self.old.evaluator.children.len - start) return self.reject(g, .graph);
        }
        if (record.buffers.len != 0) for (record.events) |event| {
            var prefix_roots: [2]u32 = undefined;
            var root_count: usize = 0;
            if (event == .view) {
                prefix_roots = .{ event.view.value, event.view.selected };
                root_count = 2;
            } else if (event == .query and event.query.input != 0) {
                prefix_roots[0] = event.query.input;
                root_count = 1;
            }
            if (root_count == 0) continue;
            const viewed = try graph.Plan.inspectConstantRoots(self.allocator, self.old, &self.gate, prefix_roots[0..root_count]);
            var view_plan = viewed.plan orelse return self.reject(g, .graph);
            defer view_plan.deinit(self.allocator);
            for (view_plan.order) |id| {
                const child = self.old.evaluator.values[id];
                for (record.buffers) |effect| {
                    const start = self.old.evaluator.values[effect.value].start - effect.frontier.offset;
                    if (child.len != 0 and child.start < @as(usize, start) + effect.frontier.capacity and start < @as(usize, child.start) + child.len) return self.reject(g, .mode);
                }
            }
        };
        const semantic = try self.pairedImporter();
        if (self.scratch == null) self.scratch = .{ .allocator = self.allocator };
        const buffers = &self.scratch.?;
        const bytes_before = buffers.payloadBytes();
        defer session.constant_stats.graph_index_bytes += buffers.payloadBytes() - bytes_before;
        const seeds = buffers.begin(&plan, g) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.reject(g, .imported);
        };
        var owned = try record.clone(self.allocator);
        var live = true;
        defer if (live) owned.deinit(self.allocator);
        if (!try self.mapOutputs(g, record, &owned)) return self.reject(g, .source);
        @memcpy(@constCast(owned.inputs.types), inputs.types);
        @memcpy(@constCast(owned.inputs.rows), inputs.rows);
        owned.values_before = session.storage.values.items.len;
        try session.retained.constant_records.ensureUnusedCapacity(self.allocator, 1);
        var value_credit: usize = 0;
        var child_credit: usize = 0;
        var imported: usize = 0;
        for (record.events, owned.events) |event, *new_event| switch (event) {
            .work => |work| {
                if (work.steps > session.options.max_steps -| session.steps or work.values > session.options.max_values -| session.constantValueCount() or work.children > session.options.max_children -| session.constantChildCount() or work.depth > session.options.max_depth -| session.depth or work.call_depth > session.options.max_call_depth -| session.call_depth) return self.abortDemand(g, .resource);
                // Temporary storage and source work occur before this read,
                // exactly as they did in the ordinary expression.
                session.steps += work.steps;
                session.constant_value_debt += work.values;
                session.constant_child_debt += work.children;
                value_credit += work.values;
                child_credit += work.children;
            },
            .read => |read| {
                if (read.depth > session.options.max_depth -| session.depth or read.call_depth > session.options.max_call_depth -| session.call_depth) return self.abortDemand(g, .resource);
                const value = ordinary: {
                    const depth = session.depth;
                    const calls = session.call_depth;
                    const provider = session.constant_provider;
                    session.constant_provider = null;
                    defer session.constant_provider = provider;
                    session.depth += read.depth;
                    session.call_depth += read.call_depth;
                    defer session.depth = depth;
                    defer session.call_depth = calls;
                    break :ordinary session.receiptRead(read.target) catch |err| {
                        if (err == error.OutOfMemory) return error.OutOfMemory;
                        return self.abortDemand(g, .read);
                    };
                };
                const matched = plan.matchIntoWithScratch(g, semantic, read.value, value, seeds, buffers) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return self.abortDemand(g, .imported);
                };
                if (!matched) return self.abortDemand(g, .read);
            },
            .view => |view| {
                if (view.value >= seeds.len or view.selected >= seeds.len or !receipt.validView(self.old.evaluator, view)) return self.abortDemand(g, .graph);
                const actual = (try semantic.importEvidence(g, view.evidence)) orelse return self.abortDemand(g, .imported);
                const input = seeds[view.value];
                const existing = if (input == 0) null else session.storage.typed_views.get(.{ .value = input, .evidence = actual });
                if (view.existed) {
                    const selected = existing orelse return self.abortDemand(g, .read);
                    const matched = plan.matchIntoWithScratch(g, semantic, view.selected, selected, seeds, buffers) catch |err| {
                        if (err == error.OutOfMemory) return error.OutOfMemory;
                        return self.abortDemand(g, .imported);
                    };
                    if (!matched) return self.abortDemand(g, .read);
                } else if (existing != null) return self.abortDemand(g, .read);
                const found_view = try graph.Plan.inspectConstantRoots(self.allocator, self.old, &self.gate, &.{ view.value, view.selected });
                var view_plan = found_view.plan orelse return self.abortDemand(g, .graph);
                defer view_plan.deinit(self.allocator);
                try session.storage.typed_views.ensureUnusedCapacity(self.allocator, 1);
                const before_values = session.storage.values.items.len;
                const before_children = session.storage.children.items.len;
                const view_storage: graph.Plan.QueryStorage = .{ .values_before = record.values_before, .values_added = value_credit, .children_added = child_credit, .exact = false, .precharged = true };
                const viewed = view_plan.materializeReceiptWithScratch(g, semantic, seeds, view_storage, buffers) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return self.abortDemand(g, .imported);
                };
                const added_values = session.storage.values.items.len - before_values;
                imported += added_values;
                value_credit -= added_values;
                child_credit -= session.storage.children.items.len - before_children;
                if (!view.existed) session.storage.typed_views.putAssumeCapacity(.{ .value = viewed[view.value], .evidence = actual }, viewed[view.selected]);
            },
            .query => |query| {
                if (query.depth > session.options.max_depth -| session.depth or query.call_depth > session.options.max_call_depth -| session.call_depth) return self.abortDemand(g, .resource);
                var current = query.*;
                if (query.kind == .array_member) {
                    if (!self.gate.admitsCallIdentity(query.target)) return self.abortDemand(g, .source);
                }
                if (query.input != 0) {
                    const inspected = try graph.Plan.inspectConstantRoots(self.allocator, self.old, &self.gate, &.{query.input});
                    var input_plan = inspected.plan orelse return self.abortDemand(g, .graph);
                    defer input_plan.deinit(self.allocator);
                    const before_values = session.storage.values.items.len;
                    const before_children = session.storage.children.items.len;
                    const storage: graph.Plan.QueryStorage = .{ .values_before = record.values_before, .values_added = value_credit, .children_added = child_credit, .exact = false, .precharged = true };
                    const mapped_input = input_plan.materializeReceiptWithScratch(g, semantic, seeds, storage, buffers) catch |err| {
                        if (err == error.OutOfMemory) return error.OutOfMemory;
                        return self.abortDemand(g, .imported);
                    };
                    const added = session.storage.values.items.len - before_values;
                    imported += added;
                    value_credit -= added;
                    child_credit -= session.storage.children.items.len - before_children;
                    current.input = mapped_input[query.input];
                }
                if (query.expected != 0) current.expected = (try semantic.importEvidence(g, query.expected)) orelse return self.abortDemand(g, .imported);
                const depth = session.depth;
                const calls = session.call_depth;
                session.depth += query.depth;
                session.call_depth += query.call_depth;
                defer session.depth = depth;
                defer session.call_depth = calls;
                if (query.kind == .source) {
                    if (!self.gate.admitsCallIdentity(query.target)) return self.abortDemand(g, .source);
                    const ordinary = session.sourceInterface(query.target) catch |err| {
                        if (err == error.OutOfMemory) return error.OutOfMemory;
                        return self.abortDemand(g, .read);
                    };
                    var expected = query.result;
                    if (expected.evidence != 0) expected.evidence = (try semantic.importEvidence(g, expected.evidence)) orelse return self.abortDemand(g, .imported);
                    if (!std.meta.eql(expected, ordinary)) return self.abortDemand(g, .read);
                    current.result = ordinary;
                } else if (query.kind == .judgment) {
                    const judgment = query.judgment orelse return self.abortDemand(g, .source);
                    const completed = (try self.replayJudgment(g, judgment, current.expected)) orelse return self.abortDemand(g, .read);
                    if (new_event.query.judgment) |old| old.destroy(self.allocator);
                    current.judgment = completed;
                } else {
                    const selected = (session.receiptQuery(current) catch |err| {
                        if (err == error.OutOfMemory) return error.OutOfMemory;
                        return self.abortDemand(g, .read);
                    }) orelse 0;
                    if ((query.selected == 0) != (selected == 0)) return self.abortDemand(g, .read);
                    if (selected != 0) {
                        const matched = plan.matchIntoWithScratch(g, semantic, query.selected, selected, seeds, buffers) catch |err| {
                            if (err == error.OutOfMemory) return error.OutOfMemory;
                            return self.abortDemand(g, .imported);
                        };
                        if (!matched) return self.abortDemand(g, .read);
                    }
                    current.selected = selected;
                }
                new_event.query.* = current;
                session.constant_stats.queries_replayed += 1;
            },
            .growth => |observed| {
                if (observed.frontier != null or observed.mutations >= std.math.maxInt(u64) - session.storage.collection_buffers.mutation_serial) return self.abortDemand(g, .resource);
                session.storage.collection_buffers.mutation_serial += observed.mutations;
            },
        };
        try session.retained.constant_records.ensureUnusedCapacity(self.allocator, 1);
        const before = session.storage.values.items.len;
        const storage: graph.Plan.QueryStorage = .{ .values_before = record.values_before, .values_added = value_credit, .children_added = child_credit, .exact = false, .precharged = true, .buffers = record.buffers };
        const mapped = plan.materializeReceiptWithScratch(g, semantic, seeds, storage, buffers) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.abortDemand(g, .imported);
        };
        owned.value = mapped[record.value];
        for (@constCast(owned.buffers)) |*effect| effect.value = mapped[effect.value];
        for (owned.events) |*event| switch (event.*) {
            .read => |*read| read.value = mapped[read.value],
            .view => |*view| {
                view.value = mapped[view.value];
                view.selected = mapped[view.selected];
                view.evidence = session.valueEvidence(view.selected);
            },
            .work, .growth, .query => {},
        };
        session.retained.constant_records.appendAssumeCapacity(owned);
        live = false;
        session.constant_stats.reused += 1;
        session.constant_stats.source_steps_replayed += total.steps;
        session.constant_stats.values_imported += imported + session.storage.values.items.len - before;
        session.constant_stats.owned_payload_bytes += owned.ownedBytes();
        return owned.value;
    }
    fn replay(self: *State, g: anytype, record: *const receipt.Record, inputs: receipt.Inputs) A.Error!?u32 {
        const session = &g.evaluator;
        if (!record.productive(session.minimum_constant_steps)) return null;
        if (!receipt.admittedGraph(self.old.evaluator, record.value)) return self.reject(g, .graph);
        for (record.events) |event| switch (event) {
            .read => |dependency| if (!receipt.admittedGraph(self.old.evaluator, dependency.value)) return self.reject(g, .graph),
            .work, .growth, .view, .query => {},
        };
        if (!std.meta.eql(record.options, session.options) or !self.gate.admitsLocalSource(record.target) or !self.gate.admitsCallIdentity(record.target)) return self.reject(g, .source);
        if (try graph.generativeNamed(self.allocator, self.old.modules[record.target.unit - 1].module, record.target.binding)) return self.reject(g, .source);
        for (record.sources) |source| switch (source) {
            .named => |target| {
                if (!self.gate.admitsLocalSource(target) or try graph.generativeNamed(self.allocator, self.old.modules[target.unit - 1].module, target.binding)) return self.reject(g, .source);
            },
            .anonymous => |closure| {
                if (!self.gate.admitsClosure(closure.unit, closure.catalog) or try graph.generativeClosure(self.allocator, self.old.modules[closure.unit - 1].module, closure.catalog)) return self.reject(g, .source);
            },
        };
        if (record.inputs.types.len != inputs.types.len or record.inputs.rows.len != inputs.rows.len) return self.reject(g, .source);
        if (inputs.types.len != 0 or inputs.rows.len != 0) {
            if (!self.gate.structural_units[record.target.unit - 1]) return self.reject(g, .source);
            const maps = try self.pairedImporter();
            const old_module = self.old.modules[record.target.unit - 1].module;
            const current_module = &self.gate.units[record.target.unit - 1];
            for (record.inputs.types, inputs.types) |before, after| {
                if (before.variable != after.variable or before.variable == 0 or before.variable >= old_module.types.nodes.len or after.variable >= current_module.types.nodes.len) return self.reject(g, .source);
                if (!receipt.sourceMappingKey(old_module, before.variable) or !receipt.sourceMappingKey(current_module, after.variable)) return self.reject(g, .source);
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
        var growth: ?receipt.Growth = null;
        var needs_demand = false;
        var has_views = false;
        var has_queries = false;
        for (record.events) |event| switch (event) {
            .growth => |observed| {
                if (growth != null or observed.mutations == 0 or observed.mutations >= std.math.maxInt(u64) - session.storage.collection_buffers.mutation_serial) return self.reject(g, .resource);
                growth = observed;
            },
            .work => |work| {
                if (work.steps > session.options.max_steps -| session.steps -| total.steps or work.values > session.options.max_values -| session.constantValueCount() -| total.values or work.children > session.options.max_children -| session.constantChildCount() -| total.children or work.depth > session.options.max_depth -| session.depth or work.call_depth > session.options.max_call_depth -| session.call_depth) return self.reject(g, .resource);
                total.steps += work.steps;
                total.values += work.values;
                total.children += work.children;
            },
            .view => has_views = true,
            .query => has_queries = true,
            .read => |read| {
                // Demand receipts retain ordinary dependency evaluation at
                // its original diagnostic, resource and fuel position.
                if (session.readyConstantAnchor(read.target) == null) needs_demand = true;
            },
        };
        if (record.buffers.len != 0 and growth == null) return self.reject(g, .graph);
        if (needs_demand or has_views or has_queries or record.buffers.len != 0) {
            if (!record.ordered_reads) return self.reject(g, .ready);
            if (growth) |observed| if (observed.frontier != null) return self.reject(g, .mode);
            return self.replayDemand(g, record, total, inputs);
        }
        if (self.scalarInputs(record)) {
            if (growth) |observed| if (observed.frontier != null) return self.reject(g, .graph);
            const result = try self.replayScalar(g, record, total, inputs);
            if (result != null) if (growth) |observed| {
                session.storage.collection_buffers.mutation_serial += observed.mutations;
            };
            return result;
        }
        var frontier: ?@import("../eval/eval_collection_growth.zig").Frontier = null;
        if (growth) |observed| if (observed.frontier) |buffer| {
            const root = self.old.evaluator.values[record.value];
            if (root.len == 0 or buffer.capacity < root.len or buffer.offset > buffer.capacity - root.len or buffer.offset > root.start) return self.reject(g, .graph);
            if (buffer.capacity > self.old.evaluator.children.len - (root.start - buffer.offset)) return self.reject(g, .graph);
            frontier = buffer;
        };
        try roots.append(self.allocator, record.value);
        for (record.events) |event| switch (event) {
            .read => |read| try roots.append(self.allocator, read.value),
            .work, .growth, .view, .query => {},
        };
        const found = try graph.Plan.inspectConstantRoots(self.allocator, self.old, &self.gate, roots.items);
        var plan = found.plan orelse return self.reject(g, .graph);
        defer plan.deinit(self.allocator);
        session.constant_stats.graph_values_examined += plan.order.len;
        // Inspection uses sparse visitation pages; transport buffers are shared
        // across this request. Neither index grants receipt authority.
        session.constant_stats.graph_index_bytes += found.stats.inspection_index_bytes;
        const semantic = try self.pairedImporter();
        if (self.scratch == null) self.scratch = .{ .allocator = self.allocator };
        const buffers = &self.scratch.?;
        const bytes_before = buffers.payloadBytes();
        defer session.constant_stats.graph_index_bytes += buffers.payloadBytes() - bytes_before;
        const seeds = buffers.begin(&plan, g) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.reject(g, .imported);
        };
        for (record.events) |event| switch (event) {
            .work, .growth, .view, .query => {},
            .read => |read| {
                const current = (session.readyConstantAnchor(read.target)).?;
                const matched = plan.matchIntoWithScratch(g, semantic, read.value, current, seeds, buffers) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return self.reject(g, .imported);
                };
                if (!matched) return self.reject(g, .read);
            },
        };
        var owned = try record.clone(self.allocator);
        owned.values_before = session.storage.values.items.len;
        @memcpy(@constCast(owned.inputs.types), inputs.types);
        @memcpy(@constCast(owned.inputs.rows), inputs.rows);
        var live = true;
        defer if (live) owned.deinit(self.allocator);
        if (!try self.mapOutputs(g, record, &owned)) return self.reject(g, .source);
        try session.retained.constant_records.ensureUnusedCapacity(self.allocator, 1);
        if (frontier != null) try session.storage.collection_buffers.buffers.ensureUnusedCapacity(self.allocator, 1);
        const before_values = session.storage.values.items.len;
        const before_children = session.storage.children.items.len;
        const storage: graph.Plan.QueryStorage = .{ .values_before = 0, .values_added = total.values, .children_added = total.children, .exact = false, .root_buffer = frontier };
        const mapped = plan.materializeReceiptWithScratch(g, semantic, seeds, storage, buffers) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.reject(g, .imported);
        };
        const added_values = session.storage.values.items.len - before_values;
        const added_children = session.storage.children.items.len - before_children;
        std.debug.assert(added_values <= total.values and added_children <= total.children);
        owned.value = mapped[record.value];
        if (frontier) |buffer| {
            const root = session.valueInfo(owned.value);
            session.storage.collection_buffers.buffers.putAssumeCapacity(.{ .start = root.start, .len = root.len }, .{ .start = root.start - buffer.offset, .len = buffer.capacity });
        }
        if (growth) |observed| session.storage.collection_buffers.mutation_serial += observed.mutations;
        for (owned.events) |*event| switch (event.*) {
            .read => |*read| read.value = mapped[read.value],
            .work, .growth, .view, .query => {},
        };
        session.steps += total.steps;
        session.constant_value_debt += total.values - added_values;
        session.constant_child_debt += total.children - added_children;
        session.retained.constant_records.appendAssumeCapacity(owned);
        live = false;
        session.constant_stats.reused += 1;
        session.constant_stats.source_steps_replayed += total.steps;
        session.constant_stats.values_imported += added_values;
        session.constant_stats.owned_payload_bytes += owned.ownedBytes();
        return owned.value;
    }
};
