const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const a = std.testing.allocator;
fn scenario(allocator: std.mem.Allocator, source: []const u8, expected: ?check.Code) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var result = try check.checkModule(allocator, &tree, &names, &.{}, &.{}, 1);
    defer result.deinit(allocator);
    if (expected) |code| {
        for (result.diagnostics) |issue| if (issue.code == code) return;
        for (result.diagnostics) |issue| std.debug.print("implementation diagnostic: {s} at {d}\n", .{ @tagName(issue.code), issue.span.start });
        return error.TestUnexpectedResult;
    }
    for (result.diagnostics) |issue| std.debug.print("implementation diagnostic: {s} at {d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try std.testing.expect(result.implementations.len != 0);
}
test "implementation heads are explicitly determined and visible coherence ignores prerequisites" {
    const good = "type Source s is contract = { type Item }\nimpl ArraySource a : Source (Array a) = { type Item = a }\nimpl Scalar : Source U32 = { type Item = U32 }\n";
    try scenario(a, good, null);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, scenario, .{ good, @as(?check.Code, null) });
    try scenario(a, "type Source s is contract = { type Item }\nimpl Bad a : Source U32 = { type Item = a }\n", .undetermined_implementation);
    try scenario(a, "type Source s is contract = { type Item }\nimpl All a : Source a where { type_eq a U32 } = { type Item = a }\nimpl ArraySource a : Source (Array a) = { type Item = a }\n", .overlapping_implementation);
    try scenario(a, "type Source s is contract = { type Item }\nimpl Bad : Source U32 = {}\n", .missing_type_member);
}

test "implementation equations and unused methods obey closed signatures and cycle checks" {
    try scenario(a, "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl ArraySource a : Source (Array a) = { type Item = a, const first = fn values => @array.get values 0 }\n", null);
    try scenario(a, "type Source s is contract = { type Item }\nimpl Loop a : Source a = { type Item = Source.Item a }\n", .recursive_associated_type);
    try scenario(a, "type Source s is contract = { type Item }\nimpl Loop a : Source a = { type Item = Source.Item (Array a) }\n", .recursive_associated_type);
    try scenario(a, "type Source s is contract = { type Item }\nimpl First : Source U32 = { type Item = Source.Item F32 }\nimpl Second : Source F32 = { type Item = Source.Item U32 }\n", .recursive_associated_type);
    try scenario(a, "type Source s is contract = { type Item }\nimpl Extra a : Source a = { type Item = missing }\n", .unsupported_type);
    try scenario(a, "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl Bad a : Source (Array a) = { type Item = a, const first = fn values => 42 }\n", .type_mismatch);
}

test "implementation selection normalizes concrete abstract outputs without inverting unknown inputs" {
    try scenario(a, "type Source s is contract = { type Item }\nimpl Scalar : Source U32 = { type Item = F32 }\nentry const answer: (Source.Item U32) = 42.0\n", null);
    try scenario(a, "type Source s is contract = { type Item }\nimpl Scalar : Source U32 = { type Item = F32 }\nconst keep: a -> (Source.Item a) where { Source a } = fn value => @panic \"unused\"\n", null);
    try scenario(a, "type Source s is contract = { type Item }\nimpl Scalar : Source U32 where { type_eq U32 F32 } = { type Item = F32 }\nentry const answer: (Source.Item U32) = 42.0\n", .incompatible_implementation);
}

fn invalidArtifact(result: anytype) !void {
    result catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expect(err == error.InvalidArtifact);
        return;
    };
    return error.TestUnexpectedResult;
}
fn selectedProof(allocator: std.mem.Allocator) !void {
    const source = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl ArraySource a : Source (Array a) = { type Item = a, const first = fn values => @array.get values 0 }\n";
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    var result = try check.checkModule(allocator, &tree, &names, &.{}, &.{}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    var module = try @import("../check/core.zig").lower(allocator, &tree, &names, &result);
    defer module.deinit(allocator);
    module.unit = 1;
    const Evidence = @import("type_evidence.zig");
    const Proofs = @import("implementation_evidence.zig");
    const Host = struct {
        units: []const @import("../check/core.zig").Module,
        evidence: Evidence.Store,
        associated_remaining: usize = 1_000_000,
        pub fn evidenceStore(self: *@This()) *Evidence.Store {
            return &self.evidence;
        }
        pub fn implementationRead(_: *@This(), _: u32, _: @import("../check/types.zig").NominalIdentity) std.mem.Allocator.Error!void {}
        pub fn implementationLegacyPredicate(_: *@This(), _: u32, _: @import("../check/core.zig").Obligation, _: [4]Evidence.Id, _: Evidence.ProjectionResolver) Evidence.Error!?@import("implementation_evidence.zig").LegacyChoice {
            return null;
        }
    };
    var host: Host = .{ .units = &.{module}, .evidence = try Evidence.Store.init(allocator) };
    defer host.evidence.deinit();
    var proofs: Proofs.Store = .{ .allocator = allocator };
    defer proofs.deinit();
    const array = try host.evidence.intern(.array, 3, 0, &.{});
    const selected = try proofs.resolve(&host, 1, module.contracts[0].identity, &.{array});
    try std.testing.expectEqual(@as(usize, 1), proofs.proofs.items.len);
    try std.testing.expectEqual(selected, try proofs.resolve(&host, 1, module.contracts[0].identity, &.{array}));
    try std.testing.expectEqual(@as(usize, 1), proofs.proofs.items.len);
    try std.testing.expectEqual(@as(u64, 1), proofs.hits);
    try std.testing.expectEqual(@as(u32, 3), try proofs.projection(&host, 1, module.contracts[0].identity, names.lookup("Item").?, &.{array}));
    host.associated_remaining = 0;
    try std.testing.expectError(error.AssociatedLimit, proofs.resolve(&host, 1, module.contracts[0].identity, &.{array}));
    try std.testing.expectEqual(@as(usize, 1), proofs.proofs.items.len);
    host.associated_remaining = 1_000_000;
    const admission = @import("selected_implementation_admission.zig");
    var remaining: usize = 1_000_000;
    try admission.snapshot(allocator, &.{module}, host.evidence.view(), proofs.view(), &remaining);
    const member = proofs.members.items[0];
    proofs.members.items[0].kind = .value;
    remaining = 1_000_000;
    try invalidArtifact(admission.snapshot(allocator, &.{module}, host.evidence.view(), proofs.view(), &remaining));
    proofs.members.items[0] = member;
    proofs.members.items[0].root = 4;
    remaining = 1_000_000;
    try invalidArtifact(admission.snapshot(allocator, &.{module}, host.evidence.view(), proofs.view(), &remaining));
    proofs.members.items[0] = member;
    try std.testing.expect(module.member_templates.len != 0);
}

test "implementation selected proofs own closed shared graphs and ordinary method targets" {
    try selectedProof(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, selectedProof, .{});
}

fn executeSource(allocator: std.mem.Allocator, source: []const u8) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    var result = try check.checkModule(allocator, &tree, &names, &.{}, &.{}, 1);
    defer result.deinit(allocator);
    for (result.diagnostics) |issue| std.debug.print("method check: {s} at {d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    var module = try @import("../check/core.zig").lower(allocator, &tree, &names, &result);
    defer module.deinit(allocator);
    module.unit = 1;
    var session = try @import("core_eval.zig").Session.init(allocator, &.{module});
    defer session.deinit();
    for (module.bodies) |body| {
        if (!body.exported) continue;
        const value = session.value(.{ .unit = 1, .binding = body.binding }) catch |err| {
            if (session.diagnostic) |issue| std.debug.print("method execution: {s} at {d}\n", .{ @tagName(issue.code), issue.span.start });
            return err;
        };
        try std.testing.expectEqual(@as(u32, 42), value.bits);
        return;
    }
    return error.TestUnexpectedResult;
}

fn executeMethod(allocator: std.mem.Allocator) !void {
    try executeSource(allocator, "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl ArraySource a : Source (Array a) = { type Item = a, const first = fn values => @array.get values 0 }\nentry const answer = Source.first #[42]\n");
}

test "implementation methods execute through complete selected proofs" {
    try executeMethod(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, executeMethod, .{});
}

test "implementation declared row binders are classified from written head use" {
    try scenario(a, "type Callable f is contract = { type Run, const keep: f -> (Callable.Run f) }\nimpl Arrow (a,b,e) : Callable (a -> b ! {| e}) = { type Run = a -> b ! {| e}, const keep = fn value => value }\n", null);
    try scenario(a, "type Callable f is contract = { type Run }\nimpl Bad e : Callable U32 = { type Run = Unit -> U32 ! {| e} }\n", .undetermined_implementation);
    try scenario(a, "type Callable f is contract = { type Run, const keep: f -> (Callable.Run f) }\nimpl Bad : Callable U32 = { type Run = U32, const keep = fn value => value + 1 }\n", .unknown_operator);
}

test "implementation caller dependence includes operation argument variables in latent rows" {
    const T = @import("../check/types.zig");
    var store = try T.Store.init(a);
    defer store.deinit();
    const variable = try store.fresh();
    const label = try store.internSymbolicOperation(.{ .unit = 7, .decl = 19 }, &.{variable});
    const row = try store.effects.row(&.{label}, .closed);
    const roots = [_]T.Id{ try store.functionWithEffects(T.unit, T.unit, row), try store.demandWithEffects(T.unit, row), try store.provider(T.unit, row) };
    const source: @import("../check/core.zig").Types = .{ .nodes = store.nodes.items, .extra = store.extra.items, .operations = store.operations.items, .effects = .{ .rows = store.effects.rows.items, .labels = store.effects.labels.items } };
    for (roots) |root| try std.testing.expect(@import("core_eval.zig").callerDependent(&source, root, 0));
    try std.testing.expect(!@import("core_eval.zig").callerDependent(&source, T.unit, 0));
    try std.testing.expect(!@import("core_eval.zig").callerDependent(&source, roots[0], 256));
}

pub const symbolic_source = "type State a is effect = { get: Unit -> a, set: a -> Unit }\nconst read: Unit -> a ! {State.get a} = fn () => State.get ()\ntype Callable f is contract = { type Run, const keep: f -> f }\nimpl Callback a : Callable (Unit -> a ! {State.get a}) = { type Run = a, const keep = fn value => value }\n";
test "implementation symbolic operation head arguments specialize complete selected evidence" {
    const source = symbolic_source ++ "entry const answer = @product.get (@effect.run State.get State.set 42 (fn () => Callable.keep read ())) 1\n";
    try executeSource(a, source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, executeSource, .{source});
    try emitSource(a, source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSource, .{source});
    try scenario(a, "type State a is effect = { set: a -> Unit }\ntype Callable f is contract = { type Run }\nimpl Callback a : Callable (Unit -> Unit ! {State.set a}) = { type Run = a }\nentry const answer: Callable.Run (Unit -> Unit ! {State.set U32}) = 42\n", null);
    try scenario(a, "type State a is effect = { set: a -> Unit }\ntype Callable f is contract = { type Run }\nimpl Unused a : Callable (Unit -> Unit ! {State.set U32}) = { type Run = a }\n", .undetermined_implementation);
}

fn emitSource(allocator: std.mem.Allocator, source: []const u8) !void {
    return emitSourceKind(allocator, source, null);
}
fn emitSourceKind(allocator: std.mem.Allocator, source: []const u8, required: ?@import("../check/types.zig").ObligationKind) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    var checked = try check.checkModule(allocator, &tree, &names, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    if (required) |kind| {
        const found = for (checked.selected_proofs) |proof| {
            if (proof.kind == .predicate and proof.predicate.kind == kind) break true;
        } else false;
        try std.testing.expect(found);
    }
    var module = try @import("../check/core.zig").lower(allocator, &tree, &names, &checked);
    defer module.deinit(allocator);
    module.unit = 1;
    var admission_remaining: usize = 1_000_000;
    try @import("implementation_admission.zig").scopes(allocator, &module.types, &module, module.obligations, &admission_remaining);
    try @import("selected_implementation_admission.zig").core(allocator, &module, &admission_remaining);
    var principal = try @import("../reuse/dependency_snapshot.zig").freeze(allocator, &tree, &checked);
    defer @import("../reuse/dependency_snapshot.zig").deinit(allocator, &principal);
    try @import("implementation_admission.zig").publicCore(allocator, &principal, &module, &admission_remaining);
    if (required != null) {
        if (principal.selected_members.len != 0) {
            const original = principal.selected_members[0].root;
            principal.selected_members[0].root = @import("../check/types.zig").f32_type;
            defer principal.selected_members[0].root = original;
            var forged_remaining: usize = 1_000_000;
            try invalidArtifact(@import("implementation_admission.zig").publicCore(allocator, &principal, &module, &forged_remaining));
        }
        {
            const original = module.selected_members;
            var forged = module;
            forged.selected_members = try allocator.alloc(@import("../check/core.zig").ImplementationMember, original.len + 1);
            defer allocator.free(forged.selected_members);
            @memcpy(forged.selected_members[0..original.len], original);
            forged.selected_members[original.len] = original[0];
            var forged_remaining: usize = 1_000_000;
            const admitted = @import("selected_implementation_admission.zig").core(allocator, &forged, &forged_remaining);
            try invalidArtifact(admitted);
        }
        var session = try @import("core_eval.zig").Session.init(allocator, &.{module});
        defer session.deinit();
        for (module.selected_proofs) |proof| {
            if (proof.kind != .implementation) continue;
            var arguments: std.ArrayList(@import("type_evidence.zig").Id) = .empty;
            defer arguments.deinit(allocator);
            for (module.types.list(proof.arguments)) |root| try arguments.append(allocator, try session.storage.evidence.projectWithBudget(&module.types, root, &.{}, &.{}, &session.associated_remaining));
            _ = try session.implementation_proofs.resolve(&session, 1, proof.contract, arguments.items);
        }
        try std.testing.expectEqual(@as(usize, 0), session.steps);
        admission_remaining = 1_000_000;
        try @import("selected_implementation_admission.zig").snapshot(allocator, &.{module}, session.storage.evidence.view(), session.implementation_proofs.view(), &admission_remaining);
    }
    var compiled = try @import("../backend/core_backend.zig").compile(allocator, &.{module}, 1);
    defer compiled.deinit(allocator);
    if (compiled.diagnostic) |issue| std.debug.print("implementation emit {s} at{d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expect(compiled.diagnostic == null and compiled.bytes.len > 8);
}
test "implementation Foreign callback method preserves its declared inner arrow" {
    try emitSource(a, "type Callable f is contract = { type Run, const run: f -> (Unit -> (Callable.Run f) ! {Foreign}) }\nimpl Callback a : Callable (Unit -> a ! {Foreign}) = { type Run = a, const run = fn callback => fn () => do:\n  use value <- callback ()\n  break value }\nentry const answer = fn (callback: Unit -> U32 ! {Foreign}) => do:\n  use first <- Callable.run callback ()\n  use second <- Callable.run callback ()\n  break @u32.add first second\n");
}

test "implementation prerequisites retain ordinary associated method evidence" {
    try emitSource(a, "type Token is data = #Token U32\nconst Token.add = fn (left: Token) => fn (right: Token) => left\ntype Source s is contract = { associated \"add\" s s s ! {}, type Item }\nimpl TokenSource : Source Token = { type Item = U32 }\nentry const answer: (Source.Item Token) = 42\n");
}
test "implementation private witnesses remain lexical across selected cache hits" {
    const declarations = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nprivate impl Hidden : Source U32 = { type Item = U32, const first = fn value => value }\n";
    try scenario(a, declarations ++ "const read: U32 -> U32 = fn value => Source.first value\n", null);
    try scenario(a, declarations ++ "const read: U32 -> U32 = fn value => Source.first value\nconst escape: (Source.Item U32) = 42\n", .private_identity_escape);
    try scenario(a, declarations ++ "type Destination s is contract = { const keep: s -> U32 }\nimpl Public : Destination U32 = { const keep = fn value => Source.first value }\n", null);
    try scenario(a, declarations ++ "const leak = Hidden.first 42\n", .unknown_value);
    const executable = declarations ++ "const read: U32 -> U32 = fn value => Source.first value\nentry const answer = read 42\n";
    try executeSource(a, executable);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, executeSource, .{executable});
}

test "implementation selected methods preserve ordinary captures curried arity and finite prerequisites" {
    const captured = "const seed = 42\ntype Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl Scalar : Source U32 = { type Item = U32, const first = fn _ => seed }\nentry const answer = Source.first 0\n";
    try executeSource(a, captured);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, executeSource, .{captured});
    try executeSource(a, "type Source s is contract = { type Item, const first: s -> U32 -> (Source.Item s) }\nimpl ArraySource a : Source (Array a) = { type Item = a, const first = fn values => fn index => @array.get values index }\nentry const answer = Source.first #[0,42] 1\n");
    try executeSource(a, "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl Scalar : Source U32 = { type Item = U32, const first = fn value => value }\nimpl ArraySource a : Source (Array a) where { Source a } = { type Item = Source.Item a, const first = fn values => Source.first (@array.get values 0) }\nentry const answer = Source.first #[#[42]]\n");
    try scenario(a, "type Source s is contract = { type Item }\nimpl Loop a : Source a where { Source a } = { type Item = U32 }\nentry const answer: Source.Item U32 = 42\n", .recursive_evidence);
}

fn matchDag(allocator: std.mem.Allocator) !void {
    const T = @import("../check/types.zig");
    const E = @import("type_evidence.zig");
    var pattern = try T.Store.init(allocator);
    defer pattern.deinit();
    var actual = try E.Store.init(allocator);
    defer actual.deinit();
    var root = try pattern.fresh();
    var concrete: E.Id = 3;
    for (0..24) |_| {
        root = try pattern.product(&.{ root, root });
        concrete = try actual.intern(.product, 0, 0, &.{ concrete, concrete });
    }
    var mappings: std.ArrayList(E.Mapping) = .empty;
    defer mappings.deinit(allocator);
    var rows: std.ArrayList(E.RowMapping) = .empty;
    defer rows.deinit(allocator);
    var remaining: usize = 256;
    try std.testing.expect(try actual.matchWithRowsBudget(&pattern, root, concrete, &mappings, &rows, &remaining));
    try std.testing.expect(remaining >= 200);
    try std.testing.expectEqual(@as(usize, 1), mappings.items.len);
}
test "implementation head matching spends distinct DAG work and releases every failed allocation" {
    try matchDag(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, matchDag, .{});
}

fn closedHeadDag(allocator: std.mem.Allocator) !void {
    const T = @import("../check/types.zig");
    var store = try T.Store.init(allocator);
    defer store.deinit();
    store.has_projections = true;
    var closed: T.Id = T.u32_type;
    var equivalent: T.Id = T.u32_type;
    var variable = try store.fresh();
    const row = try store.freshEffects();
    var callback = try store.functionWithEffects(T.unit, T.u32_type, row);
    const label = try store.internSymbolicOperation(.{ .unit = 7, .decl = 19 }, &.{callback});
    var typed_callback = try store.functionWithEffects(T.unit, T.u32_type, try store.effects.row(&.{label}, .closed));
    for (0..32) |_| {
        closed = try store.product(&.{ closed, closed });
        equivalent = try store.product(&.{ equivalent, equivalent });
        variable = try store.product(&.{ variable, variable });
        callback = try store.product(&.{ callback, callback });
        typed_callback = try store.product(&.{ typed_callback, typed_callback });
    }
    const before = store.projection_steps;
    try std.testing.expect(try store.equalClosed(closed, closed));
    try std.testing.expect(store.projection_steps - before <= 66);
    try std.testing.expect(!try store.equalClosed(variable, variable));
    try std.testing.expect(!try store.equalClosed(callback, callback));
    try std.testing.expect(!try store.equalClosed(typed_callback, typed_callback));
    try std.testing.expect(try store.equalSymbolic(variable, variable));
    const unify_before = store.projection_steps;
    try store.unify(closed, equivalent);
    try std.testing.expect(store.projection_steps - unify_before < 10_000);
    const unknown = try store.fresh();
    const repeated = try store.product(&.{ unknown, unknown });
    const incompatible = try store.product(&.{ T.u32_type, T.f32_type });
    const versions = store.versions.items.len;
    store.unify(repeated, incompatible) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.TypeMismatch, err);
        try std.testing.expectEqual(versions, store.versions.items.len);
        return;
    };
    return error.TestUnexpectedResult;
}
test "implementation closed head comparison spends distinct DAG work without assuming closure" {
    try closedHeadDag(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, closedHeadDag, .{});
}

test "implementation source projection DAG selects a closed shared head within its work budget" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "type P0 a is contract = { type Item = a }\n");
    for (1..33) |depth| {
        const declaration = try a.print("type P{d} a is contract = {{ type Item = (P{d}.Item a, P{d}.Item a) }}\n", .{ depth, depth - 1, depth - 1 });
        defer a.free(declaration);
        try source.appendSlice(a, declaration);
    }
    try source.appendSlice(a, "type Source s is contract = { type Item }\nimpl All a : Source a = { type Item = a }\nconst keep: (Source.Item (P32.Item U32)) -> (P32.Item U32) = fn value => value\nentry const answer = 42\n");
    try scenario(a, source.items, null);
}

test "implementation legacy prerequisites prove Foreign rows without changing projection ambient" {
    try emitSource(a, "type Token is data = #Token U32\nconst Token.add: Token -> (Token -> Token ! {Foreign}) = fn left => fn right => left\ntype Source s is contract = { associated \"add\" s s s ! {Foreign}, type Item }\nimpl TokenSource : Source Token = { type Item = U32 }\nentry const answer: (Source.Item Token) = 42\n");
}

test "implementation header prerequisites cannot cache incomplete self evidence" {
    try scenario(a, "type Source s is contract = { type Item }\nimpl Bad : Source U32 where { type_eq (Source.Item U32) F32 } = { type Item = U32 }\nentry const answer: (Source.Item U32) = 42\n", .incompatible_implementation);
}

test "implementation own output equations normalize prerequisites before proof publication" {
    const good = "type Source s is contract = { type Item }\nimpl Scalar : Source U32 where { type_eq (Source.Item U32) U32 } = { type Item = U32 }\nentry const answer: (Source.Item U32) = 42\n";
    try emitSource(a, good);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSource, .{good});
}

test "implementation ordinary prerequisite targets retain transitive contract evidence" {
    const good = "type Ready s is contract = { type Proof }\nimpl ReadyScalar : Ready U32 = { type Proof = U32 }\ntype Token is data = #Token U32\nconst Token.add: Token -> Token -> Token where { Ready U32 } = fn left => fn right => left\ntype Source s is contract = { associated \"add\" s s s ! {}, type Item }\nimpl TokenSource : Source Token = { type Item = U32 }\nentry const answer: (Source.Item Token) = 42\n";
    try emitSource(a, good);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSource, .{good});
    try scenario(a, "type Ready s is contract = { type Proof }\ntype Token is data = #Token U32\nconst Token.add: Token -> Token -> Token where { Ready U32 } = fn left => fn right => left\ntype Source s is contract = { associated \"add\" s s s ! {}, type Item }\nimpl TokenSource : Source Token = { type Item = U32 }\nentry const answer: (Source.Item Token) = 42\n", .incompatible_implementation);
    try scenario(a, "type Ready s is contract = { type Proof }\ntype Token is data = #Token U32\nconst Token.add: Token -> Token -> Token where { Ready U32 } = fn left => fn right => left\ntype Source s is contract = { associated \"add\" s s s ! {}, type Item }\nimpl ReadyScalar : Ready U32 where { Source Token } = { type Proof = U32 }\nimpl TokenSource : Source Token = { type Item = U32 }\nentry const answer: (Source.Item Token) = 42\n", .recursive_evidence);
}

test "implementation ordinary shared callee evidence retains its selected prerequisites" {
    const source = "type Token a is data = #Token a\nconst Token.keep = fn (value: Token a) => fn () => value\nconst helper: (Token a) -> (Token a) where { associated \"keep\" (Token a) Unit (Token a) ! {} } = fn value => value\nconst Token.add = fn (left: Token a) => fn (right: Token a) => helper left\ntype Source s is contract = { associated \"add\" s s s ! {}, type Item }\nimpl TokenSource a : Source (Token a) = { type Item = a }\nentry const answer: (Source.Item (Token U32)) = 42\n";
    try emitSourceKind(a, source, .callee_use);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSourceKind, .{ source, @as(?@import("../check/types.zig").ObligationKind, .callee_use) });
}
test "implementation record prerequisites preserve merge overwrite and update result types" {
    const source = "type Source s is contract = { merge { x: U32 } { x: F32, y: U32 } { x: F32, y: U32 }, update \"x\" { x: U32, y: U32 } F32 { x: F32, y: U32 }, type Item }\nimpl Scalar : Source U32 = { type Item = U32 }\nentry const answer: (Source.Item U32) = 42\n";
    try emitSource(a, source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSource, .{source});
}
test "implementation data field and update prerequisites derive closed constructor recipes" {
    const source = "type Box a is data = #Box { x: a, y: U32 }\ntype Source s is contract = { field \"x\" (Box U32) U32, update \"x\" (Box U32) F32 (Box F32) ! {}, type Item }\nimpl Scalar : Source U32 = { type Item = U32 }\nentry const answer: (Source.Item U32) = 42\n";
    try emitSource(a, source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSource, .{source});
    try scenario(a, "type Box is data = #Box { x: U32 }\nconst Box.x = fn (value: Box) => 42\ntype Source s is contract = { field \"x\" Box U32, type Item }\nimpl Scalar : Source U32 = { type Item = U32 }\nentry const answer: (Source.Item U32) = 42\n", .incompatible_implementation);
}
test "implementation operation prerequisites establish only their own typed row without invocation" {
    const source = "type State a is effect = { set: a -> Unit }\ntype Callable f is contract = { operation State.set U32, type Item, const run: f -> Unit ! {State.set U32} }\nimpl Callback : Callable (Unit -> Unit ! {State.set U32}) = { type Item = U32, const run = fn callback => do:\n  use State.set 42\n  break () }\nentry const answer: (Callable.Item (Unit -> Unit ! {State.set U32})) = 42\n";
    try emitSourceKind(a, source, .effect_operation);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSourceKind, .{ source, @as(?@import("../check/types.zig").ObligationKind, .effect_operation) });
}

test "implementation selected ordinary operation method retains its established invocation row" {
    const source = "type State a is effect = { set: a -> Unit }\ntype Token is data = #Token U32\nconst Token.add: Token -> (Token -> Token ! {State.set U32}) = fn left => fn right => do:\n  use State.set 42\n  break left\ntype Source s is contract = { associated \"add\" s s s ! {State.set U32}, type Item }\nimpl TokenSource : Source Token = { type Item = U32 }\nentry const answer: (Source.Item Token) = 42\n";
    try scenario(a, source, null);
    try emitSource(a, source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSource, .{source});
}
test "implementation declaration admission compares methods under logical given equations" {
    const variable = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl All a : Source a where { type_eq a U32 } = { type Item = U32, const first = fn value => value }\nconst value: U32 = 42\nentry const answer = Source.first value\n";
    const projection = "type Other s is contract = { type Item }\nimpl Scalar : Other U32 = { type Item = U32 }\ntype Source s is contract = { Other s, const first: s -> (Other.Item s) }\nimpl All a : Source a where { type_eq (Other.Item a) a } = { const first = fn value => value }\nentry const answer = Source.first 42\n";
    try emitSource(a, variable);
    try emitSource(a, projection);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSource, .{variable});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSource, .{projection});
}

fn closureProjectionDag(allocator: std.mem.Allocator) !void {
    const source = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl All a : Source a = { type Item = a, const first = fn value => value }\nentry const read = fn value => Source.first value\n";
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    var checked = try check.checkModule(allocator, &tree, &names, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    try std.testing.expect(checked.diagnostics.len == 0);
    var module = try @import("../check/core.zig").lower(allocator, &tree, &names, &checked);
    defer module.deinit(allocator);
    module.unit = 1;
    const catalog = for (checked.bindings, 0..) |binding, ordinal| {
        if (binding.name == names.lookup("read").?) break @as(u32, @intCast(ordinal));
    } else return error.TestUnexpectedResult;
    const before = @import("../reuse/code_artifacts.zig").stamp(module);
    defer std.testing.expectEqualSlices(u8, &before, &@import("../reuse/code_artifacts.zig").stamp(module)) catch @panic("DAG evidence changed its principal module");
    try closureProjectionDagPrepared(allocator, &module, catalog);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, closureProjectionDagPrepared, .{ &module, catalog });
}
fn closureProjectionDagPrepared(allocator: std.mem.Allocator, module: *const @import("../check/core.zig").Module, catalog: u32) !void {
    var session = try @import("core_eval.zig").Session.init(allocator, module[0..1]);
    defer session.deinit();
    var root: @import("type_evidence.zig").Id = 3;
    for (0..64) |_| root = try session.storage.evidence.intern(.product, 0, 0, &.{ root, root });
    const expected = try session.storage.evidence.intern(.function, root, root, &.{});
    session.associated_remaining = 20_000;
    var evidence = try session.bodyEvidenceFull(.{ .unit = 1, .binding = catalog }, expected, &.{}, &.{});
    defer evidence.deinit(allocator);
    try std.testing.expect(session.associated_remaining > 10_000);
    try std.testing.expect(session.implementation_proofs.proofs.items.len != 0);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}
test "implementation closure projection and matching spend distinct shared DAG work" {
    try closureProjectionDag(a);
}
test "implementation ordinary result selected prerequisites retain destination dispatch" {
    const source = "type Box a is data = #Box a\nconst Box.from = fn value => #Box value\nconst from = fn value => @type.result \"from\" value\ntype Token is data = #Token U32\nconst Token.add: Token -> Token -> (Box U32) = fn left => fn right => from 42\ntype Source s is contract = { associated \"add\" s s (Box U32) ! {}, type Item }\nimpl TokenSource : Source Token = { type Item = U32 }\nentry const answer: (Source.Item Token) = 42\n";
    try emitSourceKind(a, source, .result_dispatch);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSourceKind, .{ source, @as(?@import("../check/types.zig").ObligationKind, .result_dispatch) });
}
test "implementation ordinary resolver prerequisites retain complete selected protocol evidence" {
    const source = "type Box a is data = #Box a\nconst Box.pure = fn value => #Box value\ntype Token a is data = #Token a\nconst Token.add = fn (left: Token a) => fn (right: Token a) => case left of\n  #Token constructor => do (@do.monad constructor):\n    break 42\ntype Source s is contract = { associated \"add\" s s (Box U32) ! {}, type Item, const first: s -> (Source.Item s) }\nimpl TokenSource a : Source (Token a) = { type Item = U32, const first = fn value => 42 }\nentry const answer = Source.first (#Token Box)\n";
    try scenario(a, source, null);
    try emitSourceKind(a, source, .resolver_dispatch);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSourceKind, .{ source, @as(?@import("../check/types.zig").ObligationKind, .resolver_dispatch) });
}

pub const handler_source = "type State state is effect = { get: Unit -> state, set: state -> Unit }\nconst run = fn initial => fn action => @effect.run State.get State.set initial action\ntype Token a is data = #Token a\nconst Token.add = fn (left: Token a) => fn (right: Token a) => case left of\n  #Token initial => do:\n    let (next,previous) = run initial (fn () => do:\n      use State.set initial\n      break initial)\n    break #Token next\ntype Source s is contract = { associated \"add\" s s s ! {}, type Item, const first: s -> (Source.Item s) }\nimpl TokenSource a : Source (Token a) = { type Item = U32, const first = fn value => 42 }\n";
test "implementation ordinary handler prerequisites retain closed removal evidence" {
    const source = handler_source ++ "entry const answer = Source.first (#Token 42)\n";
    try scenario(a, source, null);
    try emitSourceKind(a, source, .effect_handler);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSourceKind, .{ source, @as(?@import("../check/types.zig").ObligationKind, .effect_handler) });
}

test "implementation ordinary collection prerequisites retain exact collection identity" {
    const source = "type Token c is data = #Token c\nconst Token.add = fn (left: Token c) => fn (right: Token c) => case left of\n  #Token cursor => @cursor.value cursor\ntype Source (s,a) is contract = { associated \"add\" s s a ! {}, type Item }\nimpl TokenSource (c,a) : Source (Token (Cursor c),a) = { type Item = a }\nentry const answer: (Source.Item (Token (Cursor (Array U32)),U32)) = 42\n";
    try scenario(a, source, null);
    try emitSourceKind(a, source, .collection);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSourceKind, .{ source, @as(?@import("../check/types.zig").ObligationKind, .collection) });
}

pub const witness_source = "type Token a is data = #Token a\nconst Token.add = fn (left: Token a) => fn (right: Token a) => case left of\n  #Token witness => @state.reader witness (fn () => @panic \"proof executed\") (fn () => do:\n    use unused <- @state.get witness\n    break left)\ntype Source s is contract = { associated \"add\" s s s ! {}, type Item, const first: s -> (Source.Item s) }\nimpl TokenSource a : Source (Token a) = { type Item = U32, const first = fn value => 42 }\n";
test "implementation ordinary witness prerequisites derive internal result variables" {
    const source = witness_source ++ "entry const answer: (Source.Item (Token (Unit -> U32))) = 42\n";
    try scenario(a, source, null);
    try emitSourceKind(a, source, .type_head);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitSourceKind, .{ source, @as(?@import("../check/types.zig").ObligationKind, .type_head) });
}

pub const rejected_source = "type Source s is contract = { type Item }\nimpl Scalar : Source U32 where { type_eq U32 F32 } = { type Item = U32 }\n";
fn rejectedEvidence(allocator: std.mem.Allocator) !void {
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tokens = try lexer.lex(allocator, rejected_source);
    defer tokens.deinit(allocator);
    var tree = try parser.parse(allocator, rejected_source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    var checked = try check.checkModule(allocator, &tree, &names, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    try std.testing.expect(checked.diagnostics.len == 0);
    var module = try @import("../check/core.zig").lower(allocator, &tree, &names, &checked);
    defer module.deinit(allocator);
    module.unit = 1;
    var session = try @import("core_eval.zig").Session.init(allocator, &.{module});
    defer session.deinit();
    if (session.implementation_proofs.resolve(&session, 1, module.contracts[0].identity, &.{3})) |_| {
        return error.TestUnexpectedResult;
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expect(err == error.IncompatibleImplementation);
    }
    const trace = session.implementation_proofs.trace;
    try std.testing.expect(trace.len == 1 and trace.step_len == 1);
    try std.testing.expectEqual(@import("../reuse/dispatch_explanation.zig").Outcome.requires_evidence, trace.candidates[0].outcome);
    try std.testing.expectEqual(@import("../reuse/dispatch_explanation.zig").Outcome.incompatible_type, trace.steps[0].outcome);
    try std.testing.expectEqual(@as(u32, 3), trace.steps[0].ty);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    try std.testing.expectEqual(@as(usize, 0), session.implementation_proofs.proofs.items.len);
    const request = rejected_source ++ "entry const answer: (Source.Item U32) = 42\n";
    var request_tokens = try lexer.lex(allocator, request);
    defer request_tokens.deinit(allocator);
    var request_tree = try parser.parse(allocator, request, request_tokens.tokens.items, &names);
    defer request_tree.deinit(allocator);
    var rejected = try check.checkModule(allocator, &request_tree, &names, &.{}, &.{}, 1);
    defer rejected.deinit(allocator);
    for (rejected.diagnostics) |issue| {
        if (issue.code != .incompatible_implementation) continue;
        const explained = issue.explanation orelse return error.TestUnexpectedResult;
        try std.testing.expect(explained.candidates.len == 1 and explained.steps.len == 1);
        try std.testing.expectEqual(trace.candidates[0].outcome, explained.candidates[0].outcome);
        try std.testing.expectEqual(trace.steps[0].outcome, explained.steps[0].outcome);
        try std.testing.expectEqualStrings("U32", explained.steps[0].ty.?);
        return;
    }
    return error.TestUnexpectedResult;
}
test "implementation failed prerequisite source and backend facts agree without partial proof publication" {
    try rejectedEvidence(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectedEvidence, .{});
}

const many_heads = "type Source s is contract = { type Item }\nimpl Scalar : Source U32 = { type Item = U32 }\nimpl Floating : Source F32 = { type Item = U32 }\nimpl Boolean : Source Bool = { type Item = U32 }\nimpl Empty : Source Unit = { type Item = U32 }\nimpl ArraySource a : Source (Array a) = { type Item = U32 }\nimpl ListSource a : Source (List a) = { type Item = U32 }\n";
test "implementation bounded origins never truncate candidate selection" {
    const missing = many_heads ++ "entry const answer: (Source.Item (Cursor U32)) = 42\n";
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tokens = try lexer.lex(a, missing);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, missing, tokens.tokens.items, &names);
    defer tree.deinit(a);
    var checked = try check.checkModule(a, &tree, &names, &.{}, &.{}, 1);
    defer checked.deinit(a);
    const explanation = for (checked.diagnostics) |issue| {
        if (issue.code == .missing_implementation) break issue.explanation orelse return error.TestUnexpectedResult;
    } else return error.TestUnexpectedResult;
    try std.testing.expect(explanation.truncated and explanation.candidates.len == 4);
    const encoded = try std.json.Stringify.valueAlloc(a, explanation, .{});
    defer a.free(encoded);
    try std.testing.expect(encoded.len <= 2048);
    const success = many_heads ++ "impl CursorSource a : Source (Cursor a) = { type Item = U32 }\n";
    var success_tokens = try lexer.lex(a, success);
    defer success_tokens.deinit(a);
    var success_tree = try parser.parse(a, success, success_tokens.tokens.items, &names);
    defer success_tree.deinit(a);
    var selected = try check.checkModule(a, &success_tree, &names, &.{}, &.{}, 1);
    defer selected.deinit(a);
    try std.testing.expect(selected.diagnostics.len == 0);
    var module = try @import("../check/core.zig").lower(a, &success_tree, &names, &selected);
    defer module.deinit(a);
    module.unit = 1;
    var session = try @import("core_eval.zig").Session.init(a, &.{module});
    defer session.deinit();
    const cursor = try session.storage.evidence.intern(.cursor, 3, 0, &.{});
    const proof = try session.implementation_proofs.resolve(&session, 1, module.contracts[0].identity, &.{cursor});
    try std.testing.expect(std.meta.eql(module.implementations[6].identity, session.implementation_proofs.proofs.items[proof].implementation));
    try std.testing.expect(session.implementation_proofs.trace.truncated and session.implementation_proofs.trace.len == 4);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}
