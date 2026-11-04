//! Bounded no-escape proof for an exact public host callback formal.
//! Logical callable reads authorize invocation; machine signatures alone do not.
const std = @import("std");
const w = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const Value = enum { ordinary, descriptor, environment, function };
const State = struct {
    stack: [256]Value = @splat(.ordinary),
    top: usize = 0,
    locals: [256]Value = @splat(.ordinary),
    fn push(self: *State, value: Value) bool {
        if (self.top == self.stack.len) return false;
        self.stack[self.top] = value;
        self.top += 1;
        return true;
    }
    fn pop(self: *State) ?Value {
        if (self.top == 0) return null;
        self.top -= 1;
        return self.stack[self.top];
    }
    fn ordinary(self: *State) bool {
        return self.pop() == .ordinary;
    }
};
/// Exact compiler-owned host stub, including guard-before-handle-read order.
pub fn hostStub(module: *const w.Module, body: *const ir.Function) bool {
    const references = module.host_references orelse return false;
    const code = body.instructions.items;
    if (body.entry or code.len != 12 or code[11].op != .call_import) return false;
    const callback = module.hostCallbackImport(code[11].operand) orelse return false;
    if (body.result != callback.result.machine() or body.result_role != callback.result.role() or body.provider_parameter != 2 or !std.mem.eql(ir.ValueType, body.parameters, &.{ .i32, callback.parameter.machine(), .i32 }) or body.parameter_roles != ir.packParameterRoles(&.{ .reference, callback.parameter.role(), .reference })) return false;
    const marker: ir.Ownership = .{ .kind = .scope, .chunk = 14 };
    const expected = [_]ir.Instruction{
        .{ .op = .ownership, .operand = @bitCast(marker) },
        .{ .op = .local_get, .operand = 0 },
        .{ .op = .global_get, .operand = references.active },
        .{ .op = .i32_ne },
        .{ .op = .if_ },
        .{ .op = .unreachable_ },
        .{ .op = .end },
        .{ .op = .local_get, .operand = 0 },
        .{ .op = .i32_load, .operand = 8 },
        .{ .op = .host_ref_get },
        .{ .op = .local_get, .operand = 1 },
        code[11],
    };
    for (code, expected) |actual, wanted| if (!std.meta.eql(actual, wanted)) return false;
    return true;
}
pub fn confined(module: *const w.Module, target: u32, stub: u32, ty: u32, guard: ?u32) bool {
    if (target >= module.functions.items.len or stub >= module.functions.items.len or ty == 0) return false;
    const body = &module.functions.items[target];
    const callback = &module.functions.items[stub];
    if (body.entry or body.parameters.len != 2 or !std.mem.eql(ir.ValueType, body.parameters, &.{ .i32, .i32 }) or body.parameterRole(0) != .reference or body.provider_parameter != 1) return false;
    if (body.locals.items.len > 254 or body.instructions.items.len > 4096 or callback.callable_layout != ty or !hostStub(module, callback) or callback.parameters.len != 3 or callback.parameterRole(0) != .reference or callback.parameterRole(2) != .reference) return false;
    var state: State = .{};
    state.locals[0] = .descriptor;
    const code = body.instructions.items;
    var at: usize = 0;
    var invokes: usize = 0;
    while (at < code.len) : (at += 1) {
        const inst = code[at];
        switch (inst.op) {
            .local_get => {
                if (inst.operand >= body.parameters.len + body.locals.items.len or !state.push(state.locals[inst.operand])) return false;
            },
            .local_set, .local_tee => {
                if (inst.operand < body.parameters.len or inst.operand >= body.parameters.len + body.locals.items.len) return false;
                const value = state.pop() orelse return false;
                state.locals[inst.operand] = value;
                if (inst.op == .local_tee and !state.push(value)) return false;
            },
            .i32_load => {
                const address = state.pop() orelse return false;
                var value: Value = .ordinary;
                if (address == .descriptor) {
                    switch (inst.operand) {
                        0 => {
                            if (ir.callableCodeLayout(code, at) != ty) return false;
                            value = .function;
                        },
                        4 => value = .environment,
                        else => return false,
                    }
                } else if (address != .ordinary) return false;
                if (!state.push(value)) return false;
            },
            .call_indirect => {
                if (inst.operand != callback.signature or ir.indirectResult(code, at) != callback.result_role or state.pop() != .function or !state.ordinary() or !state.ordinary() or state.pop() != .environment) return false;
                if (callback.result != .none and !state.push(.ordinary)) return false;
                invokes += 1;
            },
            // An opaque callee could observe runtime state independently of
            // the formal. This bounded admission follows no such call.
            .call => return false,
            .global_get => {
                if (inst.operand == module.host_references.?.active or !state.push(.ordinary)) return false;
            },
            .ownership => {
                const annotation: ir.Ownership = @bitCast(inst.operand);
                if (annotation.kind == .scope and annotation.chunk != 0 and annotation.chunk != 1) return false;
            },
            .block => if (at != 0 or inst.operand != @backingInt(body.result)) return false,
            .end => if (at + 1 != code.len) return false,
            .if_ => {
                // Preserve the exact generated cancellation guard. It returns
                // zero without publishing a callback or changing any alias.
                const owner = guard orelse return false;
                if (at == 0 or at + 3 >= code.len or code[at - 1].op != .global_get or code[at - 1].operand != owner or inst.operand != 0 or code[at + 1].op != .i32_const or code[at + 1].operand != 0 or code[at + 2].op != .return_ or code[at + 3].op != .end or !state.ordinary()) return false;
                at += 3;
            },
            .br => if (at + 3 != code.len or inst.operand != 0 or state.top != 1 or state.stack[0] != .ordinary) return false,
            .unreachable_ => if (at + 2 != code.len or at == 0 or code[at - 1].op != .br) return false,
            .call_import, .return_, .loop, .else_, .br_if, .resource_retire => return false,
            else => {
                const contract = ir.contract(module, body, inst);
                if (contract.effect == .host or contract.effect == .control or contract.arity > 3) return false;
                for (0..contract.arity) |_| if (!state.ordinary()) return false;
                if (contract.result != .none and !state.push(.ordinary)) return false;
            },
        }
    }
    return invokes != 0 and state.top == 1 and state.stack[0] == .ordinary;
}
