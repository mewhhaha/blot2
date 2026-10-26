// Private single-capture closure experiment, not a public CheckedFunction,
// authenticated artifact, complete K1 ABI or owned environment implementation.
namespace closure_core;
struct Span { start: i64 = 0, end: i64 = 0 }
struct Core {
    source: u8[] = [],
    function: Span = Span {}, capture: Span = Span {}, argument: Span = Span {},
    binding: Span = Span {}, parameter: Span = Span {},
    inner_use: Span = Span {}, capture_use: Span = Span {},
    binding_use: Span = Span {}, argument_use: Span = Span {},
    schema: u32 = 0, capture_kind: u32 = 0, capture_version: u32 = 0,
    argument_version: u32 = 0, inner_version: u32 = 0,
    mode: u32 = 0, placement: u32 = 0, escaping: u32 = 0,
    env_size: u32 = 0, env_align: u32 = 0, env_offset: u32 = 0,
    code_slot: u32 = 0, worker_depth: u32 = 0, worker_frame: u32 = 0,
    caller_depth: u32 = 0, caller_frame: u32 = 0
}
fn same(a: Span, b: Span) -> bool { return a.start == b.start && a.end == b.end; }
