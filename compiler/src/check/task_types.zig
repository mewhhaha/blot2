//! Compiler-owned task constructors. Source datatypes cannot manufacture these
//! identities; the scoped argument carries the exact lexical group owner.
const std = @import("std");
const T = @import("types.zig");
pub const group: T.NominalIdentity = .{ .unit = std.math.maxInt(u32), .decl = 16 };
pub const handle: T.NominalIdentity = .{ .unit = std.math.maxInt(u32), .decl = 17 };
pub const view: T.NominalIdentity = .{ .unit = std.math.maxInt(u32), .decl = 18 };
pub fn isIdentity(unit: u32, decl: u32) bool {
    return unit == group.unit and decl >= group.decl and decl <= view.decl;
}
pub fn isGroup(store: anytype, id: T.Id) bool {
    const scope = store.node(id);
    if (scope.tag != .scoped) return false;
    const family = store.node(scope.a);
    return family.tag == .nominal and family.a == group.unit and family.b == group.decl;
}
/// A scope callback accepts every fresh region and cannot mention that region
/// in its result or latent effects. The quantifier is executable evidence,
/// unlike a free identity variable in an ordinary function header.
pub fn scopeCallback(store: anytype, raw: T.Id) ?T.Node {
    const usage = store.node(store.head(raw, 0));
    if (usage.tag != .usage or usage.b != @backingInt(T.UsageKind.once) or usage.c != 0) return null;
    const quantified = store.node(store.head(usage.a, 0));
    if (quantified.tag != .forall or quantified.c != 1) return null;
    const binder = store.list(.{ .start = quantified.b, .len = quantified.c })[0];
    const bound = store.node(binder);
    if (bound.tag != .bound or bound.b != 2 or bound.c != 0) return null;
    const arrow = store.node(store.head(quantified.a, 0));
    if (arrow.tag != .function or !isGroup(store, store.head(arrow.a, 0))) return null;
    const region = store.node(store.head(arrow.a, 0));
    if (region.b != 0 or region.c != binder) return null;
    var remaining: usize = 4096;
    if (mentionsRegion(store, arrow.b, binder, &remaining, 0) or rowMentionsRegion(store, arrow.c, binder, &remaining, 0)) return null;
    return arrow;
}
fn rowMentionsRegion(store: anytype, row: T.Effects.Id, binder: T.Id, remaining: *usize, depth: usize) bool {
    if (remaining.* == 0 or depth >= 128) return true;
    remaining.* -= 1;
    for (store.rowLabels(row)) |label| {
        const operation = store.operation(label);
        if (operation.instance.unit == 0 and operation.instance.decl != 0 and mentionsRegion(store, operation.instance.decl, binder, remaining, depth + 1)) return true;
        for (store.list(operation.arguments)) |argument| if (mentionsRegion(store, argument, binder, remaining, depth + 1)) return true;
    }
    return false;
}
fn mentionsRegion(store: anytype, raw: T.Id, binder: T.Id, remaining: *usize, depth: usize) bool {
    if (raw == 0) return false;
    if (raw == binder or remaining.* == 0 or depth >= 128) return true;
    remaining.* -= 1;
    const node = store.node(store.head(raw, 0));
    switch (node.tag) {
        .scoped => return (node.b == 0 and mentionsRegion(store, node.c, binder, remaining, depth + 1)) or mentionsRegion(store, node.a, binder, remaining, depth + 1),
        .function => return mentionsRegion(store, node.a, binder, remaining, depth + 1) or mentionsRegion(store, node.b, binder, remaining, depth + 1) or rowMentionsRegion(store, node.c, binder, remaining, depth + 1),
        .usage => return mentionsRegion(store, node.a, binder, remaining, depth + 1) or mentionsRegion(store, node.c, binder, remaining, depth + 1),
        .demand, .provider => return mentionsRegion(store, node.a, binder, remaining, depth + 1) or rowMentionsRegion(store, node.c, binder, remaining, depth + 1),
        .state_provider => return mentionsRegion(store, node.a, binder, remaining, depth + 1) or mentionsRegion(store, node.b, binder, remaining, depth + 1) or mentionsRegion(store, node.c, binder, remaining, depth + 1),
        .array, .list, .cursor, .resolver, .forall, .existential => return mentionsRegion(store, node.a, binder, remaining, depth + 1),
        .product => for (store.list(.{ .start = node.a, .len = node.b })) |child| {
            if (mentionsRegion(store, child, binder, remaining, depth + 1)) return true;
        },
        .record => for (0..node.b) |index| {
            if (mentionsRegion(store, store.recordField(node, index).ty, binder, remaining, depth + 1)) return true;
        },
        .nominal, .instance_selection, .projection => for (store.nominalArguments(node)) |child| {
            if (mentionsRegion(store, child, binder, remaining, depth + 1)) return true;
        },
        else => {},
    }
    return false;
}
pub fn isRegion(store: anytype, id: T.Id) bool {
    const scope = store.node(id);
    if (scope.tag != .scoped) return false;
    const family = store.node(scope.a);
    return family.tag == .nominal and family.a == group.unit and (family.b == group.decl or family.b == view.decl);
}
pub fn isHandle(store: anytype, id: T.Id) bool {
    const wrapper = store.node(store.head(id, 0));
    if (wrapper.tag != .usage or wrapper.b != @backingInt(T.UsageKind.unique)) return false;
    const family = store.node(store.head(wrapper.a, 0));
    return family.tag == .nominal and family.a == handle.unit and family.b == handle.decl;
}
/// The receiver relation is deferred while its input is unknown, so an
/// ordinary helper can receive either one handle or a tuple of handles.
pub fn receiveResult(store: *T.Store, raw: T.Id, effects: T.Effects.Id) T.Error!?T.Id {
    const input = store.node(try store.resolve(raw, 0));
    if (input.tag == .variable or input.tag == .projection) return null;
    var inputs: [16]T.Id = undefined;
    var count: usize = 1;
    inputs[0] = raw;
    if (input.tag == .product) {
        if (input.b == 0 or input.b > inputs.len) return error.TypeMismatch;
        count = input.b;
        @memcpy(inputs[0..count], store.list(.{ .start = input.a, .len = input.b }));
    }
    var results: [16]T.Id = undefined;
    var rows: [16]T.Effects.Id = undefined;
    for (inputs[0..count], 0..) |item, index| {
        const id = try store.resolve(item, 0);
        const wrapper = store.node(id);
        if (wrapper.tag == .variable or wrapper.tag == .projection) return null;
        if (!isHandle(store, id)) return error.TypeMismatch;
        const arguments = store.nominalArguments(store.node(wrapper.a));
        if (arguments.len != 2) return error.TypeMismatch;
        const arrow = store.node(arguments[1]);
        if (arrow.tag != .function or arrow.a != T.unit) return error.TypeMismatch;
        results[index] = arrow.b;
        rows[index] = arrow.c;
    }
    for (rows[0..count]) |row| {
        const opened = store.node(try store.openCovariant(try store.functionWithEffects(T.unit, T.unit, row)));
        try store.unifyEffects(opened.c, effects);
    }
    return if (input.tag == .product) try store.product(results[0..count]) else results[0];
}
pub const View = struct { payload: T.Id, scope: T.Id, version: T.Id };
pub fn receivers(store: anytype, raw: T.Id) bool {
    if (isHandle(store, raw)) return true;
    const input = store.node(store.head(raw, 0));
    if (input.tag != .product or input.b == 0 or input.b > 16) return false;
    for (store.list(.{ .start = input.a, .len = input.b })) |item| if (!isHandle(store, item)) return false;
    return true;
}
pub fn viewInfo(store: anytype, raw: T.Id) ?View {
    const wrapper = store.node(store.head(raw, 0));
    if (wrapper.tag != .usage or wrapper.b != @backingInt(T.UsageKind.unique)) return null;
    const scope = store.node(store.head(wrapper.a, 0));
    if (scope.tag != .scoped) return null;
    const nominal = store.node(store.head(scope.a, 0));
    if (nominal.tag != .nominal or nominal.a != view.unit or nominal.b != view.decl) return null;
    const arguments = store.nominalArguments(nominal);
    if (arguments.len != 2 or store.node(arguments[0]).tag != .array or store.node(arguments[1]).tag != .instance_version) return null;
    return .{ .payload = arguments[0], .scope = wrapper.a, .version = arguments[1] };
}
pub const Op = enum(u32) { scope, spawn, join, cancel, split, read, write, collect, receive };
pub fn lookup(name: []const u8) ?Op {
    if (!std.mem.startsWith(u8, name, "@task.")) return null;
    inline for (.{ "scope", "spawn", "join", "cancel", "split", "read", "write", "collect", "receive" }, 0..) |suffix, index|
        if (std.mem.eql(u8, name, "@task." ++ suffix)) return @fromBackingInt(@intCast(index));
    return null;
}
pub fn present(pool: anytype) bool {
    inline for (@typeInfo(Op).@"enum".field_names) |name| {
        if (pool.lookup("@task." ++ name) != null) return true;
    }
    return false;
}
pub fn arity(op: Op) usize {
    return switch (op) {
        .scope, .join, .cancel, .collect, .receive => 1,
        .spawn, .read => 2,
        .split, .write => 3,
    };
}

/// A host's explicit concurrent contract copies only scalar/Array values. It
/// grants no mutable guest sharing and no lifetime beyond the active invocation.
pub fn concurrentHost(store: anytype, raw: T.Id) bool {
    const arrow = store.node(store.head(raw, 0));
    if (arrow.tag != .function) return false;
    const row = store.row(arrow.c);
    const labels = store.rowLabels(arrow.c);
    if (row.tail != .closed or labels.len != 1 or labels[0] != T.foreign_operation) return false;
    for ([_]T.Id{ arrow.a, arrow.b }) |ty| {
        const value = store.node(store.head(ty, 0));
        if (value.tag == .array) {
            const element = store.node(store.head(value.a, 0));
            if (element.tag != .u32 and element.tag != .f32) return false;
        } else if (value.tag != .unit and value.tag != .u32 and value.tag != .f32 and value.tag != .boolean) return false;
    }
    return true;
}

fn readLoanData(store: anytype, raw: T.Id, remaining: *usize, depth: usize) T.Error!bool {
    if (remaining.* == 0 or depth >= 128) return false;
    remaining.* -= 1;
    const n = store.node(store.head(raw, 0));
    switch (n.tag) {
        .unit, .boolean, .u32, .f32 => return true,
        .array, .list => return readLoanData(store, n.a, remaining, depth + 1),
        .product => {
            for (store.list(.{ .start = n.a, .len = n.b })) |child| if (!try readLoanData(store, child, remaining, depth + 1)) return false;
            return true;
        },
        .record => {
            for (0..n.b) |index| if (!try readLoanData(store, store.recordField(n, index).ty, remaining, depth + 1)) return false;
            return true;
        },
        else => return false,
    }
}

pub const CaptureIssue = enum { transfer, capability, demand, host, budget };
pub fn captureIssue(store: anytype, root: T.Id, owning: bool, remaining: *usize, depth: usize) T.Error!?CaptureIssue {
    return captureIssueWithRows(store, root, owning, remaining, depth, &.{});
}
pub fn captureIssueWithRows(store: anytype, root: T.Id, owning: bool, remaining: *usize, depth: usize, closed_rows: []const u32) T.Error!?CaptureIssue {
    if (remaining.* == 0 or depth >= 128) return .budget;
    remaining.* -= 1;
    const node = store.node(store.head(root, 0));
    switch (node.tag) {
        .variable, .bound, .rigid, .forall, .existential => return .transfer,
        .scoped => {
            if (isGroup(store, store.head(root, 0))) return null;
            const nominal = store.node(node.a);
            if (owning and nominal.tag == .nominal and nominal.a == view.unit and nominal.b == view.decl) {
                const arguments = store.nominalArguments(nominal);
                if (arguments.len == 2 and store.node(arguments[0]).tag == .array) return captureIssueWithRows(store, arguments[0], false, remaining, depth + 1, closed_rows);
            }
            return .capability;
        },
        .usage => {
            const kind: T.UsageKind = @fromBackingInt(@intCast(node.b));
            if (kind == .concurrent) {
                if (concurrentHost(store, node.a)) return null;
                return .host;
            }
            if (kind == .borrow) {
                if (try readLoanData(store, node.a, remaining, depth + 1)) return null;
                return .capability;
            }
            if (kind == .borrow_mut) return .capability;
            return captureIssueWithRows(store, node.a, kind == .unique or kind == .once, remaining, depth + 1, closed_rows);
        },
        .demand => {
            if (!owning and !try @import("usage_check.zig").affine(store, node.a)) return .demand;
            const row = store.row(node.c);
            if (!closed(row, closed_rows) or store.rowLabels(node.c).len != 0) return .host;
            return captureIssueWithRows(store, node.a, true, remaining, depth + 1, closed_rows);
        },
        .function => {
            const row = store.row(node.c);
            if (!closed(row, closed_rows)) return .host;
            for (store.rowLabels(node.c)) |label| {
                if (label == T.foreign_operation) return .host;
                if (store.operation(label).instance.decl != 0) return .capability;
            }
            if (try captureIssueWithRows(store, node.a, false, remaining, depth + 1, closed_rows)) |code| return code;
            return captureIssueWithRows(store, node.b, false, remaining, depth + 1, closed_rows);
        },
        .state_provider, .provider => return .capability,
        .array, .list, .cursor => return captureIssueWithRows(store, node.a, owning, remaining, depth + 1, closed_rows),
        .product => for (store.list(.{ .start = node.a, .len = node.b })) |child| {
            if (try captureIssueWithRows(store, child, owning, remaining, depth + 1, closed_rows)) |code| return code;
        },
        .record => for (0..node.b) |index| {
            if (try captureIssueWithRows(store, store.recordField(node, index).ty, owning, remaining, depth + 1, closed_rows)) |code| return code;
        },
        .nominal => for (store.nominalArguments(node)) |child| {
            if (try captureIssueWithRows(store, child, owning, remaining, depth + 1, closed_rows)) |code| return code;
        },
        else => {},
    }
    return null;
}

fn closed(row: T.Effects.Row, rows: []const u32) bool {
    return row.tail == .closed or (row.tail == .variable and std.mem.findScalar(u32, rows, row.tail.variable) != null);
}
