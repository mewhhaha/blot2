const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const types = @import("types.zig");
const a = std.testing.allocator;
fn lower(source: []const u8) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &names);
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.check(a, &syntax, &names);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(a, &syntax, &names, &checked);
    errdefer result.deinit(a);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}
fn target(module: *const core.Module, name: []const u8) core.BindingRef {
    for (module.bodies[1..]) |body| if (std.mem.eql(u8, module.name(body.export_name), name)) return .{ .unit = 1, .binding = body.binding };
    unreachable;
}
fn prove(session: *evaluator.Session, module: *const core.Module, name: []const u8, allocator: std.mem.Allocator) !void {
    const prior_steps = session.steps;
    const reference = target(module, name);
    const parameter = module.types.node(module.binding(reference.binding).ty).a;
    const expected = if (parameter == types.u32_type or parameter == types.f32_type) try session.evidence.intern(.function, parameter, parameter, &.{}) else 0;
    var solved = try session.bodyEvidenceFull(reference, expected, &.{}, &.{});
    defer solved.deinit(allocator);
    try std.testing.expect(session.diagnostic == null);
    try std.testing.expectEqual(prior_steps, session.steps);
}
fn repeated(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    try prove(&session, module, "first", allocator);
    try std.testing.expect(session.proofs.proof_published > 0);
    const first_hits = session.proofs.proof_reused;
    try prove(&session, module, "second", allocator);
    try std.testing.expect(session.proofs.proof_reused > first_hits);
    const second_hits = session.proofs.proof_reused;
    try prove(&session, module, "floating", allocator);
    try std.testing.expectEqual(second_hits, session.proofs.proof_reused);
    try prove(&session, module, "floating_again", allocator);
    try std.testing.expect(session.proofs.proof_reused > second_hits);
}
test "exact semantic evidence distinguishes U32 and F32 repeated generic bodies with no evaluation" {
    var module = try lower(
        \\const identity = fn value => value
        \\entry const first = fn (value: U32) -> U32 => identity value
        \\entry const second = fn (value: U32) -> U32 => identity value
        \\entry const floating = fn (value: F32) -> F32 => identity value
        \\entry const floating_again = fn (value: F32) -> F32 => identity value
    );
    defer module.deinit(a);
    const original = try a.dupe(types.Node, module.types.nodes);
    defer a.free(original);
    try repeated(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, repeated, .{&module});
    try std.testing.expectEqualDeep(original, module.types.nodes);
}
fn excluded(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    try prove(&session, module, "first", allocator);
    try prove(&session, module, "second", allocator);
    try std.testing.expectEqual(@as(usize, 0), session.proofs.proof_published);
    try std.testing.expectEqual(@as(usize, 0), session.proofs.proof_reused);
}
test "nominal payloads containing callables need richer evidence and do not enter this cache" {
    var module = try lower(
        \\type Box is data = #Box { run: Unit -> U32 }
        \\const invoke = fn (box: Box) -> U32 => box.run ()
        \\entry const first = fn (box: Box) -> U32 => invoke box
        \\entry const second = fn (box: Box) -> U32 => invoke box
    );
    defer module.deinit(a);
    try excluded(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, excluded, .{&module});
}

const selected_fixture =
    \\const identity = fn value => value
    \\entry const first = fn (value: U32) -> U32 => identity value
    \\entry const second = fn (value: U32) -> U32 => identity value
    \\entry const floating = fn (value: F32) -> F32 => identity value
    \\entry const floating_again = fn (value: F32) -> F32 => identity value
;
fn selectedProofs(allocator: std.mem.Allocator, module: *const core.Module, entry: bool) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const value = try session.richValue(target(module, "first"));
    if (entry) {
        try std.testing.expect((try session.inferEntryClosure(value)) != null);
    } else {
        _ = try session.inferClosure(value);
    }
    try std.testing.expect(session.proofs.proof_published > 0);
    const before = session.proofs.proof_reused;
    try prove(&session, module, "second", allocator);
    try std.testing.expect(session.proofs.proof_reused > before);
    const integer_hits = session.proofs.proof_reused;
    try prove(&session, module, "floating", allocator);
    try std.testing.expectEqual(integer_hits, session.proofs.proof_reused);
    try prove(&session, module, "floating_again", allocator);
    try std.testing.expect(session.proofs.proof_reused > integer_hits);
}
test "completed inferred closures retain exact dependent proofs across entry and ordinary inference" {
    var module = try lower(selected_fixture);
    defer module.deinit(a);
    const original = try a.dupe(types.Node, module.types.nodes);
    defer a.free(original);
    for ([_]bool{ true, false }) |entry| {
        try selectedProofs(a, &module, entry);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, selectedProofs, .{ &module, entry });
    }
    try std.testing.expectEqualDeep(original, module.types.nodes);
}
fn specializationProofs(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const value = try session.richValue(target(module, "generic"));
    try std.testing.expect((try session.inferEntryClosure(value)) == null);
    try std.testing.expectEqual(@as(usize, 0), session.proofs.proof_published);
    const expected = try session.evidence.intern(.function, types.u32_type, types.u32_type, &.{});
    _ = try session.specializeClosure(value, expected);
    try std.testing.expect(session.proofs.proof_published > 0);
    const before = session.proofs.proof_reused;
    try prove(&session, module, "second", allocator);
    try std.testing.expect(session.proofs.proof_reused > before);
    const integer_hits = session.proofs.proof_reused;
    try prove(&session, module, "floating", allocator);
    try std.testing.expectEqual(integer_hits, session.proofs.proof_reused);
}
test "generic export rejection publishes no proof while concrete specialization retains only its evidence" {
    var module = try lower(selected_fixture ++ "\nentry const generic = fn value => identity value\n");
    defer module.deinit(a);
    try specializationProofs(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, specializationProofs, .{&module});
}
fn constantProofs(allocator: std.mem.Allocator, module: *const core.Module, accepted: bool) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const seed = target(module, "seed");
    try std.testing.expect(module.body(seed.binding).?.scheme.obligations.len != 0);
    if (accepted) {
        try std.testing.expectEqual(@as(u32, 42), (try session.value(seed)).bits);
        try std.testing.expect(session.proofs.proof_published > 0);
        const before = session.proofs.proof_reused;
        try prove(&session, module, "second", allocator);
        try std.testing.expect(session.proofs.proof_reused > before);
    } else {
        if (session.richValue(seed)) |_| return error.TestUnexpectedSuccess else |err| switch (err) {
            error.OutOfMemory => return err,
            error.Declined => {},
            else => return err,
        }
        try std.testing.expectEqual(evaluator.Code.ambiguous_qualified, session.diagnostic.?.code);
        // Independent closed callees may complete before the enclosing
        // qualification fails. No judgment for that failed body can escape.
        var proofs = session.validated_calls.keyIterator();
        while (proofs.next()) |proof| try std.testing.expect(proof.target.binding != seed.binding);
        const before = session.proofs.proof_reused;
        session.diagnostic = null;
        try prove(&session, module, "second", allocator);
        try std.testing.expect(session.proofs.proof_reused > before);
    }
}
test "constant prepasses publish complete proofs and leave unresolved obligations unpublished" {
    inline for ([_]bool{ true, false }) |accepted| {
        const seed = if (accepted) "\nentry const seed: U32 where { type_rep U32 } = identity 42\n" else "\nentry const seed: U32 where { type_rep a } = identity 42\n";
        var module = try lower(selected_fixture ++ seed);
        defer module.deinit(a);
        try constantProofs(a, &module, accepted);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, constantProofs, .{ &module, accepted });
    }
}
