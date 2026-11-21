// Declaration ownership marks: `own` parameter mask, arity, and owned-result bit.
namespace blot_check_capability_flow;
struct Parameters { own: u32 = 0, own_count: u8 = 0, owned_results: bool = false }
fn withOwnership(self_: Parameters, previous: Parameters) -> Parameters { return previous; }
