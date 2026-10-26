// Private U32 locals fixture. Emission requires exact caller source and the
// independent source/Core check. No host ABI, certificate or work receipt.
namespace locals_wasm;
import locals_core;
import locals_check;
import wasm;
struct Action { kind: i64 = 0, value: i64 = 0 }
fn emit_value(p: locals_core::Program&, root: i64, out: u8[>..]&) -> bool {
    var stack: Action[>..] = [Action { kind:1, value:root }]; var steps: i64 = 0;
    while stack.len > 0 {
        steps += 1; if steps > 16384 || out.len > 65536 { return false; }
        let action = stack[stack.len-1]; stack.pop();
        if action.kind == 2 { out.push(action.value as u8); continue; }
        if action.kind != 1 || action.value < 1 || action.value > p.values.len { return false; }
        let n = p.values[action.value-1];
        if n.kind == 1 { out.push(0x20); wasm::unsigned_leb(out,n.a+1); }
        else if n.kind == 2 { out.push(0x41); wasm::signed_i32_leb(out,n.literal); }
        else if n.kind == 8 { stack.push(Action { kind:1, value:n.a }); }
        else if n.kind >= 3 && n.kind <= 7 {
            let opcode = if n.kind == 3 || n.kind == 4 { 0x6a } else if n.kind == 5 { 0x6b } else if n.kind == 6 { 0x6c } else { 0x71 };
            stack.push(Action { kind:2, value:opcode }); stack.push(Action { kind:1, value:n.b }); stack.push(Action { kind:1, value:n.a });
        } else { return false; }
    }
    return out.len <= 65536;
}
fn emit(expected_source: u8[:], p: locals_core::Program&) -> u8[] {
    if !locals_check::verify(expected_source,p) { return []; }
    var body: u8[>..] = [];
    if p.bindings.len == 0 { body.push(0); }
    else { body.push(1); wasm::unsigned_leb(body,p.bindings.len); body.push(0x7f); }
    for b, i in p.bindings {
        if !emit_value(p,b.value,body) { return []; }
        body.push(0x21); wasm::unsigned_leb(body,i+2); // local.set, env+arg precede locals
    }
    if p.cond_a != 0 {
        if !emit_value(p,p.cond_a,body) || !emit_value(p,p.cond_b,body) { return []; }
        body.push(0x49); // i32.lt_u
        body.push(0x04); body.push(0x40); // if with no result
        if !emit_value(p,p.yes,body) { return []; } body.push(0x0f);
        body.push(0x05);
        if !emit_value(p,p.no,body) { return []; } body.push(0x0f);
        body.push(0x0b);
    } else {
        if !emit_value(p,p.yes,body) { return []; } body.push(0x0f);
    }
    // Source completion was checked before emission; unreachable here only
    // satisfies Wasm stack polymorphism after explicit returns.
    body.push(0x00); body.push(0x0b);
    return wasm::emit_body(expected_source[p.name_start..p.name_end],body);
}
