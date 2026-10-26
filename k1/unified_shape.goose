// Exact-source shape/type/scope/completion recognizer. Checked arithmetic is
// deliberately NOT established here. This helper alone grants no admission;
// consumers must use unified_check, which also rechecks scoped arithmetic facts.
namespace unified_shape;
import lexer;
import validate;
import unified_core;
struct Reader { lex:lexer::State=lexer::State {}, t:lexer::Token=lexer::Token {}, bad:bool=false, depth:i64=0, node:i64=0, binding:i64=0 }
struct Symbol {start:i64=0,end:i64=0,slot:i64=0}
struct Term {id:i64=0,start:i64=0,end:i64=0,ty:i64=0,tag:i64=0,literal:u32=0,truth:i64=0,falls:bool=true,unreachable:bool=false}
fn step(s:u8[:],r:Reader&) {if !r.bad {r.t=lexer::next(s,r.lex);if r.t.kind==9 {r.bad=true;}}}
fn same(s:u8[:],t:lexer::Token,k:i64,v:u8[:]) -> bool {return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==v;}
fn word(s:u8[:],r:Reader&,k:i64,v:u8[:]) -> bool {if r.bad || !same(s,r.t,k,v) {r.bad=true;return false;}step(s,r);return !r.bad;}
fn category(s:u8[:],r:Reader&,k:i64) -> bool {if r.bad || r.t.kind!=k {r.bad=true;return false;}step(s,r);return !r.bad;}
fn ident(s:u8[:],t:lexer::Token) -> bool {return t.kind==1 && t.start>=0 && t.end>t.start && t.end<=s.len && validate::name_valid(s[t.start..t.end]);}
fn open(r:Reader&) -> bool {if r.bad || r.depth>=64 {r.bad=true;return false;}r.depth+=1;return true;}
fn event(r:Reader&,p:unified_core::Program&,x:unified_core::Node) -> Term {
    if r.bad || r.node<0 || r.node>=p.nodes.len {r.bad=true;return Term {};}
    let y=p.nodes[r.node];r.node+=1;
    if y.tag!=x.tag || y.start!=x.start || y.end!=x.end || y.a!=x.a || y.b!=x.b || y.c!=x.c || y.literal!=x.literal || y.ty!=x.ty {r.bad=true;return Term {};}
    return Term {id:r.node,start:x.start,end:x.end,ty:x.ty,tag:x.tag,literal:x.literal};
}
fn find(s:u8[:],t:lexer::Token,syms:Symbol[:]) -> i64 {if !ident(s,t) {return -1;}for v in syms {if s[v.start..v.end]==s[t.start..t.end] {return v.slot;}}return -1;}
fn atom(s:u8[:],r:Reader&,p:unified_core::Program&,syms:Symbol[:]) -> Term {
    if !open(r) {return Term {};}let t=r.t;var out=Term {};
    if t.kind==2 {
        var n:u64=0;
        if t.start<0 || t.end<=t.start || t.end>s.len {r.bad=true;}
        else {for i in t.start..t.end {let c=s[i];if c<'0' || c>'9' {r.bad=true;break;}let d=(c-'0') as u64;if n>(4294967295-d)/10 {r.bad=true;break;}n=n*10+d;}
            step(s,r);out=event(r,p,unified_core::Node {tag:2,start:t.start,end:t.end,literal:n as u32,ty:1});}
    } else if same(s,t,5,"#") {
        step(s,r);let x=r.t;
        if x.start!=t.end || (!same(s,x,1,"True") && !same(s,x,1,"False")) {r.bad=true;}
        else {let yes=same(s,x,1,"True");step(s,r);out=event(r,p,unified_core::Node {tag:if yes {10} else {11},start:t.start,end:x.end,ty:2});out.truth=if yes {2} else {1};}
    } else if same(s,t,5,"(") {
        step(s,r);let v=expression(s,r,p,syms);let end=r.t.end;
        if word(s,r,5,")") {out=event(r,p,unified_core::Node {tag:8,start:t.start,end:end,a:v.id,ty:v.ty});out.truth=v.truth;}
    } else if same(s,t,1,"U32") {
        step(s,r);if word(s,r,5,".") {
            var k:i64=0;if same(s,r.t,1,"wrapping_add") {k=4;}else if same(s,r.t,1,"wrapping_sub") {k=5;}else if same(s,r.t,1,"wrapping_mul") {k=6;}
            if k==0 {r.bad=true;}else {step(s,r);if word(s,r,5,"(") {
                let a=expression(s,r,p,syms);if word(s,r,5,",") {let b=expression(s,r,p,syms);let end=r.t.end;
                    if word(s,r,5,")") {if a.ty!=1 || b.ty!=1 {r.bad=true;}else {out=event(r,p,unified_core::Node {tag:k,start:t.start,end:end,a:a.id,b:b.id,ty:1});}}
                }
            }}
        }
    } else if ident(s,t) {
        let slot=find(s,t,syms);if slot<0 {r.bad=true;}else {step(s,r);out=event(r,p,unified_core::Node {tag:1,start:t.start,end:t.end,a:slot,ty:1});}
    } else {r.bad=true;}
    r.depth-=1;return out;
}
fn add(s:u8[:],r:Reader&,p:unified_core::Program&,syms:Symbol[:]) -> Term {
    var a=atom(s,r,p,syms);
    while !r.bad && same(s,r.t,5,"+") {
        step(s,r);let b=atom(s,r,p,syms);
        if r.bad || a.ty!=1 || b.ty!=1 {r.bad=true;return Term {};}
        a=event(r,p,unified_core::Node {tag:3,start:a.start,end:b.end,a:a.id,b:b.id,ty:1});
    }return a;
}
fn bitand(s:u8[:],r:Reader&,p:unified_core::Program&,syms:Symbol[:]) -> Term {
    var a=add(s,r,p,syms);
    while !r.bad && same(s,r.t,5,"&") {step(s,r);let b=add(s,r,p,syms);if r.bad || a.ty!=1 || b.ty!=1 {r.bad=true;return Term {};}
        a=event(r,p,unified_core::Node {tag:7,start:a.start,end:b.end,a:a.id,b:b.id,ty:1});}return a;
}
fn comparison(s:u8[:],r:Reader&,p:unified_core::Program&,syms:Symbol[:]) -> Term {
    var a=bitand(s,r,p,syms);
    if !r.bad && same(s,r.t,5,"<") {step(s,r);let b=bitand(s,r,p,syms);if r.bad || a.ty!=1 || b.ty!=1 {r.bad=true;return Term {};}
        a=event(r,p,unified_core::Node {tag:9,start:a.start,end:b.end,a:a.id,b:b.id,ty:2});}return a;
}
fn conjunction(s:u8[:],r:Reader&,p:unified_core::Program&,syms:Symbol[:]) -> Term {
    var a=comparison(s,r,p,syms);
    while !r.bad && same(s,r.t,5,"&&") {step(s,r);let b=comparison(s,r,p,syms);if r.bad || a.ty!=2 || b.ty!=2 {r.bad=true;return Term {};}
        a=event(r,p,unified_core::Node {tag:12,start:a.start,end:b.end,a:a.id,b:b.id,ty:2});}return a;
}
recursive fn expression(s:u8[:],r:Reader&,p:unified_core::Program&,syms:Symbol[:]) -> Term {
    var a=conjunction(s,r,p,syms);
    while !r.bad && same(s,r.t,5,"||") {step(s,r);let b=conjunction(s,r,p,syms);if r.bad || a.ty!=2 || b.ty!=2 {r.bad=true;return Term {};}
        a=event(r,p,unified_core::Node {tag:13,start:a.start,end:b.end,a:a.id,b:b.id,ty:2});}return a;
}
fn line_end(s:u8[:],r:Reader&) -> bool {if r.bad {return false;}if r.t.kind==6 {step(s,r);return !r.bad;}return r.t.kind==8 || r.t.kind==0;}
recursive fn suite(s:u8[:],r:Reader&,p:unified_core::Program&,syms:Symbol[>..]&) -> Term {
    if !open(r) {return Term {};}let saved=syms.len;var list=Term {};
    while !r.bad && r.t.kind!=8 && r.t.kind!=0 {
        if r.t.kind==6 {step(s,r);continue;}let x=statement(s,r,p,syms);if r.bad {break;}
        if list.id==0 {list=x;}else {let a=list;list=event(r,p,unified_core::Node {tag:17,start:a.start,end:x.end,a:a.id,b:x.id,ty:3});list.falls=a.falls && x.falls;list.unreachable=a.unreachable || !a.falls || x.unreachable;}
    }
    if list.id==0 {r.bad=true;}while syms.len>saved {syms.pop();}r.depth-=1;return list;
}
fn statement(s:u8[:],r:Reader&,p:unified_core::Program&,syms:Symbol[>..]&) -> Term {
    let t=r.t;
    if same(s,t,1,"let") {
        step(s,r);let name=r.t;if !ident(s,name) || find(s,name,syms)>=0 || r.binding>=128 || r.binding>=p.bindings.len {r.bad=true;return Term {};}
        step(s,r);if same(s,r.t,5,":") {step(s,r);if !word(s,r,1,"U32") {return Term {};}}
        if !word(s,r,5,"=") {return Term {};}let x=expression(s,r,p,syms);
        if x.ty!=1 || !line_end(s,r) {r.bad=true;return Term {};}
        let got=p.bindings[r.binding];if got.start!=name.start || got.end!=name.end {r.bad=true;return Term {};}
        r.binding+=1;syms.push(Symbol {start:name.start,end:name.end,slot:r.binding});
        return event(r,p,unified_core::Node {tag:14,start:t.start,end:x.end,a:x.id,b:r.binding,ty:3});
    }
    if same(s,t,1,"return") {
        step(s,r);let x=expression(s,r,p,syms);if x.ty!=1 || !line_end(s,r) {r.bad=true;return Term {};}
        var result=event(r,p,unified_core::Node {tag:15,start:t.start,end:x.end,a:x.id,ty:3});result.falls=false;return result;
    }
    if same(s,t,1,"if") {
        step(s,r);let cond=expression(s,r,p,syms);
        if cond.ty!=2 || !word(s,r,5,":") || !category(s,r,6) || !category(s,r,7) {r.bad=true;return Term {};}
        let yes=suite(s,r,p,syms);if !category(s,r,8) {return Term {};}
        var no=Term {};
        if same(s,r.t,1,"else") {step(s,r);if !word(s,r,5,":") || !category(s,r,6) || !category(s,r,7) {return Term {};}
            no=suite(s,r,p,syms);if !category(s,r,8) {return Term {};}}
        var result=event(r,p,unified_core::Node {tag:16,start:t.start,end:if no.id!=0 {no.end} else {yes.end},a:cond.id,b:yes.id,c:no.id,ty:3});
        result.falls=if cond.truth==2 {yes.falls} else if cond.truth==1 {no.falls} else {yes.falls || no.falls};
        result.unreachable=yes.unreachable || no.unreachable;return result;
    }
    r.bad=true;return Term {};
}
fn verify(expected:u8[:],p:unified_core::Program&) -> bool {
    if expected.len>16777216 || p.source!=expected || p.nodes.len<1 || p.nodes.len>2048 || p.bindings.len>128 {return false;}
    let s=expected;var r=Reader {lex:lexer::init(s)};step(s,r);while !r.bad && r.t.kind==6 {step(s,r);}
    if !word(s,r,1,"let") {return false;}let name=r.t;
    if !ident(s,name) || name.start!=p.name_start || name.end!=p.name_end {return false;}step(s,r);
    if !word(s,r,5,":") || !word(s,r,1,"U32") || !word(s,r,5,"->") || !word(s,r,1,"U32") || !word(s,r,5,"=") || !word(s,r,1,"fn") {return false;}
    let param=r.t;if !ident(s,param) || param.start!=p.param_start || param.end!=p.param_end {return false;}
    var syms:Symbol[>..]=[Symbol {start:param.start,end:param.end,slot:0}];step(s,r);
    if !word(s,r,5,"=>") || !word(s,r,1,"do") || !word(s,r,5,":") || !category(s,r,6) || !category(s,r,7) {return false;}
    let body=suite(s,r,p,syms);if !category(s,r,8) {return false;}while !r.bad && r.t.kind==6 {step(s,r);}
    return !r.bad && r.t.kind==0 && body.id==p.root && !body.falls && !body.unreachable && r.node==p.nodes.len && r.binding==p.bindings.len;
}
