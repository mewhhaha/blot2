//! Private observations of actual backend requests and instructions. Body
//! completion is separate from semantic occurrence coverage; no observation
//! licenses storage, source-query or evaluation reuse.
const std = @import("std");
const wasm = @import("wasm.zig");
const Allocator = std.mem.Allocator;
pub const none = std.math.maxInt(u32);
pub const Origin = enum { named, anonymous, runtime_initializer };
pub const Header = struct { function: u32, origin: Origin, unit: u32, identity: u32, complete: bool = false };
pub const Kind = enum { request, runtime_global_request, cell_registration, retained_value, cached_demand, direct_call, imported_call, indirect_call_unknown, global_read };
pub const Event = struct { kind: Kind, caller: u32 = none, target: u32 = none, unit: u32 = 0, identity: u32 = 0, auxiliary: u32 = 0, flag: bool = false };
pub const Snapshot = struct {
    headers: []Header,
    events: []Event,
    pub fn deinit(self: *Snapshot, a: Allocator) void {
        a.free(self.headers);
        a.free(self.events);
        self.* = undefined;
    }
};
pub const Store = struct {
    enabled: bool = false,
    active: u32 = none,
    headers: std.ArrayList(Header) = .empty,
    events: std.ArrayList(Event) = .empty,
    pub fn deinit(self: *Store, a: Allocator) void {
        self.headers.deinit(a);
        self.events.deinit(a);
        self.* = .{};
    }
    pub fn event(self: *Store, a: Allocator, value: Event) Allocator.Error!void {
        if (self.enabled) try self.events.append(a, value);
    }
    pub fn request(self: *Store, a: Allocator, function: u32, origin: Origin, unit: u32, identity: u32, hit: bool) Allocator.Error!void {
        if (!self.enabled) return;
        try self.event(a, .{ .kind = .request, .caller = self.active, .target = function, .unit = unit, .identity = identity, .flag = hit });
        if (!hit) try self.headers.append(a, .{ .function = function, .origin = origin, .unit = unit, .identity = identity });
    }
    pub fn complete(self: *Store, function: u32) void {
        if (!self.enabled) return;
        for (self.headers.items) |*header| if (header.function == function) {
            header.complete = true;
            return;
        };
    }
    pub fn capture(self: *const Store, a: Allocator, module: *const wasm.Module) Allocator.Error!Snapshot {
        const headers = try a.dupe(Header, self.headers.items);
        errdefer a.free(headers);
        var events: std.ArrayList(Event) = .empty;
        errdefer events.deinit(a);
        try events.appendSlice(a, self.events.items);
        // Scan the actual instruction owners, including direct module.emit
        // paths and wrappers. Indirect/imported calls remain explicit unknowns
        // until a separate semantic flow/operation contract covers them.
        for (module.functions.items, 0..) |function, owner| {
            for (function.instructions.items, 0..) |instruction, ordinal| {
                const kind: Kind = switch (instruction.op) {
                    .call => .direct_call,
                    .call_import => .imported_call,
                    .call_indirect => .indirect_call_unknown,
                    .global_get => .global_read,
                    else => continue,
                };
                try events.append(a, .{ .kind = kind, .caller = @intCast(owner), .target = instruction.operand, .auxiliary = @intCast(ordinal) });
            }
        }
        return .{ .headers = headers, .events = try events.toOwnedSlice(a) };
    }
};
