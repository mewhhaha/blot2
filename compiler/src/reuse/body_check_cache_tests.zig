const std = @import("std");
const cache = @import("body_check_cache.zig");
const check = @import("../check/check.zig");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const core = @import("../check/core.zig");
const A = std.mem.Allocator;
const a = std.testing.allocator;

const intrinsic_metadata_source =
    \\const seed = 2
    \\const second = func (values: Array U32) => return @cursor.value (@cursor.advance (@array.cursor values))
    \\const required = func (value: U32) => return @panic "retained trap"
    \\entry const run = func () => return second #[seed, 42]
;

const shorthand_source =
    \\const seed = 2
    \\const bundle = func (value: U32) => return func (values: Array U32) => return {value, values}
    \\const total = func (values: Array U32) => return do:
    \\  let count = 0
    \\  for let value in values:
    \\    count := @u32.add count value
    \\  break count
    \\entry const run = func () => return do:
    \\  let record = bundle seed #[40, 42]
    \\  break @u32.add record.value (total record.values)
;

const text =
    \\const seed = 2
    \\const sibling = func (value: U32) : U32 => return @u32.add value seed
    \\entry const run = func (argument: U32) : U32 => return sibling argument
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
    const memory = @import("../memory.zig");
    for ([_]usize{ 64, 128, 256 }) |count| {
        var source: std.ArrayList(u8) = .empty;
        defer source.deinit(a);
        try source.appendSlice(a, "const seed = 2\n");
        for (0..count) |index| {
            const declaration = try a.print("const sibling{d} = func (x: U32) : U32 => return @u32.add x seed\n", .{index});
            defer a.free(declaration);
            try source.appendSlice(a, declaration);
        }
        try source.appendSlice(a, "entry const run = func (x: U32) : U32 => return sibling0 x\n");
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

test "body check cache exhausted syntax proof preserves ordinary checking" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "const wide = (");
    for (0..4096) |index| {
        if (index != 0) try source.appendSlice(a, ", ");
        try source.appendSlice(a, "1");
    }
    try source.appendSlice(a, ")\nentry const run = func (x: U32) : U32 => return x\n");
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
    const producer_source = try allocator.print("{s}const {s} = func (x: U32) : U32 => return x\n", .{ prefix, original_name });
    defer allocator.free(producer_source);
    var producer_tokens = try lexer.lex(allocator, producer_source);
    defer producer_tokens.deinit(allocator);
    var producer_tree = try parser.parse(allocator, producer_source, producer_tokens.tokens.items, &pool);
    defer producer_tree.deinit(allocator);
    var producer = try check.checkModuleWithOptions(allocator, &producer_tree, &pool, &.{}, &.{}, unit, .{ .builtin_catalog = true });
    defer producer.deinit(allocator);
    const source = "entry const run = func (x: U32) : U32 => return exposed x\nconst untouched = 7\n";
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
        const declaration = try allocator.print("const sibling{d} = func (x: U32) : U32 => return @u32.add x {d}\n", .{ index, revision });
        defer allocator.free(declaration);
        try source.appendSlice(allocator, declaration);
    }
    try source.appendSlice(allocator, "entry const run = func (x: U32) : U32 => return sibling0 x\n");
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
            return allocator.print("@[func item => return item] const supplier = func (value: U32) => return {{ field_{d}_{s}: value }}\nconst wide = func value => return supplier value\nconst preserved = func (value: U32) => return {s}{s}\nentry const run = func (value: U32) => return preserved value\n", .{ generation, suffix, padding, value });
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

test "body check cache syntax owns parser allocations and preserves shared span synthetic ordinals" {
    const source =
        \\const gather = func values => return do:
        \\  let result = 0
        \\  for let value in values:
        \\    result := @u32.add result value
        \\  break result
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
    \\const make = func () => return @effect.provider Read (func () => return seed)
    \\entry const run = func () => return do (make ()):
    \\  break Read ()
;

const auxiliary_source =
    \\effect Read: Unit -> U32
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const seed = 2
    \\const read = func () => return do (@effect.provider Read (func () => return seed)):
    \\  break Read ()
    \\const state = func (initial: U32) => return @effect.run State.get State.set initial (func () => return do:
    \\  use State.set 40
    \\  break State.get ()
    \\)
    \\const describe = func () => return @effect.count (@effect.of read)
    \\const description = describe ()
    \\const checked = func computation => return do:
    \\  let count = 0
    \\  for request in @requests computation:
    \\    case request of
    \\      effect Read value =>
    \\        count := @u32.add count 1
    \\        yield 42
    \\      complete value =>
    \\        break @u32.add count value
    \\const request = func () => return checked (@computation (func () => return Read ()))
    \\entry const run = func () => return @u32.add (@product.get (state seed) 1) (@u32.add (read ()) (@u32.add (request ()) description))
;
const private_auxiliary_source =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const seed = 2
    \\const scoped = func () => return @effect.scope (func (state: State U32) => return do:
    \\  let capability = state
    \\  let read = capability.get
    \\  let write = capability.set
    \\  let local = func () => return read ()
    \\  let (successor, result) = do (@effect.state read write seed):
    \\    break local ()
    \\  break result
    \\)
    \\const borrow = func (owner: unique U32) => return @usage.borrow owner (func loan => return @usage.read loan)
    \\const resource = func () => return @resource.scope (func () => return #[seed, 40]) (func owner => return ()) (func loan => return @usage.length loan)
    \\entry const run = func () => return @u32.add (resource ()) (@u32.add (scoped ()) (borrow 40))
;
const rank_package_source =
    \\const seed = 2
    \\type Item = exists [a] => (a, a -> U32)
    \\const identity: forall [a] => a -> a = func value => return value
    \\const make: U32 -> Item = func value => return pack [U32] (value, func number => return @u32.add number 40) as Item
    \\const read: Item -> U32 = func item => return unpack item as [a] body in (@product.get body 1) (@product.get body 0)
    \\entry const run = func () => return read (make (identity seed))
;
const selected_package_source =
    \\const seed = 2
    \\type Render a is contract = { const show: a -> U32 }
    \\impl Number : Render U32 = { const show = func value => return value }
    \\impl Flag : Render Bool = { const show = func value => return if value then 7 else 9 }
    \\type Item = exists [a] where { Render a } => a
    \\const item: Item = pack [U32] seed as Item
    \\const flag: Item = pack [Bool] true as Item
    \\const read = func (item: Item) => return unpack item as [a] value in Render.show value
    \\const both = func (left: Item) => return func (right: Item) => return unpack left as [a] x in unpack right as [b] y in @u32.add (Render.show x) (Render.show y)
    \\entry const run = func () => return @u32.add (read item) (both item flag)
;
const constructor_usage_source =
    \\type Wrap a is data = $Wrap a
    \\const token = func () => return Wrap
    \\const identity = func (values: unique (Array U32)) => return values
    \\entry const run = func (values: unique (Array U32)) => return identity values
;

const forwarded_source =
    \\const seed = 2
    \\const U32.combine = func (left: U32) => return func (right: U32) => return @u32.add left right
    \\const F32.combine = func (left: F32) => return func (right: F32) => return @f32.add left right
    \\const combine = func left => return func right => return @type.call "combine" left right
    \\const alias = combine
    \\const partial = func value => return alias value
    \\const apply = func value => return partial value value
    \\entry const run = func () => return apply seed
;

const binary_argument_source =
    \\infixl 60 (++) = right
    \\infixl 60 (**) = left
    \\infixl 60 (%%) = both
    \\const seed = 2
    \\const right = func (value: U32) => return func (other: U32) => return @u32.add value other
    \\const left = func (value: U32) => return func (other: U32) => return @u32.add value other
    \\const both = func (value: U32) => return func (other: U32) => return @u32.add value other
    \\const apply = func (value: U32) => return @u32.add (value ++ seed) (@u32.add (value ** seed) (value %% seed))
    \\entry const run = func (value: U32) => return apply value
;

const residual_source =
    \\const seed = 2
    \\const Array.count = func values => return @array.length values
    \\const count = func (values: Array U32) => return values.count
    \\const increment = func record => return do:
    \\  let result = record
    \\  result.value := @u32.add self 1
    \\  break result
    \\const merge = func left => return func right => return @record.merge left right
    \\entry const run = func () => return do:
    \\  let first = increment {value: seed, values: #[40, 42]}
    \\  let second = merge first {extra: #[43]}
    \\  break @u32.add second.value (count second.values)
;

test "body check cache local qualification routes require exact bounded source clauses" {
    const source =
        \\const untouched = func value => return value
        \\const wrapper = func value => return do:
        \\  let local: a -> a where { type_rep a } = func amount => return amount
        \\  break local value
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
    const producer_source = try allocator.print("type Wrapper a is data = $Wrapper {{value: a, owning: Array U32}}\ntype Alias a = Wrapper {s}\ntype Twin a = Wrapper a\n", .{element});
    defer allocator.free(producer_source);
    var producer_tokens = try lexer.lex(allocator, producer_source);
    defer producer_tokens.deinit(allocator);
    var producer_tree = try parser.parse(allocator, producer_source, producer_tokens.tokens.items, &pool);
    defer producer_tree.deinit(allocator);
    var producer = try check.checkModuleWithOptions(allocator, &producer_tree, &pool, &.{}, &.{}, 2, .{ .builtin_catalog = true });
    defer producer.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), producer.diagnostics.len);
    const source = "entry const hold = func (value: Imported U32) => return value\n";
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

const implementation_mixed =
    \\type Source s is contract = { type Item, const first: s -> (Source.Item s) }
    \\impl ScalarSource : Source U32 = {
    \\  type Item = U32,
    \\  const first = func value => return @u32.add value 1,
    \\}
    \\const unrelated = func (value: U32) => return @u32.add value 7
    \\const selected = func (value: U32) => return Source.first value
    \\entry const run = func (value: U32) => return @u32.add (unrelated value) (selected value)
;

const implementation_annotations =
    \\type First is data = $First U32
    \\type Second is data = $Second U32
    \\type Alias = First
    \\type Source s is contract = { type Item, const first: s -> (Source.Item s) }
    \\impl ScalarSource : Source U32 = {
    \\  type Item = U32,
    \\  const first = func value => return @u32.add value 1,
    \\}
    \\const identity = func (value: Alias) : Alias => return value
    \\const read = func ($First value) => return value
    \\const selected = func (value: U32) => return Source.first value
    \\entry const run = func (value: U32) => return @u32.add (read (identity ($First value))) (selected value)
;

const loop_source =
    \\const seed = 2
    \\const sum = func (limit: U32) : U32 => return do:
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
    \\  break total
    \\entry const run = func (limit: U32) : U32 => return sum limit
;

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
    \\const helper = func (value: U32) : U32 => return do:
    \\  use initial <- @u32.add value seed
    \\  use initial
    \\  let result = initial
    \\  for index in 0..2:
    \\    use snapshot <- result
    \\    result := @u32.add self index
    \\    use snapshot
    \\  break result
    \\entry const run = func (value: U32) : U32 => return helper value
;

fn captureUsedValues(allocator: A) !void {
    var output = try prepare(allocator, used_values, null);
    defer output.deinit(allocator);
    try std.testing.expect(output.bodies.find("helper") != null);
}

const path_update_source =
    \\type Point is data = $Point { x: U32, y: U32 }
    \\type Bucket is data = $Bucket { points: Array Point }
    \\const seed = 2
    \\const update = func (index: U32) : U32 => return do:
    \\  let bucket = $Bucket { points: #[$Point { y: 1, x: 10 }, $Point { y: 2, x: 20 }] }
    \\  let before = bucket
    \\  bucket.points[index].x := @u32.add self seed
    \\  break @u32.add before.points[index].x bucket.points[index].x
    \\const replace = func values => return func index => return func value => return do:
    \\  values[index] := value
    \\  break values
    \\entry const run = func (index: U32) : U32 => return update index
;
fn capturePathUpdates(allocator: A) !void {
    var output = try prepare(allocator, path_update_source, null);
    defer output.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), output.bodies.find("update").?.rebindings.len);
    try std.testing.expectEqual(@as(usize, 1), output.bodies.find("replace").?.rebindings.len);
}
const callback_body_source =
    \\const seed = 2
    \\const force = func (value: Unit -> U32) : U32 => return value ()
    \\const twice = func (value: U32) => return do:
    \\  let delayed = func (input: Unit -> U32) => return @u32.add (input ()) (input ())
    \\  break delayed (func () => return @u32.add value seed)
    \\entry const run = func (value: U32) => return @u32.add (force (func () => return value)) (twice value)
;
const user_row_source = "effect Read: Unit -> U32\nprivate const invoke = func (host: Unit -> U32 ! {Read}) => return host ()\nprivate const identity = func (host: Unit -> U32 ! {Read}) => return host\nentry const answer = 42\n";
fn captureUserRows(allocator: A) !void {
    var output = try prepare(allocator, user_row_source, null);
    defer output.deinit(allocator);
    try std.testing.expect(output.bodies.find("invoke") != null);
    try std.testing.expect(output.bodies.find("identity") != null);
}
const static_operation_source = "effect Read: Unit -> U32\nconst seed = 2\nconst invoke = func () => return @u32.add (Read ()) seed\nentry const answer = 42\n";
fn captureStaticOperation(allocator: A) !void {
    var output = try prepare(allocator, static_operation_source, null);
    defer output.deinit(allocator);
    const body = output.bodies.find("invoke").?;
    const owner = body.auxiliary orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), owner.tables.operation_uses.len);
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
    var source: []const u8 = "const keep = func (callback: Unit -> U32 ! {Alias.ask U32}) => return callback\nentry const answer = 42\n";
    if (static) source = "const keep = func () => return Alias.ask ()\nentry const answer = 42\n";
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
        "effect Read: Unit -> U32\nconst invoke = func (callback: Unit -> U32 ! {Unknown}) => return callback ()\n",
        "effect Read: Unit -> U32\nconst invoke = func (callback: Unit -> U32 ! {Read U32}) => return callback ()\n",
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
    \\type Bundle is data = $Bundle {earlier: List U32, current: List U32, alias: List U32, other: List U32}
    \\const grown = do:
    \\  let values: List U32 = []
    \\  let earlier: List U32 = []
    \\  let other: List U32 = []
    \\  for index in 0..32:
    \\    values := if @u32.lt index 16 then @list.append values index else @list.prepend values index
    \\    other := @list.append other (@u32.add index 100)
    \\    earlier := if @u32.eq index 30 then values else earlier
    \\  break $Bundle {earlier: earlier, current: values, alias: values, other: other}
    \\entry const run = func () => return @array.from_list grown.current
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
    \\const witness: (values: Array U32) -> (index: U32) -> @proof.Index values index = func values => return func index => return @proof.index values index
    \\const at: (values: Array U32) -> (index: U32) -> (@proof.Index values index) -> U32 = func values => return func index => return func proof => return @array.get values index
    \\const checked = func (index: U32) => return do:
    \\  let values = #[seed, 13]
    \\  let alias = values
    \\  let valid = witness alias index
    \\  break at values index valid
    \\const late = func (index: U32) => return do:
    \\  let valid = @proof.index globals cursor
    \\  break at globals cursor valid
    \\entry const run = func () => return @u32.add (checked 0) (late 1)
;
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
    \\const decorate = func (value: U32) => return func () => return @u32.add value seed
    \\const outer = func (callback: Unit -> U32) => return func () => return @u32.add (callback ()) 1
    \\@[outer] @[decorate] const tagged: Unit -> U32 = 40
    \\@[func (value: U32) => return @u32.add value 1] let started: U32 = 41
    \\entry const run = func () => return @u32.add (tagged ()) started
;
const selected_scope_owner_source =
    \\const seed = 2
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const selected = func (flag: Bool) => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
    \\  let chosen = if flag then left else right
    \\  let alias = chosen
    \\  let (state, result) = do (@effect.state chosen.get chosen.set seed):
    \\    use alias.set 42
    \\    break alias.get ()
    \\  break result
    \\))
    \\entry const run = func () => return selected true
;
const iterator_owner_source =
    \\const seed = 2
    \\type Maybe a is data = $Some a | $Nothing
    \\type Counter is data = $Counter U32
    \\const Counter.iter = func (cursor: Counter) => return cursor
    \\const Counter.next = func ($Counter value) => return if @u32.lt value 4 then $Some (value, $Counter (@u32.add value 1)) else $Nothing
    \\const total = func (first: U32) => return do:
    \\  let result = seed
    \\  for value in $Counter first:
    \\    result := @u32.add self value
    \\  break result
    \\entry const run = func () => return total 1
;
const resolver_owner_source =
    \\const seed = 2
    \\type Iteration [state,result] is data = $Continue state | $Done result
    \\type Maybe value is data = $Some value | $Nothing
    \\const monad = func constructor => return @do.monad constructor
    \\const Maybe.pure = func value => return $Some value
    \\const Maybe.bind = func candidate => return func next => return case candidate of
    \\  $Some value => next value
    \\  $Nothing => $Nothing
    \\const Maybe.iterate = func initial => return func step => return do:
    \\  let state = initial
    \\  for ever:
    \\    use candidate <- step state
    \\    if let $Some ($Done result) = candidate:
    \\      break $Some result
    \\    let $Some ($Continue next) = candidate else:
    \\      break $Nothing
    \\    state := next
    \\const sequence = func forwarded => return do (monad Maybe):
    \\  let total = seed
    \\  for outer in 0..2:
    \\    for inner in 0..2:
    \\      use value <- $Some 1
    \\      total := @u32.add self value
    \\      if forwarded:
    \\        break $ $Some (@u32.add total 21)
    \\      if @u32.eq inner 1:
    \\        break @u32.add total 20
    \\      break
    \\  break total
    \\entry const answer = func () => return case sequence true of
    \\  $Some value => value
    \\  $Nothing => 0
;

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
    \\const selected = func (flag: Bool) => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
    \\  let choose = func () => return if flag then left else right
    \\  let chosen = choose ()
    \\  let alias = chosen
    \\  let (state, result) = do (@effect.state chosen.get chosen.set seed):
    \\    use alias.set 42
    \\    break alias.get ()
    \\  break result
    \\))
    \\entry const run = func () => return selected true
;
const task_view_owner_source =
    \\const seed = 2
    \\const partition = func (owner: unique (Array U32)) => return do:
    \\  let (owner, result) = @task.split owner ((0, 2), (2, 4)) (func views => return do:
    \\    let (left, right) = views
    \\    break @task.scope (func group => return do:
    \\      let first = @task.spawn group (func () => return @u32.add seed (@task.read left 0))
    \\      let second = @task.spawn group (func () => return @task.read right 0)
    \\      break @u32.add (@task.join first) (@task.join second)))
    \\  break result
    \\entry const view = func (owner: unique (Array U32)) => return partition owner
;
test "body check cache keeps recursive components ordinary" {
    const recursive = "const first = func (n: U32) : U32 => return if @u32.eq n 0 then 4 else second (@u32.sub n 1)\nconst second = func (n: U32) : U32 => return if @u32.eq n 0 then 5 else first (@u32.sub n 1)\nentry const run = func (n: U32) : U32 => return first n\nconst unrelated = 7\n";
    var before = try prepare(a, recursive, null);
    defer before.deinit(a);
    var retained = try prepare(a, recursive, &before.bodies);
    defer retained.deinit(a);
    try std.testing.expect(retained.elaborations >= 2);
}
