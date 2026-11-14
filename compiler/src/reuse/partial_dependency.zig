//! Combine admitted generic modules with newly loaded ordinary source modules.
//! Cached syntax/solvers are never reconstructed; new modules use the same
//! source loader, checker and Core lowering as an ordinary project.
const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const core = @import("../check/core.zig");
const core_builder = @import("../check/core_builder.zig");
const backend = @import("../compile.zig");
const D = @import("frozen_dependency.zig");
const format = @import("dependency_format.zig");
const PI = @import("principal_interface.zig");
const consumer = @import("dependency_consumer.zig");
const purity = @import("purity_diagnostics.zig");
const ast = @import("../parse/ast.zig");
const Allocator = std.mem.Allocator;
const parallel_lowering = @import("../check/parallel_lowering.zig");

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
/// Source-free owned frontend result for one project build. Fresh Core and
/// canonical paths belong to this owner. The cached Core prefix remains
/// borrowed from the admitted seed, which must outlive Prepared.
pub const Prepared = struct {
    units: []core.Module,
    paths: [][]u8,
    borrowed: []bool,
    entry: u32,
    source_bytes: usize,
    stats: consumer.Stats,
    pub fn deinit(self: *Prepared, a: Allocator) void {
        for (self.units, self.borrowed) |*unit, borrowed| if (!borrowed) unit.deinit(a);
        a.free(self.borrowed);
        a.free(self.units);
        for (self.paths) |path| a.free(path);
        a.free(self.paths);
        self.* = undefined;
    }
    fn cachedCount(self: *const Prepared) usize {
        var count: usize = 0;
        for (self.borrowed) |borrowed| count += @intFromBool(borrowed);
        return count;
    }
    /// Borrows Prepared and its cached Core seed. Every returned byte and
    /// diagnostic filename belongs to the new result.
    pub fn emit(self: *const Prepared, a: Allocator) !Result {
        var compiled = try backend.compile(a, self.units, self.entry);
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

/// Loads/checks/lowers fresh source against an admitted unchanged seed. All
/// Project, source, syntax and solver owners are destroyed before returning.
/// The caller must validate seed wire/compiler/settings/source/import identity.
pub fn prepare(a: Allocator, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, options: project.Options, dependency: *D.FrozenDependency) !Preparation {
    var source = try project.loadCompiled(a, io, entry_path, options, dependency);
    defer source.deinit(a);
    return prepareProject(a, &source, entry_path, output_identity, dependency);
}

/// Consumes no Project storage. Cached Core is borrowed from the dense prefix;
/// passing an empty dependency prepares an entirely fresh checked Project.
/// A rejection publishes only the first diagnostic.
pub fn prepareProject(a: Allocator, source: *project.Project, entry_path: []const u8, output_identity: ?[]const u8, dependency: *const D.FrozenDependency) !Preparation {
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
    // Checking stops at the first module that reports a diagnostic.
    var checked = try checker.checkProjectToFirstDiagnostic(a, source, null, false);
    defer checked.deinit(a);
    if (checked.diagnostics.len != 0) return rejectChecked(a, source, entry_path, checked.diagnostics[0]);
    const units = try a.alloc(core.Module, source.units.items.len);
    var initialized: usize = 0;
    const borrowed = a.alloc(bool, units.len) catch |err| {
        a.free(units);
        return err;
    };
    @memset(borrowed, false);
    var transferred = false;
    defer if (!transferred) {
        for (units[0..initialized], borrowed[0..initialized]) |*unit, kept| if (!kept) unit.deinit(a);
        a.free(borrowed);
        a.free(units);
    };
    const paths = try a.alloc([]u8, units.len);
    var paths_initialized: usize = 0;
    defer if (!transferred) {
        for (paths[0..paths_initialized]) |path| a.free(path);
        a.free(paths);
    };
    var stats: consumer.Stats = .{ .syntax_nodes = 0, .body_elaborations = checked.body_elaborations, .body_lowerings = 0, .imported_schemes = checked.imported_schemes, .normalization = checked.normalization };
    var lowered = try lowerFresh(a, source, &checked);
    defer if (lowered) |*batch| batch.deinit();
    for (source.units.items, units, paths, 1..) |*unit, *ir, *path, id| {
        path.* = try a.dupe(u8, source.filename(@intCast(id)));
        paths_initialized += 1;
        if (checked.compiledModule(source, id)) |module| {
            if (module == &source.compiled_modules[id - 1]) {
                ir.* = module.core;
                borrowed[id - 1] = true;
            } else ir.* = try @import("dependency_closure.zig").copyCore(a, &module.core);
        } else {
            const timing = @import("../phase_profile.zig").enter(.lower);
            defer timing.exit();
            ir.* = if (lowered) |*batch|
                try batch.take(id - 1)
            else
                try core_builder.lowerWithOrigins(a, &unit.tree, &source.symbols, &checked.module(@intCast(id)).checked, .{ .context = source, .lookup = checker.diagnosticModuleOrigin });
            ir.unit = @intCast(id);
            stats.body_lowerings += ir.body_lowerings;
            stats.syntax_nodes += unit.tree.nodes.items.len - 1;
        }
        initialized += 1;
        if (ir.diagnostics.len != 0) {
            const issue = ir.diagnostics[0];
            return reject(a, source, entry_path, try consumer.Diagnostic.init(a, @intCast(id), "lower", @tagName(issue.code), issue.span, issue.message()));
        }
    }
    transferred = true;
    return .{ .ready = .{ .units = units, .paths = paths, .borrowed = borrowed, .entry = source.entry, .source_bytes = source.source_bytes, .stats = stats } };
}

fn rejectChecked(a: Allocator, source: *const project.Project, entry_path: []const u8, issue: checker.Diagnostic) !Preparation {
    const unit = source.unit(issue.unit);
    const contexts = issue.contexts[0..issue.context_len];
    if (issue.hole) |hole| return reject(a, source, entry_path, try consumer.publishedDiagnostic(a, issue.unit, "check-project", unit.source, .{ .cause = .native_detail, .code = issue.codeName(), .span = issue.span, .message = issue.message() }, .{ .hole = hole }));
    if (issue.explanation) |explanation| return reject(a, source, entry_path, try consumer.publishedDiagnostic(a, issue.unit, "check-project", unit.source, .{ .cause = .native_detail, .code = issue.codeName(), .span = issue.span, .message = issue.message() }, .{ .explanation = explanation, .contexts = contexts }));
    if (contexts.len != 0) return reject(a, source, entry_path, try consumer.publishedDiagnostic(a, issue.unit, "check-project", unit.source, .{ .cause = .native_detail, .code = issue.codeName(), .span = issue.span, .message = issue.message() }, .{ .contexts = contexts }));
    if (issue.numeric_literal) |detail| return reject(a, source, entry_path, try consumer.publishedDiagnostic(a, issue.unit, "check-project", unit.source, .{ .cause = .native_detail, .code = issue.codeName(), .span = issue.span, .message = issue.message(), .actual_token = detail.actual_token }, @as([]const ast.NumericFault, &.{detail})));
    if (issue.purity) |witness| {
        if (witness.operation_name == null and !witness.foreign) return error.OperationPurityOriginRequired;
        const message = try purity.format(a, &source.symbols, "", witness);
        defer a.free(message);
        return reject(a, source, entry_path, try consumer.publishedDiagnostic(a, issue.unit, "check-project", unit.source, .{ .cause = .native_detail, .code = issue.codeName(), .span = issue.span, .message = message }, @as([]const @import("../check/check.zig").PurityWitness, &.{witness})));
    }
    const message = if (issue.symbol != 0)
        try a.print("{s}{s}{s}", .{ issue.message(), if (std.mem.eql(u8, issue.codeName(), "unknown_intrinsic") or std.mem.eql(u8, issue.codeName(), "unknown_record_field")) " " else ": ", source.symbols.get(issue.symbol) })
    else
        try a.dupe(u8, issue.message());
    defer a.free(message);
    return reject(a, source, entry_path, try consumer.Diagnostic.init(a, issue.unit, "check-project", issue.codeName(), issue.span, message));
}

/// Lowers on workers, when the project allows it, exactly the units the
/// preparation loop lowers itself; that loop then takes them in unit order.
fn lowerFresh(a: Allocator, source: *const project.Project, checked: *const checker.CheckedProject) !?parallel_lowering.Batch {
    if (source.lowering.workers <= 1) return null;
    const inputs = try a.alloc(?parallel_lowering.Input, source.units.items.len);
    defer a.free(inputs);
    for (inputs, source.units.items, 1..) |*input, *unit, id| {
        const fresh = checked.compiledModule(source, id) == null;
        input.* = if (fresh) .{ .tree = &unit.tree, .checked = &checked.module(@intCast(id)).checked } else null;
    }
    const timing = @import("../phase_profile.zig").enter(.lower);
    defer timing.exit();
    return parallel_lowering.Batch.run(a, source.lowering.io, source.lowering.workers, &source.symbols, .{ .context = source, .lookup = checker.diagnosticModuleOrigin }, inputs);
}

/// Dependency owner is borrowed throughout. All new frontend/solver owners are
/// destroyed before code generation and all fresh Core is freed afterward.
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
/// before code generation. The bundle can then only be destroyed, not reused
/// or encoded. Frontend rejection leaves all seed interfaces intact.
pub fn compileOwned(a: Allocator, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, options: project.Options, dependency: *D.FrozenDependency) !Result {
    return compileMode(a, io, entry_path, output_identity, options, dependency, true);
}
