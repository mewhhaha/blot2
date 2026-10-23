//! One process-local work limit for checking and associated evidence. The CLI
//! binds non-default limits into compiler identity before creating any session.
const root = @import("root");

pub fn configured() usize {
    if (@hasDecl(root, "inferenceBudget")) return root.inferenceBudget();
    if (@hasDecl(root, "compiler_defaults")) return root.compiler_defaults.inference_budget;
    return 1_000_000;
}
