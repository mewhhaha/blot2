// Owned finite-loop syntax producer. Bounded syntactic subset: function-body
// suites, nested for/carry, explicit bounded fact syntax, if, next/stop,
// continue/bare break and return. Expressions are names/U32/Bool literals only.
// No type inference, facts, loans, affine usage, proofs or work receipts.
namespace short_parse;
import lexer;
import validate;
import mixed_core;
struct Parser {
    lex: lexer::State = lexer::State {}, t: lexer::Token = lexer::Token {}, status: i64 = 0,
    nodes: mixed_core::Node[..2048] = [], bindings: mixed_core::Binding[..256] = [],
    active: i64[256] = [0;256], active_count: i64 = 0,
    loop_targets: i64[32] = [0;32], loop_arities: i64[32] = [0;32], loop_count: i64 = 0,
    scope: i64 = 0, function_target: i64 = 0, depth: i64 = 0
}
fn advance(s: u8[:], p: Parser&) { if p.status != 0 { return; } p.t=lexer::next(s,p.lex); if p.t.kind==9 { p.status = if p.t.status==5 { 2 } else { 1 }; } }
fn is(s: u8[:], t: lexer::Token, kind: i64, value: u8[:]) -> bool {
    return t.kind==kind && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==value;
}
fn take(s: u8[:], p: Parser&, kind: i64, value: u8[:]) -> bool {
    if p.status != 0 || !is(s,p.t,kind,value) { if p.status==0 { p.status=1; } return false; }
    advance(s,p); return p.status==0;
}
fn take_kind(s: u8[:], p: Parser&, kind: i64) -> bool {
    if p.status!=0 || p.t.kind!=kind { if p.status==0 { p.status=1; } return false; }
    advance(s,p); return p.status==0;
}
fn emit(p: Parser&, n: mixed_core::Node) -> i64 {
    if p.status!=0 { return 0; } if p.nodes.len>=2048 { p.status=2; return 0; }
    p.nodes.push(n); return p.nodes.len;
}
fn pair(p: Parser&, left: i64, right: i64) -> i64 {
    if p.status!=0 || left<=0 || right<=0 { if p.status==0 { p.status=1; } return 0; }
    return emit(p,mixed_core::Node { tag:5,start:p.nodes[left-1].start,end:p.nodes[right-1].end,a:left,b:right });
}
fn identifier(s: u8[:], t: lexer::Token) -> bool {
    return t.kind==1 && t.start>=0 && t.end>t.start && t.end<=s.len && validate::name_valid(s[t.start..t.end]);
}
fn reserve(s: u8[:], p: Parser&, t: lexer::Token, kind: i64, scope: i64, pending: i64) -> i64 {
    if p.status!=0 || !identifier(s,t) { if p.status==0 { p.status=1; } return 0; }
    for k in p.active_count {
        let prev=p.bindings[p.active[k]-1];
        if s[prev.start..prev.end]==s[t.start..t.end] { p.status=4; return 0; }
    }
    if pending>=0 {
        for k in pending..p.bindings.len {
            let prev=p.bindings[k];
            if s[prev.start..prev.end]==s[t.start..t.end] { p.status=4; return 0; }
        }
    }
    if p.bindings.len>=256 { p.status=2; return 0; }
    p.bindings.push(mixed_core::Binding { start:t.start,end:t.end,kind:kind,scope:scope }); return p.bindings.len;
}
fn activate(p: Parser&, id: i64) {
    if p.status!=0 { return; }
    if id<=0 || p.active_count>=256 { p.status=2; return; }
    p.active[p.active_count]=id; p.active_count+=1;
}
fn resolve(s: u8[:], p: Parser&, t: lexer::Token) -> i64 {
    if p.status!=0 || !identifier(s,t) { if p.status==0 { p.status=1; } return 0; }
    var i=p.active_count;
    while i>0 { i-=1; let b=p.bindings[p.active[i]-1]; if s[b.start..b.end]==s[t.start..t.end] { return p.active[i]; } }
    p.status=3; return 0;
}
fn atom(s: u8[:], p: Parser&, allow_bool: bool) -> i64 {
    if p.status!=0 { return 0; } let t=p.t;
    if t.kind==1 && identifier(s,t) {
        let binding=resolve(s,p,t); if binding==0 { return 0; } advance(s,p);
        return emit(p,mixed_core::Node { tag:1,start:t.start,end:t.end,a:binding });
    }
    if t.kind==2 { advance(s,p); return emit(p,mixed_core::Node { tag:2,start:t.start,end:t.end }); }
    if allow_bool && is(s,t,5,"#") {
        advance(s,p); let v=p.t;
        if v.start!=t.end || (!is(s,v,1,"True") && !is(s,v,1,"False")) { p.status=1; return 0; }
        let tag=if is(s,v,1,"True") { 3 } else { 4 }; advance(s,p);
        return emit(p,mixed_core::Node { tag:tag,start:t.start,end:v.end });
    }
    p.status=1; return 0;
}
// Scalar expressions share the loop's postorder node and binding arena.
recursive fn primary(s:u8[:],p:Parser&,allow_bool:bool) -> i64 {
    if p.depth>=64 {p.status=2;return 0;}p.depth+=1;let t=p.t;var id:i64=0;
    if is(s,t,1,"U32") {
        advance(s,p);if take(s,p,5,".") {var op:i64=0;if is(s,p.t,1,"wrapping_add") {op=19;} else if is(s,p.t,1,"wrapping_sub") {op=25;} else if is(s,p.t,1,"wrapping_mul") {op=26;}
            if op==0 {p.status=1;} else {advance(s,p);if take(s,p,5,"(") {let a=value(s,p,true);if a!=0 && take(s,p,5,",") {let b=value(s,p,true);let end=p.t.end;
                if b!=0 && take(s,p,5,")") {id=emit(p,mixed_core::Node {tag:op,start:t.start,end:end,a:a,b:b});}}}}
        }
    } else if is(s,t,5,"(") {
        advance(s,p);let a=value(s,p,true);let end=p.t.end;
        if a!=0 && take(s,p,5,")") {id=emit(p,mixed_core::Node {tag:20,start:t.start,end:end,a:a});}
    } else {id=atom(s,p,allow_bool);}
    p.depth-=1;return id;
}
fn sum(s:u8[:],p:Parser&,allow_bool:bool) -> i64 {
    var a=primary(s,p,allow_bool);
    while p.status==0 && is(s,p.t,5,"+") {advance(s,p);let b=primary(s,p,true);if b==0 {return 0;}
        a=emit(p,mixed_core::Node {tag:21,start:p.nodes[a-1].start,end:p.nodes[b-1].end,a:a,b:b});}
    return a;
}
fn bitand(s:u8[:],p:Parser&,allow_bool:bool) -> i64 {
    var a=sum(s,p,allow_bool);while p.status==0 && is(s,p.t,5,"&") {advance(s,p);let b=sum(s,p,true);if b==0{return 0;}a=emit(p,mixed_core::Node {tag:27,start:p.nodes[a-1].start,end:p.nodes[b-1].end,a:a,b:b});}return a;
}
fn comparison(s:u8[:],p:Parser&,allow_bool:bool) -> i64 {
    var a=bitand(s,p,allow_bool);
    if p.status==0 && (is(s,p.t,5,"<") || is(s,p.t,5,"<=")) {let tag=if is(s,p.t,5,"<") {22} else {28};advance(s,p);let b=bitand(s,p,true);if b==0{return 0;}a=emit(p,mixed_core::Node {tag:tag,start:p.nodes[a-1].start,end:p.nodes[b-1].end,a:a,b:b});}
    return a;
}

fn conjunction(s:u8[:],p:Parser&,allow_bool:bool) -> i64 {
    var a=comparison(s,p,allow_bool);while p.status==0 && is(s,p.t,5,"&&") {advance(s,p);let b=comparison(s,p,true);if b==0{return 0;}a=emit(p,mixed_core::Node {tag:23,start:p.nodes[a-1].start,end:p.nodes[b-1].end,a:a,b:b});}return a;
}
recursive fn value(s:u8[:],p:Parser&,allow_bool:bool) -> i64 {
    var a=conjunction(s,p,allow_bool);while p.status==0 && is(s,p.t,5,"||") {advance(s,p);let b=conjunction(s,p,true);if b==0{return 0;}a=emit(p,mixed_core::Node {tag:24,start:p.nodes[a-1].start,end:p.nodes[b-1].end,a:a,b:b});}return a;
}

fn term(s: u8[:], p: Parser&) -> i64 {
    let t=p.t;
    if is(s,t,1,"Init") || is(s,t,1,"Len") || is(s,t,1,"Cap") {
        let selector=if is(s,t,1,"Init") { 1 } else if is(s,t,1,"Len") { 2 } else { 3 };
        advance(s,p); if !take(s,p,5,"(") { return 0; }
        let x=value(s,p,false); if x==0 || p.nodes[x-1].tag!=1 { p.status=1; return 0; }
        let end=p.t.end; if !take(s,p,5,")") { return 0; }
        return emit(p,mixed_core::Node { tag:7,start:t.start,end:end,a:x,b:selector });
    }
    return value(s,p,false);
}
fn fact(s: u8[:], p: Parser&) -> i64 {
    let t=p.t; var kind: i64=0;
    if is(s,t,1,"Eq") { kind=1; } else if is(s,t,1,"Lt") { kind=2; } else if is(s,t,1,"Le") { kind=3; }
    else if is(s,t,1,"AddFits") { kind=4; } else if is(s,t,1,"SubFits") { kind=5; } else if is(s,t,1,"MulFits") { kind=6; }
    else if is(s,t,1,"Index") { kind=7; } else { p.status=1; return 0; }
    advance(s,p); if !take(s,p,5,"(") { return 0; }
    let a=term(s,p); if a==0 { return 0; }
    // Index's first argument is syntactically a Domain name, not an arbitrary
    // term. Its kind/authority still require the later semantic checker.
    if kind==7 && p.nodes[a-1].tag!=1 { p.status=1; return 0; }
    if !take(s,p,5,",") { return 0; }
    let b=term(s,p); if b==0 { return 0; } var third: i64=0;
    if kind==7 { if !take(s,p,5,",") { return 0; } third=term(s,p); if third==0 { return 0; } }
    let end=p.t.end; if !take(s,p,5,")") { return 0; }
    return emit(p,mixed_core::Node { tag:8,start:t.start,end:end,a:a,b:b,c:kind,d:third });
}
fn values(s: u8[:], p: Parser&) -> i64, i64, i64 {
    if !take(s,p,5,"(") { return 0,0,0; }
    var list: i64=0; var count: i64=0;
    while p.status==0 && !is(s,p.t,5,")") {
        if count>=16 { p.status=2; break; }
        let x=value(s,p,true); if x==0 { break; }
        if list==0 { list=x; } else { list=pair(p,list,x); }
        count+=1;
        if is(s,p.t,5,",") { advance(s,p); if is(s,p.t,5,")") { p.status=1; } }
        else { break; }
    }
    let end=p.t.end; if !take(s,p,5,")") { return 0,0,0; }
    return list,count,end;
}
recursive fn suite(s: u8[:], p: Parser&) -> i64 {
    if p.status!=0 { return 0; } if p.depth>=64 { p.status=2; return 0; } p.depth+=1;
    var list: i64=0; var count: i64=0;
    while p.status==0 && p.t.kind!=8 && p.t.kind!=0 {
        if p.t.kind==6 { advance(s,p); continue; }
        if count>=32 { p.status=2; break; }
        let item=statement(s,p); if item==0 { break; }
        if list==0 { list=item; } else { list=emit(p,mixed_core::Node { tag:17,start:p.nodes[list-1].start,end:p.nodes[item-1].end,a:list,b:item }); }
        count+=1;
    }
    if list==0 && p.status==0 { p.status=1; }
    p.depth-=1; return list;
}
// General loop header in the documented name/literal expression subset. The
// index and carry names are reserved first but cannot be read by initializers.
recursive fn for_loop(s: u8[:], p: Parser&) -> i64 {
    let t=p.t; if p.loop_count>=32 { p.status=2; return 0; }
    if !take(s,p,1,"for") { return 0; }
    let index_t=p.t; let pending=p.bindings.len; let index_id=reserve(s,p,index_t,2,t.start+1,pending);
    if index_id==0 { return 0; } advance(s,p); if !take(s,p,1,"in") { return 0; }
    let lo=value(s,p,false); if lo==0 || !take(s,p,5,"..") { return 0; }
    let hi=value(s,p,false); if hi==0 { return 0; }
    var carries: i64=0; var count: i64=0;
    if is(s,p.t,1,"carry") {
        advance(s,p); if !take(s,p,5,"(") { return 0; }
        while p.status==0 && !is(s,p.t,5,")") {
            if count>=16 { p.status=2; return 0; }
            let binder_t=p.t; let binder=reserve(s,p,binder_t,3,t.start+1,pending); if binder==0 { return 0; }
            advance(s,p); if !take(s,p,5,"=") { return 0; }
            let initial=value(s,p,true); if initial==0 { return 0; }
            let item=emit(p,mixed_core::Node { tag:6,start:binder_t.start,end:p.nodes[initial-1].end,a:initial,b:binder });
            if carries==0 { carries=item; } else { carries=pair(p,carries,item); }
            count+=1; if is(s,p.t,5,",") { advance(s,p); if is(s,p.t,5,")") { p.status=1; return 0; } } else { break; }
        }
        if count==0 || !take(s,p,5,")") { if p.status==0 { p.status=1; } return 0; }
    }
    let old_active=p.active_count; let old_scope=p.scope;
    for id in pending..p.bindings.len { activate(p,id+1); }
    p.scope=t.start+1;
    var continuation=false;
    if p.t.kind==6 { advance(s,p); if !take_kind(s,p,7) { return 0; } continuation=true; }
    var invariants: i64=0; var fact_count: i64=0;
    if is(s,p.t,1,"invariant") {
        advance(s,p); if !take(s,p,5,"[") { return 0; }
        while p.status==0 && !is(s,p.t,5,"]") {
            if fact_count>=32 { p.status=2; return 0; }
            let item=fact(s,p); if item==0 { return 0; }
            if invariants==0 { invariants=item; } else { invariants=pair(p,invariants,item); }
            fact_count+=1; if is(s,p.t,5,",") { advance(s,p); if is(s,p.t,5,"]") { p.status=1; return 0; } } else { break; }
        }
        if fact_count==0 || !take(s,p,5,"]") { if p.status==0 { p.status=1; } return 0; }
    } else if continuation { p.status=1; return 0; }
    if !take(s,p,1,"do") || !take(s,p,5,":") || !take_kind(s,p,6) || !take_kind(s,p,7) { return 0; }
    p.loop_targets[p.loop_count]=t.start+1; p.loop_arities[p.loop_count]=count; p.loop_count+=1;
    let body=suite(s,p); p.loop_count-=1;
    if body==0 || !take_kind(s,p,8) { return 0; }
    if continuation && !take_kind(s,p,8) { return 0; }
    p.active_count=old_active; p.scope=old_scope;
    return emit(p,mixed_core::Node { tag:15,start:t.start,end:p.nodes[body-1].end,a:lo,b:hi,c:carries,d:invariants,e:body,f:index_id,g:count,target:t.start+1 });
}
fn statement(s: u8[:], p: Parser&) -> i64 {
    let t=p.t;
    if is(s,t,1,"let") {
        advance(s,p); let name=p.t; if !identifier(s,name) { p.status=1; return 0; }
        advance(s,p); if !take(s,p,5,"=") {return 0;}
        let loop_init=is(s,p.t,1,"for");let item=if loop_init {for_loop(s,p)} else {value(s,p,true)};
        if item==0 {return 0;}let end=p.nodes[item-1].end;
        if !loop_init {if p.t.kind==6 {advance(s,p);} else if p.t.kind!=8 && p.t.kind!=0 {p.status=1;return 0;}}
        let id=reserve(s,p,name,4,p.scope,-1); if id==0 { return 0; } activate(p,id);
        return emit(p,mixed_core::Node { tag:16,start:t.start,end:end,a:item,b:id });
    }
    if is(s,t,1,"for") {
        let loop_node=for_loop(s,p); if loop_node!=0 && p.nodes[loop_node-1].g!=0 { p.status=1; return 0; } return loop_node;
    }
    if is(s,t,1,"next") || is(s,t,1,"stop") {
        let tag=if is(s,t,1,"next") { 9 } else { 10 };
        if p.loop_count==0 || p.loop_arities[p.loop_count-1]==0 { p.status=5; return 0; }
        let target=p.loop_targets[p.loop_count-1]; let arity=p.loop_arities[p.loop_count-1]; advance(s,p);
        let args,count,end=values(s,p); if p.status!=0 { return 0; }
        if count!=arity { p.status=6; return 0; }
        if p.t.kind==6 { advance(s,p); } else if p.t.kind!=8 && p.t.kind!=0 { p.status=1; return 0; }
        return emit(p,mixed_core::Node { tag:tag,start:t.start,end:end,a:args,b:count,target:target });
    }
    if is(s,t,1,"continue") || is(s,t,1,"break") {
        let tag=if is(s,t,1,"continue") { 11 } else { 12 };
        if p.loop_count==0 || p.loop_arities[p.loop_count-1]!=0 { p.status=5; return 0; }
        let target=p.loop_targets[p.loop_count-1]; advance(s,p);
        if p.t.kind==6 { advance(s,p); } else if p.t.kind!=8 && p.t.kind!=0 { p.status=1; return 0; }
        return emit(p,mixed_core::Node { tag:tag,start:t.start,end:t.end,target:target });
    }
    if is(s,t,1,"return") {
        advance(s,p); let result=value(s,p,true); if result==0 { return 0; }
        if p.t.kind==6 { advance(s,p); } else if p.t.kind!=8 && p.t.kind!=0 { p.status=1; return 0; }
        return emit(p,mixed_core::Node { tag:13,start:t.start,end:p.nodes[result-1].end,a:result,target:p.function_target });
    }
    if is(s,t,1,"if") {
        advance(s,p); let cond=value(s,p,true); if cond==0 || !take(s,p,5,":") || !take_kind(s,p,6) || !take_kind(s,p,7) { return 0; }
        let old_active=p.active_count; let old_scope=p.scope; p.scope=t.start+1;
        let yes=suite(s,p); p.active_count=old_active; p.scope=old_scope;
        if yes==0 || !take_kind(s,p,8) { return 0; } var no: i64=0;
        if is(s,p.t,1,"else") {
            let et=p.t; advance(s,p); if !take(s,p,5,":") || !take_kind(s,p,6) || !take_kind(s,p,7) { return 0; }
            p.scope=et.start+1; no=suite(s,p); p.active_count=old_active; p.scope=old_scope;
            if no==0 || !take_kind(s,p,8) { return 0; }
        }
        return emit(p,mixed_core::Node { tag:14,start:t.start,end:if no!=0 { p.nodes[no-1].end } else { p.nodes[yes-1].end },a:cond,b:yes,c:no });
    }
    p.status=1; return 0;
}
// 0 success; 1 unsupported syntax; 2 bounded implementation limit; 3 unbound
// name; 4 duplicate active binding; 5 bad control target; 6 carry arity mismatch.
fn parse(s: u8[:]) -> mixed_core::Tree, i64 {
    if s.len>65536 { return mixed_core::Tree {},2; }
    var p=Parser { lex:lexer::init(s) }; advance(s,p); while p.status==0 && p.t.kind==6 { advance(s,p); }
    let f=p.t; if !take(s,p,1,"fn") { return mixed_core::Tree {},p.status; }
    p.function_target=f.start+1; p.scope=p.function_target; var count: i64=0;
    if is(s,p.t,5,"(") {
        advance(s,p);
        while p.status==0 && !is(s,p.t,5,")") {
            if count>=16 { p.status=2; break; }
            let name=p.t; let id=reserve(s,p,name,1,p.scope,-1); if id==0 { break; }
            activate(p,id); advance(s,p); count+=1;
            if is(s,p.t,5,",") { advance(s,p); if is(s,p.t,5,")") { p.status=1; } } else { break; }
        }
        if !take(s,p,5,")") { return mixed_core::Tree {},if p.status==0 {1} else {p.status}; }
    } else {
        let name=p.t; let id=reserve(s,p,name,1,p.scope,-1);
        if id==0 {return mixed_core::Tree {},if p.status==0 {1} else {p.status};}
        activate(p,id); advance(s,p); count=1;
    }
    if !take(s,p,5,"=>") || !take(s,p,1,"do") || !take(s,p,5,":") || !take_kind(s,p,6) || !take_kind(s,p,7) {
        return mixed_core::Tree {},if p.status==0 { 1 } else { p.status };
    }
    let body=suite(s,p); if body==0 || !take_kind(s,p,8) { return mixed_core::Tree {},if p.status==0 { 1 } else { p.status }; }
    while p.status==0 && p.t.kind==6 { advance(s,p); }
    if p.status!=0 || p.t.kind!=0 { return mixed_core::Tree {},if p.status==0 { 1 } else { p.status }; }
    let root=emit(p,mixed_core::Node { tag:18,start:f.start,end:p.nodes[body-1].end,a:body,b:count,target:p.function_target });
    if root==0 { return mixed_core::Tree {},p.status; }
    return mixed_core::Tree { source:s,bindings:copy(p.bindings),nodes:copy(p.nodes),root:root },0;
}
