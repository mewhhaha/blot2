// Fixed-source particle fixture pipeline. The independently recognized Core
// is linked only to the pinned private target checked byte-for-byte. This is
// not general source lowering, qualified host/ABI/resource/loan enforcement,
// nor a compiler-wide proof meter or certificate. The pinned worker evaluates
// both row arguments before any output store and publishes length afterward.
namespace particle_source_wasm;
import particle_source_backend;
import particle_source_core;
import particle_source_validate;
import particle_source_target;
fn emit(core:particle_source_core::Core&, source:u8[:], context:particle_source_core::Context)->u8[] {
    if !particle_source_validate::verify(core,source,context) {return [];}
    let bytes=particle_source_backend::emit();
    if !particle_source_target::verify(core,source,context,bytes) {return [];}
    return bytes;
}
