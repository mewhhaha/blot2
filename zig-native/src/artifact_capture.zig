//! Movable owned backend facts and emission. Immutable Core is an explicit
//! caller pin; it must outlive this capture and every candidate using it.
const metadata = @import("code_artifacts.zig");
const emitter = @import("artifact_emitter.zig");
const std = @import("std");
const core = @import("core.zig");
const identity = @import("runtime_identity.zig");
const types = @import("types.zig");
const equal = @import("structural.zig").equal;

pub const Capture = struct {
    metadata: metadata.Context,
    emission: emitter.Recorder,
    cached_units: usize = 0,
    optimized: ?@import("optimized_bodies.zig").Capture = null,
    executable_queries: @import("executable_query.zig").FragmentTable = .{},
    executable_queries_complete: bool = false,

    /// Called only after owned pools, sealed emission and complete job/function
    /// pairing have passed validation. Graph ordinals remain under this lease.
    pub fn sealExecutableQueries(self: *Capture) std.mem.Allocator.Error!void {
        const query = @import("executable_query.zig");
        const a = self.metadata.allocator;
        std.debug.assert(self.executable_queries.records.items.len == 0 and !self.executable_queries_complete);
        const pools = &(self.metadata.pools orelse return);
        for (pools.functions) |function| {
            if (function.request != .named and function.request != .closure) continue;
            const owner = self.emission.functions[function.function].owner;
            const job = self.metadata.jobs.items[owner - 1];
            std.debug.assert(job.state == .complete and job.function.? == function.function);
            if (!job.reusable) continue;
            const bytes_needed = query.dependencyBytes(core.BindingRef, job.inline_bodies.items.len, metadata.StaticRead, job.static_reads.items.len) orelse {
                self.executable_queries.saturated +|= 1;
                return;
            };
            if (self.executable_queries.records.items.len >= self.executable_queries.limits.records or bytes_needed > self.executable_queries.limits.owned_bytes -| self.executable_queries.owned_bytes) {
                self.executable_queries.saturated +|= 1;
                return;
            }
            var builder = query.FragmentTable.begin(a, .{ .request = function.request });
            defer builder.abort();
            const bodies = try a.dupe(core.BindingRef, job.inline_bodies.items);
            var transferred = false;
            defer if (!transferred) a.free(bodies);
            builder.read(.{ .inline_bodies = bodies, .static_reads = try a.dupe(metadata.StaticRead, job.static_reads.items), .replay_job = owner, .reusable = job.reusable });
            transferred = true;
            builder.stage(.{ .function = function.function, .job = owner });
            var candidate = builder.complete().?;
            defer candidate.abort();
            const prepared = try self.executable_queries.prepare(a, &candidate) orelse return;
            _ = self.executable_queries.publish(prepared, &candidate);
        }
        self.executable_queries_complete = true;
    }

    /// Selection is globally guarded before any retained lookup. This first
    /// admission rejects fresh associated implementations and structural
    /// catalog movement. Unchanged imported methods survive a body edit.
    pub fn selectionStable(self: *const Capture, units: []const core.Module, names: ?identity.View, cached: usize) bool {
        const pools = &(self.metadata.pools orelse return false);
        const old_names = if (pools.identity) |*value| value.view() else return false;
        const current_names = names orelse return false;
        if (cached != self.cached_units or cached > units.len or units.len != pools.modules.len) return false;
        for (pools.modules, units, 1..) |pin, *unit, index| {
            // A retained prefix keeps its explicit canonical producer owner.
            const path = current_names.owner(unit.unit) orelse return false;
            if (pin.unit != unit.unit or !std.mem.eql(u8, pin.canonical_path, path)) return false;
            if (index <= cached) continue;
            const previous = pin.module;
            // Selection is first-match: preserve order and duplicate entries.
            // IDs alone do not establish the spelling or producer behind a
            // catalog. Producer paths were checked above; State additionally
            // requires exact imported Core equality before enabling lookup.
            if (!equal(previous.associated, unit.associated)) return false;
            for (previous.associated) |method| {
                if (method.member != 0) {
                    const before = old_names.symbol(method.member) orelse return false;
                    const after = current_names.symbol(method.member) orelse return false;
                    if (!std.mem.eql(u8, before, after)) return false;
                }
                if (method.identity.unit == 0) {
                    switch (method.identity.decl) {
                        types.unit, types.boolean, types.u32_type, types.f32_type, std.math.maxInt(u32), std.math.maxInt(u32) - 1 => {},
                        else => return false,
                    }
                } else if (method.identity.unit > cached) return false;
                // Local targets and aliases are intentionally conservative:
                // only a body in an unchanged imported producer is admitted.
                if (method.target.unit == 0 or method.target.unit > cached) return false;
                const producer = &units[method.target.unit - 1];
                if (method.target.binding == 0 or method.target.binding >= producer.bindings.len or producer.bindings[method.target.binding].kind == .external or producer.body(method.target.binding) == null) return false;
            }
            if (!equal(previous.types, unit.types) or !equal(previous.nominals, unit.nominals) or !equal(previous.constructors, unit.constructors)) return false;
            // Physical constructor lists are distinct from semantic records.
            for (previous.nominals, unit.nominals) |old, new| {
                if (!equal(previous.extra[old.constructors.start..][0..old.constructors.len], unit.extra[new.constructors.start..][0..new.constructors.len])) return false;
            }
            // Frozen catalog fields include Symbol ordinals; confirm the
            // spelling behind each surviving role in the same owner as well.
            for (previous.types.nodes) |node| if (node.tag == .record) {
                for (0..node.b) |field| {
                    const symbol = previous.types.extra[node.a + field * 2];
                    const before = old_names.symbol(symbol) orelse return false;
                    const after = current_names.symbol(symbol) orelse return false;
                    if (!std.mem.eql(u8, before, after)) return false;
                }
            };
        }
        return true;
    }

    pub fn deinit(self: *Capture) void {
        self.executable_queries.deinit(self.metadata.allocator);
        if (self.optimized) |*optimized| optimized.deinit();
        self.emission.deinit();
        self.metadata.deinit();
        self.* = undefined;
    }
};
