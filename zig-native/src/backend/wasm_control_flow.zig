//! Instruction-level control flow for ownership. Structured labels resolve to
//! their common `end` node; a loop label resolves to the start of its body.
//! The synthetic final node is the function exit. Predecessors are flat links,
//! so backward lifetime walks visit only the part of a body that is live.
const std = @import("std");
const w = @import("wasm.zig");
const A = std.mem.Allocator;
pub const absent = std.math.maxInt(u32);
pub const Node = struct { next: [2]u32 = .{ absent, absent }, first: u32 = absent };
const Predecessor = struct { from: u32, next: u32 };
const Control = struct { start: u32, alternate: u32 = absent };

pub const Graph = struct {
    nodes: []Node,
    predecessors: std.ArrayList(Predecessor) = .empty,
    valid: bool = true,

    pub fn init(a: A, instructions: []const w.Instruction) !Graph {
        var graph: Graph = .{ .nodes = try a.alloc(Node, instructions.len + 1) };
        errdefer graph.deinit(a);
        @memset(graph.nodes, .{});
        const ends = try a.alloc(u32, instructions.len);
        defer a.free(ends);
        @memset(ends, absent);
        var controls: std.ArrayList(Control) = .empty;
        defer controls.deinit(a);
        // Match controls before resolving forward branches.
        for (instructions, 0..) |inst, index| {
            const at: u32 = @intCast(index);
            switch (inst.op) {
                .block, .loop, .if_ => try controls.append(a, .{ .start = at }),
                .else_ => {
                    if (controls.items.len == 0) {
                        graph.valid = false;
                        return graph;
                    }
                    const control = &controls.items[controls.items.len - 1];
                    if (instructions[control.start].op != .if_ or control.alternate != absent) {
                        graph.valid = false;
                        return graph;
                    }
                    control.alternate = at;
                    graph.nodes[control.start].next[1] = at + 1;
                },
                .end => {
                    const control = controls.pop() orelse {
                        graph.valid = false;
                        return graph;
                    };
                    ends[control.start] = at;
                    if (control.alternate != absent) ends[control.alternate] = at;
                },
                else => {},
            }
        }
        if (controls.items.len != 0) {
            graph.valid = false;
            return graph;
        }
        for (instructions, 0..) |inst, index| {
            const at: u32 = @intCast(index);
            const node = &graph.nodes[at];
            node.next[0] = at + 1;
            switch (inst.op) {
                .block, .loop, .if_ => {
                    try controls.append(a, .{ .start = at });
                    if (inst.op == .if_ and node.next[1] == absent) node.next[1] = ends[at];
                },
                .else_ => node.next[0] = ends[at],
                .end => _ = controls.pop(),
                .br, .br_if => {
                    if (inst.operand > controls.items.len) {
                        graph.valid = false;
                        return graph;
                    }
                    const target: u32 = if (inst.operand == controls.items.len) @intCast(instructions.len) else target: {
                        const control = controls.items[controls.items.len - 1 - inst.operand];
                        break :target if (instructions[control.start].op == .loop) control.start + 1 else ends[control.start];
                    };
                    node.next[0] = target;
                    if (inst.op == .br_if) node.next[1] = at + 1;
                },
                .return_, .unreachable_ => node.next[0] = @intCast(instructions.len),
                else => {},
            }
        }
        for (graph.nodes, 0..) |node, index| {
            for (node.next) |next| {
                if (next == absent) continue;
                try graph.predecessors.append(a, .{ .from = @intCast(index), .next = graph.nodes[next].first });
                graph.nodes[next].first = @intCast(graph.predecessors.items.len - 1);
            }
        }
        return graph;
    }

    pub fn deinit(self: *Graph, a: A) void {
        a.free(self.nodes);
        self.predecessors.deinit(a);
    }

    /// Mark all paths to uses, stopping at this generation's allocation.
    /// Stamps let consecutive owners reuse the same scratch without clearing
    /// the entire function for each small temporary.
    pub fn markLive(self: Graph, a: A, marks: []u32, stamp: u32, definition: u32, pending: *std.ArrayList(u32)) !void {
        var cursor: usize = 0;
        while (cursor < pending.items.len) : (cursor += 1) {
            const at = pending.items[cursor];
            if (at == definition) continue;
            var edge = self.nodes[at].first;
            while (edge != absent) {
                const previous = self.predecessors.items[edge];
                if (marks[previous.from] != stamp) {
                    marks[previous.from] = stamp;
                    try pending.append(a, previous.from);
                }
                edge = previous.next;
            }
        }
    }
};

test "ownership flow resolves loop backedges, conditional exits and both arms" {
    const a = std.testing.allocator;
    var graph = try Graph.init(a, &.{
        .{ .op = .block },     .{ .op = .loop }, .{ .op = .i32_const },        .{ .op = .br_if, .operand = 1 },
        .{ .op = .i32_const }, .{ .op = .if_ },  .{ .op = .br, .operand = 1 }, .{ .op = .else_ },
        .{ .op = .return_ },   .{ .op = .end },  .{ .op = .end },              .{ .op = .end },
    });
    defer graph.deinit(a);
    try std.testing.expect(graph.valid);
    try std.testing.expectEqual([2]u32{ 11, 4 }, graph.nodes[3].next);
    try std.testing.expectEqual([2]u32{ 6, 8 }, graph.nodes[5].next);
    try std.testing.expectEqual(@as(u32, 2), graph.nodes[6].next[0]);
    try std.testing.expectEqual(@as(u32, 9), graph.nodes[7].next[0]);
    try std.testing.expectEqual(@as(u32, 12), graph.nodes[8].next[0]);
}
