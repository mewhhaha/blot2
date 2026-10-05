const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, interfaceImport, .{});
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
    const text = "const alias = source\nentry const answer = fn () => do:\n  let local = source\n  return 42\n";
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, retainedCertificates, .{});
}
fn ambientReadScenario(allocator: std.mem.Allocator) !void {
    const text =
        \\const ignore = fn ~value => 42
        \\const force = fn ~value => @force value
        \\entry const ignored = ignore (read ())
        \\entry const forced = fn () => force (read ())
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, ambientReadScenario, .{});
}
test "pure initializer and callback constraints retain their distinct effect diagnostics" {
    const cases = [_]struct { source: []const u8, code: check.Code }{
        .{ .source = "entry const answer = read ()\n", .code = .const_effect },
        .{ .source = "entry const answer = fn () => do:\n  let value = read ()\n  return value\n", .code = .let_effect },
        .{ .source = "const run = fn (callback:Unit -> U32) => callback ()\nentry const answer = fn () => run read\n", .code = .effect_mismatch },
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
        \\const same = fn left => fn right => @type.same left right
        \\const invoke = fn callback => callback ()
        \\entry const answer = same (fn () -> Phantom U32 => #Phantom) (fn () -> Phantom F32 => #Phantom)
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
        \\const N.add = fn left => fn right => read ()
        \\const N.get = fn value => read ()
        \\const N.make = fn () => #N (read ())
        \\entry const binary = fn () => #N 1 + #N 2
        \\entry const unary = fn () => (#N 1).get
        \\entry const result = fn () -> N => @type.result "make" ()
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, declarationCatalogs, .{});
}

fn sourceOperationValues(allocator: std.mem.Allocator) !void {
    const text =
        \\effect Counter: Unit -> U32
        \\type Reader a is effect = { ask: Unit -> a }
        \\type PairRead [left,right] is effect = { first: Unit -> left }
        \\type Phantom a is data = #Phantom
        \\const counter = Counter
        \\const ask = Reader.ask
        \\const read = fn () -> U32 => ask ()
        \\const explicit = Reader.ask U32
        \\const shaped = PairRead.first [U32,F32]
        \\const phantom_u32 = Reader.ask (Phantom U32)
        \\const phantom_f32 = Reader.ask (Phantom F32)
        \\const driver = fn () => do:
        \\  let local = Reader.ask
        \\  use value <- local ()
        \\  return @u32.add value 1
    ;
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    for (tree.diagnostics.items) |diagnostic| std.debug.print("effect fixture syntax {s}:{d}..{d}\n", .{ @tagName(diagnostic.code), diagnostic.start, diagnostic.end });
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, sourceOperationValues, .{});
}
test "operation invocations preserve pure initializer annotation and sealed label diagnostics" {
    const cases = [_]struct { source: []const u8, code: check.Code }{
        .{ .source = "effect Read:Unit -> U32\nconst invalid=Read ()\n", .code = .const_effect },
        .{ .source = "effect Read:Unit -> U32\nconst invalid=fn () => do:\n  let value=Read ()\n  return value\n", .code = .let_effect },
        .{ .source = "effect Read:Unit -> U32\nconst invalid:Unit -> U32=fn () => Read ()\n", .code = .effect_mismatch },
        .{ .source = "effect Foreign:Unit -> U32\n", .code = .sealed_effect },
        .{ .source = "effect Read:Unit -> U32\nconst Read=fn () => 42\n", .code = .duplicate_name },
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
        \\const provider = @effect.provider Read (fn () => 42)
        \\const read = fn () => Read ()
        \\const invoke = fn callback => callback ()
        \\const force = fn ~value => @force value
        \\const ignore = fn ~value => 42
        \\entry const direct = fn () => do provider:
        \\  return read ()
        \\entry const callback = fn () => do provider:
        \\  return invoke (fn () => Read ())
        \\entry const delayed = fn () => do provider:
        \\  return force (Read ())
        \\entry const ignored = fn () => ignore (Read ())
        \\type State a is effect = { get:Unit -> a, set:a -> Unit }
        \\const state_provider = @effect.state (State.get (Array U32)) (State.set (Array U32)) #[41]
        \\entry const stateful = fn () => do state_provider:
        \\  use old <- State.get (Array U32) ()
        \\  let next = @array.set old 0 42
        \\  use State.set (Array U32) next
        \\  return old
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, providerSource, .{});
}
test "provider primitive targets arity sealed labels and signatures match source restrictions" {
    const cases = [_]struct { source: []const u8, code: check.Code }{
        .{ .source = "effect Read:Unit -> U32\nconst alias=Read\nconst invalid=@effect.provider alias (fn () => 42)\n", .code = .operation_target },
        .{ .source = "type Read a is effect = { get:Unit -> a }\nconst invalid=@effect.provider Read.get (fn () => 42)\n", .code = .operation_target },
        .{ .source = "effect Read:Unit -> U32\nconst invalid=@effect.provider Read (fn () => #True)\n", .code = .type_mismatch },
        .{ .source = "const invalid=@effect.provider Foreign (fn () => 42)\n", .code = .sealed_effect },
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
        \\const use_alias = fn () -> U32 => alias ()
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, importedCatalogs, .{});
}

fn runnerSource(allocator: std.mem.Allocator) !void {
    const text =
        \\type State state is effect = { get:Unit -> state, set:state -> Unit }
        \\const run = fn initial => fn action => @effect.run State.get State.set initial action
        \\entry const answer = fn () => do:
        \\  let (next,previous) = run 41 (fn () => do:
        \\    use previous <- State.get ()
        \\    use State.set (@u32.add previous 1)
        \\    return previous)
        \\  return @u32.add next previous
        \\entry const reader = fn () -> U32 => @effect.reader State.get (fn () -> U32 => @panic "witness called") (fn () => 42) (fn () -> U32 => State.get ())
        \\entry const writer = fn () => @effect.run State.get State.set 0 (fn () => @effect.writer State.set (fn () -> U32 => @panic "witness called") (fn value => State.set value) (fn () => do:
        \\  use State.set 42
        \\  return 42))
    ;
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("RUNNER_DIAGNOSTIC {s} at {d}..{d}\n", .{ @tagName(diagnostic.code), diagnostic.span.start, diagnostic.span.end });
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, runnerSource, .{});
}

fn importedRunners(allocator: std.mem.Allocator) !void {
    const producer_text =
        \\type State state is effect = { get:Unit -> state, set:state -> Unit }
        \\const run = fn initial => fn action => @effect.run State.get State.set initial action
    ;
    const consumer_text =
        \\entry const integer = fn () => @product.get (run 42 (fn () -> U32 => source.State.get ())) 1
        \\entry const floating = fn () => @product.get (run 1.25 (fn () -> F32 => source.State.get ())) 1
        \\entry const direct = fn () -> U32 => @effect.reader source.State.get (fn () -> U32 => @panic "unused witness") (fn () => 42) (fn () -> U32 => source.State.get ())
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, importedRunners, .{});
}

test "effect runner template families arity and signatures match frozen negative admission" {
    const cases = [_]struct { name: []const u8, source: []const u8, code: check.Code }{
        .{ .name = "alias_template", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nconst alias = State.get\nentry const answer = fn () => @effect.reader alias 0 (fn () => 42) (fn () -> U32 => State.get ())\n", .code = .operation_target },
        .{ .name = "explicit_template", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = fn () => @effect.reader (State.get U32) 0 (fn () => 42) (fn () -> U32 => State.get ())\n", .code = .operation_target },
        .{ .name = "zero_binder", .source = "type State is effect = { get: Unit -> U32, set: U32 -> Unit }\nentry const answer = fn () => @effect.run State.get State.set 0 (fn () => 42)\n", .code = .operation_target },
        .{ .name = "shaped_binder", .source = "type State [a] is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = fn () => @effect.run State.get State.set 0 (fn () => 42)\n", .code = .type_arity },
        .{ .name = "multiple_binders", .source = "type State a => type b is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = fn () => @effect.run State.get State.set 0 (fn () => 42)\n", .code = .type_arity },
        .{ .name = "different_family", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\ntype Other a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = fn () => @effect.run State.get Other.set 0 (fn () => 42)\n", .code = .effect_family },
        .{ .name = "swapped_pair", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = fn () => do:\n  let (next,result) = @effect.run State.set State.get 0 (fn () => 42)\n  return @u32.add next result\n", .code = .type_mismatch },
        .{ .name = "duplicate_operation", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = fn () => do:\n  let (next,result) = @effect.run State.get State.get 0 (fn () => 42)\n  return @u32.add next result\n", .code = .invalid_state_provider },
        .{ .name = "wrong_implementation", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = fn () => @effect.reader State.get 0 (fn () => #True) (fn () -> U32 => State.get ())\n", .code = .type_mismatch },
        .{ .name = "wrong_action_parameter", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = fn () => @effect.run State.get State.set 0 (fn (value:U32) => value)\n", .code = .type_mismatch },
        .{ .name = "partial_run", .source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nentry const answer = fn () => @effect.run State.get State.set 0\n", .code = .call_arity },
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
        if (checked.diagnostics.len == 0) std.debug.print("MISSING_RUNNER_DIAGNOSTIC {s}\n", .{item.name});
        try std.testing.expect(checked.diagnostics.len != 0);
        if (checked.diagnostics[0].code != item.code) std.debug.print("RUNNER_NEGATIVE {s}: expected {s}, actual {s}\n", .{ item.name, @tagName(item.code), @tagName(checked.diagnostics[0].code) });
        try std.testing.expectEqual(item.code, checked.diagnostics[0].code);
    }
}

test "reader witnesses do not invent result links and forwarding implementations retain outward effects" {
    const text =
        \\type State state is effect = { get:Unit -> state, set:state -> Unit }
        \\entry const unannotated = fn () => @effect.reader State.get 0 (fn () => 42) (fn () => State.get ())
        \\entry const forwarding = fn () -> U32 => @effect.reader State.get 0 (fn () -> U32 => State.get ()) (fn () -> U32 => State.get ())
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
    const layout = @import("layout.zig");
    const text =
        \\type State state is effect = { get:Unit -> state, set:state -> Unit }
        \\entry const answer = fn () -> U32 => @effect.reader State.get (fn () -> U32 => @panic "witness called") (fn () => 42) (fn () -> U32 => State.get ())
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
        \\const invoke = fn action => action 7
        \\const call = fn (io:U32 -> U32 ! {Foreign}) => invoke io
        \\const retain = fn (io:U32 -> U32 ! {Foreign}) => fn value => io value
        \\const outer = fn (io:U32 -> U32 -> U32 ! {Foreign}) => ()
        \\const inner = fn (io:U32 -> (U32 -> U32 ! {Foreign})) => ()
        \\const pure = fn (io:U32 -> U32 ! {}) => io 1
        \\const duplicates = fn (io:U32 -> U32 ! {Foreign,Foreign}) => io 1
        \\const mixed = fn (io:Unit -> U32 ! {Read,Foreign,Read}) => io ()
        \\entry const answer = fn (io:U32 -> U32 ! {Foreign}) => call io
    ;
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("FOREIGN_ANNOTATION {s} at {d}..{d}\n", .{ @tagName(diagnostic.code), diagnostic.span.start, diagnostic.span.end });
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, foreignAnnotations, .{});
}

test "sealed Foreign annotations keep exact negative admission and ordinary shadowing" {
    const cases = [_]struct { source: []const u8, code: check.Code }{
        .{ .source = "const invalid=fn (value:U32 ! {Foreign}) => value\n", .code = .invalid_effect_annotation },
        .{ .source = "const invalid=fn () -> U32 ! {Foreign} => 42\n", .code = .invalid_effect_annotation },
        .{ .source = "const invalid=fn (io:U32 -> U32 ! {Missing}) => io\n", .code = .unknown_effect },
        .{ .source = "const invalid=fn (io:U32 -> U32 ! {Foreign U32}) => io\n", .code = .type_arity },
        .{ .source = "effect Read:Unit -> U32 ! {Foreign}\n", .code = .operation_signature },
        .{ .source = "const invalid=fn (io:U32 -> U32 ! {Foreign}) => do:\n  let value=io 1\n  return value\n", .code = .let_effect },
        .{ .source = "const callback:U32 -> U32 ! {Foreign}=fn value=>value\nentry const invalid=callback 1\n", .code = .const_effect },
        .{ .source = "const pure=fn (io:U32 -> U32)=>io 1\nconst invalid=fn (io:U32 -> U32 ! {Foreign})=>pure io\n", .code = .effect_mismatch },
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
        if (checked.diagnostics[0].code != item.code) std.debug.print("FOREIGN_NEGATIVE expected {s} actual {s}\n", .{ @tagName(item.code), @tagName(checked.diagnostics[0].code) });
        try std.testing.expectEqual(item.code, checked.diagnostics[0].code);
    }
    const text = "type Foreign is data = #Foreign\nconst Foreign=42\nconst read=fn (io:U32 -> U32 ! {Foreign})=>io 1\n";
    var tokens = try lexer.lex(a, text);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.check(a, &tree, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    for (checked.bindings) |binding| if (binding.kind == .global and binding.name == pool.lookup("read").?) {
        try std.testing.expectEqualSlices(u32, &.{T.foreign_operation}, checked.types.rowLabels(checked.types.node(binding.scheme.root).c));
    };
}
