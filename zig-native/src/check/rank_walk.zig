//! Scope-aware bounded walks. Owned quantifier edges are numeric ranges; live
//! rigid scope nonces are never substitutes for portable binder evidence.
const std = @import("std");
const T = @import("types.zig");
const Walker = struct {
    store: *T.Store,
    rigid_scope: u32,
    free_bound: bool,
    quantifier: bool = false,
    scopes: [128]T.List = undefined,
    scope_depth: usize = 0,
    steps: usize = 0,
    excluded: []const T.Id = &.{},
    collected: ?*std.ArrayList(T.Id) = null,
    remaining: ?*usize = null,
    fn visit(self: *Walker, root: T.Id, depth: usize) T.Error!bool {
        if (root == 0) return false;
        if (depth >= 128 or self.steps >= 4096) return error.TypeLimit;
        self.steps += 1;
        if (self.remaining) |remaining| {
            if (remaining.* == 0) return error.TypeLimit;
            remaining.* -= 1;
        }
        const id = try self.store.resolve(root, 0);
        const node = self.store.node(id);
        switch (node.tag) {
            .rigid => {
                if (self.free_bound or (self.rigid_scope != 0 and node.a != self.rigid_scope)) return false;
                for (self.excluded) |excluded| if (excluded == id) return false;
                if (self.collected) |collected| {
                    for (collected.items) |previous| if (previous == id) return false;
                    try collected.append(self.store.allocator, id);
                    return false;
                }
                return true;
            },
            .bound => {
                if (!self.free_bound) return false;
                for (self.scopes[0..self.scope_depth]) |scope| {
                    for (self.store.list(scope)) |binder| if (binder == id) return false;
                }
                return true;
            },
            .forall, .existential => {
                if (self.quantifier) return true;
                if (self.scope_depth == self.scopes.len) return error.TypeLimit;
                self.scopes[self.scope_depth] = .{ .start = node.b, .len = node.c };
                self.scope_depth += 1;
                defer self.scope_depth -= 1;
                if (try self.visit(node.a, depth + 1)) return true;
                const goals = try self.store.allocator.dupe(T.Obligation, self.store.quantifierGoals(id));
                defer self.store.allocator.free(goals);
                for (goals) |goal| {
                    inline for (.{ "ty", "other", "result", "signature" }) |field| if (try self.visit(@field(goal, field), depth + 1)) return true;
                    if (goal.identity.unit == 0 and goal.identity.decl != 0 and try self.visit(goal.identity.decl, depth + 1)) return true;
                }
                return false;
            },
            .function => {
                if (try self.visit(node.a, depth + 1) or try self.visit(node.b, depth + 1)) return true;
                return self.row(node.c, depth + 1);
            },
            .demand, .provider => {
                if (try self.visit(node.a, depth + 1)) return true;
                return self.row(node.c, depth + 1);
            },
            .usage => {
                if (try self.visit(node.a, depth + 1)) return true;
                if (node.c != 0) return self.visit(node.c, depth + 1);
            },
            .scoped => {
                if (try self.visit(node.a, depth + 1)) return true;
                if (node.b == 0) return self.visit(node.c, depth + 1);
            },
            .state_provider => {
                for ([_]T.Id{ node.a, node.b, node.c }) |child| if (try self.visit(child, depth + 1)) return true;
            },
            .array, .list, .cursor, .resolver => return self.visit(node.a, depth + 1),
            .product => {
                for (0..node.b) |index| if (try self.visit(self.store.extra.items[node.a + index], depth + 1)) return true;
            },
            .record => {
                for (0..node.b) |index| if (try self.visit(self.store.recordField(node, index).ty, depth + 1)) return true;
            },
            .nominal, .projection, .instance_selection => {
                const length = self.store.nominalArguments(node).len;
                for (0..length) |index| if (try self.visit(self.store.nominalArguments(node)[index], depth + 1)) return true;
            },
            else => {},
        }
        return false;
    }
    fn row(self: *Walker, root: T.Effects.Id, depth: usize) T.Error!bool {
        const row_ = self.store.row(try self.store.resolveEffects(root, 0));
        if (row_.tail == .formal and try self.visit(row_.tail.formal, depth + 1)) return true;
        for (0..row_.labels.len) |index| {
            const label = self.store.effects.list(row_.labels)[index];
            const operation = self.store.operation(label);
            for (0..operation.arguments.len) |argument| if (try self.visit(self.store.list(operation.arguments)[argument], depth + 1)) return true;
            if (operation.instance.unit == 0 and operation.instance.decl != 0 and try self.visit(operation.instance.decl, depth + 1)) return true;
        }
        return false;
    }
};
pub fn contains(store: *T.Store, root: T.Id, rigid_scope: u32, free_bound: bool) T.Error!bool {
    var walker: Walker = .{ .store = store, .rigid_scope = rigid_scope, .free_bound = free_bound };
    return walker.visit(root, 0);
}

pub fn quantified(store: *T.Store, root: T.Id) T.Error!bool {
    var walker: Walker = .{ .store = store, .rigid_scope = 0, .free_bound = false, .quantifier = true };
    return walker.visit(root, 0);
}

pub fn containsRow(store: *T.Store, root: T.Effects.Id, rigid_scope: u32) T.Error!bool {
    var walker: Walker = .{ .store = store, .rigid_scope = rigid_scope, .free_bound = false };
    return walker.row(root, 0);
}

pub fn containsExcept(store: *T.Store, root: T.Id, scope: u32, excluded: []const T.Id, remaining: *usize) T.Error!bool {
    var walker: Walker = .{ .store = store, .rigid_scope = scope, .free_bound = false, .excluded = excluded, .remaining = remaining };
    return walker.visit(root, 0);
}
pub fn collectRigids(store: *T.Store, root: T.Id, scope: u32, collected: *std.ArrayList(T.Id), remaining: *usize) T.Error!void {
    var walker: Walker = .{ .store = store, .rigid_scope = scope, .free_bound = false, .collected = collected, .remaining = remaining };
    _ = try walker.visit(root, 0);
}
