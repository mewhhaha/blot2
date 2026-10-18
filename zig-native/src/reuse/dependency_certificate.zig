//! A successful frozen-Core/dependency validation, owned by one published
//! revision. Exact namespace and graph images, producer paths and every foreign
//! bound travel together. This record never authorizes semantic or code reuse.
const std = @import("std");
const validation = @import("../check/frozen_core_validation.zig");
const identity = @import("../backend/runtime_identity.zig");
const Image = @import("validation_image.zig").Image;
const queries = @import("semantic_query_table.zig");
const Lease = @import("../eval/pool_leases.zig").Lease;
const A = std.mem.Allocator;

const Module = struct {
    unit: u32,
    path: []u8,
    stamp: [32]u8,
    graph: Image,
    /// Owns nonempty `graph.bytes`. Consecutive certificates share the image
    /// of an exactly unchanged unit instead of copying it.
    lease: ?*Lease,
    fn deinit(self: *Module, a: A) void {
        a.free(self.path);
        if (self.lease) |lease| lease.release() else self.graph.deinit(a);
    }
};
fn leased(a: A, image: Image) A.Error!?*Lease {
    if (image.bytes.len == 0) return null;
    const lease = a.create(Lease) catch |err| {
        var owned = image;
        owned.deinit(a);
        return err;
    };
    lease.* = .{ .allocator = a, .memory = image.bytes, .alignment = .@"1" };
    return lease;
}
const Dependencies = struct {
    namespace: Image,
    modules: []Module,
    pub fn deinit(self: *Dependencies, a: A) void {
        self.namespace.deinit(a);
        for (self.modules) |*module| module.deinit(a);
        a.free(self.modules);
    }
};
const Checked = struct {
    pub fn deinit(_: *Checked, _: A) void {}
};
pub const Record = queries.OwnedRecord(.source_validation, validation.ContextImage, Dependencies, Checked);
pub const Stats = struct {
    dependency_validations: usize = 0,
    reused_dependency_validations: usize = 0,
    retained: queries.Storage = .{},
    /// Module images copied from the previous certificate, not re-serialized.
    reused_images: usize = 0,
    pub fn observe(self: *Stats, gate: anytype) void {
        self.dependency_validations += gate.dependency_validations;
        self.reused_dependency_validations += gate.reused_dependency_validations;
    }
};

/// Images cover every module of the program, so they get their own budget
/// rather than one query table's. A 60-file game's images are about 16.4 MB;
/// over budget, the certificate is dropped and every later edit revalidates.
pub const owned_bytes: usize = 64 * 1024 * 1024;

pub const Certificate = struct {
    record: Record,
    reused_images: usize = 0,

    /// Called only after authoritative graph/dependency validation. A single
    /// immutable owner has one certificate and needs no bucket index. Optional
    /// oversized images decline retention; subsequent validation runs normally.
    pub fn capture(a: A, context: validation.Context, pins: anytype, names: identity.View) A.Error!?Certificate {
        return captureWithBudget(a, context, pins, names, owned_bytes);
    }
    /// `reusable[i]` must certify that the previous certificate's image of unit
    /// i exactly equals the current module's image; the unit, producer path
    /// and stamp are rechecked before its bytes are copied.
    pub fn captureReusing(a: A, context: validation.Context, pins: anytype, names: identity.View, previous: ?*const Certificate, reusable: []const bool) A.Error!?Certificate {
        return captureReusingWithBudget(a, context, pins, names, previous, reusable, owned_bytes);
    }
    pub fn captureWithBudget(a: A, context: validation.Context, pins: anytype, names: identity.View, budget: usize) A.Error!?Certificate {
        return captureReusingWithBudget(a, context, pins, names, null, &.{}, budget);
    }
    fn reusedImage(previous: ?*const Certificate, reusable: []const bool, ordinal: usize, pin: anytype) ?*Lease {
        const old = previous orelse return null;
        if (ordinal >= reusable.len or !reusable[ordinal] or ordinal >= old.record.dependencies.modules.len) return null;
        const module = old.record.dependencies.modules[ordinal];
        if (module.unit != pin.unit or !std.mem.eql(u8, module.path, pin.canonical_path) or !std.mem.eql(u8, &module.stamp, &pin.stamp)) return null;
        return module.lease;
    }
    pub fn captureReusingWithBudget(a: A, context: validation.Context, pins: anytype, names: identity.View, previous: ?*const Certificate, reusable: []const bool, budget: usize) A.Error!?Certificate {
        if (pins.len == 0 or pins.len != context.units.len or names.owners.len != pins.len) return null;
        var remaining = budget;
        if (pins.len > remaining / @sizeOf(Module)) return null;
        remaining -= pins.len * @sizeOf(Module);
        if (context.units.len > remaining / @sizeOf(@typeInfo(@FieldType(validation.ContextImage, "owners")).pointer.child)) return null;
        remaining -= context.units.len * @sizeOf(@typeInfo(@FieldType(validation.ContextImage, "owners")).pointer.child);
        for (context.units) |module| {
            if (module.nominals.len > remaining / @sizeOf(validation.NominalFact)) return null;
            remaining -= module.nominals.len * @sizeOf(validation.NominalFact);
        }
        var image = try validation.ContextImage.capture(a, context, context.units);
        var transferred = false;
        defer if (!transferred) image.deinit(a);
        var namespace = try Image.capture(a, names, &remaining) orelse return null;
        defer if (!transferred) namespace.deinit(a);
        const modules = try a.alloc(Module, pins.len);
        var initialized: usize = 0;
        var reused: usize = 0;
        defer if (!transferred) {
            for (modules[0..initialized]) |*module| module.deinit(a);
            a.free(modules);
        };
        for (modules, pins, context.units, 0..) |*module, pin, unit, ordinal| {
            const owner = names.owner(@intCast(ordinal + 1)) orelse return null;
            if (pin.module != unit or pin.unit != ordinal + 1 or !std.mem.eql(u8, pin.canonical_path, owner)) return null;
            if (pin.canonical_path.len > remaining) return null;
            remaining -= pin.canonical_path.len;
            const path = try a.dupe(u8, pin.canonical_path);
            var owned_path = true;
            defer if (owned_path) a.free(path);
            var lease: ?*Lease = null;
            if (reusedImage(previous, reusable, ordinal, pin)) |shared| {
                if (shared.memory.len > remaining) return null;
                remaining -= shared.memory.len;
                reused += 1;
                lease = shared.retain();
            } else {
                const captured = try Image.capture(a, unit.*, &remaining) orelse return null;
                lease = try leased(a, captured);
            }
            module.* = .{ .unit = pin.unit, .path = path, .stamp = pin.stamp, .graph = .{ .bytes = if (lease) |shared| shared.memory else &.{} }, .lease = lease };
            owned_path = false;
            initialized += 1;
        }
        transferred = true;
        return .{ .record = .{ .key = image, .dependencies = .{ .namespace = namespace, .modules = modules }, .value = .{} }, .reused_images = reused };
    }

    pub fn deinit(self: *Certificate, a: A) void {
        self.record.deinit(a);
        self.* = undefined;
    }
    pub fn storage(self: *const Certificate) queries.Storage {
        const dependencies = self.record.dependencies;
        var bytes = dependencies.namespace.bytes.len + dependencies.modules.len * @sizeOf(Module) + self.record.key.owners.len * @sizeOf(@TypeOf(self.record.key.owners[0])) + self.record.key.nominal_facts.len * @sizeOf(validation.NominalFact);
        for (dependencies.modules) |module| bytes += module.path.len + module.graph.bytes.len;
        return .{ .records = 1, .payload_bytes = bytes };
    }
    pub fn matches(self: *const Certificate, context: validation.Context, names: identity.View, callers: []const *const @import("../check/core.zig").Module) bool {
        return self.record.dependencies.modules.len == context.units.len and self.record.key.matches(context, callers) and self.record.dependencies.namespace.matches(names);
    }
    /// Whether this certificate was captured for exactly these modules: every
    /// image equals its pin's module, and the namespace and validation bounds
    /// are the same. The validated context is then identical, not merely
    /// equivalent, so every unit's recorded validation holds even when foreign
    /// observations keep `matches` from reusing an equivalent context.
    pub fn sameContext(self: *const Certificate, context: validation.Context, names: identity.View, pins: anytype) bool {
        if (self.record.dependencies.modules.len != pins.len or pins.len != context.units.len) return false;
        if (!std.meta.eql(self.record.key.symbol_count, context.symbol_count) or !std.meta.eql(self.record.key.source_length, context.source_length)) return false;
        if (!self.record.dependencies.namespace.matches(names)) return false;
        for (pins, context.units, 0..) |pin, unit, ordinal| if (pin.module != unit or !self.admits(ordinal, pin)) return false;
        return true;
    }
    pub fn admits(self: *const Certificate, unit: usize, pin: anytype) bool {
        if (unit >= self.record.dependencies.modules.len) return false;
        const module = self.record.dependencies.modules[unit];
        return module.unit == pin.unit and std.mem.eql(u8, module.path, pin.canonical_path) and std.mem.eql(u8, &module.stamp, &pin.stamp) and module.graph.matches(pin.module.*);
    }
};
