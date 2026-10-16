//! Exact lexical goal matching for canonical associated projections.
const std = @import("std");
const E = @import("type_evidence.zig");
pub fn validate(view: E.View, id: E.Id, goal: E.Goal, remaining: *usize) E.Error!void {
    const node = view.node(id);
    if (goal.kind != .contract or goal.identity.unit != node.a or goal.identity.decl != node.b or goal.ty == 0 or goal.ty >= view.nodes.len) return error.TypeMismatch;
    const tuple = view.node(goal.ty);
    if (tuple.tag != .product or tuple.a > view.extra.len or tuple.b > view.extra.len - tuple.a) return error.TypeMismatch;
    const expected = view.children(goal.ty);
    const actual = view.children(id);
    if (expected.len != actual.len) return error.TypeMismatch;
    var proof: Comparison = .{ .view = view, .shift = view.projection(id).scope, .remaining = remaining };
    for (expected, actual) |left, right| if (!try proof.equal(left, right, 0, 0)) return error.TypeMismatch;
}
const Comparison = struct {
    view: E.View,
    shift: u32,
    remaining: *usize,
    fn step(self: *Comparison, depth: usize) E.Error!void {
        if (depth >= 128 or self.remaining.* == 0) return error.EvidenceLimit;
        self.remaining.* -= 1;
    }
    fn equal(self: *Comparison, left: E.Id, right: E.Id, local: usize, depth: usize) E.Error!bool {
        try self.step(depth);
        if (left == 0 or right == 0 or left >= self.view.nodes.len or right >= self.view.nodes.len) return error.TypeMismatch;
        const a = self.view.node(left);
        const b = self.view.node(right);
        if (a.tag != b.tag) return false;
        switch (a.tag) {
            .bound => {
                var expected = a.c;
                if (expected >= local) expected = std.math.add(u32, expected, self.shift) catch return error.EvidenceLimit;
                return a.a == b.a and a.b == b.b and expected == b.c;
            },
            .forall, .existential => {
                if (a.b != b.b) return false;
                for (self.view.children(left), self.view.children(right)) |x, y| {
                    const first = self.view.node(x);
                    const second = self.view.node(y);
                    if (first.tag != .bound or second.tag != .bound or first.a != second.a or first.b != second.b or first.c != 0 or second.c != 0) return false;
                }
                const xs = self.view.quantifierGoals(left);
                const ys = self.view.quantifierGoals(right);
                if (xs.len != ys.len) return false;
                for (xs, ys) |x, y| {
                    if (x.kind != y.kind or x.name != y.name or x.operator != y.operator or !std.meta.eql(x.identity, y.identity)) return false;
                    inline for (.{ "ty", "other", "result", "signature" }) |field| {
                        const first = @field(x, field);
                        const second = @field(y, field);
                        if ((first == 0) != (second == 0)) return false;
                        if (first != 0 and !try self.equal(first, second, local + 1, depth + 1)) return false;
                    }
                }
                return self.equal(a.a, b.a, local + 1, depth + 1);
            },
            .function => return try self.equal(a.a, b.a, local, depth + 1) and try self.equal(a.b, b.b, local, depth + 1) and try self.row(a.c, b.c, local, depth + 1),
            .usage => {
                if (a.b != b.b or (a.c == 0) != (b.c == 0) or !try self.equal(a.a, b.a, local, depth + 1)) return false;
                return a.c == 0 or try self.equal(a.c, b.c, local, depth + 1);
            },
            .demand, .provider => return try self.equal(a.a, b.a, local, depth + 1) and try self.row(a.c, b.c, local, depth + 1),
            .array, .list, .cursor, .resolver => return self.equal(a.a, b.a, local, depth + 1),
            .state_provider => return try self.equal(a.a, b.a, local, depth + 1) and try self.equal(a.b, b.b, local, depth + 1) and try self.equal(a.c, b.c, local, depth + 1),
            .projection, .nominal, .product, .record => {
                if ((a.tag == .projection or a.tag == .nominal) and (a.a != b.a or a.b != b.b)) return false;
                if (a.tag == .projection) {
                    const x = self.view.projection(left);
                    const y = self.view.projection(right);
                    var scope = x.scope;
                    if (scope >= local) scope = std.math.add(u32, scope, self.shift) catch return error.EvidenceLimit;
                    if (x.member != y.member or scope != y.scope or x.goal != y.goal) return false;
                }
                const xs = self.view.children(left);
                const ys = self.view.children(right);
                if (xs.len != ys.len) return false;
                for (xs, ys, 0..) |x, y, index| {
                    if (a.tag == .record and index % 2 == 0) {
                        if (x != y) return false;
                    } else if (!try self.equal(x, y, local, depth + 1)) return false;
                }
                return true;
            },
            .type_constructor => return a.a == b.a and a.b == b.b,
            .unit, .boolean, .u32, .f32, .never => return true,
            .absent, .scoped, .erased_proof => return error.UnresolvedType,
        }
    }
    fn row(self: *Comparison, left: E.Effects.Id, right: E.Effects.Id, local: usize, depth: usize) E.Error!bool {
        try self.step(depth);
        if (left >= self.view.effects.rows.len or right >= self.view.effects.rows.len) return error.TypeMismatch;
        const a = self.view.effects.rows[left];
        const b = self.view.effects.rows[right];
        if ((a.formal == 0) != (b.formal == 0)) return false;
        if (a.formal != 0 and !try self.equal(a.formal, b.formal, local, depth + 1)) return false;
        const xs = self.view.effects.rowLabels(left);
        const ys = self.view.effects.rowLabels(right);
        if (xs.len != ys.len or xs.len > 256) return false;
        var used: std.bit_set.Static(256) = .empty;
        for (xs) |x| {
            var found = false;
            for (ys, 0..) |y, index| {
                try self.step(depth);
                if (used.isSet(index)) continue;
                const first = self.view.effects.operation(x);
                const second = self.view.effects.operation(y);
                if (!std.meta.eql(first.identity, second.identity) or !std.meta.eql(first.instance, second.instance)) continue;
                const args = self.view.effects.operationArguments(x);
                const other = self.view.effects.operationArguments(y);
                if (args.len != other.len) continue;
                var same = true;
                for (args, other) |expected, actual| if (!try self.equal(expected, actual, local, depth + 1)) {
                    same = false;
                    break;
                };
                if (!same) continue;
                used.set(index);
                found = true;
                break;
            }
            if (!found) return false;
        }
        return true;
    }
};
