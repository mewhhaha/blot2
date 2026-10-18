//! Private final-entry cutoff within a dependency-first mixed preparation.
//! Only semantic frontend work is reusable; staging and backend work stay fresh.
const std = @import("std");
const project = @import("project.zig");
const identity = @import("../backend/runtime_identity.zig");
const snapshot = @import("dependency_snapshot.zig");
const PI = @import("principal_interface.zig");
const Allocator = std.mem.Allocator;

pub const Import = struct { path: u32, target: u32 };
pub const Previous = struct {
    reuse_entry: bool = true,
    bodies: []const @import("body_check_cache.zig").Cache = &.{},
    reuse_modules: bool = false,
    entry: u32,
    prelude: u32,
    implicit_prelude: bool,
    names: identity.View,
    source: []const u8,
    imports: []const Import,
};
pub const Color = enum { unknown, green, red };
pub const Stats = struct { comparison_hits: usize = 0, offered: usize = 0, source_matches: usize = 0, namespace_matches: usize = 0, compared: usize = 0, interfaces_changed: usize = 0, surfaces_changed: usize = 0, reused: usize = 0 };

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
    stats.reused += 1;
    return true;
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
    if (equal(left, moved)) return true;
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
    if (views[0].bindings.len == 0 or !equal(views[0], views[1])) return false;
    @import("dependency_interface_validation.zig").validate(&views[0], symbol_count, unit_count) catch return false;
    return true;
}

/// Equal principal results stop propagation only after a successful ordinary
/// check. This cache belongs to this one immutable mixed preparation.
pub fn interfaceMatches(a: Allocator, source: *const project.Project, checked: anytype, unit: u32, stats: *Stats) Allocator.Error!bool {
    if (unit == 0 or unit > source.compiled_modules.len) return false;
    if (checked.interface_colors.len != 0) switch (checked.interface_colors[unit - 1]) {
        .green => {
            stats.comparison_hits += 1;
            return true;
        },
        .red => {
            stats.comparison_hits += 1;
            return false;
        },
        .unknown => {},
    };
    const same = try compareInterface(a, source, checked, unit, stats);
    if (checked.interface_colors.len != 0) checked.interface_colors[unit - 1] = if (same) .green else .red;
    return same;
}
fn compareInterface(a: Allocator, source: *const project.Project, checked: anytype, unit: u32, stats: *Stats) Allocator.Error!bool {
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
    if (!interfaceEqual(old.interface, published, source.symbols.entries.items.len + 1, source.units.items.len)) {
        stats.interfaces_changed += 1;
        return false;
    }
    if (current.exports.len != old.exports.len) return false;
    for (current.exports, old.exports) |new, prior| {
        if (new.name != prior.name or new.target.unit != prior.target.unit or new.target.binding != prior.target.binding or @backingInt(new.kind) != @backingInt(prior.kind) or new.catalog != prior.catalog) {
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
        if (new.operator != prior.operator or new.target != prior.target or new.precedence != prior.precedence or new.association != prior.association or new.named != prior.named or target.unit != prior.producer.unit or target.binding != prior.producer.binding) return false;
    };
    if (fixity_index != old.fixities.len) return false;
    return true;
}

fn equal(left: anytype, right: @TypeOf(left)) bool {
    const T = @TypeOf(left);
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
