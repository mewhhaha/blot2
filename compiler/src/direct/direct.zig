//! Direct backend entry: one Wasm function per `(binding, concrete type)`
//! instance reached from the entry module's exports, with fixed layouts and
//! no cross-call analysis. See tasks/FAST_COMPILE.md.
const std = @import("std");
const core = @import("../check/core.zig");
const backend = @import("../backend/core_backend.zig");
const emit = @import("emit.zig");
const function = @import("function.zig");
const W = @import("writer.zig");
const A = std.mem.Allocator;

pub fn compile(allocator: A, units: []const core.Module, entry: u32) A.Error!backend.Result {
    var g = try emit.Generator.init(allocator, units);
    defer g.deinit();
    const bytes = build(&g, entry) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported, error.Diverged => {
            const failure = g.failure orelse emit.Failure{ .unit = entry, .span = .{ .start = 0, .end = 0 }, .message = try allocator.dupe(u8, "Direct backend: unsupported program") };
            g.failure = null;
            return .{ .diagnostic = .{ .unit = failure.unit, .span = failure.span, .code = .storage_unsupported, .detail = failure.message }, .owned_message = failure.message };
        },
    };
    return .{ .bytes = bytes, .whole_module_only = true, .emitted_functions = g.module.functions.items.len };
}

fn build(g: *emit.Generator, entry: u32) emit.Error![]u8 {
    const m = g.types.module(entry) orelse return error.Unsupported;
    var entries: W.Bytes = .{};
    defer entries.deinit(g.allocator);
    var count: u32 = 0;
    // Host callback imports precede every defined function.
    for (m.bodies) |*body| {
        if (!body.exported or !body.is_function) continue;
        const parameters = m.bodyParameters(body);
        if (parameters.len != 1) return g.fail(m, body.root, "entry functions take exactly one parameter", .{});
        var empty: @import("types.zig").Env = .empty;
        const ty = g.types.lower(m, parameters[0].ty, &empty) catch |err| switch (err) {
            error.Unsupported => return g.typeFailure(m, body.root),
            else => return err,
        };
        if (function.callbackAbi(g, ty)) |kinds| _ = try function.hostImport(g, kinds);
    }
    for (m.bodies) |*body| {
        if (!body.exported or !body.is_function) continue;
        try function.emitExport(g, m, body, &entries);
        count += 1;
    }
    if (count == 0) return g.fail(m, 0, "the entry module exports no functions", .{});
    try g.emitAll();
    if (try g.summary()) |failure| {
        if (g.failure) |previous| g.allocator.free(previous.message);
        g.failure = failure;
        return error.Unsupported;
    }
    var abi: W.Bytes = .{};
    defer abi.deinit(g.allocator);
    try abi.byte(g.allocator, 8);
    try abi.uleb(g.allocator, count);
    try abi.raw(g.allocator, entries.items());
    try abi.uleb(g.allocator, 0);
    try g.module.custom("blot:abi", abi.items());
    return g.module.assemble(g.allocator);
}
