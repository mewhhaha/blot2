// Private summary of the source-backed scalar module subset. Bound records are
// supplied by a trusted caller, not parsed K1 declarations. This models only
// reserve/release/host effect bits, no region effects or external ABI frames.
namespace effect_core;

struct Bound {
    name_start: i64 = 0, name_end: i64 = 0,
    effects: i64 = 0, depth: i64 = 0, frame: i64 = 0
}
struct Entry {
    bound: Bound = Bound {}, callee: i64 = -1,
    actual_effects: i64 = 0, actual_depth: i64 = 0, actual_frame: i64 = 0
}
struct Summary { source: u8[] = [], entries: Entry[] = [] }

fn same_bound(a: Bound, b: Bound) -> bool {
    return a.name_start == b.name_start && a.name_end == b.name_end &&
           a.effects == b.effects && a.depth == b.depth && a.frame == b.frame;
}
