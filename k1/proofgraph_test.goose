import std;
import work;
import proofgraph_source;
import proofgraph_source_check;
import proofgraph_engine;
import proofgraph_validate;
fn scenario(source:u8[:],j:proofgraph_engine::Job&) -> proofgraph_engine::Result {
    var r=proofgraph_engine::begin(source,j); if r.status!=0 { return r; }
    let q=proofgraph_engine::query(j,proofgraph_engine::term(1),proofgraph_engine::term(2),true);
    if q.status!=0 { return proofgraph_engine::Result {status:q.status,receipt:q.receipt}; }
    r=proofgraph_validate::verify(source,j,q.proof,proofgraph_engine::term(1),proofgraph_engine::term(2),true); if r.status!=0 { return r; }
    r=proofgraph_engine::drop(j); if r.status!=0 { return r; }
    return proofgraph_engine::finish(j);
}
fn main() {
    let source="pub let f: (U32,U32,U32,U32,U32)->U32 ! {} requires [Eq(arg.0,arg.1), Lt(arg.1,arg.2), Le(arg.2,arg.3), Eq(arg.3,arg.4)] resources {depth:1,frame:0} = fn (a,b,c,d,e) => return a\n";
    var p,ps=proofgraph_source::parse(source); var m=work::Meter {};
    assert(ps==0 && p.count==5 && p.facts_count==4 && proofgraph_source_check::verify(source,p,m,4).status==0);
    for which in 6 {
        var bad=copy(p);
        if which==0 { bad.count=4; } else if which==1 { bad.facts_count=3; }
        else if which==2 { bad.facts[0].kind=2; } else if which==3 { bad.facts[1].left=3; }
        else if which==4 { bad.facts[2].start+=1; } else { bad.names[1].start=-1; }
        var fresh=work::Meter {}; assert(proofgraph_source_check::verify(source,bad,fresh,4).status==1);
    }
    var job=proofgraph_engine::Job {}; assert(proofgraph_engine::begin(source,job).status==0);
    assert(job.count==5 && job.edge_count==6 && job.meter.proof_terms==5 && job.meter.proof_edges==6);
    let class_a=proofgraph_engine::root(job,2); assert(class_a.status==0 && class_a.id==1);
    assert(proofgraph_validate::verify_class(source,job,proofgraph_engine::term(2),1).status==0);
    let class_d=proofgraph_engine::root(job,5); assert(class_d.status==0 && class_d.id==4);
    assert(proofgraph_validate::verify_class(source,job,proofgraph_engine::term(5),4).status==0);
    let q=proofgraph_engine::query(job,proofgraph_engine::term(1),proofgraph_engine::term(5),true);
    assert(q.status==0 && q.proof.count==4 && q.proof.actual);
    assert(proofgraph_validate::verify(source,job,q.proof,proofgraph_engine::term(1),proofgraph_engine::term(5),true).status==0);
    let before=job.meter.proof_visits;
    assert(proofgraph_validate::verify(source,job,q.proof,proofgraph_engine::term(1),proofgraph_engine::term(5),true).status==0);
    let delta=job.meter.proof_visits-before;
    assert(proofgraph_validate::verify(source,job,q.proof,proofgraph_engine::term(1),proofgraph_engine::term(5),true).status==0 && job.meter.proof_visits-before==delta*2);
    assert(proofgraph_engine::drop(job).status==0 && job.meter.proof_edges==6);
    assert(proofgraph_engine::query(job,proofgraph_engine::term(5),proofgraph_engine::term(1),false).status==5);
    assert(proofgraph_engine::finish(job).status==0 && job.meter.proof_edges==0);
    for which in 8 {
        var bad_job=proofgraph_engine::Job {}; assert(proofgraph_engine::begin(source,bad_job).status==0);
        let issued=proofgraph_engine::query(bad_job,proofgraph_engine::term(1),proofgraph_engine::term(5),true); assert(issued.status==0);
        var bad=copy(issued.proof);
        if which==0 { bad.left.version+=1; } else if which==1 { bad.right.owner+=1; }
        else if which==2 { bad.edges[0]=99; } else if which==3 { bad.edges[1]=bad.edges[0]; }
        else if which==4 { bad.actual=false; } else if which==5 { bad.generation+=1; }
        else if which==6 { bad.count=17; } else { bad.edges[15]=1; }
        assert(proofgraph_validate::verify(source,bad_job,bad,proofgraph_engine::term(1),proofgraph_engine::term(5),true).status==1 && bad_job.failed);
        let spent=bad_job.meter.semantic;
        assert(proofgraph_engine::query(bad_job,proofgraph_engine::term(1),proofgraph_engine::term(2),false).status==4 && bad_job.meter.semantic==spent);
    }
    var old=proofgraph_engine::Job {}; assert(proofgraph_engine::begin(source,old).status==0);
    let stale=proofgraph_engine::query(old,proofgraph_engine::term(1),proofgraph_engine::term(2),false); assert(stale.status==0);
    assert(proofgraph_engine::drop(old).status==0);
    let new_proof=proofgraph_engine::query(old,proofgraph_engine::term(1),proofgraph_engine::term(2),false); assert(new_proof.status==0);
    assert(proofgraph_validate::verify(source,old,stale.proof,proofgraph_engine::term(1),proofgraph_engine::term(2),false).status==1 && old.failed);
    var wrong_source=proofgraph_engine::Job {}; assert(proofgraph_engine::begin(source,wrong_source).status==0);
    let sq=proofgraph_engine::query(wrong_source,proofgraph_engine::term(1),proofgraph_engine::term(2),false); assert(sq.status==0);
    assert(proofgraph_validate::verify("different",wrong_source,sq.proof,proofgraph_engine::term(1),proofgraph_engine::term(2),false).status==1 && wrong_source.failed);
    var changed_class=proofgraph_engine::Job {}; assert(proofgraph_engine::begin(source,changed_class).status==0);
    changed_class.parents[1]=2;
    assert(proofgraph_validate::verify_class(source,changed_class,proofgraph_engine::term(2),2).status==1 && changed_class.failed);
    let chain="pub let f: (U32,U32,U32,U32,U32,U32,U32,U32)->U32 ! {} requires [Eq(arg.0,arg.1),Eq(arg.1,arg.2),Eq(arg.2,arg.3),Eq(arg.3,arg.4),Le(arg.4,arg.5),Le(arg.5,arg.6),Lt(arg.6,arg.7)] resources {depth:1,frame:0} = fn (a,b,c,d,e,g,h,i) => return a";
    var deep=proofgraph_engine::Job {}; assert(proofgraph_engine::begin(chain,deep).status==0 && deep.count==8);
    assert(proofgraph_engine::root(deep,5).id==1 && proofgraph_validate::verify_class(chain,deep,proofgraph_engine::term(5),1).status==0);
    let long_path=proofgraph_engine::query(deep,proofgraph_engine::term(1),proofgraph_engine::term(8),true);
    assert(long_path.status==0 && long_path.proof.count==7 && proofgraph_validate::verify(chain,deep,long_path.proof,proofgraph_engine::term(1),proofgraph_engine::term(8),true).status==0);
    assert(proofgraph_engine::drop(deep).status==0 && proofgraph_engine::finish(deep).status==0);
    let nonstrict_cycle="pub let f: (U32,U32)->U32 ! {} requires [Le(arg.0,arg.1),Le(arg.1,arg.0)] resources {depth:1,frame:0} = fn (a,b) => return a";
    var cyclic=proofgraph_engine::Job {}; assert(proofgraph_engine::begin(nonstrict_cycle,cyclic).status==0);
    assert(proofgraph_engine::root(cyclic,2).id==2); // only explicit Eq is interned as a class
    let reverse=proofgraph_engine::query(cyclic,proofgraph_engine::term(2),proofgraph_engine::term(1),false);
    assert(reverse.status==0 && proofgraph_validate::verify(nonstrict_cycle,cyclic,reverse.proof,proofgraph_engine::term(2),proofgraph_engine::term(1),false).status==0);
    assert(proofgraph_engine::drop(cyclic).status==0 && proofgraph_engine::finish(cyclic).status==0);
    let empty="pub let f: (U32,U32)->U32 ! {} requires [] resources {depth:1,frame:0} = fn (a,b) => return a";
    var bare=proofgraph_engine::Job {}; assert(proofgraph_engine::begin(empty,bare).status==0);
    let identity=proofgraph_engine::query(bare,proofgraph_engine::term(1),proofgraph_engine::term(1),false);
    assert(identity.status==0 && identity.proof.count==0 && proofgraph_validate::verify(empty,bare,identity.proof,proofgraph_engine::term(1),proofgraph_engine::term(1),false).status==0);
    assert(proofgraph_engine::drop(bare).status==0 && proofgraph_engine::query(bare,proofgraph_engine::term(1),proofgraph_engine::term(2),false).status==5);
    assert(proofgraph_engine::finish(bare).status==0);
    var maximum:u8[>..]=[];
    maximum.append("pub let fn_main: (U32,U32,U32,U32,U32,U32,U32,U32)->U32 ! {} requires [");
    for i in 16 { if i>0 { maximum.append(","); } maximum.append("Eq(arg.0,arg.1)"); }
    maximum.append("] resources {depth:1,frame:0} = fn (a,b,c,d,e,f,g,h) => return a");
    var max_job=proofgraph_engine::Job {};
    assert(proofgraph_engine::begin(maximum,max_job).status==0 && max_job.count==8 && max_job.edge_count==32);
    let max_q=proofgraph_engine::query(max_job,proofgraph_engine::term(1),proofgraph_engine::term(2),false);
    assert(max_q.status==0 && proofgraph_validate::verify(maximum,max_job,max_q.proof,proofgraph_engine::term(1),proofgraph_engine::term(2),false).status==0);
    assert(proofgraph_engine::drop(max_job).status==0 && proofgraph_engine::finish(max_job).status==0 && max_job.meter.proof_edges==0);
    for contradiction in [
      "pub let f: (U32,U32)->U32 ! {} requires [Lt(arg.0,arg.0)] resources {depth:1,frame:0} = fn (a,b) => return a",
      "pub let f: (U32,U32)->U32 ! {} requires [Le(arg.0,arg.1),Lt(arg.1,arg.0)] resources {depth:1,frame:0} = fn (a,b) => return a",
      "pub let f: (U32,U32,U32)->U32 ! {} requires [Eq(arg.0,arg.1),Le(arg.1,arg.2),Lt(arg.2,arg.0)] resources {depth:1,frame:0} = fn (a,b,c) => return a"
    ] { var impossible=proofgraph_engine::Job {}; assert(proofgraph_engine::begin(contradiction,impossible).status==6 && impossible.failed && !impossible.active); }
    for bad in [
      "pub let f: (U32,U32)->U32 ! {} requires [Lt(arg.0,arg.2)] resources {depth:1,frame:0} = fn (a,b) => return a",
      "pub let f: (U32,U32)->U32 ! {} requires [Lt(a,arg.1)] resources {depth:1,frame:0} = fn (a,b) => return a",
      "pub let f: (U32,U32)->U32 ! {} requires [] resources {depth:1,frame:0} = fn (a,a) => return a"
    ] { var rejected=proofgraph_engine::Job {}; assert(proofgraph_engine::begin(bad,rejected).status==1 && rejected.failed); }
    let small="pub let f: (U32,U32)->U32 ! {} requires [Lt(arg.0,arg.1)] resources {depth:1,frame:0} = fn (a,b) => return a";
    var full=proofgraph_engine::Job {}; assert(scenario(small,full).status==0);
    let events=full.meter.semantic; let visits=full.meter.proof_visits;
    assert(events<4000 && visits<4000);
    var exact=proofgraph_engine::Job {}; exact.meter.semantic=1048576-events;
    assert(scenario(small,exact).status==0 && exact.meter.semantic==1048576);
    for i in 0..events {
        var limited=proofgraph_engine::Job {}; limited.meter.semantic=1048577-events+i;
        let denied=scenario(small,limited); assert(denied.status==3 && denied.receipt.quantity==1 && limited.failed);
    }
    var exact_proof=proofgraph_engine::Job {}; exact_proof.meter.proof_visits=65536-visits;
    assert(scenario(small,exact_proof).status==0 && exact_proof.meter.proof_visits==65536);
    for i in 0..visits {
        var limited=proofgraph_engine::Job {}; limited.meter.proof_visits=65537-visits+i;
        let denied=scenario(small,limited); assert(denied.status==2 && denied.receipt.quantity==2 && limited.failed);
    }
    var term_limit=proofgraph_engine::Job {}; term_limit.meter.proof_terms=4095;
    let tl=proofgraph_engine::begin(small,term_limit); assert(tl.status==2 && tl.receipt.quantity==3 && term_limit.failed);
    var edge_limit=proofgraph_engine::Job {}; edge_limit.meter.proof_edges=16383;
    let el=scenario(small,edge_limit); assert(el.status==2 && el.receipt.quantity==4 && edge_limit.failed);
    var both=proofgraph_engine::Job {}; assert(proofgraph_engine::begin(small,both).status==0);
    both.meter.semantic=1048576; both.meter.proof_visits=65536;
    let priority=proofgraph_engine::query(both,proofgraph_engine::term(1),proofgraph_engine::term(2),true);
    assert(priority.status==3 && priority.receipt.quantity==1 && both.failed);
    print("source-checked finite proof graph and explicit equality classes passed");
}
