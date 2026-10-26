// Experimental checked-add emitter. This is a private fixture, not public K1
// admission, a portable artifact, or a certificate for executable bytes.
namespace add_wasm;
import add_core;
import add_proof;
import wasm;

// Validate the source, Core, plan and evidence again using the same trusted
// compiler-owned Work that built the proof. No caller-provided validated flag
// or attached executable is accepted. Empty output signals a failed check;
// proof/semantic budget exhaustion remains recorded on Work.
fn emit(source: u8[:], plan: add_core::AddPlanV4, work: add_proof::Work&) -> u8[] {
    if add_core::validate_plan(source, plan, work) != 0 { return []; }
    let c = plan.checked.core;
    if c.name_start < 0 || c.name_end <= c.name_start || c.name_end > source.len ||
       !wasm::identifier(source[c.name_start..c.name_end]) || !wasm::fixture_geometry_valid() { return []; }
    // Preserve the actual checked operation in unoptimized output. The proof
    // establishes AddFits(x,0), so this i32.add is not a wrapping source op.
    var body: u8[>..] = [0, 0x20, 1, 0x41, 0, 0x6a, 0x0b];
    return wasm::emit_body(source[c.name_start..c.name_end], body);
}
