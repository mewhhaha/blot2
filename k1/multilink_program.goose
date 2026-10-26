// Private bounded multi-entry imported-call fixture; not full K1 admission.
namespace multilink_program;
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
import validate;

struct Entry {name_start:i64=0,name_end:i64=0,provider:scalar_plan::ScalarLoweringPlan=scalar_plan::ScalarLoweringPlan {}}
struct Plan {graph:project_graph::Graph=project_graph::Graph {},snapshot:link_check::Snapshot=link_check::Snapshot {},entries:Entry[]=[]}
struct Result {status:i64=0,plan:Plan=Plan {},missing:u8[]=[],lookup:link_check::Snapshot=link_check::Snapshot {}}
struct Checked {status:i64=0,entries:Entry[]=[],snapshot:link_check::Snapshot=link_check::Snapshot {}}
fn check(g:project_graph::Graph&,package:u8[:],entry:u8[:],abi:u8[:],probes:link_check::Probe[:])->Checked {
 if abi.len!=32 || probes.len>32 || !link_graph_check::verify(g,package,entry) {return Checked {status:1};}
 let root=g.modules[0];let source=g.sources[root.source_start..root.source_end];let lines=link_lines::split(source);
 if lines.status!=0 || lines.lines.len<1 || lines.lines.len>16 {return Checked {status:1};}
 let exports=link_exports::collect(g,abi);if exports.status!=0 {return Checked {status:1};}
 var keys:u8[>..]=[];var interfaces:u8[>..]=[];var observations:link_check::Observation[>..]=[];
 var entries:Entry[>..]=[];var depth:u32=0;
 for span in lines.lines {
  let line=source[span.start..span.end];let call=link_consumer::parse(line);
  if call.status!=0 || !link_consumer_check::verify(line,call) {return Checked {status:1};}
  let fname=line[call.name_start..call.name_end];
  for e in g.edges {if e.from==0 && g.sources[e.alias_start..e.alias_end]==fname {return Checked {status:1};}}
  for prior in entries {if g.sources[prior.name_start..prior.name_end]==fname {return Checked {status:1};}}
  let alias=line[call.alias_start..call.alias_end];let name=line[call.target_start..call.target_end];
  let status,declared_depth=link_check::lookup(g,exports,abi,alias,name,keys,interfaces,observations);
  if status!=0 {return Checked {status:status,snapshot:link_check::Snapshot {consumer:source,keys:keys,interfaces:interfaces,observations:observations}};}
  if declared_depth>=128 {return Checked {status:5};}if declared_depth+1>depth {depth=declared_depth+1;}
  var target:i64=-1;for edge in g.edges {if edge.from==0 && g.sources[edge.alias_start..edge.alias_end]==alias {target=edge.to;break;}}
  if target<1 || target>=g.modules.len {return Checked {status:1};}
  var idx:i64=-1;for item,i in exports.values {if item.module==target && g.sources[item.name_start..item.name_end]==name {idx=i;break;}}
  if idx<0 {return Checked {status:1};}
  let item=exports.values[idx];let module=g.modules[target];let producer=g.paths[module.path_start..module.path_end];
  let provider_source=g.sources[item.line_start..item.line_end];let candidate=public_frontend::parse(provider_source);
  let encoded=exports.interfaces[item.interface_start..item.interface_end];
  if candidate.status!=0 || candidate.core.result_type!=1 || candidate.declared_depth>=128 || candidate.declared_frame!=0 ||
   public_artifact::verify_source(encoded,provider_source,candidate,g.package,producer,name,abi)!=0 {return Checked {status:5};}
  let p=scalar_plan::make(candidate.core);if !scalar_plan::validate(p) {return Checked {status:1};}
  entries.push(Entry {name_start:root.source_start+span.start+call.name_start,name_end:root.source_start+span.start+call.name_end,provider:p});
 }
 // Probes are conservative module-scope questions and may not be confused
 // with any declaration or parameter visible inside a checked caller.
 for probe in probes {
  if !validate::name_valid(probe.alias) || !validate::name_valid(probe.name) || probe.alias.len>4096 || probe.name.len>4096 {return Checked {status:1};}
  for span in lines.lines {let line=source[span.start..span.end];let call=link_consumer::parse(line);
   if probe.alias[..]==line[call.name_start..call.name_end] || probe.alias[..]==line[call.param_start..call.param_end] {return Checked {status:1};}}
  let status,_=link_check::lookup(g,exports,abi,probe.alias,probe.name,keys,interfaces,observations);
  if status!=0 && status!=3 && status!=4 {return Checked {status:status};}
 }
 return Checked {entries:entries,snapshot:link_check::Snapshot {consumer:source,keys:keys,interfaces:interfaces,observations:observations,caller_depth:depth}};
}
fn verify(plan:Plan&,package:u8[:],entry:u8[:],abi:u8[:],probes:link_check::Probe[:])->bool {
 let checked=check(plan.graph,package,entry,abi,probes);
 return checked.status==0 && checked.entries[..]==plan.entries[..] && link_check::same(checked.snapshot,plan.snapshot);
}
fn prepare(root:source_resolver::Root&,entry:u8[:],abi:u8[:],probes:link_check::Probe[:])->Result {
 let none:project_graph::Probe[]=[];let graph=project_graph::build(root,entry,none);
 if graph.status!=0 {return Result {status:10+graph.status,missing:copy(graph.missing)};}
 let checked=check(graph.graph,root.package,entry,abi,probes);
 if checked.status!=0 {return Result {status:checked.status,lookup:copy(checked.snapshot)};}
 var p=Plan {graph:copy(graph.graph),snapshot:copy(checked.snapshot),entries:copy(checked.entries)};
 if !verify(p,root.package,entry,abi,probes) {return Result {status:6};}
 return Result {plan:p};
}
