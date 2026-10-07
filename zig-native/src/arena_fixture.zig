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
    try lifetimeFixtures(&module);
    try controlLifetimeFixtures(&module);
    try graphLifetimeFixtures(&module);
    const bytes = try module.assemble();
    defer allocator.free(bytes);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = bytes });
}

fn lifetimeFixtures(module: *wasm.Module) !void {
    const arena = module.arena.?;
    // A larger-than-SROA temporary is borrowed through an interior address.
    // This loop contains no collection calls: bounded memory comes from the
    // ownership pass, including both normal and early-return paths.
    for (0..2) |early| {
        const f = try module.addFunction(&.{.i32}, .i32);
        const index = try module.addLocal(f, .i32);
        const total = try module.addLocal(f, .i32);
        const object = try module.addLocal(f, .i32);
        const alias = try module.addLocal(f, .i32);
        try module.emitSlice(f, &.{
            .{ .op = .block },                        .{ .op = .loop },
            .{ .op = .local_get, .operand = index },  .{ .op = .local_get, .operand = 0 },
            .{ .op = .i32_ge_u },                     .{ .op = .br_if, .operand = 1 },
            .{ .op = .i32_const, .operand = 128 },    .{ .op = .call, .operand = arena.allocate },
            .{ .op = .local_set, .operand = object }, .{ .op = .local_get, .operand = object },
            .{ .op = .local_get, .operand = index },  .{ .op = .i32_store, .operand = 124 },
            .{ .op = .local_get, .operand = object }, .{ .op = .i32_const, .operand = 120 },
            .{ .op = .i32_add },                      .{ .op = .local_set, .operand = alias },
            .{ .op = .local_get, .operand = total },  .{ .op = .local_get, .operand = alias },
            .{ .op = .i32_load, .operand = 4 },       .{ .op = .i32_add },
            .{ .op = .local_set, .operand = total },
        });
        if (early != 0) try module.emitSlice(f, &.{
            .{ .op = .local_get, .operand = index }, .{ .op = .i32_const, .operand = 49 }, .{ .op = .i32_eq }, .{ .op = .if_ },
            .{ .op = .local_get, .operand = total }, .{ .op = .return_ },                  .{ .op = .end },
        });
        try module.emitSlice(f, &.{
            .{ .op = .local_get, .operand = index }, .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add }, .{ .op = .local_set, .operand = index },
            .{ .op = .br },                          .{ .op = .end },                     .{ .op = .end },     .{ .op = .local_get, .operand = total },
        });
        try module.exportFunction(f, if (early == 0) "temporary_fold" else "temporary_early", .u32, .u32);
    }
    const escape = try module.addFunction(&.{.i32}, .i32);
    const object = try module.addLocal(escape, .i32);
    try module.emitSlice(escape, &.{
        .{ .op = .i32_const, .operand = 128 },    .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object },
        .{ .op = .local_get, .operand = object }, .{ .op = .i32_const },                       .{ .op = .i32_const, .operand = 128 },
        .{ .op = .memory_fill },                  .{ .op = .local_get, .operand = object },    .{ .op = .i32_const, .operand = 31 },
        .{ .op = .i32_store },                    .{ .op = .local_get, .operand = object },    .{ .op = .local_get, .operand = 0 },
        .{ .op = .i32_store, .operand = 124 },    .{ .op = .local_get, .operand = object },
    });
    try module.exportFunction(escape, "temporary_escape", .u32, .array_u32);
    const heap = try module.addFunction(&.{.i32}, .i32);
    try module.emit(heap, .{ .op = .global_get, .operand = arena.heap });
    try module.exportFunction(heap, "temporary_heap", .unit, .u32);
    const collect = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(collect, &.{ .{ .op = .i32_const }, .{ .op = .global_get, .operand = arena.base }, .{ .op = .i32_const }, .{ .op = .call, .operand = arena.collect } });
    try module.exportFunction(collect, "temporary_collect", .unit, .unit);
}

fn controlLifetimeFixtures(module: *wasm.Module) !void {
    const arena = module.arena.?;
    const read = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(read, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_load, .operand = 4 } });
    const forward = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(forward, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .call, .operand = read } });
    const make = try module.addFunction(&.{.i32}, .i32);
    const made = try module.addLocal(make, .i32);
    try module.emitSlice(make, &.{
        .{ .op = .i32_const, .operand = 128 },  .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = made },
        .{ .op = .local_get, .operand = made }, .{ .op = .local_get, .operand = 0 },         .{ .op = .i32_store, .operand = 124 },
        .{ .op = .local_get, .operand = made },
    });
    const make_forward = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(make_forward, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .call, .operand = make } });
    // The same owner is used repeatedly across a loop, then dies on br_if's
    // taken edge. There are deliberately no collector calls in these fixtures.
    const loop = try module.addFunction(&.{.i32}, .i32);
    const object = try module.addLocal(loop, .i32);
    const index = try module.addLocal(loop, .i32);
    const total = try module.addLocal(loop, .i32);
    try module.emitSlice(loop, &.{
        .{ .op = .i32_const, .operand = 7 },     .{ .op = .call, .operand = make_forward }, .{ .op = .local_set, .operand = object },
        .{ .op = .block },                       .{ .op = .loop },                          .{ .op = .local_get, .operand = index },
        .{ .op = .local_get, .operand = 0 },     .{ .op = .i32_ge_u },                      .{ .op = .br_if, .operand = 1 },
        .{ .op = .local_get, .operand = total }, .{ .op = .local_get, .operand = object },  .{ .op = .i32_const, .operand = 120 },
        .{ .op = .i32_add },                     .{ .op = .call, .operand = forward },      .{ .op = .i32_add },
        .{ .op = .local_set, .operand = total }, .{ .op = .local_get, .operand = index },   .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_add },                     .{ .op = .local_set, .operand = index },   .{ .op = .br },
        .{ .op = .end },                         .{ .op = .end },                           .{ .op = .local_get, .operand = total },
    });
    try module.exportFunction(loop, "borrowed_loop", .u32, .u32);

    for (0..3) |kind| {
        const f = try module.addFunction(&.{.i32}, .i32);
        const pointer = try module.addLocal(f, .i32);
        try module.emitSlice(f, &.{
            .{ .op = .i32_const, .operand = 128 },     .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = pointer },
            .{ .op = .local_get, .operand = pointer }, .{ .op = .i32_const, .operand = 55 },        .{ .op = .i32_store, .operand = 124 },
        });
        if (kind == 0) {
            // One arm returns without reading; the other borrows through two calls.
            try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .if_ }, .{ .op = .i32_const, .operand = 77 }, .{ .op = .return_ }, .{ .op = .end } });
        } else if (kind == 1) {
            // A branch-result value lives below the condition. Cleanup must not
            // change the original br_if depth or consume that result operand.
            try module.emitSlice(f, &.{ .{ .op = .block, .operand = 0x7f }, .{ .op = .i32_const, .operand = 77 }, .{ .op = .local_get, .operand = 0 }, .{ .op = .br_if }, .{ .op = .drop } });
        } else {
            try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .if_, .operand = 0x7f }, .{ .op = .local_get, .operand = pointer }, .{ .op = .i32_const, .operand = 120 }, .{ .op = .i32_add }, .{ .op = .call, .operand = forward }, .{ .op = .else_ } });
        }
        try module.emitSlice(f, &.{ .{ .op = .local_get, .operand = pointer }, .{ .op = .i32_const, .operand = 120 }, .{ .op = .i32_add }, .{ .op = .call, .operand = forward } });
        if (kind != 0) try module.emit(f, .{ .op = .end });
        try module.exportFunction(f, switch (kind) {
            0 => "borrowed_early",
            1 => "borrowed_branch_value",
            else => "borrowed_arms",
        }, .u32, .u32);
    }
}

fn graphLifetimeFixtures(module: *wasm.Module) !void {
    const arena = module.arena.?;
    for (0..2) |escaping| {
        const f = try module.addFunction(&.{.i32}, .i32);
        const index = try module.addLocal(f, .i32);
        const sum = try module.addLocal(f, .i32);
        const left = try module.addLocal(f, .i32);
        const right = try module.addLocal(f, .i32);
        const child = try module.addLocal(f, .i32);
        const pressure = try module.addLocal(f, .i32);
        if (escaping == 0) try module.emitSlice(f, &.{
            .{ .op = .block },    .{ .op = .loop },                .{ .op = .local_get, .operand = index }, .{ .op = .local_get, .operand = 0 },
            .{ .op = .i32_ge_u }, .{ .op = .br_if, .operand = 1 },
        });
        for ([_]u32{ left, right, child }) |local| try module.emitSlice(f, &.{
            .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = local },
        });
        // Two parents share child; child's backedge closes a real heap cycle.
        for ([_][2]u32{ .{ left, child }, .{ right, child }, .{ child, left } }) |edge| try module.emitSlice(f, &.{
            .{ .op = .local_get, .operand = edge[0] }, .{ .op = .local_get, .operand = edge[1] }, .{ .op = .i32_store },
        });
        try module.emitSlice(f, &.{
            .{ .op = .local_get, .operand = left },  .{ .op = .local_get, .operand = if (escaping == 0) index else 0 }, .{ .op = .i32_store, .operand = 124 },
            .{ .op = .local_get, .operand = child }, .{ .op = .local_get, .operand = if (escaping == 0) index else 0 }, .{ .op = .i32_const, .operand = 2 },
            .{ .op = .i32_add },                     .{ .op = .i32_store, .operand = 124 },
        });
        if (escaping != 0) {
            try module.emit(f, .{ .op = .local_get, .operand = right });
            try module.exportFunction(f, "graph_escape", .u32, .u32);
            continue;
        }
        try module.emitSlice(f, &.{
            .{ .op = .local_get, .operand = sum },       .{ .op = .local_get, .operand = left },     .{ .op = .i32_load },                       .{ .op = .i32_load },
            .{ .op = .i32_load, .operand = 124 },        .{ .op = .i32_add },                        .{ .op = .local_set, .operand = sum },
            // Force reuse between reads through the two parents: freeing the
            // common child at its first borrowed read corrupts this result.
                 .{ .op = .i32_const, .operand = 128 },
            .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = pressure }, .{ .op = .local_get, .operand = pressure }, .{ .op = .i32_const, .operand = 1000 },
            .{ .op = .i32_store, .operand = 124 },       .{ .op = .local_get, .operand = sum },      .{ .op = .local_get, .operand = right },    .{ .op = .i32_load },
            .{ .op = .i32_load, .operand = 124 },        .{ .op = .i32_add },                        .{ .op = .local_set, .operand = sum },      .{ .op = .local_get, .operand = index },
            .{ .op = .i32_const, .operand = 1 },         .{ .op = .i32_add },                        .{ .op = .local_set, .operand = index },    .{ .op = .br },
            .{ .op = .end },                             .{ .op = .end },                            .{ .op = .local_get, .operand = sum },
        });
        try module.exportFunction(f, "graph_fold", .u32, .u32);
    }
}
