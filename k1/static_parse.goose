// Private single static-let scalar producer. Float literals are deliberately
// restricted to exact nonnegative N.0 (N<=2^24) and N.5 (N<2^23); unary minus
// is F32-only. General decimal/exponent conversion and declarations are not
// implemented. This producer performs no admission or required evaluation.
namespace static_parse;
import lexer;
import validate;
import static_core;
struct Cursor {lex:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},status:i64=0,depth:i64=0}
fn step(s:u8[:],c:Cursor&) {if c.status==0 {c.t=lexer::next(s,c.lex);if c.t.kind==9 {c.status=1;}}}
fn eq(s:u8[:],t:lexer::Token,k:i64,v:u8[:]) -> bool {return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==v;}
fn take(s:u8[:],c:Cursor&,k:i64,v:u8[:]) -> bool {if c.status!=0 || !eq(s,c.t,k,v) {c.status=1;return false;}step(s,c);return c.status==0;}
fn push(c:Cursor&,nodes:static_core::Node[>..]&,n:static_core::Node) -> i64 {if nodes.len>=200000 {c.status=2;return 0;}nodes.push(n);return nodes.len;}
fn integer(s:u8[:],t:lexer::Token) -> u32,bool {
    if t.start<0 || t.end<=t.start || t.end>s.len {return 0,false;}var n:u64=0;
    for i in t.start..t.end {let ch=s[i];if ch<'0' || ch>'9' {return 0,false;}let d=(ch-'0') as u64;if n>(4294967295-d)/10 {return 0,false;}n=n*10+d;}
    return n as u32,true;
}
fn floating(s:u8[:],t:lexer::Token) -> u32,bool,bool {
    if t.start<0 || t.end<=t.start || t.end>s.len {return 0,false,false;}
    var dot=t.start;while dot<t.end && s[dot]>='0' && s[dot]<='9' {dot+=1;}
    if dot==t.start || dot+2!=t.end || s[dot]!='.' || (s[dot+1]!='0' && s[dot+1]!='5') {return 0,false,false;}
    let n,ok=integer(s,lexer::Token {start:t.start,end:dot});let half=s[dot+1]=='5';
    if !ok || (half && n>=8388608) || (!half && n>16777216) {return 0,false,false;}
    return n,half,true;
}
recursive fn primary(s:u8[:],c:Cursor&,nodes:static_core::Node[>..]&) -> i64 {
    if c.status!=0 {return 0;}
    if c.depth>=64 {c.status=2;return 0;}c.depth+=1;let t=c.t;var result:i64=0;
    if t.kind==2 {let n,ok=integer(s,t);if !ok {c.status=1;}else {step(s,c);result=push(c,nodes,static_core::Node {tag:1,ty:1,start:t.start,end:t.end,literal:n});}}
    else if t.kind==3 {let n,half,ok=floating(s,t);if !ok {c.status=1;}else {step(s,c);result=push(c,nodes,static_core::Node {tag:2,ty:2,start:t.start,end:t.end,literal:n,half:half});}}
    else if eq(s,t,5,"-") {step(s,c);let a=primary(s,c,nodes);if a!=0 {if nodes[a-1].ty!=2 {c.status=3;}else {result=push(c,nodes,static_core::Node {tag:4,ty:2,start:t.start,end:nodes[a-1].end,a:a});}}}
    else if eq(s,t,5,"(") {step(s,c);let a=expression(s,c,nodes);let end=c.t.end;if a!=0 && take(s,c,5,")") {result=push(c,nodes,static_core::Node {tag:3,ty:nodes[a-1].ty,start:t.start,end:end,a:a});}}
    else if eq(s,t,1,"U32") {
        step(s,c);if take(s,c,5,".") {
            var tag:i64=0;if eq(s,c.t,1,"wrapping_add") {tag=10;}else if eq(s,c.t,1,"wrapping_sub") {tag=11;}else if eq(s,c.t,1,"wrapping_mul") {tag=12;}
            if tag==0 {c.status=1;}else {step(s,c);if take(s,c,5,"(") {let a=expression(s,c,nodes);if a!=0 && take(s,c,5,",") {
                let b=expression(s,c,nodes);let end=c.t.end;if b!=0 && take(s,c,5,")") {
                    if nodes[a-1].ty!=1 || nodes[b-1].ty!=1 {c.status=3;}else {result=push(c,nodes,static_core::Node {tag:tag,ty:1,start:t.start,end:end,a:a,b:b});}
                }
            }}}
        }
    } else {c.status=1;}
    c.depth-=1;return result;
}
fn multiply(s:u8[:],c:Cursor&,nodes:static_core::Node[>..]&) -> i64 {
    var a=primary(s,c,nodes);
    while c.status==0 && (eq(s,c.t,5,"*") || eq(s,c.t,5,"/")) {
        let op=if eq(s,c.t,5,"*") {7} else {8};step(s,c);let b=primary(s,c,nodes);if a==0 || b==0 || c.status!=0 {return 0;}
        if nodes[a-1].ty!=nodes[b-1].ty || (op==8 && nodes[a-1].ty!=2) {c.status=3;return 0;}
        a=push(c,nodes,static_core::Node {tag:op,ty:nodes[a-1].ty,start:nodes[a-1].start,end:nodes[b-1].end,a:a,b:b});
    }return a;
}
fn add(s:u8[:],c:Cursor&,nodes:static_core::Node[>..]&) -> i64 {
    var a=multiply(s,c,nodes);
    while c.status==0 && (eq(s,c.t,5,"+") || eq(s,c.t,5,"-")) {
        let op=if eq(s,c.t,5,"+") {5} else {6};step(s,c);let b=multiply(s,c,nodes);if a==0 || b==0 || c.status!=0 {return 0;}
        if nodes[a-1].ty!=nodes[b-1].ty {c.status=3;return 0;}
        a=push(c,nodes,static_core::Node {tag:op,ty:nodes[a-1].ty,start:nodes[a-1].start,end:nodes[b-1].end,a:a,b:b});
    }return a;
}
recursive fn expression(s:u8[:],c:Cursor&,nodes:static_core::Node[>..]&) -> i64 {
    var a=add(s,c,nodes);
    while c.status==0 && eq(s,c.t,5,"&") {
        step(s,c);let b=add(s,c,nodes);if a==0 || b==0 || c.status!=0 {return 0;}
        if nodes[a-1].ty!=1 || nodes[b-1].ty!=1 {c.status=3;return 0;}
        a=push(c,nodes,static_core::Node {tag:9,ty:1,start:nodes[a-1].start,end:nodes[b-1].end,a:a,b:b});
    }return a;
}
fn parse(s:u8[:]) -> static_core::Result {
    var c=Cursor {lex:lexer::init(s)};var nodes:static_core::Node[>..]=[];step(s,c);
    if !take(s,c,1,"static") || !take(s,c,1,"let") {return static_core::Result {status:c.status};}
    let name=c.t;if name.kind!=1 || name.start<0 || name.end<=name.start || name.end>s.len || !validate::name_valid(s[name.start..name.end]) {return static_core::Result {};}
    step(s,c);if !take(s,c,5,":") {return static_core::Result {status:c.status};}
    var ty:i64=0;if eq(s,c.t,1,"U32") {ty=1;}else if eq(s,c.t,1,"F32") {ty=2;}else {return static_core::Result {};}
    step(s,c);if !take(s,c,5,"=") {return static_core::Result {status:c.status};}
    let root=expression(s,c,nodes);if root==0 || c.status!=0 {return static_core::Result {status:if c.status==0 {1} else {c.status}};}
    if nodes[root-1].ty!=ty {return static_core::Result {status:3};}
    while c.t.kind==6 && c.status==0 {step(s,c);}
    if c.status!=0 || c.t.kind!=0 {return static_core::Result {status:1};}
    return static_core::Result {status:0,tree:static_core::Tree {source:s,name_start:name.start,name_end:name.end,ty:ty,nodes:nodes,root:root}};
}
