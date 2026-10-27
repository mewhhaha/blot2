// Private single-snapshot job for a scalar leaf or bounded imported call chain.
// Root/package mapping, requested entry/name and budgets remain trusted.
namespace semantic_lift_job;
import source_resolver;import project_graph;import link_graph_check;import link_check;
import chain_program;import chain_wasm;import chain_target;import semantic_owner;import semantic_leaf_lift;import semantic_leaf_lift_check;
struct Output {status:i64=1,wasm:u8[]=[]}
// 0 success; 1 invalid/proof/target; 2 depth; 3 frame; 10..15 graph error;
// 20 cancellation; 31..36 checked chain error. No failure publishes bytes.
fn compile(root:source_resolver::Root&,entry:u8[:],name:u8[:],abi:u8[:],depth_used:u32,depth_limit:u32,frame_used:u32,frame_limit:u32,fault:u32)->Output {
 if fault>3 || abi.len!=32 {return Output {};}
 let no_probes:project_graph::Probe[]=[];let graph=project_graph::build(root,entry,no_probes);
 if graph.status!=0{return Output {status:10+graph.status};}
 if !link_graph_check::verify(graph.graph,root.package,entry){return Output {};}
 if fault==1{return Output {status:20};}
 if graph.graph.modules.len==1 {
  let m=graph.graph.modules[0];let source=graph.graph.sources[m.source_start..m.source_end];
  var owner=semantic_owner::build(root.package,entry,name,source);if owner.status!=0{return Output {};}
  if fault==2{return Output {status:20};}
  let bytes=semantic_owner::emit(root.package,entry,name,source,owner.owner,depth_used,depth_limit,frame_used,frame_limit);
  if bytes.status!=0{return Output {status:bytes.status};}
  if !semantic_owner::verify(root.package,entry,name,source,owner.owner,bytes.wasm){return Output {};}
  if fault==3{return Output {status:20};}return Output {status:0,wasm:copy(bytes.wasm)};
 }
 var lift=semantic_leaf_lift::build(graph.graph,root.package,entry);if lift.status!=0 || !semantic_leaf_lift_check::verify(graph.graph,lift.graph,root.package,entry){return Output {}; }
 let probes:link_check::Probe[]=[];let checked=chain_program::check(lift.graph,root.package,entry,abi,probes);
 if checked.status!=0{return Output {status:30+checked.status};}
 var p=chain_program::Plan {graph:copy(lift.graph),nodes:copy(checked.nodes),entries:copy(checked.entries),snapshot:copy(checked.snapshot)};
 if !chain_program::verify(p,root.package,entry,abi,probes){return Output {};}
 var found=false;for e in p.entries {if p.graph.sources[e.name_start..e.name_end]==name {found=true;}}
 if !found{return Output {};}
 // All emitted entries are covered: a wrapper plus advertised callee depth.
 // This is a compile-time capacity comparison, not actual runtime reservation.
 if depth_limit>128 || depth_used>depth_limit{return Output {status:2};}
 for e in p.entries {if e.target<0 || e.target>=p.nodes.len{return Output {};}
  let d=p.nodes[e.target].depth;if d>=128 || d+1>depth_limit-depth_used{return Output {status:2};}}
 if frame_used>frame_limit{return Output {status:3};}
 if fault==2{return Output {status:20};}
 let wasm=chain_wasm::emit(p,root.package,entry,abi,probes);
 if wasm.len==0 || !chain_target::verify(p,root.package,entry,abi,probes,wasm){return Output {};}
 if fault==3{return Output {status:20};}return Output {status:0,wasm:copy(wasm)};
}
