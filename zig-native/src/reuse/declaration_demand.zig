//! Optional source declaration demand. This manifest owns no inferred bindings,
//! schemes or catalogs; ordinary source validation remains mandatory.
const std = @import("std");
const ast = @import("../parse/ast.zig");
const symbols = @import("../parse/symbols.zig");
const project = @import("project.zig");
const references = @import("global_references.zig");
const A = std.mem.Allocator;

pub const Stats = struct { total: usize = 0, reached: usize = 0, fallback_units: usize = 0, transitions: usize = 0 };
pub const Unit = struct { declarations: []ast.Id = &.{}, total: usize = 0 };
pub const Plan = struct {
    allocator: A,
    units: []Unit,
    stats: Stats,

    pub fn prepare(a: A, loaded: *const project.Project) A.Error!?Plan {
        // Compiled interfaces use BindingIDs, not this manifest's AST identities.
        if (loaded.compiled_modules.len != 0 or loaded.diagnostics.items.len != 0) return null;
        var builder: Builder = .{ .allocator = a, .source = loaded };
        defer builder.deinit();
        try builder.collect();
        builder.selected = try a.alloc(bool, builder.declarations.items.len);
        @memset(builder.selected, false);
        builder.fallback = try a.alloc(bool, loaded.units.items.len);
        @memset(builder.fallback, false);
        try builder.importNames();
        for (builder.declarations.items, 0..) |declaration, index| if (declaration.seed) try builder.reach(@intCast(index + 1));
        for (loaded.units.items, 0..) |*unit, index| {
            const id: project.UnitId = @intCast(index + 1);
            for (unit.tree.roots.items) |root| {
                if (unit.tree.node(root).tag != .fixity_decl) continue;
                const target = unit.tree.fixity(root).target;
                if (builder.visible(id, target)) |found| {
                    if (found.ambiguous or found.value == 0) try builder.whole(id) else try builder.reach(found.value);
                } else try builder.whole(id);
            }
        }
        var next: usize = 0;
        while (next < builder.work.items.len) : (next += 1) {
            const declaration = builder.declarations.items[builder.work.items[next] - 1];
            const tree = &loaded.unit(declaration.unit).tree;
            if (tree.declarationNodes(declaration.owner)) |span| {
                for (tree.nodes.items[span.start..][0..span.len]) |node| {
                    // The shared walker does not yet reconstruct package scopes.
                    if (node.tag == .package_pack or node.tag == .package_unpack) {
                        try builder.whole(declaration.unit);
                        break;
                    }
                }
            } else try builder.whole(declaration.unit);
            builder.current = declaration.unit;
            const found = references.discover(a, tree, declaration.node, .{ .context = &builder, .self_name = loaded.symbols.lookup("self") orelse 0, .resolve = Builder.resolve }, &builder.stats.transitions, 4_000_000) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.TypeLimit => {
                    try builder.whole(declaration.unit);
                    continue;
                },
            };
            defer a.free(found);
            for (found) |reference| if (reference.binding != 0) try builder.reach(reference.binding);
        }
        const units = try a.alloc(Unit, loaded.units.items.len);
        @memset(units, .{});
        errdefer {
            for (units) |unit| a.free(unit.declarations);
            a.free(units);
        }
        for (builder.declarations.items) |declaration| units[declaration.unit - 1].total += 1;
        for (units, 0..) |*unit, index| {
            var count: usize = 0;
            for (builder.declarations.items, builder.selected) |declaration, selected| if (declaration.unit == index + 1 and selected) {
                count += 1;
            };
            unit.declarations = try a.alloc(ast.Id, count);
            var at: usize = 0;
            for (builder.declarations.items, builder.selected) |declaration, selected| if (declaration.unit == index + 1 and selected) {
                unit.declarations[at] = declaration.node;
                at += 1;
            };
            std.mem.sortUnstable(ast.Id, unit.declarations, {}, std.sort.asc(ast.Id));
        }
        builder.stats.total = builder.declarations.items.len;
        builder.stats.reached = builder.work.items.len;
        return .{ .allocator = a, .units = units, .stats = builder.stats };
    }
    pub fn wants(self: *const Plan, unit: project.UnitId, declaration: ast.Id) bool {
        if (unit == 0 or unit > self.units.len) return true;
        const roots = self.units[unit - 1].declarations;
        var low: usize = 0;
        var high = roots.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (roots[middle] < declaration) low = middle + 1 else high = middle;
        }
        return low < roots.len and roots[low] == declaration;
    }
    pub fn deinit(self: *Plan) void {
        for (self.units) |unit| self.allocator.free(unit.declarations);
        self.allocator.free(self.units);
        self.* = undefined;
    }
};

const Key = struct { unit: project.UnitId, name: symbols.Symbol };
// Zero value/namespace is a source catalog name, not a fabricated typed value.
const Name = struct { value: u32 = 0, namespace: project.UnitId = 0, public: bool = false, ambiguous: bool = false };
const Declaration = struct { unit: project.UnitId, node: ast.Id, owner: ast.Id, seed: bool };
const Builder = struct {
    allocator: A,
    source: *const project.Project,
    declarations: std.ArrayList(Declaration) = .empty,
    names: std.AutoHashMapUnmanaged(Key, Name) = .empty,
    exports: std.AutoHashMapUnmanaged(Key, Name) = .empty,
    selected: []bool = &.{},
    fallback: []bool = &.{},
    work: std.ArrayList(u32) = .empty,
    current: project.UnitId = 0,
    stats: Stats = .{},

    fn deinit(self: *Builder) void {
        self.declarations.deinit(self.allocator);
        self.names.deinit(self.allocator);
        self.exports.deinit(self.allocator);
        self.allocator.free(self.selected);
        self.allocator.free(self.fallback);
        self.work.deinit(self.allocator);
    }
    fn put(self: *Builder, key: Key, name: Name) A.Error!void {
        const item = try self.names.getOrPut(self.allocator, key);
        if (item.found_existing) {
            // A data type and its same-spelled constructor are catalog names.
            if (item.value_ptr.value == 0 and item.value_ptr.namespace == 0 and name.value == 0 and name.namespace == 0) return;
            item.value_ptr.ambiguous = true;
        } else item.value_ptr.* = name;
    }
    fn value(self: *Builder, unit: project.UnitId, root: ast.Id, method: ast.Id) A.Error!void {
        const tree = &self.source.unit(unit).tree;
        const value_ = tree.valueDecl(root);
        const associated = std.mem.findScalar(u8, self.source.symbols.get(value_.name), '.') != null;
        var body = value_.body;
        while (tree.node(body).tag == .group) body = tree.node(body).a;
        var owner = root;
        if (method != 0) owner = method;
        try self.declarations.append(self.allocator, .{ .unit = unit, .node = root, .owner = owner, .seed = method != 0 or associated or value_.exported or value_.attributes.len != 0 or tree.node(body).tag != .lambda });
        if (method == 0) try self.put(.{ .unit = unit, .name = value_.name }, .{ .value = @intCast(self.declarations.items.len), .public = !std.mem.eql(u8, self.source.symbols.get(value_.modifier), "private") and !tree.declarationTraits(root).private });
    }
    fn collect(self: *Builder) A.Error!void {
        for (self.source.units.items, 0..) |*unit, index| {
            const id: project.UnitId = @intCast(index + 1);
            for (unit.tree.roots.items) |root| {
                const node = unit.tree.node(root);
                switch (node.tag) {
                    .value_decl => try self.value(id, root, 0),
                    .implementation_decl => {
                        try self.put(.{ .unit = id, .name = node.a }, .{ .public = !unit.tree.declarationTraits(root).private });
                        for (unit.tree.list(unit.tree.implementation(root).members)) |member| if (unit.tree.node(member).tag == .value_decl) try self.value(id, member, root);
                    },
                    .data_decl => {
                        const traits = unit.tree.declarationTraits(root);
                        try self.put(.{ .unit = id, .name = node.a }, .{ .public = !traits.private });
                        for (unit.tree.children(node.b)) |constructor| try self.put(.{ .unit = id, .name = unit.tree.node(constructor).a }, .{ .public = !traits.private and !traits.is_opaque });
                    },
                    .type_alias_decl, .contract_decl, .effect_decl, .effect_type_decl => try self.put(.{ .unit = id, .name = node.a }, .{ .public = !unit.tree.declarationTraits(root).private }),
                    else => {},
                }
            }
        }
    }
    fn exported(self: *Builder, unit: project.UnitId, name: symbols.Symbol, depth: usize) ?Name {
        if (unit == 0 or unit > self.source.units.items.len or depth >= 64) return null;
        const key: Key = .{ .unit = unit, .name = name };
        if (self.exports.get(key)) |found| return found;
        if (self.names.get(key)) |found| if (found.public) return found;
        const tree = &self.source.unit(unit).tree;
        for (self.source.unitImports(unit)) |imported| {
            if (tree.node(imported.declaration.node).tag != .export_decl) continue;
            if (imported.namespace != 0) return null;
            for (tree.list(imported.bindings)) |binding| {
                const alias = tree.importBinding(binding);
                if (alias.alias == name) return self.exported(imported.target, alias.name, depth + 1);
            }
        }
        return null;
    }
    fn importNames(self: *Builder) A.Error!void {
        for (self.source.units.items, 0..) |*unit, index| {
            const id: project.UnitId = @intCast(index + 1);
            for (self.source.unitImports(id)) |imported| {
                if (imported.declaration.node == 0) {
                    try self.whole(id);
                    continue;
                }
                const forwarding = unit.tree.node(imported.declaration.node).tag == .export_decl;
                if (imported.namespace != 0) {
                    try self.put(.{ .unit = id, .name = imported.namespace }, .{ .namespace = imported.target });
                    if (forwarding) try self.whole(id);
                    continue;
                }
                for (unit.tree.list(imported.bindings)) |binding| {
                    const alias = unit.tree.importBinding(binding);
                    var target = self.exported(imported.target, alias.name, 0) orelse missing: {
                        try self.whole(imported.target);
                        break :missing Name{};
                    };
                    target.public = forwarding;
                    try self.put(.{ .unit = id, .name = alias.alias }, target);
                    if (forwarding) {
                        const entry = try self.exports.getOrPut(self.allocator, .{ .unit = id, .name = alias.alias });
                        if (entry.found_existing) entry.value_ptr.ambiguous = true else entry.value_ptr.* = target;
                    }
                }
            }
        }
    }
    fn reach(self: *Builder, value_: u32) A.Error!void {
        if (self.selected[value_ - 1]) return;
        self.selected[value_ - 1] = true;
        try self.work.append(self.allocator, value_);
    }
    fn whole(self: *Builder, unit: project.UnitId) A.Error!void {
        if (unit == 0 or unit > self.fallback.len or self.fallback[unit - 1]) return;
        self.fallback[unit - 1] = true;
        self.stats.fallback_units += 1;
        for (self.declarations.items, 0..) |declaration, index| if (declaration.unit == unit) try self.reach(@intCast(index + 1));
        for (self.source.unitImports(unit)) |imported| try self.whole(imported.target);
        if (self.source.unit(unit).implicit_prelude) try self.whole(self.source.prelude_unit);
    }
    fn exportedPath(self: *Builder, unit: project.UnitId, spelling: []const u8) ?Name {
        // Associated declarations own their complete spelling. Otherwise a
        // dotted suffix selects fields from the exported value's body.
        if (self.source.symbols.lookup(spelling)) |name| if (self.exported(unit, name, 0)) |found| return found;
        for (spelling, 0..) |character, index| {
            if (character != '.') continue;
            if (self.source.symbols.lookup(spelling[0..index])) |prefix| if (self.exported(unit, prefix, 0)) |found| return found;
        }
        return null;
    }
    fn visible(self: *Builder, unit: project.UnitId, name: symbols.Symbol) ?Name {
        if (self.names.get(.{ .unit = unit, .name = name })) |found| return found;
        const spelling = self.source.symbols.get(name);
        if (std.mem.findScalar(u8, spelling, '.')) |dot| {
            if (self.source.symbols.lookup(spelling[0..dot])) |head| if (self.names.get(.{ .unit = unit, .name = head })) |base| {
                if (base.namespace == 0) return base;
                return self.exportedPath(base.namespace, spelling[dot + 1 ..]);
            };
        }
        if (self.source.unit(unit).implicit_prelude) if (self.exported(self.source.prelude_unit, name, 0)) |found| return found;
        inline for (.{ "U32", "F32", "Bool", "Unit", "Never", "Array", "List", "Cursor", "GrowArray", "ResizeArray", "Ref", "View", "Link", "Demand", "Computation", "EffectSet", "EffectDescriptor", "Code", "Descriptor" }) |builtin| if (std.mem.eql(u8, spelling, builtin)) return .{};
        return null;
    }
    fn shadowed(self: *const Builder, locals: []const symbols.Symbol, name: symbols.Symbol) bool {
        if (std.mem.findScalar(symbols.Symbol, locals, name) != null) return true;
        const spelling = self.source.symbols.get(name);
        if (std.mem.findScalar(u8, spelling, '.')) |dot| if (self.source.symbols.lookup(spelling[0..dot])) |head| return std.mem.findScalar(symbols.Symbol, locals, head) != null;
        return false;
    }
    fn operator(self: *Builder, unit: project.UnitId, name: symbols.Symbol) ?ast.Fixity {
        for (self.source.unit(unit).tree.roots.items) |root| if (self.source.unit(unit).tree.node(root).tag == .fixity_decl) {
            const fixity = self.source.unit(unit).tree.fixity(root);
            if (fixity.operator == name) return fixity;
        };
        if (self.source.unit(unit).implicit_prelude) return self.operator(self.source.prelude_unit, name);
        return null;
    }
    fn resolve(context: *anyopaque, kind: references.Kind, name: symbols.Symbol, member: symbols.Symbol, locals: []const symbols.Symbol) references.Error!?u32 {
        const self: *Builder = @ptrCast(@alignCast(context));
        var found: ?Name = null;
        switch (kind) {
            .name => {
                if (self.shadowed(locals, name)) return null;
                found = self.visible(self.current, name);
            },
            .qualified => {
                if (self.shadowed(locals, name)) return null;
                const base = self.visible(self.current, name) orelse return null;
                if (base.namespace != 0) {
                    found = self.exportedPath(base.namespace, self.source.symbols.get(member));
                    if (found == null) try self.whole(base.namespace);
                } else if (base.value == 0 and !base.ambiguous) return 0 else return null;
            },
            .operator => {
                const spelling = self.source.symbols.get(name);
                if (std.mem.eql(u8, spelling, "and") or std.mem.eql(u8, spelling, "or")) return 0;
                if (self.operator(self.current, name)) |fixity| {
                    if (fixity.named and self.shadowed(locals, fixity.target)) return null;
                    // Symbolic inherited fixities retain the prelude's producer.
                    if (fixity.named) found = self.visible(self.current, fixity.target) else if (self.operatorUnit(self.current, name)) |owner| found = self.visible(owner, fixity.target);
                } else {
                    const text = self.source.symbols.get(name);
                    if (text.len == 0 or (!std.ascii.isAlphabetic(text[0]) and text[0] != '_')) {
                        try self.whole(self.current);
                        return 0;
                    }
                    if (self.shadowed(locals, name)) return null;
                    found = self.visible(self.current, name);
                }
            },
        }
        const target = found orelse {
            try self.whole(self.current);
            return 0;
        };
        if (target.ambiguous) {
            try self.whole(self.current);
            return 0;
        }
        if (target.namespace != 0) {
            try self.whole(target.namespace);
            return 0;
        }
        return target.value;
    }
    fn operatorUnit(self: *Builder, unit: project.UnitId, name: symbols.Symbol) ?project.UnitId {
        for (self.source.unit(unit).tree.roots.items) |root| if (self.source.unit(unit).tree.node(root).tag == .fixity_decl and self.source.unit(unit).tree.fixity(root).operator == name) return unit;
        if (self.source.unit(unit).implicit_prelude) return self.operatorUnit(self.source.prelude_unit, name);
        return null;
    }
};

const Fixture = struct {
    tmp: std.testing.TmpDir,
    loaded: project.Project,
    fn init(files: []const struct { name: []const u8, text: []const u8 }, prelude: ?[]const u8) !Fixture {
        const a = std.testing.allocator;
        const io = std.testing.io;
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        for (files) |file| try tmp.dir.writeFile(io, .{ .sub_path = file.name, .data = file.text });
        const entry = try tmp.dir.realPathFileAlloc(io, "main.blot", a);
        defer a.free(entry);
        var prelude_path: ?[:0]u8 = null;
        if (prelude) |name| prelude_path = try tmp.dir.realPathFileAlloc(io, name, a);
        defer if (prelude_path) |name| a.free(name);
        var loaded = try project.load(a, io, entry, .{ .prelude_path = prelude_path });
        errdefer loaded.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
        return .{ .tmp = tmp, .loaded = loaded };
    }
    fn deinit(self: *Fixture) void {
        self.loaded.deinit(std.testing.allocator);
        self.tmp.cleanup();
    }
    fn unit(self: *const Fixture, name: []const u8) project.UnitId {
        for (self.loaded.units.items, 1..) |_, id| if (std.mem.eql(u8, std.Io.Dir.path.basename(self.loaded.filename(@intCast(id))), name)) return @intCast(id);
        unreachable;
    }
    fn declaration(self: *const Fixture, unit_: project.UnitId, name: []const u8) ast.Id {
        const tree = &self.loaded.unit(unit_).tree;
        for (tree.nodes.items, 0..) |node, id| if (node.tag == .value_decl and std.mem.eql(u8, self.loaded.symbols.get(tree.valueDecl(@intCast(id)).name), name)) return @intCast(id);
        unreachable;
    }
    fn wants(self: *const Fixture, plan: *const Plan, file: []const u8, name: []const u8) bool {
        const id = self.unit(file);
        return plan.wants(id, self.declaration(id, name));
    }
};

fn closureLaw(a: A, fixture: *const Fixture) !void {
    var plan = (try Plan.prepare(a, &fixture.loaded)) orelse return error.TestUnexpectedResult;
    defer plan.deinit();
    try std.testing.expect(fixture.wants(&plan, "main.blot", "answer"));
    try std.testing.expect(fixture.wants(&plan, "library.blot", "helper"));
    try std.testing.expect(fixture.wants(&plan, "library.blot", "leaf"));
    try std.testing.expect(!fixture.wants(&plan, "library.blot", "expensive"));
    try std.testing.expectEqual(@as(usize, 0), plan.stats.fallback_units);
    try std.testing.expect(plan.stats.reached < plan.stats.total);
}
test "declaration demand follows namespace named reexports and ordinary helpers through allocation failures" {
    var fixture = try Fixture.init(&.{
        .{ .name = "main.blot", .text = "import * as bridge from \"./bridge\"\nentry const answer = func (input: U32) => return bridge.exposed (@u32.add input bridge.span_baskets.start)\n" },
        .{ .name = "bridge.blot", .text = "export {helper as exposed, span_baskets} from \"./library\"\n" },
        .{ .name = "library.blot", .text = "const leaf = func value => return @u32.add value 1\nconst helper = func value => return if true and false or true then leaf value else value\nconst span_baskets = {start:3}\nconst expensive = func value => return @u32.mul (@u32.mul value value) (@u32.mul value value)\n" },
    }, null);
    defer fixture.deinit();
    try closureLaw(std.testing.allocator, &fixture);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, closureLaw, .{&fixture});
}

test "declaration demand preserves named aliases prelude producers and lexical shadowing" {
    var fixture = try Fixture.init(&.{
        .{ .name = "main.blot", .text = "import {helper as chosen, other as renamed} from \"./library\"\nimport * as namespace from \"./library\"\nconst plus = func left -> right => return left\nconst local = func chosen => return do:\n  let namespace = func item => return item\n  return namespace chosen\nentry const answer = func (input: U32) => return renamed (prelude_helper (local input)) + 1\n" },
        .{ .name = "library.blot", .text = "const helper = func value => return value\nconst other = func value => return @u32.add value 7\n" },
        .{ .name = "prelude.blot", .text = "infixl 60 (+) = plus\nconst plus = func left -> right => return @u32.add left right\nconst prelude_helper = func value => return @u32.add value 2\nconst unused = func value => return value\n" },
    }, "prelude.blot");
    defer fixture.deinit();
    var plan = (try Plan.prepare(std.testing.allocator, &fixture.loaded)).?;
    defer plan.deinit();
    try std.testing.expect(fixture.wants(&plan, "library.blot", "other"));
    try std.testing.expect(!fixture.wants(&plan, "library.blot", "helper"));
    try std.testing.expect(fixture.wants(&plan, "prelude.blot", "prelude_helper"));
    try std.testing.expect(fixture.wants(&plan, "prelude.blot", "plus"));
    try std.testing.expect(!fixture.wants(&plan, "prelude.blot", "unused"));
    try std.testing.expect(!fixture.wants(&plan, "main.blot", "plus"));
    try std.testing.expectEqual(@as(usize, 0), plan.stats.fallback_units);
}

test "declaration demand retains operator associated implementation attributed and eager roots" {
    var fixture = try Fixture.init(&.{.{ .name = "main.blot", .text =
        \\infixl 60 (+) = plus
        \\const op_helper = func value => return value
        \\const plus = func left -> right => return op_helper left
        \\type Item is data = $Item U32
        \\const Item.measure = func value => return method_helper value
        \\const method_helper = func value => return value
        \\type Show a is contract = { const show: a -> U32 }
        \\impl NumberShow : Show U32 = { const show = func value => return impl_helper value }
        \\const impl_helper = func value => return value
        \\const init_helper = func () => return 1
        \\const eager = init_helper ()
        \\const attr_helper = func value => return value
        \\@[attr_helper 1]
        \\const attributed = func value => return value
        \\const unused = func value => return value
        \\entry const answer = func value => return value
    }}, null);
    defer fixture.deinit();
    var plan = (try Plan.prepare(std.testing.allocator, &fixture.loaded)).?;
    defer plan.deinit();
    for ([_][]const u8{ "plus", "op_helper", "Item.measure", "method_helper", "show", "impl_helper", "init_helper", "eager", "attr_helper", "attributed", "answer" }) |name| try std.testing.expect(fixture.wants(&plan, "main.blot", name));
    try std.testing.expect(!fixture.wants(&plan, "main.blot", "unused"));
    try std.testing.expectEqual(@as(usize, 0), plan.stats.fallback_units);
}

test "declaration demand falls back for escaped namespace authority and declines compiled owners" {
    var fixture = try Fixture.init(&.{
        .{ .name = "main.blot", .text = "import * as namespace from \"./library\"\nentry const answer = func () => return namespace\n" },
        .{ .name = "library.blot", .text = "const helper = func value => return value\nconst expensive = func value => return @u32.mul value value\n" },
    }, null);
    defer fixture.deinit();
    var plan = (try Plan.prepare(std.testing.allocator, &fixture.loaded)).?;
    defer plan.deinit();
    try std.testing.expect(fixture.wants(&plan, "library.blot", "helper"));
    try std.testing.expect(fixture.wants(&plan, "library.blot", "expensive"));
    try std.testing.expect(plan.stats.fallback_units > 0);
    const compiled: [1]@import("frozen_dependency.zig").Module = undefined;
    var borrowed = fixture.loaded;
    borrowed.compiled_modules = &compiled;
    try std.testing.expect((try Plan.prepare(std.testing.allocator, &borrowed)) == null);
}
