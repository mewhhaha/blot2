// Runtime retention follows immutable evaluated captures and frozen source roots.
namespace blot_backend_startup_runtime_reach;
import dictionary;
import support.error;
import support.option;
import support.pooled_map;
import support.pooled_buffer;
import check.core;
import eval.core_eval;
import eval.eval_values;
import reuse.declaration_dependencies;
import .startup_graph;
type Error=blot_error::Error;
type Module=blot_check_core::Module;
type BindingRef=blot_check_core::BindingRef;
type Session=blot_eval_core_eval::Session;
type ValueId=u32;
type Graph=blot_backend_startup_graph::Graph;
struct Origin {unit:u32,node:u32}
struct Result {reached:bool[:],callable_values:ValueId[:] = default<ValueId[:]>(),const_only:blot_support::Option<Origin> =blot_support::Option<Origin>{..}}
struct ClosureKey {unit:u32,catalog:u32}
enum Work {declaration{id:u32},value{id:ValueId}}
reusable[] var reached_runs:bool[>..]=[];
reusable[] var callable_runs:ValueId[>..]=[];
fn deinit(self_:Result&) {if self_.reached.len!=0 {reached_runs.free_slice(self_.reached);}if self_.callable_values.len!=0 {callable_runs.free_slice(self_.callable_values);}self_=Result{reached:[],..};}
struct WorkBuffer {storage:Work[:] = default<Work[:]>(),items:Work[:] = default<Work[:]>(),len:i64=0}
reusable[] var pool_WorkBuffer:Work[>..]=[];
fn push(self_:WorkBuffer&,value:Work)->Error {let error=blot_support_pooled_buffer::push(self_,value,pool_WorkBuffer);self_.len=self_.items.len;return error;}
fn pop(self_:WorkBuffer&)->Work {assert(self_.len>0);let value=self_.items[self_.len-1];blot_support_pooled_buffer::resize(self_,self_.len-1);self_.len=self_.items.len;return value;}
fn deinit(self_:WorkBuffer&) {blot_support_pooled_buffer::deinit(self_,pool_WorkBuffer);self_.len=0;}
struct Values {storage:ValueId[:] = default<ValueId[:]>(),items:ValueId[:] = default<ValueId[:]>(),len:i64=0}
reusable[] var pool_Values:ValueId[>..]=[];
fn push(self_:Values&,value:ValueId)->Error {let error=blot_support_pooled_buffer::push(self_,value,pool_Values);self_.len=self_.items.len;return error;}
fn pop(self_:Values&)->ValueId {assert(self_.len>0);let value=self_.items[self_.len-1];blot_support_pooled_buffer::resize(self_,self_.len-1);self_.len=self_.items.len;return value;}
fn deinit(self_:Values&) {blot_support_pooled_buffer::deinit(self_,pool_Values);self_.len=0;}
struct Ids {table:blot_support_pooled_map::Map<BindingRef,u32> =blot_support_pooled_map::Map<BindingRef,u32>{..}}
reusable[] var pool_Ids:dictionary_slot<BindingRef,u32>[>..]=[];
fn get(self_:const Ids&,key:BindingRef)->u32? {return blot_support_pooled_map::get(self_.table,key);}
fn contains(self_:const Ids&,key:BindingRef)->bool {return blot_support_pooled_map::contains(self_.table,key);}
fn insert(self_:Ids&,key:BindingRef,value:u32) {blot_support_pooled_map::insert(self_.table,key,value,pool_Ids);}
fn deinit(self_:Ids&) {blot_support_pooled_map::deinit(self_.table,pool_Ids);}
struct SeenValues {table:blot_support_pooled_map::Map<ValueId,bool> =blot_support_pooled_map::Map<ValueId,bool>{..}}
reusable[] var pool_SeenValues:dictionary_slot<ValueId,bool>[>..]=[];
fn get(self_:const SeenValues&,key:ValueId)->bool? {return blot_support_pooled_map::get(self_.table,key);}
fn contains(self_:const SeenValues&,key:ValueId)->bool {return blot_support_pooled_map::contains(self_.table,key);}
fn insert(self_:SeenValues&,key:ValueId,value:bool) {blot_support_pooled_map::insert(self_.table,key,value,pool_SeenValues);}
fn deinit(self_:SeenValues&) {blot_support_pooled_map::deinit(self_.table,pool_SeenValues);}
struct SeenClosures {table:blot_support_pooled_map::Map<ClosureKey,bool> =blot_support_pooled_map::Map<ClosureKey,bool>{..}}
reusable[] var pool_SeenClosures:dictionary_slot<ClosureKey,bool>[>..]=[];
fn get(self_:const SeenClosures&,key:ClosureKey)->bool? {return blot_support_pooled_map::get(self_.table,key);}
fn contains(self_:const SeenClosures&,key:ClosureKey)->bool {return blot_support_pooled_map::contains(self_.table,key);}
fn insert(self_:SeenClosures&,key:ClosureKey,value:bool) {blot_support_pooled_map::insert(self_.table,key,value,pool_SeenClosures);}
fn deinit(self_:SeenClosures&) {blot_support_pooled_map::deinit(self_.table,pool_SeenClosures);}
struct Reach {units:const Module[:],declarations:const Graph&,session:Session&,ids:Ids=Ids{..},seen_values:SeenValues=SeenValues{..},seen_closures:SeenClosures=SeenClosures{..},work:WorkBuffer=WorkBuffer{..},callable_values:Values=Values{..},reached:bool[:],const_only:blot_support::Option<Origin> =blot_support::Option<Origin>{..}}
fn deinit(self_:Reach&) {self_.ids.deinit();self_.seen_values.deinit();self_.seen_closures.deinit();self_.work.deinit();self_.callable_values.deinit();}
fn references(self_:Reach&,owner:u32,values:const BindingRef[:])->Error {var index=values.len;while index!=0 {index-=1;let reference,error=blot_backend_startup_graph::normalize(self_.units,owner,values[index]);if error!=blot_error::Error.none {return error;}let id .= self_.ids.get(reference);if !id {return blot_error::Error.invalid_dependency_graph;}let error=self_.work.push(Work.declaration{id:id});if error!=blot_error::Error.none {return error;}}return blot_error::Error.none;}
fn children(self_:Reach&,value:ValueId)->Error {let values=self_.session.valueChildren(value);var index=values.len;while index!=0 {index-=1;let error=self_.work.push(Work.value{id:values[index]});if error!=blot_error::Error.none {return error;}}return blot_error::Error.none;}
fn closure(self_:Reach&,value:ValueId)->Error {let error=self_.callable_values.push(value);if error!=blot_error::Error.none {return error;}let metadata=self_.session.closureInfo(value);match metadata.origin {
 named => {let producer .= self_.units[metadata.unit-1];let body .= producer.body(metadata.identity);if !body {return blot_error::Error.invalid_dependency_graph;}if metadata.applied==0 {let error=self_.references(metadata.unit,[BindingRef{unit:metadata.unit,binding:metadata.identity}]);if error!=blot_error::Error.none {return error;}}else {let parameters=producer.bodyParameters(body);if metadata.applied>parameters.len {return blot_error::Error.invalid_dependency_graph;}var source,error=blot_reuse_declaration_dependencies::expression(producer,body.root);if error!=blot_error::Error.none {return error;}if source.runtime_metadata!=0 {self_.const_only=blot_support::some(Origin{unit:metadata.unit,node:source.runtime_metadata});source.deinit();return blot_error::Error.none;}let error=self_.references(metadata.unit,source.references);source.deinit();if error!=blot_error::Error.none {return error;}let arguments=self_.session.valueChildren(value);if arguments.len!=metadata.applied {return blot_error::Error.invalid_dependency_graph;}for parameter,index in parameters[..metadata.applied] {let used,error=blot_reuse_declaration_dependencies::usesBinding(producer,body.root,parameter.binding);if error!=blot_error::Error.none {return error;}if used {let error=self_.work.push(Work.value{id:arguments[index]});if error!=blot_error::Error.none {return error;}}}return blot_error::Error.none;}},
 anonymous => {if metadata.unit==0 || metadata.unit>self_.units.len {return blot_error::Error.invalid_dependency_graph;}let producer .= self_.units[metadata.unit-1];if metadata.identity>=producer.closures.len {return blot_error::Error.invalid_dependency_graph;}let key=ClosureKey{unit:metadata.unit,catalog:metadata.identity};if !self_.seen_closures.contains(key) {self_.seen_closures.insert(key,true);var source,error=blot_reuse_declaration_dependencies::expression(producer,producer.closures[metadata.identity].body);if error!=blot_error::Error.none {return error;}if source.runtime_metadata!=0 {self_.const_only=blot_support::some(Origin{unit:metadata.unit,node:source.runtime_metadata});source.deinit();return blot_error::Error.none;}let error=self_.references(metadata.unit,source.references);source.deinit();if error!=blot_error::Error.none {return error;}}},
 _ => {},
 }return self_.children(value);}
fn run(self_:Reach&)->Error {while self_.work.len!=0 {let item=self_.work.pop();if self_.const_only.present {return blot_error::Error.none;}match item {
 declaration item => {let id=item.id;if self_.reached[id] {continue;}self_.reached[id]=true;let declaration=self_.declarations.nodes[id];if declaration.is_function || declaration.runtime {let producer .= self_.units[declaration.target.unit-1];let body_id=producer.binding(declaration.target.binding).body_id;let metadata=producer.declaration_dependencies[body_id].runtime_metadata;if metadata!=0 {self_.const_only=blot_support::some(Origin{unit:declaration.target.unit,node:metadata});return blot_error::Error.none;}let range=declaration.references;let edges=self_.declarations.edges[range.start..range.start+range.len];var index=edges.len;while index!=0 {index-=1;let error=self_.work.push(Work.declaration{id:edges[index]});if error!=blot_error::Error.none {return error;}}}else {let value,present,error=self_.session.cachedBindingValue(declaration.target);if error!=blot_error::Error.none {return error;}if !present {return blot_error::Error.invalid_dependency_graph;}let error=self_.work.push(Work.value{id:value});if error!=blot_error::Error.none {return error;}}},
 value item => {let value=item.id;if self_.seen_values.contains(value) {continue;}self_.seen_values.insert(value,true);let kind=self_.session.valueInfo(value).kind;if kind==blot_eval_eval_values::ValueKind.capability {return blot_error::Error.invalid_dependency_graph;}if kind==blot_eval_eval_values::ValueKind.closure {let error=self_.closure(value);if error!=blot_error::Error.none {return error;}}else if kind!=blot_eval_eval_values::ValueKind.descriptor && kind!=blot_eval_eval_values::ValueKind.scalar && kind!=blot_eval_eval_values::ValueKind.type_constructor && kind!=blot_eval_eval_values::ValueKind.resolver && kind!=blot_eval_eval_values::ValueKind.effect_set && kind!=blot_eval_eval_values::ValueKind.effect_descriptor && kind!=blot_eval_eval_values::ValueKind.proof {let error=self_.children(value);if error!=blot_error::Error.none {return error;}}},
 }}return blot_error::Error.none;}
fn collect(units:const Module[:],declarations:const Graph&,session:Session&,selected:const bool[:],entry:u32)->Result,Error {if selected.len!=declarations.nodes.len {return Result{reached:[],..},blot_error::Error.invalid_dependency_graph;}let reached=reached_runs.alloc_slice(selected.len);for &flag in reached {flag=false;}var walk=Reach{units:units,declarations:declarations,session:session,reached:reached,..};for declaration,index in declarations.nodes {walk.ids.insert(declaration.target,index as u32);}for class in [2 as u8,1 as u8,0 as u8] {var index=declarations.nodes.len;while index!=0 {index-=1;let declaration=declarations.nodes[index];if !selected[index] {continue;}var root=false;if class==0 {root=declaration.is_function && declaration.exported && declaration.target.unit==entry;}else if class==1 {root=!declaration.is_function && declaration.runtime;}else {root=!declaration.is_function && !declaration.runtime && declaration.exported && declaration.target.unit==entry;}if root {let error=walk.work.push(Work.declaration{id:index as u32});if error!=blot_error::Error.none {walk.deinit();reached_runs.free_slice(reached);return Result{reached:[],..},error;}}}}let error=walk.run();if error!=blot_error::Error.none {walk.deinit();reached_runs.free_slice(reached);return Result{reached:[],..},error;}let callable_values=callable_runs.alloc_slice(walk.callable_values.len);for value,index in walk.callable_values.items {callable_values[index]=value;}let const_only=walk.const_only;walk.deinit();return Result{reached:reached,callable_values:callable_values,const_only:const_only},blot_error::Error.none;}

fn hash(key:ClosureKey)->u64 {return ::hash_combine(::hash(key.unit),::hash(key.catalog));}
