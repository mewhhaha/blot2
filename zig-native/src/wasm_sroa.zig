//! Scalar replacement of small nonescaping allocations in symbolic Wasm.
//! Copies get distinct scalar slots (including loop carries); stores are admitted
//! only into freshly allocated locals before any alias is copied. ABI values,
//! calls, unknown offsets, mutable aliases and GC roots keep ordinary storage.
const std = @import("std");
const w = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const A = std.mem.Allocator;
const none = std.math.maxInt(u32);
const Value = struct { id: u32 = 0, offset: u32 = 0, constant: ?u32 = null };
const Node = struct { parent: u32, bad: bool = false, size: u32 = 0, allocation: bool = false, first_copy: u32 = none, last_store: u32 = 0, store_mask: u32 = 0, scope: usize = 0, fields: u32 = 0, used_fields: u16 = 0, journaled: bool = false, untyped: bool = false, reference_fields: u16 = 0, roots: u32 = 0, root_fields: u16 = 0, shared_roots: bool = false, nullable: bool = false, journal_carrier: bool = false, zero_fields: u16 = 0, nonzero_fields: u16 = 0, control_start: usize = 0, control_end: usize = 0 };
const Event = struct { input: Value = .{}, stored: Value = .{}, destination: u32 = 0, field: u32 = 0, allocation: u32 = 0, fresh: bool = false, static_words: bool = false, loop_scope: usize = 0, nonzero: bool = false };
const Control = struct { height: usize, result: u32, unreachable_: bool = false, entry_unreachable: bool = false, conditional: bool = false, has_else: bool = false, then_live: bool = false, has_exit: bool = false, identity: usize = 0, loop_: bool = false };
pub const Output = ir.Body;
const Analysis = struct {
    a: A,
    nodes: std.ArrayList(Node) = .empty,
    stack: std.ArrayList(Value) = .empty,
    controls: std.ArrayList(Control) = .empty,
    events: []Event,
    constants: []?u32,
    constant_scopes: []?usize,
    defined_scopes: []?usize,
    zero_locals: []const bool,
    valid: bool = true,
    owning: bool = false,
    children: bool = false,
    fn add(self: *Analysis, bad: bool, size: u32) !u32 {
        const id: u32 = @intCast(self.nodes.items.len);
        try self.nodes.append(self.a, .{ .parent = id, .bad = bad, .size = size });
        return id;
    }
    fn root(self: *Analysis, initial: u32) u32 {
        var id = initial;
        while (self.nodes.items[id].parent != id) id = self.nodes.items[id].parent;
        var next = initial;
        while (next != id) {
            const parent = self.nodes.items[next].parent;
            self.nodes.items[next].parent = id;
            next = parent;
        }
        return id;
    }
    fn escape(self: *Analysis, v: Value) void {
        if (v.id != 0) self.nodes.items[self.root(v.id)].bad = true;
    }
    fn join(self: *Analysis, dst: u32, v: Value) void {
        const target = self.root(dst);
        if (self.children and v.id == 0 and v.constant != null and v.constant.? == 0) {
            self.nodes.items[target].nullable = true;
            return;
        }
        if (v.id == 0 or v.offset != 0) {
            self.nodes.items[target].bad = true;
            self.escape(v);
            return;
        }
        const source = self.root(v.id);
        if (target == source) return;
        const right = self.nodes.items[source];
        const left = &self.nodes.items[target];
        left.bad = left.bad or right.bad or (left.size != 0 and right.size != 0 and left.size != right.size);
        if (left.size != 0 and right.size != 0 and (left.reference_fields != right.reference_fields or left.journal_carrier != right.journal_carrier)) left.bad = true;
        left.size = @max(left.size, right.size);
        left.reference_fields |= right.reference_fields;
        left.journaled = left.journaled or right.journaled;
        left.untyped = left.untyped or right.untyped;
        left.nullable = left.nullable or right.nullable;
        left.journal_carrier = left.journal_carrier or right.journal_carrier;
        left.zero_fields |= right.zero_fields;
        left.nonzero_fields |= right.nonzero_fields;
        self.nodes.items[source].parent = target;
    }
    fn push(self: *Analysis, v: Value) !void {
        try self.stack.append(self.a, v);
    }
    fn dominates(self: *const Analysis, scope: ?usize) bool {
        const owner = scope orelse return false;
        if (owner == 0) return true;
        for (self.controls.items) |c| if (c.identity == owner) return true;
        return false;
    }
    fn pop(self: *Analysis) Value {
        const floor = if (self.controls.items.len == 0) 0 else self.controls.items[self.controls.items.len - 1].height;
        return if (self.stack.items.len > floor) self.stack.pop().? else .{};
    }
    fn copy(self: *Analysis, at: usize, dst: u32, v: Value) void {
        self.join(dst, v);
        self.events[at].input = v;
        self.events[at].destination = dst;
        if (v.id != 0) self.nodes.items[v.id].first_copy = @min(self.nodes.items[v.id].first_copy, @as(u32, @intCast(at)));
    }
    fn closeArm(self: *Analysis, at: usize) void {
        const c = self.controls.items[self.controls.items.len - 1];
        if (!c.unreachable_ and c.result != 0) self.copy(at, c.result, self.pop());
        self.stack.shrinkRetainingCapacity(c.height);
    }
    fn dead(self: *Analysis) void {
        if (self.controls.items.len != 0) {
            const c = &self.controls.items[self.controls.items.len - 1];
            c.unreachable_ = true;
            self.stack.shrinkRetainingCapacity(c.height);
        } else self.stack.clearRetainingCapacity();
    }
    fn call(self: *Analysis, parameters: usize, result: w.ValueType) !void {
        for (0..parameters) |_| self.escape(self.pop());
        if (result != .none) try self.push(.{});
    }
    fn loopScope(self: *const Analysis) usize {
        var index = self.controls.items.len;
        while (index != 0) {
            index -= 1;
            const control = self.controls.items[index];
            if (control.loop_) return control.identity;
        }
        return 0;
    }
    fn scan(self: *Analysis, module: *const w.Module, function: *const w.Function, instructions: []const w.Instruction) !void {
        for (instructions, 0..) |inst, at| {
            self.events[at].loop_scope = self.loopScope();
            switch (inst.op) {
                .ownership => {
                    const scope: ir.Ownership = @bitCast(inst.operand);
                    if (scope.kind != .scope) continue;
                    switch (scope.chunk) {
                        // A scalar-only object owns no edges. Its zero address
                        // may remain in the journal after replacement; exact
                        // allocation roles must prove that before admission.
                        2, 5 => self.nodes.items[self.root(scope.roles + 1)].journaled = true,
                        6 => self.escape(.{ .id = scope.roles + 1 }),
                        3 => {
                            self.constants[scope.roles] = null;
                            self.constant_scopes[scope.roles] = null;
                            self.escape(.{ .id = scope.roles + 1 });
                        },
                        4 => {
                            self.escape(.{ .id = (scope.roles & 8191) + 1 });
                            self.nodes.items[self.root((scope.roles >> 13) + 1)].journaled = true;
                        },
                        else => {},
                    }
                },
                .i32_const => {
                    var value: Value = .{};
                    if (ir.staticConstructor(instructions, at)) |tag| {
                        const id = try self.add(!self.owning, 8);
                        self.nodes.items[id].reference_fields = 2;
                        self.nodes.items[id].zero_fields = 2;
                        self.events[at].allocation = id;
                        self.events[at].field = tag;
                        self.events[at].static_words = true;
                        value.id = id;
                    }
                    if (value.id == 0 and !inst.table_reference) value.constant = inst.operand;
                    try self.push(value);
                },
                .f32_const, .global_get, .memory_size, .host_ref_null, .host_ref_size => try self.push(.{}),
                .local_get => {
                    // A constant assignment in one arm does not dominate the
                    // other arm, the enclosing continuation, or an earlier use
                    // (locals start at zero). Keep those reads as ordinary locals.
                    if (!self.dominates(self.defined_scopes[inst.operand])) {
                        if (self.children) self.nodes.items[self.root(inst.operand + 1)].nullable = true else self.escape(.{ .id = inst.operand + 1 });
                    }
                    try self.push(if (self.dominates(self.constant_scopes[inst.operand]) and self.constants[inst.operand] != null) .{ .constant = self.constants[inst.operand].? } else .{ .id = inst.operand + 1 });
                },
                .local_set, .local_tee => {
                    const value = self.pop();
                    if (!self.dominates(self.defined_scopes[inst.operand])) self.defined_scopes[inst.operand] = if (self.controls.items.len == 0) 0 else self.controls.items[self.controls.items.len - 1].identity;
                    if (self.constants[inst.operand] != null) {
                        self.constant_scopes[inst.operand] = 0;
                        if (!self.zero_locals[inst.operand] and self.controls.items.len != 0) self.constant_scopes[inst.operand] = self.controls.items[self.controls.items.len - 1].identity;
                    }
                    self.copy(at, inst.operand + 1, value);
                    // Allocation results are always captured immediately by
                    // the emitter; this local owns initialization stores.
                    if (at != 0 and self.events[at - 1].allocation != 0 and !self.events[at - 1].static_words and value.id == self.events[at - 1].allocation) {
                        // A second allocation site into one local would mix
                        // initialization masks from distinct control paths.
                        if (self.nodes.items[inst.operand + 1].allocation) self.escape(value);
                        self.nodes.items[inst.operand + 1].allocation = true;
                        self.events[at].fresh = true;
                        self.nodes.items[inst.operand + 1].scope = if (self.controls.items.len == 0) 0 else self.controls.items[self.controls.items.len - 1].identity;
                    }
                    if (inst.op == .local_tee) try self.push(.{ .id = inst.operand + 1 });
                },
                .i32_add => {
                    var right = self.pop();
                    var left = self.pop();
                    if (left.constant != null) std.mem.swap(Value, &left, &right);
                    if (right.constant) |constant| {
                        if (left.constant) |other| try self.push(.{ .constant = other +% constant }) else {
                            left.offset +%= constant;
                            try self.push(left);
                        }
                    } else {
                        self.escape(left);
                        self.escape(right);
                        try self.push(.{});
                    }
                },
                .i32_load, .f32_load => {
                    const address = self.pop();
                    self.events[at].input = address;
                    self.events[at].field = address.offset +% inst.operand;
                    self.events[at].nonzero = ir.hasNonzeroRead(instructions, at);
                    if (address.id != 0) self.nodes.items[address.id].first_copy = @min(self.nodes.items[address.id].first_copy, @as(u32, @intCast(at)));
                    if (address.id == 0 or self.events[at].field >= 64 or self.events[at].field % 4 != 0) self.escape(address);
                    try self.push(.{});
                },
                .i32_store, .f32_store => {
                    const stored = self.pop();
                    const address = self.pop();
                    if (address.id == 0 or !self.nodes.items[self.root(address.id)].journal_carrier) self.escape(stored);
                    self.events[at].input = address;
                    self.events[at].stored = stored;
                    self.events[at].field = address.offset +% inst.operand;
                    if (address.id != 0) {
                        if (self.events[at].field < 64 and self.events[at].field % 4 == 0) {
                            const bit = @as(u16, 1) << @intCast(self.events[at].field / 4);
                            const group = &self.nodes.items[self.root(address.id)];
                            if (stored.constant != null and stored.constant.? == 0) group.zero_fields |= bit else group.nonzero_fields |= bit;
                        }
                        self.nodes.items[address.id].last_store = @intCast(at);
                        if (self.events[at].field < 64 and self.events[at].field % 4 == 0 and self.nodes.items[address.id].scope == (if (self.controls.items.len == 0) @as(usize, 0) else self.controls.items[self.controls.items.len - 1].identity)) self.nodes.items[address.id].store_mask |= @as(u32, 1) << @intCast(self.events[at].field / 4);
                    }
                    if (address.id == 0 or !self.nodes.items[address.id].allocation or self.events[at].field >= 64 or self.events[at].field % 4 != 0) self.escape(address);
                },
                .call => {
                    const callee = ir.call(module, inst);
                    if (callee.ownership == .allocate or callee.ownership == .allocate_scalar) {
                        const size = self.pop();
                        if (size.constant != null and size.constant.? != 0 and size.constant.? <= 64 and size.constant.? % 4 == 0) {
                            var owns_fields = false;
                            var references: u16 = 0;
                            if (callee.ownership != .allocate_scalar) {
                                const roles = ir.allocationAnnotations(instructions, at);
                                if (roles.len != 0) for (0..size.constant.? / 4) |word| {
                                    const role = ir.Ownership.wordRole(roles, word);
                                    if (role == .reference and self.owning) references |= @as(u16, 1) << @intCast(word) else if (role != .scalar) owns_fields = true;
                                };
                            }
                            const id = try self.add(owns_fields, size.constant.?);
                            self.nodes.items[id].reference_fields = references;
                            self.nodes.items[id].journal_carrier = self.children and self.owning and !owns_fields and ir.allocationAnnotations(instructions, at).len != 0 and ir.hasJournalCarrier(instructions, at);
                            self.nodes.items[id].untyped = callee.ownership != .allocate_scalar and ir.allocationAnnotations(instructions, at).len == 0;
                            self.events[at].allocation = id;
                            try self.push(.{ .id = id });
                        } else {
                            self.escape(size);
                            try self.push(.{});
                        }
                    } else if (module.arena != null and inst.operand == module.arena.?.mark_acyclic) {
                        // This flag affects only the allocation being removed.
                        // Ordinary heap objects retain their marker call.
                        self.events[at].input = self.pop();
                    } else if (self.owning and module.arena != null and (inst.operand == module.arena.?.collect or inst.operand == module.arena.?.recycle)) {
                        for (0..callee.parameters.len) |parameter| {
                            const input = self.pop();
                            if (parameter + 1 != callee.parameters.len or input.id == 0 or !self.nodes.items[self.root(input.id)].journal_carrier) self.escape(input);
                        }
                        if (callee.result != .none) try self.push(.{});
                    } else try self.call(callee.parameters.len, callee.result);
                },
                .call_indirect => {
                    self.escape(self.pop());
                    const signature = ir.call(module, inst);
                    try self.call(signature.parameters.len, signature.result);
                },
                .call_import => {
                    const signature = ir.call(module, inst);
                    try self.call(signature.parameters.len, signature.result);
                },
                .block, .loop, .if_ => {
                    if (inst.op == .if_) self.escape(self.pop());
                    const result = if (inst.operand != 0 and inst.operand != @backingInt(w.ValueType.none)) try self.add(false, 0) else 0;
                    // Current loop carries use locals. Value-producing Wasm
                    // loops have a different label arity from blocks.
                    if (inst.op == .loop and result != 0) {
                        self.valid = false;
                        return;
                    }
                    if (result != 0) self.nodes.items[result].control_start = at + 1;
                    var entry_unreachable = false;
                    if (self.controls.items.len != 0) entry_unreachable = self.controls.items[self.controls.items.len - 1].unreachable_;
                    try self.controls.append(self.a, .{ .height = self.stack.items.len, .result = result, .identity = at + 1, .loop_ = inst.op == .loop, .conditional = inst.op == .if_, .entry_unreachable = entry_unreachable, .unreachable_ = entry_unreachable });
                },
                .else_ => {
                    if (self.controls.items.len == 0) {
                        self.valid = false;
                        return;
                    }
                    self.closeArm(at);
                    const control = &self.controls.items[self.controls.items.len - 1];
                    control.then_live = !control.unreachable_;
                    control.has_else = true;
                    control.unreachable_ = control.entry_unreachable;
                    control.identity = at + 1;
                },
                .end => {
                    if (self.controls.items.len == 0) {
                        self.valid = false;
                        return;
                    }
                    self.closeArm(at);
                    const c = self.controls.pop().?;
                    var exits = !c.unreachable_ or c.has_exit;
                    if (c.conditional and !c.entry_unreachable and (!c.has_else or c.then_live)) exits = true;
                    if (!exits and self.controls.items.len != 0) self.controls.items[self.controls.items.len - 1].unreachable_ = true;
                    if (c.result != 0) {
                        self.nodes.items[c.result].control_end = at + 1;
                        try self.push(.{ .id = c.result });
                    }
                },
                .br, .br_if => {
                    if (inst.op == .br_if) self.escape(self.pop());
                    if (inst.operand >= self.controls.items.len) {
                        self.valid = false;
                        return;
                    }
                    const target = self.controls.items.len - 1 - inst.operand;
                    const c = self.controls.items[target];
                    const reachable = !self.controls.items[self.controls.items.len - 1].unreachable_;
                    if (reachable and !c.loop_) self.controls.items[target].has_exit = true;
                    if (reachable and c.result != 0) {
                        if (inst.op == .br_if) { // Keep conditional result transfers boxed.
                            if (self.stack.items.len != 0) self.escape(self.stack.items[self.stack.items.len - 1]);
                            self.nodes.items[self.root(c.result)].bad = true;
                        } else self.copy(at, c.result, self.pop());
                    }
                    if (inst.op == .br) self.dead();
                },
                .return_ => {
                    if (function.result != .none) self.escape(self.pop());
                    self.dead();
                },
                .unreachable_ => self.dead(),
                .drop => {
                    _ = self.pop();
                },
                else => {
                    const contract = ir.contract(module, function, inst);
                    for (0..contract.arity) |_| self.escape(self.pop());
                    if (contract.result != .none) try self.push(.{});
                },
            }
        }
        if (function.result != .none) self.escape(self.pop());
        for (self.nodes.items, 0..) |node, id| if (node.first_copy < node.last_store or (node.allocation and node.store_mask != (@as(u32, 1) << @intCast(self.nodes.items[self.root(@intCast(id))].size / 4)) - 1)) {
            self.nodes.items[self.root(@intCast(id))].bad = true;
        };
        for (self.events) |event| if (event.input.id != 0 and event.destination == 0 and event.allocation == 0) {
            const root_ = self.root(event.input.id);
            if (event.field >= self.nodes.items[root_].size) self.nodes.items[root_].bad = true;
        };
        for (instructions, self.events) |inst, event| {
            if ((inst.op != .i32_load and inst.op != .f32_load) or event.input.id == 0) continue;
            const family = self.root(event.input.id);
            if (self.nodes.items[family].journal_carrier or (self.nodes.items[family].nullable and !event.nonzero)) self.nodes.items[family].bad = true;
        }
        // Only a removed carrier may stop its stored children escaping. A
        // malformed, incomplete or externally observed carrier retains every
        // child address, including chains of compiler carriers.
        var changed = true;
        while (changed) {
            changed = false;
            for (self.events) |event| {
                if (event.input.id == 0 or event.stored.id == 0 or !self.nodes.items[self.root(event.input.id)].journal_carrier or self.selected(event.input.id)) continue;
                const child = self.root(event.stored.id);
                if (!self.nodes.items[child].bad) {
                    self.nodes.items[child].bad = true;
                    changed = true;
                }
            }
        }
    }
    fn selected(self: *Analysis, id: u32) bool {
        if (id == 0) return false;
        const n = self.nodes.items[self.root(id)];
        return !n.bad and n.size != 0 and !(n.journaled and n.untyped);
    }
    fn demandedFields(self: *Analysis) !void {
        // Copies are snapshots, but only fields subsequently read need slots.
        // Propagate demand backwards through copies, including loop carries
        // and both branch arms. One field can enter a node only once.
        const Edge = struct { source: u32, next: u32 };
        const heads = try self.a.alloc(u32, self.nodes.items.len);
        defer self.a.free(heads);
        @memset(heads, none);
        var edges: std.ArrayList(Edge) = .empty;
        defer edges.deinit(self.a);
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(self.a);
        for (self.events) |event| {
            if (event.destination != 0 and event.input.id != 0 and !event.fresh and self.selected(event.destination)) {
                const index: u32 = @intCast(edges.items.len);
                try edges.append(self.a, .{ .source = event.input.id, .next = heads[event.destination] });
                heads[event.destination] = index;
            }
        }
        for (self.nodes.items, 0..) |node, id| if (node.used_fields != 0) try pending.append(self.a, @intCast(id));
        while (pending.pop()) |destination| {
            const needed = self.nodes.items[destination].used_fields;
            var index = heads[destination];
            while (index != none) {
                const edge = edges.items[index];
                const source = &self.nodes.items[edge.source];
                if ((source.used_fields | needed) != source.used_fields) {
                    source.used_fields |= needed;
                    try pending.append(self.a, edge.source);
                }
                index = edge.next;
            }
        }
    }
    // A single constructor allocation, or an immutable alternative, produces
    // one value per enclosing loop activation. All aliases stay in that same
    // loop and no nested loop can revisit the producer. Their reference slots
    // therefore retain the same value until every admitted alias is consumed.
    // Carries/snapshots outside that activation keep independent roots.
    fn shareFieldRoots(self: *Analysis, instructions: []const w.Instruction) void {
        for (0..self.nodes.items.len) |id| {
            const family = self.nodes.items[self.root(@intCast(id))];
            self.nodes.items[id].root_fields = self.nodes.items[id].used_fields & ~(family.zero_fields & ~family.nonzero_fields);
        }
        for (0..self.nodes.items.len) |id| {
            const candidate = self.nodes.items[id];
            if (candidate.control_start == 0 or candidate.control_end == 0 or !self.selected(@intCast(id))) continue;
            const family = self.root(@intCast(id));
            if (self.nodes.items[family].shared_roots or self.nodes.items[family].reference_fields == 0 or self.nodes.items[family].nullable) continue;
            const start = candidate.control_start - 1;
            const end = candidate.control_end - 1;
            const activation = self.events[start].loop_scope;
            var admitted = true;
            for (instructions[start..end]) |inst| if (inst.op == .loop) {
                admitted = false;
                break;
            };
            if (!admitted) continue;
            var allocations: usize = 0;
            var statics: usize = 0;
            for (self.events, 0..) |event, at| {
                if (event.allocation != 0 and self.root(event.allocation) == family) {
                    if (at <= start or at >= end) {
                        admitted = false;
                        break;
                    }
                    if (event.static_words) statics += 1 else allocations += 1;
                }
                if ((event.input.id != 0 and self.root(event.input.id) == family) or
                    (event.destination != 0 and self.root(event.destination) == family))
                {
                    if (event.loop_scope != activation) {
                        admitted = false;
                        break;
                    }
                }
            }
            if (!admitted or allocations != 1 or statics == 0) continue;
            var allocation_at: usize = 0;
            for (self.events, 0..) |event, at| if (event.allocation != 0 and !event.static_words and self.root(event.allocation) == family) {
                allocation_at = at;
            };
            // The producer must evaluate exactly one alternative. An if has
            // disjoint arms. A do block admits only earlier empty returns that
            // branch straight out before reaching the single allocation.
            if (instructions[start].op == .if_) {
                var nesting: usize = 0;
                var alternative: usize = end;
                for (instructions[start + 1 .. end], start + 1..) |inst, at| switch (inst.op) {
                    .block, .loop, .if_ => nesting += 1,
                    .end => nesting -= 1,
                    .else_ => if (nesting == 0) {
                        alternative = at;
                    },
                    else => {},
                };
                for (self.events, 0..) |event, at| if (event.static_words and self.root(event.allocation) == family) {
                    if ((at < alternative) == (allocation_at < alternative)) admitted = false;
                };
            } else if (instructions[start].op == .block) {
                var nesting: usize = 0;
                for (instructions[start + 1 .. end], start + 1..) |inst, at| {
                    const event = self.events[at];
                    if (event.static_words and self.root(event.allocation) == family) {
                        if (at >= allocation_at) {
                            admitted = false;
                            break;
                        }
                        var cursor = at + 1;
                        while (cursor < end and (instructions[cursor].op == .local_get or instructions[cursor].op == .local_set or instructions[cursor].op == .ownership)) cursor += 1;
                        if (cursor == end or instructions[cursor].op != .br or instructions[cursor].operand != nesting) {
                            admitted = false;
                            break;
                        }
                    }
                    switch (inst.op) {
                        .block, .loop, .if_ => nesting += 1,
                        .end => nesting -= 1,
                        else => {},
                    }
                }
            } else admitted = false;
            if (!admitted) continue;
            var fields: u16 = 0;
            for (0..self.nodes.items.len) |member| if (self.root(@intCast(member)) == family) {
                fields |= self.nodes.items[member].used_fields;
            };
            self.nodes.items[family].root_fields = fields & ~(self.nodes.items[family].zero_fields & ~self.nodes.items[family].nonzero_fields);
            self.nodes.items[family].shared_roots = true;
        }
        if (!self.children) for (self.events) |event| if (event.static_words) {
            const family = self.root(event.allocation);
            if (self.nodes.items[family].reference_fields != 0 and !self.nodes.items[family].shared_roots) self.nodes.items[family].bad = true;
        };
    }
    fn fieldLocal(self: *const Analysis, id: u32, field: u32) u32 {
        const node = self.nodes.items[id];
        const lower = (@as(u32, 1) << @intCast(field)) - 1;
        std.debug.assert(node.used_fields & (@as(u16, 1) << @intCast(field)) != 0);
        return node.fields + @popCount(@as(u32, node.used_fields) & lower);
    }
    fn fieldRoot(self: *Analysis, id: u32, field: u32) ?u32 {
        const node = self.nodes.items[id];
        const family = self.root(id);
        const owner = if (self.nodes.items[family].shared_roots) family else id;
        const references = self.nodes.items[family].reference_fields & self.nodes.items[owner].root_fields;
        if (node.used_fields & references & (@as(u16, 1) << @intCast(field)) == 0) return null;
        const lower = (@as(u32, 1) << @intCast(field)) - 1;
        return self.nodes.items[owner].roots + @popCount(@as(u32, references) & lower);
    }
};
fn emit(out: *Output, a: A, op: w.Op, operand: u32) !void {
    try out.instructions.append(a, .{ .op = op, .operand = operand });
}
fn copyFields(out: *Output, analysis: *Analysis, event: Event) !void {
    const a = analysis.a;
    const count = analysis.nodes.items[analysis.root(event.destination)].size / 4;
    // All sources precede all stores: a loop/branch may permute aliases.
    const mask = analysis.nodes.items[event.destination].used_fields;
    for (0..count) |i| if (mask & (@as(u16, 1) << @intCast(i)) != 0) {
        if (event.input.id == 0) try emit(out, a, .i32_const, 0) else try emit(out, a, .local_get, analysis.fieldLocal(event.input.id, @intCast(i)));
    };
    var i = count;
    while (i != 0) {
        i -= 1;
        if (mask & (@as(u16, 1) << @intCast(i)) != 0) try emit(out, a, .local_set, analysis.fieldLocal(event.destination, i));
    }
    if (!analysis.nodes.items[analysis.root(event.destination)].shared_roots) {
        for (0..count) |field| try publishField(out, analysis, event.destination, @intCast(field));
    }
}
fn publishField(out: *Output, analysis: *Analysis, id: u32, field: u32) !void {
    const slot = analysis.fieldRoot(id, field) orelse return;
    const value = analysis.fieldLocal(id, field);
    const scope: ir.Ownership = .{ .kind = .scope, .chunk = 4, .roles = @intCast(slot | (value << 13)) };
    try emit(out, analysis.a, .ownership, @bitCast(scope));
}
// A checked private callback can expose bounded scalar field consumption.
// Internal blocks keep their labels; every local is freshly initialized for
// each activation. Memory writes, allocation, other calls and loops decline.
fn scalarConsumer(body: *const w.Function) bool {
    if (body.result_role != .scalar or body.codeLength() == 0 or body.codeLength() > 96 or body.parameters.len > 4 or body.locals.items.len > 64 - body.parameters.len) return false;
    const count = body.parameters.len + body.locals.items.len;
    for (0..body.parameters.len) |parameter| if (body.parameterRole(parameter) == .unknown) return false;
    for (body.locals.items) |ty| if (ty != .i32 and ty != .f32) return false;
    var depth: usize = 0;
    for (body.instructions.items) |inst| switch (inst.op) {
        .block, .if_ => depth += 1,
        .end => {
            if (depth == 0) return false;
            depth -= 1;
        },
        .else_ => if (depth == 0) return false,
        .br, .br_if => if (inst.operand >= depth) return false,
        .unreachable_ => {},
        .local_get, .local_set, .local_tee => if (inst.operand >= count) return false,
        .ownership => {
            const fact: ir.Ownership = @bitCast(inst.operand);
            if (fact.kind == .scope) return false;
        },
        .i32_load, .f32_load => {},
        else => if (ir.fixed(inst.op).effect != .pure) return false,
    };
    return depth == 0;
}
// A private closure's explicit table reference can expose its tiny projection
// wrapper. The existing initialization/copy proof supplies dominance; numeric
// scalar constants and mutable/imported table values cannot enter this path.
fn projectedCall(analysis: *Analysis, module: *const w.Module, instructions: []const w.Instruction, at: usize) ?u32 {
    if (!analysis.owning) return null;
    var load = at;
    while (load != 0) {
        load -= 1;
        if (instructions[load].op != .ownership) break;
        const annotation: ir.Ownership = @bitCast(instructions[load].operand);
        if (annotation.kind != .call_result) return null;
    }
    if (instructions[load].op != .i32_load) return null;
    const input = analysis.events[load];
    if (!analysis.selected(input.input.id)) return null;
    const family = analysis.root(input.input.id);
    var target: ?u32 = null;
    for (instructions, analysis.events, 0..) |inst, event, index| {
        if ((inst.op != .i32_store and inst.op != .f32_store) or event.input.id == 0 or event.field != input.field or analysis.root(event.input.id) != family) continue;
        if (inst.op != .i32_store) return null;
        if (index == 0) return null;
        const value = instructions[index - 1];
        if (value.op != .i32_const or !value.table_reference) return null;
        if (target) |previous| {
            if (previous != value.operand) return null;
        } else target = value.operand;
    }
    const id = target orelse return null;
    if (id >= module.functions.items.len or module.runtimeHelper(id)) return null;
    const body = &module.functions.items[id];
    if (body.entry or body.signature != instructions[at].operand or body.result_role != .scalar or ir.indirectResult(instructions, at) != .scalar) return null;
    if (body.parameters.len == 0 or body.parameters.len > 4 or body.parameterRole(0) != .reference or body.parameters[0] != .i32) return null;
    if (scalarConsumer(body)) return id;
    if (body.locals.items.len != 0 or body.instructions.items.len != body.parameters.len + 2) return null;
    const code = body.instructions.items;
    if (code[0].op != .local_get or code[0].operand != 0 or code[1].op != .i32_load or code[1].operand != 0) return null;
    for (1..body.parameters.len) |parameter| {
        if (code[parameter + 1].op != .local_get or code[parameter + 1].operand != parameter) return null;
    }
    const call = code[code.len - 1];
    if (call.op != .call or call.operand >= module.functions.items.len or module.runtimeHelper(call.operand)) return null;
    const callee = &module.functions.items[call.operand];
    if (callee.entry or callee.result_role != .scalar or callee.result != body.result or !std.mem.eql(w.ValueType, callee.parameters, body.parameters) or callee.parameterRole(0) != .scalar) return null;
    for (1..body.parameters.len) |parameter| {
        if (body.parameterRole(parameter) == .unknown or body.parameterRole(parameter) != callee.parameterRole(parameter)) return null;
    }
    return id;
}
fn emitProjectedCall(out: *Output, analysis: *Analysis, function: *const w.Function, body: *const w.Function) !void {
    const a = analysis.a;
    const base: u32 = @intCast(function.parameters.len + out.locals.items.len);
    try out.locals.appendSlice(a, body.parameters);
    try out.locals.appendSlice(a, body.locals.items);
    try emit(out, a, .drop, 0); // The checked table index is still on the stack.
    var parameter = body.parameters.len;
    while (parameter != 0) {
        parameter -= 1;
        try emit(out, a, .local_set, base + @as(u32, @intCast(parameter)));
    }
    for (body.locals.items, 0..) |ty, id| {
        var op: w.Op = .i32_const;
        if (ty == .f32) op = .f32_const;
        try emit(out, a, op, 0);
        try emit(out, a, .local_set, base + @as(u32, @intCast(body.parameters.len + id)));
    }
    for (body.instructions.items) |inst| {
        var copy = inst;
        if (copy.op == .local_get or copy.op == .local_set or copy.op == .local_tee) copy.operand += base;
        try out.instructions.append(a, copy);
    }
}
const ReferenceProof = enum { zero, immortal, frame_owned };
fn constantReferenceLocals(a: A, proof: ReferenceProof, module: *const w.Module, parameters: usize, count: usize, instructions: []const w.Instruction) ![]bool {
    const zeros = try a.alloc(bool, count);
    errdefer a.free(zeros);
    @memset(zeros, true);
    const heads = try a.alloc(u32, count);
    defer a.free(heads);
    @memset(heads, none);
    const Edge = struct { destination: u32, next: u32 };
    var edges: std.ArrayList(Edge) = .empty;
    defer edges.deinit(a);
    var pending: std.ArrayList(u32) = .empty;
    defer pending.deinit(a);
    for (0..parameters) |id| {
        zeros[id] = false;
        try pending.append(a, @intCast(id));
    }
    const zero = none - 1;
    var stack: std.ArrayList(u32) = .empty;
    defer stack.deinit(a);
    const Frame = struct {
        height: usize,
        result: bool,
        first: u32 = none,
        else_: bool = false,
        branched: bool = false,
        fn floor(frames: []const @This()) usize {
            if (frames.len == 0) return 0;
            return frames[frames.len - 1].height;
        }
    };
    var controls: std.ArrayList(Frame) = .empty;
    defer controls.deinit(a);
    var prefix = true;
    var scope_open = false;
    for (instructions, 0..) |inst, at| {
        var destination: ?u32 = null;
        switch (inst.op) {
            .ownership => {
                const fact: ir.Ownership = @bitCast(inst.operand);
                if (fact.kind == .scope and fact.chunk == 3) destination = fact.roles;
                if (fact.kind == .scope and fact.chunk <= 2) scope_open = true;
            },
            .i32_const => {
                var value: u32 = none;
                if (!inst.table_reference and (inst.operand == 0 or (proof != .zero and ir.hasImmortalReference(instructions, at)))) value = zero;
                try stack.append(a, value);
            },
            .local_get => try stack.append(a, inst.operand),
            .local_set, .local_tee => {
                const floor = Frame.floor(controls.items);
                var source: u32 = none;
                if (stack.items.len > floor) source = stack.pop().?;
                if (source < count) {
                    try edges.append(a, .{ .destination = inst.operand, .next = heads[source] });
                    heads[source] = @intCast(edges.items.len - 1);
                } else if (source != zero) destination = inst.operand;
                if (inst.op == .local_tee) try stack.append(a, inst.operand);
            },
            .block, .loop, .if_ => {
                prefix = false;
                if (inst.op == .if_ and stack.items.len != 0) _ = stack.pop();
                try controls.append(a, .{ .height = stack.items.len, .result = inst.operand != 0 and inst.operand != @backingInt(w.ValueType.none) });
            },
            .else_, .end => {
                if (controls.items.len == 0) {
                    stack.clearRetainingCapacity();
                    continue;
                }
                const frame = &controls.items[controls.items.len - 1];
                var result: u32 = none;
                if (frame.result and stack.items.len > frame.height) result = stack.items[stack.items.len - 1];
                stack.shrinkRetainingCapacity(frame.height);
                if (inst.op == .else_) {
                    frame.first = result;
                    frame.else_ = true;
                } else {
                    if ((frame.else_ and frame.first != result) or frame.branched) result = none;
                    const produces = frame.result;
                    _ = controls.pop();
                    if (produces) try stack.append(a, result);
                }
            },
            .br, .br_if, .return_, .unreachable_ => {
                for (controls.items) |*frame| frame.branched = true;
                if (inst.op == .br_if) {
                    if (stack.items.len != 0) _ = stack.pop();
                } else {
                    const floor = Frame.floor(controls.items);
                    stack.shrinkRetainingCapacity(floor);
                }
            },
            else => {
                var arity: usize = ir.fixed(inst.op).arity;
                var result = ir.fixed(inst.op).result;
                var owned = false;
                if (inst.op == .call or inst.op == .call_import or inst.op == .call_indirect) {
                    const callee = ir.call(module, inst);
                    arity = callee.parameters.len + @intFromBool(callee.selector);
                    result = callee.result;
                    owned = proof == .frame_owned and prefix and !scope_open and inst.op == .call and ir.allocationAnnotations(instructions, at).len != 0 and (callee.ownership == .allocate or callee.ownership == .allocate_scalar or callee.ownership == .allocate_typed);
                } else if (inst.op == .global_get) result = module.globals.items[inst.operand].scalar.machine();
                const floor = Frame.floor(controls.items);
                const available = stack.items.len - floor;
                stack.shrinkRetainingCapacity(stack.items.len - @min(arity, available));
                if (result != .none) {
                    var value: u32 = none;
                    if (owned) value = zero;
                    try stack.append(a, value);
                }
            },
        }
        if (destination) |id| if (zeros[id]) {
            zeros[id] = false;
            try pending.append(a, id);
        };
    }
    while (pending.pop()) |source| {
        var edge = heads[source];
        while (edge != none) {
            const value = edges.items[edge];
            if (zeros[value.destination]) {
                zeros[value.destination] = false;
                try pending.append(a, value.destination);
            }
            edge = value.next;
        }
    }
    return zeros;
}
fn pass(a: A, module: *const w.Module, function: *const w.Function, locals: []const w.ValueType, instructions: []const w.Instruction, owning: bool, children: bool) !?Output {
    const events = try a.alloc(Event, instructions.len);
    defer a.free(events);
    @memset(events, .{});
    const local_count = std.math.add(usize, function.parameters.len, locals.len) catch return error.OutOfMemory;
    const constants = try a.alloc(?u32, local_count);
    defer a.free(constants);
    @memset(constants, null);
    const constant_scopes = try a.alloc(?usize, constants.len);
    defer a.free(constant_scopes);
    @memset(constant_scopes, null);
    const defined_scopes = try a.alloc(?usize, constants.len);
    defer a.free(defined_scopes);
    @memset(defined_scopes, null);
    @memset(defined_scopes[0..function.parameters.len], 0);
    const writes = try a.alloc(bool, constants.len);
    defer a.free(writes);
    @memset(writes, false);
    for (instructions, 0..) |inst, i| if (inst.op == .local_set or inst.op == .local_tee) {
        const value: ?u32 = if (i != 0 and instructions[i - 1].op == .i32_const and !instructions[i - 1].table_reference and ir.staticConstructor(instructions, i - 1) == null) instructions[i - 1].operand else null;
        if (!writes[inst.operand]) constants[inst.operand] = value else if (constants[inst.operand] != value) constants[inst.operand] = null;
        writes[inst.operand] = true;
    };
    const zeros = blk: {
        if (children) break :blk try constantReferenceLocals(a, .zero, module, function.parameters.len, local_count, instructions);
        const disabled = try a.alloc(bool, local_count);
        @memset(disabled, false);
        break :blk disabled;
    };
    defer a.free(zeros);
    for (zeros, 0..) |zero, id| if (zero) {
        constants[id] = 0;
        constant_scopes[id] = 0;
    };
    var analysis: Analysis = .{ .a = a, .events = events, .constants = constants, .constant_scopes = constant_scopes, .defined_scopes = defined_scopes, .zero_locals = zeros, .owning = owning, .children = children };
    defer analysis.nodes.deinit(a);
    defer analysis.stack.deinit(a);
    defer analysis.controls.deinit(a);
    _ = try analysis.add(true, 0);
    for (0..local_count) |i| _ = try analysis.add(i < function.parameters.len, 0);
    try analysis.scan(module, function, instructions);
    if (!analysis.valid) return null;
    var any = false;
    for (events) |event| if (analysis.selected(event.allocation)) {
        any = true;
        break;
    };
    if (!any) return null;
    for (instructions, events) |inst, event| if ((inst.op == .i32_load or inst.op == .f32_load) and analysis.selected(event.input.id)) {
        analysis.nodes.items[event.input.id].used_fields |= @as(u16, 1) << @intCast(event.field / 4);
    };
    try analysis.demandedFields();
    analysis.shareFieldRoots(instructions);
    any = false;
    for (events) |event| if (analysis.selected(event.allocation)) {
        any = true;
        break;
    };
    if (!any) return null;
    var added: usize = 0;
    for (analysis.nodes.items, 0..) |node, id| if (analysis.selected(@intCast(id))) {
        const family = analysis.root(@intCast(id));
        added += @popCount(node.used_fields);
        if (!analysis.nodes.items[family].shared_roots or id == family) added += @popCount(node.root_fields & analysis.nodes.items[family].reference_fields);
    };
    if (owning and (local_count >= 8192 or added >= 8192 - local_count)) return null;
    var out: Output = .{};
    errdefer out.deinit(a);
    try out.locals.appendSlice(a, locals);
    for (0..analysis.nodes.items.len) |id| {
        if (!analysis.selected(@intCast(id))) continue;
        const count = @popCount(analysis.nodes.items[id].used_fields);
        analysis.nodes.items[id].fields = @intCast(function.parameters.len + out.locals.items.len);
        try out.locals.appendNTimes(a, .i32, count);
    }
    // These slots belong to the function frame, outside source scope markers.
    // Each static virtual field has one reusable slot across loop activations.
    for (0..analysis.nodes.items.len) |id| {
        if (!analysis.selected(@intCast(id))) continue;
        const family = analysis.root(@intCast(id));
        if (analysis.nodes.items[family].shared_roots and id != family) continue;
        const count = @popCount(analysis.nodes.items[id].root_fields & analysis.nodes.items[family].reference_fields);
        analysis.nodes.items[id].roots = @intCast(function.parameters.len + out.locals.items.len);
        for (0..count) |_| {
            const slot: u32 = @intCast(function.parameters.len + out.locals.items.len);
            try out.locals.append(a, .i32);
            try emit(&out, a, .ownership, @bitCast(ir.Ownership{ .kind = .scope, .chunk = 3, .roles = @intCast(slot) }));
        }
    }
    const zero_slots = try a.alloc(bool, local_count);
    defer a.free(zero_slots);
    @memset(zero_slots, false);
    for (instructions) |inst| if (inst.op == .ownership) {
        const fact: ir.Ownership = @bitCast(inst.operand);
        if (fact.kind == .scope and fact.chunk == 3) zero_slots[fact.roles] = true;
    };
    for (instructions) |inst| {
        if (inst.op == .local_get or inst.op == .local_set or inst.op == .local_tee) zero_slots[inst.operand] = false;
        if (inst.op == .ownership) {
            const fact: ir.Ownership = @bitCast(inst.operand);
            if (fact.kind != .scope or fact.chunk != 4) continue;
            const value = fact.roles >> 13;
            if (!zeros[value] and !analysis.selected(value + 1)) zero_slots[fact.roles & 8191] = false;
        }
    }
    var planned_locals = std.math.add(usize, function.parameters.len, out.locals.items.len) catch return error.OutOfMemory;
    for (instructions, 0..) |inst, at| {
        if (inst.op != .call_indirect) continue;
        const target = projectedCall(&analysis, module, instructions, at) orelse continue;
        const target_body = &module.functions.items[target];
        const parameters = target_body.parameters.len + target_body.locals.items.len;
        if (planned_locals >= 8192 or parameters >= 8192 - planned_locals) continue;
        planned_locals += parameters;
        // Call events have no field offset. During emission these two slots
        // identify the selected target and its consumed call-result marker.
        events[at].field = target + 1;
        events[at - 1].field = target + 1;
    }
    for (instructions, events) |inst, event| {
        if (inst.op == .ownership) {
            const scope: ir.Ownership = @bitCast(inst.operand);
            if (scope.kind == .scope and ((scope.chunk == 3 and zero_slots[scope.roles]) or (scope.chunk == 4 and zero_slots[scope.roles & 8191]))) continue;
            if (scope.kind == .call_result and event.field != 0) continue;
            // This anonymous slot owns only the removed scalar object. Carry
            // slots and scope boundaries keep their original clearing/order.
            if (scope.kind == .scope and scope.chunk == 5 and analysis.selected(scope.roles + 1)) continue;
        }
        if (inst.op == .call and inst.operand == module.arena.?.mark_acyclic and analysis.selected(event.input.id)) {
            try emit(&out, a, .drop, 0);
            continue;
        }
        if (analysis.selected(event.allocation)) {
            if (event.static_words) {
                out.instructions.shrinkRetainingCapacity(out.instructions.items.len - 4);
                const mask = analysis.nodes.items[event.allocation].used_fields;
                const words = analysis.nodes.items[analysis.root(event.allocation)].size / 4;
                for (0..words) |field| {
                    if (mask & (@as(u16, 1) << @intCast(field)) == 0) continue;
                    var bits: u32 = 0;
                    if (field == 0) bits = event.field;
                    try emit(&out, a, .i32_const, bits);
                    try emit(&out, a, .local_set, analysis.fieldLocal(event.allocation, @intCast(field)));
                    try publishField(&out, &analysis, event.allocation, @intCast(field));
                }
            } else try emit(&out, a, .drop, 0);
            try emit(&out, a, .i32_const, 0);
            continue;
        }
        if (inst.op == .call_indirect and event.field != 0) {
            try emitProjectedCall(&out, &analysis, function, &module.functions.items[event.field - 1]);
            continue;
        }
        if (event.destination != 0 and !event.fresh and analysis.selected(event.destination)) try copyFields(&out, &analysis, event);
        if ((inst.op == .i32_load or inst.op == .f32_load) and analysis.selected(event.input.id)) {
            try emit(&out, a, .drop, 0);
            try emit(&out, a, .local_get, analysis.fieldLocal(event.input.id, event.field / 4));
            if (inst.op == .f32_load) try emit(&out, a, .f32_reinterpret_i32, 0);
        } else if ((inst.op == .i32_store or inst.op == .f32_store) and analysis.selected(event.input.id)) {
            if (analysis.nodes.items[event.input.id].used_fields & (@as(u16, 1) << @intCast(event.field / 4)) != 0) {
                if (inst.op == .f32_store) try emit(&out, a, .i32_reinterpret_f32, 0);
                try emit(&out, a, .local_set, analysis.fieldLocal(event.input.id, event.field / 4));
            } else try emit(&out, a, .drop, 0);
            try emit(&out, a, .drop, 0);
            try publishField(&out, &analysis, event.input.id, event.field / 4);
        } else try out.instructions.append(a, inst);
    }
    return out;
}
// Private copies need no extra edge when every publication is zero, static,
// or an initial allocation still owned by the enclosing function frame.
// Machine access to a reserved slot keeps it. Scalar-looking addresses grant
// no static/ownership fact; all writes and parallel copies participate.
fn pruneFieldRoots(a: A, module: *const w.Module, owning: bool, parameters: usize, body: *Output) !void {
    const count = std.math.add(usize, parameters, body.locals.items.len) catch return error.OutOfMemory;
    var proof: ReferenceProof = .immortal;
    if (owning) proof = .frame_owned;
    const covered = try constantReferenceLocals(a, proof, module, parameters, count, body.instructions.items);
    defer a.free(covered);
    const slots = try a.alloc(bool, count);
    defer a.free(slots);
    @memset(slots, false);
    for (body.instructions.items) |inst| if (inst.op == .ownership) {
        const fact: ir.Ownership = @bitCast(inst.operand);
        if (fact.kind == .scope and fact.chunk == 3) slots[fact.roles] = true;
    };
    for (body.instructions.items) |inst| {
        if (inst.op == .local_get or inst.op == .local_set or inst.op == .local_tee) slots[inst.operand] = false;
        if (inst.op == .ownership) {
            const fact: ir.Ownership = @bitCast(inst.operand);
            if (fact.kind == .scope and fact.chunk == 4 and !covered[fact.roles >> 13]) slots[fact.roles & 8191] = false;
        }
    }
    var position: usize = 0;
    for (body.instructions.items) |inst| {
        if (inst.op == .ownership) {
            const fact: ir.Ownership = @bitCast(inst.operand);
            if (fact.kind == .scope and ((fact.chunk == 3 and slots[fact.roles]) or (fact.chunk == 4 and slots[fact.roles & 8191]))) continue;
        }
        body.instructions.items[position] = inst;
        position += 1;
    }
    body.instructions.shrinkRetainingCapacity(position);
}
pub fn run(a: A, module: *const w.Module, function: *const w.Function) !?Output {
    return runWithRoots(a, module, function, false);
}
const Cost = struct {
    const Budget = struct { allocations: usize = 0, publications: usize = 0 };
    // Cost admission is bounded independently of source nesting. Functions
    // beyond this budget keep the established scalar/activation optimization.
    scopes: [65]Budget = @splat(.{}),
    loops: usize = 0,
    valid: bool = true,
};
fn costs(module: *const w.Module, instructions: []const w.Instruction) Cost {
    var value: Cost = .{};
    var controls: [256]usize = undefined;
    var depth: usize = 0;
    var current: usize = 0;
    for (instructions, 0..) |inst, at| {
        switch (inst.op) {
            .block, .loop, .if_ => {
                if (depth == controls.len) {
                    value.valid = false;
                    return value;
                }
                controls[depth] = current;
                depth += 1;
                if (inst.op == .loop) {
                    value.loops += 1;
                    if (value.loops == value.scopes.len) {
                        value.valid = false;
                        return value;
                    }
                    current = value.loops;
                }
            },
            .end => {
                if (depth == 0) {
                    value.valid = false;
                    return value;
                }
                depth -= 1;
                current = controls[depth];
            },
            else => {},
        }
        if (inst.op == .call and module.arena.?.isAllocation(inst.operand) and !ir.hasJournalCarrier(instructions, at)) value.scopes[current].allocations += 1;
        if (inst.op == .ownership) {
            const fact: ir.Ownership = @bitCast(inst.operand);
            if (fact.kind == .scope and fact.chunk == 4) value.scopes[current].publications += 1;
        }
    }
    return value;
}
pub fn runWithRoots(a: A, module: *const w.Module, function: *const w.Function, owning: bool) !?Output {
    var output = try runMode(a, module, function, owning, true) orelse return null;
    const before = costs(module, function.instructions.items);
    const after = costs(module, output.instructions.items);
    // Admit the journal tradeoff independently in each unchanged loop. A
    // one-time allocation cannot pay for extra publications on every pull.
    var admitted = before.valid and after.valid and before.loops == after.loops;
    if (admitted) for (before.scopes, after.scopes) |left, right| {
        if (right.allocations > left.allocations or (right.publications > left.publications and right.publications - left.publications >= 2 * (left.allocations - right.allocations))) {
            admitted = false;
            break;
        }
    };
    if (!admitted) {
        output.deinit(a);
        return runMode(a, module, function, owning, false);
    }
    return output;
}
fn runMode(a: A, module: *const w.Module, function: *const w.Function, owning: bool, children: bool) !?Output {
    if (module.arena == null) return null;
    var output: ?Output = null;
    errdefer if (output) |*out| out.deinit(a);
    var previous_allocations: usize = std.math.maxInt(usize);
    var rounds: usize = 0;
    while (children or rounds < 4) {
        rounds += 1;
        const locals = if (output) |out| out.locals.items else function.locals.items;
        const instructions = if (output) |out| out.instructions.items else function.instructions.items;
        var allocations: usize = 0;
        for (instructions, 0..) |inst, i| if (inst.op == .call and module.arena.?.isAllocation(inst.operand) and i != 0 and instructions[i - 1].op == .i32_const and instructions[i - 1].operand <= 64) {
            allocations += 1;
        };
        if (allocations == 0 or allocations >= previous_allocations) break;
        previous_allocations = allocations;
        const next = try pass(a, module, function, locals, instructions, owning, children) orelse break;
        if (output) |*out| out.deinit(a);
        output = next;
    }
    if (output) |*body| try pruneFieldRoots(a, module, owning, function.parameters.len, body);
    return output;
}

fn scalarReplacementOwnership(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const f = try module.addFunction(&.{.i32}, .i32);
    const p = try module.addLocal(f, .i32);
    const alias = try module.addLocal(f, .i32);
    try module.emitSlice(f, &.{
        .{ .op = .i32_const, .operand = 8 }, .{ .op = .call, .operand = arena.allocate },  .{ .op = .local_set, .operand = p },
        .{ .op = .local_get, .operand = p }, .{ .op = .local_get, .operand = 0 },          .{ .op = .i32_store, .operand = 0 },
        .{ .op = .local_get, .operand = p }, .{ .op = .f32_const, .operand = 0x80000000 }, .{ .op = .f32_store, .operand = 4 },
        .{ .op = .local_get, .operand = p }, .{ .op = .local_set, .operand = alias },      .{ .op = .local_get, .operand = alias },
        .{ .op = .i32_load, .operand = 0 },
    });
    const before = try a.dupe(w.Instruction, module.functions.items[f].instructions.items);
    defer a.free(before);
    var out = (try run(a, &module, &module.functions.items[f])).?;
    defer out.deinit(a);
    for (out.instructions.items) |inst| try std.testing.expect(inst.op != .call);
    try std.testing.expectEqualSlices(w.Instruction, before, module.functions.items[f].instructions.items);
}
test "scalar replacement owns scratch and output through every failed allocation" {
    try scalarReplacementOwnership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scalarReplacementOwnership, .{});
}

fn selectiveFieldCopies(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const f = try module.addFunction(&.{.i32}, .i32);
    const row = try module.addLocal(f, .i32);
    const first = try module.addLocal(f, .i32);
    const last = try module.addLocal(f, .i32);
    try module.emitSlice(f, &.{ .{ .op = .i32_const, .operand = 64 }, .{ .op = .call, .operand = arena.allocate_scalar }, .{ .op = .local_set, .operand = row } });
    for (0..16) |field| try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = row }, .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_store, .operand = @intCast(field * 4) } });
    try module.emitSlice(f, &.{
        .{ .op = .local_get, .operand = row },   .{ .op = .local_set, .operand = first },
        .{ .op = .local_get, .operand = row },   .{ .op = .local_set, .operand = last },
        .{ .op = .local_get, .operand = first }, .{ .op = .i32_load, .operand = 0 },
        .{ .op = .local_get, .operand = last },  .{ .op = .i32_load, .operand = 60 },
        .{ .op = .i32_add },
    });
    const before = try a.dupe(w.Instruction, module.functions.items[f].instructions.items);
    defer a.free(before);
    var out = (try run(a, &module, &module.functions.items[f])).?;
    defer out.deinit(a);
    // Two fields for the original and one for each snapshot, not sixteen
    // slots and sixteen transfers at every single-field accessor.
    try std.testing.expectEqual(@as(usize, 7), out.locals.items.len);
    for (out.instructions.items) |inst| try std.testing.expect(inst.op != .call);
    try std.testing.expectEqualSlices(w.Instruction, before, module.functions.items[f].instructions.items);
}

test "scalar replacement copies only fields demanded by each snapshot" {
    try selectiveFieldCopies(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, selectiveFieldCopies, .{});
}

test "scalar replacement declines incomplete initialization and stores after an alias escapes" {
    const a = std.testing.allocator;
    for (0..3) |scenario| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const f = try module.addFunction(&.{.i32}, .i32);
        const p = try module.addLocal(f, .i32);
        const alias = try module.addLocal(f, .i32);
        try module.emitSlice(f, &.{ .{ .op = .i32_const, .operand = 8 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = p } });
        if (scenario == 0) try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .if_, .operand = 0 } });
        try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = p }, .{ .op = .i32_const, .operand = 42 }, .{ .op = .i32_store, .operand = 0 } });
        if (scenario == 0) try module.emit(f, .{ .op = .end });
        if (scenario == 1) try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = p }, .{ .op = .local_set, .operand = alias } });
        // Scenario 2 reads a never-initialized field; it must retain arena bytes.
        if (scenario != 2) try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = p }, .{ .op = .i32_const, .operand = 9 }, .{ .op = .i32_store, .operand = 4 } });
        try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = if (scenario == 1) alias else p }, .{ .op = .i32_load, .operand = 4 } });
        try std.testing.expect(try run(a, &module, &module.functions.items[f]) == null);
    }
}

fn owningFields(a: A) !void {
    for ([_]ir.Role{ .scalar, .reference }) |role| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const function = try module.addTypedFunction(&.{.i32}, .i32, role);
        const parent = try module.addLocal(function, .i32);
        var buffer: [ir.max_annotations]ir.Instruction = undefined;
        try module.emitSlice(function, ir.annotations(&.{role}, .scalar, &buffer));
        try module.emitSlice(function, &.{
            .{ .op = .i32_const, .operand = 4 },      .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = parent },
            .{ .op = .local_get, .operand = parent }, .{ .op = .local_get },                       .{ .op = .i32_store },
            .{ .op = .local_get, .operand = parent }, .{ .op = .i32_load },
        });
        var replacement = try run(a, &module, &module.functions.items[function]);
        defer if (replacement) |*body| body.deinit(a);
        // Eliding an owning word needs an equivalent root for its child.
        // A scalar snapshot, including pointer-looking bits, needs none.
        try std.testing.expectEqual(role == .scalar, replacement != null);
        if (replacement) |body| for (body.instructions.items) |inst| try std.testing.expect(inst.op != .call);
    }
}
test "scalar replacement preserves checked owning fields until equivalent roots exist through OOM" {
    try owningFields(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, owningFields, .{});
}

fn journaledScalarSnapshots(a: A) !void {
    for (0..4) |scenario| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const function = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
        const object = try module.addLocal(function, .i32);
        const alias = try module.addLocal(function, .i32);
        const slot = try module.addLocal(function, .i32);
        var buffer: [ir.max_annotations]ir.Instruction = undefined;
        var role: ir.Role = .scalar;
        if (scenario == 1) role = .reference;
        if (scenario != 2) try module.emitSlice(function, ir.annotations(&.{role}, .scalar, &buffer));
        try module.emitSlice(function, &.{
            .{ .op = .i32_const, .operand = 4 },      .{ .op = .call, .operand = arena.allocate },     .{ .op = .local_set, .operand = object },
            .{ .op = .local_get, .operand = object }, .{ .op = .local_get },                           .{ .op = .i32_store },
            .{ .op = .local_get, .operand = object }, .{ .op = .call, .operand = arena.mark_acyclic }, .{ .op = .local_get, .operand = object },
            .{ .op = .local_set, .operand = alias },
        });
        const scopes = [_]ir.Ownership{
            .{ .kind = .scope, .chunk = 3, .roles = @intCast(slot) },
            .{ .kind = .scope, .chunk = 4, .roles = @intCast(slot + alias * 8192) },
            .{ .kind = .scope, .chunk = 5, .roles = @intCast(alias) },
            .{ .kind = .scope, .chunk = 2, .roles = @intCast(alias) },
        };
        for (scopes) |scope| try module.emit(function, .{ .op = .ownership, .operand = @bitCast(scope) });
        if (scenario == 3) try module.emit(function, .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 6, .roles = @intCast(alias) }) });
        try module.emitSlice(function, &.{ .{ .op = .local_get, .operand = alias }, .{ .op = .i32_load } });
        const before = try a.dupe(w.Instruction, module.functions.items[function].instructions.items);
        defer a.free(before);
        var output = try run(a, &module, &module.functions.items[function]);
        defer if (output) |*body| body.deinit(a);
        try std.testing.expectEqual(scenario == 0, output != null);
        if (output) |body| {
            var scope_count: usize = 0;
            for (body.instructions.items) |inst| {
                try std.testing.expect(inst.op != .call);
                if (inst.op == .ownership and @as(ir.Ownership, @bitCast(inst.operand)).kind == .scope) scope_count += 1;
            }
            try std.testing.expectEqual(@as(usize, 1), scope_count);
            for (body.instructions.items) |inst| if (inst.op == .ownership) {
                const fact: ir.Ownership = @bitCast(inst.operand);
                if (fact.kind == .scope) try std.testing.expectEqual(@as(u4, 2), fact.chunk);
            };
        }
        try std.testing.expectEqualSlices(w.Instruction, before, module.functions.items[function].instructions.items);
    }
}
test "scalar replacement preserves journaled scalar snapshots and declines owning or untyped fields through OOM" {
    try journaledScalarSnapshots(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, journaledScalarSnapshots, .{});
}

fn journaledReferenceSnapshots(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const function = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    const object = try module.addLocal(function, .i32);
    const alias = try module.addLocal(function, .i32);
    var buffer: [ir.max_annotations]ir.Instruction = undefined;
    try module.emit(function, .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 0 }) });
    try module.emitSlice(function, ir.annotations(&.{ .reference, .scalar }, .scalar, &buffer));
    try module.emitSlice(function, &.{
        .{ .op = .i32_const, .operand = 8 },      .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object },
        .{ .op = .local_get, .operand = object }, .{ .op = .local_get },                       .{ .op = .i32_store },
        .{ .op = .local_get, .operand = object }, .{ .op = .i32_const, .operand = 8192 },      .{ .op = .i32_store, .operand = 4 },
        .{ .op = .local_get, .operand = object }, .{ .op = .local_set, .operand = alias },
    });
    try module.emit(function, .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 2, .roles = @intCast(alias) }) });
    try module.emitSlice(function, &.{ .{ .op = .local_get, .operand = alias }, .{ .op = .i32_load }, .{ .op = .i32_load, .operand = 4 } });
    const before = try a.dupe(w.Instruction, module.functions.items[function].instructions.items);
    defer a.free(before);
    try std.testing.expect(try run(a, &module, &module.functions.items[function]) == null);
    var out = (try runWithRoots(a, &module, &module.functions.items[function], true)).?;
    defer out.deinit(a);
    var reserved: usize = 0;
    var stored: usize = 0;
    var opened = false;
    for (out.instructions.items) |inst| {
        try std.testing.expect(inst.op != .call);
        if (inst.op != .ownership) continue;
        const scope: ir.Ownership = @bitCast(inst.operand);
        if (scope.kind != .scope) continue;
        if (scope.chunk == 0) opened = true;
        if (scope.chunk == 3) {
            try std.testing.expect(!opened);
            reserved += 1;
        }
        if (scope.chunk == 4) stored += 1;
    }
    try std.testing.expect(reserved >= 2);
    try std.testing.expect(stored >= 2);
    try std.testing.expectEqualSlices(w.Instruction, before, module.functions.items[function].instructions.items);
}
test "journaled reference snapshots reserve owning field roots before lexical scopes through OOM" {
    try journaledReferenceSnapshots(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, journaledReferenceSnapshots, .{});
}

fn tableProjectionOwners(a: A) !void {
    for (0..12) |scenario| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const add = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .scalar);
        try module.setParameterRoles(add, ir.packParameterRoles(&.{ .scalar, .scalar }));
        try module.emitSlice(add, &.{ .{ .op = .local_get }, .{ .op = .local_get, .operand = 1 }, .{ .op = .i32_add } });
        const wrapper = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .scalar);
        try module.setParameterRoles(wrapper, ir.packParameterRoles(&.{ .reference, .scalar }));
        try module.emitSlice(wrapper, &.{ .{ .op = .local_get }, .{ .op = .i32_load }, .{ .op = .local_get, .operand = 1 }, .{ .op = .call, .operand = add } });
        const other = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .scalar);
        try module.setParameterRoles(other, ir.packParameterRoles(&.{ .reference, .scalar }));
        try module.emitSlice(other, module.functions.items[wrapper].instructions.items);
        if (scenario == 4) {
            const imported = try module.importFunction("host", "scalar", &.{ .i32, .i32 }, .i32);
            module.functions.items[wrapper].instructions.items[3] = .{ .op = .call_import, .operand = imported };
            var session = try @import("runtime_pipeline.zig").Session.init(a, &module);
            defer session.deinit();
            try std.testing.expect(!session.roots);
        }
        if (scenario == 7) module.functions.items[add].result_role = .reference;
        if (scenario == 8) module.functions.items[wrapper].parameter_roles = 0;
        const function = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
        const environment = try module.addLocal(function, .i32);
        const closure = try module.addLocal(function, .i32);
        const alias = try module.addLocal(function, .i32);
        const saved = try module.addLocal(function, .i32);
        var buffer: [ir.max_annotations]ir.Instruction = undefined;
        try module.emitSlice(function, ir.annotations(&.{.scalar}, .scalar, &buffer));
        try module.emitSlice(function, &.{
            .{ .op = .i32_const, .operand = 4 },           .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = environment },
            .{ .op = .local_get, .operand = environment }, .{ .op = .local_get },                       .{ .op = .i32_store },
        });
        if (scenario == 6) try module.emitSlice(function, &.{ .{ .op = .local_get }, .{ .op = .if_ } });
        var count: usize = 1;
        if (scenario == 5 or scenario == 9 or scenario == 10 or scenario == 11) count = 2;
        for (0..count) |version| {
            var object = closure;
            if (version != 0) object = try module.addLocal(function, .i32);
            var held = environment;
            if (version != 0 and scenario == 9) {
                held = try module.addLocal(function, .i32);
                try module.emitSlice(function, ir.annotations(&.{.scalar}, .scalar, &buffer));
                try module.emitSlice(function, &.{
                    .{ .op = .i32_const, .operand = 4 },    .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = held },
                    .{ .op = .local_get, .operand = held }, .{ .op = .local_get },                       .{ .op = .i32_const, .operand = 1 },
                    .{ .op = .i32_add },                    .{ .op = .i32_store },
                });
            }
            try module.emitSlice(function, ir.annotations(&.{ .scalar, .reference }, .scalar, &buffer));
            var target = wrapper;
            if (version == 1 and scenario == 5) target = other;
            const start = module.functions.items[function].instructions.items.len;
            try module.emitSlice(function, &.{
                .{ .op = .i32_const, .operand = 8 },      .{ .op = .call, .operand = arena.allocate },                                .{ .op = .local_set, .operand = object },
                .{ .op = .local_get, .operand = object }, .{ .op = .i32_const, .operand = target, .table_reference = scenario != 2 }, .{ .op = .i32_store },
                .{ .op = .local_get, .operand = object }, .{ .op = .local_get, .operand = held },                                     .{ .op = .i32_store, .operand = 4 },
                .{ .op = .local_get, .operand = object }, .{ .op = .local_set, .operand = alias },
            });
            if (version == 1 and scenario == 11) {
                module.functions.items[function].instructions.items[start + 4] = .{ .op = .f32_const, .operand = target };
                module.functions.items[function].instructions.items[start + 5] = .{ .op = .f32_store };
            }
            if (version == 0 and scenario == 9) try module.emitSlice(function, &.{ .{ .op = .local_get, .operand = alias }, .{ .op = .local_set, .operand = saved } });
        }
        if (scenario == 6) try module.emit(function, .{ .op = .end });
        var calls: usize = 1;
        if (scenario == 9) calls = 2;
        var signature = module.functions.items[wrapper].signature;
        if (scenario == 3) signature = try module.internType(&.{ .i32, .i32 }, .f32);
        for (0..calls) |call| {
            var input = alias;
            if (call == 0 and scenario == 9) input = saved;
            try module.emitSlice(function, &.{
                .{ .op = .local_get, .operand = input },         .{ .op = .i32_load, .operand = 4 }, .{ .op = .i32_const, .operand = 8192 },
                .{ .op = .local_get, .operand = input },         .{ .op = .i32_load },               ir.callResult(.scalar),
                .{ .op = .call_indirect, .operand = signature },
            });
            if (call + 1 != calls) try module.emit(function, .{ .op = .drop });
        }
        const original = try a.dupe(w.Instruction, module.functions.items[function].instructions.items);
        defer a.free(original);
        const original_wrapper = try a.dupe(w.Instruction, module.functions.items[wrapper].instructions.items);
        defer a.free(original_wrapper);
        var output = try runWithRoots(a, &module, &module.functions.items[function], scenario != 1);
        defer if (output) |*body| body.deinit(a);
        const code = if (output) |body| body.instructions.items else original;
        var indirect: usize = 0;
        var allocations: usize = 0;
        for (code, 0..) |inst, at| {
            if (inst.op == .call_indirect) indirect += 1;
            if (inst.op == .call and arena.isAllocation(inst.operand)) allocations += 1;
            if (inst.op == .ownership and @as(ir.Ownership, @bitCast(inst.operand)).kind == .call_result) {
                try std.testing.expect(at + 1 < code.len and code[at + 1].op == .call_indirect);
            }
        }
        const admitted = scenario == 0 or scenario == 9 or scenario == 10;
        try std.testing.expectEqual(!admitted, indirect != 0);
        try std.testing.expectEqual(admitted, allocations == 0);
        try std.testing.expectEqualSlices(w.Instruction, original, module.functions.items[function].instructions.items);
        try std.testing.expectEqualSlices(w.Instruction, original_wrapper, module.functions.items[wrapper].instructions.items);
        if (scenario == 0) {
            var session = try @import("runtime_pipeline.zig").Session.init(a, &module);
            defer session.deinit();
            var capture: @import("optimized_bodies.zig").Capture = .{ .allocator = a, .roots = true, .needs_roots = true, .root_slots = @intCast(module.globals.items.len) };
            defer capture.deinit();
            try capture.recordInputs(&module, &session.summaries);
            try capture.recordOutput(function, output);
            try capture.sealQueries();
            const archive = @import("optimized_archive.zig");
            const bytes = try archive.encode(a, @splat(0), &capture);
            defer a.free(bytes);
            var restored = try archive.decode(a, @splat(0), bytes);
            defer restored.deinit();
            try std.testing.expectEqualSlices(w.Instruction, code, restored.output(function).?.instructions.items);
            var matcher = try @import("optimized_bodies.zig").Matcher.init(a, &restored, &capture);
            defer matcher.deinit();
            try std.testing.expect(matcher.matches(function));
            try std.testing.expectEqualSlices(w.Instruction, code, matcher.output(function).?.instructions.items);
        }
    }
}
test "private explicit table projections preserve roots dominance forks signatures imports and inputs through OOM" {
    try tableProjectionOwners(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, tableProjectionOwners, .{});
}

fn staticConstructorFields(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const address = try module.dataWords(&.{ 1, 0 });
    const f = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .scalar);
    const cell = try module.addLocal(f, .i32);
    const merged = try module.addLocal(f, .i32);
    var buffer: [ir.max_annotations]ir.Instruction = undefined;
    const facts = ir.annotations(&.{ .scalar, .reference }, .unknown, &buffer);
    try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = 1 }, .{ .op = .if_, .operand = @backingInt(w.ValueType.i32) } });
    try module.emitSlice(f, facts);
    try module.emitSlice(f, &.{
        .{ .op = .i32_const, .operand = 8 },    .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = cell },
        .{ .op = .local_get, .operand = cell }, .{ .op = .i32_const, .operand = 0 },         .{ .op = .i32_store, .operand = 0 },
        .{ .op = .local_get, .operand = cell }, .{ .op = .local_get, .operand = 0 },         .{ .op = .i32_store, .operand = 4 },
        .{ .op = .local_get, .operand = cell }, .{ .op = .else_ },
    });
    var rest: ir.Ownership = @bitCast(facts[facts.len - 1].operand);
    rest.chunk = 15;
    facts[facts.len - 1].operand = @bitCast(rest);
    try module.emitSlice(f, &.{
        .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .words, .chunk = 14, .roles = 1 }) },
        .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .words, .chunk = 15 }) },
    });
    try module.emitSlice(f, facts);
    const static_at = module.functions.items[f].instructions.items.len;
    try module.emitSlice(f, &.{
        .{ .op = .i32_const, .operand = address }, .{ .op = .end },                    .{ .op = .local_set, .operand = merged },
        .{ .op = .local_get, .operand = merged },  .{ .op = .i32_load, .operand = 4 }, .{ .op = .drop },
        .{ .op = .local_get, .operand = merged },  .{ .op = .i32_load, .operand = 0 },
    });
    const before = try a.dupe(w.Instruction, module.functions.items[f].instructions.items);
    defer a.free(before);
    var out = (try runWithRoots(a, &module, &module.functions.items[f], true)).?;
    defer out.deinit(a);
    var slots: usize = 0;
    for (out.instructions.items) |inst| {
        if (inst.op == .call) try std.testing.expect(inst.operand != arena.allocate);
        if (inst.op == .ownership) {
            const fact: ir.Ownership = @bitCast(inst.operand);
            if (fact.kind == .scope and fact.chunk == 3) slots += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), slots);
    try std.testing.expectEqualSlices(w.Instruction, before, module.functions.items[f].instructions.items);
    // Evaluating both constructors in one block cannot share their roots:
    // an older alias can still demand the allocation after the empty return.
    const combined = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .scalar);
    _ = try module.addLocal(combined, .i32);
    _ = try module.addLocal(combined, .i32);
    const alternative = for (before, 0..) |inst, at| {
        if (inst.op == .else_) break at;
    } else unreachable;
    try module.emit(combined, .{ .op = .block, .operand = @backingInt(w.ValueType.i32) });
    try module.emitSlice(combined, before[2..alternative]);
    try module.emitSlice(combined, &.{ .{ .op = .drop }, .{ .op = .local_get, .operand = 1 }, .{ .op = .if_ } });
    try module.emitSlice(combined, before[alternative + 1 .. static_at + 1]);
    try module.emitSlice(combined, &.{ .{ .op = .br, .operand = 1 }, .{ .op = .end }, .{ .op = .local_get, .operand = cell }, .{ .op = .end } });
    try module.emitSlice(combined, before[static_at + 2 ..]);
    try std.testing.expect((try runWithRoots(a, &module, &module.functions.items[combined], true)) == null);
    // Numeric words with the same bits are never evidence of static storage.
    module.functions.items[f].instructions.items[static_at - 1].operand = @bitCast(ir.Ownership{ .kind = .rest, .roles = rest.roles });
    try std.testing.expect((try runWithRoots(a, &module, &module.functions.items[f], true)) == null);
    module.functions.items[f].instructions.items[static_at - 1].operand = @bitCast(rest);
    // Mismatched reference positions remain ordinary.
    module.functions.items[f].instructions.items[static_at - 2].operand = @bitCast(ir.Ownership{ .kind = .words, .roles = @backingInt(ir.Role.scalar) | (@as(u26, @backingInt(ir.Role.scalar)) << 2) });
    try std.testing.expect((try runWithRoots(a, &module, &module.functions.items[f], true)) == null);
}
test "exact static constructor fields join private allocated alternatives without publishing identities" {
    try staticConstructorFields(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, staticConstructorFields, .{});
}

fn checkedAbsentFields(a: A) !void {
    for (0..6) |scenario| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const f = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
        const object = try module.addLocal(f, .i32);
        const saved = try module.addLocal(f, .i32);
        const observer = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
        try module.emit(observer, .{ .op = .i32_const, .operand = 9 });
        try module.emitSlice(f, &.{ .{ .op = .local_get }, .{ .op = .if_ } });
        var facts: [ir.max_annotations]ir.Instruction = undefined;
        try module.emitSlice(f, ir.annotations(&.{ .scalar, .scalar }, .unknown, &facts));
        try module.emitSlice(f, &.{
            .{ .op = .i32_const, .operand = 8 },      .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object },
            .{ .op = .local_get, .operand = object }, .{ .op = .i32_const, .operand = 8192 },      .{ .op = .i32_store },
        });
        if (scenario != 5) try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = object }, .{ .op = .f32_const, .operand = 0x80000000 }, .{ .op = .f32_store, .operand = 4 } });
        try module.emitSlice(f, &.{
            .{ .op = .local_get, .operand = object }, .{ .op = .local_set, .operand = saved },
            .{ .op = .else_ },                        .{ .op = .i32_const },
            .{ .op = .local_set, .operand = saved },  .{ .op = .end },
            .{ .op = .local_get },                    .{ .op = .if_, .operand = @backingInt(w.ValueType.i32) },
        });
        if (scenario == 3) try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = saved }, .{ .op = .call, .operand = observer }, .{ .op = .drop } });
        try module.emit(f, .{ .op = .local_get, .operand = saved });
        var marker = ir.nonzeroRead();
        if (scenario == 2) marker.operand ^= 64;
        if (scenario != 0) try module.emit(f, marker);
        var offset: u32 = 4;
        if (scenario == 4) offset = 8;
        try module.emitSlice(f, &.{ .{ .op = .f32_load, .operand = offset }, .{ .op = .i32_reinterpret_f32 }, .{ .op = .else_ }, .{ .op = .i32_const }, .{ .op = .end } });
        const before = try a.dupe(w.Instruction, module.functions.items[f].instructions.items);
        defer a.free(before);
        var out = try runWithRoots(a, &module, &module.functions.items[f], true);
        defer if (out) |*body| body.deinit(a);
        try std.testing.expectEqual(scenario == 1, out != null);
        if (out) |body| for (body.instructions.items) |inst| {
            try std.testing.expect(inst.op != .f32_load and !(inst.op == .call and arena.isAllocation(inst.operand)));
        };
        try std.testing.expectEqualSlices(w.Instruction, before, module.functions.items[f].instructions.items);
    }
}
test "checked private absent fields preserve nullable copies bits and conservative fallback through OOM" {
    try checkedAbsentFields(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, checkedAbsentFields, .{});
}

fn journalCarrierFields(a: A) !void {
    for (0..8) |scenario| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const f = try module.addTypedFunction(&.{}, .i32, .scalar);
        const child = try module.addLocal(f, .i32);
        const carrier = try module.addLocal(f, .i32);
        const observer = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
        try module.emit(observer, .{ .op = .i32_const, .operand = 9 });
        var facts: [ir.max_annotations]ir.Instruction = undefined;
        try module.emitSlice(f, ir.annotations(&.{.scalar}, .unknown, &facts));
        try module.emitSlice(f, &.{
            .{ .op = .i32_const, .operand = 4 },     .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = child },
            .{ .op = .local_get, .operand = child }, .{ .op = .i32_const, .operand = 42 },        .{ .op = .i32_store },
        });
        if (scenario != 1) try module.emit(f, ir.journalCarrier());
        var role: ir.Role = .reference;
        if (scenario == 3) role = .value;
        try module.emitSlice(f, ir.annotations(&.{ role, .scalar }, .unknown, &facts));
        try module.emitSlice(f, &.{
            .{ .op = .i32_const, .operand = 8 },       .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = carrier },
            .{ .op = .local_get, .operand = carrier }, .{ .op = .local_get, .operand = child },     .{ .op = .i32_store },
        });
        if (scenario != 6) try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = carrier }, .{ .op = .i32_const }, .{ .op = .i32_store, .operand = 4 } });
        if (scenario == 4) try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = carrier }, .{ .op = .call, .operand = observer }, .{ .op = .drop } });
        if (scenario == 5) try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = carrier }, .{ .op = .i32_load }, .{ .op = .i32_load }, .{ .op = .drop } });
        if (scenario == 7) {
            try module.emitSlice(f, &.{ .{ .op = .i32_const }, .{ .op = .local_get, .operand = carrier } });
        } else try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = carrier }, .{ .op = .i32_const } });
        try module.emitSlice(f, &.{ .{ .op = .i32_const }, .{ .op = .call, .operand = arena.collect }, .{ .op = .drop }, .{ .op = .local_get, .operand = carrier }, .{ .op = .call, .operand = arena.recycle }, .{ .op = .i32_const } });
        const before = try a.dupe(w.Instruction, module.functions.items[f].instructions.items);
        defer a.free(before);
        var out = try runWithRoots(a, &module, &module.functions.items[f], scenario != 2);
        defer if (out) |*body| body.deinit(a);
        try std.testing.expectEqual(scenario == 0, out != null);
        if (out) |body| for (body.instructions.items) |inst| {
            try std.testing.expect(!(inst.op == .call and arena.isAllocation(inst.operand)));
        };
        try std.testing.expectEqualSlices(w.Instruction, before, module.functions.items[f].instructions.items);
    }
}
test "private journal carriers decline unknown escaped read incomplete and unowned children through OOM" {
    try journalCarrierFields(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, journalCarrierFields, .{});
}

fn permanentReferenceFlows(a: A) !void {
    for (0..10) |scenario| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        var code: std.ArrayList(w.Instruction) = .empty;
        defer code.deinit(a);
        var annotated: [ir.max_annotations]ir.Instruction = undefined;
        if (scenario == 0) {
            try code.appendSlice(a, &.{ .{ .op = .local_get, .operand = 2 }, .{ .op = .local_set, .operand = 1 }, .{ .op = .local_get, .operand = 1 }, .{ .op = .local_set, .operand = 2 } });
        } else if (scenario <= 3) {
            if (scenario != 2) try code.append(a, ir.immortalReference());
            try code.append(a, .{ .op = .i32_const, .operand = 8192, .table_reference = scenario == 3 });
            try code.append(a, .{ .op = .local_set, .operand = 1 });
        } else if (scenario <= 7) {
            if (scenario == 6) try code.append(a, .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope }) });
            if (scenario == 7) try code.appendSlice(a, &.{ .{ .op = .local_get }, .{ .op = .if_ } });
            if (scenario != 5) try code.appendSlice(a, ir.annotations(&.{.scalar}, .unknown, &annotated));
            try code.appendSlice(a, &.{ .{ .op = .i32_const, .operand = 4 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = 1 } });
            if (scenario == 6) try code.append(a, .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 1 }) });
            if (scenario == 7) try code.append(a, .{ .op = .end });
        } else if (scenario == 8) {
            try code.appendSlice(a, &.{ .{ .op = .local_get }, .{ .op = .local_set, .operand = 1 } });
        } else {
            // Parallel copies keep the stack origins; the unknown parameter
            // poisons only its destination and all subsequent copies of it.
            try code.appendSlice(a, &.{ .{ .op = .i32_const }, .{ .op = .local_get }, .{ .op = .local_set, .operand = 2 }, .{ .op = .local_set, .operand = 1 } });
        }
        if (scenario != 0 and scenario != 9) try code.appendSlice(a, &.{ .{ .op = .local_get, .operand = 1 }, .{ .op = .local_set, .operand = 2 } });
        const zeros = try constantReferenceLocals(a, .zero, &module, 1, 3, code.items);
        defer a.free(zeros);
        const permanent = try constantReferenceLocals(a, .immortal, &module, 1, 3, code.items);
        defer a.free(permanent);
        const owned = try constantReferenceLocals(a, .frame_owned, &module, 1, 3, code.items);
        defer a.free(owned);
        try std.testing.expectEqual(scenario == 0 or scenario == 9, zeros[1]);
        try std.testing.expectEqual(scenario == 0 or scenario == 1 or scenario == 9, permanent[1]);
        try std.testing.expectEqual(scenario == 0 or scenario == 1 or scenario == 4 or scenario == 9, owned[1]);
        try std.testing.expectEqual(scenario == 0, zeros[2]);
        try std.testing.expectEqual(scenario == 0 or scenario == 1, permanent[2]);
        try std.testing.expectEqual(scenario == 0 or scenario == 1 or scenario == 4, owned[2]);
    }
}
test "permanent reference copies require symbolic static or enclosing frame ownership through OOM" {
    try permanentReferenceFlows(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, permanentReferenceFlows, .{});
}

fn privateScalarConsumers(a: A) !void {
    for (0..10) |scenario| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const consumer = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .scalar);
        try module.setParameterRoles(consumer, ir.packParameterRoles(&.{ .reference, .scalar }));
        const carry = try module.addLocal(consumer, .i32);
        const bits = try module.addLocal(consumer, .f32);
        try module.emitSlice(consumer, &.{
            .{ .op = .local_get, .operand = 1 },     .{ .op = .if_ },
            .{ .op = .local_get, .operand = 1 },     .{ .op = .local_set, .operand = carry },
            .{ .op = .end },                         .{ .op = .local_get, .operand = bits },
            .{ .op = .i32_reinterpret_f32 },         .{ .op = .drop },
            .{ .op = .local_get, .operand = carry },
        });
        if (scenario == 2) module.functions.items[consumer].entry = true;
        if (scenario == 3) module.functions.items[consumer].result_role = .unknown;
        if (scenario == 5) try module.setParameterRoles(consumer, ir.packParameterRoles(&.{ .reference, .unknown }));
        if (scenario == 6) {
            module.functions.items[consumer].instructions.items[0].op = .nop;
            module.functions.items[consumer].instructions.items[1].op = .loop;
        }
        if (scenario == 7) module.functions.items[consumer].instructions.items[3] = .{ .op = .br, .operand = 1 };
        if (scenario == 8) {
            const imported = try module.importFunction("host", "observe", &.{.i32}, .none);
            module.functions.items[consumer].instructions.items[7] = .{ .op = .call_import, .operand = imported };
        }
        if (scenario == 9) {
            const global = try module.addGlobal(.u32, 0, true);
            module.functions.items[consumer].instructions.items[3] = .{ .op = .global_set, .operand = global };
        }
        const caller = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
        const closure = try module.addLocal(caller, .i32);
        try module.emitSlice(caller, &.{
            .{ .op = .i32_const, .operand = 8 },                                              .{ .op = .call, .operand = arena.allocate_scalar },                           .{ .op = .local_set, .operand = closure },
            .{ .op = .local_get, .operand = closure },                                        .{ .op = .i32_const, .operand = consumer, .table_reference = scenario != 4 }, .{ .op = .i32_store },
            .{ .op = .local_get, .operand = closure },                                        .{ .op = .i32_const },                                                        .{ .op = .i32_store, .operand = 4 },
            .{ .op = .local_get, .operand = closure },                                        .{ .op = .i32_load, .operand = 4 },                                           .{ .op = .local_get },
            .{ .op = .local_get, .operand = closure },                                        .{ .op = .i32_load },                                                         .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .call_result, .roles = @backingInt(ir.Role.scalar) }) },
            .{ .op = .call_indirect, .operand = module.functions.items[consumer].signature },
        });
        const before = try a.dupe(w.Instruction, module.functions.items[caller].instructions.items);
        defer a.free(before);
        const callee_before = try a.dupe(w.Instruction, module.functions.items[consumer].instructions.items);
        defer a.free(callee_before);
        var output = (try runWithRoots(a, &module, &module.functions.items[caller], scenario != 1)).?;
        defer output.deinit(a);
        var indirect: usize = 0;
        var fresh_float = false;
        var fresh_integer = false;
        for (output.instructions.items, 0..) |inst, at| {
            if (inst.op == .call_indirect) indirect += 1;
            if (at + 1 == output.instructions.items.len or output.instructions.items[at + 1].op != .local_set) continue;
            const local = output.instructions.items[at + 1].operand;
            if (local < module.functions.items[caller].parameters.len or local >= module.functions.items[caller].parameters.len + output.locals.items.len) continue;
            const ty = output.locals.items[local - module.functions.items[caller].parameters.len];
            if (inst.op == .f32_const and inst.operand == 0 and ty == .f32) fresh_float = true;
            if (inst.op == .i32_const and inst.operand == 0 and ty == .i32) fresh_integer = true;
        }
        try std.testing.expectEqual(@as(usize, @intFromBool(scenario != 0)), indirect);
        if (scenario == 0) try std.testing.expect(fresh_float and fresh_integer);
        try std.testing.expectEqualSlices(w.Instruction, before, module.functions.items[caller].instructions.items);
        try std.testing.expectEqualSlices(w.Instruction, callee_before, module.functions.items[consumer].instructions.items);
    }
}
test "private scalar callback consumers preserve fresh locals and decline unknown control effects targets through OOM" {
    try privateScalarConsumers(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, privateScalarConsumers, .{});
}

fn controlExitAllocation(module: *w.Module, f: u32, object: u32, value: w.Instruction) !void {
    try module.emitSlice(f, &.{ .{ .op = .i32_const, .operand = 4 }, .{ .op = .call, .operand = module.arena.?.allocate_scalar }, .{ .op = .local_set, .operand = object }, .{ .op = .local_get, .operand = object }, value, .{ .op = .i32_store }, .{ .op = .local_get, .operand = object } });
}
fn controlExitShapes(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    _ = try module.ensureArena();
    const outward = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    const alternatives = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    const reentry = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    for ([_]u32{ outward, alternatives, reentry }) |f| try module.setParameterRoles(f, ir.packParameterRoles(&.{.scalar}));
    for ([_]u32{ outward, alternatives }) |f| {
        const first = try module.addLocal(f, .i32);
        const second = try module.addLocal(f, .i32);
        const joined = try module.addLocal(f, .i32);
        try module.emitSlice(f, &.{ .{ .op = .block, .operand = @backingInt(w.ValueType.i32) }, .{ .op = .local_get }, .{ .op = .if_ }, .{ .op = .block, .operand = @backingInt(w.ValueType.i32) } });
        try controlExitAllocation(&module, f, first, .{ .op = .i32_const, .operand = 42 });
        try module.emitSlice(f, &.{ .{ .op = .br, .operand = 2 }, .{ .op = .end }, .{ .op = .br, .operand = 1 } });
        if (f == alternatives) {
            try module.emit(f, .{ .op = .else_ });
            try controlExitAllocation(&module, f, second, .{ .op = .i32_const, .operand = 17 });
            try module.emitSlice(f, &.{ .{ .op = .br, .operand = 1 }, .{ .op = .end }, .{ .op = .i32_const } });
        } else {
            try module.emit(f, .{ .op = .end });
            try controlExitAllocation(&module, f, second, .{ .op = .i32_const, .operand = 17 });
        }
        try module.emitSlice(f, &.{ .{ .op = .end }, .{ .op = .local_set, .operand = joined }, .{ .op = .local_get, .operand = joined }, .{ .op = .i32_load } });
    }
    const index = try module.addLocal(reentry, .i32);
    const total = try module.addLocal(reentry, .i32);
    const previous = try module.addLocal(reentry, .i32);
    const current = try module.addLocal(reentry, .i32);
    const saved = try module.addLocal(reentry, .i32);
    try controlExitAllocation(&module, reentry, previous, .{ .op = .i32_const, .operand = 41 });
    try module.emitSlice(reentry, &.{ .{ .op = .drop }, .{ .op = .block }, .{ .op = .loop }, .{ .op = .local_get, .operand = index }, .{ .op = .local_get }, .{ .op = .i32_ge_u }, .{ .op = .br_if, .operand = 1 } });
    try controlExitAllocation(&module, reentry, current, .{ .op = .local_get, .operand = index });
    try module.emitSlice(reentry, &.{
        .{ .op = .drop },                          .{ .op = .local_get, .operand = previous }, .{ .op = .local_set, .operand = saved },
        .{ .op = .local_get, .operand = current }, .{ .op = .local_set, .operand = previous }, .{ .op = .local_get, .operand = total },
        .{ .op = .local_get, .operand = saved },   .{ .op = .i32_load },                       .{ .op = .i32_add },
        .{ .op = .local_get, .operand = current }, .{ .op = .i32_load },                       .{ .op = .i32_add },
        .{ .op = .local_set, .operand = total },   .{ .op = .local_get, .operand = index },    .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_add },                       .{ .op = .local_set, .operand = index },    .{ .op = .br },
        .{ .op = .end },                           .{ .op = .end },                            .{ .op = .local_get, .operand = total },
    });
    for ([_]u32{ outward, alternatives, reentry }) |f| {
        const before = try a.dupe(w.Instruction, module.functions.items[f].instructions.items);
        defer a.free(before);
        var result = (try run(a, &module, &module.functions.items[f])) orelse return error.TestUnexpectedResult;
        defer result.deinit(a);
        for (result.instructions.items) |inst| try std.testing.expect(inst.op != .call or inst.operand != module.arena.?.allocate_scalar);
        try std.testing.expectEqualSlices(w.Instruction, before, module.functions.items[f].instructions.items);
    }
}
test "scalar replacement joins nested outward exits and preserves loop backedge snapshots through OOM" {
    try controlExitShapes(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, controlExitShapes, .{});
}
