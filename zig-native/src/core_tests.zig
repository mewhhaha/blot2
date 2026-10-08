const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const a = std.testing.allocator;

fn effectFixture() !Fixture {
    var fixture = try Fixture.init("entry const chronology = fn () => 42\nentry const principal = fn ~(value: U32) => @force value\n");
    errdefer fixture.deinit();
    var store = &fixture.checked.types;
    const early = try store.internOperation(.{ .unit = 7, .decl = 9 }, &.{types.u32_type});
    const late = try store.internOperation(.{ .unit = 7, .decl = 9 }, &.{types.f32_type});
    const row = try store.freshEffects();
    const row_variable = store.effects.node(row).tail.variable;
    const function = try store.functionWithEffects(types.unit, types.u32_type, row);
    const replacement = try store.fresh();
    try store.effects.appendVersion(row_variable, try store.effects.row(&.{early}, .closed));
    try store.appendVersion(replacement, function);
    try store.effects.appendVersion(row_variable, try store.effects.row(&.{late}, .closed));
    const normalized = try store.resolve(replacement, 0);
    const global = fixture.binding(0);
    fixture.checked.bindings[global].ty = normalized;
    fixture.checked.bindings[global].scheme.root = normalized;
    const open = try store.freshEffects();
    const variable = store.effects.node(open).tail.variable;
    const qualified = try store.effects.row(&.{ late, early, late }, .{ .variable = variable });
    const demand = try store.demandWithEffects(types.u32_type, qualified);
    const principal = try store.functionWithEffects(demand, types.u32_type, qualified);
    const principal_global = fixture.binding(1);
    fixture.checked.bindings[principal_global].ty = principal;
    fixture.checked.bindings[principal_global].scheme.root = principal;
    fixture.checked.bindings[principal_global].scheme.row_variables = try store.saveList(&.{variable});
    const lambda_source = fixture.tree.valueDecl(fixture.tree.roots.items[1]).body;
    const lambda = fixture.tree.node(lambda_source);
    fixture.checked.expr_types[lambda_source] = principal;
    fixture.checked.expr_types[lambda.a] = demand;
    fixture.checked.bindings[fixture.checked.resolved[lambda.a]].ty = demand;
    return fixture;
}
fn verifyEffects(module: *const core.Module, chronology: core.BindingId, principal: core.BindingId) !void {
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    const signature = module.types.node(module.binding(chronology).ty);
    const labels = module.types.rowLabels(signature.c);
    try std.testing.expectEqual(@as(usize, 1), labels.len);
    const operation = module.types.operation(labels[0]);
    try std.testing.expectEqual(types.NominalIdentity{ .unit = 7, .decl = 9 }, operation.identity);
    try std.testing.expectEqualSlices(types.Id, &.{types.f32_type}, module.types.operationArguments(labels[0]));
    try std.testing.expectEqual(@as(types.Cursor, 0), module.types.row(signature.c).cursor);
    try std.testing.expectEqual(types.Effects.Tail.closed, std.meta.activeTag(module.types.row(signature.c).tail));
    const scheme = module.binding(principal).scheme;
    const arrow = module.types.node(scheme.root);
    const demand = module.types.node(arrow.a);
    try std.testing.expectEqual(types.Tag.demand, demand.tag);
    try std.testing.expectEqual(arrow.c, demand.c);
    const qualified = module.types.row(arrow.c);
    const quantified = module.types.list(scheme.row_variables);
    try std.testing.expectEqualSlices(u32, &.{qualified.tail.variable}, quantified);
    try std.testing.expect(module.types.effects.variable_count >= 1);
    try std.testing.expect(qualified.tail.variable < module.types.effects.variable_count);
    const carried = module.types.rowLabels(arrow.c);
    try std.testing.expectEqual(@as(usize, 3), carried.len);
    try std.testing.expectEqual(carried[0], carried[2]);
    try std.testing.expect(carried[0] != carried[1]);
    try std.testing.expectEqualSlices(types.Id, &.{types.u32_type}, module.types.operationArguments(carried[1]));
}
test "frozen effect rows own exact operation arguments and principal tails after frontend teardown" {
    var fixture = try effectFixture();
    const chronology = fixture.binding(0);
    const principal = fixture.binding(1);
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try verifyEffects(&module, chronology, principal);
}
fn effectPublicationFailures(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try verifyEffects(&module, fixture.binding(0), fixture.binding(1));
}
test "effect row and operation publication release every failed allocation" {
    var fixture = try effectFixture();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, effectPublicationFailures, .{&fixture});
}

fn operationFixture() !Fixture {
    var fixture = try Fixture.init("const identity = fn (value: U32) -> U32 => value\nentry const alias = identity\n");
    errdefer fixture.deinit();
    var checked = &fixture.checked;
    const source = fixture.tree.valueDecl(fixture.tree.roots.items[1]).body;
    const identity: types.NominalIdentity = .{ .unit = 17, .decl = 23 };
    const argument = try checked.types.nominal(.{ .unit = 11, .decl = 29 }, &.{types.f32_type});
    const label = try checked.types.internOperation(identity, &.{argument});
    const row = try checked.types.effects.row(&.{label}, .closed);
    const signature = try checked.types.functionWithEffects(types.u32_type, types.u32_type, row);
    const alias = fixture.binding(1);
    checked.bindings[alias].ty = signature;
    checked.bindings[alias].scheme.root = signature;
    checked.expr_types[source] = signature;
    const index = checked.effect_templates.len;
    checked.effect_templates = try a.realloc(checked.effect_templates, index + 1);
    checked.effect_templates[index] = .{ .identity = identity, .family = 0, .name = 0, .parameter = types.u32_type, .result = types.u32_type };
    checked.operation_uses = try a.realloc(checked.operation_uses, 1);
    checked.operation_uses[0] = .{ .node = source, .template = @intCast(index), .arguments = try checked.types.saveList(&.{argument}), .signature = signature };
    checked.operation_refs[source] = 1;
    return fixture;
}
fn verifyOperation(module: *const core.Module, alias: core.BindingId) !void {
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    const root = module.body(alias).?.root;
    try std.testing.expectEqual(core.Tag.operation_value, module.node(root).tag);
    const value = module.operationValue(root);
    try std.testing.expectEqual(types.NominalIdentity{ .unit = 17, .decl = 23 }, value.identity);
    const arguments = module.operationValueArguments(root);
    try std.testing.expectEqual(@as(usize, 1), arguments.len);
    const argument = module.types.node(arguments[0]);
    try std.testing.expectEqual(types.Tag.nominal, argument.tag);
    try std.testing.expectEqual(@as(u32, 11), argument.a);
    try std.testing.expectEqual(@as(u32, 29), argument.b);
    try std.testing.expectEqualSlices(types.Id, &.{types.f32_type}, module.types.nominalArguments(argument));
    const arrow = module.types.node(value.signature);
    const label = module.types.rowLabels(arrow.c)[0];
    try std.testing.expectEqual(value.identity, module.types.operation(label).identity);
    try std.testing.expectEqualSlices(types.Id, arguments, module.types.operationArguments(label));
}
fn operationPublicationFailures(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try verifyOperation(&module, fixture.binding(1));
}
test "operation callable publication owns producer identity and nominal arguments after source teardown" {
    var fixture = try operationFixture();
    const alias = fixture.binding(1);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, operationPublicationFailures, .{&fixture});
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try verifyOperation(&module, alias);
}

test "source providers preserve operation type arguments as metadata" {
    const sources = [_][]const u8{
        \\type Read is effect = { first: Unit -> U32, second: Unit -> U32 }
        \\const outer = @effect.provider Read.first (fn () => 20)
        \\const second = @effect.provider Read.second (fn () => Read.first ())
        \\entry const answer = do outer:
        \\  return do second:
        \\    return Read.second ()
        ,
        \\type State a is effect = { get: Unit -> a, set: a -> Unit }
        \\const provider = @effect.state (State.get (Array U32)) (State.set (Array U32)) #[41]
        \\entry const answer = do provider:
        \\  return State.get (Array U32) ()
        ,
    };
    for (sources) |source| {
        var fixture = try Fixture.init(source);
        defer fixture.deinit();
        var module = try fixture.lower(a);
        defer module.deinit(a);
        for (module.diagnostics) |diagnostic| std.debug.print("core:{d}..{d}: {s}\n", .{ diagnostic.span.start, diagnostic.span.end, diagnostic.message() });
        try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
        var operation_count: usize = 0;
        for (module.nodes) |node| if (node.tag == .operation_value) {
            operation_count += 1;
        };
        try std.testing.expect(operation_count >= 3);
    }
}

fn runnerFixture() !Fixture {
    return Fixture.init(
        \\type State a is effect = { get: Unit -> a, set: a -> Unit }
        \\const run = fn initial => fn action => @effect.run State.get State.set initial action
        \\entry const answer = fn () => do:
        \\  let (next, old) = run 41 (fn () => do:
        \\    use old <- State.get ()
        \\    use State.set (@u32.add old 1)
        \\    return old)
        \\  return @u32.add next old
    );
}
fn verifyRunner(module: *const core.Module, source_bindings: usize) !void {
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 1), module.handle_effects.len);
    const metadata = module.handle_effects[0];
    const handler = module.node(metadata.node);
    try std.testing.expectEqual(core.Tag.handle, handler.tag);
    try std.testing.expectEqual(@as(u32, 1), handler.c);
    try std.testing.expectEqual(core.Tag.state_provider, module.node(handler.a).tag);
    try std.testing.expectEqual(core.Tag.apply, module.node(handler.b).tag);
    const read = module.types.node(metadata.first);
    const write = module.types.node(metadata.second);
    try std.testing.expectEqual(types.Tag.nominal, read.tag);
    try std.testing.expectEqual(types.Tag.nominal, write.tag);
    try std.testing.expectEqual(read.a, write.a);
    try std.testing.expect(read.b != write.b);
    try std.testing.expectEqualSlices(types.Id, module.types.nominalArguments(read), module.types.nominalArguments(write));
    try std.testing.expectEqual(types.Tag.variable, module.types.node(module.types.nominalArguments(read)[0]).tag);
    try std.testing.expect(module.bindings.len > source_bindings);
}
fn runnerPublicationFailures(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try verifyRunner(&module, fixture.checked.bindings.len);
}
test "runner publication owns generic token equations and staged operand bindings after frontend teardown" {
    var fixture = try runnerFixture();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, runnerPublicationFailures, .{&fixture});
    const bindings = fixture.checked.bindings.len;
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try verifyRunner(&module, bindings);
}

const Fixture = struct {
    tree: ast.Tree,
    pool: symbols.Pool,
    checked: check.Checked,
    fn init(source: []const u8) !Fixture {
        var lexed = try lexer.lex(a, source);
        defer lexed.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), lexed.diagnostics.items.len);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(a);
        var tree = try parser.parse(a, source, lexed.tokens.items, &pool);
        errdefer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(a, &tree, &pool);
        errdefer checked.deinit(a);
        for (checked.diagnostics) |diagnostic| std.debug.print("semantic:{d}: {s}\n", .{ diagnostic.span.start, diagnostic.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        return .{ .tree = tree, .pool = pool, .checked = checked };
    }
    fn deinit(self: *Fixture) void {
        self.checked.deinit(a);
        self.tree.deinit(a);
        self.pool.deinit(a);
    }
    fn lower(self: *const Fixture, allocator: std.mem.Allocator) !core.Module {
        return core.lower(allocator, &self.tree, &self.pool, &self.checked);
    }
    fn binding(self: *const Fixture, declaration_index: usize) check.BindingId {
        var index: usize = 0;
        for (self.tree.roots.items) |id| if (self.tree.node(id).tag == .value_decl) {
            if (index == declaration_index) return self.checked.resolved[id];
            index += 1;
        };
        unreachable;
    }
};

test "one typed body retains principal numeric identity across U32 and F32 uses" {
    const source =
        \\infixl 60 (+) = _fixity_add
        \\const twice = fn x => x + x
        \\entry const integer = fn () -> U32 => twice 21
        \\entry const floating = fn () -> F32 => twice 1.5
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    ;
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var module = try fixture.lower(a);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 4), module.body_lowerings);
    const twice = module.body(fixture.binding(0)).?;
    const signature = module.types.node(twice.scheme.root);
    const variables = module.types.list(twice.scheme.variables);
    const variable = signature.a;
    try std.testing.expectEqual(@as(usize, 2), variables.len);
    try std.testing.expect(std.mem.findScalar(types.Id, variables, signature.a) != null);
    try std.testing.expect(std.mem.findScalar(types.Id, variables, signature.b) != null);
    try std.testing.expect(signature.a != signature.b);
    try std.testing.expectEqual(variable, module.bodyParameters(twice)[0].ty);
    const sum = module.node(twice.root);
    try std.testing.expectEqual(core.Tag.call, sum.tag);
    const selected = module.call(twice.root);
    try std.testing.expectEqual(fixture.binding(3), selected.target.binding);
    try std.testing.expectEqual(variable, module.typeOf(selected.arguments[0]));
    try std.testing.expectEqual(variable, module.typeOf(selected.arguments[1]));
    try std.testing.expectEqual(signature.b, sum.ty);
    const producer = module.node(module.body(selected.target.binding).?.root);
    try std.testing.expectEqual(core.Tag.associated, producer.tag);
    try std.testing.expectEqual(core.Op.add, producer.op);
    try std.testing.expectEqual(@as(u32, 1), twice.scheme.obligations.len);
    const constraint = module.obligations[twice.scheme.obligations.start];
    try std.testing.expectEqual(types.ObligationKind.dispatch, constraint.kind);
    try std.testing.expectEqual(variable, constraint.ty);
    try std.testing.expectEqual(variable, constraint.other);
    try std.testing.expectEqual(signature.b, constraint.result);
    try std.testing.expectEqual(types.Operator.add, constraint.operator);
    const integer = module.call(module.body(fixture.binding(1)).?.root);
    const floating = module.call(module.body(fixture.binding(2)).?.root);
    try std.testing.expectEqual(integer.target, floating.target);
    try std.testing.expectEqual(fixture.binding(0), integer.target.binding);
    try std.testing.expectEqual(types.u32_type, module.types.node(integer.callee_type).a);
    try std.testing.expectEqual(types.f32_type, module.types.node(floating.callee_type).a);
    try std.testing.expect(module.nodes.len < fixture.tree.nodes.items.len);
}

test "published unbound cursor views freeze to one principal variable identity" {
    var fixture = try Fixture.init("entry const identity = fn value => value\n");
    defer fixture.deinit();
    const global = fixture.binding(0);
    const lambda = fixture.tree.node(fixture.tree.valueDecl(fixture.tree.roots.items[0]).body);
    const parameter = fixture.checked.resolved[lambda.a];
    const variable = try fixture.checked.types.fresh();
    try fixture.checked.types.appendVersion(variable, types.u32_type);
    const cursor = fixture.checked.types.cursor();
    const first = try fixture.checked.types.resolve(variable, cursor);
    const second = try fixture.checked.types.resolve(variable, cursor + 1);
    try std.testing.expect(first != second);
    const root = try fixture.checked.types.function(first, second);
    fixture.checked.bindings[global].ty = root;
    fixture.checked.bindings[global].scheme = .{ .root = root, .variables = try fixture.checked.types.saveList(&.{first}) };
    fixture.checked.bindings[parameter].ty = second;
    fixture.checked.bindings[parameter].scheme = .{ .root = second };
    fixture.checked.expr_types[lambda.a] = second;
    fixture.checked.expr_types[lambda.b] = second;
    var module = try fixture.lower(a);
    defer module.deinit(a);
    const body = module.body(global).?;
    const frozen = module.types.list(body.scheme.variables)[0];
    const signature = module.types.node(body.scheme.root);
    try std.testing.expectEqual(frozen, signature.a);
    try std.testing.expectEqual(frozen, signature.b);
    try std.testing.expectEqual(frozen, module.typeOf(body.root));
    try std.testing.expectEqual(frozen, module.bodyParameters(body)[0].ty);
}

test "typed core owns export bytes types spans and control after syntax teardown" {
    const source =
        \\infixl 60 (+) = _fixity_add
        \\entry const nested = fn (flag: Bool) -> U32 => do:
        \\  let value = 1
        \\  if flag:
        \\    value := 2
        \\  else:
        \\    value := 3
        \\  let inner = do:
        \\    if flag:
        \\      return 20
        \\    return 21
        \\  return value + inner
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    ;
    var fixture = try Fixture.init(source);
    const global = fixture.binding(0);
    var module = try fixture.lower(a);
    fixture.deinit();
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    const body = module.body(global).?;
    try std.testing.expectEqualStrings("nested", module.name(body.export_name));
    try std.testing.expectEqual(types.boolean, module.bodyParameters(body)[0].ty);
    const statements = module.children(body.root);
    try std.testing.expectEqual(core.Tag.block, module.node(body.root).tag);
    const conditional = statements[1];
    try std.testing.expectEqual(core.Tag.if_stmt, module.node(conditional).tag);
    try std.testing.expectEqual(core.Tag.suite, module.node(module.node(conditional).b).tag);
    try std.testing.expectEqual(@as(usize, 1), module.branchMerges(conditional).len);
    const merge = module.branchMerges(conditional)[0];
    try std.testing.expect(merge.result != merge.then_binding and merge.result != merge.else_binding);
    const inner = module.node(statements[2]).b;
    try std.testing.expectEqual(core.Tag.block, module.node(inner).tag);
    const inner_statements = module.children(inner);
    const inner_if = module.node(inner_statements[0]);
    const branch_return = module.node(module.children(inner_if.b)[0]);
    try std.testing.expectEqual(core.Tag.return_, branch_return.tag);
    try std.testing.expectEqual(inner, branch_return.b);
    try std.testing.expectEqual(inner, module.node(inner_statements[1]).b);
    try std.testing.expectEqual(body.root, module.node(statements[3]).b);
    const span = module.span(statements[3]);
    try std.testing.expectEqualStrings("return value + inner", source[span.start..span.end]);
}

test "lowering preserves unreachable traps and lazy Boolean control without evaluation" {
    var fixture = try Fixture.init(
        \\infixr 25 (&&) = _fixity_and
        \\infix 30 (==) = _fixity_eq
        \\const unused = @u32.div 1 0
        \\entry const safe = (@u32.eq 0 1) && (@u32.div 1 0 == 0)
        \\entry const chosen = if @u32.eq 1 1 then 42 else @u32.div 1 0
        \\const _fixity_and = fn (left: Bool) => fn ~(right: Bool) => if left then @force right else #False
        \\const _fixity_eq = fn left => fn right => @type.call "eq" left right
    );
    defer fixture.deinit();
    var module = try fixture.lower(a);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(core.Op.div, module.node(module.body(fixture.binding(0)).?.root).op);
    const logical = module.node(module.body(fixture.binding(1)).?.root);
    try std.testing.expectEqual(core.Tag.call, logical.tag);
    const demand_call = module.call(module.body(fixture.binding(1)).?.root);
    try std.testing.expectEqual(core.Tag.suspend_, module.node(demand_call.arguments[1]).tag);
    try std.testing.expectEqual(core.Tag.if_value, module.node(module.body(demand_call.target.binding).?.root).tag);
    try std.testing.expectEqual(core.Tag.if_value, module.node(module.body(fixture.binding(2)).?.root).tag);
}

test "user fixity resolves to numeric named calls and global aliases stay references" {
    var fixture = try Fixture.init(
        \\infixl 60 (+) = combine
        \\const combine = fn left => fn right => @u32.sub left right
        \\const alias = combine
        \\entry const answer = fn () -> U32 => 44 + 2
    );
    defer fixture.deinit();
    var module = try fixture.lower(a);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    const combine = fixture.binding(0);
    const alias = module.body(fixture.binding(1)).?;
    try std.testing.expect(!alias.is_function);
    try std.testing.expectEqual(combine, module.reference(alias.root).binding);
    const call = module.call(module.body(fixture.binding(2)).?.root);
    try std.testing.expectEqual(combine, call.target.binding);
    try std.testing.expectEqual(@as(usize, 2), call.arguments.len);
}

test "ordinary function wrappers retain authoritative fully applied compiler operations" {
    var fixture = try Fixture.init("const primitive = fn left => fn right => @u32.add left right\n");
    defer fixture.deinit();
    var module = try fixture.lower(a);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    const root = module.body(fixture.binding(0)).?.root;
    try std.testing.expectEqual(core.Tag.scalar, module.node(root).tag);
    try std.testing.expectEqual(core.Op.add, module.node(root).op);
    try std.testing.expectEqual(@as(u32, 0), module.node(root).c);
    try std.testing.expectEqual(@as(usize, 2), module.bodyParameters(module.body(fixture.binding(0)).?).len);
    try std.testing.expectEqual(@as(usize, 0), module.primitives.len);
}

test "foreign aliases and grouped namespaces retain producer identities after all frontends close" {
    var module = lowered: {
        var producer = try Fixture.init("entry const identity = fn value => value\n");
        defer producer.deinit();
        const producer_binding = producer.binding(0);
        const source =
            \\import * as lib from "./producer.blot"
            \\const alias = lib.identity
            \\entry const integer = fn () -> U32 => (lib).identity 42
            \\entry const floating = fn () -> F32 => lib.identity 1.5
        ;
        var lexed = try lexer.lex(a, source);
        defer lexed.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, source, lexed.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        const imports = [_]check.ImportedBinding{.{
            .namespace = try pool.intern(a, "lib"),
            .member = try pool.intern(a, "identity"),
            .target = .{ .unit = 7, .binding = producer_binding },
            .interface = .{ .types = .{ .store = &producer.checked.types }, .scheme = producer.checked.bindings[producer_binding].scheme, .obligations = producer.checked.obligations },
            .origin = tree.roots.items[0],
        }};
        var checked = try check.checkWithImports(a, &tree, &pool, &imports);
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        break :lowered try core.lower(a, &tree, &pool, &checked);
    };
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 3), module.body_lowerings);
    const alias = module.bodies[1];
    const target = module.reference(alias.root);
    try std.testing.expectEqual(@as(u32, 7), target.unit);
    try std.testing.expectEqual(@as(core.BindingId, 1), target.binding);
    const integer = module.call(module.bodies[2].root);
    const floating = module.call(module.bodies[3].root);
    try std.testing.expectEqual(target, integer.target);
    try std.testing.expectEqual(target, floating.target);
    try std.testing.expectEqual(types.u32_type, module.types.node(integer.callee_type).a);
    try std.testing.expectEqual(types.f32_type, module.types.node(floating.callee_type).a);
    try std.testing.expectEqualStrings("integer", module.name(module.bodies[2].export_name));
}

fn allocationScenario(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 5), module.body_lowerings);
}
test "every typed core allocation failure releases partial projected artifacts" {
    var fixture = try Fixture.init(
        \\infixl 60 (+) = _fixity_add
        \\const twice = fn x => x + x
        \\entry const integer = fn () -> U32 => twice 21
        \\entry const floating = fn () -> F32 => twice 1.5
        \\entry const branch = fn (flag: Bool) -> U32 => do:
        \\  let value = 1
        \\  if flag:
        \\    value := 2
        \\  return value
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    );
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationScenario, .{&fixture});
}

test "ordinary calls use bounded scratch rather than two heap allocations per occurrence" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "infixl 60 (+) = _fixity_add\nconst twice = fn x => x + x\nentry const driver = fn () -> U32 => do:\n");
    for (0..1024) |_| try source.appendSlice(a, "  let value = twice 21\n");
    try source.appendSlice(a, "  return value\nconst _fixity_add = fn left => fn right => @u32.add left right\n");
    var fixture = try Fixture.init(source.items);
    defer fixture.deinit();
    var tracked: memory.TrackedAllocator = .{ .backing = a };
    var module = try fixture.lower(tracked.allocator());
    errdefer module.deinit(tracked.allocator());
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    try std.testing.expectEqual(@as(usize, 3), module.body_lowerings);
    try std.testing.expectEqual(@as(usize, 1025), module.calls.len);
    // Flat owned tables grow geometrically. Restoring one or two allocator
    // roundtrips per ordinary call would exceed this structural bound.
    std.debug.print("core 1024 calls: {d} allocations, {d} requested bytes, {d} peak bytes\n", .{ tracked.counts.allocations, tracked.counts.allocated_bytes, tracked.counts.peak_bytes });
    try std.testing.expect(tracked.counts.allocations < 256);
    module.deinit(tracked.allocator());
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
}

fn longCallFixture() !Fixture {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "const many = ");
    for (0..33) |_| try source.appendSlice(a, "fn x => ");
    try source.appendSlice(a, "x\nentry const driver = fn () -> U32 => many");
    for (0..33) |index| {
        var buffer: [16]u8 = undefined;
        try source.appendSlice(a, try std.mem.print(&buffer, " {d}", .{index}));
    }
    try source.appendSlice(a, "\n");
    return Fixture.init(source.items);
}
fn longCallAllocationScenario(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var module = try fixture.lower(allocator);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    const call = module.call(module.body(fixture.binding(1)).?.root);
    try std.testing.expectEqual(@as(usize, 33), call.arguments.len);
    for (call.arguments, 0..) |argument, index| try std.testing.expectEqual(@as(u32, @intCast(index)), module.node(argument).a);
}
test "larger calls preserve argument order and release every heap fallback on allocation failure" {
    var fixture = try longCallFixture();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, longCallAllocationScenario, .{&fixture});
}
