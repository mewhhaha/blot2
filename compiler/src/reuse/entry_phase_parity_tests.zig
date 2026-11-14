const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const a = std.testing.allocator;

const declarations =
    \\type Box is data = $Box U32
    \\type Tick is effect = Unit -> Unit
    \\const Box.read: Box -> U32 ! {Tick} where {} = func (value: Box) => return value.read
    \\
;
const missing_entry = declarations ++ "entry const selected: Box -> U32 = func value => return value.read\nentry const answer = 42\n";
const pure_entry = "type Box is data = $Box U32\nconst Box.read: Box -> U32 where {} = func (value: Box) => return value.read\nentry const selected: Box -> U32 = func value => return value.read\nentry const answer = 42\n";
const literal_entry = declarations ++ "entry const selected: Box -> U32 = func value => return 42\nentry const answer = 42\n";
const abi_caller = declarations ++ "entry const selected: Unit -> U32 = func () => return ($Box 1).read\nentry const answer = 42\n";
const called_entry = declarations ++ "entry const selected: Box -> U32 = func value => return value.read\nentry const answer: Unit -> U32 = func () => return selected ($Box 1)\n";
const generic_message = "entry `selected` has a generic type, so it cannot be a Wasm export: entry functions take or return Unit, U32, F32, Bool, Array U32, Array F32, or unique/shared owners of closed data; one exact Foreign scalar/numeric-array callback or synchronous cleanup descriptor is also accepted as input; every other effect must be handled; entry values are Unit, U32, F32 or Bool";

fn lower(source: []const u8) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(a, &tree, &names, &checked);
    errdefer result.deinit(a);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}
fn target(module: *const core.Module, name: []const u8) !core.BindingRef {
    for (module.bodies[1..]) |body| if (std.mem.eql(u8, module.name(body.export_name), name)) return .{ .unit = 1, .binding = body.binding };
    return error.TestUnexpectedResult;
}
test "entry phase ordinary initial type failures survive unsupported nominal entry shape" {
    const source = "type Box is data = $Box U32\nentry const selected: Box -> U32 = func value => return @u32.add 1 1.0\nentry const answer = 42\n";
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &names);
    defer tree.deinit(a);
    var checked = try checker.checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
    try std.testing.expectEqual(checker.Code.type_mismatch, checked.diagnostics[0].code);
}
