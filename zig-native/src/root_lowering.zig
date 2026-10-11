//! Function roots lower after typed publication and lifetime release. A single
//! result block makes explicit returns and branches to the function share one
//! epilogue. Root operations remain guarded until whole-module admission.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const w = @import("wasm.zig");
const A = std.mem.Allocator;

pub fn run(a: A, module: *const w.Module, source: *const ir.Function, framed: bool, entry: bool, start: bool) A.Error!?ir.Body {
    const arena = module.arena orelse return null;
    var changes = framed;
    for (source.instructions.items) |inst| if (inst.op == .call and inst.operand == arena.allocate_typed) {
        changes = true;
        break;
    };
    if (!changes) return null;
    var out: ir.Body = .{};
    errdefer out.deinit(a);
    try out.locals.appendSlice(a, source.locals.items);
    const result: u32 = @intCast(source.parameters.len + out.locals.items.len);
    const automatic = result + @intFromBool(source.result != .none);
    const array_parameter = entry and source.parameters.len != 0 and source.parameterRole(0) == .reference;
    if (framed and source.result != .none) try out.locals.append(a, source.result);
    if (entry) try out.locals.append(a, .i32);
    const publication: u32 = @intCast(source.parameters.len + out.locals.items.len);
    var global_stores = false;
    for (source.instructions.items) |inst| {
        if (inst.op == .global_set and module.globals.items[inst.operand].scalar.role() == .reference and inst.operand != arena.root_globals) global_stores = true;
    }
    if (global_stores) try out.locals.append(a, .i32);
    if (start) {
        try out.emit(a, .global_get, arena.root_enabled);
        try out.emit(a, .if_, 0);
        try out.emit(a, .i32_const, @intCast((module.globals.items.len + module.static_fields.items.len) * 4));
        try out.emit(a, .i32_const, std.math.maxInt(u32));
        try out.emit(a, .call, arena.root_allocate);
        try out.emit(a, .global_set, arena.root_globals);
        try out.emit(a, .end, 0);
    }
    if (framed) {
        try out.emit(a, .global_get, arena.root_enabled);
        try out.emit(a, .if_, 0);
        if (entry) {
            // Raw scalar callers retain their existing trap-recovery behavior.
            // ABI-aware callers enter externally and own exceptional cleanup.
            if (!array_parameter) {
                try out.emit(a, .global_get, arena.root_active);
                try out.emit(a, .i32_eqz, 0);
                try out.emit(a, .i32_eqz, 0);
                try out.emit(a, .global_get, arena.root_external);
                try out.emit(a, .i32_eqz, 0);
                try out.emit(a, .i32_and, 0);
                try out.emit(a, .global_get, arena.root_started);
                try out.emit(a, .i32_and, 0);
                try out.emit(a, .if_, 0);
                try out.emit(a, .i32_const, 1);
                try out.emit(a, .call, arena.root_leave);
                try out.emit(a, .end, 0);
            }
            try out.emit(a, .global_get, arena.root_active);
            try out.emit(a, .i32_eqz, 0);
            try out.emit(a, .if_, 0);
            try out.emit(a, .call, arena.root_enter);
            try out.emit(a, .i32_const, 0);
            try out.emit(a, .global_set, arena.root_external);
            try out.emit(a, .end, 0);
            try out.emit(a, .global_get, arena.root_external);
            try out.emit(a, .i32_eqz, 0);
            try out.emit(a, .local_set, automatic);
            try out.emit(a, .i32_const, 1);
            try out.emit(a, .global_set, arena.root_started);
        }
        try out.emit(a, .call, arena.root_open);
        try out.emit(a, .drop, 0);
        try out.emit(a, .end, 0);
        try out.emit(a, .block, if (source.result == .none) 0 else @backingInt(source.result));
    }
    var depth: u32 = 0;
    for (source.instructions.items) |instruction| {
        var inst = instruction;
        if (inst.op == .ownership) {
            const scope: ir.Ownership = @bitCast(inst.operand);
            if (scope.kind == .scope) {
                try out.emit(a, .global_get, arena.root_enabled);
                try out.emit(a, .if_, 0);
                switch (scope.chunk) {
                    0 => {
                        try out.emit(a, .call, arena.root_open);
                        try out.emit(a, .drop, 0);
                    },
                    1, 2 => {
                        if (scope.chunk == 2) try out.emit(a, .local_get, scope.roles) else try out.emit(a, .i32_const, 0);
                        try out.emit(a, .call, arena.root_close);
                    },
                    3 => {
                        try out.emit(a, .call, arena.root_reserve);
                        try out.emit(a, .local_set, scope.roles);
                    },
                    4 => {
                        try out.emit(a, .local_get, scope.roles & 8191);
                        try out.emit(a, .local_get, scope.roles >> 13);
                        try out.emit(a, .call, arena.root_store);
                    },
                    5 => {
                        try out.emit(a, .call, arena.root_reserve);
                        try out.emit(a, .local_get, scope.roles);
                        try out.emit(a, .call, arena.root_store);
                    },
                    else => unreachable,
                }
                try out.emit(a, .end, 0);
                continue;
            }
        }
        if (inst.op == .global_set and module.globals.items[inst.operand].scalar.role() == .reference and inst.operand != arena.root_globals) {
            try out.emit(a, .local_tee, publication);
            try out.emit(a, .global_get, arena.root_enabled);
            try out.emit(a, .if_, 0);
            try out.emit(a, .global_get, arena.root_globals);
            try out.emit(a, .global_get, arena.root_globals);
            try out.emit(a, .i32_const, inst.operand * 4);
            try out.emit(a, .i32_add, 0);
            try out.emit(a, .local_get, publication);
            try out.emit(a, .call, arena.store_word);
            try out.emit(a, .end, 0);
        }
        switch (inst.op) {
            .block, .loop, .if_ => depth += 1,
            .end => depth -= 1,
            .return_ => if (framed) {
                inst.op = .br;
                inst.operand = depth;
            },
            .call => if (inst.operand == arena.allocate_typed) {
                inst.operand = arena.root_allocate;
            },
            else => {},
        }
        try out.instructions.append(a, inst);
    }
    if (framed) {
        try out.emit(a, .end, 0);
        if (source.result != .none) try out.emit(a, .local_set, result);
        try out.emit(a, .global_get, arena.root_enabled);
        try out.emit(a, .if_, 0);
        if (source.result_role == .reference) try out.emit(a, .local_get, result) else try out.emit(a, .i32_const, 0);
        try out.emit(a, .call, arena.root_close);
        if (entry and !array_parameter and source.result_role != .reference) {
            try out.emit(a, .local_get, automatic);
            try out.emit(a, .if_, 0);
            try out.emit(a, .i32_const, 0);
            try out.emit(a, .call, arena.root_leave);
            try out.emit(a, .end, 0);
        }
        try out.emit(a, .end, 0);
        if (source.result != .none) try out.emit(a, .local_get, result);
    }
    return out;
}

fn ownership(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const source = try module.addTypedFunction(&.{}, .i32, .reference);
    try module.emitSlice(source, &.{
        .{ .op = .i32_const, .operand = 4 },               .{ .op = .i32_const },
        .{ .op = .call, .operand = arena.allocate_typed }, .{ .op = .return_ },
        .{ .op = .i32_const },
    });
    const before = try a.dupe(ir.Instruction, module.functions.items[source].instructions.items);
    defer a.free(before);
    var body = (try run(a, &module, &module.functions.items[source], true, false, false)).?;
    defer body.deinit(a);
    try std.testing.expectEqualSlices(ir.Instruction, before, module.functions.items[source].instructions.items);
    for (body.instructions.items) |inst| try std.testing.expect(inst.op != .return_);
    const result = try module.addTypedFunction(&.{}, .i32, .scalar);
    try module.emitSlice(result, &.{ .{ .op = .call, .operand = source }, .{ .op = .i32_load } });
    try module.exportFunction(result, "run", .unit, .u32);
    var capture: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
    defer capture.deinit();
    const bytes = try module.assembleWithOptions(.{ .tier = .development, .current = &capture });
    defer a.free(bytes);
    try std.testing.expect(capture.roots);
    const marker = (std.mem.findLast(u8, bytes, "blot:ownership") orelse return error.TestExpectedRootManifest) + "blot:ownership".len;
    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 0 }, bytes[marker..][0..3]);
    try std.testing.expect(std.mem.find(u8, bytes, "blot:ownership_enter") != null);
}
test "typed function root lowering owns early returns and preserves inputs through OOM" {
    try ownership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownership, .{});
}
