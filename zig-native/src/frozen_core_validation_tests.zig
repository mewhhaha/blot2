const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
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

test "normal frozen Core admits generic recursion, record payloads, loops, State and Requests" {
    const sources = [_][]const u8{
        "entry const identity = fn value => value\nentry const answer = fn () => identity 42\n",
        "const even = fn (n: U32) -> U32 => if @u32.eq n 0 then 42 else odd (@u32.sub n 1)\nconst odd = fn (n: U32) -> U32 => if @u32.eq n 0 then 42 else even (@u32.sub n 1)\nentry const answer = fn () => even 42\n",
        "data Pair = #Pair {left: U32, right: U32}\nentry const answer = fn () => do:\n  let #Pair payload = #Pair {left: 40, right: 2}\n  return @u32.add (@product.get payload 0) (@product.get payload 1)\n",
        "entry const answer = fn () => do:\n  let count = 0\n  for index in 0..10:\n    count := @u32.add self index\n  for ever:\n    if @u32.eq count 45:\n      break\n    count := 45\n  return count\n",
        @embedFile("request-fixtures/shadow-completion_payload_shadow.blot"),
        @embedFile("request-fixtures/template-local-effects.blot"),
        mixed_source,
    };
    for (sources) |source| {
        var m = try lower(a, source);
        defer m.deinit(a);
        try verified(a, &m);
    }
}

test "every allocation failure releases validation workspace and retains immutable Core" {
    var m = try lower(a, @embedFile("request-fixtures/template-local-effects.blot"));
    defer m.deinit(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, verified, .{&m});
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
    var m = try lower(a, @embedFile("request-fixtures/shadow-completion_payload_shadow.blot"));
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

    var requests = try lower(a, @embedFile("request-fixtures/shadow-completion_payload_shadow.blot"));
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, publicationFailures, .{mixed_source});
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
