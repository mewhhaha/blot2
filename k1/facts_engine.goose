// Compiler-owned private three-term/two-guard proof graph. Facts are seeded
// only after source checking; queries produce candidate evidence requiring
// facts_validate before use. This is not a general K1 solver, durable artifact,
// immutable owner identity, or a complete shared C09 schedule.
namespace facts_engine;
import work;
import proof_scopes;
import facts_source;
import facts_source_check;
struct Term { owner: u32 = 0, id: u32 = 0, version: u32 = 0 }
struct Edge { left: u32 = 0, right: u32 = 0, strict: bool = false, origin: u32 = 0,
              truth: bool = false, scope: u32 = 0, handle: proof_scopes::Handle = proof_scopes::Handle {} }
struct Proof { left: Term = Term {}, right: Term = Term {}, strict: bool = false,
               actual_strict: bool = false, count: u32 = 0, first: u32 = 0, second: u32 = 0,
               scope: u32 = 0, handle: proof_scopes::Handle = proof_scopes::Handle {} }
struct Step { state: u32 = 0, previous: i64 = -1, edge: u32 = 0 }
struct Check { status: u32 = 0, receipt: work::Receipt = work::Receipt {} }
// 0 candidate, 1 invalid, 2 proof limit, 3 semantic limit, 4 internal,
// 5 not established, 6 unreachable contradictory guarded scope.
struct Query { status: u32 = 0, receipt: work::Receipt = work::Receipt {}, proof: Proof = Proof {} }
struct Job {
    attempted: bool = false, active: bool = false, inner: bool = false, proof_active: bool = false,
    outer_truth: bool = false, inner_truth: bool = false,
    source_len: i64 = 0, source: u8[4096] = [0;4096],
    guards: facts_source::Guard[2] = [facts_source::Guard {};2],
    terms: Term[3] = [Term {};3], edges: Edge[2] = [Edge {};2],
    root: proof_scopes::Handle = proof_scopes::Handle {}, outer: proof_scopes::Handle = proof_scopes::Handle {},
    inner_scope: proof_scopes::Handle = proof_scopes::Handle {}, proof_scope: proof_scopes::Handle = proof_scopes::Handle {},
    proof_handle: proof_scopes::Handle = proof_scopes::Handle {}, graph: proof_scopes::Job = proof_scopes::Job {}
}
fn code(r: work::Receipt) -> u32 { return if r.status == 1 { 3 } else if r.status == 2 { 2 } else { 4 }; }
fn fail(job: Job&, status: u32, r: work::Receipt) -> Check { job.graph.failed = true; return Check { status: status, receipt: r }; }
fn failed_scope(job: Job&, r: proof_scopes::Result) -> Check { return fail(job,if r.status==2 { code(r.receipt) } else { 4 },r.receipt); }
fn same(a: Term,b: Term) -> bool { return a.owner==b.owner && a.id==b.id && a.version==b.version; }
fn term(id: u32) -> Term { return Term { owner:1, id:id, version:id }; }
fn valid_term(t: Term) -> bool { return t.id>=1 && t.id<=3 && same(t,term(t.id)); }
fn normalized(g: facts_source::Guard, truth: bool, origin: u32, scope: u32) -> Edge {
    return if truth { Edge { left:g.left,right:g.right,strict:g.strict,origin:origin,truth:true,scope:scope } }
      else { Edge { left:g.right,right:g.left,strict:!g.strict,origin:origin,truth:false,scope:scope } };
}
fn begin(source: u8[:], job: Job&, outer_truth: bool) -> Check {
    if job.attempted || job.graph.failed { return fail(job,4,work::Receipt {}); }
    job.attempted = true;
    var p, status = facts_source::parse(source);
    if status != 0 { return fail(job,1,work::Receipt {}); }
    let checked=facts_source_check::verify(source,p,job.graph.meter,4);
    if checked.status != 0 { return fail(job,checked.status,checked.receipt); }
    for i in 3 {
        let r=work::charge(job.graph.meter,4,21); if r.status!=0 { return fail(job,code(r),r); }
        job.terms[i]=term((i+1) as u32);
    }
    let none=proof_scopes::Handle {};
    let root=proof_scopes::open(job.graph,none); if root.status!=0 { return failed_scope(job,root); }
    let outer=proof_scopes::open(job.graph,root.handle); if outer.status!=0 { return failed_scope(job,outer); }
    let fact=proof_scopes::add(job.graph,outer.handle,none,none); if fact.status!=0 { return failed_scope(job,fact); }
    var edge=normalized(p.guards[0],outer_truth,1,1); edge.handle=fact.handle;
    job.source_len=source.len; for i in source.len { job.source[i]=source[i]; }
    job.guards=p.guards; job.root=root.handle; job.outer=outer.handle; job.edges[0]=edge;
    job.outer_truth=outer_truth; job.active=true;
    return Check {};
}
fn enter_inner(job: Job&, truth: bool) -> Check {
    if job.graph.failed || !job.active || job.inner || job.proof_active || !job.outer_truth { return fail(job,4,work::Receipt {}); }
    let r=work::charge(job.graph.meter,4,20); if r.status!=0 { return fail(job,code(r),r); }
    var edge=normalized(job.guards[1],truth,2,2);
    let prior=work::charge(job.graph.meter,4,20); if prior.status!=0 { return fail(job,code(prior),prior); }
    let first=job.edges[0];
    // Only two different-operand edges exist. A reverse pair with any strict
    // edge is contradictory; do not derive arbitrary facts from this branch.
    if first.left==edge.right && first.right==edge.left && (first.strict || edge.strict) { return Check { status:6 }; }
    let scope=proof_scopes::open(job.graph,job.outer); if scope.status!=0 { return failed_scope(job,scope); }
    let none=proof_scopes::Handle {};
    let fact=proof_scopes::add(job.graph,scope.handle,none,none); if fact.status!=0 { return failed_scope(job,fact); }
    edge.handle=fact.handle; job.edges[1]=edge; job.inner_scope=scope.handle; job.inner_truth=truth; job.inner=true;
    return Check {};
}
fn query_fail(job: Job&, r: work::Receipt) -> Query { job.graph.failed=true; return Query { status:code(r),receipt:r }; }
fn query(job: Job&, left: Term, right: Term, strict: bool) -> Query {
    if job.graph.failed || !job.active || job.proof_active { job.graph.failed=true; return Query { status:4 }; }
    let lp=work::charge(job.graph.meter,4,20); if lp.status!=0 { return query_fail(job,lp); }
    if !valid_term(left) { job.graph.failed=true; return Query { status:1 }; }
    let lr=work::charge(job.graph.meter,4,20); if lr.status!=0 { return query_fail(job,lr); }
    if !same(job.terms[left.id-1],left) { job.graph.failed=true; return Query { status:1 }; }
    let rp=work::charge(job.graph.meter,4,20); if rp.status!=0 { return query_fail(job,rp); }
    if !valid_term(right) { job.graph.failed=true; return Query { status:1 }; }
    let rr=work::charge(job.graph.meter,4,20); if rr.status!=0 { return query_fail(job,rr); }
    if !same(job.terms[right.id-1],right) { job.graph.failed=true; return Query { status:1 }; }
    var queue: Step[..6] = []; var seen: bool[6] = [false;6];
    let start=(left.id-1)*2; queue.push(Step { state:start }); seen[start]=true;
    var head: i64=0; var found: i64 = if left.id==right.id && !strict { 0 } else { -1 };
    let count = if job.inner { 2 } else { 1 };
    while head<queue.len && found<0 {
        let node=work::charge(job.graph.meter,4,20); if node.status!=0 { return query_fail(job,node); }
        let state=queue[head].state; let from=state/2+1; let current=head; head+=1;
        // Stable destination term-ID order; each edge inspection is charged.
        for dest in 1..4 {
            for i in count {
                let r=work::charge(job.graph.meter,4,20); if r.status!=0 { return query_fail(job,r); }
                let edge=job.edges[i]; if edge.left!=from || edge.right!=dest { continue; }
                let is_strict=state%2==1 || edge.strict; let next=(edge.right-1)*2+(if is_strict { 1 } else { 0 });
                let probe=work::charge(job.graph.meter,4,20); if probe.status!=0 { return query_fail(job,probe); }
                if !seen[next] {
                    if queue.len>=6 { job.graph.failed=true; return Query { status:4 }; }
                    seen[next]=true; queue.push(Step { state:next,previous:current,edge:(i+1) as u32 });
                    if edge.right==right.id && (!strict || is_strict) { found=queue.len-1; break; }
                }
            }
            if found>=0 { break; }
        }
    }
    if found<0 { return Query { status:5 }; }
    var path: u32[2] = [0;2]; var length: i64=0; var cursor=found;
    while cursor>0 {
        let r=work::charge(job.graph.meter,4,20); if r.status!=0 { return query_fail(job,r); }
        if length>=2 || queue[cursor].edge==0 { job.graph.failed=true; return Query { status:4 }; }
        path[length]=queue[cursor].edge; length+=1; cursor=queue[cursor].previous;
    }
    let first=if length>0 { path[length-1] } else { 0 };
    let second=if length>1 { path[0] } else { 0 };
    let parent=if job.inner { job.inner_scope } else { job.outer };
    let scope=proof_scopes::open(job.graph,parent); if scope.status!=0 { let f=failed_scope(job,scope); return Query { status:f.status,receipt:f.receipt }; }
    let none=proof_scopes::Handle {};
    let one=if first!=0 { job.edges[first-1].handle } else { none };
    let two=if second!=0 { job.edges[second-1].handle } else { none };
    let evidence=proof_scopes::add(job.graph,scope.handle,one,two);
    if evidence.status!=0 { let f=failed_scope(job,evidence); return Query { status:f.status,receipt:f.receipt }; }
    job.proof_active=true; job.proof_scope=scope.handle; job.proof_handle=evidence.handle;
    return Query { proof:Proof { left:left,right:right,strict:strict,actual_strict:queue[found].state%2==1,
        count:length as u32,first:first,second:second,scope:if job.inner { 2 } else { 1 },handle:evidence.handle } };
}
fn drop_proof(job: Job&) -> Check {
    if job.graph.failed || !job.proof_active { return fail(job,4,work::Receipt {}); }
    let r=proof_scopes::close(job.graph,job.proof_scope); if r.status!=0 { return failed_scope(job,r); }
    job.proof_active=false; return Check {};
}
fn close_inner(job: Job&) -> Check {
    if job.graph.failed || !job.inner || job.proof_active { return fail(job,4,work::Receipt {}); }
    let r=proof_scopes::close(job.graph,job.inner_scope); if r.status!=0 { return failed_scope(job,r); }
    job.inner=false; job.edges[1]=Edge {}; return Check {};
}
fn finish(job: Job&) -> Check {
    if job.graph.failed || !job.active || job.proof_active { return fail(job,4,work::Receipt {}); }
    if job.inner { let r=close_inner(job); if r.status!=0 { return r; } }
    let outer=proof_scopes::close(job.graph,job.outer); if outer.status!=0 { return failed_scope(job,outer); }
    let root=proof_scopes::close(job.graph,job.root); if root.status!=0 { return failed_scope(job,root); }
    job.active=false; return Check {};
}
