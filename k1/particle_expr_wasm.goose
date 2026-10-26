// Private F32 expression emission. Inputs are five raw f32 parameters in the
// fixture environment (p.x,p.y,p.vx,p.vy,dt). It is not the K1 function ABI,
// a particle loop, source contract admission, an optimizer or certificate.
namespace particle_expr_wasm;
import wasm;
import particle_expr_core;
import particle_expr_validate;
fn section(out: u8[>..]&, id: u8, payload: u8[:]) { out.push(id); wasm::unsigned_leb(out,payload.len); out.append(payload); }
fn emit(core: particle_expr_core::Core&) -> u8[] {
    if !particle_expr_validate::verify(core) { return []; }
    var body: u8[>..] = [0]; // no locals; checked postorder is a stack expression
    for node in core.nodes {
        if node.kind >= 1 && node.kind <= 5 { body.push(0x20); wasm::unsigned_leb(body,node.kind-1); }
        else if node.kind == 6 { body.push(0x94); } // f32.mul
        else if node.kind == 7 { body.push(0x92); } // f32.add
        else { return []; }
    }
    body.push(0x0b);
    var out: u8[>..] = [0,0x61,0x73,0x6d,1,0,0,0];
    let types: u8[10] = [1,0x60,5,0x7d,0x7d,0x7d,0x7d,0x7d,1,0x7d]; section(out,1,types);
    let functions: u8[2] = [1,0]; section(out,3,functions);
    let exports: u8[8] = [1,4,'e','x','p','r',0,0]; section(out,7,exports);
    var code: u8[>..] = [1]; wasm::unsigned_leb(code,body.len); code.append(body); section(out,10,code);
    return out;
}
