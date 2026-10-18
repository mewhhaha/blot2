//! Acyclic layout laws over real lowered projects: nominals of other units,
//! prelude and recursive families, Array/List edges, cycle-capable declines,
//! exhausted proofs, allocation failure and retained foreign edits.
const std = @import("std");
const project = @import("../reuse/project.zig");
const checker = @import("../reuse/project_check.zig");
const core = @import("../check/core.zig");
const types = @import("../check/types.zig");
const backend = @import("core_backend.zig");
const identity = @import("runtime_identity.zig");
const archive = @import("backend_checkpoint.zig");
const layout = @import("layout.zig");
const proof = @import("acyclic_layout.zig");
const a = std.testing.allocator;
const io = std.testing.io;

const prelude = "type Maybe a is data = #Nothing | #Some a\n";
const link =
    \\type Vec is data = #Vec { x: F32, y: F32 }
    \\type Link a is data = #End | #Next (Link a, a)
    \\
;
const shapes =
    \\import * as link from "./link"
    \\type Draw is data = #Draw { position: link.Vec, tint: Maybe link.Vec, extra: Array link.Vec, path: List link.Vec, chain: link.Link U32 }
    \\type Tree is data = #Leaf U32 | #Branch (Array Tree)
    \\type Callback is data = #Ready U32 | #Later (Unit -> U32)
    \\entry const answer = fn (value: U32) => value
    \\
;
const owner =
    \\import * as link from "./link"
    \\const grow = fn (count: U32) => do:
    \\  let root: link.Link U32 = #link.End
    \\  for index in 0..count:
    \\    root := #link.Next (self, index)
    \\  return root
    \\entry const run = fn (count: U32) => do:
    \\  let root = grow count
    \\  return count
    \\
;

const Ready = struct {
    units: []core.Module,
    names: identity.Metadata,
    entry: u32,
    fn deinit(self: *Ready) void {
        self.names.deinit(a);
        for (self.units) |*unit| unit.deinit(a);
        a.free(self.units);
    }
    fn module(self: *const Ready, path: []const u8) *const core.Module {
        for (self.units, 1..) |*unit, id| if (std.mem.endsWith(u8, self.names.view().owner(@intCast(id)).?, path)) return unit;
        unreachable;
    }
    fn emit(self: *const Ready, previous: ?*const @import("../reuse/artifact_capture.zig").Capture, checkpoint: ?*const archive.Checkpoint) !backend.Result {
        return backend.compileWithOptions(a, self.units, self.entry, .{ .identity = self.names.view(), .retain_artifacts = true, .previous = previous, .checkpoint = checkpoint });
    }
};

fn write(dir: anytype, name: []const u8, text: []const u8) !void {
    try dir.writeFile(io, .{ .sub_path = name, .data = text });
}

/// Source, syntax, symbols and checking owners die before any assertion.
fn lower(dir: anytype) !Ready {
    const path = try dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(path);
    const prelude_path = try dir.realPathFileAlloc(io, "prelude.blot", a);
    defer a.free(prelude_path);
    var loaded = try project.load(a, io, path, .{ .prelude_path = prelude_path });
    defer loaded.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    var checked = try checker.checkProject(a, &loaded);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const units = try a.alloc(core.Module, loaded.units.items.len);
    var initialized: usize = 0;
    var transferred = false;
    defer if (!transferred) {
        for (units[0..initialized]) |*unit| unit.deinit(a);
        a.free(units);
    };
    for (units, 1..) |*unit, id| {
        unit.* = try core.lower(a, &loaded.unit(@intCast(id)).tree, &loaded.symbols, &checked.module(@intCast(id)).checked);
        initialized += 1;
        unit.unit = @intCast(id);
        try std.testing.expectEqual(@as(usize, 0), unit.diagnostics.len);
    }
    const owners = try a.alloc(identity.Owner, units.len);
    defer a.free(owners);
    for (owners, 1..) |*item, id| item.* = .{ .unit = @intCast(id), .path = loaded.filename(@intCast(id)) };
    const names = try identity.Metadata.capture(a, &loaded.symbols, owners, owners.len);
    transferred = true;
    return .{ .units = units, .names = names, .entry = loaded.entry };
}

fn nominal(store: *layout.Store, module: *const core.Module, name: []const u8, arguments: []const layout.Id) !layout.Id {
    for (module.nominals) |item| {
        if (item.identity.unit != module.unit or !std.mem.eql(u8, module.name(item.diagnostic_name), name)) continue;
        return store.intern(.nominal, item.identity.unit, item.identity.decl, arguments);
    }
    return error.TestUnexpectedResult;
}

const Shapes = struct {
    draw: layout.Id,
    tint: layout.Id,
    chain: layout.Id,
    tree: layout.Id,
    callback: layout.Id,
    vec: layout.Id,
    fn init(store: *layout.Store, ready: *const Ready) !Shapes {
        const vec = try nominal(store, ready.module("link.blot"), "Vec", &.{});
        return .{
            .draw = try nominal(store, ready.module("main.blot"), "Draw", &.{}),
            .tint = try nominal(store, ready.module("prelude.blot"), "Maybe", &.{vec}),
            .chain = try nominal(store, ready.module("link.blot"), "Link", &.{types.u32_type}),
            .tree = try nominal(store, ready.module("main.blot"), "Tree", &.{}),
            .callback = try nominal(store, ready.module("main.blot"), "Callback", &.{}),
            .vec = vec,
        };
    }
};

test "acyclic proofs admit foreign, prelude, recursive and collection layouts and decline cycle-capable ones" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, "prelude.blot", prelude);
    try write(tmp.dir, "link.blot", link);
    try write(tmp.dir, "main.blot", shapes);
    var ready = try lower(tmp.dir);
    defer ready.deinit();
    var store = try layout.Store.init(a);
    defer store.deinit();
    const shape = try Shapes.init(&store, &ready);
    // Nominals of another unit, a prelude family over a foreign argument,
    // a foreign recursive family, a recursive family through Array edges and
    // a record whose Array and List fields carry proven elements.
    for ([_]layout.Id{ shape.vec, shape.tint, shape.chain, shape.tree, shape.draw }) |ty| try std.testing.expect(try proof.proven(&store, ready.units, ty));
    try std.testing.expect(try proof.proven(&store, ready.units, try store.intern(.list, shape.draw, 0, &.{})));
    try std.testing.expect(try proof.proven(&store, ready.units, try store.intern(.product, 0, 0, &.{ shape.tint, try store.intern(.array, shape.chain, 0, &.{}) })));
    // An unused closure variant makes the whole family cycle-capable.
    try std.testing.expect(!try proof.proven(&store, ready.units, shape.callback));
    try std.testing.expect(!try proof.proven(&store, ready.units, try store.intern(.array, shape.callback, 0, &.{})));
    const function = try store.intern(.function, types.u32_type, types.u32_type, &.{});
    const demand = try store.intern(.demand, types.u32_type, 0, &.{});
    const state = try store.intern(.nominal, types.builtin_state_read.unit, types.builtin_state_read.decl, &.{types.u32_type});
    const cursor = try store.intern(.cursor, try store.intern(.list, shape.vec, 0, &.{}), 0, &.{});
    for ([_]layout.Id{ function, demand, state, cursor }) |declined| {
        try std.testing.expect(!try proof.proven(&store, ready.units, declined));
        try std.testing.expect(!try proof.proven(&store, ready.units, try store.intern(.list, declined, 0, &.{})));
        try std.testing.expect(!try proof.proven(&store, ready.units, try store.intern(.product, 0, 0, &.{ shape.vec, declined })));
        try std.testing.expect(!try proof.proven(&store, ready.units, try store.intern(.nominal, ready.module("prelude.blot").unit, (try nominalIdentity(ready.module("prelude.blot"), "Maybe")).decl, &.{declined})));
    }
    // Exhausted depth or budget declines instead of guessing.
    var active: [2]layout.Id = undefined;
    var budget: usize = proof.default_budget;
    try std.testing.expect(!try proof.within(&store, ready.units, shape.draw, &active, 0, &budget));
    var deep: [proof.depth_limit]layout.Id = undefined;
    budget = 3;
    try std.testing.expect(!try proof.within(&store, ready.units, shape.draw, &deep, 0, &budget));
}

fn nominalIdentity(module: *const core.Module, name: []const u8) !types.NominalIdentity {
    for (module.nominals) |item| if (item.identity.unit == module.unit and std.mem.eql(u8, module.name(item.diagnostic_name), name)) return item.identity;
    return error.TestUnexpectedResult;
}

fn proofScenario(allocator: std.mem.Allocator, ready: *const Ready) !void {
    var store = try layout.Store.init(allocator);
    defer store.deinit();
    const shape = try Shapes.init(&store, ready);
    try std.testing.expect(try proof.proven(&store, ready.units, shape.draw));
    try std.testing.expect(!try proof.proven(&store, ready.units, shape.callback));
}

test "acyclic proofs own every allocation failure while interning foreign payloads" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, "prelude.blot", prelude);
    try write(tmp.dir, "link.blot", link);
    try write(tmp.dir, "main.blot", shapes);
    var ready = try lower(tmp.dir);
    defer ready.deinit();
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, proofScenario, .{&ready});
}

fn claims(result: *const backend.Result) usize {
    const emission = &result.capture.?.emission;
    var count: usize = 0;
    for (emission.instructions) |instruction| if (instruction.op == .call and instruction.operand.value == emission.arena.?.mark_acyclic) {
        count += 1;
    };
    return count;
}

test "a foreign closure constructor edit re-emits the owner without its acyclic claims" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, "prelude.blot", prelude);
    try write(tmp.dir, "link.blot", link);
    try write(tmp.dir, "main.blot", owner);
    var ready = try lower(tmp.dir);
    defer ready.deinit();
    var first = try ready.emit(null, null);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    // Only the owner constructs foreign Link cells.
    try std.testing.expect(claims(&first) != 0);
    var retained = try ready.emit(&first.capture.?, null);
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, retained.bytes);
    const compiler: [32]u8 = @splat(41);
    const bytes = try archive.encode(a, compiler, &first.capture.?);
    defer a.free(bytes);
    var checkpoint = try archive.decode(a, compiler, bytes);
    defer checkpoint.deinit();
    // The owner is unchanged; only the foreign family gains a closure variant.
    try write(tmp.dir, "link.blot",
        \\type Vec is data = #Vec { x: F32, y: F32 }
        \\type Link a is data = #End | #Next (Link a, a) | #Later (Unit -> a)
        \\
    );
    var changed_ready = try lower(tmp.dir);
    defer changed_ready.deinit();
    var changed = try changed_ready.emit(&first.capture.?, null);
    defer changed.deinit(a);
    var fresh = try changed_ready.emit(null, null);
    defer fresh.deinit(a);
    var portable = try changed_ready.emit(null, &checkpoint);
    defer portable.deinit(a);
    try std.testing.expect(fresh.diagnostic == null);
    try std.testing.expectEqualSlices(u8, fresh.bytes, changed.bytes);
    try std.testing.expectEqualSlices(u8, fresh.bytes, portable.bytes);
    try std.testing.expectEqual(@as(usize, 0), claims(&fresh));
    try std.testing.expectEqual(@as(usize, 0), claims(&changed));
    try std.testing.expectEqual(@as(usize, 0), claims(&portable));
    // Restoring the definition restores the claims.
    try write(tmp.dir, "link.blot", link);
    var restored_ready = try lower(tmp.dir);
    defer restored_ready.deinit();
    var restored = try restored_ready.emit(&changed.capture.?, null);
    defer restored.deinit(a);
    try std.testing.expectEqualSlices(u8, first.bytes, restored.bytes);
    try std.testing.expectEqual(claims(&first), claims(&restored));
}
