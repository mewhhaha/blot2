// Private generic identity execution fixture. It is not the public K1 ABI,
// host bridge, a complete ownership checker, or executable provenance.
// This worker uses (env, result-slot, dictionary, argument-slot)->Unit and
// memory.copy for a move; callers must establish the exact admitted dictionary,
// initialized source, disjoint exclusive result, and logical consumption.
namespace generic_identity_wasm;
import generic_identity;
import generic_dictionary;
import generic_layout_plan;
import wasm;

fn section(out: u8[>..]&, kind: u8, payload: u8[:]) {
    out.push(kind); wasm::unsigned_leb(out, payload.len); out.append(payload);
}
fn emit(source: u8[:], body: generic_identity::Body, dictionary: generic_dictionary::Result&,
        schema: u8[:], id: u32) -> u8[] {
    let plan = generic_layout_plan::instantiate(source, body, dictionary, schema, id);
    if plan.status != 0 { return []; }
    let name = source[body.name_start..body.name_end];
    if !wasm::identifier(name) || name.len > 114 || name == "memory" { return []; }
    var out: u8[>..] = [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0];
    let types: u8[8] = [1, 0x60, 4, 0x7f, 0x7f, 0x7f, 0x7f, 0];
    section(out, 1, types);
    let functions: u8[2] = [1, 0]; section(out, 3, functions);
    let memory: u8[4] = [1, 1, 1, 1]; section(out, 5, memory);
    var exports: u8[>..] = [2, 6]; exports.append("memory"); exports.push(2); exports.push(0);
    wasm::unsigned_leb(exports, name.len); exports.append(name); exports.push(0); exports.push(0);
    section(out, 7, exports);
    // No locals. Load dict.size, then move its bytes from argument to result.
    let code: u8[17] = [1, 15, 0, 0x20, 1, 0x20, 3, 0x20, 2, 0x28, 2, 0, 0xfc, 0x0a, 0, 0, 0x0b];
    section(out, 10, code);
    return out;
}
