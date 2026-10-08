const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const T = @import("types.zig");
const a = std.testing.allocator;

fn binding(checked: *const check.Checked, pool: *const symbols.Pool, name: []const u8) check.Binding {
    for (checked.bindings) |item| if (std.mem.eql(u8, pool.get(item.name), name)) return item;
    unreachable;
}
fn predicates(checked: *const check.Checked, item: check.Binding) []const T.Obligation {
    return checked.obligations[item.scheme.obligations.start..][0..item.scheme.obligations.len];
}
fn nominalTuple(store: *const T.Store, ty: T.Id) []const T.Id {
    const arguments = store.nominalArguments(store.node(ty));
    std.debug.assert(arguments.len == 1);
    const tuple = store.node(arguments[0]);
    std.debug.assert(tuple.tag == .product);
    return store.list(.{ .start = tuple.a, .len = tuple.b });
}
const source =
    \\infixl 60 (+) = _fixity_add
    \\type Box a is data = #Box {value: a}
    \\type Signal a is effect = { get: Unit -> a }
    \\const twice: a -> a where { associated "add" a a a } = fn value => value + value
    \\const first: a -> b where { field "value" a b } = fn box => box.value
    \\const bind: a -> b where { receiver "plus" a Unit b } = fn box => box.plus
    \\const replace: a -> b -> c where { update "value" a b c } = fn box => fn value => do:
    \\  let current = box
    \\  current.value := value
    \\  return current
    \\const read: Unit -> a ! {| e} where { operation Signal.get a } = fn () => Signal.get a ()
    \\const identity: a -> a where { type_rep a } = fn value => value
    \\let started: U32 where { effect_rep ! {} } = 7
    \\const narrow: U32 -> U32 where { associated "add" U32 U32 b } = fn value => value
    \\const unknown: a -> a where { associated "missing" a a a } = fn value => value
    \\entry const answer = fn () => do:
    \\  let represented: U32 where { type_rep U32 } = 42
    \\  let choose: a -> a where { type_rep a } = fn value => value
    \\  let first = choose represented
    \\  return @u32.add (choose first) (@f32.to_u32 (choose 0.0))
    \\const _fixity_add = fn left => fn right => @type.call "add" left right
;

fn qualifiedSchemes(allocator: std.mem.Allocator) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("WHERE {s} at {d}\n", .{ @tagName(diagnostic.code), diagnostic.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    for ([_]struct { []const u8, T.ObligationKind }{ .{ "twice", .dispatch }, .{ "first", .field }, .{ "bind", .receiver }, .{ "replace", .update }, .{ "read", .effect_operation }, .{ "identity", .type_rep }, .{ "started", .effect_rep }, .{ "represented", .type_rep } }) |expected| {
        const requirements = predicates(&checked, binding(&checked, &pool, expected[0]));
        try std.testing.expectEqual(@as(usize, 1), requirements.len);
        try std.testing.expectEqual(expected[1], requirements[0].kind);
        try std.testing.expect(requirements[0].explicit);
    }
    const twice = predicates(&checked, binding(&checked, &pool, "twice"))[0];
    try std.testing.expectEqualStrings("add", pool.get(twice.name));
    try std.testing.expectEqual(T.Operator.add, twice.operator);
    const narrow = binding(&checked, &pool, "narrow");
    try std.testing.expectEqual(@as(u32, 1), narrow.scheme.variables.len);
    try std.testing.expectEqual(@as(u32, 1), narrow.scheme.row_variables.len);
    const extra = predicates(&checked, narrow)[0];
    try std.testing.expectEqualSlices(T.Id, &.{extra.result}, checked.types.list(narrow.scheme.variables));
    const row = checked.types.row(checked.types.node(extra.signature).c);
    try std.testing.expect(row.tail == .variable);
    try std.testing.expectEqualSlices(u32, &.{row.tail.variable}, checked.types.list(narrow.scheme.row_variables));
    const get = predicates(&checked, binding(&checked, &pool, "read"))[0];
    try std.testing.expectEqual(@as(u32, 1), checked.types.node(get.other).b);
    try std.testing.expect(checked.types.node(get.signature).tag == .function);
}

test "written clauses own all predicate forms closed extras and predicate-only quantifiers" {
    try qualifiedSchemes(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, qualifiedSchemes, .{});
}

fn rejectionLaws(allocator: std.mem.Allocator) !void {
    const cases = [_]struct { source: []const u8, code: check.Code, marker: []const u8 }{
        .{ .source = "entry const answer: U32 where { mystery U32 } = 42\n", .code = .invalid_constraint, .marker = "mystery" },
        .{ .source = "entry const answer: U32 where { associated \"add\" U32 U32 } = 42\n", .code = .invalid_constraint, .marker = "associated" },
        .{ .source = "entry const answer: U32 where { type_rep \"add\" U32 } = 42\n", .code = .invalid_constraint, .marker = "type_rep" },
        .{ .source = "entry const answer: U32 where { field \"x\" U32 U32 ! {} } = 42\n", .code = .invalid_constraint, .marker = "field" },
        .{ .source = "entry const answer = fn (callback: U32 -> U32 where {}) => 42\n", .code = .higher_rank_constraint, .marker = "where" },
        .{ .source = "infixl 60 (+) = _fixity_add\nconst twice: a -> a where {} = fn value => value + value\nentry const answer = 42\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n", .code = .missing_predicate, .marker = "+ value" },
        .{ .source = "const first: a -> b where {} = fn value => value.field\nentry const answer = 42\n", .code = .missing_predicate, .marker = "field" },
        .{ .source = "infixl 60 (+) = _fixity_add\nconst twice: a -> a where { associated \"sub\" a a a } = fn value => value + value\nentry const answer = 42\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n", .code = .missing_predicate, .marker = "+ value" },
        .{ .source = "const identity: e -> e where { effect_rep ! {| e} } = fn value => value\nentry const answer = 42\n", .code = .annotation_kind_mismatch, .marker = "e}" },
        .{ .source = "type Signal a is effect = { get: Unit -> a }\nentry const answer: U32 where { operation Signal.get } = 42\n", .code = .effect_arity, .marker = "where" },
        .{ .source = "type Reader is effect = { get: Unit -> U32 }\nentry const answer: U32 where { operation Reader.get } = 42\n", .code = .invalid_constraint, .marker = "operation" },
        .{ .source = "type Signal a is effect = { get: Unit -> a }\nentry const answer: U32 where { operation (Signal.get) U32 } = 42\n", .code = .invalid_constraint, .marker = "operation" },
        .{ .source = "entry const answer: U32 where { effect_rep ! {Missing} } = 42\n", .code = .unknown_effect, .marker = "effect_rep" },
        .{ .source = "type Signal a is effect = Unit -> a\nentry const answer: U32 -> U32 where { associated \"add\" U32 U32 U32 ! {Signal a | e} } = fn value => value\n", .code = .unsupported_polymorphic_effect_label, .marker = "associated" },
        .{ .source = "const replace: a -> b -> c where {} = fn box => fn value => do:\n  let current = box\n  current.value := value\n  return current\nentry const answer = 42\n", .code = .missing_predicate, .marker = ".value" },
        .{ .source = "infixl 60 (+) = _fixity_add\nconst twice: a -> a where { associated \"add\" a a a } = fn value => value + value\nentry const answer = fn () => do:\n  let selected = case #True of\n    #True => twice\n    #False => twice\n  return @f32.add (@u32.to_f32 (selected 21)) (selected 1.5)\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n", .code = .type_mismatch, .marker = "selected 1.5" },
    };
    for (cases) |item| {
        var tokens = try lexer.lex(allocator, item.source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, item.source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(allocator, &tree, &pool);
        defer checked.deinit(allocator);
        try std.testing.expect(checked.diagnostics.len != 0);
        try std.testing.expectEqual(item.code, checked.diagnostics[0].code);
        try std.testing.expectEqual(@as(u32, @intCast(std.mem.find(u8, item.source, item.marker).?)), checked.diagnostics[0].span.start);
    }
}

test "written clauses reject malformed predicates missing coverage kinds and computed mixed uses" {
    try rejectionLaws(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, rejectionLaws, .{});
}

fn recursiveLaws(allocator: std.mem.Allocator) !void {
    for ([_][]const u8{ "", "associated \"add\" a a a" }) |clause| {
        const text = try allocator.print(
            \\infixl 60 (+) = _fixity_add
            \\const first: a -> a = fn value => do:
            \\  let alias: a -> a where {{ {s} }} = second
            \\  return alias value
            \\const second: a -> a = fn value => third value
            \\const third: a -> a = fn value => case #True of
            \\  #True => value + value
            \\  #False => first value
            \\entry const answer = fn () => first 21
            \\const _fixity_add = fn left => fn right => @type.call "add" left right
        , .{clause});
        defer allocator.free(text);
        var tokens = try lexer.lex(allocator, text);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        var checked = try check.check(allocator, &tree, &pool);
        defer checked.deinit(allocator);
        if (clause.len == 0) {
            try std.testing.expect(checked.diagnostics.len != 0);
            try std.testing.expectEqual(check.Code.missing_predicate, checked.diagnostics[0].code);
            try std.testing.expectEqual(@as(u32, @intCast(std.mem.find(u8, text, "second\n").?)), checked.diagnostics[0].span.start);
        } else {
            try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
            try std.testing.expect(predicates(&checked, binding(&checked, &pool, "alias")).len != 0);
        }
    }
}

test "local empty clauses recheck active mutual and transitive source peers" {
    try recursiveLaws(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, recursiveLaws, .{});
}

fn importedSchemes(allocator: std.mem.Allocator, loaded: *project.Project) !void {
    var checked = try project_check.checkProject(allocator, loaded);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const module = &checked.module(loaded.entry).checked;
    const imported = binding(module, &loaded.symbols, "invoke");
    try std.testing.expectEqual(@as(u32, 1), imported.scheme.variables.len);
    try std.testing.expectEqual(@as(u32, 1), imported.scheme.row_variables.len);
    const requirements = predicates(module, imported);
    try std.testing.expectEqual(@as(usize, 2), requirements.len);
    const arrow = module.types.node(imported.scheme.root);
    const callback = module.types.node(arrow.a);
    for (requirements) |constraint| {
        try std.testing.expect(constraint.explicit);
        if (constraint.kind == .effect_rep) try std.testing.expectEqual(module.types.row(callback.c).tail.variable, module.types.row(module.types.node(constraint.signature).c).tail.variable);
    }
}

test "imported qualified schemes preserve both numeric namespaces and exact predicate row identity" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "library.blot", .data = "const invoke: (Unit -> a ! {| e}) -> a ! {| e} where { type_rep a, effect_rep ! {| e} } = fn callback => callback ()\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = "import { invoke } from \"./library\"\nentry const answer = fn () => invoke (fn () => 42)\n" });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    var loaded = try project.load(a, std.testing.io, path, .{});
    defer loaded.deinit(a);
    try importedSchemes(a, &loaded);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, importedSchemes, .{&loaded});
}

fn ownedTemplateLaws(allocator: std.mem.Allocator) !void {
    const text =
        \\infixl 60 (+) = _fixity_add
        \\const twice: a -> a where { associated "add" a a a } = fn value => value + value
        \\const alias = twice
        \\entry const answer = fn () => do:
        \\  let local = alias
        \\  let integer = local 20
        \\  return @u32.add integer (@f32.to_u32 (local 1.0))
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    ;
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const local = binding(&checked, &pool, "local");
    try std.testing.expectEqual(@as(u32, 1), local.scheme.variables.len);
    try std.testing.expectEqual(@as(usize, 1), predicates(&checked, local).len);
    const marker: u32 = @intCast(std.mem.find(u8, text, "where").?);
    for (predicates(&checked, binding(&checked, &pool, "answer"))) |requirement| {
        if (!requirement.explicit) continue;
        try std.testing.expectEqual(marker, requirement.qualification_span.?.start);
        try std.testing.expectEqual(checked.unit, requirement.qualification_unit);
        const variables = try checked.types.freeVariables(requirement.ty);
        defer allocator.free(variables);
        try std.testing.expectEqual(@as(usize, 0), variables.len);
    }
}

test "local template requirements move into their scheme and concrete uses retain the original source origin" {
    try ownedTemplateLaws(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, ownedTemplateLaws, .{});
}

fn changingUpdateLaws(allocator: std.mem.Allocator) !void {
    const text =
        \\type Box (a, b) is data = #Box { value: a, keep: b }
        \\const change = fn (box: Box (U32, Bool)) => do:
        \\  let current = box
        \\  current.value := 42.0
        \\  return current
        \\entry const answer = fn () => do:
        \\  let #Box {value, keep} = change (#Box {value: 20, keep: #True})
        \\  return @f32.to_u32 value
    ;
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const arrow = checked.types.node(binding(&checked, &pool, "change").scheme.root);
    const input = nominalTuple(&checked.types, arrow.a);
    const output = nominalTuple(&checked.types, arrow.b);
    try std.testing.expectEqualSlices(T.Id, &.{ T.u32_type, T.boolean }, input);
    try std.testing.expectEqualSlices(T.Id, &.{ T.f32_type, T.boolean }, output);
    var successor = false;
    for (checked.bindings) |item| if (item.predecessor != 0) {
        successor = true;
        try std.testing.expectEqualSlices(T.Id, output, nominalTuple(&checked.types, item.scheme.root));
        try std.testing.expectEqualSlices(T.Id, input, nominalTuple(&checked.types, checked.bindings[item.predecessor].scheme.root));
    };
    try std.testing.expect(successor);
}

test "updaters change the assigned field type and retain each untouched nominal field and predecessor" {
    try changingUpdateLaws(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, changingUpdateLaws, .{});
}
