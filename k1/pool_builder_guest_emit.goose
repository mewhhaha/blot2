import os;
import pool_builder_guest;
fn main() {
    let bytes = pool_builder_guest::emit();
    if !write_file("pool-builder-guest.wasm", bytes) { abort("cannot write pool builder guest fixture"); }
}
