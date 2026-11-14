const std = @import("std");
const project = @import("project.zig");
const partial = @import("partial_dependency.zig");
const dependency = @import("frozen_dependency.zig");
const a = std.testing.allocator;
const io = std.testing.io;

const entry = "import {read} from \"./left\"\nimport {fixed} from \"./right\"\nentry const answer: U32 = @u32.add (read ()) fixed\n";
const original = "const value: U32 = 41\n";
const edited = "const value: U32 = @u32.add 40 3\n";
const left = "import {value} from \"./changed\"\nconst read: Unit -> U32 = func () => return value\n";
const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        for ([_][]const u8{ "main.blot", "left.blot", "changed.blot", "right.blot" }, [_][]const u8{ entry, left, original, "const fixed: U32 = 1\n" }) |name, text| {
            try dir.dir.writeFile(io, .{ .sub_path = name, .data = text });
        }
        return .{ .dir = dir, .path = try dir.dir.realPathFileAlloc(io, "main.blot", a) };
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        self.dir.cleanup();
    }
    fn write(self: *Fixture, name: []const u8, text: []const u8) !void {
        try self.dir.dir.writeFile(io, .{ .sub_path = name, .data = text });
    }
};
fn fresh(fixture: *Fixture) !partial.Result {
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    const empty: dependency.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
    var prepared = try partial.prepareProject(a, &source, fixture.path, null, &empty);
    switch (prepared) {
        .rejected => |result| return result,
        .ready => |*ready| {
            defer ready.deinit(a);
            return ready.emit(a);
        },
    }
}
fn equal(actual: *const partial.Result, expected: *const partial.Result) !void {
    try @import("dependency_consumer.zig").expectSamePublished(expected.result.diagnostic, actual.result.diagnostic);
    try std.testing.expectEqualDeep(expected.result.compiled.diagnostic, actual.result.compiled.diagnostic);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, actual.result.compiled.bytes);
    try std.testing.expectEqual(expected.result.compiled.constant_steps, actual.result.compiled.constant_steps);
}
fn preparedStamp(value: partial.Prepared) [32]u8 {
    const structural = @import("../structural.zig");
    const cache_types = @import("body_check_cache.zig");
    var hash = std.crypto.hash.Blake3.init(.{});
    inline for (@typeInfo(partial.Prepared).@"struct".field_names) |name| {
        // Process-local authority has no structural/serialized identity. Its
        // underlying Core and spelling tables are still hashed below.
        if (comptime std.mem.eql(u8, name, "source_completion")) continue;
        if (comptime !std.mem.eql(u8, name, "body_caches")) {
            structural.hash(&hash, @field(value, name));
        } else {
            structural.hash(&hash, value.body_caches.len);
            for (value.body_caches) |cache| {
                structural.hash(&hash, .{ cache.minimum_nodes, cache.bodies.items.len, cache.bodies.capacity, cache.index.count(), cache.index.capacity() });
                for (cache.bodies.items) |lease| {
                    structural.hash(&hash, .{ lease.index, cache.index.get(lease.body().name) });
                    inline for (@typeInfo(cache_types.Chunk).@"struct".field_names) |field| {
                        if (comptime !std.mem.eql(u8, field, "allocator") and !std.mem.eql(u8, field, "bodies")) structural.hash(&hash, @field(lease.owner.*, field));
                    }
                    structural.hash(&hash, lease.owner.bodies.len);
                    for (lease.owner.bodies) |body| {
                        structural.hash(&hash, body.owner == lease.owner);
                        inline for (@typeInfo(cache_types.Body).@"struct".field_names) |field| {
                            if (comptime std.mem.eql(u8, field, "loops")) {
                                structural.hash(&hash, body.loops != null);
                                if (body.loops) |loops| structural.hash(&hash, loops.*);
                            } else if (comptime std.mem.eql(u8, field, "auxiliary")) {
                                structural.hash(&hash, body.auxiliary != null);
                                if (body.auxiliary) |auxiliary| structural.hash(&hash, auxiliary.*);
                            } else if (comptime !std.mem.eql(u8, field, "owner")) structural.hash(&hash, @field(body, field));
                        }
                    }
                }
            }
        }
    }
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}

const opaque_storage_original = "type Token is opaque = U32\nprivate const offset = 2\nconst make: U32 -> Token = func value => return $Token (@u32.add value offset)\nconst read: Token -> U32 = func ($Token value) => return value\n";
const opaque_storage_float = "type Token is opaque = F32\nprivate const offset = 2\nconst make: U32 -> Token = func value => return $Token (@u32.to_f32 (@u32.add value offset))\nconst read: Token -> U32 = func ($Token value) => return @f32.to_u32 value\n";
const opaque_storage_reference = "type Token is opaque = Array U32\nprivate const offset = 2\nconst make: U32 -> Token = func value => return $Token #[@u32.add value offset]\nconst read: Token -> U32 = func ($Token value) => return value[0]\n";
const opaque_storage_record = "type Token is opaque = {word: U32}\nprivate const offset = 2\nconst make: U32 -> Token = func value => return $Token {word: @u32.add value offset}\nconst read: Token -> U32 = func ($Token value) => return value.word\n";
const opaque_storage_renamed = "type Token is opaque = {renamed: U32}\nprivate const offset = 2\nconst make: U32 -> Token = func value => return $Token {renamed: @u32.add value offset}\nconst read: Token -> U32 = func ($Token value) => return value.renamed\n";
const opaque_storage_alpha = "type Token is opaque = U32\nprivate const offset = 2\nconst make: U32 -> Token = func argument => return $Token (@u32.add argument offset)\nconst read: Token -> U32 = func ($Token value) => return value\n";

test "opaque semantic comparison preserves identities visibility contracts and unknown-storage declines" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("changed.blot", opaque_storage_original);
    try fixture.write("left.blot", "import {make, read} from \"./changed\"\nconst bridge = func (value: U32) => return read (make value)\n");
    try fixture.write("main.blot", "import {bridge} from \"./left\"\nentry const answer = func (value: U32) => return bridge value\n");
    var before = try producerInterface(&fixture);
    defer @import("dependency_snapshot.zig").deinit(a, &before);
    const same = @import("entry_frontend_cutoff.zig").interfaceEqual;
    const nominals = try a.dupe(@import("principal_interface.zig").Nominal, before.nominals);
    defer a.free(nominals);
    var after = before;
    after.nominals = nominals;
    const index = for (nominals, 0..) |nominal, index| {
        if (nominal.is_opaque and !nominal.private) break index;
    } else return error.MissingOpaque;
    const original_nominal = nominals[index];
    nominals[index].storage = .{ .kind = .f32 };
    try std.testing.expect(same(before, after, 1 << 16, 8));
    nominals[index].identity.decl +%= 1;
    try std.testing.expect(!same(before, after, 1 << 16, 8));
    nominals[index] = original_nominal;
    nominals[index].private = true;
    try std.testing.expect(!same(before, after, 1 << 16, 8));
    nominals[index] = original_nominal;
    nominals[index].closed_storage = !original_nominal.closed_storage;
    try std.testing.expect(!same(before, after, 1 << 16, 8));
    nominals[index] = original_nominal;
    nominals[index].storage = .{};
    try std.testing.expect(!same(before, after, 1 << 16, 8));
    nominals[index] = original_nominal;
    const constructors = try a.dupe(@import("principal_interface.zig").Constructor, before.constructors);
    defer a.free(constructors);
    after.constructors = constructors;
    const constructor_index = for (constructors, 0..) |constructor, ordinal| {
        if (constructor.private and constructor.nominal == index) break ordinal;
    } else return error.MissingOpaqueConstructor;
    const original_constructor = constructors[constructor_index];
    constructors[constructor_index].identity.decl +%= 1;
    try std.testing.expect(same(before, after, 1 << 16, 8));
    constructors[constructor_index].identity.unit +%= 1;
    try std.testing.expect(!same(before, after, 1 << 16, 8));
    constructors[constructor_index] = original_constructor;
    constructors[constructor_index].private = false;
    try std.testing.expect(!same(before, after, 1 << 16, 8));
    constructors[constructor_index] = original_constructor;
    constructors[constructor_index].tag +%= 1;
    try std.testing.expect(!same(before, after, 1 << 16, 8));
}

fn reverseDependencyUnits(value: *dependency.FrozenDependency) !void {
    const ids = try a.alloc(u32, value.modules.len);
    defer a.free(ids);
    for (ids, 0..) |*id, index| id.* = @intCast(ids.len - index);
    std.mem.reverse(@import("frozen_dependency.zig").Module, value.modules);
    const relink = @import("dependency_relink.zig");
    for (value.modules) |*module| {
        try relink.moduleUnits(&module.core, ids);
        try relink.interfaceUnits(&module.interface, ids);
        for (module.exports) |*exported| if (exported.target.unit != 0) {
            exported.target.unit = ids[exported.target.unit - 1];
        };
        for (module.fixities) |*fixity| if (fixity.producer.unit != 0) {
            fixity.producer.unit = ids[fixity.producer.unit - 1];
        };
        for (module.imports) |*unit| unit.* = ids[unit.* - 1];
        for (module.source_imports) |*request| request.target = ids[request.target - 1];
    }
}
test "inert principal suffix namespace rejects changed spellings producers and malformed views" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    const identity = @import("runtime_identity.zig");
    const owners = try a.alloc(identity.Owner, source.units.items.len);
    defer a.free(owners);
    for (owners, 1..) |*owner, unit| owner.* = .{ .unit = @intCast(unit), .path = source.filename(@intCast(unit)) };
    var names = try identity.Metadata.capture(a, &source.symbols, owners, owners.len);
    defer names.deinit(a);
    const matches = @import("entry_frontend_cutoff.zig").namespaceMatches;
    try std.testing.expect(matches(&source, names.view()));
    _ = try source.symbols.intern(a, "future_unused_local");
    try std.testing.expect(matches(&source, names.view()));
    const first = names.symbols[1];
    names.symbols[1] = names.symbols[2];
    try std.testing.expect(!matches(&source, names.view()));
    names.symbols[1] = first;
    names.symbols[1].start = @intCast(names.bytes.len + 1);
    try std.testing.expect(!matches(&source, names.view()));
    names.symbols[1] = first;
    const owner = names.owners[0];
    names.owners[0] = names.owners[1];
    try std.testing.expect(!matches(&source, names.view()));
    names.owners[0] = owner;
    var empty = names.view();
    empty.symbols = &.{};
    try std.testing.expect(!matches(&source, empty));
}

test "principal reference bounds preserve quantified row project dependencies" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("changed.blot",
        \\const apply: forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e} = func pair => return (@product.get pair 0) (@product.get pair 1)
        \\const both: (forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e}) -> U32 -> (U32, F32) = func apply => return func value => return (apply ((func item => return item), value), apply ((func item => return item), @u32.to_f32 value))
        \\const foreign_apply: ((forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e}), (U32 -> U32 ! {Foreign})) -> U32 ! {Foreign} = func pair => return (@product.get pair 0) (@product.get pair 1, 42)
    );
    try fixture.write("main.blot",
        \\import {apply, both, foreign_apply} from "./changed"
        \\entry const whole = func (value: U32) => return @product.get (both apply value) 0
        \\entry const fraction = func (value: U32) => return @product.get (both apply value) 1
        \\entry const host = func (callback: U32 -> U32 ! {Foreign}) => return foreign_apply (apply, callback)
    );
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    var checked = try @import("project_check.zig").checkProject(a, &source);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try quantifiedRowProjectFreeze(a, &source, &checked);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, quantifiedRowProjectFreeze, .{ &source, &checked });
}

fn quantifiedRowProjectFreeze(allocator: std.mem.Allocator, source: *const project.Project, checked: *const @import("project_check.zig").CheckedProject) !void {
    var frozen = try @import("dependency_closure.zig").freeze(allocator, source, checked);
    defer @import("dependency_format.zig").deinit(allocator, &frozen);
    try @import("dependency_closure.zig").validate(allocator, &frozen);
}

const richOwnerReader =
    \\import {value} from "./changed"
    \\const identity: forall [a] => a -> a = func item => return item
    \\const consume = func (item: unique U32) => return @usage.borrow item (func loan => return @usage.read loan)
    \\const checked = func (item: U32) => return do:
    \\  let witness = @proof.lt 0 item
    \\  break item
    \\const read: Unit -> U32 = func () => return identity value
    \\
;
const qualified_producer = "const pad: U32 = 1\ntype Box is data = $Box { first: U32 }\nconst first = func value => return value.first\nconst value: U32 = first ($Box { first: 41 })\n";
const qualified_moved = "const pad: U32 = 10\ntype Box is data = $Box { first: U32 }\nconst first = func value => return value.first\nconst value: U32 = first ($Box { first: 41 })\n";
const qualified_reader = "import {value, first, Box} from \"./changed\"\nconst read: Unit -> U32 = func () => return @u32.add value (first ($Box { first: 1 }))\n";
fn producerInterface(fixture: *Fixture) !@import("principal_interface.zig").Interface {
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    var checked = try @import("project_check.zig").checkProject(a, &source);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    for (source.units.items, 1..) |_, id| {
        if (!std.mem.endsWith(u8, source.filename(@intCast(id)), "/changed.blot")) continue;
        return @import("dependency_snapshot.zig").freezePrincipal(a, &source.unit(@intCast(id)).tree, &checked.module(@intCast(id)).checked);
    }
    return error.MissingProducer;
}
const associated_storage_original = "type Token is opaque = U32\ntype Other is opaque = U32\nconst make: U32 -> Token = func value => return $Token value\nconst make_other: U32 -> Other = func value => return $Other value\nconst Token.read: Token -> U32 = func ($Token value) => return value\nconst Other.read: Other -> U32 = func ($Other value) => return @u32.add value 1\n";
const associated_storage_alpha = "type Token is opaque = U32\ntype Other is opaque = U32\nconst make: U32 -> Token = func item => return $Token item\nconst make_other: U32 -> Other = func item => return $Other item\nconst Token.read: Token -> U32 = func ($Token item) => return item\nconst Other.read: Other -> U32 = func ($Other item) => return @u32.add item 1\n";

const implementation_storage_header = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl ScalarSource : Source U32 = {\n  type Item = U32,\n  const first = func value => return @u32.add value 1,\n}\n";
const implementation_storage_private = "private type Hidden a is contract = { type Item }\nprivate impl HiddenSource : Hidden F32 = { type Item = F32 }\n";
const implementation_storage_unused = implementation_storage_header ++ "type Token is opaque = U32\nconst make: U32 -> Token = func value => return $Token value\nconst read: Token -> U32 = func ($Token value) => return value\n";
const implementation_storage_used = implementation_storage_header ++ "type Token is opaque = U32\nconst make: U32 -> Token = func value => return $Token value\nconst read: Token -> U32 = func ($Token value) => return Source.first value\n";
