// Private metered scalar emission. Source association must already have been
// independently checked. This produces the existing test fixture, not a K1
// manifest, target certificate, public ABI or trusted executable provenance.
namespace scalar_wasm_metered;
import scalar_plan;
import scalar_plan_metered;
import wasm;
import wasm_fast;
import work;

struct Emitted { status: u32 = 0, receipt: work::Receipt = work::Receipt {}, bytes: u8[] = [] }
// 0 success, 1 invalid, 2 semantic limit, 3 Core limit, 4 internal.
fn emit(name: u8[:], plan: scalar_plan::ScalarLoweringPlan, meter: work::Meter&) -> Emitted {
    if !wasm::identifier(name) || !wasm::fixture_geometry_valid() { return Emitted { status: 1 }; }
    let checked = scalar_plan_metered::validate(plan, meter, 7);
    if checked.status != 0 { return Emitted { status: checked.status, receipt: checked.receipt }; }
    var r = work::charge(meter, 7, 12); // revisit and cache the plan opcode
    if r.status != 0 { return Emitted { status: scalar_plan_metered::status(r), receipt: r }; }
    let opcode = plan.opcode;
    r = work::charge(meter, 7, 13); // emission follows the plan's Core edge again
    if r.status != 0 { return Emitted { status: scalar_plan_metered::status(r), receipt: r }; }
    r = work::charge(meter, 7, 4); // Core header
    if r.status != 0 { return Emitted { status: scalar_plan_metered::status(r), receipt: r }; }
    let c = plan.core;
    r = work::charge(meter, 7, 5); // return edge
    if r.status != 0 { return Emitted { status: scalar_plan_metered::status(r), receipt: r }; }
    r = work::charge(meter, 7, 4); // returned Core value
    if r.status != 0 { return Emitted { status: scalar_plan_metered::status(r), receipt: r }; }
    let result = c.values[c.result_id];
    var body: u8[>..] = [0];
    if result.producer == 3 {
        r = work::charge(meter, 7, 5); // left value edge
        if r.status != 0 { return Emitted { status: scalar_plan_metered::status(r), receipt: r }; }
        r = work::charge(meter, 7, 4); // left value
        if r.status != 0 { return Emitted { status: scalar_plan_metered::status(r), receipt: r }; }
        wasm::emit_operand(body, c.values[result.left_id]);
        r = work::charge(meter, 7, 5); // right value edge
        if r.status != 0 { return Emitted { status: scalar_plan_metered::status(r), receipt: r }; }
        r = work::charge(meter, 7, 4); // right value
        if r.status != 0 { return Emitted { status: scalar_plan_metered::status(r), receipt: r }; }
        wasm::emit_operand(body, c.values[result.right_id]);
        body.push(opcode as u8);
    } else {
        r = work::charge(meter, 7, 4); // operand helper revisits the result value
        if r.status != 0 { return Emitted { status: scalar_plan_metered::status(r), receipt: r }; }
        wasm::emit_operand(body, result);
    }
    body.push(0x0b);
    let bytes = wasm_fast::emit_body(name, body);
    if bytes.len == 0 { return Emitted { status: 1 }; }
    return Emitted { bytes: bytes };
}
