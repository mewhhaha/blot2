const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const scoped = @import("scoped_backend.zig");
const a = std.testing.allocator;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = false });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &names, &checked);
    errdefer module.deinit(allocator);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

const shared_source =
    \\type Row is data = $Row {target: Ref U32}
    \\const bump = func (rows: Array Row) -> (amount: U32): Unit => return do:
    \\  for row in rows:
    \\    @storage.write row.target (@u32.add (@storage.load row.target) amount)
    \\const target = func (rows: Array Row): Ref U32 => return (@storage.read rows 0).target
    \\entry const answer = func (input: U32): U32 => return do:
    \\  let left: Array U32 = #[input]
    \\  let right: Array U32 = #[10]
    \\  let first: Array Row = #[$Row {target: @storage.at left 0}]
    \\  let second: Array Row = #[$Row {target: @storage.at right 0}]
    \\  bump first 1
    \\  bump second 2
    \\  return @u32.add (@storage.load (target first)) (@storage.load (target second))
;
fn publish(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expectEqual(@as(u64, 2), result.counters.scoped_owner_graph_definitions);
    try std.testing.expect(result.counters.scoped_owner_graph_hits >= 2);
}

test "symbolic owner graphs share nested writes and returned input borrows" {
    var module = try lower(a, shared_source);
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}

test "symbolic owner graph keys separate nested aliases and retain joined origins" {
    var module = try lower(a,
        \\type Row is data = $Row {left: Ref U32, right: Ref U32}
        \\const bump = func (rows: Array Row): Unit => return do:
        \\  let row = @storage.read rows 0
        \\  @storage.write row.left (@u32.add (@storage.load row.left) 1)
        \\  @storage.write row.right (@u32.add (@storage.load row.right) 10)
        \\entry const answer = func (select: Bool): U32 => return do:
        \\  let a: Array U32 = #[0]
        \\  let b: Array U32 = #[0]
        \\  let c: Array U32 = #[0]
        \\  let d: Array U32 = #[0]
        \\  let e: Array U32 = #[0]
        \\  let aliased: Array Row = #[$Row {left: @storage.at a 0, right: @storage.at a 0}]
        \\  let first: Array Row = #[$Row {left: @storage.at b 0, right: @storage.at c 0}]
        \\  let second: Array Row = #[$Row {left: @storage.at d 0, right: @storage.at e 0}]
        \\  bump aliased
        \\  bump first
        \\  bump second
        \\  let joined = if select then first else second
        \\  bump joined
        \\  return @u32.add a[0] (@u32.add b[0] (@u32.add c[0] (@u32.add d[0] e[0])))
    );
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    // Aliased, disjoint and joined schemas each compile once; the two
    // disjoint callers share despite their different physical owner IDs.
    try std.testing.expectEqual(@as(u64, 3), result.counters.scoped_owner_graph_definitions);
    try std.testing.expect(result.counters.scoped_owner_graph_hits >= 1);
}

const put =
    \\type Row is data = $Row {values: &[U32]}
    \\const put = func (rows: ResizeArray Row) -> (values: &[U32]): Unit => return @storage.push rows ($Row {values})
    \\
;
const outer =
    \\entry const answer = func (): U32 => return do:
    \\  let seed: Array U32 = #[1]
    \\  let warm: Array U32 = #[2]
    \\  let warmed: ResizeArray Row = #[$Row {values: &seed[0..1]}]
    \\  let destination: ResizeArray Row = #[$Row {values: &seed[0..1]}]
    \\  put warmed (&warm[0..1])
    \\
;

test "symbolic owner graph replay rejects a shorter caller lifetime on a cache hit" {
    var module = try lower(a, put ++ outer ++
        \\  do:
        \\    let local: Array U32 = #[3]
        \\    put destination (&local[0..1])
        \\  return 0
    );
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic != null);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, result.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    try std.testing.expect(result.counters.scoped_owner_graph_hits >= 1);
}

test "symbolic owner graph replay preserves frozen growth and returned borrow escape checks" {
    var frozen = try lower(a, put ++ outer ++
        \\  let closed = @storage.freeze destination
        \\  put destination (&warm[0..1])
        \\  return @storage.length closed
    );
    defer frozen.deinit(a);
    var refused = try scoped.compile(a, &.{frozen}, 1);
    defer refused.deinit(a);
    try std.testing.expect(refused.diagnostic != null);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_borrow_conflict, refused.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), refused.bytes.len);
    var escaped = try lower(a,
        \\type Row is data = $Row {target: Ref U32}
        \\const target = func (rows: Array Row): Ref U32 => return (@storage.read rows 0).target
        \\const local = func (): Ref U32 => return do:
        \\  let values: Array U32 = #[7]
        \\  let rows: Array Row = #[$Row {target: @storage.at values 0}]
        \\  return target rows
        \\entry const answer = func (): U32 => return @storage.load (local ())
    );
    defer escaped.deinit(a);
    var rejected = try scoped.compile(a, &.{escaped}, 1);
    defer rejected.deinit(a);
    try std.testing.expect(rejected.diagnostic != null);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, rejected.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), rejected.bytes.len);
    var shrinking = try lower(a,
        \\type Row is data = $Row {target: Ref U32}
        \\const target = func (rows: Array Row): Ref U32 => return (@storage.read rows 0).target
        \\entry const answer = func (): U32 => return do:
        \\  let values: ResizeArray U32 = #[7]
        \\  let live = do:
        \\    let rows: Array Row = #[$Row {target: @storage.at values 0}]
        \\    break target rows
        \\  @storage.truncate values 0
        \\  return @storage.load live
    );
    defer shrinking.deinit(a);
    var shrink_refused = try scoped.compile(a, &.{shrinking}, 1);
    defer shrink_refused.deinit(a);
    try std.testing.expect(shrink_refused.diagnostic != null);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_borrow_conflict, shrink_refused.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), shrink_refused.bytes.len);
}

const span_writer =
    \\type Span is data = $Span {start: U32, count: U32}
    \\const append = func (output: ResizeArray U32) -> (input: &[U32]): Span => return do:
    \\  let start = @storage.length output
    \\  let count = @storage.length input
    \\  for value in input:
    \\    @storage.push output value
    \\  return $Span {start, count}
    \\entry const answer = func (input: U32): U32 => return do:
    \\  let source: Array U32 = #[input, 7]
    \\  let first: ResizeArray U32 = #[11]
    \\  let second: ResizeArray U32 = #[13]
    \\  let a = append first (&source[0..2])
    \\  let b = append second (&source[0..2])
    \\  let c = append first (&first[0..3])
    \\  return @u32.add a.start (@u32.add b.count (@u32.add c.start c.count))
;
fn publishPlainWriter(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    // Disjoint and self-copy alias graphs differ. Both disjoint destinations
    // share one body, while the self-copy's source count is captured on entry.
    try std.testing.expectEqual(@as(u64, 2), result.counters.scoped_owner_graph_definitions);
    try std.testing.expect(result.counters.scoped_owner_graph_hits >= 1);
}
test "symbolic owner graph writers return plain results and preserve self copy" {
    var module = try lower(a, span_writer);
    defer module.deinit(a);
    try publishPlainWriter(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishPlainWriter, .{@as([]const core.Module, &.{module})});
}

test "symbolic owner graph plain result writers retain caller lifetime checks" {
    var module = try lower(a,
        \\type Row is data = $Row {values: &[U32]}
        \\type Span is data = $Span {start: U32, count: U32}
        \\const put = func (rows: ResizeArray Row) -> (values: &[U32]): Span => return do:
        \\  let start = @storage.length rows
        \\  @storage.push rows ($Row {values})
        \\  return $Span {start, count: 1}
    ++ "\n" ++ outer ++
        \\  do:
        \\    let local: Array U32 = #[3]
        \\    let ignored = put destination (&local[0..1])
        \\  return 0
    );
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic != null);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, result.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    try std.testing.expect(result.counters.scoped_owner_graph_hits >= 1);
}

const projected_writer =
    \\type Point is data = $Point {x: U32}
    \\type Pose is data = $Pose {position: Point}
    \\const advance = func (point: Point): Point => return $Point {x: @u32.add point.x 1}
    \\const amend = func (rows: ResizeArray U32) -> (pose: Pose): Pose => return do:
    \\  pose.position := advance self
    \\  @storage.push rows pose.position.x
    \\  return pose
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let first: ResizeArray U32 = #[input]
    \\  let second: ResizeArray U32 = #[input]
    \\  let a = amend first ($Pose {position: $Point {x: input}})
    \\  let b = amend second ($Pose {position: $Point {x: @u32.add input 10}})
    \\  return #[a.position.x, first[1], b.position.x, second[1]]
;
fn publishProjectedWriter(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(@as(u64, 1), result.counters.scoped_owner_graph_definitions);
    try std.testing.expect(result.counters.scoped_owner_graph_hits >= 1);
}
test "symbolic owner graph field updates bind self to the selected nominal payload" {
    var module = try lower(a, projected_writer);
    defer module.deinit(a);
    try publishProjectedWriter(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishProjectedWriter, .{@as([]const core.Module, &.{module})});
}

const owned_word_borrowed_source =
    \\type Row is data = $Row {target: Ref U32, window: &[U32], cursor: Link U32}
    \\type Choice is data = $Direct (Ref U32) | $Window (&[U32]) | $Cursor (Link U32)
    \\const target = func (rows: Array Row): Ref U32 => return rows[0].target
    \\const window = func (rows: Array Row): &[U32] => return rows[0].window
    \\const cursor = func (rows: Array Row): Link U32 => return rows[0].cursor
    \\const choose = func (rows: Array Row) -> (kind: U32): Choice => return
    \\  if @u32.eq kind 0 then $Direct rows[0].target else
    \\  if @u32.eq kind 1 then $Window rows[0].window else $Cursor rows[0].cursor
    \\const touch_ref = func (value: Ref U32): U32 => return do:
    \\  @storage.write value (@storage.load value)
    \\  return @storage.load value
    \\const touch_link = func (value: Link U32): U32 => return do:
    \\  @storage.write value (@storage.load value)
    \\  return @storage.load value
    \\const observe = func (choice: Choice): U32 => return case choice of
    \\  $Direct value => touch_ref value
    \\  $Window value => value[0]
    \\  $Cursor value => touch_link value
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let a: Array U32 = #[input, @u32.add input 1]
    \\  let b: Array U32 = #[@u32.add input 10, @u32.add input 11]
    \\  let links_a: GrowArray U32 = #[@u32.add input 20]
    \\  let links_b: GrowArray U32 = #[@u32.add input 30]
    \\  let first: Array Row = #[$Row {target: @storage.at a 0, window: &a[0..2], cursor: @storage.link links_a 0}]
    \\  let second: Array Row = #[$Row {target: @storage.at b 0, window: &b[0..2], cursor: @storage.link links_b 0}]
    \\  let joined = if @u32.eq (@u32.rem input 2) 0 then first else second
    \\  let ref = target joined
    \\  let view = window joined
    \\  let link = cursor joined
    \\  let choice = choose joined (@u32.rem input 3)
    \\  @storage.write ref (@u32.add (@storage.load ref) 2)
    \\  @storage.write link (@u32.add (@storage.load link) 3)
    \\  let again = target second
    \\  return #[a[0], b[0], links_a[0], links_b[0], @storage.load ref, view[0], view[1], @storage.load link, observe choice, @storage.load again]
;

const owned_word_cycle_source =
    \\type Node is data = $End | $Next (Ref Node)
    \\const walk = func (start: Ref Node): U32 => return case @storage.load start of
    \\  $End => 0
    \\  $Next first => case @storage.load first of
    \\    $End => 0
    \\    $Next second => case @storage.load second of
    \\      $End => 0
    \\      $Next last => 3
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let first: Array Node = #[$End]
    \\  let second: Array Node = #[$End]
    \\  first[0] := $Next (@storage.at second 0)
    \\  second[0] := $Next (@storage.at first 0)
    \\  let a = walk (@storage.at first 0)
    \\  let b = walk (@storage.at second 0)
    \\  first[0] := $End
    \\  let c = walk (@storage.at second 0)
    \\  return #[a, b, c, input]
;

const owned_word_floating_source =
    \\const flip = func (rows: Array F32): F32 => return do:
    \\  rows[0] := @f32.neg self
    \\  return @storage.read rows 0
    \\entry const answer = func (input: U32): Array U32 => return do:
    \\  let (value, unused_a, unused_b, unused_c) = @simd.u32x4.from_bits (input,input,input,input)
    \\  let rows: Array F32 = #[value]
    \\  let first = flip rows
    \\  let second = flip rows
    \\  let (a,b,c,d) = @simd.f32x4.bits (first,second,rows[0],value)
    \\  return #[a,b,c,d]
;

fn publishOwnedWords(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_owned_word_calls > 0);
    try std.testing.expectEqual(@as(u64, 0), result.counters.scoped_owned_packed_calls);
    try std.testing.expect(result.counters.scoped_owner_graph_definitions > 0);
}
test "owned word ABI retains borrowed variants joined roots cycles and scalar bits through OOM" {
    for ([_][]const u8{ owned_word_borrowed_source, owned_word_cycle_source, owned_word_floating_source }) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        try publishOwnedWords(a, &.{module});
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishOwnedWords, .{@as([]const core.Module, &.{module})});
    }
}
