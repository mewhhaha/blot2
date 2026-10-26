// Independent nonrecursive source/Core validator for the private F32 subset.
// It reconstructs postorder using its own operator/value stacks, verifies every
// token/span and node and does not trust producer annotations. It checks the
// declared fixture environment only; it does not establish a K1 function,
// ownership, loans, loop invariant, effects, resources or source authority.
namespace particle_expr_validate;
import lexer;
import particle_expr_core;
struct Op { kind: i64 = 0, start: i64 = 0, end: i64 = 0 }
fn is(s: u8[:], t: lexer::Token, kind: i64, value: u8[:]) -> bool {
    return t.kind == kind && t.start >= 0 && t.end > t.start && t.end <= s.len && s[t.start..t.end] == value;
}
fn match_node(core: particle_expr_core::Core&, index: i64, n: particle_expr_core::Node) -> bool {
    return index >= 0 && index < core.nodes.len && particle_expr_core::same(core.nodes[index], n);
}
fn reduce(core: particle_expr_core::Core&, ops: Op[:], olen: i64&, values: i64[:], vlen: i64&, next: i64&) -> bool {
    if olen <= 0 || vlen < 2 || next >= core.nodes.len { return false; }
    let op = ops[olen-1]; if op.kind != 6 && op.kind != 7 { return false; }
    let r = values[vlen-1]; let l = values[vlen-2];
    let n = particle_expr_core::Node { kind: op.kind, start: op.start, end: op.end, left: l, right: r };
    if !match_node(core,next,n) { return false; }
    olen -= 1; vlen -= 1; values[vlen-1] = next + 1; next += 1; return true;
}
fn verify(core: particle_expr_core::Core&) -> bool {
    let source = core.source;
    if source.len > 4096 || core.nodes.len == 0 || core.nodes.len > 256 || core.result != core.nodes.len { return false; }
    var lex = lexer::init(source); var token = lexer::next(source,lex);
    var ops: Op[256] = [Op {}; 256]; var olen: i64 = 0;
    var values: i64[256] = [0; 256]; var vlen: i64 = 0;
    var next: i64 = 0; var depth: i64 = 0; var need_value = true;
    loop {
        if token.kind == 9 { return false; }
        if need_value {
            if is(source,token,5,"(") {
                if depth >= 32 || olen >= 256 { return false; }
                ops[olen] = Op { kind: 0 }; olen += 1; depth += 1; token = lexer::next(source,lex); continue;
            }
            let first = token; var last = first; var kind: i64 = 0;
            if is(source,first,1,"dt") { kind = 5; token = lexer::next(source,lex); }
            else if is(source,first,1,"p") {
                token = lexer::next(source,lex); if !is(source,token,5,".") { return false; }
                token = lexer::next(source,lex); last = token;
                if is(source,last,1,"x") { kind = 1; } else if is(source,last,1,"y") { kind = 2; }
                else if is(source,last,1,"vx") { kind = 3; } else if is(source,last,1,"vy") { kind = 4; }
                else { return false; }
                token = lexer::next(source,lex);
            } else { return false; }
            if next >= core.nodes.len || vlen >= 256 || !match_node(core,next,particle_expr_core::Node { kind: kind, start: first.start, end: last.end }) { return false; }
            values[vlen] = next + 1; vlen += 1; next += 1; need_value = false; continue;
        }
        if is(source,token,5,")") {
            if depth == 0 { return false; }
            while olen > 0 && ops[olen-1].kind != 0 { if !reduce(core,ops,olen,values,vlen,next) { return false; } }
            if olen == 0 { return false; }
            olen -= 1; depth -= 1; token = lexer::next(source,lex); continue;
        }
        var kind: i64 = 0;
        if is(source,token,5,"*") { kind = 6; } else if is(source,token,5,"+") { kind = 7; }
        if kind != 0 {
            // * has precedence 2, + precedence 1; both are left associative.
            let precedence = if kind == 6 { 2 } else { 1 };
            while olen > 0 && ops[olen-1].kind != 0 {
                let p = if ops[olen-1].kind == 6 { 2 } else { 1 };
                if p < precedence { break; }
                if !reduce(core,ops,olen,values,vlen,next) { return false; }
            }
            if olen >= 256 { return false; }
            ops[olen] = Op { kind: kind, start: token.start, end: token.end }; olen += 1;
            token = lexer::next(source,lex); need_value = true; continue;
        }
        while token.kind == 6 { token = lexer::next(source,lex); }
        if token.kind != 0 || depth != 0 { return false; }
        while olen > 0 { if !reduce(core,ops,olen,values,vlen,next) { return false; } }
        return vlen == 1 && next == core.nodes.len && values[0] == core.result;
    }
}
