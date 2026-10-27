// Private bridge: original checked multiline leaf -> source-verified simple
// scalar representation. Only exact identity and U32 literal bodies qualify.
namespace semantic_leaf_lift;
import std;import project_graph;import link_graph_check;import short_frontend;import short_check;import short_fact_build;import semantic_owner;import public_frontend;
struct Lift {status:i64=1,graph:project_graph::Graph=project_graph::Graph {},count:i64=0}
struct Shape {ok:bool=false,name:u8[]=[],depth:u32=0,kind:i64=0,literal:u32=0}
// Derive only semantics present in a fully source-replayed, typed Core.
fn shape(package:u8[:],path:u8[:],source:u8[:])->Shape {
 var parsed=short_frontend::parse(source);if parsed.status!=0 || !short_check::verify(source,parsed.program){return Shape {};}
 let p=parsed.program;let h=p.head;if h.argument!=1 || h.result!=1 || h.frame!=0{return Shape {};}
 let start=h.let_start;let a=p.name_start;let b=p.name_end;if start<0 || start>source.len || a<0 || b<=a || b>source.len-start{return Shape {};}
 let name=source[start+a..start+b];var owned:u8[>..]=[];owned.append(name);var owner=semantic_owner::build(package,path,name,source);if owner.status!=0 || !semantic_owner::valid(package,path,name,source,owner.owner){return Shape {};}
 let t=owner.owner.core.program.tree;if t.nodes.len!=3 || t.bindings.len!=1 || t.root!=3{return Shape {};}
 let expr=t.nodes[0];let ret=t.nodes[1];let root=t.nodes[2];
 if root.tag!=18 || root.a!=2 || root.b!=1 || ret.tag!=13 || ret.a!=1{return Shape {};}
 if expr.tag==1 && expr.a==1 {return Shape {ok:true,name:copy(owned),depth:h.depth,kind:1};}
 if expr.tag==2 {let value,ok=short_fact_build::literal(t,1);if ok{return Shape {ok:true,name:copy(owned),depth:h.depth,kind:2,literal:value as u32};}}
 return Shape {};
}
fn leaf(g:project_graph::Graph&,i:i64)->bool {for e in g.edges {if e.from==i{return false;}}return true;}
fn text(s:Shape&)->u8[] {let value=if s.kind==1 {str("x")} else {str(s.literal)};return str("pub let ",s.name,": U32 -> U32 ! {} resources {depth: ",s.depth,", frame: 0} = fn x => return ",value,"\n");}
fn build(original:project_graph::Graph&,package:u8[:],entry:u8[:])->Lift {
 if !link_graph_check::verify(original,package,entry){return Lift {};}
 var sources:u8[>..]=[];var modules:project_graph::Module[>..]=[];var count:i64=0;
 for m,i in original.modules {let src=original.sources[m.source_start..m.source_end];let path=original.paths[m.path_start..m.path_end];var candidate: u8[>..]=[];
  if i>0 && leaf(original,i) {var s=shape(package,path,src);if s.ok {candidate.append(text(s));count+=1;}}
  let start=sources.len;if candidate.len>0 {sources.append(candidate);} else {sources.append(src);}modules.push(project_graph::Module {path_start:m.path_start,path_end:m.path_end,source_start:start,source_end:sources.len});
 }
 var edges:project_graph::Edge[>..]=[];for e in original.edges {let old=original.modules[e.from];let new=modules[e.from];edges.push(project_graph::Edge {from:e.from,to:e.to,alias_start:new.source_start+(e.alias_start-old.source_start),alias_end:new.source_start+(e.alias_end-old.source_start)});}
 let graph=project_graph::Graph {package:copy(original.package),paths:copy(original.paths),sources:copy(sources),modules:copy(modules),edges:copy(edges)};
 if !link_graph_check::verify(graph,package,entry){return Lift {};}
 return Lift {status:0,graph:graph,count:count};
}
