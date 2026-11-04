//! A real persistent slot may cover duplicate lexical owners. Identity comes
//! from exact executable value copies, never equal pointer bits or roles.
//!
//! A strong store `S := V` (scope chunk 4) whose slot has one dominating
//! reservation in the same lexical frame starts a region: every instruction
//! it reaches before that frame closes. A forward must-copy dataflow over the
//! part of the region the store dominates tracks which locals still hold V.
//! When every store into S that can follow lies there and stores V, S owns V
//! until its frame closes, so:
//!
//! - those stores are runtime no-ops (`root_store` keeps an identical slot);
//! - a lexical publication of V (chunk 5) is a duplicate owner that its frame
//!   releases no later than S's frame closes;
//! - another slot T reserved inside the region, whose every store holds V, is
//!   a duplicate owner for its whole lifetime: its reservation and stores go.
//!
//! Nothing else can remove S's owner. S's journal address lives only in its
//! slot local, which only scope directives read. Calls open and close frames
//! above the current one and release only owners they hold; memory writes
//! address objects, never journal pages; a trap or non-local exit abandons the
//! region. Reference exits (chunk 2), forces, host imports, global writes and
//! other runtime helpers still decline. The checked result role is
//! irrelevant: a lexical close carries no result, and a function close counts
//! the same owners whether it moves S or a duplicate publication into its
//! marker.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const flow = @import("wasm_control_flow.zig");
const A = std.mem.Allocator;
const none = std.math.maxInt(u32);
const multiple = none - 1;
/// A `local_set`/`local_tee` source: an earlier `local_get` of the same
/// straight-line run. `stale` marks a source reassigned before the copy.
const Copy = struct { from: u32 = none, read: u32 = none, stale: bool = false };
// Scope directives pack slot and value locals into 13 bits each.
const max_locals = 8192;
const max_code = 65536;
// At most 64 words of 64 bits describe one copy component.
const max_members = 4096;
const max_state_words = 1 << 20;
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
fn root(parents: []u32, first: u32) u32 {
    var current = first;
    while (parents[current] != current) {
        parents[current] = parents[parents[current]];
        current = parents[current];
    }
    return current;
}
fn control(op: ir.Op) bool {
    return switch (op) {
        .unreachable_, .block, .loop, .if_, .else_, .end, .br, .br_if, .return_ => true,
        else => false,
    };
}
fn listFunction(module: *const wasm.Module, id: u32) bool {
    const lists = module.lists orelse return false;
    inline for (@typeInfo(@TypeOf(lists)).@"struct".field_names) |field| {
        if (lists.functionId(field)) |function_id| if (id == function_id) return true;
    }
    return false;
}
/// Calls that keep the counted discipline without reaching an enclosing
/// journal slot: source functions, closures, allocation, field RC and List
/// helpers. Other runtime helpers, entries and the start body decline.
fn ordinaryCall(module: *const wasm.Module, inst: ir.Instruction) bool {
    if (inst.op == .call_indirect) return true;
    if (inst.op != .call or inst.operand >= module.functions.items.len) return false;
    const id = inst.operand;
    if (module.arena) |arena| inline for (.{ "allocate", "allocate_scalar", "allocate_typed", "allocate_shaped", "retain", "release", "store_word", "copy_words", "mark_acyclic" }) |field| {
        if (id == @field(arena, field)) return true;
    };
    if (listFunction(module, id)) return true;
    if (module.runtimeHelper(id)) return false;
    if (module.start != null and module.start.? == id) return false;
    return !module.functions.items[id].entry;
}
fn bit(words: []const u64, index: u32) bool {
    return words[index / 64] & (@as(u64, 1) << @intCast(index % 64)) != 0;
}
fn setBit(words: []u64, index: u32, value: bool) void {
    const mask = @as(u64, 1) << @intCast(index % 64);
    if (value) words[index / 64] |= mask else words[index / 64] &= ~mask;
}

const Analysis = struct {
    a: A,
    module: *const wasm.Module,
    source: *const ir.Function,
    code: []const ir.Instruction,
    graph: *const flow.Graph,
    locals: u32,
    work: usize = 1 << 22,
    copies: []Copy = &.{},
    reachable: []bool = &.{},
    // Per-local facts over the whole body.
    parents: []u32 = &.{},
    member_next: []u32 = &.{},
    member_head: []u32 = &.{},
    reserve_at: []u32 = &.{},
    sets: []u32 = &.{},
    gets: []u32 = &.{},
    value_uses: []u32 = &.{},
    // Strong stores per slot, linked in code order.
    store_head: []u32 = &.{},
    store_next: []u32 = &.{},
    // Per-start scratch, restored after each start.
    depths: []i32 = &.{},
    region: []u32 = &.{},
    dense: []u32 = &.{},
    seen: []u32 = &.{},
    queue: std.ArrayList(u32) = .empty,
    order: std.ArrayList(u32) = .empty,
    pending: std.ArrayList(u32) = .empty,
    members: std.ArrayList(u32) = .empty,
    states: std.ArrayList(u64) = .empty,
    visited: std.ArrayList(bool) = .empty,
    scratch: std.ArrayList(u64) = .empty,
    reservations: std.ArrayList(u32) = .empty,
    publications: std.ArrayList(u32) = .empty,
    // Results.
    remove: []bool = &.{},
    removed_slots: []bool = &.{},

    fn deinit(self: *Analysis) void {
        const a = self.a;
        inline for (.{ "copies", "reachable", "parents", "member_next", "member_head", "reserve_at", "sets", "gets", "value_uses", "store_head", "store_next", "depths", "region", "dense", "seen", "remove", "removed_slots" }) |field| a.free(@field(self, field));
        inline for (.{ "queue", "order", "pending", "members", "states", "visited", "scratch", "reservations", "publications" }) |field| @field(self, field).deinit(a);
    }
    fn spend(self: *Analysis, amount: usize) bool {
        if (self.work < amount) {
            self.work = 0;
            return false;
        }
        self.work -= amount;
        return true;
    }

    fn prepare(self: *Analysis) A.Error!bool {
        const a = self.a;
        const code = self.code;
        const locals = self.locals;
        self.copies = try a.alloc(Copy, code.len);
        @memset(self.copies, .{});
        self.reachable = try a.alloc(bool, code.len + 1);
        @memset(self.reachable, false);
        inline for (.{ "parents", "member_next", "member_head", "reserve_at", "sets", "gets", "value_uses", "store_head", "dense" }) |field| {
            @field(self, field) = try a.alloc(u32, locals);
        }
        for (self.parents, 0..) |*parent, index| parent.* = @intCast(index);
        inline for (.{ "member_next", "member_head", "reserve_at", "store_head", "dense" }) |field| @memset(@field(self, field), none);
        inline for (.{ "sets", "gets", "value_uses" }) |field| @memset(@field(self, field), 0);
        self.store_next = try a.alloc(u32, code.len);
        @memset(self.store_next, none);
        self.depths = try a.alloc(i32, code.len + 1);
        @memset(self.depths, -1);
        self.region = try a.alloc(u32, code.len + 1);
        @memset(self.region, none);
        self.seen = try a.alloc(u32, code.len + 1);
        @memset(self.seen, 0);
        self.remove = try a.alloc(bool, code.len);
        @memset(self.remove, false);
        self.removed_slots = try a.alloc(bool, locals);
        @memset(self.removed_slots, false);

        // Exact straight-line copies. Any other instruction forgets the
        // operand stack; a forgotten source is never claimed equal.
        var stack: [256]Copy = undefined;
        var height: usize = 0;
        var store_tail: []u32 = try a.alloc(u32, locals);
        defer a.free(store_tail);
        @memset(store_tail, none);
        for (code, 0..) |inst, index| {
            const at: u32 = @intCast(index);
            switch (inst.op) {
                .local_get => {
                    if (inst.operand >= locals) return false;
                    self.gets[inst.operand] += 1;
                    if (height == stack.len) height = 0;
                    stack[height] = .{ .from = inst.operand, .read = at };
                    height += 1;
                },
                .local_set, .local_tee => {
                    if (inst.operand >= locals) return false;
                    self.sets[inst.operand] += 1;
                    if (height != 0) {
                        self.copies[at] = stack[height - 1];
                        self.parents[root(self.parents, inst.operand)] = root(self.parents, stack[height - 1].from);
                        if (inst.op == .local_set) height -= 1;
                    }
                    for (stack[0..height]) |*entry| if (entry.from == inst.operand) {
                        entry.stale = true;
                    };
                },
                .drop => height -|= 1,
                .nop => {},
                .ownership => if (scope(inst)) |marker| switch (marker.chunk) {
                    3 => {
                        if (marker.roles >= locals) return false;
                        self.reserve_at[marker.roles] = if (self.reserve_at[marker.roles] == none) at else multiple;
                    },
                    4 => {
                        const slot = marker.roles & 8191;
                        const value = marker.roles >> 13;
                        if (slot >= locals or value >= locals) return false;
                        self.value_uses[value] += 1;
                        if (store_tail[slot] == none) self.store_head[slot] = at else self.store_next[store_tail[slot]] = at;
                        store_tail[slot] = at;
                    },
                    2, 5, 6 => {
                        if (marker.roles >= locals) return false;
                        self.value_uses[marker.roles] += 1;
                    },
                    else => {},
                },
                else => height = 0,
            }
        }
        for (0..locals) |index| {
            const component = root(self.parents, @intCast(index));
            self.member_next[index] = self.member_head[component];
            self.member_head[component] = @intCast(index);
        }
        self.reachable[0] = true;
        try self.queue.append(a, 0);
        var cursor: usize = 0;
        while (cursor < self.queue.items.len) : (cursor += 1) {
            for (self.graph.nodes[self.queue.items[cursor]].next) |next| {
                if (next == flow.absent or self.reachable[next]) continue;
                self.reachable[next] = true;
                try self.queue.append(a, @intCast(next));
            }
        }
        self.queue.clearRetainingCapacity();
        return true;
    }

    /// Every backward path from the store meets the slot's reservation
    /// without leaving or entering a lexical frame.
    fn reserved(self: *Analysis, start: u32, reservation: u32) A.Error!bool {
        const stamp = start + 1;
        self.pending.clearRetainingCapacity();
        try self.pending.append(self.a, start);
        self.seen[start] = stamp;
        while (self.pending.pop()) |point| {
            if (point == reservation + 1) continue;
            if (point == 0 or !self.spend(1)) return false;
            var edge = self.graph.nodes[point].first;
            if (edge == flow.absent) return false;
            while (edge != flow.absent) {
                const previous = self.graph.predecessors.items[edge];
                edge = previous.next;
                if (!self.reachable[previous.from]) continue;
                if (scope(self.code[previous.from])) |marker| if (marker.chunk <= 2) return false;
                if (self.seen[previous.from] == stamp) continue;
                self.seen[previous.from] = stamp;
                try self.pending.append(self.a, previous.from);
            }
        }
        return true;
    }

    /// The region a store's slot covers: everything reached before its frame
    /// closes, with consistent lexical depths and a sole entry at the store.
    fn reach(self: *Analysis, start: u32, slot: u32) A.Error!bool {
        const code = self.code;
        self.reservations.clearRetainingCapacity();
        self.publications.clearRetainingCapacity();
        try self.queue.append(self.a, start + 1);
        self.depths[start + 1] = 0;
        var cursor: usize = 0;
        while (cursor < self.queue.items.len) : (cursor += 1) {
            if (!self.spend(1)) return false;
            const at = self.queue.items[cursor];
            if (at == start) return false;
            const inst = code[at];
            var depth = self.depths[at];
            switch (inst.op) {
                .call, .call_indirect => if (!ordinaryCall(self.module, inst)) return false,
                .call_import, .resource_retire, .wide_layouts, .host_ref_get, .host_ref_set, .host_ref_size, .host_ref_grow, .global_set => return false,
                else => {},
            }
            if (scope(inst)) |marker| switch (marker.chunk) {
                0 => depth += 1,
                1 => {
                    if (depth == 0) continue;
                    depth -= 1;
                },
                3 => {
                    if (marker.roles == slot) return false;
                    try self.reservations.append(self.a, at);
                },
                4 => {},
                5 => {
                    if (localType(self.source, marker.roles) != .i32) return false;
                    try self.publications.append(self.a, at);
                },
                14 => {},
                else => return false,
            };
            for (self.graph.nodes[at].next) |next| {
                // A trap/return unwinds the activation; different lexical
                // depths may meet only at this synthetic terminal node.
                if (next == flow.absent or next == code.len) continue;
                if (self.depths[next] != -1) {
                    if (self.depths[next] != depth) return false;
                    continue;
                }
                self.depths[next] = depth;
                try self.queue.append(self.a, next);
            }
        }
        // Facts hold only where this real store dominates. A branch joining
        // from outside cannot borrow its owner slot: drop every instruction
        // with a live predecessor outside the remaining region, to a fixed
        // point. Later code still keeps the slot until its frame closes.
        for (self.queue.items) |at| self.region[at] = 0;
        self.pending.clearRetainingCapacity();
        try self.pending.appendSlice(self.a, self.queue.items);
        while (self.pending.pop()) |at| {
            if (self.region[at] == none or !self.spend(1)) {
                if (self.work == 0) return false;
                continue;
            }
            var edge = self.graph.nodes[at].first;
            const entered = while (edge != flow.absent) {
                const previous = self.graph.predecessors.items[edge];
                edge = previous.next;
                if (self.reachable[previous.from] and previous.from != start and self.region[previous.from] == none) break true;
            } else false;
            if (!entered) continue;
            self.region[at] = none;
            for (self.graph.nodes[at].next) |next| {
                if (next != flow.absent and next != code.len and self.region[next] != none) try self.pending.append(self.a, next);
            }
        }
        if (self.region[start + 1] == none) return false;
        self.order.clearRetainingCapacity();
        for (self.queue.items) |at| if (self.region[at] != none) {
            self.region[at] = @intCast(self.order.items.len);
            try self.order.append(self.a, at);
        };
        return true;
    }

    /// Locals of the store's copy component that hold its value right before
    /// the store: exact copies within the straight-line run ending there.
    fn initial(self: *Analysis, start: u32, value: u32, out: []u64) void {
        const code = self.code;
        var first = start;
        while (first != 0 and start - first < 4096 and !control(code[first - 1].op)) first -= 1;
        var numbers: [max_members]u32 = undefined;
        const members = self.members.items;
        for (members, 0..) |_, index| numbers[index] = @intCast(index + 1);
        var fresh: u32 = @intCast(members.len + 1);
        var stack: [256]u32 = undefined;
        var height: usize = 0;
        for (code[first..start]) |inst| switch (inst.op) {
            .local_get => {
                if (height == stack.len) height = 0;
                const index = self.dense[inst.operand];
                stack[height] = if (index == none) 0 else numbers[index];
                height += 1;
            },
            .local_set, .local_tee => {
                var number: u32 = 0;
                if (height != 0) number = stack[height - 1];
                if (inst.op == .local_set) height -|= 1;
                const index = self.dense[inst.operand];
                if (index == none) continue;
                if (number == 0) {
                    number = fresh;
                    fresh += 1;
                }
                numbers[index] = number;
            },
            .drop => height -|= 1,
            .nop, .ownership => {},
            else => height = 0,
        };
        @memset(out, 0);
        const target = numbers[self.dense[value]];
        for (members, 0..) |_, index| if (numbers[index] == target) setBit(out, @intCast(index), true);
    }

    /// Forward must-copy dataflow: which component locals hold the stored
    /// value at each region point. Unvisited points start optimistic.
    fn flowCopies(self: *Analysis, start: u32, value: u32) A.Error!bool {
        const a = self.a;
        const words = (self.members.items.len + 63) / 64;
        const count = self.order.items.len;
        // Bound scratch to 8 MiB; a larger region keeps its owners.
        if (count * words > max_state_words) return false;
        try self.states.resize(a, count * words);
        @memset(self.states.items, std.math.maxInt(u64));
        try self.visited.resize(a, count);
        @memset(self.visited.items, false);
        try self.scratch.resize(a, words);
        self.initial(start, value, self.states.items[0..words]);
        self.visited.items[0] = true;
        self.pending.clearRetainingCapacity();
        try self.pending.append(a, 0);
        const out = self.scratch.items;
        while (self.pending.pop()) |index| {
            if (!self.spend(words + 1)) return false;
            const at = self.order.items[index];
            const inst = self.code[at];
            @memcpy(out, self.states.items[index * words ..][0..words]);
            if (assigned(inst)) |local| if (self.dense[local] != none) {
                var keep = false;
                const copy = self.copies[at];
                if (inst.op != .ownership and copy.from != none and !copy.stale and self.dense[copy.from] != none) keep = bit(out, self.dense[copy.from]);
                setBit(out, self.dense[local], keep);
            };
            if (scope(inst)) |marker| if (marker.chunk == 1 and self.depths[at] == 0) continue;
            for (self.graph.nodes[at].next) |next| {
                if (next == flow.absent or next == self.code.len) continue;
                const target = self.region[next];
                if (target == none) continue;
                const state = self.states.items[target * words ..][0..words];
                var changed = !self.visited.items[target];
                for (state, out) |*word, incoming| {
                    const met = word.* & incoming;
                    if (met != word.*) changed = true;
                    word.* = met;
                }
                if (!changed) continue;
                self.visited.items[target] = true;
                try self.pending.append(a, target);
            }
        }
        return true;
    }
    /// The value local of `at` holds the stored value there.
    fn holds(self: *const Analysis, at: u32, local: u32) bool {
        const index = self.region[at];
        if (index == none or !self.visited.items[index]) return false;
        const member = self.dense[local];
        if (member == none) return false;
        const words = (self.members.items.len + 63) / 64;
        return bit(self.states.items[index * words ..][0..words], member);
    }
    fn restore(self: *Analysis) void {
        for (self.queue.items) |at| {
            self.depths[at] = -1;
            self.region[at] = none;
        }
        self.queue.clearRetainingCapacity();
        for (self.members.items) |local| self.dense[local] = none;
        self.members.clearRetainingCapacity();
    }

    /// Proves one store's region and records the duplicate owners it covers.
    fn cover(self: *Analysis, start: u32) A.Error!void {
        const marker = scope(self.code[start]).?;
        const slot: u32 = marker.roles & 8191;
        const value: u32 = marker.roles >> 13;
        const parameters = self.source.parameters.len;
        if (start + 1 >= self.code.len or self.removed_slots[slot] or slot < parameters) return;
        if (localType(self.source, slot) != .i32 or localType(self.source, value) != .i32) return;
        const reservation = self.reserve_at[slot];
        if (reservation == none or reservation == multiple) return;
        // The journal address never reaches ordinary instructions.
        if (self.sets[slot] != 0 or self.gets[slot] != 0 or self.value_uses[slot] != 0) return;
        if (!try self.reserved(start, reservation)) return;
        defer self.restore();
        if (!try self.reach(start, slot)) return;
        var member = self.member_head[root(self.parents, value)];
        while (member != none) : (member = self.member_next[member]) {
            if (self.members.items.len == max_members) return;
            self.dense[member] = @intCast(self.members.items.len);
            try self.members.append(self.a, member);
        }
        if (!try self.flowCopies(start, value)) return;
        // Every strong store into this slot that can follow the opening one
        // must lie in the dominated region and keep the same value, so the
        // slot still holds it when its frame closes.
        var store = self.store_head[slot];
        while (store != none) : (store = self.store_next[store]) {
            if (self.depths[store] == -1) continue;
            if (!self.holds(store, scope(self.code[store]).?.roles >> 13)) return;
        }
        store = self.store_head[slot];
        while (store != none) : (store = self.store_next[store]) {
            if (self.region[store] != none) self.remove[store] = true;
        }
        for (self.publications.items) |at| {
            if (self.holds(at, scope(self.code[at]).?.roles)) self.remove[at] = true;
        }
        for (self.reservations.items) |at| {
            if (self.region[at] == none) continue;
            const other: u32 = scope(self.code[at]).?.roles;
            if (other < parameters or self.removed_slots[other] or localType(self.source, other) != .i32) continue;
            if (self.reserve_at[other] != at or self.sets[other] != 0 or self.gets[other] != 0 or self.value_uses[other] != 0) continue;
            var covered = true;
            var duplicate = self.store_head[other];
            while (duplicate != none) : (duplicate = self.store_next[duplicate]) {
                if (!self.holds(duplicate, scope(self.code[duplicate]).?.roles >> 13)) covered = false;
            }
            if (!covered) continue;
            self.remove[at] = true;
            self.removed_slots[other] = true;
            duplicate = self.store_head[other];
            while (duplicate != none) : (duplicate = self.store_next[duplicate]) self.remove[duplicate] = true;
        }
    }
};

pub fn run(a: A, module: *const wasm.Module, source: *const ir.Function) A.Error!?ir.Body {
    // A close also drains resource cleanup; keep its exact owner boundary.
    if (module.resourceDrainImport() != null) return null;
    const code = source.instructions.items;
    const locals = std.math.add(usize, source.parameters.len, source.locals.items.len) catch return null;
    if (locals > max_locals or code.len > max_code) return null;
    var stores = false;
    for (code) |inst| if (scope(inst)) |marker| if (marker.chunk == 4) {
        stores = true;
        break;
    };
    if (!stores) return null;
    var graph = try flow.Graph.init(a, code);
    defer graph.deinit(a);
    if (!graph.valid) return null;
    var analysis: Analysis = .{ .a = a, .module = module, .source = source, .code = code, .graph = &graph, .locals = @intCast(locals) };
    defer analysis.deinit();
    if (!try analysis.prepare()) return null;
    for (code, 0..) |inst, start| {
        if (analysis.work == 0) break;
        const marker = scope(inst) orelse continue;
        // A store already shown redundant lies inside an earlier region.
        if (marker.chunk != 4 or analysis.remove[start]) continue;
        try analysis.cover(@intCast(start));
    }
    var changed = false;
    for (analysis.remove) |omitted| changed = changed or omitted;
    if (!changed) return null;
    var out: ir.Body = .{};
    errdefer out.deinit(a);
    try out.locals.appendSlice(a, source.locals.items);
    try out.instructions.ensureTotalCapacity(a, code.len);
    for (code, analysis.remove) |inst, omitted| if (!omitted) {
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
    const arena = try module.ensureArena();
    const function = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    _ = try module.addLocal(function, .i32);
    _ = try module.addLocal(function, .i32);
    const code = [_]ir.Instruction{
        mark(0, 0),                          mark(3, 1),            mark(4, 0 * 8192 + 1),
        mark(0, 0),                          .{ .op = .nop },       .{ .op = .local_get },
        .{ .op = .local_set, .operand = 2 }, mark(5, 2),            mark(1, 0),
        mark(1, 0),                          .{ .op = .i32_const },
    };
    try module.emitSlice(function, &code);
    const source = &module.functions.items[function];
    var optimized = (try run(a, &module, source)).?;
    defer optimized.deinit(a);
    try std.testing.expectEqual(code.len - 1, optimized.instructions.items.len);
    try std.testing.expectEqualSlices(ir.Instruction, &code, source.instructions.items);
    // The persistent strong slot, both close boundaries and every executable
    // instruction survive. Only the duplicate lexical publication is removed.
    try std.testing.expectEqualSlices(ir.Instruction, code[0..7], optimized.instructions.items[0..7]);
    try std.testing.expectEqualSlices(ir.Instruction, code[8..], optimized.instructions.items[7..]);
    // Allocation, field RC, closures and object writes keep the strong slot.
    // They cannot reach a journal slot of an enclosing frame.
    for ([_]ir.Instruction{
        .{ .op = .call, .operand = arena.allocate_typed }, .{ .op = .call, .operand = arena.store_word },
        .{ .op = .call, .operand = arena.release },        .{ .op = .call_indirect },
        .{ .op = .i32_store },                             .{ .op = .memory_copy },
        mark(14, 0),
    }) |kept| {
        source.instructions.items[4] = kept;
        var still = (try run(a, &module, source)).?;
        defer still.deinit(a);
        try std.testing.expectEqual(code.len - 1, still.instructions.items.len);
    }
    // Journal helpers, host calls, reference exits, forces, global writes and
    // unknown resources decline, as do malformed or rebound slots.
    for ([_]ir.Instruction{
        .{ .op = .call, .operand = arena.root_close }, .{ .op = .call, .operand = arena.root_pop },
        .{ .op = .call, .operand = arena.reset },      .{ .op = .call, .operand = arena.cycle_collect },
        .{ .op = .call_import },                       .{ .op = .global_set },
        .{ .op = .resource_retire },                   .{ .op = .wide_layouts },
        .{ .op = .host_ref_grow },                     .{ .op = .host_ref_set },
        mark(6, 0),                                    mark(2, 0),
        mark(15, 0),                                   mark(3, 1),
        mark(4, 255 * 8192 + 1),                       mark(4, 2 * 8192 + 255),
        .{ .op = .local_get, .operand = 1 },
    }) |bad| {
        source.instructions.items[4] = bad;
        try std.testing.expect(try run(a, &module, source) == null);
    }
    source.instructions.items[4] = code[4];
    // A recomputed/rebound head is a new producer even with the same ABI.
    source.instructions.items[5] = .{ .op = .i32_const };
    try std.testing.expect(try run(a, &module, source) == null);
    source.instructions.items[5] = code[5];
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

/// An Array-returning function carries one reference through a loop whose
/// iteration updates it in place (`in_place`) or replaces it with a fresh
/// allocation. Locals: 0 count, 1 slot, 2 iteration, 3 outgoing, 4 counter,
/// 5 inner slot, 6 edited version.
fn carryLoop(module: *wasm.Module, in_place: bool) !u32 {
    const arena = module.arena.?;
    const function = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    for (0..6) |_| _ = try module.addLocal(function, .i32);
    var edit: [2]ir.Instruction = .{ .{ .op = .local_get, .operand = 2 }, .{ .op = .nop } };
    if (!in_place) edit = .{ .{ .op = .local_get }, .{ .op = .call, .operand = arena.allocate_scalar } };
    const code = [_]ir.Instruction{
        // let values = fill; the loop's stable carry slot owns it.
        .{ .op = .local_get },               .{ .op = .call, .operand = arena.allocate_scalar }, .{ .op = .local_set, .operand = 2 },
        mark(3, 1),                          mark(4, 2 * 8192 + 1),                              .{ .op = .local_get, .operand = 2 },
        .{ .op = .local_set, .operand = 3 }, mark(4, 3 * 8192 + 1),                              .{ .op = .block },
        .{ .op = .loop },                    .{ .op = .local_get, .operand = 4 },                .{ .op = .local_get },
        .{ .op = .i32_ge_u },                .{ .op = .br_if, .operand = 1 },                    mark(0, 0),
        mark(5, 2),
        // A nested loop's own carry slot covers the same value.
                                 mark(3, 5),                                         mark(4, 2 * 8192 + 5),
        // values[i] := i, a bounds-checked numeric word.
        .{ .op = .local_get, .operand = 4 }, .{ .op = .local_get, .operand = 2 },                .{ .op = .i32_load },
        .{ .op = .i32_ge_u },                .{ .op = .if_ },                                    .{ .op = .unreachable_ },
        .{ .op = .end },                     .{ .op = .local_get, .operand = 2 },                .{ .op = .local_get, .operand = 4 },
        ir.scalarStore(4),                   .{ .op = .i32_store, .operand = 4 },                edit[0],
        edit[1],                             .{ .op = .local_set, .operand = 6 },                .{ .op = .local_get, .operand = 6 },
        .{ .op = .local_set, .operand = 2 }, mark(4, 2 * 8192 + 1),                              mark(4, 2 * 8192 + 5),
        .{ .op = .local_get, .operand = 2 }, .{ .op = .local_set, .operand = 3 },                mark(4, 3 * 8192 + 1),
        mark(1, 0),                          .{ .op = .local_get, .operand = 4 },                .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_add },                 .{ .op = .local_set, .operand = 4 },                .{ .op = .br },
        .{ .op = .end },                     .{ .op = .end },                                    .{ .op = .local_get, .operand = 3 },
    };
    try module.emitSlice(function, &code);
    return function;
}
fn directives(body: []const ir.Instruction, chunk: u4) usize {
    var result: usize = 0;
    for (body) |inst| if (scope(inst)) |marker| {
        if (marker.chunk == chunk) result += 1;
    };
    return result;
}
fn carries(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    _ = try module.ensureArena();
    const kept = try carryLoop(&module, true);
    const before = try a.dupe(ir.Instruction, module.functions.items[kept].instructions.items);
    defer a.free(before);
    var body = (try run(a, &module, &module.functions.items[kept])).?;
    defer body.deinit(a);
    try std.testing.expectEqualSlices(ir.Instruction, before, module.functions.items[kept].instructions.items);
    // Only the first strong store and its reservation remain. The iteration
    // publication, the in-place backedge stores and the duplicate inner
    // carry slot all go; the frame boundaries and every executable
    // instruction, including the trap and the checked word, stay.
    try std.testing.expectEqual(@as(usize, 1), directives(body.instructions.items, 3));
    try std.testing.expectEqual(@as(usize, 1), directives(body.instructions.items, 4));
    try std.testing.expectEqual(@as(usize, 0), directives(body.instructions.items, 5));
    try std.testing.expectEqual(@as(usize, 2), directives(body.instructions.items, 0) + directives(body.instructions.items, 1));
    var executable: usize = 0;
    for (before) |inst| executable += @intFromBool(inst.op != .ownership or scope(inst) == null);
    for (body.instructions.items) |inst| executable -= @intFromBool(inst.op != .ownership or scope(inst) == null);
    try std.testing.expectEqual(@as(usize, 0), executable);
    // A fresh replacement makes the slot store real; the publication keeps
    // the incoming version alive for the rest of its iteration.
    const copied = try carryLoop(&module, false);
    try std.testing.expect(try run(a, &module, &module.functions.items[copied]) == null);
}
test "in-place reference carries drop duplicate iteration owners in reference-returning bodies through OOM" {
    try carries(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, carries, .{});
}
