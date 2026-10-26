import os;
import source_resolver;
import project_graph;
import link_graph_check;
fn main() {
 let a=args();var root=source_resolver::open_root(a[1],"pkg");assert(root.status==0);
 let probes:project_graph::Probe[]=[];var g=project_graph::build(root.root,"main.blot",probes);assert(g.status==0);
 assert(link_graph_check::verify(g.graph,"pkg","main.blot"));
 let values:i64[]=[-1,0,1,2,1000,9223372036854775807];
 for i in g.graph.modules.len {let old=g.graph.modules[i];for f in 4 {for v in values {
  var bad=copy(g.graph);var was:i64=0;
  if f==0 {was=old.path_start;bad.modules[i].path_start=v;}else if f==1 {was=old.path_end;bad.modules[i].path_end=v;}
  else if f==2 {was=old.source_start;bad.modules[i].source_start=v;}else {was=old.source_end;bad.modules[i].source_end=v;}
  if was!=v {assert(!link_graph_check::verify(bad,"pkg","main.blot"));}
 }}}
 for i in g.graph.edges.len {let old=g.graph.edges[i];for f in 4 {for v in values {
  var bad=copy(g.graph);var was:i64=0;
  if f==0 {was=old.from;bad.edges[i].from=v;}else if f==1 {was=old.to;bad.edges[i].to=v;}
  else if f==2 {was=old.alias_start;bad.edges[i].alias_start=v;}else {was=old.alias_end;bad.edges[i].alias_end=v;}
  if was!=v {assert(!link_graph_check::verify(bad,"pkg","main.blot"));}
 }}}
 assert(source_resolver::close_root(root.root));print("link graph forged span/edge audit passed");
}
