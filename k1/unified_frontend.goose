// Private U32/Bool source candidate; no K1 public admission or work receipt.
namespace unified_frontend;
import lexer;
import validate;
import unified_core;
import unified_completion;
struct Cursor { lex:lexer::State=lexer::State {}, t:lexer::Token=lexer::Token {}, status:i64=0, depth:i64=0 }
// Status 1 syntax/unsupported, 2 local limit, 3 unbound, 4 duplicate,
// 5 unproved addition, 6 type mismatch, 7 missing return, 8 unreachable.
// These are private fixture statuses, not qualified K1 diagnostics.
fn advance(s:u8[:], c:Cursor&) { if c.status == 0 { c.t=lexer::next(s,c.lex); if c.t.kind==9 { c.status=1; } } }
fn eq(s:u8[:], t:lexer::Token, k:i64, text:u8[:]) -> bool { return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==text; }
fn take(s:u8[:], c:Cursor&, k:i64, text:u8[:]) -> bool { if c.status!=0 || !eq(s,c.t,k,text) { if c.status==0 { c.status=1; } return false; } advance(s,c); return c.status==0; }
fn kind(s:u8[:], c:Cursor&, k:i64) -> bool { if c.status!=0 || c.t.kind!=k { if c.status==0 { c.status=1; } return false; } advance(s,c); return c.status==0; }
fn ident(s:u8[:], t:lexer::Token) -> bool { return t.kind==1 && t.start>=0 && t.end>t.start && t.end<=s.len && validate::name_valid(s[t.start..t.end]); }
fn enter(c:Cursor&) -> bool { if c.depth>=64 { c.status=2; return false; } c.depth+=1; return true; }
fn push(n:unified_core::Node[>..]&, c:Cursor&, x:unified_core::Node) -> i64 { if n.len>=2048 { c.status=2; return 0; } n.push(x); return n.len; }
fn find(s:u8[:], t:lexer::Token, param:lexer::Token, b:unified_core::Binding[:], active:i64[:]) -> i64 {
    if s[t.start..t.end]==s[param.start..param.end] { return 0; }
    for k in active { if s[t.start..t.end]==s[b[k-1].start..b[k-1].end] { return k; } }
    return -1;
}
fn fits(a:unified_core::Node, b:unified_core::Node) -> bool {
    return (a.tag==2 && a.literal==0) || (b.tag==2 && b.literal==0) ||
        (a.tag==2 && b.tag==2 && (a.literal as u64)+(b.literal as u64)<=4294967295);
}
fn primary(s:u8[:], c:Cursor&, n:unified_core::Node[>..]&, b:unified_core::Binding[:], active:i64[:], param:lexer::Token) -> i64 {
    if c.status!=0 || !enter(c) { return 0; }
    let t=c.t; var id:i64=0;
    if t.kind==2 {
        var x:u64=0; for ch in s[t.start..t.end] { x=x*10+(ch-'0') as u64; }
        advance(s,c); id=push(n,c,unified_core::Node { tag:2,start:t.start,end:t.end,literal:x as u32,ty:1 });
    } else if eq(s,t,5,"#") {
        advance(s,c); let v=c.t;
        if v.start!=t.end || (!eq(s,v,1,"True") && !eq(s,v,1,"False")) { c.status=1; }
        else { advance(s,c); id=push(n,c,unified_core::Node { tag:if eq(s,v,1,"True") {10} else {11},start:t.start,end:v.end,ty:2 }); }
    } else if eq(s,t,5,"(") {
        advance(s,c); let a=expression(s,c,n,b,active,param); let end=c.t.end;
        if a!=0 && take(s,c,5,")") { id=push(n,c,unified_core::Node { tag:8,start:t.start,end:end,a:a,ty:n[a-1].ty }); }
    } else if eq(s,t,1,"U32") {
        advance(s,c); if take(s,c,5,".") {
            var op:i64=0;
            if eq(s,c.t,1,"wrapping_add") {op=4;} else if eq(s,c.t,1,"wrapping_sub") {op=5;} else if eq(s,c.t,1,"wrapping_mul") {op=6;}
            if op==0 {c.status=1;} else {
                advance(s,c); if take(s,c,5,"(") {
                    let a=expression(s,c,n,b,active,param);
                    if a!=0 && take(s,c,5,",") {
                        let z=expression(s,c,n,b,active,param); let end=c.t.end;
                        if z!=0 && take(s,c,5,")") {
                            if n[a-1].ty!=1 || n[z-1].ty!=1 {c.status=6;}
                            else {id=push(n,c,unified_core::Node {tag:op,start:t.start,end:end,a:a,b:z,ty:1});}
                        }
                    }
                }
            }
        }
    } else if ident(s,t) {
        let slot=find(s,t,param,b,active); if slot<0 {c.status=3;}
        else {advance(s,c); id=push(n,c,unified_core::Node {tag:1,start:t.start,end:t.end,a:slot,ty:1});}
    } else { c.status=1; }
    c.depth-=1; return id;
}
fn sum(s:u8[:], c:Cursor&, n:unified_core::Node[>..]&, b:unified_core::Binding[:], active:i64[:], param:lexer::Token) -> i64 {
    var a=primary(s,c,n,b,active,param);
    while c.status==0 && eq(s,c.t,5,"+") {
        advance(s,c); let z=primary(s,c,n,b,active,param); if z==0 || c.status!=0 {return 0;}
        if n[a-1].ty!=1 || n[z-1].ty!=1 {c.status=6;return 0;}
        if !fits(n[a-1],n[z-1]) {c.status=5;return 0;}
        a=push(n,c,unified_core::Node {tag:3,start:n[a-1].start,end:n[z-1].end,a:a,b:z,ty:1});
    }
    return a;
}
fn bitand(s:u8[:], c:Cursor&, n:unified_core::Node[>..]&, b:unified_core::Binding[:], active:i64[:], param:lexer::Token) -> i64 {
    var a=sum(s,c,n,b,active,param);
    while c.status==0 && eq(s,c.t,5,"&") {
        advance(s,c); let z=sum(s,c,n,b,active,param); if z==0 || c.status!=0 {return 0;}
        if n[a-1].ty!=1 || n[z-1].ty!=1 {c.status=6;return 0;}
        a=push(n,c,unified_core::Node {tag:7,start:n[a-1].start,end:n[z-1].end,a:a,b:z,ty:1});
    } return a;
}
fn compare(s:u8[:], c:Cursor&, n:unified_core::Node[>..]&, b:unified_core::Binding[:], active:i64[:], param:lexer::Token) -> i64 {
    var a=bitand(s,c,n,b,active,param);
    if c.status==0 && eq(s,c.t,5,"<") {
        advance(s,c); let z=bitand(s,c,n,b,active,param); if z==0 || c.status!=0 {return 0;}
        if n[a-1].ty!=1 || n[z-1].ty!=1 {c.status=6;return 0;}
        a=push(n,c,unified_core::Node {tag:9,start:n[a-1].start,end:n[z-1].end,a:a,b:z,ty:2});
    } return a;
}
fn conjunction(s:u8[:], c:Cursor&, n:unified_core::Node[>..]&, b:unified_core::Binding[:], active:i64[:], param:lexer::Token) -> i64 {
    var a=compare(s,c,n,b,active,param);
    while c.status==0 && eq(s,c.t,5,"&&") {
        advance(s,c); let z=compare(s,c,n,b,active,param); if z==0 || c.status!=0 {return 0;}
        if n[a-1].ty!=2 || n[z-1].ty!=2 {c.status=6;return 0;}
        a=push(n,c,unified_core::Node {tag:12,start:n[a-1].start,end:n[z-1].end,a:a,b:z,ty:2});
    } return a;
}
recursive fn expression(s:u8[:], c:Cursor&, n:unified_core::Node[>..]&, b:unified_core::Binding[:], active:i64[:], param:lexer::Token) -> i64 {
    var a=conjunction(s,c,n,b,active,param);
    while c.status==0 && eq(s,c.t,5,"||") {
        advance(s,c); let z=conjunction(s,c,n,b,active,param); if z==0 || c.status!=0 {return 0;}
        if n[a-1].ty!=2 || n[z-1].ty!=2 {c.status=6;return 0;}
        a=push(n,c,unified_core::Node {tag:13,start:n[a-1].start,end:n[z-1].end,a:a,b:z,ty:2});
    } return a;
}
fn line_end(s:u8[:], c:Cursor&) -> bool { if c.t.kind==6 {return kind(s,c,6);} if c.t.kind==8 || c.t.kind==0 {return true;} c.status=1; return false; }
recursive fn suite(s:u8[:], c:Cursor&, n:unified_core::Node[>..]&, b:unified_core::Binding[>..]&, active:i64[>..]&, param:lexer::Token) -> i64 {
    if !enter(c) {return 0;} let old=active.len; var list:i64=0;
    while c.status==0 && c.t.kind!=8 && c.t.kind!=0 {
        if c.t.kind==6 {advance(s,c);continue;}
        let v=statement(s,c,n,b,active,param); if v==0 || c.status!=0 {break;}
        if list==0 {list=v;} else {list=push(n,c,unified_core::Node {tag:17,start:n[list-1].start,end:n[v-1].end,a:list,b:v,ty:3});}
    }
    if list==0 && c.status==0 {c.status=1;}
    while active.len>old {active.pop();} c.depth-=1; return list;
}
fn statement(s:u8[:], c:Cursor&, n:unified_core::Node[>..]&, b:unified_core::Binding[>..]&, active:i64[>..]&, param:lexer::Token) -> i64 {
    let t=c.t;
    if eq(s,t,1,"let") {
        advance(s,c); let name=c.t; if !ident(s,name) {c.status=1;return 0;}
        if find(s,name,param,b,active)>=0 {c.status=4;return 0;} if b.len>=128 {c.status=2;return 0;}
        advance(s,c); if eq(s,c.t,5,":") {advance(s,c);if !take(s,c,1,"U32") {return 0;}}
        if !take(s,c,5,"=") {return 0;} let value=expression(s,c,n,b,active,param);
        if value==0 || c.status!=0 {return 0;} if n[value-1].ty!=1 {c.status=6;return 0;}
        let end=n[value-1].end; if !line_end(s,c) {return 0;}
        b.push(unified_core::Binding {start:name.start,end:name.end}); active.push(b.len);
        return push(n,c,unified_core::Node {tag:14,start:t.start,end:end,a:value,b:b.len,ty:3});
    }
    if eq(s,t,1,"return") {
        advance(s,c); let value=expression(s,c,n,b,active,param); if value==0 || c.status!=0 {return 0;}
        if n[value-1].ty!=1 {c.status=6;return 0;} let end=n[value-1].end;
        if !line_end(s,c) {return 0;} return push(n,c,unified_core::Node {tag:15,start:t.start,end:end,a:value,ty:3});
    }
    if eq(s,t,1,"if") {
        advance(s,c); let cond=expression(s,c,n,b,active,param); if cond==0 || c.status!=0 {return 0;}
        if n[cond-1].ty!=2 {c.status=6;return 0;}
        if !take(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) {return 0;}
        let yes=suite(s,c,n,b,active,param); if yes==0 || !kind(s,c,8) {return 0;}
        var no:i64=0;
        if eq(s,c.t,1,"else") {advance(s,c); if !take(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) {return 0;}
            no=suite(s,c,n,b,active,param); if no==0 || !kind(s,c,8) {return 0;}}
        return push(n,c,unified_core::Node {tag:16,start:t.start,end:if no!=0 {n[no-1].end} else {n[yes-1].end},a:cond,b:yes,c:no,ty:3});
    }
    c.status=1;return 0;
}
fn parse(s:u8[:]) -> unified_core::Result {
    var c=Cursor {lex:lexer::init(s)}; advance(s,c); while c.status==0 && c.t.kind==6 {advance(s,c);}
    if !take(s,c,1,"let") {return unified_core::Result {status:c.status};}
    let name=c.t; if !ident(s,name) {return unified_core::Result {status:1};} advance(s,c);
    if !take(s,c,5,":") || !take(s,c,1,"U32") || !take(s,c,5,"->") || !take(s,c,1,"U32") ||
       !take(s,c,5,"=") || !take(s,c,1,"fn") {return unified_core::Result {status:c.status};}
    let param=c.t; if !ident(s,param) {return unified_core::Result {status:1};} advance(s,c);
    if !take(s,c,5,"=>") || !take(s,c,1,"do") || !take(s,c,5,":") || !kind(s,c,6) || !kind(s,c,7) {return unified_core::Result {status:c.status};}
    var nodes:unified_core::Node[>..]=[]; var binds:unified_core::Binding[>..]=[]; var active:i64[>..]=[];
    let root=suite(s,c,nodes,binds,active,param); if root==0 || !kind(s,c,8) {return unified_core::Result {status:if c.status==0 {1} else {c.status}};}
    while c.status==0 && c.t.kind==6 {advance(s,c);}
    if c.status!=0 || c.t.kind!=0 {return unified_core::Result {status:if c.status==0 {1} else {c.status}};}
    let completion=unified_completion::check(nodes,root);
    if completion!=0 {return unified_core::Result {status:completion};}
    return unified_core::Result {program:unified_core::Program {source:s,name_start:name.start,name_end:name.end,param_start:param.start,param_end:param.end,nodes:nodes,bindings:binds,root:root}};
}
