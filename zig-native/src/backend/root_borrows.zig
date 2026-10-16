//! A real persistent slot may cover a duplicate lexical publication. Identity
//! comes from exact executable value copies, never equal pointer bits or roles.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const flow = @import("wasm_control_flow.zig");
const A = std.mem.Allocator;
const none = std.math.maxInt(u16);
const Copy = struct { from: u16 = none, read: u16 = none };
const Seed = struct { local: u16, at: ?u16 };
fn scope(inst: ir.Instruction) ?ir.Ownership {
    if (inst.op != .ownership) return null;
    const marker: ir.Ownership = @bitCast(inst.operand);
    if (marker.kind != .scope) return null;
    return marker;
}
fn assigned(inst: ir.Instruction) ?u32 {
    if (inst.op == .local_set or inst.op == .local_tee) return inst.operand;
    if (scope(inst)) |marker| if (marker.chunk == 3) return marker.roles;
    return null;
}
fn localType(source: *const ir.Function, index: usize) ir.ValueType {
    if (index < source.parameters.len) return source.parameters[index];
    return source.locals.items[index - source.parameters.len];
}
fn root(parents: []u16, first: u16) u16 {
    var current = first;
    while (parents[current] != current) current = parents[current];
    return current;
}
const Proof = struct {
    a: A,
    code: []const ir.Instruction,
    graph: *const flow.Graph,
    copies: []const Copy,
    reachable: []const bool,
    seed: Seed,
    work: *usize,
    memo: std.AutoHashMapUnmanaged(u64, void) = .empty,
    fn value(self: *Proof, local: u16, point: u16, depth: usize) A.Error!bool {
        if (depth == 512 or self.work.* == 0 or self.memo.count() == 4096) return false;
        self.work.* -= 1;
        if (point == 0) return self.seed.at == null and self.seed.local == local;
        const key = (@as(u64, local) << 32) | point;
        if (self.memo.contains(key)) return true;
        try self.memo.put(self.a, key, {});
        var edge = self.graph.nodes[point].first;
        if (edge == flow.absent) return false;
        while (edge != flow.absent) {
            const previous = self.graph.predecessors.items[edge];
            if (!self.reachable[previous.from]) {
                edge = previous.next;
                continue;
            }
            const at: u16 = @intCast(previous.from);
            if (assigned(self.code[at]) == local) {
                if (self.seed.at != at or self.seed.local != local) {
                    const copy = self.copies[at];
                    if (copy.from == none or !try self.value(copy.from, copy.read, depth + 1)) return false;
                }
            } else if (!try self.value(local, at, depth + 1)) return false;
            edge = previous.next;
        }
        return true;
    }
    fn reservation(self: *Proof, point: u16, needed: u16, depth: usize, seen: []bool) A.Error!bool {
        if (point == needed + 1) return true;
        if (point == 0 or depth == 512 or self.work.* == 0) return false;
        self.work.* -= 1;
        if (seen[point]) return true;
        seen[point] = true;
        var edge = self.graph.nodes[point].first;
        if (edge == flow.absent) return false;
        while (edge != flow.absent) {
            const previous = self.graph.predecessors.items[edge];
            if (!self.reachable[previous.from]) {
                edge = previous.next;
                continue;
            }
            if (scope(self.code[previous.from])) |marker| if (marker.chunk <= 2) return false;
            if (!try self.reservation(@intCast(previous.from), needed, depth + 1, seen)) return false;
            edge = previous.next;
        }
        return true;
    }
};

pub fn run(a: A, module: *const wasm.Module, source: *const ir.Function) A.Error!?ir.Body {
    if (source.result_role != .scalar or module.resourceDrainImport() != null) return null;
    const code = source.instructions.items;
    if (source.parameters.len > 256 or source.locals.items.len > 256 - source.parameters.len or code.len > 4096) return null;
    const locals = source.parameters.len + source.locals.items.len;
    var publications = false;
    for (code) |inst| if (scope(inst)) |marker| if (marker.chunk == 5) {
        publications = true;
        break;
    };
    if (!publications) return null;
    var graph = try flow.Graph.init(a, code);
    defer graph.deinit(a);
    if (!graph.valid) return null;
    const copies = try a.alloc(Copy, code.len);
    defer a.free(copies);
    @memset(copies, .{});
    var parents: [256]u16 = undefined;
    for (parents[0..locals], 0..) |*parent, index| parent.* = @intCast(index);
    var stack: [256]Copy = undefined;
    var height: usize = 0;
    for (code, 0..) |inst, at| {
        if (inst.op == .local_get) {
            if (inst.operand >= locals or height == stack.len) return null;
            stack[height] = .{ .from = @intCast(inst.operand), .read = @intCast(at) };
            height += 1;
        } else if (inst.op == .local_set or inst.op == .local_tee) {
            if (inst.operand >= locals) return null;
            if (height != 0) {
                copies[at] = stack[height - 1];
                parents[root(&parents, @intCast(inst.operand))] = root(&parents, copies[at].from);
                if (inst.op == .local_set) height -= 1;
            }
        } else if (inst.op == .drop) {
            if (height != 0) height -= 1;
        } else if (inst.op != .ownership and inst.op != .nop) height = 0;
    }
    var seeds: [256]?Seed = @splat(null);
    var conflict: [256]bool = @splat(false);
    for (source.parameters, 0..) |_, local| seeds[root(&parents, @intCast(local))] = .{ .local = @intCast(local), .at = null };
    // Multiple parameter origins in one copy component also remain distinct.
    for (source.parameters, 0..) |_, local| if (seeds[root(&parents, @intCast(local))].?.local != local) {
        conflict[root(&parents, @intCast(local))] = true;
    };
    for (code, 0..) |inst, at| if (assigned(inst)) |local| {
        if (local >= locals) return null;
        if (copies[at].from != none) continue;
        const component = root(&parents, @intCast(local));
        if (seeds[component] != null) conflict[component] = true;
        seeds[component] = .{ .local = @intCast(local), .at = @intCast(at) };
    };
    const remove = try a.alloc(bool, code.len);
    defer a.free(remove);
    @memset(remove, false);
    const depths = try a.alloc(i16, code.len + 1);
    defer a.free(depths);
    const seen = try a.alloc(bool, code.len + 1);
    defer a.free(seen);
    var queue: std.ArrayList(u16) = .empty;
    defer queue.deinit(a);
    const reachable = try a.alloc(bool, code.len + 1);
    defer a.free(reachable);
    @memset(reachable, false);
    reachable[0] = true;
    try queue.append(a, 0);
    var reach_cursor: usize = 0;
    while (reach_cursor < queue.items.len) : (reach_cursor += 1) {
        for (graph.nodes[queue.items[reach_cursor]].next) |next| {
            if (next == flow.absent or reachable[next]) continue;
            reachable[next] = true;
            try queue.append(a, @intCast(next));
        }
    }
    var proposed: std.ArrayList(u16) = .empty;
    defer proposed.deinit(a);
    var work: usize = 65536;
    var changed = false;
    for (code, 0..) |inst, start| {
        if (work == 0) break;
        work -= 1;
        const store = scope(inst) orelse continue;
        if (store.chunk != 4) continue;
        const slot = store.roles & 8191;
        const local: u16 = @intCast(store.roles >> 13);
        if (slot >= locals or local >= locals) continue;
        if (localType(source, slot) != .i32 or localType(source, local) != .i32) continue;
        const component = root(&parents, local);
        if (conflict[component]) continue;
        const seed = seeds[component] orelse continue;
        var reserved: ?u16 = null;
        var valid = true;
        for (code, 0..) |other, at| {
            if (work == 0) {
                valid = false;
                break;
            }
            work -= 1;
            if (assigned(other) != slot) continue;
            const marker = scope(other) orelse {
                valid = false;
                break;
            };
            if (marker.chunk != 3 or reserved != null) {
                valid = false;
                break;
            }
            reserved = @intCast(at);
        }
        if (!valid or reserved == null) continue;
        var proof: Proof = .{ .a = a, .code = code, .graph = &graph, .copies = copies, .reachable = reachable, .seed = seed, .work = &work };
        defer proof.memo.deinit(a);
        @memset(seen, false);
        if (!try proof.reservation(@intCast(start), reserved.?, 0, seen) or !try proof.value(local, @intCast(start), 0)) continue;
        queue.clearRetainingCapacity();
        proposed.clearRetainingCapacity();
        @memset(depths, -1);
        try queue.append(a, @intCast(start + 1));
        depths[start + 1] = 0;
        var cursor: usize = 0;
        while (cursor < queue.items.len) : (cursor += 1) {
            if (work == 0) {
                valid = false;
                break;
            }
            work -= 1;
            const at = queue.items[cursor];
            if (at == code.len) continue;
            const next_inst = code[at];
            var depth = depths[at];
            if (seed.at == at) {
                valid = false;
                break;
            }
            switch (next_inst.op) {
                .call, .call_import, .call_indirect, .resource_retire, .wide_layouts, .host_ref_get, .host_ref_set, .host_ref_size, .host_ref_grow, .global_set, .i32_store, .f32_store, .v128_store, .memory_copy, .memory_fill, .memory_grow => {
                    valid = false;
                },
                else => {},
            }
            if (!valid) break;
            if (scope(next_inst)) |marker| switch (marker.chunk) {
                0 => depth += 1,
                1 => {
                    if (depth == 0) continue;
                    depth -= 1;
                },
                2, 6, 15 => {
                    valid = false;
                },
                3 => if (marker.roles == slot) {
                    valid = false;
                },
                4 => {
                    const value = marker.roles >> 13;
                    if (value >= locals or marker.roles & 8191 >= locals) {
                        valid = false;
                        break;
                    }
                    if (marker.roles & 8191 == slot and !try proof.value(@intCast(value), at, 0)) {
                        valid = false;
                    }
                },
                5 => {
                    if (marker.roles >= locals or localType(source, marker.roles) != .i32) {
                        valid = false;
                        break;
                    }
                    if (root(&parents, @intCast(marker.roles)) == component) {
                        if (!try proof.value(@intCast(marker.roles), at, 0)) {
                            valid = false;
                            break;
                        }
                        try proposed.append(a, at);
                    }
                },
                14 => {},
                else => {
                    valid = false;
                },
            };
            if (!valid) break;
            for (graph.nodes[at].next) |next| {
                // A trap/return unwinds the activation; different lexical
                // depths may meet only at this synthetic terminal node.
                if (next == flow.absent or next == code.len) continue;
                if (depths[next] != -1) {
                    if (depths[next] != depth) valid = false;
                    continue;
                }
                depths[next] = depth;
                try queue.append(a, @intCast(next));
            }
            if (!valid) break;
        }
        // Every reachable region instruction must be dominated by this real
        // store. A branch joining from outside cannot borrow its owner slot.
        for (queue.items) |at| {
            var edge = graph.nodes[at].first;
            while (edge != flow.absent) {
                const previous = graph.predecessors.items[edge];
                if (reachable[previous.from] and previous.from != start and depths[previous.from] == -1) valid = false;
                edge = previous.next;
            }
        }
        if (!valid) continue;
        for (proposed.items) |at| remove[at] = true;
        changed = changed or proposed.items.len != 0;
    }
    if (!changed) return null;
    var out: ir.Body = .{};
    errdefer out.deinit(a);
    try out.locals.appendSlice(a, source.locals.items);
    for (code, remove) |inst, omitted| if (!omitted) {
        try out.instructions.append(a, inst);
    };
    return out;
}

fn mark(chunk: u4, roles: u26) ir.Instruction {
    return .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = chunk, .roles = roles }) };
}
fn boundaries(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    _ = try module.ensureArena();
    const function = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    _ = try module.addLocal(function, .i32);
    _ = try module.addLocal(function, .i32);
    const code = [_]ir.Instruction{
        mark(0, 0),            mark(3, 1),            mark(4, 0 * 8192 + 1),
        mark(0, 0),            .{ .op = .local_get }, .{ .op = .local_set, .operand = 2 },
        mark(5, 2),            mark(1, 0),            mark(1, 0),
        .{ .op = .i32_const },
    };
    try module.emitSlice(function, &code);
    const source = &module.functions.items[function];
    var optimized = (try run(a, &module, source)).?;
    defer optimized.deinit(a);
    try std.testing.expectEqual(code.len - 1, optimized.instructions.items.len);
    try std.testing.expectEqualSlices(ir.Instruction, &code, source.instructions.items);
    // The persistent strong slot, both close boundaries and every executable
    // instruction survive. Only the duplicate lexical publication is removed.
    try std.testing.expectEqualSlices(ir.Instruction, code[0..6], optimized.instructions.items[0..6]);
    try std.testing.expectEqualSlices(ir.Instruction, code[7..], optimized.instructions.items[6..]);
    for ([_]ir.Instruction{
        .{ .op = .call },            .{ .op = .call_import },  .{ .op = .call_indirect },
        .{ .op = .global_set },      .{ .op = .i32_store },    .{ .op = .memory_grow },
        .{ .op = .resource_retire }, .{ .op = .wide_layouts }, .{ .op = .host_ref_grow },
        .{ .op = .host_ref_set },    mark(6, 0),               mark(2, 0),
        mark(15, 0),                 mark(3, 1),               mark(4, 255 * 8192 + 1),
        mark(4, 2 * 8192 + 255),
    }) |bad| {
        source.instructions.items[4] = bad;
        try std.testing.expect(try run(a, &module, source) == null);
    }
    source.instructions.items[4] = code[4];
    // A recomputed/rebound head is a new producer even with the same ABI.
    source.instructions.items[4] = .{ .op = .i32_const };
    try std.testing.expect(try run(a, &module, source) == null);
    source.instructions.items[4] = code[4];
    source.instructions.clearRetainingCapacity();
    try module.emitSlice(function, &.{
        mark(0, 0),            mark(3, 1),                          mark(4, 1),
        .{ .op = .block },     .{ .op = .loop },                    mark(0, 0),
        .{ .op = .local_get }, .{ .op = .local_set, .operand = 2 }, mark(5, 2),
        .{ .op = .local_get }, .{ .op = .if_ },                     .{ .op = .unreachable_ },
        .{ .op = .end },       mark(1, 0),                          .{ .op = .local_get },
        .{ .op = .br_if },     .{ .op = .end },                     .{ .op = .end },
        mark(1, 0),            .{ .op = .i32_const },
    });
    // Loop backedges and trapping exits preserve the real parent lease.
    var loop = (try run(a, &module, source)).?;
    defer loop.deinit(a);
    try std.testing.expectEqual(source.instructions.items.len - 1, loop.instructions.items.len);
    source.instructions.clearRetainingCapacity();
    try module.emitSlice(function, &.{
        mark(0, 0), mark(3, 1),      .{ .op = .local_get }, .{ .op = .if_ },
        mark(4, 1), .{ .op = .end }, mark(0, 0),            mark(5, 0),
        mark(1, 0), mark(1, 0),      .{ .op = .i32_const },
    });
    // A branch bypassing the initialization must retain its publication.
    try std.testing.expect(try run(a, &module, source) == null);
    source.instructions.clearRetainingCapacity();
    try module.emitSlice(function, &.{
        mark(0, 0), mark(3, 1), mark(4, 1), mark(1, 0), mark(0, 0), mark(5, 0), mark(1, 0), .{ .op = .i32_const },
    });
    // A closed owner slot cannot cover the following sibling scope.
    try std.testing.expect(try run(a, &module, source) == null);
    // Copying a different parameter cannot manufacture the original owner.
    const other = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .scalar);
    _ = try module.addLocal(other, .i32);
    try module.emitSlice(other, &.{ mark(0, 0), mark(3, 2), mark(4, 2), mark(0, 0), mark(5, 1), mark(1, 0), mark(1, 0), .{ .op = .i32_const } });
    try std.testing.expect(try run(a, &module, &module.functions.items[other]) == null);
    module.functions.items[function].instructions.clearRetainingCapacity();
    try module.emitSlice(function, &code);
    _ = try module.importFunction("blot:resource/2", "drain", &.{}, .none);
    try std.testing.expect(module.resourceDrainImport() != null);
    try std.testing.expect(try run(a, &module, &module.functions.items[function]) == null);
}
test "persistent root borrows require exact copies and real live slots through OOM" {
    try boundaries(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, boundaries, .{});
}
