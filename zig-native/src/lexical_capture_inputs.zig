//! Session-owned inputs to a lexical typing job. Value handles are used only
//! while building this record; aliases survive as canonical graph ordinals.
const std = @import("std");
const core = @import("core.zig");
const types = @import("types.zig");
const evidence = @import("type_evidence.zig");
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{Declined};
pub const Interfaces = std.AutoHashMapUnmanaged(u32, evidence.Id);

fn interface(view: anytype, selected: *const Interfaces, value: u32) evidence.Id {
    return selected.get(value) orelse view.value_evidence[value];
}

pub const Slot = struct { binding: core.BindingId, interface: evidence.Id, alias: u32 };
pub const Inputs = struct {
    unit: u32,
    identity: u32,
    anonymous: bool,
    applied: u32,
    source_type: types.Id,
    existing: evidence.Id,
    parameters: usize,
    mappings: []evidence.Mapping,
    rows: []evidence.RowMapping,
    slots: []Slot,
    words: []u64,
    /// Corresponding live handles in canonical traversal order; never key bytes.
    values: []u32,
    pub fn deinit(self: *Inputs, allocator: Allocator) void {
        allocator.free(self.mappings);
        allocator.free(self.rows);
        allocator.free(self.slots);
        allocator.free(self.words);
        allocator.free(self.values);
        self.* = undefined;
    }
};

pub const Cache = struct {
    keys: std.StringHashMapUnmanaged(u32) = .empty,
    inputs: std.ArrayList(Inputs) = .empty,
    requests: usize = 0,
    reused: usize = 0,
    retained_words: usize = 0,
    examined_words: usize = 0,
    interface_visits: usize = 0,
    pub fn deinit(self: *Cache, allocator: Allocator) void {
        for (self.inputs.items) |*input| input.deinit(allocator);
        self.inputs.deinit(allocator);
        self.keys.deinit(allocator);
        self.* = undefined;
    }
    pub fn intern(self: *Cache, allocator: Allocator, session: anytype, value: u32, selected: *const Interfaces) Allocator.Error!?u32 {
        self.requests += 1;
        // One session budget bounds the whole collection, including repeated
        // exact-key lookups. Deep nested environments cannot each retain an
        // unbounded copy of their transitive capture graph.
        if (self.examined_words >= session.options.max_children) return null;
        var examined: usize = 0;
        defer self.examined_words += examined;
        var input = try buildWithBudget(allocator, session, value, selected, session.options.max_children - self.examined_words, &examined, false) orelse return null;
        errdefer input.deinit(allocator);
        const bytes = std.mem.sliceAsBytes(input.words);
        if (self.keys.get(bytes)) |existing| {
            input.deinit(allocator);
            self.reused += 1;
            return existing;
        }
        if (self.inputs.items.len >= session.options.max_values or self.inputs.items.len >= std.math.maxInt(u32) or input.words.len > session.options.max_children -| self.retained_words) {
            input.deinit(allocator);
            return null;
        }
        try self.keys.ensureUnusedCapacity(allocator, 1);
        try self.inputs.ensureUnusedCapacity(allocator, 1);
        const index: u32 = @intCast(self.inputs.items.len + 1);
        self.keys.putAssumeCapacity(bytes, index);
        self.inputs.appendAssumeCapacity(input);
        self.retained_words += input.words.len;
        return index;
    }
};

fn append(allocator: Allocator, words: *std.ArrayList(u64), values: []const u64, limit: usize, examined: *usize) Error!void {
    if (words.items.len > limit or values.len > limit - words.items.len) return error.Declined;
    examined.* += values.len;
    try words.appendSlice(allocator, values);
}

pub fn build(allocator: Allocator, session: anytype, value: u32) Allocator.Error!?Inputs {
    const selected: Interfaces = .empty;
    return buildWithInterfaces(allocator, session, value, &selected);
}
pub fn buildWithInterfaces(allocator: Allocator, session: anytype, value: u32, selected: *const Interfaces) Allocator.Error!?Inputs {
    var examined: usize = 0;
    return buildWithBudget(allocator, session, value, selected, session.options.max_children, &examined, false);
}
/// Exact session-local specialization input, including an empty environment.
pub fn buildCanonical(allocator: Allocator, session: anytype, value: u32) Allocator.Error!?Inputs {
    const selected: Interfaces = .empty;
    var examined: usize = 0;
    return buildWithBudget(allocator, session, value, &selected, session.options.max_children, &examined, true);
}
pub fn buildCanonicalBudget(allocator: Allocator, session: anytype, value: u32, limit: usize, examined: *usize) Allocator.Error!?Inputs {
    const selected: Interfaces = .empty;
    return buildWithBudget(allocator, session, value, &selected, limit, examined, true);
}
fn buildWithBudget(allocator: Allocator, session: anytype, value: u32, selected: *const Interfaces, limit: usize, examined: *usize, allow_empty: bool) Allocator.Error!?Inputs {
    return buildChecked(allocator, session, value, selected, limit, examined, allow_empty) catch |err| switch (err) {
        error.Declined => null,
        error.OutOfMemory => error.OutOfMemory,
    };
}

fn buildChecked(allocator: Allocator, session: anytype, value: u32, selected: *const Interfaces, limit: usize, examined: *usize, allow_empty: bool) Error!Inputs {
    const view = session.snapshot();
    if (value == 0 or value >= view.values.len or view.values[value].kind != .closure) return error.Declined;
    const root = session.closureInfo(value);
    if (root.origin != .anonymous and root.origin != .named) return error.Declined;
    var owner: ?usize = null;
    for (session.units, 0..) |module, index| if (module.unit == root.unit or (module.unit == 0 and index + 1 == root.unit)) {
        owner = index;
        break;
    };
    const module = &session.units[owner orelse return error.Declined];
    const children = session.valueChildren(value);
    if ((!allow_empty and children.len == 0) or children.len > session.options.max_children) return error.Declined;
    if (children.len > limit / 4) return error.Declined;
    const anonymous = root.origin == .anonymous;
    if (anonymous and root.identity >= module.closures.len) return error.Declined;
    const definition = if (anonymous) null else module.body(root.identity) orelse return error.Declined;
    const bindings: []const u32 = if (anonymous) module.extra[module.closures[root.identity].captures.start..][0..module.closures[root.identity].captures.len] else &.{};
    if (anonymous and bindings.len != children.len) return error.Declined;
    if (!anonymous and (children.len != root.applied or root.applied >= definition.?.parameters.len)) return error.Declined;
    const slots = try allocator.alloc(Slot, children.len);
    errdefer allocator.free(slots);
    const mappings = try allocator.dupe(evidence.Mapping, view.type_mappings[root.mappings.start..][0..root.mappings.len]);
    errdefer allocator.free(mappings);
    const rows = try allocator.dupe(evidence.RowMapping, view.row_mappings[root.row_mappings.start..][0..root.row_mappings.len]);
    errdefer allocator.free(rows);
    var values: std.ArrayList(u32) = .empty;
    errdefer values.deinit(allocator);
    try values.append(allocator, value);
    var words: std.ArrayList(u64) = .empty;
    errdefer words.deinit(allocator);
    try append(allocator, &words, &.{ 1, root.unit, root.identity, @intFromBool(anonymous), root.applied, root.ty, view.value_evidence[value], children.len }, limit, examined);
    inline for (@typeInfo(@TypeOf(session.options)).@"struct".field_names) |field| {
        const option = @field(session.options, field);
        try append(allocator, &words, &.{if (@TypeOf(option) == bool) @intFromBool(option) else @intCast(option)}, limit, examined);
    }
    try append(allocator, &words, &.{mappings.len}, limit, examined);
    for (mappings) |mapping| try append(allocator, &words, &.{ mapping.variable, mapping.evidence }, limit, examined);
    try append(allocator, &words, &.{rows.len}, limit, examined);
    for (rows) |row| try append(allocator, &words, &.{ row.variable, row.evidence }, limit, examined);
    const Seen = struct { ordinal: u32, active: bool };
    var seen: std.AutoHashMapUnmanaged(u32, Seen) = .empty;
    defer seen.deinit(allocator);
    const Visit = struct { value: u32, next: usize = 0, depth: usize, opened: bool = false };
    var stack: std.ArrayList(Visit) = .empty;
    defer stack.deinit(allocator);
    var edges: usize = 0;
    for (children, 0..) |child, index| {
        const binding = if (anonymous) bindings[index] else module.bodyParameters(definition.?)[index].binding;
        if (child >= view.values.len or child >= view.value_evidence.len or interface(view, selected, child) == 0) return error.Declined;
        try append(allocator, &words, &.{ 0x736c6f74, binding }, limit, examined);
        try stack.append(allocator, .{ .value = child, .depth = 0 });
        while (stack.items.len != 0) {
            const last = stack.items.len - 1;
            const current = stack.items[last];
            if (!current.opened) {
                if (seen.get(current.value)) |prior| {
                    if (prior.active) return error.Declined;
                    try append(allocator, &words, &.{ 0, prior.ordinal }, limit, examined);
                    _ = stack.pop();
                    continue;
                }
                if (current.depth >= session.options.max_type_depth or seen.count() >= session.options.max_values or seen.count() >= std.math.maxInt(u32)) return error.Declined;
                if (current.value >= view.values.len or current.value >= view.value_evidence.len or interface(view, selected, current.value) == 0) return error.Declined;
                const ordinal: u32 = @intCast(seen.count());
                try values.append(allocator, current.value);
                try seen.put(allocator, current.value, .{ .ordinal = ordinal, .active = true });
                const info = view.values[current.value];
                if (info.start > view.children.len or info.len > view.children.len - info.start) return error.Declined;
                try append(allocator, &words, &.{ 1, ordinal, @backingInt(info.kind), @backingInt(info.scalar), interface(view, selected, current.value), info.len }, limit, examined);
                switch (info.kind) {
                    .scalar, .product, .record, .nominal, .array, .list, .cursor => try append(allocator, &words, &.{ info.nominal, info.bits }, limit, examined),
                    .closure, .suspension => {
                        if (info.bits >= view.closures.len) return error.Declined;
                        const metadata = view.closures[info.bits];
                        try append(allocator, &words, &.{ metadata.unit, metadata.identity, @backingInt(metadata.origin), metadata.applied, metadata.ty, metadata.mappings.len }, limit, examined);
                        for (view.type_mappings[metadata.mappings.start..][0..metadata.mappings.len]) |mapping| try append(allocator, &words, &.{ mapping.variable, mapping.evidence }, limit, examined);
                        try append(allocator, &words, &.{metadata.row_mappings.len}, limit, examined);
                        for (view.row_mappings[metadata.row_mappings.start..][0..metadata.row_mappings.len]) |row| try append(allocator, &words, &.{ row.variable, row.evidence }, limit, examined);
                        if (info.kind == .suspension) {
                            if (info.nominal >= view.demands.len) return error.Declined;
                            const memo = view.demands[@intCast(info.nominal)];
                            // Cached/evaluating demands require an owned memo
                            // result and staging dependencies, not only a state.
                            if (memo.state != .pending) return error.Declined;
                            // Creation identity and consumed memo state are semantic
                            // inputs, rather than alpha-renamable alias ordinals.
                            try append(allocator, &words, &.{ current.value, info.nominal, @backingInt(memo.state), memo.value }, limit, examined);
                        }
                    },
                    .provider, .state_provider => try append(allocator, &words, &.{ current.value, info.nominal, info.bits }, limit, examined),
                    .type_constructor, .resolver, .effect_set, .effect_descriptor, .computation, .request_decision => return error.Declined,
                }
                if (info.kind == .record) {
                    const names = session.recordFieldNames(current.value);
                    try append(allocator, &words, &.{names.len}, limit, examined);
                    for (names) |name| try append(allocator, &words, &.{name}, limit, examined);
                }
                stack.items[last].opened = true;
            }
            const info = view.values[current.value];
            if (current.next == info.len) {
                seen.getPtr(current.value).?.active = false;
                _ = stack.pop();
                continue;
            }
            edges += 1;
            if (edges > limit) return error.Declined;
            stack.items[last].next += 1;
            try stack.append(allocator, .{ .value = view.children[info.start + current.next], .depth = current.depth + 1 });
        }
        slots[index] = .{ .binding = binding, .interface = interface(view, selected, child), .alias = seen.get(child).?.ordinal };
    }
    const owned_words = try words.toOwnedSlice(allocator);
    errdefer allocator.free(owned_words);
    return .{ .unit = root.unit, .identity = root.identity, .anonymous = anonymous, .applied = root.applied, .source_type = root.ty, .existing = view.value_evidence[value], .parameters = if (anonymous) 1 else definition.?.parameters.len - root.applied, .mappings = mappings, .rows = rows, .slots = slots, .words = owned_words, .values = try values.toOwnedSlice(allocator) };
}
