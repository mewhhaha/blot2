//! Monotonic invalidation stamps for store-owned resolution caches.
// Epochs never wrap. Once their compact stamps are exhausted, queries bypass
// retained entries; rollback cannot make an old numerical stamp live again.
pub fn tick(epoch: *u64) void {
    if (epoch.* != @import("std").math.maxInt(u64)) epoch.* += 1;
}
pub fn stamp(epoch: u64) ?u32 {
    return if (epoch < @import("std").math.maxInt(u32)) @intCast(epoch) else null;
}
