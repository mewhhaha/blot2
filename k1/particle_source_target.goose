// Exact admitted target for the one closed particle-source fixture. This
// checker binds source and every typed operation/evidence record to the pinned
// complete target bytes, rather than accepting a caller-provided hash, byte
// pointer, or self-declared certificate. The pinned target is a trusted,
// separately tested runtime component: its raw owner slots, disjointness and
// input initialization still depend on the fixture caller. It is not M13,
// a general semantic Wasm validator, or an actual public K1 host ABI.
namespace particle_source_target;
import particle_source_core;
import particle_source_validate;
import particle_source_golden;
fn verify(core:particle_source_core::Core&, source:u8[:], context:particle_source_core::Context, bytes:u8[:])->bool {
    if !particle_source_validate::verify(core,source,context) {return false;}
    let pinned=particle_source_golden::bytes();
    return bytes==pinned[..];
}
