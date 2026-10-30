const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("check.zig");
const T = @import("types.zig");
const a = std.testing.allocator;

fn interfaceImport(allocator: std.mem.Allocator) !void {
    const text = "entry const first = earlier\nentry const second = later\n";
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var source1 = try T.Store.init(allocator);
    defer source1.deinit();
    var source2 = try T.Store.init(allocator);
    defer source2.deinit();
    const label1 = try source1.internOperation(.{ .unit = 10, .decl = 7 }, &.{T.u32_type});
    const label2 = try source2.internOperation(.{ .unit = 20, .decl = 7 }, &.{T.f32_type});
    try std.testing.expectEqual(label1, label2); // producer-local IDs deliberately collide
    const raw_tail = try source1.freshEffects();
    const raw_one = try source1.functionWithEffects(T.unit, T.u32_type, try source1.effects.row(&.{ label1, label1 }, source1.row(raw_tail).tail));
    const certificate = try source1.closeCovariantCertified(raw_one, &.{source1.row(raw_tail).tail.variable}, &.{});
    const one = certificate.root;
    const two = try source2.functionWithEffects(T.unit, T.f32_type, try source2.effects.row(&.{label2}, .closed));
    var checked = try check.checkWithImports(allocator, &tree, &pool, &.{
        .{ .name = pool.lookup("earlier").?, .target = .{ .unit = 10, .binding = 1 }, .origin = 0, .interface = .{ .types = .{ .store = &source1 }, .scheme = .{ .root = one, .closed_rows = certificate.closed_rows }, .obligations = &.{} } },
        .{ .name = pool.lookup("later").?, .target = .{ .unit = 20, .binding = 1 }, .origin = 0, .interface = .{ .types = .{ .store = &source2 }, .scheme = .{ .root = two }, .obligations = &.{} } },
    });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const first = checked.types.node(checked.bindings[1].ty);
    const second = checked.types.node(checked.bindings[2].ty);
    const first_labels = checked.types.effects.list(checked.types.effects.node(first.c).labels);
    const second_labels = checked.types.effects.list(checked.types.effects.node(second.c).labels);
    try std.testing.expectEqual(@as(usize, 2), first_labels.len);
    try std.testing.expectEqual(first_labels[0], first_labels[1]);
    try std.testing.expect(first_labels[0] != second_labels[0]);
    try std.testing.expectEqual(@as(u32, 10), checked.types.operations.items[first_labels[0]].identity.unit);
    try std.testing.expectEqual(@as(u32, 20), checked.types.operations.items[second_labels[0]].identity.unit);
    try std.testing.expectEqualSlices(T.Id, &.{T.u32_type}, checked.types.list(checked.types.operations.items[first_labels[0]].arguments));
    try std.testing.expectEqualSlices(T.Id, &.{T.f32_type}, checked.types.list(checked.types.operations.items[second_labels[0]].arguments));
    var imported_certificate: ?u32 = null;
    for (checked.bindings) |binding| if (binding.external) |external| if (external.unit == 10) {
        try std.testing.expectEqual(@as(u32, 1), binding.scheme.closed_rows.len);
        imported_certificate = checked.types.list(binding.scheme.closed_rows)[0];
    };
    try std.testing.expect(imported_certificate != null);
    try std.testing.expect(imported_certificate.? < checked.types.effects.variables.items.len);
}
test "foreign interfaces remap colliding operation IDs and preserve exact family arguments and multiplicity" {
    try interfaceImport(a);
}
test "foreign operation and row interface imports release every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, interfaceImport, .{});
}
test "a closed pure annotation rejects an imported effectful function with effect_mismatch" {
    const text = "entry const answer: Unit -> U32 = source\n";
    var tokens = try lexer.lex(a, text);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var producer = try T.Store.init(a);
    defer producer.deinit();
    const label = try producer.internOperation(.{ .unit = 2, .decl = 7 }, &.{});
    const signature = try producer.functionWithEffects(T.unit, T.u32_type, try producer.effects.row(&.{label}, .closed));
    var checked = try check.checkWithImports(a, &tree, &pool, &.{.{
        .name = pool.lookup("source").?,
        .target = .{ .unit = 2, .binding = 1 },
        .origin = 0,
        .interface = .{ .types = .{ .store = &producer }, .scheme = .{ .root = signature }, .obligations = &.{} },
    }});
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
    try std.testing.expectEqual(check.Code.effect_mismatch, checked.diagnostics[0].code);
}
test "imported value and row quantifiers are copied once then freshened independently at each use" {
    const text = "entry const first = identity 42\nentry const second = identity 1.25\n";
    var tokens = try lexer.lex(a, text);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var source = try T.Store.init(a);
    defer source.deinit();
    const ty = try source.fresh();
    const row = try source.freshEffects();
    const function = try source.functionWithEffects(ty, ty, row);
    var checked = try check.checkWithImports(a, &tree, &pool, &.{.{ .name = pool.lookup("identity").?, .target = .{ .unit = 2, .binding = 1 }, .origin = 0, .interface = .{ .types = .{ .store = &source }, .scheme = .{ .root = function, .variables = try source.saveList(&.{ty}), .row_variables = try source.saveList(&.{source.effects.node(row).tail.variable}) }, .obligations = &.{} } }});
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(u64, 1), checked.imported_schemes);
    for (checked.bindings) |binding| {
        if (binding.name == pool.lookup("first").?) try std.testing.expectEqual(T.u32_type, binding.ty);
        if (binding.name == pool.lookup("second").?) try std.testing.expectEqual(T.f32_type, binding.ty);
    }
    try std.testing.expectEqual(@as(usize, 0), source.versions.items.len);
    try std.testing.expectEqual(@as(usize, 0), source.effects.versions.items.len);
    for (checked.bindings) |binding| if (binding.kind == .external) {
        try std.testing.expectEqual(@as(u32, 1), binding.scheme.row_variables.len);
    };
}
fn retainedCertificates(allocator: std.mem.Allocator) !void {
    const text = "const alias = source\nentry const answer = func () => return do:\n  let local = source\n  break 42\n";
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var producer = try T.Store.init(allocator);
    defer producer.deinit();
    const latent = try producer.freshEffects();
    const signature = try producer.functionWithEffects(T.unit, T.u32_type, latent);
    const quantifiers = try producer.saveList(&.{producer.row(latent).tail.variable});
    var checked = try check.checkWithImports(allocator, &tree, &pool, &.{.{
        .name = pool.lookup("source").?,
        .target = .{ .unit = 2, .binding = 1 },
        .origin = 0,
        .interface = .{ .types = .{ .store = &producer }, .scheme = .{ .root = signature, .row_variables = quantifiers }, .obligations = &.{} },
    }});
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 3), checked.body_closed_rows.len);
    var alias: check.BindingId = 0;
    var answer: check.BindingId = 0;
    var local: check.BindingId = 0;
    for (checked.bindings, 0..) |binding, index| {
        if (binding.name == pool.lookup("alias").?) alias = @intCast(index);
        if (binding.name == pool.lookup("answer").?) answer = @intCast(index);
        if (binding.name == pool.lookup("local").?) local = @intCast(index);
    }
    try std.testing.expect(alias != 0 and answer != 0 and local != 0);
    for ([_]check.BindingId{ alias, local }) |binding| {
        const definition = checked.bindings[binding];
        try std.testing.expectEqual(@as(u32, 1), definition.scheme.closed_rows.len);
        try std.testing.expectEqual(@as(u32, 0), definition.scheme.row_variables.len);
        try std.testing.expectEqual(T.Effects.Tail.closed, checked.types.row(checked.types.node(definition.scheme.root).c).tail);
        const raw_tail = checked.types.row(checked.types.node(definition.ty).c).tail;
        try std.testing.expect(raw_tail == .variable);
        try std.testing.expectEqual(raw_tail.variable, checked.types.list(definition.scheme.closed_rows)[0]);
        try std.testing.expect(checked.types.effects.replacementAt(raw_tail.variable, 0) == null);
        var found = false;
        for (checked.body_closed_rows) |decision| if (decision.owner == (if (binding == alias) alias else answer) and decision.variable == raw_tail.variable) {
            found = true;
        };
        try std.testing.expect(found);
    }
    var anonymous_certificates: u32 = 0;
    for (checked.lambda_closed_rows) |list| anonymous_certificates += list.len;
    try std.testing.expectEqual(@as(u32, 1), anonymous_certificates);
}
test "global and local row closing retain exact raw body certificates without solver mutation" {
    try retainedCertificates(a);
}
test "retained row certificate publication releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, retainedCertificates, .{});
}
fn ambientReadScenario(allocator: std.mem.Allocator) !void {
    const text =
        \\const ignore = func ~value => return 42
        \\const force = func ~value => return @force value
        \\entry const ignored = ignore (read ())
        \\entry const forced = func () => return force (read ())
    ;
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var producer = try T.Store.init(allocator);
    defer producer.deinit();
    const identity: T.NominalIdentity = .{ .unit = 2, .decl = 7 };
    const label = try producer.internOperation(identity, &.{});
    const signature = try producer.functionWithEffects(T.unit, T.u32_type, try producer.effects.row(&.{label}, .closed));
    var checked = try check.checkWithImports(allocator, &tree, &pool, &.{.{ .name = pool.lookup("read").?, .target = .{ .unit = 2, .binding = 1 }, .origin = 0, .interface = .{ .types = .{ .store = &producer }, .scheme = .{ .root = signature }, .obligations = &.{} } }});
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var verified: usize = 0;
    for (checked.bindings) |binding| {
        if (binding.name == pool.lookup("ignored").?) {
            try std.testing.expectEqual(T.u32_type, binding.ty);
            verified += 1;
        }
        if (binding.name == pool.lookup("forced").?) {
            const function = checked.types.node(binding.scheme.root);
            try std.testing.expectEqual(T.Tag.function, function.tag);
            const labels = checked.types.rowLabels(function.c);
            try std.testing.expectEqual(@as(usize, 1), labels.len);
            try std.testing.expectEqualDeep(identity, checked.types.operation(labels[0]).identity);
            try std.testing.expectEqual(T.Effects.Tail.closed, checked.types.row(function.c).tail);
            verified += 1;
        }
        if (binding.name == pool.lookup("force").?) {
            const function = checked.types.node(binding.scheme.root);
            const argument = checked.types.node(function.a);
            try std.testing.expectEqual(T.Tag.demand, argument.tag);
            try std.testing.expectEqualDeep(checked.types.row(argument.c).tail, checked.types.row(function.c).tail);
            try std.testing.expectEqual(@as(u32, 1), binding.scheme.row_variables.len);
            verified += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 3), verified);
}
test "ordinary ambient rows preserve forced demand effects while ignored demand effects stay latent" {
    try ambientReadScenario(a);
}
test "ambient and demanded row inference releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, ambientReadScenario, .{});
}
test "pure initializer and callback constraints retain their distinct effect diagnostics" {
    const cases = [_]struct { source: []const u8, code: check.Code }{
        .{ .source = "entry const answer = read ()\n", .code = .const_effect },
        .{ .source = "entry const answer = func () => return do:\n  let value = read ()\n  break value\n", .code = .let_effect },
        .{ .source = "const run = func (callback:Unit -> U32) => return callback ()\nentry const answer = func () => return run read\n", .code = .effect_mismatch },
    };
    for (cases) |fixture| {
        var tokens = try lexer.lex(a, fixture.source);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, fixture.source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        var producer = try T.Store.init(a);
        defer producer.deinit();
        const label = try producer.internOperation(.{ .unit = 2, .decl = 7 }, &.{});
        const signature = try producer.functionWithEffects(T.unit, T.u32_type, try producer.effects.row(&.{label}, .closed));
        var checked = try check.checkWithImports(a, &tree, &pool, &.{.{ .name = pool.lookup("read").?, .target = .{ .unit = 2, .binding = 1 }, .origin = 0, .interface = .{ .types = .{ .store = &producer }, .scheme = .{ .root = signature }, .obligations = &.{} } }});
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
        try std.testing.expectEqual(fixture.code, checked.diagnostics[0].code);
    }
}
test "anonymous pure witnesses get exact certificates while callback connected lambdas stay open" {
    const text =
        \\type Phantom a is data = #Phantom
        \\const same = func left => return func right => return @type.same left right
        \\const invoke = func callback => return callback ()
        \\entry const answer = same (func () : Phantom U32 => return #Phantom) (func () : Phantom F32 => return #Phantom)
    ;
    var tokens = try lexer.lex(a, text);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var witnesses: usize = 0;
    for (tree.nodes.items, 0..) |node, index| if (node.tag == .lambda and node.c != 0) {
        const certificate = checked.lambda_closed_rows[index];
        try std.testing.expectEqual(@as(u32, 1), certificate.len);
        const raw = checked.types.node(checked.expr_types[index]);
        const raw_tail = checked.types.row(raw.c).tail;
        try std.testing.expect(raw_tail == .variable);
        try std.testing.expectEqual(raw_tail.variable, checked.types.list(certificate)[0]);
        witnesses += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), witnesses);
    for (checked.bindings) |binding| if (binding.kind == .global and binding.name == pool.lookup("invoke").?) {
        const declaration = tree.valueDecl(binding.declaration);
        try std.testing.expectEqual(@as(u32, 0), checked.lambda_closed_rows[declaration.body].len);
        const function = checked.types.node(binding.scheme.root);
        const parameter = checked.types.node(function.a);
        try std.testing.expectEqual(T.Tag.function, parameter.tag);
        try std.testing.expectEqualDeep(checked.types.row(parameter.c).tail, checked.types.row(function.c).tail);
    };
}
test "immediate binary unary and result associated selections publish their actual invocation rows" {
    const text =
        \\infixl 60 (+) = _fixity_add
        \\type N is data = #N U32
        \\const N.add = func left => return func right => return read ()
        \\const N.get = func value => return read ()
        \\const N.make = func () => return #N (read ())
        \\entry const binary = func () => return #N 1 + #N 2
        \\entry const unary = func () => return (#N 1).get
        \\entry const result = func () : N => return @type.result "make" ()
        \\const _fixity_add = func left => return func right => return @type.call "add" left right
    ;
    var tokens = try lexer.lex(a, text);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var producer = try T.Store.init(a);
    defer producer.deinit();
    const identity: T.NominalIdentity = .{ .unit = 2, .decl = 7 };
    const label = try producer.internOperation(identity, &.{});
    const signature = try producer.functionWithEffects(T.unit, T.u32_type, try producer.effects.row(&.{label}, .closed));
    var checked = try check.checkWithImports(a, &tree, &pool, &.{.{ .name = pool.lookup("read").?, .target = .{ .unit = 2, .binding = 1 }, .origin = 0, .interface = .{ .types = .{ .store = &producer }, .scheme = .{ .root = signature }, .obligations = &.{} } }});
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var count: usize = 0;
    for (checked.dispatch_signatures) |call| if (call != 0) {
        const function = checked.types.node(call);
        try std.testing.expectEqual(T.Tag.function, function.tag);
        const labels = checked.types.rowLabels(function.c);
        try std.testing.expectEqual(@as(usize, 1), labels.len);
        try std.testing.expectEqualDeep(identity, checked.types.operation(labels[0]).identity);
        count += 1;
    };
    try std.testing.expectEqual(@as(usize, 3), count);
}

fn declarationCatalogs(allocator: std.mem.Allocator) !void {
    const text =
        \\type Read [left,right] is effect = { pair: (left,right) -> left, write: right -> Unit }
        \\effect Counter: Unit -> U32
    ;
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 3), checked.effect_families.len);
    try std.testing.expectEqual(@as(usize, 4), checked.effect_templates.len);
    const family = checked.effect_families[1];
    try std.testing.expectEqual(@as(u32, 1), family.parameters.len);
    try std.testing.expectEqual(@as(u32, 2), family.variables.len);
    const operations = checked.types.list(family.operations);
    try std.testing.expectEqual(@as(usize, 2), operations.len);
    const pair = checked.effect_templates[operations[0]];
    const write = checked.effect_templates[operations[1]];
    try std.testing.expectEqual(family.identity.unit, pair.identity.unit);
    try std.testing.expect(pair.identity.decl != write.identity.decl);
    const shaped = checked.types.node(pair.parameter);
    try std.testing.expectEqual(T.Tag.product, shaped.tag);
    const parts = checked.types.list(.{ .start = shaped.a, .len = shaped.b });
    try std.testing.expectEqual(pair.result, parts[0]);
    try std.testing.expectEqual(write.parameter, parts[1]);
    try std.testing.expectEqual(T.unit, write.result);
    try std.testing.expectEqual(T.unit, checked.effect_templates[3].parameter);
    try std.testing.expectEqual(T.u32_type, checked.effect_templates[3].result);
}
test "source effect declaration catalogs preserve shaped binders and exact operation origins" {
    try declarationCatalogs(a);
}
test "source effect family catalogs release every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, declarationCatalogs, .{});
}

fn sourceOperationValues(allocator: std.mem.Allocator) !void {
    const text =
        \\effect Counter: Unit -> U32
        \\type Reader a is effect = { ask: Unit -> a }
        \\type PairRead [left,right] is effect = { first: Unit -> left }
        \\type Phantom a is data = #Phantom
        \\const counter = Counter
        \\const ask = Reader.ask
        \\const read = func () : U32 => return ask ()
        \\const explicit = Reader.ask U32
        \\const shaped = PairRead.first [U32,F32]
        \\const phantom_u32 = Reader.ask (Phantom U32)
        \\const phantom_f32 = Reader.ask (Phantom F32)
        \\const driver = func () => return do:
        \\  let local = Reader.ask
        \\  use value <- local ()
        \\  break @u32.add value 1
    ;
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 8), checked.body_elaborations);
    try std.testing.expectEqual(@as(usize, 7), checked.operation_uses.len);
    var phantom_labels: [2]u32 = undefined;
    var phantom_count: usize = 0;
    var inferred_count: usize = 0;
    for (checked.operation_uses, 0..) |use, index| {
        try std.testing.expectEqual(@as(u32, @intCast(index + 1)), checked.operation_refs[use.node]);
        const signature = checked.types.node(use.signature);
        try std.testing.expectEqual(T.Tag.function, signature.tag);
        const arguments = checked.types.list(use.arguments);
        const labels = checked.types.rowLabels(signature.c);
        if (labels.len == 0) {
            inferred_count += 1;
            try std.testing.expectEqual(T.Effects.Tail.variable, std.meta.activeTag(checked.types.row(signature.c).tail));
        } else {
            try std.testing.expectEqual(@as(usize, 1), labels.len);
            try std.testing.expectEqualDeep(checked.effect_templates[use.template].identity, checked.types.operation(labels[0]).identity);
            if (arguments.len == 1 and checked.types.node(arguments[0]).tag == .nominal) {
                phantom_labels[phantom_count] = labels[0];
                phantom_count += 1;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 2), inferred_count);
    try std.testing.expectEqual(@as(usize, 2), phantom_count);
    try std.testing.expect(phantom_labels[0] != phantom_labels[1]);
    var reflected_principal_seen = false;
    for (checked.bindings) |binding| if (binding.name == pool.lookup("read").? and binding.kind == .global) {
        const function = checked.types.node(binding.scheme.root);
        try std.testing.expectEqual(T.u32_type, function.b);
        try std.testing.expect(checked.types.row(function.c).tail == .variable);
        try std.testing.expect(binding.scheme.obligations.len != 0);
        for (checked.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len]) |predicate| {
            if (predicate.kind != .effect_operation) continue;
            reflected_principal_seen = true;
            try std.testing.expectEqual(T.Tag.function, checked.types.node(predicate.signature).tag);
        }
    };
    try std.testing.expect(reflected_principal_seen);
}
test "declared operation values retain generic aliases shaped arguments and exact phantom identities" {
    try sourceOperationValues(a);
}
test "source operation selection and latent predicate publication release every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, sourceOperationValues, .{});
}
test "operation invocations preserve pure initializer annotation and sealed label diagnostics" {
    const cases = [_]struct { source: []const u8, code: check.Code }{
        .{ .source = "effect Read:Unit -> U32\nconst invalid=Read ()\n", .code = .const_effect },
        .{ .source = "effect Read:Unit -> U32\nconst invalid=func () => return do:\n  let value=Read ()\n  break value\n", .code = .let_effect },
        .{ .source = "effect Read:Unit -> U32\nconst invalid:Unit -> U32=func () => return Read ()\n", .code = .effect_mismatch },
        .{ .source = "effect Foreign:Unit -> U32\n", .code = .sealed_effect },
        .{ .source = "effect Read:Unit -> U32\nconst Read=func () => return 42\n", .code = .duplicate_name },
    };
    for (cases) |item| {
        var tokens = try lexer.lex(a, item.source);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, item.source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        var checked = try check.check(a, &tree, &pool);
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
        try std.testing.expectEqual(item.code, checked.diagnostics[0].code);
    }
}

fn providerSource(allocator: std.mem.Allocator) !void {
    const text =
        \\effect Read:Unit -> U32
        \\const provider = @effect.provider Read (func () => return 42)
        \\const read = func () => return Read ()
        \\const invoke = func callback => return callback ()
        \\const force = func ~value => return @force value
        \\const ignore = func ~value => return 42
        \\entry const direct = func () => return do provider:
        \\  break read ()
        \\entry const callback = func () => return do provider:
        \\  break invoke (func () => return Read ())
        \\entry const delayed = func () => return do provider:
        \\  break force (Read ())
        \\entry const ignored = func () => return ignore (Read ())
        \\type State a is effect = { get:Unit -> a, set:a -> Unit }
        \\const state_provider = @effect.state (State.get (Array U32)) (State.set (Array U32)) #[41]
        \\entry const stateful = func () => return do state_provider:
        \\  use old <- State.get (Array U32) ()
        \\  let next = @array.set old 0 42
        \\  use State.set (Array U32) next
        \\  break old
    ;
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 4), checked.provider_blocks.len);
    for (checked.provider_blocks, 0..) |block, index| {
        try std.testing.expectEqual(@as(u32, @intCast(index + 1)), checked.provider_block_ids[block.node]);
        const provider_ = checked.types.node(checked.expr_types[block.provider]);
        try std.testing.expect(provider_.tag == .provider or provider_.tag == .state_provider);
        try std.testing.expectEqual(@as(usize, 0), checked.types.rowLabels(block.outer_effects).len);
        const outer_tail = checked.types.row(block.outer_effects).tail;
        try std.testing.expectEqualDeep(outer_tail, checked.types.row(block.body_effects).tail);
        if (outer_tail == .variable) {
            // The principal entry closes this tail through its exact body
            // certificate; the raw block keeps the same outer row relationship.
            var certified = false;
            for (checked.body_closed_rows) |decision| certified = certified or decision.variable == outer_tail.variable;
            try std.testing.expect(certified);
        }
        try std.testing.expectEqual(@as(usize, if (provider_.tag == .provider) 1 else 2), checked.types.rowLabels(block.body_effects).len);
        if (provider_.tag == .provider) {
            try std.testing.expectEqual(T.u32_type, block.body_result);
            try std.testing.expectEqual(T.u32_type, block.result);
        } else {
            try std.testing.expectEqual(T.Tag.array, checked.types.node(block.body_result).tag);
            const product = checked.types.node(block.result);
            try std.testing.expectEqual(T.Tag.product, product.tag);
            try std.testing.expectEqual(@as(u32, 2), product.b);
            const parts = checked.types.list(.{ .start = product.a, .len = product.b });
            for (parts) |part| try std.testing.expectEqual(T.Tag.array, checked.types.node(part).tag);
        }
    }
}
test "ordinary providers and State blocks retain exact ambient rows and separate public results" {
    try providerSource(a);
}
test "provider constructors blocks and latent demand captures release every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, providerSource, .{});
}
test "provider primitive targets arity sealed labels and signatures match source restrictions" {
    const cases = [_]struct { source: []const u8, code: check.Code }{
        .{ .source = "effect Read:Unit -> U32\nconst alias=Read\nconst invalid=@effect.provider alias (func () => return 42)\n", .code = .operation_target },
        .{ .source = "type Read a is effect = { get:Unit -> a }\nconst invalid=@effect.provider Read.get (func () => return 42)\n", .code = .operation_target },
        .{ .source = "effect Read:Unit -> U32\nconst invalid=@effect.provider Read (func () => return true)\n", .code = .type_mismatch },
        .{ .source = "const invalid=@effect.provider Foreign (func () => return 42)\n", .code = .sealed_effect },
        .{ .source = "effect Read:Unit -> U32\nconst invalid=@effect.state Read Read 42\n", .code = .invalid_state_provider },
        .{ .source = "effect Read:Unit -> U32\nconst invalid=@effect.provider Read\n", .code = .call_arity },
        .{ .source = "effect Read:Unit -> U32\nconst invalid=@effect.provider\n", .code = .call_arity },
    };
    for (cases) |item| {
        var tokens = try lexer.lex(a, item.source);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, item.source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        var checked = try check.check(a, &tree, &pool);
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
        try std.testing.expectEqual(item.code, checked.diagnostics[0].code);
    }
}

fn importedCatalogs(allocator: std.mem.Allocator) !void {
    const source_text = "type Reader [left,right] is effect = { read: Unit -> left, write: right -> Unit }\n";
    const consumer_text =
        \\const direct = source.Reader.read [U32,F32]
        \\const named = First.read [U32,F32]
        \\const alias = Second.read
        \\const use_alias = func () : U32 => return alias ()
        \\entry const answer = 42
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var source_tokens = try lexer.lex(allocator, source_text);
    defer source_tokens.deinit(allocator);
    var source_tree = try parser.parse(allocator, source_text, source_tokens.tokens.items, &pool);
    defer source_tree.deinit(allocator);
    var producer = try check.checkModule(allocator, &source_tree, &pool, &.{}, &.{}, 2);
    var producer_alive = true;
    defer if (producer_alive) producer.deinit(allocator);
    var consumer_tokens = try lexer.lex(allocator, consumer_text);
    defer consumer_tokens.deinit(allocator);
    var consumer_tree = try parser.parse(allocator, consumer_text, consumer_tokens.tokens.items, &pool);
    defer consumer_tree.deinit(allocator);
    const namespace = try pool.intern(allocator, "source");
    const first = try pool.intern(allocator, "First");
    const second = try pool.intern(allocator, "Second");
    var consumer = try check.checkModule(allocator, &consumer_tree, &pool, &.{}, &.{
        .{ .producer = &producer, .kind = .catalog, .index = 0, .origin = 0 },
        .{ .producer = &producer, .kind = .effect_family, .index = 1, .name = pool.lookup("Reader").?, .namespace = namespace, .origin = 0 },
        .{ .producer = &producer, .kind = .effect_family, .index = 1, .name = first, .origin = 0 },
        .{ .producer = &producer, .kind = .effect_family, .index = 1, .name = second, .origin = 0 },
    }, 1);
    defer consumer.deinit(allocator);
    producer.deinit(allocator);
    producer_alive = false;
    try std.testing.expectEqual(@as(usize, 0), consumer.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 2), consumer.effect_families.len);
    try std.testing.expectEqual(@as(usize, 3), consumer.effect_templates.len);
    const family = consumer.effect_families[1];
    try std.testing.expectEqual(@as(u32, 2), family.identity.unit);
    try std.testing.expectEqual(@as(u32, 1), family.parameters.len);
    try std.testing.expectEqual(@as(u32, 2), family.variables.len);
    const shaped = consumer.types.node(consumer.types.list(family.parameters)[0]);
    const components = consumer.types.list(.{ .start = shaped.a, .len = shaped.b });
    const operations = consumer.types.list(family.operations);
    try std.testing.expectEqual(components[0], consumer.effect_templates[operations[0]].result);
    try std.testing.expectEqual(components[1], consumer.effect_templates[operations[1]].parameter);
    try std.testing.expectEqual(@as(u32, 2), consumer.effect_templates[operations[0]].identity.unit);
    try std.testing.expectEqual(@as(usize, 3), consumer.operation_uses.len);
    for (consumer.operation_uses) |use| {
        try std.testing.expectEqual(@as(u32, 2), consumer.effect_templates[use.template].identity.unit);
        try std.testing.expectEqual(T.Tag.function, consumer.types.node(use.signature).tag);
    }
}
test "owned effect family imports deduplicate aliases and outlive the producer semantic store" {
    try importedCatalogs(a);
}
test "owned effect catalog imports clean every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, importedCatalogs, .{});
}

fn runnerSource(allocator: std.mem.Allocator) !void {
    const text =
        \\type State state is effect = { get:Unit -> state, set:state -> Unit }
        \\const run = func initial => return func action => return @effect.run State.get State.set initial action
        \\entry const answer = func () => return do:
        \\  let (next,previous) = run 41 (func () => return do:
        \\    use previous <- State.get ()
        \\    use State.set (@u32.add previous 1)
        \\    break previous)
        \\  break @u32.add next previous
        \\entry const reader = func () : U32 => return @effect.reader State.get (func () : U32 => return @panic "witness called") (func () => return 42) (func () : U32 => return State.get ())
        \\entry const writer = func () => return @effect.run State.get State.set 0 (func () => return @effect.writer State.set (func () : U32 => return @panic "witness called") (func value => return State.set value) (func () => return do:
        \\  use State.set 42
        \\  break 42))
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
    try std.testing.expectEqual(@as(usize, 4), checked.effect_runners.len);
    var generic_predicates: usize = 0;
    for (checked.bindings) |binding| if (binding.name == pool.lookup("run").?) {
        for (checked.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len]) |predicate| {
            if (predicate.kind == .effect_handler) {
                generic_predicates += 1;
                const token = checked.types.node(predicate.ty);
                try std.testing.expectEqual(T.Tag.nominal, token.tag);
                const state = checked.types.nominalArguments(token)[0];
                try std.testing.expectEqual(T.Tag.variable, checked.types.node(state).tag);
                try std.testing.expectEqual(T.Tag.function, checked.types.node(predicate.signature).tag);
                try std.testing.expectEqual(T.Tag.function, checked.types.node(predicate.other).tag);
            }
        }
    };
    try std.testing.expectEqual(@as(usize, 2), generic_predicates);
    for (checked.effect_runners, 0..) |runner, index| {
        try std.testing.expectEqual(@as(u32, @intCast(index + 1)), checked.effect_runner_ids[runner.node]);
        try std.testing.expectEqual(T.Tag.function, checked.types.node(runner.action_type).tag);
        if (runner.kind == .run) {
            try std.testing.expect(runner.initial != 0 and runner.witness == 0 and runner.implementation == 0);
            try std.testing.expect(runner.read_token != 0 and runner.write_token != 0);
            try std.testing.expectEqual(T.Tag.product, checked.types.node(runner.result).tag);
        } else {
            try std.testing.expect(runner.initial == 0 and runner.witness != 0 and runner.implementation != 0);
            try std.testing.expectEqual(T.u32_type, runner.state_type);
            try std.testing.expectEqual(T.Tag.function, checked.types.node(runner.implementation_type).tag);
        }
    }
}
test "generic effect runners retain exact state row removal and ordinary operand metadata" {
    try runnerSource(a);
}
test "effect runner schemes rows and source operand publication release every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, runnerSource, .{});
}

fn importedRunners(allocator: std.mem.Allocator) !void {
    const producer_text =
        \\type State state is effect = { get:Unit -> state, set:state -> Unit }
        \\const run = func initial => return func action => return @effect.run State.get State.set initial action
    ;
    const consumer_text =
        \\entry const integer = func () => return @product.get (run 42 (func () : U32 => return source.State.get ())) 1
        \\entry const floating = func () => return @product.get (run 1.25 (func () : F32 => return source.State.get ())) 1
        \\entry const direct = func () : U32 => return @effect.reader source.State.get (func () : U32 => return @panic "unused witness") (func () => return 42) (func () : U32 => return source.State.get ())
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var producer_tokens = try lexer.lex(allocator, producer_text);
    defer producer_tokens.deinit(allocator);
    var producer_tree = try parser.parse(allocator, producer_text, producer_tokens.tokens.items, &pool);
    defer producer_tree.deinit(allocator);
    var producer = try check.checkModule(allocator, &producer_tree, &pool, &.{}, &.{}, 7);
    var producer_alive = true;
    defer if (producer_alive) producer.deinit(allocator);
    var consumer_tokens = try lexer.lex(allocator, consumer_text);
    defer consumer_tokens.deinit(allocator);
    var consumer_tree = try parser.parse(allocator, consumer_text, consumer_tokens.tokens.items, &pool);
    defer consumer_tree.deinit(allocator);
    const namespace = pool.lookup("source").?;
    const run_name = pool.lookup("run").?;
    var run_binding: check.BindingId = 0;
    for (producer.bindings, 0..) |binding, index| if (binding.name == run_name) {
        run_binding = @intCast(index);
        break;
    };
    const binding = producer.bindings[run_binding];
    var consumer = try check.checkModule(allocator, &consumer_tree, &pool, &.{.{ .name = run_name, .target = .{ .unit = 7, .binding = run_binding }, .origin = 0, .interface = .{ .types = .{ .store = &producer.types }, .scheme = binding.scheme, .obligations = producer.obligations } }}, &.{
        .{ .producer = &producer, .kind = .catalog, .index = 0, .origin = 0 },
        .{ .producer = &producer, .kind = .effect_family, .index = 1, .name = pool.lookup("State").?, .namespace = namespace, .origin = 0 },
    }, 1);
    defer consumer.deinit(allocator);
    producer.deinit(allocator);
    producer_alive = false;
    try std.testing.expectEqual(@as(usize, 0), consumer.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 1), consumer.imported_schemes);
    try std.testing.expectEqual(@as(usize, 3), consumer.body_elaborations);
    for (consumer.bindings) |actual| {
        if (actual.kind != .global) continue;
        const function = consumer.types.node(actual.scheme.root);
        if (actual.name == pool.lookup("integer").?) try std.testing.expectEqual(T.u32_type, function.b);
        if (actual.name == pool.lookup("floating").?) try std.testing.expectEqual(T.f32_type, function.b);
    }
    try std.testing.expectEqual(@as(usize, 1), consumer.effect_runners.len);
    const token = consumer.types.node(consumer.effect_runners[0].read_token);
    try std.testing.expectEqual(@as(u32, 7), token.a);
    try std.testing.expectEqualSlices(T.Id, &.{T.u32_type}, consumer.types.nominalArguments(token));
    for (consumer.obligations) |predicate| if (predicate.kind == .effect_handler) {
        const origin = consumer.types.node(predicate.ty);
        try std.testing.expectEqual(@as(u32, 7), origin.a);
    };
}
test "imported generic runners preserve producer identity and independently freshen state and residual rows" {
    try importedRunners(a);
}
test "imported runner interfaces release every failed allocation and outlive their producer" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, importedRunners, .{});
}

test "effect runner template families arity and signatures match frozen negative admission" {
    const cases = [_]struct { name: []const u8, source: []const u8, code: check.Code }{
        .{ .name = "alias_template", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nconst alias = State.get\nentry const answer = func () => return @effect.reader alias 0 (func () => return 42) (func () : U32 => return State.get ())\n", .code = .operation_target },
        .{ .name = "explicit_template", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = func () => return @effect.reader (State.get U32) 0 (func () => return 42) (func () : U32 => return State.get ())\n", .code = .operation_target },
        .{ .name = "zero_binder", .source = "type State is effect = { get: Unit -> U32, set: U32 -> Unit }\nentry const answer = func () => return @effect.run State.get State.set 0 (func () => return 42)\n", .code = .operation_target },
        .{ .name = "shaped_binder", .source = "type State [a] is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = func () => return @effect.run State.get State.set 0 (func () => return 42)\n", .code = .type_arity },
        .{ .name = "multiple_binders", .source = "type State a => type b is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = func () => return @effect.run State.get State.set 0 (func () => return 42)\n", .code = .type_arity },
        .{ .name = "different_family", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\ntype Other a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = func () => return @effect.run State.get Other.set 0 (func () => return 42)\n", .code = .effect_family },
        .{ .name = "swapped_pair", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = func () => return do:\n  let (next,result) = @effect.run State.set State.get 0 (func () => return 42)\n  break @u32.add next result\n", .code = .type_mismatch },
        .{ .name = "duplicate_operation", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = func () => return do:\n  let (next,result) = @effect.run State.get State.get 0 (func () => return 42)\n  break @u32.add next result\n", .code = .invalid_state_provider },
        .{ .name = "wrong_implementation", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = func () => return @effect.reader State.get 0 (func () => return true) (func () : U32 => return State.get ())\n", .code = .type_mismatch },
        .{ .name = "wrong_action_parameter", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = func () => return @effect.run State.get State.set 0 (func (value:U32) => return value)\n", .code = .type_mismatch },
        .{ .name = "partial_run", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = func () => return @effect.run State.get State.set 0\n", .code = .call_arity },
        .{ .name = "bare_reader", .source = "const helper = @effect.reader\nentry const answer = 42\n", .code = .call_arity },
    };
    for (cases) |item| {
        var tokens = try lexer.lex(a, item.source);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, item.source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        var checked = try check.check(a, &tree, &pool);
        defer checked.deinit(a);
        try std.testing.expect(checked.diagnostics.len != 0);
        try std.testing.expectEqual(item.code, checked.diagnostics[0].code);
    }
}

test "reader witnesses do not invent result links and forwarding implementations retain outward effects" {
    const text =
        \\type State state is effect = { get:Unit -> state, set:state -> Unit }
        \\entry const unannotated = func () => return @effect.reader State.get 0 (func () => return 42) (func () => return State.get ())
        \\entry const forwarding = func () : U32 => return @effect.reader State.get 0 (func () : U32 => return State.get ()) (func () : U32 => return State.get ())
    ;
    var tokens = try lexer.lex(a, text);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    for (checked.bindings) |binding| {
        if (binding.kind != .global) continue;
        const function = checked.types.node(binding.scheme.root);
        if (binding.name == pool.lookup("unannotated").?) try std.testing.expectEqual(T.Tag.variable, checked.types.node(function.b).tag);
        if (binding.name != pool.lookup("forwarding").?) continue;
        try std.testing.expectEqual(T.u32_type, function.b);
        try std.testing.expect(checked.types.row(function.c).tail == .variable);
        var retained_operation = false;
        for (checked.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len]) |predicate| {
            if (predicate.kind != .effect_operation) continue;
            retained_operation = true;
            try std.testing.expectEqualSlices(T.Id, &.{T.u32_type}, checked.types.list(.{ .start = checked.types.node(predicate.other).a, .len = 1 }));
        }
        try std.testing.expect(retained_operation);
    }
}

test "a handled inferred operation closes the exported reader principal and complete entry layout" {
    const core = @import("core.zig");
    const layout = @import("../backend/layout.zig");
    const text =
        \\type State state is effect = { get:Unit -> state, set:state -> Unit }
        \\entry const answer = func () : U32 => return @effect.reader State.get (func () : U32 => return @panic "witness called") (func () => return 42) (func () : U32 => return State.get ())
    ;
    var tokens = try lexer.lex(a, text);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var binding_id: check.BindingId = 0;
    for (checked.bindings, 0..) |binding, index| if (binding.name == pool.lookup("answer").?) {
        binding_id = @intCast(index);
        const principal = checked.types.node(binding.scheme.root);
        try std.testing.expectEqual(T.u32_type, principal.b);
        try std.testing.expectEqual(@as(u32, 0), principal.c);
        for (checked.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len]) |predicate| try std.testing.expect(predicate.kind != .effect_operation);
    };
    try std.testing.expect(binding_id != 0);
    var module = try core.lower(a, &tree, &pool, &checked);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    var layouts = try layout.Store.init(a);
    defer layouts.deinit();
    const body = module.body(binding_id).?;
    const complete = try layouts.fromType(&module, body.scheme.root, &.{});
    const function = layouts.node(complete);
    try std.testing.expectEqual(layout.Tag.function, function.tag);
    try std.testing.expectEqual(layout.Tag.unit, layouts.node(function.a).tag);
    try std.testing.expectEqual(layout.Tag.u32, layouts.node(function.b).tag);
    try std.testing.expectEqual(@as(u32, 0), try layouts.rowFromType(&module, module.types.node(body.scheme.root).c, &.{}, &.{}, false));
}

fn foreignAnnotations(allocator: std.mem.Allocator) !void {
    const text =
        \\effect Read: Unit -> U32
        \\type Callback is data = #Callback { invoke:U32 -> U32 ! {Foreign} }
        \\const invoke = func action => return action 7
        \\const call = func (io:U32 -> U32 ! {Foreign}) => return invoke io
        \\const retain = func (io:U32 -> U32 ! {Foreign}) => return func value => return io value
        \\const outer = func (io:U32 -> U32 -> U32 ! {Foreign}) => return ()
        \\const inner = func (io:U32 -> (U32 -> U32 ! {Foreign})) => return ()
        \\const pure = func (io:U32 -> U32 ! {}) => return io 1
        \\const duplicates = func (io:U32 -> U32 ! {Foreign,Foreign}) => return io 1
        \\const mixed = func (io:Unit -> U32 ! {Read,Foreign,Read}) => return io ()
        \\entry const answer = func (io:U32 -> U32 ! {Foreign}) => return call io
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
    for (checked.bindings) |binding| {
        if (binding.kind != .global) continue;
        const function = checked.types.node(binding.scheme.root);
        const name = pool.get(binding.name);
        if (std.mem.eql(u8, name, "call") or std.mem.eql(u8, name, "answer")) try std.testing.expectEqualSlices(u32, &.{T.foreign_operation}, checked.types.rowLabels(function.c));
        if (std.mem.eql(u8, name, "retain")) {
            try std.testing.expectEqual(@as(u32, 0), function.c);
            try std.testing.expectEqualSlices(u32, &.{T.foreign_operation}, checked.types.rowLabels(checked.types.node(function.b).c));
        }
        if (std.mem.eql(u8, name, "outer")) {
            const callback = checked.types.node(function.a);
            try std.testing.expectEqualSlices(u32, &.{T.foreign_operation}, checked.types.rowLabels(callback.c));
            try std.testing.expectEqual(@as(u32, 0), checked.types.node(callback.b).c);
        }
        if (std.mem.eql(u8, name, "inner")) {
            const callback = checked.types.node(function.a);
            try std.testing.expectEqual(@as(u32, 0), callback.c);
            try std.testing.expectEqualSlices(u32, &.{T.foreign_operation}, checked.types.rowLabels(checked.types.node(callback.b).c));
        }
        if (std.mem.eql(u8, name, "pure")) try std.testing.expectEqual(@as(u32, 0), function.c);
        if (std.mem.eql(u8, name, "duplicates")) try std.testing.expectEqualSlices(u32, &.{ T.foreign_operation, T.foreign_operation }, checked.types.rowLabels(function.c));
        if (std.mem.eql(u8, name, "mixed")) {
            const labels = checked.types.rowLabels(function.c);
            try std.testing.expectEqual(@as(usize, 3), labels.len);
            var foreign_count: usize = 0;
            for (labels) |label| if (label == T.foreign_operation) {
                foreign_count += 1;
            };
            try std.testing.expectEqual(@as(usize, 1), foreign_count);
        }
    }
    const constructor = checked.constructors[1];
    const record = checked.types.node(constructor.payload);
    const callback = checked.types.node(checked.types.recordField(record, 0).ty);
    try std.testing.expectEqualSlices(u32, &.{T.foreign_operation}, checked.types.rowLabels(callback.c));
}
test "source closed effect annotations retain Foreign callbacks arrow scope and multiplicity" {
    try foreignAnnotations(a);
}
test "source Foreign annotation and callback row publication release every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, foreignAnnotations, .{});
}

test "sealed Foreign annotations keep exact negative admission and ordinary shadowing" {
    const cases = [_]struct { source: []const u8, code: check.Code }{
        .{ .source = "const invalid=func (value:U32 ! {Foreign}) => return value\n", .code = .invalid_effect_annotation },
        .{ .source = "const invalid=func (io:U32 -> U32 ! {Missing}) => return io\n", .code = .unknown_effect },
        .{ .source = "const invalid=func (io:U32 -> U32 ! {Foreign U32}) => return io\n", .code = .type_arity },
        .{ .source = "effect Read:Unit -> U32 ! {Foreign}\n", .code = .operation_signature },
        .{ .source = "const invalid=func (io:U32 -> U32 ! {Foreign}) => return do:\n  let value=io 1\n  break value\n", .code = .let_effect },
        .{ .source = "const callback:U32 -> U32 ! {Foreign}=func value=> return value\nentry const invalid=callback 1\n", .code = .const_effect },
        .{ .source = "const pure=func (io:U32 -> U32)=> return io 1\nconst invalid=func (io:U32 -> U32 ! {Foreign})=> return pure io\n", .code = .effect_mismatch },
    };
    for (cases) |item| {
        var tokens = try lexer.lex(a, item.source);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, item.source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        var checked = try check.check(a, &tree, &pool);
        defer checked.deinit(a);
        try std.testing.expect(checked.diagnostics.len != 0);
        try std.testing.expectEqual(item.code, checked.diagnostics[0].code);
    }
    const text = "type Foreign is data = #Foreign\nconst Foreign=42\nconst read=func (io:U32 -> U32 ! {Foreign})=> return io 1\nconst result=func () : U32 ! {Foreign} => return 42\n";
    var tokens = try lexer.lex(a, text);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    for (checked.bindings) |binding| {
        if (binding.kind != .global) continue;
        if (binding.name != pool.lookup("read").? and binding.name != pool.lookup("result").?) continue;
        const signature = checked.types.node(binding.scheme.root);
        try std.testing.expectEqualSlices(u32, &.{T.foreign_operation}, checked.types.rowLabels(signature.c));
        if (binding.name == pool.lookup("result").?) {
            try std.testing.expectEqual(T.unit, signature.a);
            try std.testing.expectEqual(T.u32_type, signature.b);
        }
    }
}

fn symbolicWrittenRows(allocator: std.mem.Allocator) !void {
    const text =
        \\type State a is effect = { get: Unit -> a, set: a -> Unit }
        \\const read: Unit -> a ! {State.get a} = func () => return State.get ()
        \\const apply = func (callback: Unit -> a ! {State.get a | e}) => return callback ()
        \\const capture = func (callback: Unit -> a ! {State.get a}) => return func () => return callback ()
        \\entry const integer = func () => return @effect.run State.get State.set 42 (func () => return apply (capture read))
        \\entry const floating = func () => return @effect.run State.get State.set 1.5 (func () => return read ())
    ;
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
}

test "symbolic written operation rows retain generic arguments through callbacks and captures" {
    try symbolicWrittenRows(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, symbolicWrittenRows, .{});
}

fn symbolicImportedRows(allocator: std.mem.Allocator) !void {
    const text =
        \\const alias = source
        \\const integer = func () : U32 => return source ()
        \\const floating = func () : F32 => return alias ()
        \\entry const answer = 42
    ;
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var producer = try T.Store.init(allocator);
    defer producer.deinit();
    const variable = try producer.fresh();
    const label = try producer.internSymbolicOperation(.{ .unit = 9, .decl = 31 }, &.{variable});
    const signature = try producer.functionWithEffects(T.unit, variable, try producer.effects.row(&.{label}, .closed));
    const scheme: T.Scheme = .{ .root = signature, .variables = try producer.saveList(&.{variable}) };
    var checked = try check.checkWithImports(allocator, &tree, &pool, &.{.{
        .name = pool.lookup("source").?,
        .target = .{ .unit = 9, .binding = 1 },
        .origin = 0,
        .interface = .{ .types = .{ .store = &producer }, .scheme = scheme, .obligations = &.{} },
    }});
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    for ([_]struct { []const u8, T.Id }{ .{ "integer", T.u32_type }, .{ "floating", T.f32_type } }) |expected| {
        const binding = for (checked.bindings) |candidate| {
            if (candidate.name == pool.lookup(expected[0]).?) break candidate;
        } else unreachable;
        const root = checked.types.node(binding.scheme.root);
        const labels = checked.types.rowLabels(root.c);
        try std.testing.expectEqual(@as(usize, 1), labels.len);
        try std.testing.expectEqualSlices(T.Id, &.{expected[1]}, checked.types.operationArguments(labels[0]));
    }
}

test "symbolic operation interface imports freshen argument binders with generic aliases" {
    try symbolicImportedRows(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, symbolicImportedRows, .{});
}

fn checkScopedSource(allocator: std.mem.Allocator, text: []const u8, expected: ?check.Code) !void {
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    if (expected) |code| {
        for (checked.diagnostics) |diagnostic| if (diagnostic.code == code) return;
        return error.ExpectedScopedDiagnostic;
    }
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expect(checked.effect_scopes.len != 0);
}
const scoped_state_header = "type State a is effect = {get: Unit -> a, set: a -> Unit}\n";
const scoped_nested_source = scoped_state_header ++
    "entry const answer = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:\n" ++
    "  let (outer, result) = do (@effect.state left.get left.set 10):\n" ++
    "    use nested <- do (@effect.state right.get right.set 100):\n" ++
    "      use a <- left.get ()\n" ++
    "      use b <- right.get ()\n" ++
    "      use left.set (@u32.add a 1)\n" ++
    "      use right.set (@u32.add b 2)\n" ++
    "      break #[a, b]\n" ++
    "    let (inner, reads) = nested\n" ++
    "    break @array.concat #[inner] reads\n" ++
    "  break @array.concat #[outer] result\n" ++
    "))\n";
test "scoped effect nested same typed capabilities retain independent exact rows" {
    try checkScopedSource(a, scoped_nested_source, null);
}
test "scoped effect boundary rejects direct capability and handled closures" {
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func (s: State U32) => return s)\n", .capability_escape);
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func (s: State U32) => return func () => return do (@effect.state s.get s.set 0):\n  break 42\n)\n", .capability_escape);
}
test "scoped effect requires explicit closed family callback and rejects residual identity" {
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func s => return 42)\n", .effect_identity_scope);
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func (s: State U32) => return do:\n  use n <- s.get ()\n  break n\n)\n", .effect_mismatch);
}
test "scoped effect operation aliases and local callbacks remain usable" {
    try checkScopedSource(a, scoped_state_header ++ "entry const answer = func () => return @effect.scope (func (s: State U32) => return do:\n  let capability = s\n  let read = capability.get\n  let write = capability.set\n  let local = func () => return read ()\n  let (state, result) = do (@effect.state read write 7):\n    break local ()\n  break result\n)\n", null);
}

test "scoped effect rejects operation aggregate demand and generic authority escapes" {
    const suffixes = [_][]const u8{
        "s.get",
        "#[s]",
        "{saved: s.get}",
        "@computation (func () => return do (@effect.state s.get s.set 0):\n  break 42\n)",
    };
    for (suffixes) |suffix| {
        const text = try a.print("{s}entry const bad = func () => return @effect.scope (func (s: State U32) => return {s})\n", .{ scoped_state_header, suffix });
        defer a.free(text);
        try checkScopedSource(a, text, .capability_escape);
    }
    try checkScopedSource(a, scoped_state_header ++ "const identity = func value => return value\nentry const bad = func () => return @effect.scope (func (s: State U32) => return identity s)\n", .capability_escape);
}

test "scoped effect different instance provider leaves exact requirement visible" {
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do (@effect.state right.get right.set 0):\n  use value <- left.get ()\n  break value\n))\n", .effect_mismatch);
}

test "scoped effect reflection cannot publish a fresh descriptor" {
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func (s: State U32) => return @effect.descriptor s.get)\n", .open_effect_descriptor);
}

fn scopedAllocationLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, scoped_state_header ++ "entry const answer = func () => return @effect.scope (func (s: State U32) => return do (@effect.state s.get s.set 7):\n  break s.get ()\n)\n", null);
}

test "scoped effect checker releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, scopedAllocationLaw, .{});
}

test "scoped effect longer lived builtin State cannot retain capturing closure" {
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @state.run (func () => return 0) (func () => return @effect.scope (func (s: State U32) => return do:\n  use @state.set (func () => return do (@effect.state s.get s.set 0):\n    break 42\n  )\n  break 42\n))\n", .capability_escape);
}

test "scoped effect request clauses preserve a fresh owner" {
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func (s: State U32) => return do:\n  let computation = @computation (func () => return s.get ())\n  for request in @requests computation:\n    case request of\n      effect s.get () =>\n        yield 7\n      complete value =>\n        break value\n)\n", null);
}

test "scoped effect State pairing rejects different runtime owners" {
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:\n  let provider = @effect.state left.get right.set 0\n  break 42\n))\n", .effect_identity_scope);
}

test "scoped effect request aliases reject duplicate owner clauses" {
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func (s: State U32) => return do:\n  let alias = s.get\n  let computation = @computation (func () => return s.get ())\n  for request in @requests computation:\n    case request of\n      effect s.get () =>\n        yield 7\n      effect alias () =>\n        yield 8\n      complete value =>\n        break value\n)\n", .duplicate_request_handler);
}
test "scoped effect request clause for another owner leaves its requirement" {
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:\n  let computation = @computation (func () => return left.get ())\n  for request in @requests computation:\n    case request of\n      effect right.get () =>\n        yield 7\n      complete value =>\n        break value\n))\n", .effect_mismatch);
}

const scoped_generic_source = scoped_state_header ++
    "const local = func (value: a) => return @effect.scope (func (s: State a) => return do:\n" ++
    "  let (state, result) = do (@effect.state s.get s.set value):\n" ++
    "    break s.get ()\n" ++
    "  break result\n" ++
    ")\n" ++
    "entry const integer = func () => return local 7\n" ++
    "entry const fraction = func () => return local 1.5\n";
test "scoped effect symbolic family arguments preserve inherited payload shapes" {
    try checkScopedSource(a, scoped_generic_source, null);
    try checkScopedSource(a, scoped_state_header ++ "const local = func (value: a) => return @effect.scope (func (s: State a) => return {saved: value})\nentry const answer = func () => return local 7\n", null);
}
test "scoped effect symbolic payload proof cannot erase a fresh capture" {
    try checkScopedSource(a, scoped_state_header ++ "const local = func (value: a) => return @effect.scope (func (s: State a) => return func () => return do (@effect.state s.get s.set value):\n  break s.get ()\n)\nentry const bad = func () => return local 7\n", .capability_escape);
    try checkScopedSource(a, scoped_state_header ++ "const local = func (value: a) => return @effect.scope (func (s: State a) => return {saved: s})\nentry const bad = func () => return local 7\n", .capability_escape);
}
fn scopedGenericAllocationLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, scoped_generic_source, null);
}
test "scoped effect symbolic payload checking releases failed allocations" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, scopedGenericAllocationLaw, .{});
}

const scoped_static_store_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\type Save a is effect = {keep: (Unit -> a) -> Unit}
    \\entry const bad = func () => return do:
    \\  let (saved, result) = @state.run (func () => return 0) (func () => return do (@effect.provider (Save.keep U32) (func value => return @state.set value)):
    \\    break @effect.scope (func (s: State U32) => return do:
    \\      use Save.keep U32 (func () => return do:
    \\        let (state, result) = do (@effect.state s.get s.set 0):
    \\          break 42
    \\        break result
    \\      )
    \\      break 42
    \\    )
    \\  )
    \\  break saved ()
;
fn scopedStaticStoreAllocationLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, scoped_static_store_source, .capability_escape);
}
test "scoped effect static generic operations cannot transfer authority to longer lived storage" {
    try scopedStaticStoreAllocationLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, scopedStaticStoreAllocationLaw, .{});
}

const scoped_callback_source = scoped_state_header ++
    "entry const answer = func () => return @effect.scope (func (s: State U32) => return do:\n" ++
    "  let (state, result) = do (@effect.state s.get s.set 7):\n" ++
    "    break (func callback => return callback ()) (func () => return s.get ())\n" ++
    "  break result\n" ++
    ")\n";
fn scopedCallbackAllocationLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, scoped_callback_source, null);
}
test "scoped effect direct callback adapters can borrow live authority" {
    try scopedCallbackAllocationLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, scopedCallbackAllocationLaw, .{});
}
test "scoped effect direct callback adapter cannot return captured authority" {
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func (s: State U32) => return (func callback => return callback ()) (func () => return s.get))\n", .capability_escape);
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func (s: State U32) => return (func callback => return func () => return callback ()) (func () => return do (@effect.state s.get s.set 0):\n  break 42\n))\n", .capability_escape);
}

const scoped_outer_result_source = scoped_state_header ++
    "entry const answer = func () => return @effect.scope (func (left: State U32) => return do:\n" ++
    "  let longer = @effect.scope (func (right: State U32) => return {saved: left})\n" ++
    "  let (state, result) = do (@effect.state left.get left.set 7):\n" ++
    "    break longer.saved.get ()\n" ++
    "  break result\n" ++
    ")\n";
fn scopedOuterResultAllocationLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, scoped_outer_result_source, null);
}
test "scoped effect result footprint subtracts only the exiting binder" {
    try scopedOuterResultAllocationLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, scopedOuterResultAllocationLaw, .{});
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func (left: State U32) => return do:\n  let invalid = @effect.scope (func (right: State U32) => return {outer: left, inner: #[right]})\n  break 42\n)\n", .capability_escape);
}

const scoped_pure_closure_source = scoped_state_header ++
    "entry const answer = func () => return do:\n" ++
    "  let callback = @effect.scope (func (s: State U32) => return func () => return 42)\n" ++
    "  break callback ()\n";
fn scopedPureClosureAllocationLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, scoped_pure_closure_source, null);
}
test "scoped effect closed source closure footprints distinguish captures from effects" {
    try scopedPureClosureAllocationLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, scopedPureClosureAllocationLaw, .{});
    try checkScopedSource(a, scoped_state_header ++ "entry const bad = func () => return @effect.scope (func (s: State U32) => return func () => return do (@effect.state s.get s.set 0):\n  break 42\n)\n", .capability_escape);
}

const static_alias_regression_source =
    \\type Number = U32
    \\type Identity a = a
    \\type Signal a is effect = { get: Unit -> a }
    \\type Read a is contract = { operation Signal.get a, type_rep a, effect_rep ! {} }
    \\const read: Unit -> a ! {| e} where { Read a } = func () => return Signal.get a ()
    \\const number: Unit -> Number ! {Signal.get Number} = func () => return Signal.get Number ()
    \\entry const answer = func () : U32 => return do (@effect.provider (Signal.get (Identity Number)) (func () => return 21)):
    \\  break @u32.add (read ()) (number ())
    \\entry const fraction = func () : F32 => return do (@effect.provider (Signal.get (Identity F32)) (func () => return 1.5)):
    \\  break read ()
;
fn abstractReadAliasLaw(allocator: std.mem.Allocator) !void {
    var tokens = try lexer.lex(allocator, static_alias_regression_source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, static_alias_regression_source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &names);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(0, checked.diagnostics.len);
    var symbolic: usize = 0;
    for (checked.contract_predicates) |predicate| {
        if (predicate.kind != .effect_operation) continue;
        const signature = checked.types.node(try checked.types.resolve(predicate.signature, 0));
        for (checked.types.rowLabels(signature.c)) |label| {
            const arguments = checked.types.operationArguments(label);
            if (arguments.len != 1) continue;
            if (!try checked.types.equalClosed(arguments[0], arguments[0])) symbolic += 1;
        }
    }
    try std.testing.expect(symbolic > 0);
}
test "symbolic operation aliases with abstract Read contracts retain argument closure" {
    try abstractReadAliasLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, abstractReadAliasLaw, .{});
}

const parameter_store_source = scoped_state_header ++
    \\type Save a is effect = {keep: (Unit -> a) -> Unit}
    \\const invalid = func (s: State U32) => return Save.keep U32 (func () => return do:
    \\  let (state, result) = do (@effect.state s.get s.set 0):
    \\    break 42
    \\  break result
    \\)
    \\entry const answer = 42
;
fn parameterStoreRejected(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, parameter_store_source, .capability_escape);
}
test "scoped effect symbolic capability parameters cannot hide captures in static storage operations" {
    try parameterStoreRejected(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, parameterStoreRejected, .{});
}

test "scoped effect callback rows retain unmatched owner requirements at scope exit" {
    try checkScopedSource(a, scoped_state_header ++
        \\const apply = func (s: State a) => return func (callback: Unit -> a ! {s.get | e}) => return callback ()
        \\entry const invalid = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
        \\  use nested <- do (@effect.state left.get left.set 7):
        \\    break apply left (func () => return right.get ())
        \\  let (state, result) = nested
        \\  break result
        \\))
    , .capability_escape);
}

test "scoped effect partially applied identity cannot hide a storage sink" {
    try checkScopedSource(a, scoped_state_header ++
        \\type Save a is effect = {keep: (Unit -> a) -> Unit}
        \\const identity = func value => return value
        \\const save = func callback => return Save.keep U32 callback
        \\entry const invalid = func () => return @effect.scope (func (s: State U32) => return (identity save) (func () => return do (@effect.state s.get s.set 0):
        \\  break 42
        \\))
    , .capability_escape);
}

pub const local_store_source = scoped_state_header ++
    \\type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}
    \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
    \\  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
    \\    use Box.set (func () => return do:
    \\      let (state, value) = do (@effect.state s.get s.set 7):
    \\        break s.get ()
    \\      break value
    \\    )
    \\    use callback <- Box.get ()
    \\    break callback ()
    \\  break result
    \\)
;
fn localStateStorageLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, local_store_source, null);
}
test "scoped effect local State cells may store longer lived source captures" {
    try localStateStorageLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, localStateStorageLaw, .{});
}

test "scoped effect older State cells reject younger source captures" {
    try checkScopedSource(a, scoped_state_header ++
        \\entry const invalid = func () => return @effect.scope (func (cell: State (Unit -> U32)) => return do:
        \\  let (stored, result) = do (@effect.state cell.get cell.set (func () => return 0)):
        \\    break @effect.scope (func (s: State U32) => return do:
        \\      use cell.set (func () => return do:
        \\        let (state, value) = do (@effect.state s.get s.set 7):
        \\          break s.get ()
        \\        break value
        \\      )
        \\      break 42
        \\    )
        \\  break result
        \\)
    , .capability_escape);
}

test "scoped effect ordinary provider shadowing cannot license a State storage lifetime" {
    try checkScopedSource(a, scoped_state_header ++
        \\type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}
        \\entry const invalid = func () => return @effect.scope (func (s: State U32) => return do:
        \\  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
        \\    break do (@effect.provider Box.set (func callback => return ())):
        \\      use Box.set (func () => return do:
        \\        let (state, value) = do (@effect.state s.get s.set 7):
        \\          break s.get ()
        \\        break value
        \\      )
        \\      break 42
        \\  break result
        \\)
    , .capability_escape);
}

test "scoped effect closures do not inherit construction time State handlers" {
    try checkScopedSource(a, scoped_state_header ++
        \\type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}
        \\entry const invalid = func () => return @effect.scope (func (s: State U32) => return do:
        \\  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
        \\    let later = func () => return Box.set (func () => return do:
        \\      let (state, value) = do (@effect.state s.get s.set 7):
        \\        break s.get ()
        \\      break value
        \\    )
        \\    break 42
        \\  break result
        \\)
    , .capability_escape);
}

pub const dependent_arrow_source = scoped_state_header ++
    \\const read: (state: State a) -> a ! {state.get} = func input => return input.get ()
    \\const apply: (state: State a) -> ((Unit -> a ! {state.get | e}) -> a ! {state.get | e}) = func input => return func callback => return callback ()
    \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
    \\  let (state, result) = do (@effect.state s.get s.set 7):
    \\    use a <- read s
    \\    use b <- apply s (func () => return s.get ())
    \\    break @u32.add a b
    \\  break result
    \\)
;
fn dependentArrowLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, dependent_arrow_source, null);
}
test "scoped effect complete arrow binders share input identities across later rows" {
    try dependentArrowLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, dependentArrowLaw, .{});
}

test "scoped effect complete arrow inputs cannot hide captures in storage" {
    try checkScopedSource(a, scoped_state_header ++
        \\type Save a is effect = {keep: (Unit -> a) -> Unit}
        \\const invalid: (state: State U32) -> Unit ! {Save.keep U32} = func input => return Save.keep U32 (func () => return do:
        \\  let (state, value) = do (@effect.state input.get input.set 7):
        \\    break input.get ()
        \\  break value
        \\)
        \\entry const answer = 42
    , .capability_escape);
}

test "scoped effect complete arrow binder names stop at the annotation boundary" {
    try checkScopedSource(a, dependent_arrow_source ++ "\n" ++
        \\const invalid: Unit -> U32 ! {state.get} = func () => return 42
    , .unknown_effect);
}

test "scoped effect complete arrow context preserves explicit parameter constraints" {
    try checkScopedSource(a, scoped_state_header ++
        \\const invalid: (state: State U32) -> U32 ! {state.get} = func (input: State F32) => return input.get ()
        \\entry const answer = 42
    , .type_mismatch);
    try checkScopedSource(a, scoped_state_header ++
        \\const invalid: (state: State U32) -> U32 = func () => return 42
        \\entry const answer = 42
    , .type_mismatch);
}

pub const pair_source = scoped_state_header ++
    \\const first = func (left: State a) => return func (right: State b) => return left.get ()
    \\const second: (left: State a) -> ((right: State b) -> b ! {right.get}) = func x => return func y => return y.get ()
    \\entry const answer = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
    \\  use outer <- do (@effect.state left.get left.set 7):
    \\    use inner <- do (@effect.state right.get right.set 100):
    \\      use a <- first left right
    \\      use b <- second left right
    \\      use c <- first right left
    \\      use d <- second right left
    \\      break @u32.add (@u32.add a b) (@u32.add c d)
    \\    let (state, result) = inner
    \\    break result
    \\  let (state, result) = outer
    \\  break result
    \\))
;
fn pairLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, pair_source, null);
}
test "scoped effect paired capability binders retain each selected input row" {
    try pairLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, pairLaw, .{});
}

pub const selection_source = scoped_state_header ++
    \\entry const answer = func flag => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
    \\  let selected = if flag then left else right
    \\  let alias = selected
    \\  let (state, result) = do (@effect.state selected.get selected.set 41):
    \\    use alias.set 42
    \\    break alias.get ()
    \\  break result
    \\))
;
fn selectionLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, selection_source, null);
}
test "scoped effect selection retains one rigid value and both reachable owners" {
    try selectionLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, selectionLaw, .{});
}

test "scoped effect selection cannot discharge independent roots or expose either origin" {
    try checkScopedSource(a, scoped_state_header ++
        \\entry const bad = func flag => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return if flag then left else right))
    , .capability_escape);
    try checkScopedSource(a, scoped_state_header ++
        \\entry const bad = func flag => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
        \\  let selected = if flag then left else right
        \\  let independent = if flag then left else right
        \\  use nested <- do (@effect.state selected.get selected.set 7):
        \\    break independent.get ()
        \\  let (state, result) = nested
        \\  break result
        \\))
    , .capability_escape);
    try checkScopedSource(a, scoped_state_header ++
        \\entry const bad = func flag => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
        \\  let selected = if flag then left else right
        \\  break func () => return do:
        \\    let (state, result) = do (@effect.state selected.get selected.set 7):
        \\      break selected.get ()
        \\    break result
        \\))
    , .capability_escape);
}
test "scoped effect selection keeps loop rejection and permits uninvoked local factories" {
    try checkScopedSource(a, scoped_state_header ++
        \\entry const bad = func flag => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
        \\  for index in 0..2:
        \\    let selected = if flag then left else right
        \\  break 42
        \\))
    , .effect_identity_scope);
    try checkScopedSource(a, scoped_state_header ++
        \\entry const bad = func flag => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
        \\  let later = func () => return if flag then left else right
        \\  break 42
        \\))
    , null);
    try checkScopedSource(a, scoped_state_header ++
        \\entry const bad = func flag => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
        \\  let later = func () => return if flag then left else right
        \\  break later
        \\))
    , .capability_escape);
}

pub const symbolic_selection_source = scoped_state_header ++
    \\const read = func (state: State a) => return state.get ()
    \\entry const answer = func initial => return @effect.scope (func (left: State a) => return @effect.scope (func (right: State a) => return do:
    \\  let selected = if true then left else right
    \\  let (state, result) = do (@effect.state selected.get selected.set initial):
    \\    use selected.set 7
    \\    break read selected
    \\  break result
    \\))
;
fn symbolicSelectionLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, symbolic_selection_source, null);
}
test "scoped effect selected symbolic payload normalization preserves the same instance edge" {
    try symbolicSelectionLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, symbolicSelectionLaw, .{});
}

pub const parameter_footprint_source = scoped_state_header ++
    \\const pack = func first => return func second => return func third => return (third, (first, second), first)
    \\entry const answer = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
    \\  let (selected, (first, second), repeated) = pack left right right
    \\  use outer <- do (@effect.state left.get left.set 7):
    \\    use inner <- do (@effect.state right.get right.set 100):
    \\      use a <- selected.get ()
    \\      use b <- first.get ()
    \\      use c <- second.get ()
    \\      use d <- repeated.get ()
    \\      break @u32.add (@u32.add a b) (@u32.add c d)
    \\    let (state, result) = inner
    \\    break result
    \\  let (state, result) = outer
    \\  break result
    \\))
;
fn parameterFootprintLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, parameter_footprint_source, null);
}
test "scoped effect pure product helpers retain every exact input footprint" {
    try parameterFootprintLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, parameterFootprintLaw, .{});
    try checkScopedSource(a, scoped_state_header ++
        \\const pack = func first => return func second => return (second, first)
        \\entry const bad = func () => return @effect.scope (func (state: State U32) => return pack state 42)
    , .capability_escape);
    try checkScopedSource(a, scoped_state_header ++
        \\const pack = func first => return func second => return do:
        \\  let saved = first
        \\  break (second, saved)
        \\entry const answer = func () => return @effect.scope (func (state: State U32) => return do:
        \\  let borrowed = pack state 42
        \\  break 42
        \\)
    , null);
    try checkScopedSource(a, scoped_state_header ++
        \\const pack = func first => return func second => return do:
        \\  let saved = first
        \\  break (second, saved)
        \\entry const bad = func () => return @effect.scope (func (state: State U32) => return do:
        \\  let borrowed = pack state 42
        \\  break borrowed
        \\)
    , .capability_escape);
}

test "scoped effect product summaries omit unused younger owners precisely" {
    try checkScopedSource(a, scoped_state_header ++
        \\const keep = func unused => return func retained => return (retained, 42)
        \\entry const answer = func () => return @effect.scope (func (older: State U32) => return do:
        \\  let (borrowed, count) = @effect.scope (func (younger: State U32) => return keep younger older)
        \\  use handled <- do (@effect.state borrowed.get borrowed.set 7):
        \\    use value <- borrowed.get ()
        \\    break @u32.add value count
        \\  let (state, result) = handled
        \\  break result
        \\)
    , null);
}

pub const parameter_invocation_source = scoped_state_header ++
    \\const invoke = func (left: State a) => return func (right: State b) => return func (callback: Unit -> U32 ! {left.get, right.get | e}) => return callback ()
    \\entry const answer = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
    \\  use outer <- do (@effect.state left.get left.set 7):
    \\    use inner <- do (@effect.state right.get right.set 100):
    \\      break invoke left right (func () => return do:
    \\        use a <- left.get ()
    \\        use b <- right.get ()
    \\        break @u32.add a b
    \\      )
    \\    let (state, result) = inner
    \\    break result
    \\  let (state, result) = outer
    \\  break result
    \\))
;
fn parameterInvocationLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, parameter_invocation_source, null);
}
test "scoped effect multiple input invocation summaries preserve exact callback rows" {
    try parameterInvocationLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, parameterInvocationLaw, .{});
}

pub const record_footprint_source = scoped_state_header ++
    \\const pack = func first => return func second => return {selected: second, nested: {first}, repeated: first}
    \\entry const answer = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
    \\  let borrowed = pack left right
    \\  use outer <- do (@effect.state left.get left.set 7):
    \\    use inner <- do (@effect.state right.get right.set 100):
    \\      use a <- borrowed.selected.get ()
    \\      use b <- borrowed.nested.first.get ()
    \\      use c <- borrowed.repeated.get ()
    \\      break @u32.add a (@u32.add b c)
    \\    let (state, result) = inner
    \\    break result
    \\  let (state, result) = outer
    \\  break result
    \\))
;
fn recordFootprintLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, record_footprint_source, null);
}
test "scoped effect record constructors retain exact named input footprints" {
    try recordFootprintLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, recordFootprintLaw, .{});
    try checkScopedSource(a, scoped_state_header ++
        \\const pack = func first => return func second => return {second, nested: {first}}
        \\entry const bad = func () => return @effect.scope (func (state: State U32) => return pack state 42)
    , .capability_escape);
    try checkScopedSource(a, scoped_state_header ++
        \\const keep = func unused => return func retained => return {retained, count: 42}
        \\entry const answer = func () => return @effect.scope (func (older: State U32) => return do:
        \\  let borrowed = @effect.scope (func (younger: State U32) => return keep younger older)
        \\  use handled <- do (@effect.state borrowed.retained.get borrowed.retained.set 7):
        \\    use value <- borrowed.retained.get ()
        \\    break @u32.add value borrowed.count
        \\  let (state, result) = handled
        \\  break result
        \\)
    , null);
}

pub const member_closure_source = scoped_state_header ++
    \\const reader = func unused => return func (state: State a) => return func () => return state.get ()
    \\entry const answer = func () => return @effect.scope (func (older: State U32) => return do:
    \\  let callback = @effect.scope (func (younger: State F32) => return reader younger older)
    \\  let (state, result) = do (@effect.state older.get older.set 7):
    \\    break callback ()
    \\  break result
    \\)
;
pub const too_many_member_closure_source = scoped_state_header ++
    \\const read = func a0 => return func a1 => return func a2 => return func a3 => return func a4 => return func a5 => return func a6 => return func a7 => return func a8 => return func a9 => return func a10 => return func a11 => return func a12 => return func a13 => return func a14 => return func (state: State a) => return func () => return state.get ()
    \\entry const answer = func () => return @effect.scope (func (older: State U32) => return do:
    \\  let callback = @effect.scope (func (younger: State F32) => return read younger younger younger younger younger younger younger younger younger younger younger younger younger younger younger older)
    \\  let (state, result) = do (@effect.state older.get older.set 7):
    \\    break callback ()
    \\  break result
    \\)
;
pub const maximum_member_closure_source = scoped_state_header ++
    \\const read = func a0 => return func a1 => return func a2 => return func a3 => return func a4 => return func a5 => return func a6 => return func a7 => return func a8 => return func a9 => return func a10 => return func a11 => return func a12 => return func a13 => return func (state: State a) => return func () => return state.get ()
    \\entry const answer = func () => return @effect.scope (func (older: State U32) => return do:
    \\  let callback = @effect.scope (func (younger: State F32) => return read younger younger younger younger younger younger younger younger younger younger younger younger younger younger older)
    \\  let (state, result) = do (@effect.state older.get older.set 7):
    \\    break callback ()
    \\  break result
    \\)
;
fn memberClosureLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, member_closure_source, null);
}
test "scoped effect member closure factories preserve exact captured formal lifetimes" {
    try memberClosureLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, memberClosureLaw, .{});
    try checkScopedSource(a, maximum_member_closure_source, null);
    try checkScopedSource(a, too_many_member_closure_source, .capability_escape);
    try checkScopedSource(a, scoped_state_header ++
        \\const reader = func (state: State a) => return func () => return state.get ()
        \\entry const bad = func () => return @effect.scope (func (state: State U32) => return reader state)
    , .capability_escape);
    try checkScopedSource(a, scoped_state_header ++
        \\const reader: (state: State a) -> (Unit -> a ! {state.get}) = func value => return func () => return value.get ()
        \\entry const answer = func () => return @effect.scope (func (older: State U32) => return do:
        \\  let callback = @effect.scope (func (younger: State F32) => return reader older)
        \\  let (state, result) = do (@effect.state older.get older.set 7):
        \\    break callback ()
        \\  break result
        \\)
    , null);
    try checkScopedSource(a, scoped_state_header ++
        \\const reader = func unused => return func (state: State a) => return func () => return state.get ()
        \\entry const bad = func () => return @effect.scope (func (older: State U32) => return do:
        \\  let callback = @effect.scope (func (younger: State U32) => return reader (func () => return younger.get ()) older)
        \\  let (state, result) = do (@effect.state older.get older.set 7):
        \\    break callback ()
        \\  break result
        \\)
    , .capability_escape);
}

const general_value_source = scoped_state_header ++
    \\const pack = func unused => return func (kept: State a) => return #[(func () => return kept.get ())]
    \\const identity = func value => return value
    \\entry const answer = func () => return @effect.scope (func (older: State U32) => return do:
    \\  let callbacks = @effect.scope (func (younger: State F32) => return do:
    \\    let alias = func () => return older.get ()
    \\    let version = identity alias
    \\    break {callbacks: pack younger older, nested: (version, #[version])}
    \\  )
    \\  let (state, result) = do (@effect.state older.get older.set 7):
    \\    break (@array.get callbacks.callbacks 0) ()
    \\  break result
    \\)
;
test "scoped value footprints preserve aliases nested callable containers and retained formal contracts" {
    try checkScopedSource(a, general_value_source, null);
    try checkScopedSource(a, scoped_state_header ++
        \\const pack = func unused => return func (kept: State a) => return #[(func () => return kept.get ())]
        \\entry const bad = func () => return @effect.scope (func (state: State U32) => return pack 42 state)
    , .capability_escape);
    try checkScopedSource(a, scoped_state_header ++
        \\entry const bad = func () => return @effect.scope (func (state: State U32) => return do:
        \\  let hidden = func () => return state.get ()
        \\  break {nested: #[(hidden, 42)]}
        \\)
    , .capability_escape);
}

fn generalValueFootprintLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, general_value_source, null);
}
test "scoped value footprint publication is transactional under allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, generalValueFootprintLaw, .{});
}

test "scoped value origins distinguish enclosing inputs from the fresh scope parameter" {
    try checkScopedSource(a, scoped_state_header ++
        \\const through = func callback => return @effect.scope (func (state: State U32) => return do:
        \\  let alias = callback
        \\  break {callback: alias}
        \\)
        \\entry const answer = func () => return (through (func () => return 7)).callback ()
    , null);
    try checkScopedSource(a, scoped_state_header ++
        \\entry const bad = func () => return @effect.scope (func (state: State U32) => return {callback: func () => return state.get ()})
    , .capability_escape);
    try checkScopedSource(a, scoped_state_header ++
        \\const defer = func sink => return func value => return #[(func () => return sink value)]
        \\entry const bad = func () => return @effect.scope (func (state: State U32) => return do:
        \\  let hidden = defer (func value => return value) state
        \\  break 42
        \\)
    , .capability_escape);
}

const precise_path_source = scoped_state_header ++
    \\const bundle = func (discarded: State a) => return func (retained: State a) => return {discarded: func () => return discarded.get (), retained: func () => return retained.get ()}
    \\const select = func value => return value.retained
    \\opaque type Wrapper a = a
    \\const unwrap = func value => return case value of
    \\  #Wrapper retained => retained
    \\entry const answer = func () => return @effect.scope (func (older: State U32) => return do:
    \\  let callback = @effect.scope (func (younger: State U32) => return do:
    \\    let fields = bundle younger older
    \\    break select (unwrap (#Wrapper fields))
    \\  )
    \\  let (state, result) = do (@effect.state older.get older.set 7):
    \\    break callback ()
    \\  break result
    \\)
;
fn preciseResultLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, precise_path_source, null);
}
test "scoped owned result paths discard unrelated hidden closure authority" {
    try preciseResultLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, preciseResultLaw, .{});
    try checkScopedSource(a, scoped_state_header ++
        \\const bundle = func (discarded: State a) => return func (retained: State a) => return {discarded: func () => return discarded.get (), retained: func () => return retained.get ()}
        \\entry const bad = func () => return @effect.scope (func (older: State U32) => return @effect.scope (func (younger: State U32) => return (bundle younger older).discarded))
    , .capability_escape);
    try checkScopedSource(a, scoped_state_header ++
        \\entry const bad = func () => return @effect.scope (func (older: State U32) => return @effect.scope (func (younger: State U32) => return do:
        \\  let fields = {discarded: func () => return younger.get (), retained: func () => return older.get ()}
        \\  let thunk = func () => return fields.retained ()
        \\  break thunk
        \\))
    , .capability_escape);
}

test "scoped owned projections retain pure hidden captures independently of latent effects" {
    try checkScopedSource(a, scoped_state_header ++
        \\const take_array = func values => return @array.get values 1
        \\entry const answer = func () => return @effect.scope (func (older: State U32) => return do:
        \\  let callback = @effect.scope (func (younger: State U32) => return do:
        \\    let discarded = func () => return do:
        \\      let ignored = younger
        \\      break 1
        \\    let retained = func () => return do:
        \\      let ignored = older
        \\      break 7
        \\    break take_array #[discarded, retained]
        \\  )
        \\  break callback ()
        \\)
    , null);
    try checkScopedSource(a, scoped_state_header ++
        \\const take_array = func values => return @array.get values 0
        \\entry const bad = func () => return @effect.scope (func (older: State U32) => return @effect.scope (func (younger: State U32) => return do:
        \\  let discarded = func () => return do:
        \\    let ignored = younger
        \\    break 1
        \\  let retained = func () => return do:
        \\    let ignored = older
        \\    break 7
        \\  break take_array #[discarded, retained]
        \\))
    , .capability_escape);
    try checkScopedSource(a, scoped_state_header ++
        \\const take_at = func values => return func index => return @array.get values index
        \\entry const bad = func (index: U32) => return @effect.scope (func (older: State U32) => return @effect.scope (func (younger: State U32) => return do:
        \\  let discarded = func () => return do:
        \\    let ignored = younger
        \\    break 1
        \\  let retained = func () => return do:
        \\    let ignored = older
        \\    break 7
        \\  break @array.get (take_at #[#[retained, discarded], #[retained, retained]] index) 1
        \\))
    , .capability_escape);
}

fn directScopeOlderStateLaw(allocator: std.mem.Allocator) !void {
    const text = scoped_state_header ++
        \\type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}
        \\entry const answer = func () => return do:
        \\  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
        \\    break @effect.scope (func (s: State U32) => return do:
        \\      use previous <- Box.get ()
        \\      use Box.set (func () => return 0)
        \\      break previous ()
        \\    )
        \\  break result
    ;
    try checkScopedSource(allocator, text, null);
}

test "scoped effect direct scope callback preserves an older State cell without granting younger stores" {
    try directScopeOlderStateLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, directScopeOlderStateLaw, .{});
}

fn demandedConstructionLaw(allocator: std.mem.Allocator) !void {
    const prefix = scoped_state_header ++ "const delay = func ~value => return value\n";
    try checkScopedSource(allocator, prefix ++
        \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
        \\  let ignored = s
        \\  let pending = delay (@effect.scope (func (local: State U32) => return do (@effect.state local.get local.set 42):
        \\    break local.get ()
        \\  ))
        \\  use result <- @demand pending
        \\  let (state, value) = result
        \\  break value
        \\)
    , null);
    try checkScopedSource(allocator, prefix ++
        \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
        \\  let ignored = s
        \\  let pending = delay (do:
        \\    let local = 42
        \\    break local
        \\  )
        \\  use finished <- @demand pending
        \\  break finished
        \\)
    , null);
    try checkScopedSource(allocator, prefix ++
        \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
        \\  let pending = delay (do:
        \\    let captured = s
        \\    break 42
        \\  )
        \\  use finished <- @demand pending
        \\  break finished
        \\)
    , .capability_escape);
    try checkScopedSource(allocator, prefix ++
        \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
        \\  let pending = delay (do:
        \\    let captured = s.get
        \\    break 42
        \\  )
        \\  use finished <- @demand pending
        \\  break finished
        \\)
    , .capability_escape);
}
test "demand construction capture proof admits local values and rejects fresh authority independently of scalar result" {
    try demandedConstructionLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, demandedConstructionLaw, .{});
}

const generic_local_state_source = scoped_state_header ++
    \\type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}
    \\const store = func setter => return func value => return setter value
    \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
    \\  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
    \\    use store Box.set (func () => return do:
    \\      let (state, value) = do (@effect.state s.get s.set 42):
    \\        break s.get ()
    \\      break value
    \\    )
    \\    use callback <- Box.get ()
    \\    break callback ()
    \\  break result
    \\)
;
const generic_older_state =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}
    \\const store = func setter => return func value => return setter value
    \\entry const answer = func () => return do:
    \\  let (stored, result) = do (@effect.state Box.get Box.set (func () => return 0)):
    \\    break @effect.scope (func (s: State U32) => return do:
    \\      use store Box.set (func () => return do:
    \\        let (state, value) = do (@effect.state s.get s.set 42):
    \\          break s.get ()
    \\        break value
    \\      )
    \\      break 0
    \\    )
    \\  break result
;
const generic_ordinary_provider =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\type Box is effect = {get: Unit -> (Unit -> U32), set: (Unit -> U32) -> Unit}
    \\const store = func setter => return func value => return setter value
    \\entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
    \\  let result = do (@effect.provider Box.set (func value => return ())):
    \\    use store Box.set (func () => return do:
    \\      let (state, value) = do (@effect.state s.get s.set 42):
    \\        break s.get ()
    \\      break value
    \\    )
    \\    use callback <- Box.get ()
    \\    break callback ()
    \\  break result
    \\)
;
const generic_foreign_sink =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const store = func setter => return func value => return setter value
    \\const transfer = func (foreign: (Unit -> U32) -> Unit ! {Foreign}) => return @effect.scope (func (s: State U32) => return do:
    \\  use store foreign (func () => return do:
    \\    let (state, value) = do (@effect.state s.get s.set 42):
    \\      break s.get ()
    \\    break value
    \\  )
    \\  break 0
    \\)
    \\entry const answer = func () => return 42
;
fn genericStateStoreLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, generic_local_state_source, null);
    try checkScopedSource(allocator, generic_older_state, .capability_escape);
    try checkScopedSource(allocator, generic_ordinary_provider, .capability_escape);
    try checkScopedSource(allocator, generic_foreign_sink, .capability_escape);
}
test "generic setter invocation uses the actual installed State lifetime through OOM" {
    try genericStateStoreLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, genericStateStoreLaw, .{});
}

fn noStoreConditionLaw(allocator: std.mem.Allocator) !void {
    try checkScopedSource(allocator, scoped_state_header ++
        \\const bury = func value => return do:
        \\  let retained = [value]
        \\  break true
        \\const invoke = func value => return func callback => return callback value
        \\entry const bad = func () => return @effect.scope (func (state: State U32) => return invoke state (func actual => return if bury actual then 0 else 0))
    , .capability_escape);
    try checkScopedSource(allocator, scoped_state_header ++
        \\const copy = func value => return value
        \\const forward = func value => return copy value
        \\const invoke = func value => return func callback => return callback value
        \\entry const answer = func () => return @effect.scope (func (state: State U32) => return do:
        \\  let alias = invoke state (func actual => return forward actual)
        \\  let (stored, result) = do (@effect.state alias.get alias.set 7):
        \\    break alias.get ()
        \\  break result
        \\)
    , null);
}
test "scoped no store conditions require executable callback roles beyond ordinary result masks through OOM" {
    try noStoreConditionLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, noStoreConditionLaw, .{});
}

test "principal row substitution preserves Foreign callback authority and prefix labels" {
    const Copier = @import("check_scheme_import.zig").Copier;
    var producer = try T.Store.init(a);
    defer producer.deinit();
    const prefix = try producer.internOperation(.{ .unit = 41, .decl = 7 }, &.{T.u32_type});
    const public_row = try producer.freshEffects();
    const formal = producer.row(public_row).tail.variable;
    const prefixes = [_][]const T.Effects.Label{ &.{}, &.{T.foreign_operation}, &.{prefix} };
    for (prefixes, 0..) |labels, scenario| {
        var destination = try T.Store.init(a);
        defer destination.deinit();
        // Deliberately occupy the producer's local prefix ID in the reader.
        const unrelated = try destination.internOperation(.{ .unit = 52, .decl = 9 }, &.{T.f32_type});
        try std.testing.expectEqual(prefix, unrelated);
        const foreign_row = try destination.effects.row(&.{T.foreign_operation}, .closed);
        const row = try producer.effects.row(labels, producer.row(public_row).tail);
        const callback = try producer.functionWithEffects(T.unit, T.u32_type, row);
        const signature = try producer.functionWithEffects(T.u32_type, callback, 0);
        var copier: Copier = .{ .allocator = a, .source = .{ .store = &producer }, .destination = &destination };
        defer copier.deinit();
        try copier.row_variables.put(a, formal, foreign_row);
        const imported = try copier.copy(signature, 0);
        const imported_callback = destination.node(destination.node(imported).b);
        const imported_row = destination.row(imported_callback.c);
        const imported_labels = destination.rowLabels(imported_callback.c);
        try std.testing.expect(imported_row.tail == .closed);
        try std.testing.expectEqual(@as(usize, if (scenario == 2) 2 else 1), imported_labels.len);
        try std.testing.expect(std.mem.findScalar(T.Effects.Label, imported_labels, T.foreign_operation) != null);
        if (scenario == 2) {
            const relocated = imported_labels[0];
            try std.testing.expect(relocated != unrelated);
            const operation = destination.operation(relocated);
            try std.testing.expectEqualDeep((T.NominalIdentity{ .unit = 41, .decl = 7 }), operation.identity);
            try std.testing.expectEqualSlices(T.Id, &.{T.u32_type}, destination.list(operation.arguments));
        }
        // A closed pure callback must not accept an importer-erased Foreign row.
        const pure_callback = try destination.functionWithEffects(T.unit, T.u32_type, 0);
        const pure_signature = try destination.functionWithEffects(T.u32_type, pure_callback, 0);
        try std.testing.expectError(error.EffectMismatch, destination.unify(imported, pure_signature));
        const still_effectful = destination.node(destination.node(imported).b);
        try std.testing.expect(std.mem.findScalar(T.Effects.Label, destination.rowLabels(still_effectful.c), T.foreign_operation) != null);
    }
}
