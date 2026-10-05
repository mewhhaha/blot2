const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const a = std.testing.allocator;

const unused_nested = "type Left is data = #Left U32\ntype Right is data = #Right U32\nconst Right.read = fn value => first\nconst Left.read = fn value => fn () => (#Right 1).read\nconst pick = fn value => value.read\nlet first: Unit -> U32 = pick (#Left 1)\nentry const answer: Unit -> U32 = fn () => 42\n";
const demanded_mismatch = "type Left is data = #Left U32\ntype Right is data = #Right U32\nconst Right.read = fn value => first\nconst Left.read = fn value => fn () => (#Right 1).read\nconst pick = fn value => value.read\nlet first: Unit -> U32 = pick (#Left 1)\nentry const answer: Unit -> U32 = fn () => first ()\n";
const distinct_methods = "type Left is data = #Left U32\ntype Right is data = #Right U32\nconst Left.read = fn value => 42\nconst Right.read = fn value => 1.25\nconst pick = fn value => value.read\nentry const integer: Unit -> U32 = fn () => pick (#Left 1)\nentry const floating: Unit -> F32 = fn () => pick (#Right 2)\n";

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &syntax, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    for (checked.diagnostics) |d| std.debug.print("initial {s} {d}..{d}\n", .{ @tagName(d.code), d.span.start, d.span.end });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &syntax, &names, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}

fn emit(allocator: std.mem.Allocator, module: *const core.Module, expected: ?backend.Code) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    if (result.diagnostic) |d| std.debug.print("demanded {s} {d}..{d}\n", .{ @tagName(d.code), d.span.start, d.span.end });
    try std.testing.expectEqual(expected, if (result.diagnostic) |d| d.code else null);
    if (expected == null) try std.testing.expect(result.bytes.len > 8) else try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
}

test "deferred method unused malformed nested slot survives initial checking and frontend teardown" {
    var module = try lower(a, unused_nested);
    defer module.deinit(a);
    var retained: usize = 0;
    for (module.obligations) |obligation| if (obligation.kind == .receiver and !obligation.explicit) {
        retained += 1;
        try std.testing.expect(obligation.signature != 0 and obligation.result != 0);
    };
    try std.testing.expect(retained > 0);
    try emit(a, &module, null);
}

test "deferred method demanded mismatched result remains an authoritative evidence failure" {
    var module = try lower(a, demanded_mismatch);
    defer module.deinit(a);
    try emit(a, &module, .type_mismatch);
}

test "deferred method concrete instances retain independent generic receiver evidence" {
    var module = try lower(a, distinct_methods);
    defer module.deinit(a);
    try emit(a, &module, null);
}

test "deferred method reached returned closures preserve initializer cycle diagnostics" {
    for ([_]struct { source: []const u8, point: u32 }{
        .{ .source = "type Left is data = #Left U32\nconst Left.read = fn value => fn () => first ()\nconst pick = fn value => value.read\nlet first: Unit -> U32 = pick (#Left 1)\nentry const answer: Unit -> U32 = fn () => do:\n  let unused = first\n  return 42\n", .point = 118 },
        .{ .source = "type Left is data = #Left U32\ndata Cell = #Cell {value: U32, action: Unit -> U32}\nconst Left.read = fn value => fn () => first.value\nconst pick = fn value => value.read\nlet first = #Cell {value: 42, action: pick (#Left 1)}\nentry const answer: Unit -> U32 = fn () => first.action ()\n", .point = 173 },
        .{ .source = "type Left is data = #Left U32\ntype Right is data = #Right U32\nconst Right.read = fn value => @array.length #[first]\nconst Left.read = fn value => fn () => (#Right 1).read\nconst pick = fn value => value.read\nlet first: Unit -> U32 = pick (#Left 1)\nentry const answer: Unit -> U32 = fn () => do:\n  let unused = first\n  return 42\n", .point = 211 },
    }) |case_| {
        var module = try lower(a, case_.source);
        defer module.deinit(a);
        var result = try backend.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic != null);
        try std.testing.expectEqual(backend.Code.initialization_cycle, result.diagnostic.?.code);
        try std.testing.expectEqual(core.Span{ .start = case_.point, .end = case_.point }, result.diagnostic.?.span);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    }
}

fn initialDiagnostic(allocator: std.mem.Allocator, source: []const u8, expected: check.Code) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &syntax, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    try std.testing.expect(checked.diagnostics.len > 0);
    try std.testing.expectEqual(expected, checked.diagnostics[0].code);
}

const initial_errors = [_]struct { source: []const u8, expected: check.Code }{
    .{ .source = "type Box is data = #Box U32\nconst Box.read = fn value => 1.25\nentry const answer: Unit -> U32 = fn () => (#Box 1).read\n", .expected = .type_mismatch },
    .{ .source = "const unused: U32 = #True\nentry const answer = fn () => 42\n", .expected = .type_mismatch },
    .{ .source = "const unused = fn value => value value\nentry const answer = fn () => 42\n", .expected = .infinite_type },
    .{ .source = "type Box is data = #Box {value: F32}\nconst unused: U32 = (#Box {value: 1.25}).value\nentry const answer = fn () => 42\n", .expected = .type_mismatch },
    .{ .source = "type Box is data = #Box U32\nconst unused = fn () => (#Box 1).absent\nentry const answer = fn () => 42\n", .expected = .missing_member },
    .{ .source = "type Box is data = #Box {read: U32}\nconst Box.read = fn value => 42\nconst unused = fn () => (#Box {read: 1}).read\nentry const answer = fn () => 42\n", .expected = .ambiguous_member },
};

test "deferred method leaves plain infinite physical missing and ambiguous initial errors intact" {
    for (initial_errors) |case_| try initialDiagnostic(a, case_.source, case_.expected);
}

fn lowerAndEmit(allocator: std.mem.Allocator, source: []const u8, expected: ?backend.Code) !void {
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    try emit(allocator, &module, expected);
    try std.testing.expectEqualSlices(u8, &before, &@import("core_snapshot_tests.zig").stamp(module));
}

test "deferred method source requirements and later evidence release every failed allocation" {
    const failures = @import("allocation_failures.zig");
    try failures.checkAllAllocationFailures(a, lowerAndEmit, .{ unused_nested, @as(?backend.Code, null) });
    try failures.checkAllAllocationFailures(a, lowerAndEmit, .{ demanded_mismatch, @as(?backend.Code, .type_mismatch) });
    for (initial_errors) |case_| try failures.checkAllAllocationFailures(a, initialDiagnostic, .{ case_.source, case_.expected });
}

const qualified_member_cases = [_][]const u8{
    "type Box is data = #Box U32\nconst Box.read: Box -> a where {field \"read\" Box a} = fn (value: Box) => do:\n  let result = (fn other => other.read) value\n  return result\nentry const answer = 42\n",
    "type Box is data = #Box U32\nconst Box.read: Box -> a where {field \"read\" Box a} = fn value => helper value\nconst helper: Box -> a = fn value => value.read\nentry const answer = 42\n",
    "type Box is data = #Box U32\nconst Box.read: Box -> a where {field \"read\" Box a} = fn (value: Box) => do:\n  let result = helper value\n  return result\nconst helper: Box -> a = fn value => value.read\nentry const answer = 42\n",
    "type Box is data = #Box U32\nconst Box.read: Box -> a where {receiver \"read\" Box Unit a} = fn (value: Box) => do:\n  let result = (fn other => other.read) value\n  return result\nentry const answer = 42\n",
    "type Box is data = #Box U32\nconst Box.read: Box -> U32 where {} = fn value => value.read\nentry const answer = 42\n",
};

test "method source qualification retains field coverage for active recursive selected projections" {
    for (qualified_member_cases) |source| try lowerAndEmit(a, source, null);
}

test "method source qualification preserves explicit field provenance after frontend ownership ends" {
    var module = try lower(a, qualified_member_cases[0]);
    defer module.deinit(a);
    var found: usize = 0;
    for (module.obligations) |obligation| if (obligation.explicit and obligation.kind == .field) {
        found += 1;
        try std.testing.expectEqual(@as(u32, 1), obligation.qualification_unit);
        const origin = obligation.qualification_span orelse return error.MissingQualificationOrigin;
        try std.testing.expect(origin.end > origin.start);
        try std.testing.expect(obligation.ty != 0 and obligation.result != 0);
    };
    try std.testing.expect(found != 0);
    try emit(a, &module, null);
}

fn missingMemberCoverage(allocator: std.mem.Allocator, clause: []const u8) !void {
    const source = try allocator.print("type Box is data = #Box U32\nconst Box.read: Box -> a where {{{s}}} = fn (value: Box) => do:\n  let result = (fn other => other.read) value\n  return result\nentry const answer = 42\n", .{clause});
    defer allocator.free(source);
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &syntax, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    try std.testing.expect(checked.diagnostics.len != 0);
    try std.testing.expectEqual(check.Code.missing_predicate, checked.diagnostics[0].code);
    const point: u32 = @intCast(std.mem.find(u8, source, "other.read").? + "other.".len);
    try std.testing.expectEqual(core.Span{ .start = point, .end = point }, checked.diagnostics[0].span);
}

test "method source qualification preserves delayed member missing predicate origin" {
    try missingMemberCoverage(a, "");
}

test "method source qualification cannot cover another name or a non Unit receiver application" {
    try missingMemberCoverage(a, "field \"other\" Box a");
    try missingMemberCoverage(a, "receiver \"read\" Box U32 a");
}

test "method source qualification correction remains owned and atomic under every allocation failure" {
    const failures = @import("allocation_failures.zig");
    try failures.checkAllAllocationFailures(a, lowerAndEmit, .{ qualified_member_cases[0], @as(?backend.Code, null) });
    try failures.checkAllAllocationFailures(a, missingMemberCoverage, .{@as([]const u8, "")});
}

fn forwardedMemberCoverage(allocator: std.mem.Allocator, delayed: bool) !void {
    const source = if (delayed)
        "type Box is data = #Box U32\nconst Box.read: Box -> a where {} = fn (value: Box) => do:\n  let result = helper value\n  return result\nconst helper: Box -> a = fn value => value.read\nentry const answer = 42\n"
    else
        "type Box is data = #Box U32\nconst Box.read: Box -> a where {} = fn value => helper value\nconst helper: Box -> a = fn value => value.read\nentry const answer = 42\n";
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &syntax, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    try std.testing.expect(checked.diagnostics.len != 0);
    try std.testing.expectEqual(check.Code.missing_predicate, checked.diagnostics[0].code);
    const point: u32 = @intCast(std.mem.find(u8, source, "helper value").?);
    try std.testing.expectEqual(core.Span{ .start = point, .end = point }, checked.diagnostics[0].span);
}

test "method source qualification keeps mutual and forwarded empty clause reference envelopes" {
    try forwardedMemberCoverage(a, false);
    try forwardedMemberCoverage(a, true);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, forwardedMemberCoverage, .{true});
}

test "method source qualification coverage keeps demanded field and receiver evidence distinct" {
    const source = "type Box is data = #Box U32\nconst Box.read = fn value => 42\nconst select: a -> b where {field \"read\" a b} = fn value => value.read\nentry const answer = fn () => select (#Box 1)\n";
    try lowerAndEmit(a, source, .missing_field);
    const receiver = "type Box is data = #Box U32\nconst Box.read = fn value => 42\nconst select: a -> b where {receiver \"read\" a Unit b} = fn value => value.read\nentry const answer = fn () => select (#Box 1)\n";
    try lowerAndEmit(a, receiver, null);
}

fn explicitFieldEnvelope(allocator: std.mem.Allocator) !void {
    const source = "type Box is data = #Box U32\nconst Box.read = fn value => 42\nconst select: a -> b where {field \"read\" a b} = fn value => value.read\nentry const answer = fn () => select (#Box 1)\n";
    var module = try lower(allocator, source);
    var module_live = true;
    defer if (module_live) module.deinit(allocator);
    var retained_use = false;
    for (module.obligations) |obligation| if (obligation.explicit and obligation.kind == .field) {
        try std.testing.expectEqual(@as(u32, 1), obligation.qualification_unit);
        try std.testing.expectEqualStrings("read", module.name(obligation.diagnostic_name));
        const qualification = obligation.qualification_span orelse return error.MissingQualificationOrigin;
        try std.testing.expectEqual(@as(u32, 81), qualification.start);
        if (obligation.span.start == 161 and obligation.span.end == 167) retained_use = true;
    };
    try std.testing.expect(retained_use);
    var result = try backend.compile(allocator, &.{module}, 1);
    defer result.deinit(allocator);
    // Public diagnostic display must outlive the owned Core too.
    module.deinit(allocator);
    module_live = false;
    const diagnostic = result.diagnostic orelse return error.MissingDiagnostic;
    try std.testing.expectEqual(backend.Code.missing_field, diagnostic.code);
    try std.testing.expectEqual(@as(u32, 1), diagnostic.unit);
    try std.testing.expectEqual(core.Span{ .start = 81, .end = 81 }, diagnostic.span);
    try std.testing.expectEqualStrings("no field read on main::Box", diagnostic.message());
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
}

test "demanded physical field failure preserves exact written where clause envelope after all owners end" {
    try explicitFieldEnvelope(a);
}

test "demanded physical field failure releases display and provenance owners on every allocation failure" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, explicitFieldEnvelope, .{});
}

fn currentFieldContextEnvelope(allocator: std.mem.Allocator) !void {
    const source = "type Box is data = #Box U32\nconst Box.read = fn value => 42\nconst select: a -> b where {field \"read\" a b} = fn value => value.read\nentry const answer = fn () => select (#Box 1)\n";
    for ([_]enum { project, source, prelude }{ .project, .source, .prelude }) |mode| {
        var module = try lower(allocator, source);
        var module_live = true;
        defer if (module_live) module.deinit(allocator);
        var names: symbols.Pool = .{};
        defer names.deinit(allocator);
        var identity = try @import("runtime_identity.zig").Metadata.capture(allocator, &names, &.{.{ .unit = 1, .path = "/project/consumer/renamed.blot" }}, 1);
        var identity_live = true;
        defer if (identity_live) identity.deinit(allocator);
        var result = try backend.compileWithOptions(allocator, &.{module}, 1, .{ .identity = identity.view(), .diagnostic_source_mode = mode == .source, .diagnostic_prelude_unit = if (mode == .prelude) 1 else 0 });
        defer result.deinit(allocator);
        module.deinit(allocator);
        module_live = false;
        identity.deinit(allocator);
        identity_live = false;
        const diagnostic = result.diagnostic orelse return error.MissingDiagnostic;
        try std.testing.expectEqual(backend.Code.missing_field, diagnostic.code);
        try std.testing.expectEqual(core.Span{ .start = 81, .end = 81 }, diagnostic.span);
        try std.testing.expectEqualStrings(switch (mode) {
            .project => "no field read on renamed.blot::Box",
            .source => "no field read on main::Box",
            .prelude => "no field read on std/prelude::Box",
        }, diagnostic.message());
    }
}

test "demanded physical field display uses explicit current context after all identity owners end" {
    try currentFieldContextEnvelope(a);
}

test "demanded physical field current-context display releases every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, currentFieldContextEnvelope, .{});
}

const self_open_empty = "type Box is data = #Box U32\nconst Box.read: Box -> a where {} = fn value => value.read\nentry const answer = 42\n";
const self_closed_typed = "type Box is data = #Box U32\nconst Box.read: Box -> U32 where {} = fn (value: Box) => value.read\nentry const answer = 42\n";
const self_unused_closed_nested = "type Box is data = #Box U32\nconst Box.read: Box -> (Unit -> U32) where {} = fn (value: Box) => fn () => value.read\nentry const answer = 42\n";
const self_demanded_closed_nested = "type Box is data = #Box U32\nconst Box.read: Box -> (Unit -> U32) where {} = fn (value: Box) => fn () => value.read\nentry const answer: Unit -> U32 = fn () => (#Box 1).read ()\n";

fn selfMissingCoverage(allocator: std.mem.Allocator, source: []const u8, point: u32) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &syntax, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    try std.testing.expect(checked.diagnostics.len != 0);
    try std.testing.expectEqual(check.Code.missing_predicate, checked.diagnostics[0].code);
    try std.testing.expectEqual(core.Span{ .start = point, .end = point }, checked.diagnostics[0].span);
}

test "self method source open result cannot prove its own empty clause from an unpublished scheme" {
    try selfMissingCoverage(a, self_open_empty, 82);
    try selfMissingCoverage(a, "type Box is data = #Box U32\nconst Box.read: Box -> a where {} = fn (value: Box) => value.read\nentry const answer = 42\n", 89);
}

test "self method source aliases and nested open result rows retain exact empty clause points" {
    try selfMissingCoverage(a, "type Box is data = #Box U32\nconst Box.read: Box -> a where {} = fn value => do:\n  let alias = value\n  return alias.read\nentry const answer = 42\n", 115);
    try selfMissingCoverage(a, "type Box is data = #Box U32\nconst Box.read: Box -> (Unit -> U32 ! {|e}) where {} = fn value => value.read\nentry const answer = 42\n", 101);
}

test "self method source concrete typed declarations keep field receiver and invocation rows deferred" {
    for ([_][]const u8{
        self_closed_typed,
        "type Box is data = #Box U32\nconst Box.read: Box -> U32 where {field \"read\" Box U32} = fn (value: Box) => value.read\nentry const answer = 42\n",
        "type Box is data = #Box U32\nconst Box.read: Box -> U32 where {receiver \"read\" Box Unit U32} = fn (value: Box) => value.read\nentry const answer = 42\n",
        "type Box is data = #Box U32\ntype Tick is effect = Unit -> Unit\nconst Box.read: Box -> U32 ! {Tick} where {} = fn (value: Box) => value.read\nentry const answer = 42\n",
        "type Box is data = #Box U32\nconst Box.read: Box -> U32 where {} = fn (value: Box) => helper value\nconst helper: Box -> U32 = fn value => value.read\nentry const answer = 42\n",
    }) |source| try lowerAndEmit(a, source, null);
}

test "self method source projected uses and qualified function uses keep distinct missing clause origins" {
    try selfMissingCoverage(a, "type Box is data = #Box U32\nconst Box.read: Box -> a = fn value => value.read\nconst empty: Box -> a where {} = fn value => value.read\nentry const answer = 42\n", 129);
    try selfMissingCoverage(a, "type Box is data = #Box U32\nconst Box.read: Box -> a = fn value => value.read\nconst empty: Box -> a where {} = fn value => Box.read value\nentry const answer = 42\n", 123);
}

test "self method source unqualified open recursion retains owned receiver evidence after frontend teardown" {
    var module = try lower(a, "type Box is data = #Box U32\nconst Box.read: Box -> a = fn value => value.read\nentry const answer = 42\n");
    defer module.deinit(a);
    var implicit: usize = 0;
    for (module.obligations) |obligation| if (!obligation.explicit and obligation.kind == .receiver) {
        implicit += 1;
        try std.testing.expectEqual(@import("types.zig").Tag.unit, module.types.nodes[obligation.other].tag);
        try std.testing.expect(obligation.ty != 0 and obligation.result != 0 and obligation.signature != 0);
    };
    try std.testing.expect(implicit != 0);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    try emit(a, &module, null);
    try std.testing.expectEqualSlices(u8, &before, &@import("core_snapshot_tests.zig").stamp(module));
}

test "self method source closed latent evidence remains unused or fails when actually demanded" {
    try lowerAndEmit(a, self_unused_closed_nested, null);
    try lowerAndEmit(a, self_demanded_closed_nested, .type_mismatch);
}

test "self method source empty closed and demanded revisions release every failed allocation" {
    const failures = @import("allocation_failures.zig");
    try failures.checkAllAllocationFailures(a, selfMissingCoverage, .{ self_open_empty, @as(u32, 82) });
    try failures.checkAllAllocationFailures(a, selfMissingCoverage, .{ "type Box is data = #Box U32\nconst Box.read: Box -> a = fn value => value.read\nconst empty: Box -> a where {} = fn value => value.read\nentry const answer = 42\n", @as(u32, 129) });
    try failures.checkAllAllocationFailures(a, lowerAndEmit, .{ self_closed_typed, @as(?backend.Code, null) });
    try failures.checkAllAllocationFailures(a, lowerAndEmit, .{ self_demanded_closed_nested, @as(?backend.Code, .type_mismatch) });
}
