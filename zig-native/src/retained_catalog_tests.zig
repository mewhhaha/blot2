//! Catalog admission controls built from real source and an owned backend run.
//! Source, syntax, symbols and checking owners die before each backend assertion.
const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const core = @import("core.zig");
const closure = @import("dependency_closure.zig");
const format = @import("dependency_format.zig");
const dependency = @import("frozen_dependency.zig");
const partial = @import("partial_dependency.zig");
const capture = @import("artifact_capture.zig");
const fragment = @import("artifact_fragment.zig");
const artifacts = @import("code_artifacts.zig");
const types = @import("types.zig");
const a = std.testing.allocator;
const key: format.Key = .{ .compiler = @splat(17), .settings = @splat(18), .source = @splat(19), .dependencies = @splat(20) };
const prelude_source =
    \\const U32.add = fn left => fn right => @u32.add left right
    \\const U32.sub = fn left => fn right => @u32.sub left right
;
const helper_source = "const calculate = fn (value: U32) => U32.add value 3\n";
const initial_source =
    \\import * as helper from "./helper"
    \\entry const answer: U32 -> U32 = fn value => helper.calculate value
    \\entry const schema = 8
;
const edited_source =
    \\import * as helper from "./helper"
    \\entry const answer: U32 -> U32 = fn value => helper.calculate value
    \\entry const schema = 9
;

const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    prelude_path: [:0]u8,
    encoded: []u8,

    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        inline for (.{ .{ "prelude.blot", prelude_source }, .{ "helper.blot", helper_source }, .{ "main.blot", initial_source } }) |file|
            try dir.dir.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
        const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
        errdefer a.free(path);
        const prelude_path = try dir.dir.realPathFileAlloc(std.testing.io, "prelude.blot", a);
        errdefer a.free(prelude_path);
        const encoded = try freeze(path, prelude_path);
        return .{ .dir = dir, .path = path, .prelude_path = prelude_path, .encoded = encoded };
    }

    fn removeSources(self: *Fixture) !void {
        inline for (.{ "prelude.blot", "helper.blot", "main.blot" }) |path|
            try self.dir.dir.deleteFile(std.testing.io, path);
    }

    fn deinit(self: *Fixture) void {
        a.free(self.encoded);
        a.free(self.path);
        a.free(self.prelude_path);
        self.dir.cleanup();
    }
};

fn freeze(path: []const u8, prelude_path: []const u8) ![]u8 {
    var loaded = try project.load(a, std.testing.io, path, .{ .prelude_path = prelude_path });
    defer loaded.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    var checked = try checker.checkProject(a, &loaded);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var frozen = try closure.freeze(a, &loaded, &checked);
    defer format.deinit(a, &frozen);
    try closure.validate(a, &frozen);
    return format.encode(a, key, frozen);
}

const Revision = struct {
    seed: dependency.FrozenDependency,
    prepared: partial.Prepared,

    fn init(fixture: *const Fixture) !Revision {
        // Distinct wire decodes make every cached Core mutation below private
        // to this revision. They cannot mutate the previous artifact's pins.
        var seed = try format.decode(dependency.FrozenDependency, a, fixture.encoded, key);
        errdefer format.deinit(a, &seed);
        try closure.validate(a, &seed);
        const result = try partial.prepare(a, std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path }, &seed);
        switch (result) {
            .ready => |prepared| return .{ .seed = seed, .prepared = prepared },
            .rejected => |rejected| {
                var owned = rejected;
                defer owned.deinit(a);
                if (owned.result.diagnostic) |issue| std.debug.print("catalog preparation {s}: {s}\n", .{ issue.code, issue.message });
                return error.TestUnexpectedResult;
            },
        }
    }

    fn deinit(self: *Revision) void {
        self.prepared.deinit(a);
        format.deinit(a, &self.seed);
    }
};

fn assertShape(old: *const Revision, current: *const Revision) !void {
    try std.testing.expectEqual(@as(usize, 3), old.prepared.units.len);
    try std.testing.expectEqual(@as(usize, 2), old.prepared.cached);
    try std.testing.expectEqual(@as(u32, 3), old.prepared.entry);
    try std.testing.expectEqual(old.prepared.cached, current.prepared.cached);
    try std.testing.expect(old.prepared.units[0].nodes.ptr != current.prepared.units[0].nodes.ptr);
    for ([_]*const Revision{ old, current }) |revision| {
        const entry = &revision.prepared.units[revision.prepared.entry - 1];
        try std.testing.expectEqual(@as(usize, 2), entry.associated.len);
        for (entry.associated) |method| {
            try std.testing.expectEqual(@as(u32, 0), method.identity.unit);
            try std.testing.expectEqual(types.u32_type, method.identity.decl);
            try std.testing.expect(method.target.unit > 0 and method.target.unit <= revision.prepared.cached);
            try std.testing.expect(revision.prepared.units[method.target.unit - 1].body(method.target.binding) != null);
        }
    }
}

fn expectDisabled(previous: *const capture.Capture, prepared: *const partial.Prepared) !void {
    try std.testing.expect(!previous.selectionStable(prepared.units, prepared.identity.view(), prepared.cached));
    var state = try fragment.State.init(a, previous, prepared.units, prepared.identity.view(), prepared.cached);
    defer state.deinit();
    try std.testing.expect(!state.enabled);
}

test "retained catalog admits unchanged imported builtin methods after source and backend owners die" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var old = try Revision.init(&fixture);
    defer old.deinit();
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = edited_source });
    var current = try Revision.init(&fixture);
    defer current.deinit();
    try assertShape(&old, &current);
    try fixture.removeSources();

    var first = try old.prepared.emitWithOptions(a, .{ .retain_artifacts = true, .cached_units = old.prepared.cached });
    defer first.deinit(a);
    try std.testing.expect(first.result.compiled.diagnostic == null);
    const previous = &first.result.compiled.capture.?;
    const original_core = artifacts.stamp(old.prepared.units);
    const original_emission = artifacts.stamp(previous.emission.instructions);
    try std.testing.expect(previous.selectionStable(current.prepared.units, current.prepared.identity.view(), current.prepared.cached));

    var state = try fragment.State.init(a, previous, current.prepared.units, current.prepared.identity.view(), current.prepared.cached);
    defer state.deinit();
    try std.testing.expect(state.enabled);
    for (state.importer.stable[0..current.prepared.cached]) |stable| try std.testing.expect(stable);

    var fresh = try current.prepared.emit(a);
    defer fresh.deinit(a);
    var retained = try current.prepared.emitWithOptions(a, .{ .previous = previous, .cached_units = current.prepared.cached });
    defer retained.deinit(a);
    try std.testing.expect(fresh.result.compiled.diagnostic == null and retained.result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, fresh.result.compiled.bytes, retained.result.compiled.bytes);
    try std.testing.expect(!std.mem.eql(u8, first.result.compiled.bytes, retained.result.compiled.bytes));
    try std.testing.expect(retained.result.compiled.reuse.reused_named > 0);
    try std.testing.expect(retained.result.compiled.reuse.refinement_regions < first.result.compiled.reuse.refinement_regions);
    try std.testing.expectEqualSlices(u8, &original_core, &artifacts.stamp(old.prepared.units));
    try std.testing.expectEqualSlices(u8, &original_emission, &artifacts.stamp(previous.emission.instructions));
}

test "retained catalog rejects same length retarget member spelling operator order and fresh implementation changes" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var old = try Revision.init(&fixture);
    defer old.deinit();
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = edited_source });
    var current = try Revision.init(&fixture);
    defer current.deinit();
    try assertShape(&old, &current);
    try fixture.removeSources();
    var first = try old.prepared.emitWithOptions(a, .{ .retain_artifacts = true, .cached_units = old.prepared.cached });
    defer first.deinit(a);
    try std.testing.expect(first.result.compiled.diagnostic == null);
    const previous = &first.result.compiled.capture.?;
    const original_core = artifacts.stamp(old.prepared.units);
    const original_emission = artifacts.stamp(previous.emission.instructions);
    const entry = &current.prepared.units[current.prepared.entry - 1];
    const original = entry.associated[0];

    // A different unchanged implementation has the same callable signature.
    try std.testing.expect(original.target.binding != entry.associated[1].target.binding);
    entry.associated[0].target = entry.associated[1].target;
    try expectDisabled(previous, &current.prepared);
    entry.associated[0] = original;

    entry.associated[0].member = entry.associated[1].member;
    try expectDisabled(previous, &current.prepared);
    entry.associated[0] = original;

    entry.associated[0].operator = if (original.operator == .add) .sub else .add;
    try expectDisabled(previous, &current.prepared);
    entry.associated[0] = original;

    std.mem.swap(core.Associated, &entry.associated[0], &entry.associated[1]);
    try expectDisabled(previous, &current.prepared);
    std.mem.swap(core.Associated, &entry.associated[0], &entry.associated[1]);

    entry.associated[0].identity.decl = types.f32_type;
    try expectDisabled(previous, &current.prepared);
    entry.associated[0] = original;

    const local_binding = blk: {
        for (entry.bodies) |body| if (body.binding != 0 and body.is_function) break :blk body.binding;
        return error.TestUnexpectedResult;
    };
    entry.associated[0].target.unit = 0;
    entry.associated[0].target.binding = local_binding;
    try expectDisabled(previous, &current.prepared);
    entry.associated[0] = original;

    entry.associated[0].target.unit = current.prepared.entry;
    entry.associated[0].target.binding = local_binding;
    try expectDisabled(previous, &current.prepared);
    entry.associated[0] = original;

    // Preserve the numeric Symbol while changing its canonical spelling.
    const spelling = current.prepared.identity.view().symbol(original.member).?;
    try std.testing.expect(spelling.len > 0);
    const offset = @intFromPtr(spelling.ptr) - @intFromPtr(current.prepared.identity.bytes.ptr);
    const saved_byte = current.prepared.identity.bytes[offset];
    current.prepared.identity.bytes[offset] = 'z';
    try expectDisabled(previous, &current.prepared);
    current.prepared.identity.bytes[offset] = saved_byte;

    try std.testing.expect(previous.selectionStable(current.prepared.units, current.prepared.identity.view(), current.prepared.cached));
    try std.testing.expectEqualSlices(u8, &original_core, &artifacts.stamp(old.prepared.units));
    try std.testing.expectEqualSlices(u8, &original_emission, &artifacts.stamp(previous.emission.instructions));
}

test "retained catalog identical target IDs cannot admit a changed cached producer body" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var old = try Revision.init(&fixture);
    defer old.deinit();
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = edited_source });
    var current = try Revision.init(&fixture);
    defer current.deinit();
    try assertShape(&old, &current);
    try fixture.removeSources();
    var first = try old.prepared.emitWithOptions(a, .{ .retain_artifacts = true, .cached_units = old.prepared.cached });
    defer first.deinit(a);
    try std.testing.expect(first.result.compiled.diagnostic == null);
    const previous = &first.result.compiled.capture.?;
    const old_core = artifacts.stamp(old.prepared.units);
    const before = artifacts.stamp(current.prepared.units);
    const entry = &current.prepared.units[current.prepared.entry - 1];
    const producer_id = entry.associated[0].target.unit;
    const producer = &current.prepared.units[producer_id - 1];
    var changed = false;
    for (producer.nodes) |*node| if (node.tag == .scalar and (node.op == .add or node.op == .sub)) {
        node.op = if (node.op == .add) .sub else .add;
        changed = true;
        break;
    };
    try std.testing.expect(changed);
    try std.testing.expect(!std.mem.eql(u8, &before, &artifacts.stamp(current.prepared.units)));
    // Catalog projections stay equal. The exact immutable producer check must
    // still turn off replay before any request matching or refinement occurs.
    try std.testing.expect(previous.selectionStable(current.prepared.units, current.prepared.identity.view(), current.prepared.cached));
    var state = try fragment.State.init(a, previous, current.prepared.units, current.prepared.identity.view(), current.prepared.cached);
    defer state.deinit();
    try std.testing.expect(!state.importer.stable[producer_id - 1]);
    try std.testing.expect(!state.enabled);
    try std.testing.expectEqualSlices(u8, &old_core, &artifacts.stamp(old.prepared.units));
}
