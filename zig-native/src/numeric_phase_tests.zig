const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const syntax = @import("syntax_diagnostics.zig");
const a = std.testing.allocator;
const Case = struct { source: []const u8, code: check.Code, point: u32 };
// Numeric precedence is preserved when the surrounding syntax stays valid.
// Structural records now admit their child expressions instead of rejecting
// the brace syntax before inspecting numeric/name failures.
const cases = [_]Case{
    .{ .source = "const answer=4294967296\n", .code = .integer_range, .point = 13 }, // overflow-decimal
    .{ .source = "const answer=0x1_0000_0000\n", .code = .integer_range, .point = 13 }, // overflow-hex
    .{ .source = "const answer=99999999999999999999999999999999999999\n", .code = .integer_range, .point = 13 }, // overflow-long
    .{ .source = "// 雪🙂\nconst answer=4294967296\n", .code = .integer_range, .point = 24 }, // overflow-unicode
    .{ .source = "const earlier=42\r\nconst answer=4294967296\r\n", .code = .integer_range, .point = 31 }, // overflow-CRLF
    .{ .source = "const first=4294967296\nconst later=missing\n", .code = .unknown_value, .point = 35 }, // overflow-before-name
    .{ .source = "const first=missing\nconst later=4294967296\n", .code = .integer_range, .point = 32 }, // name-before-overflow
    .{ .source = "const first=4294967296\nconst later=0x1_0000_0000\n", .code = .integer_range, .point = 35 }, // two-overflows
    .{ .source = "const answer:Missing=4294967296\n", .code = .unsupported_type, .point = 13 }, // unknown-annotation-overflow
    .{ .source = "const first=4294967296\nconst later:Missing=42\n", .code = .unsupported_type, .point = 35 }, // overflow-before-later-annotation
    .{ .source = "const first:Missing=42\nconst later=4294967296\n", .code = .integer_range, .point = 35 }, // annotation-before-later-overflow
    .{ .source = "const answer=fn(value:Missing)=>4294967296\n", .code = .unsupported_type, .point = 22 }, // lambda-annotation-overflow
    .{ .source = "const answer=@u32.add 4294967296\n", .code = .call_arity, .point = 13 }, // primitive-arity-overflow
    .{ .source = "const answer=@u32.add missing 4294967296\n", .code = .unknown_value, .point = 22 }, // primitive-first-name-overflow
    .{ .source = "const answer=@u32.add 4294967296 missing\n", .code = .integer_range, .point = 22 }, // primitive-first-overflow-name
    .{ .source = "const answer=do:\n  return 42\n  4294967296\n", .code = .unreachable_statement, .point = 31 }, // unreachable-overflow
    .{ .source = "const answer=do:\n  return missing\n  4294967296\n", .code = .unreachable_statement, .point = 36 }, // unreachable-name-overflow
    .{ .source = "const answer=do:\n  return 4294967296\n  42\n", .code = .unreachable_statement, .point = 39 }, // return-overflow-unreachable
    .{ .source = "const answer=do:\n  saved:=4294967296\n  return 42\n", .code = .unknown_rebinding, .point = 19 }, // rebind-overflow
    .{ .source = "const answer=fn value=>case value of\n  4294967296=>42\n  _=>0\n", .code = .integer_range, .point = 39 }, // case-pattern-overflow
    .{ .source = "const answer=fn value=>case value of\n  0=>missing\n  4294967296=>42\n  _=>0\n", .code = .unknown_value, .point = 42 }, // case-first-body-name-later-pattern
    .{ .source = "const answer=case missing of\n  4294967296=>42\n  _=>0\n", .code = .unknown_value, .point = 18 }, // case-subject-name-overflow
    .{ .source = "const answer=@product.get (42,43) 4294967296\n", .code = .integer_range, .point = 34 }, // product-selector-overflow
    .{ .source = "const answer=@array.get #[42] 4294967296\n", .code = .integer_range, .point = 30 }, // array-index-overflow
    .{ .source = "@[4294967296]\nconst answer=42\n", .code = .integer_range, .point = 0 }, // attribute-overflow
    .{ .source = "infixl 4294967296 (+)=add\nconst add=fn left=>fn right=>@u32.add left right\n", .code = .integer_range, .point = 7 }, // fixity-overflow
    .{ .source = "infixl 4294967296 (+)=missing\n", .code = .integer_range, .point = 7 }, // fixity-overflow-missing-target
    .{ .source = "infixl 256 (+)=add\nconst add=fn left=>fn right=>@u32.add left right\n", .code = .operator_precedence, .point = 0 }, // fixity-oversized-operator-precedence
    .{ .source = "const answer=42\ninfixl 4294967296 (+)=add\nconst add=fn left=>fn right=>@u32.add left right\n", .code = .operator_header_order, .point = 16 }, // fixity-after-value-overflow
    .{ .source = "import * as dependency from \"./missing\"\nconst answer=4294967296\n", .code = .module_loader_required, .point = 0 }, // import-before-overflow
    .{ .source = "import * as dependency from \"./missing\"\nconst answer=fn value=>case value of\n  4294967296=>42\n  _=>0\n", .code = .module_loader_required, .point = 0 }, // import-before-pattern-overflow
    .{ .source = "import * as dependency from \"./missing\"\ninfixl 4294967296 (+)=add\nconst add=fn left=>fn right=>@u32.add left right\n", .code = .module_loader_required, .point = 0 }, // import-before-fixity-overflow
    .{ .source = "const answer=1e999\n", .code = .float_range, .point = 13 }, // float-overflow
    .{ .source = "import * as dependency from \"./missing\"\nconst answer=1e999\n", .code = .module_loader_required, .point = 0 }, // float-overflow-import
    .{ .source = "const answer = -4294967296\n", .code = .integer_range, .point = 16 }, // negative-spaced-overflow
    .{ .source = "const answer = -1e999\n", .code = .float_range, .point = 16 }, // negative-spaced-float-overflow
    .{ .source = "const answer = :4294967296\n", .code = .integer_range, .point = 16 }, // overflow-type-witness
    .{ .source = "infixl 4294967296 (+)=add\ninfixl 60 (+)=add\nconst add=fn left=>fn right=>@u32.add left right\n", .code = .integer_range, .point = 7 }, // duplicate-fixity-overflow-first
    .{ .source = "infixl 60 (+)=add\ninfixl 4294967296 (+)=add\nconst add=fn left=>fn right=>@u32.add left right\n", .code = .integer_range, .point = 25 }, // duplicate-fixity-overflow-later
    .{ .source = "@[4294967296]\nconst answer=missing\n", .code = .unknown_value, .point = 27 }, // tag-name-before-overflow
    .{ .source = "@[missing]\nconst answer=4294967296\n", .code = .integer_range, .point = 24 }, // tag-overflow-before-name
    .{ .source = "const answer=fn value=>case value of\n  (4294967296,_)=>42\n  _=>0\n", .code = .integer_range, .point = 40 }, // grouped-pattern-overflow
    .{ .source = "type Wrapped is data=#Wrapped {value:U32}\nconst answer=fn value=>case value of\n  #Wrapped {value:4294967296}=>42\n", .code = .integer_range, .point = 97 }, // record-pattern-overflow
    .{ .source = "const answer:Missing=1e999\n", .code = .unsupported_type, .point = 13 }, // float-unknown-annotation
    .{ .source = "const first=1e999\nconst later=missing\n", .code = .unknown_value, .point = 30 }, // float-before-name
    .{ .source = "const answer=@f32.add 1e999\n", .code = .call_arity, .point = 13 }, // float-primitive-arity
    .{ .source = "type Box a is data=#Box a\nconst answer=Box 4294967296\n", .code = .integer_range, .point = 43 }, // nominal-type-argument-overflow
    .{ .source = "type Box a is data=#Box a\nconst answer=Box {value:4294967296}\n", .code = .constructor_marker, .point = 39 }, // nominal-record-type-argument-overflow
    .{ .source = "type Box a is data=#Box a\nconst answer=Box (missing,4294967296)\n", .code = .unknown_value, .point = 44 }, // nominal-type-argument-name-before-overflow
    .{ .source = "type Box a is data=#Box a\nconst answer=Box (4294967296,missing)\n", .code = .integer_range, .point = 44 }, // nominal-type-argument-overflow-before-name
    .{ .source = "type Box a is data=#Box a\nconst answer=#Box 4294967296\n", .code = .integer_range, .point = 44 }, // nominal-constructor-overflow
    .{ .source = "type Tick a is effect={read:Unit->a}\nconst answer=Tick 4294967296\n", .code = .effect_member, .point = 50 }, // effect-family-argument-overflow
    .{ .source = "type Tick a is effect={read:Unit->a}\nconst answer=Tick 1e999\n", .code = .effect_member, .point = 50 }, // effect-family-argument-float-overflow
    .{ .source = "type Tick a is effect={read:Unit->a}\nconst answer=Tick.read 4294967296 ()\n", .code = .integer_range, .point = 60 }, // effect-operation-argument-overflow
    .{ .source = "const answer=@do.pure 4294967296\n", .code = .unknown_intrinsic, .point = 13 }, // unknown-intrinsic-overflow
    .{ .source = "const answer=@product.get (42,43) 1e999\n", .code = .product_index_literal, .point = 34 }, // product-selector-float-overflow
    .{ .source = "@[42]\ninfixl 4294967296 (+)=add\nconst add=fn left=>fn right=>@u32.add left right\n", .code = .integer_range, .point = 13 }, // fixity-attribute-overflow
    .{ .source = "@[4294967296]\ninfixl 60 (+)=add\nconst add=fn left=>fn right=>@u32.add left right\n", .code = .unsupported_attribute, .point = 0 }, // fixity-attribute-literal-overflow
    .{ .source = "import * as dependency from \"./missing\"\nconst answer:Missing=4294967296\n", .code = .module_loader_required, .point = 0 }, // explicit-type-import-overflow
    .{ .source = "const answer=do:\n  let 4294967296=42 else:\n    return 0\n  return 42\n", .code = .integer_range, .point = 23 }, // local-pattern-overflow
    .{ .source = "type Box a is data=#Box a\nconst first=4294967296\nconst later=Box {value:U32}\n", .code = .constructor_marker, .point = 61 }, // nominal-record-known-types
    .{ .source = "type Box {value:a} is data=#Box a\nconst first=4294967296\nconst later=Box {value:U32}\n", .code = .constructor_marker, .point = 69 }, // nominal-record-structured-pattern
    .{ .source = "type Box a is data=#Box a\nconst first=4294967296\nconst later=Box Missing\n", .code = .unknown_value, .point = 65 }, // nominal-bare-argument-unknown
    .{ .source = "type Box a is data=#Box a\nconst Box=fn value=>value\nconst answer=Box 4294967296\n", .code = .duplicate_name, .point = 19 }, // nominal-value-shadow-argument
    .{ .source = "type Box a is data=#Box a\nconst first=4294967296\nconst later=Box U32\n", .code = .unknown_value, .point = 65 }, // nominal-value-known-type-before-overflow
    .{ .source = "type Box a is data=#Box a\nconst answer=(Box) 4294967296\n", .code = .integer_range, .point = 45 }, // nominal-grouped-application-overflow
    .{ .source = "type Box a is data=#Box a\nconst answer=Box U32 4294967296\n", .code = .unknown_value, .point = 43 }, // nominal-second-argument-overflow
    .{ .source = "type Tick a is effect={read:Unit->a}\nconst answer=Tick.read U32 4294967296\n", .code = .integer_range, .point = 64 }, // operation-known-type-then-overflow
    .{ .source = "type Tick a is effect={read:Unit->a}\nconst answer=Tick.read Missing 4294967296\n", .code = .unknown_value, .point = 60 }, // operation-unknown-type-before-overflow
    .{ .source = "type Tick a is effect={read:Unit->a}\nconst answer=(Tick.read) 4294967296 ()\n", .code = .integer_range, .point = 62 }, // operation-grouped-overflow
    .{ .source = "type Tick [a,b] is effect={read:Unit->a}\nconst answer=Tick.read [U32,4294967296] ()\n", .code = .unknown_value, .point = 65 }, // operation-product-type-overflow
    .{ .source = "type Tick {value:a} is effect={read:Unit->a}\nconst answer=Tick.read {value:4294967296} ()\n", .code = .integer_range, .point = 75 }, // operation-record-pattern-overflow
    .{ .source = "type Tick {value:a} is effect={read:Unit->a}\nconst first=4294967296\nconst later=Tick.read {value:U32} ()\n", .code = .integer_range, .point = 57 }, // operation-record-pattern-known
    .{ .source = "type Tick a is effect={read:Unit->a}\nconst first=4294967296\nconst later=Tick.read {value:U32} ()\n", .code = .integer_range, .point = 49 }, // operation-record-binding-pattern
    .{ .source = "type Tick a is effect={read:Unit->a}\nconst answer=(Tick) 4294967296\n", .code = .effect_member, .point = 51 }, // family-grouped-overflow
    .{ .source = "type Tick a is effect={read:Unit->a}\nconst first=4294967296\nconst later=Tick\n", .code = .effect_member, .point = 72 }, // family-bare-overflow-later
    .{ .source = "const answer=4294967296\nconst answer=42\n", .code = .duplicate_name, .point = 0 }, // duplicate-global-overflow
    .{ .source = "type Box is data=#Box U32\nconst answer=Box 4294967296\n", .code = .integer_range, .point = 43 }, // constructor-marker-before-overflow
    .{ .source = "type Box is data=#Box {value:U32}\nconst answer=#Box {unknown:4294967296}\n", .code = .unknown_record_field, .point = 53 }, // record-unknown-field-before-overflow
    .{ .source = "type Box is data=#Box {value:U32}\nconst answer=#Box {value:4294967296,value:0}\n", .code = .integer_range, .point = 59 }, // record-duplicate-field-overflow-first
    .{ .source = "type Box is data=#Box {value:U32}\nconst answer=#Box {value:0,value:4294967296}\n", .code = .duplicate_record_field, .point = 61 }, // record-duplicate-field-overflow-later
    .{ .source = "type Box is data=#Box {value:U32,other:U32}\nconst answer=#Box {value:4294967296}\n", .code = .integer_range, .point = 69 }, // record-missing-field-after-overflow
    .{ .source = "type Choice is data=#First U32|#Second U32\nconst answer=fn x=>case x of\n  #First 4294967296|#Missing _=>42\n", .code = .integer_range, .point = 81 }, // alternative-pattern-overflow-first
    .{ .source = "type Choice is data=#First U32|#Second U32\nconst answer=fn x=>case x of\n  #Missing _|#First 4294967296=>42\n", .code = .unknown_value, .point = 75 }, // alternative-pattern-overflow-later
    .{ .source = "const answer=fn x=>case x of\n  4294967296=>missing\n", .code = .integer_range, .point = 31 }, // case-body-name-before-pattern-overflow
    .{ .source = "const text=\"🙂é\"\nconst answer=4294967296\n", .code = .integer_range, .point = 33 }, // unicode-numeric-origin
    .{ .source = "const answer=(42,{value:4294967296})\n", .code = .integer_range, .point = 24 }, // nested-ordinary-record-overflow
    .{ .source = "const answer=fn f=>f {value:4294967296}\n", .code = .integer_range, .point = 28 }, // nested-record-callee-overflow
    .{ .source = "type Box {value:a} is data=#Box a\nconst first=4294967296\nconst later=Box {other:U32}\n", .code = .constructor_marker, .point = 69 }, // nominal-record-missing-field-type
    .{ .source = "type Box {value:a} is data=#Box a\nconst first=4294967296\nconst later=Box {}\n", .code = .constructor_marker, .point = 69 }, // nominal-record-empty
    .{ .source = "type Tick {value:a} is effect={read:Unit->a}\nconst first=4294967296\nconst later=Tick.read {other:U32} ()\n", .code = .unknown_value, .point = 97 }, // operation-record-missing-field
    .{ .source = "type Tick {value:a} is effect={read:Unit->a}\nconst first=4294967296\nconst later=Tick.read {value:U32,value:U32} ()\n", .code = .unknown_value, .point = 97 }, // operation-record-duplicate-field
    .{ .source = "type Tick {value:a} is effect={read:Unit->a}\nconst first=4294967296\nconst later=Tick.read {} ()\n", .code = .integer_range, .point = 57 }, // operation-record-empty
    .{ .source = "type Tick {value:a} is effect={read:Unit->a}\nconst first=4294967296\nconst later=Tick.read {value:Missing} ()\n", .code = .unknown_value, .point = 97 }, // operation-record-unbound-value
    .{ .source = "type Tick {value:a} is effect={read:Unit->a}\nconst first=4294967296\nconst later=Tick.read {value:@u32.add} ()\n", .code = .call_arity, .point = 97 }, // operation-record-intrinsic-value
    .{ .source = "type Tick {value:a} is effect={read:Unit->a}\nconst answer=Tick.read {value:1e999} ()\n", .code = .float_range, .point = 75 }, // operation-record-float-overflow
    .{ .source = "const Box=fn value=>value\ntype Box a is data=#Box a\nconst answer=4294967296\n", .code = .duplicate_name, .point = 0 }, // nominal-value-collision-reverse
    .{ .source = "const answer=#Missing {value:4294967296}\n", .code = .unknown_constructor, .point = 14 }, // unknown-record-before-overflow
    .{ .source = "const f=fn value=>value\nconst answer=f {value:4294967296}\n", .code = .integer_range, .point = 46 }, // record-ordinary-callee-before-overflow
    .{ .source = "type Tick a is effect={read:Unit->a}\nconst answer=Tick.missing 4294967296\n", .code = .effect_member, .point = 50 }, // qualified-name-argument-overflow
    .{ .source = "const first=4294967296\nconst later=\"bad\"\n", .code = .unsupported_expression, .point = 35 }, // string-before-overflow
    .{ .source = "const first=\"bad\"\nconst later=4294967296\n", .code = .integer_range, .point = 30 }, // overflow-before-string
    .{ .source = "const answer=(\"bad\",4294967296)\n", .code = .unsupported_expression, .point = 14 }, // string-lower-before-overflow
    .{ .source = "const answer=(4294967296,\"bad\")\n", .code = .integer_range, .point = 14 }, // overflow-lower-before-string
    .{ .source = "const first=4294967296\nconst later=@panic \"bad\"\n", .code = .integer_range, .point = 12 }, // string-literal-primitive-before-overflow
    .{ .source = "const answer=@type.call \"add\" 4294967296 42\n", .code = .integer_range, .point = 30 }, // string-literal-descriptor-before-overflow
    .{ .source = "const answer=@type.result \"result\" 4294967296\n", .code = .integer_range, .point = 35 }, // string-literal-result-before-overflow
    .{ .source = "const answer=@panic 4294967296\n", .code = .literal_required, .point = 20 }, // panic-numeric-arity-before-overflow
    .{ .source = "//�\nconst answer=4294967296\n", .code = .integer_range, .point = 19 }, // surrogate-comment-numeric-origin
    .{ .source = "const text=\"�\"\nconst answer=4294967296\n", .code = .integer_range, .point = 30 }, // surrogate-string-before-numeric
    .{ .source = "// 🙂é\nconst answer=4294967296\n", .code = .integer_range, .point = 23 }, // supplementary-comment-numeric-origin
};
fn rejected(allocator: std.mem.Allocator, item: Case) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var lexed = try lexer.lex(allocator, item.source);
    defer lexed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), lexed.diagnostics.items.len);
    var tree = try parser.parse(allocator, item.source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const node_count = tree.nodes.items.len;
    const extra_count = tree.extra.items.len;
    const symbol_count = pool.entries.items.len;
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
    const diagnostic = checked.diagnostics[0];
    errdefer std.debug.print("actual {s} at {d}\n", .{ @tagName(diagnostic.code), diagnostic.span.start });
    try std.testing.expectEqual(item.code, diagnostic.code);
    try std.testing.expectEqual(item.point, diagnostic.span.start);
    if (check.hasNumericFailure(&tree) or diagnostic.code == .module_loader_required) {
        // Guaranteed source failure owns diagnostics only. No expression type,
        // principal value, obligation or executable body may be published.
        try std.testing.expectEqual(@as(usize, 0), checked.expr_types.len);
        try std.testing.expectEqual(@as(usize, 0), checked.resolved.len);
        try std.testing.expectEqual(@as(usize, 1), checked.bindings.len);
        try std.testing.expectEqual(@as(usize, 0), checked.body_elaborations);
        try std.testing.expectEqual(@as(usize, 0), checked.obligations.len);
    }
    if (diagnostic.numeric_literal) |fault| {
        try std.testing.expectEqual(ast.Span{ .start = item.point, .end = item.point }, diagnostic.span);
        try std.testing.expectEqual(ast.Tag.numeric_error, tree.node(fault.node).tag);
        try std.testing.expectEqualDeep(fault, tree.numericFault(fault.node));
        const token = for (lexed.tokens.items) |token| {
            if (token.start == fault.span.start and token.end == fault.span.end) break token;
        } else return error.TestExpectedEqual;
        try std.testing.expectEqual(fault.actual_token, token.tag);
        const publication: syntax.Publication = .{ .cause = .native_detail, .code = @tagName(diagnostic.code), .span = diagnostic.span, .message = diagnostic.message() };
        try std.testing.expect(publication.utf16(item.source) != null);
    }
    try std.testing.expectEqual(node_count, tree.nodes.items.len);
    try std.testing.expectEqual(extra_count, tree.extra.items.len);
    try std.testing.expectEqual(symbol_count, pool.entries.items.len);
}
test "numeric source failures preserve actual frozen lexical declaration primitive and pattern precedence" {
    var failed: usize = 0;
    for (cases) |item| rejected(a, item) catch {
        std.debug.print("numeric source fixture: {s}\n", .{item.source});
        failed += 1;
    };
    try std.testing.expectEqual(@as(usize, 0), failed);
}
test "numeric diagnostic-only publication releases all failed allocations and static trial conversions" {
    for ([_]usize{ 8, 25, 32, 39, 42, 46, 58, 71, 76, 85, 91, 96, 100, 104, 105, 108 }) |index| try @import("allocation_failures.zig").checkAllAllocationFailures(a, rejected, .{cases[index]});
}

fn importedOwnership(allocator: std.mem.Allocator) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    const producer_source = "type Box a is data=#Box a\ntype Tick {value:a} is effect={read:Unit->a}\nconst Box.keep=fn value=>value\nconst identity=fn value=>value\n";
    var producer_lexed = try lexer.lex(allocator, producer_source);
    defer producer_lexed.deinit(allocator);
    var producer_tree = try parser.parse(allocator, producer_source, producer_lexed.tokens.items, &pool);
    defer producer_tree.deinit(allocator);
    var producer = try check.checkModule(allocator, &producer_tree, &pool, &.{}, &.{}, 1);
    var producer_live = true;
    defer if (producer_live) producer.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), producer.diagnostics.len);
    const source = "entry const answer=identity 4294967296\n";
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    const name = pool.lookup("identity").?;
    var binding: check.BindingId = 0;
    for (producer.bindings, 0..) |definition, index| if (definition.name == name and definition.kind == .global) {
        binding = @intCast(index);
        break;
    };
    try std.testing.expect(binding != 0);
    const imports = [_]check.ImportedBinding{.{ .name = name, .target = .{ .unit = 1, .binding = binding }, .interface = .{ .types = .{ .store = &producer.types }, .scheme = producer.bindings[binding].scheme, .obligations = producer.obligations, .named_function = true }, .origin = 0 }};
    const catalogs = [_]check.ImportedCatalog{.{ .producer = &producer, .kind = .catalog, .index = 0, .origin = 0 }};
    var checked = try check.checkModule(allocator, &tree, &pool, &imports, &catalogs, 2);
    defer checked.deinit(allocator);
    // Result owns only rejection data. Static conversion of the borrowed
    // producer catalog and associated declarations has already been destroyed.
    producer.deinit(allocator);
    producer_live = false;
    try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
    try std.testing.expectEqual(check.Code.integer_range, checked.diagnostics[0].code);
    try std.testing.expectEqual(@as(usize, 0), checked.imported_schemes);
    try std.testing.expectEqual(@as(usize, 0), checked.expr_types.len);
    try std.testing.expectEqual(@as(usize, 0), checked.nominals.len);
    try std.testing.expectEqual(@as(usize, 0), checked.effect_families.len);
    try std.testing.expectEqual(@as(usize, 1), checked.bindings.len);
    try std.testing.expectEqualStrings("integer literal exceeds U32 (4294967295)", checked.diagnostics[0].message());
    try std.testing.expectEqualDeep(tree.numericFault(checked.diagnostics[0].numeric_literal.?.node), checked.diagnostics[0].numeric_literal.?);
}
test "numeric failure adapts borrowed principal imports to static facts without publishing their interfaces" {
    try importedOwnership(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, importedOwnership, .{});
}

fn projectOwnership(allocator: std.mem.Allocator, entry: []const u8, prelude: ?[]const u8) !void {
    var loaded = try project.load(allocator, std.testing.io, entry, .{ .prelude_path = prelude });
    defer loaded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    var checked = try project_check.checkProject(allocator, &loaded);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
    try std.testing.expectEqualStrings("integer_range", checked.diagnostics[0].codeName());
    for (checked.modules) |module_| try std.testing.expect(module_ == null);
    try std.testing.expectEqual(@as(usize, 0), checked.body_elaborations);
    try std.testing.expectEqual(@as(usize, 0), checked.imported_schemes);
    try std.testing.expect(checked.diagnostics[0].numeric_literal != null);
}
test "numeric project failures destroy every static region before publication and every failed allocation" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "dependency.blot", .data = "const identity=fn value=>value\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "prelude.blot", .data = "const invalid:U32=#True\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "import {identity} from \"./dependency\"\nentry const answer=identity 4294967296\n" });
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const count = try tmp.dir.realPath(std.testing.io, &buffer);
    const entry = try std.fs.path.join(a, &.{ buffer[0..count], "main.blot" });
    defer a.free(entry);
    const prelude = try std.fs.path.join(a, &.{ buffer[0..count], "prelude.blot" });
    defer a.free(prelude);
    for ([_]?[]const u8{ null, prelude }) |prelude_path| {
        try projectOwnership(a, entry, prelude_path);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, projectOwnership, .{ entry, prelude_path });
    }
}
