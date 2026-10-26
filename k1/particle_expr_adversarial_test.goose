import particle_expr_core;
import particle_expr_parse;
import particle_expr_validate;
fn random(seed: u32&) -> u32 { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return seed; }
recursive fn gen(out: u8[>..]&, seed: u32&, depth: i64) {
    if depth == 0 || random(seed) % 3 == 0 {
        let pick = random(seed) % 5;
        if pick == 0 { out.append("p.x"); } else if pick == 1 { out.append("p.y"); }
        else if pick == 2 { out.append("p.vx"); } else if pick == 3 { out.append("p.vy"); } else { out.append("dt"); }
    } else {
        out.push('('); gen(out,seed,depth-1);
        if random(seed) % 2 == 0 { out.append(" + "); } else { out.append(" * "); }
        gen(out,seed,depth-1); out.push(')');
    }
}
fn main() {
    var seed: u32 = 0x7e57ba1e;
    for trial in 10000 {
        var src: u8[>..] = []; gen(src,seed,5);
        let c, status = particle_expr_parse::parse(src);
        assert(status == 0 && particle_expr_validate::verify(c));
        var other = particle_expr_core::Core { source: copy(c.source), nodes: copy(c.nodes), result: c.result };
        let index = random(seed) % other.nodes.len; let field = random(seed) % 5;
        if field == 0 { other.nodes[index].kind += 1; }
        else if field == 1 { other.nodes[index].start += 1; }
        else if field == 2 { other.nodes[index].end += 1; }
        else if field == 3 { other.nodes[index].left += 1; }
        else { other.nodes[index].right += 1; }
        assert(!particle_expr_validate::verify(other));
        src[0] = '?'; assert(particle_expr_validate::verify(c));
    }
    print("10000 generated expressions and forged records passed");
}
