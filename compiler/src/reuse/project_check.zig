//! Separate module semantic regions. Import aliases resolve to structured
//! producer identities; source trees and written names are never rewritten.
const std = @import("std");
const project = @import("project.zig");
const check = @import("../check/check.zig");
const ast = @import("../parse/ast.zig");
const symbols = @import("../parse/symbols.zig");
const Allocator = std.mem.Allocator;
const PI = @import("principal_interface.zig");
const profile = @import("../phase_profile.zig");

pub const EditorQuery = struct {
    unit: project.UnitId,
    marker: check.EditorMarker,
    budget: *@import("completion_fit.zig").Budget,
};

pub const Export = struct { name: symbols.Symbol, target: check.ExternalTarget = .{ .unit = 0, .binding = 0 }, kind: enum { value, nominal, constructor, effect_family, contract, implementation } = .value, catalog: u32 = 0 };
pub const Module = struct {
    checked: check.Checked,
    exports: []Export,
    valid: bool,

    fn deinit(self: *Module, allocator: Allocator) void {
        self.checked.deinit(allocator);
        allocator.free(self.exports);
    }
};
pub const Code = enum { resolution_budget, source_validation, semantic, duplicate_name, unknown_export, entry_module, declaration_modifier, dependency_failed };
pub const Diagnostic = struct {
    unit: project.UnitId,
    span: ast.Span,
    code: Code,
    semantic: ?check.Code = null,
    type_application: ?check.Diagnostic.TypeApplication = null,
    symbol: symbols.Symbol = 0,
    implicit_type_witness: bool = false,
    source_terminator: check.Diagnostic.Terminator = .none,
    numeric_literal: ?ast.NumericFault = null,
    purity: ?check.PurityWitness = null,
    detail: ?[]const u8 = null,
    hole: ?@import("hole_diagnostics.zig").Snapshot = null,
    explanation: ?@import("dispatch_explanation.zig").Explanation = null,
    contexts: [2]check.Diagnostic.Context = .{
        .{ .kind = .callee, .span = .{ .start = 0, .end = 0 } },
        .{ .kind = .argument, .span = .{ .start = 0, .end = 0 } },
    },
    context_len: u8 = 0,
    source: ?project.Diagnostic = null,

    pub fn codeName(self: Diagnostic) []const u8 {
        if (self.semantic) |code| return @tagName(code);
        if (self.source) |source| return source.codeName();
        return @tagName(self.code);
    }
    pub fn message(self: Diagnostic) []const u8 {
        if (self.detail) |detail| return detail;
        if (self.semantic) |code| return (check.Diagnostic{ .code = code, .node = 0, .span = self.span, .type_application = self.type_application, .symbol = self.symbol, .implicit_type_witness = self.implicit_type_witness, .source_terminator = self.source_terminator }).message();
        if (self.source) |source| return source.message();
        return switch (self.code) {
            .resolution_budget => "Module forwarding resolution budget exhausted",
            .source_validation => "Source loading or parsing failed",
            .semantic => "Module semantic checking failed",
            .duplicate_name => "Import aliases cannot collide with another alias or a local declaration",
            .unknown_export => "Imported module does not export this declaration",
            .entry_module => "Only the entry module may declare host entries",
            .declaration_modifier => "Unknown top-level declaration modifier",
            .dependency_failed => "Imported module has no successful semantic interface",
        };
    }
};
pub const CheckedProject = struct {
    // Index is UnitId-1, independent of dependency-first evaluation order.
    modules: []?Module = &.{},
    diagnostics: []Diagnostic = &.{},
    body_elaborations: usize = 0,
    imported_schemes: usize = 0,
    normalization: @import("../work_counters.zig").Normalization = .{},

    pub fn deinit(self: *CheckedProject, allocator: Allocator) void {
        for (self.modules) |*item| if (item.*) |*module_| module_.deinit(allocator);
        allocator.free(self.modules);
        for (self.diagnostics) |diagnostic| {
            if (diagnostic.purity) |witness| witness.deinit(allocator);
            if (diagnostic.detail) |detail| allocator.free(detail);
            if (diagnostic.hole) |hole| hole.deinit(allocator);
            if (diagnostic.explanation) |explanation| explanation.deinit(allocator);
        }
        allocator.free(self.diagnostics);
        self.* = .{};
    }
    pub fn module(self: *const CheckedProject, unit: project.UnitId) *const Module {
        std.debug.assert(unit != 0);
        if (self.modules[unit - 1]) |*module_| return module_;
        unreachable;
    }
    pub fn interface(self: *const CheckedProject, target: check.ExternalTarget) check.SchemeInterface {
        const producer = &self.module(target.unit).checked;
        return .{ .producer_binding = target.binding, .proof_contract = check.checkedProofContract(producer, target.binding), .types = .{ .store = &producer.types }, .scheme = producer.bindings[target.binding].scheme, .summary = if (producer.bindings[target.binding].summary.shareable) producer.bindings[target.binding].summary else null, .capability_flow = producer.bindings[target.binding].capability_flow, .capability_parameters = producer.bindings[target.binding].capability_parameters, .named_function = producer.bindings[target.binding].named_function, .obligations = producer.obligations, .callees = .{ .live = producer } };
    }
};

fn moduleOrigin(context: ?*const anyopaque, allocator: Allocator, unit: u32) @import("../check/types.zig").Error![]u8 {
    const loaded: *const project.Project = @ptrCast(@alignCast(context orelse return error.TypeLimit));
    if (unit == loaded.prelude_unit and unit != 0) return allocator.dupe(u8, "std/prelude");
    if (loaded.input_mode == .source and unit == loaded.entry) return allocator.dupe(u8, "main");
    if (unit == 0 or unit > loaded.units.items.len) return error.TypeLimit;
    const directory = std.Io.Dir.path.dirname(loaded.filename(loaded.entry)) orelse return error.TypeLimit;
    return std.Io.Dir.path.relativeAlloc(allocator, directory, null, directory, loaded.filename(unit));
}

fn moduleSourceAvailable(context: ?*const anyopaque, unit: u32) bool {
    const loaded: *const project.Project = @ptrCast(@alignCast(context orelse return false));
    return unit != 0 and unit <= loaded.units.items.len and loaded.compiledModule(unit) == null;
}
pub fn diagnosticModuleOrigin(context: ?*const anyopaque, allocator: Allocator, unit: u32) @import("../check/types.zig").Error![]u8 {
    return moduleOrigin(context, allocator, unit);
}

const Engine = struct {
    allocator: Allocator,
    source: *project.Project,
    result: CheckedProject,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    source_validation: bool = false,
    prepare_names: bool = false,
    execution: check.PrivateExecution = .{},
    resolution_remaining: usize = 1_000_000,
    associated_remaining: usize = 1_000_000,
    editor: ?EditorQuery = null,
    source_modules: []?SourceModule = &.{},
    compiled_catalogs: []CompiledCatalog = &.{},
    const CompiledCatalog = struct { exports: []Export = &.{}, declarations: []check.SourceDeclaration = &.{} };
    const SourceModule = struct { validation: check.SourceValidation, exports: []Export, valid: bool };
    const CatalogModule = struct {
        owner: union(enum) { typed: *const check.Checked, source: *const check.SourceValidation, frozen: *const PI.Interface },
        exports: []const Export,
        valid: bool,
        fn catalog(self: CatalogModule) check.DeclarationCatalog {
            return switch (self.owner) {
                .typed => |typed| check.declarationCatalog(typed),
                .source => |source| check.declarationCatalog(source),
                .frozen => |frozen| (check.ImportedCatalog{ .frozen = frozen, .kind = .catalog, .index = 0, .origin = 0 }).catalog(),
            };
        }
        fn declaration(self: CatalogModule, binding: check.BindingId) check.SourceDeclaration {
            return switch (self.owner) {
                .typed => |typed| check.sourceDeclaration(typed.bindings[binding]),
                .source => |source| source.declarations[binding],
                .frozen => |frozen| (check.ImportedCatalog{ .frozen = frozen, .kind = .catalog, .index = 0, .origin = 0 }).declaration(binding),
            };
        }
        fn resolved(self: CatalogModule, node: ast.Id) check.BindingId {
            return switch (self.owner) {
                .typed => |typed| typed.resolved[node],
                .source => |source| source.resolved[node],
                .frozen => unreachable,
            };
        }
    };

    fn catalogModule(self: *const Engine, unit: project.UnitId) ?CatalogModule {
        if (unit == 0) return null;
        if (self.source.compiledModule(unit)) |compiled| return .{ .owner = .{ .frozen = &compiled.interface }, .exports = self.compiled_catalogs[unit - 1].exports, .valid = true };
        if (self.source_validation) {
            if (self.source_modules[unit - 1]) |*module_| return .{ .owner = .{ .source = &module_.validation }, .exports = module_.exports, .valid = module_.valid };
        } else if (self.result.modules[unit - 1]) |*module_| return .{ .owner = .{ .typed = &module_.checked }, .exports = module_.exports, .valid = module_.valid };
        return null;
    }
    fn valueImport(self: *const Engine, target: check.ExternalTarget, origin: ast.Id) check.ImportedBinding {
        std.debug.assert(!self.source_validation);
        const interface = if (self.source.compiledModule(target.unit)) |compiled| (check.ImportedCatalog{ .frozen = &compiled.interface, .kind = .catalog, .index = 0, .origin = origin }).interface(target.binding) else self.result.interface(target);
        return .{ .target = target, .origin = origin, .interface = interface };
    }
    fn headerImport(self: *const Engine, target: check.ExternalTarget, origin: ast.Id) check.SourceHeader {
        std.debug.assert(self.source_validation);
        return .{ .target = target, .origin = origin, .capability_flow = self.catalogModule(target.unit).?.declaration(target.binding).capability_flow, .capability_parameters = self.catalogModule(target.unit).?.declaration(target.binding).capability_parameters, .named_function = self.catalogModule(target.unit).?.declaration(target.binding).named_function };
    }
    fn deinitSourceModules(self: *Engine) void {
        for (self.source_modules) |*item| if (item.*) |*module_| {
            module_.validation.deinit(self.allocator);
            self.allocator.free(module_.exports);
        };
        self.allocator.free(self.source_modules);
        for (self.compiled_catalogs) |catalog| {
            self.allocator.free(catalog.exports);
            self.allocator.free(catalog.declarations);
        }
        self.allocator.free(self.compiled_catalogs);
    }
    fn initCompiledCatalogs(self: *Engine) !void {
        self.compiled_catalogs = try self.allocator.alloc(CompiledCatalog, self.source.compiled_modules.len);
        @memset(self.compiled_catalogs, .{});
        for (self.source.compiled_modules, self.compiled_catalogs, 1..) |module, *catalog, id| {
            if (self.source.compiledModule(id) == null) continue;
            catalog.exports = try self.allocator.alloc(Export, module.exports.len);
            for (module.exports, catalog.exports) |old, *new| new.* = .{ .name = old.name, .target = old.target, .kind = @fromBackingInt(@intCast(@backingInt(old.kind))), .catalog = old.catalog };
            if (self.source_validation) {
                catalog.declarations = try self.allocator.alloc(check.SourceDeclaration, module.interface.bindings.len);
                const view: check.ImportedCatalog = .{ .frozen = &module.interface, .kind = .catalog, .index = 0, .origin = 0 };
                for (catalog.declarations, 0..) |*declaration, binding| declaration.* = view.declaration(@intCast(binding));
            }
        }
    }

    fn deinitDiagnostics(self: *Engine) void {
        for (self.diagnostics.items) |diagnostic_| {
            if (diagnostic_.purity) |witness| witness.deinit(self.allocator);
            if (diagnostic_.detail) |detail| self.allocator.free(detail);
            if (diagnostic_.hole) |hole| hole.deinit(self.allocator);
            if (diagnostic_.explanation) |explanation| explanation.deinit(self.allocator);
        }
        self.diagnostics.deinit(self.allocator);
    }
    /// One dependency-first step of a project check. False stops checking the
    /// remaining modules.
    fn checkOrdered(self: *Engine, unit: project.UnitId) !bool {
        const source = self.source;
        if (source.input_mode == .source and unit == source.entry) {
            if (check.sourceImportDiagnostic(&source.unit(unit).tree)) |item| {
                // Prelude semantics precede the source import boundary;
                // entry syntax already succeeded in project.load.
                if (self.diagnostics.items.len == 0) try self.diagnostics.append(self.allocator, .{ .unit = unit, .span = item.span, .code = .semantic, .semantic = item.code });
                return false;
            }
        }
        try self.checkModule(unit);
        return true;
    }

    fn diagnostic(self: *Engine, unit: project.UnitId, span: ast.Span, code: Code) Allocator.Error!void {
        try self.diagnostics.append(self.allocator, .{ .unit = unit, .span = span, .code = code });
    }

    const ParallelJob = struct {
        work: @import("../work_counters.zig").Frontend = .{},
        diagnostics: std.ArrayList(Diagnostic) = .empty,
        failure: ?anyerror = null,
        missing_name: bool = false,
        resolution_used: usize = 0,
        associated_used: usize = 0,
    };
    const ParallelWork = struct {
        trace: ?*@import("../phase_profile.zig").Trace = null,
        trace_space: @import("../phase_profile.zig").Space = .source,
        parent: *Engine,
        allocator: Allocator,
        units: []const u32,
        jobs: []ParallelJob,
        next: std.atomic.Value(usize) = .init(0),
        timings: [16]WorkerTiming = @splat(.{}),

        const WorkerTiming = struct { us: u64 = 0, cpu_us: u64 = 0, cpu_samples: u64 = 0, jobs: u64 = 0 };

        fn execute(self: *ParallelWork, index: usize) void {
            const space_scope = @import("../phase_profile.zig").enterSpace(self.trace_space);
            defer space_scope.restore();
            const trace_installation = @import("../phase_profile.zig").installTrace(self.trace);
            defer trace_installation.restore();
            var started: ?std.Io.Timestamp = null;
            var cpu: ?u64 = null;
            if (self.trace) |trace| {
                started = std.Io.Clock.awake.now(trace.io);
                cpu = profile.cpuNanos();
            }
            defer if (self.trace) |trace| {
                const timing = &self.timings[index];
                timing.us = @intCast(@max(0, started.?.durationTo(std.Io.Clock.awake.now(trace.io)).toMicroseconds()));
                if (cpu) |before| if (profile.cpuNanos()) |after| {
                    timing.cpu_us = (after -| before) / std.time.ns_per_us;
                    timing.cpu_samples = 1;
                };
            };
            while (true) {
                const at = self.next.fetchAdd(1, .monotonic);
                if (at >= self.units.len) return;
                const unit = self.units[at];
                const job = &self.jobs[unit - 1];
                var source = self.parent.source.*;
                source.symbols.read_only = true;
                source.symbols.missing_name = false;
                var worker = self.parent.*;
                worker.source = &source;
                worker.allocator = self.allocator;
                worker.diagnostics = .empty;
                worker.result.body_elaborations = 0;
                worker.result.imported_schemes = 0;
                worker.result.normalization = .{};
                const capture = @import("../phase_profile.zig").captureChecking(&job.work);
                defer capture.restore();
                worker.checkModule(unit) catch |err| {
                    job.failure = err;
                };
                job.diagnostics = worker.diagnostics;
                job.missing_name = source.symbols.missing_name;
                job.resolution_used = self.parent.resolution_remaining - worker.resolution_remaining;
                job.associated_used = self.parent.associated_remaining - worker.associated_remaining;
                job.work.parallel_jobs += 1;
                if (self.trace != null) self.timings[index].jobs += 1;
            }
        }
    };

    fn parallelReady(self: *const Engine, unit: u32, done: []const bool) bool {
        for (self.source.unitImports(unit)) |imported| {
            if (!done[imported.target - 1] and self.source.compiledModule(imported.target) == null) return false;
        }
        if (self.source.unit(unit).implicit_prelude and self.source.prelude_unit != 0 and self.source.prelude_unit != unit) {
            const prelude = self.source.prelude_unit;
            if (!done[prelude - 1] and self.source.compiledModule(prelude) == null) return false;
        }
        return true;
    }
    fn largerModuleFirst(source: *const project.Project, left: u32, right: u32) bool {
        const left_nodes = source.unit(left).tree.nodes.items.len;
        const right_nodes = source.unit(right).tree.nodes.items.len;
        if (left_nodes != right_nodes) return left_nodes > right_nodes;
        return left < right;
    }
    fn discardParallel(self: *Engine, resolution: usize, associated: usize) void {
        for (self.result.modules) |*slot| if (slot.*) |*module_| {
            module_.deinit(self.allocator);
            slot.* = null;
        };
        self.result.body_elaborations = 0;
        self.result.imported_schemes = 0;
        self.result.normalization = .{};
        self.resolution_remaining = resolution;
        self.associated_remaining = associated;
        @import("../phase_profile.zig").recordChecking(.{ .parallel_retries = 1 });
    }
    /// Ready modules run against immutable producer slots and a frozen symbol
    /// pool. Every batch joins before symbol growth or ordered budget charging.
    /// Diagnostics, unknown synthesized names and aggregate budget exhaustion
    /// discard speculation and replay the original serial diagnostic order.
    fn checkParallel(self: *Engine) !bool {
        const requested = self.source.checking.workers;
        if (requested <= 1 or self.source_validation or self.editor != null or self.execution.observe != null or self.execution.stats != null or self.source.input_mode != .project) return false;
        const io = self.source.checking.io orelse return false;
        var nodes: usize = 0;
        var remaining: usize = 0;
        for (self.source.order.items) |unit| {
            nodes +|= self.source.unit(unit).tree.nodes.items.len;
            remaining += 1;
        }
        if (remaining < 2 or nodes < self.execution.parallel_min_nodes) return false;
        const initial_resolution = self.resolution_remaining;
        const initial_associated = self.associated_remaining;
        const done = try self.allocator.alloc(bool, self.source.units.items.len);
        defer self.allocator.free(done);
        @memset(done, false);
        const jobs = try self.allocator.alloc(ParallelJob, done.len);
        defer self.allocator.free(jobs);
        @memset(jobs, .{});
        defer for (jobs) |*job| {
            var cleanup = self.*;
            cleanup.diagnostics = job.diagnostics;
            cleanup.deinitDiagnostics();
        };
        var ready: std.ArrayList(u32) = .empty;
        defer ready.deinit(self.allocator);
        var work_order: std.ArrayList(u32) = .empty;
        defer work_order.deinit(self.allocator);
        var locked: @import("../check/parallel_allocator.zig").LockedAllocator = .{ .backing = self.allocator, .io = io };
        while (remaining != 0) {
            ready.clearRetainingCapacity();
            for (self.source.order.items) |unit| {
                if (done[unit - 1]) continue;
                if (self.parallelReady(unit, done)) try ready.append(self.allocator, unit);
            }
            if (ready.items.len == 0) {
                self.discardParallel(initial_resolution, initial_associated);
                return false;
            }
            const trace = profile.currentTrace();
            {
                var started: ?std.Io.Timestamp = null;
                if (trace) |owner| started = std.Io.Clock.awake.now(owner.io);
                defer if (trace) |owner| {
                    profile.recordChecking(.{ .parallel_prepare_us = @intCast(@max(0, started.?.durationTo(std.Io.Clock.awake.now(owner.io)).toMicroseconds())) });
                };
                for (ready.items) |unit| {
                    var preparation = self.*;
                    preparation.prepare_names = true;
                    preparation.diagnostics = .empty;
                    defer preparation.deinitDiagnostics();
                    try preparation.checkModule(unit);
                    if (preparation.diagnostics.items.len != 0) {
                        self.discardParallel(initial_resolution, initial_associated);
                        return false;
                    }
                }
            }
            // Dispatch large bodies first; preparation, budgets and publication
            // keep dependency traversal order in `ready`.
            work_order.clearRetainingCapacity();
            try work_order.appendSlice(self.allocator, ready.items);
            std.mem.sort(u32, work_order.items, @as(*const project.Project, self.source), largerModuleFirst);
            var work: ParallelWork = .{ .trace = trace, .trace_space = @import("../phase_profile.zig").currentSpace(), .parent = self, .allocator = locked.allocator(), .units = work_order.items, .jobs = jobs };
            {
                var group: std.Io.Group = .init;
                const protection = io.swapCancelProtection(.blocked);
                defer _ = io.swapCancelProtection(protection);
                defer group.cancel(io);
                const count = @min(@as(usize, requested), @min(ready.items.len, 16));
                var started: ?std.Io.Timestamp = null;
                if (trace) |owner| started = std.Io.Clock.awake.now(owner.io);
                var actual_workers: usize = 1;
                for (1..count) |index| {
                    group.concurrent(io, ParallelWork.execute, .{ &work, index }) catch break;
                    actual_workers += 1;
                }
                work.execute(0);
                const wait_region = @import("../phase_profile.zig").region("check.worker-join", 0, 0, 0);
                group.await(io) catch unreachable;
                wait_region.exit();
                if (trace) |owner| {
                    const batch_us: u64 = @intCast(@max(0, started.?.durationTo(std.Io.Clock.awake.now(owner.io)).toMicroseconds()));
                    var batch_counts: @import("../work_counters.zig").Frontend = .{ .parallel_batch_us = batch_us, .parallel_capacity_us = batch_us *| actual_workers, .parallel_worker_slots = actual_workers };
                    for (work.timings[0..actual_workers]) |timing| {
                        batch_counts.parallel_worker_us +|= timing.us;
                        batch_counts.parallel_worker_cpu_us +|= timing.cpu_us;
                        batch_counts.parallel_worker_cpu_samples += timing.cpu_samples;
                        batch_counts.parallel_worker_jobs += timing.jobs;
                    }
                    profile.recordChecking(batch_counts);
                }
            }
            // Store allocators must not retain the temporary lock adapter.
            for (ready.items) |unit| if (self.result.modules[unit - 1]) |*module_| {
                module_.checked.types.allocator = self.allocator;
                module_.checked.types.effects.allocator = self.allocator;
            };
            @import("../phase_profile.zig").recordChecking(.{ .parallel_batches = 1 });
            var retry = false;
            var out_of_memory = false;
            for (ready.items) |unit| {
                const job = &jobs[unit - 1];
                @import("../phase_profile.zig").recordChecking(job.work);
                if (job.failure) |failure| {
                    out_of_memory = out_of_memory or failure == error.OutOfMemory;
                    retry = true;
                }
                retry = retry or job.missing_name or job.diagnostics.items.len != 0 or self.result.modules[unit - 1] == null;
                if (job.resolution_used > self.resolution_remaining or job.associated_used > self.associated_remaining) {
                    retry = true;
                } else {
                    self.resolution_remaining -= job.resolution_used;
                    self.associated_remaining -= job.associated_used;
                }
            }
            if (retry) {
                self.discardParallel(initial_resolution, initial_associated);
                if (out_of_memory) return error.OutOfMemory;
                return false;
            }
            for (ready.items) |unit| {
                const checked = &self.result.modules[unit - 1].?.checked;
                self.result.body_elaborations += checked.body_elaborations;
                self.result.imported_schemes += checked.imported_schemes;
                self.result.normalization.merge(checked.types.normalization);
                done[unit - 1] = true;
                remaining -= 1;
            }
        }
        return true;
    }
    fn appendCatalog(self: *Engine, catalogs: *std.ArrayList(check.ImportedCatalog), source_catalogs: *std.ArrayList(check.SourceCatalog), producer: CatalogModule, name: symbols.Symbol, namespace: symbols.Symbol, kind: @FieldType(check.ImportedCatalog, "kind"), index: u32, origin: ast.Id) Allocator.Error!void {
        switch (producer.owner) {
            .typed => |typed| try catalogs.append(self.allocator, .{ .producer = typed, .name = name, .namespace = namespace, .kind = kind, .index = index, .origin = origin }),
            .source => |source| try source_catalogs.append(self.allocator, .{ .producer = check.declarationCatalog(source), .declarations = source.declarations, .name = name, .namespace = namespace, .kind = kind, .index = index, .origin = origin }),
            .frozen => |frozen| if (self.source_validation) {
                try source_catalogs.append(self.allocator, .{ .producer = producer.catalog(), .declarations = self.compiled_catalogs[frozen.unit - 1].declarations, .name = name, .namespace = namespace, .kind = kind, .index = index, .origin = origin });
            } else {
                try catalogs.append(self.allocator, .{ .frozen = frozen, .name = name, .namespace = namespace, .kind = kind, .index = index, .origin = origin });
            },
        }
    }
    fn importExport(self: *Engine, imports: *std.ArrayList(check.ImportedBinding), headers: *std.ArrayList(check.SourceHeader), catalogs: *std.ArrayList(check.ImportedCatalog), source_catalogs: *std.ArrayList(check.SourceCatalog), producer: CatalogModule, exported: Export, name: symbols.Symbol, namespace: symbols.Symbol, origin: ast.Id) Allocator.Error!void {
        if (exported.kind == .value) {
            if (self.source_validation) {
                var imported = self.headerImport(exported.target, origin);
                imported.name = if (namespace == 0) name else 0;
                imported.namespace = namespace;
                imported.member = if (namespace == 0) 0 else name;
                try headers.append(self.allocator, imported);
            } else {
                var imported = self.valueImport(exported.target, origin);
                imported.name = if (namespace == 0) name else 0;
                imported.namespace = namespace;
                imported.member = if (namespace == 0) 0 else name;
                try imports.append(self.allocator, imported);
            }
        } else try self.appendCatalog(catalogs, source_catalogs, producer, name, namespace, switch (exported.kind) {
            .nominal => .nominal,
            .constructor => .constructor,
            .effect_family => .effect_family,
            .contract => .contract,
            .implementation => .implementation,
            .value => unreachable,
        }, exported.catalog, origin);
    }
    /// A catalog member imported through another module keeps its producer's
    /// capability facts (check.ProducerCapability), whether that producer was
    /// checked here or comes from its frozen interface.
    fn producerCapability(context: *const anyopaque, target: check.ExternalTarget) ?check.ProducerCapability {
        const self: *const Engine = @ptrCast(@alignCast(context));
        const module = self.catalogModule(target.unit) orelse return null;
        switch (module.owner) {
            .typed => |owner| {
                if (target.binding >= owner.bindings.len or owner.bindings[target.binding].external != null) return null;
                const binding = owner.bindings[target.binding];
                return .{ .flow = binding.capability_flow, .parameters = binding.capability_parameters, .recipe = .{ .callees = .{ .live = owner }, .binding = target.binding } };
            },
            .frozen => |owner| {
                if (target.binding >= owner.bindings.len or owner.bindings[target.binding].external != null) return null;
                const binding = owner.bindings[target.binding];
                return .{ .flow = binding.capability_flow, .parameters = binding.capability_parameters, .recipe = .{ .callees = .{ .frozen = owner }, .binding = target.binding } };
            },
            .source => |owner| {
                if (target.binding >= owner.declarations.len or owner.declarations[target.binding].external != null) return null;
                const declaration = owner.declarations[target.binding];
                return .{ .flow = declaration.capability_flow, .parameters = declaration.capability_parameters };
            },
        }
    }
    fn producerStorage(context: *const anyopaque, identity_: check.Identity) ?@import("../check/opaque_storage.zig").Storage {
        const self: *const Engine = @ptrCast(@alignCast(context));
        if (identity_.unit == 0 or identity_.unit > self.source.units.items.len) return null;
        const module = self.catalogModule(identity_.unit) orelse return null;
        for (module.catalog().nominals) |nominal| {
            if (nominal.is_opaque and nominal.identity.unit == identity_.unit and nominal.identity.decl == identity_.decl) return nominal.storage;
        }
        return null;
    }
    fn checkModule(self: *Engine, unit: project.UnitId) !void {
        const diagnostics_before = self.diagnostics.items.len;
        const source = self.source.unit(unit);
        const telemetry = @import("../phase_profile.zig");
        telemetry.traceModule(unit, self.source.symbols.get(source.filename), source.source.len);
        const region = telemetry.region("check.module", unit, 0, @intCast(source.source.len));
        defer region.exit();
        const tree = &source.tree;
        var occupied: std.AutoHashMapUnmanaged(symbols.Symbol, void) = .empty;
        defer occupied.deinit(self.allocator);
        var forwarded: std.ArrayList(Export) = .empty;
        defer forwarded.deinit(self.allocator);
        var imports: std.ArrayList(check.ImportedBinding) = .empty;
        defer imports.deinit(self.allocator);
        var headers: std.ArrayList(check.SourceHeader) = .empty;
        defer headers.deinit(self.allocator);
        var catalogs: std.ArrayList(check.ImportedCatalog) = .empty;
        defer catalogs.deinit(self.allocator);
        var source_catalogs: std.ArrayList(check.SourceCatalog) = .empty;
        defer source_catalogs.deinit(self.allocator);
        var inherited_fixities: std.ArrayList(check.ImportedFixity) = .empty;
        defer inherited_fixities.deinit(self.allocator);
        // Own declarations precede imports in the binding catalog, regardless
        // of the source position of a namespace import.
        for (tree.roots.items) |root| {
            const node = tree.node(root);
            if (node.tag == .value_decl or node.tag == .data_decl or node.tag == .type_alias_decl or node.tag == .contract_decl or node.tag == .implementation_decl or node.tag == .effect_type_decl or node.tag == .effect_decl)
                try occupied.put(self.allocator, node.a, {});
            if (node.tag == .data_decl) for (tree.children(node.b)) |constructor| {
                try occupied.put(self.allocator, tree.node(constructor).a, {});
            };
            if (node.tag != .value_decl) continue;
            const declaration = tree.valueDecl(root);
            if (declaration.exported and unit != self.source.entry)
                try self.diagnostic(unit, tree.span(root), .entry_module);
        }
        for (self.source.unitImports(unit)) |imported| {
            const info = tree.importDecl(imported.declaration.node);
            const forwarding = tree.node(imported.declaration.node).tag == .export_decl;
            if (info.namespace != 0) {
                const entry = try occupied.getOrPut(self.allocator, info.namespace);
                if (entry.found_existing) {
                    try self.diagnostic(unit, info.namespace_span, .duplicate_name);
                    continue;
                }
            }
            if (self.catalogModule(imported.target) == null) {
                try self.diagnostic(unit, imported.span, .dependency_failed);
                continue;
            }
            const producer = self.catalogModule(imported.target).?;
            if (!producer.valid) {
                try self.diagnostic(unit, imported.span, .dependency_failed);
                continue;
            }
            try self.appendCatalog(&catalogs, &source_catalogs, producer, 0, 0, .catalog, 0, imported.declaration.node);
            if (info.namespace != 0) {
                for (producer.exports) |exported| {
                    var original = producer;
                    if (exported.kind != .value and exported.target.unit != 0 and exported.target.unit != imported.target) original = self.catalogModule(exported.target.unit).?;
                    try self.importExport(&imports, &headers, &catalogs, &source_catalogs, original, exported, exported.name, info.namespace, imported.declaration.node);
                }
            } else {
                for (tree.list(info.bindings)) |binding| {
                    const alias = tree.importBinding(binding);
                    const entry = try occupied.getOrPut(self.allocator, alias.alias);
                    if (entry.found_existing) {
                        try self.diagnostic(unit, tree.span(binding), .duplicate_name);
                        continue;
                    }
                    var found = false;
                    for (producer.exports) |exported| {
                        if (forwarding) {
                            if (self.resolution_remaining == 0) {
                                try self.diagnostic(unit, tree.span(binding), .resolution_budget);
                                break;
                            }
                            self.resolution_remaining -= 1;
                        }
                        if (exported.name != alias.name) continue;
                        found = true;
                        var original = producer;
                        if (exported.kind != .value and exported.target.unit != 0 and exported.target.unit != imported.target) original = self.catalogModule(exported.target.unit).?;
                        try self.importExport(&imports, &headers, &catalogs, &source_catalogs, original, exported, alias.alias, 0, binding);
                        if (forwarding) {
                            var public = exported;
                            public.name = alias.alias;
                            try forwarded.append(self.allocator, public);
                        }
                    }
                    if (!found) {
                        try self.diagnostic(unit, tree.span(binding), .unknown_export);
                        continue;
                    }
                }
            }
        }
        if (source.implicit_prelude) {
            const prelude_unit = self.source.prelude_unit;
            if (self.catalogModule(prelude_unit) == null or !self.catalogModule(prelude_unit).?.valid) {
                try self.diagnostic(unit, .{ .start = 0, .end = 0 }, .dependency_failed);
            } else {
                const producer = self.catalogModule(prelude_unit).?;
                try self.appendCatalog(&catalogs, &source_catalogs, producer, 0, 0, .catalog, 0, 0);
                for (producer.exports) |exported| {
                    // Lexical declarations and explicit aliases shadow the
                    // ordinary prelude names without changing its producers.
                    if (occupied.contains(exported.name)) continue;
                    try self.importExport(&imports, &headers, &catalogs, &source_catalogs, producer, exported, exported.name, 0, 0);
                }
                if (self.source.compiledModule(prelude_unit) != null) {
                    for (self.source.compiled_modules[prelude_unit - 1].fixities) |fixity| {
                        if (!fixity.named) {
                            if (self.source_validation) {
                                var imported = self.headerImport(fixity.producer, 0);
                                imported.expose = false;
                                try headers.append(self.allocator, imported);
                            } else {
                                var imported = self.valueImport(fixity.producer, 0);
                                imported.expose = false;
                                try imports.append(self.allocator, imported);
                            }
                        }
                        try inherited_fixities.append(self.allocator, .{ .operator = fixity.operator, .target = fixity.target, .named = fixity.named, .external = if (fixity.named) null else fixity.producer });
                    }
                } else {
                    const prelude_tree = &self.source.unit(prelude_unit).tree;
                    for (prelude_tree.roots.items) |root| {
                        if (prelude_tree.node(root).tag != .fixity_decl) continue;
                        const fixity = prelude_tree.fixity(root);
                        const binding = producer.resolved(root);
                        const target = producer.declaration(binding).external orelse check.ExternalTarget{ .unit = prelude_unit, .binding = binding };
                        if (!fixity.named) {
                            if (self.source_validation) {
                                var imported = self.headerImport(target, 0);
                                imported.expose = false;
                                try headers.append(self.allocator, imported);
                            } else {
                                var imported = self.valueImport(target, 0);
                                imported.expose = false;
                                try imports.append(self.allocator, imported);
                            }
                        }
                        try inherited_fixities.append(self.allocator, .{ .operator = fixity.operator, .target = fixity.target, .named = fixity.named, .external = if (fixity.named) null else target });
                    }
                }
            }
        }
        if (self.prepare_names) {
            try check.prepareGeneratedNames(self.allocator, &self.source.symbols, tree, catalogs.items);
            return;
        }
        var options: check.ModuleOptions = .{ .associated_remaining = &self.associated_remaining, .purity_origins = .{ .context = self.source, .lookup = moduleOrigin, .source_available = moduleSourceAvailable }, .builtin_catalog = unit == self.source.prelude_unit, .prelude_unit = self.source.prelude_unit, .inherited_fixities = inherited_fixities.items };
        options.producer_capabilities = .{ .context = self, .lookup = producerCapability };
        options.producer_storage = .{ .context = self, .lookup = producerStorage };
        if (self.editor) |query| {
            options.max_inference_transitions = query.budget.remaining;
            if (query.unit == unit) options.editor = query.marker;
        }
        if (self.source_validation) {
            var validation = try check.validateModuleSource(self.allocator, tree, &self.source.symbols, headers.items, source_catalogs.items, unit, options);
            var transferred = false;
            defer if (!transferred) validation.deinit(self.allocator);
            if (check.hasNumericFailure(tree) and validation.diagnostics.len == 0) return error.NumericValidationIncomplete;
            const owned_exports = try self.moduleExports(unit, check.declarationCatalog(&validation), validation.declarations, validation.diagnostics, forwarded.items);
            self.source_modules[unit - 1] = .{ .validation = validation, .exports = owned_exports, .valid = self.diagnostics.items.len == diagnostics_before };
            transferred = true;
        } else {
            var checked = try check.checkModuleWithPrivateExecution(self.allocator, tree, &self.source.symbols, imports.items, catalogs.items, unit, options, self.execution);
            var transferred = false;
            defer if (!transferred) checked.deinit(self.allocator);
            if (self.editor) |query| {
                _ = query.budget.spend(@intCast(checked.counters.inference_steps));
                if (checked.initializer_rejected) query.budget.exhausted = true;
                for (checked.diagnostics) |diagnostic_| if (diagnostic_.code == .inference_budget) {
                    query.budget.remaining = 0;
                    query.budget.exhausted = true;
                };
            }
            if (checked.initializer_rejected) {
                try self.appendDiagnostics(unit, checked.diagnostics);
                return;
            }
            const owned_exports = try self.moduleExports(unit, check.declarationCatalog(&checked), checked.bindings, checked.diagnostics, forwarded.items);
            self.result.modules[unit - 1] = .{ .checked = checked, .exports = owned_exports, .valid = self.diagnostics.items.len == diagnostics_before };
            transferred = true;
            self.result.body_elaborations += checked.body_elaborations;
            self.result.imported_schemes += checked.imported_schemes;
            self.result.normalization.merge(checked.types.normalization);
        }
    }
    fn appendDiagnostics(self: *Engine, unit: project.UnitId, diagnostics: []const check.Diagnostic) !void {
        for (diagnostics) |diagnostic_| {
            const purity = if (diagnostic_.purity) |witness| try witness.clone(self.allocator) else null;
            errdefer if (purity) |witness| witness.deinit(self.allocator);
            const detail = if (diagnostic_.detail) |text| try self.allocator.dupe(u8, text) else null;
            errdefer if (detail) |text| self.allocator.free(text);
            const hole = if (diagnostic_.hole) |value| try value.clone(self.allocator) else null;
            errdefer if (hole) |value| value.deinit(self.allocator);
            const explanation = if (diagnostic_.explanation) |value| try value.clone(self.allocator) else null;
            errdefer if (explanation) |value| value.deinit(self.allocator);
            var origin_unit = unit;
            if (diagnostic_.origin_unit != 0) origin_unit = diagnostic_.origin_unit;
            try self.diagnostics.append(self.allocator, .{
                .unit = origin_unit,
                .span = diagnostic_.span,
                .code = .semantic,
                .semantic = diagnostic_.code,
                .type_application = diagnostic_.type_application,
                .symbol = diagnostic_.symbol,
                .implicit_type_witness = diagnostic_.implicit_type_witness,
                .source_terminator = diagnostic_.source_terminator,
                .numeric_literal = diagnostic_.numeric_literal,
                .purity = purity,
                .detail = detail,
                .hole = hole,
                .explanation = explanation,
                .contexts = diagnostic_.contexts,
                .context_len = diagnostic_.context_len,
            });
        }
    }
    fn moduleExports(self: *Engine, unit: project.UnitId, catalog: check.DeclarationCatalog, declarations: anytype, diagnostics: []const check.Diagnostic, forwarded: []const Export) ![]Export {
        var exports: std.ArrayList(Export) = .empty;
        defer exports.deinit(self.allocator);
        for (declarations, 0..) |binding, index| {
            if (binding.kind != .global or binding.private) continue;
            try exports.append(self.allocator, .{ .name = binding.name, .target = .{ .unit = unit, .binding = @intCast(index) } });
        }
        for (catalog.nominals, 0..) |nominal, index| if (index != 0 and nominal.identity.unit == unit and !nominal.private) {
            try exports.append(self.allocator, .{ .name = nominal.name, .target = .{ .unit = unit, .binding = 0 }, .kind = .nominal, .catalog = @intCast(index) });
        };
        for (catalog.constructors, 0..) |constructor, index| if (index != 0 and constructor.identity.unit == unit and !constructor.private) {
            try exports.append(self.allocator, .{ .name = constructor.name, .target = .{ .unit = unit, .binding = 0 }, .kind = .constructor, .catalog = @intCast(index) });
        };
        for (catalog.effect_families, 0..) |family, index| if (index != 0 and family.identity.unit == unit and !family.private) {
            try exports.append(self.allocator, .{ .name = family.name, .target = .{ .unit = unit, .binding = 0 }, .kind = .effect_family, .catalog = @intCast(index) });
        };
        for (catalog.contracts, 0..) |contract, index| if (contract.identity.unit == unit and !contract.private) {
            try exports.append(self.allocator, .{ .name = contract.name, .target = .{ .unit = unit, .binding = 0 }, .kind = .contract, .catalog = @intCast(index) });
        };
        for (catalog.implementations, 0..) |implementation, index| if (implementation.identity.unit == unit and !implementation.private) {
            try exports.append(self.allocator, .{ .name = implementation.name, .target = .{ .unit = unit, .binding = 0 }, .kind = .implementation, .catalog = @intCast(index) });
        };
        try exports.appendSlice(self.allocator, forwarded);
        try self.appendDiagnostics(unit, diagnostics);
        // All fallible transfers finish before the caller publishes its owner.
        return exports.toOwnedSlice(self.allocator);
    }
};

/// Owns semantic tables only. Source UTF-8, syntax and symbol ownership stay in
/// Project and must outlive any subsequent source-aware lowering.
pub fn checkProject(allocator: Allocator, source: *project.Project) !CheckedProject {
    return checkProjectWithPrivateExecution(allocator, source, .{});
}

/// PRIVATE execution-only project proof. Public callers remain default off;
/// the loader, semantic options and artifact identities receive no new flags.
pub fn checkProjectWithPrivateExecution(allocator: Allocator, source: *project.Project, execution: check.PrivateExecution) !CheckedProject {
    return checkProjectMode(allocator, source, execution, null, false);
}

/// One request-local checker graph, with a shared work budget across modules.
pub fn checkProjectForEditor(allocator: Allocator, source: *project.Project, query: EditorQuery) !CheckedProject {
    return checkProjectMode(allocator, source, .{}, query, false);
}

/// checkProject for callers that publish only the first diagnostic. Checking
/// stops after the first module that reports one, so `diagnostics` is a
/// non-empty prefix of the complete check's list exactly when that list is
/// non-empty, and later modules stay unchecked.
pub fn checkProjectToFirstDiagnostic(allocator: Allocator, source: *project.Project) !CheckedProject {
    return checkProjectMode(allocator, source, .{}, null, true);
}

fn checkProjectMode(allocator: Allocator, source: *project.Project, execution: check.PrivateExecution, editor: ?EditorQuery, first_diagnostic: bool) !CheckedProject {
    const timing = @import("../phase_profile.zig").enter(.check);
    defer timing.exit();
    var engine: Engine = .{ .associated_remaining = @import("../inference_limits.zig").configured(), .allocator = allocator, .source = source, .result = .{}, .execution = execution, .editor = editor };
    errdefer engine.result.deinit(allocator);
    defer engine.deinitDiagnostics();
    defer engine.deinitSourceModules();
    if (source.diagnostics.items.len != 0) {
        for (source.diagnostics.items) |diagnostic_| try engine.diagnostics.append(allocator, .{
            .unit = diagnostic_.unit,
            .span = diagnostic_.span,
            .code = .source_validation,
            .source = diagnostic_,
        });
    } else {
        engine.result.modules = try allocator.alloc(?Module, source.units.items.len);
        @memset(engine.result.modules, null);
        engine.source_validation = source.input_mode == .source and check.sourceImportDiagnostic(&source.unit(source.entry).tree) != null;
        for (source.units.items) |*unit| if (check.hasNumericFailure(&unit.tree)) {
            engine.source_validation = true;
            break;
        };
        if (engine.source_validation) {
            engine.source_modules = try allocator.alloc(?Engine.SourceModule, source.units.items.len);
            @memset(engine.source_modules, null);
        }
        try engine.initCompiledCatalogs();
        if (!try engine.checkParallel()) for (source.order.items) |unit| {
            if (!try engine.checkOrdered(unit)) break;
            // Diagnostics are appended in dependency order and never
            // reordered, so the first is final once it exists. Source
            // validation still collects every module's numeric diagnostics.
            if (first_diagnostic and !engine.source_validation and engine.diagnostics.items.len != 0) break;
        };
    }
    engine.result.diagnostics = try engine.diagnostics.toOwnedSlice(allocator);
    return engine.result;
}

test "project exports preserve positioned inference budget rejection with empty catalogs" {
    const allocator = std.testing.allocator;
    const text = "const exhausted = func x => return x\n";
    var tokens = try @import("../parse/lexer.zig").lex(allocator, text);
    defer tokens.deinit(allocator);
    var source: project.Project = .{};
    defer source.deinit(allocator);
    var tree = try @import("../parse/parser.zig").parse(allocator, text, tokens.tokens.items, &source.symbols);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &source.symbols, &.{}, &.{}, 1, .{ .max_inference_transitions = 0 });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(check.Code.inference_budget, checked.diagnostics[0].code);
    try std.testing.expectEqual(@as(usize, 0), checked.nominals.len);
    try std.testing.expectEqual(@as(usize, 0), checked.constructors.len);
    try std.testing.expectEqual(@as(usize, 0), checked.effect_families.len);
    var engine: Engine = .{ .allocator = allocator, .source = &source, .result = .{} };
    defer {
        for (engine.diagnostics.items) |diagnostic| if (diagnostic.detail) |detail| allocator.free(detail);
        engine.diagnostics.deinit(allocator);
    }
    const exports = try engine.moduleExports(1, check.declarationCatalog(&checked), checked.bindings, checked.diagnostics, &.{});
    defer engine.allocator.free(exports);
    try std.testing.expectEqual(@as(usize, 0), exports.len);
    try std.testing.expectEqual(@as(usize, 1), engine.diagnostics.items.len);
    const diagnostic = engine.diagnostics.items[0];
    try std.testing.expectEqual(@as(u32, 1), diagnostic.unit);
    try std.testing.expectEqual(check.Code.inference_budget, diagnostic.semantic.?);
    try std.testing.expectEqual(checked.diagnostics[0].span, diagnostic.span);
    try std.testing.expect(diagnostic.span.end > diagnostic.span.start);
    try std.testing.expectEqualStrings(checked.diagnostics[0].detail.?, diagnostic.detail.?);
}

fn forwardingBudgetCheck(allocator: Allocator, source: *project.Project, parallel: bool) !CheckedProject {
    var engine: Engine = .{ .allocator = allocator, .source = source, .result = .{}, .resolution_remaining = 1, .execution = .{ .parallel_min_nodes = 0 } };
    errdefer engine.result.deinit(allocator);
    defer engine.deinitDiagnostics();
    defer engine.deinitSourceModules();
    engine.result.modules = try allocator.alloc(?Module, source.units.items.len);
    @memset(engine.result.modules, null);
    try engine.initCompiledCatalogs();
    const completed = parallel and try engine.checkParallel();
    if (!completed) for (source.order.items) |unit| {
        if (!try engine.checkOrdered(unit)) break;
    };
    engine.result.diagnostics = try engine.diagnostics.toOwnedSlice(allocator);
    return engine.result;
}

test "parallel module forwarding charges the combined project budget in serial order" {
    const allocator = std.testing.allocator;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const filenames = [_][]const u8{ "shared.blot", "left.blot", "right.blot", "main.blot" };
    const sources = [_][]const u8{
        "const value = 42\n",
        "export {value as first} from \"./shared\"\n",
        "export {value as second} from \"./shared\"\n",
        "import {first} from \"./left\"\nimport {second} from \"./right\"\nentry const answer = first\n",
    };
    for (filenames, sources) |filename, text| try directory.dir.writeFile(std.testing.io, .{ .sub_path = filename, .data = text });
    const path = try directory.dir.realPathFileAlloc(std.testing.io, "main.blot", allocator);
    defer allocator.free(path);
    var source = try project.load(allocator, std.testing.io, path, .{});
    defer source.deinit(allocator);
    source.checking = .{ .io = std.testing.io, .workers = 4 };
    var serial = try forwardingBudgetCheck(allocator, &source, false);
    defer serial.deinit(allocator);
    var counts: @import("../work_counters.zig").Frontend = .{};
    const capture = @import("../phase_profile.zig").captureChecking(&counts);
    defer capture.restore();
    var parallel = try forwardingBudgetCheck(allocator, &source, true);
    defer parallel.deinit(allocator);
    try std.testing.expectEqual(@as(u64, 1), counts.parallel_retries);
    try std.testing.expect(serial.diagnostics.len != 0);
    try std.testing.expectEqualDeep(serial.diagnostics, parallel.diagnostics);
    try std.testing.expectEqual(Code.resolution_budget, parallel.diagnostics[0].code);
}
