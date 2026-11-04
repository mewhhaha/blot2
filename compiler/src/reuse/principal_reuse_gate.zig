//! Conservative edited-source admission for owned principal evidence. This
//! gate never grants validity to executable values, slots or generated code.
//! Ordered namespaces and semantic catalogs must agree. Admitted modules
//! preserve their entire structure except isolated scalar constant payloads;
//! optional changed-module admission invalidates changed declarations, the
//! declarations that may select a changed associated function by type, and
//! their readers. Exact unchanged declaration projections may supply principal
//! proofs.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const artifacts = @import("code_artifacts.zig");
const identity = @import("../backend/runtime_identity.zig");
const validation = @import("../check/frozen_core_validation.zig");
const dependencies = @import("declaration_dependencies.zig");
const projection = @import("declaration_projection.zig");
const equal = @import("../structural.zig").equal;
const Allocator = std.mem.Allocator;
const ModuleField = std.meta.FieldEnum(core.Module);

pub const Gate = struct {
    constant_types: bool = false,
    has_generative_sources: bool = false,
    allocator: Allocator,
    units: []const core.Module,
    /// Exact retained Snapshot owner paired with this private gate.
    source_pools: ?*const artifacts.Pools = null,
    enabled: bool = false,
    dependency_validations: usize = 0,
    reused_dependency_validations: usize = 0,
    projection_scans: usize = 0,
    projection_visits: usize = 0,
    projection_workspace_peak_bytes: usize = 0,
    dependencies_validated: bool = false,
    validation_symbols: usize = 0,
    validation_names: ?identity.View = null,
    /// Exact ordered namespace/structure equality, allowing only the narrowly
    /// permitted scalar value bits. This alone does not establish proof validity.
    structural_units: []const bool,
    /// Units whose old certificate image exactly matched the old pin and whose
    /// current module is exactly stream-equal to that pin (`proveSame`). The
    /// old image bytes therefore equal the current module's image.
    certified_images: []const bool,
    /// For each closure catalog entry of a non-structural unit, the global
    /// declaration whose exact projection reached it, or zero.
    closure_owners: []const u32,
    closure_offsets: []const usize,
    offsets: []const usize,
    dirty: []const bool,
    local_dirty: []const bool,
    call_origins: []const bool,
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
        result.projection_scans = 0;
        result.projection_visits = 0;
        result.projection_workspace_peak_bytes = 0;
        return result;
    }

    /// The caller retains immutable current Core through every admits call.
    /// Retained pins and identity remain immutable during initialization; the
    /// gate owns only its flags and does not retain the old artifact owner.
    pub fn init(allocator: Allocator, old: *const artifacts.Pools, units: []const core.Module, names: ?identity.View) Allocator.Error!Gate {
        return initWithStamps(allocator, old, units, names, null);
    }

    /// Changed-module admission keeps its semantic catalogs exact; exact
    /// declaration projections may retain principal proofs in changed modules.
    /// Executable/value/receipt admission still requires structural_units.
    pub fn initWithStamps(allocator: Allocator, old: *const artifacts.Pools, units: []const core.Module, names: ?identity.View, stamps: ?*artifacts.ModuleStamps) Allocator.Error!Gate {
        return initMode(allocator, old, units, names, stamps, false);
    }

    /// Dedicated constant receipts retain their own exact initializer and read
    /// proof. A duplicate closed type appended by an old evaluation has no
    /// semantic identity; it may disappear when frontend body facts replay.
    /// This mode never authorizes ordinary principal or executable reuse.
    pub fn initConstantReceipts(allocator: Allocator, old: *const artifacts.Pools, units: []const core.Module, names: ?identity.View, stamps: ?*artifacts.ModuleStamps) Allocator.Error!Gate {
        return initMode(allocator, old, units, names, stamps, true);
    }

    fn initMode(allocator: Allocator, old: *const artifacts.Pools, units: []const core.Module, names: ?identity.View, stamps: ?*artifacts.ModuleStamps, constant_types: bool) Allocator.Error!Gate {
        const structural_units = try allocator.alloc(bool, units.len);
        errdefer allocator.free(structural_units);
        @memset(structural_units, false);
        const certified_images = try allocator.alloc(bool, units.len);
        errdefer allocator.free(certified_images);
        @memset(certified_images, false);
        const closure_offsets = try allocator.alloc(usize, units.len + 1);
        errdefer allocator.free(closure_offsets);
        closure_offsets[0] = 0;
        for (units, 0..) |module, i| closure_offsets[i + 1] = std.math.add(usize, closure_offsets[i], module.closures.len) catch return error.OutOfMemory;
        const closure_owners = try allocator.alloc(u32, closure_offsets[units.len]);
        errdefer allocator.free(closure_owners);
        @memset(closure_owners, 0);
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
        const call_origins = try allocator.alloc(bool, offsets[units.len]);
        errdefer allocator.free(call_origins);
        @memset(call_origins, false);
        const storage = try allocator.create(Storage);
        errdefer allocator.destroy(storage);
        storage.* = .{};
        var result: Gate = .{ .constant_types = constant_types, .storage = storage, .allocator = allocator, .source_pools = old, .units = units, .structural_units = structural_units, .certified_images = certified_images, .closure_owners = closure_owners, .closure_offsets = closure_offsets, .offsets = offsets, .dirty = dirty, .local_dirty = local_dirty, .call_origins = call_origins };

        if (!old.project_identity or old.identity == null or names == null or old.modules.len != units.len or units.len == 0 or units.len >= std.math.maxInt(u32)) return result;
        // Artifact/query records below use one-based catalog positions. The
        // general evaluator also accepts explicit, non-dense Core unit IDs;
        // decline this adapter until its entire reference protocol maps them.
        for (units, 0..) |module, index| if (module.unit != 0 and module.unit != index + 1) return result;
        // Check every retained pointer against its original pin before comparing
        // any current structure or using a retained dependency recipe.
        for (old.modules, 0..) |*pin, index| {
            if (!try artifacts.pinIntact(pin, stamps)) return result;
            if (pin.module.unit != 0 and pin.module.unit != index + 1) return result;
        }
        for (units, old.modules) |*module, pin| {
            result.has_generative_sources = result.has_generative_sources or @import("source_value_template.zig").moduleGenerative(module) or @import("source_value_template.zig").moduleGenerative(pin.module);
        }
        const previous = old.identity.?.view();
        const current = names.?;
        if (!try namespaceEqual(allocator, old, units, previous, current)) return result;

        var all_structural = true;
        for (units, old.modules, 0..) |*module, pin, unit| {
            const exact = if (stamps) |checker| try checker.proveSame(pin.module, module) else false;
            structural_units[unit] = exact or moduleEqual(pin.module, module);
            certified_images[unit] = exact;
            all_structural = all_structural and structural_units[unit];
        }
        if (!all_structural) {
            for (units, old.modules, structural_units) |*module, pin, structural| {
                if (!structural and !catalogEqual(pin.module, module, constant_types)) return result;
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
        // Equal local graphs own caller classification. Validators observing
        // foreign bodies/types decline until exact receipts own those inputs.
        const equivalent_context = validation.equivalentContext(
            .{ .units = old_units, .symbol_count = previous.symbols.len },
            .{ .units = current_units, .symbol_count = current.symbols.len },
            old_units,
            current_units,
        );
        const old_context: validation.Context = .{ .units = old_units, .symbol_count = previous.symbols.len };
        const certified_context = if (old.dependency_certificate) |*certificate| certificate.matches(old_context, previous, old_units) else false;
        // A certificate captured for exactly these pins (the previous edit's
        // current modules) certifies every one of them, whatever the
        // validators observe across modules.
        const same_context = !certified_context and if (old.dependency_certificate) |*certificate| certificate.sameContext(old_context, previous, old.modules) else false;
        for (units, old.modules, structural_units, 0..) |*module, pin, structural, unit| {
            if (same_context or (certified_context and old.dependency_certificate.?.admits(unit, pin))) {
                // Every pin was checked against its current immutable bytes
                // above; the certificate also owns its original token.
                result.reused_dependency_validations += 1;
            } else {
                certified_images[unit] = false;
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
            if (!structural or !equivalent_context) {
                result.dependency_validations += 1;
                if (!try validDependencies(allocator, module, current_units, current.symbols.len)) return result;
            }
        }
        result.dependencies_validated = true;
        result.validation_symbols = current.symbols.len;
        result.validation_names = current;
        for (units, old.modules, 0..) |*module, pin, unit| {
            try @import("declaration_origins.zig").mark(allocator, pin.module, module, call_origins[offsets[unit]..offsets[unit + 1]]);
        }
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

        var reached: std.ArrayList(u32) = .empty;
        defer reached.deinit(allocator);
        for (units, old.modules, 0..) |module, pin, unit| {
            if (!structural_units[unit]) {
                // Whole-module executable reuse stays disabled. An exact
                // declaration projection may retain only its principal proof.
                @memset(dirty[offsets[unit]..offsets[unit + 1]], true);
                var workspace = try projection.Workspace.init(allocator, pin.module);
                defer workspace.deinit();
                defer {
                    result.projection_scans += workspace.scans;
                    result.projection_visits += workspace.visits;
                    result.projection_workspace_peak_bytes = @max(result.projection_workspace_peak_bytes, workspace.capacityBytes());
                }
                for (module.bindings[1..], 1..) |binding, id| {
                    reached.clearRetainingCapacity();
                    const same = switch (binding.kind) {
                        .global => try workspace.definitionEqualWithOrigins(pin.module, &module, @intCast(id), &reached, constant_types, call_origins[offsets[unit]..offsets[unit + 1]]),
                        .external => id < pin.module.bindings.len and std.meta.eql(pin.module.bindings[id], binding),
                        .local, .parameter => false,
                    };
                    dirty[offsets[unit] + id] = !same;
                    if (same) for (reached.items) |closure| {
                        closure_owners[closure_offsets[unit] + closure] = @intCast(id);
                    };
                }
                continue;
            }
            for (module.nodes, pin.module.nodes, 0..) |node, before, id| {
                if (node.a == before.a) continue;
                const binding = scalarRoot(module, @intCast(id)) orelse return result;
                dirty[offsets[unit] + binding] = true;
            }
        }

        @memcpy(local_dirty, dirty);
        propagateReferences(&result, dirty);
        // Selection by type can reach an associated candidate through no
        // named reference: a body resolves a member name or operator against
        // the catalog of its operand's type. A dirty candidate therefore
        // dirties every declaration that resolves its key, and those
        // declarations' readers in turn.
        try dirtySelections(&result, allocator, dirty);
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
        return !self.local_dirty[self.offsets[unit] + target.binding];
    }

    /// The collector consumed only these checked facts. No body, value,
    /// executable fragment is admitted by this proof. Requirement producers
    /// have separate observations; their exact public headers must also pass.
    pub fn admitsCheckedInterface(self: *const Gate, target: core.BindingRef) bool {
        return self.checkedInterfaceEqual(target, true);
    }
    fn checkedInterfaceEqual(self: *const Gate, target: core.BindingRef, functions_only: bool) bool {
        if (self.constant_types or !self.admitsCallIdentity(target)) return false;
        const old = self.source_pools.?.modules[target.unit - 1].module;
        const current = &self.units[target.unit - 1];
        const before = old.body(target.binding).?;
        const after = current.body(target.binding).?;
        const left = old.binding(target.binding);
        const right = current.binding(target.binding);
        // The gate already proves the whole type/catalog graph. Compare the
        // fields used to instantiate headers, including the explicit-leaf bit
        // consulted before descending into a producer's requirements.
        if ((functions_only and (!before.is_function or !after.is_function)) or !equal(left.scheme, right.scheme) or
            left.has_explicit != right.has_explicit or before.parameters.len != after.parameters.len or
            !equal(old.types.list(left.public_variables), current.types.list(right.public_variables)) or
            !equal(old.types.list(left.public_rows), current.types.list(right.public_rows)) or
            !equal(old.types.list(before.closed_rows), current.types.list(after.closed_rows))) return false;
        if (!projection.parameterHeadersEqual(old, before.*, current, after.*)) return false;
        // Retained residual constraints may carry requirement diagnostics.
        // Unlike catalog equality, this proof keeps their locations exact.
        return equal(old.obligations[left.scheme.obligations.start..][0..left.scheme.obligations.len], current.obligations[right.scheme.obligations.start..][0..right.scheme.obligations.len]);
    }

    /// Inferred requirements additionally consume a lexical completeness proof.
    /// Equal headers alone cannot certify a different implementation. Rebuild
    /// that proof from current Core before accepting the old query's result.
    pub fn admitsCompletedInterface(self: *const Gate, target: core.BindingRef) Allocator.Error!bool {
        if (!self.checkedInterfaceEqual(target, false)) return false;
        const current = &self.units[target.unit - 1];
        const scheme = current.binding(target.binding).scheme;
        var needs_proof = !current.body(target.binding).?.is_function;
        for (current.obligations[scheme.obligations.start..][0..scheme.obligations.len]) |requirement| {
            needs_proof = needs_proof or !requirement.explicit;
        }
        if (needs_proof) {
            const owners = try self.allocator.alloc(*const core.Module, self.units.len);
            defer self.allocator.free(owners);
            for (owners, self.units) |*owner, *module| owner.* = module;
            var remaining: usize = 65_536;
            @import("../check/package_core.zig").checkedInterfaceBody(current, target.binding, .{ .units = owners }, &remaining, self.allocator) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
        }
        return true;
    }

    /// A closure root of a structural unit, or one reached by the exact
    /// projection of a declaration whose own source and identity are admitted.
    /// The same catalog index then names the same lexical closure.
    pub fn admitsClosure(self: *const Gate, unit: u32, catalog: u32) bool {
        if (!self.enabled or unit == 0 or unit > self.units.len or catalog >= self.units[unit - 1].closures.len) return false;
        if (self.structural_units[unit - 1]) return true;
        const owner = self.closure_owners[self.closure_offsets[unit - 1] + catalog];
        return owner != 0 and self.admitsLocalSource(.{ .unit = unit, .binding = owner });
    }

    /// Identity alone permits comparing a freshly established closed judgment.
    /// It never admits an old body, call proof, value or executable fragment.
    pub fn admitsCallIdentity(self: *const Gate, target: core.BindingRef) bool {
        return self.callIdentityFailure(target) == .none;
    }
    pub const IdentityFailure = enum { none, disabled, bounds, kind, binding_type, source_position, declaration_origin, body, scheme_root, scheme, flags };
    pub fn callIdentityFailure(self: *const Gate, target: core.BindingRef) IdentityFailure {
        if (!self.enabled) return .disabled;
        if (target.unit == 0 or target.unit > self.units.len or target.binding == 0) return .bounds;
        const current = &self.units[target.unit - 1];
        const old = self.source_pools.?.modules[target.unit - 1].module;
        if (target.binding >= current.bindings.len or target.binding >= old.bindings.len) return .bounds;
        const left = old.binding(target.binding);
        const right = current.binding(target.binding);
        if (left.kind != .global or right.kind != .global) return .kind;
        if (left.ty != right.ty) {
            if (!self.constant_types or !projection.equalConstantType(old.types, left.ty, current.types, right.ty)) return .binding_type;
        }
        const before = old.body(target.binding) orelse return .body;
        const after = current.body(target.binding) orelse return .body;
        // Named declarations need an unambiguous origin in this exact paired
        // unit and binding ordinal. Legacy synthetic Cores without owned names
        // retain the conservative source-position check. Neither path grants
        // body, capture, observation or executable validity.
        if (before.declaration_name.len != 0 or after.declaration_name.len != 0) {
            if (!self.call_origins[self.offsets[target.unit - 1] + target.binding]) return .declaration_origin;
        } else if (old.sourceNamePoint(target.binding) != current.sourceNamePoint(target.binding)) return .source_position;
        var scheme = before.scheme;
        if (scheme.root != after.scheme.root) {
            if (!self.constant_types or !projection.equalConstantType(old.types, scheme.root, current.types, after.scheme.root)) return .scheme_root;
            scheme.root = after.scheme.root;
        }
        if (before.runtime != after.runtime or before.is_function != after.is_function) return .flags;
        return if (equal(scheme, after.scheme)) .none else .scheme;
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
            self.allocator.free(self.certified_images);
            self.allocator.free(self.closure_owners);
            self.allocator.free(self.closure_offsets);
            self.allocator.free(self.offsets);
            self.allocator.free(self.dirty);
            self.allocator.free(self.local_dirty);
            self.allocator.free(self.call_origins);
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
        // Exactly proven unchanged units copy the old certificate's image
        // instead of re-serializing their whole graph.
        const previous = if (self.source_pools) |old| if (old.dependency_certificate) |*certificate| certificate else null else null;
        return try @import("dependency_certificate.zig").Certificate.captureReusing(a, .{ .units = units, .symbol_count = self.validation_symbols }, pins, self.validation_names orelse return null, previous, self.certified_images);
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

/// A fixed point also handles recursive source declarations. External
/// aliases are vertices: a read of either the alias or its producer is
/// invalidated by the same transitive source change.
fn propagateReferences(gate: *const Gate, dirty: []bool) void {
    var changed = true;
    while (changed) {
        changed = false;
        for (gate.units, 0..) |module, unit| {
            for (module.bindings[1..], 1..) |binding, id| {
                const index = gate.offsets[unit] + id;
                if (dirty[index]) continue;
                if (binding.kind == .external) {
                    if (gate.targetDirty(unit, binding.target)) {
                        dirty[index] = true;
                        changed = true;
                    }
                } else if (binding.kind == .global) {
                    const recipe = module.declaration_dependencies[binding.body_id];
                    for (module.dependency_references[recipe.references.start..][0..recipe.references.len]) |target| {
                        if (gate.targetDirty(unit, target)) {
                            dirty[index] = true;
                            changed = true;
                            break;
                        }
                    }
                }
            }
        }
    }
}

/// The catalog lookup rule of every type-directed selection: a member name
/// when the use has one, otherwise its operator.
fn selects(use: core.DependencyMember, candidate: core.Associated) bool {
    return if (use.name != 0) use.name == candidate.member else use.operator != .none and use.operator == candidate.operator;
}

/// Dirties every declaration whose body may select a dirty associated
/// candidate (declaration_dependencies.selectionMembers), then their readers,
/// until no further candidate becomes dirty. A body whose scan exceeds its
/// limit counts as selecting everything.
fn dirtySelections(gate: *const Gate, allocator: Allocator, dirty: []bool) Allocator.Error!void {
    var candidates: std.ArrayList(core.Associated) = .empty;
    defer candidates.deinit(allocator);
    var scanned: std.AutoHashMapUnmanaged(usize, []const core.DependencyMember) = .empty;
    defer {
        var uses = scanned.valueIterator();
        while (uses.next()) |value| allocator.free(value.*);
        scanned.deinit(allocator);
    }
    while (true) {
        const known = candidates.items.len;
        for (gate.units, 0..) |module, unit| for (module.associated) |candidate| {
            if (!gate.targetDirty(unit, candidate.target)) continue;
            for (candidates.items) |prior| {
                if (prior.member == candidate.member and prior.operator == candidate.operator) break;
            } else try candidates.append(allocator, candidate);
        };
        if (candidates.items.len == known) return;
        var changed = false;
        for (gate.units, 0..) |*module, unit| for (module.bindings[1..], 1..) |binding, id| {
            const index = gate.offsets[unit] + id;
            if (dirty[index] or binding.kind != .global) continue;
            const entry = try scanned.getOrPut(allocator, index);
            if (!entry.found_existing) {
                entry.value_ptr.* = dependencies.selectionMembers(allocator, module, module.bodies[binding.body_id]) catch |err| switch (err) {
                    error.OutOfMemory => {
                        scanned.removeByPtr(entry.key_ptr);
                        return error.OutOfMemory;
                    },
                    error.CoreLimit => {
                        scanned.removeByPtr(entry.key_ptr);
                        dirty[index] = true;
                        changed = true;
                        continue;
                    },
                };
            }
            const uses = entry.value_ptr.*;
            selected: for (uses) |use| for (candidates.items[0..]) |candidate| if (selects(use, candidate)) {
                dirty[index] = true;
                changed = true;
                break :selected;
            };
        };
        if (changed) propagateReferences(gate, dirty);
    }
}

/// A changed executable module cannot change global selection or semantic
/// identity. This initial projection keeps its complete type/obligation graph
/// and ordered catalogs exact. Body IDs and local executable tables may move;
/// executable reuse stays disabled. Individual principal proofs require a
/// separate exact declaration projection and transitive dependency validation.
/// A new Core field must explicitly choose one of these domains.
fn obligationsEqual(previous: []const core.Obligation, current: []const core.Obligation) bool {
    if (previous.len != current.len) return false;
    for (previous, current) |before, after| {
        var left = before;
        var right = after;
        left.span = .{ .start = 0, .end = 0 };
        right.span = left.span;
        left.qualification_span = if (left.qualification_span != null) left.span else null;
        right.qualification_span = if (right.qualification_span != null) right.span else null;
        if (!equal(left, right)) return false;
    }
    return true;
}
fn catalogEqual(previous: *const core.Module, current: *const core.Module, constant_types: bool) bool {
    const shared = @min(previous.bindings.len, current.bindings.len);
    for (previous.bindings[0..shared], current.bindings[0..shared]) |before, after| if (before.private != after.private) return false;
    for (previous.bindings[shared..]) |binding| if (binding.private) return false;
    for (current.bindings[shared..]) |binding| if (binding.private) return false;
    inline for (@typeInfo(core.Module).@"struct".field_names) |name| {
        const field = @field(ModuleField, name);
        switch (field) {
            // Operation values are an identity catalog: entries must be
            // identical. Their witness expressions are projected by every
            // referencing declaration's definition equality and dependency
            // walk, so a changed witness dirties exactly its consumers.
            .unit, .nominals, .constructors, .associated, .contracts, .contract_members, .implementations, .implementation_members, .member_templates, .selected_proofs, .selected_members, .selected_edges, .selected_uses, .dictionary_selections, .dictionary_uses, .operation_names, .names, .field_names, .operation_values, .capability_contracts, .proof_contracts, .has_rank_contracts, .has_numeric_proofs, .has_usage_contracts => {
                if (!equal(@field(previous, name), @field(current, name))) return false;
            },
            .types => {
                if (!equal(previous.types, current.types)) {
                    if (!constant_types or !duplicateTypeTail(previous.types, current.types)) return false;
                }
            },
            // Obligation spans locate diagnostics only. A shifted source
            // position keeps the catalog; declarations still compare spans.
            .obligations => if (!obligationsEqual(previous.obligations, current.obligations)) return false,
            .diagnostics => {
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
        if (node.tag != .effect_reflection or node.a != @backingInt(@import("../check/check.zig").ReflectionKind.of)) continue;
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
        .block, .suite, .product, .record, .array, .array_op, .storage => if (rangeHas(module.extra, core.List{ .start = value.a, .len = value.b }, id)) return null,
        .call, .break_ => if (rangeHas(module.extra, core.List{ .start = value.b, .len = value.c }, id)) return null,
        .pattern_bind => if (value.b == id or value.c == id) return null,
        .request_decision => if (value.b == id or value.c == id) return null,
        .effect_reflection => if (value.a >= @backingInt(@import("../check/check.zig").ReflectionKind.count) and (value.b == id or value.c == id)) return null,
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

// Every shared ID keeps exactly the same meaning. The only discarded entries
// are bounded duplicates of primitive/container nodes in that shared domain;
// variables, declarations and row identities cannot enter through this path.
fn duplicateTypeTail(left: core.Types, right: core.Types) bool {
    if (!equal(left.extra, right.extra) or !equal(left.effects, right.effects) or !equal(left.operations, right.operations)) return false;
    const shared = @min(left.nodes.len, right.nodes.len);
    if (!equal(left.nodes[0..shared], right.nodes[0..shared])) return false;
    const left_count = left.nodes.len - shared;
    const right_count = right.nodes.len - shared;
    if (left_count > 4096 or right_count > 4096 - left_count) return false;
    for ([_][]const T.Node{ left.nodes[shared..], right.nodes[shared..] }) |tail| {
        for (tail) |node| {
            switch (node.tag) {
                .unit, .boolean, .u32, .f32, .never => {},
                .array, .list, .cursor => {
                    if (node.a >= shared or node.b != 0 or node.c != 0) return false;
                    switch (left.nodes[node.a].tag) {
                        .unit, .boolean, .u32, .f32, .never => {},
                        else => return false,
                    }
                },
                else => return false,
            }
            var found = false;
            for (left.nodes[0..shared]) |existing| {
                if (std.meta.eql(existing, node)) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }
    }
    return true;
}

test "constant type tail proof rejects new shapes variables and malformed aliases" {
    const base = [_]T.Node{
        .{ .tag = .absent },
        .{ .tag = .u32 },
        .{ .tag = .array, .a = 1 },
    };
    const duplicate = base ++ [_]T.Node{base[2]};
    const distinct = base ++ [_]T.Node{.{ .tag = .list, .a = 1 }};
    const variable = base ++ [_]T.Node{.{ .tag = .variable, .a = 1 }};
    const malformed = base ++ [_]T.Node{.{ .tag = .array, .a = 99 }};
    const current: core.Types = .{ .nodes = @constCast(&base), .extra = &.{} };
    try std.testing.expect(duplicateTypeTail(.{ .nodes = @constCast(&duplicate), .extra = &.{} }, current));
    try std.testing.expect(!duplicateTypeTail(.{ .nodes = @constCast(&distinct), .extra = &.{} }, current));
    try std.testing.expect(!duplicateTypeTail(.{ .nodes = @constCast(&variable), .extra = &.{} }, current));
    try std.testing.expect(!duplicateTypeTail(.{ .nodes = @constCast(&malformed), .extra = &.{} }, current));
    try std.testing.expect(projection.equalConstantType(.{ .nodes = @constCast(&duplicate), .extra = &.{} }, 3, current, 2));
    try std.testing.expect(!projection.equalConstantType(.{ .nodes = @constCast(&distinct), .extra = &.{} }, 3, current, 2));
    try std.testing.expect(!projection.equalConstantType(.{ .nodes = @constCast(&malformed), .extra = &.{} }, 3, current, 2));
    try std.testing.expect(!projection.equalConstantType(current, 3, current, 3));
}
