//! Private serial ownership for immutable dependency snapshots. Portable
//! payloads keep their original representation. Each module is retained
//! independently; a new snapshot never retains an entire previous revision.
//! Payloads and their views must remain immutable until the last release.
const std = @import("std");
const D = @import("frozen_dependency.zig");
const format = @import("dependency_format.zig");
const Allocator = std.mem.Allocator;

const Module = struct {
    allocator: Allocator,
    references: usize = 1,
    value: D.Module,

    fn release(self: *Module) void {
        std.debug.assert(self.references != 0);
        self.references -= 1;
        if (self.references != 0) return;
        const a = self.allocator;
        format.deinit(a, &self.value);
        a.destroy(self);
    }
};

pub const Stats = struct {
    shared_modules: usize = 0,
    fresh_modules: usize = 0,
    core_checked: usize = 0,
    core_reused: usize = 0,
    interface_checked: usize = 0,
    interface_reused: usize = 0,
};

pub const Snapshot = struct {
    allocator: Allocator,
    value: D.FrozenDependency,
    modules: []*Module,
    initialized: usize = 0,
    /// Set only after the complete dependency validator succeeds for this
    /// immutable snapshot. It grants no source or semantic cache admission.
    validated: bool = false,

    /// Takes ownership of symbols only on success. Module slots are filled by
    /// appendOwned/appendShared; teardown also accepts a partial construction.
    pub fn create(a: Allocator, symbols: []D.Symbol, count: usize) Allocator.Error!*Snapshot {
        const self = try a.create(Snapshot);
        errdefer a.destroy(self);
        const views = try a.alloc(D.Module, count);
        errdefer a.free(views);
        const modules = try a.alloc(*Module, count);
        self.* = .{ .allocator = a, .value = .{ .symbols = symbols, .modules = views }, .modules = modules };
        return self;
    }

    /// Moves an already owned payload after all bookkeeping allocations
    /// succeed. Failure leaves the caller's ownership and payload unchanged.
    pub fn adopt(a: Allocator, value: D.FrozenDependency) Allocator.Error!*Snapshot {
        const self = try a.create(Snapshot);
        errdefer a.destroy(self);
        const modules = try a.alloc(*Module, value.modules.len);
        errdefer a.free(modules);
        var initialized: usize = 0;
        errdefer for (modules[0..initialized]) |module| a.destroy(module);
        for (value.modules, modules) |item, *module| {
            const owner = try a.create(Module);
            owner.* = .{ .allocator = a, .value = item };
            module.* = owner;
            initialized += 1;
        }
        self.* = .{ .allocator = a, .value = value, .modules = modules, .initialized = modules.len };
        return self;
    }

    /// Consumes the module, including on allocation failure.
    pub fn appendOwned(self: *Snapshot, value: D.Module) Allocator.Error!void {
        var moved = value;
        errdefer format.deinit(self.allocator, &moved);
        const module = try self.allocator.create(Module);
        module.* = .{ .allocator = self.allocator, .value = value };
        self.append(module);
    }

    pub fn appendShared(self: *Snapshot, previous: *const Snapshot, index: usize) error{DependencyLimit}!void {
        std.debug.assert(index < previous.initialized);
        const module = previous.modules[index];
        if (module.references == std.math.maxInt(usize)) return error.DependencyLimit;
        module.references += 1;
        self.append(module);
    }

    fn append(self: *Snapshot, module: *Module) void {
        std.debug.assert(!self.validated and self.initialized < self.modules.len);
        self.modules[self.initialized] = module;
        self.value.modules[self.initialized] = module.value;
        self.initialized += 1;
    }

    pub fn shares(self: *const Snapshot, previous: *const Snapshot, index: usize) bool {
        return index < self.initialized and index < previous.initialized and self.modules[index] == previous.modules[index];
    }

    pub fn references(self: *const Snapshot, index: usize) usize {
        std.debug.assert(index < self.initialized);
        return self.modules[index].references;
    }

    pub fn deinit(self: *Snapshot) void {
        const a = self.allocator;
        for (self.modules[0..self.initialized]) |module| module.release();
        a.free(self.modules);
        a.free(self.value.modules);
        for (self.value.symbols) |symbol| a.free(symbol.text);
        a.free(self.value.symbols);
        a.destroy(self);
    }
};

/// A retained candidate either owns a portable payload directly or owns a
/// snapshot whose value is its immutable view. Exactly one cleanup path runs.
pub const Seed = struct {
    value: D.FrozenDependency,
    snapshot: ?*Snapshot = null,

    pub fn deinit(self: *Seed, a: Allocator) void {
        if (self.snapshot) |snapshot| snapshot.deinit() else format.deinit(a, &self.value);
        self.* = undefined;
    }
};
