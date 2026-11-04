const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const ast = @import("../parse/ast.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const a = std.testing.allocator;
const Case = struct { source: []const u8, code: ?check.Code, point: u32 = 0, exact_span: bool = true };
const cases = [_]Case{
    .{ .source = "const invalid = func value => return do:\n  let (true, selected) = value\n  break selected\n", .code = .non_exhaustive_match, .point = 43 }, // original-151
    .{ .source = "const invalid = func () => return do:\n  let (first, second, third) = (1, 2)\n  break first\n", .code = .product_arity, .point = 40 }, // original-153
    .{ .source = "type Pair is data = $Pair U32\nconst invalid = func value => return case value of\n  $Pair {} => 0\n", .code = .record_constructor, .point = 84 }, // original-158
    .{ .source = "type Pair is data = $Pair { x: U32, x: U32 }\n", .code = .duplicate_record_field, .point = 36 }, // original-171
    .{ .source = "type Pair is data = $Pair { x: U32, y: U32 }\nconst make = func () => return $Pair { x: 1 }\n", .code = .missing_record_field, .point = 77 }, // original-172
    .{ .source = "type Pair is data = $Pair { x: U32, y: U32 }\nconst make = func () => return $Pair { x: 1, y: 2, z: 3 }\n", .code = .unknown_record_field, .point = 96 }, // original-173
    .{ .source = "type Pair is data = $Pair { x: U32, y: U32 }\nconst make = func () => return $Pair { x: 1, y: 2, x: 3 }\n", .code = .duplicate_record_field, .point = 96 }, // original-174
    .{ .source = "type Box is data = $Box U32\nconst make = func () => return $Box { x: 1 }\n", .code = .record_constructor, .point = 60 }, // original-175
    .{ .source = "const make = func value => return $value { x: 1 }\n", .code = .record_constructor, .point = 35 }, // original-176
    .{ .source = "pub const answer = func () => return 42", .code = .unknown_modifier, .point = 0 }, // original-317
    .{ .source = "pub let answer = func () => return 42", .code = .unknown_modifier, .point = 0 }, // original-318
    .{ .source = "type Pair is data = $Pair { x: U32, y: U32 }\nconst x=1\nconst y=2\nconst invalid = func () => return $Pair { absent: missing }\n", .code = .unknown_record_field, .point = 107 }, // unknown-before-value
    .{ .source = "type Pair is data = $Pair { x: U32, y: U32 }\nconst x=1\nconst y=2\nconst invalid = func () => return $Pair { x: 1, x: missing }\n", .code = .duplicate_record_field, .point = 113 }, // duplicate-before-value
    .{ .source = "type Pair is data = $Pair { x: U32, y: U32 }\nconst x=1\nconst y=2\nconst invalid = func () => return $Pair { x: missing }\n", .code = .unknown_value, .point = 110 }, // missing-after-value
    .{ .source = "type Pair is data = $Pair { x: U32, y: U32 }\nconst x=1\nconst y=2\nconst invalid = func () => return $Pair { x: missing, absent: 2 }\n", .code = .unknown_value, .point = 110 }, // unknown-after-value
    .{ .source = "type Pair is data = $Pair { x: U32, y: U32 }\nconst x=1\nconst y=2\nconst invalid = func () => return $Pair {}\n", .code = .missing_record_field, .point = 100 }, // allmissing
    .{ .source = "type Pair is data = $Pair { x: U32, y: U32 }\nconst x=1\nconst y=2\nconst invalid = func () => return $Pair { y: 2, x: 1 }\n", .code = null, .point = 0 }, // reordered-positive
    .{ .source = "type Pair is data = $Pair { x: U32, y: U32 }\nconst x=1\nconst y=2\nconst invalid = func () => return $Pair { y, x }\n", .code = null, .point = 0 }, // shorthand-positive
    .{ .source = "type Pair is data = $Pair { x: Missing, x: U32 }\n", .code = .duplicate_record_field, .point = 40 }, // declaration-duplicate-vs-type
    .{ .source = "type Pair is data = $Pair { x: U32, x: U32 }\nentry const answer=1+2\n", .code = .duplicate_record_field, .point = 36 }, // declaration-duplicate-vs-operator
    .{ .source = "infixl 300 (+) = missing\ntype Pair is data = $Pair { x: U32, x: U32 }\n", .code = .duplicate_record_field, .point = 61 }, // declaration-duplicate-vs-fixity
    .{ .source = "const repeated=1\nconst repeated=2\ntype Pair is data = $Pair { x: U32, x: U32 }\n", .code = .duplicate_record_field, .point = 70 }, // declaration-duplicate-vs-duplicate-name
    .{ .source = "type Box is data= $Box U32\nconst invalid=func()=> return $Box { x: missing }\n", .code = .record_constructor, .point = 58 }, // nonrecord-target-before-value
    .{ .source = "type Empty is data= $Empty\nconst invalid=func()=> return $Empty {}\n", .code = .record_constructor, .point = 58 }, // nullary-record-value
    .{ .source = "type Empty is data= $Empty {}\nentry const answer=func()=> return case $Empty {} of\n  $Empty {} => 42\n", .code = null, .point = 0 }, // empty-record-value
    .{ .source = "type Pair is data= $Pair ({x:U32,y:U32})\nentry const answer=func()=> return case $Pair {x:20,y:22} of\n  $Pair {x,y}=>@u32.add x y\n", .code = .record_constructor, .point = 82 }, // grouped-record-value
    .{ .source = "const target=func x=> return x\nconst invalid=func()=> return $target {x:1}\n", .code = .record_constructor, .point = 62 }, // ordinary-target-record
    .{ .source = "const invalid=func()=> return $Missing {x:missing}\n", .code = .unknown_constructor, .point = 31 }, // missing-ctor-before-value
    .{ .source = "type Box is data= $Box U32\nconst invalid=func value=> return case value of\n  $Box {x}=>missing\n", .code = .record_constructor, .point = 78 }, // nonrecord-pattern-before-body
    .{ .source = "type Empty is data= $Empty\nconst invalid=func value=> return case value of\n  $Empty {}=>0\n", .code = .record_constructor, .point = 78 }, // nullary-record-pattern
    .{ .source = "type Pair is data = $Pair { x: U32, y: U32 }\nconst invalid=func value=> return case value of\n  $Pair {z:^missing}=>0\n", .code = .unknown_record_field, .point = 102 }, // unknown-pattern-before-name
    .{ .source = "type Pair is data = $Pair { x: U32, y: U32 }\nconst invalid=func value=> return case value of\n  $Pair {x, x:^missing}=>0\n", .code = .duplicate_record_field, .point = 105 }, // duplicate-pattern-before-name
    .{ .source = "type Pair is data = $Pair { x: U32, y: U32 }\nentry const answer=func()=> return case $Pair {x:42,y:0} of\n  $Pair {x}=>x\n", .code = null, .point = 0 }, // missing-pattern-fields-positive
    .{ .source = "pub const invalid=missing\n", .code = .unknown_modifier, .point = 0 }, // modifier-vs-missing
    .{ .source = "pub const repeated=1\nconst repeated=2\n", .code = .duplicate_name, .point = 0 }, // modifier-vs-duplicate
    .{ .source = "pub const invalid=1+2\n", .code = .unknown_modifier, .point = 0 }, // modifier-vs-operator
    .{ .source = "pub const first=42\nconst second=missing\n", .code = .unknown_value, .point = 32 }, // modifier-declarations-order
    .{ .source = "const first=missing\npub const second=42\n", .code = .unknown_modifier, .point = 20 }, // modifier-last
    .{ .source = "const invalid=func value=> return do:\n  let true=value\n  break 42\n", .code = .non_exhaustive_match, .point = 40 }, // refutable-bool
    .{ .source = "type Maybe a is data= $Some a| $None\nconst invalid=func()=> return do:\n  let $Some value= $Some 42\n  break value\n", .code = .non_exhaustive_match, .point = 73 }, // refutable-constructor
    .{ .source = "const invalid=func()=> return do:\n  let true=42\n  break 0\n", .code = .type_mismatch, .point = 36 }, // refutable-type-failure
    .{ .source = "const invalid=func()=> return do:\n  let value=42 else:\n    0\n  break value\n", .code = .guard_fallthrough, .point = 36 }, // guard-irrefutable
    .{ .source = "const invalid=func()=> return do:\n  let true=42 else:\n    0\n  break 0\n", .code = .type_mismatch, .point = 36 }, // guard-type-failure
    .{ .source = "type Maybe a is data= $Some a| $None\nentry const answer=func()=> return do:\n  let $Some value= $Some 42 else:\n    break 0\n  break value\n", .code = null, .point = 0 }, // guard-positive
    .{ .source = "type Maybe a is data= $Some a| $None\nentry const answer=func()=> return do:\n  let $Some value= $Some 42 else:\n    @panic \"unreachable\"\n  break value\n", .code = null, .point = 0 }, // guard-panic-positive
    .{ .source = "const invalid=func()=> return do:\n  let (true, second, third)=(1,2)\n  break second\n", .code = .product_arity, .point = 36 }, // product-count-versus-element
    .{ .source = "const invalid=func()=> return do:\n  let ((first,second,third),fourth)=((1,2),3)\n  break first\n", .code = .product_arity, .point = 36 }, // product-nested-count
    .{ .source = "const invalid=func (value:(U32,U32))=> return do:\n  let (first,second,third)=value\n  break first\n", .code = .product_arity, .point = 52 }, // product-annotated-count
    .{ .source = "const invalid=func()=> return do:\n  let (first,second)=()\n  break first\n", .code = .type_mismatch, .point = 36 }, // product-unit-type-mismatch
    .{ .source = "entry const answer=func()=> return do:\n  let (first,second)=(20,22)\n  break @u32.add first second\n", .code = null, .point = 0 }, // product-positive
    .{ .source = "const invalid=func()=> return do:\n  let identity=func value=> return value else:\n    break 0\n  let first=identity 1\n  let second=identity 1.5\n  break 0\n", .code = .type_mismatch, .point = 129, .exact_span = false }, // guard-binder-monomorphic
    .{ .source = "entry const answer=func()=> return do:\n  let identity=func value=> return value\n  let first=identity 42\n  let second=identity 1.5\n  break first\n", .code = null, .point = 0 }, // plain-binder-polymorphic
    .{ .source = "type Pair is data= $Pair {x:U32,x:U32}\nconst repeated=1\nconst repeated=2\n", .code = .duplicate_name, .point = 39 }, // declaration-duplicate-name-later
    .{ .source = "type Pair is data= $Pair ({x:U32,x:U32})\n", .code = .duplicate_type_field, .point = 26 }, // grouped-declaration-duplicate
    .{ .source = "type Pair is data= $Pair {x:U32,y:U32}\nconst invalid=func()=> return $Pair {z}\n", .code = .unknown_record_field, .point = 76 }, // shorthand-missing-field-before-missing-value
    .{ .source = "type Pair is data= $Pair {x:U32,y:U32}\nentry const answer=func()=> return case $Pair {x:20,y:22} of\n  $Pair {x,y}=>@u32.add x y\n", .code = null, .point = 0 }, // record-type-field-label-not-global
    .{ .source = "const invalid=func ns=> return $ns.Pair {x:1}\n", .code = .unknown_constructor, .point = 32 }, // local-record-qualified-root
    .{ .source = "const invalid=func ns=> return func value=> return case value of\n  $ns.Pair {x}=>0\n", .code = .unknown_constructor, .point = 68 }, // record-pattern-local-qualified-root
    .{ .source = "const invalid=func()=> return $U32 {}\n", .code = .unknown_constructor, .point = 31 }, // target primitive_type
    .{ .source = "const invalid=func()=> return $Unit {}\n", .code = .unknown_constructor, .point = 31 }, // target unit_type
    .{ .source = "type Box is data= $Other U32\nconst invalid=func()=> return $Box {}\n", .code = .unknown_constructor, .point = 60 }, // target header_without_constructor
    .{ .source = "type Box a is data= $Other a\nconst invalid=func()=> return $Box {}\n", .code = .unknown_constructor, .point = 60 }, // target generic_header_without_constructor
    .{ .source = "type Input is effect={get:Unit->U32}\nconst invalid=func()=> return $Input {}\n", .code = .record_constructor, .point = 68 }, // target grouped_effect_family
    .{ .source = "type Read is effect=Unit->U32\nconst invalid=func()=> return $Read {}\n", .code = .record_constructor, .point = 61 }, // target callable_effect
    .{ .source = "const U32=42\nconst invalid=func()=> return $U32 {}\n", .code = .record_constructor, .point = 44 }, // target explicit_global_primitive_name
};
fn scenario(allocator: std.mem.Allocator, case: Case) !void {
    var tokens = try lexer.lex(allocator, case.source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, case.source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const nodes = try allocator.dupe(ast.Node, tree.nodes.items);
    defer allocator.free(nodes);
    const spans = try allocator.dupe(ast.Span, tree.spans.items);
    defer allocator.free(spans);
    const extras = try allocator.dupe(u32, tree.extra.items);
    defer allocator.free(extras);
    const symbols_before = pool.entries.items.len;
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    if (case.code) |code| {
        try std.testing.expect(checked.diagnostics.len != 0);
        try std.testing.expectEqual(code, checked.diagnostics[0].code);
        if (case.exact_span) try std.testing.expectEqual(ast.Span{ .start = case.point, .end = case.point }, checked.diagnostics[0].span);
    } else try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqualSlices(ast.Node, nodes, tree.nodes.items);
    try std.testing.expectEqualSlices(ast.Span, spans, tree.spans.items);
    try std.testing.expectEqualSlices(u32, extras, tree.extra.items);
    try std.testing.expectEqual(symbols_before, pool.entries.items.len);
}
test "record and pattern diagnostics preserve contextual frozen stages and guard scopes" {
    for (cases) |case| try scenario(a, case);
}
test "record and guard validation release every failed allocation without mutating source" {
    for ([_]usize{ 2, 3, 4, 18, 22, 24, 25, 43, 41, 46, 50, 55 }) |index|
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, scenario, .{cases[index]});
}

fn importedScenario(allocator: std.mem.Allocator, path: []const u8, code: ?check.Code, point: u32) !void {
    const Owned = struct { checked: project_check.CheckedProject, entry: project.UnitId, names: [3]symbols.Symbol };
    var owned = frontends: {
        var source = try project.load(allocator, std.testing.io, path, .{});
        defer source.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
        var checked = try project_check.checkProject(allocator, &source);
        errdefer checked.deinit(allocator);
        if (code) |expected| {
            try std.testing.expect(checked.diagnostics.len != 0);
            try std.testing.expectEqual(expected, checked.diagnostics[0].semantic.?);
            try std.testing.expectEqual(ast.Span{ .start = point, .end = point }, checked.diagnostics[0].span);
        } else try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        break :frontends Owned{ .checked = checked, .entry = source.entry, .names = .{ source.symbols.lookup("Pair").?, source.symbols.lookup("Empty").?, source.symbols.lookup("Nullary").? } };
    };
    defer owned.checked.deinit(allocator);
    // The immutable imported catalog owns the distinction after source,
    // syntax, symbol storage and producer interfaces have been destroyed.
    const consumer = &owned.checked.module(owned.entry).checked;
    var found = [_]bool{ false, false, false };
    for (consumer.constructors) |constructor| {
        if (constructor.identity.unit == owned.entry) continue;
        for (owned.names, 0..) |name, index| if (constructor.name == name) {
            try std.testing.expectEqual(index != 2, constructor.declared_record);
            found[index] = true;
        };
    }
    try std.testing.expectEqualSlices(bool, &.{ true, true, true }, &found);
}

test "imported record kind remains owned across frontend teardown and every allocation failure" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "producer.blot", .data = "type Pair is data= $Pair {x:U32,y:U32}\ntype Empty is data= $Empty {}\ntype Nullary is data= $Nullary\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "" });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    const imported = [_]Case{
        .{ .source = "import * as shape from \"./producer\"\nentry const answer=func()=> return case $shape.Empty {} of\n  $shape.Empty {}=>42\n", .code = null },
        .{ .source = "import * as shape from \"./producer\"\nentry const answer=func()=> return $shape.Nullary {}\n", .code = .record_constructor, .point = 72 },
        .{ .source = "import * as shape from \"./producer\"\nentry const answer=func()=> return $shape.Pair {x:42}\n", .code = .missing_record_field, .point = 72 },
    };
    for (imported) |case| {
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = case.source });
        try importedScenario(a, path, case.code, case.point);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, importedScenario, .{ path, case.code, case.point });
    }
}
