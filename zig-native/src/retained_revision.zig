//! Transactional revisions validate owned raw inputs before borrowing a seed.
//! Changed modules and their importers recheck; changed settings/closures rebuild.
//! Source checking,
//! entry validation, staging and startup are fresh roots on compiled revisions.
//! Private unchanged-input reuse validates the complete actual input snapshot
//! before returning independently owned output from a successful revision.
const std = @import("std");
const partial = @import("partial_dependency.zig");
const project = @import("project.zig");
const dependency_format = @import("dependency_format.zig");
const dependency = @import("frozen_dependency.zig");
const capture = @import("artifact_capture.zig");
const inputs = @import("revision_inputs.zig");
const closure = @import("dependency_closure.zig");
const retained_dependency = @import("retained_dependency.zig");
const checker = @import("project_check.zig");
const settings = @import("dependency_cli.zig").settings;
const Allocator = std.mem.Allocator;

const OutputPolicy = struct {
    capture_fresh_principals: bool,
    reuse_projected_principals: bool,
    reuse_declaration_principals: bool,
    reuse_unaffected_modules: bool,
    reuse_refinements: bool,
    reuse_solver_capacity: bool,
    optimize_completed_query_admission: bool,
    reuse_completed_specializations: bool,
    reuse_source_effect_queries: bool,
    reuse_query_graph_scratch: bool,
    share_query_gate: bool,
    reuse_fallback_check: bool,
    reuse_fallback_core: bool,
    reuse_module_frontends: bool,
    reuse_prepared_entry: bool,
    reuse_entry_interface_cutoff: bool,
    reuse_module_interface_cutoff: bool,
    share_dependency_storage: bool,
    reuse_dependency_validation: bool,
    reuse_rebuilt_queries: bool,
    prepare_checked_query_importer: bool,
    reuse_equivalent_validation: bool,
    transport_source_templates: bool,
    principal_reuse: bool,
    principal_graph_mode: @import("principal_evidence_reuse.zig").GraphMode,
};

/// Owned successful output; no frontend, caller Result or source-byte borrow.
const CachedOutput = struct {
    entry_request: []u8,
    output_identity: ?[]u8 = null,
    bytes: []u8 = &.{},
    source_bytes: usize,
    modules: usize,
    policy: OutputPolicy,
    fn init(a: Allocator, entry: []const u8, identity: ?[]const u8, result: *const partial.Result, modules: usize, policy: OutputPolicy) Allocator.Error!CachedOutput {
        var cached: CachedOutput = .{ .entry_request = try a.dupe(u8, entry), .source_bytes = result.source_bytes, .modules = modules, .policy = policy };
        errdefer cached.deinit(a);
        if (identity) |text| cached.output_identity = try a.dupe(u8, text);
        cached.bytes = try a.dupe(u8, result.result.compiled.bytes);
        return cached;
    }
    fn deinit(self: *CachedOutput, a: Allocator) void {
        a.free(self.entry_request);
        if (self.output_identity) |text| a.free(text);
        a.free(self.bytes);
    }
    fn matches(self: CachedOutput, entry: []const u8, identity: ?[]const u8, policy: OutputPolicy) bool {
        if (!std.mem.eql(u8, self.entry_request, entry) or !std.meta.eql(self.policy, policy)) return false;
        if (self.output_identity) |text| return if (identity) |other| std.mem.eql(u8, text, other) else false;
        return identity == null;
    }
    fn emission(self: CachedOutput, a: Allocator) Allocator.Error!partial.Result {
        // All counters describe work performed by this attempt. The prior
        // staging/evidence work is not reported as fresh native work.
        return .{ .result = .{ .compiled = .{ .bytes = try a.dupe(u8, self.bytes) }, .stats = .{ .syntax_nodes = 0, .body_elaborations = 0, .body_lowerings = 0, .imported_schemes = 0 } }, .source_bytes = self.source_bytes, .fresh_modules = 0, .cached_modules = self.modules };
    }
};

const Current = struct {
    prepared: partial.Prepared,
    artifacts: capture.Capture,
    snapshot: inputs.Snapshot,
    output: ?CachedOutput = null,
    fn deinit(self: *Current, a: Allocator) void {
        // Artifact producer pins are invalid once Prepared's fresh Core dies.
        self.artifacts.deinit();
        self.prepared.deinit(a);
        self.snapshot.deinit();
        if (self.output) |*output| output.deinit(a);
    }
};
pub const FallbackStats = struct {
    validated_modules: usize = 0,
    reused_frontend_modules: usize = 0,
    syntax_nodes: usize = 0,
    body_elaborations: usize = 0,
    body_lowerings: usize = 0,
    recheck_body_elaborations: usize = 0,
    reused_check_body_elaborations: usize = 0,
    frozen_modules: usize = 0,
    freeze_body_lowerings: usize = 0,
    reused_core_bodies: usize = 0,
    reused_entry_bodies: usize = 0,
    entry_cutoff: @import("entry_frontend_cutoff.zig").Stats = .{},
    module_cutoff: @import("entry_frontend_cutoff.zig").Stats = .{},
    dependency_storage: retained_dependency.Stats = .{},
};
pub const Stats = struct { rebuilt_seed: bool = false, reused_output: bool = false, inputs: inputs.Counts = .{}, fallback: FallbackStats = .{} };

// A live Candidate keeps this lease allocated even after Session teardown or
// reinitialization at the same address. It grants no semantic cache admission.
const Epoch = struct {
    allocator: Allocator,
    owner: ?*Session,
    references: usize = 1,
    preparing: bool = false,
    active: ?*Candidate = null,
    token: usize = 0,
    fn release(self: *Epoch) void {
        self.references -= 1;
        if (self.references == 0) self.allocator.destroy(self);
    }
};

/// A successful, fully emitted revision awaiting caller publication. Borrowed
/// seed/current owners remain alive until commit, discard or Session teardown.
/// A Candidate stays at its allocated address and is released with deinit.
pub const Candidate = struct {
    allocator: Allocator,
    epoch: *Epoch,
    token: usize,
    base_revision: usize,
    settings_key: [32]u8,
    stats: Stats,
    pending: ?Current,
    seed: ?retained_dependency.Seed,
    emission: ?partial.Result,
    kind: enum { compiled, unchanged } = .compiled,
    state: enum { prepared, committed, discarded } = .prepared,

    /// Read-only borrowed emission for fallible encoding before commit. Bytes,
    /// diagnostics and native-work metrics are independently owned: this view
    /// remains valid after commit/discard/Session teardown until takeResult or
    /// Candidate.deinit. It must not be deinitialized or retained beyond that.
    pub fn result(self: *const Candidate) ?*const partial.Result {
        if (self.emission) |*emission| return emission;
        return null;
    }
    /// Detached output may be taken only after the candidate has finished.
    /// It then belongs to the caller and uses this Candidate's allocator.
    pub fn takeResult(self: *Candidate) ?partial.Result {
        if (self.state == .prepared) return null;
        const result_ = self.emission orelse return null;
        self.emission = null;
        return result_;
    }
    fn discardPending(self: *Candidate) void {
        if (self.state != .prepared) return;
        // Captures/Prepared must die before a rebuilt seed they may borrow.
        if (self.pending) |*pending| pending.deinit(self.allocator);
        self.pending = null;
        if (self.seed) |*seed| seed.deinit(self.allocator);
        self.seed = null;
        if (self.epoch.active == self) self.epoch.active = null;
        self.state = .discarded;
    }
    /// Discard needs no Session dereference; late cleanup is safe after its
    /// teardown. The independent emission remains readable until deinit.
    pub fn discard(self: *Candidate) void {
        self.discardPending();
    }
    pub fn deinit(self: *Candidate) void {
        self.discardPending();
        if (self.emission) |*emission| emission.deinit(self.allocator);
        const epoch = self.epoch;
        self.allocator.destroy(self);
        epoch.release();
    }
};

/// Rejections own their diagnostic result, captured inputs and attempt counts.
/// They never reserve an active Candidate or change Session.last.
pub const Rejection = struct {
    result: partial.Result,
    snapshot: inputs.Snapshot,
    stats: Stats,
    pub fn deinit(self: *Rejection) void {
        self.result.deinit(self.snapshot.allocator);
        self.snapshot.deinit();
        self.* = undefined;
    }
    fn takeResult(self: *Rejection) partial.Result {
        const result_ = self.result;
        self.snapshot.deinit();
        self.* = undefined;
        return result_;
    }
};
pub const Preparation = union(enum) {
    ready: *Candidate,
    rejected: Rejection,
    pub fn deinit(self: *Preparation) void {
        switch (self.*) {
            .ready => |candidate| candidate.deinit(),
            .rejected => |*rejection| rejection.deinit(),
        }
        self.* = undefined;
    }
};

/// A Session may move while init returns it. Its first prepare binds the final
/// address; afterward the owner must remain there until deinit. Preparation is
/// serial and admits one live Candidate. Teardown discards pending compiler
/// owners before current/seed, while a late Candidate still owns its Result.
pub const Session = struct {
    allocator: Allocator,
    seed: dependency.FrozenDependency,
    seed_snapshot: ?*retained_dependency.Snapshot = null,
    seed_settings: [32]u8,
    current: ?Current = null,
    revisions: usize = 0,
    last: Stats = .{},
    // Bound lazily, after init's returned Session has reached its final address.
    epoch: ?*Epoch = null,
    /// Same-binary execution policies; none grants semantic cache admission.
    reuse_solver_capacity: bool = true,
    reuse_refinements: bool = false,
    /// Retain the principal prepasses already executed by a fresh backend.
    capture_fresh_principals: bool = false,
    reuse_projected_principals: bool = false,
    reuse_declaration_principals: bool = false,
    reuse_unaffected_modules: bool = false,
    optimize_completed_query_admission: bool = false,
    reuse_completed_specializations: bool = false,
    reuse_source_effect_queries: bool = false,
    reuse_query_graph_scratch: bool = false,
    share_query_gate: bool = false,
    reuse_fallback_check: bool = false,
    reuse_fallback_core: bool = false,
    /// Recheck changed modules and importers while retaining exact admitted siblings.
    reuse_module_frontends: bool = false,
    /// Keep the already checked/lowered entry across a mixed seed rebuild.
    reuse_prepared_entry: bool = false,
    reuse_entry_interface_cutoff: bool = false,
    reuse_module_interface_cutoff: bool = false,
    share_dependency_storage: bool = false,
    reuse_dependency_validation: bool = false,
    /// Offer retained inference receipts after rebuilding a dependency seed.
    /// Catalog, declaration and dynamic-read checks remain authoritative.
    reuse_rebuilt_queries: bool = false,
    prepare_checked_query_importer: bool = false,
    reuse_equivalent_validation: bool = false,
    transport_source_templates: bool = false,
    principal_reuse: bool = true,
    principal_graph_mode: @import("principal_evidence_reuse.zig").GraphMode = .primitive,
    /// Private exact-input output reuse. Production policy remains unchanged.
    reuse_unchanged_output: bool = false,

    fn outputPolicy(self: *const Session) OutputPolicy {
        return .{
            .capture_fresh_principals = self.capture_fresh_principals,
            .reuse_projected_principals = self.reuse_projected_principals,
            .reuse_declaration_principals = self.reuse_declaration_principals,
            .reuse_unaffected_modules = self.reuse_unaffected_modules,
            .reuse_solver_capacity = self.reuse_solver_capacity,
            .reuse_refinements = self.reuse_refinements,
            .optimize_completed_query_admission = self.optimize_completed_query_admission,
            .reuse_completed_specializations = self.reuse_completed_specializations,
            .reuse_source_effect_queries = self.reuse_source_effect_queries,
            .reuse_query_graph_scratch = self.reuse_query_graph_scratch,
            .share_query_gate = self.share_query_gate,
            .reuse_fallback_check = self.reuse_fallback_check,
            .reuse_fallback_core = self.reuse_fallback_core,
            .reuse_module_frontends = self.reuse_module_frontends,
            .reuse_prepared_entry = self.reuse_prepared_entry,
            .reuse_entry_interface_cutoff = self.reuse_entry_interface_cutoff,
            .reuse_module_interface_cutoff = self.reuse_module_interface_cutoff,
            .share_dependency_storage = self.share_dependency_storage,
            .reuse_dependency_validation = self.reuse_dependency_validation,
            .reuse_rebuilt_queries = self.reuse_rebuilt_queries,
            .prepare_checked_query_importer = self.prepare_checked_query_importer,
            .reuse_equivalent_validation = self.reuse_equivalent_validation,
            .transport_source_templates = self.transport_source_templates,
            .principal_reuse = self.principal_reuse,
            .principal_graph_mode = self.principal_graph_mode,
        };
    }

    /// Project-server execution policy, selected before the first preparation.
    /// Source/settings admission, fresh checking and transactional publication
    /// remain authoritative; these choices are not dependency artifact keys.
    pub fn enableProjectBuildReuse(self: *Session) void {
        std.debug.assert(self.epoch == null and self.current == null and self.revisions == 0);
        self.capture_fresh_principals = true;
        self.reuse_projected_principals = true;
        self.reuse_declaration_principals = true;
        self.reuse_unaffected_modules = true;
        self.reuse_refinements = true;
        self.optimize_completed_query_admission = true;
        self.reuse_completed_specializations = true;
        self.reuse_source_effect_queries = true;
        self.reuse_query_graph_scratch = true;
        self.share_query_gate = true;
        self.reuse_fallback_check = true;
        self.reuse_fallback_core = true;
        self.reuse_module_frontends = true;
        self.reuse_prepared_entry = true;
        self.reuse_entry_interface_cutoff = true;
        self.reuse_module_interface_cutoff = true;
        self.share_dependency_storage = true;
        self.reuse_dependency_validation = true;
        self.reuse_rebuilt_queries = true;
        self.prepare_checked_query_importer = true;
        self.reuse_equivalent_validation = true;
    }

    /// Moves an already wire/semantic/compiler-admitted seed and pins its exact
    /// source/check/backend settings. Compiler identity cannot change within
    /// this same-binary Session. Actual sources/imports are verified per revise.
    pub fn init(a: Allocator, seed: dependency.FrozenDependency, admitted_options: project.Options) Session {
        std.debug.assert(admitted_options.input_mode == .project);
        return .{ .allocator = a, .seed = seed, .seed_settings = settings(admitted_options) };
    }
    /// Internal source-only initial state. Imports/prelude still use the same
    /// checked closure fallback; no-import projects admit the empty prefix.
    pub fn initEmpty(a: Allocator, options: project.Options) Allocator.Error!Session {
        std.debug.assert(options.input_mode == .project);
        // The read-only loader requires the canonical absent dictionary entry,
        // even with no modules. Own its array; never free a static sentinel.
        const symbols = try a.alloc(dependency.Symbol, 1);
        symbols[0] = .{ .text = &.{} };
        return init(a, .{ .symbols = symbols, .modules = &.{} }, options);
    }
    pub fn deinit(self: *Session) void {
        if (self.epoch) |epoch| {
            std.debug.assert(epoch.owner == self and !epoch.preparing);
            if (epoch.active) |candidate| candidate.discardPending();
            epoch.owner = null;
        }
        if (self.current) |*current| current.deinit(self.allocator);
        self.releaseSeed();
        if (self.epoch) |epoch| epoch.release();
        self.* = undefined;
    }
    fn releaseSeed(self: *Session) void {
        if (self.seed_snapshot) |owner| owner.deinit() else dependency_format.deinit(self.allocator, &self.seed);
        self.seed_snapshot = null;
    }
    fn ensureSharedSeed(self: *Session) !void {
        if (!self.share_dependency_storage or self.seed_snapshot != null) return;
        // A decoded seed must establish complete validation before its result
        // can be retained. The cost belongs to this initial preparation.
        try closure.validate(self.allocator, &self.seed);
        const owner = try retained_dependency.Snapshot.adopt(self.allocator, self.seed);
        owner.validated = true;
        self.seed_snapshot = owner;
    }
    fn bind(self: *Session) !*Epoch {
        if (self.epoch) |epoch| {
            // Check address pairing before reading any borrowed seed/Core.
            if (epoch.owner != self) return error.SessionMoved;
            return epoch;
        }
        const epoch = try self.allocator.create(Epoch);
        epoch.* = .{ .allocator = self.allocator, .owner = self };
        self.epoch = epoch;
        return epoch;
    }
    fn paired(self: *const Session, candidate: *const Candidate) bool {
        if (candidate.state != .prepared) return false;
        const epoch = self.epoch orelse return false;
        return epoch.owner == self and candidate.epoch == epoch and epoch.active == candidate and candidate.token == epoch.token and candidate.base_revision == self.revisions and self.allocator.ptr == candidate.allocator.ptr and self.allocator.vtable == candidate.allocator.vtable;
    }
    /// Successful commit performs no allocation or I/O. Stale/wrong-owner
    /// candidates decline before touching retained semantic owners.
    pub fn commit(self: *Session, candidate: *Candidate) bool {
        if (!self.paired(candidate)) return false;
        const a = candidate.allocator;
        switch (candidate.kind) {
            .compiled => {
                if (self.current) |*current| current.deinit(a);
                if (candidate.seed) |seed| {
                    self.releaseSeed();
                    self.seed = seed.value;
                    self.seed_snapshot = seed.snapshot;
                    candidate.seed = null;
                }
                self.current = candidate.pending.?;
                candidate.pending = null;
            },
            .unchanged => {
                std.debug.assert(self.current != null and candidate.pending == null and candidate.seed == null);
            },
        }
        self.seed_settings = candidate.settings_key;
        self.last = candidate.stats;
        self.revisions += 1; // prepareRevision reserves this non-overflowing step.
        candidate.epoch.active = null;
        candidate.state = .committed;
        return true;
    }
    pub fn discard(self: *Session, candidate: *Candidate) bool {
        if (!self.paired(candidate)) return false;
        candidate.discardPending();
        return true;
    }
    fn entryOffer(self: *const Session) ?partial.EntryPrevious {
        if (!self.reuse_entry_interface_cutoff or !self.reuse_prepared_entry) return null;
        const previous = if (self.current) |*value| value else return null;
        const prepared = &previous.prepared;
        if (prepared.units.len == 0 or prepared.entry != prepared.units.len or prepared.units.len != self.seed.modules.len + 1 or prepared.cached != self.seed.modules.len or prepared.paths.len != prepared.units.len) return null;
        // The old entry proof and this dependency seed belong to one successful
        // publication. Check every borrowed prefix header before offering it.
        for (self.seed.modules, prepared.units[0..self.seed.modules.len]) |module, ir| {
            if (!std.meta.eql(module.core, ir)) return null;
        }
        return .{ .prepared = prepared, .source = previous.snapshot.capturedSource(prepared.paths[prepared.entry - 1]) orelse return null, .reuse_modules = self.reuse_module_interface_cutoff };
    }
    fn mixedFrontend(self: *Session, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, snapshot: *inputs.Snapshot, candidate_seed: *?retained_dependency.Seed, counts: *FallbackStats, reuse: []const bool) !?partial.Preparation {
        const a = self.allocator;
        var work: FallbackStats = .{};
        var kept: ?partial.Prepared = null;
        defer if (kept) |*prepared| prepared.deinit(a);
        var frozen = snapshot_block: {
            var source = try project.loadCompiledMixedReadOnly(a, io, entry_path, snapshot.options, &self.seed, snapshot.provider(), reuse);
            defer source.deinit(a);
            if (source.diagnostics.items.len != 0) return null;
            var checked: ?checker.CheckedProject = null;
            defer if (checked) |*owner| owner.deinit(a);
            var fresh = try partial.prepareProjectKeepingEntry(a, &source, entry_path, output_identity, &self.seed, &checked, self.entryOffer());
            var fresh_alive = true;
            defer if (fresh_alive) fresh.deinit(a);
            if (fresh == .rejected) return null;
            const saved: retained_dependency.Seed = if (self.share_dependency_storage) shared: {
                const owner = try closure.freezeSharedFromMixed(a, &source, &checked.?, &fresh.ready, self.seed_snapshot.?, self.reuse_dependency_validation, &work.dependency_storage);
                break :shared .{ .value = owner.value, .snapshot = owner };
            } else .{ .value = try closure.freezeFromMixedCheckedCore(a, &source, &checked.?, &fresh.ready) };
            work.validated_modules = source.order.items.len - checked.?.entry_cutoff.reused - checked.?.module_cutoff.reused;
            work.entry_cutoff = checked.?.entry_cutoff;
            work.module_cutoff = checked.?.module_cutoff;
            work.reused_frontend_modules = source.compiledCount() + checked.?.entry_cutoff.reused + checked.?.module_cutoff.reused;
            work.syntax_nodes = fresh.ready.stats.syntax_nodes;
            work.body_elaborations = fresh.ready.stats.body_elaborations;
            work.body_lowerings = fresh.ready.stats.body_lowerings;
            work.reused_check_body_elaborations = checked.?.body_elaborations;
            work.frozen_modules = saved.value.modules.len;
            for (saved.value.modules) |module| work.reused_core_bodies += module.core.body_lowerings;
            if (self.reuse_prepared_entry) {
                kept = fresh.ready;
                fresh_alive = false;
            }
            break :snapshot_block saved;
        };
        // The new seed owns or retains every immutable module independently.
        // Release temporary syntax/check/Core before preparing its consumer.
        var transferred = false;
        defer if (!transferred) frozen.deinit(a);
        if (kept) |*prepared| {
            try prepared.rebindFrozenPrefix(a, &frozen.value);
            work.reused_entry_bodies = prepared.units[prepared.entry - 1].body_lowerings;
            // FallbackStats already records all frontend work in this attempt.
            // No second consumer parse/check/lower was performed.
            prepared.stats = .{ .syntax_nodes = 0, .body_elaborations = 0, .body_lowerings = 0, .imported_schemes = 0 };
            const output: partial.Preparation = .{ .ready = prepared.* };
            kept = null;
            counts.* = work;
            candidate_seed.* = frozen;
            transferred = true;
            return output;
        }
        var output = try partial.prepareReadOnly(a, io, entry_path, output_identity, snapshot.options, &frozen.value, snapshot.provider());
        if (output == .rejected) {
            output.deinit(a);
            return null;
        }
        counts.* = work;
        candidate_seed.* = frozen;
        transferred = true;
        return output;
    }
    fn fallback(self: *Session, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, snapshot: *inputs.Snapshot, candidate_seed: *?retained_dependency.Seed, counts: *FallbackStats) !partial.Preparation {
        const a = self.allocator;
        if (self.reuse_module_frontends and std.mem.eql(u8, &self.seed_settings, &settings(snapshot.options))) {
            if (try snapshot.reusableModules(io, &self.seed)) |reuse| {
                defer a.free(reuse);
                const mixed = self.mixedFrontend(io, entry_path, output_identity, snapshot, candidate_seed, counts, reuse) catch |err| blk: {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    break :blk null;
                };
                if (mixed) |prepared| return prepared;
            }
        }
        var source = try project.loadWithInputs(a, io, entry_path, snapshot.options, snapshot.provider());
        defer source.deinit(a);
        // Both lanes retain the ordinary source/check/lower validation order.
        // The private sharing lane keeps only that successful check, for this
        // exact captured Project, until closure freeze. No failure is cached.
        var kept_check: ?checker.CheckedProject = null;
        defer if (kept_check) |*checked| checked.deinit(a);
        const empty: dependency.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
        var fresh = if (self.reuse_fallback_check)
            try partial.prepareProjectKeepingCheck(a, &source, entry_path, output_identity, &empty, &kept_check)
        else
            try partial.prepareProject(a, &source, entry_path, output_identity, &empty);
        const reuse_core = self.reuse_fallback_check and self.reuse_fallback_core;
        var fresh_alive = false;
        defer if (fresh_alive) fresh.deinit(a);
        switch (fresh) {
            .rejected => return fresh,
            .ready => |*prepared| {
                counts.validated_modules = prepared.units.len;
                counts.syntax_nodes = prepared.stats.syntax_nodes;
                counts.body_elaborations = prepared.stats.body_elaborations;
                counts.body_lowerings = prepared.stats.body_lowerings;
                if (reuse_core) fresh_alive = true else prepared.deinit(a);
            },
        }
        if (kept_check == null) {
            kept_check = try checker.checkProject(a, &source);
            counts.recheck_body_elaborations = kept_check.?.body_elaborations;
        } else counts.reused_check_body_elaborations = kept_check.?.body_elaborations;
        const frozen = if (reuse_core)
            try closure.freezeFromCheckedCore(a, &source, &kept_check.?, &fresh.ready)
        else
            try closure.freeze(a, &source, &kept_check.?);
        if (fresh_alive) {
            fresh.deinit(a);
            fresh_alive = false;
        }
        candidate_seed.* = .{ .value = frozen };
        if (self.share_dependency_storage) {
            const owner = try retained_dependency.Snapshot.adopt(a, frozen);
            owner.validated = true;
            candidate_seed.*.?.snapshot = owner;
            counts.dependency_storage = .{ .fresh_modules = frozen.modules.len, .core_checked = frozen.modules.len, .interface_checked = frozen.modules.len };
        }
        counts.frozen_modules = frozen.modules.len;
        for (frozen.modules) |module| {
            if (reuse_core) counts.reused_core_bodies += module.core.body_lowerings else counts.freeze_body_lowerings += module.core.body_lowerings;
        }
        return partial.prepareReadOnly(a, io, entry_path, output_identity, snapshot.options, &candidate_seed.*.?.value, snapshot.provider());
    }
    pub fn prepareRevision(self: *Session, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, options: project.Options) !Preparation {
        return self.prepareRevisionWithSources(io, entry_path, output_identity, options, &.{});
    }
    pub fn prepareRevisionWithSources(self: *Session, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, options: project.Options, sources: []const inputs.overlays.Source) !Preparation {
        if (options.input_mode != .project) return error.InputModeUnsupported;
        const epoch = try self.bind();
        if (epoch.preparing or epoch.active != null) return error.CandidateActive;
        if (self.revisions == std.math.maxInt(usize) or epoch.token == std.math.maxInt(usize) or epoch.references == std.math.maxInt(usize)) return error.RevisionLimit;
        epoch.preparing = true;
        defer epoch.preparing = false;
        const a = self.allocator;
        try self.ensureSharedSeed();
        var snapshot = try inputs.Snapshot.initWithSources(a, io, options, sources);
        var snapshot_alive = true;
        defer if (snapshot_alive) snapshot.deinit();
        var candidate_seed: ?retained_dependency.Seed = null;
        defer if (candidate_seed) |*seed| seed.deinit(a);
        const settings_key = settings(snapshot.options);
        const admitted = std.mem.eql(u8, &self.seed_settings, &settings_key) and try snapshot.admits(io, &self.seed);
        if (admitted and self.reuse_unchanged_output) if (self.current) |*current| if (current.output) |output| {
            if (output.matches(entry_path, output_identity, self.outputPolicy()) and try snapshot.entryEqualsPrevious(io, entry_path, current.prepared.paths[current.prepared.entry - 1], &current.snapshot) and try snapshot.equalsPrevious(io, &current.snapshot)) {
                var emission = try output.emission(a);
                errdefer emission.deinit(a);
                const candidate = try a.create(Candidate);
                candidate.* = .{ .allocator = a, .epoch = epoch, .token = epoch.token + 1, .base_revision = self.revisions, .settings_key = settings_key, .stats = .{ .reused_output = true, .inputs = snapshot.counts }, .pending = null, .seed = null, .emission = emission, .kind = .unchanged };
                epoch.token = candidate.token;
                epoch.references += 1;
                epoch.active = candidate;
                return .{ .ready = candidate };
            }
        };
        var fallback_counts: FallbackStats = .{};
        var preparation: partial.Preparation = undefined;
        if (admitted) {
            var fast_result = true;
            preparation = partial.prepareReadOnly(a, io, entry_path, output_identity, snapshot.options, &self.seed, snapshot.provider()) catch |err| switch (err) {
                error.DependencySetChanged => blk: {
                    fast_result = false;
                    break :blk try self.fallback(io, entry_path, output_identity, &snapshot, &candidate_seed, &fallback_counts);
                },
                else => return err,
            };
            if (fast_result) switch (preparation) {
                .rejected => |*result| {
                    // An entry may remove old producers before a load/parse
                    // error. Fresh graph limits and diagnostic ordering then
                    // differ from a compiled prefix; establish the fresh result.
                    result.deinit(a);
                    preparation = try self.fallback(io, entry_path, output_identity, &snapshot, &candidate_seed, &fallback_counts);
                },
                .ready => {},
            };
        } else preparation = try self.fallback(io, entry_path, output_identity, &snapshot, &candidate_seed, &fallback_counts);
        var preparation_alive = true;
        defer if (preparation_alive) preparation.deinit(a);
        switch (preparation) {
            .rejected => |result| {
                preparation_alive = false;
                snapshot_alive = false;
                return .{ .rejected = .{ .result = result, .snapshot = snapshot, .stats = .{ .rebuilt_seed = candidate_seed != null, .inputs = snapshot.counts, .fallback = fallback_counts } } };
            },
            .ready => |*prepared| {
                const rebuilt = candidate_seed != null;
                // Rebuilt seeds still generate executable bodies freshly.
                // Inference receipts have their own exact catalog, source and
                // dynamic-input admission, independent of the seed owner.
                const prior_compatible = !rebuilt;
                const queries_compatible = prior_compatible or (self.reuse_rebuilt_queries and std.mem.eql(u8, &self.seed_settings, &settings(snapshot.options)));
                var result = try prepared.emitWithOptions(a, .{
                    .reuse_projected_principals = self.reuse_projected_principals,
                    .reuse_declaration_principals = self.reuse_declaration_principals,
                    .reuse_unaffected_modules = self.reuse_unaffected_modules,
                    .reuse_solver_capacity = self.reuse_solver_capacity,
                    .reuse_refinements = self.reuse_refinements,
                    .retain_artifacts = true,
                    .previous = if (prior_compatible and self.current != null) &self.current.?.artifacts else null,
                    .query_previous = if (queries_compatible and self.current != null) &self.current.?.artifacts else null,
                    .principal_previous = if (rebuilt and self.reuse_projected_principals and self.current != null) &self.current.?.artifacts else null,
                    .cached_units = prepared.cached,
                    .reuse_completed_specializations = self.reuse_completed_specializations,
                    .reuse_source_effect_queries = self.reuse_source_effect_queries,
                    .reuse_query_graph_scratch = self.reuse_query_graph_scratch,
                    .share_query_gate = self.share_query_gate,
                    .prepare_checked_query_importer = self.prepare_checked_query_importer,
                    .reuse_equivalent_validation = self.reuse_equivalent_validation,
                    .optimize_completed_query_admission = self.optimize_completed_query_admission,
                    .transport_source_templates = self.transport_source_templates,
                    .principal_reuse = self.principal_reuse and (prior_compatible or self.capture_fresh_principals),
                    .principal_graph_mode = self.principal_graph_mode,
                });
                errdefer result.deinit(a);
                if (result.result.compiled.diagnostic != null) {
                    snapshot_alive = false;
                    return .{ .rejected = .{ .result = result, .snapshot = snapshot, .stats = .{ .rebuilt_seed = rebuilt, .inputs = snapshot.counts, .fallback = fallback_counts } } };
                }
                var artifacts = result.result.compiled.capture orelse return error.MissingOwnedArtifacts;
                result.result.compiled.capture = null;
                errdefer artifacts.deinit();
                var cached_output: ?CachedOutput = if (self.reuse_unchanged_output) try CachedOutput.init(a, entry_path, output_identity, &result, prepared.units.len, self.outputPolicy()) else null;
                errdefer if (cached_output) |*output| output.deinit(a);
                const candidate = try a.create(Candidate);
                candidate.* = .{
                    .allocator = a,
                    .epoch = epoch,
                    .token = epoch.token + 1,
                    .base_revision = self.revisions,
                    .settings_key = settings_key,
                    .stats = .{ .rebuilt_seed = rebuilt, .inputs = snapshot.counts, .fallback = fallback_counts },
                    .pending = .{ .prepared = prepared.*, .artifacts = artifacts, .snapshot = snapshot, .output = cached_output },
                    .seed = candidate_seed,
                    .emission = result,
                };
                epoch.token = candidate.token;
                epoch.references += 1;
                epoch.active = candidate;
                candidate_seed = null;
                snapshot_alive = false;
                preparation_alive = false;
                return .{ .ready = candidate };
            },
        }
    }
    /// Existing synchronous behavior: all fallible compilation happens during
    /// preparation; commit and result detachment cannot allocate or fail.
    pub fn revise(self: *Session, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, options: project.Options) !partial.Result {
        var preparation = try self.prepareRevision(io, entry_path, output_identity, options);
        switch (preparation) {
            .rejected => |*rejection| return rejection.takeResult(),
            .ready => |candidate| {
                defer candidate.deinit();
                const committed = self.commit(candidate);
                std.debug.assert(committed);
                return candidate.takeResult().?;
            },
        }
    }
};
