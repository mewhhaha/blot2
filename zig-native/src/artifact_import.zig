//! Imports owned artifact graphs into one candidate Generator. Old numeric IDs
//! always name old pools; producer paths and exact pinned Core qualify local IDs.
//! Unsupported identity transitions decline without publishing a code artifact.
const std = @import("std");
const core = @import("core.zig");
const core_eval = @import("core_eval.zig");
const types = @import("types.zig");
const layout = @import("layout.zig");
const evidence = @import("type_evidence.zig");
const substitutions = @import("substitution_keys.zig");
const artifacts = @import("code_artifacts.zig");
const identity = @import("runtime_identity.zig");
const QueryGate = @import("principal_reuse_gate.zig").Gate;
const runtime_operations = @import("runtime_operations.zig");
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{Declined};
const depth_limit = 128;
const Domain = enum { layout, semantic };
const RowKey = struct { domain: Domain, id: u32 };
const EvidenceKey = struct { id: u32, owner: u32 = 0, mappings: bool = false };
const SubstitutionKey = struct { id: u32, owner: u32 };
const OperationScope = enum { unchecked, admitted, declined };

pub const Solved = struct {
    mappings: []layout.Mapping,
    rows: []layout.RowMapping,
    templates: []substitutions.Entry,
    pub fn deinit(self: *Solved, allocator: Allocator) void {
        allocator.free(self.mappings);
        allocator.free(self.rows);
        allocator.free(self.templates);
        self.* = undefined;
    }
};

pub const Importer = struct {
    allocator: Allocator,
    old: *const artifacts.Pools,
    units: []const core.Module,
    names: ?identity.Metadata = null,
    unit_map: []u32,
    symbol_map: []u32,
    stable: []bool,
    code_gate: ?@import("code_body_validity.zig").Gate = null,
    /// Only initCheckedQuery may establish exact semantic catalogs separately
    /// from executable structure. Layout and code imports still use stable.
    semantic_catalogs: bool = false,
    enabled: bool = false,
    generator_owner: ?usize = null,
    layouts: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    semantic: std.AutoHashMapUnmanaged(EvidenceKey, u32) = .empty,
    rows: std.AutoHashMapUnmanaged(RowKey, u32) = .empty,
    template_keys: std.AutoHashMapUnmanaged(SubstitutionKey, u32) = .empty,
    row_keys: std.AutoHashMapUnmanaged(SubstitutionKey, u32) = .empty,
    captures: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    /// Correspondence proved by complete static value/evidence/capture graphs.
    /// These IDs belong to this Importer's old and current evaluator owners.
    value_anchors: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    operation_labels: ?[]u32 = null,
    operation_scopes: ?[]OperationScope = null,

    /// The caller retains old Pools and immutable current Core through use.
    /// Canonical spellings are copied; temporary frontend owners may disappear.
    pub fn init(allocator: Allocator, old: *const artifacts.Pools, units: []const core.Module, names: ?identity.View, cached_units: usize) Allocator.Error!Importer {
        return initWithStamps(allocator, old, units, names, cached_units, null);
    }
    pub fn initWithStamps(allocator: Allocator, old: *const artifacts.Pools, units: []const core.Module, names: ?identity.View, cached_units: usize, stamps: ?*artifacts.ModuleStamps) Allocator.Error!Importer {
        const unit_map = try allocator.alloc(u32, old.modules.len);
        errdefer allocator.free(unit_map);
        @memset(unit_map, 0);
        const stable = try allocator.alloc(bool, old.modules.len);
        errdefer allocator.free(stable);
        @memset(stable, false);
        const old_names = if (old.identity) |*metadata| metadata.view() else null;
        const symbol_map = try allocator.alloc(u32, if (old_names) |view| view.symbols.len else 0);
        errdefer allocator.free(symbol_map);
        @memset(symbol_map, 0);
        var result: Importer = .{ .allocator = allocator, .old = old, .units = units, .unit_map = unit_map, .symbol_map = symbol_map, .stable = stable };
        errdefer if (result.names) |*owned| owned.deinit(allocator);
        if (!old.project_identity or names == null or old_names == null or cached_units > units.len) return result;
        result.names = try copyIdentity(allocator, names.?);
        const current = result.names.?.view();
        if (current.owners.len != units.len or old_names.?.owners.len != old.modules.len or current.symbols.len == 0 or old_names.?.symbols.len == 0) return result;
        var producer_ids: std.StringHashMapUnmanaged(u32) = .empty;
        defer producer_ids.deinit(allocator);
        for (units, 0..) |module, i| {
            if (module.unit != 0 and module.unit != i + 1) return result;
            const path = current.owner(@intCast(i + 1)) orelse return result;
            if (path.len == 0 or !std.unicode.utf8ValidateSlice(path) or std.mem.findScalar(u8, path, 0) != null) return result;
            const entry = try producer_ids.getOrPut(allocator, path);
            if (entry.found_existing) return result;
            entry.value_ptr.* = @intCast(i + 1);
        }
        var spelling_ids: std.StringHashMapUnmanaged(u32) = .empty;
        defer spelling_ids.deinit(allocator);
        for (1..current.symbols.len) |i| {
            const spelling = current.symbol(@intCast(i)) orelse return result;
            if (spelling.len == 0 or !std.unicode.utf8ValidateSlice(spelling)) return result;
            const entry = try spelling_ids.getOrPut(allocator, spelling);
            if (entry.found_existing) return result;
            entry.value_ptr.* = @intCast(i);
        }
        // A duplicate path or spelling is ambiguous even if its ordinal matches.
        for (old.modules, 0..) |pin, i| {
            if (pin.unit != i + 1 or pin.canonical_path.len == 0) return result;
            if (pin.module.unit != 0 and pin.module.unit != pin.unit) return result;
            const path = old_names.?.owner(pin.unit) orelse return result;
            if (!std.mem.eql(u8, path, pin.canonical_path)) return result;
            for (old.modules[0..i]) |previous| if (std.mem.eql(u8, previous.canonical_path, path)) return result;
            unit_map[i] = producer_ids.get(path) orelse 0;
        }
        for (symbol_map[1..], 1..) |*mapped, i| {
            const spelling = old_names.?.symbol(@intCast(i)) orelse return result;
            if (spelling.len == 0) return result;
            mapped.* = spelling_ids.get(spelling) orelse 0;
        }
        result.enabled = true;
        for (old.modules, 0..) |pin, i| {
            const mapped = unit_map[i];
            if (mapped == 0 or mapped > cached_units) continue;
            // A hash is an accelerator, followed by exact content equality.
            // Check the retained pointer still names the originally pinned Core.
            if (!std.mem.eql(u8, &pin.stamp, &try artifacts.moduleStamp(pin.module, stamps))) continue;
            stable[i] = result.coreEqual(pin.module, &units[mapped - 1]) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Declined => false,
            };
        }
        result.code_gate = try @import("code_body_validity.zig").Gate.init(allocator, old, units, names, stamps);
        return result;
    }
    /// PRIVATE query-only preparation within one compileWithOptions epoch.
    /// The caller has already checked this exact immutable old/current pair.
    /// No new namespace is validated here and these scalar-tolerant flags never
    /// authorize executable fragments. Public/fresh import remains unchanged.
    /// Gate, old Pools and current Core stay immutable through preparation/use;
    /// the returned importer independently owns every copied map and spelling.
    pub fn initCheckedQuery(allocator: Allocator, old: *const artifacts.Pools, units: []const core.Module, checked: *const QueryGate) Allocator.Error!?Importer {
        // Pair before reading borrowed old content. Pointer equality identifies
        // this compile epoch's owners; it is not cross-compilation validation.
        if (!checked.enabled or checked.source_pools != old or checked.units.ptr != units.ptr or checked.units.len != units.len or checked.allocator.ptr != allocator.ptr or checked.allocator.vtable != allocator.vtable) return null;
        if (old.modules.len != units.len or checked.structural_units.len != units.len or !old.project_identity or old.identity == null) return null;
        const names = old.identity.?.view();
        if (names.owners.len != units.len or names.symbols.len == 0 or names.symbols.len > std.math.maxInt(u32) or units.len >= std.math.maxInt(u32)) return null;
        const unit_map = try allocator.alloc(u32, units.len);
        errdefer allocator.free(unit_map);
        for (unit_map, 0..) |*mapped, i| mapped.* = @intCast(i + 1);
        const symbol_map = try allocator.alloc(u32, names.symbols.len);
        errdefer allocator.free(symbol_map);
        for (symbol_map, 0..) |*mapped, i| mapped.* = @intCast(i);
        const stable = try allocator.dupe(bool, checked.structural_units);
        errdefer allocator.free(stable);
        const owned_names = try copyIdentity(allocator, names);
        // All fallible allocation precedes publication. Mutable semantic/row/
        // capture memo tables start empty and retain their ordinary live checks.
        return .{ .allocator = allocator, .old = old, .units = units, .names = owned_names, .unit_map = unit_map, .symbol_map = symbol_map, .stable = stable, .semantic_catalogs = true, .enabled = true };
    }
    pub fn deinit(self: *Importer) void {
        self.layouts.deinit(self.allocator);
        self.semantic.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.template_keys.deinit(self.allocator);
        self.row_keys.deinit(self.allocator);
        self.captures.deinit(self.allocator);
        self.value_anchors.deinit(self.allocator);
        if (self.operation_labels) |labels| self.allocator.free(labels);
        if (self.operation_scopes) |scopes| self.allocator.free(scopes);
        if (self.names) |*names| names.deinit(self.allocator);
        self.allocator.free(self.unit_map);
        self.allocator.free(self.symbol_map);
        if (self.code_gate) |*gate| gate.deinit();
        self.allocator.free(self.stable);
        self.* = undefined;
    }
    fn bind(self: *Importer, generator: anytype) Error!void {
        if (!self.enabled) return error.Declined;
        const owner = @intFromPtr(generator);
        if (self.generator_owner) |previous| {
            if (owner != previous) return error.Declined;
        } else {
            try self.checkFields(generator);
            self.generator_owner = owner;
        }
    }
    fn unit(self: *const Importer, old_unit: u32, require_stable: bool) Error!u32 {
        if (old_unit == 0 or old_unit > self.unit_map.len) return error.Declined;
        const mapped = self.unit_map[old_unit - 1];
        if (mapped == 0 or (require_stable and !self.stable[old_unit - 1])) return error.Declined;
        return mapped;
    }
    fn nominal(self: *const Importer, old_unit: u32, decl: u32) Error!u32 {
        return self.nominalInDomain(old_unit, decl, true);
    }
    fn semanticNominal(self: *const Importer, old_unit: u32, decl: u32) Error!u32 {
        return self.nominalInDomain(old_unit, decl, !self.semantic_catalogs);
    }
    fn nominalInDomain(self: *const Importer, old_unit: u32, decl: u32, require_stable: bool) Error!u32 {
        if (decl == 0) return error.Declined;
        if (old_unit == std.math.maxInt(u32)) {
            // Compiler-owned State/Computation identities retain their explicit
            // payload arguments; unknown generative domains are not admitted.
            if (decl > 6) return error.Declined;
            return old_unit;
        }
        const mapped = if (require_stable) try self.typeUnit(old_unit) else try self.unit(old_unit, false);
        const module = &self.units[mapped - 1];
        for (module.nominals) |value| if (value.identity.decl == decl and (value.identity.unit == 0 or value.identity.unit == mapped)) return mapped;
        for (module.types.operations) |value| if (value.identity.decl == decl and value.identity.unit == mapped) return mapped;
        for (module.operation_values) |value| if (value.identity.decl == decl and value.identity.unit == mapped) return mapped;
        return error.Declined;
    }
    fn symbol(self: *const Importer, old_symbol: u32) Error!u32 {
        if (old_symbol == 0 or old_symbol >= self.symbol_map.len or self.symbol_map[old_symbol] == 0) return error.Declined;
        return self.symbol_map[old_symbol];
    }
    pub fn admitsBody(self: *const Importer, value: core.BindingRef) bool {
        if (value.unit == 0 or value.unit > self.unit_map.len) return false;
        if (self.stable[value.unit - 1]) return true;
        const gate = if (self.code_gate) |*owned| owned else return false;
        return gate.body(.{ .unit = self.unit_map[value.unit - 1], .binding = value.binding });
    }
    fn typeUnit(self: *const Importer, source: u32) Error!u32 {
        const exact_catalog = if (self.code_gate) |*gate| gate.catalog(source) else false;
        return self.unit(source, !exact_catalog);
    }
    fn expressionUnit(self: *const Importer, source: u32, root: core.Id) Error!u32 {
        const mapped = try self.unit(source, false);
        if (self.stable[source - 1]) return mapped;
        const gate = if (self.code_gate) |*owned| &owned.semantic else return error.Declined;
        // Structural equality permits only isolated top-level scalar changes;
        // lexical nodes, catalogs, captures and type IDs remain exact. Confirm
        // every named read of this expression against the transitive dirty set.
        if (!gate.enabled or !gate.structural_units[source - 1]) return error.Declined;
        const refs = @import("declaration_dependencies.zig").expressionReferences(self.allocator, self.old.modules[source - 1].module, root) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.Declined;
        defer self.allocator.free(refs);
        for (refs) |ref| {
            const unit_id = if (ref.unit == 0) source else ref.unit;
            if (unit_id == 0 or unit_id >= gate.offsets.len or ref.binding >= gate.units[unit_id - 1].bindings.len or gate.dirty[gate.offsets[unit_id - 1] + ref.binding]) return error.Declined;
        }
        return mapped;
    }
    fn target(self: *const Importer, value: core.BindingRef) Error!core.BindingRef {
        if (!self.admitsBody(value)) return error.Declined;
        const mapped = try self.unit(value.unit, false);
        if (value.binding == 0 or value.binding >= self.units[mapped - 1].bindings.len) return error.Declined;
        if (self.units[mapped - 1].body(value.binding) == null) return error.Declined;
        return .{ .unit = mapped, .binding = value.binding };
    }
    fn checkFields(self: *const Importer, generator: anytype) Error!void {
        if (self.old.field_locations.len != generator.evaluator.field_locations.count()) return error.Declined;
        for (self.old.field_locations) |field| {
            const source_unit: u32 = @intCast(field.family >> 32);
            const decl: u32 = @truncate(field.family);
            const mapped = if (source_unit == std.math.maxInt(u32)) source_unit else try self.unit(source_unit, false);
            const family = (@as(u64, mapped) << 32) | decl;
            const found = generator.evaluator.field_locations.get(.{ .family = family, .tag = field.tag, .name = try self.symbol(field.name) }) orelse return error.Declined;
            if (found.field != field.field or found.len != field.len) return error.Declined;
        }
    }

    pub fn importRequest(self: *Importer, generator: anytype, old_request: artifacts.Request) Allocator.Error!?artifacts.Request {
        return self.request(generator, old_request, true) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.Declined => null,
        };
    }
    /// Exact current-owner equality after structural import. Hashes and IDs from
    /// different owners never authorize a match, and operation tables are read-only.
    pub fn matches(self: *Importer, generator: anytype, old_request: artifacts.Request, current: artifacts.Request) Allocator.Error!bool {
        if (old_request == .closure and current == .closure and (old_request.closure.static_values != 0 or current.closure.static_values != 0)) {
            var actual = current;
            actual.closure.static_values = 0;
            const imported = self.request(generator, old_request, false) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
            if (!std.meta.eql(imported, actual)) return false;
            return self.matchStaticKey(generator, old_request.closure.static_values, current.closure.static_values);
        }
        const imported = (try self.importRequest(generator, old_request)) orelse return false;
        return std.meta.eql(imported, current);
    }
    fn staticEntries(self: *const Importer, id: u32) Error![]const substitutions.Entry {
        if (id == 0) return &.{};
        if (id > self.old.static_values.spans.len) return error.Declined;
        const span = self.old.static_values.spans[id - 1];
        const entries = try bounded(substitutions.Entry, self.old.static_values.entries, span.start, span.len);
        for (entries, 0..) |entry, index| {
            if (entry.variable == 0 or entry.value >= self.old.evaluator.values.len) return error.Declined;
            if (index != 0 and entry.variable <= entries[index - 1].variable) return error.Declined;
        }
        return entries;
    }
    /// Merge only a correspondence already proved by source_value_template.
    /// Conflicting alias relationships decline rather than overwrite a proof.
    pub fn recordValueAnchors(self: *Importer, anchors: []const u32) Allocator.Error!bool {
        if (anchors.len != self.old.evaluator.values.len) return false;
        for (anchors, 0..) |current, old| if (current != 0) {
            if (self.value_anchors.get(@intCast(old))) |known| if (known != current) return false;
        };
        for (anchors, 0..) |current, old| if (current != 0) try self.value_anchors.put(self.allocator, @intCast(old), current);
        return true;
    }
    fn matchStaticKey(self: *Importer, g: anytype, old_id: u32, current_id: u32) Allocator.Error!bool {
        const before = self.staticEntries(old_id) catch return false;
        const after = g.static_keys.get(current_id);
        if (before.len != after.len or before.len == 0) return false;
        const gate = if (self.code_gate) |*owned| &owned.semantic else return false;
        const roots = try self.allocator.alloc(u32, before.len);
        defer self.allocator.free(roots);
        for (before, after, roots) |old, current, *root| {
            if (old.variable != current.variable) return false;
            root.* = old.value;
        }
        const inspection = try @import("source_value_template.zig").Plan.inspectRootsWithRows(self.allocator, self.old, gate, roots, .source_declared);
        var plan = inspection.plan orelse return false;
        defer plan.deinit(self.allocator);
        const anchors = try self.allocator.alloc(u32, self.old.evaluator.values.len);
        defer self.allocator.free(anchors);
        @memset(anchors, 0);
        for (before, after) |old, current| {
            if (!(plan.matchInto(g, self, old.value, current.value, anchors) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false)) return false;
        }
        return self.recordValueAnchors(anchors);
    }
    fn staticKey(self: *Importer, g: anytype, id: u32) Error!u32 {
        if (id == 0) return 0;
        const source = try self.staticEntries(id);
        const entries = try self.allocator.alloc(substitutions.Entry, source.len);
        defer self.allocator.free(entries);
        for (source, entries) |old, *current| current.* = .{ .variable = old.variable, .value = if (old.value == 0) 0 else self.value_anchors.get(old.value) orelse return error.Declined };
        return g.static_keys.intern(entries) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.Declined;
    }
    fn request(self: *Importer, g: anytype, old_request: artifacts.Request, import_static: bool) Error!artifacts.Request {
        try self.bind(g);
        return switch (old_request) {
            .named => |old_key| blk: {
                var key = old_key;
                key.target = try self.target(key.target);
                if (key.count > artifacts.max_parameters) return error.Declined;
                for (0..artifacts.max_parameters) |i| {
                    if (i >= key.count) {
                        if (key.parameters[i] != 1 or key.effects[i] != 0) return error.Declined;
                        continue;
                    }
                    key.parameters[i] = try self.shape(g, key.parameters[i], 0);
                    if (!knownLayout(&g.layouts, key.parameters[i], 0)) return error.Declined;
                    if (key.effects[i] == layout.unknown_row) return error.Declined;
                    key.effects[i] = try self.row(g, .layout, key.effects[i], 0);
                    if (!knownRow(&g.layouts, key.effects[i], 0)) return error.Declined;
                }
                key.result = try self.shape(g, key.result, 0);
                if (!knownLayout(&g.layouts, key.result, 0)) return error.Declined;
                key.templates = try self.templateKey(g, old_key.target.unit, key.templates, 0);
                break :blk .{ .named = key };
            },
            .closure => |old_key| blk: {
                var key = old_key;
                if (old_key.unit == 0 or old_key.unit > self.old.modules.len or old_key.catalog >= self.old.modules[old_key.unit - 1].module.closures.len) return error.Declined;
                key.unit = try self.expressionUnit(old_key.unit, self.old.modules[old_key.unit - 1].module.closures[old_key.catalog].body);
                if (key.catalog >= self.units[key.unit - 1].closures.len) return error.Declined;
                key.ty = try self.shape(g, key.ty, 0);
                key.captures = try self.shape(g, key.captures, 0);
                if (g.layouts.node(key.ty).tag != .function or g.layouts.node(key.captures).tag != .product) return error.Declined;
                if (!knownLayout(&g.layouts, key.ty, 0)) return error.Declined;
                if (old_key.static_values == 0) {
                    if (!knownLayout(&g.layouts, key.captures, 0)) return error.Declined;
                } else {
                    const module = self.old.modules[old_key.unit - 1].module;
                    const capture_span = module.closures[old_key.catalog].captures;
                    const bindings = module.extra[capture_span.start..][0..capture_span.len];
                    const layouts = g.layouts.children(key.captures);
                    if (bindings.len != layouts.len) return error.Declined;
                    const statics = try self.staticEntries(old_key.static_values);
                    for (bindings, layouts) |binding, actual| {
                        const is_static = for (statics) |item| {
                            if (item.variable == binding) break true;
                        } else false;
                        if (!is_static and !knownLayout(&g.layouts, actual, 0)) return error.Declined;
                    }
                }
                key.templates = try self.templateKey(g, old_key.unit, key.templates, 0);
                key.evidence = try self.mappingEvidence(g, old_key.unit, key.evidence, 0);
                key.rows = try self.rowKey(g, old_key.unit, key.rows, 0);
                key.parameter_template = if (key.parameter_template == 0) 0 else try self.capture(g, key.parameter_template, 0);
                key.static_values = if (import_static) try self.staticKey(g, old_key.static_values) else 0;
                break :blk .{ .closure = key };
            },
            .callable => |old_key| .{ .callable = .{ .target = try self.target(old_key.target), .ty = try self.closedShape(g, old_key.ty), .applied = old_key.applied } },
            .constructor => |old_key| blk: {
                const owner = try self.typeUnit(old_key.unit);
                if (old_key.catalog >= self.units[owner - 1].constructors.len) return error.Declined;
                break :blk .{ .constructor = .{ .unit = owner, .catalog = old_key.catalog, .ty = try self.closedShape(g, old_key.ty) } };
            },
            .primitive => |old_key| blk: {
                const owner = try self.unit(old_key.unit, true);
                if (old_key.catalog >= self.units[owner - 1].primitives.len) return error.Declined;
                break :blk .{ .primitive = .{ .unit = owner, .catalog = old_key.catalog, .ty = try self.closedShape(g, old_key.ty), .applied = old_key.applied } };
            },
            .operation => |old_key| blk: {
                if (old_key.operation == 0 or old_key.operation > self.old.operations.len) return error.Declined;
                const operation = self.old.operations[old_key.operation - 1];
                try self.operationScope(g, old_key.operation);
                for (g.runtime_operations.entries.items, 0..) |current, i| {
                    if (current.foreign == operation.foreign and std.mem.eql(u8, current.key, operation.key))
                        break :blk .{ .operation = .{ .operation = @intCast(i + 1), .ty = try self.closedShape(g, old_key.ty) } };
                }
                return error.Declined;
            },
            .host => |old_id| .{ .host = try self.closedShape(g, old_id) },
            // Evaluation and startup are independent fresh revision roots.
            .constant, .runtime_global => error.Declined,
        };
    }
    fn closedShape(self: *Importer, g: anytype, old_id: u32) Error!u32 {
        const id = try self.shape(g, old_id, 0);
        if (!knownLayout(&g.layouts, id, 0)) return error.Declined;
        return id;
    }
    /// Qualifies symbolic references, including unused symbol demands, without
    /// publishing anything in the current runtime operation table. A declined
    /// scope is immutable; an allocation failure never caches a decline.
    pub fn admitOperation(self: *Importer, g: anytype, id: u32) Allocator.Error!bool {
        self.operationScope(g, id) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.Declined => false,
        };
        return true;
    }
    /// Build one old symbol-to-semantic-label index per importer. The private
    /// scratch table and incomplete index disappear together on failure.
    fn indexOperations(self: *Importer) Error!void {
        if (self.operation_labels != null) return;
        const labels = try self.allocator.alloc(u32, self.old.operations.len);
        errdefer self.allocator.free(labels);
        @memset(labels, 0);
        const scopes = try self.allocator.alloc(OperationScope, labels.len);
        errdefer self.allocator.free(scopes);
        @memset(scopes, .unchecked);
        var symbols: std.StringHashMapUnmanaged(usize) = .empty;
        defer symbols.deinit(self.allocator);
        for (self.old.operations, 0..) |operation, i| {
            if (operation.key.len < 2 or operation.key[0] != 1 or operation.key[1] != 'P') continue;
            const slot = try symbols.getOrPut(self.allocator, operation.key);
            if (slot.found_existing) return error.Declined;
            slot.value_ptr.* = i;
        }
        const view = self.old.evaluator.evidence.view();
        var scratch = runtime_operations.Store.initProject(self.allocator, self.old.identity.?.view());
        defer scratch.deinit();
        for (1..view.effects.operations.len) |label| {
            const candidate = scratch.intern(view, @intCast(label)) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            const index = symbols.get(scratch.entries.items[candidate - 1].key) orelse continue;
            if (labels[index] == 0) labels[index] = @intCast(label);
        }
        self.operation_labels = labels;
        self.operation_scopes = scopes;
    }
    fn operationScope(self: *Importer, g: anytype, id: u32) Error!void {
        try self.bind(g);
        if (id == 0 or id > self.old.operations.len) return error.Declined;
        try self.indexOperations();
        const scope = &self.operation_scopes.?[id - 1];
        switch (scope.*) {
            .admitted => return,
            .declined => return error.Declined,
            .unchecked => {},
        }
        self.qualifyOperation(g, id) catch |err| {
            if (err == error.Declined) scope.* = .declined;
            return err;
        };
        scope.* = .admitted;
    }
    fn qualifyOperation(self: *Importer, g: anytype, id: u32) Error!void {
        const label = self.operation_labels.?[id - 1];
        if (label == 0) return error.Declined;
        const operation = self.old.operations[id - 1];
        const view = self.old.evaluator.evidence.view();
        const producer = view.effects.operations[label];
        const arguments = try bounded(u32, view.effects.arguments, producer.arguments.start, producer.arguments.len);
        if (producer.identity.unit == 0) {
            if (producer.identity.decl != 1 or arguments.len != 0 or !operation.foreign) return error.Declined;
        } else {
            _ = try self.nominal(producer.identity.unit, producer.identity.decl);
            if (operation.foreign) return error.Declined;
        }
        for (arguments) |argument| _ = try self.semanticType(g, argument, 0);
    }
    pub fn importLayout(self: *Importer, generator: anytype, old_id: u32) Allocator.Error!?u32 {
        self.bind(generator) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
        return self.shape(generator, old_id, 0) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    }
    pub fn importEvidence(self: *Importer, generator: anytype, old_id: u32) Allocator.Error!?u32 {
        self.bind(generator) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
        return self.semanticType(generator, old_id, 0) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    }

    /// Semantic row IDs belong to their type owner. Exact-query graph admission
    /// validates source operations before requesting this owner-bound import.
    pub fn importSemanticRow(self: *Importer, generator: anytype, old_id: u32) Allocator.Error!?u32 {
        self.bind(generator) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
        return self.row(generator, .semantic, old_id, 0) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    }

    /// Import only the prepass's closed facts, preserving unresolved omissions.
    /// Variable IDs belong to the admitted source owner; evidence and effect
    /// IDs are re-interned from old Pools into this Generator. No values or
    /// validated-call certificates are published by this operation.
    pub fn importPrincipalEvidence(self: *Importer, generator: anytype, old_owner: u32, type_maps: []const evidence.Mapping, row_maps: []const evidence.RowMapping) Allocator.Error!?core_eval.SolvedEvidence {
        return self.principalEvidence(generator, old_owner, type_maps, row_maps) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    }
    /// A retained principal query may also have published a closed call proof.
    /// Its caller must validate the query's full source image and dynamic inputs.
    /// This operation translates the evidence; it publishes no certificate.
    pub fn importPrincipalCall(self: *Importer, generator: anytype, reference: core.BindingRef, actual: u32) Allocator.Error!?u32 {
        return self.principalCall(generator, reference, actual) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    }
    fn principalCall(self: *Importer, generator: anytype, reference: core.BindingRef, actual: u32) Error!u32 {
        try self.bind(generator);
        const previous = try self.oldModule(reference.unit);
        const current = &self.units[(try self.unit(reference.unit, true)) - 1];
        if (reference.binding == 0 or reference.binding >= previous.bindings.len or reference.binding >= current.bindings.len) return error.Declined;
        if (previous.binding(reference.binding).kind != .global or current.binding(reference.binding).kind != .global or previous.body(reference.binding) == null or current.body(reference.binding) == null) return error.Declined;
        var remaining: usize = 1_000_000;
        try self.principalType(actual, 0, &remaining);
        if (self.old.evaluator.evidence.view().node(actual).tag != .function) return error.Declined;
        return self.semanticType(generator, actual, 0);
    }
    fn principalEvidence(self: *Importer, g: anytype, owner: u32, type_maps: []const evidence.Mapping, row_maps: []const evidence.RowMapping) Error!core_eval.SolvedEvidence {
        try self.bind(g);
        const module = try self.oldModule(owner);
        const current = &self.units[(try self.unit(owner, true)) - 1];
        var remaining: usize = 1_000_000;
        for (type_maps, 0..) |mapping, i| {
            if (mapping.variable == 0 or mapping.variable >= module.types.nodes.len or mapping.variable >= current.types.nodes.len) return error.Declined;
            if (module.types.nodes[mapping.variable].tag != .variable or current.types.nodes[mapping.variable].tag != .variable) return error.Declined;
            for (type_maps[0..i]) |previous| if (previous.variable == mapping.variable) return error.Declined;
            try self.principalType(mapping.evidence, 0, &remaining);
        }
        for (row_maps, 0..) |mapping, i| {
            if (mapping.variable >= module.types.effects.variable_count or mapping.variable >= current.types.effects.variable_count) return error.Declined;
            for (row_maps[0..i]) |previous| if (previous.variable == mapping.variable) return error.Declined;
            try self.principalRow(mapping.evidence, 0, &remaining);
        }
        const imported_types = try self.allocator.alloc(evidence.Mapping, type_maps.len);
        errdefer self.allocator.free(imported_types);
        for (type_maps, imported_types) |from, *to| to.* = .{ .variable = from.variable, .evidence = try self.semanticType(g, from.evidence, 0) };
        const imported_rows = try self.allocator.alloc(evidence.RowMapping, row_maps.len);
        errdefer self.allocator.free(imported_rows);
        for (row_maps, imported_rows) |from, *to| to.* = .{ .variable = from.variable, .evidence = try self.row(g, .semantic, from.evidence, 0) };
        return .{ .types = imported_types, .rows = imported_rows };
    }
    fn principalType(self: *const Importer, id: u32, depth: usize, remaining: *usize) Error!void {
        if (depth >= depth_limit or remaining.* == 0 or id == 0 or id >= self.old.evaluator.evidence.nodes.len) return error.Declined;
        remaining.* -= 1;
        const n = self.old.evaluator.evidence.nodes[id];
        switch (n.tag) {
            .absent, .provider, .state_provider, .resolver, .type_constructor => return error.Declined,
            .unit, .boolean, .u32, .f32, .never => if (n.a != 0 or n.b != 0 or n.c != 0) return error.Declined,
            .array, .list, .cursor => {
                if (n.b != 0 or n.c != 0) return error.Declined;
                try self.principalType(n.a, depth + 1, remaining);
            },
            .function => {
                try self.principalType(n.a, depth + 1, remaining);
                try self.principalType(n.b, depth + 1, remaining);
                try self.principalRow(n.c, depth + 1, remaining);
            },
            .demand => {
                if (n.b != 0) return error.Declined;
                try self.principalType(n.a, depth + 1, remaining);
                try self.principalRow(n.c, depth + 1, remaining);
            },
            .product, .record, .nominal => {
                if (n.tag == .nominal) {
                    if (n.a == std.math.maxInt(u32) or n.b == 0) return error.Declined;
                    const current = &self.units[(try self.unit(n.a, true)) - 1];
                    for (current.nominals) |nominal_| {
                        if (nominal_.identity.decl == n.b and (nominal_.identity.unit == 0 or nominal_.identity.unit == current.unit or nominal_.identity.unit == self.unit_map[n.a - 1])) break;
                    } else return error.Declined;
                } else if (n.c != 0) return error.Declined;
                const children = try evidenceChildren(self.old.evaluator.evidence.view(), id);
                for (children, 0..) |child, i| {
                    if (n.tag == .record and i % 2 == 0) {
                        _ = try self.symbol(child);
                    } else try self.principalType(child, depth + 1, remaining);
                }
                if (n.tag == .record) try uniqueFields(children);
            },
        }
    }
    fn principalRow(self: *const Importer, id: u32, depth: usize, remaining: *usize) Error!void {
        const source = self.old.evaluator.evidence.effects.view();
        if (depth >= depth_limit or remaining.* == 0 or id >= source.rows.len) return error.Declined;
        remaining.* -= 1;
        const span = source.rows[id];
        const labels = try bounded(u32, source.labels, span.start, span.len);
        if (id == 0 and labels.len != 0) return error.Declined;
        for (labels) |label| {
            if (label == 0 or label >= source.operations.len) return error.Declined;
            const operation = source.operations[label];
            if (operation.identity.unit == std.math.maxInt(u32)) return error.Declined;
            const arguments = try bounded(u32, source.arguments, operation.arguments.start, operation.arguments.len);
            if (operation.identity.unit == 0) {
                if (operation.identity.decl != 1 or arguments.len != 0) return error.Declined;
            } else _ = try self.nominal(operation.identity.unit, operation.identity.decl);
            for (arguments) |argument| try self.principalType(argument, depth + 1, remaining);
        }
    }

    fn shape(self: *Importer, g: anytype, id: u32, depth: usize) Error!u32 {
        if (depth >= depth_limit or id == 0 or id >= self.old.layouts.nodes.len) return error.Declined;
        if (self.layouts.get(id)) |mapped| return mapped;
        const n = self.old.layouts.nodes[id];
        var values: std.ArrayList(u32) = .empty;
        defer values.deinit(self.allocator);
        var a = n.a;
        var b = n.b;
        var c = n.c;
        switch (n.tag) {
            .invalid => return error.Declined,
            .unit, .boolean, .u32, .f32, .never, .erased => {
                if (a != 0 or b != 0 or c != 0) return error.Declined;
                const mapped: u32 = switch (n.tag) {
                    .unit => 1,
                    .boolean => 2,
                    .u32 => 3,
                    .f32 => 4,
                    .never => 5,
                    .erased => 6,
                    else => unreachable,
                };
                if (g.layouts.node(mapped).tag != n.tag) return error.Declined;
                try self.layouts.put(self.allocator, id, mapped);
                return mapped;
            },
            .product, .record, .nominal => {
                if (n.tag != .nominal and n.c != 0) return error.Declined;
                const children = try shapeChildren(self.old.layouts, id);
                if (n.tag == .nominal) a = try self.nominal(a, b) else {
                    a = 0;
                    b = 0;
                }
                for (children, 0..) |child, i| try values.append(self.allocator, if (n.tag == .record and i % 2 == 0) try self.symbol(child) else try self.shape(g, child, depth + 1));
                if (n.tag == .record) try uniqueFields(values.items);
                c = 0;
            },
            .function => {
                a = try self.shape(g, a, depth + 1);
                b = try self.shape(g, b, depth + 1);
                c = try self.row(g, .layout, c, depth + 1);
            },
            .array, .list, .cursor, .resolver => {
                if (b != 0 or c != 0) return error.Declined;
                a = try self.shape(g, a, depth + 1);
            },
            .demand, .provider => {
                if (b != 0) return error.Declined;
                a = try self.shape(g, a, depth + 1);
                c = try self.row(g, .layout, c, depth + 1);
            },
            .state_provider => {
                a = try self.shape(g, a, depth + 1);
                b = try self.shape(g, b, depth + 1);
                c = try self.shape(g, c, depth + 1);
            },
            .type_constructor => {
                if (c != 0) return error.Declined;
                a = try self.nominal(a, b);
            },
        }
        const mapped = if (n.tag == .state_provider)
            g.layouts.internStateProvider(a, b, c) catch |err| return convert(err)
        else
            g.layouts.internWithEffects(n.tag, a, b, c, values.items) catch |err| return convert(err);
        try self.layouts.put(self.allocator, id, mapped);
        return mapped;
    }
    fn semanticType(self: *Importer, g: anytype, id: u32, depth: usize) Error!u32 {
        if (depth >= depth_limit or id == 0 or id >= self.old.evaluator.evidence.nodes.len) return error.Declined;
        const key: EvidenceKey = .{ .id = id };
        if (self.semantic.get(key)) |mapped| return mapped;
        const n = self.old.evaluator.evidence.nodes[id];
        var a = n.a;
        var b = n.b;
        var c = n.c;
        var values: std.ArrayList(u32) = .empty;
        defer values.deinit(self.allocator);
        switch (n.tag) {
            .absent => return error.Declined,
            .unit, .boolean, .u32, .f32, .never => if (a != 0 or b != 0 or c != 0) return error.Declined,
            .product, .record, .nominal => {
                if (n.tag != .nominal and n.c != 0) return error.Declined;
                const children = try evidenceChildren(self.old.evaluator.evidence.view(), id);
                if (n.tag == .nominal) a = try self.semanticNominal(a, b) else {
                    a = 0;
                    b = 0;
                }
                for (children, 0..) |child, i| try values.append(self.allocator, if (n.tag == .record and i % 2 == 0) try self.symbol(child) else try self.semanticType(g, child, depth + 1));
                if (n.tag == .record) try uniqueFields(values.items);
                c = 0;
            },
            .function => {
                a = try self.semanticType(g, a, depth + 1);
                b = try self.semanticType(g, b, depth + 1);
                c = try self.row(g, .semantic, c, depth + 1);
            },
            .array, .list, .cursor, .resolver => {
                if (b != 0 or c != 0) return error.Declined;
                a = try self.semanticType(g, a, depth + 1);
            },
            .demand, .provider => {
                if (b != 0) return error.Declined;
                a = try self.semanticType(g, a, depth + 1);
                c = try self.row(g, .semantic, c, depth + 1);
            },
            .state_provider => {
                a = try self.semanticType(g, a, depth + 1);
                b = try self.semanticType(g, b, depth + 1);
                c = try self.semanticType(g, c, depth + 1);
            },
            .type_constructor => {
                if (c != 0) return error.Declined;
                a = try self.semanticNominal(a, b);
            },
        }
        const mapped = if (n.tag == .state_provider)
            g.evaluator.evidence.internStateProvider(a, b, c) catch |err| return convert(err)
        else
            g.evaluator.evidence.internWithEffects(n.tag, a, b, c, values.items) catch |err| return convert(err);
        try self.semantic.put(self.allocator, key, mapped);
        return mapped;
    }
    fn row(self: *Importer, g: anytype, domain: Domain, id: u32, depth: usize) Error!u32 {
        if (depth >= depth_limit) return error.Declined;
        if (domain == .layout and id == layout.unknown_row) return layout.unknown_row;
        const key: RowKey = .{ .domain = domain, .id = id };
        if (self.rows.get(key)) |mapped| return mapped;
        const source = if (domain == .layout) self.old.layouts.effects.view() else self.old.evaluator.evidence.effects.view();
        if (id >= source.rows.len) return error.Declined;
        const span = source.rows[id];
        const labels = try bounded(u32, source.labels, span.start, span.len);
        if (id == 0 and labels.len != 0) return error.Declined;
        var imported: std.ArrayList(u32) = .empty;
        defer imported.deinit(self.allocator);
        var arguments: std.ArrayList(u32) = .empty;
        defer arguments.deinit(self.allocator);
        for (labels) |label| {
            if (label == 0 or label >= source.operations.len) return error.Declined;
            const operation = source.operations[label];
            const old_args = try bounded(u32, source.arguments, operation.arguments.start, operation.arguments.len);
            var owner: u32 = undefined;
            if (operation.identity.unit == 0) {
                if (operation.identity.decl != 1 or old_args.len != 0) return error.Declined;
                owner = 0;
            } else owner = if (domain == .semantic) try self.semanticNominal(operation.identity.unit, operation.identity.decl) else try self.nominal(operation.identity.unit, operation.identity.decl);
            arguments.clearRetainingCapacity();
            for (old_args) |argument| try arguments.append(self.allocator, if (domain == .layout) try self.shape(g, argument, depth + 1) else try self.semanticType(g, argument, depth + 1));
            const store = if (domain == .layout) &g.layouts.effects else &g.evaluator.evidence.effects;
            const new_label = store.internOperation(.{ .unit = owner, .decl = operation.identity.decl }, arguments.items) catch |err| return convert(err);
            try imported.append(self.allocator, new_label);
        }
        const store = if (domain == .layout) &g.layouts.effects else &g.evaluator.evidence.effects;
        const mapped = store.internRow(imported.items) catch |err| return convert(err);
        try self.rows.put(self.allocator, key, mapped);
        return mapped;
    }
    fn oldModule(self: *const Importer, owner: u32) Error!*const core.Module {
        _ = try self.typeUnit(owner);
        return self.old.modules[owner - 1].module;
    }
    fn mappingEvidence(self: *Importer, g: anytype, owner: u32, id: u32, depth: usize) Error!u32 {
        if (id == 0) return 0;
        if (depth >= depth_limit or id >= self.old.evaluator.evidence.nodes.len) return error.Declined;
        const key: EvidenceKey = .{ .id = id, .owner = owner, .mappings = true };
        if (self.semantic.get(key)) |mapped| return mapped;
        const module = try self.oldModule(owner);
        const n = self.old.evaluator.evidence.nodes[id];
        if (n.tag != .record) return error.Declined;
        const children = try evidenceChildren(self.old.evaluator.evidence.view(), id);
        var words: std.ArrayList(u32) = .empty;
        defer words.deinit(self.allocator);
        var i: usize = 0;
        while (i < children.len) : (i += 2) {
            const variable = children[i];
            if (variable == 0 or variable >= module.types.nodes.len) return error.Declined;
            try words.appendSlice(self.allocator, &.{ variable, try self.semanticType(g, children[i + 1], depth + 1) });
        }
        try uniqueFields(words.items);
        const mapped = g.evaluator.evidence.intern(.record, 0, 0, words.items) catch |err| return convert(err);
        try self.semantic.put(self.allocator, key, mapped);
        return mapped;
    }
    fn templateKey(self: *Importer, g: anytype, owner: u32, id: u32, depth: usize) Error!u32 {
        if (id == 0) return 0;
        if (depth >= depth_limit) return error.Declined;
        const key: SubstitutionKey = .{ .id = id, .owner = owner };
        if (self.template_keys.get(key)) |mapped| return mapped;
        const module = try self.oldModule(owner);
        const entries = try substitutionEntries(&self.old.templates, id);
        var imported: std.ArrayList(substitutions.Entry) = .empty;
        defer imported.deinit(self.allocator);
        for (entries) |entry| {
            if (entry.variable == 0 or entry.variable >= module.bindings.len) return error.Declined;
            try imported.append(self.allocator, .{ .variable = entry.variable, .value = try self.capture(g, entry.value, depth + 1) });
        }
        const mapped = g.template_keys.intern(imported.items) catch |err| return convert(err);
        try self.template_keys.put(self.allocator, key, mapped);
        return mapped;
    }
    fn rowKey(self: *Importer, g: anytype, owner: u32, id: u32, depth: usize) Error!u32 {
        if (id == 0) return 0;
        if (depth >= depth_limit) return error.Declined;
        const key: SubstitutionKey = .{ .id = id, .owner = owner };
        if (self.row_keys.get(key)) |mapped| return mapped;
        const module = try self.oldModule(owner);
        const entries = try substitutionEntries(&self.old.rows, id);
        var imported: std.ArrayList(substitutions.Entry) = .empty;
        defer imported.deinit(self.allocator);
        for (entries) |entry| {
            if (entry.variable >= module.types.effects.variable_count or entry.value == layout.unknown_row) return error.Declined;
            try imported.append(self.allocator, .{ .variable = entry.variable, .value = try self.row(g, .semantic, entry.value, depth + 1) });
        }
        const mapped = g.row_keys.intern(imported.items) catch |err| return convert(err);
        try self.row_keys.put(self.allocator, key, mapped);
        return mapped;
    }
    fn capture(self: *Importer, g: anytype, id: u32, depth: usize) Error!u32 {
        if (depth >= depth_limit or id == 0 or id > self.old.captures.len) return error.Declined;
        if (self.captures.get(id)) |mapped| return mapped;
        const old_capture = self.old.captures[id - 1];
        const owner = try self.expressionUnit(old_capture.unit, old_capture.node);
        if (old_capture.node == 0 or old_capture.node >= self.units[owner - 1].nodes.len) return error.Declined;
        const imported: artifacts.CapturedTemplate = .{
            .unit = owner,
            .node = old_capture.node,
            .captures = try self.shape(g, old_capture.captures, depth + 1),
            .templates = try self.templateKey(g, old_capture.unit, old_capture.templates, depth + 1),
            .has_environment = old_capture.has_environment,
            .computation = old_capture.computation,
            .evidence = try self.mappingEvidence(g, old_capture.unit, old_capture.evidence, depth + 1),
            .rows = try self.rowKey(g, old_capture.unit, old_capture.rows, depth + 1),
        };
        if (!knownLayout(&g.layouts, imported.captures, 0)) return error.Declined;
        const mapped = if (g.template_instances.get(imported)) |existing| existing else blk: {
            if (g.template_catalog.items.len >= std.math.maxInt(u32)) return error.Declined;
            try g.template_catalog.ensureUnusedCapacity(self.allocator, 1);
            try g.template_instances.ensureUnusedCapacity(self.allocator, 1);
            try self.captures.ensureUnusedCapacity(self.allocator, 1);
            const new_id: u32 = @intCast(g.template_catalog.items.len + 1);
            g.template_catalog.appendAssumeCapacity(imported);
            g.template_instances.putAssumeCapacityNoClobber(imported, new_id);
            break :blk new_id;
        };
        try self.captures.put(self.allocator, id, mapped);
        return mapped;
    }
    pub fn importResultTemplate(self: *Importer, generator: anytype, id: u32) Allocator.Error!?u32 {
        self.bind(generator) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
        return self.capture(generator, id, 0) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    }
    pub fn importSolved(self: *Importer, generator: anytype, job: *const artifacts.Job) Allocator.Error!?Solved {
        return self.solved(generator, job) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    }
    fn solved(self: *Importer, g: anytype, job: *const artifacts.Job) Error!Solved {
        try self.bind(g);
        if (!job.solved or job.state != .complete) return error.Declined;
        const owner = switch (job.request) {
            .named => |key| key.target.unit,
            .closure => |key| key.unit,
            else => return error.Declined,
        };
        const module = try self.oldModule(owner);
        const mappings = try self.allocator.alloc(layout.Mapping, job.mappings.len);
        errdefer self.allocator.free(mappings);
        for (job.mappings, mappings, 0..) |from, *to, i| {
            if (from.variable == 0 or from.variable >= module.types.nodes.len) return error.Declined;
            for (job.mappings[0..i]) |prior| if (prior.variable == from.variable) return error.Declined;
            to.* = .{ .variable = from.variable, .layout = try self.closedShape(g, from.layout) };
        }
        const rows = try self.allocator.alloc(layout.RowMapping, job.rows.len);
        errdefer self.allocator.free(rows);
        for (job.rows, rows, 0..) |from, *to, i| {
            if (from.variable >= module.types.effects.variable_count or from.row == layout.unknown_row) return error.Declined;
            for (job.rows[0..i]) |prior| if (prior.variable == from.variable) return error.Declined;
            to.* = .{ .variable = from.variable, .row = try self.row(g, .layout, from.row, 0) };
            if (!knownRow(&g.layouts, to.row, 0)) return error.Declined;
        }
        const templates = try self.allocator.alloc(substitutions.Entry, job.templates.len);
        errdefer self.allocator.free(templates);
        for (job.templates, templates, 0..) |from, *to, i| {
            if (from.variable == 0 or from.variable >= module.bindings.len) return error.Declined;
            for (job.templates[0..i]) |prior| if (prior.variable == from.variable) return error.Declined;
            to.* = .{ .variable = from.variable, .value = try self.capture(g, from.value, 0) };
        }
        return .{ .mappings = mappings, .rows = rows, .templates = templates };
    }

    fn coreEqual(self: *const Importer, old_module: *const core.Module, current: *const core.Module) Error!bool {
        var identical_namespaces = true;
        for (self.unit_map, 1..) |mapped, i| if (mapped != i) {
            identical_namespaces = false;
        };
        for (self.symbol_map, 0..) |mapped, i| if (mapped != i) {
            identical_namespaces = false;
        };
        if (identical_namespaces and deepEqual(old_module.*, current.*)) return true;
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var copy = try clone(arena.allocator(), old_module.*);
        try self.remapCore(&copy);
        return deepEqual(copy, current.*);
    }
    fn remapIdentity(self: *const Importer, value: *types.NominalIdentity) Error!void {
        if (value.unit == 0 or value.unit == std.math.maxInt(u32)) return;
        value.unit = try self.unit(value.unit, false);
    }
    fn remapReference(self: *const Importer, value: *core.BindingRef) Error!void {
        if (value.unit != 0) value.unit = try self.unit(value.unit, false);
    }
    fn optionalSymbol(self: *const Importer, value: *u32) Error!void {
        if (value.* != 0) value.* = try self.symbol(value.*);
    }
    fn remapCore(self: *const Importer, module: *core.Module) Error!void {
        for (module.field_names) |*field| try self.optionalSymbol(&field.symbol);
        std.mem.sortUnstable(core.FieldName, module.field_names, {}, struct {
            fn less(_: void, left: core.FieldName, right: core.FieldName) bool {
                return left.symbol < right.symbol;
            }
        }.less);
        if (module.unit != 0) module.unit = try self.unit(module.unit, false);
        for (module.types.nodes) |*n| switch (n.tag) {
            .nominal, .type_constructor => if (n.a != 0 and n.a != std.math.maxInt(u32)) {
                n.a = try self.unit(n.a, false);
            },
            .record => {
                const fields = try bounded(u32, module.types.extra, n.a, @as(usize, n.b) * 2);
                var i: usize = 0;
                while (i < fields.len) : (i += 2) module.types.extra[n.a + i] = try self.symbol(fields[i]);
            },
            else => {},
        };
        for (module.types.operations) |*value| try self.remapIdentity(&value.identity);
        for (module.bindings) |*value| try self.remapReference(&value.target);
        for (module.references) |*value| try self.remapReference(value);
        for (module.dependency_references) |*value| try self.remapReference(value);
        for (module.erased_declaration_references) |*value| try self.remapReference(&value.target);
        for (module.dependency_members) |*value| try self.optionalSymbol(&value.name);
        for (module.calls) |*value| try self.remapReference(&value.target);
        for (module.obligations) |*value| {
            try self.remapIdentity(&value.identity);
            try self.optionalSymbol(&value.name);
            if (value.qualification_unit != 0) value.qualification_unit = try self.unit(value.qualification_unit, false);
        }
        for (module.nominals) |*value| try self.remapIdentity(&value.identity);
        for (module.operation_names) |*value| try self.remapIdentity(&value.identity);
        for (module.constructors) |*value| try self.remapIdentity(&value.identity);
        for (module.projections) |*value| {
            try self.remapIdentity(&value.nominal);
            try self.optionalSymbol(&value.field);
        }
        for (module.associated) |*value| {
            try self.remapIdentity(&value.identity);
            try self.remapReference(&value.target);
            try self.optionalSymbol(&value.member);
        }
        for (module.resolver_ops) |*value| {
            try self.remapReference(&value.method);
            try self.optionalSymbol(&value.member);
        }
        for (module.operation_values) |*value| try self.remapIdentity(&value.identity);
        for (module.nodes) |*n| switch (n.tag) {
            .associated => try self.optionalSymbol(&n.c),
            .result_associated => try self.optionalSymbol(&n.b),
            else => {},
        };
    }
};

fn convert(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.Declined;
}
fn bounded(comptime T: type, values: []const T, start: usize, len: usize) Error![]const T {
    if (start > values.len or len > values.len - start) return error.Declined;
    return values[start..][0..len];
}
fn shapeChildren(pool: artifacts.Layouts, id: u32) Error![]const u32 {
    const n = pool.nodes[id];
    return switch (n.tag) {
        .product => bounded(u32, pool.extra, n.a, n.b),
        .record => bounded(u32, pool.extra, n.a, @as(usize, n.b) * 2),
        .nominal => if (n.c >= pool.extra.len) error.Declined else bounded(u32, pool.extra, @as(usize, n.c) + 1, pool.extra[n.c]),
        else => error.Declined,
    };
}
fn evidenceChildren(pool: evidence.View, id: u32) Error![]const u32 {
    const n = pool.nodes[id];
    return switch (n.tag) {
        .product => bounded(u32, pool.extra, n.a, n.b),
        .record => bounded(u32, pool.extra, n.a, @as(usize, n.b) * 2),
        .nominal => if (n.c >= pool.extra.len) error.Declined else bounded(u32, pool.extra, @as(usize, n.c) + 1, pool.extra[n.c]),
        else => error.Declined,
    };
}
fn substitutionEntries(pool: *const artifacts.Substitutions, id: u32) Error![]const substitutions.Entry {
    if (id == 0) return &.{};
    if (id > pool.spans.len) return error.Declined;
    const span = pool.spans[id - 1];
    const entries = try bounded(substitutions.Entry, pool.entries, span.start, span.len);
    for (entries, 0..) |entry, i| if (i != 0 and entry.variable <= entries[i - 1].variable) return error.Declined;
    return entries;
}
fn uniqueFields(words: []const u32) Error!void {
    if (words.len % 2 != 0) return error.Declined;
    var i: usize = 0;
    while (i < words.len) : (i += 2) {
        if (words[i] == 0) return error.Declined;
        var j: usize = 0;
        while (j < i) : (j += 2) if (words[j] == words[i]) return error.Declined;
    }
}
fn knownLayout(store: *const layout.Store, id: u32, depth: usize) bool {
    if (id == 0 or id >= store.nodes.items.len or depth >= depth_limit) return false;
    const n = store.node(id);
    return switch (n.tag) {
        .invalid, .erased => false,
        .function => knownRow(store, n.c, depth + 1) and knownLayout(store, n.a, depth + 1) and knownLayout(store, n.b, depth + 1),
        .demand, .provider => knownRow(store, n.c, depth + 1) and knownLayout(store, n.a, depth + 1),
        .array, .list, .cursor, .resolver => knownLayout(store, n.a, depth + 1),
        .state_provider => knownLayout(store, n.a, depth + 1) and knownLayout(store, n.b, depth + 1) and knownLayout(store, n.c, depth + 1),
        .product, .record, .nominal => blk: {
            for (store.children(id), 0..) |child, i| if (n.tag != .record or i % 2 != 0) {
                if (!knownLayout(store, child, depth + 1)) break :blk false;
            };
            break :blk true;
        },
        else => true,
    };
}
fn knownRow(store: *const layout.Store, id: u32, depth: usize) bool {
    if (depth >= depth_limit or id == layout.unknown_row or id >= store.effects.rows.items.len) return false;
    const view = store.effects.view();
    for (view.rowLabels(id)) |label| for (view.operationArguments(label)) |argument| {
        if (!knownLayout(store, argument, depth + 1)) return false;
    };
    return true;
}
fn copyIdentity(allocator: Allocator, view: identity.View) Allocator.Error!identity.Metadata {
    const bytes = try allocator.dupe(u8, view.bytes);
    errdefer allocator.free(bytes);
    const names = try allocator.dupe(@typeInfo(@TypeOf(view.symbols)).pointer.child, view.symbols);
    errdefer allocator.free(names);
    return .{ .bytes = bytes, .symbols = names, .owners = try allocator.dupe(@typeInfo(@TypeOf(view.owners)).pointer.child, view.owners) };
}
fn deepEqual(left: anytype, right: @TypeOf(left)) bool {
    const T = @TypeOf(left);
    return switch (@typeInfo(T)) {
        .pointer => |pointer| blk: {
            if (pointer.size != .slice) @compileError("Only immutable Core slices are compared");
            if (left.len != right.len) break :blk false;
            for (left, right) |a, b| if (!deepEqual(a, b)) break :blk false;
            break :blk true;
        },
        .array => blk: {
            for (left, right) |a, b| if (!deepEqual(a, b)) break :blk false;
            break :blk true;
        },
        .@"struct" => |structure| blk: {
            inline for (structure.field_names) |name| if (!deepEqual(@field(left, name), @field(right, name))) break :blk false;
            break :blk true;
        },
        .optional => if (left) |a| if (right) |b| deepEqual(a, b) else false else right == null,
        .@"union" => blk: {
            if (std.meta.activeTag(left) != std.meta.activeTag(right)) break :blk false;
            break :blk switch (left) {
                inline else => |a, tag| deepEqual(a, @field(right, @tagName(tag))),
            };
        },
        .void => true,
        else => left == right,
    };
}
fn clone(allocator: Allocator, value: anytype) Allocator.Error!@TypeOf(value) {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .pointer => |pointer| blk: {
            if (pointer.size != .slice) @compileError("Only Core slices are cloned");
            const values = try allocator.alloc(pointer.child, value.len);
            for (value, values) |from, *to| to.* = try clone(allocator, from);
            break :blk values;
        },
        .array => blk: {
            var result: T = undefined;
            for (value, &result) |from, *to| to.* = try clone(allocator, from);
            break :blk result;
        },
        .@"struct" => |structure| blk: {
            var result: T = undefined;
            inline for (structure.field_names) |name| @field(result, name) = try clone(allocator, @field(value, name));
            break :blk result;
        },
        .optional => if (value) |item| try clone(allocator, item) else null,
        .@"union" => switch (value) {
            inline else => |item, tag| @unionInit(T, @tagName(tag), try clone(allocator, item)),
        },
        else => value,
    };
}
