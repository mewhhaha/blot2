// Execution choices owned by one compilation or session. They never change
// the emitted bytes.
namespace blot_execution_policy;

struct Policy {
    // Workers lowering independent modules to Core.
    semantic_workers: u8 = 1,
    // Checkers of independent modules. Zig defaults to 4 threads. Here a
    // checker beyond the first is a forked copy of the process, and on Gdev
    // Main four of them take 3.8 s where one takes 1.9 s (15 November 2026),
    // so one is the default until the copies are cheaper.
    frontend_workers: u8 = 1,
}
