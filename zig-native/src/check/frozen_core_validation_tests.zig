const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const ast = @import("../parse/ast.zig");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("check.zig");
const V = @import("frozen_core_validation.zig");
const a = std.testing.allocator;
const mixed_source =
    \\type Point is data = #Point { x: U32 }
    \\type Bucket is data = #Bucket { points: Array Point }
    \\const make = fn (initial: Bucket) => do:
    \\  let bucket = initial
    \\  return fn (index: U32) => do:
    \\    bucket.points[index].x := do:
    \\      let other = #[40]
    \\      other[0] := @u32.add self 2
    \\      return other[0]
    \\    return bucket.points[index].x
    \\entry const run = fn () -> U32 => (make (#Bucket { points: #[#Point { x: 1 }] })) 0
;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), lexed.diagnostics.items.len);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    for (tree.diagnostics.items) |d| std.debug.print("parse error {d}: {s} source={s}\n", .{ d.start, d.message(), source });
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |d| std.debug.print("fixture error {d}: {s}\n", .{ d.span.start, d.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &pool, &checked);
    result.unit = 1;
    errdefer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}

fn digest(module: *const core.Module) u64 {
    var h = std.hash.Wyhash.init(0);
    inline for (@typeInfo(core.Module).@"struct".field_names) |name| {
        const info = @typeInfo(@FieldType(core.Module, name));
        if (info == .pointer and info.pointer.size == .slice) h.update(std.mem.sliceAsBytes(@field(module, name)));
    }
    h.update(std.mem.sliceAsBytes(module.types.nodes));
    h.update(std.mem.sliceAsBytes(module.types.extra));
    h.update(std.mem.sliceAsBytes(module.types.effects.rows));
    h.update(std.mem.sliceAsBytes(module.types.effects.labels));
    h.update(std.mem.sliceAsBytes(module.types.operations));
    return h.final();
}
fn verified(allocator: std.mem.Allocator, module: *const core.Module) !void {
    const before = digest(module);
    try V.validate(allocator, module, .{});
    try std.testing.expectEqual(before, digest(module));
}

test "portable typed staging validates complete shapes and rejects forged operands and stage references" {
    var m = try lower(a,
        \\const make = fn (step: U32) => @code.quote (fn (value: U32) => @u32.add value (@code.lift step))
        \\const generated = make 2
        \\const inspected = @code.describe generated
        \\const fields = @descriptor.fields (@code.describe (@code.quote {number: 1})).result
        \\const same = @descriptor.same fields.number inspected.result
        \\entry const answer = fn (value: U32) => (@code.emit generated) value
    );
    defer m.deinit(a);
    try verified(a, &m);
    const staging = @import("typed_staging.zig");
    var count: usize = 0;
    for (m.nodes, 0..) |*n, id| {
        if (n.tag != .staging) continue;
        count += 1;
        const saved = n.*;
        n.c = std.math.maxInt(u32);
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
        n.* = saved;
        n.a = @intCast(id);
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
        n.* = saved;
        n.ty = T.boolean;
        if (saved.c != @backingInt(staging.Op.same)) try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
        n.* = saved;
        if (saved.c == @backingInt(staging.Op.lift)) {
            // The operand remains the same well-typed U32 parameter, but a bare
            // future-stage reference must not acquire its earlier stage's value.
            n.* = m.nodes[n.a];
            try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
            n.* = saved;
        }
    }
    try std.testing.expect(count >= 5);
    try verified(a, &m);
}

fn stagedRoundtrip(allocator: std.mem.Allocator, bytes: []const u8, answer: u32) !void {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var m = try format.decode(core.Module, allocator, bytes, key);
    defer format.deinit(allocator, &m);
    try verified(allocator, &m);
    var session = try @import("../eval/core_eval.zig").Session.init(allocator, &.{m});
    defer session.deinit();
    const value = try session.value(.{ .unit = 1, .binding = answer });
    try std.testing.expectEqual(@as(u32, 42), value.bits);
}

test "portable typed staging reconstructs named loop carries after producer teardown through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a,
            \\const sum = fn (values: Array U32) => do:
            \\  let total = 0
            \\  for value in values:
            \\    if @u32.eq value 0:
            \\      break
            \\    if @u32.eq value 20:
            \\      total := @u32.add total value
            \\    else:
            \\      total := @u32.add value total
            \\  return total
            \\const generated = @code.quote (sum #[20, 22])
            \\const answer: U32 = @code.run generated
        );
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging rejects loop carry and merge ownership forgeries" {
    var m = try lower(a,
        \\const sum = fn (values: Array U32) => do:
        \\  let total = 0
        \\  for value in values:
        \\    if @u32.eq value 20:
        \\      total := @u32.add total value
        \\    else:
        \\      total := @u32.add value total
        \\  return total
        \\const generated = @code.quote (sum #[20, 22])
    );
    defer m.deinit(a);
    try verified(a, &m);
    const quote = m.node(m.bodies[m.bodies.len - 1].root);
    const rows = m.bodies[m.bodies.len - 1].closed_rows;
    var remaining: usize = 65536;
    _ = try @import("staging_core.zig").namedCall(&m, quote.a, rows, &remaining);
    const carry = &m.loop_carries[0];
    const saved_carry = carry.*;
    carry.backedge = carry.outgoing;
    remaining = 65536;
    try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, quote.a, rows, &remaining));
    carry.* = saved_carry;
    const merge = &m.merges[0];
    const saved_merge = merge.*;
    merge.then_binding = merge.else_binding;
    remaining = 65536;
    try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, quote.a, rows, &remaining));
    merge.* = saved_merge;
    try verified(a, &m);
}

test "portable typed staging owns future local scope graphs after producer teardown through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a,
            \\type State a is effect = {get: Unit -> a, set: a -> Unit}
            \\const local = fn (value: U32) => @effect.scope (fn (state: State U32) => value)
            \\const generated = @code.quote (local 42)
            \\const answer = 42
        );
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging owns handled future effects and fresh scope providers through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a,
            \\effect Read: Unit -> U32
            \\type State a is effect = {get: Unit -> a, set: a -> Unit}
            \\const plain = @code.quote (do (@effect.provider Read (fn () => 42)):
            \\  return Read ())
            \\const local = fn (initial: U32) => @effect.scope (fn (state: State U32) => do:
            \\  let pair = do (@effect.state state.get state.set initial):
            \\    use previous <- state.get ()
            \\    use state.set (@u32.add previous 2)
            \\    return state.get ()
            \\  let (last, result) = pair
            \\  return result)
            \\const scoped = @code.quote (local 40)
            \\const answer: U32 = @code.run plain
        );
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

fn namedProviderRoundtrip(allocator: std.mem.Allocator, consumer_bytes: []const u8, producer_bytes: []const u8) !void {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var producer = try format.decode(core.Module, allocator, producer_bytes, key);
    defer format.deinit(allocator, &producer);
    var consumer = try format.decode(core.Module, allocator, consumer_bytes, key);
    defer format.deinit(allocator, &consumer);
    try V.validate(allocator, &consumer, .{ .units = &.{&producer} });
    var session = try @import("../eval/core_eval.zig").Session.init(allocator, &.{ consumer, producer });
    defer session.deinit();
    const value = try session.value(.{ .unit = consumer.unit, .binding = consumer.bodies[consumer.bodies.len - 1].binding });
    try std.testing.expectEqual(@as(u32, 42), value.bits);
}

test "portable typed staging named provider callbacks retain local and foreign producer principals through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var producer = try lower(a, "const callback = fn () => 42\n");
    defer producer.deinit(a);
    producer.unit = 2;
    var consumer = try lower(a,
        \\effect Read: Unit -> U32
        \\const callback = fn () => 42
        \\const generated = @code.quote (do (@effect.provider Read callback):
        \\  return Read ())
        \\const answer: U32 = @code.run generated
    );
    defer consumer.deinit(a);
    try verified(a, &consumer);
    const implementation = for (consumer.nodes) |node| {
        if (node.tag == .effect_provider) break node.b;
    } else return error.TestUnexpectedResult;
    const reference = &consumer.references[consumer.node(implementation).a];
    reference.unit = producer.unit;
    reference.binding = producer.bodies[1].binding;
    try V.validate(a, &consumer, .{ .units = &.{&producer} });
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &consumer, .{}));
    const root = producer.bodies[1].root;
    const saved = producer.nodes[root];
    producer.nodes[root] = .{ .tag = .constant, .ty = T.boolean, .a = 1 };
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &consumer, .{ .units = &.{&producer} }));
    producer.nodes[root] = saved;
    const consumer_bytes = try format.encode(a, key, consumer);
    defer a.free(consumer_bytes);
    const producer_bytes = try format.encode(a, key, producer);
    defer a.free(producer_bytes);
    try namedProviderRoundtrip(a, consumer_bytes, producer_bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, namedProviderRoundtrip, .{ consumer_bytes, producer_bytes });
}

test "portable typed staging earlier lift operands retain their actual affine stage owner through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    const sources = [_][]const u8{
        \\const consume = fn (value: unique U32) => @usage.borrow value (fn loan => @usage.read loan)
        \\const make = fn (value: unique U32) => @code.quote (@code.lift (consume value))
        \\const generated = make 42
        \\const answer: U32 = @code.run generated
        ,
        \\const consume = fn (value: unique U32) => @usage.borrow value (fn loan => @usage.read loan)
        \\const make = fn (value: unique U32) => @code.quote (@code.quote (@code.lift (@code.lift (consume value))))
        \\const generated = @code.run (make 42)
        \\const answer: U32 = @code.run generated
        ,
        \\const consume = fn (value: unique U32) => @usage.borrow value (fn loan => @usage.read loan)
        \\const make = fn (value: unique U32) => @code.quote (@code.lift (consume value))
        \\const spliced = fn (value: unique U32) => @code.quote (@code.splice (make value))
        \\const answer: U32 = @code.run (spliced 42)
        ,
        \\const consume = fn (value: unique U32) => @usage.borrow value (fn loan => @usage.read loan)
        \\const make = fn (value: unique U32) => do:
        \\  let build: once (Unit -> code [U32, row {}]) = fn () => @code.quote (@code.lift (consume value))
        \\  return build ()
        \\const answer: U32 = @code.run (make 42)
        ,
    };
    for (sources) |source| {
        var m = try lower(a, source);
        defer m.deinit(a);
        try verified(a, &m);
        const bytes = try format.encode(a, key, m);
        defer a.free(bytes);
        const answer = m.bodies[m.bodies.len - 1].binding;
        try stagedRoundtrip(a, bytes, answer);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
    }
}

test "portable typed staging rejects a forged repeated earlier affine move across lifts" {
    var m = try lower(a,
        \\const consume = fn (value: unique U32) => @usage.borrow value (fn loan => @usage.read loan)
        \\const make = fn () => do:
        \\  let left: unique U32 = 20
        \\  let right: unique U32 = 22
        \\  return @code.quote (@u32.add (@code.lift (consume left)) (@code.lift (consume right)))
        \\const answer: U32 = @code.run (make ())
    );
    defer m.deinit(a);
    try verified(a, &m);
    var references: [2]u32 = undefined;
    var count: usize = 0;
    for (m.nodes) |node| {
        if (node.tag != .staging or node.c != @backingInt(@import("typed_staging.zig").Op.lift)) continue;
        const operands = m.children(node.a);
        try std.testing.expectEqual(@as(usize, 1), operands.len);
        references[count] = m.node(operands[0]).a;
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
    m.references[references[1]].binding = m.references[references[0]].binding;
    try std.testing.expectError(error.InvalidArtifact, @import("usage_core.zig").validate(&m));
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
}

test "portable typed staging future affine parameters keep independent usage owners" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var m = try lower(a,
        \\const generated = @code.quote (fn (value: unique U32) => do:
        \\  let first = value
        \\  return first)
        \\const emitted = @code.emit generated
        \\const answer = 42
    );
    defer m.deinit(a);
    try verified(a, &m);
    const body = m.closures[0].body;
    const children = m.children(body);
    try std.testing.expectEqual(@as(usize, 2), children.len);
    const binding = m.node(children[0]);
    const returned = &m.nodes[children[1]];
    const saved = returned.a;
    returned.a = binding.b;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    returned.a = saved;
    try verified(a, &m);
    const bytes = try format.encode(a, key, m);
    defer a.free(bytes);
    const answer = m.bodies[m.bodies.len - 1].binding;
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging future loans retain their lexical callback owner" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    const sources = [_][]const u8{
        \\const generated = @code.quote (fn (value: unique U32) => @usage.borrow value (fn loan => @usage.read loan))
        \\const emitted = @code.emit generated
        \\const answer = 42
        ,
        \\const read: unique U32 -> U32 = fn value => @usage.borrow value (fn loan => @usage.read loan)
        \\const generated = @code.quote (fn (value: unique U32) => read value)
        \\const emitted = @code.emit generated
        \\const answer = 42
        ,
        \\const generated = @code.quote (fn (value: unique U32) => @usage.borrow value (fn loan => do:
        \\  let read = fn () => @usage.read loan
        \\  return read ()))
        \\const emitted = @code.emit generated
        \\const answer = 42
        ,
    };
    for (sources) |source| {
        var m = try lower(a, source);
        defer m.deinit(a);
        try verified(a, &m);
        const borrowed = for (m.types.nodes) |node| {
            if (node.tag == .usage and node.b == @backingInt(T.UsageKind.borrow)) break node;
        } else return error.TestUnexpectedResult;
        const region = &m.types.nodes[borrowed.c];
        const owner = region.c;
        region.c = 0;
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
        region.c = owner;
        try verified(a, &m);
        const bytes = try format.encode(a, key, m);
        defer a.free(bytes);
        const answer = m.bodies[m.bodies.len - 1].binding;
        try stagedRoundtrip(a, bytes, answer);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
    }
}

test "portable typed staging loan captures reject phantom missing and escaping executable owners" {
    var m = try lower(a,
        \\const generated = @code.quote (fn (value: unique U32) => @usage.borrow value (fn loan => do:
        \\  let read = fn () => @usage.read loan
        \\  return read ()))
        \\const answer = 42
    );
    defer m.deinit(a);
    try verified(a, &m);
    const closure = for (m.closures) |*callback| {
        if (m.node(callback.body).tag == .usage_read and callback.captures.len == 1) break callback;
    } else return error.TestUnexpectedResult;
    const body = closure.body;
    const captures = closure.captures;
    closure.body = m.bodies[m.bodies.len - 1].root;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    closure.body = body;
    closure.captures.len = 0;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    closure.captures = captures;
    // Its selected callable and result headers still promise U32. The actual
    // body now returns the borrowed owner instead of reading its scalar value.
    closure.body = m.node(body).a;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    closure.body = body;
    try verified(a, &m);
}

test "portable typed staging resource bodies retain cleanup loan and effect owners" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    const sources = [_][]const u8{
        \\const generated = @code.quote (fn () => @resource.scope (fn () => 42) (fn owner => ()) (fn loan => @usage.read loan))
        \\const emitted = @code.emit generated
        \\const answer = 42
        ,
        \\const generated = @code.quote (fn () => do:
        \\  use owner <- @resource.acquire (fn () => 42) (fn value => ())
        \\  use @resource.release owner
        \\  return 42)
        \\const emitted = @code.emit generated
        \\const answer = 42
        ,
    };
    for (sources) |source| {
        var m = try lower(a, source);
        defer m.deinit(a);
        try verified(a, &m);
        const cleanup = for (m.types.nodes, 0..) |node, index| {
            if (node.tag == .usage and node.b == @backingInt(T.UsageKind.cleanup)) break index;
        } else return error.TestUnexpectedResult;
        m.types.nodes[cleanup].b = @backingInt(T.UsageKind.once);
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
        m.types.nodes[cleanup].b = @backingInt(T.UsageKind.cleanup);
        try verified(a, &m);
        const bytes = try format.encode(a, key, m);
        defer a.free(bytes);
        const answer = m.bodies[m.bodies.len - 1].binding;
        try stagedRoundtrip(a, bytes, answer);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
        const quote = for (m.nodes) |node| {
            if (node.tag == .staging and node.c == @backingInt(@import("typed_staging.zig").Op.quote)) break node;
        } else return error.TestUnexpectedResult;
        var remaining: usize = 65536;
        const saved_types = try a.dupe(T.Node, m.types.nodes);
        defer a.free(saved_types);
        for (m.types.nodes) |*node| if (node.tag == .function or node.tag == .demand) {
            node.c = 0;
        };
        try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").quoteEffects(&m, quote, m.bodies[1].closed_rows, &remaining));
        @memcpy(m.types.nodes, saved_types);
    }
}

test "frozen operation declarations own generic argument shapes and signatures through teardown and OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var m = try lower(a,
        \\type State a is effect = {get: Unit -> a, set: a -> Unit}
        \\effect Read: Unit -> U32
        \\const answer = 42
    );
    defer m.deinit(a);
    try verified(a, &m);
    try std.testing.expectEqual(@as(usize, 3), m.operation_names.len);
    var generic: usize = 0;
    for (m.operation_names) |header| {
        try std.testing.expect(header.parameter != 0 and header.result != 0);
        if (header.variables.len == 0) {
            try std.testing.expectEqual(T.unit, header.parameter);
            try std.testing.expectEqual(T.u32_type, header.result);
        } else {
            generic += 1;
            try std.testing.expectEqual(@as(u32, 1), header.variables.len);
            try std.testing.expectEqual(@as(u32, 1), header.parameters.len);
            const variable = m.types.list(header.variables)[0];
            try std.testing.expectEqual(variable, m.types.list(header.parameters)[0]);
            try std.testing.expect(header.parameter == variable or header.result == variable);
        }
    }
    try std.testing.expectEqual(@as(usize, 2), generic);
    const saved = m.operation_names[0];
    m.operation_names[0].parameter = @intCast(m.types.nodes.len);
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.operation_names[0] = saved;
    m.operation_names[0].result = 0;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.operation_names[0] = saved;
    try verified(a, &m);
    const bytes = try format.encode(a, key, m);
    defer a.free(bytes);
    const answer = m.bodies[m.bodies.len - 1].binding;
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging request handlers retain independent declared operation signatures through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var m = try lower(a,
        \\effect Read: Unit -> U32
        \\const generated = @code.quote (do:
        \\  let calculation = @computation (fn () => Read ())
        \\  for request in @requests calculation:
        \\    case request of
        \\      effect Read () =>
        \\        yield 42
        \\      complete value =>
        \\        return value)
        \\const answer: U32 = @code.run generated
    );
    defer m.deinit(a);
    try verified(a, &m);
    const header = &m.operation_names[0];
    const result_type = header.result;
    header.result = T.boolean;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    header.result = result_type;
    const arm = &m.request_arms[0];
    const operation = arm.operation;
    arm.operation = T.foreign_operation;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    arm.operation = operation;
    try verified(a, &m);
    const bytes = try format.encode(a, key, m);
    defer a.free(bytes);
    const answer = m.bodies[m.bodies.len - 1].binding;
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging request clauses retain foreign callback effects through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var m = try lower(a,
        \\effect Read: Unit -> U32
        \\const generated = @code.quote (fn (host: Unit -> U32 ! {Foreign}) => do:
        \\  let calculation = @computation (fn () => @u32.add (Read ()) 40)
        \\  for request in @requests calculation:
        \\    case request of
        \\      effect Read () =>
        \\        yield host ()
        \\      complete value =>
        \\        return value)
        \\const answer = 42
    );
    defer m.deinit(a);
    try verified(a, &m);
    const action = m.types.node(m.request_loops[0].action_type);
    try std.testing.expect(std.mem.findScalar(T.Effects.Label, m.types.rowLabels(action.c), T.foreign_operation) != null);
    m.types.nodes[m.request_loops[0].action_type].c = 0;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.types.nodes[m.request_loops[0].action_type] = action;
    try verified(a, &m);
    const bytes = try format.encode(a, key, m);
    defer a.free(bytes);
    const answer = m.bodies[m.bodies.len - 1].binding;
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging unused request handlers preserve actual computation row variance through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var m = try lower(a,
        \\effect Read: Unit -> U32
        \\const generated = @code.quote (do:
        \\  let calculation = @computation (fn () => 42)
        \\  for request in @requests calculation:
        \\    case request of
        \\      effect Read () =>
        \\        yield 0
        \\      complete value =>
        \\        return value)
        \\const answer: U32 = @code.run generated
    );
    defer m.deinit(a);
    try verified(a, &m);
    const bytes = try format.encode(a, key, m);
    defer a.free(bytes);
    const answer = m.bodies[m.bodies.len - 1].binding;
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging reconstructs handled callback effects despite coordinated pure headers" {
    var m = try lower(a,
        \\effect Read: Unit -> U32
        \\effect Other: Unit -> U32
        \\const generated = @code.quote (do (@effect.provider Read (fn () => Other ())):
        \\  return Read ())
    );
    defer m.deinit(a);
    try verified(a, &m);
    const quote = m.node(m.bodies[m.bodies.len - 1].root);
    const rows = m.bodies[m.bodies.len - 1].closed_rows;
    const saved_types = try a.dupe(T.Node, m.types.nodes);
    defer a.free(saved_types);
    for (m.types.nodes) |*node| if (node.tag == .function or node.tag == .demand or node.tag == .provider) {
        node.c = 0;
    };
    var remaining: usize = 65536;
    try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").quoteEffects(&m, quote, rows, &remaining));
    @memcpy(m.types.nodes, saved_types);
    try verified(a, &m);
}

test "portable typed staging reconstructs uncalled future closure effects despite coordinated pure headers" {
    var m = try lower(a,
        \\effect Read: Unit -> U32
        \\const generated = @code.quote (fn () => Read ())
    );
    defer m.deinit(a);
    try verified(a, &m);
    for (m.types.nodes) |*node| if (node.tag == .function or node.tag == .demand) {
        node.c = 0;
    };
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
}

test "portable typed staging proves fresh same stage capability captures through owned lifetime edges and OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var m = try lower(a,
        \\type State a is effect = {get: Unit -> a, set: a -> Unit}
        \\const generated = @code.quote (@effect.scope (fn (state: State U32) => do:
        \\  let unused = state
        \\  let read = fn () => state.get ()
        \\  let pair = do (@effect.state state.get state.set 42):
        \\    return read ()
        \\  let (_, result) = pair
        \\  return result))
        \\const answer: U32 = @code.run generated
    );
    defer m.deinit(a);
    try verified(a, &m);
    const bytes = try format.encode(a, key, m);
    defer a.free(bytes);
    const answer = m.bodies[m.bodies.len - 1].binding;
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
    const read = for (m.nodes, 0..) |node, id| {
        if (node.tag != .closure) continue;
        const metadata = m.closures[node.a];
        if (metadata.captures.len == 1 and m.types.node(m.bindings[m.extra[metadata.captures.start]].ty).tag == .scoped) break @as(core.Id, @intCast(id));
    } else return error.TestUnexpectedResult;
    const unused = for (m.bindings, 0..) |binding, id| {
        if (binding.kind == .local and m.types.node(binding.ty).tag == .scoped) break @as(core.BindingId, @intCast(id));
    } else return error.TestUnexpectedResult;
    const captures = m.closures[m.node(read).a].captures;
    const actual = m.extra[captures.start];
    try std.testing.expect(actual != unused);
    m.extra[captures.start] = unused;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.extra[captures.start] = actual;
    try verified(a, &m);
}

test "portable typed staging named scope helpers retain future local capture row owners" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var m = try lower(a,
        \\type State a is effect = {get: Unit -> a, set: a -> Unit}
        \\const helper = fn (value: U32) => @effect.scope (fn (state: State U32) => do:
        \\  let read = fn () => state.get ()
        \\  let pair = do (@effect.state state.get state.set 40):
        \\    use previous <- read ()
        \\    use state.set (@u32.add previous value)
        \\    return read ()
        \\  let (_, result) = pair
        \\  return result)
        \\const generated = @code.quote (fn (value: U32) => helper value)
        \\const evaluated: U32 = @code.run (@code.quote (helper 2))
    );
    defer m.deinit(a);
    try verified(a, &m);
    const local = for (m.closures, 0..) |closure, index| {
        if (closure.qualifier != 0) break index;
    } else return error.TestUnexpectedResult;
    const qualifier = m.closures[local].qualifier;
    m.closures[local].qualifier = m.bodies[1].binding;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.closures[local].qualifier = qualifier;
    const owner = &m.bindings[qualifier];
    const scheme_root = owner.scheme.root;
    owner.scheme.root = T.u32_type;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    owner.scheme.root = scheme_root;
    const view = for (m.nodes, 0..) |node, index| {
        if (node.tag != .reference or m.reference(@intCast(index)).binding != qualifier) continue;
        if (node.ty != owner.ty) break node.ty;
    } else return error.TestUnexpectedResult;
    const row = m.types.nodes[view].c;
    m.types.nodes[view].c = 0;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.types.nodes[view].c = row;
    try verified(a, &m);
    const bytes = try format.encode(a, key, m);
    defer a.free(bytes);
    const answer = m.bodies[m.bodies.len - 1].binding;
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging reconstructs future local scope effects despite coordinated pure headers" {
    var m = try lower(a,
        \\type State a is effect = {get: Unit -> a, set: a -> Unit}
        \\effect Tick: Unit -> U32
        \\const generated = @code.quote (@effect.scope (fn (state: State U32) => Tick ()))
    );
    defer m.deinit(a);
    try verified(a, &m);
    const quote = m.node(m.bodies[m.bodies.len - 1].root);
    try std.testing.expectEqual(core.Tag.staging, quote.tag);
    var remaining: usize = 65536;
    try @import("staging_core.zig").quoteEffects(&m, quote, .{}, &remaining);
    const saved_types = try a.dupe(T.Node, m.types.nodes);
    defer a.free(saved_types);
    for (m.types.nodes) |*node| {
        if (node.tag == .function or node.tag == .demand) node.c = 0;
    }
    remaining = 65536;
    try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").quoteEffects(&m, quote, .{}, &remaining));
    @memcpy(m.types.nodes, saved_types);
    remaining = 1;
    try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").quoteEffects(&m, quote, .{}, &remaining));
}

test "portable typed staging owns roundtrip graphs after producer release through allocation failures" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a,
            \\const make = fn (step: U32) => @code.quote (do:
            \\  let value = 40
            \\  return @u32.add value (@code.lift step))
            \\const generated = make 2
            \\const answer: U32 = @code.run generated
        );
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "typed staging declaration projection retains exact inputs and invalidates same-type quoted edits" {
    const source =
        \\const make = fn (step: U32) => @code.quote (do:
        \\  let value = 40
        \\  return @u32.add value (@code.lift step))
        \\const generated = make 2
        \\const answer: U32 = @code.run generated
    ;
    var before = try lower(a, source);
    defer before.deinit(a);
    var after = try lower(a, source);
    defer after.deinit(a);
    const projection = @import("../reuse/declaration_projection.zig");
    for (before.bodies[1..]) |body| try std.testing.expect(try projection.definitionEqual(a, &before, &after, body.binding));
    var edits: usize = 0;
    for (after.nodes) |*node| {
        if (node.tag != .constant or node.a != 40) continue;
        edits += 1;
        node.a = 41;
        try verified(a, &after);
        try std.testing.expect(!try projection.definitionEqual(a, &before, &after, before.bodies[1].binding));
        // Consumers also read the generator's body through the dependency
        // fixed point; this local projection grants no transitive admission.
        node.a = 40;
    }
    try std.testing.expect(edits != 0);
    try std.testing.expect(try projection.definitionEqual(a, &before, &after, before.bodies[1].binding));
}

test "portable typed staging rejects forged pure rows on quoted operations and forced demands" {
    const sources = [_][]const u8{
        "effect Read: Unit -> U32\nconst generated = @code.quote (Read ())\n",
        "effect Read: Unit -> U32\nconst generated = @code.quote ((fn ~value => @demand value) (Read ()))\n",
    };
    for (sources) |source| {
        var m = try lower(a, source);
        defer m.deinit(a);
        try verified(a, &m);
        var forged: usize = 0;
        for (m.types.nodes, 0..) |n, id| {
            const shape = @import("typed_staging.zig").codeInfo(&m.types, @intCast(id)) orelse continue;
            if (shape.effects == 0) continue;
            forged += 1;
            const latent = m.types.nominalArguments(n)[1];
            const saved = m.types.nodes[latent].c;
            m.types.nodes[latent].c = 0;
            try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
            m.types.nodes[latent].c = saved;
        }
        try std.testing.expect(forged != 0);
        // Coordinated signature edits also cannot hide the operation actually
        // requested, or the operation in the force's actual suspension body.
        for (m.types.nodes) |*ty| {
            if (ty.tag == .function or ty.tag == .demand) ty.c = 0;
        }
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    }
}

test "portable typed staging admits named operation calls and rejects forged pure claims" {
    var m = try lower(a, "effect Read: Unit -> U32\nconst invoke = fn () => Read ()\nconst generated = @code.quote (invoke ())\n");
    defer m.deinit(a);
    try V.validateBounds(&m, .{});
    try verified(a, &m);
    for (m.types.nodes) |*ty| {
        if (ty.tag == .function or ty.tag == .demand) ty.c = 0;
    }
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
}

test "portable typed staging named calls retain unused declared effects without inventing pure authority" {
    const sources = [_][]const u8{
        "effect Read: Unit -> U32\nconst invoke: Unit -> U32 ! {Read} = fn () => 42\nconst generated = @code.quote (invoke ())\n",
        "effect Read: Unit -> U32\neffect Write: Unit -> Unit\nconst invoke: Unit -> U32 ! {Read, Write} = fn () => Read ()\nconst generated = @code.quote (invoke ())\n",
    };
    for (sources) |source| {
        var m = try lower(a, source);
        defer m.deinit(a);
        try verified(a, &m);
        const quote = m.node(m.bodies[m.bodies.len - 1].root);
        const call = m.call(quote.a);
        const selected = m.types.nodes[call.callee_type];
        m.types.nodes[call.callee_type].c = 0;
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
        m.types.nodes[call.callee_type] = selected;
        try verified(a, &m);
    }
}

test "portable typed staging named operation bodies survive producer release and all allocation failures" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a,
            \\effect Read: Unit -> U32
            \\const invoke = fn () => Read ()
            \\const helper = fn () => @u32.add (invoke ()) 2
            \\const generated = @code.quote (helper ())
            \\const provider = @effect.provider Read (fn () => 40)
            \\const answer: U32 = do provider:
            \\  return @code.emit generated
        );
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging named operation bodies reject identity result and scope forgeries" {
    var m = try lower(a,
        \\effect Read: Unit -> U32
        \\effect Other: Unit -> U32
        \\const helper = fn () => Read ()
        \\const generated = @code.quote (helper ())
    );
    defer m.deinit(a);
    try verified(a, &m);
    const operation = &m.operation_values[0];
    const saved = operation.*;
    operation.identity.decl += 1;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    operation.* = saved;
    const signature = m.types.nodes[operation.signature];
    m.types.nodes[operation.signature].b = T.boolean;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.types.nodes[operation.signature] = signature;
    operation.instance = .{ .unit = m.unit, .decl = 1 };
    var remaining: usize = 4096;
    const quote = for (m.nodes) |node| {
        if (node.tag == .staging) break node;
    } else return error.MissingQuote;
    try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, quote.a, m.bodies[m.bodies.len - 1].closed_rows, &remaining));
    operation.* = saved;
    try verified(a, &m);
}

test "portable typed staging foreign generic helpers retain exact producer body authority" {
    var producer = try lower(a, "const helper = fn value => value\n");
    defer producer.deinit(a);
    producer.unit = 2;
    var consumer = try lower(a, "const helper = fn value => value\nconst generated = @code.quote (helper 42)\n");
    defer consumer.deinit(a);
    const quote = consumer.node(consumer.bodies[consumer.bodies.len - 1].root);
    const call = &consumer.calls[consumer.node(quote.a).a];
    call.target = .{ .unit = producer.unit, .binding = producer.bodies[1].binding };
    const context: V.Context = .{ .units = &.{&producer} };
    try V.validate(a, &consumer, context);
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &consumer, .{}));
    const reference = producer.node(producer.bodies[1].root);
    producer.nodes[producer.bodies[1].root] = .{ .tag = .constant, .ty = T.u32_type, .a = 42 };
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &consumer, context));
    producer.nodes[producer.bodies[1].root] = reference;
    const original = consumer.types.nodes[call.callee_type];
    consumer.types.nodes[call.callee_type].b = T.boolean;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &consumer, context));
    consumer.types.nodes[call.callee_type] = original;
    try V.validate(a, &consumer, context);
}

test "portable typed staging never closes splice rows using an unrelated body certificate" {
    var m = try lower(a,
        \\const decoy = fn (value: U32) => @u32.add value 1
        \\const generated = @code.quote (@u32.eq (@code.splice (@code.quote 42)) 42)
    );
    defer m.deinit(a);
    try verified(a, &m);
    const closed = m.types.list(m.bodies[1].closed_rows);
    try std.testing.expect(closed.len != 0);
    const variable = closed[0];
    try std.testing.expect(std.mem.findScalar(u32, m.types.list(m.bodies[2].closed_rows), variable) == null);
    const row = for (m.types.effects.rows, 0..) |value, id| {
        if (value.tail == .variable and value.tail.variable == variable and value.labels.len == 0) break @as(u32, @intCast(id));
    } else return error.TestUnexpectedResult;
    const staging = @import("typed_staging.zig");
    var changed: usize = 0;
    for (m.nodes) |node| {
        if (node.tag != .staging or node.c != @backingInt(staging.Op.quote)) continue;
        const shape = staging.codeInfo(&m.types, node.ty).?;
        if (shape.result != T.u32_type) continue;
        const latent = m.types.nominalArguments(m.types.node(node.ty))[1];
        m.types.nodes[latent].c = row;
        changed += 1;
    }
    try std.testing.expect(changed != 0);
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
}

test "portable typed staging refuses scoped authority hidden in quoted closure capture tables" {
    var m = try lower(a,
        \\type State a is effect = {get: Unit -> a, set: a -> Unit}
        \\const generated = @code.quote (fn (value: U32) => value)
        \\entry const region = fn () => @effect.scope (fn (s: State U32) => 42)
    );
    defer m.deinit(a);
    try verified(a, &m);
    const scope_binding = for (m.bindings, 0..) |binding, id| {
        if (m.types.node(binding.ty).tag == .scoped) break @as(u32, @intCast(id));
    } else return error.TestUnexpectedResult;
    const closure = for (m.nodes) |node| {
        if (node.tag == .staging and node.c == @backingInt(@import("typed_staging.zig").Op.quote)) break m.nodes[node.a].a;
    } else return error.TestUnexpectedResult;
    const extra = m.extra;
    const forged = try a.alloc(u32, extra.len + 1);
    defer a.free(forged);
    @memcpy(forged[0..extra.len], extra);
    forged[extra.len] = scope_binding;
    const captures = m.closures[closure].captures;
    m.extra = forged;
    m.closures[closure].captures = .{ .start = @intCast(extra.len), .len = 1 };
    defer {
        m.extra = extra;
        m.closures[closure].captures = captures;
    }
    // The code/callable signature stays U32 -> U32. Its hidden captures are
    // independently checked rather than accepted from that plain shape.
    try @import("staging_core.zig").shapes(&m);
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
}

test "portable typed staging refuses earlier-stage plain callable capture tables" {
    var m = try lower(a,
        \\const earlier: Unit -> U32 = fn () => 42
        \\const generated = @code.quote (fn (value: U32) => value)
    );
    defer m.deinit(a);
    try verified(a, &m);
    const closure = m.nodes[m.nodes[m.bodies[2].root].a].a;
    const extra = m.extra;
    const forged = try a.alloc(u32, extra.len + 1);
    defer a.free(forged);
    @memcpy(forged[0..extra.len], extra);
    forged[extra.len] = m.bodies[1].binding;
    const captures = m.closures[closure].captures;
    m.extra = forged;
    m.closures[closure].captures = .{ .start = @intCast(extra.len), .len = 1 };
    defer {
        m.extra = extra;
        m.closures[closure].captures = captures;
    }
    try std.testing.expect(try @import("staging_core.zig").authorityFree(&m, m.bindings[forged[extra.len]].ty));
    try @import("staging_core.zig").shapes(&m);
    // There is no future reference node to catch this forged table entry.
    // A plain function shape cannot license a different stage's hidden graph.
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
}

test "normal frozen Core admits generic recursion, record payloads, loops, State and Requests" {
    const sources = [_][]const u8{
        "entry const identity = fn value => value\nentry const answer = fn () => identity 42\n",
        "const even = fn (n: U32) -> U32 => if @u32.eq n 0 then 42 else odd (@u32.sub n 1)\nconst odd = fn (n: U32) -> U32 => if @u32.eq n 0 then 42 else even (@u32.sub n 1)\nentry const answer = fn () => even 42\n",
        "data Pair = #Pair {left: U32, right: U32}\nentry const answer = fn () => do:\n  let #Pair payload = #Pair {left: 40, right: 2}\n  return @u32.add (@product.get payload 0) (@product.get payload 1)\n",
        "entry const answer = fn () => do:\n  let count = 0\n  for index in 0..10:\n    count := @u32.add self index\n  for ever:\n    if @u32.eq count 45:\n      break\n    count := 45\n  return count\n",
        @import("fixtures").source("request-fixtures/shadow-completion_payload_shadow.blot"),
        @import("fixtures").source("request-fixtures/template-local-effects.blot"),
        mixed_source,
    };
    for (sources) |source| {
        var m = try lower(a, source);
        defer m.deinit(a);
        try verified(a, &m);
    }
}

test "every allocation failure releases validation workspace and retains immutable Core" {
    var m = try lower(a, @import("fixtures").source("request-fixtures/template-local-effects.blot"));
    defer m.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, verified, .{&m});
}

test "shared scheme public slots and row carriers reject malformed frozen metadata" {
    var m = try lower(a,
        \\const twice: a -> a where { associated "add" a a a } = fn value => @type.call "add" value value
        \\const alias = twice
        \\entry const generic = fn value => alias value
    );
    defer m.deinit(a);
    try verified(a, &m);
    var uses: usize = 0;
    for (m.obligations) |*obligation| {
        if (obligation.kind != .callee_use) continue;
        uses += 1;
        const saved = obligation.*;
        const callee = &m.bindings[obligation.identity.decl];
        const variables = callee.public_variables;
        callee.public_variables.len = std.math.maxInt(u32);
        try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
        callee.public_variables = variables;
        const rows = callee.public_rows;
        callee.public_rows.start = std.math.maxInt(u32);
        try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
        callee.public_rows = rows;
        obligation.identity.decl = std.math.maxInt(u32);
        try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
        obligation.* = saved;
        obligation.ty = T.u32_type;
        try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
        obligation.* = saved;
        const product = m.types.node(obligation.ty);
        for (m.types.extra[product.a + variables.len ..][0..rows.len]) |carrier| {
            const original = m.types.nodes[carrier];
            m.types.nodes[carrier].a = T.boolean;
            try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
            m.types.nodes[carrier] = original;
        }
    }
    try std.testing.expect(uses != 0);
    var explicit_bindings: usize = 0;
    for (m.bindings) |*binding| {
        if (!binding.has_explicit) continue;
        explicit_bindings += 1;
        binding.has_explicit = false;
        try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
        binding.has_explicit = true;
    }
    try std.testing.expect(explicit_bindings != 0);
    try verified(a, &m);
}

test "retained header cycles reject without rejecting ordinary recursive bodies" {
    var m = try lower(a,
        \\const twice: a -> a where { associated "add" a a a } = fn value => @type.call "add" value value
        \\const alias = twice
        \\entry const generic = fn value => alias value
    );
    defer m.deinit(a);
    try verified(a, &m);
    var cycles: usize = 0;
    for (m.bindings, 0..) |binding, id| {
        for (m.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len]) |*use| {
            if (use.kind != .callee_use) continue;
            const callee = m.binding(use.identity.decl);
            if (binding.public_variables.len != callee.public_variables.len or binding.public_rows.len != callee.public_rows.len) continue;
            const original = use.*;
            use.identity.decl = @intCast(id);
            try V.validateBounds(&m, .{});
            try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
            use.* = original;
            cycles += 1;
        }
    }
    try std.testing.expect(cycles != 0);
    try verified(a, &m);
}

test "bounds reject overflow and every Core tag's interpreted reference before indexed reads" {
    var m = try lower(a, "entry const answer = fn () => do:\n  let values = #[40, 2]\n  return @u32.add (@array.get values 0) (@array.get values 1)\n");
    defer m.deinit(a);
    const id: usize = 1;
    const saved = m.nodes[id];
    defer m.nodes[id] = saved;
    for (std.meta.tags(core.Tag)) |tag| {
        if (tag == .invalid or tag == .constant or tag == .type_constructor) continue;
        m.nodes[id] = .{ .tag = tag, .op = .add, .ty = T.u32_type, .a = std.math.maxInt(u32), .b = std.math.maxInt(u32), .c = std.math.maxInt(u32) };
        try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
    }
    m.nodes[id] = saved;
    const root = m.bodies[1].root;
    const original = m.nodes[root];
    defer m.nodes[root] = original;
    m.nodes[root] = .{ .tag = .product, .ty = T.u32_type, .a = std.math.maxInt(u32), .b = std.math.maxInt(u32) };
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
    m.nodes[root] = .{ .tag = .array_op, .ty = T.u32_type, .a = 0, .b = 0, .c = @backingInt(core.ArrayOp.get) };
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
}

test "frozen demanded diagnostic display ranges reject stale and overflowing names" {
    var m = try lower(a, "type Box is data = #Box U32\nconst Box.read = fn value => 42\nconst select: a -> b where {field \"read\" a b} = fn value => value.read\nentry const answer = fn () => select (#Box 1)\n");
    defer m.deinit(a);
    try V.validateBounds(&m, .{});
    var nominal_names: usize = 0;
    for (m.nominals) |*nominal| {
        const saved = nominal.diagnostic_name;
        if (saved.len == 0) continue;
        nominal_names += 1;
        nominal.diagnostic_name = .{ .start = std.math.maxInt(u32), .len = 1 };
        try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
        nominal.diagnostic_name = saved;
        const origin = nominal.diagnostic_origin;
        nominal.diagnostic_origin = .{ .start = std.math.maxInt(u32), .len = 1 };
        try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
        nominal.diagnostic_origin = origin;
    }
    try std.testing.expect(nominal_names != 0);
    var field_names: usize = 0;
    for (m.obligations) |*obligation| {
        const saved = obligation.diagnostic_name;
        if (saved.len == 0) continue;
        field_names += 1;
        obligation.diagnostic_name = .{ .start = 1, .len = std.math.maxInt(u32) };
        try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
        obligation.diagnostic_name = saved;
    }
    try std.testing.expect(field_names != 0);
    try V.validateBounds(&m, .{});
}

test "structural cycles reject while recursive BindingRef and control targets remain legal" {
    var m = try lower(a, "entry const answer = fn (n: U32) -> U32 => if @u32.eq n 0 then 42 else answer (@u32.sub n 1)\n");
    defer m.deinit(a);
    try V.validate(a, &m, .{});
    const root = m.bodies[1].root;
    const original = m.nodes[root];
    m.nodes[root] = .{ .tag = .apply, .ty = original.ty, .a = root, .b = root };
    try V.validateBounds(&m, .{});
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.nodes[root] = original;
    const original_type = m.types.nodes[m.bindings[m.bodies[1].binding].ty];
    const ty = m.bindings[m.bodies[1].binding].ty;
    m.types.nodes[ty] = .{ .tag = .array, .a = ty };
    try V.validateBounds(&m, .{});
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.types.nodes[ty] = original_type;
    try V.validate(a, &m, .{});
}

test "caller scratch handles deep forward structural DAG without a fixed depth policy" {
    var m = try lower(a, "entry const answer = 42\n");
    defer m.deinit(a);
    const count = 4096;
    a.free(m.nodes);
    a.free(m.spans);
    a.free(m.merge_ranges);
    a.free(m.dispatch_signatures);
    m.nodes = try a.alloc(core.Node, count);
    m.spans = try a.alloc(core.Span, count);
    m.merge_ranges = try a.alloc(core.List, count);
    m.dispatch_signatures = try a.alloc(T.Id, count);
    @memset(m.spans, .{ .start = 0, .end = 0 });
    @memset(m.merge_ranges, .{});
    @memset(m.dispatch_signatures, 0);
    m.nodes[0] = .{ .tag = .invalid };
    for (m.nodes[1 .. count - 1], 1..) |*n, i| n.* = .{ .tag = .force, .ty = T.u32_type, .a = @intCast(i + 1) };
    m.nodes[count - 1] = .{ .tag = .constant, .ty = T.u32_type, .a = 42 };
    m.bodies[1].root = 1;
    const size = try V.scratchSize(&m);
    const colors = try a.alloc(u8, size);
    defer a.free(colors);
    const path = try a.alloc(V.Frame, size);
    defer a.free(path);
    try V.validateWithScratch(&m, .{}, .{ .colors = colors, .path = path });
    try std.testing.expectError(error.InvalidArtifact, V.validateWithScratch(&m, .{}, .{ .colors = colors[0 .. size - 1], .path = path }));
    m.nodes[count - 1] = .{ .tag = .force, .ty = T.u32_type, .a = 1 };
    try std.testing.expectError(error.InvalidArtifact, V.validateWithScratch(&m, .{}, .{ .colors = colors, .path = path }));
}

test "external owner context proves producer binding bounds and symbol dictionary bounds" {
    var m = try lower(a, "const identity = fn value => value\nentry const answer = identity 42\n");
    defer m.deinit(a);
    var producer = try lower(a, "const identity = fn value => value\nentry const answer = 42\n");
    defer producer.deinit(a);
    producer.unit = 7;
    m.calls[0].target = .{ .unit = 7, .binding = 1 };
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    try V.validate(a, &m, .{ .units = &.{&producer} });
    m.calls[0].target.binding = @intCast(producer.bindings.len);
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{ .units = &.{&producer} }));
}

test "row-operation type cycle, recycled catalogs, and physical field changes are never inferred away" {
    var m = try lower(a, @import("fixtures").source("request-fixtures/shadow-completion_payload_shadow.blot"));
    defer m.deinit(a);
    try V.validate(a, &m, .{});
    var row_id: u32 = 0;
    for (m.types.effects.rows, 0..) |r, i| if (r.labels.len != 0) {
        row_id = @intCast(i);
        break;
    };
    try std.testing.expect(row_id != 0);
    const label = m.types.effects.labels[m.types.effects.rows[row_id].labels.start];
    const old_args = m.types.operations[label].arguments;
    const old_extra = m.types.extra;
    const old_nodes = m.types.nodes;
    const args = try a.dupe(T.Id, old_extra);
    defer a.free(args);
    const nodes = try a.alloc(T.Node, old_nodes.len + 1);
    defer a.free(nodes);
    @memcpy(nodes[0..old_nodes.len], old_nodes);
    nodes[old_nodes.len] = .{ .tag = .provider, .a = T.u32_type, .c = row_id };
    const extra = try a.alloc(T.Id, args.len + 1);
    defer a.free(extra);
    @memcpy(extra[0..args.len], args);
    extra[args.len] = @intCast(old_nodes.len);
    m.types.nodes = nodes;
    m.types.extra = extra;
    m.types.operations[label].arguments = .{ .start = @intCast(args.len), .len = 1 };
    defer {
        m.types.nodes = old_nodes;
        m.types.extra = old_extra;
        m.types.operations[label].arguments = old_args;
    }
    try V.validateBounds(&m, .{});
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.types.effects.labels[m.types.effects.rows[row_id].labels.start] = @intCast(m.types.operations.len);
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
}

fn badField(m: *core.Module, comptime table: []const u8, comptime field: []const u8) !void {
    const records = @field(m, table);
    try std.testing.expect(records.len != 0);
    const slot = &@field(records[0], field);
    const saved = slot.*;
    defer slot.* = saved;
    slot.* = std.math.maxInt(u32);
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(m, .{}));
}
fn badSpan(m: *core.Module, comptime table: []const u8, comptime field: []const u8) !void {
    const records = @field(m, table);
    try std.testing.expect(records.len != 0);
    const slot = &@field(records[0], field);
    const saved = slot.*;
    defer slot.* = saved;
    slot.* = .{ .start = std.math.maxInt(u32), .len = std.math.maxInt(u32) };
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(m, .{}));
}
test "decoded catalogs reject malformed lists, references and contradictory local ownership" {
    var m = try lower(a, mixed_source);
    defer m.deinit(a);
    try V.validate(a, &m, .{});
    try badSpan(&m, "bodies", "parameters");
    try badSpan(&m, "nominals", "parameters");
    try badSpan(&m, "nominals", "variables");
    try badSpan(&m, "nominals", "constructors");
    try badSpan(&m, "projections", "variants");
    try badSpan(&m, "closures", "captures");
    try badSpan(&m, "closures", "closed_rows");
    try badSpan(&m, "updates", "path");
    try badSpan(&m, "updates", "selectors");
    try badField(&m, "parameters", "ty");
    try badField(&m, "projections", "result_type");
    try badField(&m, "update_steps", "result_type");
    try badField(&m, "updates", "root");
    try badField(&m, "closures", "body");
    const saved = m.bindings[1].target;
    m.bindings[1].target = .{ .binding = 2 };
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
    m.bindings[1].target = saved;
    const old_type = m.types.nodes[0];
    m.types.nodes[0].tag = .u32;
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{}));
    m.types.nodes[0] = old_type;
    try V.validate(a, &m, .{});

    var requests = try lower(a, @import("fixtures").source("request-fixtures/shadow-completion_payload_shadow.blot"));
    defer requests.deinit(a);
    try badSpan(&requests, "request_loops", "arms");
    try badSpan(&requests, "request_loops", "completion_state_bindings");
    try badSpan(&requests, "request_loops", "carries");
    try badField(&requests, "request_loops", "return_target");
    try badField(&requests, "request_loops", "completion_pattern");
    try badField(&requests, "request_arms", "operation");
    try badField(&requests, "operation_values", "signature");
    try badField(&requests, "loop_carries", "iteration");
    var matched = try lower(a, "data Pair = #Pair {left: U32, right: U32}\nentry const answer = fn () => case #Pair {left: 40, right: 2} of\n  #Pair payload => @product.get payload 0\n");
    defer matched.deinit(a);
    try badSpan(&matched, "match_arms", "rows");
    try badSpan(&matched, "pattern_rows", "patterns");
    try badSpan(&matched, "matches", "inputs");
    try badSpan(&matched, "matches", "arms");
    try V.validate(a, &matched, .{});
    try V.validate(a, &requests, .{});
}

test "complete validation rejects mixed extra-table domains with individually valid bounds" {
    var m = try lower(a, mixed_source);
    defer m.deinit(a);
    const old = m.types.nodes;
    const nodes = try a.alloc(T.Node, old.len + 1);
    defer a.free(nodes);
    @memcpy(nodes[0..old.len], old);
    var record: ?T.Node = null;
    for (old) |n| if (n.tag == .record and n.b != 0) {
        record = n;
        break;
    };
    const r = record orelse return error.TestUnexpectedResult;
    // The symbol number also lies in the type-ID domain, so bounds alone admit
    // it. Its same word cannot be remapped as both a symbol and a type identity.
    try std.testing.expect(m.types.extra[r.a] < m.types.nodes.len);
    nodes[old.len] = .{ .tag = .product, .a = r.a, .b = 1 };
    m.types.nodes = nodes;
    defer m.types.nodes = old;
    try V.validateBounds(&m, .{});
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
}

fn publicationFailures(allocator: std.mem.Allocator, source: []const u8) !void {
    var m = try lower(allocator, source);
    defer m.deinit(allocator);
    try verified(allocator, &m);
}
test "normal frontend publication and final validation clean up every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publicationFailures, .{mixed_source});
}

test "structural cycles through closure and loop catalogs reject without treating control backlinks as children" {
    var m = try lower(a, mixed_source);
    defer m.deinit(a);
    var id: ?core.Id = null;
    for (m.nodes, 0..) |n, i| if (n.tag == .closure) {
        id = @intCast(i);
        break;
    };
    const closure = id orelse return error.TestUnexpectedResult;
    const catalog = m.nodes[closure].a;
    const old = m.closures[catalog].body;
    m.closures[catalog].body = closure;
    try V.validateBounds(&m, .{});
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.closures[catalog].body = old;
    try V.validate(a, &m, .{});

    var loop = try lower(a, "entry const answer = fn () => do:\n  for ever:\n    return 42\n");
    defer loop.deinit(a);
    try V.validate(a, &loop, .{});
    var loop_id: ?core.Id = null;
    for (loop.nodes, 0..) |n, i| if (n.tag == .loop) {
        loop_id = @intCast(i);
        break;
    };
    const actual = loop_id orelse return error.TestUnexpectedResult;
    const body = loop.loops[loop.nodes[actual].a].body;
    loop.loops[loop.nodes[actual].a].body = actual;
    try V.validateBounds(&loop, .{});
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &loop, .{}));
    loop.loops[loop.nodes[actual].a].body = body;
    try V.validate(a, &loop, .{});
}

test "context symbol and source bounds reject while historical principal identities remain legal" {
    var m = try lower(a, mixed_source);
    defer m.deinit(a);
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{ .symbol_count = 1 }));
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&m, .{ .source_length = 1 }));
    var principal = try lower(a, "entry const identity = fn value => value\n");
    defer principal.deinit(a);
    var variable: ?usize = null;
    for (principal.types.nodes, 0..) |n, i| if (n.tag == .variable) {
        variable = i;
        break;
    };
    const id = variable orelse return error.TestUnexpectedResult;
    principal.types.nodes[id].a = std.math.maxInt(u32);
    principal.types.nodes[id].b = 937;
    try V.validate(a, &principal, .{});
    const old = principal.types.nodes;
    // A bounds-only rejected oversized table must not read beyond the actual
    // backing allocation; the fake slice is never published or traversed.
    principal.types.nodes = old.ptr[0 .. @as(usize, std.math.maxInt(u32)) + 1];
    try std.testing.expectError(error.InvalidArtifact, V.validateBounds(&principal, .{}));
    principal.types.nodes = old;
}

test "fully invalid bounds reject before requesting allocation" {
    var m = try lower(a, "entry const answer = 42\n");
    defer m.deinit(a);
    m.bodies[1].root = @intCast(m.nodes.len);
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    try std.testing.expectError(error.InvalidArtifact, V.validate(failing.allocator(), &m, .{}));
    try std.testing.expectEqual(@as(usize, 0), failing.alloc_index);
}

const named_future_source =
    \\const add = fn (value: U32) => @u32.add value 2
    \\const twice = fn (value: U32) => add (add value)
    \\const generated = @code.quote (twice 38)
    \\const answer: U32 = @code.run generated
;
test "portable typed staging admits exact owned monomorphic named future calls after roundtrip and allocation failures" {
    const format = @import("../reuse/dependency_format.zig");
    const key_: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a, named_future_source);
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key_, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}
test "portable typed staging named calls reject forged signatures foreign parameters and unrelated row certificates" {
    var m = try lower(a,
        \\const decoy = fn (value: U32) => value
        \\const helper = fn (value: U32) => @u32.add value 2
        \\const generated = @code.quote (helper 40)
    );
    defer m.deinit(a);
    try verified(a, &m);
    const body = m.bodies[2];
    const call_id = for (m.nodes, 0..) |node, id| {
        if (node.tag == .call and m.call(@intCast(id)).target.binding == body.binding) break @as(core.Id, @intCast(id));
    } else return error.MissingCall;
    const selected_id = m.call(call_id).callee_type;
    const original = m.types.nodes[selected_id];
    for ([_]u32{ 0, 1 }) |which| {
        if (which == 0) m.types.nodes[selected_id].a = T.boolean else m.types.nodes[selected_id].b = T.f32_type;
        try V.validateBounds(&m, .{});
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
        m.types.nodes[selected_id] = original;
    }
    m.types.nodes[selected_id].c = m.types.node(m.bindings[m.bodies[1].binding].ty).c;
    try V.validateBounds(&m, .{});
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.types.nodes[selected_id] = original;
    const reference = m.nodes[m.node(body.root).a].a;
    const saved = m.references[reference];
    m.references[reference].binding = m.bodyParameters(&m.bodies[1])[0].binding;
    try V.validateBounds(&m, .{});
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.references[reference] = saved;
    const scalar = m.nodes[body.root];
    m.nodes[body.root].c = 1;
    try V.validateBounds(&m, .{});
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.nodes[body.root] = scalar;
    try verified(a, &m);
}
test "portable typed staging named calls reconstruct effects despite coordinated pure target claims" {
    var m = try lower(a,
        \\effect Read: Unit -> U32
        \\const effectful = fn (value: U32) => Read ()
        \\const helper = fn (value: U32) => @u32.add value 2
        \\const generated = @code.quote (helper 40)
    );
    defer m.deinit(a);
    try verified(a, &m);
    for (m.nodes) |node| {
        if (node.tag != .call or m.calls[node.a].target.binding != m.bodies[2].binding) continue;
        m.calls[node.a].target.binding = m.bodies[1].binding;
    }
    const signature = m.bindings[m.bodies[1].binding].ty;
    m.types.nodes[signature].c = 0;
    try V.validateBounds(&m, .{});
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
}
test "portable typed staging row polymorphic calls reconstruct owned principals through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    const cases = [_][]const u8{
        "const apply = fn (callback: U32 -> U32) => callback 42\nconst generated = @code.quote (apply (fn (value: U32) => value))\nconst answer: U32 = @code.run generated\n",
        "const apply = fn callback => callback 42\nconst generated = @code.quote (apply (fn (value: U32) => value))\nconst answer: U32 = @code.run generated\n",
        \\effect Read: Unit -> U32
        \\const apply = fn callback => callback ()
        \\const generated = @code.quote (do (@effect.provider Read (fn () => 42)):
        \\  return apply (fn () => Read ()))
        \\const answer: U32 = @code.run generated
        ,
        \\effect Read: Unit -> U32
        \\const apply: (Unit -> U32 ! {| e}) -> U32 ! {| e} = fn callback => callback ()
        \\const generated = @code.quote (do (@effect.provider Read (fn () => 42)):
        \\  return apply (fn () => Read ()))
        \\const answer: U32 = @code.run generated
        ,
    };
    for (cases) |source| {
        var m = try lower(a, source);
        defer m.deinit(a);
        try verified(a, &m);
        const bytes = try format.encode(a, key, m);
        defer a.free(bytes);
        const answer = m.bodies[m.bodies.len - 1].binding;
        try stagedRoundtrip(a, bytes, answer);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
    }
}

test "portable typed staging row polymorphic calls reject erased effects and foreign row owners" {
    var m = try lower(a,
        \\effect Read: Unit -> U32
        \\const apply: (Unit -> U32 ! {| e}) -> U32 ! {| e} = fn callback => callback ()
        \\const other: (Unit -> U32 ! {| f}) -> U32 ! {| f} = fn callback => callback ()
        \\const generated = @code.quote (do (@effect.provider Read (fn () => 42)):
        \\  return apply (fn () => Read ()))
    );
    defer m.deinit(a);
    try verified(a, &m);
    const target = for (m.nodes) |node| {
        if (node.tag == .call) break m.calls[node.a];
    } else return error.TestUnexpectedResult;
    const signature = &m.types.nodes[target.callee_type];
    const saved_row = signature.c;
    try std.testing.expect(m.types.rowLabels(saved_row).len != 0);
    signature.c = 0;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    signature.c = saved_row;
    const owner = m.body(target.target.binding) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u32, 1), owner.scheme.row_variables.len);
    const foreign = for (m.bodies) |body| {
        if (body.binding != owner.binding and body.scheme.row_variables.len == 1) break m.types.list(body.scheme.row_variables)[0];
    } else return error.TestUnexpectedResult;
    const slot = &m.types.extra[owner.scheme.row_variables.start];
    const actual = slot.*;
    try std.testing.expect(actual != foreign);
    slot.* = foreign;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    slot.* = actual;
    try verified(a, &m);
}

test "portable typed staging explicitly typed higher order helpers keep future callback principals" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var m = try lower(a,
        \\const apply: (U32 -> U32 ! {}) -> U32 ! {} = fn callback => callback 42
        \\const generated = @code.quote (apply (fn (value: U32) -> U32 => value))
        \\const answer: U32 = @code.run generated
    );
    defer m.deinit(a);
    try verified(a, &m);
    const bytes = try format.encode(a, key, m);
    defer a.free(bytes);
    const answer = m.bodies[m.bodies.len - 1].binding;
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging retains sealed package identities and stored operations" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var m = try lower(a,
        \\type Item = exists [a] => (a, a -> U32)
        \\const make: Unit -> Item = fn () => pack [U32] (42, fn value => value) as Item
        \\const generated = @code.quote (make ())
        \\const read: Item -> U32 = fn item => unpack item as [a] value in (@product.get value 1) (@product.get value 0)
        \\const answer: U32 = read (@code.run generated)
    );
    defer m.deinit(a);
    try verified(a, &m);
    const bytes = try format.encode(a, key, m);
    defer a.free(bytes);
    const answer = m.bodies[m.bodies.len - 1].binding;
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging higher order global arguments prove their actual producer bodies" {
    var m = try lower(a,
        \\const identity: U32 -> U32 ! {} = fn value => value
        \\const apply: (U32 -> U32 ! {}) -> U32 ! {} = fn callback => callback 42
        \\const generated = @code.quote (apply identity)
    );
    defer m.deinit(a);
    try verified(a, &m);
    const body = m.bodies[1];
    const original = m.nodes[body.root];
    m.nodes[body.root].ty = T.boolean;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.nodes[body.root] = original;
    const reference = m.references[original.a];
    m.references[original.a].binding = m.bodyParameters(&m.bodies[2])[0].binding;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    m.references[original.a] = reference;
    try verified(a, &m);
}

test "portable typed staging generic helpers own repeated and nested substitutions through allocation failures" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a,
            \\const identity = fn value => value
            \\const pair = fn value => (identity value, identity value)
            \\const generated = @code.quote (@u32.add (@product.get (pair 40) 0) (@f32.to_u32 (identity 2.0)))
            \\const answer: U32 = @code.run generated
        );
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging generic helpers reject inconsistent and unowned substitutions" {
    var m = try lower(a,
        \\const identity = fn value => value
        \\const unrelated = fn value => value
        \\const generated = @code.quote (identity 42)
    );
    defer m.deinit(a);
    try verified(a, &m);
    const call_id = for (m.nodes, 0..) |node, id| {
        if (node.tag == .call) break @as(core.Id, @intCast(id));
    } else return error.MissingCall;
    const selected = m.call(call_id).callee_type;
    const original = m.types.nodes[selected];
    const saved_result = m.nodes[call_id].ty;
    m.types.nodes[selected].b = T.f32_type;
    m.nodes[call_id].ty = T.f32_type;
    var remaining: usize = 4096;
    try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, call_id, m.bodies[m.bodies.len - 1].closed_rows, &remaining));
    m.types.nodes[selected] = original;
    m.nodes[call_id].ty = saved_result;
    const target = m.call(call_id).target.binding;
    for (m.bodies) |*body| if (body.binding == target) {
        const variables = body.scheme.variables;
        body.scheme.variables = .{};
        remaining = 4096;
        try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, call_id, m.bodies[m.bodies.len - 1].closed_rows, &remaining));
        body.scheme.variables = variables;
        const variable = m.types.list(variables)[0];
        const other = for (m.bodies) |candidate| {
            if (candidate.binding != target and candidate.scheme.variables.len != 0) break m.types.list(candidate.scheme.variables)[0];
        } else return error.MissingUnrelatedVariable;
        try std.testing.expect(variable != other);
        const saved_node = m.types.nodes[other];
        const parameter = &m.parameters[body.parameters.start];
        const saved_parameter = parameter.ty;
        // Equal-looking mutable node payloads do not transfer binder ownership.
        m.types.nodes[other] = m.types.nodes[variable];
        parameter.ty = other;
        remaining = 4096;
        try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, call_id, m.bodies[m.bodies.len - 1].closed_rows, &remaining));
        parameter.ty = saved_parameter;
        m.types.nodes[other] = saved_node;
    };
    try verified(a, &m);
}

test "portable typed staging named helpers reconstruct pure producer data through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a,
            \\const identity = fn value => value
            \\const original = {amount: identity 40}
            \\const config = original
            \\const helper = fn (value: U32) => @u32.add config.amount value
            \\const generated = @code.quote (helper 2)
            \\const answer: U32 = @code.run generated
        );
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging producer data rejects runtime foreign and cyclic owners" {
    var m = try lower(a,
        \\const seed = @u32.add 39 1
        \\const helper = fn (value: U32) => @u32.add seed value
        \\const generated = @code.quote (helper 2)
    );
    defer m.deinit(a);
    try verified(a, &m);
    const call_id = for (m.nodes, 0..) |node, id| {
        if (node.tag == .call) break @as(core.Id, @intCast(id));
    } else return error.MissingCall;
    const owner = for (m.bodies) |*body| {
        if (body.binding != 0 and !body.is_function) break body;
    } else return error.MissingDataBody;
    owner.runtime = true;
    var remaining: usize = 4096;
    try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, call_id, m.bodies[m.bodies.len - 1].closed_rows, &remaining));
    owner.runtime = false;
    const read = for (m.nodes, 0..) |node, id| {
        if (node.tag == .reference and m.reference(@intCast(id)).binding == owner.binding) break @as(core.Id, @intCast(id));
    } else return error.MissingRead;
    const reference = &m.references[m.nodes[read].a];
    const saved_unit = reference.unit;
    reference.unit = 2;
    remaining = 4096;
    try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, call_id, m.bodies[m.bodies.len - 1].closed_rows, &remaining));
    reference.unit = saved_unit;
    const saved_root = owner.root;
    owner.root = read;
    remaining = 4096;
    try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, call_id, m.bodies[m.bodies.len - 1].closed_rows, &remaining));
    owner.root = saved_root;
    try verified(a, &m);
}

const nominal_descriptor_source =
    \\data Packet a = #Packet {payload: a, flag: Bool}
    \\data Choice a = #Left {shared: a, left: Bool} | #Right {shared: a, right: U32}
    \\const packet = @descriptor.fields (@code.describe (@code.quote #Packet {payload: 40, flag: #True})).result
    \\const choice = @descriptor.fields (@code.describe (@code.quote #Left {shared: 40, left: #True})).result
    \\const scalar = (@code.describe (@code.quote 1)).result
    \\const answer = if @descriptor.same packet.payload scalar then if @descriptor.same choice.shared scalar then 42 else 0 else 0
;
test "portable typed staging nominal descriptors reconstruct constructor substitutions through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a, nominal_descriptor_source);
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}
test "portable typed staging nominal descriptors reject private owners forged fields and missing binders" {
    var m = try lower(a, nominal_descriptor_source);
    defer m.deinit(a);
    try verified(a, &m);
    var changed = false;
    for (m.nominals, 0..) |*family, index| {
        if (family.variables.len == 0 or family.constructors.len != 1) continue;
        family.private = true;
        try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").shapes(&m));
        family.private = false;
        const constructor = &m.constructors[m.nominalConstructors(@intCast(index))[0]];
        const variables = constructor.scheme.variables;
        constructor.scheme.variables = .{};
        try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").shapes(&m));
        constructor.scheme.variables = variables;
        changed = true;
        break;
    }
    try std.testing.expect(changed);
    changed = false;
    for (m.nodes) |node| {
        if (node.tag != .staging or node.c != @backingInt(@import("typed_staging.zig").Op.fields)) continue;
        const output = m.types.node(node.ty);
        for (0..output.b) |index| {
            const field = m.types.recordField(output, index);
            const descriptor = m.types.node(field.ty);
            const arguments = @constCast(m.types.nominalArguments(descriptor));
            if (arguments.len != 1 or arguments[0] != T.u32_type) continue;
            arguments[0] = T.boolean;
            try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").shapes(&m));
            arguments[0] = T.u32_type;
            changed = true;
            break;
        }
        if (changed) break;
    }
    try std.testing.expect(changed);
    try verified(a, &m);
}

test "portable typed staging helper blocks own nested locals and generic calls through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a,
            \\const identity = fn value => do:
            \\  let kept = value
            \\  let nested = do:
            \\    let value = kept
            \\    return value
            \\  return nested
            \\const pair = fn value => do:
            \\  let left = identity value
            \\  let right = identity value
            \\  return (left, right)
            \\const generated = @code.quote (@u32.add (@product.get (pair 40) 0) (@f32.to_u32 (identity 2.0)))
            \\const answer: U32 = @code.run generated
        );
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging helper locals reject future reads caller capture duplicate owners and foreign returns" {
    var m = try lower(a,
        \\const leaf = fn (value: U32) => value
        \\const helper = fn (value: U32) => do:
        \\  let first = value
        \\  let second = leaf first
        \\  return second
        \\const unrelated = fn (value: U32) => do:
        \\  let foreign = value
        \\  return foreign
        \\const generated = @code.quote (helper 42)
    );
    defer m.deinit(a);
    try verified(a, &m);
    const helper = m.bodies[2];
    const children = m.children(helper.root);
    try std.testing.expectEqual(@as(usize, 3), children.len);
    const first = m.node(children[0]);
    const second = m.node(children[1]);
    const call_id = for (m.nodes, 0..) |node, id| {
        if (node.tag == .call and m.call(@intCast(id)).target.binding == helper.binding) break @as(core.Id, @intCast(id));
    } else return error.MissingCall;
    const rows = m.bodies[m.bodies.len - 1].closed_rows;
    for (0..4) |mutation| {
        var reference: ?*core.BindingRef = null;
        var saved_reference: core.BindingRef = undefined;
        var changed_node: ?*core.Node = null;
        var saved_node: core.Node = undefined;
        switch (mutation) {
            0 => {
                reference = &m.references[m.node(first.b).a];
                saved_reference = reference.?.*;
                reference.?.binding = second.a;
            },
            1 => {
                reference = &m.references[m.node(m.bodies[1].root).a];
                saved_reference = reference.?.*;
                reference.?.binding = first.a;
            },
            2 => {
                changed_node = &m.nodes[children[1]];
                saved_node = changed_node.?.*;
                changed_node.?.* = first;
            },
            3 => {
                changed_node = &m.nodes[children[2]];
                saved_node = changed_node.?.*;
                changed_node.?.b = m.bodies[3].root;
            },
            else => unreachable,
        }
        // Every index still names an existing owner. Check staging independently
        // of the ordinary capability/usage contracts on these changed bodies.
        var remaining: usize = 4096;
        try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, call_id, rows, &remaining));
        if (reference) |value| value.* = saved_reference;
        if (changed_node) |value| value.* = saved_node;
    }
    try verified(a, &m);
}

fn invocationContextLaw(allocator: std.mem.Allocator) !void {
    var producer = try lower(allocator, "const identity = fn value => value\n");
    defer producer.deinit(allocator);
    const context: V.Context = .{ .units = &.{&producer} };
    var image = try V.ContextImage.capture(allocator, context, context.units);
    defer image.deinit(allocator);
    try std.testing.expect(image.matches(context, context.units));
    try std.testing.expect(V.equivalentContext(context, context, context.units, context.units));
    const original = producer.bindings[1].scheme.generative;
    producer.bindings[1].scheme.generative = .{ .len = 2 };
    // Equal counts cannot certify a newly observed foreign invocation owner.
    try std.testing.expect(!image.matches(context, context.units));
    try std.testing.expect(!V.equivalentContext(context, context, context.units, context.units));
    var generative = try V.ContextImage.capture(allocator, context, context.units);
    defer generative.deinit(allocator);
    producer.bindings[1].scheme.generative = original;
    try std.testing.expect(image.matches(context, context.units));
    try std.testing.expect(!generative.matches(context, context.units));
    const leaf = producer.types.nodes[producer.types.nodes.len - 1];
    producer.types.nodes[producer.types.nodes.len - 1] = .{ .tag = .instance_version, .a = 1, .b = 1 };
    try std.testing.expect(!image.matches(context, context.units));
    try std.testing.expect(!V.equivalentContext(context, context, context.units, context.units));
    producer.types.nodes[producer.types.nodes.len - 1] = leaf;
    try std.testing.expect(image.matches(context, context.units));
}
test "foreign invocation authority declines validation context reuse under allocation failure" {
    try invocationContextLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, invocationContextLaw, .{});
}

fn unrelatedContextLaw(allocator: std.mem.Allocator) !void {
    var caller = try lower(allocator, "entry const identity = fn (value: U32) => value\n");
    defer caller.deinit(allocator);
    var sibling = try lower(allocator, "data Token = #Token U32\nconst identity = fn (value: U32) => value\n");
    defer sibling.deinit(allocator);
    sibling.unit = 2;
    const context: V.Context = .{ .units = &.{ &caller, &sibling } };
    var image = try V.ContextImage.capture(allocator, context, &.{&caller});
    defer image.deinit(allocator);
    try std.testing.expect(image.matches(context, &.{&caller}));
    // Features in an unobserved sibling do not activate this caller's source
    // validators. Rich callers themselves still decline without body receipts.
    sibling.has_usage_contracts = true;
    sibling.has_rank_contracts = true;
    sibling.has_numeric_proofs = true;
    try std.testing.expect(image.matches(context, &.{&caller}));
    try std.testing.expect(V.equivalentContext(context, context, &.{&caller}, &.{&caller}));
    try std.testing.expect(!image.matches(context, &.{&sibling}));
    var old_sibling = sibling;
    const nominals = try allocator.dupe(core.Nominal, sibling.nominals);
    old_sibling.nominals = nominals;
    defer allocator.free(old_sibling.nominals);
    const old_context: V.Context = .{ .units = &.{ &caller, &old_sibling } };
    const original = sibling.nominals[0];
    inline for (.{ "affine", "has_usage", "closed_storage" }) |field| {
        @field(sibling.nominals[0], field) = !@field(original, field);
        try std.testing.expect(!image.matches(context, &.{&caller}));
        try std.testing.expect(!V.equivalentContext(old_context, context, &.{&caller}, &.{&caller}));
        sibling.nominals[0] = original;
    }
    sibling.nominals[0].identity.decl += 1;
    try std.testing.expect(!image.matches(context, &.{&caller}));
    try std.testing.expect(!V.equivalentContext(old_context, context, &.{&caller}, &.{&caller}));
    sibling.nominals[0] = original;
    try std.testing.expect(image.matches(context, &.{&caller}));
    caller.has_rank_contracts = true;
    try std.testing.expect(!image.matches(context, &.{&caller}));
}

test "ordinary validation contexts ignore unrelated feature owners and own exact nominal facts through OOM" {
    try unrelatedContextLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, unrelatedContextLaw, .{});
}

const nominal_helper_source =
    \\data Packet a = #Packet {payload: a, flag: Bool}
    \\data Marker = #Marker {}
    \\data Choice a = #Left {shared: a, left: Bool} | #Right {shared: a, right: U32}
    \\data Single a = #Single {item: a}
    \\data Option a = #Absent | #Present a
    \\const make = fn value => #Packet {payload: value, flag: #True}
    \\const positional = fn value => #Packet (value, #True)
    \\const single = fn value => #Single value
    \\const present = fn value => #Present value
    \\const marker = fn () => #Marker {}
    \\const choose = fn (flag: Bool) => fn value => if flag then #Left {shared: value, left: flag} else #Right {shared: value, right: 0}
    \\const generated = @code.quote (make 42)
    \\const marked = @code.quote (marker ())
    \\const chosen = @code.quote (choose #True 42)
    \\const constructors = @code.quote {packet: positional 42, single: single 42, option: present 42}
    \\const answer: U32 = (@code.run chosen).shared
;
test "portable typed staging nominal helper bodies reconstruct payloads through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a, nominal_helper_source);
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}
test "portable typed staging nominal helpers retain private producer rights and reject foreign owners" {
    var m = try lower(a, nominal_helper_source);
    defer m.deinit(a);
    try verified(a, &m);
    const proof = @import("staging_core.zig");
    const call_id = for (m.nodes, 0..) |node, id| {
        if (node.tag != .call) continue;
        const target = m.call(@intCast(id)).target;
        const body = m.body(target.binding) orelse continue;
        if (m.node(body.root).tag == .construct and m.types.node(m.typeOf(body.root)).tag == .nominal and m.types.nominalArguments(m.types.node(m.typeOf(body.root))).len != 0) break @as(core.Id, @intCast(id));
    } else return error.MissingNominalHelper;
    const caller_rows = for (m.bodies) |caller| {
        const root = m.node(caller.root);
        if (root.tag == .staging and root.c == @backingInt(@import("typed_staging.zig").Op.quote) and root.a == call_id) break caller.closed_rows;
    } else return error.MissingQuoteOwner;
    var remaining: usize = 4096;
    const body = try proof.namedCall(&m, call_id, caller_rows, &remaining);
    const construction = m.node(body.root);
    const constructor = &m.constructors[construction.a];
    const family = &m.nominals[constructor.nominal];
    family.private = true;
    remaining = 4096;
    _ = try proof.namedCall(&m, call_id, caller_rows, &remaining);
    const identity = family.identity;
    family.identity.unit = m.unit + 1;
    remaining = 4096;
    try std.testing.expectError(error.InvalidArtifact, proof.namedCall(&m, call_id, caller_rows, &remaining));
    family.identity = identity;
    family.private = false;
    const variables = constructor.scheme.variables;
    constructor.scheme.variables = .{};
    remaining = 4096;
    try std.testing.expectError(error.InvalidArtifact, proof.namedCall(&m, call_id, caller_rows, &remaining));
    constructor.scheme.variables = variables;
    const arrow = &m.types.nodes[constructor.scheme.root];
    const input = arrow.a;
    arrow.a = T.boolean;
    remaining = 4096;
    try std.testing.expectError(error.InvalidArtifact, proof.namedCall(&m, call_id, caller_rows, &remaining));
    arrow.a = input;
    const payload = &m.nodes[construction.b];
    const payload_type = payload.ty;
    payload.ty = T.boolean;
    remaining = 4096;
    try std.testing.expectError(error.InvalidArtifact, proof.namedCall(&m, call_id, caller_rows, &remaining));
    payload.ty = payload_type;
    try verified(a, &m);
}
test "portable typed staging nominal helpers admit closed callable payloads and reject unowned rows and forged payload types" {
    var m = try lower(a,
        \\data Hidden = #Hidden {read: Unit -> U32}
        \\const relay = fn value => value
        \\const generated = @code.quote (relay (#Hidden {read: fn () => 42}))
    );
    defer m.deinit(a);
    try verified(a, &m);
    const staging_core = @import("staging_core.zig");
    const call_id = for (m.nodes, 0..) |node, id| {
        if (node.tag == .call) break @as(core.Id, @intCast(id));
    } else return error.MissingCall;
    const owner = for (m.bodies) |*body| {
        const root = m.node(body.root);
        if (root.tag == .staging and root.c == @backingInt(@import("typed_staging.zig").Op.quote) and root.a == call_id) break body;
    } else return error.MissingQuoteOwner;
    const caller_rows = owner.closed_rows;
    const call_ = m.call(call_id);
    // A pure closure stored in a nominal payload is ordinary closed data.
    var remaining: usize = 4096;
    try std.testing.expectEqual(call_.target.binding, (try staging_core.namedCall(&m, call_id, caller_rows, &remaining)).binding);
    const constructor = m.constructors[m.node(call_.arguments[0]).a];
    const field = &m.types.nodes[m.types.recordField(m.types.node(constructor.payload), 0).ty];
    const closure_type = for (m.nodes) |node| {
        if (node.tag == .closure) break &m.types.nodes[m.closures[node.a].function_type];
    } else return error.MissingClosure;
    const selected = &m.types.nodes[call_.callee_type];
    try std.testing.expect(field != closure_type and field != selected and closure_type != selected);
    // Payload data is proved through the nominal: a declared callable field
    // whose row the caller's closed rows do not own is rejected.
    const foreign_row = m.types.node(m.bindings[call_.target.binding].ty).c;
    const foreign = m.types.row(foreign_row).tail;
    try std.testing.expect(foreign == .variable and std.mem.findScalar(u32, m.types.list(caller_rows), foreign.variable) == null);
    const declared_row = field.c;
    field.c = foreign_row;
    remaining = 4096;
    try std.testing.expectError(error.InvalidArtifact, staging_core.namedCall(&m, call_id, caller_rows, &remaining));
    field.c = declared_row;
    // An owned open row still cannot inhabit the declared closed field.
    const use_tail = m.types.row(selected.c).tail;
    const owned = m.types.list(caller_rows);
    try std.testing.expect(use_tail == .variable and owned.len != 0 and owned[owned.len - 1] == use_tail.variable);
    const closure_row = closure_type.c;
    closure_type.c = selected.c;
    remaining = 4096;
    try std.testing.expectError(error.InvalidArtifact, staging_core.namedCall(&m, call_id, caller_rows, &remaining));
    closure_type.c = closure_row;
    const input = selected.a;
    selected.a = T.boolean;
    remaining = 4096;
    try std.testing.expectError(error.InvalidArtifact, staging_core.namedCall(&m, call_id, caller_rows, &remaining));
    selected.a = input;
    // Rows come from the enclosing body's certificate, so genuine caller rows
    // cannot vouch for a use row that certificate no longer owns.
    owner.closed_rows.len -= 1;
    remaining = 4096;
    try std.testing.expectError(error.InvalidArtifact, staging_core.namedCall(&m, call_id, caller_rows, &remaining));
    owner.closed_rows = caller_rows;
    remaining = 4096;
    _ = try staging_core.namedCall(&m, call_id, caller_rows, &remaining);
    try verified(a, &m);
}

fn malformedApplyCaptureLaw(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator,
        \\type Application is data = #Application {reset: Unit -> U32}
        \\const reset_scoped = fn application => fn () => do:
        \\  let #Application {reset} = application
        \\  return reset ()
    );
    defer module.deinit(allocator);
    try V.validate(allocator, &module, .{});
    const id: u32 = for (module.nodes, 0..) |node, index| {
        if (node.tag == .apply) break @intCast(index);
    } else return error.TestUnexpectedResult;
    const original = module.nodes[id];
    try std.testing.expect(@import("capability_flow.zig").coreCall(&module, @intCast(module.nodes.len)) == null);
    module.nodes[id].a = @intCast(module.nodes.len);
    try std.testing.expect(@import("capability_flow.zig").coreCall(&module, id) == null);
    try std.testing.expectError(error.InvalidArtifact, V.validate(allocator, &module, .{}));
    module.nodes[id] = original;
    module.nodes[id].b = @intCast(module.nodes.len);
    try std.testing.expect(@import("capability_flow.zig").coreCall(&module, id) == null);
    try std.testing.expectError(error.InvalidArtifact, V.validate(allocator, &module, .{}));
    module.nodes[id] = original;
    module.nodes[id].a = id;
    try std.testing.expect(@import("capability_flow.zig").coreCall(&module, id) == null);
    try std.testing.expectError(error.InvalidArtifact, V.validate(allocator, &module, .{}));
    module.nodes[id] = original;
    try V.validate(allocator, &module, .{});
}
test "captured nominal patterns reject malformed application chains before graph admission through OOM" {
    try malformedApplyCaptureLaw(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, malformedApplyCaptureLaw, .{});
}

const collection_helper_source =
    \\const first = fn items => @array.get items 0
    \\const count = fn items => @list.length (@list.from_array items)
    \\const select = fn (value: U32) => do:
    \\  let joined = @array.concat #[value] #[2]
    \\  let window = @array.slice joined 0 (count joined)
    \\  let restored = @array.from_list (@list.from_array window)
    \\  return @u32.add (first restored) (@array.get restored 1)
    \\const floating = @code.quote (first #[1.5])
    \\const generated = @code.quote (select 40)
    \\const answer: U32 = @code.run generated
;

test "portable typed staging collection helper bodies retain exact shapes through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a, collection_helper_source);
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging collection helpers reject forged inputs outputs and operations" {
    var m = try lower(a, collection_helper_source);
    defer m.deinit(a);
    try verified(a, &m);
    const quote = for (m.nodes) |node| {
        if (node.tag == .staging and node.c == @backingInt(@import("typed_staging.zig").Op.quote) and m.node(node.a).tag == .call and m.typeOf(node.a) == T.u32_type) break node;
    } else return error.MissingQuote;
    const owner = &m.bodies[m.bodies.len - 2];
    const staging = @import("staging_core.zig");
    for (m.nodes, 0..) |*node, id| {
        if (node.tag != .array_op) continue;
        const saved = node.*;
        const operation = m.arrayOperation(@intCast(id));
        var remaining: usize = 65536;
        node.ty = T.boolean;
        try std.testing.expectError(error.InvalidArtifact, staging.namedCall(&m, quote.a, owner.closed_rows, &remaining));
        node.* = saved;
        const arguments = m.children(@intCast(id));
        const input = &m.nodes[arguments[0]];
        const saved_input = input.*;
        input.ty = T.u32_type;
        remaining = 65536;
        try std.testing.expectError(error.InvalidArtifact, staging.namedCall(&m, quote.a, owner.closed_rows, &remaining));
        input.* = saved_input;
        if (operation == .get) {
            node.c = @backingInt(core.ArrayOp.concat);
            remaining = 65536;
            try std.testing.expectError(error.InvalidArtifact, staging.namedCall(&m, quote.a, owner.closed_rows, &remaining));
            node.* = saved;
        }
        if (operation == .length) {
            node.c = @backingInt(core.ArrayOp.cursor_has);
            remaining = 65536;
            try std.testing.expectError(error.InvalidArtifact, staging.namedCall(&m, quote.a, owner.closed_rows, &remaining));
            node.* = saved;
        }
    }
    try verified(a, &m);
}

const nominal_read_source =
    \\type Packet a is data = #Packet {item: a, shadow: a}
    \\type Choice a is data = #Left {item: a, flag: Bool} | #Right {padding: U32, item: a}
    \\const read = fn (packet: Packet a) => packet.item
    \\const shared = fn (choice: Choice a) => choice.item
    \\const add = fn (value: U32) => @u32.add (read (#Packet {shadow: 9, item: value})) (shared (#Right {padding: 9, item: 2}))
    \\const floating = @code.quote (read (#Packet {item: 1.5, shadow: 9.5}))
    \\const generated = @code.quote (add 40)
    \\const answer: U32 = @code.run generated
;

test "portable typed staging nominal readers retain common field owners through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a, nominal_read_source);
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging nominal readers reject wrong physical fields variants and families" {
    var m = try lower(a, nominal_read_source);
    defer m.deinit(a);
    try verified(a, &m);
    const quote = for (m.nodes) |node| {
        if (node.tag == .staging and node.c == @backingInt(@import("typed_staging.zig").Op.quote) and m.node(node.a).tag == .call and m.typeOf(node.a) == T.u32_type) break node;
    } else return error.MissingQuote;
    const rows = m.bodies[m.bodies.len - 2].closed_rows;
    const staging = @import("staging_core.zig");
    for (m.projections[1..]) |*projection| {
        if (m.types.node(projection.source_type).tag != .nominal) continue;
        const saved = projection.*;
        const variant = &m.projection_variants[projection.variants.start];
        const saved_variant = variant.*;
        variant.field = 1 - variant.field;
        var remaining: usize = 65536;
        try std.testing.expectError(error.InvalidArtifact, staging.namedCall(&m, quote.a, rows, &remaining));
        variant.* = saved_variant;
        variant.tag += 1;
        remaining = 65536;
        try std.testing.expectError(error.InvalidArtifact, staging.namedCall(&m, quote.a, rows, &remaining));
        variant.* = saved_variant;
        projection.variants.len -= 1;
        remaining = 65536;
        try std.testing.expectError(error.InvalidArtifact, staging.namedCall(&m, quote.a, rows, &remaining));
        projection.* = saved;
        projection.nominal.decl += 1;
        remaining = 65536;
        try std.testing.expectError(error.InvalidArtifact, staging.namedCall(&m, quote.a, rows, &remaining));
        projection.* = saved;
    }
    try verified(a, &m);
}

const statement_if_source =
    \\const helper = fn (value: U32) => do:
    \\  let kept = @u32.add value 40
    \\  if @u32.eq value 0:
    \\    let value = kept
    \\    return value
    \\  if @u32.eq value 1:
    \\    if @u32.eq kept 41:
    \\      return kept
    \\    else:
    \\      return 0
    \\  return @u32.add value 40
    \\const generated = @code.quote (helper 2)
    \\const unit_helper = fn (flag: Bool) => do:
    \\  if flag:
    \\    let value = 42
    \\const unit_generated = @code.quote (unit_helper #False)
    \\const unit_value = @code.run unit_generated
    \\const answer: U32 = @code.run generated
;
test "portable typed staging statement if suites retain branch locals and return owners through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a, statement_if_source);
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging statement if rejects foreign return owners branch leaks and fallthrough" {
    var m = try lower(a, statement_if_source);
    defer m.deinit(a);
    try verified(a, &m);
    const helper = m.bodies[1];
    const children = m.children(helper.root);
    const conditional = m.node(children[1]);
    const branch = m.children(conditional.b);
    const returned = m.node(branch[branch.len - 1]);
    const quote = for (m.nodes) |node| {
        if (node.tag == .staging and node.a != 0 and m.node(node.a).tag == .call) break node;
    } else return error.MissingQuote;
    const rows = m.bodies[2].closed_rows;
    for (0..5) |mutation| {
        const id = switch (mutation) {
            0 => branch[branch.len - 1],
            1 => children[children.len - 1],
            2, 3 => children[1],
            4 => helper.root,
            else => unreachable,
        };
        const saved = m.nodes[id];
        switch (mutation) {
            0 => m.nodes[id].b = conditional.b,
            // Same U32 result, but the reference belongs only to the branch.
            1 => m.nodes[id].a = returned.a,
            2 => m.nodes[id].a = m.node(children[0]).b,
            3 => m.nodes[id].c = helper.root,
            // Removing the final return must not certify a U32 fallthrough.
            4 => m.nodes[id].b -= 1,
            else => unreachable,
        }
        var remaining: usize = 65536;
        try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, quote.a, rows, &remaining));
        m.nodes[id] = saved;
    }
    try verified(a, &m);
}

test "portable typed staging statement if proves unselected effectful branches" {
    var m = try lower(a,
        \\effect Read: Unit -> U32
        \\const helper = fn (flag: Bool) => do:
        \\  if flag:
        \\    return Read ()
        \\  return 42
        \\const generated = @code.quote (helper #False)
    );
    defer m.deinit(a);
    const quote = m.node(m.bodies[m.bodies.len - 1].root);
    try std.testing.expectEqual(core.Tag.staging, quote.tag);
    var remaining: usize = 65536;
    _ = try @import("staging_core.zig").namedCall(&m, quote.a, m.bodies[m.bodies.len - 1].closed_rows, &remaining);
    // Coordinate a forged pure declaration and selected signature. Admission
    // must still inspect the unexecuted suite instead of trusting either row.
    const saved_types = try a.dupe(T.Node, m.types.nodes);
    defer a.free(saved_types);
    for (m.types.nodes) |*node| {
        if (node.tag == .function) node.c = 0;
    }
    remaining = 65536;
    try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, quote.a, m.bodies[m.bodies.len - 1].closed_rows, &remaining));
    @memcpy(m.types.nodes, saved_types);
}

const boolean_case_source =
    \\const helper = fn (flag: Bool) => fn (value: U32) => case flag of
    \\  #True => do:
    \\    let flag = value
    \\    return @u32.add flag 40
    \\  #False => do:
    \\    let value = @u32.add value 41
    \\    return value
    \\const generated = @code.quote (helper #False 1)
    \\const answer: U32 = @code.run generated
;
test "portable typed staging Boolean case reconstructs arm owners after producer teardown through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    var bytes: []u8 = undefined;
    var answer: u32 = 0;
    {
        var m = try lower(a, boolean_case_source);
        defer m.deinit(a);
        try verified(a, &m);
        answer = m.bodies[m.bodies.len - 1].binding;
        bytes = try format.encode(a, key, m);
    }
    defer a.free(bytes);
    try stagedRoundtrip(a, bytes, answer);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
}

test "portable typed staging Boolean case rejects missing overlapping forged and leaked arm owners" {
    var m = try lower(a, boolean_case_source);
    defer m.deinit(a);
    try verified(a, &m);
    const helper = m.bodies[1];
    const match_id = helper.root;
    const info = m.matchInfo(match_id);
    const arms = m.matchArms(match_id);
    const first = m.rowPatterns(m.armRows(arms[0])[0])[0];
    const second = m.rowPatterns(m.armRows(arms[1])[0])[0];
    const first_children = m.children(arms[0].body);
    const second_children = m.children(arms[1].body);
    const quote = m.node(m.bodies[2].root);
    const rows = m.bodies[2].closed_rows;
    for (0..11) |mutation| {
        const pattern = m.patterns[first];
        const arm = m.match_arms[info.arms.start];
        const match_ = m.matches[m.node(match_id).a];
        const returned = m.nodes[first_children[first_children.len - 1]];
        switch (mutation) {
            0 => m.patterns[first].a = m.patterns[second].a,
            1 => m.patterns[first].a = 2,
            2 => m.patterns[first].ty = T.u32_type,
            3 => m.matches[m.node(match_id).a].arms.len = 1,
            4 => m.match_arms[info.arms.start].guard = m.matchInputs(match_id)[0],
            5 => m.patterns[first].tag = .bind,
            6 => m.patterns[first].b = first,
            // The reference and return target have valid indices and U32
            // shapes, but belong exclusively to the other arm's block.
            7 => m.nodes[first_children[first_children.len - 1]].a = m.node(second_children[second_children.len - 1]).a,
            8 => m.nodes[first_children[first_children.len - 1]].b = arms[1].body,
            9 => m.match_arms[info.arms.start].rows.len = 0,
            // A valid Bool parameter reference cannot replace a U32 arm.
            10 => m.match_arms[info.arms.start].body = m.matchInputs(match_id)[0],
            else => unreachable,
        }
        var remaining: usize = 65536;
        try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, quote.a, rows, &remaining));
        m.patterns[first] = pattern;
        m.match_arms[info.arms.start] = arm;
        m.matches[m.node(match_id).a] = match_;
        m.nodes[first_children[first_children.len - 1]] = returned;
    }
    try verified(a, &m);
}

test "portable typed staging Boolean case reconstructs unselected effects despite forged pure rows" {
    var m = try lower(a,
        \\effect Read: Unit -> U32
        \\const helper = fn (flag: Bool) => case flag of
        \\  #True => Read ()
        \\  #False => 42
        \\const generated = @code.quote (helper #False)
    );
    defer m.deinit(a);
    const quote = m.node(m.bodies[m.bodies.len - 1].root);
    const saved_types = try a.dupe(T.Node, m.types.nodes);
    defer a.free(saved_types);
    for (m.types.nodes) |*node| {
        if (node.tag == .function) node.c = 0;
    }
    var remaining: usize = 65536;
    try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, quote.a, m.bodies[m.bodies.len - 1].closed_rows, &remaining));
    @memcpy(m.types.nodes, saved_types);
}

test "portable typed staging generic operation rows match permutations and retain comparison limits" {
    var nodes = [_]T.Node{ .{ .tag = .absent }, .{ .tag = .unit }, .{ .tag = .boolean }, .{ .tag = .u32 }, .{ .tag = .f32 }, .{ .tag = .never } };
    var extra = [_]T.Id{ T.u32_type, T.boolean };
    var operations = [_]T.Operation{
        .{ .identity = .{ .unit = 0, .decl = 0 } },
        .{ .identity = .{ .unit = 0, .decl = 1 } },
        .{ .identity = .{ .unit = 9, .decl = 2 }, .arguments = .{ .len = 1 } },
        .{ .identity = .{ .unit = 9, .decl = 2 }, .arguments = .{ .start = 1, .len = 1 } },
    };
    var rows = [_]T.Effects.Row{ .{}, .{ .labels = .{ .len = 2 } }, .{ .labels = .{ .start = 2, .len = 2 } } };
    var labels = [_]T.Effects.Label{ 2, 3, 3, 2 };
    var module = std.mem.zeroes(core.Module);
    module.types = .{ .nodes = &nodes, .extra = &extra, .operations = &operations, .effects = .{ .rows = &rows, .labels = &labels } };
    const matcher = @import("staging_type_match.zig");
    var remaining: usize = 128;
    try matcher.row(&module, 1, &module, 2, &remaining, 0);
    try std.testing.expect(remaining < 128);
    labels[2] = 2;
    remaining = 128;
    try std.testing.expectError(error.InvalidArtifact, matcher.row(&module, 1, &module, 2, &remaining, 0));
    labels[2] = 3;
    remaining = 1;
    try std.testing.expectError(error.InvalidArtifact, matcher.row(&module, 1, &module, 2, &remaining, 0));
    try std.testing.expectEqual(@as(usize, 0), remaining);
    remaining = 128;
    try std.testing.expectError(error.InvalidArtifact, matcher.row(&module, 1, &module, 2, &remaining, 127));
}

test "portable typed staging lifts preserve nominal usage authority before executable admission" {
    var module = try lower(a,
        \\type Box is data = #Box U32
        \\opaque type Other = U32
        \\const lifted = @code.quote (@code.lift (#Box 42))
        \\const sealed = @code.quote (@code.lift (#Other 43))
    );
    defer module.deinit(a);
    const S = @import("staging_core.zig");
    try S.shapes(&module);
    var checked: usize = 0;
    for (module.nominals) |*nominal| {
        if (nominal.identity.decl == 0) continue;
        checked += 1;
        try std.testing.expect(!nominal.has_usage);
        nominal.has_usage = true;
        try std.testing.expectError(error.InvalidArtifact, S.shapes(&module));
        nominal.has_usage = false;
        try S.shapes(&module);
    }
    try std.testing.expectEqual(@as(usize, 2), checked);
    try verified(a, &module);
}

fn returnedRankCapability(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator,
        \\const keep: forall [a] => a -> (forall [b] => b -> a) = fn first => fn second => first
        \\const held = fn (value: U32) => (keep value) #True
    );
    defer module.deinit(allocator);
    const body = for (module.bodies) |candidate| {
        if (candidate.parameters.len != 1) continue;
        if (module.parameters[candidate.parameters.start].ty == T.u32_type) break candidate;
    } else return error.TestExpectedBody;
    const flow = @import("capability_flow.zig");
    const terms = @import("capability_contracts.zig");
    const summary = module.bindings[body.binding].capability_parameters;
    if (!summary.present()) return error.MissingSourceCapability;
    const recipe = module.capability_contracts.header(body.binding, summary.arity()) orelse return error.TestExpectedContract;
    var store: terms.Store = .{};
    defer store.deinit(allocator);
    const derived = (try @import("capability_contract_core.zig").derive(allocator, &store, &module, body, summary)) orelse return error.TestExpectedContract;
    if (!try terms.equivalent(.{ .nodes = recipe.nodes, .words = recipe.words }, recipe.root, store.view(), derived)) return error.SourceCoreRelationshipMismatch;
    const call = flow.localCoreCall(&module, body.root) orelse return error.TestExpectedCall;
    try std.testing.expectEqual(@as(usize, 2), call.len);
    try std.testing.expect(call.bindings[0] != call.bindings[1]);
    const callee = module.bodies[module.bindings[call.target.binding].body_id];
    const closure_id = module.nodes[callee.root].a;
    const previous = module.closures[closure_id].parameter.binding;
    module.closures[closure_id].parameter.binding = call.bindings[0];
    try std.testing.expect(flow.localCoreCall(&module, body.root) == null);
    const refused = try @import("capability_contract_core.zig").derive(allocator, &store, &module, body, summary);
    try std.testing.expect(refused == null);
    module.closures[closure_id].parameter.binding = previous;
    module.closures[closure_id].body = @intCast(module.nodes.len);
    try std.testing.expect(flow.localCoreCall(&module, body.root) == null);
}
test "returned annotated universal calls retain exact source Core capability relationships and reject stolen binders through OOM" {
    try returnedRankCapability(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, returnedRankCapability, .{});
}

const data_case_sources = [_][]const u8{
    \\const helper = fn (value: U32) => case value of
    \\  0 => 40
    \\  value => @u32.add value 40
    \\const generated = @code.quote (helper 2)
    \\const answer: U32 = @code.run generated
    ,
    \\const helper = fn (pair: (U32, U32)) => case pair of
    \\  (left, right) => @u32.add left right
    \\const generated = @code.quote (helper (20, 22))
    \\const answer: U32 = @code.run generated
    ,
};
test "portable typed staging scalar and product case helpers own complete arm binders through OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    for (data_case_sources) |source| {
        var bytes: []u8 = undefined;
        var answer: u32 = 0;
        {
            var m = try lower(a, source);
            defer m.deinit(a);
            try verified(a, &m);
            answer = m.bodies[m.bodies.len - 1].binding;
            bytes = try format.encode(a, key, m);
        }
        defer a.free(bytes);
        try stagedRoundtrip(a, bytes, answer);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
    }
}

test "portable typed staging scalar and product cases reject missing coverage forged literals and leaked arm locals" {
    var m = try lower(a, data_case_sources[0]);
    defer m.deinit(a);
    try verified(a, &m);
    const match_id = m.bodies[1].root;
    const match_index = m.node(match_id).a;
    const info = m.matchInfo(match_id);
    const arms = m.matchArms(match_id);
    const first = m.rowPatterns(m.armRows(arms[0])[0])[0];
    const second = m.rowPatterns(m.armRows(arms[1])[0])[0];
    const quote = m.node(m.bodies[2].root);
    for (0..6) |mutation| {
        const literal = m.patterns[first];
        const fallback = m.patterns[second];
        const match_ = m.matches[match_index];
        const arm = m.match_arms[info.arms.start];
        switch (mutation) {
            0 => m.patterns[first].b = 1,
            1 => m.patterns[first].ty = T.boolean,
            2 => m.patterns[second] = .{ .tag = .constant, .ty = T.u32_type },
            3 => m.matches[match_index].arms.len = 1,
            4 => m.match_arms[info.arms.start].body = arms[1].body,
            5 => m.patterns[second].a = m.bodies[1].binding,
            else => unreachable,
        }
        var remaining: usize = 65536;
        try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&m, quote.a, m.bodies[2].closed_rows, &remaining));
        m.patterns[first] = literal;
        m.patterns[second] = fallback;
        m.matches[match_index] = match_;
        m.match_arms[info.arms.start] = arm;
    }
    try verified(a, &m);
    var product = try lower(a, data_case_sources[1]);
    defer product.deinit(a);
    try verified(a, &product);
    const product_arm = product.matchArms(product.bodies[1].root)[0];
    const row = product.rowPatterns(product.armRows(product_arm)[0])[0];
    const children = product.patternChildren(row);
    const saved = product.patterns[children[0]];
    product.patterns[children[0]].a = product.patterns[children[1]].a;
    var remaining: usize = 65536;
    const product_quote = product.node(product.bodies[2].root);
    try std.testing.expectError(error.InvalidArtifact, @import("staging_core.zig").namedCall(&product, product_quote.a, product.bodies[2].closed_rows, &remaining));
    product.patterns[children[0]] = saved;
    try verified(a, &product);
}

test "portable typed staging named calls reconstruct higher order and scoped bodies after replay" {
    const cases = [_][]const u8{
        "const apply = fn (callback: U32 -> U32) => callback 42\nconst generated = @code.quote (apply (fn (value: U32) => value))\n",
        "type State a is effect = {get: Unit -> a, set: a -> Unit}\nconst hidden = fn (value: U32) => @effect.scope (fn (state: State U32) => value)\nconst generated = @code.quote (hidden 42)\n",
    };
    for (cases) |source| {
        var m = try lower(a, source);
        defer m.deinit(a);
        try V.validateBounds(&m, .{});
        try verified(a, &m);
        const format = @import("../reuse/dependency_format.zig");
        const key: format.Key = .{ .compiler = @splat(1), .settings = @splat(2), .source = @splat(3), .dependencies = @splat(4) };
        const bytes = try format.encode(a, key, m);
        defer a.free(bytes);
        var decoded = try format.decode(core.Module, a, bytes, key);
        defer decoded.deinit(a);
        try verified(a, &decoded);
    }
}

const named_composition_sources = [_][]const u8{
    \\effect Read: U32 -> U32
    \\const checked = fn computation => do:
    \\  let count = 0
    \\  for request in @requests computation:
    \\    case request of
    \\      effect Read value =>
    \\        count := @u32.add self 1
    \\        yield value
    \\      complete value =>
    \\        return @u32.add count value
    \\const generated = @code.quote (checked (@computation (fn () => Read 41)))
    \\const answer = @code.run generated
    ,
    \\type Box a is data = #Box a
    \\const Box.pure = fn value => #Box value
    \\const Box.bind = fn candidate => fn next => case candidate of
    \\  #Box value => next value
    \\const try = @do.monad Box
    \\const sequence = fn (value: Box U32) => do try:
    \\  use number <- value
    \\  return @u32.add number 1
    \\const unwrap = fn value => case value of
    \\  #Box number => number
    \\const generated = @code.quote (unwrap (sequence (#Box 41)))
    \\const answer = @code.run generated
    ,
    \\effect Read: U32 -> U32
    \\const checked = fn computation => do:
    \\  let count = 40
    \\  for request in @requests computation:
    \\    case request of
    \\      effect Read value =>
    \\        count := @u32.add self value
    \\        break
    \\      complete value =>
    \\        break
    \\  return count
    \\const generated = @code.quote (checked (@computation (fn () => Read 2)))
    \\const answer = @code.run generated
    ,
    \\effect Read: U32 -> U32
    \\const checked = fn computation => do:
    \\  let count = 39
    \\  let calls = 0
    \\  for request in @requests computation:
    \\    case request of
    \\      effect Read value =>
    \\        count := @u32.add self value
    \\        calls := @u32.add self 1
    \\        yield value
    \\      complete value =>
    \\        return @u32.add count calls
    \\const generated = @code.quote (checked (@computation (fn () => Read 2)))
    \\const answer = @code.run generated
    ,
    \\effect Read: U32 -> U32
    \\const checked = fn computation => do:
    \\  for request in @requests computation:
    \\    case request of
    \\      effect Read value =>
    \\        return value
    \\      complete value =>
    \\        return value
    \\const generated = @code.quote (checked (@computation (fn () => Read 42)))
    \\const answer = @code.run generated
};
test "portable named request and resolver composition survives producer teardown and complete OOM" {
    const format = @import("../reuse/dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
    for (named_composition_sources) |source| {
        var bytes: []u8 = undefined;
        var answer: u32 = 0;
        {
            var m = try lower(a, source);
            defer m.deinit(a);
            try verified(a, &m);
            answer = m.bodies[m.bodies.len - 1].binding;
            bytes = try format.encode(a, key, m);
        }
        defer a.free(bytes);
        try stagedRoundtrip(a, bytes, answer);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedRoundtrip, .{ bytes, answer });
    }
}

fn rejectedNamedComposition(allocator: std.mem.Allocator, module: *const core.Module) !void {
    V.validate(allocator, module, .{}) catch |err| switch (err) {
        error.OutOfMemory => return err,
        error.InvalidArtifact => return,
    };
    return error.TestUnexpectedResult;
}

test "portable named request composition rejects state decision and lexical target forgeries" {
    var m = try lower(a, named_composition_sources[0]);
    defer m.deinit(a);
    try verified(a, &m);
    const request = &m.request_loops[0];
    const complete = &m.extra[request.completion_state_bindings.start];
    const saved_complete = complete.*;
    complete.* = m.loop_carries[request.carries.start].incoming;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectedNamedComposition, .{&m});
    complete.* = saved_complete;
    const saved_target = request.return_target;
    request.return_target = m.closures[m.nodes[m.request_arms[0].callback].a].body;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectedNamedComposition, .{&m});
    request.return_target = saved_target;
    const saved_type = request.state_type;
    request.state_type = T.boolean;
    try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectedNamedComposition, .{&m});
    request.state_type = saved_type;
    for (m.nodes) |*n| {
        if (n.tag != .request_decision) continue;
        const saved = n.*;
        n.a = @backingInt(core.RequestDecisionKind.cancel);
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectedNamedComposition, .{&m});
        n.* = saved;
    }
    try verified(a, &m);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, verified, .{&m});
}

test "portable named resolver composition rejects forged selected methods and result families" {
    var m = try lower(a, named_composition_sources[1]);
    defer m.deinit(a);
    try verified(a, &m);
    for (m.resolver_ops) |*metadata| {
        if (metadata.operation != .pure and metadata.operation != .bind) continue;
        const saved = metadata.*;
        metadata.method.binding = m.bodies[m.bodies.len - 2].binding;
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectedNamedComposition, .{&m});
        metadata.* = saved;
        metadata.method_type = T.boolean;
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectedNamedComposition, .{&m});
        metadata.* = saved;
        metadata.operation = .forward;
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectedNamedComposition, .{&m});
        metadata.* = saved;
    }
    try verified(a, &m);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, verified, .{&m});
}

test "portable named resolver composition proves actual Foreign execution beneath pure selected headers" {
    var m = try lower(a,
        \\type Box a is data = #Box a
        \\const Box.pure = fn value => do:
        \\  use owner <- @resource.acquire (fn () => 1) (fn value => ())
        \\  use @resource.release owner
        \\  return #Box value
        \\const selected = @do.monad Box
        \\const helper = fn () => do selected:
        \\  return 42
        \\const generated = @code.quote (fn () => helper ())
        \\const answer = 42
    );
    defer m.deinit(a);
    try verified(a, &m);
    for (m.resolver_ops) |metadata| {
        if (metadata.operation != .pure) continue;
        const producer_type = m.bindings[metadata.method.binding].ty;
        const producer = m.types.nodes[producer_type];
        const selected = m.types.nodes[metadata.method_type];
        m.types.nodes[producer_type].c = 0;
        m.types.nodes[metadata.method_type].c = 0;
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, .{}));
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectedNamedComposition, .{&m});
        m.types.nodes[producer_type] = producer;
        m.types.nodes[metadata.method_type] = selected;
    }
    try verified(a, &m);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, verified, .{&m});
}

test "portable named resolver composition carries effectful continuations" {
    var m = try lower(a,
        \\type Box a is data = #Box a
        \\const Box.pure = fn value => do:
        \\  use owner <- @resource.acquire (fn () => 1) (fn value => ())
        \\  use @resource.release owner
        \\  return #Box value
        \\const Box.bind = fn candidate => fn next => case candidate of
        \\  #Box value => next value
        \\const identity = fn value => value
        \\const selected = identity (@do.monad (identity Box))
        \\const sequence = fn (value: U32) => do selected:
        \\  use number <- #Box value
        \\  return @u32.add number 40
        \\const helper = fn (value: U32) => case sequence value of
        \\  #Box result => result
        \\const generated = @code.quote (fn (value: U32) => helper value)
        \\const generated_task = generated
        \\const evaluated: U32 = 42
    );
    defer m.deinit(a);
    try verified(a, &m);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, verified, .{&m});
}

test "portable named resolver composition rejects same shaped foreign method substitutions" {
    var m = try lower(a, named_composition_sources[1]);
    defer m.deinit(a);
    var foreign = try lower(a, named_composition_sources[1]);
    defer foreign.deinit(a);
    foreign.unit = 2;
    const context: V.Context = .{ .units = &.{ &m, &foreign } };
    try V.validate(a, &m, context);
    for (m.resolver_ops) |*metadata| {
        if (metadata.operation != .pure and metadata.operation != .bind) continue;
        const saved = metadata.method;
        metadata.method.unit = foreign.unit;
        try std.testing.expectError(error.InvalidArtifact, V.validate(a, &m, context));
        metadata.method = saved;
    }
    try V.validate(a, &m, context);
}

test "portable named qualified resolver composition owns actual predicates in task helpers" {
    var m = try lower(a,
        \\type Box a is data = #Box a
        \\const Box.pure = fn value => #Box value
        \\const Box.bind = fn candidate => fn next => case candidate of
        \\  #Box value => next value
        \\const monad = fn constructor => @do.monad constructor
        \\const selected = monad Box
        \\const sequence = fn selected => fn candidate => do selected:
        \\  use value <- candidate
        \\  return @u32.add value 2
        \\const helper = fn (value: U32) => case sequence selected (#Box value) of
        \\  #Box number => number
        \\const generated = @code.quote (fn (value: U32) => helper value)
        \\entry const run = fn (value: U32) => @task.scope (fn group => @task.join (@task.spawn group (fn () => helper value)))
        \\const answer = 42
    );
    defer m.deinit(a);
    try verified(a, &m);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, verified, .{&m});
}
