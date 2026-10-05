//! Dynamic provider scope shared by the evaluator and the Wasm representation.
//! Operation tokens belong to one closed semantic evidence catalog. They are
//! interned only after exact source identity and all shaped arguments are known.
//! Heads and cell IDs belong to this execution store and never enter a closure,
//! operation alias, immutable provider value, or exported semantic evidence.
const std = @import("std");
const effects = @import("effect_evidence.zig");
pub const Operation = effects.Label;
pub const Value = u32;
pub const Head = u32;
pub const CellId = u32;
pub const empty: Head = 0;
pub const Kind = enum(u32) { callback, state_read, state_write, request };
/// These four words are also the guest's provider-frame representation. Target
/// is a callable value for callback frames and a cell handle for state frames.
pub const Frame = extern struct {
    operation: Operation,
    target: u32,
    outer: Head,
    kind: Kind,
};
pub const Cell = extern struct { value: Value };
pub const Provider = extern struct { operation: Operation, implementation: Value };
pub const StateProvider = extern struct { read: Operation, write: Operation, initial: Value };
pub const Installation = struct { head: Head, cell: CellId };
pub const Match = struct { frame: Frame };
pub const Mark = struct { frames: usize, cells: usize };
pub const Error = std.mem.Allocator.Error || error{ InvalidOperation, SealedOperation, InvalidStateOperations, InvalidScope, ProviderLimit };

pub const Store = struct {
    allocator: std.mem.Allocator,
    frames: std.ArrayList(Frame) = .empty,
    cells: std.ArrayList(Cell) = .empty,

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Store) void {
        self.frames.deinit(self.allocator);
        self.cells.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn mark(self: *const Store) Mark {
        return .{ .frames = self.frames.items.len, .cells = self.cells.items.len };
    }
    /// Reclaim completed dynamic installations. Existing outer-cell writes are
    /// retained. The caller first saves any successor value, and must not keep
    /// an inner head/cell handle beyond this boundary. Ordinary values may escape.
    pub fn rewind(self: *Store, point: Mark) void {
        std.debug.assert(point.frames <= self.frames.items.len and point.cells <= self.cells.items.len);
        self.frames.shrinkRetainingCapacity(point.frames);
        self.cells.shrinkRetainingCapacity(point.cells);
    }
    pub fn installProvider(self: *Store, catalog: effects.View, outer: Head, provider: Provider) Error!Head {
        try self.validateHead(outer);
        try validateOperation(catalog, provider.operation);
        if (self.frames.items.len == std.math.maxInt(u32)) return error.ProviderLimit;
        try self.frames.append(self.allocator, .{ .operation = provider.operation, .target = provider.implementation, .outer = outer, .kind = .callback });
        return @intCast(self.frames.items.len);
    }
    /// Request targets are evaluator-owned handler identities. The callback
    /// and its runner-wide outer scope live in that handler's numeric record.
    pub fn installRequest(self: *Store, catalog: effects.View, outer: Head, operation: Operation, handler: u32) Error!Head {
        try self.validateHead(outer);
        try validateOperation(catalog, operation);
        if (self.frames.items.len == std.math.maxInt(u32)) return error.ProviderLimit;
        try self.frames.append(self.allocator, .{ .operation = operation, .target = handler, .outer = outer, .kind = .request });
        return @intCast(self.frames.items.len);
    }
    /// Installing a reusable provider always creates a fresh cell. Both frames
    /// share that installation's cell; neither mutates the provider's default.
    pub fn installState(self: *Store, catalog: effects.View, outer: Head, provider: StateProvider) Error!Installation {
        try self.validateHead(outer);
        try validateOperation(catalog, provider.read);
        try validateOperation(catalog, provider.write);
        if (provider.read == provider.write) return error.InvalidStateOperations;
        if (self.frames.items.len > std.math.maxInt(u32) - 2 or self.cells.items.len == std.math.maxInt(u32)) return error.ProviderLimit;
        // Reserve every allocation before publishing a cell or frame.
        try self.frames.ensureUnusedCapacity(self.allocator, 2);
        try self.cells.ensureUnusedCapacity(self.allocator, 1);
        const cell: CellId = @intCast(self.cells.items.len + 1);
        self.cells.appendAssumeCapacity(.{ .value = provider.initial });
        self.frames.appendAssumeCapacity(.{ .operation = provider.write, .target = cell, .outer = outer, .kind = .state_write });
        const write_head: Head = @intCast(self.frames.items.len);
        self.frames.appendAssumeCapacity(.{ .operation = provider.read, .target = cell, .outer = write_head, .kind = .state_read });
        return .{ .head = @intCast(self.frames.items.len), .cell = cell };
    }
    /// Copy the matched frame, so no borrowed array element survives growth.
    /// A callback must run under result.frame.outer, excluding the matched frame
    /// and every younger installation. Unrelated operations forward unchanged.
    pub fn lookup(self: *const Store, head: Head, operation: Operation) Error!?Match {
        try self.validateHead(head);
        var cursor = head;
        while (cursor != empty) {
            const frame = self.frames.items[cursor - 1];
            if (frame.operation == operation) return .{ .frame = frame };
            cursor = frame.outer;
        }
        return null;
    }
    pub fn read(self: *const Store, cell: CellId) Error!Value {
        if (cell == 0 or cell > self.cells.items.len) return error.InvalidScope;
        return self.cells.items[cell - 1].value;
    }
    pub fn write(self: *Store, cell: CellId, value: Value) Error!void {
        if (cell == 0 or cell > self.cells.items.len) return error.InvalidScope;
        self.cells.items[cell - 1].value = value;
    }
    fn validateHead(self: *const Store, head: Head) Error!void {
        if (head > self.frames.items.len) return error.InvalidScope;
    }
};

fn validateOperation(catalog: effects.View, operation: Operation) Error!void {
    if (operation == 0 or operation >= catalog.operations.len) return error.InvalidOperation;
    const identity = catalog.operation(operation).identity;
    if (identity.decl == 0) return error.InvalidOperation;
    if (identity.unit == 0 and identity.decl == 1) return error.SealedOperation;
}

test "matching a provider excludes itself and all younger scopes" {
    var catalog = try effects.Store.init(std.testing.allocator);
    defer catalog.deinit();
    const read = try catalog.internOperation(.{ .unit = 2, .decl = 3 }, &.{4});
    const other = try catalog.internOperation(.{ .unit = 2, .decl = 5 }, &.{});
    // The same phantom representation with a different semantic argument is a
    // different operation; tokens come from semantic evidence, not ABI layout.
    const different = try catalog.internOperation(.{ .unit = 2, .decl = 3 }, &.{6});
    var chain = Store.init(std.testing.allocator);
    defer chain.deinit();
    const outer = try chain.installProvider(catalog.view(), empty, .{ .operation = read, .implementation = 10 });
    const forwarding = try chain.installProvider(catalog.view(), outer, .{ .operation = other, .implementation = 20 });
    const younger = try chain.installProvider(catalog.view(), forwarding, .{ .operation = read, .implementation = 30 });
    const found = (try chain.lookup(younger, other)).?;
    try std.testing.expectEqual(20, found.frame.target);
    try std.testing.expectEqual(outer, found.frame.outer);
    const forwarded = (try chain.lookup(found.frame.outer, read)).?;
    try std.testing.expectEqual(10, forwarded.frame.target);
    try std.testing.expect((try chain.lookup(found.frame.outer, different)) == null);
    const same = (try chain.lookup(younger, read)).?;
    try std.testing.expectEqual(30, same.frame.target);
    try std.testing.expectEqual(forwarding, same.frame.outer);
    try std.testing.expectEqual(10, (try chain.lookup(same.frame.outer, read)).?.frame.target);
}

fn stateScenario(allocator: std.mem.Allocator) !void {
    var catalog = try effects.Store.init(allocator);
    defer catalog.deinit();
    const read = try catalog.internOperation(.{ .unit = 2, .decl = 3 }, &.{4});
    const write = try catalog.internOperation(.{ .unit = 2, .decl = 5 }, &.{4});
    const foreign = try catalog.internOperation(.{ .unit = 0, .decl = 1 }, &.{});
    var chain = Store.init(allocator);
    defer chain.deinit();
    const provider = StateProvider{ .read = read, .write = write, .initial = 41 };
    const before = chain.mark();
    const first = chain.installState(catalog.view(), empty, provider) catch |err| {
        try std.testing.expectEqualDeep(before, chain.mark());
        return err;
    };
    try std.testing.expectEqual(41, try chain.read(first.cell));
    const nested_mark = chain.mark();
    const second = chain.installState(catalog.view(), first.head, provider) catch |err| {
        try std.testing.expectEqualDeep(nested_mark, chain.mark());
        return err;
    };
    try std.testing.expect(first.cell != second.cell);
    try chain.write(second.cell, 42);
    try std.testing.expectEqual(41, try chain.read(first.cell));
    try std.testing.expectEqual(42, try chain.read(second.cell));
    const read_frame = (try chain.lookup(second.head, read)).?.frame;
    const write_frame = (try chain.lookup(second.head, write)).?.frame;
    try std.testing.expectEqual(Kind.state_read, read_frame.kind);
    try std.testing.expectEqual(Kind.state_write, write_frame.kind);
    try std.testing.expectEqual(second.cell, read_frame.target);
    try std.testing.expectEqual(second.cell, write_frame.target);
    try std.testing.expectEqual(first.head, write_frame.outer);
    // Mutations forwarded into an older cell survive inner-scope reclamation.
    try chain.write(first.cell, 43);
    const snapshot = try chain.read(second.cell);
    chain.rewind(nested_mark);
    try std.testing.expectEqual(43, try chain.read(first.cell));
    try std.testing.expectEqual(42, snapshot);
    try std.testing.expectEqual(41, provider.initial);
    try std.testing.expectError(error.InvalidScope, chain.read(second.cell));
    const invalid_mark = chain.mark();
    try std.testing.expectError(error.InvalidStateOperations, chain.installState(catalog.view(), first.head, .{ .read = read, .write = read, .initial = 0 }));
    try std.testing.expectError(error.SealedOperation, chain.installProvider(catalog.view(), first.head, .{ .operation = foreign, .implementation = 0 }));
    try std.testing.expectEqualDeep(invalid_mark, chain.mark());
    chain.rewind(before);
}

test "state installations isolate defaults, preserve snapshots, and publish atomically" {
    try stateScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, stateScenario, .{});
}
