//! Owns physical layouts and backend substitution identities. The bridge borrows
//! live semantic evidence and is bound lazily after this owner has a stable
//! address; it is destroyed before either evidence or layouts are released.
const std = @import("std");
const core = @import("../check/core.zig");
const layout = @import("layout.zig");
const layout_bridge = @import("layout_bridge.zig");
const type_evidence = @import("../eval/type_evidence.zig");
const substitution_keys = @import("../reuse/substitution_keys.zig");
const Allocator = std.mem.Allocator;
pub const State = struct {
    store: layout.Store,
    connection: ?layout_bridge.Store = null,
    row_keys: substitution_keys.Store,
    template_keys: substitution_keys.Store,
    static_keys: substitution_keys.Store,
    instance_arguments: @import("../eval/instance_arguments.zig").Store = .{},
    pub fn init(a: Allocator, units: []const core.Module) error{ OutOfMemory, Declined }!State {
        var store = layout.Store.init(a) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => unreachable,
        };
        errdefer store.deinit();
        store.opaque_sources = units;
        for (units) |*unit| store.record_names.add(a, unit) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.TypeMismatch => return error.Declined,
        };
        return fromStore(a, store);
    }
    pub fn fromStore(a: Allocator, store: layout.Store) State {
        return .{ .store = store, .row_keys = .init(a), .template_keys = .init(a), .static_keys = .init(a) };
    }
    pub fn deinit(self: *State, a: Allocator) void {
        if (self.connection) |*bridge| bridge.deinit();
        self.store.deinit();
        self.row_keys.deinit();
        self.template_keys.deinit();
        self.static_keys.deinit();
        self.instance_arguments.deinit(a);
    }
    pub fn representationBridge(self: *State, evidence: *type_evidence.Store) Allocator.Error!*layout_bridge.Store {
        // Bind only after init has returned and the Generator has a stable address.
        if (self.connection == null) self.connection = try layout_bridge.Store.init(self.store.allocator, &self.store, evidence);
        return &self.connection.?;
    }
    pub fn toEvidence(self: *State, evidence: *type_evidence.Store, id: layout.Id) type_evidence.Error!type_evidence.Id {
        return @backingInt(try (try self.representationBridge(evidence)).toEvidence(@fromBackingInt(@intCast(id))));
    }
    pub fn fromEvidence(self: *State, evidence: *type_evidence.Store, id: type_evidence.Id) layout.Error!layout.Id {
        return @backingInt(try (try self.representationBridge(evidence)).fromEvidence(@fromBackingInt(@intCast(id))));
    }
    pub fn rowToEvidence(self: *State, evidence: *type_evidence.Store, id: type_evidence.Effects.Id) type_evidence.Error!type_evidence.Effects.Id {
        return @backingInt(try (try self.representationBridge(evidence)).rowToEvidence(@fromBackingInt(@intCast(id))));
    }
    pub fn rowFromEvidence(self: *State, evidence: *type_evidence.Store, id: type_evidence.Effects.Id) layout.Error!type_evidence.Effects.Id {
        return @backingInt(try (try self.representationBridge(evidence)).rowFromEvidence(@fromBackingInt(@intCast(id))));
    }
};
