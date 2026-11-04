//! Visible unit-level producer contracts. Source-facing tests use the real
//! separate std/prelude module; these fragments model its primitive catalog.
const std = @import("std");
pub const Operation = enum { add, sub, mul, div, rem, eq, ne, lt, le, gt, ge };
pub fn withMethods(allocator: std.mem.Allocator, input: []const u8, operations: []const Operation) ![]u8 {
    var source: std.ArrayList(u8) = .empty;
    errdefer source.deinit(allocator);
    try source.appendSlice(allocator, input);
    try source.appendSlice(allocator, "\n");
    var needs_not = false;
    for (operations) |operation| if (operation == .ne or operation == .le or operation == .ge) {
        needs_not = true;
    };
    var needs_lt = false;
    var needs_eq = false;
    var has_lt = false;
    var has_eq = false;
    for (operations) |operation| {
        needs_lt = needs_lt or operation == .le or operation == .ge or operation == .gt;
        needs_eq = needs_eq or operation == .ne;
        has_lt = has_lt or operation == .lt;
        has_eq = has_eq or operation == .eq;
    }
    if (needs_lt and !has_lt) try source.appendSlice(allocator, "const U32.lt = func left => return func right => return @u32.lt left right\n");
    if (needs_eq and !has_eq) try source.appendSlice(allocator, "const U32.eq = func left => return func right => return @u32.eq left right\n");
    if (needs_not) try source.appendSlice(allocator, "const Bool.not = func value => return case value of\n  true => false\n  false => true\n");
    for (operations) |operation| {
        const declarations = switch (operation) {
            .add => "const U32.add = func left => return func right => return @u32.add left right\n" ++ "const F32.add = func left => return func right => return @f32.add left right\n",
            .sub => "const U32.sub = func left => return func right => return @u32.sub left right\n" ++ "const F32.sub = func left => return func right => return @f32.sub left right\n",
            .mul => "const U32.mul = func left => return func right => return @u32.mul left right\n" ++ "const F32.mul = func left => return func right => return @f32.mul left right\n",
            .div => "const U32.div = func left => return func right => return @u32.div left right\n" ++ "const F32.div = func left => return func right => return @f32.div left right\n",
            .rem => "const U32.rem = func left => return func right => return @u32.rem left right\n",
            .eq => "const U32.eq = func left => return func right => return @u32.eq left right\n" ++ "const F32.eq = func left => return func right => return @f32.eq left right\n",
            .ne => "const U32.ne = func left => return func right => return Bool.not (U32.eq left right)\n" ++ "const F32.ne = func left => return func right => return @f32.ne left right\n",
            .lt => "const U32.lt = func left => return func right => return @u32.lt left right\n" ++ "const F32.lt = func left => return func right => return @f32.lt left right\n",
            .le => "const U32.le = func left => return func right => return Bool.not (U32.lt right left)\n" ++ "const F32.le = func left => return func right => return @f32.le left right\n",
            .gt => "const U32.gt = func left => return func right => return U32.lt right left\n" ++ "const F32.gt = func left => return func right => return @f32.gt left right\n",
            .ge => "const U32.ge = func left => return func right => return Bool.not (U32.lt left right)\n" ++ "const F32.ge = func left => return func right => return @f32.ge left right\n",
        };
        try source.appendSlice(allocator, declarations);
    }
    return source.toOwnedSlice(allocator);
}
