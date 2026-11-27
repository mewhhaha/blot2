// Execution choices owned by one compilation or session. They never change
// the emitted bytes.
namespace squid_execution_policy;

struct Policy {
    // Workers lowering independent modules to Core.
    semantic_workers: u8 = 1,
    // Checkers of independent modules, including the coordinating process.
    // An omitted setting lets the project server choose for the loaded source.
    frontend_workers: u8 = 0,
}
