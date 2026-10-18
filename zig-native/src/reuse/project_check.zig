//! Separate module semantic regions. Import aliases resolve to structured
//! producer identities; source trees and written names are never rewritten.
const std = @import("std");
const project = @import("project.zig");
const check = @import("../check/check.zig");
const ast = @import("../parse/ast.zig");
const symbols = @import("../parse/symbols.zig");
const Allocator = std.mem.Allocator;
const PI = @import("principal_interface.zig");
const entry_cutoff = @import("entry_frontend_cutoff.zig");

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
    body_caches: []@import("body_check_cache.zig").Cache = &.{},
    // Index is UnitId-1, independent of dependency-first evaluation order.
    modules: []?Module = &.{},
    diagnostics: []Diagnostic = &.{},
    body_elaborations: usize = 0,
    imported_schemes: usize = 0,
    entry_cutoff: entry_cutoff.Stats = .{},
    module_cutoff: entry_cutoff.Stats = .{},
    reused_modules: []bool = &.{},
    interface_colors: []entry_cutoff.Color = &.{},
    /// Set by checkProjectDeferringEntry: every module except the entry is
    /// checked, and these budgets resume its check in checkDeferredEntry.
    deferred_entry: ?Deferred = null,
    pub const Deferred = struct { resolution_remaining: usize, associated_remaining: usize };
    pub fn compiledModule(self: *const CheckedProject, source: *const project.Project, id: usize) ?*const @import("frozen_dependency.zig").Module {
        if (source.compiledModule(id)) |value| return value;
        if (id == 0 or id > self.reused_modules.len or !self.reused_modules[id - 1]) return null;
        return &source.compiled_modules[id - 1];
    }

    pub fn deinit(self: *CheckedProject, allocator: Allocator) void {
        for (self.body_caches) |*cache| cache.deinit(allocator);
        allocator.free(self.body_caches);
        for (self.modules) |*item| if (item.*) |*module_| module_.deinit(allocator);
        allocator.free(self.modules);
        allocator.free(self.reused_modules);
        allocator.free(self.interface_colors);
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
        return .{ .producer_binding = target.binding, .proof_contract = check.checkedProofContract(producer, target.binding), .types = .{ .store = &producer.types }, .scheme = producer.bindings[target.binding].scheme, .capability_flow = producer.bindings[target.binding].capability_flow, .capability_parameters = producer.bindings[target.binding].capability_parameters, .named_function = producer.bindings[target.binding].named_function, .obligations = producer.obligations, .callees = .{ .live = producer } };
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
    previous_bodies: std.StringHashMapUnmanaged(?*const @import("body_check_cache.zig").Cache) = .empty,
    retain_bodies: bool = false,
    allocator: Allocator,
    source: *project.Project,
    result: CheckedProject,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    source_validation: bool = false,
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
        if (self.result.compiledModule(self.source, unit) != null) return .{ .owner = .{ .frozen = &self.source.compiled_modules[unit - 1].interface }, .exports = self.compiled_catalogs[unit - 1].exports, .valid = true };
        if (self.source_validation) {
            if (self.source_modules[unit - 1]) |*module_| return .{ .owner = .{ .source = &module_.validation }, .exports = module_.exports, .valid = module_.valid };
        } else if (self.result.modules[unit - 1]) |*module_| return .{ .owner = .{ .typed = &module_.checked }, .exports = module_.exports, .valid = module_.valid };
        return null;
    }
    fn valueImport(self: *const Engine, target: check.ExternalTarget, origin: ast.Id) check.ImportedBinding {
        std.debug.assert(!self.source_validation);
        const interface = if (self.result.compiledModule(self.source, target.unit) != null) (check.ImportedCatalog{ .frozen = &self.source.compiled_modules[target.unit - 1].interface, .kind = .catalog, .index = 0, .origin = origin }).interface(target.binding) else self.result.interface(target);
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
            if (self.result.compiledModule(self.source, id) == null) continue;
            catalog.exports = try self.allocator.alloc(Export, module.exports.len);
            for (module.exports, catalog.exports) |old, *new| new.* = .{ .name = old.name, .target = old.target, .kind = @fromBackingInt(@intCast(@backingInt(old.kind))), .catalog = old.catalog };
            if (self.source_validation) {
                catalog.declarations = try self.allocator.alloc(check.SourceDeclaration, module.interface.bindings.len);
                const view: check.ImportedCatalog = .{ .frozen = &module.interface, .kind = .catalog, .index = 0, .origin = 0 };
                for (catalog.declarations, 0..) |*declaration, binding| declaration.* = view.declaration(@intCast(binding));
            }
        }
    }

    fn recoverModule(self: *Engine, unit: u32) Allocator.Error!void {
        const previous = &self.source.compiled_modules[unit - 1];
        const exports = try self.allocator.alloc(Export, previous.exports.len);
        for (previous.exports, exports) |old, *new| new.* = .{ .name = old.name, .target = old.target, .kind = @fromBackingInt(@intCast(@backingInt(old.kind))), .catalog = old.catalog };
        self.compiled_catalogs[unit - 1].exports = exports;
        self.result.reused_modules[unit - 1] = true;
        self.result.module_cutoff.reused += 1;
    }

    /// Body offers stay borrowed from the accepted revision. Filename offers
    /// relocate modules independently of loader discovery order.
    fn offerBodies(self: *Engine, previous: ?entry_cutoff.Previous) Allocator.Error!void {
        const old = previous orelse return;
        if (old.bodies.len != old.names.owners.len) return;
        for (old.bodies, 1..) |*body, unit| {
            const filename = old.names.owner(@intCast(unit)) orelse continue;
            const entry = try self.previous_bodies.getOrPut(self.allocator, filename);
            if (entry.found_existing) {
                entry.value_ptr.* = null;
            } else entry.value_ptr.* = body;
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
    fn checkOrdered(self: *Engine, unit: project.UnitId, previous: ?entry_cutoff.Previous) !bool {
        const source = self.source;
        if (source.input_mode == .source and unit == source.entry) {
            if (check.sourceImportDiagnostic(&source.unit(unit).tree)) |item| {
                // Prelude semantics precede the source import boundary;
                // entry syntax already succeeded in project.load.
                if (self.diagnostics.items.len == 0) try self.diagnostics.append(self.allocator, .{ .unit = unit, .span = item.span, .code = .semantic, .semantic = item.code });
                return false;
            }
        }
        if (unit == source.entry and !self.source_validation and self.diagnostics.items.len == 0) if (previous) |old| {
            if (old.reuse_entry and try entry_cutoff.confirm(self.allocator, source, &self.result, old, &self.result.entry_cutoff)) return true;
        };
        if (unit != source.entry and self.result.reused_modules.len != 0 and self.diagnostics.items.len == 0) if (previous) |old| {
            if (try @import("module_frontend_cutoff.zig").confirm(self.allocator, source, &self.result, old, unit, &self.result.module_cutoff)) {
                try self.recoverModule(unit);
                return true;
            }
        };
        try self.checkModule(unit);
        return true;
    }

    fn diagnostic(self: *Engine, unit: project.UnitId, span: ast.Span, code: Code) Allocator.Error!void {
        try self.diagnostics.append(self.allocator, .{ .unit = unit, .span = span, .code = code });
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
    fn originalBindingClosedRows(context: *const anyopaque, target: check.ExternalTarget) ?@import("body_check_cache.zig").Digest {
        const self: *const Engine = @ptrCast(@alignCast(context));
        const module = self.catalogModule(target.unit) orelse return null;
        switch (module.owner) {
            .typed => |typed| {
                if (target.binding >= typed.bindings.len) return null;
                const binding = typed.bindings[target.binding];
                return @import("body_check_cache.zig").closedRowsDigest(.{ .store = &typed.types }, binding.ty, binding.scheme, &self.source.symbols);
            },
            .frozen => |frozen| {
                if (target.binding >= frozen.bindings.len) return null;
                const binding = frozen.bindings[target.binding];
                return @import("body_check_cache.zig").closedRowsDigest(.{ .frozen = &frozen.graph }, binding.ty, binding.scheme, &self.source.symbols);
            },
            .source => return null,
        }
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
    fn originalBindingCapabilities(context: *const anyopaque, target: check.ExternalTarget) ?@import("body_check_cache.zig").Digest {
        const self: *const Engine = @ptrCast(@alignCast(context));
        const module = self.catalogModule(target.unit) orelse return null;
        switch (module.owner) {
            inline .typed, .frozen => |owner| {
                if (target.binding >= owner.bindings.len) return null;
                const binding = owner.bindings[target.binding];
                const recipe = owner.capability_contracts.header(target.binding, binding.capability_parameters.arity());
                return @import("body_check_cache.zig").capabilityDigest(&self.source.symbols, binding, recipe);
            },
            .source => return null,
        }
    }
    fn originalQualification(context: *const anyopaque, unit: u32, span: ast.Span) ?@import("body_check_cache.zig").Digest {
        const self: *const Engine = @ptrCast(@alignCast(context));
        const cache = @import("body_check_cache.zig");
        const module = self.catalogModule(unit) orelse return null;
        switch (module.owner) {
            .typed => |typed| {
                const tree = &self.source.unit(unit).tree;
                if (typed.bindings.len > 4096) return null;
                var budget: usize = 4096;
                for (typed.bindings) |binding| {
                    if (cache.sourceQualificationDigest(tree, &self.source.symbols, binding, span, &budget)) |digest| return digest;
                }
                return null;
            },
            .frozen => |frozen| {
                const compiled = self.result.compiledModule(self.source, unit) orelse return null;
                if (frozen.bindings.len > 4096 or frozen.obligations.len > 4096 or frozen.obligation_spans.len != frozen.obligations.len) return null;
                var owner: ?u32 = null;
                for (frozen.bindings, 0..) |binding, index| {
                    if (binding.kind != .global) continue;
                    for (frozen.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len], frozen.obligation_spans[binding.scheme.obligations.start..][0..binding.scheme.obligations.len]) |predicate, origin| {
                        if (!predicate.explicit or predicate.qualification_unit != unit or !std.meta.eql(predicate.qualification_span, @as(?ast.Span, span))) continue;
                        // Declared source clauses lie inside their where span;
                        // forwarded use sites lie in the consumer declaration.
                        if (origin.start < span.start or origin.end > span.end or origin.start > origin.end) continue;
                        if (owner) |prior| if (prior != index) return null;
                        owner = @intCast(index);
                    }
                }
                const index = owner orelse {
                    // Public snapshots redact local names and schemes. Frozen
                    // Core still owns declared clause spans and local binders.
                    const core = &compiled.core;
                    if (core.bindings.len > 4096 or core.obligations.len > 4096) return null;
                    var declaration: ?u32 = null;
                    var remaining: usize = 4096;
                    for (core.bindings) |local| {
                        if (remaining == 0) return null;
                        remaining -= 1;
                        if (local.kind != .local) continue;
                        var declared = false;
                        for (core.obligations[local.scheme.obligations.start..][0..local.scheme.obligations.len]) |predicate| {
                            if (remaining == 0) return null;
                            remaining -= 1;
                            if (!predicate.explicit or predicate.qualification_unit != unit or !std.meta.eql(predicate.qualification_span, @as(?ast.Span, span))) continue;
                            if (predicate.span.start < span.start or predicate.span.end > span.end or predicate.span.start > predicate.span.end) continue;
                            declared = true;
                        }
                        if (!declared) continue;
                        for (core.bindings, 0..) |enclosing, enclosing_index| {
                            if (remaining == 0) return null;
                            remaining -= 1;
                            if (enclosing.kind != .global or enclosing.body_id == 0 or enclosing.body_id >= core.bodies.len) continue;
                            if (span.start < enclosing.span.start or span.end > enclosing.span.end or local.span.start < enclosing.span.start or local.span.end > enclosing.span.end) continue;
                            if (declaration) |prior| if (prior != enclosing_index) return null;
                            declaration = @intCast(enclosing_index);
                        }
                    }
                    const enclosing_index = declaration orelse return null;
                    if (enclosing_index >= frozen.bindings.len) return null;
                    const enclosing = core.bindings[enclosing_index];
                    const body = core.bodies[enclosing.body_id];
                    if (body.binding != enclosing_index) return null;
                    const principal = frozen.bindings[enclosing_index];
                    return cache.localQualificationDigest(self.source.symbols.get(principal.name), principal.private, body.runtime, enclosing.span, span);
                };
                if (index >= compiled.core.bindings.len) return null;
                const binding = compiled.core.bindings[index];
                if (binding.kind != .global or binding.body_id == 0 or binding.body_id >= compiled.core.bodies.len) return null;
                const body = compiled.core.bodies[binding.body_id];
                if (body.binding != index) return null;
                const principal = frozen.bindings[index];
                return cache.qualificationDigest(self.source.symbols.get(principal.name), principal.private, body.runtime, binding.span, span);
            },
            .source => return null,
        }
    }
    fn originalUnitOrigin(context: *const anyopaque, unit: u32) ?@import("body_check_cache.zig").Digest {
        const self: *const Engine = @ptrCast(@alignCast(context));
        if (unit == 0 or unit > self.source.units.items.len) return null;
        var hash: std.crypto.hash.Blake3 = .init(.{});
        hash.update("body original module");
        hash.update(self.source.filename(unit));
        var digest: @import("body_check_cache.zig").Digest = undefined;
        hash.final(&digest);
        return digest;
    }
    fn originalBindingName(context: *const anyopaque, target: check.ExternalTarget) ?[]const u8 {
        const self: *const Engine = @ptrCast(@alignCast(context));
        const producer = self.catalogModule(target.unit) orelse return null;
        return self.source.symbols.get(producer.declaration(target.binding).name);
    }
    fn checkModule(self: *Engine, unit: project.UnitId) !void {
        const diagnostics_before = self.diagnostics.items.len;
        const source = self.source.unit(unit);
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
                if (self.result.compiledModule(self.source, prelude_unit) != null) {
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
        var options: check.ModuleOptions = .{ .associated_remaining = &self.associated_remaining, .purity_origins = .{ .context = self.source, .lookup = moduleOrigin, .source_available = moduleSourceAvailable }, .builtin_catalog = unit == self.source.prelude_unit, .prelude_unit = self.source.prelude_unit, .inherited_fixities = inherited_fixities.items };
        if (self.retain_bodies and self.editor == null) options.retained_bodies = &self.result.body_caches[unit - 1];
        options.body_source = self.source.unit(unit).source;
        options.body_external_names = .{ .context = self, .lookup = originalBindingName, .unit_origin = originalUnitOrigin, .closed_rows = originalBindingClosedRows, .qualification = originalQualification, .capabilities = originalBindingCapabilities };
        options.producer_capabilities = .{ .context = self, .lookup = producerCapability };
        if (self.previous_bodies.get(self.source.filename(unit))) |cached| options.previous_bodies = cached;
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
    return checkProjectMode(allocator, source, execution, null, null, false);
}

/// One request-local checker graph, with a shared work budget across modules.
/// No retained frontend or executable body is offered or published here.
pub fn checkProjectForEditor(allocator: Allocator, source: *project.Project, query: EditorQuery) !CheckedProject {
    return checkProjectMode(allocator, source, .{}, null, query, false);
}

/// PRIVATE final-entry proof. The caller owns the previous successful Core and
/// the same seed named by this mixed Project throughout preparation.
pub fn checkProjectWithEntryCutoff(allocator: Allocator, source: *project.Project, previous: entry_cutoff.Previous) !CheckedProject {
    return checkProjectMode(allocator, source, .{}, previous, null, true);
}

pub fn checkProjectRetainingBodies(allocator: Allocator, source: *project.Project, previous: ?entry_cutoff.Previous) !CheckedProject {
    return checkProjectMode(allocator, source, .{}, previous, null, true);
}

/// PRIVATE: checks like checkProjectWithEntryCutoff (with `previous`),
/// checkProjectRetainingBodies or checkProject, for callers that publish only
/// the first diagnostic. Checking stops after the first module that reports
/// one, so `diagnostics` is a non-empty prefix of the complete check's list
/// exactly when that list is non-empty, and later modules stay unchecked.
pub fn checkProjectToFirstDiagnostic(allocator: Allocator, source: *project.Project, previous: ?entry_cutoff.Previous, retain_bodies: bool) !CheckedProject {
    return checkProjectModeDeferring(allocator, source, .{}, previous, null, retain_bodies, false, true);
}

/// PRIVATE population lane: checks every module except the entry, which is
/// last in dependency order, and records the budgets left for it. The entry
/// stays unchecked until checkDeferredEntry. Source-validation projects check
/// every module at once and leave `deferred_entry` null.
pub fn checkProjectDeferringEntry(allocator: Allocator, source: *project.Project, previous: ?entry_cutoff.Previous) !CheckedProject {
    return checkProjectModeDeferring(allocator, source, .{}, previous, null, true, true, false);
}

/// checkProjectDeferringEntry for a caller that publishes only the first
/// diagnostic: a dependency's diagnostic stops checking there, leaving
/// `deferred_entry` null, so checkDeferredEntry checks nothing more.
pub fn checkProjectDeferringEntryToFirstDiagnostic(allocator: Allocator, source: *project.Project, previous: ?entry_cutoff.Previous) !CheckedProject {
    return checkProjectModeDeferring(allocator, source, .{}, previous, null, true, true, true);
}

/// Checks the entry of a checkProjectDeferringEntry result exactly as one
/// undivided pass would have checked it last: with the same remaining
/// budgets, body offers and diagnostic order. `previous` must be the same
/// offer. On failure `checked` is left empty.
pub fn checkDeferredEntry(allocator: Allocator, source: *project.Project, checked: *CheckedProject, previous: ?entry_cutoff.Previous) !void {
    const deferred = checked.deferred_entry orelse return;
    const timing = @import("../phase_profile.zig").enter(.check);
    defer timing.exit();
    var engine: Engine = .{ .allocator = allocator, .source = source, .result = checked.*, .retain_bodies = checked.body_caches.len != 0, .resolution_remaining = deferred.resolution_remaining, .associated_remaining = deferred.associated_remaining };
    checked.* = .{};
    engine.result.deferred_entry = null;
    engine.diagnostics = .fromOwnedSlice(engine.result.diagnostics);
    engine.result.diagnostics = &.{};
    errdefer engine.result.deinit(allocator);
    defer engine.deinitDiagnostics();
    defer engine.previous_bodies.deinit(allocator);
    defer engine.deinitSourceModules();
    try engine.offerBodies(previous);
    try engine.initCompiledCatalogs();
    _ = try engine.checkOrdered(source.entry, previous);
    engine.result.diagnostics = try engine.diagnostics.toOwnedSlice(allocator);
    checked.* = engine.result;
}

fn checkProjectMode(allocator: Allocator, source: *project.Project, execution: check.PrivateExecution, previous: ?entry_cutoff.Previous, editor: ?EditorQuery, retain_bodies: bool) !CheckedProject {
    return checkProjectModeDeferring(allocator, source, execution, previous, editor, retain_bodies, false, false);
}
fn checkProjectModeDeferring(allocator: Allocator, source: *project.Project, execution: check.PrivateExecution, previous: ?entry_cutoff.Previous, editor: ?EditorQuery, retain_bodies: bool, defer_entry: bool, first_diagnostic: bool) !CheckedProject {
    const timing = @import("../phase_profile.zig").enter(.check);
    defer timing.exit();
    var engine: Engine = .{ .allocator = allocator, .source = source, .result = .{}, .execution = execution, .editor = editor, .retain_bodies = retain_bodies };
    defer engine.previous_bodies.deinit(allocator);
    try engine.offerBodies(previous);
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
        if (retain_bodies) {
            engine.result.body_caches = try allocator.alloc(@import("body_check_cache.zig").Cache, source.units.items.len);
            @memset(engine.result.body_caches, .{});
        }
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
        if (previous != null and previous.?.reuse_modules and !engine.source_validation) {
            engine.result.reused_modules = try allocator.alloc(bool, source.compiled_modules.len);
            @memset(engine.result.reused_modules, false);
            engine.result.interface_colors = try allocator.alloc(entry_cutoff.Color, source.compiled_modules.len);
            @memset(engine.result.interface_colors, .unknown);
        }
        try engine.initCompiledCatalogs();
        const deferrable = defer_entry and source.input_mode == .project and !engine.source_validation and source.order.items.len != 0 and source.order.items[source.order.items.len - 1] == source.entry;
        for (source.order.items) |unit| {
            if (deferrable and unit == source.entry) {
                engine.result.deferred_entry = .{ .resolution_remaining = engine.resolution_remaining, .associated_remaining = engine.associated_remaining };
                break;
            }
            if (!try engine.checkOrdered(unit, previous)) break;
            // Diagnostics are appended in dependency order and never
            // reordered, so the first is final once it exists. Source
            // validation still collects every module's numeric diagnostics.
            if (first_diagnostic and !engine.source_validation and engine.diagnostics.items.len != 0) break;
        }
    }
    engine.result.diagnostics = try engine.diagnostics.toOwnedSlice(allocator);
    return engine.result;
}

test "project exports preserve positioned inference budget rejection with empty catalogs" {
    const allocator = std.testing.allocator;
    const text = "const exhausted = fn x => x\n";
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
