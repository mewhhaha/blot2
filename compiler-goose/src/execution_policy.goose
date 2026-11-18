// Execution choices owned by one compilation or session. They never change
// the emitted bytes.
namespace blot_execution_policy;

struct Policy {
    // Workers lowering independent modules to Core.
    semantic_workers: u8 = 1,
    // Checkers of independent modules, including the coordinating process.
    // Higher counts fork a process per group of ready modules.
    frontend_workers: u8 = 1,
}
