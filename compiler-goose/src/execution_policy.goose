// Execution choices owned by one compilation or session. They never change
// the emitted bytes.
namespace blot_execution_policy;

struct Policy {
    // Workers lowering independent modules to Core.
    semantic_workers: u8 = 1,
    // Workers checking independent modules.
    frontend_workers: u8 = 4,
}
