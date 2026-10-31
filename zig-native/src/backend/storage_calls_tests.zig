const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const scoped = @import("scoped_backend.zig");
const a = std.testing.allocator;
fn publishSmallModule(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compileWithWorkLimits(allocator, modules, 1, .{}, .{ .expressions = 512 });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
test "loaded nominal fields keep semantic witnesses across cached generic contexts" {
    var module = try lowerWithCatalog(a, "type Maybe a is data = $Some a | $Nothing\n" ++
        "const ResizeArray.length = func (values: ResizeArray a): U32 => return @storage.length values\n" ++
        "const View.at = func (values: View a) -> (index: U32) => return @storage.read values index\n" ++
        "type Vector is data = $Vector {x: F32}\ntype Pose is data = $Pose {position: Vector}\n" ++
        "const vector = func (x: F32) => return $Vector {x}\n" ++
        "const Vector.add = func (left: Vector) -> (right: Vector) => return vector (@f32.add left.x right.x)\n" ++
        "const rows = func (pool: ResizeArray (Maybe a)): &[Maybe a] => return &pool[0..pool.length]\n" ++
        "const shifted = func access -> tag => return do:\n  let poses = rows access.pool\n  let $Some pose = poses.at 0 else:\n    return (tag, vector 0.0)\n  return (tag, @type.call \"add\" pose.position (vector 1.0))\n" ++
        "entry const answer = func (input: F32) => return do:\n" ++
        "  let pool: ResizeArray (Maybe Pose) = #[$Some $Pose {position: vector input}]\n" ++
        "  let (integer, first) = shifted {pool} 7\n" ++
        "  pool[0] := $Some $Pose {position: vector (@f32.add input 10.0)}\n" ++
        "  let (floating, second) = shifted {pool} input\n" ++
        "  return #[@u32.to_f32 integer, first.x, floating, second.x]\n", true);
    defer module.deinit(a);
    try publishSmallModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSmallModule, .{@as([]const core.Module, &.{module})});
}
test "inline generic result witnesses preserve distinct same layout nominal instances" {
    var module = try lower(a, "type Maybe a is data = $Some a | $Nothing\n" ++
        "type Actor is data = $Actor U32\ntype Pose is data = $Pose U32\n" ++
        "const pick = func fallback -> maybe => return case maybe of\n  $Some value => value\n  $Nothing => fallback\n" ++
        "const consume = func ($Actor actor) -> ($Pose pose) => return @u32.add (@u32.mul actor 100) pose\n" ++
        "entry const answer = func (input: U32) => return do:\n  let rows: ResizeArray U32 = #[input]\n" ++
        "  let actors: Maybe Actor = if @u32.eq (@u32.bit_and input 1) 0 then $Nothing else $Some ($Actor rows[0])\n" ++
        "  let poses: Maybe Pose = if @u32.eq (@u32.bit_and input 2) 0 then $Nothing else $Some ($Pose rows[0])\n" ++
        "  let actor = pick ($Actor 10) actors\n  let pose = pick ($Pose 20) poses\n  let retained = pick ($Actor 30) actors\n" ++
        "  return @u32.add (consume actor pose) (consume retained pose)\n");
    defer module.deinit(a);
    try publishSmallModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSmallModule, .{@as([]const core.Module, &.{module})});
}
test "writer outlining leaves implicit global pool reads with their owning generator" {
    var module = try lower(a, "const pool: Array U32 = #[5]\n" ++
        "const implicit = func (destination: ResizeArray U32) => return @storage.push destination pool[0]\n" ++
        "const explicit = func (destination: ResizeArray U32) -> (source: Array U32) => return @storage.push destination source[0]\n" ++
        "entry const answer = func (input: U32) => return do:\n  let source = pool\n  source[0] := @u32.add input 7\n  let rows: ResizeArray U32 = #[input]\n  implicit rows\n  explicit rows source\n  return rows[1]\n");
    defer module.deinit(a);
    try publishSmallModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSmallModule, .{@as([]const core.Module, &.{module})});
}
test "plain getters preserve exact dispatch through selected inline helpers" {
    var parts: [103][]const u8 = undefined;
    parts[0] = "const F32.abs = func (value: F32) => return @f32.abs value\n" ++
        "const abs = func value => return value.abs\n" ++
        "type Number is data = $Number F32\n" ++
        "const Number.abs = func (number: Number) => return do:\n  let $Number value = number\n  return @f32.add (@f32.abs value) 10.0\n" ++
        "const kernel = func (input: F32) => return do:\n  let number = $Number input\n  let total = @f32.add (abs input) number.abs\n";
    @memset(parts[1..81], "  total := @f32.add total 1.0\n");
    parts[81] = "  return total\nentry const answer = func (input: F32) => return do:\n  let rows: ResizeArray F32 = #[input]\n  let total: F32 = 0.0\n";
    @memset(parts[82..102], "  total := @f32.add total (kernel rows[0])\n");
    parts[102] = "  return total\n";
    const source = try std.mem.concat(a, u8, &parts);
    defer a.free(source);
    var module = try lowerWithCatalog(a, source, true);
    defer module.deinit(a);
    try publishSmallModule(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSmallModule, .{@as([]const core.Module, &.{module})});
}
fn publishScratchWriter(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compileWithWorkLimits(allocator, modules, 1, .{}, .{ .expressions = 512 });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}

test "Unit writer helpers admit plain local scratch arrays with checked cleanup" {
    const helper = "const keeper: Array U32 = #[123]\n" ++
        "const Array.length = func (values: Array a): U32 => return @array.length values\n" ++
        "const Array.at = func (values: Array a) -> (index: U32) => return @array.get values index\n" ++
        "const ResizeArray.push = func (values: ResizeArray a) -> (value: a) => return @storage.push values value\n" ++
        "const some = func (values: Array U32) -> (predicate: U32 -> Bool) => return do:\n  for index in 0 .. values.length:\n    if predicate (values.at index):\n      return true\n  return false\n" ++
        "const bump = func (first: U32) -> (second: U32) -> (third: U32) => return @u32.add (@u32.add first second) third\n" ++
        "const encode = func (input: U32): Array U32 => return #[input, @u32.add input 1]\n" ++
        "const append = func (values: Array U32) -> (destination: ResizeArray U32) => return do:\n  let read = values.at\n  for index in 0 .. values.length:\n    destination.push (read index)\n" ++
        "const write = func (destination: ResizeArray U32) -> (input: U32) => return do:\n  let encoded = encode input\n  let local: GrowArray U32 = #[]\n  @storage.push local encoded[0]\n  @storage.push local encoded[1]\n  let sum: U32 = 0\n";
    var parts: [102][]const u8 = undefined;
    parts[0] = helper;
    @memset(parts[1..81], "  sum := @u32.add sum 1\n");
    parts[81] = "  let found = some encoded (func outer => return some encoded (func inner => return true))\n  if found:\n    destination.push input\n  let first = bump input\n  let partial = first sum\n  destination.push (partial 0)\n  append (encode sum) destination\n  @storage.push destination local[0]\nentry const answer = func (input: U32) => return do:\n  let rows: ResizeArray U32 = #[input]\n";
    @memset(parts[82..101], "  write rows input\n");
    parts[101] = "  do:\n    let busy: GrowArray U32 = #[0]\n    write rows input\n    @storage.push busy input\n  write rows input\n  return @u32.add rows[0] (@u32.sub keeper[0] 123)\n";
    const source = try std.mem.concat(a, u8, &parts);
    defer a.free(source);
    var module = try lowerWithCatalog(a, source, true);
    defer module.deinit(a);
    try publishScratchWriter(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishScratchWriter, .{@as([]const core.Module, &.{module})});
    var invalid = try lower(a, "const borrow = func () => return &(#[42])[0]\n" ++
        "const write = func (destination: ResizeArray U32) => return do:\n  let scratch: Array U32 = #[1]\n  @storage.push destination (@storage.load (borrow ()))\n" ++
        "entry const answer = func () => return do:\n  let rows: ResizeArray U32 = #[]\n  write rows\n  return rows[0]\n");
    defer invalid.deinit(a);
    var rejected = try scoped.compile(a, &.{invalid}, 1);
    defer rejected.deinit(a);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, rejected.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), rejected.bytes.len);
}

fn publishSelectedReader(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compileWithWorkLimits(allocator, modules, 1, .{}, .{ .expressions = 512 });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
fn publishLargeKeyFallback(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_outline_key_declines >= 2);
}

test "optional oversized reader and writer keys fall back without hiding invalid borrows" {
    var name: [7000]u8 = undefined;
    @memset(&name, 'x');
    const source = try std.fmt.allocPrint(a, "type State = {{{s}: ResizeArray U32}}\n" ++
        "const write = func (state: State) -> (amount: U32) => return do:\n  state.{s}[0] := @u32.add state.{s}[0] amount\n" ++
        "const read = func (state: State) => return state.{s}[0]\n" ++
        "entry const answer = func (input: U32) => return do:\n  let rows: ResizeArray U32 = #[10]\n  let state = {{{s}: rows}}\n  write state input\n  write state 1\n  return read state\n", .{ &name, &name, &name, &name, &name });
    defer a.free(source);
    var module = try lower(a, source);
    defer module.deinit(a);
    try publishLargeKeyFallback(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishLargeKeyFallback, .{@as([]const core.Module, &.{module})});
    const invalid_source = try std.fmt.allocPrint(a, "type State = {{{s}: ResizeArray U32}}\n" ++
        "const borrow = func (state: State) => return do:\n  let local: GrowArray U32 = #[1]\n  return &local[0]\n" ++
        "entry const answer = func () => return do:\n  let rows: ResizeArray U32 = #[0]\n  let escaped = borrow {{{s}: rows}}\n  return @storage.load escaped\n", .{ &name, &name });
    defer a.free(invalid_source);
    var invalid = try lower(a, invalid_source);
    defer invalid.deinit(a);
    var rejected = try scoped.compile(a, &.{invalid}, 1);
    defer rejected.deinit(a);
    try std.testing.expect(rejected.diagnostic != null);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, rejected.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), rejected.bytes.len);
}

test "selected parameterized readers outline exact descriptor payloads across owners" {
    var parts: [122][]const u8 = undefined;
    parts[0] = "type Research rows is data = $Research {rows: rows, count: U32}\nconst read = func (value: Research rows) => return do:\n  let number = value.count\n";
    @memset(parts[1..101], "  number := @u32.add number 1\n");
    parts[101] = "  return number\nentry const answer = func (input: U32) => return do:\n  let owner: ResizeArray U32 = #[input]\n  let research = $Research {rows: &owner[0..1], count: input}\n  let total: U32 = 0\n";
    @memset(parts[102..121], "  total := @u32.add total (read research)\n");
    parts[121] = "  return total\n";
    const source = try std.mem.concat(a, u8, &parts);
    defer a.free(source);
    var module = try lower(a, source);
    defer module.deinit(a);
    var result = try scoped.compileWithWorkLimits(a, &.{module}, 1, .{}, .{ .expressions = 512 });
    defer result.deinit(a);
    if (result.diagnostic) |diagnostic| std.debug.print("generic reader: {s}\n", .{diagnostic.message()});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.counters.max_scoped_emission_body_steps <= 512);
    try std.testing.expect(result.counters.scoped_emission_expressions > result.counters.max_scoped_emission_body_steps);
    try std.testing.expect(result.bytes.len > 8);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishSelectedReader, .{@as([]const core.Module, &.{module})});
    const callable_source = try std.mem.replaceOwned(u8, a, source, "rows: &owner[0..1]", "rows: func () => return input");
    defer a.free(callable_source);
    var callable_module = try lower(a, callable_source);
    defer callable_module.deinit(a);
    var declined = try scoped.compileWithWorkLimits(a, &.{callable_module}, 1, .{}, .{ .expressions = 512 });
    defer declined.deinit(a);
    try std.testing.expect(declined.diagnostic != null);
    try std.testing.expectEqualStrings("Storage source expansion exceeded its expression budget", declined.diagnostic.?.message());
    try std.testing.expectEqual(@as(usize, 0), declined.bytes.len);
}
fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    return lowerWithCatalog(allocator, source, false);
}
fn lowerWithCatalog(allocator: std.mem.Allocator, source: []const u8, builtin_catalog: bool) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = builtin_catalog });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &names, &checked);
    errdefer module.deinit(allocator);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

test "owned calls reuse scalar and destination specializations" {
    var unused = try lower(a, "const unused = func (rows: GrowArray U32) => return @storage.length rows\nentry const answer = func () => return 42\n");
    defer unused.deinit(a);
    try std.testing.expect(!try scoped.required(a, &.{unused}, 1));
    var reached = try lower(a, "const length = func (rows: GrowArray U32) => return @storage.length rows\nentry const answer = func () => return length #[42]\n");
    defer reached.deinit(a);
    try std.testing.expect(try scoped.required(a, &.{reached}, 1));
    const simple_once = "const row = func (value: U32) => return #[value, 7]\nconst number = func (value: U32) => return @u32.add value 1\nentry const answer = func () => return do:\n  let values = row 40\n  break number values[0]\n";
    const simple_twice = "const row = func (value: U32) => return #[value, 7]\nconst number = func (value: U32) => return @u32.add value 1\nentry const answer = func () => return do:\n  let first = row 40\n  let second = row 41\n  let a = number first[0]\n  break @u32.add a (number second[0])\n";
    var left = try lower(a, simple_once);
    defer left.deinit(a);
    var right = try lower(a, simple_twice);
    defer right.deinit(a);
    var first = try scoped.compile(a, &.{left}, 1);
    defer first.deinit(a);
    var second = try scoped.compile(a, &.{right}, 1);
    defer second.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try std.testing.expect(second.diagnostic == null);
    try std.testing.expect(first.bytes.len > 8);
    try std.testing.expectEqual(first.emitted_functions, second.emitted_functions);
}

test "owned callback specialization keeps runtime scalar captures as parameters" {
    var module = try lower(a, "const apply = func (base: U32) => return do:\n  let add = func (value: U32) => return @u32.add base value\n  break @u32.add (add 2) (add 3)\nentry const answer = func () => return apply 10\n");
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}

test "owned inline calls reuse aggregate parameter and result layouts" {
    const helper = "const pair = func (input: {left: U32, right: U32}) => return {left: @u32.add input.left 1, right: input.right}\n";
    var once = try lower(a, helper ++ "entry const answer = func () => return do:\n  let mode: GrowArray U32 = #[0]\n  let result = pair {left: 40, right: 2}\n  return result.left\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ "entry const answer = func () => return do:\n  let mode: GrowArray U32 = #[0]\n  let first = pair {left: 40, right: 2}\n  let second = pair {left: 1, right: 3}\n  return @u32.add first.left second.left\n");
    defer twice.deinit(a);
    var baseline = try lower(a, "entry const answer = func () => return do:\n  let mode: GrowArray U32 = #[0]\n  return 41\n");
    defer baseline.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    try std.testing.expect(base.diagnostic == null);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "owned reader calls reuse code across independent owner identities" {
    const helper = "const read = func (values: ResizeArray U32) => return @storage.read values 0\n";
    const owners = "entry const answer = func () => return do:\n  let first: ResizeArray U32 = #[7]\n  let second: ResizeArray U32 = #[9]\n";
    var baseline = try lower(a, owners ++ "  return @u32.add first[0] second[0]\n");
    defer baseline.deinit(a);
    var once = try lower(a, helper ++ owners ++ "  return @u32.add (read first) second[0]\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ owners ++ "  return @u32.add (read first) (read second)\n");
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(base.diagnostic == null);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "closed owned calls reuse code across unrelated generic environments" {
    const helper = "const inc = func (value: U32) => return @u32.add value 1\nconst wrap = func unrelated -> (value: U32) => return do:\n  let scratch: GrowArray U32 = #[value]\n  return inc scratch[0]\n";
    var once = try lower(a, helper ++ "entry const answer = func () => return do:\n  let mode: GrowArray U32 = #[0]\n  return wrap true 41\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ "entry const answer = func () => return do:\n  let mode: GrowArray U32 = #[0]\n  let first = wrap true 41\n  return @u32.add first (wrap 2.0 3)\n");
    defer twice.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "closed direct call graphs reuse inline data without admitting recursive calls" {
    const helper = "const inc = func (value: U32) => return @u32.add value 1\nconst pair = func (input: {left: U32, right: U32}) => return {left: inc input.left, right: input.right}\n";
    const entry = "entry const answer = func () => return do:\n  let rows: GrowArray U32 = #[0]\n";
    var baseline = try lower(a, entry ++ "  return 42\n");
    defer baseline.deinit(a);
    var module = try lower(a, helper ++ entry ++ "  let first = pair {left: 40, right: 2}\n  let second = pair {left: 1, right: 3}\n  return @u32.add first.left second.left\n");
    defer module.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(base.diagnostic == null);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, result.emitted_functions);
    var cycle = try lower(a, "const cycle = func (value: U32): U32 => return cycle value\nentry const answer = func () => return cycle 1\n");
    defer cycle.deinit(a);
    var remaining: usize = 10_000;
    for (cycle.bodies) |body| try std.testing.expect(!@import("storage_calls.zig").inlineBody(&.{cycle}, &cycle, body.binding, &remaining));
    try std.testing.expect(remaining != 0);
}

test "owned readonly descriptor captures reuse helpers across caller owners" {
    const helper = "const reading = func (rows: &[U32]) -> (index: U32) => return do:\n  let callback = func (at: U32) => return @storage.read rows at\n  return callback index\n";
    const entry = "entry const answer = func () => return do:\n  let first: ResizeArray U32 = #[7]\n  let second: ResizeArray U32 = #[9]\n";
    var baseline = try lower(a, entry ++ "  return @u32.add first[0] second[0]\n");
    defer baseline.deinit(a);
    var once = try lower(a, helper ++ entry ++ "  return @u32.add (reading (&first[0..1]) 0) second[0]\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ entry ++ "  return @u32.add (reading (&first[0..1]) 0) (reading (&second[0..1]) 0)\n");
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(base.diagnostic == null);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "selected numeric declarations reuse exact generic scalar specializations" {
    const helper = "const U32.minus = func (left: U32) -> (right: U32): U32 => return @u32.sub left right\nconst difference = func left -> right => return @type.call \"minus\" left right\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let rows: ResizeArray U32 = #[42, 2]\n";
    var baseline = try lower(a, entry ++ "  return @u32.sub rows[0] rows[1]\n");
    defer baseline.deinit(a);
    var once = try lowerWithCatalog(a, helper ++ entry ++ "  return difference rows[0] rows[1]\n", true);
    defer once.deinit(a);
    var twice = try lowerWithCatalog(a, helper ++ entry ++ "  return @u32.add (difference rows[0] rows[1]) (difference rows[1] 1)\n", true);
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
}

test "selected inline data helpers reuse checked record results" {
    const helpers = "const U32.minus = func (left: U32) -> (right: U32): U32 => return @u32.sub left right\nconst pack = func (input: {left: U32, right: U32}) => return {left: @type.call \"minus\" input.left input.right, right: input.right}\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let rows: ResizeArray U32 = #[42, 2]\n";
    var baseline = try lower(a, entry ++ "  return @u32.sub rows[0] rows[1]\n");
    defer baseline.deinit(a);
    var once = try lowerWithCatalog(a, helpers ++ entry ++ "  let result = pack {left: rows[0], right: rows[1]}\n  return result.left\n", true);
    defer once.deinit(a);
    var twice = try lowerWithCatalog(a, helpers ++ entry ++ "  let first = pack {left: rows[0], right: rows[1]}\n  let second = pack {left: 9, right: 1}\n  return @u32.add first.left second.left\n", true);
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "readonly descriptor records reuse caller result slots across owners" {
    const helper = "type Bundle is data = #Bundle {rows: &[U32], bias: U32}\nconst folded = func (input: Bundle) => return do:\n  let total = input.bias\n  for index in 0..@storage.length input.rows:\n    total := @u32.add self (@storage.read input.rows index)\n  return {total, count: @storage.length input.rows}\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let first: ResizeArray U32 = #[7, 9]\n  let second: ResizeArray U32 = #[11]\n";
    var once = try lower(a, helper ++ entry ++ "  let value = folded (#Bundle {rows: &first[0..2], bias: 1})\n  return value.total\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ entry ++ "  let left = folded (#Bundle {rows: &first[0..2], bias: 1})\n  let right = folded (#Bundle {rows: &second[0..1], bias: 2})\n  return @u32.add left.total right.total\n");
    defer twice.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "pure generic wrappers specialize their actual runtime parameter types" {
    const helper = "const inc = func (value: U32) => return @u32.add value 1\nconst wrap = func unrelated -> (value: U32) => return inc value\n";
    var once = try lower(a, helper ++ "entry const answer = func (): U32 => return do:\n  let rows: GrowArray U32 = #[41]\n  return wrap true rows[0]\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ "entry const answer = func (): U32 => return do:\n  let rows: GrowArray U32 = #[41, 3]\n  return @u32.add (wrap true rows[0]) (wrap 2.0 rows[1])\n");
    defer twice.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(left.emitted_functions + 1, right.emitted_functions);
}

test "static readonly callback arguments reuse selected helpers across owners" {
    const helpers = "const plus = func (value: U32): U32 => return @u32.add value 1\nconst folded = func transform -> (rows: &[U32]): U32 => return do:\n  let total = 0\n  for index in 0..@storage.length rows:\n    total := @u32.add self (transform (@storage.read rows index))\n  return total\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let first: ResizeArray U32 = #[7, 9]\n  let second: ResizeArray U32 = #[11]\n";
    var baseline = try lower(a, entry ++ "  return @u32.add first[0] second[0]\n");
    defer baseline.deinit(a);
    var once = try lower(a, helpers ++ entry ++ "  return folded plus (&first[0..2])\n");
    defer once.deinit(a);
    var twice = try lower(a, helpers ++ entry ++ "  return @u32.add (folded plus (&first[0..2])) (folded plus (&second[0..1]))\n");
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "returned reader descriptors reuse alias maps without fresh owner results" {
    const helper = "type Buffer is data = #Buffer {rows: ResizeArray U32, label: U32}\nconst chosen = func (input: Buffer): Buffer => return input\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let first: ResizeArray U32 = #[7]\n  let second: ResizeArray U32 = #[9]\n";
    var baseline = try lower(a, entry ++ "  return @u32.add first[0] second[0]\n");
    defer baseline.deinit(a);
    var once = try lower(a, helper ++ entry ++ "  let value = chosen (#Buffer {rows: first, label: 1})\n  return value.rows[0]\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ entry ++ "  let left = chosen (#Buffer {rows: first, label: 1})\n  let right = chosen (#Buffer {rows: second, label: 2})\n  return @u32.add left.rows[0] right.rows[0]\n");
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
    const copy = "const copied = func (rows: ResizeArray U32) => return @storage.copy rows\n";
    var direct = try lower(a, entry ++ "  let output = @storage.copy first\n  return output[0]\n");
    defer direct.deinit(a);
    var expanded = try lower(a, copy ++ entry ++ "  let output = copied first\n  return output[0]\n");
    defer expanded.deinit(a);
    var plain = try scoped.compile(a, &.{direct}, 1);
    defer plain.deinit(a);
    var fresh = try scoped.compile(a, &.{expanded}, 1);
    defer fresh.deinit(a);
    try std.testing.expect(plain.diagnostic == null);
    try std.testing.expect(fresh.diagnostic == null);
    try std.testing.expectEqual(plain.emitted_functions, fresh.emitted_functions);
}

test "plain Unit writers reuse checked row mutation and growth helpers" {
    const helper = "const advance = func (rows: ResizeArray U32) -> (amount: U32): Unit => return do:\n  @storage.write (@storage.at rows 0) (@u32.add (@storage.read rows 0) amount)\n  @storage.push rows amount\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let first: ResizeArray U32 = #[7]\n  let second: ResizeArray U32 = #[9]\n";
    var baseline = try lower(a, entry ++ "  return @storage.read first 0\n");
    defer baseline.deinit(a);
    var once = try lower(a, helper ++ entry ++ "  advance first 2\n  return @storage.read first 0\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ entry ++ "  advance first 2\n  advance second 3\n  return @u32.add (@storage.read first 0) (@storage.read second 0)\n");
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "selected pure calls follow exact reference aliases without expanding callers" {
    const helper = "const rounded = func (value: F32): F32 => return @f32.floor value\nconst raised = func (value: F32): F32 => return @f32.ceil value\nconst alias = rounded\nconst again = alias\nconst upper = raised\nconst convert = func (value: F32): U32 => return @u32.add (@f32.to_u32 (again value)) (@f32.to_u32 (upper value))\n";
    const entry = "entry const answer = func (): U32 => return do:\n  let rows: ResizeArray F32 = #[1.5, 2.5]\n";
    var baseline = try lower(a, entry ++ "  return @u32.add (@f32.to_u32 (@f32.floor rows[0])) (@f32.to_u32 (@f32.ceil rows[0]))\n");
    defer baseline.deinit(a);
    var once = try lower(a, helper ++ entry ++ "  return convert rows[0]\n");
    defer once.deinit(a);
    var twice = try lower(a, helper ++ entry ++ "  return @u32.add (convert rows[0]) (convert rows[1])\n");
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "selected primitive associated partials reuse their saturated callers" {
    const helper = "const F32.blend = func (left: F32) -> (right: F32) -> (weight: F32): F32 => return @f32.add left (@f32.mul (@f32.sub right left) weight)\nconst F32.weighted = func (left: F32) -> (right: F32) -> (weight: F32): F32 => return @f32.add left (@f32.mul right weight)\nconst blend = func left -> right => return @type.call \"blend\" left right\nconst weighted = func left -> right => return @type.call \"weighted\" left right\nconst interpolate = func (value: F32): F32 => return @f32.add (blend 0.0 value 0.25) (weighted 1.0 value 0.75)\n";
    const entry = "entry const answer = func (): F32 => return do:\n  let rows: ResizeArray F32 = #[2.0, 4.0]\n";
    var baseline = try lower(a, entry ++ "  return @f32.add (@f32.mul rows[0] 0.25) (@f32.add 1.0 (@f32.mul rows[0] 0.75))\n");
    defer baseline.deinit(a);
    var once = try lowerWithCatalog(a, helper ++ entry ++ "  return interpolate rows[0]\n", true);
    defer once.deinit(a);
    var twice = try lowerWithCatalog(a, helper ++ entry ++ "  return @f32.add (interpolate rows[0]) (interpolate rows[1])\n", true);
    defer twice.deinit(a);
    var base = try scoped.compile(a, &.{baseline}, 1);
    defer base.deinit(a);
    var left = try scoped.compile(a, &.{once}, 1);
    defer left.deinit(a);
    var right = try scoped.compile(a, &.{twice}, 1);
    defer right.deinit(a);
    if (left.diagnostic) |diagnostic| {
        std.debug.print("ASSOCIATED_NATIVE_FAILURE {d}:{d}..{d} {s}\n", .{ diagnostic.unit, diagnostic.span.start, diagnostic.span.end, diagnostic.detail });
        for (once.bodies) |body| std.debug.print("ASSOCIATED_NATIVE_BODY {d} {s} parameters={d} span={d}..{d}\n", .{ body.binding, @tagName(once.node(body.root).tag), once.bodyParameters(&body).len, once.span(body.root).start, once.span(body.root).end });
    }
    try std.testing.expect(left.diagnostic == null);
    try std.testing.expect(right.diagnostic == null);
    // Expanded callers would emit two distinct numeric leaf helpers instead.
    try std.testing.expectEqual(base.emitted_functions + 1, left.emitted_functions);
    try std.testing.expectEqual(left.emitted_functions, right.emitted_functions);
}

test "selected application policies share wide callback type descriptions within the existing bound" {
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "type Wide = {");
    for (0..166) |index| {
        const field = try std.fmt.allocPrint(a, "f{d}: Array U32,", .{index});
        defer a.free(field);
        try source.appendSlice(a, field);
    }
    try source.appendSlice(a, "}\nconst inspect = func (value: Wide): U32 ! {} => return 0\nconst policy = func ");
    for (0..13) |index| {
        const parameter = try std.fmt.allocPrint(a, "callback_{d} -> ", .{index});
        defer a.free(parameter);
        try source.appendSlice(a, parameter);
    }
    try source.appendSlice(a, "(value: U32): U32 => return @u32.add value 1\nentry const answer = func () => return do:\n  let kept: Array U32 = #[41]\n  return policy ");
    for (0..13) |_| try source.appendSlice(a, "inspect ");
    try source.appendSlice(a, "kept[0]\n");
    var module = try lower(a, source.items);
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    if (result.diagnostic) |diagnostic| std.debug.print("wide policy diagnostic: {s}\n", .{diagnostic.message()});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
