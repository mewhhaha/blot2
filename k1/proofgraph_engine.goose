// Private source-bound finite U32 graph: <=/< edges, explicit Eq classes,
// deterministic two-state paths and one live proof scope. No literals,
// collection observations, branch joins, artifact authority, full C09 or
// public admission. A failed owner is discarded; no cached success is trust.
namespace proofgraph_engine;
import work;
import proofgraph_source;
import proofgraph_source_check;
struct Term { owner:u32=0, id:u32=0, version:u32=0 }
struct Edge { left:u32=0, right:u32=0, strict:bool=false, origin:u32=0, reverse:bool=false }
struct Step { state:u32=0, prev:i64=-1, edge:u32=0 }
struct Walk { status:u32=0, receipt:work::Receipt=work::Receipt {}, found:bool=false,
              actual:bool=false, count:u32=0, edges:u32[16]=[0;16] }
struct Proof { left:Term=Term {},right:Term=Term {},strict:bool=false,actual:bool=false,
               count:u32=0,edges:u32[16]=[0;16],generation:u32=0 }
struct Result { status:u32=0, receipt:work::Receipt=work::Receipt {} }
struct Query { status:u32=0, receipt:work::Receipt=work::Receipt {}, proof:Proof=Proof {} }
// status 0 success; 1 invalid; 2 proof limit; 3 semantic limit; 4 internal;
// 5 not established; 6 inconsistent declared requirements; 7 private slice limit.
struct Job {
    attempted:bool=false, active:bool=false, failed:bool=false, proof_active:bool=false,
    source_len:i64=0, source:u8[4096]=[0;4096], count:u32=0, terms:Term[8]=[Term {};8],
    parents:u32[8]=[0;8], edge_count:u32=0, edges:Edge[32]=[Edge {};32],
    generation:u32=0, proof_charge:u32=0, meter:work::Meter=work::Meter {}
}
fn code(r:work::Receipt)->u32 { return if r.status==1 {3} else if r.status==2 {2} else {4}; }
fn fail(j:Job&,status:u32,r:work::Receipt)->Result { j.failed=true; return Result {status:status,receipt:r}; }
fn term(id:u32)->Term { return Term {owner:1,id:id,version:id}; }
fn same(a:Term,b:Term)->bool { return a.owner==b.owner && a.id==b.id && a.version==b.version; }
fn valid(j:Job&,t:Term)->bool { return t.owner==1 && t.id>=1 && t.id<=j.count && t.version==t.id; }
struct Root { status:u32=0,receipt:work::Receipt=work::Receipt {},id:u32=0 }
fn root(j:Job&,id:u32)->Root {
    if j.failed || id==0 || id>j.count { return Root {status:1}; }
    var cursor=id;
    for step in 8 {
        let r=work::charge(j.meter,4,20); if r.status!=0 { j.failed=true; return Root {status:code(r),receipt:r}; }
        let parent=j.parents[cursor-1]; if parent==0 || parent>cursor { j.failed=true; return Root {status:4}; }
        if parent==cursor { return Root {id:cursor}; } cursor=parent;
    }
    j.failed=true; return Root {status:4};
}
fn add_edge(j:Job&,edge:Edge)->Result {
    if j.edge_count>=32 { return fail(j,4,work::Receipt {}); }
    let r=work::charge(j.meter,4,22); if r.status!=0 { return fail(j,code(r),r); }
    j.edges[j.edge_count]=edge; j.edge_count+=1; return Result {};
}
fn walk(j:Job&,left:u32,right:u32,strict:bool)->Walk {
    if j.failed || left==0 || left>j.count || right==0 || right>j.count { return Walk {status:4}; }
    var queue:Step[..16]=[]; var seen:bool[16]=[false;16];
    let start=(left-1)*2; queue.push(Step {state:start}); seen[start]=true;
    var head:i64=0; var found:i64=if left==right && !strict {0} else {-1};
    while head<queue.len && found<0 {
        let nr=work::charge(j.meter,4,20); if nr.status!=0 { j.failed=true; return Walk {status:code(nr),receipt:nr}; }
        let state=queue[head].state; let from=state/2+1; let current=head; head+=1;
        // Stable target-ID then source-fact edge order.
        for dest in 1..(j.count+1) {
            for k in j.edge_count {
                let er=work::charge(j.meter,4,20); if er.status!=0 { j.failed=true; return Walk {status:code(er),receipt:er}; }
                let e=j.edges[k]; if e.left!=from || e.right!=dest { continue; }
                let q=(e.right-1)*2+(if state%2==1 || e.strict {1} else {0});
                let pr=work::charge(j.meter,4,20); if pr.status!=0 { j.failed=true; return Walk {status:code(pr),receipt:pr}; }
                if !seen[q] {
                    if queue.len>=16 { j.failed=true; return Walk {status:4}; }
                    seen[q]=true; queue.push(Step {state:q,prev:current,edge:k+1});
                    if e.right==right && (!strict || q%2==1) { found=queue.len-1; break; }
                }
            }
            if found>=0 { break; }
        }
    }
    if found<0 { return Walk {}; }
    var result=Walk {found:true,actual:queue[found].state%2==1};
    var reverse:u32[16]=[0;16]; var size:i64=0; var cursor=found;
    while cursor>0 {
        let r=work::charge(j.meter,4,20); if r.status!=0 { j.failed=true; return Walk {status:code(r),receipt:r}; }
        if size>=16 || queue[cursor].edge==0 { j.failed=true; return Walk {status:4}; }
        reverse[size]=queue[cursor].edge; size+=1; cursor=queue[cursor].prev;
    }
    result.count=size as u32;
    for i in size {
        let r=work::charge(j.meter,4,20); if r.status!=0 { j.failed=true; return Walk {status:code(r),receipt:r}; }
        result.edges[i]=reverse[size-1-i];
    }
    return result;
}
fn begin(source:u8[:],j:Job&)->Result {
    if j.failed || j.attempted { return fail(j,4,work::Receipt {}); } j.attempted=true;
    var p,ps=proofgraph_source::parse(source); if ps!=0 { return fail(j,if ps==2 {7} else {1},work::Receipt {}); }
    let checked=proofgraph_source_check::verify(source,p,j.meter,4);
    if checked.status!=0 { return fail(j,checked.status,checked.receipt); }
    j.source_len=source.len; for i in source.len { j.source[i]=source[i]; }
    j.count=p.count;
    for i in p.count {
        let r=work::charge(j.meter,4,21); if r.status!=0 { return fail(j,code(r),r); }
        let id=i+1; j.terms[i]=term(id); j.parents[i]=id;
    }
    for i in p.facts_count {
        let r=work::charge(j.meter,4,20); if r.status!=0 { return fail(j,code(r),r); }
        let f=p.facts[i];
        let one=add_edge(j,Edge {left:f.left,right:f.right,strict:f.kind==2,origin:i+1});
        if one.status!=0 { return one; }
        if f.kind==3 {
            let two=add_edge(j,Edge {left:f.right,right:f.left,origin:i+1,reverse:true});
            if two.status!=0 { return two; }
            let l=root(j,f.left); if l.status!=0 { return fail(j,l.status,l.receipt); }
            let rroot=root(j,f.right); if rroot.status!=0 { return fail(j,rroot.status,rroot.receipt); }
            let union=work::charge(j.meter,4,20); if union.status!=0 { return fail(j,code(union),union); }
            if l.id<rroot.id { j.parents[rroot.id-1]=l.id; } else if rroot.id<l.id { j.parents[l.id-1]=rroot.id; }
        }
    }
    // An impossible declared requirement is rejected instead of authorizing
    // arbitrary evidence. Bounds and helper graph visits share this meter.
    for i in j.count {
        let id=i+1; let cycle=walk(j,id,id,true);
        if cycle.status!=0 { return fail(j,cycle.status,cycle.receipt); }
        if cycle.found { return fail(j,6,work::Receipt {}); }
    }
    j.active=true; return Result {};
}
fn query(j:Job&,left:Term,right:Term,strict:bool)->Query {
    if j.failed || !j.active || j.proof_active { j.failed=true; return Query {status:4}; }
    let lr=work::charge(j.meter,4,20); if lr.status!=0 { j.failed=true; return Query {status:code(lr),receipt:lr}; }
    if !valid(j,left) { j.failed=true; return Query {status:1}; }
    let rr=work::charge(j.meter,4,20); if rr.status!=0 { j.failed=true; return Query {status:code(rr),receipt:rr}; }
    if !valid(j,right) { j.failed=true; return Query {status:1}; }
    let lentry=work::charge(j.meter,4,20); if lentry.status!=0 { j.failed=true; return Query {status:code(lentry),receipt:lentry}; }
    if !same(j.terms[left.id-1],left) { j.failed=true; return Query {status:1}; }
    let rentry=work::charge(j.meter,4,20); if rentry.status!=0 { j.failed=true; return Query {status:code(rentry),receipt:rentry}; }
    if !same(j.terms[right.id-1],right) { j.failed=true; return Query {status:1}; }
    let result=walk(j,left.id,right.id,strict); if result.status!=0 { return Query {status:result.status,receipt:result.receipt}; }
    if !result.found { return Query {status:5}; }
    if j.generation==4294967295 { j.failed=true; return Query {status:4}; }
    // One evidence record and one prerequisite link per source edge, charged
    // separately before publishing any candidate.
    for i in 0..(result.count+1) { let r=work::charge(j.meter,4,22); if r.status!=0 { j.failed=true; return Query {status:code(r),receipt:r}; } }
    j.generation+=1; j.proof_charge=result.count+1; j.proof_active=true;
    return Query {proof:Proof {left:left,right:right,strict:strict,actual:result.actual,count:result.count,edges:result.edges,generation:j.generation}};
}
fn drop(j:Job&)->Result {
    if j.failed || !j.active || !j.proof_active || j.proof_charge==0 { return fail(j,4,work::Receipt {}); }
    for i in j.proof_charge {
        let r=work::charge(j.meter,4,20); if r.status!=0 { return fail(j,code(r),r); }
        if j.meter.proof_edges==0 { return fail(j,4,work::Receipt {}); } j.meter.proof_edges-=1;
    }
    j.proof_active=false; j.proof_charge=0; return Result {};
}
fn finish(j:Job&)->Result {
    if j.failed || !j.active || j.proof_active { return fail(j,4,work::Receipt {}); }
    for i in j.edge_count {
        let r=work::charge(j.meter,4,20); if r.status!=0 { return fail(j,code(r),r); }
        if j.meter.proof_edges==0 { return fail(j,4,work::Receipt {}); } j.meter.proof_edges-=1;
    }
    j.active=false; return Result {};
}
