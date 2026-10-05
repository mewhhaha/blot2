//! Fresh project entry checking against an admitted generic dependency closure.
//! Only entry syntax is parsed; no cached module frontend owner is reconstructed.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const ast = @import("ast.zig");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const D = @import("frozen_dependency.zig");
const consumer = @import("dependency_consumer.zig");
const PI = @import("principal_interface.zig");
const format = @import("dependency_format.zig");
const purity = @import("purity_diagnostics.zig");
const T = @import("types.zig");
const Allocator = std.mem.Allocator;
const syntax = @import("syntax_diagnostics.zig");

const ResolvedImport = struct { node: ast.Id, owner: u32 };
const Lowered = union(enum) {
    ready: struct { ir: core.Module, stats: consumer.Stats },
    rejected: consumer.Result,
};
const Origins = struct {
    bundle: *const D.FrozenDependency,
    entry: u32,
    entry_identity: []const u8,
    prelude: u32,
    fn lookup(context: ?*const anyopaque, allocator: Allocator, unit: u32) T.Error![]u8 {
        const self: *const Origins = @ptrCast(@alignCast(context orelse return error.TypeLimit));
        if (unit == self.prelude and unit != 0) return allocator.dupe(u8, "std/prelude");
        const path = if (unit == self.entry) self.entry_identity else blk: {
            if (unit == 0 or unit > self.bundle.modules.len) return error.TypeLimit;
            break :blk self.bundle.modules[unit - 1].identity.normalized_path;
        };
        const directory = std.fs.path.dirname(self.entry_identity) orelse return error.TypeLimit;
        return std.fs.path.relative(allocator, directory, null, directory, path);
    }
};
fn require(condition: bool) error{InvalidArtifact}!void {
    if (!condition) return error.InvalidArtifact;
}
fn rejected(a: Allocator, unit: u32, stage: []const u8, code: []const u8, span: ast.Span, message: []const u8) !Lowered {
    const detail = try consumer.Diagnostic.init(a, unit, stage, code, span, message);
    return .{ .rejected = .{ .compiled = .{}, .stats = .{ .syntax_nodes = 0, .body_elaborations = 0, .body_lowerings = 0, .imported_schemes = 0 }, .diagnostic = detail } };
}
fn publishedRejected(a: Allocator, unit: u32, stage: []const u8, source: []const u8, publication: syntax.Publication, details: anytype) !Lowered {
    return .{ .rejected = .{ .compiled = .{}, .stats = .{ .syntax_nodes = 0, .body_elaborations = 0, .body_lowerings = 0, .imported_schemes = 0 }, .diagnostic = try consumer.publishedDiagnostic(a, unit, stage, source, publication, details) } };
}
fn projectRejected(a: Allocator, unit: u32, code: project_check.Code, span: ast.Span) !Lowered {
    const issue: project_check.Diagnostic = .{ .unit = unit, .code = code, .span = span };
    return rejected(a, unit, "project-check", @tagName(code), span, issue.message());
}
fn loadRejected(a: Allocator, unit: u32, code: project.Code, span: ast.Span) !Lowered {
    const issue: project.Diagnostic = .{ .unit = unit, .code = code, .span = span };
    return rejected(a, unit, "load", @tagName(code), span, issue.message());
}
fn target(bundle: *const D.FrozenDependency, owner: u32, raw: PI.ExternalTarget) error{InvalidArtifact}!PI.ExternalTarget {
    const unit = if (raw.unit == 0) owner else raw.unit;
    try require(unit != 0 and unit <= bundle.modules.len);
    try require(raw.binding != 0 and raw.binding < bundle.modules[unit - 1].interface.bindings.len);
    return .{ .unit = unit, .binding = raw.binding };
}
fn importedValue(bundle: *const D.FrozenDependency, owner: u32, raw: PI.ExternalTarget, origin: ast.Id) !check.ImportedBinding {
    const resolved = try target(bundle, owner, raw);
    const producer = &bundle.modules[resolved.unit - 1].interface;
    const definition = producer.bindings[resolved.binding];
    return .{ .target = resolved, .origin = origin, .interface = .{ .types = .{ .frozen = &producer.graph }, .scheme = definition.scheme, .obligations = producer.obligations, .named_function = definition.named_function } };
}
fn importExport(a: Allocator, bundle: *const D.FrozenDependency, imports: *std.ArrayList(check.ImportedBinding), catalogs: *std.ArrayList(check.ImportedCatalog), owner: u32, exported: D.Export, name: u32, namespace: u32, origin: ast.Id) !void {
    if (exported.kind == .value) {
        var value = try importedValue(bundle, owner, exported.target, origin);
        value.name = if (namespace == 0) name else 0;
        value.namespace = namespace;
        value.member = if (namespace == 0) 0 else name;
        try imports.append(a, value);
    } else try catalogs.append(a, .{ .frozen = &bundle.modules[owner - 1].interface, .name = name, .namespace = namespace, .origin = origin, .index = exported.catalog, .kind = switch (exported.kind) {
        .nominal => .nominal,
        .constructor => .constructor,
        .effect_family => .effect_family,
        .value => unreachable,
    } });
}

/// Keep the first gate's closure exact. Retaining an unreachable former module
/// could expose an extra associated catalog to backend-wide method lookup.
fn exactClosure(a: Allocator, bundle: *const D.FrozenDependency, roots: []const ResolvedImport, prelude: u32) !void {
    const seen = try a.alloc(bool, bundle.modules.len);
    defer a.free(seen);
    @memset(seen, false);
    var stack: std.ArrayList(u32) = .empty;
    defer stack.deinit(a);
    if (prelude != 0) try stack.append(a, prelude);
    for (roots) |root| try stack.append(a, root.owner);
    while (stack.pop()) |unit| {
        try require(unit != 0 and unit <= bundle.modules.len);
        if (seen[unit - 1]) continue;
        seen[unit - 1] = true;
        for (bundle.modules[unit - 1].imports) |dependency| try stack.append(a, dependency);
    }
    for (seen) |reached| if (!reached) return error.DependencySetChanged;
}

/// The caller validates wire/key/source/Core/principal ownership and publishes
/// the original ordered dictionary first. Cached units remain dense1..N, with
/// the fresh entry atN+1. Returned code never borrows entry syntax or schemes.
fn lowerEntry(a: Allocator, io: std.Io, entry_identity: []const u8, source: []const u8, options: project.Options, pool: *symbols.Pool, bundle: *const D.FrozenDependency) !Lowered {
    if (options.input_mode != .project) return error.InputModeUnsupported;
    try require(bundle.modules.len < std.math.maxInt(u32));
    const entry: u32 = @intCast(bundle.modules.len + 1);
    var prelude: u32 = 0;
    for (bundle.modules, 1..) |*module, unit| {
        try require(module.core.unit == unit and module.interface.unit == unit);
        if (std.mem.eql(u8, module.identity.normalized_path, entry_identity)) return error.DependencySetChanged;
        if (module.identity.prelude) {
            try require(prelude == 0);
            prelude = @intCast(unit);
        }
    }
    var inherited: std.ArrayList(parser.InheritedFixity) = .empty;
    defer inherited.deinit(a);
    if (prelude != 0) for (bundle.modules[prelude - 1].fixities) |f| try inherited.append(a, .{ .operator = f.operator, .precedence = f.precedence, .association = f.association, .named = f.named });
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    if (tokens.diagnostics.items.len != 0) {
        const issue = tokens.diagnostics.items[0];
        return publishedRejected(a, entry, "parse-project", source, syntax.lexical(tokens.tokens.items, issue), tokens.diagnostics.items);
    }
    var tree = try parser.parseWithFixities(a, source, tokens.tokens.items, pool, inherited.items);
    defer tree.deinit(a);
    if (tree.diagnostics.items.len != 0) {
        const issue = tree.diagnostics.items[0];
        return publishedRejected(a, entry, "parse-project", source, try syntax.parse(a, tokens.tokens.items, issue), tree.diagnostics.items);
    }
    var resolved: std.ArrayList(ResolvedImport) = .empty;
    defer resolved.deinit(a);
    for (tree.roots.items) |id| if (tree.node(id).tag == .import_decl) {
        const info = tree.importDecl(id);
        const path = project.resolveImportPath(a, entry_identity, pool.get(info.path), options) catch |err| switch (err) {
            error.InvalidPath => return loadRejected(a, entry, .import_path, tree.span(id)),
            else => return err,
        };
        defer a.free(path);
        const canonical = std.Io.Dir.cwd().realPathFileAlloc(io, path, a) catch |err| switch (err) {
            error.FileNotFound => return loadRejected(a, entry, .missing_file, tree.span(id)),
            error.OutOfMemory => return error.OutOfMemory,
            else => return loadRejected(a, entry, .io_error, tree.span(id)),
        };
        defer a.free(canonical);
        const owner = for (bundle.modules, 1..) |*module, unit| {
            if (std.mem.eql(u8, module.identity.normalized_path, canonical)) break @as(u32, @intCast(unit));
        } else return error.DependencySetChanged;
        try resolved.append(a, .{ .node = id, .owner = owner });
    };
    try exactClosure(a, bundle, resolved.items, prelude);
    var occupied: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer occupied.deinit(a);
    for (tree.roots.items) |id| {
        const node = tree.node(id);
        if (node.tag == .value_decl or node.tag == .data_decl or node.tag == .effect_decl or node.tag == .effect_type_decl) try occupied.put(a, node.a, {});
        if (node.tag == .data_decl) for (tree.children(node.b)) |constructor| try occupied.put(a, tree.node(constructor).a, {});
    }
    var imports: std.ArrayList(check.ImportedBinding) = .empty;
    defer imports.deinit(a);
    var catalogs: std.ArrayList(check.ImportedCatalog) = .empty;
    defer catalogs.deinit(a);
    var fixities: std.ArrayList(check.ImportedFixity) = .empty;
    defer fixities.deinit(a);
    for (resolved.items) |imported| {
        const info = tree.importDecl(imported.node);
        const producer = &bundle.modules[imported.owner - 1];
        if (info.namespace != 0) {
            const present = try occupied.getOrPut(a, info.namespace);
            if (present.found_existing) return projectRejected(a, entry, .duplicate_name, info.namespace_span);
        }
        try catalogs.append(a, .{ .frozen = &producer.interface, .kind = .catalog, .index = 0, .origin = imported.node });
        if (info.namespace != 0) {
            for (producer.exports) |exported| try importExport(a, bundle, &imports, &catalogs, imported.owner, exported, exported.name, info.namespace, imported.node);
        } else for (tree.list(info.bindings)) |binding| {
            const alias = tree.importBinding(binding);
            const present = try occupied.getOrPut(a, alias.alias);
            if (present.found_existing) return projectRejected(a, entry, .duplicate_name, tree.span(binding));
            var found = false;
            for (producer.exports) |exported| if (exported.name == alias.name) {
                found = true;
                try importExport(a, bundle, &imports, &catalogs, imported.owner, exported, alias.alias, 0, binding);
            };
            if (!found) return projectRejected(a, entry, .unknown_export, tree.span(binding));
        }
    }
    if (prelude != 0) {
        const producer = &bundle.modules[prelude - 1];
        try catalogs.append(a, .{ .frozen = &producer.interface, .kind = .catalog, .index = 0, .origin = 0 });
        for (producer.exports) |exported| if (!occupied.contains(exported.name)) try importExport(a, bundle, &imports, &catalogs, prelude, exported, exported.name, 0, 0);
        for (producer.fixities) |f| {
            const actual = try target(bundle, prelude, f.producer);
            if (!f.named) {
                var hidden = try importedValue(bundle, prelude, actual, 0);
                hidden.expose = false;
                try imports.append(a, hidden);
            }
            try fixities.append(a, .{ .operator = f.operator, .target = f.target, .named = f.named, .external = if (f.named) null else actual });
        }
    }
    const origins: Origins = .{ .bundle = bundle, .entry = entry, .entry_identity = entry_identity, .prelude = prelude };
    var checked = try check.checkModuleWithOptions(a, &tree, pool, imports.items, catalogs.items, entry, .{ .purity_origins = .{ .context = &origins, .lookup = Origins.lookup }, .prelude_unit = prelude, .inherited_fixities = fixities.items });
    defer checked.deinit(a);
    if (checked.diagnostics.len != 0) {
        const issue = checked.diagnostics[0];
        if (issue.purity) |witness| {
            const label = if (witness.operation_name != null or witness.foreign)
                try a.dupe(u8, "")
            else
                try Origins.lookup(&origins, a, witness.identity.unit);
            defer a.free(label);
            const message = try purity.format(a, pool, label, witness);
            defer a.free(message);
            return publishedRejected(a, entry, "check-project", source, .{ .cause = .native_detail, .code = @tagName(issue.code), .span = issue.span, .message = message }, @as([]const check.PurityWitness, &.{witness}));
        }
        if (issue.numeric_literal) |detail| return publishedRejected(a, entry, "check-project", source, .{ .cause = .native_detail, .code = @tagName(issue.code), .span = issue.span, .message = issue.message(), .actual_token = detail.actual_token }, @as([]const ast.NumericFault, &.{detail}));
        if (issue.symbol == 0) return rejected(a, entry, "check-project", @tagName(issue.code), issue.span, issue.message());
        const message = try a.print("{s}{s}{s}", .{ issue.message(), if (issue.code == .unknown_intrinsic or issue.code == .unknown_record_field) " " else ": ", pool.get(issue.symbol) });
        defer a.free(message);
        return rejected(a, entry, "check-project", @tagName(issue.code), issue.span, message);
    }
    var ir = try core.lowerWithOrigins(a, &tree, pool, &checked, .{ .context = &origins, .lookup = Origins.lookup });
    var transferred = false;
    defer if (!transferred) ir.deinit(a);
    ir.unit = entry;
    if (ir.diagnostics.len != 0) {
        const issue = ir.diagnostics[0];
        return rejected(a, entry, "lower", @tagName(issue.code), issue.span, issue.message());
    }
    const stats: consumer.Stats = .{ .syntax_nodes = tree.nodes.items.len - 1, .body_elaborations = checked.body_elaborations, .body_lowerings = ir.body_lowerings, .imported_schemes = checked.imported_schemes };
    transferred = true;
    return .{ .ready = .{ .ir = ir, .stats = stats } };
}

fn emissionIdentity(a: Allocator, pool: *const symbols.Pool, bundle: *const D.FrozenDependency, entry_identity: []const u8, entry: u32) !@import("runtime_identity.zig").Metadata {
    const owners = try a.alloc(@import("runtime_identity.zig").Owner, bundle.modules.len + 1);
    defer a.free(owners);
    for (bundle.modules, owners[0..bundle.modules.len]) |*module, *owner| owner.* = .{ .unit = module.core.unit, .path = module.identity.normalized_path };
    owners[bundle.modules.len] = .{ .unit = entry, .path = entry_identity };
    return @import("runtime_identity.zig").Metadata.capture(a, pool, owners, owners.len);
}

fn emitLowered(a: Allocator, bundle: *const D.FrozenDependency, ir: *const core.Module, stats: consumer.Stats, names: @import("runtime_identity.zig").View) !consumer.Result {
    const units = try a.alloc(core.Module, bundle.modules.len + 1);
    defer a.free(units);
    for (bundle.modules, units[0..bundle.modules.len]) |*module, *unit| unit.* = module.core;
    units[bundle.modules.len] = ir.*;
    var prelude_unit: u32 = 0;
    for (bundle.modules) |module| if (module.identity.prelude) {
        prelude_unit = module.core.unit;
    };
    return .{ .compiled = try backend.compileWithOptions(a, units, ir.unit, .{ .identity = names, .diagnostic_prelude_unit = prelude_unit }), .stats = stats };
}

/// Borrows the admitted bundle. Entry frontend and solver owners are released
/// before backend work; dependency interfaces remain reusable and immutable.
pub fn compile(a: Allocator, io: std.Io, entry_identity: []const u8, source: []const u8, options: project.Options, pool: *symbols.Pool, bundle: *const D.FrozenDependency) !consumer.Result {
    const lowered = try lowerEntry(a, io, entry_identity, source, options, pool, bundle);
    switch (lowered) {
        .rejected => |result| return result,
        .ready => |ready| {
            var ir = ready.ir;
            defer ir.deinit(a);
            var names = try emissionIdentity(a, pool, bundle, entry_identity, ir.unit);
            defer names.deinit(a);
            return emitLowered(a, bundle, &ir, ready.stats, names.view());
        },
    }
}

/// One-shot consumption of an owned, admitted bundle. Successful entry lowering
/// ends the principal-interface lifetime before backend work. Core, producer
/// identities and dictionary owners survive until the caller deinitializes the
/// bundle. The remaining bundle cannot be reused or encoded as an artifact.
/// Rejection before lowering preserves all dependency interfaces.
pub fn compileOwned(a: Allocator, io: std.Io, entry_identity: []const u8, source: []const u8, options: project.Options, pool: *symbols.Pool, bundle: *D.FrozenDependency) !consumer.Result {
    const lowered = try lowerEntry(a, io, entry_identity, source, options, pool, bundle);
    switch (lowered) {
        .rejected => |result| return result,
        .ready => |ready| {
            var ir = ready.ir;
            defer ir.deinit(a);
            var names = try emissionIdentity(a, pool, bundle, entry_identity, ir.unit);
            defer names.deinit(a);
            for (bundle.modules) |*module| {
                format.deinit(a, &module.interface);
                module.interface = std.mem.zeroes(PI.Interface);
            }
            return emitLowered(a, bundle, &ir, ready.stats, names.view());
        },
    }
}
