import os;
import particle_guest;
fn main() {
    let bytes = particle_guest::emit();
    if !write_file("particle-guest.wasm", bytes) { abort("cannot write particle guest fixture"); }
    if !write_file("particle-fault-0.wasm", particle_guest::emit_test(0)) { abort("cannot write fault fixture"); }
    if !write_file("particle-fault-1.wasm", particle_guest::emit_test(1)) { abort("cannot write fault fixture"); }
    if !write_file("particle-fault-2.wasm", particle_guest::emit_test(2)) { abort("cannot write fault fixture"); }
    if !write_file("particle-fault-3.wasm", particle_guest::emit_test(3)) { abort("cannot write fault fixture"); }
    if !write_file("particle-fault-4.wasm", particle_guest::emit_test(4)) { abort("cannot write fault fixture"); }
}
