import os;
import bridge_wasm_fixture;
fn main() {
    let bytes = bridge_wasm_fixture::emit();
    if !write_file("bridge-fixture.wasm", bytes) { abort("cannot write bridge fixture"); }
}
