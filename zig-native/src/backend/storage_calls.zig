//! Exact reusable-call keys. Runtime scalar values are parameters, never keys.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
pub const Key = struct {
    unit: u32,
    binding: core.BindingId,
    /// Complete checked type substitution, callback identity, and static region
    /// mapping are serialized here. Equality compares all bytes, not a hash.
    evidence: []const u32,
};
pub const Entry = struct { key: Key, function: u32, floating: bool, building: bool = true };
/// Selected source calls, not source references or partial applications. Keys
/// contain only bounded static callback choices; runtime data is never a key.
pub const ActiveCalls = struct {
    pub const Target = struct { unit: u32, id: u32, kind: enum { named, closure } };
    const Frame = struct { target: Target, start: usize, length: usize };
    allocator: std.mem.Allocator,
    frames: std.ArrayList(Frame) = .empty,
    selections: std.ArrayList(u32) = .empty,
    pub fn deinit(self: *ActiveCalls) void {
        self.frames.deinit(self.allocator);
        self.selections.deinit(self.allocator);
    }
    pub fn contains(self: *const ActiveCalls, target: Target, selection: []const u32) bool {
        for (self.frames.items) |frame| {
            if (std.meta.eql(frame.target, target) and std.mem.eql(u32, self.selections.items[frame.start..][0..frame.length], selection)) return true;
        }
        return false;
    }
    pub fn enter(self: *ActiveCalls, target: Target, selection: []const u32) !bool {
        if (self.contains(target, selection)) return false;
        try self.frames.ensureUnusedCapacity(self.allocator, 1);
        try self.selections.ensureUnusedCapacity(self.allocator, selection.len);
        const start = self.selections.items.len;
        self.selections.appendSliceAssumeCapacity(selection);
        self.frames.appendAssumeCapacity(.{ .target = target, .start = start, .length = selection.len });
        return true;
    }
    pub fn leave(self: *ActiveCalls) void {
        const frame = self.frames.pop().?;
        self.selections.shrinkRetainingCapacity(frame.start);
    }
};
pub const Cache = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,
    pub fn deinit(self: *Cache) void {
        for (self.entries.items) |entry| self.allocator.free(entry.key.evidence);
        self.entries.deinit(self.allocator);
    }
    pub fn find(self: *const Cache, key: Key) ?usize {
        for (self.entries.items, 0..) |entry, index| {
            if (entry.key.unit == key.unit and entry.key.binding == key.binding and
                std.mem.eql(u32, entry.key.evidence, key.evidence)) return index;
        }
        return null;
    }
    pub fn insert(self: *Cache, key: Key, function: u32, floating: bool) !usize {
        const evidence = try self.allocator.dupe(u32, key.evidence);
        errdefer self.allocator.free(evidence);
        const index = self.entries.items.len;
        try self.entries.append(self.allocator, .{
            .key = .{ .unit = key.unit, .binding = key.binding, .evidence = evidence },
            .function = function,
            .floating = floating,
        });
        return index;
    }
};

/// Only scalar computations can use the first reusable ABI. Storage,
/// captures, globals, handlers and unknown forms retain explicit admission in
/// the main planner rather than being guessed safe by this predicate.
pub fn scalarBody(m: *const core.Module, root: core.Id, remaining: *usize, depth: usize) bool {
    if (root == 0) return true;
    if (remaining.* == 0 or depth > 128) return false;
    remaining.* -= 1;
    const n = m.node(root);
    if (n.ty != @import("../check/types.zig").never and n.ty != @import("../check/types.zig").unit and
        n.ty != @import("../check/types.zig").boolean and n.ty != @import("../check/types.zig").u32_type and
        n.ty != @import("../check/types.zig").f32_type) return false;
    switch (n.tag) {
        .constant => {},
        .reference => {
            const ref = m.reference(root);
            if (ref.unit != 0 and ref.unit != m.unit) return false;
            const kind = m.binding(ref.binding).kind;
            if (kind != .local and kind != .parameter) return false;
        },
        .scalar, .logical => {
            if (!scalarBody(m, n.a, remaining, depth + 1) or !scalarBody(m, n.b, remaining, depth + 1)) return false;
        },
        .bind => if (!scalarBody(m, n.b, remaining, depth + 1)) return false,
        .return_ => if (!scalarBody(m, n.a, remaining, depth + 1)) return false,
        .if_value, .if_stmt => {
            if (!scalarBody(m, n.a, remaining, depth + 1) or !scalarBody(m, n.b, remaining, depth + 1) or !scalarBody(m, n.c, remaining, depth + 1)) return false;
        },
        .block, .suite => for (m.children(root)) |child| {
            if (!scalarBody(m, child, remaining, depth + 1)) return false;
        },
        else => return false,
    }
    return true;
}

/// A first destination ABI: exactly one fixed array construction, scalar
/// inputs, no calls/branches/loops or borrowed payloads. The caller opens the
/// result owner; the callee initializes it without retaining local scratch.
pub fn destinationBody(m: *const core.Module, root: core.Id, arrays: *usize, remaining: *usize, depth: usize) bool {
    if (root == 0) return true;
    if (remaining.* == 0 or depth > 128) return false;
    remaining.* -= 1;
    const n = m.node(root);
    switch (n.tag) {
        .array => {
            arrays.* += 1;
            if (arrays.* > 1 or m.types.node(n.ty).tag != .array) return false;
            for (m.children(root)) |child| if (!scalarBody(m, child, remaining, depth + 1)) return false;
        },
        .reference => {
            const ref = m.reference(root);
            if (ref.unit != 0 and ref.unit != m.unit) return false;
            const kind = m.binding(ref.binding).kind;
            if (kind != .local and kind != .parameter) return false;
        },
        .bind => return destinationBody(m, n.b, arrays, remaining, depth + 1),
        .return_ => return destinationBody(m, n.a, arrays, remaining, depth + 1),
        .block, .suite => for (m.children(root)) |child| {
            if (!destinationBody(m, child, arrays, remaining, depth + 1)) return false;
        },
        else => return scalarBody(m, root, remaining, depth + 1),
    }
    return true;
}

/// Closed inline data has no owning descriptors, borrows, or callable slots.
/// Generic layouts stay with the ordinary planner until their substitutions
/// have an explicit reusable-call contract.
pub fn inlineType(m: *const core.Module, ty: T.Id, remaining: *usize, depth: usize) bool {
    if (remaining.* == 0 or depth > 128) return false;
    remaining.* -= 1;
    const n = m.types.node(ty);
    switch (n.tag) {
        .unit, .boolean, .u32, .f32, .never => return true,
        .product, .record => {
            for (0..n.b) |index| {
                const child = if (n.tag == .record) m.types.recordField(n, index).ty else m.types.list(.{ .start = n.a, .len = n.b })[index];
                if (!inlineType(m, child, remaining, depth + 1)) return false;
            }
            return true;
        },
        .nominal => {
            if (m.types.nominalArguments(n).len != 0) return false;
            for (m.nominals, 0..) |nominal, index| {
                if (nominal.identity.unit != n.a or nominal.identity.decl != n.b) continue;
                const constructors = m.nominalConstructors(@intCast(index));
                if (constructors.len == 0) return false;
                for (constructors) |constructor| {
                    const payload = m.constructor(constructor).payload;
                    if (payload != 0 and !inlineType(m, payload, remaining, depth + 1)) return false;
                }
                return true;
            }
            return false;
        },
        else => return false,
    }
}

/// Closed direct callees can share the inline-data ABI. Every reached header
/// and body is checked; active cycles, generic headers and unknown calls decline.
/// This is physical admission only. Source authority is still proved separately.
const ClosedCalls = struct {
    units: []const core.Module,
    active: [128]core.BindingRef = undefined,
    len: usize = 0,
    fn body(self: *ClosedCalls, m: *const core.Module, binding: core.BindingId, remaining: *usize, depth: usize) bool {
        if (self.len == self.active.len or binding == 0 or binding >= m.bindings.len) return false;
        const target: core.BindingRef = .{ .unit = m.unit, .binding = binding };
        for (self.active[0..self.len]) |prior| if (std.meta.eql(prior, target)) return false;
        const source = m.body(binding) orelse return false;
        if (!source.is_function or source.scheme.variables.len != 0 or source.scheme.row_variables.len != 0 or source.scheme.obligations.len != 0 or source.scheme.generative.len != 0) return false;
        var signature = m.binding(binding).ty;
        for (m.bodyParameters(source)) |parameter| {
            if (!inlineType(m, parameter.ty, remaining, depth + 1)) return false;
            const arrow = m.types.node(signature);
            if (arrow.tag != .function) return false;
            const row = m.types.row(arrow.c);
            if (row.labels.len != 0 or row.tail != .closed) return false;
            signature = arrow.b;
        }
        if (!inlineType(m, signature, remaining, depth + 1)) return false;
        self.active[self.len] = target;
        self.len += 1;
        defer self.len -= 1;
        return leafBody(m, source.root, remaining, depth + 1, false, self);
    }
};
pub fn inlineBody(units: []const core.Module, m: *const core.Module, binding: core.BindingId, remaining: *usize) bool {
    const source = m.body(binding) orelse return false;
    // Leaves already establish every physical type from their checked nodes;
    // residual unused header variables do not add a call dependency.
    if (leafBody(m, source.root, remaining, 0, false, null)) return true;
    var calls: ClosedCalls = .{ .units = units };
    return calls.body(m, binding, remaining, 0);
}

pub fn readerType(m: *const core.Module, ty: T.Id, remaining: *usize, depth: usize) bool {
    if (remaining.* == 0 or depth > 128) return false;
    remaining.* -= 1;
    const n = m.types.node(ty);
    if (n.tag == .array or n.tag == .list) return inlineType(m, n.a, remaining, depth + 1);
    if (n.tag == .cursor) return readerType(m, n.a, remaining, depth + 1);
    if (@import("../check/storage_types.zig").info(&m.types, ty)) |info| return inlineType(m, info.element, remaining, depth + 1);
    switch (n.tag) {
        .product => {
            for (m.types.list(.{ .start = n.a, .len = n.b })) |child| if (!readerType(m, child, remaining, depth + 1)) return false;
            return true;
        },
        .record => {
            for (0..n.b) |index| if (!readerType(m, m.types.recordField(n, index).ty, remaining, depth + 1)) return false;
            return true;
        },
        .nominal => {
            // Storage nominals were handled above. User payloads in this first
            // descriptor-record ABI must have a closed, unparameterized schema.
            if (m.types.nominalArguments(n).len != 0) return false;
            for (m.nominals, 0..) |nominal, index| if (nominal.identity.unit == n.a and nominal.identity.decl == n.b) {
                for (m.nominalConstructors(@intCast(index))) |constructor| {
                    const payload = m.constructor(constructor).payload;
                    if (payload != 0 and !readerType(m, payload, remaining, depth + 1)) return false;
                }
                return true;
            };
            return false;
        },
        else => return inlineType(m, ty, remaining, depth + 1),
    }
}

/// Descriptor parameters preserve the caller's owner identity. This admission
/// walk permits reads only, and the initial ABI returns a scalar, so no callee
/// can resize an input or return a borrow with a manufactured lifetime.
pub fn readerBody(m: *const core.Module, root: core.Id, remaining: *usize, depth: usize) bool {
    return leafBody(m, root, remaining, depth, true, null);
}

fn leafBody(m: *const core.Module, root: core.Id, remaining: *usize, depth: usize, readers: bool, calls: ?*ClosedCalls) bool {
    if (root == 0) return true;
    if (remaining.* == 0 or depth > 128) return false;
    remaining.* -= 1;
    const n = m.node(root);
    if (readers) {
        if (!readerType(m, n.ty, remaining, depth + 1)) return false;
    } else if (!inlineType(m, n.ty, remaining, depth + 1)) return false;
    switch (n.tag) {
        .constant => {},
        .reference => {
            const ref = m.reference(root);
            if (ref.unit != 0 and ref.unit != m.unit) return false;
            const kind = m.binding(ref.binding).kind;
            if (kind != .local and kind != .parameter) return false;
        },
        .scalar, .logical => {
            if (n.tag == .scalar and (n.c != 0 or @import("simd_intrinsics.zig").literalLanes(n.op))) return false;
            if (!leafBody(m, n.a, remaining, depth + 1, readers, calls) or !leafBody(m, n.b, remaining, depth + 1, readers, calls)) return false;
        },
        .bind, .construct => return leafBody(m, n.b, remaining, depth + 1, readers, calls),
        .pattern_bind => return n.c == 0 and leafBody(m, n.b, remaining, depth + 1, readers, calls),
        .return_ => return leafBody(m, n.a, remaining, depth + 1, readers, calls),
        .project => {
            const projection = m.projection(n.b);
            if (projection.variants.len == 0) {
                const receiver = m.types.node(m.typeOf(n.a));
                const field = if (receiver.tag == .record) found: {
                    for (0..receiver.b) |index| if (m.types.recordField(receiver, index).name == projection.field) break :found true;
                    break :found false;
                } else false;
                // A missing data field can invoke a user getter. Such a call
                // needs its own summary and is outside these leaf ABIs.
                if (!field) return false;
            }
            return leafBody(m, n.a, remaining, depth + 1, readers, calls);
        },
        .if_value, .if_stmt => {
            if (!leafBody(m, n.a, remaining, depth + 1, readers, calls) or !leafBody(m, n.b, remaining, depth + 1, readers, calls) or !leafBody(m, n.c, remaining, depth + 1, readers, calls)) return false;
        },
        .block, .suite, .product, .record => for (m.children(root)) |child| {
            if (!leafBody(m, child, remaining, depth + 1, readers, calls)) return false;
        },
        .call => {
            const graph = calls orelse return false;
            const call = m.call(root);
            var target = call.target;
            if (target.unit == 0) target.unit = m.unit;
            if (target.unit > graph.units.len) return false;
            const owner = &graph.units[target.unit - 1];
            const body = owner.body(target.binding) orelse return false;
            if (call.arguments.len != owner.bodyParameters(body).len) return false;
            for (call.arguments) |argument| if (!leafBody(m, argument, remaining, depth + 1, false, calls)) return false;
            if (!graph.body(owner, target.binding, remaining, depth + 1)) return false;
        },
        .storage => {
            if (!readers) return false;
            const op: @import("../check/storage_ops.zig").Op = @fromBackingInt(@intCast(n.c));
            switch (op) {
                .at, .link, .view, .load, .length, .read => {},
                else => return false,
            }
            for (m.children(root)) |child| if (!leafBody(m, child, remaining, depth + 1, readers, calls)) return false;
        },
        .array_op => {
            if (!readers) return false;
            const op: @import("collection_ops.zig").Op = @fromBackingInt(@intCast(n.c));
            switch (op) {
                .length, .get, .identity, .cursor, .cursor_has, .cursor_value, .cursor_advance => {},
                else => return false,
            }
            for (m.children(root)) |child| if (!leafBody(m, child, remaining, depth + 1, readers, calls)) return false;
        },
        else => return false,
    }
    return true;
}
