// Private source-bound two-function module plan. Graph and interface records
// come from a fresh trusted descriptor-root read, not an imported artifact.
// This is not full K1 admission, a public ABI or proof/work qualification.
namespace linked_program;
import source_resolver;
import project_graph;
import link_graph_check;
import link_lines;
import link_consumer;
import link_consumer_check;
import link_exports;
import link_check;
import public_frontend;
import public_artifact;
import scalar_plan;

struct Selection {status:i64=1, caller_start:i64=0,caller_end:i64=0,provider:scalar_plan::ScalarLoweringPlan=scalar_plan::ScalarLoweringPlan {}}
struct Plan {graph:project_graph::Graph=project_graph::Graph {},snapshot:link_check::Snapshot=link_check::Snapshot {},
             caller_start:i64=0,caller_end:i64=0,provider:scalar_plan::ScalarLoweringPlan=scalar_plan::ScalarLoweringPlan {}}
struct Result {status:i64=0, plan:Plan=Plan {},missing:u8[]=[], lookup:link_check::Snapshot=link_check::Snapshot {}}
// Re-derive the selected provider from checked source edges and exact exported
// name, then independently recheck its source-bound canonical interface.
fn select(g:project_graph::Graph&,package:u8[:],entry:u8[:],abi:u8[:]) -> Selection {
 if !link_graph_check::verify(g,package,entry) {return Selection {};}
 let root=g.modules[0];let source=g.sources[root.source_start..root.source_end];
 let lines=link_lines::split(source);if lines.status!=0 || lines.lines.len!=1 {return Selection {};}
 let line_span=lines.lines[0];let line=source[line_span.start..line_span.end];
 let call=link_consumer::parse(line);if call.status!=0 || !link_consumer_check::verify(line,call) {return Selection {};}
 let alias=line[call.alias_start..call.alias_end];let name=line[call.target_start..call.target_end];
 var target:i64=-1;
 for edge in g.edges {if edge.from==0 && g.sources[edge.alias_start..edge.alias_end]==alias {target=edge.to;break;}}
 if target<1 || target>=g.modules.len {return Selection {};}
 let exports=link_exports::collect(g,abi);if exports.status!=0 {return Selection {};}
 var index:i64=-1;
 for item,i in exports.values {if item.module==target && g.sources[item.name_start..item.name_end]==name {index=i;break;}}
 if index<0 {return Selection {};}
 let item=exports.values[index];let module=g.modules[target];
 let provider_source=g.sources[item.line_start..item.line_end];let producer=g.paths[module.path_start..module.path_end];
 let candidate=public_frontend::parse(provider_source);
 let interface=exports.interfaces[item.interface_start..item.interface_end];
 if candidate.status!=0 || candidate.core.result_type!=1 || candidate.declared_depth>=128 ||
    public_artifact::verify_source(interface,provider_source,candidate,g.package,producer,name,abi)!=0 {return Selection {};}
 // This private emitter has no qualified frame arena or wrapper preflight.
 // Accept only a zero-frame provider rather than treating a nonzero resource
 // contract as established by the simplified two-function target.
 if candidate.declared_frame!=0 {return Selection {status:5};}
 let plan=scalar_plan::make(candidate.core);if !scalar_plan::validate(plan) {return Selection {};}
 return Selection {status:0,caller_start:root.source_start+line_span.start+call.name_start,
  caller_end:root.source_start+line_span.start+call.name_end,provider:plan};
}
// Structural/source association is re-established from bytes; an arbitrary
// caller-supplied graph cannot authenticate filesystem origin or a work receipt.
fn verify(plan:Plan&,package:u8[:],entry:u8[:],abi:u8[:],probes:link_check::Probe[:]) -> bool {
 if !link_graph_check::verify(plan.graph,package,entry) {return false;}
 let checked=link_check::check(plan.graph,package,entry,abi,probes);
 if checked.status!=0 || !link_check::same(plan.snapshot,checked.snapshot) {return false;}
 let selected=select(plan.graph,package,entry,abi);
 return selected.status==0 && selected.caller_start==plan.caller_start && selected.caller_end==plan.caller_end &&
        selected.provider==plan.provider;
}
fn prepare(root:source_resolver::Root&,entry:u8[:],abi:u8[:],probes:link_check::Probe[:]) -> Result {
 let none:project_graph::Probe[]=[];let graph=project_graph::build(root,entry,none);
 if graph.status!=0 {return Result {status:10+graph.status,missing:copy(graph.missing)};}
 let checked=link_check::check(graph.graph,root.package,entry,abi,probes);
 if checked.status!=0 {return Result {status:checked.status,lookup:copy(checked.snapshot)};}
 let selected=select(graph.graph,root.package,entry,abi);
 if selected.status!=0 {return Result {status:if selected.status==5 {5} else {6}};}
 var plan=Plan {graph:copy(graph.graph),snapshot:copy(checked.snapshot),caller_start:selected.caller_start,
  caller_end:selected.caller_end,provider:selected.provider};
 if !verify(plan,root.package,entry,abi,probes) {return Result {status:6};}
 return Result {plan:plan};
}
