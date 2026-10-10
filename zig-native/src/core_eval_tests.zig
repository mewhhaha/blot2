const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const scalar_ops = @import("scalar_ops.zig");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const code_expectation = @import("code_expectation.zig");
const types = @import("types.zig");
const type_evidence = @import("type_evidence.zig");
const a = std.testing.allocator;
const test_prelude = @import("test_prelude_producers.zig");

fn componentBatchScenario(allocator: std.mem.Allocator, module: *const core.Module, workers: u8) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    session.semantic_io = std.testing.io;
    session.semantic_component_workers = workers;
    session.options.max_steps = 0;
    const result = try session.sourceInterface(target(module, "run"));
    const arrow = session.evidence.node(result.evidence);
    try std.testing.expectEqual(type_evidence.Tag.function, arrow.tag);
    try std.testing.expectEqual(types.u32_type, arrow.a);
    try std.testing.expectEqual(types.u32_type, arrow.b);
    try std.testing.expectEqual(@as(u32, 0), arrow.c);
    try std.testing.expect(session.counters.semantic_component_jobs >= 4);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    try std.testing.expect(session.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), session.call_summaries.stack.items.len);
}

test "private semantic components infer independent body jobs with one and multiple workers" {
    var module = try lower(
        \\const a = fn value => @u32.add value 1
        \\const b = fn value => @u32.add value 2
        \\const c = fn value => @u32.add value 3
        \\const d = fn value => @u32.add value 4
        \\entry const run: U32 -> U32 = fn value => @u32.add (@u32.add (a value) (b value)) (@u32.add (c value) (d value))
    );
    defer module.deinit(a);
    for ([_]u8{ 1, 2, 4 }) |workers| try componentBatchScenario(a, &module, workers);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, componentBatchScenario, .{ &module, @as(u8, 1) });
}

const component_source =
    \\const even: U32 -> U32 = fn value => if @u32.eq value 0 then 42 else odd (@u32.sub value 1)
    \\const odd: U32 -> U32 = fn value => if @u32.eq value 0 then 42 else even (@u32.sub value 1)
    \\entry const run: U32 -> U32 = fn value => even value
;

fn jointComponentScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    session.options.max_steps = 0;
    session.options.max_depth = 1;
    const result = try session.sourceInterface(target(module, "run"));
    const arrow = session.evidence.node(result.evidence);
    try std.testing.expectEqual(type_evidence.Tag.function, arrow.tag);
    try std.testing.expectEqual(types.u32_type, arrow.a);
    try std.testing.expectEqual(types.u32_type, arrow.b);
    try std.testing.expectEqual(@as(u32, 0), arrow.c);
    try std.testing.expect(session.component_restarts != 0);
    try std.testing.expect(session.component_members_published >= 2);
    try std.testing.expectEqual(@as(usize, 0), session.call_summaries.stack.items.len);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}

test "recursive summary tickets restart jointly and publish every member after all allocations" {
    var module = try lower(component_source);
    defer module.deinit(a);
    try jointComponentScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, jointComponentScenario, .{&module});
}

test "recursive summary transition exhaustion falls back without spending execution fuel" {
    var module = try lower(component_source);
    defer module.deinit(a);
    for ([_]usize{ 0, 1, 8, 64, 1_000_000 }) |limit| {
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        session.options.max_summary_transitions = limit;
        session.options.max_steps = 0;
        session.options.max_depth = 1;
        const result = try session.sourceInterface(target(&module, "run"));
        const arrow = session.evidence.node(result.evidence);
        try std.testing.expectEqual(type_evidence.Tag.function, arrow.tag);
        try std.testing.expectEqual(types.u32_type, arrow.a);
        try std.testing.expectEqual(types.u32_type, arrow.b);
        try std.testing.expectEqual(@as(u32, 0), arrow.c);
        try std.testing.expect(session.summary_transitions <= limit);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
        try std.testing.expect(session.diagnostic == null);
    }
}

test "recursive ordinary fallback collects a thousand bodies with explicit frames" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(a);
    try text.appendSlice(a, "const f_0: U32 -> U32 = fn value => @u32.add value 0\n");
    for (1..1001) |index| try text.print(a, "const f_{d}: U32 -> U32 = fn value => f_{d} value\n", .{ index, index - 1 });
    try text.appendSlice(a, "entry const run: U32 -> U32 = fn value => f_1000 value\n");
    var module = try lower(text.items);
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    session.reuse_principal_graphs = false;
    session.options.reuse_validated_calls = false;
    session.options.max_summary_transitions = 0;
    session.options.max_steps = 0;
    session.options.max_depth = 1;
    session.options.max_type_depth = 8;
    for (module.bodies[1..]) |body| try session.call_summaries.eligibility.put(a, .{ .unit = 0, .binding = body.binding }, false);
    const result = try session.sourceInterface(target(&module, "run"));
    const arrow = session.evidence.node(result.evidence);
    try std.testing.expectEqual(types.u32_type, arrow.a);
    try std.testing.expectEqual(types.u32_type, arrow.b);
    try std.testing.expect(session.counters.max_region_scopes >= 1001);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}

fn componentRetry(module: *const core.Module, offset: ?usize) !usize {
    var failing = std.testing.FailingAllocator.init(a, .{});
    var session = try evaluator.Session.init(failing.allocator(), &.{module.*});
    defer session.deinit();
    const start = failing.alloc_index;
    if (offset) |index| failing.fail_index = start + index;
    const result = session.sourceInterface(target(module, "run")) catch |err| retry: {
        try std.testing.expectEqual(error.OutOfMemory, err);
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectEqual(@as(usize, 0), session.inquiry_regions);
        try std.testing.expectEqual(@as(usize, 0), session.call_summaries.stack.items.len);
        try std.testing.expectEqual(@as(u32, 0), session.call_summaries.active.count());
        for (session.call_summaries.jobs.items) |job| {
            try std.testing.expect(job.region == null);
            try std.testing.expect(job.state == .complete or job.state == .declined);
        }
        failing.fail_index = std.math.maxInt(usize);
        break :retry try session.sourceInterface(target(module, "run"));
    };
    const arrow = session.evidence.node(result.evidence);
    try std.testing.expectEqual(types.u32_type, arrow.a);
    try std.testing.expectEqual(types.u32_type, arrow.b);
    try std.testing.expect(session.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    return failing.alloc_index - start;
}

test "recursive component allocation failures abandon pending members and retry in the same session" {
    var module = try lower(component_source);
    defer module.deinit(a);
    const allocations = try componentRetry(&module, null);
    for (0..allocations) |index| _ = try componentRetry(&module, index);
}

test "recursive selected frontend probe reaches bounded source inference" {
    const source =
        \\type Seed is data = #Seed
        \\type Box a is data = #Box a
        \\const Seed.build: a -> Seed -> Box a = fn value => fn seed => #Box value
        \\const f_0 = fn value => @type.call "build" value #Seed
        \\const parent: a -> a = fn value => (f_0 value).read
        \\const Box.read: Box a -> a = fn box => case box of
        \\  #Box value => parent value
        \\entry const generic = fn value => parent value
    ;
    var module = try lower(source);
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const result = try session.sourceInterface(target(&module, "generic"));
    try std.testing.expect(result.generic or result.pending != 0 or result.evidence != 0);
    try std.testing.expect(session.counters.max_region_scopes <= 32);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}

test "recursive discovery preserves invalid witnesses through unresolved acyclic diamonds" {
    for ([_]usize{ 8, 12 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, "const f_0 = fn left => fn right => @type.same (@panic \"uncalled witness\") right\n");
        for (1..depth + 1) |index| try text.print(a, "const f_{d} = fn left => fn right => do:\n  let ignored = f_{d} left right\n  return f_{d} left right\n", .{ index, index - 1, index - 1 });
        try text.print(a, "entry const integer = fn (value: U32) -> Bool => f_{d} value value\n", .{depth});
        var module = try lower(text.items);
        defer module.deinit(a);
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        const reference = target(&module, "integer");
        try std.testing.expectError(error.Declined, session.sourceInterface(reference));
        try std.testing.expectEqual(evaluator.Code.invalid_annotation, session.diagnostic.?.code);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    }
}

fn lower(source: []const u8) !core.Module {
    return lowerWithOptions(source, .{});
}

// These laws model a compiler/prelude producer, not a no-prelude source
// program. Method declarations are ordinary std/prelude definitions and the
// existing catalog option is explicit at this boundary.
fn lowerPreludeProducer(source: []const u8, operations: []const test_prelude.Operation) !core.Module {
    const input = try test_prelude.withMethods(a, source, operations);
    defer a.free(input);
    return lowerWithOptions(input, .{ .builtin_catalog = true });
}

fn lowerWithOptions(source: []const u8, options: checker.ModuleOptions) !core.Module {
    return lowerWithUnit(source, options, 1);
}

fn lowerWithUnit(source: []const u8, options: checker.ModuleOptions, unit: u32) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(a, &syntax, &pool, &.{}, &.{}, unit, options);
    defer checked.deinit(a);
    for (checked.diagnostics) |diagnostic| std.debug.print("check:{d}: {s}\n", .{ diagnostic.span.start, diagnostic.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &syntax, &pool, &checked);
    errdefer module.deinit(a);
    for (module.diagnostics) |diagnostic| std.debug.print("core:{d}: {s}\n", .{ diagnostic.span.start, diagnostic.message() });
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

fn qualifiedSchemeScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const selected = try session.sourceInterface(target(module, "run"));
    try std.testing.expect(selected.evidence != 0);
    try std.testing.expect(session.counters.max_region_scopes <= 8);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}

fn principalGraphScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    var summarized = try evaluator.Session.init(allocator, &.{module.*});
    defer summarized.deinit();
    for ([_][]const u8{ "integer", "floating", "field" }) |name| {
        const expected = try ordinary.sourceInterface(target(module, name));
        const actual = try summarized.sourceInterface(target(module, name));
        try std.testing.expect(expected.evidence != 0 and actual.evidence != 0);
        const expected_arrow = ordinary.evidence.node(expected.evidence);
        const actual_arrow = summarized.evidence.node(actual.evidence);
        try std.testing.expectEqual(type_evidence.Tag.function, actual_arrow.tag);
        try std.testing.expectEqual(expected_arrow.a, actual_arrow.a);
        try std.testing.expectEqual(expected_arrow.b, actual_arrow.b);
        try std.testing.expectEqual(expected_arrow.c, actual_arrow.c);
    }
    const expected_generic = try ordinary.sourceInterface(target(module, "generic"));
    const actual_generic = try summarized.sourceInterface(target(module, "generic"));
    try std.testing.expectEqual(expected_generic.evidence, actual_generic.evidence);
    try std.testing.expectEqual(expected_generic.generic, actual_generic.generic);
    try std.testing.expectEqual(expected_generic.selected, actual_generic.selected);
    try std.testing.expect(actual_generic.pending <= expected_generic.pending);
    try std.testing.expect(actual_generic.pending != 0);
    try std.testing.expect(summarized.principal_graph_builds != 0);
    try std.testing.expect(summarized.principal_graph_imports != 0);
    try std.testing.expect(summarized.principal_graph_deferred != 0);
    try std.testing.expect(summarized.counters.region_scopes < ordinary.counters.region_scopes);
    const builds = summarized.principal_graph_builds;
    _ = try summarized.sourceInterface(target(module, "integer"));
    try std.testing.expectEqual(builds, summarized.principal_graph_builds);
    try std.testing.expectEqual(@as(usize, 0), summarized.steps);
    try std.testing.expect(summarized.diagnostic == null);
}

test "owned principal graphs preserve independent inferred uses and publish atomically" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(a);
    try text.appendSlice(a,
        \\const f_0 = fn value => @type.call "add" value value
        \\const first = fn value => value.first
        \\
    );
    for (1..5) |i| try text.print(a, "const f_{d} = fn value => f_{d} (f_{d} value)\n", .{ i, i - 1, i - 1 });
    try text.appendSlice(a,
        \\entry const integer = fn (value: U32) => f_4 value
        \\entry const floating = fn (value: F32) => f_4 value
        \\entry const field = fn (value: F32) => first ({first: value})
        \\entry const generic = fn value => f_4 value
        \\
    );
    var module = try lowerPreludeProducer(text.items, &.{.add});
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const type_nodes = try a.dupe(types.Node, module.types.nodes);
    defer a.free(type_nodes);
    const obligations = try a.dupe(core.Obligation, module.obligations);
    defer a.free(obligations);
    try principalGraphScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, principalGraphScenario, .{&module});
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualDeep(type_nodes, module.types.nodes);
    try std.testing.expectEqualDeep(obligations, module.obligations);
}

test "open principal diamond inquiry grows with distinct bodies and edges" {
    for ([_][]const u8{ "@type.call \"add\" value value", "@type.result \"from\" value", "value.first" }) |leaf| for ([_]bool{ false, true }) |written| for ([_]usize{ 8, 16, 64 }) |depth| {
        if (written and std.mem.startsWith(u8, leaf, "@type.result")) continue;
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        const clause = if (!written) "" else if (std.mem.startsWith(u8, leaf, "@type.call")) ": a -> a where { associated \"add\" a a a }" else ": a -> b where { field \"first\" a b }";
        try text.print(a, "const f_0{s} = fn value => {s}\n", .{ clause, leaf });
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn value => f_{d} (f_{d} value)\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const generic = fn value => f_{d} value\n", .{depth});
        var module = try lowerPreludeProducer(text.items, &.{.add});
        defer module.deinit(a);
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        const result = try session.sourceInterface(target(&module, "generic"));
        try std.testing.expectEqual(@as(type_evidence.Id, 0), result.evidence);
        try std.testing.expect(result.pending != 0);
        if (session.counters.region_scopes > depth * 2 + 20) std.debug.print("principal case {s}, written={}, depth={d}: scopes={d}, builds={d}, imports={d}, deferred={d}\n", .{ leaf, written, depth, session.counters.region_scopes, session.principal_graph_builds, session.principal_graph_imports, session.principal_graph_deferred });
        try std.testing.expect(session.counters.region_scopes <= depth * 2 + 20);
        try std.testing.expect(session.principal_graph_builds <= depth * 2 + 4);
        try std.testing.expect(session.principal_graph_nodes <= depth * 64 + 128);
        if (session.principal_graph_deferred == 0) std.debug.print("no residual for {s}, written={}, depth={d}: scopes={d}, builds={d}, nodes={d}\n", .{ leaf, written, depth, session.counters.region_scopes, session.principal_graph_builds, session.principal_graph_nodes });
        try std.testing.expect(session.principal_graph_deferred != 0);
        const builds = session.principal_graph_builds;
        const scopes = session.counters.region_scopes;
        const again = try session.sourceInterface(target(&module, "generic"));
        try std.testing.expectEqualDeep(result, again);
        try std.testing.expectEqual(builds, session.principal_graph_builds);
        try std.testing.expectEqual(scopes + 1, session.counters.region_scopes);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    };
}

test "source owned array record and nominal skeletons keep open diamonds bounded" {
    for ([_][]const u8{ "#[value.first]", "{result: value.first}", "#Box value.first" }) |leaf| {
        for ([_]usize{ 8, 16, 64 }) |depth| {
            var text: std.ArrayList(u8) = .empty;
            defer text.deinit(a);
            try text.appendSlice(a, "type Box a is data = #Box a\n");
            try text.print(a, "const f_0 = fn value => {s}\n", .{leaf});
            for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn value => do:\n  let ignored = f_{d} value\n  return f_{d} value\n", .{ i, i - 1, i - 1 });
            try text.print(a, "entry const factory = do:\n  return f_{d}\n", .{depth});
            var module = try lower(text.items);
            defer module.deinit(a);
            var session = try evaluator.Session.init(a, &.{module});
            defer session.deinit();
            const result = try session.sourceInterface(target(&module, "factory"));
            if (session.counters.region_scopes > depth * 2 + 20) std.debug.print("structured {s}, depth={d}: scopes={d}, builds={d}, deferred={d}\n", .{ leaf, depth, session.counters.region_scopes, session.principal_graph_builds, session.principal_graph_deferred });
            try std.testing.expect(result.evidence == 0 and result.pending != 0);
            try std.testing.expect(session.counters.region_scopes <= depth * 2 + 20);
            try std.testing.expect(session.principal_graph_builds <= depth * 2 + 4);
            try std.testing.expect(session.principal_graph_deferred != 0);
            try std.testing.expectEqual(@as(usize, 0), session.steps);
        }
    }
}

test "source owned structured residuals preserve independent concrete interfaces" {
    for ([_]struct { leaf: []const u8, select: []const u8 }{
        .{ .leaf = "#[value.first]", .select = "result[0]" },
        .{ .leaf = "{result: value.first}", .select = "result.result" },
        .{ .leaf = "#Box value.first", .select = "case result of\n    #Box value => value" },
    }) |shape| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.print(a, "type Box a is data = #Box a\nconst f_0 = fn value => {s}\n", .{shape.leaf});
        for (1..9) |i| try text.print(a, "const f_{d} = fn value => do:\n  let ignored = f_{d} value\n  return f_{d} value\n", .{ i, i - 1, i - 1 });
        try text.appendSlice(a, "const factory = do:\n  return f_8\n");
        for ([_]struct { []const u8, []const u8 }{ .{ "integer", "U32" }, .{ "floating", "F32" } }) |instance| try text.print(a, "entry const {s} = fn (value: {s}) -> {s} => do:\n  let result = factory {{first: value}}\n  return {s}\n", .{ instance[0], instance[1], instance[1], shape.select });
        var module = try lower(text.items);
        defer module.deinit(a);
        var ordinary = try evaluator.Session.init(a, &.{module});
        defer ordinary.deinit();
        ordinary.reuse_principal_graphs = false;
        var summarized = try evaluator.Session.init(a, &.{module});
        defer summarized.deinit();
        for ([_][]const u8{ "integer", "floating" }) |name| {
            const expected = try ordinary.sourceInterface(target(&module, name));
            const actual = try summarized.sourceInterface(target(&module, name));
            try std.testing.expect(actual.evidence != 0);
            try std.testing.expectEqualDeep(ordinary.evidence.node(expected.evidence), summarized.evidence.node(actual.evidence));
        }
        try std.testing.expectEqual(@as(usize, 0), summarized.steps);
    }
}

test "source owned operation identities retain open rows through shared diamonds" {
    for ([_]bool{ false, true }) |written| for ([_]usize{ 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.print(a, "type Signal a is effect = {{ get: Unit -> a }}\nconst f_0{s} = fn (token: a) => Signal.get a ()\n", .{if (written) ": a -> a ! {| e} where { operation Signal.get a }" else ""});
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn token => do:\n  use ignored <- f_{d} token\n  return f_{d} token\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const factory = do:\n  return f_{d}\n", .{depth});
        var module = try lower(text.items);
        defer module.deinit(a);
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        const result = try session.sourceInterface(target(&module, "factory"));
        if (result.evidence != 0 or session.counters.region_scopes > depth * 4 + 32) std.debug.print("operation written={}, depth={d}: result={any}, scopes={d}, builds={d}, deferred={d}\n", .{ written, depth, result, session.counters.region_scopes, session.principal_graph_builds, session.principal_graph_deferred });
        try std.testing.expectEqual(@as(type_evidence.Id, 0), result.evidence);
        try std.testing.expect(result.pending != 0);
        // Source description and normalization each visit distinct bodies.
        try std.testing.expect(session.counters.region_scopes <= depth * 4 + 32);
        try std.testing.expect(session.counters.solver_constraint_visits <= depth * 256 + 256);
        try std.testing.expect(session.principal_graph_deferred != 0);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    };
}

fn operationPrincipalScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    var summarized = try evaluator.Session.init(allocator, &.{module.*});
    defer summarized.deinit();
    for ([_][]const u8{ "integer", "floating" }) |name| {
        const expected = try ordinary.sourceInterface(target(module, name));
        const actual = try summarized.sourceInterface(target(module, name));
        try std.testing.expect(actual.evidence != 0);
        try std.testing.expectEqualDeep(ordinary.evidence.node(expected.evidence), summarized.evidence.node(actual.evidence));
    }
    for ([_]*evaluator.Session{ &ordinary, &summarized }) |session| {
        const correct = try session.sourceInterface(target(module, "integer"));
        var accepted = try session.bodyEvidenceFull(target(module, "convert"), correct.evidence, &.{}, &.{});
        accepted.deinit(allocator);
        const pure = try session.evidence.intern(.function, types.u32_type, types.u32_type, &.{});
        try resultWitnessFailure(session, target(module, "convert"), pure);
        try std.testing.expectEqual(evaluator.Code.effect_mismatch, session.diagnostic.?.code);
    }
    try std.testing.expectEqualDeep(ordinary.diagnostic, summarized.diagnostic);
    ordinary.diagnostic = null;
    summarized.diagnostic = null;
    for ([_]*evaluator.Session{ &ordinary, &summarized }) |session| {
        const correct = try session.sourceInterface(target(module, "integer"));
        var recovered = try session.bodyEvidenceFull(target(module, "convert"), correct.evidence, &.{}, &.{});
        recovered.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    }
}

test "operation residual graphs preserve family instances exact rows and recovery under allocation failure" {
    var module = try lower(
        \\type Signal a is effect = { get: Unit -> a }
        \\const f_0 = fn (token: a) => Signal.get a ()
        \\const f_1 = fn token => do:
        \\  use ignored <- f_0 token
        \\  return f_0 token
        \\const f_2 = fn token => do:
        \\  use ignored <- f_1 token
        \\  return f_1 token
        \\const f_3 = fn token => do:
        \\  use ignored <- f_2 token
        \\  return f_2 token
        \\entry const convert = fn value => f_3 value
        \\entry const integer = fn (value: U32) -> U32 => convert value
        \\entry const floating = fn (value: F32) -> F32 => convert value
    );
    defer module.deinit(a);
    try operationPrincipalScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, operationPrincipalScenario, .{&module});
}

fn writtenOperationProviderScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    for ([_]bool{ false, true }) |sharing| {
        var session = try evaluator.Session.init(allocator, &.{module.*});
        defer session.deinit();
        session.reuse_principal_graphs = sharing;
        const interface = try session.sourceInterface(target(module, "requested"));
        try std.testing.expect(interface.evidence != 0);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
        try std.testing.expectEqual(@as(u32, 37), (try session.value(target(module, "answer"))).bits);
    }
}

test "inferred wrappers discharge transitive written operation rows under a provider" {
    var module = try lower(
        \\type Signal a is effect = { get: Unit -> a }
        \\const operation_0: a -> a ! {| e} where { operation Signal.get a } = fn token => Signal.get a ()
        \\const operation_1 = fn token => operation_0 token
        \\const operation_2 = fn token => operation_1 token
        \\const factory = do:
        \\  return operation_2
        \\entry const requested = fn (value: U32) -> U32 => do (@effect.provider (Signal.get U32) (fn () => value)):
        \\  return factory value
        \\entry const answer = requested 37
    );
    defer module.deinit(a);
    try writtenOperationProviderScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, writtenOperationProviderScenario, .{&module});
}

fn resultPrincipalScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    var summarized = try evaluator.Session.init(allocator, &.{module.*});
    defer summarized.deinit();
    const expected = try ordinary.sourceInterface(target(module, "generic"));
    const actual = try summarized.sourceInterface(target(module, "generic"));
    try std.testing.expectEqual(expected.evidence, actual.evidence);
    try std.testing.expectEqual(expected.generic, actual.generic);
    try std.testing.expect(actual.pending != 0 and actual.pending <= expected.pending);
    try std.testing.expect(summarized.principal_graph_deferred != 0);
    try std.testing.expect(summarized.counters.region_scopes < ordinary.counters.region_scopes);
    for ([_][]const u8{ "integer", "floating" }) |name| {
        const baseline = try ordinary.sourceInterface(target(module, name));
        const candidate = try summarized.sourceInterface(target(module, name));
        try std.testing.expect(baseline.evidence != 0 and candidate.evidence != 0);
        try std.testing.expectEqualDeep(ordinary.evidence.node(baseline.evidence), summarized.evidence.node(candidate.evidence));
    }
    for ([_][]const u8{ "argument_failure", "result_failure", "competing_failure" }) |name| {
        const expected_type = try ordinary.evidence.intern(.function, types.u32_type, types.u32_type, &.{});
        const actual_type = try summarized.evidence.intern(.function, types.u32_type, types.u32_type, &.{});
        try resultWitnessFailure(&ordinary, target(module, name), expected_type);
        try resultWitnessFailure(&summarized, target(module, name), actual_type);
        try std.testing.expectEqualDeep(ordinary.diagnostic, summarized.diagnostic);
        ordinary.diagnostic = null;
        summarized.diagnostic = null;
    }
    const builds = summarized.principal_graph_builds;
    _ = try summarized.sourceInterface(target(module, "generic"));
    try std.testing.expectEqual(builds, summarized.principal_graph_builds);
    try std.testing.expectEqual(@as(usize, 0), summarized.steps);
}

fn resultWitnessFailure(session: *evaluator.Session, reference: core.BindingRef, expected: type_evidence.Id) !void {
    var solved = session.bodyEvidenceFull(reference, expected, &.{}, &.{}) catch |err| {
        if (err == error.Declined) return;
        return err;
    };
    defer solved.deinit(session.allocator);
    return error.TestExpectedError;
}

fn sharedHeaderWitnessScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    for ([_]bool{ false, true }) |reuse| {
        var session = try evaluator.Session.init(allocator, &.{module.*});
        defer session.deinit();
        session.reuse_principal_graphs = reuse;
        _ = session.sourceInterface(target(module, "answer")) catch |err| {
            if (err != error.Declined) return err;
            const diagnostic = session.diagnostic orelse return error.TestExpectedDiagnostic;
            try std.testing.expectEqual(evaluator.Code.missing_member, diagnostic.code);
            try std.testing.expectEqualDeep(core.Span{ .start = 335, .end = 341 }, diagnostic.span);
            continue;
        };
        return error.TestExpectedError;
    }
}

test "shared written headers preserve the first missing receiver witness under allocation failure" {
    var module = try lower(@embedFile("captured-callable-fixtures/bound-cache-missing.blot"));
    defer module.deinit(a);
    try sharedHeaderWitnessScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, sharedHeaderWitnessScenario, .{&module});
}

test "result principal edges retain independent expected witnesses and ordinary failures under allocation pressure" {
    var module = try lower(
        \\type Box a is data = #Box a
        \\const Box.from = fn value => #Box value
        \\type Missing is data = #Missing U32
        \\const absent = fn value => value.absent
        \\const f_0 = fn value => @type.result "from" value
        \\const f_1 = fn value => f_0 (f_0 value)
        \\const f_2 = fn value => f_1 (f_1 value)
        \\const f_3 = fn value => f_2 (f_2 value)
        \\entry const generic = fn value => f_3 value
        \\entry const integer = fn (value: U32) => do:
        \\  let #Box result: Box U32 = f_0 value
        \\  return result
        \\entry const floating = fn (value: F32) => do:
        \\  let #Box result: Box F32 = f_0 value
        \\  return result
        \\entry const argument_failure = fn value => do:
        \\  let #Box result: Box U32 = f_0 (absent value)
        \\  return result
        \\entry const result_failure = fn (value: U32) -> U32 => do:
        \\  let #Missing result: Missing = f_0 value
        \\  return result
        \\entry const competing_failure = fn value => do:
        \\  let #Missing result: Missing = f_0 (absent value)
        \\  return result
    );
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const frozen_types = try a.dupe(types.Node, module.types.nodes);
    defer a.free(frozen_types);
    try resultPrincipalScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, resultPrincipalScenario, .{&module});
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualDeep(frozen_types, module.types.nodes);
}

test "closed result directed diamonds propagate destinations before expanding shared edges" {
    for ([_]bool{ false, true }) |double| for ([_]usize{ 4, 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a,
            \\type Box a is data = #Box a
            \\
        );
        try text.appendSlice(a, if (double) "const Box.from = fn (box: Box a) -> Box a => case box of\n  #Box value => #Box (@type.call \"add\" value value)\n" else "const Box.from = fn (box: Box a) -> Box a => box\n");
        try text.appendSlice(a, "const f_0 = fn value => @type.result \"from\" value\n");
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn value => f_{d} (f_{d} value)\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const integer = fn (value: U32) -> U32 => do:\n  let #Box result: Box U32 = f_{d} (#Box value)\n  return result\nentry const floating = fn (value: F32) -> F32 => do:\n  let #Box result: Box F32 = f_{d} (#Box value)\n  return result\n", .{ depth, depth });
        var module = try lowerPreludeProducer(text.items, &.{.add});
        defer module.deinit(a);
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        for ([_][]const u8{ "integer", "floating" }) |name| {
            const result = try session.sourceInterface(target(&module, name));
            if (result.evidence == 0 or session.counters.region_scopes > depth * 16 + 128) std.debug.print("result diamond depth={d}, {s}: {any}, scopes={d}, largest={d}, visits={d}, builds={d}\n", .{ depth, name, result, session.counters.region_scopes, session.counters.max_region_scopes, session.counters.solver_constraint_visits, session.principal_graph_builds });
            try std.testing.expect(result.evidence != 0 and result.pending == 0);
            try std.testing.expect(session.counters.region_scopes <= depth * 16 + 128);
            const jobs = session.call_summaries.jobs.items.len;
            const attempts = session.split_attempts;
            const repeated = try session.sourceInterface(target(&module, name));
            try std.testing.expectEqual(result.evidence, repeated.evidence);
            try std.testing.expectEqual(jobs, session.call_summaries.jobs.items.len);
            try std.testing.expectEqual(attempts, session.split_attempts);
            try std.testing.expectEqual(jobs, session.call_summaries.keys.count());
            if (depth <= 8) {
                var ordinary = try evaluator.Session.init(a, &.{module});
                defer ordinary.deinit();
                ordinary.reuse_principal_graphs = false;
                const baseline = try ordinary.sourceInterface(target(&module, name));
                try std.testing.expectEqualDeep(ordinary.evidence.node(baseline.evidence), session.evidence.node(result.evidence));
            }
        }
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    };
}

test "source owned representation predicates retain open diamonds without closing private rows" {
    for ([_][]const u8{
        "const f_0: Box a -> Box a where { type_rep (Box a) } = fn value => value\n",
        "const f_0: Unit -> Unit ! {| e} where { effect_rep ! {| e} } = fn () => ()\n",
    }) |leaf| for ([_]usize{ 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, "type Box a is data = #Box a\n");
        try text.appendSlice(a, leaf);
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn value => f_{d} (f_{d} value)\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const factory = do:\n  return f_{d}\n", .{depth});
        var module = try lower(text.items);
        defer module.deinit(a);
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        const interface = try session.sourceInterface(target(&module, "factory"));
        try std.testing.expect(interface.evidence == 0 and interface.pending != 0);
        if (session.counters.region_scopes > depth * 4 + 32 or session.principal_graph_deferred == 0) std.debug.print("representation {s}, depth={d}: {any}, deferred={d}\n", .{ leaf, depth, session.counters, session.principal_graph_deferred });
        try std.testing.expect(session.counters.region_scopes <= depth * 4 + 32);
        try std.testing.expect(session.counters.solver_constraint_visits <= depth * 256 + 256);
        try std.testing.expect(session.principal_graph_deferred != 0);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    };
}

fn representationHeaderScenario(allocator: std.mem.Allocator, module: *const core.Module, depth: usize) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const leaf = module.binding(target(module, "f_0").binding);
    const arrow = module.types.node(leaf.scheme.root);
    const variable = module.types.list(leaf.public_variables)[0];
    for ([_]types.Id{ types.u32_type, types.f32_type }) |scalar| {
        const box = try session.evidence.project(&module.types, arrow.a, &.{.{ .variable = variable, .evidence = scalar }});
        const expected = try session.evidence.intern(.function, box, box, &.{});
        var name: [32]u8 = undefined;
        const reference = target(module, try std.mem.print(&name, "f_{d}", .{depth}));
        var solved = try session.bodyEvidenceFull(reference, expected, &.{}, &.{});
        solved.deinit(allocator);
        try std.testing.expect(session.counters.solver_constraint_visits <= depth * 24 + 128);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    }
    const before = session.counters.solver_constraint_visits;
    try session.prepare(target(module, "factory"));
    const factory = (try session.cachedBindingValue(target(module, "factory"))).?;
    try std.testing.expectEqual(evaluator.ValueKind.closure, session.valueInfo(factory).kind);
    try std.testing.expect(session.counters.solver_constraint_visits - before <= depth * 24 + 128);
    try std.testing.expect(session.diagnostic == null);
}

test "representation headers share live public inputs across distinct wrapper products" {
    for ([_]usize{ 4, 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a,
            \\type Box a is data = #Box a
            \\entry const f_0: Box a -> Box a where { type_rep (Box a) } = fn value => value
            \\
        );
        for (1..depth + 1) |i| try text.print(a, "entry const f_{d} = fn value => f_{d} (f_{d} value)\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const factory = do:\n  return f_{d}\n", .{depth});
        var module = try lower(text.items);
        defer module.deinit(a);
        const nodes = try a.dupe(core.Node, module.nodes);
        defer a.free(nodes);
        const frozen = try a.dupe(types.Node, module.types.nodes);
        defer a.free(frozen);
        const obligations = try a.dupe(core.Obligation, module.obligations);
        defer a.free(obligations);
        try representationHeaderScenario(a, &module, depth);
        if (depth == 4) try @import("allocation_failures.zig").checkAllAllocationFailures(a, representationHeaderScenario, .{ &module, depth });
        try std.testing.expectEqualDeep(nodes, module.nodes);
        try std.testing.expectEqualDeep(frozen, module.types.nodes);
        try std.testing.expectEqualDeep(obligations, module.obligations);
    }
}

fn privateHeaderScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    var summarized = try evaluator.Session.init(allocator, &.{module.*});
    defer summarized.deinit();
    var expected: ?evaluator.Diagnostic = null;
    for ([_]*evaluator.Session{ &ordinary, &summarized }) |session| {
        const accepted = try session.sourceInterface(target(module, "accepted"));
        try std.testing.expect(accepted.evidence != 0);
        _ = session.sourceInterface(target(module, "missing")) catch |err| {
            if (err != error.Declined) return err;
            if (expected) |diagnostic| try std.testing.expectEqualDeep(diagnostic, session.diagnostic.?) else expected = session.diagnostic;
            session.diagnostic = null;
            const recovered = try session.sourceInterface(target(module, "accepted"));
            try std.testing.expectEqual(accepted.evidence, recovered.evidence);
            try std.testing.expectEqual(@as(usize, 0), session.steps);
            continue;
        };
        return error.TestExpectedError;
    }
}

test "mandatory headers preserve independent private field results and the missing second witness" {
    var module = try lower(
        \\const ignore_fields: a -> Unit where { field "left" a b, field "right" a c } = fn value => ()
        \\const twice = fn value => do:
        \\  let ignored = ignore_fields value
        \\  return ignore_fields value
        \\entry const accepted = fn (value: {left: U32, right: F32}) -> Unit => twice value
        \\entry const missing = fn (value: {left: U32}) -> Unit => twice value
    );
    defer module.deinit(a);
    const original = try a.dupe(types.Node, module.types.nodes);
    defer a.free(original);
    try privateHeaderScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, privateHeaderScenario, .{&module});
    try std.testing.expectEqualDeep(original, module.types.nodes);
}

fn comparisonGraphScenario(allocator: std.mem.Allocator, module: *const core.Module, depth: usize) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const generic = try session.sourceInterface(target(module, "generic"));
    try std.testing.expect(generic.evidence == 0 and generic.pending != 0);
    try std.testing.expect(session.principal_graph_deferred != 0);
    for ([_][]const u8{ "integer", "floating" }) |name| {
        const interface = try session.sourceInterface(target(module, name));
        try std.testing.expect(interface.evidence != 0);
        const arrow = session.evidence.node(interface.evidence);
        try std.testing.expectEqual(types.boolean, arrow.b);
    }
    try std.testing.expect(session.counters.solver_constraint_visits <= depth * 96 + 256);
    try std.testing.expect(session.counters.max_region_scopes <= depth * 4 + 8);
    const builds = session.principal_graph_builds;
    _ = try session.sourceInterface(target(module, "integer"));
    try std.testing.expectEqual(builds, session.principal_graph_builds);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    var graphs = session.call_summaries.principals.valueIterator();
    while (graphs.next()) |graph_| if (graph_.*) |graph| {
        try std.testing.expectEqual(@as(usize, 0), graph.types.versions.items.len);
        try std.testing.expectEqual(@as(usize, 0), graph.types.effects.versions.items.len);
    };
    if (depth != 4) return;
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    const expected = try ordinary.sourceInterface(target(module, "generic"));
    try std.testing.expectEqual(expected.evidence, generic.evidence);
    try std.testing.expectEqual(expected.generic, generic.generic);
    try std.testing.expectEqual(expected.selected, generic.selected);
    try std.testing.expect(generic.pending <= expected.pending);
    for ([_]*evaluator.Session{ &ordinary, &session }) |checked| {
        _ = checked.sourceInterface(target(module, "invalid")) catch |err| {
            if (err != error.Declined) return err;
            try std.testing.expectEqual(evaluator.Code.invalid_annotation, checked.diagnostic.?.code);
            if (checked == &session) try std.testing.expectEqualDeep(ordinary.diagnostic, session.diagnostic);
            continue;
        };
        return error.TestExpectedError;
    }
    ordinary.diagnostic = null;
    session.diagnostic = null;
    _ = session.sourceInterface(target(module, "factory")) catch |err| {
        if (err != error.Declined) return err;
        _ = ordinary.sourceInterface(target(module, "factory")) catch |failure| {
            if (failure != error.Declined) return failure;
            try std.testing.expectEqualDeep(ordinary.diagnostic, session.diagnostic);
            ordinary.diagnostic = null;
            session.diagnostic = null;
            const recovered = try session.sourceInterface(target(module, "floating"));
            try std.testing.expect(recovered.evidence != 0);
            return;
        };
        return error.TestExpectedError;
    };
    return error.TestExpectedError;
}

fn callbackGraphScenario(allocator: std.mem.Allocator, module: *const core.Module, depth: usize, curried: bool) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const generic = try session.sourceInterface(target(module, "generic"));
    if (generic.pending != 0) std.debug.print("callback source depth={d}: {any}\n", .{ depth, generic });
    try std.testing.expect(generic.evidence == 0 and generic.pending == 0);
    var callbacks: usize = 0;
    var second_stages: usize = 0;
    var graphs = session.call_summaries.normalized_principals.valueIterator();
    while (graphs.next()) |entry| {
        const graph = entry.*;
        for (graph.constraints) |constraint| if (constraint.kind == .callback_use) {
            try std.testing.expect(constraint.callback_interface and !constraint.solved);
            try std.testing.expectEqual(@as(u32, 0), constraint.callback_slot);
            callbacks += 1;
            second_stages += @intFromBool(constraint.callback_stage == 1);
        };
        try std.testing.expectEqual(@as(usize, 0), graph.types.versions.items.len);
        try std.testing.expectEqual(@as(usize, 0), graph.types.effects.versions.items.len);
    }
    if (callbacks == 0) std.debug.print("no callback graphs depth={d}, raw={d}, normalized={d}, {any}\n", .{ depth, session.call_summaries.principals.count(), session.call_summaries.normalized_principals.count(), session.counters });
    try std.testing.expect(callbacks != 0);
    try std.testing.expectEqual(curried, second_stages != 0);
    for ([_][]const u8{ "integer", "floating" }, [_]types.Id{ types.u32_type, types.f32_type }) |name, scalar| {
        const selected = try session.sourceInterface(target(module, name));
        try std.testing.expect(selected.evidence != 0 and selected.pending == 0);
        try std.testing.expectEqual(scalar, session.evidence.node(selected.evidence).b);
    }
    if (session.counters.region_scopes > depth * 24 + 128 or session.counters.max_region_scopes > 8) std.debug.print("callback depth={d}: {any}, graphs={d}\n", .{ depth, session.counters, session.call_summaries.normalized_principals.count() });
    try std.testing.expect(session.counters.region_scopes <= depth * 24 + 128);
    try std.testing.expect(session.counters.max_region_scopes <= 8);
    try std.testing.expect(session.counters.solver_constraint_visits <= depth * 512 + 512);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    if (depth != 4) return;
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    const reference = try ordinary.sourceInterface(target(module, "generic"));
    try std.testing.expectEqualDeep(reference, generic);
    for ([_][]const u8{ "integer", "floating" }) |name| {
        const expected = try ordinary.sourceInterface(target(module, name));
        const actual = try session.sourceInterface(target(module, name));
        try std.testing.expectEqualDeep(ordinary.evidence.node(expected.evidence), session.evidence.node(actual.evidence));
    }
}

test "owned callback obligations bound higher order diamonds and preserve curried and returned callback stages" {
    for ([_][]const u8{ "callback value", "callback value value", "callback () value" }, [_][]const u8{ "fn value => value", "fn value => fn ignored => value", "fn () => fn value => value" }, [_]bool{ false, true, true }) |invocation, producer, curried| {
        for ([_]usize{ 4, 8, 16, 64 }) |depth| {
            var text: std.ArrayList(u8) = .empty;
            defer text.deinit(a);
            try text.print(a, "type Count is data = #Count U32\ntype Other is data = #Other U32\nconst identity = {s}\nconst f_0 = fn callback => fn value => do:\n  let compared = @type.same #Count #Other\n  use result <- {s}\n  return result\n", .{ producer, invocation });
            for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn callback => fn value => do:\n  use first <- f_{d} callback value\n  return f_{d} callback first\n", .{ i, i - 1, i - 1 });
            try text.print(a, "entry const generic = do:\n  return f_{d}\nentry const integer = fn (value: U32) => f_{d} identity value\nentry const floating = fn (value: F32) => f_{d} identity value\n", .{ depth, depth, depth });
            var module = try lower(text.items);
            defer module.deinit(a);
            const nodes = try a.dupe(core.Node, module.nodes);
            defer a.free(nodes);
            const frozen = try a.dupe(types.Node, module.types.nodes);
            defer a.free(frozen);
            const obligations = try a.dupe(core.Obligation, module.obligations);
            defer a.free(obligations);
            try callbackGraphScenario(a, &module, depth, curried);
            if (depth == 4) try @import("allocation_failures.zig").checkAllAllocationFailures(a, callbackGraphScenario, .{ &module, depth, curried });
            try std.testing.expectEqualDeep(nodes, module.nodes);
            try std.testing.expectEqualDeep(frozen, module.types.nodes);
            try std.testing.expectEqualDeep(obligations, module.obligations);
        }
    }
}

fn callbackRowScenario(allocator: std.mem.Allocator, module: *const core.Module, depth: usize) !void {
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    var summarized = try evaluator.Session.init(allocator, &.{module.*});
    defer summarized.deinit();
    var name_buffer: [32]u8 = undefined;
    const name = try std.mem.print(&name_buffer, "f_{d}", .{depth});
    for ([_]*evaluator.Session{ &ordinary, &summarized }) |session| {
        const interface = try session.sourceInterface(target(module, "signature"));
        try std.testing.expect(interface.evidence != 0);
        const full = interface.evidence;
        const outer = session.evidence.node(full);
        const inner = session.evidence.node(outer.b);
        const callback = session.evidence.node(outer.a);
        try std.testing.expect(callback.c != 0 and inner.c == callback.c);
        var valid = try session.bodyEvidenceFull(target(module, name), full, &.{}, &.{});
        valid.deinit(allocator);
        const pure_inner = try session.evidence.intern(.function, inner.a, inner.b, &.{});
        const wrong = try session.evidence.internWithEffects(.function, outer.a, pure_inner, outer.c, &.{});
        try std.testing.expectError(error.Declined, session.bodyEvidenceFull(target(module, name), wrong, &.{}, &.{}));
        try std.testing.expectEqual(evaluator.Code.effect_mismatch, session.diagnostic.?.code);
    }
    try std.testing.expectEqualDeep(ordinary.diagnostic, summarized.diagnostic);
    ordinary.diagnostic = null;
    summarized.diagnostic = null;
    for ([_]*evaluator.Session{ &ordinary, &summarized }) |session| {
        const interface = try session.sourceInterface(target(module, "signature"));
        try std.testing.expect(interface.evidence != 0);
        const full = interface.evidence;
        var corrected = try session.bodyEvidenceFull(target(module, name), full, &.{}, &.{});
        corrected.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    }
    try std.testing.expect(summarized.counters.max_region_scopes <= 8);
}

test "callback latent operation rows remain exact through independent jobs and failed expected rows recover under allocation failure" {
    const depth: usize = 4;
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(a);
    try text.appendSlice(a,
        \\type Tick is effect = Unit -> U32
        \\const f_0 = fn callback => fn value => do:
        \\  use result <- callback value
        \\  return result
        \\entry const signature = fn (callback: U32 -> U32 ! {Tick}) => fn (value: U32) => do:
        \\  use result <- callback value
        \\  return result
        \\
    );
    for (1..depth + 1) |i| try text.print(a, "entry const f_{d} = fn callback => fn value => do:\n  use first <- f_{d} callback value\n  use second <- f_{d} callback first\n  return second\n", .{ i, i - 1, i - 1 });
    var module = try lower(text.items);
    defer module.deinit(a);
    const frozen = try a.dupe(types.Node, module.types.nodes);
    defer a.free(frozen);
    const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
    defer a.free(rows);
    try callbackRowScenario(a, &module, depth);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, callbackRowScenario, .{ &module, depth });
    try std.testing.expectEqualDeep(frozen, module.types.nodes);
    try std.testing.expectEqualDeep(rows, module.types.effects.rows);
}

fn callbackCaptureFallbackScenario(allocator: std.mem.Allocator, module: *const core.Module, depth: usize) !void {
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    var summarized = try evaluator.Session.init(allocator, &.{module.*});
    defer summarized.deinit();
    const reference = try ordinary.sourceInterface(target(module, "answer"));
    const actual = try summarized.sourceInterface(target(module, "answer"));
    try std.testing.expect(actual.evidence != 0 and actual.pending == 0);
    try std.testing.expectEqualDeep(reference, actual);
    try std.testing.expectEqualDeep(ordinary.evidence.node(reference.evidence), summarized.evidence.node(actual.evidence));
    try std.testing.expect(summarized.counters.region_scopes <= ordinary.counters.region_scopes + depth * 8 + 32);
    try std.testing.expect(summarized.counters.solver_constraint_visits <= ordinary.counters.solver_constraint_visits + depth * 8 + 32);
    try std.testing.expectEqual(@as(usize, 0), summarized.steps);
}

test "higher order callback capture fallback preserves source checking without duplicate transitive work" {
    for ([_]usize{ 4, 8 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, "type Count is data = #Count U32\ntype Other is data = #Other U32\nconst f_0 = fn callback => fn value => do:\n  let compared = @type.same #Count #Other\n  use result <- callback value\n  return result\n");
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn callback => fn value => do:\n  use first <- f_{d} callback value\n  use second <- f_{d} callback first\n  return second\n", .{ i, i - 1, i - 1 });
        try text.print(a, "const factory = do:\n  return f_{d}\nentry const answer = fn (delta: U32) => factory (fn value => @u32.add value delta) 7\n", .{depth});
        var module = try lower(text.items);
        defer module.deinit(a);
        const nodes = try a.dupe(core.Node, module.nodes);
        defer a.free(nodes);
        const frozen = try a.dupe(types.Node, module.types.nodes);
        defer a.free(frozen);
        try callbackCaptureFallbackScenario(a, &module, depth);
        if (depth == 4) try @import("allocation_failures.zig").checkAllAllocationFailures(a, callbackCaptureFallbackScenario, .{ &module, depth });
        try std.testing.expectEqualDeep(nodes, module.nodes);
        try std.testing.expectEqualDeep(frozen, module.types.nodes);
    }
}

fn sourceProvenGraphScenario(allocator: std.mem.Allocator, module: *const core.Module, depth: usize) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const generic = try session.sourceInterface(target(module, "generic"));
    if (!(generic.evidence == 0 and generic.generic and generic.pending == 0)) std.debug.print("source theorem interface: {any}\n", .{generic});
    try std.testing.expect(generic.evidence == 0 and generic.generic and generic.pending == 0);
    for ([_][]const u8{ "integer", "floating" }) |name| {
        const interface = try session.sourceInterface(target(module, name));
        try std.testing.expect(interface.evidence != 0);
    }
    try std.testing.expect(session.counters.region_scopes <= depth * 8 + 64);
    try std.testing.expect(session.counters.solver_constraint_visits <= depth * 256 + 256);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    var graphs = session.call_summaries.normalized_principals.valueIterator();
    while (graphs.next()) |graph| {
        try std.testing.expectEqual(@as(usize, 0), graph.*.types.versions.items.len);
        try std.testing.expectEqual(@as(usize, 0), graph.*.types.effects.versions.items.len);
    }
    if (depth != 4) return;
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    const expected = try ordinary.sourceInterface(target(module, "generic"));
    try std.testing.expectEqual(expected.generic, generic.generic);
    try std.testing.expectEqual(expected.pending, generic.pending);
    try std.testing.expectEqual(expected.selected, generic.selected);
    try std.testing.expectEqual(expected.evidence, generic.evidence);
    for ([_][]const u8{ "integer", "floating" }) |name| {
        const reference = try ordinary.sourceInterface(target(module, name));
        const actual = try session.sourceInterface(target(module, name));
        const expected_arrow = ordinary.evidence.node(reference.evidence);
        const actual_arrow = session.evidence.node(actual.evidence);
        try std.testing.expectEqual(expected_arrow.a, actual_arrow.a);
        try std.testing.expectEqual(expected_arrow.b, actual_arrow.b);
        try std.testing.expectEqual(expected_arrow.c, actual_arrow.c);
    }
}

fn revealedSourceEdgeScenario(allocator: std.mem.Allocator, module: *const core.Module, depth: usize) !void {
    const read_binding = blk: {
        try std.testing.expectEqual(@as(usize, 2), module.associated.len);
        break :blk module.associated[1].target.binding;
    };
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const generic = try session.sourceInterface(target(module, "generic"));
    var raw_parent = false;
    var originals = session.call_summaries.principals.valueIterator();
    while (originals.next()) |entry| {
        const graph = entry.* orelse continue;
        if (graph.key.target.binding != target(module, "parent").binding) continue;
        raw_parent = true;
        for (graph.constraints) |constraint| if (constraint.kind == .call_summary or constraint.kind == .scheme_use) {
            try std.testing.expect(constraint.target.binding != read_binding);
        };
    }
    if (!raw_parent) std.debug.print("no raw parent graph\n", .{});
    try std.testing.expect(raw_parent);
    {
        try std.testing.expect(generic.generic and generic.pending == 0);
        var checked_member = false;
        var revealed_member = false;
        var graphs = session.call_summaries.normalized_principals.valueIterator();
        while (graphs.next()) |entry| {
            const graph = entry.*;
            if (graph.key.target.binding == read_binding) checked_member = graph.source_complete;
            if (graph.key.target.binding == target(module, "parent").binding) for (graph.constraints) |constraint| {
                if (constraint.kind == .call_summary and constraint.target.binding == read_binding) revealed_member = true;
            };
            try std.testing.expectEqual(@as(usize, 0), graph.types.versions.items.len);
        }
        if (!checked_member) std.debug.print("selected member was not source complete\n", .{});
        try std.testing.expect(checked_member);
        if (!revealed_member) std.debug.print("no normalized parent edge\n", .{});
        try std.testing.expect(revealed_member);
        for ([_][]const u8{ "integer", "floating" }, [_]types.Id{ types.u32_type, types.f32_type }) |name, scalar| {
            const selected = try session.sourceInterface(target(module, name));
            try std.testing.expect(selected.evidence != 0 and selected.pending == 0);
            try std.testing.expectEqual(scalar, session.evidence.node(selected.evidence).b);
        }
        if (session.counters.region_scopes > depth * 12 + 128 or session.counters.solver_constraint_visits > depth * 512 + 512) std.debug.print("revealed edge depth={d}: {any}, graphs={d}/{d}\n", .{ depth, session.counters, session.call_summaries.principals.count(), session.call_summaries.normalized_principals.count() });
        try std.testing.expect(session.counters.region_scopes <= depth * 12 + 128);
        try std.testing.expect(session.counters.solver_constraint_visits <= depth * 512 + 512);
    }
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    if (depth != 4) return;
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    const expected = try ordinary.sourceInterface(target(module, "generic"));
    try std.testing.expectEqual(expected.evidence, generic.evidence);
    try std.testing.expectEqual(expected.generic, generic.generic);
    try std.testing.expectEqual(expected.selected, generic.selected);
    try std.testing.expectEqual(expected.pending, generic.pending);
    try std.testing.expectEqualDeep(ordinary.diagnostic, session.diagnostic);
}

test "source result equations check newly revealed selected edges through every allocation failure" {
    for ([_]usize{ 4, 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a,
            \\type Seed is data = #Seed
            \\type Box a is data = #Box a
            \\const Seed.build: a -> Seed -> Box a = fn value => fn seed => #Box value
            \\const f_0 = fn value => @type.call "build" value #Seed
            \\
        );
        try text.appendSlice(a, "entry const parent: a -> a = fn value => (f_0 value).read\nconst Box.read: Box a -> a = fn box => case box of\n  #Box value => value\n");
        try text.appendSlice(a, "const chain_0 = fn value => parent value\n");
        for (1..depth + 1) |i| try text.print(a, "const chain_{d} = fn value => do:\n  let discard = chain_{d} value\n  return chain_{d} value\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const generic = fn value => chain_{d} value\nentry const integer = fn (value: U32) -> U32 => chain_{d} value\nentry const floating = fn (value: F32) -> F32 => chain_{d} value\n", .{ depth, depth, depth });
        var module = try lower(text.items);
        defer module.deinit(a);
        const frozen = try a.dupe(types.Node, module.types.nodes);
        defer a.free(frozen);
        try revealedSourceEdgeScenario(a, &module, depth);
        if (depth == 4) try @import("allocation_failures.zig").checkAllAllocationFailures(a, revealedSourceEdgeScenario, .{ &module, depth });
        try std.testing.expectEqualDeep(frozen, module.types.nodes);
    }
}

fn sourceKnownOperandScenario(allocator: std.mem.Allocator, module: *const core.Module, depth: usize) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const generic = try session.sourceInterface(target(module, "generic"));
    if (generic.evidence == 0 or generic.generic or generic.pending != 0) std.debug.print("known operand depth={d}: interface={any}, counters={any}, graphs={d}, normalized={d}\n", .{ depth, generic, session.counters, session.call_summaries.principals.count(), session.call_summaries.normalized_principals.count() });
    try std.testing.expect(generic.evidence != 0 and !generic.generic and generic.pending == 0);
    const arrow = session.evidence.node(generic.evidence);
    try std.testing.expectEqual(types.u32_type, arrow.a);
    try std.testing.expectEqual(types.u32_type, arrow.b);
    if (session.counters.region_scopes > depth * 8 + 64 or session.counters.solver_constraint_visits > depth * 256 + 256) std.debug.print("known operand depth={d}: {any}\n", .{ depth, session.counters });
    try std.testing.expect(session.counters.region_scopes <= depth * 8 + 64);
    try std.testing.expect(session.counters.solver_constraint_visits <= depth * 256 + 256);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    if (depth != 4) return;
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    const expected = try ordinary.sourceInterface(target(module, "generic"));
    try std.testing.expectEqualDeep(ordinary.evidence.node(expected.evidence), arrow);
}

fn selectedSourceHeaderScenario(allocator: std.mem.Allocator, module: *const core.Module, row_failure: bool) !void {
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    var summarized = try evaluator.Session.init(allocator, &.{module.*});
    defer summarized.deinit();
    for ([_]*evaluator.Session{ &ordinary, &summarized }) |session| {
        if (row_failure) {
            const selected = try session.sourceInterface(target(module, "answer"));
            try std.testing.expect(selected.evidence != 0);
            const pure = try session.evidence.intern(.function, types.unit, types.u32_type, &.{});
            try resultWitnessFailure(session, target(module, "answer"), pure);
            try std.testing.expectEqual(evaluator.Code.effect_mismatch, session.diagnostic.?.code);
            continue;
        }
        _ = session.sourceInterface(target(module, "answer")) catch |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expectEqual(if (row_failure) evaluator.Code.effect_mismatch else evaluator.Code.missing_associated, session.diagnostic.?.code);
            continue;
        };
        return error.TestExpectedDiagnostic;
    }
    try std.testing.expectEqualDeep(ordinary.diagnostic, summarized.diagnostic);
    for ([_]*evaluator.Session{ &ordinary, &summarized }) |session| {
        session.diagnostic = null;
        const corrected = try session.sourceInterface(target(module, "good"));
        try std.testing.expect(corrected.evidence != 0);
        if (row_failure) {
            const selected = try session.sourceInterface(target(module, "answer"));
            var checked = try session.bodyEvidenceFull(target(module, "answer"), selected.evidence, &.{}, &.{});
            checked.deinit(allocator);
        }
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    }
}

test "source selected member graphs retain written header and closed caller row failures under allocation failure" {
    for ([_]bool{ false, true }) |row_failure| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, if (row_failure)
            \\type Tick is effect = Unit -> Unit
            \\type Box a is data = #Box {value: a}
            \\const Box.read: Box a -> a ! {Tick} = fn box => do:
            \\  use Tick ()
            \\  return box.value
            \\const f_0 = fn box => box.read
            \\
        else
            \\type Box a is data = #Box {value: a}
            \\const Box.read: Box a -> a where { associated "add" a a a } = fn box => box.value
            \\const f_0 = fn box => box.read
            \\
        );
        for (1..5) |i| try text.print(a, "const f_{d} = fn box => do:\n  {s} ignored {s} f_{d} box\n  return f_{d} box\n", .{ i, if (row_failure) "use" else "let", if (row_failure) "<-" else "=", i - 1, i - 1 });
        try text.appendSlice(a, "const factory = do:\n  return f_4\nentry const good = fn (value: U32) => value\n");
        try text.appendSlice(a, if (row_failure) "entry const answer = fn () => factory (#Box {value: 21})\n" else "entry const answer = fn () => factory (#Box {value: #True})\n");
        var module = try lowerPreludeProducer(text.items, &.{.add});
        defer module.deinit(a);
        try selectedSourceHeaderScenario(a, &module, row_failure);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, selectedSourceHeaderScenario, .{ &module, row_failure });
    }
}

fn seededSourceRowScenario(allocator: std.mem.Allocator, module: *const core.Module, depth: usize) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const generic = try session.sourceInterface(target(module, "convert"));
    try std.testing.expect(generic.evidence == 0 and generic.pending == 0);
    try std.testing.expect(session.call_summaries.normalized_principals.count() != 0);
    var seeded = false;
    var graphs = session.call_summaries.normalized_principals.valueIterator();
    while (graphs.next()) |entry| {
        const graph = entry.*;
        for (graph.constraints) |constraint| if (constraint.kind == .effect_operation and constraint.solved) {
            seeded = true;
            // The theorem retains the operation in its public row.
            try std.testing.expectEqual(@as(usize, 1), graph.types.rowLabels(graph.types.node(graph.root).c).len);
        };
    }
    try std.testing.expect(seeded);
    try std.testing.expect(session.counters.region_scopes <= depth * 8 + 64);
    const correct = try session.sourceInterface(target(module, "correct"));
    var checked = try session.bodyEvidenceFull(target(module, "convert"), correct.evidence, &.{}, &.{});
    checked.deinit(allocator);
    const pure = try session.evidence.intern(.function, types.u32_type, types.unit, &.{});
    try resultWitnessFailure(&session, target(module, "convert"), pure);
    try std.testing.expectEqual(evaluator.Code.effect_mismatch, session.diagnostic.?.code);
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    const expected = try ordinary.sourceInterface(target(module, "correct"));
    try std.testing.expectEqualDeep(ordinary.evidence.node(expected.evidence), session.evidence.node(correct.evidence));
    try resultWitnessFailure(&ordinary, target(module, "convert"), try ordinary.evidence.intern(.function, types.u32_type, types.unit, &.{}));
    try std.testing.expectEqualDeep(ordinary.diagnostic, session.diagnostic);
    session.diagnostic = null;
    var recovered = try session.bodyEvidenceFull(target(module, "convert"), correct.evidence, &.{}, &.{});
    recovered.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}

test "seeded source operation theorems retain escaping rows and exact pure caller failures under allocation failure" {
    for ([_]usize{ 4, 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, "type Tick is effect = Unit -> Unit\nconst f_0 = fn value => Tick ()\n");
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn value => do:\n  use ignored <- f_{d} value\n  return f_{d} value\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const convert = fn value => f_{d} value\nentry const correct = fn (value: U32) -> Unit => convert value\n", .{depth});
        var module = try lower(text.items);
        defer module.deinit(a);
        try seededSourceRowScenario(a, &module, depth);
        if (depth == 4) try @import("allocation_failures.zig").checkAllAllocationFailures(a, seededSourceRowScenario, .{ &module, depth });
    }
}

fn sourceHandlerGraphScenario(allocator: std.mem.Allocator, module: *const core.Module, depth: usize) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const generic = try session.sourceInterface(target(module, "generic"));
    try std.testing.expectEqual(@as(type_evidence.Id, 0), generic.evidence);
    if (session.counters.region_scopes > depth * 8 + 64 or session.counters.solver_constraint_visits > depth * 256 + 256) std.debug.print("handler depth={d}: {any}\n", .{ depth, session.counters });
    try std.testing.expect(session.counters.region_scopes <= depth * 8 + 64);
    try std.testing.expect(session.counters.solver_constraint_visits <= depth * 256 + 256);
    for ([_][]const u8{ "integer", "floating" }) |name| {
        const selected = try session.sourceInterface(target(module, name));
        try std.testing.expect(selected.evidence != 0 and selected.pending == 0);
        try std.testing.expectEqual(@as(u32, 0), session.evidence.node(selected.evidence).c);
    }
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    if (depth != 4) return;
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    const expected_generic = try ordinary.sourceInterface(target(module, "generic"));
    try std.testing.expectEqualDeep(expected_generic, generic);
    for ([_][]const u8{ "integer", "floating" }) |name| {
        const expected = try ordinary.sourceInterface(target(module, name));
        const actual = try session.sourceInterface(target(module, name));
        try std.testing.expectEqualDeep(ordinary.evidence.node(expected.evidence), session.evidence.node(actual.evidence));
    }
}

test "source closed first order handler equations bound independent argument diamonds" {
    for ([_]usize{ 4, 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a,
            \\type Signal a is effect = { get: Unit -> a }
            \\const unreachable: Unit -> U32 = fn () => @panic "provider called"
            \\const f_0: a -> a = fn value => do (@effect.provider (Signal.get U32) unreachable):
            \\  return value
            \\
        );
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn value => f_{d} (f_{d} value)\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const generic = fn value => f_{d} value\nentry const integer = fn (value: U32) -> U32 => f_{d} value\nentry const floating = fn (value: F32) -> F32 => f_{d} value\n", .{ depth, depth, depth });
        var module = try lower(text.items);
        defer module.deinit(a);
        const frozen = try a.dupe(types.Node, module.types.nodes);
        defer a.free(frozen);
        try sourceHandlerGraphScenario(a, &module, depth);
        if (depth == 4) try @import("allocation_failures.zig").checkAllAllocationFailures(a, sourceHandlerGraphScenario, .{ &module, depth });
        try std.testing.expectEqualDeep(frozen, module.types.nodes);
    }
}

test "source known associated operand equations propagate through open summary diamonds" {
    for ([_]usize{ 4, 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, "const U32.add = fn (left: U32) => fn (right: U32) => @u32.add left right\nconst f_0 = fn value => @type.call \"add\" value (@u32.add 0 1)\n");
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn value => do:\n  let ignored = f_{d} value\n  return f_{d} value\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const generic = fn value => f_{d} value\n", .{depth});
        var module = try lowerWithOptions(text.items, .{ .builtin_catalog = true });
        defer module.deinit(a);
        const frozen = try a.dupe(types.Node, module.types.nodes);
        defer a.free(frozen);
        try sourceKnownOperandScenario(a, &module, depth);
        if (depth == 4) try @import("allocation_failures.zig").checkAllAllocationFailures(a, sourceKnownOperandScenario, .{ &module, depth });
        try std.testing.expectEqualDeep(frozen, module.types.nodes);
    }
}

test "source proven physical nominal merge update and fixed comparison graphs bound open diamonds" {
    const Case = struct { declarations: []const u8 = "", leaf: []const u8, input: []const u8 = "value", result: []const u8 = "", closed: bool = false };
    for ([_]Case{
        .{ .leaf = "const f_0 = fn value => {left: value, right: value}.left\n" },
        .{ .leaf = "const f_0 = fn value => @record.merge {left: value} {right: value}\n", .result = ".left" },
        .{ .leaf = "const f_0 = fn value => do:\n  let record = {left: 0, keep: value}\n  record.left := value\n  return record.left\n" },
        .{ .declarations = "type Box a is data = #Box {left: a, keep: a}\n", .leaf = "const f_0 = fn value => (#Box {left: value, keep: value}).left\n" },
        .{ .declarations = "type Box a is data = #Box {left: a, keep: a}\n", .leaf = "const f_0 = fn (box: Box a) => box.left\n", .input = "(#Box {left: value, keep: value})" },
        .{ .declarations = "type Box a is data = #Box a\nconst Box.read: Box a -> a = fn box => case box of\n  #Box value => value\n", .leaf = "const f_0 = fn (box: Box a) => box.read\n", .input = "(#Box value)" },
        .{ .declarations = "type Count is data = #Count U32\ntype Other is data = #Other U32\n", .leaf = "const f_0 = fn ignored => @type.same #Count #Other\n", .closed = true },
    }) |case| for ([_]usize{ 4, 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, case.declarations);
        try text.appendSlice(a, case.leaf);
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn value => do:\n  let ignored = f_{d} value\n  return f_{d} value\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const generic = fn value => (f_{d} {s}){s}\n", .{ depth, case.input, case.result });
        for ([_][]const u8{ "integer", "floating" }, [_][]const u8{ "U32", "F32" }) |name, input| {
            try text.print(a, "entry const {s} = fn (value: {s}) -> {s} => (f_{d} {s}){s}\n", .{ name, input, if (case.closed) "Bool" else input, depth, case.input, case.result });
        }
        var module = try lower(text.items);
        defer module.deinit(a);
        const frozen = try a.dupe(types.Node, module.types.nodes);
        defer a.free(frozen);
        sourceProvenGraphScenario(a, &module, depth) catch |err| {
            std.debug.print("source theorem leaf at depth {d}: {s}\n", .{ depth, case.leaf });
            return err;
        };
        if (depth == 4) try @import("allocation_failures.zig").checkAllAllocationFailures(a, sourceProvenGraphScenario, .{ &module, depth });
        try std.testing.expectEqualDeep(frozen, module.types.nodes);
    };
}

test "type comparison principal graphs bound repeated diamonds and preserve original witness failures" {
    for ([_]usize{ 4, 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, "const f_0 = fn left => fn right => @type.same left right\n");
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn left => fn right => do:\n  let ignored = f_{d} left right\n  return f_{d} left right\n", .{ i, i - 1, i - 1 });
        try text.print(
            a,
            "entry const generic = fn value => f_{d} value value\n" ++
                "entry const integer = fn (value: U32) -> Bool => f_{d} value value\n" ++
                "entry const floating = fn (value: F32) -> Bool => f_{d} value value\n" ++
                "entry const invalid = fn (value: U32) -> Bool => do:\n  let ignored = f_{d} value value\n  return @type.same (@panic \"uncalled witness\") value\n" ++
                "entry const factory = do:\n  return f_{d}\n",
            .{ depth, depth, depth, depth, depth },
        );
        var module = try lower(text.items);
        defer module.deinit(a);
        const nodes = try a.dupe(core.Node, module.nodes);
        defer a.free(nodes);
        const frozen = try a.dupe(types.Node, module.types.nodes);
        defer a.free(frozen);
        const obligations = try a.dupe(core.Obligation, module.obligations);
        defer a.free(obligations);
        try comparisonGraphScenario(a, &module, depth);
        if (depth == 4) try @import("allocation_failures.zig").checkAllAllocationFailures(a, comparisonGraphScenario, .{ &module, depth });
        try std.testing.expectEqualDeep(nodes, module.nodes);
        try std.testing.expectEqualDeep(frozen, module.types.nodes);
        try std.testing.expectEqualDeep(obligations, module.obligations);
    }
}

fn typeHeadGraphScenario(allocator: std.mem.Allocator, module: *const core.Module, depth: usize) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const interface = try session.sourceInterface(target(module, "generic"));
    try std.testing.expect(interface.evidence == 0 and interface.pending != 0);
    try std.testing.expect(session.principal_graph_deferred != 0);
    const before = session.counters.solver_constraint_visits;
    try std.testing.expect(before <= depth * 24 + 128);
    const leaf = module.types.node(module.binding(target(module, "f_0").binding).scheme.root);
    const cell_node = module.types.node(leaf.b);
    try std.testing.expectEqual(types.Tag.nominal, cell_node.tag);
    const argument = module.types.nominalArguments(cell_node)[0];
    try std.testing.expectEqual(types.Tag.variable, module.types.node(argument).tag);
    for ([_]types.Id{ types.u32_type, types.f32_type }) |scalar| {
        const cell = try session.evidence.project(&module.types, leaf.b, &.{.{ .variable = argument, .evidence = scalar }});
        const operation = try session.evidence.effects.internOperation(types.builtin_state_read, &.{cell});
        const row = try session.evidence.effects.internRow(&.{operation});
        const expected = try session.evidence.internWithEffects(.function, cell, cell, row, &.{});
        var name: [32]u8 = undefined;
        var proof = try session.bodyEvidenceFull(target(module, try std.mem.print(&name, "f_{d}", .{depth})), expected, &.{}, &.{});
        proof.deinit(allocator);
    }
    try std.testing.expect(session.counters.solver_constraint_visits - before <= depth * 96 + 256);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    if (depth != 4) return;
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    const baseline = try ordinary.sourceInterface(target(module, "generic"));
    try std.testing.expectEqual(baseline.evidence, interface.evidence);
    try std.testing.expectEqual(baseline.generic, interface.generic);
    try std.testing.expectEqual(baseline.selected, interface.selected);
    try std.testing.expect(interface.pending <= baseline.pending);
    for ([_]bool{ false, true }) |wrong_row| {
        for ([_]*evaluator.Session{ &ordinary, &session }) |checked| {
            const cell = try checked.evidence.project(&module.types, leaf.b, &.{.{ .variable = argument, .evidence = types.u32_type }});
            const other = try checked.evidence.project(&module.types, leaf.b, &.{.{ .variable = argument, .evidence = types.f32_type }});
            const operation = try checked.evidence.effects.internOperation(types.builtin_state_read, &.{if (wrong_row) other else cell});
            const row = try checked.evidence.effects.internRow(&.{operation});
            const expected = try checked.evidence.internWithEffects(.function, if (wrong_row) cell else types.u32_type, cell, row, &.{});
            try resultWitnessFailure(checked, target(module, "f_4"), expected);
            try std.testing.expectEqual(if (wrong_row) evaluator.Code.effect_mismatch else evaluator.Code.type_mismatch, checked.diagnostic.?.code);
        }
        try std.testing.expectEqualDeep(ordinary.diagnostic, session.diagnostic);
        ordinary.diagnostic = null;
        session.diagnostic = null;
    }
    const cell = try session.evidence.project(&module.types, leaf.b, &.{.{ .variable = argument, .evidence = types.u32_type }});
    const operation = try session.evidence.effects.internOperation(types.builtin_state_read, &.{cell});
    const row = try session.evidence.effects.internRow(&.{operation});
    const expected = try session.evidence.internWithEffects(.function, cell, cell, row, &.{});
    var corrected = try session.bodyEvidenceFull(target(module, "f_4"), expected, &.{}, &.{});
    corrected.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}

test "type head principal graphs retain structured nominal results and exact state operation arguments" {
    for ([_]usize{ 4, 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a,
            \\type Cell a is data = #Cell a
            \\entry const f_0 = fn (witness: w) -> Cell a => @state.get witness
            \\
        );
        for (1..depth + 1) |i| try text.print(a, "entry const f_{d} = fn witness => do:\n  use ignored <- f_{d} witness\n  return f_{d} witness\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const generic = fn witness => do:\n  use cell <- f_{d} witness\n  let #Cell value = cell\n  return value\n", .{depth});
        var module = try lower(text.items);
        defer module.deinit(a);
        const nodes = try a.dupe(core.Node, module.nodes);
        defer a.free(nodes);
        const frozen = try a.dupe(types.Node, module.types.nodes);
        defer a.free(frozen);
        const obligations = try a.dupe(core.Obligation, module.obligations);
        defer a.free(obligations);
        try typeHeadGraphScenario(a, &module, depth);
        if (depth == 4) try @import("allocation_failures.zig").checkAllAllocationFailures(a, typeHeadGraphScenario, .{ &module, depth });
        try std.testing.expectEqualDeep(nodes, module.nodes);
        try std.testing.expectEqualDeep(frozen, module.types.nodes);
        try std.testing.expectEqualDeep(obligations, module.obligations);
    }
}

fn closedHeadGraphScenario(allocator: std.mem.Allocator, module: *const core.Module, depth: usize) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    _ = try session.sourceInterface(target(module, "factory"));
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    try session.prepare(target(module, "factory"));
    const value = (try session.cachedBindingValue(target(module, "factory"))).?;
    try std.testing.expectEqual(evaluator.ValueKind.closure, session.valueInfo(value).kind);
    if (session.counters.region_scopes > depth * 4 + 32 or session.counters.solver_constraint_visits > depth * 16 + 128) std.debug.print("source closed witness depth={d}: {any}\n", .{ depth, session.counters });
    try std.testing.expect(session.counters.region_scopes <= depth * 4 + 32);
    try std.testing.expect(session.counters.solver_constraint_visits <= depth * 16 + 128);
    try std.testing.expect(session.principal_graph_deferred != 0);
}

test "source closed state witnesses bound diamonds with unrelated unknown public inputs" {
    for ([_][]const u8{
        "const f_0 = fn ignored => @state.get (#Cell 0)\n",
        "const f_0 = fn (witness: Cell a) -> Cell a => @state.get witness\n",
    }) |leaf| for ([_]usize{ 4, 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, "type Cell a is data = #Cell a\n");
        try text.appendSlice(a, leaf);
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn witness => do:\n  use ignored <- f_{d} witness\n  return f_{d} witness\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const factory = do:\n  return f_{d}\n", .{depth});
        var module = try lower(text.items);
        defer module.deinit(a);
        const frozen = try a.dupe(types.Node, module.types.nodes);
        defer a.free(frozen);
        try closedHeadGraphScenario(a, &module, depth);
        if (depth == 4) try @import("allocation_failures.zig").checkAllAllocationFailures(a, closedHeadGraphScenario, .{ &module, depth });
        try std.testing.expectEqualDeep(frozen, module.types.nodes);
    };
}

test "result principal jobs defer Never witness diagnostics to their original source entry" {
    var module = try lower(
        \\type Box a is data = #Box a
        \\const Box.from = fn value => #Box value
        \\const convert = fn value => do:
        \\  let same = @type.same (@panic "uncalled witness") value
        \\  return @type.result "from" value
        \\entry const run = fn (value: U32) -> U32 => do:
        \\  let #Box result: Box U32 = convert value
        \\  return result
    );
    defer module.deinit(a);
    for ([_]bool{ false, true }) |sharing| {
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        session.reuse_principal_graphs = sharing;
        _ = session.sourceInterface(target(&module, "run")) catch |err| {
            try std.testing.expectEqual(error.Declined, err);
            try std.testing.expectEqual(evaluator.Code.invalid_annotation, session.diagnostic.?.code);
            const point = module.sourceNamePoint(target(&module, "run").binding);
            try std.testing.expectEqual(core.Span{ .start = point, .end = point }, session.diagnostic.?.span);
            try std.testing.expectEqual(@as(usize, 0), session.steps);
            if (sharing) {
                var declined = session.split_declined != 0;
                var graphs = session.call_summaries.principals.valueIterator();
                while (graphs.next()) |graph| declined = declined or graph.* == null;
                try std.testing.expect(declined);
            }
            continue;
        };
        return error.TestUnexpectedResult;
    }
}

fn resultPrincipalWitnessScenario(allocator: std.mem.Allocator, module: *const core.Module, effects: bool) !void {
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.reuse_principal_graphs = false;
    var summarized = try evaluator.Session.init(allocator, &.{module.*});
    defer summarized.deinit();
    for ([_]*evaluator.Session{ &ordinary, &summarized }) |session| {
        const complete = try session.evidence.project(&module.types, module.binding(target(module, "correct").binding).scheme.root, &.{});
        var first = try session.bodyEvidenceFull(target(module, "convert"), complete, &.{}, &.{});
        first.deinit(allocator);
        const arrow = session.evidence.node(complete);
        const incompatible = try session.evidence.intern(.function, if (effects) types.f32_type else types.u32_type, arrow.b, &.{});
        try resultWitnessFailure(session, target(module, "convert"), incompatible);
        try std.testing.expectEqual(if (effects) evaluator.Code.effect_mismatch else evaluator.Code.type_mismatch, session.diagnostic.?.code);
    }
    try std.testing.expectEqualDeep(ordinary.diagnostic, summarized.diagnostic);
    try std.testing.expect(summarized.split_accepted != 0);
    ordinary.diagnostic = null;
    summarized.diagnostic = null;
    for ([_]*evaluator.Session{ &ordinary, &summarized }) |session| {
        const complete = try session.evidence.project(&module.types, module.binding(target(module, "correct").binding).scheme.root, &.{});
        var corrected = try session.bodyEvidenceFull(target(module, "convert"), complete, &.{}, &.{});
        corrected.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    }
}

test "result principal judgments keep per use input and effect failures authoritative and recover under allocation failure" {
    for ([_]bool{ false, true }) |effects| {
        const pure =
            \\type Out is data = #Out U32
            \\const Out.from = fn (value: F32) => #Out 42
            \\const leaf = fn value => @type.result "from" value
            \\entry const convert = fn value => leaf value
            \\entry const correct = fn (value: F32) -> Out => convert value
            \\entry const answer = 42
        ;
        const effectful =
            \\type Out is data = #Out U32
            \\type Tick is effect = Unit -> Unit
            \\const Out.from = fn (value: F32) => do:
            \\  use Tick ()
            \\  return #Out 42
            \\const leaf = fn value => @type.result "from" value
            \\entry const convert = fn value => leaf value
            \\entry const correct: F32 -> Out ! {Tick} = fn value => convert value
            \\entry const answer = 42
        ;
        var module = try lower(if (effects) effectful else pure);
        defer module.deinit(a);
        try resultPrincipalWitnessScenario(a, &module, effects);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, resultPrincipalWitnessScenario, .{ &module, effects });
    }
}

test "written predicate schemes share fresh requirements without expanding source chains or mutating inputs" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(a);
    try text.appendSlice(a,
        \\type N is data = #N U32
        \\const N.add = fn left => fn right => case left, right of
        \\  #N a, #N b => #N (@u32.add a b)
        \\const f_0: a -> a where { associated "add" a a a } = fn value => @type.call "add" value value
        \\
    );
    for (1..17) |i| try text.print(a, "const f_{d} = fn value => f_{d} value\n", .{ i, i - 1 });
    try text.appendSlice(a,
        \\entry const run = fn (value: U32) => case f_16 (#N value) of
        \\  #N result => result
        \\
    );
    var module = try lower(text.items);
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const extra = try a.dupe(u32, module.extra);
    defer a.free(extra);
    try qualifiedSchemeScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, qualifiedSchemeScenario, .{&module});
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualSlices(u32, extra, module.extra);
}

test "closed written predicate diamonds share required work under complete public inputs" {
    for ([_]usize{ 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, "const f_0: a -> a where { associated \"add\" a a a } = fn value => @type.call \"add\" value value\n");
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn value => f_{d} (f_{d} value)\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const integer = fn (value: U32) -> U32 => f_{d} value\nentry const floating = fn (value: F32) -> F32 => f_{d} value\n", .{ depth, depth });
        var module = try lowerPreludeProducer(text.items, &.{.add});
        defer module.deinit(a);
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        for ([_]struct { []const u8, type_evidence.Id }{ .{ "integer", types.u32_type }, .{ "floating", types.f32_type } }) |instance| {
            const result = try session.sourceInterface(target(&module, instance[0]));
            if (result.evidence == 0 or result.pending != 0) std.debug.print("closed written {s}, depth={d}: result={any}, scopes={d}, visits={d}\n", .{ instance[0], depth, result, session.counters.region_scopes, session.counters.solver_constraint_visits });
            try std.testing.expect(result.evidence != 0 and result.pending == 0);
            const arrow = session.evidence.node(result.evidence);
            try std.testing.expectEqual(instance[1], arrow.a);
            try std.testing.expectEqual(instance[1], arrow.b);
        }
        try std.testing.expect(session.counters.max_region_scopes <= 8);
        try std.testing.expect(session.counters.solver_constraint_visits <= depth * 20 + 128);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    }
}

fn constantHeaderScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    _ = session.sourceInterface(target(module, "factory")) catch |err| {
        if (err != error.Declined) return err;
        try std.testing.expectEqual(evaluator.Code.missing_associated, session.diagnostic.?.code);
        if (module.bindings.len < 20) {
            var ordinary = try evaluator.Session.init(allocator, &.{module.*});
            defer ordinary.deinit();
            ordinary.reuse_principal_graphs = false;
            _ = ordinary.sourceInterface(target(module, "factory")) catch |failed| {
                if (failed != error.Declined) return failed;
                try std.testing.expectEqualDeep(ordinary.diagnostic, session.diagnostic);
            };
            try std.testing.expect(ordinary.diagnostic != null);
        }
        try std.testing.expect(session.counters.solver_constraint_visits <= module.bindings.len * 12 + 128);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
        return;
    };
    return error.TestExpectedError;
}

test "closed mandatory headers remain bounded with unrelated generic public inputs" {
    for ([_]usize{ 4, 8, 16, 64 }) |depth| {
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(a);
        try text.appendSlice(a, "const f_0: a -> a where { associated \"add\" Bool Bool Bool } = fn value => value\n");
        for (1..depth + 1) |i| try text.print(a, "const f_{d} = fn value => f_{d} (f_{d} value)\n", .{ i, i - 1, i - 1 });
        try text.print(a, "entry const factory = do:\n  return f_{d}\n", .{depth});
        var module = try lower(text.items);
        defer module.deinit(a);
        try constantHeaderScenario(a, &module);
        if (depth == 4) try @import("allocation_failures.zig").checkAllAllocationFailures(a, constantHeaderScenario, .{&module});
    }
}

fn summaryAdmissionScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const first = try session.sourceInterface(target(module, "run"));
    try std.testing.expect(first.evidence != 0);
    const visits = session.summary_eligibility_visits;
    try std.testing.expect(visits != 0 and visits <= 34);
    const second = try session.sourceInterface(target(module, "run"));
    try std.testing.expect(second.evidence != 0);
    try std.testing.expectEqual(visits, session.summary_eligibility_visits);
}

fn dispatchedSchemeScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for ([_]struct { name: []const u8, scalar: types.Id }{
        .{ .name = "integer", .scalar = types.u32_type },
        .{ .name = "floating", .scalar = types.f32_type },
        .{ .name = "associated", .scalar = types.u32_type },
        .{ .name = "constructed", .scalar = types.f32_type },
    }) |entry| {
        const selected = try session.sourceInterface(target(module, entry.name));
        try std.testing.expect(selected.evidence != 0);
        const arrow = session.evidence.node(selected.evidence);
        try std.testing.expectEqual(type_evidence.Tag.function, arrow.tag);
        try std.testing.expectEqual(entry.scalar, arrow.a);
        try std.testing.expectEqual(entry.scalar, arrow.b);
    }
    // The written residuals, not the wrappers inside each implementation,
    // supply the source interface. Every use still has its own fresh scope.
    try std.testing.expect(session.counters.max_region_scopes <= 6);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    try std.testing.expect(session.diagnostic == null);
}

test "dispatched written schemes preserve fresh argument and result predicates without body expansion" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(a);
    try text.appendSlice(a,
        \\type Integer is data = #Integer U32
        \\type Float is data = #Float F32
        \\const Integer.add = fn left => fn right => case left, right of
        \\  #Integer x, #Integer y => #Integer (@u32.add x y)
        \\const Float.add = fn left => fn right => case left, right of
        \\  #Float x, #Float y => #Float (@f32.add x y)
        \\const f_0: a -> a where { associated "add" a a a } = fn value => @type.call "add" value value
        \\
    );
    for (1..9) |i| try text.print(a, "const f_{d} = fn value => f_{d} value\n", .{ i, i - 1 });
    try text.appendSlice(a,
        \\type Box a is data = #Box a
        \\const Box.twice: Box a -> Box a where { associated "add" a a a } = fn box => case box of
        \\  #Box value => do:
        \\    let first = f_8 value
        \\    return #Box (f_8 first)
        \\const Box.add: Box a -> Box a -> Box a where { associated "add" a a a } = fn left => fn right => case left, right of
        \\  #Box x, #Box y => #Box (f_8 x)
        \\const Box.from: a -> Box a where { associated "add" a a a } = fn value => #Box (f_8 value)
        \\const add = fn left => fn right => @type.call "add" left right
        \\const from = fn value => @type.result "from" value
        \\entry const integer = fn (value: U32) => case (#Box (#Integer value)).twice of
        \\  #Box (#Integer result) => result
        \\entry const floating = fn (value: F32) => case (#Box (#Float value)).twice of
        \\  #Box (#Float result) => result
        \\entry const associated = fn (value: U32) => case add (#Box (#Integer value)) (#Box (#Integer value)) of
        \\  #Box (#Integer result) => result
        \\entry const constructed = fn (value: F32) => do:
        \\  let #Box (#Float result): Box Float = from (#Float value)
        \\  return result
        \\
    );
    var module = try lower(text.items);
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const graph = try a.dupe(types.Node, module.types.nodes);
    defer a.free(graph);
    const obligations = try a.dupe(core.Obligation, module.obligations);
    defer a.free(obligations);
    try dispatchedSchemeScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, dispatchedSchemeScenario, .{&module});
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualDeep(graph, module.types.nodes);
    try std.testing.expectEqualDeep(obligations, module.obligations);
}

test "summary admission visits a shared callee graph once and publishes atomically" {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(a);
    try text.appendSlice(a,
        \\type N is data = #N U32
        \\const N.add = fn left => fn right => case left, right of
        \\  #N a, #N b => #N (@u32.add a b)
        \\const f_0 = fn value => @type.call "add" value value
        \\
    );
    for (1..33) |i| try text.print(a, "const f_{d} = fn value => f_{d} value\n", .{ i, i - 1 });
    try text.appendSlice(a,
        \\entry const run = fn (value: U32) => case f_32 (#N value) of
        \\  #N result => result
        \\
    );
    var module = try lower(text.items);
    defer module.deinit(a);
    try summaryAdmissionScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, summaryAdmissionScenario, .{&module});
}

const contextual_result_prelude =
    \\infixl 60 (+) = add
    \\const add = fn left => fn right => @type.call "add" left right
    \\const U32.add = fn left => fn right => @u32.add left right
    \\const F32.add = fn left => fn right => @f32.add left right
    \\const from = fn value => @type.result "from" value
    \\const F32.from = fn value => value.to_f32
    \\const U32.from = fn value => value.to_u32
    \\const U32.to_f32 = fn value => @u32.to_f32 value
    \\const F32.to_u32 = fn value => @f32.to_u32 value
    \\const F32.to_f32 = fn (value: F32) => value
    \\const U32.to_u32 = fn (value: U32) => value
    \\const sqrt = fn value => @f32.sqrt value
    \\const ceil = fn value => @f32.ceil value
    \\const count = 42
;

fn contextualResultScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    var proof = try session.bodyEvidenceFull(target(module, "nested"), 0, &.{}, &.{});
    defer proof.deinit(allocator);
    try std.testing.expect(proof.types.len != 0);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    const nested = try session.richValue(target(module, "nested"));
    try std.testing.expectEqual(scalar_ops.Value{ .scalar = .u32, .bits = 9 }, session.valueScalar(nested).?);
    try std.testing.expectEqual(types.u32_type, session.valueEvidence(nested));
    try std.testing.expectEqual(scalar_ops.Value{ .scalar = .f32, .bits = @bitCast(@as(f32, 42.5)) }, try session.value(target(module, "floating")));
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "delayed"))).bits);
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "recursive"))).bits);
    var snapshot = try session.copySnapshot(allocator);
    defer snapshot.deinit(allocator);
    try std.testing.expectEqual(types.u32_type, snapshot.value_evidence[nested]);
    try std.testing.expect(session.diagnostic == null);
}

test "constant contextual result evidence waits for receiver owners before one-sided inference" {
    var module = try lowerWithOptions(contextual_result_prelude ++
        \\
        \\type Number is data = #Number U32
        \\type Holder is data = #Holder {direction:Number}
        \\const Number.add = fn left => fn (right: U32) => case left of
        \\  #Number value => @u32.add value right
        \\const Number.walk = fn (left: Number) => fn (remaining: U32) -> U32 =>
        \\  if @u32.eq remaining 0 then 42 else @type.call "walk" left (@u32.sub remaining 1)
        \\const holder = #Holder {direction: #Number 40}
        \\const combine = fn value => value.direction + 2
        \\entry const nested = from (ceil (sqrt (from count))) + 2
        \\entry const floating = from count + 0.5
        \\entry const delayed = combine holder
        \\entry const recursive = @type.call "walk" (#Number 0) 4
    , .{ .builtin_catalog = true });
    defer module.deinit(a);
    const frozen_nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(frozen_nodes);
    const frozen_types = try a.dupe(types.Node, module.types.nodes);
    defer a.free(frozen_types);
    try contextualResultScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, contextualResultScenario, .{&module});
    try std.testing.expectEqualDeep(frozen_nodes, module.nodes);
    try std.testing.expectEqualDeep(frozen_types, module.types.nodes);
}

test "constant contextual evidence preserves ambiguity and selected result mismatches" {
    var ambiguous = try lowerWithOptions(contextual_result_prelude ++ "\nentry const answer = from count\n", .{ .builtin_catalog = true });
    defer ambiguous.deinit(a);
    const unknown = try evaluator.evaluate(a, &.{ambiguous}, target(&ambiguous, "answer"), .{});
    try std.testing.expectEqual(evaluator.Code.ambiguous_associated, unknown.diagnostic.?.code);
    var mismatch = try lowerWithOptions(contextual_result_prelude ++ "\nentry const answer: Bool = from count + 2\n", .{ .builtin_catalog = true });
    defer mismatch.deinit(a);
    const invalid = try evaluator.evaluate(a, &.{mismatch}, target(&mismatch, "answer"), .{});
    try std.testing.expectEqual(evaluator.Code.type_mismatch, invalid.diagnostic.?.code);
}

fn ambientMemberScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const action = target(module, "action");
    const expected = try session.evidence.project(&module.types, module.binding(action.binding).scheme.root, &.{});
    try std.testing.expect(session.evidence.view().effects.rowLabels(session.evidence.node(expected).c).len != 0);
    var proof = try session.bodyEvidenceFull(action, expected, &.{}, &.{});
    defer proof.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "answer"))).bits);
    const callback = try session.evidence.internWithEffects(.function, types.unit, types.u32_type, session.evidence.node(expected).c, &.{});
    const forbidden = try session.evidence.internWithEffects(.function, callback, types.u32_type, session.evidence.node(expected).c, &.{});
    const rejected = session.bodyEvidenceFull(target(module, "strict"), forbidden, &.{}, &.{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.RequestUnwind => return error.TestUnexpectedResult,
        error.Declined => {
            try std.testing.expectEqual(evaluator.Code.effect_mismatch, session.diagnostic.?.code);
            return;
        },
    };
    allocator.free(rejected.types);
    allocator.free(rejected.rows);
    return error.TestUnexpectedResult;
}

test "selected pure members admit ambient effects while callback inputs retain exact rows" {
    var module = try lower(
        \\effect Read: Unit -> U32
        \\type Box is data = #Box U32
        \\const Box.read: Box -> U32 = fn box => case box of
        \\  #Box value => value
        \\const Box.invoke: Box -> (Unit -> U32) -> U32 = fn box => fn callback => callback ()
        \\const read = fn value => value.read
        \\entry const action = fn () => do:
        \\  use before <- Read ()
        \\  return @u32.add before (read (#Box 2))
        \\const provider = @effect.provider Read (fn () => 40)
        \\entry const answer = do provider:
        \\  return action ()
        \\entry const strict = fn callback => (#Box 2).invoke callback
    );
    defer module.deinit(a);
    try ambientMemberScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, ambientMemberScenario, .{&module});
}

fn curriedAmbientScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    var proof = try session.bodyEvidenceFull(target(module, "answer"), 0, &.{}, &.{});
    defer proof.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "constant"))).bits);
    const pure_type = try session.evidence.project(&module.types, module.binding(target(module, "pure").binding).scheme.root, &.{});
    const effectful_type = try session.evidence.project(&module.types, module.binding(target(module, "effectful").binding).scheme.root, &.{});
    const pure = try session.richValue(target(module, "pure"));
    const retained_type = session.valueEvidence(pure);
    const admitted = try session.specializeClosure(pure, effectful_type);
    try std.testing.expectEqual(effectful_type, session.valueEvidence(admitted));
    try std.testing.expectEqual(retained_type, session.valueEvidence(pure));
    const effectful = try session.richValue(target(module, "effectful"));
    _ = session.specializeClosure(effectful, pure_type) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.RequestUnwind => return error.TestUnexpectedResult,
        error.Declined => {
            try std.testing.expectEqual(evaluator.Code.effect_mismatch, session.diagnostic.?.code);
            return;
        },
    };
    return error.TestUnexpectedResult;
}
test "curried member results and retained pure closures admit ambient rows without dropping required effects" {
    var module = try lower(
        \\effect Read: Unit -> U32
        \\type Box is data = #Box U32
        \\const Box.add: Box -> U32 -> U32 = fn box => fn offset => case box of
        \\  #Box value => @u32.add value offset
        \\const reader = @effect.provider Read (fn () => 2)
        \\entry const answer = fn () => do reader:
        \\  use offset <- Read ()
        \\  return (#Box 40).add offset
        \\entry const constant = answer ()
        \\entry const pure = fn () -> U32 => 42
        \\entry const effectful = fn () => Read ()
    );
    defer module.deinit(a);
    try curriedAmbientScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, curriedAmbientScenario, .{&module});
}

fn nestedScopeScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const builder = try session.richValue(target(module, "builder"));
    const scope = session.valueChildren(session.valueChildren(builder)[0])[1];
    const before = session.steps;
    const tail = try session.evidence.intern(.product, 0, 0, &.{ types.f32_type, types.unit });
    const world = try session.evidence.intern(.product, 0, 0, &.{ types.u32_type, tail });
    const array = try session.evidence.intern(.array, types.u32_type, 0, &.{});
    var labels: std.ArrayList(u32) = .empty;
    defer labels.deinit(allocator);
    for (module.operation_values) |operation| {
        const identity = types.NominalIdentity{ .unit = if (operation.identity.unit == 0) 1 else operation.identity.unit, .decl = operation.identity.decl };
        for ([_]types.Id{ types.u32_type, types.f32_type }) |argument| {
            const label = try session.evidence.effects.internOperation(identity, &.{argument});
            if (std.mem.findScalar(u32, labels.items, label) == null) try labels.append(allocator, label);
        }
    }
    const row = try session.evidence.effects.internRow(labels.items);
    const callback = try session.evidence.internWithEffects(.function, types.unit, array, row, &.{});
    const result = try session.evidence.intern(.product, 0, 0, &.{ world, array });
    const inner = try session.evidence.intern(.function, callback, result, &.{});
    const expected = try session.evidence.intern(.function, world, inner, &.{});
    const specialized = try session.specializeClosure(scope, expected);
    try std.testing.expectEqual(expected, session.valueEvidence(specialized));
    try std.testing.expectEqual(before, session.steps);
    try std.testing.expect(session.valueChildren(specialized).len != 0);
    try std.testing.expect(session.diagnostic == null);
}
test "nested State scope closures prove captured callback rows before freezing their graph" {
    var module = try lower(
        \\type State a is effect = { get: Unit -> a, set: a -> Unit }
        \\type Builder [world,scope] is data = #Builder { initial: world, scope: world -> scope }
        \\const empty = fn () => do:
        \\  let scope = fn world => fn action => do:
        \\    use result <- action ()
        \\    return (world,result)
        \\  return #Builder { initial: (), scope }
        \\const insert = fn initial => fn builder => do:
        \\  let #Builder { initial: previous_initial, scope: previous_scope } = builder
        \\  let scope = fn world => fn action => do:
        \\    let (current,previous) = world
        \\    use outcome <- @effect.run State.get State.set current (fn () => previous_scope previous action)
        \\    let (next,(previous_next,result)) = outcome
        \\    return ((next,previous_next),result)
        \\  return #Builder { initial: (initial,previous_initial), scope }
        \\entry const builder = insert 42 (insert 1.5 (empty ()))
    );
    defer module.deinit(a);
    const frozen_nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(frozen_nodes);
    const frozen_types = try a.dupe(types.Node, module.types.nodes);
    defer a.free(frozen_types);
    try nestedScopeScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, nestedScopeScenario, .{&module});
    try std.testing.expectEqualDeep(frozen_nodes, module.nodes);
    try std.testing.expectEqualDeep(frozen_types, module.types.nodes);
}

fn capturedAmbientScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const raw = try session.richValue(target(module, "checkpoint"));
    const previous = session.valueChildren(raw)[0];
    const prior_evidence = session.valueEvidence(previous);
    const raw_evidence = session.valueEvidence(raw);
    const expected = try session.evidence.project(&module.types, module.binding(target(module, "required").binding).scheme.root, &.{});
    const before = session.steps;
    const specialized = try session.specializeClosure(raw, expected);
    try std.testing.expectEqual(before, session.steps);
    try std.testing.expectEqual(expected, session.valueEvidence(specialized));
    try std.testing.expectEqual(raw_evidence, session.valueEvidence(raw));
    try std.testing.expectEqual(prior_evidence, session.valueEvidence(previous));
    const frozen_previous = session.valueChildren(specialized)[0];
    try std.testing.expectEqual(@as(usize, 0), session.evidence.view().effects.rowLabels(session.evidence.node(session.valueEvidence(frozen_previous)).c).len);
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "answer"))).bits);
    const pure = try session.evidence.intern(.function, types.unit, types.unit, &.{});
    try expectCaptureMismatch(&session, raw, pure);
    session.diagnostic = null;
    const strict = try session.richValue(target(module, "captured_strict"));
    const callback = try session.evidence.internWithEffects(.function, types.unit, types.unit, session.evidence.node(expected).c, &.{});
    const incompatible = try session.evidence.internWithEffects(.function, callback, types.unit, session.evidence.node(expected).c, &.{});
    try expectCaptureMismatch(&session, strict, incompatible);
}

fn expectCaptureMismatch(session: *evaluator.Session, value: evaluator.ValueId, expected: u32) !void {
    _ = session.specializeClosure(value, expected) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.RequestUnwind => return error.TestUnexpectedResult,
        error.Declined => {
            try std.testing.expectEqual(evaluator.Code.effect_mismatch, session.diagnostic.?.code);
            return;
        },
    };
    return error.TestUnexpectedResult;
}

test "captured pure checkpoint rows admit ambient effects while retaining the original alias" {
    var module = try lower(
        \\effect Read: Unit -> U32
        \\effect Touch: U32 -> Unit
        \\entry const previous: Unit -> Unit = fn () => ()
        \\const extend = fn previous => fn () => do:
        \\  use previous ()
        \\  use value <- Read ()
        \\  use Touch value
        \\  return ()
        \\entry const checkpoint = extend previous
        \\entry const required = fn () => do:
        \\  use value <- Read ()
        \\  use Touch value
        \\  return ()
        \\const reader = @effect.provider Read (fn () => 42)
        \\const touch = @effect.provider Touch (fn value => ())
        \\const run = fn () => do touch:
        \\  use checkpoint ()
        \\  return 42
        \\entry const answer = do reader:
        \\  return run ()
        \\const strict: (Unit -> Unit) -> Unit = fn callback => callback ()
        \\const capture = fn consumer => fn (callback: Unit -> Unit) => consumer callback
        \\entry const captured_strict = capture strict
    );
    defer module.deinit(a);
    const frozen_nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(frozen_nodes);
    const frozen_types = try a.dupe(types.Node, module.types.nodes);
    defer a.free(frozen_types);
    try capturedAmbientScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, capturedAmbientScenario, .{&module});
    try std.testing.expectEqualDeep(frozen_nodes, module.nodes);
    try std.testing.expectEqualDeep(frozen_types, module.types.nodes);
}

fn retainedOwnRowScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const original = try session.richValue(target(module, "drawable"));
    const settings = session.valueChildren(original)[0];
    const original_evidence = session.valueEvidence(original);
    const settings_evidence = session.valueEvidence(settings);
    const begin = try session.richValue(target(module, "begin"));
    const begin_evidence = session.valueEvidence(begin);
    const begin_metadata = session.closureInfo(begin);
    const expected = try session.evidence.intern(.function, types.unit, types.u32_type, &.{});
    const before = session.steps;
    const inferred = try session.inferClosure(original);
    try std.testing.expectEqual(inferred, try session.inferClosure(original));
    try std.testing.expectEqual(expected, session.valueEvidence(inferred));
    const specialized = try session.specializeClosure(original, expected);
    try std.testing.expectEqual(before, session.steps);
    try std.testing.expectEqual(expected, session.valueEvidence(specialized));
    try std.testing.expectEqual(original_evidence, session.valueEvidence(original));
    try std.testing.expectEqual(settings_evidence, session.valueEvidence(settings));
    try std.testing.expectEqual(begin_evidence, session.valueEvidence(begin));
    try std.testing.expectEqualDeep(begin_metadata, session.closureInfo(begin));
    const specialized_settings = session.valueChildren(inferred)[0];
    const settings_type = session.evidence.node(session.valueEvidence(specialized_settings));
    try std.testing.expectEqual(type_evidence.Tag.nominal, settings_type.tag);
    const begin_type = session.evidence.node(session.evidence.children(session.valueEvidence(specialized_settings))[0]);
    try std.testing.expectEqual(type_evidence.Tag.function, begin_type.tag);
    try std.testing.expectEqual(types.unit, begin_type.a);
    try std.testing.expectEqual(types.unit, begin_type.b);
    const row = session.evidence.view().effects;
    const labels = row.rowLabels(begin_type.c);
    try std.testing.expectEqual(@as(usize, 1), labels.len);
    try std.testing.expectEqualSlices(u32, &.{types.u32_type}, row.operationArguments(labels[0]));
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "answer"))).bits);
    const increment = try session.inferClosure(try session.richValue(target(module, "increment")));
    const increment_type = session.evidence.node(session.valueEvidence(increment));
    try std.testing.expectEqual(types.u32_type, increment_type.a);
    try std.testing.expectEqual(types.u32_type, increment_type.b);
    try std.testing.expectEqual(@as(usize, 0), session.evidence.view().effects.rowLabels(increment_type.c).len);
    const composed = try session.inferClosure(try session.richValue(target(module, "composed")));
    try std.testing.expectEqual(session.valueEvidence(increment), session.valueEvidence(composed));
    const pure = try session.evidence.intern(.function, types.unit, types.unit, &.{});
    try expectCaptureMismatch(&session, begin, pure);
    session.diagnostic = null;
    const unbound = try session.richValue(target(module, "unbound"));
    _ = session.inferClosure(unbound) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.RequestUnwind => return error.TestUnexpectedResult,
        error.Declined => {
            try std.testing.expectEqual(evaluator.Code.unsupported, session.diagnostic.?.code);
            return;
        },
    };
    return error.TestUnexpectedResult;
}

test "retained callable own latent row closes only after concrete operation proof" {
    var module = try lower(
        \\type State a is effect = { set: a -> Unit }
        \\type Settings begin is data = #Settings { value: U32, begin: begin }
        \\const set = fn value => State.set value
        \\entry const begin = fn () => set 7
        \\const settings = #Settings { value: 42, begin }
        \\const draw = fn settings => fn () => do:
        \\  let #Settings { value } = settings
        \\  return value
        \\entry const drawable = draw settings
        \\entry const answer = drawable ()
        \\const needs_callback = fn callback => @u32.add (callback ()) 1
        \\entry const unbound = draw (#Settings { value: 42, begin: needs_callback })
        \\entry const increment = fn value => @u32.add value 1
        \\const compose = fn left => fn right => fn value => left (right value)
        \\entry const composed = compose increment increment
    );
    defer module.deinit(a);
    const frozen_nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(frozen_nodes);
    const frozen_types = try a.dupe(types.Node, module.types.nodes);
    defer a.free(frozen_types);
    try retainedOwnRowScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, retainedOwnRowScenario, .{&module});
    try std.testing.expectEqualDeep(frozen_nodes, module.nodes);
    try std.testing.expectEqualDeep(frozen_types, module.types.nodes);
}

fn target(module: *const core.Module, name: []const u8) core.BindingRef {
    for (module.bodies) |body| if (body.exported and std.mem.eql(u8, module.name(body.export_name), name)) return .{ .unit = if (module.unit == 0) 1 else module.unit, .binding = body.binding };
    unreachable;
}

fn expectValue(module: *const core.Module, name: []const u8, expected: scalar_ops.Value) !void {
    const result = try evaluator.evaluate(a, &.{module.*}, target(module, name), .{});
    if (result.diagnostic) |diagnostic| std.debug.print("evaluation:{d}:{d}: {s}\n", .{ diagnostic.unit, diagnostic.span.start, diagnostic.message() });
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(expected, result.value.?);
}

test "immutable evaluation shares generic numeric bodies and named function aliases" {
    var module = try lowerPreludeProducer("infixl 60 (+) = _fixity_add\nconst twice = fn value => value + value\nconst alias = twice\nentry const integer = alias 21\nentry const floating = twice 1.5\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n", &.{.add});
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    try std.testing.expectEqual(scalar_ops.Value{ .scalar = .u32, .bits = 42 }, try session.value(target(&module, "integer")));
    const traced = session.traced_bodies;
    try std.testing.expectEqual(scalar_ops.Value{ .scalar = .f32, .bits = @bitCast(@as(f32, 3.0)) }, try session.value(target(&module, "floating")));
    try std.testing.expectEqual(traced + 2, session.traced_bodies);
    const steps = session.steps;
    _ = try session.value(target(&module, "integer"));
    _ = try session.value(target(&module, "floating"));
    try std.testing.expectEqual(steps, session.steps);
    try std.testing.expectEqual(@as(usize, 7), module.body_lowerings);
}

test "lazy global memo survives every output root and does not evaluate unused constants" {
    var module = try lower("const unused = @u32.div 1 0\nconst shared = @u32.add 40 2\nentry const first = shared\nentry const second = shared\n");
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const first = try session.value(target(&module, "first"));
    try std.testing.expectEqual(@as(u32, 42), first.bits);
    const steps = session.steps;
    const second = try session.value(target(&module, "second"));
    try std.testing.expectEqual(first, second);
    // The second root reads the memo; the shared operation does not run again.
    try std.testing.expectEqual(steps + 1, session.steps);
    try std.testing.expectEqual(@as(usize, 3), session.traced_bodies);
}

test "runtime dependency tracing demands named constants without executing runtime initializers" {
    var module = try lower(
        \\const named = @u32.add 40 2
        \\let unused = @panic "unused initializer"
        \\let before = @u32.add named (@u32.div 1 0)
        \\entry const answer = fn () -> U32 => before
    );
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    session.options.trace_runtime_dependencies = true;
    try session.prepare(target(&module, "answer"));
    try std.testing.expect(session.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 3), session.traced_bodies);
    try std.testing.expectEqual(@as(usize, 1), session.pending.items.len);
    try std.testing.expectEqual(@as(usize, 1), session.demanded);
    try std.testing.expectEqual(@as(u32, 42), session.valueInfo(session.slots[session.binding_offsets[0] + session.pending.items[0].binding].value).bits);
    var default = try evaluator.Session.init(a, &.{module});
    defer default.deinit();
    try std.testing.expectError(error.Declined, default.prepare(target(&module, "answer")));
    try std.testing.expectEqual(evaluator.Code.unsupported, default.diagnostic.?.code);
    var read = try lower("let before = 42\nentry const answer = before\n");
    defer read.deinit(a);
    const result = try evaluator.evaluate(a, &.{read}, target(&read, "answer"), .{ .trace_runtime_dependencies = true });
    try std.testing.expectEqual(evaluator.Code.const_runtime_dependency, result.diagnostic.?.code);
}

test "global dead-branch references are demanded but direct unselected traps are skipped" {
    var direct = try lowerPreludeProducer("infixr 25 (&&) = _fixity_and\ninfix 30 (==) = _fixity_eq\nentry const selected = if #False then @u32.div 1 0 else 42\nentry const logical = #False && (@u32.div 1 0 == 0)\nconst _fixity_and = fn (left: Bool) => fn ~(right: Bool) => if left then @force right else #False\nconst _fixity_eq = fn left => fn right => @type.call \"eq\" left right\n", &.{.eq});
    defer direct.deinit(a);
    try expectValue(&direct, "selected", .{ .scalar = .u32, .bits = 42 });
    try expectValue(&direct, "logical", .{ .scalar = .bool, .bits = 0 });
    var referenced = try lower("const failure = @u32.div 1 0\nentry const selected = if #False then failure else 42\nentry const function = fn () -> U32 => if #False then failure else 42\n");
    defer referenced.deinit(a);
    const result = try evaluator.evaluate(a, &.{referenced}, target(&referenced, "selected"), .{});
    try std.testing.expectEqual(evaluator.Code.integer_divide_by_zero, result.diagnostic.?.code);
    try std.testing.expectEqual(@as(u32, 1), result.diagnostic.?.unit);
    var session = try evaluator.Session.init(a, &.{referenced});
    defer session.deinit();
    try std.testing.expectError(error.Declined, session.prepare(target(&referenced, "function")));
    try std.testing.expectEqual(evaluator.Code.integer_divide_by_zero, session.diagnostic.?.code);
}

test "rebindings merges and suite returns retain their enclosing block boundary" {
    var module = try lowerPreludeProducer(
        \\infixl 60 (+) = _fixity_add
        \\const choose = fn flag => do:
        \\  let value = 1
        \\  if flag:
        \\    value := 20
        \\  else:
        \\    value := 21
        \\  let inner = do:
        \\    if flag:
        \\      return 2
        \\    return 3
        \\  if flag:
        \\    return value + inner
        \\  return value + inner
        \\entry const yes = choose #True
        \\entry const no = choose #False
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    , &.{.add});
    defer module.deinit(a);
    try expectValue(&module, "yes", .{ .scalar = .u32, .bits = 22 });
    try expectValue(&module, "no", .{ .scalar = .u32, .bits = 24 });
}

test "recursive pure calls are traced once and execute under fuel and depth limits" {
    var module = try lowerPreludeProducer(
        \\infix 30 (<=) = _fixity_le
        \\infixl 60 (-) = _fixity_sub
        \\infixl 70 (*) = _fixity_mul
        \\const factorial = fn (value: U32) -> U32 => do:
        \\  if value <= 1:
        \\    return 1
        \\  return value * factorial (value - 1)
        \\entry const answer = factorial 5
        \\const _fixity_le = fn left => fn right => @type.call "le" left right
        \\const _fixity_sub = fn left => fn right => @type.call "sub" left right
        \\const _fixity_mul = fn left => fn right => @type.call "mul" left right
    , &.{ .le, .mul, .sub });
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    try std.testing.expectEqual(@as(u32, 120), (try session.value(target(&module, "answer"))).bits);
    try std.testing.expectEqual(@as(usize, 10), session.traced_bodies);
    const fuel = try evaluator.evaluate(a, &.{module}, target(&module, "answer"), .{ .max_steps = 4 });
    try std.testing.expectEqual(evaluator.Code.constant_fuel, fuel.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 4), fuel.steps);
    const depth = try evaluator.evaluate(a, &.{module}, target(&module, "answer"), .{ .max_depth = 2 });
    try std.testing.expectEqual(evaluator.Code.constant_fuel, depth.diagnostic.?.code);
}

test "constant cycles and impure runtime globals decline with distinct diagnostics" {
    var cyclic = try lower("const first = second\nconst second = first\nentry const answer: U32 = first\n");
    defer cyclic.deinit(a);
    const cycle = try evaluator.evaluate(a, &.{cyclic}, target(&cyclic, "answer"), .{});
    try std.testing.expectEqual(evaluator.Code.cycle, cycle.diagnostic.?.code);
    var runtime = try lower("let before = 42\nentry const answer = fn () -> U32 => before\n");
    defer runtime.deinit(a);
    var session = try evaluator.Session.init(a, &.{runtime});
    defer session.deinit();
    try std.testing.expectError(error.Declined, session.prepare(target(&runtime, "answer")));
    try std.testing.expectEqual(evaluator.Code.unsupported, session.diagnostic.?.code);
}

fn reentrantQueueScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    session.prepare(target(module, "answer")) catch |err| {
        try std.testing.expect(!session.draining_pending);
        return err;
    };
    try std.testing.expect(!session.draining_pending);
    try std.testing.expect(session.diagnostic == null);
    const steps = session.steps;
    try session.prepare(target(module, "answer"));
    try std.testing.expectEqual(steps, session.steps);
}

test "method lookup queues dependents until the active constant finishes and releases the drain guard on failure" {
    var module = try lower(
        \\type Box is data = #Box U32
        \\const Box.get = fn box => case box of
        \\  #Box value => value
        \\const read = fn value => value.get
        \\const first = read (#Box 40)
        \\const second = @u32.add first 2
        \\entry const answer = fn () => @u32.add first second
    );
    defer module.deinit(a);
    try reentrantQueueScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, reentrantQueueScenario, .{&module});
}

test "numeric imported aliases and constants keep their producer identity after project teardown" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "main.blot", .data = "import { alias as twice, base } from \"./producer\"\ninfixl 60 (+) = _fixity_add\nentry const integer = twice (base + 1)\nentry const floating = twice 1.5\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "producer.blot", .data = "infixl 60 (+) = _fixity_add\nconst twice = fn value => value + value\nconst alias = twice\nconst base = 40\nconst unused = @u32.div 1 0\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n" });
    const filename = try tmp.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(filename);
    var modules: [3]core.Module = undefined;
    {
        var source = try project.load(a, io, filename, .{ .prelude_path = "std/prelude.blot" });
        defer source.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
        try std.testing.expectEqual(@as(usize, 3), source.units.items.len);
        var checked = try project_check.checkProject(a, &source);
        defer checked.deinit(a);
        for (checked.diagnostics) |diagnostic| std.debug.print("project:{d}:{d}: {s}\n", .{ diagnostic.unit, diagnostic.span.start, diagnostic.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        var completed: usize = 0;
        errdefer for (modules[0..completed]) |*module| module.deinit(a);
        for (&modules, 1..) |*module, unit_id| {
            module.* = try core.lower(a, &source.unit(@intCast(unit_id)).tree, &source.symbols, &checked.module(@intCast(unit_id)).checked);
            module.unit = @intCast(unit_id);
            completed += 1;
            try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
        }
    }
    defer for (&modules) |*module| module.deinit(a);
    var session = try evaluator.Session.init(a, &modules);
    defer session.deinit();
    try std.testing.expectEqual(scalar_ops.Value{ .scalar = .u32, .bits = 82 }, try session.value(target(&modules[1], "integer")));
    try std.testing.expectEqual(scalar_ops.Value{ .scalar = .f32, .bits = @bitCast(@as(f32, 3.0)) }, try session.value(target(&modules[1], "floating")));
    // Two roots, original function, alias, base, two explicit fixity
    // targets and two reached scalar producers. The dead divide is absent.
    try std.testing.expectEqual(@as(usize, 9), session.traced_bodies);
}

fn allocationScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "answer"))).bits);
}

test "session trace cache call frames and results release on every allocation failure" {
    var module = try lowerPreludeProducer("infix 30 (>) = _fixity_gt\ninfixl 60 (+) = _fixity_add\nconst plus = fn value => do:\n  let next = value + 1\n  if next > 20:\n    next := self + 20\n  return next\nentry const answer = plus 21\nconst _fixity_gt = fn left => fn right => @type.call \"gt\" left right\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n", &.{ .add, .gt });
    defer module.deinit(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationScenario, .{&module});
}

test "rich generic product constants share immutable handles and owned snapshots outlive the session" {
    var module = try lowerPreludeProducer("infixl 60 (+) = _fixity_add\nconst pair = fn value => (value, value + value)\nentry const integer = pair 21\nentry const floating = pair 1.5\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n", &.{.add});
    defer module.deinit(a);
    var copied: evaluator.Snapshot = undefined;
    var integer: evaluator.ValueId = undefined;
    var floating: evaluator.ValueId = undefined;
    {
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        integer = try session.richValue(target(&module, "integer"));
        floating = try session.richValue(target(&module, "floating"));
        try std.testing.expectEqual(evaluator.ValueKind.product, session.valueInfo(integer).kind);
        const fields = session.valueChildren(integer);
        try std.testing.expectEqual(@as(usize, 2), fields.len);
        try std.testing.expectEqual(scalar_ops.Value{ .scalar = .u32, .bits = 21 }, session.valueScalar(fields[0]).?);
        try std.testing.expectEqual(scalar_ops.Value{ .scalar = .u32, .bits = 42 }, session.valueScalar(fields[1]).?);
        const before = session.steps;
        try std.testing.expectEqual(integer, try session.richValue(target(&module, "integer")));
        try std.testing.expectEqual(before, session.steps);
        try std.testing.expectEqual(@as(usize, 6), session.traced_bodies);
        copied = try session.copySnapshot(a);
        try std.testing.expectEqual(session.snapshot().values.len, copied.values.len);
    }
    defer copied.deinit(a);
    const info = copied.values[floating];
    try std.testing.expectEqual(evaluator.ValueKind.product, info.kind);
    const fields = copied.children[info.start..][0..info.len];
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 1.5))), copied.values[fields[0]].bits);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 3.0))), copied.values[fields[1]].bits);
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(evaluator.ValueInfo));
}

fn richAllocationScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const id = try session.richValue(target(module, "answer"));
    try std.testing.expectEqual(evaluator.ValueKind.product, session.valueInfo(id).kind);
    var copied = try session.copySnapshot(allocator);
    defer copied.deinit(allocator);
    try std.testing.expectEqual(session.snapshot().children.len, copied.children.len);
}

test "rich value slots child buffers snapshots and fuel limits release on allocation failure" {
    var module = try lowerPreludeProducer("infixl 60 (+) = _fixity_add\nconst pair = fn value => (value, value + 1)\nentry const answer = pair 41\nconst _fixity_add = fn left => fn right => @type.call \"add\" left right\n", &.{.add});
    defer module.deinit(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, richAllocationScenario, .{&module});
    var slots = try evaluator.Session.init(a, &.{module});
    defer slots.deinit();
    slots.options.max_values = 2;
    try std.testing.expectError(error.Declined, slots.richValue(target(&module, "answer")));
    try std.testing.expectEqual(evaluator.Code.constant_fuel, slots.diagnostic.?.code);
    try std.testing.expect(slots.snapshot().values.len <= 2);
    var children = try evaluator.Session.init(a, &.{module});
    defer children.deinit();
    children.options.max_children = 1;
    try std.testing.expectError(error.Declined, children.richValue(target(&module, "answer")));
    try std.testing.expectEqual(evaluator.Code.constant_fuel, children.diagnostic.?.code);
    try std.testing.expect(children.snapshot().children.len <= 1);
}

test "reference record field order and rebinding preserve immutable aliases" {
    var module = try lower(
        \\type Point is data = #Point { x: U32, y: U32 }
        \\entry const answer = do:
        \\  let point = #Point { y: 2, x: 1 }
        \\  let before = point
        \\  point.x := @u32.add self 1
        \\  return @u32.add before.x (@u32.mul point.x 10)
    );
    defer module.deinit(a);
    try expectValue(&module, "answer", .{ .scalar = .u32, .bits = 21 });
}

test "reference parameterized variants preserve scalar payloads and empty constructors" {
    var module = try lower(
        \\type Choice a is data = #Present a | #Absent
        \\const get = fn fallback => fn candidate => case candidate of
        \\  #Present value => value
        \\  #Absent => fallback
        \\entry const integer = get 0 (#Present 42)
        \\entry const floating = get 0.0 (#Present 1.5)
        \\entry const empty = get 7 #Absent
    );
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    try std.testing.expectEqual(scalar_ops.Value{ .scalar = .u32, .bits = 42 }, try session.value(target(&module, "integer")));
    try std.testing.expectEqual(scalar_ops.Value{ .scalar = .f32, .bits = @bitCast(@as(f32, 1.5)) }, try session.value(target(&module, "floating")));
    try std.testing.expectEqual(scalar_ops.Value{ .scalar = .u32, .bits = 7 }, try session.value(target(&module, "empty")));
    try std.testing.expectEqual(@as(usize, 4), session.traced_bodies);
}

test "reference nested nominal record tuple patterns use canonical slots and wildcard holes" {
    var module = try lower(
        \\type Point is data = #Point { x: U32, y: U32 }
        \\type Pair [left, right] is data = #Pair (left, right)
        \\entry const answer = do:
        \\  let #Pair (#Point { y, x }, amount) = #Pair (#Point { y: 20, x: 2 }, 20)
        \\  return @u32.add x (@u32.add y amount)
    );
    defer module.deinit(a);
    try expectValue(&module, "answer", .{ .scalar = .u32, .bits = 42 });
}

test "reference ordered constructor alternatives and failed guards fall through once" {
    var module = try lower(
        \\type Choice is data = #First U32 | #Second U32 | #Empty
        \\const choose = fn candidate => case candidate of
        \\  #First value | #Second value if @u32.lt 39 value => value
        \\  #First value | #Second value => @u32.add value 2
        \\  #Empty => 0
        \\entry const guarded = choose (#Second 42)
        \\entry const fallback = choose (#First 40)
        \\entry const low = choose (#Second 39)
        \\entry const empty = choose #Empty
    );
    defer module.deinit(a);
    try expectValue(&module, "guarded", .{ .scalar = .u32, .bits = 42 });
    try expectValue(&module, "fallback", .{ .scalar = .u32, .bits = 40 });
    try expectValue(&module, "low", .{ .scalar = .u32, .bits = 41 });
    try expectValue(&module, "empty", .{ .scalar = .u32, .bits = 0 });
}

test "reference existing value patterns and multiple inputs evaluate to one ordered match" {
    var module = try lower(
        \\entry const selected = 7
        \\const choose = fn key => fn payload => case key, payload of
        \\  ^selected, (value, #True) => value
        \\  _, (_, _) => 0
        \\entry const yes = choose 7 (42, #True)
        \\entry const no = choose 8 (42, #True)
    );
    defer module.deinit(a);
    try expectValue(&module, "yes", .{ .scalar = .u32, .bits = 42 });
    try expectValue(&module, "no", .{ .scalar = .u32, .bits = 0 });
}

test "rich nominal snapshot identities erase generic arguments and distinguish declaration families" {
    var integer: evaluator.ValueId = undefined;
    var floating: evaluator.ValueId = undefined;
    var snapshot: evaluator.Snapshot = undefined;
    {
        var module = try lower("type Box a is data = #Box a\ntype Other a is data = #Other a\nentry const integer = #Box 41\nentry const floating = #Box 1.5\nentry const other = #Other 41\n");
        defer module.deinit(a);
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        integer = try session.richValue(target(&module, "integer"));
        floating = try session.richValue(target(&module, "floating"));
        const other = try session.richValue(target(&module, "other"));
        try std.testing.expectEqual(evaluator.ValueKind.nominal, session.valueInfo(integer).kind);
        try std.testing.expectEqual(session.valueInfo(integer).nominal, session.valueInfo(floating).nominal);
        try std.testing.expect(session.valueInfo(integer).nominal != session.valueInfo(other).nominal);
        try std.testing.expectEqual(@as(u32, 0), session.constructorTag(integer).?);
        try std.testing.expectEqual(@as(usize, 1), session.valueChildren(integer).len);
        const steps = session.steps;
        try std.testing.expectEqual(integer, try session.richValue(target(&module, "integer")));
        try std.testing.expectEqual(steps, session.steps);
        snapshot = try session.copySnapshot(a);
    }
    defer snapshot.deinit(a);
    const integer_payload = snapshot.children[snapshot.values[integer].start];
    const floating_payload = snapshot.children[snapshot.values[floating].start];
    try std.testing.expectEqual(@as(u32, 41), snapshot.values[integer_payload].bits);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 1.5))), snapshot.values[floating_payload].bits);
}

test "refutable patterns and conditional matches preserve exiting suites and branch merges" {
    var module = try lower(
        \\type Choice a is data = #Present a | #Absent
        \\const unpack = fn candidate => do:
        \\  let #Present value = candidate else:
        \\    return 0
        \\  return value
        \\const choose = fn candidate => do:
        \\  let total = 1
        \\  if let #Present value = candidate:
        \\    total := @u32.add value 1
        \\  else:
        \\    total := 2
        \\  return total
        \\entry const unpacked = unpack (#Present 42)
        \\entry const missing = unpack #Absent
        \\entry const selected = choose (#Present 42)
        \\entry const fallback = choose #Absent
    );
    defer module.deinit(a);
    try expectValue(&module, "unpacked", .{ .scalar = .u32, .bits = 42 });
    try expectValue(&module, "missing", .{ .scalar = .u32, .bits = 0 });
    try expectValue(&module, "selected", .{ .scalar = .u32, .bits = 43 });
    try expectValue(&module, "fallback", .{ .scalar = .u32, .bits = 2 });
}

test "nested field paths copy only immutable descendants and retain omitted pattern slots" {
    var module = try lower(
        \\type Point is data = #Point { x: U32, y: U32 }
        \\type Holder is data = #Holder { point: Point, flag: Bool }
        \\entry const answer = do:
        \\  let holder = #Holder { flag: #True, point: #Point { y: 3, x: 1 } }
        \\  let before = holder
        \\  holder.point.x := @u32.add self 1
        \\  let #Holder { point: #Point { y } } = holder
        \\  return @u32.add (@u32.mul before.point.x 10) (@u32.add holder.point.x y)
    );
    defer module.deinit(a);
    try expectValue(&module, "answer", .{ .scalar = .u32, .bits = 15 });
}

fn nominalAllocationScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const id = try session.richValue(target(module, "answer"));
    try std.testing.expectEqual(evaluator.ValueKind.nominal, session.valueInfo(id).kind);
    var copied = try session.copySnapshot(allocator);
    defer copied.deinit(allocator);
    const payload = copied.children[copied.values[id].start];
    const x = copied.children[copied.values[payload].start];
    try std.testing.expectEqual(@as(u32, 42), copied.values[x].bits);
}

test "aggregate matching path copies and snapshots release on every allocation failure" {
    var module = try lower(
        \\type Point is data = #Point { x: U32, y: U32 }
        \\type Choice a is data = #Present a | #Absent
        \\const change = fn (candidate: Choice Point) => do:
        \\  let #Present point = candidate else:
        \\    return #Point { x: 0, y: 0 }
        \\  point.x := @u32.add self 1
        \\  return point
        \\entry const answer = change (#Present (#Point { y: 9, x: 41 }))
    );
    defer module.deinit(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, nominalAllocationScenario, .{&module});
}

test "record operands execute written order before declaration-order permutation" {
    const source =
        \\type Point is data = #Point { x: U32, y: U32 }
        \\const point = #Point { y: @u32.div 2 0, x: @u32.div 1 0 }
        \\entry const answer = point.x
    ;
    var module = try lower(source);
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    try std.testing.expectError(error.Declined, session.value(target(&module, "answer")));
    try std.testing.expectEqual(evaluator.Code.integer_divide_by_zero, session.diagnostic.?.code);
    try std.testing.expectEqual(@as(u32, @intCast(std.mem.find(u8, source, "@u32.div 2 0").?)), session.diagnostic.?.span.start);
}

test "product literal projections and sum-record fields follow their typed variant slot" {
    var module = try lower(
        \\type Position is data = #First { x: U32, y: U32 } | #Second { y: U32, x: U32 }
        \\const coordinate = fn (point: Position) => point.x
        \\entry const first = coordinate (#First { y: 9, x: 21 })
        \\entry const second = coordinate (#Second { x: 42, y: 8 })
        \\entry const tuple = @product.get (99, 42) 1
    );
    defer module.deinit(a);
    try expectValue(&module, "first", .{ .scalar = .u32, .bits = 21 });
    try expectValue(&module, "second", .{ .scalar = .u32, .bits = 42 });
    try expectValue(&module, "tuple", .{ .scalar = .u32, .bits = 42 });
}

test "reference array literals fill and set preserve cached immutable snapshots" {
    var module = try lower(
        \\const values = #[20, 22]
        \\const before = @array.fill 3 7
        \\const after = @array.set before 1 42
        \\entry const answer = @u32.add (@array.get values 0) (@array.get values 1)
        \\entry const length = @array.length values
        \\entry const old = @array.get before 1
        \\entry const next = @array.get after 1
        \\entry const empty = @array.length (@array.fill 0 8)
    );
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(&module, "answer"))).bits);
    try std.testing.expectEqual(@as(u32, 2), (try session.value(target(&module, "length"))).bits);
    try std.testing.expectEqual(@as(u32, 7), (try session.value(target(&module, "old"))).bits);
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(&module, "next"))).bits);
    try std.testing.expectEqual(@as(u32, 0), (try session.value(target(&module, "empty"))).bits);
    const steps = session.steps;
    _ = try session.value(target(&module, "old"));
    _ = try session.value(target(&module, "next"));
    try std.testing.expectEqual(steps, session.steps);
}

test "reference arrays carry nominal and nested array handles without mutating aliases" {
    var module = try lower(
        \\type Box is data = #Box { x: U32 }
        \\const values = #[#Box { x: 40 }, #Box { x: 2 }]
        \\const rows = #[#[1, 2], #[3, 4]]
        \\const next = @array.set rows 1 (@array.set (@array.get rows 1) 0 42)
        \\entry const answer = @u32.add (@array.get values 0).x (@array.get values 1).x
        \\entry const old = @array.get (@array.get rows 1) 0
        \\entry const changed = @array.get (@array.get next 1) 0
        \\entry const first = @array.get (@array.get next 0) 0
    );
    defer module.deinit(a);
    try expectValue(&module, "answer", .{ .scalar = .u32, .bits = 42 });
    try expectValue(&module, "old", .{ .scalar = .u32, .bits = 3 });
    try expectValue(&module, "changed", .{ .scalar = .u32, .bits = 42 });
    try expectValue(&module, "first", .{ .scalar = .u32, .bits = 1 });
}

fn growingCollectionScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const first = try session.richValue(target(module, "first"));
    var frozen = try session.copySnapshot(allocator);
    defer frozen.deinit(allocator);
    const info = frozen.values[first];
    const second = try session.richValue(target(module, "second"));
    const branch = try session.richValue(target(module, "branch"));
    const previous = try session.richValue(target(module, "previous"));
    const changed = try session.richValue(target(module, "changed"));
    for ([_]evaluator.ValueId{ first, second, branch, previous, changed }, [_][]const u32{ &.{20}, &.{ 20, 22 }, &.{ 10, 20 }, &.{20}, &.{99} }) |id, expected| {
        const items = session.valueChildren(id);
        try std.testing.expectEqual(expected.len, items.len);
        for (items, expected) |item, value| try std.testing.expectEqual(value, session.valueScalar(item).?.bits);
    }
    try std.testing.expectEqual(@as(u32, 1), info.len);
    try std.testing.expectEqual(@as(u32, 20), frozen.values[frozen.children[info.start]].bits);
}

test "growing collection values preserve captures typed views owned snapshots and branching under allocation failures" {
    var module = try lower(
        \\const identity = fn value => value
        \\entry const first = @list.append [] 20
        \\const capture = fn () => first
        \\entry const second = @list.append (identity first) 22
        \\entry const branch = @list.prepend first 10
        \\entry const previous = capture ()
        \\entry const changed = @array.set (@array.from_list first) 0 99
    );
    defer module.deinit(a);
    try growingCollectionScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, growingCollectionScenario, .{&module});
}

test "reference array diagnostics preserve bounds primitive argument order and bootstrap limits" {
    const Case = struct { source: []const u8, code: evaluator.Code };
    for ([_]Case{
        .{ .source = "entry const answer = @array.get #[1] 1\n", .code = .array_bounds },
        .{ .source = "entry const answer = @array.length (@array.set #[1] 1 42)\n", .code = .array_bounds },
        .{ .source = "entry const answer = @array.length (@array.set #[1] 1 (@u32.div 1 0))\n", .code = .integer_divide_by_zero },
        .{ .source = "entry const answer = @array.length (@array.fill 0 (@u32.div 1 0))\n", .code = .integer_divide_by_zero },
        .{ .source = "entry const answer = @array.length (@array.fill 4194304 7)\n", .code = .backend_limit },
        .{ .source = "entry const answer = @array.length (@array.fill 4294967295 7)\n", .code = .backend_limit },
    }) |gate| {
        var module = try lower(gate.source);
        defer module.deinit(a);
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        try std.testing.expectError(error.Declined, session.value(target(&module, "answer")));
        try std.testing.expectEqual(gate.code, session.diagnostic.?.code);
        try std.testing.expect(session.snapshot().children.len <= 1);
    }
}

fn arrayAllocationScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const id = try session.richValue(target(module, "answer"));
    try std.testing.expectEqual(evaluator.ValueKind.array, session.valueInfo(id).kind);
    const children = session.valueChildren(id);
    try std.testing.expectEqual(@as(usize, 3), children.len);
    try std.testing.expectEqual(@as(u32, 42), session.valueScalar(children[1]).?.bits);
    var copied = try session.copySnapshot(allocator);
    defer copied.deinit(allocator);
}

test "owned array copies charge every cell and clean up all allocation failures" {
    var module = try lower("const before = @array.fill 3 7\nentry const answer = @array.set before 1 42\n");
    defer module.deinit(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, arrayAllocationScenario, .{&module});
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const id = try session.richValue(target(&module, "answer"));
    try std.testing.expectEqual(@as(usize, 6), session.snapshot().children.len);
    try std.testing.expectEqual(@as(u32, 7), session.valueScalar(session.valueChildren(id)[0]).?.bits);
    try std.testing.expectEqual(@as(u32, 7), session.valueScalar(session.valueChildren(id)[2]).?.bits);
    // Seven expression visits plus three fill and three copy cells.
    try std.testing.expectEqual(@as(usize, 13), session.steps);
    var limited = try evaluator.Session.init(a, &.{module});
    defer limited.deinit();
    limited.options.max_steps = 12;
    try std.testing.expectError(error.Declined, limited.richValue(target(&module, "answer")));
    try std.testing.expectEqual(evaluator.Code.constant_fuel, limited.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 12), limited.steps);
    try std.testing.expectEqual(@as(usize, 3), limited.snapshot().children.len);
    var fill = try lower("entry const answer = @array.length (@array.fill 100 7)\n");
    defer fill.deinit(a);
    const budget = try evaluator.evaluate(a, &.{fill}, target(&fill, "answer"), .{ .max_steps = 16 });
    try std.testing.expectEqual(evaluator.Code.constant_fuel, budget.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 16), budget.steps);
}

test "reference lexical closures retain old bindings and transitive curried captures" {
    var module = try lower(
        \\const capture = fn start => do:
        \\  let value = start
        \\  let before = fn () => value
        \\  value := @u32.add self 1
        \\  return @u32.add (@u32.mul (before ()) 10) value
        \\const make = fn base => do:
        \\  return fn left => fn right => @u32.add base (@u32.add left right)
        \\entry const previous = capture 3
        \\entry const curried = make 20 21 1
    );
    defer module.deinit(a);
    try expectValue(&module, "previous", .{ .scalar = .u32, .bits = 34 });
    try expectValue(&module, "curried", .{ .scalar = .u32, .bits = 42 });
}

test "reference higher-order callbacks and polymorphic lexical functions avoid reinference" {
    var module = try lower(
        \\const apply = fn transform => fn value => transform value
        \\entry const integer = apply (fn value => @u32.add value 1) 41
        \\entry const floating = apply (fn value => @f32.mul value 2.0) 1.5
        \\entry const polymorphic = do:
        \\  let identity = fn value => value
        \\  let number = identity 42
        \\  let truth = identity #True
        \\  return if truth then number else 0
    );
    defer module.deinit(a);
    try expectValue(&module, "integer", .{ .scalar = .u32, .bits = 42 });
    try expectValue(&module, "floating", .{ .scalar = .f32, .bits = @bitCast(@as(f32, 3.0)) });
    try expectValue(&module, "polymorphic", .{ .scalar = .u32, .bits = 42 });
    try std.testing.expectEqual(@as(usize, 4), module.body_lowerings);
}

test "reference partial named calls and staged selected functions share cached closure values" {
    var module = try lower(
        \\const sum = fn left => fn right => @u32.add left right
        \\const add = sum 40
        \\const make = fn start => do:
        \\  let captured = @u32.add start 1
        \\  return fn value => @u32.add captured value
        \\const ready = make 20
        \\const first = fn value => @u32.add value 1
        \\const second = fn value => @u32.add value 2
        \\const selected = if #False then first else second
        \\entry const partial = add 2
        \\entry const staged = ready 21
        \\entry const chosen = selected 40
    );
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    for ([_][]const u8{ "partial", "staged", "chosen" }) |name| try std.testing.expectEqual(@as(u32, 42), (try session.value(target(&module, name))).bits);
    const steps = session.steps;
    const closures = session.snapshot().closures.len;
    for ([_][]const u8{ "partial", "staged", "chosen" }) |name| _ = try session.value(target(&module, name));
    try std.testing.expectEqual(steps, session.steps);
    try std.testing.expectEqual(closures, session.snapshot().closures.len);
}

test "reference first-class constructors and ordinary primitive wrappers remain callable" {
    var module = try lower(
        \\type Box a is data = #Box a
        \\const apply = fn transform => fn value => transform value
        \\const box = #Box
        \\const add = fn left => fn right => @u32.add left right
        \\const increment = add 40
        \\const fill = fn value => @array.fill 2 value
        \\entry const boxed = case apply box 42 of
        \\  #Box value => value
        \\entry const scalar = increment 2
        \\entry const length = @array.length (fill 7)
    );
    defer module.deinit(a);
    try expectValue(&module, "boxed", .{ .scalar = .u32, .bits = 42 });
    try expectValue(&module, "scalar", .{ .scalar = .u32, .bits = 42 });
    try expectValue(&module, "length", .{ .scalar = .u32, .bits = 2 });
}

test "literal panic details remain lazy and preserve decoded owned text" {
    var selected = try lower("const unused = @panic \"unused\"\nentry const answer = if #False then @panic \"dead\" else 42\n");
    defer selected.deinit(a);
    try expectValue(&selected, "answer", .{ .scalar = .u32, .bits = 42 });
    var panicking = try lower("entry const answer = @panic \"line\\nmessage\"\n");
    defer panicking.deinit(a);
    const result = try evaluator.evaluate(a, &.{panicking}, target(&panicking, "answer"), .{});
    try std.testing.expectEqual(evaluator.Code.const_panic, result.diagnostic.?.code);
    try std.testing.expectEqualStrings("line\nmessage", result.diagnostic.?.detail);
    try std.testing.expectEqualStrings(result.diagnostic.?.detail, result.diagnostic.?.message());
}

fn closureAllocationScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "answer"))).bits);
    var snapshot = try session.copySnapshot(allocator);
    defer snapshot.deinit(allocator);
    try std.testing.expect(snapshot.closures.len != 0);
}

test "staged closure captures partial application frames and snapshots clean up on allocation failure" {
    var module = try lower(
        \\const make = fn base => do:
        \\  let offset = @u32.add base 1
        \\  return fn left => fn right => @u32.add offset (@u32.add left right)
        \\const ready = make 19
        \\const partial = ready 21
        \\entry const answer = partial 1
        \\entry const function = partial
    );
    defer module.deinit(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, closureAllocationScenario, .{&module});
    var snapshot: evaluator.Snapshot = undefined;
    var id: evaluator.ValueId = undefined;
    {
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        id = try session.richValue(target(&module, "function"));
        try std.testing.expectEqual(evaluator.ClosureOrigin.anonymous, session.closureInfo(id).origin);
        try std.testing.expectEqual(@as(usize, 2), session.valueChildren(id).len);
        snapshot = try session.copySnapshot(a);
    }
    defer snapshot.deinit(a);
    try std.testing.expectEqual(evaluator.ValueKind.closure, snapshot.values[id].kind);
    try std.testing.expectEqual(evaluator.ClosureOrigin.anonymous, snapshot.closures[snapshot.values[id].bits].origin);
    const captures = snapshot.children[snapshot.values[id].start..][0..snapshot.values[id].len];
    try std.testing.expectEqual(@as(u32, 20), snapshot.values[captures[0]].bits);
    try std.testing.expectEqual(@as(u32, 21), snapshot.values[captures[1]].bits);
}

fn evidenceAllocationScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "answer"))).bits);
    var snapshot = try session.copySnapshot(allocator);
    defer snapshot.deinit(allocator);
    try std.testing.expectEqual(snapshot.values.len, snapshot.value_evidence.len);
    try std.testing.expect(snapshot.evidence.nodes.len > 6);
}

test "exact evidence keeps generic fields and associated member calls independent across uses" {
    var module = try lower(
        \\type Point a is data = #Point {x:a}
        \\type FloatPoint is data = #FloatPoint {x:F32}
        \\const Point.combine = fn (left:Point U32) => fn (right:Point U32) => #Point {x:@u32.add left.x right.x}
        \\const combine = fn left => fn right => @type.call "combine" left right
        \\const coordinate = fn point => point.x
        \\entry const answer = coordinate (combine (#Point {x:20}) (#Point {x:22}))
        \\entry const floating = coordinate (#FloatPoint {x:1.25})
    );
    defer module.deinit(a);
    try expectValue(&module, "answer", .{ .scalar = .u32, .bits = 42 });
    try expectValue(&module, "floating", .{ .scalar = .f32, .bits = @bitCast(@as(f32, 1.25)) });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, evidenceAllocationScenario, .{&module});
}

test "phantom nominal arguments control ordered method admission before implementation effects" {
    var module = try lowerPreludeProducer(
        \\infixl 60 (+) = _fixity_add
        \\type Phantom a is data = #Phantom Unit
        \\type Right is data = #Right Unit
        \\const Phantom.add = fn (left:Phantom U32) => fn (right:Right) => @u32.div 1 0
        \\const Right.add = fn (left:Phantom F32) => fn (right:Right) => 42
        \\const plus = fn left => fn right => left + right
        \\const integer:Phantom U32 = #Phantom ()
        \\const floating:Phantom F32 = #Phantom ()
        \\entry const answer = plus floating (#Right ())
        \\entry const integer_view = integer
        \\entry const floating_view = floating
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    , &.{.add});
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(&module, "answer"))).bits);
    const integer = try session.richValue(target(&module, "integer_view"));
    const floating = try session.richValue(target(&module, "floating_view"));
    try std.testing.expectEqual(session.valueInfo(integer).nominal, session.valueInfo(floating).nominal);
    try std.testing.expectEqual(session.valueInfo(integer).bits, session.valueInfo(floating).bits);
    try std.testing.expect(session.valueEvidence(integer) != session.valueEvidence(floating));
    try std.testing.expectEqual(@as(u32, 3), session.evidence.children(session.valueEvidence(integer))[0]);
    try std.testing.expectEqual(@as(u32, 4), session.evidence.children(session.valueEvidence(floating))[0]);
    var snapshot = try session.copySnapshot(a);
    defer snapshot.deinit(a);
    try std.testing.expectEqual(@as(u32, 4), snapshot.evidence.view().children(snapshot.value_evidence[floating])[0]);
}

test "authoritative scalar primitives bypass source methods while generic operators select them" {
    var module = try lowerPreludeProducer(
        \\infixl 60 (+) = _fixity_add
        \\type Point is data = #Point {x:U32}
        \\const Point.add = fn left => fn right => #Point {x:@u32.add left.x right.x}
        \\const plus = fn left => fn right => left + right
        \\entry const nominal = (plus (#Point {x:20}) (#Point {x:22})).x
        \\entry const scalar = plus 20 22
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    , &.{.add});
    defer module.deinit(a);
    try expectValue(&module, "nominal", .{ .scalar = .u32, .bits = 42 });
    try expectValue(&module, "scalar", .{ .scalar = .u32, .bits = 42 });
}

test "unused generic bodies remain principal and a concrete dead-branch use rejects missing methods" {
    var unused = try lowerPreludeProducer(
        \\infixl 60 (+) = _fixity_add
        \\type Empty is data = #Empty
        \\const bad = fn value => if #False then value + value else 42
        \\entry const answer = 42
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    , &.{.add});
    defer unused.deinit(a);
    try expectValue(&unused, "answer", .{ .scalar = .u32, .bits = 42 });
    const source =
        \\infixl 60 (+) = _fixity_add
        \\type Empty is data = #Empty
        \\const bad = fn value => if #False then value + value else 42
        \\entry const answer = bad #Empty
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    ;
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    var checked = try checker.check(a, &syntax, &pool);
    defer checked.deinit(a);
    // An ordinary fixity target retains its requirement until the concrete
    // invocation is proved. The dead branch must still require that method.
    if (checked.diagnostics.len == 0) {
        var demanded = try core.lower(a, &syntax, &pool, &checked);
        defer demanded.deinit(a);
        const result = try evaluator.evaluate(a, &.{demanded}, target(&demanded, "answer"), .{});
        try std.testing.expectEqual(evaluator.Code.missing_associated, result.diagnostic.?.code);
    } else try std.testing.expect(checked.diagnostics.len != 0);
}

test "staged phantom captures and curried named partials retain exact type evidence" {
    var module = try lowerPreludeProducer(
        \\infixl 60 (+) = _fixity_add
        \\type Phantom a is data = #Phantom Unit
        \\type Right is data = #Right Unit
        \\const Phantom.add = fn (left:Phantom U32) => fn (right:Right) => @u32.div 1 0
        \\const Right.add = fn (left:Phantom F32) => fn (right:Right) => 42
        \\const plus = fn left => fn right => left + right
        \\const make = fn marker => fn () => marker
        \\const floating:Phantom F32 = #Phantom ()
        \\const ready = make floating
        \\const partial = plus (ready ())
        \\entry const answer = partial (#Right ())
        \\entry const function = ready
        \\const _fixity_add = fn left => fn right => @type.call "add" left right
    , &.{.add});
    defer module.deinit(a);
    try expectValue(&module, "answer", .{ .scalar = .u32, .bits = 42 });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, closureAllocationScenario, .{&module});
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const function = try session.richValue(target(&module, "function"));
    const evidence = session.evidence.node(session.valueEvidence(function));
    try std.testing.expectEqual(@import("type_evidence.zig").Tag.function, evidence.tag);
    try std.testing.expectEqual(@as(u32, 4), session.evidence.children(evidence.b)[0]);
    const captured = session.valueChildren(function)[0];
    try std.testing.expectEqual(@as(u32, 4), session.evidence.children(session.valueEvidence(captured))[0]);
}

fn witnessScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for ([_]struct { name: []const u8, bits: u32 }{
        .{ .name = "constructor", .bits = 1 },
        .{ .name = "nominal", .bits = 0 },
        .{ .name = "generic", .bits = 0 },
        .{ .name = "array", .bits = 1 },
        .{ .name = "product", .bits = 0 },
        .{ .name = "cell", .bits = 1 },
        .{ .name = "distinct", .bits = 0 },
        .{ .name = "equal", .bits = 1 },
        .{ .name = "colon", .bits = 1 },
    }) |expected| try std.testing.expectEqual(scalar_ops.Value{ .scalar = .bool, .bits = expected.bits }, try session.value(target(module, expected.name)));
    _ = session.value(target(module, "ordered")) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.RequestUnwind => return error.TestUnexpectedResult,
        error.Declined => {},
    };
    try std.testing.expectEqual(evaluator.Code.const_panic, session.diagnostic.?.code);
    try std.testing.expectEqualStrings("right witness", session.diagnostic.?.detail);
}

test "type witnesses retain phantom arguments while excluding their uncalled arrow rows" {
    var module = try lower(
        \\type Count is data = #Count U32
        \\type Other is data = #Other U32
        \\type Cell value is data = #Cell value
        \\type Phantom value is data = #Phantom
        \\type Type witness is data = #Type witness
        \\const same = fn left => fn right => @type.same left right
        \\const Type.eq = fn left => fn right => case left, right of
        \\  #Type first, #Type second => @type.same first second
        \\entry const constructor = same #Count (#Count 42)
        \\entry const nominal = same #Count #Other
        \\entry const generic = same (#Cell 1) (#Cell 1.0)
        \\entry const array = same #[1,2] #[42]
        \\entry const product = same (1,#True) (1.0,#True)
        \\entry const cell = same (#Cell 42) (fn () -> Cell U32 => @panic "uncalled witness")
        \\entry const distinct = same (fn () -> Phantom U32 => #Phantom) (fn () -> Phantom F32 => #Phantom)
        \\entry const equal = same (fn () -> Phantom U32 => #Phantom) (fn () -> Phantom U32 => #Phantom)
        \\entry const colon = Type.eq (:1) (:2)
        \\entry const ordered = @type.same (fn () -> U32 => @panic "uncalled witness") (@panic "right witness")
    );
    defer module.deinit(a);
    try witnessScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, witnessScenario, .{&module});
}

test "private code evidence retains uncalled type witnesses inside generic calls" {
    var module = try lower(
        \\type Cell value is data = #Cell value
        \\type Phantom value is data = #Phantom
        \\const same = fn left => fn right => @type.same left right
        \\entry const run = fn () => same (#Cell 42) (fn () -> Cell U32 => @panic "uncalled witness")
        \\entry const phantom = fn () => same (fn () -> Phantom U32 => #Phantom) (fn () -> Phantom F32 => #Phantom)
        \\entry const equal = fn () => same (fn () -> Phantom U32 => #Phantom) (fn () -> Phantom U32 => #Phantom)
    );
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    var expectations = try code_expectation.Store.init(a);
    defer expectations.deinit();
    const expected = try expectations.intern(.function, types.unit, types.boolean, &.{});
    for ([_][]const u8{ "run", "phantom", "equal" }) |name| {
        var proof = try session.bodyEvidencePartialFull(target(&module, name), expectations.view(), expected, &.{}, &.{});
        defer proof.deinit(a);
    }
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}

test "selected generic associated producers demand constants from unselected method branches" {
    var module = try lower(
        \\type Point is data = #Point U32
        \\const failure = @u32.div 1 0
        \\const Point.combine = fn left => fn right => if #False then failure else 42
        \\const combine = fn left => fn right => @type.call "combine" left right
        \\entry const answer = combine (#Point 1) (#Point 2)
    );
    defer module.deinit(a);
    const result = try evaluator.evaluate(a, &.{module}, target(&module, "answer"), .{});
    try std.testing.expectEqual(evaluator.Code.integer_divide_by_zero, result.diagnostic.?.code);
    try std.testing.expectEqual(@as(u32, 48), result.diagnostic.?.span.start);
}

test "generic record closure snapshots retain storage names independently of semantic field order" {
    var module = try lower(
        \\const prime = fn value => value.a
        \\type Point is data = #Point {z:U32,a:U32}
        \\const capture = fn value => fn () => value
        \\const make = fn value => case value of
        \\  #Point {z,a} => capture (#Point {z,a})
        \\const ready = make (#Point {z:40,a:2})
        \\entry const answer = @u32.add (prime (ready ())) (ready ()).z
        \\entry const function = ready
    );
    defer module.deinit(a);
    try expectValue(&module, "answer", .{ .scalar = .u32, .bits = 42 });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, closureAllocationScenario, .{&module});
    var snapshot: evaluator.Snapshot = undefined;
    var captured: evaluator.ValueId = undefined;
    {
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        const function = try session.richValue(target(&module, "function"));
        const nominal = session.valueChildren(function)[0];
        try std.testing.expectEqual(evaluator.ValueKind.nominal, session.valueInfo(nominal).kind);
        captured = session.valueChildren(nominal)[0];
        try std.testing.expectEqual(evaluator.ValueKind.record, session.valueInfo(captured).kind);
        try std.testing.expectEqual(@as(usize, 2), session.recordFieldNames(captured).len);
        const names = session.recordFieldNames(captured);
        const semantic = session.evidence.children(session.valueEvidence(captured));
        for (names) |name| try std.testing.expect(name == semantic[0] or name == semantic[2]);
        snapshot = try session.copySnapshot(a);
    }
    defer snapshot.deinit(a);
    const fields = snapshot.record_layouts[snapshot.value_records[captured]];
    try std.testing.expectEqual(@as(u32, 2), fields.len);
    const names = snapshot.field_names[fields.start..][0..fields.len];
    const semantic = snapshot.evidence.view().children(snapshot.value_evidence[captured]);
    for (names) |name| try std.testing.expect(name == semantic[0] or name == semantic[2]);
}

test "unreferenced concrete method predicates stay lazy and demanded functions reject them" {
    var unused = try lower("const unused = fn () -> U32 => @type.call \"add\" #True #False\nentry const answer = 42\n");
    defer unused.deinit(a);
    try expectValue(&unused, "answer", .{ .scalar = .u32, .bits = 42 });
    var demanded = try lower("const unused = fn () -> U32 => @type.call \"add\" #True #False\nentry const answer = unused ()\n");
    defer demanded.deinit(a);
    const result = try evaluator.evaluate(a, &.{demanded}, target(&demanded, "answer"), .{});
    try std.testing.expectEqual(evaluator.Code.missing_associated, result.diagnostic.?.code);
    try std.testing.expectEqual(@as(u32, 31), result.diagnostic.?.span.start);
    var operand = try lower("const unused = fn () -> U32 => @type.call \"add\" #True #False\nentry const answer = unused (@panic \"argument\")\n");
    defer operand.deinit(a);
    const ordered = try evaluator.evaluate(a, &.{operand}, target(&operand, "answer"), .{});
    try std.testing.expectEqual(evaluator.Code.missing_associated, ordered.diagnostic.?.code);
}

const staged_builder_source =
    \\infixl 60 (+) = _fixity_add
    \\type Builder callback is data = #Builder {run:callback}
    \\const add_step = fn amount => fn builder => do:
    \\  let #Builder {run:previous} = builder
    \\  return #Builder {run:fn value => previous value + amount}
    \\const staged = do:
    \\  let builder = #Builder {run:fn value => value}
    \\  builder := add_step 10 self
    \\  builder := add_step 20 self
    \\  return builder
    \\const floating = do:
    \\  let builder = #Builder {run:fn value => value}
    \\  builder := add_step 1.5 self
    \\  builder := add_step 2.5 self
    \\  return builder
    \\entry const integer_view = staged
    \\entry const floating_view = floating
    \\const _fixity_add = fn left => fn right => @type.call "add" left right
;

fn builderSpecializationScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for ([_][]const u8{ "integer_view", "floating_view" }, [_]u32{ 3, 4 }) |name, scalar| {
        const builder = try session.richValue(target(module, name));
        const callback = session.valueChildren(session.valueChildren(builder)[0])[0];
        const expected = try session.evidence.intern(.function, scalar, scalar, &.{});
        const steps = session.steps;
        const specialized = try session.specializeClosure(callback, expected);
        try std.testing.expectEqual(steps, session.steps);
        try std.testing.expectEqual(expected, session.valueEvidence(specialized));
        try std.testing.expect(session.closureInfo(specialized).mappings.len != 0);
        const values = session.values.items.len;
        const regions = session.counters.inference_regions;
        try std.testing.expectEqual(specialized, try session.specializeClosure(specialized, expected));
        try std.testing.expectEqual(values, session.values.items.len);
        try std.testing.expectEqual(regions, session.counters.inference_regions);
        try std.testing.expectEqual(steps, session.steps);
        for (session.valueChildren(specialized)) |capture| if (session.valueInfo(capture).kind == .closure) {
            try std.testing.expectEqual(expected, session.valueEvidence(capture));
            try std.testing.expectEqual(capture, try session.specializeClosure(capture, expected));
            try std.testing.expectEqual(values, session.values.items.len);
            try std.testing.expectEqual(regions, session.counters.inference_regions);
        };
    }
    var snapshot = try session.copySnapshot(allocator);
    defer snapshot.deinit(allocator);
}

test "owned closure evidence region specializes unannotated staged builders without executing bodies" {
    var module = try lowerPreludeProducer(staged_builder_source, &.{.add});
    defer module.deinit(a);
    try builderSpecializationScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, builderSpecializationScenario, .{&module});
}

test "closure evidence region resolves nested accessor fields and captured aggregate callbacks" {
    var module = try lower(
        \\type Box value is data = #Box {value:value}
        \\const Box.get = fn (self:Box value) => self.value
        \\const nested = .get.value
        \\const make = fn box => fn value => box.value value
        \\const ready = make (#Box {value:fn value=>value})
        \\entry const accessor = nested
        \\entry const captured = ready
    );
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const integer_fn = try session.evidence.intern(.function, 3, 3, &.{});
    const box = for (module.nominals) |nominal| {
        if (nominal.identity.decl != 0) break nominal.identity;
    } else unreachable;
    const owner = if (box.unit == 0) (if (module.unit == 0) 1 else module.unit) else box.unit;
    const inner = try session.evidence.intern(.nominal, owner, box.decl, &.{3});
    const outer = try session.evidence.intern(.nominal, owner, box.decl, &.{inner});
    const expected = try session.evidence.intern(.function, outer, 3, &.{});
    const accessor = try session.specializeClosure(try session.richValue(target(&module, "accessor")), expected);
    try std.testing.expectEqual(expected, session.valueEvidence(accessor));
    const original = try session.richValue(target(&module, "captured"));
    const ready = try session.specializeClosure(original, integer_fn);
    try std.testing.expectEqual(integer_fn, session.valueEvidence(ready));
    const captured_box = session.valueChildren(ready)[0];
    const callback = session.valueChildren(session.valueChildren(captured_box)[0])[0];
    try std.testing.expectEqual(integer_fn, session.valueEvidence(callback));
    const size = session.snapshot().values.len;
    try std.testing.expectEqual(ready, try session.specializeClosure(original, integer_fn));
    try std.testing.expectEqual(size, session.snapshot().values.len);
}

test "demand evaluation skips bodies, caches aliases and retains lexical capture versions" {
    var module = try lower(
        \\const delay = fn ~value=>value
        \\const ignore = fn ~(value:U32)=>42
        \\const pending = delay (@u32.add 20 1)
        \\const before = fn start=>do:
        \\  let value=start
        \\  let deferred=delay value
        \\  value:=@u32.add self 1
        \\  return @force deferred
        \\entry const suspension=pending
        \\entry const first=@force pending
        \\entry const second=@force pending
        \\entry const ignored=ignore (@panic "unused")
        \\entry const captured=before 42
    );
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const pending = try session.richValue(target(&module, "suspension"));
    try std.testing.expectEqual(evaluator.ValueKind.suspension, session.valueInfo(pending).kind);
    try std.testing.expect(session.suspensionCached(pending) == null);
    try std.testing.expectEqual(@as(u32, 21), (try session.value(target(&module, "first"))).bits);
    const memo = session.suspensionCached(pending).?;
    const steps = session.steps;
    try std.testing.expectEqual(@as(u32, 21), (try session.value(target(&module, "second"))).bits);
    try std.testing.expectEqual(steps + 2, session.steps);
    try std.testing.expectEqual(memo, session.suspensionCached(pending).?);
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(&module, "ignored"))).bits);
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(&module, "captured"))).bits);
}

fn demandAllocationScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const closure = try session.richValue(target(module, "function"));
    const actual = try session.evidence.intern(.function, 1, 3, &.{});
    const specialized = try session.specializeClosure(closure, actual);
    const pending = session.valueChildren(specialized)[0];
    try std.testing.expectEqual(evaluator.ValueKind.suspension, session.valueInfo(pending).kind);
    try std.testing.expect(session.suspensionCached(pending) == null);
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "answer"))).bits);
    try std.testing.expect(session.suspensionCached(pending) != null);
    var snapshot = try session.copySnapshot(allocator);
    defer snapshot.deinit(allocator);
    try std.testing.expectEqual(evaluator.DemandState.cached, snapshot.demands[@intCast(snapshot.values[pending].nominal)].state);
}

test "staged closures preserve shared demand memo slots through specialization and every allocation failure" {
    var module = try lower(
        \\const capture = fn ~value=>fn ()=>@force value
        \\const ready=capture (@u32.add 40 2)
        \\entry const function=ready
        \\entry const answer=ready ()
    );
    defer module.deinit(a);
    try demandAllocationScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, demandAllocationScenario, .{&module});
}

test "forcing a demand traces named dependencies lazily and never publishes failed memo values" {
    var module = try lower(
        \\const delay=fn ~(value:U32)=>value
        \\const bad=@panic "named deferred failure"
        \\const pending=delay (if #False then bad else 42)
        \\entry const suspension=pending
        \\entry const forced=@force pending
        \\entry const direct=@force (delay (if #False then @panic "unselected" else 42))
    );
    defer module.deinit(a);
    try expectValue(&module, "direct", .{ .scalar = .u32, .bits = 42 });
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const pending = try session.richValue(target(&module, "suspension"));
    try std.testing.expectEqual(@as(usize, 0), session.demands.items[@intCast(session.valueInfo(pending).nominal)].value);
    try std.testing.expectError(error.Declined, session.richValue(target(&module, "forced")));
    try std.testing.expectEqual(evaluator.Code.const_panic, session.diagnostic.?.code);
    try std.testing.expectEqualStrings("named deferred failure", session.diagnostic.?.detail);
    try std.testing.expectEqual(evaluator.DemandState.pending, session.demands.items[@intCast(session.valueInfo(pending).nominal)].state);
    try std.testing.expect(session.suspensionCached(pending) == null);
    var budget = try evaluator.Session.init(a, &.{module});
    defer budget.deinit();
    const unforced = try budget.richValue(target(&module, "suspension"));
    budget.options.max_steps = budget.steps + 1;
    try std.testing.expectError(error.Declined, budget.richValue(target(&module, "forced")));
    try std.testing.expectEqual(evaluator.Code.constant_fuel, budget.diagnostic.?.code);
    try std.testing.expect(budget.suspensionCached(unforced) == null);
}

test "owned demand snapshots retain aggregate memo values after source and session teardown" {
    var module = try lower(
        \\const delay=fn ~value=>value
        \\const pending=delay #[20,22]
        \\entry const suspension=pending
        \\entry const forced=@force pending
    );
    var session = try evaluator.Session.init(a, &.{module});
    const pending = try session.richValue(target(&module, "suspension"));
    const expected = try session.evidence.intern(.demand, try session.evidence.intern(.array, 3, 0, &.{}), 0, &.{});
    const alias = try session.specializeSuspension(pending, expected);
    try std.testing.expectEqual(session.valueInfo(pending).nominal, session.valueInfo(alias).nominal);
    _ = try session.richValue(target(&module, "forced"));
    const memo = session.suspensionCached(alias).?;
    var snapshot = try session.copySnapshot(a);
    defer snapshot.deinit(a);
    session.deinit();
    module.deinit(a);
    try std.testing.expectEqual(expected, snapshot.value_evidence[alias]);
    try std.testing.expectEqual(evaluator.DemandState.cached, snapshot.demands[@intCast(snapshot.values[alias].nominal)].state);
    const info = snapshot.values[memo];
    try std.testing.expectEqual(evaluator.ValueKind.array, info.kind);
    try std.testing.expectEqual(@as(u32, 20), snapshot.values[snapshot.children[info.start]].bits);
    try std.testing.expectEqual(@as(u32, 22), snapshot.values[snapshot.children[info.start + 1]].bits);
}

test "closure evidence writable fields ignore associated read members" {
    var module = try lower(
        \\type Box value is data=#Box {value:value}
        \\const Box.value=fn (self:Box value)=>self
        \\const change=fn box=>do:
        \\  box.value:=@u32.add self 1
        \\  return box
        \\entry const function=change
    );
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const box = for (module.nominals) |nominal| {
        if (nominal.identity.decl != 0) break nominal.identity;
    } else unreachable;
    const nominal = try session.evidence.intern(.nominal, box.unit, box.decl, &.{3});
    const expected = try session.evidence.intern(.function, nominal, nominal, &.{});
    const specialized = try session.specializeClosure(try session.richValue(target(&module, "function")), expected);
    try std.testing.expectEqual(expected, session.valueEvidence(specialized));
}

fn resultClosureRegionScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const box = for (module.nominals) |nominal| {
        if (nominal.identity.decl != 0) break nominal.identity;
    } else unreachable;
    const nominal = try session.evidence.intern(.nominal, box.unit, box.decl, &.{3});
    const expected = try session.evidence.intern(.function, 3, nominal, &.{});
    const original = try session.richValue(target(module, "function"));
    const steps = session.steps;
    const specialized = try session.specializeClosure(original, expected);
    try std.testing.expectEqual(steps, session.steps);
    try std.testing.expectEqual(expected, session.valueEvidence(specialized));
    try std.testing.expectEqual(expected, session.valueEvidence(session.valueChildren(specialized)[0]));
    var snapshot = try session.copySnapshot(allocator);
    defer snapshot.deinit(allocator);
    try std.testing.expectEqual(expected, snapshot.value_evidence[specialized]);
}

test "closure evidence resolves result-associated constraints through captured generic producers" {
    var module = try lower(
        \\type Box value is data=#Box value
        \\const Box.from=fn value=>#Box value
        \\const from=fn value=>@type.result "from" value
        \\const make=fn callback=>fn value=>callback value
        \\entry const function=make from
    );
    defer module.deinit(a);
    try resultClosureRegionScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, resultClosureRegionScenario, .{&module});
}

test "declared type tokens and generic monad factories retain exact source producer identity" {
    var module = try lower(
        \\type Wrap value is data=#Wrap value
        \\const alias=Wrap
        \\const monad=fn constructor=>@do.monad constructor
        \\entry const token=alias
        \\entry const provider=monad alias
    );
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const token = try session.richValue(target(&module, "token"));
    const provider = try session.richValue(target(&module, "provider"));
    try std.testing.expectEqual(evaluator.ValueKind.type_constructor, session.valueInfo(token).kind);
    try std.testing.expectEqual(evaluator.ValueKind.resolver, session.valueInfo(provider).kind);
    try std.testing.expectEqual(session.valueInfo(token).nominal, session.valueInfo(provider).nominal);
    const token_type = session.valueEvidence(token);
    try std.testing.expectEqual(@import("type_evidence.zig").Tag.type_constructor, session.evidence.node(token_type).tag);
    try std.testing.expectEqual(token_type, session.evidence.node(session.valueEvidence(provider)).a);
}

test "resolver binds invoke ordinary continuations repeatedly with independent lexical rebindings" {
    var module = try lower(
        \\type Wrap value is data=#Wrap value
        \\const Wrap.pure=fn value=>#Wrap value
        \\const Wrap.bind=fn candidate=>fn next=>do:
        \\  let #Wrap first=next candidate
        \\  let #Wrap second=next (@u32.add candidate 1)
        \\  return #Wrap (@u32.add first second)
        \\const monad=fn constructor=>@do.monad constructor
        \\const provider=monad Wrap
        \\const run=fn ()=>do provider:
        \\  let amount=20
        \\  use value<-20
        \\  amount:=@u32.add self value
        \\  return amount
        \\entry const answer=case run () of
        \\  #Wrap result=>result
    );
    defer module.deinit(a);
    try expectValue(&module, "answer", .{ .scalar = .u32, .bits = 81 });
}

test "resolver producers control ignored continuations forwarding and falling through" {
    var module = try lower(
        \\type Wrap value is data=#Wrap value
        \\const Wrap.pure=fn value=>#Wrap value
        \\const Wrap.bind=fn (candidate:U32)=>fn (next:U32->Wrap U32)=>#Wrap 42
        \\const monad=fn constructor=>@do.monad constructor
        \\const provider=monad Wrap
        \\entry const skipped=case (do provider:
        \\  use value<-0
        \\  return @panic "unused continuation"
        \\) of
        \\  #Wrap value=>value
        \\entry const forwarded=case (do provider:
        \\  return $ #Wrap 42
        \\) of
        \\  #Wrap value=>value
        \\entry const fallback=do provider:
        \\  let value=42
    );
    defer module.deinit(a);
    try expectValue(&module, "skipped", .{ .scalar = .u32, .bits = 42 });
    try expectValue(&module, "forwarded", .{ .scalar = .u32, .bits = 42 });
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const fallback = try session.richValue(target(&module, "fallback"));
    try std.testing.expectEqual(evaluator.ValueKind.nominal, session.valueInfo(fallback).kind);
    try std.testing.expectEqual(scalar_ops.Value{ .scalar = .unit, .bits = 0 }, session.valueScalar(session.valueChildren(fallback)[0]).?);
}

const resolver_capture_source =
    \\type Wrap value is data=#Wrap value
    \\const Wrap.pure=fn value=>#Wrap value
    \\const Wrap.bind=fn candidate=>fn next=>next candidate
    \\const monad=fn constructor=>@do.monad constructor
    \\const make=fn provider=>fn value=>do provider:
    \\  use first<-value
    \\  return first
    \\const provider=monad Wrap
    \\const run=make provider
    \\entry const function=run
    \\entry const integer=run 42
    \\entry const floating=run 1.5
;

fn resolverAllocationScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const closure = try session.richValue(target(module, "function"));
    const family = for (module.nominals) |nominal| {
        if (nominal.identity.decl != 0) break nominal.identity;
    } else unreachable;
    const integer = try session.evidence.intern(.nominal, family.unit, family.decl, &.{3});
    const floating = try session.evidence.intern(.nominal, family.unit, family.decl, &.{4});
    const integer_type = try session.evidence.intern(.function, 3, integer, &.{});
    const floating_type = try session.evidence.intern(.function, 4, floating, &.{});
    const integer_closure = try session.specializeClosure(closure, integer_type);
    const floating_closure = try session.specializeClosure(closure, floating_type);
    try std.testing.expect(integer_closure != floating_closure);
    const provider = session.valueChildren(integer_closure)[0];
    try std.testing.expectEqual(evaluator.ValueKind.resolver, session.valueInfo(provider).kind);
    var before = try session.copySnapshot(allocator);
    defer before.deinit(allocator);
    const integer_value = try session.richValue(target(module, "integer"));
    const floating_value = try session.richValue(target(module, "floating"));
    try std.testing.expectEqual(@as(u32, 42), session.valueScalar(session.valueChildren(integer_value)[0]).?.bits);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 1.5))), session.valueScalar(session.valueChildren(floating_value)[0]).?.bits);
    try std.testing.expectEqual(integer_type, before.value_evidence[integer_closure]);
    try std.testing.expectEqual(floating_type, before.value_evidence[floating_closure]);
    try std.testing.expectEqual(before.values[provider].nominal, session.valueInfo(provider).nominal);
}

test "captured resolver callbacks preserve exact independent evidence and snapshot ownership on every allocation failure" {
    var module = try lower(resolver_capture_source);
    defer module.deinit(a);
    try resolverAllocationScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, resolverAllocationScenario, .{&module});
}

const private_body_source =
    \\type Box value is data=#Box {value:value}
    \\const Box.get=fn (self:Box value)=>self.value
    \\const nested=.get.value
    \\const Box.pure=fn value=>#Box {value:value}
    \\const Box.bind=fn candidate=>fn next=>next candidate.value
    \\const monad=fn constructor=>@do.monad constructor
    \\const sequence=fn (candidate:U32)=>do (monad Box):
    \\  use value<-#Box {value:candidate}
    \\  return @u32.add value 2
    \\entry const accessor=nested
    \\entry const function=sequence
;

fn privateBodyScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const family = for (module.nominals) |nominal| {
        if (nominal.identity.decl != 0) break nominal.identity;
    } else unreachable;
    const nominal = try session.evidence.intern(.nominal, family.unit, family.decl, &.{3});
    const nested = try session.evidence.intern(.nominal, family.unit, family.decl, &.{nominal});
    const accessor_type = try session.evidence.intern(.function, nested, 3, &.{});
    var accessor_binding: core.BindingId = 0;
    for (module.bodies) |body| if (std.mem.eql(u8, module.name(body.export_name), "accessor")) {
        accessor_binding = body.binding;
        break;
    };
    const alias = module.node(module.body(accessor_binding).?.root);
    const reference = module.reference(module.body(accessor_binding).?.root);
    try std.testing.expectEqual(core.Tag.reference, alias.tag);
    var accessor_proof = try session.bodyEvidenceFull(.{ .unit = if (module.unit == 0) 1 else module.unit, .binding = reference.binding }, accessor_type, &.{}, &.{});
    defer accessor_proof.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    try std.testing.expectEqual(@as(usize, 1), session.values.items.len);
    const concrete = try session.evidence.projectWithRows(&module.types, module.binding(reference.binding).ty, accessor_proof.types, accessor_proof.rows);
    try std.testing.expectEqual(accessor_type, concrete);
    const sequence_type = try session.evidence.intern(.function, 3, nominal, &.{});
    const function = target(module, "function");
    const producer = module.reference(module.body(function.binding).?.root);
    var body_proof = try session.bodyEvidenceFull(.{ .unit = function.unit, .binding = producer.binding }, sequence_type, &.{}, &.{});
    defer body_proof.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    for (module.nodes) |node| if (node.tag == .resolver_op) {
        const op = module.resolver_ops[node.a];
        if (op.method_type != 0) _ = try session.evidence.projectWithRows(&module.types, op.method_type, body_proof.types, body_proof.rows);
    };
    for (module.closures, 0..) |closure, catalog| {
        const parameter = session.evidence.projectWithRows(&module.types, closure.parameter.ty, body_proof.types, body_proof.rows) catch |err| switch (err) {
            error.UnresolvedType => continue,
            else => return err,
        };
        const result = session.evidence.projectWithRows(&module.types, module.typeOf(closure.body), body_proof.types, body_proof.rows) catch |err| switch (err) {
            error.UnresolvedType => continue,
            else => return err,
        };
        const expected = try session.evidence.intern(.function, parameter, result, &.{});
        var closure_proof = try session.closureEvidenceFull(function.unit, @intCast(catalog), expected, body_proof.types, body_proof.rows);
        defer closure_proof.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    }
}

test "pure frozen body and closure evidence APIs solve private fields and resolver arguments without values" {
    var module = try lower(private_body_source);
    defer module.deinit(a);
    try privateBodyScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, privateBodyScenario, .{&module});
}

test "generic cursor evidence retains array and list element relationships without evaluation" {
    var module = try lowerWithOptions(
        \\const F32.abs = fn value => @f32.abs value
        \\const read = fn cursor => (@cursor.value cursor).abs
        \\entry const array = fn (values: Array F32) => read (@array.cursor values)
        \\entry const list = fn (values: List F32) => read (@list.cursor values)
    , .{ .builtin_catalog = true });
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    for ([_][]const u8{ "array", "list" }) |name| {
        const reference = target(&module, name);
        const collection = try session.evidence.intern(if (std.mem.eql(u8, name, "array")) .array else .list, types.f32_type, 0, &.{});
        const expected = try session.evidence.intern(.function, collection, types.f32_type, &.{});
        var proof = try session.bodyEvidenceFull(reference, expected, &.{}, &.{});
        defer proof.deinit(a);
        const signature = try session.evidence.projectWithRows(&module.types, module.binding(reference.binding).ty, proof.types, proof.rows);
        const arrow = session.evidence.node(signature);
        try std.testing.expectEqual(type_evidence.Tag.function, arrow.tag);
        try std.testing.expectEqual(types.f32_type, arrow.b);
    }
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}

test "an absent input's independent phantom type remains unresolved instead of adopting the output type" {
    var module = try lower(
        \\type Option value is data=#Present value | #Absent
        \\const Option.pure=fn value=>#Present value
        \\const Option.bind=fn candidate=>fn next=>case candidate of
        \\  #Present value=>next value
        \\  #Absent=>#Absent
        \\entry const sequence=fn (flag:Bool)=>do (@do.monad Option):
        \\  if flag:
        \\    use #Absent
        \\  return 42
    );
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const family = for (module.nominals) |nominal| {
        if (nominal.identity.decl != 0) break nominal.identity;
    } else unreachable;
    const result = try session.evidence.intern(.nominal, family.unit, family.decl, &.{3});
    const expected = try session.evidence.intern(.function, 2, result, &.{});
    const mappings = try session.bodyEvidence(target(&module, "sequence"), expected, &.{});
    defer a.free(mappings);
    var input_unresolved = false;
    for (module.nodes) |node| if (node.tag == .resolver_op and module.resolver_ops[node.a].operation == .bind) {
        const info = module.resolver_ops[node.a];
        const method = module.types.node(info.method_type);
        try std.testing.expectEqual(core.Tag.resolver_op, node.tag);
        const actual = session.evidence.project(&module.types, method.a, mappings) catch |err| switch (err) {
            error.UnresolvedType => {
                input_unresolved = true;
                continue;
            },
            else => return err,
        };
        _ = actual;
    };
    try std.testing.expect(input_unresolved);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}

test "frozen body evidence separates generic call instances and closes recursive type dependencies without evaluation" {
    var module = try lowerPreludeProducer(
        \\infix 30 (==) = _fixity_eq
        \\type Box value is data=#Box {value:value}
        \\const get=fn box=>box.value
        \\const alias=get
        \\const repeat=fn (value:U32)->U32=>if value==0 then 42 else repeat (@u32.sub value 1)
        \\entry const mixed=fn ()=> (alias (#Box {value:42}),alias (#Box {value:1.5}))
        \\entry const recursive=repeat
        \\const _fixity_eq = fn left => fn right => @type.call "eq" left right
    , &.{.eq});
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const pair = try session.evidence.intern(.product, 0, 0, &.{ 3, 4 });
    const expected = try session.evidence.intern(.function, 1, pair, &.{});
    const mappings = try session.bodyEvidence(target(&module, "mixed"), expected, &.{});
    defer a.free(mappings);
    try std.testing.expectEqual(expected, try session.evidence.project(&module.types, module.binding(target(&module, "mixed").binding).scheme.root, mappings));
    const alias = module.reference(module.body(target(&module, "recursive").binding).?.root);
    const recursive_expected = try session.evidence.intern(.function, 3, 3, &.{});
    const recursive = try session.bodyEvidence(.{ .unit = 1, .binding = alias.binding }, recursive_expected, &.{});
    defer a.free(recursive);
    try std.testing.expectEqual(recursive_expected, try session.evidence.project(&module.types, module.binding(alias.binding).scheme.root, recursive));
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    try std.testing.expectEqual(@as(usize, 1), session.values.items.len);
}

fn partialEvidenceScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    var expectations = try code_expectation.Store.init(allocator);
    defer expectations.deinit();
    const ignored_type = try expectations.intern(.function, 0, 3, &.{});
    const ignored = try session.bodyEvidencePartial(target(module, "ignored"), expectations.view(), ignored_type, &.{});
    defer allocator.free(ignored);
    const ignored_root = module.types.node(module.binding(target(module, "ignored").binding).scheme.root);
    for (ignored) |mapping| try std.testing.expect(mapping.variable != ignored_root.a);
    try std.testing.expectError(error.UnresolvedType, session.evidence.project(&module.types, ignored_root.a, ignored));
    const pair = try expectations.intern(.product, 0, 0, &.{ 3, 4 });
    const right = try expectations.intern(.function, 0, pair, &.{});
    const shape = try expectations.intern(.function, 0, right, &.{});
    const pair_mappings = try session.bodyEvidencePartial(target(module, "pair"), expectations.view(), shape, &.{});
    defer allocator.free(pair_mappings);
    const actual = try session.evidence.project(&module.types, module.binding(target(module, "pair").binding).scheme.root, pair_mappings);
    const left_node = session.evidence.node(actual);
    try std.testing.expectEqual(@as(u32, 3), left_node.a);
    try std.testing.expectEqual(@as(u32, 4), session.evidence.node(left_node.b).a);
    const outer = try expectations.intern(.function, 3, ignored_type, &.{});
    const outer_mappings = try session.bodyEvidencePartial(target(module, "maker"), expectations.view(), outer, &.{});
    defer allocator.free(outer_mappings);
    var saw_closure = false;
    for (module.closures, 0..) |closure, catalog| {
        const parameter = module.types.node(closure.parameter.ty);
        if (parameter.tag != .variable or module.types.node(module.typeOf(closure.body)).tag != .u32) continue;
        const mappings = try session.closureEvidencePartial(if (module.unit == 0) 1 else module.unit, @intCast(catalog), expectations.view(), ignored_type, outer_mappings);
        defer allocator.free(mappings);
        for (mappings) |mapping| try std.testing.expect(mapping.variable != closure.parameter.ty);
        saw_closure = true;
    }
    try std.testing.expect(saw_closure);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}
test "partial code expectations preserve independent unknown parameters and derive concrete facts without evaluation" {
    var module = try lower(
        \\entry const ignored = fn value => 42
        \\entry const pair = fn left => fn right => (left,right)
        \\entry const maker = fn outer => do:
        \\  let retained = outer
        \\  return fn ignored => @u32.add retained 2
    );
    defer module.deinit(a);
    try partialEvidenceScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, partialEvidenceScenario, .{&module});
}

// The source-effect syntax is tested at its own admission boundary. This fixture
// isolates transfer of normalized semantic rows through immutable publication.
fn rowEvidenceModule() !core.Module {
    const source =
        \\entry const direct = fn (value: U32) -> U32 => value
        \\entry const required = fn (value: U32) -> U32 => value
        \\entry const maker = fn () => do:
        \\  return fn (value: U32) -> U32 => value
        \\entry const certified = fn (value: U32) -> U32 => value
    ;
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    var checked = try checker.check(a, &syntax, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var store = &checked.types;
    const open = try store.freshEffects();
    const variable = store.row(open).tail.variable;
    const integer = try store.internOperation(.{ .unit = 7, .decl = 9 }, &.{types.u32_type});
    const floating = try store.internOperation(.{ .unit = 7, .decl = 9 }, &.{types.f32_type});
    const closed = try store.effects.row(&.{ integer, floating, integer }, .closed);
    for (syntax.roots.items[0..2], 0..) |declaration, index| {
        const binding = checked.resolved[declaration];
        const lambda = syntax.valueDecl(declaration).body;
        const original = store.node(checked.bindings[binding].scheme.root);
        const signature = try store.functionWithEffects(original.a, original.b, if (index == 0) open else closed);
        checked.bindings[binding].ty = signature;
        checked.bindings[binding].scheme.root = signature;
        checked.expr_types[lambda] = signature;
        if (index == 0) checked.bindings[binding].scheme.row_variables = try store.saveList(&.{variable});
    }
    const maker = checked.resolved[syntax.roots.items[2]];
    const outer_source = syntax.valueDecl(syntax.roots.items[2]).body;
    const suite_source = syntax.node(outer_source).b;
    const inner_source = syntax.node(syntax.children(suite_source)[0]).a;
    const outer = store.node(checked.bindings[maker].scheme.root);
    const inner = store.node(outer.b);
    const callback = try store.functionWithEffects(inner.a, inner.b, open);
    const envelope = try store.functionWithEffects(outer.a, callback, outer.c);
    checked.bindings[maker].ty = envelope;
    checked.bindings[maker].scheme.root = envelope;
    checked.bindings[maker].scheme.row_variables = try store.saveList(&.{variable});
    checked.expr_types[outer_source] = envelope;
    checked.expr_types[suite_source] = callback;
    checked.expr_types[inner_source] = callback;
    const maker_closed = try store.closeCovariantCertified(envelope, &.{variable}, &.{});
    checked.bindings[maker].scheme.root = maker_closed.root;
    checked.bindings[maker].scheme.closed_rows = maker_closed.closed_rows;
    checked.lambda_closed_rows[inner_source] = maker_closed.closed_rows;
    const certified_declaration = syntax.roots.items[3];
    const certified = checked.resolved[certified_declaration];
    const certified_source = syntax.valueDecl(certified_declaration).body;
    const certified_tail = try store.freshEffects();
    const certified_variable = store.row(certified_tail).tail.variable;
    const certified_row = try store.effects.row(&.{integer}, .{ .variable = certified_variable });
    const certified_raw = try store.functionWithEffects(types.u32_type, types.u32_type, certified_row);
    const certified_closed = try store.closeCovariantCertified(certified_raw, &.{certified_variable}, &.{});
    checked.bindings[certified].ty = certified_raw;
    checked.bindings[certified].scheme.root = certified_closed.root;
    checked.bindings[certified].scheme.closed_rows = certified_closed.closed_rows;
    checked.expr_types[certified_source] = certified_raw;
    checked.body_closed_rows = try a.realloc(checked.body_closed_rows, 2);
    checked.body_closed_rows[0] = .{ .owner = maker, .variable = variable };
    checked.body_closed_rows[1] = .{ .owner = certified, .variable = certified_variable };
    var module = try core.lower(a, &syntax, &pool, &checked);
    errdefer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
fn rowEvidenceScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    var expectations = try code_expectation.Store.init(allocator);
    defer expectations.deinit();
    const shape = try expectations.intern(.function, types.u32_type, types.u32_type, &.{});
    const direct = target(module, "direct");
    const root = module.binding(direct.binding).scheme.root;
    const variable = module.types.row(module.types.node(root).c).tail.variable;
    var unknown = try session.bodyEvidencePartialFull(direct, expectations.view(), shape, &.{}, &.{});
    defer unknown.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), unknown.rows.len);
    try std.testing.expectError(error.UnresolvedType, session.evidence.projectWithRows(&module.types, root, unknown.types, unknown.rows));
    var empty = try session.bodyEvidencePartialFull(direct, expectations.view(), shape, &.{}, &.{.{ .variable = variable, .evidence = 0 }});
    defer empty.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), empty.rows.len);
    try std.testing.expectEqual(variable, empty.rows[0].variable);
    try std.testing.expectEqual(@as(u32, 0), empty.rows[0].evidence);
    const integer = try session.evidence.effects.internOperation(.{ .unit = 7, .decl = 9 }, &.{types.u32_type});
    const floating = try session.evidence.effects.internOperation(.{ .unit = 7, .decl = 9 }, &.{types.f32_type});
    const row = try session.evidence.effects.internRow(&.{ floating, integer, integer });
    var seeded = try session.bodyEvidencePartialFull(direct, expectations.view(), shape, &.{}, &.{.{ .variable = variable, .evidence = row }});
    defer seeded.deinit(allocator);
    try std.testing.expectEqual(row, seeded.rows[0].evidence);
    const expected = try session.evidence.internWithEffects(.function, types.u32_type, types.u32_type, row, &.{});
    try std.testing.expectEqual(expected, try session.evidence.projectWithRows(&module.types, root, seeded.types, seeded.rows));
    var inferred = try session.bodyEvidenceFull(direct, expected, &.{}, &.{});
    defer inferred.deinit(allocator);
    try std.testing.expectEqual(row, inferred.rows[0].evidence);
    var required = try session.bodyEvidenceFull(target(module, "required"), expected, &.{}, &.{});
    defer required.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), required.rows.len);
    const certified = target(module, "certified");
    const certified_root = module.binding(certified.binding).ty;
    var certified_proof = try session.bodyEvidencePartialFull(certified, expectations.view(), shape, &.{}, &.{});
    defer certified_proof.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), certified_proof.rows.len);
    try std.testing.expectEqual(@as(u32, 0), certified_proof.rows[0].evidence);
    const certified_type = try session.evidence.projectWithRows(&module.types, certified_root, certified_proof.types, certified_proof.rows);
    const certified_labels = session.evidence.view().effects.rowLabels(session.evidence.node(certified_type).c);
    try std.testing.expectEqualSlices(u32, &.{integer}, certified_labels);
    const widened_row = try session.evidence.effects.internRow(&.{ integer, floating });
    const widened = try session.evidence.internWithEffects(.function, types.u32_type, types.u32_type, widened_row, &.{});
    var widened_proof = try session.bodyEvidenceFull(certified, widened, &.{}, &.{});
    defer widened_proof.deinit(allocator);
    try std.testing.expectEqual(widened, try session.evidence.projectWithRows(&module.types, certified_root, widened_proof.types, widened_proof.rows));
    try std.testing.expectEqualSlices(u32, &.{floating}, session.evidence.view().effects.rowLabels(widened_proof.rows[0].evidence));
    var saw_closure = false;
    for (module.closures, 0..) |closure, catalog| {
        const envelope = module.types.node(closure.function_type);
        if (envelope.a != types.u32_type) continue;
        var proof = try session.closureEvidenceFull(1, @intCast(catalog), expected, &.{}, &.{});
        defer proof.deinit(allocator);
        try std.testing.expectEqual(row, proof.rows[0].evidence);
        try std.testing.expectEqual(expected, try session.evidence.projectWithRows(&module.types, closure.function_type, proof.types, proof.rows));
        saw_closure = true;
    }
    try std.testing.expect(saw_closure);
    const maker = try session.richValue(target(module, "maker"));
    const maker_expected = try session.evidence.intern(.function, types.unit, expected, &.{});
    const staged = try session.specializeClosure(maker, maker_expected);
    const retained = session.closureInfo(staged).row_mappings;
    const retained_rows = session.row_mappings.items[retained.start..][0..retained.len];
    var retained_variable = false;
    for (retained_rows) |mapping| if (mapping.variable == variable) {
        try std.testing.expectEqual(row, mapping.evidence);
        retained_variable = true;
    };
    try std.testing.expect(retained_variable);
    try std.testing.expectEqual(maker, try session.richValue(target(module, "maker")));
    try std.testing.expectEqual(@as(u32, 0), session.closureInfo(maker).row_mappings.len);
    var snapshot = try session.copySnapshot(allocator);
    defer snapshot.deinit(allocator);
    const snapshot_metadata = snapshot.closures[snapshot.values[staged].bits];
    try std.testing.expectEqualSlices(@import("type_evidence.zig").RowMapping, retained_rows, snapshot.row_mappings[snapshot_metadata.row_mappings.start..][0..snapshot_metadata.row_mappings.len]);
    try std.testing.expectEqual(@as(usize, 3), snapshot.evidence.view().effects.rowLabels(row).len);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}
test "private evidence owns exact operation rows and exports closed source tails without defaults" {
    var module = try rowEvidenceModule();
    defer module.deinit(a);
    try rowEvidenceScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, rowEvidenceScenario, .{&module});
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const integer = try session.evidence.effects.internOperation(.{ .unit = 7, .decl = 9 }, &.{types.u32_type});
    const wrong_row = try session.evidence.effects.internRow(&.{ integer, integer, integer });
    const wrong = try session.evidence.internWithEffects(.function, types.u32_type, types.u32_type, wrong_row, &.{});
    try std.testing.expectError(error.Declined, session.bodyEvidenceFull(target(&module, "required"), wrong, &.{}, &.{}));
    try std.testing.expectEqual(evaluator.Code.effect_mismatch, session.diagnostic.?.code);
}

fn providerEvidenceModule() !core.Module {
    const source = "entry const ordinary = fn value => value\nentry const state = fn value => value\n";
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    var checked = try checker.check(a, &syntax, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var store = &checked.types;
    const argument = try store.nominal(.{ .unit = 11, .decl = 29 }, &.{types.f32_type});
    const read = try store.nominal(.{ .unit = 17, .decl = 23 }, &.{argument});
    const write = try store.nominal(.{ .unit = 17, .decl = 24 }, &.{argument});
    const label = try store.internOperation(.{ .unit = 19, .decl = 31 }, &.{argument});
    const effects = try store.effects.row(&.{ label, label }, .closed);
    const ordinary = try store.provider(read, effects);
    const state_type = try store.array(argument);
    const state = try store.stateProvider(read, write, state_type);
    for (syntax.roots.items, [_]types.Id{ ordinary, state }) |declaration, value_type| {
        const binding = checked.resolved[declaration];
        const source_lambda = syntax.valueDecl(declaration).body;
        const lambda = syntax.node(source_lambda);
        const signature = try store.function(value_type, value_type);
        checked.bindings[binding].ty = signature;
        checked.bindings[binding].scheme.root = signature;
        checked.expr_types[source_lambda] = signature;
        checked.expr_types[lambda.a] = value_type;
        checked.expr_types[lambda.b] = value_type;
        const parameter = checked.resolved[lambda.a];
        checked.bindings[parameter].ty = value_type;
        checked.bindings[parameter].scheme.root = value_type;
    }
    var module = try core.lower(a, &syntax, &pool, &checked);
    errdefer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
fn providerEvidenceScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    var expected = try code_expectation.Store.init(allocator);
    defer expected.deinit();
    const argument = try expected.intern(.nominal, 11, 29, &.{types.f32_type});
    const read = try expected.intern(.nominal, 17, 23, &.{argument});
    const write = try expected.intern(.nominal, 17, 24, &.{argument});
    const provider = try expected.intern(.provider, read, 0, &.{});
    const state = try expected.internStateProvider(read, write, try expected.intern(.array, argument, 0, &.{}));
    for ([_][]const u8{ "ordinary", "state" }, [_]code_expectation.Id{ provider, state }) |name, shape| {
        const reference = target(module, name);
        const root = module.binding(reference.binding).ty;
        const source_value = module.types.node(module.types.node(root).a);
        if (source_value.tag == .provider) {
            const labels = module.types.rowLabels(source_value.c);
            try std.testing.expectEqual(@as(usize, 2), labels.len);
            try std.testing.expectEqual(labels[0], labels[1]);
            try std.testing.expectEqual(types.NominalIdentity{ .unit = 19, .decl = 31 }, module.types.operation(labels[0]).identity);
        } else {
            try std.testing.expectEqual(types.Tag.state_provider, source_value.tag);
            try std.testing.expectEqual(types.Tag.array, module.types.node(source_value.c).tag);
        }
        const concrete = try session.evidence.project(&module.types, root, &.{});
        var exact = try session.bodyEvidenceFull(reference, concrete, &.{}, &.{});
        defer exact.deinit(allocator);
        const signature = try expected.intern(.function, shape, shape, &.{});
        var partial = try session.bodyEvidencePartialFull(reference, expected.view(), signature, &.{}, &.{});
        defer partial.deinit(allocator);
        try std.testing.expectEqual(concrete, try session.evidence.projectWithRows(&module.types, root, partial.types, partial.rows));
    }
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}
test "owned provider evidence separates latent rows from state value types through every import" {
    var module = try providerEvidenceModule();
    defer module.deinit(a);
    try providerEvidenceScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, providerEvidenceScenario, .{&module});
}

const provider_execution_source =
    \\effect Read: Unit -> U32
    \\const provider = @effect.provider Read (fn () => 42)
    \\const read = fn () => Read ()
    \\const invoke = fn callback => callback ()
    \\const force = fn ~value => @force value
    \\const ignore = fn ~value => 42
    \\const direct = fn () => do provider:
    \\  return read ()
    \\const callback = fn () => do provider:
    \\  return invoke (fn () => Read ())
    \\const delayed = fn () => do provider:
    \\  return force (Read ())
    \\entry const constant = do provider:
    \\  return Read ()
    \\entry const named_answer = direct ()
    \\entry const callback_answer = callback ()
    \\entry const delayed_answer = delayed ()
    \\entry const ignored_answer = ignore (Read ())
    \\entry const function = fn () => do provider:
    \\  return read ()
;
test "source providers handle named callbacks and demands in evaluation and private proof" {
    var module = try lower(provider_execution_source);
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    for ([_][]const u8{ "constant", "named_answer", "callback_answer", "delayed_answer", "ignored_answer" }) |name| {
        const actual = session.value(target(&module, name)) catch |err| {
            if (session.diagnostic) |diagnostic| std.debug.print("provider {s}:{d}..{d}: {s}\n", .{ name, diagnostic.span.start, diagnostic.span.end, diagnostic.message() });
            return err;
        };
        try std.testing.expectEqual(scalar_ops.Value{ .scalar = .u32, .bits = 42 }, actual);
        try std.testing.expectEqual(@as(usize, 0), session.providers.frames.items.len);
        try std.testing.expectEqual(@as(usize, 0), session.providers.cells.items.len);
    }
    var expected = try code_expectation.Store.init(a);
    defer expected.deinit();
    const signature = try expected.intern(.function, types.unit, types.u32_type, &.{});
    var proof = try session.bodyEvidencePartialFull(target(&module, "function"), expected.view(), signature, &.{}, &.{});
    defer proof.deinit(a);
}

const provider_state_source =
    \\type Read is effect = { first: Unit -> U32, second: Unit -> U32 }
    \\const outer = @effect.provider Read.first (fn () => 20)
    \\const second = @effect.provider Read.second (fn () => Read.first ())
    \\const younger = @effect.provider Read.first (fn () => 99)
    \\const forwarded = fn () => do outer:
    \\  return do second:
    \\    return do younger:
    \\      use first <- Read.first ()
    \\      use older <- Read.second ()
    \\      return @u32.add first older
    \\type State a is effect = { get: Unit -> a, set: a -> Unit }
    \\const state = @effect.state (State.get (Array U32)) (State.set (Array U32)) #[41]
    \\const snapshot = fn () => do:
    \\  let (next, old) = do state:
    \\    use old <- State.get (Array U32) ()
    \\    let updated = @array.set old 0 42
    \\    use State.set (Array U32) updated
    \\    return old
    \\  return @u32.add (@array.get next 0) (@array.get old 0)
    \\entry const forwarding = forwarded ()
    \\entry const first_snapshot = snapshot ()
    \\entry const second_snapshot = snapshot ()
    \\entry const state_descriptor = state
;
fn providerStateScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for ([_][]const u8{ "forwarding", "first_snapshot", "second_snapshot" }, [_]u32{ 119, 83, 83 }) |name, expected| {
        const actual = session.value(target(module, name)) catch |err| {
            if (session.diagnostic) |diagnostic| std.debug.print("provider {s}:{d}..{d}: {s}\n", .{ name, diagnostic.span.start, diagnostic.span.end, diagnostic.message() });
            return err;
        };
        try std.testing.expectEqual(scalar_ops.Value{ .scalar = .u32, .bits = expected }, actual);
        try std.testing.expectEqual(@as(usize, 0), session.providers.frames.items.len);
        try std.testing.expectEqual(@as(usize, 0), session.providers.cells.items.len);
    }
    const state_value = try session.richValue(target(module, "state_descriptor"));
    const initial = session.stateProviderInfo(state_value).initial;
    try std.testing.expectEqual(@as(u32, 41), session.valueInfo(session.valueChildren(initial)[0]).bits);
}
test "source provider forwarding skips younger heads and State preserves fresh immutable snapshots" {
    var module = try lower(provider_state_source);
    defer module.deinit(a);
    try providerStateScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, providerStateScenario, .{&module});
}

const runner_sources = [_][]const u8{
    \\type State a is effect = { get: Unit -> a, set: a -> Unit }
    \\const run = fn initial => fn action => @effect.run State.get State.set initial action
    \\entry const answer = fn () => do:
    \\  let (next,previous) = run 41 (fn () => do:
    \\    use previous <- State.get ()
    \\    use State.set (@u32.add previous 1)
    \\    return previous)
    \\  return @u32.add next previous
    \\entry const folded = answer ()
    ,
    \\type State a is effect = { get: Unit -> a, set: a -> Unit }
    \\entry const answer = fn () -> U32 => @effect.reader State.get (fn () -> U32 => @panic "witness called") (fn () => 42) (fn () -> U32 => State.get ())
    \\entry const folded = answer ()
    ,
    \\type State a is effect = { get: Unit -> a, set: a -> Unit }
    \\entry const answer = fn () => do:
    \\  let (next,result) = @effect.run State.get State.set 0 (fn () =>
    \\    @effect.writer State.set (fn () -> U32 => @panic "witness called") (fn value => State.set value) (fn () => do:
    \\      use State.set 42
    \\      return 42))
    \\  return @u32.add next result
    \\entry const folded = answer ()
    ,
    \\type State a is effect = { get: Unit -> a, set: a -> Unit }
    \\entry const answer = fn () => do:
    \\  let (next,result) = @effect.run State.get State.set 41 (fn () =>
    \\    @effect.reader State.get 0 (fn () => 99) (do:
    \\      use before <- State.get ()
    \\      return (fn () -> U32 => before)))
    \\  return @u32.add next result
    \\entry const folded = answer ()
    ,
};
fn runnerScenario(allocator: std.mem.Allocator, module: *const core.Module, expected: u32) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const result = session.value(target(module, "folded")) catch |err| {
        if (session.diagnostic) |diagnostic| std.debug.print("runner:{d}..{d}: {s}\n", .{ diagnostic.span.start, diagnostic.span.end, diagnostic.message() });
        return err;
    };
    try std.testing.expectEqual(scalar_ops.Value{ .scalar = .u32, .bits = expected }, result);
    var shape = try code_expectation.Store.init(allocator);
    defer shape.deinit();
    const signature = try shape.intern(.function, types.unit, types.u32_type, &.{});
    var proof = session.bodyEvidencePartialFull(target(module, "answer"), shape.view(), signature, &.{}, &.{}) catch |err| {
        if (session.diagnostic) |diagnostic| std.debug.print("runner proof:{d}..{d}: {s}\n", .{ diagnostic.span.start, diagnostic.span.end, diagnostic.message() });
        return err;
    };
    defer proof.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), session.providers.frames.items.len);
    try std.testing.expectEqual(@as(usize, 0), session.providers.cells.items.len);
}
test "reference effect runners retain generic row removal and evaluate action operands before installation" {
    for (runner_sources, [_]u32{ 83, 42, 84, 82 }) |source, expected| {
        var module = try lower(source);
        defer module.deinit(a);
        try runnerScenario(a, &module, expected);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, runnerScenario, .{ &module, expected });
    }
}

fn recordEvidenceScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "folded"))).bits);
    try std.testing.expect(session.diagnostic == null);
}

test "staged heterogeneous schemas recover concrete record evidence beside generic callbacks" {
    var module = try lower(
        \\type End is data = #End
        \\type Entry {head,tail} is data = #Entry{head,tail}
        \\type Builder [world,scope,schema] is data = #Builder{initial:world,scope:world->scope,schema:schema}
        \\const End.contains = fn (end:End) => fn witness => #False
        \\const Entry.contains = fn entry => fn witness => do:
        \\  let #Entry{head,tail}=entry
        \\  if @type.same head witness:
        \\    return #True
        \\  return tail.contains(witness)
        \\const empty=fn () => do:
        \\  let scope=fn world => fn action => do:
        \\    use result <- action ()
        \\    return (world,result)
        \\  return #Builder{initial:(),scope,schema:#End}
        \\const insert_cell=fn initial => fn builder => do:
        \\  let #Builder{initial:previous_initial,scope:previous_scope,schema}=builder
        \\  let scope=fn world => fn action => do:
        \\    let (current,previous)=world
        \\    return previous_scope previous action
        \\  return #Builder{initial:(initial,previous_initial),scope,schema}
        \\const insert=fn value => fn builder => do:
        \\  let #Builder{schema}=builder
        \\  if schema.contains(value):
        \\    return @panic "duplicate"
        \\  let #Builder{initial,scope}=insert_cell value builder
        \\  return #Builder{initial,scope,schema:#Entry{head:value,tail:schema}}
        \\const staged=do:
        \\  let builder=empty ()
        \\  builder := insert 42 self
        \\  builder := insert 1.0 self
        \\  return builder
        \\entry const answer=fn () => do:
        \\  let #Builder{schema}=staged
        \\  return if schema.contains(1.0) then 42 else 0
        \\
        \\entry const folded = answer ()
    );
    defer module.deinit(a);
    try recordEvidenceScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, recordEvidenceScenario, .{&module});
}

fn associatedProducerScenario(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var session = try evaluator.Session.init(allocator, modules);
    defer session.deinit();
    const result = try session.value(target(&modules[0], "answer"));
    try std.testing.expectEqual(scalar_ops.Value{ .scalar = .f32, .bits = @bitCast(@as(f32, 42.0)) }, result);
    const member = modules[0].associated[0].member;
    const chosen = (try session.associatedTarget(2, modules[0].associated[0].identity, member, .none)).?;
    try std.testing.expectEqual(@as(u32, 1), chosen.unit);
}

test "generic imported producer dispatch uses the exact nominal declaration owner after frontend teardown" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "producer.blot", .data = "const multiply=fn left=>fn right=>@type.call \"mul\" left right\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "main.blot", .data =
        \\import { multiply } from "./producer"
        \\type Vec is data=#Vec F32
        \\const Vec.mul:Vec->F32->Vec=fn value=>fn scale=>do:
        \\  let #Vec number=value
        \\  return #Vec (@f32.mul number scale)
        \\const scaled=multiply (#Vec 21.0) 2.0
        \\entry const answer=do:
        \\  let #Vec number=scaled
        \\  return number
    });
    const filename = try tmp.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(filename);
    var modules: [2]core.Module = undefined;
    {
        var source = try project.load(a, io, filename, .{});
        defer source.deinit(a);
        var checked = try project_check.checkProject(a, &source);
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        try std.testing.expectEqual(@as(usize, 2), source.units.items.len);
        var completed: usize = 0;
        errdefer for (modules[0..completed]) |*module| module.deinit(a);
        for (&modules, 1..) |*module, unit_id| {
            module.* = try core.lower(a, &source.unit(@intCast(unit_id)).tree, &source.symbols, &checked.module(@intCast(unit_id)).checked);
            module.unit = @intCast(unit_id);
            completed += 1;
            try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
        }
    }
    defer for (&modules) |*module| module.deinit(a);
    try associatedProducerScenario(a, &modules);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, associatedProducerScenario, .{&modules});
}
test "staged generic record publication preserves written field permutations" {
    var module = try lower(
        \\type End is data = #End
        \\type Entry {head,tail} is data = #Entry{head,tail}
        \\type Builder [world,scope,schema] is data = #Builder{initial:world,scope:world->scope,schema:schema}
        \\const End.contains = fn (end:End) => fn witness => #False
        \\const Entry.contains = fn entry => fn witness => do:
        \\  let #Entry{head,tail}=entry
        \\  if @type.same head witness:
        \\    return #True
        \\  return tail.contains(witness)
        \\const empty=fn () => do:
        \\  let scope=fn world => fn action => do:
        \\    use result <- action ()
        \\    return (world,result)
        \\  return #Builder{initial:(),scope,schema:#End}
        \\const insert_cell=fn initial => fn builder => do:
        \\  let #Builder{initial:previous_initial,scope:previous_scope,schema}=builder
        \\  let scope=fn world => fn action => do:
        \\    let (current,previous)=world
        \\    return previous_scope previous action
        \\  return #Builder{initial:(initial,previous_initial),scope,schema}
        \\const insert=fn value => fn builder => do:
        \\  let #Builder{schema}=builder
        \\  if schema.contains(value):
        \\    return @panic "duplicate"
        \\  let #Builder{initial,scope}=insert_cell value builder
        \\  return #Builder{initial,scope,schema:#Entry{tail:schema,head:value}}
        \\const staged=do:
        \\  let builder=empty ()
        \\  builder := insert 42 self
        \\  builder := insert 1.0 self
        \\  return builder
        \\entry const answer=fn () => do:
        \\  let #Builder{schema}=staged
        \\  return if schema.contains(1.0) then 42 else 0
        \\
        \\entry const folded = answer ()
    );
    defer module.deinit(a);
    try recordEvidenceScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, recordEvidenceScenario, .{&module});
}

fn recursiveInferenceScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for ([_][]const u8{ "integer", "floating", "factorial", "mutual" }, [_]types.Id{ types.u32_type, types.f32_type, types.u32_type, types.u32_type }) |name, expected| {
        const original = try session.richValue(target(module, name));
        const steps = session.steps;
        const prior_evidence = session.valueEvidence(original);
        const inferred = try session.inferClosure(original);
        try std.testing.expectEqual(steps, session.steps);
        try std.testing.expectEqual(prior_evidence, session.valueEvidence(original));
        const actual = session.evidenceView().node(session.valueEvidence(inferred));
        try std.testing.expectEqual(type_evidence.Tag.function, actual.tag);
        try std.testing.expectEqual(expected, actual.b);
        try std.testing.expectEqual(@as(u32, 0), actual.c);
        try std.testing.expectEqual(inferred, try session.inferClosure(original));
    }
    try std.testing.expect(session.diagnostic == null);
}

test "recursive owned inference ties active monomorphic calls and keeps independent generic instances" {
    var module = try lowerWithOptions(
        \\infixl 60 (+) = add
        \\const add = fn left => fn right => @type.call "add" left right
        \\const U32.add = fn left => fn right => @u32.add left right
        \\const F32.add = fn left => fn right => @f32.add left right
        \\const recursive = fn value => fn (count: U32) => do:
        \\  if @u32.eq count 0:
        \\    return value
        \\  return recursive (value + value) (@u32.sub count 1)
        \\entry const integer = fn () => recursive 21 1
        \\entry const floating = fn () => recursive 1.25 1
        \\entry const factorial = fn value => do:
        \\  if @u32.lt value 2:
        \\    return 1
        \\  return @u32.mul value (factorial (@u32.sub value 1))
        \\const even = fn (value: U32) => do:
        \\  if @u32.eq value 0:
        \\    return 42
        \\  return odd (@u32.sub value 1)
        \\const odd = fn (value: U32) => do:
        \\  if @u32.eq value 0:
        \\    return 42
        \\  return even (@u32.sub value 1)
        \\entry const mutual = fn () => even 5
    , .{ .builtin_catalog = true });
    defer module.deinit(a);
    const original = try a.dupe(types.Node, module.types.nodes);
    defer a.free(original);
    try recursiveInferenceScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, recursiveInferenceScenario, .{&module});
    try std.testing.expectEqualDeep(original, module.types.nodes);
}

fn namedBinaryEffectScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const before = session.steps;
    const receive_raw = try session.richValue(target(module, "receive"));
    const selected_raw = try session.richValue(target(module, "selected"));
    const merge_raw = try session.richValue(target(module, "merge"));
    const raw_evidence = session.valueEvidence(receive_raw);
    const after_values = session.steps;
    const receive = try session.inferClosure(receive_raw);
    const selected = try session.inferClosure(selected_raw);
    const merge = try session.inferClosure(merge_raw);
    try std.testing.expectEqual(before, after_values);
    try std.testing.expectEqual(after_values, session.steps);
    try std.testing.expectEqual(receive, try session.inferClosure(receive_raw));
    try std.testing.expectEqual(raw_evidence, session.valueEvidence(receive_raw));
    const row = session.evidence.view().effects;
    for ([_]evaluator.ValueId{ receive, selected, merge }, 0..) |value, index| {
        const ty = session.evidence.node(session.valueEvidence(value));
        try std.testing.expectEqual(type_evidence.Tag.function, ty.tag);
        try std.testing.expectEqual(if (index == 2) types.unit else types.boolean, ty.a);
        try std.testing.expectEqual(if (index == 0) types.unit else if (index == 1) types.boolean else types.u32_type, ty.b);
        const labels = row.rowLabels(ty.c);
        try std.testing.expectEqual(@as(usize, 1), labels.len);
        const operation = row.operation(labels[0]).identity;
        var required: ?types.NominalIdentity = null;
        for (module.operation_values) |candidate| {
            const signature = module.types.node(candidate.signature);
            if (signature.a == (if (index == 1) types.unit else types.u32_type) and
                signature.b == (if (index == 1) types.u32_type else types.unit)) required = candidate.identity;
        }
        try std.testing.expect(required != null);
        try std.testing.expectEqualDeep(required.?, operation);
    }
    const pure = try session.evidence.intern(.function, types.boolean, types.unit, &.{});
    try expectCaptureMismatch(&session, receive_raw, pure);
    session.diagnostic = null;
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "answer"))).bits);
    try std.testing.expectEqual(@as(u32, 1), (try session.value(target(module, "loaded"))).bits);
    try std.testing.expectEqual(@as(u32, 0), (try session.value(target(module, "unforced"))).bits);
}

test "named binary calls retain producer effect and demanded operand rows" {
    var module = try lower(
        \\infixl 20 (&&) = choose
        \\infixl 60 (%%) = combine
        \\effect Read: Unit -> U32
        \\effect Touch: U32 -> Unit
        \\const choose = fn (left: Bool) => fn ~(right: Bool) => if left then @force right else #False
        \\const combine = fn (left: U32) => fn (right: U32) => do:
        \\  use Touch left
        \\  return @u32.add left right
        \\entry const receive = fn (flag: Bool) => do:
        \\  let go = flag && #False
        \\  if go:
        \\    return ()
        \\  use Touch 7
        \\  return ()
        \\entry const selected = fn (flag: Bool) => flag && (do:
        \\  use value <- Read ()
        \\  return @u32.eq value 42)
        \\entry const merge = fn () => 20 %% 22
        \\const reader = @effect.provider Read (fn () => 42)
        \\const touch = @effect.provider Touch (fn value => ())
        \\entry const answer = do touch:
        \\  use receive #True
        \\  return 20 %% 22
        \\entry const loaded = do reader:
        \\  return selected #True
        \\entry const unforced = #False && @panic "not demanded"
    );
    defer module.deinit(a);
    const frozen_nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(frozen_nodes);
    const frozen_types = try a.dupe(types.Node, module.types.nodes);
    defer a.free(frozen_types);
    const frozen_rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
    defer a.free(frozen_rows);
    try namedBinaryEffectScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, namedBinaryEffectScenario, .{&module});
    try std.testing.expectEqualDeep(frozen_nodes, module.nodes);
    try std.testing.expectEqualDeep(frozen_types, module.types.nodes);
    try std.testing.expectEqualDeep(frozen_rows, module.types.effects.rows);
}

fn cachedScalarReferenceScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const count = try session.richValue(target(module, "column_count"));
    try std.testing.expectEqual(@as(u32, 9), session.valueScalar(count).?.bits);
    const count_evidence = session.valueEvidence(count);
    const grid_raw = try session.richValue(target(module, "grid"));
    const raw_evidence = session.valueEvidence(grid_raw);
    const before = session.steps;
    const grid = try session.inferClosure(grid_raw);
    try std.testing.expectEqual(grid, try session.inferClosure(grid_raw));
    const expected = try session.evidence.intern(.function, types.unit, types.u32_type, &.{});
    try std.testing.expectEqual(expected, session.valueEvidence(grid));
    try std.testing.expectEqual(before, session.steps);
    try std.testing.expectEqual(count_evidence, session.valueEvidence(count));
    try std.testing.expectEqual(raw_evidence, session.valueEvidence(grid_raw));
    const shadow = try session.inferClosure(try session.richValue(target(module, "shadow")));
    const floating = try session.evidence.intern(.function, types.f32_type, types.f32_type, &.{});
    try std.testing.expectEqual(floating, session.valueEvidence(shadow));
    const wrong = try session.evidence.intern(.function, types.unit, types.f32_type, &.{});
    if (session.specializeClosure(grid_raw, wrong)) |_| return error.TestUnexpectedResult else |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.RequestUnwind => return error.TestUnexpectedResult,
        error.Declined => try std.testing.expectEqual(evaluator.Code.type_mismatch, session.diagnostic.?.code),
    }
    session.diagnostic = null;
    const unbound = try session.richValue(target(module, "unbound"));
    const before_decline = session.steps;
    if (session.inferClosure(unbound)) |_| return error.TestUnexpectedResult else |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.RequestUnwind => return error.TestUnexpectedResult,
        error.Declined => try std.testing.expectEqual(evaluator.Code.unsupported, session.diagnostic.?.code),
    }
    try std.testing.expectEqual(before_decline, session.steps);
    session.diagnostic = null;
    try std.testing.expectEqual(@as(u32, 81), (try session.value(target(module, "answer"))).bits);
    try std.testing.expectEqual(@as(u32, @bitCast(@as(f32, 6.25))), (try session.value(target(module, "float_answer"))).bits);
}

test "retained callable proof reads exact cached scalar globals without evaluating or defaulting generic owners" {
    var module = try lowerWithOptions("infixl 70 (*) = mul\n" ++ contextual_result_prelude ++ "\n" ++
        \\const mul = fn left => fn right => @type.call "mul" left right
        \\const U32.mul = fn left => fn right => @u32.mul left right
        \\const F32.mul = fn left => fn right => @f32.mul left right
        \\entry const column_count = from (ceil (sqrt (from count))) + 2
        \\entry const grid = fn () => column_count * column_count
        \\entry const shadow = fn (column_count: F32) => column_count * column_count
        \\entry const unbound = fn value => @u32.add (value * value) 1
        \\entry const answer = grid ()
        \\entry const float_answer = shadow 2.5
    , .{ .builtin_catalog = true });
    defer module.deinit(a);
    const frozen_nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(frozen_nodes);
    const frozen_types = try a.dupe(types.Node, module.types.nodes);
    defer a.free(frozen_types);
    const frozen_rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
    defer a.free(frozen_rows);
    try cachedScalarReferenceScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, cachedScalarReferenceScenario, .{&module});
    try std.testing.expectEqualDeep(frozen_nodes, module.nodes);
    try std.testing.expectEqualDeep(frozen_types, module.types.nodes);
    try std.testing.expectEqualDeep(frozen_rows, module.types.effects.rows);
}

const closed_data_alias_source =
    "infixl 70 (/) = divide\n" ++ contextual_result_prelude ++ "\n" ++
    \\const divide = fn left => fn right => @type.call "div" left right
    \\const F32.div = fn left => fn right => @f32.div left right
    \\const U32.div = fn left => fn right => @u32.div left right
    \\const scaled = fn (value: U32) => from value / 65536.0
    \\entry const place = fn (index: U32) => do:
    \\  let x = scaled index + 0.5
    \\  return (x, x, index)
    \\const generate = fn count => fn make => @array.generate count make
    \\entry const run = fn (count: U32) -> Bool => do:
    \\  let positions = generate count place
    \\  let flags = generate count (fn index => do:
    \\    let (x, y, _) = positions[index]
    \\    return @f32.eq (@f32.add x y) 1.0)
    \\  return flags[0]
    \\entry const wrong = fn (index: U32) -> U32 => do:
    \\  let x = scaled index + 0.5
    \\  return @u32.add x 1
    \\type Box a is data = #Box {x: a}
    \\entry const wrapped = fn (index: U32) => do:
    \\  let x = scaled index + 0.5
    \\  let box: Box F32 = #Box {x: x}
    \\  let items = #[box]
    \\  return (items, items)
    \\entry const independent = fn () => do:
    \\  let identity = fn value => value
    \\  return (identity 41, identity 1.5)
    \\entry const answer = run 2
    ;

fn closedDataAliasScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const tuple = try session.evidence.intern(.product, 0, 0, &.{ types.f32_type, types.f32_type, types.u32_type });
    const signature = try session.evidence.intern(.function, types.u32_type, tuple, &.{});
    const raw = try session.richValue(target(module, "place"));
    const original = session.valueEvidence(raw);
    const before = session.steps;
    const selected = try session.inferClosure(raw);
    try std.testing.expectEqual(signature, session.valueEvidence(selected));
    try std.testing.expectEqual(original, session.valueEvidence(raw));
    try std.testing.expectEqual(before, session.steps);
    const wrapped = try session.inferClosure(try session.richValue(target(module, "wrapped")));
    const wrapped_root = session.evidence.node(session.valueEvidence(wrapped));
    try std.testing.expectEqual(type_evidence.Tag.function, wrapped_root.tag);
    try std.testing.expectEqual(types.u32_type, wrapped_root.a);
    const children = session.evidence.children(wrapped_root.b);
    try std.testing.expectEqual(@as(usize, 2), children.len);
    try std.testing.expectEqual(children[0], children[1]);
    const element = session.evidence.node(session.evidence.node(children[0]).a);
    try std.testing.expectEqual(type_evidence.Tag.nominal, element.tag);
    try std.testing.expectEqualSlices(type_evidence.Id, &.{types.f32_type}, session.evidence.children(session.evidence.node(children[0]).a));
    const mixed = try session.evidence.intern(.product, 0, 0, &.{ types.u32_type, types.f32_type });
    const independent_signature = try session.evidence.intern(.function, types.unit, mixed, &.{});
    var independent = try session.bodyEvidenceFull(target(module, "independent"), independent_signature, &.{}, &.{});
    defer independent.deinit(allocator);
    const wrong = try session.evidence.intern(.function, types.u32_type, types.u32_type, &.{});
    if (session.bodyEvidenceFull(target(module, "wrong"), wrong, &.{}, &.{})) |invalid| {
        var owned = invalid;
        owned.deinit(allocator);
        return error.TestUnexpectedResult;
    } else |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.RequestUnwind => return error.TestUnexpectedResult,
        error.Declined => try std.testing.expectEqual(evaluator.Code.type_mismatch, session.diagnostic.?.code),
    }
    session.diagnostic = null;
}

test "selected closed local data retains scalar and captured aggregate types while callable instances stay independent" {
    var module = try lowerWithOptions(closed_data_alias_source, .{ .builtin_catalog = true });
    defer module.deinit(a);
    const frozen_nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(frozen_nodes);
    const frozen_types = try a.dupe(types.Node, module.types.nodes);
    defer a.free(frozen_types);
    const frozen_rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
    defer a.free(frozen_rows);
    try closedDataAliasScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, closedDataAliasScenario, .{&module});
    try std.testing.expectEqualDeep(frozen_nodes, module.nodes);
    try std.testing.expectEqualDeep(frozen_types, module.types.nodes);
    try std.testing.expectEqualDeep(frozen_rows, module.types.effects.rows);
}

const partial_data_alias_source =
    "infixl 70 (/) = divide\n" ++ contextual_result_prelude ++ "\n" ++
    \\const divide = fn left => fn right => @type.call "div" left right
    \\const F32.div = fn left => fn right => @f32.div left right
    \\const U32.div = fn left => fn right => @u32.div left right
    \\const scaled = fn (value: U32) => from value / 65536.0
    \\entry const mixed = fn (index: U32) -> F32 => do:
    \\  let pair = (scaled index + 0.5, fn value => value)
    \\  let (x, identity) = pair
    \\  let first = identity 41
    \\  return @f32.add x (@u32.to_f32 first)
    \\entry const wrong = fn (index: U32) -> U32 => do:
    \\  let pair = (scaled index + 0.5, fn value => value)
    \\  let (value, identity) = pair
    \\  let first = identity 41
    \\  return @u32.add value first
    ;

fn partialDataAliasScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const signature = try session.evidence.intern(.function, types.u32_type, types.f32_type, &.{});
    var proof = try session.bodyEvidenceFull(target(module, "mixed"), signature, &.{}, &.{});
    defer proof.deinit(allocator);
    const start = std.mem.find(u8, partial_data_alias_source, "x, identity").?;
    var checked = false;
    for (module.bindings) |binding| {
        if (binding.span.start != start) continue;
        try std.testing.expectEqual(types.f32_type, try session.evidence.projectWithRows(&module.types, binding.ty, proof.types, proof.rows));
        checked = true;
    }
    try std.testing.expect(checked);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
    const wrong = try session.evidence.intern(.function, types.u32_type, types.u32_type, &.{});
    if (session.bodyEvidenceFull(target(module, "wrong"), wrong, &.{}, &.{})) |invalid| {
        var owned = invalid;
        owned.deinit(allocator);
        return error.TestUnexpectedResult;
    } else |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.RequestUnwind => return error.TestUnexpectedResult,
        error.Declined => try std.testing.expectEqual(evaluator.Code.type_mismatch, session.diagnostic.?.code),
    }
}

test "selected data components cross local aggregate aliases without merging generic callable components" {
    var module = try lowerWithOptions(partial_data_alias_source, .{ .builtin_catalog = true });
    defer module.deinit(a);
    const frozen_nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(frozen_nodes);
    const frozen_types = try a.dupe(types.Node, module.types.nodes);
    defer a.free(frozen_types);
    const frozen_rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
    defer a.free(frozen_rows);
    try partialDataAliasScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, partialDataAliasScenario, .{&module});
    try std.testing.expectEqualDeep(frozen_nodes, module.nodes);
    try std.testing.expectEqualDeep(frozen_types, module.types.nodes);
    try std.testing.expectEqualDeep(frozen_rows, module.types.effects.rows);
}

fn wideEvidenceModule() !core.Module {
    const source = "entry const wide = fn value => value\n";
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    var checked = try checker.check(a, &syntax, &pool);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const store = &checked.types;
    var children: [40]types.Id = undefined;
    for (&children, 0..) |*child, index| child.* = if (index % 2 == 0) types.u32_type else types.f32_type;
    const product = try store.product(&children);
    const nominal = try store.nominal(.{ .unit = 11, .decl = 29 }, &children);
    var fields: [20]types.Field = undefined;
    for (&fields, 0..) |*field, index| {
        var buffer: [32]u8 = undefined;
        const name = try pool.intern(a, try std.mem.print(&buffer, "field_{d:0>2}", .{index}));
        field.* = .{ .name = name, .ty = switch (index) {
            0 => try store.array(product),
            1 => nominal,
            else => if (index % 2 == 0) types.u32_type else types.f32_type,
        } };
    }
    const record = try store.record(&fields);
    const read = try store.nominal(.{ .unit = 17, .decl = 23 }, &.{record});
    const label = try store.internOperation(.{ .unit = 19, .decl = 31 }, &children);
    const row = try store.effects.row(&(@as([33]u32, @splat(label))), .closed);
    const provider = try store.provider(read, row);
    const signature = try store.functionWithEffects(provider, provider, row);
    const declaration = syntax.roots.items[0];
    const binding = checked.resolved[declaration];
    const lambda_source = syntax.valueDecl(declaration).body;
    const lambda = syntax.node(lambda_source);
    checked.bindings[binding].ty = signature;
    checked.bindings[binding].scheme.root = signature;
    checked.expr_types[lambda_source] = signature;
    checked.expr_types[lambda.a] = provider;
    checked.expr_types[lambda.b] = provider;
    const parameter = checked.resolved[lambda.a];
    checked.bindings[parameter].ty = provider;
    checked.bindings[parameter].scheme.root = provider;
    var module = try core.lower(a, &syntax, &pool, &checked);
    errdefer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
fn wideEvidenceScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const reference = target(module, "wide");
    const root = module.binding(reference.binding).ty;
    const concrete = try session.evidence.project(&module.types, root, &.{});
    var exact = try session.bodyEvidenceFull(reference, concrete, &.{}, &.{});
    defer exact.deinit(allocator);
    try std.testing.expectEqual(concrete, try session.evidence.projectWithRows(&module.types, root, exact.types, exact.rows));
    const effects = session.evidence.view().effects;
    const labels = effects.rowLabels(session.evidence.node(concrete).c);
    try std.testing.expectEqual(@as(usize, 33), labels.len);
    for (labels) |label| try std.testing.expectEqual(labels[0], label);
    const arguments = effects.operationArguments(labels[0]);
    try std.testing.expectEqual(@as(usize, 40), arguments.len);
    for (arguments, 0..) |argument, index| try std.testing.expectEqual(if (index % 2 == 0) types.u32_type else types.f32_type, argument);
    var expected = try code_expectation.Store.init(allocator);
    defer expected.deinit();
    var children: [40]u32 = undefined;
    for (&children, 0..) |*child, index| child.* = if (index % 2 == 0) types.u32_type else types.f32_type;
    const product = try expected.intern(.product, 0, 0, &children);
    const array = try expected.intern(.array, product, 0, &.{});
    const nominal = try expected.intern(.nominal, 11, 29, &children);
    const source_provider = module.types.node(module.types.node(root).a);
    const source_read = module.types.node(source_provider.a);
    const source_record = module.types.node(module.types.nominalArguments(source_read)[0]);
    var fields: [40]u32 = undefined;
    for (0..20) |index| {
        fields[index * 2] = module.types.recordField(source_record, index).name;
        fields[index * 2 + 1] = switch (index) {
            0 => array,
            1 => nominal,
            else => if (index % 2 == 0) types.u32_type else types.f32_type,
        };
    }
    const record = try expected.intern(.record, 0, 0, &fields);
    const read = try expected.intern(.nominal, 17, 23, &.{record});
    const provider = try expected.intern(.provider, read, 0, &.{});
    const shape = try expected.intern(.function, provider, provider, &.{});
    var partial = try session.bodyEvidencePartialFull(reference, expected.view(), shape, &.{}, &.{});
    defer partial.deinit(allocator);
    try std.testing.expectEqual(concrete, try session.evidence.projectWithRows(&module.types, root, partial.types, partial.rows));
    children[39] = types.u32_type;
    const wrong_label = try session.evidence.effects.internOperation(.{ .unit = 19, .decl = 31 }, &children);
    const wrong_row = try session.evidence.effects.internRow(&(@as([33]u32, @splat(wrong_label))));
    const header = session.evidence.node(concrete);
    const wrong = try session.evidence.internWithEffects(.function, header.a, header.b, wrong_row, &.{});
    if (session.bodyEvidenceFull(reference, wrong, &.{}, &.{})) |proof| {
        var unexpected = proof;
        unexpected.deinit(allocator);
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.Declined => try std.testing.expectEqual(evaluator.Code.effect_mismatch, session.diagnostic.?.code),
        else => return err,
    }
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}
test "wide nested evidence preserves operation arguments and row multiplicity through owned imports" {
    var module = try wideEvidenceModule();
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const type_nodes = try a.dupe(types.Node, module.types.nodes);
    defer a.free(type_nodes);
    const extra = try a.dupe(types.Id, module.types.extra);
    defer a.free(extra);
    const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
    defer a.free(rows);
    const labels = try a.dupe(u32, module.types.effects.labels);
    defer a.free(labels);
    try wideEvidenceScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, wideEvidenceScenario, .{&module});
    try std.testing.expectEqualSlices(core.Node, nodes, module.nodes);
    try std.testing.expectEqualSlices(types.Node, type_nodes, module.types.nodes);
    try std.testing.expectEqualSlices(types.Id, extra, module.types.extra);
    try std.testing.expectEqualSlices(types.Effects.Row, rows, module.types.effects.rows);
    try std.testing.expectEqualSlices(u32, labels, module.types.effects.labels);
}

const partial_array_methods =
    \\const Array.length = fn values => @array.length values
    \\const F32.from = fn value => @u32.to_f32 value
    \\const Array.convert = fn values => @type.result "from" (@array.length values)
    \\const map = fn transform => fn values => @array.generate (@array.length values) (fn index => transform (@array.get values index))
    \\const lengths = map .length #[#[], #[]]
    \\entry const answer = @u32.add (@array.get lengths 0) (@array.get lengths 1)
    \\entry const floating: F32 = #[].convert
    \\entry const nested: F32 = #[#[], #[]].convert
    \\entry const concrete: F32 = #[1, 2].convert
    \\entry const untyped = #[].convert
;

fn partialArrayScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    for ([_]bool{ true, false }) |reuse| {
        var session = try evaluator.Session.init(allocator, &.{module.*});
        defer session.deinit();
        session.options.reuse_body_recipes = reuse;
        try std.testing.expectEqual(scalar_ops.Value{ .scalar = .u32, .bits = 0 }, try session.value(target(module, "answer")));
        try std.testing.expectEqual(scalar_ops.Value{ .scalar = .f32, .bits = @bitCast(@as(f32, 0)) }, try session.value(target(module, "floating")));
        try std.testing.expectEqual(scalar_ops.Value{ .scalar = .f32, .bits = @bitCast(@as(f32, 2)) }, try session.value(target(module, "nested")));
        try std.testing.expectEqual(scalar_ops.Value{ .scalar = .f32, .bits = @bitCast(@as(f32, 2)) }, try session.value(target(module, "concrete")));
        try std.testing.expect(session.diagnostic == null);
        _ = session.value(target(module, "untyped")) catch |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expectEqual(error.Declined, err);
            try std.testing.expectEqual(evaluator.Code.ambiguous_associated, session.diagnostic.?.code);
            continue;
        };
        return error.ExpectedAmbiguousDestination;
    }
}

test "partial empty-array members preserve shape independent result evidence and immutable source through every allocation failure" {
    // This module models an explicit prelude producer. Source-facing oracles
    // use the real source prelude and its registered Array method family.
    var module = try lowerWithOptions(partial_array_methods, .{ .builtin_catalog = true });
    defer module.deinit(a);
    const inputs = .{ module.nodes, module.extra, module.bindings, module.closures, module.projections, module.types.nodes, module.types.extra, module.types.effects.rows, module.types.effects.labels, module.types.operations };
    var saved: @TypeOf(inputs) = undefined;
    var copied: usize = 0;
    defer inline for (0..inputs.len) |index| {
        if (index < copied) a.free(saved[index]);
    };
    inline for (inputs, 0..) |items, index| {
        saved[index] = try a.dupe(std.meta.Child(@TypeOf(items)), items);
        copied += 1;
    }
    try partialArrayScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, partialArrayScenario, .{&module});
    inline for (inputs, 0..) |items, index| try std.testing.expectEqualDeep(saved[index], items);
}

fn indexedRegionOwnership(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    try std.testing.expectEqual(@as(u32, 49), (try session.value(target(module, "answer"))).bits);
    try std.testing.expect(session.indexed_region == null);
}
test "private nested indexed regions preserve source aliases and clean up every failed allocation" {
    var module = try lower(
        \\const original = @array.fill 8 7
        \\const updated = do:
        \\  let values = original
        \\  let offset = 0
        \\  for outer in 0..4:
        \\    for inner in 0..2:
        \\      values[@u32.add offset inner] := 42
        \\    offset := @u32.add offset 2
        \\  return values
        \\entry const answer = @u32.add original[7] updated[7]
    );
    defer module.deinit(a);
    try indexedRegionOwnership(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, indexedRegionOwnership, .{&module});
}

fn parametricCallbackScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for ([_][]const u8{ "integer", "floating", "answer" }, [_]types.Id{ types.u32_type, types.f32_type, types.u32_type }) |name, scalar| {
        const original = try session.richValue(target(module, name));
        const expected = try session.evidence.intern(.function, scalar, scalar, &.{});
        const prior = session.valueEvidence(original);
        const steps = session.steps;
        const selected = try session.specializeClosure(original, expected);
        try std.testing.expectEqual(expected, session.valueEvidence(selected));
        try std.testing.expectEqual(prior, session.valueEvidence(original));
        try std.testing.expectEqual(steps, session.steps);
    }
    // A parametric callback row remains the caller's obligation; its concrete
    // use cannot be silently admitted as a pure function.
    const reading = try session.richValue(target(module, "reading"));
    const pure = try session.evidence.intern(.function, types.unit, types.u32_type, &.{});
    try expectCaptureMismatch(&session, reading, pure);
}

test "obligation-free higher-order schemes preserve captures independent instances and callback effects" {
    var module = try lower(
        \\effect Read: Unit -> U32
        \\const apply = fn callback => fn value => callback value
        \\const compose = fn outer => fn inner => fn value => outer (inner value)
        \\const plus = fn amount => fn value => @u32.add amount value
        \\entry const integer = fn (value: U32) => apply (compose (plus 2) (plus 3)) value
        \\entry const floating = fn (value: F32) => apply (fn item => @f32.add item 0.5) value
        \\entry const reading = fn () => apply (fn () => Read ()) ()
        \\entry const answer = fn (value: U32) => do @effect.provider Read (fn () => value):
        \\  use result <- reading ()
        \\  return @u32.add result 5
    );
    defer module.deinit(a);
    try parametricCallbackScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, parametricCallbackScenario, .{&module});
}

const lexical_inputs = @import("lexical_capture_inputs.zig");

fn lexicalScalarScenario(allocator: std.mem.Allocator, module: *const core.Module, anonymous: bool) !void {
    var summarized = try evaluator.Session.init(allocator, &.{module.*});
    defer summarized.deinit();
    var ordinary = try evaluator.Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    ordinary.options.reuse_lexical_summaries = false;
    // Isolate lexical job reuse; canonical proof reuse has its own region laws.
    summarized.canonical_specializations.enabled = false;
    var keys: lexical_inputs.Cache = .{};
    defer keys.deinit(allocator);
    const selected: lexical_inputs.Interfaces = .empty;
    var identifiers: [3]u32 = undefined;
    for ([_][]const u8{ "first", "again", "other" }, 0..) |name, index| {
        const value = try summarized.richValue(target(module, name));
        const reference = try ordinary.richValue(target(module, name));
        const before = summarized.steps;
        const ready = try summarized.inferEntryClosure(value) orelse return error.ExpectedConcreteLexicalInterface;
        const expected = try ordinary.inferClosure(reference);
        try std.testing.expectEqual(before, summarized.steps);
        const scopes = summarized.counters.region_scopes;
        const complete = try summarized.inferClosure(value);
        try std.testing.expect(summarized.counters.region_scopes > scopes);
        try std.testing.expectEqual(summarized.valueEvidence(ready), summarized.valueEvidence(complete));
        try std.testing.expectEqual(before, summarized.steps);
        const actual_arrow = summarized.evidence.node(summarized.valueEvidence(ready));
        const expected_arrow = ordinary.evidence.node(ordinary.valueEvidence(expected));
        try std.testing.expectEqual(type_evidence.Tag.function, actual_arrow.tag);
        try std.testing.expectEqual(types.u32_type, actual_arrow.a);
        try std.testing.expectEqual(types.u32_type, actual_arrow.b);
        try std.testing.expectEqual(expected_arrow.c, actual_arrow.c);
        identifiers[index] = try keys.intern(allocator, &summarized, ready, &selected) orelse return error.ExpectedCompleteCaptureInputs;
        try std.testing.expectEqual(anonymous, keys.inputs.items[identifiers[index] - 1].anonymous);
        try std.testing.expectEqual(@as(usize, 1), keys.inputs.items[identifiers[index] - 1].slots.len);
        try std.testing.expectEqual(@as(u32, if (index == 2) 2 else 1), summarized.valueInfo(summarized.valueChildren(ready)[0]).bits);
    }
    try std.testing.expectEqual(identifiers[0], identifiers[1]);
    try std.testing.expect(identifiers[0] != identifiers[2]);
    try std.testing.expect(keys.reused != 0);
    try std.testing.expect(summarized.lexical_inputs.requests != 0);
    try std.testing.expect(summarized.lexical_inputs.reused != 0);
    var complete_jobs: usize = 0;
    for (summarized.call_summaries.jobs.items) |job| if (job.key.lexical != 0 and job.state == .complete) {
        complete_jobs += 1;
    };
    try std.testing.expect(complete_jobs != 0);
    try std.testing.expectEqual(@as(usize, 0), ordinary.lexical_inputs.requests);
    const values_before = summarized.values.items.len;
    const key_count = keys.inputs.items.len;
    const original_limit = summarized.options.max_type_depth;
    summarized.options.max_type_depth = 0;
    const first = try summarized.richValue(target(module, "first"));
    try std.testing.expectEqual(@as(?u32, null), try keys.intern(allocator, &summarized, first, &selected));
    summarized.options.max_type_depth = original_limit;
    try std.testing.expectEqual(key_count, keys.inputs.items.len);
    try std.testing.expectEqual(values_before, summarized.values.items.len);
    var bounded: lexical_inputs.Cache = .{};
    defer bounded.deinit(allocator);
    const original_edges = summarized.options.max_children;
    const ready = try summarized.inferClosure(first);
    summarized.options.max_children = keys.inputs.items[identifiers[0] - 1].words.len;
    _ = try bounded.intern(allocator, &summarized, ready, &selected) orelse return error.ExpectedCompleteCaptureInputs;
    try std.testing.expectEqual(@as(?u32, null), try bounded.intern(allocator, &summarized, ready, &selected));
    try std.testing.expect(bounded.retained_words <= summarized.options.max_children);
    try std.testing.expect(bounded.examined_words <= summarized.options.max_children);
    try std.testing.expectEqual(@as(usize, 1), bounded.inputs.items.len);
    summarized.options.max_children = original_edges;
    try std.testing.expectEqual(@as(u32, 83), (try summarized.value(target(module, "answer"))).bits);
    try std.testing.expectEqual(@as(u32, 83), (try ordinary.value(target(module, "answer"))).bits);
}

test "lexical summaries own all scalar captures and keep different values separate through allocation failure" {
    var module = try lower(
        \\const make: U32 -> (U32 -> U32 ! {}) = fn captured => fn value => @u32.add captured value
        \\entry const first = make 1
        \\entry const again = make 1
        \\entry const other = make 2
        \\entry const answer = @u32.add (first 40) (other 40)
    );
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const bindings = try a.dupe(core.Binding, module.bindings);
    defer a.free(bindings);
    const type_nodes = try a.dupe(types.Node, module.types.nodes);
    defer a.free(type_nodes);
    try lexicalScalarScenario(a, &module, false);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lexicalScalarScenario, .{ &module, false });
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualDeep(bindings, module.bindings);
    try std.testing.expectEqualDeep(type_nodes, module.types.nodes);
}

test "anonymous lexical jobs preserve complete inference mode and repeated capture interfaces" {
    var module = try lower(
        \\const make = fn (captured: U32) => do:
        \\  return fn (value: U32) => @u32.add captured value
        \\entry const first = make 1
        \\entry const again = make 1
        \\entry const other = make 2
        \\entry const answer = @u32.add (first 40) (other 40)
    );
    defer module.deinit(a);
    try lexicalScalarScenario(a, &module, true);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lexicalScalarScenario, .{ &module, true });
}

fn lexicalAliasScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    var keys: lexical_inputs.Cache = .{};
    defer keys.deinit(allocator);
    const selected: lexical_inputs.Interfaces = .empty;
    var identifiers: [2]u32 = undefined;
    for ([_][]const u8{ "shared", "separate" }, 0..) |name, index| {
        const value = try session.richValue(target(module, name));
        const steps = session.steps;
        const ready = try session.inferClosure(value);
        try std.testing.expectEqual(steps, session.steps);
        const children = session.valueChildren(ready);
        try std.testing.expectEqual(@as(usize, 2), children.len);
        try std.testing.expectEqual(index == 0, children[0] == children[1]);
        identifiers[index] = try keys.intern(allocator, &session, ready, &selected) orelse return error.ExpectedCompleteCaptureInputs;
        const slots = keys.inputs.items[identifiers[index] - 1].slots;
        try std.testing.expectEqual(@as(usize, 2), slots.len);
        try std.testing.expectEqual(index == 0, slots[0].alias == slots[1].alias);
        try std.testing.expectEqual(slots[0].interface, slots[1].interface);
    }
    try std.testing.expect(identifiers[0] != identifiers[1]);
    try std.testing.expectEqual(@as(u32, 80), (try session.value(target(module, "answer"))).bits);
}

test "lexical summary inputs preserve shared aggregate slots instead of merging equal separate captures" {
    var module = try lower(
        \\type Box is data = #Box { value: U32 }
        \\const make = fn left => fn right => fn () => @u32.add left.value right.value
        \\const box = #Box { value: 20 }
        \\entry const shared = make box box
        \\entry const separate = make (#Box { value: 20 }) (#Box { value: 20 })
        \\entry const answer = @u32.add (shared ()) (separate ())
    );
    defer module.deinit(a);
    try lexicalAliasScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lexicalAliasScenario, .{&module});
}

fn lexicalDemandScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    var keys: lexical_inputs.Cache = .{};
    defer keys.deinit(allocator);
    const selected: lexical_inputs.Interfaces = .empty;
    var identifiers: [2]u32 = undefined;
    var captures: [2]evaluator.ValueId = undefined;
    for ([_][]const u8{ "first", "other" }, 0..) |name, index| {
        const value = try session.richValue(target(module, name));
        const steps = session.steps;
        const ready = try session.inferClosure(value);
        try std.testing.expectEqual(steps, session.steps);
        captures[index] = session.valueChildren(ready)[0];
        try std.testing.expectEqual(evaluator.ValueKind.suspension, session.valueInfo(captures[index]).kind);
        try std.testing.expect(session.suspensionCached(captures[index]) == null);
        const examined = session.canonical_specializations.examined_words;
        try std.testing.expectEqual(@as(?lexical_inputs.Inputs, null), try session.canonical_specializations.key(&session, ready));
        try std.testing.expect(session.canonical_specializations.examined_words > examined);
        identifiers[index] = try keys.intern(allocator, &session, ready, &selected) orelse return error.ExpectedCompleteCaptureInputs;
    }
    try std.testing.expect(identifiers[0] != identifiers[1]);
    try std.testing.expect(captures[0] != captures[1]);
    try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "answer"))).bits);
    try std.testing.expect(session.suspensionCached(captures[0]) != null);
    const value = try session.inferClosure(try session.richValue(target(module, "first")));
    try std.testing.expectEqual(@as(?u32, null), try keys.intern(allocator, &session, value, &selected));
    try std.testing.expectEqual(@as(usize, 2), keys.inputs.items.len);
}

test "lexical keys distinguish pending demand creation and decline changed cached memo state" {
    var module = try lower(
        \\const make = fn ~(value: U32) => fn () => @force value
        \\entry const first = make (@u32.add 40 2)
        \\entry const other = make (@u32.add 40 2)
        \\entry const answer = first ()
    );
    defer module.deinit(a);
    try lexicalDemandScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lexicalDemandScenario, .{&module});
}

fn lexicalProviderScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    var keys: lexical_inputs.Cache = .{};
    defer keys.deinit(allocator);
    var selected: lexical_inputs.Interfaces = .empty;
    defer selected.deinit(allocator);
    var identifiers: [2]u32 = undefined;
    for ([_][]const u8{ "first", "other" }, 0..) |name, index| {
        const value = try session.richValue(target(module, name));
        const provider = session.valueChildren(value)[0];
        const implementation = session.valueChildren(provider)[0];
        const steps = session.steps;
        const ready = try session.inferClosure(implementation);
        try std.testing.expectEqual(steps, session.steps);
        try std.testing.expectEqual(evaluator.ValueKind.provider, session.valueInfo(provider).kind);
        const implemented = session.valueEvidence(ready);
        const signature = session.evidence.node(implemented);
        const operation = session.evidence.node(@intCast(session.valueInfo(provider).nominal));
        try std.testing.expectEqual(operation.a, signature.a);
        try std.testing.expectEqual(operation.b, signature.b);
        // This input-builder law supplies a complete checked producer
        // interface. Untyped runtime providers keep ordinary checking.
        var token: type_evidence.Id = 0;
        for (module.nodes) |node| if (node.tag == .effect_provider) {
            token = try session.evidence.project(&module.types, module.types.node(node.ty).a, &.{});
            break;
        };
        try std.testing.expect(token != 0);
        const provider_type = try session.evidence.internWithEffects(.provider, token, 0, signature.c, &.{});
        try selected.put(allocator, provider, provider_type);
        try selected.put(allocator, implementation, implemented);
        identifiers[index] = try keys.intern(allocator, &session, value, &selected) orelse return error.ExpectedCompleteCaptureInputs;
    }
    // Even equal-shaped installations have separate creation identities. A
    // result for one provider cannot certify another installation's capture.
    try std.testing.expect(identifiers[0] != identifiers[1]);
    try std.testing.expectEqual(@as(u32, 84), (try session.value(target(module, "answer"))).bits);
}

test "lexical summary inputs retain provider creation identity and complete implementation rows" {
    var module = try lower(
        \\effect Tick: Unit -> U32
        \\const implementation: Unit -> U32 ! {} = fn () => 42
        \\const make = fn (ignored: U32) => do:
        \\  let provider = @effect.provider Tick implementation
        \\  return fn () => do provider:
        \\    use result <- Tick ()
        \\    return result
        \\entry const first = make 1
        \\entry const other = make 2
        \\entry const answer = @u32.add (first ()) (other ())
    );
    defer module.deinit(a);
    try lexicalProviderScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lexicalProviderScenario, .{&module});
}

fn lexicalNestedScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    var keys: lexical_inputs.Cache = .{};
    defer keys.deinit(allocator);
    const selected: lexical_inputs.Interfaces = .empty;
    var identifiers: [2]u32 = undefined;
    for ([_][]const u8{ "first", "other" }, 0..) |name, index| {
        const value = try session.richValue(target(module, name));
        const steps = session.steps;
        const ready = try session.inferClosure(value);
        try std.testing.expectEqual(steps, session.steps);
        const callback = session.valueChildren(ready)[0];
        try std.testing.expectEqual(evaluator.ValueKind.closure, session.valueInfo(callback).kind);
        try std.testing.expect(session.valueEvidence(callback) != 0);
        try std.testing.expectEqual(@as(usize, 1), session.valueChildren(callback).len);
        identifiers[index] = try keys.intern(allocator, &session, ready, &selected) orelse return error.ExpectedCompleteCaptureInputs;
    }
    try std.testing.expect(identifiers[0] != identifiers[1]);
    try std.testing.expectEqual(@as(u32, 83), (try session.value(target(module, "answer"))).bits);
}

test "lexical summary inputs include nested callback captures without executing the callback" {
    var module = try lower(
        \\const plus: U32 -> (U32 -> U32 ! {}) = fn amount => fn value => @u32.add amount value
        \\const make: (U32 -> U32 ! {}) -> (U32 -> U32 ! {}) = fn callback => fn value => callback value
        \\entry const first = make (plus 1)
        \\entry const other = make (plus 2)
        \\entry const answer = @u32.add (first 40) (other 40)
    );
    defer module.deinit(a);
    try lexicalNestedScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lexicalNestedScenario, .{&module});
}

fn lexicalRetryScenario(module: *const core.Module, offset: ?usize) !usize {
    var failing = std.testing.FailingAllocator.init(a, .{});
    var allocations: usize = 0;
    {
        var session = try evaluator.Session.init(failing.allocator(), &.{module.*});
        defer session.deinit();
        const value = try session.richValue(target(module, "first"));
        const steps = session.steps;
        const start = failing.alloc_index;
        if (offset) |index| failing.fail_index = start + index;
        const ready = session.inferEntryClosure(value) catch |err| retry: {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expect(failing.has_induced_failure);
            try std.testing.expectEqual(@as(usize, 0), session.call_summaries.stack.items.len);
            try std.testing.expectEqual(@as(u32, 0), session.call_summaries.active.count());
            try std.testing.expectEqual(@as(u32, 0), session.call_summaries.active_lexical.count());
            for (session.call_summaries.jobs.items) |job| {
                try std.testing.expect(job.state == .complete or job.state == .declined);
                try std.testing.expect(job.region == null);
            }
            failing.fail_index = std.math.maxInt(usize);
            break :retry try session.inferEntryClosure(value);
        };
        allocations = failing.alloc_index - start;
        const selected = ready orelse return error.ExpectedConcreteLexicalInterface;
        const arrow = session.evidence.node(session.valueEvidence(selected));
        try std.testing.expectEqual(type_evidence.Tag.function, arrow.tag);
        try std.testing.expectEqual(types.u32_type, arrow.a);
        try std.testing.expectEqual(types.u32_type, arrow.b);
        try std.testing.expectEqual(@as(u32, 0), arrow.c);
        try std.testing.expectEqual(steps, session.steps);
        try std.testing.expectEqual(@as(u32, 42), (try session.value(target(module, "answer"))).bits);
    }
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    return allocations;
}

test "lexical summary allocation failures abandon partial jobs and retry in the same session" {
    var module = try lower(
        \\const make: U32 -> (U32 -> U32 ! {}) = fn captured => fn value => @u32.add captured value
        \\entry const first = make 1
        \\entry const answer = first 41
    );
    defer module.deinit(a);
    const allocations = try lexicalRetryScenario(&module, null);
    for (0..allocations) |offset| _ = try lexicalRetryScenario(&module, offset);
}

fn canonicalScalarScenario(allocator: std.mem.Allocator, module: *const core.Module, collision: bool) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    session.canonical_specializations.force_collision = collision;
    session.options.trace_runtime_dependencies = true;
    session.options.retain_source_suspensions = true;
    const expected = try session.evidence.intern(.function, types.u32_type, types.u32_type, &.{});
    const first = try session.richValue(target(module, "first"));
    _ = try session.specializeClosure(first, expected);
    const again = try session.richValue(target(module, "again"));
    const capture = session.valueChildren(again)[0];
    try std.testing.expect(capture != session.valueChildren(first)[0]);
    const regions = session.counters.inference_regions;
    const steps = session.steps;
    const selected = try session.specializeClosure(again, expected);
    try std.testing.expectEqual(regions, session.counters.inference_regions);
    try std.testing.expectEqual(steps, session.steps);
    try std.testing.expectEqual(capture, session.valueChildren(selected)[0]);
    try std.testing.expectEqual(@as(usize, 1), session.canonical_specializations.reused);
    const other = try session.richValue(target(module, "other"));
    const before_other = session.counters.inference_regions;
    const different = try session.specializeClosure(other, expected);
    try std.testing.expect(session.counters.inference_regions > before_other);
    try std.testing.expectEqual(@as(u32, 2), session.valueInfo(session.valueChildren(different)[0]).bits);
    try std.testing.expectEqual(@as(usize, 1), session.canonical_specializations.reused);
    try std.testing.expectEqual(@as(u32, 83), (try session.value(target(module, "answer"))).bits);
}

test "canonical selected proofs use current captures and exact equality under forced collisions" {
    var module = try lower(
        \\const make: U32 -> (U32 -> U32 ! {}) = fn captured => fn value => @u32.add captured value
        \\entry const first = make 1
        \\entry const again = make 1
        \\entry const other = make 2
        \\entry const answer = @u32.add (first 40) (other 40)
    );
    defer module.deinit(a);
    try canonicalScalarScenario(a, &module, false);
    try canonicalScalarScenario(a, &module, true);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, canonicalScalarScenario, .{ &module, true });
}

test "canonical inference proofs distinguish selected and entry modes with current capture graphs" {
    var module = try lower(
        \\const make: U32 -> (U32 -> U32 ! {}) = fn captured => fn value => @u32.add captured value
        \\entry const first = make 1
        \\entry const again = make 1
    );
    defer module.deinit(a);
    for ([_]bool{ false, true }) |entry_mode| {
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        const first = try session.richValue(target(&module, "first"));
        _ = if (entry_mode) (try session.inferEntryClosure(first)).? else try session.inferClosure(first);
        const again = try session.richValue(target(&module, "again"));
        const before = session.counters.inference_regions;
        const selected = if (entry_mode) (try session.inferEntryClosure(again)).? else try session.inferClosure(again);
        try std.testing.expectEqual(before, session.counters.inference_regions);
        try std.testing.expectEqual(session.valueChildren(again)[0], session.valueChildren(selected)[0]);
        try std.testing.expectEqual(@as(usize, 1), session.canonical_specializations.reused);
        const expected = try session.evidence.intern(.function, types.u32_type, types.u32_type, &.{});
        const selected_before = session.counters.inference_regions;
        _ = try session.specializeClosure(again, expected);
        try std.testing.expect(session.counters.inference_regions > selected_before);
    }
}

fn canonicalHitRetry(module: *const core.Module, offset: ?usize) !usize {
    var failing = std.testing.FailingAllocator.init(a, .{});
    var allocations: usize = 0;
    {
        var session = try evaluator.Session.init(failing.allocator(), &.{module.*});
        defer session.deinit();
        session.retain_specialization_receipts = true;
        const expected = try session.evidence.intern(.function, types.u32_type, types.u32_type, &.{});
        const first = try session.richValue(target(module, "first"));
        const again = try session.richValue(target(module, "again"));
        _ = try session.specializeClosure(first, expected);
        const sizes = .{ session.values.items.len, session.children.items.len, session.closures.items.len, session.type_mappings.items.len, session.row_mappings.items.len, session.demands.items.len, session.typed_views.count(), session.specialized_closures.count(), session.validated_calls.count(), session.plain_nominals.count(), session.specialization_receipts.items.len };
        const regions = session.counters.inference_regions;
        const start = failing.alloc_index;
        if (offset) |index| failing.fail_index = start + index;
        const selected = session.specializeClosure(again, expected) catch |err| retry: {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expect(failing.has_induced_failure);
            try std.testing.expectEqual(sizes, .{ session.values.items.len, session.children.items.len, session.closures.items.len, session.type_mappings.items.len, session.row_mappings.items.len, session.demands.items.len, session.typed_views.count(), session.specialized_closures.count(), session.validated_calls.count(), session.plain_nominals.count(), session.specialization_receipts.items.len });
            try std.testing.expectEqual(regions, session.counters.inference_regions);
            try std.testing.expectEqual(@as(usize, 0), session.canonical_specializations.reused);
            failing.fail_index = std.math.maxInt(usize);
            break :retry try session.specializeClosure(again, expected);
        };
        allocations = failing.alloc_index - start;
        try std.testing.expectEqual(regions, session.counters.inference_regions);
        try std.testing.expectEqual(session.valueChildren(again)[0], session.valueChildren(selected)[0]);
        try std.testing.expectEqual(@as(usize, 1), session.canonical_specializations.reused);
        try std.testing.expectEqual(@as(usize, 2), session.specialization_receipts.items.len);
        try std.testing.expectEqual(again, session.specialization_receipts.items[1].input);
    }
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    return allocations;
}

test "canonical proof hit publishes atomically and retries every allocation failure in the same session" {
    var module = try lower(
        \\const make: U32 -> (U32 -> U32 ! {}) = fn captured => fn value => @u32.add captured value
        \\entry const first = make 1
        \\entry const again = make 1
    );
    defer module.deinit(a);
    const allocations = try canonicalHitRetry(&module, null);
    for (0..allocations) |offset| _ = try canonicalHitRetry(&module, offset);
}

test "canonical capture keys preserve aggregate aliases nominal identities and settings" {
    var module = try lower(
        \\type Box is data = #Box { value: U32 }
        \\type Other is data = #Other { value: U32 }
        \\const make = fn left => fn right => fn () => @u32.add left.value right.value
        \\const box = #Box { value: 20 }
        \\entry const shared = make box box
        \\entry const shared_again = make box box
        \\entry const separate = make (#Box { value: 20 }) (#Box { value: 20 })
        \\entry const separate_again = make (#Box { value: 20 }) (#Box { value: 20 })
        \\entry const nominal = make (#Other { value: 20 }) (#Other { value: 20 })
    );
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    session.canonical_specializations.force_collision = true;
    const expected = try session.evidence.intern(.function, types.unit, types.u32_type, &.{});
    for ([_][]const u8{ "shared", "shared_again", "separate", "separate_again", "nominal" }, 0..) |name, index| {
        const raw = try session.richValue(target(&module, name));
        const before = session.counters.inference_regions;
        const selected = try session.specializeClosure(raw, expected);
        if (index == 1 or index == 3) try std.testing.expectEqual(before, session.counters.inference_regions) else try std.testing.expect(session.counters.inference_regions > before);
        const current = session.valueChildren(raw);
        const frozen = session.valueChildren(selected);
        for (current, frozen) |original, refined| {
            try std.testing.expectEqual(session.valueInfo(original).nominal, session.valueInfo(refined).nominal);
            try canonicalCurrentPayload(&session, original, refined);
        }
        try std.testing.expectEqual(index < 2, current[0] == current[1]);
        try std.testing.expectEqual(index < 2, frozen[0] == frozen[1]);
    }
    const raw = try session.richValue(target(&module, "shared_again"));
    session.options.max_steps -= 1;
    try std.testing.expectEqual(@as(?lexical_inputs.Inputs, null), try session.canonical_specializations.key(&session, raw));
}

fn canonicalCurrentPayload(session: *evaluator.Session, original: u32, refined: u32) !void {
    const left = session.valueInfo(original);
    const right = session.valueInfo(refined);
    try std.testing.expectEqual(left.kind, right.kind);
    try std.testing.expectEqual(left.bits, right.bits);
    try std.testing.expectEqual(left.nominal, right.nominal);
    if (left.kind == .scalar) try std.testing.expectEqual(original, refined);
    const before = session.valueChildren(original);
    const after = session.valueChildren(refined);
    try std.testing.expectEqual(before.len, after.len);
    for (before, after) |old, current| try canonicalCurrentPayload(session, old, current);
}

test "canonical proofs preserve selected effect evidence and mismatch diagnostics" {
    var module = try lower(
        \\effect Read: Unit -> U32
        \\const make = fn (captured: U32) => fn () => do:
        \\  use value <- Read ()
        \\  return @u32.add captured value
        \\entry const first = make 1
        \\entry const again = make 1
    );
    defer module.deinit(a);
    for ([_]bool{ false, true }) |sharing| {
        var session = try evaluator.Session.init(a, &.{module});
        defer session.deinit();
        session.canonical_specializations.enabled = sharing;
        session.canonical_specializations.force_collision = true;
        const first = try session.richValue(target(&module, "first"));
        const expected = session.valueEvidence(try session.inferClosure(first));
        _ = try session.specializeClosure(first, expected);
        const again = try session.richValue(target(&module, "again"));
        const selected = try session.specializeClosure(again, expected);
        try std.testing.expectEqual(expected, session.valueEvidence(selected));
        const pure = try session.evidence.intern(.function, types.unit, types.u32_type, &.{});
        try std.testing.expect(expected != pure);
        try expectCaptureMismatch(&session, again, pure);
    }
}

test "canonical call observations resolve explicit nonsequential source unit identities" {
    var module = try lowerWithUnit(
        \\entry const callee: U32 -> U32 = fn value => @u32.add value 0
        \\const make: U32 -> (U32 -> U32 ! {}) = fn captured => fn value => callee (@u32.add captured value)
        \\entry const first = make 1
        \\entry const again = make 1
        \\entry const third = make 1
    , .{}, 17);
    defer module.deinit(a);
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    const expected = try session.evidence.intern(.function, types.u32_type, types.u32_type, &.{});
    const callee = try session.richValue(target(&module, "callee"));
    _ = try session.specializeClosure(callee, expected);
    for ([_][]const u8{ "first", "again", "third" }) |name| {
        _ = try session.specializeClosure(try session.richValue(target(&module, name)), expected);
    }
    try std.testing.expect(session.canonical_specializations.reused != 0);
    var observed = false;
    var buckets = session.canonical_specializations.buckets.valueIterator();
    while (buckets.next()) |bucket| for (bucket.items) |entry| {
        for (entry.proof.call_reads) |read| {
            try std.testing.expectEqual(@as(u32, 17), read.unit);
            observed = true;
        }
    };
    try std.testing.expect(observed);
}

fn frozenPublicationScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var copied: evaluator.Snapshot = undefined;
    var selected: evaluator.ValueId = undefined;
    {
        var session = try evaluator.Session.init(allocator, &.{module.*});
        defer session.deinit();
        session.canonical_specializations.enabled = false;
        const raw = try session.richValue(target(module, "first"));
        const info = session.valueInfo(raw);
        const captures = try allocator.dupe(evaluator.ValueId, session.valueChildren(raw));
        defer allocator.free(captures);
        selected = (session.inferEntryClosure(raw) catch |err| {
            // Child preparation may have completed before a parent reservation
            // failed. Existing source headers and spans remain immutable.
            try std.testing.expectEqualDeep(info, session.valueInfo(raw));
            try std.testing.expectEqualSlices(evaluator.ValueId, captures, session.valueChildren(raw));
            return err;
        }) orelse return error.ExpectedConcreteInterface;
        try std.testing.expectEqualDeep(info, session.valueInfo(raw));
        try std.testing.expectEqualSlices(evaluator.ValueId, captures, session.valueChildren(raw));
        try std.testing.expectEqualSlices(evaluator.ValueId, captures, session.valueChildren(selected));
        try std.testing.expectEqual(@as(u64, 0), session.counters.frozen_capture_temporary_bytes);
        try std.testing.expectEqual(@as(u64, 32), session.counters.frozen_capture_published_bytes);
        try std.testing.expect(session.counters.solver_requested_bytes != 0);
        try std.testing.expect(session.counters.scratch_requested_bytes != 0);
        copied = try session.copySnapshotMeasured(allocator);
        try std.testing.expect(session.counters.snapshot_copy_bytes != 0);
    }
    defer copied.deinit(allocator);
    const info = copied.values[selected];
    try std.testing.expectEqual(@as(u32, 8), info.len);
    for (copied.children[info.start..][0..info.len], 1..) |capture, expected| {
        try std.testing.expectEqual(@as(u32, @intCast(expected)), copied.values[capture].bits);
    }
}

test "frozen publication preserves wide source captures and owned snapshots at every allocation failure" {
    var module = try lower(
        \\const make: U32 -> (U32 -> U32 ! {}) = fn seed => do:
        \\  let c0 = seed
        \\  let c1 = @u32.add seed 1
        \\  let c2 = @u32.add seed 2
        \\  let c3 = @u32.add seed 3
        \\  let c4 = @u32.add seed 4
        \\  let c5 = @u32.add seed 5
        \\  let c6 = @u32.add seed 6
        \\  let c7 = @u32.add seed 7
        \\  return fn value => @u32.add value (@u32.add c0 (@u32.add c1 (@u32.add c2 (@u32.add c3 (@u32.add c4 (@u32.add c5 (@u32.add c6 c7)))))))
        \\entry const first = make 1
        \\entry const answer = first 6
    );
    defer module.deinit(a);
    try frozenPublicationScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, frozenPublicationScenario, .{&module});
}
