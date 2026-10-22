const std = @import("std");
const core = @import("../check/core.zig");
const ragged = @import("ragged_builder.zig");
const backend = @import("core_backend.zig");
const a = std.testing.allocator;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    return lowerNames(allocator, source, null);
}
fn lowerNames(allocator: std.mem.Allocator, source: []const u8, metadata: ?*@import("runtime_identity.zig").Metadata) !core.Module {
    var lexed = try @import("../parse/lexer.zig").lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: @import("../parse/symbols.zig").Pool = .{};
    defer pool.deinit(allocator);
    var tree = try @import("../parse/parser.zig").parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try @import("../check/check.zig").checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true, .prelude_unit = 1 });
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("ragged check {s} at {d}\n", .{ diagnostic.message(), diagnostic.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &pool, &checked);
    module.unit = 1;
    errdefer module.deinit(allocator);
    if (metadata) |out| out.* = try @import("runtime_identity.zig").Metadata.capture(allocator, &pool, &.{.{ .unit = 1, .path = "/ragged/main.blot" }}, 1);
    return module;
}
const PrimitiveFacts = struct {
    module: *const core.Module,
    pub fn primitive(self: @This(), id: core.Id) bool {
        const n = self.module.node(id);
        return n.tag == .scalar and n.c == 0;
    }
    pub fn reference(self: @This(), id: core.Id) bool {
        const ref = self.module.reference(id);
        const kind = self.module.binding(ref.binding).kind;
        return kind == .local or kind == .parameter;
    }
    pub fn field(_: @This(), _: core.Id) bool {
        return false;
    }
    pub fn pattern(self: @This(), id: core.Id) bool {
        const binding_pattern = self.module.pattern(self.module.loopInfo(id).pattern);
        return binding_pattern.tag == .bind or binding_pattern.tag == .wildcard;
    }
};
const triangle_source =
    \\entry const run = fn (count: U32) => do:
    \\  let result: List U32 = []
    \\  for x in 0..count:
    \\    for y in 0..x:
    \\      result := [...self, @u32.add (@u32.mul x 10) y]
    \\  break @array.from_list result
;
test "ragged proof admits dependent bounds and ordered guard qualifier merges" {
    const sources = [_][]const u8{
        triangle_source,
        "entry const run = fn (values: Array U32) => #[square | x <- values, @u32.lt 1 x, let square = @u32.mul x x, @u32.lt square 10]\n",
        "entry const run = fn (values: Array U32) => [y | x <- values, @u32.lt 1 x, y <- values, @u32.lt y x]\n",
    };
    for (sources) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        const plan = ragged.analyze(&module, module.bodies[1].root, PrimitiveFacts{ .module = &module });
        try std.testing.expect(plan != null);
    }
}
test "ragged proof declines trapping controls payloads and intermediate observations" {
    const sources = [_][]const u8{
        "entry const run = fn (values: Array U32) => #[x | x <- values, @u32.lt 0 (@u32.div 1 x)]\n",
        "entry const run = fn (values: Array U32) => #[@u32.div 1 x | x <- values, @u32.lt 0 x]\n",
        "entry const run = fn (values: Array U32) => #[#[x] | x <- values, @u32.lt 0 x]\n",
        "entry const run = fn (count: U32) => do:\n  let result: List U32 = []\n  for x in 0..count:\n    for y in 0..x:\n      result := @list.append result (@list.length result)\n  break result\n",
    };
    for (sources) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        try std.testing.expect(ragged.analyze(&module, module.bodies[1].root, PrimitiveFacts{ .module = &module }) == null);
    }
}
fn emission(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{});
    defer result.deinit(allocator);
    if (result.diagnostic) |diagnostic| std.debug.print("ragged emit {s}\n", .{diagnostic.message()});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(@as(u64, 1), result.counters.ragged_runtime_regions);
}
test "ragged runtime preparation emits selected primitive controls and owns every allocation failure" {
    var module = try lower(a, triangle_source);
    defer module.deinit(a);
    try emission(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emission, .{&module});
    var ordinary = try backend.compileWithOptions(a, &.{module}, 1, .{ .ragged_builders = false });
    defer ordinary.deinit(a);
    try std.testing.expect(ordinary.diagnostic == null);
    try std.testing.expectEqual(@as(u64, 0), ordinary.counters.ragged_runtime_regions);
}
test "ragged selected primitive source adapters admit ordinary typed operators" {
    var module = try lower(a, wrappers ++ selected_region);
    defer module.deinit(a);
    try emission(a, &module);
}

const evaluator = @import("../eval/core_eval.zig");
fn target(module: *const core.Module, name: []const u8) core.BindingRef {
    for (module.bodies) |body| if (body.exported and std.mem.eql(u8, module.name(body.export_name), name)) return .{ .unit = module.unit, .binding = body.binding };
    unreachable;
}
const staged_source =
    \\const triangle = fn (count: U32) => do:
    \\  let result: List U32 = []
    \\  for x in 0..count:
    \\    for y in 0..x:
    \\      result := [...self, @u32.add (@u32.mul x 10) y]
    \\  break @array.from_list result
    \\entry const values = triangle 4
;
fn stagedOwnership(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    const result = try session.richValue(target(module, "values"));
    const expected = [_]u32{ 10, 20, 21, 30, 31, 32 };
    const children = session.valueChildren(result);
    try std.testing.expectEqual(expected.len, children.len);
    for (children, expected) |child, bits| try std.testing.expectEqual(bits, session.valueScalar(child).?.bits);
    try std.testing.expectEqual(@as(u64, 1), session.counters.ragged_staged_regions);
    try std.testing.expectEqual(@as(u64, 6), session.counters.ragged_published_children);
    try std.testing.expectEqual(@as(usize, 0), session.ragged_reserved_children);
    try std.testing.expect(session.ragged_region == null);
}
test "ragged staged borrowed controls own private fill and every allocation failure" {
    var module = try lower(a, staged_source);
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    try stagedOwnership(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, stagedOwnership, .{&module});
    try std.testing.expectEqualSlices(core.Node, nodes, module.nodes);
}
fn fuelBoundaries(source: []const u8) !void {
    var module = try lower(a, source);
    defer module.deinit(a);
    var ordinary = try evaluator.Session.init(a, &.{module});
    defer ordinary.deinit();
    ordinary.ragged_probe_limit = 0;
    _ = try ordinary.richValue(target(&module, "values"));
    for (0..ordinary.steps + 1) |fuel| {
        var optimized = try evaluator.Session.init(a, &.{module});
        defer optimized.deinit();
        var baseline = try evaluator.Session.init(a, &.{module});
        defer baseline.deinit();
        baseline.ragged_probe_limit = 0;
        optimized.options.max_steps = fuel;
        baseline.options.max_steps = fuel;
        const fast = optimized.richValue(target(&module, "values"));
        const slow = baseline.richValue(target(&module, "values"));
        if (fast) |_| {
            _ = try slow;
        } else |err| {
            try std.testing.expectEqual(error.Declined, err);
            try std.testing.expectError(error.Declined, slow);
            try std.testing.expectEqualDeep(baseline.diagnostic.?, optimized.diagnostic.?);
        }
        try std.testing.expectEqual(baseline.steps, optimized.steps);
        try std.testing.expectEqual(@as(usize, 0), optimized.ragged_reserved_children);
    }
    var exhausted = try evaluator.Session.init(a, &.{module});
    defer exhausted.deinit();
    exhausted.ragged_probe_limit = 1;
    const result = try exhausted.richValue(target(&module, "values"));
    try std.testing.expectEqual(@as(usize, 6), exhausted.valueChildren(result).len);
    try std.testing.expect(exhausted.counters.ragged_probe_declines > 0);
    try std.testing.expectEqual(@as(u64, 0), exhausted.counters.ragged_staged_regions);
    try std.testing.expectEqual(ordinary.steps, exhausted.steps);
}

const wrappers =
    \\infix 30 (>) = gt
    \\infix 30 (<) = lt
    \\infixl 70 (*) = mul
    \\const gt = fn left => fn right => @type.call "gt" left right
    \\const lt = fn left => fn right => @type.call "lt" left right
    \\const mul = fn left => fn right => @type.call "mul" left right
    \\const U32.lt = fn left => fn right => @u32.lt left right
    \\const U32.gt = fn left => fn right => U32.lt right left
    \\const U32.mul = fn left => fn right => @u32.mul left right
;
const selected_region = "\nentry const run = fn (values: Array U32) => #[square | x <- values, x > 1, let square = x * x, square < 10]\n";
test "ragged staged fill preserves source fuel including primitive wrapper applications" {
    try fuelBoundaries(staged_source);
    var module = try lower(a, wrappers ++ "\nconst selected = fn (values: Array U32) => #[square | x <- values, x > 1, let square = x * x, square < 10]\nentry const values = selected #[0,1,2,3,4]\n");
    defer module.deinit(a);
    var ordinary = try evaluator.Session.init(a, &.{module});
    defer ordinary.deinit();
    ordinary.ragged_probe_limit = 0;
    _ = try ordinary.richValue(target(&module, "values"));
    for (0..ordinary.steps + 1) |fuel| {
        var fast = try evaluator.Session.init(a, &.{module});
        defer fast.deinit();
        var slow = try evaluator.Session.init(a, &.{module});
        defer slow.deinit();
        slow.ragged_probe_limit = 0;
        fast.options.max_steps = fuel;
        slow.options.max_steps = fuel;
        const result = fast.richValue(target(&module, "values"));
        if (result) |_| {
            const old = try slow.richValue(target(&module, "values"));
            try std.testing.expectEqual(@as(usize, 2), slow.valueChildren(old).len);
            try std.testing.expectEqual(@as(u64, 1), fast.counters.ragged_staged_regions);
        } else |err| {
            try std.testing.expectEqual(error.Declined, err);
            try std.testing.expectError(error.Declined, slow.richValue(target(&module, "values")));
            try std.testing.expectEqualDeep(slow.diagnostic.?, fast.diagnostic.?);
        }
        try std.testing.expectEqual(slow.steps, fast.steps);
    }
}
test "ragged retained stable type wrapper edits invalidate every primitive spine dependency" {
    var before_names: @import("runtime_identity.zig").Metadata = undefined;
    var before = try lowerNames(a, wrappers ++ selected_region, &before_names);
    defer before.deinit(a);
    defer before_names.deinit(a);
    const edited_source = try std.mem.replaceOwned(u8, a, wrappers ++ selected_region, "@u32.mul left right", "@u32.div left right");
    defer a.free(edited_source);
    var after_names: @import("runtime_identity.zig").Metadata = undefined;
    var after = try lowerNames(a, edited_source, &after_names);
    defer after.deinit(a);
    defer after_names.deinit(a);
    var first = try backend.compileWithOptions(a, &.{before}, 1, .{ .identity = before_names.view(), .retain_artifacts = true });
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    try std.testing.expectEqual(@as(u64, 1), first.counters.ragged_runtime_regions);
    var no_op = try backend.compileWithOptions(a, &.{before}, 1, .{ .identity = before_names.view(), .retain_artifacts = true, .previous = &first.capture.? });
    defer no_op.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, no_op.bytes);
    var edited = try backend.compileWithOptions(a, &.{after}, 1, .{ .identity = after_names.view(), .retain_artifacts = true, .previous = &no_op.capture.? });
    defer edited.deinit(a);
    var fresh = try backend.compileWithOptions(a, &.{after}, 1, .{});
    defer fresh.deinit(a);
    try std.testing.expect(edited.diagnostic == null and fresh.diagnostic == null);
    try std.testing.expectEqual(@as(u64, 0), fresh.counters.ragged_runtime_regions);
    try std.testing.expectEqualSlices(u8, fresh.bytes, edited.bytes);
    try std.testing.expect(!std.mem.eql(u8, first.bytes, edited.bytes));
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, retainedRecovery, .{ &after, after_names.view(), &no_op.capture.? });
    var recovered = try backend.compileWithOptions(a, &.{before}, 1, .{ .identity = before_names.view(), .retain_artifacts = true, .previous = &no_op.capture.? });
    defer recovered.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, recovered.bytes);
}

test "ragged sizing uses exact ceilings and checked header row arithmetic" {
    try std.testing.expectEqual(@as(u32, 0x10000000), ragged.maximumCount(0, false).?);
    try std.testing.expectEqual(@as(u32, 0x10000000), ragged.maximumCount(0, true).?);
    try std.testing.expectEqual(@as(u32, 67_108_863), ragged.maximumCount(16, false).?);
    try std.testing.expectEqual(@as(u32, 16_777_216), ragged.maximumCount(16, true).?);
    try std.testing.expect(ragged.maximumCount(0x40000000, false) == null);
    try std.testing.expectEqual(@as(u32, 0), ragged.maximumCount(std.math.maxInt(u32), true).?);
}
test "ragged staged zero and selected outputs preserve successful ordinary value child and depth limits" {
    const sources = [_][]const u8{
        staged_source,
        "entry const values = [x | x <- #[], #False]\n",
        "entry const values = #[x | x <- #[1,2,3], #False]\n",
        "entry const values = [x | x <- #[1,2,3], @u32.lt 1 x]\n",
    };
    for (sources) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        for (0..3) |kind| for (1..65) |limit| {
            var slow = try evaluator.Session.init(a, &.{module});
            defer slow.deinit();
            var fast = try evaluator.Session.init(a, &.{module});
            defer fast.deinit();
            slow.ragged_probe_limit = 0;
            switch (kind) {
                0 => {
                    slow.options.max_values = limit;
                    fast.options.max_values = limit;
                },
                1 => {
                    slow.options.max_children = limit;
                    fast.options.max_children = limit;
                },
                else => {
                    slow.options.max_depth = limit;
                    fast.options.max_depth = limit;
                },
            }
            const expected = slow.richValue(target(&module, "values")) catch |err| {
                if (err == error.OutOfMemory) return err;
                continue;
            };
            const actual = try fast.richValue(target(&module, "values"));
            try std.testing.expectEqual(slow.valueInfo(expected).kind, fast.valueInfo(actual).kind);
            try std.testing.expectEqual(slow.valueChildren(expected).len, fast.valueChildren(actual).len);
            try std.testing.expect(fast.diagnostic == null and fast.ragged_region == null);
            try std.testing.expectEqual(@as(usize, 0), fast.ragged_reserved_children);
        };
    }
}
test "ragged staged construction publishes only selected children across growth" {
    for ([_]usize{ 0, 1, 8, 32, 128 }) |count| {
        const source = try a.print("const build = fn count => do:\n  let result: List U32 = []\n  for x in 0..count:\n    for y in 0..x:\n      result := @list.append self (@u32.add (@u32.mul x 10) y)\n  break @array.from_list result\nentry const values = build {d}\n", .{count});
        defer a.free(source);
        var module = try lower(a, source);
        defer module.deinit(a);
        var fast = try evaluator.Session.init(a, &.{module});
        defer fast.deinit();
        var slow = try evaluator.Session.init(a, &.{module});
        defer slow.deinit();
        slow.ragged_probe_limit = 0;
        const actual = try fast.richValue(target(&module, "values"));
        const expected = try slow.richValue(target(&module, "values"));
        const selected = count * (count -| 1) / 2;
        try std.testing.expectEqual(selected, fast.valueChildren(actual).len);
        try std.testing.expectEqual(selected, fast.storage.children.items.len);
        try std.testing.expectEqual(slow.steps, fast.steps);
        for (fast.valueChildren(actual), slow.valueChildren(expected)) |left, right| try std.testing.expectEqualDeep(fast.valueScalar(left).?, slow.valueScalar(right).?);
        if (selected != 0) try std.testing.expect(slow.storage.children.items.len > fast.storage.children.items.len);
        try std.testing.expectEqual(selected, fast.counters.ragged_published_children);
    }
}

fn retainedRecovery(allocator: std.mem.Allocator, module: *const core.Module, identity: @import("runtime_identity.zig").View, previous: *const @import("../reuse/artifact_capture.zig").Capture) !void {
    var result = try backend.compileWithOptions(allocator, &.{module.*}, 1, .{ .identity = identity, .retain_artifacts = true, .previous = previous });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
}
test "ragged runtime preparation admits packed copies four dimensions and established global inputs" {
    const sources = [_][]const u8{
        "const copied = fn (rows: Array {a: U32, b: U32, z: U32}) => #[row | row <- rows, @u32.lt row.a 249]\nentry const run = fn count => do:\n  let rows = @array.generate count (fn i => {a: i, b: @u32.add i 1, z: @u32.mul i 3})\n  break @array.length (copied rows)\n",
        "const copied = fn (rows: List {a: U32, b: U32, z: U32}) => [row | row <- rows, @u32.lt row.a 249]\nentry const run = fn count => do:\n  let rows = @list.generate count (fn i => {a: i, b: @u32.add i 1, z: @u32.mul i 3})\n  break @list.length (copied rows)\n",
        "entry const run = fn count => do:\n  let values: List U32 = []\n  for a in 0..count:\n    for b in 0..a:\n      for c in 0..b:\n        for d in 0..c:\n          values := @list.append self d\n  break @array.from_list values\n",
        "let inputs = @array.fill 4 7\nentry const run = fn threshold => #[x | x <- inputs, @u32.lt threshold x]\n",
    };
    for (sources) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        try emission(a, &module);
    }
}

test "ragged speculative facts preserve unreached payloads at the real evidence limit" {
    var source: std.Io.Writer.Allocating = .init(a);
    defer source.deinit();
    try source.writer.writeAll("type Deep0 = U32\n");
    for (1..20) |depth| try source.writer.print("type Deep{d} = (Deep{d}, Deep{d})\n", .{ depth, depth - 1, depth - 1 });
    try source.writer.writeAll(
        \\const ignored = fn left => fn right => 0
        \\entry const values = do:
        \\  let values: List U32 = []
        \\  for x in 0..0:
        \\    let left: Array Deep19 = #[]
        \\    values := @list.append self (ignored left left)
        \\  break @array.from_list values
        \\entry const filtered = do:
        \\  let values: List U32 = []
        \\  for x in 0..1:
        \\    if #False:
        \\      let left: Array Deep19 = #[]
        \\      values := @list.append self (ignored left left)
        \\  break @array.from_list values
        \\
    );
    var module = try lower(a, source.written());
    defer module.deinit(a);
    var evidence = try @import("../eval/type_evidence.zig").Store.init(a);
    defer evidence.deinit();
    var limit_seen = false;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .call or module.children(@intCast(id)).len != 2) continue;
        const operand = module.children(@intCast(id))[0];
        try std.testing.expectError(error.EvidenceLimit, evidence.project(&module.types, module.typeOf(operand), &.{}));
        limit_seen = true;
        break;
    }
    try std.testing.expect(limit_seen);
    for ([_][]const u8{ "values", "filtered" }) |name| {
        var ordinary = try evaluator.Session.init(a, &.{module});
        defer ordinary.deinit();
        ordinary.ragged_probe_limit = 0;
        const expected = try ordinary.richValue(target(&module, name));
        try std.testing.expectEqual(@as(usize, 0), ordinary.valueChildren(expected).len);
        var fast = try evaluator.Session.init(a, &.{module});
        defer fast.deinit();
        const actual = try fast.richValue(target(&module, name));
        try std.testing.expectEqual(@as(usize, 0), fast.valueChildren(actual).len);
        try std.testing.expectEqual(ordinary.steps, fast.steps);
        try std.testing.expect(fast.diagnostic == null);
        try std.testing.expectEqual(@as(u64, 0), fast.counters.ragged_staged_regions);
        var short_ordinary = try evaluator.Session.init(a, &.{module});
        defer short_ordinary.deinit();
        short_ordinary.ragged_probe_limit = 0;
        short_ordinary.options.max_steps = ordinary.steps - 1;
        var short_fast = try evaluator.Session.init(a, &.{module});
        defer short_fast.deinit();
        short_fast.options.max_steps = ordinary.steps - 1;
        try std.testing.expectError(error.Declined, short_ordinary.richValue(target(&module, name)));
        try std.testing.expectError(error.Declined, short_fast.richValue(target(&module, name)));
        try std.testing.expectEqualDeep(short_ordinary.diagnostic.?, short_fast.diagnostic.?);
        try std.testing.expectEqual(short_ordinary.steps, short_fast.steps);
    }
}

test "ragged imported controls cannot alias local bindings with the same numeric identity" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const source =
        \\import { limit } from "./limits"
        \\entry const run = fn () => do:
        \\  let result: List U32 = []
        \\  for x in 0..3:
        \\    if @u32.lt x limit:
        \\      result := [...self, x]
        \\  break @array.from_list result
        \\const folded = run ()
        \\entry const staged = fn () => folded
    ;
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = source });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "prelude.blot", .data = "" });
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
    defer a.free(path);
    const prelude = try dir.dir.realPathFileAlloc(std.testing.io, "prelude.blot", a);
    defer a.free(prelude);
    {
        const padding = 6;
        var library: std.ArrayList(u8) = .empty;
        defer library.deinit(a);
        for (0..padding) |index| {
            const declaration = try a.print("const padding{d}: U32 = 4\n", .{index});
            defer a.free(declaration);
            try library.appendSlice(a, declaration);
        }
        try library.appendSlice(a, "const limit: U32 = 4\n");
        try dir.dir.writeFile(std.testing.io, .{ .sub_path = "limits.blot", .data = library.items });
        var loaded = try @import("../reuse/project.zig").load(a, std.testing.io, path, .{ .prelude_path = prelude });
        defer loaded.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
        var checked = try @import("../reuse/project_check.zig").checkProject(a, &loaded);
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const units = try a.alloc(core.Module, loaded.units.items.len);
        defer a.free(units);
        var initialized: usize = 0;
        defer for (units[0..initialized]) |*unit| unit.deinit(a);
        for (units, 1..) |*unit, index| {
            unit.* = try core.lower(a, &loaded.unit(@intCast(index)).tree, &loaded.symbols, &checked.module(@intCast(index)).checked);
            unit.unit = @intCast(index);
            initialized += 1;
        }
        const main = &units[loaded.entry - 1];
        var local: core.BindingId = 0;
        var foreign: core.BindingRef = .{ .binding = 0 };
        for (main.nodes, 0..) |node, index| {
            if (node.tag == .loop) local = main.pattern(main.loopInfo(@intCast(index)).pattern).a;
            if (node.tag == .reference) {
                const ref = main.reference(@intCast(index));
                if (ref.unit != 0 and ref.unit != main.unit) foreign = ref;
            }
        }
        try std.testing.expectEqual(local, foreign.binding);
        try std.testing.expect(foreign.unit != main.unit);
        var folded: core.BindingRef = .{ .unit = main.unit, .binding = 0 };
        for (checked.module(main.unit).checked.bindings, 0..) |binding, index| {
            if (std.mem.eql(u8, loaded.symbols.get(binding.name), "folded")) folded.binding = @intCast(index);
        }
        var fast = try evaluator.Session.init(a, units);
        defer fast.deinit();
        var slow = try evaluator.Session.init(a, units);
        defer slow.deinit();
        slow.ragged_probe_limit = 0;
        _ = try fast.richValue(foreign);
        _ = try slow.richValue(foreign);
        const fast_value = try fast.richValue(folded);
        const slow_value = try slow.richValue(folded);
        try std.testing.expectEqual(@as(usize, 3), fast.valueChildren(fast_value).len);
        for (fast.valueChildren(fast_value), slow.valueChildren(slow_value), 0..) |actual, expected, index| {
            try std.testing.expectEqual(@as(u32, @intCast(index)), fast.valueScalar(actual).?.bits);
            try std.testing.expectEqual(slow.valueScalar(expected).?.bits, fast.valueScalar(actual).?.bits);
        }
        try std.testing.expectEqual(slow.steps, fast.steps);
        try std.testing.expectEqual(@as(u64, 1), fast.counters.ragged_staged_regions);
        var emitted = try backend.compileWithOptions(a, units, loaded.entry, .{});
        defer emitted.deinit(a);
        try std.testing.expect(emitted.diagnostic == null);
        try std.testing.expectEqual(@as(u64, 1), emitted.counters.ragged_runtime_regions);
        return;
    }
}
