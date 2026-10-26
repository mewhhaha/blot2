import os;
import pool_guest;
fn main() {
    let bytes = pool_guest::emit();
    if !write_file("pool-guest.wasm", bytes) { abort("cannot write pool guest fixture"); }
}
