//! Rank and package authority share exact binder ownership and lexical Core
//! reconstruction. Physical carrier layouts never prove parametric code.
const core = @import("core.zig");
const PI = @import("../reuse/principal_interface.zig");
const Error = error{InvalidArtifact};
pub fn interface(owner: *const PI.Interface) Error!void {
    if (!owner.has_rank_contracts) return;
    try @import("package_portable.zig").interface(owner);
}
pub fn publicCore(owner: *const PI.Interface, module: *const core.Module) Error!void {
    if (owner.has_rank_contracts != module.has_rank_contracts) return error.InvalidArtifact;
    if (!owner.has_rank_contracts) return;
    try @import("package_portable.zig").publicCore(owner, module);
}
pub fn executable(module: *const core.Module, context: anytype) Error!void {
    if (!module.has_rank_contracts) return;
    try @import("package_core.zig").executable(module, context);
}

pub fn executableAllocated(allocator: @import("std").mem.Allocator, module: *const core.Module, context: anytype) error{ InvalidArtifact, OutOfMemory }!void {
    var workspace: @import("scheme_equations.zig").Workspace = .{ .allocator = allocator };
    return executableWorkspace(module, context, &workspace);
}
pub fn executableWorkspace(module: *const core.Module, context: anytype, workspace: *@import("scheme_equations.zig").Workspace) error{ InvalidArtifact, OutOfMemory }!void {
    if (!module.has_rank_contracts) return;
    var remaining: usize = 65_536;
    @import("package_core.zig").executableWorkspace(module, context, &remaining, workspace) catch |err| {
        if (workspace.oom) return error.OutOfMemory;
        return err;
    };
    if (workspace.oom) return error.OutOfMemory;
}
