// The append-only list retains traversal and diagnostic order.
namespace blot_check_ordered_membership;
import std;
import dictionary;
import support.error;
struct Index { members: dictionary<u32, bool>&, enabled: bool = true, covered: i64 = 0 }
fn init(members: dictionary<u32, bool>&) -> Index { members.clear(); return Index { members }; }
fn deinit(self: Index&) { self.members.clear(); self.covered = 0; }
fn contains(self: Index&, values: const u32[:], value: u32) -> bool, blot_error::Error {
    if !self.enabled || values.len < 64 {
        for item in values { if item == value { return true, blot_error::Error.none; } }
        return false, blot_error::Error.none;
    }
    assert(values.len >= self.covered);
    while self.covered < values.len {
        self.members.insert(values[self.covered], true);
        self.covered += 1;
    }
    return self.members.contains(value), blot_error::Error.none;
}
