// Declaration ownership marks and direct operator-forwarder tags.
// direct_op: 0 = ordinary, 1 = @type.call forwarder, 2 = @pipe forwarder, 3 = @pipe flipped forwarder.
namespace blot_check_capability_flow;
struct Parameters { own: u32 = 0, own_count: u8 = 0, owned_results: bool = false, direct_op: u8 = 0 }
fn withOwnership(self_: Parameters, previous: Parameters) -> Parameters { return previous; }
