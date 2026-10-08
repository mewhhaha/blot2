//! Private, bounded startup occurrence evidence. This interpreter observes
//! immutable Core and completed Session values; it never evaluates a Session
//! binding or changes a demand memo. Unsupported flow declines the whole proof.
const std = @import("std");
const core = @import("core.zig");
const core_eval = @import("core_eval.zig");
const scalar_ops = @import("scalar_ops.zig");
const types = @import("types.zig");
const Allocator = std.mem.Allocator;

pub const Error = Allocator.Error || error{Incomplete};
pub const EdgeKind = enum { selected_call, runtime_read, retention };
pub const Edge = struct {
    root: core.BindingRef,
    target: core.BindingRef,
    weak: bool,
    kind: EdgeKind,
    unit: u32,
    node: core.Id,
};
pub const FactKind = enum { node, body_enter, body_complete, ready_witness, value_retained };
pub const Fact = struct {
    root: core.BindingRef,
    kind: FactKind,
    unit: u32,
    node: core.Id,
    weak: bool,
    identity: u32 = 0,
    value: core_eval.ValueId = 0,
};
pub const Result = struct {
    edges: []Edge,
    facts: []Fact,
    pub fn deinit(self: *Result, allocator: Allocator) void {
        allocator.free(self.edges);
        allocator.free(self.facts);
        self.* = undefined;
    }
};

const ValueId = u32;
const Provenance = enum { inherit, ready, waiting };
const Kind = enum { scalar, product, record, nominal, array, closure, suspension };
const Value = struct {
    kind: Kind = .scalar,
    scalar: core_eval.Value = .{ .scalar = .unit, .bits = 0 },
    known: bool = true,
    children: core.List = .{},
    fields: core.List = .{},
    nominal: types.NominalIdentity = .{ .unit = 0, .decl = 0 },
    tag: u32 = 0,
    closure: core_eval.ClosureValue = .{ .unit = 0, .identity = 0, .origin = .anonymous },
    actual: ?core_eval.ValueId = null,
    cached: ?core_eval.ValueId = null,
    provenance: Provenance = .inherit,
};
const Frame = struct {
    values: std.AutoHashMapUnmanaged(core.BindingId, ValueId) = .empty,
    possible_return: ?struct { target: core.Id, value: ValueId } = null,
    fn deinit(self: *Frame, a: Allocator) void {
        self.values.deinit(a);
    }
};
const Flow = union(enum) {
    value: ValueId,
    returning: struct { target: core.Id, value: ValueId },
};
const Expansion = struct { unit: u32, identity: u32, origin: core_eval.ClosureOrigin };
const Site = struct { owner: usize, node: core.Id };
const ScalarInterface = struct { parameter: ValueId, result: @TypeOf(@as(core_eval.Value, undefined).scalar) };
const max_steps = 100_000;
const max_depth = 128;
const max_values = 32_768;
const max_children = 131_072;

const Walk = struct {
    allocator: Allocator,
    units: []const core.Module,
    session: *core_eval.Session,
    root: core.BindingRef = .{ .binding = 0 },
    edges: std.ArrayList(Edge) = .empty,
    facts: std.ArrayList(Fact) = .empty,
    values: std.ArrayList(Value) = .empty,
    children: std.ArrayList(ValueId) = .empty,
    fields: std.ArrayList(u32) = .empty,
    constants: std.AutoHashMapUnmanaged(core.BindingRef, ValueId) = .empty,
    preparing: std.AutoHashMapUnmanaged(core.BindingRef, void) = .empty,
    replay_producer: ?core.BindingRef = null,
    expansions: std.ArrayList(Expansion) = .empty,
    steps: usize = 0,
    depth: usize = 0,

    fn deinit(self: *Walk) void {
        self.edges.deinit(self.allocator);
        self.facts.deinit(self.allocator);
        self.values.deinit(self.allocator);
        self.children.deinit(self.allocator);
        self.fields.deinit(self.allocator);
        self.constants.deinit(self.allocator);
        self.preparing.deinit(self.allocator);
        self.expansions.deinit(self.allocator);
    }
    fn charge(self: *Walk) Error!void {
        if (self.steps >= max_steps or self.depth >= max_depth) return error.Incomplete;
        self.steps += 1;
    }
    fn unitId(self: *const Walk, owner: usize) u32 {
        return if (self.units[owner].unit != 0) self.units[owner].unit else @intCast(owner + 1);
    }
    fn ownerOf(self: *const Walk, unit: u32, local: ?usize) Error!usize {
        if (unit == 0) {
            if (local) |owner| return owner;
            if (self.units.len == 1) return 0;
            return error.Incomplete;
        }
        for (self.units, 0..) |_, i| if (self.unitId(i) == unit) return i;
        return error.Incomplete;
    }
    fn normalize(self: *Walk, owner: ?usize, initial: core.BindingRef) Error!core.BindingRef {
        var target = initial;
        var local = owner;
        for (0..128) |_| {
            const producer = try self.ownerOf(target.unit, local);
            const module = &self.units[producer];
            if (target.binding == 0 or target.binding >= module.bindings.len) return error.Incomplete;
            const binding = module.binding(target.binding);
            if (binding.kind != .external) return .{ .unit = self.unitId(producer), .binding = target.binding };
            target = binding.target;
            local = producer;
        }
        return error.Incomplete;
    }
    fn emit(self: *Walk, site: Site, target: core.BindingRef, kind: EdgeKind, weak: bool, observe: bool) Error!void {
        if (!observe) return;
        try self.edges.append(self.allocator, .{ .root = self.root, .target = target, .weak = weak, .kind = kind, .unit = self.unitId(site.owner), .node = site.node });
    }
    fn fact(self: *Walk, site: Site, kind: FactKind, weak: bool, identity: u32, actual: ?core_eval.ValueId, observe: bool) Error!void {
        if (!observe) return;
        try self.facts.append(self.allocator, .{ .root = self.root, .kind = kind, .unit = self.unitId(site.owner), .node = site.node, .weak = weak, .identity = identity, .value = actual orelse 0 });
    }
    fn add(self: *Walk, value: Value) Error!ValueId {
        if (self.values.items.len >= max_values) return error.Incomplete;
        const id: ValueId = @intCast(self.values.items.len);
        try self.values.append(self.allocator, value);
        return id;
    }
    fn aggregate(self: *Walk, value_: Value, children_: []const ValueId, fields_: []const u32) Error!ValueId {
        if (children_.len > max_children -| self.children.items.len or fields_.len > max_children -| self.fields.items.len) return error.Incomplete;
        var value = value_;
        value.children = .{ .start = @intCast(self.children.items.len), .len = @intCast(children_.len) };
        value.fields = .{ .start = @intCast(self.fields.items.len), .len = @intCast(fields_.len) };
        try self.children.appendSlice(self.allocator, children_);
        try self.fields.appendSlice(self.allocator, fields_);
        return self.add(value);
    }
    fn mode(value: Value, inherited: bool) bool {
        return switch (value.provenance) {
            .inherit => inherited,
            .ready => true,
            .waiting => false,
        };
    }
    fn boundary(self: *Walk, id: ValueId, provenance: Provenance) Error!ValueId {
        var value = self.values.items[id];
        value.provenance = provenance;
        return self.add(value);
    }
    fn context(self: *Walk, id: ValueId, weak: bool) Error!ValueId {
        if (!weak or self.values.items[id].provenance != .inherit) return id;
        return self.boundary(id, .ready);
    }
    fn scalarType(self: *Walk, owner: usize, ty: types.Id, known: bool, bits: u32) Error!ValueId {
        const module = &self.units[owner];
        if (ty >= module.types.nodes.len) return error.Incomplete;
        const scalar_kind: @TypeOf(@as(core_eval.Value, undefined).scalar) = switch (module.types.node(ty).tag) {
            .unit => .unit,
            .boolean => .bool,
            .u32 => .u32,
            .f32 => .f32,
            else => return error.Incomplete,
        };
        return self.add(.{ .scalar = .{ .scalar = scalar_kind, .bits = bits }, .known = known or scalar_kind == .unit });
    }
    fn placeholder(self: *Walk, owner: usize, ty: types.Id) Error!ValueId {
        return self.scalarType(owner, ty, false, 0);
    }
    fn body(self: *Walk, target: core.BindingRef) Error!*const core.Body {
        const owner = try self.ownerOf(target.unit, null);
        const module = &self.units[owner];
        const binding = module.binding(target.binding);
        if (binding.body_id == 0 or binding.body_id >= module.bodies.len) return error.Incomplete;
        return &module.bodies[binding.body_id];
    }
    fn named(self: *Walk, target: core.BindingRef) Error!ValueId {
        return self.add(.{ .kind = .closure, .closure = .{ .unit = target.unit, .identity = target.binding, .origin = .named } });
    }

    /// Replay the producer only to recover provenance. Completed immutable
    /// values certify its exact captures and ready state. Producer evaluation
    /// itself creates no runtime occurrence facts.
    fn constant(self: *Walk, target: core.BindingRef) Error!ValueId {
        if (self.constants.get(target)) |value| return value;
        if (self.preparing.contains(target)) return error.Incomplete;
        const owner = try self.ownerOf(target.unit, null);
        const declaration = try self.body(target);
        if (declaration.runtime) return error.Incomplete;
        const cached = self.session.cachedBindingValue(target) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.Incomplete,
        };
        if (declaration.is_function) {
            const value = try self.named(target);
            const result = if (cached) |actual| try self.alignActual(actual, value) else value;
            try self.constants.put(self.allocator, target, result);
            return result;
        }
        const actual = cached orelse return error.Incomplete;
        try self.preparing.put(self.allocator, target, {});
        defer _ = self.preparing.remove(target);
        const previous_producer = self.replay_producer;
        self.replay_producer = target;
        defer self.replay_producer = previous_producer;
        var frame: Frame = .{};
        defer frame.deinit(self.allocator);
        const result = try self.expression(owner, declaration.root, &frame, false, false);
        if (result != .value) return error.Incomplete;
        const value = try self.alignActual(actual, result.value);
        try self.constants.put(self.allocator, target, value);
        return value;
    }
    fn alignActual(self: *Walk, actual: core_eval.ValueId, symbolic: ValueId) Error!ValueId {
        try self.charge();
        self.depth += 1;
        defer self.depth -= 1;
        if (actual >= self.session.values.items.len) return error.Incomplete;
        const info = self.session.valueInfo(actual);
        var value = self.values.items[symbolic];
        const kind: Kind = switch (info.kind) {
            .scalar => .scalar,
            .product => .product,
            .record => .record,
            .nominal => .nominal,
            .array, .list => .array,
            .closure => .closure,
            .suspension => .suspension,
            else => return error.Incomplete,
        };
        if (kind != value.kind or info.len != value.children.len) return error.Incomplete;
        if (kind == .scalar) {
            if (!value.known or value.scalar.scalar != info.scalar or value.scalar.bits != info.bits) return error.Incomplete;
        } else if (kind == .closure or kind == .suspension) {
            const metadata = self.session.closureInfo(actual);
            const source = value.closure;
            if (metadata.origin != source.origin or metadata.unit != source.unit or metadata.identity != source.identity or metadata.applied != source.applied) return error.Incomplete;
            value.closure = metadata;
            if (kind == .suspension) value.cached = self.session.suspensionCached(actual);
        } else if (kind == .nominal) {
            if (value.nominal.unit != @as(u32, @truncate(info.nominal >> 32)) or value.nominal.decl != @as(u32, @truncate(info.nominal)) or value.tag != info.bits) return error.Incomplete;
        }
        const children_ = try self.allocator.alloc(ValueId, info.len);
        defer self.allocator.free(children_);
        for (children_, 0..) |*child, i| {
            const supplied = self.session.children.items[info.start + i];
            const previous = self.children.items[value.children.start + i];
            child.* = try self.alignActual(supplied, previous);
        }
        const fields_ = try self.allocator.alloc(u32, value.fields.len);
        defer self.allocator.free(fields_);
        @memcpy(fields_, self.fields.items[value.fields.start..][0..value.fields.len]);
        if (kind == .record) {
            if (actual >= self.session.value_records.items.len) return error.Incomplete;
            const layout_id = self.session.value_records.items[actual];
            if (layout_id >= self.session.record_layouts.items.len) return error.Incomplete;
            const layout = self.session.record_layouts.items[layout_id];
            if (layout.len != fields_.len or !std.mem.eql(u32, self.session.field_names.items[layout.start..][0..layout.len], fields_)) return error.Incomplete;
        }
        value.actual = actual;
        return self.aggregate(value, children_, fields_);
    }

    fn enter(self: *Walk, metadata: core_eval.ClosureValue) Error!void {
        const key: Expansion = .{ .unit = metadata.unit, .identity = metadata.identity, .origin = metadata.origin };
        for (self.expansions.items) |active| if (std.meta.eql(active, key)) return error.Incomplete;
        if (self.expansions.items.len >= max_depth) return error.Incomplete;
        try self.expansions.append(self.allocator, key);
    }
    fn invoke(self: *Walk, function: ValueId, arguments: []const ValueId, site: Site, inherited: bool, observe: bool, retention: bool) Error!ValueId {
        return self.invokeScalarInterface(function, arguments, site, inherited, observe, retention, null);
    }
    fn invokeScalarInterface(self: *Walk, function: ValueId, arguments: []const ValueId, site: Site, inherited: bool, observe: bool, retention: bool, expected: ?ScalarInterface) Error!ValueId {
        try self.charge();
        const value = self.values.items[function];
        if (value.kind != .closure and value.kind != .suspension) return error.Incomplete;
        const weak = mode(value, inherited);
        const metadata = value.closure;
        const owner = try self.ownerOf(metadata.unit, null);
        const module = &self.units[owner];
        switch (metadata.origin) {
            .operation => return error.Incomplete,
            .primitive => {
                if (metadata.identity >= module.primitives.len) return error.Incomplete;
                const primitive = module.primitives[metadata.identity];
                if (metadata.applied != value.children.len or metadata.applied > primitive.arity or arguments.len > primitive.arity - metadata.applied) return error.Incomplete;
                const count = std.math.add(usize, value.children.len, arguments.len) catch return error.Incomplete;
                const supplied = try self.allocator.alloc(ValueId, count);
                defer self.allocator.free(supplied);
                @memcpy(supplied[0..value.children.len], self.children.items[value.children.start..][0..value.children.len]);
                @memcpy(supplied[value.children.len..], arguments);
                if (count != primitive.arity) {
                    var partial = value;
                    partial.closure.applied = @intCast(count);
                    partial.actual = null;
                    return self.aggregate(partial, supplied, &.{});
                }
                return if (primitive.kind == .array) self.arrayValues(primitive.array_op, supplied, site, weak, observe) else self.scalar(primitive.op, supplied[0], if (count == 1) 0 else supplied[1]);
            },
            .constructor => {
                if (metadata.applied != 0 or arguments.len != 1 or metadata.identity >= module.constructors.len) return error.Incomplete;
                return self.construct(owner, metadata.identity, arguments[0], true);
            },
            .named, .anonymous => {},
        }
        var frame: Frame = .{};
        defer frame.deinit(self.allocator);
        var body_root: core.Id = undefined;
        if (metadata.origin == .named) {
            const target = try self.normalize(null, .{ .unit = metadata.unit, .binding = metadata.identity });
            if (target.unit != metadata.unit or target.binding != metadata.identity) return error.Incomplete;
            const declaration = try self.body(target);
            if (!declaration.is_function) return error.Incomplete;
            const parameters = module.bodyParameters(declaration);
            if (metadata.applied != value.children.len or metadata.applied > parameters.len or arguments.len > parameters.len - metadata.applied) return error.Incomplete;
            const count = std.math.add(usize, value.children.len, arguments.len) catch return error.Incomplete;
            if (expected != null and (!retention or parameters.len - count != 1)) return error.Incomplete;
            if (count < parameters.len and !retention) {
                const supplied = try self.allocator.alloc(ValueId, count);
                defer self.allocator.free(supplied);
                @memcpy(supplied[0..value.children.len], self.children.items[value.children.start..][0..value.children.len]);
                @memcpy(supplied[value.children.len..], arguments);
                var partial = value;
                partial.closure.applied = @intCast(count);
                partial.actual = null;
                return self.context(try self.aggregate(partial, supplied, &.{}), weak);
            }
            for (parameters, 0..) |parameter, i| {
                const bound = if (i < value.children.len) self.children.items[value.children.start + i] else if (i < count) arguments[i - value.children.len] else if (expected) |selected| try self.interfaceParameter(owner, parameter.ty, selected.parameter) else try self.placeholder(owner, parameter.ty);
                try frame.values.put(self.allocator, parameter.binding, bound);
            }
            body_root = declaration.root;
            try self.emit(site, target, if (retention) .retention else .selected_call, weak, observe);
        } else {
            if (metadata.identity >= module.closures.len or metadata.applied != 0 or arguments.len > 1) return error.Incomplete;
            const template = module.closures[metadata.identity];
            if (template.captures.len != value.children.len) return error.Incomplete;
            for (module.extra[template.captures.start..][0..template.captures.len], 0..) |binding, i| try frame.values.put(self.allocator, binding, self.children.items[value.children.start + i]);
            const parameter = if (arguments.len == 1) arguments[0] else if (retention) if (expected) |selected| try self.interfaceParameter(owner, template.parameter.ty, selected.parameter) else try self.placeholder(owner, template.parameter.ty) else return error.Incomplete;
            if (template.parameter.binding != 0) try frame.values.put(self.allocator, template.parameter.binding, parameter);
            body_root = template.body;
        }
        try self.enter(metadata);
        defer _ = self.expansions.pop();
        const body_site: Site = .{ .owner = owner, .node = body_root };
        try self.fact(body_site, .body_enter, weak, metadata.identity, value.actual, observe);
        const outcome = try self.expression(owner, body_root, &frame, weak, observe);
        if (outcome != .value or frame.possible_return != null) return error.Incomplete;
        if (expected) |selected| {
            const result = self.values.items[outcome.value];
            if (result.kind != .scalar or result.scalar.scalar != selected.result) return error.Incomplete;
        }
        try self.fact(body_site, .body_complete, weak, metadata.identity, value.actual, observe);
        return self.context(outcome.value, weak);
    }

    fn force(self: *Walk, demand: ValueId, site: Site, observe: bool) Error!ValueId {
        const value = self.values.items[demand];
        if (value.kind != .suspension) return error.Incomplete;
        if (!observe and self.replay_producer != null and value.actual == null) return error.Incomplete;
        // Source replay recovers the cached result's exact bound value flow;
        // the old computation is not an occurrence in the ready use region.
        const ready = value.cached != null;
        const strong_demand = try self.boundary(demand, .waiting);
        const result = try self.invoke(strong_demand, &.{0}, site, false, if (ready) false else observe, false);
        if (value.cached) |actual| {
            const aligned = try self.alignActual(actual, result);
            try self.fact(site, .ready_witness, true, value.closure.identity, value.actual, observe);
            return self.boundary(aligned, .ready);
        }
        // Waiting execution resets the region, while a returned operand can
        // independently own a complete cached-result witness. Preserve only
        // that explicit boundary; inherited fresh results stay strong.
        return if (self.values.items[result].provenance == .ready) result else self.boundary(result, .waiting);
    }
    fn retain(self: *Walk, id: ValueId, site: Site, inherited: bool, observe: bool) Error!void {
        return self.retainScalarInterface(id, site, inherited, observe, null);
    }
    fn retainScalarInterface(self: *Walk, id: ValueId, site: Site, inherited: bool, observe: bool, expected: ?ScalarInterface) Error!void {
        if (!observe) return;
        try self.charge();
        self.depth += 1;
        defer self.depth -= 1;
        const value = self.values.items[id];
        const weak = mode(value, inherited);
        try self.fact(site, .value_retained, weak, value.closure.identity, value.actual, true);
        switch (value.kind) {
            .scalar => {},
            .product, .record, .nominal, .array => for (0..value.children.len) |i| try self.retain(self.children.items[value.children.start + i], site, weak, true),
            .suspension => {
                const result = try self.force(id, site, true);
                try self.retain(result, site, value.cached != null, true);
            },
            .closure => {
                if (value.closure.origin == .primitive or value.closure.origin == .constructor) {
                    for (0..value.children.len) |i| try self.retain(self.children.items[value.children.start + i], site, weak, true);
                    return;
                }
                const result = try self.invokeScalarInterface(id, &.{}, site, weak, true, true, expected);
                try self.retain(result, site, weak, true);
            },
        }
    }

    /// A concrete current declaration supplies the domain of the retained
    /// occurrence; it never certifies a body or a read. The complete body is
    /// still walked with an unknown scalar, and unsupported flow declines.
    fn scalarInterface(self: *Walk, owner: usize, ty: types.Id) Error!?ScalarInterface {
        const module = &self.units[owner];
        if (ty >= module.types.nodes.len) return error.Incomplete;
        const node = module.types.node(ty);
        if (node.tag != .function) return null;
        const parameter = self.placeholder(owner, node.a) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Incomplete => return null,
        };
        const result = self.placeholder(owner, node.b) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Incomplete => return null,
        };
        return .{ .parameter = parameter, .result = self.values.items[result].scalar.scalar };
    }
    fn interfaceParameter(self: *Walk, owner: usize, source: types.Id, selected: ValueId) Error!ValueId {
        const module = &self.units[owner];
        if (source >= module.types.nodes.len) return error.Incomplete;
        if (module.types.node(source).tag != .variable) {
            const ordinary = try self.placeholder(owner, source);
            if (self.values.items[ordinary].scalar.scalar != self.values.items[selected].scalar.scalar) return error.Incomplete;
        }
        return selected;
    }

    fn scalar(self: *Walk, op: core.Op, first: ValueId, second: ValueId) Error!ValueId {
        const left = self.values.items[first];
        const right = self.values.items[second];
        if (left.kind != .scalar or right.kind != .scalar or scalar_ops.opcode(op, left.scalar.scalar) == null) return error.Incomplete;
        if (left.known and right.known) {
            const result = scalar_ops.evaluate(op, left.scalar, right.scalar) catch return error.Incomplete;
            return self.add(.{ .scalar = result });
        }
        var result = left;
        result.known = false;
        result.scalar.scalar = switch (op) {
            .equal, .not_equal, .less, .less_equal, .greater, .greater_equal => .bool,
            .convert_u32_f32 => .f32,
            .convert_f32_u32 => .u32,
            else => left.scalar.scalar,
        };
        return self.add(result);
    }
    fn dispatchedScalar(self: *Walk, owner: usize, node: core.Id, op: core.Op, member: u32, left: ValueId, right: ValueId, weak: bool, observe: bool) Error!ValueId {
        const l = self.values.items[left];
        const r = self.values.items[right];
        if (l.kind != .scalar or r.kind != .scalar or l.scalar.scalar != r.scalar.scalar) return error.Incomplete;
        const identity: types.NominalIdentity = .{ .unit = 0, .decl = switch (l.scalar.scalar) {
            .unit => types.unit,
            .bool => types.boolean,
            .u32 => types.u32_type,
            .f32 => types.f32_type,
            else => return error.Incomplete,
        } };
        const operation: types.Operator = switch (op) {
            .add => .add,
            .sub => .sub,
            .mul => .mul,
            .div => .div,
            .rem => .rem,
            .equal => .equal,
            .not_equal => .not_equal,
            .less => .less,
            .less_equal => .less_equal,
            .greater => .greater,
            .greater_equal => .greater_equal,
            .bit_and => .bit_and,
            .bit_or => .bit_or,
            .bit_xor => .bit_xor,
            .shift_left => .shift_left,
            .shift_right => .shift_right,
            .none => if (member != 0) .none else return error.Incomplete,
            else => return error.Incomplete,
        };
        // Scalar methods are selected from the caller's catalog, exactly as
        // ordinary associatedTarget does for a scalar owner. Unknown parameter
        // admission never falls through to a builtin or a guessed method.
        for (self.units[owner].associated) |candidate| {
            if ((if (member != 0) candidate.member != member else candidate.operator != operation) or !std.meta.eql(candidate.identity, identity)) continue;
            const target = try self.normalize(owner, candidate.target);
            const producer = try self.ownerOf(target.unit, null);
            const declaration = try self.body(target);
            if (!declaration.is_function or declaration.scheme.obligations.len != 0) return error.Incomplete;
            const parameters = self.units[producer].bodyParameters(declaration);
            if (parameters.len != 2) return error.Incomplete;
            for (parameters) |parameter| {
                const ty = self.units[producer].types.node(parameter.ty).tag;
                const admitted = switch (l.scalar.scalar) {
                    .unit => ty == .unit,
                    .bool => ty == .boolean,
                    .u32 => ty == .u32,
                    .f32 => ty == .f32,
                    else => false,
                };
                if (!admitted) return error.Incomplete;
            }
            return self.invoke(try self.named(target), &.{ left, right }, .{ .owner = owner, .node = node }, weak, observe, false);
        }
        if (member != 0) return error.Incomplete;
        return self.scalar(op, left, right);
    }
    fn copyFrame(self: *Walk, frame: *const Frame) Error!Frame {
        var result: Frame = .{ .possible_return = frame.possible_return };
        errdefer result.deinit(self.allocator);
        var entries = frame.values.iterator();
        while (entries.next()) |entry| try result.values.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
        return result;
    }
    fn join(self: *Walk, left: ValueId, right: ValueId) Error!ValueId {
        if (left == right) return left;
        var l = self.values.items[left];
        const r = self.values.items[right];
        if (l.kind != .scalar or r.kind != .scalar or l.scalar.scalar != r.scalar.scalar) return error.Incomplete;
        if (!l.known or !r.known or l.scalar.bits != r.scalar.bits) l.known = false;
        if (l.actual != r.actual) l.actual = null;
        if (l.provenance != r.provenance) l.provenance = .waiting;
        return self.add(l);
    }
    const Match = enum { yes, no, unknown };
    fn pattern(self: *Walk, owner: usize, id: core.PatternId, input: ValueId, frame: *Frame, weak: bool, observe: bool) Error!Match {
        try self.charge();
        self.depth += 1;
        defer self.depth -= 1;
        const module = &self.units[owner];
        if (id == 0 or id >= module.patterns.len) return error.Incomplete;
        const p = module.pattern(id);
        const value = self.values.items[input];
        switch (p.tag) {
            .wildcard => return .yes,
            .bind => {
                if (p.a != 0) try frame.values.put(self.allocator, p.a, input);
                return .yes;
            },
            .constant, .value => {
                const expected = if (p.tag == .constant) try self.scalarType(owner, p.ty, true, p.a) else blk: {
                    const result = try self.expression(owner, p.a, frame, weak, observe);
                    if (result != .value) return error.Incomplete;
                    break :blk result.value;
                };
                const other = self.values.items[expected];
                if (value.kind != .scalar or other.kind != .scalar or value.scalar.scalar != other.scalar.scalar) return .no;
                if (value.scalar.scalar != .unit and value.scalar.scalar != .u32 and value.scalar.scalar != .bool) return error.Incomplete;
                if (!value.known or !other.known) return .unknown;
                return if (value.scalar.bits == other.scalar.bits) .yes else .no;
            },
            .product => {
                const parts = module.patternChildren(id);
                if ((value.kind != .product and value.kind != .record) or value.children.len != parts.len) return error.Incomplete;
                var result: Match = .yes;
                for (parts, 0..) |part, i| {
                    const matched = try self.pattern(owner, part, self.children.items[value.children.start + i], frame, weak, observe);
                    if (matched == .no) result = .no else if (matched == .unknown and result != .no) result = .unknown;
                }
                return result;
            },
            .constructor => {
                if (p.a >= module.constructors.len) return error.Incomplete;
                const constructor = module.constructor(p.a);
                var identity = module.nominal(constructor.nominal).identity;
                if (identity.unit == 0) identity.unit = self.unitId(owner);
                if (value.kind != .nominal or !std.meta.eql(value.nominal, identity) or value.tag != constructor.tag) return error.Incomplete;
                if (p.b == 0) return if (value.children.len == 0) .yes else .no;
                if (value.children.len != 1) return error.Incomplete;
                return self.pattern(owner, p.b, self.children.items[value.children.start], frame, weak, observe);
            },
            .record_payload => {
                if (value.kind != .record or value.children.len != p.a or value.fields.len != p.a or p.a == 0) return error.Incomplete;
                const declared = module.types.node(p.ty);
                if (declared.tag != .record or declared.b != p.a) return error.Incomplete;
                for (0..p.a) |i| if (self.fields.items[value.fields.start + i] != module.types.recordField(declared, i).name) return error.Incomplete;
                const parts = try self.allocator.dupe(ValueId, self.children.items[value.children.start..][0..value.children.len]);
                defer self.allocator.free(parts);
                const canonical = if (p.a == 1) parts[0] else try self.aggregate(.{ .kind = .product }, parts, &.{});
                return self.pattern(owner, p.b, canonical, frame, weak, observe);
            },
            else => return error.Incomplete,
        }
    }
    fn joinFlow(self: *Walk, previous: Flow, next: Flow) Error!Flow {
        if (previous == .value and next == .value) return .{ .value = try self.join(previous.value, next.value) };
        if (previous == .returning and next == .returning and previous.returning.target == next.returning.target) return .{ .returning = .{ .target = previous.returning.target, .value = try self.join(previous.returning.value, next.returning.value) } };
        return error.Incomplete;
    }
    fn match(self: *Walk, owner: usize, id: core.Id, frame: *Frame, weak: bool, observe: bool) Error!Flow {
        const module = &self.units[owner];
        const inputs = module.matchInputs(id);
        const supplied = try self.allocator.alloc(ValueId, inputs.len);
        defer self.allocator.free(supplied);
        for (inputs, 0..) |input, i| {
            const outcome = try self.expression(owner, input, frame, weak, observe);
            if (outcome != .value) return outcome;
            supplied[i] = outcome.value;
        }
        var selected: ?Flow = null;
        var settled = false;
        for (module.matchArms(id)) |arm| {
            for (module.armRows(arm)) |row| {
                var branch = try self.copyFrame(frame);
                defer branch.deinit(self.allocator);
                const patterns = module.rowPatterns(row);
                if (patterns.len != supplied.len) return error.Incomplete;
                var matched: Match = .yes;
                for (patterns, supplied) |p, value| {
                    const result = try self.pattern(owner, p, value, &branch, weak, observe);
                    if (result == .no) matched = .no else if (result == .unknown and matched != .no) matched = .unknown;
                }
                if (arm.guard != 0) {
                    const result = try self.expression(owner, arm.guard, &branch, weak, observe);
                    if (result != .value) return error.Incomplete;
                    const guard = self.values.items[result.value];
                    if (guard.kind != .scalar or guard.scalar.scalar != .bool) return error.Incomplete;
                    if (guard.known and guard.scalar.bits == 0) matched = .no else if (!guard.known and matched != .no) matched = .unknown;
                }
                if (!observe and (settled or matched == .no)) continue;
                const outcome = try self.expression(owner, arm.body, &branch, weak, observe);
                if (!std.meta.eql(branch.possible_return, frame.possible_return)) return error.Incomplete;
                if (!settled and matched != .no) {
                    if (!observe and matched == .unknown) return error.Incomplete;
                    selected = if (selected) |previous| try self.joinFlow(previous, outcome) else outcome;
                    if (matched == .yes) settled = true;
                }
            }
        }
        return selected orelse error.Incomplete;
    }
    fn arrayValues(self: *Walk, operation: core.ArrayOp, arguments: []const ValueId, site: Site, weak: bool, observe: bool) Error!ValueId {
        const arity = @import("collection_ops.zig").arity(operation);
        if (arguments.len != arity) return error.Incomplete;
        // Aggregate emission retains every waiting computation, even when
        // length/get does not force an element at runtime.
        for (arguments) |argument| try self.retain(argument, site, weak, observe);
        if (operation == .identity) return arguments[0];
        if (operation != .length and operation != .get and operation != .set) return error.Incomplete;
        const array = self.values.items[arguments[0]];
        if (array.kind != .array) return error.Incomplete;
        if (operation == .length) return self.add(.{ .scalar = .{ .scalar = .u32, .bits = array.children.len } });
        const index = self.values.items[arguments[1]];
        if (index.kind != .scalar or !index.known or index.scalar.scalar != .u32 or index.scalar.bits >= array.children.len) return error.Incomplete;
        if (operation == .get) return self.context(self.children.items[array.children.start + index.scalar.bits], mode(array, weak));
        const children_ = try self.allocator.alloc(ValueId, array.children.len);
        defer self.allocator.free(children_);
        @memcpy(children_, self.children.items[array.children.start..][0..array.children.len]);
        children_[index.scalar.bits] = arguments[2];
        var updated = array;
        updated.actual = null;
        return self.aggregate(updated, children_, &.{});
    }
    fn construct(self: *Walk, owner: usize, catalog: u32, argument: ?ValueId, canonical: bool) Error!ValueId {
        const module = &self.units[owner];
        if (catalog >= module.constructors.len) return error.Incomplete;
        const constructor = module.constructor(catalog);
        if (constructor.nominal >= module.nominals.len) return error.Incomplete;
        var identity = module.nominal(constructor.nominal).identity;
        if (identity.unit == 0) identity.unit = self.unitId(owner);
        var payload = argument;
        if (canonical) {
            if (argument == null or constructor.payload >= module.types.nodes.len) return error.Incomplete;
            const record = module.types.node(constructor.payload);
            if (record.tag == .record) {
                const children_ = try self.allocator.alloc(ValueId, record.b);
                defer self.allocator.free(children_);
                const fields_ = try self.allocator.alloc(u32, record.b);
                defer self.allocator.free(fields_);
                const supplied = self.values.items[argument.?];
                if (record.b == 1) children_[0] = argument.? else {
                    if (supplied.kind != .product or supplied.children.len != record.b) return error.Incomplete;
                    @memcpy(children_, self.children.items[supplied.children.start..][0..supplied.children.len]);
                }
                for (fields_, 0..) |*field, i| field.* = module.types.recordField(record, i).name;
                payload = try self.aggregate(.{ .kind = .record }, children_, fields_);
            }
        }
        return self.aggregate(.{ .kind = .nominal, .nominal = identity, .tag = constructor.tag }, if (payload) |p| &.{p} else &.{}, &.{});
    }
    fn physicalField(self: *Walk, id: ValueId, field: u32) ?ValueId {
        const value = self.values.items[id];
        if (value.kind == .record) {
            for (0..value.fields.len) |i| if (self.fields.items[value.fields.start + i] == field) return self.children.items[value.children.start + i];
            return null;
        }
        if (value.kind == .nominal and value.children.len == 1) {
            const payload = self.children.items[value.children.start];
            if (self.values.items[payload].kind == .record) return self.physicalField(payload, field);
        }
        return null;
    }
    fn project(self: *Walk, owner: usize, node: core.Id, catalog: u32, receiver: ValueId, weak: bool, observe: bool) Error!ValueId {
        const module = &self.units[owner];
        if (catalog >= module.projections.len) return error.Incomplete;
        const projection = module.projection(catalog);
        const value = self.values.items[receiver];
        const effective = mode(value, weak);
        if (projection.variants.len != 0) {
            const variants = module.projectionVariants(catalog);
            var container = receiver;
            var selected: ?u32 = null;
            if (value.kind == .nominal) {
                const unit = if (projection.nominal.unit == 0) self.unitId(owner) else projection.nominal.unit;
                if (value.nominal.unit != unit or value.nominal.decl != projection.nominal.decl or value.children.len != 1) return error.Incomplete;
                for (variants) |variant| if (variant.tag == value.tag) {
                    selected = variant.field;
                    break;
                };
                container = self.children.items[value.children.start];
            } else {
                if (projection.nominal.decl != 0 or variants.len != 1) return error.Incomplete;
                selected = variants[0].field;
            }
            const storage = self.values.items[container];
            const index = selected orelse return error.Incomplete;
            if ((storage.kind != .product and storage.kind != .record) or index >= storage.children.len) return error.Incomplete;
            return self.context(self.children.items[storage.children.start + index], effective);
        }
        if (self.physicalField(receiver, projection.field)) |field| return self.context(field, effective);
        if (value.kind != .nominal) return error.Incomplete;
        var target: ?core.BindingRef = null;
        for (self.units, 0..) |producer, producer_owner| for (producer.associated) |candidate| {
            const identity_unit = if (candidate.identity.unit == 0) self.unitId(producer_owner) else candidate.identity.unit;
            if (candidate.member != projection.field or candidate.operator != .none or identity_unit != value.nominal.unit or candidate.identity.decl != value.nominal.decl) continue;
            const actual = try self.normalize(producer_owner, candidate.target);
            if (target) |previous| {
                if (!std.meta.eql(previous, actual)) return error.Incomplete;
            } else target = actual;
        };
        const selected = target orelse return error.Incomplete;
        return self.invoke(try self.named(selected), &.{receiver}, .{ .owner = owner, .node = node }, effective, observe, false);
    }

    fn expression(self: *Walk, owner: usize, id: core.Id, frame: *Frame, weak: bool, observe: bool) Error!Flow {
        if (id == 0) return .{ .value = 0 };
        try self.charge();
        self.depth += 1;
        defer self.depth -= 1;
        const module = &self.units[owner];
        if (id >= module.nodes.len) return error.Incomplete;
        const n = module.node(id);
        const site: Site = .{ .owner = owner, .node = id };
        try self.fact(site, .node, weak, 0, null, observe);
        switch (n.tag) {
            .constant => return .{ .value = try self.scalarType(owner, n.ty, true, n.a) },
            .reference => {
                const target = try self.normalize(owner, module.reference(id));
                const producer = try self.ownerOf(target.unit, null);
                const binding = self.units[producer].binding(target.binding);
                if (binding.kind == .local or binding.kind == .parameter) {
                    if (producer != owner) return error.Incomplete;
                    return .{ .value = frame.values.get(target.binding) orelse return error.Incomplete };
                }
                const declaration = try self.body(target);
                if (declaration.runtime) {
                    try self.emit(site, target, .runtime_read, weak, observe);
                    if (declaration.is_function) return .{ .value = try self.named(target) };
                    return .{ .value = try self.placeholder(producer, binding.ty) };
                }
                return .{ .value = try self.constant(target) };
            },
            .scalar, .associated => {
                if (n.tag == .scalar and n.c > 1) return error.Incomplete;
                const first = try self.expression(owner, n.a, frame, weak, observe);
                if (first != .value) return first;
                const second = try self.expression(owner, n.b, frame, weak, observe);
                if (second != .value) return second;
                return .{ .value = if (n.tag == .associated or n.c == 1) try self.dispatchedScalar(owner, id, n.op, if (n.tag == .associated) n.c else 0, first.value, second.value, weak, observe) else try self.scalar(n.op, first.value, second.value) };
            },
            .logical, .if_value, .if_stmt => {
                const condition = try self.expression(owner, n.a, frame, weak, observe);
                if (condition != .value) return condition;
                const value = self.values.items[condition.value];
                if (value.kind != .scalar or !value.known or value.scalar.scalar != .bool) return error.Incomplete;
                if (n.tag == .logical) {
                    if (n.op != .and_ and n.op != .or_) return error.Incomplete;
                    if ((n.op == .and_ and value.scalar.bits == 0) or (n.op == .or_ and value.scalar.bits != 0)) {
                        if (observe) {
                            var branch = try self.copyFrame(frame);
                            defer branch.deinit(self.allocator);
                            _ = try self.expression(owner, n.b, &branch, weak, true);
                        }
                        return condition;
                    }
                    return self.expression(owner, n.b, frame, weak, observe);
                }
                const yes = value.scalar.bits != 0;
                if (observe) {
                    var branch = try self.copyFrame(frame);
                    defer branch.deinit(self.allocator);
                    _ = try self.expression(owner, if (yes) n.c else n.b, &branch, weak, true);
                }
                const result = try self.expression(owner, if (yes) n.b else n.c, frame, weak, observe);
                if (n.tag == .if_value or result != .value) return result;
                for (module.branchMerges(id)) |merge| try frame.values.put(self.allocator, merge.result, frame.values.get(if (yes) merge.then_binding else merge.else_binding) orelse return error.Incomplete);
                return .{ .value = 0 };
            },
            .call => {
                const call = module.call(id);
                const target = try self.normalize(owner, call.target);
                const target_owner = try self.ownerOf(target.unit, null);
                const target_binding = self.units[target_owner].binding(target.binding);
                if (target_binding.kind == .local or target_binding.kind == .parameter) {
                    if (target_owner != owner) return error.Incomplete;
                    var function = frame.values.get(target.binding) orelse return error.Incomplete;
                    for (call.arguments) |argument| {
                        const result = try self.expression(owner, argument, frame, weak, observe);
                        if (result != .value) return result;
                        function = try self.invoke(function, &.{result.value}, site, weak, observe, false);
                    }
                    return .{ .value = function };
                }
                const declaration = try self.body(target);
                var function = if (declaration.is_function) try self.named(target) else try self.constant(target);
                if (declaration.runtime) try self.emit(site, target, .runtime_read, weak, observe);
                const producer = try self.ownerOf(target.unit, null);
                const parameters = self.units[producer].bodyParameters(declaration);
                const consumed = if (declaration.is_function) @min(call.arguments.len, parameters.len) else 0;
                const arguments = try self.allocator.alloc(ValueId, consumed);
                defer self.allocator.free(arguments);
                for (call.arguments[0..consumed], 0..) |argument, i| {
                    const result = try self.expression(owner, argument, frame, weak, observe);
                    if (result != .value) return result;
                    arguments[i] = result.value;
                }
                if (declaration.is_function) function = try self.invoke(function, arguments, site, weak, observe, false);
                for (call.arguments[consumed..]) |argument| {
                    const result = try self.expression(owner, argument, frame, weak, observe);
                    if (result != .value) return result;
                    function = try self.invoke(function, &.{result.value}, site, weak, observe, false);
                }
                return .{ .value = function };
            },
            .apply => {
                const function = try self.expression(owner, n.a, frame, weak, observe);
                if (function != .value) return function;
                const argument = try self.expression(owner, n.b, frame, weak, observe);
                if (argument != .value) return argument;
                return .{ .value = try self.invoke(function.value, &.{argument.value}, site, weak, observe, false) };
            },
            .closure, .suspend_ => {
                if (n.a >= module.closures.len) return error.Incomplete;
                const template = module.closures[n.a];
                const captures = try self.allocator.alloc(ValueId, template.captures.len);
                defer self.allocator.free(captures);
                for (module.extra[template.captures.start..][0..template.captures.len], 0..) |binding, i| captures[i] = frame.values.get(binding) orelse return error.Incomplete;
                var result = try self.aggregate(.{ .kind = if (n.tag == .closure) .closure else .suspension, .closure = .{ .unit = self.unitId(owner), .identity = n.a, .origin = .anonymous }, .provenance = if (n.tag == .suspend_) .waiting else .inherit }, captures, &.{});
                if (n.tag == .suspend_ and !observe) if (self.replay_producer) |producer| {
                    if (self.session.singleSourceSuspension(producer, self.unitId(owner), id)) |actual| result = try self.alignActual(actual, result);
                };
                if (n.tag == .suspend_) try self.retain(result, site, false, observe);
                return .{ .value = result };
            },
            .force => {
                const operand = try self.expression(owner, n.a, frame, weak, observe);
                if (operand != .value) return operand;
                return .{ .value = try self.force(operand.value, site, observe) };
            },
            .block, .suite => {
                for (module.children(id)) |child| {
                    const result = try self.expression(owner, child, frame, weak, observe);
                    if (result == .returning) {
                        if (n.tag == .block and result.returning.target == id) {
                            var value = result.returning.value;
                            if (frame.possible_return) |possible| {
                                if (possible.target != id) return error.Incomplete;
                                value = try self.join(value, possible.value);
                                frame.possible_return = null;
                            }
                            return .{ .value = value };
                        }
                        return result;
                    }
                }
                return .{ .value = 0 };
            },
            .match => return self.match(owner, id, frame, weak, observe),
            .pattern_bind => {
                const operand = try self.expression(owner, n.b, frame, weak, observe);
                if (operand != .value) return operand;
                var branch = try self.copyFrame(frame);
                defer branch.deinit(self.allocator);
                const matched = try self.pattern(owner, n.a, operand.value, &branch, weak, observe);
                if (matched == .yes) {
                    if (observe) {
                        var failure_frame = try self.copyFrame(frame);
                        defer failure_frame.deinit(self.allocator);
                        _ = try self.expression(owner, n.c, &failure_frame, weak, true);
                    }
                    frame.deinit(self.allocator);
                    frame.* = branch;
                    branch = .{};
                    return .{ .value = 0 };
                }
                var failure_frame = try self.copyFrame(frame);
                defer failure_frame.deinit(self.allocator);
                const failure = try self.expression(owner, n.c, &failure_frame, weak, observe);
                if (matched == .no) return failure;
                if (!observe or failure != .returning or branch.values.count() != frame.values.count()) return error.Incomplete;
                var entries = branch.values.iterator();
                while (entries.next()) |entry| if (frame.values.get(entry.key_ptr.*) != entry.value_ptr.*) return error.Incomplete;
                if (frame.possible_return) |previous| {
                    if (previous.target != failure.returning.target) return error.Incomplete;
                    frame.possible_return = .{ .target = previous.target, .value = try self.join(previous.value, failure.returning.value) };
                } else frame.possible_return = .{ .target = failure.returning.target, .value = failure.returning.value };
                return .{ .value = 0 };
            },
            .bind => {
                const result = try self.expression(owner, n.b, frame, weak, observe);
                if (result != .value) return result;
                try frame.values.put(self.allocator, n.a, result.value);
                return .{ .value = 0 };
            },
            .return_ => {
                const result = try self.expression(owner, n.a, frame, weak, observe);
                if (result != .value) return result;
                return .{ .returning = .{ .target = n.b, .value = result.value } };
            },
            .product, .record, .array => {
                const operands = module.children(id);
                const children_ = try self.allocator.alloc(ValueId, operands.len);
                defer self.allocator.free(children_);
                const fields_ = try self.allocator.alloc(u32, if (n.tag == .record) operands.len else 0);
                defer self.allocator.free(fields_);
                if (n.tag == .record) {
                    if (n.ty >= module.types.nodes.len) return error.Incomplete;
                    const record = module.types.node(n.ty);
                    if (record.tag != .record or record.b != operands.len) return error.Incomplete;
                    for (fields_, 0..) |*field, i| field.* = module.types.recordField(record, i).name;
                }
                for (operands, 0..) |operand, i| {
                    const result = try self.expression(owner, operand, frame, weak, observe);
                    if (result != .value) return result;
                    const destination = if (n.tag == .record) module.recordDestinations(id)[i] else i;
                    if (destination >= children_.len) return error.Incomplete;
                    children_[destination] = result.value;
                }
                const result = try self.aggregate(.{ .kind = if (n.tag == .record) .record else if (n.tag == .array) .array else .product }, children_, fields_);
                try self.retain(result, site, weak, observe);
                return .{ .value = result };
            },
            .array_op => {
                if (n.c > @backingInt(core.ArrayOp.generate)) return error.Incomplete;
                const operands = module.children(id);
                if (operands.len > 3) return error.Incomplete;
                var arguments: [3]ValueId = undefined;
                for (operands, 0..) |operand, i| {
                    const result = try self.expression(owner, operand, frame, weak, observe);
                    if (result != .value) return result;
                    arguments[i] = result.value;
                }
                return .{ .value = try self.arrayValues(@fromBackingInt(@intCast(n.c)), arguments[0..operands.len], site, weak, observe) };
            },
            .construct => {
                const argument: ?ValueId = if (n.b == 0) null else blk: {
                    const result = try self.expression(owner, n.b, frame, weak, observe);
                    if (result != .value) return result;
                    break :blk result.value;
                };
                return .{ .value = try self.construct(owner, n.a, argument, n.c != 0) };
            },
            .project => {
                const receiver = try self.expression(owner, n.a, frame, weak, observe);
                if (receiver != .value) return receiver;
                return .{ .value = try self.project(owner, id, n.b, receiver.value, weak, observe) };
            },
            .constructor_function, .primitive_function => return .{ .value = try self.add(.{ .kind = .closure, .closure = .{ .unit = self.unitId(owner), .identity = n.a, .origin = if (n.tag == .constructor_function) .constructor else .primitive, .ty = n.ty } }) },
            else => return error.Incomplete,
        }
    }
};

pub fn collect(allocator: Allocator, units: []const core.Module, session: *core_eval.Session, roots: []const core.BindingRef) Error!Result {
    if (session.units.ptr != units.ptr or session.units.len != units.len) return error.Incomplete;
    var walk: Walk = .{ .allocator = allocator, .units = units, .session = session };
    defer walk.deinit();
    _ = try walk.add(.{}); // Exact Unit, also the argument to a demand body.
    for (roots) |root| {
        walk.root = try walk.normalize(null, root);
        const owner = try walk.ownerOf(walk.root.unit, null);
        const declaration = try walk.body(walk.root);
        if (!declaration.runtime or declaration.is_function) return error.Incomplete;
        var frame: Frame = .{};
        defer frame.deinit(allocator);
        const site: Site = .{ .owner = owner, .node = declaration.root };
        try walk.fact(site, .body_enter, false, walk.root.binding, null, true);
        const result = try walk.expression(owner, declaration.root, &frame, false, true);
        if (result != .value or frame.possible_return != null) return error.Incomplete;
        const expected = if (walk.values.items[result.value].kind == .closure) try walk.scalarInterface(owner, units[owner].binding(walk.root.binding).ty) else null;
        try walk.retainScalarInterface(result.value, site, false, true, expected);
        try walk.fact(site, .body_complete, false, walk.root.binding, null, true);
    }
    const edges = try walk.edges.toOwnedSlice(allocator);
    errdefer allocator.free(edges);
    return .{ .edges = edges, .facts = try walk.facts.toOwnedSlice(allocator) };
}
