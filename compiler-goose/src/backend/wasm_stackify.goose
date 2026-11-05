// Pure nontrapping single-use trees move only inside physical effect barriers.
namespace blot_backend_wasm_stackify;
import .runtime_ir;
import .wasm;
import .optimizer_buffers;
import support.error;
import support.option;
import support.pooled_buffer;
type Error=blot_error::Error;
type Module=blot_backend_wasm::Module;
type Function=blot_backend_runtime_ir::Function;
type Instruction=blot_backend_runtime_ir::Instruction;
type Op=blot_backend_runtime_ir::Op;
type ValueType=blot_backend_runtime_ir::ValueType;
type Output=blot_backend_runtime_ir::DetachedBody;
type Sizes=blot_backend_optimizer_buffers::Sizes;
type Code=blot_backend_optimizer_buffers::Code;
type Types=blot_backend_optimizer_buffers::Types;
let absent:i64=0x7fffffffffffffff;
struct Use {pending:i64=absent,segment:i64=absent,definitions:u8=0,reads:u8=0,pinned:bool=false,eliminated:bool=false,crosses_barrier:bool=false}
fn candidate(self_:Use)->bool {return !self_.pinned && self_.definitions==1 && self_.reads==1;}
struct Node {instruction:Instruction,children:i64[3]=[absent;3],arity:u8=0,ty:ValueType}
struct Pending {local:i64,node:i64,instruction:Instruction}
struct Visit {node:i64,emit:bool=false}
reusable[] var use_runs:Use[>..]=[];
struct Nodes {storage:Node[:] = default<Node[:]>(),items:Node[:] = default<Node[:]>(),len:i64=0}
reusable[] var pool_Nodes:Node[>..]=[];
fn push(self_:Nodes&,value:Node)->Error {let error=blot_support_pooled_buffer::push(self_,value,pool_Nodes);self_.len=self_.items.len;return error;}
fn pop(self_:Nodes&)->Node {assert(self_.len>0);let value=self_.items[self_.len-1];blot_support_pooled_buffer::resize(self_,self_.len-1);self_.len=self_.items.len;return value;}
fn clear(self_:Nodes&) {blot_support_pooled_buffer::clear(self_);self_.len=0;}
fn deinit(self_:Nodes&) {blot_support_pooled_buffer::deinit(self_,pool_Nodes);self_.len=0;}
struct PendingBuffer {storage:Pending[:] = default<Pending[:]>(),items:Pending[:] = default<Pending[:]>(),len:i64=0}
reusable[] var pool_PendingBuffer:Pending[>..]=[];
fn push(self_:PendingBuffer&,value:Pending)->Error {let error=blot_support_pooled_buffer::push(self_,value,pool_PendingBuffer);self_.len=self_.items.len;return error;}
fn pop(self_:PendingBuffer&)->Pending {assert(self_.len>0);let value=self_.items[self_.len-1];blot_support_pooled_buffer::resize(self_,self_.len-1);self_.len=self_.items.len;return value;}
fn clear(self_:PendingBuffer&) {blot_support_pooled_buffer::clear(self_);self_.len=0;}
fn deinit(self_:PendingBuffer&) {blot_support_pooled_buffer::deinit(self_,pool_PendingBuffer);self_.len=0;}
struct Visits {storage:Visit[:] = default<Visit[:]>(),items:Visit[:] = default<Visit[:]>(),len:i64=0}
reusable[] var pool_Visits:Visit[>..]=[];
fn push(self_:Visits&,value:Visit)->Error {let error=blot_support_pooled_buffer::push(self_,value,pool_Visits);self_.len=self_.items.len;return error;}
fn pop(self_:Visits&)->Visit {assert(self_.len>0);let value=self_.items[self_.len-1];blot_support_pooled_buffer::resize(self_,self_.len-1);self_.len=self_.items.len;return value;}
fn clear(self_:Visits&) {blot_support_pooled_buffer::clear(self_);self_.len=0;}
fn deinit(self_:Visits&) {blot_support_pooled_buffer::deinit(self_,pool_Visits);self_.len=0;}
struct Builder {uses:Use[:] = default<Use[:]>(),nodes:Nodes=Nodes{..},stack:Sizes=Sizes{..},pending:PendingBuffer=PendingBuffer{..},visits:Visits=Visits{..},locals:Types=Types{..},code:Code=Code{..}}
fn deinit(self_:Builder&) {self_.nodes.deinit();self_.stack.deinit();self_.pending.deinit();self_.visits.deinit();}
fn push(self_:Builder&,node:Node)->Error {let id=self_.nodes.len;let error=self_.nodes.push(node);if error!=blot_error::Error.none {return error;}return self_.stack.push(id);}
fn emit(self_:Builder&,root:i64)->Error {let error=self_.visits.push(Visit{node:root,..});if error!=blot_error::Error.none {return error;}while self_.visits.len!=0 {let visit=self_.visits.pop();let node=self_.nodes.items[visit.node];if visit.emit || node.arity==0 {let error=self_.code.push(node.instruction);if error!=blot_error::Error.none {return error;}continue;}let error=self_.visits.push(Visit{node:visit.node,emit:true,..});if error!=blot_error::Error.none {return error;}var index=node.arity as i64;while index>0 {index-=1;let error=self_.visits.push(Visit{node:node.children[index],..});if error!=blot_error::Error.none {return error;}}}return blot_error::Error.none;}
fn flush(self_:Builder&)->Error {for pending,index in self_.pending.items {let use .= self_.uses[pending.local];if use.pending!=index {continue;}let error=self_.emit(pending.node);if error!=blot_error::Error.none {return error;}let error=self_.code.push(pending.instruction);if error!=blot_error::Error.none {return error;}use.pending=absent;}for node in self_.stack.items {let error=self_.emit(node);if error!=blot_error::Error.none {return error;}}self_.pending.clear();self_.stack.clear();self_.nodes.clear();return blot_error::Error.none;}
fn barrier(self_:Builder&,instruction:Instruction)->Error {let error=self_.flush();if error!=blot_error::Error.none {return error;}return self_.code.push(instruction);}
fn numeric(ty:ValueType)->bool {return ty==blot_backend_runtime_ir::VT_i32 || ty==blot_backend_runtime_ir::VT_f32 || ty==blot_backend_runtime_ir::VT_v128;}
fn local(op:Op)->bool {return op==blot_backend_runtime_ir::OP_local_get || op==blot_backend_runtime_ir::OP_local_set || op==blot_backend_runtime_ir::OP_local_tee;}
fn admit(module:const Module&,source:const Function&,uses:Use[:],total:i64)->bool {var segment:i64=0;let parameters=module.parameters(source);let locals=module.locals(source);for inst in blot_backend_wasm::instructions(module,source) {if inst.op==blot_backend_runtime_ir::OP_ownership || inst.op==blot_backend_runtime_ir::OP_resource_retire || inst.op==blot_backend_runtime_ir::OP_wide_layouts {return false;}if !local(inst.op) {let contract=blot_backend_runtime_ir::fixed(inst.op);if contract.effect!=blot_backend_runtime_ir::EFFECT_pure || contract.may_trap || !numeric(contract.result) || inst.table_reference || inst.table_kind!=blot_backend_runtime_ir::TABLE_unknown {segment+=1;}continue;}if inst.operand>=total || inst.table_reference || inst.table_kind!=blot_backend_runtime_ir::TABLE_unknown {return false;}if inst.operand<parameters.len {if inst.op!=blot_backend_runtime_ir::OP_local_get || !numeric(parameters[inst.operand]) {segment+=1;}continue;}let use .= uses[inst.operand-parameters.len];if inst.op==blot_backend_runtime_ir::OP_local_get {if use.reads!=255 {use.reads+=1;}if use.definitions==0 {use.pinned=true;}if use.segment!=segment {use.crosses_barrier=true;}if !numeric(locals[inst.operand-parameters.len]) {segment+=1;}}else {if use.definitions!=255 {use.definitions+=1;}use.segment=segment;if inst.op==blot_backend_runtime_ir::OP_local_tee {use.pinned=true;segment+=1;}}}for use in uses {if use.candidate() && !use.crosses_barrier {return true;}}return false;}
fn run(module:const Module&,source:const Function&)->blot_support::Option<Output>,Error {let locals=module.locals(source);if locals.len==0 || locals.len>0x7fffffffffffffff-source.parameters.len {return blot_support::none<Output>(),blot_error::Error.none;}let total=source.parameters.len+locals.len;if total>0xffffffff {return blot_support::none<Output>(),blot_error::Error.none;}let uses=use_runs.alloc_slice(locals.len);for &use,index in uses {use=Use{pinned:!numeric(locals[index]),..};}if !admit(module,source,uses,total) {use_runs.free_slice(uses);return blot_support::none<Output>(),blot_error::Error.none;}var builder=Builder{uses:uses,..};let changed,error=build(module,source,builder);builder.deinit();use_runs.free_slice(uses);return blot_backend_optimizer_buffers::finishOptional(builder.locals,builder.code,changed,error);}
fn build(module:const Module&,source:const Function&,builder:Builder&)->bool,Error {let parameters=module.parameters(source);let locals=module.locals(source);for inst in blot_backend_wasm::instructions(module,source) {if inst.op==blot_backend_runtime_ir::OP_local_get {if inst.operand>=parameters.len {let use .= builder.uses[inst.operand-parameters.len];if use.pending!=absent {let node=builder.pending.items[use.pending].node;use.pending=absent;use.eliminated=true;let error=builder.stack.push(node);if error!=blot_error::Error.none {return false,error;}continue;}}var ty=blot_backend_runtime_ir::VT_none;if inst.operand<parameters.len {ty=parameters[inst.operand];}else {ty=locals[inst.operand-parameters.len];}if numeric(ty) {let error=builder.push(Node{instruction:inst,ty:ty,..});if error!=blot_error::Error.none {return false,error;}continue;}}else if inst.op==blot_backend_runtime_ir::OP_local_set && inst.operand>=parameters.len {let use .= builder.uses[inst.operand-parameters.len];if use.candidate() && builder.stack.len>0 && builder.nodes.items[builder.stack.items[builder.stack.len-1]].ty==locals[inst.operand-parameters.len] {let node=builder.stack.pop();use.pending=builder.pending.len;let error=builder.pending.push(Pending{local:inst.operand-parameters.len,node:node,instruction:inst,..});if error!=blot_error::Error.none {return false,error;}continue;}}else if !inst.table_reference && inst.table_kind==blot_backend_runtime_ir::TABLE_unknown {let contract=blot_backend_runtime_ir::fixed(inst.op);if contract.effect==blot_backend_runtime_ir::EFFECT_pure && !contract.may_trap && numeric(contract.result) && contract.arity<=builder.stack.len {var node=Node{instruction:inst,arity:contract.arity as u8,ty:contract.result,..};let start=builder.stack.len-contract.arity;var valid=true;for index in 0..contract.arity {node.children[index]=builder.stack.items[start+index];if builder.nodes.items[node.children[index]].ty!=contract.inputs[index] {valid=false;}}if valid {builder.stack.resize(start);let error=builder.push(node);if error!=blot_error::Error.none {return false,error;}continue;}}}let error=builder.barrier(inst);if error!=blot_error::Error.none {return false,error;}}let error=builder.flush();if error!=blot_error::Error.none {return false,error;}var eliminated:i64=0;for use in builder.uses {if use.eliminated {eliminated+=1;}}if eliminated==0 {return false,blot_error::Error.none;}var slots=blot_backend_optimizer_buffers::Words{..};let error=remap(builder,parameters.len,locals,slots);slots.deinit();return true,error;}
fn remap(builder:Builder&,parameters:i64,original:const ValueType[:],slots:blot_backend_optimizer_buffers::Words&)->Error {let error=slots.resize(builder.uses.len,0 as u32);if error!=blot_error::Error.none {return error;}for use,index in builder.uses {slots.items[index]=(parameters+builder.locals.len) as u32;if !use.eliminated {let error=builder.locals.push(original[index]);if error!=blot_error::Error.none {return error;}}}for &inst in builder.code.items {if local(inst.op) && inst.operand>=parameters {assert(!builder.uses[inst.operand-parameters].eliminated);inst.operand=slots.items[inst.operand-parameters];}}return blot_error::Error.none;}
