// Private source→interface→function→plan→Wasm integration fixture.
// Caller-selected package/ABI/pages and the fixture exports are untrusted test
// inputs, not an authenticated resolver, ABI profile, M13 certificate or host
// bridge. This module must not enable public K1 check/build or accept cached
// executable bytes. The engine receives regenerated Wasm only after fresh
// source and every candidate semantic link are checked.
namespace public_fixture;
import public_frontend;
import public_artifact;
import public_function;
import public_plan;
import scalar_plan;
import wasm;

fn emit(source: u8[:], interface: u8[:], function: u8[:], plan: u8[:],
        package: u8[:], module: u8[:], declaration: u8[:], abi: u8[:]) -> u8[] {
    // This fixture only implements its existing fixed 275-page geometry. It
    // cannot promote caller-supplied geometry or hashes into target authority.
    let candidate = public_frontend::parse(source);
    if candidate.status != 0 ||
       public_artifact::verify_source(interface, source, candidate, package, module, declaration, abi) != 0 ||
       public_function::verify_source(function, source, candidate, interface, package, module, declaration, abi) != 0 ||
       public_plan::verify_source(plan, source, candidate, interface, function, package, module, declaration, abi, 275) != 0 {
        return [];
    }
    let checked = public_plan::decode(plan, interface, function, package, module, declaration, abi, 275);
    if checked.status != 0 || checked.opcode != public_plan::opcode(candidate.core) { return []; }
    let lowering = scalar_plan::make(candidate.core);
    if !scalar_plan::validate(lowering) || lowering.memory_initial_pages != checked.pages ||
       lowering.memory_maximum_pages != checked.pages { return []; }
    // For the private plan, unary values have no final binary opcode. The
    // serialized plan instead names their local.get or i32.const producer.
    if (checked.opcode == 0x20 || checked.opcode == 0x41) && lowering.opcode != 0 { return []; }
    if (checked.opcode == 0x71 || checked.opcode == 0x49) && lowering.opcode != checked.opcode { return []; }
    if candidate.core.name_start < 0 || candidate.core.name_end > source.len ||
       candidate.core.name_end <= candidate.core.name_start { return []; }
    return wasm::emit_scalar_v2(source[candidate.core.name_start..candidate.core.name_end], lowering);
}
