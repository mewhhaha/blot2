const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const snapshot = @import("dependency_snapshot.zig");
const bundle = @import("dependency_bundle.zig");
const D = @import("frozen_dependency.zig");
const format = @import("dependency_format.zig");
const relink = @import("dependency_relink.zig");
const validation = @import("dependency_interface_validation.zig");
const consumer_api = @import("dependency_consumer.zig");
const slots_api = @import("dependency_symbol_slots.zig");

const producer_source =
    \\type Box a is data = $Box { value: a }
    \\const Box.get = func receiver => return receiver.value
    \\type Cell a is effect = { get: Unit -> a, set: a -> Unit }
    \\const identity = func value => return value
    \\const qualified: a -> a where { type_rep a } = func value => return value
    \\const reader = @effect.provider (Cell.get U32) (func () => return 41)
;
const consumer_source =
    \\entry const answer: Unit -> U32 = func () => return do reader:
    \\  use value <- Cell.get U32 ()
    \\  break @u32.add (qualified (identity ($Box { value: value }).get)) 1
;

const prelude_source = @import("fixtures").source("dependency-fixtures/prelude.blot");
const rank_identity_source =
    \\const id: forall [a] => a -> a = func value => return value
    \\const two: (forall [a] => a -> a) -> U32 -> (U32, F32) = func identity => return func value => return (identity value, identity (@u32.to_f32 value))
;

const key: format.Key = .{ .compiler = @as([32]u8, @splat(1)), .settings = @as([32]u8, @splat(2)), .source = @as([32]u8, @splat(3)), .dependencies = @as([32]u8, @splat(4)) };

const rank_array_source =
    \\effect Hidden: Unit -> Unit
    \\const hidden = func () => return Hidden ()
    \\const id: forall [a] => a -> a = func value => return value
    \\const array: (forall [a] => a -> a) -> Array U32 -> Array U32 = func identity => return func values => return identity values
    \\const floating: (forall [a] => a -> a) -> Array F32 -> Array F32 = func identity => return func values => return identity values
    \\const list: (forall [a] => a -> a) -> List U32 -> List U32 = func identity => return func values => return identity values
    \\const floating_list: (forall [a] => a -> a) -> List F32 -> List F32 = func identity => return func values => return identity values
;
fn relinkScenario(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var frozen = try format.decode(D.FrozenDependency, allocator, bytes, key);
    defer format.deinit(allocator, &frozen);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    _ = try pool.intern(allocator, "prior-symbol");
    const count = pool.entries.items.len;
    relink.relink(allocator, &frozen, &pool, &.{2}) catch |err| {
        try std.testing.expectEqual(count, pool.entries.items.len);
        try std.testing.expectEqualStrings("prior-symbol", pool.get(1));
        try std.testing.expectEqual(@as(u32, 1), frozen.modules[0].core.unit);
        try std.testing.expectEqual(@as(u32, 1), frozen.modules[0].interface.unit);
        return err;
    };
    try std.testing.expectEqual(@as(u32, 2), frozen.modules[0].core.unit);
    try std.testing.expectEqual(@as(u32, 2), frozen.modules[0].interface.unit);
}

const abstraction_producer =
    \\type Token is opaque = U32
    \\private const offset = 1
    \\const make: U32 -> Token = func value => return $Token (@u32.add value offset)
    \\const read: Token -> U32 = func ($Token value) => return value
;
const abstraction_consumer = "entry const answer = func (value: U32) => return read (make value)\n";

const associated_producer =
    \\type Identity a is contract = { type Item = a, type Pair = (Identity.Item a, a) }
    \\type Source s is contract = { type Item, const first: s -> (Source.Item s) }
    \\type Callable f is contract = { type Run = f }
    \\type Signature s is contract = { const first: Callable.Run (s -> U32) }
    \\type Alias b = Identity.Item b
    \\const helper: b -> b = func value => return value
    \\const keep: a -> (Identity.Item a) where { Identity a, type_eq (Identity.Item a) a } = func value => return value
;
const associated_rows_producer =
    \\type Scoped a is contract = { type Item = a, effect_rep ! {| e}, effect_rep ! {| f} }
;
fn appendAssociatedRecipe(a: std.mem.Allocator, extra: *[]u32, words: []const u32) !@import("../check/types.zig").List {
    const result: @import("../check/types.zig").List = .{ .start = @intCast(extra.len), .len = @intCast(words.len) };
    const length = std.math.add(usize, extra.len, words.len) catch return error.InvalidArtifact;
    const enlarged = try a.alloc(u32, length);
    @memcpy(enlarged[0..extra.len], extra.*);
    @memcpy(enlarged[extra.len..], words);
    a.free(extra.*);
    extra.* = enlarged;
    return result;
}
const implementation_producer =
    \\type Source s is contract = { type Item, const first: s -> (Source.Item s) }
    \\impl ArraySource a : Source (Array a) = { type Item = a, const first = func values => return @array.get values 0 }
;
const selected_implementation_producer =
    \\type Source s is contract = { type Item, const first: s -> (Source.Item s) }
    \\impl Scalar : Source U32 = { type Item = U32, const first = func value => return value }
    \\impl ArraySource a : Source (Array a) where { Source a } = { type Item = Source.Item a, const first = func values => return Source.first (@array.get values 0) }
    \\const answer: U32 = Source.first #[42]
;
const legacy_implementation_producer =
    \\type Token is data = $Token U32
    \\const Token.add = func (left: Token) => return func (right: Token) => return left
    \\type Source s is contract = { associated "add" s s s ! {}, type Item }
    \\impl TokenSource : Source Token = { type Item = U32 }
    \\const answer: (Source.Item Token) = 42
;
const inferred_legacy_implementation_producer =
    \\type Token is data = $Token U32
    \\const Token.add = func (left: Token) => return func (right: Token) => return left
    \\type Source s is contract = { associated "add" s s s, type Item }
    \\impl TokenSource : Source Token = { type Item = U32 }
    \\const answer: (Source.Item Token) = 42
;
const paired_capability_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const first = func (left: State a) => return func (right: State b) => return left.get ()
    \\const second = func (left: State a) => return func (right: State b) => return right.get ()
;
test "scoped public claim wire rejects unknown values after the admitted maximum" {
    const a = std.testing.allocator;
    const Contract = @import("../check/capability_flow.zig").Contract;
    const bytes = try format.encode(a, key, Contract.member_second_unit);
    defer a.free(bytes);
    try std.testing.expectEqual(Contract.member_second_unit, try format.decode(Contract, a, bytes, key));
    // The payload is the enum's one-byte LEB128 value.
    const payload = bytes.len - 1;
    bytes[payload] = @intCast(@backingInt(Contract.spawn_task) + 1);
    // Recompute integrity so rejection tests the enum domain, not its digest.
    @memcpy(bytes[payload - 32 .. payload], &format.digest(bytes[payload..]));
    try std.testing.expectError(error.InvalidArtifact, format.decode(Contract, a, bytes, key));
}

const parameter_footprint_producer =
    \\const pack = func first => return func second => return func third => return (third, (first, second), first)
    \\const keep = func unused => return func retained => return (retained, 42)
    \\const grouped = func first => return (func second => return (first, second))
;
const parameter_invocation_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const invoke = func (left: State a) => return func (right: State b) => return func (callback: Unit -> U32 ! {left.get, right.get | e}) => return callback ()
;
const record_footprint_producer =
    \\const pack = func first => return func second => return {selected: second, nested: {first}, repeated: first}
;
const member_closure_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const read = func unused => return func (state: State a) => return func () => return state.get ()
    \\const ordinary = func (record: {get: Unit -> U32}) => return func () => return record.get ()
;
const callable_container_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const keep = func unused => return func (state: State a) => return {callbacks: #[(func () => return state.get ())]}
    \\const alias = func unused => return func retained => return do:
    \\  let version = retained
    \\  break {nested: #[version]}
    \\type Wrapper a is opaque = a
    \\const wrap = func unused => return func retained => return $Wrapper retained
    \\const unwrap = func unused => return func wrapped => return case wrapped of
    \\  $Wrapper retained => retained
;
const precise_result_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const bundle = func (discarded: State a) => return func (retained: State a) => return {discarded: func () => return discarded.get (), retained: func () => return retained.get ()}
    \\const select = func value => return value.retained
    \\const operation = func (state: State a) => return state.get
    \\const take_second = func (values: (a, b)) => return @product.get values 1
    \\const take_array = func values => return @array.get values 1
    \\const take_at = func values => return func index => return @array.get values index
;
const nullary_shape_producer =
    \\type Maybe a is data = $Some a | $None
    \\const absent = func value => return case value of
    \\  $Some payload => payload
    \\  $None => $None
;

const text_shape_producer =
    \\const unicode = func unused => return "世界🙂"
    \\const empty = func unused => return ""
    \\const escaped = func unused => return "\n\t"
;
test "capability import keeps producer graph ordinal distinct from relocated external target" {
    const a = std.testing.allocator;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    const producer = "const project = func record => return record.left\nconst constant = func () => return 7\n";
    var tokens = try lexer.lex(a, producer);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, producer, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    var checked = try check.checkModule(a, &tree, &pool, &.{}, &.{}, 2);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const projected = checked.resolved[tree.roots.items[0]];
    const constant = checked.resolved[tree.roots.items[1]];
    try std.testing.expect(checked.capability_contracts.header(projected, 1) != null);
    const catalog: check.ImportedCatalog = .{ .producer = &checked, .kind = .catalog, .index = 0, .origin = 0 };
    var interface = catalog.interface(constant);
    const consumer = "const answer = value ()\n";
    var input_tokens = try lexer.lex(a, consumer);
    defer input_tokens.deinit(a);
    var input_tree = try parser.parse(a, consumer, input_tokens.tokens.items, &pool);
    defer input_tree.deinit(a);
    const name = pool.lookup("value").?;
    const imported: check.ImportedBinding = .{ .name = name, .target = .{ .unit = 3, .binding = projected }, .origin = 0, .interface = interface };
    var result = try check.checkModule(a, &input_tree, &pool, &.{imported}, &.{}, 4);
    defer result.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    // A forged owner ordinal does not decline to unknown or acquire authority.
    interface.producer_binding = projected;
    var forged = imported;
    forged.interface = interface;
    try std.testing.expectError(error.TypeLimit, check.checkModule(a, &input_tree, &pool, &.{forged}, &.{}, 4));
}

const deferred_block_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const fields = func (discarded: State a) => return func (retained: State a) => return do:
    \\  let dropped = func () => return do:
    \\    let alias = discarded
    \\    break alias.get ()
    \\  let kept = func () => return do:
    \\    let alias = retained
    \\    break case (alias, 1) of
    \\      (cell, number) => cell.get ()
    \\  break {discarded: dropped, retained: kept}
;
const scoped_constructor_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const provider = func unused => return func (state: State a) => return func implementation => return @effect.provider state.get implementation
    \\const state = func unused => return func (state: State a) => return func initial => return @effect.state state.get state.set initial
    \\const computation = func unused => return func action => return @computation action
;
const generative_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const choose = func flag => return func (left: State a) => return func (right: State a) => return if flag then left else right
    \\const forward = func flag => return func (left: State a) => return func (right: State a) => return choose flag left right
    \\const freeze = func value => return func () => return value
    \\const bundle = func flag => return func (left: State a) => return func (right: State a) => return func initial => return do:
    \\  let selected = forward flag left right
    \\  break {cell: selected, read: func () => return selected.get (), provider: @effect.state selected.get selected.set initial}
;
const returned_generative_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const staged = func (left: State a) => return func (middle: State a) => return do:
    \\  let first = if true then left else middle
    \\  break func () => return {first: first, second: if false then left else middle}
    \\const returned_forward = func (left: State a) => return func (right: State a) => return staged left right
;
const pattern_capture_producer =
    \\type Application is data = $Application {reset: Unit -> U32}
    \\const reset_scoped = func application => return func () => return do:
    \\  let $Application {reset} = application
    \\  break reset ()
;
const formal_generative_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const call = func callback => return callback ()
    \\const staged = func (left: State a) => return func (right: State a) => return func () => return if true then left else right
    \\const exercise = func (left: State a) => return func (right: State a) => return do:
    \\  let maker = staged left right
    \\  break call maker
    \\const ordinary = func () => return 42
;
const projected_generative_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const call = func callback => return callback ()
    \\const staged = func (left: State a) => return func (right: State a) => return func () => return if true then left else right
    \\const exercise = func (left: State a) => return func (right: State a) => return do:
    \\  let maker = staged left right
    \\  let container = {nested: {maker: maker, ordinary: func () => return 42}, unused: 99}
    \\  let alias = container
    \\  break call alias.nested.maker
    \\const product = func (left: State a) => return func (right: State a) => return do:
    \\  let maker = staged left right
    \\  let container = (maker, func () => return 42)
    \\  let alias = container
    \\  break call (@product.get alias 0)
;
const input_invocation_producer =
    \\type State a is effect = {get: Unit -> a, set: a -> Unit}
    \\const invoke = func cell => return func callback => return callback cell
    \\const read = func (cell: State a) => return invoke cell (func (actual: State a) => return actual.get ())
    \\const choose = func (left: State a) => return func (right: State a) => return invoke left (func (unused: State a) => return if true then left else right)
    \\const identity = func (cell: State a) => return invoke cell (func actual => return actual)
    \\const scoped = func () => return @effect.scope (func (cell: State U32) => return do:
    \\  use handled <- do (@effect.state cell.get cell.set 42):
    \\    break invoke cell (func (actual: State U32) => return if true then actual.get () else 0)
    \\  let (state, value) = handled
    \\  break value
    \\)
;
test "principal reference bounds preserve quantified row callback producers" {
    const a = std.testing.allocator;
    const source =
        \\const apply: forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e} = func pair => return (@product.get pair 0) (@product.get pair 1)
        \\const both: (forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e}) -> U32 -> (U32, F32) = func apply => return func value => return (apply ((func item => return item), value), apply ((func item => return item), @u32.to_f32 value))
        \\const foreign_apply: ((forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e}), (U32 -> U32 ! {Foreign})) -> U32 ! {Foreign} = func pair => return (@product.get pair 0) (@product.get pair 1, 42)
    ;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModule(a, &tree, &pool, &.{}, &.{}, 1);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var frozen = try snapshot.freezePrincipal(a, &tree, &checked);
    defer snapshot.deinit(a, &frozen);
    try validation.validate(&frozen, pool.entries.items.len + 1, 1);
}
