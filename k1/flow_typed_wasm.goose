// Private Bool -> U32 lowering. This consumes only a source-rechecked typed
// flow tree and emits no imports. It is not the K1 host bridge or certificate.
namespace flow_typed_wasm;
import flow_typed;
import flow_typed_check;
import wasm;

// Iterative stack avoids recursion on long statement sequences. Kinds are
// visit node, emit one byte, or emit the node's checked i32 literal.
struct Action { kind: i64 = 0, value: i64 = 0 }
fn visit(stack: Action[>..]&, id: i64) { stack.push(Action { kind: 1, value: id }); }
fn byte(stack: Action[>..]&, x: i64) { stack.push(Action { kind: 2, value: x }); }
fn literal(stack: Action[>..]&, id: i64) { stack.push(Action { kind: 3, value: id }); }

// probe_node is only exposed by probe() below, never by ordinary emission.
// It makes a particular Bool operand trap so tests can witness laziness.
fn lower(p: flow_typed::Program&, probe_node: i64) -> u8[] {
    if !flow_typed_check::verify(p) { return []; }
    if probe_node != 0 {
        var found = false;
        for n in p.tree.nodes { if (n.tag == 7 || n.tag == 8) && n.b == probe_node { found = true; } }
        if !found { return []; }
    }
    var out: u8[>..] = [0]; var stack: Action[>..] = []; visit(stack,p.tree.root);
    var steps: i64 = 0;
    while stack.len > 0 {
        steps += 1;
        if steps > 16384 || out.len > 65536 { return []; }
        let a = stack[stack.len-1]; stack.pop();
        if a.kind == 2 { out.push(a.value as u8); continue; }
        if a.kind == 3 { wasm::signed_i32_leb(out,p.literals[a.value-1]); continue; }
        if a.kind != 1 || a.value < 1 || a.value > p.tree.nodes.len { return []; }
        if a.value == probe_node { out.push(0x00); continue; }
        let n = p.tree.nodes[a.value-1];
        if n.tag == 1 { out.push(0x20); out.push(1); }
        else if n.tag == 2 { out.push(0x41); literal(stack,a.value); }
        else if n.tag == 3 || n.tag == 4 { out.push(0x41); out.push(if n.tag == 4 { 1 } else { 0 }); }
        else if n.tag == 5 { visit(stack,n.a); }
        else if n.tag == 7 || n.tag == 8 {
            byte(stack,0x0b); // end if (result i32)
            if n.tag == 7 { byte(stack,0); byte(stack,0x41); }
            else { visit(stack,n.b); }
            byte(stack,0x05); // else
            if n.tag == 7 { visit(stack,n.b); }
            else { byte(stack,1); byte(stack,0x41); }
            byte(stack,0x7f); byte(stack,0x04); visit(stack,n.a);
        } else if n.tag == 9 { byte(stack,0x0f); visit(stack,n.a); }
        else if n.tag == 10 {
            byte(stack,0x0b);
            if n.c != 0 { visit(stack,n.c); byte(stack,0x05); }
            visit(stack,n.b); byte(stack,0x40); byte(stack,0x04); visit(stack,n.a);
        } else if n.tag == 11 { visit(stack,n.b); visit(stack,n.a); }
        else { return []; }
    }
    // Completion has established that normal source paths return. The final
    // unreachable supplies Wasm stack polymorphism after structured control;
    // it is not used as evidence for source completion.
    out.push(0x00); out.push(0x0b);
    return wasm::emit_body(p.name,out);
}
fn emit(p: flow_typed::Program&) -> u8[] { return lower(p,0); }
// Test only: no public compiler path calls this trapping variant.
fn probe(p: flow_typed::Program&, node: i64) -> u8[] { if node <= 0 { return []; } return lower(p,node); }
