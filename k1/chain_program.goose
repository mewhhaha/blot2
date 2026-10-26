// Bounded one-public-declaration-per-module call-chain experiment. The graph
// must come from a trusted fresh resolver; this is not full project admission.
namespace chain_program;
import project_graph;
import link_graph_check;
import source_resolver;
import link_lines;
import link_consumer;
import link_consumer_check;
import link_check;
import chain_public;
import chain_public_check;
import public_frontend;
import public_artifact;
import scalar_plan;
import validate;
struct Node {module:i64=0,name_start:i64=0,name_end:i64=0,line_start:i64=0,line_end:i64=0,
 alias_start:i64=0,alias_end:i64=0,target_start:i64=0,target_end:i64=0,target:i64=-1,kind:u32=0,depth:u32=0,frame:u32=0,
 iface_start:i64=0,iface_end:i64=0,scalar:scalar_plan::ScalarLoweringPlan=scalar_plan::ScalarLoweringPlan {}}
struct Entry {name_start:i64=0,name_end:i64=0,target:i64=-1}
struct Observation {from:i64=0,kind:u32=0,found:bool=false,alias_start:i64=0,alias_end:i64=0,name_start:i64=0,name_end:i64=0,
 path_start:i64=0,path_end:i64=0,iface_start:i64=0,iface_end:i64=0}
struct Snapshot {consumer:u8[]=[],keys:u8[]=[],interfaces:u8[]=[],obs:Observation[]=[]}
struct Plan {graph:project_graph::Graph=project_graph::Graph {},nodes:Node[]=[],entries:Entry[]=[],snapshot:Snapshot=Snapshot {}}
struct Checked {status:i64=0,nodes:Node[]=[],entries:Entry[]=[],snapshot:Snapshot=Snapshot {}}
struct Result {status:i64=0,plan:Plan=Plan {},missing:u8[]=[],lookup:Snapshot=Snapshot {}}
fn finish(status:i64,nodes:Node[:],entries:Entry[:],consumer:u8[:],keys:u8[:],interfaces:u8[:],obs:Observation[:])->Checked {
 return Checked {status:status,nodes:nodes,entries:entries,snapshot:Snapshot {consumer:consumer,keys:keys,interfaces:interfaces,obs:obs}};
}
// Every query is tied to a source module and exact alias/name/producer/interface.
fn lookup(g:project_graph::Graph&,nodes:Node[:],from:i64,alias:u8[:],name:u8[:],
 keys:u8[>..]&,interfaces:u8[:],obs:Observation[>..]&) -> i64,i64 {
 if alias.len==0 || name.len==0 || alias.len>4096 || name.len>4096 || obs.len>510 || alias.len+name.len>524288-keys.len {return 2,-1;}
 let a=keys.len;keys.append(alias);let ae=keys.len;let n=keys.len;keys.append(name);let ne=keys.len;
 var module:i64=-1;
 for e in g.edges {if e.from==from && g.sources[e.alias_start..e.alias_end]==alias {module=e.to;break;}}
 if module<0 {obs.push(Observation {from:from,kind:1,alias_start:a,alias_end:ae,name_start:n,name_end:ne});return 3,-1;}
 if module<1 || module>nodes.len {return 1,-1;}
 let m=g.modules[module];let path=g.paths[m.path_start..m.path_end];if path.len>524288-keys.len {return 2,-1;}
 let start=keys.len;keys.append(path);let end=keys.len;
 obs.push(Observation {from:from,kind:1,found:true,alias_start:a,alias_end:ae,name_start:n,name_end:ne,path_start:start,path_end:end});
 let node=nodes[module-1];
 if g.sources[node.name_start..node.name_end]!=name {
  obs.push(Observation {from:from,kind:2,alias_start:a,alias_end:ae,name_start:n,name_end:ne,path_start:start,path_end:end});return 4,-1;
 }
 if node.iface_start<0 || node.iface_end<node.iface_start || node.iface_end>interfaces.len {return 1,-1;}
 obs.push(Observation {from:from,kind:2,found:true,alias_start:a,alias_end:ae,name_start:n,name_end:ne,path_start:start,path_end:end,iface_start:node.iface_start,iface_end:node.iface_end});
 return 0,module-1;
}
fn check(g:project_graph::Graph&,package:u8[:],entry:u8[:],abi:u8[:],probes:link_check::Probe[:])->Checked {
 if abi.len!=32 || probes.len>32 || !link_graph_check::verify(g,package,entry) || g.modules.len<2 {return Checked {status:1};}
 let root=g.modules[0];let source=g.sources[root.source_start..root.source_end];
 let lines=link_lines::split(source);if lines.status!=0 || lines.lines.len<1 || lines.lines.len>16 {return Checked {status:1};}
 var nodes:Node[>..]=[];var entries:Entry[>..]=[];var keys:u8[>..]=[];var interfaces:u8[>..]=[];var obs:Observation[>..]=[];
 for module,mid in g.modules {
  if mid==0 {continue;}
  let text=g.sources[module.source_start..module.source_end];let path=g.paths[module.path_start..module.path_end];
  let parts=link_lines::split(text);if parts.status!=0 || parts.lines.len!=1 {return Checked {status:1};}
  let span=parts.lines[0];let line=text[span.start..span.end];let base=module.source_start+span.start;
  let c=public_frontend::parse(line);let call=chain_public::parse(line,g.package,path,abi);
  var node=Node {module:mid,line_start:base,line_end:base+line.len};
  if c.status==0 {
   if c.core.result_type!=1 || c.declared_frame!=0 {return Checked {status:5};}
   node.kind=1;node.name_start=base+c.core.name_start;node.name_end=base+c.core.name_end;
   node.depth=c.declared_depth;node.frame=c.declared_frame;node.scalar=scalar_plan::make(c.core);
   if !scalar_plan::validate(node.scalar) {return Checked {status:1};}
   let name=g.sources[node.name_start..node.name_end];let iface=public_artifact::encode(line,c,g.package,path,name,abi);
   if iface.len==0 || public_artifact::verify_source(iface,line,c,g.package,path,name,abi)!=0 || iface.len>1048576-interfaces.len {return Checked {status:1};}
   node.iface_start=interfaces.len;interfaces.append(iface);node.iface_end=interfaces.len;
  }else if call.status==0 {
   if call.frame!=0 {return Checked {status:5};}
   if !chain_public_check::verify(line,call.name_start,call.name_end,call.param_start,call.param_end,
       call.alias_start,call.alias_end,call.target_start,call.target_end,call.depth,call.frame) {return Checked {status:1};}
   let declared=line[call.name_start..call.name_end];
   let decoded=public_artifact::decode(call.interface,g.package,path,declared,abi);
   if decoded.status!=0 || decoded.result_type!=1 || decoded.declared_depth!=call.depth || decoded.declared_frame!=call.frame {return Checked {status:1};}
   node.kind=2;node.name_start=base+call.name_start;node.name_end=base+call.name_end;
   node.alias_start=base+call.alias_start;node.alias_end=base+call.alias_end;
   node.target_start=base+call.target_start;node.target_end=base+call.target_end;node.depth=call.depth;node.frame=call.frame;
   if call.interface.len>1048576-interfaces.len {return Checked {status:2};}
   node.iface_start=interfaces.len;interfaces.append(call.interface);node.iface_end=interfaces.len;
  }else{return Checked {status:1};}
  for edge in g.edges {if edge.from==mid && g.sources[edge.alias_start..edge.alias_end]==g.sources[node.name_start..node.name_end] {return Checked {status:1};}}
  nodes.push(node);
 }
 // Resolve all public wrappers, preserving ordered cross-module observations.
 for node,i in nodes {
  if node.kind==2 {
   let alias=g.sources[node.alias_start..node.alias_end];let name=g.sources[node.target_start..node.target_end];
   let status,target=lookup(g,nodes,node.module,alias,name,keys,interfaces,obs);
   if status!=0 {return finish(status,nodes,entries,source,keys,interfaces,obs);}
   if nodes[target].depth>=128 || node.depth<nodes[target].depth+1 {return Checked {status:5};}
   nodes[i].target=target;
  }
 }
 for span in lines.lines {
  let line=source[span.start..span.end];let call=link_consumer::parse(line);
  if call.status!=0 || !link_consumer_check::verify(line,call) {return Checked {status:1};}
  let name=line[call.name_start..call.name_end];
  for edge in g.edges {if edge.from==0 && g.sources[edge.alias_start..edge.alias_end]==name {return Checked {status:1};}}
  for e in entries {if g.sources[e.name_start..e.name_end]==name {return Checked {status:1};}}
  let status,target=lookup(g,nodes,0,line[call.alias_start..call.alias_end],line[call.target_start..call.target_end],keys,interfaces,obs);
  if status!=0 {return finish(status,nodes,entries,source,keys,interfaces,obs);}
  if nodes[target].depth>=128 {return Checked {status:5};}
  entries.push(Entry {name_start:root.source_start+span.start+call.name_start,name_end:root.source_start+span.start+call.name_end,target:target});
 }
 for probe in probes {
  if !validate::name_valid(probe.alias) || !validate::name_valid(probe.name) || probe.alias.len>4096 || probe.name.len>4096 {return Checked {status:1};}
  for span in lines.lines {let line=source[span.start..span.end];let call=link_consumer::parse(line);
   if probe.alias[..]==line[call.name_start..call.name_end] || probe.alias[..]==line[call.param_start..call.param_end] {return Checked {status:1};}}
  let status,_=lookup(g,nodes,0,probe.alias,probe.name,keys,interfaces,obs);
  if status!=0 && status!=3 && status!=4 {return Checked {status:status};}
 }
 return finish(0,nodes,entries,source,keys,interfaces,obs);
}
fn same(a:Snapshot&,b:Snapshot&)->bool{return a.consumer[..]==b.consumer[..] && a.keys[..]==b.keys[..] && a.interfaces[..]==b.interfaces[..] && a.obs[..]==b.obs[..];}
fn verify(plan:Plan&,package:u8[:],entry:u8[:],abi:u8[:],probes:link_check::Probe[:])->bool {
 let c=check(plan.graph,package,entry,abi,probes);
 return c.status==0 && c.nodes[..]==plan.nodes[..] && c.entries[..]==plan.entries[..] && same(c.snapshot,plan.snapshot);
}
fn prepare(root:source_resolver::Root&,entry:u8[:],abi:u8[:],probes:link_check::Probe[:])->Result {
 let none:project_graph::Probe[]=[];let graph=project_graph::build(root,entry,none);
 if graph.status!=0 {return Result {status:10+graph.status,missing:copy(graph.missing)};}
 let checked=check(graph.graph,root.package,entry,abi,probes);
 if checked.status!=0 {return Result {status:checked.status,lookup:copy(checked.snapshot)};}
 var p=Plan {graph:copy(graph.graph),nodes:copy(checked.nodes),entries:copy(checked.entries),snapshot:copy(checked.snapshot)};
 if !verify(p,root.package,entry,abi,probes) {return Result {status:6};}
 return Result {plan:p};
}
