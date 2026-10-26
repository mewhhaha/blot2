// Private cross-module scalar-call checking. All project graphs must come from
// a fresh trusted descriptor-root read; source/interface bytes are rechecked.
// This is not full K1 semantic admission, import authority, ABI qualification,
// work accounting, filesystem snapshot or executable provenance.
namespace link_check;
import project_graph;
import link_graph_check;
import link_lines;
import link_consumer;
import link_consumer_check;
import link_exports;
import public_frontend;
import public_artifact;
import validate;

struct Probe {alias:u8[]=[],name:u8[]=[]}
// kind 1 import-alias lookup, kind 2 exported-member lookup. All positions
// refer to bounded keys/interfaces pools; negative records have no interface.
struct Observation {kind:u32=0,found:bool=false,alias_start:i64=0,alias_end:i64=0,
 name_start:i64=0,name_end:i64=0,producer_start:i64=0,producer_end:i64=0,interface_start:i64=0,interface_end:i64=0}
struct Snapshot {consumer:u8[]=[],keys:u8[]=[],interfaces:u8[]=[],observations:Observation[]=[],caller_depth:u32=0}
// 0 checked, 1 malformed/unsupported, 2 private bound, 3 missing alias,
// 4 missing public member, 5 call type/resource mismatch, 6 internal failure.
// Failed lookups return observations but no completed caller artifact.
struct Result {status:i64=0,snapshot:Snapshot=Snapshot {}}
fn finish(status:i64,consumer:u8[:],keys:u8[:],interfaces:u8[:],observations:Observation[:],depth:u32) -> Result {
 return Result {status:status,snapshot:Snapshot {consumer:consumer,keys:keys,interfaces:interfaces,observations:observations,caller_depth:depth}};
}
// 0 hit, 3 missing alias, 4 missing member, 2 bound, 6 bad interface.
// Both positive and negative records include exact alias, selected name, and
// when an alias exists, the exact resolved producer path. Interface bytes are
// copied only after fresh source-bound independent decoding.
fn lookup(g:project_graph::Graph&, exports:link_exports::Result&, abi:u8[:], alias:u8[:],name:u8[:],
          keys:u8[>..]&,interfaces:u8[>..]&,observations:Observation[>..]&) -> i64,u32 {
 if alias.len==0 || name.len==0 || alias.len>4096 || name.len>4096 || observations.len>126 ||
    alias.len>524288-keys.len {return 2,0;}
 let a=keys.len;keys.append(alias);let ae=keys.len;
 if name.len>524288-keys.len {return 2,0;}let n=keys.len;keys.append(name);let ne=keys.len;
 var module:i64=-1;
 for e in g.edges {if e.from==0 && g.sources[e.alias_start..e.alias_end]==alias {module=e.to;break;}}
 if module<0 {
  observations.push(Observation {kind:1,alias_start:a,alias_end:ae,name_start:n,name_end:ne});return 3,0;
 }
 let target=g.modules[module];let path=g.paths[target.path_start..target.path_end];
 if path.len>524288-keys.len {return 2,0;}let producer=keys.len;keys.append(path);let producer_end=keys.len;
 observations.push(Observation {kind:1,found:true,alias_start:a,alias_end:ae,name_start:n,name_end:ne,producer_start:producer,producer_end:producer_end});
 var selected:i64=-1;
 for x,i in exports.values {if x.module==module && g.sources[x.name_start..x.name_end]==name {selected=i;break;}}
 if selected<0 {
  observations.push(Observation {kind:2,alias_start:a,alias_end:ae,name_start:n,name_end:ne,producer_start:producer,producer_end:producer_end});return 4,0;
 }
 let item=exports.values[selected];let encoded=exports.interfaces[item.interface_start..item.interface_end];
 let line=g.sources[item.line_start..item.line_end];let candidate=public_frontend::parse(line);
 if candidate.status!=0 || public_artifact::verify_source(encoded,line,candidate,g.package,path,name,abi)!=0 {return 6,0;}
 if encoded.len>1048576-interfaces.len {return 2,0;}
 let start=interfaces.len;interfaces.append(encoded);
 observations.push(Observation {kind:2,found:true,alias_start:a,alias_end:ae,name_start:n,name_end:ne,
   producer_start:producer,producer_end:producer_end,interface_start:start,interface_end:interfaces.len});
 return 0,item.depth;
}
fn check(g:project_graph::Graph&,package:u8[:],entry:u8[:],abi:u8[:],probes:Probe[:]) -> Result {
 if abi.len!=32 || probes.len>32 || !link_graph_check::verify(g,package,entry) {return Result {status:1};}
 let root=g.modules[0];let source=g.sources[root.source_start..root.source_end];
 let lines=link_lines::split(source);if lines.status!=0 || lines.lines.len!=1 {return Result {status:1};}
 let span=lines.lines[0];let line=source[span.start..span.end];
 let call=link_consumer::parse(line);if call.status!=0 || !link_consumer_check::verify(line,call) {return Result {status:1};}
 // Do not admit a declaration that collides with any same-scope import alias.
 // This is a conservative rule until the full K1 namespace model is present.
 for edge in g.edges {
  if edge.from==0 && g.sources[edge.alias_start..edge.alias_end]==line[call.name_start..call.name_end] {return Result {status:1};}
 }
 let exports=link_exports::collect(g,abi);if exports.status!=0 {return Result {status:if exports.status==2 {2} else {1}};}
 var keys:u8[>..]=[];var interfaces:u8[>..]=[];var observations:Observation[>..]=[];
 let alias=line[call.alias_start..call.alias_end];let target=line[call.target_start..call.target_end];
 let status,depth=lookup(g,exports,abi,alias,target,keys,interfaces,observations);
 if status!=0 {return finish(status,source,keys,interfaces,observations,0);}
 // The private caller accepts and returns U32. Check the independently decoded
 // selected interface rather than inferring type from name or a hash.
 let last=observations[observations.len-1];let encoded=interfaces[last.interface_start..last.interface_end];
 let producer=keys[last.producer_start..last.producer_end];
 let decoded=public_artifact::decode(encoded,g.package,producer,target,abi);
 if decoded.status!=0 {return finish(6,source,keys,interfaces,observations,0);}
 if decoded.result_type!=1 || depth>=128 {return finish(5,source,keys,interfaces,observations,0);}
 for probe in probes {
  if probe.alias.len>4096 || probe.name.len>4096 {return finish(2,source,keys,interfaces,observations,0);}
  if !validate::name_valid(probe.alias) || !validate::name_valid(probe.name) {return finish(1,source,keys,interfaces,observations,0);}
  // Probes in this fixture are caller-scoped. A lexical parameter or the
  // caller declaration shadows that spelling regardless of whether an import
  // with the same name exists. Do not record a misleading module lookup.
  if probe.alias[..]==line[call.param_start..call.param_end] || probe.alias[..]==line[call.name_start..call.name_end] {
   return finish(1,source,keys,interfaces,observations,0);
  }
  let observed,_=lookup(g,exports,abi,probe.alias,probe.name,keys,interfaces,observations);
  if observed!=0 && observed!=3 && observed!=4 {return finish(observed,source,keys,interfaces,observations,0);}
 }
 return finish(0,source,keys,interfaces,observations,depth+1);
}
fn same(a:Snapshot&,b:Snapshot&) -> bool {
 return a.consumer[..]==b.consumer[..] && a.keys[..]==b.keys[..] && a.interfaces[..]==b.interfaces[..] &&
  a.observations[..]==b.observations[..] && a.caller_depth==b.caller_depth;
}
