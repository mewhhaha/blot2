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
pub const View = struct { payload: T.Id, scope: T.Id, version: T.Id };
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
pub const Op = enum(u32) { scope, spawn, join, cancel, split, read, write };
pub fn lookup(name: []const u8) ?Op {
    if (!std.mem.startsWith(u8, name, "@task.")) return null;
    inline for (.{ "scope", "spawn", "join", "cancel", "split", "read", "write" }, 0..) |suffix, index|
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
        .scope, .join, .cancel => 1,
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
