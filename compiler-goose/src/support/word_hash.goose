// Word-key hashes use the same little-endian structural stream as other private keys.
import support.wyhash;
fn hash(values:const u64[:])->u64 {
    var state=blot_support_wyhash::init(0);
    for value in values {state.value(value);}
    return state.final();
}
