const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const core = @import("../check/core.zig");
const core_builder = @import("../check/core_builder.zig");
const parallel_lowering = @import("../check/parallel_lowering.zig");
const structural = @import("../structural.zig");

const prelude = "infixl 60 (+) = plus\nconst plus = func left => return func right => return @u32.add left right\ntype Box a is data = $Box a\n";
const shared = "const unwrap = func box => return case box of\n  $Box value => value\nconst twice = func value => return value + value\n";
const left = "import {unwrap, twice} from \"./shared\"\nconst first = func value => return twice (unwrap ($Box value))\nconst third = func value => return first value + 1\n";
const right = "import {unwrap} from \"./shared\"\nconst second = func value => return unwrap ($Box (value + 2))\n";
const entry = "import {first, third} from \"./left\"\nimport {second} from \"./right\"\nentry const answer:Unit->U32 = func () => return first 20 + second 22 + third 1\n";

const Fixture = struct {
    dir: std.testing.TmpDir,
    source: project.Project,
    checked: checker.CheckedProject,
    fn init(a: std.mem.Allocator) !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        inline for (.{ .{ "prelude.blot", prelude }, .{ "shared.blot", shared }, .{ "left.blot", left }, .{ "right.blot", right }, .{ "main.blot", entry } }) |file| {
            try dir.dir.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
        }
        const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
        defer a.free(path);
        const prelude_path = try dir.dir.realPathFileAlloc(std.testing.io, "prelude.blot", a);
        defer a.free(prelude_path);
        var source = try project.load(a, std.testing.io, path, .{ .prelude_path = prelude_path });
        errdefer source.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
        const checked = try checker.checkProject(a, &source);
        return .{ .dir = dir, .source = source, .checked = checked };
    }
    fn deinit(self: *Fixture, a: std.mem.Allocator) void {
        self.checked.deinit(a);
        self.source.deinit(a);
        self.dir.cleanup();
    }
    fn origins(self: *const Fixture) @import("../check/check.zig").ModuleOrigins {
        return .{ .context = &self.source, .lookup = checker.diagnosticModuleOrigin };
    }
    fn inputs(self: *const Fixture, a: std.mem.Allocator, skipped: ?usize) ![]?parallel_lowering.Input {
        const result = try a.alloc(?parallel_lowering.Input, self.source.units.items.len);
        for (result, self.source.units.items, 0..) |*input, *unit, index| {
            input.* = if (skipped == index) null else .{ .tree = &unit.tree, .checked = &self.checked.module(@intCast(index + 1)).checked };
        }
        return result;
    }
};

test "units lowered on workers equal serial lowering for every worker count" {
    const a = std.testing.allocator;
    var fixture = try Fixture.init(a);
    defer fixture.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), fixture.checked.diagnostics.len);
    const count = fixture.source.units.items.len;
    try std.testing.expect(count >= 4);
    const serial = try a.alloc(core.Module, count);
    defer a.free(serial);
    var lowered: usize = 0;
    defer for (serial[0..lowered]) |*module| module.deinit(a);
    for (serial, fixture.source.units.items, 1..) |*module, *unit, id| {
        module.* = try core_builder.lowerWithOrigins(a, &unit.tree, &fixture.source.symbols, &fixture.checked.module(@intCast(id)).checked, fixture.origins());
        lowered += 1;
    }
    // The skipped unit is one the caller would obtain another way.
    for ([_]?usize{ null, 1 }) |skipped| {
        const inputs = try fixture.inputs(a, skipped);
        defer a.free(inputs);
        for ([_]u8{ 2, 3, 4, 16 }) |workers| {
            var batch = (try parallel_lowering.Batch.runAbove(a, std.testing.io, workers, &fixture.source.symbols, fixture.origins(), inputs, 0)).?;
            defer batch.deinit();
            try std.testing.expect(batch.workers > 1);
            for (serial, 0..) |*expected, index| {
                if (skipped == index) {
                    try std.testing.expect(batch.slots[index].output == null);
                    continue;
                }
                var module = try batch.take(index);
                defer module.deinit(a);
                try std.testing.expect(structural.equal(expected.*, module));
            }
        }
    }
    // One worker, no Io, or too little work leaves lowering to the caller.
    const inputs = try fixture.inputs(a, null);
    defer a.free(inputs);
    try std.testing.expect((try parallel_lowering.Batch.runAbove(a, std.testing.io, 1, &fixture.source.symbols, fixture.origins(), inputs, 0)) == null);
    try std.testing.expect((try parallel_lowering.Batch.runAbove(a, null, 4, &fixture.source.symbols, fixture.origins(), inputs, 0)) == null);
    try std.testing.expect((try parallel_lowering.Batch.run(a, std.testing.io, 4, &fixture.source.symbols, fixture.origins(), inputs)) == null);
}

fn takeSome(a: std.mem.Allocator, fixture: *const Fixture) !void {
    const inputs = try fixture.inputs(a, null);
    defer a.free(inputs);
    var batch = (try parallel_lowering.Batch.runAbove(a, std.testing.io, 3, &fixture.source.symbols, fixture.origins(), inputs, 0)) orelse return error.TestUnexpectedResult;
    defer batch.deinit();
    // Take only a prefix, as a caller stopping at a diagnostic would; the
    // batch releases the rest. Every worker failure still surfaces.
    for (0..2) |index| {
        var module = try batch.take(index);
        module.deinit(a);
    }
    for (batch.slots[2..]) |slot| _ = try slot.output.?;
}
test "lowering workers release every result across allocation failures" {
    const a = std.testing.allocator;
    var fixture = try Fixture.init(a);
    defer fixture.deinit(a);
    try takeSome(a, &fixture);
    try @import("../allocation_failures.zig").checkObservedConcurrentFailures(a, takeSome, .{&fixture});
}
