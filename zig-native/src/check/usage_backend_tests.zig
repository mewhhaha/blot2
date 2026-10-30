const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("../backend/core_backend.zig");
const a = std.testing.allocator;

fn emit(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
}

fn lower(source: []const u8) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    var checked = try checker.checkModule(a, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &syntax, &pool, &checked);
    errdefer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

test "borrow backend scalar callbacks retain complete replay and allocation failure ownership" {
    const source =
        \\const inspect = func (owner: unique U32) => return @usage.borrow_mut owner (func loan => return @u32.add (@usage.read loan) (@usage.read loan))
        \\entry const run = func () => return inspect 9
    ;
    var module = try lower(source);
    defer module.deinit(a);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    var first = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer first.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), first.diagnostic);
    var retained = try backend.compileWithOptions(a, &.{module}, 1, .{ .previous = &first.capture.?, .retain_artifacts = true, .artifact_replay = true });
    defer retained.deinit(a);
    try std.testing.expect(retained.diagnostic == null);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "borrow backend never supplies missing sort zero value representations" {
    var module = try lower(
        \\entry const unresolved: forall [a] => a -> a = func value => return value
    );
    defer module.deinit(a);
    var has_value_binder = false;
    for (module.types.nodes) |node| if (node.tag == .bound and node.b == 0) {
        has_value_binder = true;
    };
    try std.testing.expect(has_value_binder);
    var result = try backend.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic != null);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
}

test "borrow backend preserves loan identity and rejects malformed read descriptors" {
    var module = try lower(
        \\const inspect = func (owner: unique U32) => return @usage.borrow_mut owner (func loan => return @usage.read loan)
        \\entry const run = func () => return inspect 9
    );
    defer module.deinit(a);
    var read: core.Id = 0;
    var region: @import("types.zig").Id = 0;
    for (module.nodes, 0..) |node, index| if (node.tag == .usage_read) {
        read = @intCast(index);
    };
    for (module.types.nodes, 0..) |node, index| if (node.tag == .bound and node.b == 2) {
        region = @intCast(index);
    };
    try std.testing.expect(read != 0 and region != 0);
    const original_region = module.types.nodes[region];
    module.types.nodes[region].c = module.bodies[0].binding;
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
    module.types.nodes[region] = original_region;
    try @import("usage_core.zig").validate(&module);
    const original = module.nodes[read];
    for ([_]core.Node{
        .{ .tag = .usage_read, .a = original.a, .b = 3, .ty = original.ty },
        .{ .tag = .usage_read, .a = original.a, .b = original.b, .c = 1, .ty = original.ty },
        .{ .tag = .usage_read, .a = original.a, .b = original.b, .ty = @import("types.zig").f32_type },
    }) |malformed| {
        module.nodes[read] = malformed;
        var result = try backend.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic != null);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    }
    module.nodes[read] = original;
    try emit(a, &module);
}

test "resource backend cleanup journals preserve replay and every failed allocation" {
    var module = try lower(
        \\entry const run = func () => return @resource.scope (func () => return 9) (func owner => return ()) (func loan => return @usage.read loan)
    );
    defer module.deinit(a);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    const before = @import("core_snapshot_tests.zig").stamp(module);
    var first = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer first.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), first.diagnostic);
    var retained = try backend.compileWithOptions(a, &.{module}, 1, .{ .previous = &first.capture.?, .retain_artifacts = true, .artifact_replay = true });
    defer retained.deinit(a);
    try std.testing.expect(retained.diagnostic == null);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
    for (module.nodes) |*node| if (node.tag == .resource_scope) {
        const saved = node.b;
        node.b = node.a;
        var rejected = try backend.compile(a, &.{module}, 1);
        defer rejected.deinit(a);
        try std.testing.expect(rejected.diagnostic != null);
        try std.testing.expectEqual(@as(usize, 0), rejected.bytes.len);
        node.b = saved;
    };
}

test "resource reference backend journals preserve replay and every failed allocation" {
    var module = try lower(
        \\entry const run = func (value: U32) => return @resource.scope (func () => return #[value, @u32.add value 1]) (func owner => return ()) (func loan => return @usage.length loan)
    );
    defer module.deinit(a);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    const before = @import("core_snapshot_tests.zig").stamp(module);
    var first = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer first.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), first.diagnostic);
    var retained = try backend.compileWithOptions(a, &.{module}, 1, .{ .previous = &first.capture.?, .retain_artifacts = true, .artifact_replay = true });
    defer retained.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), retained.diagnostic);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "usage sharing backend preserves managed owners replay and rejects unsealed conversion authority" {
    var module = try lower(
        \\const shared = func (owner: unique (Array U32)) => return @usage.share owner
        \\entry const run = func (value: U32) => return do:
        \\  let values = shared #[value, @u32.add value 1]
        \\  break @u32.add (@usage.length values) (@usage.length values)
        \\entry const captured = func (value: U32) => return do:
        \\  let owner: unique (Array U32) = #[value, @u32.add value 1]
        \\  let transfer: once (Unit -> shared (Array U32)) = func () => return @usage.share owner
        \\  let shared = transfer ()
        \\  break @usage.length shared
    );
    defer module.deinit(a);
    const stamp = @import("core_snapshot_tests.zig").stamp(module);
    var first = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer first.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), first.diagnostic);
    var retained = try backend.compileWithOptions(a, &.{module}, 1, .{ .previous = &first.capture.?, .retain_artifacts = true, .artifact_replay = true });
    defer retained.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), retained.diagnostic);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(stamp, @import("core_snapshot_tests.zig").stamp(module));
    for (module.nodes) |*node| if (node.tag == .usage_share) {
        const original = node.*;
        node.ty = module.typeOf(node.a);
        var denied = try backend.compile(a, &.{module}, 1);
        defer denied.deinit(a);
        try std.testing.expect(denied.diagnostic != null);
        try std.testing.expectEqual(@as(usize, 0), denied.bytes.len);
        node.* = original;
        const input = module.types.nodes[module.typeOf(node.a)];
        module.types.nodes[module.typeOf(node.a)].b = @backingInt(@import("types.zig").UsageKind.shared);
        var invalid = try backend.compile(a, &.{module}, 1);
        defer invalid.deinit(a);
        try std.testing.expect(invalid.diagnostic != null);
        try std.testing.expectEqual(@as(usize, 0), invalid.bytes.len);
        module.types.nodes[module.typeOf(node.a)] = input;
        try emit(a, &module);
    };
}

test "owning entry bridges box fresh inputs and publish typed persistent leases" {
    var module = try lower(
        \\entry const scalar = func (owner: unique U32) => return @usage.borrow owner (func loan => return @usage.read loan)
        \\entry const array = func (owner: unique (Array U32)) => return @usage.borrow owner (func loan => return @usage.length loan)
        \\entry const float = func (owner: shared F32) => return @usage.read owner
    );
    defer module.deinit(a);
    var admitted = try backend.compile(a, &.{module}, 1);
    defer admitted.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), admitted.diagnostic);
    var escaped = try lower(
        \\entry const escaped = func () : unique U32 => return 9
    );
    defer escaped.deinit(a);
    var rejected = try backend.compile(a, &.{escaped}, 1);
    defer rejected.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), rejected.diagnostic);
    try std.testing.expect(std.mem.find(u8, rejected.bytes, "blot:owner_token") != null);
}

test "resource acquired owners execute through exact Core and backend contracts" {
    var module = try lower(
        \\const forward = func (owner: unique U32) => return owner
        \\const make = func () : unique U32 ! {Foreign} => return @resource.acquire (func () => return 9) (func owner => return ())
        \\entry const run = func () => return do:
        \\  use owner <- make ()
        \\  use value <- @usage.borrow owner (func loan => return @usage.read loan)
        \\  use @resource.release (forward owner)
        \\  break value
        \\entry const merged = func (choose: Bool) => return do:
        \\  let initial_left: unique (Array U32) = #[1]
        \\  let initial_right: unique (Array U32) = #[1, 2]
        \\  let left = @usage.share initial_left
        \\  let right = @usage.share initial_right
        \\  if choose:
        \\    use first <- @resource.acquire (func () => return #[1, 2]) (func owner => return ())
        \\    left := @usage.share first
        \\    use second <- @resource.acquire (func () => return #[1, 2, 3]) (func owner => return ())
        \\    right := @usage.share second
        \\  break @u32.add (@usage.length left) (@usage.length right)
        \\entry const broken = func () => return do:
        \\  for ever:
        \\    use owner <- make ()
        \\    break
        \\  break 9
    );
    defer module.deinit(a);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    var admitted = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer admitted.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), admitted.diagnostic);
    var retained = try backend.compileWithOptions(a, &.{module}, 1, .{ .previous = &admitted.capture.?, .retain_artifacts = true, .artifact_replay = true });
    defer retained.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), retained.diagnostic);
    try std.testing.expectEqualSlices(u8, admitted.bytes, retained.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    // Startup has no invocation journal authority, even if a forged owned
    // body retains a bounds-correct acquisition copied from a runtime helper.
    const T = @import("types.zig");
    const acquire = for (module.nodes, 0..) |node, index| {
        if (node.tag == .resource_acquire) break @as(u32, @intCast(index));
    } else return error.TestUnexpectedResult;
    var mutated_startup = false;
    for (module.bodies) |*body| {
        if (body.root != acquire) continue;
        mutated_startup = true;
        const saved_body = body.*;
        const saved_binding = module.bindings[body.binding];
        const owner_type = module.typeOf(acquire);
        body.parameters.len = 0;
        module.bindings[body.binding].ty = owner_type;
        module.bindings[body.binding].scheme.root = owner_type;
        try std.testing.expectEqual(T.Tag.usage, module.types.node(owner_type).tag);
        try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&module));
        body.* = saved_body;
        module.bindings[body.binding] = saved_binding;
        try @import("frozen_core_validation.zig").validate(a, &module, .{});
    }
    try std.testing.expect(mutated_startup);
    var escaped = try lower("entry const escaped = func () => return @resource.acquire (func () => return 9) (func owner => return ())\n");
    defer escaped.deinit(a);
    var rejected = try backend.compile(a, &.{escaped}, 1);
    defer rejected.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), rejected.diagnostic);
    try std.testing.expect(std.mem.find(u8, rejected.bytes, "blot:owner_token") != null);
}

test "resource closed aggregate backend retains child roles through replay and failed allocation" {
    var module = try lower(
        \\entry const run = func (value: U32) => return @resource.scope (func () => return {left: value, right: #[#[value, 7], #[9]]}) (func owner => return ()) (func loan => return 42)
        \\entry const tuple = func (value: U32) => return do:
        \\  use owner <- @resource.acquire (func () => return (value, #[value, 8])) (func owned => return ())
        \\  let transfer: once (Unit -> Unit ! {Foreign}) = func () => return @resource.release owner
        \\  use transfer ()
        \\  break 42
    );
    defer module.deinit(a);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    const before = @import("core_snapshot_tests.zig").stamp(module);
    var first = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer first.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), first.diagnostic);
    var retained = try backend.compileWithOptions(a, &.{module}, 1, .{ .previous = &first.capture.?, .retain_artifacts = true, .artifact_replay = true });
    defer retained.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), retained.diagnostic);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "resource nominal closed storage backend owns opaque references through replay and every failed allocation" {
    var module = try lower(
        \\type Box a is data = #Box a
        \\opaque type Secret = {left: U32, right: Array U32}
        \\type Tree a is data = #Leaf a | #Branch (Tree a, Tree a)
        \\entry const boxed = func (value: U32) => return @resource.scope (func () => return #Box #[value, 7]) (func owner => return ()) (func loan => return 42)
        \\entry const tree = func (value: U32) => return @resource.scope (func () => return #Branch (#Leaf value, #Leaf 9)) (func owner => return ()) (func loan => return 42)
        \\entry const secret = func (value: U32) => return do:
        \\  use owner <- @resource.acquire (func () => return #Secret {right: #[value, 8], left: value}) (func owned => return ())
        \\  let transfer: once (Unit -> Unit ! {Foreign}) = func () => return @resource.release owner
        \\  use transfer ()
        \\  break 42
    );
    defer module.deinit(a);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    const before = @import("core_snapshot_tests.zig").stamp(module);
    var first = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer first.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), first.diagnostic);
    var retained = try backend.compileWithOptions(a, &.{module}, 1, .{ .previous = &first.capture.?, .retain_artifacts = true, .artifact_replay = true });
    defer retained.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), retained.diagnostic);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "once public entry guards retain exact multiplicity through replay and failed publication" {
    var module = try lower(
        \\entry const run: once (U32 -> U32) = func value => return value
        \\entry const failing: once (U32 -> U32) = func value => return @panic "once failure"
        \\entry const ordinary = func (value: U32) => return value
    );
    defer module.deinit(a);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    const before = @import("core_snapshot_tests.zig").stamp(module);
    var first = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer first.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), first.diagnostic);
    try std.testing.expect(std.mem.find(u8, first.bytes, "blot:multiplicity") != null);
    var retained = try backend.compileWithOptions(a, &.{module}, 1, .{ .previous = &first.capture.?, .retain_artifacts = true, .artifact_replay = true });
    defer retained.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), retained.diagnostic);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "public owner leases and owned cleanup roles survive replay and allocation failure" {
    var module = try lower(
        \\entry const make = func (drop: cleanup ((unique U32) -> Unit ! {Foreign})) => return @resource.acquire (func () => return 42) drop
        \\entry const consume = func (owner: unique U32) => return @usage.borrow owner (func loan => return @usage.read loan)
        \\entry const pass = func (owner: unique U32) => return owner
        \\entry const share = func (owner: unique U32) => return @usage.share owner
        \\entry const read = func (owner: shared U32) => return @usage.borrow owner (func loan => return @usage.read loan)
    );
    defer module.deinit(a);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    const before = @import("core_snapshot_tests.zig").stamp(module);
    var first = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer first.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), first.diagnostic);
    try std.testing.expect(std.mem.find(u8, first.bytes, "blot:cleanup/2") != null);
    var retained = try backend.compileWithOptions(a, &.{module}, 1, .{ .previous = &first.capture.?, .retain_artifacts = true, .artifact_replay = true });
    defer retained.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), retained.diagnostic);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "public owner admission refuses forged callable storage authority" {
    var module = try lower("entry const invalid = func (owner: unique U32) => return ()\n");
    defer module.deinit(a);
    const function = for (module.types.nodes, 0..) |node, id| {
        if (node.tag == .function) break @as(u32, @intCast(id));
    } else return error.TestUnexpectedResult;
    const owner = for (module.types.nodes) |*node| {
        if (node.tag == .usage and node.b == @backingInt(@import("types.zig").UsageKind.unique)) break node;
    } else return error.TestUnexpectedResult;
    owner.a = function;
    var result = try backend.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic != null);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
}

test "structured host cleanup schemas retain source roles through replay and every failed allocation" {
    var module = try lower(
        \\type Tree a is data = #Leaf a | #Branch (Tree a, Tree a)
        \\opaque type Secret = {items: Array U32, nonce: U32}
        \\entry const record = func (drop: cleanup ((unique {items: Array U32, nonce: U32}) -> Unit ! {Foreign})) => return @resource.scope (func () => return {nonce: 7, items: #[1, 2]}) drop (func loan => return 42)
        \\entry const tree = func (drop: cleanup ((unique (Tree U32)) -> Unit ! {Foreign})) => return @resource.scope (func () => return #Branch (#Leaf 7, #Leaf 9)) drop (func loan => return 42)
        \\entry const opaque_data = func (drop: cleanup ((unique Secret) -> Unit ! {Foreign})) => return @resource.scope (func () => return #Secret {items: #[1, 2], nonce: 7}) drop (func loan => return 42)
        \\entry const owner = func (drop: cleanup ((unique {items: Array U32, nonce: U32}) -> Unit ! {Foreign})) => return @resource.acquire (func () => return {nonce: 7, items: #[1, 2]}) drop
        \\entry const release = func (owner: unique {items: Array U32, nonce: U32}) => return @resource.release owner
    );
    defer module.deinit(a);
    try @import("frozen_core_validation.zig").validate(a, &module, .{});
    const before = @import("core_snapshot_tests.zig").stamp(module);
    var first = try backend.compileWithOptions(a, &.{module}, 1, .{ .retain_artifacts = true, .artifact_replay = true });
    defer first.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), first.diagnostic);
    try std.testing.expect(std.mem.find(u8, first.bytes, "blot:cleanup_data") != null);
    var retained = try backend.compileWithOptions(a, &.{module}, 1, .{ .previous = &first.capture.?, .retain_artifacts = true, .artifact_replay = true });
    defer retained.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), retained.diagnostic);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}
