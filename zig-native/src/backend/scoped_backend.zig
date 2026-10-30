//! Source storage admission and data-stack emission. Owner identities survive
//! aliases and control-flow joins; borrowed values never own or retain storage.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const types = @import("../check/storage_types.zig");
const ops = @import("../check/storage_ops.zig");
const wasm = @import("wasm.zig");
const storage = @import("../runtime/data_stacks.zig");
const packets = @import("../runtime/storage_packets.zig");
const Code = @import("runtime_code.zig").Code;
const Local = @import("runtime_code.zig").Local;
const backend = @import("core_backend.zig");
const call_plan = @import("storage_calls.zig");
const selected_types = @import("storage_type_key.zig");
const private_append = @import("private_append_region.zig");
const storage_plan = @import("storage_plan.zig");
const type_evidence = @import("../eval/type_evidence.zig");
const source_proof = @import("../check/package_core.zig");
const Error = std.mem.Allocator.Error || error{Declined};

/// Transitional selection follows reached expressions, not imported type tables.
/// It grants no admission authority; the selected backend still validates Core.
pub fn required(allocator: std.mem.Allocator, units: []const core.Module, entry: u32) std.mem.Allocator.Error!bool {
    const Node = struct { unit: u32, id: core.Id };
    var pending: std.ArrayList(Node) = .empty;
    defer pending.deinit(allocator);
    var seen: std.AutoHashMapUnmanaged(u64, void) = .empty;
    defer seen.deinit(allocator);
    if (entry == 0 or entry > units.len) return true;
    for (units[entry - 1].bodies) |body| if (body.exported) {
        try pending.append(allocator, .{ .unit = entry, .id = body.root });
    };
    while (pending.pop()) |current| {
        if (current.id == 0) continue;
        if (current.unit == 0 or current.unit > units.len or seen.count() >= 100_000) return true;
        const m = &units[current.unit - 1];
        if (current.id >= m.nodes.len) return true;
        if ((try seen.getOrPut(allocator, (@as(u64, current.unit) << 32) | current.id)).found_existing) continue;
        const n = m.node(current.id);
        if (n.tag == .storage) return true;
        if (n.tag == .update) for (m.updateSelectors(current.id)) |selector| {
            if (selector.kind == .index) return true;
        };
        const ty = m.types.node(n.ty);
        if (ty.tag == .nominal and types.identity(ty.a, ty.b) != null) return true;
        if (n.tag == .reference or n.tag == .call) {
            var target = if (n.tag == .call) m.call(current.id).target else m.reference(current.id);
            if (target.unit == 0) target.unit = m.unit;
            if (target.unit == 0 or target.unit > units.len) return true;
            const producer = &units[target.unit - 1];
            if (target.binding >= producer.bindings.len) return true;
            if (producer.body(target.binding)) |body| try pending.append(allocator, .{ .unit = target.unit, .id = body.root });
        }
        if (n.tag == .closure or n.tag == .suspend_) {
            try pending.append(allocator, .{ .unit = m.unit, .id = m.closures[n.a].body });
        }
        const Visitor = struct {
            pending: *std.ArrayList(Node),
            unit: u32,
            pub fn append(self: *@This(), a: std.mem.Allocator, id: core.Id) error{ OutOfMemory, PlanLimit }!void {
                if (self.pending.items.len >= 100_000) return error.PlanLimit;
                if (id != 0) try self.pending.append(a, .{ .unit = self.unit, .id = id });
            }
            pub fn appendSlice(self: *@This(), a: std.mem.Allocator, ids: []const core.Id) error{ OutOfMemory, PlanLimit }!void {
                for (ids) |id| try self.append(a, id);
            }
        };
        var visitor: Visitor = .{ .pending = &pending, .unit = m.unit };
        @import("../eval/body_recipe.zig").appendChildren(&visitor, allocator, m, current.id, false) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.PlanLimit => return true,
        };
    }
    return false;
}
const Value = struct {
    tag: enum { scalar, array, ref, view, link, aggregate, callable } = .scalar,
    word: Local,
    root: ?usize = null,
    other_roots: []const usize = &.{},
    fields: []Value = &.{},
    variant_tags: []const u32 = &.{},
    variant_index: ?usize = null,
    // Immutable evidence about initialized payloads. Empty means unknown;
    // fresh pool layouts start with an all-false set and stores widen it.
    variant_possible: []const bool = &.{},
    terminated: bool = false,
    sequence: bool = false,
    pool_borrow: bool = false,
    token: Local = .{ .id = 0 },
    epoch_low: Local = .{ .id = 0 },
    epoch_high: Local = .{ .id = 0 },
    index: Local = .{ .id = 0 },
    length: Local = .{ .id = 0 },
    depth: usize = 0,
    mode: storage.Mode = .fixed,
    floating: bool = false,
    literal: ?u32 = null,
    name: []const u8 = "",
    callable: ?Callable = null,
    host: ?wasm.Callback = null,
    nominal: ?T.NominalIdentity = null,
    type_evidence: ?struct { root: TypeRef, arguments: []const TypeArgument } = null,
    demand: ?*Demand = null,
};
const Demand = struct { ready: Local, result: ?Value = null, building: bool = false };
const Callable = struct { unit: u32, node: core.Id = 0, target: core.BindingId = 0, captures: []const core.BindingId = &.{}, types: []const TypeArgument = &.{}, goals: []const core.Obligation = &.{} };
fn orderFields(fields: []Value) void {
    std.mem.sort(Value, fields, {}, struct {
        fn less(_: void, left: Value, right: Value) bool {
            return std.mem.order(u8, left.name, right.name) == .lt;
        }
    }.less);
}
const Root = struct { word: Local, token: Local, epoch_low: Local, epoch_high: Local, stack: u32, depth: usize, element: Value, element_initialized: bool = true, capacity_request: ?usize = null, live: bool = true, frozen: bool = false, persistent: bool = false, dedicated: bool = true };
const Global = struct { target: core.BindingRef, word: u32, token: u32, epoch_low: u32, epoch_high: u32, capacity_request: usize, literal_bytes: ?u32 = null, initializing: bool = false };
const TypeRef = struct { unit: u32, ty: T.Id, environment: ?[]const TypeArgument = null };
const TypeArgument = struct { unit: u32, parameter: T.Id, argument: T.Id, argument_unit: u32, environment: ?[]const TypeArgument = null };
const Binding = struct { unit: u32, id: core.BindingId, value: Value, remaining: u32 };
const Control = struct { unit: u32, id: core.Id, nesting: u32, roots_before: usize, result: ?Value = null };
const Loop = struct { unit: u32, id: core.Id, nesting: u32, roots_before: usize, carries: []Value, iterator: ?Local, mark: Local, depth: usize, read_frame: usize };
const RootRead = struct { owner: usize, shape: Value };
const ReadFrame = struct { first: []?*const Value, persistent: std.ArrayList(RootRead) = .empty };
const WriterKind = enum { read, write };
const WriterEvent = struct { owner: usize, kind: WriterKind, shape: Value };
const WriterTrace = struct { inputs: usize, events: std.ArrayList(WriterEvent) = .empty, remaining: usize = 100_000 };
fn hasRoot(value: Value, root_id: usize) bool {
    return storage_plan.hasRoot(value, root_id);
}
fn borrows(value: Value, owner: Value) bool {
    return storage_plan.borrows(value, owner);
}
const DispatchKey = struct { unit: u32, identity: T.NominalIdentity, member: u32, operator: T.Operator, field: bool = false };
const Dispatches = std.AutoHashMapUnmanaged(DispatchKey, ?core.BindingRef);
const Generator = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    uses: []const u32 = &.{},
    active_goals: []const core.Obligation = &.{},
    calls: call_plan.Cache,
    active_calls: *call_plan.ActiveCalls,
    specialize: bool = true,
    protected: std.ArrayList(Value) = .empty,
    append_regions: std.ArrayList(struct { unit: u32, plan: private_append.Plan }) = .empty,
    units: []const core.Module,
    module: *wasm.Module,
    runtime: storage.Runtime,
    transport: ?packets.Runtime = null,
    transport_region: ?u32 = null,
    fixed_region: u32 = 0,
    destination: ?Value = null,
    external_destination: ?usize = null,
    c: Code = undefined,
    stacks: std.ArrayList(bool) = .empty,
    globals: std.ArrayList(Global) = .empty,
    type_arguments: std.ArrayList(TypeArgument) = .empty,
    max_stacks: u32 = 0,
    roots: std.ArrayList(Root) = .empty,
    bindings: std.ArrayList(Binding) = .empty,
    controls: std.ArrayList(Control) = .empty,
    loops: std.ArrayList(Loop) = .empty,
    read_frames: std.ArrayList(ReadFrame) = .empty,
    diagnostic: ?backend.Diagnostic = null,
    depth: usize = 0,
    nesting: u32 = 0,
    steps: usize = 0,
    layout_steps: usize = 0,
    // Templates contain only closed inline data and zero local words. Each use
    // receives independent fields; root/variant evidence is never cached here.
    plain_layouts: std.AutoHashMapUnmanaged(u64, Value) = .empty,
    reader_results: std.AutoHashMapUnmanaged(u32, Value) = .empty,
    writer_facts: std.AutoHashMapUnmanaged(u32, []const WriterEvent) = .empty,
    // Borrowed only while compiling one selected writer specialization.
    writer_trace: ?*WriterTrace = null,
    planning_writer: bool = false,
    validation_budget: *usize,
    proof_cache: *source_proof.SourceProofCache,
    dispatches: *Dispatches,
    capacity_requests: *storage_plan.CapacityRequests,
    unit_views: []const *const core.Module,
    invalid_literals: std.AutoHashMapUnmanaged(u32, void) = .empty,
    fn deinit(self: *Generator) void {
        self.calls.deinit();
        // Value fields borrow this generator's arena or immutable Core; the
        // protected list owns only its backing buffer, not those shared slices.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.protected.deinit(self.allocator);
        self.append_regions.deinit(self.allocator);
        self.roots.deinit(self.allocator);
        self.stacks.deinit(self.allocator);
        self.globals.deinit(self.allocator);
        self.type_arguments.deinit(self.allocator);
        self.invalid_literals.deinit(self.allocator);
        // Templates and nested fields are owned by the generator arena.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.plain_layouts.deinit(self.allocator);
        // Result trees and captured type environments belong to this arena.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.reader_results.deinit(self.allocator);
        // Event shapes belong to the generator arena.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.writer_facts.deinit(self.allocator);
        self.bindings.deinit(self.allocator);
        self.controls.deinit(self.allocator);
        self.loops.deinit(self.allocator);
        // Snapshot fields belong to the generator arena, not the list buffer.
        // zig-analyzer: disable-next-line incomplete-owned-field-cleanup
        self.read_frames.deinit(self.allocator);
        self.arena.deinit();
    }
    fn fail(self: *Generator, m: *const core.Module, id: core.Id, code: backend.Code, detail: []const u8) Error {
        if (self.diagnostic == null) self.diagnostic = .{ .unit = m.unit, .span = m.span(id), .code = code, .detail = detail };
        return error.Declined;
    }
    fn unsupported(self: *Generator, m: *const core.Module, id: core.Id) Error {
        return self.fail(m, id, .storage_unsupported, "This form is not yet supported by the bounded scoped-storage backend");
    }
    fn unit(self: *Generator, id: u32) Error!*const core.Module {
        if (id == 0 or id > self.units.len) return error.Declined;
        return &self.units[id - 1];
    }
    fn constant(self: *Generator, word: u32) Error!Value {
        const local = try self.c.temp();
        try self.c.set(local, word);
        return .{ .word = local };
    }
    fn terminated(self: *Generator) Error!Value {
        var value = try self.constant(0);
        value.terminated = true;
        return value;
    }
    fn scalar(self: *Generator, m: *const core.Module, id: core.Id, value: Value) Error!Local {
        if (value.tag != .scalar) return self.unsupported(m, id);
        return value.word;
    }
    fn bind(self: *Generator, m: *const core.Module, id: core.BindingId, original: Value) Error!void {
        const value = try self.snapshot(original);
        try self.bindings.append(self.allocator, .{ .unit = m.unit, .id = id, .value = value, .remaining = if (id < self.uses.len) self.uses[id] else 0 });
    }
    fn knownLiteral(self: *Generator, value: Value) ?u32 {
        if (self.invalid_literals.contains(value.word.id)) return null;
        return value.literal;
    }
    fn snapshot(self: *Generator, original: Value) Error!Value {
        var value = original;
        value.literal = self.knownLiteral(original);
        if (value.tag == .scalar) {
            value.word = try self.c.temp();
            try self.c.set(value.word, original.word);
            value.depth = self.depth;
        }
        if (value.tag == .view or value.tag == .link or (value.tag == .ref and (value.root != null or value.pool_borrow))) {
            value.word = try self.c.temp();
            value.token = try self.c.temp();
            value.epoch_low = try self.c.temp();
            value.epoch_high = try self.c.temp();
            value.index = try self.c.temp();
            try self.c.set(value.word, original.word);
            try self.c.set(value.token, original.token);
            try self.c.set(value.epoch_low, original.epoch_low);
            try self.c.set(value.epoch_high, original.epoch_high);
            try self.c.set(value.index, original.index);
            if (value.tag == .view) {
                value.length = try self.c.temp();
                try self.c.set(value.length, original.length);
            }
        }
        if (value.tag == .aggregate) {
            if (value.variant_tags.len != 0) {
                value.word = try self.c.temp();
                try self.c.set(value.word, original.word);
            }
            value.fields = try self.arena.allocator().alloc(Value, original.fields.len);
            for (value.fields, original.fields) |*field, input| field.* = try self.snapshot(input);
        }
        return value;
    }
    fn bindingValue(self: *Generator, m: *const core.Module, id: core.BindingId) Error!Value {
        var i = self.bindings.items.len;
        while (i != 0) {
            i -= 1;
            const binding = &self.bindings.items[i];
            if (binding.unit == m.unit and binding.id == id) {
                binding.remaining -|= 1;
                return binding.value;
            }
        }
        return error.Declined;
    }
    fn returnedRoot(self: *Generator, index: usize) bool {
        for (self.controls.items) |control| if (control.result) |value| if (hasRoot(value, index)) return true;
        return false;
    }
    fn closeRuntime(self: *Generator, first: usize, keep: Value) Error!void {
        var cursor = self.roots.items.len;
        while (cursor > first) {
            cursor -= 1;
            const index = cursor;
            const owner = self.roots.items[index];
            if (!owner.live or owner.persistent or hasRoot(keep, index)) continue;
            try self.c.value(.{ .call, self.runtime.functions.close, owner.token, owner.epoch_low, owner.epoch_high });
            try self.c.set(owner.token, 0);
        }
    }
    fn frameMark(self: *Generator) Error!Local {
        const mark = try self.c.temp();
        try self.c.set(mark, .{ .call, self.runtime.functions.mark, self.fixed_region });
        return mark;
    }
    fn rewindUnescaped(self: *Generator, first: usize, mark: Local, keep: Value) Error!void {
        // Pure helper/block evaluation creates no owner to invalidate and
        // cannot advance this fixed region. Avoid scanning unrelated owners.
        if (first == self.roots.items.len) return;
        // A caller opened this owner before entering the callee, but its
        // payload is constructed after the callee's mark. Root creation order
        // alone cannot prove that rewinding preserves the returned payload.
        if (self.external_destination) |root_id| if (hasRoot(keep, root_id)) return;
        for (first..self.roots.items.len) |index| if (hasRoot(keep, index)) return;
        try self.c.value(.{ .call, self.runtime.functions.rewind, self.fixed_region, mark });
    }
    fn root(self: *Generator, m: *const core.Module, id: core.Id, value: Value) Error!*Root {
        return &self.roots.items[value.root orelse return self.unsupported(m, id)];
    }
    fn borrowed(self: *Generator, owner: Value) bool {
        for (self.bindings.items) |binding| if (binding.remaining != 0 and borrows(binding.value, owner)) return true;
        for (self.protected.items) |value| if (borrows(value, owner)) return true;
        for (self.roots.items) |root_| if (root_.live and borrows(root_.element, owner)) return true;
        return false;
    }
    fn shape(self: *Generator, m: *const core.Module, id: core.Id, ty: T.Id, depth: usize) Error!Value {
        if (depth > 128) return self.fail(m, id, .storage_unsupported, "Storage layout exceeded its nesting bound");
        var argument_index = self.type_arguments.items.len;
        while (argument_index != 0) {
            argument_index -= 1;
            const argument = self.type_arguments.items[argument_index];
            if (argument.unit == m.unit and argument.parameter == ty and (argument.argument != ty or argument.argument_unit != m.unit)) {
                const before = self.type_arguments.items.len;
                defer self.type_arguments.shrinkRetainingCapacity(before);
                if (argument.environment) |environment| try self.restoreTypes(environment);
                return self.shape(try self.unit(argument.argument_unit), 0, argument.argument, depth + 1);
            }
        }
        const key = (@as(u64, m.unit) << 32) | ty;
        if (self.plain_layouts.get(key)) |template| return self.cloneLayout(template);
        self.layout_steps += 1;
        if (self.layout_steps > 100_000) return self.fail(m, id, .storage_unsupported, "Storage layout exceeded its checked node budget");
        const value = try self.shapeUncached(m, id, ty, depth);
        // A concrete shape reached through a generic substitution is not a
        // declaration-wide fact. Only independently closed immutable types may
        // use this key; owning/borrowed descriptors retain full live evidence.
        if (plainShape(value)) {
            var remaining = 100_000 - self.layout_steps;
            const closed = call_plan.inlineType(m, ty, &remaining, 0);
            self.layout_steps = 100_000 - remaining;
            if (closed) try self.plain_layouts.put(self.allocator, key, try self.cloneLayout(value));
        }
        return value;
    }
    fn cloneLayout(self: *Generator, template: Value) Error!Value {
        var result = template;
        if (template.fields.len != 0) {
            result.fields = try self.arena.allocator().alloc(Value, template.fields.len);
            for (result.fields, template.fields) |*field, original| field.* = try self.cloneLayout(original);
        }
        return result;
    }
    fn shapeUncached(self: *Generator, m: *const core.Module, id: core.Id, ty: T.Id, depth: usize) Error!Value {
        const n = m.types.node(ty);
        if (n.tag == .unit or n.tag == .u32 or n.tag == .boolean or n.tag == .f32) return .{ .word = .{ .id = 0 }, .floating = n.tag == .f32, .type_evidence = .{ .root = .{ .unit = m.unit, .ty = ty }, .arguments = &.{} } };
        if (@import("storage_collections.zig").element(m, ty) != null) return .{
            .tag = .array,
            .word = .{ .id = 0 },
            .sequence = n.tag == .list,
            .mode = if (types.info(&m.types, ty)) |info| switch (info.kind) {
                .grow => .grow,
                .resize => .resize,
                else => .fixed,
            } else .fixed,
            .type_evidence = .{ .root = .{ .unit = m.unit, .ty = ty }, .arguments = try self.captureTypes() },
        };
        if (n.tag == .cursor) return .{
            .tag = .view,
            .word = .{ .id = 0 },
            .pool_borrow = true,
            .type_evidence = .{ .root = .{ .unit = m.unit, .ty = ty }, .arguments = try self.captureTypes() },
        };
        if (n.tag == .record or n.tag == .product) {
            const fields = try self.arena.allocator().alloc(Value, n.b);
            for (fields, 0..) |*field, index| {
                field.* = try self.shape(m, id, if (n.tag == .record) m.types.recordField(n, index).ty else m.types.list(.{ .start = n.a, .len = n.b })[index], depth + 1);
                if (n.tag == .record) field.name = m.fieldSpelling(m.types.recordField(n, index).name) orelse return self.unsupported(m, id);
            }
            if (n.tag == .record) orderFields(fields);
            return .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = fields };
        }
        if (types.info(&m.types, ty)) |info| switch (info.kind) {
            .ref, .view, .link => return .{ .tag = switch (info.kind) {
                .ref => .ref,
                .view => .view,
                else => .link,
            }, .word = .{ .id = 0 }, .pool_borrow = true },
            else => {},
        };
        if (n.tag == .nominal) for (m.nominals, 0..) |nominal, ordinal| {
            if (nominal.identity.unit != n.a or nominal.identity.decl != n.b) continue;
            const constructors = m.nominalConstructors(@intCast(ordinal));
            if (constructors.len == 0) return self.unsupported(m, id);
            const parameters = m.types.list(nominal.parameters);
            const arguments = m.types.nominalArguments(n);
            if (parameters.len != arguments.len) return self.unsupported(m, id);
            const before = self.type_arguments.items.len;
            defer self.type_arguments.shrinkRetainingCapacity(before);
            for (parameters, arguments) |parameter, argument| try self.mapTypes(.{ .unit = m.unit, .ty = parameter }, .{ .unit = m.unit, .ty = argument }, 0);
            const fields = try self.arena.allocator().alloc(Value, constructors.len);
            const tags: []u32 = if (constructors.len > 1) try self.arena.allocator().alloc(u32, constructors.len) else &.{};
            for (constructors, fields, 0..) |constructor_id, *field, index| {
                const constructor = m.constructor(constructor_id);
                const signature = m.types.node(constructor.scheme.root);
                const result_type = if (signature.tag == .function) signature.b else constructor.scheme.root;
                try self.mapTypes(.{ .unit = m.unit, .ty = result_type }, .{ .unit = m.unit, .ty = ty }, 0);
                field.* = if (constructor.payload == 0) .{ .word = .{ .id = 0 } } else try self.shape(m, id, constructor.payload, depth + 1);
                if (constructors.len > 1) tags[index] = constructor.tag;
            }
            return .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = fields, .nominal = nominal.identity, .variant_tags = tags };
        };
        return self.fail(m, id, .storage_unsupported, "Array elements require a fixed inline layout; resizable and unresolved elements cannot be stored here");
    }
    fn width(value: Value) Error!u32 {
        return @import("storage_layout.zig").bytes(value) catch error.Declined;
    }
    fn unionRoots(self: *Generator, target: *Value, value: Value) Error!void {
        var roots: std.ArrayList(usize) = .empty;
        defer roots.deinit(self.allocator);
        for (self.roots.items, 0..) |_, index| {
            if (target.root == index or value.root == index or std.mem.findScalar(usize, target.other_roots, index) != null or std.mem.findScalar(usize, value.other_roots, index) != null) try roots.append(self.allocator, index);
        }
        if (roots.items.len != 0) {
            target.root = roots.items[0];
            target.other_roots = try self.arena.allocator().dupe(usize, roots.items[1..]);
        }
        target.depth = @max(target.depth, value.depth);
    }
    fn storedShape(self: *Generator, m: *const core.Module, id: core.Id, target: *Value, value: Value, owner_depth: usize) Error!void {
        if (target.tag != value.tag or target.fields.len != value.fields.len or target.floating != value.floating) return self.unsupported(m, id);
        if (!std.meta.eql(target.nominal, value.nominal)) return self.unsupported(m, id);
        if (value.tag == .ref or value.tag == .view or value.tag == .link) {
            if (value.root == null) return self.fail(m, id, .storage_escape, "A local scalar reference cannot be stored in a data-stack aggregate");
            for (self.roots.items, 0..) |owner, index| if (hasRoot(value, index) and owner.depth > owner_depth) return self.fail(m, id, .storage_escape, "The stored borrow would outlive its owner");
        }
        try self.unionRoots(target, value);
        for (target.fields, value.fields, 0..) |*field, input, index| {
            if (!possibleVariant(value, index)) continue;
            try self.storedShape(m, id, field, input, owner_depth);
        }
        try self.unionVariants(target, value);
    }
    fn possibleVariant(value: Value, index: usize) bool {
        if (value.variant_tags.len == 0) return true;
        if (value.variant_index) |selected| return selected == index;
        return value.variant_possible.len == 0 or value.variant_possible[index];
    }
    fn unionVariants(self: *Generator, target: *Value, value: Value) Error!void {
        if (target.variant_tags.len == 0) return;
        const possible = try self.arena.allocator().alloc(bool, target.variant_tags.len);
        for (possible, 0..) |*present, index| present.* = possibleVariant(target.*, index) or possibleVariant(value, index);
        target.variant_possible = possible;
        if (target.variant_index != value.variant_index) target.variant_index = null;
    }
    fn emptyShape(self: *Generator, input: Value) Error!Value {
        var value = input;
        if (value.variant_tags.len != 0 and !plainShape(value)) {
            const possible = try self.arena.allocator().alloc(bool, value.variant_tags.len);
            @memset(possible, false);
            value.variant_possible = possible;
            value.variant_index = null;
        }
        value.fields = try self.arena.allocator().alloc(Value, input.fields.len);
        for (value.fields, input.fields) |*field, original| field.* = try self.emptyShape(original);
        return value;
    }
    fn storeValue(self: *Generator, address: Local, offset: u32, value: Value) Error!void {
        switch (value.tag) {
            .scalar => try self.c.store(address, offset, value.word),
            .ref, .link, .view => {
                try self.c.store(address, offset, value.word);
                try self.c.store(address, offset + 4, value.token);
                try self.c.store(address, offset + 8, value.epoch_low);
                try self.c.store(address, offset + 12, value.epoch_high);
                try self.c.store(address, offset + 16, value.index);
                if (value.tag == .view) try self.c.store(address, offset + 20, value.length);
            },
            .aggregate => {
                if (value.variant_tags.len != 0) {
                    try self.c.store(address, offset, value.word);
                    for (value.fields, value.variant_tags) |field, tag| {
                        try self.c.when(.{ .i32_eq, value.word, tag });
                        self.nesting += 1;
                        try self.storeValue(address, offset + 4, field);
                        self.nesting -= 1;
                        try self.c.end();
                    }
                    return;
                }
                var at = offset;
                for (value.fields) |field| {
                    try self.storeValue(address, at, field);
                    at += try width(field);
                }
            },
            .array, .callable => unreachable,
        }
    }
    fn loadValue(self: *Generator, address: Local, offset: u32, shape_: Value) Error!Value {
        var value = shape_;
        value.word = try self.c.temp();
        switch (value.tag) {
            .scalar => try self.c.set(value.word, .{ .load, address, offset }),
            .ref, .link, .view => {
                try self.c.set(value.word, .{ .load, address, offset });
                value.token = try self.c.temp();
                value.epoch_low = try self.c.temp();
                value.epoch_high = try self.c.temp();
                value.index = try self.c.temp();
                try self.c.set(value.token, .{ .load, address, offset + 4 });
                try self.c.set(value.epoch_low, .{ .load, address, offset + 8 });
                try self.c.set(value.epoch_high, .{ .load, address, offset + 12 });
                try self.c.set(value.index, .{ .load, address, offset + 16 });
                if (value.tag == .view) {
                    value.length = try self.c.temp();
                    try self.c.set(value.length, .{ .load, address, offset + 20 });
                }
            },
            .aggregate => {
                value.fields = try self.arena.allocator().alloc(Value, shape_.fields.len);
                if (value.variant_tags.len != 0) {
                    try self.c.set(value.word, .{ .load, address, offset });
                    const valid = try self.c.temp();
                    try self.c.set(valid, 0);
                    for (value.fields, shape_.fields, value.variant_tags) |*field, input, tag| {
                        try self.c.when(.{ .i32_eq, value.word, tag });
                        self.nesting += 1;
                        field.* = try self.loadValue(address, offset + 4, input);
                        try self.c.set(valid, 1);
                        self.nesting -= 1;
                        try self.c.end();
                    }
                    try self.c.trap(.{ .i32_eqz, valid });
                    value.variant_index = null;
                    return value;
                }
                var at = offset;
                for (value.fields, shape_.fields) |*field, input| {
                    field.* = try self.loadValue(address, at, input);
                    at += try width(input);
                }
            },
            .array, .callable => unreachable,
        }
        return value;
    }
    fn readElement(self: *Generator, m: *const core.Module, id: core.Id, array_: Value, index: Local) Error!Value {
        try self.writerEvent(m, id, array_, .read);
        try self.registerShapeRead(array_);
        var element = (try self.root(m, id, array_)).element;
        // A joined pool can hold borrows into either origin. Preserve the
        // complete origin set independently of the runtime-selected address.
        for (array_.other_roots) |other| {
            // An empty alternative has no payload whose borrow roots must be
            // merged. Its address is still checked against its runtime length.
            if (!self.roots.items[other].element_initialized) continue;
            element = try self.cloneShape(element);
            try self.storedShape(m, id, &element, self.roots.items[other].element, std.math.maxInt(usize));
        }
        const address = try self.c.temp();
        try self.c.set(address, .{ .call, self.runtime.functions.address, array_.token, array_.epoch_low, array_.epoch_high, array_.word, index });
        return self.loadValue(address, 0, element);
    }
    fn zeroShape(self: *Generator, shape_: Value) Error!Value {
        var value = shape_;
        value.word = (try self.constant(0)).word;
        if (value.variant_tags.len != 0) {
            const possible = try self.arena.allocator().alloc(bool, value.variant_tags.len);
            @memset(possible, false);
            value.variant_possible = possible;
            value.variant_index = null;
        }
        if (value.pool_borrow or value.tag == .array) {
            value.token = (try self.constant(0)).word;
            value.epoch_low = (try self.constant(0)).word;
            value.epoch_high = (try self.constant(0)).word;
            value.index = (try self.constant(0)).word;
            if (value.tag == .view) value.length = (try self.constant(0)).word;
        }
        value.fields = try self.arena.allocator().alloc(Value, shape_.fields.len);
        for (value.fields, shape_.fields) |*field, input| field.* = try self.zeroShape(input);
        return value;
    }
    fn cloneShape(self: *Generator, value: Value) Error!Value {
        var result = value;
        result.fields = try self.arena.allocator().alloc(Value, value.fields.len);
        for (result.fields, value.fields) |*field, input| field.* = try self.cloneShape(input);
        return result;
    }
    fn beginReadFrame(self: *Generator) Error!usize {
        const first = try self.arena.allocator().alloc(?*const Value, self.roots.items.len);
        @memset(first, null);
        const index = self.read_frames.items.len;
        try self.read_frames.append(self.allocator, .{ .first = first });
        return index;
    }
    fn readShapeSnapshot(self: *Generator, value: Value) Error!*const Value {
        const snapshot_ = try self.arena.allocator().create(Value);
        snapshot_.* = try self.cloneShape(value);
        return snapshot_;
    }
    fn registerShapeRead(self: *Generator, value: Value) Error!void {
        // Every enclosing runtime loop needs the read, including reads in a
        // nested generator. Evidence must not share mutable field slices.
        for (self.read_frames.items) |*frame| {
            if (value.root) |owner| if (owner < frame.first.len and frame.first[owner] == null) {
                frame.first[owner] = try self.readShapeSnapshot(self.roots.items[owner].element);
            } else if (owner >= frame.first.len) {
                try self.registerPersistentRead(frame, owner);
            };
            for (value.other_roots) |owner| if (owner < frame.first.len and frame.first[owner] == null) {
                frame.first[owner] = try self.readShapeSnapshot(self.roots.items[owner].element);
            } else if (owner >= frame.first.len) {
                try self.registerPersistentRead(frame, owner);
            };
        }
    }
    fn registerPersistentRead(self: *Generator, frame: *ReadFrame, owner: usize) Error!void {
        // Global owners may be opened lazily inside a loop. Their storage is
        // persistent even though their compiler root index is new here.
        if (!self.roots.items[owner].persistent) return;
        for (frame.persistent.items) |read| if (read.owner == owner) return;
        try frame.persistent.append(self.arena.allocator(), .{ .owner = owner, .shape = try self.cloneShape(self.roots.items[owner].element) });
    }
    fn includesReadShape(before: Value, after: Value) bool {
        if (before.tag != after.tag or before.fields.len != after.fields.len or before.variant_tags.len != after.variant_tags.len) return false;
        if (after.root) |owner| if (!hasRoot(before, owner)) return false;
        for (after.other_roots) |owner| if (!hasRoot(before, owner)) return false;
        for (before.fields, after.fields, 0..) |old, next, index| {
            if (!possibleVariant(after, index)) continue;
            if (!possibleVariant(before, index) or !includesReadShape(old, next)) return false;
        }
        return true;
    }
    fn checkReadFrame(self: *Generator, m: *const core.Module, id: core.Id, index: usize) Error!void {
        for (self.read_frames.items[index].first, 0..) |first, owner| if (first) |shape_| {
            if (!includesReadShape(shape_.*, self.roots.items[owner].element)) return self.fail(m, id, .storage_escape, "A loop cannot widen stored variants or borrowed roots after reading them; write the complete shape before its first read");
        };
        for (self.read_frames.items[index].persistent.items) |read| {
            if (!includesReadShape(read.shape, self.roots.items[read.owner].element)) return self.fail(m, id, .storage_escape, "A loop cannot widen stored variants or borrowed roots after reading them; write the complete shape before its first read");
        }
    }
    fn writeElement(self: *Generator, m: *const core.Module, id: core.Id, array_: Value, index: ?Local, value: Value) Error!void {
        for (self.roots.items, 0..) |*owner, root_id| if (array_.root == root_id or std.mem.findScalar(usize, array_.other_roots, root_id) != null) {
            try self.storedShape(m, id, &owner.element, value, owner.depth);
            owner.element_initialized = true;
        };
        try self.writerEvent(m, id, array_, .write);
        const address = try self.c.temp();
        if (index) |at| try self.c.set(address, .{ .call, self.runtime.functions.address, array_.token, array_.epoch_low, array_.epoch_high, array_.word, at }) else try self.c.set(address, .{ .call, self.runtime.functions.append_space, array_.token, array_.epoch_low, array_.epoch_high, array_.word });
        try self.storeValue(address, 0, value);
    }
    fn writerEvent(self: *Generator, m: *const core.Module, id: core.Id, value: Value, kind: WriterKind) Error!void {
        const trace = self.writer_trace orelse return;
        for (self.roots.items, 0..) |owner, index| {
            if (index >= trace.inputs or !hasRoot(value, index)) continue;
            if (trace.remaining == 0) return self.fail(m, id, .storage_unsupported, "Writer access summary exceeded its checked event budget");
            trace.remaining -= 1;
            try trace.events.append(self.allocator, .{ .owner = index, .kind = kind, .shape = try self.cloneShape(owner.element) });
        }
    }
    fn privateAppendNode(self: *const Generator, unit_: u32, id: core.Id, comptime field: []const u8) bool {
        var index = self.append_regions.items.len;
        while (index != 0) {
            index -= 1;
            const region = self.append_regions.items[index];
            if (region.unit == unit_ and @field(region.plan, field) == id) return true;
        }
        return false;
    }
    fn freezeValue(self: *Generator, m: *const core.Module, id: core.Id, first: Value) Error!Value {
        if (self.frozen(first)) return self.fail(m, id, .storage_borrow_conflict, "This array's growth capability was already consumed");
        for (self.roots.items, 0..) |*owner, index| if (hasRoot(first, index)) {
            owner.frozen = true;
        };
        try self.c.value(.{ .call, self.runtime.functions.freeze, first.token, first.epoch_low, first.epoch_high, first.word });
        var result = first;
        result.mode = .fixed;
        result.type_evidence = null;
        return result;
    }
    fn frozen(self: *Generator, owner: Value) bool {
        for (self.roots.items, 0..) |item, index| if (item.frozen and hasRoot(owner, index)) return true;
        return false;
    }
    fn temporary(self: *Generator, value: Value) Error!Value {
        var result = value;
        result.literal = null;
        if (value.host != null) result.word = .{ .id = try self.module.addLocal(self.c.function, .externref) } else if (value.tag != .ref or value.root != null or value.pool_borrow) result.word = try self.c.temp();
        if (value.root != null or value.pool_borrow or value.tag == .array) {
            result.token = try self.c.temp();
            result.epoch_low = try self.c.temp();
            result.epoch_high = try self.c.temp();
        }
        if (value.tag == .ref or value.tag == .view or value.tag == .link) result.index = try self.c.temp();
        if (value.tag == .view) result.length = try self.c.temp();
        result.fields = try self.arena.allocator().alloc(Value, value.fields.len);
        for (result.fields, value.fields) |*field, original| field.* = try self.temporary(original);
        return result;
    }
    fn assign(self: *Generator, m: *const core.Module, id: core.Id, target: *Value, value: Value) Error!void {
        target.literal = null;
        if (target.tag != value.tag or target.fields.len != value.fields.len or target.mode != value.mode or target.floating != value.floating) return self.unsupported(m, id);
        if (!std.meta.eql(target.nominal, value.nominal) or target.demand != value.demand) return self.unsupported(m, id);
        if (!std.meta.eql(target.host, value.host)) return self.unsupported(m, id);
        if (target.tag == .callable and target.host == null and (target.callable.?.unit != value.callable.?.unit or target.callable.?.node != value.callable.?.node or target.callable.?.target != value.callable.?.target)) return self.fail(m, id, .storage_unsupported, "A callback must have a statically known function body");
        if (target.tag == .ref and target.root == null and !target.pool_borrow) {
            if (value.root != null or target.word.id != value.word.id) return self.unsupported(m, id);
        } else try self.c.set(target.word, value.word);
        if (target.root != null or target.pool_borrow or target.tag == .array) {
            try self.c.set(target.token, value.token);
            try self.c.set(target.epoch_low, value.epoch_low);
            try self.c.set(target.epoch_high, value.epoch_high);
        }
        if (value.tag == .ref or value.tag == .view or value.tag == .link) try self.c.set(target.index, value.index);
        if (value.tag == .view) try self.c.set(target.length, value.length);
        try self.unionRoots(target, value);
        for (target.fields, value.fields, 0..) |*field, original, index| {
            if (!possibleVariant(value, index)) continue;
            try self.assign(m, id, field, original);
        }
        try self.unionVariants(target, value);
    }
    fn promote(self: *Generator, value: *Value, boundary: usize) void {
        if (value.tag == .array) {
            for (self.roots.items, 0..) |*owner, index| if (hasRoot(value.*, index) and owner.depth >= boundary) {
                owner.depth = boundary - 1;
            };
            value.depth = @min(value.depth, boundary - 1);
        }
        for (value.fields) |*field| self.promote(field, boundary);
    }
    fn escape(self: *Generator, m: *const core.Module, id: core.Id, value: *Value, boundary: usize) Error!void {
        self.promote(value, boundary);
        try self.checkEscape(m, id, value.*, boundary);
    }
    fn checkEscape(self: *Generator, m: *const core.Module, id: core.Id, value: Value, boundary: usize) Error!void {
        if (value.demand != null and value.depth >= boundary) return self.fail(m, id, .storage_escape, "Memoized demands must remain within their defining invocation");
        if (value.tag == .ref or value.tag == .view or value.tag == .link) {
            if (value.root == null) {
                if (value.depth >= boundary) return self.fail(m, id, .storage_escape, "A borrowed result would outlive its local value");
            } else for (self.roots.items, 0..) |owner, index| {
                if (hasRoot(value, index) and owner.depth >= boundary) return self.fail(m, id, .storage_escape, "A borrowed result would outlive its data-stack owner");
            }
        } else if (value.tag == .array) {
            for (self.roots.items, 0..) |owner, index| if (hasRoot(value, index)) {
                try self.checkEscape(m, id, owner.element, boundary);
            };
        }
        for (value.fields) |field| try self.checkEscape(m, id, field, boundary);
    }
    fn array(self: *Generator, m: *const core.Module, id: core.Id, capacity: Local, mode: storage.Mode) Error!Value {
        const element = @import("storage_collections.zig").element(m, m.typeOf(id)) orelse return self.unsupported(m, id);
        const element_shape = try self.shape(m, id, element, 0);
        var result = try self.arrayWithShape(m, id, capacity, mode, element_shape);
        result.sequence = @import("storage_collections.zig").immutable(m, m.typeOf(id));
        return result;
    }
    fn arrayWithShape(self: *Generator, m: *const core.Module, id: core.Id, capacity: Local, mode: storage.Mode, element_shape: Value) Error!Value {
        var value: Value = undefined;
        if (self.destination) |destination| {
            value = destination;
            self.destination = null;
        } else value = try self.reserveOwner(m, id, mode, element_shape);
        try self.c.set(value.word, .{ .call, self.runtime.functions.create, value.token, value.epoch_low, value.epoch_high, capacity, @backingInt(mode), try width(element_shape) });
        return value;
    }
    fn reserveOwner(self: *Generator, m: *const core.Module, id: core.Id, mode: storage.Mode, element_shape: Value) Error!Value {
        var slot: usize = self.fixed_region;
        if (mode != .fixed) {
            slot = 0;
            while (slot < self.stacks.items.len and self.stacks.items[slot]) : (slot += 1) {}
            if (slot >= storage.max_stacks) return self.fail(m, id, .storage_unsupported, "Too many simultaneously live data regions");
            if (slot == self.stacks.items.len) try self.stacks.append(self.allocator, false);
            self.stacks.items[slot] = true;
            self.max_stacks = @max(self.max_stacks, @as(u32, @intCast(slot + 1)));
        }
        const token = try self.c.temp();
        const word = try self.c.temp();
        const epoch_low = try self.c.temp();
        const epoch_high = try self.c.temp();
        try self.c.set(token, .{ .call, self.runtime.functions.open, @as(u32, @intCast(slot)) });
        try self.c.set(epoch_low, .{ .call, self.runtime.functions.epoch_low, token });
        try self.c.set(epoch_high, .{ .call, self.runtime.functions.epoch_high, token });
        const index = self.roots.items.len;
        const request = if (mode != .fixed) try self.capacity_requests.add(@intCast(slot)) else null;
        try self.roots.append(self.allocator, .{ .word = word, .token = token, .epoch_low = epoch_low, .epoch_high = epoch_high, .stack = @intCast(slot), .depth = self.depth, .element = try self.emptyShape(element_shape), .element_initialized = plainShape(element_shape), .capacity_request = request, .dedicated = mode != .fixed });
        return .{ .tag = .array, .word = word, .token = token, .epoch_low = epoch_low, .epoch_high = epoch_high, .root = index, .depth = self.depth, .mode = mode };
    }
    fn fromWire(self: *Generator, m: *const core.Module, id: core.Id, pointer: Local, kind: wasm.Scalar) Error!Value {
        const transport = self.transport orelse return self.unsupported(m, id);
        const count = try self.c.temp();
        try self.c.set(count, .{ .call, transport.length, pointer });
        const value = try self.arrayWithShape(m, id, count, .fixed, .{ .word = .{ .id = 0 }, .floating = kind == .array_f32 });
        try self.c.copy(.{ .i32_add, value.word, storage.header_bytes }, .{ .i32_add, pointer, 4 }, .{ .i32_mul, count, 4 });
        return value;
    }
    fn toWire(self: *Generator, m: *const core.Module, id: core.Id, value: Value, kind: wasm.Scalar) Error!Local {
        const transport = self.transport orelse return self.unsupported(m, id);
        if (value.tag != .array) return self.unsupported(m, id);
        const shape_ = (try self.root(m, id, value)).element;
        if (shape_.tag != .scalar or shape_.floating != (kind == .array_f32)) return self.unsupported(m, id);
        const count = try self.length(m, id, value);
        const pointer = try self.c.temp();
        try self.c.trap(.{ .i32_gt_u, count, (std.math.maxInt(u32) - 4) / 4 });
        try self.c.set(pointer, .{ .call, transport.allocate, .{ .i32_add, 4, .{ .i32_mul, count, 4 } } });
        try self.c.store(pointer, 0, count);
        try self.c.copy(.{ .i32_add, pointer, 4 }, .{ .i32_add, value.word, storage.header_bytes }, .{ .i32_mul, count, 4 });
        return pointer;
    }
    fn resetPackets(self: *Generator) Error!void {
        if (self.transport) |transport| {
            try self.c.value(.{ .call, transport.reset, 0 });
            try self.c.op(.drop, 0);
        }
    }
    fn hostCall(self: *Generator, m: *const core.Module, id: core.Id, function: Value, argument: Value) Error!Value {
        const signature = function.host.?;
        const import = self.module.importHostCallback(signature) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.unsupported(m, id);
        };
        try self.resetPackets();
        const input = if (arrayAbi(signature.parameter)) try self.toWire(m, id, argument, signature.parameter) else try self.scalar(m, id, argument);
        try self.c.value(function.word);
        try self.c.value(input);
        if (signature.parameter == .f32) try self.c.op(.f32_reinterpret_i32, 0);
        try self.c.op(.call_import, import);
        const output = try self.c.temp();
        if (signature.result == .f32) try self.c.op(.i32_reinterpret_f32, 0);
        try self.c.op(.local_set, output.id);
        const result = if (arrayAbi(signature.result)) try self.fromWire(m, id, output, signature.result) else Value{ .word = output, .floating = signature.result == .f32 };
        try self.resetPackets();
        return result;
    }
    fn plainShape(value: Value) bool {
        if (value.tag != .scalar and value.tag != .aggregate) return false;
        for (value.fields) |field| if (!plainShape(field)) return false;
        return true;
    }
    fn globalArray(self: *Generator, m: *const core.Module, id: core.Id, target: core.BindingRef) Error!Value {
        const slot = for (self.globals.items, 0..) |global, index| {
            if (std.meta.eql(global.target, target)) break index;
        } else return self.unsupported(m, id);
        const global = &self.globals.items[slot];
        if (global.initializing) return self.fail(m, id, .storage_unsupported, "Application storage initializers cannot be recursive");
        const owner = try self.unit(target.unit);
        const binding = owner.binding(target.binding);
        const initializer = (owner.body(target.binding) orelse return self.unsupported(m, id)).root;

        const info = types.info(&owner.types, binding.ty);
        const mode: storage.Mode = if (info) |kind| (if (kind.kind == .grow) .grow else .resize) else .fixed;
        const sequence = @import("storage_collections.zig").immutable(owner, binding.ty);
        // Dependency-ordered initialization dominates the entry body. Reached
        // references reuse its locals instead of emitting the initializer and
        // payload copy again. Each export clears roots before this traversal.
        for (self.roots.items, 0..) |existing, index| if (existing.persistent and existing.stack == slot) return .{
            .tag = .array,
            .word = existing.word,
            .token = existing.token,
            .epoch_low = existing.epoch_low,
            .epoch_high = existing.epoch_high,
            .root = index,
            .depth = 0,
            .mode = mode,
            .sequence = sequence,
        };
        const element = @import("storage_collections.zig").element(owner, binding.ty) orelse return self.unsupported(m, id);
        const shape_ = try self.shape(owner, initializer, element, 0);
        if (!plainShape(shape_)) return self.fail(owner, initializer, .storage_unsupported, "Application array elements currently require scalar or inline record data without borrows");
        if (mode == .fixed and owner.node(initializer).tag == .array) {
            // Fixed literal pools can never extend. Reserve only their known
            // extent, while retaining configured limits for computed lengths.
            global.literal_bytes = storage_plan.CapacityRequests.bytes(@intCast(owner.children(initializer).len), try width(shape_)) catch return self.unsupported(owner, initializer);
        }
        const index = self.roots.items.len;
        try self.roots.append(self.allocator, .{ .word = try self.c.temp(), .token = try self.c.temp(), .epoch_low = try self.c.temp(), .epoch_high = try self.c.temp(), .stack = @intCast(slot), .depth = 0, .element = shape_, .capacity_request = global.capacity_request, .persistent = true });
        const word = self.roots.items[index].word;
        const token = self.roots.items[index].token;
        const epoch_low = self.roots.items[index].epoch_low;
        const epoch_high = self.roots.items[index].epoch_high;
        try self.c.set(epoch_low, .{ .global, global.epoch_low });
        try self.c.set(epoch_high, .{ .global, global.epoch_high });
        try self.c.set(word, .{ .global, global.word });
        try self.c.set(token, .{ .global, global.token });
        const result: Value = .{ .tag = .array, .word = word, .token = token, .epoch_low = epoch_low, .epoch_high = epoch_high, .root = index, .depth = 0, .mode = mode, .sequence = sequence };
        try self.c.when(.{ .i32_eqz, word });
        self.nesting += 1;
        global.initializing = true;
        defer global.initializing = false;
        // Clear the retry handle before closing the previous unpublished
        // attempt. An open/create failure cannot leave a stale close token.
        try self.c.value(0);
        try self.c.op(.global_set, global.token);
        try self.c.value(0);
        try self.c.op(.global_set, global.epoch_low);
        try self.c.value(0);
        try self.c.op(.global_set, global.epoch_high);
        try self.c.value(.{ .call, self.runtime.functions.close, token, epoch_low, epoch_high });
        const temporary_start = self.roots.items.len;
        const initialization_mark = try self.frameMark();
        const source = try self.invoke(target, &.{}, 0);
        if (source.tag != .array) return self.unsupported(owner, initializer);
        for (self.roots.items, 0..) |root_, root_index| if (hasRoot(source, root_index) and root_.persistent) {
            return self.fail(owner, initializer, .storage_unsupported, "A named pool initializer must build fresh storage; use an explicit copy for an existing pool");
        };
        const count = try self.length(owner, initializer, source);
        try self.c.set(token, .{ .call, self.runtime.functions.open, @as(u32, @intCast(slot)) });
        try self.c.set(epoch_low, .{ .call, self.runtime.functions.epoch_low, token });
        try self.c.set(epoch_high, .{ .call, self.runtime.functions.epoch_high, token });
        // This unpublished owner is retained only as a retry handle. Publish
        // global.word after every payload write and temporary cleanup succeeds.
        try self.c.value(token);
        try self.c.op(.global_set, global.token);
        try self.c.value(epoch_low);
        try self.c.op(.global_set, global.epoch_low);
        try self.c.value(epoch_high);
        try self.c.op(.global_set, global.epoch_high);
        try self.c.set(word, .{ .call, self.runtime.functions.create, token, epoch_low, epoch_high, count, @backingInt(mode), try width(shape_) });
        // Persistent rows were independently admitted as plain inline data.
        // Both owners are live and create checked count * stride against its
        // region. Copy the initialized payload without per-field locals or an
        // ownership walk; no descriptor-bearing row reaches this path.
        const source_shape = (try self.root(owner, initializer, source)).element;
        if (!plainShape(source_shape) or try width(source_shape) != try width(shape_)) return self.unsupported(owner, initializer);
        try self.c.copy(.{ .i32_add, word, storage.header_bytes }, .{ .i32_add, source.word, storage.header_bytes }, .{ .i32_mul, count, try width(shape_) });
        try self.release(temporary_start, null);
        try self.c.value(.{ .call, self.runtime.functions.rewind, self.fixed_region, initialization_mark });
        try self.c.value(word);
        try self.c.op(.global_set, global.word);
        self.nesting -= 1;
        try self.c.end();
        return result;
    }
    fn release(self: *Generator, first: usize, keep: ?Value) Error!void {
        var cursor = self.roots.items.len;
        while (cursor > first) {
            cursor -= 1;
            const index = cursor;
            if (keep) |value| if (hasRoot(value, index)) continue;
            if (self.returnedRoot(index)) continue;
            const owner = &self.roots.items[index];
            if (!owner.live or owner.persistent) continue;
            try self.c.value(.{ .call, self.runtime.functions.close, owner.token, owner.epoch_low, owner.epoch_high });
            try self.c.set(owner.token, 0);
            if (owner.dedicated) self.stacks.items[owner.stack] = false;
            owner.live = false;
        }
    }

    fn length(self: *Generator, m: *const core.Module, id: core.Id, value: Value) Error!Local {
        if (value.tag == .view) return value.length;
        if (value.tag != .array) return self.unsupported(m, id);
        const result = try self.c.temp();
        try self.c.set(result, .{ .call, self.runtime.functions.length, value.token, value.epoch_low, value.epoch_high, value.word });
        return result;
    }
    fn elementIndex(self: *Generator, m: *const core.Module, id: core.Id, value: Value, index: Local) Error!Local {
        if (value.tag == .array) return index;
        if (value.tag != .view) return self.unsupported(m, id);
        try self.c.trap(.{ .i32_ge_u, index, value.length });
        const absolute = try self.c.temp();
        try self.c.set(absolute, .{ .i32_add, value.index, index });
        return absolute;
    }
    fn operation(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        const n = m.node(id);
        const op: ops.Op = @fromBackingInt(@intCast(n.c));
        const args = m.children(id);
        const protected_before = self.protected.items.len;
        defer self.protected.shrinkRetainingCapacity(protected_before);
        const first = try self.expression(m, args[0], depth + 1);
        try self.protected.append(self.allocator, first);
        const second = if (args.len >= 2) try self.expression(m, args[1], depth + 1) else try self.constant(0);
        const third = if (args.len == 3) try self.expression(m, args[2], depth + 1) else try self.constant(0);
        switch (op) {
            .reserve => {
                const count = self.knownLiteral(second) orelse return self.fail(m, id, .storage_unsupported, "A storage reservation requires a compile-time U32 literal");
                if (first.tag != .array or first.mode == .fixed or first.root == null) return self.unsupported(m, id);
                for (self.roots.items, 0..) |owner, index| {
                    if (!hasRoot(first, index)) continue;
                    const request = owner.capacity_request orelse return self.unsupported(m, id);
                    self.capacity_requests.reserve(request, count, try width(owner.element)) catch return self.fail(m, id, .storage_unsupported, "Array capacity exceeds the Wasm32 storage plan");
                }
            },
            .ref => {
                var place = args[0];
                while (m.node(place).tag == .project) place = m.node(place).a;
                if (m.node(place).tag != .reference) return self.fail(m, id, .storage_escape, "A reference needs a local place with an enclosing lifetime");
                const target = m.reference(place);
                if ((target.unit != 0 and target.unit != m.unit) or (m.binding(target.binding).kind != .local and m.binding(target.binding).kind != .parameter)) return self.unsupported(m, id);
                if (first.tag != .scalar) return self.unsupported(m, id);
                try self.invalid_literals.put(self.allocator, first.word.id, {});
                var result = first;
                result.literal = null;
                result.tag = .ref;
                result.type_evidence = null;
                return result;
            },
            .at, .link => {
                const index = try self.elementIndex(m, id, first, try self.scalar(m, id, second));
                const address = try self.c.temp();
                try self.c.set(address, .{ .call, self.runtime.functions.address, first.token, first.epoch_low, first.epoch_high, first.word, index });
                return .{ .tag = if (op == .link) .link else .ref, .word = first.word, .token = first.token, .epoch_low = first.epoch_low, .epoch_high = first.epoch_high, .root = first.root, .other_roots = first.other_roots, .index = index, .depth = first.depth };
            },
            .view => {
                const start = try self.scalar(m, id, second);
                const end = try self.scalar(m, id, third);
                const length_ = try self.length(m, id, first);
                try self.c.trap(.{ .i32_or, .{ .i32_gt_u, start, end }, .{ .i32_gt_u, end, length_ } });
                const index = try self.c.temp();
                try self.c.set(index, start);
                if (first.tag == .view) try self.c.set(index, .{ .i32_add, first.index, start });
                const count = try self.c.temp();
                try self.c.set(count, .{ .i32_sub, end, start });
                return .{ .tag = .view, .word = first.word, .token = first.token, .epoch_low = first.epoch_low, .epoch_high = first.epoch_high, .root = first.root, .other_roots = first.other_roots, .index = index, .length = count, .depth = first.depth };
            },
            .load, .write => {
                if (first.tag != .ref and first.tag != .link) return self.unsupported(m, id);
                if (op == .load) {
                    if (first.root != null) return self.readElement(m, id, first, first.index);
                    var value = try self.constant(0);
                    try self.c.set(value.word, first.word);
                    value.floating = first.floating;
                    return value;
                }
                if (first.root == null) try self.c.set(first.word, try self.scalar(m, id, second)) else try self.writeElement(m, id, first, first.index, second);
            },
            .length => return .{ .word = try self.length(m, id, first) },
            .read => {
                const index = try self.elementIndex(m, id, first, try self.scalar(m, id, second));
                return self.readElement(m, id, first, index);
            },
            .push => {
                if (self.frozen(first)) return self.fail(m, id, .storage_borrow_conflict, "This array's growth capability was consumed by freeze");
                try self.writeElement(m, id, first, null, second);
            },
            .pop, .truncate => {
                if (self.borrowed(first) or self.frozen(first)) return self.fail(m, id, .storage_borrow_conflict, "Shrinking would invalidate a live borrow or a consumed growth capability");
                const count = if (op == .pop) try self.length(m, id, first) else try self.scalar(m, id, second);
                var popped: ?Value = null;
                if (op == .pop) {
                    try self.c.trap(.{ .i32_eqz, count });
                    try self.c.set(count, .{ .i32_sub, count, 1 });
                    popped = try self.readElement(m, id, first, count);
                }
                try self.c.value(.{ .call, self.runtime.functions.truncate, first.token, first.epoch_low, first.epoch_high, first.word, count });
                if (popped) |value| return value;
            },
            .freeze => return self.freezeValue(m, id, first),
            .copy => {
                const count = try self.length(m, id, first);
                const copied = try self.array(m, id, count, first.mode);
                const index = (try self.constant(0)).word;
                try self.c.loop(.{ .i32_lt_u, index, count });
                const value = try self.readElement(m, id, first, index);
                try self.writeElement(m, id, copied, index, value);
                try self.c.next(index);
                try self.c.again();
                return copied;
            },
        }
        return self.constant(0);
    }
    fn copyRange(self: *Generator, m: *const core.Module, id: core.Id, target: Value, offset: Local, source: Value, start: Local, count: Local) Error!void {
        const index = try self.c.temp();
        try self.c.set(index, 0);
        try self.c.op(.block, 0);
        try self.c.op(.loop, 0);
        try self.c.value(.{ .i32_ge_u, index, count });
        try self.c.op(.br_if, 1);
        const from = try self.c.temp();
        const to = try self.c.temp();
        try self.c.set(from, .{ .i32_add, start, index });
        try self.c.set(to, .{ .i32_add, offset, index });
        try self.writeElement(m, id, target, to, try self.readElement(m, id, source, from));
        try self.c.next(index);
        try self.c.op(.br, 0);
        try self.c.end();
        try self.c.end();
    }
    fn collection(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        const inputs = m.children(id);
        if (inputs.len > 3 or inputs.len == 0) return self.unsupported(m, id);
        var args: [3]Value = undefined;
        const before = self.protected.items.len;
        defer self.protected.shrinkRetainingCapacity(before);
        for (inputs, 0..) |input, index| {
            args[index] = try self.expression(m, input, depth + 1);
            try self.protected.append(self.allocator, args[index]);
        }
        const op = m.arrayOperation(id);
        if (op == .append and self.privateAppendNode(m.unit, id, "append")) {
            try self.writeElement(m, id, args[0], null, args[1]);
            return args[0];
        }
        if (op == .convert and self.privateAppendNode(m.unit, id, "conversion")) {
            var result = try self.freezeValue(m, id, args[0]);
            result.sequence = false;
            return result;
        }
        const zero = (try self.constant(0)).word;
        switch (op) {
            .length => return .{ .word = try self.length(m, id, args[0]) },
            .get => return self.readElement(m, id, args[0], try self.elementIndex(m, id, args[0], try self.scalar(m, id, args[1]))),
            .simd_load, .simd_store => {
                const element = (try self.root(m, id, args[0])).element;
                if (element.tag != .scalar or args[0].sequence) return self.unsupported(m, id);
                const start = try self.scalar(m, id, args[1]);
                const count = try self.length(m, id, args[0]);
                // Check the entire span before storing any lane, without an
                // overflowing start + 4 calculation.
                try self.c.trap(.{ .i32_or, .{ .i32_lt_u, count, 4 }, .{ .i32_gt_u, start, .{ .i32_sub, count, 4 } } });
                const at = try self.elementIndex(m, id, args[0], start);
                const address = try self.c.temp();
                try self.c.set(address, .{ .call, self.runtime.functions.address, args[0].token, args[0].epoch_low, args[0].epoch_high, args[0].word, at });
                if (op == .simd_store) {
                    const vector = try self.vectorLocal(m, id, args[2]);
                    if (args[2].fields[0].floating != element.floating) return self.unsupported(m, id);
                    try self.c.value(address);
                    try self.c.value(vector);
                    try self.c.op(.v128_store, 0);
                    return args[0];
                }
                const vector: Local = .{ .id = try self.module.addLocal(self.c.function, .v128) };
                try self.c.value(address);
                try self.c.op(.v128_load, 0);
                try self.c.op(.local_set, vector.id);
                const result = try self.temporary(try self.shape(m, id, m.typeOf(id), 0));
                for (result.fields, 0..) |field, lane| {
                    try self.c.value(vector);
                    try self.c.op(.i32x4_extract_lane, @intCast(lane));
                    try self.c.op(.local_set, field.word.id);
                }
                return result;
            },
            .set => {
                if (args[0].sequence) return self.unsupported(m, id);
                try self.writeElement(m, id, args[0], try self.scalar(m, id, args[1]), args[2]);
                return args[0];
            },
            .identity => return args[0],
            .convert => {
                const count = try self.length(m, id, args[0]);
                const result = try self.array(m, id, count, .fixed);
                try self.copyRange(m, id, result, zero, args[0], zero, count);
                return result;
            },
            .cursor => {
                var result = args[0];
                result.tag = .view;
                result.type_evidence = null;
                result.index = (try self.constant(0)).word;
                result.length = try self.length(m, id, args[0]);
                return result;
            },
            .cursor_has => {
                if (args[0].tag != .view) return self.unsupported(m, id);
                const result = try self.c.temp();
                try self.c.set(result, .{ .i32_lt_u, args[0].index, args[0].length });
                return .{ .word = result };
            },
            .cursor_value => {
                if (args[0].tag != .view) return self.unsupported(m, id);
                try self.c.trap(.{ .i32_ge_u, args[0].index, args[0].length });
                return self.readElement(m, id, args[0], args[0].index);
            },
            .cursor_advance => {
                if (args[0].tag != .view) return self.unsupported(m, id);
                var result = args[0];
                try self.c.trap(.{ .i32_ge_u, result.index, result.length });
                result.index = try self.c.temp();
                try self.c.set(result.index, .{ .i32_add, args[0].index, 1 });
                return result;
            },
            .fill, .generate => {
                const count = try self.scalar(m, id, args[0]);
                const result = try self.array(m, id, count, .fixed);
                const read_frame = try self.beginReadFrame();
                defer self.read_frames.shrinkRetainingCapacity(read_frame);
                const index = try self.c.temp();
                try self.c.set(index, 0);
                try self.c.op(.block, 0);
                try self.c.op(.loop, 0);
                self.nesting += 2;
                try self.c.value(.{ .i32_ge_u, index, count });
                try self.c.op(.br_if, 1);
                const value = if (op == .fill) args[1] else try self.apply(m, id, args[1], .{ .word = index }, depth + 1);
                try self.writeElement(m, id, result, index, value);
                try self.checkReadFrame(m, id, read_frame);
                try self.c.next(index);
                try self.c.op(.br, 0);
                try self.c.end();
                try self.c.end();
                self.nesting -= 2;
                return result;
            },
            .concat, .append, .prepend, .slice => {
                const source_length = try self.length(m, id, args[0]);
                const count = try self.c.temp();
                var start = zero;
                if (op == .slice) {
                    start = try self.scalar(m, id, args[1]);
                    try self.c.set(count, try self.scalar(m, id, args[2]));
                    try self.c.trap(.{ .i32_gt_u, start, source_length });
                    try self.c.trap(.{ .i32_gt_u, count, .{ .i32_sub, source_length, start } });
                } else {
                    const added = if (op == .concat) try self.length(m, id, args[1]) else (try self.constant(1)).word;
                    try self.c.set(count, .{ .i32_add, source_length, added });
                    try self.c.trap(.{ .i32_lt_u, count, source_length });
                }
                const result = try self.array(m, id, count, .fixed);
                if (op == .slice) {
                    try self.copyRange(m, id, result, zero, args[0], start, count);
                } else if (op == .prepend) {
                    try self.writeElement(m, id, result, zero, args[1]);
                    try self.copyRange(m, id, result, (try self.constant(1)).word, args[0], zero, source_length);
                } else {
                    try self.copyRange(m, id, result, zero, args[0], zero, source_length);
                    if (op == .concat) try self.copyRange(m, id, result, source_length, args[1], zero, try self.length(m, id, args[1])) else try self.writeElement(m, id, result, source_length, args[1]);
                }
                return result;
            },
            else => return self.unsupported(m, id),
        }
    }
    fn restoreTypes(self: *Generator, arguments: []const TypeArgument) Error!void {
        for (arguments) |argument| {
            var at = self.type_arguments.items.len;
            const present = while (at != 0) {
                at -= 1;
                const previous = self.type_arguments.items[at];
                if (previous.unit == argument.unit and previous.parameter == argument.parameter) break std.meta.eql(previous, argument);
            } else false;
            if (!present) try self.type_arguments.append(self.allocator, argument);
        }
    }
    fn captureTypes(self: *Generator) Error![]const TypeArgument {
        var seen: std.AutoHashMapUnmanaged(u64, void) = .empty;
        defer seen.deinit(self.allocator);
        var captured: std.ArrayList(TypeArgument) = .empty;
        defer captured.deinit(self.allocator);
        var at = self.type_arguments.items.len;
        while (at != 0) {
            at -= 1;
            const argument = self.type_arguments.items[at];
            const key = (@as(u64, argument.unit) << 32) | argument.parameter;
            if ((try seen.getOrPut(self.allocator, key)).found_existing) continue;
            try captured.append(self.allocator, argument);
        }
        std.mem.reverse(TypeArgument, captured.items);
        return self.arena.allocator().dupe(TypeArgument, captured.items);
    }
    fn resolveType(self: *Generator, input: TypeRef, depth: usize) Error!TypeRef {
        if (depth > 128) return error.Declined;
        if (input.environment) |environment| return self.resolveActual(.{ .unit = input.unit, .ty = input.ty }, environment, depth + 1);
        var i = self.type_arguments.items.len;
        while (i != 0) {
            i -= 1;
            const argument = self.type_arguments.items[i];
            if (argument.unit != input.unit or argument.parameter != input.ty) continue;
            if (argument.argument_unit == input.unit and argument.argument == input.ty) continue;
            return self.resolveType(.{ .unit = argument.argument_unit, .ty = argument.argument, .environment = argument.environment }, depth + 1);
        }
        return input;
    }
    fn mapTypes(self: *Generator, formal: TypeRef, input: TypeRef, depth: usize) Error!void {
        return self.mapTypesUnder(formal, input, null, depth);
    }
    // Actual value/callback witnesses have their own immutable substitution
    // environment. Installing it globally can overwrite an active callee's
    // inference variables when the same generic helper is instantiated twice.
    fn resolveActual(self: *Generator, input: TypeRef, environment: []const TypeArgument, depth: usize) Error!TypeRef {
        if (depth > 128) return error.Declined;
        var at = environment.len;
        while (at != 0) {
            at -= 1;
            const item = environment[at];
            if (item.unit != input.unit or item.parameter != input.ty) continue;
            const next: TypeRef = .{ .unit = item.argument_unit, .ty = item.argument, .environment = item.environment };
            if (std.meta.eql(input, next)) continue;
            if (next.environment != null) return self.resolveType(next, depth + 1);
            return self.resolveActual(next, environment, depth + 1);
        }
        const resolved = try self.resolveType(input, depth);
        return .{ .unit = resolved.unit, .ty = resolved.ty, .environment = resolved.environment orelse environment };
    }
    fn mapTypesUnder(self: *Generator, formal: TypeRef, input: TypeRef, environment: ?[]const TypeArgument, depth: usize) Error!void {
        if (depth > 128) return error.Declined;
        const actual = if (environment) |captured| try self.resolveActual(input, captured, 0) else try self.resolveType(input, 0);
        const actual_environment = actual.environment orelse environment;
        if (std.meta.eql(try self.resolveType(formal, 0), actual)) return;
        const left = try self.unit(formal.unit);
        const right = try self.unit(actual.unit);
        const source = left.types.node(formal.ty);
        const destination = right.types.node(actual.ty);
        if (source.tag == .variable or source.tag == .bound) {
            if (destination.tag == .variable or destination.tag == .bound) {
                const known = try self.resolveType(formal, 0);
                const known_owner = try self.unit(known.unit);
                const known_shape = known_owner.types.node(known.ty);
                // A getter's result may still be a source inference variable
                // even after its receiver supplied the concrete element type.
                // Propagate that fact to the result instead of erasing it.
                if (known_shape.tag != .variable and known_shape.tag != .bound) {
                    try self.type_arguments.append(self.allocator, .{ .unit = actual.unit, .parameter = actual.ty, .argument = known.ty, .argument_unit = known.unit, .environment = known.environment });
                    return;
                }
            }
            // Preserve equalities shared by several parameters/results. If a
            // maps to still-open x, specializing a also specializes every other
            // checked occurrence of x (not just this one alias of it).
            const representative = try self.resolveType(formal, 0);
            const representative_node = (try self.unit(representative.unit)).types.node(representative.ty);
            const parameter = if (representative_node.tag == .variable or representative_node.tag == .bound) representative else formal;
            if (!std.meta.eql(parameter, actual)) try self.type_arguments.append(self.allocator, .{ .unit = parameter.unit, .parameter = parameter.ty, .argument = actual.ty, .argument_unit = actual.unit, .environment = actual_environment });
            return;
        }
        if (source.tag == .forall or source.tag == .usage) return self.mapTypesUnder(.{ .unit = formal.unit, .ty = source.a }, if (destination.tag == source.tag) .{ .unit = actual.unit, .ty = destination.a } else actual, actual_environment, depth + 1);
        // A generic callback such as identity can acquire its concrete input
        // from the checked higher-order parameter (for example U32 -> a).
        // Propagate that semantic constraint to its shared result variable.
        if (destination.tag == .variable or destination.tag == .bound) {
            const known = try self.resolveType(formal, 0);
            try self.type_arguments.append(self.allocator, .{ .unit = actual.unit, .parameter = actual.ty, .argument = known.ty, .argument_unit = known.unit, .environment = known.environment });
            return;
        }
        if (source.tag != destination.tag) return;
        switch (source.tag) {
            .function => {
                try self.mapTypesUnder(.{ .unit = formal.unit, .ty = source.a }, .{ .unit = actual.unit, .ty = destination.a }, actual_environment, depth + 1);
                try self.mapTypesUnder(.{ .unit = formal.unit, .ty = source.b }, .{ .unit = actual.unit, .ty = destination.b }, actual_environment, depth + 1);
            },
            .array, .list, .cursor => try self.mapTypesUnder(.{ .unit = formal.unit, .ty = source.a }, .{ .unit = actual.unit, .ty = destination.a }, actual_environment, depth + 1),
            .product, .nominal => {
                const from = if (source.tag == .product) left.types.list(.{ .start = source.a, .len = source.b }) else left.types.nominalArguments(source);
                const to = if (destination.tag == .product) right.types.list(.{ .start = destination.a, .len = destination.b }) else right.types.nominalArguments(destination);
                if (source.tag == .nominal and (source.a != destination.a or source.b != destination.b)) return error.Declined;
                if (from.len != to.len) return error.Declined;
                for (from, to) |a, b| try self.mapTypesUnder(.{ .unit = formal.unit, .ty = a }, .{ .unit = actual.unit, .ty = b }, actual_environment, depth + 1);
            },
            .record => for (0..source.b) |index| {
                const field = left.types.recordField(source, index);
                const name = left.fieldSpelling(field.name) orelse return error.Declined;
                for (0..destination.b) |other| {
                    const target = right.types.recordField(destination, other);
                    if (std.mem.eql(u8, name, right.fieldSpelling(target.name) orelse return error.Declined)) {
                        try self.mapTypesUnder(.{ .unit = formal.unit, .ty = field.ty }, .{ .unit = actual.unit, .ty = target.ty }, actual_environment, depth + 1);
                        break;
                    }
                }
            },
            else => {},
        }
    }
    /// Resolve dependent field results before planning a callee's local owners.
    /// The checked receiver and its actual catalog declaration establish the
    /// result; the spelling of a member never implies a collection element type.
    fn refineFields(self: *Generator, m: *const core.Module, goals: []const core.Obligation) Error!void {
        var passes: usize = 0;
        while (passes <= goals.len) : (passes += 1) {
            const before = self.type_arguments.items.len;
            for (goals) |goal| {
                if ((goal.kind != .field and goal.kind != .collection) or goal.result == 0) continue;
                const receiver = try self.resolveType(.{ .unit = m.unit, .ty = goal.ty }, 0);
                const source = try self.unit(receiver.unit);
                const node = source.types.node(receiver.ty);
                if (goal.kind == .collection) {
                    const element = types.readableElement(&source.types, receiver.ty) orelse
                        (if (node.tag == .list) node.a else continue);
                    try self.mapTypes(.{ .unit = m.unit, .ty = goal.result }, .{ .unit = source.unit, .ty = element, .environment = receiver.environment }, 0);
                    continue;
                }
                if (node.tag == .record) {
                    const name = m.fieldSpelling(goal.name) orelse continue;
                    for (0..node.b) |index| {
                        const field = source.types.recordField(node, index);
                        const spelling = source.fieldSpelling(field.name) orelse continue;
                        if (!std.mem.eql(u8, name, spelling)) continue;
                        try self.mapTypes(.{ .unit = m.unit, .ty = goal.result }, .{ .unit = source.unit, .ty = field.ty, .environment = receiver.environment }, 0);
                        break;
                    }
                    continue;
                }
                const identity = T.receiverIdentity(node) orelse continue;
                const target = (try self.fieldTarget(m, identity, goal.name)) orelse continue;
                const owner = try self.unit(target.unit);
                const signature = owner.types.node(owner.binding(target.binding).ty);
                if (signature.tag != .function) continue;
                try self.mapTypes(.{ .unit = owner.unit, .ty = signature.a }, receiver, 0);
                try self.mapTypes(.{ .unit = m.unit, .ty = goal.result }, .{ .unit = owner.unit, .ty = signature.b }, 0);
            }
            if (self.type_arguments.items.len == before) return;
        }
    }
    /// Specialize only from checked semantic witnesses carried by values.
    /// Inline product fields retain their own witnesses; a machine word or a
    /// storage descriptor alone never chooses a type or associated operation.
    fn mapValueTypes(self: *Generator, formal: TypeRef, value: Value, depth: usize) Error!void {
        if (depth > 128) return error.Declined;
        if (value.type_evidence) |evidence| {
            try self.mapTypesUnder(formal, evidence.root, evidence.arguments, depth + 1);
            return;
        }
        if (value.tag != .aggregate) return;
        const actual = try self.resolveType(formal, 0);
        const owner = try self.unit(actual.unit);
        const node = owner.types.node(actual.ty);
        if (node.tag == .product and node.b == value.fields.len) {
            for (owner.types.list(.{ .start = node.a, .len = node.b }), value.fields) |ty, field| try self.mapValueTypes(.{ .unit = actual.unit, .ty = ty }, field, depth + 1);
        } else if (node.tag == .record) {
            for (0..node.b) |index| {
                const field = owner.types.recordField(node, index);
                const name = owner.fieldSpelling(field.name) orelse return error.Declined;
                for (value.fields) |item| if (std.mem.eql(u8, item.name, name)) {
                    try self.mapValueTypes(.{ .unit = actual.unit, .ty = field.ty }, item, depth + 1);
                    break;
                };
            }
        }
    }
    fn instantiate(self: *Generator, target: core.BindingRef, signature: TypeRef, arguments: []const Value, depth: usize) Error!Value {
        const before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(before);
        const owner = try self.unit(target.unit);
        try self.mapTypes(.{ .unit = owner.unit, .ty = owner.binding(target.binding).ty }, signature, 0);
        return self.invoke(target, arguments, depth);
    }
    fn callableType(self: *Generator, value: Value) Error!?TypeRef {
        if (value.demand != null) return null;
        const callable = value.callable orelse return null;
        const owner = try self.unit(callable.unit);
        var signature = if (callable.node == 0) owner.binding(callable.target).ty else owner.closure(callable.node).function_type;
        if (callable.node == 0) for (value.fields) |_| {
            const arrow = owner.types.node(signature);
            if (arrow.tag != .function) return null;
            signature = arrow.b;
        };
        return .{ .unit = owner.unit, .ty = signature, .environment = callable.types };
    }
    // Additional inline-data specializations follow exact checked numeric
    // selections. No storage, host calls, captures, global values or unknown
    // callbacks enter this summary. Generic declarations are instantiated from
    // their actual checked inputs before examining their scalar bodies.
    fn selectedInlineType(self: *Generator, input: TypeRef, remaining: *usize) Error!bool {
        const actual = try self.resolveType(input, 0);
        const owner = try self.unit(actual.unit);
        return call_plan.inlineType(owner, actual.ty, remaining, 0);
    }
    // Symbolic values used only by the read-only admission walk. Runtime
    // capture words are supplied by readerParameter, never computed here.
    fn planValue(self: *Generator, m: *const core.Module, id: core.Id, remaining: *usize, depth: usize) Error!?Value {
        if (id == 0 or remaining.* == 0 or depth > 128) return null;
        remaining.* -= 1;
        const n = m.node(id);
        switch (n.tag) {
            .reference => {
                var ref = m.reference(id);
                if (ref.unit == 0) ref.unit = m.unit;
                var at = self.bindings.items.len;
                while (at != 0) {
                    at -= 1;
                    const item = self.bindings.items[at];
                    if (item.unit == ref.unit and item.id == ref.binding) return item.value;
                }
                const owner = try self.unit(ref.unit);
                if (owner.binding(ref.binding).kind == .external) {
                    ref = owner.binding(ref.binding).target;
                    if (ref.unit == 0) ref.unit = owner.unit;
                }
                const source = try self.unit(ref.unit);
                if (source.body(ref.binding)) |body| {
                    if (body.is_function) return .{ .tag = .callable, .word = .{ .id = 0 }, .callable = .{ .unit = ref.unit, .target = ref.binding, .types = try self.captureTypes() } };
                } else if (source.binding(ref.binding).kind != .local and source.binding(ref.binding).kind != .parameter) return null;
            },
            .closure => {
                const captures = m.closureCaptures(id);
                const fields = try self.arena.allocator().alloc(Value, captures.len);
                for (captures, fields) |capture, *field| {
                    var at = self.bindings.items.len;
                    var found = false;
                    while (at != 0) {
                        at -= 1;
                        const item = self.bindings.items[at];
                        if (item.unit == m.unit and item.id == capture) {
                            field.* = item.value;
                            found = true;
                            break;
                        }
                    }
                    if (!found) return null;
                }
                return .{ .tag = .callable, .word = .{ .id = 0 }, .fields = fields, .callable = .{ .unit = m.unit, .node = id, .captures = captures, .types = try self.captureTypes(), .goals = self.active_goals } };
            },
            .project => {
                const receiver = (try self.planValue(m, n.a, remaining, depth + 1)) orelse return null;
                const projection = m.projection(n.b);
                const name = m.fieldSpelling(projection.field) orelse return null;
                if (dataField(receiver, name)) |field| return field;
            },
            .product, .record => {
                const children = m.children(id);
                const fields = try self.arena.allocator().alloc(Value, children.len);
                for (children, 0..) |child, index| {
                    const destination = if (n.tag == .record) m.recordDestinations(id)[index] else index;
                    fields[destination] = (try self.planValue(m, child, remaining, depth + 1)) orelse return null;
                    if (n.tag == .record) fields[destination].name = m.fieldSpelling(m.types.recordField(m.types.node(n.ty), destination).name) orelse return null;
                }
                if (n.tag == .record) orderFields(fields);
                return .{ .tag = .aggregate, .word = .{ .id = 0 }, .fields = fields };
            },
            .record_merge => {
                const left = (try self.planValue(m, n.a, remaining, depth + 1)) orelse return null;
                const right = (try self.planValue(m, n.b, remaining, depth + 1)) orelse return null;
                return self.mergeRecordValues(left, right);
            },
            .call => {
                const call = m.call(id);
                var target = call.target;
                if (target.unit == 0) target.unit = m.unit;
                const owner = try self.unit(target.unit);
                const body = owner.body(target.binding) orelse return null;
                if (call.arguments.len < owner.bodyParameters(body).len) {
                    const fields = try self.arena.allocator().alloc(Value, call.arguments.len);
                    for (fields, call.arguments) |*field, argument| field.* = (try self.planValue(m, argument, remaining, depth + 1)) orelse return null;
                    return .{ .tag = .callable, .word = .{ .id = 0 }, .fields = fields, .callable = .{ .unit = owner.unit, .target = target.binding, .types = try self.captureTypes() } };
                }
                if (call.arguments.len == owner.bodyParameters(body).len and owner.node(body.root).tag == .associated) {
                    const types_before = self.type_arguments.items.len;
                    defer self.type_arguments.shrinkRetainingCapacity(types_before);
                    const bindings_before = self.bindings.items.len;
                    defer self.bindings.shrinkRetainingCapacity(bindings_before);
                    for (owner.bodyParameters(body), call.arguments) |parameter, argument| {
                        const value = (try self.planValue(m, argument, remaining, depth + 1)) orelse return null;
                        try self.mapValueTypes(.{ .unit = owner.unit, .ty = parameter.ty }, value, 0);
                        try self.bindings.append(self.allocator, .{ .unit = owner.unit, .id = parameter.binding, .value = value, .remaining = 0 });
                    }
                    if (try self.planValue(owner, body.root, remaining, depth + 1)) |value| if (value.tag == .callable) return value;
                }
            },
            .storage => {
                const op: @import("../check/storage_ops.zig").Op = @fromBackingInt(@intCast(n.c));
                const args = m.children(id);
                if (op == .view or op == .at or op == .link) {
                    var receiver = (try self.planValue(m, args[0], remaining, depth + 1)) orelse return null;
                    receiver.tag = if (op == .view) .view else if (op == .at) .ref else .link;
                    // Roots describe physical provenance; the checked result
                    // describes the selected capability, not its source owner.
                    receiver.type_evidence = .{
                        .root = .{ .unit = m.unit, .ty = n.ty },
                        .arguments = try self.captureTypes(),
                    };
                    return receiver;
                }
            },
            .associated => {
                const first = (try self.planValue(m, n.a, remaining, depth + 1)) orelse return null;
                const second = (try self.planValue(m, n.b, remaining, depth + 1)) orelse return null;
                const left = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(n.a) }, 0);
                const right = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(n.b) }, 0);
                const a = (try self.unit(left.unit)).types.node(left.ty);
                const b = (try self.unit(right.unit)).types.node(right.ty);
                if (a.tag != b.tag or (a.tag != .u32 and a.tag != .f32 and a.tag != .boolean)) return null;
                const target = (try self.dispatchTarget(m, T.receiverIdentity(a).?, n.c, .none)) orelse return null;
                const owner = try self.unit(target.unit);
                const body = owner.body(target.binding) orelse return null;
                const parameters = owner.bodyParameters(body);
                if (parameters.len <= 2) return null;
                try self.mapValueTypes(.{ .unit = owner.unit, .ty = parameters[0].ty }, first, 0);
                try self.mapValueTypes(.{ .unit = owner.unit, .ty = parameters[1].ty }, second, 0);
                const fields = try self.arena.allocator().dupe(Value, &.{ first, second });
                return .{ .tag = .callable, .word = .{ .id = 0 }, .fields = fields, .callable = .{ .unit = owner.unit, .target = target.binding, .types = try self.captureTypes() } };
            },
            else => {},
        }
        if (!try self.selectedInlineType(.{ .unit = m.unit, .ty = n.ty }, remaining)) return null;
        var value = try self.shape(m, id, n.ty, 0);
        value.type_evidence = .{ .root = .{ .unit = m.unit, .ty = n.ty }, .arguments = try self.captureTypes() };
        return value;
    }
    fn plannedCallback(self: *Generator, function: Value, argument: Value, remaining: *usize, active: *[128]core.BindingRef, used: usize, depth: usize) Error!bool {
        const callable = function.callable orelse return false;
        if (function.demand != null or function.host != null or used == active.len) return false;
        const owner = try self.unit(callable.unit);
        if (callable.node == 0) {
            const values = try self.arena.allocator().alloc(Value, function.fields.len + 1);
            @memcpy(values[0..function.fields.len], function.fields);
            values[function.fields.len] = argument;
            const inputs = try self.arena.allocator().alloc(TypeRef, values.len);
            const body = owner.body(callable.target) orelse return false;
            if (owner.bodyParameters(body).len != values.len) return false;
            for (inputs, values, owner.bodyParameters(body)) |*input, value, parameter| {
                if (value.type_evidence) |evidence| input.* = .{ .unit = evidence.root.unit, .ty = evidence.root.ty, .environment = evidence.arguments } else input.* = .{ .unit = owner.unit, .ty = parameter.ty, .environment = callable.types };
            }
            return self.numericCallBody(.{ .unit = owner.unit, .binding = callable.target }, inputs, values, .{ .unit = owner.unit, .ty = owner.typeOf(body.root), .environment = callable.types }, remaining, active, used, true);
        }
        const identity: core.BindingRef = .{ .unit = owner.unit, .binding = callable.node | 0x80000000 };
        for (active[0..used]) |prior| if (std.meta.eql(prior, identity)) return false;
        active[used] = identity;
        const types_before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(types_before);
        const bindings_before = self.bindings.items.len;
        defer self.bindings.shrinkRetainingCapacity(bindings_before);
        try self.restoreTypes(callable.types);
        const closure = owner.closure(callable.node);
        try self.mapValueTypes(.{ .unit = owner.unit, .ty = closure.parameter.ty }, argument, 0);
        for (callable.captures, function.fields) |binding, capture| {
            try self.mapValueTypes(.{ .unit = owner.unit, .ty = owner.binding(binding).ty }, capture, 0);
            try self.bindings.append(self.allocator, .{ .unit = owner.unit, .id = binding, .value = capture, .remaining = 0 });
        }
        try self.bindings.append(self.allocator, .{ .unit = owner.unit, .id = closure.parameter.binding, .value = argument, .remaining = 0 });
        try self.refineFields(owner, callable.goals);
        return self.numericExpression(owner, closure.body, remaining, active, used + 1, true, depth + 1);
    }
    fn numericCallBody(self: *Generator, target: core.BindingRef, inputs: []const TypeRef, values: ?[]const Value, output: TypeRef, remaining: *usize, active: *[128]core.BindingRef, used: usize, readers: bool) Error!bool {
        if (used == active.len) return false;
        for (active[0..used]) |prior| if (std.meta.eql(prior, target)) return false;
        const owner = try self.unit(target.unit);
        const body = owner.body(target.binding) orelse return false;
        const parameters = owner.bodyParameters(body);
        if (parameters.len != inputs.len) {
            // A source alias such as `floor = F32.floor` has no own
            // parameters. Follow only its exact reference body; evaluating a
            // factory or choosing a callback remains a separate admission.
            if (parameters.len == 0 and inputs.len != 0 and owner.node(body.root).tag == .reference and remaining.* != 0) {
                remaining.* -= 1;
                active[used] = target;
                var next = owner.reference(body.root);
                if (next.unit == 0) next.unit = owner.unit;
                return self.numericCallBody(next, inputs, values, output, remaining, active, used + 1, readers);
            }
            // A checked primitive associated partial (lerp) can consume one
            // final argument. No arbitrary factory body is evaluated here.
            const known = values orelse return false;
            const node = owner.node(body.root);
            if (inputs.len != parameters.len + 1 or node.tag != .associated) return false;
            const types_before = self.type_arguments.items.len;
            defer self.type_arguments.shrinkRetainingCapacity(types_before);
            const bindings_before = self.bindings.items.len;
            defer self.bindings.shrinkRetainingCapacity(bindings_before);
            active[used] = target;
            for (parameters, known[0..parameters.len]) |parameter, value| {
                try self.mapValueTypes(.{ .unit = owner.unit, .ty = parameter.ty }, value, 0);
                try self.bindings.append(self.allocator, .{ .unit = owner.unit, .id = parameter.binding, .value = value, .remaining = 0 });
            }
            if (!try self.numericExpression(owner, node.a, remaining, active, used + 1, readers, 0) or !try self.numericExpression(owner, node.b, remaining, active, used + 1, readers, 0)) return false;
            const function = (try self.planValue(owner, body.root, remaining, 0)) orelse return false;
            return self.plannedCallback(function, known[parameters.len], remaining, active, used + 1, 0);
        }
        const before = self.type_arguments.items.len;
        const bindings_before = self.bindings.items.len;
        defer self.bindings.shrinkRetainingCapacity(bindings_before);
        active[used] = target;
        if (values) |known| for (parameters, known) |parameter, value| {
            try self.bindings.append(self.allocator, .{ .unit = owner.unit, .id = parameter.binding, .value = value, .remaining = 0 });
        };
        if (values) |known| {
            for (parameters, known) |parameter, value| {
                const formal: TypeRef = .{ .unit = owner.unit, .ty = parameter.ty };
                if (try self.callableType(value)) |signature| try self.mapTypesUnder(formal, signature, value.callable.?.types, 0) else try self.mapValueTypes(formal, value, 0);
            }
        } else for (parameters, inputs) |parameter, input| try self.mapTypes(.{ .unit = owner.unit, .ty = parameter.ty }, input, 0);
        try self.mapTypes(.{ .unit = owner.unit, .ty = owner.typeOf(body.root) }, output, 0);
        try self.refineFields(owner, owner.obligations[body.scheme.obligations.start..][0..body.scheme.obligations.len]);
        const admitted = self.numericExpression(owner, body.root, remaining, active, used + 1, readers, 0) catch |err| {
            self.type_arguments.shrinkRetainingCapacity(before);
            return err;
        };
        var result = try self.resolveType(.{ .unit = owner.unit, .ty = owner.typeOf(body.root) }, 0);
        if (result.environment == null and (try self.unit(result.unit)).types.node(result.ty).tag == .function) result.environment = try self.captureTypes();
        self.type_arguments.shrinkRetainingCapacity(before);
        if (admitted) try self.mapTypes(output, result, 0);
        return admitted;
    }
    fn numericExpression(self: *Generator, m: *const core.Module, id: core.Id, remaining: *usize, active: *[128]core.BindingRef, used: usize, readers: bool, depth: usize) Error!bool {
        if (id == 0) return true;
        if (remaining.* == 0 or depth > 128) return false;
        remaining.* -= 1;
        const n = m.node(id);
        switch (n.tag) {
            .panic => return true,
            .constant => {},
            .reference => {
                var ref = m.reference(id);
                if (ref.unit == 0) ref.unit = m.unit;
                const owner = try self.unit(ref.unit);
                const binding = owner.binding(ref.binding);
                if (binding.kind == .external) {
                    ref = binding.target;
                    if (ref.unit == 0) ref.unit = owner.unit;
                }
                const source = try self.unit(ref.unit);
                const kind = source.binding(ref.binding).kind;
                if (kind != .local and kind != .parameter) {
                    const body = source.body(ref.binding) orelse return false;
                    if (body.is_function) {
                        if (!readers) return false;
                        const value = (try self.planValue(m, id, remaining, depth + 1)) orelse return false;
                        var descriptor = false;
                        return self.readerArgument(value, &descriptor, remaining);
                    }
                    if (!try self.numericCallBody(ref, &.{}, null, .{ .unit = m.unit, .ty = n.ty }, remaining, active, used, readers)) return false;
                }
            },
            .scalar, .logical => {
                if (!try self.numericExpression(m, n.a, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1)) return false;
            },
            .bind => {
                if (!try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1)) return false;
                if (readers) if (try self.planValue(m, n.b, remaining, depth + 1)) |value| try self.bindings.append(self.allocator, .{ .unit = m.unit, .id = n.a, .value = value, .remaining = 0 });
            },
            .construct, .return_ => if (!try self.numericExpression(m, if (n.tag == .return_) n.a else n.b, remaining, active, used, readers, depth + 1)) return false,
            .closure => {
                if (!readers) return false;
                const value = (try self.planValue(m, id, remaining, depth + 1)) orelse return false;
                var descriptor = false;
                return self.readerArgument(value, &descriptor, remaining);
            },
            .apply => {
                if (!try self.numericExpression(m, n.a, remaining, active, used, readers, depth + 1)) return false;
                const function = (try self.planValue(m, n.a, remaining, depth + 1)) orelse return false;
                const argument = (try self.planValue(m, n.b, remaining, depth + 1)) orelse return false;
                if (!try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1)) return false;
                if (!try self.plannedCallback(function, argument, remaining, active, used, depth + 1)) return false;
            },
            .pattern_bind => {
                if (!try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, n.c, remaining, active, used, readers, depth + 1)) return false;
            },
            .project => {
                const projection = m.projection(n.b);
                if (projection.variants.len == 0) {
                    const receiver = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(n.a) }, 0);
                    const owner = try self.unit(receiver.unit);
                    const record = owner.types.node(receiver.ty);
                    if (record.tag != .record) return false;
                    var found = false;
                    const name = m.fieldSpelling(projection.field) orelse return false;
                    for (0..record.b) |index| {
                        const field = owner.types.recordField(record, index);
                        if (std.mem.eql(u8, name, owner.fieldSpelling(field.name) orelse return false)) found = true;
                    }
                    if (!found) return false;
                }
                if (!try self.numericExpression(m, n.a, remaining, active, used, readers, depth + 1)) return false;
            },
            .match => {
                for (m.matchInputs(id)) |input| if (!try self.numericExpression(m, input, remaining, active, used, readers, depth + 1)) return false;
                for (m.matchArms(id)) |arm| {
                    if (!try self.numericExpression(m, arm.guard, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, arm.body, remaining, active, used, readers, depth + 1)) return false;
                }
            },
            .if_value, .if_stmt => {
                if (!try self.numericExpression(m, n.a, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, n.c, remaining, active, used, readers, depth + 1)) return false;
            },
            .record_merge => {
                if (!try self.numericExpression(m, n.a, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1)) return false;
            },
            .block, .suite, .product, .record => for (m.children(id)) |child| {
                if (!try self.numericExpression(m, child, remaining, active, used, readers, depth + 1)) return false;
            },
            .storage => {
                if (!readers) return false;
                const op: @import("../check/storage_ops.zig").Op = @fromBackingInt(@intCast(n.c));
                switch (op) {
                    .at, .link, .view, .load, .length, .read => {},
                    .push, .write => {
                        if (!self.planning_writer) return false;
                        const args = m.children(id);
                        const receiver = (try self.planValue(m, args[0], remaining, depth + 1)) orelse return false;
                        if (receiver.root == null) return false;
                        if (op == .push and (receiver.tag != .array or receiver.mode == .fixed)) return false;
                        if (op == .write and receiver.tag != .ref and receiver.tag != .link) return false;
                    },
                    else => return false,
                }
                for (m.children(id)) |child| if (!try self.numericExpression(m, child, remaining, active, used, readers, depth + 1)) return false;
            },
            .update => {
                if (!self.planning_writer) return false;
                const info = m.updateInfo(id);
                const selectors = m.updateSelectors(id);
                var receiver = (try self.planValue(m, info.root, remaining, depth + 1)) orelse return false;
                var row = false;
                for (selectors) |selector| {
                    if (selector.kind == .index) {
                        if (row or receiver.root == null or (receiver.tag != .array and receiver.tag != .view)) return false;
                        if (!try self.numericExpression(m, selector.index, remaining, active, used, readers, depth + 1)) return false;
                        receiver = self.roots.items[receiver.root.?].element;
                        row = true;
                    } else {
                        const projection = m.projection(selector.projection);
                        const name = m.fieldSpelling(projection.field) orelse return false;
                        receiver = dataField(receiver, name) orelse return false;
                    }
                }
                if (!row and !try self.selectedInlineType(.{ .unit = m.unit, .ty = m.typeOf(info.root) }, remaining)) return false;
                const before = self.bindings.items.len;
                defer self.bindings.shrinkRetainingCapacity(before);
                try self.bindings.append(self.allocator, .{ .unit = m.unit, .id = info.self_binding, .value = receiver, .remaining = 0 });
                if (!try self.numericExpression(m, info.value, remaining, active, used, readers, depth + 1)) return false;
            },
            .array_op => {
                if (!readers) return false;
                const op: @import("collection_ops.zig").Op = @fromBackingInt(@intCast(n.c));
                switch (op) {
                    .length, .get, .identity, .cursor, .cursor_has, .cursor_value, .cursor_advance => {},
                    else => return false,
                }
                for (m.children(id)) |child| if (!try self.numericExpression(m, child, remaining, active, used, readers, depth + 1)) return false;
            },
            .loop => {
                const loop = m.loopInfo(id);
                if (loop.kind != .range and !readers) return false;
                if (!try self.numericExpression(m, loop.first, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, loop.end, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, loop.body, remaining, active, used, readers, depth + 1)) return false;
            },
            .call => {
                const call = m.call(id);
                var target = call.target;
                if (target.unit == 0) target.unit = m.unit;
                for (call.arguments) |argument| if (!try self.numericExpression(m, argument, remaining, active, used, readers, depth + 1)) return false;
                const declaration = (try self.unit(target.unit)).body(target.binding) orelse return false;
                if (call.arguments.len < (try self.unit(target.unit)).bodyParameters(declaration).len) {
                    const value = (try self.planValue(m, id, remaining, depth + 1)) orelse return false;
                    if (value.tag != .callable) return false;
                    if (readers) {
                        var descriptor = false;
                        return self.readerArgument(value, &descriptor, remaining);
                    }
                    for (value.fields) |field| if (!plainShape(field)) return false;
                    return true;
                }
                const inputs = try self.arena.allocator().alloc(TypeRef, call.arguments.len);
                const values = try self.arena.allocator().alloc(Value, call.arguments.len);
                var all_known = true;
                for (inputs, values, call.arguments) |*input, *value, argument| {
                    input.* = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(argument) }, 0);
                    if (try self.planValue(m, argument, remaining, depth + 1)) |known| value.* = known else all_known = false;
                }
                if (!try self.numericCallBody(target, inputs, if (all_known) values else null, .{ .unit = m.unit, .ty = n.ty }, remaining, active, used, readers)) return false;
                if (try self.planValue(m, id, remaining, depth + 1)) |value| if (value.tag == .callable) {
                    if (readers) {
                        var descriptor = false;
                        return self.readerArgument(value, &descriptor, remaining);
                    }
                    for (value.fields) |field| if (!plainShape(field)) return false;
                    return true;
                };
            },
            .associated => {
                if (!try self.numericExpression(m, n.a, remaining, active, used, readers, depth + 1) or !try self.numericExpression(m, n.b, remaining, active, used, readers, depth + 1)) return false;
                const first = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(n.a) }, 0);
                const second = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(n.b) }, 0);
                const a = (try self.unit(first.unit)).types.node(first.ty);
                const b = (try self.unit(second.unit)).types.node(second.ty);
                // Equal concrete primitive receivers select the same catalog
                // family; user nominal overloads remain on the existing path.
                if (a.tag != b.tag or (a.tag != .u32 and a.tag != .f32 and a.tag != .boolean)) return false;
                const identity = T.receiverIdentity(a) orelse return false;
                const target = (try self.dispatchTarget(m, identity, n.c, .none)) orelse return false;
                const actual_output = try self.resolveType(.{ .unit = m.unit, .ty = n.ty }, 0);
                if ((try self.unit(actual_output.unit)).types.node(actual_output.ty).tag == .function) {
                    const partial = (try self.planValue(m, id, remaining, depth + 1)) orelse return false;
                    return partial.tag == .callable;
                }
                if (!try self.numericCallBody(target, &.{ first, second }, null, .{ .unit = m.unit, .ty = n.ty }, remaining, active, used, readers)) return false;
            },
            else => return false,
        }
        if (readers) {
            if (n.tag == .reference or n.tag == .project or n.tag == .call) if (try self.planValue(m, id, remaining, depth + 1)) |value| if (value.tag == .callable) {
                var descriptor = false;
                return self.readerArgument(value, &descriptor, remaining);
            };
            const actual = try self.resolveType(.{ .unit = m.unit, .ty = n.ty }, 0);
            return call_plan.readerType(try self.unit(actual.unit), actual.ty, remaining, 0);
        }
        return self.selectedInlineType(.{ .unit = m.unit, .ty = n.ty }, remaining);
    }
    /// Scalar leaves use a normal Wasm call, not repeated source expansion.
    /// The initial ABI transports F32 as exact i32 bits, matching Value.word.
    fn reusableCall(self: *Generator, m: *const core.Module, target: core.BindingRef, arguments: []const Value) Error!?Value {
        const body = m.body(target.binding) orelse return null;
        const raw_result_type = m.typeOf(body.root);
        const owned_result = m.types.node(raw_result_type).tag == .array;
        var result_type = raw_result_type;
        for (arguments) |arg| if (arg.tag != .scalar or arg.demand != null) return null;
        var remaining: usize = 100_000;
        if (owned_result) {
            var arrays: usize = 0;
            if (!call_plan.destinationBody(m, body.root, &arrays, &remaining, 0) or arrays != 1) return null;
        } else if (!call_plan.scalarBody(m, body.root, &remaining, 0)) {
            var active: [128]core.BindingRef = undefined;
            active[0] = target;
            if (!try self.numericExpression(m, body.root, &remaining, &active, 1, false, 0)) return null;
        }
        if (!owned_result) {
            const resolved = try self.resolveType(.{ .unit = m.unit, .ty = raw_result_type }, 0);
            const tag = (try self.unit(resolved.unit)).types.node(resolved.ty).tag;
            result_type = switch (tag) {
                .unit => T.unit,
                .boolean => T.boolean,
                .u32 => T.u32_type,
                .f32 => T.f32_type,
                else => return null,
            };
        }
        const destination: ?Value = if (owned_result) blk: {
            const element_shape = try self.shape(m, body.root, m.types.node(result_type).a, 0);
            if (!plainShape(element_shape)) return null;
            break :blk try self.reserveOwner(m, body.root, .fixed, element_shape);
        } else null;
        var evidence: std.ArrayList(u32) = .empty;
        defer evidence.deinit(self.allocator);
        try evidence.append(self.allocator, result_type);
        var type_work: usize = 4096;
        var type_key = selected_types.Builder.init(self.allocator, &type_work, .{});
        defer type_key.deinit();
        for (m.bodyParameters(body), arguments) |parameter, arg| {
            try evidence.appendSlice(self.allocator, &.{ parameter.ty, @intFromBool(arg.floating) });
            try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = parameter.ty }, &evidence, &type_key, 0);
        }
        try self.finishSelectedTypes(m, body.root, &evidence, &type_key);
        const key: call_plan.Key = .{ .unit = m.unit, .binding = target.binding, .evidence = evidence.items };
        const index = if (self.calls.find(key)) |found| found else blk: {
            const parameter_count = std.math.add(usize, arguments.len, if (owned_result) 3 else 0) catch return self.unsupported(m, body.root);
            const signature = try self.allocator.alloc(wasm.ValueType, parameter_count);
            defer self.allocator.free(signature);
            @memset(signature, .i32);
            const function = self.module.addTypedFunction(signature, .i32, .scalar) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.unsupported(m, body.root),
            };
            const inserted = try self.calls.insert(key, function, result_type == T.f32_type);
            var child: Generator = .{
                .allocator = self.allocator,
                .arena = std.heap.ArenaAllocator.init(self.allocator),
                .calls = .{ .allocator = self.allocator },
                .active_calls = self.active_calls,
                .specialize = false,
                .units = self.units,
                .unit_views = self.unit_views,
                .proof_cache = self.proof_cache,
                .dispatches = self.dispatches,
                .capacity_requests = self.capacity_requests,
                .validation_budget = self.validation_budget,
                .module = self.module,
                .runtime = self.runtime,
                .fixed_region = self.fixed_region,
                .c = .{ .module = self.module, .function = function },
            };
            defer child.deinit();
            try child.type_arguments.appendSlice(self.allocator, self.type_arguments.items);
            const inputs = try self.allocator.alloc(Value, arguments.len);
            defer self.allocator.free(inputs);
            for (inputs, arguments, 0..) |*input, argument, parameter| input.* = .{
                .word = .{ .id = @intCast(parameter) },
                .floating = argument.floating,
            };
            if (destination) |owner| {
                const input: Value = .{
                    .tag = .array,
                    .word = try child.c.temp(),
                    .token = .{ .id = @intCast(arguments.len) },
                    .epoch_low = .{ .id = @intCast(arguments.len + 1) },
                    .epoch_high = .{ .id = @intCast(arguments.len + 2) },
                    .root = 0,
                    .mode = .fixed,
                };
                const shape_ = try child.cloneShape((try self.root(m, body.root, owner)).element);
                try child.roots.append(self.allocator, .{ .word = input.word, .token = input.token, .epoch_low = input.epoch_low, .epoch_high = input.epoch_high, .stack = self.fixed_region, .depth = 0, .element = shape_, .dedicated = false });
                child.destination = input;
                child.external_destination = 0;
            }
            const output = child.invoke(target, inputs, 0) catch |err| {
                if (child.diagnostic) |diagnostic| self.diagnostic = diagnostic;
                return err;
            };
            try child.c.value(if (owned_result) output.word else try child.scalar(m, body.root, output));
            self.calls.entries.items[inserted].building = false;
            break :blk inserted;
        };
        const entry = self.calls.entries.items[index];
        if (entry.building) return self.fail(m, body.root, .storage_unsupported, "Recursive storage specializations are not admitted");
        for (arguments) |argument| try self.c.value(argument.word);
        if (destination) |owner| {
            try self.c.value(owner.token);
            try self.c.value(owner.epoch_low);
            try self.c.value(owner.epoch_high);
        }
        try self.c.op(.call, entry.function);
        const result = try self.c.temp();
        try self.c.op(.local_set, result.id);
        if (destination) |owner| {
            try self.c.set(owner.word, result);
            return owner;
        }
        return .{ .word = result, .floating = entry.floating, .type_evidence = .{ .root = .{ .unit = m.unit, .ty = result_type }, .arguments = &.{} } };
    }
    fn inlineWords(value: Value) Error!usize {
        if (value.tag == .scalar) return 1;
        var count: usize = @intFromBool(value.variant_tags.len != 0);
        for (value.fields) |field| count = std.math.add(usize, count, try inlineWords(field)) catch return error.Declined;
        return count;
    }
    fn inlineParameter(self: *Generator, original: Value, next: *u32) Error!Value {
        var value = original;
        value.literal = null;
        if (value.tag == .scalar or value.variant_tags.len != 0) {
            value.word = .{ .id = next.* };
            next.* += 1;
        } else value.word = (try self.constant(0)).word;
        value.variant_index = null;
        value.variant_possible = &.{};
        value.fields = try self.arena.allocator().alloc(Value, original.fields.len);
        for (value.fields, original.fields) |*field, input| field.* = try self.inlineParameter(input, next);
        return value;
    }
    fn inlineArgument(self: *Generator, value: Value) Error!void {
        if (value.tag == .scalar or value.variant_tags.len != 0) try self.c.value(value.word);
        for (value.fields) |field| try self.inlineArgument(field);
    }
    /// Inline fields travel as ordinary word parameters. Aggregate results use
    /// a caller-owned slot, loaded into locals and rewound immediately after
    /// the call. The callee cannot retain this slot or manufacture an owner.
    fn reusableInlineCall(self: *Generator, m: *const core.Module, target: core.BindingRef, arguments: []const Value) Error!?Value {
        const body = m.body(target.binding) orelse return null;
        var remaining: usize = 100_000;
        if (!call_plan.inlineBody(self.units, m, target.binding, &remaining)) {
            var active: [128]core.BindingRef = undefined;
            active[0] = target;
            if (!try self.numericExpression(m, body.root, &remaining, &active, 1, false, 0)) return null;
        }
        for (m.bodyParameters(body), arguments) |parameter, argument| {
            if (!plainShape(argument) or argument.demand != null or argument.host != null) return null;
            if (!try self.selectedInlineType(.{ .unit = m.unit, .ty = parameter.ty }, &remaining)) return null;
        }
        const result_type = m.typeOf(body.root);
        const result_shape = try self.shape(m, body.root, result_type, 0);
        if (!plainShape(result_shape)) return null;
        var words: usize = 0;
        for (arguments) |argument| words = std.math.add(usize, words, try inlineWords(argument)) catch return self.unsupported(m, body.root);
        const aggregate_result = result_shape.tag == .aggregate;
        const parameter_count = std.math.add(usize, words, @intFromBool(aggregate_result)) catch return self.unsupported(m, body.root);
        if (parameter_count > std.math.maxInt(u32)) return self.unsupported(m, body.root);
        var evidence: std.ArrayList(u32) = .empty;
        defer evidence.deinit(self.allocator);
        try evidence.appendSlice(self.allocator, &.{ std.math.maxInt(u32), result_type });
        var type_work: usize = 4096;
        var type_key = selected_types.Builder.init(self.allocator, &type_work, .{});
        defer type_key.deinit();
        for (m.bodyParameters(body)) |parameter| try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = parameter.ty }, &evidence, &type_key, 0);
        try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = result_type }, &evidence, &type_key, 0);
        try self.finishSelectedTypes(m, body.root, &evidence, &type_key);
        const key: call_plan.Key = .{ .unit = m.unit, .binding = target.binding, .evidence = evidence.items };
        const index = if (self.calls.find(key)) |found| found else blk: {
            const signature = try self.allocator.alloc(wasm.ValueType, parameter_count);
            defer self.allocator.free(signature);
            @memset(signature, .i32);
            const function = self.module.addTypedFunction(signature, .i32, .scalar) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.unsupported(m, body.root),
            };
            const inserted = try self.calls.insert(key, function, result_shape.floating);
            var child: Generator = .{
                .allocator = self.allocator,
                .arena = std.heap.ArenaAllocator.init(self.allocator),
                .calls = .{ .allocator = self.allocator },
                .active_calls = self.active_calls,
                .specialize = false,
                .units = self.units,
                .unit_views = self.unit_views,
                .proof_cache = self.proof_cache,
                .dispatches = self.dispatches,
                .capacity_requests = self.capacity_requests,
                .validation_budget = self.validation_budget,
                .module = self.module,
                .runtime = self.runtime,
                .fixed_region = self.fixed_region,
                .c = .{ .module = self.module, .function = function },
            };
            defer child.deinit();
            try child.type_arguments.appendSlice(self.allocator, self.type_arguments.items);
            const inputs = try child.arena.allocator().alloc(Value, arguments.len);
            var next: u32 = 0;
            for (inputs, arguments) |*input, argument| input.* = try child.inlineParameter(argument, &next);
            const output = child.invoke(target, inputs, 0) catch |err| {
                if (child.diagnostic) |diagnostic| self.diagnostic = diagnostic;
                return err;
            };
            if (aggregate_result) {
                try child.storeValue(.{ .id = @intCast(words) }, 0, output);
                try child.c.value(0);
            } else try child.c.value(try child.scalar(m, body.root, output));
            self.calls.entries.items[inserted].building = false;
            break :blk inserted;
        };
        const entry = self.calls.entries.items[index];
        if (entry.building) return self.fail(m, body.root, .storage_unsupported, "Recursive inline specializations are not admitted");
        const first_root = self.roots.items.len;
        const mark: ?Local = if (aggregate_result) try self.frameMark() else null;
        var address: ?Local = null;
        if (aggregate_result) {
            const slot = try self.arrayWithShape(m, body.root, (try self.constant(1)).word, .fixed, result_shape);
            address = try self.c.temp();
            try self.c.set(address.?, .{ .call, self.runtime.functions.address, slot.token, slot.epoch_low, slot.epoch_high, slot.word, 0 });
        }
        for (arguments) |argument| try self.inlineArgument(argument);
        if (address) |pointer| try self.c.value(pointer);
        try self.c.op(.call, entry.function);
        const word = try self.c.temp();
        try self.c.op(.local_set, word.id);
        var result = if (address) |pointer| try self.loadValue(pointer, 0, result_shape) else Value{ .word = word, .floating = entry.floating };
        if (mark) |saved| {
            try self.release(first_root, null);
            try self.c.value(.{ .call, self.runtime.functions.rewind, self.fixed_region, saved });
        }
        result.type_evidence = .{ .root = .{ .unit = m.unit, .ty = result_type }, .arguments = &.{} };
        return result;
    }
    fn readerWords(value: Value) usize {
        if (value.tag == .aggregate or value.tag == .callable) {
            var count: usize = @intFromBool(value.variant_tags.len != 0);
            for (value.fields) |field| count += readerWords(field);
            return count;
        }
        return switch (value.tag) {
            .scalar => 1,
            .array => 4,
            .ref, .link => 5,
            .view => 6,
            else => unreachable,
        };
    }
    fn readerArgument(self: *Generator, value: Value, descriptor: *bool, remaining: *usize) bool {
        if (remaining.* == 0 or value.host != null or value.demand != null) return false;
        remaining.* -= 1;
        switch (value.tag) {
            .scalar => return true,
            .aggregate, .callable => {
                if (value.tag == .callable) {
                    if (value.callable == null) return false;
                    descriptor.* = true;
                }
                for (value.fields) |field| if (!self.readerArgument(field, descriptor, remaining)) return false;
                return true;
            },
            .array, .ref, .link, .view => {
                const owner_root = value.root orelse return false;
                if (!plainShape(self.roots.items[owner_root].element)) return false;
                for (value.other_roots) |other| if (!plainShape(self.roots.items[other].element)) return false;
                descriptor.* = true;
                return true;
            },
        }
    }
    fn readerLayoutEvidence(self: *Generator, m: *const core.Module, id: core.Id, value: Value, evidence: *std.ArrayList(u32), keys: *selected_types.Builder) Error!void {
        const remaining = keys.remaining;
        if (remaining.* == 0 or value.name.len >= remaining.*) return self.fail(m, id, .storage_unsupported, "The static callback capture schema exceeds its supported bound");
        remaining.* -= 1;
        try evidence.appendSlice(self.allocator, &.{ @backingInt(value.tag), @backingInt(value.mode), @intFromBool(value.sequence), @intFromBool(value.floating), @intCast(value.fields.len), @intCast(value.variant_tags.len), @intCast(value.name.len), if (value.variant_index) |selected| @intCast(selected) else std.math.maxInt(u32) });
        for (value.name) |byte| {
            try evidence.append(self.allocator, byte);
            remaining.* -= 1;
        }
        if (value.nominal) |identity| try evidence.appendSlice(self.allocator, &.{ 1, identity.unit, identity.decl }) else try evidence.append(self.allocator, 0);
        if (value.type_evidence) |known| {
            try evidence.append(self.allocator, 1);
            try self.selectedType(m, id, .{ .unit = known.root.unit, .ty = known.root.ty, .environment = known.arguments }, evidence, keys, 0);
        } else try evidence.append(self.allocator, 0);
        if (value.callable) |callable| {
            try evidence.appendSlice(self.allocator, &.{ callable.unit, callable.target, callable.node });
            const owner = try self.unit(callable.unit);
            for (callable.captures) |binding| try self.selectedType(m, id, .{ .unit = owner.unit, .ty = owner.binding(binding).ty, .environment = callable.types }, evidence, keys, 0);
        }
        try evidence.appendSlice(self.allocator, value.variant_tags);
        try evidence.append(self.allocator, @intCast(value.variant_possible.len));
        for (value.variant_possible) |possible| try evidence.append(self.allocator, @intFromBool(possible));
        for (value.fields) |field| try self.readerLayoutEvidence(m, id, field, evidence, keys);
    }
    fn readerReads(self: *Generator, value: Value) Error!void {
        if (value.tag == .aggregate or value.tag == .callable) {
            for (value.fields) |field| try self.readerReads(field);
        } else if (value.tag != .scalar) try self.registerShapeRead(value);
    }
    fn readerValues(self: *Generator, value: Value) Error!void {
        if (value.tag == .aggregate or value.tag == .callable) {
            if (value.variant_tags.len != 0) try self.c.value(value.word);
            for (value.fields) |field| try self.readerValues(field);
            return;
        }
        try self.c.value(value.word);
        if (value.tag == .scalar) return;
        try self.c.value(value.token);
        try self.c.value(value.epoch_low);
        try self.c.value(value.epoch_high);
        if (value.tag != .array) try self.c.value(value.index);
        if (value.tag == .view) try self.c.value(value.length);
    }
    fn readerPlainShape(self: *Generator, source: Value) Error!Value {
        var value = try self.cloneShape(source);
        value.literal = null;
        value.variant_index = null;
        value.variant_possible = &.{};
        for (value.fields) |*field| field.* = try self.readerPlainShape(field.*);
        return value;
    }
    // Runtime descriptors are rebound to independent child roots; owner identity
    // and epochs remain runtime parameters rather than specialization keys.
    fn readerParameter(self: *Generator, child: *Generator, input: *Value, argument: Value, next: *u32) Error!void {
        input.* = argument;
        input.literal = null;
        if (argument.tag == .aggregate or argument.tag == .callable) {
            input.fields = try child.arena.allocator().alloc(Value, argument.fields.len);
            input.word = if (argument.variant_tags.len != 0) .{ .id = next.* } else (try child.constant(0)).word;
            if (argument.variant_tags.len != 0) next.* += 1;
            for (input.fields, argument.fields) |*field, source| try self.readerParameter(child, field, source, next);
            return;
        }
        input.word = .{ .id = next.* };
        input.literal = null;
        next.* += 1;
        input.depth = 0;
        if (argument.tag == .scalar) return;
        input.token = .{ .id = next.* };
        input.epoch_low = .{ .id = next.* + 1 };
        input.epoch_high = .{ .id = next.* + 2 };
        next.* += 3;
        if (argument.tag != .array) {
            input.index = .{ .id = next.* };
            next.* += 1;
        }
        if (argument.tag == .view) {
            input.length = .{ .id = next.* };
            next.* += 1;
        }
        // Only reads and aliases of existing inputs are admitted. A joined input's
        // selected runtime descriptor keeps its actual owner and epoch;
        // this local root supplies the already-proved plain row layout.
        input.root = child.roots.items.len;
        input.other_roots = &.{};
        try child.roots.append(self.allocator, .{
            .word = input.word,
            .token = input.token,
            .epoch_low = input.epoch_low,
            .epoch_high = input.epoch_high,
            .stack = self.fixed_region,
            .depth = 0,
            .element = try child.readerPlainShape(self.roots.items[argument.root.?].element),
            .element_initialized = self.roots.items[argument.root.?].element_initialized,
            .dedicated = false,
        });
    }
    const EnvironmentKey = struct { address: usize, length: usize };
    const EnvironmentCopies = std.AutoHashMapUnmanaged(EnvironmentKey, []const TypeArgument);
    fn retainEnvironment(self: *Generator, source: []const TypeArgument, copies: *EnvironmentCopies, depth: usize) Error![]const TypeArgument {
        if (depth > 128) return error.Declined;
        if (source.len == 0) return &.{};
        const key: EnvironmentKey = .{ .address = @intFromPtr(source.ptr), .length = source.len };
        if (copies.get(key)) |known| return known;
        const result = try self.arena.allocator().dupe(TypeArgument, source);
        try copies.put(self.allocator, key, result);
        for (result) |*item| if (item.environment) |environment| {
            item.environment = try self.retainEnvironment(environment, copies, depth + 1);
        };
        return result;
    }
    fn retainReaderResult(self: *Generator, source: Value, inputs: usize, copies: *EnvironmentCopies, reachable: bool, depth: usize) Error!Value {
        if (depth > 128 or source.host != null or source.demand != null or source.tag == .callable) return error.Declined;
        if (source.tag != .scalar and source.tag != .aggregate) {
            if (source.root) |input| {
                if (input >= inputs) return error.Declined;
            } else if (reachable) return error.Declined;
            for (source.other_roots) |other| if (other >= inputs) return error.Declined;
        }
        // Root indices are parameter-descriptor ordinals here, not retained
        // caller identities. Every hit substitutes the current argument roots.
        var result = source;
        result.other_roots = try self.arena.allocator().dupe(usize, source.other_roots);
        result.variant_tags = try self.arena.allocator().dupe(u32, source.variant_tags);
        result.variant_possible = try self.arena.allocator().dupe(bool, source.variant_possible);
        result.fields = try self.arena.allocator().alloc(Value, source.fields.len);
        for (result.fields, source.fields, 0..) |*field, original, index| {
            const live = reachable and (source.variant_tags.len == 0 or possibleVariant(source, index));
            field.* = try self.retainReaderResult(original, inputs, copies, live, depth + 1);
        }
        if (source.type_evidence) |known| {
            var root_type = known.root;
            if (root_type.environment) |environment| root_type.environment = try self.retainEnvironment(environment, copies, 0);
            result.type_evidence = .{ .root = root_type, .arguments = try self.retainEnvironment(known.arguments, copies, 0) };
        }
        return result;
    }
    fn readerDescriptors(self: *Generator, value: Value, output: *std.ArrayList(Value)) Error!void {
        if (value.tag == .aggregate or value.tag == .callable) {
            for (value.fields) |field| try self.readerDescriptors(field, output);
        } else if (value.tag != .scalar) try output.append(self.allocator, value);
    }
    fn readerResult(self: *Generator, template: Value, descriptors: []const Value) Error!Value {
        var result = template;
        result.fields = try self.arena.allocator().alloc(Value, template.fields.len);
        for (result.fields, template.fields) |*field, original| field.* = try self.readerResult(original, descriptors);
        if (template.tag == .scalar or template.tag == .aggregate) return result;
        result.root = null;
        result.other_roots = &.{};
        result.depth = 0;
        if (template.root) |input| try self.unionRoots(&result, descriptors[input]);
        for (template.other_roots) |input| try self.unionRoots(&result, descriptors[input]);
        for (self.roots.items, 0..) |owner, index| {
            if (hasRoot(result, index)) result.depth = @max(result.depth, owner.depth);
        }
        return result;
    }
    // ABI slots are temporary U32 buffers, never language rows containing
    // owning descriptors. Every descriptor word is copied before slot rewind.
    fn storeReaderResult(self: *Generator, address: Local, offset: u32, value: Value) Error!void {
        var at = offset;
        if (value.tag == .aggregate or value.tag == .callable) {
            if (value.variant_tags.len != 0) {
                try self.c.store(address, at, value.word);
                at += 4;
            }
            for (value.fields) |field| {
                try self.storeReaderResult(address, at, field);
                at += @intCast(readerWords(field) * 4);
            }
            return;
        }
        try self.c.store(address, at, value.word);
        if (value.tag == .scalar) return;
        try self.c.store(address, at + 4, value.token);
        try self.c.store(address, at + 8, value.epoch_low);
        try self.c.store(address, at + 12, value.epoch_high);
        if (value.tag != .array) try self.c.store(address, at + 16, value.index);
        if (value.tag == .view) try self.c.store(address, at + 20, value.length);
    }
    fn loadReaderResult(self: *Generator, address: Local, offset: u32, template: Value) Error!Value {
        var result = template;
        var at = offset;
        result.word = try self.c.temp();
        if (result.tag == .aggregate or result.tag == .callable) {
            if (result.variant_tags.len != 0) {
                try self.c.set(result.word, .{ .load, address, at });
                at += 4;
            } else try self.c.set(result.word, 0);
            result.fields = try self.arena.allocator().alloc(Value, template.fields.len);
            for (result.fields, template.fields) |*field, original| {
                field.* = try self.loadReaderResult(address, at, original);
                at += @intCast(readerWords(original) * 4);
            }
            return result;
        }
        try self.c.set(result.word, .{ .load, address, at });
        if (result.tag == .scalar) return result;
        result.token = try self.c.temp();
        result.epoch_low = try self.c.temp();
        result.epoch_high = try self.c.temp();
        try self.c.set(result.token, .{ .load, address, at + 4 });
        try self.c.set(result.epoch_low, .{ .load, address, at + 8 });
        try self.c.set(result.epoch_high, .{ .load, address, at + 12 });
        if (result.tag != .array) {
            result.index = try self.c.temp();
            try self.c.set(result.index, .{ .load, address, at + 16 });
        }
        if (result.tag == .view) {
            result.length = try self.c.temp();
            try self.c.set(result.length, .{ .load, address, at + 20 });
        }
        return result;
    }
    fn reusableReaderCall(self: *Generator, m: *const core.Module, target: core.BindingRef, arguments: []const Value) Error!?Value {
        const body = m.body(target.binding) orelse return null;
        const result_type = m.typeOf(body.root);
        var remaining: usize = 100_000;
        const actual_result = try self.resolveType(.{ .unit = m.unit, .ty = result_type }, 0);
        if (!call_plan.readerType(try self.unit(actual_result.unit), actual_result.ty, &remaining, 0)) return null;
        const result_shape = try self.shape(m, body.root, result_type, 0);
        const aggregate_result = result_shape.tag != .scalar;
        var has_descriptor = false;
        var words: usize = 0;
        for (m.bodyParameters(body), arguments) |parameter, argument| {
            if (!self.readerArgument(argument, &has_descriptor, &remaining)) return null;
            const actual = try self.resolveType(.{ .unit = m.unit, .ty = parameter.ty }, 0);
            if (argument.tag != .callable and !call_plan.readerType(try self.unit(actual.unit), actual.ty, &remaining, 0)) return null;
            words = std.math.add(usize, words, readerWords(argument)) catch return self.unsupported(m, body.root);
        }
        if (!has_descriptor) return null;
        var descriptors: std.ArrayList(Value) = .empty;
        defer descriptors.deinit(self.allocator);
        for (arguments) |argument| try self.readerDescriptors(argument, &descriptors);
        if (!call_plan.readerBody(m, body.root, &remaining, 0)) {
            var active: [128]core.BindingRef = undefined;
            active[0] = target;
            const before = self.bindings.items.len;
            defer self.bindings.shrinkRetainingCapacity(before);
            for (m.bodyParameters(body), arguments) |parameter, value| try self.bindings.append(self.allocator, .{ .unit = m.unit, .id = parameter.binding, .value = value, .remaining = 0 });
            if (!try self.numericExpression(m, body.root, &remaining, &active, 1, true, 0)) return null;
        }
        const parameter_words = std.math.add(usize, words, @intFromBool(aggregate_result)) catch return null;
        if (parameter_words > std.math.maxInt(u32)) return null;
        // Reused Wasm readers perform their loads in a separate generator,
        // including on cache hits. Preserve their reads in caller loops too.
        for (arguments) |argument| try self.readerReads(argument);
        var evidence: std.ArrayList(u32) = .empty;
        defer evidence.deinit(self.allocator);
        try evidence.appendSlice(self.allocator, &.{ std.math.maxInt(u32) - 1, result_type });
        var type_work: usize = 4096;
        var type_key = selected_types.Builder.init(self.allocator, &type_work, .{});
        defer type_key.deinit();
        for (arguments) |argument| try self.readerLayoutEvidence(m, body.root, argument, &evidence, &type_key);
        for (m.bodyParameters(body)) |parameter| try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = parameter.ty }, &evidence, &type_key, 0);
        try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = result_type }, &evidence, &type_key, 0);
        try self.finishSelectedTypes(m, body.root, &evidence, &type_key);
        const key: call_plan.Key = .{ .unit = m.unit, .binding = target.binding, .evidence = evidence.items };
        const index = if (self.calls.find(key)) |found| found else blk: {
            const signature = try self.allocator.alloc(wasm.ValueType, parameter_words);
            defer self.allocator.free(signature);
            @memset(signature, .i32);
            const function = self.module.addTypedFunction(signature, .i32, .scalar) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.unsupported(m, body.root),
            };
            const inserted = try self.calls.insert(key, function, result_shape.floating);
            var child: Generator = .{
                .allocator = self.allocator,
                .arena = std.heap.ArenaAllocator.init(self.allocator),
                .calls = .{ .allocator = self.allocator },
                .active_calls = self.active_calls,
                .specialize = false,
                .units = self.units,
                .unit_views = self.unit_views,
                .proof_cache = self.proof_cache,
                .dispatches = self.dispatches,
                .capacity_requests = self.capacity_requests,
                .validation_budget = self.validation_budget,
                .module = self.module,
                .runtime = self.runtime,
                .fixed_region = self.fixed_region,
                .c = .{ .module = self.module, .function = function },
            };
            defer child.deinit();
            try child.type_arguments.appendSlice(self.allocator, self.type_arguments.items);
            const inputs = try child.arena.allocator().alloc(Value, arguments.len);
            var next: u32 = 0;
            for (inputs, arguments) |*input, argument| {
                try self.readerParameter(&child, input, argument, &next);
            }
            const output = child.invoke(target, inputs, 0) catch |err| {
                if (child.diagnostic) |diagnostic| self.diagnostic = diagnostic;
                return err;
            };
            if (aggregate_result) {
                var copies: EnvironmentCopies = .empty;
                defer copies.deinit(self.allocator);
                const template = try self.retainReaderResult(output, descriptors.items.len, &copies, true, 0);
                try self.reader_results.put(self.allocator, function, template);
                try child.storeReaderResult(.{ .id = next }, 0, output);
                try child.c.value(0);
            } else try child.c.value(try child.scalar(m, body.root, output));
            self.calls.entries.items[inserted].building = false;
            break :blk inserted;
        };
        const entry = self.calls.entries.items[index];
        if (entry.building) return self.fail(m, body.root, .storage_unsupported, "Recursive reader specializations are not admitted");
        const result_template = if (aggregate_result) try self.readerResult(self.reader_results.get(entry.function) orelse return self.unsupported(m, body.root), descriptors.items) else result_shape;
        const first_root = self.roots.items.len;
        const mark: ?Local = if (aggregate_result) try self.frameMark() else null;
        var address: ?Local = null;
        if (aggregate_result) {
            const count = std.math.cast(u32, @max(1, readerWords(result_template))) orelse return self.unsupported(m, body.root);
            const lane: Value = .{ .word = .{ .id = 0 } };
            const slot = try self.arrayWithShape(m, body.root, (try self.constant(count)).word, .fixed, lane);
            address = try self.c.temp();
            try self.c.set(address.?, .{ .call, self.runtime.functions.address, slot.token, slot.epoch_low, slot.epoch_high, slot.word, 0 });
        }
        for (arguments) |argument| try self.readerValues(argument);
        if (address) |pointer| try self.c.value(pointer);
        try self.c.op(.call, entry.function);
        const word = try self.c.temp();
        try self.c.op(.local_set, word.id);
        var result = if (address) |pointer| try self.loadReaderResult(pointer, 0, result_template) else Value{ .word = word, .floating = entry.floating };
        if (mark) |saved| {
            try self.release(first_root, null);
            try self.c.value(.{ .call, self.runtime.functions.rewind, self.fixed_region, saved });
        }
        result.type_evidence = .{ .root = .{ .unit = m.unit, .ty = result_type }, .arguments = try self.captureTypes() };
        return result;
    }
    fn writerOrdinal(owners: []const usize, owner_id: usize) Error!usize {
        return std.mem.findScalar(usize, owners, owner_id) orelse error.Declined;
    }
    fn writerInput(self: *Generator, value: *Value, owners: []const usize, assigned: []bool) Error!void {
        value.literal = null;
        value.depth = 0;
        for (value.fields) |*field| try self.writerInput(field, owners, assigned);
        if (value.tag == .scalar or value.tag == .aggregate or value.tag == .callable) return;
        const original = value.root orelse return error.Declined;
        value.root = try writerOrdinal(owners, original);
        const others = try self.arena.allocator().alloc(usize, value.other_roots.len);
        for (others, value.other_roots) |*destination, source| destination.* = try writerOrdinal(owners, source);
        value.other_roots = others;
        for (self.roots.items, 0..) |*owner, index| if (hasRoot(value.*, index) and !assigned[index]) {
            owner.word = value.word;
            owner.token = value.token;
            owner.epoch_low = value.epoch_low;
            owner.epoch_high = value.epoch_high;
            assigned[index] = true;
        };
    }
    fn clearWriterLiterals(value: *Value) void {
        value.literal = null;
        for (value.fields) |*field| clearWriterLiterals(field);
    }
    fn reusableUnitWriter(self: *Generator, m: *const core.Module, target: core.BindingRef, arguments: []const Value) Error!?Value {
        const body = m.body(target.binding) orelse return null;
        const result = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(body.root) }, 0);
        if ((try self.unit(result.unit)).types.node(result.ty).tag != .unit) return null;
        var remaining: usize = 100_000;
        var descriptor = false;
        var words: usize = 0;
        for (arguments) |argument| {
            if (!self.readerArgument(argument, &descriptor, &remaining)) return null;
            words = std.math.add(usize, words, readerWords(argument)) catch return null;
        }
        if (!descriptor) return null;
        // The same exact selected-call summary is used for reads and writes;
        // this opt-in admits only stable row writes and append-space growth.
        {
            const planning_before = self.planning_writer;
            self.planning_writer = true;
            defer self.planning_writer = planning_before;
            const bindings_before = self.bindings.items.len;
            defer self.bindings.shrinkRetainingCapacity(bindings_before);
            for (m.bodyParameters(body), arguments) |parameter, value| try self.bindings.append(self.allocator, .{ .unit = m.unit, .id = parameter.binding, .value = value, .remaining = 0 });
            var active: [128]core.BindingRef = undefined;
            active[0] = target;
            if (!try self.numericExpression(m, body.root, &remaining, &active, 1, true, 0)) return null;
        }
        var descriptors: std.ArrayList(Value) = .empty;
        defer descriptors.deinit(self.allocator);
        for (arguments) |argument| try self.readerDescriptors(argument, &descriptors);
        var owners: std.ArrayList(usize) = .empty;
        defer owners.deinit(self.allocator);
        for (descriptors.items) |value| {
            const first = value.root orelse return null;
            if (std.mem.findScalar(usize, owners.items, first) == null) try owners.append(self.allocator, first);
            for (value.other_roots) |other| if (std.mem.findScalar(usize, owners.items, other) == null) try owners.append(self.allocator, other);
        }
        var evidence: std.ArrayList(u32) = .empty;
        defer evidence.deinit(self.allocator);
        try evidence.appendSlice(self.allocator, &.{ std.math.maxInt(u32) - 2, @intCast(owners.items.len) });
        var type_work: usize = 4096;
        var type_key = selected_types.Builder.init(self.allocator, &type_work, .{});
        defer type_key.deinit();
        for (arguments) |argument| try self.readerLayoutEvidence(m, body.root, argument, &evidence, &type_key);
        for (m.bodyParameters(body)) |parameter| try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = parameter.ty }, &evidence, &type_key, 0);
        for (descriptors.items) |value| {
            try evidence.appendSlice(self.allocator, &.{ @intCast(try writerOrdinal(owners.items, value.root.?)), @intCast(value.other_roots.len) });
            for (value.other_roots) |other| try evidence.append(self.allocator, @intCast(try writerOrdinal(owners.items, other)));
        }
        for (owners.items) |owner_id| {
            const owner = self.roots.items[owner_id];
            try evidence.appendSlice(self.allocator, &.{ @intFromBool(owner.frozen), @intFromBool(owner.element_initialized) });
            try self.readerLayoutEvidence(m, body.root, owner.element, &evidence, &type_key);
        }
        try self.finishSelectedTypes(m, body.root, &evidence, &type_key);
        const key: call_plan.Key = .{ .unit = m.unit, .binding = target.binding, .evidence = evidence.items };
        const index = if (self.calls.find(key)) |found| found else blk: {
            const function = self.module.addTypedFunction(&.{.i32}, .i32, .scalar) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.unsupported(m, body.root),
            };
            const inserted = try self.calls.insert(key, function, false);
            var trace: WriterTrace = .{ .inputs = owners.items.len };
            defer trace.events.deinit(self.allocator);
            var child: Generator = .{
                .allocator = self.allocator,
                .arena = std.heap.ArenaAllocator.init(self.allocator),
                .calls = .{ .allocator = self.allocator },
                .active_calls = self.active_calls,
                .specialize = false,
                .units = self.units,
                .unit_views = self.unit_views,
                .proof_cache = self.proof_cache,
                .dispatches = self.dispatches,
                .capacity_requests = self.capacity_requests,
                .validation_budget = self.validation_budget,
                .module = self.module,
                .runtime = self.runtime,
                .fixed_region = self.fixed_region,
                .writer_trace = &trace,
                .c = .{ .module = self.module, .function = function },
            };
            defer child.deinit();
            try child.type_arguments.appendSlice(self.allocator, self.type_arguments.items);
            for (owners.items) |owner_id| {
                const original = self.roots.items[owner_id];
                var row = try child.cloneShape(original.element);
                clearWriterLiterals(&row);
                try child.roots.append(self.allocator, .{ .word = .{ .id = 0 }, .token = .{ .id = 0 }, .epoch_low = .{ .id = 0 }, .epoch_high = .{ .id = 0 }, .stack = self.fixed_region, .depth = 0, .element = row, .element_initialized = original.element_initialized, .frozen = original.frozen, .dedicated = false });
            }
            const assigned = try child.arena.allocator().alloc(bool, owners.items.len);
            @memset(assigned, false);
            const inputs = try child.arena.allocator().alloc(Value, arguments.len);
            var offset: u32 = 0;
            for (inputs, arguments) |*input, argument| {
                input.* = try child.loadReaderResult(.{ .id = 0 }, offset, argument);
                try child.writerInput(input, owners.items, assigned);
                offset += @intCast(readerWords(argument) * 4);
            }
            const output = child.invoke(target, inputs, 0) catch |err| {
                if (child.diagnostic) |diagnostic| self.diagnostic = diagnostic;
                return err;
            };
            try child.c.value(try child.scalar(m, body.root, output));
            const facts = try self.arena.allocator().alloc(WriterEvent, trace.events.items.len);
            var copies: EnvironmentCopies = .empty;
            defer copies.deinit(self.allocator);
            for (facts, trace.events.items) |*fact, original| fact.* = .{ .owner = original.owner, .kind = original.kind, .shape = try self.retainReaderResult(original.shape, 0, &copies, true, 0) };
            try self.writer_facts.put(self.allocator, function, facts);
            self.calls.entries.items[inserted].building = false;
            break :blk inserted;
        };
        const entry = self.calls.entries.items[index];
        if (entry.building) return self.fail(m, body.root, .storage_unsupported, "Recursive writer specializations are not admitted");
        // Replay the actual compiler access order even on cache hits. Caller
        // loop scopes see the same row shapes as expanded selected bodies.
        for (self.writer_facts.get(entry.function) orelse return self.unsupported(m, body.root)) |event| {
            const owner_id = owners.items[event.owner];
            if (event.kind == .write) {
                const owner = &self.roots.items[owner_id];
                try self.storedShape(m, body.root, &owner.element, event.shape, owner.depth);
                owner.element_initialized = true;
            } else {
                const owner = self.roots.items[owner_id];
                if (!includesReadShape(event.shape, owner.element) or !includesReadShape(owner.element, event.shape)) return self.fail(m, body.root, .storage_escape, "A writer call must preserve its checked read and mutation shape order");
                try self.registerShapeRead(.{ .tag = .array, .word = owner.word, .root = owner_id });
            }
        }
        const first_root = self.roots.items.len;
        const mark = try self.frameMark();
        const count = std.math.cast(u32, @max(1, words)) orelse return self.unsupported(m, body.root);
        const slot = try self.arrayWithShape(m, body.root, (try self.constant(count)).word, .fixed, .{ .word = .{ .id = 0 } });
        const address = try self.c.temp();
        try self.c.set(address, .{ .call, self.runtime.functions.address, slot.token, slot.epoch_low, slot.epoch_high, slot.word, 0 });
        var offset: u32 = 0;
        for (arguments) |argument| {
            try self.storeReaderResult(address, offset, argument);
            offset += @intCast(readerWords(argument) * 4);
        }
        try self.c.value(address);
        try self.c.op(.call, entry.function);
        const word = try self.c.temp();
        try self.c.op(.local_set, word.id);
        try self.release(first_root, null);
        try self.c.value(.{ .call, self.runtime.functions.rewind, self.fixed_region, mark });
        return .{ .word = word, .type_evidence = .{ .root = .{ .unit = m.unit, .ty = T.unit }, .arguments = &.{} } };
    }
    fn selectedCallbacks(self: *Generator, m: *const core.Module, id: core.Id, value: Value, path: *std.ArrayList(u32), selection: *std.ArrayList(u32), remaining: *usize, depth: usize) Error!void {
        if (remaining.* == 0 or depth > 128) return self.fail(m, id, .storage_unsupported, "The static callback selection tree exceeds the supported bound");
        remaining.* -= 1;
        if (value.callable) |callable| {
            try selection.append(self.allocator, @intCast(path.items.len));
            try selection.appendSlice(self.allocator, path.items);
            try selection.appendSlice(self.allocator, &.{ callable.unit, callable.target, callable.node });
        }
        if (value.tag != .aggregate and value.callable == null) return;
        for (value.fields, 0..) |field, index| {
            const before = path.items.len;
            if (field.name.len != 0) {
                try path.appendSlice(self.allocator, &.{ 1, @intCast(field.name.len) });
                for (field.name) |byte| try path.append(self.allocator, byte);
            } else try path.appendSlice(self.allocator, &.{ 0, @intCast(index) });
            try self.selectedCallbacks(m, id, field, path, selection, remaining, depth + 1);
            path.shrinkRetainingCapacity(before);
        }
    }
    fn selectedArguments(self: *Generator, m: *const core.Module, id: core.Id, captures: []const Value, arguments: []const Value, selection: *std.ArrayList(u32)) Error!void {
        var path: std.ArrayList(u32) = .empty;
        defer path.deinit(self.allocator);
        var remaining: usize = 4096;
        for ([_][]const Value{ captures, arguments }, 0..) |values, group| for (values, 0..) |value, index| {
            path.clearRetainingCapacity();
            try path.appendSlice(self.allocator, &.{ @intCast(group), @intCast(index) });
            try self.selectedCallbacks(m, id, value, &path, selection, &remaining, 0);
        };
    }
    fn selectedType(self: *Generator, m: *const core.Module, id: core.Id, input: TypeRef, selection: *std.ArrayList(u32), keys: *selected_types.Builder, depth: usize) Error!void {
        const result = self.selectedTypeNode(m, id, input, keys, depth) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.Declined => error.Declined,
            error.Cycle => self.fail(m, id, .storage_unsupported, "Cyclic selected call types cannot form a structural key"),
            error.Limit => self.fail(m, id, .storage_unsupported, "The selected call type exceeds the supported bound"),
        };
        keys.root(selection, result) catch |err| return self.selectedKeyError(m, id, err);
    }
    fn selectedKeyError(self: *Generator, m: *const core.Module, id: core.Id, err: selected_types.Error) Error {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.Cycle => self.fail(m, id, .storage_unsupported, "Cyclic selected call types cannot form a structural key"),
            error.Limit => self.fail(m, id, .storage_unsupported, "The selected call key exceeds its encoded-word or construction-work bound"),
        };
    }
    fn finishSelectedTypes(self: *Generator, m: *const core.Module, id: core.Id, selection: *std.ArrayList(u32), keys: *selected_types.Builder) Error!void {
        keys.finish(selection) catch |err| return self.selectedKeyError(m, id, err);
    }
    fn selectedTypeChild(self: *Generator, m: *const core.Module, id: core.Id, input: TypeRef, descriptor: *std.ArrayList(u32), keys: *selected_types.Builder, depth: usize, height: *usize) (Error || selected_types.Error)!void {
        const child = try self.selectedTypeNode(m, id, input, keys, depth + 1);
        try keys.addWord(descriptor, child.id);
        height.* = @max(height.*, child.height + 1);
    }
    fn selectedTypeNode(self: *Generator, m: *const core.Module, id: core.Id, input: TypeRef, keys: *selected_types.Builder, depth: usize) (Error || selected_types.Error)!selected_types.Result {
        if (keys.remaining.* == 0 or depth > 128) return error.Limit;
        const actual = try self.resolveType(input, 0);
        const reference: selected_types.Reference = .{
            .unit = actual.unit,
            .ty = actual.ty,
            .environment = if (actual.environment) |environment| @intFromPtr(environment.ptr) else 0,
            .environment_len = if (actual.environment) |environment| environment.len else 0,
            .captured = actual.environment != null,
        };
        if (try keys.enter(reference, depth)) |completed| return completed;
        const owner = try self.unit(actual.unit);
        const node = owner.types.node(actual.ty);
        var descriptor: std.ArrayList(u32) = .empty;
        defer descriptor.deinit(self.allocator);
        var height: usize = 0;
        try keys.addWord(&descriptor, @backingInt(node.tag));
        switch (node.tag) {
            .array, .list, .cursor, .demand, .resolver, .provider => try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, &descriptor, keys, depth, &height),
            .usage => {
                try keys.addWord(&descriptor, node.b);
                try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, &descriptor, keys, depth, &height);
                try keys.addWord(&descriptor, @intFromBool(node.c != 0));
                if (node.c != 0) try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = node.c, .environment = actual.environment }, &descriptor, keys, depth, &height);
            },
            .function => {
                try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, &descriptor, keys, depth, &height);
                try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = node.b, .environment = actual.environment }, &descriptor, keys, depth, &height);
                // Retain the existing exact checked row-carrier identity.
                try keys.addWords(&descriptor, &.{ if (node.c == 0) 0 else actual.unit, node.c });
            },
            .product, .nominal => {
                if (node.tag == .nominal) try keys.addWords(&descriptor, &.{ node.a, node.b });
                const children = if (node.tag == .product) owner.types.list(.{ .start = node.a, .len = node.b }) else owner.types.nominalArguments(node);
                try keys.addWord(&descriptor, @intCast(children.len));
                for (children) |child| try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = child, .environment = actual.environment }, &descriptor, keys, depth, &height);
            },
            .record => {
                try keys.addWord(&descriptor, node.b);
                for (0..node.b) |index| {
                    const field = owner.types.recordField(node, index);
                    if (owner.fieldSpelling(field.name)) |name| {
                        try keys.addWord(&descriptor, @intCast(name.len));
                        for (name) |byte| try keys.addWord(&descriptor, byte);
                    } else try keys.addWords(&descriptor, &.{ std.math.maxInt(u32), actual.unit, field.name });
                    try self.selectedTypeChild(m, id, .{ .unit = actual.unit, .ty = field.ty, .environment = actual.environment }, &descriptor, keys, depth, &height);
                }
            },
            .unit, .boolean, .u32, .f32, .never => {},
            // Abstract roles keep their source identity and correlation.
            else => try keys.addWords(&descriptor, &.{ actual.unit, actual.ty }),
        }
        return keys.complete(reference, descriptor.items, height);
    }
    fn invoke(self: *Generator, target: core.BindingRef, arguments: []const Value, depth: usize) Error!Value {
        const m = try self.unit(target.unit);
        const body = m.body(target.binding) orelse return error.Declined;
        const parameters = m.bodyParameters(body);
        const selected_target: call_plan.ActiveCalls.Target = .{ .unit = m.unit, .id = target.binding, .kind = .named };
        var selected: std.ArrayList(u32) = .empty;
        defer selected.deinit(self.allocator);
        var origin: ?@import("../check/scheme_equations.zig").SourceFailure = null;
        source_proof.checkedInterfaceBodyCached(self.proof_cache, m, target.binding, self.validation_budget, &origin, null) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            if (self.proof_cache.exhaustedUnit()) |exhausted| {
                self.diagnostic = .{ .unit = exhausted, .span = if (origin) |failure| failure.span else .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Source module storage validation exceeded its checked work budget" };
                return error.Declined;
            }
            if (self.validation_budget.* == 0) return self.fail(m, body.root, .storage_unsupported, "Source storage validation exceeded its checked work budget");
            if (origin) |failure| {
                self.diagnostic = .{ .unit = failure.unit, .span = failure.span, .code = .storage_unsupported, .detail = "The scoped body lacks complete type evidence" };
                return error.Declined;
            }
            return self.fail(m, body.root, .storage_unsupported, "The scoped body lacks complete type evidence");
        };
        if (arguments.len < parameters.len) {
            if (depth > 128) return self.unsupported(m, body.root);
            const fields = try self.arena.allocator().alloc(Value, arguments.len);
            for (fields, arguments) |*field, argument| field.* = try self.snapshot(argument);
            return .{ .tag = .callable, .word = (try self.constant(0)).word, .callable = .{ .unit = m.unit, .target = target.binding, .types = try self.captureTypes() }, .fields = fields };
        }
        if (arguments.len > parameters.len) {
            if (depth > 128) return self.unsupported(m, body.root);
            var function = try self.invoke(target, arguments[0..parameters.len], depth + 1);
            for (arguments[parameters.len..]) |argument| function = try self.applyUse(m, body.root, function, argument, depth + 1, false);
            return function;
        }
        for (parameters, arguments) |parameter, value| {
            const formal: TypeRef = .{ .unit = m.unit, .ty = parameter.ty };
            if (try self.callableType(value)) |signature| {
                try self.mapTypesUnder(formal, signature, value.callable.?.types, 0);
            } else try self.mapValueTypes(formal, value, 0);
        }
        const previous_goals = self.active_goals;
        self.active_goals = m.obligations[body.scheme.obligations.start..][0..body.scheme.obligations.len];
        defer self.active_goals = previous_goals;
        try self.refineFields(m, self.active_goals);
        try self.selectedArguments(m, body.root, &.{}, arguments, &selected);
        const public = m.types.list(m.binding(target.binding).public_variables);
        try selected.appendSlice(self.allocator, &.{ std.math.maxInt(u32), @intCast(public.len) });
        var type_work: usize = 4096;
        var type_key = selected_types.Builder.init(self.allocator, &type_work, .{});
        defer type_key.deinit();
        for (public) |parameter| try self.selectedType(m, body.root, .{ .unit = m.unit, .ty = parameter }, &selected, &type_key, 0);
        try self.finishSelectedTypes(m, body.root, &selected, &type_key);
        if (self.active_calls.contains(selected_target, selected.items)) return self.fail(m, body.root, .storage_unsupported, "Recursive selected calls are not supported by the owned-storage backend");
        if (self.active_calls.frames.items.len >= 128) return self.fail(m, body.root, .storage_unsupported, "Selected calls exceeded their active call bound");
        if (self.specialize) if (try self.reusableCall(m, target, arguments)) |value| return value;
        if (self.specialize) if (try self.reusableInlineCall(m, target, arguments)) |value| return value;
        if (self.specialize) if (try self.reusableReaderCall(m, target, arguments)) |value| return value;
        if (self.specialize) if (try self.reusableUnitWriter(m, target, arguments)) |value| return value;
        // A reusable definition's child enters while compiling its body. Do
        // not enter twice merely because planning moved to another Generator.
        if (!try self.active_calls.enter(selected_target, selected.items)) return self.fail(m, body.root, .storage_unsupported, "Recursive selected calls are not supported by the owned-storage backend");
        defer self.active_calls.leave();
        const first_root = self.roots.items.len;
        const mark = try self.frameMark();
        const uses = @import("storage_liveness.zig").count(self.allocator, m, body.root) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.unsupported(m, body.root);
        };
        defer self.allocator.free(uses);
        const previous_uses = self.uses;
        self.uses = uses;
        defer self.uses = previous_uses;
        const before = self.bindings.items.len;
        defer self.bindings.shrinkRetainingCapacity(before);
        self.depth += 1;
        defer self.depth -= 1;
        for (parameters, arguments) |parameter, value| try self.bind(m, parameter.binding, value);
        var result = try self.expression(m, body.root, 0);
        try self.escape(m, body.root, &result, self.depth);
        try self.release(first_root, result);
        try self.rewindUnescaped(first_root, mark, result);
        return result;
    }
    fn reusableClosure(self: *Generator, m: *const core.Module, id: core.Id, function: Value, argument: Value) Error!?Value {
        if (function.demand != null or argument.tag != .scalar or argument.demand != null) return null;
        var descriptor = false;
        var words: usize = 1;
        for (function.fields) |capture| {
            if (capture.demand != null or capture.host != null) return null;
            switch (capture.tag) {
                .scalar => {},
                .array, .ref, .link, .view => {
                    const capture_root = capture.root orelse return null;
                    if (!plainShape(self.roots.items[capture_root].element)) return null;
                    for (capture.other_roots) |other| if (!plainShape(self.roots.items[other].element)) return null;
                    descriptor = true;
                },
                else => return null,
            }
            words = std.math.add(usize, words, readerWords(capture)) catch return null;
        }
        if (words > std.math.maxInt(u32)) return null;
        const callable = function.callable.?;
        const owner = try self.unit(callable.unit);
        const closure = owner.closure(callable.node);
        var remaining: usize = 100_000;
        if (descriptor) {
            if (!call_plan.readerBody(owner, closure.body, &remaining, 0)) return null;
        } else if (!call_plan.scalarBody(owner, closure.body, &remaining, 0)) return null;
        const result_type = owner.typeOf(closure.body);
        if (result_type != T.unit and result_type != T.boolean and result_type != T.u32_type and result_type != T.f32_type) return null;
        var evidence: std.ArrayList(u32) = .empty;
        defer evidence.deinit(self.allocator);
        try evidence.appendSlice(self.allocator, &.{ callable.node, result_type, @intFromBool(argument.floating) });
        var type_work: usize = 4096;
        var type_key = selected_types.Builder.init(self.allocator, &type_work, .{});
        defer type_key.deinit();
        for (callable.captures, function.fields) |binding, capture| {
            try evidence.appendSlice(self.allocator, &.{ @backingInt(capture.tag), @backingInt(capture.mode), @intFromBool(capture.sequence), @intFromBool(capture.floating) });
            try self.selectedType(m, id, .{ .unit = owner.unit, .ty = owner.binding(binding).ty }, &evidence, &type_key, 0);
            if (capture.tag != .scalar) try self.registerShapeRead(capture);
        }
        try self.selectedType(m, id, .{ .unit = owner.unit, .ty = closure.parameter.ty }, &evidence, &type_key, 0);
        try self.selectedType(m, id, .{ .unit = owner.unit, .ty = result_type }, &evidence, &type_key, 0);
        try self.finishSelectedTypes(m, id, &evidence, &type_key);
        const key: call_plan.Key = .{ .unit = owner.unit, .binding = 0, .evidence = evidence.items };
        const index = if (self.calls.find(key)) |found| found else blk: {
            const signature = try self.allocator.alloc(wasm.ValueType, words);
            defer self.allocator.free(signature);
            @memset(signature, .i32);
            const target = self.module.addTypedFunction(signature, .i32, .scalar) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.unsupported(m, id),
            };
            const inserted = try self.calls.insert(key, target, result_type == T.f32_type);
            var child: Generator = .{
                .allocator = self.allocator,
                .arena = std.heap.ArenaAllocator.init(self.allocator),
                .calls = .{ .allocator = self.allocator },
                .active_calls = self.active_calls,
                .specialize = false,
                .units = self.units,
                .unit_views = self.unit_views,
                .proof_cache = self.proof_cache,
                .dispatches = self.dispatches,
                .capacity_requests = self.capacity_requests,
                .validation_budget = self.validation_budget,
                .module = self.module,
                .runtime = self.runtime,
                .fixed_region = self.fixed_region,
                .c = .{ .module = self.module, .function = target },
            };
            defer child.deinit();
            try child.type_arguments.appendSlice(self.allocator, self.type_arguments.items);
            var input = function;
            input.fields = try child.arena.allocator().alloc(Value, function.fields.len);
            var next: u32 = 0;
            for (input.fields, function.fields) |*capture, original| try self.readerParameter(&child, capture, original, &next);
            const output = child.apply(m, id, input, .{ .word = .{ .id = next }, .floating = argument.floating }, 0) catch |err| {
                if (child.diagnostic) |diagnostic| self.diagnostic = diagnostic;
                return err;
            };
            try child.c.value(try child.scalar(m, id, output));
            self.calls.entries.items[inserted].building = false;
            break :blk inserted;
        };
        const entry = self.calls.entries.items[index];
        if (entry.building) return self.fail(m, id, .storage_unsupported, "Recursive callback specialization is not admitted");
        for (function.fields) |capture| {
            try self.c.value(capture.word);
            if (capture.tag == .scalar) continue;
            try self.c.value(capture.token);
            try self.c.value(capture.epoch_low);
            try self.c.value(capture.epoch_high);
            if (capture.tag != .array) try self.c.value(capture.index);
            if (capture.tag == .view) try self.c.value(capture.length);
        }
        try self.c.value(argument.word);
        try self.c.op(.call, entry.function);
        const word = try self.c.temp();
        try self.c.op(.local_set, word.id);
        return .{ .word = word, .floating = entry.floating, .type_evidence = .{ .root = .{ .unit = owner.unit, .ty = result_type }, .arguments = &.{} } };
    }
    fn apply(self: *Generator, m: *const core.Module, id: core.Id, function: Value, argument: Value, depth: usize) Error!Value {
        return self.applyUse(m, id, function, argument, depth, true);
    }
    fn applyUse(self: *Generator, m: *const core.Module, id: core.Id, function: Value, argument: Value, depth: usize, checked_use: bool) Error!Value {
        if (function.host != null) return self.hostCall(m, id, function, argument);
        const callable = function.callable orelse return self.fail(m, id, .storage_unsupported, "A callback must have a statically known function body");
        const types_before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(types_before);
        // Resolve the caller's current instance before entering the captured
        // environment. Static inference IDs can be shared by distinct active
        // instantiations; a capture must not rewrite the checked use's result.
        const use_input: ?TypeRef = if (checked_use and m.node(id).tag == .apply) try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(m.node(id).b) }, 0) else null;
        const use_output: ?TypeRef = if (checked_use and m.node(id).tag == .apply) try self.resolveType(.{ .unit = m.unit, .ty = m.node(id).ty }, 0) else null;
        try self.restoreTypes(callable.types);
        // A partial application may have been captured before its remaining
        // generic inputs were known. The checked use owns the final instance;
        // refine after restoring the capture's earlier type environment.
        if (checked_use and m.node(id).tag == .apply) {
            const owner = try self.unit(callable.unit);
            var signature = if (callable.node == 0) owner.binding(callable.target).ty else owner.closure(callable.node).function_type;
            var skipped: usize = 0;
            while (skipped < if (callable.node == 0) function.fields.len else 0) : (skipped += 1) {
                const arrow = owner.types.node(signature);
                if (arrow.tag != .function) return self.unsupported(m, id);
                signature = arrow.b;
            }
            const arrow = owner.types.node(signature);
            if (arrow.tag == .function) {
                try self.mapTypes(.{ .unit = owner.unit, .ty = arrow.a }, use_input.?, 0);
                try self.mapTypes(.{ .unit = owner.unit, .ty = arrow.b }, use_output.?, 0);
            }
        }
        if (callable.node == 0) {
            const args = try self.arena.allocator().alloc(Value, function.fields.len + 1);
            @memcpy(args[0..function.fields.len], function.fields);
            args[function.fields.len] = argument;
            return self.invoke(.{ .unit = callable.unit, .binding = callable.target }, args, depth + 1);
        }
        const owner = try self.unit(callable.unit);
        const closure = if (function.demand != null) owner.suspension(callable.node) else owner.closure(callable.node);
        if (try self.callableType(argument)) |signature| {
            try self.mapTypesUnder(.{ .unit = owner.unit, .ty = closure.parameter.ty }, signature, argument.callable.?.types, 0);
        } else try self.mapValueTypes(.{ .unit = owner.unit, .ty = closure.parameter.ty }, argument, 0);
        const previous_goals = self.active_goals;
        self.active_goals = callable.goals;
        defer self.active_goals = previous_goals;
        try self.refineFields(owner, callable.goals);
        if (closure.qualifier != 0) {
            const scheme = owner.binding(closure.qualifier).scheme;
            try self.refineFields(owner, owner.obligations[scheme.obligations.start..][0..scheme.obligations.len]);
        }
        for (callable.captures, function.fields) |binding, capture| {
            const formal: TypeRef = .{ .unit = owner.unit, .ty = owner.binding(binding).ty };
            if (try self.callableType(capture)) |signature| {
                try self.mapTypesUnder(formal, signature, capture.callable.?.types, 0);
            } else try self.mapValueTypes(formal, capture, 0);
        }
        const selected_target: call_plan.ActiveCalls.Target = .{ .unit = callable.unit, .id = callable.node, .kind = .closure };
        var selected: std.ArrayList(u32) = .empty;
        defer selected.deinit(self.allocator);
        try self.selectedArguments(m, id, function.fields, &.{argument}, &selected);
        try selected.appendSlice(self.allocator, &.{ std.math.maxInt(u32), @intCast(callable.captures.len + 2) });
        var type_work: usize = 4096;
        var type_key = selected_types.Builder.init(self.allocator, &type_work, .{});
        defer type_key.deinit();
        for (callable.captures) |binding| try self.selectedType(m, id, .{ .unit = owner.unit, .ty = owner.binding(binding).ty }, &selected, &type_key, 0);
        try self.selectedType(m, id, .{ .unit = owner.unit, .ty = closure.parameter.ty }, &selected, &type_key, 0);
        try self.selectedType(m, id, .{ .unit = owner.unit, .ty = owner.typeOf(closure.body) }, &selected, &type_key, 0);
        try self.finishSelectedTypes(m, id, &selected, &type_key);
        if (self.active_calls.contains(selected_target, selected.items)) return self.fail(m, id, .storage_unsupported, "Recursive selected calls are not supported by the owned-storage backend");
        if (self.active_calls.frames.items.len >= 128) return self.fail(m, id, .storage_unsupported, "Selected calls exceeded their active call bound");
        if (self.specialize and checked_use) if (try self.reusableClosure(m, id, function, argument)) |value| return value;
        if (!try self.active_calls.enter(selected_target, selected.items)) return self.fail(m, id, .storage_unsupported, "Recursive selected calls are not supported by the owned-storage backend");
        defer self.active_calls.leave();
        const uses = @import("storage_liveness.zig").count(self.allocator, owner, closure.body) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.unsupported(m, id);
        };
        defer self.allocator.free(uses);
        const previous_uses = self.uses;
        self.uses = uses;
        defer self.uses = previous_uses;
        const bindings_before = self.bindings.items.len;
        defer self.bindings.shrinkRetainingCapacity(bindings_before);
        const roots_before = self.roots.items.len;
        const mark = try self.frameMark();
        self.depth += 1;
        defer self.depth -= 1;
        for (callable.captures, function.fields) |binding, value| try self.bindings.append(self.allocator, .{ .unit = owner.unit, .id = binding, .value = value, .remaining = uses[binding] });
        try self.bind(owner, closure.parameter.binding, argument);
        var result = try self.expression(owner, closure.body, 0);
        try self.escape(owner, closure.body, &result, self.depth);
        try self.release(roots_before, result);
        try self.rewindUnescaped(roots_before, mark, result);
        return result;
    }
    fn pattern(self: *Generator, m: *const core.Module, id: core.PatternId, value: Value) Error!void {
        const p = m.pattern(id);
        switch (p.tag) {
            .bind => try self.bind(m, p.a, value),
            .wildcard => {},
            .product => {
                const children = m.patternChildren(id);
                if (value.tag != .aggregate or children.len != value.fields.len) return error.Declined;
                const ty = m.types.node(p.ty);
                for (children, 0..) |child, index| {
                    const field = if (ty.tag == .record) try self.namedField(m, 0, value, m.types.recordField(ty, index).name) else value.fields[index];
                    try self.pattern(m, child, field);
                }
            },
            .constructor => {
                const constructor = m.constructor(p.a);
                const nominal = m.nominal(constructor.nominal);
                if (value.nominal == null or !std.meta.eql(nominal.identity, value.nominal.?)) return error.Declined;
                const selected = if (value.variant_tags.len == 0) @as(usize, 0) else @import("storage_layout.zig").variantIndex(value.variant_tags, constructor.tag) orelse return error.Declined;
                if (value.variant_tags.len != 0) try self.c.trap(.{ .i32_ne, value.word, constructor.tag });
                if (p.b != 0) try self.pattern(m, p.b, value.fields[selected]);
            },
            .record_payload => {
                if (p.a == 1) {
                    if (value.fields.len != 1) return error.Declined;
                    try self.pattern(m, p.b, value.fields[0]);
                } else if (m.pattern(p.b).tag == .product) {
                    const children = m.patternChildren(p.b);
                    const ty = m.types.node(p.ty);
                    if (ty.tag != .record or children.len != value.fields.len) return error.Declined;
                    for (children, 0..) |child, index| try self.pattern(m, child, try self.namedField(m, 0, value, m.types.recordField(ty, index).name));
                } else return error.Declined;
            },
            else => return error.Declined,
        }
    }
    fn testPattern(self: *Generator, m: *const core.Module, id: core.PatternId, value: Value, depth: usize) Error!Local {
        if (depth > 128) return self.unsupported(m, 0);
        const p = m.pattern(id);
        switch (p.tag) {
            .bind => {
                try self.bind(m, p.a, value);
                return (try self.constant(1)).word;
            },
            .wildcard => return (try self.constant(1)).word,
            .constant, .value => {
                const expected = if (p.tag == .constant) try self.constant(p.a) else try self.expression(m, p.a, depth + 1);
                const actual = try self.scalar(m, 0, value);
                return @import("storage_patterns.zig").equal(self.c, actual, try self.scalar(m, 0, expected), value.floating);
            },
            .constructor => {
                const constructor = m.constructor(p.a);
                const nominal = m.nominal(constructor.nominal);
                if (value.nominal == null or !std.meta.eql(value.nominal.?, nominal.identity)) return self.unsupported(m, 0);
                const selected = if (value.variant_tags.len == 0) @as(usize, 0) else @import("storage_layout.zig").variantIndex(value.variant_tags, constructor.tag) orelse return self.unsupported(m, 0);
                const result = try self.c.temp();
                if (value.variant_tags.len == 0) try self.c.set(result, 1) else try self.c.set(result, .{ .i32_eq, value.word, constructor.tag });
                if (p.b != 0) {
                    try self.c.when(result);
                    self.nesting += 1;
                    try self.c.set(result, try self.testPattern(m, p.b, value.fields[selected], depth + 1));
                    self.nesting -= 1;
                    try self.c.end();
                }
                return result;
            },
            .product => {
                const children = m.patternChildren(id);
                if (value.tag != .aggregate or children.len != value.fields.len or value.variant_tags.len != 0) return self.unsupported(m, 0);
                const result = (try self.constant(1)).word;
                const ty = m.types.node(p.ty);
                for (children, 0..) |child, index| {
                    const field = if (ty.tag == .record) try self.namedField(m, 0, value, m.types.recordField(ty, index).name) else value.fields[index];
                    try self.c.when(result);
                    self.nesting += 1;
                    try self.c.set(result, try self.testPattern(m, child, field, depth + 1));
                    self.nesting -= 1;
                    try self.c.end();
                }
                return result;
            },
            .record_payload => {
                if (p.a == 1) {
                    if (value.fields.len != 1) return self.unsupported(m, 0);
                    return self.testPattern(m, p.b, value.fields[0], depth + 1);
                }
                return self.testPattern(m, p.b, value, depth + 1);
            },
            else => return self.unsupported(m, 0),
        }
    }
    fn evaluatedPattern(m: *const core.Module, id: core.PatternId, depth: usize) bool {
        if (depth > 128) return true;
        const p = m.pattern(id);
        return switch (p.tag) {
            .value => true,
            .constructor, .record_payload => p.b != 0 and evaluatedPattern(m, p.b, depth + 1),
            .product => blk: {
                for (m.patternChildren(id)) |child| if (evaluatedPattern(m, child, depth + 1)) break :blk true;
                break :blk false;
            },
            else => false,
        };
    }
    fn impossiblePattern(m: *const core.Module, id: core.PatternId, value: Value, depth: usize) bool {
        if (depth > 128) return false;
        const p = m.pattern(id);
        switch (p.tag) {
            .constructor => {
                const constructor = m.constructor(p.a);
                if (value.nominal == null or !std.meta.eql(value.nominal.?, m.nominal(constructor.nominal).identity)) return false;
                const selected = if (value.variant_tags.len == 0) @as(usize, 0) else @import("storage_layout.zig").variantIndex(value.variant_tags, constructor.tag) orelse return false;
                if (!possibleVariant(value, selected)) return true;
                return p.b != 0 and selected < value.fields.len and impossiblePattern(m, p.b, value.fields[selected], depth + 1);
            },
            .product => {
                const children = m.patternChildren(id);
                if (value.tag != .aggregate or children.len != value.fields.len or value.variant_tags.len != 0) return false;
                const ty = m.types.node(p.ty);
                for (children, 0..) |child, index| {
                    const field = if (ty.tag == .record) dataField(value, m.fieldSpelling(m.types.recordField(ty, index).name) orelse return false) orelse return false else value.fields[index];
                    if (impossiblePattern(m, child, field, depth + 1)) return true;
                }
            },
            .record_payload => {
                if (p.a == 1) return value.fields.len == 1 and impossiblePattern(m, p.b, value.fields[0], depth + 1);
                return impossiblePattern(m, p.b, value, depth + 1);
            },
            else => {},
        }
        return false;
    }
    fn continuationBindings(self: *Generator, m: *const core.Module, id: core.Id, output: *std.ArrayList(Binding), bindings: []const Binding) Error!void {
        for (bindings) |binding| {
            var existing: ?*Binding = null;
            for (output.items) |*item| if (item.unit == binding.unit and item.id == binding.id) {
                existing = item;
                break;
            };
            if (existing) |item| {
                try self.assign(m, id, &item.value, binding.value);
                item.remaining = @max(item.remaining, binding.remaining);
            } else {
                var item = binding;
                item.value = try self.temporary(binding.value);
                try self.assign(m, id, &item.value, binding.value);
                try output.append(self.allocator, item);
            }
        }
    }
    fn emitMatch(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        const inputs = m.matchInputs(id);
        const values = try self.arena.allocator().alloc(Value, inputs.len);
        const protected_before = self.protected.items.len;
        defer self.protected.shrinkRetainingCapacity(protected_before);
        for (inputs, values) |input, *value| {
            value.* = try self.snapshot(try self.expression(m, input, depth + 1));
            try self.protected.append(self.allocator, value.*);
        }
        const done = (try self.constant(0)).word;
        var result: ?Value = null;
        const merges = m.branchMerges(id);
        const merged = try self.arena.allocator().alloc(?Value, merges.len);
        @memset(merged, null);
        if (merges.len != 0 and m.matchArms(id).len != 2) return self.unsupported(m, id);
        var continuing: usize = 0;
        var survivor: []const Binding = &.{};
        for (m.matchArms(id), 0..) |arm, arm_index| {
            var arm_bindings: std.ArrayList(Binding) = .empty;
            defer arm_bindings.deinit(self.allocator);
            var arm_continues = false;
            const selected = (try self.constant(0)).word;
            rows: for (m.armRows(arm)) |row| {
                const bindings_before = self.bindings.items.len;
                const patterns = m.rowPatterns(row);
                if (patterns.len != values.len) return self.unsupported(m, id);
                // Source admission still checks every arm. Emission may omit
                // an uninhabited payload, but never skip value-pattern work.
                const evaluated = for (patterns) |pattern_id| {
                    if (evaluatedPattern(m, pattern_id, 0)) break true;
                } else false;
                if (!evaluated) for (patterns, values) |pattern_id, value| {
                    if (impossiblePattern(m, pattern_id, value, 0)) continue :rows;
                };
                try self.c.when(.{ .i32_eqz, .{ .i32_or, done, selected } });
                self.nesting += 1;
                const matches = (try self.constant(1)).word;
                for (patterns, values) |pattern_id, value| {
                    try self.c.when(matches);
                    self.nesting += 1;
                    try self.c.set(matches, try self.testPattern(m, pattern_id, value, depth + 1));
                    self.nesting -= 1;
                    try self.c.end();
                }
                try self.c.when(matches);
                self.nesting += 1;
                try self.c.set(selected, 1);
                const guard = if (arm.guard != 0) try self.scalar(m, id, try self.expression(m, arm.guard, depth + 1)) else (try self.constant(1)).word;
                try self.c.when(guard);
                self.nesting += 1;
                try self.c.set(done, 1);
                const body = if (arm.body != 0) try self.expression(m, arm.body, depth + 1) else try self.constant(0);
                if (!body.terminated) {
                    arm_continues = true;
                    if (result == null) result = try self.temporary(body);
                    try self.assign(m, id, &result.?, body);
                    for (merges, merged) |merge, *value| {
                        const incoming = try self.bindingValue(m, if (arm_index == 0) merge.then_binding else merge.else_binding);
                        if (value.* == null) value.* = try self.temporary(incoming);
                        try self.assign(m, id, &value.*.?, incoming);
                    }
                    if (m.matchInfo(id).statement) try self.continuationBindings(m, id, &arm_bindings, self.bindings.items[bindings_before..]);
                }
                self.nesting -= 3;
                try self.c.end();
                try self.c.end();
                try self.c.end();
                self.bindings.shrinkRetainingCapacity(bindings_before);
            }
            if (arm_continues) {
                continuing += 1;
                survivor = try self.arena.allocator().dupe(Binding, arm_bindings.items);
            }
        }
        try self.c.trap(.{ .i32_eqz, done });
        if (m.matchInfo(id).statement and continuing == 1) try self.bindings.appendSlice(self.allocator, survivor);
        for (merges, merged) |merge, value| if (value) |joined| try self.bind(m, merge.result, joined);
        return result orelse try self.terminated();
    }
    fn namedField(self: *Generator, m: *const core.Module, id: core.Id, value: Value, name: u32) Error!Value {
        const spelling = m.fieldSpelling(name) orelse return self.unsupported(m, id);
        for (value.fields) |field| if (std.mem.eql(u8, field.name, spelling)) return field;
        return self.unsupported(m, id);
    }
    fn dataField(value: Value, name: []const u8) ?Value {
        if (value.tag != .aggregate) return null;
        for (value.fields) |field| if (std.mem.eql(u8, field.name, name)) return field;
        if (value.nominal != null and value.variant_tags.len == 0 and value.fields.len == 1) return dataField(value.fields[0], name);
        return null;
    }
    /// A record view selects existing field descriptors. Copying Value keeps
    /// callable captures and every owner/borrow root; no payload is copied.
    fn mergeRecordValues(self: *Generator, left: Value, right: Value) Error!?Value {
        if (left.tag != .aggregate or right.tag != .aggregate or left.nominal != null or right.nominal != null or
            left.variant_tags.len != 0 or right.variant_tags.len != 0 or left.sequence or right.sequence) return null;
        for (left.fields) |field| if (field.name.len == 0) return null;
        for (right.fields) |field| if (field.name.len == 0) return null;
        var count = left.fields.len;
        for (right.fields) |field| if (dataField(left, field.name) == null) {
            count += 1;
        };
        const fields = try self.arena.allocator().alloc(Value, count);
        for (left.fields, fields[0..left.fields.len]) |field, *selected| selected.* = dataField(right, field.name) orelse field;
        var next = left.fields.len;
        for (right.fields) |field| if (dataField(left, field.name) == null) {
            fields[next] = field;
            next += 1;
        };
        orderFields(fields);
        return .{ .tag = .aggregate, .word = left.word, .fields = fields };
    }
    /// Substitute only checked source types. Physical words and field counts
    /// cannot establish the receiver of an associated operation.
    fn dispatchEvidence(self: *Generator, evidence: *type_evidence.Store, input: TypeRef, depth: usize) Error!type_evidence.Id {
        if (depth > 128 or self.validation_budget.* == 0) {
            return error.Declined;
        }
        self.validation_budget.* -= 1;
        const actual = try self.resolveType(input, 0);
        const owner = try self.unit(actual.unit);
        const node = owner.types.node(actual.ty);
        var children: std.ArrayList(T.Id) = .empty;
        defer children.deinit(self.allocator);
        switch (node.tag) {
            .variable, .bound => {
                return error.Declined;
            },
            .array, .list, .cursor, .demand, .resolver => try children.append(self.allocator, node.a),
            .function => try children.appendSlice(self.allocator, &.{ node.a, node.b }),
            .product => try children.appendSlice(self.allocator, owner.types.list(.{ .start = node.a, .len = node.b })),
            .nominal => try children.appendSlice(self.allocator, owner.types.nominalArguments(node)),
            .record => for (0..node.b) |index| try children.append(self.allocator, owner.types.recordField(node, index).ty),
            .usage => {
                try children.append(self.allocator, node.a);
                if (node.c != 0) try children.append(self.allocator, node.c);
            },
            else => {},
        }
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        defer mappings.deinit(self.allocator);
        for (children.items) |child| try mappings.append(self.allocator, .{
            .variable = child,
            .evidence = try self.dispatchEvidence(evidence, .{ .unit = actual.unit, .ty = child, .environment = actual.environment }, depth + 1),
        });
        return evidence.projectWithBudget(&owner.types, actual.ty, mappings.items, &.{}, self.validation_budget) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.Declined;
        };
    }
    // A selected associated declaration can return a function (for example
    // lerp after its two operands). Its exact result supplies the latent row
    // instantiation, while resolved child types and concrete effects must
    // still match. Never default an open row to empty or infer receiver types
    // from physical values here.
    fn dispatchResultEvidence(self: *Generator, evidence: *type_evidence.Store, input: TypeRef, selected: type_evidence.Id, depth: usize) Error!type_evidence.Id {
        if (depth > 128) return error.Declined;
        const actual = try self.resolveType(input, 0);
        const owner = try self.unit(actual.unit);
        const node = owner.types.node(actual.ty);
        if (node.tag != .function) return self.dispatchEvidence(evidence, actual, depth + 1);
        const candidate = evidence.nodes.items[selected];
        if (candidate.tag != .function) return error.Declined;
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        defer mappings.deinit(self.allocator);
        try mappings.append(self.allocator, .{ .variable = node.a, .evidence = try self.dispatchResultEvidence(evidence, .{ .unit = actual.unit, .ty = node.a, .environment = actual.environment }, candidate.a, depth + 1) });
        try mappings.append(self.allocator, .{ .variable = node.b, .evidence = try self.dispatchResultEvidence(evidence, .{ .unit = actual.unit, .ty = node.b, .environment = actual.environment }, candidate.b, depth + 1) });
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        const matches = evidence.matchWithRowsBudget(&owner.types, actual.ty, selected, &mappings, &rows, self.validation_budget) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.Declined;
        };
        if (!matches) return error.Declined;
        return evidence.projectWithBudget(&owner.types, actual.ty, mappings.items, rows.items, self.validation_budget) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.Declined;
        };
    }
    fn dispatchTarget(self: *Generator, m: *const core.Module, identity: T.NominalIdentity, member: u32, operator: T.Operator) Error!?core.BindingRef {
        const key: DispatchKey = .{ .unit = m.unit, .identity = identity, .member = member, .operator = operator };
        if (self.dispatches.get(key)) |cached| return cached;
        const nominal_owner = if (identity.unit == 0 or types.identity(identity.unit, identity.decl) != null) m else try self.unit(identity.unit);
        for ([_]*const core.Module{ m, nominal_owner }, 0..) |catalog, index| {
            if (index == 1 and catalog == m) continue;
            for (catalog.associated) |method| {
                if (self.validation_budget.* == 0) return error.Declined;
                self.validation_budget.* -= 1;
                if (!std.meta.eql(method.identity, identity) or (if (member != 0) method.member != member else method.operator != operator)) continue;
                var target = method.target;
                if (target.unit == 0) target.unit = catalog.unit;
                const owner = try self.unit(target.unit);
                if (owner != m and owner.binding(target.binding).private) continue;
                try self.dispatches.put(self.allocator, key, target);
                return target;
            }
        }
        try self.dispatches.put(self.allocator, key, null);
        return null;
    }
    fn fieldTarget(self: *Generator, m: *const core.Module, identity: T.NominalIdentity, member: u32) Error!?core.BindingRef {
        const key: DispatchKey = .{ .unit = m.unit, .identity = identity, .member = member, .operator = .none, .field = true };
        if (self.dispatches.get(key)) |cached| return cached;
        const target = @import("../check/resolver_core.zig").method(m, self.unit_views, identity, member, self.validation_budget) catch {
            if (self.validation_budget.* == 0) return error.Declined;
            try self.dispatches.put(self.allocator, key, null);
            return null;
        };
        try self.dispatches.put(self.allocator, key, target);
        return target;
    }
    fn dispatchCandidate(self: *Generator, m: *const core.Module, id: core.Id, target: core.BindingRef, inputs: []const TypeRef, output: TypeRef, arguments: []const Value, depth: usize) Error!?Value {
        const owner = try self.unit(target.unit);
        const body = owner.body(target.binding) orelse return null;
        var evidence = type_evidence.Store.init(self.allocator) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.Declined;
        };
        defer evidence.deinit();
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        defer mappings.deinit(self.allocator);
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        const before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(before);
        var result = body.scheme.root;
        for (inputs) |input| {
            const arrow = owner.types.node(result);
            if (arrow.tag != .function) return null;
            const actual = try self.dispatchEvidence(&evidence, input, 0);
            const matches = evidence.matchWithRowsBudget(&owner.types, arrow.a, actual, &mappings, &rows, self.validation_budget) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return self.unsupported(m, id);
            };
            if (!matches) return null;
            result = arrow.b;
        }
        // Operand compatibility fixes the declaration. An incompatible result
        // must not make selection fall through to the other operand's owner.
        var cursor = body.scheme.root;
        for (inputs) |input| {
            const arrow = owner.types.node(cursor);
            try self.mapTypes(.{ .unit = owner.unit, .ty = arrow.a }, input, 0);
            cursor = arrow.b;
        }
        const selected_result = try self.resolveType(.{ .unit = owner.unit, .ty = result }, 0);
        const resolved_output = try self.resolveType(output, 0);
        const output_owner = try self.unit(resolved_output.unit);
        if (output_owner.types.node(resolved_output.ty).tag == .variable) try self.mapTypes(resolved_output, selected_result, 0);
        const expected = if (output_owner.types.node(resolved_output.ty).tag == .function) function_result: {
            const selected_evidence = try self.dispatchEvidence(&evidence, selected_result, 0);
            break :function_result try self.dispatchResultEvidence(&evidence, output, selected_evidence, 0);
        } else try self.dispatchEvidence(&evidence, output, 0);
        const matches = evidence.matchWithRowsBudget(&owner.types, result, expected, &mappings, &rows, self.validation_budget) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.unsupported(m, id);
        };
        if (!matches) return self.unsupported(m, id);
        try self.mapTypes(.{ .unit = owner.unit, .ty = result }, output, 0);
        return try self.invoke(target, arguments, depth + 1);
    }
    fn operandType(self: *Generator, input: TypeRef, value: Value) Error!TypeRef {
        const resolved = try self.resolveType(input, 0);
        const owner = try self.unit(resolved.unit);
        if (T.receiverIdentity(owner.types.node(resolved.ty)) != null) return resolved;
        if (value.type_evidence) |evidence| {
            try self.restoreTypes(evidence.arguments);
            return self.resolveType(evidence.root, 0);
        }
        return resolved;
    }
    fn vectorLocal(self: *Generator, m: *const core.Module, id: core.Id, value: Value) Error!Local {
        if (value.tag != .aggregate or value.nominal != null or value.fields.len != 4) return self.unsupported(m, id);
        for (value.fields) |field| if (field.tag != .scalar or field.floating != value.fields[0].floating) return self.unsupported(m, id);
        const vector: Local = .{ .id = try self.module.addLocal(self.c.function, .v128) };
        try self.c.value(value.fields[0].word);
        try self.c.op(.i32x4_splat, 0);
        for (value.fields[1..], 1..) |field, lane| {
            try self.c.value(field.word);
            try self.c.op(.i32x4_replace_lane, @intCast(lane));
        }
        try self.c.op(.local_set, vector.id);
        return vector;
    }
    fn vectorPrimitive(self: *Generator, m: *const core.Module, id: core.Id, left: Value, right: Value) Error!Value {
        const n = m.node(id);
        const catalog = @import("simd_intrinsics.zig");
        const pair = catalog.pairs(n.op);
        if (pair and (right.tag != .aggregate or right.fields.len != 2)) return self.unsupported(m, id);
        const operand = if (pair) right.fields[0] else if (n.op == .swizzle) right else left;
        if (operand.tag != .aggregate or operand.fields.len != 4) return self.unsupported(m, id);
        const floating = operand.fields[0].floating;
        const intrinsic = catalog.operation(n.op, if (floating) .f32 else .u32) orelse return self.unsupported(m, id);
        if (catalog.literalLanes(n.op)) {
            var lanes: [4]u32 = undefined;
            if (n.op == .broadcast) {
                const lane = self.knownLiteral(right) orelse return self.fail(m, id, .simd_lane_literal, "SIMD lane selectors must be literal integers");
                @memset(&lanes, lane);
            } else {
                if (left.tag != .aggregate or left.fields.len != 4) return self.unsupported(m, id);
                for (&lanes, left.fields) |*lane, field| lane.* = self.knownLiteral(field) orelse return self.fail(m, id, .simd_lane_literal, "SIMD lane selectors must be literal integers");
            }
            var lane_bits: u32 = 0;
            for (lanes, 0..) |lane, index| {
                if (lane >= catalog.laneLimit(n.op)) return self.fail(m, id, .simd_lane_literal, "SIMD lane selector is outside its source vectors");
                lane_bits |= lane << @intCast(index * 3);
            }
            const first = try self.vectorLocal(m, id, operand);
            const second = if (n.op == .shuffle) try self.vectorLocal(m, id, right.fields[1]) else first;
            try self.c.value(first);
            try self.c.value(second);
            try self.c.op(.i8x16_shuffle, lane_bits);
        } else if (pair) {
            const a = try self.vectorLocal(m, id, left);
            const b = try self.vectorLocal(m, id, right.fields[0]);
            const c = try self.vectorLocal(m, id, right.fields[1]);
            if (n.op == .select) {
                try self.c.value(b);
                try self.c.value(c);
                try self.c.value(a);
                try self.c.op(.v128_bitselect, 0);
            } else {
                try self.c.value(a);
                try self.c.value(b);
                try self.c.value(c);
                try self.c.op(if (n.op == .relaxed_madd) .f32x4_relaxed_madd else .f32x4_relaxed_nmadd, 0);
            }
        } else {
            const a = try self.vectorLocal(m, id, left);
            const b: ?Local = if (n.b == 0) null else if (intrinsic.shape == .shift) try self.scalar(m, id, right) else try self.vectorLocal(m, id, right);
            if ((n.op == .min or n.op == .max) and floating) {
                try self.c.value(b.?);
                try self.c.value(a);
            } else {
                try self.c.value(a);
                if (b) |value| try self.c.value(value);
            }
            const opcode: ?wasm.Op = switch (n.op) {
                .bits, .from_bits => null,
                .bit_not => .v128_not,
                .bit_andnot => .v128_andnot,
                .shift_left => .i32x4_shl,
                .shift_right => .i32x4_shr_u,
                .shift_right_signed => .i32x4_shr_s,
                .any_true => .v128_any_true,
                .all_true => .i32x4_all_true,
                .min => if (floating) .f32x4_pmin else .i32x4_min_u,
                .max => if (floating) .f32x4_pmax else .i32x4_max_u,
                .convert_i32_f32 => .f32x4_convert_i32x4_s,
                .convert_f32_i32 => .i32x4_trunc_sat_f32x4_s,
                .equal => if (floating) .f32x4_eq else .i32x4_eq,
                .not_equal => if (floating) .f32x4_ne else .i32x4_ne,
                .less => if (floating) .f32x4_lt else .i32x4_lt_u,
                .less_equal => if (floating) .f32x4_le else .i32x4_le_u,
                .greater => if (floating) .f32x4_gt else .i32x4_gt_u,
                .greater_equal => if (floating) .f32x4_ge else .i32x4_ge_u,
                else => blk: {
                    const scalar_op = @import("scalar_ops.zig").opcode(n.op, if (floating) .f32 else .u32) orelse return self.unsupported(m, id);
                    break :blk @import("runtime_ir.zig").lift(scalar_op) orelse return self.unsupported(m, id);
                },
            };
            if (opcode) |op| try self.c.op(op, 0);
        }
        if (intrinsic.shape == .reduce) {
            const result = try self.c.temp();
            try self.c.op(.local_set, result.id);
            return .{ .word = result };
        }
        const vector: Local = .{ .id = try self.module.addLocal(self.c.function, .v128) };
        try self.c.op(.local_set, vector.id);
        const result = try self.temporary(try self.shape(m, id, n.ty, 0));
        for (result.fields, 0..) |*field, lane| {
            try self.c.value(vector);
            try self.c.op(.i32x4_extract_lane, @intCast(lane));
            try self.c.op(.local_set, field.word.id);
        }
        return result;
    }
    fn primitive(self: *Generator, m: *const core.Module, id: core.Id, left_value: Value, right_value: Value) Error!Value {
        if (left_value.tag == .aggregate) return self.vectorPrimitive(m, id, left_value, right_value);
        const n = m.node(id);
        const left = try self.scalar(m, n.a, left_value);
        const right = try self.scalar(m, id, right_value);
        const op: wasm.Op = if (left_value.floating) switch (n.op) {
            .add => .f32_add,
            .sub => .f32_sub,
            .mul => .f32_mul,
            .div => .f32_div,
            .equal => .f32_eq,
            .not_equal => .f32_ne,
            .less => .f32_lt,
            .less_equal => .f32_le,
            .greater => .f32_gt,
            .greater_equal => .f32_ge,
            .neg => .f32_neg,
            .abs => .f32_abs,
            .ceil => .f32_ceil,
            .floor => .f32_floor,
            .trunc => .f32_trunc,
            .sqrt => .f32_sqrt,
            .min => .f32_min,
            .max => .f32_max,
            .convert_f32_u32 => .i32_trunc_sat_f32_u,
            .bits => .i32_reinterpret_f32,
            else => return self.unsupported(m, id),
        } else switch (n.op) {
            .add => .i32_add,
            .sub => .i32_sub,
            .mul => .i32_mul,
            .div => .i32_div_u,
            .rem => .i32_rem_u,
            .equal => .i32_eq,
            .not_equal => .i32_ne,
            .less => .i32_lt_u,
            .less_equal => .i32_le_u,
            .greater => .i32_gt_u,
            .greater_equal => .i32_ge_u,
            .bit_and => .i32_and,
            .bit_or => .i32_or,
            .bit_xor => .i32_xor,
            .shift_left => .i32_shl,
            .shift_right => .i32_shr_u,
            .convert_u32_f32 => .f32_convert_i32_u,
            .from_bits => .f32_reinterpret_i32,
            else => return self.unsupported(m, id),
        };
        const word = try self.c.temp();
        try self.c.value(left);
        if (left_value.floating) try self.c.op(.f32_reinterpret_i32, 0);
        if (n.b != 0) {
            try self.c.value(right);
            if (right_value.floating) try self.c.op(.f32_reinterpret_i32, 0);
        }
        try self.c.op(op, 0);
        const floating = n.ty == T.f32_type or (left_value.floating and switch (n.op) {
            .add, .sub, .mul, .div, .neg, .abs, .ceil, .floor, .trunc, .sqrt, .min, .max => true,
            else => false,
        });
        if (floating) try self.c.op(.i32_reinterpret_f32, 0);
        try self.c.op(.local_set, word.id);
        return .{ .word = word, .floating = floating };
    }
    fn associated(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        const node = m.node(id);
        const types_before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(types_before);
        const before = self.protected.items.len;
        defer self.protected.shrinkRetainingCapacity(before);
        const left = try self.expression(m, node.a, depth + 1);
        if (left.terminated) return left;
        try self.protected.append(self.allocator, left);
        const output: TypeRef = .{ .unit = m.unit, .ty = node.ty };
        const input = try self.operandType(.{ .unit = m.unit, .ty = m.typeOf(node.a) }, left);
        if (node.tag == .result_associated) {
            const resolved = try self.resolveType(output, 0);
            const owner = try self.unit(resolved.unit);
            const identity = T.receiverIdentity(owner.types.node(resolved.ty)) orelse return self.unsupported(m, id);
            const target = (try self.dispatchTarget(m, identity, node.b, .none)) orelse return self.unsupported(m, id);
            return (try self.dispatchCandidate(m, id, target, &.{input}, output, &.{left}, depth + 1)) orelse self.unsupported(m, id);
        }
        const right = try self.expression(m, node.b, depth + 1);
        if (right.terminated) return right;
        try self.protected.append(self.allocator, right);
        const inputs = [_]TypeRef{ input, try self.operandType(.{ .unit = m.unit, .ty = m.typeOf(node.b) }, right) };
        const operator: T.Operator = if (@backingInt(node.op) <= @backingInt(core.Op.shift_right)) @fromBackingInt(@intCast(@backingInt(node.op))) else .none;
        for (inputs, 0..) |subject, side| {
            if (side == 1 and node.tag == .scalar) {
                const first = try self.resolveType(inputs[0], 0);
                const second = try self.resolveType(inputs[1], 0);
                const a = (try self.unit(first.unit)).types.node(first.ty);
                const b = (try self.unit(second.unit)).types.node(second.ty);
                if (a.tag == b.tag and (a.tag == .u32 or a.tag == .f32 or (a.tag == .boolean and (node.op == .equal or node.op == .not_equal)))) return self.primitive(m, id, left, right);
            }
            const resolved = try self.resolveType(subject, 0);
            const owner = try self.unit(resolved.unit);
            const identity = T.receiverIdentity(owner.types.node(resolved.ty)) orelse continue;
            const target = (try self.dispatchTarget(m, identity, if (node.tag == .associated) node.c else 0, operator)) orelse continue;
            if (try self.dispatchCandidate(m, id, target, &inputs, output, &.{ left, right }, depth + 1)) |value| return value;
        }
        return self.unsupported(m, id);
    }
    fn getter(self: *Generator, m: *const core.Module, id: core.Id, value: Value, depth: usize) Error!Value {
        const projection = m.projection(m.node(id).b);
        const before = self.type_arguments.items.len;
        defer self.type_arguments.shrinkRetainingCapacity(before);
        var receiver = try self.resolveType(.{ .unit = m.unit, .ty = projection.source_type }, 0);
        var source = try self.unit(receiver.unit);
        if (T.receiverIdentity(source.types.node(receiver.ty)) == null) if (value.type_evidence) |evidence| {
            try self.restoreTypes(evidence.arguments);
            receiver = try self.resolveType(evidence.root, 0);
            source = try self.unit(receiver.unit);
        };
        const identity = T.receiverIdentity(source.types.node(receiver.ty)) orelse value.nominal orelse return self.unsupported(m, id);
        const target = (try self.fieldTarget(m, identity, projection.field)) orelse return self.unsupported(m, id);
        const owner = try self.unit(target.unit);
        const signature = owner.types.node(owner.binding(target.binding).ty);
        if (signature.tag != .function) return self.unsupported(m, id);
        try self.mapTypes(.{ .unit = owner.unit, .ty = signature.a }, receiver, 0);
        try self.mapTypes(.{ .unit = owner.unit, .ty = signature.b }, .{ .unit = m.unit, .ty = projection.result_type }, 0);
        return self.invoke(target, &.{value}, depth + 1);
    }
    fn namedPlace(self: *Generator, m: *const core.Module, id: core.Id, value: *Value, name: u32) Error!*Value {
        const spelling = m.fieldSpelling(name) orelse return self.unsupported(m, id);
        for (value.fields) |*field| if (std.mem.eql(u8, field.name, spelling)) return field;
        return self.unsupported(m, id);
    }
    fn dataPlace(value: *Value, name: []const u8) ?*Value {
        if (value.tag != .aggregate) return null;
        for (value.fields) |*field| if (std.mem.eql(u8, field.name, name)) return field;
        if (value.nominal != null and value.variant_tags.len == 0 and value.fields.len == 1) return dataPlace(&value.fields[0], name);
        return null;
    }
    fn projected(self: *Generator, m: *const core.Module, id: core.Id, value: *Value, projection_id: u32) Error!*Value {
        if (value.tag != .aggregate) return self.unsupported(m, id);
        const projection = m.projection(projection_id);
        const variants = m.projectionVariants(projection_id);
        if (variants.len == 0) if (m.fieldSpelling(projection.field)) |name| {
            if (dataPlace(value, name)) |field| return field;
        };
        if (projection.nominal.decl != 0) {
            if (value.nominal == null or !std.meta.eql(value.nominal.?, projection.nominal) or value.fields.len != 1 or variants.len != 1) return self.unsupported(m, id);
            for (m.constructors) |constructor| {
                if (!std.meta.eql(m.nominal(constructor.nominal).identity, projection.nominal) or constructor.tag != variants[0].tag) continue;
                const record = m.types.node(constructor.payload);
                if (record.tag != .record or variants[0].field >= record.b) return self.unsupported(m, id);
                return self.namedPlace(m, id, &value.fields[0], m.types.recordField(record, variants[0].field).name);
            }
        } else if (m.types.node(projection.source_type).tag == .record) {
            return self.namedPlace(m, id, value, projection.field);
        } else if (variants.len == 1 and variants[0].field < value.fields.len) return &value.fields[variants[0].field];
        return self.unsupported(m, id);
    }
    fn fieldOffset(value: *const Value, target: *const Value) Error!?u32 {
        if (value == target) return 0;
        var offset: u32 = 0;
        for (value.fields) |*field| {
            if (try fieldOffset(field, target)) |nested| return offset + nested;
            offset += try width(field.*);
        }
        return null;
    }
    fn updateValue(self: *Generator, m: *const core.Module, id: core.Id, original: Value, at: usize, depth: usize) Error!Value {
        if (depth > 128) return self.unsupported(m, id);
        const info = m.updateInfo(id);
        const selectors = m.updateSelectors(id);
        const path = m.updatePath(id);
        const protected_before = self.protected.items.len;
        defer self.protected.shrinkRetainingCapacity(protected_before);
        try self.protected.append(self.allocator, original);
        if (at == @max(selectors.len, path.len)) {
            const before = self.bindings.items.len;
            defer self.bindings.shrinkRetainingCapacity(before);
            try self.bind(m, info.self_binding, original);
            return self.expression(m, info.value, depth + 1);
        }
        var value = original;
        if (selectors.len != 0 and selectors[at].kind == .index) {
            const index = try self.scalar(m, id, try self.expression(m, selectors[at].index, depth + 1));
            var selected = try self.readElement(m, id, value, index);
            // Selecting a writable element pins its extent throughout RHS
            // evaluation, including nested calls. Growth keeps it in place.
            var selected_borrow = value;
            selected_borrow.tag = .ref;
            selected_borrow.index = index;
            try self.protected.append(self.allocator, selected_borrow);
            var leaf = &selected;
            var offset: u32 = 0;
            var next = at + 1;
            while (next < @max(selectors.len, path.len)) : (next += 1) {
                if (selectors.len != 0 and selectors[next].kind == .index) return self.unsupported(m, id);
                const projection = if (selectors.len != 0) selectors[next].projection else path[next];
                const field = try self.projected(m, id, leaf, projection);
                offset += (try fieldOffset(leaf, field)) orelse return self.unsupported(m, id);
                leaf = field;
            }
            const replacement = try self.updateValue(m, id, leaf.*, next, depth + 1);
            const name = leaf.name;
            leaf.* = replacement;
            leaf.name = name;
            for (self.roots.items, 0..) |*owner, root_id| if (hasRoot(value, root_id)) try self.storedShape(m, id, &owner.element, selected, owner.depth);
            try self.writerEvent(m, id, value, .write);
            const address = try self.c.temp();
            try self.c.set(address, .{ .call, self.runtime.functions.address, value.token, value.epoch_low, value.epoch_high, value.word, index });
            // Write the selected place only. The RHS may have written other
            // fields through an alias; rebuilding the row would erase them.
            try self.storeValue(address, offset, replacement);
        } else {
            const projection = if (selectors.len != 0) selectors[at].projection else path[at];
            const field = try self.projected(m, id, &value, projection);
            const name = field.name;
            field.* = try self.updateValue(m, id, field.*, at + 1, depth + 1);
            field.name = name;
        }
        return value;
    }
    fn emitLoop(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        const info = m.loopInfo(id);
        const collection_value: ?Value = if (info.kind == .array) try self.expression(m, info.first, depth + 1) else null;
        const first = if (info.kind == .range) try self.scalar(m, id, try self.expression(m, info.first, depth + 1)) else (try self.constant(0)).word;
        const end = if (info.kind == .range) try self.scalar(m, id, try self.expression(m, info.end, depth + 1)) else if (collection_value) |value| try self.length(m, id, value) else first;
        const iterator = try self.c.temp();
        try self.c.set(iterator, first);
        const roots_before = self.roots.items.len;
        const bindings_before = self.bindings.items.len;
        const pinned_before = self.protected.items.len;
        const read_frame = try self.beginReadFrame();
        defer self.read_frames.shrinkRetainingCapacity(read_frame);
        defer self.protected.shrinkRetainingCapacity(pinned_before);
        if (collection_value) |value| {
            var traversal = value;
            traversal.tag = .view;
            try self.protected.append(self.allocator, traversal);
        }
        const uses = @import("storage_liveness.zig").count(self.allocator, m, info.body) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.unsupported(m, id);
        };
        defer self.allocator.free(uses);
        for (self.bindings.items) |binding| if (binding.unit == m.unit and binding.id < uses.len and uses[binding.id] != 0) {
            try self.protected.append(self.allocator, binding.value);
        };
        const carries = m.loopCarries(id);
        const values = try self.arena.allocator().alloc(Value, carries.len);
        for (values, carries) |*value, carry| {
            const incoming = try self.bindingValue(m, carry.incoming);
            if (!@import("storage_control.zig").fixedCarry(incoming)) return self.unsupported(m, id);
            value.* = try self.temporary(incoming);
            try self.assign(m, id, value, incoming);
        }
        try self.c.op(.block, 0);
        try self.c.op(.loop, 0);
        self.nesting += 2;
        const frame_mark = try self.c.temp();
        try self.c.set(frame_mark, .{ .call, self.runtime.functions.mark, self.fixed_region });
        try self.loops.append(self.allocator, .{ .unit = m.unit, .id = id, .nesting = self.nesting, .roots_before = roots_before, .carries = values, .iterator = if (info.kind != .forever) iterator else null, .mark = frame_mark, .depth = self.depth + 1, .read_frame = read_frame });
        defer _ = self.loops.pop();
        if (info.kind != .forever) {
            try self.c.value(.{ .i32_ge_u, iterator, end });
            try self.c.op(.br_if, 1);
        }
        self.depth += 1;
        for (carries, values) |carry, value| try self.bind(m, carry.iteration, value);
        if (info.pattern != 0) {
            const item = if (collection_value) |value| try self.readElement(m, id, value, try self.elementIndex(m, id, value, iterator)) else Value{ .word = iterator };
            try self.pattern(m, info.pattern, item);
        }
        const body = try self.expression(m, info.body, depth + 1);
        if (!body.terminated) {
            try self.checkReadFrame(m, id, read_frame);
            const next_values = try self.arena.allocator().alloc(Value, carries.len);
            for (carries, next_values) |carry, *next| {
                next.* = try self.snapshot(try self.bindingValue(m, carry.backedge));
                try self.checkEscape(m, id, next.*, self.depth);
            }
            for (values, next_values) |*value, next| {
                if (!@import("storage_control.zig").stableCarry(value.*, next)) return self.fail(m, id, .storage_escape, "A loop must retain the same named owners and borrowed roots across iterations");
                try self.assign(m, id, value, next);
            }
        }
        // A conditional return reserves its result's static slot for the
        // caller, but the path reaching this backedge did not return it.
        // Rewind that iteration too; the next iteration reopens the same slot.
        try self.closeRuntime(roots_before, try self.constant(0));
        try self.release(roots_before, null);
        try self.c.value(.{ .call, self.runtime.functions.rewind, self.fixed_region, frame_mark });
        self.depth -= 1;
        self.bindings.shrinkRetainingCapacity(bindings_before);
        if (info.kind != .forever) try self.c.next(iterator);
        try self.c.op(.br, 0);
        try self.c.end();
        try self.c.end();
        self.nesting -= 2;
        for (carries, values) |carry, value| try self.bind(m, carry.outgoing, value);
        return self.constant(0);
    }
    fn expression(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        var value = try self.expressionInner(m, id, depth);
        if (!value.terminated and value.type_evidence == null) {
            const actual = try self.resolveType(.{ .unit = m.unit, .ty = m.typeOf(id) }, 0);
            // Keep the checked receiver across generic calls, including the
            // cursor descriptor produced by Array.iter. Its physical view
            // layout does not identify the Cursor associated-method family.
            const owner = try self.unit(actual.unit);
            if (T.receiverIdentity(owner.types.node(actual.ty)) != null) value.type_evidence = .{
                .root = actual,
                .arguments = if (actual.ty <= T.f32_type) &.{} else try self.captureTypes(),
            };
        }
        return value;
    }
    fn expressionInner(self: *Generator, m: *const core.Module, id: core.Id, depth: usize) Error!Value {
        errdefer if (self.diagnostic == null) {
            self.diagnostic = .{ .unit = m.unit, .span = m.span(id), .code = .storage_unsupported, .detail = "This expression has no admitted storage layout or binding" };
        };
        self.steps += 1;
        if (depth > 128) return self.fail(m, id, .storage_unsupported, "Storage source expansion exceeded its nesting bound");
        if (self.steps > 100_000) return self.fail(m, id, .storage_unsupported, "Storage source expansion exceeded its expression budget");
        const n = m.node(id);
        switch (n.tag) {
            .task => return self.fail(m, id, .storage_unsupported, "Language tasks are not part of the data-stack model; use isolated host worker jobs and copied packets"),
            .constant => {
                if (n.ty != T.u32_type and n.ty != T.boolean and n.ty != T.unit and n.ty != T.f32_type) return self.unsupported(m, id);
                var value = try self.constant(n.a);
                value.literal = if (n.ty == T.u32_type) n.a else null;
                value.floating = n.ty == T.f32_type;
                return value;
            },
            .reference => {
                var ref = m.reference(id);
                if (ref.unit == 0) ref.unit = m.unit;
                var i = self.bindings.items.len;
                while (i != 0) {
                    i -= 1;
                    const binding = &self.bindings.items[i];
                    if (binding.unit == ref.unit and binding.id == ref.binding) {
                        binding.remaining -|= 1;
                        return binding.value;
                    }
                }
                const owner = try self.unit(ref.unit);
                const binding = owner.binding(ref.binding);
                if (owner.body(ref.binding)) |body| if (body.is_function) return self.instantiate(ref, .{ .unit = m.unit, .ty = n.ty }, &.{}, depth + 1);
                if (binding.kind == .global and @import("storage_collections.zig").element(owner, binding.ty) != null) return self.globalArray(m, id, ref);
                if (binding.kind != .global or owner.body(ref.binding) == null or owner.body(ref.binding).?.runtime or types.info(&owner.types, binding.ty) != null) return self.unsupported(m, id);
                return self.instantiate(ref, .{ .unit = m.unit, .ty = n.ty }, &.{}, depth + 1);
            },
            .bind => {
                const value = try self.expression(m, n.b, depth + 1);
                if (value.terminated) return value;
                try self.bind(m, n.a, value);
                return self.constant(0);
            },
            .pattern_bind => {
                const value = try self.expression(m, n.b, depth + 1);
                if (n.c == 0) try self.pattern(m, n.a, value) else {
                    const matches = try self.testPattern(m, n.a, value, depth + 1);
                    try self.c.when(.{ .i32_eqz, matches });
                    self.nesting += 1;
                    const fallback = try self.expression(m, n.c, depth + 1);
                    if (!fallback.terminated) return self.unsupported(m, id);
                    self.nesting -= 1;
                    try self.c.end();
                }
                return self.constant(0);
            },
            .construct => {
                const constructor = m.constructor(n.a);
                const nominal = m.nominal(constructor.nominal);

                var payload = if (n.b == 0) try self.constant(0) else try self.expression(m, n.b, depth + 1);
                if (payload.terminated) return payload;
                if (n.b != 0) try self.mapValueTypes(.{ .unit = m.unit, .ty = m.typeOf(n.b) }, payload, 0);
                if (n.c != 0) {
                    const record = m.types.node(constructor.payload);
                    if (record.tag != .record or record.b == 0) return self.unsupported(m, id);
                    const fields = try self.arena.allocator().alloc(Value, record.b);
                    if (record.b == 1) fields[0] = payload else {
                        if (payload.tag != .aggregate or payload.fields.len != fields.len) return self.unsupported(m, id);
                        @memcpy(fields, payload.fields);
                    }
                    for (fields, 0..) |*field, index| field.name = m.fieldSpelling(m.types.recordField(record, index).name) orelse return self.unsupported(m, id);
                    orderFields(fields);
                    payload = .{ .tag = .aggregate, .word = (try self.constant(0)).word, .fields = fields };
                }
                if (m.nominalConstructors(constructor.nominal).len == 1) {
                    const fields = try self.arena.allocator().alloc(Value, 1);
                    fields[0] = payload;
                    return .{ .tag = .aggregate, .word = (try self.constant(0)).word, .fields = fields, .nominal = nominal.identity, .type_evidence = .{ .root = .{ .unit = m.unit, .ty = n.ty }, .arguments = try self.captureTypes() } };
                }
                var result = try self.zeroShape(try self.shape(m, id, n.ty, 0));
                const selected = @import("storage_layout.zig").variantIndex(result.variant_tags, constructor.tag) orelse return self.unsupported(m, id);
                result.word = (try self.constant(constructor.tag)).word;
                result.fields[selected] = payload;
                result.variant_index = selected;
                return result;
            },
            .closure, .suspend_ => {
                const captures = if (n.tag == .suspend_) m.suspensionCaptures(id) else m.closureCaptures(id);
                const values = try self.arena.allocator().alloc(Value, captures.len);
                for (captures, values) |capture, *value| value.* = try self.snapshot(try self.bindingValue(m, capture));
                const demand: ?*Demand = if (n.tag == .suspend_) try self.arena.allocator().create(Demand) else null;
                if (demand) |memo| memo.* = .{ .ready = (try self.constant(0)).word };
                return .{ .tag = .callable, .word = (try self.constant(0)).word, .callable = .{ .unit = m.unit, .node = id, .captures = captures, .goals = self.active_goals, .types = try self.captureTypes() }, .fields = values, .demand = demand, .depth = self.depth };
            },
            .force => {
                const pending = try self.expression(m, n.a, depth + 1);
                const memo = pending.demand orelse return self.unsupported(m, id);
                if (memo.building) return self.unsupported(m, id);
                memo.building = true;
                defer memo.building = false;
                try self.c.when(.{ .i32_eqz, memo.ready });
                self.nesting += 1;
                const computed = try self.apply(m, id, pending, try self.constant(0), depth + 1);
                if (computed.tag != .scalar) return self.fail(m, id, .storage_unsupported, "A local memoized demand currently requires a scalar result");
                if (memo.result == null) memo.result = try self.temporary(computed);
                try self.assign(m, id, &memo.result.?, computed);
                try self.c.set(memo.ready, 1);
                self.nesting -= 1;
                try self.c.end();
                return memo.result.?;
            },
            .panic => {
                try self.c.op(.unreachable_, 0);
                return self.terminated();
            },
            .apply => {
                const function = try self.expression(m, n.a, depth + 1);
                const before = self.protected.items.len;
                defer self.protected.shrinkRetainingCapacity(before);
                try self.protected.append(self.allocator, function);
                const argument = try self.expression(m, n.b, depth + 1);
                try self.protected.append(self.allocator, argument);
                return self.apply(m, id, function, argument, depth + 1);
            },
            .product, .record => {
                const children = m.children(id);
                const fields = try self.arena.allocator().alloc(Value, children.len);
                const before = self.protected.items.len;
                defer self.protected.shrinkRetainingCapacity(before);
                for (children, 0..) |child, index| {
                    const value = try self.expression(m, child, depth + 1);
                    const destination = if (n.tag == .record) m.recordDestinations(id)[index] else index;
                    fields[destination] = value;
                    if (n.tag == .record) fields[destination].name = m.fieldSpelling(m.types.recordField(m.types.node(n.ty), destination).name) orelse return self.unsupported(m, id);
                    try self.protected.append(self.allocator, value);
                }
                if (n.tag == .record) orderFields(fields);
                return .{ .tag = .aggregate, .word = (try self.constant(0)).word, .fields = fields };
            },
            .record_merge => {
                const before = self.protected.items.len;
                defer self.protected.shrinkRetainingCapacity(before);
                const left = try self.expression(m, n.a, depth + 1);
                if (left.terminated) return left;
                try self.protected.append(self.allocator, left);
                const right = try self.expression(m, n.b, depth + 1);
                if (right.terminated) return right;
                try self.protected.append(self.allocator, right);
                var merged = (try self.mergeRecordValues(left, right)) orelse return self.unsupported(m, id);
                const output = try self.resolveType(.{ .unit = m.unit, .ty = n.ty }, 0);
                const owner = try self.unit(output.unit);
                const record = owner.types.node(output.ty);
                if (record.tag == .record) {
                    if (record.b != merged.fields.len) return self.unsupported(m, id);
                    const fields = try self.arena.allocator().alloc(Value, record.b);
                    for (fields, 0..) |*field, index| {
                        const name = owner.fieldSpelling(owner.types.recordField(record, index).name) orelse return self.unsupported(m, id);
                        field.* = dataField(merged, name) orelse return self.unsupported(m, id);
                    }
                    merged.fields = fields;
                }
                return merged;
            },
            .project => {
                var value = try self.expression(m, n.a, depth + 1);
                if (m.projection(n.b).variants.len == 0) {
                    if (m.fieldSpelling(m.projection(n.b).field)) |spelling| if (dataField(value, spelling)) |field| return field;
                    return self.getter(m, id, value, depth + 1);
                }
                return (try self.projected(m, id, &value, n.b)).*;
            },
            .update => {
                const info = m.updateInfo(id);
                const root_value = try self.snapshot(try self.expression(m, info.root, depth + 1));
                return self.updateValue(m, id, root_value, 0, depth + 1);
            },
            .loop => return self.emitLoop(m, id, depth),
            .match => return self.emitMatch(m, id, depth),
            .break_ => {
                var index = self.loops.items.len;
                while (index != 0) {
                    index -= 1;
                    const target = self.loops.items[index];
                    if (target.unit != m.unit or target.id != n.a) continue;
                    const args = m.breakValues(id);
                    if (args.len != target.carries.len) return self.unsupported(m, id);
                    const snapshots = try self.arena.allocator().alloc(Value, args.len);
                    for (args, snapshots) |arg, *value| {
                        value.* = try self.snapshot(try self.expression(m, arg, depth + 1));
                        try self.checkEscape(m, id, value.*, target.depth);
                    }
                    for (target.carries, snapshots) |*carry, value| {
                        if (!@import("storage_control.zig").stableCarry(carry.*, value)) return self.fail(m, id, .storage_escape, "A loop exit must retain the same named owners and borrowed roots");
                        try self.assign(m, id, carry, value);
                    }
                    if (n.op == .continue_) try self.checkReadFrame(m, id, target.read_frame);
                    try self.closeRuntime(target.roots_before, try self.constant(0));
                    try self.c.value(.{ .call, self.runtime.functions.rewind, self.fixed_region, target.mark });
                    if (n.op == .continue_) if (target.iterator) |iterator| try self.c.next(iterator);
                    try self.c.op(.br, self.nesting - target.nesting + @as(u32, if (n.op == .continue_) 0 else 1));
                    return self.terminated();
                }
                return self.unsupported(m, id);
            },
            .array => {
                const element = @import("storage_collections.zig").element(m, n.ty) orelse return self.unsupported(m, id);
                _ = element;
                const info = types.info(&m.types, n.ty);
                const mode: storage.Mode = if (self.privateAppendNode(m.unit, id, "initial")) .grow else if (info) |kind| (if (kind.kind == .grow) .grow else .resize) else .fixed;
                const values = m.children(id);
                const capacity = try self.constant(@intCast(values.len));
                const result = try self.array(m, id, capacity.word, mode);
                if (result.root) |owner_id| if (self.roots.items[owner_id].capacity_request) |request| {
                    self.capacity_requests.initial(request, @intCast(values.len), try width(self.roots.items[owner_id].element)) catch return self.fail(m, id, .storage_unsupported, "Array capacity exceeds the Wasm32 storage plan");
                };
                for (values, 0..) |child, index| {
                    const value = try self.expression(m, child, depth + 1);
                    try self.writeElement(m, id, result, (try self.constant(@intCast(index))).word, value);
                }
                return result;
            },
            .staging => {
                const evaluation = @import("../eval/core_eval.zig");
                var session = try evaluation.Session.init(self.allocator, self.units);
                defer session.deinit();
                const values: std.AutoHashMapUnmanaged(core.BindingId, evaluation.ValueId) = .empty;
                const evaluated = session.closedNode(m.unit, id, &values, &.{}, &.{}) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return self.fail(m, id, .stage_unavailable, "");
                };
                const value = session.valueScalar(evaluated) orelse return self.unsupported(m, id);
                if (value.scalar != .u32 and value.scalar != .unit and value.scalar != .bool and value.scalar != .f32) return self.unsupported(m, id);
                var result = try self.constant(value.bits);
                result.literal = if (value.scalar == .u32) value.bits else null;
                result.floating = value.scalar == .f32;
                return result;
            },
            .storage => return self.operation(m, id, depth),
            .array_op => return self.collection(m, id, depth + 1),
            .associated, .result_associated => return self.associated(m, id, depth),
            .scalar => {
                if (n.c != 0 and n.b != 0) return self.associated(m, id, depth);
                const before = self.protected.items.len;
                defer self.protected.shrinkRetainingCapacity(before);
                const left = try self.expression(m, n.a, depth + 1);
                if (left.terminated) return left;
                try self.protected.append(self.allocator, left);
                const right = if (n.b != 0) try self.expression(m, n.b, depth + 1) else left;
                if (right.terminated) return right;
                return self.primitive(m, id, left, right);
            },
            .logical => {
                const left_value = try self.expression(m, n.a, depth + 1);
                if (left_value.terminated) return left_value;
                const left = try self.scalar(m, n.a, left_value);
                const result = try self.c.temp();
                try self.c.set(result, left);
                if (n.op == .and_) try self.c.when(left) else try self.c.when(.{ .i32_eqz, left });
                self.nesting += 1;
                const right = try self.expression(m, n.b, depth + 1);
                if (!right.terminated) try self.c.set(result, try self.scalar(m, n.b, right));
                self.nesting -= 1;
                try self.c.end();
                return .{ .word = result };
            },
            .block => {
                const region_count = self.append_regions.items.len;
                defer self.append_regions.shrinkRetainingCapacity(region_count);
                // This proof changes storage allocation only. The ordinary
                // evaluator retains the original immutable List semantics.
                if (self.destination == null) if (private_append.analyze(m, id)) |plan| {
                    try self.append_regions.append(self.allocator, .{ .unit = m.unit, .plan = plan });
                };
                const roots_before = self.roots.items.len;
                const mark = try self.frameMark();
                const bindings_before = self.bindings.items.len;
                defer self.bindings.shrinkRetainingCapacity(bindings_before);
                self.depth += 1;
                defer self.depth -= 1;
                try self.c.op(.block, 0);
                self.nesting += 1;
                const control_index = self.controls.items.len;
                try self.controls.append(self.allocator, .{ .unit = m.unit, .id = id, .nesting = self.nesting, .roots_before = roots_before });
                defer _ = self.controls.pop();
                var exits = false;
                for (m.children(id)) |child| {
                    const value = try self.expression(m, child, depth + 1);
                    if (value.terminated) {
                        exits = true;
                        break;
                    }
                }
                self.nesting -= 1;
                try self.c.end();
                var result = self.controls.items[control_index].result orelse if (exits) try self.terminated() else try self.constant(0);
                try self.escape(m, id, &result, self.depth);
                try self.release(roots_before, result);
                try self.rewindUnescaped(roots_before, mark, result);
                return result;
            },
            .suite => {
                for (m.children(id)) |child| {
                    const value = try self.expression(m, child, depth + 1);
                    if (value.terminated) return value;
                }
                return self.constant(0);
            },
            .return_ => {
                const value = try self.expression(m, n.a, depth + 1);
                if (value.terminated) return value;
                if (m.typeOf(n.a) == T.never) {
                    try self.c.op(.unreachable_, 0);
                    return self.terminated();
                }
                var i = self.controls.items.len;
                while (i != 0) {
                    i -= 1;
                    if (self.controls.items[i].unit == m.unit and self.controls.items[i].id == n.b) {
                        var target = self.controls.items[i];
                        if (target.result == null) target.result = try self.temporary(value);
                        try self.assign(m, id, &target.result.?, value);
                        self.controls.items[i] = target;
                        try self.closeRuntime(target.roots_before, value);
                        try self.c.op(.br, self.nesting - target.nesting);
                        return self.terminated();
                    }
                }
                return self.unsupported(m, id);
            },
            .if_value, .if_stmt => {
                const condition = try self.scalar(m, n.a, try self.expression(m, n.a, depth + 1));
                const bindings_before = self.bindings.items.len;
                const merges = m.branchMerges(id);
                const merged = try self.arena.allocator().alloc(?Value, merges.len);
                @memset(merged, null);
                var result: ?Value = null;
                try self.c.when(condition);
                self.nesting += 1;
                const left = try self.expression(m, n.b, depth + 1);
                var left_bindings: []const Binding = &.{};
                if (!left.terminated) {
                    result = try self.temporary(left);
                    try self.assign(m, id, &result.?, left);
                    for (merges, merged) |merge, *value| {
                        const incoming = try self.bindingValue(m, merge.then_binding);
                        value.* = try self.temporary(incoming);
                        try self.assign(m, id, &value.*.?, incoming);
                    }
                    if (n.tag == .if_stmt) left_bindings = try self.arena.allocator().dupe(Binding, self.bindings.items[bindings_before..]);
                }
                self.bindings.shrinkRetainingCapacity(bindings_before);
                try self.c.op(.else_, 0);
                const right = if (n.c != 0) try self.expression(m, n.c, depth + 1) else try self.constant(0);
                var right_bindings: []const Binding = &.{};
                if (!right.terminated) {
                    if (result == null) result = try self.temporary(right);
                    try self.assign(m, id, &result.?, right);
                    for (merges, merged) |merge, *value| {
                        const incoming = try self.bindingValue(m, merge.else_binding);
                        if (value.* == null) value.* = try self.temporary(incoming);
                        try self.assign(m, id, &value.*.?, incoming);
                    }
                    if (n.tag == .if_stmt) right_bindings = try self.arena.allocator().dupe(Binding, self.bindings.items[bindings_before..]);
                }
                self.bindings.shrinkRetainingCapacity(bindings_before);
                self.nesting -= 1;
                try self.c.end();
                if (n.tag == .if_stmt and left.terminated != right.terminated) try self.bindings.appendSlice(self.allocator, if (left.terminated) right_bindings else left_bindings);
                for (merges, merged) |merge, value| if (value) |normal| try self.bind(m, merge.result, normal);
                return result orelse try self.terminated();
            },
            .call => {
                const call = m.call(id);
                var values: std.ArrayList(Value) = .empty;
                defer values.deinit(self.allocator);
                const before = self.protected.items.len;
                defer self.protected.shrinkRetainingCapacity(before);
                for (call.arguments) |arg| {
                    const value = try self.expression(m, arg, depth + 1);
                    try values.append(self.allocator, value);
                    try self.protected.append(self.allocator, value);
                }
                var target = call.target;
                if (target.unit == 0) target.unit = m.unit;
                return self.instantiate(target, .{ .unit = m.unit, .ty = call.callee_type }, values.items, depth + 1);
            },
            else => return self.unsupported(m, id),
        }
    }
    fn emit(self: *Generator, entry: u32) Error!void {
        const m = try self.unit(entry);
        const globals = @import("storage_globals.zig").collect(self.allocator, self.units, entry) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.fail(m, 0, .storage_unsupported, switch (err) {
                error.InitializationCycle => "Application pool initialization dependencies are cyclic",
                error.Limit => "Application pool dependency discovery exceeded its checked node budget",
                else => "Application pool dependency could not be resolved",
            });
        };
        defer self.allocator.free(globals);
        if (globals.len > storage.max_stacks) return error.Declined;
        for (globals, 0..) |target, index| try self.globals.append(self.allocator, .{ .target = target, .word = try self.newGlobal(), .token = try self.newGlobal(), .epoch_low = try self.newGlobal(), .epoch_high = try self.newGlobal(), .capacity_request = try self.capacity_requests.add(@intCast(index)) });
        var reserved = globals.len;
        for (m.bodies) |*body| {
            if (!body.exported) continue;
            const parameters = m.bodyParameters(body);
            if (parameters.len != 1) continue;
            const callback = callbackAbi(m, parameters[0].ty);
            const needs_packets = if (callback) |host| arrayAbi(host.parameter) or arrayAbi(host.result) else if (valueAbi(m, parameters[0].ty)) |kind| arrayAbi(kind) else false;
            const result_packets = if (valueAbi(m, m.typeOf(body.root))) |kind| arrayAbi(kind) else false;
            if ((needs_packets or result_packets) and self.transport == null) {
                if (reserved >= storage.max_stacks) return self.unsupported(m, body.root);
                self.transport_region = @intCast(reserved);
                self.transport = packets.emit(self.module) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return self.unsupported(m, body.root);
                };
                reserved += 1;
            }
        }
        self.fixed_region = @intCast(reserved);
        reserved += 1;
        self.max_stacks = @intCast(reserved);
        var exports: usize = 0;
        for (m.bodies) |*body| {
            if (!body.exported) continue;
            const parameters = m.bodyParameters(body);
            if (!body.is_function or parameters.len != 1) return self.unsupported(m, body.root);
            const callback = callbackAbi(m, parameters[0].ty);
            const parameter = if (callback != null) wasm.Scalar.unit else valueAbi(m, parameters[0].ty) orelse return self.unsupported(m, body.root);
            const result = valueAbi(m, m.typeOf(body.root)) orelse return self.unsupported(m, body.root);
            const function = self.module.addTypedFunction(&.{if (callback != null) .externref else if (parameter == .f32) .f32 else .i32}, if (result == .f32) .f32 else .i32, .scalar) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.unsupported(m, body.root),
            };
            self.c = .{ .module = self.module, .function = function };
            // These values belong to one Wasm local namespace and one body
            // planning budget. Completed source proofs, call definitions and
            // physical capacity requests remain compilation-wide.
            self.steps = 0;
            self.layout_steps = 0;
            self.type_arguments.clearRetainingCapacity();
            self.invalid_literals.clearRetainingCapacity();
            self.active_goals = &.{};
            self.roots.clearRetainingCapacity();
            self.bindings.clearRetainingCapacity();
            self.stacks.clearRetainingCapacity();
            try self.stacks.appendNTimes(self.allocator, true, reserved);
            self.depth = 0;
            try self.c.value(.{ .call, self.runtime.functions.reset_temporary, @as(u32, @intCast(self.globals.items.len)) });
            for (self.globals.items) |global| _ = try self.globalArray(m, body.root, global.target);
            const argument: Value = if (callback) |host| .{ .tag = .callable, .word = .{ .id = 0 }, .host = host } else if (arrayAbi(parameter)) try self.fromWire(m, body.root, .{ .id = 0 }, parameter) else blk: {
                const input = try self.c.temp();
                try self.c.op(.local_get, 0);
                if (parameter == .f32) try self.c.op(.i32_reinterpret_f32, 0);
                try self.c.op(.local_set, input.id);
                break :blk .{ .word = input, .floating = parameter == .f32 };
            };
            const value = try self.invoke(.{ .unit = m.unit, .binding = body.binding }, &.{argument}, 0);
            if (arrayAbi(result)) try self.resetPackets();
            const word = if (arrayAbi(result)) try self.toWire(m, body.root, value, result) else try self.scalar(m, body.root, value);
            try self.release(0, null);
            try self.c.value(word);
            if (result == .f32) try self.c.op(.f32_reinterpret_i32, 0);
            const exported = if (callback) |host| self.module.exportCallbackFunction(function, m.name(body.export_name), host, result) else self.module.exportFunction(function, m.name(body.export_name), parameter, result);
            exported catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.unsupported(m, body.root),
            };
            exports += 1;
        }
        if (exports == 0) return error.Declined;
    }
    fn newGlobal(self: *Generator) Error!u32 {
        return self.module.addGlobal(.u32, 0, true) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.Declined,
        };
    }
};
fn valueAbi(m: *const core.Module, ty: T.Id) ?wasm.Scalar {
    const node = m.types.node(ty);
    if (node.tag == .array) return switch (node.a) {
        T.u32_type => .array_u32,
        T.f32_type => .array_f32,
        else => null,
    };
    return switch (ty) {
        T.unit => .unit,
        T.boolean => .bool,
        T.u32_type => .u32,
        T.f32_type => .f32,
        else => null,
    };
}
fn arrayAbi(kind: wasm.Scalar) bool {
    return kind == .array_u32 or kind == .array_f32;
}
fn callbackAbi(m: *const core.Module, ty: T.Id) ?wasm.Callback {
    const node = m.types.node(ty);
    if (node.tag != .function) return null;
    const row = m.types.row(node.c);
    const labels = m.types.rowLabels(node.c);
    if (row.tail != .closed or labels.len != 1 or labels[0] != T.foreign_operation) return null;
    return .{ .parameter = valueAbi(m, node.a) orelse return null, .result = valueAbi(m, node.b) orelse return null };
}
pub fn compile(allocator: std.mem.Allocator, units: []const core.Module, entry: u32) std.mem.Allocator.Error!backend.Result {
    return compileWithConfig(allocator, units, entry, .{});
}
pub fn compileWithConfig(allocator: std.mem.Allocator, units: []const core.Module, entry: u32, config: storage_plan.Config) std.mem.Allocator.Error!backend.Result {
    const views = try allocator.alloc(*const core.Module, units.len);
    defer allocator.free(views);
    for (units, 0..) |*unit_, index| views[index] = unit_;
    const validation = @import("../check/frozen_core_validation.zig");
    for (units) |*unit_| validation.validateBounds(unit_, .{ .units = views }) catch {
        return .{ .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Invalid scoped-storage Core bounds" } };
    };
    for (units) |*unit_| validation.validate(allocator, unit_, .{ .units = views }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidArtifact => {
            return .{ .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Invalid scoped-storage Core evidence" } };
        },
    };
    var module = wasm.Module.init(allocator);
    defer module.deinit();
    const runtime = storage.emit(&module) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };
    var proof_cache = source_proof.SourceProofCache.initWithInventoryBudget(allocator, views) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidArtifact => return .{ .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Invalid source proof context" } },
    };
    defer {
        // Temporary first-frame evidence: the actual Gdev world-storage unit
        // is unit 2. Report its one shared source allowance without changing it.
        for (views) |view| {
            if (view.unit != 2) continue;
            const inventory = view.nodes.len + view.extra.len + view.types.nodes.len + view.types.extra.len + view.obligations.len;
            const allowance = @min(@as(usize, 32_000_000), @max(@as(usize, 1_000_000), inventory * 256));
            if (allowance != 32_000_000) continue;
            if (proof_cache.moduleRemaining(view.unit)) |remaining| std.debug.print("SOURCE_WORK_FINAL unit={d} inventory={d} allowance={d} consumed={d} principal_bytes={d}\n", .{ view.unit, inventory, allowance, allowance - remaining, @sizeOf(@import("../check/package_contracts.zig").Principal) });
        }
        proof_cache.deinit();
    }
    var dispatches: Dispatches = .empty;
    defer dispatches.deinit(allocator);
    var capacity_requests: storage_plan.CapacityRequests = .{ .allocator = allocator };
    defer capacity_requests.deinit();
    var validation_budget: usize = 1_000_000;
    var active_calls: call_plan.ActiveCalls = .{ .allocator = allocator };
    defer active_calls.deinit();
    var g: Generator = .{ .allocator = allocator, .arena = std.heap.ArenaAllocator.init(allocator), .calls = .{ .allocator = allocator }, .active_calls = &active_calls, .units = units, .unit_views = views, .proof_cache = &proof_cache, .dispatches = &dispatches, .capacity_requests = &capacity_requests, .validation_budget = &validation_budget, .module = &module, .runtime = runtime };
    defer g.deinit();
    g.emit(entry) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Declined => return .{ .diagnostic = g.diagnostic orelse .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported } },
    };
    const capacities = try allocator.alloc(u32, g.max_stacks);
    defer allocator.free(capacities);
    if (config.persistent_lanes.len != 0 and config.persistent_lanes.len != g.globals.items.len) return .{ .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Persistent storage budgets must match the named pool inventory" } };
    @memset(capacities, config.grower_bytes);
    capacities[g.fixed_region] = config.temporary_bytes;
    for (g.globals.items, 0..) |global, index| {
        const configured = if (config.persistent_lanes.len == 0) config.persistent_bytes else config.persistent_lanes[index];
        // Inferred extents only reduce reservation; they never enlarge an
        // application's explicit per-pool budget.
        capacities[index] = @min(configured, global.literal_bytes orelse configured);
    }
    if (g.transport_region) |region| capacities[region] = config.transport_bytes;
    try capacity_requests.apply(capacities);
    const memory_plan: storage.Plan = .{ .region_capacities = capacities, .owner_capacity = config.owner_capacity };
    storage.finishPlan(&module, runtime, memory_plan) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Owned storage memory plan exceeds Wasm32 capacity" } },
    };
    if (g.transport) |transport| packets.configure(&module, transport, storage.regionBase(memory_plan, g.transport_region.?) catch unreachable, capacities[g.transport_region.?]) catch {
        return .{ .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Invalid copied transport memory plan" } };
    };
    const bytes = module.assembleWithOptions(.{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .diagnostic = .{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .code = .storage_unsupported, .detail = "Scoped storage emission failed Wasm validation" } },
    };
    return .{ .bytes = bytes, .emitted_functions = module.functions.items.len, .whole_module_only = true };
}
