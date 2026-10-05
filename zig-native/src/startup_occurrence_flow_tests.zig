const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const core_eval = @import("core_eval.zig");
const a = std.testing.allocator;
fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("source check {s} {d}..{d}: {s}\n", .{ @tagName(diagnostic.code), diagnostic.span.start, diagnostic.span.end, diagnostic.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &names, &checked);
    module.unit = 1;
    return module;
}
fn compile(allocator: std.mem.Allocator, source: []const u8) !backend.Result {
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    return backend.compile(allocator, &.{module}, 1);
}
const waiting_array =
    \\type Box is data = #Box U32
    \\const Box.read = fn value => 42
    \\const keep = fn ~(value: Unit -> U32) => value
    \\const helper = fn () => (#Box 1).read
    \\const pending = keep helper
    \\let first: U32 = @array.length #[pending]
    \\entry const answer: Unit -> U32 = fn () => first
;
const ready_self =
    \\type Box is data = #Box U32
    \\const Box.read = fn value => first
    \\const keep = fn ~(value: Unit -> U32) => value
    \\const helper = fn () => (#Box 1).read
    \\const pending = keep helper
    \\const cached = @force pending
    \\let first: U32 = cached ()
    \\entry const answer: Unit -> U32 = fn () => first
;
const mixed_waiting =
    \\type Box is data = #Box U32
    \\const Box.read = fn value => second
    \\const keep = fn ~(value: Unit -> U32) => value
    \\const helper = fn () => (#Box 1).read
    \\const ready_pending = keep helper
    \\const waiting_pending = keep helper
    \\const cached = @force ready_pending
    \\let first: U32 = cached ()
    \\let second: U32 = (@force waiting_pending) ()
    \\entry const answer: Unit -> U32 = fn () => @u32.add first second
;
const returned_waiting =
    \\type Box is data = #Box U32
    \\const Box.read = fn value => second
    \\const keep = fn ~(value: Unit -> U32) => value
    \\const helper = fn () => (#Box 1).read
    \\const ready_pending = keep helper
    \\const waiting_pending = keep helper
    \\const provide = fn () => waiting_pending
    \\const cached = @force ready_pending
    \\let first: U32 = cached ()
    \\let second: U32 = (@force (provide ())) ()
    \\entry const answer: Unit -> U32 = fn () => @u32.add first second
;
const array_waiting =
    \\type Box is data = #Box U32
    \\const Box.read = fn value => second
    \\const keep = fn ~(value: Unit -> U32) => value
    \\const helper = fn () => (#Box 1).read
    \\const ready_pending = keep helper
    \\const waiting_store = #[keep helper]
    \\const cached = @force ready_pending
    \\let first: U32 = cached ()
    \\let second: U32 = (@force (@array.get waiting_store 0)) ()
    \\entry const answer: Unit -> U32 = fn () => @u32.add first second
;
fn succeeds(allocator: std.mem.Allocator) !void {
    var result = try compile(allocator, ready_self);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
test "ready selected self read receives only its complete current occurrence proof" {
    try succeeds(a);
}
test "same source helper reached ready and waiting still rejects the waiting self cycle" {
    for ([_][]const u8{ mixed_waiting, returned_waiting, array_waiting }) |source| {
        var result = try compile(a, source);
        defer result.deinit(a);
        const diagnostic = result.diagnostic orelse return error.MissingCycle;
        try std.testing.expectEqual(backend.Code.initialization_cycle, diagnostic.code);
        try std.testing.expectEqual(diagnostic.span.start, diagnostic.span.end);
        try std.testing.expectEqual(@as(u32, 1), diagnostic.unit);
    }
}
test "complete occurrence planning and owned emission release every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, succeeds, .{});
}
fn waitingProof(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator, waiting_array);
    defer module.deinit(allocator);
    const units = [_]core.Module{module};
    var session = try core_eval.Session.init(allocator, &units);
    defer session.deinit();
    var pending: core_eval.ValueId = 0;
    for (module.bodies[1..]) |body| {
        if (!body.is_function and !body.runtime and module.types.node(body.scheme.root).tag == .demand) pending = try session.richValue(.{ .unit = 1, .binding = body.binding });
    }
    try std.testing.expect(pending != 0);
    try std.testing.expect(session.suspensionCached(pending) == null);
    const prior = session.valueInfo(pending);
    const evidence = session.valueEvidence(pending);
    const demanded = session.demanded;
    const selected = try session.inferSuspension(pending);
    try std.testing.expectEqual(core_eval.ValueKind.suspension, session.valueInfo(selected).kind);
    try std.testing.expect(session.valueEvidence(selected) != 0);
    try std.testing.expect(session.suspensionCached(pending) == null);
    try std.testing.expect(session.suspensionCached(selected) == null);
    try std.testing.expectEqual(prior, session.valueInfo(pending));
    try std.testing.expectEqual(evidence, session.valueEvidence(pending));
    try std.testing.expectEqual(demanded, session.demanded);
    var result = try backend.compile(allocator, &units, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
}
test "unforced waiting array keeps its demand pending while full retained bodies close representation rows" {
    try waitingProof(a);
}
test "full waiting demand inference and emission release every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, waitingProof, .{});
}
test "fresh waiting region preserves an independently cached returned operand without weakening its own calls" {
    const prefix = "type Box is data = #Box U32\nconst Box.read = fn value => second\nconst keep = fn ~(value: Unit -> U32) => value\nconst helper = fn () => (#Box 1).read\nconst ready_pending = keep helper\nconst cached = @force ready_pending\nconst make = fn (action: Unit -> U32) => fn () => keep action\nconst fetch = make cached\n";
    for ([_][]const u8{
        prefix ++ "let second: U32 = (@force (fetch ())) ()\nentry const answer: Unit -> U32 = fn () => second\n",
        prefix ++ "let second: U32 = @array.length #[fetch ()]\nentry const answer: Unit -> U32 = fn () => second\n",
    }) |source| {
        var result = try compile(a, source);
        defer result.deinit(a);
        if (result.diagnostic) |diagnostic| std.debug.print("returned ready {s} {d}..{d}\n", .{ @tagName(diagnostic.code), diagnostic.span.start, diagnostic.span.end });
        try std.testing.expect(result.diagnostic == null);
    }
}
test "tagged startup wrappers cover calls through exact bound retained closures" {
    const source = "infixl 60 (+) = plus\nconst plus = fn left => fn right => @u32.add left right\nconst decorate = fn (function: U32 -> U32) => fn (value: U32) => function value + 1\n@[decorate] let next: U32 -> U32 = fn(value: U32) => value\nentry const answer: U32 -> U32 = fn(value: U32) => next value\n";
    var result = try compile(a, source);
    defer result.deinit(a);
    if (result.diagnostic) |diagnostic| std.debug.print("tagged startup {s} {d}..{d}\n", .{ @tagName(diagnostic.code), diagnostic.span.start, diagnostic.span.end });
    try std.testing.expect(result.diagnostic == null);
}
fn genericTaggedProof(allocator: std.mem.Allocator) !void {
    const source = "const decorate=fn function=>fn value=>@u32.add (function value) 1\n@[decorate] let next:U32->U32=fn(value:U32)=>value\nentry const answer=fn(value:U32)=>next value\n";
    var result = try compile(allocator, source);
    defer result.deinit(allocator);
    if (result.diagnostic) |diagnostic| std.debug.print("generic tagged startup {s} {d}..{d}\n", .{ @tagName(diagnostic.code), diagnostic.span.start, diagnostic.span.end });
    try std.testing.expect(result.diagnostic == null);
}
test "generic tagged startup wrappers retain the concrete scalar occurrence parameter" {
    try genericTaggedProof(a);
}
test "generic retained scalar context declines an uncovered runtime callable cycle" {
    const source = "const decorate=fn function=>fn value=>@u32.add (function value) bias\n@[decorate] let next:U32->U32=fn(value:U32)=>value\nlet bias:U32=next 0\nentry const answer=fn(value:U32)=>next value\n";
    var result = try compile(a, source);
    defer result.deinit(a);
    const diagnostic = result.diagnostic orelse return error.MissingDecline;
    try std.testing.expectEqual(backend.Code.constant_expression, diagnostic.code);
}
test "generic retained scalar context releases every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, genericTaggedProof, .{});
}
fn nestedDemandProof(allocator: std.mem.Allocator) !void {
    const source = "type Box is data = #Box U32\nconst Box.read=fn value=>42\nconst keep=fn ~(value:Unit->U32)=>value\nconst helper=fn ()=>(#Box 1).read\nconst unforced=keep helper\nconst ready_pending=keep helper\nconst cached=@force ready_pending\nconst make=fn (action:Unit->U32)=>fn ()=>keep action\nentry const fetch=make cached\n";
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    for ([_]bool{ true, false }) |recipes| {
        var session = try core_eval.Session.init(allocator, &.{module});
        defer session.deinit();
        session.options.reuse_body_recipes = recipes;
        session.options.retain_source_suspensions = true;
        var unforced: core.BindingRef = undefined;
        for (module.bodies[1..]) |body| if (module.types.node(body.scheme.root).tag == .demand) {
            unforced = .{ .unit = 1, .binding = body.binding };
            break;
        };
        const pending = try session.richValue(unforced);
        const fetch = for (module.bodies[1..]) |body| {
            if (body.exported) break core.BindingRef{ .unit = 1, .binding = body.binding };
        } else return error.MissingExport;
        const raw = try session.richValue(fetch);
        const memo = try allocator.dupe(core_eval.Demand, session.demands.items);
        defer allocator.free(memo);
        const info = session.valueInfo(raw);
        const steps = session.steps;
        const records = session.source_suspensions.items.len;
        const inferred = try session.inferClosure(raw);
        try std.testing.expectEqual(steps, session.steps);
        try std.testing.expectEqual(records, session.source_suspensions.items.len);
        try std.testing.expectEqualDeep(memo, session.demands.items[0..memo.len]);
        try std.testing.expectEqual(info, session.valueInfo(raw));
        try std.testing.expect(session.suspensionCached(pending) == null);
        const arrow = session.evidence.node(session.valueEvidence(inferred));
        try std.testing.expectEqual(@import("type_evidence.zig").Tag.function, arrow.tag);
        const demand = session.evidence.node(arrow.b);
        try std.testing.expectEqual(@import("type_evidence.zig").Tag.demand, demand.tag);
        const wrong_callback = try session.evidence.intern(.function, 1, 4, &.{});
        const wrong_demand = try session.evidence.intern(.demand, wrong_callback, 0, &.{});
        const wrong = try session.evidence.intern(.function, 1, wrong_demand, &.{});
        if (session.specializeClosure(raw, wrong)) |_| return error.ExpectedTypeMismatch else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Declined => {},
            error.RequestUnwind => return error.TestUnexpectedResult,
        }
        try std.testing.expectEqual(core_eval.Code.type_mismatch, session.diagnostic.?.code);
        try std.testing.expectEqualDeep(memo, session.demands.items[0..memo.len]);
    }
}
test "completed source demand bodies preserve memo state and selected type negatives with recipes on and off" {
    try nestedDemandProof(a);
}
test "completed source demand body inference releases every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, nestedDemandProof, .{});
}
test "completed demand body cannot erase the returned callback latent effect" {
    const source = "effect Read:Unit->U32\nconst keep=fn ~value=>value\nconst action=fn ()=>do:\n  use value<-Read ()\n  return value\nconst make=fn action=>fn ()=>keep action\nentry const fetch=make action\n";
    var module = try lower(a, source);
    defer module.deinit(a);
    var session = try core_eval.Session.init(a, &.{module});
    defer session.deinit();
    const fetch = for (module.bodies[1..]) |body| {
        if (body.exported) break core.BindingRef{ .unit = 1, .binding = body.binding };
    } else return error.MissingExport;
    const raw = try session.richValue(fetch);
    const inferred = try session.inferClosure(raw);
    const arrow = session.evidence.node(session.valueEvidence(inferred));
    const demand = session.evidence.node(arrow.b);
    const callback = session.evidence.node(demand.a);
    try std.testing.expect(session.evidence.view().effects.rowLabels(callback.c).len != 0);
    const pure_callback = try session.evidence.intern(.function, 1, 3, &.{});
    const pure_demand = try session.evidence.intern(.demand, pure_callback, 0, &.{});
    const pure = try session.evidence.intern(.function, 1, pure_demand, &.{});
    try std.testing.expectError(error.Declined, session.specializeClosure(raw, pure));
    try std.testing.expectEqual(core_eval.Code.effect_mismatch, session.diagnostic.?.code);
}
fn nestedArrayEmission(allocator: std.mem.Allocator) !void {
    const source = "type Box is data=#Box U32\nconst Box.read=fn value=>second\nconst keep=fn ~(value:Unit->U32)=>value\nconst helper=fn ()=>(#Box 1).read\nconst pending=keep helper\nconst cached=@force pending\nconst make=fn (action:Unit->U32)=>fn ()=>keep action\nconst fetch=make cached\nlet second:U32=@array.length #[fetch ()]\nentry const answer:Unit->U32=fn ()=>second\n";
    var result = try compile(allocator, source);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
}
test "nested pending demand representation emission releases every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, nestedArrayEmission, .{});
}
