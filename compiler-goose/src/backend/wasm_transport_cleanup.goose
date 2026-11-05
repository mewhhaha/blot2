// Source coordinates remain against the immutable body during transport cleanup.
namespace blot_backend_wasm_transport_cleanup;
import .runtime_ir;
import .wasm;
import .optimizer_buffers;
import support.error;
import support.option;
type Error=blot_error::Error;
type Instruction=blot_backend_runtime_ir::Instruction;
type Output=blot_backend_runtime_ir::DetachedBody;
type Code=blot_backend_optimizer_buffers::Code;
type Types=blot_backend_optimizer_buffers::Types;
enum Pair {keep,remove,tee}
fn neutral(inst:Instruction)->bool {return !inst.table_reference && inst.table_kind==blot_backend_runtime_ir::TABLE_unknown;}
fn pair(first:Instruction,second:Instruction)->Pair {if first.operand!=second.operand || !neutral(first) || !neutral(second) {return Pair.keep;}if first.op==blot_backend_runtime_ir::OP_local_get && second.op==blot_backend_runtime_ir::OP_local_set {return Pair.remove;}if first.op==blot_backend_runtime_ir::OP_local_set && second.op==blot_backend_runtime_ir::OP_local_get {return Pair.tee;}return Pair.keep;}
fn rewrite(code:const Instruction[:],output:Code?)->i64,Error {var pending=blot_support::none<Instruction>();var length:i64=0;var at:i64=0;while at<code.len {if at+1<code.len && pair(code[at],code[at+1])==Pair.remove {at+=2;continue;}let inst=code[at];at+=1;if inst.op==blot_backend_runtime_ir::OP_nop && neutral(inst) {continue;}if pending.present {let previous=pending.value;if pair(previous,inst)==Pair.tee {pending.value.op=blot_backend_runtime_ir::OP_local_tee;continue;}let out .= output;if out {let error=out.push(previous);if error!=Error.none {return 0,error;}}length+=1;}pending=blot_support::some(inst);}if pending.present {let out .= output;if out {let error=out.push(pending.value);if error!=Error.none {return 0,error;}}length+=1;}return length,Error.none;}
fn run(module:const blot_backend_wasm::Module&,source:const blot_backend_runtime_ir::Function&)->blot_support::Option<Output>,Error {let code=module.instructions(source);let locals=module.locals(source);if locals.len>0x7fffffffffffffff-source.parameters.len {return blot_support::none<Output>(),Error.none;}let total=source.parameters.len+locals.len;for inst in code {match inst.op {blot_backend_runtime_ir::OP_ownership,blot_backend_runtime_ir::OP_resource_retire=>{return blot_support::none<Output>(),Error.none;},blot_backend_runtime_ir::OP_local_get,blot_backend_runtime_ir::OP_local_set,blot_backend_runtime_ir::OP_local_tee=>{if inst.operand>=total {return blot_support::none<Output>(),Error.none;}},_=>{},}}let length,error=rewrite(code,null);if error!=Error.none || length==code.len {return blot_support::none<Output>(),error;}var copied=Types{..};var result=Code{..};let error=copied.append(locals);if error!=Error.none {return blot_backend_optimizer_buffers::finishOptional(copied,result,false,error);}let error=result.ensure(length);if error!=Error.none {return blot_backend_optimizer_buffers::finishOptional(copied,result,false,error);}let written,error=rewrite(code,result);if error==Error.none {assert(written==length);}return blot_backend_optimizer_buffers::finishOptional(copied,result,true,error);}
