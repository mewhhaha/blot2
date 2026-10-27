// Independent source-to-tree recognizer for the bounded iteration syntax
// experiment. It shares only the lexer and the record schema with the producer.
// Exact caller-retained source, binding order/scope, every node and transfer
// target are checked; no type, ownership, effect, proof or artifact authority
// is established. This verifier is deliberately unmetered and private.
namespace short_verify;
import lexer;
import validate;
import mixed_core;

struct Term { id: i64 = 0, start: i64 = 0, end: i64 = 0 }
struct Reader {
    lex: lexer::State = lexer::State {}, t: lexer::Token = lexer::Token {}, bad: bool = false,
    next_node: i64 = 0, next_binding: i64 = 0,
    active: i64[256] = [0;256], active_len: i64 = 0,
    loops: i64[32] = [0;32], arities: i64[32] = [0;32], loop_depth: i64 = 0,
    suite_depth: i64 = 0, expression_depth: i64 = 0, function_target: i64 = 0
}
fn bump(s: u8[:], r: Reader&) { if !r.bad { r.t = lexer::next(s,r.lex); if r.t.kind == 9 { r.bad = true; } } }
fn text(s: u8[:], t: lexer::Token, k: i64, v: u8[:]) -> bool {
    return t.kind == k && t.start >= 0 && t.end > t.start && t.end <= s.len && s[t.start..t.end] == v;
}
fn take(s: u8[:], r: Reader&, k: i64, v: u8[:]) -> lexer::Token {
    let t = r.t;
    if r.bad || !text(s,t,k,v) { r.bad = true; return lexer::Token {}; }
    bump(s,r); return t;
}
fn kind(s: u8[:], r: Reader&, k: i64) -> bool {
    if r.bad || r.t.kind != k { r.bad = true; return false; }
    bump(s,r); return !r.bad;
}
fn event(r: Reader&, tree: mixed_core::Tree&, n: mixed_core::Node) -> Term {
    if r.bad || r.next_node < 0 || r.next_node >= tree.nodes.len { r.bad = true; return Term {}; }
    if !mixed_core::same_node(tree.nodes[r.next_node],n) { r.bad = true; return Term {}; }
    r.next_node += 1; return Term { id:r.next_node, start:n.start, end:n.end };
}
fn ident(s: u8[:], t: lexer::Token) -> bool {
    return t.kind == 1 && t.start >= 0 && t.end > t.start && t.end <= s.len && validate::name_valid(s[t.start..t.end]);
}
fn same_name(s: u8[:], a: lexer::Token, b: mixed_core::Binding) -> bool {
    return a.start >= 0 && a.end > a.start && a.end <= s.len && b.start >= 0 && b.end > b.start && b.end <= s.len && s[a.start..a.end] == s[b.start..b.end];
}
fn lookup(s: u8[:], r: Reader&, tree: mixed_core::Tree&, t: lexer::Token) -> i64 {
    if !ident(s,t) { r.bad = true; return 0; }
    for i in r.active_len {
        let id = r.active[i];
        if id < 1 || id > tree.bindings.len { r.bad = true; return 0; }
        if same_name(s,t,tree.bindings[id-1]) { return id; }
    }
    return 0;
}
// Reserve a producer-ordered binding without making it visible. Pending IDs
// are checked too, so loop index/carry names cannot duplicate each other.
fn binding(s: u8[:], r: Reader&, tree: mixed_core::Tree&, t: lexer::Token,
           k: i64, scope: i64, pending: i64[:]) -> i64 {
    if r.bad || !ident(s,t) || scope <= 0 || r.next_binding >= tree.bindings.len || r.next_binding >= 256 { r.bad = true; return 0; }
    if lookup(s,r,tree,t) != 0 || r.bad { r.bad = true; return 0; }
    for id in pending {
        if id < 1 || id > r.next_binding || same_name(s,t,tree.bindings[id-1]) { r.bad = true; return 0; }
    }
    let expected=mixed_core::Binding { start:t.start, end:t.end, kind:k, scope:scope };
    if !mixed_core::same_binding(tree.bindings[r.next_binding],expected) { r.bad = true; return 0; }
    r.next_binding += 1; return r.next_binding;
}
fn activate(r: Reader&, id: i64) {
    if r.bad || id < 1 || id > r.next_binding || r.active_len >= 256 { r.bad = true; return; }
    r.active[r.active_len] = id; r.active_len += 1;
}
fn atom(s: u8[:], r: Reader&, tree: mixed_core::Tree&, allow_bool: bool) -> Term {
    let t = r.t;
    if t.kind == 1 {
        let id=lookup(s,r,tree,t); if r.bad || id == 0 { r.bad = true; return Term {}; }
        bump(s,r); return event(r,tree,mixed_core::Node {tag:1,start:t.start,end:t.end,a:id});
    }
    if t.kind == 2 && t.start >= 0 && t.end > t.start && t.end <= s.len {
        var value:u64=0;
        for p in t.start..t.end {
            if s[p] < '0' || s[p] > '9' { r.bad=true; return Term {}; }
            let d=(s[p]-'0') as u64; if value > (4294967295-d)/10 { r.bad=true; return Term {}; }
            value=value*10+d;
        }
        bump(s,r); return event(r,tree,mixed_core::Node {tag:2,start:t.start,end:t.end});
    }
    if allow_bool && text(s,t,5,"#") {
        bump(s,r); let v=r.t;
        if v.start != t.end || (!text(s,v,1,"True") && !text(s,v,1,"False")) { r.bad=true; return Term {}; }
        bump(s,r); return event(r,tree,mixed_core::Node {tag:if text(s,v,1,"True") {3} else {4},start:t.start,end:v.end});
    }
    r.bad=true; return Term {};
}
// Reconstruct each expression from source using the reader's active lexical
// bindings. Events compare every field of the candidate in postorder. The
// scalar type/proof pass is separate and must still validate each operator.
recursive fn primary(s:u8[:],r:Reader&,tree:mixed_core::Tree&,allow_bool:bool) -> Term {
    if r.bad || r.suite_depth+r.expression_depth>=64 {r.bad=true;return Term {};}
    r.expression_depth+=1;let t=r.t;var out=Term {};
    if text(s,t,1,"U32") {
        bump(s,r);take(s,r,5,".");var op:i64=0;if text(s,r.t,1,"wrapping_add") {op=19;} else if text(s,r.t,1,"wrapping_sub") {op=25;} else if text(s,r.t,1,"wrapping_mul") {op=26;}
        if op==0 {r.bad=true;}else {bump(s,r);take(s,r,5,"(");let a=expression(s,r,tree,true);take(s,r,5,",");let b=expression(s,r,tree,true);let end=take(s,r,5,")");
        if a.id!=0 && b.id!=0 && !r.bad {out=event(r,tree,mixed_core::Node {tag:op,start:t.start,end:end.end,a:a.id,b:b.id});}}
    } else if text(s,t,5,"(") {
        bump(s,r);let a=expression(s,r,tree,true);let end=take(s,r,5,")");
        if a.id!=0 && !r.bad {out=event(r,tree,mixed_core::Node {tag:20,start:t.start,end:end.end,a:a.id});}
    } else {out=atom(s,r,tree,allow_bool);}
    r.expression_depth-=1;return out;
}
fn sum(s:u8[:],r:Reader&,tree:mixed_core::Tree&,allow_bool:bool) -> Term {
    var left=primary(s,r,tree,allow_bool);
    while !r.bad && text(s,r.t,5,"+") {
        bump(s,r);let right=primary(s,r,tree,true);if right.id==0 {r.bad=true;return Term {};}
        left=event(r,tree,mixed_core::Node {tag:21,start:left.start,end:right.end,a:left.id,b:right.id});
    }
    return left;
}
fn bitand(s:u8[:],r:Reader&,tree:mixed_core::Tree&,allow_bool:bool) -> Term {
    var left=sum(s,r,tree,allow_bool);while !r.bad && text(s,r.t,5,"&") {bump(s,r);let right=sum(s,r,tree,true);if right.id==0 {r.bad=true;return Term {};}left=event(r,tree,mixed_core::Node {tag:27,start:left.start,end:right.end,a:left.id,b:right.id});}return left;
}
fn comparison(s:u8[:],r:Reader&,tree:mixed_core::Tree&,allow_bool:bool) -> Term {
    var left=bitand(s,r,tree,allow_bool);if !r.bad && (text(s,r.t,5,"<") || text(s,r.t,5,"<=")) {let tag=if text(s,r.t,5,"<") {22} else {28};bump(s,r);let right=bitand(s,r,tree,true);if right.id==0 {r.bad=true;return Term {};}left=event(r,tree,mixed_core::Node {tag:tag,start:left.start,end:right.end,a:left.id,b:right.id});}return left;
}

fn conjunction(s:u8[:],r:Reader&,tree:mixed_core::Tree&,allow_bool:bool) -> Term {
    var left=comparison(s,r,tree,allow_bool);while !r.bad && text(s,r.t,5,"&&") {bump(s,r);let right=comparison(s,r,tree,true);if right.id==0 {r.bad=true;return Term {};}left=event(r,tree,mixed_core::Node {tag:23,start:left.start,end:right.end,a:left.id,b:right.id});}return left;
}
recursive fn expression(s:u8[:],r:Reader&,tree:mixed_core::Tree&,allow_bool:bool) -> Term {
    var left=conjunction(s,r,tree,allow_bool);while !r.bad && text(s,r.t,5,"||") {bump(s,r);let right=conjunction(s,r,tree,true);if right.id==0 {r.bad=true;return Term {};}left=event(r,tree,mixed_core::Node {tag:24,start:left.start,end:right.end,a:left.id,b:right.id});}return left;
}

fn pair(r: Reader&, tree: mixed_core::Tree&, a: Term, b: Term) -> Term {
    if a.id == 0 || b.id == 0 { r.bad=true; return Term {}; }
    return event(r,tree,mixed_core::Node {tag:5,start:a.start,end:b.end,a:a.id,b:b.id});
}
fn term(s: u8[:], r: Reader&, tree: mixed_core::Tree&) -> Term {
    let t=r.t;
    if text(s,t,1,"Init") || text(s,t,1,"Len") || text(s,t,1,"Cap") {
        let selector=if text(s,t,1,"Init") {1} else if text(s,t,1,"Len") {2} else {3};
        bump(s,r); take(s,r,5,"("); let value=expression(s,r,tree,false); let end=take(s,r,5,")");
        if value.id==0 || value.id>tree.nodes.len || tree.nodes[value.id-1].tag!=1 { r.bad=true; return Term {}; }
        return event(r,tree,mixed_core::Node {tag:7,start:t.start,end:end.end,a:value.id,b:selector});
    }
    return expression(s,r,tree,false);
}
fn fact(s: u8[:], r: Reader&, tree: mixed_core::Tree&) -> Term {
    let t=r.t; var op:i64=0;
    if text(s,t,1,"Eq") {op=1;} else if text(s,t,1,"Lt") {op=2;} else if text(s,t,1,"Le") {op=3;}
    else if text(s,t,1,"AddFits") {op=4;} else if text(s,t,1,"SubFits") {op=5;}
    else if text(s,t,1,"MulFits") {op=6;} else if text(s,t,1,"Index") {op=7;}
    else {r.bad=true; return Term {};}
    bump(s,r); take(s,r,5,"("); let a=term(s,r,tree);
    if op==7 && (a.id==0 || a.id>tree.nodes.len || tree.nodes[a.id-1].tag!=1) {r.bad=true;return Term {};}
    take(s,r,5,","); let b=term(s,r,tree);
    var d=Term {}; if op==7 {take(s,r,5,","); d=term(s,r,tree);}
    let end=take(s,r,5,")");
    return event(r,tree,mixed_core::Node {tag:8,start:t.start,end:end.end,a:a.id,b:b.id,c:op,d:d.id});
}
fn line_end(s: u8[:], r: Reader&) -> bool {
    if r.bad { return false; }
    if r.t.kind==6 { bump(s,r); return !r.bad; }
    if r.t.kind==8 || r.t.kind==0 { return true; }
    r.bad=true; return false;
}
recursive fn suite(s: u8[:], r: Reader&, tree: mixed_core::Tree&, scope: i64) -> Term {
    if r.bad || r.suite_depth >= 64 { r.bad=true; return Term {}; }
    r.suite_depth+=1; let saved=r.active_len; var list=Term {}; var count:i64=0;
    while !r.bad && r.t.kind!=8 && r.t.kind!=0 {
        if r.t.kind==6 { bump(s,r); continue; }
        if count>=32 { r.bad=true; break; }
        let n=statement(s,r,tree,scope); if n.id==0 || r.bad { break; }
        list=if list.id==0 { n } else { event(r,tree,mixed_core::Node {tag:17,start:list.start,end:n.end,a:list.id,b:n.id}) };
        count+=1;
    }
    if count==0 { r.bad=true; }
    r.active_len=saved; r.suite_depth-=1; return list;
}
fn read_loop(s: u8[:], r: Reader&, tree: mixed_core::Tree&) -> Term {
    let start=take(s,r,1,"for"); if r.bad || r.loop_depth>=32 { r.bad=true; return Term {}; }
    let scope=start.start+1; let saved=r.active_len; var pending:i64[17]=[0;17]; var pending_count:i64=0;
    let idx_token=r.t; if !ident(s,idx_token) { r.bad=true; return Term {}; } bump(s,r);
    let index=binding(s,r,tree,idx_token,2,scope,pending[..pending_count]); pending[pending_count]=index; pending_count+=1;
    take(s,r,1,"in"); let lo=expression(s,r,tree,false); take(s,r,5,".."); let hi=expression(s,r,tree,false);
    var carries=Term {}; var arity:i64=0;
    if text(s,r.t,1,"carry") {
        bump(s,r); take(s,r,5,"(");
        loop {
            if r.bad || arity>=16 { r.bad=true; break; }
            let name=r.t; if !ident(s,name) { r.bad=true; break; } bump(s,r);
            let id=binding(s,r,tree,name,3,scope,pending[..pending_count]); pending[pending_count]=id; pending_count+=1;
            take(s,r,5,"="); let value=expression(s,r,tree,true);
            let item=event(r,tree,mixed_core::Node {tag:6,start:name.start,end:value.end,a:value.id,b:id});
            carries=if arity==0 {item} else {pair(r,tree,carries,item)}; arity+=1;
            if !text(s,r.t,5,",") { break; } bump(s,r);
        }
        take(s,r,5,")");
    }
    for i in pending_count { activate(r,pending[i]); }
    var continuation=false;
    if r.t.kind==6 { bump(s,r); if !kind(s,r,7) { r.bad=true; } else { continuation=true; } }
    var facts=Term {}; var fact_count:i64=0;
    if text(s,r.t,1,"invariant") {
        bump(s,r); take(s,r,5,"[");
        loop {
            if r.bad { break; }
            if fact_count>=32 { r.bad=true; break; }
            let item=fact(s,r,tree); if item.id==0 { break; }
            facts=if fact_count==0 {item} else {pair(r,tree,facts,item)}; fact_count+=1;
            if !text(s,r.t,5,",") { break; } bump(s,r);
        }
        take(s,r,5,"]");
    }
    if continuation && fact_count==0 {r.bad=true;}
    take(s,r,1,"do"); take(s,r,5,":"); kind(s,r,6); kind(s,r,7);
    if r.bad {r.active_len=saved; return Term {};}
    r.loops[r.loop_depth]=scope; r.arities[r.loop_depth]=arity; r.loop_depth+=1;
    let body=suite(s,r,tree,scope); r.loop_depth-=1;
    kind(s,r,8); if continuation {kind(s,r,8);}
    r.active_len=saved;
    return event(r,tree,mixed_core::Node {tag:15,start:start.start,end:body.end,a:lo.id,b:hi.id,c:carries.id,d:facts.id,e:body.id,f:index,g:arity,target:scope});
}
fn statement(s: u8[:], r: Reader&, tree: mixed_core::Tree&, scope: i64) -> Term {
    let t=r.t;
    if text(s,t,1,"let") {
        bump(s,r); let name=r.t; if !ident(s,name) {r.bad=true;return Term {};} bump(s,r);
        take(s,r,5,"="); let loop_init=text(s,r.t,1,"for");
        let value=if loop_init {read_loop(s,r,tree)} else {expression(s,r,tree,true)};
        if !loop_init && !line_end(s,r) {return Term {};}
        let empty:i64[0]=[]; let id=binding(s,r,tree,name,4,scope,empty); activate(r,id);
        return event(r,tree,mixed_core::Node {tag:16,start:t.start,end:value.end,a:value.id,b:id});
    }
    if text(s,t,1,"for") {
        let value=read_loop(s,r,tree);
        if value.id!=0 && tree.nodes[value.id-1].g!=0 {r.bad=true;return Term {};}
        return value;
    }
    if text(s,t,1,"return") {
        bump(s,r); let value=expression(s,r,tree,true); if !line_end(s,r) {return Term {};}
        return event(r,tree,mixed_core::Node {tag:13,start:t.start,end:value.end,a:value.id,target:r.function_target});
    }
    if text(s,t,1,"break") || text(s,t,1,"continue") {
        if r.loop_depth==0 || r.arities[r.loop_depth-1]!=0 {r.bad=true;return Term {};}
        let tag=if text(s,t,1,"break") {12} else {11}; bump(s,r); if !line_end(s,r) {return Term {};}
        return event(r,tree,mixed_core::Node {tag:tag,start:t.start,end:t.end,target:r.loops[r.loop_depth-1]});
    }
    if text(s,t,1,"next") || text(s,t,1,"stop") {
        if r.loop_depth==0 || r.arities[r.loop_depth-1]==0 {r.bad=true;return Term {};}
        let tag=if text(s,t,1,"next") {9} else {10}; bump(s,r); take(s,r,5,"(");
        var list=Term {}; var n:i64=0;
        loop {
            if r.bad || n>=16 {r.bad=true;break;}
            let x=expression(s,r,tree,true); if x.id==0 {break;}
            list=if n==0 {x} else {pair(r,tree,list,x)}; n+=1;
            if !text(s,r.t,5,",") {break;} bump(s,r);
        }
        let end=take(s,r,5,")"); if n!=r.arities[r.loop_depth-1] || !line_end(s,r) {r.bad=true;return Term {};}
        return event(r,tree,mixed_core::Node {tag:tag,start:t.start,end:end.end,a:list.id,b:n,target:r.loops[r.loop_depth-1]});
    }
    if text(s,t,1,"if") {
        bump(s,r); let cond=expression(s,r,tree,true); take(s,r,5,":"); kind(s,r,6); kind(s,r,7);
        let yes=suite(s,r,tree,t.start+1); kind(s,r,8); var no=Term {};
        if text(s,r.t,1,"else") { let el=r.t; bump(s,r); take(s,r,5,":"); kind(s,r,6); kind(s,r,7); no=suite(s,r,tree,el.start+1); kind(s,r,8); }
        return event(r,tree,mixed_core::Node {tag:14,start:t.start,end:if no.id!=0 {no.end} else {yes.end},a:cond.id,b:yes.id,c:no.id});
    }
    r.bad=true; return Term {};
}
fn verify(tree: mixed_core::Tree&, expected_source: u8[:]) -> bool {
    if expected_source.len>65536 || tree.source[..]!=expected_source || tree.nodes.len<1 || tree.nodes.len>2048 || tree.bindings.len>256 {return false;}
    let s=expected_source; var r=Reader {lex:lexer::init(s)}; bump(s,r);
    while !r.bad && r.t.kind==6 {bump(s,r);}
    let function=take(s,r,1,"fn"); r.function_target=function.start+1; var count:i64=0;
    if text(s,r.t,5,"(") {
        bump(s,r);
        if !text(s,r.t,5,")") {
            loop {
                if r.bad || count>=16 {r.bad=true;break;}
                let name=r.t; if !ident(s,name) {r.bad=true;break;} bump(s,r);
                let empty:i64[0]=[]; let id=binding(s,r,tree,name,1,r.function_target,empty); activate(r,id); count+=1;
                if !text(s,r.t,5,",") {break;} bump(s,r);
            }
        }
        take(s,r,5,")");
    } else {
        let name=r.t;if !ident(s,name) {r.bad=true;}else {bump(s,r);let empty:i64[0]=[];let id=binding(s,r,tree,name,1,r.function_target,empty);activate(r,id);count=1;}
    }
    take(s,r,5,"=>"); var body=Term {};
    if text(s,r.t,1,"do") {
        take(s,r,1,"do"); take(s,r,5,":"); kind(s,r,6); kind(s,r,7);
        body=suite(s,r,tree,r.function_target); kind(s,r,8);
    } else {
        if !text(s,r.t,1,"return") {return false;}
        body=statement(s,r,tree,r.function_target);
    }
    while !r.bad && r.t.kind==6 {bump(s,r);}
    if r.bad || r.t.kind!=0 || body.id==0 {return false;}
    let root=event(r,tree,mixed_core::Node {tag:18,start:function.start,end:body.end,a:body.id,b:count,target:r.function_target});
    return !r.bad && root.id==tree.root && r.next_node==tree.nodes.len && r.next_binding==tree.bindings.len && r.loop_depth==0;
}
