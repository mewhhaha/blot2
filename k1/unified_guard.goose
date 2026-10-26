// Scratch-only source-revalidated, true-edge successor evidence. This is a
// narrow compiler-owned proof job, not K1's general graph or C09 metering.
namespace unified_guard;
import unified_core;
import unified_shape;
struct Evidence { guard_id:i64=0, subject:i64=0, reference:i64=0, one:i64=0, addition:i64=0 }
struct Result { status:i64=0, evidence:Evidence[]=[] }
// action kinds: node 1, set fact 2, restore fact 3, check add 4, bind alias 5.
struct Action { kind:i64=0, node:i64=0, slot:i64=0, old:i64=0, guard_id:i64=0 }
fn node(stack:Action[>..]&,id:i64) {stack.push(Action {kind:1,node:id});}
fn ref(p:unified_core::Program&,id:i64,aliases:i64[:]) -> i64 {
    var cur=id;var steps=0;
    while cur>0 && cur<=p.nodes.len && p.nodes[cur-1].tag==8 {
        steps+=1;if steps>64 {return -1;}cur=p.nodes[cur-1].a;
    }
    if cur<1 || cur>p.nodes.len {return -1;}
    let x=p.nodes[cur-1];if x.tag!=1 || x.a<0 || x.a>=aliases.len {return -1;}
    return aliases[x.a];
}
fn literal(p:unified_core::Program&,id:i64,value:u32) -> bool {
    return id>0 && id<=p.nodes.len && p.nodes[id-1].tag==2 && p.nodes[id-1].literal==value;
}
fn guard_slot(p:unified_core::Program&,id:i64,aliases:i64[:]) -> i64 {
    var cur=id;var steps=0;
    while cur>0 && cur<=p.nodes.len && p.nodes[cur-1].tag==8 {steps+=1;if steps>64 {return -1;}cur=p.nodes[cur-1].a;}
    if cur<1 || cur>p.nodes.len {return -1;}let x=p.nodes[cur-1];
    if x.tag!=9 || !literal(p,x.b,4294967295) {return -1;}
    return ref(p,x.a,aliases);
}
fn check(expected:u8[:],p:unified_core::Program&) -> Result {
    if !unified_shape::verify(expected,p) {return Result {status:1};}
    var aliases:i64[129]=[0;129];for i in 129 {aliases[i]=i;}
    var facts:i64[129]=[0;129];var events:Evidence[>..]=[];var actions:Action[>..]=[];
    node(actions,p.root);var visits:i64=0;
    while actions.len>0 {
        visits+=1;if visits>32768 {return Result {status:2};}
        let a=actions[actions.len-1];actions.pop();
        if a.kind==2 {facts[a.slot]=a.guard_id;continue;}
        if a.kind==3 {facts[a.slot]=a.old;continue;}
        if a.kind==5 {let q=p.nodes[a.node-1];let v=ref(p,q.a,aliases);aliases[q.b]=if v<0 {q.b} else {v};continue;}
        if a.kind==4 {
            let q=p.nodes[a.node-1];let left=p.nodes[q.a-1];let right=p.nodes[q.b-1];
            let simple=(left.tag==2 && left.literal==0) || (right.tag==2 && right.literal==0) ||
                (left.tag==2 && right.tag==2 && (left.literal as u64)+(right.literal as u64)<=4294967295);
            if !simple {
                var subject:i64=-1;var one:i64=0;var reference:i64=0;
                if literal(p,q.b,1) {subject=ref(p,q.a,aliases);one=q.b;reference=q.a;}
                else if literal(p,q.a,1) {subject=ref(p,q.b,aliases);one=q.a;reference=q.b;}
                if subject<0 || subject>=facts.len || facts[subject]==0 {return Result {status:5};}
                events.push(Evidence {guard_id:facts[subject],subject:subject,reference:reference,one:one,addition:a.node});
            } continue;
        }
        if a.kind!=1 || a.node<1 || a.node>p.nodes.len {return Result {status:1};}
        let n=p.nodes[a.node-1];
        if n.tag==1 || n.tag==2 || n.tag==10 || n.tag==11 {continue;}
        if n.tag==3 {actions.push(Action {kind:4,node:a.node});node(actions,n.b);node(actions,n.a);}
        else if n.tag==4 || n.tag==5 || n.tag==6 || n.tag==7 || n.tag==9 || n.tag==12 || n.tag==13 {node(actions,n.b);node(actions,n.a);}
        else if n.tag==8 || n.tag==15 {node(actions,n.a);}
        else if n.tag==14 {actions.push(Action {kind:5,node:a.node});node(actions,n.a);}
        else if n.tag==17 {node(actions,n.b);node(actions,n.a);}
        else if n.tag==16 {
            if n.c!=0 {node(actions,n.c);}
            let slot=guard_slot(p,n.a,aliases);
            if slot>=0 {actions.push(Action {kind:3,slot:slot,old:facts[slot]});node(actions,n.b);actions.push(Action {kind:2,slot:slot,guard_id:n.a});}
            else {node(actions,n.b);}
            node(actions,n.a);
        } else {return Result {status:1};}
    }
    return Result {evidence:events};
}
