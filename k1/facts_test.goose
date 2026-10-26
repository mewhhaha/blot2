import std;
import work;
import facts_source;
import facts_source_check;
import facts_engine;
import facts_validate;
fn scenario(s: u8[:], job: facts_engine::Job&) -> facts_engine::Check {
    var r=facts_engine::begin(s,job,true); if r.status!=0 { return r; }
    r=facts_engine::enter_inner(job,true); if r.status!=0 { return r; }
    let q=facts_engine::query(job,facts_engine::term(1),facts_engine::term(3),true);
    if q.status!=0 { return facts_engine::Check { status:q.status,receipt:q.receipt }; }
    r=facts_validate::verify(s,job,q.proof,facts_engine::term(1),facts_engine::term(3),true); if r.status!=0 { return r; }
    r=facts_engine::drop_proof(job); if r.status!=0 { return r; }
    r=facts_engine::close_inner(job); if r.status!=0 { return r; }
    return facts_engine::finish(job);
}
fn main() {
    let source="let f: (U32,U32,U32)->U32 = fn (a,b,c) => do:\n  if a < b:\n    if b <= c:\n      ()\n    else:\n      ()\n    return a\n  else:\n    return c\n";
    var parsed,status=facts_source::parse(source); var meter=work::Meter {};
    assert(status==0 && facts_source_check::verify(source,parsed,meter,4).status==0);
    var job=facts_engine::Job {};
    assert(facts_engine::begin(source,job,true).status==0);
    assert(facts_engine::enter_inner(job,true).status==0);
    let q=facts_engine::query(job,facts_engine::term(1),facts_engine::term(3),true);
    assert(q.status==0 && q.proof.count==2 && q.proof.actual_strict);
    assert(facts_validate::verify(source,job,q.proof,facts_engine::term(1),facts_engine::term(3),true).status==0);
    let before=job.graph.meter.semantic;
    assert(facts_validate::verify(source,job,q.proof,facts_engine::term(1),facts_engine::term(3),true).status==0);
    let used=job.graph.meter.semantic-before;
    assert(facts_validate::verify(source,job,q.proof,facts_engine::term(1),facts_engine::term(3),true).status==0);
    assert(job.graph.meter.semantic-before==2*used);
    assert(facts_engine::drop_proof(job).status==0 && facts_engine::close_inner(job).status==0);
    // Both inner branches flow to the checked source's join; discard their
    // non-common guard facts while preserving the outer branch's guard.
    assert(facts_engine::query(job,facts_engine::term(1),facts_engine::term(3),true).status==5);
    let outer=facts_engine::query(job,facts_engine::term(1),facts_engine::term(2),true);
    assert(outer.status==0 && outer.proof.count==1 && facts_validate::verify(source,job,outer.proof,facts_engine::term(1),facts_engine::term(2),true).status==0);
    assert(facts_engine::drop_proof(job).status==0 && facts_engine::finish(job).status==0);
    assert(job.graph.meter.proof_edges==0 && job.graph.meter.proof_terms==3);
    var false_outer=facts_engine::Job {};
    assert(facts_engine::begin(source,false_outer,false).status==0);
    let reversed=facts_engine::query(false_outer,facts_engine::term(2),facts_engine::term(1),false);
    assert(reversed.status==0 && !reversed.proof.actual_strict);
    assert(facts_validate::verify(source,false_outer,reversed.proof,facts_engine::term(2),facts_engine::term(1),false).status==0);
    assert(facts_engine::drop_proof(false_outer).status==0);
    assert(facts_engine::query(false_outer,facts_engine::term(2),facts_engine::term(1),true).status==5);
    assert(facts_engine::finish(false_outer).status==0);
    var false_inner=facts_engine::Job {};
    assert(facts_engine::begin(source,false_inner,true).status==0 && facts_engine::enter_inner(false_inner,false).status==0);
    let complement=facts_engine::query(false_inner,facts_engine::term(3),facts_engine::term(2),true);
    assert(complement.status==0 && facts_validate::verify(source,false_inner,complement.proof,facts_engine::term(3),facts_engine::term(2),true).status==0);
    assert(facts_engine::drop_proof(false_inner).status==0 && facts_engine::close_inner(false_inner).status==0);
    assert(facts_engine::query(false_inner,facts_engine::term(3),facts_engine::term(2),true).status==5);
    assert(facts_engine::finish(false_inner).status==0);
    var reflexive=facts_engine::Job {}; assert(facts_engine::begin(source,reflexive,true).status==0);
    let equal=facts_engine::query(reflexive,facts_engine::term(2),facts_engine::term(2),false);
    assert(equal.status==0 && equal.proof.count==0 && facts_validate::verify(source,reflexive,equal.proof,facts_engine::term(2),facts_engine::term(2),false).status==0);
    assert(facts_engine::drop_proof(reflexive).status==0);
    assert(facts_engine::query(reflexive,facts_engine::term(2),facts_engine::term(2),true).status==5);
    assert(facts_engine::finish(reflexive).status==0);
    for which in 7 {
        var forged_job=facts_engine::Job {}; assert(facts_engine::begin(source,forged_job,true).status==0 && facts_engine::enter_inner(forged_job,true).status==0);
        let proof=facts_engine::query(forged_job,facts_engine::term(1),facts_engine::term(3),true); assert(proof.status==0);
        var altered=proof.proof;
        if which==0 { altered.left.version+=1; } else if which==1 { altered.right.owner+=1; }
        else if which==2 { altered.first=2; } else if which==3 { altered.second=1; }
        else if which==4 { altered.actual_strict=false; } else if which==5 { altered.scope=1; }
        else { altered.handle.generation+=1; }
        assert(facts_validate::verify(source,forged_job,altered,facts_engine::term(1),facts_engine::term(3),true).status==1 && forged_job.graph.failed);
        let spent=forged_job.graph.meter.semantic;
        assert(facts_engine::query(forged_job,facts_engine::term(1),facts_engine::term(2),true).status==4 && forged_job.graph.meter.semantic==spent);
    }
    // A forged proof-scope parent is read only after its own link charge.
    for available in 2 {
        var limited=facts_engine::Job {};
        assert(facts_engine::begin(source,limited,true).status==0 && facts_engine::enter_inner(limited,true).status==0);
        let candidate=facts_engine::query(limited,facts_engine::term(1),facts_engine::term(3),true); assert(candidate.status==0);
        limited.graph.entries[limited.proof_scope.index-1].scope.parent=limited.root;
        limited.graph.meter.proof_visits=if available==0 { 65510 } else { 65509 };
        let result=facts_validate::verify(source,limited,candidate.proof,facts_engine::term(1),facts_engine::term(3),true);
        assert(result.status==(if available==0 { 2 } else { 1 }));
        assert(limited.graph.meter.proof_visits==65536 && limited.graph.failed);
    }
    // The path ID itself is not inspected until its charged edge visit.
    for available in 2 {
        var limited=facts_engine::Job {};
        assert(facts_engine::begin(source,limited,true).status==0 && facts_engine::enter_inner(limited,true).status==0);
        let candidate=facts_engine::query(limited,facts_engine::term(1),facts_engine::term(3),true); assert(candidate.status==0);
        var bad=copy(candidate.proof); bad.first=99;
        limited.graph.meter.proof_visits=if available==0 { 65508 } else { 65507 };
        let result=facts_validate::verify(source,limited,bad,facts_engine::term(1),facts_engine::term(3),true);
        assert(result.status==(if available==0 { 2 } else { 1 }));
        assert(limited.graph.meter.proof_visits==65536 && limited.graph.failed);
    }
    var rebound=facts_engine::Job {}; assert(facts_engine::begin(source,rebound,true).status==0);
    let stale=facts_engine::Term { owner:1,id:1,version:2 };
    assert(facts_engine::query(rebound,stale,facts_engine::term(2),true).status==1 && rebound.graph.failed);
    var expired=facts_engine::Job {}; assert(facts_engine::begin(source,expired,true).status==0);
    let old=facts_engine::query(expired,facts_engine::term(1),facts_engine::term(2),true);
    assert(old.status==0 && facts_engine::drop_proof(expired).status==0);
    let prior_count=expired.graph.meter.semantic;
    assert(facts_validate::verify(source,expired,old.proof,facts_engine::term(1),facts_engine::term(2),true).status==4);
    assert(expired.graph.failed && expired.graph.meter.semantic==prior_count);
    var changed=facts_engine::Job {}; assert(facts_engine::begin(source,changed,true).status==0);
    let current=facts_engine::query(changed,facts_engine::term(1),facts_engine::term(2),true); assert(current.status==0);
    let other_source="let f: (U32,U32,U32)->U32 = fn (a,b,c) => do:\n  if a <= b:\n    if b <= c:\n      ()\n    else:\n      ()\n    return a\n  else:\n    return c\n";
    assert(facts_validate::verify(other_source,changed,current.proof,facts_engine::term(1),facts_engine::term(2),true).status==1 && changed.graph.failed);
    var rebound_source=facts_engine::Job {};
    let unsupported="let f: (U32,U32,U32)->U32 = fn (a,b,c) => do:\n  let a = b\n  if a < b:\n    if b <= c:\n      ()\n    else:\n      ()\n    return a\n  else:\n    return c\n";
    assert(facts_engine::begin(unsupported,rebound_source,true).status==1 && rebound_source.graph.failed);
    var contradiction=facts_engine::Job {};
    let unreachable="let f: (U32,U32,U32)->U32 = fn (a,b,c) => do:\n  if a < b:\n    if b <= a:\n      ()\n    else:\n      ()\n    return a\n  else:\n    return c\n";
    assert(facts_engine::begin(unreachable,contradiction,true).status==0);
    assert(facts_engine::enter_inner(contradiction,true).status==6 && !contradiction.inner);
    assert(facts_engine::finish(contradiction).status==0);
    var complete=facts_engine::Job {}; assert(scenario(source,complete).status==0);
    let events=complete.graph.meter.semantic; let proofs=complete.graph.meter.proof_visits;
    assert(events<1000 && proofs<1000);
    var exact=facts_engine::Job {}; exact.graph.meter.semantic=1048576-events;
    assert(scenario(source,exact).status==0 && exact.graph.meter.semantic==1048576);
    for i in 0..events {
        var limit=facts_engine::Job {}; limit.graph.meter.semantic=1048577-events+i;
        let failure=scenario(source,limit); assert(failure.status==3 && failure.receipt.quantity==1 && limit.graph.failed);
    }
    var proof_exact=facts_engine::Job {}; proof_exact.graph.meter.proof_visits=65536-proofs;
    assert(scenario(source,proof_exact).status==0 && proof_exact.graph.meter.proof_visits==65536);
    for i in 0..proofs {
        var limit=facts_engine::Job {}; limit.graph.meter.proof_visits=65537-proofs+i;
        let failure=scenario(source,limit); assert(failure.status==2 && failure.receipt.quantity==2 && limit.graph.failed);
    }
    var terms=facts_engine::Job {}; terms.graph.meter.proof_terms=4094;
    let term_fail=scenario(source,terms); assert(term_fail.status==2 && term_fail.receipt.quantity==3 && terms.graph.failed);
    var edges=facts_engine::Job {}; edges.graph.meter.proof_edges=16380;
    let edge_fail=scenario(source,edges); assert(edge_fail.status==2 && edge_fail.receipt.quantity==4 && edges.graph.failed);
    var simultaneous=facts_engine::Job {}; assert(facts_engine::begin(source,simultaneous,true).status==0);
    simultaneous.graph.meter.semantic=1048576; simultaneous.graph.meter.proof_visits=65536;
    let priority=facts_engine::enter_inner(simultaneous,true); assert(priority.status==3 && priority.receipt.quantity==1 && simultaneous.graph.failed);
    print("source-bound scoped finite fact paths passed");
}
