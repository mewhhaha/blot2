//! PRIVATE full-project proof owner. Checking stays in project_check; this
//! helper only freezes its successful real source units for source-free emission.
const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const identity = @import("runtime_identity.zig");
const Allocator = std.mem.Allocator;

pub const OwnedCore = struct {
    units: []core.Module,
    names: identity.Metadata,
    order: []u32,
    entry: u32,
    prelude: u32,
    source_mode: bool,
    body_lowerings: usize,
    pub fn deinit(self: *OwnedCore, a: Allocator) void {
        for (self.units) |*module| module.deinit(a);
        a.free(self.units);
        self.names.deinit(a);
        a.free(self.order);
        self.* = undefined;
    }
    pub fn emit(self: *const OwnedCore, a: Allocator) !backend.Result {
        return backend.compileWithOptions(a, self.units, self.entry, .{ .identity = self.names.view(), .unit_order = self.order, .diagnostic_source_mode = self.source_mode, .diagnostic_prelude_unit = self.prelude });
    }
};

pub fn lowerChecked(a: Allocator, source: *const project.Project, checked: *const checker.CheckedProject) !OwnedCore {
    if (source.diagnostics.items.len != 0 or checked.diagnostics.len != 0 or source.compiled_modules.len != 0) return error.UnqualifiedProject;
    const units = try a.alloc(core.Module, source.units.items.len);
    errdefer a.free(units);
    var done: usize = 0;
    errdefer for (units[0..done]) |*module| module.deinit(a);
    var lowerings: usize = 0;
    for (source.units.items, units, 0..) |*unit, *module, index| {
        const id: u32 = @intCast(index + 1);
        module.* = try core.lowerWithOrigins(a, &unit.tree, &source.symbols, &checked.module(id).checked, .{ .context = source, .lookup = checker.diagnosticModuleOrigin });
        done += 1;
        if (module.diagnostics.len != 0) return error.LoweringDiagnostics;
        module.unit = id;
        lowerings += module.body_lowerings;
    }
    const owners = try a.alloc(identity.Owner, units.len);
    defer a.free(owners);
    for (owners, 0..) |*owner, i| owner.* = .{ .unit = @intCast(i + 1), .path = source.filename(@intCast(i + 1)) };
    var names = try identity.Metadata.capture(a, &source.symbols, owners, units.len);
    errdefer names.deinit(a);
    const order = try a.dupe(u32, source.order.items);
    return .{ .units = units, .names = names, .order = order, .entry = source.entry, .prelude = source.prelude_unit, .source_mode = source.input_mode == .source, .body_lowerings = lowerings };
}
