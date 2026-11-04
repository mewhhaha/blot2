//! Bounded source admission for the first fixed-owner recursive calling ABI.
//! This proves a finite access footprint, never initialization or runtime aliasing.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const recipe = @import("../eval/body_recipe.zig");
const A = std.mem.Allocator;
const Error = A.Error || error{Declined};
const limit = 100_000;

pub const Access = struct { read: bool = false, write: bool = false };
pub const Contract = struct {
    parameter_access: []const Access,
    self_recursive: bool,
    work: usize,
    backedges: usize,
};
const Edge = struct { target: core.BindingRef, owners: []const ?usize };
const Direct = struct { access: []Access, edges: []const Edge, self_edges: usize, result: T.Tag, work: usize };

pub const Cache = struct {
    arena: ?std.heap.ArenaAllocator = null,
    candidates: std.AutoHashMapUnmanaged(core.BindingRef, bool) = .empty,
    sources: std.AutoHashMapUnmanaged(core.BindingRef, ?*const Direct) = .empty,
    completed: std.AutoHashMapUnmanaged(core.BindingRef, ?*const Contract) = .empty,
    discovery_bodies: usize = 0,
    discovery_nodes: usize = 0,
    scans: usize = 0,
    nodes: usize = 0,

    pub fn deinit(self: *Cache, allocator: A) void {
        self.candidates.deinit(allocator);
        self.sources.deinit(allocator);
        self.completed.deinit(allocator);
        if (self.arena) |*arena| arena.deinit();
        self.* = .{};
    }
    fn owner(units: []const core.Module, unit: u32) ?*const core.Module {
        if (unit != 0 and unit <= units.len and units[unit - 1].unit == unit) return &units[unit - 1];
        for (units) |*m| if (m.unit == unit) return m;
        return null;
    }
    fn canonical(units: []const core.Module, target_: core.BindingRef) ?core.BindingRef {
        var target = target_;
        for (0..128) |_| {
            const m = owner(units, target.unit) orelse return null;
            if (target.binding == 0 or target.binding >= m.bindings.len) return null;
            const binding = m.binding(target.binding);
            if (binding.kind != .external) return target;
            target = binding.target;
            if (target.unit == 0) target.unit = m.unit;
        }
        return null;
    }
    /// Cheap negative prefilter: no source/helper admission for ordinary calls.
    pub fn analyze(self: *Cache, allocator: A, units: []const core.Module, target_: core.BindingRef) A.Error!?*const Contract {
        const target = canonical(units, target_) orelse return null;
        if (self.completed.get(target)) |cached| return cached;
        const m = owner(units, target.unit).?;
        const body = m.body(target.binding) orelse return null;
        const candidate = self.candidates.get(target) orelse blk: {
            self.discovery_bodies += 1;
            var pending: recipe.Pending = .{ .limit = limit };
            defer pending.items.deinit(allocator);
            var seen: std.AutoHashMapUnmanaged(core.Id, void) = .empty;
            defer seen.deinit(allocator);
            var found = false;
            pending.append(allocator, body.root) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.PlanLimit => return null,
            };
            while (pending.pop()) |id| {
                if (id == 0 or seen.contains(id)) continue;
                if (id >= m.nodes.len or seen.count() == limit) break;
                try seen.put(allocator, id, {});
                self.discovery_nodes += 1;
                const n = m.node(id);
                if (n.tag == .call) {
                    var called = m.call(id).target;
                    if (called.unit == 0) called.unit = m.unit;
                    if (canonical(units, called)) |resolved| if (std.meta.eql(target, resolved)) {
                        found = true;
                        break;
                    };
                }
                recipe.appendChildren(&pending, allocator, m, id, false) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.PlanLimit => break,
                };
            }
            try self.candidates.put(allocator, target, found);
            break :blk found;
        };
        var result: ?*const Contract = null;
        if (candidate) {
            if (self.arena == null) self.arena = .init(allocator);
            var solve: Solve = .{ .cache = self, .allocator = allocator, .units = units, .root = target };
            defer solve.completed.deinit(allocator);
            result = solve.run(target, 0) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Declined => null,
            };
        }
        try self.completed.put(allocator, target, result);
        return result;
    }
    fn direct(self: *Cache, allocator: A, units: []const core.Module, target: core.BindingRef) Error!*const Direct {
        if (self.sources.get(target)) |cached| return cached orelse error.Declined;
        const m = owner(units, target.unit) orelse return error.Declined;
        const body = m.body(target.binding) orelse return error.Declined;
        var walk: Walk = .{ .allocator = allocator, .arena = self.arena.?.allocator(), .units = units, .module = m, .body = body, .target = target };
        defer walk.aliases.deinit(allocator);
        const result = walk.scan() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Declined => null,
        };
        try self.sources.put(allocator, target, result);
        self.scans += 1;
        if (result) |summary| {
            self.nodes += summary.work;
            return summary;
        }
        return error.Declined;
    }
};

fn scalar(m: *const core.Module, ty: T.Id) bool {
    return switch (m.types.node(ty).tag) {
        .unit, .u32, .boolean, .never => true,
        else => false,
    };
}
fn array(m: *const core.Module, ty: T.Id) bool {
    const n = m.types.node(ty);
    return n.tag == .array and m.types.node(n.a).tag == .u32;
}
fn closed(scheme: T.Scheme) bool {
    return scheme.variables.len == 0 and scheme.obligations.len == 0 and scheme.generative.len == 0;
}
fn pureRow(m: *const core.Module, row: T.Effects.Id, scheme: T.Scheme) bool {
    const value = m.types.row(row);
    if (value.labels.len != 0) return false;
    if (value.tail == .closed) return true;
    if (value.tail != .variable) return false;
    // A direct recursive effect equation can retain its generalized row tail.
    // Complete body/helper admission below supplies its finite pure solution.
    return std.mem.findScalar(u32, m.types.list(scheme.closed_rows), value.tail.variable) != null or
        std.mem.findScalar(u32, m.types.list(scheme.row_variables), value.tail.variable) != null;
}

const Walk = struct {
    allocator: A,
    arena: A,
    units: []const core.Module,
    module: *const core.Module,
    body: *const core.Body,
    target: core.BindingRef,
    aliases: std.AutoHashMapUnmanaged(core.BindingId, core.BindingId) = .empty,
    remaining: usize = limit,

    fn origin(self: *Walk, id: core.Id, depth: usize) Error!usize {
        if (id == 0 or depth == 128 or self.remaining == 0) return error.Declined;
        self.remaining -= 1;
        const m = self.module;
        const n = m.node(id);
        if (n.tag == .update) return self.origin(m.updateInfo(id).root, depth + 1);
        if (n.tag != .reference) return error.Declined;
        const ref = m.reference(id);
        if (ref.unit != 0 and ref.unit != m.unit) return error.Declined;
        return self.bindingOrigin(ref.binding, depth + 1);
    }
    fn bindingOrigin(self: *Walk, binding: core.BindingId, depth: usize) Error!usize {
        if (depth >= 128 or binding == 0 or binding >= self.module.bindings.len or self.remaining == 0) return error.Declined;
        self.remaining -= 1;
        for (self.module.bodyParameters(self.body), 0..) |p, i| if (p.binding == binding and array(self.module, p.ty)) return i;
        if (self.aliases.get(binding)) |prior| return self.bindingOrigin(prior, depth + 1);
        const source = self.module.binding(binding);
        if (source.kind != .local or source.initializer == 0) return error.Declined;
        return self.origin(source.initializer, depth + 1);
    }
    fn scalarBinding(self: *const Walk, binding: core.BindingId) bool {
        return binding != 0 and binding < self.module.bindings.len and scalar(self.module, self.module.binding(binding).ty);
    }
    fn scan(self: *Walk) Error!*const Direct {
        const m = self.module;
        const source = m.binding(self.target.binding);
        if (!self.body.is_function or source.kind != .global or !closed(self.body.scheme) or !closed(source.scheme)) return error.Declined;
        const parameters = m.bodyParameters(self.body);
        if (source.scheme.closed_rows.len > limit or source.scheme.row_variables.len > limit) return error.Declined;
        if (parameters.len > 128) return error.Declined;
        var signature = source.ty;
        for (parameters) |p| {
            const arrow = m.types.node(signature);
            if ((!scalar(m, p.ty) and !array(m, p.ty)) or arrow.tag != .function or arrow.a != p.ty or !pureRow(m, arrow.c, source.scheme)) return error.Declined;
            signature = arrow.b;
        }
        if (!scalar(m, signature) or signature != m.typeOf(self.body.root)) return error.Declined;
        var recipes: recipe.Cache = .{};
        defer recipes.deinit(self.allocator);
        const visits = (try recipes.get(self.allocator, self.units, .{ .owner = for (self.units, 0..) |*unit, i| {
            if (unit == m) break i;
        } else return error.Declined, .body = self.body.root, .callables = false }, limit) orelse return error.Declined).visits.items;
        for (visits) |id| switch (m.node(id).tag) {
            .loop => for (m.loopCarries(id)) |carry| {
                if (self.scalarBinding(carry.incoming)) continue;
                try self.aliases.put(self.allocator, carry.iteration, carry.incoming);
                try self.aliases.put(self.allocator, carry.outgoing, carry.incoming);
            },
            .if_value, .if_stmt => for (m.branchMerges(id)) |merge| {
                if (!self.scalarBinding(merge.result)) try self.aliases.put(self.allocator, merge.result, merge.then_binding);
            },
            else => {},
        };
        const access = try self.arena.alloc(Access, parameters.len);
        @memset(access, .{});
        var edges: std.ArrayList(Edge) = .empty;
        var self_edges: usize = 0;
        for (visits) |id| {
            const n = m.node(id);
            if (!scalar(m, n.ty) and !array(m, n.ty)) return error.Declined;
            switch (n.tag) {
                .constant => if (!scalar(m, n.ty)) return error.Declined,
                .reference => {
                    const ref = m.reference(id);
                    if ((ref.unit != 0 and ref.unit != m.unit) or ref.binding == 0 or ref.binding >= m.bindings.len) return error.Declined;
                    const kind = m.binding(ref.binding).kind;
                    if (kind != .local and kind != .parameter) return error.Declined;
                    if (array(m, n.ty)) _ = try self.origin(id, 0);
                },
                .scalar => {
                    if (n.c != 0) return error.Declined;
                    switch (n.op) {
                        .add, .sub, .mul, .div, .rem, .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right, .min, .max, .bit_not, .neg => {},
                        else => return error.Declined,
                    }
                },
                .logical, .bind, .return_, .block, .suite, .panic, .break_ => {},
                .pattern_bind => switch (m.pattern(n.a).tag) {
                    .bind, .wildcard => {},
                    else => return error.Declined,
                },
                .if_value, .if_stmt => for (m.branchMerges(id)) |merge| {
                    if (!self.scalarBinding(merge.result) and try self.bindingOrigin(merge.then_binding, 0) != try self.bindingOrigin(merge.else_binding, 0)) return error.Declined;
                },
                .loop => {
                    const info = m.loopInfo(id);
                    if (info.kind == .array) return error.Declined;
                    if (info.pattern != 0) switch (m.pattern(info.pattern).tag) {
                        .bind, .wildcard => {},
                        else => return error.Declined,
                    };
                    for (m.loopCarries(id)) |carry| if (!self.scalarBinding(carry.incoming) and try self.bindingOrigin(carry.incoming, 0) != try self.bindingOrigin(carry.backedge, 0)) return error.Declined;
                },
                .update => {
                    const update = m.updateInfo(id);
                    const selectors = m.updateSelectors(id);
                    if (m.updatePath(id).len != 0 or selectors.len != 1 or selectors[0].kind != .index or !array(m, selectors[0].source_type) or m.types.node(selectors[0].result_type).tag != .u32) return error.Declined;
                    const owner = try self.origin(update.root, 0);
                    // Owned-place lowering reads the old row for the self binding.
                    access[owner].read = true;
                    access[owner].write = true;
                },
                .array_op => {
                    const operands = m.children(id);
                    const op = m.arrayOperation(id);
                    if (op != .get and op != .length) return error.Declined;
                    if (operands.len == 0 or !array(m, m.typeOf(operands[0]))) return error.Declined;
                    const index = try self.origin(operands[0], 0);
                    if (op == .get) access[index].read = true;
                },
                .call => {
                    const call = m.call(id);
                    var called = call.target;
                    if (called.unit == 0) called.unit = m.unit;
                    called = Cache.canonical(self.units, called) orelse return error.Declined;
                    const callee = Cache.owner(self.units, called.unit).?;
                    const body = callee.body(called.binding) orelse return error.Declined;
                    const formals = callee.bodyParameters(body);
                    if (formals.len > 128 or call.arguments.len != formals.len) return error.Declined;
                    const owners = try self.arena.alloc(?usize, formals.len);
                    @memset(owners, null);
                    for (call.arguments, formals, 0..) |argument, formal, i| {
                        if (array(callee, formal.ty)) {
                            if (!array(m, m.typeOf(argument))) return error.Declined;
                            owners[i] = try self.origin(argument, 0);
                            if (std.meta.eql(called, self.target) and owners[i].? != i) return error.Declined;
                        } else if (!scalar(callee, formal.ty) or m.types.node(m.typeOf(argument)).tag != callee.types.node(formal.ty).tag) return error.Declined;
                    }
                    if (std.meta.eql(called, self.target)) self_edges += 1 else try edges.append(self.arena, .{ .target = called, .owners = owners });
                },
                else => return error.Declined,
            }
        }
        const result = try self.arena.create(Direct);
        result.* = .{ .access = access, .edges = edges.items, .self_edges = self_edges, .result = m.types.node(signature).tag, .work = visits.len };
        return result;
    }
};

const Solve = struct {
    cache: *Cache,
    allocator: A,
    units: []const core.Module,
    root: core.BindingRef,
    active: [128]core.BindingRef = undefined,
    completed: std.AutoHashMapUnmanaged(core.BindingRef, *const Contract) = .empty,
    remaining: usize = limit,

    fn run(self: *Solve, target: core.BindingRef, depth: usize) Error!*const Contract {
        if (depth == self.active.len or self.remaining == 0) return error.Declined;
        if (self.completed.get(target)) |result| return result;
        for (self.active[0..depth]) |active| if (std.meta.eql(active, target)) return error.Declined;
        self.remaining -= 1;
        const direct = try self.cache.direct(self.allocator, self.units, target);
        if (direct.work > self.remaining) return error.Declined;
        self.remaining -= direct.work;
        const root = std.meta.eql(self.root, target);
        if (!root and direct.self_edges != 0) return error.Declined;
        if (root) {
            const m = Cache.owner(self.units, target.unit).?;
            for (m.bodyParameters(m.body(target.binding).?)) |p| if (m.types.node(p.ty).tag != .u32 and !array(m, p.ty)) return error.Declined;
            if (direct.result != .unit or direct.self_edges == 0) return error.Declined;
        }
        self.active[depth] = target;
        const arena = self.cache.arena.?.allocator();
        const access = try arena.dupe(Access, direct.access);
        var work = direct.work;
        for (direct.edges) |edge| {
            const child = try self.run(edge.target, depth + 1);
            if (child.work > limit - work) return error.Declined;
            work += child.work;
            for (child.parameter_access, edge.owners) |effect, ordinal| if (ordinal) |i| {
                access[i].read = access[i].read or effect.read;
                access[i].write = access[i].write or effect.write;
            };
        }
        const result = try arena.create(Contract);
        result.* = .{ .parameter_access = access, .self_recursive = root, .work = work, .backedges = direct.self_edges };
        try self.completed.put(self.allocator, target, result);
        return result;
    }
};

fn lowerTest(a: A, source: []const u8) !core.Module {
    var lexed = try @import("../parse/lexer.zig").lex(a, source);
    defer lexed.deinit(a);
    var names: @import("../parse/symbols.zig").Pool = .{};
    defer names.deinit(a);
    var tree = try @import("../parse/parser.zig").parse(a, source, lexed.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try @import("../check/check.zig").checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = false });
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(a, &tree, &names, &checked);
    result.unit = 1;
    return result;
}
fn named(m: *const core.Module, name: []const u8) core.BindingRef {
    for (m.bodies[1..]) |body| if (std.mem.eql(u8, m.name(body.declaration_name), name)) return .{ .unit = m.unit, .binding = body.binding };
    unreachable;
}
fn admitTest(a: A, modules: []const core.Module) !void {
    var cache: Cache = .{};
    defer cache.deinit(a);
    const target = named(&modules[0], "sort");
    const contract = (try cache.analyze(a, modules, target)).?;
    try std.testing.expect(contract.self_recursive);
    try std.testing.expectEqual(@as(usize, 2), contract.backedges);
    try std.testing.expectEqualSlices(Access, &.{ .{ .read = true, .write = true }, .{}, .{} }, contract.parameter_access);
    const scans = cache.scans;
    try std.testing.expectEqual(contract, (try cache.analyze(a, modules, target)).?);
    try std.testing.expectEqual(scans, cache.scans);
}
test "recursive source admission collects helper reads writes and both fixed-owner self edges through OOM" {
    const a = std.testing.allocator;
    var m = try lowerTest(a,
        \\const touch = func (arr: Array U32) -> (index: U32): U32 => return do:
        \\  let value = arr[index]
        \\  arr[index] := value
        \\  return value
        \\const sort = func (arr: Array U32) -> (left: U32) -> (right: U32): Unit => return do:
        \\  if @u32.lt left right:
        \\    let mid = touch arr left
        \\    sort arr left mid
        \\    sort arr (@u32.add mid 1) right
        \\  return ()
    );
    defer m.deinit(a);
    try admitTest(a, &.{m});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, admitTest, .{@as([]const core.Module, &.{m})});
}
test "recursive source admission declines changing owner correspondence hidden allocations globals and cycles" {
    const a = std.testing.allocator;
    const cases = [_][]const u8{
        \\const sort = func (arr: Array U32) -> (n: U32): Unit ! {Foreign} => return do:
        \\  if @u32.lt 0 n:
        \\    sort arr (@u32.sub n 1)
        \\  return ()
        ,
        \\const sort = func (left: Array U32) -> (right: Array U32) -> (n: U32): Unit => return do:
        \\  if @u32.lt 0 n:
        \\    sort right left (@u32.sub n 1)
        \\  return ()
        ,
        \\const helper = func (arr: Array U32): Unit => return do:
        \\  let scratch: Array U32 = #[1]
        \\  arr[0] := scratch[0]
        \\  return ()
        \\const sort = func (arr: Array U32) -> (n: U32): Unit => return do:
        \\  if @u32.lt 0 n:
        \\    helper arr
        \\    sort arr (@u32.sub n 1)
        \\  return ()
        ,
        \\const hidden: Array U32 = #[1]
        \\const sort = func (arr: Array U32) -> (n: U32): Unit => return do:
        \\  if @u32.lt 0 n:
        \\    arr[0] := hidden[0]
        \\    sort arr (@u32.sub n 1)
        \\  return ()
        ,
        \\const helper = func (arr: Array U32) -> (n: U32): Unit => return sort arr n
        \\const sort = func (arr: Array U32) -> (n: U32): Unit => return do:
        \\  if @u32.lt 0 n:
        \\    helper arr n
        \\    sort arr (@u32.sub n 1)
        \\  return ()
    };
    for (cases) |source| {
        var m = try lowerTest(a, source);
        defer m.deinit(a);
        var cache: Cache = .{};
        defer cache.deinit(a);
        try std.testing.expect(try cache.analyze(a, &.{m}, named(&m, "sort")) == null);
    }
}
test "recursive source admission preserves unused inputs and mutable owner loop versions" {
    const a = std.testing.allocator;
    var m = try lowerTest(a,
        \\const sort = func (arr: Array U32) -> (unused: Array U32) -> (n: U32): Unit => return do:
        \\  for index in 0 .. n:
        \\    arr[index] := index
        \\  if @u32.lt 0 n:
        \\    sort arr unused (@u32.sub n 1)
        \\  return ()
    );
    defer m.deinit(a);
    var cache: Cache = .{};
    defer cache.deinit(a);
    const contract = (try cache.analyze(a, &.{m}, named(&m, "sort"))).?;
    try std.testing.expectEqualSlices(Access, &.{ .{ .read = true, .write = true }, .{}, .{} }, contract.parameter_access);
}
