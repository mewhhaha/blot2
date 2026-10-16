const std = @import("std");
const cache = @import("body_check_cache.zig");
const check = @import("../check/check.zig");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const core = @import("../check/core.zig");
const backend = @import("../backend/core_backend.zig");
const A = std.mem.Allocator;
const a = std.testing.allocator;

const intrinsic_metadata_source =
    \\const seed = 2
    \\const second = fn (values: Array U32) => @cursor.value (@cursor.advance (@array.cursor values))
    \\const required = fn (value: U32) => @panic "retained trap"
    \\entry const run = fn () => second #[seed, 42]
;

test "body check cache uses typed facts for ordinary intrinsics rather than a spelling allowlist through OOM" {
    var before = try prepare(a, intrinsic_metadata_source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("second") != null);
    try std.testing.expect(before.bodies.find("required") != null);
    const source = try std.mem.replaceOwned(u8, a, intrinsic_metadata_source, "const seed = 2", "const seed = 3");
    defer a.free(source);
    var fresh = try prepare(a, source, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, source, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, source, expected.bytes, @as(usize, 1) });
}

const shorthand_source =
    \\const seed = 2
    \\const bundle = fn (value: U32) => fn (values: Array U32) => {value, values}
    \\const total = fn (values: Array U32) => do:
    \\  let count = 0
    \\  for let value in values:
    \\    count := @u32.add count value
    \\  return count
    \\entry const run = fn () => do:
    \\  let record = bundle seed #[40, 42]
    \\  return @u32.add record.value (total record.values)
;

test "body check cache retains shorthand owning fields and explicit ordinary array binders through OOM" {
    var before = try prepare(a, shorthand_source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("bundle") != null);
    try std.testing.expect(before.bodies.find("total") != null);
    const source = try std.mem.replaceOwned(u8, a, shorthand_source, "const seed = 2", "const seed = 3");
    defer a.free(source);
    var fresh = try prepare(a, source, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, source, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, source, expected.bytes, @as(usize, 1) });
}
const text =
    \\const seed = 2
    \\const sibling = fn (value: U32) -> U32 => @u32.add value seed
    \\entry const run = fn (argument: U32) -> U32 => sibling argument
;
const Output = struct {
    bodies: cache.Cache,
    module: core.Module,
    elaborations: usize,
    proof_visits: usize = 0,
    fn deinit(self: *Output, allocator: A) void {
        self.bodies.deinit(allocator);
        self.module.deinit(allocator);
    }
};
fn prepare(allocator: A, source: []const u8, previous: ?*const cache.Cache) !Output {
    return prepareMode(allocator, source, previous, true);
}
fn prepareMode(allocator: A, source: []const u8, previous: ?*const cache.Cache, retain: bool) !Output {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var owned: cache.Cache = .{ .minimum_nodes = 0 };
    errdefer owned.deinit(allocator);
    var retained_bodies: ?*cache.Cache = null;
    if (retain) retained_bodies = &owned;
    var checked = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true, .prelude_unit = 1, .body_source = source, .previous_bodies = previous, .retained_bodies = retained_bodies });
    defer checked.deinit(allocator);
    for (checked.diagnostics) |issue| std.debug.print("body cache {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    return .{ .bodies = owned, .module = try core.lower(allocator, &tree, &pool, &checked), .elaborations = checked.body_elaborations, .proof_visits = proof_visits: {
        var visits: usize = 0;
        for (checked.proof_bodies.debits) |debit| visits += debit.visits;
        break :proof_visits visits;
    } };
}
fn compile(allocator: A, output: *const Output) !backend.Result {
    var result = try backend.compile(allocator, &.{output.module}, 1);
    errdefer result.deinit(allocator);
    if (result.diagnostic) |issue| std.debug.print("body cache backend {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
    try std.testing.expect(result.diagnostic == null);
    return result;
}
fn compare(allocator: A, previous: *const cache.Cache, source: []const u8, expected: []const u8, elaborations: usize) !void {
    var output = try prepare(allocator, source, previous);
    defer output.deinit(allocator);
    if (elaborations != output.elaborations) std.debug.print("body reuse work mismatch for:\n{s}\n", .{source});
    try std.testing.expectEqual(elaborations, output.elaborations);
    var result = try compile(allocator, &output);
    defer result.deinit(allocator);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
}

test "body check cache relocates untouched siblings across syntax types and spellings" {
    var before = try prepare(a, text, null);
    defer before.deinit(a);
    try std.testing.expectEqual(@as(usize, 3), before.bodies.bodies.items.len);
    const changed = "const new_spelling = fn (earlier: F32) -> F32 => @f32.add earlier 4.0\nconst seed = @u32.add 2 1\nconst sibling = fn (value: U32) -> U32 => @u32.add value seed\nentry const run = fn (argument: U32) -> U32 => sibling argument\n";
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var result = try compile(a, &fresh);
    defer result.deinit(a);
    try compare(a, &before.bodies, changed, result.bytes, 2);
}

test "body check cache ownership survives all allocation failures" {
    var before = try prepare(a, text, null);
    defer before.deinit(a);
    const changed = "const seed = 3\nconst sibling = fn (value: U32) -> U32 => @u32.add value seed\nentry const run = fn (argument: U32) -> U32 => sibling argument\n";
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var result = try compile(a, &fresh);
    defer result.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, result.bytes, @as(usize, 1) });
}

fn parity(before_text: []const u8, after_text: []const u8, elaborations: usize) !void {
    var before = try prepare(a, before_text, null);
    defer before.deinit(a);
    var fresh = try prepare(a, after_text, null);
    defer fresh.deinit(a);
    var result = try compile(a, &fresh);
    defer result.deinit(a);
    try compare(a, &before.bodies, after_text, result.bytes, elaborations);
}

test "body check cache revokes type generic interface privacy and runtime reads" {
    try parity("const seed = 2\nentry const run = fn (x: U32) => seed\nconst unrelated = 7\n", "const seed = #False\nentry const run = fn (x: U32) => seed\nconst unrelated = 7\n", 2);
    try parity("const helper = fn (x: U32) -> U32 => x\nentry const run = fn (x: U32) -> U32 => helper x\nconst unrelated = 7\n", "const helper = fn x => x\nentry const run = fn (x: U32) -> U32 => helper x\nconst unrelated = 7\n", 2);
    try parity(text, "private const seed = 2\nconst sibling = fn (value: U32) -> U32 => @u32.add value seed\nentry const run = fn (argument: U32) -> U32 => sibling argument\n", 2);
    try parity(text, "let seed = 2\nconst sibling = fn (value: U32) -> U32 => @u32.add value seed\nentry const run = fn (argument: U32) -> U32 => sibling argument\n", 2);
}

test "body check cache keeps recursive components ordinary and retains demand boundaries" {
    const recursive = "const first = fn (n: U32) -> U32 => if @u32.eq n 0 then 4 else second (@u32.sub n 1)\nconst second = fn (n: U32) -> U32 => if @u32.eq n 0 then 5 else first (@u32.sub n 1)\nentry const run = fn (n: U32) -> U32 => first n\nconst unrelated = 7\n";
    var before = try prepare(a, recursive, null);
    defer before.deinit(a);
    var retained = try prepare(a, recursive, &before.bodies);
    defer retained.deinit(a);
    try std.testing.expect(retained.elaborations >= 2);
    const demanded = "const force = fn ~(x: U32) -> U32 => @demand x\nentry const run = fn (n: U32) -> U32 => force n\nconst unrelated = 7\n";
    try parity(demanded, demanded, 0);
}

fn cloneScenario(allocator: A, previous: *const cache.Cache) !void {
    var copied = try previous.clone(allocator);
    defer copied.deinit(allocator);
    var output = try prepare(allocator, text, &copied);
    defer output.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), output.elaborations);
}

test "body check cache copied owners survive allocation failures and unchanged revisions" {
    var before = try prepare(a, text, null);
    defer before.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, cloneScenario, .{&before.bodies});
}

test "body check cache sparse storage and elaboration scale with admitted declarations" {
    const memory = @import("../runtime/memory.zig");
    for ([_]usize{ 64, 128, 256 }) |count| {
        var source: std.ArrayList(u8) = .empty;
        defer source.deinit(a);
        try source.appendSlice(a, "const seed = 2\n");
        for (0..count) |index| {
            const declaration = try a.print("const sibling{d} = fn (x: U32) -> U32 => @u32.add x seed\n", .{index});
            defer a.free(declaration);
            try source.appendSlice(a, declaration);
        }
        try source.appendSlice(a, "entry const run = fn (x: U32) -> U32 => sibling0 x\n");
        var before = try prepare(a, source.items, null);
        defer before.deinit(a);
        source.items[13] = '3';
        var bare_memory: memory.TrackedAllocator = .{ .backing = a };
        var bare = try prepareMode(bare_memory.allocator(), source.items, null, false);
        defer bare.deinit(bare_memory.allocator());
        var fresh_memory: memory.TrackedAllocator = .{ .backing = a };
        var fresh = try prepare(fresh_memory.allocator(), source.items, null);
        defer fresh.deinit(fresh_memory.allocator());
        var retained_memory: memory.TrackedAllocator = .{ .backing = a };
        var retained = try prepare(retained_memory.allocator(), source.items, &before.bodies);
        defer retained.deinit(retained_memory.allocator());
        try std.testing.expectEqual(count + 2, fresh.elaborations);
        try std.testing.expectEqual(@as(usize, 1), retained.elaborations);
        try std.testing.expectEqual(count + 2, retained.bodies.bodies.items.len);
        const payload = try retained.bodies.payload(a);
        const owned_bytes = payload.bytes;
        std.debug.print("BODY_CHECK_GROWTH N={d} elaborations={d}/{d} bare_requested={d} fresh_requested={d} retained_requested={d} bare_peak={d} fresh_peak={d} retained_peak={d} owned_payload={d} graph_nodes={d}\n", .{ count, retained.elaborations, fresh.elaborations, bare_memory.counts.allocated_bytes, fresh_memory.counts.allocated_bytes, retained_memory.counts.allocated_bytes, bare_memory.counts.peak_bytes, fresh_memory.counts.peak_bytes, retained_memory.counts.peak_bytes, owned_bytes, payload.graph_nodes });
        try std.testing.expect(owned_bytes < 1024 * (count + 2));
        try std.testing.expect(retained_memory.counts.allocated_bytes < fresh_memory.counts.allocated_bytes);
    }
}

test "body check cache owns Foreign annotations and preserves unresolved selection diagnostics" {
    const effectful = "const invoke = fn (host: U32 -> U32 ! {Foreign}) => host 42\nentry const run = fn (host: U32 -> U32 ! {Foreign}) => invoke host\nconst unrelated = 7\n";
    var before = try prepare(a, effectful, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("invoke") != null);
    try std.testing.expect(before.bodies.find("run") != null);
    try parity(effectful, effectful, 0);
    const selected = "const helper = fn (x: U32) -> U32 => @type.call \"add\" x 2\nentry const run = fn (x: U32) -> U32 => helper x\nconst unrelated = 7\n";
    var selected_before = try prepare(a, selected, null);
    defer selected_before.deinit(a);
    try std.testing.expect(selected_before.bodies.find("helper") != null);
    try std.testing.expect(selected_before.bodies.find("run") != null);
    var selected_retained = try prepare(a, selected, &selected_before.bodies);
    defer selected_retained.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), selected_retained.elaborations);
    var ordinary = try backend.compile(a, &.{selected_before.module}, 1);
    defer ordinary.deinit(a);
    var reused = try backend.compile(a, &.{selected_retained.module}, 1);
    defer reused.deinit(a);
    try std.testing.expect(ordinary.diagnostic != null and reused.diagnostic != null);
    try std.testing.expectEqual(ordinary.diagnostic.?.code, reused.diagnostic.?.code);
}

test "body check cache exhausted syntax proof preserves ordinary checking" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "const wide = (");
    for (0..4096) |index| {
        if (index != 0) try source.appendSlice(a, ", ");
        try source.appendSlice(a, "1");
    }
    try source.appendSlice(a, ")\nentry const run = fn (x: U32) -> U32 => x\n");
    var before = try prepare(a, source.items, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("wide") == null);
    var retained = try prepare(a, source.items, &before.bodies);
    defer retained.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), retained.elaborations);
}

const ImportedReceipt = struct { name: []const u8, closed_rows: cache.Digest, unit: u32 = 2, binding: u32 = 1, origin: ?cache.Digest = null };
fn importedClosedRows(context: *const anyopaque, target: check.ExternalTarget) ?cache.Digest {
    const receipt: *const ImportedReceipt = @ptrCast(@alignCast(context));
    if (target.unit != receipt.unit or target.binding != receipt.binding) return null;
    return receipt.closed_rows;
}
fn importedName(context: *const anyopaque, target: check.ExternalTarget) ?[]const u8 {
    const receipt: *const ImportedReceipt = @ptrCast(@alignCast(context));
    if (target.unit != receipt.unit or target.binding != receipt.binding) return null;
    return receipt.name;
}
fn importedConsumer(allocator: A, original_name: []const u8, previous: ?*const cache.Cache) !Output {
    return importedConsumerAt(allocator, original_name, 2, false, null, previous);
}
fn importedUnitOrigin(context: *const anyopaque, unit: u32) ?cache.Digest {
    const receipt: *const ImportedReceipt = @ptrCast(@alignCast(context));
    if (unit != receipt.unit) return null;
    return receipt.origin;
}
fn importedConsumerAt(allocator: A, original_name: []const u8, unit: u32, inserted: bool, origin: ?cache.Digest, previous: ?*const cache.Cache) !Output {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var prefix: []const u8 = "";
    var target: u32 = 1;
    if (inserted) {
        prefix = "const earlier = 7\n";
        target = 2;
    }
    const producer_source = try allocator.print("{s}const {s} = fn (x: U32) -> U32 => x\n", .{ prefix, original_name });
    defer allocator.free(producer_source);
    var producer_tokens = try lexer.lex(allocator, producer_source);
    defer producer_tokens.deinit(allocator);
    var producer_tree = try parser.parse(allocator, producer_source, producer_tokens.tokens.items, &pool);
    defer producer_tree.deinit(allocator);
    var producer = try check.checkModuleWithOptions(allocator, &producer_tree, &pool, &.{}, &.{}, unit, .{ .builtin_catalog = true });
    defer producer.deinit(allocator);
    const source = "entry const run = fn (x: U32) -> U32 => exposed x\nconst untouched = 7\n";
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    const imported = check.ImportedBinding{ .origin = 0, .name = pool.lookup("exposed").?, .target = .{ .unit = unit, .binding = target }, .interface = .{ .types = .{ .store = &producer.types }, .scheme = producer.bindings[target].scheme, .named_function = true, .obligations = producer.obligations } };
    const receipt: ImportedReceipt = .{ .name = original_name, .unit = unit, .binding = target, .origin = origin, .closed_rows = cache.closedRowsDigest(.{ .store = &producer.types }, producer.bindings[target].ty, producer.bindings[target].scheme, &pool).? };
    var names: cache.ExternalNames = .{ .context = @ptrCast(&receipt), .lookup = importedName, .closed_rows = importedClosedRows };
    if (origin != null) names.unit_origin = importedUnitOrigin;
    var bodies: cache.Cache = .{ .minimum_nodes = 0 };
    errdefer bodies.deinit(allocator);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{imported}, &.{}, 1, .{ .builtin_catalog = true, .body_source = source, .previous_bodies = previous, .body_external_names = names, .retained_bodies = &bodies });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try cache.captureInto(allocator, &tree, &pool, source, &checked, names, &bodies);
    return .{ .bodies = bodies, .module = try core.lower(allocator, &tree, &pool, &checked), .elaborations = checked.body_elaborations };
}

test "body check cache original imported spelling revokes an equal type and numeric target" {
    var before = try importedConsumer(a, "first", null);
    defer before.deinit(a);
    var unchanged = try importedConsumer(a, "first", &before.bodies);
    defer unchanged.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), unchanged.elaborations);
    var renamed = try importedConsumer(a, "second", &before.bodies);
    defer renamed.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), renamed.elaborations);
}

fn replacementSource(allocator: A, count: usize, generation: usize) ![]u8 {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    for (0..count) |index| {
        const revision = @min(index, generation);
        const declaration = try allocator.print("const sibling{d} = fn (x: U32) -> U32 => @u32.add x {d}\n", .{ index, revision });
        defer allocator.free(declaration);
        try source.appendSlice(allocator, declaration);
    }
    try source.appendSlice(allocator, "entry const run = fn (x: U32) -> U32 => sibling0 x\n");
    return source.toOwnedSlice(allocator);
}

fn compactFailure(allocator: A, previous: *const cache.Cache, source: []const u8) !void {
    var references: [9]usize = undefined;
    for (previous.bodies.items, &references) |lease, *count| count.* = lease.owner.references;
    defer for (previous.bodies.items, references) |lease, count| std.debug.assert(lease.owner.references == count);
    var next = try prepare(allocator, source, previous);
    defer next.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 6), next.elaborations);
}

test "body check cache compacts mostly obsolete leased chunks without retaining quadratic generations" {
    for ([_]usize{ 32, 64 }) |count| {
        const initial_source = try replacementSource(a, count, 0);
        defer a.free(initial_source);
        var current = try prepare(a, initial_source, null);
        defer current.deinit(a);
        const initial_payload = try current.bodies.payload(a);
        for (1..count) |generation| {
            const source = try replacementSource(a, count, generation);
            defer a.free(source);
            var next = try prepare(a, source, &current.bodies);
            errdefer next.deinit(a);
            current.deinit(a);
            current = next;
            const payload = try current.bodies.payload(a);
            // One surviving body from each generation must not pin every full
            // preceding module-sized chunk. Includes obsolete bodies and graphs.
            try std.testing.expect(payload.bytes < initial_payload.bytes * 3);
        }
        const final_payload = try current.bodies.payload(a);
        std.debug.print("BODY_CHECK_CHUNKS N={d} initial={d} final={d} chunks={d}\n", .{ count, initial_payload.bytes, final_payload.bytes, final_payload.chunks });
    }
}

test "body check cache compact chunk publication preserves previous leases under OOM" {
    const initial_source = try replacementSource(a, 8, 0);
    defer a.free(initial_source);
    var initial = try prepare(a, initial_source, null);
    defer initial.deinit(a);
    const first_source = try replacementSource(a, 8, 1);
    defer a.free(first_source);
    var previous = try prepare(a, first_source, &initial.bodies);
    defer previous.deinit(a);
    const next_source = try replacementSource(a, 8, 7);
    defer a.free(next_source);
    // Only one old sibling and the entry survive from the larger new chunk;
    // the next capture compacts those leases while publishing changed bodies.
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compactFailure, .{ &previous.bodies, next_source });
    var copied = try previous.bodies.clone(a);
    defer copied.deinit(a);
    try std.testing.expect(copied.find("sibling0").? == previous.bodies.find("sibling0").?);
}

test "body check cache relocates generic principal binders and independently specializes consumers" {
    const before_text = "const identity = fn x => x\nconst box = fn x => #[x]\nentry const run = fn (x: U32) -> U32 => identity x\nentry const packed = fn (x: U32) => box x\n";
    var before = try prepare(a, before_text, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("identity") != null);
    try std.testing.expect(before.bodies.find("box") != null);
    const after_text = "const earlier_spelling = fn (f: F32) -> F32 => @f32.add f 2.0\nconst identity = fn x => x\nconst box = fn x => #[x]\nentry const run = fn (x: U32) -> U32 => identity x\nentry const packed = fn (x: U32) => box x\n";
    var fresh = try prepare(a, after_text, null);
    defer fresh.deinit(a);
    var result = try compile(a, &fresh);
    defer result.deinit(a);
    try compare(a, &before.bodies, after_text, result.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, after_text, result.bytes, @as(usize, 1) });
    try parity(before_text, "const identity = fn x => #[x]\nconst box = fn x => #[x]\nentry const run = fn (x: U32) => identity x\nentry const packed = fn (x: U32) => box x\n", 2);
}

test "body check cache compacts obsolete type graphs even when surviving syntax payload dominates" {
    var producer: std.ArrayList(u8) = .empty;
    defer producer.deinit(a);
    try producer.appendSlice(a, "@[fn value => value] const supplier = fn (x: U32) => (");
    for (0..256) |index| {
        if (index != 0) try producer.appendSlice(a, ", ");
        try producer.appendSlice(a, "x");
    }
    try producer.appendSlice(a, ")\n");
    // Inflate retained syntax without creating more partial-application types.
    const padding: [16384]u8 = @splat(' ');
    const stable = try a.print("const preserved = fn (x: U32) -> U32 => {s}@u32.add x 0\nentry const run = fn (x: U32) -> U32 => preserved x\n", .{padding});
    defer a.free(stable);
    const first_source = try a.print("{s}const wide = fn x => supplier x\n{s}", .{ producer.items, stable });
    defer a.free(first_source);
    var first = try prepare(a, first_source, null);
    defer first.deinit(a);
    const old = first.bodies.find("preserved").?;
    const removed = first.bodies.find("wide").?;
    const producer_body = first.bodies.find("supplier").?;
    // Byte occupancy alone would retain the old graph, even though the old
    // wide result accounts for most type projection work in that graph.
    try std.testing.expect(old.bytes() * 2 > old.owner.body_bytes);
    try std.testing.expect((removed.type_work + producer_body.type_work) * 2 > old.owner.type_work);
    const next_source = try a.print("const wide = fn x => @u32.add x 1\n{s}", .{stable});
    defer a.free(next_source);
    var next = try prepare(a, next_source, &first.bodies);
    defer next.deinit(a);
    try std.testing.expect(next.bodies.find("preserved").?.owner != old.owner);
    try std.testing.expectEqual(@as(usize, 1), next.elaborations);
    var fresh = try prepare(a, next_source, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    var actual = try compile(a, &next);
    defer actual.deinit(a);
    try std.testing.expectEqualSlices(u8, expected.bytes, actual.bytes);
}

test "body check cache relocates symbolic callback effects without closing them" {
    const first_source = "const apply = fn callback => fn argument => callback argument\nentry const run = fn (x: U32) -> U32 => apply (fn (y: U32) -> U32 => @u32.add y 1) x\n";
    var first = try prepare(a, first_source, null);
    defer first.deinit(a);
    try std.testing.expect(first.bodies.find("apply") != null);
    const next_source = "const earlier_spelling = fn (z: F32) -> F32 => @f32.add z 2.0\nconst apply = fn callback => fn argument => callback argument\nentry const run = fn (x: U32) -> U32 => apply (fn (y: U32) -> U32 => @u32.add y 1) x\n";
    var fresh = try prepare(a, next_source, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &first.bodies, next_source, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &first.bodies, next_source, expected.bytes, @as(usize, 1) });
    // Both inferred and written callback rows preserve the Foreign effect.
    const foreign_source = "const apply = fn callback => fn argument => callback argument\nentry const run = fn (host: U32 -> U32 ! {Foreign}) => apply host 42\n";
    var foreign_fresh = try prepare(a, foreign_source, null);
    defer foreign_fresh.deinit(a);
    var foreign_expected = try compile(a, &foreign_fresh);
    defer foreign_expected.deinit(a);
    try compare(a, &first.bodies, foreign_source, foreign_expected.bytes, 1);
}

test "body check cache relocates nominal identities and revokes retargeted local aliases" {
    const original = "type Token is data = #Token U32\nconst make = fn (n: U32) => #Token n\nconst identity = fn (value: Token) -> Token => value\nconst read = fn (#Token value) => value\nentry const run = fn (n: U32) => read (identity (make n))\n";
    var before = try prepare(a, original, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("identity") != null);
    try std.testing.expect(before.bodies.find("run") != null);
    try std.testing.expect(before.bodies.find("make") != null);
    const inserted = "type Earlier is data = #Earlier F32\nconst earlier_spelling = fn (f: F32) -> F32 => @f32.add f 2.0\ntype Token is data = #Token U32\nconst make = fn (n: U32) => #Token n\nconst identity = fn (value: Token) -> Token => value\nconst read = fn (#Token value) => value\nentry const run = fn (n: U32) => read (identity (make n))\n";
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const alias_first = "type First is data = #First U32\ntype Second is data = #Second U32\ntype Alias = First\nconst identity = fn (value: Alias) -> Alias => value\nconst read = fn (#First value) => value\nentry const run = fn (n: U32) => read (identity (#First n))\n";
    const alias_next = "type First is data = #First U32\ntype Second is data = #Second U32\ntype Alias = Second\nconst identity = fn (value: Alias) -> Alias => value\nconst read = fn (#Second value) => value\nentry const run = fn (n: U32) => read (identity (#Second n))\n";
    try parity(alias_first, alias_next, 3);
    const private_alias = try std.mem.replaceOwned(u8, a, alias_first, "type Alias = First", "private type Alias = First");
    defer a.free(private_alias);
    try parity(alias_first, private_alias, 1);
}

test "body check cache opaque storage roles revoke scalar to reference consumers" {
    const original = "opaque type Token = U32\nconst make = fn (n: U32) => #Token n\nconst identity = fn (value: Token) -> Token => value\nconst read = fn (#Token value) => value\nentry const run = fn (n: U32) => read (identity (make n))\n";
    var before = try prepare(a, original, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("identity") != null);
    const inserted = "const earlier_spelling = fn (f: F32) -> F32 => @f32.add f 2.0\nopaque type Token = U32\nconst make = fn (n: U32) => #Token n\nconst identity = fn (value: Token) -> Token => value\nconst read = fn (#Token value) => value\nentry const run = fn (n: U32) => read (identity (make n))\n";
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    const changed = "opaque type Token = Array U32\nconst make = fn (n: U32) => #Token #[n]\nconst identity = fn (value: Token) -> Token => value\nconst read = fn (#Token value) => value\nentry const run = fn (n: U32) => read (identity (make n))\n";
    try parity(original, changed, 4);
}

test "body check cache relocates generic nominal arguments and opaque parameter recipes" {
    const source = "opaque type Box a = a\nconst make = fn value => #Box value\nconst read = fn (#Box value) => value\nconst identity = fn value => value\nentry const unsigned = fn (value: U32) => read (identity (make value))\nentry const floating = fn (value: F32) => read (identity (make value))\nentry const reference = fn (value: U32) => read (identity (make #[value]))\n";
    var first = try prepare(a, source, null);
    defer first.deinit(a);
    try std.testing.expect(first.bodies.find("unsigned") != null);
    try std.testing.expect(first.bodies.find("floating") != null);
    try std.testing.expect(first.bodies.find("reference") != null);
    const changed = try a.print("type Earlier is data = #Earlier Bool\nconst earlier_spelling = 2.0\n{s}", .{source});
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &first.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &first.bodies, changed, expected.bytes, @as(usize, 1) });
}

test "body check cache relocates structural field spellings and shaped nominal arguments" {
    const source = "opaque type Entry { head, tail } = { head: head, tail: tail }\nconst make = fn value => #Entry value\nconst read = fn (#Entry { tail }) => tail\nconst identity = fn value => value\nentry const unsigned = fn (value: U32) => read (identity (make { head: value, tail: #[value] }))\nentry const floating = fn (value: F32) => read (identity (make { head: value, tail: #[value] }))\n";
    var first = try prepare(a, source, null);
    defer first.deinit(a);
    try std.testing.expect(first.bodies.find("unsigned") != null);
    try std.testing.expect(first.bodies.find("floating") != null);
    // Reverse first spelling encounter order and move both AST and type IDs.
    const changed = try a.print("const earlier_spelling = {{ tail: 2.0, head: 3.0 }}\n{s}", .{source});
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &first.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &first.bodies, changed, expected.bytes, @as(usize, 1) });
}

test "body check cache reconstructs symbolic associated predicates in the current solver" {
    const source = "const U32.add = fn (left: U32) => fn (right: U32) => @u32.add left right\nconst F32.add = fn (left: F32) => fn (right: F32) => @f32.add left right\nconst add = fn left => fn right => @type.call \"add\" left right\nentry const unsigned = fn (value: U32) => add value 2\nentry const floating = fn (value: F32) => add value 2.0\n";
    var first = try prepare(a, source, null);
    defer first.deinit(a);
    const add = first.bodies.find("add") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 1), add.predicates.len);
    const changed = try a.print("const earlier_spelling = 3.0\n{s}", .{source});
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &first.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &first.bodies, changed, expected.bytes, @as(usize, 1) });
    const edited = try std.mem.replaceOwned(u8, a, source, "@u32.add left right", "@u32.sub left right");
    defer a.free(edited);
    var edited_fresh = try prepare(a, edited, null);
    defer edited_fresh.deinit(a);
    var edited_expected = try compile(a, &edited_fresh);
    defer edited_expected.deinit(a);
    try compare(a, &first.bodies, edited, edited_expected.bytes, 1);
    try std.testing.expect(!std.mem.eql(u8, expected.bytes, edited_expected.bytes));
}

test "body check cache consumes selected evidence and revokes candidate interface or presence edits" {
    const source = "const U32.add = fn (left: U32) => fn (right: U32) => @u32.add left right\nentry const run = fn (value: U32) => (fn ready => @type.call \"add\" value 2) U32.add\n";
    var first = try prepare(a, source, null);
    defer first.deinit(a);
    const run = first.bodies.find("run") orelse return error.TestUnexpectedResult;
    try std.testing.expect(run.selection_digest != null);
    try std.testing.expectEqual(@as(usize, 1), run.signatures.len);
    const changed = try a.print("const earlier_spelling = 3.0\n{s}", .{source});
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &first.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &first.bodies, changed, expected.bytes, @as(usize, 1) });
    const body_edit = try std.mem.replaceOwned(u8, a, source, "@u32.add left right", "@u32.sub left right");
    defer a.free(body_edit);
    try parity(source, body_edit, 1);
    // A new candidate is a negative read even when U32 remains the winner.
    const added = try a.print("const F32.add = fn (left: F32) => fn (right: F32) => @f32.add left right\n{s}", .{source});
    defer a.free(added);
    try parity(source, added, 2);
    // Changing the established candidate's parameter/result scheme revokes the
    // old solved evidence, while ordinary dispatch remains authoritative.
    const widened = try std.mem.replaceOwned(u8, a, source, "@u32.add left right", "@u32.to_f32 (@u32.add left right)");
    defer a.free(widened);
    try parity(source, widened, 2);
}

test "body check cache compacts obsolete owned field spellings under successive interface edits" {
    var expression = try a.dupe(u8, "value");
    defer a.free(expression);
    for (0..12) |_| {
        const next = try a.print("@u32.add ({s}) 0", .{expression});
        a.free(expression);
        expression = next;
    }
    const Fixture = struct {
        fn source(allocator: A, value: []const u8, generation: usize) ![]u8 {
            var suffix: [4096]u8 = undefined;
            @memset(&suffix, 'x');
            const padding: [16384]u8 = @splat(' ');
            return allocator.print("@[fn item => item] const supplier = fn (value: U32) => {{ field_{d}_{s}: value }}\nconst wide = fn value => supplier value\nconst preserved = fn (value: U32) => {s}{s}\nentry const run = fn (value: U32) => preserved value\n", .{ generation, suffix, padding, value });
        }
    };
    const initial = try Fixture.source(a, expression, 0);
    defer a.free(initial);
    var previous = try prepare(a, initial, null);
    defer previous.deinit(a);
    const initial_payload = try previous.bodies.payload(a);
    const old = previous.bodies.find("preserved").?;
    try std.testing.expect(old.bytes() * 2 > old.owner.body_bytes);
    for (1..17) |generation| {
        const changed = try Fixture.source(a, expression, generation);
        defer a.free(changed);
        var next = try prepare(a, changed, &previous.bodies);
        errdefer next.deinit(a);
        const payload = try next.bodies.payload(a);
        try std.testing.expect(payload.bytes < initial_payload.bytes * 3);
        // New owning spellings dominate the graph even when live AST facts
        // dominate byte occupancy. Never pin their obsolete generation.
        try std.testing.expect(next.bodies.find("preserved").?.owner != previous.bodies.find("preserved").?.owner);
        previous.deinit(a);
        previous = next;
    }
}

test "body check cache revokes retargeted source operators at stable body syntax and types" {
    const source = "infixl 60 (+) = combine\nconst combine = fn (left: U32) => fn (right: U32) => @u32.add left right\nconst other = fn (left: U32) => fn (right: U32) => @u32.sub left right\nentry const run = fn (value: U32) => value + 2\n";
    var first = try prepare(a, source, null);
    defer first.deinit(a);
    try std.testing.expect(first.bodies.find("run") != null);
    const relocated = try std.mem.replaceOwned(u8, a, source, "const combine", "const earlier_spelling = 3.0\nconst combine");
    defer a.free(relocated);
    var fresh = try prepare(a, relocated, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &first.bodies, relocated, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &first.bodies, relocated, expected.bytes, @as(usize, 1) });
    const retargeted = try std.mem.replaceOwned(u8, a, source, "(+) = combine", "(+) = other");
    defer a.free(retargeted);
    try parity(source, retargeted, 1);
}

test "body check cache distinguishes equal arity closed row binder and anonymous path constraints" {
    const T = @import("../check/types.zig");
    var types = try T.Store.init(a);
    defer types.deinit();
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    const first = try types.freshEffects();
    const second = try types.freshEffects();
    const variables = [_]u32{ types.row(first).tail.variable, types.row(second).tail.variable };
    const left = try types.functionWithEffects(T.unit, T.u32_type, first);
    const right = try types.functionWithEffects(T.unit, T.u32_type, second);
    const raw = try types.product(&.{ left, right });
    const catalog: cache.Catalog = .{ .unit = 1, .pool = &pool, .nominals = &.{}, .constructors = &.{} };
    var binding: check.Binding = .{ .name = 0, .declaration = 0, .owner = 0, .kind = .global, .ty = raw, .scheme = .{ .root = raw, .row_variables = try types.saveList(&variables), .closed_rows = try types.saveList(variables[0..1]) } };
    const first_binder = cache.interfaceDigest(.{ .store = &types }, binding, &.{}, catalog).?;
    binding.scheme.closed_rows = try types.saveList(variables[1..2]);
    const second_binder = cache.interfaceDigest(.{ .store = &types }, binding, &.{}, catalog).?;
    try std.testing.expect(!std.mem.eql(u8, &first_binder, &second_binder));
    // Normal covariance certificates can disappear from public quantifiers.
    // The raw paths still distinguish which of two identical closed callbacks
    // was constrained, without depending on live numeric effect IDs.
    const closed = try types.functionWithEffects(T.unit, T.u32_type, 0);
    binding.scheme.root = try types.product(&.{ closed, closed });
    binding.scheme.row_variables = .{};
    binding.scheme.closed_rows = try types.saveList(variables[0..1]);
    const first_path = cache.interfaceDigest(.{ .store = &types }, binding, &.{}, catalog).?;
    binding.scheme.closed_rows = try types.saveList(variables[1..2]);
    const second_path = cache.interfaceDigest(.{ .store = &types }, binding, &.{}, catalog).?;
    try std.testing.expect(!std.mem.eql(u8, &first_path, &second_path));
    const unknown = try types.freshEffects();
    binding.scheme.closed_rows = try types.saveList(&.{types.row(unknown).tail.variable});
    try std.testing.expect(cache.interfaceDigest(.{ .store = &types }, binding, &.{}, catalog) == null);
}

test "body check cache relocates shared principal edges and reinstantiates current selection" {
    const source = "const U32.add = fn (left: U32) => fn (right: U32) => @u32.add left right\nconst F32.add = fn (left: F32) => fn (right: F32) => @f32.add left right\nconst add = fn left => fn right => @type.call \"add\" left right\nconst forwarded = fn left => fn right => add left right\nconst alias = forwarded\nentry const unsigned = fn (value: U32) => alias value 2\nentry const floating = fn (value: F32) => alias value 2.0\n";
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    const forwarded = before.bodies.find("forwarded") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 0), forwarded.predicates.len);
    try std.testing.expect(forwarded.selection_digest != null);
    try std.testing.expect(before.bodies.find("alias") != null);
    const inserted = try a.print("const different_spelling = 3.0\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const body_edit = try std.mem.replaceOwned(u8, a, source, "@u32.add left right", "@u32.sub left right");
    defer a.free(body_edit);
    try parity(source, body_edit, 1);
    const candidate = try a.print("const Bool.add = fn (left: Bool) => fn (right: Bool) => left\n{s}", .{source});
    defer a.free(candidate);
    var candidate_fresh = try prepare(a, candidate, null);
    defer candidate_fresh.deinit(a);
    var candidate_expected = try compile(a, &candidate_fresh);
    defer candidate_expected.deinit(a);
    var candidate_reused = try prepare(a, candidate, &before.bodies);
    defer candidate_reused.deinit(a);
    try std.testing.expect(candidate_reused.elaborations > 1);
    var candidate_result = try compile(a, &candidate_reused);
    defer candidate_result.deinit(a);
    try std.testing.expectEqualSlices(u8, candidate_expected.bytes, candidate_result.bytes);
}

test "body check cache recreates declared associated and representation qualifications" {
    const source = "const U32.add = fn (left: U32) => fn (right: U32) => @u32.add left right\nconst F32.add = fn (left: F32) => fn (right: F32) => @f32.add left right\nconst twice: a -> a where { associated \"add\" a a a } = fn value => @type.call \"add\" value value\nconst identity: a -> a where { type_rep a } = fn value => value\nentry const unsigned = fn (value: U32) => identity (twice value)\nentry const floating = fn (value: F32) => identity (twice value)\n";
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("twice") != null);
    try std.testing.expect(before.bodies.find("identity") != null);
    const changed = try a.print("const earlier_spelling = 3.0\n{s}", .{source});
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
    const edited = try std.mem.replaceOwned(u8, a, source, "@u32.add left right", "@u32.sub left right");
    defer a.free(edited);
    try parity(source, edited, 1);
}

test "body check cache relocates applied generic annotations and revokes constructor recipes" {
    const source = "type Box a is data = #Box a\nconst make = fn value => #Box value\nconst read = fn (#Box value) => value\nconst identity = fn (value: Box a) -> Box a => value\ntype Pair [left, right] = (left, right)\nconst shaped = fn (value: Pair [U32, F32]) -> Pair [U32, F32] => value\nconst arrayed = fn (value: Array a) -> Array a => value\nentry const run = fn (value: U32) => read (identity (make value))\nconst pair = fn (value: U32) => shaped (value, 2.0)\nentry const array = fn (value: U32) => arrayed #[value]\n";
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("identity") != null);
    try std.testing.expect(before.bodies.find("shaped") != null);
    try std.testing.expect(before.bodies.find("arrayed") != null);
    const inserted = try a.print("const new_spelling = {{ tail: 3.0, head: 2 }}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    // The new declaration elaborates; constructor references, destructuring
    // and applied annotations all keep their independently owned receipts.
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const recipe_type = try std.mem.replaceOwned(u8, a, source, "#Box a", "#Box (a, U32)");
    defer a.free(recipe_type);
    const recipe_make = try std.mem.replaceOwned(u8, a, recipe_type, "=> #Box value", "=> #Box (value, 0)");
    defer a.free(recipe_make);
    const recipe_edit = try std.mem.replaceOwned(u8, a, recipe_make, "fn (#Box value) => value", "fn (#Box (value, ignored)) => value");
    defer a.free(recipe_edit);
    var changed = try prepare(a, recipe_edit, null);
    defer changed.deinit(a);
    var changed_expected = try compile(a, &changed);
    defer changed_expected.deinit(a);
    var reused = try prepare(a, recipe_edit, &before.bodies);
    defer reused.deinit(a);
    try std.testing.expect(reused.elaborations > 2);
    var actual = try compile(a, &reused);
    defer actual.deinit(a);
    try std.testing.expectEqualSlices(u8, changed_expected.bytes, actual.bytes);
}

test "body check cache relocates ordinary block locals mutations joins and cases" {
    const original =
        \\const seed = 2
        \\const branched = fn (value: U32) -> U32 => do:
        \\  let count = value
        \\  if @u32.lt value 8:
        \\    count := @u32.add self seed
        \\  else:
        \\    count := @u32.add self 1
        \\  return count
        \\const matched = fn (value: U32) -> U32 => case value of
        \\  0 => seed
        \\  result => @u32.add result seed
        \\entry const run = fn (value: U32) -> U32 => matched (branched value)
    ;
    var before = try prepare(a, original, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("branched") != null);
    try std.testing.expect(before.bodies.find("matched") != null);
    const prefix = "const earlier_spelling = fn (fraction: F32) => @f32.add fraction 3.0\n";
    const inserted = try std.mem.concat(a, u8, &.{ prefix, original });
    defer a.free(inserted);
    const next = try std.mem.replaceOwned(u8, a, inserted, "const seed = 2", "const seed = @u32.add 2 1");
    defer a.free(next);
    var fresh = try prepare(a, next, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, next, expected.bytes, 2);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, next, expected.bytes, @as(usize, 2) });
    const body_edit = try std.mem.replaceOwned(u8, a, next, "count := @u32.add self seed", "count := @u32.mul self seed");
    defer a.free(body_edit);
    var altered = try prepare(a, body_edit, null);
    defer altered.deinit(a);
    var altered_output = try compile(a, &altered);
    defer altered_output.deinit(a);
    try compare(a, &before.bodies, body_edit, altered_output.bytes, 3);
    const polymorphic = "const local_generic = fn (value: U32) => do:\n  let identity = fn item => item\n  return identity value\nentry const run = fn (value: U32) => local_generic value\n";
    var ordinary = try prepare(a, polymorphic, null);
    defer ordinary.deinit(a);
    try std.testing.expect(ordinary.bodies.find("local_generic") != null);
}

test "body check cache relocates constructor cases and record pattern fields by spelling" {
    const source =
        \\type Packet is data = #Packet { head: U32, tail: Array U32 }
        \\const make = fn (value: U32) => #Packet { head: value, tail: #[value, @u32.add value 1] }
        \\const read = fn (packet: Packet) => case packet of
        \\  #Packet { tail } => tail
        \\entry const run = fn (value: U32) => read (make value)
    ;
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("make") != null);
    try std.testing.expect(before.bodies.find("read") != null);
    const inserted = try a.print("const new_spelling = {{ tail: 3.0, head: 2 }}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const changed = try std.mem.replaceOwned(u8, a, inserted, "@u32.add value 1", "@u32.add value 2");
    defer a.free(changed);
    var altered = try prepare(a, changed, null);
    defer altered.deinit(a);
    var altered_result = try compile(a, &altered);
    defer altered_result.deinit(a);
    try compare(a, &before.bodies, changed, altered_result.bytes, 2);
    // Both the tag recipe and nominal identity are reads, even if the selected
    // constructor's own payload and the exported function type stay unchanged.
    const reordered = try std.mem.replaceOwned(u8, a, source, "= #Packet { head: U32, tail: Array U32 }", "= #Unused | #Packet { head: U32, tail: Array U32 }");
    defer a.free(reordered);
    const exhaustive = try std.mem.replaceOwned(u8, a, reordered, "#Packet { tail } => tail", "#Packet { tail } => tail\n  #Unused => #[0]");
    defer a.free(exhaustive);
    var recipe = try prepare(a, exhaustive, null);
    defer recipe.deinit(a);
    var recipe_result = try compile(a, &recipe);
    defer recipe_result.deinit(a);
    try compare(a, &before.bodies, exhaustive, recipe_result.bytes, 3);
}

test "body check cache relocates generic local principals and covariance rows" {
    const source =
        \\const seed = 2
        \\const helper = fn (value: U32) -> U32 => do:
        \\  let identity = fn item => item
        \\  let apply = fn callback => fn argument => callback argument
        \\  let fraction = identity 3.0
        \\  let whole = apply identity value
        \\  return @u32.add whole seed
        \\entry const run = fn (value: U32) -> U32 => helper value
    ;
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    const helper = before.bodies.find("helper") orelse return error.TestUnexpectedResult;
    try std.testing.expect(helper.local_schemes.len >= 2);
    const inserted = try a.print("const earlier_spelling = {{ tail: 3.0, head: 2 }}\n{s}", .{source});
    defer a.free(inserted);
    const changed = try std.mem.replaceOwned(u8, a, inserted, "const seed = 2", "const seed = @u32.add 2 1");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 2);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 2) });
    // A changed local template is executable source, independent of the
    // unchanged outer scalar signature and its neighboring generic local.
    const body_edit = try std.mem.replaceOwned(u8, a, changed, "=> callback argument", "=> callback (@u32.add argument 1)");
    defer a.free(body_edit);
    var altered = try prepare(a, body_edit, null);
    defer altered.deinit(a);
    var altered_result = try compile(a, &altered);
    defer altered_result.deinit(a);
    try compare(a, &before.bodies, body_edit, altered_result.bytes, 3);
}

test "body check cache relocates concrete record and nominal projections by spelling" {
    const source =
        \\type Packet is data = #Packet { head: U32, tail: Array U32 }
        \\const get = fn (value: { head: U32, tail: Array U32 }) => (value).tail
        \\const read = fn (value: Packet) => (value).tail
        \\const make = fn (value: U32) => #Packet { head: value, tail: #[value, @u32.add value 1] }
        \\entry const run = fn (value: U32) => read (make value)
        \\entry const plain = fn (value: U32) => get { head: value, tail: #[value] }
    ;
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("get") != null);
    try std.testing.expect(before.bodies.find("read") != null);
    const inserted = try a.print("const earlier_spelling = {{ tail: 3.0, head: 2 }}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const changed = try std.mem.replaceOwned(u8, a, inserted, "@u32.add value 1", "@u32.add value 2");
    defer a.free(changed);
    var altered = try prepare(a, changed, null);
    defer altered.deinit(a);
    var altered_result = try compile(a, &altered);
    defer altered_result.deinit(a);
    try compare(a, &before.bodies, changed, altered_result.bytes, 2);
}

test "body check cache relocates dotted access paths without erasing projections" {
    const source = "const seed = 2\nconst helper = fn (value: { head: U32, tail: F32 }) -> U32 => @u32.add value.head seed\nentry const run = fn (value: U32) -> U32 => helper { head: value, tail: 1.0 }\n";
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("helper") != null);
    const changed = try std.mem.replaceOwned(u8, a, source, "const seed = 2", "const seed = 3");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
}

test "body check cache owns chained dotted nominal paths and owning payloads" {
    const source =
        \\type Packet is data = #Packet { head: U32, nested: { tail: Array U32, marker: F32 } } | #Alternate { nested: { marker: F32, tail: Array U32 }, head: U32 }
        \\const read = fn (value: Packet) => value.nested.tail
        \\const get = fn (value: { head: U32, nested: { tail: Array U32, marker: F32 } }) => value.nested.tail
        \\const make = fn value => #Packet { head: value, nested: { tail: #[value, @u32.add value 1], marker: 1.0 } }
        \\entry const run = fn (value: U32) => read (make value)
        \\entry const plain = fn (value: U32) => get { head: value, nested: { tail: #[value], marker: 1.0 } }
    ;
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), before.bodies.find("read").?.accesses.len);
    try std.testing.expectEqual(@as(usize, 2), before.bodies.find("get").?.accesses.len);
    const inserted = try a.print("const earlier_spelling = {{ marker: 3.0, tail: 2, nested: 1, head: 4 }}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const empty: cache.Cache = .{};
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &empty, inserted, expected.bytes, fresh.elaborations });
    const changed = try std.mem.replaceOwned(u8, a, inserted, "=> #Packet", "=> #Alternate");
    defer a.free(changed);
    var altered = try prepare(a, changed, null);
    defer altered.deinit(a);
    var altered_result = try compile(a, &altered);
    defer altered_result.deinit(a);
    try compare(a, &before.bodies, changed, altered_result.bytes, 2);
}

test "body check cache retains concrete dotted method paths through body edits and OOM" {
    const source =
        \\type Number is data = #Number U32
        \\const Number.next = fn (#Number value) => @u32.add value 1
        \\const read = fn (value: Number) => value.next
        \\entry const run = fn (value: U32) => read (#Number value)
    ;
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("read") != null);
    const changed = try std.mem.replaceOwned(u8, a, source, "@u32.add value 1", "@u32.add value 2");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
}

test "body check cache syntax owns parser allocations and preserves shared span synthetic ordinals" {
    const source =
        \\const gather = fn values => do:
        \\  let result = 0
        \\  for let value in values:
        \\    result := @u32.add result value
        \\  return result
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    const root = tree.roots.items[0];
    const owner = tree.declarationNodes(root).?;
    const shape = (try cache.syntax(a, &tree, &pool, root)).?;
    defer a.free(shape.ids);
    try std.testing.expectEqual(owner.len, shape.ids.len);
    var shared_span = false;
    for (shape.ids, 0..) |id, index| {
        try std.testing.expect(id >= owner.start and id - owner.start < owner.len);
        for (shape.ids[0..index]) |previous| {
            try std.testing.expect(previous != id);
            shared_span = shared_span or std.meta.eql(tree.span(previous), tree.span(id));
        }
    }
    try std.testing.expect(shared_span);
    // Numeric IDs and source intervals alone cannot manufacture an owner.
    tree.declaration_nodes.clearRetainingCapacity();
    try std.testing.expect(try cache.syntax(a, &tree, &pool, root) == null);
}

const provider_source =
    \\effect Read: Unit -> U32
    \\const seed = 2
    \\const make = fn () => @effect.provider Read (fn () => seed)
    \\entry const run = fn () => do (make ()):
    \\  return Read ()
;

test "body check cache owns complete static provider installations and token recipes through OOM" {
    var before = try prepare(a, provider_source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("make") != null);
    try std.testing.expect(before.bodies.find("run") != null);
    const source = try std.mem.replaceOwned(u8, a, provider_source, "const seed = 2", "const seed = 3");
    defer a.free(source);
    var fresh = try prepare(a, source, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, source, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, source, expected.bytes, @as(usize, 1) });
}

const auxiliary_source =
    \\effect Read: Unit -> U32
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const seed = 2
    \\const read = fn () => do (@effect.provider Read (fn () => seed)):
    \\  return Read ()
    \\const state = fn (initial: U32) => @effect.run State.get State.set initial (fn () => do:
    \\  use State.set 40
    \\  return State.get ()
    \\)
    \\const describe = fn () => @effect.count (@effect.of read)
    \\const description = describe ()
    \\const checked = fn computation => do:
    \\  let count = 0
    \\  for request in @requests computation:
    \\    case request of
    \\      effect Read value =>
    \\        count := @u32.add count 1
    \\        yield 42
    \\      complete value =>
    \\        return @u32.add count value
    \\const request = fn () => checked (@computation (fn () => Read ()))
    \\entry const run = fn () => @u32.add (@product.get (state seed) 1) (@u32.add (read ()) (@u32.add (request ()) description))
;
test "body check cache transports computations request state provider and reflection owners through relocation and OOM" {
    var before = try prepare(a, auxiliary_source, null);
    defer before.deinit(a);
    for ([_][]const u8{ "read", "state", "describe", "checked", "request", "run" }) |name| {
        if (before.bodies.find(name) == null) std.debug.print("missing auxiliary body {s}\n", .{name});
        try std.testing.expect(before.bodies.find(name) != null);
    }
    const changed = try std.mem.replaceOwned(u8, a, auxiliary_source, "const seed = 2", "const seed = 3");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
    const inserted = try a.print("effect Earlier: F32 -> F32\nconst earlier = fn (unrelated: F32) => unrelated\n{s}", .{changed});
    defer a.free(inserted);
    var fresh_inserted = try prepare(a, inserted, null);
    defer fresh_inserted.deinit(a);
    var inserted_expected = try compile(a, &fresh_inserted);
    defer inserted_expected.deinit(a);
    try compare(a, &before.bodies, inserted, inserted_expected.bytes, 2);
}

const private_auxiliary_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const seed = 2
    \\const scoped = fn () => @effect.scope (fn (state: State U32) => do:
    \\  let capability = state
    \\  let read = capability.get
    \\  let write = capability.set
    \\  let local = fn () => read ()
    \\  let (successor, result) = do (@effect.state read write seed):
    \\    return local ()
    \\  return result
    \\)
    \\const borrow = fn (owner: unique U32) => @usage.borrow owner (fn loan => @usage.read loan)
    \\const resource = fn () => @resource.scope (fn () => #[seed, 40]) (fn owner => ()) (fn loan => @usage.length loan)
    \\entry const run = fn () => @u32.add (resource ()) (@u32.add (scoped ()) (borrow 40))
;
test "body check cache owns fresh scope aliases and local loan regions through relocation and OOM" {
    var before = try prepare(a, private_auxiliary_source, null);
    defer before.deinit(a);
    for ([_][]const u8{ "scoped", "borrow", "resource", "run" }) |name| {
        if (before.bodies.find(name) == null) std.debug.print("missing private auxiliary body {s}\n", .{name});
        try std.testing.expect(before.bodies.find(name) != null);
    }
    const changed = try std.mem.replaceOwned(u8, a, private_auxiliary_source, "const seed = 2", "const seed = 3");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
    const inserted = try a.print("effect Earlier: F32 -> F32\nconst earlier = fn (unrelated: F32) => unrelated\n{s}", .{changed});
    defer a.free(inserted);
    var fresh_inserted = try prepare(a, inserted, null);
    defer fresh_inserted.deinit(a);
    var inserted_expected = try compile(a, &fresh_inserted);
    defer inserted_expected.deinit(a);
    try compare(a, &before.bodies, inserted, inserted_expected.bytes, 2);
}

const rank_package_source =
    \\const seed = 2
    \\type Item = exists [a] => (a, a -> U32)
    \\const identity: forall [a] => a -> a = fn value => value
    \\const make: U32 -> Item = fn value => pack [U32] (value, fn number => @u32.add number 40) as Item
    \\const read: Item -> U32 = fn item => unpack item as [a] body in (@product.get body 1) (@product.get body 0)
    \\entry const run = fn () => read (make (identity seed))
;
test "body check cache retains ordinary universal and existential owners through relocation and OOM" {
    var before = try prepare(a, rank_package_source, null);
    defer before.deinit(a);
    for ([_][]const u8{ "identity", "make", "read", "run" }) |name| {
        if (before.bodies.find(name) == null) std.debug.print("missing rank package body {s}\n", .{name});
        try std.testing.expect(before.bodies.find(name) != null);
    }
    const changed = try std.mem.replaceOwned(u8, a, rank_package_source, "const seed = 2", "const seed = 3");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
    const inserted = try a.print("type Earlier is data = #Earlier F32\nconst earlier = fn (unrelated: F32) => unrelated\n{s}", .{changed});
    defer a.free(inserted);
    var fresh_inserted = try prepare(a, inserted, null);
    defer fresh_inserted.deinit(a);
    var inserted_expected = try compile(a, &fresh_inserted);
    defer inserted_expected.deinit(a);
    try compare(a, &before.bodies, inserted, inserted_expected.bytes, 2);
}

const selected_package_source =
    \\const seed = 2
    \\type Render a is contract = { const show: a -> U32 }
    \\impl Number : Render U32 = { const show = fn value => value }
    \\impl Flag : Render Bool = { const show = fn value => if value then 7 else 9 }
    \\type Item = exists [a] where { Render a } => a
    \\const item: Item = pack [U32] seed as Item
    \\const flag: Item = pack [Bool] #True as Item
    \\const read = fn (item: Item) => unpack item as [a] value in Render.show value
    \\const both = fn (left: Item) => fn (right: Item) => unpack left as [a] x in unpack right as [b] y in @u32.add (Render.show x) (Render.show y)
    \\entry const run = fn () => @u32.add (read item) (both item flag)
;
test "body check cache reconstructs current selected and given package dictionaries through relocation and OOM" {
    var before = try prepare(a, selected_package_source, null);
    defer before.deinit(a);
    for ([_][]const u8{ "item", "flag", "read", "both", "run" }) |name| {
        if (before.bodies.find(name) == null) std.debug.print("missing selected package body {s}\n", .{name});
        try std.testing.expect(before.bodies.find(name) != null);
    }
    const changed = try std.mem.replaceOwned(u8, a, selected_package_source, "const seed = 2", "const seed = 3");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    // The implementation members are current ordinary globals; all five
    // unaffected value declarations keep their body receipts.
    const work = fresh.elaborations - 5;
    try compare(a, &before.bodies, changed, expected.bytes, work);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, work });
    const inserted = try a.print("type Earlier is data = #Earlier F32\nconst earlier = fn (unrelated: F32) => unrelated\n{s}", .{changed});
    defer a.free(inserted);
    var fresh_inserted = try prepare(a, inserted, null);
    defer fresh_inserted.deinit(a);
    var inserted_expected = try compile(a, &fresh_inserted);
    defer inserted_expected.deinit(a);
    try compare(a, &before.bodies, inserted, inserted_expected.bytes, work + 1);
    const method_edit = try std.mem.replaceOwned(u8, a, changed, "then 7 else 9", "then 8 else 9");
    defer a.free(method_edit);
    var fresh_method = try prepare(a, method_edit, null);
    defer fresh_method.deinit(a);
    var method_expected = try compile(a, &fresh_method);
    defer method_expected.deinit(a);
    try compare(a, &before.bodies, method_edit, method_expected.bytes, work);
}

const constructor_usage_source =
    \\type Wrap a is data = #Wrap a
    \\const token = fn () => Wrap
    \\const identity = fn (values: unique (Array U32)) => values
    \\entry const run = fn (values: unique (Array U32)) => identity values
;

test "body check cache owns type constructor recipes and ordinary unique types through relocation and OOM" {
    var before = try prepare(a, constructor_usage_source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("token") != null);
    try std.testing.expect(before.bodies.find("identity") != null);
    const source = try a.print("type Earlier is data = #Earlier U32\n{s}", .{constructor_usage_source});
    defer a.free(source);
    var fresh = try prepare(a, source, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, source, expected.bytes, 0);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, source, expected.bytes, @as(usize, 0) });
    const changed = try std.mem.replaceOwned(u8, a, constructor_usage_source, "#Wrap a", "#Wrap (Array a)");
    defer a.free(changed);
    try parity(constructor_usage_source, changed, 1);
}

const forwarded_source =
    \\const seed = 2
    \\const U32.combine = fn (left: U32) => fn (right: U32) => @u32.add left right
    \\const F32.combine = fn (left: F32) => fn (right: F32) => @f32.add left right
    \\const combine = fn left => fn right => @type.call "combine" left right
    \\const alias = combine
    \\const partial = fn value => alias value
    \\const apply = fn value => partial value value
    \\entry const run = fn () => apply seed
;

test "body check cache reconstructs transitive forwarded shared requirements through aliases and OOM" {
    var before = try prepare(a, forwarded_source, null);
    defer before.deinit(a);
    for ([_][]const u8{ "alias", "partial", "apply" }) |name| try std.testing.expect(before.bodies.find(name) != null);
    const source = try std.mem.replaceOwned(u8, a, forwarded_source, "const seed = 2", "const seed = 3");
    defer a.free(source);
    var fresh = try prepare(a, source, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, source, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, source, expected.bytes, @as(usize, 1) });
}

const binary_demand_source =
    \\infixl 60 (++) = right
    \\infixl 60 (**) = left
    \\infixl 60 (%%) = both
    \\const seed = 2
    \\const right = fn (value: U32) => fn ~(other: U32) => @u32.add value (@force other)
    \\const left = fn ~(value: U32) => fn (other: U32) => @u32.add (@force value) other
    \\const both = fn ~(value: U32) => fn ~(other: U32) => @u32.add (@force value) (@force other)
    \\const apply = fn (value: U32) => @u32.add (value ++ seed) (@u32.add (value ** seed) (value %% seed))
    \\entry const run = fn (value: U32) => apply value
;

test "body check cache owns both binary demand arguments through unchanged interfaces and OOM" {
    var before = try prepare(a, binary_demand_source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("apply") != null);
    const source = try std.mem.replaceOwned(u8, a, binary_demand_source, "const seed = 2", "const seed = 3");
    defer a.free(source);
    var fresh = try prepare(a, source, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, source, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, source, expected.bytes, @as(usize, 1) });
}

const residual_source =
    \\const seed = 2
    \\const Array.count = fn values => @array.length values
    \\const count = fn (values: Array U32) => values.count
    \\const increment = fn record => do:
    \\  let result = record
    \\  result.value := @u32.add self 1
    \\  return result
    \\const merge = fn left => fn right => @record.merge left right
    \\entry const run = fn () => do:
    \\  let first = increment {value: seed, values: #[40, 42]}
    \\  let second = merge first {extra: #[43]}
    \\  return @u32.add second.value (count second.values)
;

test "body check cache owns general record update merge and concrete array method residuals through OOM" {
    var before = try prepare(a, residual_source, null);
    defer before.deinit(a);
    for ([_][]const u8{ "count", "increment", "merge" }) |name| try std.testing.expect(before.bodies.find(name) != null);
    const source = try std.mem.replaceOwned(u8, a, residual_source, "const seed = 2", "const seed = 3");
    defer a.free(source);
    var fresh = try prepare(a, source, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, source, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, source, expected.bytes, @as(usize, 1) });
}

test "body check cache owns inferred local associated requirements" {
    const source =
        \\const U32.add = fn (left: U32) => fn (right: U32) => @u32.add left right
        \\const F32.add = fn (left: F32) => fn (right: F32) => @f32.add left right
        \\const Array.add = fn (left: Array U32) => fn (right: Array U32) => @array.concat left right
        \\const twice = fn value => do:
        \\  let local = fn amount => @type.call "add" amount amount
        \\  return local value
        \\entry const unsigned = fn (value: U32) => twice value
        \\entry const floating = fn (value: F32) => twice value
        \\entry const packed = fn (value: U32) => twice #[value, @u32.add value 1]
    ;
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("twice") != null);
    try std.testing.expect(before.bodies.find("twice").?.local_schemes[0].principal.obligations.len != 0);
    const changed = try a.print("const earlier_spelling = {{ tail: 3.0, head: 2 }}\n{s}", .{source});
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
    const empty: cache.Cache = .{};
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &empty, changed, expected.bytes, fresh.elaborations });
    const edited = try std.mem.replaceOwned(u8, a, source, "@u32.add left right", "@u32.sub left right");
    defer a.free(edited);
    try parity(source, edited, 1);
    const candidate = try a.print("const Bool.add = fn (left: Bool) => fn (right: Bool) => left\n{s}", .{source});
    defer a.free(candidate);
    var candidate_fresh = try prepare(a, candidate, null);
    defer candidate_fresh.deinit(a);
    var candidate_expected = try compile(a, &candidate_fresh);
    defer candidate_expected.deinit(a);
    var candidate_reused = try prepare(a, candidate, &before.bodies);
    defer candidate_reused.deinit(a);
    try std.testing.expect(candidate_reused.bodies.find("twice").? != before.bodies.find("twice").?);
    try std.testing.expect(candidate_reused.elaborations > 2);
    var candidate_result = try compile(a, &candidate_reused);
    defer candidate_result.deinit(a);
    try std.testing.expectEqualSlices(u8, candidate_expected.bytes, candidate_result.bytes);
}

test "body check cache owns local result directed requirements" {
    const source =
        \\type Number is data = #Number U32
        \\const Number.from = fn (value: U32) => #Number value
        \\const read = fn (#Number value) => value
        \\const convert = fn (value: U32) -> Number => do:
        \\  let local = fn amount => @type.result "from" amount
        \\  return local value
        \\entry const run = fn (value: U32) => read (convert value)
    ;
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("convert") != null);
    const inserted = try a.print("const earlier_spelling = {{ tail: 3.0, head: 2 }}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const edited = try std.mem.replaceOwned(u8, a, source, "=> #Number value", "=> #Number (@u32.add value 1)");
    defer a.free(edited);
    var changed = try prepare(a, edited, &before.bodies);
    defer changed.deinit(a);
    const original_convert = before.bodies.find("convert").?;
    const changed_convert = changed.bodies.find("convert").?;
    try std.testing.expectEqualSlices(u8, original_convert.source, changed_convert.source);
    // The selected constructor now computes its payload instead of preserving
    // the argument's capability relationship. Recheck that positive read.
    try std.testing.expect(!std.mem.eql(u8, &original_convert.selection_digest.?, &changed_convert.selection_digest.?));
    try std.testing.expectEqual(@as(usize, 4), before.elaborations);
    try std.testing.expectEqual(@as(usize, 2), changed.elaborations);
    try parity(source, edited, 2);
}

test "body check cache relocates declared local qualification origins" {
    const source =
        \\const U32.add = fn (left: U32) => fn (right: U32) => @u32.add left right
        \\const F32.add = fn (left: F32) => fn (right: F32) => @f32.add left right
        \\const Array.add = fn (left: Array U32) => fn (right: Array U32) => @array.concat left right
        \\const twice = fn value => do:
        \\  let identity: a -> a where { type_rep a } = fn amount => amount
        \\  let local: a -> a where { associated "add" a a a } = fn amount => @type.call "add" amount amount
        \\  return identity (local value)
        \\entry const unsigned = fn (value: U32) => twice value
        \\entry const floating = fn (value: F32) => twice value
        \\entry const packed = fn (value: U32) => twice #[value, @u32.add value 1]
    ;
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("twice") != null);
    const inserted = try a.print("const earlier_spelling = {{ tail: 3.0, head: 2 }}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const empty: cache.Cache = .{};
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &empty, inserted, expected.bytes, fresh.elaborations });
    const edited = try std.mem.replaceOwned(u8, a, source, "@u32.add left right", "@u32.sub left right");
    defer a.free(edited);
    try parity(source, edited, 1);
}

test "body check cache declines large local requirement receipts without changing results" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "const U32.add = fn (left: U32) => fn (right: U32) => @u32.add left right\nconst seed = 2\nconst many = fn (value: U32) => do:\n");
    for (0..256) |index| {
        const local = try a.print("  let local{d} = fn amount => @type.call \"add\" (@type.call \"add\" amount amount) amount\n", .{index});
        defer a.free(local);
        try source.appendSlice(a, local);
    }
    try source.appendSlice(a, "  return @u32.add value seed\nentry const run = fn (value: U32) => many value\n");
    var before = try prepare(a, source.items, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("many") == null);
    const changed = try std.mem.replaceOwned(u8, a, source.items, "const seed = 2", "const seed = 3");
    defer a.free(changed);
    try parity(source.items, changed, 2);
}

test "body check cache local qualification routes require exact bounded source clauses" {
    const source =
        \\const untouched = fn value => value
        \\const wrapper = fn value => do:
        \\  let local: a -> a where { type_rep a } = fn amount => amount
        \\  return local value
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var enclosing: ?check.Binding = null;
    var unrelated: ?check.Binding = null;
    var origin: ?@import("../parse/ast.zig").Span = null;
    for (checked.bindings) |binding| {
        if (binding.kind == .global) {
            if (std.mem.eql(u8, pool.get(binding.name), "wrapper")) enclosing = binding;
            if (std.mem.eql(u8, pool.get(binding.name), "untouched")) unrelated = binding;
        }
        if (binding.kind == .local) for (checked.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len]) |predicate| {
            if (predicate.explicit) origin = predicate.qualification_span;
        };
    }
    const span = origin orelse return error.TestUnexpectedResult;
    var complete: usize = 4096;
    try std.testing.expect(cache.sourceQualificationDigest(&tree, &pool, enclosing.?, span, &complete) != null);
    try std.testing.expect(complete < 4096);
    var none: usize = 0;
    try std.testing.expect(cache.sourceQualificationDigest(&tree, &pool, enclosing.?, span, &none) == null);
    try std.testing.expectEqual(@as(usize, 0), none);
    var shallow: usize = 1;
    try std.testing.expect(cache.sourceQualificationDigest(&tree, &pool, enclosing.?, span, &shallow) == null);
    try std.testing.expectEqual(@as(usize, 0), shallow);
    var altered: usize = 4096;
    try std.testing.expect(cache.sourceQualificationDigest(&tree, &pool, enclosing.?, .{ .start = span.start + 1, .end = span.end }, &altered) == null);
    var wrong: usize = 4096;
    try std.testing.expect(cache.sourceQualificationDigest(&tree, &pool, unrelated.?, span, &wrong) == null);
}

fn importedOrdinalReplay(allocator: A, previous: *const cache.Cache, origin: cache.Digest) !void {
    var output = try importedConsumerAt(allocator, "first", 3, true, origin, previous);
    defer output.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), output.elaborations);
    var found = false;
    for (output.module.bindings) |binding| if (binding.kind == .external) {
        try std.testing.expectEqual(@as(u32, 3), binding.target.unit);
        try std.testing.expectEqual(@as(u32, 2), binding.target.binding);
        found = true;
    };
    try std.testing.expect(found);
}

test "body check cache relocates imported ordinals only with exact original module authority" {
    const origin: cache.Digest = @splat(7);
    var before = try importedConsumerAt(a, "first", 2, false, origin, null);
    defer before.deinit(a);
    try importedOrdinalReplay(a, &before.bodies, origin);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, importedOrdinalReplay, .{ &before.bodies, origin });
    var renamed = try importedConsumerAt(a, "second", 3, true, origin, &before.bodies);
    defer renamed.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), renamed.elaborations);
    var replaced = try importedConsumerAt(a, "first", 3, true, @splat(8), &before.bodies);
    defer replaced.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), replaced.elaborations);
    var missing = try importedConsumerAt(a, "first", 3, true, null, &before.bodies);
    defer missing.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), missing.elaborations);
}

fn importedAnnotationConsumer(allocator: A, concrete: bool, renamed: bool, previous: ?*const cache.Cache) !Output {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var element: []const u8 = "a";
    if (concrete) element = "U32";
    const producer_source = try allocator.print("type Wrapper a is data = #Wrapper {{value: a, owning: Array U32}}\ntype Alias a = Wrapper {s}\ntype Twin a = Wrapper a\n", .{element});
    defer allocator.free(producer_source);
    var producer_tokens = try lexer.lex(allocator, producer_source);
    defer producer_tokens.deinit(allocator);
    var producer_tree = try parser.parse(allocator, producer_source, producer_tokens.tokens.items, &pool);
    defer producer_tree.deinit(allocator);
    var producer = try check.checkModuleWithOptions(allocator, &producer_tree, &pool, &.{}, &.{}, 2, .{ .builtin_catalog = true });
    defer producer.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), producer.diagnostics.len);
    const source = "entry const hold = fn (value: Imported U32) => value\n";
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var original_name: []const u8 = "Alias";
    if (renamed) original_name = "Twin";
    var target: ?u32 = null;
    for (producer.nominals, 0..) |nominal, index| if (std.mem.eql(u8, pool.get(nominal.name), original_name)) {
        target = @intCast(index);
    };
    const imported: check.ImportedCatalog = .{ .producer = &producer, .name = pool.lookup("Imported").?, .kind = .nominal, .index = target.?, .origin = 0 };
    const complete: check.ImportedCatalog = .{ .producer = &producer, .kind = .catalog, .index = 0, .origin = 0 };
    var bodies: cache.Cache = .{ .minimum_nodes = 0 };
    errdefer bodies.deinit(allocator);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{ complete, imported }, 1, .{ .builtin_catalog = true, .body_source = source, .previous_bodies = previous, .retained_bodies = &bodies });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expect(bodies.find("hold") != null);
    try std.testing.expectEqual(@as(usize, 1), bodies.find("hold").?.type_reads.len);
    return .{ .bodies = bodies, .module = try core.lower(allocator, &tree, &pool, &checked), .elaborations = checked.body_elaborations };
}
fn importedAnnotationReplay(allocator: A, previous: *const cache.Cache, elaborations: usize) !void {
    var output = try importedAnnotationConsumer(allocator, false, false, previous);
    defer output.deinit(allocator);
    try std.testing.expectEqual(elaborations, output.elaborations);
}
test "body check cache imported annotation recipes own original heads through allocation failures" {
    var before = try importedAnnotationConsumer(a, false, false, null);
    defer before.deinit(a);
    try importedAnnotationReplay(a, &before.bodies, 0);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, importedAnnotationReplay, .{ &before.bodies, @as(usize, 0) });
    const empty: cache.Cache = .{};
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, importedAnnotationReplay, .{ &empty, @as(usize, 1) });
    var concrete = try importedAnnotationConsumer(a, true, false, &before.bodies);
    defer concrete.deinit(a);
    // Both instantiated heads are Wrapper U32. The generic recipes differ.
    try std.testing.expectEqual(@as(usize, 1), concrete.elaborations);
    var renamed = try importedAnnotationConsumer(a, false, true, &before.bodies);
    defer renamed.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), renamed.elaborations);
}

test "body check cache restores shared requirements inside local principals" {
    const source =
        \\const U32.add = fn (left: U32) => fn (right: U32) => @u32.add left right
        \\const F32.add = fn (left: F32) => fn (right: F32) => @f32.add left right
        \\const Array.add = fn (left: Array U32) => fn (right: Array U32) => @array.concat left right
        \\const twice = fn value => @type.call "add" value value
        \\const pipeline = fn value => do:
        \\  let local = fn amount => twice amount
        \\  let relay = fn amount => local amount
        \\  return relay value
        \\entry const unsigned = fn (value: U32) => pipeline value
        \\entry const floating = fn (value: F32) => pipeline value
        \\entry const packed = fn (value: U32) => pipeline #[value, @u32.add value 1]
    ;
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("pipeline") != null);
    const inserted = try a.print("const earlier_spelling = {{tail: 3.0, head: 2}}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const empty: cache.Cache = .{};
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &empty, inserted, expected.bytes, fresh.elaborations });
    const edited = try std.mem.replaceOwned(u8, a, source, "@u32.add left right", "@u32.sub left right");
    defer a.free(edited);
    try parity(source, edited, 1);
    const added = try a.print("const Bool.add = fn (left: Bool) => fn (right: Bool) => left\n{s}", .{source});
    defer a.free(added);
    try parity(source, added, 5);
    const unqualified = try std.mem.replaceOwned(u8, a, source, "fn value => @type.call \"add\" value value", "fn value => value");
    defer a.free(unqualified);
    try parity(source, unqualified, 5);
}

test "body check cache Foreign arrow receipts survive allocation failures and interface changes" {
    const source = "const invoke = fn (host: U32 -> U32 ! {Foreign}) => host 42\nentry const run = fn (host: U32 -> U32 ! {Foreign}) => invoke host\n";
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("invoke") != null);
    try std.testing.expect(before.bodies.find("run") != null);
    const inserted = try a.print("const earlier_spelling = {{tail: 3.0, head: 2}}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const empty: cache.Cache = .{};
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &empty, inserted, expected.bytes, fresh.elaborations });
    const edited = try std.mem.replaceOwned(u8, a, source, "host 42", "host 43");
    defer a.free(edited);
    try parity(source, edited, 1);
    const pure = "const invoke = fn (host: U32 -> U32 ! {}) => host 42\nentry const run = fn () => invoke (fn (value: U32) => value)\n";
    try parity(source, pure, 2);
    const operation = "effect Read: Unit -> U32\nconst invoke = fn (host: Unit -> U32 ! {Read}) => host ()\n";
    var ordinary = try prepare(a, operation, null);
    defer ordinary.deinit(a);
    try std.testing.expect(ordinary.bodies.find("invoke") != null);
}

test "body check cache owns symbolic written Foreign arrow rows" {
    const symbolic = "const invoke: (U32 -> U32 ! {|e}) -> U32 ! {|e} = fn host => host 42\nentry const run = fn (host: U32 -> U32 ! {Foreign}) => invoke host\n";
    try parity(symbolic, symbolic, 0);
}

test "body check cache owns generic array indexing through allocation failures" {
    const source =
        \\const seed = 0
        \\const first = fn (value: Array a) => value[seed]
        \\entry const unsigned = fn (value: U32) => first #[value, @u32.add value 1]
        \\entry const floating = fn (value: F32) => first #[value, @f32.add value 1.0]
        \\entry const packed = fn (value: U32) => first #[#[value], #[@u32.add value 1]]
    ;
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("first") != null);
    const inserted = try a.print("const earlier_spelling = {{tail: 3.0, head: 2}}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const empty: cache.Cache = .{};
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &empty, inserted, expected.bytes, fresh.elaborations });
    const edited = try std.mem.replaceOwned(u8, a, source, "const seed = 0", "const seed = 1");
    defer a.free(edited);
    try parity(source, edited, 1);
}

test "body check cache restores generic explicit field templates" {
    const source = "const extract = fn value => (value).item\nentry const run = fn (value: U32) => extract {tail: 3.0, item: value}\nentry const packed = fn (value: U32) => extract {item: #[value], head: 2}\n";
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("extract") != null);
    const inserted = try a.print("const earlier_spelling = {{head: 3.0, tail: 2}}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const empty: cache.Cache = .{};
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &empty, inserted, expected.bytes, fresh.elaborations });
    const candidate = try a.print("const U32.item = fn (value: U32) => value\n{s}", .{source});
    defer a.free(candidate);
    try parity(source, candidate, 4);
}

test "body check cache restores field requirements in local principals" {
    const source = "const extract = fn value => do:\n  let local = fn amount => (amount).item\n  return local value\nentry const run = fn (value: U32) => extract {tail: 3.0, item: value}\nentry const packed = fn (value: U32) => extract {item: #[value], head: 2}\n";
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("extract") != null);
    const inserted = try a.print("const earlier_spelling = {{head: 3.0, tail: 2}}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const empty: cache.Cache = .{};
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &empty, inserted, expected.bytes, fresh.elaborations });
}

test "body check cache restores generic dotted templates through allocation failures" {
    const source = "const extract = fn value => value.item.count\nconst scoped = fn value => do:\n  let local = fn amount => amount.item.count\n  return local value\nentry const run = fn (value: U32) => extract {tail: 3.0, item: {count: value, ignored: 2}}\nentry const packed = fn (value: U32) => scoped {item: {ignored: 2.0, count: #[value]}, head: 2}\n";
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("extract") != null);
    try std.testing.expect(before.bodies.find("scoped") != null);
    const inserted = try a.print("const earlier_spelling = {{head: 3.0, tail: 2}}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const empty: cache.Cache = .{};
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &empty, inserted, expected.bytes, fresh.elaborations });
    const candidate = try a.print("const U32.count = fn (value: U32) => value\n{s}", .{source});
    defer a.free(candidate);
    try parity(source, candidate, 5);
}

test "body check cache owns if let pattern scopes and predecessor joins" {
    const source =
        \\type Maybe a is data = #None | #Some a
        \\const choose = fn (value: Maybe U32) => do:
        \\  let result = 2
        \\  if let #Some amount = value:
        \\    result := @u32.add amount 1
        \\  else:
        \\    result := 3
        \\  return result
        \\const pack = fn (value: Maybe (Array U32)) => do:
        \\  let result = #[2]
        \\  if let #Some amount = value:
        \\    result := amount
        \\  return result
        \\entry const run = fn (value: U32) => choose (#Some value)
        \\entry const empty = fn () => choose #None
        \\entry const packed = fn (value: U32) => pack (#Some #[value])
    ;
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("choose") != null);
    try std.testing.expect(before.bodies.find("pack") != null);
    const inserted = try a.print("const earlier_spelling = {{head: 3.0, tail: 2}}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const empty: cache.Cache = .{};
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &empty, inserted, expected.bytes, fresh.elaborations });
    const changed = try std.mem.replaceOwned(u8, a, source, "result := 3", "result := 4");
    defer a.free(changed);
    try parity(source, changed, 1);
}

test "body check cache owns pure collection unary and value pattern recipes" {
    const source =
        \\const marker = 2
        \\const copied = fn value => @array.identity (@array.set (@array.concat (@array.prepend (@array.append #[value] 1) 2) (@array.fill 2 value)) 0 value)
        \\const listed = fn value => @list.from_array (@array.slice (@array.from_list (@list.append [value] value)) 0 1)
        \\const generated = fn value => @array.generate 2 (fn (index: U32) => @u32.add value index)
        \\const projected = fn (value: U32) => @product.get (3.0, value) 1
        \\const negative = fn (value: F32) => -value
        \\const selected = fn (value: U32) => do:
        \\  if let ^marker = value:
        \\    return 1
        \\  return 0
        \\entry const run = fn (value: U32) => copied value
        \\entry const scalar = fn (value: U32) => @array.get (generated value) 1
        \\entry const count = fn (value: U32) => @list.length (listed value)
        \\entry const pair = fn (value: U32) => projected value
        \\entry const fraction = fn (value: F32) => negative value
        \\entry const matched = fn (value: U32) => selected value
    ;
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    for ([_][]const u8{ "copied", "listed", "generated", "projected", "negative", "selected" }) |name| try std.testing.expect(before.bodies.find(name) != null);
    const inserted = try a.print("const earlier_spelling = {{head: 3.0, tail: 2}}\n{s}", .{source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    const empty: cache.Cache = .{};
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &empty, inserted, expected.bytes, fresh.elaborations });
    const changed = try std.mem.replaceOwned(u8, a, source, "const marker = 2", "const marker = 3");
    defer a.free(changed);
    try parity(source, changed, 1);
}

fn nominalCoreOrderReplay(allocator: A, previous: *const cache.Cache, source: []const u8, expected_core: *const core.Module, expected: []const u8) !void {
    var output = try prepare(allocator, source, previous);
    defer output.deinit(allocator);
    try std.testing.expect(@import("../structural.zig").equal(expected_core.types, output.module.types));
    var result = try compile(allocator, &output);
    defer result.deinit(allocator);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
}

test "body check cache preserves monomorphic nominal Core ordering on a third revision" {
    const source =
        \\const marker = 60.0
        \\type Walk is data = #Walk {yaw: F32}
        \\type Flight is data = #Flight {vy: F32}
        \\type Robot is data = #Walking Walk | #Flying Flight
        \\const encode = fn (current: Robot) => case current of
        \\  #Walking walk => #[walk.yaw, marker]
        \\  #Flying flight => #[flight.vy, marker]
        \\entry const schema = marker
    ;
    var first = try prepare(a, source, null);
    defer first.deinit(a);
    const edited = try std.mem.replaceOwned(u8, a, source, "marker = 60.0", "marker = 61.0");
    defer a.free(edited);
    var second = try prepare(a, edited, &first.bodies);
    defer second.deinit(a);
    var third = try prepare(a, source, &second.bodies);
    defer third.deinit(a);
    var fresh = try prepare(a, source, null);
    defer fresh.deinit(a);
    try std.testing.expect(@import("../structural.zig").equal(fresh.module.types, third.module.types));
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    var actual = try compile(a, &third);
    defer actual.deinit(a);
    try std.testing.expectEqualSlices(u8, expected.bytes, actual.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, nominalCoreOrderReplay, .{ &second.bodies, source, &fresh.module, expected.bytes });
    const changed_recipe = try std.mem.replaceOwned(u8, a, source, "#Walk {yaw: F32}", "#Walk {yaw: F32, extra: U32}");
    defer a.free(changed_recipe);
    var revoked = try prepare(a, changed_recipe, &second.bodies);
    defer revoked.deinit(a);
    try std.testing.expect(revoked.elaborations > third.elaborations);
}

const implementation_mixed =
    \\type Source s is contract = { type Item, const first: s -> (Source.Item s) }
    \\impl ScalarSource : Source U32 = {
    \\  type Item = U32,
    \\  const first = fn value => @u32.add value 1,
    \\}
    \\const unrelated = fn (value: U32) => @u32.add value 7
    \\const selected = fn (value: U32) => Source.first value
    \\entry const run = fn (value: U32) => @u32.add (unrelated value) (selected value)
;

test "body check cache mixed implementation module retains independent receipts" {
    var before = try prepare(a, implementation_mixed, null);
    defer before.deinit(a);
    var repeated = try prepare(a, implementation_mixed, &before.bodies);
    defer repeated.deinit(a);
    try std.testing.expect(before.bodies.find("unrelated") != null);
    try std.testing.expect(before.bodies.find("selected").?.implementation_selection);
    try std.testing.expectEqual(@as(usize, 4), before.elaborations);
    try std.testing.expectEqual(@as(usize, 1), repeated.elaborations);
    try std.testing.expectEqual(@as(usize, 3), before.bodies.bodies.items.len);
    var first = try compile(a, &before);
    defer first.deinit(a);
    var retained = try compile(a, &repeated);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
}

test "body check cache closed implementation calls reconstruct current proofs" {
    const source = try std.mem.replaceOwned(u8, a, implementation_mixed, "(Source.Item s)", "U32");
    defer a.free(source);
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    const selected = before.bodies.find("selected") orelse return error.TestUnexpectedResult;
    try std.testing.expect(selected.implementation_selection);
    var repeated = try prepare(a, source, &before.bodies);
    defer repeated.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), repeated.elaborations);
    var remaining: usize = 16_384;
    try @import("../eval/selected_implementation_admission.zig").core(a, &repeated.module, &remaining);
    var first = try compile(a, &before);
    defer first.deinit(a);
    var retained = try compile(a, &repeated);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
}

test "body check cache generic contract callers retain residual requirements" {
    const source = try std.mem.replaceOwned(u8, a, implementation_mixed, "const selected = fn (value: U32)", "const selected = fn value");
    defer a.free(source);
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("selected") != null);
    var repeated = try prepare(a, source, &before.bodies);
    defer repeated.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), repeated.elaborations);
    var first = try compile(a, &before);
    defer first.deinit(a);
    var retained = try compile(a, &repeated);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, source, first.bytes, @as(usize, 1) });
}

test "body check cache local contract requirements own current declaration identities" {
    const source = try std.mem.replaceOwned(u8, a, implementation_mixed, "fn (value: U32) => Source.first value", "fn (value: U32) => do:\n  let forward = fn item => Source.first item\n  return forward value");
    defer a.free(source);
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    const selected = before.bodies.find("selected") orelse return error.TestUnexpectedResult;
    try std.testing.expect(selected.local_schemes.len != 0);
    const shifted_source = try std.mem.concat(a, u8, &.{ "const earlier_spelling = 3\n", source });
    defer a.free(shifted_source);
    var shifted = try prepare(a, shifted_source, &before.bodies);
    defer shifted.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), shifted.elaborations);
    try std.testing.expect(shifted.bodies.find("selected").?.owner == selected.owner);
    var shifted_fresh = try prepare(a, shifted_source, null);
    defer shifted_fresh.deinit(a);
    var shifted_expected = try compile(a, &shifted_fresh);
    defer shifted_expected.deinit(a);
    var shifted_result = try compile(a, &shifted);
    defer shifted_result.deinit(a);
    try std.testing.expectEqualSlices(u8, shifted_expected.bytes, shifted_result.bytes);
    const relocated = try std.mem.concat(a, u8, &.{ "type Earlier a is contract = { type Value }\n", source });
    defer a.free(relocated);
    var fresh = try prepare(a, relocated, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    // A new losing contract changes the complete candidate read.
    try compare(a, &before.bodies, relocated, expected.bytes, 2);
    try compare(a, &fresh.bodies, relocated, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &fresh.bodies, relocated, expected.bytes, @as(usize, 1) });
}

test "body check cache mixed implementation edits retain exact replay allocation ownership" {
    var before = try prepare(a, implementation_mixed, null);
    defer before.deinit(a);
    const changed = try std.mem.replaceOwned(u8, a, implementation_mixed, "@u32.add value 1", "@u32.add value 4");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var result = try compile(a, &fresh);
    defer result.deinit(a);
    try compare(a, &before.bodies, changed, result.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, result.bytes, @as(usize, 1) });
    const caller = try std.mem.replaceOwned(u8, a, changed, "Source.first value", "@u32.add (Source.first value) 3");
    defer a.free(caller);
    try parity(changed, caller, 2);
}

const implementation_annotations =
    \\type First is data = #First U32
    \\type Second is data = #Second U32
    \\type Alias = First
    \\type Source s is contract = { type Item, const first: s -> (Source.Item s) }
    \\impl ScalarSource : Source U32 = {
    \\  type Item = U32,
    \\  const first = fn value => @u32.add value 1,
    \\}
    \\const identity = fn (value: Alias) -> Alias => value
    \\const read = fn (#First value) => value
    \\const selected = fn (value: U32) => Source.first value
    \\entry const run = fn (value: U32) => @u32.add (read (identity (#First value))) (selected value)
;

test "body check cache mixed implementation annotations own independent nominal recipes" {
    var before = try prepare(a, implementation_annotations, null);
    defer before.deinit(a);
    const identity = before.bodies.find("identity") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 2), identity.type_reads.len);
    try std.testing.expect(before.bodies.find("selected").?.implementation_selection);
    try std.testing.expectEqual(@as(usize, 5), before.elaborations);
    var repeated = try prepare(a, implementation_annotations, &before.bodies);
    defer repeated.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), repeated.elaborations);
    try std.testing.expectEqual(@as(usize, 4), before.bodies.bodies.items.len);
    // The unchanged annotated declaration keeps its owner, while current
    // checking reconstructs complete selected proofs and precise Core uses.
    try std.testing.expectEqual(before.module.selected_proofs.len, repeated.module.selected_proofs.len);
    try std.testing.expectEqual(before.module.selected_members.len, repeated.module.selected_members.len);
    try std.testing.expectEqual(before.module.selected_edges.len, repeated.module.selected_edges.len);
    try std.testing.expectEqual(before.module.selected_uses.len, repeated.module.selected_uses.len);
    var remaining: usize = 16_384;
    try @import("../eval/selected_implementation_admission.zig").core(a, &repeated.module, &remaining);
    var initial = try compile(a, &before);
    defer initial.deinit(a);
    var replayed = try compile(a, &repeated);
    defer replayed.deinit(a);
    try std.testing.expectEqualSlices(u8, initial.bytes, replayed.bytes);
    const changed = try std.mem.replaceOwned(u8, a, implementation_annotations, "@u32.add value 1", "@u32.add value 4");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try std.testing.expect(!std.mem.eql(u8, initial.bytes, expected.bytes));
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
}

test "body check cache mixed implementation aliases revoke same layout identity and privacy changes" {
    // Both nominal owners carry U32. Equal runtime layout does not authorize
    // replaying an old alias recipe after it names the other nominal owner.
    const retarget = try std.mem.replaceOwned(u8, a, implementation_annotations, "type Alias = First", "type Alias = Second");
    defer a.free(retarget);
    const reader = try std.mem.replaceOwned(u8, a, retarget, "fn (#First value)", "fn (#Second value)");
    defer a.free(reader);
    const changed = try std.mem.replaceOwned(u8, a, reader, "identity (#First value)", "identity (#Second value)");
    defer a.free(changed);
    try parity(implementation_annotations, changed, 4);
    const private_alias = try std.mem.replaceOwned(u8, a, implementation_annotations, "type Alias = First", "private type Alias = First");
    defer a.free(private_alias);
    try parity(implementation_annotations, private_alias, 2);
}

test "body check cache mixed implementation aliases own selected associated type authority" {
    const typed = try std.mem.replaceOwned(u8, a, implementation_mixed, "const unrelated = fn (value: U32)", "const unrelated = fn (value: Scalar)");
    defer a.free(typed);
    const source = try std.mem.concat(a, u8, &.{ "type Scalar = Source.Item U32\n", typed });
    defer a.free(source);
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    // The original projection recipe and complete implementation catalog
    // authorize this alias alongside its independently relocated facts.
    try std.testing.expect(before.bodies.find("unrelated").?.implementation_selection);
    try std.testing.expect(before.bodies.find("selected").?.implementation_selection);
    var repeated = try prepare(a, source, &before.bodies);
    defer repeated.deinit(a);
    try std.testing.expectEqual(@as(usize, 4), before.elaborations);
    try std.testing.expectEqual(@as(usize, 1), repeated.elaborations);
    var expected = try compile(a, &before);
    defer expected.deinit(a);
    var actual = try compile(a, &repeated);
    defer actual.deinit(a);
    try std.testing.expectEqualSlices(u8, expected.bytes, actual.bytes);
}

test "body check cache mixed implementation keeps ordinary associated selection receipts" {
    const associated = try std.mem.replaceOwned(u8, a, implementation_mixed, "@u32.add value 7", "@type.call \"twice\" value 7");
    defer a.free(associated);
    const source = try std.mem.concat(a, u8, &.{ "const U32.twice = fn (value: U32) => fn (delta: U32) => @u32.add value delta\n", associated });
    defer a.free(source);
    var before = try prepare(a, source, null);
    defer before.deinit(a);
    const ordinary = before.bodies.find("unrelated") orelse return error.TestUnexpectedResult;
    try std.testing.expect(ordinary.selection_digest != null);
    try std.testing.expect(before.bodies.find("selected").?.implementation_selection);
    var repeated = try prepare(a, source, &before.bodies);
    defer repeated.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), repeated.elaborations);
    const changed = try std.mem.replaceOwned(u8, a, source, "@u32.add value delta", "@u32.sub value delta");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var result = try compile(a, &fresh);
    defer result.deinit(a);
    try compare(a, &before.bodies, changed, result.bytes, 2);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, result.bytes, @as(usize, 2) });
    // Adding an unrelated contract cannot revoke an ordinary member proof.
    const added = try std.mem.concat(a, u8, &.{ source, "\ntype Marker s is contract = { type Item }\nimpl Marked : Marker F32 = { type Item = F32 }\n" });
    defer a.free(added);
    try parity(source, added, 2);
}

const loop_source =
    \\const seed = 2
    \\const sum = fn (limit: U32) -> U32 => do:
    \\  let total = seed
    \\  for index in 0..limit:
    \\    for 0..2:
    \\      total := @u32.add self index
    \\      if @u32.lt 3 total:
    \\        break
    \\  for value in [1, 2]:
    \\    total := @u32.add self value
    \\  for ever:
    \\    total := @u32.add self 1
    \\    let total = 42
    \\    break
    \\  return total
    \\entry const run = fn (limit: U32) -> U32 => sum limit
;

test "body check cache relocates ordinary loop carries and lexical break snapshots through OOM" {
    var before = try prepare(a, loop_source, null);
    defer before.deinit(a);
    const receipt = before.bodies.find("sum") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 4), receipt.loops.?.carries.len);
    try std.testing.expectEqual(@as(usize, 2), receipt.loops.?.exits.len);
    const changed = "const earlier = fn (value: F32) -> F32 => @f32.add value 1.0\n" ++ loop_source;
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var result = try compile(a, &fresh);
    defer result.deinit(a);
    try compare(a, &before.bodies, changed, result.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, result.bytes, @as(usize, 1) });
    // Changed bounds, writes and lexical exits must elaborate normally.
    const rewritten = "const seed = 2\nconst sum = fn (limit: U32) -> U32 => do:\n  let total = seed\n  for index in 1..limit:\n    total := @u32.add self index\n  return total\nentry const run = fn (limit: U32) -> U32 => sum limit\n";
    var rewritten_fresh = try prepare(a, rewritten, null);
    defer rewritten_fresh.deinit(a);
    var rewritten_result = try compile(a, &rewritten_fresh);
    defer rewritten_result.deinit(a);
    try compare(a, &before.bodies, rewritten, rewritten_result.bytes, 1);
}

fn captureLoops(allocator: A) !void {
    var output = try prepare(allocator, loop_source, null);
    defer output.deinit(allocator);
    const receipt = output.bodies.find("sum") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 4), receipt.loops.?.carries.len);
    try std.testing.expectEqual(@as(usize, 2), receipt.loops.?.exits.len);
}

test "body check cache loop receipt publication releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, captureLoops, .{});
}

const used_values =
    \\const seed = 2
    \\const helper = fn (value: U32) -> U32 => do:
    \\  use initial <- @u32.add value seed
    \\  use initial
    \\  let result = initial
    \\  for index in 0..2:
    \\    use snapshot <- result
    \\    result := @u32.add self index
    \\    use snapshot
    \\  return result
    \\entry const run = fn (value: U32) -> U32 => helper value
;

fn captureUsedValues(allocator: A) !void {
    var output = try prepare(allocator, used_values, null);
    defer output.deinit(allocator);
    try std.testing.expect(output.bodies.find("helper") != null);
}

test "body check cache owns ordinary use values and monomorphic named bindings through OOM" {
    var before = try prepare(a, used_values, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("helper") != null);
    const changed = "const earlier = 4.0\n" ++ used_values;
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var result = try compile(a, &fresh);
    defer result.deinit(a);
    try compare(a, &before.bodies, changed, result.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, result.bytes, @as(usize, 1) });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, captureUsedValues, .{});
}

const path_update_source =
    \\type Point is data = #Point { x: U32, y: U32 }
    \\type Bucket is data = #Bucket { points: Array Point }
    \\const seed = 2
    \\const update = fn (index: U32) -> U32 => do:
    \\  let bucket = #Bucket { points: #[#Point { y: 1, x: 10 }, #Point { y: 2, x: 20 }] }
    \\  let before = bucket
    \\  bucket.points[index].x := @u32.add self seed
    \\  return @u32.add before.points[index].x bucket.points[index].x
    \\const replace = fn values => fn index => fn value => do:
    \\  values[index] := value
    \\  return values
    \\entry const run = fn (index: U32) -> U32 => update index
;
fn capturePathUpdates(allocator: A) !void {
    var output = try prepare(allocator, path_update_source, null);
    defer output.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), output.bodies.find("update").?.rebindings.len);
    try std.testing.expectEqual(@as(usize, 1), output.bodies.find("replace").?.rebindings.len);
}
test "body check cache restores mixed nominal Array updates and leaf self identities through OOM" {
    var before = try prepare(a, path_update_source, null);
    defer before.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), before.bodies.find("update").?.rebindings.len);
    try std.testing.expectEqual(@as(usize, 1), before.bodies.find("replace").?.rebindings.len);
    const changed = "const earlier = fn (value: F32) => @f32.add value 1.0\n" ++ path_update_source;
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var result = try compile(a, &fresh);
    defer result.deinit(a);
    try compare(a, &before.bodies, changed, result.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, result.bytes, @as(usize, 1) });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, capturePathUpdates, .{});
}

const demanded_body_source =
    \\const seed = 2
    \\const force = fn ~(value: U32) -> U32 => @demand value
    \\const twice = fn (value: U32) => do:
    \\  let delayed = fn ~(input: U32) => @u32.add (@force input) (@force input)
    \\  return delayed (@u32.add value seed)
    \\entry const run = fn (value: U32) => @u32.add (force value) (twice value)
;
test "body check cache demand call reconstruction owns fresh and replayed suspension metadata through OOM" {
    var before = try prepare(a, demanded_body_source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("force") != null);
    try std.testing.expect(before.bodies.find("twice") != null);
    const changed = try std.mem.replaceOwned(u8, a, demanded_body_source, "seed = 2", "seed = 3");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var result = try compile(a, &fresh);
    defer result.deinit(a);
    try compare(a, &before.bodies, changed, result.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, result.bytes, @as(usize, 1) });
}

const user_row_source = "effect Read: Unit -> U32\nprivate const invoke = fn (host: Unit -> U32 ! {Read}) => host ()\nprivate const identity = fn (host: Unit -> U32 ! {Read}) => host\nentry const answer = 42\n";
fn captureUserRows(allocator: A) !void {
    var output = try prepare(allocator, user_row_source, null);
    defer output.deinit(allocator);
    try std.testing.expect(output.bodies.find("invoke") != null);
    try std.testing.expect(output.bodies.find("identity") != null);
}
test "body check cache user operation rows relocate and own all allocation failures" {
    var before = try prepare(a, user_row_source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("invoke") != null);
    const inserted = try a.print("effect Earlier: Bool -> Bool\nconst earlier = 9\n{s}", .{user_row_source});
    defer a.free(inserted);
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, captureUserRows, .{});
    const private = try std.mem.replaceOwned(u8, a, user_row_source, "effect Read", "private effect Read");
    defer a.free(private);
    try parity(user_row_source, private, 2);
    const signature = try std.mem.replaceOwned(u8, a, user_row_source, "effect Read: Unit -> U32", "effect Read: Bool -> U32");
    defer a.free(signature);
    try parity(user_row_source, signature, 2);
}
test "body check cache user operation rows keep open variables and static invocation recipes" {
    const open = "effect Read: Unit -> U32\nconst invoke: (Unit -> U32 ! {Read |e}) -> U32 ! {Read |e} = fn host => host ()\nentry const answer = 42\n";
    try parity(open, open, 0);
    const invocation = "effect Read: Unit -> U32\nconst invoke = fn () => Read ()\n";
    var output = try prepare(a, invocation, null);
    defer output.deinit(a);
    try std.testing.expect(output.bodies.find("invoke") != null);
}

const static_operation_source = "effect Read: Unit -> U32\nconst seed = 2\nconst invoke = fn () => @u32.add (Read ()) seed\nentry const answer = 42\n";
fn captureStaticOperation(allocator: A) !void {
    var output = try prepare(allocator, static_operation_source, null);
    defer output.deinit(allocator);
    const body = output.bodies.find("invoke").?;
    const owner = body.auxiliary orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), owner.tables.operation_uses.len);
}
test "body check cache static operation calls restore current targets through all allocation failures" {
    var before = try prepare(a, static_operation_source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("invoke") != null);
    const changed = "effect Earlier: Bool -> Bool\n" ++ static_operation_source;
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 0);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 0) });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, captureStaticOperation, .{});
    const renamed = try std.mem.replaceOwned(u8, a, static_operation_source, "effect Read:", "effect Other:");
    defer a.free(renamed);
    const shadowed = try a.print("const Read = fn () => 7\n{s}", .{renamed});
    defer a.free(shadowed);
    var changed_output = try prepare(a, shadowed, &before.bodies);
    defer changed_output.deinit(a);
    try std.testing.expect(changed_output.elaborations > 0);
}

fn importedUserRow(allocator: A, unit: u32, origin: cache.Digest, retarget: bool, specialized: bool, previous: ?*const cache.Cache) !Output {
    return importedUserBody(allocator, unit, origin, retarget, specialized, previous, false);
}
fn importedUserBody(allocator: A, unit: u32, origin: cache.Digest, retarget: bool, specialized: bool, previous: ?*const cache.Cache, static: bool) !Output {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var parameter: []const u8 = "a";
    if (specialized) parameter = "U32";
    var producer_source: []u8 = undefined;
    if (static) {
        producer_source = try allocator.dupe(u8, "effect Earlier: Bool -> Bool\ntype Read is effect = {ask: Unit -> U32}\ntype Twin is effect = {ask: Unit -> U32}\n");
    } else producer_source = try allocator.print("effect Earlier: Bool -> Bool\ntype Read a is effect = {{ask: Unit -> {s}, unused: a -> Unit}}\ntype Twin a is effect = {{ask: Unit -> a, unused: a -> Unit}}\n", .{parameter});
    defer allocator.free(producer_source);
    var producer_tokens = try lexer.lex(allocator, producer_source);
    defer producer_tokens.deinit(allocator);
    var producer_tree = try parser.parse(allocator, producer_source, producer_tokens.tokens.items, &pool);
    defer producer_tree.deinit(allocator);
    var producer = try check.checkModuleWithOptions(allocator, &producer_tree, &pool, &.{}, &.{}, unit, .{ .builtin_catalog = true });
    defer producer.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), producer.diagnostics.len);
    var source: []const u8 = "const keep = fn (callback: Unit -> U32 ! {Alias.ask U32}) => callback\nentry const answer = 42\n";
    if (static) source = "const keep = fn () => Alias.ask ()\nentry const answer = 42\n";
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var target: u32 = 2;
    if (retarget) target = 3;
    const imported: check.ImportedCatalog = .{ .producer = &producer, .name = pool.lookup("Alias").?, .kind = .effect_family, .index = target, .origin = 0 };
    const complete: check.ImportedCatalog = .{ .producer = &producer, .kind = .catalog, .index = 0, .origin = 0 };
    const receipt: ImportedReceipt = .{ .name = "unused", .unit = unit, .origin = origin, .closed_rows = @splat(0) };
    const names: cache.ExternalNames = .{ .context = &receipt, .lookup = importedName, .unit_origin = importedUnitOrigin };
    var bodies: cache.Cache = .{ .minimum_nodes = 0 };
    errdefer bodies.deinit(allocator);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{ complete, imported }, 1, .{ .builtin_catalog = true, .body_source = source, .body_external_names = names, .previous_bodies = previous, .retained_bodies = &bodies });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expect(bodies.find("keep") != null);
    return .{ .bodies = bodies, .module = try core.lower(allocator, &tree, &pool, &checked), .elaborations = checked.body_elaborations };
}
fn replayImportedUserRow(allocator: A, previous: *const cache.Cache) !void {
    var output = try importedUserRow(allocator, 3, @splat(7), false, false, previous);
    defer output.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), output.elaborations);
}
test "body check cache user operation rows require exact alias producer and generic recipe" {
    var before = try importedUserRow(a, 2, @splat(7), false, false, null);
    defer before.deinit(a);
    try replayImportedUserRow(a, &before.bodies);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayImportedUserRow, .{&before.bodies});
    var retargeted = try importedUserRow(a, 3, @splat(7), true, false, &before.bodies);
    defer retargeted.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), retargeted.elaborations);
    var wrong_origin = try importedUserRow(a, 3, @splat(8), false, false, &before.bodies);
    defer wrong_origin.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), wrong_origin.elaborations);
    // The observed member is still Unit -> U32 at this use, but the family
    // declaration lost a generic result dependency.
    var specialized = try importedUserRow(a, 3, @splat(7), false, true, &before.bodies);
    defer specialized.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), specialized.elaborations);
}

fn replayImportedStaticOperation(allocator: A, previous: *const cache.Cache) !void {
    var replayed = try importedUserBody(allocator, 3, @splat(7), false, false, previous, true);
    defer replayed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), replayed.elaborations);
    var fresh = try importedUserBody(allocator, 3, @splat(7), false, false, null, true);
    defer fresh.deinit(allocator);
    var expected = try compile(allocator, &fresh);
    defer expected.deinit(allocator);
    var actual = try compile(allocator, &replayed);
    defer actual.deinit(allocator);
    try std.testing.expectEqualSlices(u8, expected.bytes, actual.bytes);
}
test "body check cache static operation calls reject retargeted imported aliases through OOM" {
    var before = try importedUserBody(a, 2, @splat(7), false, false, null, true);
    defer before.deinit(a);
    try replayImportedStaticOperation(a, &before.bodies);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayImportedStaticOperation, .{&before.bodies});
    var retargeted = try importedUserBody(a, 3, @splat(7), true, false, &before.bodies, true);
    defer retargeted.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), retargeted.elaborations);
    var changed_origin = try importedUserBody(a, 3, @splat(8), false, false, &before.bodies, true);
    defer changed_origin.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), changed_origin.elaborations);
}

test "body check cache user operation rows traverse demand boundaries" {
    const source = "effect Read: Unit -> U32\nconst force = fn ~(value: U32) => @force value\nconst invoke = fn (callback: Unit -> U32 ! {Read}) => force (callback ())\nentry const answer = 42\n";
    try parity(source, source, 0);
    const changed = try std.mem.replaceOwned(u8, a, source, "effect Read: Unit -> U32", "effect Read: Bool -> Bool");
    defer a.free(changed);
    try parity(source, changed, 1);
}

test "body check cache user operation rows reject unknown ambiguous and malformed catalog authority" {
    const source = "effect Read: Unit -> U32\n";
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(a);
    var catalog: cache.Catalog = .{ .unit = 1, .pool = &pool, .nominals = checked.nominals, .constructors = checked.constructors, .effect_families = checked.effect_families, .effect_templates = checked.effect_templates, .patterns = .{ .store = &checked.parameter_patterns } };
    const typed: @import("../check/frozen_types.zig").Source = .{ .store = &checked.types };
    const digest = cache.operationDigest(typed, catalog, 1).?;
    const origin = catalog.unitOrigin(1).?;
    try std.testing.expect(catalog.namedOperation(origin, "4:ReadRead") != null);
    try std.testing.expect(catalog.namedOperation(origin, "4:ReadOther") == null);
    try std.testing.expect(catalog.namedOperation(origin, "999:ReadRead") == null);
    try std.testing.expect(catalog.namedOperation(origin, "missing") == null);
    const duplicate = [_]check.EffectTemplate{ checked.effect_templates[1], checked.effect_templates[1] };
    catalog.effect_templates = &duplicate;
    var budget: usize = 4096;
    try std.testing.expect(catalog.operation(checked.effect_templates[1].identity, &budget) == null);
    try std.testing.expect(catalog.namedOperation(origin, "4:ReadRead") == null);
    catalog.effect_templates = checked.effect_templates;
    checked.effect_families[1].callable = false;
    const changed = cache.operationDigest(typed, catalog, 1).?;
    try std.testing.expect(!std.mem.eql(u8, &digest, &changed));
    checked.effect_families[1].patterns.len = 1;
    try std.testing.expect(cache.operationDigest(typed, catalog, 1) == null);
    checked.effect_families[1].patterns.len = 0;
    checked.effect_templates[1].family = 999;
    try std.testing.expect(cache.operationDigest(typed, catalog, 1) == null);
}

test "body check cache user operation rows preserve unknown and malformed annotation diagnostics" {
    for ([_][]const u8{
        "effect Read: Unit -> U32\nconst invoke = fn (callback: Unit -> U32 ! {Unknown}) => callback ()\n",
        "effect Read: Unit -> U32\nconst invoke = fn (callback: Unit -> U32 ! {Read U32}) => callback ()\n",
    }) |source| {
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        var bodies: cache.Cache = .{ .minimum_nodes = 0 };
        defer bodies.deinit(a);
        var checked = try check.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true, .body_source = source, .retained_bodies = &bodies });
        defer checked.deinit(a);
        try std.testing.expect(checked.diagnostics.len != 0);
        try std.testing.expect(bodies.find("invoke") == null);
    }
}

const compound_loop_order =
    \\data Bundle = #Bundle {earlier: List U32, current: List U32, alias: List U32, other: List U32}
    \\const grown = do:
    \\  let values: List U32 = []
    \\  let earlier: List U32 = []
    \\  let other: List U32 = []
    \\  for index in 0..32:
    \\    values := if @u32.lt index 16 then @list.append values index else @list.prepend values index
    \\    other := @list.append other (@u32.add index 100)
    \\    earlier := if @u32.eq index 30 then values else earlier
    \\  return #Bundle {earlier: earlier, current: values, alias: values, other: other}
    \\entry const run = fn () => @array.from_list grown.current
    \\entry const sibling = 1
;
fn replayCompoundOrder(allocator: A, previous: *const cache.Cache, current: []const u8, expected: *const core.Module) !void {
    var replayed = try prepare(allocator, current, previous);
    defer replayed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), replayed.elaborations);
    try std.testing.expectEqualDeep(expected.references, replayed.module.references);
    try std.testing.expectEqualDeep(expected.loop_carries, replayed.module.loop_carries);
    try std.testing.expectEqualDeep(expected.bindings, replayed.module.bindings);
    try std.testing.expectEqualDeep(expected.types, replayed.module.types);
}
fn captureCompoundOrder(allocator: A) !void {
    var output = try prepare(allocator, compound_loop_order, null);
    defer output.deinit(allocator);
    try std.testing.expect(output.bodies.find("grown") != null);
    for (output.module.types.nodes, 0..) |node, index| {
        if ((node.tag == .array or node.tag == .list or node.tag == .cursor) and node.a > 0 and node.a < 6) {
            for (output.module.types.nodes[0..index]) |prior| try std.testing.expect(node.tag != prior.tag or node.a != prior.a);
        }
        if (node.tag == .nominal and output.module.types.nominalArguments(node).len == 0) {
            for (output.module.types.nodes[0..index]) |prior| {
                if (prior.tag != .nominal or output.module.types.nominalArguments(prior).len != 0) continue;
                try std.testing.expect(node.a != prior.a or node.b != prior.b);
            }
        }
    }
}
test "body check cache preserves compound loop successor creation order through OOM" {
    try captureCompoundOrder(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, captureCompoundOrder, .{});
    var before = try prepare(a, compound_loop_order, null);
    defer before.deinit(a);
    const edited = try a.dupe(u8, compound_loop_order);
    defer a.free(edited);
    edited[edited.len - 1] = '2';
    var fresh = try prepare(a, edited, null);
    defer fresh.deinit(a);
    try replayCompoundOrder(a, &before.bodies, edited, &fresh.module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayCompoundOrder, .{ &before.bodies, edited, &fresh.module });
}

const numeric_owner_source =
    \\const seed = 2
    \\const globals = #[seed, 13]
    \\const cursor = 0
    \\const witness: (values: Array U32) -> (index: U32) -> @proof.Index values index = fn values => fn index => @proof.index values index
    \\const at: (values: Array U32) -> (index: U32) -> (@proof.Index values index) -> U32 = fn values => fn index => fn proof => @array.get values index
    \\const checked = fn (index: U32) => do:
    \\  let values = #[seed, 13]
    \\  let alias = values
    \\  let valid = witness alias index
    \\  return at values index valid
    \\const late = fn (index: U32) => do:
    \\  let valid = @proof.index globals cursor
    \\  return at globals cursor valid
    \\entry const run = fn () => @u32.add (checked 0) (late 1)
;
test "body check cache transports erased numeric contract operands and guards through relocation and OOM" {
    var before = try prepare(a, numeric_owner_source, null);
    defer before.deinit(a);
    for ([_][]const u8{ "witness", "at", "checked", "late", "run" }) |name| {
        if (before.bodies.find(name) == null) std.debug.print("missing numeric owner body {s}\n", .{name});
        try std.testing.expect(before.bodies.find(name) != null);
    }
    const changed = try std.mem.replaceOwned(u8, a, numeric_owner_source, "const seed = 2", "const seed = 3");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    var reused = try prepare(a, changed, &before.bodies);
    defer reused.deinit(a);
    try std.testing.expect(fresh.proof_visits != 0);
    try std.testing.expectEqual(fresh.proof_visits, reused.proof_visits);
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
    const inserted = try a.print("type Earlier is data = #Earlier F32\nconst earlier = fn (unrelated: F32) => unrelated\n{s}", .{changed});
    defer a.free(inserted);
    var fresh_inserted = try prepare(a, inserted, null);
    defer fresh_inserted.deinit(a);
    var inserted_expected = try compile(a, &fresh_inserted);
    defer inserted_expected.deinit(a);
    try compare(a, &before.bodies, inserted, inserted_expected.bytes, 2);
}

fn changedNumericHeader(allocator: A, previous: *const cache.Cache, source: []const u8) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var fresh = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer fresh.deinit(allocator);
    var reused = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true, .body_source = source, .previous_bodies = previous });
    defer reused.deinit(allocator);
    try std.testing.expect(fresh.diagnostics.len != 0);
    try std.testing.expectEqual(fresh.diagnostics.len, reused.diagnostics.len);
    var mismatch = false;
    for (fresh.diagnostics, reused.diagnostics) |expected, actual| {
        if (expected.code == .proof_mismatch) mismatch = true;
        try std.testing.expectEqual(expected.code, actual.code);
        try std.testing.expectEqual(expected.span, actual.span);
    }
    try std.testing.expect(mismatch);
}
test "body check cache revokes numeric consumers when only a positional proof operand changes" {
    var before = try prepare(a, numeric_owner_source, null);
    defer before.deinit(a);
    const changed = try std.mem.replaceOwned(u8, a, numeric_owner_source, "(@proof.Index values index) -> U32", "(@proof.Index values 1) -> U32");
    defer a.free(changed);
    try changedNumericHeader(a, &before.bodies, changed);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, changedNumericHeader, .{ &before.bodies, changed });
}

const tagged_owner_source =
    \\const seed = 2
    \\const decorate = fn (value: U32) => fn () => @u32.add value seed
    \\const outer = fn (callback: Unit -> U32) => fn () => @u32.add (callback ()) 1
    \\@[outer] @[decorate] const tagged: Unit -> U32 = 40
    \\@[fn (value: U32) => @u32.add value 1] let started: U32 = 41
    \\entry const run = fn () => @u32.add (tagged ()) started
;
test "body check cache retains complete ordered tag applications and their outer result through OOM" {
    var before = try prepare(a, tagged_owner_source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("tagged") != null);
    try std.testing.expect(before.bodies.find("started") != null);
    const changed = try std.mem.replaceOwned(u8, a, tagged_owner_source, "const seed = 2", "const seed = 3");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
    const inserted = try a.print("const earlier = fn (unrelated: F32) => unrelated\n{s}", .{changed});
    defer a.free(inserted);
    var fresh_inserted = try prepare(a, inserted, null);
    defer fresh_inserted.deinit(a);
    var inserted_expected = try compile(a, &fresh_inserted);
    defer inserted_expected.deinit(a);
    try compare(a, &before.bodies, inserted, inserted_expected.bytes, 2);
}

const selected_scope_owner_source =
    \\const seed = 2
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const selected = fn (flag: Bool) => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
    \\  let chosen = if flag then left else right
    \\  let alias = chosen
    \\  let (state, result) = do (@effect.state chosen.get chosen.set seed):
    \\    use alias.set 42
    \\    return alias.get ()
    \\  return result
    \\))
    \\entry const run = fn () => selected #True
;
test "body check cache transports selected fresh scope versions through relocation and OOM" {
    var before = try prepare(a, selected_scope_owner_source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("selected") != null);
    const changed = try std.mem.replaceOwned(u8, a, selected_scope_owner_source, "const seed = 2", "const seed = 3");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
    const inserted = try a.print("const earlier = fn (unrelated: F32) => unrelated\n{s}", .{changed});
    defer a.free(inserted);
    var fresh_inserted = try prepare(a, inserted, null);
    defer fresh_inserted.deinit(a);
    var inserted_expected = try compile(a, &fresh_inserted);
    defer inserted_expected.deinit(a);
    try compare(a, &before.bodies, inserted, inserted_expected.bytes, 2);
}

const iterator_owner_source =
    \\const seed = 2
    \\type Maybe a is data = #Some a | #Nothing
    \\type Counter is data = #Counter U32
    \\const Counter.iter = fn (cursor: Counter) => cursor
    \\const Counter.next = fn (#Counter value) => if @u32.lt value 4 then #Some (value, #Counter (@u32.add value 1)) else #Nothing
    \\const total = fn (first: U32) => do:
    \\  let result = seed
    \\  for value in #Counter first:
    \\    result := @u32.add self value
    \\  return result
    \\entry const run = fn () => total 1
;
test "body check cache transports actual generated iterator owners through relocation and OOM" {
    var before = try prepare(a, iterator_owner_source, null);
    defer before.deinit(a);
    const receipt = before.bodies.find("total") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 1), receipt.auxiliary.?.iterators.len);
    const changed = try std.mem.replaceOwned(u8, a, iterator_owner_source, "const seed = 2", "const seed = 3");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
    const inserted = try a.print("const earlier = fn (unrelated: F32) => unrelated\n{s}", .{changed});
    defer a.free(inserted);
    var fresh_inserted = try prepare(a, inserted, null);
    defer fresh_inserted.deinit(a);
    var inserted_expected = try compile(a, &fresh_inserted);
    defer inserted_expected.deinit(a);
    try compare(a, &before.bodies, inserted, inserted_expected.bytes, 2);
}

const resolver_owner_source =
    \\const seed = 2
    \\type Iteration [state,result] is data = #Continue state | #Done result
    \\type Maybe value is data = #Some value | #Nothing
    \\const monad = fn constructor => @do.monad constructor
    \\const Maybe.pure = fn value => #Some value
    \\const Maybe.bind = fn candidate => fn next => case candidate of
    \\  #Some value => next value
    \\  #Nothing => #Nothing
    \\const Maybe.iterate = fn initial => fn step => do:
    \\  let state = initial
    \\  for ever:
    \\    use candidate <- step state
    \\    if let #Some (#Done result) = candidate:
    \\      return #Some result
    \\    let #Some (#Continue next) = candidate else:
    \\      return #Nothing
    \\    state := next
    \\const sequence = fn forwarded => do (monad Maybe):
    \\  let total = seed
    \\  for outer in 0..2:
    \\    for inner in 0..2:
    \\      use value <- #Some 1
    \\      total := @u32.add self value
    \\      if forwarded:
    \\        return $ #Some (@u32.add total 21)
    \\      if @u32.eq inner 1:
    \\        return @u32.add total 20
    \\      break
    \\  return total
    \\entry const answer = fn () => case sequence #True of
    \\  #Some value => value
    \\  #Nothing => 0
;

test "body check cache transports resolver joins completions and nested iterate owners through relocation and OOM" {
    var before = try prepare(a, resolver_owner_source, null);
    defer before.deinit(a);
    const receipt = before.bodies.find("sequence") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 2), receipt.auxiliary.?.tables.resolver_loops.len);
    const changed = try std.mem.replaceOwned(u8, a, resolver_owner_source, "const seed = 2", "const seed = 3");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    const ordinary = fresh.elaborations - before.bodies.bodies.items.len + 1;
    try compare(a, &before.bodies, changed, expected.bytes, ordinary);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compareChecked, .{ &before.bodies, changed, &fresh.module, ordinary });
    const inserted = try a.print("type Earlier is data = #Earlier F32\nconst earlier = fn (unrelated: F32) => unrelated\n{s}", .{changed});
    defer a.free(inserted);
    var fresh_inserted = try prepare(a, inserted, null);
    defer fresh_inserted.deinit(a);
    var inserted_expected = try compile(a, &fresh_inserted);
    defer inserted_expected.deinit(a);
    try compare(a, &before.bodies, inserted, inserted_expected.bytes, ordinary + 1);
}

fn compareChecked(allocator: A, previous: *const cache.Cache, source: []const u8, expected: *const core.Module, elaborations: usize) !void {
    var output = try prepare(allocator, source, previous);
    defer output.deinit(allocator);
    try std.testing.expectEqual(elaborations, output.elaborations);
    try std.testing.expectEqual(expected.resolver_ops.len, output.module.resolver_ops.len);
    try @import("../check/frozen_core_validation.zig").validate(allocator, &output.module, .{ .units = &.{&output.module}, .source_length = @intCast(source.len) });
}

const local_generation_owner_source =
    \\const seed = 2
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const selected = fn (flag: Bool) => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
    \\  let choose = fn () => if flag then left else right
    \\  let chosen = choose ()
    \\  let alias = chosen
    \\  let (state, result) = do (@effect.state chosen.get chosen.set seed):
    \\    use alias.set 42
    \\    return alias.get ()
    \\  return result
    \\))
    \\entry const run = fn () => selected #True
;
test "body check cache transports local invocation generation owners and fresh ordinals through relocation and OOM" {
    var before = try prepare(a, local_generation_owner_source, null);
    defer before.deinit(a);
    const receipt = before.bodies.find("selected") orelse return error.TestUnexpectedResult;
    try std.testing.expect(receipt.auxiliary.?.tables.generative_bindings.len != 0);
    const changed = try std.mem.replaceOwned(u8, a, local_generation_owner_source, "const seed = 2", "const seed = 3");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
    const inserted = try a.print("const earlier = fn (unrelated: F32) => unrelated\n{s}", .{changed});
    defer a.free(inserted);
    var fresh_inserted = try prepare(a, inserted, null);
    defer fresh_inserted.deinit(a);
    var inserted_expected = try compile(a, &fresh_inserted);
    defer inserted_expected.deinit(a);
    try compare(a, &before.bodies, inserted, inserted_expected.bytes, 2);
}

const task_view_owner_source =
    \\const seed = 2
    \\const partition = fn (owner: unique (Array U32)) => do:
    \\  let (owner, result) = @task.split owner ((0, 2), (2, 4)) (fn views => do:
    \\    let (left, right) = views
    \\    return @task.scope (fn group => do:
    \\      let first = @task.spawn group (fn () => @u32.add seed (@task.read left 0))
    \\      let second = @task.spawn group (fn () => @task.read right 0)
    \\      return @u32.add (@task.join first) (@task.join second)))
    \\  return result
    \\entry const view = fn (owner: unique (Array U32)) => partition owner
;
test "body check cache transports actual task view binding versions through relocation and OOM" {
    var before = try prepare(a, task_view_owner_source, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("partition") != null);
    try std.testing.expect(before.bodies.find("view") != null);
    const changed = try std.mem.replaceOwned(u8, a, task_view_owner_source, "const seed = 2", "const seed = 3");
    defer a.free(changed);
    var fresh = try prepare(a, changed, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, changed, expected.bytes, 1);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, compareChecked, .{ &before.bodies, changed, &fresh.module, @as(usize, 1) });
    const inserted = try a.print("type Earlier is data = #Earlier F32\nconst earlier = fn (unrelated: F32) => unrelated\n{s}", .{changed});
    defer a.free(inserted);
    var fresh_inserted = try prepare(a, inserted, null);
    defer fresh_inserted.deinit(a);
    var inserted_expected = try compile(a, &fresh_inserted);
    defer inserted_expected.deinit(a);
    try compare(a, &before.bodies, inserted, inserted_expected.bytes, 2);
}
