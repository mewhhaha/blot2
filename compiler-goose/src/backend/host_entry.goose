// Exact logical callable reads prove a public host callback cannot escape.
namespace blot_backend_host_entry;
import .wasm;
import .runtime_ir;
import support.option;
enum Value { ordinary,descriptor,environment,function }
struct State { stack: Value[256] = [Value.ordinary;256],top: i64 = 0,locals: Value[256] = [Value.ordinary;256] }
fn push(state: State&,value: Value) -> bool { if state.top == 256 { return false; } state.stack[state.top] = value; state.top++; return true; }
fn pop(state: State&) -> blot_support::Option<Value> { if state.top == 0 { return blot_support::none<Value>(); } state.top--; return blot_support::some(state.stack[state.top]); }
fn ordinary(state: State&) -> bool { let value = pop(state); return value.present && value.value == Value.ordinary; }
fn take(state: State&,wanted: Value) -> bool { let value = pop(state); return value.present && value.value == wanted; }
fn hostStub(module: const blot_backend_wasm::Module&,body: blot_backend_runtime_ir::Function) -> bool {
    if !module.host_references.present { return false; } let references = module.host_references.value; let code = module.instructions(body);
    if body.entry || code.len != 12 || code[11].op != blot_backend_runtime_ir::OP_call_import { return false; }
    let callback = module.hostCallbackImport(code[11].operand); if !callback.present { return false; }
    let parameters: blot_backend_runtime_ir::ValueType[3] = [blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::machine(callback.value.parameter),blot_backend_runtime_ir::VT_i32]; let roles: blot_backend_runtime_ir::Role[3] = [blot_backend_runtime_ir::ROLE_reference,blot_backend_runtime_ir::role(callback.value.parameter),blot_backend_runtime_ir::ROLE_reference];
    if body.result != blot_backend_runtime_ir::machine(callback.value.result) || body.result_role != blot_backend_runtime_ir::role(callback.value.result) || body.provider_parameter != 2 || !blot_backend_wasm::equal(module.parameters(body),parameters) || body.parameter_roles != blot_backend_runtime_ir::packParameterRoles(roles) { return false; }
    let marker = blot_backend_runtime_ir::Ownership { kind: blot_backend_runtime_ir::OWN_scope,chunk: 14 };
    let expected: blot_backend_runtime_ir::Instruction[12] = [
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_ownership,blot_backend_runtime_ir::pack(marker)),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get,references.active),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ne),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,8),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_host_ref_get),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,1),code[11],
    ];
    for actual,index in code { if actual != expected[index] { return false; } } return true;
}
fn confined(module: const blot_backend_wasm::Module&,target: u32,stub: u32,ty: u32,guard: blot_support::Option<u32>) -> bool {
    if target >= module.functions.len || stub >= module.functions.len || ty == 0 { return false; } let body = module.functions[target]; let callback = module.functions[stub];
    if body.entry || body.parameters.len != 2 || !blot_backend_wasm::equal(module.parameters(body),[blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::VT_i32]) || blot_backend_runtime_ir::parameterRole(body,0) != blot_backend_runtime_ir::ROLE_reference || body.provider_parameter != 1 { return false; }
    if body.locals.len > 254 || body.instructions.len > 4096 || callback.callable_layout != ty || !hostStub(module,callback) || callback.parameters.len != 3 || blot_backend_runtime_ir::parameterRole(callback,0) != blot_backend_runtime_ir::ROLE_reference || blot_backend_runtime_ir::parameterRole(callback,2) != blot_backend_runtime_ir::ROLE_reference { return false; }
    var state = State {}; state.locals[0] = Value.descriptor; let code = module.instructions(body); var at: i64 = 0; var invokes: i64 = 0;
    while at < code.len {
        let instruction = code[at]; let op = instruction.op;
        if op == blot_backend_runtime_ir::OP_local_get { if instruction.operand >= body.parameters.len + body.locals.len || !push(state,state.locals[instruction.operand]) { return false; } }
        else if op == blot_backend_runtime_ir::OP_local_set || op == blot_backend_runtime_ir::OP_local_tee {
            if instruction.operand < body.parameters.len || instruction.operand >= body.parameters.len + body.locals.len { return false; } let value = pop(state); if !value.present { return false; } state.locals[instruction.operand] = value.value; if op == blot_backend_runtime_ir::OP_local_tee && !push(state,value.value) { return false; }
        } else if op == blot_backend_runtime_ir::OP_i32_load {
            let address = pop(state); if !address.present { return false; } var value = Value.ordinary;
            if address.value == Value.descriptor {
                if instruction.operand == 0 { let layout,present = blot_backend_runtime_ir::callableCodeLayout(code,at); if !present || layout != ty { return false; } value = Value.function; }
                else if instruction.operand == 4 { value = Value.environment; } else { return false; }
            } else if address.value != Value.ordinary { return false; } if !push(state,value) { return false; }
        } else if op == blot_backend_runtime_ir::OP_call_indirect {
            if instruction.operand != callback.signature || blot_backend_runtime_ir::indirectResult(code,at) != callback.result_role || !take(state,Value.function) || !ordinary(state) || !ordinary(state) || !take(state,Value.environment) { return false; }
            if callback.result != blot_backend_runtime_ir::VT_none && !push(state,Value.ordinary) { return false; } invokes++;
        } else if op == blot_backend_runtime_ir::OP_call { return false; }
        else if op == blot_backend_runtime_ir::OP_global_get { assert(module.host_references.present); if instruction.operand == module.host_references.value.active || !push(state,Value.ordinary) { return false; } }
        else if op == blot_backend_runtime_ir::OP_ownership { let annotation = blot_backend_runtime_ir::ownership(instruction.operand); if annotation.kind == blot_backend_runtime_ir::OWN_scope && annotation.chunk != 0 && annotation.chunk != 1 { return false; } }
        else if op == blot_backend_runtime_ir::OP_block { if at != 0 || instruction.operand != body.result as u32 { return false; } }
        else if op == blot_backend_runtime_ir::OP_end { if at + 1 != code.len { return false; } }
        else if op == blot_backend_runtime_ir::OP_if_ {
            if !guard.present { return false; } let owner = guard.value;
            if at == 0 || at + 3 >= code.len || code[at - 1].op != blot_backend_runtime_ir::OP_global_get || code[at - 1].operand != owner || instruction.operand != 0 || code[at + 1].op != blot_backend_runtime_ir::OP_i32_const || code[at + 1].operand != 0 || code[at + 2].op != blot_backend_runtime_ir::OP_return_ || code[at + 3].op != blot_backend_runtime_ir::OP_end || !ordinary(state) { return false; } at += 3;
        } else if op == blot_backend_runtime_ir::OP_br { if at + 3 != code.len || instruction.operand != 0 || state.top != 1 || state.stack[0] != Value.ordinary { return false; } }
        else if op == blot_backend_runtime_ir::OP_unreachable_ { if at + 2 != code.len || at == 0 || code[at - 1].op != blot_backend_runtime_ir::OP_br { return false; } }
        else if op == blot_backend_runtime_ir::OP_call_import || op == blot_backend_runtime_ir::OP_return_ || op == blot_backend_runtime_ir::OP_loop || op == blot_backend_runtime_ir::OP_else_ || op == blot_backend_runtime_ir::OP_br_if || op == blot_backend_runtime_ir::OP_resource_retire { return false; }
        else {
            let contract = blot_backend_runtime_ir::contract(module,body,instruction); if contract.effect == blot_backend_runtime_ir::EFFECT_host || contract.effect == blot_backend_runtime_ir::EFFECT_control || contract.arity > 3 { return false; }
            for index in 0..contract.arity { if !ordinary(state) { return false; } } if contract.result != blot_backend_runtime_ir::VT_none && !push(state,Value.ordinary) { return false; }
        }
        at++;
    }
    return invokes != 0 && state.top == 1 && state.stack[0] == Value.ordinary;
}
