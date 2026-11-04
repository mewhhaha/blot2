//! Private provider heads stay outside source graphs. This bounded, whole-body
//! proof precedes operation specialization; unsupported flow declines authority.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const origins = @import("provider_origins.zig");
const cfg = @import("wasm_control_flow.zig");
const A = std.mem.Allocator;
const frame = 1;
const ordinary = 2;
const zero = 4;
const Condition = struct { local: u32, version: u32, kinds: u8 };
const Value = struct {
    kinds: u8 = zero,
    constant: ?u32 = 0,
    offset: u32 = 0,
    frame_kinds: u8 = 0,
    local: ?u32 = null,
    version: u32 = 0,
    kind_source: ?u32 = null,
    kind_version: u32 = 0,
    condition: ?Condition = null,
    pointer: bool = false,
    borrowed_head: bool = false,
    owned_sources: u64 = 0,
    fn hasFrame(self: Value) bool {
        return self.kinds & frame != 0;
    }
    fn head(self: Value) bool {
        return self.kinds & ordinary == 0 and self.offset == 0;
    }
};
const Control = struct { height: usize, result: bool, conditional: bool = false, value: Value = .{ .kinds = 0, .constant = null }, condition: ?Condition = null, alternate: bool = false };
fn merge(left: *Value, right: Value) bool {
    const changed = left.kinds | right.kinds != left.kinds or
        (left.constant != null and left.constant != right.constant) or
        (left.offset != std.math.maxInt(u32) and left.offset != right.offset) or
        left.frame_kinds | right.frame_kinds != left.frame_kinds or (!left.pointer and right.pointer) or (!left.borrowed_head and right.borrowed_head) or (left.owned_sources | right.owned_sources != left.owned_sources);
    left.kinds |= right.kinds;
    if (left.constant != right.constant) left.constant = null;
    if (left.offset != right.offset) left.offset = std.math.maxInt(u32);
    left.frame_kinds |= right.frame_kinds;
    left.pointer = left.pointer or right.pointer;
    left.borrowed_head = left.borrowed_head or right.borrowed_head;
    left.owned_sources |= right.owned_sources;
    left.local = null;
    left.kind_source = null;
    left.condition = null;
    return changed;
}
fn pop(stack: *std.ArrayList(Value)) ?Value {
    return stack.pop();
}
fn push(a: A, stack: *std.ArrayList(Value), value: Value) !void {
    try stack.append(a, value);
}
fn dead(controls: []const Control, locals: []const Value, versions: []const u32, observed: []bool) bool {
    for (controls) |control| if (control.condition) |condition| {
        if (condition.local >= locals.len or versions[condition.local] != condition.version) continue;
        observed[condition.local] = true;
        var kinds = locals[condition.local].frame_kinds;
        for (controls) |branch| if (branch.condition) |other| {
            if (other.local == condition.local and other.version == condition.version) kinds &= if (branch.alternate) ~other.kinds else other.kinds;
        };
        if (kinds == 0) return true;
    };
    return false;
}
fn constructionAt(constructions: []const origins.Fact, at: usize) ?origins.Fact {
    for (constructions) |fact| if (fact.allocation == at) return fact;
    return null;
}
// Adjacent instruction states share one hash entry. The logical state count
// retains the traversal/cache bound; the bit packing changes only scratch.
const Positions = struct {
    words: std.AutoHashMapUnmanaged(u64, u64) = .empty,
    count: u32 = 0,
    fn key(at: u32, local: u32) u64 {
        return @as(u64, local) << 32 | (at >> 6);
    }
    fn bit(at: u32) u64 {
        return @as(u64, 1) << @as(u6, @truncate(at));
    }
    fn contains(self: *const Positions, at: u32, local: u32) bool {
        return (self.words.get(key(at, local)) orelse 0) & bit(at) != 0;
    }
    fn insert(self: *Positions, a: A, at: u32, local: u32) A.Error!bool {
        const entry = try self.words.getOrPut(a, key(at, local));
        if (!entry.found_existing) entry.value_ptr.* = 0;
        const present = entry.value_ptr.* & bit(at) != 0;
        if (!present) self.count += 1;
        entry.value_ptr.* |= bit(at);
        return present;
    }
    fn deinit(self: *Positions, a: A) void {
        self.words.deinit(a);
    }
    fn clear(self: *Positions) void {
        self.words.clearRetainingCapacity();
        self.count = 0;
    }
    fn include(self: *Positions, a: A, other: *const Positions) A.Error!void {
        // Reserve the complete union before publishing any positive subproof.
        try self.words.ensureUnusedCapacity(a, other.words.count());
        var entries = other.words.iterator();
        while (entries.next()) |entry| {
            const destination = self.words.getOrPutAssumeCapacity(entry.key_ptr.*);
            if (!destination.found_existing) destination.value_ptr.* = 0;
            self.count += @popCount(entry.value_ptr.* & ~destination.value_ptr.*);
            destination.value_ptr.* |= entry.value_ptr.*;
        }
    }
};
const Guards = struct {
    const Position = struct { at: u32, local: u32 };
    graph: cfg.Graph,
    reachable: []bool,
    cache: Positions = .{},
    pending: std.ArrayList(Position) = .empty,
    seen: Positions = .{},
    fn init(a: A, body: *const ir.Function) A.Error!Guards {
        var graph = try cfg.Graph.init(a, body.instructions.items);
        errdefer graph.deinit(a);
        const reachable = try a.alloc(bool, graph.nodes.len);
        errdefer a.free(reachable);
        @memset(reachable, false);
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(a);
        try pending.append(a, 0);
        reachable[0] = true;
        var cursor: usize = 0;
        while (cursor < pending.items.len) : (cursor += 1) for (graph.nodes[pending.items[cursor]].next) |next| {
            if (next == cfg.absent or reachable[next]) continue;
            reachable[next] = true;
            try pending.append(a, next);
        };
        return .{ .graph = graph, .reachable = reachable };
    }
    fn deinit(self: *Guards, a: A) void {
        self.graph.deinit(a);
        a.free(self.reachable);
        self.cache.deinit(a);
        self.pending.deinit(a);
        self.seen.deinit(a);
    }
    fn nonnull(self: *Guards, a: A, body: *const ir.Function, constructions: []const origins.Fact, at: u32, local: u32) A.Error!bool {
        if (self.cache.contains(at, local)) return true;
        if (!self.reachable[at]) return true;
        const pending = &self.pending;
        const seen = &self.seen;
        pending.clearRetainingCapacity();
        seen.clear();
        try pending.append(a, .{ .at = at, .local = local });
        var valid = true;
        var cursor: usize = 0;
        while (cursor < pending.items.len) : (cursor += 1) {
            if (cursor == 16384) {
                valid = false;
                break;
            }
            const point = pending.items[cursor];
            if (self.cache.contains(point.at, point.local)) continue;
            if (try seen.insert(a, point.at, point.local)) continue;
            if (point.at == 0) {
                valid = false;
                break;
            }
            var edge = self.graph.nodes[point.at].first;
            if (edge == cfg.absent) {
                valid = false;
                break;
            }
            while (edge != cfg.absent) {
                const predecessor = self.graph.predecessors.items[edge];
                edge = predecessor.next;
                const before = predecessor.from;
                if (!self.reachable[before]) continue;
                const inst = body.instructions.items[before];
                if (inst.op == .end and before >= 4) {
                    const guard = body.instructions.items[before - 4 .. before + 1];
                    if (guard[0].op == .local_get and guard[0].operand == point.local and guard[1].op == .i32_eqz and guard[2].op == .if_ and guard[2].operand == 0 and guard[3].op == .unreachable_) continue;
                }
                var tracked = point.local;
                if ((inst.op == .local_set or inst.op == .local_tee) and inst.operand == point.local) {
                    if (before != 0) if (constructionAt(constructions, before - 1)) |fact| if (fact.local == point.local) continue;
                    if (before == 0 or body.instructions.items[before - 1].op != .local_get) {
                        valid = false;
                        break;
                    }
                    tracked = body.instructions.items[before - 1].operand;
                }
                try pending.append(a, .{ .at = before, .local = tracked });
            }
            if (!valid) break;
        }
        if (valid and seen.count <= 16_384 -| self.cache.count) {
            // Bound retained scratch by the existing traversal capacity. A
            // completed query remains valid when the optional cache is full.
            // Every visited state considered all reachable predecessors using
            // only this immutable body's exact copies, guards and constructors.
            // Reserve before publishing: a failed traversal or allocation adds
            // no subproof, and no queried-load path assumption is retained.
            try self.cache.include(a, seen);
        }
        return valid;
    }
};
fn runtimeArgument(module: *const wasm.Module, target: u32, index: usize, values: []const Value) bool {
    const arena = module.arena orelse return false;
    if (module.regions) |regions| {
        if (target == regions.runtime.member_at and index == 0 and values[index].head()) return true;
    }
    if (module.cohorts) |cohorts| {
        if (target == cohorts.begin and index == 0 and values[index].head() and !values[index].borrowed_head) return true;
        if (target == cohorts.allocate and index == 2 and values[index].head()) return true;
    }
    if (index == 0 and values[index].head()) {
        if (target == arena.retain) return true;
        // A source activation may retire its own constructed frame. Its
        // implicit provider and every inherited outer head are borrowed.
        if (!values[index].borrowed_head and (target == arena.release or target == arena.release_lease or target == arena.retire or target == arena.free or target == arena.recycle or target == arena.decrement or target == arena.mark_acyclic)) return true;
    }
    return (index == 0 or index == 1) and target == arena.store_word and values.len == 3 and values[0].head() and values[1].kinds & ordinary == 0 and values[1].offset == 4 and values[1].frame_kinds & ~@as(u8, (1 << 4) | (1 << 5)) == 0 and !values[2].hasFrame();
}
fn arguments(module: *const wasm.Module, target: u32, values: []const Value) bool {
    if (target >= module.functions.items.len) return false;
    const callee = &module.functions.items[target];
    if (values.len != callee.parameters.len or !callee.validProviderParameter()) return false;
    for (values, 0..) |value, index| {
        if (index == callee.provider_parameter) {
            if (!value.head()) return false;
        } else if (value.hasFrame() and !runtimeArgument(module, target, index, values)) return false;
    }
    return true;
}
/// Every possible checked table callable must agree on the provider position.
/// Table entries whose authority is absent, including raw fixtures, decline.
fn indirect(module: *const wasm.Module, signature: u32, values: []const Value) bool {
    if (signature >= module.signatures.items.len) return false;
    for (module.table_functions.items) |target| {
        if (target >= module.functions.items.len) return false;
        const body = &module.functions.items[target];
        if (body.signature != signature) continue;
        if (body.provider_parameter == ir.unknown_provider or !arguments(module, target, values)) return false;
    }
    return true;
}
fn bodyFlow(a: A, module: *const wasm.Module, body: *const ir.Function, frame_kinds: u8, stack_heads: bool) A.Error!bool {
    const count = std.math.add(usize, body.parameters.len, body.locals.items.len) catch return false;
    if (count > 8192 or body.codeLength() > 4096 or !body.validProviderParameter()) return false;
    if (body.provider_parameter == ir.unknown_provider and !body.entry) return false;
    if (stack_heads and body.entry and body.provider_parameter != ir.unknown_provider and body.provider_parameter != ir.no_provider) return false;
    const locals = try a.alloc(Value, count);
    defer a.free(locals);
    @memset(locals, .{});
    const observed = try a.alloc(bool, count);
    defer a.free(observed);
    const versions = try a.alloc(u32, count);
    defer a.free(versions);
    for (body.parameters, 0..) |_, index| locals[index] = .{ .kinds = if (index == body.provider_parameter) frame else ordinary, .constant = null, .frame_kinds = if (index == body.provider_parameter) frame_kinds else 0, .pointer = body.parameterRole(index) == .reference, .borrowed_head = index == body.provider_parameter };
    var constructions: std.ArrayList(origins.Fact) = .empty;
    defer constructions.deinit(a);
    for (body.instructions.items, 0..) |inst, at| {
        if (inst.op != .ownership) continue;
        const mark: ir.Ownership = @bitCast(inst.operand);
        if (mark.kind != .rest or mark.chunk != origins.begin_chunk) continue;
        const fact = origins.constructor(module, body, at) orelse return false;
        if (constructionAt(constructions.items, fact.allocation) != null) return false;
        try constructions.append(a, fact);
    }
    const tracking = stack_heads and constructions.items.len != 0;
    const source_ids = try a.alloc(u64, if (tracking) body.instructions.items.len else 0);
    defer a.free(source_ids);
    @memset(source_ids, 0);
    var source_count: u7 = 0;
    if (stack_heads) for (constructions.items) |fact| {
        if (source_count == 64) return false;
        source_ids[fact.allocation] = @as(u64, 1) << @intCast(source_count);
        source_count += 1;
    };
    var next_sources: [64]u64 = @splat(0);
    var outer_sources: [64]u64 = @splat(0);
    var stack: std.ArrayList(Value) = .empty;
    defer stack.deinit(a);
    var controls: std.ArrayList(Control) = .empty;
    defer controls.deinit(a);
    var guards: ?Guards = null;
    defer if (guards) |*owned| owned.deinit(a);
    const uses = try a.alloc(u64, if (tracking) body.instructions.items.len else 0);
    defer a.free(uses);
    const retirements = try a.alloc(u64, uses.len);
    defer a.free(retirements);
    @memset(uses, 0);
    @memset(retirements, 0);
    // Local classes are a monotone union over every branch and loop iteration.
    // The budget bounds scratch/work and never authorizes incomplete flow.
    for (0..32) |_| {
        stack.clearRetainingCapacity();
        controls.clearRetainingCapacity();
        @memset(versions, 0);
        @memset(observed, false);
        var changed = false;
        for (body.instructions.items, 0..) |inst, at| {
            if (tracking) for (stack.items, 0..) |value, index| {
                const cleanup = inst.op == .call and retirementCall(module, inst.operand) and index + 1 == stack.items.len;
                if (!cleanup and value.hasFrame()) uses[at] |= value.owned_sources;
            };
            switch (inst.op) {
                .ownership => {
                    const marker: ir.Ownership = @bitCast(inst.operand);
                    if (marker.kind != .scope) continue;
                    switch (marker.chunk) {
                        2, 3, 5, 6 => {
                            if (marker.roles >= count or locals[marker.roles].hasFrame()) return false;
                            observed[marker.roles] = true;
                        },
                        4 => {
                            const slot = marker.roles & 8191;
                            const value = marker.roles >> 13;
                            if (slot >= count or value >= count or locals[slot].hasFrame() or locals[value].hasFrame()) return false;
                            observed[slot] = true;
                            observed[value] = true;
                        },
                        else => {},
                    }
                },
                .nop => {},
                .local_get => {
                    if (inst.operand >= count) return false;
                    observed[inst.operand] = true;
                    var value = locals[inst.operand];
                    if (tracking and value.hasFrame()) {
                        const cleanup = at + 1 < body.instructions.items.len and body.instructions.items[at + 1].op == .call and retirementCall(module, body.instructions.items[at + 1].operand);
                        if (!cleanup) uses[at] |= value.owned_sources;
                    }
                    value.local = inst.operand;
                    value.version = versions[inst.operand];
                    for (controls.items) |control| if (control.condition) |condition| {
                        if (condition.local == inst.operand and condition.version == value.version) value.frame_kinds &= if (control.alternate) ~condition.kinds else condition.kinds;
                    };
                    if (dead(controls.items, locals, versions, observed)) value.kinds = 0;
                    try push(a, &stack, value);
                },
                .local_set, .local_tee => {
                    if (inst.operand >= count) return false;
                    const value = pop(&stack) orelse return false;
                    versions[inst.operand] += 1;
                    // A forward definition reaches its later consumers now.
                    // Only a class already consumed needs another full pass.
                    if (merge(&locals[inst.operand], value) and observed[inst.operand]) changed = true;
                    if (inst.op == .local_tee) try push(a, &stack, value);
                },
                .i32_const => try push(a, &stack, .{ .kinds = if (inst.operand == 0 and !inst.table_reference) zero else ordinary, .constant = if (inst.table_reference) null else inst.operand, .pointer = !inst.table_reference and inst.operand < module.globals.items[module.arena.?.static_end].bits and (ir.hasImmortalReference(body.instructions.items, at) or ir.staticConstructor(body.instructions.items, at) != null) }),
                .global_get => try push(a, &stack, .{ .kinds = ordinary, .constant = null, .pointer = module.globals.items[inst.operand].scalar.role() == .reference }),
                .f32_const, .memory_size, .host_ref_null, .host_ref_size => try push(a, &stack, .{ .kinds = ordinary, .constant = null }),
                .i32_load, .f32_load, .v128_load => {
                    const address = pop(&stack) orelse return false;
                    if (!address.hasFrame() and address.kinds != 0 and !address.pointer) return false;
                    if (address.hasFrame()) {
                        const offset = std.math.add(u32, address.offset, inst.operand) catch return false;
                        if (address.kinds & ordinary != 0 or offset % 4 != 0 or address.frame_kinds == 0 or address.local == null or address.version != versions[address.local.?]) return false;
                        if (guards == null) guards = try Guards.init(a, body);
                        if (!guards.?.graph.valid or !try guards.?.nonnull(a, body, constructions.items, @intCast(at), address.local.?)) return false;
                        for (0..8) |kind| {
                            if (address.frame_kinds & (@as(u8, 1) << @intCast(kind)) == 0) continue;
                            const bytes = origins.frameBytes(@intCast(kind)) orelse return false;
                            if (offset >= bytes or inst.op == .v128_load) return false;
                            if (inst.op == .f32_load and (offset != 4 or (kind != 4 and kind != 5))) return false;
                        }
                        if (offset == 8) {
                            try push(a, &stack, .{ .kinds = frame, .constant = null, .frame_kinds = frame_kinds, .borrowed_head = true, .owned_sources = inheritedSources(&next_sources, address.owned_sources) });
                            continue;
                        }
                        if (offset == 20) {
                            const outer = address.frame_kinds & ((1 << 3) | (1 << 7)) != 0;
                            const owner = address.frame_kinds & (1 << 5) != 0;
                            try push(a, &stack, .{ .kinds = @as(u8, if (outer) frame else 0) | @as(u8, if (owner) ordinary else 0), .constant = null, .frame_kinds = if (outer) frame_kinds else 0, .borrowed_head = outer, .owned_sources = if (outer) inheritedSources(&outer_sources, address.owned_sources) else 0 });
                            continue;
                        }
                        if (offset == 12) {
                            try push(a, &stack, .{ .kinds = ordinary, .constant = null, .kind_source = address.local, .kind_version = address.version });
                            continue;
                        }
                    }
                    try push(a, &stack, .{ .kinds = ordinary, .constant = null, .pointer = inst.op == .i32_load });
                },
                .i32_store, .f32_store, .v128_store => {
                    const value = pop(&stack) orelse return false;
                    const address = pop(&stack) orelse return false;
                    if (!address.hasFrame()) {
                        if (value.hasFrame() or (address.kinds != 0 and !address.pointer)) return false;
                        continue;
                    }
                    if (address.kinds & ordinary != 0) return false;
                    const offset = std.math.add(u32, address.offset, inst.operand) catch return false;
                    var initialized: ?origins.Fact = null;
                    for (constructions.items) |fact| {
                        if (at > fact.allocation and at < fact.end) initialized = fact;
                    }
                    if (initialized) |fact| {
                        if (offset == 8 or ((fact.kind == 3 or fact.kind == 7) and offset == 20)) {
                            if (!value.head()) return false;
                            if (tracking) {
                                var sources = address.owned_sources;
                                while (sources != 0) {
                                    const index = @ctz(sources);
                                    sources &= sources - 1;
                                    const parents = if (offset == 8) &next_sources[index] else &outer_sources[index];
                                    if (parents.* | value.owned_sources != parents.*) changed = true;
                                    parents.* |= value.owned_sources;
                                }
                            }
                        } else if (value.hasFrame()) return false;
                        continue;
                    }
                    if (offset != 4 or inst.op == .v128_store or value.hasFrame() or address.frame_kinds & ~@as(u8, (1 << 4) | (1 << 5)) != 0) return false;
                },
                .call, .call_indirect, .call_import => {
                    const signature = ir.call(module, inst);
                    if (signature.parameters.len > stack.items.len) return false;
                    if (inst.op == .call_indirect) {
                        const table = pop(&stack) orelse return false;
                        if (table.hasFrame()) return false;
                    }
                    if (signature.parameters.len > stack.items.len) return false;
                    const start = stack.items.len - signature.parameters.len;
                    const values = stack.items[start..];
                    if (stack_heads and inst.op == .call) {
                        const arena = module.arena.?;
                        inline for (.{ "root_open", "root_close", "root_leave", "root_pop", "root_enter", "root_store", "root_reserve", "root_force" }) |field| if (inst.operand == @field(arena, field)) return false;
                    }
                    if (stack_heads and !dead(controls.items, locals, versions, observed)) for (values, 0..) |value, index| {
                        if (!value.hasFrame() or inst.op != .call or index != 0) continue;
                        const arena = module.arena.?;
                        if (inst.operand == arena.retain) return false;
                        if (tracking and retirementCall(module, inst.operand)) retirements[at] |= value.owned_sources;
                    };
                    if (dead(controls.items, locals, versions, observed)) {
                        // Every frame-kind path here is impossible after its exact
                        // nonnull guard; keep stack effects but grant no head fact.
                    } else if (inst.op == .call_import) {
                        for (values) |value| if (value.hasFrame()) return false;
                    } else if (inst.op == .call) {
                        if (!arguments(module, inst.operand, values)) return false;
                    } else if (!indirect(module, inst.operand, values)) return false;
                    stack.shrinkRetainingCapacity(start);
                    if (signature.result != .none) {
                        var pointer = false;
                        if (inst.op == .call) pointer = module.functions.items[inst.operand].result_role == .reference or module.arena.?.isAllocation(inst.operand);
                        if (inst.op == .call_indirect) pointer = ir.indirectResult(body.instructions.items, at) == .reference;
                        const constructed = constructionAt(constructions.items, at);
                        try push(a, &stack, .{ .kinds = if (constructed != null) frame else ordinary, .constant = null, .pointer = pointer, .frame_kinds = if (constructed) |fact| @as(u8, 1) << @intCast(fact.kind) else 0, .owned_sources = if (tracking) source_ids[at] else 0 });
                    }
                },
                .block, .loop, .if_ => {
                    var condition: ?Condition = null;
                    if (inst.op == .if_) condition = (pop(&stack) orelse return false).condition;
                    try controls.append(a, .{ .height = stack.items.len, .result = inst.operand != 0 and inst.operand != @backingInt(ir.ValueType.none), .condition = condition, .conditional = inst.op == .if_ });
                },
                .else_, .end => {
                    if (controls.items.len == 0) return false;
                    const control = &controls.items[controls.items.len - 1];
                    if (inst.op == .else_ and (!control.conditional or control.alternate)) return false;
                    if (control.result) {
                        const value = pop(&stack) orelse Value{ .kinds = 0, .constant = null };
                        _ = merge(&control.value, value);
                    }
                    if (stack.items.len < control.height) return false;
                    stack.shrinkRetainingCapacity(control.height);
                    if (inst.op == .else_) control.alternate = true;
                    if (inst.op == .end) {
                        const completed = controls.pop().?;
                        if (completed.result) try push(a, &stack, completed.value);
                    }
                },
                .br, .br_if => {
                    if (inst.op == .br_if) _ = pop(&stack) orelse return false;
                    if (inst.operand > controls.items.len) return false;
                    if (inst.operand == controls.items.len) {
                        if (body.result != .none and stack.items.len != 0 and stack.items[stack.items.len - 1].hasFrame()) return false;
                    } else {
                        const target = &controls.items[controls.items.len - 1 - inst.operand];
                        if (target.result and stack.items.len != 0) _ = merge(&target.value, stack.items[stack.items.len - 1]);
                    }
                    if (inst.op == .br) stack.shrinkRetainingCapacity(if (controls.items.len == 0) 0 else controls.items[controls.items.len - 1].height);
                },
                .return_, .unreachable_ => {
                    if (inst.op == .return_ and body.result != .none) {
                        const value = pop(&stack) orelse return false;
                        if (value.hasFrame()) return false;
                    }
                    stack.shrinkRetainingCapacity(if (controls.items.len == 0) 0 else controls.items[controls.items.len - 1].height);
                },
                .i32_eqz, .i32_eq, .i32_ne, .i32_or => {
                    var right = Value{};
                    if (inst.op != .i32_eqz) right = pop(&stack) orelse return false;
                    const left = pop(&stack) orelse return false;
                    var condition: ?Condition = null;
                    if (inst.op == .i32_or) {
                        if (left.condition != null and right.condition != null and left.condition.?.local == right.condition.?.local and left.condition.?.version == right.condition.?.version) condition = .{ .local = left.condition.?.local, .version = left.condition.?.version, .kinds = left.condition.?.kinds | right.condition.?.kinds };
                    } else if (left.kind_source != null and right.constant != null and right.constant.? < 8) {
                        var selected = @as(u8, 1) << @intCast(right.constant.?);
                        if (inst.op == .i32_ne) selected = ~selected;
                        condition = .{ .local = left.kind_source.?, .version = left.kind_version, .kinds = selected };
                    }
                    try push(a, &stack, .{ .kinds = ordinary, .constant = null, .condition = condition });
                },
                .i32_add => {
                    var right = pop(&stack) orelse return false;
                    var left = pop(&stack) orelse return false;
                    if (right.hasFrame()) std.mem.swap(Value, &left, &right);
                    if (left.hasFrame()) {
                        if (!left.head() or right.hasFrame() or right.constant == null or right.constant.? != 4) return false;
                        left.offset = 4;
                        left.constant = null;
                        try push(a, &stack, left);
                    } else try push(a, &stack, .{ .kinds = ordinary, .constant = null, .pointer = left.pointer != right.pointer });
                },
                .i32_sub => {
                    const right = pop(&stack) orelse return false;
                    const left = pop(&stack) orelse return false;
                    if (left.hasFrame() or right.hasFrame()) return false;
                    try push(a, &stack, .{ .kinds = ordinary, .constant = null, .pointer = left.pointer and !right.pointer and right.constant != null });
                },
                .drop => _ = pop(&stack) orelse return false,
                else => {
                    const contract = ir.contract(module, body, inst);
                    for (0..contract.arity) |_| {
                        const value = pop(&stack) orelse return false;
                        if (value.hasFrame()) return false;
                    }
                    if (contract.result != .none) try push(a, &stack, .{ .kinds = ordinary, .constant = null });
                },
            }
        }
        if (controls.items.len != 0 or (body.result != .none and stack.items.len != 0 and stack.items[stack.items.len - 1].hasFrame())) return false;
        if (!changed) {
            if (!stack_heads or source_count == 0) return true;
            if (guards == null) guards = try Guards.init(a, body);
            if (!guards.?.graph.valid) return false;
            if (!try scopeRetirements(a, &guards.?.graph, body.instructions.items, source_ids, retirements)) return false;
            for (uses) |*sources| sources.* = borrowerSources(&next_sources, &outer_sources, sources.*);
            return protectedBorrowers(a, &guards.?.graph, guards.?.reachable, uses, retirements);
        }
    }
    return false;
}
/// A stronger optional law for activation storage: allocation-origin sets flow
/// through aliases and outer links; no path uses or retires an owner twice.
/// Borrowed heads remain protected by their caller through the entire call.
/// Fresh allocation epochs in one body conservatively decline this proof.
pub fn protectedActivations(a: A, module: *const wasm.Module) A.Error!bool {
    return completeMode(a, module, true);
}
pub fn complete(a: A, module: *const wasm.Module) A.Error!bool {
    return completeMode(a, module, false);
}
fn completeMode(a: A, module: *const wasm.Module, stack_heads: bool) A.Error!bool {
    if (module.arena == null or module.mutable_static) return false;
    var frame_kinds: u8 = 0;
    for (module.functions.items) |*body| for (body.instructions.items, 0..) |inst, at| {
        if (inst.op != .ownership) continue;
        const marker: ir.Ownership = @bitCast(inst.operand);
        if (marker.kind != .rest or marker.chunk != origins.begin_chunk) continue;
        const fact = origins.constructor(module, body, at) orelse return false;
        frame_kinds |= @as(u8, 1) << @intCast(fact.kind);
    };
    for (module.functions.items, 0..) |*body, id| {
        if (module.runtimeHelper(id)) continue;
        if (!try bodyFlow(a, module, body, frame_kinds, stack_heads)) return false;
    }
    return true;
}

fn scopeRetirements(a: A, graph: *const cfg.Graph, code: []const ir.Instruction, sources: []const u64, retirements: []u64) A.Error!bool {
    const Position = struct { at: u32, depth: u8 };
    const states = std.math.mul(usize, graph.nodes.len, 65) catch return false;
    const seen = try a.alloc(bool, states);
    defer a.free(seen);
    var pending: std.ArrayList(Position) = .empty;
    defer pending.deinit(a);
    var work: usize = 262144;
    for (sources, 0..) |source, start| {
        if (source == 0) continue;
        @memset(seen, false);
        pending.clearRetainingCapacity();
        for (graph.nodes[start].next) |next| if (next != cfg.absent) {
            try pending.append(a, .{ .at = next, .depth = 0 });
        };
        var cursor: usize = 0;
        while (cursor < pending.items.len) : (cursor += 1) {
            if (work == 0) return false;
            work -= 1;
            const point = pending.items[cursor];
            if (point.at >= code.len) continue;
            const key = @as(usize, point.at) * 65 + point.depth;
            if (seen[key]) continue;
            seen[key] = true;
            var depth = point.depth;
            const inst = code[point.at];
            if (inst.op == .ownership) {
                const mark: ir.Ownership = @bitCast(inst.operand);
                if (mark.kind == .scope) {
                    if (mark.chunk == 0) {
                        if (depth == 64) return false;
                        depth += 1;
                    } else if (mark.chunk == 1 or mark.chunk == 2) {
                        if (depth == 0) {
                            retirements[point.at] |= source;
                            continue;
                        }
                        depth -= 1;
                    }
                }
            }
            for (graph.nodes[point.at].next) |next| if (next != cfg.absent) {
                try pending.append(a, .{ .at = next, .depth = depth });
            };
        }
    }
    return true;
}
fn retirementCall(module: *const wasm.Module, target: u32) bool {
    const arena = module.arena.?;
    if (target >= module.functions.items.len or module.functions.items[target].parameters.len != 1) return false;
    inline for (.{ "release", "release_lease", "free", "recycle", "retire", "decrement" }) |field| if (target == @field(arena, field)) return true;
    return false;
}
fn inheritedSources(parents: *const [64]u64, initial: u64) u64 {
    var sources = initial;
    var result: u64 = 0;
    while (sources != 0) {
        const index = @ctz(sources);
        sources &= sources - 1;
        result |= parents[index];
    }
    return result;
}
fn borrowerSources(next: *const [64]u64, outer: *const [64]u64, initial: u64) u64 {
    var result = initial;
    var pending = initial;
    while (pending != 0) {
        const index = @ctz(pending);
        pending &= pending - 1;
        const parents = next[index] | outer[index];
        pending |= parents & ~result;
        result |= parents;
    }
    return result;
}
fn protectedBorrowers(a: A, graph: *const cfg.Graph, reachable: []const bool, uses: []const u64, retirements: []const u64) A.Error!bool {
    const retired = try a.alloc(u64, graph.nodes.len);
    defer a.free(retired);
    @memset(retired, 0);
    var pending: std.ArrayList(u32) = .empty;
    defer pending.deinit(a);
    for (retirements, 0..) |sources, at| {
        if (sources == 0 or !reachable[at]) continue;
        for (graph.nodes[at].next) |next| {
            if (next == cfg.absent or retired[next] | sources == retired[next]) continue;
            retired[next] |= sources;
            try pending.append(a, next);
        }
    }
    var cursor: usize = 0;
    while (cursor < pending.items.len) : (cursor += 1) {
        const at = pending.items[cursor];
        if (at < uses.len and retired[at] & (uses[at] | retirements[at]) != 0) return false;
        for (graph.nodes[at].next) |next| {
            if (next == cfg.absent or retired[next] | retired[at] == retired[next]) continue;
            retired[next] |= retired[at];
            try pending.append(a, next);
        }
    }
    return true;
}

test "provider retirement protects transitive outer borrowers cleanup and allocation epochs" {
    const a = std.testing.allocator;
    const code = [_]ir.Instruction{ .{ .op = .nop }, .{ .op = .nop }, .{ .op = .nop }, .{ .op = .nop }, .{ .op = .nop } };
    var graph = try cfg.Graph.init(a, &code);
    defer graph.deinit(a);
    var next: [64]u64 = @splat(0);
    var outer: [64]u64 = @splat(0);
    next[1] = 1;
    outer[2] = 2;
    try std.testing.expectEqual(@as(u64, 7), borrowerSources(&next, &outer, 4));
    try std.testing.expect(!try protectedBorrowers(a, &graph, &@as([6]bool, @splat(true)), &.{ 1, 2, 0, borrowerSources(&next, &outer, 2), 0 }, &.{ 0, 0, 1, 0, 2 }));
    // The inner owner can close before a remaining outer read. Merely closing
    // its own slot does not observe or retire its borrowed outer head.
    try std.testing.expect(try protectedBorrowers(a, &graph, &@as([6]bool, @splat(true)), &.{ 1, 3, 0, 1, 0 }, &.{ 0, 0, 2, 0, 1 }));
    try std.testing.expect(!try protectedBorrowers(a, &graph, &@as([6]bool, @splat(true)), &.{ 1, 0, 0, 0, 0 }, &.{ 0, 1, 0, 1, 0 }));
    const loop = [_]ir.Instruction{ .{ .op = .loop }, .{ .op = .nop }, .{ .op = .nop }, .{ .op = .br }, .{ .op = .end } };
    var loop_graph = try cfg.Graph.init(a, &loop);
    defer loop_graph.deinit(a);
    try std.testing.expect(!try protectedBorrowers(a, &loop_graph, &@as([6]bool, @splat(true)), &.{ 0, 1, 0, 0, 0 }, &.{ 0, 0, 1, 0, 0 }));
}

const GuardFixture = struct {
    a: A,
    body: ir.Function,
    const Query = struct { at: u32, local: u32 = 0, expected: bool };
    fn append(self: *GuardFixture, code: []const ir.Instruction) A.Error!void {
        try self.body.instructions.appendSlice(self.a, code);
    }
    fn guard(self: *GuardFixture, local: u32) A.Error!void {
        try self.append(&.{ .{ .op = .local_get, .operand = local }, .{ .op = .i32_eqz }, .{ .op = .if_ }, .{ .op = .unreachable_ }, .{ .op = .end } });
    }
    fn load(self: *GuardFixture, local: u32) A.Error!u32 {
        const at: u32 = @intCast(self.body.instructions.items.len + 1);
        try self.append(&.{ .{ .op = .local_get, .operand = local }, .{ .op = .i32_load }, .{ .op = .drop } });
        return at;
    }
    fn check(self: *GuardFixture, queries: []const Query, allocations: []const usize) !void {
        var guards = try Guards.init(self.a, &self.body);
        defer guards.deinit(self.a);
        try std.testing.expect(guards.graph.valid);
        const constructions = try self.a.alloc(origins.Fact, allocations.len);
        defer self.a.free(constructions);
        // The standalone guard reader receives constructor facts only after
        // ordinary producer validation; separate Source laws cover rederivation.
        for (allocations, constructions) |at, *fact| fact.* = .{ .local = self.body.instructions.items[at + 1].operand, .kind = 4, .value_role = .scalar, .value_machine = .i32, .read = 1, .write = 2, .allocation = at, .end = at + 1 };
        for (queries) |query| {
            const before = guards.cache.count;
            const result = guards.nonnull(self.a, &self.body, constructions, query.at, query.local) catch |err| {
                try std.testing.expectEqual(before, guards.cache.count);
                return err;
            };
            try std.testing.expectEqual(query.expected, result);
            try std.testing.expect(guards.cache.count <= 16_384);
            if (result) {
                try std.testing.expect(guards.cache.count > 1);
            } else try std.testing.expectEqual(before, guards.cache.count);
        }
    }
};
fn guardSharingScenario(a: A) !void {
    var parameters = [_]ir.ValueType{ .i32, .i32, .i32, .i32 };
    var fixture: GuardFixture = .{ .a = a, .body = .{ .parameters = &parameters, .result = .none, .signature = 0, .provider_parameter = ir.no_provider, .parameter_roles = ir.packParameterRoles(&.{ .reference, .reference, .reference, .scalar }) } };
    defer fixture.body.deinit(a);
    const before_guard = try fixture.load(0);
    try fixture.guard(0);
    const guarded = try fixture.load(0);
    const later = try fixture.load(0);
    try fixture.append(&.{ .{ .op = .i32_const }, .{ .op = .local_set } });
    const rebound = try fixture.load(0);
    try fixture.check(&.{ .{ .at = guarded, .expected = true }, .{ .at = later, .expected = true }, .{ .at = before_guard, .expected = false }, .{ .at = rebound, .expected = false } }, &.{});

    fixture.body.instructions.clearRetainingCapacity();
    try fixture.append(&.{ .{ .op = .local_get, .operand = 3 }, .{ .op = .if_ } });
    try fixture.guard(0);
    const selected = try fixture.load(0);
    try fixture.append(&.{.{ .op = .else_ }});
    const alternate = try fixture.load(0);
    try fixture.append(&.{.{ .op = .end }});
    const joined = try fixture.load(0);
    try fixture.check(&.{ .{ .at = selected, .expected = true }, .{ .at = alternate, .expected = false }, .{ .at = joined, .expected = false } }, &.{});

    fixture.body.instructions.clearRetainingCapacity();
    try fixture.append(&.{ .{ .op = .local_get, .operand = 3 }, .{ .op = .if_ } });
    try fixture.guard(0);
    try fixture.append(&.{.{ .op = .else_ }});
    try fixture.guard(0);
    try fixture.append(&.{.{ .op = .end }});
    const both = try fixture.load(0);
    try fixture.check(&.{.{ .at = both, .expected = true }}, &.{});

    fixture.body.instructions.clearRetainingCapacity();
    try fixture.guard(0);
    try fixture.append(&.{ .{ .op = .local_get }, .{ .op = .local_set, .operand = 1 } });
    const copied = try fixture.load(1);
    try fixture.append(&.{ .{ .op = .local_get, .operand = 2 }, .{ .op = .local_set } });
    const changed = try fixture.load(0);
    const preserved = try fixture.load(1);
    try fixture.check(&.{ .{ .at = copied, .local = 1, .expected = true }, .{ .at = changed, .expected = false }, .{ .at = preserved, .local = 1, .expected = true } }, &.{});

    fixture.body.instructions.clearRetainingCapacity();
    try fixture.append(&.{.{ .op = .loop }});
    const unseeded = try fixture.load(0);
    try fixture.append(&.{ .{ .op = .local_get, .operand = 3 }, .{ .op = .br_if }, .{ .op = .end } });
    try fixture.check(&.{.{ .at = unseeded, .expected = false }}, &.{});

    fixture.body.instructions.clearRetainingCapacity();
    try fixture.append(&.{.{ .op = .loop }});
    try fixture.guard(0);
    const iteration = try fixture.load(0);
    try fixture.append(&.{ .{ .op = .i32_const }, .{ .op = .local_set } });
    const expired = try fixture.load(0);
    try fixture.append(&.{ .{ .op = .local_get, .operand = 3 }, .{ .op = .br_if }, .{ .op = .end } });
    try fixture.check(&.{ .{ .at = iteration, .expected = true }, .{ .at = expired, .expected = false } }, &.{});

    fixture.body.instructions.clearRetainingCapacity();
    try fixture.append(&.{ .{ .op = .call }, .{ .op = .local_set } });
    const constructed = try fixture.load(0);
    try fixture.append(&.{ .{ .op = .i32_const }, .{ .op = .local_set } });
    const old_epoch = try fixture.load(0);
    const allocation = fixture.body.instructions.items.len;
    try fixture.append(&.{ .{ .op = .call }, .{ .op = .local_set } });
    const next_epoch = try fixture.load(0);
    try fixture.check(&.{ .{ .at = constructed, .expected = true }, .{ .at = old_epoch, .expected = false }, .{ .at = next_epoch, .expected = true } }, &.{ 0, allocation });
    // Same PCs in a fresh context with no constructor proof acquire no cache.
    try fixture.check(&.{ .{ .at = constructed, .expected = false }, .{ .at = next_epoch, .expected = false } }, &.{});
}
test "provider nonnull completed subproofs preserve branch joins aliases epochs and fresh contexts through OOM" {
    try guardSharingScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, guardSharingScenario, .{});
}
test "provider nonnull traversal cutoff publishes no partial positive subproof" {
    const a = std.testing.allocator;
    var parameters = [_]ir.ValueType{.i32};
    var fixture: GuardFixture = .{ .a = a, .body = .{ .parameters = &parameters, .result = .none, .signature = 0 } };
    defer fixture.body.deinit(a);
    try fixture.guard(0);
    // Exercise the guard reader's own unchanged16384 traversal bound directly;
    // Source body admission independently retains its smaller4096 code bound.
    try fixture.body.instructions.appendNTimes(a, .{ .op = .nop }, 16_384 + 8);
    const at = try fixture.load(0);
    try fixture.check(&.{.{ .at = at, .expected = false }}, &.{});
}

test "provider nonnull full scratch cache keeps complete proofs within the original traversal capacity" {
    const a = std.testing.allocator;
    var parameters = [_]ir.ValueType{.i32};
    var fixture: GuardFixture = .{ .a = a, .body = .{ .parameters = &parameters, .result = .none, .signature = 0 } };
    defer fixture.body.deinit(a);
    try fixture.guard(0);
    try fixture.body.instructions.appendNTimes(a, .{ .op = .nop }, 16_384 - 8);
    var queries: [5]GuardFixture.Query = undefined;
    for (&queries) |*query| query.* = .{ .at = try fixture.load(0), .expected = true };
    try fixture.check(&queries, &.{});
}

fn observedOwnership(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    _ = try module.ensureArena();
    const id = try module.addTypedFunction(&.{.i32}, .none, .scalar);
    try module.setParameterRoles(id, ir.packParameterRoles(&.{.reference}));
    module.functions.items[id].provider_parameter = 0;
    const local = try module.addLocal(id, .i32);
    const observe: ir.Instruction = .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 3, .roles = @intCast(local) }) };
    try module.emitSlice(id, &.{ observe, .{ .op = .local_get }, .{ .op = .local_set, .operand = local } });
    // This consumer reads a class without a local_get. The later provider
    // assignment must revisit it and reject ordinary journal ownership.
    try std.testing.expect(!try bodyFlow(a, &module, &module.functions.items[id], 1 << 4, false));
    module.functions.items[id].instructions.items[0] = .{ .op = .nop };
    try std.testing.expect(try bodyFlow(a, &module, &module.functions.items[id], 1 << 4, false));
    try std.testing.expect(try bodyFlow(a, &module, &module.functions.items[id], 1 << 4, true));
    const length = module.functions.items[id].instructions.items.len;
    try module.emitSlice(id, &.{ .{ .op = .block }, .{ .op = .else_ }, .{ .op = .end } });
    try std.testing.expect(!try bodyFlow(a, &module, &module.functions.items[id], 1 << 4, false));
    module.functions.items[id].instructions.shrinkRetainingCapacity(length);
    try module.emitSlice(id, &.{ .{ .op = .i32_const, .operand = 1 }, .{ .op = .if_ }, .{ .op = .else_ }, .{ .op = .else_ }, .{ .op = .end } });
    try std.testing.expect(!try bodyFlow(a, &module, &module.functions.items[id], 1 << 4, false));
}
test "provider flow revisits earlier ownership consumers after later local classification through OOM" {
    try observedOwnership(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, observedOwnership, .{});
}

fn packedPositions(a: A) !void {
    var left: Positions = .{};
    defer left.deinit(a);
    var right: Positions = .{};
    defer right.deinit(a);
    for ([_]u32{ 0, 63, 64, 127, 128, 4095 }) |at| {
        try std.testing.expect(!try left.insert(a, at, 8191));
        try std.testing.expect(try left.insert(a, at, 8191));
        try std.testing.expect(!left.contains(at, 8190));
        try std.testing.expect(!try right.insert(a, at, 8190));
        try std.testing.expect(!try right.insert(a, at, 8191));
    }
    const count = left.count;
    left.include(a, &right) catch |err| {
        try std.testing.expectEqual(count, left.count);
        for ([_]u32{ 0, 63, 64, 127, 128, 4095 }) |at| try std.testing.expect(!left.contains(at, 8190));
        return err;
    };
    try std.testing.expectEqual(@as(u32, 12), left.count);
    try left.include(a, &right);
    try std.testing.expectEqual(@as(u32, 12), left.count);
    left.clear();
    try std.testing.expectEqual(@as(u32, 0), left.count);
    try std.testing.expect(!left.contains(64, 8191));
}
test "provider packed positions keep instruction words and local aliases distinct and publish atomically through OOM" {
    try packedPositions(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, packedPositions, .{});
}
