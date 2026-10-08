//! Conservative edited-source admission for owned principal evidence. This
//! gate never grants validity to executable values, slots or generated code.
//! Ordered namespaces and semantic catalogs must agree. Admitted modules
//! preserve their entire structure except isolated scalar constant payloads;
//! optional changed-module admission invalidates changed declarations and their
//! readers. Exact unchanged declaration projections may supply principal proofs.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const artifacts = @import("code_artifacts.zig");
const identity = @import("runtime_identity.zig");
const validation = @import("frozen_core_validation.zig");
const dependencies = @import("declaration_dependencies.zig");
const projection = @import("declaration_projection.zig");
const Allocator = std.mem.Allocator;
const ModuleField = std.meta.FieldEnum(core.Module);

pub const Gate = struct {
    allocator: Allocator,
    units: []const core.Module,
    /// Exact retained Snapshot owner paired with this private gate.
    source_pools: ?*const artifacts.Pools = null,
    enabled: bool = false,
    /// Exact declaration graphs in changed modules may supply principal proofs.
    /// Executable/value/receipt admission still requires structural_units.
    declaration_principals: bool = false,
    dependency_validations: usize = 0,
    reused_dependency_validations: usize = 0,
    dependencies_validated: bool = false,
    validation_symbols: usize = 0,
    /// Exact ordered namespace/structure equality, allowing only the narrowly
    /// permitted scalar value bits. This alone does not establish proof validity.
    structural_units: []const bool,
    offsets: []const usize,
    dirty: []const bool,
    local_dirty: []const bool,
    storage: *Storage,

    // Immutable after construction. Each semantic consumer owns a lease;
    // executable/value admission still lives in its separate gate.
    const Storage = struct { references: usize = 1 };

    pub fn retain(self: *const Gate) Gate {
        std.debug.assert(self.storage.references != std.math.maxInt(usize));
        self.storage.references += 1;
        var result = self.*;
        result.dependency_validations = 0;
        result.reused_dependency_validations = 0;
        return result;
    }

    /// The caller retains immutable current Core through every admits call.
    /// Retained pins and identity remain immutable during initialization; the
    /// gate owns only its flags and does not retain the old artifact owner.
    pub const Execution = struct { reuse_projected_principals: bool = false, reuse_declaration_principals: bool = false, reuse_unaffected_modules: bool = false, reuse_equivalent_validation: bool = false, stamps: ?*artifacts.ModuleStamps = null };

    pub fn init(allocator: Allocator, old: *const artifacts.Pools, units: []const core.Module, names: ?identity.View) Allocator.Error!Gate {
        return initWithExecution(allocator, old, units, names, .{});
    }

    /// Changed-module admission keeps its semantic catalogs exact and marks
    /// declarations dirty unless an exact principal projection is enabled.
    pub fn initWithExecution(allocator: Allocator, old: *const artifacts.Pools, units: []const core.Module, names: ?identity.View, execution: Execution) Allocator.Error!Gate {
        const structural_units = try allocator.alloc(bool, units.len);
        errdefer allocator.free(structural_units);
        @memset(structural_units, false);
        const offsets = try allocator.alloc(usize, units.len + 1);
        errdefer allocator.free(offsets);
        offsets[0] = 0;
        for (units, 0..) |module, i| offsets[i + 1] = std.math.add(usize, offsets[i], module.bindings.len) catch return error.OutOfMemory;
        const dirty = try allocator.alloc(bool, offsets[units.len]);
        errdefer allocator.free(dirty);
        @memset(dirty, false);
        const local_dirty = try allocator.alloc(bool, offsets[units.len]);
        errdefer allocator.free(local_dirty);
        @memset(local_dirty, true);
        const storage = try allocator.create(Storage);
        errdefer allocator.destroy(storage);
        storage.* = .{};
        var result: Gate = .{ .storage = storage, .allocator = allocator, .source_pools = old, .units = units, .declaration_principals = execution.reuse_declaration_principals, .structural_units = structural_units, .offsets = offsets, .dirty = dirty, .local_dirty = local_dirty };

        if (!old.project_identity or old.identity == null or names == null or old.modules.len != units.len or units.len == 0 or units.len >= std.math.maxInt(u32)) return result;
        // Check every retained pointer against its original pin before comparing
        // any current structure or using a retained dependency recipe.
        for (old.modules) |pin| if (!std.mem.eql(u8, &pin.stamp, &try artifacts.moduleStamp(pin.module, execution.stamps))) return result;
        const previous = old.identity.?.view();
        const current = names.?;
        if (!try namespaceEqual(allocator, old, units, previous, current)) return result;

        var all_structural = true;
        for (units, old.modules, 0..) |*module, pin, unit| {
            const exact = if (execution.stamps) |stamps| try stamps.proveSame(pin.module, module) else false;
            structural_units[unit] = exact or moduleEqual(pin.module, module);
            all_structural = all_structural and structural_units[unit];
        }
        if (!all_structural) {
            if (!execution.reuse_unaffected_modules) return result;
            for (units, old.modules, structural_units) |*module, pin, structural| {
                if (!structural and !catalogEqual(pin.module, module)) return result;
            }
        }

        const old_units = try allocator.alloc(*const core.Module, units.len);
        defer allocator.free(old_units);
        const current_units = try allocator.alloc(*const core.Module, units.len);
        defer allocator.free(current_units);
        for (old.modules, units, old_units, current_units) |pin, *module, *old_unit, *current_unit| {
            old_unit.* = pin.module;
            current_unit.* = module;
        }
        // Foreign Core validation currently observes only module identities
        // and binding-table bounds. Those domains can remain equal even when
        // a sibling's executable body changes. The local graph/dependency
        // scan is then equivalent for each structurally unchanged module.
        const equivalent_context = validation.equivalentContext(
            .{ .units = old_units, .symbol_count = previous.symbols.len },
            .{ .units = current_units, .symbol_count = current.symbols.len },
        );
        const old_context: validation.Context = .{ .units = old_units, .symbol_count = previous.symbols.len };
        const certified_context = if (old.dependency_certificate) |*certificate| certificate.matches(old_context) else false;
        for (units, old.modules, structural_units, 0..) |*module, pin, structural, unit| {
            if (certified_context and old.dependency_certificate.?.admits(unit, pin.stamp)) {
                // Every pin was checked against its current immutable bytes
                // above; the certificate also owns its original stamp.
                result.reused_dependency_validations += 1;
            } else {
                result.dependency_validations += 1;
                if (!try validDependencies(allocator, pin.module, old_units, previous.symbols.len)) return result;
            }
            // namespaceEqual and moduleEqual proved this local graph equal
            // except isolated scalar constant payload bits. Frozen validation
            // and dependency capture never interpret a constant's payload as
            // an edge, list, identity, role or bound. Their old/current inputs
            // therefore have equal validation results when foreign bounds
            // also agree. Every dirty/source/catalog check still runs, and
            // changed modules always receive their own full validation.
            if (!execution.reuse_equivalent_validation or !structural or !equivalent_context) {
                result.dependency_validations += 1;
                if (!try validDependencies(allocator, module, current_units, current.symbols.len)) return result;
            }
        }
        result.dependencies_validated = true;
        result.validation_symbols = current.symbols.len;
        // All source declarations must have complete bodies. Imported aliases
        // must resolve to such a declaration, never a lexical or absent target.
        for (units, 0..) |module, unit| for (module.bindings[1..], 1..) |binding, id| switch (binding.kind) {
            .global => if (binding.body_id == 0) return result,
            .external => if (result.declaration(.{ .unit = @intCast(unit + 1), .binding = @intCast(id) }) == null) return result,
            .local, .parameter => {},
        };
        for (units, 0..) |module, unit| {
            for (module.dependency_references) |reference| {
                const target = core.BindingRef{ .unit = if (reference.unit == 0) @intCast(unit + 1) else reference.unit, .binding = reference.binding };
                if (result.declaration(target) == null) return result;
            }
            for (module.associated) |candidate| {
                const target = core.BindingRef{ .unit = if (candidate.target.unit == 0) @intCast(unit + 1) else candidate.target.unit, .binding = candidate.target.binding };
                if (result.declaration(target) == null) return result;
            }
        }

        for (units, old.modules, 0..) |module, pin, unit| {
            if (!structural_units[unit]) {
                // Whole-module executable reuse stays disabled. An exact
                // declaration projection may retain only its principal proof.
                @memset(dirty[offsets[unit]..offsets[unit + 1]], true);
                if (execution.reuse_declaration_principals) for (module.bindings[1..], 1..) |binding, id| {
                    const same = switch (binding.kind) {
                        .global => try projection.definitionEqual(allocator, pin.module, &module, @intCast(id)),
                        .external => id < pin.module.bindings.len and std.meta.eql(pin.module.bindings[id], binding),
                        .local, .parameter => false,
                    };
                    dirty[offsets[unit] + id] = !same;
                };
                continue;
            }
            for (module.nodes, pin.module.nodes, 0..) |node, before, id| {
                if (node.a == before.a) continue;
                const binding = scalarRoot(module, @intCast(id)) orelse return result;
                dirty[offsets[unit] + binding] = true;
            }
        }

        @memcpy(local_dirty, dirty);
        // A fixed point also handles recursive source declarations. External
        // aliases are vertices: a read of either the alias or its producer is
        // invalidated by the same transitive source change.
        var changed = true;
        while (changed) {
            changed = false;
            for (units, 0..) |module, unit| {
                for (module.bindings[1..], 1..) |binding, id| {
                    const index = offsets[unit] + id;
                    if (dirty[index]) continue;
                    if (binding.kind == .external) {
                        if (result.targetDirty(unit, binding.target)) {
                            dirty[index] = true;
                            changed = true;
                        }
                    } else if (binding.kind == .global) {
                        const recipe = module.declaration_dependencies[binding.body_id];
                        for (module.dependency_references[recipe.references.start..][0..recipe.references.len]) |target| {
                            if (result.targetDirty(unit, target)) {
                                dirty[index] = true;
                                changed = true;
                                break;
                            }
                        }
                    }
                }
            }
        }
        // Principal selection can inspect a candidate that leaves no named
        // executable reference. Until selected-member edges are independently
        // complete, any dirty catalog candidate disables the entire gate.
        for (units, 0..) |module, unit| for (module.associated) |candidate| {
            if (result.targetDirty(unit, candidate.target)) return result;
        };
        result.enabled = true;
        return result;
    }

    /// Callers pass an explicit producer unit; a local unit-zero spelling has
    /// no unambiguous meaning at this context-free admission boundary.
    pub fn admits(self: *const Gate, target: core.BindingRef) bool {
        if (!self.enabled or target.unit == 0 or target.unit > self.units.len or target.binding == 0) return false;
        const unit = target.unit - 1;
        if (!self.structural_units[unit]) return false;
        return self.admitsPrincipal(target);
    }

    /// An enabled gate has checked the entire ordered type/nominal/effect
    /// catalog, including payload types, constructors and operation arguments.
    /// Catalog identity can survive an executable body edit. This grants only
    /// semantic identities; body IDs, closures and code still require admits.
    /// Pair the retained owner before any consumer reads its nominal tables.
    pub fn admitsCatalog(self: *const Gate, pools: *const artifacts.Pools, unit: u32) bool {
        return self.enabled and self.source_pools == pools and unit != 0 and
            unit <= pools.modules.len and unit <= self.units.len;
    }

    /// No body IDs, closures or value graphs cross this proof-only boundary.
    /// Nonempty evidence import separately requires its exact source owner.
    pub fn admitsPrincipal(self: *const Gate, target: core.BindingRef) bool {
        if (!self.enabled or target.unit == 0 or target.unit > self.units.len or target.binding == 0) return false;
        const unit = target.unit - 1;
        if (!self.structural_units[unit] and !self.declaration_principals) return false;
        const module = self.units[unit];
        if (target.binding >= module.bindings.len) return false;
        const binding = module.bindings[target.binding];
        return binding.kind == .global and binding.body_id != 0 and !self.dirty[self.offsets[unit] + target.binding];
    }

    /// Source reads and persistent proof reads/writes all carry source IDs.
    /// Check each domain before any replay can index a changed module's tables.
    pub fn admitsReceipt(self: *const Gate, record: anytype) bool {
        for (record.sources) |source| if (!self.admits(source)) return false;
        for (record.scalar_reads) |read| if (!self.admits(read.target)) return false;
        for (record.call_reads) |read| if (!self.admits(.{ .unit = read.unit, .binding = read.binding })) return false;
        for (record.call_publications) |call| if (!self.admits(.{ .unit = call.unit, .binding = call.binding })) return false;
        return true;
    }

    /// A source collection reads this exact body. Its separately recorded
    /// callees and dynamic facts decide whether transitive edits matter.
    pub fn admitsLocalSource(self: *const Gate, target: core.BindingRef) bool {
        if (!self.admitsCallIdentity(target)) return false;
        const unit = target.unit - 1;
        return (self.structural_units[unit] or self.declaration_principals) and !self.local_dirty[self.offsets[unit] + target.binding];
    }

    /// Identity alone permits comparing a freshly established closed judgment.
    /// It never admits an old body, call proof, value or executable fragment.
    pub fn admitsCallIdentity(self: *const Gate, target: core.BindingRef) bool {
        if (!self.enabled or target.unit == 0 or target.unit > self.units.len or target.binding == 0) return false;
        const current = &self.units[target.unit - 1];
        const old = self.source_pools.?.modules[target.unit - 1].module;
        if (target.binding >= current.bindings.len or target.binding >= old.bindings.len) return false;
        const left = old.binding(target.binding);
        const right = current.binding(target.binding);
        if (left.kind != .global or right.kind != .global or left.ty != right.ty) return false;
        if (!equal(old.source_names, current.source_names)) return false;
        const before = old.body(target.binding) orelse return false;
        const after = current.body(target.binding) orelse return false;
        return before.runtime == after.runtime and before.is_function == after.is_function and equal(before.scheme, after.scheme);
    }

    pub fn admitsRefinement(self: *const Gate, record: anytype) bool {
        for (record.sources) |source| if (!self.admitsLocalSource(source)) return false;
        for (record.scalar_reads) |read| if (!self.admits(read.target)) return false;
        for (record.call_reads) |read| {
            const target: core.BindingRef = .{ .unit = read.unit, .binding = read.binding };
            if (read.present) {
                if (!self.admitsCallIdentity(target)) return false;
            } else if (!self.admitsLocalSource(target)) return false;
        }
        for (record.call_publications) |call| if (!self.admitsLocalSource(.{ .unit = call.unit, .binding = call.binding })) return false;
        return true;
    }

    pub fn deinit(self: *Gate) void {
        self.storage.references -= 1;
        if (self.storage.references == 0) {
            self.allocator.free(self.structural_units);
            self.allocator.free(self.offsets);
            self.allocator.free(self.dirty);
            self.allocator.free(self.local_dirty);
            self.allocator.destroy(self.storage);
        }
        self.* = undefined;
    }

    /// Called only while these exact current modules remain immutable. The
    /// candidate owns the certificate; failure cannot mutate the old revision.
    pub fn freezeValidation(self: *const Gate, a: Allocator, pins: []const artifacts.ModulePin) Allocator.Error!?@import("dependency_certificate.zig").Certificate {
        if (!self.dependencies_validated or pins.len != self.units.len) return null;
        const units = try a.alloc(*const core.Module, pins.len);
        defer a.free(units);
        for (pins, self.units, units) |pin, *module, *unit| {
            if (pin.module != module) return null;
            unit.* = module;
        }
        return try @import("dependency_certificate.zig").Certificate.capture(a, .{ .units = units, .symbol_count = self.validation_symbols }, pins);
    }

    fn targetDirty(self: *const Gate, owner: usize, target: core.BindingRef) bool {
        const unit = if (target.unit == 0) owner else target.unit - 1;
        return self.dirty[self.offsets[unit] + target.binding];
    }

    fn declaration(self: *const Gate, initial: core.BindingRef) ?core.BindingRef {
        var target = initial;
        var remaining = self.dirty.len;
        while (remaining != 0) : (remaining -= 1) {
            if (target.unit == 0 or target.unit > self.units.len or target.binding == 0) return null;
            const module = self.units[target.unit - 1];
            if (target.binding >= module.bindings.len) return null;
            const binding = module.bindings[target.binding];
            if (binding.kind == .global) return if (binding.body_id == 0) null else target;
            if (binding.kind != .external) return null;
            target = .{ .unit = if (binding.target.unit == 0) target.unit else binding.target.unit, .binding = binding.target.binding };
        }
        return null;
    }
};

/// A changed executable module cannot change global selection or semantic
/// identity. This initial projection keeps its complete type/obligation graph
/// and ordered catalogs exact. Body IDs and local executable tables may move;
/// executable reuse stays disabled. Individual principal proofs require a
/// separate exact declaration projection and transitive dependency validation.
/// A new Core field must explicitly choose one of these domains.
fn catalogEqual(previous: *const core.Module, current: *const core.Module) bool {
    inline for (@typeInfo(core.Module).@"struct".field_names) |name| {
        const field = @field(ModuleField, name);
        switch (field) {
            .unit, .types, .nominals, .constructors, .associated, .operation_names, .names, .field_names, .obligations => {
                if (!equal(@field(previous, name), @field(current, name))) return false;
            },
            // Witness expressions require their own dependency projection.
            .operation_values, .diagnostics => {
                if (@field(previous, name).len != 0 or @field(current, name).len != 0) return false;
            },
            .runtime_names,
            .source_names,
            .declaration_dependencies,
            .dependency_references,
            .dependency_members,
            .erased_declaration_references,
            .request_loops,
            .request_arms,
            .tag_calls,
            .nodes,
            .spans,
            .extra,
            .bindings,
            .bodies,
            .parameters,
            .references,
            .calls,
            .merges,
            .merge_ranges,
            .projections,
            .projection_variants,
            .patterns,
            .pattern_rows,
            .match_arms,
            .matches,
            .updates,
            .update_steps,
            .closures,
            .primitives,
            .loops,
            .loop_carries,
            .resolver_ops,
            .handle_effects,
            .dispatch_signatures,
            .body_lowerings,
            => {},
        }
    }
    // Constructor ordering lives in the executable extra array but belongs to
    // the nominal catalog. Validate its bounds before the full graph checker.
    for (previous.nominals) |nominal| {
        const list = nominal.constructors;
        if (list.start > previous.extra.len or list.len > previous.extra.len - list.start or list.start > current.extra.len or list.len > current.extra.len - list.start) return false;
        if (!equal(previous.extra[list.start..][0..list.len], current.extra[list.start..][0..list.len])) return false;
    }
    return true;
}

fn namespaceEqual(allocator: Allocator, old: *const artifacts.Pools, units: []const core.Module, previous: identity.View, current: identity.View) Allocator.Error!bool {
    if (previous.owners.len != units.len or current.owners.len != units.len or previous.symbols.len == 0 or previous.symbols.len != current.symbols.len) return false;
    // Equality is structural, including byte/table order; hashes and ordinal
    // coincidences cannot turn different producer identities into a match.
    if (!equal(previous, current)) return false;
    if (current.symbols[0].start != 0 or current.symbols[0].len != 0) return false;
    var paths: std.StringHashMapUnmanaged(void) = .empty;
    defer paths.deinit(allocator);
    for (units, old.modules, 0..) |module, pin, i| {
        if (module.unit != i + 1 or pin.unit != i + 1 or pin.module.unit != pin.unit) return false;
        const path = current.owner(@intCast(i + 1)) orelse return false;
        if (path.len == 0 or !std.unicode.utf8ValidateSlice(path) or std.mem.findScalar(u8, path, 0) != null or !std.mem.eql(u8, path, pin.canonical_path)) return false;
        if ((try paths.getOrPut(allocator, path)).found_existing) return false;
    }
    var spellings: std.StringHashMapUnmanaged(void) = .empty;
    defer spellings.deinit(allocator);
    for (1..current.symbols.len) |i| {
        const spelling = current.symbol(@intCast(i)) orelse return false;
        if (spelling.len == 0 or !std.unicode.utf8ValidateSlice(spelling) or std.mem.findScalar(u8, spelling, 0) != null) return false;
        if ((try spellings.getOrPut(allocator, spelling)).found_existing) return false;
    }
    return true;
}

fn validDependencies(allocator: Allocator, module: *const core.Module, units: []const *const core.Module, symbol_count: usize) Allocator.Error!bool {
    validation.validate(allocator, module, .{ .units = units, .symbol_count = symbol_count }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidArtifact => return false,
    };
    // Lowering always records the source declaration erased by Effects.of.
    // The dependency rescan cannot reconstruct a missing producer identity
    // from the reflected effect row, so verify this mandatory source metadata.
    var erased: usize = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .effect_reflection or node.a != @backingInt(@import("check.zig").ReflectionKind.of)) continue;
        if (erased >= module.erased_declaration_references.len or module.erased_declaration_references[erased].node != id) return false;
        erased += 1;
    }
    if (erased != module.erased_declaration_references.len) return false;
    var scanned = module.*;
    scanned.declaration_dependencies = &.{};
    scanned.dependency_references = &.{};
    scanned.dependency_members = &.{};
    dependencies.capture(allocator, &scanned) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CoreLimit => return false,
    };
    defer allocator.free(scanned.declaration_dependencies);
    defer allocator.free(scanned.dependency_references);
    defer allocator.free(scanned.dependency_members);
    return equal(module.declaration_dependencies, scanned.declaration_dependencies) and equal(module.dependency_references, scanned.dependency_references) and equal(module.dependency_members, scanned.dependency_members);
}

fn moduleEqual(previous: *const core.Module, current: *const core.Module) bool {
    inline for (@typeInfo(core.Module).@"struct".field_names) |name| {
        if (comptime !std.mem.eql(u8, name, "nodes")) {
            if (!equal(@field(previous, name), @field(current, name))) return false;
        }
    }
    if (previous.nodes.len != current.nodes.len) return false;
    for (previous.nodes, current.nodes, 0..) |before, after, id| {
        var normalized = after;
        if (before.a != after.a) {
            if (scalarRoot(previous.*, @intCast(id)) == null or scalarRoot(current.*, @intCast(id)) == null) return false;
            normalized.a = before.a;
        }
        if (!equal(before, normalized)) return false;
    }
    return true;
}

fn equal(left: anytype, right: @TypeOf(left)) bool {
    const V = @TypeOf(left);
    return switch (@typeInfo(V)) {
        .pointer => |pointer| blk: {
            if (pointer.size != .slice) @compileError("Principal gate compares owned structural slices only");
            if (left.len != right.len) break :blk false;
            for (left, right) |a, b| if (!equal(a, b)) break :blk false;
            break :blk true;
        },
        .array => blk: {
            for (left, right) |a, b| if (!equal(a, b)) break :blk false;
            break :blk true;
        },
        .@"struct" => |structure| blk: {
            inline for (structure.field_names) |name| if (!equal(@field(left, name), @field(right, name))) break :blk false;
            break :blk true;
        },
        .optional => if (left) |a| if (right) |b| equal(a, b) else false else right == null,
        .@"union" => blk: {
            if (std.meta.activeTag(left) != std.meta.activeTag(right)) break :blk false;
            break :blk switch (left) {
                inline else => |value, tag| equal(value, @field(right, @tagName(tag))),
            };
        },
        .int, .float, .bool, .@"enum" => left == right,
        .void => true,
        else => @compileError("Unsupported principal gate structural field " ++ @typeName(V)),
    };
}

fn rangeHas(values: []const u32, range: anytype, id: core.Id) bool {
    if (range.start > values.len or range.len > values.len - range.start) return true;
    return std.mem.findScalar(u32, values[range.start..][0..range.len], id) != null;
}

/// An allowed scalar node has exactly one declaration owner and no structural
/// consumers. Other declarations must read its binding, where dependency
/// propagation can invalidate them, rather than share the changed node itself.
fn scalarRoot(module: core.Module, id: core.Id) ?core.BindingId {
    if (id == 0 or id >= module.nodes.len or module.bodies.len == 0) return null;
    const node = module.nodes[id];
    if (node.tag != .constant or node.op != .none or node.b != 0 or node.c != 0 or node.ty >= module.types.nodes.len) return null;
    switch (module.types.nodes[node.ty].tag) {
        .boolean, .u32, .f32 => {},
        else => return null,
    }
    var owner: ?core.BindingId = null;
    for (module.bodies[1..]) |body| {
        if (body.root != id) continue;
        if (owner != null or body.binding == 0 or body.binding >= module.bindings.len or body.is_function or body.runtime or body.parameters.len != 0 or module.bindings[body.binding].kind != .global) return null;
        owner = body.binding;
    }
    const binding = owner orelse return null;
    for (module.bindings, 0..) |value, index| if (value.initializer == id and index != binding) return null;
    for (module.nodes) |value| switch (value.tag) {
        .scalar, .logical, .apply, .associated, .record_merge, .type_same, .effect_provider, .handle => if (value.a == id or value.b == id) return null,
        .if_value, .if_stmt, .state_provider => if (value.a == id or value.b == id or value.c == id) return null,
        .bind => if (value.b == id) return null,
        .return_, .force, .project, .computation, .result_associated => if (value.a == id) return null,
        .construct => if (value.b == id) return null,
        .block, .suite, .product, .record, .array, .array_op => if (rangeHas(module.extra, core.List{ .start = value.a, .len = value.b }, id)) return null,
        .call, .break_ => if (rangeHas(module.extra, core.List{ .start = value.b, .len = value.c }, id)) return null,
        .pattern_bind => if (value.b == id or value.c == id) return null,
        .request_decision => if (value.b == id or value.c == id) return null,
        .effect_reflection => if (value.a >= @backingInt(@import("check.zig").ReflectionKind.count) and (value.b == id or value.c == id)) return null,
        else => {},
    };
    for (module.closures) |value| if (value.body == id) return null;
    for (module.patterns) |value| if (value.tag == .value and value.a == id) return null;
    for (module.matches) |value| if (rangeHas(module.extra, value.inputs, id)) return null;
    for (module.match_arms) |value| if (value.body == id or value.guard == id) return null;
    for (module.updates) |value| if (value.root == id or value.value == id) return null;
    for (module.update_steps) |value| if (value.kind == .index and value.index == id) return null;
    for (module.loops) |value| if (value.first == id or value.end == id or value.body == id) return null;
    for (module.resolver_ops) |value| if (value.resolver == id or rangeHas(module.extra, value.arguments, id)) return null;
    for (module.operation_values) |value| if (value.witness == id) return null;
    for (module.request_loops) |value| if (value.computation == id or value.completion_body == id) return null;
    for (module.request_arms) |value| if (value.callback == id) return null;
    return binding;
}
