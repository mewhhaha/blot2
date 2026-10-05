//! Create a generic source-module bundle, before any application evaluation.
const std = @import("std");
const ast = @import("ast.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const snapshot = @import("dependency_snapshot.zig");
const D = @import("frozen_dependency.zig");
const format = @import("dependency_format.zig");
const Allocator = std.mem.Allocator;

/// First gate: one no-import dependency checked in its own source unit 1.
/// This never freezes application-specific instances, evaluated values or code.
pub fn freeze(allocator: Allocator, path: []const u8, source: []const u8, pool: *const symbols.Pool, tree: *const ast.Tree, checked: *const check.Checked, prelude: bool) !D.FrozenDependency {
    if (checked.unit != 1 or checked.diagnostics.len != 0 or source.len > std.math.maxInt(u32)) return error.InvalidArtifact;
    for (tree.roots.items) |id| if (tree.node(id).tag == .import_decl) return error.ImportedDependencyUnsupported;
    var ir = try core.lower(allocator, tree, pool, checked);
    errdefer ir.deinit(allocator);
    ir.unit = 1;
    if (ir.diagnostics.len != 0) return error.InvalidArtifact;
    // Private solver certificates are epoch-bound scratch facts, never a
    // portable proof. Core semantics consist only of tag/a/b/c here.
    for (ir.types.nodes) |*node| node.* = .{ .tag = node.tag, .a = node.a, .b = node.b, .c = node.c };
    for (ir.bodies) |body| if (body.exported) return error.EntryDependencyUnsupported;
    var interface = try snapshot.freeze(allocator, tree, checked);
    errdefer snapshot.deinit(allocator, &interface);
    var exports: std.ArrayList(D.Export) = .empty;
    defer exports.deinit(allocator);
    for (checked.bindings, 0..) |binding, id| if (binding.kind == .global) {
        try exports.append(allocator, .{ .name = binding.name, .target = .{ .unit = 1, .binding = @intCast(id) }, .kind = .value, .catalog = 0 });
    };
    for (checked.nominals[1..], 1..) |nominal, id| if (nominal.identity.unit == 1) {
        try exports.append(allocator, .{ .name = nominal.name, .target = .{ .unit = 0, .binding = 0 }, .kind = .nominal, .catalog = @intCast(id) });
    };
    for (checked.constructors[1..], 1..) |constructor, id| if (constructor.identity.unit == 1) {
        try exports.append(allocator, .{ .name = constructor.name, .target = .{ .unit = 0, .binding = 0 }, .kind = .constructor, .catalog = @intCast(id) });
    };
    for (checked.effect_families[1..], 1..) |family, id| if (family.identity.unit == 1) {
        try exports.append(allocator, .{ .name = family.name, .target = .{ .unit = 0, .binding = 0 }, .kind = .effect_family, .catalog = @intCast(id) });
    };
    var fixities: std.ArrayList(D.Fixity) = .empty;
    defer fixities.deinit(allocator);
    for (tree.roots.items) |id| if (tree.node(id).tag == .fixity_decl) {
        const value = tree.fixity(id);
        const binding = checked.resolved[id];
        const target = checked.bindings[binding].external orelse check.ExternalTarget{ .unit = 1, .binding = binding };
        try fixities.append(allocator, .{ .operator = value.operator, .target = value.target, .precedence = value.precedence, .association = value.association, .named = value.named, .producer = target });
    };
    const name_dictionary = try allocator.alloc(D.Symbol, pool.entries.items.len + 1);
    @memset(name_dictionary, .{ .text = &.{} });
    errdefer {
        for (name_dictionary) |value| allocator.free(value.text);
        allocator.free(name_dictionary);
    }
    for (name_dictionary[1..], 1..) |*value, id| value.text = try allocator.dupe(u8, pool.get(@intCast(id)));
    const normalized_path = try allocator.dupe(u8, path);
    errdefer allocator.free(normalized_path);
    const owned_exports = try exports.toOwnedSlice(allocator);
    errdefer allocator.free(owned_exports);
    const owned_fixities = try fixities.toOwnedSlice(allocator);
    errdefer allocator.free(owned_fixities);
    const modules = try allocator.alloc(D.Module, 1);
    modules[0] = .{ .identity = .{ .normalized_path = normalized_path, .source_digest = format.digest(source), .source_bytes = @intCast(source.len), .prelude = prelude }, .imports = &.{}, .core = ir, .interface = interface, .exports = owned_exports, .fixities = owned_fixities };
    return .{ .symbols = name_dictionary, .modules = modules };
}
