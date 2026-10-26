// Independently rebinds each graph edge to its exact source import, alias and
// normalized module path. Filesystem provenance still comes from the trusted
// resolver and immutable-source coordination, not from this structural check.
namespace link_graph_check;
import project_graph;
import project_imports;
import project_imports_check;
import public_interface;
import source_identity;
fn span(start:i64,end:i64,n:i64) -> bool {return start>=0 && end>=start && end<=n;}
fn verify(g:project_graph::Graph&,package:u8[:],entry:u8[:]) -> bool {
 if g.package[..]!=package || !public_interface::package_valid(package) || !public_interface::module_valid(entry) ||
    g.modules.len<1 || g.modules.len>64 || g.edges.len>256 || g.observations.len!=0 ||
    g.paths.len>524288 || g.sources.len>16777216 {return false;}
 var path_end:i64=0;var source_end:i64=0;
 for m,i in g.modules {
  if !span(m.path_start,m.path_end,g.paths.len) || m.path_start!=path_end || m.path_end==m.path_start ||
     !span(m.source_start,m.source_end,g.sources.len) || m.source_start!=source_end {return false;}
  let path=g.paths[m.path_start..m.path_end];
  if path.len>4096 || !public_interface::module_valid(path) || (i==0 && path!=entry) {return false;}
  for j in i {let previous=g.modules[j];if g.paths[previous.path_start..previous.path_end]==path {return false;}}
  path_end=m.path_end;source_end=m.source_end;
 }
 if path_end!=g.paths.len || source_end!=g.sources.len || !project_graph::acyclic(g.modules,g.edges) {return false;}
 var edge_index:i64=0;var discovered:bool[64]=[false;64];discovered[0]=true;var next:i64=1;
 for m,i in g.modules {
  if !discovered[i] {return false;}
  let path=g.paths[m.path_start..m.path_end];let source=g.sources[m.source_start..m.source_end];
  let parsed=project_imports::parse(source);
  if parsed.status!=0 || !project_imports_check::verify(source,parsed.imports) {return false;}
  for imp in parsed.imports {
   if edge_index>=g.edges.len {return false;}
   let e=g.edges[edge_index];edge_index+=1;
   if e.from!=i || e.to<0 || e.to>=g.modules.len || e.alias_start!=m.source_start+imp.alias_start ||
      e.alias_end!=m.source_start+imp.alias_end || !span(e.alias_start,e.alias_end,g.sources.len) {return false;}
   let target=g.modules[e.to];
   let normalized=source_identity::normalize_import(path,source[imp.path_start..imp.path_end]);
   if normalized.status!=0 || normalized.path[..]!=g.paths[target.path_start..target.path_end] {return false;}
   if !discovered[e.to] {if e.to!=next {return false;}discovered[e.to]=true;next+=1;}
  }
 }
 return edge_index==g.edges.len && next==g.modules.len;
}
