//! Direct backend: each `(binding, concrete type)` instance becomes one Wasm
//! function, emitted once in a single pass over its Core body. Values live in
//! Wasm locals laid out by their concrete type; nothing flows between
//! functions except arguments and results.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const W = @import("writer.zig");
const types = @import("types.zig");
const Ty = types.Ty;
const A = std.mem.Allocator;

pub const Error = A.Error || error{Unsupported};

pub const Failure = struct { unit: u32, span: core.Span, message: []u8 };

/// A value: one Wasm local per word of its type's layout.
pub const Val = struct {
    ty: Ty,
    words: []const u32 = &.{},
};

const InstanceKind = enum(u8) { named, lambda };
const InstanceKey = struct { kind: InstanceKind, unit: u32, id: u32, ty: Ty, parent: u32 = 0 };
const Instance = struct {
    key: InstanceKey,
    env: types.Env,
    function: u32,
    parameters: []const Ty,
    result: Ty,
};

pub const Generator = struct {
    allocator: A,
    arena: std.heap.ArenaAllocator,
    units: []const core.Module,
    types: types.Types,
    module: W.Module,
    /// Stable addresses: emission adds instances while others are borrowed.
    instances: std.ArrayList(*Instance) = .empty,
    instance_index: std.AutoHashMapUnmanaged(InstanceKey, u32) = .empty,
    queue: std.ArrayList(u32) = .empty,
    failure: ?Failure = null,

    pub fn init(allocator: A, units: []const core.Module) A.Error!Generator {
        const interned = types.Types.init(allocator, units) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Unsupported => unreachable,
        };
        return .{ .allocator = allocator, .arena = std.heap.ArenaAllocator.init(allocator), .units = units, .types = interned, .module = W.Module.init(allocator) };
    }
    pub fn deinit(self: *Generator) void {
        for (self.instances.items) |item| item.env.deinit(self.allocator);
        self.instances.deinit(self.allocator);
        self.instance_index.deinit(self.allocator);
        self.queue.deinit(self.allocator);
        if (self.failure) |failure| self.allocator.free(failure.message);
        self.types.deinit();
        self.module.deinit();
        self.arena.deinit();
    }

    pub fn fail(self: *Generator, m: *const core.Module, id: core.Id, comptime format: []const u8, arguments: anytype) error{ Unsupported, OutOfMemory } {
        if (self.failure == null) {
            const message = try self.allocator.print("Direct backend: " ++ format, arguments);
            self.failure = .{ .unit = m.unit, .span = if (id < m.spans.len) m.span(id) else .{ .start = 0, .end = 0 }, .message = message };
        }
        return error.Unsupported;
    }
    pub fn typeFailure(self: *Generator, m: *const core.Module, id: core.Id) error{ Unsupported, OutOfMemory } {
        return self.fail(m, id, "unsupported type ({s})", .{self.types.failure_reason});
    }

    pub fn unitModule(self: *Generator, unit_id: u32) *const core.Module {
        return self.types.module(unit_id).?;
    }
    /// Follows external bindings to their defining declaration. Unit zero in
    /// a reference means the referring unit `m`.
    pub fn resolve(self: *Generator, m: *const core.Module, target: core.BindingRef) core.BindingRef {
        var current: core.BindingRef = .{ .unit = if (target.unit == 0) m.unit else target.unit, .binding = target.binding };
        for (0..64) |_| {
            const owner = self.types.module(current.unit) orelse return current;
            const binding = owner.binding(current.binding);
            if (binding.kind != .external) return current;
            current = .{ .unit = if (binding.target.unit == 0) current.unit else binding.target.unit, .binding = binding.target.binding };
        }
        return current;
    }

    /// The associated-function family of a concrete receiver type.
    pub fn receiverIdentity(self: *Generator, ty: Ty) ?T.NominalIdentity {
        const n = self.types.node(ty);
        return switch (n.tag) {
            .nominal => self.types.nominalIdentity(ty),
            .u32 => .{ .unit = 0, .decl = T.u32_type },
            .f32 => .{ .unit = 0, .decl = T.f32_type },
            .boolean => .{ .unit = 0, .decl = T.boolean },
            .unit => .{ .unit = 0, .decl = T.unit },
            .array, .grow, .resize => .{ .unit = 0, .decl = std.math.maxInt(u32) },
            .list => .{ .unit = 0, .decl = std.math.maxInt(u32) - 1 },
            .cursor => .{ .unit = 0, .decl = std.math.maxInt(u32) - 2 },
            else => null,
        };
    }
    /// The associated member `member` (a symbol of `m`) for `identity`: the
    /// referring unit's catalog first, then the nominal's own unit.
    pub fn dispatchTarget(self: *Generator, m: *const core.Module, identity: T.NominalIdentity, member: u32, operator: T.Operator) ?core.BindingRef {
        const owner = if (identity.unit == 0 or identity.unit == std.math.maxInt(u32)) m else self.types.module(identity.unit) orelse m;
        for ([_]*const core.Module{ m, owner }, 0..) |catalog, index| {
            if (index == 1 and catalog == m) continue;
            for (catalog.associated) |method| {
                // Catalog identities may name their own unit as zero.
                const local = method.identity.unit == 0 and method.identity.decl != 0;
                const same = (method.identity.unit == identity.unit or (local and catalog.unit == identity.unit)) and method.identity.decl == identity.decl;
                if (!same) continue;
                if (if (member != 0) method.member != member else method.operator != operator) continue;
                var target = method.target;
                if (target.unit == 0) target.unit = catalog.unit;
                const defining = self.types.module(target.unit) orelse continue;
                if (defining != m and defining.binding(target.binding).private) continue;
                return self.resolve(catalog, target);
            }
        }
        return null;
    }

    pub fn signatureOf(self: *Generator, parameters: []const Ty, result: Ty) Error!u32 {
        var words: std.ArrayList(W.ValType) = .empty;
        defer words.deinit(self.allocator);
        for (parameters) |parameter| try words.appendSlice(self.allocator, try self.types.layout(parameter));
        return self.module.signature(words.items, try self.types.layout(result));
    }

    /// The instance of a named function at concrete function type `ty`.
    pub fn named(self: *Generator, target: core.BindingRef, ty: Ty, site: *const core.Module, site_id: core.Id) Error!u32 {
        const key: InstanceKey = .{ .kind = .named, .unit = target.unit, .id = target.binding, .ty = ty };
        if (self.instance_index.get(key)) |found| return found;
        const m = self.unitModule(target.unit);
        const body = m.body(target.binding) orelse return self.fail(site, site_id, "call target has no body", .{});
        const binding = m.binding(target.binding);
        var env: types.Env = .empty;
        errdefer env.deinit(self.allocator);
        try self.types.match(m, binding.ty, ty, &env);
        try self.solveObligations(m, body.scheme.obligations, &env);
        const parameters = m.bodyParameters(body);
        const lowered = try self.arena.allocator().alloc(Ty, parameters.len);
        for (parameters, lowered) |parameter, *slot| slot.* = self.types.lower(m, parameter.ty, &env) catch |err| switch (err) {
            error.Unsupported => return self.typeFailure(site, site_id),
            else => return err,
        };
        const result = self.types.lower(m, m.typeOf(body.root), &env) catch |err| switch (err) {
            error.Unsupported => return self.typeFailure(site, site_id),
            else => return err,
        };
        return self.addInstance(key, env, lowered, result, site, site_id);
    }
    fn addInstance(self: *Generator, key: InstanceKey, env: types.Env, parameters: []const Ty, result: Ty, site: *const core.Module, site_id: core.Id) Error!u32 {
        const signature = self.signatureOf(parameters, result) catch |err| switch (err) {
            error.Unsupported => return self.typeFailure(site, site_id),
            else => return err,
        };
        const function = try self.module.addFunction(signature);
        const id: u32 = @intCast(self.instances.items.len);
        const owned = try self.arena.allocator().create(Instance);
        owned.* = .{ .key = key, .env = env, .function = function, .parameters = parameters, .result = result };
        try self.instances.append(self.allocator, owned);
        try self.instance_index.put(self.allocator, key, id);
        try self.queue.append(self.allocator, id);
        return id;
    }

    /// Dependent type variables (field and element results) follow from the
    /// receivers the instance's parameters already fixed.
    fn solveObligations(self: *Generator, m: *const core.Module, goals_span: T.List, env: *types.Env) Error!void {
        const goals = m.obligations[goals_span.start..][0..goals_span.len];
        var pass: usize = 0;
        while (pass <= goals.len) : (pass += 1) {
            const before = env.count();
            for (goals) |goal| {
                if (goal.result == 0) continue;
                if (goal.kind != .field and goal.kind != .collection) continue;
                const receiver = self.types.lower(m, goal.ty, env) catch continue;
                const n = self.types.node(receiver);
                if (goal.kind == .collection) {
                    switch (n.tag) {
                        .array, .list, .cursor, .grow, .resize, .view => try self.types.match(m, goal.result, n.a, env),
                        else => {},
                    }
                    continue;
                }
                const spelling = m.fieldSpelling(goal.name) orelse continue;
                const name = try self.types.fieldName(spelling);
                const record = switch (n.tag) {
                    .record => receiver,
                    .nominal => blk: {
                        const cases = self.types.variants(receiver) catch continue;
                        if (cases.payloads.len != 1) continue;
                        break :blk cases.payloads[0];
                    },
                    else => continue,
                };
                const position = self.types.findField(record, name) orelse continue;
                try self.types.match(m, goal.result, self.types.recordField(record, position).ty, env);
            }
            if (env.count() == before) return;
        }
    }

    pub fn emitAll(self: *Generator) Error!void {
        var next: usize = 0;
        while (next < self.queue.items.len) : (next += 1) {
            try @import("function.zig").emitInstance(self, self.queue.items[next]);
        }
    }
    pub fn instance(self: *Generator, id: u32) *Instance {
        return self.instances.items[id];
    }
};
