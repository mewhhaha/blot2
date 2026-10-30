const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const scoped = @import("scoped_backend.zig");
const a = std.testing.allocator;
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
