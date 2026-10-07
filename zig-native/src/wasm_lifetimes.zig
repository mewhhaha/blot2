//! Ownership over symbolic Wasm. Allocations have one owning local and any
//! number of fixed-offset borrows. Whole-module call summaries prove borrowing
//! without relying on source names. Backward control-flow liveness places a
//! release on every edge that ends an owner's lifetime, including loop exits.
//! Known private reference fields form ownership groups, including sharing and
//! cycles. Escaping graphs and unsupported aliases remain under arena policy.
const std = @import("std");
const w = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const flow = @import("wasm_control_flow.zig");
const A = std.mem.Allocator;
const absent = std.math.maxInt(u32);
// Overlap validation may compare several fields with the same access list.
// Bound proof work independently of record width; exhausting it keeps the
// existing arena policy rather than making compilation quadratic in that width.
const reference_check_limit = 256 * 1024;
const Value = struct { owner: u32 = 0, offset: u32 = 0, constant: ?u32 = null, region: u32 = 0, scope: u32 = 0 };
const Allocation = struct {
    size: u32,
    region: u32,
    last_region: u32,
    definition: u32,
    last: u32,
    local: u32 = absent,
    uses: u32 = absent,
    required: u32 = 0,
    escaped: bool = false,
    parameter: bool = false,
    returned: bool = false,
    segment: u32 = 0,
    references: u32 = absent,
    accesses: u32 = absent,
};
const Use = struct { at: u32, previous: u32 };
const Reference = struct {
    parent: u32,
    child: Value,
    offset: u32,
    at: u32,
    scope: u32,
    region: u32,
    previous: u32,
};
const Access = struct {
    offset: u32,
    bytes: u32,
    at: u32,
    previous: u32,
    kind: enum { read, write },
    reference: u32 = absent,
};
const Control = struct { height: usize, result: bool, identity: u32 };
const Group = struct { parent: u32, first: u32 = absent, next: u32 = absent };
fn groupRoot(groups: []Group, initial: u32) u32 {
    var root = initial;
    while (groups[root].parent != root) root = groups[root].parent;
    var at = initial;
    while (at != root) {
        const next = groups[at].parent;
        groups[at].parent = root;
        at = next;
    }
    return root;
}
fn releaseGroup(a: A, plan: *Plan, groups: []const Group, owners: []const Allocation, root: usize, at: u32, edge: Edge) !void {
    var member = groups[root].first;
    while (member != absent) {
        try plan.releases.append(a, .{ .after = at, .local = owners[member].local, .edge = edge });
        member = groups[member].next;
    }
}
pub const Edge = enum { after, before, when_true, when_false };
pub const Release = struct { after: u32, local: u32, edge: Edge = .after };
pub const Plan = struct {
    releases: std.ArrayList(Release) = .empty,
    pub fn deinit(self: *Plan, a: A) void {
        self.releases.deinit(a);
    }
};
pub const Output = ir.Body;
const Parameter = struct { escapes: bool = true, bytes: u32 = 0 };
const Summary = struct {
    parameters: []Parameter,
    invalidates: bool = true,
    owned_result_bytes: ?u32 = null,
    state: enum { unseen, active, done } = .unseen,
};

/// One demand-driven table per assembly. Recursive or opaque calls are
/// conservative; no optimistic summary is published while it is being built.
/// These are properties of emitted code, not retained source/evidence keys.
pub const Summaries = struct {
    a: A,
    module: *const w.Module,
    functions: []Summary,
    parameters: []Parameter,
    depth: u32 = 0,

    pub fn init(a: A, module: *const w.Module) !Summaries {
        const functions = try a.alloc(Summary, module.functions.items.len);
        errdefer a.free(functions);
        var count: usize = 0;
        for (module.functions.items) |f| count = std.math.add(usize, count, f.parameters.len) catch return error.OutOfMemory;
        const parameters = try a.alloc(Parameter, count);
        @memset(parameters, .{});
        var start: usize = 0;
        for (module.functions.items, functions) |f, *summary| {
            summary.* = .{ .parameters = parameters[start..][0..f.parameters.len] };
            start += f.parameters.len;
        }
        return .{ .a = a, .module = module, .functions = functions, .parameters = parameters };
    }
    pub fn deinit(self: *Summaries) void {
        self.a.free(self.parameters);
        self.a.free(self.functions);
    }
    fn get(self: *Summaries, id: u32) A.Error!Summary {
        const summary = &self.functions[id];
        if (summary.state != .unseen or self.depth == 128) return summary.*;
        if (self.module.arena) |arena| {
            if (id == arena.recycle or id == arena.reset or id == arena.collect or id == arena.mark or arena.isAllocation(id)) {
                summary.state = .done;
                return summary.*;
            }
        }
        summary.state = .active;
        self.depth += 1;
        defer self.depth -= 1;
        const function = &self.module.functions.items[id];
        var state = try Analysis.init(self.a, self, function, .parameters);
        defer state.deinit();
        // Machine i32 parameters are symbolic addresses during this proof.
        // Arithmetic/returning one makes that parameter ineligible for borrowing.
        for (function.parameters, 0..) |parameter, index| {
            if (parameter != .i32) continue;
            try state.allocations.append(self.a, .{ .size = std.math.maxInt(u32), .region = 0, .last_region = 0, .definition = 0, .last = 0, .parameter = true });
            state.locals[index] = .{ .owner = @intCast(state.allocations.items.len) };
        }
        try state.scan(self.module, function);
        if (state.valid) {
            var owner: usize = 0;
            for (function.parameters, 0..) |parameter, index| {
                if (parameter != .i32) continue;
                const value = state.allocations.items[owner];
                summary.parameters[index] = .{ .escapes = value.escaped or value.returned, .bytes = value.required };
                owner += 1;
            }
            summary.invalidates = state.invalidates;
            if (state.result_owner != 0 and state.result_owner != absent and !state.invalidates) {
                const result = state.allocations.items[state.result_owner - 1];
                // This summary transfers one allocation, not a heap graph.
                // An embedded alias (including a self/back edge) could escape
                // through a later shallow copy in the caller. Such results
                // need an ownership-graph summary before callers may free them.
                var embedded = false;
                for (state.references.items) |reference| if (reference.child.owner == state.result_owner) {
                    embedded = true;
                    break;
                };
                if (!result.parameter and !result.escaped and !embedded) summary.owned_result_bytes = result.size;
            }
        }
        summary.state = .done;
        return summary.*;
    }
};

const Analysis = struct {
    a: A,
    summaries: *Summaries,
    mode: enum { temporaries, parameters },
    locals: []Value,
    writes: []u32,
    read_unset: []bool,
    allocations: std.ArrayList(Allocation) = .empty,
    uses: std.ArrayList(Use) = .empty,
    stack: std.ArrayList(Value) = .empty,
    controls: std.ArrayList(Control) = .empty,
    references: std.ArrayList(Reference) = .empty,
    fields: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    accesses: std.ArrayList(Access) = .empty,
    region: u32 = 0,
    segment: u32 = 0,
    at: u32 = 0,
    valid: bool = true,
    invalidates: bool = false,
    result_owner: u32 = 0,

    fn init(a: A, summaries: *Summaries, function: *const w.Function, mode: @FieldType(Analysis, "mode")) A.Error!Analysis {
        const count = std.math.add(usize, function.parameters.len, function.locals.items.len) catch return error.OutOfMemory;
        const locals = try a.alloc(Value, count);
        errdefer a.free(locals);
        @memset(locals, .{});
        const writes = try a.alloc(u32, count);
        errdefer a.free(writes);
        @memset(writes, 0);
        @memset(writes[0..function.parameters.len], 1);
        const read_unset = try a.alloc(bool, count);
        @memset(read_unset, false);
        for (function.instructions.items) |inst| if (inst.op == .local_set or inst.op == .local_tee) {
            writes[inst.operand] +|= 1;
        };
        return .{ .a = a, .summaries = summaries, .mode = mode, .locals = locals, .writes = writes, .read_unset = read_unset };
    }
    fn deinit(self: *Analysis) void {
        self.a.free(self.locals);
        self.a.free(self.writes);
        self.a.free(self.read_unset);
        self.allocations.deinit(self.a);
        self.uses.deinit(self.a);
        self.stack.deinit(self.a);
        self.controls.deinit(self.a);
        self.references.deinit(self.a);
        self.fields.deinit(self.a);
        self.accesses.deinit(self.a);
    }
    fn dominates(self: *const Analysis, scope: u32) bool {
        if (scope == 0) return true;
        for (self.controls.items) |c| if (c.identity == scope) return true;
        return false;
    }
    fn pop(self: *Analysis) Value {
        const floor = if (self.controls.items.len == 0) 0 else self.controls.items[self.controls.items.len - 1].height;
        return if (self.stack.items.len > floor) self.stack.pop().? else .{};
    }
    fn push(self: *Analysis, value: Value) !void {
        try self.stack.append(self.a, value);
    }
    fn use(self: *Analysis, value: Value) !void {
        if (value.owner == 0) return;
        const owner = &self.allocations.items[value.owner - 1];
        owner.last = self.at;
        owner.last_region = self.region;
        if (self.mode == .temporaries and (owner.uses == absent or self.uses.items[owner.uses].at != self.at)) {
            try self.uses.append(self.a, .{ .at = self.at, .previous = owner.uses });
            owner.uses = @intCast(self.uses.items.len - 1);
        }
    }
    fn escape(self: *Analysis, value: Value) !void {
        try self.use(value);
        if (value.owner != 0) self.allocations.items[value.owner - 1].escaped = true;
    }
    fn recordResult(self: *Analysis, value: Value) !void {
        try self.use(value);
        if (value.owner != 0) self.allocations.items[value.owner - 1].returned = true;
        if (value.owner == 0 or value.offset != 0 or (self.result_owner != 0 and self.result_owner != value.owner)) {
            self.result_owner = absent;
        } else self.result_owner = value.owner;
    }
    fn allocation(self: *Analysis, bytes: u32) !void {
        try self.allocations.append(self.a, .{ .size = bytes, .region = self.region, .last_region = self.region, .definition = self.at, .last = self.at, .segment = self.segment });
        try self.push(.{ .owner = @intCast(self.allocations.items.len) });
    }
    fn memory(self: *Analysis, value: Value, offset: u32, bytes: ?u32, kind: @FieldType(Access, "kind"), reference: u32) !void {
        try self.use(value);
        if (value.owner == 0) return;
        const start = std.math.add(u32, value.offset, offset) catch {
            try self.escape(value);
            return;
        };
        const owner = &self.allocations.items[value.owner - 1];
        if (bytes == null or start > owner.size or bytes.? > owner.size - start) {
            try self.escape(value);
        } else {
            owner.required = @max(owner.required, start + bytes.?);
            if (!owner.parameter and bytes.? != 0) {
                try self.accesses.append(self.a, .{ .offset = start, .bytes = bytes.?, .at = self.at, .previous = owner.accesses, .kind = kind, .reference = reference });
                owner.accesses = @intCast(self.accesses.items.len - 1);
            }
        }
    }
    fn fieldKey(owner: u32, offset: u32) u64 {
        return (@as(u64, owner) << 32) | offset;
    }
    fn field(self: *const Analysis, address: Value, offset: u32) ?u32 {
        if (address.owner == 0) return null;
        const start = std.math.add(u32, address.offset, offset) catch return null;
        const id = self.fields.get(fieldKey(address.owner, start)) orelse return null;
        const reference = self.references.items[id];
        return if (reference.region == self.region and self.dominates(reference.scope)) id else null;
    }
    fn storeReference(self: *Analysis, address: Value, offset: u32, value: Value) !void {
        try self.use(value);
        if (value.owner == 0) return;
        // Parameters retain the old conservative store/escape contract. A
        // callee cannot hide an argument in its returned allocation and claim
        // that it only borrowed that argument.
        if (address.owner == 0 or self.allocations.items[address.owner - 1].parameter or self.allocations.items[value.owner - 1].parameter) {
            try self.escape(value);
            return;
        }
        const start = std.math.add(u32, address.offset, offset) catch {
            try self.escape(value);
            return;
        };
        const parent = &self.allocations.items[address.owner - 1];
        const id: u32 = @intCast(self.references.items.len);
        try self.references.append(self.a, .{ .parent = address.owner, .child = value, .offset = start, .at = self.at, .scope = if (self.controls.items.len == 0) 0 else self.controls.items[self.controls.items.len - 1].identity, .region = self.region, .previous = parent.references });
        parent.references = id;
        try self.fields.put(self.a, fieldKey(address.owner, start), id);
    }
    fn validateReferences(self: *Analysis) !void {
        if (self.references.items.len == 0) return;
        // Every read of a reference slot must carry the child's provenance.
        // Copies, calls exposing unknown contents, overlapping writes, forward
        // reads and conditional initialization decline the entire proof.
        var remaining: usize = reference_check_limit;
        for (self.references.items, 0..) |reference, id| {
            const parent = &self.allocations.items[reference.parent - 1];
            if (parent.escaped) continue;
            var next = parent.accesses;
            while (next != absent) {
                if (remaining == 0) {
                    parent.escaped = true;
                    break;
                }
                remaining -= 1;
                const access = self.accesses.items[next];
                next = access.previous;
                if (@as(u64, access.offset) >= @as(u64, reference.offset) + 4 or
                    @as(u64, reference.offset) >= @as(u64, access.offset) + access.bytes) continue;
                if (access.kind == .write and access.at <= reference.at) continue;
                if (access.kind == .read and access.reference == id and access.bytes == 4 and access.offset == reference.offset) continue;
                parent.escaped = true;
                break;
            }
        }
        // Escape is transitive through heap references. In particular, a
        // factory returning a child of a globally retained parent cannot report
        // that child as an independently owned fresh result.
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(self.a);
        for (self.allocations.items, 0..) |owner, i| if (owner.escaped) {
            try pending.append(self.a, @intCast(i));
        };
        var at: usize = 0;
        while (at < pending.items.len) : (at += 1) {
            var next = self.allocations.items[pending.items[at]].references;
            while (next != absent) {
                const reference = self.references.items[next];
                const child = &self.allocations.items[reference.child.owner - 1];
                if (!child.escaped) {
                    child.escaped = true;
                    try pending.append(self.a, reference.child.owner - 1);
                }
                next = reference.previous;
            }
        }
    }
    fn closeArm(self: *Analysis) !void {
        const c = self.controls.items[self.controls.items.len - 1];
        if (c.result) try self.escape(self.pop());
        for (self.stack.items[c.height..]) |value| try self.escape(value);
        self.stack.shrinkRetainingCapacity(c.height);
    }
    fn dead(self: *Analysis) !void {
        const floor = if (self.controls.items.len == 0) 0 else self.controls.items[self.controls.items.len - 1].height;
        for (self.stack.items[floor..]) |value| try self.escape(value);
        self.stack.shrinkRetainingCapacity(floor);
    }
    fn opaqueCall(self: *Analysis, parameters: usize, result: w.ValueType) !void {
        for (0..parameters) |_| try self.escape(self.pop());
        if (result != .none) try self.push(.{});
        self.region += 1;
        self.segment += 1;
        self.invalidates = true;
    }
    fn scan(self: *Analysis, module: *const w.Module, function: *const w.Function) A.Error!void {
        for (function.instructions.items, 0..) |inst, index| {
            self.at = @intCast(index);
            switch (inst.op) {
                .i32_const => try self.push(.{ .constant = inst.operand }),
                .f32_const, .global_get, .memory_size, .host_ref_null, .host_ref_size => try self.push(.{}),
                .local_get => {
                    var value = self.locals[inst.operand];
                    if (!self.dominates(value.scope)) {
                        try self.escape(value);
                        value.constant = null;
                    }
                    if (value.region != self.region) value.constant = null;
                    if (value.owner == 0 and value.constant == null and inst.operand >= function.parameters.len) self.read_unset[inst.operand] = true;
                    try self.use(value);
                    try self.push(value);
                },
                .local_set, .local_tee => {
                    var value = self.pop();
                    try self.use(value);
                    if (self.writes[inst.operand] != 1 or self.read_unset[inst.operand]) {
                        try self.escape(value);
                        try self.escape(self.locals[inst.operand]);
                        value.constant = null;
                    }
                    value.region = self.region;
                    value.scope = if (self.controls.items.len == 0) 0 else self.controls.items[self.controls.items.len - 1].identity;
                    self.locals[inst.operand] = value;
                    if (value.owner != 0 and value.offset == 0) {
                        const owner = &self.allocations.items[value.owner - 1];
                        if (owner.local == absent) owner.local = inst.operand;
                    }
                    if (inst.op == .local_tee) try self.push(value);
                },
                .i32_add => {
                    var right = self.pop();
                    var left = self.pop();
                    if (left.constant != null) std.mem.swap(Value, &left, &right);
                    try self.use(left);
                    try self.use(right);
                    if (right.constant) |offset| {
                        if (left.constant) |constant| try self.push(.{ .constant = constant +% offset }) else if (std.math.add(u32, left.offset, offset)) |sum| {
                            left.offset = sum;
                            try self.push(left);
                        } else |_| {
                            try self.escape(left);
                            try self.push(.{});
                        }
                    } else {
                        try self.escape(left);
                        try self.escape(right);
                        try self.push(.{});
                    }
                },
                .i32_load, .f32_load, .v128_load => {
                    const address = self.pop();
                    const reference = if (inst.op == .i32_load) self.field(address, inst.operand) else null;
                    try self.memory(address, inst.operand, ir.fixed(inst.op).bytes, .read, reference orelse absent);
                    try self.push(if (reference) |id| self.references.items[id].child else .{});
                },
                .i32_store, .f32_store, .v128_store => {
                    const value = self.pop();
                    const address = self.pop();
                    try self.memory(address, inst.operand, ir.fixed(inst.op).bytes, .write, absent);
                    if (inst.op == .i32_store) try self.storeReference(address, inst.operand, value) else try self.escape(value);
                },
                .memory_copy, .memory_fill => {
                    const bytes = self.pop();
                    const source = self.pop();
                    try self.escape(bytes);
                    if (inst.op == .memory_copy) try self.memory(source, 0, bytes.constant, .read, absent) else try self.escape(source);
                    try self.memory(self.pop(), 0, bytes.constant, .write, absent);
                },
                .call => {
                    const callee = ir.call(module, inst);
                    if (callee.ownership == .allocate or callee.ownership == .allocate_scalar) {
                        const bytes = self.pop();
                        try self.escape(bytes);
                        if (bytes.constant != null and bytes.constant.? > 0) try self.allocation(bytes.constant.?) else try self.push(.{});
                    } else {
                        const summary = try self.summaries.get(inst.operand);
                        for (0..callee.parameters.len) |argument| {
                            const parameter = summary.parameters[callee.parameters.len - 1 - argument];
                            const value = self.pop();
                            if (parameter.escapes or summary.invalidates) try self.escape(value) else try self.memory(value, 0, parameter.bytes, .read, absent);
                        }
                        if (summary.owned_result_bytes) |bytes| {
                            try self.allocation(bytes);
                        } else if (callee.result != .none) try self.push(.{});
                        if (summary.invalidates) {
                            self.region += 1;
                            self.segment += 1;
                            self.invalidates = true;
                        }
                    }
                },
                .call_indirect => {
                    try self.escape(self.pop());
                    const signature = ir.call(module, inst);
                    try self.opaqueCall(signature.parameters.len, signature.result);
                },
                .call_import => {
                    const signature = ir.call(module, inst);
                    try self.opaqueCall(signature.parameters.len, signature.result);
                },
                .block, .loop, .if_ => {
                    self.segment += 1;
                    if (inst.op == .if_) try self.escape(self.pop());
                    try self.controls.append(self.a, .{ .height = self.stack.items.len, .result = inst.operand != 0 and inst.operand != @backingInt(w.ValueType.none), .identity = self.at + 1 });
                },
                .else_ => {
                    self.segment += 1;
                    if (self.controls.items.len == 0) {
                        self.valid = false;
                        return;
                    }
                    try self.closeArm();
                    self.controls.items[self.controls.items.len - 1].identity = self.at + 1;
                },
                .end => {
                    self.segment += 1;
                    if (self.controls.items.len == 0) {
                        self.valid = false;
                        return;
                    }
                    try self.closeArm();
                    const c = self.controls.pop().?;
                    if (c.result) try self.push(.{});
                },
                .br, .br_if => {
                    self.segment += 1;
                    if (inst.op == .br_if) try self.escape(self.pop());
                    for (self.stack.items) |value| try self.escape(value);
                    if (inst.op == .br) try self.dead();
                },
                .return_ => {
                    self.segment += 1;
                    if (function.result != .none) try self.recordResult(self.pop());
                    try self.dead();
                },
                .unreachable_ => {
                    self.segment += 1;
                    try self.dead();
                },
                .drop => try self.use(self.pop()),
                else => {
                    const contract = ir.contract(module, function, inst);
                    for (0..contract.arity) |_| try self.escape(self.pop());
                    if (contract.result != .none) try self.push(.{});
                },
            }
        }
        if (function.result != .none) {
            if (self.stack.items.len != 0) try self.recordResult(self.pop()) else if (self.result_owner == 0) {
                self.result_owner = absent;
            }
        }
        if (self.controls.items.len != 0) self.valid = false;
        if (self.valid) try self.validateReferences();
    }
};

pub fn analyze(a: A, module: *const w.Module, function: *const w.Function) !Plan {
    var summaries = try Summaries.init(a, module);
    defer summaries.deinit();
    return analyzeWithSummaries(a, module, function, &summaries);
}
fn analyzeWithSummaries(a: A, module: *const w.Module, function: *const w.Function, summaries: *Summaries) !Plan {
    var plan: Plan = .{};
    errdefer plan.deinit(a);
    if (module.arena == null) return plan;
    var has_allocations = false;
    for (function.instructions.items) |inst| if (inst.op == .call) {
        if (module.arena.?.isAllocation(inst.operand) or (try summaries.get(inst.operand)).owned_result_bytes != null) {
            has_allocations = true;
            break;
        }
    };
    if (!has_allocations) return plan;
    var state = try Analysis.init(a, summaries, function, .temporaries);
    defer state.deinit();
    try state.scan(module, function);
    if (!state.valid or state.allocations.items.len == 0) return plan;
    const groups = try a.alloc(Group, state.allocations.items.len);
    defer a.free(groups);
    for (groups, 0..) |*group, i| group.* = .{ .parent = @intCast(i) };
    for (state.references.items) |reference| {
        const left = groupRoot(groups, reference.parent - 1);
        const right = groupRoot(groups, reference.child.owner - 1);
        groups[right].parent = left;
    }
    for (0..groups.len) |i| {
        const root = groupRoot(groups, @intCast(i));
        groups[i].next = groups[root].first;
        groups[root].first = @intCast(i);
    }
    var graph = try flow.Graph.init(a, function.instructions.items);
    defer graph.deinit(a);
    if (!graph.valid) return plan;
    const marks = try a.alloc(u32, graph.nodes.len);
    defer a.free(marks);
    @memset(marks, 0);
    var pending: std.ArrayList(u32) = .empty;
    defer pending.deinit(a);
    for (groups, 0..) |group, index| {
        if (group.parent != index) continue;
        var admitted = true;
        var definition: u32 = 0;
        var member = group.first;
        const segment = state.allocations.items[index].segment;
        while (member != absent) {
            const owner = state.allocations.items[member];
            // Members are created in one straight-line segment, so all of
            // their owning locals exist when the group's common lifetime
            // starts. Later branches may end that lifetime on different edges.
            if (owner.escaped or owner.returned or owner.local == absent or owner.region != owner.last_region or owner.segment != segment) admitted = false;
            definition = @max(definition, owner.definition);
            member = groups[member].next;
        }
        if (!admitted) continue;
        const stamp: u32 = @intCast(index + 1);
        pending.clearRetainingCapacity();
        member = group.first;
        while (member != absent) {
            var use = state.allocations.items[member].uses;
            while (use != absent) {
                const site = state.uses.items[use];
                if (site.at >= definition and marks[site.at] != stamp) {
                    marks[site.at] = stamp;
                    try pending.append(a, site.at);
                }
                use = site.previous;
            }
            member = groups[member].next;
        }
        try graph.markLive(a, marks, stamp, definition, &pending);
        var dominated = true;
        for (pending.items) |at| if (at != definition and graph.nodes[at].first == absent) {
            dominated = false;
            break;
        };
        if (!dominated) continue;
        for (pending.items) |at| {
            const node = graph.nodes[at];
            if (node.next[0] == absent) continue;
            const dead_true = marks[node.next[0]] != stamp or node.next[0] == definition;
            const dead_false = node.next[1] == absent or marks[node.next[1]] != stamp or node.next[1] == definition;
            if (!dead_true and !dead_false) continue;
            if (node.next[1] != absent and dead_true != dead_false) {
                try releaseGroup(a, &plan, groups, state.allocations.items, index, at, if (dead_true) .when_true else .when_false);
            } else if (dead_true) {
                const op = function.instructions.items[at].op;
                const before = op == .br or op == .br_if or op == .return_ or op == .unreachable_ or op == .else_ or op == .if_;
                try releaseGroup(a, &plan, groups, state.allocations.items, index, at, if (before) .before else .after);
            }
        }
    }
    std.mem.sort(Release, plan.releases.items, {}, struct {
        fn less(_: void, left: Release, right: Release) bool {
            if (left.after != right.after) return left.after < right.after;
            if (left.edge != right.edge) return @backingInt(left.edge) < @backingInt(right.edge);
            return left.local < right.local;
        }
    }.less);
    return plan;
}

pub fn run(a: A, module: *const w.Module, function: *const w.Function) !?Output {
    var summaries = try Summaries.init(a, module);
    defer summaries.deinit();
    return runWithSummaries(a, module, function, &summaries);
}
pub fn runWithSummaries(a: A, module: *const w.Module, function: *const w.Function, summaries: *Summaries) !?Output {
    var plan = try analyzeWithSummaries(a, module, function, summaries);
    defer plan.deinit(a);
    if (plan.releases.items.len == 0) return null;
    var out: Output = .{};
    errdefer out.deinit(a);
    try out.locals.appendSlice(a, function.locals.items);
    var condition: u32 = absent;
    var next: usize = 0;
    for (function.instructions.items, 0..) |inst, at| {
        const start = next;
        while (next < plan.releases.items.len and plan.releases.items[next].after == at) : (next += 1) {}
        const releases = plan.releases.items[start..next];
        for (releases) |release| if (release.edge == .before) try emitRelease(a, &out, module.arena.?.recycle, release.local);
        var conditional = false;
        for (releases) |release| if (release.edge == .when_true or release.edge == .when_false) {
            conditional = true;
            break;
        };
        if (conditional) {
            if (condition == absent) {
                condition = @intCast(function.parameters.len + out.locals.items.len);
                try out.locals.append(a, .i32);
            }
            // Keep branch-result operands below the condition intact. Wrapping
            // the original br_if in a new block would change its stack height.
            try out.instructions.appendSlice(a, &.{ .{ .op = .local_tee, .operand = condition }, .{ .op = .if_ } });
            for (releases) |release| if (release.edge == .when_true) try emitRelease(a, &out, module.arena.?.recycle, release.local);
            try out.instructions.append(a, .{ .op = .else_ });
            for (releases) |release| if (release.edge == .when_false) try emitRelease(a, &out, module.arena.?.recycle, release.local);
            try out.instructions.appendSlice(a, &.{ .{ .op = .end }, .{ .op = .local_get, .operand = condition } });
        }
        try out.instructions.append(a, inst);
        for (releases) |release| if (release.edge == .after) try emitRelease(a, &out, module.arena.?.recycle, release.local);
    }
    return out;
}
fn emitRelease(a: A, out: *Output, recycle: u32, local: u32) !void {
    try out.instructions.appendSlice(a, &.{ .{ .op = .local_get, .operand = local }, .{ .op = .call, .operand = recycle } });
}

fn lifetimeOwnership(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const f = try module.addFunction(&.{.i32}, .i32);
    const object = try module.addLocal(f, .i32);
    const alias = try module.addLocal(f, .i32);
    try module.emitSlice(f, &.{
        .{ .op = .i32_const, .operand = 128 },    .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object },
        .{ .op = .local_get, .operand = object }, .{ .op = .local_get, .operand = 0 },         .{ .op = .i32_store, .operand = 124 },
        .{ .op = .local_get, .operand = object }, .{ .op = .i32_const, .operand = 120 },       .{ .op = .i32_add },
        .{ .op = .local_set, .operand = alias },  .{ .op = .local_get, .operand = alias },     .{ .op = .i32_load, .operand = 4 },
    });
    const before = try a.dupe(w.Instruction, module.functions.items[f].instructions.items);
    defer a.free(before);
    var plan = try analyze(a, &module, &module.functions.items[f]);
    defer plan.deinit(a);
    try std.testing.expectEqualSlices(Release, &.{.{ .after = 11, .local = object }}, plan.releases.items);
    var output = (try run(a, &module, &module.functions.items[f])).?;
    defer output.deinit(a);
    try std.testing.expectEqual(arena.recycle, output.instructions.items[output.instructions.items.len - 1].operand);
    try std.testing.expectEqualSlices(w.Instruction, before, module.functions.items[f].instructions.items);
}
test "temporary lifetime proof owns scratch and leaves retained instructions untouched on failure" {
    try lifetimeOwnership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, lifetimeOwnership, .{});
}

test "temporary lifetime proof excludes escapes, unknown offsets and multiple assignments" {
    const a = std.testing.allocator;
    for ([_]u32{ 0, 1, 3, 4, 5, 6 }) |scenario| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const f = try module.addFunction(&.{.i32}, .i32);
        const object = try module.addLocal(f, .i32);
        try module.emitSlice(f, &.{ .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object } });
        switch (scenario) {
            0 => try module.emit(f, .{ .op = .local_get, .operand = object }), // returned owner
            1 => { // address escapes as a stored field
                try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .local_get, .operand = object }, .{ .op = .i32_store }, .{ .op = .i32_const } });
            },
            2 => { // borrowed read crosses a branch
                try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .if_, .operand = 0x7f }, .{ .op = .local_get, .operand = object }, .{ .op = .i32_load }, .{ .op = .else_ }, .{ .op = .i32_const }, .{ .op = .end } });
            },
            3 => { // unknown address could escape the allocation
                try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = object }, .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_add }, .{ .op = .i32_load } });
            },
            4 => { // releasing the overwritten local would free the wrong value
                try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = object }, .{ .op = .i32_load }, .{ .op = .i32_const }, .{ .op = .local_set, .operand = object } });
            },
            5 => { // opaque calls may retain arguments
                const callee = try module.addFunction(&.{.i32}, .i32);
                try module.emit(callee, .{ .op = .local_get, .operand = 0 });
                try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = object }, .{ .op = .call, .operand = callee } });
            },
            6 => { // offset+load width must stay inside this allocation
                try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = object }, .{ .op = .i32_load, .operand = 128 } });
            },
            else => unreachable,
        }
        var plan = try analyze(a, &module, &module.functions.items[f]);
        defer plan.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), plan.releases.items.len);
    }
}

test "a conditional size is not treated as a dominating constant" {
    const a = std.testing.allocator;
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const f = try module.addFunction(&.{.i32}, .i32);
    const size = try module.addLocal(f, .i32);
    const object = try module.addLocal(f, .i32);
    try module.emitSlice(f, &.{
        .{ .op = .local_get, .operand = 0 },    .{ .op = .if_ },                             .{ .op = .i32_const, .operand = 128 },    .{ .op = .local_set, .operand = size },   .{ .op = .end },
        .{ .op = .local_get, .operand = size }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object }, .{ .op = .local_get, .operand = object }, .{ .op = .i32_load },
    });
    var plan = try analyze(a, &module, &module.functions.items[f]);
    defer plan.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), plan.releases.items.len);
}

fn controlOwnership(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const read = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(read, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_load, .operand = 124 } });
    const f = try module.addFunction(&.{.i32}, .i32);
    const object = try module.addLocal(f, .i32);
    try module.emitSlice(f, &.{
        .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object },
        .{ .op = .local_get, .operand = 0 },   .{ .op = .if_, .operand = 0x7f },            .{ .op = .local_get, .operand = object },
        .{ .op = .call, .operand = read },     .{ .op = .else_ },                           .{ .op = .i32_const },
        .{ .op = .end },
    });
    var plan = try analyze(a, &module, &module.functions.items[f]);
    defer plan.deinit(a);
    try std.testing.expectEqualSlices(Release, &.{
        .{ .after = 4, .local = object, .edge = .when_false }, .{ .after = 6, .local = object },
    }, plan.releases.items);
    var output = (try run(a, &module, &module.functions.items[f])).?;
    defer output.deinit(a);
    try std.testing.expectEqual(module.functions.items[f].locals.items.len + 1, output.locals.items.len);
    try std.testing.expectEqual(@as(usize, 10), module.functions.items[f].instructions.items.len);
}
test "control-flow lifetimes and borrow summaries own their output through allocation failure" {
    try controlOwnership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, controlOwnership, .{});
}

test "borrow summaries reject retained addresses, oversized borrows, recursive calls and invalidation" {
    const a = std.testing.allocator;
    for (0..5) |scenario| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const callee = try module.addFunction(&.{.i32}, .i32);
        if (scenario == 0) {
            const global = try module.addGlobal(.pointer, 0, true);
            try module.emitSlice(callee, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .global_set, .operand = global }, .{ .op = .i32_const } });
        } else if (scenario == 1) {
            try module.emitSlice(callee, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_load, .operand = 128 } });
        } else if (scenario == 2) {
            try module.emitSlice(callee, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .call, .operand = callee } });
        } else if (scenario == 3) {
            try module.emitSlice(callee, &.{ .{ .op = .i32_const }, .{ .op = .call, .operand = arena.reset }, .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_load } });
        } else {
            // An address returned through a branch is still an escape.
            try module.emitSlice(callee, &.{ .{ .op = .i32_const }, .{ .op = .if_, .operand = 0x7f }, .{ .op = .local_get, .operand = 0 }, .{ .op = .else_ }, .{ .op = .i32_const }, .{ .op = .end } });
        }
        const f = try module.addFunction(&.{}, .i32);
        const object = try module.addLocal(f, .i32);
        try module.emitSlice(f, &.{
            .{ .op = .i32_const, .operand = 128 },    .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object },
            .{ .op = .local_get, .operand = object }, .{ .op = .call, .operand = callee },
        });
        var plan = try analyze(a, &module, &module.functions.items[f]);
        defer plan.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), plan.releases.items.len);
    }
}

test "conditional owners and loop-carried aliases do not gain an unconditional release" {
    const a = std.testing.allocator;
    for (0..2) |scenario| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const f = try module.addFunction(&.{.i32}, .i32);
        const object = try module.addLocal(f, .i32);
        if (scenario == 0) {
            try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .if_ } });
        } else {
            try module.emitSlice(f, &.{ .{ .op = .loop }, .{ .op = .local_get, .operand = object }, .{ .op = .drop } });
        }
        try module.emitSlice(f, &.{ .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object } });
        if (scenario == 1) try module.emit(f, .{ .op = .br });
        try module.emitSlice(f, &.{ .{ .op = .end }, .{ .op = .local_get, .operand = object }, .{ .op = .i32_load } });
        var plan = try analyze(a, &module, &module.functions.items[f]);
        defer plan.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), plan.releases.items.len);
    }
}

test "fresh results transfer ownership through calls but shared or conditional results do not" {
    const a = std.testing.allocator;
    for (0..3) |scenario| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const factory = try module.addFunction(&.{.i32}, .i32);
        const fresh = try module.addLocal(factory, .i32);
        try module.emitSlice(factory, &.{ .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = fresh } });
        if (scenario == 1) {
            const global = try module.addGlobal(.pointer, 0, true);
            try module.emitSlice(factory, &.{ .{ .op = .local_get, .operand = fresh }, .{ .op = .global_set, .operand = global } });
        } else if (scenario == 2) {
            try module.emitSlice(factory, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .if_ }, .{ .op = .i32_const }, .{ .op = .return_ }, .{ .op = .end } });
        }
        try module.emit(factory, .{ .op = .local_get, .operand = fresh });
        const f = try module.addFunction(&.{}, .i32);
        const object = try module.addLocal(f, .i32);
        try module.emitSlice(f, &.{ .{ .op = .i32_const }, .{ .op = .call, .operand = factory }, .{ .op = .local_set, .operand = object }, .{ .op = .local_get, .operand = object }, .{ .op = .i32_load, .operand = 124 } });
        var plan = try analyze(a, &module, &module.functions.items[f]);
        defer plan.deinit(a);
        try std.testing.expectEqual(@as(usize, if (scenario == 0) 1 else 0), plan.releases.items.len);
        if (scenario == 0) {
            var factory_plan = try analyze(a, &module, &module.functions.items[factory]);
            defer factory_plan.deinit(a);
            try std.testing.expectEqual(@as(usize, 0), factory_plan.releases.items.len);
        }
    }
}

fn closedGraph(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const f = try module.addFunction(&.{.i32}, .i32);
    var objects: [3]u32 = undefined;
    for (&objects) |*object| {
        object.* = try module.addLocal(f, .i32);
        try module.emitSlice(f, &.{ .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object.* } });
    }
    for ([_][2]u32{ .{ 0, 2 }, .{ 1, 2 }, .{ 2, 0 } }) |edge| try module.emitSlice(f, &.{
        .{ .op = .local_get, .operand = objects[edge[0]] }, .{ .op = .local_get, .operand = objects[edge[1]] }, .{ .op = .i32_store },
    });
    try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = objects[1] }, .{ .op = .i32_load }, .{ .op = .i32_load }, .{ .op = .i32_load, .operand = 124 } });
    var plan = try analyze(a, &module, &module.functions.items[f]);
    defer plan.deinit(a);
    try std.testing.expectEqual(@as(usize, 3), plan.releases.items.len);
    for (plan.releases.items, objects) |release, object| {
        try std.testing.expectEqual(object, release.local);
        try std.testing.expectEqual(@as(u32, 21), release.after);
    }
    var output = (try run(a, &module, &module.functions.items[f])).?;
    defer output.deinit(a);
    try std.testing.expectEqual(@as(usize, 22), module.functions.items[f].instructions.items.len);
    try std.testing.expectEqual(@as(usize, 28), output.instructions.items.len);
}
test "closed shared and cyclic ownership groups survive allocation failure without publishing partial output" {
    try closedGraph(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, closedGraph, .{});
}

test "shared graphs reject escaped members, unknown contents, overlapping writes and returned aliases" {
    const a = std.testing.allocator;
    for (0..8) |scenario| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const f = try module.addFunction(&.{.i32}, .i32);
        const parent = try module.addLocal(f, .i32);
        const child = try module.addLocal(f, .i32);
        for ([_]u32{ parent, child }) |object| try module.emitSlice(f, &.{
            .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object },
        });
        if (scenario == 6) try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = parent }, .{ .op = .i32_load }, .{ .op = .drop } });
        try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = parent }, .{ .op = .local_get, .operand = child }, .{ .op = .i32_store } });
        switch (scenario) {
            0, 1 => {
                const global = try module.addGlobal(.pointer, 0, true);
                try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = if (scenario == 0) parent else child }, .{ .op = .global_set, .operand = global } });
            },
            2 => {
                const callee = try module.addFunction(&.{.i32}, .i32);
                try module.emitSlice(callee, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_load } });
                try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = parent }, .{ .op = .call, .operand = callee }, .{ .op = .drop } });
            },
            3 => try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = parent }, .{ .op = .i32_const }, .{ .op = .i32_store, .operand = 2 } }),
            4 => try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .local_get, .operand = parent }, .{ .op = .i32_const, .operand = 4 }, .{ .op = .memory_copy } }),
            5 => try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = parent }, .{ .op = .i32_load }, .{ .op = .return_ } }),
            6 => {},
            7 => try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = parent }, .{ .op = .i32_const }, .{ .op = .i32_const, .operand = 16 }, .{ .op = .memory_fill } }),
            else => unreachable,
        }
        try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = child }, .{ .op = .i32_load, .operand = 124 } });
        var plan = try analyze(a, &module, &module.functions.items[f]);
        defer plan.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), plan.releases.items.len);
    }
}

test "an escaped parent prevents reporting its child as a fresh owned result" {
    const a = std.testing.allocator;
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const factory = try module.addFunction(&.{}, .i32);
    const parent = try module.addLocal(factory, .i32);
    const child = try module.addLocal(factory, .i32);
    for ([_]u32{ parent, child }) |object| try module.emitSlice(factory, &.{
        .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object },
    });
    const global = try module.addGlobal(.pointer, 0, true);
    try module.emitSlice(factory, &.{
        .{ .op = .local_get, .operand = parent }, .{ .op = .local_get, .operand = child },   .{ .op = .i32_store },
        .{ .op = .local_get, .operand = parent }, .{ .op = .global_set, .operand = global }, .{ .op = .local_get, .operand = parent },
        .{ .op = .i32_load },
    });
    var summaries = try Summaries.init(a, &module);
    defer summaries.deinit();
    try std.testing.expectEqual(@as(?u32, null), (try summaries.get(factory)).owned_result_bytes);
}

test "capturing an argument in a private record is not a borrowed-parameter summary" {
    const a = std.testing.allocator;
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const factory = try module.addFunction(&.{.i32}, .i32);
    const parent = try module.addLocal(factory, .i32);
    try module.emitSlice(factory, &.{
        .{ .op = .i32_const, .operand = 128 },    .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = parent },
        .{ .op = .local_get, .operand = parent }, .{ .op = .local_get, .operand = 0 },         .{ .op = .i32_store },
        .{ .op = .local_get, .operand = parent },
    });
    var summaries = try Summaries.init(a, &module);
    defer summaries.deinit();
    try std.testing.expect((try summaries.get(factory)).parameters[0].escapes);
}

test "fresh-result summaries do not hide an embedded self alias from later shallow copies" {
    const a = std.testing.allocator;
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const factory = try module.addFunction(&.{}, .i32);
    const object = try module.addLocal(factory, .i32);
    try module.emitSlice(factory, &.{
        .{ .op = .i32_const, .operand = 128 },    .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object },
        .{ .op = .local_get, .operand = object }, .{ .op = .local_get, .operand = object },    .{ .op = .i32_store },
        .{ .op = .local_get, .operand = object },
    });
    var summaries = try Summaries.init(a, &module);
    defer summaries.deinit();
    try std.testing.expectEqual(@as(?u32, null), (try summaries.get(factory)).owned_result_bytes);
}

test "very wide cyclic records decline a proof whose overlap work exceeds the budget" {
    const a = std.testing.allocator;
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const f = try module.addFunction(&.{}, .none);
    const object = try module.addLocal(f, .i32);
    try module.emitSlice(f, &.{
        .{ .op = .i32_const, .operand = 4096 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object },
    });
    for (0..1024) |field| try module.emitSlice(f, &.{
        .{ .op = .local_get, .operand = object }, .{ .op = .local_get, .operand = object }, .{ .op = .i32_store, .operand = @intCast(field * 4) },
    });
    var plan = try analyze(a, &module, &module.functions.items[f]);
    defer plan.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), plan.releases.items.len);
}
