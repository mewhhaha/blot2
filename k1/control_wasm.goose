// Private control fixture emitter. It always validates the source against the
// owned control record before emitting. It is not a public K1 ABI/certificate.
namespace control_wasm;
import control_core;
import control_validate;
import wasm;

fn atom(out: u8[>..]&, kind: i64) {
    if kind == 1 { out.push(0x20); out.push(1); } // parameter local; env is 0
    else { out.push(0x41); out.push(if kind == 2 { 1 } else { 0 }); }
}
fn condition(out: u8[>..]&, op: i64, left: i64, right: i64, probe: bool) {
    atom(out,left);
    if op == 0 { return; }
    // if (result i32): evaluate RHS only on the appropriate edge.
    out.push(0x04); out.push(0x7f);
    if op == 1 { if probe { out.push(0x00); } else { atom(out,right); } }
    else { out.push(0x41); out.push(1); }
    out.push(0x05);
    if op == 1 { out.push(0x41); out.push(0); }
    else { if probe { out.push(0x00); } else { atom(out,right); } }
    out.push(0x0b);
}
fn emit(source: u8[:], p: control_core::Program) -> u8[] {
    if !control_validate::verify(source,p) { return []; }
    var body: u8[>..] = [0];
    condition(body,p.op,p.left_kind,p.right_kind,false);
    body.push(0x04); body.push(0x7f);
    body.push(0x41); wasm::signed_i32_leb(body,p.yes);
    body.push(0x05);
    body.push(0x41); wasm::signed_i32_leb(body,p.no);
    body.push(0x0b); body.push(0x0b);
    return wasm::emit_body(source[p.name_start..p.name_end],body);
}
// Test-only: a deliberately unreachable RHS witnesses non-evaluation on the
// short-circuit edge. This function is not reachable from source compilation.
fn probe(op: i64) -> u8[] {
    if op != 1 && op != 2 { return []; }
    var body: u8[>..] = [0];
    condition(body,op,1,1,true);
    body.push(0x0b);
    return wasm::emit_body("probe",body);
}
