//! Private final-entry cutoff within a dependency-first mixed preparation.
//! Only semantic frontend work is reusable; staging and backend work stay fresh.
const std = @import("std");
const project = @import("project.zig");
const identity = @import("../backend/runtime_identity.zig");
const snapshot = @import("dependency_snapshot.zig");
const PI = @import("principal_interface.zig");
const core = @import("../check/core.zig");
const types = @import("../check/types.zig");
const Allocator = std.mem.Allocator;
const binding_relocation = @import("frontend_binding_relocation.zig");
const reference_relocation = @import("frontend_reference_relocation.zig");

pub const Import = struct { path: u32, target: u32 };
pub const Previous = struct {
    reuse_entry: bool = true,
    bodies: []const @import("body_check_cache.zig").Cache = &.{},
    reuse_modules: bool = false,
    entry_core: ?*const core.Module = null,
    entry: u32,
    prelude: u32,
    implicit_prelude: bool,
    names: identity.View,
    source: []const u8,
    imports: []const Import,
};
pub const Color = enum { unknown, green, green_storage, red };
pub const Stats = struct { comparison_hits: usize = 0, offered: usize = 0, source_matches: usize = 0, namespace_matches: usize = 0, compared: usize = 0, interfaces_changed: usize = 0, surfaces_changed: usize = 0, storage_rechecks: usize = 0, reused: usize = 0 };

/// A successful previous entry and its seed must belong to the same retained
/// revision. The caller proves that ownership pair before offering this view.
/// Current dependency checks finish first; any error prevents entry reuse.
pub fn confirm(a: Allocator, source: *const project.Project, checked: anytype, previous: Previous, stats: *Stats) Allocator.Error!bool {
    stats.offered += 1;
    const entry = source.entry;
    if (source.input_mode != .project or entry == 0 or entry != source.units.items.len or source.compiled_modules.len + 1 != source.units.items.len or source.compiled_reuse.len != source.compiled_modules.len or source.order.items.len == 0 or source.order.items[source.order.items.len - 1] != entry) return false;
    if (previous.entry != entry or previous.prelude != source.prelude_unit or previous.implicit_prelude != source.unit(entry).implicit_prelude or !std.mem.eql(u8, previous.source, source.unit(entry).source)) return false;
    const imports = source.unitImports(entry);
    if (imports.len != previous.imports.len) return false;
    for (imports, previous.imports) |current, old| if (current.path != old.path or current.target != old.target) return false;
    stats.source_matches += 1;
    // Ordered IDs must denote identical spellings and canonical producers.
    // Successful checking can append names; missing prior names decline.
    if (!namespaceMatches(source, previous.names)) return false;
    stats.namespace_matches += 1;
    // Confirm the entire prefix, including indirect aliases, implicit prelude,
    // ordered associated candidates and private principal declarations.
    for (1..source.compiled_modules.len + 1) |unit| {
        if (checked.compiledModule(source, unit) != null) continue;
        if (!try interfaceMatches(a, source, checked, @intCast(unit), stats)) return false;
    }
    if (!storageInputsMatch(source, checked, entry, previous.entry_core, stats)) return false;
    const targets: binding_relocation.Targets = .{ .units = checked.binding_maps };
    if (targets.changes() and !reference_relocation.admits(previous.entry_core orelse return false, targets)) return false;
    stats.reused += 1;
    return true;
}

/// Public nominal identity can stay equal while a private machine recipe
/// changes. A module defining another opaque representation must republish its
/// derived recipe if its payload reads that changed input. Ordinary semantic
/// callers keep the cutoff; storage producers retain ordinary checking.
pub fn storageInputsMatch(source: *const project.Project, checked: anytype, unit: u32, previous: ?*const core.Module, stats: *Stats) bool {
    if (std.mem.findScalar(Color, checked.interface_colors, .green_storage) == null) return true;
    const tree = &source.unit(unit).tree;
    const defines_storage = for (tree.roots.items) |root| {
        if (tree.declarationTraits(root).is_opaque) break true;
    } else false;
    if (!defines_storage) return true;
    if (previous) |module| {
        var remaining: usize = 1_000_000;
        if (module.unit == unit) {
            for (module.nominals) |nominal| {
                if (!nominal.is_opaque or nominal.identity.unit != unit) continue;
                if (nominal.constructors.len != 1) break;
                const constructor = module.constructors[module.extra[nominal.constructors.start]];
                if (!storageTypeStable(source, checked, module, constructor.payload, 0, &remaining)) break;
            } else return true;
        }
    }
    stats.storage_rechecks += 1;
    return false;
}

fn storageIdentityStable(source: *const project.Project, checked: anytype, identity_: types.NominalIdentity) bool {
    if (identity_.unit == 0 or identity_.unit == std.math.maxInt(u32)) return true;
    if (identity_.unit > checked.interface_colors.len) return false;
    if (checked.interface_colors[identity_.unit - 1] != .green_storage) return true;
    const current = if (checked.modules[identity_.unit - 1]) |*value| value else return false;
    const old = &source.compiled_modules[identity_.unit - 1].interface;
    for (old.nominals) |before| {
        if (!equal(before.identity, identity_)) continue;
        for (current.checked.nominals) |after| {
            if (equal(after.identity, identity_)) return equal(before.storage, after.storage);
        }
        return false;
    }
    return false;
}

fn storageTypeStable(source: *const project.Project, checked: anytype, module: *const core.Module, id: types.Id, depth: usize, remaining: *usize) bool {
    if (depth >= 128 or remaining.* == 0 or id >= module.types.nodes.len) return false;
    remaining.* -= 1;
    const node = module.types.node(id);
    return switch (node.tag) {
        .absent, .unit, .boolean, .u32, .f32, .never, .variable, .bound, .erased_proof, .type_constructor => true,
        .nominal => stable: {
            // Every locally owned opaque payload is visited by the caller.
            // Local identities do not name an imported prefix recipe.
            if (node.a != module.unit and !storageIdentityStable(source, checked, .{ .unit = node.a, .decl = node.b })) break :stable false;
            for (module.types.nominalArguments(node)) |child| if (!storageTypeStable(source, checked, module, child, depth + 1, remaining)) break :stable false;
            break :stable true;
        },
        .array, .list, .cursor, .resolver => storageTypeStable(source, checked, module, node.a, depth + 1, remaining),
        .demand, .provider => node.c == 0 and storageTypeStable(source, checked, module, node.a, depth + 1, remaining),
        .function => node.c == 0 and storageTypeStable(source, checked, module, node.a, depth + 1, remaining) and storageTypeStable(source, checked, module, node.b, depth + 1, remaining),
        .state_provider => storageTypeStable(source, checked, module, node.a, depth + 1, remaining) and storageTypeStable(source, checked, module, node.b, depth + 1, remaining) and storageTypeStable(source, checked, module, node.c, depth + 1, remaining),
        .usage => storageTypeStable(source, checked, module, node.a, depth + 1, remaining) and (node.c == 0 or storageTypeStable(source, checked, module, node.c, depth + 1, remaining)),
        .product => stable: {
            for (module.types.list(.{ .start = node.a, .len = node.b })) |child| if (!storageTypeStable(source, checked, module, child, depth + 1, remaining)) break :stable false;
            break :stable true;
        },
        .record => stable: {
            for (0..node.b) |index| if (!storageTypeStable(source, checked, module, module.types.recordField(node, index).ty, depth + 1, remaining)) break :stable false;
            break :stable true;
        },
        // Unresolved selections, scoped identities and exhausted proofs retain
        // ordinary storage publication rather than guessing their dependencies.
        else => false,
    };
}

/// New spellings may append after the exact namespace used by retained Core.
pub fn namespaceMatches(source: *const project.Project, names: identity.View) bool {
    if (names.owners.len != source.units.items.len or names.symbols.len == 0 or names.symbols.len > source.symbols.entries.items.len + 1) return false;
    for (source.units.items, 1..) |_, unit| if (!std.mem.eql(u8, names.owner(@intCast(unit)) orelse return false, source.filename(@intCast(unit)))) return false;
    for (1..names.symbols.len) |id| if (!std.mem.eql(u8, names.symbol(@intCast(id)) orelse return false, source.symbols.get(@intCast(id)))) return false;
    return true;
}

/// Compare every principal fact after omitting only unreferenced local
/// suffixes, wherever the producer's obligations sit in its source.
pub fn interfaceEqual(left: PI.Interface, right: PI.Interface, symbol_count: usize, unit_count: usize) bool {
    // Obligation spans place each predicate in the producer's own source.
    // Only the producer's diagnostics and body-cache qualification digests
    // (admission, never results) read them; no importer's check result does.
    // A size-changing edit before a qualified declaration moves them alone.
    var moved = right;
    if (left.obligation_spans.len == right.obligation_spans.len) moved.obligation_spans = left.obligation_spans;
    if (equal(left, moved) or principalEqual(left, moved)) return true;
    var views = [_]PI.Interface{ left, moved };
    for (&views) |*view| {
        var count = view.bindings.len;
        while (count != 0) {
            const binding = view.bindings[count - 1];
            if (binding.kind != .local and binding.kind != .parameter) break;
            const inert: PI.Binding = .{ .private = binding.private, .kind = binding.kind, .name = 0, .named_function = false, .ty = 0, .scheme = .{}, .external = null };
            if (!equal(binding, inert)) break;
            count -= 1;
        }
        view.bindings = view.bindings[0..count];
    }
    if (views[0].bindings.len == 0 or (!equal(views[0], views[1]) and !principalEqual(views[0], views[1]))) return false;
    @import("dependency_interface_validation.zig").validate(&views[0], symbol_count, unit_count) catch return false;
    return true;
}

fn principalEqual(left: PI.Interface, right: PI.Interface) bool {
    if (left.constructors.len != right.constructors.len) return false;
    var before = left;
    var after = right;
    before.constructors = &.{};
    after.constructors = &.{};
    if (!equal(before, after)) return false;
    for (left.constructors, right.constructors) |old, current| {
        var candidate = current;
        if (old.private and current.private and old.nominal < left.nominals.len and current.nominal < right.nominals.len) {
            const old_parent = left.nominals[old.nominal];
            const new_parent = right.nominals[current.nominal];
            // An opaque constructor is hidden from semantic consumers. Its
            // syntax node moves when its private payload changes; the matched
            // opaque parent retains the public identity. Keep unit, catalog
            // slot, tag and all other constructor facts exact. Executable and
            // artifact admission continue to compare the original identities.
            if (old_parent.is_opaque and new_parent.is_opaque and old_parent.storage.kind != .unknown and new_parent.storage.kind != .unknown and equal(old_parent.identity, new_parent.identity) and old.identity.unit == old_parent.identity.unit and current.identity.unit == new_parent.identity.unit) candidate.identity.decl = old.identity.decl;
        }
        if (!equal(old, candidate)) return false;
    }
    return true;
}

/// Equal principal results stop propagation only after a successful ordinary
/// check. This cache belongs to this one immutable mixed preparation.
pub fn interfaceMatches(a: Allocator, source: *const project.Project, checked: anytype, unit: u32, stats: *Stats) Allocator.Error!bool {
    if (unit == 0 or unit > source.compiled_modules.len) return false;
    if (checked.interface_colors.len != 0) switch (checked.interface_colors[unit - 1]) {
        .green, .green_storage => {
            stats.comparison_hits += 1;
            return true;
        },
        .red => {
            stats.comparison_hits += 1;
            return false;
        },
        .unknown => {},
    };
    var storage_changed = false;
    const same = try compareInterface(a, source, checked, unit, stats, &storage_changed);
    if (checked.interface_colors.len != 0) checked.interface_colors[unit - 1] = if (same) (if (storage_changed) .green_storage else .green) else .red;
    return same;
}
fn compareInterface(a: Allocator, source: *const project.Project, checked: anytype, unit: u32, stats: *Stats, storage_changed: *bool) Allocator.Error!bool {
    const old = &source.compiled_modules[unit - 1];
    const current = if (checked.modules[unit - 1]) |*value| value else return false;
    if (!current.valid or current.checked.diagnostics.len != 0) return false;
    const tree = &source.unit(@intCast(unit)).tree;
    var published = snapshot.freezePrincipal(a, tree, &current.checked) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    };
    defer snapshot.deinit(a, &published);
    stats.compared += 1;
    var mapping: ?binding_relocation.Map = null;
    defer if (mapping) |*owned| owned.deinit(a);
    if (!interfaceEqual(old.interface, published, source.symbols.entries.items.len + 1, source.units.items.len)) {
        if (unit > checked.binding_maps.len) {
            stats.interfaces_changed += 1;
            return false;
        }
        mapping = try binding_relocation.compare(a, &old.interface, &published, .{ .units = checked.binding_maps });
        if (mapping == null) {
            stats.interfaces_changed += 1;
            return false;
        }
    }
    if (current.exports.len != old.exports.len) return false;
    for (current.exports, old.exports) |new, prior| {
        const target = relocatedTarget(unit, mapping, checked.binding_maps, prior.target) orelse return false;
        const catalog = relocatedCatalog(unit, mapping, checked.binding_maps, prior) orelse return false;
        if (new.name != prior.name or new.target.unit != target.unit or new.target.binding != target.binding or @backingInt(new.kind) != @backingInt(prior.kind) or new.catalog != catalog) {
            stats.surfaces_changed += 1;
            return false;
        }
    }
    var fixity_index: usize = 0;
    for (tree.roots.items) |id| if (tree.node(id).tag == .fixity_decl) {
        if (fixity_index >= old.fixities.len) return false;
        const new = tree.fixity(id);
        const prior = old.fixities[fixity_index];
        fixity_index += 1;
        const binding = current.checked.resolved[id];
        if (binding == 0 or binding >= current.checked.bindings.len) return false;
        const target = current.checked.bindings[binding].external orelse @import("../check/check.zig").ExternalTarget{ .unit = @intCast(unit), .binding = binding };
        const producer = relocatedTarget(unit, mapping, checked.binding_maps, prior.producer) orelse return false;
        if (new.operator != prior.operator or new.target != prior.target or new.precedence != prior.precedence or new.association != prior.association or new.named != prior.named or target.unit != producer.unit or target.binding != producer.binding) return false;
    };
    if (fixity_index != old.fixities.len) return false;
    for (old.interface.nominals, 0..) |before, index| {
        if (index == 0 or before.private) continue;
        const current_index = if (mapping) |map| map.catalog(.nominal, @intCast(index)) orelse return false else index;
        if (current_index >= published.nominals.len) return false;
        const after = published.nominals[current_index];
        if (before.is_opaque and !equal(before.storage, after.storage)) storage_changed.* = true;
    }
    if (mapping) |map| if (map.changes()) {
        checked.binding_maps[unit - 1] = map;
        mapping = null;
    };
    return true;
}

fn relocatedCatalog(unit: u32, mapping: ?binding_relocation.Map, prior: []const ?binding_relocation.Map, exported: @import("frozen_dependency.zig").Export) ?u32 {
    if (exported.target.unit == unit) {
        const map = mapping orelse return exported.catalog;
        return map.catalog(exported.kind, exported.catalog);
    }
    return ((binding_relocation.Targets{ .units = prior }).exported(exported) orelse return null).catalog;
}

fn relocatedTarget(unit: u32, mapping: ?binding_relocation.Map, prior: []const ?binding_relocation.Map, target: PI.ExternalTarget) ?PI.ExternalTarget {
    if (target.binding == 0) return target;
    if (target.unit == unit) {
        const map = mapping orelse return target;
        return .{ .unit = unit, .binding = map.binding(target.binding) orelse return null };
    }
    return (binding_relocation.Targets{ .units = prior }).target(target);
}

fn equal(left: anytype, right: @TypeOf(left)) bool {
    const T = @TypeOf(left);
    if (comptime T == PI.Nominal) {
        var before = left;
        var after = right;
        // A known opaque storage recipe is an executable input. The caller's
        // checked principal sees only the nominal identity and public facts;
        // emission reads the current producer Core for its machine layout.
        // Unknown recipes keep the ordinary conservative comparison. No
        // executable/artifact equality uses this private semantic comparator.
        if (before.is_opaque and after.is_opaque and before.storage.kind != .unknown and after.storage.kind != .unknown) {
            before.storage = .{};
            after.storage = .{};
        }
        inline for (@typeInfo(T).@"struct".field_names) |field| if (!equal(@field(before, field), @field(after, field))) return false;
        return true;
    }
    return switch (@typeInfo(T)) {
        .pointer => |pointer| blk: {
            if (pointer.size != .slice) @compileError("Only immutable slices are compared");
            if (left.len != right.len) break :blk false;
            if (left.ptr == right.ptr) break :blk true;
            for (left, right) |a, b| if (!equal(a, b)) break :blk false;
            break :blk true;
        },
        .@"struct" => |info| blk: {
            inline for (info.field_names) |field| if (!equal(@field(left, field), @field(right, field))) break :blk false;
            break :blk true;
        },
        .optional => if (left) |value| if (right) |other| equal(value, other) else false else right == null,
        .array => blk: {
            for (left, right) |a, b| if (!equal(a, b)) break :blk false;
            break :blk true;
        },
        .@"union" => |info| blk: {
            const Tag = info.tag_type orelse @compileError("Tagged values required");
            if (@as(Tag, left) != @as(Tag, right)) break :blk false;
            inline for (info.field_names) |field| if (@as(Tag, left) == @field(Tag, field)) break :blk equal(@field(left, field), @field(right, field));
            unreachable;
        },
        .float => std.mem.eql(u8, std.mem.asBytes(&left), std.mem.asBytes(&right)),
        .int, .bool, .@"enum" => left == right,
        .void => true,
        else => @compileError("Add explicit frontend equality for new semantic fields"),
    };
}
