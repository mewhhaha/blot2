const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("check.zig");

fn generatorOrigins(allocator: std.mem.Allocator) !void {
    const source =
        \\const make = func (divisor: U32) => return @code.quote (@u32.div 42 (@code.lift divisor))
        \\const first = make 1
        \\const second = make 0
        \\const choices = {good: first, bad: second}
        \\const answer: U32 = @code.run choices.bad
    ;
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const answer = checked.resolved[tree.roots.items[tree.roots.items.len - 1]];
    const core = @import("core.zig");
    var module = try core.lower(allocator, &tree, &pool, &checked);
    defer module.deinit(allocator);
    var session = try @import("../eval/core_eval.zig").Session.init(allocator, &.{module});
    defer session.deinit();
    const outcome = session.value(.{ .unit = 1, .binding = answer });
    if (outcome) |_| {
        return error.TestExpectedDiagnostic;
    } else |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try std.testing.expectEqual(error.Declined, err);
    }
    const issue = session.diagnostic orelse return error.TestExpectedDiagnostic;
    const selected = std.mem.find(u8, source, "make 0").?;
    var found = false;
    for (issue.origins.items()) |origin| {
        if (origin.kind != .generator) continue;
        try std.testing.expectEqual(@as(u32, @intCast(selected)), origin.location.span.start);
        found = true;
    }
    try std.testing.expect(found);
    var snapshot = try session.copySnapshot(allocator);
    defer snapshot.deinit(allocator);
    const units = [_]struct { core: core.Module }{.{ .core = module }};
    try @import("staging_snapshot.zig").validate(allocator, &snapshot, &units);
    try std.testing.expect(snapshot.code_origins.len >= 2);
    const original = snapshot.code_origins[0];
    snapshot.code_origins[0].generator.node = @intCast(module.nodes.len);
    try std.testing.expectError(error.InvalidArtifact, @import("staging_snapshot.zig").validate(allocator, &snapshot, &units));
    snapshot.code_origins[0] = original;
}

test "typed staging attributes selected generator instances through records and owns portable origins through OOM" {
    try generatorOrigins(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, generatorOrigins, .{});
}

fn law(allocator: std.mem.Allocator, source: []const u8, expected: ?check.Code) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    if (expected) |wanted| {
        for (checked.diagnostics) |diagnostic| if (diagnostic.code == wanted) return;
        for (checked.diagnostics) |diagnostic| std.debug.print("unexpected {s}\n", .{@tagName(diagnostic.code)});
        return error.ExpectedStagingDiagnostic;
    }
    for (checked.diagnostics) |diagnostic| std.debug.print("unexpected {s} at {}\n", .{ @tagName(diagnostic.code), diagnostic.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
}
fn composition(allocator: std.mem.Allocator) !void {
    try law(allocator,
        \\const left: code [U32, row {}] = @code.quote 40
        \\const right: code [U32, row {}] = @code.quote 2
        \\const answer = @code.quote (@u32.add (@code.splice left) (@code.splice right))
        \\const checked_answer: U32 = @code.run answer
        \\const make = func (value: U32) => return @code.quote (@u32.add (@code.lift value) 1)
        \\const future = @code.quote (func (value: U32) => return @u32.add value 1)
        \\const shape = @code.describe (@code.quote {left: 1, right: true})
        \\const fields = @descriptor.fields shape.result
        \\const same: Bool = @descriptor.same fields.left (@code.describe left).result
    , null);
}
test "typed staging checks owned shapes stage locals and explicit composition through OOM" {
    try composition(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, composition, .{});
}
test "typed staging rejects bare earlier values malformed shapes and authority crossing" {
    const a = std.testing.allocator;
    try law(a, "const bad = func (value: U32) => return @code.quote value", .stage_unavailable);
    try law(a, "const value = 1\nconst bad = @code.quote value", .stage_unavailable);
    try law(a, "const bad = @code.splice (@code.quote 1)", .stage_unavailable);
    try law(a, "const bad = @code.lift 1", .stage_unavailable);
    try law(a, "const bad = @code.emit 1", .code_shape_mismatch);
    try law(a, "const bad: code [Bool, row {}] = @code.quote 1", .type_mismatch);
    try law(a, "const bad = @code.quote (@u32.add (@code.splice (@code.quote true)) 1)", .type_mismatch);
    try law(a, "const bad = func callback => return @code.quote (@code.lift callback)", .cross_stage_authority);
    try law(a, "const bad = @descriptor.fields (@code.describe (@code.quote 1)).result", .descriptor_private);
}

fn spliceUsageShape(allocator: std.mem.Allocator) !void {
    try law(allocator,
        \\const generated = @code.quote (func (value: U32) => return value)
        \\const accepted = @code.quote ((func (callback: U32 -> U32) => return callback 42) (@code.splice generated))
    , null);
    try law(allocator,
        \\const generated = @code.quote (func (value: unique U32) => return value)
        \\const bad = @code.quote ((func (callback: U32 -> U32) => return callback 42) (@code.splice generated))
    , .type_mismatch);
}
test "typed staging rejects a spliced callable with a different usage shape through OOM" {
    try spliceUsageShape(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, spliceUsageShape, .{});
}

fn liveSkolemLift(allocator: std.mem.Allocator) !void {
    try law(allocator,
        \\const bad: forall [a] => a -> code [a, row {}] = func value => return @code.quote (@code.lift value)
    , .cross_stage_authority);
}
test "typed staging refuses a lifted live skolem before code publication through OOM" {
    try liveSkolemLift(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, liveSkolemLift, .{});
}

test "typed staging nominal descriptors expose only common public constructor fields" {
    const source =
        \\data Packet a = #Packet {payload: a, flag: Bool}
        \\data Choice a = #Left {shared: a, left: Bool} | #Right {shared: a, right: U32}
        \\const packet = @descriptor.fields (@code.describe (@code.quote #Packet {payload: 40, flag: true})).result
        \\const choice = @descriptor.fields (@code.describe (@code.quote #Left {shared: 40, left: true})).result
        \\const scalar = (@code.describe (@code.quote 1)).result
        \\const answer = if @descriptor.same packet.payload scalar then if @descriptor.same choice.shared scalar then 42 else 0 else 0
    ;
    try law(std.testing.allocator, source, null);
    try evaluatedSource(std.testing.allocator, source);
    try law(std.testing.allocator,
        \\private data Packet = #Packet {payload: U32}
        \\const bad = @descriptor.fields (@code.describe (@code.quote #Packet {payload: 1})).result
    , .descriptor_private);
    try law(std.testing.allocator,
        \\opaque type Packet = {payload: U32}
        \\const bad = @descriptor.fields (@code.describe (@code.quote #Packet {payload: 1})).result
    , .descriptor_private);
}

fn ownedEvaluation(allocator: std.mem.Allocator) !void {
    const source =
        \\const left: code [U32, row {}] = @code.quote 40
        \\const right: code [U32, row {}] = @code.quote 2
        \\const generated = @code.quote (@u32.add (@code.splice left) (@code.splice right))
        \\const answer: U32 = @code.run generated
    ;
    return evaluatedSource(allocator, source);
}
fn evaluatedSource(allocator: std.mem.Allocator, source: []const u8) !void {
    const core = @import("core.zig");
    var module: core.Module = undefined;
    var answer: u32 = 0;
    {
        var tokens = try lexer.lex(allocator, source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        var checked = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{});
        defer checked.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        answer = checked.resolved[tree.roots.items[tree.roots.items.len - 1]];
        module = try core.lower(allocator, &tree, &pool, &checked);
    }
    defer module.deinit(allocator);
    var session = try @import("../eval/core_eval.zig").Session.init(allocator, &.{module});
    defer session.deinit();
    const value = try session.value(.{ .unit = 1, .binding = answer });
    try std.testing.expectEqual(@as(u32, 42), value.bits);
    const again = try session.value(.{ .unit = 1, .binding = answer });
    try std.testing.expectEqual(value, again);
}
test "typed staging owns composed graphs after frontend teardown through OOM" {
    try ownedEvaluation(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownedEvaluation, .{});
}

fn nestedEvaluation(allocator: std.mem.Allocator) !void {
    const source =
        \\const make = func (value: U32) => return @code.quote (@code.quote (@u32.add (@code.lift (@code.lift value)) 2))
        \\const outer = make 40
        \\const inner = @code.run outer
        \\const answer: U32 = @code.run inner
    ;
    try evaluatedSource(allocator, source);
}
test "nested typed staging owns earlier lifts through frontend teardown and every allocation failure" {
    try nestedEvaluation(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, nestedEvaluation, .{});
}

fn callableDescriptors(allocator: std.mem.Allocator) !void {
    const source =
        \\const make = func (step: U32) => return @code.quote (func (value: U32) => return do:
        \\  let step = @u32.add value (@code.lift step)
        \\  let value = 1
        \\  break @u32.add step value)
        \\const first = make 1
        \\const second = make 2
        \\const same = @descriptor.same (@code.describe first).result (@code.describe second).result
        \\const answer: U32 = if same then (@code.run second) 39 else 0
    ;
    try evaluatedSource(allocator, source);
}
test "typed staging callable descriptors retain their exact closure row certificate through OOM" {
    try callableDescriptors(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, callableDescriptors, .{});
}
test "typed staging callable descriptors preserve declared operation effects" {
    try evaluatedSource(std.testing.allocator,
        \\effect Read: Unit -> U32
        \\const effectful = @code.quote (func () => return Read ())
        \\const pure = @code.quote (func () => return 42)
        \\const same = @descriptor.same (@code.describe effectful).result (@code.describe pure).result
        \\const answer: U32 = if same then 0 else 42
    );
}

fn ambientStagingRows(allocator: std.mem.Allocator) !void {
    try law(allocator,
        \\const generated: code [U32, row {}] = @code.quote 42
        \\const spliced = @code.quote (do:
        \\  use @array.length #[1]
        \\  break @code.splice generated)
        \\entry const answer = func (host: Unit -> Unit ! {Foreign}) => return do:
        \\  use host ()
        \\  break @code.emit spliced
    , null);
    try law(allocator,
        \\effect Read: Unit -> U32
        \\const generated: code [U32, row {Read}] = @code.quote (Read ())
        \\const broader: Unit -> U32 ! {Read, Foreign} = func () => return Read ()
        \\const composed: code [U32, row {Read, Foreign}] = @code.quote (do:
        \\  use ignored <- broader ()
        \\  break @code.splice generated)
        \\entry const answer = func (host: Unit -> U32 ! {Foreign}) => return do:
        \\  let provider = @effect.provider Read host
        \\  break do provider:
        \\    break @code.emit generated
    , null);
}
test "typed staging contributes latent rows without closing the surrounding ambient through OOM" {
    try ambientStagingRows(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ambientStagingRows, .{});
}
test "typed staging row widening retains missing handlers callback rows and pure run restrictions" {
    const a = std.testing.allocator;
    try law(a, "effect Read: Unit -> U32\nconst generated = @code.quote (Read ())\nentry const answer: Unit -> U32 ! {} = func () => return @code.emit generated", .effect_mismatch);
    try law(a, "effect Read: Unit -> U32\nconst generated = @code.quote (Read ())\nconst answer = @code.run generated", .const_effect);
    try law(a, "const generated = @code.quote (func (host: Unit -> Unit ! {Foreign}) => return host ())\nconst emitted = @code.run generated\nconst pure: (Unit -> Unit ! {}) -> Unit = emitted", .effect_mismatch);
}
