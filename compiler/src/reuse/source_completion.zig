//! Process-local source authority, minted only by factories which themselves
//! check and lower source. It is not portable Core evidence. The immutable
//! snapshot and Prepared owners must remain pinned throughout emission.
const std = @import("std");
const core = @import("../check/core.zig");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const partial = @import("partial_dependency.zig");
const closure = @import("dependency_closure.zig");
const retained = @import("retained_dependency.zig");
const D = @import("frozen_dependency.zig");
const identity = @import("../backend/runtime_identity.zig");
const Allocator = std.mem.Allocator;

const PrefixState = struct {
    allocator: Allocator,
    graph: D.FrozenDependency,
    validation: *const @import("completed_core_validation.zig").Receipt,
};

/// No public constructor or upgrade from a validation-only receipt exists.
pub const Prefix = opaque {
    pub fn deinit(self: *Prefix) void {
        const state: *PrefixState = @ptrCast(@alignCast(self));
        state.allocator.destroy(state);
    }

    fn owns(self: *const Prefix, graph: *const D.FrozenDependency) bool {
        const state: *const PrefixState = @ptrCast(@alignCast(self));
        return sameDescriptors(state.graph, graph.*);
    }

    fn prefix(self: *const Prefix, units: []const core.Module, entry: u32, names: identity.View) usize {
        const state: *const PrefixState = @ptrCast(@alignCast(self));
        const count = state.graph.modules.len;
        if (count == 0 or state.validation.borrow(&state.graph).prefix(units, entry, names) != count) return 0;
        for (state.graph.modules, 1..) |module, ordinal| {
            const path = names.owner(@intCast(ordinal)) orelse return 0;
            if (!std.mem.eql(u8, path, module.identity.normalized_path)) return 0;
        }
        return count;
    }
};

const EntryState = struct {
    allocator: Allocator,
    prefix: *const Prefix,
    module: core.Module,
    names: identity.Metadata,
};

/// Belongs to exactly one freshly checked/lowered entry, with no copied entry
/// or caller-supplied CheckedProject/Prepared on its construction path.
pub const Entry = opaque {
    pub fn deinit(self: *Entry) void {
        const state: *EntryState = @ptrCast(@alignCast(self));
        const a = state.allocator;
        state.names.deinit(a);
        a.destroy(state);
    }

    fn matches(self: *const Entry, units: []const core.Module, entry: u32, names: identity.View) bool {
        const state: *const EntryState = @ptrCast(@alignCast(self));
        if (units.len == 0 or entry != units.len or state.prefix.prefix(units, entry, names) != units.len - 1) return false;
        if (!sameDescriptors(state.module, units[entry - 1])) return false;
        const saved = state.names.view();
        if (!std.mem.eql(u8, saved.bytes, names.bytes) or saved.symbols.len != names.symbols.len or saved.owners.len != names.owners.len) return false;
        for (saved.symbols, names.symbols) |left, right| if (!std.meta.eql(left, right)) return false;
        for (saved.owners, names.owners) |left, right| if (!std.meta.eql(left, right)) return false;
        return true;
    }
};

pub const Borrow = struct {
    prefix: ?*const Prefix = null,
    entry: ?*const Entry = null,

    /// Exact live immutable context only. The caller still validates all Core
    /// bounds and semantics, and every runtime call's types, rows and owners.
    pub fn covered(self: Borrow, units: []const core.Module, entry: u32, names: identity.View) usize {
        if (self.entry) |receipt| if (receipt.matches(units, entry, names)) return units.len;
        if (self.prefix) |receipt| return receipt.prefix(units, entry, names);
        return 0;
    }
};

pub const Population = struct {
    checked: checker.CheckedProject,
    snapshot: ?*retained.Snapshot = null,
};

/// Closed fresh-source factory. Arbitrary precomputed checks, decoded graphs
/// and previous Core offers cannot mint source authority. A lowering decline
/// preserves the successful checker owner for the ordinary fallback lane.
pub fn checkAndFreezeDependencies(a: Allocator, source: *project.Project, previous: ?@import("entry_frontend_cutoff.zig").Previous) !Population {
    var checked = try checker.checkProjectDeferringEntryToFirstDiagnostic(a, source, previous);
    errdefer checked.deinit(a);
    if (checked.deferred_entry == null or checked.diagnostics.len != 0) return .{ .checked = checked };
    const owner = closure.freezeDeferringEntrySnapshot(a, source, &checked) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{ .checked = checked };
    };
    errdefer owner.deinit();
    if (previous == null and source.compiled_modules.len == 0) {
        const state = try a.create(PrefixState);
        state.* = .{ .allocator = a, .graph = owner.value, .validation = owner.core_validation.? };
        owner.source_completion = @ptrCast(state);
    }
    return .{ .checked = checked, .snapshot = owner };
}

/// Runs the actual consumer checker and lowerer before exposing Prepared.
/// The seed remains pinned by its caller, just as with ordinary partial prep.
pub fn prepareEntry(a: Allocator, io: std.Io, entry_path: []const u8, output_identity: ?[]const u8, options: project.Options, owner: *const retained.Snapshot, inputs: ?project.InputProvider, previous: ?partial.EntryPrevious) !partial.Preparation {
    var prepared = try partial.prepareReadOnlyWithBodies(a, io, entry_path, output_identity, options, &owner.value, inputs, previous);
    errdefer prepared.deinit(a);
    if (prepared != .ready or previous != null) return prepared;
    const prefix = owner.source_completion orelse return prepared;
    if (!prefix.owns(&owner.value)) return prepared;
    const value = &prepared.ready;
    if (value.source_mode or value.units.len != owner.value.modules.len + 1 or value.entry != value.units.len or value.cached != owner.value.modules.len) return prepared;
    if (prefix.prefix(value.units, value.entry, value.identity.view()) != owner.value.modules.len) return prepared;
    const state = try a.create(EntryState);
    errdefer a.destroy(state);
    const names = try copyIdentity(a, value.identity.view());
    state.* = .{ .allocator = a, .prefix = prefix, .module = value.units[value.entry - 1], .names = names };
    value.source_completion = @ptrCast(state);
    return prepared;
}

fn copyIdentity(a: Allocator, names: identity.View) Allocator.Error!identity.Metadata {
    const bytes = try a.dupe(u8, names.bytes);
    errdefer a.free(bytes);
    const symbols = try a.dupe(@TypeOf(names.symbols[0]), names.symbols);
    errdefer a.free(symbols);
    const owners = try a.dupe(@TypeOf(names.owners[0]), names.owners);
    return .{ .bytes = bytes, .symbols = symbols, .owners = owners };
}

fn sameDescriptors(before: anytype, after: @TypeOf(before)) bool {
    @setEvalBranchQuota(20000);
    switch (@typeInfo(@TypeOf(before))) {
        .pointer => |pointer| {
            if (comptime pointer.size != .slice) @compileError("immutable descriptors must own slices");
            return before.ptr == after.ptr and before.len == after.len;
        },
        .@"struct" => |structure| {
            inline for (structure.field_names) |name| if (!sameDescriptors(@field(before, name), @field(after, name))) return false;
            return true;
        },
        else => return std.meta.eql(before, after),
    }
}
