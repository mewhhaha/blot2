import os;
import particle_expr_core;
import particle_expr_parse;
import particle_expr_validate;
import particle_expr_wasm;
fn write_expression(source: u8[:], path: u8[:]) {
    let core, status = particle_expr_parse::parse(source);
    assert(status == 0 && particle_expr_validate::verify(core));
    let bytes = particle_expr_wasm::emit(core);
    assert(bytes.len > 0 && write_file(path,bytes));
}
fn main() {
    write_expression("p.x + p.vx * dt", "particle-expr-x.wasm");
    write_expression("p.y + p.vy * dt", "particle-expr-y.wasm");
    write_expression("(p.x + p.vx) * (dt + p.y)", "particle-expr-group.wasm");
    for src in ["dt", "p.x+p.y+p.vx+p.vy", "p.x*p.y*dt", "(p.x + (p.vx * dt))", "p . x + p . vx * dt\n"] {
        let c, status = particle_expr_parse::parse(src);
        assert(status == 0 && particle_expr_validate::verify(c));
    }
    for src in ["", "p", "p.z", "dt - p.x", "p.x / dt", "q.x + dt", "p.x +", "(p.x", "p.x)", "p.x p.y", "p.x\np.y", "p.x + // comment\n p.y", "dt * * dt", "p.x == dt", "dt + ( )"] {
        let c, status = particle_expr_parse::parse(src); assert(status != 0); assert(!particle_expr_validate::verify(c));
    }
    let original, status = particle_expr_parse::parse("p.x + p.vx * dt"); assert(status == 0);
    for index in original.nodes.len {
        for field in 5 {
            var c = particle_expr_core::Core { source: copy(original.source), nodes: copy(original.nodes), result: original.result };
            if field == 0 { c.nodes[index].kind += 1; }
            else if field == 1 { c.nodes[index].start += 1; }
            else if field == 2 { c.nodes[index].end += 1; }
            else if field == 3 { c.nodes[index].left += 1; }
            else { c.nodes[index].right += 1; }
            assert(!particle_expr_validate::verify(c)); assert(particle_expr_wasm::emit(c).len == 0);
        }
    }
    var c = particle_expr_core::Core { source: copy(original.source), nodes: copy(original.nodes), result: original.result };
    c.result -= 1; assert(!particle_expr_validate::verify(c)); assert(particle_expr_wasm::emit(c).len == 0);
    for i in original.source.len {
        var altered = particle_expr_core::Core { source: copy(original.source), nodes: copy(original.nodes), result: original.result };
        altered.source[i] = '?'; assert(!particle_expr_validate::verify(altered)); assert(particle_expr_wasm::emit(altered).len == 0);
    }
    var too_deep: u8[>..] = [];
    for i in 33 { too_deep.push('('); } too_deep.append("dt"); for i in 33 { too_deep.push(')'); }
    let depth_core, depth_status = particle_expr_parse::parse(too_deep); assert(depth_status == 2 && !particle_expr_validate::verify(depth_core));
    var too_long: u8[>..] = [32; 4097]; let long_core, long_status = particle_expr_parse::parse(too_long);
    assert(long_status == 2 && !particle_expr_validate::verify(long_core));
    print("private source-bound particle F32 expression Core passed");
}
