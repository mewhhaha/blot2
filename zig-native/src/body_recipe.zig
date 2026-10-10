//! Immutable visit orders over source Core. A recipe contains no inference
//! types, selected members, capture values, rows, or solved obligations. Each replay
//! executes the original region actions in its current private source scope.
const std = @import("std");
const core = @import("core.zig");
const checked = @import("check.zig");
const Allocator = std.mem.Allocator;

pub const Key = struct { owner: usize, body: core.Id, callables: bool };
pub const Recipe = struct {
    visits: std.ArrayList(core.Id) = .empty,
    has_lexical_captures: bool = false,
    pub fn deinit(self: *Recipe, allocator: Allocator) void {
        self.visits.deinit(allocator);
    }
};
const PlanError = Allocator.Error || error{PlanLimit};
const Pending = struct {
    items: std.ArrayList(core.Id) = .empty,
    limit: usize,
    fn append(self: *Pending, allocator: Allocator, id: core.Id) PlanError!void {
        if (self.items.items.len == self.limit) return error.PlanLimit;
        try self.items.append(allocator, id);
    }
    fn appendSlice(self: *Pending, allocator: Allocator, ids: []const core.Id) PlanError!void {
        // Check before allocating: a wide source list must not grow a plan's
        // temporary stack beyond its own quota before optimization declines.
        if (ids.len > self.limit - self.items.items.len) return error.PlanLimit;
        try self.items.appendSlice(allocator, ids);
    }
    fn pop(self: *Pending) ?core.Id {
        return self.items.pop();
    }
};

/// The stack order is the order used by ClosureRegion.collect. Nested closure
/// collection remains a separate replay, with its own seen set and contextual
/// defer-members flag. Only apply/resolver bodies that were pushed on this
/// logical walk enter this recipe.
fn children(work: *Pending, allocator: Allocator, module: *const core.Module, id: core.Id, callables: bool) PlanError!void {
    const n = module.node(id);
    if (callables and n.tag == .apply and module.node(n.a).tag == .closure) try work.append(allocator, module.closure(n.a).body);
    switch (n.tag) {
        .scalar, .associated, .logical, .record_merge, .type_same, .apply, .effect_provider, .handle => try work.appendSlice(allocator, &.{ n.a, n.b }),
        .if_value, .if_stmt, .state_provider => try work.appendSlice(allocator, &.{ n.a, n.b, n.c }),
        .block, .suite, .product, .record, .array, .array_op, .call => try work.appendSlice(allocator, module.children(id)),
        .bind => try work.append(allocator, n.b),
        .return_, .project, .result_associated, .force => try work.append(allocator, n.a),
        .construct => try work.append(allocator, n.b),
        .pattern_bind => try work.appendSlice(allocator, &.{ n.b, n.c }),
        .match => {
            try work.appendSlice(allocator, module.matchInputs(id));
            for (module.matchArms(id)) |arm| try work.appendSlice(allocator, &.{ arm.guard, arm.body });
        },
        .loop => {
            const iteration = module.loopInfo(id);
            try work.appendSlice(allocator, &.{ iteration.first, iteration.end, iteration.body });
        },
        .break_ => try work.appendSlice(allocator, module.breakValues(id)),
        .resolver_op => {
            const metadata = module.resolverInfo(id);
            try work.append(allocator, metadata.resolver);
            try work.appendSlice(allocator, module.resolverArguments(id));
            if (callables and (metadata.operation == .run or metadata.operation == .bind or metadata.operation == .iterate)) for (module.resolverArguments(id)) |argument| {
                if (module.node(argument).tag == .closure) try work.append(allocator, module.closure(argument).body);
            };
        },
        .update => {
            const update = module.updateInfo(id);
            try work.appendSlice(allocator, &.{ update.root, update.value });
            for (module.updateSelectors(id)) |selector| if (selector.kind == .index) try work.append(allocator, selector.index);
        },
        .effect_reflection => {
            const kind: checked.ReflectionKind = @fromBackingInt(@intCast(n.a));
            if (kind == .count or kind == .has or kind == .same) try work.append(allocator, n.b);
            if (n.c != 0) try work.append(allocator, n.c);
        },
        .computation => try work.append(allocator, n.a),
        .request_decision => try work.appendSlice(allocator, &.{ n.b, n.c }),
        .request_loop => {
            const metadata = module.requestLoopInfo(id);
            try work.appendSlice(allocator, &.{ metadata.computation, metadata.completion_body });
            for (module.requestArms(id)) |arm| try work.append(allocator, arm.callback);
        },
        .closure, .operation_value, .suspend_, .constant, .reference, .constructor_function, .primitive_function, .panic, .type_constructor, .invalid => {},
    }
}

pub const Cache = struct {
    recipes: std.AutoHashMapUnmanaged(Key, *Recipe) = .empty,
    requests: usize = 0,
    builds: usize = 0,
    planned_visits: usize = 0,
    replayed_visits: usize = 0,
    declined_walks: usize = 0,

    pub fn deinit(self: *Cache, allocator: Allocator) void {
        var entries = self.recipes.valueIterator();
        while (entries.next()) |entry| {
            entry.*.deinit(allocator);
            allocator.destroy(entry.*);
        }
        self.recipes.deinit(allocator);
    }
    fn build(recipe: *Recipe, allocator: Allocator, module: *const core.Module, key: Key, limit: usize) PlanError!void {
        var work: Pending = .{ .limit = limit };
        defer work.items.deinit(allocator);
        var seen: std.AutoHashMapUnmanaged(core.Id, void) = .empty;
        defer seen.deinit(allocator);
        try work.append(allocator, key.body);
        while (work.pop()) |id| {
            if (id == 0) continue;
            if (seen.contains(id)) continue;
            if (recipe.visits.items.len == limit) return error.PlanLimit;
            try seen.put(allocator, id, {});
            try recipe.visits.append(allocator, id);
            const tag = module.node(id).tag;
            if ((tag == .closure or tag == .suspend_) and module.closures[module.node(id).a].captures.len != 0) recipe.has_lexical_captures = true;
            // No later node can execute after this source error. Avoid reading
            // unreachable malformed descendants of intentionally invalid Core.
            if (module.node(id).tag == .invalid) break;
            try children(&work, allocator, module, id, key.callables);
        }
    }
    pub fn get(self: *Cache, allocator: Allocator, units: []const core.Module, key: Key, max_values: usize) Allocator.Error!?*const Recipe {
        self.requests += 1;
        if (self.recipes.get(key)) |known| {
            if (known.visits.items.len <= max_values) return known;
            self.declined_walks += 1;
            return null;
        }
        const limit = @min(max_values, 4096);
        if (limit == 0) {
            self.declined_walks += 1;
            return null;
        }
        const recipe = try allocator.create(Recipe);
        recipe.* = .{};
        errdefer {
            recipe.deinit(allocator);
            allocator.destroy(recipe);
        }
        build(recipe, allocator, &units[key.owner], key, limit) catch |err| switch (err) {
            error.PlanLimit => {
                recipe.deinit(allocator);
                allocator.destroy(recipe);
                self.declined_walks += 1;
                return null;
            },
            error.OutOfMemory => return error.OutOfMemory,
        };
        try self.recipes.put(allocator, key, recipe);
        self.builds += 1;
        self.planned_visits += recipe.visits.items.len;
        return recipe;
    }
};

/// The reference walker remains an explicit owned Session option for semantic
/// and allocation comparisons. Recipe replays never switch to it mid-region.
pub const Walk = struct {
    recipe: ?*const Recipe = null,
    index: usize = 0,
    count: usize = 0,
    work: std.ArrayList(core.Id) = .empty,
    seen: std.AutoHashMapUnmanaged(core.Id, void) = .empty,

    pub fn deinit(self: *Walk, allocator: Allocator) void {
        self.work.deinit(allocator);
        self.seen.deinit(allocator);
    }
    pub fn append(self: *Walk, allocator: Allocator, id: core.Id) Allocator.Error!void {
        if (self.recipe == null) try self.work.append(allocator, id);
    }
    pub fn appendSlice(self: *Walk, allocator: Allocator, ids: []const core.Id) Allocator.Error!void {
        if (self.recipe == null) try self.work.appendSlice(allocator, ids);
    }
    pub fn next(self: *Walk, allocator: Allocator) Allocator.Error!?core.Id {
        if (self.recipe) |recipe| {
            if (self.index == recipe.visits.items.len) return null;
            const id = recipe.visits.items[self.index];
            self.index += 1;
            self.count += 1;
            return id;
        }
        while (self.work.pop()) |id| {
            if (id == 0) continue;
            const entry = try self.seen.getOrPut(allocator, id);
            if (entry.found_existing) continue;
            self.count += 1;
            return id;
        }
        return null;
    }
};
