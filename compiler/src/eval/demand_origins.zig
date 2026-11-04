//! Read-only stored-Memo outcome relationships over current executable Source.
//! Constructor markers alone cannot certify mutable cache or producer edges.
const std = @import("std");
const ir = @import("../backend/runtime_ir.zig");
const wasm = @import("../backend/wasm.zig");
const heap = @import("../runtime/runtime_layout.zig");

pub const Force = struct {
    cell_parameter: u32,
    provider_parameter: u32,
    producer: u32,
    guard_global: ?u32,
    producer_call: usize,
    cache_publication: usize,
    ready_publication: usize,
};
fn matches(actual: []const ir.Instruction, expected: []const ir.Instruction) bool {
    if (actual.len < expected.len) return false;
    for (actual[0..expected.len], expected) |left, right| if (!std.meta.eql(left, right)) return false;
    return true;
}
/// Ready returns the existing cached edge; pending evaluates the exact producer
/// with this cell's environment and the caller's head, then owns its result in
/// the cache before publishing ready. A guarded early exit resets pending and
/// returns zero. This is not a confinement, borrowing or dispatch permission.
/// Call-site flow must still identify the actual cell and match its constructor
/// producer; reference roles or equal machine signatures cannot supply that.
pub fn force(module: *const wasm.Module, function: u32) ?Force {
    if (function >= module.functions.items.len or module.runtimeHelper(function)) return null;
    const arena = module.arena orelse return null;
    const body = &module.functions.items[function];
    const code = body.instructions.items;
    const roles = ir.packParameterRoles(&.{ .reference, .scalar, .reference });
    if (body.entry or body.provider_parameter != 2 or body.parameters.len != 3 or body.parameter_roles != roles or body.result != .i32 or body.result_role != .reference or body.locals.items.len != 2) return null;
    for (body.parameters) |machine| if (machine != .i32) return null;
    for (body.locals.items) |machine| if (machine != .i32) return null;
    if (code.len != 50 and code.len != 61) return null;
    if (code[27].op != .call or code[27].operand >= module.functions.items.len or module.runtimeHelper(code[27].operand)) return null;
    const producer = &module.functions.items[code[27].operand];
    if (producer.entry or producer.provider_parameter != 2 or producer.parameters.len != 3 or producer.parameter_roles != roles or producer.result != .i32 or producer.result_role != .reference) return null;
    for (producer.parameters) |machine| if (machine != .i32) return null;
    const status = heap.offset(heap.Demand, "status");
    const cached = heap.offset(heap.Demand, "cached");
    if (!matches(code, &.{
        .{ .op = .local_get },                                                                              .{ .op = .local_set, .operand = 3 },
        .{ .op = .local_get, .operand = 3 },                                                                .{ .op = .i32_load, .operand = status },
        .{ .op = .i32_const, .operand = @backingInt(heap.DemandStatus.ready) },                             .{ .op = .i32_eq },
        .{ .op = .if_ },                                                                                    .{ .op = .local_get, .operand = 3 },
        .{ .op = .i32_load, .operand = cached },                                                            .{ .op = .local_set, .operand = 4 },
        .{ .op = .else_ },                                                                                  .{ .op = .local_get, .operand = 3 },
        .{ .op = .i32_load, .operand = status },                                                            .{ .op = .if_ },
        .{ .op = .unreachable_ },                                                                           .{ .op = .end },
        .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = 6, .roles = 3 }) }, .{ .op = .local_get, .operand = 3 },
        .{ .op = .local_get, .operand = 3 },                                                                .{ .op = .i32_const, .operand = status },
        .{ .op = .i32_add },                                                                                .{ .op = .i32_const, .operand = @backingInt(heap.DemandStatus.evaluating) },
        .{ .op = .call, .operand = arena.store_word },                                                      .{ .op = .local_get, .operand = 3 },
        .{ .op = .i32_load, .operand = heap.offset(heap.Demand, "environment") },                           .{ .op = .i32_const },
        .{ .op = .local_get, .operand = 2 },                                                                .{ .op = .call, .operand = code[27].operand },
        .{ .op = .local_set, .operand = 4 },
    })) return null;
    var at: usize = 29;
    var guard: ?u32 = null;
    if (code.len == 61) {
        const owner = code[at].operand;
        if (owner >= module.globals.items.len) return null;
        const global = module.globals.items[owner];
        if (!global.mutable or global.scalar != .u32) return null;
        if (!matches(code[at..], &.{
            .{ .op = .global_get, .operand = owner },                                 .{ .op = .if_ },
            .{ .op = .local_get, .operand = 3 },                                      .{ .op = .local_get, .operand = 3 },
            .{ .op = .i32_const, .operand = status },                                 .{ .op = .i32_add },
            .{ .op = .i32_const, .operand = @backingInt(heap.DemandStatus.pending) }, .{ .op = .call, .operand = arena.store_word },
            .{ .op = .i32_const },                                                    .{ .op = .return_ },
            .{ .op = .end },
        })) return null;
        guard = owner;
        at += 11;
    }
    if (!matches(code[at..], &.{
        .{ .op = .local_get, .operand = 3 },                                    .{ .op = .local_get, .operand = 3 },
        .{ .op = .i32_const, .operand = cached },                               .{ .op = .i32_add },
        .{ .op = .local_get, .operand = 4 },                                    .{ .op = .call, .operand = arena.store_word },
        .{ .op = .local_get, .operand = 3 },                                    .{ .op = .local_get, .operand = 3 },
        .{ .op = .i32_const, .operand = status },                               .{ .op = .i32_add },
        .{ .op = .i32_const, .operand = @backingInt(heap.DemandStatus.ready) }, .{ .op = .call, .operand = arena.store_word },
        .{ .op = .local_get, .operand = 3 },                                    .{ .op = .global_get, .operand = arena.base },
        .{ .op = .i32_lt_u },                                                   .{ .op = .if_ },
        .{ .op = .global_get, .operand = arena.heap },                          .{ .op = .global_set, .operand = arena.base },
        .{ .op = .end },                                                        .{ .op = .end },
        .{ .op = .local_get, .operand = 4 },
    })) return null;
    return .{ .cell_parameter = 0, .provider_parameter = 2, .producer = code[27].operand, .guard_global = guard, .producer_call = 27, .cache_publication = at + 5, .ready_publication = at + 11 };
}
