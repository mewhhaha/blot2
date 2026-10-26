// Experimental scalar thin-entry fixture. It is not a K1 public host bridge,
// ABI manifest or certificate. Source/Core correspondence and resource
// admission must be established independently before calling this encoder.
namespace scalar_thin;
import scalar_core;
import scalar_plan;
import wasm;

fn append_section(out: u8[>..]&, id: u8, payload: u8[:]) {
    out.push(id);
    wasm::unsigned_leb(out, payload.len);
    out.append(payload);
}

fn emit_thin_operand(out: u8[>..]&, value: scalar_core::ScalarValue) {
    if value.producer == 1 { out.push(0x20); out.push(0); }
    else { out.push(0x41); wasm::signed_i32_leb(out, value.literal); }
}

// Emits a fixed (arg:i32)->i32 thin worker and a canonical
// (env:i32,arg:i32)->i32 adapter. Only the worker is exported. The adapter
// discards the environment and forwards its argument once. There are no imported helpers,
// allocations, mutable globals or memory.grow. Empty output means rejection.
fn emit(name: u8[:], plan: scalar_plan::ScalarLoweringPlan) -> u8[] {
    if !wasm::identifier(name) || !wasm::fixture_geometry_valid() ||
       !scalar_plan::validate(plan) || !wasm::valid_v2(plan.core) { return []; }
    let core = plan.core;
    let value = core.values[core.result_id];
    var worker: u8[>..] = [0]; // no locals
    if value.producer == 3 {
        emit_thin_operand(worker, core.values[value.left_id]);
        emit_thin_operand(worker, core.values[value.right_id]);
        worker.push(plan.opcode as u8);
    } else { emit_thin_operand(worker, value); }
    worker.push(0x0b);
    // local decl count, local.get 1, call worker 0, end
    let canonical: u8[6] = [0, 0x20, 1, 0x10, 0, 0x0b];
    var output: u8[>..] = [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0];
    // Two types: thin (i32)->i32 and canonical (i32,i32)->i32.
    let types: u8[12] = [2, 0x60, 1, 0x7f, 1, 0x7f, 0x60, 2, 0x7f, 0x7f, 1, 0x7f];
    append_section(output, 1, types);
    let functions: u8[3] = [2, 0, 1];
    append_section(output, 3, functions);
    var memory: u8[>..] = [1, 1];
    wasm::unsigned_leb(memory, 275); wasm::unsigned_leb(memory, 275);
    append_section(output, 5, memory);
    var exports: u8[>..] = [1];
    wasm::unsigned_leb(exports, name.len);
    exports.append(name); exports.push(0); exports.push(0);
    append_section(output, 7, exports);
    var code: u8[>..] = [2];
    wasm::unsigned_leb(code, worker.len); code.append(worker);
    wasm::unsigned_leb(code, canonical.len); code.append(canonical);
    append_section(output, 10, code);
    return output;
}
