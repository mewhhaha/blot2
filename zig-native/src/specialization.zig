//! Specialization is a semantic service. It binds representation expectations,
//! solves source obligations and returns owned mappings before runtime emission.
//! It has no Wasm module, function table or instruction builder. Cache hooks
//! preserve the caller's stable retained-owner identity without exposing codegen.
const std = @import("std");
const core = @import("core.zig");
const types = @import("types.zig");
const layout = @import("layout.zig");
const type_evidence = @import("type_evidence.zig");
const core_eval = @import("core_eval.zig");
const layout_bridge = @import("layout_bridge.zig");
const refinement_receipt = @import("refinement_receipt.zig");
const code_artifacts = @import("code_artifacts.zig");
const Allocator = std.mem.Allocator;
const Mapping = layout.Mapping;
const RowMapping = layout.RowMapping;
const EvidenceRoot = refinement_receipt.Root;
// Small scalar bodies usually own a few mappings. Start with four slots;
// subsequent growth still follows ArrayList's ordinary amortized policy.
fn appendMapping(a: Allocator, mappings: *std.ArrayList(Mapping), value: Mapping) Allocator.Error!void {
    if (mappings.capacity == 0) try mappings.ensureTotalCapacityPrecise(a, 4);
    try mappings.append(a, value);
}
pub const Error = Allocator.Error || error{Declined};
pub const Failure = struct { unit: u32, span: core.Span, code: enum { unresolved_type, complexity, evaluation } };
pub const Record = struct {
    root: EvidenceRoot,
    expected: u32,
    seeds: []const type_evidence.Mapping,
    rows: []const type_evidence.RowMapping,
    result: core_eval.SolvedEvidence,
    tape: *@import("specialization_receipt.zig").Tape,
    observed: refinement_receipt.Observation,
    before_values: usize,
    before_children: usize,
    before_steps: usize,
};
pub const Cache = struct {
    context: *anyopaque,
    lookup: *const fn (*anyopaque, EvidenceRoot, @import("code_expectation.zig").View, u32, []const type_evidence.Mapping, []const type_evidence.RowMapping) Allocator.Error!?core_eval.SolvedEvidence,
    record: *const fn (*anyopaque, Record) Allocator.Error!void,
};
pub const ResolvedBody = struct {
    source: core.BindingRef,
    root: @import("semantic_handles.zig").Expression,
    mappings: std.ArrayList(Mapping),
    rows: std.ArrayList(RowMapping),
    pub fn deinit(self: *ResolvedBody, a: Allocator) void {
        self.mappings.deinit(a);
        self.rows.deinit(a);
    }
};
pub const PhysicalProjection = struct {
    allocator: Allocator,
    layouts: *layout.Store,
    mappings: *std.ArrayList(Mapping),
    pub fn mapping(context: *anyopaque, solver: *types.Store, variable: types.Id, root: types.Id) (types.Error || error{UnresolvedType})!void {
        const self: *@This() = @ptrCast(@alignCast(context));
        for (self.mappings.items) |entry| if (entry.variable == variable and entry.layout != layout.erased) return;
        const concrete = self.layouts.fromSolver(solver, root) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.TypeMismatch => error.TypeMismatch,
            error.UnresolvedType => error.UnresolvedType,
            error.LayoutLimit => error.TypeLimit,
        };
        if (concrete == layout.erased) return;
        for (self.mappings.items) |*entry| if (entry.variable == variable) {
            entry.layout = concrete;
            return;
        };
        try appendMapping(self.allocator, self.mappings, .{ .variable = variable, .layout = concrete });
    }
};
const OwnedProjection = struct {
    unit: u32,
    mappings: []const Mapping,
    physical: core_eval.CodeProjection,
    fn mapping(context: *anyopaque, solver: *types.Store, variable: types.Id, root: types.Id) (types.Error || error{UnresolvedType})!void {
        const self: *@This() = @ptrCast(@alignCast(context));
        try self.physical.mapping(self.physical.context, solver, variable, root);
    }
    fn instance(context: *anyopaque, unit: u32, variable: types.Id) ?types.NominalIdentity {
        const self: *@This() = @ptrCast(@alignCast(context));
        if (unit != self.unit) return null;
        for (self.mappings) |entry| if (entry.variable == variable and entry.instance.unit != 0) return entry.instance;
        return null;
    }
};
pub const Service = struct {
    timing: ?*@import("backend_timing.zig").Work = null,
    allocator: Allocator,
    units: []const core.Module,
    evaluator: *core_eval.Session,
    layouts: *layout.Store,
    bridge: *layout_bridge.Store,
    refinement_stats: *refinement_receipt.Stats,
    refinement_regions: *usize,
    cache: ?Cache = null,
    code_projection: ?core_eval.CodeProjection = null,
    failure: ?Failure = null,

    fn unit(self: *const Service, id: u32) *const core.Module {
        return &self.units[id - 1];
    }
    fn decline(self: *Service, id: u32, span: core.Span, code: @FieldType(Failure, "code")) Error {
        self.failure = .{ .unit = id, .span = span, .code = code };
        return error.Declined;
    }
    fn evaluationFailure(self: *Service) Error {
        return self.decline(0, .{ .start = 0, .end = 0 }, .evaluation);
    }
    fn toEvidence(self: *Service, id: layout.Id) type_evidence.Error!type_evidence.Id {
        return @backingInt(try self.bridge.toEvidence(@fromBackingInt(@intCast(id))));
    }
    fn fromEvidence(self: *Service, id: type_evidence.Id) layout.Error!layout.Id {
        return @backingInt(try self.bridge.fromEvidence(@fromBackingInt(@intCast(id))));
    }
    fn rowToEvidence(self: *Service, id: u32) type_evidence.Error!u32 {
        return @backingInt(try self.bridge.rowToEvidence(@fromBackingInt(@intCast(id))));
    }
    fn rowFromEvidence(self: *Service, id: u32) layout.Error!u32 {
        return @backingInt(try self.bridge.rowFromEvidence(@fromBackingInt(@intCast(id))));
    }
    fn codeLayoutWithRows(self: *Service, id: u32, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, span: core.Span) Error!layout.Id {
        return self.layouts.fromTypeWithRows(self.unit(id), ty, mappings, rows, true) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(id, span, .unresolved_type);
    }
    fn internFunction(self: *Service, argument: layout.Id, result: layout.Id, row: u32) Error!layout.Id {
        return self.layouts.internWithEffects(.function, argument, result, row, &.{}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .complexity);
    }
    pub fn named(self: *Service, key: code_artifacts.Key) Error!ResolvedBody {
        const unit_id = key.target.unit;
        const source = self.unit(unit_id);
        const body = source.body(key.target.binding).?;
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        errdefer rows.deinit(self.allocator);
        errdefer mappings.deinit(self.allocator);
        var ty = source.binding(key.target.binding).ty;
        // Written labels can name result or later parameter binders.
        // Map every data endpoint before projecting their operation arguments.
        var source_rows: [code_artifacts.max_parameters]types.Effects.Id = undefined;
        for (key.parameters[0..key.count], 0..) |scalar_type, index| {
            const n = source.types.node(ty);
            if (n.tag != .function) return self.decline(unit_id, body.span, .unresolved_type);
            try self.mapTypeDepth(unit_id, &mappings, &rows, n.a, scalar_type, body.span, 0);
            if (index == 0 and key.instance.unit != 0) {
                const input = source.types.node(n.a);
                if (input.tag == .scoped and input.b == 0) try appendMapping(self.allocator, &mappings, .{ .variable = input.c, .layout = layout.erased, .instance = key.instance });
            }
            source_rows[index] = n.c;
            ty = n.b;
        }
        try self.mapTypeDepth(unit_id, &mappings, &rows, ty, key.result, body.span, 0);
        for (source_rows[0..key.count], key.effects[0..key.count]) |row, actual|
            try self.mapRow(unit_id, &mappings, &rows, row, actual, body.span, true);
        var full = key.result;
        var reverse: usize = key.count;
        while (reverse > 0) {
            reverse -= 1;
            full = try self.internFunction(key.parameters[reverse], full, key.effects[reverse]);
        }
        try self.refineMappings(unit_id, .{ .body = key.target }, full, &mappings, &rows, body.span);
        return .{ .source = key.target, .root = @fromBackingInt(@intCast(body.root)), .mappings = mappings, .rows = rows };
    }
    pub fn mapType(self: *Service, unit_id: u32, mappings: *std.ArrayList(Mapping), ty: types.Id, concrete: layout.Id, span: core.Span) Error!void {
        return self.mapTypeDepth(unit_id, mappings, null, ty, concrete, span, 0);
    }
    pub fn refineMappings(self: *Service, unit_id: u32, root: EvidenceRoot, expected: layout.Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), span: core.Span) Error!void {
        return self.refineMappingsCaptures(unit_id, root, expected, mappings, rows, span, &.{});
    }
    pub fn refineMappingsCaptures(self: *Service, unit_id: u32, root: EvidenceRoot, expected: layout.Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), span: core.Span, captures: []const core_eval.RetainedCapture) Error!void {
        var shapes: std.ArrayList(Mapping) = .empty;
        defer shapes.deinit(self.allocator);
        var partial: PhysicalProjection = .{ .allocator = self.allocator, .layouts = self.layouts, .mappings = &shapes };
        var owned_projection: OwnedProjection = .{ .unit = unit_id, .mappings = mappings.items, .physical = self.code_projection orelse core_eval.CodeProjection{ .context = &partial, .mapping = PhysicalProjection.mapping } };
        const projection: core_eval.CodeProjection = .{ .context = &owned_projection, .mapping = OwnedProjection.mapping, .instance = OwnedProjection.instance };
        const timing = if (self.timing) |work| work.enter(.specialization) else null;
        defer if (timing) |scope| scope.deinit();
        self.refinement_stats.requests += 1;
        var seeds: std.ArrayList(type_evidence.Mapping) = .empty;
        defer seeds.deinit(self.allocator);
        for (mappings.items) |mapping| {
            if (mapping.instance.decl != 0) continue;
            const evidence = self.toEvidence(mapping.layout) catch |err| switch (err) {
                error.UnresolvedType => continue,
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.decline(unit_id, span, .unresolved_type),
            };
            try seeds.append(self.allocator, .{ .variable = mapping.variable, .evidence = evidence });
        }
        var row_seeds: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer row_seeds.deinit(self.allocator);
        for (rows.items) |mapping| {
            if (mapping.row == layout.unknown_row) continue;
            const actual = self.rowToEvidence(mapping.row) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
            try row_seeds.append(self.allocator, .{ .variable = mapping.variable, .evidence = actual });
        }
        const bridge = self.bridge;
        const result_handle = bridge.toCodeExpectation(@fromBackingInt(@intCast(expected))) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
        const result = @backingInt(result_handle);
        var has_instances = false;
        for (mappings.items) |entry| has_instances = has_instances or entry.instance.decl != 0;
        const enabled = !has_instances and self.cache != null and captures.len == 0 and self.code_projection == null and self.evaluator.receipt_tape == null;
        const cached = if (enabled) try self.cache.?.lookup(self.cache.?.context, root, bridge.partialView(), result, seeds.items, row_seeds.items) else null;
        var solved = cached orelse fresh: {
            self.refinement_regions.* += 1;
            var tape: @import("specialization_receipt.zig").Tape = .{};
            defer tape.deinit(self.allocator);
            var observation: refinement_receipt.Observation = .{};
            const old_tape = self.evaluator.receipt_tape;
            const old_observation = self.evaluator.refinement_observation;
            if (enabled) {
                self.evaluator.receipt_tape = &tape;
                self.evaluator.refinement_observation = &observation;
            }
            defer {
                self.evaluator.receipt_tape = old_tape;
                self.evaluator.refinement_observation = old_observation;
            }
            const before_values = self.evaluator.values.items.len;
            const before_children = self.evaluator.children.items.len;
            const before_steps = self.evaluator.steps;
            var output = switch (root) {
                .body => |target| self.evaluator.bodyEvidencePartialFullCode(target, bridge.partialView(), result, seeds.items, row_seeds.items, projection),
                .closure => |closure_| self.evaluator.closureEvidencePartialCapturesCode(closure_.unit, closure_.catalog, bridge.partialView(), result, seeds.items, row_seeds.items, captures, projection),
            } catch |err| switch (err) {
                error.RequestUnwind => return self.evaluationFailure(),
                error.Declined => return self.evaluationFailure(),
                error.OutOfMemory => return error.OutOfMemory,
            };
            errdefer output.deinit(self.allocator);
            // Physical holes carry no semantic proof. Queries needing their
            // projected shapes rebuild instead of publishing an incomplete receipt.
            if (enabled and shapes.items.len == 0) try self.cache.?.record(self.cache.?.context, .{ .root = root, .expected = result, .seeds = seeds.items, .rows = row_seeds.items, .result = output, .tape = &tape, .observed = observation, .before_values = before_values, .before_children = before_children, .before_steps = before_steps });
            break :fresh output;
        };
        defer solved.deinit(self.allocator);
        for (solved.types) |mapping| {
            // A closed seed already owns its physical record slots. Semantic
            // evidence canonicalizes field names, so round-tripping that same
            // proof must not replace or reject the caller's storage order.
            var retained = false;
            for (seeds.items) |seed| if (seed.variable == mapping.variable and seed.evidence == mapping.evidence) {
                retained = true;
                break;
            };
            if (retained) continue;
            const concrete = self.fromEvidence(mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
            try self.mapTypeDepth(unit_id, mappings, rows, mapping.variable, concrete, span, 0);
        }
        for (solved.rows) |mapping| {
            const concrete = self.rowFromEvidence(mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
            var found = false;
            for (rows.items) |prior| if (prior.variable == mapping.variable) {
                const actual = self.rowToEvidence(prior.row) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
                if (actual != mapping.evidence) return self.decline(unit_id, span, .unresolved_type);
                found = true;
                break;
            };
            if (!found) try rows.append(self.allocator, .{ .variable = mapping.variable, .row = concrete });
        }
        for (shapes.items) |shape| try self.mapTypeDepth(unit_id, mappings, rows, shape.variable, shape.layout, span, 0);
    }
    pub fn mapTypeDepth(self: *Service, unit_id: u32, mappings: *std.ArrayList(Mapping), rows: ?*std.ArrayList(RowMapping), ty: types.Id, concrete: layout.Id, span: core.Span, depth: usize) Error!void {
        if (depth >= 1024) return self.decline(unit_id, span, .complexity);
        const source = self.unit(unit_id);
        const n = source.types.node(ty);
        if (n.tag == .scoped) {
            const physical = self.layouts.node(concrete);
            if (physical.tag != .nominal or physical.a != std.math.maxInt(u32) or physical.b != layout.capability_layout_decl) return self.decline(unit_id, span, .unresolved_type);
            return;
        }
        const representation = self.layouts.node(concrete);
        if (n.tag == .never) return;
        if (n.tag == .variable) {
            for (mappings.items) |*mapping| if (mapping.variable == ty) {
                mapping.layout = self.layouts.mergePartial(mapping.layout, concrete) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
                return;
            };
            try appendMapping(self.allocator, mappings, .{ .variable = ty, .layout = concrete });
            return;
        }
        if (n.tag == .projection) {
            // Inputs must already own semantic evidence. The wanted physical
            // result cannot invent a contract argument or select a witness.
            var seeds: std.ArrayList(type_evidence.Mapping) = .empty;
            defer seeds.deinit(self.allocator);
            for (mappings.items) |mapping| {
                if (self.layouts.node(mapping.layout).tag == .erased) continue;
                const actual = self.toEvidence(mapping.layout) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => continue,
                };
                try seeds.append(self.allocator, .{ .variable = mapping.variable, .evidence = actual });
            }
            var row_seeds: std.ArrayList(type_evidence.RowMapping) = .empty;
            defer row_seeds.deinit(self.allocator);
            if (rows) |values| for (values.items) |mapping| {
                if (mapping.row == layout.unknown_row) continue;
                try row_seeds.append(self.allocator, .{ .variable = mapping.variable, .evidence = self.rowToEvidence(mapping.row) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => return self.decline(unit_id, span, .unresolved_type),
                } });
            };
            var use: core.Id = 0;
            for (source.selected_uses) |selected| {
                const location = source.span(selected.node);
                if (location.start >= span.start and location.end <= span.end) {
                    use = selected.node;
                    break;
                }
            }
            const owner: usize = @intCast(unit_id - 1);
            const selected = self.evaluator.projectType(owner, use, ty, seeds.items, row_seeds.items) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.evaluationFailure(),
            };
            if (selected == 0) return self.decline(unit_id, span, .unresolved_type);
            const wanted = self.toEvidence(concrete) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.decline(unit_id, span, .unresolved_type),
            };
            if (selected != wanted) return self.decline(unit_id, span, .unresolved_type);
            for (mappings.items) |*mapping| if (mapping.variable == ty) {
                mapping.layout = concrete;
                return;
            };
            try appendMapping(self.allocator, mappings, .{ .variable = ty, .layout = concrete });
            return;
        }
        const valid = switch (n.tag) {
            .unit => representation.tag == .unit,
            .boolean => representation.tag == .boolean,
            .u32 => representation.tag == .u32,
            .f32 => representation.tag == .f32,
            .function => representation.tag == .function,
            .array => representation.tag == .array,
            .list => representation.tag == .list,
            .cursor => representation.tag == .cursor,
            .demand => representation.tag == .demand,
            .type_constructor => representation.tag == .type_constructor and n.a == representation.a and n.b == representation.b,
            .resolver => representation.tag == .resolver,
            .provider => representation.tag == .provider,
            .state_provider => representation.tag == .state_provider,
            .product => representation.tag == .product,
            .record => representation.tag == .record,
            .nominal => representation.tag == .nominal and n.a == representation.a and n.b == representation.b,
            else => false,
        };
        if (!valid) return self.decline(unit_id, span, .unresolved_type);
        switch (n.tag) {
            .function, .array, .list, .cursor, .demand, .resolver, .provider => {
                try self.mapTypeDepth(unit_id, mappings, rows, n.a, representation.a, span, depth + 1);
                if (n.tag == .function) try self.mapTypeDepth(unit_id, mappings, rows, n.b, representation.b, span, depth + 1);
                if ((n.tag == .function or n.tag == .demand or n.tag == .provider) and rows != null) try self.mapRow(unit_id, mappings, rows.?, n.c, representation.c, span, false);
            },
            .state_provider => {
                try self.mapTypeDepth(unit_id, mappings, rows, n.a, representation.a, span, depth + 1);
                try self.mapTypeDepth(unit_id, mappings, rows, n.b, representation.b, span, depth + 1);
                try self.mapTypeDepth(unit_id, mappings, rows, n.c, representation.c, span, depth + 1);
            },
            .product, .nominal => {
                const children = if (n.tag == .nominal) source.types.nominalArguments(n) else source.types.list(.{ .start = n.a, .len = n.b });
                if (children.len != self.layouts.children(concrete).len) return self.decline(unit_id, span, .unresolved_type);
                for (children, 0..) |child, index| try self.mapTypeDepth(unit_id, mappings, rows, child, self.layouts.children(concrete)[index], span, depth + 1);
            },
            .record => try self.mapRecord(unit_id, mappings, rows, n, concrete, span, depth),
            else => {},
        }
    }
    pub fn mapRow(self: *Service, unit_id: u32, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), source_row: types.Effects.Id, actual_row: u32, span: core.Span, covariant: bool) Error!void {
        if (actual_row == layout.unknown_row) return;
        const source = &self.unit(unit_id).types;
        const expected = source.row(source_row);
        const actuals = try self.allocator.dupe(u32, self.layouts.effects.view().rowLabels(actual_row));
        defer self.allocator.free(actuals);
        const used = try self.allocator.alloc(bool, actuals.len);
        defer self.allocator.free(used);
        @memset(used, false);
        var argument_ids: std.ArrayList(u32) = .empty;
        defer argument_ids.deinit(self.allocator);
        for (source.rowLabels(source_row)) |label| {
            argument_ids.clearRetainingCapacity();
            for (source.operationArguments(label)) |argument| {
                const concrete = try self.codeLayoutWithRows(unit_id, argument, mappings.items, rows.items, span);
                const semantic = self.toEvidence(concrete) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
                try argument_ids.append(self.allocator, semantic);
            }
            const identity = source.operation(label).identity;
            const source_instance = source.operation(label).instance;
            const instance = layout.mappedInstance(source_instance, mappings.items);
            const unbound_instance = instance.unit == 0 and instance.decl != 0;
            var selected: ?usize = null;
            for (actuals, 0..) |actual, index| {
                if (used[index]) continue;
                const operation = self.layouts.effects.view().operation(actual);
                if (!std.meta.eql(identity, operation.identity)) continue;
                if (unbound_instance) {
                    if (operation.instance.unit == 0 or operation.instance.decl == 0) continue;
                } else if (!std.meta.eql(instance, operation.instance)) continue;
                const arguments = self.layouts.effects.view().operationArguments(actual);
                if (arguments.len != argument_ids.items.len) continue;
                var same = true;
                for (arguments, argument_ids.items) |argument, wanted| {
                    const semantic = self.toEvidence(argument) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
                    same = same and semantic == wanted;
                }
                if (same) {
                    if (selected) |prior| {
                        if (!std.meta.eql(self.layouts.effects.view().operation(actuals[prior]).instance, operation.instance)) return self.decline(unit_id, span, .unresolved_type);
                    } else selected = index;
                    if (!unbound_instance) break;
                }
            }
            const index = selected orelse return self.decline(unit_id, span, .unresolved_type);
            used[index] = true;
            if (unbound_instance) try appendMapping(self.allocator, mappings, .{ .variable = source_instance.decl, .layout = layout.erased, .instance = self.layouts.effects.view().operation(actuals[index]).instance });
        }
        var suffix: std.ArrayList(u32) = .empty;
        defer suffix.deinit(self.allocator);
        for (actuals, used) |label, consumed| if (!consumed) try suffix.append(self.allocator, label);
        switch (expected.tail) {
            .closed => if (!covariant and suffix.items.len != 0) return self.decline(unit_id, span, .unresolved_type),
            .parameter => return self.decline(unit_id, span, .unresolved_type),
            .variable => |variable| {
                const remaining = self.layouts.effects.internRow(suffix.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .complexity);
                for (rows.items) |mapping| if (mapping.variable == variable) {
                    const prior = self.rowToEvidence(mapping.row) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
                    const current = self.rowToEvidence(remaining) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
                    if (prior != current) return self.decline(unit_id, span, .unresolved_type);
                    return;
                };
                try rows.append(self.allocator, .{ .variable = variable, .row = remaining });
            },
        }
    }
    fn mapRecord(self: *Service, unit_id: u32, mappings: *std.ArrayList(Mapping), rows: ?*std.ArrayList(RowMapping), n: types.Node, concrete: layout.Id, span: core.Span, depth: usize) Error!void {
        if (self.layouts.children(concrete).len != @as(usize, n.b) * 2) return self.decline(unit_id, span, .unresolved_type);
        for (0..n.b) |i| {
            const field = self.unit(unit_id).types.recordField(n, i);
            var matched = false;
            var j: usize = 0;
            while (j < @as(usize, n.b) * 2) : (j += 2) if (self.layouts.children(concrete)[j] == field.name) {
                try self.mapTypeDepth(unit_id, mappings, rows, field.ty, self.layouts.children(concrete)[j + 1], span, depth + 1);
                matched = true;
                break;
            };
            if (!matched) return self.decline(unit_id, span, .unresolved_type);
        }
    }
};
