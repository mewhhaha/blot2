//! Deferred physical copies for an already checked, untagged Value join.
//! Every unresolved edge occupies two neutral instructions until final assembly.
const std = @import("std");
const Code = @import("runtime_code.zig").Code;
const Local = @import("runtime_code.zig").Local;
const outline = @import("wasm_scope_outline.zig");
const A = std.mem.Allocator;
pub const Lane = struct {
    first: Local,
    carrier: ?Local = null,
    holes: std.ArrayList(usize) = .empty,
};
pub const Join = struct {
    entry_locals: usize,
    edges: usize = 0,
    lanes: []Lane = &.{},
    pub fn init(code: Code) Join {
        const function = &code.module.functions.items[code.function];
        return .{ .entry_locals = function.parameters.len + function.locals.items.len };
    }
    fn materialize(lane: *Lane, arena: A, code: Code, context: *outline.Context) outline.Error!void {
        _ = arena;
        if (lane.carrier != null) return;
        const carrier = try code.temp();
        for (lane.holes.items) |index| try context.patchCopy(code.function, index, lane.first.id, carrier.id);
        lane.holes.clearRetainingCapacity();
        lane.carrier = carrier;
    }
    pub fn add(self: *Join, arena: A, code: Code, context: *outline.Context, words: []const Local) outline.Error!void {
        if (self.edges == 0) {
            self.lanes = try arena.alloc(Lane, words.len);
            for (self.lanes, words) |*lane, incoming| lane.* = .{ .first = incoming };
        }
        if (words.len != self.lanes.len) return error.InvalidOutline;
        for (self.lanes, words) |*lane, incoming| {
            // Only a dominating local can have one physical origin on multiple
            // edges. A sole continuing edge may retain its branch-local words.
            if (self.edges != 0 and (lane.first.id != incoming.id or lane.first.id >= self.entry_locals))
                try materialize(lane, arena, code, context);
            if (lane.carrier) |carrier| {
                try code.set(carrier, incoming);
            } else {
                try lane.holes.ensureUnusedCapacity(arena, 1);
                const index = try context.reserveCopy(code.function);
                lane.holes.appendAssumeCapacity(index);
            }
        }
        self.edges += 1;
    }
    pub fn finish(self: *Join, arena: A, code: Code, context: *outline.Context, mutable: *const std.AutoHashMapUnmanaged(u32, void), fallthrough: bool) outline.Error!u64 {
        var shared: u64 = 0;
        for (self.lanes) |*lane| {
            // Default locals preserve the ordinary zero result on normal
            // fallthrough. Mutable locals must be captured at the edge, before
            // owner close or a loop backedge can overwrite them.
            if (fallthrough or mutable.contains(lane.first.id)) try materialize(lane, arena, code, context);
            if (lane.carrier == null) {
                for (lane.holes.items) |index| try context.releaseCopy(code.function, index);
                lane.holes.clearRetainingCapacity();
                shared += self.edges;
            }
        }
        return shared;
    }
    pub fn word(self: Join, index: usize) Local {
        const lane = self.lanes[index];
        return lane.carrier orelse lane.first;
    }
};

test {
    _ = @import("storage_deferred_join_tests.zig");
}
