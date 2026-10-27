// Independent whole-source/header, lexical-target and narrow type/proof
// admission for a private U32 iteration fixture. This is not general K1
// type/effect/ownership validation, portable evidence or C09 work accounting.
namespace mixed_validate;
import lexer;
import validate;
import mixed_core;
import mixed_fact_build;
import mixed_fact_verify;
import mixed_verify;
import mixed_completion;
import unified_check;
import mixed_compiler_core;

struct Reader {lex:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},bad:bool=false}
fn step(s:u8[:],r:Reader&) {if !r.bad {r.t=lexer::next(s,r.lex);if r.t.kind==9 {r.bad=true;}}}
fn text(s:u8[:],t:lexer::Token,k:i64,v:u8[:]) -> bool {return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==v;}
fn take(s:u8[:],r:Reader&,k:i64,v:u8[:]) -> bool {if r.bad || !text(s,r.t,k,v) {r.bad=true;return false;}step(s,r);return !r.bad;}
fn id(s:u8[:],t:lexer::Token) -> bool {return t.kind==1 && t.start>=0 && t.end>t.start && t.end<=s.len && validate::name_valid(s[t.start..t.end]);}
// 1 U32, 2 Bool, 3 statement / Unit loop, 4 single-carry descriptor.
fn known(types:u8[:],id:i64) -> u8 {if id<1 || id>types.len {return 0;}return types[id-1];}
fn lit(s:u8[:],n:mixed_core::Node) -> u64,bool {
    if n.tag!=2 || n.start<0 || n.end<=n.start || n.end>s.len {return 0,false;}
    var value:u64=0;
    for k in n.start..n.end {let c=s[k];if c<'0' || c>'9' {return 0,false;}let d=(c-'0') as u64;
        if value>(4294967295-d)/10 {return 0,false;}value=value*10+d;}
    return value,true;
}
// Independent admission recomputes the only supported range proofs: 0 <= a
// U32 value, and exact literal comparison. A dynamic nonzero lower bound is not
// assumed safe, and an invalid literal interval never becomes an empty loop.
fn range(tree:mixed_core::Tree&,lo:i64,hi:i64) -> bool {
    if lo<1 || hi<1 || lo>tree.nodes.len || hi>tree.nodes.len {return false;}
    let a, a_lit=lit(tree.source,tree.nodes[lo-1]);
    if !a_lit {return false;}
    if a==0 {return true;}
    let b,b_lit=lit(tree.source,tree.nodes[hi-1]);return b_lit && a<=b;
}
fn semantic(tree:mixed_core::Tree&) -> bool {
    if tree.nodes.len<1 || tree.nodes.len>2048 || tree.bindings.len<1 || tree.bindings.len>128 ||
       tree.root<1 || tree.root>tree.nodes.len || tree.bindings[0].kind!=1 {return false;}
    var types:u8[>..]=[];var depths:i64[>..]=[];var loops:i64=0;
    for n in tree.nodes {
        var ty:u8=0;
        if n.tag==1 {
            if n.a<1 || n.a>tree.bindings.len {return false;}
            let b=tree.bindings[n.a-1];if b.kind<1 || b.kind>4 {return false;}ty=1;
        } else if n.tag==2 {let _,ok=lit(tree.source,n);if !ok {return false;}ty=1;}
        else if n.tag==3 || n.tag==4 {ty=2;}
        else if n.tag==6 {
            if known(types,n.a)!=1 || n.b<1 || n.b>tree.bindings.len || tree.bindings[n.b-1].kind!=3 {return false;}
            ty=4;
        } else if n.tag==9 || n.tag==10 {
            if n.b!=1 || known(types,n.a)!=1 {return false;}ty=3;
        } else if n.tag==11 || n.tag==12 {ty=3;}
        else if n.tag==13 {if known(types,n.a)!=1 {return false;}ty=3;}
        else if n.tag==14 {
            if known(types,n.a)!=2 || known(types,n.b)!=3 || (n.c!=0 && known(types,n.c)!=3) {return false;}ty=3;
        } else if n.tag==15 {
            loops+=1;if loops>128 || n.g<0 || n.g>1 || n.d!=0 || known(types,n.a)!=1 || known(types,n.b)!=1 ||
               known(types,n.e)!=3 || n.f<1 || n.f>tree.bindings.len || tree.bindings[n.f-1].kind!=2 || !range(tree,n.a,n.b) {return false;}
            if n.g==0 {if n.c!=0 {return false;}ty=3;}
            else {if known(types,n.c)!=4 {return false;}ty=1;}
        } else if n.tag==16 {
            if known(types,n.a)!=1 || n.b<1 || n.b>tree.bindings.len || tree.bindings[n.b-1].kind!=4 {return false;}ty=3;
        } else if n.tag==17 {if known(types,n.a)!=3 || known(types,n.b)!=3 {return false;}ty=3;}
        else if n.tag==18 {
            if n.b!=1 || known(types,n.a)!=3 {return false;}ty=3;
        } else if n.tag==19 || n.tag==21 {
            if known(types,n.a)!=1 || known(types,n.b)!=1 {return false;}
            // Checked-add safety is independently reconstructed after type
            // and source checks by the mixed fact producer and consumer.
            ty=1;
        } else if n.tag==20 {ty=known(types,n.a);if ty!=1 && ty!=2 {return false;}}
        else if n.tag==22 {if known(types,n.a)!=1 || known(types,n.b)!=1 {return false;}ty=2;}
        else {return false;}
        var expr_depth:i64=0;
        if n.tag>=1 && n.tag<=4 {expr_depth=1;}
        else if n.tag==20 {expr_depth=depths[n.a-1]+1;}
        else if n.tag==19 || n.tag==21 || n.tag==22 {
            expr_depth=if depths[n.a-1]>depths[n.b-1] {depths[n.a-1]+1} else {depths[n.b-1]+1};
        }
        if expr_depth>128 {return false;}
        types.push(ty);depths.push(expr_depth);
    }
    return tree.nodes[tree.root-1].tag==18 && known(types,tree.root)==3;
}
fn verify(expected:u8[:],p:mixed_compiler_core::Program&) -> bool {
    if expected.len>16777216 || p.source!=expected {return false;}
    if p.variant==1 {
        if p.name_start!=0 || p.name_end!=0 || p.fn_start!=0 || p.body.source.len!=0 ||
           p.body.nodes.len!=0 || p.body.bindings.len!=0 || p.body.root!=0 {return false;}
        return unified_check::verify(expected,p.scalar);
    }
    if p.variant!=2 || expected.len>65536 || p.scalar.source.len!=0 || p.scalar.name_start!=0 || p.scalar.name_end!=0 ||
       p.scalar.param_start!=0 || p.scalar.param_end!=0 || p.scalar.nodes.len!=0 ||
       p.scalar.bindings.len!=0 || p.scalar.root!=0 {return false;}
    let s=expected;var r=Reader {lex:lexer::init(s)};step(s,r);
    while !r.bad && r.t.kind==6 {step(s,r);}
    if !take(s,r,1,"let") {return false;}let name=r.t;
    if !id(s,name) || name.start!=p.name_start || name.end!=p.name_end {return false;}step(s,r);
    if !take(s,r,5,":") || !take(s,r,1,"U32") || !take(s,r,5,"->") || !take(s,r,1,"U32") || !take(s,r,5,"=") {return false;}
    if r.bad || !text(s,r.t,1,"fn") || r.t.start!=p.fn_start || p.fn_start<0 || p.fn_start>s.len {return false;}
    step(s,r);let param=r.t;if !id(s,param) {return false;}step(s,r);
    if !text(s,r.t,5,"=>") {return false;}
    let suffix=s[p.fn_start..];
    if p.body.source!=suffix || !mixed_verify::verify(p.body,suffix) || mixed_completion::check(p.body,suffix)!=0 {return false;}
    if p.body.bindings.len<1 || p.body.bindings[0].start!=param.start-p.fn_start ||
       p.body.bindings[0].end!=param.end-p.fn_start {return false;}
    if !semantic(p.body) {return false;}
    let proof=mixed_fact_build::build(p.body);return proof.status==0 && mixed_fact_verify::verify(p.body,suffix,proof.events);
}
