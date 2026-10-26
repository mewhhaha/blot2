// Bounded source producer only. Names, lexical loans, control and authority
// are checked separately. The syntax is a deliberately restricted K1 body.
namespace ownership_parse;
import lexer;
import validate;
import ownership_syntax;
struct Cursor {lex:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},status:i64=0,depth:i64=0,previous:i64=0}
fn step(s:u8[:],c:Cursor&) {if c.status==0 {c.previous=c.t.end;c.t=lexer::next(s,c.lex);if c.t.kind==9 {c.status=1;}}}
fn eq(s:u8[:],t:lexer::Token,k:i64,v:u8[:]) -> bool {return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==v;}
fn word(s:u8[:],c:Cursor&,k:i64,v:u8[:]) -> bool {if c.status!=0 || !eq(s,c.t,k,v) {c.status=1;return false;}step(s,c);return c.status==0;}
fn kind(s:u8[:],c:Cursor&,k:i64) -> bool {if c.status!=0 || c.t.kind!=k {c.status=1;return false;}step(s,c);return c.status==0;}
fn name(s:u8[:],c:Cursor&) -> lexer::Token {
    let t=c.t;
    if c.status!=0 || t.kind!=1 || t.start<0 || t.end<=t.start || t.end>s.len || !validate::name_valid(s[t.start..t.end]) {c.status=1;return lexer::Token {kind:9};}
    step(s,c);return t;
}
fn binding(c:Cursor&, b:ownership_syntax::Binding[>..]&, t:lexer::Token) -> i64 {
    if c.status!=0 || t.kind==9 {return 0;} if b.len>=128 {c.status=2;return 0;}
    b.push(ownership_syntax::Binding {start:t.start,end:t.end});return b.len;
}
fn push(c:Cursor&,n:ownership_syntax::Node[>..]&,x:ownership_syntax::Node) -> i64 {
    if c.status!=0 {return 0;} if n.len>=256 {c.status=2;return 0;} n.push(x);return n.len;
}
fn line(s:u8[:],c:Cursor&) -> bool {if c.t.kind==6 {return kind(s,c,6);}return c.status==0 && (c.t.kind==8 || c.t.kind==0);}
recursive fn suite(s:u8[:],c:Cursor&,n:ownership_syntax::Node[>..]&,b:ownership_syntax::Binding[>..]&) -> i64 {
    if c.depth>=32 {c.status=2;return 0;}c.depth+=1;var list:i64=0;
    while c.status==0 && c.t.kind!=8 && c.t.kind!=0 {
        if c.t.kind==6 {step(s,c);continue;}let v=stmt(s,c,n,b);if v==0 || c.status!=0 {break;}
        if list==0 {list=v;}else {list=push(c,n,ownership_syntax::Node {tag:8,start:n[list-1].start,end:n[v-1].end,a:list,b:v});}
    }
    c.depth-=1;if list==0 && c.status==0 {c.status=1;}return list;
}
recursive fn stmt(s:u8[:],c:Cursor&,n:ownership_syntax::Node[>..]&,b:ownership_syntax::Binding[>..]&) -> i64 {
    let start=c.t.start;
    if eq(s,c.t,1,"let") {
        step(s,c);let bound=binding(c,b,name(s,c));if bound==0 || !word(s,c,5,"=") {return 0;}
        if eq(s,c.t,1,"owned") {
            step(s,c);if !word(s,c,5,".") || !word(s,c,1,"open") || !word(s,c,5,"(") {return 0;}
            let ref=name(s,c);if ref.kind==9 || !word(s,c,5,")") || !word(s,c,1,"as") {return 0;}
            let region=binding(c,b,name(s,c));let payload=binding(c,b,name(s,c));
            if region==0 || payload==0 || !word(s,c,1,"in") || !word(s,c,1,"do") || !word(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) {return 0;}
            let body=suite(s,c,n,b);if body==0 || !kind(s,c,8) {return 0;}
            return push(c,n,ownership_syntax::Node {tag:3,start:start,end:n[body-1].end,ref_start:ref.start,ref_end:ref.end,a:body,bound:bound,region:region,payload:payload});
        }
        let ref=name(s,c);if ref.kind==9 || !line(s,c) {c.status=1;return 0;}
        return push(c,n,ownership_syntax::Node {tag:1,start:start,end:ref.end,ref_start:ref.start,ref_end:ref.end,bound:bound});
    }
    if eq(s,c.t,1,"owned") {
        step(s,c);if !word(s,c,5,".") || !word(s,c,1,"close") || !word(s,c,5,"(") {return 0;}
        let ref=name(s,c);if ref.kind==9 || !eq(s,c.t,5,")") {c.status=1;return 0;}
        let end=c.t.end;step(s,c);if !line(s,c) {c.status=1;return 0;}
        return push(c,n,ownership_syntax::Node {tag:2,start:start,end:end,ref_start:ref.start,ref_end:ref.end});
    }
    if eq(s,c.t,1,"if") {
        step(s,c);let cond=name(s,c);if cond.kind==9 || !word(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) {return 0;}
        let yes=suite(s,c,n,b);if yes==0 || !kind(s,c,8) {return 0;}var no:i64=0;
        if eq(s,c.t,1,"else") {step(s,c);if !word(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) {return 0;}no=suite(s,c,n,b);if no==0 || !kind(s,c,8) {return 0;}}
        return push(c,n,ownership_syntax::Node {tag:4,start:start,end:if no!=0 {n[no-1].end} else {n[yes-1].end},ref_start:cond.start,ref_end:cond.end,a:yes,b:no});
    }
    if eq(s,c.t,1,"return") {
        step(s,c);
        if eq(s,c.t,5,"(") {step(s,c);if !eq(s,c.t,5,")") {c.status=1;return 0;}let end=c.t.end;step(s,c);if !line(s,c) {c.status=1;return 0;}
            return push(c,n,ownership_syntax::Node {tag:5,start:start,end:end});}
        let ref=name(s,c);if ref.kind==9 || !line(s,c) {c.status=1;return 0;}
        return push(c,n,ownership_syntax::Node {tag:6,start:start,end:ref.end,ref_start:ref.start,ref_end:ref.end});
    }
    if eq(s,c.t,1,"break") {
        step(s,c);let ref=name(s,c);if ref.kind==9 || !line(s,c) {c.status=1;return 0;}
        return push(c,n,ownership_syntax::Node {tag:7,start:start,end:ref.end,ref_start:ref.start,ref_end:ref.end});
    }
    c.status=1;return 0;
}
fn parse(s:u8[:]) -> ownership_syntax::Result {
    var c=Cursor {lex:lexer::init(s)};var n:ownership_syntax::Node[>..]=[];var b:ownership_syntax::Binding[>..]=[];step(s,c);
    if !word(s,c,1,"do") || !word(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) {return ownership_syntax::Result {status:c.status};}
    let root=suite(s,c,n,b);if root==0 || !kind(s,c,8) || c.status!=0 || c.t.kind!=0 {return ownership_syntax::Result {status:if c.status==0 {1} else {c.status}};}
    return ownership_syntax::Result {status:0,tree:ownership_syntax::Tree {source:s,nodes:n,bindings:b,root:root}};
}
