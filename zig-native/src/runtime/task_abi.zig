//! Exact compiler-generated task protocol. Hidden adapters own counted roots;
//! the host never decodes arbitrary source values or infers their ownership.
const w = @import("../backend/wasm.zig");
pub const Import = struct { name: []const u8, parameters: []const w.ValueType, result: w.ValueType };
pub const imports = [_]Import{
    .{ .name = "open", .parameters = &.{}, .result = .i32 },
    .{ .name = "close", .parameters = &.{.i32}, .result = .none },
    .{ .name = "spawn", .parameters = &.{ .i32, .i32, .i32 }, .result = .i32 },
    .{ .name = "join", .parameters = &.{ .i32, .i32 }, .result = .i32 },
    .{ .name = "cancel", .parameters = &.{.i32}, .result = .none },
    .{ .name = "poll", .parameters = &.{ .i32, .i32 }, .result = .i32 },
    .{ .name = "drop", .parameters = &.{ .i32, .i32 }, .result = .none },
    .{ .name = "drain", .parameters = &.{}, .result = .none },
    .{ .name = "checkpoint", .parameters = &.{}, .result = .none },
    .{ .name = "current", .parameters = &.{}, .result = .i32 },
    .{ .name = "resume", .parameters = &.{.i32}, .result = .none },
    .{ .name = "transfer", .parameters = &.{.i32}, .result = .none },
};
pub fn ensure(module: *w.Module) !void {
    inline for (imports) |item| _ = try module.importFunction("blot:task/1", item.name, item.parameters, item.result);
}
