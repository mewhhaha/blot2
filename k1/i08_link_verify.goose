// Source-replayed association between independent bounded I08 syntax,
// numerical read checking and source-local particle capability trace.
// It does not discharge the formal View/builder caller obligations.
namespace i08_link_verify;
import i08_link_core;
import i08_header_verify;
import i08_bound_shape;
import i08_cap_verify;
fn verify(p:i08_link_core::Program&,source:u8[:])->bool {
 if !i08_header_verify::verify(p.tree,source) || !i08_bound_shape::verify(p.tree,source) || !i08_cap_verify::verify(p.cap,source) {return false;}
 let tree=p.tree;let core=p.cap.job.core;var reads:i64=0;var lowered:i64=0;var loops:i64=0;var append:i64=0;var freeze:i64=0;var nexts:i64=0;
 for n in tree.nodes {
  if n.tag==23 && n.b>=1 && n.b<=4 {reads+=1;var found:i64=0;for x in core.nodes {if x.kind==1 && x.start==n.start && x.end==n.end && x.field+1==n.b {found+=1;}}if found!=1 {return false;}}
  if n.tag==15 && n.start==core.sites.for_site.start {loops+=1;}
  if n.tag==27 && n.start<=core.sites.append_site.start && n.end>=core.sites.append_site.end {append+=1;}
  if n.tag==28 && n.start<=core.sites.freeze_site.start && n.end>=core.sites.freeze_site.end {freeze+=1;}
  if n.tag==9 && n.start==core.sites.next_site.start {nexts+=1;}
 }
 for x in core.nodes {
  if x.kind==1 {lowered+=1;var count:i64=0;for n in tree.nodes {if n.tag==23 && n.start==x.start && n.end==x.end && n.b==x.field+1 {count+=1;}}if count!=1 {return false;}}
  else if x.kind==2 {var count:i64=0;for n in tree.nodes {if n.tag==1 && n.a==7 && n.start==x.start && n.end==x.end {count+=1;}}if count!=1 {return false;}}
  else if x.kind==3 || x.kind==4 {var count:i64=0;for n in tree.nodes {let tag=if x.kind==3 {25} else {21};if n.tag!=tag || n.a<1 || n.a>tree.nodes.len || n.b<1 || n.b>tree.nodes.len {continue;}let l=tree.nodes[n.a-1];let r=tree.nodes[n.b-1];if l.end<=x.start && x.end<=r.start {count+=1;}}if count!=1 {return false;}}
  else {return false;}
 }
 return reads>0 && reads==lowered && loops==1 && append==1 && freeze==1 && nexts==1;
}
