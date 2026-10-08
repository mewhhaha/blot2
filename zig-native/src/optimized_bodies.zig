//! Immutable optimizer inputs and results owned by one successful revision.
//! Exact input equality authorizes reuse; no source hash or semantic admission
//! can substitute for the call/body/ownership facts consumed by these passes.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const lifetimes = @import("wasm_lifetimes.zig");
const A = std.mem.Allocator;

pub const Stats = struct {
    tier: @import("compilation_tier.zig").Tier = .optimized,
    functions: usize = 0,
    optimized: usize = 0,
    reused: usize = 0,
    shared: usize = 0,
    workers: usize = 1,
    parallel_jobs: usize = 0,
    retained_bytes: usize = 0,
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

pub const Capture = struct {
    allocator: A,
    tier: @import("compilation_tier.zig").Tier = .optimized,
    entries: std.ArrayList(Entry) = .empty,
    signatures: std.ArrayList(ir.Signature) = .empty,
    imports: std.ArrayList(u32) = .empty,
    globals: std.ArrayList(ir.ValueType) = .empty,
    arena: ?wasm.Arena = null,

    pub fn deinit(self: *Capture) void {
        for (self.entries.items) |*entry| entry.deinit(self.allocator);
        for (self.signatures.items) |signature| self.allocator.free(signature.parameters);
        self.entries.deinit(self.allocator);
        self.signatures.deinit(self.allocator);
        self.imports.deinit(self.allocator);
        self.globals.deinit(self.allocator);
        self.* = .{ .allocator = self.allocator };
    }

    /// The caller publishes only after complete assembly. Failed candidates
    /// release this owner without modifying the previous revision's capture.
    pub fn recordInputs(self: *Capture, module: *const wasm.Module, summaries: *const lifetimes.Summaries) A.Error!void {
        std.debug.assert(self.entries.items.len == 0 and self.signatures.items.len == 0);
        self.arena = module.arena;
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
        for (module.imports.items) |item| self.imports.appendAssumeCapacity(item.signature);
        try self.globals.ensureTotalCapacity(self.allocator, module.globals.items.len);
        for (module.globals.items) |global| self.globals.appendAssumeCapacity(global.scalar.machine());
    }

    pub fn recordOutput(self: *Capture, id: usize, body_result: ?ir.Body) A.Error!void {
        std.debug.assert(self.entries.items[id].output == null);
        self.entries.items[id].output = if (body_result) |body| try cloneBody(self.allocator, body) else null;
        self.entries.items[id].output_ready = true;
    }
    pub fn output(self: *const Capture, id: usize) ?ir.Body {
        return self.entries.items[id].output;
    }
    pub fn bytes(self: *const Capture) usize {
        var count = self.entries.items.len * @sizeOf(Entry) + self.signatures.items.len * @sizeOf(ir.Signature) + self.imports.items.len * 4 + self.globals.items.len;
        for (self.entries.items) |entry| {
            count += entry.source.parameters.len + entry.source.locals.items.len + entry.source.instructions.items.len * @sizeOf(ir.Instruction) + entry.parameters.len * @sizeOf(lifetimes.Parameter);
            if (entry.output) |body| count += body.locals.items.len + body.instructions.items.len * @sizeOf(ir.Instruction);
        }
        for (self.signatures.items) |signature| count += signature.parameters.len;
        return count;
    }
};

pub const Matcher = struct {
    allocator: A,
    old: *const Capture,
    current: *const Capture,
    same: []bool,
    arena_same: bool,
    relocated: []?ir.Body,
    prior_ids: []?usize,

    pub fn init(a: A, old: *const Capture, current: *const Capture) A.Error!Matcher {
        const same = try a.alloc(bool, current.entries.items.len);
        errdefer a.free(same);
        for (same, current.entries.items, 0..) |*match, entry, id| match.* = id < old.entries.items.len and @import("runtime_function_key.zig").equal(old.entries.items[id].source, entry.source);
        const relocated = try a.alloc(?ir.Body, current.entries.items.len);
        errdefer a.free(relocated);
        @memset(relocated, null);
        const prior_ids = try a.alloc(?usize, current.entries.items.len);
        @memset(prior_ids, null);
        var self: Matcher = .{ .allocator = a, .old = old, .current = current, .same = same, .arena_same = old.tier == current.tier and std.meta.eql(old.arena, current.arena), .relocated = relocated, .prior_ids = prior_ids };
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
    fn signatureSame(self: *const Matcher, before: u32, after: u32) bool {
        if (before >= self.old.signatures.items.len or after >= self.current.signatures.items.len) return false;
        const left = self.old.signatures.items[before];
        const right = self.current.signatures.items[after];
        return left.result == right.result and std.mem.eql(ir.ValueType, left.parameters, right.parameters);
    }
    fn matchesPosition(self: *const Matcher, id: usize) bool {
        if (!self.arena_same or !self.same[id] or !self.old.entries.items[id].output_ready) return false;
        for (self.current.entries.items[id].source.instructions.items) |inst| switch (inst.op) {
            .call => {
                // Vectorization reads the callee body. Lifetime analysis reads
                // its completed borrow/fresh-result summary, including facts
                // derived transitively from otherwise unchanged callees.
                if (inst.operand >= self.same.len or !self.same[inst.operand]) return false;
                const before = self.old.entries.items[inst.operand];
                const after = self.current.entries.items[inst.operand];
                if (before.invalidates != after.invalidates or before.owned_result_bytes != after.owned_result_bytes or before.parameters.len != after.parameters.len) return false;
                for (before.parameters, after.parameters) |left, right| if (!std.meta.eql(left, right)) return false;
            },
            .call_import => {
                if (inst.operand >= self.old.imports.items.len or inst.operand >= self.current.imports.items.len or !self.signatureSame(self.old.imports.items[inst.operand], self.current.imports.items[inst.operand])) return false;
            },
            .call_indirect => if (!self.signatureSame(inst.operand, inst.operand)) return false,
            .global_get, .global_set => if (inst.operand >= self.old.globals.items.len or inst.operand >= self.current.globals.items.len or self.old.globals.items[inst.operand] != self.current.globals.items[inst.operand]) return false,
            else => {},
        };
        return true;
    }
    pub fn matches(self: *const Matcher, id: usize) bool {
        return self.prior_ids[id] != null;
    }
    pub fn output(self: *const Matcher, id: usize) ?ir.Body {
        return self.relocated[id] orelse self.old.output(self.prior_ids[id].?);
    }
    fn externalFactsSame(self: *const Matcher, function: ir.Function) bool {
        for (function.instructions.items) |inst| switch (inst.op) {
            .call_import => if (inst.operand >= self.old.imports.items.len or inst.operand >= self.current.imports.items.len or !self.signatureSame(self.old.imports.items[inst.operand], self.current.imports.items[inst.operand])) return false,
            .call_indirect => if (!self.signatureSame(inst.operand, inst.operand)) return false,
            .global_get, .global_set => if (inst.operand >= self.old.globals.items.len or inst.operand >= self.current.globals.items.len or self.old.globals.items[inst.operand] != self.current.globals.items[inst.operand]) return false,
            else => {},
        };
        return true;
    }
    fn graphSame(self: *const Matcher, walk: *@import("runtime_body_relocation.zig").Walk, before: usize, after: usize) A.Error!bool {
        const relocation = @import("runtime_body_relocation.zig");
        walk.clear();
        if (!try walk.add(self.allocator, @intCast(before), @intCast(after))) return false;
        while (walk.pending.pop()) |pair| {
            if (pair.before >= self.old.entries.items.len or pair.after >= self.current.entries.items.len) return false;
            const left = self.old.entries.items[pair.before];
            const right = self.current.entries.items[pair.after];
            if (!relocation.equalLocal(left.source, right.source) or !self.externalFactsSame(right.source)) return false;
            if (left.invalidates != right.invalidates or left.owned_result_bytes != right.owned_result_bytes or left.parameters.len != right.parameters.len) return false;
            for (left.parameters, right.parameters) |l, r| if (!std.meta.eql(l, r)) return false;
            for (left.source.instructions.items, right.source.instructions.items) |l, r| if (l.op == .call) {
                if (!try walk.add(self.allocator, l.operand, r.operand)) return false;
            };
        }
        return true;
    }
    fn findRelocations(self: *Matcher) A.Error!void {
        const relocation = @import("runtime_body_relocation.zig");
        var missing = false;
        for (self.prior_ids, 0..) |*prior, id| {
            if (self.matchesPosition(id)) prior.* = id else missing = true;
        }
        if (!missing) return;
        var buckets: std.AutoHashMapUnmanaged(u64, usize) = .empty;
        defer buckets.deinit(self.allocator);
        const next = try self.allocator.alloc(?usize, self.old.entries.items.len);
        defer self.allocator.free(next);
        for (self.old.entries.items, 0..) |entry, id| {
            next[id] = null;
            if (!entry.output_ready) continue;
            const bucket = try buckets.getOrPut(self.allocator, relocation.hash(entry.source));
            next[id] = if (bucket.found_existing) bucket.value_ptr.* else null;
            bucket.value_ptr.* = id;
        }
        var walk: relocation.Walk = .{};
        defer walk.deinit(self.allocator);
        for (self.current.entries.items, self.prior_ids, 0..) |entry, *prior, id| {
            if (prior.* != null) continue;
            var candidate = buckets.get(relocation.hash(entry.source));
            var budget: usize = 64;
            while (candidate) |before| {
                if (budget == 0) break;
                budget -= 1;
                candidate = next[before];
                if (!try self.graphSame(&walk, before, id)) continue;
                if (self.old.output(before)) |body| {
                    var relocated = try cloneBody(self.allocator, body);
                    var owns = true;
                    defer if (owns) relocated.deinit(self.allocator);
                    var valid = true;
                    for (relocated.instructions.items) |*inst| if (inst.op == .call) {
                        if (walk.targets.get(inst.operand)) |target| {
                            inst.operand = target;
                        } else if (self.current.arena == null or inst.operand != self.current.arena.?.recycle) {
                            // Cleanup may introduce recycle; every other direct
                            // call must be justified by the checked body graph.
                            valid = false;
                            break;
                        }
                    };
                    if (!valid) continue;
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
    return .{ .parameters = parameters, .result = source.result, .signature = source.signature, .locals = body.locals, .instructions = body.instructions };
}
