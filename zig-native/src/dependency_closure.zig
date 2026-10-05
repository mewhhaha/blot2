//! Owned source-free snapshots of a complete nonentry dependency closure.
//! Source units are normalized to dense artifact ordinals. Nothing here forces
//! a source constant, specializes a caller, or retains frontend/solver owners.
const std = @import("std");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const core = @import("core.zig");
const partial = @import("partial_dependency.zig");
const PI = @import("principal_interface.zig");
const D = @import("frozen_dependency.zig");
const retained = @import("retained_dependency.zig");
const snapshot = @import("dependency_snapshot.zig");
const format = @import("dependency_format.zig");
const relink = @import("dependency_relink.zig");
const core_validation = @import("frozen_core_validation.zig");
const principal_validation = @import("dependency_interface_validation.zig");
pub const Error = std.mem.Allocator.Error || error{ InvalidArtifact, DependencyLimit, CoreLimit };

fn ordinal(source: *const project.Project, unit: u32) Error!u32 {
    try require(unit != 0 and unit <= source.units.items.len and unit != source.entry);
    return if (unit < source.entry) unit else unit - 1;
}

fn require(value: bool) Error!void {
    if (!value) return error.InvalidArtifact;
}
fn mapped(units: []const u32, id: u32) Error!u32 {
    if (id == 0 or id == std.math.maxInt(u32)) return id;
    try require(id <= units.len and units[id - 1] != 0);
    return units[id - 1];
}
fn checkInterfaceUnits(owner: *const PI.Interface, units: []const u32) Error!void {
    _ = try mapped(units, owner.unit);
    for (owner.graph.nodes) |n| if (n.tag == .nominal or n.tag == .type_constructor) {
        _ = try mapped(units, n.a);
    };
    for (owner.graph.operations) |o| _ = try mapped(units, o.identity.unit);
    for (owner.bindings) |b| if (b.external) |t| {
        _ = try mapped(units, t.unit);
    };
    for (owner.obligations) |o| {
        _ = try mapped(units, o.identity.unit);
        _ = try mapped(units, o.qualification_unit);
    }
    for (owner.nominals) |n| _ = try mapped(units, n.identity.unit);
    for (owner.constructors) |c| _ = try mapped(units, c.identity.unit);
    for (owner.effect_families) |f| _ = try mapped(units, f.identity.unit);
    for (owner.effect_templates) |o| _ = try mapped(units, o.identity.unit);
    for (owner.associated) |m| _ = try mapped(units, m.identity.unit);
}

// Flat slice elements can be copied in bulk. Nested owned slices recurse so
// newly owned fields cannot silently become borrowed from an earlier revision.
fn plain(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => false,
        .@"struct" => |structure| blk: {
            inline for (structure.field_names) |name| if (!plain(@FieldType(T, name))) break :blk false;
            break :blk true;
        },
        .@"union" => |union_| blk: {
            inline for (union_.field_names) |name| if (!plain(@FieldType(T, name))) break :blk false;
            break :blk true;
        },
        .array => |array| plain(array.child),
        .optional => |optional| plain(optional.child),
        .int, .float, .bool, .@"enum", .void => true,
        else => false,
    };
}
/// Independent owned Core for an admitted frontend result.
pub fn copyCore(a: std.mem.Allocator, value: *const core.Module) std.mem.Allocator.Error!core.Module {
    return copyCoreValue(a, value.*);
}
fn copyCoreValue(a: std.mem.Allocator, value: anytype) std.mem.Allocator.Error!@TypeOf(value) {
    @setEvalBranchQuota(20000);
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .pointer => |pointer| {
            if (comptime pointer.size != .slice) @compileError("Owned slices required");
            if (comptime plain(pointer.child)) return a.dupe(pointer.child, value);
            const result = try a.alloc(pointer.child, value.len);
            var initialized: usize = 0;
            errdefer {
                for (result[0..initialized]) |*item| format.deinit(a, item);
                a.free(result);
            }
            for (value, result) |item, *copy| {
                copy.* = try copyCoreValue(a, item);
                initialized += 1;
            }
            return result;
        },
        .@"struct" => |structure| {
            var result: T = undefined;
            var initialized: usize = 0;
            errdefer inline for (structure.field_names, 0..) |name, index| {
                if (index < initialized) format.deinit(a, &@field(result, name));
            };
            inline for (structure.field_names) |name| {
                @field(result, name) = try copyCoreValue(a, @field(value, name));
                initialized += 1;
            }
            return result;
        },
        else => {
            if (comptime !plain(T)) @compileError("Unsupported Core copy field");
            return value;
        },
    }
}

fn freezeOne(a: std.mem.Allocator, source: *const project.Project, checked: *const project_check.CheckedProject, unit: u32, units: []const u32, retained_core: ?*const core.Module) Error!D.Module {
    const src = source.unit(unit);
    const typed = checked.module(unit);
    try require(typed.valid and typed.checked.diagnostics.len == 0 and typed.checked.unit == unit);
    var ir = if (retained_core) |saved| try copyCoreValue(a, saved.*) else try core.lowerWithOrigins(a, &src.tree, &source.symbols, &typed.checked, .{ .context = source, .lookup = project_check.diagnosticModuleOrigin });
    errdefer ir.deinit(a);
    ir.unit = unit;
    try require(ir.diagnostics.len == 0);
    for (ir.bodies) |body| try require(!body.exported);
    // Portable semantics contain no epoch-bound solver certificate metadata.
    for (ir.types.nodes) |*node| node.* = .{ .tag = node.tag, .a = node.a, .b = node.b, .c = node.c };
    var interface = try snapshot.freezePrincipal(a, &src.tree, &typed.checked);
    errdefer snapshot.deinit(a, &interface);
    try principal_validation.validate(&interface, source.symbols.entries.items.len + 1, source.units.items.len);
    try principal_validation.validateGraph(a, &interface);
    try checkInterfaceUnits(&interface, units);
    const exports = try a.alloc(D.Export, typed.exports.len);
    errdefer a.free(exports);
    for (typed.exports, exports) |old, *new| {
        new.* = .{ .name = old.name, .target = .{ .unit = old.target.unit, .binding = old.target.binding }, .kind = @fromBackingInt(@intCast(@backingInt(old.kind))), .catalog = old.catalog };
        _ = try mapped(units, new.target.unit);
    }
    var fixities: std.ArrayList(D.Fixity) = .empty;
    defer fixities.deinit(a);
    for (src.tree.roots.items) |id| if (src.tree.node(id).tag == .fixity_decl) {
        const f = src.tree.fixity(id);
        const binding = typed.checked.resolved[id];
        try require(binding != 0 and binding < typed.checked.bindings.len);
        const producer = typed.checked.bindings[binding].external orelse @import("check.zig").ExternalTarget{ .unit = unit, .binding = binding };
        _ = try mapped(units, producer.unit);
        try fixities.append(a, .{ .operator = f.operator, .target = f.target, .precedence = f.precedence, .association = f.association, .named = f.named, .producer = .{ .unit = producer.unit, .binding = producer.binding } });
    };
    var imports: std.ArrayList(u32) = .empty;
    defer imports.deinit(a);
    // The implicit prelude is a real semantic dependency, even without a source
    // import declaration. Source imports retain their declaration order.
    if (src.implicit_prelude) try imports.append(a, try mapped(units, source.prelude_unit));
    for (source.unitImports(unit)) |imported| try imports.append(a, try mapped(units, imported.target));
    const source_imports = try a.alloc(D.ImportResolution, source.unitImports(unit).len);
    errdefer a.free(source_imports);
    var requests_initialized: usize = 0;
    errdefer for (source_imports[0..requests_initialized]) |request| a.free(request.path);
    for (source.unitImports(unit), source_imports) |imported, *request| {
        const target = try mapped(units, imported.target);
        request.* = .{ .path = try a.dupe(u8, source.symbols.get(imported.path)), .target = target };
        requests_initialized += 1;
    }
    const path = try a.dupe(u8, source.filename(unit));
    errdefer a.free(path);
    try require(src.source.len <= std.math.maxInt(u32));
    const own_imports = try imports.toOwnedSlice(a);
    errdefer a.free(own_imports);
    const own_fixities = try fixities.toOwnedSlice(a);
    return .{ .identity = .{ .normalized_path = path, .source_digest = format.digest(src.source), .source_bytes = @intCast(src.source.len), .prelude = unit == source.prelude_unit }, .imports = own_imports, .implicit_prelude = src.implicit_prelude, .source_imports = source_imports, .core = ir, .interface = interface, .exports = exports, .fixities = own_fixities };
}

/// Freshly lower/freeze every successfully checked nonentry source module.
/// Returned slices exclusively own their storage and use artifact unit IDs.
/// Release with dependency_format.deinit(allocator, &result).
pub fn freeze(a: std.mem.Allocator, source: *const project.Project, checked: *const project_check.CheckedProject) Error!D.FrozenDependency {
    return freezeMode(a, source, checked, null);
}

/// Private same-captured-project path. The caller must retain the successful
/// fresh Prepared and the CheckedProject transferred from that same prepare.
/// Only executable Core is copied; principal interfaces are frozen afresh from
/// the exact checked source. No solver or caller evidence is admitted here.
pub fn freezeFromCheckedCore(a: std.mem.Allocator, source: *const project.Project, checked: *const project_check.CheckedProject, prepared: *const partial.Prepared) Error!D.FrozenDependency {
    try require(prepared.cached == 0 and !prepared.source_mode and prepared.entry == source.entry and prepared.prelude == source.prelude_unit);
    try require(prepared.units.len == source.units.items.len and prepared.paths.len == source.units.items.len);
    const identity = prepared.identity.view();
    try require(identity.owners.len == source.units.items.len and identity.symbols.len == source.symbols.entries.items.len + 1);
    for (source.symbols.entries.items, 1..) |_, id| {
        const spelling = identity.symbol(@intCast(id)) orelse return error.InvalidArtifact;
        try require(std.mem.eql(u8, spelling, source.symbols.get(@intCast(id))));
    }
    for (prepared.units, prepared.paths, 1..) |*ir, path, id| {
        const owner = identity.owner(@intCast(id)) orelse return error.InvalidArtifact;
        try require(ir.unit == id and ir.diagnostics.len == 0);
        try require(std.mem.eql(u8, path, source.filename(@intCast(id))) and std.mem.eql(u8, owner, path));
    }
    return freezeMode(a, source, checked, prepared.units);
}

pub fn freezeFromMixedCheckedCore(a: std.mem.Allocator, source: *const project.Project, checked: *const project_check.CheckedProject, prepared: *const partial.Prepared) Error!D.FrozenDependency {
    try checkMixed(source, prepared);
    return freezeMode(a, source, checked, prepared.units);
}
fn checkMixed(source: *const project.Project, prepared: *const partial.Prepared) Error!void {
    try require(source.compiled_reuse.len == source.compiled_modules.len and source.entry == source.units.items.len);
    try require(source.compiled_modules.len + 1 == source.units.items.len and prepared.entry == source.entry and prepared.prelude == source.prelude_unit and !prepared.source_mode);
    try require(prepared.units.len == source.units.items.len and prepared.paths.len == source.units.items.len);
    for (prepared.units, prepared.paths, 1..) |ir, path, id| {
        try require(ir.unit == id and ir.diagnostics.len == 0 and std.mem.eql(u8, path, source.filename(@intCast(id))));
    }
}
fn checkChecked(source: *const project.Project, checked: *const project_check.CheckedProject) Error!void {
    try require(source.diagnostics.items.len == 0 and checked.diagnostics.len == 0);
    try require(source.entry != 0 and source.entry <= source.units.items.len and checked.modules.len == source.units.items.len);
    try require(source.units.items.len <= std.math.maxInt(u32));
    for (checked.modules, 1..) |m, id| if (checked.compiledModule(source, id) == null and !(id == source.entry and checked.entry_cutoff.reused != 0)) {
        try require(m != null and m.?.valid);
    };
}

/// Retained entry-last preparation. The supplied snapshot exclusively controls
/// the lifetime of its immutable module payloads. Sharing grants storage and
/// structural validation reuse only; source/check admission already completed.
pub fn freezeSharedFromMixed(a: std.mem.Allocator, source: *const project.Project, checked: *const project_check.CheckedProject, prepared: *const partial.Prepared, previous: *const retained.Snapshot, reuse_validation: bool, stats: *retained.Stats) Error!*retained.Snapshot {
    try checkMixed(source, prepared);
    try checkChecked(source, checked);
    try require(previous.initialized == previous.modules.len and source.compiled_modules.ptr == previous.value.modules.ptr and source.compiled_modules.len == previous.value.modules.len);
    const symbols = try a.alloc(D.Symbol, source.symbols.entries.items.len + 1);
    @memset(symbols, .{ .text = &.{} });
    var owned_symbols = true;
    defer if (owned_symbols) {
        for (symbols) |symbol| a.free(symbol.text);
        a.free(symbols);
    };
    for (symbols[1..], 1..) |*symbol, id| symbol.text = try a.dupe(u8, source.symbols.get(@intCast(id)));
    const result = try retained.Snapshot.create(a, symbols, source.compiled_modules.len);
    owned_symbols = false;
    errdefer result.deinit();
    const units = try a.alloc(u32, source.units.items.len);
    defer a.free(units);
    for (units, 1..) |*id, index| id.* = if (index == source.entry) 0 else @intCast(index);
    for (0..source.compiled_modules.len) |index| {
        const id: u32 = @intCast(index + 1);
        if (checked.compiledModule(source, id)) |module| {
            try require(module == &previous.value.modules[index]);
            try result.appendShared(previous, index);
            stats.shared_modules += 1;
        } else {
            try result.appendOwned(try freezeOne(a, source, checked, id, units, &prepared.units[index]));
            stats.fresh_modules += 1;
        }
    }
    try validateMode(a, &result.value, result, if (reuse_validation) previous else null, stats);
    try validateSources(&result.value, source);
    result.validated = true;
    return result;
}
fn freezeMode(a: std.mem.Allocator, source: *const project.Project, checked: *const project_check.CheckedProject, retained_cores: ?[]const core.Module) Error!D.FrozenDependency {
    try checkChecked(source, checked);
    var result: D.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
    const units = try a.alloc(u32, source.units.items.len);
    defer a.free(units);
    var count: u32 = 0;
    for (units, 1..) |*id, source_id| {
        id.* = if (source_id == source.entry) 0 else blk: {
            count += 1;
            break :blk count;
        };
    }
    result.symbols = try a.alloc(D.Symbol, source.symbols.entries.items.len + 1);
    @memset(result.symbols, .{ .text = &.{} });
    errdefer {
        for (result.symbols) |s| a.free(s.text);
        a.free(result.symbols);
    }
    for (result.symbols[1..], 1..) |*symbol, id| symbol.text = try a.dupe(u8, source.symbols.get(@intCast(id)));
    result.modules = try a.alloc(D.Module, count);
    var initialized: usize = 0;
    errdefer {
        for (result.modules[0..initialized]) |*m| format.deinit(a, m);
        a.free(result.modules);
    }
    for (units, 1..) |id, source_id| if (id != 0) {
        result.modules[initialized] = if (checked.compiledModule(source, source_id)) |previous|
            try copyCoreValue(a, previous.*)
        else
            try freezeOne(a, source, checked, @intCast(source_id), units, if (retained_cores) |cores| &cores[source_id - 1] else null);
        initialized += 1;
    };
    // When the entry is last, retained units and symbols already have their
    // final ordinals. Leave the owned copies untouched; complete validation
    // below still rejects references to the excluded entry and malformed IDs.
    // Without relocation there are no unchecked map accesses to guard with a
    // second Core traversal. Other entry positions retain both validations.
    if (source.entry != source.units.items.len) {
        const views = try a.alloc(*const core.Module, result.modules.len);
        defer a.free(views);
        for (result.modules, views) |*m, *view| view.* = &m.core;
        // Source identities are checked against only retained siblings. An excluded
        // entry producer can never silently become the reserved unit-zero context.
        for (result.modules) |*m| try core_validation.validate(a, &m.core, .{ .units = views, .symbol_count = result.symbols.len, .source_length = m.identity.source_bytes });
        const names = try a.alloc(u32, result.symbols.len);
        defer a.free(names);
        for (names, 0..) |*name, id| name.* = @intCast(id);
        for (result.modules) |*m| {
            relink.module(&m.core, names, units);
            relink.interface(&m.interface, names, units);
            for (m.exports) |*exported| exported.target.unit = try mapped(units, exported.target.unit);
            for (m.fixities) |*f| f.producer.unit = try mapped(units, f.producer.unit);
        }
    }
    try validate(a, &result);
    try validateSources(&result, source);
    return result;
}

fn external(value: *const D.FrozenDependency, current: usize, target: PI.ExternalTarget) Error!void {
    const unit = if (target.unit == 0) current + 1 else target.unit;
    try require(unit != 0 and unit <= value.modules.len);
    try require(target.binding != 0 and target.binding < value.modules[unit - 1].interface.bindings.len);
}

/// Complete owner validation of a decoded closure before numeric relocation.
/// Provenance/key verification is performed by dependency_format.decode first.
pub fn validate(a: std.mem.Allocator, value: *const D.FrozenDependency) Error!void {
    var stats: retained.Stats = .{};
    return validateMode(a, value, null, null, &stats);
}
fn validateMode(a: std.mem.Allocator, value: *const D.FrozenDependency, current: ?*const retained.Snapshot, previous: ?*const retained.Snapshot, stats: *retained.Stats) Error!void {
    try require(value.symbols.len != 0 and value.symbols[0].text.len == 0);
    var paths: std.StringHashMapUnmanaged(void) = .empty;
    defer paths.deinit(a);
    var prelude_count: usize = 0;
    const prelude_unit: u32 = for (value.modules, 1..) |m, id| {
        if (m.identity.prelude) break @intCast(id);
    } else 0;
    const views = try a.alloc(*const core.Module, value.modules.len);
    defer a.free(views);
    for (value.modules, views, 1..) |*m, *view, id| {
        try require(m.core.unit == id and m.interface.unit == id);
        view.* = &m.core;
    }
    const saved = if (previous) |old| if (old.validated) old else null else null;
    const previous_views: []*const core.Module = if (saved) |old| try a.alloc(*const core.Module, old.value.modules.len) else &.{};
    defer a.free(previous_views);
    if (saved) |old| {
        for (old.value.modules, previous_views) |*module, *view| view.* = &module.core;
    }
    for (value.modules, 0..) |*m, id| {
        const shared = if (saved) |old| if (current) |owner| owner.shares(old, id) else false else false;
        const same_interface_bounds = if (saved) |old| value.symbols.len == old.value.symbols.len and value.modules.len == old.value.modules.len else false;
        try require(std.fs.path.isAbsolute(m.identity.normalized_path));
        const path = try paths.getOrPut(a, m.identity.normalized_path);
        try require(!path.found_existing);
        prelude_count += @intFromBool(m.identity.prelude);
        try require(prelude_count <= 1);
        if (shared and same_interface_bounds) {
            stats.interface_reused += 1;
        } else {
            try principal_validation.validate(&m.interface, value.symbols.len, value.modules.len);
            try principal_validation.validateGraph(a, &m.interface);
            stats.interface_checked += 1;
        }
        const context: core_validation.Context = .{ .units = views, .symbol_count = value.symbols.len, .source_length = m.identity.source_bytes };
        const same_core_context = if (shared) core_validation.equivalentContext(.{ .units = previous_views, .symbol_count = saved.?.value.symbols.len, .source_length = saved.?.value.modules[id].identity.source_bytes }, context) else false;
        if (same_core_context) {
            stats.core_reused += 1;
        } else {
            try core_validation.validate(a, &m.core, context);
            stats.core_checked += 1;
        }
        for (m.core.bodies) |body| try require(!body.exported);
        for (m.imports) |unit| try require(unit != 0 and unit <= value.modules.len and unit != id + 1);
        try require(m.imports.len == m.source_imports.len + @intFromBool(m.implicit_prelude));
        if (m.implicit_prelude) try require(!m.identity.prelude and prelude_unit != 0 and m.imports[0] == prelude_unit);
        for (m.source_imports, m.imports[@intFromBool(m.implicit_prelude)..]) |request, unit| {
            try require(request.target == unit and request.path.len != 0 and request.path.len <= m.identity.source_bytes);
            try require(std.unicode.utf8ValidateSlice(request.path) and std.mem.indexOfScalar(u8, request.path, 0) == null);
        }
        for (m.interface.bindings) |b| if (b.external) |target| try external(value, id, target);
        for (m.exports) |exported| {
            try require(exported.name != 0 and exported.name < value.symbols.len);
            switch (exported.kind) {
                .value => {
                    try external(value, id, exported.target);
                    const unit = if (exported.target.unit == 0) id + 1 else exported.target.unit;
                    const b = value.modules[unit - 1].interface.bindings[exported.target.binding];
                    try require(b.kind == .global and b.name == exported.name);
                },
                .nominal => try require(exported.catalog != 0 and exported.catalog < m.interface.nominals.len and m.interface.nominals[exported.catalog].name == exported.name),
                .constructor => try require(exported.catalog != 0 and exported.catalog < m.interface.constructors.len and m.interface.constructors[exported.catalog].name == exported.name),
                .effect_family => try require(exported.catalog != 0 and exported.catalog < m.interface.effect_families.len and m.interface.effect_families[exported.catalog].name == exported.name),
            }
        }
        for (m.fixities) |f| {
            try require(f.operator != 0 and f.operator < value.symbols.len and f.target != 0 and f.target < value.symbols.len);
            try require(f.precedence <= 255 and f.association <= 2);
            try external(value, id, f.producer);
        }
    }
    try validateImportGraph(a, value);
}

fn validateImportGraph(a: std.mem.Allocator, value: *const D.FrozenDependency) Error!void {
    const colors = try a.alloc(u8, value.modules.len);
    defer a.free(colors);
    @memset(colors, 0);
    const Frame = struct { unit: usize, next: usize = 0 };
    const stack = try a.alloc(Frame, value.modules.len);
    defer a.free(stack);
    for (value.modules, 0..) |_, root| {
        if (colors[root] != 0) continue;
        var len: usize = 1;
        stack[0] = .{ .unit = root };
        colors[root] = 1;
        while (len != 0) {
            const current = &stack[len - 1];
            const imports = value.modules[current.unit].imports;
            if (current.next == imports.len) {
                colors[current.unit] = 2;
                len -= 1;
                continue;
            }
            const child = imports[current.next] - 1;
            current.next += 1;
            if (colors[child] == 1) return error.InvalidArtifact;
            if (colors[child] == 2) continue;
            colors[child] = 1;
            stack[len] = .{ .unit = child };
            len += 1;
        }
    }
}

/// Compare decoded identities and import order against the current source
/// closure. Call before relocation; artifact metadata is never its own key.
pub fn validateSources(value: *const D.FrozenDependency, source: *const project.Project) Error!void {
    try require(source.entry != 0 and source.entry <= source.units.items.len);
    try require(value.modules.len == source.units.items.len - 1);
    for (source.units.items, 1..) |src, source_id| {
        if (source_id == source.entry) continue;
        const id = try ordinal(source, @intCast(source_id));
        const m = &value.modules[id - 1];
        try require(std.mem.eql(u8, m.identity.normalized_path, source.filename(@intCast(source_id))));
        if (source.compiledModule(source_id)) |previous| {
            try require(m.identity.source_bytes == previous.identity.source_bytes and std.mem.eql(u8, &m.identity.source_digest, &previous.identity.source_digest));
        } else try require(m.identity.source_bytes == src.source.len and std.mem.eql(u8, &m.identity.source_digest, &format.digest(src.source)));
        try require(m.identity.prelude == (source_id == source.prelude_unit));
        const prelude = src.implicit_prelude;
        const edges = source.unitImports(@intCast(source_id));
        try require(m.implicit_prelude == prelude and m.source_imports.len == edges.len);
        for (edges, m.source_imports) |edge, request| {
            try require(request.target == try ordinal(source, edge.target));
            try require(std.mem.eql(u8, request.path, source.symbols.get(edge.path)));
        }
        try require(m.imports.len == edges.len + @intFromBool(prelude));
        var next: usize = 0;
        if (prelude) {
            try require(m.imports[0] == try ordinal(source, source.prelude_unit));
            next = 1;
        }
        for (edges) |edge| {
            try require(m.imports[next] == try ordinal(source, edge.target));
            next += 1;
        }
    }
}

fn word(hash: *std.crypto.hash.Blake3, value: u64) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    hash.update(&bytes);
}
fn text(hash: *std.crypto.hash.Blake3, value: []const u8) void {
    word(hash, value.len);
    hash.update(value);
}

/// The settings digest must include every source/check/backend option of the
/// consumer. Entry bytes are excluded; all retained paths, contents, prelude
/// ownership and ordered dependency edges are included with length framing.
pub fn sourceKey(compiler: [32]u8, settings: [32]u8, source: *const project.Project) Error!format.Key {
    try require(source.diagnostics.items.len == 0 and source.entry != 0 and source.entry <= source.units.items.len);
    var content = std.crypto.hash.Blake3.init(.{});
    var edges = std.crypto.hash.Blake3.init(.{});
    text(&content, "dependency-closure-v1");
    text(&edges, "dependency-closure-edges-v2");
    word(&content, source.units.items.len - 1);
    word(&edges, source.units.items.len - 1);
    for (source.units.items, 1..) |src, source_id| {
        if (source_id == source.entry) continue;
        const id = try ordinal(source, @intCast(source_id));
        word(&content, id);
        text(&content, source.filename(@intCast(source_id)));
        word(&content, src.source.len);
        content.update(&format.digest(src.source));
        word(&content, @intFromBool(source_id == source.prelude_unit));
        word(&edges, id);
        const prelude = src.implicit_prelude;
        const imports = source.unitImports(@intCast(source_id));
        word(&edges, @intFromBool(prelude));
        word(&edges, imports.len + @intFromBool(prelude));
        if (prelude) word(&edges, try ordinal(source, source.prelude_unit));
        for (imports) |edge| {
            text(&edges, source.symbols.get(edge.path));
            word(&edges, try ordinal(source, edge.target));
        }
    }
    var source_digest: [32]u8 = undefined;
    var dependency_digest: [32]u8 = undefined;
    content.final(&source_digest);
    edges.final(&dependency_digest);
    return .{ .compiler = compiler, .settings = settings, .source = source_digest, .dependencies = dependency_digest };
}

/// A loader verifies every canonical producer path and current raw file before
/// using its stored import edges. This requires no parsing or checking.
pub fn validateProducer(owner: *const D.Module, canonical_path: []const u8, source: []const u8) Error!void {
    try require(std.mem.eql(u8, owner.identity.normalized_path, canonical_path));
    try require(owner.identity.source_bytes == source.len and std.mem.eql(u8, &owner.identity.source_digest, &format.digest(source)));
}

/// Equivalent to sourceKey after complete validate and validateProducer for
/// every module. Key verification, not this function, admits stored topology.
pub fn payloadKey(compiler: [32]u8, settings: [32]u8, value: *const D.FrozenDependency) format.Key {
    var content = std.crypto.hash.Blake3.init(.{});
    var edges = std.crypto.hash.Blake3.init(.{});
    text(&content, "dependency-closure-v1");
    text(&edges, "dependency-closure-edges-v2");
    word(&content, value.modules.len);
    word(&edges, value.modules.len);
    for (value.modules, 1..) |owner, id| {
        word(&content, id);
        text(&content, owner.identity.normalized_path);
        word(&content, owner.identity.source_bytes);
        content.update(&owner.identity.source_digest);
        word(&content, @intFromBool(owner.identity.prelude));
        word(&edges, id);
        word(&edges, @intFromBool(owner.implicit_prelude));
        word(&edges, owner.imports.len);
        if (owner.implicit_prelude) word(&edges, owner.imports[0]);
        for (owner.source_imports) |request| {
            text(&edges, request.path);
            word(&edges, request.target);
        }
    }
    var source_digest: [32]u8 = undefined;
    var dependency_digest: [32]u8 = undefined;
    content.final(&source_digest);
    edges.final(&dependency_digest);
    return .{ .compiler = compiler, .settings = settings, .source = source_digest, .dependencies = dependency_digest };
}
