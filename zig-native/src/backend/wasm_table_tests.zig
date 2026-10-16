const std = @import("std");
const wasm = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const optimized = @import("optimized_bodies.zig");

test "mutable function tables disable owned roots while checked machine sharing preserves them" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    _ = try module.ensureArena();
    for (0..2) |_| {
        const function = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
        try module.setParameterRoles(function, ir.packParameterRoles(&.{.scalar}));
        try module.emit(function, .{ .op = .local_get });
    }
    for (0..4) |scenario| {
        var capture: optimized.Capture = .{ .allocator = a };
        defer capture.deinit();
        var stats: optimized.Stats = .{};
        var options: wasm.AssemblyOptions = .{ .current = &capture, .stats = &stats };
        if (scenario == 1) options.export_function_table = true;
        if (scenario == 2) options.import_function_table = @intCast(module.functions.items.len);
        if (scenario == 3) options.share_machine_code = true;
        const bytes = try module.assembleWithOptions(options);
        defer a.free(bytes);
        try std.testing.expectEqual(scenario == 0 or scenario == 3, capture.roots);
        if (scenario == 3) try std.testing.expect(stats.shared != 0);
        if (scenario != 3) try std.testing.expectEqual(@as(usize, 0), stats.shared);
    }
}
