// Rank and package authority share exact binder ownership.
namespace blot_check_rank_portable;
import support.error;
fn interface(owner: const blot_reuse_principal_interface::Interface&) -> blot_error::Error {
    if !owner.has_rank_contracts { return blot_error::Error.none; }
    return blot_check_package_portable::interface(owner);
}
fn publicCore(owner: const blot_reuse_principal_interface::Interface&, module: const blot_check_core::Module&) -> blot_error::Error {
    if owner.has_rank_contracts != module.has_rank_contracts { return blot_error::Error.invalid_artifact; }
    if !owner.has_rank_contracts { return blot_error::Error.none; }
    return blot_check_package_portable::publicCore(owner, module);
}
fn executable(module: const blot_check_core::Module&, context) -> blot_error::Error {
    if !module.has_rank_contracts { return blot_error::Error.none; }
    return blot_check_package_core::executable(module, context);
}
fn executableAllocated(module: const blot_check_core::Module&, context,
                       workspace: blot_check_scheme_equations::Workspace&) -> blot_error::Error {
    // The caller owns the typed workspace and its backing tables.
    return executableWorkspace(module, context, workspace);
}
fn executableWorkspace(module: const blot_check_core::Module&, context,
                       workspace: blot_check_scheme_equations::Workspace&) -> blot_error::Error {
    if !module.has_rank_contracts { return blot_error::Error.none; }
    var remaining: i64 = 65536;
    let error = blot_check_package_core::executableWorkspace(module, context, remaining, workspace);
    if workspace.oom { return blot_error::Error.out_of_memory; }
    return error;
}
