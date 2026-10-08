//! Standalone executed-Wasm fixture; no production patch policy is enabled.
const std = @import("std");
const patches = @import("scalar_live_patch.zig");
const fixture = @import("scalar_live_patch_tests.zig").fixture;
fn image(a: std.mem.Allocator, value: u32) !patches.Image {
    var module = try fixture(a, value);
    defer module.deinit();
    return (try patches.Image.capture(a, &module)).?;
}
fn encoded(a: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    const buffer = try a.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
    return std.base64.standard.Encoder.encode(buffer, bytes);
}
pub fn main(init: std.process.Init) !void {
    const a = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var original = try image(a, 1);
    defer original.deinit();
    var changed = try image(a, 7);
    defer changed.deinit();
    var last = try image(a, 3);
    defer last.deinit();
    const initial = try original.initial();
    defer a.free(initial);
    var first = (try changed.delta(&original)).?;
    defer first.deinit();
    var second = (try last.delta(&changed)).?;
    defer second.deinit();
    var revert = (try original.delta(&last)).?;
    defer revert.deinit();
    const initial64 = try encoded(a, initial);
    defer a.free(initial64);
    const first64 = try encoded(a, first.bytes);
    defer a.free(first64);
    const second64 = try encoded(a, second.bytes);
    defer a.free(second64);
    const revert64 = try encoded(a, revert.bytes);
    defer a.free(revert64);
    const output = try std.json.Stringify.valueAlloc(a, .{ .initial = initial64, .first = first64, .second = second64, .revert = revert64 }, .{});
    defer a.free(output);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = output });
}
