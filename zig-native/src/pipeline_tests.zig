const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const scalar_source =
    \\const identity = fn value => value
    \\const add = fn left => fn right => @u32.add left right
    \\entry const maximum: U32 = 0xFFFF_FFFF
    \\entry const answer = fn () -> U32 => add (identity 20) (identity 22)
    \\entry const floating = fn (value: F32) -> F32 => identity value
    \\entry const capped = fn (value: U32) -> U32 => do:
    \\  if @u32.lt value 42:
    \\    return value
    \\  return 42
    \\entry const nested = fn () -> U32 => do:
    \\  let inner = do:
    \\    return 20
    \\  return @u32.add inner 22
;
fn lowerSource(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), lexed.diagnostics.items.len);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &pool, &checked);
    errdefer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    result.unit = 1;
    return result;
}
fn compileSource(allocator: std.mem.Allocator, source: []const u8) !backend.Result {
    var lowered = try lowerSource(allocator, source);
    defer lowered.deinit(allocator);
    return backend.compile(allocator, &.{lowered}, 1);
}
test "native source pipeline retains generic bodies and deterministic scalar output" {
    const allocator = std.testing.allocator;
    var first = try compileSource(allocator, scalar_source);
    defer first.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), first.diagnostic);
    try std.testing.expectEqual(@as(usize, 4), first.code_instances);
    var second = try compileSource(allocator, scalar_source);
    defer second.deinit(allocator);
    try std.testing.expectEqualSlices(u8, first.bytes, second.bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0, 97, 115, 109, 1, 0, 0, 0 }, first.bytes[0..8]);
}
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compiled = try compileSource(allocator, scalar_source);
    defer compiled.deinit(allocator);
    try std.testing.expect(compiled.diagnostic == null);
}
test "all pipeline allocation failures release syntax types and code buffers" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

test "a valid source without an entry cannot produce a Wasm program" {
    var result = try compileSource(std.testing.allocator, "const answer = 42\n");
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(backend.Code.no_entry, result.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
}

const provider_source =
    \\effect Read: Unit -> F32
    \\type State a is effect = { get: Unit -> a, set: a -> Unit }
    \\const reader = @effect.provider Read (fn () => 1.75)
    \\const state = @effect.state (State.get F32) (State.set F32) 1.75
    \\entry const folded = do reader:
    \\  return Read ()
    \\entry const callback = fn () => do reader:
    \\  return Read ()
    \\entry const answer = fn (value: F32) => do:
    \\  let (next, old) = do state:
    \\    use old <- State.get F32 ()
    \\    use State.set F32 (@f32.add old value)
    \\    return old
    \\  return @f32.add next old
;

fn providerPipelineScenario(allocator: std.mem.Allocator) !void {
    var result = try compileSource(allocator, provider_source);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.callable_wrappers >= 3);
}
test "provider emission releases callback code rows frames and State data on every allocation failure" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, providerPipelineScenario, .{});
}

fn foreignPipelineScenario(allocator: std.mem.Allocator) !void {
    const source =
        \\const invoke = fn callback => callback 21
        \\entry const scalar = fn (host: U32 -> U32 ! {Foreign}) => invoke host
        \\entry const arrays = fn (host: Array F32 -> Array F32 ! {Foreign}) => host #[1.25]
    ;
    var result = try compileSource(allocator, source);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
}
test "source callback emission releases imports retained references descriptors and signatures on every allocation failure" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, foreignPipelineScenario, .{});
}

const record_witness_source =
    \\const apple = 0.0
    \\type Pair is data = #Pair { zebra: U32, apple: F32 }
    \\type State a is effect = { get: Unit -> a, set: a -> Unit }
    \\const get = fn (witness: p -> a) -> a => State.get ()
    \\const state = @effect.state (State.get Pair) (State.set Pair) (#Pair { zebra: 42, apple: 1.5 })
    \\entry const answer = fn () => do:
    \\  let (_, result) = do state:
    \\    use value <- get #Pair
    \\    return value.zebra
    \\  return result
;
fn recordWitnessScenario(allocator: std.mem.Allocator) !void {
    var result = try compileSource(allocator, record_witness_source);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.callable_wrappers >= 2);
}
test "closed record evidence retains caller field storage during generic effect specialization" {
    try recordWitnessScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, recordWitnessScenario, .{});
}

const retained_checkpoint_sources = [_][]const u8{
    \\type State a is effect = { get: Unit -> a, set: a -> Unit }
    \\type Builder [world,scope,checkpoint] is data = #Builder { initial: world, scope: world -> scope, checkpoint: checkpoint }
    \\const empty = fn () => do:
    \\  let scope = fn world => fn action => do:
    \\    use result <- action ()
    \\    return (world,result)
    \\  return #Builder { initial: (), scope, checkpoint: fn () => () }
    \\const insert = fn initial => fn builder => do:
    \\  let #Builder { initial: previous_initial, scope: previous_scope, checkpoint } = builder
    \\  let scope = fn world => fn action => do:
    \\    let (current,previous) = world
    \\    use outcome <- @effect.run State.get State.set current (fn () => previous_scope previous action)
    \\    let (next,(previous_next,result)) = outcome
    \\    return ((next,previous_next),result)
    \\  return #Builder { initial: (initial,previous_initial), scope, checkpoint }
    \\const snapshot = fn initial => fn builder => do:
    \\  let #Builder { checkpoint: previous_checkpoint } = builder
    \\  let #Builder { initial: previous_initial, scope: previous_scope } = insert initial builder
    \\  let checkpoint = fn () => do:
    \\    use previous_checkpoint ()
    \\    use current <- State.get ()
    \\    use State.set (@u32.add current 1)
    \\    return ()
    \\  return #Builder { initial: previous_initial, scope: previous_scope, checkpoint }
    \\const built = snapshot 41 (empty ())
    \\entry const answer = fn () => do:
    \\  let #Builder { initial,scope,checkpoint } = built
    \\  let (world,_) = scope initial checkpoint
    \\  let (current,_) = world
    \\  return current
    ,
    \\effect Read: Unit -> U32
    \\effect Touch: U32 -> Unit
    \\const previous: Unit -> Unit = fn () => ()
    \\const extend = fn previous => fn () => do:
    \\  use previous ()
    \\  use value <- Read ()
    \\  use Touch value
    \\  return ()
    \\const checkpoint = extend previous
    \\const reader = @effect.provider Read (fn () => 42)
    \\const touch = @effect.provider Touch (fn value => ())
    \\const run = fn () => do touch:
    \\  use checkpoint ()
    \\  return 42
    \\entry const answer = fn () => do reader:
    \\  return run ()
    ,
};
fn retainedCallableScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}
test "retained checkpoint implementations emit their own rows and release every failed allocation" {
    const allocator = std.testing.allocator;
    for (retained_checkpoint_sources) |source| {
        var module = try lowerSource(allocator, source);
        defer module.deinit(allocator);
        try retainedCallableScenario(allocator, &module);
        try @import("allocation_failures.zig").checkAllAllocationFailures(allocator, retainedCallableScenario, .{&module});
    }
}

const curried_dispatch_source =
    \\effect Read: Unit -> F32
    \\type Box is data = #Box F32
    \\type Deferred is data = #Deferred F32
    \\type Scale is data = #Scale F32
    \\const Box.mix = fn left => fn right => fn weight => do:
    \\  let #Box base = left
    \\  return @f32.add base (@f32.mul right weight)
    \\const Deferred.mix = fn left => do:
    \\  let #Deferred base = left
    \\  use offset <- Read ()
    \\  return fn right => fn weight => @f32.add (@f32.add base offset) (@f32.mul right weight)
    \\const Scale.mix = fn left => fn right => fn weight => do:
    \\  let #Scale scale = right
    \\  return @f32.add left (@f32.mul scale weight)
    \\const mix = fn left => fn right => @type.call "mix" left right
    \\const reader = @effect.provider Read (fn () => 2.0)
    \\entry const nominal = fn (value: F32) => mix (#Box value) 2.0 1.0
    \\entry const partial = fn (value: F32) => do:
    \\  let blend = mix (#Box value) 4.0
    \\  return blend 0.5
    \\entry const deferred = fn (value: F32) => do reader:
    \\  return mix (#Deferred value) 4.0 0.5
    \\entry const right = fn (value: F32) => mix value (#Scale 2.0) 1.0
    \\type Live is data = #Live F32
    \\const Live.mix = fn left => fn right => fn () => do:
    \\  let #Live base = left
    \\  use value <- Read ()
    \\  return @f32.add base (@f32.add right value)
    \\const earlier = @effect.provider Read (fn () => 100.0)
    \\entry const live = fn (value: F32) => do:
    \\  let callback = do earlier:
    \\    return mix (#Live value) 0.0
    \\  return do reader:
    \\    return callback ()
;
test "curried binary dispatch retains selected invocation rows and releases every failed allocation" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator, curried_dispatch_source);
    defer module.deinit(allocator);
    try retainedCallableScenario(allocator, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(allocator, retainedCallableScenario, .{&module});
}

test "runtime scalar exports release startup functions and global names on every failed allocation" {
    const allocator = std.testing.allocator;
    var module = try lowerSource(allocator,
        \\entry let integer: U32 = @u32.add base 2
        \\let base: U32 = 40
        \\entry let floating: F32 = @f32.add 1.25 2.5
        \\entry let enabled: Bool = #True
        \\entry let empty: Unit = ()
        \\entry const read = fn () => @u32.add integer base
    );
    defer module.deinit(allocator);
    try retainedCallableScenario(allocator, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(allocator, retainedCallableScenario, .{&module});
}
