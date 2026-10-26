// Scratch source-revalidated U32 successor refinement adapter. This is not the
// general fact graph, a portable artifact, or complete C09 work accounting.
namespace unified_guard;
import unified_core;
import unified_shape;
import work;
struct Evidence { guard_id:i64=0, subject:i64=0, reference:i64=0, one:i64=0, addition:i64=0 }
struct Result { status:i64=0, receipt:work::Receipt=work::Receipt {}, evidence:Evidence[]=[] }
// Positive fact is an exact dominating x<MAX node; negative is its false edge
// (x==MAX). Different guard origins are conservatively discarded at joins.
struct Env { alive:bool=true, facts:i64[129]=[0;129], aliases:i64[129]=[0;129] }
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
fn guard_slot(p:unified_core::Program&,id:i64,aliases:i64[:])->i64 {
    var cur=id;var steps=0;
    while cur>0 && cur<=p.nodes.len && p.nodes[cur-1].tag==8 {steps+=1;if steps>64{return -1;}cur=p.nodes[cur-1].a;}
    if cur<1 || cur>p.nodes.len {return -1;}let x=p.nodes[cur-1];
    if x.tag!=9 || !literal(p,x.b,4294967295) {return -1;}return ref(p,x.a,aliases);
}
fn refine(env:Env,slot:i64,id:i64,positive:bool)->Env {
    var out=env;if !out.alive || slot<0 || slot>=129 {return out;}
    let old=out.facts[slot];
    if (positive && old<0) || (!positive && old>0) {out.alive=false;return out;}
    if old==0 {out.facts[slot]=if positive {id} else {-id};}
    return out;
}
// Both predecessors survive only facts with the same source evidence; this
// conservatively drops equivalent facts proven through different guards.
fn merge(a:Env,b:Env)->Env {
    if !a.alive {return b;}if !b.alive {return a;}
    var out=a;
    for i in 129 {if a.facts[i]!=b.facts[i] {out.facts[i]=0;}if a.aliases[i]!=b.aliases[i] {out.aliases[i]=i;}}
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
                if slot<0 || slot>=129 || env.facts[slot]<=0 {return 5;}
                ctx.events.push(Evidence {guard_id:env.facts[slot],subject:slot,reference:reference,one:one,addition:act.node});
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
    if n.tag==9 {
        let a=value(p,n.a,env,ctx,meter);if a!=0 {return Cond {status:a};}
        let b=value(p,n.b,env,ctx,meter);if b!=0 {return Cond {status:b};}
        let slot=guard_slot(p,id,env.aliases);
        if slot<0 {return Cond {yes:env,no:env};}
        return Cond {yes:refine(env,slot,id,true),no:refine(env,slot,id,false)};
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
            let st=value(p,n.a,env,ctx,meter);if st!=0 {return Flow {status:st};}env.alive=false;
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
    if !unified_shape::verify(expected,p) {return Result {status:1};}
    var initial=Env {};for i in 129 {initial.aliases[i]=i;}
    var ctx=Ctx {};let checked=sequence(p,p.root,initial,ctx,meter,0);
    if checked.status!=0 {return Result {status:checked.status,receipt:ctx.receipt};}
    return Result {evidence:copy(ctx.events)};
}
fn check(expected:u8[:],p:unified_core::Program&)->Result {var meter=work::Meter {};return check_with_work(expected,p,meter);}
