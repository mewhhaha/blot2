// Independent source-backed finite path and explicit Eq class validator.
// Reconstructs requirements, edges, consistency and class roots; it does not
// trust the producer's graph, a success flag, counters, or a source digest.
// This bounded private fixture is not the full K1 proof/artifact validator.
namespace proofgraph_validate;
import work;
import proofgraph_source;
import proofgraph_source_check;
import proofgraph_engine;
fn fail(r:work::Receipt)->proofgraph_engine::Result { return proofgraph_engine::Result {status:proofgraph_engine::code(r),receipt:r}; }
fn edge_same(a:proofgraph_engine::Edge,b:proofgraph_engine::Edge)->bool { return a.left==b.left && a.right==b.right && a.strict==b.strict && a.origin==b.origin && a.reverse==b.reverse; }
fn term_valid(t:proofgraph_engine::Term,n:u32)->bool { return t.owner==1 && t.id>=1 && t.id<=n && t.version==t.id; }
fn term_same(a:proofgraph_engine::Term,b:proofgraph_engine::Term)->bool { return a.owner==b.owner && a.id==b.id && a.version==b.version; }
// Independent per-root DFS of (term, strict-seen) states. It stores only the
// current root's visited set, never a table of transitive term pairs.
fn no_strict_cycle(edges:proofgraph_engine::Edge[:],count:u32,start:u32,m:work::Meter&)->proofgraph_engine::Result {
    var stack:u32[..16]=[]; var seen:bool[16]=[false;16];
    let initial=(start-1)*2; stack.push(initial); seen[initial]=true;
    while stack.len>0 {
        let node=work::charge(m,4,20); if node.status!=0 { return fail(node); }
        let state=stack.pop(); let from=state/2+1;
        for dest in 1..(count+1) {
            for k in edges.len {
                let visit=work::charge(m,4,20); if visit.status!=0 { return fail(visit); }
                let e=edges[k]; if e.left!=from || e.right!=dest { continue; }
                let strong=state%2==1 || e.strict;
                if e.right==start && strong { return proofgraph_engine::Result {status:1}; }
                let next=(e.right-1)*2+(if strong {1} else {0});
                let probe=work::charge(m,4,20); if probe.status!=0 { return fail(probe); }
                if !seen[next] {
                    if stack.len>=16 { return proofgraph_engine::Result {status:4}; }
                    seen[next]=true; stack.push(next);
                }
            }
        }
    }
    return proofgraph_engine::Result {};
}
// Traverse only explicit Eq edges, independently of the producer's union
// structure; the representative is the smallest reachable formal ID.
fn eq_min(edges:proofgraph_engine::Edge[:],count:u32,start:u32,m:work::Meter&)->proofgraph_engine::Root {
    var queue:u32[..8]=[]; var seen:bool[8]=[false;8]; var head:i64=0;
    queue.push(start); seen[start-1]=true; var smallest=start;
    while head<queue.len {
        let node=work::charge(m,4,20); if node.status!=0 { return proofgraph_engine::Root {status:proofgraph_engine::code(node),receipt:node}; }
        let from=queue[head]; head+=1;
        for dest in 1..(count+1) {
            for k in edges.len {
                let visit=work::charge(m,4,20); if visit.status!=0 { return proofgraph_engine::Root {status:proofgraph_engine::code(visit),receipt:visit}; }
                let e=edges[k];
                if !e.reverse || !((e.left==from && e.right==dest) || (e.right==from && e.left==dest)) { continue; }
                let probe=work::charge(m,4,20); if probe.status!=0 { return proofgraph_engine::Root {status:proofgraph_engine::code(probe),receipt:probe}; }
                if !seen[dest-1] {
                    if queue.len>=8 { return proofgraph_engine::Root {status:4}; }
                    seen[dest-1]=true; queue.push(dest); if dest<smallest { smallest=dest; }
                }
            }
        }
    }
    return proofgraph_engine::Root {id:smallest};
}
// Perform this complete source/graph recheck on every evidence validation.
fn base(source:u8[:],j:proofgraph_engine::Job&)->proofgraph_engine::Result {
    if j.failed || !j.active { return proofgraph_engine::Result {status:4}; }
    if j.source_len<0 || j.source_len>4096 || source.len!=j.source_len || j.source[..j.source_len]!=source { return proofgraph_engine::Result {status:1}; }
    var p,ps=proofgraph_source::parse(source); if ps!=0 { return proofgraph_engine::Result {status:1}; }
    let src=proofgraph_source_check::verify(source,p,j.meter,4); if src.status!=0 { return proofgraph_engine::Result {status:src.status,receipt:src.receipt}; }
    if j.count!=p.count || j.count<2 || j.count>8 || j.edge_count>32 { return proofgraph_engine::Result {status:1}; }
    for i in j.count {
        let r=work::charge(j.meter,4,20); if r.status!=0 { return fail(r); }
        if j.terms[i].owner!=1 || j.terms[i].id!=i+1 || j.terms[i].version!=i+1 { return proofgraph_engine::Result {status:1}; }
    }
    var expected:proofgraph_engine::Edge[32]=[proofgraph_engine::Edge {};32]; var ne:u32=0;
    // Eq supplies both <= directions; facts retain source occurrence IDs.
    for i in p.facts_count {
        let r=work::charge(j.meter,4,20); if r.status!=0 { return fail(r); }
        let f=p.facts[i]; if f.left==0 || f.left>p.count || f.right==0 || f.right>p.count || f.kind<1 || f.kind>3 { return proofgraph_engine::Result {status:1}; }
        if ne>=32 { return proofgraph_engine::Result {status:1}; }
        expected[ne]=proofgraph_engine::Edge {left:f.left,right:f.right,strict:f.kind==2,origin:i+1}; ne+=1;
        if f.kind==3 {
            if ne>=32 { return proofgraph_engine::Result {status:1}; }
            expected[ne]=proofgraph_engine::Edge {left:f.right,right:f.left,origin:i+1,reverse:true}; ne+=1;
        }
    }
    if j.edge_count!=ne { return proofgraph_engine::Result {status:1}; }
    for i in ne {
        let r=work::charge(j.meter,4,20); if r.status!=0 { return fail(r); }
        if !edge_same(j.edges[i],expected[i]) { return proofgraph_engine::Result {status:1}; }
    }
    // Check each possible strict cycle on demand; nothing is retained from a
    // previous root. The fixed source edge array remains the only graph.
    for i in p.count {
        let r=no_strict_cycle(expected[..ne],p.count,i+1,j.meter);
        if r.status!=0 { return r; }
    }
    // Equality class representative is the smallest explicit Eq-connected ID.
    for i in p.count {
        let smallest=eq_min(expected[..ne],p.count,i+1,j.meter);
        if smallest.status!=0 { return proofgraph_engine::Result {status:smallest.status,receipt:smallest.receipt}; }
        var cursor=i+1; var found:u32=0;
        for step in 8 {
            let r=work::charge(j.meter,4,20); if r.status!=0 { return fail(r); }
            let parent=j.parents[cursor-1]; if parent==0 || parent>cursor { return proofgraph_engine::Result {status:1}; }
            if parent==cursor { found=cursor; break; } cursor=parent;
        }
        if found!=smallest.id { return proofgraph_engine::Result {status:1}; }
    }
    return proofgraph_engine::Result {};
}
fn verify_inner(source:u8[:],j:proofgraph_engine::Job&,proof:proofgraph_engine::Proof,
                left:proofgraph_engine::Term,right:proofgraph_engine::Term,strict:bool)->proofgraph_engine::Result {
    let b=base(source,j); if b.status!=0 { return b; }
    let h=work::charge(j.meter,4,20); if h.status!=0 { return fail(h); }
    if !j.proof_active || proof.generation!=j.generation || !term_valid(left,j.count) || !term_valid(right,j.count) ||
       !term_same(proof.left,left) || !term_same(proof.right,right) || proof.strict!=strict || proof.count>16 ||
       j.proof_charge!=proof.count+1 || j.meter.proof_edges<j.edge_count+j.proof_charge { return proofgraph_engine::Result {status:1}; }
    var current=left.id; var actual=false;
    for i in proof.count {
        let link=work::charge(j.meter,4,20); if link.status!=0 { return fail(link); }
        let id=proof.edges[i]; if id==0 || id>j.edge_count { return proofgraph_engine::Result {status:1}; }
        let node=work::charge(j.meter,4,20); if node.status!=0 { return fail(node); }
        let e=j.edges[id-1]; if e.left!=current { return proofgraph_engine::Result {status:1}; }
        current=e.right; actual=actual || e.strict;
    }
    for i in proof.count..16 {
        let r=work::charge(j.meter,4,20); if r.status!=0 { return fail(r); }
        if proof.edges[i]!=0 { return proofgraph_engine::Result {status:1}; }
    }
    if current!=right.id || actual!=proof.actual || (strict && !actual) || (proof.count==0 && (strict || left.id!=right.id)) { return proofgraph_engine::Result {status:1}; }
    return proofgraph_engine::Result {};
}
fn verify(source:u8[:],j:proofgraph_engine::Job&,proof:proofgraph_engine::Proof,
          left:proofgraph_engine::Term,right:proofgraph_engine::Term,strict:bool)->proofgraph_engine::Result {
    let r=verify_inner(source,j,proof,left,right,strict); if r.status!=0 { j.failed=true; } return r;
}
// Validate a compiler-proposed equality representative independently. Eq
// classes use exact U32 formal identities, not an exported type-level cast.
fn verify_class(source:u8[:],j:proofgraph_engine::Job&,value:proofgraph_engine::Term,representative:u32)->proofgraph_engine::Result {
    let b=base(source,j); if b.status!=0 { j.failed=true; return b; }
    if !term_valid(value,j.count) || representative==0 || representative>j.count { j.failed=true; return proofgraph_engine::Result {status:1}; }
    var current=value.id;
    for i in 8 {
        let r=work::charge(j.meter,4,20); if r.status!=0 { j.failed=true; return fail(r); }
        let parent=j.parents[current-1]; if parent==0 || parent>current { j.failed=true; return proofgraph_engine::Result {status:1}; }
        if parent==current { if current!=representative { j.failed=true; return proofgraph_engine::Result {status:1}; } return proofgraph_engine::Result {}; }
        current=parent;
    }
    j.failed=true; return proofgraph_engine::Result {status:1};
}
