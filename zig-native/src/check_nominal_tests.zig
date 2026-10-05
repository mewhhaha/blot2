const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const T = @import("types.zig");
const a = std.testing.allocator;
const Fixture = struct {
    pool: symbols.Pool = .{},
    tree: @import("ast.zig").Tree,
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
    \\type Vec2 is data = #Vec2 { x: F32, y: F32 }
    \\const sum = fn point => do:
    \\  let #Vec2 { x, y } = point
    \\  return x + y
    \\const origin = #Vec2 { y: 2.0, x: 20.0 }
    \\entry const answer = fn () -> F32 => sum origin
    \\entry const projected = fn () -> F32 => origin.x
    \\entry const tuple = fn () -> U32 => @product.get (20, 22) 1
    \\const _fixity_add = fn left => fn right => @type.call "add" left right
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
        \\type Box a is data = #Box a
        \\type Pair [left, right] is data = #Pair (left, right)
        \\const unbox = fn box => do:
        \\  let #Box value = box
        \\  return value
        \\const first = fn (pair: Pair [U32, a]) => do:
        \\  let #Pair (value, _) = pair
        \\  return value
        \\entry const integer = fn () => unbox (#Box 42)
        \\entry const floating = fn () => unbox (#Box 1.25)
        \\entry const paired = fn () => first (#Pair (42, #True))
    );
    defer f.deinit();
    try f.valid();
    try std.testing.expectEqual(@as(u32, 1), f.checked.nominals[2].parameters.len);
    try std.testing.expectEqual(@as(u32, 2), f.checked.nominals[2].variables.len);
}
test "record constructor diagnostics retain duplicate missing and wrong nominal identity" {
    for ([_]struct { source: []const u8, code: check.Code }{
        .{ .source = "type P is data = #P {x:U32,y:U32}\nentry const x=#P {x:1,x:2,y:3}\n", .code = .duplicate_record_field },
        .{ .source = "type P is data = #P {x:U32,y:U32}\nentry const x=#P {x:1}\n", .code = .missing_record_field },
        .{ .source = "type P is data = #P U32\ntype Q is data = #Q U32\nentry const x:P=#Q 1\n", .code = .type_mismatch },
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
        \\type Box is data = #Box { x: U32 }
        \\const values = #[#Box { x: 40 }, #Box { x: 2 }]
        \\entry const answer = @u32.add (@array.get values 0).x (@array.get values 1).x
    );
    defer f.deinit();
    try f.valid();
}

test "deferred fields and associated operators remain principal across distinct nominal uses" {
    var f = try Fixture.init(
        \\infixl 60 (+) = _fixity_add
        \\type Point is data = #Point {x:U32}
        \\type FloatPoint is data = #FloatPoint {x:F32}
        \\const Point.add = fn left => fn right => #Point {x: @u32.add left.x right.x}
        \\const coordinate = fn point => point.x
        \\const plus = fn left => fn right => left + right
        \\entry const integer = coordinate (#Point {x:42})
        \\entry const floating = coordinate (#FloatPoint {x:1.25})
        \\entry const aggregate = (plus (#Point {x:20}) (#Point {x:22})).x
        \\entry const scalar = plus 20 22
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
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
test "associated binary admission checks ordered operands and does not backtrack on chosen result" {
    var admitted = try Fixture.init(
        \\infixl 60 (+) = _fixity_add
        \\type Left is data = #Left U32
        \\type Right is data = #Right U32
        \\const Left.add = fn (left:Left) => fn (right:Left) => 1
        \\const Right.add = fn (left:Left) => fn (right:Right) => 42
        \\entry const answer = #Left 1 + #Right 2
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    );
    defer admitted.deinit();
    try admitted.valid();
    // Operator syntax calls the ordinary fixity function. Verify the selected
    // implementation through evaluation, after preserving principal evidence.
    var lowered = try @import("core.zig").lower(a, &admitted.tree, &admitted.pool, &admitted.checked);
    defer lowered.deinit(a);
    lowered.unit = 1;
    var session = try @import("core_eval.zig").Session.init(a, &.{lowered});
    defer session.deinit();
    var selected = false;
    for (admitted.checked.bindings, 0..) |binding, id| {
        if (binding.kind == .global and std.mem.eql(u8, admitted.pool.get(binding.name), "answer")) {
            try std.testing.expectEqual(@as(u32, 42), (try session.value(.{ .unit = 1, .binding = @intCast(id) })).bits);
            selected = true;
        }
    }
    try std.testing.expect(selected);
    var rejected = try Fixture.init(
        \\infixl 60 (+) = _fixity_add
        \\type Left is data = #Left U32
        \\type Right is data = #Right U32
        \\const Left.add = fn (left:Left) => fn (right:Right) => 1
        \\const Right.add = fn (left:Left) => fn (right:Right) => 42.0
        \\entry const answer:F32 = #Left 1 + #Right 2
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    );
    defer rejected.deinit();
    var mismatch = false;
    for (rejected.checked.diagnostics) |diagnostic| mismatch = mismatch or diagnostic.code == .type_mismatch;
    try std.testing.expect(mismatch);
}

test "authoritative binary primitive admits nominal evidence and rejects missing builtin providers" {
    for ([_]struct { source: []const u8, code: ?check.Code }{
        .{ .source = @embedFile("fixtures/nominal/generic-fields-and-associated.blot"), .code = null },
        .{ .source = @embedFile("fixtures/nominal/ordered-right-fallback.blot"), .code = null },
        .{ .source = @embedFile("fixtures/nominal/left-result-conflict.blot"), .code = .type_mismatch },
        .{ .source = @embedFile("fixtures/nominal/compiler-binary-type-call.blot"), .code = null },
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
        \\const unused = fn (value:U32) -> U32 => @panic "unused trap"
        \\entry const answer = if #True then 42 else @panic "dead branch"
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
        \\type Point a is data = #Point {x:a}
        \\const Point.combine = fn left => fn right => #Point {x:@u32.add left.x right.x}
        \\const combine = fn left => fn right => @type.call "combine" left right
        \\const coordinate = fn point => point.x
        \\entry const answer = do:
        \\  let point = combine (#Point {x:20}) (#Point {x:21})
        \\  point.x := @u32.add self 1
        \\  return coordinate point
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, nominalAllocationScenario, .{});
}

test "latent staged callback intermediates are fresh per scalar evidence use" {
    // This fixture declares the ordinary scalar methods normally imported
    // from std/prelude, so admit it as a prelude catalog producer.
    var f = try Fixture.initWithOptions(
        \\infixl 60 (+) = _fixity_add
        \\const U32.add = fn left => fn right => @u32.add left right
        \\const F32.add = fn left => fn right => @f32.add left right
        \\type Builder callback is data = #Builder {run:callback}
        \\const add_step = fn amount => fn builder => do:
        \\  let #Builder {run:previous} = builder
        \\  return #Builder {run:fn value => previous value + amount}
        \\const make = fn amount => do:
        \\  let builder = #Builder {run:fn value => value}
        \\  builder := add_step amount self
        \\  builder := add_step amount self
        \\  return builder
        \\entry const integer = fn () => do:
        \\  let #Builder {run} = make 10
        \\  return run 22
        \\entry const floating = fn () => do:
        \\  let #Builder {run} = make 1.5
        \\  return run 39.0
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
        \\entry const integer_result: U32 = integer ()
        \\entry const floating_result: F32 = floating ()
    , .{ .builtin_catalog = true });
    defer f.deinit();
    try f.valid();
    var found: usize = 0;
    for (f.checked.bindings[1..]) |binding| {
        if (binding.kind != .global) continue;
        const name = f.pool.get(binding.name);
        if (std.mem.eql(u8, name, "integer") or std.mem.eql(u8, name, "floating")) {
            // Principal callback results may retain deferred dispatch evidence.
            // Concrete scalar results are checked at their instantiated uses below.
            try std.testing.expectEqual(T.Tag.function, f.checked.types.node(binding.scheme.root).tag);
            found += 1;
        }
        const quantified = f.checked.types.list(binding.scheme.variables);
        // No private predicate variable may escape a principal scheme. Such
        // variables connect closure inputs to final outputs without appearing
        // directly in the published callback signature.
        for (f.checked.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len]) |constraint| {
            for ([_]T.Id{ constraint.ty, constraint.other, constraint.result }) |part| {
                if (part == 0) continue;
                const free = try f.checked.types.freeVariables(part);
                defer a.free(free);
                for (free) |variable| {
                    var present = false;
                    for (quantified) |candidate| present = present or candidate == variable;
                    try std.testing.expect(present);
                }
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 2), found);
    var lowered = try @import("core.zig").lower(a, &f.tree, &f.pool, &f.checked);
    defer lowered.deinit(a);
    lowered.unit = 1;
    var session = try @import("core_eval.zig").Session.init(a, &.{lowered});
    defer session.deinit();
    var results: usize = 0;
    for (f.checked.bindings, 0..) |binding, id| {
        if (binding.kind != .global) continue;
        const name = f.pool.get(binding.name);
        if (std.mem.eql(u8, name, "integer_result")) {
            const result = try session.value(.{ .unit = 1, .binding = @intCast(id) });
            try std.testing.expectEqual(.u32, result.scalar);
            try std.testing.expectEqual(@as(u32, 42), result.bits);
            results += 1;
        } else if (std.mem.eql(u8, name, "floating_result")) {
            const result = try session.value(.{ .unit = 1, .binding = @intCast(id) });
            try std.testing.expectEqual(.f32, result.scalar);
            try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 42))), result.bits);
            results += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), results);
}
test "missing named dispatch remains an owned predicate in an unreachable typed function" {
    var f = try Fixture.init(
        \\const unused = fn () -> U32 => @type.call "add" #True #False
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
    \\type Box is data = #Box {x:U32}
    \\entry const answer = fn () => do:
    \\  let values = #[#Box {x:20}, #Box {x:21}]
    \\  let original = values
    \\  values[@u32.sub (@array.length self) 1].x := @u32.add self 1
    \\  return @u32.add original[1].x values[1].x
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
        try std.testing.expectEqual(@import("ast.zig").Tag.index_access, f.tree.node(access[0]).tag);
        try std.testing.expectEqual(@import("ast.zig").Tag.field_access, f.tree.node(access[1]).tag);
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, indexedUpdateAllocationScenario, .{});
}
