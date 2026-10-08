//! Flat effect rows with chronological substitution. Labels are exact operation
//! catalog IDs; family argument specialization belongs to the semantic checker.
const std = @import("std");
const resolution_cache = @import("resolution_cache.zig");
const epoch_cache = @import("epoch_resolution_cache.zig");
pub const Id = u32;
pub const Label = u32;
pub const Cursor = u32;
pub const List = struct { start: u32 = 0, len: u32 = 0 };
pub const Tail = union(enum) { closed, variable: u32, parameter: u32 };
pub const Row = struct { labels: List = .{}, tail: Tail = .closed, cursor: Cursor = 0 };
pub const Error = std.mem.Allocator.Error || error{ EffectMismatch, InfiniteEffect, EffectLimit };
const none = std.math.maxInt(u32);
const Variable = struct { first: u32 = none, last: u32 = none };
pub const Version = struct { variable: u32, replacement: Id, position: Cursor, previous: u32, next: u32 = none };
pub const Mark = struct { rows: usize, labels: usize, variables: usize, versions: usize, next_position: Cursor };
pub const Extraction = struct { remaining: Id, expanded: ?u32 = null };

pub const Store = struct {
    // Only removal/recycling changes immutable closed row descriptors.
    physical_epoch: u64 = 0,
    // Writes and rollback advance this clock; recycled numeric IDs never make
    // an entry from a discarded history valid again. It is not rolled back.
    mutation_epoch: u64 = 0,
    use_resolution_cache: bool = true,
    resolved: epoch_cache.Cache = .{},
    allocator: std.mem.Allocator,
    rows: std.ArrayList(Row) = .empty,
    labels: std.ArrayList(Label) = .empty,
    variables: std.ArrayList(Variable) = .empty,
    versions: std.ArrayList(Version) = .empty,
    /// Type and row substitutions share this clock when embedded in types.Store.
    next_position: Cursor = 0,

    /// Owned per-store policy; uncached instances preserve the same chronology.
    pub const Options = struct { resolution_cache: bool = true };

    pub fn init(allocator: std.mem.Allocator) Error!Store {
        return initWithOptions(allocator, .{});
    }
    pub fn initWithOptions(allocator: std.mem.Allocator, options: Options) Error!Store {
        var self: Store = .{ .allocator = allocator, .use_resolution_cache = options.resolution_cache };
        errdefer self.deinit();
        try self.rows.append(allocator, .{});
        return self;
    }
    pub fn deinit(self: *Store) void {
        self.rows.deinit(self.allocator);
        self.labels.deinit(self.allocator);
        self.variables.deinit(self.allocator);
        self.versions.deinit(self.allocator);
        self.resolved.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn node(self: *const Store, id: Id) Row {
        return self.rows.items[id];
    }
    pub fn list(self: *const Store, span: List) []const Label {
        return self.labels.items[span.start..][0..span.len];
    }
    pub fn mark(self: *const Store) Mark {
        return .{ .rows = self.rows.items.len, .labels = self.labels.items.len, .variables = self.variables.items.len, .versions = self.versions.items.len, .next_position = self.next_position };
    }
    pub fn rollback(self: *Store, point: Mark) void {
        if (self.physical_epoch != std.math.maxInt(u64)) self.physical_epoch += 1;
        resolution_cache.tick(&self.mutation_epoch);
        while (self.versions.items.len > point.versions) {
            const write = self.versions.pop().?;
            self.variables.items[write.variable].last = write.previous;
            if (write.previous == none) self.variables.items[write.variable].first = none else self.versions.items[write.previous].next = none;
        }
        self.rows.shrinkRetainingCapacity(point.rows);
        self.labels.shrinkRetainingCapacity(point.labels);
        self.variables.shrinkRetainingCapacity(point.variables);
        self.next_position = point.next_position;
    }
    fn add(self: *Store, value: Row) Error!Id {
        if (self.rows.items.len == none) return error.EffectLimit;
        const id: Id = @intCast(self.rows.items.len);
        try self.rows.append(self.allocator, value);
        return id;
    }
    pub fn row(self: *Store, labels: []const Label, tail: Tail) Error!Id {
        if (labels.len == 0 and tail == .closed) return 0;
        if (labels.len > none - self.labels.items.len) return error.EffectLimit;
        const start = self.labels.items.len;
        errdefer self.labels.shrinkRetainingCapacity(start);
        // An imported/rebuilt row may borrow this side array. Preserve an index
        // across growth instead of reading a pointer into its previous buffer.
        const source_address = @intFromPtr(labels.ptr);
        const own_address = @intFromPtr(self.labels.items.ptr);
        const borrowed: ?usize = if (labels.len != 0 and source_address >= own_address and
            source_address - own_address <= self.labels.items.len * @sizeOf(Label) and
            (source_address - own_address) % @sizeOf(Label) == 0 and
            labels.len <= self.labels.items.len - (source_address - own_address) / @sizeOf(Label))
            (source_address - own_address) / @sizeOf(Label)
        else
            null;
        try self.labels.ensureUnusedCapacity(self.allocator, labels.len);
        self.labels.appendSliceAssumeCapacity(if (borrowed) |index| self.labels.items[index..][0..labels.len] else labels);
        return self.add(.{ .labels = .{ .start = @intCast(start), .len = @intCast(labels.len) }, .tail = tail });
    }
    pub fn rowAt(self: *Store, labels: []const Label, tail: Tail, at: Cursor) Error!Id {
        const result = try self.row(labels, tail);
        if (result != 0) self.rows.items[result].cursor = at;
        return result;
    }
    pub fn cursor(self: *const Store) Cursor {
        return self.next_position;
    }
    pub fn freeVariables(self: *Store, root: Id) Error![]u32 {
        const tail = self.node(try self.resolve(root, 0)).tail;
        return self.allocator.dupe(u32, if (tail == .variable) &.{tail.variable} else &.{});
    }
    pub fn fresh(self: *Store) Error!Id {
        if (self.variables.items.len == none) return error.EffectLimit;
        const index: u32 = @intCast(self.variables.items.len);
        try self.variables.append(self.allocator, .{});
        errdefer _ = self.variables.pop();
        return self.row(&.{}, .{ .variable = index });
    }
    pub fn appendVersion(self: *Store, variable: u32, replacement_id: Id) Error!void {
        return self.appendVersionAt(variable, replacement_id, self.next_position);
    }
    pub fn appendVersionAt(self: *Store, variable: u32, replacement_id: Id, position: Cursor) Error!void {
        std.debug.assert(variable < self.variables.items.len and replacement_id < self.rows.items.len);
        std.debug.assert(position >= self.next_position);
        if (position == none or self.versions.items.len == none) return error.EffectLimit;
        const old = self.variables.items[variable];
        const index: u32 = @intCast(self.versions.items.len);
        try self.versions.append(self.allocator, .{ .variable = variable, .replacement = replacement_id, .position = position, .previous = old.last });
        if (old.last == none) self.variables.items[variable].first = index else self.versions.items[old.last].next = index;
        self.variables.items[variable].last = index;
        self.next_position = position + 1;
        resolution_cache.tick(&self.mutation_epoch);
    }
    fn replacement(self: *const Store, variable: u32, at: Cursor) ?Version {
        var index = self.variables.items[variable].first;
        while (index != none) : (index = self.versions.items[index].next) {
            const write = self.versions.items[index];
            if (write.position >= at) return write;
        }
        return null;
    }
    pub fn replacementAt(self: *const Store, variable: u32, at: Cursor) ?Version {
        return self.replacement(variable, at);
    }
    pub fn resolve(self: *Store, root: Id, at: Cursor) Error!Id {
        if (!self.use_resolution_cache or at != 0 or root == 0) return self.resolveUncached(root, at);
        const mutation = resolution_cache.stamp(self.mutation_epoch) orelse return self.resolveUncached(root, at);
        if (!self.resolved.activate(mutation, 0)) return self.resolveUncached(root, at);
        if (self.resolved.get(root)) |result| return result;
        const result = try self.resolveUncached(root, at);
        // An unchanged query must not acquire fresh retained storage.
        if (result == root and root >= self.resolved.high_water) return result;
        try self.resolved.put(self.allocator, root, result);
        return result;
    }
    fn resolveUncached(self: *Store, root: Id, at: Cursor) Error!Id {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const scratch_allocator = scratch.allocator();
        const original = self.node(root);
        if (original.tail != .variable) return root;
        var position = @max(at, original.cursor);
        var current = original;
        var labels: std.ArrayList(Label) = .empty;
        defer labels.deinit(scratch_allocator);
        var single: List = .{};
        var fragments: usize = 0;
        var changed = false;
        while (current.tail == .variable) {
            position = @max(position, current.cursor);
            const write = self.replacement(current.tail.variable, position) orelse break;
            if (current.labels.len != 0) {
                if (fragments == 0) {
                    single = current.labels;
                } else {
                    if (fragments == 1) try labels.appendSlice(scratch_allocator, self.list(single));
                    try labels.appendSlice(scratch_allocator, self.list(current.labels));
                }
                fragments += 1;
            }
            current = self.node(write.replacement);
            position = write.position + 1;
            changed = true;
        }
        if (!changed) {
            if (position == original.cursor) return root;
            return self.add(.{ .labels = original.labels, .tail = original.tail, .cursor = position });
        }
        if (current.labels.len != 0) {
            if (fragments == 0) {
                single = current.labels;
            } else {
                if (fragments == 1) try labels.appendSlice(scratch_allocator, self.list(single));
                try labels.appendSlice(scratch_allocator, self.list(current.labels));
            }
            fragments += 1;
        }
        // Published label spans are immutable. A single fragment only needs
        // an owned row header with the newly advanced chronological cursor.
        if (fragments <= 1) {
            if (single.len == 0 and current.tail == .closed) return 0;
            return self.add(.{ .labels = single, .tail = current.tail, .cursor = position });
        }
        const result = try self.row(labels.items, current.tail);
        if (result != 0) self.rows.items[result].cursor = position;
        return result;
    }
    pub fn bind(self: *Store, variable: u32, replacement_id: Id) Error!void {
        const point = self.mark();
        errdefer self.rollback(point);
        const resolved = try self.resolve(replacement_id, 0);
        const tail = self.node(resolved).tail;
        if (tail == .variable and tail.variable == variable) return error.InfiniteEffect;
        try self.appendVersion(variable, resolved);
    }
    fn extractInner(self: *Store, root: Id, label: Label) Error!Extraction {
        const view = try self.extractView(self.node(root), label);
        const remaining = view.saved orelse if (view.remaining.labels.len == 0 and view.remaining.tail == .closed) 0 else try self.add(view.remaining);
        return .{ .remaining = remaining, .expanded = view.expanded };
    }
    pub fn extract(self: *Store, root: Id, label: Label) Error!Extraction {
        const point = self.mark();
        errdefer self.rollback(point);
        return self.extractInner(try self.resolve(root, 0), label);
    }
    // Unification walks immutable spans without publishing a row header for
    // every removed label. Cursors and substitutions remain chronological.
    const ExtractionView = struct { remaining: Row, expanded: ?u32 = null, saved: ?Id = null };
    fn resolveView(self: *Store, value: Row) Error!Row {
        if (value.tail != .variable or self.replacement(value.tail.variable, value.cursor) == null) return value;
        return self.node(try self.resolve(try self.add(value), 0));
    }
    fn extractView(self: *Store, value: Row, label: Label) Error!ExtractionView {
        const labels = self.list(value.labels);
        for (labels, 0..) |candidate, index| if (candidate == label) {
            if (index == 0 or index + 1 == labels.len) {
                return .{ .remaining = .{ .labels = .{ .start = value.labels.start + @as(u32, if (index == 0) 1 else 0), .len = value.labels.len - 1 }, .tail = value.tail } };
            }
            var buffer: [512]u8 align(@alignOf(usize)) = undefined;
            var scratch: std.heap.BufferFirstAllocator = .init(&buffer, self.allocator);
            const allocator = scratch.allocator();
            var remaining: std.ArrayList(Label) = .empty;
            defer remaining.deinit(allocator);
            try remaining.appendSlice(allocator, labels[0..index]);
            try remaining.appendSlice(allocator, labels[index + 1 ..]);
            const saved = try self.row(remaining.items, value.tail);
            return .{ .remaining = self.node(saved), .saved = saved };
        };
        if (value.tail != .variable) return error.EffectMismatch;
        const tail = try self.fresh();
        const replacement_id = try self.row(&.{label}, self.node(tail).tail);
        try self.appendVersion(value.tail.variable, replacement_id);
        return .{ .remaining = .{ .labels = value.labels, .tail = self.node(tail).tail, .cursor = value.cursor }, .expanded = value.tail.variable };
    }
    pub fn unify(self: *Store, left: Id, right: Id) Error!void {
        const point = self.mark();
        errdefer self.rollback(point);
        var a = self.node(try self.resolve(left, 0));
        var b = self.node(try self.resolve(right, 0));
        var work: usize = 0;
        while (true) {
            if (work == 65536) return error.EffectLimit;
            work += 1;
            if (a.labels.len == 0 and b.labels.len == 0 and std.meta.eql(a.tail, b.tail)) return;
            if (a.labels.len == 0 and a.tail == .variable) return self.bind(a.tail.variable, try self.add(b));
            if (b.labels.len == 0 and b.tail == .variable) return self.bind(b.tail.variable, try self.add(a));
            if (a.labels.len == 0) return error.EffectMismatch;
            const selected = try self.extractView(b, self.list(a.labels)[0]);
            if (selected.expanded) |variable| {
                if (a.tail == .variable and a.tail.variable == variable) return error.InfiniteEffect;
            }
            a = try self.resolveView(.{ .labels = .{ .start = a.labels.start + 1, .len = a.labels.len - 1 }, .tail = a.tail, .cursor = a.cursor });
            b = try self.resolveView(selected.remaining);
        }
    }
    /// Substitution for scheme instantiation replaces only the named tail.
    pub fn substitute(self: *Store, root: Id, variable: u32, replacement_id: Id) Error!Id {
        const original = self.node(root);
        if (original.tail != .variable or original.tail.variable != variable) return root;
        return self.replaceTail(root, replacement_id);
    }
    pub fn substituteParameter(self: *Store, root: Id, parameter: u32, replacement_id: Id) Error!Id {
        const original = self.node(root);
        if (original.tail != .parameter or original.tail.parameter != parameter) return root;
        return self.replaceTail(root, replacement_id);
    }
    fn replaceTail(self: *Store, root: Id, replacement_id: Id) Error!Id {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const scratch_allocator = scratch.allocator();
        const original = self.node(root);
        const replacement_ = self.node(replacement_id);
        var labels: std.ArrayList(Label) = .empty;
        defer labels.deinit(scratch_allocator);
        try labels.appendSlice(scratch_allocator, self.list(original.labels));
        try labels.appendSlice(scratch_allocator, self.list(replacement_.labels));
        const result = try self.row(labels.items, replacement_.tail);
        if (result != 0) self.rows.items[result].cursor = @max(original.cursor, replacement_.cursor);
        return result;
    }
    /// Reflection discards repeated labels; inference rows retain multiplicity.
    pub fn operationSet(self: *const Store, root: Id) Error![]Label {
        if (self.node(root).tail != .closed) return error.EffectMismatch;
        const labels = try self.allocator.dupe(Label, self.list(self.node(root).labels));
        errdefer self.allocator.free(labels);
        std.mem.sort(Label, labels, {}, std.sort.asc(Label));
        var distinct: usize = 0;
        for (labels) |label| {
            if (distinct != 0 and labels[distinct - 1] == label) continue;
            labels[distinct] = label;
            distinct += 1;
        }
        const result = try self.allocator.dupe(Label, labels[0..distinct]);
        self.allocator.free(labels);
        return result;
    }
};
