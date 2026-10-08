//! A separate principal prepass importer. Ordinary artifact admission remains
//! exact. Changed declarations never borrow old principal facts or values.
const std = @import("std");
const core = @import("core.zig");
const core_eval = @import("core_eval.zig");
const semantic = @import("type_evidence.zig");
const types = @import("types.zig");
const capture = @import("artifact_capture.zig");
const importer = @import("artifact_import.zig");
const identity = @import("runtime_identity.zig");
const gate = @import("principal_reuse_gate.zig");
const code_artifacts = @import("code_artifacts.zig");
const Allocator = std.mem.Allocator;

pub const Stats = struct {
    persisted_requests: usize = 0,
    persisted_hits: usize = 0,
    persisted_nonempty_hits: usize = 0,
    persisted_call_proofs: usize = 0,
    persisted_declines: usize = 0,
    projected_empty_hits: usize = 0,
    projected_empty_declines: usize = 0,
    input_image_checks: usize = 0,
    dependency_validations: usize = 0,
    reused_dependency_validations: usize = 0,
    graph_importers_initialized: usize = 0,
    graph_importers_prepared: usize = 0,
    empty_hits: usize = 0,
    primitive_hits: usize = 0,
    primitive_fallbacks: usize = 0,
    primitive_key_declined: usize = 0,
    nonempty_requests: usize = 0,
    requests: usize = 0,
    fresh_unit_requests: usize = 0,
    fresh_unit_hits: usize = 0,
    hits: usize = 0,
    changed_or_unsupported: usize = 0,
    missing: usize = 0,
    evidence_declined: usize = 0,
    options_declined: usize = 0,
    captured: usize = 0,
    fresh_regions: usize = 0,
    call_publications_replayed: usize = 0,
};
pub const State = struct {
    allocator: Allocator,
    old: *const capture.Capture,
    gate: gate.Gate,
    /// Borrowed current identity stays alive through this compile, like Core.
    names: ?identity.View,
    graphs: ?importer.Importer = null,
    input_image_equal: ?bool = null,
    last_inputs: ?*const @import("principal_inputs.zig").Key = null,
    imported_inputs: ?@import("principal_inputs.zig").Key = null,
    stats: Stats = .{},

    /// Old Core and Pools stay immutable/alive through this candidate. Only
    /// this distinct importer's stability flags receive the checked namespace
    /// gate; retained code fragments keep their existing exact Core gate.
    pub fn init(allocator: Allocator, old: *const capture.Capture, units: []const core.Module, names: ?identity.View, stamps: ?*code_artifacts.ModuleStamps) Allocator.Error!State {
        var admission = try gate.Gate.initWithStamps(allocator, &old.metadata.pools.?, units, names, stamps);
        errdefer admission.deinit();
        const result: State = .{ .allocator = allocator, .old = old, .gate = admission, .names = names, .stats = .{ .dependency_validations = admission.dependency_validations, .reused_dependency_validations = admission.reused_dependency_validations } };
        return result;
    }
    /// Reuse this query's already validated namespace and catalog. No importer
    /// owner is published until every allocation and stability update succeeds.
    fn ensureGraphs(self: *State) Allocator.Error!bool {
        if (self.graphs) |*graphs| return graphs.enabled;
        if (!self.gate.enabled) return false;
        const prepared = try importer.Importer.initCheckedQuery(self.allocator, &self.old.metadata.pools.?, self.gate.units, &self.gate);
        var graphs = prepared orelse try importer.Importer.init(self.allocator, &self.old.metadata.pools.?, self.gate.units, self.names, self.gate.units.len);
        if (!graphs.enabled) {
            graphs.deinit();
            return false;
        }
        for (graphs.stable, self.gate.structural_units) |*stable, structural| stable.* = structural;
        self.graphs = graphs;
        self.stats.graph_importers_initialized += 1;
        self.stats.graph_importers_prepared += @intFromBool(prepared != null);
        return true;
    }
    const PrimitiveResult = union(enum) { fallback, declined, solved: core_eval.SolvedEvidence };

    /// Only admitted owner-qualified source variables and the canonical U32
    /// leaf cross this boundary. No foreign semantic graph or value is owned.
    fn primitiveEvidence(self: *const State, generator: anytype, owner: u32, type_maps: []const semantic.Mapping, row_maps: []const semantic.RowMapping) Allocator.Error!PrimitiveResult {
        if (row_maps.len != 0 or type_maps.len == 0) return .fallback;
        // Gate admission established the exact ordered producer namespace.
        // Keep bounds explicit here before dereferencing either source owner.
        if (generator.evaluator.units.len != self.gate.units.len or generator.evaluator.units.ptr != self.gate.units.ptr) return .declined;
        const pools = &self.old.metadata.pools.?;
        if (owner == 0 or owner > pools.modules.len or owner > self.gate.units.len) return .declined;
        const pin = pools.modules[owner - 1];
        if (pin.unit != owner or !self.gate.structural_units[owner - 1]) return .declined;
        const previous = pin.module;
        const current = &self.gate.units[owner - 1];
        for (type_maps, 0..) |mapping, i| {
            if (mapping.variable == 0 or mapping.variable >= previous.types.nodes.len or mapping.variable >= current.types.nodes.len) return .declined;
            if (previous.types.nodes[mapping.variable].tag != .variable or current.types.nodes[mapping.variable].tag != .variable) return .declined;
            if (!std.meta.eql(previous.types.nodes[mapping.variable], current.types.nodes[mapping.variable])) return .declined;
            for (type_maps[0..i]) |prior| if (prior.variable == mapping.variable) return .declined;
        }
        const old_view = pools.evaluator.evidence.view();
        const current_view = generator.evaluator.evidence.view();
        if (!canonicalPrefix(old_view) or !canonicalPrefix(current_view)) return .fallback;
        if (!sourceU32(previous) or !sourceU32(current)) return .fallback;
        for (type_maps) |mapping| if (mapping.evidence != types.u32_type) return .fallback;
        // Resolve the primitive through the CURRENT semantic owner. The old
        // mapping ordinal is never itself the translated result.
        const current_u32 = generator.evaluator.evidence.intern(.u32, 0, 0, &.{}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else .fallback;
        if (current_u32 >= current_view.nodes.len or !std.meta.eql(current_view.nodes[current_u32], semantic.Node{ .tag = .u32 })) return .fallback;
        const copied = try self.allocator.alloc(semantic.Mapping, type_maps.len);
        for (type_maps, copied) |from, *to| to.* = .{ .variable = from.variable, .evidence = current_u32 };
        return .{ .solved = .{ .types = copied, .rows = &.{} } };
    }

    fn canonicalPrefix(view: semantic.View) bool {
        const tags = [_]semantic.Tag{ .absent, .unit, .boolean, .u32, .f32, .never };
        if (view.nodes.len < tags.len or view.effects.rows.len == 0) return false;
        if (view.effects.rows[0].start != 0 or view.effects.rows[0].len != 0) return false;
        for (view.nodes[0..tags.len], tags) |node, tag| if (!std.meta.eql(node, semantic.Node{ .tag = tag })) return false;
        return true;
    }
    fn sourceU32(module: *const core.Module) bool {
        if (module.types.nodes.len <= types.u32_type) return false;
        const node = module.types.nodes[types.u32_type];
        return node.tag == .u32 and node.a == 0 and node.b == 0 and node.c == 0;
    }
    pub fn deinit(self: *State) void {
        if (self.imported_inputs) |*inputs| inputs.deinit(self.allocator);
        if (self.graphs) |*graphs| graphs.deinit();
        self.gate.deinit();
        self.* = undefined;
    }
    fn inputImageEqual(self: *State) bool {
        if (self.input_image_equal) |known| return known;
        self.stats.input_image_checks += 1;
        for (self.gate.units, self.old.metadata.pools.?.modules) |*current, previous| {
            if (!@import("principal_input_image.zig").moduleEqual(previous.module, current)) {
                self.input_image_equal = false;
                return false;
            }
        }
        self.input_image_equal = true;
        return true;
    }
    /// Retained evidence IDs belong to the old Snapshot. Re-intern every
    /// publication before publishing any of them or retaining the new key.
    fn currentInputs(self: *State, generator: anytype, inputs: *const @import("principal_inputs.zig").Key) Allocator.Error!?*const @import("principal_inputs.zig").Key {
        if (inputs.call_publications.len == 0) return inputs;
        if (!self.inputImageEqual() or !try self.ensureGraphs()) return null;
        // This importer is private to principal type/row translation. The
        // complete input projection proved every source type, nominal, effect
        // and local ID equal, even when a nested literal changed. It grants no
        // executable or value import; those use separate importers and gates.
        @memset(self.graphs.?.stable, true);
        var translated = try inputs.clone(self.allocator);
        var owned = true;
        defer if (owned) translated.deinit(self.allocator);
        for (translated.call_publications) |*call|
            call.evidence = (try self.graphs.?.importPrincipalCall(generator, call.target, call.evidence)) orelse return null;
        self.imported_inputs = translated;
        owned = false;
        return &self.imported_inputs.?;
    }
    pub fn lookup(self: *State, generator: anytype, target: core.BindingRef, options: core_eval.Options) Allocator.Error!?core_eval.SolvedEvidence {
        self.last_inputs = null;
        if (self.imported_inputs) |*inputs| inputs.deinit(self.allocator);
        self.imported_inputs = null;
        self.stats.requests += 1;
        if (target.unit == 0 or target.unit > self.gate.units.len or target.binding == 0 or target.binding >= self.gate.units[target.unit - 1].bindings.len) {
            self.stats.changed_or_unsupported += 1;
            return null;
        }
        if (target.unit > self.old.cached_units) self.stats.fresh_unit_requests += 1;
        const exact = self.gate.admitsPrincipal(target);
        if (!exact and !self.gate.enabled) {
            self.stats.changed_or_unsupported += 1;
            return null;
        }
        // last_inputs is consumed by the provider's record callback after
        // lookup returns. Borrow the owned proof, never a loop-local copy.
        for (self.old.metadata.principal_proofs.items) |*proof| {
            if (!std.meta.eql(proof.target, target)) continue;
            if (!std.meta.eql(proof.options, options)) {
                self.stats.options_declined += 1;
                return null;
            }
            const empty = proof.types.len == 0 and proof.rows.len == 0;
            if (!exact) {
                if (generator.evaluator.units.ptr != self.gate.units.ptr or generator.evaluator.units.len != self.gate.units.len) {
                    self.stats.projected_empty_declines += 1;
                    return null;
                }
                if (empty) if (proof.inputs) |*inputs| if (inputs.matches(&generator.evaluator) and self.inputImageEqual()) {
                    const current_inputs = (try self.currentInputs(generator, inputs)) orelse {
                        self.stats.projected_empty_declines += 1;
                        return null;
                    };
                    try current_inputs.publish(&generator.evaluator);
                    self.last_inputs = current_inputs;
                    self.stats.call_publications_replayed += current_inputs.call_publications.len;
                    self.stats.projected_empty_hits += 1;
                    self.stats.hits += 1;
                    self.stats.empty_hits += 1;
                    if (target.unit > self.old.cached_units) self.stats.fresh_unit_hits += 1;
                    return .{ .types = &.{}, .rows = &.{} };
                };
                self.stats.projected_empty_declines += 1;
                return null;
            }
            if (!empty) self.stats.nonempty_requests += 1;
            const solved: core_eval.SolvedEvidence = if (empty)
                .{ .types = &.{}, .rows = &.{} }
            else blk: {
                switch (try self.primitiveEvidence(generator, target.unit, proof.types, proof.rows)) {
                    .solved => |facts| {
                        self.stats.primitive_hits += 1;
                        break :blk facts;
                    },
                    .declined => {
                        self.stats.primitive_key_declined += 1;
                        self.stats.evidence_declined += 1;
                        return null;
                    },
                    .fallback => self.stats.primitive_fallbacks += 1,
                }
                if (!try self.ensureGraphs()) {
                    self.stats.evidence_declined += 1;
                    return null;
                }
                break :blk (try self.graphs.?.importPrincipalEvidence(generator, target.unit, proof.types, proof.rows)) orelse {
                    self.stats.evidence_declined += 1;
                    return null;
                };
            };
            // An exact-source result can still be reused without its projected
            // key. Carry that key forward only when its dynamic reads match,
            // and replay the memo publications the skipped region would make.
            errdefer {
                var owned = solved;
                owned.deinit(self.allocator);
            }
            if (proof.inputs) |*inputs| if (inputs.matches(&generator.evaluator)) if (try self.currentInputs(generator, inputs)) |current_inputs| {
                try current_inputs.publish(&generator.evaluator);
                self.last_inputs = current_inputs;
                self.stats.call_publications_replayed += current_inputs.call_publications.len;
            };
            if (empty) self.stats.empty_hits += 1;
            self.stats.hits += 1;
            if (target.unit > self.old.cached_units) self.stats.fresh_unit_hits += 1;
            return solved;
        }
        self.stats.missing += 1;
        return null;
    }
};
