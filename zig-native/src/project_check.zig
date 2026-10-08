//! Separate module semantic regions. Import aliases resolve to structured
//! producer identities; source trees and written names are never rewritten.
const std = @import("std");
const project = @import("project.zig");
const check = @import("check.zig");
const ast = @import("ast.zig");
const symbols = @import("symbols.zig");
const Allocator = std.mem.Allocator;
const PI = @import("principal_interface.zig");
const entry_cutoff = @import("entry_frontend_cutoff.zig");

pub const Export = struct { name: symbols.Symbol, target: check.ExternalTarget = .{ .unit = 0, .binding = 0 }, kind: enum { value, nominal, constructor, effect_family, contract } = .value, catalog: u32 = 0 };
pub const Module = struct {
    checked: check.Checked,
    exports: []Export,
    valid: bool,

    fn deinit(self: *Module, allocator: Allocator) void {
        self.checked.deinit(allocator);
        allocator.free(self.exports);
    }
};
pub const Code = enum { source_validation, semantic, duplicate_name, unknown_export, entry_module, declaration_modifier, dependency_failed };
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
    entry_cutoff: entry_cutoff.Stats = .{},
    module_cutoff: entry_cutoff.Stats = .{},
    reused_modules: []bool = &.{},
    interface_colors: []entry_cutoff.Color = &.{},
    pub fn compiledModule(self: *const CheckedProject, source: *const project.Project, id: usize) ?*const @import("frozen_dependency.zig").Module {
        if (source.compiledModule(id)) |value| return value;
        if (id == 0 or id > self.reused_modules.len or !self.reused_modules[id - 1]) return null;
        return &source.compiled_modules[id - 1];
    }

    pub fn deinit(self: *CheckedProject, allocator: Allocator) void {
        for (self.modules) |*item| if (item.*) |*module_| module_.deinit(allocator);
        allocator.free(self.modules);
        allocator.free(self.reused_modules);
        allocator.free(self.interface_colors);
        for (self.diagnostics) |diagnostic| {
            if (diagnostic.purity) |witness| witness.deinit(allocator);
            if (diagnostic.detail) |detail| allocator.free(detail);
            if (diagnostic.hole) |hole| hole.deinit(allocator);
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
        return .{ .types = .{ .store = &producer.types }, .scheme = producer.bindings[target.binding].scheme, .named_function = producer.bindings[target.binding].named_function, .obligations = producer.obligations };
    }
};

fn moduleOrigin(context: ?*const anyopaque, allocator: Allocator, unit: u32) @import("types.zig").Error![]u8 {
    const loaded: *const project.Project = @ptrCast(@alignCast(context orelse return error.TypeLimit));
    if (unit == loaded.prelude_unit and unit != 0) return allocator.dupe(u8, "std/prelude");
    if (loaded.input_mode == .source and unit == loaded.entry) return allocator.dupe(u8, "main");
    if (unit == 0 or unit > loaded.units.items.len) return error.TypeLimit;
    const directory = std.Io.Dir.path.dirname(loaded.filename(loaded.entry)) orelse return error.TypeLimit;
    return std.Io.Dir.path.relativeAlloc(allocator, directory, null, directory, loaded.filename(unit));
}

pub fn diagnosticModuleOrigin(context: ?*const anyopaque, allocator: Allocator, unit: u32) @import("types.zig").Error![]u8 {
    return moduleOrigin(context, allocator, unit);
}

const Engine = struct {
    allocator: Allocator,
    source: *project.Project,
    result: CheckedProject,
    diagnostics: std.ArrayList(Diagnostic) = .empty,
    source_validation: bool = false,
    execution: check.PrivateExecution = .{},
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
        return .{ .target = target, .origin = origin, .named_function = self.catalogModule(target.unit).?.declaration(target.binding).named_function };
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
            .value => unreachable,
        }, exported.catalog, origin);
    }
    fn checkModule(self: *Engine, unit: project.UnitId) !void {
        const diagnostics_before = self.diagnostics.items.len;
        const source = self.source.unit(unit);
        const tree = &source.tree;
        var occupied: std.AutoHashMapUnmanaged(symbols.Symbol, void) = .empty;
        defer occupied.deinit(self.allocator);
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
            if (node.tag == .value_decl or node.tag == .data_decl or node.tag == .type_alias_decl or node.tag == .contract_decl or node.tag == .effect_type_decl or node.tag == .effect_decl)
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
                for (producer.exports) |exported| try self.importExport(&imports, &headers, &catalogs, &source_catalogs, producer, exported, exported.name, info.namespace, imported.declaration.node);
            } else {
                for (tree.list(info.bindings)) |binding| {
                    const alias = tree.importBinding(binding);
                    const entry = try occupied.getOrPut(self.allocator, alias.alias);
                    if (entry.found_existing) {
                        try self.diagnostic(unit, tree.span(binding), .duplicate_name);
                        continue;
                    }
                    var found = false;
                    for (producer.exports) |exported| if (exported.name == alias.name) {
                        found = true;
                        try self.importExport(&imports, &headers, &catalogs, &source_catalogs, producer, exported, alias.alias, 0, binding);
                    };
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
        const options: check.ModuleOptions = .{ .purity_origins = .{ .context = self.source, .lookup = moduleOrigin }, .builtin_catalog = unit == self.source.prelude_unit, .prelude_unit = self.source.prelude_unit, .inherited_fixities = inherited_fixities.items };
        if (self.source_validation) {
            var validation = try check.validateModuleSource(self.allocator, tree, &self.source.symbols, headers.items, source_catalogs.items, unit, options);
            var transferred = false;
            defer if (!transferred) validation.deinit(self.allocator);
            if (check.hasNumericFailure(tree) and validation.diagnostics.len == 0) return error.NumericValidationIncomplete;
            const owned_exports = try self.moduleExports(unit, check.declarationCatalog(&validation), validation.declarations, validation.diagnostics);
            self.source_modules[unit - 1] = .{ .validation = validation, .exports = owned_exports, .valid = self.diagnostics.items.len == diagnostics_before };
            transferred = true;
        } else {
            var checked = try check.checkModuleWithPrivateExecution(self.allocator, tree, &self.source.symbols, imports.items, catalogs.items, unit, options, self.execution);
            var transferred = false;
            defer if (!transferred) checked.deinit(self.allocator);
            if (checked.initializer_rejected) {
                try self.appendDiagnostics(unit, checked.diagnostics);
                return;
            }
            const owned_exports = try self.moduleExports(unit, check.declarationCatalog(&checked), checked.bindings, checked.diagnostics);
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
            try self.diagnostics.append(self.allocator, .{
                .unit = unit,
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
            });
        }
    }
    fn moduleExports(self: *Engine, unit: project.UnitId, catalog: check.DeclarationCatalog, declarations: anytype, diagnostics: []const check.Diagnostic) ![]Export {
        var exports: std.ArrayList(Export) = .empty;
        defer exports.deinit(self.allocator);
        for (declarations, 0..) |binding, index| {
            if (binding.kind != .global) continue;
            try exports.append(self.allocator, .{ .name = binding.name, .target = .{ .unit = unit, .binding = @intCast(index) } });
        }
        for (catalog.nominals[1..], 1..) |nominal, index| if (nominal.identity.unit == unit) {
            try exports.append(self.allocator, .{ .name = nominal.name, .kind = .nominal, .catalog = @intCast(index) });
        };
        for (catalog.constructors[1..], 1..) |constructor, index| if (constructor.identity.unit == unit) {
            try exports.append(self.allocator, .{ .name = constructor.name, .kind = .constructor, .catalog = @intCast(index) });
        };
        for (catalog.effect_families[1..], 1..) |family, index| if (family.identity.unit == unit) {
            try exports.append(self.allocator, .{ .name = family.name, .kind = .effect_family, .catalog = @intCast(index) });
        };
        for (catalog.contracts, 0..) |contract, index| if (contract.identity.unit == unit) {
            try exports.append(self.allocator, .{ .name = contract.name, .kind = .contract, .catalog = @intCast(index) });
        };
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
    return checkProjectMode(allocator, source, execution, null);
}

/// PRIVATE final-entry proof. The caller owns the previous successful Core and
/// the same seed named by this mixed Project throughout preparation.
pub fn checkProjectWithEntryCutoff(allocator: Allocator, source: *project.Project, previous: entry_cutoff.Previous) !CheckedProject {
    return checkProjectMode(allocator, source, .{}, previous);
}

fn checkProjectMode(allocator: Allocator, source: *project.Project, execution: check.PrivateExecution, previous: ?entry_cutoff.Previous) !CheckedProject {
    var engine: Engine = .{ .allocator = allocator, .source = source, .result = .{}, .execution = execution };
    errdefer engine.result.deinit(allocator);
    defer {
        for (engine.diagnostics.items) |diagnostic| {
            if (diagnostic.purity) |witness| witness.deinit(allocator);
            if (diagnostic.detail) |detail| allocator.free(detail);
            if (diagnostic.hole) |hole| hole.deinit(allocator);
        }
        engine.diagnostics.deinit(allocator);
    }
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
        if (previous != null and previous.?.reuse_modules and !engine.source_validation) {
            engine.result.reused_modules = try allocator.alloc(bool, source.compiled_modules.len);
            @memset(engine.result.reused_modules, false);
            engine.result.interface_colors = try allocator.alloc(entry_cutoff.Color, source.compiled_modules.len);
            @memset(engine.result.interface_colors, .unknown);
        }
        try engine.initCompiledCatalogs();
        for (source.order.items) |unit| {
            if (source.input_mode == .source and unit == source.entry) {
                if (check.sourceImportDiagnostic(&source.unit(unit).tree)) |item| {
                    // Prelude semantics precede the source import boundary;
                    // entry syntax already succeeded in project.load.
                    if (engine.diagnostics.items.len == 0) try engine.diagnostics.append(allocator, .{ .unit = unit, .span = item.span, .code = .semantic, .semantic = item.code });
                    break;
                }
            }
            if (unit == source.entry and !engine.source_validation and engine.diagnostics.items.len == 0) if (previous) |old| {
                if (try entry_cutoff.confirm(allocator, source, &engine.result, old, &engine.result.entry_cutoff)) continue;
            };
            if (unit != source.entry and engine.result.reused_modules.len != 0 and engine.diagnostics.items.len == 0) if (previous) |old| {
                if (try @import("module_frontend_cutoff.zig").confirm(allocator, source, &engine.result, old, unit, &engine.result.module_cutoff)) {
                    try engine.recoverModule(unit);
                    continue;
                }
            };
            try engine.checkModule(unit);
        }
    }
    engine.result.diagnostics = try engine.diagnostics.toOwnedSlice(allocator);
    return engine.result;
}
