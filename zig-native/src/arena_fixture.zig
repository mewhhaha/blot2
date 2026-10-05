//! Test artifact for executed allocator/ABI behavior, independent of checking.
const std = @import("std");
const wasm = @import("wasm.zig");
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var module = wasm.Module.init(allocator);
    defer module.deinit();
    const literal = try module.dataWords(&.{ 3, 1, 2, 3 });
    const identity = try module.addFunction(&.{.i32}, .i32);
    try module.emit(identity, .{ .op = .local_get, .operand = 0 });
    try module.exportFunction(identity, "identity", .array_u32, .array_u32);
    const constant = try module.addFunction(&.{.i32}, .i32);
    try module.emit(constant, .{ .op = .i32_const, .operand = literal });
    try module.exportFunction(constant, "literal", .unit, .array_u32);
    const captured = try module.dataWords(&.{21});
    const target = try module.addFunction(&.{ .i32, .i32 }, .i32);
    for ([_]wasm.Instruction{
        .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_load },
        .{ .op = .local_get, .operand = 1 }, .{ .op = .i32_add },
    }) |instruction| try module.emit(target, instruction);
    const closure = try module.dataWords(&.{ target, captured });
    const invoke = try module.addFunction(&.{.i32}, .i32);
    for ([_]wasm.Instruction{
        .{ .op = .i32_const, .operand = closure }, .{ .op = .i32_load, .operand = 4 },
        .{ .op = .local_get, .operand = 0 },       .{ .op = .i32_const, .operand = closure },
        .{ .op = .i32_load },                      .{ .op = .call_indirect, .operand = module.functions.items[target].signature },
    }) |instruction| try module.emit(invoke, instruction);
    try module.exportFunction(invoke, "captured", .u32, .u32);
    const host_scalar: wasm.Callback = .{ .parameter = .u32, .result = .u32 };
    const scalar_import = try module.importHostCallback(host_scalar);
    const call_host = try module.addFunction(&.{.externref}, .i32);
    for ([_]wasm.Instruction{
        .{ .op = .local_get, .operand = 0 },               .{ .op = .i32_const, .operand = 21 },
        .{ .op = .call_import, .operand = scalar_import },
    }) |instruction| try module.emit(call_host, instruction);
    try module.exportCallbackFunction(call_host, "host_scalar", host_scalar, .u32);
    const references = try module.ensureHostReferences();
    const retained_target = try module.addFunction(&.{ .i32, .i32 }, .i32);
    for ([_]wasm.Instruction{
        .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_load },                              .{ .op = .host_ref_get },
        .{ .op = .local_get, .operand = 1 }, .{ .op = .call_import, .operand = scalar_import },
    }) |instruction| try module.emit(retained_target, instruction);
    const retained = try module.addFunction(&.{.externref}, .i32);
    const mark = try module.addLocal(retained, .i32);
    const handle = try module.addLocal(retained, .i32);
    const environment = try module.addLocal(retained, .i32);
    const result = try module.addLocal(retained, .i32);
    for ([_]wasm.Instruction{
        .{ .op = .global_get, .operand = references.cursor },                                    .{ .op = .local_set, .operand = mark },
        .{ .op = .local_get, .operand = 0 },                                                     .{ .op = .call, .operand = references.retain },
        .{ .op = .drop },                                                                        .{ .op = .local_get, .operand = 0 },
        .{ .op = .call, .operand = references.retain },                                          .{ .op = .local_set, .operand = handle },
        .{ .op = .i32_const, .operand = 4 },                                                     .{ .op = .call, .operand = module.arena.?.allocate },
        .{ .op = .local_tee, .operand = environment },                                           .{ .op = .local_get, .operand = handle },
        .{ .op = .i32_store },                                                                   .{ .op = .local_get, .operand = environment },
        .{ .op = .i32_const, .operand = 21 },                                                    .{ .op = .i32_const, .operand = retained_target },
        .{ .op = .call_indirect, .operand = module.functions.items[retained_target].signature }, .{ .op = .local_set, .operand = result },
        .{ .op = .local_get, .operand = mark },                                                  .{ .op = .call, .operand = references.release },
        .{ .op = .local_get, .operand = result },
    }) |instruction| try module.emit(retained, instruction);
    try module.exportCallbackFunction(retained, "host_retained", host_scalar, .u32);
    const retained_count = try module.addFunction(&.{.i32}, .i32);
    try module.emit(retained_count, .{ .op = .global_get, .operand = references.cursor });
    try module.exportFunction(retained_count, "host_retained_count", .unit, .u32);
    const retained_capacity = try module.addFunction(&.{.i32}, .i32);
    try module.emit(retained_capacity, .{ .op = .host_ref_size });
    try module.exportFunction(retained_capacity, "host_retained_capacity", .unit, .u32);
    const cleared = try module.addFunction(&.{.i32}, .i32);
    try module.emit(cleared, .{ .op = .local_get, .operand = 0 });
    try module.emit(cleared, .{ .op = .host_ref_get });
    try module.emit(cleared, .{ .op = .host_ref_is_null });
    try module.exportFunction(cleared, "host_handle_cleared", .u32, .bool);
    const host_array: wasm.Callback = .{ .parameter = .array_f32, .result = .array_f32 };
    const array_import = try module.importHostCallback(host_array);
    const array_literal = try module.dataWords(&.{ 3, @as(u32, @bitCast(@as(f32, 1.5))), @as(u32, @bitCast(@as(f32, 2.5))), @as(u32, @bitCast(@as(f32, 3.5))) });
    const call_array = try module.addFunction(&.{.externref}, .i32);
    for ([_]wasm.Instruction{
        .{ .op = .local_get, .operand = 0 },              .{ .op = .i32_const, .operand = array_literal },
        .{ .op = .call_import, .operand = array_import },
    }) |instruction| try module.emit(call_array, instruction);
    try module.exportCallbackFunction(call_array, "host_array", host_array, .array_f32);
    const initialized = try module.addGlobal(.u32, 0, true);
    const startup = try module.addFunction(&.{}, .none);
    try module.emit(startup, .{ .op = .i32_const, .operand = 42 });
    try module.emit(startup, .{ .op = .global_set, .operand = initialized });
    module.start = startup;
    const read_initialized = try module.addFunction(&.{.i32}, .i32);
    try module.emit(read_initialized, .{ .op = .global_get, .operand = initialized });
    try module.exportFunction(read_initialized, "initialized", .unit, .u32);
    const bytes = try module.assemble();
    defer allocator.free(bytes);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = bytes });
}
