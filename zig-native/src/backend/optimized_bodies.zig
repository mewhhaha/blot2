//! Immutable optimizer inputs and results owned by one successful revision.
//! Exact input equality authorizes reuse; no source hash or semantic admission
//! can substitute for the call/body/ownership facts consumed by these passes.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const lifetimes = @import("wasm_lifetimes.zig");
const executable = @import("../reuse/executable_query.zig");
const A = std.mem.Allocator;

pub const Stats = struct {
    tier: @import("../compilation_tier.zig").Tier = .optimized,
    functions: usize = 0,
    optimized: usize = 0,
    reused: usize = 0,
    /// Prepared source bodies omitted only from final machine emission;
    /// this is independent of optimized/reused preparation counts.
    shared: usize = 0,
    workers: usize = 1,
    parallel_jobs: usize = 0,
    retained_bytes: usize = 0,
    /// Stores that contradict an allocation's checked word roles (see
    /// `wasm_lifetimes.Summaries.role_conflicts`).
    role_conflicts: usize = 0,
    /// Exact optimizer matching work, bounded independently of source fuel.
    match_candidates: usize = 0,
    match_work: usize = 0,
    match_budget_exhausted: usize = 0,
};
const Entry = struct {
    source: ir.Function,
    parameters: []lifetimes.Parameter,
    invalidates: bool,
    owned_result_bytes: ?u32,
    output: ?ir.Body = null,
    output_ready: bool = false,

    fn deinit(self: *Entry, a: A) void {
        a.free(self.source.parameters);
        self.source.deinit(a);
        a.free(self.parameters);
        if (self.output) |*body| body.deinit(a);
    }
};

pub const Import = struct {
    module: []u8,
    name: []u8,
    signature: u32,
    fn deinit(self: Import, a: A) void {
        a.free(self.module);
        a.free(self.name);
    }
};

pub const Capture = struct {
    allocator: A,
    roots: bool = false,
    needs_roots: bool = false,
    root_slots: u32 = 0,
    tier: @import("../compilation_tier.zig").Tier = .optimized,
    entries: std.ArrayList(Entry) = .empty,
    signatures: std.ArrayList(ir.Signature) = .empty,
    imports: std.ArrayList(Import) = .empty,
    globals: std.ArrayList(wasm.Global) = .empty,
    arena: ?wasm.Arena = null,
    /// Exact freshly constructed preparation context; never semantic authority.
    regions: ?@import("../runtime/region_runtime.zig").Prepared = null,
    providers: std.ArrayList(@import("provider_modes.zig").Mode) = .empty,
    queries: executable.OptimizerTable = .{},
    queries_complete: bool = false,

    pub fn deinit(self: *Capture) void {
        if (self.regions) |regions| {
            self.allocator.free(regions.plan.members);
            self.allocator.free(regions.scopes);
        }
        self.queries.deinit(self.allocator);
        for (self.entries.items) |*entry| entry.deinit(self.allocator);
        for (self.signatures.items) |signature| self.allocator.free(signature.parameters);
        self.entries.deinit(self.allocator);
        self.signatures.deinit(self.allocator);
        for (self.imports.items) |item| item.deinit(self.allocator);
        self.imports.deinit(self.allocator);
        self.globals.deinit(self.allocator);
        self.providers.deinit(self.allocator);
        self.* = .{ .allocator = self.allocator };
    }

    /// The caller publishes only after complete assembly. Failed candidates
    /// release this owner without modifying the previous revision's capture.
    pub fn captureRegions(self: *Capture, regions: ?@import("../runtime/region_runtime.zig").Prepared) A.Error!void {
        std.debug.assert(self.regions == null);
        const context = regions orelse return;
        const members = try self.allocator.dupe(@import("../runtime/region_runtime.zig").Member, context.plan.members);
        errdefer self.allocator.free(members);
        const scopes = try self.allocator.dupe(@import("../runtime/region_runtime.zig").Scope, context.scopes);
        self.regions = context;
        self.regions.?.plan.members = members;
        self.regions.?.scopes = scopes;
    }
    pub fn recordInputs(self: *Capture, module: *const wasm.Module, summaries: *const lifetimes.Summaries) A.Error!void {
        std.debug.assert(self.entries.items.len == 0 and self.signatures.items.len == 0);
        self.arena = module.arena;
        try self.captureRegions(module.regions);
        try self.entries.ensureTotalCapacity(self.allocator, module.functions.items.len);
        for (module.functions.items, summaries.functions) |function, summary| {
            var source = try cloneFunction(self.allocator, function);
            errdefer {
                self.allocator.free(source.parameters);
                source.deinit(self.allocator);
            }
            const parameters = try self.allocator.dupe(lifetimes.Parameter, summary.parameters);
            self.entries.appendAssumeCapacity(.{ .source = source, .parameters = parameters, .invalidates = summary.invalidates, .owned_result_bytes = summary.owned_result_bytes });
        }
        try self.signatures.ensureTotalCapacity(self.allocator, module.signatures.items.len);
        for (module.signatures.items) |signature| self.signatures.appendAssumeCapacity(.{ .parameters = try self.allocator.dupe(ir.ValueType, signature.parameters), .result = signature.result });
        try self.imports.ensureTotalCapacity(self.allocator, module.imports.items.len);
        for (module.imports.items) |item| {
            const namespace = try self.allocator.dupe(u8, item.module);
            errdefer self.allocator.free(namespace);
            const name = try self.allocator.dupe(u8, item.name);
            self.imports.appendAssumeCapacity(.{ .module = namespace, .name = name, .signature = item.signature });
        }
        try self.globals.ensureTotalCapacity(self.allocator, module.globals.items.len);
        self.globals.appendSliceAssumeCapacity(module.globals.items);
    }

    pub fn recordOutput(self: *Capture, id: usize, body_result: ?ir.Body) A.Error!void {
        std.debug.assert(self.entries.items[id].output == null);
        self.entries.items[id].output = if (body_result) |body| try cloneBody(self.allocator, body) else null;
        self.entries.items[id].output_ready = true;
    }
    pub fn output(self: *const Capture, id: usize) ?ir.Body {
        return self.entries.items[id].output;
    }
    /// Records are sealed in ascending source order, including physical gaps.
    /// This exact ordinal lookup preserves the same-position fast path without
    /// granting reuse to unpublished, skipped or saturated inquiries.
    fn queryAt(self: *const Capture, id: usize) ?*const executable.OptimizerTable.Record {
        if (!self.queries_complete or self.queries.limits.lookup_work == 0) return null;
        var first: usize = 0;
        var end = self.queries.records.items.len;
        while (first < end) {
            const middle = first + (end - first) / 2;
            const record = &self.queries.records.items[middle];
            if (record.value.function < id) first = middle + 1 else if (record.value.function > id) end = middle else return record;
        }
        return null;
    }
    /// Seal in source ordinal order after successful assembly, never in worker
    /// completion order. Skipped physical aliases remain inputs, not results.
    /// A saturated optional index declines relocation for the entire owner.
    pub fn sealQueries(self: *Capture) A.Error!void {
        std.debug.assert(self.queries.records.items.len == 0 and !self.queries_complete);
        for (self.entries.items, 0..) |entry, id| {
            if (!entry.output_ready) continue;
            var call_count: usize = 0;
            for (entry.source.instructions.items) |inst| if (inst.op == .call or inst.table_reference) {
                call_count += 1;
            };
            const bytes_needed = executable.dependencyBytes(u32, call_count, lifetimes.Parameter, entry.parameters.len) orelse {
                self.queries.saturated +|= 1;
                return;
            };
            if (self.queries.records.items.len >= self.queries.limits.records or bytes_needed > self.queries.limits.owned_bytes -| self.queries.owned_bytes) {
                self.queries.saturated +|= 1;
                return;
            }
            var builder = executable.OptimizerTable.begin(self.allocator, .{ .local_fingerprint = @import("runtime_body_relocation.zig").hash(entry.source), .tier = self.tier });
            defer builder.abort();
            const callees = try self.allocator.alloc(u32, call_count);
            var transferred = false;
            defer if (!transferred) self.allocator.free(callees);
            var cursor: usize = 0;
            for (entry.source.instructions.items) |inst| if (inst.op == .call or inst.table_reference) {
                callees[cursor] = inst.operand;
                cursor += 1;
            };
            builder.read(.{ .callees = callees, .parameters = try self.allocator.dupe(lifetimes.Parameter, entry.parameters), .invalidates = entry.invalidates, .owned_result_bytes = entry.owned_result_bytes, .context_complete = true });
            transferred = true;
            builder.stage(.{ .function = @intCast(id), .ready = true });
            var candidate = builder.complete().?;
            defer candidate.abort();
            const prepared = try self.queries.prepare(self.allocator, &candidate) orelse return;
            _ = self.queries.publish(prepared, &candidate);
        }
        self.queries_complete = true;
    }
    pub fn bytes(self: *const Capture) usize {
        var count = self.entries.items.len * @sizeOf(Entry) + self.signatures.items.len * @sizeOf(ir.Signature) + self.imports.items.len * @sizeOf(Import) + self.globals.items.len * @sizeOf(wasm.Global) + self.providers.items.len * @sizeOf(@import("provider_modes.zig").Mode);
        for (self.entries.items) |entry| {
            count += entry.source.parameters.len + entry.source.locals.items.len + entry.source.instructions.items.len * @sizeOf(ir.Instruction) + entry.parameters.len * @sizeOf(lifetimes.Parameter);
            if (entry.output) |body| count += body.locals.items.len + body.instructions.items.len * @sizeOf(ir.Instruction);
        }
        for (self.signatures.items) |signature| count += signature.parameters.len;
        for (self.imports.items) |item| count += item.module.len + item.name.len;
        if (self.regions) |regions| count += regions.plan.members.len * @sizeOf(@import("../runtime/region_runtime.zig").Member) + regions.scopes.len * @sizeOf(@import("../runtime/region_runtime.zig").Scope);
        return count + self.queries.owned_bytes + self.queries.capacity_bytes;
    }
};

fn regionsEqual(before: ?@import("../runtime/region_runtime.zig").Prepared, after: ?@import("../runtime/region_runtime.zig").Prepared) bool {
    const left = before orelse return after == null;
    const right = after orelse return false;
    if (!std.meta.eql(left.runtime, right.runtime) or left.plan.frame_bytes != right.plan.frame_bytes or left.plan.bytes != right.plan.bytes or left.plan.mask != right.plan.mask or left.plan.members.len != right.plan.members.len or left.scopes.len != right.scopes.len) return false;
    for (left.plan.members, right.plan.members) |l, r_| if (!std.meta.eql(l, r_)) return false;
    for (left.scopes, right.scopes) |l, r_| if (!std.meta.eql(l, r_)) return false;
    return true;
}

pub const Matcher = struct {
    allocator: A,
    old: *const Capture,
    current: *const Capture,
    same: []bool,
    arena_same: bool,
    relocated: []?ir.Body,
    prior_ids: []?usize,
    candidates: usize = 0,
    work: usize = 0,
    budget_exhausted: usize = 0,

    fn resourceDrain(capture: *const Capture) bool {
        for (capture.imports.items) |item| {
            if (!std.mem.eql(u8, item.module, "blot:resource/2") or !std.mem.eql(u8, item.name, "drain")) continue;
            const signature = capture.signatures.items[item.signature];
            if (signature.parameters.len == 0 and signature.result == .none) return true;
        }
        return false;
    }

    pub fn init(a: A, old: *const Capture, current: *const Capture) A.Error!Matcher {
        const same = try a.alloc(bool, current.entries.items.len);
        errdefer a.free(same);
        var providers_same = old.providers.items.len == current.providers.items.len;
        if (providers_same) for (old.providers.items, current.providers.items) |left, right| {
            if (!std.meta.eql(left, right)) {
                providers_same = false;
                break;
            }
        };
        // Cleanup drains are inserted at ordinary exits even when the source
        // body does not directly reference this import. Their presence is an
        // optimizer input, including the empty lexical-frame fallback.
        const arena_same = regionsEqual(old.regions, current.regions) and resourceDrain(old) == resourceDrain(current) and providers_same and old.tier == current.tier and old.roots == current.roots and old.needs_roots == current.needs_roots and old.root_slots == current.root_slots and (old.arena != null) == (current.arena != null);
        if (arena_same and old.queries_complete and old.queries.limits.lookup_work != 0) {
            for (same, current.entries.items, 0..) |*match, entry, id| match.* = id < old.entries.items.len and samePosition(old.entries.items[id].source, entry.source);
        } else @memset(same, false);
        const relocated = try a.alloc(?ir.Body, current.entries.items.len);
        errdefer a.free(relocated);
        @memset(relocated, null);
        const prior_ids = try a.alloc(?usize, current.entries.items.len);
        @memset(prior_ids, null);
        var self: Matcher = .{ .allocator = a, .old = old, .current = current, .same = same, .arena_same = arena_same, .relocated = relocated, .prior_ids = prior_ids };
        errdefer {
            for (relocated) |*body| if (body.*) |*owned| owned.deinit(a);
            a.free(prior_ids);
        }
        if (self.arena_same) try self.findRelocations();
        return self;
    }
    pub fn deinit(self: *Matcher) void {
        for (self.relocated) |*body| if (body.*) |*owned| owned.deinit(self.allocator);
        self.allocator.free(self.relocated);
        self.allocator.free(self.prior_ids);
        self.allocator.free(self.same);
    }
    fn samePosition(before: ir.Function, after: ir.Function) bool {
        if (!@import("runtime_body_relocation.zig").equalLocal(before, after)) return false;
        for (before.instructions.items, after.instructions.items) |left, right| if (left.operand != right.operand) return false;
        return true;
    }
    fn signatureSame(self: *const Matcher, before: u32, after: u32) bool {
        if (before >= self.old.signatures.items.len or after >= self.current.signatures.items.len) return false;
        const left = self.old.signatures.items[before];
        const right = self.current.signatures.items[after];
        return left.result == right.result and std.mem.eql(ir.ValueType, left.parameters, right.parameters);
    }
    fn matchesPosition(self: *const Matcher, walk: *@import("runtime_body_relocation.zig").Walk, id: usize) bool {
        if (!self.arena_same or !std.meta.eql(self.old.arena, self.current.arena) or !self.same[id] or self.old.entries.items[id].source.parameter_roles != self.current.entries.items[id].source.parameter_roles or !self.old.entries.items[id].output_ready) return false;
        const record = self.old.queryAt(id) orelse return false;
        if (record.key.tier != self.current.tier) return false;
        if (!self.summarySame(record.dependencies, self.current.entries.items[id])) return false;
        if (self.old.output(id)) |body| {
            if (!walk.spend(body.instructions.items.len)) return false;
            for (body.instructions.items) |inst| {
                const kind = @import("runtime_body_relocation.zig").referenceKind(inst) orelse continue;
                switch (kind) {
                    .function => if (inst.operand >= self.same.len or !self.same[inst.operand]) return false,
                    .import_ => if (!self.importSame(inst.operand, inst.operand)) return false,
                    .signature => if (!self.signatureSame(inst.operand, inst.operand)) return false,
                    .global => if (!self.globalSame(inst.operand, inst.operand)) return false,
                }
            }
        }
        return true;
    }
    fn summarySame(_: *const Matcher, before: executable.OptimizerDependencies, after: Entry) bool {
        if (before.invalidates != after.invalidates or before.owned_result_bytes != after.owned_result_bytes or before.parameters.len != after.parameters.len) return false;
        for (before.parameters, after.parameters) |left, right| if (!std.meta.eql(left, right)) return false;
        return true;
    }
    pub fn matches(self: *const Matcher, id: usize) bool {
        return self.prior_ids[id] != null;
    }
    pub fn output(self: *const Matcher, id: usize) ?ir.Body {
        return self.relocated[id] orelse self.old.output(self.prior_ids[id].?);
    }
    fn importSame(self: *const Matcher, before: u32, after: u32) bool {
        if (before >= self.old.imports.items.len or after >= self.current.imports.items.len) return false;
        const left = self.old.imports.items[before];
        const right = self.current.imports.items[after];
        return std.mem.eql(u8, left.module, right.module) and std.mem.eql(u8, left.name, right.name) and self.signatureSame(left.signature, right.signature);
    }
    fn globalSame(self: *const Matcher, before: u32, after: u32) bool {
        return before < self.old.globals.items.len and after < self.current.globals.items.len and std.meta.eql(self.old.globals.items[before], self.current.globals.items[after]);
    }
    fn arenaRole(comptime fields: anytype, arena: ?wasm.Arena, id: u32) ?usize {
        const value = arena orelse return null;
        inline for (fields, 0..) |field, index| if (@field(value, field) == id) return index;
        return null;
    }
    fn referenceSame(self: *const Matcher, walk: *@import("runtime_body_relocation.zig").Walk, kind: @import("runtime_body_relocation.zig").Kind, before: u32, after: u32) A.Error!bool {
        switch (kind) {
            .function => if (arenaRole(wasm.Arena.function_fields, self.old.arena, before) != arenaRole(wasm.Arena.function_fields, self.current.arena, after)) return false,
            .import_ => {
                if (!self.importSame(before, after)) return false;
                if (!try walk.add(self.allocator, .signature, self.old.imports.items[before].signature, self.current.imports.items[after].signature)) return false;
            },
            .signature => if (!self.signatureSame(before, after)) return false,
            .global => {
                if (!self.globalSame(before, after)) return false;
                if (arenaRole(wasm.Arena.global_fields, self.old.arena, before) != arenaRole(wasm.Arena.global_fields, self.current.arena, after)) return false;
            },
        }
        return walk.add(self.allocator, kind, before, after);
    }
    fn drainGraph(self: *const Matcher, walk: *@import("runtime_body_relocation.zig").Walk) A.Error!bool {
        const relocation = @import("runtime_body_relocation.zig");
        while (walk.pending.pop()) |pair| {
            if (pair.before >= self.old.entries.items.len or pair.after >= self.current.entries.items.len) return false;
            const left = self.old.entries.items[pair.before];
            const right = self.current.entries.items[pair.after];
            if (!try self.referenceSame(walk, .signature, left.source.signature, right.source.signature)) return false;
            if (!walk.spend(left.source.instructions.items.len +| left.source.parameters.len +| left.source.locals.items.len) or !relocation.equalLocal(left.source, right.source)) return false;
            if (left.invalidates != right.invalidates or left.owned_result_bytes != right.owned_result_bytes or left.parameters.len != right.parameters.len) return false;
            for (left.parameters, right.parameters) |l, r| if (!std.meta.eql(l, r)) return false;
            for (left.source.instructions.items, right.source.instructions.items) |l, r| {
                if (relocation.referenceKind(l)) |kind| if (!try self.referenceSame(walk, kind, l.operand, r.operand)) return false;
            }
        }
        return true;
    }
    fn graphSame(self: *const Matcher, walk: *@import("runtime_body_relocation.zig").Walk, before: usize, after: usize) A.Error!bool {
        walk.clear();
        if (!try self.referenceSame(walk, .function, @intCast(before), @intCast(after))) return false;
        return self.drainGraph(walk);
    }
    /// Passes may introduce named runtime helpers. Prove their complete input
    /// graphs as well; an ordinal coincidence cannot authorize cleanup reuse.
    fn outputReferences(self: *const Matcher, walk: *@import("runtime_body_relocation.zig").Walk, body: ir.Body) A.Error!bool {
        const relocation = @import("runtime_body_relocation.zig");
        for (body.instructions.items) |inst| {
            const kind = relocation.referenceKind(inst) orelse continue;
            if (!walk.spend(1)) return false;
            if (walk.get(kind, inst.operand) != null) continue;
            if (kind != .function) return false;
            const old_arena = self.old.arena orelse return false;
            const new_arena = self.current.arena orelse return false;
            var found = false;
            inline for (wasm.Arena.function_fields) |field| {
                if (@field(old_arena, field) == inst.operand) {
                    if (!try self.referenceSame(walk, .function, inst.operand, @field(new_arena, field))) return false;
                    found = true;
                }
            }
            if (!found) return false;
        }
        return self.drainGraph(walk);
    }
    /// Positional equality is only a shortcut after complete transitive facts
    /// settle. Changed imports/globals or ownership facts invalidate callers,
    /// including recursive components, even when all numeric operands stayed.
    fn preparePositions(self: *Matcher, walk: *@import("runtime_body_relocation.zig").Walk) A.Error!void {
        if (!std.meta.eql(self.old.arena, self.current.arena)) {
            @memset(self.same, false);
            return;
        }
        // Charge before allocating graph storage. Each input and dependency is
        // examined once; a changed callee enqueues every still-admitted caller.
        if (!walk.spend(self.same.len)) {
            @memset(self.same, false);
            return;
        }
        for (self.current.entries.items, self.same, 0..) |entry, *same, id| {
            if (!same.*) continue;
            const before = self.old.entries.items[id];
            if (!walk.spend(entry.source.instructions.items.len +| before.parameters.len)) {
                @memset(self.same, false);
                return;
            }
            if (before.invalidates != entry.invalidates or before.owned_result_bytes != entry.owned_result_bytes or before.parameters.len != entry.parameters.len) {
                same.* = false;
                continue;
            }
            for (before.parameters, entry.parameters) |left, right| {
                if (!std.meta.eql(left, right)) same.* = false;
            }
            for (entry.source.instructions.items) |inst| switch (inst.op) {
                .call_import => if (!self.importSame(inst.operand, inst.operand)) {
                    same.* = false;
                },
                .call_indirect => if (!self.signatureSame(inst.operand, inst.operand)) {
                    same.* = false;
                },
                .global_get, .global_set => if (!self.globalSame(inst.operand, inst.operand)) {
                    same.* = false;
                },
                else => {},
            };
        }
        var changed = false;
        for (self.same) |same| if (!same) {
            changed = true;
            break;
        };
        if (!changed) return;
        const Edge = struct { caller: u32, next: u32 };
        const absent = std.math.maxInt(u32);
        const heads = try self.allocator.alloc(u32, self.same.len);
        defer self.allocator.free(heads);
        @memset(heads, absent);
        var edges: std.ArrayList(Edge) = .empty;
        defer edges.deinit(self.allocator);
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(self.allocator);
        for (self.current.entries.items, 0..) |entry, id| {
            if (!self.same[id]) continue;
            for (entry.source.instructions.items) |inst| {
                if (inst.op != .call and !inst.table_reference) continue;
                if (!walk.spend(1)) {
                    @memset(self.same, false);
                    return;
                }
                if (inst.operand >= self.same.len) {
                    self.same[id] = false;
                    break;
                }
                const next: u32 = @intCast(edges.items.len);
                try edges.append(self.allocator, .{ .caller = @intCast(id), .next = heads[inst.operand] });
                heads[inst.operand] = next;
            }
        }
        for (self.same, 0..) |same, id| if (!same) try pending.append(self.allocator, @intCast(id));
        while (pending.pop()) |callee| {
            var edge = heads[callee];
            while (edge != absent) {
                if (!walk.spend(1)) {
                    @memset(self.same, false);
                    return;
                }
                const item = edges.items[edge];
                if (self.same[item.caller]) {
                    self.same[item.caller] = false;
                    try pending.append(self.allocator, item.caller);
                }
                edge = item.next;
            }
        }
    }
    fn findRelocations(self: *Matcher) A.Error!void {
        if (!self.old.queries_complete or self.old.queries.limits.lookup_work == 0) return;
        const relocation = @import("runtime_body_relocation.zig");
        var walk: relocation.Walk = .{};
        const budget = walk.remaining;
        defer {
            self.work = budget - walk.remaining;
            self.budget_exhausted = @intFromBool(walk.remaining == 0);
            walk.deinit(self.allocator);
        }
        try self.preparePositions(&walk);
        var missing = false;
        for (self.prior_ids, 0..) |*prior, id| {
            self.candidates += 1;
            if (self.matchesPosition(&walk, id)) prior.* = id else missing = true;
        }
        if (!missing) return;
        for (self.current.entries.items, self.prior_ids, 0..) |entry, *prior, id| {
            if (prior.* != null) continue;
            if (walk.remaining == 0) return;
            var candidates = self.old.queries.candidates(relocation.hash(entry.source), .newest_first);
            candidates.remaining = @min(candidates.remaining, 64);
            while (candidates.next()) |position| {
                if (walk.remaining == 0) return;
                self.candidates += 1;
                const record = self.old.queries.records.items[position];
                if (record.key.tier != self.current.tier) continue;
                if (!self.summarySame(record.dependencies, entry)) continue;
                const before = record.value.function;
                if (!try self.graphSame(&walk, before, id)) continue;
                if (self.old.output(before)) |body| {
                    var relocated = try cloneBody(self.allocator, body);
                    var owns = true;
                    defer if (owns) relocated.deinit(self.allocator);
                    if (!try self.outputReferences(&walk, body)) continue;
                    for (relocated.instructions.items) |*inst| {
                        if (relocation.referenceKind(inst.*)) |kind| inst.operand = walk.get(kind, inst.operand).?;
                    }
                    self.relocated[id] = relocated;
                    owns = false;
                }
                prior.* = before;
                break;
            }
        }
    }
};

fn cloneBody(a: A, source: ir.Body) A.Error!ir.Body {
    const locals = try a.dupe(ir.ValueType, source.locals.items);
    errdefer a.free(locals);
    const instructions = try a.dupe(ir.Instruction, source.instructions.items);
    return .{ .locals = .fromOwnedSlice(locals), .instructions = .fromOwnedSlice(instructions) };
}
fn cloneFunction(a: A, source: ir.Function) A.Error!ir.Function {
    const parameters = try a.dupe(ir.ValueType, source.parameters);
    errdefer a.free(parameters);
    const body = try cloneBody(a, .{ .locals = source.locals, .instructions = source.instructions });
    return .{ .parameters = parameters, .result = source.result, .result_role = source.result_role, .entry = source.entry, .signature = source.signature, .parameter_roles = source.parameter_roles, .provider_parameter = source.provider_parameter, .callable_layout = source.callable_layout, .annotations = source.annotations, .locals = body.locals, .instructions = body.instructions };
}
