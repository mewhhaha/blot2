//! Dynamic provider scope shared by the evaluator and the Wasm representation.
//! Operation tokens belong to one closed semantic evidence catalog. They are
//! interned only after exact source identity and all shaped arguments are known.
//! Heads and cell IDs belong to this execution store and never enter a closure,
//! operation alias, immutable provider value, or exported semantic evidence.
const std = @import("std");
const effects = @import("effect_evidence.zig");
const authority = @import("effect_authority.zig");
pub const Operation = effects.Label;
pub const Authority = authority.Handle;
pub const Key = struct {
    operation: Operation,
    owner: Authority = .static,
    pub fn same(left: Key, right: Key) bool {
        return left.operation == right.operation and left.owner == right.owner;
    }
};
pub const Value = u32;
pub const Head = u32;
pub const CellId = u32;
pub const empty: Head = 0;
const heap = @import("runtime_layout.zig");
pub const Kind = heap.ProviderKind;
/// These four words are also the guest's provider-frame representation. Target
/// is a callable value for callback frames and a cell handle for state frames.
pub const Frame = heap.ProviderFrame;
pub const Cell = heap.StateCell;
pub const Provider = heap.Provider;
pub const StateProvider = heap.StateProvider;
pub const Installation = struct { head: Head, cell: CellId };
pub const Match = struct { frame: Frame };
pub const Mark = struct { frames: usize, cells: usize };
pub const Error = authority.Error || error{ InvalidOperation, SealedOperation, InvalidStateOperations, InvalidScope, ProviderLimit };
/// Lives in the owning computation/continuation, independently of native stack
/// entry. Suspending preserves this record; termination revokes all its scopes.
pub const Activation = struct {
    scopes: std.ArrayList(Authority) = .empty,
    pub fn deinit(self: *Activation, store: *Store) void {
        self.end(store);
        self.scopes.deinit(store.allocator);
        self.* = undefined;
    }
    pub fn end(self: *Activation, store: *Store) void {
        while (self.scopes.pop()) |owner| store.authorities.end(owner) catch unreachable;
    }
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    frames: std.ArrayList(Frame) = .empty,
    cells: std.ArrayList(Cell) = .empty,
    authorities: authority.Store,
    // Static frames retain their existing four-word representation. Scoped
    // identities are execution-local owned edges, independent of cells/heads.
    frame_owners: std.AutoHashMapUnmanaged(Head, Authority) = .empty,

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{ .allocator = allocator, .authorities = authority.Store.init(allocator) };
    }
    pub fn deinit(self: *Store) void {
        self.frames.deinit(self.allocator);
        self.cells.deinit(self.allocator);
        self.frame_owners.deinit(self.allocator);
        self.authorities.deinit();
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
        if (self.frame_owners.count() != 0) {
            var head = self.frames.items.len;
            while (head > point.frames) : (head -= 1) {
                if (self.frame_owners.fetchRemove(@intCast(head))) |entry|
                    self.authorities.release(entry.value) catch unreachable;
            }
        }
        self.frames.shrinkRetainingCapacity(point.frames);
        self.cells.shrinkRetainingCapacity(point.cells);
    }
    /// Register terminal cleanup before publishing the fresh handle. Suspension
    /// leaves this stack untouched; the owning activation ends its entries.
    pub fn beginScope(self: *Store, activation: *Activation) Error!Authority {
        try activation.scopes.ensureUnusedCapacity(self.allocator, 1);
        const owner = try self.authorities.begin();
        activation.scopes.appendAssumeCapacity(owner);
        return owner;
    }
    pub fn endScope(self: *Store, activation: *Activation, owner: Authority) Error!void {
        if (activation.scopes.items.len == 0 or activation.scopes.items[activation.scopes.items.len - 1] != owner) return error.InvalidScope;
        try self.authorities.end(owner);
        _ = activation.scopes.pop();
    }
    pub fn retainAuthority(self: *Store, owner: Authority) Error!void {
        try self.authorities.retain(owner);
    }
    pub fn releaseAuthority(self: *Store, owner: Authority) Error!void {
        try self.authorities.release(owner);
    }
    pub fn installProvider(self: *Store, catalog: effects.View, outer: Head, provider: Provider) Error!Head {
        return self.installProviderKey(catalog, outer, .{ .operation = provider.operation }, provider.implementation);
    }
    pub fn installProviderKey(self: *Store, catalog: effects.View, outer: Head, key: Key, implementation: Value) Error!Head {
        try self.validateHead(outer);
        try validateOperation(catalog, key.operation);
        try self.authorities.requireActive(key.owner);
        if (self.frames.items.len == std.math.maxInt(u32)) return error.ProviderLimit;
        try self.frames.ensureUnusedCapacity(self.allocator, 1);
        const head: Head = @intCast(self.frames.items.len + 1);
        try self.retainFrame(head, key.owner);
        self.frames.appendAssumeCapacity(.{ .operation = key.operation, .target = implementation, .outer = outer, .kind = .callback });
        return @intCast(self.frames.items.len);
    }
    /// Request targets are evaluator-owned handler identities. The callback
    /// and its runner-wide outer scope live in that handler's numeric record.
    pub fn installRequest(self: *Store, catalog: effects.View, outer: Head, operation: Operation, handler: u32) Error!Head {
        return self.installRequestKey(catalog, outer, .{ .operation = operation }, handler);
    }
    pub fn installRequestKey(self: *Store, catalog: effects.View, outer: Head, key: Key, handler: u32) Error!Head {
        try self.validateHead(outer);
        try validateOperation(catalog, key.operation);
        try self.authorities.requireActive(key.owner);
        if (self.frames.items.len == std.math.maxInt(u32)) return error.ProviderLimit;
        try self.frames.ensureUnusedCapacity(self.allocator, 1);
        const head: Head = @intCast(self.frames.items.len + 1);
        try self.retainFrame(head, key.owner);
        self.frames.appendAssumeCapacity(.{ .operation = key.operation, .target = handler, .outer = outer, .kind = .request });
        return @intCast(self.frames.items.len);
    }
    /// Installing a reusable provider always creates a fresh cell. Both frames
    /// share that installation's cell; neither mutates the provider's default.
    pub fn installState(self: *Store, catalog: effects.View, outer: Head, provider: StateProvider) Error!Installation {
        return self.installStateKeys(catalog, outer, .{ .operation = provider.read }, .{ .operation = provider.write }, provider.initial);
    }
    pub fn installStateKeys(self: *Store, catalog: effects.View, outer: Head, read_key: Key, write_key: Key, initial: Value) Error!Installation {
        try self.validateHead(outer);
        try validateOperation(catalog, read_key.operation);
        try validateOperation(catalog, write_key.operation);
        try self.authorities.requireActive(read_key.owner);
        try self.authorities.requireActive(write_key.owner);
        if (Key.same(read_key, write_key) or read_key.owner != write_key.owner) return error.InvalidStateOperations;
        if (self.frames.items.len > std.math.maxInt(u32) - 2 or self.cells.items.len == std.math.maxInt(u32)) return error.ProviderLimit;
        // Reserve every allocation before publishing a cell or frame.
        try self.frames.ensureUnusedCapacity(self.allocator, 2);
        try self.cells.ensureUnusedCapacity(self.allocator, 1);
        const write_head: Head = @intCast(self.frames.items.len + 1);
        try self.retainFrame(write_head, write_key.owner);
        errdefer self.releaseFrame(write_head);
        try self.retainFrame(write_head + 1, read_key.owner);
        const cell: CellId = @intCast(self.cells.items.len + 1);
        self.cells.appendAssumeCapacity(.{ .value = initial });
        self.frames.appendAssumeCapacity(.{ .operation = write_key.operation, .target = cell, .outer = outer, .kind = .state_write });
        self.frames.appendAssumeCapacity(.{ .operation = read_key.operation, .target = cell, .outer = write_head, .kind = .state_read });
        return .{ .head = @intCast(self.frames.items.len), .cell = cell };
    }
    /// Copy the matched frame, so no borrowed array element survives growth.
    /// A callback must run under result.frame.outer, excluding the matched frame
    /// and every younger installation. Unrelated operations forward unchanged.
    pub fn lookup(self: *const Store, head: Head, operation: Operation) Error!?Match {
        return self.lookupKey(head, .{ .operation = operation });
    }
    pub fn lookupKey(self: *const Store, head: Head, key: Key) Error!?Match {
        // Permission fails before any provider lookup, even if an old frame
        // still owns the revoked identity.
        try self.authorities.requireActive(key.owner);
        try self.validateHead(head);
        var cursor = head;
        while (cursor != empty) {
            const frame = self.frames.items[cursor - 1];
            if (frame.operation == key.operation) {
                var owner: Authority = .static;
                if (self.frame_owners.count() != 0) owner = self.frame_owners.get(cursor) orelse .static;
                if (owner == key.owner) return .{ .frame = frame };
            }
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
    fn retainFrame(self: *Store, head: Head, owner: Authority) Error!void {
        if (owner == .static) return;
        try self.frame_owners.ensureUnusedCapacity(self.allocator, 1);
        try self.authorities.retain(owner);
        self.frame_owners.putAssumeCapacity(head, owner);
    }
    fn releaseFrame(self: *Store, head: Head) void {
        if (self.frame_owners.fetchRemove(head)) |entry|
            self.authorities.release(entry.value) catch unreachable;
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

fn scopedScenario(allocator: std.mem.Allocator) !void {
    var catalog = try effects.Store.init(allocator);
    defer catalog.deinit();
    const read = try catalog.internOperation(.{ .unit = 2, .decl = 3 }, &.{4});
    const write = try catalog.internOperation(.{ .unit = 2, .decl = 5 }, &.{4});
    var chain = Store.init(allocator);
    defer chain.deinit();
    var outer_activation: Activation = .{};
    defer outer_activation.deinit(&chain);
    var inner_activation: Activation = .{};
    defer inner_activation.deinit(&chain);
    const before = chain.mark();
    defer {
        inner_activation.end(&chain);
        outer_activation.end(&chain);
        chain.rewind(before);
    }
    const left = try chain.beginScope(&outer_activation);
    const right = try chain.beginScope(&inner_activation);
    try std.testing.expect(left != right);
    const left_read: Key = .{ .operation = read, .owner = left };
    const left_write: Key = .{ .operation = write, .owner = left };
    const right_read: Key = .{ .operation = read, .owner = right };
    const right_write: Key = .{ .operation = write, .owner = right };
    const first = try chain.installStateKeys(catalog.view(), empty, left_read, left_write, 10);
    const point = chain.mark();
    const second = chain.installStateKeys(catalog.view(), first.head, right_read, right_write, 100) catch |err| {
        try std.testing.expectEqualDeep(point, chain.mark());
        return err;
    };
    try std.testing.expect(first.cell != second.cell);
    try std.testing.expectEqual(first.cell, (try chain.lookupKey(second.head, left_read)).?.frame.target);
    try std.testing.expectEqual(second.cell, (try chain.lookupKey(second.head, right_read)).?.frame.target);
    try std.testing.expect((try chain.lookup(second.head, read)) == null);
    try chain.write((try chain.lookupKey(second.head, left_write)).?.frame.target, 11);
    try chain.write((try chain.lookupKey(second.head, right_write)).?.frame.target, 102);
    try std.testing.expectEqual(11, try chain.read(first.cell));
    try std.testing.expectEqual(102, try chain.read(second.cell));
    // One alias shadows its own owner. Its callback forwards under the matched
    // frame's outer chain, which excludes itself and all younger installations.
    const callback = try chain.installProviderKey(catalog.view(), second.head, left_read, 20);
    const request = try chain.installRequestKey(catalog.view(), callback, right_read, 30);
    const matched = (try chain.lookupKey(request, left_read)).?.frame;
    try std.testing.expectEqual(20, matched.target);
    try std.testing.expectEqual(second.head, matched.outer);
    try std.testing.expectEqual(first.cell, (try chain.lookupKey(matched.outer, left_read)).?.frame.target);
    try std.testing.expectEqual(30, (try chain.lookupKey(request, right_read)).?.frame.target);
    try std.testing.expectError(error.InvalidStateOperations, chain.installStateKeys(catalog.view(), request, left_read, right_write, 0));
    // An outstanding alias and all provider frames retain identity after scope
    // termination, while no one may invoke or reinstall its revoked operation.
    try chain.retainAuthority(right);
    var alias_owned = true;
    defer if (alias_owned) chain.releaseAuthority(right) catch unreachable;
    inner_activation.end(&chain);
    inner_activation.end(&chain);
    try std.testing.expectError(error.InactiveAuthority, chain.lookupKey(request, right_read));
    try std.testing.expectError(error.InactiveAuthority, chain.installProviderKey(catalog.view(), request, right_read, 0));
    try std.testing.expectEqual(first.cell, (try chain.lookupKey(matched.outer, left_read)).?.frame.target);
    outer_activation.end(&chain);
    // Revocation precedes retirement; ending twice is harmless.
    try std.testing.expectEqual(0, chain.authorities.active);
    chain.rewind(before);
    try std.testing.expectEqual(1, chain.authorities.live);
    try chain.releaseAuthority(right);
    alias_owned = false;
    try std.testing.expectError(error.InvalidAuthority, chain.retainAuthority(left));
    const retry = try chain.beginScope(&inner_activation);
    try std.testing.expect(retry != left and retry != right);
    try chain.retainAuthority(retry);
    inner_activation.end(&chain);
    try chain.releaseAuthority(retry);
    try std.testing.expectEqual(0, chain.authorities.live);
}

test "scoped provider keys route same-typed owners and revoke before retirement" {
    try scopedScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scopedScenario, .{});
}
