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
const phase_profile = @import("../phase_profile.zig");
const Allocator = std.mem.Allocator;

const Policy = @import("../execution_policy.zig").Policy;
const OutputPolicy = Policy;

/// Owned successful output; no frontend, caller Result or source-byte borrow.
const CachedOutput = struct {
    entry_request: []u8,
    output_identity: ?[]u8 = null,
    bytes: []u8 = &.{},
    demand_lowering: ?@import("../backend/demand_lowering.zig").Snapshot = null,
    source_bytes: usize,
    modules: usize,
    policy: OutputPolicy,
    fn init(a: Allocator, entry: []const u8, identity: ?[]const u8, result: *const partial.Result, modules: usize, policy: OutputPolicy) Allocator.Error!CachedOutput {
        var cached: CachedOutput = .{ .entry_request = try a.dupe(u8, entry), .source_bytes = result.source_bytes, .modules = modules, .policy = policy };
        errdefer cached.deinit(a);
        if (identity) |text| cached.output_identity = try a.dupe(u8, text);
        cached.bytes = try a.dupe(u8, result.result.compiled.bytes);
        if (result.result.compiled.demand_lowering) |report| {
            const copied = try report.clone(a);
            cached.demand_lowering = copied;
        }
        return cached;
    }
    fn deinit(self: *CachedOutput, a: Allocator) void {
        a.free(self.entry_request);
        if (self.output_identity) |text| a.free(text);
        a.free(self.bytes);
        if (self.demand_lowering) |*report| report.deinit(a);
    }
    fn matches(self: CachedOutput, entry: []const u8, identity: ?[]const u8, policy: OutputPolicy, explain_demands: bool) bool {
        if ((self.demand_lowering != null) != explain_demands) return false;
        if (!std.mem.eql(u8, self.entry_request, entry) or !std.meta.eql(self.policy, policy)) return false;
        if (self.output_identity) |text| return if (identity) |other| std.mem.eql(u8, text, other) else false;
        return identity == null;
    }
    fn emission(self: CachedOutput, a: Allocator) Allocator.Error!partial.Result {
        // All counters describe work performed by this attempt. The prior
        // staging/evidence work is not reported as fresh native work.
        var result: partial.Result = .{ .result = .{ .compiled = .{ .bytes = try a.dupe(u8, self.bytes) }, .stats = .{ .syntax_nodes = 0, .body_elaborations = 0, .body_lowerings = 0, .imported_schemes = 0 } }, .source_bytes = self.source_bytes, .fresh_modules = 0, .cached_modules = self.modules };
        errdefer result.deinit(a);
        if (self.demand_lowering) |report| {
            const copied = try report.clone(a);
            result.result.compiled.demand_lowering = copied;
        }
        return result;
    }
};

test "unchanged output owns demand explanations through result teardown and allocation failures" {
    const Law = struct {
        fn run(a: Allocator) !void {
            const Site = @import("../backend/demand_lowering.zig").Site;
            var original: partial.Result = .{ .result = .{ .compiled = .{ .bytes = try a.dupe(u8, "wasm") }, .stats = .{ .syntax_nodes = 0, .body_elaborations = 0, .body_lowerings = 0, .imported_schemes = 0 } } };
            var original_alive = true;
            defer if (original_alive) original.deinit(a);
            const sites = try a.dupe(Site, &.{.{ .unit = 1, .span = .{ .start = 7, .end = 9 }, .lowering = .direct, .reason = .proved_local }});
            original.result.compiled.demand_lowering = .{ .sites = sites, .omitted = 3 };
            var cached = try CachedOutput.init(a, "main.blot", null, &original, 1, .{});
            defer cached.deinit(a);
            original.deinit(a);
            original_alive = false;
            var output = try cached.emission(a);
            defer output.deinit(a);
            try std.testing.expectEqualStrings("wasm", output.result.compiled.bytes);
            const report = output.result.compiled.demand_lowering.?;
            try std.testing.expectEqual(@as(usize, 3), report.omitted);
            try std.testing.expectEqual(@as(u32, 7), report.sites[0].span.start);
            try std.testing.expectEqual(@as(u64, 0), output.result.compiled.counters.demand_direct);
            try std.testing.expect(cached.matches("main.blot", null, .{}, true));
            try std.testing.expect(!cached.matches("main.blot", null, .{}, false));
        }
    };
    try Law.run(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, Law.run, .{});
}

const Current = struct {
    prepared: partial.Prepared,
    artifacts: capture.Capture,
    snapshot: inputs.Frozen,
    output: ?CachedOutput = null,
    fn deinit(self: *Current, a: Allocator) void {
        // Artifact producer pins are invalid once Prepared's fresh Core dies.
        self.artifacts.deinit();
        self.prepared.deinit(a);
        self.snapshot.deinit();
        if (self.output) |*output| output.deinit(a);
    }
};
/// A previous process's successful output and the inputs it read, from the
/// restart cache. A first build whose inputs, settings, entry and output policy
/// equal them exactly publishes that output without compiling, under the same
/// unchanged-input contract as a retained session; it keeps no retained state.
pub const Restored = struct {
    allocator: Allocator,
    inputs: inputs.Persisted,
    output: CachedOutput,
    entry_canonical: []u8,
    settings: [32]u8,
    /// Digest of the checkpoint the same writer published, if any.
    checkpoint_digest: ?[32]u8,

    pub const Wire = struct {
        settings: [32]u8,
        entry_request: []const u8,
        entry_canonical: []const u8,
        output_identity: ?[]const u8,
        policy: Policy,
        wasm: []const u8,
        source_bytes: usize,
        modules: usize,
        checkpoint_digest: ?[32]u8,
        inputs: inputs.Persisted.Wire,
    };
    fn key(compiler: [32]u8) dependency_format.Key {
        return .{ .compiler = compiler, .settings = dependency_format.digest("blot-restored-output-v1"), .source = @splat(0), .dependencies = @splat(0) };
    }
    /// Rejects bytes that do not decode for `compiler`, or whose entry is not
    /// among their own source observations.
    pub fn decode(a: Allocator, compiler: [32]u8, bytes: []const u8) !Restored {
        var wire = try dependency_format.decode(Wire, a, bytes, key(compiler));
        var wire_alive = true;
        defer if (wire_alive) dependency_format.deinit(a, &wire);
        const entry_read = for (wire.inputs.files) |file| {
            if (std.mem.eql(u8, file.key, wire.entry_canonical)) break true;
        } else false;
        if (!entry_read or wire.wasm.len == 0) return error.InvalidArtifact;
        var persisted = try inputs.Persisted.adopt(a, wire.inputs);
        wire.inputs = .{ .options = .{}, .paths = &.{}, .files = &.{}, .imports = &.{} };
        errdefer persisted.deinit();
        // The output owns the decoded strings and bytes from here on.
        const result: Restored = .{
            .allocator = a,
            .inputs = persisted,
            .output = .{ .entry_request = @constCast(wire.entry_request), .output_identity = @constCast(wire.output_identity), .bytes = @constCast(wire.wasm), .source_bytes = wire.source_bytes, .modules = wire.modules, .policy = wire.policy },
            .entry_canonical = @constCast(wire.entry_canonical),
            .settings = wire.settings,
            .checkpoint_digest = wire.checkpoint_digest,
        };
        wire_alive = false;
        return result;
    }
    pub fn deinit(self: *Restored) void {
        self.inputs.deinit();
        self.output.deinit(self.allocator);
        self.allocator.free(self.entry_canonical);
        self.* = undefined;
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
    reused_core_bodies: usize = 0,
    reused_entry_bodies: usize = 0,
    entry_cutoff: @import("entry_frontend_cutoff.zig").Stats = .{},
    module_cutoff: @import("entry_frontend_cutoff.zig").Stats = .{},
    dependency_storage: retained_dependency.Stats = .{},
    /// The published check rejection came from the lane that checked only the
    /// changed modules, or the entry against frozen dependencies, without
    /// checking the whole project again (partial.portableRejection).
    portable_rejection: bool = false,
};
pub const Stats = struct { rebuilt_seed: bool = false, reused_output: bool = false, trivia_only: bool = false, restored_output: bool = false, inputs: inputs.Counts = .{}, fallback: FallbackStats = .{} };

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
    policy: Policy = .{},
    profile_backend: bool = false,
    explain_demands: bool = false,
    checkpoint: ?@import("../backend/backend_checkpoint.zig").Checkpoint = null,
    /// Released when a compiled revision commits.
    restored: ?Restored = null,

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
        if (self.checkpoint) |*checkpoint| checkpoint.deinit();
        if (self.restored) |*restored| restored.deinit();
        self.releaseSeed();
        if (self.epoch) |epoch| epoch.release();
        self.* = undefined;
    }
    /// Exports only the committed revision. Encoding never modifies it, and
    /// callers own the returned bytes independently of this Session.
    pub fn checkpointBytes(self: *const Session, compiler: [32]u8) ![]u8 {
        return self.encodeCheckpoint(self.allocator, compiler);
    }
    /// As `checkpointBytes`, with every allocation from `a`. Encoding only
    /// reads the session, so a forked restart-cache writer can run it on its
    /// own heap over a copy-on-write image.
    pub fn encodeCheckpoint(self: *const Session, a: Allocator, compiler: [32]u8) ![]u8 {
        if (self.epoch) |epoch| if (epoch.preparing or epoch.active != null) return error.RevisionBusy;
        const current = &(self.current orelse return error.NoSuccessfulRevision);
        return @import("../backend/backend_checkpoint.zig").encode(a, compiler, &current.artifacts);
    }
    /// The committed revision's output and inputs for `Restored.decode`, or
    /// null when it cannot be restored: an explained output, or an input
    /// observation that failed. `checkpoint` is what the same writer publishes.
    pub fn encodeRestored(self: *const Session, a: Allocator, compiler: [32]u8, checkpoint: ?[]const u8) !?[]u8 {
        if (self.epoch) |epoch| if (epoch.preparing or epoch.active != null) return error.RevisionBusy;
        const current = &(self.current orelse return null);
        const output = current.output orelse return null;
        const prepared = &current.prepared;
        if (output.demand_lowering != null or prepared.entry == 0 or prepared.entry > prepared.paths.len) return null;
        const observed = try inputs.Persisted.capture(a, current.snapshot.view()) orelse return null;
        defer inputs.Persisted.releaseWire(a, observed);
        return try dependency_format.encode(a, Restored.key(compiler), Restored.Wire{
            .settings = self.seed_settings,
            .entry_request = output.entry_request,
            .entry_canonical = prepared.paths[prepared.entry - 1],
            .output_identity = output.output_identity,
            .policy = output.policy,
            .wasm = output.bytes,
            .source_bytes = output.source_bytes,
            .modules = output.modules,
            .checkpoint_digest = if (checkpoint) |bytes| dependency_format.digest(bytes) else null,
            .inputs = observed,
        });
    }
    /// A first build may publish the restored output. Returns null, having
    /// published nothing, unless this build's inputs equal the restored ones.
    pub fn prepareRestored(self: *Session, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, options: project.Options, sources: []const inputs.overlays.Source) !?Preparation {
        const restored = if (self.restored) |*value| value else return null;
        if (self.current != null or options.input_mode != .project) return null;
        const epoch = try self.bind();
        if (epoch.preparing or epoch.active != null) return error.CandidateActive;
        if (self.revisions == std.math.maxInt(usize) or epoch.token == std.math.maxInt(usize) or epoch.references == std.math.maxInt(usize)) return error.RevisionLimit;
        epoch.preparing = true;
        defer epoch.preparing = false;
        const a = self.allocator;
        const timing = phase_profile.enter(.inputs);
        defer timing.exit();
        var snapshot = try inputs.Snapshot.initWithSources(a, io, options, sources);
        defer snapshot.deinit();
        const settings_key = settings(snapshot.options);
        if (!std.mem.eql(u8, &restored.settings, &settings_key) or !restored.output.matches(entry_path, output_identity, self.policy, self.explain_demands)) return null;
        if (!try snapshot.entryPathEqualsPrevious(io, entry_path, restored.entry_canonical) or !try snapshot.equalsPrevious(io, restored.inputs.view())) return null;
        var emission = try restored.output.emission(a);
        errdefer emission.deinit(a);
        const candidate = try a.create(Candidate);
        candidate.* = .{ .allocator = a, .epoch = epoch, .token = epoch.token + 1, .base_revision = self.revisions, .settings_key = settings_key, .stats = .{ .reused_output = true, .restored_output = true, .inputs = snapshot.counts }, .pending = null, .seed = null, .emission = emission, .kind = .unchanged };
        epoch.token = candidate.token;
        epoch.references += 1;
        epoch.active = candidate;
        return .{ .ready = candidate };
    }
    fn releaseSeed(self: *Session) void {
        if (self.seed_snapshot) |owner| owner.deinit() else dependency_format.deinit(self.allocator, &self.seed);
        self.seed_snapshot = null;
    }
    fn ensureSharedSeed(self: *Session) !void {
        if (self.seed_snapshot != null) return;
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
                if (self.restored) |*restored| restored.deinit();
                self.restored = null;
            },
            .unchanged => {
                std.debug.assert((self.current != null or self.restored != null) and candidate.pending == null and candidate.seed == null);
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
        const previous = if (self.current) |*value| value else return null;
        const prepared = &previous.prepared;
        if (prepared.units.len == 0 or prepared.entry != prepared.units.len or prepared.units.len != self.seed.modules.len + 1 or prepared.cached != self.seed.modules.len or prepared.paths.len != prepared.units.len) return null;
        // The old entry proof and this dependency seed belong to one successful
        // publication. Check every borrowed prefix header before offering it.
        for (self.seed.modules, prepared.units[0..self.seed.modules.len]) |module, ir| {
            if (!std.meta.eql(module.core, ir)) return null;
        }
        return .{ .prepared = prepared, .source = previous.snapshot.capturedSource(prepared.paths[prepared.entry - 1]) orelse return null, .reuse_modules = true };
    }
    fn frontendOffer(self: *const Session, options: project.Options) ?partial.EntryPrevious {
        if (!std.mem.eql(u8, &self.seed_settings, &settings(options))) return null;
        if (self.entryOffer()) |offer| return offer;
        return self.bodyOffer(options);
    }
    fn bodyOffer(self: *const Session, options: project.Options) ?partial.EntryPrevious {
        if (!std.mem.eql(u8, &self.seed_settings, &settings(options))) return null;
        const previous = if (self.current) |*value| value else return null;
        const prepared = &previous.prepared;
        if (prepared.entry == 0 or prepared.entry > prepared.paths.len or prepared.paths.len != prepared.units.len or prepared.body_caches.len != prepared.units.len) return null;
        // Body chunks are independent of the old seed/Core pairing. Only their
        // filename directory is offered; each body rechecks current reads.
        return .{ .prepared = prepared, .source = previous.snapshot.capturedSource(prepared.paths[prepared.entry - 1]) orelse return null, .body_only = true };
    }
    fn mixedFrontend(self: *Session, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, snapshot: *inputs.Snapshot, candidate_seed: *?retained_dependency.Seed, counts: *FallbackStats, reuse: []const bool) !?partial.Preparation {
        const a = self.allocator;
        var work: FallbackStats = .{};
        var kept: ?partial.Prepared = null;
        defer if (kept) |*prepared| prepared.deinit(a);
        var frozen = snapshot_block: {
            var source = try project.loadCompiledMixedReadOnly(a, io, entry_path, snapshot.options, &self.seed, snapshot.provider(), reuse);
            defer source.deinit(a);
            source.lowering = .{ .io = io, .workers = self.policy.semantic_workers };
            if (source.diagnostics.items.len != 0) return null;
            var checked: ?checker.CheckedProject = null;
            defer if (checked) |*owner| owner.deinit(a);
            var fresh = try partial.prepareProjectKeepingEntry(a, &source, entry_path, output_identity, &self.seed, &checked, self.frontendOffer(snapshot.options));
            var fresh_alive = true;
            defer if (fresh_alive) fresh.deinit(a);
            if (fresh == .rejected) {
                // The ordinary lane would meet this same first diagnostic
                // (partial.portableRejection); only other rejections take it.
                if (!fresh.rejected.portable) return null;
                fresh_alive = false;
                counts.portable_rejection = true;
                return fresh;
            }
            const saved: retained_dependency.Seed = shared: {
                const owner = try closure.freezeSharedFromMixed(a, &source, &checked.?, &fresh.ready, self.seed_snapshot.?, &work.dependency_storage);
                break :shared .{ .value = owner.value, .snapshot = owner };
            };
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
            kept = fresh.ready;
            fresh_alive = false;
            break :snapshot_block saved;
        };
        // The new seed owns or retains every immutable module independently.
        // Release temporary syntax/check/Core before preparing its consumer.
        var transferred = false;
        defer if (!transferred) frozen.deinit(a);
        if (kept) |*prepared| {
            {
                const timing = phase_profile.enter(.freeze);
                defer timing.exit();
                try prepared.rebindFrozenPrefix(a, &frozen.value);
            }
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
        if (std.mem.eql(u8, &self.seed_settings, &settings(snapshot.options))) {
            const reusable = reused: {
                const timing = phase_profile.enter(.inputs);
                defer timing.exit();
                break :reused try snapshot.reusableModules(io, &self.seed);
            };
            if (reusable) |reuse| {
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
        source.lowering = .{ .io = io, .workers = self.policy.semantic_workers };
        const body_offer = self.bodyOffer(snapshot.options);
        const check_offer: ?@import("entry_frontend_cutoff.zig").Previous = if (body_offer) |offer| partial.checkPrevious(offer) else null;
        // The ordinary lane checks the entry twice: within the whole project,
        // then as the consumer of the frozen dependencies, whose result is
        // published. Defer it from the first check; finish that check only
        // when the consumer lane declines with a failure it cannot publish
        // (see consumeDeferred), so the ordinary lane below owns the rest.
        // Only the first diagnostic is published, so a dependency's stops the
        // check there.
        var deferred: ?checker.CheckedProject = null;
        defer if (deferred) |*checked| checked.deinit(a);
        if (source.diagnostics.items.len == 0 and !outputIsSource(&source, output_identity)) {
            deferred = try checker.checkProjectDeferringEntryToFirstDiagnostic(a, &source, check_offer);
            if (try self.consumeDeferred(io, entry_path, output_identity, snapshot, &source, &deferred.?, candidate_seed, counts, body_offer)) |consumer| return consumer;
            try checker.checkDeferredEntry(a, &source, &deferred.?, check_offer);
        }
        // Both lanes retain the ordinary source/check/lower validation order.
        // The private sharing lane keeps only that successful check, for this
        // exact captured Project, until closure freeze. No failure is cached.
        var kept_check: ?checker.CheckedProject = null;
        defer if (kept_check) |*checked| checked.deinit(a);
        const empty: dependency.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
        var fresh = if (deferred) |checked| precomputed: {
            deferred = null;
            break :precomputed try partial.prepareProjectWithCheck(a, &source, entry_path, output_identity, &empty, checked, &kept_check, body_offer);
        } else try partial.prepareProjectKeepingEntry(a, &source, entry_path, output_identity, &empty, &kept_check, body_offer);
        var fresh_alive = false;
        defer if (fresh_alive) fresh.deinit(a);
        switch (fresh) {
            .rejected => return fresh,
            .ready => |*prepared| {
                counts.validated_modules = prepared.units.len;
                counts.syntax_nodes = prepared.stats.syntax_nodes;
                counts.body_elaborations = prepared.stats.body_elaborations;
                counts.body_lowerings = prepared.stats.body_lowerings;
                fresh_alive = true;
            },
        }
        if (kept_check == null) {
            kept_check = try checker.checkProject(a, &source);
            counts.recheck_body_elaborations = kept_check.?.body_elaborations;
        } else counts.reused_check_body_elaborations = kept_check.?.body_elaborations;
        const frozen = try closure.freezeFromCheckedCore(a, &source, &kept_check.?, &fresh.ready);
        // The seed owns Core; checked body offers keep their independent
        // owners across the entry-only preparation, without retaining Core.
        const body_caches = fresh.ready.body_caches;
        fresh.ready.body_caches = &.{};
        defer {
            for (body_caches) |*cache| cache.deinit(a);
            a.free(body_caches);
        }
        const body_paths = fresh.ready.paths;
        fresh.ready.paths = &.{};
        defer {
            for (body_paths) |path| a.free(path);
            a.free(body_paths);
        }
        fresh.deinit(a);
        fresh_alive = false;
        candidate_seed.* = .{ .value = frozen };
        const owner = try retained_dependency.Snapshot.adopt(a, frozen);
        owner.validated = true;
        candidate_seed.*.?.snapshot = owner;
        counts.dependency_storage = .{ .fresh_modules = frozen.modules.len, .core_checked = frozen.modules.len, .interface_checked = frozen.modules.len };
        counts.frozen_modules = frozen.modules.len;
        for (frozen.modules) |module| counts.reused_core_bodies += module.core.body_lowerings;
        var consumer = try partial.prepareReadOnlyWithBodies(a, io, entry_path, output_identity, snapshot.options, &candidate_seed.*.?.value, snapshot.provider(), body_offer);
        errdefer consumer.deinit(a);
        if (consumer == .ready) try consumer.ready.inheritBodyCaches(a, body_caches, body_paths);
        return consumer;
    }
    fn outputIsSource(source: *const project.Project, output_identity: ?[]const u8) bool {
        const output = output_identity orelse return false;
        for (source.units.items) |unit| if (std.mem.eql(u8, output, source.symbols.get(unit.filename))) return true;
        return false;
    }
    /// The consumer lane of a deferred population check: freeze the checked
    /// dependencies and prepare the entry once, against that seed, exactly as
    /// the ordinary lane's published consumer. It publishes success, and a
    /// portable rejection (partial.portableRejection), which the entry's check
    /// against the live dependencies would report identically; nothing is
    /// seeded from a rejection. Null leaves the candidate seed and counts
    /// untouched.
    fn consumeDeferred(self: *Session, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, snapshot: *inputs.Snapshot, source: *project.Project, checked: *const checker.CheckedProject, candidate_seed: *?retained_dependency.Seed, counts: *FallbackStats, body_offer: ?partial.EntryPrevious) !?partial.Preparation {
        const a = self.allocator;
        if (checked.deferred_entry == null or checked.diagnostics.len != 0) return null;
        // A lowering diagnostic or limit is reported by the ordinary lane.
        const frozen = closure.freezeDeferringEntry(a, source, checked) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
        var seed: retained_dependency.Seed = .{ .value = frozen };
        var seed_alive = true;
        defer if (seed_alive) seed.deinit(a);
        const owner = try retained_dependency.Snapshot.adopt(a, frozen);
        owner.validated = true;
        seed.snapshot = owner;
        var consumer = try partial.prepareReadOnlyWithBodies(a, io, entry_path, output_identity, snapshot.options, &seed.value, snapshot.provider(), body_offer);
        if (consumer == .rejected) {
            if (consumer.rejected.portable) {
                counts.portable_rejection = true;
                return consumer;
            }
            consumer.deinit(a);
            return null;
        }
        errdefer consumer.deinit(a);
        // Dependency body offers come from this check; the deferred entry has
        // none, so the consumer keeps its own.
        const paths = try a.alloc([]const u8, source.units.items.len);
        defer a.free(paths);
        for (paths, 1..) |*path, unit| path.* = source.filename(@intCast(unit));
        try consumer.ready.inheritBodyCaches(a, checked.body_caches, paths);
        var work: FallbackStats = .{ .validated_modules = source.units.items.len, .body_elaborations = checked.body_elaborations, .reused_check_body_elaborations = checked.body_elaborations, .frozen_modules = frozen.modules.len };
        for (source.units.items) |unit| work.syntax_nodes += unit.tree.nodes.items.len - 1;
        // Each dependency body was lowered once, straight into the seed.
        for (frozen.modules) |module| work.body_lowerings += module.core.body_lowerings;
        work.reused_core_bodies = work.body_lowerings;
        work.dependency_storage = .{ .fresh_modules = frozen.modules.len, .core_checked = frozen.modules.len, .interface_checked = frozen.modules.len };
        counts.* = work;
        candidate_seed.* = seed;
        seed_alive = false;
        return consumer;
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
        // Input capture and comparison end before any frontend preparation.
        const input_timing = phase_profile.enter(.inputs);
        var capturing = true;
        defer if (capturing) input_timing.exit();
        var snapshot = try inputs.Snapshot.initWithSources(a, io, options, sources);
        var snapshot_alive = true;
        defer if (snapshot_alive) snapshot.deinit();
        var candidate_seed: ?retained_dependency.Seed = null;
        defer if (candidate_seed) |*seed| seed.deinit(a);
        const settings_key = settings(snapshot.options);
        const admitted = std.mem.eql(u8, &self.seed_settings, &settings_key) and try snapshot.admits(io, &self.seed);
        if (self.current) |*current| if (current.output) |output| {
            // A trivia-only edit (comments, or spacing that keeps the same
            // tokens and adjacency) parses to the same program, so the last
            // output stands and the retained state is kept; later edits diff
            // against the last compiled sources. Settings must be unchanged.
            const reusable = std.mem.eql(u8, &self.seed_settings, &settings_key) and output.matches(entry_path, output_identity, self.policy, self.explain_demands) and try snapshot.entryPathEqualsPrevious(io, entry_path, current.prepared.paths[current.prepared.entry - 1]);
            const exact = reusable and admitted and try snapshot.entryEqualsPrevious(io, entry_path, current.prepared.paths[current.prepared.entry - 1], current.snapshot.view()) and try snapshot.equalsPrevious(io, current.snapshot.view());
            // Explained spans belong to the actual source bytes. Recompute
            // them after trivia changes rather than publishing old offsets.
            if (exact or (!self.explain_demands and reusable and try snapshot.triviaEqualsPrevious(io, current.snapshot.view()))) {
                var emission = try output.emission(a);
                errdefer emission.deinit(a);
                const candidate = try a.create(Candidate);
                candidate.* = .{ .allocator = a, .epoch = epoch, .token = epoch.token + 1, .base_revision = self.revisions, .settings_key = settings_key, .stats = .{ .reused_output = true, .trivia_only = !exact, .inputs = snapshot.counts }, .pending = null, .seed = null, .emission = emission, .kind = .unchanged };
                epoch.token = candidate.token;
                epoch.references += 1;
                epoch.active = candidate;
                return .{ .ready = candidate };
            }
        };
        input_timing.exit();
        capturing = false;
        var fallback_counts: FallbackStats = .{};
        var preparation: partial.Preparation = undefined;
        if (admitted) {
            var fast_result = true;
            preparation = partial.prepareReadOnlyWithBodies(a, io, entry_path, output_identity, snapshot.options, &self.seed, snapshot.provider(), self.frontendOffer(snapshot.options)) catch |err| switch (err) {
                error.DependencySetChanged => blk: {
                    fast_result = false;
                    break :blk try self.fallback(io, entry_path, output_identity, &snapshot, &candidate_seed, &fallback_counts);
                },
                else => return err,
            };
            if (fast_result) switch (preparation) {
                .rejected => |*result| if (result.portable) {
                    // A portable check rejection already is the fresh result.
                    fallback_counts.portable_rejection = true;
                } else {
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
                // Old pins stay alive until candidate publication. The backend
                // checks exact per-body dependencies, catalogs and static value
                // graphs even when a dependency seed had to be rebuilt.
                const prior_compatible = !rebuilt;
                const compatible = prior_compatible or std.mem.eql(u8, &self.seed_settings, &settings_key);
                var result = emitted: {
                    const timing = phase_profile.enter(.backend);
                    defer timing.exit();
                    break :emitted try prepared.emitWithOptions(a, .{
                        .io = io,
                        .profile_backend = self.profile_backend,
                        .explain_demands = self.explain_demands,
                        .checkpoint = if (self.checkpoint) |*checkpoint| checkpoint else null,
                        .policy = self.policy,
                        .retain_artifacts = true,
                        .previous = if (compatible and self.current != null) &self.current.?.artifacts else null,
                        .query_previous = if (compatible and self.current != null) &self.current.?.artifacts else null,
                        .principal_previous = if (rebuilt and self.current != null) &self.current.?.artifacts else null,
                        .cached_units = prepared.cached,
                    });
                };
                errdefer result.deinit(a);
                if (result.result.compiled.diagnostic != null) {
                    snapshot_alive = false;
                    return .{ .rejected = .{ .result = result, .snapshot = snapshot, .stats = .{ .rebuilt_seed = rebuilt, .inputs = snapshot.counts, .fallback = fallback_counts } } };
                }
                var artifacts = result.result.compiled.capture orelse return error.MissingOwnedArtifacts;
                result.result.compiled.capture = null;
                errdefer artifacts.deinit();
                var cached_output = try CachedOutput.init(a, entry_path, output_identity, &result, prepared.units.len, self.policy);
                errdefer cached_output.deinit(a);
                const candidate = try a.create(Candidate);
                const input_counts = snapshot.counts;
                candidate.* = .{
                    .allocator = a,
                    .epoch = epoch,
                    .token = epoch.token + 1,
                    .base_revision = self.revisions,
                    .settings_key = settings_key,
                    .stats = .{ .rebuilt_seed = rebuilt, .inputs = input_counts, .fallback = fallback_counts },
                    .pending = .{ .prepared = prepared.*, .artifacts = artifacts, .snapshot = snapshot.freeze(), .output = cached_output },
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
