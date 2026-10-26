// Independent exact-source/tree recognizer; IDs, identifier spans, binding
// order, node shape and parentage are rebuilt rather than trusted as facts.
namespace ownership_verify;
import lexer;
import validate;
import ownership_syntax;
struct Scan {lex:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},bad:bool=false,previous:i64=0,
             seen:bool[256]=[false;256],visits:i64=0,next_binding:i64=0}
fn step(s:u8[:],r:Scan&) {if !r.bad {r.previous=r.t.end;r.t=lexer::next(s,r.lex);if r.t.kind==9 {r.bad=true;}}}
fn word(s:u8[:],r:Scan&,k:i64,text:u8[:]) -> bool {
    let t=r.t;if r.bad || t.kind!=k || t.start<0 || t.end<=t.start || t.end>s.len || s[t.start..t.end]!=text {r.bad=true;return false;}
    step(s,r);return !r.bad;
}
fn kind(s:u8[:],r:Scan&,k:i64) -> bool {if r.bad || r.t.kind!=k {r.bad=true;return false;}step(s,r);return !r.bad;}
fn line(s:u8[:],r:Scan&) -> bool {if r.t.kind==6 {return kind(s,r,6);}return !r.bad && (r.t.kind==8 || r.t.kind==0);}
fn valid_name(s:u8[:],t:lexer::Token) -> bool {return t.kind==1 && t.start>=0 && t.end>t.start && t.end<=s.len && validate::name_valid(s[t.start..t.end]);}
fn binding(s:u8[:],r:Scan&,tree:ownership_syntax::Tree&,id:i64) -> bool {
    if r.bad || id!=r.next_binding+1 || id<1 || id>tree.bindings.len || !valid_name(s,r.t) {return false;}
    let b=tree.bindings[id-1];if b.start!=r.t.start || b.end!=r.t.end {return false;}
    r.next_binding+=1;step(s,r);return !r.bad;
}
fn reference(s:u8[:],r:Scan&,n:ownership_syntax::Node) -> bool {
    if r.bad || !valid_name(s,r.t) || r.t.start!=n.ref_start || r.t.end!=n.ref_end {return false;}
    step(s,r);return !r.bad;
}
recursive fn node(s:u8[:],r:Scan&,t:ownership_syntax::Tree&,id:i64,depth:i64) -> bool {
    if r.bad || id<1 || id>t.nodes.len || depth>256 || r.seen[id-1] {return false;}
    r.seen[id-1]=true;r.visits+=1;let n=t.nodes[id-1];
    if n.start<0 || n.end<=n.start || n.end>s.len {return false;}
    if n.tag==8 {
        if n.ref_start!=0 || n.ref_end!=0 || n.bound!=0 || n.region!=0 || n.payload!=0 || n.a<1 || n.a>=id || n.b<1 || n.b>=id {return false;}
        let a=t.nodes[n.a-1];let b=t.nodes[n.b-1];
        return n.start==a.start && n.end==b.end && a.end<=b.start && node(s,r,t,n.a,depth+1) && node(s,r,t,n.b,depth+1);
    }
    if n.start!=r.t.start {return false;}
    if n.tag==1 {
        if n.a!=0 || n.b!=0 || n.region!=0 || n.payload!=0 || !word(s,r,1,"let") || !binding(s,r,t,n.bound) ||
           !word(s,r,5,"=") || !reference(s,r,n) {return false;}
        return n.end==r.previous && line(s,r);
    }
    if n.tag==2 {
        if n.a!=0 || n.b!=0 || n.bound!=0 || n.region!=0 || n.payload!=0 || !word(s,r,1,"owned") ||
           !word(s,r,5,".") || !word(s,r,1,"close") || !word(s,r,5,"(") || !reference(s,r,n) || !word(s,r,5,")") {return false;}
        return n.end==r.previous && line(s,r);
    }
    if n.tag==3 {
        if n.a<1 || n.a>=id || n.b!=0 || !word(s,r,1,"let") || !binding(s,r,t,n.bound) || !word(s,r,5,"=") ||
           !word(s,r,1,"owned") || !word(s,r,5,".") || !word(s,r,1,"open") || !word(s,r,5,"(") ||
           !reference(s,r,n) || !word(s,r,5,")") || !word(s,r,1,"as") || !binding(s,r,t,n.region) ||
           !binding(s,r,t,n.payload) || !word(s,r,1,"in") || !word(s,r,1,"do") || !word(s,r,5,":") ||
           !kind(s,r,6) || !kind(s,r,7) {return false;}
        return n.end==t.nodes[n.a-1].end && node(s,r,t,n.a,depth+1) && kind(s,r,8);
    }
    if n.tag==4 {
        if n.bound!=0 || n.region!=0 || n.payload!=0 || n.a<1 || n.a>=id || n.b<0 || n.b>=id ||
           !word(s,r,1,"if") || !reference(s,r,n) || !word(s,r,5,":") || !kind(s,r,6) || !kind(s,r,7) ||
           !node(s,r,t,n.a,depth+1) || !kind(s,r,8) {return false;}
        if n.b==0 {return n.end==t.nodes[n.a-1].end;}
        if !word(s,r,1,"else") || !word(s,r,5,":") || !kind(s,r,6) || !kind(s,r,7) || !node(s,r,t,n.b,depth+1) || !kind(s,r,8) {return false;}
        return n.end==t.nodes[n.b-1].end;
    }
    if n.tag==5 {
        if n.ref_start!=0 || n.ref_end!=0 || n.a!=0 || n.b!=0 || n.bound!=0 || n.region!=0 || n.payload!=0 ||
           !word(s,r,1,"return") || !word(s,r,5,"(") || !word(s,r,5,")") {return false;}
        return n.end==r.previous && line(s,r);
    }
    if n.tag==6 || n.tag==7 {
        if n.a!=0 || n.b!=0 || n.bound!=0 || n.region!=0 || n.payload!=0 ||
           !word(s,r,1,if n.tag==6 {"return"} else {"break"}) || !reference(s,r,n) {return false;}
        return n.end==r.previous && line(s,r);
    }
    return false;
}
fn verify(tree:ownership_syntax::Tree&) -> bool {
    if tree.source.len>16777216 || tree.nodes.len<1 || tree.nodes.len>256 || tree.bindings.len>128 || tree.root!=tree.nodes.len {return false;}
    let s=tree.source;var r=Scan {lex:lexer::init(s)};step(s,r);
    if !word(s,r,1,"do") || !word(s,r,5,":") || !kind(s,r,6) || !kind(s,r,7) || !node(s,r,tree,tree.root,0) ||
       !kind(s,r,8) || r.bad || r.t.kind!=0 {return false;}
    return r.visits==tree.nodes.len && r.next_binding==tree.bindings.len;
}
