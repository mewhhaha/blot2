// Independently replay source-anchored proof paths. Job-local handles are
// bookkeeping only, never a cross-job identity or serialized authorization.
// This private checker is not the full K1 evidence validator or join algebra.
namespace facts_validate;
import work;
import proof_scopes;
import facts_source;
import facts_source_check;
import facts_engine;
fn fail(r: work::Receipt) -> facts_engine::Check { return facts_engine::Check { status: facts_engine::code(r), receipt: r }; }
fn same_edge(a: facts_engine::Edge,b: facts_engine::Edge) -> bool {
    return a.left==b.left && a.right==b.right && a.strict==b.strict && a.origin==b.origin && a.truth==b.truth && a.scope==b.scope;
}
fn valid_term(t: facts_engine::Term) -> bool { return t.owner==1 && t.id>=1 && t.id<=3 && t.version==t.id; }
fn same_term(a: facts_engine::Term,b: facts_engine::Term) -> bool { return a.owner==b.owner && a.id==b.id && a.version==b.version; }
fn verify_inner(source: u8[:], job: facts_engine::Job&, proof: facts_engine::Proof,
                left: facts_engine::Term,right: facts_engine::Term,strict: bool) -> facts_engine::Check {
    if job.graph.failed || !job.active || !job.proof_active || (job.inner && !job.outer_truth) { return facts_engine::Check { status:4 }; }
    if job.source_len < 0 || job.source_len > 4096 || source.len != job.source_len ||
       job.source[..job.source_len] != source { return facts_engine::Check { status:1 }; }
    var candidate, parse_status=facts_source::parse(source);
    if parse_status!=0 { return facts_engine::Check { status:1 }; }
    let source_check=facts_source_check::verify(source,candidate,job.graph.meter,4);
    if source_check.status!=0 { return facts_engine::Check { status:source_check.status,receipt:source_check.receipt }; }
    for i in (if job.inner { 3 } else { 2 }) {
        let r=work::charge(job.graph.meter,4,20); if r.status!=0 { return fail(r); }
        let h=if i==0 { job.root } else if i==1 { job.outer } else { job.inner_scope };
        if !proof_scopes::scope_valid(job.graph,h) { return facts_engine::Check { status:1 }; }
        let r2=work::charge(job.graph.meter,4,20); if r2.status!=0 { return fail(r2); }
        if i==0 {
            if job.graph.entries[h.index-1].scope.has_parent { return facts_engine::Check { status:1 }; }
        } else {
            if !job.graph.entries[h.index-1].scope.has_parent { return facts_engine::Check { status:1 }; }
            let link=work::charge(job.graph.meter,4,20); if link.status!=0 { return fail(link); }
            if !proof_scopes::same(job.graph.entries[h.index-1].scope.parent,if i==1 { job.root } else { job.outer }) { return facts_engine::Check { status:1 }; }
        }
    }
    for i in 3 {
        let r=work::charge(job.graph.meter,4,20); if r.status!=0 { return fail(r); }
        if job.terms[i].owner!=1 || job.terms[i].id!=i+1 || job.terms[i].version!=i+1 { return facts_engine::Check { status:1 }; }
    }
    let n=if job.inner { 2 } else { 1 };
    for i in n {
        let r=work::charge(job.graph.meter,4,20); if r.status!=0 { return fail(r); }
        // Independently reconstruct the true/false edge rather than trusting
        // the producer's normalization helper or its stored edge fields.
        let g=candidate.guards[i]; let taken=if i==0 { job.outer_truth } else { job.inner_truth };
        let expected=if taken { facts_engine::Edge { left:g.left,right:g.right,strict:g.strict,origin:(i+1) as u32,truth:true,scope:(i+1) as u32 } }
            else { facts_engine::Edge { left:g.right,right:g.left,strict:!g.strict,origin:(i+1) as u32,truth:false,scope:(i+1) as u32 } };
        if job.guards[i].left!=candidate.guards[i].left || job.guards[i].right!=candidate.guards[i].right ||
           job.guards[i].strict!=candidate.guards[i].strict { return facts_engine::Check { status:1 }; }
        let edge_record=work::charge(job.graph.meter,4,20); if edge_record.status!=0 { return fail(edge_record); }
        if !same_edge(job.edges[i],expected) { return facts_engine::Check { status:1 }; }
        let fact_record=work::charge(job.graph.meter,4,20); if fact_record.status!=0 { return fail(fact_record); }
        if !proof_scopes::fact_valid(job.graph,job.edges[i].handle) { return facts_engine::Check { status:1 }; }
        let r2=work::charge(job.graph.meter,4,20); if r2.status!=0 { return fail(r2); }
        let scope=job.graph.entries[job.edges[i].handle.index-1].fact.scope;
        if !proof_scopes::same(scope,if i==0 { job.outer } else { job.inner_scope }) { return facts_engine::Check { status:1 }; }
    }
    if job.inner {
        let a_read=work::charge(job.graph.meter,4,20); if a_read.status!=0 { return fail(a_read); }
        let a=job.edges[0];
        let b_read=work::charge(job.graph.meter,4,20); if b_read.status!=0 { return fail(b_read); }
        let b=job.edges[1];
        if a.left==b.right && a.right==b.left && (a.strict || b.strict) { return facts_engine::Check { status:1 }; }
    }
    let header=work::charge(job.graph.meter,4,20); if header.status!=0 { return fail(header); }
    if !valid_term(left) || !valid_term(right) || !same_term(proof.left,left) ||
       !same_term(proof.right,right) || proof.strict!=strict || proof.count>2 ||
       proof.scope!=(if job.inner { 2 } else { 1 }) || !proof_scopes::same(proof.handle,job.proof_handle) { return facts_engine::Check { status:1 }; }
    let proof_record=work::charge(job.graph.meter,4,20); if proof_record.status!=0 { return fail(proof_record); }
    if !proof_scopes::fact_valid(job.graph,proof.handle) { return facts_engine::Check { status:1 }; }
    let proof_scope_record=work::charge(job.graph.meter,4,20); if proof_scope_record.status!=0 { return fail(proof_scope_record); }
    if !proof_scopes::scope_valid(job.graph,job.proof_scope) { return facts_engine::Check { status:1 }; }
    let scope_read=work::charge(job.graph.meter,4,20); if scope_read.status!=0 { return fail(scope_read); }
    if !proof_scopes::same(job.graph.entries[proof.handle.index-1].fact.scope,job.proof_scope) { return facts_engine::Check { status:1 }; }
    let parent_read=work::charge(job.graph.meter,4,20); if parent_read.status!=0 { return fail(parent_read); }
    if !job.graph.entries[job.proof_scope.index-1].scope.has_parent { return facts_engine::Check { status:1 }; }
    let parent_edge=work::charge(job.graph.meter,4,20); if parent_edge.status!=0 { return fail(parent_edge); }
    if !proof_scopes::same(job.graph.entries[job.proof_scope.index-1].scope.parent,if job.inner { job.inner_scope } else { job.outer }) { return facts_engine::Check { status:1 }; }
    let expected_links=if proof.count==0 { 0 } else if proof.count==1 { 1 } else { 3 };
    let flags=work::charge(job.graph.meter,4,20); if flags.status!=0 { return fail(flags); }
    if job.graph.entries[proof.handle.index-1].fact.links!=expected_links { return facts_engine::Check { status:1 }; }
    var current=left.id; var saw_strict=false;
    for i in proof.count {
        // Charge the path edge before inspecting the ID or linked record.
        let visit=work::charge(job.graph.meter,4,20); if visit.status!=0 { return fail(visit); }
        let id=if i==0 { proof.first } else { proof.second };
        if id==0 || id>n { return facts_engine::Check { status:1 }; }
        let edge_record=work::charge(job.graph.meter,4,20); if edge_record.status!=0 { return fail(edge_record); }
        let edge=job.edges[id-1]; if edge.left!=current { return facts_engine::Check { status:1 }; }
        current=edge.right; saw_strict=saw_strict || edge.strict;
        let link=work::charge(job.graph.meter,4,20); if link.status!=0 { return fail(link); }
        let prior=if i==0 { job.graph.entries[proof.handle.index-1].fact.first } else { job.graph.entries[proof.handle.index-1].fact.second };
        if !proof_scopes::same(prior,edge.handle) { return facts_engine::Check { status:1 }; }
    }
    if (proof.count==0 && (proof.first!=0 || proof.second!=0 || left.id!=right.id)) ||
       (proof.count==1 && proof.second!=0) || current!=right.id || saw_strict!=proof.actual_strict ||
       (strict && !saw_strict) { return facts_engine::Check { status:1 }; }
    return facts_engine::Check {};
}
// Invalid evidence or budget failure is terminal for this declaration owner.
fn verify(source: u8[:], job: facts_engine::Job&, proof: facts_engine::Proof,
          left: facts_engine::Term,right: facts_engine::Term,strict: bool) -> facts_engine::Check {
    let checked=verify_inner(source,job,proof,left,right,strict);
    if checked.status!=0 { job.graph.failed=true; }
    return checked;
}
