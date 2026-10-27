// Independent source/Core correspondence check for each changed leaf.
// Synthetic source is only a checked internal representation, not authority.
namespace semantic_leaf_lift_check;
import project_graph;import link_graph_check;import short_frontend;import short_check;import semantic_owner;import public_frontend;
fn number(t:u8[:])->u32,bool {if t.len==0{return 0,false;}var n:u64=0;for c in t {if c<'0' || c>'9'{return 0,false;}let d=(c-'0') as u64;if n>(4294967295-d)/10{return 0,false;}n=n*10+d;}return n as u32,true;}
fn proof(package:u8[:],path:u8[:],source:u8[:],synthetic:u8[:])->bool {
 var s=short_frontend::parse(source);if s.status!=0 || !short_check::verify(source,s.program) {return false;}let p=s.program;let h=p.head;
 if h.argument!=1 || h.result!=1 || h.frame!=0 || h.let_start<0 || h.let_start>source.len || p.name_start<0 || p.name_end<=p.name_start || p.name_end>source.len-h.let_start{return false;}
 let name=source[h.let_start+p.name_start..h.let_start+p.name_end];var owner=semantic_owner::build(package,path,name,source);if owner.status!=0 || !semantic_owner::valid(package,path,name,source,owner.owner){return false;}
 let t=owner.owner.core.program.tree;if t.nodes.len!=3 || t.bindings.len!=1 || t.root!=3{return false;}let r=t.nodes[2];let q=t.nodes[1];let x=t.nodes[0];if r.tag!=18 || r.a!=2 || r.b!=1 || q.tag!=13 || q.a!=1{return false;}
 let c=public_frontend::parse(synthetic);if c.status!=0 || !public_frontend::verify(synthetic,c) || c.declared_depth!=h.depth || c.declared_frame!=h.frame || c.core.result_type!=1 || c.core.name_start<0 || c.core.name_end>synthetic.len || synthetic[c.core.name_start..c.core.name_end]!=name || c.core.result_id<0 || c.core.result_id>=c.core.value_count{return false;}
 let result=c.core.values[c.core.result_id];if x.tag==1 && x.a==1 {return result.producer==1 && c.core.value_count==1;}
 if x.tag!=2 || x.start<0 || x.end<=x.start || x.end>t.source.len{return false;}let v,ok=number(t.source[x.start..x.end]);return ok && result.producer==2 && result.literal==v;
}
fn verify(old:project_graph::Graph&,new:project_graph::Graph&,package:u8[:],entry:u8[:])->bool {
 if !link_graph_check::verify(old,package,entry) || !link_graph_check::verify(new,package,entry) || old.package[..]!=new.package[..] || old.paths[..]!=new.paths[..] || old.modules.len!=new.modules.len || old.edges.len!=new.edges.len{return false;}
 for m,i in old.modules {let n=new.modules[i];if m.path_start!=n.path_start || m.path_end!=n.path_end{return false;}
  let a=old.sources[m.source_start..m.source_end];let b=new.sources[n.source_start..n.source_end];if a!=b {
   if i==0{return false;}for e in old.edges {if e.from==i{return false;}}
   if !proof(package,old.paths[m.path_start..m.path_end],a,b){return false;}
  }
 }
 for e,i in old.edges {let f=new.edges[i];let a=old.modules[e.from];let b=new.modules[f.from];if e.from!=f.from || e.to!=f.to || e.alias_start-a.source_start!=f.alias_start-b.source_start || e.alias_end-a.source_start!=f.alias_end-b.source_start{return false;}}
 return true;
}
