//! Read-only alpha equality with an explicit lexical binder correspondence.
const std = @import("std");
const T = @import("types.zig");
const Frame = struct { left: T.List, right: T.List };
fn Walker(comptime Store: type) type {
    return struct {
        const Self = @This();
        store: Store,
        symbolic: bool,
        frames: [128]Frame = undefined,
        depth: usize = 0,
        steps: usize = 0,
        height: usize = 0,
        budget: ?*usize = null,
        fn work(self: *Self) T.Error!void {
            if (self.budget) |remaining| {
                if (remaining.* == 0) return error.TypeLimit;
                remaining.* -= 1;
            }
        }
        fn equal(self: *Self, left: T.Id, right: T.Id) T.Error!bool {
            if (self.steps >= 4096 or self.height >= 128) return error.TypeLimit;
            self.height += 1;
            defer self.height -= 1;
            self.steps += 1;
            try self.work();
            const a = self.store.node(left);
            const b = self.store.node(right);
            if (a.tag != b.tag) return false;
            switch (a.tag) {
                .absent => return false,
                .variable => return self.symbolic and a.a == b.a and a.b == b.b,
                .instance_version => return a.a == b.a and a.b == b.b and a.c == b.c,
                .rigid => return self.symbolic and a.a == b.a and a.b == b.b and a.c == b.c,
                .bound => {
                    var index = self.depth;
                    while (index != 0) {
                        index -= 1;
                        try self.work();
                        const frame = self.frames[index];
                        for (self.store.list(frame.left), self.store.list(frame.right)) |av, bv| {
                            try self.work();
                            if (av == left or bv == right) return av == left and bv == right;
                        }
                    }
                    return left == right;
                },
                .forall, .existential => {
                    if (a.c != b.c) return false;
                    if (self.depth == self.frames.len) return error.TypeLimit;
                    const frame: Frame = .{ .left = .{ .start = a.b, .len = a.c }, .right = .{ .start = b.b, .len = b.c } };
                    for (self.store.list(frame.left), self.store.list(frame.right)) |av, bv| {
                        try self.work();
                        const aa = self.store.node(av);
                        const bb = self.store.node(bv);
                        if (aa.tag != .bound or bb.tag != .bound or aa.b != bb.b) return false;
                    }
                    self.frames[self.depth] = frame;
                    self.depth += 1;
                    defer self.depth -= 1;
                    const left_goals = self.store.quantifierGoals(left);
                    const right_goals = self.store.quantifierGoals(right);
                    if (left_goals.len != right_goals.len) return false;
                    for (left_goals, right_goals) |left_goal, right_goal| {
                        try self.work();
                        if (!@import("quantifier_goals.zig").sameHead(left_goal, right_goal)) return false;
                        inline for (.{ "ty", "other", "result", "signature" }) |field| {
                            const left_child = @field(left_goal, field);
                            const right_child = @field(right_goal, field);
                            if ((left_child == 0) != (right_child == 0)) return false;
                            if (left_child != 0 and !try self.equal(left_child, right_child)) return false;
                        }
                    }
                    return self.equal(a.a, b.a);
                },
                .function => return try self.equal(a.a, b.a) and try self.equal(a.b, b.b) and try self.row(a.c, b.c),
                .demand, .provider => return try self.equal(a.a, b.a) and try self.row(a.c, b.c),
                .array, .list, .cursor, .resolver => return self.equal(a.a, b.a),
                .state_provider => return try self.equal(a.a, b.a) and try self.equal(a.b, b.b) and try self.equal(a.c, b.c),
                .usage => return a.b == b.b and (a.c == 0) == (b.c == 0) and try self.equal(a.a, b.a) and (a.c == 0 or try self.equal(a.c, b.c)),
                .scoped => {
                    if (a.b != b.b) return false;
                    if (a.b == 0) {
                        if (!try self.equal(a.c, b.c)) return false;
                    } else if (a.c != b.c) return false;
                    return self.equal(a.a, b.a);
                },
                .product => {
                    if (a.b != b.b) return false;
                    for (self.store.list(.{ .start = a.a, .len = a.b }), self.store.list(.{ .start = b.a, .len = b.b })) |av, bv| if (!try self.equal(av, bv)) return false;
                },
                .record => {
                    if (a.b != b.b) return false;
                    for (0..a.b) |index| {
                        const field = self.store.recordField(a, index);
                        var matched = false;
                        for (0..b.b) |other| {
                            try self.work();
                            const candidate = self.store.recordField(b, other);
                            if (field.name == candidate.name) {
                                if (!try self.equal(field.ty, candidate.ty)) return false;
                                matched = true;
                                break;
                            }
                        }
                        if (!matched) return false;
                    }
                },
                .nominal, .projection, .instance_selection => {
                    if (a.a != b.a or a.b != b.b) return false;
                    if (a.tag == .projection and self.store.projectionMember(a) != self.store.projectionMember(b)) return false;
                    const aa = self.store.nominalArguments(a);
                    const bb = self.store.nominalArguments(b);
                    if (aa.len != bb.len) return false;
                    for (aa, bb) |av, bv| if (!try self.equal(av, bv)) return false;
                },
                .type_constructor => return a.a == b.a and a.b == b.b,
                else => {},
            }
            return true;
        }
        fn operation(self: *Self, left: T.Effects.Label, right: T.Effects.Label) T.Error!bool {
            try self.work();
            const a = self.store.operation(left);
            const b = self.store.operation(right);
            if (!std.meta.eql(a.identity, b.identity) or a.instance.unit != b.instance.unit or a.arguments.len != b.arguments.len) return false;
            if (a.instance.unit == 0 and a.instance.decl != 0 and b.instance.decl != 0) {
                if (!try self.equal(a.instance.decl, b.instance.decl)) return false;
            } else if (a.instance.decl != b.instance.decl) return false;
            for (self.store.list(a.arguments), self.store.list(b.arguments)) |av, bv| if (!try self.equal(av, bv)) return false;
            return true;
        }
        fn row(self: *Self, left: T.Effects.Id, right: T.Effects.Id) T.Error!bool {
            try self.work();
            const a = self.store.effects.node(left);
            const b = self.store.effects.node(right);
            if (a.labels.len != b.labels.len or std.meta.activeTag(a.tail) != std.meta.activeTag(b.tail)) return false;
            if (a.tail == .formal) {
                if (!try self.equal(a.tail.formal, b.tail.formal)) return false;
            } else if (!std.meta.eql(a.tail, b.tail) or (!self.symbolic and a.tail != .closed)) return false;
            for (self.store.effects.list(a.labels)) |label| {
                var ac: usize = 0;
                var bc: usize = 0;
                for (self.store.effects.list(a.labels)) |other| if (try self.operation(label, other)) {
                    ac += 1;
                };
                for (self.store.effects.list(b.labels)) |other| if (try self.operation(label, other)) {
                    bc += 1;
                };
                if (ac != bc) return false;
            }
            return true;
        }
    };
}
pub fn equal(store: anytype, left: T.Id, right: T.Id, symbolic: bool) T.Error!bool {
    var walker: Walker(@TypeOf(store)) = .{ .store = store, .symbolic = symbolic };
    return walker.equal(left, right);
}
pub fn operationEqual(store: anytype, left: T.Effects.Label, right: T.Effects.Label, symbolic: bool) T.Error!bool {
    var walker: Walker(@TypeOf(store)) = .{ .store = store, .symbolic = symbolic };
    return walker.operation(left, right);
}

/// Alpha equality charged to an enclosing immutable proof's shared budget.
pub fn equalWithBudget(store: anytype, left: T.Id, right: T.Id, symbolic: bool, budget: *usize) T.Error!bool {
    var walker: Walker(@TypeOf(store)) = .{ .store = store, .symbolic = symbolic, .budget = budget };
    return walker.equal(left, right);
}
