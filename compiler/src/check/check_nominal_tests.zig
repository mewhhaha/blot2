const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("check.zig");
const T = @import("types.zig");
const a = std.testing.allocator;
const Fixture = struct {
    pool: symbols.Pool = .{},
    tree: @import("../parse/ast.zig").Tree,
    checked: check.Checked,
    fn init(source: []const u8) !Fixture {
        return initWithOptions(source, .{});
    }
    fn initWithOptions(source: []const u8, options: check.ModuleOptions) !Fixture {
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        const checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, options);
        return .{ .pool = pool, .tree = tree, .checked = checked };
    }
    fn deinit(self: *Fixture) void {
        self.checked.deinit(a);
        self.tree.deinit(a);
        self.pool.deinit(a);
    }
    fn valid(self: *Fixture) !void {
        for (self.checked.diagnostics) |d| std.debug.print("{s}:{d}: {s}\n", .{ @tagName(d.code), d.span.start, d.message() });
        try std.testing.expectEqual(@as(usize, 0), self.checked.diagnostics.len);
    }
};
pub const records_source =
    \\infixl 60 (+) = _fixity_add
    \\type Vec2 is data = $Vec2 { x: F32, y: F32 }
    \\const sum = func point => return do:
    \\  let $Vec2 { x, y } = point
    \\  break x + y
    \\const origin = $Vec2 { y: 2.0, x: 20.0 }
    \\entry const answer = func () : F32 => return sum origin
    \\entry const projected = func () : F32 => return origin.x
    \\entry const tuple = func () : U32 => return @product.get (20, 22) 1
    \\const _fixity_add = func left => return func right => return @type.call "add" left right
;
test "nominal record source has canonical field order and independently owned constructor schemes" {
    var f = try Fixture.init(records_source);
    defer f.deinit();
    try f.valid();
    try std.testing.expectEqual(@as(usize, 2), f.checked.nominals.len);
    try std.testing.expectEqual(@as(usize, 2), f.checked.constructors.len);
    try std.testing.expectEqual(@as(u32, 1), f.checked.nominals[1].identity.unit);
    const ctor = f.checked.constructors[1];
    const record = f.checked.types.node(ctor.payload);
    try std.testing.expectEqual(T.Tag.record, record.tag);
    try std.testing.expectEqualStrings("x", f.pool.get(f.checked.types.recordField(record, 0).name));
    try std.testing.expectEqualStrings("y", f.pool.get(f.checked.types.recordField(record, 1).name));
    var reversed = false;
    for (f.tree.nodes.items, 0..) |n, id| if (n.tag == .record) {
        const fields = f.tree.children(@intCast(id));
        if (fields.len == 2) {
            try std.testing.expectEqual(@as(u32, 1), f.checked.projections[fields[0]]);
            try std.testing.expectEqual(@as(u32, 0), f.checked.projections[fields[1]]);
            reversed = true;
        }
    };
    try std.testing.expect(reversed);
}
test "generic nominal payloads and shaped annotations retain principal variables across scalar uses" {
    var f = try Fixture.init(
        \\type Box a is data = $Box a
        \\type Pair [left, right] is data = $Pair (left, right)
        \\const unbox = func box => return do:
        \\  let $Box value = box
        \\  break value
        \\const first = func (pair: Pair [U32, a]) => return do:
        \\  let $Pair (value, _) = pair
        \\  break value
        \\entry const integer = func () => return unbox ($Box 42)
        \\entry const floating = func () => return unbox ($Box 1.25)
        \\entry const paired = func () => return first ($Pair (42, true))
    );
    defer f.deinit();
    try f.valid();
    try std.testing.expectEqual(@as(u32, 1), f.checked.nominals[2].parameters.len);
    try std.testing.expectEqual(@as(u32, 2), f.checked.nominals[2].variables.len);
}
test "record constructor diagnostics retain duplicate missing and wrong nominal identity" {
    for ([_]struct { source: []const u8, code: check.Code }{
        .{ .source = "type P is data = $P {x:U32,y:U32}\nentry const x= $P {x:1,x:2,y:3}\n", .code = .duplicate_record_field },
        .{ .source = "type P is data = $P {x:U32,y:U32}\nentry const x= $P {x:1}\n", .code = .missing_record_field },
        .{ .source = "type P is data = $P U32\ntype Q is data = $Q U32\nentry const x:P= $Q 1\n", .code = .type_mismatch },
    }) |case_| {
        var f = try Fixture.init(case_.source);
        defer f.deinit();
        var found = false;
        for (f.checked.diagnostics) |d| if (d.code == case_.code) {
            found = true;
        };
        try std.testing.expect(found);
    }
}
test "array element projections retain nominal result through unary primitive applications" {
    var f = try Fixture.init(
        \\type Box is data = $Box { x: U32 }
        \\const values = #[$Box { x: 40 }, $Box { x: 2 }]
        \\entry const answer = @u32.add (@array.get values 0).x (@array.get values 1).x
    );
    defer f.deinit();
    try f.valid();
}

test "deferred fields and associated operators remain principal across distinct nominal uses" {
    var f = try Fixture.init(
        \\infixl 60 (+) = _fixity_add
        \\type Point is data = $Point {x:U32}
        \\type FloatPoint is data = $FloatPoint {x:F32}
        \\const Point.add = func left => return func right => return $Point {x: @u32.add left.x right.x}
        \\const coordinate = func point => return point.x
        \\const plus = func left => return func right => return left + right
        \\entry const integer = coordinate ($Point {x:42})
        \\entry const floating = coordinate ($FloatPoint {x:1.25})
        \\entry const aggregate = (plus ($Point {x:20}) ($Point {x:22})).x
        \\entry const scalar = plus 20 22
        \\const _fixity_add = func left => return func right => return @type.call "add" left right
    );
    defer f.deinit();
    try f.valid();
    var field_constraint = false;
    var dispatch_constraint = false;
    for (f.checked.obligations) |constraint| {
        field_constraint = field_constraint or constraint.kind == .field;
        dispatch_constraint = dispatch_constraint or constraint.kind == .dispatch;
        if (constraint.kind == .dispatch) {
            try std.testing.expect(constraint.result != 0 and constraint.other != 0);
            try std.testing.expectEqual(T.Operator.add, constraint.operator);
        }
    }
    try std.testing.expect(field_constraint and dispatch_constraint);
    try std.testing.expectEqual(@as(usize, 1), f.checked.associated.len);
    try std.testing.expectEqualStrings("add", f.pool.get(f.checked.associated[0].member));
}
test "authoritative binary primitive admits nominal evidence and rejects missing builtin providers" {
    for ([_]struct { source: []const u8, code: ?check.Code }{
        .{ .source = @import("fixtures").source("nominal/generic-fields-and-associated.blot"), .code = null },
        .{ .source = @import("fixtures").source("nominal/ordered-right-fallback.blot"), .code = null },
        .{ .source = @import("fixtures").source("nominal/left-result-conflict.blot"), .code = .type_mismatch },
        .{ .source = @import("fixtures").source("nominal/compiler-binary-type-call.blot"), .code = null },
    }) |case_| {
        var f = try Fixture.init(case_.source);
        defer f.deinit();
        if (case_.code) |code| {
            var found = false;
            for (f.checked.diagnostics) |diagnostic| found = found or diagnostic.code == code;
            try std.testing.expect(found);
        } else try f.valid();
    }
}
test "panic literals type check in unused functions without executing and preserve branch result" {
    var f = try Fixture.init(
        \\const unused = func (value:U32) : U32 => return @panic "unused trap"
        \\entry const answer = if true then 42 else @panic "dead branch"
    );
    defer f.deinit();
    try f.valid();
    var never: usize = 0;
    for (f.checked.expr_types) |ty| if (ty == T.never) {
        never += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), never);
}

fn nominalAllocationScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\type Point a is data = $Point {x:a}
        \\const Point.combine = func left => return func right => return $Point {x:@u32.add left.x right.x}
        \\const combine = func left => return func right => return @type.call "combine" left right
        \\const coordinate = func point => return point.x
        \\entry const answer = do:
        \\  let point = combine ($Point {x:20}) ($Point {x:21})
        \\  point.x := @u32.add self 1
        \\  break coordinate point
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
}
test "nominal catalogs deferred evidence and immutable field updates release every allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, nominalAllocationScenario, .{});
}

test "missing named dispatch remains an owned predicate in an unreachable typed function" {
    var f = try Fixture.init(
        \\const unused = func () : U32 => return @type.call "add" true false
        \\entry const answer = 42
    );
    defer f.deinit();
    try f.valid();
    var retained = false;
    for (f.checked.bindings[1..]) |binding| if (binding.kind == .global and std.mem.eql(u8, f.pool.get(binding.name), "unused")) {
        try std.testing.expectEqual(@as(u32, 1), binding.scheme.obligations.len);
        const predicate = f.checked.obligations[binding.scheme.obligations.start];
        try std.testing.expectEqual(T.ObligationKind.dispatch, predicate.kind);
        try std.testing.expectEqual(T.boolean, predicate.ty);
        try std.testing.expectEqual(T.boolean, predicate.other);
        try std.testing.expectEqual(T.u32_type, predicate.result);
        retained = true;
    };
    try std.testing.expect(retained);
}

const indexed_update_source =
    \\type Box is data = $Box {x:U32}
    \\entry const answer = func () => return do:
    \\  let values = #[$Box {x:20}, $Box {x:21}]
    \\  let original = values
    \\  values[@u32.sub (@array.length self) 1].x := @u32.add self 1
    \\  break @u32.add original[1].x values[1].x
;
test "mixed array record updates type selectors against root and RHS against old leaf" {
    var f = try Fixture.init(indexed_update_source);
    defer f.deinit();
    try f.valid();
    var found = false;
    for (f.tree.nodes.items, 0..) |node, raw_id| {
        if (node.tag != .rebind_stmt) continue;
        const id: u32 = @intCast(raw_id);
        const access = f.checked.types.list(f.checked.access_nodes[id]);
        const path = f.checked.types.list(f.checked.rebindings[id].path);
        const types = f.checked.types.list(f.checked.access_types[id]);
        try std.testing.expectEqual(@as(usize, 2), access.len);
        try std.testing.expectEqual(@as(usize, 3), types.len);
        try std.testing.expectEqual(@import("../parse/ast.zig").Tag.index_access, f.tree.node(access[0]).tag);
        try std.testing.expectEqual(@import("../parse/ast.zig").Tag.field_access, f.tree.node(access[1]).tag);
        try std.testing.expectEqual(@as(u32, 0), path[0]);
        try std.testing.expect(path[1] != 0);
        try std.testing.expectEqual(T.Tag.array, f.checked.types.node(types[0]).tag);
        try std.testing.expectEqual(T.Tag.nominal, f.checked.types.node(types[1]).tag);
        try std.testing.expectEqual(T.u32_type, types[2]);
        try std.testing.expectEqual(T.u32_type, f.checked.bindings[f.checked.rebindings[id].self_binding].ty);
        var root_self = false;
        var leaf_self = false;
        for (f.tree.nodes.items, 0..) |candidate, self_id| if (candidate.tag == .name and std.mem.eql(u8, f.pool.get(candidate.a), "self")) {
            root_self = root_self or f.checked.resolved[self_id] == f.checked.rebindings[id].root;
            leaf_self = leaf_self or f.checked.resolved[self_id] == f.checked.rebindings[id].self_binding;
        };
        try std.testing.expect(root_self and leaf_self);
        found = true;
    }
    try std.testing.expect(found);
}
fn indexedUpdateAllocationScenario(allocator: std.mem.Allocator) !void {
    var tokens = try lexer.lex(allocator, indexed_update_source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, indexed_update_source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
}
test "mixed immutable updates release path metadata at every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, indexedUpdateAllocationScenario, .{});
}

const generic_indexed_field_source =
    \\type Mode is data = $Play | $Edit
    \\type Editor is data = $Editor {mode: Mode}
    \\const set_mode = func access => return do:
    \\  access.editor[0].mode := $Edit
    \\entry const answer = func (): U32 => return do:
    \\  let editor: Array Editor = #[$Editor {mode: $Play}]
    \\  set_mode {editor}
    \\  return case editor[0].mode of
    \\    $Edit => 1
    \\    $Play => 0
;

test "indexed field invariance rejects incompatible writes while ordinary rebinding changes types" {
    var invalid = try Fixture.init(
        \\type Mode is data = $Play | $Edit
        \\type Editor is data = $Editor {mode: Mode}
        \\const invalid = func access => return do:
        \\  access.editor[0].mode := 7
        \\entry const answer = func (): U32 => return do:
        \\  let editor: Array Editor = #[$Editor {mode: $Play}]
        \\  invalid {editor}
        \\  return 0
    );
    defer invalid.deinit();
    var mismatch = false;
    for (invalid.checked.diagnostics) |diagnostic| if (diagnostic.code == .type_mismatch) {
        mismatch = true;
    };
    try std.testing.expect(mismatch);
    var ordinary = try Fixture.init(
        \\const replace = func record => return do:
        \\  record.value := true
        \\  return record
        \\entry const answer = func (): Bool => return (replace {value: 7}).value
    );
    defer ordinary.deinit();
    try ordinary.valid();
}

test "multiple indexed boundaries retain each selected element equation in source Core" {
    const source =
        \\type Mode is data = $Play | $Edit
        \\type Editor is data = $Editor {mode: Mode}
        \\type Group is data = $Group {editors: Array Editor}
        \\const set_mode = func access => return do:
        \\  access.groups[0].editors[0].mode := $Edit
        \\const apply = func (groups: Array Group) => return set_mode {groups}
    ;
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    try fixture.valid();
    var module = try @import("core.zig").lower(a, &fixture.tree, &fixture.pool, &fixture.checked);
    defer module.deinit(a);
    module.unit = 1;
    const units = [_]*const @import("core.zig").Module{&module};
    var remaining: usize = 1_000_000;
    for (module.bodies) |body| {
        if (module.binding(body.binding).kind != .global) continue;
        try @import("package_core.zig").checkedInterfaceBody(&module, body.binding, .{ .units = &units }, &remaining, a);
    }
    // Nested owners are checked as source equations here; this law does not
    // ask the emitter to admit nested owning arrays into inline storage.
    const incompatible = try std.mem.replaceOwned(u8, a, source, ":= $Edit", ":= 7");
    defer a.free(incompatible);
    var invalid = try Fixture.init(incompatible);
    defer invalid.deinit();
    var mismatch = false;
    for (invalid.checked.diagnostics) |diagnostic| if (diagnostic.code == .type_mismatch) {
        mismatch = true;
    };
    try std.testing.expect(mismatch);
}
