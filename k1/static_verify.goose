// Independent exact-source and postorder operation recognizer for the private
// required-static subset. It reconstructs precedence, literal values, types,
// identifier and all node fields; it never invokes the producer parser.
namespace static_verify;
import lexer;
import validate;
import static_core;
struct Reader {lex:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},bad:bool=false,depth:i64=0,node:i64=0}
struct Term {id:i64=0,ty:i64=0,start:i64=0,end:i64=0}
fn step(s:u8[:],r:Reader&) {if !r.bad {r.t=lexer::next(s,r.lex);if r.t.kind==9 {r.bad=true;}}}
fn same(s:u8[:],t:lexer::Token,k:i64,v:u8[:]) -> bool {return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==v;}
fn word(s:u8[:],r:Reader&,k:i64,v:u8[:]) -> bool {if r.bad || !same(s,r.t,k,v) {r.bad=true;return false;}step(s,r);return !r.bad;}
fn event(r:Reader&,p:static_core::Tree&,want:static_core::Node) -> Term {
    if r.bad || r.node<0 || r.node>=p.nodes.len {r.bad=true;return Term {};}
    let got=p.nodes[r.node];r.node+=1;
    if got.tag!=want.tag || got.ty!=want.ty || got.start!=want.start || got.end!=want.end || got.a!=want.a || got.b!=want.b ||
       got.literal!=want.literal || got.half!=want.half {r.bad=true;return Term {};}
    return Term {id:r.node,ty:want.ty,start:want.start,end:want.end};
}
fn read_integer(s:u8[:],start:i64,end:i64) -> u32,bool {
    if start<0 || end<=start || end>s.len {return 0,false;}var n:u64=0;
    for i in start..end {let ch=s[i];if ch<'0' || ch>'9' {return 0,false;}let d=(ch-'0') as u64;if n>(4294967295-d)/10 {return 0,false;}n=n*10+d;}
    return n as u32,true;
}
recursive fn atom(s:u8[:],r:Reader&,p:static_core::Tree&) -> Term {
    if r.bad || r.depth>=64 {r.bad=true;return Term {};}r.depth+=1;let t=r.t;var out=Term {};
    if t.kind==2 {let v,ok=read_integer(s,t.start,t.end);if !ok {r.bad=true;}else {step(s,r);out=event(r,p,static_core::Node {tag:1,ty:1,start:t.start,end:t.end,literal:v});}}
    else if t.kind==3 {
        var dot=t.start;while dot<t.end && dot<s.len && s[dot]>='0' && s[dot]<='9' {dot+=1;}
        if t.start<0 || dot==t.start || dot+2!=t.end || t.end>s.len || s[dot]!='.' || (s[dot+1]!='0' && s[dot+1]!='5') {r.bad=true;}
        else {let v,ok=read_integer(s,t.start,dot);let half=s[dot+1]=='5';
            if !ok || (half && v>=8388608) || (!half && v>16777216) {r.bad=true;}
            else {step(s,r);out=event(r,p,static_core::Node {tag:2,ty:2,start:t.start,end:t.end,literal:v,half:half});}}
    } else if same(s,t,5,"-") {
        step(s,r);let a=atom(s,r,p);if a.id==0 || a.ty!=2 {r.bad=true;}else {out=event(r,p,static_core::Node {tag:4,ty:2,start:t.start,end:a.end,a:a.id});}
    } else if same(s,t,5,"(") {
        step(s,r);let a=expression(s,r,p);let end=r.t.end;if a.id!=0 && word(s,r,5,")") {out=event(r,p,static_core::Node {tag:3,ty:a.ty,start:t.start,end:end,a:a.id});}
    } else if same(s,t,1,"U32") {
        step(s,r);if word(s,r,5,".") {
            var tag:i64=0;if same(s,r.t,1,"wrapping_add") {tag=10;}else if same(s,r.t,1,"wrapping_sub") {tag=11;}else if same(s,r.t,1,"wrapping_mul") {tag=12;}
            if tag==0 {r.bad=true;}else {step(s,r);if word(s,r,5,"(") {let a=expression(s,r,p);if word(s,r,5,",") {
                let b=expression(s,r,p);let end=r.t.end;if word(s,r,5,")") {if a.ty!=1 || b.ty!=1 {r.bad=true;}else {out=event(r,p,static_core::Node {tag:tag,ty:1,start:t.start,end:end,a:a.id,b:b.id});}}
            }}}
        }
    } else {r.bad=true;}
    r.depth-=1;return out;
}
fn multiply(s:u8[:],r:Reader&,p:static_core::Tree&) -> Term {
    var a=atom(s,r,p);
    while !r.bad && (same(s,r.t,5,"*") || same(s,r.t,5,"/")) {
        let op=if same(s,r.t,5,"*") {7} else {8};step(s,r);let b=atom(s,r,p);
        if a.id==0 || b.id==0 || a.ty!=b.ty || (op==8 && a.ty!=2) {r.bad=true;return Term {};}
        a=event(r,p,static_core::Node {tag:op,ty:a.ty,start:a.start,end:b.end,a:a.id,b:b.id});
    }return a;
}
fn add(s:u8[:],r:Reader&,p:static_core::Tree&) -> Term {
    var a=multiply(s,r,p);
    while !r.bad && (same(s,r.t,5,"+") || same(s,r.t,5,"-")) {
        let op=if same(s,r.t,5,"+") {5} else {6};step(s,r);let b=multiply(s,r,p);
        if a.id==0 || b.id==0 || a.ty!=b.ty {r.bad=true;return Term {};}
        a=event(r,p,static_core::Node {tag:op,ty:a.ty,start:a.start,end:b.end,a:a.id,b:b.id});
    }return a;
}
recursive fn expression(s:u8[:],r:Reader&,p:static_core::Tree&) -> Term {
    var a=add(s,r,p);
    while !r.bad && same(s,r.t,5,"&") {
        step(s,r);let b=add(s,r,p);if a.id==0 || b.id==0 || a.ty!=1 || b.ty!=1 {r.bad=true;return Term {};}
        a=event(r,p,static_core::Node {tag:9,ty:1,start:a.start,end:b.end,a:a.id,b:b.id});
    }return a;
}
fn verify(s:u8[:],p:static_core::Tree&) -> bool {
    if s.len>16777216 || p.source[..]!=s || p.nodes.len<1 || p.nodes.len>200000 {return false;}
    var r=Reader {lex:lexer::init(s)};step(s,r);
    if !word(s,r,1,"static") || !word(s,r,1,"let") {return false;}
    let name=r.t;if name.kind!=1 || name.start<0 || name.end<=name.start || name.end>s.len ||
       name.start!=p.name_start || name.end!=p.name_end || !validate::name_valid(s[name.start..name.end]) {return false;}
    step(s,r);if !word(s,r,5,":") {return false;}
    var ty:i64=0;if same(s,r.t,1,"U32") {ty=1;}else if same(s,r.t,1,"F32") {ty=2;}else {return false;}
    step(s,r);if !word(s,r,5,"=") {return false;}
    let value=expression(s,r,p);while !r.bad && r.t.kind==6 {step(s,r);}
    return !r.bad && r.t.kind==0 && ty==p.ty && value.ty==ty && value.id==p.root && r.node==p.nodes.len;
}
