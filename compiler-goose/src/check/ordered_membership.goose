// The append-only list retains traversal and diagnostic order.
namespace blot_check_ordered_membership;
import support.error;
import support.pooled_map;

import std;
import dictionary;
struct Index { members: dictionary<u32, bool>&, enabled: bool = true, covered: i64 = 0 }
fn init(members: dictionary<u32, bool>&) -> Index { members.clear(); return Index { members , ..}; }
fn deinit(self_: Index&) { self_.members.clear(); self_.covered = 0; }
fn contains(self_: Index&, values: const u32[:], value: u32) -> bool, blot_error::Error {
    if !self_.enabled || values.len < 64 {
        for item in values { if item == value { return true, blot_error::Error.none; } }
        return false, blot_error::Error.none;
    }
    assert(values.len >= self_.covered);
    while self_.covered < values.len {
        self_.members.insert(values[self_.covered], true);
        self_.covered += 1;
    }
    return self_.members.contains(value), blot_error::Error.none;
}
struct PooledIndex {members:blot_support_pooled_map::Map<u32,bool>   = blot_support_pooled_map::Map<u32,bool>{..},enabled:bool=true,covered:i64=0}
reusable[] var membership_slots:dictionary_slot<u32,bool>[>..];
fn initPooled(enabled:bool=true)->PooledIndex {return PooledIndex{enabled:enabled, ..};}
fn deinit(self_:PooledIndex&) {self_.members.deinit(membership_slots);self_.covered=0;}
fn contains(self_:PooledIndex&,values:const u32[:],value:u32)->bool,blot_error::Error {if !self_.enabled || values.len<64 {for item in values {if item==value {return true,blot_error::Error.none;}}return false,blot_error::Error.none;}assert(values.len>=self_.covered);while self_.covered<values.len {self_.members.insert(values[self_.covered],true,membership_slots);self_.covered+=1;}return self_.members.contains(value),blot_error::Error.none;}
