//! One instance's Wasm body. A single pass over its Core body; every value is a
//! list of Wasm locals in its type's layout, so projections share locals.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const W = @import("writer.zig");
const types = @import("types.zig");
const emit = @import("emit.zig");
const runtime = @import("runtime.zig");
const storage_ops = @import("../check/storage_ops.zig");
const Ty = types.Ty;
const Val = emit.Val;
const Generator = emit.Generator;
const Error = emit.Error;
const A = std.mem.Allocator;

/// A Core block or loop that `return_`/`break_` can leave, at a Wasm depth.
const Label = struct {
    target: core.Id,
    depth: u32,
    /// Allocated by the first value that leaves the block.
    result: *?Val,
    /// function: the body's own exit, the target of every unmatched return.
    kind: enum { block, loop, function } = .block,
    /// Loops: the backedge target depth, current iteration and exit values.
    top: u32 = 0,
    iteration: []const Val = &.{},
    outgoing: []const Val = &.{},
    /// Owner and stack mark locals an iteration releases to, and whether a
    /// `continue` already released to them.
    release: ?[2]u32 = null,
    used: bool = false,
    /// Carries held in loop slots (boxed values copied in place).
    slots: []const bool = &.{},
};

pub const Fn = struct {
    g: *Generator,
    m: *const core.Module,
    /// The instance's type variables, refined as emission learns the
    /// concrete type of each expression (dependent field/element results).
    env: *types.Env,
    arena: A,
    instance_id: u32 = 0,
    /// The call node whose arguments are being typed.
    current_call: core.Id = 0,
    /// Set while evaluating a direct field value of a record literal.
    field_value: bool = false,
    /// Reference counts of this unit's local bindings, built on first use.
    use_counts: ?std.AutoHashMapUnmanaged(core.BindingId, u32) = null,
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
    /// Allocation events so far, so a loop can tell whether its body allocated.
    allocations: u32 = 0,

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
            error.Unsupported => {
                // Values refined since the instance began may now decide
                // the enclosing body's obligations (a collection's element).
                if (self.enclosingBody()) |body| {
                    const before = self.env.count();
                    try self.g.solveObligationsPublic(self.m, body.scheme.obligations, self.env);
                    if (self.env.count() != before) if (self.g.types.lower(self.m, ty, self.env)) |found| {
                        self.g.dropFailure();
                        return found;
                    } else |_| {};
                }
                return self.g.typeFailure(self.m, id);
            },
            else => return err,
        };
    }
    /// The named body this instance's code belongs to (a lambda's enclosing
    /// named instance), in this unit.
    fn enclosingBody(self: *Fn) ?*const core.Body {
        var instance = self.g.instance(self.instance_id);
        for (0..64) |_| {
            if (instance.key.unit != self.m.unit) return null;
            switch (instance.key.kind) {
                .lambda => instance = self.g.instance(instance.key.parent),
                .named => return self.m.body(instance.key.id),
                else => return null,
            }
        }
        return null;
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
        if (from.words.len != to.words.len) return self.g.fail(self.m, id, "value layout mismatch ({s} of {d} words into {s} of {d})", .{ @tagName(self.tagOf(from.ty)), from.words.len, @tagName(self.tagOf(to.ty)), to.words.len });
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

    /// An operand: if it diverges, so does the expression using it.
    pub fn expr(self: *Fn, id: core.Id) Error!Val {
        const value = try self.stmt(id);
        if (value.ty == types.never) return error.Diverged;
        return value;
    }
    /// A value that may diverge (statements, branches, bodies). An
    /// unsupported form is recorded and compiled as a trap, so one build
    /// reports every missing form; the compilation still fails.
    pub fn stmt(self: *Fn, id: core.Id) Error!Val {
        // Only the field's own reference node may see the field flag.
        const field_value = self.field_value;
        defer self.field_value = field_value;
        if (id == 0 or self.m.node(id).tag != .reference) self.field_value = false;
        const depth = self.depth;
        const labels = self.labels.items.len;
        const value = self.exprInner(id) catch |err| switch (err) {
            error.Unsupported, error.Diverged => {
                if (err == error.Unsupported) try self.g.recordFailure(self.m, id);
                // The rest is unreachable; close what the operand left open.
                while (self.depth > depth) try self.close();
                self.labels.shrinkRetainingCapacity(labels);
                try self.op(.unreachable_);
                return neverVal();
            },
            else => return err,
        };
        if (value.ty != types.never and id != 0) try self.refine(self.m.typeOf(id), value.ty);
        return value;
    }
    /// Binds the variables of Core type `ty` that `actual` determines.
    fn refine(self: *Fn, ty: T.Id, actual: Ty) Error!void {
        if (ty <= T.never) return;
        if (self.g.types.closed.contains(.{ .unit = self.m.unit, .ty = ty })) return;
        try self.g.types.match(self.m, ty, actual, self.env);
    }
    fn exprInner(self: *Fn, id: core.Id) Error!Val {
        // Node zero is an absent value, such as a bare `return ()`.
        if (id == 0) return unitVal();
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
                for (self.m.children(id)) |child| last = try self.stmt(child);
                break :blk if (last.ty == types.never) last else unitVal();
            },
            .bind => blk: {
                // A generalized local closure is built at each use, at that
                // use's types; its captures are already immutable values.
                const deferred = switch (self.m.node(n.b).tag) {
                    .closure, .constructor_function, .primitive_function, .reference => true,
                    // A pure partial application, rebuilt at each use's types.
                    .call => self.partialCall(n.b),
                    .apply => self.partialApply(n.b),
                    else => false,
                };
                if (deferred and self.m.binding(n.a).scheme.variables.len != 0) {
                    try self.polymorphic.put(self.a(), n.a, n.b);
                    break :blk unitVal();
                }
                if (try self.linearAppend(n.b)) |grown| {
                    try self.bindings.put(self.a(), n.a, grown);
                    break :blk unitVal();
                }
                const value = try self.stmt(n.b);
                if (value.ty != types.never) try self.refine(self.m.binding(n.a).ty, value.ty);
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
            .array => self.arrayLiteral(id),
            .array_op => self.arrayOp(id),
            .storage => self.storageOp(id),
            .record_merge => self.recordMerge(id),
            .result_associated => self.resultAssociated(id),
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
        return self.referenceInner(id) catch |err| switch (err) {
            error.Unsupported => {
                // Name the binding: a generic function value needs annotations.
                const target = self.g.resolve(self.m, self.m.reference(id));
                const tm = self.g.unitModule(target.unit);
                if (tm.body(target.binding)) |body| if (self.g.failure) |failure| if (std.mem.find(u8, failure.message, "unresolved type variable") != null) {
                    const cause = try self.a().dupe(u8, failure.message);
                    defer self.a().free(cause);
                    self.g.dropFailure();
                    return self.g.fail(self.m, id, "value of `{s}` (unit {d}) has a type its uses leave open [{s}]", .{ tm.name(body.declaration_name), target.unit, cause });
                };
                return err;
            },
            else => return err,
        };
    }
    fn referenceInner(self: *Fn, id: core.Id) Error!Val {
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
        var holed = false;
        const ty = self.g.types.lower(self.m, self.m.typeOf(id), self.env) catch |err| switch (err) {
            error.Unsupported => blk: {
                // Variables no use here determines may only sit inside
                // function types: such a function can never be called here.
                const partial_ty = try self.g.types.lowerHoles(self.m, self.m.typeOf(id), self.env);
                if (!self.holesOnlyInFunctions(partial_ty)) return self.g.typeFailure(self.m, id);
                holed = true;
                break :blk partial_ty;
            },
            else => return err,
        };
        // Holes no use can reach: variables the checker left ambiguous, or
        // ones this instance's key already left unused.
        const unused = holed and try self.holesUnused(self.m.typeOf(id), 0);
        if (holed and self.tagOf(ty) == .function) {
            // A function stored as a field of a literal record can go unused
            // at a type no use fixes; otherwise its holes must be unused.
            if (!self.field_value and !unused) return self.g.typeFailure(self.m, id);
            return self.trapClosure(ty, id);
        }
        if (primitiveAlias(tm, target.binding) != null) return self.partial(.primitive, target, ty, &.{}, id);
        if (tm.body(target.binding)) |body| {
            if (body.is_function) return self.partial(.partial, target, ty, &.{}, id);
            switch (self.tagOf(ty)) {
                .array, .grow, .resize => return self.pool(target, ty, id),
                else => {},
            }
            // A constant: its instance computes the value.
            const instance = try self.g.namedWith(target, ty, unused, self.m, id);
            try self.opIndex(.call, self.g.instance(instance).function);
            return self.received(ty, id);
        }
        return self.g.fail(self.m, id, "reference to a {s} binding without a value", .{@tagName(binding.kind)});
    }
    /// Whether every variable of Core type `ty` that the environment leaves
    /// unbound is unused: ambiguous (no scheme quantifies it), or quantified
    /// by this instance's binding when its key's holes are unused.
    fn holesUnused(self: *Fn, ty: T.Id, depth: usize) Error!bool {
        if (ty <= T.never) return true;
        if (depth > 64) return false;
        const n = self.m.types.node(ty);
        switch (n.tag) {
            .variable => {
                if (self.env.contains(.{ .unit = self.m.unit, .ty = ty })) return true;
                if (!try self.g.isQuantified(self.m, ty)) return true;
                const instance = self.g.instance(self.instance_id);
                if (!instance.unused_holes or instance.key.kind != .named or instance.key.unit != self.m.unit) return false;
                return std.mem.findScalar(T.Id, self.m.types.list(self.m.binding(instance.key.id).scheme.variables), ty) != null;
            },
            .bound => return self.env.contains(.{ .unit = self.m.unit, .ty = ty }),
            .usage, .forall, .array, .list, .cursor => return self.holesUnused(n.a, depth + 1),
            .function => return try self.holesUnused(n.a, depth + 1) and try self.holesUnused(n.b, depth + 1),
            .product => {
                for (self.m.types.list(.{ .start = n.a, .len = n.b })) |child| if (!try self.holesUnused(child, depth + 1)) return false;
                return true;
            },
            .record => {
                for (0..n.b) |index| if (!try self.holesUnused(self.m.types.recordField(n, index).ty, depth + 1)) return false;
                return true;
            },
            .nominal => {
                for (self.m.types.nominalArguments(n)) |argument| if (!try self.holesUnused(argument, depth + 1)) return false;
                return true;
            },
            else => return false,
        }
    }
    /// Whether no hole (`never`) of `ty` affects its layout: holes may sit
    /// under function and container types, whose layouts are fixed.
    fn holesOnlyInFunctions(self: *Fn, ty: Ty) bool {
        return self.layoutFree(ty, 0);
    }
    fn layoutFree(self: *Fn, ty: Ty, depth: usize) bool {
        if (depth > 32) return false;
        const n = self.g.types.node(ty);
        return switch (n.tag) {
            .never => false,
            .function, .array, .list, .cursor, .grow, .resize, .ref, .view, .link => true,
            .tuple => for (self.g.types.tupleItems(ty)) |item| {
                if (!self.layoutFree(item, depth + 1)) break false;
            } else true,
            .record => for (0..n.b) |index| {
                if (!self.layoutFree(self.g.types.recordField(ty, index).ty, depth + 1)) break false;
            } else true,
            .nominal => blk: {
                const cases = self.g.types.variants(ty) catch break :blk false;
                for (cases.payloads) |payload| if (payload != ty and !self.layoutFree(payload, depth + 1)) break :blk false;
                break :blk true;
            },
            else => true,
        };
    }
    /// A closure of a type no use determines: calling it traps.
    fn trapClosure(self: *Fn, ty: Ty, id: core.Id) Error!Val {
        // Never called, so one shared `(env) -> ()` body serves every type.
        const key: emit.InstanceKey = .{ .kind = .trap, .unit = self.m.unit, .id = 0, .ty = types.unit };
        const instance = self.g.find(key) orelse try self.g.addInstanceWith(key, .empty, try self.g.arena.allocator().dupe(Ty, &.{types.unit}), types.unit, true, &.{}, self.m, id);
        self.g.trap_closures += 1;
        return self.makeClosure(instance, ty, &.{}, id);
    }
    /// Pops a call result; a result that may refer to scope memory makes
    /// this body responsible for releasing it.
    fn received(self: *Fn, ty: Ty, id: core.Id) Error!Val {
        if (try self.g.holdsMemory(ty)) self.noteAllocation();
        return self.pop(ty, id);
    }

    /// Allocates `bytes` of scope memory and returns its address local.
    fn allocate(self: *Fn, bytes: u32) Error!u32 {
        self.noteAllocation();
        const rt = try self.g.runtime_();
        const address = try self.local(.i32);
        try self.i32Const(bytes);
        try self.opIndex(.call, rt.stack);
        try self.opIndex(.local_set, address);
        return address;
    }
    fn noteAllocation(self: *Fn) void {
        self.allocates = true;
        self.allocations += 1;
    }
    /// Code that records the current owner and stack marks into locals.
    fn markInto(self: *Fn, out: *W.Bytes, owner_mark: u32, stack_mark: u32) Error!void {
        const rt = try self.g.runtime_();
        try out.byte(self.a(), @backingInt(W.Op.global_get));
        try out.uleb(self.a(), rt.owner_top);
        try out.byte(self.a(), @backingInt(W.Op.local_set));
        try out.uleb(self.a(), owner_mark);
        try out.byte(self.a(), @backingInt(W.Op.global_get));
        try out.uleb(self.a(), rt.stack_pointer);
        try out.byte(self.a(), @backingInt(W.Op.local_set));
        try out.uleb(self.a(), stack_mark);
    }
    /// Releases every owner and stack byte allocated since the marks.
    fn releaseTo(self: *Fn, owner_mark: u32, stack_mark: u32) Error!void {
        const rt = try self.g.runtime_();
        try self.opIndex(.local_get, owner_mark);
        try self.opIndex(.call, rt.release);
        try self.opIndex(.local_get, stack_mark);
        try self.opIndex(.global_set, rt.stack_pointer);
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
        const ty = self.g.types.lower(self.m, self.m.typeOf(id), self.env) catch |err| switch (err) {
            error.Unsupported => return self.inferredClosure(id),
            else => return err,
        };
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

    /// A lambda whose parameter type is known but whose result only its
    /// body determines: its instance is emitted now to learn the result.
    fn inferredClosure(self: *Fn, id: core.Id) Error!Val {
        const info = self.m.closure(id);
        const parameter = try self.lower(info.parameter.ty, id);
        const capture_ids = self.m.closureCaptures(id);
        const captures = try self.arena.alloc(Val, capture_ids.len);
        for (capture_ids, captures) |binding, *slot| slot.* = self.bindings.get(binding) orelse return self.g.fail(self.m, id, "closure capture without a value", .{});
        const marker = try self.g.types.function(parameter, types.never);
        const key: emit.InstanceKey = .{ .kind = .lambda, .unit = self.m.unit, .id = id, .ty = marker, .parent = self.instance_id };
        const instance = self.g.find(key) orelse blk: {
            const capture_types = try self.g.arena.allocator().alloc(Ty, captures.len);
            for (captures, capture_types) |capture, *slot| slot.* = capture.ty;
            var env: types.Env = .empty;
            var it = self.env.iterator();
            while (it.next()) |entry| try env.put(self.a(), entry.key_ptr.*, entry.value_ptr.*);
            const parameters = try self.g.arena.allocator().dupe(Ty, &.{parameter});
            break :blk try self.g.inferClosure(key, env, parameters, capture_types, self.m, id);
        };
        const ty = try self.g.types.function(parameter, self.g.instance(instance).result);
        try self.refine(self.m.typeOf(id), ty);
        return self.makeClosure(instance, ty, captures, id);
    }
    /// Calls the closure `callee` with one argument.
    fn applyClosure(self: *Fn, callee: Val, argument: Val, id: core.Id) Error!Val {
        const arrow = self.g.types.node(callee.ty);
        if (arrow.tag != .function or callee.words.len != 2) return self.g.fail(self.m, id, "application of a non-function value", .{});
        if ((try self.layout(arrow.a, id)).len != argument.words.len)
            return self.g.fail(self.m, id, "closure argument of {d} words for a {s} parameter of {d} words", .{ argument.words.len, @tagName(self.tagOf(arrow.a)), (try self.layout(arrow.a, id)).len });
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

    /// A global array constant: one persistent owner per instance,
    /// initialized on first use.
    fn pool(self: *Fn, target: core.BindingRef, ty: Ty, id: core.Id) Error!Val {
        const key: emit.InstanceKey = .{ .kind = .pool, .unit = target.unit, .id = target.binding, .ty = ty };
        const instance = self.g.find(key) orelse blk: {
            const created = try self.g.addInstanceWith(key, .empty, &.{}, ty, false, &.{}, self.m, id);
            try self.g.pool_globals.put(self.a(), created, .{ try self.g.module.addGlobal(.i32, true, 0), try self.g.module.addGlobal(.i32, true, 0), try self.g.module.addGlobal(.i32, true, 0) });
            break :blk created;
        };
        try self.opIndex(.call, self.g.instance(instance).function);
        return self.pop(ty, id);
    }
    fn poolBody(self: *Fn, instance: *const emit.Instance) Error!Val {
        const globals = self.g.pool_globals.get(self.instance_id).?;
        const rt = try self.g.runtime_();
        const key = instance.key;
        try self.opIndex(.global_get, globals[2]);
        try self.i32Const(1);
        try self.op(.i32_ne);
        _ = try self.open(.if_);
        // Initialization cycles trap.
        try self.opIndex(.global_get, globals[2]);
        try self.i32Const(2);
        try self.op(.i32_eq);
        try self.trap();
        try self.i32Const(2);
        try self.opIndex(.global_set, globals[2]);
        const marks: [2]u32 = .{ try self.local32(), try self.local32() };
        var prefix: W.Bytes = .{};
        defer prefix.deinit(self.a());
        try self.markInto(&prefix, marks[0], marks[1]);
        try self.code.raw(self.a(), prefix.items());
        const value_instance = try self.g.named(.{ .unit = key.unit, .binding = key.id }, key.ty, self.m, 0);
        try self.opIndex(.call, self.g.instance(value_instance).function);
        const value = try self.pop(key.ty, 0);
        try self.opIndex(.local_get, value.words[0]);
        try self.opIndex(.local_get, value.words[1]);
        try self.i32Const(try self.stride(try self.elementOf(key.ty, 0), 0));
        try self.i32Const(@intFromBool(self.growable(key.ty)));
        try self.opIndex(.call, rt.persist);
        try self.opIndex(.global_set, globals[1]);
        try self.opIndex(.global_set, globals[0]);
        try self.releaseTo(marks[0], marks[1]);
        try self.i32Const(1);
        try self.opIndex(.global_set, globals[2]);
        try self.close();
        const result = try self.fresh(key.ty, 0);
        try self.opIndex(.global_get, globals[0]);
        try self.opIndex(.local_set, result.words[0]);
        try self.opIndex(.global_get, globals[1]);
        try self.opIndex(.local_set, result.words[1]);
        return result;
    }

    // ----- host boundary -----------------------------------------------

    /// A fresh fixed array copied from the host packet at `packet` (a local).
    fn fromPacket(self: *Fn, ty: Ty, packet: u32) Error!Val {
        const rt = try self.g.runtime_();
        const length = try self.local32();
        try self.opIndex(.local_get, packet);
        try self.opIndex(.call, rt.packet_length);
        try self.opIndex(.local_set, length);
        const array_ty = try self.g.types.intern(.array, &.{self.g.types.node(ty).a});
        const handle = try self.create(array_ty, length, 0);
        const base = try self.baseOf(handle);
        try self.opIndex(.local_get, base);
        try self.opIndex(.local_get, packet);
        try self.i32Const(4);
        try self.op(.i32_add);
        try self.opIndex(.local_get, length);
        try self.i32Const(4);
        try self.op(.i32_mul);
        try self.op(.prefix_fc);
        try self.code.uleb(self.a(), 10);
        try self.code.byte(self.a(), 0);
        try self.code.byte(self.a(), 0);
        return .{ .ty = ty, .words = handle.words };
    }
    /// Copies an array into a fresh host packet; returns its address local.
    fn toPacket(self: *Fn, value: Val, id: core.Id) Error!u32 {
        const rt = try self.g.runtime_();
        const length = try self.lengthOf(value, id);
        try self.i32Const(0);
        try self.opIndex(.call, rt.reset);
        try self.op(.drop);
        const packet = try self.local32();
        try self.opIndex(.local_get, length);
        try self.i32Const(4);
        try self.op(.i32_mul);
        try self.i32Const(4);
        try self.op(.i32_add);
        try self.opIndex(.call, rt.allocate);
        try self.opIndex(.local_tee, packet);
        try self.opIndex(.local_get, length);
        try self.op(.i32_store);
        try self.code.uleb(self.a(), 2);
        try self.code.uleb(self.a(), 0);
        _ = try self.open(.block);
        try self.opIndex(.local_get, length);
        try self.op(.i32_eqz);
        try self.opIndex(.br_if, 0);
        const base = try self.baseOf(value);
        try self.opIndex(.local_get, packet);
        try self.i32Const(4);
        try self.op(.i32_add);
        try self.opIndex(.local_get, base);
        try self.opIndex(.local_get, length);
        try self.i32Const(4);
        try self.op(.i32_mul);
        try self.op(.prefix_fc);
        try self.code.uleb(self.a(), 10);
        try self.code.byte(self.a(), 0);
        try self.code.byte(self.a(), 0);
        try self.close();
        return packet;
    }
    /// A closure calling host callback `slot` of table 1.
    fn hostClosure(self: *Fn, ty: Ty, kinds: [2]Abi, slot: u32) Error!Val {
        const import = try hostImport(self.g, kinds);
        const key: emit.InstanceKey = .{ .kind = .host, .unit = self.m.unit, .id = import, .ty = ty };
        const arrow = self.g.types.node(ty);
        const instance = self.g.find(key) orelse try self.g.addInstanceWith(key, .empty, try self.g.arena.allocator().dupe(Ty, &.{arrow.a}), arrow.b, true, try self.g.arena.allocator().dupe(Ty, &.{types.u32_}), self.m, 0);
        const captured = try self.constLocal(slot);
        return self.makeClosure(instance, ty, &.{.{ .ty = types.u32_, .words = try self.arena.dupe(u32, &.{captured}) }}, 0);
    }
    /// The host adapter body: converts the argument, calls the import with
    /// the callback's externref and converts the result.
    fn hostBody(self: *Fn, instance: *const emit.Instance, captures: []const Val, argument: Val) Error!Val {
        const arrow = self.g.types.node(instance.key.ty);
        const kinds = callbackAbi(self.g, instance.key.ty) orelse return self.g.fail(self.m, 0, "host callback shape", .{});
        var packet: ?u32 = null;
        if (isArray(kinds[0])) packet = try self.toPacket(argument, 0);
        try self.opIndex(.local_get, captures[0].words[0]);
        try self.opIndex(.table_get, 1);
        if (packet) |address| try self.opIndex(.local_get, address) else if (kinds[0] == .unit) try self.i32Const(0) else try self.push(argument);
        try self.opIndex(.call, instance.key.id);
        if (isArray(kinds[1])) {
            const address = try self.local32();
            try self.opIndex(.local_set, address);
            self.noteAllocation();
            return self.fromPacket(arrow.b, address);
        }
        if (kinds[1] == .unit) {
            try self.op(.drop);
            return unitVal();
        }
        return self.pop(arrow.b, 0);
    }

    // ----- storage -----------------------------------------------------

    fn isBoxed(self: *Fn, ty: Ty, id: core.Id) Error!bool {
        return self.g.types.boxed(ty) catch |err| switch (err) {
            error.Unsupported => return self.g.typeFailure(self.m, id),
            else => return err,
        };
    }
    fn flatBytes(self: *Fn, ty: Ty, id: core.Id) Error!u32 {
        return self.g.types.flatBytes(ty) catch |err| switch (err) {
            error.Unsupported => return self.g.typeFailure(self.m, id),
            else => return err,
        };
    }
    /// A fresh scope block holding one boxed value of `ty`.
    fn newBlock(self: *Fn, ty: Ty, id: core.Id) Error!u32 {
        return self.allocate(try self.flatBytes(ty, id));
    }
    fn memoryCopy(self: *Fn, to: u32, to_offset: u32, from: u32, bytes: u32) Error!void {
        try self.opIndex(.local_get, to);
        if (to_offset != 0) {
            try self.i32Const(to_offset);
            try self.op(.i32_add);
        }
        try self.opIndex(.local_get, from);
        try self.i32Const(bytes);
        try self.op(.prefix_fc);
        try self.code.uleb(self.a(), 10);
        try self.code.byte(self.a(), 0);
        try self.code.byte(self.a(), 0);
    }
    /// Writes `value` in flat form at `base + offset`.
    fn writeFlat(self: *Fn, base: u32, offset: u32, value: Val, id: core.Id) Error!void {
        if (value.ty == types.never) return;
        if (try self.isBoxed(value.ty, id)) return self.memoryCopy(base, offset, value.words[0], try self.flatBytes(value.ty, id));
        try self.storeAt(base, offset, value);
    }
    /// Reads a value of `ty` at `base + offset` of an immutable block: a
    /// boxed value shares the block, others load into locals.
    fn readFlat(self: *Fn, base: u32, offset: u32, ty: Ty, id: core.Id) Error!Val {
        if (try self.isBoxed(ty, id)) {
            const pointer = try self.local(.i32);
            try self.opIndex(.local_get, base);
            try self.i32Const(offset);
            try self.op(.i32_add);
            try self.opIndex(.local_set, pointer);
            return .{ .ty = ty, .words = try self.arena.dupe(u32, &.{pointer}) };
        }
        return self.loadAt(base, offset, ty, id);
    }
    /// Element reads copy: storage elements change through their owner.
    fn loadElement(self: *Fn, address: u32, offset: u32, ty: Ty, id: core.Id) Error!Val {
        if (try self.isBoxed(ty, id)) {
            const memory_block = try self.newBlock(ty, id);
            try self.memoryCopy(memory_block, 0, address, try self.flatBytes(ty, id));
            if (offset != 0) return self.g.fail(self.m, id, "offset boxed element read", .{});
            return .{ .ty = ty, .words = try self.arena.dupe(u32, &.{memory_block}) };
        }
        return self.loadAt(address, offset, ty, id);
    }
    /// Byte offset of record field `index` in flat form.
    fn fieldOffset(self: *Fn, ty: Ty, index: usize, id: core.Id) Error!u32 {
        var offset: u32 = 0;
        for (0..index) |before| offset += try self.flatBytes(self.g.types.recordField(ty, before).ty, id);
        return offset;
    }
    fn itemOffset(self: *Fn, ty: Ty, index: usize, id: core.Id) Error!u32 {
        var offset: u32 = 0;
        for (self.g.types.tupleItems(ty)[0..index]) |item| offset += try self.flatBytes(item, id);
        return offset;
    }
    /// Field `position` of a record value, boxed or not.
    fn recordField(self: *Fn, record: Val, position: usize, id: core.Id) Error!Val {
        const field_ty = self.g.types.recordField(record.ty, position).ty;
        if (try self.isBoxed(record.ty, id)) return self.readFlat(record.words[0], try self.fieldOffset(record.ty, position, id), field_ty, id);
        const slice = try self.fieldSlice(record.ty, position, id);
        return .{ .ty = field_ty, .words = record.words[slice.start..][0..slice.len] };
    }
    fn tupleItem(self: *Fn, tuple: Val, index: usize, id: core.Id) Error!Val {
        const items = self.g.types.tupleItems(tuple.ty);
        if (try self.isBoxed(tuple.ty, id)) return self.readFlat(tuple.words[0], try self.itemOffset(tuple.ty, index, id), items[index], id);
        var start: usize = 0;
        for (items[0..index]) |item| start += (try self.layout(item, id)).len;
        return .{ .ty = items[index], .words = tuple.words[start..][0..(try self.layout(items[index], id)).len] };
    }
    fn wordBytes(kind: W.ValType) u32 {
        return if (kind == .v128) 16 else 4;
    }
    /// Bytes per element of a container holding `element`.
    fn stride(self: *Fn, element: Ty, id: core.Id) Error!u32 {
        return @max(try self.flatBytes(element, id), 4);
    }
    fn storeAt(self: *Fn, address: u32, offset: u32, value: Val) Error!void {
        var at = offset;
        for (value.words) |word| {
            const kind = self.locals.items[word];
            try self.opIndex(.local_get, address);
            try self.opIndex(.local_get, word);
            switch (kind) {
                .f32 => try self.op(.f32_store),
                .v128 => {
                    try self.op(.prefix_fd);
                    try self.code.uleb(self.a(), 11);
                },
                else => try self.op(.i32_store),
            }
            try self.code.uleb(self.a(), if (kind == .v128) 4 else 2);
            try self.code.uleb(self.a(), at);
            at += wordBytes(kind);
        }
    }
    fn loadAt(self: *Fn, address: u32, offset: u32, ty: Ty, id: core.Id) Error!Val {
        const value = try self.fresh(ty, id);
        var at = offset;
        for (value.words) |word| {
            const kind = self.locals.items[word];
            try self.opIndex(.local_get, address);
            switch (kind) {
                .f32 => try self.op(.f32_load),
                .v128 => {
                    try self.op(.prefix_fd);
                    try self.code.uleb(self.a(), 0);
                },
                else => try self.op(.i32_load),
            }
            try self.code.uleb(self.a(), if (kind == .v128) 4 else 2);
            try self.code.uleb(self.a(), at);
            try self.opIndex(.local_set, word);
            at += wordBytes(kind);
        }
        return value;
    }
    fn tagOf(self: *Fn, ty: Ty) types.Tag {
        return self.g.types.node(ty).tag;
    }
    fn elementOf(self: *Fn, ty: Ty, id: core.Id) Error!Ty {
        return switch (self.tagOf(ty)) {
            .array, .list, .grow, .resize, .view, .ref, .link => self.g.types.node(ty).a,
            else => self.g.fail(self.m, id, "storage operation on a {s}", .{@tagName(self.tagOf(ty))}),
        };
    }
    fn growable(self: *Fn, ty: Ty) bool {
        const tag = self.tagOf(ty);
        return tag == .grow or tag == .resize;
    }
    fn local32(self: *Fn) Error!u32 {
        return self.local(.i32);
    }
    /// A fresh owner of `ty` (a container) with `length` zeroed elements.
    fn create(self: *Fn, ty: Ty, length: u32, id: core.Id) Error!Val {
        const rt = try self.g.runtime_();
        self.noteAllocation();
        const element = try self.elementOf(ty, id);
        try self.opIndex(.local_get, length);
        try self.i32Const(try self.stride(element, id));
        try self.i32Const(@intFromBool(self.growable(ty)));
        try self.opIndex(.call, rt.create);
        return self.pop(ty, id);
    }
    /// The address of element 0 of an owner handle.
    fn baseOf(self: *Fn, handle: Val) Error!u32 {
        const rt = try self.g.runtime_();
        const base = try self.local32();
        try self.opIndex(.local_get, handle.words[0]);
        try self.opIndex(.local_get, handle.words[1]);
        try self.opIndex(.call, rt.check);
        try self.op(.i32_load);
        try self.code.uleb(self.a(), 2);
        try self.code.uleb(self.a(), runtime.entry_base);
        try self.opIndex(.local_set, base);
        return base;
    }
    fn lengthOf(self: *Fn, container: Val, id: core.Id) Error!u32 {
        const rt = try self.g.runtime_();
        if (self.tagOf(container.ty) == .view) return container.words[3];
        _ = try self.elementOf(container.ty, id);
        const length = try self.local32();
        try self.opIndex(.local_get, container.words[0]);
        try self.opIndex(.local_get, container.words[1]);
        try self.opIndex(.call, rt.length);
        try self.opIndex(.local_set, length);
        return length;
    }
    /// The checked address of element `index` (a local) of a container or
    /// view; views check their own range first.
    fn elementAddress(self: *Fn, container: Val, index: u32, id: core.Id) Error!u32 {
        const rt = try self.g.runtime_();
        const element = try self.elementOf(container.ty, id);
        var position = index;
        if (self.tagOf(container.ty) == .view) {
            try self.opIndex(.local_get, index);
            try self.opIndex(.local_get, container.words[3]);
            try self.op(.i32_ge_u);
            try self.trap();
            position = try self.local32();
            try self.opIndex(.local_get, container.words[2]);
            try self.opIndex(.local_get, index);
            try self.op(.i32_add);
            try self.opIndex(.local_set, position);
        }
        const address = try self.local32();
        try self.opIndex(.local_get, container.words[0]);
        try self.opIndex(.local_get, container.words[1]);
        try self.opIndex(.local_get, position);
        try self.i32Const(try self.stride(element, id));
        try self.opIndex(.call, rt.address);
        try self.opIndex(.local_set, address);
        return address;
    }
    /// Traps when the i32 on the stack is nonzero.
    fn trap(self: *Fn) Error!void {
        _ = try self.open(.if_);
        try self.op(.unreachable_);
        try self.close();
    }
    fn scalarLocal(self: *Fn, value: Val, id: core.Id) Error!u32 {
        if (value.words.len != 1) return self.g.fail(self.m, id, "expected a scalar", .{});
        return value.words[0];
    }
    fn readElement(self: *Fn, container: Val, index: u32, id: core.Id) Error!Val {
        const address = try self.elementAddress(container, index, id);
        return self.loadElement(address, 0, try self.elementOf(container.ty, id), id);
    }
    fn constLocal(self: *Fn, value: u32) Error!u32 {
        const local_ = try self.local32();
        try self.i32Const(value);
        try self.opIndex(.local_set, local_);
        return local_;
    }

    fn arrayLiteral(self: *Fn, id: core.Id) Error!Val {
        const children = self.m.children(id);
        // An empty literal whose element type no use can fix holds no
        // element: its unused variables are Unit.
        const ty = self.g.types.lower(self.m, self.m.typeOf(id), self.env) catch |err| switch (err) {
            error.Unsupported => if (children.len == 0 and try self.holesUnused(self.m.typeOf(id), 0))
                try self.g.types.lowerFilled(self.m, self.m.typeOf(id), self.env, types.unit)
            else
                return self.g.typeFailure(self.m, id),
            else => return err,
        };
        const values = try self.arena.alloc(Val, children.len);
        for (children, values) |child, *slot| slot.* = try self.expr(child);
        const handle = try self.create(ty, try self.constLocal(@intCast(children.len)), id);
        if (children.len == 0) return handle;
        const base = try self.baseOf(handle);
        const step = try self.stride(try self.elementOf(ty, id), id);
        for (values, 0..) |value, index| try self.writeFlat(base, @intCast(index * step), value, id);
        return handle;
    }

    fn arrayOp(self: *Fn, id: core.Id) Error!Val {
        const operation = self.m.arrayOperation(id);
        const children = self.m.children(id);
        // Operations whose operands decide the result type look at them
        // when the node's own type is still open.
        const declared: ?Ty = self.g.types.lower(self.m, self.m.typeOf(id), self.env) catch |err| switch (err) {
            error.Unsupported => null,
            else => return err,
        };
        switch (operation) {
            .length, .get, .fill, .generate => {},
            else => if (declared == null) return self.g.typeFailure(self.m, id),
        }
        const ty = declared orelse types.never;
        switch (operation) {
            .length => {
                const container = try self.expr(children[0]);
                return .{ .ty = types.u32_, .words = try self.arena.dupe(u32, &.{try self.lengthOf(container, id)}) };
            },
            .get => {
                const container = try self.expr(children[0]);
                const index = try self.scalarLocal(try self.expr(children[1]), id);
                return self.readElement(container, index, id);
            },
            .identity, .convert => {
                const value = try self.expr(children[0]);
                if (operation == .identity) return .{ .ty = ty, .words = value.words };
                return self.copyContainer(value, ty, id);
            },
            .fill, .generate => {
                const count = try self.scalarLocal(try self.expr(children[0]), id);
                const source = try self.expr(children[1]);
                const ty_ = declared orelse blk: {
                    const element = if (operation == .fill) source.ty else self.g.types.node(source.ty).b;
                    if (operation == .generate and self.tagOf(source.ty) != .function) return self.g.typeFailure(self.m, id);
                    const container = try self.g.types.lowerHoles(self.m, self.m.typeOf(id), self.env);
                    const built = try self.g.types.intern(self.tagOf(container), &.{element});
                    try self.refine(self.m.typeOf(id), built);
                    break :blk built;
                };
                const handle = try self.create(ty_, count, id);
                const base = try self.baseOf(handle);
                const element = try self.elementOf(ty_, id);
                const step = try self.stride(element, id);
                const index = try self.constLocal(0);
                const exit = try self.open(.block);
                const top = try self.open(.loop);
                try self.opIndex(.local_get, index);
                try self.opIndex(.local_get, count);
                try self.op(.i32_ge_u);
                try self.br(.br_if, exit);
                const value = if (operation == .fill) source else try self.applyClosure(source, .{ .ty = types.u32_, .words = try self.arena.dupe(u32, &.{index}) }, id);
                const address = try self.local32();
                try self.opIndex(.local_get, base);
                try self.opIndex(.local_get, index);
                try self.i32Const(step);
                try self.op(.i32_mul);
                try self.op(.i32_add);
                try self.opIndex(.local_set, address);
                try self.writeFlat(address, 0, value, id);
                try self.opIndex(.local_get, index);
                try self.i32Const(1);
                try self.op(.i32_add);
                try self.opIndex(.local_set, index);
                try self.br(.br, top);
                try self.close();
                try self.close();
                return handle;
            },
            .append, .prepend, .concat => {
                const first = try self.expr(children[0]);
                const second = try self.expr(children[1]);
                const element = try self.elementOf(ty, id);
                const parts: []const Val = switch (operation) {
                    .append => &.{ first, second },
                    .prepend => &.{ second, first },
                    else => &.{ first, second },
                };
                return self.joined(ty, element, parts, operation == .concat, id);
            },
            .slice => {
                const container = try self.expr(children[0]);
                const start = try self.scalarLocal(try self.expr(children[1]), id);
                const count = try self.scalarLocal(try self.expr(children[2]), id);
                const length = try self.lengthOf(container, id);
                // start + count <= length, without overflow.
                try self.opIndex(.local_get, start);
                try self.opIndex(.local_get, length);
                try self.op(.i32_gt_u);
                try self.opIndex(.local_get, count);
                try self.opIndex(.local_get, length);
                try self.opIndex(.local_get, start);
                try self.op(.i32_sub);
                try self.op(.i32_gt_u);
                try self.op(.i32_or);
                try self.trap();
                const handle = try self.create(ty, count, id);
                try self.copyElements(container, start, handle, try self.constLocal(0), count, id);
                return handle;
            },
            .cursor => {
                // (slot, generation, position, end) over the container's live range.
                const container = try self.expr(children[0]);
                const result = try self.fresh(ty, id);
                try self.copy(.{ .ty = types.u32_, .words = container.words[0..1] }, .{ .ty = types.u32_, .words = result.words[0..1] }, id);
                try self.copy(.{ .ty = types.u32_, .words = container.words[1..2] }, .{ .ty = types.u32_, .words = result.words[1..2] }, id);
                const length = try self.lengthOf(container, id);
                if (self.tagOf(container.ty) == .view) {
                    try self.opIndex(.local_get, container.words[2]);
                    try self.opIndex(.local_set, result.words[2]);
                    try self.opIndex(.local_get, container.words[2]);
                    try self.opIndex(.local_get, length);
                    try self.op(.i32_add);
                } else {
                    try self.i32Const(0);
                    try self.opIndex(.local_set, result.words[2]);
                    try self.opIndex(.local_get, length);
                }
                try self.opIndex(.local_set, result.words[3]);
                return result;
            },
            .cursor_has => {
                const cursor = try self.expr(children[0]);
                const result = try self.fresh(types.boolean, id);
                try self.opIndex(.local_get, cursor.words[2]);
                try self.opIndex(.local_get, cursor.words[3]);
                try self.op(.i32_lt_u);
                try self.opIndex(.local_set, result.words[0]);
                return result;
            },
            .cursor_value, .cursor_advance => {
                const cursor = try self.expr(children[0]);
                try self.opIndex(.local_get, cursor.words[2]);
                try self.opIndex(.local_get, cursor.words[3]);
                try self.op(.i32_ge_u);
                try self.trap();
                if (operation == .cursor_advance) {
                    const result = try self.fresh(cursor.ty, id);
                    for (cursor.words, result.words, 0..) |from, to, index| {
                        try self.opIndex(.local_get, from);
                        if (index == 2) {
                            try self.i32Const(1);
                            try self.op(.i32_add);
                        }
                        try self.opIndex(.local_set, to);
                    }
                    return result;
                }
                const rt = try self.g.runtime_();
                // A cursor's type argument is its collection.
                const collection = self.g.types.node(cursor.ty).a;
                const element = switch (self.tagOf(collection)) {
                    .array, .list, .grow, .resize, .view => self.g.types.node(collection).a,
                    else => collection,
                };
                const address = try self.local32();
                try self.opIndex(.local_get, cursor.words[0]);
                try self.opIndex(.local_get, cursor.words[1]);
                try self.opIndex(.local_get, cursor.words[2]);
                try self.i32Const(try self.stride(element, id));
                try self.opIndex(.call, rt.address);
                try self.opIndex(.local_set, address);
                return self.loadElement(address, 0, element, id);
            },
            .simd_load, .simd_store => {
                // Four consecutive elements, all in bounds.
                const container = try self.expr(children[0]);
                const index = try self.scalarLocal(try self.expr(children[1]), id);
                const last = try self.local32();
                try self.opIndex(.local_get, index);
                try self.i32Const(3);
                try self.op(.i32_add);
                try self.opIndex(.local_tee, last);
                try self.opIndex(.local_get, index);
                try self.op(.i32_lt_u);
                try self.trap();
                _ = try self.elementAddress(container, last, id);
                const address = try self.elementAddress(container, index, id);
                const element = try self.elementOf(container.ty, id);
                const lane_ty = try self.g.types.tuple(&.{ element, element, element, element });
                if (operation == .simd_load) return self.loadAt(address, 0, lane_ty, id);
                const lanes_value = try self.expr(children[2]);
                try self.storeAt(address, 0, lanes_value);
                return container;
            },
            else => return self.g.fail(self.m, id, "array operation {s} is not supported yet", .{@tagName(operation)}),
        }
    }
    /// Copies `count` elements from `source[from..]` to `target[to..]`.
    fn copyElements(self: *Fn, source: Val, from: u32, target: Val, to: u32, count: u32, id: core.Id) Error!void {
        const step = try self.stride(try self.elementOf(target.ty, id), id);
        _ = try self.open(.block);
        try self.opIndex(.local_get, count);
        try self.op(.i32_eqz);
        try self.opIndex(.br_if, 0);
        const destination = try self.elementAddress(target, to, id);
        const origin = try self.elementAddress(source, from, id);
        // Both ranges end inside their owners: check the last elements too.
        const last = try self.local32();
        try self.opIndex(.local_get, count);
        try self.i32Const(1);
        try self.op(.i32_sub);
        try self.opIndex(.local_set, last);
        const end_target = try self.local32();
        try self.opIndex(.local_get, to);
        try self.opIndex(.local_get, last);
        try self.op(.i32_add);
        try self.opIndex(.local_set, end_target);
        _ = try self.elementAddress(target, end_target, id);
        const end_source = try self.local32();
        try self.opIndex(.local_get, from);
        try self.opIndex(.local_get, last);
        try self.op(.i32_add);
        try self.opIndex(.local_set, end_source);
        _ = try self.elementAddress(source, end_source, id);
        try self.opIndex(.local_get, destination);
        try self.opIndex(.local_get, origin);
        try self.opIndex(.local_get, count);
        try self.i32Const(step);
        try self.op(.i32_mul);
        try self.op(.prefix_fc);
        try self.code.uleb(self.a(), 10);
        try self.code.byte(self.a(), 0);
        try self.code.byte(self.a(), 0);
        try self.close();
    }
    /// A new fixed array: the elements of each part in order (a part is
    /// either a container or, unless `containers`, one element).
    fn joined(self: *Fn, ty: Ty, element: Ty, parts: []const Val, containers: bool, id: core.Id) Error!Val {
        const lengths = try self.arena.alloc(?u32, parts.len);
        const total = try self.constLocal(0);
        for (parts, lengths) |part, *length| {
            const is_container = containers or part.ty != element;
            length.* = if (is_container) try self.lengthOf(part, id) else null;
            try self.opIndex(.local_get, total);
            if (length.*) |value| try self.opIndex(.local_get, value) else try self.i32Const(1);
            try self.op(.i32_add);
            try self.opIndex(.local_set, total);
        }
        const handle = try self.create(ty, total, id);
        const at = try self.constLocal(0);
        for (parts, lengths) |part, length| {
            if (length) |count| {
                try self.copyElements(part, try self.constLocal(0), handle, at, count, id);
                try self.opIndex(.local_get, at);
                try self.opIndex(.local_get, count);
            } else {
                try self.writeFlat(try self.elementAddress(handle, at, id), 0, part, id);
                try self.opIndex(.local_get, at);
                try self.i32Const(1);
            }
            try self.op(.i32_add);
            try self.opIndex(.local_set, at);
        }
        return handle;
    }
    /// An independent owner of type `ty` with `value`'s elements.
    fn copyContainer(self: *Fn, value: Val, ty: Ty, id: core.Id) Error!Val {
        const length = try self.lengthOf(value, id);
        const handle = try self.create(ty, length, id);
        try self.copyElements(value, try self.constLocal(0), handle, try self.constLocal(0), length, id);
        return handle;
    }

    fn storageOp(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const operation: storage_ops.Op = @fromBackingInt(n.c);
        const children = self.m.children(id);
        const ty = try self.typeOf(id);
        const rt = try self.g.runtime_();
        switch (operation) {
            .reserve => {
                _ = try self.expr(children[0]);
                return unitVal();
            },
            .length => {
                const container = try self.expr(children[0]);
                return .{ .ty = types.u32_, .words = try self.arena.dupe(u32, &.{try self.lengthOf(container, id)}) };
            },
            .read => {
                const container = try self.expr(children[0]);
                return self.readElement(container, try self.scalarLocal(try self.expr(children[1]), id), id);
            },
            .push => {
                const container = try self.expr(children[0]);
                const value = try self.expr(children[1]);
                const address = try self.local32();
                try self.opIndex(.local_get, container.words[0]);
                try self.opIndex(.local_get, container.words[1]);
                try self.i32Const(try self.stride(try self.elementOf(container.ty, id), id));
                try self.opIndex(.call, rt.push);
                try self.opIndex(.local_set, address);
                try self.writeFlat(address, 0, value, id);
                return unitVal();
            },
            .pop => {
                const container = try self.expr(children[0]);
                const address = try self.local32();
                try self.opIndex(.local_get, container.words[0]);
                try self.opIndex(.local_get, container.words[1]);
                try self.i32Const(try self.stride(try self.elementOf(container.ty, id), id));
                try self.opIndex(.call, rt.pop);
                try self.opIndex(.local_set, address);
                return self.loadElement(address, 0, ty, id);
            },
            .truncate => {
                const container = try self.expr(children[0]);
                const count = try self.scalarLocal(try self.expr(children[1]), id);
                try self.opIndex(.local_get, container.words[0]);
                try self.opIndex(.local_get, container.words[1]);
                try self.opIndex(.local_get, count);
                try self.opIndex(.call, rt.truncate);
                return unitVal();
            },
            .freeze => {
                const container = try self.expr(children[0]);
                try self.opIndex(.local_get, container.words[0]);
                try self.opIndex(.local_get, container.words[1]);
                try self.opIndex(.call, rt.freeze);
                return .{ .ty = ty, .words = container.words };
            },
            .copy => {
                const container = try self.expr(children[0]);
                return self.copyContainer(container, ty, id);
            },
            .view => {
                const container = try self.expr(children[0]);
                const start = try self.scalarLocal(try self.expr(children[1]), id);
                const end = try self.scalarLocal(try self.expr(children[2]), id);
                const length = try self.lengthOf(container, id);
                try self.opIndex(.local_get, start);
                try self.opIndex(.local_get, end);
                try self.op(.i32_gt_u);
                try self.opIndex(.local_get, end);
                try self.opIndex(.local_get, length);
                try self.op(.i32_gt_u);
                try self.op(.i32_or);
                try self.trap();
                const result = try self.fresh(ty, id);
                try self.copy(.{ .ty = types.u32_, .words = container.words[0..1] }, .{ .ty = types.u32_, .words = result.words[0..1] }, id);
                try self.copy(.{ .ty = types.u32_, .words = container.words[1..2] }, .{ .ty = types.u32_, .words = result.words[1..2] }, id);
                if (self.tagOf(container.ty) == .view) {
                    try self.opIndex(.local_get, container.words[2]);
                    try self.opIndex(.local_get, start);
                    try self.op(.i32_add);
                } else try self.opIndex(.local_get, start);
                try self.opIndex(.local_set, result.words[2]);
                try self.opIndex(.local_get, end);
                try self.opIndex(.local_get, start);
                try self.op(.i32_sub);
                try self.opIndex(.local_set, result.words[3]);
                return result;
            },
            .at, .link => {
                const container = try self.expr(children[0]);
                const index = try self.scalarLocal(try self.expr(children[1]), id);
                // Check now, so a reference never names a missing element.
                _ = try self.elementAddress(container, index, id);
                const result = try self.fresh(ty, id);
                try self.copy(.{ .ty = types.u32_, .words = container.words[0..1] }, .{ .ty = types.u32_, .words = result.words[0..1] }, id);
                try self.copy(.{ .ty = types.u32_, .words = container.words[1..2] }, .{ .ty = types.u32_, .words = result.words[1..2] }, id);
                if (self.tagOf(container.ty) == .view) {
                    try self.opIndex(.local_get, container.words[2]);
                    try self.opIndex(.local_get, index);
                    try self.op(.i32_add);
                } else try self.opIndex(.local_get, index);
                try self.opIndex(.local_set, result.words[2]);
                return result;
            },
            .load, .write => {
                const reference_ = try self.expr(children[0]);
                const element = try self.elementOf(reference_.ty, id);
                const address = try self.local32();
                try self.opIndex(.local_get, reference_.words[0]);
                try self.opIndex(.local_get, reference_.words[1]);
                try self.opIndex(.local_get, reference_.words[2]);
                try self.i32Const(try self.stride(element, id));
                try self.opIndex(.call, rt.address);
                try self.opIndex(.local_set, address);
                if (operation == .load) return self.loadElement(address, 0, element, id);
                const value = try self.expr(children[1]);
                try self.writeFlat(address, 0, value, id);
                return unitVal();
            },
            .ref => return self.g.fail(self.m, id, "references to whole values are not supported yet", .{}),
        }
    }

    /// `@type.result "member" value`: dispatch on the expected result type.
    fn resultAssociated(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const value = try self.expr(n.a);
        const result = try self.typeOf(id);
        const identity = self.g.receiverIdentity(result) orelse return self.g.fail(self.m, id, "result member on a {s}", .{@tagName(self.tagOf(result))});
        const target = self.g.dispatchTarget(self.m, identity, n.b, .none) orelse return self.g.fail(self.m, id, "no result member for this type", .{});
        const arguments = try self.arena.dupe(Val, &.{value});
        return self.callTarget(target, arguments, try self.g.types.function(value.ty, result), result, id);
    }

    /// All fields of the left record, with same-named right fields replacing them.
    fn recordMerge(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const left = try self.expr(n.a);
        const right = try self.expr(n.b);
        const ty = try self.typeOf(id);
        if (self.tagOf(ty) != .record) return self.g.fail(self.m, id, "record merge of a non-record type", .{});
        var words: std.ArrayList(u32) = .empty;
        const boxed = try self.isBoxed(ty, id);
        const memory_block: u32 = if (boxed) try self.newBlock(ty, id) else 0;
        for (0..self.g.types.node(ty).b) |index| {
            const name = self.g.types.recordField(ty, index).name;
            const source = for ([_]Val{ right, left }) |side| {
                if (self.tagOf(side.ty) != .record) continue;
                if (self.g.types.findField(side.ty, name)) |position| break .{ side, position };
            } else return self.g.fail(self.m, id, "merged field missing from both records", .{});
            const field = try self.recordField(source[0], source[1], id);
            if (boxed) try self.writeFlat(memory_block, try self.fieldOffset(ty, index, id), field, id) else try words.appendSlice(self.arena, field.words);
        }
        if (boxed) return .{ .ty = ty, .words = try self.arena.dupe(u32, &.{memory_block}) };
        return .{ .ty = ty, .words = words.items };
    }

    /// `root` with the field path of an update replaced by its new value.
    fn update(self: *Fn, id: core.Id) Error!Val {
        const info = self.m.updateInfo(id);
        const root = try self.expr(info.root);
        return self.updateAt(id, root, 0);
    }
    /// `container[index].fields... := value` writes the selected place
    /// through the owner and leaves the handle unchanged.
    fn indexedUpdate(self: *Fn, id: core.Id, container: Val, at: usize) Error!Val {
        const info = self.m.updateInfo(id);
        const selectors = self.m.updateSelectors(id);
        const index = try self.scalarLocal(try self.expr(selectors[at].index), id);
        const address = try self.elementAddress(container, index, id);
        var ty = try self.elementOf(container.ty, id);
        var offset: u32 = 0;
        for (selectors[at + 1 ..]) |step| {
            if (step.kind == .index) return self.g.fail(self.m, id, "nested indexed updates are not supported yet", .{});
            const projection = self.m.projection(step.projection);
            const spelling = self.m.fieldSpelling(projection.field) orelse return self.g.fail(self.m, id, "updated field without a spelling", .{});
            const name = try self.g.types.fieldName(spelling);
            var record = ty;
            if (self.tagOf(ty) == .nominal) {
                const cases = self.g.types.variants(ty) catch |err| switch (err) {
                    error.Unsupported => return self.g.typeFailure(self.m, id),
                    else => return err,
                };
                if (cases.payloads.len != 1) return self.g.fail(self.m, id, "update of a multi-constructor element", .{});
                record = cases.payloads[0];
            }
            const position = self.g.types.findField(record, name) orelse return self.g.fail(self.m, id, "updated field missing", .{});
            for (0..position) |before| offset += try self.byteWidth(self.g.types.recordField(record, before).ty, id);
            ty = self.g.types.recordField(record, position).ty;
        }
        const old = if (offset == 0) try self.loadElement(address, 0, ty, id) else try self.loadAt(address, offset, ty, id);
        if (offset != 0 and try self.isBoxed(ty, id)) return self.g.fail(self.m, id, "update of a boxed field inside an element", .{});
        try self.bindings.put(self.a(), info.self_binding, old);
        const replacement = try self.stmt(info.value);
        if (replacement.ty == types.never) return replacement;
        try self.writeFlat(address, offset, replacement, id);
        return container;
    }
    fn byteWidth(self: *Fn, ty: Ty, id: core.Id) Error!u32 {
        return self.flatBytes(ty, id);
    }
    /// A boxed record (or one-constructor wrapper of one) with field
    /// `name` replaced: a fresh copy of the block, then the field written.
    fn updateBoxed(self: *Fn, id: core.Id, value: Val, name: u32, at: usize) Error!Val {
        var record_ty = value.ty;
        if (self.tagOf(value.ty) == .nominal) {
            const cases = self.g.types.variants(value.ty) catch |err| switch (err) {
                error.Unsupported => return self.g.typeFailure(self.m, id),
                else => return err,
            };
            if (cases.payloads.len != 1) return self.g.fail(self.m, id, "update of a multi-constructor value", .{});
            record_ty = cases.payloads[0];
        }
        if (self.tagOf(record_ty) != .record) return self.g.fail(self.m, id, "update of a boxed {s}", .{@tagName(self.tagOf(record_ty))});
        const position = self.g.types.findField(record_ty, name) orelse return self.g.fail(self.m, id, "updated field missing", .{});
        // A one-constructor wrapper's payload starts at its block's start.
        const offset = try self.fieldOffset(record_ty, position, id);
        const field_ty = self.g.types.recordField(record_ty, position).ty;
        const old = try self.readFlat(value.words[0], offset, field_ty, id);
        const replacement = try self.updateAt(id, old, at + 1);
        if (replacement.ty == types.never) return replacement;
        if (replacement.ty != field_ty) return self.g.fail(self.m, id, "an update that changes a boxed field's type", .{});
        const memory_block = try self.newBlock(value.ty, id);
        try self.memoryCopy(memory_block, 0, value.words[0], try self.flatBytes(value.ty, id));
        try self.writeFlat(memory_block, offset, replacement, id);
        return .{ .ty = value.ty, .words = try self.arena.dupe(u32, &.{memory_block}) };
    }
    fn updateAt(self: *Fn, id: core.Id, value: Val, at: usize) Error!Val {
        const info = self.m.updateInfo(id);
        const selectors = self.m.updateSelectors(id);
        const path = self.m.updatePath(id);
        const steps = @max(selectors.len, path.len);
        if (at == steps) {
            try self.bindings.put(self.a(), info.self_binding, value);
            return self.stmt(info.value);
        }
        if (selectors.len != 0 and selectors[at].kind == .index) return self.indexedUpdate(id, value, at);
        const projection = self.m.projection(if (selectors.len != 0) selectors[at].projection else path[at]);
        const spelling = self.m.fieldSpelling(projection.field) orelse return self.g.fail(self.m, id, "updated field without a spelling", .{});
        const name = try self.g.types.fieldName(spelling);
        if (try self.isBoxed(value.ty, id)) return self.updateBoxed(id, value, name, at);
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
        const left = try self.expr(n.a);
        const right = if (n.b != 0) try self.expr(n.b) else null;
        var tag = self.tagOf(left.ty);
        var operand_left = left;
        var operand_right = right;
        // Opaque wrappers of a scalar are erased at run time.
        if (tag == .nominal) if (try self.scalarPayload(left)) |inner| {
            const dispatch = n.c == 1 and self.g.dispatchTarget(self.m, self.g.receiverIdentity(left.ty).?, 0, operatorOf(n.op) orelse .none) != null;
            if (!dispatch) {
                operand_left = inner;
                if (right) |value| operand_right = (try self.scalarPayload(value)) orelse value;
                tag = self.tagOf(inner.ty);
            }
        };
        if (tag == .u32 or tag == .f32 or tag == .boolean) if (operand_left.ty != left.ty) {
            try self.push(operand_left);
            if (operand_right) |value| try self.push(value);
            try self.scalarOp(n.op, operand_left.ty, id);
            return self.pop(try self.typeOf(id), id);
        };
        if (n.c == 1 and tag != .u32 and tag != .f32 and tag != .boolean and tag != .tuple) {
            // Operator dispatch: the operand type's associated operator member.
            const operator = operatorOf(n.op) orelse return self.g.fail(self.m, id, "{s} has no associated operator", .{@tagName(n.op)});
            const identity = self.g.receiverIdentity(left.ty) orelse return self.g.fail(self.m, id, "{s} on a {s}", .{ @tagName(n.op), @tagName(tag) });
            const target = self.g.dispatchTarget(self.m, identity, 0, operator) orelse return self.g.fail(self.m, id, "no {s} operator for this type", .{@tagName(n.op)});
            const arguments: []const Val = if (right) |value| try self.arena.dupe(Val, &.{ left, value }) else try self.arena.dupe(Val, &.{left});
            const callee = try self.g.calleeFromArguments(target, arguments, self.m, id);
            return self.callTarget(target, arguments, callee, try self.restType(callee, arguments.len, id), id);
        }
        const result = try self.typeOf(id);
        if (tag == .tuple) return self.lanes(n.op, left, right, result, id);
        try self.push(left);
        if (right) |value| try self.push(value);
        try self.scalarOp(n.op, left.ty, id);
        return self.pop(result, id);
    }
    /// The scalar payload of a single-constructor value, if it has one.
    fn scalarPayload(self: *Fn, value: Val) Error!?Val {
        if (self.tagOf(value.ty) != .nominal) return null;
        const cases = self.g.types.variants(value.ty) catch return null;
        if (cases.payloads.len != 1) return null;
        const payload = cases.payloads[0];
        const tag = self.tagOf(payload);
        if (tag != .u32 and tag != .f32 and tag != .boolean) return null;
        return .{ .ty = payload, .words = value.words };
    }
    /// Four-lane operations on (U32|F32)x4 products, one lane at a time.
    fn lanes(self: *Fn, op_: core.Op, left: Val, right: ?Val, result_ty: Ty, id: core.Id) Error!Val {
        const items = self.g.types.tupleItems(left.ty);
        if (items.len != 4) return self.g.fail(self.m, id, "lane operation on a {d}-tuple", .{items.len});
        const lane = items[0];
        const float = self.tagOf(lane) == .f32;
        const result = try self.fresh(result_ty, id);
        switch (op_) {
            .any_true, .all_true => {
                try self.i32Const(@intFromBool(op_ == .all_true));
                for (left.words) |word| {
                    try self.opIndex(.local_get, word);
                    try self.i32Const(0);
                    try self.op(.i32_ne);
                    try self.op(if (op_ == .all_true) .i32_and else .i32_or);
                }
                try self.opIndex(.local_set, result.words[0]);
                return result;
            },
            .select => {
                // mask selects bits of the first product, the rest from the second.
                const pair = right orelse return self.g.fail(self.m, id, "select without operands", .{});
                for (0..4) |index| {
                    const mask = left.words[index];
                    const yes = pair.words[index];
                    const no = pair.words[index + 4];
                    const f = self.locals.items[yes] == .f32;
                    try self.opIndex(.local_get, yes);
                    if (f) try self.op(.i32_reinterpret_f32);
                    try self.opIndex(.local_get, mask);
                    try self.op(.i32_and);
                    try self.opIndex(.local_get, no);
                    if (f) try self.op(.i32_reinterpret_f32);
                    try self.opIndex(.local_get, mask);
                    try self.i32Const(0xffff_ffff);
                    try self.op(.i32_xor);
                    try self.op(.i32_and);
                    try self.op(.i32_or);
                    if (f) try self.op(.f32_reinterpret_i32);
                    try self.opIndex(.local_set, result.words[index]);
                }
                return result;
            },
            .shuffle, .swizzle, .broadcast => {
                // Lane selectors index the candidate words: shuffle's two
                // products (0-3, 4-7), swizzle's one, broadcast's one lane.
                const operand = right orelse return self.g.fail(self.m, id, "{s} without operands", .{@tagName(op_)});
                const candidates = if (op_ == .broadcast) left.words else operand.words;
                for (0..4) |index| {
                    const selector = if (op_ == .broadcast) operand.words[0] else left.words[index];
                    try self.opIndex(.local_get, candidates[0]);
                    for (candidates[1..], 1..) |candidate, position| {
                        const value = try self.local(self.locals.items[candidate]);
                        try self.opIndex(.local_set, value);
                        try self.opIndex(.local_get, candidate);
                        try self.opIndex(.local_get, value);
                        try self.opIndex(.local_get, selector);
                        try self.i32Const(@intCast(position));
                        try self.op(.i32_eq);
                        try self.op(.select);
                    }
                    try self.opIndex(.local_set, result.words[index]);
                }
                return result;
            },
            else => {},
        }
        // A scalar right operand (a shift count) applies to every lane.
        var broadcast: [4]u32 = undefined;
        const right_words: ?[]const u32 = if (right) |value| blk: {
            if (value.words.len != 1) break :blk value.words;
            broadcast = @splat(value.words[0]);
            break :blk &broadcast;
        } else null;
        if (right_words) |words| if (words.len != 4) return self.g.fail(self.m, id, "lane operation with a {d}-word right operand", .{words.len});
        for (0..4) |index| {
            switch (op_) {
                .bits, .from_bits => {
                    try self.opIndex(.local_get, left.words[index]);
                    try self.op(if (op_ == .bits) .i32_reinterpret_f32 else .f32_reinterpret_i32);
                },
                .min, .max => {
                    // The prelude's `if a < b then a else b`, NaN and zero signs included.
                    const r = (right_words orelse return self.g.fail(self.m, id, "lane operation without a right operand", .{}))[index];
                    try self.opIndex(.local_get, left.words[index]);
                    try self.opIndex(.local_get, r);
                    try self.opIndex(.local_get, left.words[index]);
                    try self.opIndex(.local_get, r);
                    try self.op(if (float) (if (op_ == .min) W.Op.f32_lt else .f32_gt) else (if (op_ == .min) W.Op.i32_lt_u else .i32_gt_u));
                    try self.op(.select);
                },
                .equal, .not_equal, .less, .less_equal, .greater, .greater_equal => {
                    const r = (right_words orelse return self.g.fail(self.m, id, "comparison without a right operand", .{}))[index];
                    // A lane mask: all ones where the comparison holds.
                    try self.i32Const(0);
                    try self.opIndex(.local_get, left.words[index]);
                    try self.opIndex(.local_get, r);
                    try self.scalarOp(op_, lane, id);
                    try self.op(.i32_sub);
                },
                else => {
                    try self.opIndex(.local_get, left.words[index]);
                    if (right_words) |words| try self.opIndex(.local_get, words[index]);
                    try self.scalarOp(op_, lane, id);
                },
            }
            try self.opIndex(.local_set, result.words[index]);
        }
        return result;
    }
    /// Emits the machine operation for `op` on operands already on the stack.
    pub fn scalarOp(self: *Fn, op_: core.Op, operand: Ty, id: core.Id) Error!void {
        const tag = self.g.types.node(operand).tag;
        const float = tag == .f32;
        if (tag != .u32 and tag != .f32 and tag != .boolean) return self.g.fail(self.m, id, "{s} on a {s} operand at a {s} node", .{ @tagName(op_), @tagName(tag), @tagName(self.m.node(id).tag) });
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
        const previous_call = self.current_call;
        self.current_call = id;
        defer self.current_call = previous_call;
        const info = self.m.call(id);
        const target = self.g.resolve(self.m, info.target);
        const values = try self.arena.alloc(Val, info.arguments.len);
        // Building a function value has no effects, so one whose type the
        // other arguments still determine is built after them.
        var deferred = false;
        for (info.arguments, values) |argument, *slot| {
            if (self.pureFunctionValue(argument) and !self.lowers(self.m.typeOf(argument))) {
                deferred = true;
                slot.* = neverVal();
                continue;
            }
            slot.* = try self.expr(argument);
        }
        if (deferred) for (info.arguments, values, 0..) |argument, *slot, index| {
            if (slot.ty != types.never) continue;
            // Still unknown: take the type the callee expects from the
            // arguments known so far, with holes for what they leave open.
            if (!self.lowers(self.m.typeOf(argument))) {
                if (try self.expectedArgument(target, values, index)) |expected| try self.refine(self.m.typeOf(argument), expected);
            }
            slot.* = try self.expr(argument);
        };
        const callee = self.g.types.lower(self.m, info.callee_type, self.env) catch |err| switch (err) {
            error.Unsupported => try self.g.calleeFromArguments(target, values, self.m, id),
            else => return err,
        };
        try self.refine(info.callee_type, callee);
        return self.callTarget(target, values, callee, try self.restType(callee, values.len, id), id);
    }
    /// Parameter `index` of `target` as fixed by the evaluated `values`
    /// (entries typed never are not yet evaluated), with holes.
    fn expectedArgument(self: *Fn, target: core.BindingRef, values: []const Val, index: usize) Error!?Ty {
        const tm = self.g.unitModule(target.unit);
        var env: types.Env = .empty;
        defer env.deinit(self.a());
        var arrow = tm.binding(target.binding).ty;
        var parameter: ?T.Id = null;
        for (values, 0..) |value, at| {
            var n = tm.types.node(arrow);
            while (n.tag == .forall or n.tag == .usage) {
                arrow = n.a;
                n = tm.types.node(arrow);
            }
            if (n.tag != .function) return null;
            if (at == index) parameter = n.a else if (value.ty != types.never) try self.g.types.match(tm, n.a, value.ty, &env);
            arrow = n.b;
        }
        const body = tm.body(target.binding);
        if (body) |b| try self.g.solveObligationsPublic(tm, b.scheme.obligations, &env);
        const formal = parameter orelse return null;
        const expected = try self.g.types.lowerHoles(tm, formal, &env);
        if (self.tagOf(expected) != .never) return expected;
        // The parameter is a bare variable: its field constraints and the
        // argument's own nominal type give the argument's type arguments.
        const b = body orelse return null;
        return self.fromFieldConstraints(tm, b.scheme.obligations, formal, &env, index);
    }
    /// The nominal type of argument `index` of the current call, with its
    /// type arguments taken from the callee's field constraints on it.
    fn fromFieldConstraints(self: *Fn, tm: *const core.Module, goals_span: T.List, formal: T.Id, env: *types.Env, index: usize) Error!?Ty {
        const info = self.m.call(self.current_call);
        const argument_type = self.m.typeOf(info.arguments[index]);
        const shape = self.m.types.node(argument_type);
        if (shape.tag != .nominal) return null;
        const identity: T.NominalIdentity = .{ .unit = shape.a, .decl = shape.b };
        const owner = self.g.types.module(identity.unit) orelse return null;
        const ordinal = self.g.types.nominalOrdinal(owner, identity) catch return null;
        const constructors = owner.nominalConstructors(ordinal);
        if (constructors.len != 1) return null;
        const constructor = owner.constructor(constructors[0]);
        const payload = owner.types.node(constructor.payload);
        if (payload.tag != .record) return null;
        var params_env: types.Env = .empty;
        defer params_env.deinit(self.a());
        const goals = tm.obligations[goals_span.start..][0..goals_span.len];
        for (goals) |goal| {
            if (goal.kind != .field or goal.ty != formal or goal.result == 0) continue;
            const spelling = tm.fieldSpelling(goal.name) orelse continue;
            const wanted = try self.g.types.lowerHoles(tm, goal.result, env);
            for (0..payload.b) |field_index| {
                const field = owner.types.recordField(payload, field_index);
                const name = owner.fieldSpelling(field.name) orelse continue;
                if (std.mem.eql(u8, name, spelling)) try self.g.types.match(owner, field.ty, wanted, &params_env);
            }
        }
        // The payload's fields bind the constructor's scheme variables.
        const signature = owner.types.node(constructor.scheme.root);
        const result = if (signature.tag == .function) signature.b else constructor.scheme.root;
        return try self.g.types.lowerHoles(owner, result, &params_env);
    }
    /// `acc := @list.append acc x` (a comprehension's accumulator) where the
    /// old `acc` has no other use: grow the same owner in place, so the loop
    /// carries an owner created before it instead of a fresh one.
    fn linearAppend(self: *Fn, id: core.Id) Error!?Val {
        const n = self.m.node(id);
        if (n.tag != .array_op or self.m.arrayOperation(id) != .append) return null;
        const children = self.m.children(id);
        if (children.len != 2 or self.m.node(children[0]).tag != .reference) return null;
        const ref = self.m.reference(children[0]);
        if (ref.unit != 0 and ref.unit != self.m.unit) return null;
        const list = self.bindings.get(ref.binding) orelse return null;
        if (self.tagOf(list.ty) != .list and self.tagOf(list.ty) != .array) return null;
        if (try self.uses(ref.binding) != 1) return null;
        const value = try self.expr(children[1]);
        const rt = try self.g.runtime_();
        const address = try self.local32();
        try self.opIndex(.local_get, list.words[0]);
        try self.opIndex(.local_get, list.words[1]);
        try self.i32Const(try self.stride(try self.elementOf(list.ty, id), id));
        try self.opIndex(.call, rt.push);
        try self.opIndex(.local_set, address);
        try self.writeFlat(address, 0, value, id);
        return .{ .ty = list.ty, .words = list.words };
    }
    /// References to local `binding` in this unit, counted once. A loop
    /// exit (`break_`) carrying a version is on a path exclusive with any
    /// later rebinding of it, so it does not count.
    fn uses(self: *Fn, binding: core.BindingId) Error!u32 {
        if (self.use_counts == null) {
            var exits: std.AutoHashMapUnmanaged(core.Id, void) = .empty;
            for (self.m.nodes, 0..) |node, index| if (node.tag == .break_) {
                for (self.m.children(@intCast(index))) |child| try exits.put(self.arena, child, {});
            };
            var counts: std.AutoHashMapUnmanaged(core.BindingId, u32) = .empty;
            for (self.m.nodes, 0..) |node, index| if (node.tag == .reference and !exits.contains(@intCast(index))) {
                const target = self.m.references[node.a];
                if (target.unit != 0 and target.unit != self.m.unit) continue;
                const entry = try counts.getOrPut(self.arena, target.binding);
                entry.value_ptr.* = if (entry.found_existing) entry.value_ptr.* + 1 else 1;
            };
            self.use_counts = counts;
        }
        return self.use_counts.?.get(binding) orelse 0;
    }
    /// Whether call node `id` applies a named function to fewer arguments
    /// than its parameters.
    fn partialCall(self: *Fn, id: core.Id) bool {
        const info = self.m.call(id);
        const target = self.g.resolve(self.m, info.target);
        const tm = self.g.unitModule(target.unit);
        const body = tm.body(target.binding) orelse return false;
        return body.is_function and info.arguments.len < tm.bodyParameters(body).len;
    }
    /// Whether an apply chain applies a named function to fewer arguments
    /// than its parameters (with pure arguments).
    fn partialApply(self: *Fn, id: core.Id) bool {
        var head = id;
        var count: usize = 0;
        while (self.m.node(head).tag == .apply) : (count += 1) head = self.m.node(head).a;
        if (self.m.node(head).tag != .reference) return false;
        const target = self.g.resolve(self.m, self.m.reference(head));
        const tm = self.g.unitModule(target.unit);
        const body = tm.body(target.binding) orelse return false;
        return body.is_function and count < tm.bodyParameters(body).len;
    }
    fn pureFunctionValue(self: *Fn, id: core.Id) bool {
        return switch (self.m.node(id).tag) {
            .reference, .closure, .constructor_function, .primitive_function => true,
            else => false,
        };
    }
    /// Whether `ty` lowers under the current environment (no failure kept).
    fn lowers(self: *Fn, ty: T.Id) bool {
        _ = self.g.types.lower(self.m, ty, self.env) catch return false;
        return true;
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
                if (self.g.instance(instance).inferring) return self.g.fail(self.m, id, "recursion through a function whose result type its body determines", .{});
                for (direct, self.g.instance(instance).parameters) |argument, parameter| {
                    if ((try self.layout(parameter, id)).len != argument.words.len)
                        return self.g.fail(self.m, id, "argument of {d} words for a {s} parameter of {d} words", .{ argument.words.len, @tagName(self.tagOf(parameter)), (try self.layout(parameter, id)).len });
                }
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
                return try self.pop(if (self.tagOf(result) == .never) scalarResult(n.op, left.ty) else result, id);
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
        const result: ?Ty = self.g.types.lower(self.m, self.m.typeOf(id), self.env) catch |err| switch (err) {
            error.Unsupported => null,
            else => return err,
        };
        const tag = self.g.types.node(left.ty).tag;
        if (n.op != .none and (tag == .u32 or tag == .f32 or tag == .boolean)) {
            try self.push(left);
            if (right) |value| try self.push(value);
            try self.scalarOp(n.op, left.ty, id);
            return self.pop(result orelse scalarResult(n.op, left.ty), id);
        }
        const identity = self.g.receiverIdentity(left.ty) orelse return self.g.fail(self.m, id, "associated member on a {s}", .{@tagName(tag)});
        const target = self.g.dispatchTarget(self.m, identity, n.c, .none) orelse return self.g.fail(self.m, id, "no associated member for this receiver", .{});
        const arguments: []const Val = if (right) |value| &.{ left, value } else &.{left};
        const owned = try self.arena.dupe(Val, arguments);
        const callee = if (result) |known| try self.curried(owned, known) else try self.g.calleeFromArguments(target, owned, self.m, id);
        return self.callTarget(target, owned, callee, try self.restType(callee, owned.len, id), id);
    }

    fn ifNode(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const result = try self.arena.create(?Val);
        result.* = null;
        const merges = self.m.branchMerges(id);
        const merged = try self.arena.alloc(?Val, merges.len);
        @memset(merged, null);
        try self.push(try self.expr(n.a));
        _ = try self.open(.if_);
        const then = try self.stmt(n.b);
        var falls = then.ty != types.never;
        if (falls) {
            if (n.tag == .if_value) try self.deliver(then, result, id);
            for (merges, merged) |merge, *slot| if (self.bindings.get(merge.then_binding)) |value| try self.deliver(value, slot, id);
        }
        try self.op(.else_);
        if (n.c != 0) {
            const otherwise = try self.stmt(n.c);
            if (otherwise.ty != types.never) {
                falls = true;
                if (n.tag == .if_value) try self.deliver(otherwise, result, id);
                for (merges, merged) |merge, *slot| if (self.bindings.get(merge.else_binding)) |value| try self.deliver(value, slot, id);
            }
        } else {
            falls = true;
            for (merges, merged) |merge, *slot| if (self.bindings.get(merge.else_binding)) |value| try self.deliver(value, slot, id);
        }
        try self.close();
        for (merges, merged) |merge, slot| if (slot) |value| try self.bindings.put(self.a(), merge.result, value);
        if (!falls) return neverVal();
        if (n.tag == .if_stmt) return unitVal();
        return result.* orelse neverVal();
    }

    fn block(self: *Fn, id: core.Id) Error!Val {
        const result = try self.arena.create(?Val);
        result.* = null;
        const depth = try self.open(.block);
        try self.labels.append(self.a(), .{ .target = id, .depth = depth, .result = result });
        var last = unitVal();
        for (self.m.children(id)) |child| last = try self.stmt(child);
        _ = self.labels.pop();
        try self.close();
        if (result.*) |value| return value;
        // A Unit block may fall through its end.
        return if (last.ty != types.never and self.m.typeOf(id) == T.unit) unitVal() else neverVal();
    }
    /// Copies `value` into a lazily allocated result slot.
    fn deliver(self: *Fn, value: Val, slot: *?Val, id: core.Id) Error!void {
        if (value.ty == types.never) return;
        if (slot.* == null) slot.* = try self.fresh(value.ty, id);
        try self.copy(value, slot.*.?, id);
    }

    fn returnNode(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const value = try self.stmt(n.a);
        if (value.ty == types.never) return neverVal();
        var at = self.labels.items.len;
        while (at != 0) {
            at -= 1;
            const label = self.labels.items[at];
            if ((label.target != n.b and label.kind != .function) or label.kind == .loop) continue;
            try self.deliver(value, label.result, id);
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
        const children = self.m.children(id);
        const values = try self.arena.alloc(Val, children.len);
        for (children, values) |child, *slot| slot.* = try self.fieldValue(child);
        // The literal's type, or the one its fields' values give it.
        const ty = self.g.types.lower(self.m, self.m.typeOf(id), self.env) catch |err| switch (err) {
            error.Unsupported => try self.productType(id, values),
            else => return err,
        };
        const shape = self.g.types.node(ty);
        var words: std.ArrayList(u32) = .empty;
        const boxed = try self.isBoxed(ty, id);
        const memory_block: u32 = if (boxed) try self.newBlock(ty, id) else 0;
        switch (shape.tag) {
            .unit => return unitVal(),
            .tuple => for (values, 0..) |value, index| {
                if (boxed) try self.writeFlat(memory_block, try self.itemOffset(ty, index, id), value, id) else try words.appendSlice(self.arena, value.words);
            },
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
                for (ordered, 0..) |slot, index| {
                    const value = slot orelse return self.g.fail(self.m, id, "record literal misses a field", .{});
                    if (boxed) try self.writeFlat(memory_block, try self.fieldOffset(ty, index, id), value, id) else try words.appendSlice(self.arena, value.words);
                }
            },
            else => return self.g.fail(self.m, id, "product of type {s}", .{@tagName(shape.tag)}),
        }
        if (boxed) return .{ .ty = ty, .words = try self.arena.dupe(u32, &.{memory_block}) };
        return .{ .ty = ty, .words = words.items };
    }

    /// A literal's field value: a reference here may be a trap closure.
    fn fieldValue(self: *Fn, id: core.Id) Error!Val {
        const previous = self.field_value;
        self.field_value = self.m.node(id).tag == .reference;
        defer self.field_value = previous;
        return self.expr(id);
    }
    fn productType(self: *Fn, id: core.Id, values: []const Val) Error!Ty {
        const n = self.m.node(id);
        const source = self.m.types.node(self.m.typeOf(id));
        if (source.tag == .product) {
            const items = try self.arena.alloc(Ty, values.len);
            for (values, items) |value, *item| item.* = value.ty;
            return self.g.types.tuple(items);
        }
        if (source.tag != .record or n.tag != .record) return self.g.typeFailure(self.m, id);
        const fields = try self.arena.alloc(types.Field, values.len);
        for (values, self.m.recordDestinations(id), fields) |value, destination, *field| {
            const spelling = self.m.fieldSpelling(self.m.types.recordField(source, destination).name) orelse return self.g.typeFailure(self.m, id);
            field.* = .{ .name = try self.g.types.fieldName(spelling), .ty = value.ty };
        }
        const ty = try self.g.types.record(fields);
        try self.refine(self.m.typeOf(id), ty);
        return ty;
    }
    fn construct(self: *Fn, id: core.Id) Error!Val {
        const n = self.m.node(id);
        const constructor = self.m.constructor(n.a);
        const payload = if (n.b != 0) try self.expr(n.b) else unitVal();
        // The node's type, or the one the payload's value gives the nominal.
        const ty = self.g.types.lower(self.m, self.m.typeOf(id), self.env) catch |err| switch (err) {
            error.Unsupported => try self.constructedType(constructor, payload, id),
            else => return err,
        };
        return self.wrapVariant(ty, constructor.tag, payload, id);
    }
    fn constructedType(self: *Fn, constructor: core.Constructor, payload: Val, id: core.Id) Error!Ty {
        const shape = self.m.types.node(self.m.typeOf(id));
        if (shape.tag != .nominal) return self.g.typeFailure(self.m, id);
        const identity: T.NominalIdentity = .{ .unit = shape.a, .decl = shape.b };
        const owner = self.g.types.module(identity.unit) orelse return self.g.typeFailure(self.m, id);
        const ordinal = self.g.types.nominalOrdinal(owner, identity) catch return self.g.typeFailure(self.m, id);
        const nominal = owner.nominal(ordinal);
        // The declaring unit's constructor of the same tag gives the payload in its parameters.
        const declared = for (owner.nominalConstructors(ordinal)) |candidate| {
            if (owner.constructor(candidate).tag == constructor.tag) break owner.constructor(candidate);
        } else return self.g.typeFailure(self.m, id);
        _ = nominal;
        // The payload binds the constructor's scheme variables; its result
        // type in them is the nominal type.
        var env: types.Env = .empty;
        defer env.deinit(self.a());
        if (declared.payload != 0) try self.g.types.match(owner, declared.payload, payload.ty, &env);
        const signature = owner.types.node(declared.scheme.root);
        const result = if (signature.tag == .function) signature.b else declared.scheme.root;
        const ty = try self.g.types.lowerHoles(owner, result, &env);
        try self.refine(self.m.typeOf(id), ty);
        return ty;
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
        if (payload.ty == types.never) return neverVal();
        if (try self.isBoxed(ty, id)) {
            const memory_block = try self.newBlock(ty, id);
            if (cases.payloads.len > 1) {
                try self.opIndex(.local_get, memory_block);
                try self.i32Const(tag);
                try self.op(.i32_store);
                try self.code.uleb(self.a(), 2);
                try self.code.uleb(self.a(), 0);
            }
            try self.writeFlat(memory_block, if (cases.payloads.len > 1) 4 else 0, payload, id);
            return .{ .ty = ty, .words = try self.arena.dupe(u32, &.{memory_block}) };
        }
        const position_ = try self.variantPosition(cases, tag, id);
        if ((try self.layout(cases.payloads[position_], id)).len != payload.words.len)
            return self.g.fail(self.m, id, "constructor payload of type {s} ({d} words) does not match its declared {s} ({d} words)", .{ @tagName(self.tagOf(payload.ty)), payload.words.len, @tagName(self.tagOf(cases.payloads[position_])), (try self.layout(cases.payloads[position_], id)).len });
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
        if (try self.isBoxed(value.ty, id)) return self.readFlat(value.words[0], if (cases.payloads.len > 1) 4 else 0, payload_ty, id);
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
            if (variants[0].field >= self.g.types.tupleItems(value.ty).len) return self.g.fail(self.m, id, "tuple projection out of range", .{});
            return self.tupleItem(value, variants[0].field, id);
        }
        const nominal_field = variants.len != 0 and projection.nominal.decl != 0;
        if (nominal_field) {
            name_symbol = for (self.m.constructors) |constructor| {
                const identity = self.m.nominal(constructor.nominal).identity;
                if (!sameNominal(self.m, identity, projection.nominal) or constructor.tag != variants[0].tag) continue;
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
        if (self.g.types.findField(record.ty, name)) |position| return self.recordField(record, position, id);
        if (nominal_field) return self.g.fail(self.m, id, "projected field missing", .{});
        // Not a data field: a receiver member, called with the value.
        if (self.tagOf(value.ty) == .record) return self.g.fail(self.m, id, "projected field missing", .{});
        const identity = self.g.receiverIdentity(value.ty) orelse return self.g.fail(self.m, id, "member of a {s}", .{@tagName(self.g.types.node(value.ty).tag)});
        const target = self.g.dispatchTarget(self.m, identity, projection.field, .none) orelse return self.g.fail(self.m, id, "no member {s} for this receiver", .{spelling});
        const arguments = try self.arena.dupe(Val, &.{value});
        const callee = try self.g.calleeFromArguments(target, arguments, self.m, id);
        return self.callTarget(target, arguments, callee, try self.restType(callee, 1, id), id);
    }

    fn match(self: *Fn, id: core.Id) Error!Val {
        const info = self.m.matchInfo(id);
        const inputs = self.m.matchInputs(id);
        const values = try self.arena.alloc(Val, inputs.len);
        for (inputs, values) |input, *slot| {
            slot.* = try self.expr(input);
            if (slot.ty == types.never) return neverVal();
        }
        const result = try self.arena.create(?Val);
        result.* = null;
        const merges = self.m.branchMerges(id);
        const merged = try self.arena.alloc(?Val, merges.len);
        @memset(merged, null);
        var falls = false;
        const done = try self.open(.block);
        for (self.m.matchArms(id), 0..) |arm, arm_index| {
            const rows = self.m.armRows(arm);
            const next = try self.open(.block);
            if (rows.len == 1) {
                for (self.m.rowPatterns(rows[0]), values) |pattern, value| try self.test_(pattern, value, next, id);
            } else {
                // Alternatives bind the same names; later rows copy into the first row's locals.
                const matched = try self.open(.block);
                var first: std.AutoHashMapUnmanaged(core.BindingId, Val) = .empty;
                for (rows, 0..) |row, row_index| {
                    const row_fail = try self.open(.block);
                    var before = try self.bindings.clone(self.a());
                    defer before.deinit(self.a());
                    for (self.m.rowPatterns(row), values) |pattern, value| try self.test_(pattern, value, row_fail, id);
                    var it = self.bindings.iterator();
                    while (it.next()) |entry| {
                        const prior = before.get(entry.key_ptr.*);
                        if (prior != null and std.mem.eql(u32, prior.?.words, entry.value_ptr.words)) continue;
                        if (row_index == 0) {
                            const owned = try self.fresh(entry.value_ptr.ty, id);
                            try self.copy(entry.value_ptr.*, owned, id);
                            try first.put(self.arena, entry.key_ptr.*, owned);
                        } else if (first.get(entry.key_ptr.*)) |target| try self.copy(entry.value_ptr.*, target, id);
                    }
                    try self.br(.br, matched);
                    try self.close();
                }
                try self.br(.br, next);
                try self.close();
                var it = first.iterator();
                while (it.next()) |entry| try self.bindings.put(self.a(), entry.key_ptr.*, entry.value_ptr.*);
            }
            if (arm.guard != 0) {
                try self.push(try self.expr(arm.guard));
                try self.op(.i32_eqz);
                try self.br(.br_if, next);
            }
            const body = try self.stmt(arm.body);
            if (body.ty != types.never) {
                falls = true;
                if (!info.statement) try self.deliver(body, result, id);
                // A two-arm statement match carries rebindings like an if.
                if (merges.len != 0 and arm_index < 2) for (merges, merged) |merge, *slot| {
                    if (self.bindings.get(if (arm_index == 0) merge.then_binding else merge.else_binding)) |value| try self.deliver(value, slot, id);
                };
            }
            try self.br(.br, done);
            try self.close();
        }
        try self.op(.unreachable_);
        try self.close();
        for (merges, merged) |merge, slot| if (slot) |value| try self.bindings.put(self.a(), merge.result, value);
        if (!falls) return neverVal();
        if (info.statement) return unitVal();
        return result.* orelse neverVal();
    }

    /// Tests `pattern` against `value`, branching to `fail` (a Wasm depth) on
    /// mismatch, and binds its names.
    fn test_(self: *Fn, pattern_id: core.PatternId, value: Val, fail: ?u32, id: core.Id) Error!void {
        const pattern = self.m.pattern(pattern_id);
        if (value.ty == types.never) return;
        switch (pattern.tag) {
            .wildcard => {},
            .bind => {
                try self.refine(self.m.binding(pattern.a).ty, value.ty);
                try self.bindings.put(self.a(), pattern.a, value);
            },
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
                    .tuple => for (children, 0..) |child, index| try self.test_(child, try self.tupleItem(value, index, id), fail, id),
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
                    // A boxed value's tag is the first word of its block.
                    if (try self.isBoxed(value.ty, id)) {
                        try self.op(.i32_load);
                        try self.code.uleb(self.a(), 2);
                        try self.code.uleb(self.a(), 0);
                    }
                    try self.i32Const(constructor.tag);
                    try self.op(.i32_ne);
                    try self.failIf(fail, id);
                }
                if (pattern.b != 0) try self.test_(pattern.b, try self.unwrapVariant(value, constructor.tag, id), fail, id);
            },
            .record_payload => {
                if (self.g.types.node(value.ty).tag != .record) return self.g.fail(self.m, id, "record pattern on a non-record", .{});
                // A one-field record's child is that field's own pattern.
                const children: []const core.PatternId = if (self.m.pattern(pattern.b).tag == .product) self.m.patternChildren(pattern.b) else &.{pattern.b};
                try self.recordPattern(children, self.m.types.node(pattern.ty), value, fail, id);
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
            try self.test_(child, try self.recordField(value, position, id), fail, id);
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
    /// assign, but a boxed carry's new value is copied into its slot.
    fn assignCarries(self: *Fn, values: []const Val, targets: []const Val, slots: []const bool, id: core.Id) Error!void {
        var plain_values: std.ArrayList(Val) = .empty;
        var plain_targets: std.ArrayList(Val) = .empty;
        for (values, targets, slots) |value, target, slot| {
            if (!slot) {
                try plain_values.append(self.arena, value);
                try plain_targets.append(self.arena, target);
                continue;
            }
            if (value.ty == types.never or value.words[0] == target.words[0]) continue;
            try self.memoryCopy(target.words[0], 0, value.words[0], try self.flatBytes(value.ty, id));
        }
        try self.assign(plain_values.items, plain_targets.items, id);
    }
    fn holdsClosure(self: *Fn, ty: Ty) Error!bool {
        const n = self.g.types.node(ty);
        return switch (n.tag) {
            .function => true,
            .tuple => for (self.g.types.tupleItems(ty)) |item| {
                if (try self.holdsClosure(item)) break true;
            } else false,
            .record => for (0..n.b) |index| {
                if (try self.holdsClosure(self.g.types.recordField(ty, index).ty)) break true;
            } else false,
            .nominal => blk: {
                const cases = self.g.types.variants(ty) catch break :blk true;
                for (cases.payloads) |payload| if (payload != ty and try self.holdsClosure(payload)) break :blk true;
                break :blk false;
            },
            else => false,
        };
    }
    fn carryVals(self: *Fn, carries: []const core.LoopCarry, comptime field: []const u8, id: core.Id) Error![]Val {
        const out = try self.arena.alloc(Val, carries.len);
        for (carries, out) |carry, *slot| slot.* = try self.fresh(try self.lower(self.m.binding(@field(carry, field)).ty, id), id);
        return out;
    }
    fn loop(self: *Fn, id: core.Id) Error!Val {
        const info = self.m.loopInfo(id);
        const carries = self.m.loopCarries(id);
        const incoming = try self.arena.alloc(Val, carries.len);
        for (carries, incoming) |carry, *slot| slot.* = self.bindings.get(carry.incoming) orelse return self.g.fail(self.m, id, "loop carry without an incoming value", .{});
        const iteration = try self.arena.alloc(Val, carries.len);
        const outgoing = try self.arena.alloc(Val, carries.len);
        // A boxed carry lives in a slot reserved before the loop, so each
        // iteration can release what it allocated.
        const slots = try self.arena.alloc(bool, carries.len);
        for (incoming, iteration, outgoing, slots) |value, *current, *after, *slot| {
            slot.* = try self.isBoxed(value.ty, id);
            current.* = if (slot.*) .{ .ty = value.ty, .words = try self.arena.dupe(u32, &.{try self.newBlock(value.ty, id)}) } else try self.fresh(value.ty, id);
            after.* = try self.fresh(value.ty, id);
        }
        try self.assignCarries(incoming, iteration, slots, id);
        for (carries, iteration) |carry, value| try self.bindings.put(self.a(), carry.iteration, value);
        var index: ?u32 = null;
        var end: ?Val = null;
        var source: ?Val = null;
        switch (info.kind) {
            .forever => {},
            .range => {
                index = try self.local32();
                try self.copy(try self.expr(info.first), .{ .ty = types.u32_, .words = try self.arena.dupe(u32, &.{index.?}) }, id);
                end = try self.fresh(types.u32_, id);
                try self.copy(try self.expr(info.end), end.?, id);
            },
            .array => {
                source = try self.expr(info.first);
                index = try self.constLocal(0);
                end = .{ .ty = types.u32_, .words = try self.arena.dupe(u32, &.{try self.lengthOf(source.?, id)}) };
            },
        }
        const exit = try self.open(.block);
        const top = try self.open(.loop);
        if (index) |counter| {
            try self.opIndex(.local_get, counter);
            try self.opIndex(.local_get, end.?.words[0]);
            try self.op(.i32_ge_u);
            _ = try self.open(.if_);
            try self.assign(iteration, outgoing, id);
            try self.br(.br, exit);
            try self.close();
            const current = try self.local32();
            try self.opIndex(.local_get, counter);
            try self.opIndex(.local_set, current);
            try self.opIndex(.local_get, counter);
            try self.i32Const(1);
            try self.op(.i32_add);
            try self.opIndex(.local_set, counter);
            const item: Val = if (source) |container| try self.readElement(container, current, id) else .{ .ty = types.u32_, .words = try self.arena.dupe(u32, &.{current}) };
            if (info.pattern != 0) try self.test_(info.pattern, item, null, id);
        }
        // An iteration releases what it allocated unless a carried value is
        // a closure; fresh owners cannot be carried, and a stale one traps.
        var release = true;
        for (iteration) |value| if (try self.holdsClosure(value.ty)) {
            release = false;
        };
        const marks: [2]u32 = .{ try self.local(.i32), try self.local(.i32) };
        const mark_at = self.code.list.items.len;
        const allocations = self.allocations;
        const unused = try self.arena.create(?Val);
        unused.* = null;
        try self.labels.append(self.a(), .{ .target = id, .depth = exit, .result = unused, .kind = .loop, .top = top, .iteration = iteration, .outgoing = outgoing, .release = if (release) marks else null, .slots = slots });
        const body = try self.stmt(info.body);
        const label = self.labels.pop().?;
        if (body.ty != types.never) {
            const backedge = try self.arena.alloc(Val, carries.len);
            for (carries, backedge) |carry, *slot| slot.* = self.bindings.get(carry.backedge) orelse return self.g.fail(self.m, id, "loop carry without a backedge value", .{});
            try self.assignCarries(backedge, iteration, slots, id);
            if (label.release) |pair| if (self.allocations != allocations) try self.releaseTo(pair[0], pair[1]);
            try self.br(.br, top);
        }
        if (release and (self.allocations != allocations or label.used)) {
            // Insert the iteration's marks at its start, now that the body is known to allocate.
            var prefix: W.Bytes = .{};
            defer prefix.deinit(self.a());
            try self.markInto(&prefix, marks[0], marks[1]);
            try self.code.list.insertSlice(self.a(), mark_at, prefix.items());
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
                try self.assignCarries(values, label.iteration, label.slots, id);
                if (label.release) |pair| {
                    try self.releaseTo(pair[0], pair[1]);
                    self.labels.items[at].used = true;
                }
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
        _ = try self.stmt(n.c);
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

/// The result type of a scalar operator on operands of type `operand`.
fn scalarResult(op: core.Op, operand: Ty) Ty {
    return switch (op) {
        .equal, .not_equal, .less, .less_equal, .greater, .greater_equal => types.boolean,
        .convert_u32_f32 => types.f32_,
        .convert_f32_u32 => types.u32_,
        else => operand,
    };
}

fn operatorOf(op: core.Op) ?T.Operator {
    return switch (op) {
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
        else => null,
    };
}

/// Whether two catalog identities name the same nominal type.
fn sameNominal(m: *const core.Module, left: T.NominalIdentity, right: T.NominalIdentity) bool {
    _ = m;
    return left.unit == right.unit and left.decl == right.decl;
}

/// Marks a primitive node (rather than a binding) as a partial target.
const primitive_node_bit: u32 = 0x8000_0000;

pub fn emitInstance(g: *Generator, id: u32) Error!void {
    const instance = g.instance(id);
    const m = g.unitModule(instance.key.unit);
    var arena = std.heap.ArenaAllocator.init(g.allocator);
    defer arena.deinit();
    var env: types.Env = .empty;
    defer env.deinit(g.allocator);
    var it = instance.env.iterator();
    while (it.next()) |entry| try env.put(g.allocator, entry.key_ptr.*, entry.value_ptr.*);
    var f: Fn = .{ .g = g, .m = m, .env = &env, .arena = arena.allocator(), .instance_id = id };
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
    const owner_mark = try f.local(.i32);
    const stack_mark = try f.local(.i32);
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
        .partial, .primitive, .constructor, .host, .pool, .trap => {},
    }
    const slot = try f.arena.create(?Val);
    slot.* = if (instance.inferring) null else try f.fresh(instance.result, root);
    const exit = try f.open(.block);
    try f.labels.append(g.allocator, .{ .target = std.math.maxInt(u32), .depth = exit, .result = slot, .kind = .function });
    const value = switch (instance.key.kind) {
        .named, .lambda => try f.stmt(root),
        .partial, .primitive, .constructor => try f.adapterBody(instance, captures, inputs[0]),
        .host => try f.hostBody(instance, captures, inputs[0]),
        .pool => try f.poolBody(instance),
        .trap => blk: {
            try f.op(.unreachable_);
            break :blk Val{ .ty = types.never };
        },
    };
    f.deliver(value, slot, root) catch |err| switch (err) {
        error.Unsupported => try g.recordFailure(m, root),
        else => return err,
    };
    try f.close();
    // An inferred result is the type of the first value the body delivers.
    if (instance.inferring) instance.result = if (slot.*) |delivered| delivered.ty else types.never;
    const result: Val = slot.* orelse .{ .ty = types.never };
    const release = f.allocates and !try g.holdsMemory(instance.result);
    if (release) try f.releaseTo(owner_mark, stack_mark);
    if (result.ty == types.never) try f.op(.unreachable_) else try f.push(result);
    try f.op(.end);
    var prologue: W.Bytes = .{};
    defer prologue.deinit(g.allocator);
    if (release) try f.markInto(&prologue, owner_mark, stack_mark);
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

/// ABI 8 value kinds (runtime_ir.Scalar), and callback import names.
const Abi = enum(u8) { unit = 0, u32 = 1, bool = 2, f32 = 3, array_u32 = 5, array_f32 = 6 };
fn abiKind(g: *Generator, ty: Ty) ?Abi {
    const n = g.types.node(ty);
    return switch (n.tag) {
        .unit => .unit,
        .u32 => .u32,
        .boolean => .bool,
        .f32 => .f32,
        .array, .grow, .resize => switch (g.types.node(n.a).tag) {
            .u32 => .array_u32,
            .f32 => .array_f32,
            else => null,
        },
        else => null,
    };
}
fn abiMachine(kind: Abi) W.ValType {
    return if (kind == .f32) .f32 else .i32;
}
fn isArray(kind: Abi) bool {
    return kind == .array_u32 or kind == .array_f32;
}
/// A Foreign host callback parameter: its argument and result kinds.
pub fn callbackAbi(g: *Generator, ty: Ty) ?[2]Abi {
    const n = g.types.node(ty);
    if (n.tag != .function) return null;
    return .{ abiKind(g, n.a) orelse return null, abiKind(g, n.b) orelse return null };
}
/// Declares the host import for a callback shape; imports precede functions.
pub fn hostImport(g: *Generator, kinds: [2]Abi) Error!u32 {
    const key: [2]u8 = .{ @backingInt(kinds[0]), @backingInt(kinds[1]) };
    if (g.host_imports.get(key)) |found| return found;
    const name = try g.arena.allocator().print("call_{s}_{s}", .{ @tagName(kinds[0]), @tagName(kinds[1]) });
    const signature = try g.module.signature(&.{ .externref, abiMachine(kinds[0]) }, &.{abiMachine(kinds[1])});
    const import = try g.module.importFunction("blot:host/1", name, signature);
    try g.host_imports.put(g.allocator, key, import);
    return import;
}

/// An exported entry: resets temporaries, converts its one ABI argument,
/// calls the instance, converts the result and releases temporaries.
pub fn emitExport(g: *Generator, m: *const core.Module, body: *const core.Body, abi: *W.Bytes) Error!void {
    var empty: types.Env = .empty;
    const ty = g.types.lower(m, m.binding(body.binding).ty, &empty) catch |err| switch (err) {
        error.Unsupported => return g.typeFailure(m, body.root),
        else => return err,
    };
    const instance_id = try g.named(.{ .unit = m.unit, .binding = body.binding }, ty, m, body.root);
    const instance = g.instance(instance_id);
    const parameter = instance.parameters[0];
    const callback = callbackAbi(g, parameter);
    const parameter_abi: Abi = if (callback != null) .unit else abiKind(g, parameter) orelse return g.fail(m, body.root, "entry parameters of type {s} are not supported", .{@tagName(g.types.node(parameter).tag)});
    const result_abi = abiKind(g, instance.result) orelse return g.fail(m, body.root, "entry results of type {s} are not supported", .{@tagName(g.types.node(instance.result).tag)});
    const machine: W.ValType = if (callback != null) .externref else abiMachine(parameter_abi);
    const signature = try g.module.signature(&.{machine}, &.{abiMachine(result_abi)});
    const function = try g.module.addFunction(signature);
    var arena = std.heap.ArenaAllocator.init(g.allocator);
    defer arena.deinit();
    var f: Fn = .{ .g = g, .m = m, .env = &empty, .arena = arena.allocator() };
    defer {
        f.code.deinit(g.allocator);
        f.locals.deinit(g.allocator);
    }
    _ = try f.local(machine);
    f.parameter_words = 1;
    // The host requires the storage exports exactly when packets cross.
    const packets = isArray(parameter_abi) or isArray(result_abi) or (if (callback) |kinds| isArray(kinds[0]) or isArray(kinds[1]) else false);
    const rt = try g.runtime_();
    // Recover temporaries a trapped earlier call may have left behind.
    try f.i32Const(1);
    try f.opIndex(.call, rt.release);
    try f.i32Const(rt.layout.stack_base);
    try f.opIndex(.global_set, rt.stack_pointer);
    var argument: Val = .{ .ty = types.unit };
    if (callback) |kinds| {
        const slot = g.module.host_slots;
        g.module.host_slots += 1;
        try f.i32Const(slot);
        try f.opIndex(.local_get, 0);
        try f.opIndex(.table_set, 1);
        argument = try f.hostClosure(parameter, kinds, slot);
    } else if (isArray(parameter_abi)) {
        argument = try f.fromPacket(parameter, 0);
    } else if (parameter != types.unit) {
        argument = .{ .ty = parameter, .words = try f.arena.dupe(u32, &.{0}) };
    }
    try f.push(argument);
    try f.opIndex(.call, instance.function);
    const result = try f.pop(instance.result, body.root);
    if (isArray(result_abi)) {
        const packet = try f.toPacket(result, body.root);
        try f.i32Const(1);
        try f.opIndex(.call, rt.release);
        try f.opIndex(.local_get, packet);
    } else {
        try f.i32Const(1);
        try f.opIndex(.call, rt.release);
        if (instance.result == types.unit) try f.i32Const(0) else try f.push(result);
    }
    try f.op(.end);
    try finish(g, function, &f);
    const name = m.name(body.export_name);
    try g.module.exportItem(name, .function, function);
    try abi.name(g.allocator, name);
    if (callback) |kinds| {
        try abi.byte(g.allocator, 4);
        try abi.byte(g.allocator, @backingInt(kinds[0]));
        try abi.byte(g.allocator, @backingInt(kinds[1]));
    } else try abi.byte(g.allocator, @backingInt(parameter_abi));
    try abi.byte(g.allocator, @backingInt(result_abi));
    if (packets and !g.exported_storage) {
        g.exported_storage = true;
        try g.module.exportItem("blot:memory", .memory, 0);
        try g.module.exportItem("blot:allocate", .function, rt.allocate);
        try g.module.exportItem("blot:reset", .function, rt.reset);
    }
}
