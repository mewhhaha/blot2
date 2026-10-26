// Independent lexical/source-tree recognizer. Candidate IDs, spans, shape,
// parentage and every token are rechecked; no producer `validated` flag or
// source digest conveys authority. Only this restricted fixture is recognized.
namespace affine_verify;
import lexer;
import affine_syntax;
struct Scan { lex: lexer::State = lexer::State {}, t: lexer::Token = lexer::Token {}, bad: bool = false, previous: i64 = 0, seen: bool[256] = [false;256], visits:i64 = 0 }
fn step(s: u8[:], r: Scan&) { if !r.bad { r.previous = r.t.end; r.t = lexer::next(s,r.lex); if r.t.kind == 9 {r.bad=true;} } }
fn word(s: u8[:], r: Scan&, k: i64, text: u8[:]) -> bool {
    let t=r.t;
    if r.bad || t.kind != k || t.start < 0 || t.end <= t.start || t.end > s.len || s[t.start..t.end] != text { r.bad=true; return false; }
    step(s,r); return !r.bad;
}
fn kind(s: u8[:], r: Scan&, k: i64) -> bool { if r.bad || r.t.kind != k { r.bad=true; return false; } step(s,r); return !r.bad; }
fn line(s: u8[:], r: Scan&) -> bool { if r.t.kind == 6 {return kind(s,r,6);} return !r.bad && (r.t.kind == 8 || r.t.kind == 0); }
fn own(s: u8[:], r: Scan&, h:i64) -> bool { if h==1 { return word(s,r,1,"h"); } if h==2 {return word(s,r,1,"m");} return false; }
recursive fn node(s: u8[:], r: Scan&, tree: affine_syntax::Tree&, id:i64, depth:i64) -> bool {
    if r.bad || id < 1 || id > tree.nodes.len || depth > 256 || r.seen[id-1] { return false; }
    r.seen[id-1]=true; r.visits+=1;
    let n=tree.nodes[id-1];
    if n.start<0 || n.end<=n.start || n.end>s.len { return false; }
    if n.tag==8 {
        if n.owner!=0 || n.a<1 || n.a>=id || n.b<1 || n.b>=id { return false; }
        let a=tree.nodes[n.a-1]; let b=tree.nodes[n.b-1];
        return n.start==a.start && n.end==b.end && a.end<=b.start && node(s,r,tree,n.a,depth+1) && node(s,r,tree,n.b,depth+1);
    }
    if n.start!=r.t.start { return false; }
    if n.tag==1 {
        if n.owner!=1 || n.a!=0 || n.b!=0 || !word(s,r,1,"let") || !word(s,r,1,"m") || !word(s,r,5,"=") || !word(s,r,1,"h") { return false; }
        return n.end==r.previous && line(s,r);
    }
    if n.tag==2 {
        if n.a!=0 || n.b!=0 || !word(s,r,1,"owned") || !word(s,r,5,".") || !word(s,r,1,"close") ||
           !word(s,r,5,"(") || !own(s,r,n.owner) || !word(s,r,5,")") { return false; }
        return n.end==r.previous && line(s,r);
    }
    if n.tag==3 {
        if n.a<1 || n.a>=id || n.b!=0 || !word(s,r,1,"let") || !word(s,r,1,"value") || !word(s,r,5,"=") ||
           !word(s,r,1,"owned") || !word(s,r,5,".") || !word(s,r,1,"open") || !word(s,r,5,"(") || !own(s,r,n.owner) ||
           !word(s,r,5,")") || !word(s,r,1,"as") || !word(s,r,1,"r") || !word(s,r,1,"payload") ||
           !word(s,r,1,"in") || !word(s,r,1,"do") || !word(s,r,5,":") || !kind(s,r,6) || !kind(s,r,7) { return false; }
        let child=tree.nodes[n.a-1];
        return n.end==child.end && node(s,r,tree,n.a,depth+1) && kind(s,r,8);
    }
    if n.tag==4 {
        if n.owner!=0 || n.a<1 || n.a>=id || n.b<0 || n.b>=id || !word(s,r,1,"if") || !word(s,r,1,"flag") ||
           !word(s,r,5,":") || !kind(s,r,6) || !kind(s,r,7) || !node(s,r,tree,n.a,depth+1) || !kind(s,r,8) { return false; }
        if n.b==0 { return n.end==tree.nodes[n.a-1].end; }
        if !word(s,r,1,"else") || !word(s,r,5,":") || !kind(s,r,6) || !kind(s,r,7) || !node(s,r,tree,n.b,depth+1) || !kind(s,r,8) { return false; }
        return n.end==tree.nodes[n.b-1].end;
    }
    if n.tag==5 {
        if n.owner!=0 || n.a!=0 || n.b!=0 || !word(s,r,1,"return") || !word(s,r,5,"(") || !word(s,r,5,")") {return false;}
        return n.end==r.previous && line(s,r);
    }
    if n.tag==6 {
        if n.a!=0 || n.b!=0 || !word(s,r,1,"return") || !own(s,r,n.owner) {return false;}
        return n.end==r.previous && line(s,r);
    }
    if n.tag==7 {
        if n.owner!=0 || n.a!=0 || n.b!=0 || !word(s,r,1,"break") || !word(s,r,1,"payload") {return false;}
        return n.end==r.previous && line(s,r);
    }
    return false;
}
fn verify(tree: affine_syntax::Tree&) -> bool {
    if tree.source.len>16777216 || tree.nodes.len<1 || tree.nodes.len>256 || tree.root!=tree.nodes.len {return false;}
    let s=tree.source;
    var r=Scan {lex:lexer::init(s)}; step(s,r);
    if !word(s,r,1,"do") || !word(s,r,5,":") || !kind(s,r,6) || !kind(s,r,7) ||
       !node(s,r,tree,tree.root,0) || !kind(s,r,8) || r.bad || r.t.kind!=0 {return false;}
    return r.visits==tree.nodes.len;
}
