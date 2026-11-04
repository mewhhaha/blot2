//! Shared proof for bounded scalar readers across direct and private calls.
const ir = @import("runtime_ir.zig");
// A checked private callback can expose bounded scalar field consumption.
// Internal blocks keep their labels; every local is freshly initialized for
// each activation. Memory writes, allocation, other calls and loops decline.
pub fn check(body: *const ir.Function) bool {
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

/// Locals that may be read before this activation writes them. Other locals
/// need no synthetic zero store, preserving constant offsets for later passes.
pub fn zeroes(body: *const ir.Function) u64 {
    const Frame = struct { entry: u64, conditional: bool, alternate: ?u64 = null };
    var frames: [96]Frame = undefined;
    var depth: usize = 0;
    var defined: u64 = 0;
    for (0..body.parameters.len) |index| defined |= @as(u64, 1) << @intCast(index);
    const parameters = defined;
    var required: u64 = 0;
    for (body.instructions.items) |inst| switch (inst.op) {
        .local_get => {
            const bit = @as(u64, 1) << @intCast(inst.operand);
            if (defined & bit == 0) required |= bit;
        },
        .local_set, .local_tee => defined |= @as(u64, 1) << @intCast(inst.operand),
        .block, .if_ => {
            frames[depth] = .{ .entry = defined, .conditional = inst.op == .if_ };
            depth += 1;
        },
        .else_ => {
            frames[depth - 1].alternate = defined;
            defined = frames[depth - 1].entry;
        },
        .end => {
            depth -= 1;
            const frame = frames[depth];
            defined = frame.entry | (if (frame.conditional and frame.alternate != null) defined & frame.alternate.? else 0);
        },
        .br, .br_if, .unreachable_ => defined = parameters,
        else => {},
    };
    return required;
}

test "scalar readers initialize conditional and untouched locals without obscuring definite offsets" {
    const std = @import("std");
    var parameters = [_]ir.ValueType{.i32};
    var locals = [_]ir.ValueType{ .i32, .f32, .i32 };
    var code = [_]ir.Instruction{
        .{ .op = .local_get },                .{ .op = .if_ },
        .{ .op = .i32_const, .operand = 7 },  .{ .op = .local_set, .operand = 1 },
        .{ .op = .end },                      .{ .op = .local_get, .operand = 2 },
        .{ .op = .i32_reinterpret_f32 },      .{ .op = .drop },
        .{ .op = .i32_const, .operand = 12 }, .{ .op = .local_set, .operand = 3 },
        .{ .op = .local_get, .operand = 3 },  .{ .op = .drop },
        .{ .op = .local_get, .operand = 1 },
    };
    var body: ir.Function = .{ .parameters = &parameters, .result = .i32, .result_role = .scalar, .signature = 0, .parameter_roles = ir.packParameterRoles(&.{.scalar}), .locals = .fromOwnedSlice(&locals), .instructions = .fromOwnedSlice(&code) };
    try std.testing.expect(check(&body));
    try std.testing.expectEqual(@as(u64, 6), zeroes(&body));
    var complete = [_]ir.Instruction{
        .{ .op = .local_get },               .{ .op = .if_ },
        .{ .op = .i32_const, .operand = 7 }, .{ .op = .local_set, .operand = 1 },
        .{ .op = .else_ },                   .{ .op = .i32_const, .operand = 8 },
        .{ .op = .local_set, .operand = 1 }, .{ .op = .end },
        .{ .op = .local_get, .operand = 2 }, .{ .op = .i32_reinterpret_f32 },
        .{ .op = .drop },                    .{ .op = .local_get, .operand = 1 },
    };
    body.instructions = .fromOwnedSlice(&complete);
    try std.testing.expect(check(&body));
    try std.testing.expectEqual(@as(u64, 4), zeroes(&body));
    body.result_role = .reference;
    try std.testing.expect(!check(&body));
}
