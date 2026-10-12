const std = @import("std");
const cache = @import("body_check_cache.zig");
const check = @import("check.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const A = std.mem.Allocator;
const a = std.testing.allocator;
const text =
    \\const seed = 2
    \\const sibling = fn (value: U32) -> U32 => @u32.add value seed
    \\entry const run = fn (argument: U32) -> U32 => sibling argument
;
const Output = struct {
    bodies: cache.Cache,
    module: core.Module,
    elaborations: usize,
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
    var checked = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true, .body_source = source, .previous_bodies = previous, .retained_bodies = &owned });
    defer checked.deinit(allocator);
    for (checked.diagnostics) |issue| std.debug.print("body cache {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    if (retain) try cache.captureInto(allocator, &tree, &pool, source, &checked, null, &owned);
    return .{ .bodies = owned, .module = try core.lower(allocator, &tree, &pool, &checked), .elaborations = checked.body_elaborations };
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, result.bytes, @as(usize, 1) });
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

test "body check cache keeps recursive components and demanded bodies ordinary" {
    const recursive = "const first = fn (n: U32) -> U32 => if @u32.eq n 0 then 4 else second (@u32.sub n 1)\nconst second = fn (n: U32) -> U32 => if @u32.eq n 0 then 5 else first (@u32.sub n 1)\nentry const run = fn (n: U32) -> U32 => first n\nconst unrelated = 7\n";
    var before = try prepare(a, recursive, null);
    defer before.deinit(a);
    var retained = try prepare(a, recursive, &before.bodies);
    defer retained.deinit(a);
    try std.testing.expect(retained.elaborations >= 2);
    const demanded = "const force = fn ~(x: U32) -> U32 => @demand x\nentry const run = fn (n: U32) -> U32 => force n\nconst unrelated = 7\n";
    try parity(demanded, demanded, 2);
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, cloneScenario, .{&before.bodies});
}

test "body check cache sparse storage and elaboration scale with admitted declarations" {
    const memory = @import("memory.zig");
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

test "body check cache declines effect annotations and preserves unresolved selection diagnostics" {
    const effectful = "const invoke = fn (host: U32 -> U32 ! {Foreign}) => host 42\nentry const run = fn (host: U32 -> U32 ! {Foreign}) => invoke host\nconst unrelated = 7\n";
    var before = try prepare(a, effectful, null);
    defer before.deinit(a);
    try std.testing.expect(before.bodies.find("invoke") == null);
    try std.testing.expect(before.bodies.find("run") == null);
    try parity(effectful, effectful, 2);
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

const ImportedReceipt = struct { name: []const u8, closed_rows: cache.Digest };
fn importedClosedRows(context: *const anyopaque, target: check.ExternalTarget) ?cache.Digest {
    if (target.unit != 2 or target.binding != 1) return null;
    const receipt: *const ImportedReceipt = @ptrCast(@alignCast(context));
    return receipt.closed_rows;
}
fn importedName(context: *const anyopaque, target: check.ExternalTarget) ?[]const u8 {
    if (target.unit != 2 or target.binding != 1) return null;
    const receipt: *const ImportedReceipt = @ptrCast(@alignCast(context));
    return receipt.name;
}
fn importedConsumer(allocator: A, original_name: []const u8, previous: ?*const cache.Cache) !Output {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    const producer_source = try allocator.print("const {s} = fn (x: U32) -> U32 => x\n", .{original_name});
    defer allocator.free(producer_source);
    var producer_tokens = try lexer.lex(allocator, producer_source);
    defer producer_tokens.deinit(allocator);
    var producer_tree = try parser.parse(allocator, producer_source, producer_tokens.tokens.items, &pool);
    defer producer_tree.deinit(allocator);
    var producer = try check.checkModuleWithOptions(allocator, &producer_tree, &pool, &.{}, &.{}, 2, .{ .builtin_catalog = true });
    defer producer.deinit(allocator);
    const source = "entry const run = fn (x: U32) -> U32 => exposed x\nconst untouched = 7\n";
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    const imported = check.ImportedBinding{ .origin = 0, .name = pool.lookup("exposed").?, .target = .{ .unit = 2, .binding = 1 }, .interface = .{ .types = .{ .store = &producer.types }, .scheme = producer.bindings[1].scheme, .named_function = true, .obligations = producer.obligations } };
    const receipt: ImportedReceipt = .{ .name = original_name, .closed_rows = cache.closedRowsDigest(.{ .store = &producer.types }, producer.bindings[1].ty, producer.bindings[1].scheme, &pool).? };
    const names: cache.ExternalNames = .{ .context = @ptrCast(&receipt), .lookup = importedName, .closed_rows = importedClosedRows };
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compactFailure, .{ &previous.bodies, next_source });
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, after_text, result.bytes, @as(usize, 1) });
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
    var expression = try a.dupe(u8, "x");
    defer a.free(expression);
    for (0..12) |_| {
        const next = try a.print("@u32.add ({s}) 0", .{expression});
        a.free(expression);
        expression = next;
    }
    const stable = try a.print("const preserved = fn (x: U32) -> U32 => {s}\nentry const run = fn (x: U32) -> U32 => preserved x\n", .{expression});
    defer a.free(stable);
    const first_source = try a.print("{s}const wide = fn x => supplier x\n{s}", .{ producer.items, stable });
    defer a.free(first_source);
    var first = try prepare(a, first_source, null);
    defer first.deinit(a);
    const old = first.bodies.find("preserved").?;
    const removed = first.bodies.find("wide").?;
    // Byte occupancy alone would retain the old graph, even though the old
    // wide result accounts for most type projection work in that graph.
    try std.testing.expect(old.bytes() * 2 > old.owner.body_bytes);
    try std.testing.expect(removed.type_work * 2 > old.owner.type_work);
    const next_source = try a.print("{s}const wide = fn x => @u32.add x 1\n{s}", .{ producer.items, stable });
    defer a.free(next_source);
    var next = try prepare(a, next_source, &first.bodies);
    defer next.deinit(a);
    try std.testing.expect(next.bodies.find("preserved").?.owner != old.owner);
    try std.testing.expectEqual(@as(usize, 2), next.elaborations);
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &first.bodies, next_source, expected.bytes, @as(usize, 1) });
    // The helper's symbolic row must remain open for Foreign callbacks. A
    // consumer with explicit effect syntax stays ordinary in this slice.
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
    try std.testing.expect(before.bodies.find("make") == null);
    const inserted = "type Earlier is data = #Earlier F32\nconst earlier_spelling = fn (f: F32) -> F32 => @f32.add f 2.0\ntype Token is data = #Token U32\nconst make = fn (n: U32) => #Token n\nconst identity = fn (value: Token) -> Token => value\nconst read = fn (#Token value) => value\nentry const run = fn (n: U32) => read (identity (make n))\n";
    var fresh = try prepare(a, inserted, null);
    defer fresh.deinit(a);
    var expected = try compile(a, &fresh);
    defer expected.deinit(a);
    try compare(a, &before.bodies, inserted, expected.bytes, 3);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 3) });
    const alias_first = "type First is data = #First U32\ntype Second is data = #Second U32\ntype Alias = First\nconst identity = fn (value: Alias) -> Alias => value\nconst read = fn (#First value) => value\nentry const run = fn (n: U32) => read (identity (#First n))\n";
    const alias_next = "type First is data = #First U32\ntype Second is data = #Second U32\ntype Alias = Second\nconst identity = fn (value: Alias) -> Alias => value\nconst read = fn (#Second value) => value\nentry const run = fn (n: U32) => read (identity (#Second n))\n";
    try parity(alias_first, alias_next, 3);
    const private_alias = try std.mem.replaceOwned(u8, a, alias_first, "type Alias = First", "private type Alias = First");
    defer a.free(private_alias);
    try parity(alias_first, private_alias, 3);
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
    try compare(a, &before.bodies, inserted, expected.bytes, 3);
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
    try compare(a, &first.bodies, changed, expected.bytes, 3);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &first.bodies, changed, expected.bytes, @as(usize, 3) });
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
    try compare(a, &first.bodies, changed, expected.bytes, 3);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &first.bodies, changed, expected.bytes, @as(usize, 3) });
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &first.bodies, changed, expected.bytes, @as(usize, 1) });
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &first.bodies, changed, expected.bytes, @as(usize, 1) });
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
            return allocator.print("@[fn item => item] const supplier = fn (value: U32) => {{ field_{d}_{s}: value }}\nconst wide = fn value => supplier value\nconst preserved = fn (value: U32) => {s}\nentry const run = fn (value: U32) => preserved value\n", .{ generation, suffix, value });
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &first.bodies, relocated, expected.bytes, @as(usize, 1) });
    const retargeted = try std.mem.replaceOwned(u8, a, source, "(+) = combine", "(+) = other");
    defer a.free(retargeted);
    try parity(source, retargeted, 1);
}

test "body check cache distinguishes equal arity closed row binder and anonymous path constraints" {
    const T = @import("types.zig");
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 1) });
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, changed, expected.bytes, @as(usize, 1) });
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
    // Constructor introduction/pattern syntax remains ordinary; every other
    // unchanged admitted body relocates its applied annotations independently.
    try compare(a, &before.bodies, inserted, expected.bytes, 3);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compare, .{ &before.bodies, inserted, expected.bytes, @as(usize, 3) });
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
