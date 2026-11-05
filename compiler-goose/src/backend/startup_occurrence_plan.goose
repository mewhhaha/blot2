// Strong occurrence admission precedes weak-edge source ordering.
namespace blot_backend_startup_occurrence_plan;
import support.error;
import check.core;
import .startup_graph;
import .startup_occurrence_flow;
type Error=blot_error::Error;
type Graph=blot_backend_startup_graph::Graph;
type Plan=blot_backend_startup_graph::Plan;
type Declaration=blot_backend_startup_graph::Declaration;
type BindingRef=blot_check_core::BindingRef;
type List=blot_check_core::List;
type Edge=blot_backend_startup_occurrence_flow::Edge;
fn build(original:const Graph&,facts:const Edge[:],include_weak:bool)->Graph,Error {var declarations:Declaration[>..<]=[];var references:BindingRef[>..<]=[];var ranges:List[>..<]=[];for node in original.nodes {let start=references.len;for target in original.edges[node.references.start..node.references.start+node.references.len] {references.push(original.nodes[target].target);}for fact in facts {if fact.root==node.target && (include_weak || !fact.weak) {references.push(fact.target);}}if references.len>0xffffffff {return Graph{..},Error.invalid_dependency_graph;}ranges.push(List{start:start as u32,len:(references.len-start) as u32});declarations.push(Declaration{target:node.target,references:[],is_function:node.is_function,runtime:node.runtime,exported:node.exported,..});}for &declaration,index in declarations {let range=ranges[index];declaration.references=references[range.start..range.start+range.len];}return blot_backend_startup_graph::init(declarations);}
fn plan(original:const Graph&,facts:const Edge[:],reached:const bool[:])->Plan,Error {var strong,error=build(original,facts,false);if error!=Error.none {return Plan{..},error;}var admission,error=strong.plan(reached);strong.deinit();if error!=Error.none {return Plan{..},error;}if admission.cycle.present {return admission,Error.none;}admission.deinit();var ordered,error=build(original,facts,true);if error!=Error.none {return Plan{..},error;}let result,error=ordered.orderAfterStrongProof(reached);ordered.deinit();return result,error;}
