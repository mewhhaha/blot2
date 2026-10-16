//! Bounded checks of the public type/effect frontier. Executable bodies and an
//! opaque owner's private representation are deliberately separate inputs.
const std = @import("std");
const T = @import("../check/types.zig");
const F = @import("../check/frozen_types.zig");
const PI = @import("principal_interface.zig");
const Allocator = std.mem.Allocator;
pub const Error = Allocator.Error || error{TypeLimit};
pub const Scan = struct {
    allocator: Allocator,
    source: F.Source,
    blocked: std.AutoHashMapUnmanaged(T.NominalIdentity, void) = .empty,
    seen: std.AutoHashMapUnmanaged(Work, void) = .empty,
    work: std.ArrayList(Work) = .empty,
    remaining: usize = 1_000_000,
    const Work = struct { id: u32, row: bool = false };

    pub fn init(allocator: Allocator, source: F.Source, nominals: []const PI.Nominal, families: []const PI.EffectFamily, templates: []const PI.EffectTemplate) Error!Scan {
        var self: Scan = .{ .allocator = allocator, .source = source };
        errdefer self.deinit();
        for (nominals) |nominal| if (nominal.private and nominal.alias == 0) try self.blocked.put(allocator, nominal.identity, {});
        for (families) |family| if (family.private) try self.blocked.put(allocator, family.identity, {});
        for (templates) |operation| if (operation.family < families.len and families[operation.family].private) try self.blocked.put(allocator, operation.identity, {});
        return self;
    }
    pub fn deinit(self: *Scan) void {
        self.blocked.deinit(self.allocator);
        self.seen.deinit(self.allocator);
        self.work.deinit(self.allocator);
    }
    fn enqueue(self: *Scan, item: Work) Error!void {
        if (item.id == 0) return;
        const entry = try self.seen.getOrPut(self.allocator, item);
        if (entry.found_existing) return;
        if (self.remaining == 0) return error.TypeLimit;
        self.remaining -= 1;
        try self.work.append(self.allocator, item);
    }
    pub fn allowed(self: *Scan, root: T.Id) Error!bool {
        self.seen.clearRetainingCapacity();
        self.work.clearRetainingCapacity();
        try self.enqueue(.{ .id = root });
        while (self.work.pop()) |item| {
            if (item.row) {
                const row = self.source.row(item.id);
                for (self.source.rowLabels(row.labels)) |label| {
                    const operation = self.source.operation(label);
                    if (self.blocked.contains(operation.identity)) return false;
                    for (self.source.list(operation.arguments)) |argument| try self.enqueue(.{ .id = argument });
                }
                continue;
            }
            const n = self.source.node(self.source.head(item.id, 0));
            switch (n.tag) {
                .nominal, .projection, .type_constructor => {
                    if (self.blocked.contains(.{ .unit = n.a, .decl = n.b })) return false;
                    if (n.tag == .nominal or n.tag == .projection) for (self.source.nominalArguments(n)) |argument| try self.enqueue(.{ .id = argument });
                },
                .function => {
                    try self.enqueue(.{ .id = n.a });
                    try self.enqueue(.{ .id = n.b });
                    try self.enqueue(.{ .id = n.c, .row = true });
                },
                .demand, .provider => {
                    try self.enqueue(.{ .id = n.a });
                    try self.enqueue(.{ .id = n.c, .row = true });
                },
                .state_provider => {
                    try self.enqueue(.{ .id = n.a });
                    try self.enqueue(.{ .id = n.b });
                    try self.enqueue(.{ .id = n.c });
                },
                .usage, .array, .list, .cursor, .resolver => try self.enqueue(.{ .id = n.a }),
                .product => for (self.source.list(.{ .start = n.a, .len = n.b })) |child| try self.enqueue(.{ .id = child }),
                .record => for (0..n.b) |index| try self.enqueue(.{ .id = self.source.recordField(n, index).ty }),
                else => {},
            }
        }
        return true;
    }
};
