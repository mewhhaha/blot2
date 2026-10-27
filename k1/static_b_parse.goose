// Private single static-let scalar producer. Float literals are deliberately
// restricted to exact nonnegative N.0 (N<=2^24) and N.5 (N<2^23); unary minus
// is F32-only. General decimal/exponent conversion and declarations are not
// implemented. This producer performs no admission or required evaluation.
namespace static_b_parse;
import lexer;
import lexer_m;
import static_m_name;
import validate;
import static_core;
import static_m_core;
import work;
struct Cursor {lex:lexer_m::State=lexer_m::State {},t:lexer::Token=lexer::Token {},status:i64=0,depth:i64=0,meter:work::Meter=work::Meter {}}
fn charged(c:Cursor&,event:u32)->bool {
    if c.status!=0{return false;}let receipt=work::charge(c.meter,1,event);
    if receipt.status!=0 {c.status=if receipt.status==1 {4} else {5};return false;}return true;
}
fn step(s:u8[:],c:Cursor&) {if c.status==0 {
    if !charged(c,1) {return;}
    c.lex.meter=c.meter;c.t=lexer_m::next(s,c.lex);c.meter=c.lex.meter;
    if c.lex.work_status!=0 {c.status=if c.lex.work_status==5 {5} else {6};return;}
    if c.t.kind==9 {c.status=1;}
}}
fn byte(s:u8[:],i:i64,c:Cursor&)->u8 {
    if c.status!=0{return 0;}let receipt=work::source_read(c.meter,1);
    if receipt.status!=0 {c.status=if receipt.status==5 {5} else {6};return 0;}return s[i];
}
fn eq(s:u8[:],c:Cursor&,t:lexer::Token,k:i64,v:u8[:]) -> bool {
    if c.status!=0 || t.kind!=k || t.start<0 || t.end<=t.start || t.end>s.len || t.end-t.start!=v.len{return false;}
    for i in v.len {let ch=byte(s,t.start+i,c);if c.status!=0 || ch!=v[i] {return false;}}return true;
}
fn take(s:u8[:],c:Cursor&,k:i64,v:u8[:]) -> bool {if c.status!=0 || !eq(s,c,c.t,k,v) {if c.status==0 {c.status=1;}return false;}step(s,c);return c.status==0;}
fn push(c:Cursor&,nodes:static_core::Node[>..]&,n:static_core::Node) -> i64 {
    if c.status!=0{return 0;}if nodes.len>=200000 {c.status=2;return 0;}
    if !charged(c,2){return 0;}
    if !charged(c,6){return 0;}
    nodes.push(n);return nodes.len;
}
fn peek(c:Cursor&,nodes:static_core::Node[:],id:i64)->static_core::Node {
    if c.status!=0 || id<1 || id>nodes.len {return static_core::Node {};}
    if !charged(c,3){return static_core::Node {};}
    return nodes[id-1];
}
fn read_ty(c:Cursor&,nodes:static_core::Node[:],id:i64)->i64 {
    let n=peek(c,nodes,id);if c.status!=0{return 0;}
    if !charged(c,6){return 0;}return n.ty;
}
fn integer(s:u8[:],t:lexer::Token,c:Cursor&) -> u32,bool {
    if t.start<0 || t.end<=t.start || t.end>s.len {return 0,false;}var n:u64=0;
    for i in t.start..t.end {let ch=byte(s,i,c);if ch<'0' || ch>'9' {return 0,false;}let d=(ch-'0') as u64;if n>(4294967295-d)/10 {return 0,false;}n=n*10+d;}
    return n as u32,true;
}
fn floating(s:u8[:],t:lexer::Token,c:Cursor&) -> u32,bool,bool {
    if t.start<0 || t.end<=t.start || t.end>s.len {return 0,false,false;}
    var dot=t.start;while dot<t.end && byte(s,dot,c)>='0' && byte(s,dot,c)<='9' {dot+=1;}
    if dot==t.start || dot+2!=t.end || byte(s,dot,c)!='.' || (byte(s,dot+1,c)!='0' && byte(s,dot+1,c)!='5') {return 0,false,false;}
    let n,ok=integer(s,lexer::Token {start:t.start,end:dot},c);let half=byte(s,dot+1,c)=='5';
    if !ok || (half && n>=8388608) || (!half && n>16777216) {return 0,false,false;}
    return n,half,true;
}
recursive fn primary(s:u8[:],c:Cursor&,nodes:static_core::Node[>..]&) -> i64 {
    if c.status!=0 {return 0;}
    if c.depth>=64 {c.status=2;return 0;}c.depth+=1;let t=c.t;var result:i64=0;
    if t.kind==2 {let n,ok=integer(s,t,c);if !ok {if c.status==0 {c.status=1;}}else {step(s,c);result=push(c,nodes,static_core::Node {tag:1,ty:1,start:t.start,end:t.end,literal:n});}}
    else if t.kind==3 {let n,half,ok=floating(s,t,c);if !ok {if c.status==0 {c.status=1;}}else {step(s,c);result=push(c,nodes,static_core::Node {tag:2,ty:2,start:t.start,end:t.end,literal:n,half:half});}}
    else if eq(s,c,t,5,"-") {step(s,c);let a=primary(s,c,nodes);if a!=0 {if read_ty(c,nodes,a)!=2 {if c.status==0 {c.status=3;}}else {result=push(c,nodes,static_core::Node {tag:4,ty:2,start:t.start,end:peek(c,nodes,a).end,a:a});}}}
    else if eq(s,c,t,5,"(") {step(s,c);let a=expression(s,c,nodes);let end=c.t.end;if a!=0 && take(s,c,5,")") {result=push(c,nodes,static_core::Node {tag:3,ty:read_ty(c,nodes,a),start:t.start,end:end,a:a});}}
    else if eq(s,c,t,1,"U32") {
        step(s,c);if take(s,c,5,".") {
            var tag:i64=0;if eq(s,c,c.t,1,"wrapping_add") {tag=10;}else if eq(s,c,c.t,1,"wrapping_sub") {tag=11;}else if eq(s,c,c.t,1,"wrapping_mul") {tag=12;}
            if tag==0 {if c.status==0 {c.status=1;}}else {step(s,c);if take(s,c,5,"(") {let a=expression(s,c,nodes);if a!=0 && take(s,c,5,",") {
                let b=expression(s,c,nodes);let end=c.t.end;if b!=0 && take(s,c,5,")") {
                    if read_ty(c,nodes,a)!=1 || read_ty(c,nodes,b)!=1 {if c.status==0 {c.status=3;}}else {result=push(c,nodes,static_core::Node {tag:tag,ty:1,start:t.start,end:end,a:a,b:b});}
                }
            }}}
        }
    } else {if c.status==0 {c.status=1;}}
    c.depth-=1;return result;
}
fn multiply(s:u8[:],c:Cursor&,nodes:static_core::Node[>..]&) -> i64 {
    var a=primary(s,c,nodes);
    while c.status==0 && (eq(s,c,c.t,5,"*") || eq(s,c,c.t,5,"/")) {
        let op=if eq(s,c,c.t,5,"*") {7} else {8};step(s,c);let b=primary(s,c,nodes);if a==0 || b==0 || c.status!=0 {return 0;}
        if read_ty(c,nodes,a)!=read_ty(c,nodes,b) || (op==8 && read_ty(c,nodes,a)!=2) {if c.status==0 {c.status=3;}return 0;}
        a=push(c,nodes,static_core::Node {tag:op,ty:read_ty(c,nodes,a),start:peek(c,nodes,a).start,end:peek(c,nodes,b).end,a:a,b:b});
    }return a;
}
fn add(s:u8[:],c:Cursor&,nodes:static_core::Node[>..]&) -> i64 {
    var a=multiply(s,c,nodes);
    while c.status==0 && (eq(s,c,c.t,5,"+") || eq(s,c,c.t,5,"-")) {
        let op=if eq(s,c,c.t,5,"+") {5} else {6};step(s,c);let b=multiply(s,c,nodes);if a==0 || b==0 || c.status!=0 {return 0;}
        if read_ty(c,nodes,a)!=read_ty(c,nodes,b) {if c.status==0 {c.status=3;}return 0;}
        a=push(c,nodes,static_core::Node {tag:op,ty:read_ty(c,nodes,a),start:peek(c,nodes,a).start,end:peek(c,nodes,b).end,a:a,b:b});
    }return a;
}
recursive fn expression(s:u8[:],c:Cursor&,nodes:static_core::Node[>..]&) -> i64 {
    var a=add(s,c,nodes);
    while c.status==0 && eq(s,c,c.t,5,"&") {
        step(s,c);let b=add(s,c,nodes);if a==0 || b==0 || c.status!=0 {return 0;}
        if read_ty(c,nodes,a)!=1 || read_ty(c,nodes,b)!=1 {if c.status==0 {c.status=3;}return 0;}
        a=push(c,nodes,static_core::Node {tag:9,ty:1,start:peek(c,nodes,a).start,end:peek(c,nodes,b).end,a:a,b:b});
    }return a;
}
fn parse(s:u8[:],meter:work::Meter) -> static_m_core::Result {
    var lex=lexer_m::init(s,meter);var c=Cursor {lex:lex,meter:lex.meter};if lex.work_status!=0 {return static_m_core::Result {meter:c.meter,status:if lex.work_status==5 {5} else {6}};}var nodes:static_core::Node[>..]=[];step(s,c);
    if !take(s,c,1,"static") || !take(s,c,1,"let") {return static_m_core::Result {meter:c.meter,status:c.status};}
    let name=c.t;if name.kind!=1 || name.start<0 || name.end<=name.start || name.end>s.len {return static_m_core::Result {meter:c.meter};}
    let checked=static_m_name::check(s[name.start..name.end],c.meter);
    if checked.work_status!=0{return static_m_core::Result {meter:c.meter,status:if checked.work_status==5 {5} else {6}};}
    if !checked.valid{return static_m_core::Result {meter:c.meter};}
    step(s,c);if !take(s,c,5,":") {return static_m_core::Result {meter:c.meter,status:c.status};}
    var ty:i64=0;if eq(s,c,c.t,1,"U32") {ty=1;}else if eq(s,c,c.t,1,"F32") {ty=2;}else {return static_m_core::Result {meter:c.meter,status:if c.status==0 {1} else {c.status}};}
    step(s,c);if !take(s,c,5,"=") {return static_m_core::Result {meter:c.meter,status:c.status};}
    let root=expression(s,c,nodes);if root==0 || c.status!=0 {return static_m_core::Result {meter:c.meter,status:if c.status==0 {1} else {c.status}};}
    if read_ty(c,nodes,root)!=ty {return static_m_core::Result {meter:c.meter,status:if c.status==4 || c.status==5 || c.status==6 {c.status} else {3}};}
    while c.t.kind==6 && c.status==0 {step(s,c);}
    if c.status!=0 || c.t.kind!=0 {return static_m_core::Result {meter:c.meter,status:if c.status==4 || c.status==5 || c.status==6 {c.status} else {1}};}
    return static_m_core::Result {meter:c.meter,status:0,tree:static_core::Tree {source:s,name_start:name.start,name_end:name.end,ty:ty,nodes:nodes,root:root}};
}
