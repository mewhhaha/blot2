// Frozen declaration identity, source-order selection, and exact compact components.
namespace blot_backend_startup_graph;
import dictionary;
import support.error;
import support.option;
import support.pooled_buffer;
import check.core;
import check.types;
import .optimizer_buffers;
type Error=blot_error::Error;
type Id=u32;
type BindingRef=blot_check_core::BindingRef;
type List=blot_check_core::List;
type Module=blot_check_core::Module;
type Words=blot_backend_optimizer_buffers::Words;
let none:u32=0xffffffff;
struct Declaration {target:BindingRef,references:const BindingRef[:],candidates:const BindingRef[:]=[],is_function:bool=false,runtime:bool=false,exported:bool=false}
struct Selection {source:BindingRef,target:BindingRef}
struct Node {target:BindingRef,references:List,candidates:List,is_function:bool,runtime:bool,exported:bool}
struct Plan {initializers:BindingRef[:]=[],cycle:blot_support::Option<BindingRef>=blot_support::Option<BindingRef>{..}}
struct Graph {nodes:Node[:]=[],edges:Id[:]=[]}
reusable[] var node_runs:Node[>..]=[];
reusable[] var id_runs:Id[>..]=[];
reusable[] var binding_runs:BindingRef[>..]=[];
reusable[] var flag_runs:bool[>..]=[];
reusable[] var list_runs:List[>..]=[];
fn deinit(self:Plan&) {if self.initializers.len!=0 {binding_runs.free_slice(self.initializers);}self=Plan{..};}
fn deinit(self:Graph&) {if self.nodes.len!=0 {node_runs.free_slice(self.nodes);}if self.edges.len!=0 {id_runs.free_slice(self.edges);}self=Graph{..};}
fn release(selected:bool[:]) {if selected.len!=0 {flag_runs.free_slice(selected);}}
fn list(self:const Graph&,range:List)->const Id[:] {return self.edges[range.start..range.start+range.len];}
fn init(declarations:const Declaration[:])->Graph,Error {
 if declarations.len>=none {return Graph{..},Error.invalid_dependency_graph;}
 var ids:dictionary<BindingRef,Id>=dictionary{};
 for declaration,index in declarations {if declaration.target.unit==0 || declaration.target.binding==0 || ::contains(ids,declaration.target) {return Graph{..},Error.invalid_dependency_graph;}::insert(ids,declaration.target,index as Id);}
 let nodes=node_runs.alloc_slice(declarations.len);var edges:Id[>..]=[];
 for declaration,index in declarations {let start=edges.len;for reference in declaration.references {let id .= ::get(ids,reference);if !id {node_runs.free_slice(nodes);return Graph{..},Error.invalid_dependency_graph;}edges.push(id);}let candidate_start=edges.len;for candidate in declaration.candidates {let id .= ::get(ids,candidate);if !id {node_runs.free_slice(nodes);return Graph{..},Error.invalid_dependency_graph;}edges.push(id);}if edges.len>none {node_runs.free_slice(nodes);return Graph{..},Error.invalid_dependency_graph;}nodes[index]=Node{target:declaration.target,references:List{start:start as u32,len:(candidate_start-start) as u32},candidates:List{start:candidate_start as u32,len:(edges.len-candidate_start) as u32},is_function:declaration.is_function,runtime:declaration.runtime,exported:declaration.exported};}
 let owned=id_runs.alloc_slice(edges.len);for edge,index in edges {owned[index]=edge;}return Graph{nodes:nodes,edges:owned},Error.none;
}
fn select(self:const Graph&,entry:u32)->bool[:],Error {let selected=flag_runs.alloc_slice(self.nodes.len);for &value in selected {value=false;}var work:Id[>..]=[];for node,index in self.nodes {if node.exported && node.target.unit==entry {work.push(index as Id);}}while work.len!=0 {let id=work[work.len-1];work.resize(work.len-1);if selected[id] {continue;}selected[id]=true;let node=self.nodes[id];work.append(self.list(node.references));work.append(self.list(node.candidates));}return selected,Error.none;}
struct Event {id:Id,leave:bool=false}
fn plan(self:const Graph&,reached:const bool[:])->Plan,Error {return planMode(self,reached,false);}
fn orderAfterStrongProof(self:const Graph&,reached:const bool[:])->Plan,Error {return planMode(self,reached,true);}
fn planMode(self:const Graph&,reached:const bool[:],weak_components_allowed:bool)->Plan,Error {
 if reached.len!=self.nodes.len {return Plan{..},Error.invalid_dependency_graph;}
 var incoming:List[>..]=[];incoming.resize(self.nodes.len,List{..});var edge_count:i64=0;
 for node,index in self.nodes {if reached[index] {for target in self.list(node.references) {if reached[target] {incoming[target].len+=1;edge_count+=1;}}}}
 if edge_count>none {return Plan{..},Error.invalid_dependency_graph;}var start:u32=0;for &range in incoming {range.start=start;start+=range.len;}
 var reverse:Id[>..]=[];reverse.resize(edge_count,0 as Id);
 for node,index in self.nodes {if reached[index] {for target in self.list(node.references) {if reached[target] {incoming[target].len-=1;reverse[incoming[target].start+incoming[target].len]=index as Id;}}}}
 for &range,index in incoming {var end=edge_count as u32;if index+1<incoming.len {end=incoming[index+1].start;}range.len=end-range.start;}
 var seen:bool[>..]=[];seen.resize(self.nodes.len,false);var pending:Event[>..]=[];var finished:Id[>..]=[];
 for node,index in self.nodes {if !reached[index] {continue;}pending.push(Event{id:index as Id,..});while pending.len!=0 {let event=pending[pending.len-1];pending.resize(pending.len-1);if event.leave {finished.push(event.id);continue;}if seen[event.id] {continue;}seen[event.id]=true;pending.push(Event{id:event.id,leave:true});let range=incoming[event.id];var j=range.len as i64;while j!=0 {j-=1;pending.push(Event{id:reverse[range.start+j],..});}}}
 for &value in seen {value=false;}var members:Id[>..]=[];var initializers:BindingRef[>..]=[];var position=finished.len;
 while position!=0 {position-=1;let root=finished[position];if seen[root] {continue;}members.clear();pending.push(Event{id:root,..});while pending.len!=0 {let event=pending[pending.len-1];pending.resize(pending.len-1);if seen[event.id] {continue;}seen[event.id]=true;members.push(event.id);let neighbors=self.list(self.nodes[event.id].references);var j=neighbors.len;while j!=0 {j-=1;if reached[neighbors[j]] {pending.push(Event{id:neighbors[j],..});}}}var cyclic=members.len>1;if !cyclic {for target in self.list(self.nodes[root].references) {if target==root {cyclic=true;break;}}}var j=members.len;while j!=0 {j-=1;let node=self.nodes[members[j]];if !node.runtime || node.is_function {continue;}if cyclic && !weak_components_allowed {return Plan{cycle:blot_support::some(node.target),..},Error.none;}initializers.push(node.target);}}
 let owned=binding_runs.alloc_slice(initializers.len);for value,index in initializers {owned[index]=value;}return Plan{initializers:owned,..},Error.none;
}
fn normalize(units:const Module[:],owner:u32,raw:BindingRef)->BindingRef,Error {var target=raw;if target.unit==0 {target.unit=owner;}var remaining:i64=1;for unit in units {remaining+=unit.bindings.len;}while remaining!=0 {remaining-=1;if target.unit==0 || target.unit>units.len || target.binding==0 {return BindingRef{..},Error.invalid_dependency_graph;}let module .= units[target.unit-1];if target.binding>=module.bindings.len {return BindingRef{..},Error.invalid_dependency_graph;}let binding=module.binding(target.binding);if binding.kind!=blot_check_core::BindingKind.external {if binding.kind!=blot_check_core::BindingKind.global || module.body(target.binding)==null {return BindingRef{..},Error.invalid_dependency_graph;}return target,Error.none;}var unit=binding.target.unit;if unit==0 {unit=target.unit;}target=BindingRef{unit:unit,binding:binding.target.binding};}return BindingRef{..},Error.invalid_dependency_graph;}
struct Ranges {references:List,candidates:List}
fn fromCore(units:const Module[:],unit_order:const u32[:])->Graph,Error {return fromCoreWithSelections(units,unit_order,[]);}
fn fromCoreWithSelections(units:const Module[:],unit_order:const u32[:],selections:const Selection[:])->Graph,Error {
 if unit_order.len!=units.len {return Graph{..},Error.invalid_dependency_graph;}var seen:bool[>..]=[];seen.resize(units.len,false);for unit in unit_order {if unit==0 || unit>units.len || seen[unit-1] {return Graph{..},Error.invalid_dependency_graph;}seen[unit-1]=true;if units[unit-1].declaration_dependencies.len!=units[unit-1].bodies.len {return Graph{..},Error.invalid_dependency_graph;}}
 var declarations:Declaration[>..]=[];var owned_references:BindingRef[>..]=[];var owned_candidates:BindingRef[>..]=[];var ranges:Ranges[>..]=[];
 for functions in [true,false] {for unit in unit_order {let module .= units[unit-1];for body,index in module.bodies[1..] {if body.is_function!=functions {continue;}let source=module.declaration_dependencies[index+1];let ref_start=owned_references.len;for reference in module.dependency_references[source.references.start..source.references.start+source.references.len] {let target,error=normalize(units,unit,reference);if error!=Error.none {return Graph{..},error;}owned_references.push(target);}for selection in selections {if selection.source.unit==unit && selection.source.binding==body.binding {let target,error=normalize(units,unit,selection.target);if error!=Error.none {return Graph{..},error;}owned_references.push(target);}}let candidate_start=owned_candidates.len;for member in module.dependency_members[source.members.start..source.members.start+source.members.len] {for candidate_module,u in units {for candidate in candidate_module.associated {var matches=member.operator!=blot_check_types::Operator.none && member.operator==candidate.operator;if member.name!=0 {matches=member.name==candidate.member;}if matches {let target,error=normalize(units,(u+1) as u32,candidate.target);if error!=Error.none {return Graph{..},error;}owned_candidates.push(target);}}}}if owned_references.len>none || owned_candidates.len>none {return Graph{..},Error.invalid_dependency_graph;}ranges.push(Ranges{references:List{start:ref_start as u32,len:(owned_references.len-ref_start) as u32},candidates:List{start:candidate_start as u32,len:(owned_candidates.len-candidate_start) as u32}});declarations.push(Declaration{target:BindingRef{unit:unit,binding:body.binding},references:[],is_function:body.is_function,runtime:body.runtime,exported:body.exported,..});}}}
 for &declaration,index in declarations {let range=ranges[index];declaration.references=owned_references[range.references.start..range.references.start+range.references.len];declaration.candidates=owned_candidates[range.candidates.start..range.candidates.start+range.candidates.len];}return init(declarations);
}
