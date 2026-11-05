// Closed machine ranges share a private nonreentrant root bank after source checks.
namespace blot_backend_wasm_scope_outline;
import std;
import dictionary;
import support.error;
import support.option;
import support.native;
import support.pooled_buffer;
import support.pooled_map;
import .runtime_ir;
import .wasm;
import .wasm_copy_coalesce;
import .wasm_stackify;
import .wasm_local_compact;
import .wasm_local_order;
import .wasm_simd_ops;
import .optimizer_buffers;
type Error=blot_error::Error;
type Module=blot_backend_wasm::Module;
type Function=blot_backend_runtime_ir::Function;
type Instruction=blot_backend_runtime_ir::Instruction;
type Op=blot_backend_runtime_ir::Op;
type ValueType=blot_backend_runtime_ir::ValueType;
type Output=blot_backend_runtime_ir::DetachedBody;
type Words=blot_backend_optimizer_buffers::Words;
type Code=blot_backend_optimizer_buffers::Code;
type Types=blot_backend_optimizer_buffers::Types;
let absent:u32=0xffffffff;
enum Contract {scoped_numeric_adapter_nonreentrant}
type Mode=Contract;
struct Options {verify_copy_inputs:bool=false,minimum_instructions:i64=5000,maximum_range_instructions:i64=1800000,maximum_helpers:i64=8192,maximum_control_depth:i64=1024,maximum_globals:i64=1000000,maximum_locals:i64=49000,maximum_body_bytes:i64=7500000}
struct Work {expressions:i64,layouts:i64}
struct Ticket {function:u32,start:i64,work:Work}
type Credit=Work;
struct Stats {regions:u64=0,globals:u64=0,copies_removed:u64=0,reads_forwarded:u64=0,bank_operand_bytes_saved:u64=0}
struct Total {references:i64=0,writes:i64=0}
struct Reference {function:u32=absent,weight:u64=0}
struct Helper {function:u32,root:u32,read_before_def:u32[:]=[],credit:Credit}
struct Prepared {function:u32,body:Output=Output{..}}
struct Bank {root:u32,globals:u32[:]=[]}
struct Totals {storage:Total[:]=[],items:Total[:]=[],len:i64=0}
reusable[] var pool_Totals:Total[>..]=[];
fn ensure(self:Totals&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Totals);}
fn push(self:Totals&,value:Total)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Totals);self.len=self.items.len;return error;}
fn resize(self:Totals&,length:i64,value:Total)->Error {if length<=self.len {blot_support_pooled_buffer::resize(self,length);self.len=length;return Error.none;}let error=self.ensure(length);if error!=Error.none {return error;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;return Error.none;}
fn deinit(self:Totals&) {blot_support_pooled_buffer::deinit(self,pool_Totals);self.len=0;}
struct Helpers {storage:Helper[:]=[],items:Helper[:]=[],len:i64=0}
reusable[] var pool_Helpers:Helper[>..]=[];
fn ensure(self:Helpers&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Helpers);}
fn push(self:Helpers&,value:Helper)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Helpers);self.len=self.items.len;return error;}
fn resize(self:Helpers&,length:i64,value:Helper)->Error {if length<=self.len {blot_support_pooled_buffer::resize(self,length);self.len=length;return Error.none;}let error=self.ensure(length);if error!=Error.none {return error;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;return Error.none;}
fn deinit(self:Helpers&) {blot_support_pooled_buffer::deinit(self,pool_Helpers);self.len=0;}
struct PreparedBuffer {storage:Prepared[:]=[],items:Prepared[:]=[],len:i64=0}
reusable[] var pool_PreparedBuffer:Prepared[>..]=[];
fn ensure(self:PreparedBuffer&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_PreparedBuffer);}
fn push(self:PreparedBuffer&,value:Prepared)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_PreparedBuffer);self.len=self.items.len;return error;}
fn resize(self:PreparedBuffer&,length:i64,value:Prepared)->Error {if length<=self.len {blot_support_pooled_buffer::resize(self,length);self.len=length;return Error.none;}let error=self.ensure(length);if error!=Error.none {return error;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;return Error.none;}
fn deinit(self:PreparedBuffer&) {blot_support_pooled_buffer::deinit(self,pool_PreparedBuffer);self.len=0;}
struct Banks {storage:Bank[:]=[],items:Bank[:]=[],len:i64=0}
reusable[] var pool_Banks:Bank[>..]=[];
fn ensure(self:Banks&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self,minimum,pool_Banks);}
fn push(self:Banks&,value:Bank)->Error {let error=blot_support_pooled_buffer::push(self,value,pool_Banks);self.len=self.items.len;return error;}
fn resize(self:Banks&,length:i64,value:Bank)->Error {if length<=self.len {blot_support_pooled_buffer::resize(self,length);self.len=length;return Error.none;}let error=self.ensure(length);if error!=Error.none {return error;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;return Error.none;}
fn deinit(self:Banks&) {blot_support_pooled_buffer::deinit(self,pool_Banks);self.len=0;}
struct Pending {table:blot_support_pooled_map::Map<i64,bool>=blot_support_pooled_map::Map<i64,bool>{..}}
reusable[] var pending_slots:dictionary_slot<i64,bool>[>..]=[];
fn insert(self:Pending&,key:i64) {blot_support_pooled_map::insert(self.table,key,true,pending_slots);}
fn remove(self:Pending&,key:i64) {blot_support_pooled_map::remove(self.table,key);}
fn deinit(self:Pending&) {blot_support_pooled_map::deinit(self.table,pending_slots);}
struct Root {function:u32,scanned:i64=0,totals:Totals=Totals{..},helpers:Words=Words{..},pending:Pending=Pending{..}}
fn deinit(self:Root&) {self.totals.deinit();self.helpers.deinit();self.pending.deinit();}
struct Roots {storage:Root[:]=[],items:Root[:]=[],len:i64=0}
reusable[] var root_runs:Root[>..]=[];
fn push(self:Roots&,value:Root)->Error {let error=blot_support_pooled_buffer::push(self,value,root_runs);self.len=self.items.len;return error;}
fn deinit(self:Roots&) {blot_support_pooled_buffer::deinit(self,root_runs);self.len=0;}
struct ContextState {roots:Roots=Roots{..},helpers:Helpers=Helpers{..},stats:Stats=Stats{..},finalized:bool=false,generation:u64=0,live:bool=false}
reusable var context_states:ContextState[>..]=[];
var inactive_context:ContextState=ContextState{..};
reusable[] var word_runs:u32[>..]=[];
reusable[] var reference_runs:Reference[>..]=[];
reusable[] var flag_runs:bool[>..]=[];
struct Context {module:Module?=null,options:Options=Options{..},slot:u32=0,generation:u64=0,roots:Roots&=inactive_context.roots,helpers:Helpers&=inactive_context.helpers,stats:Stats&=inactive_context.stats,finalized:bool&=inactive_context.finalized}
fn live(self:const Context&)->bool {return self.slot!=0 && self.slot<=context_states.len && context_states[self.slot-1].live && context_states[self.slot-1].generation==self.generation;}
fn target(self:const Context&)->Module& {assert(self.live());let module .= self.module;assert(module);return module;}
fn init(module:Module&,contract:Contract,options:Options)->Context {let generation=blot_native::fresh_owner_id();let at=context_states.alloc_index(ContextState{generation:generation,live:true,..});let owner .= context_states[at];return Context{module:module,options:options,slot:(at+1) as u32,generation:generation,roots:owner.roots,helpers:owner.helpers,stats:owner.stats,finalized:owner.finalized,..};}
fn deinit(self:Context&) {if self.slot==0 {return;}assert(self.live());for &root in self.roots.items {root.deinit();}for helper in self.helpers.items {if helper.read_before_def.len!=0 {word_runs.free_slice(helper.read_before_def);}}self.roots.deinit();self.helpers.deinit();let at=self.slot-1;context_states[at].live=false;context_states.free(at);self=Context{..};}
fn rootIndex(self:const Context&,function:u32)->blot_support::Option<i64> {for root,index in self.roots.items {if root.function==function {return blot_support::some(index);}}return blot_support::none<i64>();}
fn registerRoot(self:Context&,function:u32)->Error {let module .= self.target();let options=self.options;if options.maximum_globals==0 || options.maximum_globals>1000000 || options.maximum_locals>50000 || options.maximum_body_bytes>7654321 || options.minimum_instructions==0 || options.minimum_instructions>options.maximum_range_instructions {return Error.invalid_outline;}if self.finalized || module.memory_model!=blot_backend_wasm::MemoryModel.data_stacks || module.artifacts || function>=module.functions.len || self.rootIndex(function).present {return Error.invalid_outline;}return self.roots.push(Root{function:function,..});}
fn begin(self:const Context&,function:u32,work:Work)->blot_support::Option<Ticket> {if self.finalized || !self.rootIndex(function).present {return blot_support::none<Ticket>();}return blot_support::some(Ticket{function:function,start:self.target().instructions(function).len,work:work,..});}
fn hasCoordinates(module:const Module&,function:u32)->bool {for site in module.semantic_sites {if site.function==function {return true;}}for site in module.table_origins {if site.function==function {return true;}}return false;}
fn canRewriteSuffix(self:const Context&,function:u32,start:i64)->bool {if self.finalized || hasCoordinates(self.target(),function) {return false;}let selected=self.rootIndex(function);if selected.present {let root .= self.roots.items[selected.value];if root.scanned>start {return false;}for entry in root.pending.table.slots {if entry.tag!=0 && entry.key>=start {return false;}}}return true;}
fn local(op:Op)->bool {return op==blot_backend_runtime_ir::OP_local_get || op==blot_backend_runtime_ir::OP_local_set || op==blot_backend_runtime_ir::OP_local_tee;}
fn localType(module:const Module&,function:const Function&,id:u32)->blot_support::Option<ValueType> {if id<function.parameters.len {return blot_support::some(module.parameters(function)[id]);}let index=id-function.parameters.len;let own=module.locals(function);if index>=own.len {return blot_support::none<ValueType>();}return blot_support::some(own[index]);}
fn sync(self:Context&,index:i64)->Error {let module .= self.target();let function=module.functions[self.roots.items[index].function];let root .= self.roots.items[index];let own=module.locals(function);if own.len>0x7fffffffffffffff-function.parameters.len {return Error.invalid_outline;}let count=function.parameters.len+own.len;let code=module.instructions(function);if count>=absent || count<root.totals.len || root.scanned>code.len {return Error.invalid_outline;}let error=root.totals.resize(count,Total{..});if error!=Error.none {return error;}for inst in code[root.scanned..] {if local(inst.op) {if inst.operand>=count {return Error.invalid_outline;}root.totals.items[inst.operand].references+=1;if inst.op!=blot_backend_runtime_ir::OP_local_get {root.totals.items[inst.operand].writes+=1;}}}root.scanned=code.len;return Error.none;}
fn reserveCopy(self:Context&,function:u32)->i64,Error {let module .= self.target();if self.finalized || function>=module.functions.len {return 0,Error.invalid_outline;}let index=module.instructions(function).len;let error=module.reserveInstructions(function,2);if error!=Error.none {return 0,error;}let root=self.rootIndex(function);if root.present {self.roots.items[root.value].pending.insert(index);}let error=module.emitSlice(function,[Instruction{op:blot_backend_runtime_ir::OP_nop,..},Instruction{op:blot_backend_runtime_ir::OP_nop,..}]);return index,error;}
fn copyPair(self:Context&,function:u32,index:i64)->Error {let module .= self.target();if self.finalized || function>=module.functions.len {return Error.invalid_outline;}let code=module.instructions(function);if index>=code.len || code.len-index<2 {return Error.invalid_outline;}for inst in code[index..index+2] {if inst.op!=blot_backend_runtime_ir::OP_nop || inst.table_reference || inst.table_kind!=blot_backend_runtime_ir::TABLE_unknown {return Error.invalid_outline;}}return Error.none;}
fn releaseCopy(self:Context&,function:u32,index:i64)->Error {let error=self.copyPair(function,index);if error!=Error.none {return error;}let root=self.rootIndex(function);if root.present {self.roots.items[root.value].pending.remove(index);}return Error.none;}
fn patchCopy(self:Context&,function:u32,index:i64,src:u32,dst:u32)->Error {let error=self.copyPair(function,index);if error!=Error.none {return error;}let module .= self.target();let source=module.functions[function];let own=module.locals(source);if own.len>0x7fffffffffffffff-source.parameters.len {return Error.invalid_outline;}let count=source.parameters.len+own.len;let src_type=localType(module,source,src);let dst_type=localType(module,source,dst);if src>=count || dst>=count || !src_type.present || !dst_type.present || src_type.value!=blot_backend_runtime_ir::VT_i32 || dst_type.value!=blot_backend_runtime_ir::VT_i32 {return Error.invalid_outline;}let selected=self.rootIndex(function);if selected.present {let root .= self.roots.items[selected.value];if count<root.totals.len {return Error.invalid_outline;}let error=root.totals.resize(count,Total{..});if error!=Error.none {return error;}if index<root.scanned {if root.scanned-index<2 {return Error.invalid_outline;}root.totals.items[src].references+=1;root.totals.items[dst].references+=1;root.totals.items[dst].writes+=1;}root.pending.remove(index);}let first,error=module.mutableInstruction(function,index);if error!=Error.none {return error;}let second,error=module.mutableInstruction(function,index+1);if error!=Error.none {return error;}first.op=blot_backend_runtime_ir::OP_local_get;first.operand=src;second.op=blot_backend_runtime_ir::OP_local_set;second.operand=dst;return Error.none;}
