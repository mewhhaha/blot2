// Independent source-linked replay of a conditional invariant schema. Input
// and output version numbers are job-local symbolic roles, not fresh runtime
// generations; the append intrinsic and validated live capabilities are still
// required before executing any code. This checker supplies no C09 receipt.
namespace i08_transition_verify;
import i08_link_core;
import i08_link_verify;
import i08_affine_core;
import i08_affine_verify;
import i08_transition_core;
import particle_source_core;
fn verify(p:i08_link_core::Program&,source:u8[:],plan:i08_affine_core::Plan,proof:i08_transition_core::Proof)->bool {
 if !i08_link_verify::verify(p,source) || !i08_affine_verify::verify(p.tree,source,plan) {return false;}
 let t=p.tree;let job=p.cap.job;let core=job.core;let c=core.context;let site=core.sites;
 let cycle=t.nodes[plan.loop_id-1];let invariant=t.nodes[plan.invariant_id-1];let next=t.nodes[plan.next_node-1];let app=t.nodes[plan.append-1];let freeze=t.nodes[plan.freeze-1];let ret=t.nodes[plan.return_node-1];
 if cycle.start!=site.for_site.start || next.start!=site.next_site.start || ret.start!=site.return_site.start ||
    site.invariant_site.end>invariant.start || invariant.end>next.start || app.start>site.append_site.start || app.end<site.append_site.end ||
    freeze.start>site.freeze_site.start || freeze.end<site.freeze_site.end {return false;}
 // Independently reconnect the source-local append/next/freeze events and
 // their symbolic input/output role versions; none of these IDs is authority.
 if job.events.len<4 {return false;}let a=job.events[job.events.len-4];let n=job.events[job.events.len-3];let f=job.events[job.events.len-2];let r=job.events[job.events.len-1];
 if a.kind!=7 || a.site!=site.append_site.start || a.symbol!=c.builder || a.version!=c.builder_version ||
    a.output!=c.next_builder || a.output_version!=c.next_version || a.proof!=4 ||
    n.kind!=8 || n.site!=site.next_site.start || n.symbol!=c.next_builder || n.version!=c.next_version ||
    n.output!=c.builder || n.output_version!=c.builder_version || n.proof!=5 ||
    f.kind!=9 || f.site!=site.freeze_site.start || f.symbol!=c.builder || f.version!=c.builder_version ||
    f.output!=c.result || f.output_version!=c.result_version || f.proof!=6 ||
    r.kind!=10 || r.site!=site.return_site.start || r.symbol!=c.result || r.version!=c.result_version {return false;}
 // Rebuild the six closed-job premise links independently, including their
 // source origins. Their interpretation is conditional on the intrinsic rule.
 let evidence:particle_source_core::Evidence[6]=[
  particle_source_core::Evidence {rule:1,owner:c.owner,left:c.length,right:c.capacity,site:site.requires_site.start},
  particle_source_core::Evidence {rule:2,owner:c.owner,left:c.builder,right:c.index,version:c.builder_version,site:site.invariant_site.start},
  particle_source_core::Evidence {rule:3,owner:c.owner,left:c.index,right:c.length,version:c.input_version,site:site.for_site.start},
  particle_source_core::Evidence {rule:4,owner:c.owner,left:c.builder,right:c.capacity,version:c.builder_version,dep1:1,dep2:2,dep3:3,site:site.append_site.start},
  particle_source_core::Evidence {rule:5,owner:c.owner,left:c.next_builder,right:c.index,version:c.next_version,dep1:2,dep2:4,site:site.next_site.start},
  particle_source_core::Evidence {rule:6,owner:c.owner,left:c.result,right:c.length,version:c.result_version,dep1:2,dep2:5,site:site.return_site.start}
 ];
 for x,i in evidence {if !particle_source_core::same_evidence(x,core.proofs[i]) {return false;}}
 let expected:i08_transition_core::Step[6]=[
  i08_transition_core::Step {kind:1,site:site.requires_site.start,nat:plan.nat,capacity:plan.capacity},
  i08_transition_core::Step {kind:2,node:plan.invariant_id,site:site.invariant_site.start,subject:c.builder,version:c.builder_version,index:c.index,nat:plan.nat,dep1:1},
  i08_transition_core::Step {kind:3,node:plan.loop_id,site:site.for_site.start,index:c.index,nat:plan.nat,dep1:1},
  i08_transition_core::Step {kind:4,node:plan.append,site:site.append_site.start,subject:c.builder,version:c.builder_version,index:c.index,nat:plan.nat,capacity:plan.capacity,dep1:1,dep2:2,dep3:3},
  i08_transition_core::Step {kind:5,node:plan.next_node,site:site.next_site.start,subject:c.builder,version:c.builder_version,result:c.next_builder,result_version:c.next_version,index:c.index,nat:plan.nat,dep1:2,dep2:4},
  i08_transition_core::Step {kind:6,node:plan.return_node,site:site.return_site.start,subject:c.result,version:c.result_version,index:c.index,nat:plan.nat,dep1:2,dep2:5}
 ];
 for e,i in expected {if !i08_transition_core::same(e,proof.steps[i]) {return false;}}
 return true;
}
