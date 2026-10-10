//! A successful frozen-Core/dependency validation, owned by one published
//! revision. Exact namespace and graph images, producer paths and every foreign
//! bound travel together. This record never authorizes semantic or code reuse.
const std = @import("std");
const validation = @import("frozen_core_validation.zig");
const identity = @import("runtime_identity.zig");
const Image = @import("validation_image.zig").Image;
const queries = @import("semantic_query_table.zig");
const A = std.mem.Allocator;

const Module = struct {
    unit: u32,
    path: []u8,
    stamp: [32]u8,
    graph: Image,
    fn deinit(self: *Module, a: A) void {
        a.free(self.path);
        self.graph.deinit(a);
    }
};
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
    pub fn observe(self: *Stats, gate: anytype) void {
        self.dependency_validations += gate.dependency_validations;
        self.reused_dependency_validations += gate.reused_dependency_validations;
    }
};

pub const Certificate = struct {
    record: Record,

    /// Called only after authoritative graph/dependency validation. A single
    /// immutable owner has one certificate and needs no bucket index. Optional
    /// oversized images decline retention; subsequent validation runs normally.
    pub fn capture(a: A, context: validation.Context, pins: anytype, names: identity.View) A.Error!?Certificate {
        return captureWithBudget(a, context, pins, names, (queries.Limits{}).owned_bytes);
    }
    pub fn captureWithBudget(a: A, context: validation.Context, pins: anytype, names: identity.View, budget: usize) A.Error!?Certificate {
        if (pins.len == 0 or pins.len != context.units.len or names.owners.len != pins.len) return null;
        var remaining = budget;
        if (pins.len > remaining / @sizeOf(Module)) return null;
        remaining -= pins.len * @sizeOf(Module);
        if (context.units.len > remaining / @sizeOf(@typeInfo(@FieldType(validation.ContextImage, "owners")).pointer.child)) return null;
        remaining -= context.units.len * @sizeOf(@typeInfo(@FieldType(validation.ContextImage, "owners")).pointer.child);
        var image = try validation.ContextImage.capture(a, context);
        var transferred = false;
        defer if (!transferred) image.deinit(a);
        var namespace = try Image.capture(a, names, &remaining) orelse return null;
        defer if (!transferred) namespace.deinit(a);
        const modules = try a.alloc(Module, pins.len);
        var initialized: usize = 0;
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
            const graph = try Image.capture(a, unit.*, &remaining) orelse return null;
            module.* = .{ .unit = pin.unit, .path = path, .stamp = pin.stamp, .graph = graph };
            owned_path = false;
            initialized += 1;
        }
        transferred = true;
        return .{ .record = .{ .key = image, .dependencies = .{ .namespace = namespace, .modules = modules }, .value = .{} } };
    }

    pub fn deinit(self: *Certificate, a: A) void {
        self.record.deinit(a);
        self.* = undefined;
    }
    pub fn storage(self: *const Certificate) queries.Storage {
        const dependencies = self.record.dependencies;
        var bytes = dependencies.namespace.bytes.len + dependencies.modules.len * @sizeOf(Module) + self.record.key.owners.len * @sizeOf(@TypeOf(self.record.key.owners[0]));
        for (dependencies.modules) |module| bytes += module.path.len + module.graph.bytes.len;
        return .{ .records = 1, .payload_bytes = bytes };
    }
    pub fn matches(self: *const Certificate, context: validation.Context, names: identity.View) bool {
        return self.record.dependencies.modules.len == context.units.len and self.record.key.matches(context) and self.record.dependencies.namespace.matches(names);
    }
    pub fn admits(self: *const Certificate, unit: usize, pin: anytype) bool {
        if (unit >= self.record.dependencies.modules.len) return false;
        const module = self.record.dependencies.modules[unit];
        return module.unit == pin.unit and std.mem.eql(u8, module.path, pin.canonical_path) and std.mem.eql(u8, &module.stamp, &pin.stamp) and module.graph.matches(pin.module.*);
    }
};
