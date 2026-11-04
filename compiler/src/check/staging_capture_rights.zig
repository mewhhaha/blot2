//! Future-local captures require actual lifetime edges from a complete scope
//! execution. Stage equality and a callable's type supply no capture authority.
const std = @import("std");
const core = @import("core.zig");
const lifetimes = @import("capability_lifetimes.zig");
const A = std.mem.Allocator;
const Error = A.Error || error{InvalidArtifact};
fn require(value: bool) Error!void {
    if (!value) return error.InvalidArtifact;
}
pub const Checker = struct {
    allocator: ?A,
    module: *const core.Module,
    units: []const *const core.Module,
    remaining: *usize,
    reports: std.ArrayList(struct { scope: core.Id, report: lifetimes.Report }) = .empty,

    pub fn deinit(self: *Checker) void {
        const allocator = self.allocator orelse return;
        for (self.reports.items) |*entry| entry.report.deinit(allocator);
        self.reports.deinit(allocator);
    }
    fn step(self: *Checker) Error!void {
        try require(self.remaining.* != 0);
        self.remaining.* -= 1;
    }
    fn report(self: *Checker, root: core.Id) Error!*const lifetimes.Report {
        for (self.reports.items) |*entry| {
            try self.step();
            if (entry.scope == root) return &entry.report;
        }
        // The scratch-only validator cannot allocate the lifetime reader's
        // owned workspace. Such graphs use validateWithBudget instead.
        const allocator = self.allocator orelse return error.InvalidArtifact;
        var result = lifetimes.analyzeScope(allocator, self.module, self.units, root, self.remaining) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.InvalidArtifact;
        };
        errdefer result.deinit(allocator);
        try require(result.complete);
        try self.reports.append(allocator, .{ .scope = root, .report = result });
        return &self.reports.items[self.reports.items.len - 1].report;
    }
    fn confined(self: *Checker, image: *const lifetimes.Report, value: lifetimes.Id, scopes: []const core.Id) Error!void {
        const allocator = self.allocator orelse return error.InvalidArtifact;
        var work: std.ArrayList(lifetimes.Id) = .empty;
        defer work.deinit(allocator);
        var seen: std.AutoHashMapUnmanaged(lifetimes.Id, void) = .empty;
        defer seen.deinit(allocator);
        try work.append(allocator, value);
        while (work.pop()) |current| {
            try self.step();
            try require(current < image.nodes.len);
            const entry = try seen.getOrPut(allocator, current);
            if (entry.found_existing) continue;
            const node = image.nodes[current];
            try require(node.kind != .unknown and node.kind != .external);
            if (node.kind == .capability) {
                try require(node.owner < image.nodes.len);
                const owner = image.nodes[node.owner];
                try require(owner.kind == .scope and owner.site.unit == self.module.unit);
                try require(std.mem.findScalar(core.Id, scopes, owner.site.node) != null);
            }
            var next = node.first_edge;
            while (next) |index| {
                try self.step();
                try require(index < image.edges.len);
                const edge = image.edges[index];
                try require(edge.from == current);
                try work.append(allocator, edge.to);
                next = edge.next;
            }
            if (node.contents != 0) try work.append(allocator, node.contents);
        }
    }
    fn loanCapture(self: *Checker, closure: core.Id, binding: core.BindingId, loans: []const core.Id) Error!bool {
        const T = @import("types.zig");
        const borrowed = self.module.types.node(self.module.bindings[binding].ty);
        if (borrowed.tag != .usage or (borrowed.b != @backingInt(T.UsageKind.borrow) and borrowed.b != @backingInt(T.UsageKind.borrow_mut)) or borrowed.c == 0) return false;
        const region = self.module.types.node(borrowed.c);
        if (region.tag != .bound or region.a != 0 or region.b != 2 or region.c != binding) return false;
        for (loans) |site| {
            try self.step();
            const node = self.module.node(site);
            var callback_id: core.Id = 0;
            if (node.tag == .usage_borrow) callback_id = node.b;
            if (node.tag == .resource_scope) callback_id = node.c;
            try require(callback_id != 0 and self.module.node(callback_id).tag == .closure);
            const callback = self.module.closure(callback_id);
            if (callback.parameter.binding != binding or callback.parameter.ty != self.module.bindings[binding].ty) continue;
            // Bounds admission already ran the complete usage/loan proof.
            // This lexical callback supplies the region; an actual body read
            // independently supplies the capture edge.
            return try @import("usage_core.zig").physicallyCaptures(self.module, self.module.closures[self.module.node(closure).a].body, binding, self.remaining);
        }
        return false;
    }
    pub fn requireLoanCaptures(self: *Checker, closure: core.Id, loans: []const core.Id) Error!void {
        const callback = self.module.closures[self.module.node(closure).a];
        const captures = self.module.extra[callback.captures.start..][0..callback.captures.len];
        for (loans) |site| {
            try self.step();
            const node = self.module.node(site);
            var owner_id = node.b;
            if (node.tag == .resource_scope) owner_id = node.c;
            const owner = self.module.closure(owner_id);
            const binding = owner.parameter.binding;
            if (binding == callback.parameter.binding) continue;
            if (try @import("usage_core.zig").physicallyCaptures(self.module, callback.body, binding, self.remaining)) {
                try require(std.mem.findScalar(core.BindingId, captures, binding) != null);
            }
        }
    }
    pub fn capture(self: *Checker, closure: core.Id, binding: core.BindingId, scopes: []const core.Id, loans: []const core.Id) Error!void {
        if (try self.loanCapture(closure, binding, loans)) return;
        if (scopes.len == 0) return error.InvalidArtifact;
        const image = try self.report(scopes[0]);
        const catalog = self.module.node(closure).a;
        var found = false;
        for (image.nodes, 0..) |node, value| {
            try self.step();
            if (node.site.unit != self.module.unit or node.site.node != closure or node.closure != catalog) continue;
            var captured = false;
            var next = node.first_edge;
            while (next) |index| {
                try self.step();
                try require(index < image.edges.len);
                const edge = image.edges[index];
                try require(edge.from == value);
                next = edge.next;
                if (edge.kind != .capture or edge.field != binding) continue;
                try self.confined(image, edge.to, scopes);
                captured = true;
            }
            try require(captured);
            found = true;
        }
        try require(found);
    }
};
