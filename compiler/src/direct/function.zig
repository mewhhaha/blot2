//! One instance's Wasm body. A single pass over its Core body; every value is a
//! list of Wasm locals in its type's layout, so projections share locals.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const W = @import("writer.zig");
const types = @import("types.zig");
const emit = @import("emit.zig");
const Ty = types.Ty;
const Val = emit.Val;
const Generator = emit.Generator;
const Error = emit.Error;
const A = std.mem.Allocator;

/// A Core block or loop that `return_`/`break_` can leave, at a Wasm depth.
const Label = struct {
    target: core.Id,
    depth: u32,
    result: Val = .{ .ty = types.unit },
    /// function: the body's own exit, the target of every unmatched return.
    kind: enum { block, loop, function } = .block,
    /// Loops: the backedge target depth, current iteration and exit values.
    top: u32 = 0,
    iteration: []const Val = &.{},
    outgoing: []const Val = &.{},
};

pub const Fn = struct {
    g: *Generator,
    m: *const core.Module,
    env: *const types.Env,
    arena: A,
    instance_id: u32 = 0,
    code: W.Bytes = .{},
    locals: std.ArrayList(W.ValType) = .empty,
    parameter_words: u32 = 0,
    bindings: std.AutoHashMapUnmanaged(core.BindingId, Val) = .empty,
    /// Generalized local function values by binding, built at each use.
    polymorphic: std.AutoHashMapUnmanaged(core.BindingId, core.Id) = .empty,
    labels: std.ArrayList(Label) = .empty,
    depth: u32 = 0,
    /// Set when this body allocates environment memory or receives a value
    /// that may refer to it; such a body restores the stack on exit unless
    /// its result can hold that memory.
    allocates: bool = false,

    fn a(self: *Fn) A {
        return self.g.allocator;
    }
    fn op(self: *Fn, value: W.Op) Error!void {
        try self.code.byte(self.a(), @backingInt(value));
    }
    fn opIndex(self: *Fn, value: W.Op, index: u32) Error!void {
        try self.op(value);
        try self.code.uleb(self.a(), index);
    }
    fn i32Const(self: *Fn, value: u32) Error!void {
        try self.op(.i32_const);
        try self.code.sleb(self.a(), @as(i32, @bitCast(value)));
    }
    fn f32Const(self: *Fn, bits: u32) Error!void {
        try self.op(.f32_const);
        try self.code.raw(self.a(), std.mem.asBytes(&bits));
    }
    /// Opens a void structured block (block, loop or if) and returns its depth.
    fn open(self: *Fn, kind: W.Op) Error!u32 {
        try self.op(kind);
        try self.code.byte(self.a(), 0x40);
        self.depth += 1;
        return self.depth;
    }
    fn close(self: *Fn) Error!void {
        try self.op(.end);
        self.depth -= 1;
    }
    fn br(self: *Fn, value: W.Op, depth: u32) Error!void {
        try self.opIndex(value, self.depth - depth);
    }

    fn local(self: *Fn, ty: W.ValType) Error!u32 {
        const id: u32 = @intCast(self.locals.items.len);
        try self.locals.append(self.a(), ty);
        return id;
    }
    fn layout(self: *Fn, ty: Ty, id: core.Id) Error![]const W.ValType {
        return self.g.types.layout(ty) catch |err| switch (err) {
            error.Unsupported => return self.g.typeFailure(self.m, id),
            else => return err,
        };
    }
    fn fresh(self: *Fn, ty: Ty, id: core.Id) Error!Val {
        const words = try self.layout(ty, id);
        const locals = try self.arena.alloc(u32, words.len);
        for (words, locals) |word, *slot| slot.* = try self.local(word);
        return .{ .ty = ty, .words = locals };
    }
    fn lower(self: *Fn, ty: T.Id, id: core.Id) Error!Ty {
        return self.g.types.lower(self.m, ty, self.env) catch |err| switch (err) {
            error.Unsupported => return self.g.typeFailure(self.m, id),
            else => return err,
        };
    }
    fn typeOf(self: *Fn, id: core.Id) Error!Ty {
        return self.lower(self.m.typeOf(id), id);
    }
    fn push(self: *Fn, value: Val) Error!void {
        for (value.words) |word| try self.opIndex(.local_get, word);
    }
    /// Pops a value of type `ty` from the operand stack into fresh locals.
    fn pop(self: *Fn, ty: Ty, id: core.Id) Error!Val {
        const value = try self.fresh(ty, id);
        var at = value.words.len;
        while (at != 0) {
            at -= 1;
            try self.opIndex(.local_set, value.words[at]);
        }
        return value;
    }
    fn copy(self: *Fn, from: Val, to: Val, id: core.Id) Error!void {
        if (from.ty == types.never) return;
        if (from.words.len != to.words.len) return self.g.fail(self.m, id, "value layout mismatch", .{});
        for (from.words, to.words) |source, target| {
            if (source == target) continue;
            try self.opIndex(.local_get, source);
            try self.opIndex(.local_set, target);
        }
    }
    fn unitVal() Val {
        return .{ .ty = types.unit };
    }
    fn neverVal() Val {
        return .{ .ty = types.never };
    }

    pub fn expr(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        return switch (n.tag) {
            .constant => self.constant(id),
            .reference => self.reference(id),
            .scalar => self.scalar(id),
            .logical => self.logical(id),
            .call => self.call(id),
            .associated => self.associated(id),
            .if_value, .if_stmt => self.ifNode(id),
            .block => self.block(id),
            .suite => blk: {
                var last = unitVal();
                for (self.m.children(id)) |child| last = try self.expr(child);
                break :blk if (last.ty == types.never) last else unitVal();
            },
            .bind => blk: {
                // A generalized local closure is built at each use, at that
                // use's types; its captures are already immutable values.
                const deferred = switch (self.m.node(n.b).tag) {
                    .closure, .constructor_function, .primitive_function, .reference => true,
                    else => false,
                };
                if (deferred and self.m.binding(n.a).scheme.variables.len != 0) {
                    try self.polymorphic.put(self.a(), n.a, n.b);
                    break :blk unitVal();
                }
                const value = try self.expr(n.b);
                try self.bindings.put(self.a(), n.a, value);
                break :blk if (value.ty == types.never) value else unitVal();
            },
            .return_ => self.returnNode(id),
            .product, .record => self.product(id),
            .construct => self.construct(id),
            .project => self.project(id),
            .match => self.match(id),
            .pattern_bind => self.patternBind(id),
            .loop => self.loop(id),
            .closure => self.closureNode(id),
            .apply => self.apply(id),
            .constructor_function => self.constructorFunction(id),
            .primitive_function => self.primitiveFunction(id),
            .update => self.update(id),
            .break_ => self.breakNode(id),
            .panic => blk: {
                try self.op(.unreachable_);
                break :blk neverVal();
            },
            else => self.g.fail(self.m, id, "{s} expressions are not supported yet", .{@tagName(n.tag)}),
        };
    }

    fn constant(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const ty = try self.typeOf(id);
        switch (self.g.types.node(ty).tag) {
            .unit => return unitVal(),
            .f32 => try self.f32Const(n.a),
            .u32, .boolean => try self.i32Const(n.a),
            else => return self.g.fail(self.m, id, "constant of a composite type", .{}),
        }
        return self.pop(ty, id);
    }

    fn reference(self: *Fn, id: core.Id) Error!Val {
        const ref = self.m.reference(id);
        if (ref.unit == 0 or ref.unit == self.m.unit) {
            if (self.bindings.get(ref.binding)) |value| return value;
            if (self.polymorphic.get(ref.binding)) |closure| {
                var env: types.Env = .empty;
                defer env.deinit(self.a());
                var it = self.env.iterator();
                while (it.next()) |entry| try env.put(self.a(), entry.key_ptr.*, entry.value_ptr.*);
                try self.g.types.match(self.m, self.m.typeOf(closure), try self.typeOf(id), &env);
                const previous = self.env;
                self.env = &env;
                defer self.env = previous;
                return self.expr(closure);
            }
        }
        const target = self.g.resolve(self.m, ref);
        const tm = self.g.unitModule(target.unit);
        const binding = tm.binding(target.binding);
        switch (binding.kind) {
            .local, .parameter => return self.g.fail(self.m, id, "unbound local reference", .{}),
            else => {},
        }
        const ty = try self.typeOf(id);
        if (primitiveAlias(tm, target.binding) != null) return self.partial(.primitive, target, ty, &.{}, id);
        if (tm.body(target.binding)) |body| {
            if (body.is_function) return self.partial(.partial, target, ty, &.{}, id);
            // A constant: its instance computes the value.
            const instance = try self.g.named(target, ty, self.m, id);
            try self.opIndex(.call, self.g.instance(instance).function);
            return self.received(ty, id);
        }
        return self.g.fail(self.m, id, "reference to a {s} binding without a value", .{@tagName(binding.kind)});
    }
    /// Pops a call result; a result that may refer to scope memory makes
    /// this body responsible for releasing it.
    fn received(self: *Fn, ty: Ty, id: core.Id) Error!Val {
        if (try self.g.holdsMemory(ty)) self.allocates = true;
        return self.pop(ty, id);
    }

    /// Allocates `bytes` of environment memory and returns its address local.
    fn allocate(self: *Fn, bytes: u32) Error!u32 {
        self.allocates = true;
        const sp = try self.g.stackPointer();
        const address = try self.local(.i32);
        try self.opIndex(.global_get, sp);
        try self.opIndex(.local_tee, address);
        try self.i32Const(bytes);
        try self.op(.i32_add);
        try self.opIndex(.global_set, sp);
        try self.opIndex(.global_get, sp);
        try self.i32Const(emit.env_base + emit.env_bytes);
        try self.op(.i32_gt_u);
        _ = try self.open(.if_);
        try self.op(.unreachable_);
        try self.close();
        return address;
    }
    /// A closure over `captures`, invoking instance `instance` with them.
    fn makeClosure(self: *Fn, instance: u32, ty: Ty, captures: []const Val, id: core.Id) Error!Val {
        const slot = self.g.instance(instance).slot;
        var words: usize = 0;
        for (captures) |capture| words += capture.words.len;
        const result = try self.fresh(ty, id);
        try self.i32Const(slot);
        try self.opIndex(.local_set, result.words[0]);
        if (words == 0) {
            try self.i32Const(0);
            try self.opIndex(.local_set, result.words[1]);
            return result;
        }
        const address = try self.allocate(@intCast(words * 4));
        var offset: u32 = 0;
        for (captures) |capture| for (capture.words) |word| {
            try self.opIndex(.local_get, address);
            try self.opIndex(.local_get, word);
            try self.op(if (self.locals.items[word] == .f32) .f32_store else .i32_store);
            try self.code.uleb(self.a(), 2);
            try self.code.uleb(self.a(), offset);
            offset += 4;
        };
        try self.opIndex(.local_get, address);
        try self.opIndex(.local_set, result.words[1]);
        return result;
    }
    /// Loads a closure's captures from its environment parameter (local 0).
    fn loadCaptures(self: *Fn, captures: []const Ty, id: core.Id) Error![]Val {
        const out = try self.arena.alloc(Val, captures.len);
        var offset: u32 = 0;
        for (captures, out) |ty, *slot| {
            slot.* = try self.fresh(ty, id);
            for (slot.words) |word| {
                try self.opIndex(.local_get, 0);
                try self.op(if (self.locals.items[word] == .f32) .f32_load else .i32_load);
                try self.code.uleb(self.a(), 2);
                try self.code.uleb(self.a(), offset);
                try self.opIndex(.local_set, word);
                offset += 4;
            }
        }
        return out;
    }

    /// A curried function value: `target` (a named function, primitive alias
    /// or constructor) applied to its first `arguments`.
    fn partial(self: *Fn, kind: emit.InstanceKind, target: core.BindingRef, ty: Ty, arguments: []const Val, id: core.Id) Error!Val {
        const full = try self.curried(arguments, ty);
        const instance = try self.adapter(kind, target, full, arguments.len, id);
        return self.makeClosure(instance, ty, arguments, id);
    }
    /// The closure taking argument `count` of `target` at function type `full`.
    fn adapter(self: *Fn, kind: emit.InstanceKind, target: core.BindingRef, full: Ty, count: usize, id: core.Id) Error!u32 {
        const key: emit.InstanceKey = .{ .kind = kind, .unit = target.unit, .id = target.binding, .ty = full, .parent = @intCast(count) };
        if (self.g.find(key)) |found| return found;
        var captures: std.ArrayList(Ty) = .empty;
        var rest = full;
        for (0..count) |_| {
            const arrow = self.g.types.node(rest);
            if (arrow.tag != .function) return self.g.fail(self.m, id, "partial application beyond the function's arity", .{});
            try captures.append(self.g.arena.allocator(), arrow.a);
            rest = arrow.b;
        }
        const arrow = self.g.types.node(rest);
        if (arrow.tag != .function) return self.g.fail(self.m, id, "function value of a non-function type", .{});
        const parameters = try self.g.arena.allocator().dupe(Ty, &.{arrow.a});
        return self.g.addInstanceWith(key, .empty, parameters, arrow.b, true, captures.items, self.m, id);
    }

    /// The body of a curried adapter: the captured arguments plus this one
    /// either saturate the target or form the next partial application.
    fn adapterBody(self: *Fn, instance: *const emit.Instance, captures: []const Val, argument: Val) Error!Val {
        const key = instance.key;
        const arguments = try self.arena.alloc(Val, captures.len + 1);
        @memcpy(arguments[0..captures.len], captures);
        arguments[captures.len] = argument;
        const result = instance.result;
        switch (key.kind) {
            .partial => {
                const target: core.BindingRef = .{ .unit = key.unit, .binding = key.id };
                const tm = self.g.unitModule(key.unit);
                const parameters = tm.bodyParameters(tm.body(key.id).?);
                if (arguments.len < parameters.len) return self.partial(.partial, target, result, arguments, 0);
                return self.callTarget(target, arguments, key.ty, result, 0);
            },
            .primitive => {
                const tm = self.g.unitModule(key.unit);
                const primitive = if (key.id & primitive_node_bit != 0) tm.primitive(key.id & ~primitive_node_bit) else tm.primitive(primitiveAlias(tm, key.id).?);
                return self.applyPrimitive(primitive, arguments, key.ty, result, .{ .unit = key.unit, .binding = key.id }, 0);
            },
            .constructor => {
                const tm = self.g.unitModule(key.unit);
                const constructor = tm.constructor(key.id);
                return self.wrapVariant(result, constructor.tag, argument, 0);
            },
            else => unreachable,
        }
    }
    fn closureNode(self: *Fn, id: core.Id) Error!Val {
        const ty = try self.typeOf(id);
        const arrow = self.g.types.node(ty);
        if (arrow.tag != .function) return self.g.fail(self.m, id, "closure of a non-function type", .{});
        const capture_ids = self.m.closureCaptures(id);
        const captures = try self.arena.alloc(Val, capture_ids.len);
        for (capture_ids, captures) |binding, *slot| slot.* = self.bindings.get(binding) orelse return self.g.fail(self.m, id, "closure capture without a value", .{});
        const key: emit.InstanceKey = .{ .kind = .lambda, .unit = self.m.unit, .id = id, .ty = ty, .parent = self.instance_id };
        const instance = self.g.find(key) orelse blk: {
            const capture_types = try self.g.arena.allocator().alloc(Ty, captures.len);
            for (captures, capture_types) |capture, *slot| slot.* = capture.ty;
            var env: types.Env = .empty;
            var it = self.env.iterator();
            while (it.next()) |entry| try env.put(self.a(), entry.key_ptr.*, entry.value_ptr.*);
            const parameters = try self.g.arena.allocator().dupe(Ty, &.{arrow.a});
            break :blk try self.g.addInstanceWith(key, env, parameters, arrow.b, true, capture_types, self.m, id);
        };
        return self.makeClosure(instance, ty, captures, id);
    }

    /// Calls the closure `callee` with one argument.
    fn applyClosure(self: *Fn, callee: Val, argument: Val, id: core.Id) Error!Val {
        const arrow = self.g.types.node(callee.ty);
        if (arrow.tag != .function or callee.words.len != 2) return self.g.fail(self.m, id, "application of a non-function value", .{});
        try self.opIndex(.local_get, callee.words[1]);
        try self.push(argument);
        try self.opIndex(.local_get, callee.words[0]);
        const signature = self.g.closureSignature(arrow.a, arrow.b) catch |err| switch (err) {
            error.Unsupported => return self.g.typeFailure(self.m, id),
            else => return err,
        };
        try self.opIndex(.call_indirect, signature);
        try self.code.uleb(self.a(), 0);
        return self.received(arrow.b, id);
    }
    fn apply(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const callee = try self.expr(n.a);
        const argument = try self.expr(n.b);
        return self.applyClosure(callee, argument, id);
    }
    fn constructorFunction(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const ty = try self.typeOf(id);
        return self.partial(.constructor, .{ .unit = self.m.unit, .binding = n.a }, ty, &.{}, id);
    }
    fn primitiveFunction(self: *Fn, id: core.Id) Error!Val {
        const ty = try self.typeOf(id);
        // A primitive node is its own target: the unit's primitive catalog.
        return self.partial(.primitive, .{ .unit = self.m.unit, .binding = id | primitive_node_bit }, ty, &.{}, id);
    }

    /// `root` with the field path of an update replaced by its new value.
    fn update(self: *Fn, id: core.Id) Error!Val {
        const info = self.m.updateInfo(id);
        const root = try self.expr(info.root);
        return self.updateAt(id, root, 0);
    }
    fn updateAt(self: *Fn, id: core.Id, value: Val, at: usize) Error!Val {
        const info = self.m.updateInfo(id);
        const selectors = self.m.updateSelectors(id);
        const path = self.m.updatePath(id);
        const steps = @max(selectors.len, path.len);
        if (at == steps) {
            try self.bindings.put(self.a(), info.self_binding, value);
            return self.expr(info.value);
        }
        if (selectors.len != 0 and selectors[at].kind == .index) return self.g.fail(self.m, id, "indexed updates are not supported yet", .{});
        const projection = self.m.projection(if (selectors.len != 0) selectors[at].projection else path[at]);
        const spelling = self.m.fieldSpelling(projection.field) orelse return self.g.fail(self.m, id, "updated field without a spelling", .{});
        const name = try self.g.types.fieldName(spelling);
        var record = value;
        var wrapped: ?u32 = null;
        if (self.g.types.node(value.ty).tag == .nominal) {
            const cases = self.g.types.variants(value.ty) catch |err| switch (err) {
                error.Unsupported => return self.g.typeFailure(self.m, id),
                else => return err,
            };
            if (cases.payloads.len != 1) return self.g.fail(self.m, id, "update of a multi-constructor value", .{});
            record = try self.unwrapVariant(value, cases.tags[0], id);
            wrapped = cases.tags[0];
        }
        const position = self.g.types.findField(record.ty, name) orelse return self.g.fail(self.m, id, "updated field missing", .{});
        const slice = try self.fieldSlice(record.ty, position, id);
        const old: Val = .{ .ty = self.g.types.recordField(record.ty, position).ty, .words = record.words[slice.start..][0..slice.len] };
        const replacement = try self.updateAt(id, old, at + 1);
        if (replacement.ty == types.never) return replacement;
        var words: std.ArrayList(u32) = .empty;
        try words.appendSlice(self.arena, record.words[0..slice.start]);
        try words.appendSlice(self.arena, replacement.words);
        try words.appendSlice(self.arena, record.words[slice.start + slice.len ..]);
        var ty = record.ty;
        if (replacement.ty != old.ty) {
            const shape = self.g.types.node(record.ty);
            const fields = try self.arena.alloc(types.Field, shape.b);
            for (fields, 0..) |*field, index| field.* = self.g.types.recordField(record.ty, index);
            fields[position].ty = replacement.ty;
            ty = try self.g.types.record(fields);
        }
        const updated: Val = .{ .ty = ty, .words = words.items };
        if (wrapped != null) return .{ .ty = value.ty, .words = updated.words };
        return updated;
    }

    fn scalar(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const operand = try self.typeOf(n.a);
        const left = try self.expr(n.a);
        const right = if (n.b != 0) try self.expr(n.b) else null;
        const result = try self.typeOf(id);
        try self.push(left);
        if (right) |value| try self.push(value);
        try self.scalarOp(n.op, operand, id);
        return self.pop(result, id);
    }
    /// Emits the machine operation for `op` on operands already on the stack.
    pub fn scalarOp(self: *Fn, op_: core.Op, operand: Ty, id: core.Id) Error!void {
        const tag = self.g.types.node(operand).tag;
        const float = tag == .f32;
        if (tag != .u32 and tag != .f32 and tag != .boolean) return self.g.fail(self.m, id, "{s} on a non-scalar operand needs associated dispatch", .{@tagName(op_)});
        const code: W.Op = switch (op_) {
            .add => if (float) .f32_add else .i32_add,
            .sub => if (float) .f32_sub else .i32_sub,
            .mul => if (float) .f32_mul else .i32_mul,
            .div => if (float) .f32_div else .i32_div_u,
            .rem => if (float) return self.g.fail(self.m, id, "F32 remainder", .{}) else .i32_rem_u,
            .equal => if (float) .f32_eq else .i32_eq,
            .not_equal => if (float) .f32_ne else .i32_ne,
            .less => if (float) .f32_lt else .i32_lt_u,
            .less_equal => if (float) .f32_le else .i32_le_u,
            .greater => if (float) .f32_gt else .i32_gt_u,
            .greater_equal => if (float) .f32_ge else .i32_ge_u,
            .bit_and => .i32_and,
            .bit_or => .i32_or,
            .bit_xor => .i32_xor,
            .shift_left => .i32_shl,
            .shift_right => .i32_shr_u,
            .shift_right_signed => .i32_shr_s,
            .neg => if (float) .f32_neg else {
                // 0 - x: the operand is already on the stack.
                const value = try self.local(.i32);
                try self.opIndex(.local_set, value);
                try self.i32Const(0);
                try self.opIndex(.local_get, value);
                try self.op(.i32_sub);
                return;
            },
            .abs => if (float) .f32_abs else return,
            .ceil => .f32_ceil,
            .floor => .f32_floor,
            .trunc => .f32_trunc,
            .sqrt => .f32_sqrt,
            .min => .f32_min,
            .max => .f32_max,
            .convert_u32_f32 => .f32_convert_i32_u,
            .convert_f32_u32 => {
                try self.op(.prefix_fc);
                try self.code.uleb(self.a(), 1); // i32.trunc_sat_f32_u
                return;
            },
            .bit_not => {
                try self.i32Const(0xffff_ffff);
                try self.op(.i32_xor);
                return;
            },
            else => return self.g.fail(self.m, id, "scalar operation {s}", .{@tagName(op_)}),
        };
        try self.op(code);
    }

    fn logical(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const result = try self.fresh(types.boolean, id);
        const left = try self.expr(n.a);
        try self.push(left);
        if (n.op == .and_) {
            _ = try self.open(.if_);
            const right = try self.expr(n.b);
            try self.copy(right, result, id);
            try self.op(.else_);
            try self.i32Const(0);
            try self.opIndex(.local_set, result.words[0]);
        } else {
            _ = try self.open(.if_);
            try self.i32Const(1);
            try self.opIndex(.local_set, result.words[0]);
            try self.op(.else_);
            const right = try self.expr(n.b);
            try self.copy(right, result, id);
        }
        try self.close();
        return result;
    }

    fn call(self: *Fn, id: core.Id) Error!Val {
        const info = self.m.call(id);
        const target = self.g.resolve(self.m, info.target);
        const values = try self.arena.alloc(Val, info.arguments.len);
        for (info.arguments, values) |argument, *slot| slot.* = try self.expr(argument);
        return self.callTarget(target, values, try self.lower(info.callee_type, id), try self.typeOf(id), id);
    }
    /// Applies a resolved module-level binding to evaluated arguments.
    /// `callee` is its concrete (curried) function type at this site.
    fn callTarget(self: *Fn, target: core.BindingRef, arguments: []const Val, callee: Ty, result: Ty, id: core.Id) Error!Val {
        const tm = self.g.unitModule(target.unit);
        const binding = tm.binding(target.binding);
        _ = binding;
        if (tm.body(target.binding)) |body| if (body.is_function) {
            const parameters = tm.bodyParameters(body);
            if (arguments.len < parameters.len) return self.partial(.partial, target, try self.restType(callee, arguments.len, id), arguments, id);
            const direct = arguments[0..parameters.len];
            const after = try self.restType(callee, parameters.len, id);
            var value = (try self.forward(tm, body, direct, callee, after, id)) orelse blk: {
                const instance = try self.g.named(target, callee, self.m, id);
                for (direct) |argument| try self.push(argument);
                const function = self.g.instance(instance);
                try self.opIndex(.call, function.function);
                break :blk try self.received(function.result, id);
            };
            for (arguments[parameters.len..]) |argument| value = try self.applyClosure(value, argument, id);
            return value;
        };
        if (primitiveAlias(tm, target.binding)) |node| return self.applyPrimitive(tm.primitive(node), arguments, callee, result, target, id);
        // A constant holding a function value: apply it one argument at a time.
        var value = try self.namedValue(target, callee, id);
        for (arguments) |argument| value = try self.applyClosure(value, argument, id);
        return value;
    }
    fn namedValue(self: *Fn, target: core.BindingRef, ty: Ty, id: core.Id) Error!Val {
        const instance = try self.g.named(target, ty, self.m, id);
        try self.opIndex(.call, self.g.instance(instance).function);
        return self.received(ty, id);
    }
    fn applyPrimitive(self: *Fn, primitive: core.Primitive, arguments: []const Val, callee: Ty, result: Ty, target: core.BindingRef, id: core.Id) Error!Val {
        if (primitive.kind != .scalar) return self.g.fail(self.m, id, "array primitives are not supported yet", .{});
        if (arguments.len < primitive.arity) return self.partial(.primitive, target, try self.restType(callee, arguments.len, id), arguments, id);
        if (arguments.len > primitive.arity) return self.g.fail(self.m, id, "primitive over-application", .{});
        for (arguments) |argument| try self.push(argument);
        try self.scalarOp(primitive.op, arguments[0].ty, id);
        return self.pop(result, id);
    }
    /// The type left after applying `count` arguments to function type `ty`.
    fn restType(self: *Fn, ty: Ty, count: usize, id: core.Id) Error!Ty {
        var rest = ty;
        for (0..count) |_| {
            const arrow = self.g.types.node(rest);
            if (arrow.tag != .function) return self.g.fail(self.m, id, "too many arguments", .{});
            rest = arrow.b;
        }
        return rest;
    }
    /// A wrapper whose body only passes its parameters to an associated
    /// member or another named function is resolved at the call site, so an
    /// operator on scalars costs one machine instruction, not two calls.
    fn forward(self: *Fn, tm: *const core.Module, body: *const core.Body, arguments: []const Val, callee: Ty, result: Ty, id: core.Id) Error!?Val {
        const parameters = tm.bodyParameters(body);
        var root = body.root;
        for (0..8) |_| {
            const n = tm.node(root);
            if (n.tag == .return_) {
                root = n.a;
            } else if (n.tag == .block and n.b == 1) {
                root = tm.children(root)[0];
            } else break;
        }
        const n = tm.node(root);
        const operands: []const core.Id = switch (n.tag) {
            .associated => if (n.b != 0) &.{ n.a, n.b } else &.{n.a},
            .call => tm.call(root).arguments,
            else => return null,
        };
        if (operands.len > 8) return null;
        var order: [8]Val = undefined;
        for (operands, order[0..operands.len]) |operand, *slot| {
            if (tm.node(operand).tag != .reference) return null;
            const ref = tm.reference(operand);
            if (ref.unit != 0 and ref.unit != tm.unit) return null;
            slot.* = for (parameters, 0..) |parameter, position| {
                if (parameter.binding == ref.binding) break arguments[position];
            } else return null;
        }
        const forwarded = try self.arena.dupe(Val, order[0..operands.len]);
        if (n.tag == .associated) {
            const left = forwarded[0];
            const tag = self.g.types.node(left.ty).tag;
            if (n.op != .none and (tag == .u32 or tag == .f32 or tag == .boolean)) {
                for (forwarded) |value| try self.push(value);
                try self.scalarOp(n.op, left.ty, id);
                return try self.pop(result, id);
            }
            const identity = self.g.receiverIdentity(left.ty) orelse return null;
            const target = self.g.dispatchTarget(tm, identity, n.c, .none) orelse return null;
            return try self.callTarget(target, forwarded, try self.curried(forwarded, result), result, id);
        }
        // Lower the inner call's type under the wrapper's own instance types.
        var env: types.Env = .empty;
        defer env.deinit(self.a());
        try self.g.types.match(tm, tm.binding(body.binding).ty, callee, &env);
        const inner = tm.call(root);
        const inner_type = self.g.types.lower(tm, inner.callee_type, &env) catch |err| switch (err) {
            error.Unsupported => return null,
            else => return err,
        };
        return try self.callTarget(self.g.resolve(tm, inner.target), forwarded, inner_type, result, id);
    }
    /// The curried function type taking `arguments` and returning `result`.
    fn curried(self: *Fn, arguments: []const Val, result: Ty) Error!Ty {
        var ty = result;
        var at = arguments.len;
        while (at != 0) {
            at -= 1;
            ty = try self.g.types.function(arguments[at].ty, ty);
        }
        return ty;
    }

    /// Operator or member dispatch on the left operand's concrete type.
    fn associated(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const left = try self.expr(n.a);
        const right: ?Val = if (n.b != 0) try self.expr(n.b) else null;
        const result = try self.typeOf(id);
        const tag = self.g.types.node(left.ty).tag;
        if (n.op != .none and (tag == .u32 or tag == .f32 or tag == .boolean)) {
            try self.push(left);
            if (right) |value| try self.push(value);
            try self.scalarOp(n.op, left.ty, id);
            return self.pop(result, id);
        }
        const identity = self.g.receiverIdentity(left.ty) orelse return self.g.fail(self.m, id, "associated member on a {s}", .{@tagName(tag)});
        const target = self.g.dispatchTarget(self.m, identity, n.c, .none) orelse return self.g.fail(self.m, id, "no associated member for this receiver", .{});
        const arguments: []const Val = if (right) |value| &.{ left, value } else &.{left};
        const owned = try self.arena.dupe(Val, arguments);
        return self.callTarget(target, owned, try self.curried(owned, result), result, id);
    }

    fn ifNode(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const ty = if (n.tag == .if_stmt) types.unit else try self.typeOf(id);
        const result = try self.fresh(ty, id);
        const merges = self.m.branchMerges(id);
        const merged = try self.arena.alloc(Val, merges.len);
        for (merges, merged) |merge, *slot| slot.* = try self.fresh(try self.lower(self.m.binding(merge.result).ty, id), id);
        try self.push(try self.expr(n.a));
        _ = try self.open(.if_);
        const then = try self.expr(n.b);
        if (then.ty != types.never) {
            if (n.tag == .if_value) try self.copy(then, result, id);
            for (merges, merged) |merge, slot| if (self.bindings.get(merge.then_binding)) |value| try self.copy(value, slot, id);
        }
        try self.op(.else_);
        if (n.c != 0) {
            const otherwise = try self.expr(n.c);
            if (otherwise.ty != types.never) {
                if (n.tag == .if_value) try self.copy(otherwise, result, id);
                for (merges, merged) |merge, slot| if (self.bindings.get(merge.else_binding)) |value| try self.copy(value, slot, id);
            }
        } else for (merges, merged) |merge, slot| if (self.bindings.get(merge.else_binding)) |value| try self.copy(value, slot, id);
        try self.close();
        for (merges, merged) |merge, slot| try self.bindings.put(self.a(), merge.result, slot);
        return result;
    }

    fn block(self: *Fn, id: core.Id) Error!Val {
        const ty = try self.typeOf(id);
        const result = try self.fresh(ty, id);
        const depth = try self.open(.block);
        try self.labels.append(self.a(), .{ .target = id, .depth = depth, .result = result });
        for (self.m.children(id)) |child| _ = try self.expr(child);
        _ = self.labels.pop();
        try self.close();
        return result;
    }

    fn returnNode(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const value = try self.expr(n.a);
        if (value.ty == types.never) return neverVal();
        var at = self.labels.items.len;
        while (at != 0) {
            at -= 1;
            const label = self.labels.items[at];
            if ((label.target != n.b and label.kind != .function) or label.kind == .loop) continue;
            try self.copy(value, label.result, id);
            try self.br(.br, label.depth);
            return neverVal();
        }
        return self.g.fail(self.m, id, "return outside its block", .{});
    }

    /// Word offset and width of record field `index` of `ty`.
    fn fieldSlice(self: *Fn, ty: Ty, index: usize, id: core.Id) Error!struct { start: usize, len: usize } {
        var start: usize = 0;
        for (0..index) |before| start += (try self.layout(self.g.types.recordField(ty, before).ty, id)).len;
        return .{ .start = start, .len = (try self.layout(self.g.types.recordField(ty, index).ty, id)).len };
    }

    fn product(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const ty = try self.typeOf(id);
        const children = self.m.children(id);
        const values = try self.arena.alloc(Val, children.len);
        for (children, values) |child, *slot| slot.* = try self.expr(child);
        const shape = self.g.types.node(ty);
        var words: std.ArrayList(u32) = .empty;
        switch (shape.tag) {
            .unit => return unitVal(),
            .tuple => for (values) |value| try words.appendSlice(self.arena, value.words),
            .record => {
                const ordered = try self.arena.alloc(?Val, shape.b);
                @memset(ordered, null);
                const source = self.m.types.node(self.m.typeOf(id));
                if (source.tag != .record) return self.g.fail(self.m, id, "record literal without a record type", .{});
                const destinations: []const u32 = if (n.tag == .record) self.m.recordDestinations(id) else blk: {
                    const identity = try self.arena.alloc(u32, children.len);
                    for (identity, 0..) |*slot, index| slot.* = @intCast(index);
                    break :blk identity;
                };
                for (values, destinations) |value, destination| {
                    const field = self.m.types.recordField(source, destination);
                    const spelling = self.m.fieldSpelling(field.name) orelse return self.g.fail(self.m, id, "record field without a spelling", .{});
                    const position = self.g.types.findField(ty, try self.g.types.fieldName(spelling)) orelse return self.g.fail(self.m, id, "record field missing from its type", .{});
                    ordered[position] = value;
                }
                for (ordered) |value| try words.appendSlice(self.arena, (value orelse return self.g.fail(self.m, id, "record literal misses a field", .{})).words);
            },
            else => return self.g.fail(self.m, id, "product of type {s}", .{@tagName(shape.tag)}),
        }
        return .{ .ty = ty, .words = words.items };
    }

    fn construct(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const ty = try self.typeOf(id);
        const constructor = self.m.constructor(n.a);
        const payload = if (n.b != 0) try self.expr(n.b) else unitVal();
        return self.wrapVariant(ty, constructor.tag, payload, id);
    }
    fn variantPosition(self: *Fn, cases: types.Variants, tag: u32, id: core.Id) Error!usize {
        for (cases.tags, 0..) |candidate, position| if (candidate == tag) return position;
        return self.g.fail(self.m, id, "constructor tag missing from its type", .{});
    }
    fn wrapVariant(self: *Fn, ty: Ty, tag: u32, payload: Val, id: core.Id) Error!Val {
        const cases = self.g.types.variants(ty) catch |err| switch (err) {
            error.Unsupported => return self.g.typeFailure(self.m, id),
            else => return err,
        };
        if (cases.payloads.len == 1) return .{ .ty = ty, .words = payload.words };
        const result = try self.fresh(ty, id);
        try self.i32Const(tag);
        try self.opIndex(.local_set, result.words[0]);
        const slots = try self.layout(ty, id);
        const position = try self.variantPosition(cases, tag, id);
        const words = try self.layout(cases.payloads[position], id);
        for (payload.words, words, 0..) |word, kind, index| {
            try self.opIndex(.local_get, word);
            if (kind == .f32 and slots[index + 1] == .i32) try self.op(.i32_reinterpret_f32);
            try self.opIndex(.local_set, result.words[index + 1]);
        }
        return result;
    }
    /// The payload of `value` read as constructor `tag` (no tag check).
    fn unwrapVariant(self: *Fn, value: Val, tag: u32, id: core.Id) Error!Val {
        const cases = self.g.types.variants(value.ty) catch |err| switch (err) {
            error.Unsupported => return self.g.typeFailure(self.m, id),
            else => return err,
        };
        const position = try self.variantPosition(cases, tag, id);
        const payload_ty = cases.payloads[position];
        if (cases.payloads.len == 1) return .{ .ty = payload_ty, .words = value.words };
        const slots = try self.layout(value.ty, id);
        const words = try self.layout(payload_ty, id);
        const locals = try self.arena.alloc(u32, words.len);
        for (words, locals, 0..) |kind, *slot, index| {
            if (kind == slots[index + 1]) {
                slot.* = value.words[index + 1];
                continue;
            }
            slot.* = try self.local(kind);
            try self.opIndex(.local_get, value.words[index + 1]);
            try self.op(.f32_reinterpret_i32);
            try self.opIndex(.local_set, slot.*);
        }
        return .{ .ty = payload_ty, .words = locals };
    }

    fn project(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const value = try self.expr(n.a);
        const projection = self.m.projection(n.b);
        const variants = self.m.projectionVariants(n.b);
        // Constructor fields are named by the projecting unit's catalog.
        var name_symbol = projection.field;
        if (variants.len == 1 and projection.nominal.decl == 0 and self.g.types.node(value.ty).tag == .tuple) {
            const items = self.g.types.tupleItems(value.ty);
            if (variants[0].field >= items.len) return self.g.fail(self.m, id, "tuple projection out of range", .{});
            var start: usize = 0;
            for (items[0..variants[0].field]) |item| start += (try self.layout(item, id)).len;
            const item = items[variants[0].field];
            return .{ .ty = item, .words = value.words[start..][0..(try self.layout(item, id)).len] };
        }
        const nominal_field = variants.len != 0 and projection.nominal.decl != 0;
        if (nominal_field) {
            name_symbol = for (self.m.constructors) |constructor| {
                const identity = self.m.nominal(constructor.nominal).identity;
                if (identity.decl != projection.nominal.decl or constructor.tag != variants[0].tag) continue;
                const payload = self.m.types.node(constructor.payload);
                if (payload.tag != .record or variants[0].field >= payload.b) return self.g.fail(self.m, id, "constructor field projection", .{});
                break self.m.types.recordField(payload, variants[0].field).name;
            } else return self.g.fail(self.m, id, "projected constructor missing from the catalog", .{});
            if (variants.len > 1) return self.g.fail(self.m, id, "field shared by several constructors", .{});
        }
        const spelling = self.m.fieldSpelling(name_symbol) orelse return self.g.fail(self.m, id, "projected field without a spelling", .{});
        const name = try self.g.types.fieldName(spelling);
        var record = value;
        if (self.g.types.node(value.ty).tag == .nominal) {
            const cases = self.g.types.variants(value.ty) catch |err| switch (err) {
                error.Unsupported => return self.g.typeFailure(self.m, id),
                else => return err,
            };
            if (cases.payloads.len == 1) {
                record = try self.unwrapVariant(value, cases.tags[0], id);
            } else if (nominal_field and variants.len == 1) {
                record = try self.unwrapVariant(value, variants[0].tag, id);
            }
        }
        if (self.g.types.findField(record.ty, name)) |position| {
            const slice = try self.fieldSlice(record.ty, position, id);
            return .{ .ty = self.g.types.recordField(record.ty, position).ty, .words = record.words[slice.start..][0..slice.len] };
        }
        if (nominal_field or self.g.types.node(record.ty).tag == .record) return self.g.fail(self.m, id, "projected field missing", .{});
        // Not a data field: a receiver member, called with the value.
        const result = try self.typeOf(id);
        const identity = self.g.receiverIdentity(value.ty) orelse return self.g.fail(self.m, id, "member of a {s}", .{@tagName(self.g.types.node(value.ty).tag)});
        const target = self.g.dispatchTarget(self.m, identity, projection.field, .none) orelse return self.g.fail(self.m, id, "no member {s} for this receiver", .{spelling});
        const arguments = try self.arena.dupe(Val, &.{value});
        return self.callTarget(target, arguments, try self.g.types.function(value.ty, result), result, id);
    }

    fn match(self: *Fn, id: core.Id) Error!Val {
        const info = self.m.matchInfo(id);
        const inputs = self.m.matchInputs(id);
        const values = try self.arena.alloc(Val, inputs.len);
        for (inputs, values) |input, *slot| slot.* = try self.expr(input);
        const ty = if (info.statement) types.unit else try self.typeOf(id);
        const result = try self.fresh(ty, id);
        const done = try self.open(.block);
        for (self.m.matchArms(id)) |arm| {
            const rows = self.m.armRows(arm);
            if (rows.len != 1) return self.g.fail(self.m, id, "pattern alternatives are not supported yet", .{});
            const next = try self.open(.block);
            for (self.m.rowPatterns(rows[0]), values) |pattern, value| try self.test_(pattern, value, next, id);
            if (arm.guard != 0) {
                try self.push(try self.expr(arm.guard));
                try self.op(.i32_eqz);
                try self.br(.br_if, next);
            }
            const body = try self.expr(arm.body);
            if (!info.statement) try self.copy(body, result, id);
            try self.br(.br, done);
            try self.close();
        }
        try self.op(.unreachable_);
        try self.close();
        return result;
    }

    /// Tests `pattern` against `value`, branching to `fail` (a Wasm depth) on
    /// mismatch, and binds its names.
    fn test_(self: *Fn, pattern_id: core.PatternId, value: Val, fail: ?u32, id: core.Id) Error!void {
        const pattern = self.m.pattern(pattern_id);
        switch (pattern.tag) {
            .wildcard => {},
            .bind => try self.bindings.put(self.a(), pattern.a, value),
            .constant, .value => {
                const tag = self.g.types.node(value.ty).tag;
                try self.push(value);
                if (pattern.tag == .constant) {
                    if (tag == .f32) try self.f32Const(pattern.a) else try self.i32Const(pattern.a);
                } else try self.push(try self.expr(pattern.a));
                try self.op(if (tag == .f32) .f32_ne else .i32_ne);
                try self.failIf(fail, id);
            },
            .product => {
                const children = self.m.patternChildren(pattern_id);
                const shape = self.g.types.node(value.ty);
                switch (shape.tag) {
                    .tuple => {
                        var start: usize = 0;
                        for (children, self.g.types.tupleItems(value.ty)) |child, item| {
                            const width = (try self.layout(item, id)).len;
                            try self.test_(child, .{ .ty = item, .words = value.words[start..][0..width] }, fail, id);
                            start += width;
                        }
                    },
                    .unit => {},
                    // Children follow the pattern's Core record type order.
                    .record => try self.recordPattern(children, self.m.types.node(pattern.ty), value, fail, id),
                    else => return self.g.fail(self.m, id, "product pattern on a {s}", .{@tagName(shape.tag)}),
                }
            },
            .constructor => {
                const constructor = self.m.constructor(pattern.a);
                const cases = self.g.types.variants(value.ty) catch |err| switch (err) {
                    error.Unsupported => return self.g.typeFailure(self.m, id),
                    else => return err,
                };
                if (cases.payloads.len > 1) {
                    try self.opIndex(.local_get, value.words[0]);
                    try self.i32Const(constructor.tag);
                    try self.op(.i32_ne);
                    try self.failIf(fail, id);
                }
                if (pattern.b != 0) try self.test_(pattern.b, try self.unwrapVariant(value, constructor.tag, id), fail, id);
            },
            .record_payload => {
                if (self.g.types.node(value.ty).tag != .record) return self.g.fail(self.m, id, "record pattern on a non-record", .{});
                try self.recordPattern(self.m.patternChildren(pattern.b), self.m.types.node(pattern.ty), value, fail, id);
            },
            .invalid => return self.g.fail(self.m, id, "invalid pattern", .{}),
        }
    }
    /// Child `i` matches field `i` of the Core record type `storage`.
    fn recordPattern(self: *Fn, children: []const core.PatternId, storage: T.Node, value: Val, fail: ?u32, id: core.Id) Error!void {
        if (storage.tag != .record or storage.b < children.len) return self.g.fail(self.m, id, "record pattern without a record type", .{});
        for (children, 0..) |child, index| {
            const field = self.m.types.recordField(storage, index);
            const spelling = self.m.fieldSpelling(field.name) orelse return self.g.fail(self.m, id, "record pattern field without a spelling", .{});
            const position = self.g.types.findField(value.ty, try self.g.types.fieldName(spelling)) orelse return self.g.fail(self.m, id, "record pattern field missing", .{});
            const slice = try self.fieldSlice(value.ty, position, id);
            try self.test_(child, .{ .ty = self.g.types.recordField(value.ty, position).ty, .words = value.words[slice.start..][0..slice.len] }, fail, id);
        }
    }
    fn failIf(self: *Fn, fail: ?u32, id: core.Id) Error!void {
        if (fail) |depth| return self.br(.br_if, depth);
        _ = id;
        _ = try self.open(.if_);
        try self.op(.unreachable_);
        try self.close();
    }

    /// Copies `values` into `targets` through temporaries, so a value may
    /// read a target that an earlier assignment already overwrote.
    fn assign(self: *Fn, values: []const Val, targets: []const Val, id: core.Id) Error!void {
        const staged = try self.arena.alloc(Val, values.len);
        for (values, targets, staged) |value, target, *slot| {
            slot.* = value;
            if (value.ty == types.never or std.mem.eql(u32, value.words, target.words)) continue;
            for (targets) |other| for (other.words) |word| if (std.mem.findScalar(u32, value.words, word) != null) {
                slot.* = try self.fresh(target.ty, id);
                try self.copy(value, slot.*, id);
                break;
            };
        }
        for (staged, targets) |value, target| try self.copy(value, target, id);
    }
    fn carryVals(self: *Fn, carries: []const core.LoopCarry, comptime field: []const u8, id: core.Id) Error![]Val {
        const out = try self.arena.alloc(Val, carries.len);
        for (carries, out) |carry, *slot| slot.* = try self.fresh(try self.lower(self.m.binding(@field(carry, field)).ty, id), id);
        return out;
    }
    fn loop(self: *Fn, id: core.Id) Error!Val {
        const info = self.m.loopInfo(id);
        const carries = self.m.loopCarries(id);
        const iteration = try self.carryVals(carries, "iteration", id);
        const outgoing = try self.carryVals(carries, "outgoing", id);
        const incoming = try self.arena.alloc(Val, carries.len);
        for (carries, incoming) |carry, *slot| slot.* = self.bindings.get(carry.incoming) orelse return self.g.fail(self.m, id, "loop carry without an incoming value", .{});
        try self.assign(incoming, iteration, id);
        for (carries, iteration) |carry, value| try self.bindings.put(self.a(), carry.iteration, value);
        var index: ?Val = null;
        var end: ?Val = null;
        switch (info.kind) {
            .forever => {},
            .range => {
                index = try self.fresh(types.u32_, id);
                try self.copy(try self.expr(info.first), index.?, id);
                end = try self.fresh(types.u32_, id);
                try self.copy(try self.expr(info.end), end.?, id);
            },
            .array => return self.g.fail(self.m, id, "array loops are not supported yet", .{}),
        }
        const exit = try self.open(.block);
        const top = try self.open(.loop);
        if (index) |counter| {
            try self.opIndex(.local_get, counter.words[0]);
            try self.opIndex(.local_get, end.?.words[0]);
            try self.op(.i32_ge_u);
            _ = try self.open(.if_);
            try self.assign(iteration, outgoing, id);
            try self.br(.br, exit);
            try self.close();
            const current = try self.fresh(types.u32_, id);
            try self.copy(counter, current, id);
            try self.opIndex(.local_get, counter.words[0]);
            try self.i32Const(1);
            try self.op(.i32_add);
            try self.opIndex(.local_set, counter.words[0]);
            if (info.pattern != 0) try self.test_(info.pattern, current, null, id);
        }
        try self.labels.append(self.a(), .{ .target = id, .depth = exit, .kind = .loop, .top = top, .iteration = iteration, .outgoing = outgoing });
        const body = try self.expr(info.body);
        _ = self.labels.pop();
        if (body.ty != types.never) {
            const backedge = try self.arena.alloc(Val, carries.len);
            for (carries, backedge) |carry, *slot| slot.* = self.bindings.get(carry.backedge) orelse return self.g.fail(self.m, id, "loop carry without a backedge value", .{});
            try self.assign(backedge, iteration, id);
            try self.br(.br, top);
        }
        try self.close();
        try self.close();
        for (carries, outgoing) |carry, value| try self.bindings.put(self.a(), carry.outgoing, value);
        if (info.kind == .forever and !info.can_exit) return neverVal();
        return unitVal();
    }
    fn breakNode(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const children = self.m.breakValues(id);
        const values = try self.arena.alloc(Val, children.len);
        for (children, values) |child, *slot| slot.* = try self.expr(child);
        var at = self.labels.items.len;
        while (at != 0) {
            at -= 1;
            const label = self.labels.items[at];
            if (label.target != n.a or label.kind != .loop) continue;
            if (values.len != label.iteration.len) return self.g.fail(self.m, id, "break carries the wrong number of values", .{});
            if (n.op == .continue_) {
                try self.assign(values, label.iteration, id);
                try self.br(.br, label.top);
            } else {
                try self.assign(values, label.outgoing, id);
                try self.br(.br, label.depth);
            }
            return neverVal();
        }
        return self.g.fail(self.m, id, "break outside its loop", .{});
    }

    fn patternBind(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const value = try self.expr(n.b);
        if (n.c == 0) {
            try self.test_(n.a, value, null, id);
            return unitVal();
        }
        const ok = try self.open(.block);
        const failed = try self.open(.block);
        try self.test_(n.a, value, failed, id);
        try self.br(.br, ok);
        try self.close();
        _ = try self.expr(n.c);
        try self.op(.unreachable_);
        try self.close();
        return unitVal();
    }
};

/// The primitive a constant such as `const U32.add = @u32.add` names.
fn primitiveAlias(m: *const core.Module, binding_id: core.BindingId) ?core.Id {
    const binding = m.binding(binding_id);
    const value = if (m.body(binding_id)) |body| (if (body.is_function) return null else body.root) else binding.initializer;
    if (value == 0 or m.node(value).tag != .primitive_function) return null;
    return value;
}

/// Marks a primitive node (rather than a binding) as a partial target.
const primitive_node_bit: u32 = 0x8000_0000;

pub fn emitInstance(g: *Generator, id: u32) Error!void {
    const instance = g.instance(id);
    const m = g.unitModule(instance.key.unit);
    var arena = std.heap.ArenaAllocator.init(g.allocator);
    defer arena.deinit();
    var f: Fn = .{ .g = g, .m = m, .env = &instance.env, .arena = arena.allocator(), .instance_id = id };
    defer {
        f.code.deinit(g.allocator);
        f.locals.deinit(g.allocator);
        f.bindings.deinit(g.allocator);
        f.polymorphic.deinit(g.allocator);
        f.labels.deinit(g.allocator);
    }
    var root: core.Id = 0;
    var captures: []Val = &.{};
    var inputs: []Val = &.{};
    if (instance.closure) _ = try f.local(.i32);
    inputs = try f.arena.alloc(Val, instance.parameters.len);
    for (instance.parameters, inputs) |ty, *slot| {
        const words = try f.layout(ty, 0);
        const locals = try f.arena.alloc(u32, words.len);
        for (words, locals) |word, *local_| local_.* = try f.local(word);
        slot.* = .{ .ty = ty, .words = locals };
    }
    f.parameter_words = @intCast(f.locals.items.len);
    const saved = try f.local(.i32);
    if (instance.closure) captures = try f.loadCaptures(instance.captures, 0);
    switch (instance.key.kind) {
        .named => {
            const body = m.body(instance.key.id).?;
            for (m.bodyParameters(body), inputs) |parameter, value| try f.bindings.put(g.allocator, parameter.binding, value);
            root = body.root;
        },
        .lambda => {
            const info = m.closure(instance.key.id);
            for (m.closureCaptures(instance.key.id), captures) |binding, value| try f.bindings.put(g.allocator, binding, value);
            try f.bindings.put(g.allocator, info.parameter.binding, inputs[0]);
            root = info.body;
        },
        .partial, .primitive, .constructor => {},
    }
    const result = try f.fresh(instance.result, root);
    const exit = try f.open(.block);
    try f.labels.append(g.allocator, .{ .target = std.math.maxInt(u32), .depth = exit, .result = result, .kind = .function });
    const value = switch (instance.key.kind) {
        .named, .lambda => try f.expr(root),
        .partial, .primitive, .constructor => try f.adapterBody(instance, captures, inputs[0]),
    };
    try f.copy(value, result, root);
    try f.close();
    const release = f.allocates and !try g.holdsMemory(instance.result);
    if (release) _ = try g.stackPointer();
    if (release) {
        try f.opIndex(.local_get, saved);
        try f.opIndex(.global_set, g.stack_pointer.?);
    }
    try f.push(result);
    try f.op(.end);
    var prologue: W.Bytes = .{};
    defer prologue.deinit(g.allocator);
    if (release) {
        try prologue.byte(g.allocator, @backingInt(W.Op.global_get));
        try prologue.uleb(g.allocator, g.stack_pointer.?);
        try prologue.byte(g.allocator, @backingInt(W.Op.local_set));
        try prologue.uleb(g.allocator, saved);
    }
    try finishWith(g, instance.function, &f, prologue.items());
}

pub fn finish(g: *Generator, function: u32, f: *Fn) Error!void {
    return finishWith(g, function, f, &.{});
}

/// Encodes the body: local declarations (in runs of one type) then code.
fn finishWith(g: *Generator, function: u32, f: *Fn, prologue: []const u8) Error!void {
    var out: W.Bytes = .{};
    defer out.deinit(g.allocator);
    const declared = f.locals.items[f.parameter_words..];
    var runs: usize = 0;
    var at: usize = 0;
    while (at < declared.len) : (runs += 1) {
        var end = at + 1;
        while (end < declared.len and declared[end] == declared[at]) end += 1;
        at = end;
    }
    try out.uleb(g.allocator, runs);
    at = 0;
    while (at < declared.len) {
        var end = at + 1;
        while (end < declared.len and declared[end] == declared[at]) end += 1;
        try out.uleb(g.allocator, end - at);
        try out.byte(g.allocator, @backingInt(declared[at]));
        at = end;
    }
    try out.raw(g.allocator, prologue);
    try out.raw(g.allocator, f.code.items());
    try g.module.setBody(function, out.items());
}

/// An exported entry: converts its one ABI argument, calls the instance and
/// converts the result.
pub fn emitExport(g: *Generator, m: *const core.Module, body: *const core.Body, abi: *W.Bytes) Error!void {
    const parameters = m.bodyParameters(body);
    var empty: types.Env = .empty;
    const ty = g.types.lower(m, m.binding(body.binding).ty, &empty) catch |err| switch (err) {
        error.Unsupported => return g.typeFailure(m, body.root),
        else => return err,
    };
    const instance_id = try g.named(.{ .unit = m.unit, .binding = body.binding }, ty, m, body.root);
    const instance = g.instance(instance_id);
    const parameter = instance.parameters[0];
    const parameter_abi = try abiScalar(g, m, body.root, parameter);
    const result_abi = try abiScalar(g, m, body.root, instance.result);
    const machine = struct {
        fn of(kind: u8) W.ValType {
            return if (kind == 3) .f32 else .i32;
        }
    };
    const signature = try g.module.signature(&.{machine.of(parameter_abi)}, &.{machine.of(result_abi)});
    const function = try g.module.addFunction(signature);
    var arena = std.heap.ArenaAllocator.init(g.allocator);
    defer arena.deinit();
    var f: Fn = .{ .g = g, .m = m, .env = &empty, .arena = arena.allocator() };
    defer {
        f.code.deinit(g.allocator);
        f.locals.deinit(g.allocator);
    }
    _ = try f.local(machine.of(parameter_abi));
    f.parameter_words = 1;
    if (parameter != types.unit) try f.opIndex(.local_get, 0);
    try f.opIndex(.call, instance.function);
    if (instance.result == types.unit) try f.i32Const(0);
    try f.op(.end);
    try finish(g, function, &f);
    const name = m.name(body.export_name);
    try g.module.exportItem(name, .function, function);
    try abi.name(g.allocator, name);
    try abi.byte(g.allocator, parameter_abi);
    try abi.byte(g.allocator, result_abi);
    _ = parameters;
}

fn abiScalar(g: *Generator, m: *const core.Module, id: core.Id, ty: Ty) Error!u8 {
    return switch (g.types.node(ty).tag) {
        .unit => 0,
        .u32 => 1,
        .boolean => 2,
        .f32 => 3,
        else => g.fail(m, id, "entry values of type {s} are not supported yet", .{@tagName(g.types.node(ty).tag)}),
    };
}
