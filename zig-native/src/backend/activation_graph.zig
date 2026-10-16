//! Bounded executable heap graph for one scalar-returning activation.
//! No consumer may turn a partial graph or caller-supplied report into authority.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const modes = @import("provider_modes.zig");
const constructors = @import("callable_origins.zig");
const providers = @import("provider_origins.zig");
const demands = @import("../eval/demand_origins.zig");
const A = std.mem.Allocator;
const Error = A.Error || error{Unavailable};
const absent = std.math.maxInt(u32);
const max_sites = 64;
const max_words = 16;
const TagTest = struct { local: u32, version: u32, value: u32, equal: bool };
const Value = struct {
    owners: u64 = 0,
    codes: u64 = 0,
    constant: ?u32 = 0,
    offset: u32 = 0,
    outside_head: bool = false,
    cancellation: bool = false,
    local: ?u32 = null,
    version: u32 = 0,
    tag_field: bool = false,
    tag_test: ?TagTest = null,
    condition_global: bool = false,
    fn merge(self: *Value, other: Value) bool {
        const previous = self.*;
        self.owners |= other.owners;
        self.codes |= other.codes;
        self.outside_head = self.outside_head or other.outside_head;
        self.cancellation = self.cancellation or other.cancellation;
        if (self.constant != other.constant) self.constant = null;
        if (self.offset != other.offset) self.offset = absent;
        self.local = null;
        self.tag_field = false;
        self.tag_test = null;
        self.condition_global = false;
        return !std.meta.eql(previous, self.*);
    }
    fn reference(self: Value) bool {
        return self.owners != 0 or self.outside_head;
    }
};
pub const Kind = enum { ordinary, closure, memo, frame, static_data };
pub const Site = struct { function: u32, at: u32, context: u32, bytes: u32, kind: Kind, provider: u64 = 0, children: u64 = 0, borrowed_head: bool = false };
pub const Store = struct { function: u32, at: u32, context: u32, owners: u64, values: u64, offset: u32, outside_value: bool };
pub const Call = struct { from: u32, at: u32, target: u32, indirect: bool };
pub const Blocker = enum { none, boundary, limit, instruction, receiver, escape, recursion, epoch, control, caller };
pub const Report = struct {
    sites: []Site,
    calls: []Call,
    contexts: []Context,
    stores: []Store,
    complete: bool,
    blocker: Blocker,
    function: u32,
    at: u32,
    work: usize,
    pub fn deinit(self: *Report, a: A) void {
        a.free(self.sites);
        a.free(self.calls);
        a.free(self.contexts);
        a.free(self.stores);
    }
};
const Object = struct {
    site: Site,
    words: [max_words]Value = @splat(.{}),
    roles: [max_words]ir.Role = @splat(.unknown),
    written: u16 = 0,
    observed: u16 = 0,
    frame: ?providers.Fact = null,
    producer: ?u32 = null,
};
pub const Context = struct { parent: u32, at: u32, function: u32, provider: u64 = 0, outside_provider: bool = false };
const Flow = struct {
    cells: [max_sites]?*const Value = @splat(null),
    caches: [max_sites]?*const Value = @splat(null),
    written: u64 = 0,
    ready: u64 = 0,
    evaluating: u64 = 0,
};
const Frame = struct { end: u32, alternate: u32, height: usize, result: bool };
const State = struct {
    pc: u32 = 0,
    locals: []Value,
    versions: []u32,
    stack: std.ArrayList(Value) = .empty,
    frames: std.ArrayList(Frame) = .empty,
    guard: enum { unknown, clear, active } = .unknown,
    flow: Flow = .{},
    fn clone(self: State, a: A) A.Error!State {
        const locals = try a.dupe(Value, self.locals);
        errdefer a.free(locals);
        const versions = try a.dupe(u32, self.versions);
        errdefer a.free(versions);
        var stack = try self.stack.clone(a);
        errdefer stack.deinit(a);
        return .{ .pc = self.pc, .locals = locals, .versions = versions, .stack = stack, .frames = try self.frames.clone(a), .guard = self.guard, .flow = self.flow };
    }
    fn deinit(self: *State, a: A) void {
        a.free(self.locals);
        a.free(self.versions);
        self.stack.deinit(a);
        self.frames.deinit(a);
    }
    fn pop(self: *State) Error!Value {
        return self.stack.pop() orelse error.Unavailable;
    }
    fn push(self: *State, a: A, value: Value) A.Error!void {
        try self.stack.append(a, value);
    }
};
const Outcome = struct { value: Value, guard: @FieldType(State, "guard"), flow: Flow };
const Structure = struct { ends: []u32, alternates: []u32 };
const Graph = struct {
    a: A,
    module: *const wasm.Module,
    catalog: modes.Catalog,
    objects: std.ArrayList(Object) = .empty,
    calls: std.ArrayList(Call) = .empty,
    targets: std.ArrayList(u32) = .empty,
    contexts: std.ArrayList(Context) = .empty,
    stores: std.ArrayList(Store) = .empty,
    active: std.ArrayList(u32) = .empty,
    guard_global: ?u32 = null,
    work: usize = 0,
    changed: bool = false,
    structures: []?Structure = &.{},
    blocker: Blocker = .none,
    function: u32 = 0,
    at: u32 = 0,
    fn freeze(self: *Graph, value: Value) A.Error!*const Value {
        const snapshot = try self.a.create(Value);
        snapshot.* = value;
        return snapshot;
    }
    fn fail(self: *Graph, reason: Blocker) Error {
        if (self.blocker == .none) self.blocker = reason;
        return error.Unavailable;
    }
    fn spend(self: *Graph, count: usize) Error!void {
        if (count > 262144 -| self.work) return self.fail(.limit);
        self.work += count;
    }
    fn context(self: *Graph, parent: u32, at: u32, function: u32) Error!u32 {
        for (self.contexts.items, 0..) |entry, id| if (entry.parent == parent and entry.at == at and entry.function == function) return @intCast(id);
        if (self.contexts.items.len == 64) return self.fail(.limit);
        try self.contexts.append(self.a, .{ .parent = parent, .at = at, .function = function });
        return @intCast(self.contexts.items.len - 1);
    }
    fn target(self: *Graph, function: u32) Error!Value {
        for (self.targets.items, 0..) |entry, id| if (entry == function) return .{ .codes = @as(u64, 1) << @intCast(id), .constant = null };
        if (self.targets.items.len == 64) return self.fail(.limit);
        try self.targets.append(self.a, function);
        return .{ .codes = @as(u64, 1) << @intCast(self.targets.items.len - 1), .constant = null };
    }
    fn object(self: *Graph, context_id: u32, function: u32, at: u32, bytes: u32, kind: Kind) Error!u32 {
        for (self.objects.items, 0..) |entry, id| if (entry.site.context == context_id and entry.site.function == function and entry.site.at == at) return @intCast(id);
        if (self.objects.items.len == max_sites or bytes == 0 or bytes % 4 != 0 or bytes / 4 > max_words) return self.fail(.limit);
        try self.objects.append(self.a, .{ .site = .{ .context = context_id, .function = function, .at = at, .bytes = bytes, .kind = kind } });
        return @intCast(self.objects.items.len - 1);
    }
    fn staticObject(self: *Graph, address: u32) Error!Value {
        const id = try self.object(absent, absent, address, 8, .static_data);
        if (address > self.module.data.items.len or 8 > self.module.data.items.len - address) return self.fail(.receiver);
        var code: ?u32 = null;
        for (self.module.table_origins.items) |origin| if (origin.function == null and origin.place == address and constructors.construction(self.module, origin) != null) {
            code = origin.target;
            break;
        };
        for (0..2) |word| {
            const value = std.mem.readInt(u32, self.module.data.items[address + word * 4 ..][0..4], .little);
            var field: Value = .{ .constant = value };
            if (word == 0 and code != null) field = try self.target(code.?);
            if (word == 1 and value != 0) return self.fail(.receiver);
            self.objects.items[id].words[word] = field;
            self.objects.items[id].roles[word] = .scalar;
            self.objects.items[id].written |= @as(u16, 1) << @intCast(word);
        }
        return .{ .owners = @as(u64, 1) << @intCast(id), .constant = null };
    }
    fn load(self: *Graph, flow: *const Flow, address: Value, offset: u32) Error!Value {
        if (address.outside_head or address.owners == 0 or address.offset == absent) return self.fail(.receiver);
        const position = std.math.add(u32, address.offset, offset) catch return self.fail(.receiver);
        if (position % 4 != 0) return self.fail(.receiver);
        var result: ?Value = null;
        var owners = address.owners;
        while (owners != 0) {
            const id: usize = @intCast(@ctz(owners));
            owners &= owners - 1;
            const object_ = &self.objects.items[id];
            if (position >= object_.site.bytes) return self.fail(.receiver);
            if (object_.written & (@as(u16, 1) << @intCast(position / 4)) == 0) return self.fail(.receiver);
            var field = object_.words[position / 4];
            const bit = @as(u64, 1) << @intCast(id);
            if (object_.frame != null and position == 4) {
                if (flow.written & bit == 0) return self.fail(.receiver);
                field = (flow.cells[id] orelse return self.fail(.receiver)).*;
            } else object_.observed |= @as(u16, 1) << @intCast(position / 4);
            if (result) |*value| _ = value.merge(field) else result = field;
        }
        var value = result orelse return self.fail(.receiver);
        if (position == 0 and value.codes == 0 and value.owners == 0 and address.local != null) {
            value.tag_field = true;
            value.local = address.local;
            value.version = address.version;
        }
        return value;
    }
    fn recordStore(self: *Graph, context_id: u32, function: u32, at: u32, owners: u64, offset: u32, value: Value) Error!void {
        for (self.stores.items) |*entry| if (entry.context == context_id and entry.function == function and entry.at == at and entry.offset == offset) {
            entry.owners |= owners;
            entry.values |= value.owners;
            entry.outside_value = entry.outside_value or value.outside_head;
            return;
        };
        if (self.stores.items.len == 256) return self.fail(.limit);
        try self.stores.append(self.a, .{ .function = function, .at = at, .context = context_id, .owners = owners, .values = value.owners, .offset = offset, .outside_value = value.outside_head });
    }
    fn store(self: *Graph, flow: *Flow, context_id: u32, function: u32, at: u32, address: Value, offset: u32, value: Value) Error!void {
        if (address.outside_head or address.owners == 0 or address.offset == absent) return self.fail(.escape);
        const position = std.math.add(u32, address.offset, offset) catch return self.fail(.receiver);
        if (position % 4 != 0) return self.fail(.receiver);
        try self.recordStore(context_id, function, at, address.owners, position, value);
        var owners = address.owners;
        while (owners != 0) {
            const id: usize = @intCast(@ctz(owners));
            owners &= owners - 1;
            const object_ = &self.objects.items[id];
            if (position >= object_.site.bytes or object_.site.kind == .static_data) return self.fail(.escape);
            if (value.reference() and object_.roles[position / 4] != .reference) return self.fail(.escape);
            if (object_.roles[position / 4] == .reference and !value.reference() and (value.codes != 0 or value.constant != 0 or value.offset != 0)) return self.fail(.receiver);
            if (value.outside_head and (object_.frame == null or position != 8)) return self.fail(.escape);
            const bit = @as(u16, 1) << @intCast(position / 4);
            if (object_.written & bit == 0) {
                object_.words[position / 4] = value;
                object_.words[position / 4].local = null;
                object_.written |= bit;
            } else {
                const changed = object_.words[position / 4].merge(value);
                // Only a value already consumed by this interpretation can
                // invalidate it. Fresh definitions are visible to later reads;
                // State values use path-owned Flow snapshots instead.
                if (changed and object_.observed & bit != 0) self.changed = true;
            }
            if (object_.frame != null and position == 4) {
                flow.cells[id] = try self.freeze(value);
                flow.written |= @as(u64, 1) << @intCast(id);
            }
            object_.site.children |= value.owners;
            object_.site.borrowed_head = object_.site.borrowed_head or value.outside_head;
        }
    }
    fn structure(self: *Graph, function: u32) Error!Structure {
        if (self.structures[function]) |known| return known;
        const code = self.module.functions.items[function].instructions.items;
        const ends = try self.a.alloc(u32, code.len);
        const alternates = try self.a.alloc(u32, code.len);
        @memset(ends, absent);
        @memset(alternates, absent);
        var stack: std.ArrayList(u32) = .empty;
        for (code, 0..) |inst, at| switch (inst.op) {
            .block, .if_ => try stack.append(self.a, @intCast(at)),
            .loop => return self.fail(.epoch),
            .else_ => {
                if (stack.items.len == 0) return self.fail(.control);
                const top = stack.items[stack.items.len - 1];
                if (code[top].op != .if_ or alternates[top] != absent) return self.fail(.control);
                alternates[top] = @intCast(at);
            },
            .end => {
                const top = stack.pop() orelse return self.fail(.control);
                ends[top] = @intCast(at);
            },
            else => {},
        };
        if (stack.items.len != 0) return self.fail(.control);
        const result: Structure = .{ .ends = ends, .alternates = alternates };
        self.structures[function] = result;
        return result;
    }
    fn recordCall(self: *Graph, from: u32, at: u32, target_id: u32, indirect: bool) Error!void {
        const call: Call = .{ .from = from, .at = at, .target = target_id, .indirect = indirect };
        for (self.calls.items) |old| if (std.meta.eql(old, call)) return;
        if (self.calls.items.len == 256) return self.fail(.limit);
        try self.calls.append(self.a, call);
    }
    fn incoming(self: *Graph, boundary: u32) Error!void {
        const affected = try self.a.alloc(bool, self.module.functions.items.len);
        @memset(affected, false);
        affected[boundary] = true;
        for (self.calls.items) |call| {
            affected[call.from] = true;
            affected[call.target] = true;
        }
        for (self.module.exports.items) |entry| if (!entry.global and entry.index < affected.len and entry.index != boundary and affected[entry.index]) return self.fail(.caller);
        if (self.module.start) |id| if (id >= affected.len or (id != boundary and affected[id])) return self.fail(.caller);
        for (self.module.functions.items, 0..) |body_, function| {
            if (self.module.runtimeHelper(function)) continue;
            for (body_.instructions.items, 0..) |inst, at| {
                try self.spend(1);
                if (inst.op == .call and inst.operand < affected.len and affected[inst.operand] and inst.operand != boundary and !affected[function]) {
                    self.function = @intCast(function);
                    self.at = @intCast(at);
                    return self.fail(.caller);
                }
                if (!inst.table_reference or inst.operand >= affected.len or !affected[inst.operand]) continue;
                var constructed = false;
                for (self.module.table_origins.items) |origin| {
                    if (origin.function != @as(u32, @intCast(function)) or origin.place != at or origin.target != inst.operand) continue;
                    if (!affected[function] or constructors.construction(self.module, origin) == null) return self.fail(.caller);
                    constructed = true;
                    break;
                }
                if (!constructed) return self.fail(.caller);
            }
        }
        for (self.module.table_origins.items) |origin| {
            if (origin.target >= affected.len or (origin.function != null and origin.function.? >= affected.len)) return self.fail(.caller);
            if (!affected[origin.target]) continue;
            if (origin.function == null or !affected[origin.function.?] or constructors.construction(self.module, origin) == null) return self.fail(.caller);
        }
    }
    fn allocation(self: *Graph, flow: *Flow, context_id: u32, function: u32, at: u32, bytes: u32, head: Value) Error!Value {
        const body = &self.module.functions.items[function];
        const annotations = ir.allocationAnnotations(body.instructions.items, at);
        if (annotations.len == 0) return self.fail(.instruction);
        const id = try self.object(context_id, function, at, bytes, .ordinary);
        if (head.offset != 0) return self.fail(.receiver);
        self.objects.items[id].site.provider |= head.owners;
        const bit = @as(u64, 1) << @intCast(id);
        flow.written &= ~bit;
        flow.ready &= ~bit;
        flow.evaluating &= ~bit;
        for (0..bytes / 4) |word| {
            const role = ir.Ownership.wordRole(annotations, word);
            if (role != .scalar and role != .reference) return self.fail(.instruction);
            if (body.instructions.items[at].operand == self.module.arena.?.allocate_scalar and role != .scalar) return self.fail(.instruction);
            self.objects.items[id].roles[word] = role;
        }
        for (self.module.table_origins.items) |origin| {
            if (origin.function != function or origin.kind == .unknown) continue;
            const fact = constructors.construction(self.module, origin) orelse return self.fail(.instruction);
            if (fact.allocation != at) continue;
            self.objects.items[id].site.kind = if (fact.kind == .demand) .memo else .closure;
            self.objects.items[id].producer = fact.target;
        }
        for (body.instructions.items, 0..) |inst, point| {
            if (inst.op != .ownership) continue;
            const marker: ir.Ownership = @bitCast(inst.operand);
            if (marker.kind != .rest or marker.chunk != providers.begin_chunk) continue;
            const fact = providers.constructor(self.module, body, point) orelse return self.fail(.instruction);
            if (fact.allocation != at) continue;
            if (fact.kind != 4) return self.fail(.instruction);
            self.objects.items[id].site.kind = .frame;
            self.objects.items[id].frame = fact;
        }
        return .{ .owners = @as(u64, 1) << @intCast(id), .constant = null };
    }
    fn stateAccess(self: *Graph, flow: *Flow, context_id: u32, function: u32, head: Value, mode: modes.Mode, input: Value, seen: u64) Error!Value {
        if (head.outside_head or head.owners == 0 or head.offset != 0) return self.fail(.receiver);
        var result: ?Value = null;
        var owners = head.owners;
        while (owners != 0) {
            const id: u6 = @intCast(@ctz(owners));
            const bit = @as(u64, 1) << id;
            owners &= owners - 1;
            if (seen & bit != 0) return self.fail(.receiver);
            const object_ = self.objects.items[id];
            const fact = object_.frame orelse return self.fail(.receiver);
            var value: Value = .{};
            if (mode.operation == fact.read or mode.operation == fact.write) {
                if (mode.access == .read) {
                    if (mode.operation != fact.read) return self.fail(.receiver);
                    value = try self.load(flow, .{ .owners = bit, .constant = null }, 4);
                } else {
                    if (mode.operation != fact.write) return self.fail(.receiver);
                    try self.store(flow, context_id, function, 48 + @as(u32, @intFromBool(mode.machine == .f32)), .{ .owners = bit, .constant = null }, 4, input);
                }
            } else value = try self.stateAccess(flow, context_id, function, try self.load(flow, .{ .owners = bit, .constant = null }, 8), mode, input, seen | bit);
            if (result) |*merged| _ = merged.merge(value) else result = value;
        }
        return result orelse self.fail(.receiver);
    }
    fn invoke(self: *Graph, parent: u32, at: u32, function: u32, arguments: []const Value, guard: @FieldType(State, "guard"), input_flow: Flow) Error![]Outcome {
        try self.spend(1);
        if (function >= self.module.functions.items.len or self.module.runtimeHelper(function) or self.active.items.len == 16) return self.fail(.instruction);
        for (self.active.items) |id| if (id == function) return self.fail(.recursion);
        const body = &self.module.functions.items[function];
        if (body.entry or arguments.len != body.parameters.len or arguments.len > 16) return self.fail(.boundary);
        for (arguments, 0..) |value, index| {
            const role = body.parameterRole(index);
            if (role != .scalar and role != .reference) return self.fail(.boundary);
            if (role == .scalar and value.reference()) return self.fail(.escape);
            if (value.outside_head and index != body.provider_parameter) return self.fail(.escape);
        }
        const context_id = try self.context(parent, at, function);
        if (body.provider_parameter < arguments.len) {
            const supplied = arguments[body.provider_parameter];
            self.contexts.items[context_id].provider |= supplied.owners;
            self.contexts.items[context_id].outside_provider = self.contexts.items[context_id].outside_provider or supplied.outside_head;
        }
        try self.active.append(self.a, function);
        defer _ = self.active.pop();
        var outcomes: std.ArrayList(Outcome) = .empty;
        errdefer outcomes.deinit(self.a);
        var flow = input_flow;
        if (modes.readOperation(&self.catalog, body)) |mode| {
            try outcomes.append(self.a, .{ .guard = guard, .value = try self.stateAccess(&flow, context_id, function, arguments[2], mode, .{}, 0), .flow = flow });
        } else if (modes.writeOperation(self.module, &self.catalog, body)) |mode| {
            try outcomes.append(self.a, .{ .guard = guard, .value = try self.stateAccess(&flow, context_id, function, arguments[2], mode, arguments[1], 0), .flow = flow });
        } else if (demands.force(self.module, function)) |fact| {
            if (fact.guard_global != null and self.guard_global != fact.guard_global) return self.fail(.control);
            var cells = arguments[fact.cell_parameter].owners;
            if (cells == 0 or arguments[fact.cell_parameter].outside_head or arguments[fact.cell_parameter].offset != 0) return self.fail(.receiver);
            while (cells != 0) {
                const id: usize = @intCast(@ctz(cells));
                cells &= cells - 1;
                const object_ = self.objects.items[id];
                if (object_.site.kind != .memo or object_.producer != fact.producer) return self.fail(.receiver);
                const bit = @as(u64, 1) << @intCast(id);
                if (flow.ready & bit != 0) {
                    try outcomes.append(self.a, .{ .guard = guard, .value = (flow.caches[id] orelse return self.fail(.receiver)).*, .flow = flow });
                    continue;
                }
                if (flow.evaluating & bit != 0) continue;
                var pending_flow = flow;
                pending_flow.evaluating |= bit;
                try self.recordCall(function, @intCast(fact.producer_call), fact.producer, false);
                self.objects.items[id].observed |= 1 << 1;
                const child = try self.invoke(context_id, @intCast(fact.producer_call), fact.producer, &.{ object_.words[1], .{}, arguments[fact.provider_parameter] }, guard, pending_flow);
                for (child) |outcome| {
                    var value = outcome.value;
                    var result_flow = outcome.flow;
                    result_flow.evaluating &= ~bit;
                    if (fact.guard_global != null and outcome.guard == .active) {
                        value = .{ .cancellation = true };
                    } else {
                        const mutable = &self.objects.items[id];
                        result_flow.ready |= bit;
                        result_flow.caches[id] = try self.freeze(value);
                        mutable.site.children |= value.owners;
                        try self.recordStore(context_id, function, @intCast(fact.cache_publication), @as(u64, 1) << @intCast(id), 12, value);
                    }
                    try outcomes.append(self.a, .{ .guard = outcome.guard, .value = value, .flow = result_flow });
                }
            }
        } else {
            outcomes = try self.scanBody(context_id, function, arguments, guard, flow);
        }
        return outcomes.items;
    }
    fn finishFrame(self: *Graph, state: *State, frame: Frame) Error!void {
        var result: Value = .{};
        if (frame.result) result = try state.pop();
        if (state.stack.items.len < frame.height) return self.fail(.control);
        state.stack.shrinkRetainingCapacity(frame.height);
        if (frame.result) try state.push(self.a, result);
    }
    fn branch(self: *Graph, state: *State, depth: u32, result: ir.ValueType, outcomes: *std.ArrayList(Outcome)) Error!bool {
        if (depth > state.frames.items.len) return self.fail(.control);
        if (depth == state.frames.items.len) {
            var value: Value = .{};
            if (result != .none) value = try state.pop();
            try outcomes.append(self.a, .{ .guard = state.guard, .value = value, .flow = state.flow });
            return false;
        }
        const index = state.frames.items.len - 1 - depth;
        const frame = state.frames.items[index];
        try self.finishFrame(state, frame);
        state.frames.shrinkRetainingCapacity(index);
        state.pc = frame.end + 1;
        return true;
    }
    fn constrain(self: *Graph, state: *State, value: Value, taken: bool) bool {
        if (value.constant) |constant| return (constant != 0) == taken;
        if (value.condition_global) {
            state.guard = if (taken) .active else .clear;
            if (!taken) {
                for (state.locals) |*local| local.cancellation = false;
                for (state.stack.items) |*local| local.cancellation = false;
            }
        }
        if (value.tag_test) |test_| {
            if (test_.local >= state.locals.len or state.versions[test_.local] != test_.version) return true;
            var mask: u64 = 0;
            var owners = state.locals[test_.local].owners;
            while (owners != 0) {
                const id: u6 = @intCast(@ctz(owners));
                owners &= owners - 1;
                self.objects.items[id].observed |= 1;
                const tag = self.objects.items[id].words[0].constant;
                if (tag == null or ((tag.? == test_.value) == test_.equal) == taken) mask |= @as(u64, 1) << id;
            }
            state.locals[test_.local].owners &= mask;
            if (state.locals[test_.local].owners == 0) return false;
        }
        return true;
    }
    fn scanBody(self: *Graph, context_id: u32, function: u32, arguments: []const Value, guard: @FieldType(State, "guard"), flow: Flow) Error!std.ArrayList(Outcome) {
        const source = &self.module.functions.items[function];
        const code = source.instructions.items;
        const count = std.math.add(usize, source.parameters.len, source.locals.items.len) catch return self.fail(.limit);
        if (count > 128 or code.len > 4096) return self.fail(.limit);
        const layout = try self.structure(function);
        const locals = try self.a.alloc(Value, count);
        @memset(locals, .{});
        @memcpy(locals[0..arguments.len], arguments);
        const versions = try self.a.alloc(u32, count);
        @memset(versions, 0);
        var pending: std.ArrayList(State) = .empty;
        defer pending.deinit(self.a);
        try pending.append(self.a, .{ .locals = locals, .versions = versions, .guard = guard, .flow = flow });
        var outcomes: std.ArrayList(Outcome) = .empty;
        var paths: usize = 0;
        while (pending.pop()) |input| {
            paths += 1;
            if (paths > 256) return self.fail(.limit);
            var state = input;
            var live = true;
            while (state.pc < code.len and live) {
                try self.spend(1);
                self.function = function;
                self.at = state.pc;
                const inst = code[state.pc];
                var next = true;
                switch (inst.op) {
                    .ownership, .nop => {},
                    .local_get => {
                        if (inst.operand >= count) return self.fail(.instruction);
                        var value = state.locals[inst.operand];
                        value.local = inst.operand;
                        value.version = state.versions[inst.operand];
                        try state.push(self.a, value);
                    },
                    .local_set, .local_tee => {
                        if (inst.operand >= count) return self.fail(.instruction);
                        var value = try state.pop();
                        const machine = if (inst.operand < source.parameters.len) source.parameters[inst.operand] else source.locals.items[inst.operand - source.parameters.len];
                        if (value.reference() and machine != .i32) return self.fail(.instruction);
                        value.local = null;
                        value.tag_field = false;
                        state.locals[inst.operand] = value;
                        state.versions[inst.operand] += 1;
                        if (inst.op == .local_tee) try state.push(self.a, value);
                    },
                    .i32_const => {
                        var value: Value = .{ .constant = inst.operand };
                        if (inst.table_reference) value = try self.target(inst.operand) else if (ir.hasImmortalReference(code, state.pc) or ir.staticConstructor(code, state.pc) != null) value = try self.staticObject(inst.operand);
                        try state.push(self.a, value);
                    },
                    .f32_const => try state.push(self.a, .{ .constant = inst.operand }),
                    .global_get => {
                        if (inst.operand >= self.module.globals.items.len or self.module.globals.items[inst.operand].scalar.role() == .reference) return self.fail(.escape);
                        var value: Value = .{ .constant = null };
                        if (self.guard_global == inst.operand) {
                            value.condition_global = true;
                            value.constant = switch (state.guard) {
                                .unknown => null,
                                .clear => 0,
                                .active => 1,
                            };
                        }
                        try state.push(self.a, value);
                    },
                    .i32_load, .f32_load => {
                        const value = try self.load(&state.flow, try state.pop(), inst.operand);
                        if (inst.op == .f32_load and value.reference()) return self.fail(.instruction);
                        try state.push(self.a, value);
                    },
                    .i32_store, .f32_store => {
                        const value = try state.pop();
                        if (inst.op == .f32_store and value.reference()) return self.fail(.instruction);
                        try self.store(&state.flow, context_id, function, state.pc, try state.pop(), inst.operand, value);
                    },
                    .i32_add, .i32_sub => {
                        var right = try state.pop();
                        var left = try state.pop();
                        if (right.reference() and inst.op == .i32_add) std.mem.swap(Value, &left, &right);
                        if (!left.reference() and right.reference()) return self.fail(.escape);
                        if (left.reference()) {
                            if (right.reference() or right.constant == null or left.offset == absent) return self.fail(.receiver);
                            left.offset = if (inst.op == .i32_add) std.math.add(u32, left.offset, right.constant.?) catch return self.fail(.receiver) else std.math.sub(u32, left.offset, right.constant.?) catch return self.fail(.receiver);
                            left.local = null;
                            try state.push(self.a, left);
                        } else {
                            var value: Value = .{ .constant = null };
                            if (left.constant != null and right.constant != null) value.constant = if (inst.op == .i32_add) left.constant.? +% right.constant.? else left.constant.? -% right.constant.?;
                            try state.push(self.a, value);
                        }
                    },
                    .i32_eq, .i32_ne, .i32_eqz => {
                        var right: Value = .{};
                        if (inst.op != .i32_eqz) right = try state.pop();
                        const left = try state.pop();
                        var value: Value = .{ .constant = null };
                        if (left.constant != null and right.constant != null) value.constant = @intFromBool((left.constant.? == right.constant.?) != (inst.op == .i32_ne));
                        if (left.tag_field and left.local != null and right.constant != null and inst.op != .i32_eqz) value.tag_test = .{ .local = left.local.?, .version = left.version, .value = right.constant.?, .equal = inst.op == .i32_eq };
                        try state.push(self.a, value);
                    },
                    .block, .if_ => {
                        var condition: Value = .{ .constant = 1 };
                        if (inst.op == .if_) condition = try state.pop();
                        const frame: Frame = .{ .end = layout.ends[state.pc], .alternate = layout.alternates[state.pc], .height = state.stack.items.len, .result = inst.operand != 0 and inst.operand != @backingInt(ir.ValueType.none) };
                        try state.frames.append(self.a, frame);
                        if (inst.op == .if_) {
                            var other = try state.clone(self.a);
                            errdefer other.deinit(self.a);
                            if (self.constrain(&other, condition, false)) {
                                if (frame.alternate != absent) other.pc = frame.alternate + 1 else {
                                    if (frame.result) return self.fail(.control);
                                    _ = other.frames.pop();
                                    other.pc = frame.end + 1;
                                }
                                try pending.append(self.a, other);
                            }
                            live = self.constrain(&state, condition, true);
                        }
                    },
                    .else_, .end => {
                        const frame = state.frames.pop() orelse return self.fail(.control);
                        try self.finishFrame(&state, frame);
                        if (inst.op == .else_) {
                            state.pc = frame.end + 1;
                            next = false;
                        }
                    },
                    .br, .br_if => {
                        if (inst.op == .br_if) {
                            const condition = try state.pop();
                            var taken = try state.clone(self.a);
                            errdefer taken.deinit(self.a);
                            if (self.constrain(&taken, condition, true) and try self.branch(&taken, inst.operand, source.result, &outcomes)) try pending.append(self.a, taken);
                            live = self.constrain(&state, condition, false);
                        } else {
                            live = try self.branch(&state, inst.operand, source.result, &outcomes);
                            next = false;
                        }
                    },
                    .return_ => {
                        var value: Value = .{};
                        if (source.result != .none) value = try state.pop();
                        if (source.result_role == .reference and value.constant == 0 and state.guard == .active) value.cancellation = true;
                        try outcomes.append(self.a, .{ .guard = state.guard, .value = value, .flow = state.flow });
                        live = false;
                    },
                    .unreachable_ => live = false,
                    .drop => _ = try state.pop(),
                    .call, .call_indirect => {
                        if ((inst.op == .call and inst.operand >= self.module.functions.items.len) or (inst.op == .call_indirect and inst.operand >= self.module.signatures.items.len)) return self.fail(.instruction);
                        var selector: Value = .{};
                        if (inst.op == .call_indirect) selector = try state.pop();
                        const signature = ir.call(self.module, inst);
                        if (signature.parameters.len > 16) return self.fail(.limit);
                        var args: [16]Value = undefined;
                        var count_args = signature.parameters.len;
                        while (count_args != 0) {
                            count_args -= 1;
                            args[count_args] = try state.pop();
                        }
                        const arena = self.module.arena.?;
                        if (inst.op == .call and arena.isAllocation(inst.operand)) {
                            if (signature.parameters.len != 1 or args[0].constant == null or args[0].reference()) return self.fail(.instruction);
                            try state.push(self.a, try self.allocation(&state.flow, context_id, function, state.pc, args[0].constant.?, if (source.provider_parameter < arguments.len) arguments[source.provider_parameter] else .{}));
                        } else if (inst.op == .call and inst.operand == arena.recycle) {
                            if (signature.parameters.len != 1 or args[0].outside_head or args[0].owners == 0 or args[0].offset != 0) return self.fail(.escape);
                            var owners = args[0].owners;
                            while (owners != 0) {
                                const id: usize = @intCast(@ctz(owners));
                                owners &= owners - 1;
                                if (self.objects.items[id].site.kind != .frame) return self.fail(.escape);
                            }
                        } else {
                            // invoke's immutable outcomes already live in this graph's arena.
                            // Only multiple indirect targets need a combined vector.
                            var combined: std.ArrayList(Outcome) = .empty;
                            var results: []const Outcome = undefined;
                            if (inst.op == .call) {
                                try self.recordCall(function, state.pc, inst.operand, false);
                                results = try self.invoke(context_id, state.pc, inst.operand, args[0..signature.parameters.len], state.guard, state.flow);
                            } else {
                                if (selector.codes == 0 or selector.reference() or selector.constant != null) return self.fail(.receiver);
                                var targets = selector.codes;
                                while (targets != 0) {
                                    const index: usize = @intCast(@ctz(targets));
                                    targets &= targets - 1;
                                    const target_id = self.targets.items[index];
                                    if (self.module.functions.items[target_id].signature != inst.operand) continue;
                                    try self.recordCall(function, state.pc, target_id, true);
                                    try combined.appendSlice(self.a, try self.invoke(context_id, state.pc, target_id, args[0..signature.parameters.len], state.guard, state.flow));
                                }
                                results = combined.items;
                            }
                            for (results) |outcome| {
                                var continuation = try state.clone(self.a);
                                continuation.pc += 1;
                                continuation.guard = outcome.guard;
                                continuation.flow = outcome.flow;
                                if (signature.result != .none) try continuation.push(self.a, outcome.value);
                                try pending.append(self.a, continuation);
                            }
                            live = false;
                        }
                    },
                    .call_import => return self.fail(.instruction),
                    else => {
                        const contract = ir.contract(self.module, source, inst);
                        if (contract.effect != .pure or contract.may_trap) return self.fail(.instruction);
                        for (0..contract.arity) |_| if ((try state.pop()).reference()) return self.fail(.escape);
                        if (contract.result != .none) try state.push(self.a, .{ .constant = null });
                    },
                }
                if (state.stack.items.len > 128 or state.frames.items.len > 64) return self.fail(.limit);
                if (next) state.pc += 1;
            }
            if (live) {
                if (state.frames.items.len != 0) return self.fail(.control);
                var value: Value = .{};
                if (source.result != .none) value = try state.pop();
                try outcomes.append(self.a, .{ .guard = state.guard, .value = value, .flow = state.flow });
            }
        }
        return outcomes;
    }
};

pub fn analyze(a: A, module: *const wasm.Module, boundary: u32) A.Error!Report {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const temp = scratch.allocator();
    const catalog = try modes.Catalog.initProtected(temp, module);
    const structures = try temp.alloc(?Structure, module.functions.items.len);
    @memset(structures, null);
    var graph: Graph = .{ .a = temp, .module = module, .catalog = catalog orelse .{}, .function = boundary, .structures = structures };
    var complete = false;
    if (module.arena != null and boundary < module.functions.items.len and module.resourceDrainImport() == null) admission: {
        const source = &module.functions.items[boundary];
        if (source.entry or source.result != .i32 or source.result_role != .scalar or source.parameters.len > 16 or !source.validProviderParameter()) break :admission;
        var args: [16]Value = undefined;
        for (source.parameters, 0..) |_, index| {
            if (index == source.provider_parameter) args[index] = .{ .outside_head = true, .constant = null } else {
                if (source.parameterRole(index) != .scalar) break :admission;
                args[index] = .{ .constant = null };
            }
        }
        if (catalog == null) break :admission;
        for (module.functions.items, 0..) |_, id| if (demands.force(module, @intCast(id))) |fact| {
            if (fact.guard_global == null) continue;
            if (graph.guard_global != null and graph.guard_global != fact.guard_global) break :admission;
            graph.guard_global = fact.guard_global;
        };
        for (0..32) |_| {
            graph.changed = false;
            for (graph.objects.items) |*object_| object_.observed = 0;
            const outcomes = graph.invoke(absent, absent, boundary, args[0..source.parameters.len], .unknown, .{}) catch |err| switch (err) {
                error.Unavailable => break :admission,
                error.OutOfMemory => return error.OutOfMemory,
            };
            for (outcomes) |outcome| if (outcome.value.reference()) {
                graph.blocker = .escape;
                break :admission;
            };
            if (!graph.changed) {
                complete = true;
                break;
            }
        }
    }
    if (!complete and graph.blocker == .none) graph.blocker = .boundary;
    if (complete) graph.incoming(boundary) catch |err| switch (err) {
        error.Unavailable => complete = false,
        error.OutOfMemory => return error.OutOfMemory,
    };
    const sites = try a.alloc(Site, graph.objects.items.len);
    errdefer a.free(sites);
    for (graph.objects.items, sites) |object_, *site| site.* = object_.site;
    const calls = try a.dupe(Call, graph.calls.items);
    errdefer a.free(calls);
    const contexts = try a.dupe(Context, graph.contexts.items);
    errdefer a.free(contexts);
    return .{ .sites = sites, .calls = calls, .contexts = contexts, .stores = try a.dupe(Store, graph.stores.items), .complete = complete, .blocker = graph.blocker, .function = graph.function, .at = graph.at, .work = graph.work };
}

pub const Cohort = struct {
    graph: Report,
    owner: u6,
    members: u64,
    pub fn deinit(self: *Cohort, a: A) void {
        self.graph.deinit(a);
    }
};
fn reachable(sites: []const Site, initial: u64) u64 {
    var seen = initial;
    for (0..max_sites) |_| {
        var pending = seen;
        var next = seen;
        while (pending != 0) {
            const id: u6 = @intCast(@ctz(pending));
            pending &= pending - 1;
            next |= sites[id].children;
        }
        if (next == seen) return seen;
        seen = next;
    }
    return seen;
}
/// Rederive the runtime half of one closed cohort. The independent owned Core
/// proof and exact generator-request intersection remain mandatory consumers.
/// No caller-supplied report or allocation flag participates in this check.
pub fn cohort(a: A, module: *const wasm.Module, boundary: u32) A.Error!?Cohort {
    var graph = try analyze(a, module, boundary);
    var transferred = false;
    defer if (!transferred) graph.deinit(a);
    if (!graph.complete or graph.contexts.len == 0) return null;
    var frame: ?u6 = null;
    var statics: u64 = 0;
    for (graph.sites, 0..) |site, id| {
        if (site.kind == .static_data) statics |= @as(u64, 1) << @intCast(id);
        if (site.kind != .frame) continue;
        // A directly allocated boundary owner outlives every descendant result
        // journal. Nested installation/returned-owner protocols decline.
        if (frame != null or site.function != boundary or site.context != 0) return null;
        frame = @intCast(id);
    }
    const owner_id = frame orelse return null;
    const owner_bit = @as(u64, 1) << owner_id;
    var members: u64 = 0;
    for (graph.sites, 0..) |site, id| {
        if (site.kind != .memo) continue;
        const bit = @as(u64, 1) << @intCast(id);
        var pending = reachable(graph.sites, bit);
        while (pending != 0) {
            const child: u6 = @intCast(@ctz(pending));
            pending &= pending - 1;
            if (reachable(graph.sites, @as(u64, 1) << child) & bit != 0) members |= @as(u64, 1) << child;
        }
    }
    if (@popCount(members) < 2 or members & (statics | owner_bit) != 0) return null;
    const internal = members | owner_bit | statics;
    var pending = members;
    while (pending != 0) {
        const id: u6 = @intCast(@ctz(pending));
        pending &= pending - 1;
        const site = graph.sites[id];
        if (site.context == 0 or site.provider != owner_bit or site.borrowed_head or site.children & ~internal != 0) return null;
        if (site.function >= module.functions.items.len or module.functions.items[site.function].provider_parameter >= module.functions.items[site.function].parameters.len) return null;
        var context_id = site.context;
        var enclosed = false;
        for (0..64) |_| {
            if (context_id >= graph.contexts.len) return null;
            const context_ = graph.contexts[context_id];
            if (context_id == 0) {
                enclosed = context_.parent == absent and context_.function == boundary;
                break;
            }
            context_id = context_.parent;
        }
        if (!enclosed) return null;
    }
    for (graph.stores) |store_| {
        const grouped_destination = store_.owners & members != 0 or (store_.owners & owner_bit != 0 and store_.offset == 4);
        if (grouped_destination) {
            if (store_.outside_value or store_.values & ~internal != 0) return null;
            if (store_.owners & ~(members | owner_bit) != 0) return null;
        } else if (store_.values & members != 0) return null;
    }
    transferred = true;
    return .{ .graph = graph, .owner = owner_id, .members = members };
}

fn immutableFlowSnapshots(a: A) !void {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    var module = wasm.Module.init(scratch.allocator());
    defer module.deinit();
    var graph: Graph = .{ .a = scratch.allocator(), .module = &module, .catalog = .{} };
    const first: Value = .{ .owners = 17, .codes = 8, .constant = null, .offset = 12, .outside_head = true, .cancellation = true, .local = 7, .version = 9, .tag_field = true, .tag_test = .{ .local = 6, .version = 4, .value = 3, .equal = true }, .condition_global = true };
    var original: Flow = .{};
    original.cells[3] = try graph.freeze(first);
    original.written |= 8;
    original.caches[5] = try graph.freeze(first);
    original.ready |= 32;
    original.evaluating = 64;
    const branch = original;
    original.cells[3] = try graph.freeze(.{ .owners = 2 });
    original.caches[5] = try graph.freeze(.{ .constant = 42 });
    original.written = 0;
    original.ready = 0;
    original.evaluating = 0;
    try std.testing.expectEqualDeep(first, branch.cells[3].?.*);
    try std.testing.expectEqualDeep(first, branch.caches[5].?.*);
    try std.testing.expectEqual(@as(u64, 8), branch.written);
    try std.testing.expectEqual(@as(u64, 32), branch.ready);
    try std.testing.expectEqual(@as(u64, 64), branch.evaluating);
    try std.testing.expect(branch.cells[3] != original.cells[3]);
    try std.testing.expect(branch.caches[5] != original.caches[5]);
}
test "activation flow snapshots preserve branch cells cache metadata and guards through OOM" {
    try immutableFlowSnapshots(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, immutableFlowSnapshots, .{});
}

fn observedHeap(a: A) !void {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const temp = scratch.allocator();
    var module = wasm.Module.init(temp);
    defer module.deinit();
    var graph: Graph = .{ .a = temp, .module = &module, .catalog = .{} };
    var flow: Flow = .{};
    const id = try graph.object(0, 0, 0, 8, .ordinary);
    graph.objects.items[id].roles[0] = .scalar;
    const address: Value = .{ .owners = 1, .constant = null };
    try graph.store(&flow, 0, 0, 1, address, 0, .{ .constant = 1 });
    try std.testing.expect(!graph.changed);
    try std.testing.expectEqual(@as(?u32, 1), (try graph.load(&flow, address, 0)).constant);
    try graph.store(&flow, 0, 0, 2, address, 0, .{ .constant = 2 });
    // A later heap alternative invalidates an earlier consumed tag.
    try std.testing.expect(graph.changed);
    try std.testing.expectEqual(@as(?u32, null), (try graph.load(&flow, address, 0)).constant);
    graph.changed = false;
    const state = try graph.object(0, 0, 3, 8, .frame);
    graph.objects.items[state].roles[1] = .scalar;
    graph.objects.items[state].frame = .{ .local = 0, .kind = 4, .value_role = .scalar, .value_machine = .i32, .read = 1, .write = 2, .allocation = 0, .end = 1 };
    const state_address: Value = .{ .owners = 2, .constant = null };
    try graph.store(&flow, 0, 0, 4, state_address, 4, .{ .constant = 1 });
    var earlier = flow;
    try graph.store(&flow, 0, 0, 5, state_address, 4, .{ .constant = 2 });
    // State reads consume the exact path snapshot, never the global union.
    try std.testing.expectEqual(@as(?u32, 1), (try graph.load(&earlier, state_address, 4)).constant);
    try std.testing.expectEqual(@as(?u32, 2), (try graph.load(&flow, state_address, 4)).constant);
    try std.testing.expect(!graph.changed);
}
test "activation graph revisits consumed heap alternatives and preserves exact State snapshots through OOM" {
    try observedHeap(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, observedHeap, .{});
}
