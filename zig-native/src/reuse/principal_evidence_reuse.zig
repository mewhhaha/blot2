//! A separate principal prepass importer. Ordinary artifact admission remains
//! exact. Observed source and dynamic inputs admit only principal facts.
const std = @import("std");
const core = @import("../check/core.zig");
const core_eval = @import("../eval/core_eval.zig");
const semantic = @import("../eval/type_evidence.zig");
const types = @import("../check/types.zig");
const capture = @import("artifact_capture.zig");
const importer = @import("artifact_import.zig");
const identity = @import("../backend/runtime_identity.zig");
const gate = @import("principal_reuse_gate.zig");
const code_artifacts = @import("code_artifacts.zig");
const Allocator = std.mem.Allocator;

pub const SourceDecline = struct {
    target: core.BindingRef = .{ .unit = 0, .binding = 0 },
    source: core.BindingRef = .{ .unit = 0, .binding = 0 },
    reason: enum { none, disabled, constant_types, incomplete, identity, changed_source, module_image, missing_root } = .none,
    identity_failure: gate.Gate.IdentityFailure = .none,
    source_name_utf8: [96]u8 = @splat(0),
    source_name_truncated: bool = false,
    source_point: u32 = 0,
    interface_observation: bool = false,
    binding_requirements: u32 = 0,
    inferred_requirements: u32 = 0,
    callee_requirements: u32 = 0,
    body_requirements: u32 = 0,
    pub fn jsonStringify(self: *const SourceDecline, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.write(.{ .target = self.target, .source = self.source, .reason = self.reason, .identity_failure = self.identity_failure, .source_name = std.mem.sliceTo(&self.source_name_utf8, 0), .source_name_truncated = self.source_name_truncated, .source_point = self.source_point, .interface_observation = self.interface_observation, .binding_requirements = self.binding_requirements, .body_requirements = self.body_requirements, .inferred_requirements = self.inferred_requirements, .callee_requirements = self.callee_requirements });
    }
};
pub const Stats = struct {
    persisted_requests: usize = 0,
    persisted_hits: usize = 0,
    persisted_nonempty_hits: usize = 0,
    persisted_call_proofs: usize = 0,
    persisted_declines: usize = 0,
    projected_empty_hits: usize = 0,
    projected_nonempty_hits: usize = 0,
    projected_source_hits: usize = 0,
    projected_empty_declines: usize = 0,
    projected_owner_declines: usize = 0,
    projected_result_declines: usize = 0,
    projected_unrecorded_declines: usize = 0,
    projected_input_declines: usize = 0,
    projected_image_declines: usize = 0,
    projected_import_declines: usize = 0,
    input_image_checks: usize = 0,
    dependency_validations: usize = 0,
    reused_dependency_validations: usize = 0,
    projection_scans: usize = 0,
    projection_visits: usize = 0,
    projection_workspace_peak_bytes: usize = 0,
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
    call_publications_declined: usize = 0,
    summary_publications_replayed: usize = 0,
    summary_publications_declined: usize = 0,
    /// Bounded first failed source observation per principal lookup. These
    /// diagnostics never grant or revoke admission.
    source_declines: [8]SourceDecline = @splat(.{}),
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
        const result: State = .{ .allocator = allocator, .old = old, .gate = admission, .names = names, .stats = .{ .dependency_validations = admission.dependency_validations, .reused_dependency_validations = admission.reused_dependency_validations, .projection_scans = admission.projection_scans, .projection_visits = admission.projection_visits, .projection_workspace_peak_bytes = admission.projection_workspace_peak_bytes } };
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
        const current_view = generator.evaluator.storage.evidence.view();
        if (!canonicalPrefix(old_view) or !canonicalPrefix(current_view)) return .fallback;
        if (!sourceU32(previous) or !sourceU32(current)) return .fallback;
        for (type_maps) |mapping| if (mapping.evidence != types.u32_type) return .fallback;
        // Resolve the primitive through the CURRENT semantic owner. The old
        // mapping ordinal is never itself the translated result.
        const current_u32 = generator.evaluator.storage.evidence.intern(.u32, 0, 0, &.{}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else .fallback;
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
    /// A complete observation may survive changes outside the declarations it
    /// read. The gate still proves the entire ordered semantic catalog exact.
    fn sourceDeclined(self: *State, detail: SourceDecline) bool {
        for (&self.stats.source_declines) |*slot| {
            if (std.meta.eql(slot.target, detail.target)) return false;
            if (slot.reason == .none) {
                slot.* = detail;
                if (detail.reason == .identity) slot.identity_failure = self.gate.callIdentityFailure(detail.source);
                if (detail.source.unit != 0 and detail.source.unit <= self.gate.units.len) {
                    const module = &self.gate.units[detail.source.unit - 1];
                    if (detail.source.binding != 0 and detail.source.binding < module.bindings.len) {
                        slot.source_point = module.sourceNamePoint(detail.source.binding);
                        slot.binding_requirements = module.binding(detail.source.binding).scheme.obligations.len;
                        const requirements = module.binding(detail.source.binding).scheme.obligations;
                        for (module.obligations[requirements.start..][0..requirements.len]) |requirement| {
                            if (requirement.kind == .callee_use) slot.callee_requirements += 1 else if (!requirement.explicit) slot.inferred_requirements += 1;
                        }
                        if (module.body(detail.source.binding)) |body| {
                            slot.body_requirements = body.scheme.obligations.len;
                            if (@import("declaration_origins.zig").name(module, body.*)) |name| {
                                var len = @min(name.len, slot.source_name_utf8.len);
                                while (len != 0 and !std.unicode.utf8ValidateSlice(name[0..len])) len -= 1;
                                @memcpy(slot.source_name_utf8[0..len], name[0..len]);
                                slot.source_name_truncated = len != name.len;
                            }
                        }
                    }
                }
                break;
            }
        }
        return false;
    }
    fn sourcesEqual(self: *State, target: core.BindingRef, inputs: *const @import("principal_inputs.zig").Key) bool {
        if (!self.gate.enabled) return self.sourceDeclined(.{ .target = target, .reason = .disabled });
        if (self.gate.constant_types) return self.sourceDeclined(.{ .target = target, .reason = .constant_types });
        if (!inputs.source_complete) return self.sourceDeclined(.{ .target = target, .reason = .incomplete });
        for (inputs.source_units) |unit| {
            if (unit == 0 or unit > self.gate.units.len or !@import("principal_input_image.zig").moduleEqual(self.old.metadata.pools.?.modules[unit - 1].module, &self.gate.units[unit - 1])) return self.sourceDeclined(.{ .target = target, .source = .{ .unit = unit, .binding = 0 }, .reason = .module_image });
        }
        for (inputs.interfaces) |source| {
            if (!self.gate.admitsCheckedInterface(source)) return self.sourceDeclined(.{ .target = target, .source = source, .interface_observation = true, .reason = if (self.gate.admitsCallIdentity(source)) .changed_source else .identity });
        }
        var root = false;
        for (inputs.sources) |source| {
            if (!self.gate.admitsLocalSource(source)) return self.sourceDeclined(.{ .target = target, .source = source, .reason = if (self.gate.admitsCallIdentity(source)) .changed_source else .identity });
            root = root or std.meta.eql(source, target);
        }
        return root or self.sourceDeclined(.{ .target = target, .reason = .missing_root });
    }
    /// Retained evidence IDs belong to the old Snapshot. Re-intern every
    /// publication before publishing any of them or retaining the new key.
    fn currentInputs(self: *State, generator: anytype, target: core.BindingRef, inputs: *const @import("principal_inputs.zig").Key) Allocator.Error!?*const @import("principal_inputs.zig").Key {
        if (inputs.call_publications.len == 0 and inputs.call_reads.len == 0 and inputs.summary_reads.len == 0 and inputs.summary_publications.len == 0) return inputs;
        if ((!self.inputImageEqual() and !self.sourcesEqual(target, inputs)) or !try self.ensureGraphs()) return null;
        // This importer is private to principal type/row translation. The
        // gate proved every source type, nominal and effect ID equal. The
        // source observations separately prove the consumed bodies. It grants no
        // executable or value import; those use separate importers and gates.
        @memset(self.graphs.?.stable, true);
        var translated = try inputs.clone(self.allocator);
        var owned = true;
        defer if (owned) translated.deinit(self.allocator);
        for (translated.call_reads) |*read| {
            read.evidence = (try self.graphs.?.importPrincipalCall(generator, read.target, read.evidence)) orelse return null;
        }
        for (translated.summary_reads) |*read| {
            read.key.inputs = (try self.graphs.?.importPrincipalInput(generator, read.key.inputs)) orelse return null;
            read.result = (try self.graphs.?.importPrincipalCall(generator, read.key.target, read.result)) orelse return null;
        }
        if (!translated.matches(&generator.evaluator)) return null;
        // These are optional memo outputs of the completed query, not inputs
        // to its result. An untranslatable proof stays absent: its next use
        // performs ordinary checking. Never publish an old evidence ID.
        var kept: usize = 0;
        for (translated.call_publications) |call| {
            const actual = (try self.graphs.?.importPrincipalCall(generator, call.target, call.evidence)) orelse {
                self.stats.call_publications_declined += 1;
                continue;
            };
            translated.call_publications[kept] = .{ .target = call.target, .evidence = actual };
            kept += 1;
        }
        translated.call_publications = try self.allocator.realloc(translated.call_publications, kept);
        kept = 0;
        for (translated.summary_publications) |summary| {
            const actual_inputs = (try self.graphs.?.importPrincipalInput(generator, summary.key.inputs)) orelse {
                self.stats.summary_publications_declined += 1;
                continue;
            };
            const result = (try self.graphs.?.importPrincipalCall(generator, summary.key.target, summary.result)) orelse {
                self.stats.summary_publications_declined += 1;
                continue;
            };
            translated.summary_publications[kept] = .{ .key = .{ .target = summary.key.target, .inputs = actual_inputs, .deferred_member = summary.key.deferred_member }, .result = result };
            kept += 1;
        }
        translated.summary_publications = try self.allocator.realloc(translated.summary_publications, kept);
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
        const table = &self.old.metadata.principal_queries;
        var cursor = table.candidates(@import("principal_query.zig").fingerprint(target), .oldest_first);
        while (cursor.next()) |position| {
            const proof = &table.records.items[position];
            if (!std.meta.eql(proof.key.target, target)) continue;
            if (!std.meta.eql(proof.key.options, options)) {
                self.stats.options_declined += 1;
                return null;
            }
            const empty = proof.value.types.len == 0 and proof.value.rows.len == 0;
            if (!exact) {
                if (generator.evaluator.units.ptr != self.gate.units.ptr or generator.evaluator.units.len != self.gate.units.len) {
                    self.stats.projected_owner_declines += 1;
                    self.stats.projected_empty_declines += 1;
                    return null;
                }
                const inputs = if (proof.dependencies.inputs) |*inputs| inputs else {
                    self.stats.projected_unrecorded_declines += 1;
                    self.stats.projected_empty_declines += 1;
                    return null;
                };
                if (!inputs.matchesBase(&generator.evaluator)) {
                    self.stats.projected_input_declines += 1;
                    self.stats.projected_empty_declines += 1;
                    return null;
                }
                const complete_image = self.inputImageEqual();
                if (!complete_image and !self.sourcesEqual(target, inputs)) {
                    self.stats.projected_image_declines += 1;
                    self.stats.projected_empty_declines += 1;
                    return null;
                }
                const current_inputs = (try self.currentInputs(generator, target, inputs)) orelse {
                    self.stats.projected_import_declines += 1;
                    self.stats.projected_empty_declines += 1;
                    return null;
                };
                var solved: core_eval.SolvedEvidence = .{ .types = &.{}, .rows = &.{} };
                if (!empty) {
                    if (!try self.ensureGraphs()) {
                        self.stats.projected_result_declines += 1;
                        self.stats.projected_empty_declines += 1;
                        return null;
                    }
                    // The gate proves source type and row ordinals exact.
                    // The importer owns every translated result.
                    @memset(self.graphs.?.stable, true);
                    solved = (try self.graphs.?.importPrincipalEvidence(generator, target.unit, proof.value.types, proof.value.rows)) orelse {
                        self.stats.projected_result_declines += 1;
                        self.stats.projected_empty_declines += 1;
                        return null;
                    };
                }
                errdefer solved.deinit(self.allocator);
                try current_inputs.publish(&generator.evaluator);
                self.last_inputs = current_inputs;
                self.stats.call_publications_replayed += current_inputs.call_publications.len;
                self.stats.summary_publications_replayed += current_inputs.summary_publications.len;
                if (empty) self.stats.projected_empty_hits += 1 else self.stats.projected_nonempty_hits += 1;
                self.stats.projected_source_hits += @intFromBool(!complete_image);
                self.stats.hits += 1;
                self.stats.empty_hits += @intFromBool(empty);
                if (target.unit > self.old.cached_units) self.stats.fresh_unit_hits += 1;
                return solved;
            }
            if (!empty) self.stats.nonempty_requests += 1;
            const solved: core_eval.SolvedEvidence = if (empty)
                .{ .types = &.{}, .rows = &.{} }
            else blk: {
                switch (try self.primitiveEvidence(generator, target.unit, proof.value.types, proof.value.rows)) {
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
                break :blk (try self.graphs.?.importPrincipalEvidence(generator, target.unit, proof.value.types, proof.value.rows)) orelse {
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
            if (proof.dependencies.inputs) |*inputs| if (inputs.matchesBase(&generator.evaluator)) if (try self.currentInputs(generator, target, inputs)) |current_inputs| {
                try current_inputs.publish(&generator.evaluator);
                self.last_inputs = current_inputs;
                self.stats.call_publications_replayed += current_inputs.call_publications.len;
                self.stats.summary_publications_replayed += current_inputs.summary_publications.len;
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
