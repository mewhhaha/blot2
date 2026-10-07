//! Combine admitted generic modules with newly loaded ordinary source modules.
//! Cached syntax/solvers are never reconstructed; new modules use the same
//! source loader, checker and Core lowering as an ordinary project.
const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const D = @import("frozen_dependency.zig");
const format = @import("dependency_format.zig");
const PI = @import("principal_interface.zig");
const consumer = @import("dependency_consumer.zig");
const purity = @import("purity_diagnostics.zig");
const ast = @import("ast.zig");
const Allocator = std.mem.Allocator;
const RuntimeIdentity = @import("runtime_identity.zig");
const entry_cutoff = @import("entry_frontend_cutoff.zig");

pub const Result = struct {
    result: consumer.Result,
    diagnostic_filename: ?[]u8 = null,
    source_bytes: usize = 0,
    fresh_modules: usize = 0,
    cached_modules: usize = 0,
    pub fn deinit(self: *Result, a: Allocator) void {
        self.result.deinit(a);
        if (self.diagnostic_filename) |path| a.free(path);
        self.* = undefined;
    }
};
/// Source-free owned frontend result for one fresh project revision.
/// Fresh Core, canonical paths and runtime spelling metadata belong to this
/// owner. The cached Core prefix remains borrowed from the admitted seed, which
/// must outlive Prepared. Backend work does not consult source files or PI.
/// This owner grants no cross-revision staging/code-cache validity by itself.
pub const Prepared = struct {
    units: []core.Module,
    identity: RuntimeIdentity.Metadata,
    unit_order: []u32,
    paths: [][]u8,
    cached: usize,
    borrowed: []bool = &.{},
    entry_imports: []entry_cutoff.Import = &.{},
    entry_implicit_prelude: bool = false,
    entry: u32,
    prelude: u32,
    source_mode: bool,
    source_bytes: usize,
    stats: consumer.Stats,
    pub fn deinit(self: *Prepared, a: Allocator) void {
        self.identity.deinit(a);
        a.free(self.unit_order);
        for (self.units, 0..) |*unit, i| if (!self.isBorrowed(i)) {
            unit.deinit(a);
        };
        a.free(self.borrowed);
        a.free(self.entry_imports);
        a.free(self.units);
        for (self.paths) |path| a.free(path);
        a.free(self.paths);
        self.* = undefined;
    }

    fn isBorrowed(self: *const Prepared, index: usize) bool {
        return if (self.borrowed.len != 0) self.borrowed[index] else index < self.cached;
    }
    fn cachedCount(self: *const Prepared) usize {
        if (self.borrowed.len == 0) return self.cached;
        var count: usize = 0;
        for (self.borrowed) |borrowed| count += @intFromBool(borrowed);
        return count;
    }

    /// PRIVATE ownership transfer after freezeFromMixedCheckedCore copied this
    /// exact preparation. Entry-last ordinals and the complete dictionary must
    /// be unchanged: no entry relinking or new source admission happens here.
    /// All guards precede mutation. The new seed must outlive this Prepared.
    pub fn rebindFrozenPrefix(self: *Prepared, a: Allocator, seed: *const D.FrozenDependency) error{InvalidArtifact}!void {
        const names = self.identity.view();
        if (self.source_mode or self.units.len == 0 or self.units.len > std.math.maxInt(u32) or self.entry != self.units.len or seed.modules.len != self.units.len - 1 or self.paths.len != self.units.len or names.owners.len != self.units.len or names.symbols.len != seed.symbols.len or seed.symbols.len == 0) return error.InvalidArtifact;
        if (self.borrowed.len != 0 and self.borrowed.len != self.units.len) return error.InvalidArtifact;
        if (self.isBorrowed(self.entry - 1)) return error.InvalidArtifact;
        for (seed.symbols, 0..) |symbol, id| {
            if (id == 0) {
                if (symbol.text.len != 0) return error.InvalidArtifact;
            } else if (!std.mem.eql(u8, names.symbol(@intCast(id)) orelse return error.InvalidArtifact, symbol.text)) return error.InvalidArtifact;
        }
        for (seed.modules, 0..) |*module, index| {
            const id: u32 = @intCast(index + 1);
            if (module.core.unit != id or module.interface.unit != id or self.units[index].unit != id or module.core.diagnostics.len != 0) return error.InvalidArtifact;
            if (!std.mem.eql(u8, self.paths[index], module.identity.normalized_path) or !std.mem.eql(u8, names.owner(id) orelse return error.InvalidArtifact, module.identity.normalized_path)) return error.InvalidArtifact;
        }
        for (seed.modules, 0..) |*module, index| {
            if (!self.isBorrowed(index)) self.units[index].deinit(a);
            self.units[index] = module.core;
            if (self.borrowed.len != 0) self.borrowed[index] = true;
        }
        self.cached = seed.modules.len;
    }
    /// Borrows Prepared and its cached Core seed. Every returned byte and
    /// diagnostic filename belongs to the new emission result. The allocator
    /// may differ from Prepared's owner because no retained input is mutated.
    pub fn emit(self: *const Prepared, a: Allocator) !Result {
        return self.emitWithOptions(a, .{});
    }
    pub fn emitWithOptions(self: *const Prepared, a: Allocator, options: backend.CompileOptions) !Result {
        var actual = options;
        actual.identity = self.identity.view();
        actual.unit_order = self.unit_order;
        actual.diagnostic_prelude_unit = self.prelude;
        actual.diagnostic_source_mode = self.source_mode;
        var compiled = try backend.compileWithOptions(a, self.units, self.entry, actual);
        errdefer compiled.deinit(a);
        var filename: ?[]u8 = null;
        if (compiled.diagnostic) |issue| {
            if (issue.unit == 0 or issue.unit > self.paths.len) return error.InvalidUnit;
            filename = try a.dupe(u8, self.paths[issue.unit - 1]);
        }
        return .{ .result = .{ .compiled = compiled, .stats = self.stats }, .diagnostic_filename = filename, .source_bytes = self.source_bytes, .fresh_modules = self.units.len - self.cachedCount(), .cached_modules = self.cachedCount() };
    }
};

/// Both cases own their fresh allocations. Match and move one case or destroy
/// the union; the admitted seed's Core/PI owner is always retained by the caller.
pub const Preparation = union(enum) {
    ready: Prepared,
    rejected: Result,
    pub fn deinit(self: *Preparation, a: Allocator) void {
        switch (self.*) {
            .ready => |*prepared| prepared.deinit(a),
            .rejected => |*result| result.deinit(a),
        }
        self.* = undefined;
    }
};
fn reject(a: Allocator, source: *const project.Project, entry_path: []const u8, diagnostic: consumer.Diagnostic) !Preparation {
    var owned = diagnostic;
    errdefer owned.deinit(a);
    const path = if (owned.unit == 0) entry_path else source.filename(owned.unit);
    // Invalid loader settings can reject before any seed module is installed.
    // Count actual installed units rather than the borrowed seed's capacity.
    const cached = @min(source.units.items.len, source.compiledCount());
    return .{ .rejected = .{ .result = .{ .compiled = .{}, .stats = .{ .syntax_nodes = 0, .body_elaborations = 0, .body_lowerings = 0, .imported_schemes = 0 }, .diagnostic = owned }, .diagnostic_filename = try a.dupe(u8, path), .source_bytes = source.source_bytes, .fresh_modules = source.units.items.len - cached, .cached_modules = cached } };
}
/// Cached loader order contains fresh units only. Reconstruct the complete
/// source catalog order from the admitted import skeleton while it is owned;
/// no cached source text, syntax or PI is reopened. Prelude roots finish first.
fn sourceOrder(a: Allocator, source: *const project.Project) ![]u32 {
    const states = try a.alloc(u8, source.units.items.len);
    defer a.free(states);
    @memset(states, 0);
    const Frame = struct { unit: u32, next: usize = 0 };
    var stack: std.ArrayList(Frame) = .empty;
    defer stack.deinit(a);
    var order: std.ArrayList(u32) = .empty;
    defer order.deinit(a);
    for ([_]u32{ source.prelude_unit, source.entry }) |root| {
        if (root == 0) continue;
        if (root > states.len) return error.InvalidUnit;
        if (states[root - 1] == 2) continue;
        states[root - 1] = 1;
        try stack.append(a, .{ .unit = root });
        while (stack.items.len != 0) {
            const position = stack.items.len - 1;
            const frame = stack.items[position];
            const unit = source.unit(frame.unit);
            const implicit: usize = if (unit.implicit_prelude) 1 else 0;
            const imports = source.unitImports(frame.unit);
            if (frame.next == implicit + imports.len) {
                states[frame.unit - 1] = 2;
                try order.append(a, frame.unit);
                _ = stack.pop();
                continue;
            }
            stack.items[position].next += 1;
            const target = if (frame.next < implicit) source.prelude_unit else imports[frame.next - implicit].target;
            if (target == 0 or target > states.len or states[target - 1] == 1) return error.InvalidUnit;
            if (states[target - 1] == 2) continue;
            states[target - 1] = 1;
            try stack.append(a, .{ .unit = target });
        }
    }
    if (order.items.len != states.len) return error.DependencySetChanged;
    return order.toOwnedSlice(a);
}

/// Loads/checks/lowers fresh source against an admitted unchanged seed. All
/// Project, source, syntax and solver owners are destroyed before returning.
/// The caller must validate seed wire/compiler/settings/source/import identity.
/// Success borrows seed Core and preserves PI; rejection publishes only owned
/// diagnostic metadata and leaves every previously prepared revision intact.
pub fn prepare(a: Allocator, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, options: project.Options, dependency: *D.FrozenDependency) !Preparation {
    var source = try project.loadCompiled(a, io, entry_path, options, dependency);
    defer source.deinit(a);
    return prepareProject(a, &source, entry_path, output_identity, dependency);
}

pub fn prepareReadOnly(a: Allocator, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, options: project.Options, dependency: *const D.FrozenDependency, inputs: ?project.InputProvider) !Preparation {
    var source = try project.loadCompiledReadOnly(a, io, entry_path, options, dependency, inputs);
    defer source.deinit(a);
    // Additional source producers change the catalog and must be checked in
    // the full fresh closure before any cached interfaces are consumed.
    if (source.units.items.len != dependency.modules.len + 1) return error.DependencySetChanged;
    return prepareProject(a, &source, entry_path, output_identity, dependency);
}

/// Consumes no Project storage. Cached Core is borrowed from the dense prefix;
/// passing an empty dependency prepares an entirely fresh checked Project.
pub fn prepareProject(a: Allocator, source: *project.Project, entry_path: []const u8, output_identity: ?[]const u8, dependency: *const D.FrozenDependency) !Preparation {
    return prepareProjectMode(a, source, entry_path, output_identity, dependency, null, null);
}

/// Retain the exact successful checker owner for this already captured Project.
/// Rejection and errors keep the caller's output null. The caller must destroy
/// the check before the source and must not use it with a different Project.
pub fn prepareProjectKeepingCheck(a: Allocator, source: *project.Project, entry_path: []const u8, output_identity: ?[]const u8, dependency: *const D.FrozenDependency, kept: *?checker.CheckedProject) !Preparation {
    std.debug.assert(kept.* == null);
    return prepareProjectMode(a, source, entry_path, output_identity, dependency, kept, null);
}

pub const EntryPrevious = struct { prepared: *const Prepared, source: []const u8, reuse_modules: bool = false };
pub fn prepareProjectKeepingEntry(a: Allocator, source: *project.Project, entry_path: []const u8, output_identity: ?[]const u8, dependency: *const D.FrozenDependency, kept: *?checker.CheckedProject, previous: ?EntryPrevious) !Preparation {
    std.debug.assert(kept.* == null);
    return prepareProjectMode(a, source, entry_path, output_identity, dependency, kept, previous);
}
fn prepareProjectMode(a: Allocator, source: *project.Project, entry_path: []const u8, output_identity: ?[]const u8, dependency: *const D.FrozenDependency, kept: ?*?checker.CheckedProject, previous: ?EntryPrevious) !Preparation {
    if (source.compiled_modules.len != dependency.modules.len) return error.InvalidArtifact;
    if (source.diagnostics.items.len != 0) {
        const issue = source.diagnostics.items[0];
        if (issue.publication) |publication| {
            const unit = source.unit(issue.unit);
            const diagnostic = if (issue.parse_code != null)
                try consumer.publishedDiagnostic(a, issue.unit, "parse-project", unit.source, publication, unit.tree.diagnostics.items)
            else
                try consumer.publishedDiagnostic(a, issue.unit, "parse-project", unit.source, publication, issue.lexical_details);
            return reject(a, source, entry_path, diagnostic);
        }
        return reject(a, source, entry_path, try consumer.Diagnostic.init(a, issue.unit, "load", issue.codeName(), issue.span, issue.message()));
    }
    if (output_identity) |output| for (source.units.items) |unit| {
        if (std.mem.eql(u8, output, source.symbols.get(unit.filename))) return error.OutputIsSource;
    };
    var checked = if (previous) |old|
        try checker.checkProjectWithEntryCutoff(a, source, .{ .entry = old.prepared.entry, .prelude = old.prepared.prelude, .implicit_prelude = old.prepared.entry_implicit_prelude, .names = old.prepared.identity.view(), .source = old.source, .imports = old.prepared.entry_imports, .reuse_modules = old.reuse_modules })
    else
        try checker.checkProject(a, source);
    var check_transferred = false;
    defer if (!check_transferred) checked.deinit(a);
    if (checked.diagnostics.len != 0) {
        const issue = checked.diagnostics[0];
        const unit = source.unit(issue.unit);
        if (issue.hole) |hole| return reject(a, source, entry_path, try consumer.publishedDiagnostic(a, issue.unit, "check-project", unit.source, .{ .cause = .native_detail, .code = issue.codeName(), .span = issue.span, .message = issue.message() }, .{ .hole = hole }));
        if (issue.numeric_literal) |detail| return reject(a, source, entry_path, try consumer.publishedDiagnostic(a, issue.unit, "check-project", unit.source, .{ .cause = .native_detail, .code = issue.codeName(), .span = issue.span, .message = issue.message(), .actual_token = detail.actual_token }, @as([]const ast.NumericFault, &.{detail})));
        if (issue.purity) |witness| {
            if (witness.operation_name == null and !witness.foreign) return error.OperationPurityOriginRequired;
            const message = try purity.format(a, &source.symbols, "", witness);
            defer a.free(message);
            return reject(a, source, entry_path, try consumer.publishedDiagnostic(a, issue.unit, "check-project", unit.source, .{ .cause = .native_detail, .code = issue.codeName(), .span = issue.span, .message = message }, @as([]const @import("check.zig").PurityWitness, &.{witness})));
        }
        const message = if (issue.symbol != 0)
            try a.print("{s}{s}{s}", .{ issue.message(), if (std.mem.eql(u8, issue.codeName(), "unknown_intrinsic") or std.mem.eql(u8, issue.codeName(), "unknown_record_field")) " " else ": ", source.symbols.get(issue.symbol) })
        else
            try a.dupe(u8, issue.message());
        defer a.free(message);
        return reject(a, source, entry_path, try consumer.Diagnostic.init(a, issue.unit, "check-project", issue.codeName(), issue.span, message));
    }
    const units = try a.alloc(core.Module, source.units.items.len);
    var initialized: usize = 0;
    var transferred = false;
    defer if (!transferred) {
        for (units[0..initialized], 1..) |*unit, id| if (checked.compiledModule(source, id) == null) {
            unit.deinit(a);
        };
        a.free(units);
    };
    const paths = try a.alloc([]u8, units.len);
    var paths_initialized: usize = 0;
    defer if (!transferred) {
        for (paths[0..paths_initialized]) |path| a.free(path);
        a.free(paths);
    };
    var stats: consumer.Stats = .{ .syntax_nodes = 0, .body_elaborations = checked.body_elaborations, .body_lowerings = 0, .imported_schemes = checked.imported_schemes };
    for (source.units.items, units, paths, 1..) |*unit, *ir, *path, id| {
        path.* = try a.dupe(u8, source.filename(@intCast(id)));
        paths_initialized += 1;
        if (checked.compiledModule(source, id) != null) {
            ir.* = dependency.modules[id - 1].core;
        } else {
            if (id == source.entry and checked.entry_cutoff.reused != 0) {
                // The candidate owns this complete copy. Commit may destroy the
                // previous Prepared and all of its immutable source pins.
                ir.* = try @import("dependency_closure.zig").copyCore(a, &previous.?.prepared.units[id - 1]);
            } else {
                ir.* = try core.lowerWithOrigins(a, &unit.tree, &source.symbols, &checked.module(@intCast(id)).checked, .{ .context = source, .lookup = checker.diagnosticModuleOrigin });
                ir.unit = @intCast(id);
                stats.body_lowerings += ir.body_lowerings;
            }
        }
        // Reusing semantic results does not undo parsing already performed by
        // the mixed loader. Count every tree that was actually parsed.
        if (source.compiledModule(id) == null) stats.syntax_nodes += unit.tree.nodes.items.len - 1;
        initialized += 1;
        if (ir.diagnostics.len != 0) {
            const issue = ir.diagnostics[0];
            return reject(a, source, entry_path, try consumer.Diagnostic.init(a, @intCast(id), "lower", @tagName(issue.code), issue.span, issue.message()));
        }
    }
    // Capture spelling and canonical producer owners while the mixed project's
    // source symbol pool is live. This separate owner survives every frontend
    // and solver teardown, including cached PI consumption before emission.
    const owners = try a.alloc(RuntimeIdentity.Owner, units.len);
    defer a.free(owners);
    for (owners, 1..) |*owner, unit| owner.* = .{ .unit = @intCast(unit), .path = source.filename(@intCast(unit)) };
    const unit_order = try sourceOrder(a, source);
    errdefer a.free(unit_order);
    const identity = try RuntimeIdentity.Metadata.capture(a, &source.symbols, owners, units.len);
    errdefer {
        var owned_identity = identity;
        owned_identity.deinit(a);
    }
    const entry_imports = try a.alloc(entry_cutoff.Import, source.unitImports(source.entry).len);
    errdefer a.free(entry_imports);
    for (source.unitImports(source.entry), entry_imports) |from, *to| to.* = .{ .path = from.path, .target = from.target };
    const borrowed: []bool = if (source.compiled_reuse.len != 0) try a.alloc(bool, units.len) else &.{};
    for (borrowed, 1..) |*item, id| item.* = checked.compiledModule(source, id) != null;
    if (kept) |out| {
        out.* = checked;
        check_transferred = true;
    }
    transferred = true;
    return .{ .ready = .{ .units = units, .identity = identity, .unit_order = unit_order, .paths = paths, .cached = dependency.modules.len, .borrowed = borrowed, .entry_imports = entry_imports, .entry_implicit_prelude = source.unit(source.entry).implicit_prelude, .entry = source.entry, .prelude = source.prelude_unit, .source_mode = source.input_mode == .source, .source_bytes = source.source_bytes, .stats = stats } };
}

/// Dependency owner is borrowed throughout. All new frontend/solver owners are
/// destroyed before backend specialization and all fresh Core is freed afterward.
fn compileMode(a: Allocator, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, options: project.Options, dependency: *D.FrozenDependency, consume_interfaces: bool) !Result {
    switch (try prepare(a, io, entry_path, output_identity, options, dependency)) {
        .rejected => |result| return result,
        .ready => |value| {
            var ready = value;
            defer ready.deinit(a);
            if (consume_interfaces) for (dependency.modules) |*module| {
                format.deinit(a, &module.interface);
                module.interface = std.mem.zeroes(PI.Interface);
            };
            return ready.emit(a);
        },
    }
}

/// Borrowing compilation preserves every admitted principal interface.
pub fn compile(a: Allocator, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, options: project.Options, dependency: *D.FrozenDependency) !Result {
    return compileMode(a, io, entry_path, output_identity, options, dependency, false);
}

/// Successful fresh lowering ends the dependency principal-interface lifetime
/// before specialization. The bundle can then only be destroyed, not reused or
/// encoded. Frontend rejection leaves all seed interfaces intact.
pub fn compileOwned(a: Allocator, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, options: project.Options, dependency: *D.FrozenDependency) !Result {
    return compileMode(a, io, entry_path, output_identity, options, dependency, true);
}
