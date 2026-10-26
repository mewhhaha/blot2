import project_imports;
import project_imports_check;
import project_graph;
fn next(s:u64&) -> u32 {s=(s*1664525+1013904223)&4294967295;return s as u32;}
fn main() {
 let source="import \"./a.blot\" as apple\nimport \"../b.blot\" as berry\nlet x: U32 = 1\n";
 let p=project_imports::parse(source);assert(p.status==0 && project_imports_check::verify(source,p.imports));
 for i in source.len {for c in [0,10,32,34,47,46,65,95,120,255] {
  var changed:u8[>..]=[];changed.append(source);changed[i]=c as u8;
  let r=project_imports::parse(changed);
  if r.status==0 {assert(project_imports_check::verify(changed,r.imports));}
 }}
 for i in p.imports.len {for f in 4 {for value in [-1 as i64,0,1,99999999,9223372036854775807] {
  var items:project_imports::Import[>..]=[];items.append(p.imports);let old=items[i];var previous:i64=0;
  if f==0 {previous=old.path_start;items[i].path_start=value;}
  else if f==1 {previous=old.path_end;items[i].path_end=value;}
  else if f==2 {previous=old.alias_start;items[i].alias_start=value;}
  else {previous=old.alias_end;items[i].alias_end=value;}
  if previous!=value {assert(!project_imports_check::verify(source,items));}
 }}}
 var rng:u64=0x3859ab11;
 for _ in 2000 {
   let count=(next(rng)%20+1) as i64;let edge_count=(next(rng)%100) as i64;
   var modules:project_graph::Module[>..]=[];for i in count {modules.push(project_graph::Module {});}
   var edges:project_graph::Edge[>..]=[];var graph:bool[400]=[false;400];
   for i in edge_count {let a=(next(rng)%count as u32) as i64;let b=(next(rng)%count as u32) as i64;
       edges.push(project_graph::Edge {from:a,to:b});graph[a*20+b]=true;}
   for k in count {for i in count {for j in count {if graph[i*20+k] && graph[k*20+j] {graph[i*20+j]=true;}}}}
   var cycle=false;for i in count {if graph[i*20+i] {cycle=true;}}
   assert(project_graph::acyclic(modules,edges)==!cycle);
 }
 print("project imports and cycle oracle passed");
}
