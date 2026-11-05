// Ownership summaries and edge liveness over symbolic Wasm.
namespace blot_backend_wasm_lifetimes;
import .wasm;
import .runtime_ir;
import .wasm_control_flow;
import support.error;
import support.option;
struct Parameter {escapes:bool=true,bytes:u32=0}
import std;
import dictionary;
import support.pooled_buffer;
import support.pooled_map;
import support.native;
import .provider_modes;
import runtime.runtime_layout;
type Error=blot_error::Error;
type Module=blot_backend_wasm::Module;
type Function=blot_backend_runtime_ir::Function;
type Instruction=blot_backend_runtime_ir::Instruction;
type Op=blot_backend_runtime_ir::Op;
type ValueType=blot_backend_runtime_ir::ValueType;
type Mode=blot_backend_provider_modes::Mode;
type Output=blot_backend_runtime_ir::DetachedBody;
let absent:u32=0xffffffff;
let reference_check_limit:i64=262144;
let summary_depth_limit:u32=128;
let proof_scratch_bytes:i64=4096;
struct Value {owner:u32=0,offset:u32=0,constant:blot_support::Option<u32>=blot_support::none<u32>(),region:u32=0,scope:u32=0}
struct Allocation {size:u32,region:u32,last_region:u32,definition:u32,last:u32,local:u32=absent,uses:u32=absent,required:u32=0,escaped:bool=false,parameter:bool=false,returned:bool=false,segment:u32=0,references:u32=absent,accesses:u32=absent,annotations:u32=absent,annotation_count:u32=0,rc_mask:blot_support::Option<u32>=blot_support::none<u32>()}
struct Use {at:u32,previous:u32}
struct Reference {parent:u32,child:Value,offset:u32,at:u32,scope:u32,region:u32,previous:u32}
enum AccessKind {read,write}
struct Access {offset:u32,bytes:u32,at:u32,previous:u32,kind:AccessKind,reference:u32=absent}
struct Control {height:i64,result:bool,identity:u32}
struct Group {parent:u32,first:u32=absent,next:u32=absent}
enum Edge {after,before,when_true,when_false}
struct Release {after:u32,local:u32,edge:Edge=Edge.after}
enum SummaryPhase {unseen,active,done}
struct Summary {parameters:Parameter[:]=[],invalidates:bool=true,owned_result_bytes:blot_support::Option<u32>=blot_support::none<u32>(),state:SummaryPhase=SummaryPhase.unseen}
enum AnalysisMode {temporaries,parameters}
enum RcWriteKind {word,float_word,copy}
struct RcWrite {at:u32,owner:u32,kind:RcWriteKind}
struct RcAllocation {at:u32,mask:u32}
struct RcPublication {at:u32,local:u32,kind:RcWriteKind}
struct Values {storage:Value[:]=[],items:Value[:]=[],len:i64=0}
reusable[] var pool_Values:Value[>..]=[];
fn ensure(self:Values&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Values);}
fn push(self:Values&,value:Value)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Values);self.len=self.items.len;return error;}
fn append(self:Values&,values:const Value[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Values);self.len=self.items.len;return error;}
fn resize(self:Values&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn pop(self:Values&)->Value {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Values&) {self.resize(0);}
fn deinit(self:Values&) {blot_support_pooled_buffer::deinit(self,pool_Values);self.len=0;}
struct Allocations {storage:Allocation[:]=[],items:Allocation[:]=[],len:i64=0}
reusable[] var pool_Allocations:Allocation[>..]=[];
fn ensure(self:Allocations&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Allocations);}
fn push(self:Allocations&,value:Allocation)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Allocations);self.len=self.items.len;return error;}
fn append(self:Allocations&,values:const Allocation[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Allocations);self.len=self.items.len;return error;}
fn resize(self:Allocations&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn pop(self:Allocations&)->Allocation {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Allocations&) {self.resize(0);}
fn deinit(self:Allocations&) {blot_support_pooled_buffer::deinit(self,pool_Allocations);self.len=0;}
struct Uses {storage:Use[:]=[],items:Use[:]=[],len:i64=0}
reusable[] var pool_Uses:Use[>..]=[];
fn ensure(self:Uses&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Uses);}
fn push(self:Uses&,value:Use)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Uses);self.len=self.items.len;return error;}
fn append(self:Uses&,values:const Use[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Uses);self.len=self.items.len;return error;}
fn resize(self:Uses&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn pop(self:Uses&)->Use {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Uses&) {self.resize(0);}
fn deinit(self:Uses&) {blot_support_pooled_buffer::deinit(self,pool_Uses);self.len=0;}
struct Controls {storage:Control[:]=[],items:Control[:]=[],len:i64=0}
reusable[] var pool_Controls:Control[>..]=[];
fn ensure(self:Controls&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Controls);}
fn push(self:Controls&,value:Control)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Controls);self.len=self.items.len;return error;}
fn append(self:Controls&,values:const Control[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Controls);self.len=self.items.len;return error;}
fn resize(self:Controls&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn pop(self:Controls&)->Control {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Controls&) {self.resize(0);}
fn deinit(self:Controls&) {blot_support_pooled_buffer::deinit(self,pool_Controls);self.len=0;}
struct References {storage:Reference[:]=[],items:Reference[:]=[],len:i64=0}
reusable[] var pool_References:Reference[>..]=[];
fn ensure(self:References&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_References);}
fn push(self:References&,value:Reference)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_References);self.len=self.items.len;return error;}
fn append(self:References&,values:const Reference[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_References);self.len=self.items.len;return error;}
fn resize(self:References&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn pop(self:References&)->Reference {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:References&) {self.resize(0);}
fn deinit(self:References&) {blot_support_pooled_buffer::deinit(self,pool_References);self.len=0;}
struct Accesses {storage:Access[:]=[],items:Access[:]=[],len:i64=0}
reusable[] var pool_Accesses:Access[>..]=[];
fn ensure(self:Accesses&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Accesses);}
fn push(self:Accesses&,value:Access)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Accesses);self.len=self.items.len;return error;}
fn append(self:Accesses&,values:const Access[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Accesses);self.len=self.items.len;return error;}
fn resize(self:Accesses&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn pop(self:Accesses&)->Access {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Accesses&) {self.resize(0);}
fn deinit(self:Accesses&) {blot_support_pooled_buffer::deinit(self,pool_Accesses);self.len=0;}
struct RcWrites {storage:RcWrite[:]=[],items:RcWrite[:]=[],len:i64=0}
reusable[] var pool_RcWrites:RcWrite[>..]=[];
fn ensure(self:RcWrites&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_RcWrites);}
fn push(self:RcWrites&,value:RcWrite)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_RcWrites);self.len=self.items.len;return error;}
fn append(self:RcWrites&,values:const RcWrite[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_RcWrites);self.len=self.items.len;return error;}
fn resize(self:RcWrites&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn pop(self:RcWrites&)->RcWrite {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:RcWrites&) {self.resize(0);}
fn deinit(self:RcWrites&) {blot_support_pooled_buffer::deinit(self,pool_RcWrites);self.len=0;}
struct Releases {storage:Release[:]=[],items:Release[:]=[],len:i64=0}
reusable[] var pool_Releases:Release[>..]=[];
fn ensure(self:Releases&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Releases);}
fn push(self:Releases&,value:Release)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Releases);self.len=self.items.len;return error;}
fn append(self:Releases&,values:const Release[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Releases);self.len=self.items.len;return error;}
fn resize(self:Releases&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn pop(self:Releases&)->Release {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Releases&) {self.resize(0);}
fn deinit(self:Releases&) {blot_support_pooled_buffer::deinit(self,pool_Releases);self.len=0;}
struct RcAllocations {storage:RcAllocation[:]=[],items:RcAllocation[:]=[],len:i64=0}
reusable[] var pool_RcAllocations:RcAllocation[>..]=[];
fn ensure(self:RcAllocations&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_RcAllocations);}
fn push(self:RcAllocations&,value:RcAllocation)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_RcAllocations);self.len=self.items.len;return error;}
fn append(self:RcAllocations&,values:const RcAllocation[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_RcAllocations);self.len=self.items.len;return error;}
fn resize(self:RcAllocations&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn pop(self:RcAllocations&)->RcAllocation {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:RcAllocations&) {self.resize(0);}
fn deinit(self:RcAllocations&) {blot_support_pooled_buffer::deinit(self,pool_RcAllocations);self.len=0;}
struct RcPublications {storage:RcPublication[:]=[],items:RcPublication[:]=[],len:i64=0}
reusable[] var pool_RcPublications:RcPublication[>..]=[];
fn ensure(self:RcPublications&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_RcPublications);}
fn push(self:RcPublications&,value:RcPublication)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_RcPublications);self.len=self.items.len;return error;}
fn append(self:RcPublications&,values:const RcPublication[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_RcPublications);self.len=self.items.len;return error;}
fn resize(self:RcPublications&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn pop(self:RcPublications&)->RcPublication {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:RcPublications&) {self.resize(0);}
fn deinit(self:RcPublications&) {blot_support_pooled_buffer::deinit(self,pool_RcPublications);self.len=0;}
struct Words {storage:u32[:]=[],items:u32[:]=[],len:i64=0}
reusable[] var pool_Words:u32[>..]=[];
fn ensure(self:Words&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Words);}
fn push(self:Words&,value:u32)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Words);self.len=self.items.len;return error;}
fn append(self:Words&,values:const u32[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Words);self.len=self.items.len;return error;}
fn resize(self:Words&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn pop(self:Words&)->u32 {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Words&) {self.resize(0);}
fn deinit(self:Words&) {blot_support_pooled_buffer::deinit(self,pool_Words);self.len=0;}
struct Code {storage:Instruction[:]=[],items:Instruction[:]=[],len:i64=0}
reusable[] var pool_Code:Instruction[>..]=[];
fn ensure(self:Code&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Code);}
fn push(self:Code&,value:Instruction)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Code);self.len=self.items.len;return error;}
fn append(self:Code&,values:const Instruction[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_Code);self.len=self.items.len;return error;}
fn resize(self:Code&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn pop(self:Code&)->Instruction {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:Code&) {self.resize(0);}
fn deinit(self:Code&) {blot_support_pooled_buffer::deinit(self,pool_Code);self.len=0;}
struct MachineTypes {storage:ValueType[:]=[],items:ValueType[:]=[],len:i64=0}
reusable[] var pool_MachineTypes:ValueType[>..]=[];
fn ensure(self:MachineTypes&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_MachineTypes);}
fn push(self:MachineTypes&,value:ValueType)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_MachineTypes);self.len=self.items.len;return error;}
fn append(self:MachineTypes&,values:const ValueType[:])->Error {let error=blot_support_pooled_buffer::append(self,values,pool_MachineTypes);self.len=self.items.len;return error;}
fn resize(self:MachineTypes&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn pop(self:MachineTypes&)->ValueType {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn clear(self:MachineTypes&) {self.resize(0);}
fn deinit(self:MachineTypes&) {blot_support_pooled_buffer::deinit(self,pool_MachineTypes);self.len=0;}
struct Plan {releases:Releases=Releases{..}}
fn deinit(self:Plan&) {self.releases.deinit();}
struct RcPlan {admitted:bool=true,allocations:RcAllocations=RcAllocations{..},writes:RcPublications=RcPublications{..}}
fn deinit(self:RcPlan&) {self.allocations.deinit();self.writes.deinit();}
struct FieldMap {table:blot_support_pooled_map::Map<u64,u32>=blot_support_pooled_map::Map<u64,u32>{..}}
reusable[] var field_slots:dictionary_slot<u64,u32>[>..]=[];
fn get(self:const FieldMap&,key:u64)->u32? {return blot_support_pooled_map::get(self.table,key);}
fn insert(self:FieldMap&,key:u64,value:u32) {blot_support_pooled_map::insert(self.table,key,value,field_slots);}
fn deinit(self:FieldMap&) {blot_support_pooled_map::deinit(self.table,field_slots);}
struct SummaryState {module:const Module?=null,providers:Mode[:]=[],functions:Summary[:]=[],parameters:Parameter[:]=[],depth:u32=0,prepared:bool=false,role_conflicts:i64=0,generation:u64=0,live:bool=false}
var inactive_summaries:SummaryState=SummaryState{..};
reusable var summary_states:SummaryState[>..]=[];
reusable[] var summary_runs:Summary[>..]=[];
reusable[] var parameter_runs:Parameter[>..]=[];
reusable[] var provider_runs:Mode[>..]=[];
struct Summaries {slot:u32=0,generation:u64=0,functions:Summary[:]&=inactive_summaries.functions,parameters:Parameter[:]&=inactive_summaries.parameters,providers:Mode[:]&=inactive_summaries.providers,depth:u32&=inactive_summaries.depth,prepared:bool&=inactive_summaries.prepared,role_conflicts:i64&=inactive_summaries.role_conflicts}
fn valid(self:const Summaries&)->bool {return self.slot!=0 && self.slot<=summary_states.len && summary_states[self.slot-1].live && summary_states[self.slot-1].generation==self.generation;}
fn module(self:const Summaries&)->const Module& {assert(self.valid());let module .= summary_states[self.slot-1].module;assert(module);return module;}
fn initSummaries(module:const Module&)->Summaries,Error {var count:i64=0;for function in module.functions {if function.parameters.len>0x7fffffffffffffff-count {return Summaries{..},Error.out_of_memory;}count+=function.parameters.len;}let functions=summary_runs.alloc_slice(module.functions.len);let parameters=parameter_runs.alloc_slice(count);for &parameter in parameters {parameter=Parameter{..};}var start:i64=0;for function,index in module.functions {functions[index]=Summary{parameters:parameters[start..start+function.parameters.len],..};start+=function.parameters.len;}let generation=blot_native::fresh_owner_id();let at=summary_states.alloc_index(SummaryState{module:module,functions:functions,parameters:parameters,generation:generation,live:true,..});let state .= summary_states[at];return Summaries{slot:(at+1) as u32,generation:generation,functions:state.functions,parameters:state.parameters,providers:state.providers,depth:state.depth,prepared:state.prepared,role_conflicts:state.role_conflicts,..},Error.none;}
fn init(module:const Module&)->Summaries,Error {return initSummaries(module);}
fn setProviders(self:Summaries&,providers:const Mode[:])->Error {assert(self.valid());let copy=provider_runs.alloc_slice(providers.len);for value,index in providers {copy[index]=value;}if self.providers.len!=0 {provider_runs.free_slice(self.providers);}self.providers=copy;return Error.none;}
fn deinit(self:Summaries&) {if self.slot==0 {return;}assert(self.valid());if self.parameters.len!=0 {parameter_runs.free_slice(self.parameters);}if self.functions.len!=0 {summary_runs.free_slice(self.functions);}if self.providers.len!=0 {provider_runs.free_slice(self.providers);}let at=self.slot-1;summary_states[at].live=false;summary_states.free(at);self=Summaries{..};}
fn prepare(self:const Summaries&)->Error {assert(self.valid());if self.prepared {return Error.none;}if self.module().arena.present {for id in 0..self.functions.len {let summary,error=self.get(id as u32);if error!=Error.none {return error;}}}self.prepared=true;return Error.none;}
fn mayReference(function:const Function&,parameter:ValueType,index:i64)->bool {return parameter==blot_backend_runtime_ir::VT_i32 && function.parameterRole(index)!=blot_backend_runtime_ir::ROLE_scalar;}
struct Analysis {instructions:const Instruction[:]=[],summaries:Summaries=Summaries{..},mode:AnalysisMode=AnalysisMode.temporaries,locals:Value[:]=[],writes:u32[:]=[],read_unset:bool[:]=[],allocations:Allocations=Allocations{..},uses:Uses=Uses{..},stack:Values=Values{..},controls:Controls=Controls{..},references:References=References{..},fields:FieldMap=FieldMap{..},accesses:Accesses=Accesses{..},region:u32=0,segment:u32=0,at:u32=0,valid:bool=true,invalidates:bool=false,rc_valid:bool=true,rc_writes:RcWrites=RcWrites{..},result_owner:u32=0}
reusable[] var local_runs:Value[>..]=[];
reusable[] var write_runs:u32[>..]=[];
reusable[] var unset_runs:bool[>..]=[];
fn initAnalysis(summaries:const Summaries&,function:const Function&,mode:AnalysisMode)->Analysis,Error {let module .= summaries.module();let local_count=module.locals(function).len;if local_count>0x7fffffffffffffff-function.parameters.len {return Analysis{..},Error.out_of_memory;}let count=function.parameters.len+local_count;let locals=local_runs.alloc_slice(count);let writes=write_runs.alloc_slice(count);let unset=unset_runs.alloc_slice(count);for &value in locals {value=Value{..};}for &value,index in writes {value=0;if index<function.parameters.len {value=1;}}for &value in unset {value=false;}for inst in module.instructions(function) {if inst.op==blot_backend_runtime_ir::OP_local_set || inst.op==blot_backend_runtime_ir::OP_local_tee {if writes[inst.operand]!=0xffffffff {writes[inst.operand]+=1;}}}return Analysis{summaries:summaries,mode:mode,locals:locals,writes:writes,read_unset:unset,..},Error.none;}
fn deinit(self:Analysis&) {if self.locals.len!=0 {local_runs.free_slice(self.locals);}if self.writes.len!=0 {write_runs.free_slice(self.writes);}if self.read_unset.len!=0 {unset_runs.free_slice(self.read_unset);}self.allocations.deinit();self.uses.deinit();self.stack.deinit();self.controls.deinit();self.references.deinit();self.fields.deinit();self.accesses.deinit();self.rc_writes.deinit();self=Analysis{..};}
fn dominates(self:const Analysis&,scope:u32)->bool {if scope==0 {return true;}for control in self.controls.items {if control.identity==scope {return true;}}return false;}
fn floor(self:const Analysis&)->i64 {if self.controls.len==0 {return 0;}return self.controls.items[self.controls.len-1].height;}
fn pop(self:Analysis&)->Value {if self.stack.len>self.floor() {return self.stack.pop();}return Value{..};}
fn push(self:Analysis&,value:Value)->Error {return self.stack.push(value);}
fn use(self:Analysis&,value:Value)->Error {if value.owner==0 {return Error.none;}let owner .= self.allocations.items[value.owner-1];owner.last=self.at;owner.last_region=self.region;if self.mode==AnalysisMode.temporaries && (owner.uses==absent || self.uses.items[owner.uses].at!=self.at) {let error=self.uses.push(Use{at:self.at,previous:owner.uses,..});if error!=Error.none {return error;}owner.uses=(self.uses.len-1) as u32;}return Error.none;}
fn escape(self:Analysis&,value:Value)->Error {let error=self.use(value);if error!=Error.none {return error;}if value.owner!=0 {self.allocations.items[value.owner-1].escaped=true;}return Error.none;}
fn recordResult(self:Analysis&,value:Value)->Error {let error=self.use(value);if error!=Error.none {return error;}if value.owner!=0 {self.allocations.items[value.owner-1].returned=true;}if value.owner==0 || value.offset!=0 || (self.result_owner!=0 && self.result_owner!=value.owner) {self.result_owner=absent;}else {self.result_owner=value.owner;}return Error.none;}
fn allocation(self:Analysis&,bytes:u32)->Error {let error=self.allocations.push(Allocation{size:bytes,region:self.region,last_region:self.region,definition:self.at,last:self.at,segment:self.segment,..});if error!=Error.none {return error;}return self.push(Value{owner:self.allocations.len as u32,..});}
fn memory(self:Analysis&,value:Value,offset:u32,bytes:blot_support::Option<u32>,kind:AccessKind,reference:u32)->Error {let error=self.use(value);if error!=Error.none {return error;}if value.owner==0 {return Error.none;}if offset>0xffffffff-value.offset {return self.escape(value);}let start=value.offset+offset;let owner .= self.allocations.items[value.owner-1];if !bytes.present || start>owner.size || bytes.value>owner.size-start {return self.escape(value);}owner.required=max(owner.required,start+bytes.value);if !owner.parameter && bytes.value!=0 {let error=self.accesses.push(Access{offset:start,bytes:bytes.value,at:self.at,previous:owner.accesses,kind:kind,reference:reference,..});if error!=Error.none {return error;}owner.accesses=(self.accesses.len-1) as u32;}return Error.none;}
fn scalarSlot(self:const Analysis&,address:Value,offset:u32)->bool {if address.owner==0 || offset>0xffffffff-address.offset {return false;}let start=address.offset+offset;if start%4!=0 {return false;}let owner=self.allocations.items[address.owner-1];if start>owner.size || 4>owner.size-start {return false;}if owner.rc_mask.present {return !blot_runtime_layout::referenceWord(owner.rc_mask.value,start/4);}if owner.annotations==absent {return false;}return blot_backend_runtime_ir::wordRole(self.instructions[owner.annotations..owner.annotations+owner.annotation_count],start/4)==blot_backend_runtime_ir::ROLE_scalar;}
fn fieldKey(owner:u32,offset:u32)->u64 {return (owner as u64)<<32 | offset as u64;}
fn scalarRange(self:const Analysis&,address:Value,offset:u32,bytes:u32)->bool {var word:u32=0;while word<bytes {if word>0xffffffff-offset || !self.scalarSlot(address,offset+word) {return false;}if word>0xffffffff-4 {return false;}word+=4;}return true;}
fn scalarStoreAddress(self:const Analysis&,address:Value,offset:u32,bytes:u32)->bool {if address.offset!=absent && address.offset%4!=0 {return false;}if address.owner==0 {return true;}if address.offset==absent {let mask=self.allocations.items[address.owner-1].rc_mask;return mask.present && mask.value==0;}return self.scalarRange(address,offset,bytes);}
fn field(self:const Analysis&,address:Value,offset:u32)->blot_support::Option<u32> {if address.owner==0 || offset>0xffffffff-address.offset {return blot_support::none<u32>();}let start=address.offset+offset;let id .= self.fields.get(fieldKey(address.owner,start));if !id {return blot_support::none<u32>();}let reference=self.references.items[id];if reference.region!=self.region || !self.dominates(reference.scope) {return blot_support::none<u32>();}return blot_support::some(id);}
fn storeReference(self:Analysis&,address:Value,offset:u32,value:Value)->Error {let error=self.use(value);if error!=Error.none {return error;}if value.owner==0 {return Error.none;}if address.owner==0 || self.allocations.items[address.owner-1].parameter || self.allocations.items[value.owner-1].parameter || offset>0xffffffff-address.offset {return self.escape(value);}let start=address.offset+offset;let parent .= self.allocations.items[address.owner-1];var scalar=false;if parent.rc_mask.present && !blot_runtime_layout::referenceWord(parent.rc_mask.value,start/4) {scalar=true;}if parent.annotations!=absent && (start%4!=0 || blot_backend_runtime_ir::wordRole(self.instructions[parent.annotations..parent.annotations+parent.annotation_count],start/4)==blot_backend_runtime_ir::ROLE_scalar) {scalar=true;}let identity=scalar && start%4==0 && address.owner==value.owner && value.offset==0 && blot_backend_runtime_ir::hasSelfIdentityStore(self.instructions,self.at);if scalar && !identity {if self.mode==AnalysisMode.parameters {self.summaries.role_conflicts+=1;}return self.escape(value);}let id=self.references.len as u32;var scope:u32=0;if self.controls.len!=0 {scope=self.controls.items[self.controls.len-1].identity;}let error=self.references.push(Reference{parent:address.owner,child:value,offset:start,at:self.at,scope:scope,region:self.region,previous:parent.references,..});if error!=Error.none {return error;}parent.references=id;self.fields.insert(fieldKey(address.owner,start),id);return Error.none;}
fn validateReferences(self:Analysis&)->Error {if self.references.len==0 {return Error.none;}var remaining:i64=reference_check_limit;for reference,id in self.references.items {let parent .= self.allocations.items[reference.parent-1];if parent.escaped {continue;}var next=parent.accesses;while next!=absent {if remaining==0 {parent.escaped=true;break;}remaining-=1;let access=self.accesses.items[next];next=access.previous;if access.offset as u64>=reference.offset as u64+4 || reference.offset as u64>=access.offset as u64+access.bytes {continue;}if access.kind==AccessKind.write && access.at<=reference.at {continue;}if access.kind==AccessKind.read && access.reference==id && access.bytes==4 && access.offset==reference.offset {continue;}parent.escaped=true;break;}}var pending=Words{..};let error=propagateEscapes(self,pending);pending.deinit();return error;}
fn propagateEscapes(self:Analysis&,pending:Words&)->Error {for owner,index in self.allocations.items {if owner.escaped {let error=pending.push(index as u32);if error!=Error.none {return error;}}}var at:i64=0;while at<pending.len {var next=self.allocations.items[pending.items[at]].references;at+=1;while next!=absent {let reference=self.references.items[next];let child .= self.allocations.items[reference.child.owner-1];if !child.escaped {child.escaped=true;let error=pending.push(reference.child.owner-1);if error!=Error.none {return error;}}next=reference.previous;}}return Error.none;}
fn closeArm(self:Analysis&)->Error {let control=self.controls.items[self.controls.len-1];if control.result {let error=self.escape(self.pop());if error!=Error.none {return error;}}for value in self.stack.items[control.height..] {let error=self.escape(value);if error!=Error.none {return error;}}self.stack.resize(control.height);return Error.none;}
fn dead(self:Analysis&)->Error {let floor=self.floor();for value in self.stack.items[floor..] {let error=self.escape(value);if error!=Error.none {return error;}}self.stack.resize(floor);return Error.none;}
fn opaqueCall(self:Analysis&,parameters:i64,result:ValueType)->Error {for index in 0..parameters {let error=self.escape(self.pop());if error!=Error.none {return error;}}if result!=blot_backend_runtime_ir::VT_none {let error=self.push(Value{..});if error!=Error.none {return error;}}self.region+=1;self.segment+=1;self.invalidates=true;return Error.none;}
recursive fn get(self:const Summaries&,id:u32)->Summary,Error {assert(self.valid());let summary .= self.functions[id];if self.prepared || summary.state!=SummaryPhase.unseen || self.depth==summary_depth_limit {return summary,Error.none;}let module .= self.module();if module.fixtureHelper(id) {summary.state=SummaryPhase.done;return summary,Error.none;}if module.arena.present {let arena=module.arena.value;if id==arena.recycle || id==arena.reset || id==arena.cycle_collect || id==arena.cycle_safe || arena.isAllocation(id) {summary.state=SummaryPhase.done;return summary,Error.none;}}if module.cohorts.present && id==module.cohorts.value.begin {for &parameter in summary.parameters {parameter=Parameter{escapes:false,..};}summary.invalidates=false;summary.state=SummaryPhase.done;return summary,Error.none;}summary.state=SummaryPhase.active;self.depth+=1;let function .= module.functions[id];let catalog=blot_backend_provider_modes::Catalog{entries:blot_backend_provider_modes::Modes{items:self.providers,len:self.providers.len,..},..};if blot_backend_provider_modes::readOperation(catalog,function).present {for &parameter in summary.parameters {parameter=Parameter{escapes:false,..};}summary.parameters[function.provider_parameter].bytes=blot_runtime_layout::StateFrame_bytes;summary.invalidates=false;summary.state=SummaryPhase.done;self.depth-=1;return summary,Error.none;}let created,error=initAnalysis(self,function,AnalysisMode.parameters);if error!=Error.none {self.depth-=1;return Summary{..},error;}var state=created;let error=summarize(self,module,function,summary,state);state.deinit();self.depth-=1;if error!=Error.none {return Summary{..},error;}summary.state=SummaryPhase.done;return summary,Error.none;}
fn summarize(self:const Summaries&,module:const Module&,function:const Function&,summary:Summary&,state:Analysis&)->Error {for parameter,index in module.parameters(function) {if !mayReference(function,parameter,index) {continue;}let error=state.allocations.push(Allocation{size:0xffffffff,region:0,last_region:0,definition:0,last:0,parameter:true,..});if error!=Error.none {return error;}state.locals[index]=Value{owner:state.allocations.len as u32,..};}let error=state.scan(module,function);if error!=Error.none {return error;}if !state.valid {return Error.none;}var owner:i64=0;for parameter,index in module.parameters(function) {if !mayReference(function,parameter,index) {continue;}let value=state.allocations.items[owner];summary.parameters[index]=Parameter{escapes:value.escaped || value.returned,bytes:value.required,..};owner+=1;}summary.invalidates=state.invalidates;if state.result_owner==0 || state.result_owner==absent || state.invalidates {return Error.none;}let result=state.allocations.items[state.result_owner-1];var embedded=false;for reference in state.references.items {if reference.child.owner==state.result_owner {embedded=true;break;}}var owns_fields=result.references!=absent;if result.rc_mask.present {owns_fields=owns_fields || result.rc_mask.value!=0;}if result.annotations!=absent {let roles=module.instructions(function)[result.annotations..result.annotations+result.annotation_count];let checked=min(result.size/4,16*blot_backend_runtime_ir::words_per_chunk+1);for word in 0..checked {if blot_backend_runtime_ir::wordRole(roles,word)!=blot_backend_runtime_ir::ROLE_scalar {owns_fields=true;}}}if !result.parameter && !result.escaped && !embedded && !owns_fields {summary.owned_result_bytes=blot_support::some(result.size);}return Error.none;}

let OP_ownership=blot_backend_runtime_ir::OP_ownership;
let OP_i32_const=blot_backend_runtime_ir::OP_i32_const;
let OP_f32_const=blot_backend_runtime_ir::OP_f32_const;
let OP_global_get=blot_backend_runtime_ir::OP_global_get;
let OP_memory_size=blot_backend_runtime_ir::OP_memory_size;
let OP_host_ref_null=blot_backend_runtime_ir::OP_host_ref_null;
let OP_host_ref_size=blot_backend_runtime_ir::OP_host_ref_size;
let OP_local_get=blot_backend_runtime_ir::OP_local_get;
let OP_local_set=blot_backend_runtime_ir::OP_local_set;
let OP_local_tee=blot_backend_runtime_ir::OP_local_tee;
let OP_i32_add=blot_backend_runtime_ir::OP_i32_add;
let OP_i32_mul=blot_backend_runtime_ir::OP_i32_mul;
let OP_i32_load=blot_backend_runtime_ir::OP_i32_load;
let OP_f32_load=blot_backend_runtime_ir::OP_f32_load;
let OP_v128_load=blot_backend_runtime_ir::OP_v128_load;
let OP_i32_store=blot_backend_runtime_ir::OP_i32_store;
let OP_f32_store=blot_backend_runtime_ir::OP_f32_store;
let OP_v128_store=blot_backend_runtime_ir::OP_v128_store;
let OP_memory_copy=blot_backend_runtime_ir::OP_memory_copy;
let OP_memory_fill=blot_backend_runtime_ir::OP_memory_fill;
let OP_call=blot_backend_runtime_ir::OP_call;
let OP_call_indirect=blot_backend_runtime_ir::OP_call_indirect;
let OP_call_import=blot_backend_runtime_ir::OP_call_import;
let OP_block=blot_backend_runtime_ir::OP_block;
let OP_loop=blot_backend_runtime_ir::OP_loop;
let OP_if_=blot_backend_runtime_ir::OP_if_;
let OP_else_=blot_backend_runtime_ir::OP_else_;
let OP_end=blot_backend_runtime_ir::OP_end;
let OP_br=blot_backend_runtime_ir::OP_br;
let OP_br_if=blot_backend_runtime_ir::OP_br_if;
let OP_return_=blot_backend_runtime_ir::OP_return_;
let OP_unreachable_=blot_backend_runtime_ir::OP_unreachable_;
let OP_drop=blot_backend_runtime_ir::OP_drop;
recursive fn scan(self:Analysis&,module:const Module&,function:const Function&)->Error {self.instructions=module.instructions(function);for inst,index in self.instructions {self.at=index as u32;let error=scanInstruction(self,module,function,inst,index);if error!=Error.none {return error;}if !self.valid {return Error.none;}}if function.result!=blot_backend_runtime_ir::VT_none {if self.stack.len!=0 {let error=self.recordResult(self.pop());if error!=Error.none {return error;}}else if self.result_owner==0 {self.result_owner=absent;}}if self.controls.len!=0 {self.valid=false;}if self.valid {return self.validateReferences();}return Error.none;}
fn scanInstruction(self:Analysis&,module:const Module&,function:const Function&,inst:Instruction,index:i64)->Error {match inst.op {
 OP_ownership=>{let scope=blot_backend_runtime_ir::ownership(inst.operand);if scope.kind!=blot_backend_runtime_ir::OWN_scope {return Error.none;}match scope.chunk {2,5,6=>{return self.escape(self.locals[scope.roles]);},3=>{let error=self.escape(self.locals[scope.roles]);if error!=Error.none {return error;}self.locals[scope.roles]=Value{..};},4=>{let error=self.use(self.locals[scope.roles&8191]);if error!=Error.none {return error;}return self.escape(self.locals[scope.roles>>13]);},_=>{},}},
 OP_i32_const=>{var value=Value{..};if !inst.table_reference {value.constant=blot_support::some(inst.operand);}return self.push(value);},OP_f32_const,OP_global_get,OP_memory_size,OP_host_ref_null,OP_host_ref_size=>{return self.push(Value{..});},
 OP_local_get=>{var value=self.locals[inst.operand];if !self.dominates(value.scope) {let error=self.escape(value);if error!=Error.none {return error;}value.constant=blot_support::none<u32>();}if value.region!=self.region {value.constant=blot_support::none<u32>();}if value.owner==0 && !value.constant.present && inst.operand>=function.parameters.len {self.read_unset[inst.operand]=true;}let error=self.use(value);if error!=Error.none {return error;}return self.push(value);},
 OP_local_set,OP_local_tee=>{var value=self.pop();let error=self.use(value);if error!=Error.none {return error;}if self.writes[inst.operand]!=1 || self.read_unset[inst.operand] {let error=self.escape(value);if error!=Error.none {return error;}let error=self.escape(self.locals[inst.operand]);if error!=Error.none {return error;}value.constant=blot_support::none<u32>();value.owner=0;}value.region=self.region;value.scope=0;if self.controls.len!=0 {value.scope=self.controls.items[self.controls.len-1].identity;}self.locals[inst.operand]=value;if value.owner!=0 && value.offset==0 {let owner .= self.allocations.items[value.owner-1];if owner.local==absent {owner.local=inst.operand;}}if inst.op==OP_local_tee {return self.push(value);}},
 OP_i32_add=>{return scanAdd(self);},OP_i32_mul=>{let right=self.pop();let left=self.pop();let error=self.escape(left);if error!=Error.none {return error;}let error=self.escape(right);if error!=Error.none {return error;}var value=Value{..};if left.constant.present && right.constant.present {value.constant=blot_support::some((left.constant.value as u64*right.constant.value as u64) as! u32);}return self.push(value);},
 OP_i32_load,OP_f32_load,OP_v128_load=>{return scanLoad(self,inst);},OP_i32_store,OP_f32_store,OP_v128_store=>{return scanStore(self,inst,index);},OP_memory_copy,OP_memory_fill=>{return scanCopy(self,inst);},
 OP_call=>{return scanCall(self,module,function,inst,index);},OP_call_indirect=>{let error=self.escape(self.pop());if error!=Error.none {return error;}let signature=blot_backend_runtime_ir::call(module,inst);return self.opaqueCall(signature.parameters.len,signature.result);},OP_call_import=>{let signature=blot_backend_runtime_ir::call(module,inst);return self.opaqueCall(signature.parameters.len,signature.result);},
 OP_block,OP_loop,OP_if_=>{self.segment+=1;if inst.op==OP_if_ {let error=self.escape(self.pop());if error!=Error.none {return error;}}return self.controls.push(Control{height:self.stack.len,result:inst.operand!=0 && inst.operand!=blot_backend_runtime_ir::VT_none as u32,identity:self.at+1,..});},
 OP_else_=>{self.segment+=1;if self.controls.len==0 {self.valid=false;return Error.none;}let error=self.closeArm();if error!=Error.none {return error;}self.controls.items[self.controls.len-1].identity=self.at+1;},OP_end=>{self.segment+=1;if self.controls.len==0 {self.valid=false;return Error.none;}let error=self.closeArm();if error!=Error.none {return error;}let control=self.controls.pop();if control.result {return self.push(Value{..});}},
 OP_br,OP_br_if=>{self.segment+=1;if inst.op==OP_br_if {let error=self.escape(self.pop());if error!=Error.none {return error;}}for value in self.stack.items {let error=self.escape(value);if error!=Error.none {return error;}}if inst.op==OP_br {return self.dead();}},
 OP_return_=>{self.segment+=1;if function.result!=blot_backend_runtime_ir::VT_none {let error=self.recordResult(self.pop());if error!=Error.none {return error;}}return self.dead();},OP_unreachable_=>{self.segment+=1;return self.dead();},OP_drop=>{return self.use(self.pop());},
 _=>{let contract=blot_backend_runtime_ir::contract(module,function,inst);for argument in 0..contract.arity {let error=self.escape(self.pop());if error!=Error.none {return error;}}if contract.result!=blot_backend_runtime_ir::VT_none {return self.push(Value{..});}},
 }return Error.none;}
fn scanAdd(self:Analysis&)->Error {var right=self.pop();var left=self.pop();if left.constant.present {let swap=left;left=right;right=swap;}let error=self.use(left);if error!=Error.none {return error;}let error=self.use(right);if error!=Error.none {return error;}if right.constant.present {let offset=right.constant.value;if left.constant.present {return self.push(Value{constant:blot_support::some((left.constant.value as u64+offset as u64) as! u32),..});}if offset<=0xffffffff-left.offset {left.offset+=offset;return self.push(left);}let error=self.escape(left);if error!=Error.none {return error;}return self.push(Value{..});}let error=self.escape(left);if error!=Error.none {return error;}let error=self.escape(right);if error!=Error.none {return error;}var owner:u32=0;if right.owner==0 {owner=left.owner;}return self.push(Value{owner:owner,offset:absent,..});}
fn scanLoad(self:Analysis&,inst:Instruction)->Error {let address=self.pop();var reference=blot_support::none<u32>();if inst.op==OP_i32_load {reference=self.field(address,inst.operand);}var id:u32=absent;if reference.present {id=reference.value;}let error=self.memory(address,inst.operand,blot_support::some(blot_backend_runtime_ir::fixed(inst.op).bytes as u32),AccessKind.read,id);if error!=Error.none {return error;}if inst.op==OP_i32_load && !reference.present && address.owner!=0 {let parent=self.allocations.items[address.owner-1];var offset:u32=absent;if inst.operand<=0xffffffff-address.offset {offset=address.offset+inst.operand;}var followed=false;if parent.rc_mask.present && blot_runtime_layout::referenceWord(parent.rc_mask.value,offset/4) {followed=true;}if parent.annotations!=absent && blot_backend_runtime_ir::wordRole(self.instructions[parent.annotations..parent.annotations+parent.annotation_count],offset/4)!=blot_backend_runtime_ir::ROLE_scalar {followed=true;}if followed {let error=self.escape(address);if error!=Error.none {return error;}}}if reference.present {return self.push(self.references.items[reference.value].child);}return self.push(Value{..});}
fn scanStore(self:Analysis&,inst:Instruction,index:i64)->Error {let value=self.pop();let address=self.pop();let bytes=blot_backend_runtime_ir::fixed(inst.op).bytes as u32;let error=self.memory(address,inst.operand,blot_support::some(bytes),AccessKind.write,absent);if error!=Error.none {return error;}let scalar_store=blot_backend_runtime_ir::hasScalarStore(self.instructions,index);let checked_scalar=scalar_store && value.owner==0 && self.scalarStoreAddress(address,inst.operand,bytes);if scalar_store && !checked_scalar {self.rc_valid=false;}if !checked_scalar {if address.owner==0 {self.rc_valid=false;}else if inst.op==OP_v128_store {let mask=self.allocations.items[address.owner-1].rc_mask;if !mask.present || mask.value!=0 {self.rc_valid=false;}}else if !self.scalarSlot(address,inst.operand) {var kind=RcWriteKind.word;if inst.op==OP_f32_store {kind=RcWriteKind.float_word;}let error=self.rc_writes.push(RcWrite{at:self.at,owner:address.owner,kind:kind,..});if error!=Error.none {return error;}}}if inst.op==OP_i32_store {return self.storeReference(address,inst.operand,value);}return self.escape(value);}
fn scanCopy(self:Analysis&,inst:Instruction)->Error {let bytes=self.pop();let source=self.pop();let error=self.escape(bytes);if error!=Error.none {return error;}if inst.op==OP_memory_copy {let error=self.memory(source,0,bytes.constant,AccessKind.read,absent);if error!=Error.none {return error;}}else {let error=self.escape(source);if error!=Error.none {return error;}}let target=self.pop();if inst.op==OP_memory_copy && target.owner!=0 {let error=self.rc_writes.push(RcWrite{at:self.at,owner:target.owner,kind:RcWriteKind.copy,..});if error!=Error.none {return error;}}else {var fresh_clear=false;if inst.op==OP_memory_fill && target.owner!=0 && source.constant.present && source.constant.value==0 && target.offset==0 && bytes.constant.present {let owner=self.allocations.items[target.owner-1];fresh_clear=bytes.constant.value==owner.size && owner.accesses==absent && !owner.escaped;}if !fresh_clear {self.rc_valid=false;}}return self.memory(target,0,bytes.constant,AccessKind.write,absent);}
fn scanCall(self:Analysis&,module:const Module&,function:const Function&,inst:Instruction,index:i64)->Error {let callee=blot_backend_runtime_ir::call(module,inst);if callee.ownership==blot_backend_runtime_ir::CALL_allocate || callee.ownership==blot_backend_runtime_ir::CALL_allocate_scalar || callee.ownership==blot_backend_runtime_ir::CALL_allocate_typed || callee.ownership==blot_backend_runtime_ir::CALL_allocate_shaped || callee.ownership==blot_backend_runtime_ir::CALL_allocate_cohort || callee.ownership==blot_backend_runtime_ir::CALL_allocate_region {return scanAllocationCall(self,module,function,callee,inst,index);}if callee.ownership==blot_backend_runtime_ir::CALL_borrow_region {let offset=self.pop();let error=self.escape(self.pop());if error!=Error.none {return error;}var bytes=blot_support::none<u32>();for member in module.regions.value.plan.members {if offset.constant.present && offset.constant.value==member.offset {bytes=blot_support::some(member.bytes);}}if bytes.present {let error=self.allocation(bytes.value);if error!=Error.none {return error;}let view .= self.allocations.items[self.allocations.len-1];view.parameter=true;view.escaped=true;view.rc_mask=blot_support::some(0 as u32);}else {self.rc_valid=false;return self.push(Value{..});}return Error.none;}let summary,error=self.summaries.get(inst.operand);if error!=Error.none {return error;}for argument in 0..callee.parameters.len {let parameter=summary.parameters[callee.parameters.len-1-argument];let value=self.pop();var error=Error.none;if parameter.escapes || summary.invalidates {error=self.escape(value);}else {error=self.memory(value,0,blot_support::some(parameter.bytes),AccessKind.read,absent);}if error!=Error.none {return error;}}if summary.owned_result_bytes.present {let error=self.allocation(summary.owned_result_bytes.value);if error!=Error.none {return error;}}else if callee.result!=blot_backend_runtime_ir::VT_none {let error=self.push(Value{..});if error!=Error.none {return error;}}if summary.invalidates {self.region+=1;self.segment+=1;self.invalidates=true;}return Error.none;}
fn scanAllocationCall(self:Analysis&,module:const Module&,function:const Function&,callee:blot_backend_runtime_ir::Call,inst:Instruction,index:i64)->Error {var mask=blot_support::none<u32>();if callee.ownership==blot_backend_runtime_ir::CALL_allocate_scalar {mask=blot_support::some(0 as u32);}if callee.ownership==blot_backend_runtime_ir::CALL_allocate_cohort {let error=self.escape(self.pop());if error!=Error.none {return error;}}if callee.ownership==blot_backend_runtime_ir::CALL_allocate_shaped {let error=self.escape(self.pop());if error!=Error.none {return error;}mask=blot_support::some(0xffffffff as u32);}else if callee.ownership==blot_backend_runtime_ir::CALL_allocate_typed || callee.ownership==blot_backend_runtime_ir::CALL_allocate_cohort {let value=self.pop();mask=value.constant;let error=self.escape(value);if error!=Error.none {return error;}}var bytes=self.pop();let error=self.escape(bytes);if error!=Error.none {return error;}if callee.ownership==blot_backend_runtime_ir::CALL_allocate_region {bytes.constant=blot_support::some(module.regions.value.plan.bytes);mask=blot_support::some(module.regions.value.plan.mask);}if bytes.constant.present && bytes.constant.value>0 {let error=self.allocation(bytes.constant.value);if error!=Error.none {return error;}let owner .= self.allocations.items[self.allocations.len-1];owner.rc_mask=mask;var roles:const Instruction[:]=[];if callee.ownership==blot_backend_runtime_ir::CALL_allocate || callee.ownership==blot_backend_runtime_ir::CALL_allocate_scalar {roles=blot_backend_runtime_ir::allocationAnnotations(module.instructions(function),index);}if roles.len!=0 {owner.annotations=(index-1-roles.len) as u32;owner.annotation_count=roles.len as u32;}}else if callee.ownership==blot_backend_runtime_ir::CALL_allocate_scalar || callee.ownership==blot_backend_runtime_ir::CALL_allocate_typed || callee.ownership==blot_backend_runtime_ir::CALL_allocate_shaped || callee.ownership==blot_backend_runtime_ir::CALL_allocate_cohort || callee.ownership==blot_backend_runtime_ir::CALL_allocate_region {let error=self.allocation(0xffffffff);if error!=Error.none {return error;}let owner .= self.allocations.items[self.allocations.len-1];owner.escaped=true;owner.rc_mask=mask;}else {self.rc_valid=false;return self.push(Value{..});}return Error.none;}
