//! Read-only relocation of an owned invocation scheme at an executable call.
//! Captured versions remain exact; only consumed declaring arrows may freshen.
const std = @import("std");
const C = @import("core.zig");
const T = @import("types.zig");
const Error = error{InvalidArtifact};
fn require(value: bool) Error!void {
    if (!value) return error.InvalidArtifact;
}
fn list(types: *const C.Types, span: T.List) Error![]const T.Id {
    try require(span.start <= types.extra.len and span.len <= types.extra.len - span.start);
    return types.list(span);
}
fn arguments(types: *const C.Types, node: T.Node) Error![]const T.Id {
    try require(node.c < types.extra.len);
    const count = types.extra[node.c];
    try require(count <= types.extra.len - node.c - 1);
    if (node.tag == .projection) try require(count < types.extra.len - node.c - 1);
    return types.nominalArguments(node);
}
pub fn labels(types: *const C.Types, row: T.Effects.Id) Error![]const T.Effects.Label {
    try require(row < types.effects.rows.len);
    const span = types.row(row).labels;
    try require(span.start <= types.effects.labels.len and span.len <= types.effects.labels.len - span.start);
    return types.rowLabels(row);
}
fn sameVersion(left: T.Node, right: T.Node) bool {
    return left.a == right.a and left.b == right.b and left.c == right.c;
}
const Pair = struct { before: T.Id, after: T.Id, opened: bool = false };
const Instance = struct { variable: T.Id, owner: T.NominalIdentity };
const RowInstance = struct { variable: u32, labels: T.Effects.List, tail: T.Effects.Tail };
pub const Relocation = struct {
    source: *const C.Module,
    target: *const C.Module,
    scheme: T.Scheme,
    endpoint: u32,
    strict_versions: bool = false,
    closing: bool = false,
    fresh_versions: [16]T.Id = undefined,
    fresh_len: usize = 0,
    fresh_pairs: [16]Pair = undefined,
    fresh_pair_len: usize = 0,
    pairs: [4096]Pair = undefined,
    len: usize = 0,
    remaining: usize = 65_536,
    instances: [32]Instance = undefined,
    instance_len: usize = 0,
    rows: [32]RowInstance = undefined,
    row_len: usize = 0,
    pub fn init(source: *const C.Module, target: *const C.Module, scheme: T.Scheme, actual: T.Id, output: T.Id, consumed: usize, endpoint: u32) Error!Relocation {
        var result: Relocation = .{ .source = source, .target = target, .scheme = scheme, .endpoint = endpoint };
        try require(scheme.generative.len <= 32 and scheme.generative.len % 2 == 0);
        const words = try list(&source.types, scheme.generative);
        var arrow = scheme.root;
        for (0..consumed) |_| {
            try require(arrow < source.types.nodes.len);
            const n = source.types.node(arrow);
            try require(n.tag == .function);
            for (0..words.len / 2) |index| if (words[index * 2] == arrow) {
                try require(words[index * 2 + 1] < source.types.nodes.len);
                const selected = source.types.node(words[index * 2 + 1]);
                try require(selected.tag == .scoped and selected.b == 0 and selected.c < source.types.nodes.len);
                const term = source.types.node(selected.c);
                try require(term.tag == .instance_selection);
                const children = try arguments(&source.types, term);
                try require(children.len == 3 and result.fresh_len < result.fresh_versions.len);
                try require(children[2] < source.types.nodes.len and source.types.node(children[2]).tag == .instance_version);
                result.fresh_versions[result.fresh_len] = children[2];
                result.fresh_len += 1;
            };
            arrow = n.b;
        }
        try result.tyOpened(scheme.root, actual, 0, true);
        // The callee edge owns instantiation; the result edge owns evaluated
        // versions. Retain variable correspondence while relocating its result.
        var kept: usize = 0;
        for (result.pairs[0..result.len]) |pair| if (source.types.node(pair.before).tag == .variable) {
            result.pairs[kept] = pair;
            kept += 1;
        };
        result.len = kept;
        result.strict_versions = true;
        try result.tyOpened(arrow, output, 0, true);
        return result;
    }
    pub fn applications(self: *Relocation, id: C.Id) Error!void {
        try require(id != 0 and id < self.target.nodes.len);
        var chain: [16]C.Id = undefined;
        var count: usize = 0;
        var callee = id;
        while (self.target.node(callee).tag == .apply) {
            try require(count < chain.len);
            chain[count] = callee;
            count += 1;
            callee = self.target.node(callee).a;
            try require(callee != 0 and callee < self.target.nodes.len);
        }
        var arrow = self.scheme.root;
        for (0..count) |index| {
            const function = self.source.types.node(arrow);
            try require(function.tag == .function);
            arrow = function.b;
            try self.tyOpened(arrow, self.target.node(chain[count - index - 1]).ty, 0, true);
        }
    }
    pub fn invoked(module: *const C.Module, variables: T.List, before: T.Id, after: T.Id, versions: []const T.Id, endpoint: u32) Error!void {
        var relation: Relocation = .{ .source = module, .target = module, .scheme = .{ .root = before, .variables = variables }, .endpoint = endpoint, .strict_versions = true };
        try require(versions.len <= relation.fresh_versions.len);
        for (versions) |version| try require(version < module.types.nodes.len and module.types.node(version).tag == .instance_version);
        @memcpy(relation.fresh_versions[0..versions.len], versions);
        relation.fresh_len = versions.len;
        try relation.ty(before, after, 0);
    }
    pub fn generalized(module: *const C.Module, scheme: T.Scheme, raw: T.Id) Error!void {
        var relation: Relocation = .{ .source = module, .target = module, .scheme = scheme, .endpoint = 0, .strict_versions = true, .closing = true };
        for (try list(&module.types, scheme.closed_rows)) |variable| try require(try relation.safeClosing(raw, variable, 0));
        try relation.tyOpened(raw, scheme.root, 0, true);
    }
    fn hasRow(self: *Relocation, root: T.Id, variable: u32, depth: usize) Error!bool {
        try require(depth < 128 and self.remaining != 0 and root < self.source.types.nodes.len);
        self.remaining -= 1;
        const node = self.source.types.node(root);
        switch (node.tag) {
            .function, .demand, .provider => {
                try require(node.c < self.source.types.effects.rows.len);
                const row_ = self.source.types.row(node.c);
                if (row_.tail == .variable and row_.tail.variable == variable) return true;
                for (try labels(&self.source.types, node.c)) |label| {
                    try require(label < self.source.types.operations.len);
                    const operation = self.source.types.operation(label);
                    if (operation.instance.unit == 0 and operation.instance.decl != 0 and try self.hasRow(operation.instance.decl, variable, depth + 1)) return true;
                    for (try list(&self.source.types, operation.arguments)) |argument| if (try self.hasRow(argument, variable, depth + 1)) return true;
                }
                if (try self.hasRow(node.a, variable, depth + 1)) return true;
                if (node.tag == .function) return self.hasRow(node.b, variable, depth + 1);
            },
            .array, .list, .cursor, .resolver => return self.hasRow(node.a, variable, depth + 1),
            .usage => {
                if (try self.hasRow(node.a, variable, depth + 1)) return true;
                if (node.c != 0) return self.hasRow(node.c, variable, depth + 1);
            },
            .state_provider => return try self.hasRow(node.a, variable, depth + 1) or try self.hasRow(node.b, variable, depth + 1) or try self.hasRow(node.c, variable, depth + 1),
            .scoped => {
                if (try self.hasRow(node.a, variable, depth + 1)) return true;
                if (node.b == 0) return self.hasRow(node.c, variable, depth + 1);
            },
            .product => for (try list(&self.source.types, .{ .start = node.a, .len = node.b })) |child| {
                if (try self.hasRow(child, variable, depth + 1)) return true;
            },
            .record => {
                try require(node.a <= self.source.types.extra.len and node.b <= (self.source.types.extra.len - node.a) / 2);
                for (0..node.b) |index| if (try self.hasRow(self.source.types.recordField(node, index).ty, variable, depth + 1)) return true;
            },
            .nominal, .projection, .instance_selection => for (try arguments(&self.source.types, node)) |child| {
                if (try self.hasRow(child, variable, depth + 1)) return true;
            },
            .forall, .existential, .bound, .rigid, .absent => return error.InvalidArtifact,
            else => {},
        }
        return false;
    }
    fn safeClosing(self: *Relocation, root: T.Id, variable: u32, depth: usize) Error!bool {
        try require(depth < 128 and self.remaining != 0 and root < self.source.types.nodes.len);
        self.remaining -= 1;
        const node = self.source.types.node(root);
        switch (node.tag) {
            .function => {
                if (try self.hasRow(node.a, variable, depth + 1)) return false;
                try require(node.c < self.source.types.effects.rows.len);
                const tail = self.source.types.row(node.c).tail;
                if (tail == .variable and tail.variable == variable and try self.hasRow(node.b, variable, depth + 1)) return false;
                return self.safeClosing(node.b, variable, depth + 1);
            },
            .provider => return !try self.hasRow(node.a, variable, depth + 1),
            .array, .list, .cursor, .usage => return self.safeClosing(node.a, variable, depth + 1),
            .product => for (try list(&self.source.types, .{ .start = node.a, .len = node.b })) |child| {
                if (!try self.safeClosing(child, variable, depth + 1)) return false;
            },
            .record => {
                try require(node.a <= self.source.types.extra.len and node.b <= (self.source.types.extra.len - node.a) / 2);
                for (0..node.b) |index| if (!try self.safeClosing(self.source.types.recordField(node, index).ty, variable, depth + 1)) return false;
            },
            else => return !try self.hasRow(root, variable, depth + 1),
        }
        return true;
    }
    pub fn get(self: *const Relocation, before: T.Id) ?T.Id {
        for (self.pairs[0..self.len]) |pair| if (pair.before == before) return pair.after;
        return null;
    }
    fn ownedVariable(self: *const Relocation, id: T.Id) Error!bool {
        for (try list(&self.source.types, self.scheme.variables)) |variable| if (variable == id) return true;
        return false;
    }
    fn instance(self: *Relocation, variable: T.Id, actual: T.NominalIdentity) Error!void {
        if (!try self.ownedVariable(variable)) {
            try require(self.source == self.target and actual.unit == 0 and actual.decl == variable);
            return;
        }
        if (actual.unit == 0) {
            try require(actual.decl < self.target.types.nodes.len);
            const node = self.target.types.node(actual.decl);
            try require(node.tag == .variable or node.tag == .instance_selection);
        } else try require(actual.decl != 0);
        if (self.get(variable)) |mapped| {
            try require(actual.unit == 0);
            try require(@import("rank_equal.zig").equal(&self.target.types, mapped, actual.decl, true) catch false);
        }
        for (self.instances[0..self.instance_len]) |prior| if (prior.variable == variable) {
            if (prior.owner.unit == 0 and actual.unit == 0) {
                try require(@import("rank_equal.zig").equal(&self.target.types, prior.owner.decl, actual.decl, true) catch false);
            } else try require(std.meta.eql(prior.owner, actual));
            return;
        };
        try require(self.instance_len < self.instances.len);
        self.instances[self.instance_len] = .{ .variable = variable, .owner = actual };
        self.instance_len += 1;
    }
    fn freshVersion(self: *Relocation, before: T.Id, after: T.Id) Error!void {
        const source = self.source.types.node(before);
        const target = self.target.types.node(after);
        for (self.fresh_pairs[0..self.fresh_pair_len]) |pair| {
            const same_source = sameVersion(source, self.source.types.node(pair.before));
            const same_target = sameVersion(target, self.target.types.node(pair.after));
            if (same_source) {
                try require(same_target);
                return;
            }
            try require(!same_target);
        }
        try require(self.fresh_pair_len < self.fresh_pairs.len);
        self.fresh_pairs[self.fresh_pair_len] = .{ .before = before, .after = after };
        self.fresh_pair_len += 1;
    }
    fn ty(self: *Relocation, before: T.Id, after: T.Id, depth: usize) Error!void {
        return self.tyOpened(before, after, depth, false);
    }
    fn tyOpened(self: *Relocation, before: T.Id, after: T.Id, depth: usize, opened: bool) Error!void {
        try require(depth < 128 and self.remaining != 0 and before < self.source.types.nodes.len and after < self.target.types.nodes.len);
        self.remaining -= 1;
        const source_variable = self.source.types.node(before).tag == .variable;
        for (self.pairs[0..self.len]) |pair| if (pair.before == before and (source_variable or pair.opened == opened)) {
            try require(@import("rank_equal.zig").equal(&self.target.types, pair.after, after, true) catch false);
            return;
        };
        try require(self.len < self.pairs.len);
        self.pairs[self.len] = .{ .before = before, .after = after, .opened = opened };
        self.len += 1;
        const a = self.source.types.node(before);
        const b = self.target.types.node(after);
        if (a.tag == .variable) {
            if (self.closing) {
                try require(before == after);
                return;
            }
            if (!try self.ownedVariable(before)) {
                try require(self.source == self.target and before == after);
                return;
            }
            for (self.instances[0..self.instance_len]) |prior| if (prior.variable == before) {
                try require(prior.owner.unit == 0);
                try require(@import("rank_equal.zig").equal(&self.target.types, prior.owner.decl, after, true) catch false);
            };
            return;
        }
        try require(a.tag == b.tag);
        switch (a.tag) {
            .function => {
                try self.ty(a.a, b.a, depth + 1);
                try self.tyOpened(a.b, b.b, depth + 1, opened);
                try self.rowOpened(a.c, b.c, depth + 1, opened);
            },
            .demand, .provider => {
                try self.ty(a.a, b.a, depth + 1);
                try self.rowOpened(a.c, b.c, depth + 1, opened and a.tag == .provider);
            },
            .array, .list, .cursor, .resolver => try self.tyOpened(a.a, b.a, depth + 1, opened and a.tag != .resolver),
            .state_provider => {
                try self.ty(a.a, b.a, depth + 1);
                try self.ty(a.b, b.b, depth + 1);
                try self.ty(a.c, b.c, depth + 1);
            },
            .usage => {
                try require(a.b == b.b and (a.c == 0) == (b.c == 0));
                try self.tyOpened(a.a, b.a, depth + 1, opened);
                if (a.c != 0) try self.ty(a.c, b.c, depth + 1);
            },
            .scoped => {
                try self.ty(a.a, b.a, depth + 1);
                if (a.b == 0) {
                    try require(a.c < self.source.types.nodes.len);
                    if (self.source.types.node(a.c).tag == .variable and !self.closing) {
                        try self.instance(a.c, .{ .unit = b.b, .decl = b.c });
                    } else {
                        try require(b.b == 0);
                        try self.ty(a.c, b.c, depth + 1);
                    }
                } else try require(a.b == b.b and a.c == b.c);
            },
            .product => {
                try require(a.b == b.b);
                for (try list(&self.source.types, .{ .start = a.a, .len = a.b }), try list(&self.target.types, .{ .start = b.a, .len = b.b })) |left, right| try self.tyOpened(left, right, depth + 1, opened);
            },
            .record => {
                try require(a.b == b.b and a.a <= self.source.types.extra.len and a.b <= (self.source.types.extra.len - a.a) / 2 and b.a <= self.target.types.extra.len and b.b <= (self.target.types.extra.len - b.a) / 2);
                for (0..a.b) |index| {
                    const field = self.source.types.recordField(a, index);
                    const other = for (0..b.b) |slot| {
                        const candidate = self.target.types.recordField(b, slot);
                        if (candidate.name == field.name) break candidate;
                    } else return error.InvalidArtifact;
                    try self.tyOpened(field.ty, other.ty, depth + 1, opened);
                }
            },
            .nominal, .projection, .instance_selection => {
                try require(a.a == b.a and a.b == b.b);
                const left = try arguments(&self.source.types, a);
                const right = try arguments(&self.target.types, b);
                if (a.tag == .projection) try require(self.source.types.projectionMember(a) == self.target.types.projectionMember(b));
                try require(left.len == right.len);
                for (left, right) |l, r| try self.ty(l, r, depth + 1);
            },
            .instance_version => {
                for (self.fresh_versions[0..self.fresh_len]) |version| if (sameVersion(self.source.types.node(version), a)) {
                    if (!self.strict_versions and a.a == b.a and a.b == b.b and a.c == b.c) return;
                    try require(b.a == self.target.unit and b.b == self.endpoint and b.c < 16);
                    try self.freshVersion(before, after);
                    return;
                };
                try require(a.a == b.a and a.b == b.b and a.c == b.c);
            },
            .forall, .existential, .bound, .rigid, .absent => return error.InvalidArtifact,
            else => try require(a.a == b.a and a.b == b.b and a.c == b.c),
        }
    }
    fn row(self: *Relocation, before: T.Effects.Id, after: T.Effects.Id, depth: usize) Error!void {
        return self.rowOpened(before, after, depth, false);
    }
    fn rowOpened(self: *Relocation, before: T.Effects.Id, after: T.Effects.Id, depth: usize, opened: bool) Error!void {
        const left = try labels(&self.source.types, before);
        const right = try labels(&self.target.types, after);
        const source = self.source.types.row(before);
        var variable: ?u32 = null;
        if (source.tail == .variable) {
            for (try list(&self.source.types, self.scheme.row_variables)) |owned| if (owned == source.tail.variable) {
                variable = owned;
                break;
            };
        }
        if (self.closing) {
            try require(left.len == right.len);
            const target = self.target.types.row(after);
            if (!std.meta.eql(source.tail, target.tail)) {
                try require(opened and source.tail == .variable and target.tail == .closed);
                var owned = false;
                for (try list(&self.source.types, self.scheme.closed_rows)) |closed| if (closed == source.tail.variable) {
                    owned = true;
                    break;
                };
                try require(owned);
            }
        } else if (variable) |owned| {
            try require(right.len >= left.len);
            const target = self.target.types.row(after);
            const remainder: T.Effects.List = .{ .start = target.labels.start + @as(u32, @intCast(left.len)), .len = @intCast(right.len - left.len) };
            var matched = false;
            for (self.rows[0..self.row_len]) |prior| if (prior.variable == owned) {
                try require(prior.labels.len == remainder.len and std.meta.eql(prior.tail, target.tail));
                for (self.target.types.effects.labels[prior.labels.start..][0..prior.labels.len], right[left.len..]) |a, b| try require(@import("rank_equal.zig").operationEqual(&self.target.types, a, b, true) catch false);
                matched = true;
                break;
            };
            if (!matched) {
                try require(self.row_len < self.rows.len);
                self.rows[self.row_len] = .{ .variable = owned, .labels = remainder, .tail = target.tail };
                self.row_len += 1;
            }
        } else if (opened and source.tail == .closed) {
            // Source instantiation opens exactly these covariant rows before
            // ambient inference. Their explicit operation prefix stays exact.
            try require(right.len >= left.len);
        } else {
            try require(left.len == right.len);
            const target = self.target.types.row(after);
            if (source.tail != .closed) try require(self.source == self.target);
            try require(std.meta.eql(source.tail, target.tail));
        }
        for (left, right[0..left.len]) |l, r| {
            try require(l < self.source.types.operations.len and r < self.target.types.operations.len);
            const a = self.source.types.operation(l);
            const b = self.target.types.operation(r);
            try require(std.meta.eql(a.identity, b.identity) and a.arguments.len == b.arguments.len);
            if (a.instance.unit == 0 and a.instance.decl != 0) {
                try require(a.instance.decl < self.source.types.nodes.len and b.instance.decl != 0);
                if (self.source.types.node(a.instance.decl).tag == .variable and !self.closing) {
                    try self.instance(a.instance.decl, b.instance);
                } else {
                    try require(b.instance.unit == 0);
                    try self.ty(a.instance.decl, b.instance.decl, depth + 1);
                }
            } else try require(std.meta.eql(a.instance, b.instance));
            for (try list(&self.source.types, a.arguments), try list(&self.target.types, b.arguments)) |lty, rty| try self.ty(lty, rty, depth + 1);
        }
    }
};

const TestRelocation = struct {
    const source_nodes = [_]T.Node{
        .{ .tag = .absent },                  .{ .tag = .unit },                              .{ .tag = .boolean },                           .{ .tag = .u32 },                                                   .{ .tag = .f32 },                             .{ .tag = .never },
        .{ .tag = .variable, .a = 0 },        .{ .tag = .variable, .a = 1 },                  .{ .tag = .nominal, .a = 1, .b = 9, .c = 0 },   .{ .tag = .scoped, .a = 8, .c = 7 },                                .{ .tag = .scoped, .a = 8, .b = 1, .c = 40 }, .{ .tag = .nominal, .a = 1, .b = 10, .c = 0 },
        .{ .tag = .scoped, .a = 11, .c = 7 }, .{ .tag = .instance_version, .a = 1, .b = 77 }, .{ .tag = .instance_version, .a = 1, .b = 78 }, .{ .tag = .instance_version, .a = 1, .b = 77, .closed_height = 3 },
    };
    const target_nodes = [_]T.Node{
        .{ .tag = .absent },                             .{ .tag = .unit },                                       .{ .tag = .boolean },                                                                       .{ .tag = .u32 },                               .{ .tag = .f32 },                              .{ .tag = .never },
        .{ .tag = .nominal, .a = 1, .b = 9, .c = 0 },    .{ .tag = .scoped, .a = 6, .b = 1, .c = 101 },           .{ .tag = .scoped, .a = 6, .b = 1, .c = 102 },                                              .{ .tag = .nominal, .a = 1, .b = 10, .c = 0 },  .{ .tag = .scoped, .a = 9, .b = 1, .c = 101 }, .{ .tag = .scoped, .a = 9, .b = 1, .c = 102 },
        .{ .tag = .scoped, .a = 6, .b = 1, .c = 40 },    .{ .tag = .scoped, .a = 6, .b = 2, .c = 40 },            .{ .tag = .instance_version, .a = 1, .b = 77, .closed_height = 2, .closed_generation = 3 }, .{ .tag = .instance_version, .a = 1, .b = 78 }, .{ .tag = .variable, .a = 0 },                 .{ .tag = .variable, .a = 1 },
        .{ .tag = .instance_version, .a = 1, .b = 300 }, .{ .tag = .instance_version, .a = 1, .b = 300, .c = 1 },
    };
    const source_extra = [_]T.Id{ 1, 6, 6, 7 };
    const target_extra = [_]T.Id{ 1, T.u32_type };
    const source_operations = [_]T.Operation{.{ .identity = .{ .unit = 1, .decl = 11 }, .instance = .{ .unit = 0, .decl = 7 } }};
    const target_operations = [_]T.Operation{
        .{ .identity = .{ .unit = 1, .decl = 11 }, .instance = .{ .unit = 1, .decl = 101 } },
        .{ .identity = .{ .unit = 1, .decl = 11 }, .instance = .{ .unit = 1, .decl = 102 } },
    };
    const rows = [_]T.Effects.Row{ .{}, .{ .labels = .{ .len = 1 } }, .{ .labels = .{ .start = 1, .len = 1 } } };
    const row_labels = [_]T.Effects.Label{ 0, 1 };
    fn module(types: C.Types) C.Module {
        return .{ .unit = 1, .types = types, .nodes = &.{}, .spans = &.{}, .extra = &.{}, .bindings = &.{}, .bodies = &.{}, .parameters = &.{}, .references = &.{}, .calls = &.{}, .merges = &.{}, .merge_ranges = &.{}, .names = &.{}, .obligations = &.{}, .diagnostics = &.{}, .body_lowerings = 0 };
    }
    fn source() C.Module {
        return module(.{ .nodes = @constCast(&source_nodes), .extra = @constCast(&source_extra), .operations = @constCast(&source_operations), .effects = .{ .rows = @constCast(rows[0..2]), .labels = @constCast(row_labels[0..1]) } });
    }
    fn target() C.Module {
        return module(.{ .nodes = @constCast(&target_nodes), .extra = @constCast(&target_extra), .operations = @constCast(&target_operations), .effects = .{ .rows = @constCast(&rows), .labels = @constCast(&row_labels) } });
    }
    fn relocation(source_: *const C.Module, target_: *const C.Module) Relocation {
        return .{ .source = source_, .target = target_, .scheme = .{ .root = 9, .variables = .{ .start = 2, .len = 2 } }, .endpoint = 300 };
    }
};

test "quantified scoped relocation preserves owner correspondence across descriptors and rows" {
    const source = TestRelocation.source();
    const target = TestRelocation.target();
    var relation = TestRelocation.relocation(&source, &target);
    try relation.ty(9, 7, 0);
    try relation.ty(12, 10, 0);
    try relation.row(1, 1, 0);
    try std.testing.expectError(error.InvalidArtifact, relation.ty(12, 11, 0));
    relation = TestRelocation.relocation(&source, &target);
    try relation.ty(9, 7, 0);
    try std.testing.expectError(error.InvalidArtifact, relation.ty(12, 11, 0));
    relation = TestRelocation.relocation(&source, &target);
    try relation.ty(9, 7, 0);
    try std.testing.expectError(error.InvalidArtifact, relation.row(1, 2, 0));
    relation = TestRelocation.relocation(&source, &target);
    relation.scheme.variables.len = 1;
    try std.testing.expectError(error.InvalidArtifact, relation.ty(9, 7, 0));
    relation = TestRelocation.relocation(&source, &target);
    try relation.ty(7, T.u32_type, 0);
    try std.testing.expectError(error.InvalidArtifact, relation.ty(9, 7, 0));
    relation = TestRelocation.relocation(&source, &target);
    try relation.ty(9, 7, 0);
    try std.testing.expectError(error.InvalidArtifact, relation.ty(7, T.u32_type, 0));
}

test "captured scoped relocation preserves concrete owners and invocation versions" {
    const source = TestRelocation.source();
    const target = TestRelocation.target();
    var relation = TestRelocation.relocation(&source, &target);
    try relation.ty(10, 12, 0);
    try relation.ty(13, 14, 0);
    try std.testing.expectError(error.InvalidArtifact, relation.ty(13, 15, 0));
    relation = TestRelocation.relocation(&source, &target);
    try std.testing.expectError(error.InvalidArtifact, relation.ty(10, 13, 0));
    relation = TestRelocation.relocation(&source, &target);
    try std.testing.expectError(error.InvalidArtifact, relation.ty(10, 7, 0));
}

test "symbolic scope-owner relocation shares only the same unresolved instance term" {
    const source = TestRelocation.source();
    const target = TestRelocation.target();
    var relation = TestRelocation.relocation(&source, &target);
    try relation.instance(7, .{ .unit = 0, .decl = 16 });
    try relation.ty(7, 16, 0);
    try std.testing.expectError(error.InvalidArtifact, relation.ty(7, 17, 0));
    relation = TestRelocation.relocation(&source, &target);
    try relation.ty(7, 16, 0);
    try relation.instance(7, .{ .unit = 0, .decl = 16 });
    try std.testing.expectError(error.InvalidArtifact, relation.instance(7, .{ .unit = 0, .decl = 17 }));
}

test "fresh invocation relocation preserves distinct slots and semantic source aliases" {
    const source = TestRelocation.source();
    const target = TestRelocation.target();
    var relation = TestRelocation.relocation(&source, &target);
    relation.strict_versions = true;
    relation.fresh_versions[0] = 13;
    relation.fresh_versions[1] = 14;
    relation.fresh_len = 2;
    try relation.ty(13, 18, 0);
    try relation.ty(14, 19, 0);
    try relation.ty(15, 18, 0);
    relation = TestRelocation.relocation(&source, &target);
    relation.strict_versions = true;
    relation.fresh_versions[0] = 13;
    relation.fresh_versions[1] = 14;
    relation.fresh_len = 2;
    try relation.ty(13, 18, 0);
    try std.testing.expectError(error.InvalidArtifact, relation.ty(14, 18, 0));
    try std.testing.expectError(error.InvalidArtifact, relation.ty(15, 19, 0));
}

test "input invocation relocates owned rows and only covariant ambient extensions" {
    const prefix = TestRelocation.source_nodes[0..6].*;
    var source_nodes = prefix ++ [_]T.Node{
        .{ .tag = .function, .a = T.unit, .b = T.u32_type, .c = 1 },
        .{ .tag = .function, .a = 6, .b = T.u32_type, .c = 1 },
        .{ .tag = .function, .a = T.unit, .b = 7 },
    };
    var target_nodes = source_nodes;
    target_nodes[6].c = 2;
    target_nodes[7].c = 2;
    target_nodes[8].c = 2;
    var extra = [_]T.Id{0};
    var operations = [_]T.Operation{.{ .identity = .{ .unit = 1, .decl = 11 } }};
    var row_labels = [_]T.Effects.Label{0};
    var rows = [_]T.Effects.Row{
        .{},
        .{ .tail = .{ .variable = 0 } },
        .{ .labels = .{ .len = 1 }, .tail = .{ .variable = 8 } },
        .{ .labels = .{ .len = 1 }, .tail = .{ .variable = 9 } },
        .{ .labels = .{ .len = 1 } },
    };
    var source = TestRelocation.module(.{ .nodes = &source_nodes, .extra = &extra, .operations = &operations, .effects = .{ .rows = &rows, .labels = &row_labels } });
    const target = TestRelocation.module(.{ .nodes = &target_nodes, .extra = &extra, .operations = &operations, .effects = .{ .rows = &rows, .labels = &row_labels } });
    const scheme: T.Scheme = .{ .root = 8, .row_variables = .{ .len = 1 } };
    _ = try Relocation.init(&source, &target, scheme, 8, T.u32_type, 2, 0);
    target_nodes[7].c = 3;
    try std.testing.expectError(error.InvalidArtifact, Relocation.init(&source, &target, scheme, 8, T.u32_type, 2, 0));
    target_nodes[7].c = 0;
    try std.testing.expectError(error.InvalidArtifact, Relocation.init(&source, &target, scheme, 8, T.u32_type, 2, 0));
    target_nodes[7].c = 2;
    target_nodes[6].c = 0;
    try std.testing.expectError(error.InvalidArtifact, Relocation.init(&source, &target, scheme, 8, T.u32_type, 2, 0));
    target_nodes[6].c = 2;
    source_nodes[6].c = 0;
    try std.testing.expectError(error.InvalidArtifact, Relocation.init(&source, &target, scheme, 8, T.u32_type, 2, 0));
    source_nodes[6].c = 1;
    var unowned = scheme;
    unowned.row_variables = .{};
    try std.testing.expectError(error.InvalidArtifact, Relocation.init(&source, &target, unowned, 8, T.u32_type, 2, 0));
    rows[2].labels = .{};
    try std.testing.expectError(error.InvalidArtifact, Relocation.init(&source, &target, unowned, 8, T.u32_type, 2, 0));
    source_nodes[6].c = 0;
    try std.testing.expectError(error.InvalidArtifact, Relocation.init(&source, &target, scheme, 8, T.u32_type, 2, 0));
    source_nodes[6].c = 1;
    rows[2].labels = .{ .len = 1 };
    source_nodes[8].c = 4;
    target_nodes[8].c = 0;
    try std.testing.expectError(error.InvalidArtifact, Relocation.init(&source, &target, scheme, 8, T.u32_type, 2, 0));
}

test "input invocation never reuses a covariant proof at a callback input" {
    var nodes = TestRelocation.source_nodes[0..6].* ++ [_]T.Node{
        .{ .tag = .function, .a = T.unit, .b = T.u32_type },
        .{ .tag = .function, .a = 6, .b = T.u32_type },
        .{ .tag = .product, .a = 0, .b = 2 },
        .{ .tag = .function, .a = T.unit, .b = T.u32_type, .c = 2 },
        .{ .tag = .function, .a = 9, .b = T.u32_type },
        .{ .tag = .product, .a = 2, .b = 2 },
    };
    var extra = [_]T.Id{ 6, 7, 9, 10, 11 };
    var rows = [_]T.Effects.Row{ .{}, .{ .tail = .{ .variable = 11 } }, .{ .tail = .{ .variable = 8 } } };
    const module = TestRelocation.module(.{ .nodes = &nodes, .extra = &extra, .effects = .{ .rows = &rows, .labels = &.{} } });
    var scheme: T.Scheme = .{ .root = 8 };
    try std.testing.expectError(error.InvalidArtifact, Relocation.init(&module, &module, scheme, 11, 11, 0, 0));
    // A closing certificate grants covariance only; it cannot rewrite a
    // captured callback input, even when the same node was visited earlier.
    nodes[6].c = 1;
    nodes[9].c = 0;
    scheme.root = 11;
    scheme.closed_rows = .{ .start = 4, .len = 1 };
    try std.testing.expectError(error.InvalidArtifact, Relocation.generalized(&module, scheme, 8));
    scheme.root = 9;
    try Relocation.generalized(&module, scheme, 6);
    scheme.closed_rows = .{};
    try std.testing.expectError(error.InvalidArtifact, Relocation.generalized(&module, scheme, 6));
    scheme.closed_rows = .{ .start = 4, .len = 1 };
    rows[1].tail = .{ .variable = 12 };
    try std.testing.expectError(error.InvalidArtifact, Relocation.generalized(&module, scheme, 6));
    rows[1].tail = .{ .variable = 11 };
    nodes[9].c = 2;
    try std.testing.expectError(error.InvalidArtifact, Relocation.generalized(&module, scheme, 6));
}
