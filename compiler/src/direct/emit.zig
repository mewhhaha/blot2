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

/// Diverged: an operand never produced a value; its user diverges too.
pub const Error = A.Error || error{ Unsupported, Diverged };

pub const Failure = struct { unit: u32, span: core.Span, message: []u8 };

/// A value: one Wasm local per word of its type's layout.
pub const Val = struct {
    ty: Ty,
    words: []const u32 = &.{},
};

/// named: a function or constant binding; lambda: a closure node of the
/// `parent` instance; partial: a named function applied to its first
/// `parent` arguments; primitive: the same for a primitive alias binding;
/// constructor: a constructor (catalog index `id`) as a function value.
/// host: a Foreign callback adapter calling import `id`; pool: the
/// lazily initialized persistent owner of a global array constant.
/// trap: a closure of a type no use determines, which traps if called.
/// operation: an effect operation's trampoline (id = operation id, ty = its
/// signature); state_get / state_set: a state provider's cell accessors.
pub const InstanceKind = enum(u8) { named, lambda, partial, primitive, constructor, host, pool, trap, operation, state_get, state_set };
pub const InstanceKey = struct { kind: InstanceKind, unit: u32, id: u32, ty: Ty, parent: u32 = 0 };
pub const Instance = struct {
    key: InstanceKey,
    env: types.Env,
    function: u32,
    parameters: []const Ty,
    result: Ty,
    /// Closure convention: the environment pointer is the first parameter.
    /// Captures are its contents, and slot is the function's table index.
    closure: bool = false,
    captures: []const Ty = &.{},
    slot: u32 = 0,
    /// Being emitted to learn its result type; already emitted.
    inferring: bool = false,
    emitted: bool = false,
    /// Every hole (`never`) of the key is a part no use reaches, so the
    /// instance's unbound scheme variables are unused too.
    unused_holes: bool = false,
};
const runtime = @import("runtime.zig");

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
    solve_depth: u32 = 0,
    /// Closures built for function values no use determines (they trap).
    trap_closures: u32 = 0,
    /// Effect operations (lowered operation types) and their frame ids.
    operation_ids: std.AutoHashMapUnmanaged(Ty, u32) = .empty,
    /// Type variables some scheme quantifies, per unit (built on demand).
    quantified: std.AutoHashMapUnmanaged(types.VarKey, void) = .empty,
    quantified_units: std.AutoHashMapUnmanaged(u32, void) = .empty,
    failures: std.ArrayList(struct { failure: Failure, count: u32 = 1, samples: [48]core.Span = undefined, sample_units: [48]u32 = undefined }) = .empty,
    /// The storage runtime, emitted on first use.
    rt: ?runtime.Runtime = null,
    /// Host callback imports by (parameter, result) ABI kinds.
    host_imports: std.AutoHashMapUnmanaged([2]u8, u32) = .empty,
    exported_storage: bool = false,
    /// Pool instance globals: (slot, generation, state) by instance.
    pool_globals: std.AutoHashMapUnmanaged(u32, [3]u32) = .empty,
    holds_memory: std.AutoHashMapUnmanaged(Ty, bool) = .empty,

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
        self.holds_memory.deinit(self.allocator);
        self.host_imports.deinit(self.allocator);
        self.pool_globals.deinit(self.allocator);
        self.quantified.deinit(self.allocator);
        self.operation_ids.deinit(self.allocator);
        self.quantified_units.deinit(self.allocator);
        if (self.failure) |failure| self.allocator.free(failure.message);
        for (self.failures.items) |item| self.allocator.free(item.failure.message);
        self.failures.deinit(self.allocator);
        self.types.deinit();
        self.module.deinit();
        self.arena.deinit();
    }

    /// Moves the current failure into the build's list, counting repeats.
    pub fn recordFailure(self: *Generator, m: *const core.Module, id: core.Id) Error!void {
        const failure = self.failure orelse Failure{ .unit = m.unit, .span = if (id < m.spans.len) m.span(id) else .{ .start = 0, .end = 0 }, .message = try self.allocator.dupe(u8, "Direct backend: unsupported form") };
        self.failure = null;
        for (self.failures.items) |*seen| if (std.mem.eql(u8, seen.failure.message, failure.message)) {
            if (seen.count < 48) {
                seen.samples[seen.count] = failure.span;
                seen.sample_units[seen.count] = failure.unit;
            }
            seen.count += 1;
            self.allocator.free(failure.message);
            return;
        };
        try self.failures.append(self.allocator, .{ .failure = failure });
        const added = &self.failures.items[self.failures.items.len - 1];
        added.samples[0] = failure.span;
        added.sample_units[0] = failure.unit;
    }
    /// One failure summarizing every distinct unsupported form, if any.
    pub fn summary(self: *Generator) Error!?Failure {
        if (self.failures.items.len == 0) return null;
        var text: std.ArrayList(u8) = .empty;
        errdefer text.deinit(self.allocator);
        try text.print(self.allocator, "Direct backend: {d} unsupported form(s): ", .{self.failures.items.len});
        for (self.failures.items, 0..) |item, index| {
            if (index == 24) {
                try text.appendSlice(self.allocator, "; ...");
                break;
            }
            if (index != 0) try text.appendSlice(self.allocator, "; ");
            const message = item.failure.message;
            const prefix = "Direct backend: ";
            try text.appendSlice(self.allocator, if (std.mem.startsWith(u8, message, prefix)) message[prefix.len..] else message);
            try text.print(self.allocator, " ({d}x at", .{item.count});
            for (0..@min(item.count, 48)) |sample| try text.print(self.allocator, " {d}:{d}", .{ item.sample_units[sample], item.samples[sample].start });
            try text.appendSlice(self.allocator, ")");
        }
        const first = self.failures.items[0].failure;
        return .{ .unit = first.unit, .span = first.span, .message = try text.toOwnedSlice(self.allocator) };
    }

    /// Discards a failure an optional attempt recorded.
    pub fn dropFailure(self: *Generator) void {
        if (self.failure) |failure| self.allocator.free(failure.message);
        self.failure = null;
    }

    pub fn fail(self: *Generator, m: *const core.Module, id: core.Id, comptime format: []const u8, arguments: anytype) error{ Unsupported, OutOfMemory } {
        if (self.failure == null) {
            const message = try self.allocator.print("Direct backend: " ++ format, arguments);
            self.failure = .{ .unit = m.unit, .span = if (id < m.spans.len) m.span(id) else .{ .start = 0, .end = 0 }, .message = message };
        }
        return error.Unsupported;
    }
    pub fn typeFailure(self: *Generator, m: *const core.Module, id: core.Id) error{ Unsupported, OutOfMemory } {
        const tag = if (id != 0 and id < m.nodes.len) @tagName(m.node(id).tag) else "declaration";
        return self.fail(m, id, "unsupported type ({s}) at a {s}", .{ self.types.failure_reason, tag });
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
            .array => .{ .unit = 0, .decl = std.math.maxInt(u32) },
            // Storage capabilities are compiler-owned nominal identities.
            .grow, .resize, .ref, .view, .link => .{ .unit = std.math.maxInt(u32), .decl = @backingInt(@as(@import("../check/storage_types.zig").Kind, switch (n.tag) {
                .grow => .grow,
                .resize => .resize,
                .ref => .ref,
                .view => .view,
                else => .link,
            })) },
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
                // Unit zero names built-in receivers; nominals carry their unit.
                if (method.identity.unit != identity.unit or method.identity.decl != identity.decl) continue;
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

    /// `(env, parameter words) -> result words`, the call_indirect type of
    /// every closure of type `parameter -> result`.
    pub fn closureSignature(self: *Generator, parameter: Ty, result: Ty) Error!u32 {
        var words: std.ArrayList(W.ValType) = .empty;
        defer words.deinit(self.allocator);
        try words.append(self.allocator, .i32);
        try words.appendSlice(self.allocator, try self.types.layout(parameter));
        return self.module.signature(words.items, try self.types.layout(result));
    }
    pub fn find(self: *Generator, key: InstanceKey) ?u32 {
        return self.instance_index.get(key);
    }
    pub fn runtime_(self: *Generator) Error!*const runtime.Runtime {
        if (self.rt == null) self.rt = try runtime.emit(self.allocator, &self.module, .{});
        return &self.rt.?;
    }
    /// Whether a value of `ty` can refer to scope-allocated memory.
    pub fn holdsMemory(self: *Generator, ty: Ty) Error!bool {
        if (self.holds_memory.get(ty)) |hit| return hit;
        // A boxed value is a pointer into scope memory.
        if (self.types.boxed(ty) catch false) {
            try self.holds_memory.put(self.allocator, ty, true);
            return true;
        }
        const n = self.types.node(ty);
        const result = switch (n.tag) {
            .unit, .boolean, .u32, .f32, .never => false,
            .function, .provider, .array, .list, .cursor, .grow, .resize, .ref, .view, .link => true,
            .state_provider => try self.holdsMemory(self.types.list(n.a, n.b)[2]),
            .tuple => blk: {
                for (self.types.tupleItems(ty)) |item| if (try self.holdsMemory(item)) break :blk true;
                break :blk false;
            },
            .record => blk: {
                for (0..n.b) |index| if (try self.holdsMemory(self.types.recordField(ty, index).ty)) break :blk true;
                break :blk false;
            },
            .nominal => blk: {
                try self.holds_memory.put(self.allocator, ty, false); // recursion guard
                const cases = try self.types.variants(ty);
                for (cases.payloads) |payload| if (try self.holdsMemory(payload)) break :blk true;
                break :blk false;
            },
        };
        try self.holds_memory.put(self.allocator, ty, result);
        return result;
    }

    pub fn signatureOf(self: *Generator, parameters: []const Ty, result: Ty) Error!u32 {
        var words: std.ArrayList(W.ValType) = .empty;
        defer words.deinit(self.allocator);
        for (parameters) |parameter| try words.appendSlice(self.allocator, try self.types.layout(parameter));
        return self.module.signature(words.items, try self.types.layout(result));
    }

    /// Whether a scheme of `m` quantifies variable `ty`. A variable none
    /// quantifies is one the checker left ambiguous: no use fixes it.
    /// The provider frame id of effect operation `operation` (from 1).
    pub fn operationId(self: *Generator, operation: Ty) Error!u32 {
        const entry = try self.operation_ids.getOrPut(self.allocator, operation);
        if (!entry.found_existing) entry.value_ptr.* = @intCast(self.operation_ids.count());
        return entry.value_ptr.*;
    }
    /// Only variables an instance key can reach count: ones the binding's
    /// type mentions, or obligations on reachable variables determine. A
    /// scheme may also quantify variables its body alone leaves open.
    pub fn isQuantified(self: *Generator, m: *const core.Module, ty: T.Id) Error!bool {
        if (!self.quantified_units.contains(m.unit)) {
            try self.quantified_units.put(self.allocator, m.unit, {});
            var reach: std.AutoHashMapUnmanaged(T.Id, void) = .empty;
            defer reach.deinit(self.allocator);
            for (m.bindings, 0..) |binding, index| {
                const body = m.body(@intCast(index));
                reach.clearRetainingCapacity();
                try self.mentions(m, binding.ty, &reach, 0);
                var obligations: [2]T.List = .{ binding.scheme.obligations, if (body) |b| b.scheme.obligations else .{} };
                // Obligations on reachable receivers reach their results.
                var grew = true;
                while (grew) {
                    grew = false;
                    for (&obligations) |span| for (m.obligations[span.start..][0..span.len]) |goal| {
                        // Exactly what solveObligations can derive: a field or
                        // element of a receiver whose variables are all reachable.
                        if (goal.result == 0 or (goal.kind != .field and goal.kind != .collection)) continue;
                        if (!try self.within(m, goal.ty, &reach)) continue;
                        const before = reach.count();
                        for ([_]T.Id{ goal.result, goal.other, goal.signature }) |part| try self.mentions(m, part, &reach, 0);
                        if (reach.count() != before) grew = true;
                    };
                }
                var schemes: [2]T.List = .{ binding.scheme.variables, if (body) |b| b.scheme.variables else .{} };
                for (&schemes) |span| for (m.types.list(span)) |variable| if (reach.contains(variable))
                    try self.quantified.put(self.allocator, .{ .unit = m.unit, .ty = variable }, {});
            }
        }
        return self.quantified.contains(.{ .unit = m.unit, .ty = ty });
    }
    fn mentions(self: *Generator, m: *const core.Module, ty: T.Id, into: *std.AutoHashMapUnmanaged(T.Id, void), depth: usize) Error!void {
        if (ty <= T.never or depth > 64) return;
        const n = m.types.node(ty);
        switch (n.tag) {
            .variable, .bound => try into.put(self.allocator, ty, {}),
            .usage, .forall, .array, .list, .cursor => try self.mentions(m, n.a, into, depth + 1),
            .function => {
                try self.mentions(m, n.a, into, depth + 1);
                try self.mentions(m, n.b, into, depth + 1);
            },
            .product => for (m.types.list(.{ .start = n.a, .len = n.b })) |child| try self.mentions(m, child, into, depth + 1),
            .record => for (0..n.b) |index| try self.mentions(m, m.types.recordField(n, index).ty, into, depth + 1),
            .nominal => for (m.types.nominalArguments(n)) |argument| try self.mentions(m, argument, into, depth + 1),
            else => {},
        }
    }
    /// Whether every variable of `ty` is in `reach`.
    fn within(self: *Generator, m: *const core.Module, ty: T.Id, reach: *const std.AutoHashMapUnmanaged(T.Id, void)) Error!bool {
        var found: std.AutoHashMapUnmanaged(T.Id, void) = .empty;
        defer found.deinit(self.allocator);
        try self.mentions(m, ty, &found, 0);
        var it = found.keyIterator();
        while (it.next()) |key| if (!reach.contains(key.*)) return false;
        return true;
    }

    /// The instance of a named function at concrete function type `ty`.
    pub fn named(self: *Generator, target: core.BindingRef, ty: Ty, site: *const core.Module, site_id: core.Id) Error!u32 {
        return self.namedWith(target, ty, false, site, site_id);
    }
    /// `named`, where `unused_holes` says every hole of `ty` is unused.
    pub fn namedWith(self: *Generator, target: core.BindingRef, ty: Ty, unused_holes: bool, site: *const core.Module, site_id: core.Id) Error!u32 {
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
            // The body determines its result type: emit it now.
            error.Unsupported => return self.inferResultWith(key, env, lowered, unused_holes, site, site_id),
            else => return err,
        };
        const id = try self.addInstance(key, env, lowered, result, site, site_id);
        self.instance(id).unused_holes = unused_holes;
        return id;
    }
    /// An instance whose result type only its body determines: emitted
    /// immediately, with its signature fixed once the result is known.
    fn inferResult(self: *Generator, key: InstanceKey, env: types.Env, parameters: []const Ty, site: *const core.Module, site_id: core.Id) Error!u32 {
        return self.inferResultWith(key, env, parameters, false, site, site_id);
    }
    fn inferResultWith(self: *Generator, key: InstanceKey, env: types.Env, parameters: []const Ty, unused_holes: bool, site: *const core.Module, site_id: core.Id) Error!u32 {
        const function = try self.module.addFunction(try self.module.signature(&.{}, &.{}));
        const id: u32 = @intCast(self.instances.items.len);
        const owned = try self.arena.allocator().create(Instance);
        owned.* = .{ .key = key, .env = env, .function = function, .parameters = parameters, .result = types.never, .inferring = true, .emitted = true, .unused_holes = unused_holes };
        try self.nameFunction(function, key);
        try self.instances.append(self.allocator, owned);
        try self.instance_index.put(self.allocator, key, id);
        try @import("function.zig").emitInstance(self, id);
        owned.inferring = false;
        const signature = self.signatureOf(parameters, owned.result) catch |err| switch (err) {
            error.Unsupported => return self.typeFailure(site, site_id),
            else => return err,
        };
        self.module.functions.items[function - self.module.imports.items.len].signature = signature;
        return id;
    }
    fn addInstance(self: *Generator, key: InstanceKey, env: types.Env, parameters: []const Ty, result: Ty, site: *const core.Module, site_id: core.Id) Error!u32 {
        return self.addInstanceWith(key, env, parameters, result, false, &.{}, site, site_id);
    }
    pub fn addInstanceWith(self: *Generator, key: InstanceKey, env: types.Env, parameters: []const Ty, result: Ty, closure: bool, captures: []const Ty, site: *const core.Module, site_id: core.Id) Error!u32 {
        if (closure and parameters.len != 1) return self.fail(site, site_id, "closures take one parameter", .{});
        const signature = (if (closure and parameters.len == 1) self.closureSignature(parameters[0], result) else self.signatureOf(parameters, result)) catch |err| switch (err) {
            error.Unsupported => return self.typeFailure(site, site_id),
            else => return err,
        };
        const function = try self.module.addFunction(signature);
        const id: u32 = @intCast(self.instances.items.len);
        const owned = try self.arena.allocator().create(Instance);
        owned.* = .{ .key = key, .env = env, .function = function, .parameters = parameters, .result = result, .closure = closure, .captures = captures, .slot = if (closure) try self.module.tableSlot(function) else 0 };
        try self.nameFunction(function, key);
        try self.instances.append(self.allocator, owned);
        try self.instance_index.put(self.allocator, key, id);
        try self.queue.append(self.allocator, id);
        return id;
    }

    /// Names the function after its source binding, for the name section.
    pub fn nameFunction(self: *Generator, function: u32, key: InstanceKey) Error!void {
        const m = self.types.module(key.unit) orelse return;
        const base: []const u8 = switch (key.kind) {
            .named, .partial, .pool => if (m.body(key.id)) |body| m.name(body.declaration_name) else "binding",
            .lambda => "lambda",
            .primitive => "primitive",
            .constructor => "constructor",
            .host => "host",
            .trap => "trap",
            .operation => "operation",
            .state_get => "state_get",
            .state_set => "state_set",
        };
        const text = try self.module.arena.allocator().print("{s}.{s}#{d}", .{ @tagName(key.kind), base, function });
        try self.module.names.put(self.allocator, function, text);
    }
    /// The concrete type of `target` when applied to `arguments`: its
    /// parameter types fix its variables, obligations the dependent ones.
    pub fn calleeFromArguments(self: *Generator, target: core.BindingRef, arguments: []const Val, site: *const core.Module, site_id: core.Id) Error!Ty {
        const m = self.unitModule(target.unit);
        const binding = m.binding(target.binding);
        var env: types.Env = .empty;
        defer env.deinit(self.allocator);
        var arrow = binding.ty;
        for (arguments) |argument| {
            var n = m.types.node(arrow);
            while (n.tag == .forall or n.tag == .usage) {
                arrow = n.a;
                n = m.types.node(arrow);
            }
            if (n.tag != .function) break;
            try self.types.match(m, n.a, argument.ty, &env);
            arrow = n.b;
        }
        if (m.body(target.binding)) |body| try self.solveObligations(m, body.scheme.obligations, &env);
        try self.solveObligations(m, binding.scheme.obligations, &env);
        if (self.types.lower(m, binding.ty, &env)) |ty| return ty else |err| switch (err) {
            error.Unsupported => {},
            else => return err,
        }
        // Only the body determines the result: key the instance by its
        // parameter types, infer the result, and alias the full type.
        const body = m.body(target.binding) orelse return self.typeFailure(site, site_id);
        const parameters = m.bodyParameters(body);
        if (!body.is_function or arguments.len < parameters.len) return self.typeFailure(site, site_id);
        const instance_id = try self.namedByParameters(target, arguments[0..parameters.len], site, site_id);
        const instance_ = self.instance(instance_id);
        var full = instance_.result;
        var at = parameters.len;
        while (at != 0) {
            at -= 1;
            full = try self.types.function(arguments[at].ty, full);
        }
        try self.instance_index.put(self.allocator, .{ .kind = .named, .unit = target.unit, .id = target.binding, .ty = full }, instance_id);
        return full;
    }
    fn namedByParameters(self: *Generator, target: core.BindingRef, arguments: []const Val, site: *const core.Module, site_id: core.Id) Error!u32 {
        var marker = types.never;
        var at = arguments.len;
        while (at != 0) {
            at -= 1;
            marker = try self.types.function(arguments[at].ty, marker);
        }
        const key: InstanceKey = .{ .kind = .named, .unit = target.unit, .id = target.binding, .ty = marker };
        if (self.instance_index.get(key)) |found| return found;
        const m = self.unitModule(target.unit);
        const body = m.body(target.binding).?;
        var env: types.Env = .empty;
        errdefer env.deinit(self.allocator);
        const parameters = m.bodyParameters(body);
        const lowered = try self.arena.allocator().alloc(Ty, parameters.len);
        for (parameters, arguments, lowered) |parameter, argument, *slot| {
            try self.types.match(m, parameter.ty, argument.ty, &env);
            slot.* = argument.ty;
        }
        try self.solveObligations(m, body.scheme.obligations, &env);
        const result = self.types.lower(m, m.typeOf(body.root), &env) catch |err| switch (err) {
            error.Unsupported => return self.inferResult(key, env, lowered, site, site_id),
            else => return err,
        };
        return self.addInstance(key, env, lowered, result, site, site_id);
    }

    pub fn solveObligationsPublic(self: *Generator, m: *const core.Module, goals_span: T.List, env: *types.Env) Error!void {
        return self.solveObligations(m, goals_span, env);
    }
    /// A lambda instance whose result type its body determines.
    pub fn inferClosure(self: *Generator, key: InstanceKey, env: types.Env, parameters: []const Ty, captures: []const Ty, site: *const core.Module, site_id: core.Id) Error!u32 {
        const function = try self.module.addFunction(try self.module.signature(&.{}, &.{}));
        const id: u32 = @intCast(self.instances.items.len);
        const owned = try self.arena.allocator().create(Instance);
        owned.* = .{ .key = key, .env = env, .function = function, .parameters = parameters, .result = types.never, .closure = true, .captures = captures, .slot = try self.module.tableSlot(function), .inferring = true, .emitted = true };
        try self.nameFunction(function, key);
        try self.instances.append(self.allocator, owned);
        try self.instance_index.put(self.allocator, key, id);
        try @import("function.zig").emitInstance(self, id);
        owned.inferring = false;
        if (parameters.len != 1) return self.fail(site, site_id, "closures take one parameter", .{});
        const signature = self.closureSignature(parameters[0], owned.result) catch |err| switch (err) {
            error.Unsupported => return self.typeFailure(site, site_id),
            else => return err,
        };
        self.module.functions.items[function - self.module.imports.items.len].signature = signature;
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
                        const cases = self.types.variants(receiver) catch break :blk receiver;
                        if (cases.payloads.len != 1) break :blk receiver;
                        break :blk cases.payloads[0];
                    },
                    else => receiver,
                };
                if (self.types.findField(record, name)) |position| {
                    try self.types.match(m, goal.result, self.types.recordField(record, position).ty, env);
                    continue;
                }
                // A receiver member: its result at this receiver.
                if (self.solve_depth >= 32) continue;
                const identity = self.receiverIdentity(receiver) orelse continue;
                const target = self.dispatchTarget(m, identity, goal.name, .none) orelse continue;
                self.solve_depth += 1;
                defer self.solve_depth -= 1;
                const callee = self.calleeFromArguments(target, &.{.{ .ty = receiver }}, m, 0) catch |err| switch (err) {
                    error.Unsupported => {
                        self.dropFailure();
                        continue;
                    },
                    else => return err,
                };
                const arrow = self.types.node(callee);
                if (arrow.tag == .function) try self.types.match(m, goal.result, arrow.b, env);
            }
            if (env.count() == before) return;
        }
    }

    pub fn emitAll(self: *Generator) Error!void {
        var next: usize = 0;
        while (next < self.queue.items.len) : (next += 1) {
            const item = self.instance(self.queue.items[next]);
            if (item.emitted) continue;
            item.emitted = true;
            try @import("function.zig").emitInstance(self, self.queue.items[next]);
        }
    }
    pub fn instance(self: *Generator, id: u32) *Instance {
        return self.instances.items[id];
    }
};
