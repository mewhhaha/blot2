//! A catalog member imported through another module (here F32.lerp, which
//! `vec`'s catalog re-exports) carries its producer's capability facts whether
//! that producer was checked live (population) or from its frozen interface
//! (every later edit), so `mid` publishes the same interface and recipes on
//! both and the first edit after population cuts off its importer.
const std = @import("std");
const retained = @import("retained_revision.zig");
const project = @import("project.zig");
const dependency = @import("frozen_dependency.zig");
const capability_contracts = @import("../check/capability_contracts.zig");
const capability_flow = @import("../check/capability_flow.zig");
const a = std.testing.allocator;
const io = std.testing.io;

const prelude =
    \\type Box a is data = #Box a
    \\const Box.map = func transform => return func box => return case box of
    \\  #Box value => #Box (transform value)
    \\const F32.lerp = func left => return func right => return func weight => return @f32.add left (@f32.mul (@f32.sub right left) weight)
    \\const apply = func function => return func value => return function value
;
const vec =
    \\type P is data = #P { x: F32 }
    \\const P.mix = func (a: P) => return func (b: P) => return func (t: F32) => return #P { x: F32.lerp a.x b.x t }
;
const mid =
    \\import { P } from "./vec"
    \\const blend = func (a: F32) => return func (b: F32) => return func (t: F32) => return F32.lerp a b t
    \\const shade: U32 = 1
;
const main =
    \\import * as mid from "./mid"
    \\entry const answer: U32 = mid.shade
    \\entry const mixed = func (a: F32) : F32 => return mid.blend a 1.0 0.5
;

const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    prelude: [:0]u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        for ([_][]const u8{ "prelude.blot", "vec.blot", "mid.blot", "main.blot" }, [_][]const u8{ prelude, vec, mid, main }) |name, text| {
            try dir.dir.writeFile(io, .{ .sub_path = name, .data = text });
        }
        const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
        errdefer a.free(path);
        return .{ .dir = dir, .path = path, .prelude = try dir.dir.realPathFileAlloc(io, "prelude.blot", a) };
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        a.free(self.prelude);
        self.dir.cleanup();
    }
    fn options(self: *const Fixture) project.Options {
        return .{ .prelude_path = self.prelude };
    }
};

/// `mid`'s published capability facts: each binding's flow and parameters,
/// and its recipe collection.
const Published = struct {
    flows: []capability_flow.Contract,
    parameters: []capability_flow.Parameters,
    nodes: []capability_contracts.Term,
    words: []u32,
    bindings: []capability_contracts.Binding,
    blend: capability_flow.Contract,
    fn capture(seed: *const dependency.FrozenDependency) !Published {
        const module = for (seed.modules) |*module| {
            if (std.mem.endsWith(u8, module.identity.normalized_path, "mid.blot")) break module;
        } else return error.TestMissingModule;
        const interface = &module.interface;
        var blend: ?capability_flow.Contract = null;
        for (interface.bindings) |binding| {
            if (binding.name != 0 and std.mem.eql(u8, seed.symbols[binding.name].text, "blend")) blend = binding.capability_flow;
        }
        const flows = try a.alloc(capability_flow.Contract, interface.bindings.len);
        errdefer a.free(flows);
        const parameters = try a.alloc(capability_flow.Parameters, interface.bindings.len);
        errdefer a.free(parameters);
        for (interface.bindings, flows, parameters) |binding, *flow, *parameter| {
            flow.* = binding.capability_flow;
            parameter.* = binding.capability_parameters;
        }
        const recipes = interface.capability_contracts;
        const nodes = try a.dupe(capability_contracts.Term, recipes.nodes);
        errdefer a.free(nodes);
        const words = try a.dupe(u32, recipes.words);
        errdefer a.free(words);
        return .{ .flows = flows, .parameters = parameters, .nodes = nodes, .words = words, .bindings = try a.dupe(capability_contracts.Binding, recipes.bindings), .blend = blend orelse return error.TestMissingBinding };
    }
    fn deinit(self: *Published) void {
        a.free(self.flows);
        a.free(self.parameters);
        a.free(self.nodes);
        a.free(self.words);
        a.free(self.bindings);
    }
    fn expectEqual(expected: *const Published, actual: *const Published) !void {
        try std.testing.expectEqualSlices(capability_flow.Contract, expected.flows, actual.flows);
        try std.testing.expectEqualDeep(expected.parameters, actual.parameters);
        try std.testing.expectEqualDeep(expected.nodes, actual.nodes);
        try std.testing.expectEqualSlices(u32, expected.words, actual.words);
        try std.testing.expectEqualDeep(expected.bindings, actual.bindings);
    }
};

fn revise(session: *retained.Session, fixture: *const Fixture) ![]u8 {
    var result = try session.revise(io, fixture.path, null, fixture.options());
    defer result.deinit(a);
    try std.testing.expect(result.result.diagnostic == null and result.result.compiled.diagnostic == null);
    return a.dupe(u8, result.result.compiled.bytes);
}

test "a member imported through another catalog publishes the same recipes live and from frozen interfaces" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, fixture.options());
    defer session.deinit();
    const populated = try revise(&session, &fixture);
    defer a.free(populated);
    // Population checks `mid` against live dependencies. `blend` calls the
    // re-exported F32.lerp and so receives its no-store recipe.
    var live = try Published.capture(&session.seed);
    defer live.deinit();
    try std.testing.expectEqual(capability_flow.Contract.input_shape, live.blend);

    // A scalar edit checks `mid` again, against frozen `vec` and prelude.
    try fixture.dir.dir.writeFile(io, .{ .sub_path = "mid.blot", .data = "import { P } from \"./vec\"\nconst blend = func (a: F32) => return func (b: F32) => return func (t: F32) => return F32.lerp a b t\nconst shade: U32 = 2\n" });
    const edited = try revise(&session, &fixture);
    defer a.free(edited);
    var frozen = try Published.capture(&session.seed);
    defer frozen.deinit();
    try live.expectEqual(&frozen);
    // Its interface is unchanged, so `main` is cut off: only `mid` is checked.
    try std.testing.expectEqual(@as(usize, 1), session.last.fallback.validated_modules);

    // The retained output equals a fresh build of the edited project.
    var fresh_session = try retained.Session.initEmpty(a, fixture.options());
    defer fresh_session.deinit();
    const fresh = try revise(&fresh_session, &fixture);
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, edited);
    var cold = try Published.capture(&fresh_session.seed);
    defer cold.deinit();
    try live.expectEqual(&cold);
}
