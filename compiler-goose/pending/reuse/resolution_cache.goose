namespace blot_reuse_resolution_cache;
import support.option;

fn tick(epoch: u64&) { if epoch != 18446744073709551615 { epoch++; } }
fn stamp(epoch: u64) -> blot_support::Option<u32> {
    if epoch < 4294967295 { return blot_support::some(epoch as u32); }
    return blot_support::none<u32>();
}
