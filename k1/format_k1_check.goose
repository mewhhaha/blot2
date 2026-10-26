// Independent round-trip comparisons for the private tagged compiler subset.
// All candidate programs must first pass their normal source/Core validators.
namespace format_k1_check;
import lexer;
import compiler_core;
import compiler_validate;
import compiler_wasm;
import iteration_core;
import unified_core;

fn span(a:u8[:],a0:i64,a1:i64,b:u8[:],b0:i64,b1:i64) -> bool {
    return a0>=0 && a1>a0 && a1<=a.len && b0>=0 && b1>b0 && b1<=b.len && a[a0..a1]==b[b0..b1];
}
// Compare exact significant token spellings while ignoring layout-token byte
// positions. Structural and lexical target checks below separately preserve
// line/suite nesting and binding/transfer targets.
fn tokens(a:u8[:],b:u8[:]) -> bool {
    var la=lexer::init(a);var lb=lexer::init(b);var ta=lexer::next(a,la);var tb=lexer::next(b,lb);
    loop {
        while ta.kind>=6 && ta.kind<=8 {ta=lexer::next(a,la);}
        while tb.kind>=6 && tb.kind<=8 {tb=lexer::next(b,lb);}
        if ta.kind==9 || tb.kind==9 || ta.kind!=tb.kind {return false;}
        if ta.kind==0 {return true;}
        if !span(a,ta.start,ta.end,b,tb.start,tb.end) {return false;}
        ta=lexer::next(a,la);tb=lexer::next(b,lb);
    }
}
// The lexer visits source tokens in byte order. One-based offsets for lexical
// fn/for/if/else owners can therefore be normalized by binary-searching the
// corresponding significant-token ordinal; no byte offset is treated as a
// durable identity across formatting.
fn token_positions(s:u8[:]) -> i64[] {
    var state=lexer::init(s);var positions:i64[>..]=[];
    loop {let t=lexer::next(s,state);if t.kind==9 {return [];}if t.kind==0 {break;}
        if t.kind>=1 && t.kind<=5 {positions.push(t.start+1);}}
    return positions;
}
fn ordinal(positions:i64[:],offset:i64) -> i64 {
    var low:i64=0;var high=positions.len;
    while low<high {let mid=low+(high-low)/2;if positions[mid]<offset {low=mid+1;}else {high=mid;}}
    return if low<positions.len && positions[low]==offset {low+1} else {0};
}
fn scalar(a:unified_core::Program&,b:unified_core::Program&) -> bool {
    if a.nodes.len!=b.nodes.len || a.bindings.len!=b.bindings.len || a.root!=b.root ||
       !span(a.source,a.name_start,a.name_end,b.source,b.name_start,b.name_end) ||
       !span(a.source,a.param_start,a.param_end,b.source,b.param_start,b.param_end) {return false;}
    for n,i in a.nodes {let m=b.nodes[i];
        if n.tag!=m.tag || n.a!=m.a || n.b!=m.b || n.c!=m.c || n.literal!=m.literal || n.ty!=m.ty {return false;}}
    for x,i in a.bindings {let y=b.bindings[i];if !span(a.source,x.start,x.end,b.source,y.start,y.end) {return false;}}
    return true;
}
fn iteration(a:iteration_core::Tree&,b:iteration_core::Tree&) -> bool {
    if a.nodes.len!=b.nodes.len || a.bindings.len!=b.bindings.len || a.root!=b.root {return false;}
    let pa=token_positions(a.source);let pb=token_positions(b.source);
    if pa.len==0 || pa.len!=pb.len {return false;}
    for n,i in a.nodes {let m=b.nodes[i];
        if n.tag!=m.tag || n.a!=m.a || n.b!=m.b || n.c!=m.c || n.d!=m.d || n.e!=m.e || n.f!=m.f || n.g!=m.g {return false;}
        if (n.target==0)!=(m.target==0) {return false;}
        if n.target!=0 {let x=ordinal(pa,n.target);if x==0 || x!=ordinal(pb,m.target) {return false;}}
    }
    for x,i in a.bindings {let y=b.bindings[i];
        if x.kind!=y.kind || !span(a.source,x.start,x.end,b.source,y.start,y.end) {return false;}
        let scope=ordinal(pa,x.scope);if scope==0 || scope!=ordinal(pb,y.scope) {return false;}
    }
    return true;
}
fn equivalent(a:compiler_core::Program&,b:compiler_core::Program&) -> bool {
    if a.variant!=b.variant || !compiler_validate::verify(a.source,a) || !compiler_validate::verify(b.source,b) || !tokens(a.source,b.source) {return false;}
    if a.variant==1 {if !scalar(a.scalar,b.scalar) {return false;}}
    else if a.variant==2 {
        if !span(a.source,a.name_start,a.name_end,b.source,b.name_start,b.name_end) || !iteration(a.body,b.body) {return false;}
    } else {return false;}
    let x=compiler_wasm::emit(a.source,a);let y=compiler_wasm::emit(b.source,b);
    return x.len>0 && x[..]==y[..];
}
