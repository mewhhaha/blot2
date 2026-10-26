// Formal proof-plan producer for the exact source-local I08 transition.
// The append rule is a conditional intrinsic contract, not a live capability
// or proof of the runtime implementation, host ABI, or per-iteration freshness.
namespace i08_transition_build;
import i08_link_core;
import i08_link_verify;
import i08_affine_core;
import i08_affine_verify;
import i08_transition_core;
fn build(p:i08_link_core::Program&,source:u8[:],plan:i08_affine_core::Plan)->i08_transition_core::Result {
 if !i08_link_verify::verify(p,source) || !i08_affine_verify::verify(p.tree,source,plan) {return i08_transition_core::Result {status:1};}
 let t=p.tree;let core=p.cap.job.core;let c=core.context;let sites=core.sites;
 let loop_node=t.nodes[plan.loop_id-1];let inv=t.nodes[plan.invariant_id-1];let next=t.nodes[plan.next_node-1];let append=t.nodes[plan.append-1];let freeze=t.nodes[plan.freeze-1];let ret=t.nodes[plan.return_node-1];
 if loop_node.start!=sites.for_site.start || next.start!=sites.next_site.start || ret.start!=sites.return_site.start ||
    sites.invariant_site.end>inv.start || inv.end>next.start || sites.append_site.start<append.start || sites.append_site.end>append.end ||
    sites.freeze_site.start<freeze.start || sites.freeze_site.end>freeze.end {return i08_transition_core::Result {status:1};}
 // Roles are job-local symbolic input/output slots. The proof is instantiated
 // afresh per iteration only by a future checker for actual builder versions.
 let steps:i08_transition_core::Step[6]=[
  i08_transition_core::Step {kind:1,site:sites.requires_site.start,nat:plan.nat,capacity:plan.capacity},
  i08_transition_core::Step {kind:2,node:plan.invariant_id,site:sites.invariant_site.start,subject:c.builder,version:c.builder_version,index:c.index,nat:plan.nat,dep1:1},
  i08_transition_core::Step {kind:3,node:plan.loop_id,site:sites.for_site.start,index:c.index,nat:plan.nat,dep1:1},
  i08_transition_core::Step {kind:4,node:plan.append,site:sites.append_site.start,subject:c.builder,version:c.builder_version,index:c.index,nat:plan.nat,capacity:plan.capacity,dep1:1,dep2:2,dep3:3},
  i08_transition_core::Step {kind:5,node:plan.next_node,site:sites.next_site.start,subject:c.builder,version:c.builder_version,result:c.next_builder,result_version:c.next_version,index:c.index,nat:plan.nat,dep1:2,dep2:4},
  i08_transition_core::Step {kind:6,node:plan.return_node,site:sites.return_site.start,subject:c.result,version:c.result_version,index:c.index,nat:plan.nat,dep1:2,dep2:5}
 ];
 return i08_transition_core::Result {proof:i08_transition_core::Proof {steps:steps}};
}
