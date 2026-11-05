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
struct Result {reached:bool[:],callable_values:ValueId[:]=[],const_only:blot_support::Option<Origin>=blot_support::Option<Origin>{..}}
struct ClosureKey {unit:u32,catalog:u32}
enum Work {declaration{id:u32},value{id:ValueId}}
reusable[] var reached_runs:bool[>..]=[];
reusable[] var callable_runs:ValueId[>..]=[];
fn deinit(self:Result&) {if self.reached.len!=0 {reached_runs.free_slice(self.reached);}if self.callable_values.len!=0 {callable_runs.free_slice(self.callable_values);}self=Result{reached:[],..};}
struct WorkBuffer {storage:Work[:]=[],items:Work[:]=[],len:i64=0}
reusable[] var pool_WorkBuffer:Work[>..]=[];
fn push(self:WorkBuffer&,value:Work)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_WorkBuffer);self.len=self.items.len;return error;}
fn pop(self:WorkBuffer&)->Work {assert(self.len>0);let value=self.items[self.len-1];blot_support_pooled_buffer::resize(self,self.len-1);self.len=self.items.len;return value;}
fn deinit(self:WorkBuffer&) {blot_support_pooled_buffer::deinit(self,pool_WorkBuffer);self.len=0;}
struct Values {storage:ValueId[:]=[],items:ValueId[:]=[],len:i64=0}
reusable[] var pool_Values:ValueId[>..]=[];
fn push(self:Values&,value:ValueId)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Values);self.len=self.items.len;return error;}
fn pop(self:Values&)->ValueId {assert(self.len>0);let value=self.items[self.len-1];blot_support_pooled_buffer::resize(self,self.len-1);self.len=self.items.len;return value;}
fn deinit(self:Values&) {blot_support_pooled_buffer::deinit(self,pool_Values);self.len=0;}
struct Ids {table:blot_support_pooled_map::Map<BindingRef,u32>=blot_support_pooled_map::Map<BindingRef,u32>{..}}
reusable[] var pool_Ids:dictionary_slot<BindingRef,u32>[>..]=[];
fn get(self:const Ids&,key:BindingRef)->u32? {return blot_support_pooled_map::get(self.table,key);}
fn contains(self:const Ids&,key:BindingRef)->bool {return blot_support_pooled_map::contains(self.table,key);}
fn insert(self:Ids&,key:BindingRef,value:u32) {blot_support_pooled_map::insert(self.table,key,value,pool_Ids);}
fn deinit(self:Ids&) {blot_support_pooled_map::deinit(self.table,pool_Ids);}
struct SeenValues {table:blot_support_pooled_map::Map<ValueId,bool>=blot_support_pooled_map::Map<ValueId,bool>{..}}
reusable[] var pool_SeenValues:dictionary_slot<ValueId,bool>[>..]=[];
fn get(self:const SeenValues&,key:ValueId)->bool? {return blot_support_pooled_map::get(self.table,key);}
fn contains(self:const SeenValues&,key:ValueId)->bool {return blot_support_pooled_map::contains(self.table,key);}
fn insert(self:SeenValues&,key:ValueId,value:bool) {blot_support_pooled_map::insert(self.table,key,value,pool_SeenValues);}
fn deinit(self:SeenValues&) {blot_support_pooled_map::deinit(self.table,pool_SeenValues);}
struct SeenClosures {table:blot_support_pooled_map::Map<ClosureKey,bool>=blot_support_pooled_map::Map<ClosureKey,bool>{..}}
reusable[] var pool_SeenClosures:dictionary_slot<ClosureKey,bool>[>..]=[];
fn get(self:const SeenClosures&,key:ClosureKey)->bool? {return blot_support_pooled_map::get(self.table,key);}
fn contains(self:const SeenClosures&,key:ClosureKey)->bool {return blot_support_pooled_map::contains(self.table,key);}
fn insert(self:SeenClosures&,key:ClosureKey,value:bool) {blot_support_pooled_map::insert(self.table,key,value,pool_SeenClosures);}
fn deinit(self:SeenClosures&) {blot_support_pooled_map::deinit(self.table,pool_SeenClosures);}
struct Reach {units:const Module[:],declarations:const Graph&,session:Session&,ids:Ids=Ids{..},seen_values:SeenValues=SeenValues{..},seen_closures:SeenClosures=SeenClosures{..},work:WorkBuffer=WorkBuffer{..},callable_values:Values=Values{..},reached:bool[:],const_only:blot_support::Option<Origin>=blot_support::Option<Origin>{..}}
fn deinit(self:Reach&) {self.ids.deinit();self.seen_values.deinit();self.seen_closures.deinit();self.work.deinit();self.callable_values.deinit();}
fn references(self:Reach&,owner:u32,values:const BindingRef[:])->Error {var index=values.len;while index!=0 {index-=1;let reference,error=blot_backend_startup_graph::normalize(self.units,owner,values[index]);if error!=Error.none {return error;}let id .= self.ids.get(reference);if !id {return Error.invalid_dependency_graph;}let error=self.work.push(Work.declaration{id:id});if error!=Error.none {return error;}}return Error.none;}
fn children(self:Reach&,value:ValueId)->Error {let values=self.session.valueChildren(value);var index=values.len;while index!=0 {index-=1;let error=self.work.push(Work.value{id:values[index]});if error!=Error.none {return error;}}return Error.none;}
fn closure(self:Reach&,value:ValueId)->Error {let error=self.callable_values.push(value);if error!=Error.none {return error;}let metadata=self.session.closureInfo(value);match metadata.origin {
 blot_eval_eval_values::ClosureOrigin.named => {let producer .= self.units[metadata.unit-1];let body .= producer.body(metadata.identity);if !body {return Error.invalid_dependency_graph;}if metadata.applied==0 {let error=self.references(metadata.unit,[BindingRef{unit:metadata.unit,binding:metadata.identity}]);if error!=Error.none {return error;}}else {let parameters=producer.bodyParameters(body);if metadata.applied>parameters.len {return Error.invalid_dependency_graph;}var source,error=blot_reuse_declaration_dependencies::expression(producer,body.root);if error!=Error.none {return error;}if source.runtime_metadata!=0 {self.const_only=blot_support::some(Origin{unit:metadata.unit,node:source.runtime_metadata});source.deinit();return Error.none;}let error=self.references(metadata.unit,source.references);source.deinit();if error!=Error.none {return error;}let arguments=self.session.valueChildren(value);if arguments.len!=metadata.applied {return Error.invalid_dependency_graph;}for parameter,index in parameters[..metadata.applied] {let used,error=blot_reuse_declaration_dependencies::usesBinding(producer,body.root,parameter.binding);if error!=Error.none {return error;}if used {let error=self.work.push(Work.value{id:arguments[index]});if error!=Error.none {return error;}}}return Error.none;}},
 blot_eval_eval_values::ClosureOrigin.anonymous => {if metadata.unit==0 || metadata.unit>self.units.len {return Error.invalid_dependency_graph;}let producer .= self.units[metadata.unit-1];if metadata.identity>=producer.closures.len {return Error.invalid_dependency_graph;}let key=ClosureKey{unit:metadata.unit,catalog:metadata.identity};if !self.seen_closures.contains(key) {self.seen_closures.insert(key,true);var source,error=blot_reuse_declaration_dependencies::expression(producer,producer.closures[metadata.identity].body);if error!=Error.none {return error;}if source.runtime_metadata!=0 {self.const_only=blot_support::some(Origin{unit:metadata.unit,node:source.runtime_metadata});source.deinit();return Error.none;}let error=self.references(metadata.unit,source.references);source.deinit();if error!=Error.none {return error;}}},
 _ => {},
 }return self.children(value);}
fn run(self:Reach&)->Error {while self.work.len!=0 {let item=self.work.pop();if self.const_only.present {return Error.none;}match item {
 Work.declaration item => {let id=item.id;if self.reached[id] {continue;}self.reached[id]=true;let declaration=self.declarations.nodes[id];if declaration.is_function || declaration.runtime {let producer .= self.units[declaration.target.unit-1];let body_id=producer.binding(declaration.target.binding).body_id;let metadata=producer.declaration_dependencies[body_id].runtime_metadata;if metadata!=0 {self.const_only=blot_support::some(Origin{unit:declaration.target.unit,node:metadata});return Error.none;}let range=declaration.references;let edges=self.declarations.edges[range.start..range.start+range.len];var index=edges.len;while index!=0 {index-=1;let error=self.work.push(Work.declaration{id:edges[index]});if error!=Error.none {return error;}}}else {let value,present,error=self.session.cachedBindingValue(declaration.target);if error!=Error.none {return error;}if !present {return Error.invalid_dependency_graph;}let error=self.work.push(Work.value{id:value});if error!=Error.none {return error;}}},
 Work.value item => {let value=item.id;if self.seen_values.contains(value) {continue;}self.seen_values.insert(value,true);let kind=self.session.valueInfo(value).kind;if kind==blot_eval_eval_values::ValueKind.capability {return Error.invalid_dependency_graph;}if kind==blot_eval_eval_values::ValueKind.closure {let error=self.closure(value);if error!=Error.none {return error;}}else if kind!=blot_eval_eval_values::ValueKind.descriptor && kind!=blot_eval_eval_values::ValueKind.scalar && kind!=blot_eval_eval_values::ValueKind.type_constructor && kind!=blot_eval_eval_values::ValueKind.resolver && kind!=blot_eval_eval_values::ValueKind.effect_set && kind!=blot_eval_eval_values::ValueKind.effect_descriptor && kind!=blot_eval_eval_values::ValueKind.proof {let error=self.children(value);if error!=Error.none {return error;}}},
 }}return Error.none;}
fn collect(units:const Module[:],declarations:const Graph&,session:Session&,selected:const bool[:],entry:u32)->Result,Error {if selected.len!=declarations.nodes.len {return Result{reached:[],..},Error.invalid_dependency_graph;}let reached=reached_runs.alloc_slice(selected.len);for &flag in reached {flag=false;}var walk=Reach{units:units,declarations:declarations,session:session,reached:reached,..};for declaration,index in declarations.nodes {walk.ids.insert(declaration.target,index as u32);}for class in [2 as u8,1 as u8,0 as u8] {var index=declarations.nodes.len;while index!=0 {index-=1;let declaration=declarations.nodes[index];if !selected[index] {continue;}var root=false;if class==0 {root=declaration.is_function && declaration.exported && declaration.target.unit==entry;}else if class==1 {root=!declaration.is_function && declaration.runtime;}else {root=!declaration.is_function && !declaration.runtime && declaration.exported && declaration.target.unit==entry;}if root {let error=walk.work.push(Work.declaration{id:index as u32});if error!=Error.none {walk.deinit();reached_runs.free_slice(reached);return Result{reached:[],..},error;}}}}let error=walk.run();if error!=Error.none {walk.deinit();reached_runs.free_slice(reached);return Result{reached:[],..},error;}let callable_values=callable_runs.alloc_slice(walk.callable_values.len);for value,index in walk.callable_values.items {callable_values[index]=value;}let const_only=walk.const_only;walk.deinit();return Result{reached:reached,callable_values:callable_values,const_only:const_only},Error.none;}
