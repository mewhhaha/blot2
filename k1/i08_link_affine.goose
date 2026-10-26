// Binds an independently checked source-affine plan to the same source and
// job capability trace. This is still not a live allocator/loan authority.
namespace i08_link_affine;
import i08_link_core;
import i08_link_verify;
import i08_affine_core;
import i08_affine_build;
import i08_affine_verify;
fn verify(p:i08_link_core::Program&,source:u8[:],plan:i08_affine_core::Plan)->bool {
 if !i08_link_verify::verify(p,source) || !i08_affine_verify::verify(p.tree,source,plan) {return false;}
 let nodes=p.tree.nodes;let sites=p.cap.job.core.sites;
 if nodes[plan.loop_id-1].start!=sites.for_site.start || nodes[plan.next_node-1].start!=sites.next_site.start {return false;}
 let append=nodes[plan.append-1];let freeze=nodes[plan.freeze-1];let ret=nodes[plan.return_node-1];
 return append.start<=sites.append_site.start && sites.append_site.end<=append.end &&
  freeze.start<=sites.freeze_site.start && sites.freeze_site.end<=freeze.end && ret.start==sites.return_site.start;
}
fn build(p:i08_link_core::Program&,source:u8[:])->i08_affine_core::Result {
 if !i08_link_verify::verify(p,source) {return i08_affine_core::Result {status:1};}
 let r=i08_affine_build::build(p.tree,source);if r.status!=0 || !verify(p,source,r.plan) {return i08_affine_core::Result {status:1};}return r;
}
