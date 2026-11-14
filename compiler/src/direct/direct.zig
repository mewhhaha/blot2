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
            return .{ .diagnostic = .{ .unit = failure.unit, .span = failure.span, .code = failure.code, .detail = failure.message }, .owned_message = failure.message };
        },
    };
    return .{ .bytes = bytes, .whole_module_only = true, .emitted_functions = g.module.functions.items.len };
}

fn build(g: *emit.Generator, entry: u32) emit.Error![]u8 {
    const m = g.types.module(entry) orelse return error.Unsupported;
    var entries: W.Bytes = .{};
    defer entries.deinit(g.allocator);
    var constants: W.Bytes = .{};
    defer constants.deinit(g.allocator);
    var inits: std.ArrayList(u32) = .empty;
    defer inits.deinit(g.allocator);
    var count: u32 = 0;
    // Host callback imports precede every defined function.
    for (m.bodies) |*body| {
        if (!body.exported) continue;
        const parameter = (try exportedParameter(g, m, body)) orelse continue;
        if (function.callbackAbi(g, parameter)) |kinds| _ = try function.hostImport(g, kinds);
    }
    for (m.bodies) |*body| {
        if (!body.exported) continue;
        if ((try exportedParameter(g, m, body)) == null) continue;
        try function.emitExport(g, m, body, &entries);
        count += 1;
    }
    for (m.bodies) |*body| {
        if (!body.exported or (try exportedParameter(g, m, body)) != null) continue;
        try inits.append(g.allocator, try function.emitConstantExport(g, m, body, &constants));
    }
    if (count == 0 and inits.items.len == 0) return g.fail(m, 0, "the entry module exports nothing", .{});
    try g.emitAll();
    if (inits.items.len != 0) g.module.start = try function.startFunction(g, m, inits.items);
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
    try abi.uleb(g.allocator, @intCast(inits.items.len));
    try abi.raw(g.allocator, constants.items());
    try g.module.custom("blot:abi", abi.items());
    return g.module.assemble(g.allocator);
}

/// The parameter type of an exported function, or of an exported constant
/// whose value is a function; null for an exported scalar constant.
fn exportedParameter(g: *emit.Generator, m: *const core.Module, body: *const core.Body) emit.Error!?@import("types.zig").Ty {
    var empty: @import("types.zig").Env = .empty;
    if (unhandledEffect(m, m.binding(body.binding).ty)) return g.failCode(m, body.root, .entry_type, "an exported function cannot leave source effects unhandled", .{});
    if (body.is_function) {
        const parameters = m.bodyParameters(body);
        if (parameters.len != 1) return g.fail(m, body.root, "entry functions take exactly one parameter", .{});
        return g.types.lower(m, parameters[0].ty, &empty) catch |err| switch (err) {
            error.Unsupported => return g.failCode(m, body.root, .entry_type, "an exported binding needs a concrete type", .{}),
            else => return err,
        };
    }
    const ty = g.types.lower(m, m.binding(body.binding).ty, &empty) catch |err| switch (err) {
        error.Unsupported => return g.failCode(m, body.root, .entry_type, "an exported binding needs a concrete type", .{}),
        else => return err,
    };
    const n = g.types.node(ty);
    return if (n.tag == .function) n.a else null;
}

/// Whether the outer arrow of `ty` has an effect other than Foreign.
fn unhandledEffect(m: *const core.Module, ty: @import("../check/types.zig").Id) bool {
    var arrow = ty;
    var n = m.types.node(arrow);
    while (n.tag == .forall or n.tag == .usage) {
        arrow = n.a;
        n = m.types.node(arrow);
    }
    if (n.tag != .function or n.c == 0) return false;
    for (m.types.rowLabels(n.c)) |label| {
        const operation = m.types.operation(label);
        const foreign = operation.identity.unit == 0 and operation.identity.decl == 1 and operation.instance.unit == 0 and operation.instance.decl == 0 and operation.arguments.len == 0;
        if (!foreign) return true;
    }
    return false;
}
