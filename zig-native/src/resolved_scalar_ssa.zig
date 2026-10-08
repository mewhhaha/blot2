//! Resolved scalar SSA with structured branches, explicit joins,
//! operands, result types, trap facts and scalar ownership. Admission borrows
//! checked Core; the completed body owns everything needed for emission.
//! Calls and heap values stay on the existing path.
const std = @import("std");
const core = @import("core.zig");
const types = @import("types.zig");
const ir = @import("runtime_ir.zig");
const scalar = @import("scalar_ops.zig");
const A = std.mem.Allocator;
pub const Value = enum(u32) { _ };
pub const Node = struct {
    kind: enum { value, branch, alternate, join } = .value,
    /// Matching structured branch for alternate/join nodes. Phi operands are
    /// selected by that branch, never eagerly evaluated at the join.
    control: ?Value = null,
    instruction: ir.Instruction,
    operands: [2]Value = @splat(@fromBackingInt(0)),
    arity: u2 = 0,
    ty: ir.ValueType,
    ownership: enum { scalar, none } = .scalar,
    may_trap: bool = false,
};
pub const Body = struct {
    nodes: std.ArrayList(Node) = .empty,
    result: Value,
    pub fn deinit(self: *Body, a: A) void {
        self.nodes.deinit(a);
        self.* = undefined;
    }
    /// No source, evaluator, type solver, layout store or provider is read here.
    pub fn emit(self: *const Body, module: *@import("wasm.zig").Module, function: u32) A.Error!void {
        for (self.nodes.items) |node| try module.emit(function, node.instruction);
    }
};
const Error = A.Error || error{Unsupported};
const Builder = struct {
    allocator: A,
    source: *const core.Module,
    parameters: []const core.Parameter,
    nodes: std.ArrayList(Node) = .empty,
    fn append(self: *Builder, node: Node) Error!Value {
        if (self.nodes.items.len >= 4096) return error.Unsupported;
        const result: Value = @fromBackingInt(@intCast(self.nodes.items.len));
        try self.nodes.append(self.allocator, node);
        return result;
    }
    fn value(self: *Builder, id: core.Id, depth: usize) Error!Value {
        if (depth >= 64 or id == 0 or id >= self.source.nodes.len) return error.Unsupported;
        const node = self.source.node(id);
        const result = primitive(node.ty) orelse return error.Unsupported;
        switch (node.tag) {
            .constant => return self.append(.{ .instruction = .{ .op = if (result == .f32) .f32_const else .i32_const, .operand = node.a }, .ty = result }),
            .reference => {
                const ref = self.source.reference(id);
                if (ref.unit != 0 and ref.unit != self.source.unit) return error.Unsupported;
                for (self.parameters, 0..) |parameter, index| if (parameter.binding != 0 and parameter.binding == ref.binding) {
                    if (primitive(parameter.ty) != result) return error.Unsupported;
                    return self.append(.{ .instruction = .{ .op = .local_get, .operand = @intCast(index) }, .ty = result });
                };
                return error.Unsupported;
            },
            .scalar => {
                // A selected source operator can consume implementation/effect
                // evidence. Only authoritative compiler scalar nodes qualify.
                if (node.c != 0 or node.a == 0) return error.Unsupported;
                const left = try self.value(node.a, depth + 1);
                const argument = self.nodes.items[@backingInt(left)].ty;
                const opcode = scalar.opcode(node.op, if (argument == .f32) .f32 else .u32) orelse return error.Unsupported;
                const contract = ir.fixed(opcode);
                if (contract.result != result or contract.arity == 0 or contract.arity > 2 or contract.inputs[0] != argument) return error.Unsupported;
                var operands: [2]Value = .{ left, @fromBackingInt(0) };
                if (contract.arity == 2) {
                    if (node.b == 0) return error.Unsupported;
                    operands[1] = try self.value(node.b, depth + 1);
                    if (self.nodes.items[@backingInt(operands[1])].ty != contract.inputs[1]) return error.Unsupported;
                } else if (node.b != 0) return error.Unsupported;
                return self.append(.{ .instruction = .{ .op = opcode }, .operands = operands, .arity = @intCast(contract.arity), .ty = result, .may_trap = contract.may_trap });
            },
            .if_value => {
                if (self.source.typeOf(node.a) != types.boolean) return error.Unsupported;
                const condition = try self.value(node.a, depth + 1);
                const branch = try self.append(.{ .kind = .branch, .instruction = .{ .op = .if_, .operand = @backingInt(result) }, .operands = .{ condition, @fromBackingInt(0) }, .arity = 1, .ty = .none, .ownership = .none });
                const when_true = try self.value(node.b, depth + 1);
                if (self.nodes.items[@backingInt(when_true)].ty != result) return error.Unsupported;
                _ = try self.append(.{ .kind = .alternate, .control = branch, .instruction = .{ .op = .else_ }, .ty = .none, .ownership = .none });
                const when_false = try self.value(node.c, depth + 1);
                if (self.nodes.items[@backingInt(when_false)].ty != result) return error.Unsupported;
                return self.append(.{ .kind = .join, .control = branch, .instruction = .{ .op = .end }, .operands = .{ when_true, when_false }, .arity = 2, .ty = result });
            },
            else => return error.Unsupported,
        }
    }
};
fn primitive(ty: types.Id) ?ir.ValueType {
    return switch (ty) {
        types.unit, types.boolean, types.u32_type => .i32,
        types.f32_type => .f32,
        else => null,
    };
}
/// Failure to admit a body has no source/evaluator side effects and writes no
/// instructions. OOM remains a compilation failure, not a semantic fallback.
pub fn resolve(a: A, source: *const core.Module, parameters: []const core.Parameter, root: core.Id) A.Error!?Body {
    var builder: Builder = .{ .allocator = a, .source = source, .parameters = parameters };
    var moved = false;
    defer if (!moved) builder.nodes.deinit(a);
    const result = builder.value(root, 0) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    moved = true;
    return .{ .nodes = builder.nodes, .result = result };
}
