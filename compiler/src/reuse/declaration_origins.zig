//! Correspondence for named top-level declarations in an already paired unit.
//! Names identify only a declaration, never its body, type, or observations.
//! Ambiguous names and moved binding ordinals conservatively decline.
const std = @import("std");
const core = @import("../check/core.zig");
const Pair = struct { before: u32 = 0, after: u32 = 0, ambiguous: bool = false };
pub fn name(module: *const core.Module, body: core.Body) ?[]const u8 {
    const span = body.declaration_name;
    if (span.len == 0 or span.start > module.names.len or span.len > module.names.len - span.start) return null;
    return module.names[span.start..][0..span.len];
}
fn collect(a: std.mem.Allocator, entries: *std.StringHashMapUnmanaged(Pair), module: *const core.Module, comptime before: bool) std.mem.Allocator.Error!void {
    for (module.bodies) |body| {
        if (body.binding == 0) continue;
        const spelling = name(module, body) orelse continue;
        const entry = try entries.getOrPut(a, spelling);
        if (!entry.found_existing) entry.value_ptr.* = .{};
        const slot = if (before) &entry.value_ptr.before else &entry.value_ptr.after;
        if (slot.* != 0) entry.value_ptr.ambiguous = true;
        slot.* = body.binding;
    }
}
pub fn mark(a: std.mem.Allocator, old: *const core.Module, current: *const core.Module, admitted: []bool) std.mem.Allocator.Error!void {
    std.debug.assert(admitted.len == current.bindings.len);
    @memset(admitted, false);
    var entries: std.StringHashMapUnmanaged(Pair) = .empty;
    defer entries.deinit(a);
    try collect(a, &entries, old, true);
    try collect(a, &entries, current, false);
    var values = entries.valueIterator();
    while (values.next()) |pair| {
        if (!pair.ambiguous and pair.before != 0 and pair.before == pair.after and pair.after < admitted.len) admitted[pair.after] = true;
    }
}
