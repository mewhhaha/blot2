// Scratch source-revalidated U32 successor refinement adapter. This is not the
// general fact graph, a portable artifact, or complete C09 work accounting.
namespace predflow_guard;
import unified_core;
import predflow_shape;
import work;
struct Evidence { guard_id:i64=0, guard_true:bool=false, subject:i64=0, reference:i64=0, one:i64=0, addition:i64=0, path_count:u32=0, path_guard:i64[16]=[0;16], path_true:bool[16]=[false;16] }
struct Result { status:i64=0, receipt:work::Receipt=work::Receipt {}, evidence:Evidence[]=[] }
// Positive fact is an exact dominating x<MAX node; negative is its false edge
// (x==MAX). Different guard origins are conservatively discarded at joins.
struct Rel { left:i64=0,right:i64=0,strict:bool=false,guard_id:i64=0,guard_true:bool=false }
struct Env { alive:bool=true, facts:i64[129]=[0;129], guard_true:bool[129]=[false;129], aliases:i64[129]=[0;129], rel_count:i64=0, relations:Rel[64]=[Rel {};64] }
struct Flow { status:i64=0, env:Env=Env {} }
struct Cond { status:i64=0, yes:Env=Env {}, no:Env=Env {} }
struct Action { kind:i64=0, node:i64=0 }
struct Ctx { steps:i64=0, receipt:work::Receipt=work::Receipt {}, events:Evidence[>..]=[] }
fn tick(ctx:Ctx&,meter:work::Meter&) -> bool {
    if ctx.steps>=32768 {return false;}
    let r=work::charge(meter,4,20);if r.status!=0 {ctx.receipt=r;return false;}
    ctx.steps+=1;return true;
}
fn ref(p:unified_core::Program&,id:i64,aliases:i64[:])->i64 {
    var cur=id;var steps=0;
    while cur>0 && cur<=p.nodes.len && p.nodes[cur-1].tag==8 {steps+=1;if steps>64{return -1;}cur=p.nodes[cur-1].a;}
    if cur<1 || cur>p.nodes.len {return -1;}let x=p.nodes[cur-1];
    if x.tag!=1 || x.a<0 || x.a>=aliases.len {return -1;}return aliases[x.a];
}
fn literal(p:unified_core::Program&,id:i64,value:u32)->bool {return id>0 && id<=p.nodes.len && p.nodes[id-1].tag==2 && p.nodes[id-1].literal==value;}
struct Constraint { slot:i64=-1, nonmax_on_true:bool=false, only_true:bool=false }
fn guard_slot(p:unified_core::Program&,id:i64,aliases:i64[:])->Constraint {
    var cur=id;var steps=0;
    while cur>0 && cur<=p.nodes.len && p.nodes[cur-1].tag==8 {steps+=1;if steps>64{return Constraint {};}cur=p.nodes[cur-1].a;}
    if cur<1 || cur>p.nodes.len {return Constraint {};}let x=p.nodes[cur-1];
    if x.tag==9 && literal(p,x.b,4294967295) {return Constraint {slot:ref(p,x.a,aliases),nonmax_on_true:true};}
    if x.tag==18 && literal(p,x.b,4294967294) {return Constraint {slot:ref(p,x.a,aliases),nonmax_on_true:true};}
    if x.tag==9 && literal(p,x.a,4294967294) {return Constraint {slot:ref(p,x.b,aliases),nonmax_on_true:false};}
    if x.tag==18 && literal(p,x.a,4294967295) {return Constraint {slot:ref(p,x.b,aliases),nonmax_on_true:false};}
    // For typed U32 y, x < y implies x < MAX. Its false edge does not
    // establish x==MAX unless y is the MAX literal handled above.
    if x.tag==9 {return Constraint {slot:ref(p,x.a,aliases),nonmax_on_true:true,only_true:true};}
    return Constraint {};
}
fn refine(env:Env,slot:i64,id:i64,positive:bool,edge_true:bool)->Env {
    var out=env;if !out.alive || slot<0 || slot>=129 {return out;}
    let old=out.facts[slot];
    if (positive && old<0) || (!positive && old>0) {out.alive=false;return out;}
    if old==0 {out.facts[slot]=if positive {id} else {-id};out.guard_true[slot]=edge_true;}
    return out;
}

struct Aug {status:i64=0,env:Env=Env {}}
struct Route {status:i64=0,terminal:i64=-1,count:u32=0,guards:i64[16]=[0;16],truth:bool[16]=[false;16]}
fn same_rel(a:Rel,b:Rel)->bool {return a.left==b.left && a.right==b.right && a.strict==b.strict && a.guard_id==b.guard_id && a.guard_true==b.guard_true;}
fn rel_before(a:Rel,b:Rel)->bool {
    if a.left!=b.left{return a.left<b.left;}if a.right!=b.right{return a.right<b.right;}
    if a.guard_id!=b.guard_id{return a.guard_id<b.guard_id;}
    if a.guard_true!=b.guard_true{return !a.guard_true;}return !a.strict && b.strict;
}
// Source-derived facts live only in their branch state. This scratch active
// set is not yet the compiler-wide active-edge owner or a portable receipt.
fn add_relation(env:Env,left:i64,right:i64,strict:bool,id:i64,edge_true:bool,ctx:Ctx&,meter:work::Meter&)->Aug {
    var out=env;if !out.alive || left<0 || right<0 || left>=129 || right>=129 {return Aug {env:out};}
    if left==right {if strict {out.alive=false;}return Aug {env:out};}
    let item=Rel {left:left,right:right,strict:strict,guard_id:id,guard_true:edge_true};
    var where:i64=0;
    while where<out.rel_count {
        if !tick(ctx,meter){return Aug {status:2};}
        if same_rel(out.relations[where],item){return Aug {env:out};}
        if rel_before(item,out.relations[where]) {break;}where+=1;
    }
    if out.rel_count>=64 {return Aug {status:2};}
    var i=out.rel_count;while i>where {if !tick(ctx,meter){return Aug {status:2};}out.relations[i]=out.relations[i-1];i-=1;}
    out.relations[where]=item;out.rel_count+=1;
    if strict {out=refine(out,left,id,true,edge_true);}
    return Aug {env:out};
}
// Deterministic bounded adjacency traversal. A <= path to any active
// non-MAX fact proves the original subject is also non-MAX.
fn route(env:Env,subject:i64,ctx:Ctx&,meter:work::Meter&)->Route {
    if subject<0 || subject>=129 || env.facts[subject]<0 {return Route {status:5};}
    var seen:bool[129]=[false;129];var queue:i64[129]=[0;129];var previous:i64[129]=[-1;129];var via:i64[129]=[-1;129];
    var head:i64=0;var length:i64=1;queue[0]=subject;seen[subject]=true;var found:i64=-1;
    while head<length {
        if !tick(ctx,meter){return Route {status:2};}let current=queue[head];head+=1;
        if env.facts[current]>0 {found=current;break;}
        for i in env.rel_count {
            if !tick(ctx,meter){return Route {status:2};}let e=env.relations[i];
            if e.left!=current || e.right<0 || e.right>=129 || seen[e.right] {continue;}
            if length>=129 {return Route {status:2};}
            seen[e.right]=true;previous[e.right]=current;via[e.right]=i;queue[length]=e.right;length+=1;
        }
    }
    if found<0 {return Route {status:5};}
    var reverse:i64[16]=[0;16];var n:i64=0;var cur=found;
    while cur!=subject {
        if !tick(ctx,meter){return Route {status:2};}
        if n>=16 || cur<0 || cur>=129 || via[cur]<0 {return Route {status:2};}
        reverse[n]=via[cur];n+=1;cur=previous[cur];
    }
    var out=Route {terminal:found,count:n as u32};
    for i in n {if !tick(ctx,meter){return Route {status:2};}let e=env.relations[reverse[n-1-i]];out.guards[i]=e.guard_id;out.truth[i]=e.guard_true;}
    return out;
}
// Both predecessors survive only facts with the same source evidence; this
// conservatively drops equivalent facts proven through different guards.
fn merge(a:Env,b:Env)->Env {
    if !a.alive {return b;}if !b.alive {return a;}
    var out=a;
    for i in 129 {if a.facts[i]!=b.facts[i] || a.guard_true[i]!=b.guard_true[i] {out.facts[i]=0;out.guard_true[i]=false;}if a.aliases[i]!=b.aliases[i] {out.aliases[i]=i;}}
    out.rel_count=0;
    for i in a.rel_count {for j in b.rel_count {if same_rel(a.relations[i],b.relations[j]) {out.relations[out.rel_count]=a.relations[i];out.rel_count+=1;break;}}}
    return out;
}
fn value(p:unified_core::Program&,id:i64,env:Env,ctx:Ctx&,meter:work::Meter&)->i64 {
    if !env.alive {return 0;}var actions:Action[>..]=[];actions.push(Action {kind:1,node:id});
    while actions.len>0 {
        if !tick(ctx,meter) {return 2;}
        let act=actions[actions.len-1];actions.pop();
        if act.node<1 || act.node>p.nodes.len {return 1;}let n=p.nodes[act.node-1];
        if act.kind==2 {
            let a=p.nodes[n.a-1];let b=p.nodes[n.b-1];
            let simple=(a.tag==2 && a.literal==0) || (b.tag==2 && b.literal==0) ||
                (a.tag==2 && b.tag==2 && (a.literal as u64)+(b.literal as u64)<=4294967295);
            if !simple {
                var slot:i64=-1;var one:i64=0;var reference:i64=0;
                if literal(p,n.b,1) {slot=ref(p,n.a,env.aliases);one=n.b;reference=n.a;}
                else if literal(p,n.a,1) {slot=ref(p,n.b,env.aliases);one=n.a;reference=n.b;}
                let path=route(env,slot,ctx,meter);if path.status!=0 {return path.status;}
                ctx.events.push(Evidence {guard_id:env.facts[path.terminal],guard_true:env.guard_true[path.terminal],subject:slot,reference:reference,one:one,addition:act.node,path_count:path.count,path_guard:path.guards,path_true:path.truth});
            }
        } else if act.kind==1 {
            if n.tag==1 || n.tag==2 {continue;}
            if n.tag==3 {actions.push(Action {kind:2,node:act.node});actions.push(Action {kind:1,node:n.b});actions.push(Action {kind:1,node:n.a});}
            else if n.tag==4 || n.tag==5 || n.tag==6 || n.tag==7 {actions.push(Action {kind:1,node:n.b});actions.push(Action {kind:1,node:n.a});}
            else if n.tag==8 {actions.push(Action {kind:1,node:n.a});}
            else {return 1;}
        } else {return 1;}
    }
    return 0;
}
recursive fn condition(p:unified_core::Program&,id:i64,env:Env,ctx:Ctx&,meter:work::Meter&,depth:i64)->Cond {
    if depth>64 {return Cond {status:2};}
    if !env.alive {return Cond {yes:env,no:env};}
    if !tick(ctx,meter) {return Cond {status:2};}
    if id<1 || id>p.nodes.len {return Cond {status:1};}
    let n=p.nodes[id-1];
    if n.tag==8 {return condition(p,n.a,env,ctx,meter,depth+1);}
    if n.tag==10 || n.tag==11 {
        var yes=env;var no=env;if n.tag==10 {no.alive=false;}else {yes.alive=false;}
        return Cond {yes:yes,no:no};
    }
    if n.tag==9 || n.tag==18 {
        let a=value(p,n.a,env,ctx,meter);if a!=0 {return Cond {status:a};}
        let b=value(p,n.b,env,ctx,meter);if b!=0 {return Cond {status:b};}
        let rule=guard_slot(p,id,env.aliases);
        var yes=env;var no=env;
        if rule.slot>=0 {yes=refine(env,rule.slot,id,rule.nonmax_on_true,true);if !rule.only_true {no=refine(env,rule.slot,id,!rule.nonmax_on_true,false);}}
        let left=ref(p,n.a,env.aliases);let right=ref(p,n.b,env.aliases);
        if left>=0 && right>=0 {
            let yt=add_relation(yes,left,right,n.tag==9,id,true,ctx,meter);if yt.status!=0{return Cond {status:yt.status};}yes=yt.env;
            let nf=add_relation(no,right,left,n.tag==18,id,false,ctx,meter);if nf.status!=0{return Cond {status:nf.status};}no=nf.env;
        }
        return Cond {yes:yes,no:no};
    }
    if n.tag==12 || n.tag==13 {
        // Flatten associative left spines, avoiding recursion proportional to
        // a long unparenthesized && or || chain.
        var rest:i64[2048]=[0;2048];var remaining:i64=0;var cursor=id;
        while cursor>0 && cursor<=p.nodes.len && p.nodes[cursor-1].tag==n.tag {
            let item=p.nodes[cursor-1];if remaining>=2048 {return Cond {status:2};}rest[remaining]=item.b;remaining+=1;cursor=item.a;
            if cursor!=id && !tick(ctx,meter) {return Cond {status:2};}
        }
        var result=condition(p,cursor,env,ctx,meter,depth+1);if result.status!=0 {return result;}
        while remaining>0 {
            remaining-=1;let child=rest[remaining];
            let before=if n.tag==12 {result.yes} else {result.no};
            if !before.alive {continue;}
            let rhs=condition(p,child,before,ctx,meter,depth+1);if rhs.status!=0 {return rhs;}
            if n.tag==12 {result.no=merge(result.no,rhs.no);result.yes=rhs.yes;}
            else {result.yes=merge(result.yes,rhs.yes);result.no=rhs.no;}
        }
        return result;
    }
    return Cond {status:1};
}
recursive fn sequence(p:unified_core::Program&,id:i64,initial:Env,ctx:Ctx&,meter:work::Meter&,depth:i64)->Flow {
    if depth>64 {return Flow {status:2};}var env=initial;
    var todo:i64[2048]=[0;2048];var count:i64=1;todo[0]=id;
    while count>0 && env.alive {
        if !tick(ctx,meter) {return Flow {status:2};}
        count-=1;let current=todo[count];if current<1 || current>p.nodes.len{return Flow {status:1};}
        let n=p.nodes[current-1];
        if n.tag==17 {if count+2>2048 {return Flow {status:2};}todo[count]=n.b;todo[count+1]=n.a;count+=2;}
        else if n.tag==14 {
            let st=value(p,n.a,env,ctx,meter);if st!=0 {return Flow {status:st};}
            let root=ref(p,n.a,env.aliases);env.aliases[n.b]=if root<0 {n.b} else {root};
        } else if n.tag==15 {
            let result=condition(p,n.a,env,ctx,meter,0);if result.status!=0 {return Flow {status:result.status};}env.alive=false;
        } else if n.tag==16 {
            let c=condition(p,n.a,env,ctx,meter,0);if c.status!=0 {return Flow {status:c.status};}
            var yes=Flow {env:c.yes};var no=Flow {env:c.no};
            if c.yes.alive {yes=sequence(p,n.b,c.yes,ctx,meter,depth+1);if yes.status!=0{return yes;}}
            if n.c!=0 && c.no.alive {no=sequence(p,n.c,c.no,ctx,meter,depth+1);if no.status!=0{return no;}}
            env=merge(yes.env,no.env);
        } else {return Flow {status:1};}
    }
    return Flow {env:env};
}
fn check_with_work(expected:u8[:],p:unified_core::Program&,meter:work::Meter&)->Result {
    if !predflow_shape::verify(expected,p) {return Result {status:1};}
    var initial=Env {};for i in 129 {initial.aliases[i]=i;}
    var ctx=Ctx {};let checked=sequence(p,p.root,initial,ctx,meter,0);
    if checked.status!=0 {return Result {status:checked.status,receipt:ctx.receipt};}
    return Result {evidence:copy(ctx.events)};
}
fn check(expected:u8[:],p:unified_core::Program&)->Result {var meter=work::Meter {};return check_with_work(expected,p,meter);}
