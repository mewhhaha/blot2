const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const ast = @import("ast.zig");

const Case = struct { source: []const u8, valid: bool, start: u32 = 0, end: u32 = 0 };
const cases = [_]Case{
    // record_type_upper
    .{ .source =
    \\type Box is data = #Box { Upper: U32 }
    \\entry const answer = 42
    \\
    , .valid = false, .start = 0, .end = 4 },
    // record_type_lower
    .{ .source =
    \\type Box is data = #Box { lower: U32 }
    \\entry const answer = 42
    \\
    , .valid = true },
    // record_type_shorthand_upper
    .{ .source =
    \\type Box { Upper } is data = #Box { Upper }
    \\entry const answer = 42
    \\
    , .valid = false, .start = 0, .end = 4 },
    // record_type_shorthand_lower
    .{ .source =
    \\type Box { lower } is data = #Box { lower }
    \\entry const answer = 42
    \\
    , .valid = true },
    // effect_operation_upper
    .{ .source =
    \\type Input is effect = { Ask: Unit -> U32 }
    \\entry const answer = 42
    \\
    , .valid = false, .start = 0, .end = 4 },
    // effect_operation_lower
    .{ .source =
    \\type Input is effect = { ask: Unit -> U32 }
    \\entry const answer = 42
    \\
    , .valid = true },
    // plain_record_upper
    .{ .source =
    \\entry const answer = ({ Upper: 42 }).Upper
    \\
    , .valid = false, .start = 0, .end = 5 },
    // plain_record_lower
    .{ .source =
    \\entry const answer = ({ lower: 42 }).lower
    \\
    , .valid = true },
    // named_record_upper
    .{ .source =
    \\type Box is data = #Box { lower: U32 }
    \\entry const answer = (#Box { Upper: 42 }).lower
    \\
    , .valid = false, .start = 39, .end = 44 },
    // named_record_lower
    .{ .source =
    \\type Box is data = #Box { lower: U32 }
    \\entry const answer = (#Box { lower: 42 }).lower
    \\
    , .valid = true },
    // record_pun_upper
    .{ .source =
    \\entry const Value = 42
    \\entry const answer = ({ Value }).Value
    \\
    , .valid = false, .start = 23, .end = 28 },
    // record_pun_lower
    .{ .source =
    \\const value = 42
    \\entry const answer = ({ value }).value
    \\
    , .valid = true },
    // data_name_lower
    .{ .source =
    \\type box is data = #Box U32
    \\entry const answer = 42
    \\
    , .valid = false, .start = 0, .end = 4 },
    // data_name_upper
    .{ .source =
    \\type Box is data = #Box U32
    \\entry const answer = 42
    \\
    , .valid = true },
    // legacy_data_name_lower
    .{ .source =
    \\data box = #Box U32
    \\entry const answer = 42
    \\
    , .valid = false, .start = 0, .end = 4 },
    // legacy_data_name_upper
    .{ .source =
    \\data Box = #Box U32
    \\entry const answer = 42
    \\
    , .valid = true },
    // effect_name_lower
    .{ .source =
    \\type input is effect = Unit -> U32
    \\entry const answer = 42
    \\
    , .valid = false, .start = 0, .end = 4 },
    // effect_name_upper
    .{ .source =
    \\type Input is effect = Unit -> U32
    \\entry const answer = 42
    \\
    , .valid = true },
    // data_name_qualified
    .{ .source =
    \\type ns.Box is data = #Box U32
    \\entry const answer = 42
    \\
    , .valid = false, .start = 0, .end = 4 },
    // constructor_decl_lower
    .{ .source =
    \\type Box is data = #box U32
    \\entry const answer = 42
    \\
    , .valid = false, .start = 0, .end = 4 },
    // constructor_decl_upper
    .{ .source =
    \\type Box is data = #Box U32
    \\entry const answer = 42
    \\
    , .valid = true },
    // constructor_decl_qualified
    .{ .source =
    \\type Box is data = #Ns.Box U32
    \\entry const answer = 42
    \\
    , .valid = false, .start = 0, .end = 4 },
    // constructor_pattern_lower
    .{ .source =
    \\type Box is data = #Box U32
    \\entry const answer = fn value => case value of
    \\  #box amount => amount
    \\
    , .valid = false, .start = 28, .end = 33 },
    // constructor_pattern_qualified_lower
    .{ .source =
    \\entry const answer = fn value => case value of
    \\  #ns.box amount => amount
    \\
    , .valid = false, .start = 0, .end = 5 },
    // constructor_pattern_upper
    .{ .source =
    \\type Box is data = #Box U32
    \\entry const answer = fn () => case #Box 42 of
    \\  #Box amount => amount
    \\
    , .valid = true },
    // qualified_selector_upper
    .{ .source =
    \\type Box is data = #Box U32
    \\const Box.Upper = fn box => case box of
    \\  #Box value => value
    \\entry const answer = (#Box 42).Upper
    \\
    , .valid = true },
    // bare_selector_upper
    .{ .source =
    \\type Box is data = #Box U32
    \\const Box.Upper = fn box => case box of
    \\  #Box value => value
    \\entry const answer = .Upper (#Box 42)
    \\
    , .valid = true },
    // qualified_global_upper
    .{ .source =
    \\const Namespace.Value = 42
    \\entry const answer = Namespace.Value
    \\
    , .valid = true },
    // global_upper
    .{ .source =
    \\entry const Answer = 42
    \\
    , .valid = true },
    // constraint_kind_upper
    .{ .source =
    \\entry const answer: U32 where { Type_rep U32 } = 42
    \\
    , .valid = false, .start = 0, .end = 5 },
    // constraint_kind_lower
    .{ .source =
    \\entry const answer: U32 where { type_rep U32 } = 42
    \\
    , .valid = true },
    // row_tail_upper
    .{ .source =
    \\const identity: a -> a ! {| E} = fn value => value
    \\entry const answer = identity 42
    \\
    , .valid = false, .start = 0, .end = 5 },
    // row_tail_lower
    .{ .source =
    \\const identity: a -> a ! {| e} = fn value => value
    \\entry const answer = identity 42
    \\
    , .valid = true },
    // effect_use_binder_upper
    .{ .source =
    \\effect tick: Unit -> U32
    \\entry const answer = fn () => do:
    \\  use Value <- tick ()
    \\  return 42
    \\
    , .valid = false, .start = 25, .end = 30 },
    // effect_use_binder_lower
    .{ .source =
    \\effect tick: Unit -> U32
    \\entry const answer = fn () => do (@effect.provider tick (fn () => 42)):
    \\  use value <- tick ()
    \\  return value
    \\
    , .valid = true },
    // effect_use_value_upper
    .{ .source =
    \\type Tick is effect = Unit -> U32
    \\entry const answer = fn () => do (@effect.provider Tick (fn () => 42)):
    \\  use Tick ()
    \\  return 42
    \\
    , .valid = true },
    // request_subject_upper
    .{ .source =
    \\entry const answer = fn () => do:
    \\  for request in @requests (@computation (fn () => 42)):
    \\    case Request of
    \\      complete value =>
    \\        return value
    \\
    , .valid = false, .start = 0, .end = 5 },
    // request_subject_qualified
    .{ .source =
    \\entry const answer = fn () => do:
    \\  for request in @requests (@computation (fn () => 42)):
    \\    case ns.request of
    \\      complete value =>
    \\        return value
    \\
    , .valid = false, .start = 0, .end = 5 },
    // request_subject_lower
    .{ .source =
    \\entry const answer = fn () => do:
    \\  for request in @requests (@computation (fn () => 42)):
    \\    case request of
    \\      complete value =>
    \\        return value
    \\
    , .valid = true },
    // rebind_root_upper
    .{ .source =
    \\entry const answer = fn () => do:
    \\  let value = 42
    \\  Value := 0
    \\  return value
    \\
    , .valid = false, .start = 0, .end = 5 },
    // rebind_root_lower
    .{ .source =
    \\entry const answer = fn () => do:
    \\  let value = 0
    \\  value := 42
    \\  return value
    \\
    , .valid = true },
    // update_field_upper
    .{ .source =
    \\entry const answer = fn value => do:
    \\  value.Upper := 42
    \\  return value
    \\
    , .valid = true },
    // modifier_upper
    .{ .source =
    \\Entry const answer = 42
    \\
    , .valid = false, .start = 0, .end = 5 },
    // modifier_lower
    .{ .source =
    \\entry const answer = 42
    \\
    , .valid = true },
    // effect_name_qualified_legal
    .{ .source =
    \\effect Namespace.Tick: Unit -> U32
    \\entry const answer = fn () => do (@effect.provider Namespace.Tick (fn () => 42)):
    \\  return Namespace.Tick ()
    \\
    , .valid = true },
    // request_record_payload
    .{ .source =
    \\effect read: { first: U32 } -> U32
    \\entry const answer = fn () => do:
    \\  for request in @requests (@computation (fn () => 42)):
    \\    case request of
    \\      effect read { first } =>
    \\        yield first
    \\      complete value =>
    \\        return value
    \\
    , .valid = false, .start = 35, .end = 40 },
    // request_grouped_record_payload
    .{ .source =
    \\type Read a is effect = ({ first: a } -> a)
    \\entry const answer = fn () => do:
    \\  for request in @requests (@computation (fn () => 42)):
    \\    case request of
    \\      effect (Read U32) { first } =>
    \\        yield first
    \\      complete value =>
    \\        return value
    \\
    , .valid = false, .start = 44, .end = 49 },
    // request_operation_selector
    .{ .source =
    \\entry const answer = fn () => do:
    \\  for request in @requests (@computation (fn () => 42)):
    \\    case request of
    \\      effect .operation () =>
    \\        yield 42
    \\      complete value =>
    \\        return value
    \\
    , .valid = false, .start = 0, .end = 5 },
    // standalone_record_pattern
    .{ .source =
    \\const extract = fn value => do:
    \\  let { first } = value
    \\  return first
    \\entry const answer = 42
    \\
    , .valid = false, .start = 0, .end = 5 },
    // constructor_record_pattern
    .{ .source =
    \\type Box is data = #Box { first: U32 }
    \\entry const answer = fn () => do:
    \\  let #Box { first } = #Box { first: 42 }
    \\  return first
    \\
    , .valid = true },
    // constructor_record_pattern_upper_field
    .{ .source =
    \\type Box is data = #Box { first: U32 }
    \\entry const answer = fn () => do:
    \\  let #Box { First } = #Box { first: 42 }
    \\  return 42
    \\
    , .valid = false, .start = 39, .end = 44 },
    // row_tail_builtin_u32
    .{ .source =
    \\const invoke = fn (callback: Unit -> U32 ! {| U32}) => callback ()
    \\
    , .valid = false, .start = 0, .end = 5 },
    // row_tail_named_type
    .{ .source =
    \\const invoke = fn (callback: Unit -> U32 ! {| Token}) => callback ()
    \\
    , .valid = false, .start = 0, .end = 5 },
    // row_tail_builtin_bool
    .{ .source =
    \\const invoke = fn (callback: Unit -> U32 ! {| Bool}) => callback ()
    \\
    , .valid = false, .start = 0, .end = 5 },
    // namespace_alias_upper
    .{ .source =
    \\import * as Library from "./library"
    \\entry const answer = Library.value
    \\
    , .valid = false, .start = 0, .end = 6 },
    // namespace_alias_lower
    .{ .source =
    \\import * as library from "./library"
    \\entry const answer = library.value
    \\
    , .valid = true },
    // named_alias_upper_legal
    .{ .source =
    \\import { value as Value } from "./library"
    \\entry const answer = Value
    \\
    , .valid = true },
    // named_alias_lower_legal
    .{ .source =
    \\import { value as selected } from "./library"
    \\entry const answer = selected
    \\
    , .valid = true },
    // named_constructor_upper_legal
    .{ .source =
    \\import { Box as Renamed } from "./library"
    \\entry const answer = fn () => case #Renamed 42 of
    \\  #Renamed value => value
    \\
    , .valid = true },
    // qualified_constructor_upper_legal
    .{ .source =
    \\import * as library from "./library"
    \\entry const answer = fn () => case #library.Box 42 of
    \\  #library.Box value => value
    \\
    , .valid = true },
};

fn identifierGrammar(allocator: std.mem.Allocator) !void {
    for (cases) |item| {
        var tokens = try lexer.lex(allocator, item.source);
        defer tokens.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, item.source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        if (item.valid) {
            try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        } else {
            try std.testing.expect(tree.diagnostics.items.len != 0);
            const diagnostic = tree.diagnostics.items[0];
            try std.testing.expectEqual(ast.Code.GPU_FRONTEND_SYNTAX_ERROR, diagnostic.code);
            try std.testing.expectEqual(item.start, diagnostic.start);
            try std.testing.expectEqual(item.end, diagnostic.end);
        }
    }
}

test "source name contexts enforce IDENT TYPE_IDENT and qualified constructor positions with frozen spans" {
    try identifierGrammar(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, identifierGrammar, .{});
}
