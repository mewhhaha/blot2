namespace blot_backend_runtime_body_relocation;
import std;
import dictionary;
import .runtime_ir;
import .wasm;
import .runtime_function_key;
import support.option;
import support.wyhash;

struct Pair { before: u32, after: u32 }
enum Kind { function, import_, signature, global }
struct Key { kind: Kind, index: u32 }
fn hash(key: Key) -> u64 {
    var kind: u64 = 0;
    if key.kind == Kind.import_ { kind = 1; } else if key.kind == Kind.signature { kind = 2; } else if key.kind == Kind.global { kind = 3; }
    return ::hash((kind << 32) | key.index);
}
struct Walk {
    targets: dictionary<Key, u32>&, reverse: dictionary<Key, u32>&, pending: Pair[>..<]&, remaining: i64 = 1000000,
}
fn clear(walk: Walk&) { ::clear(walk.targets); ::clear(walk.reverse); walk.pending.clear(); }
fn spend(walk: Walk&, amount: i64) -> bool { if amount > walk.remaining { walk.remaining = 0; return false; } walk.remaining -= amount; return true; }
fn get(walk: Walk&, kind: Kind, before: u32) -> blot_support::Option<u32> {
    let found = ::get(walk.targets,Key { kind: kind, index: before , ..}); if found { return blot_support::some(found); } return blot_support::none<u32>();
}
fn add(walk: Walk&, kind: Kind, before: u32, after: u32) -> bool {
    if !spend(walk, 1) { return false; }
    let known = get(walk, kind, before); if known.present { return known.value == after; }
    if ::contains(walk.reverse,Key { kind: kind, index: after }) || walk.targets.count >= 4096 { return false; }
    ::insert(walk.targets,Key { kind: kind, index: before , ..}, after); ::insert(walk.reverse,Key { kind: kind, index: after , ..}, before);
    if kind == Kind.function { walk.pending.push(Pair { before: before, after: after , ..}); } return true;
}
fn reference(inst: blot_backend_runtime_ir::Instruction) -> bool {
    return inst.table_reference || inst.op == blot_backend_runtime_ir::OP_call || inst.op == blot_backend_runtime_ir::OP_call_import || inst.op == blot_backend_runtime_ir::OP_call_indirect || inst.op == blot_backend_runtime_ir::OP_global_get || inst.op == blot_backend_runtime_ir::OP_global_set;
}
fn referenceKind(inst: blot_backend_runtime_ir::Instruction) -> blot_support::Option<Kind> {
    if inst.table_reference || inst.op == blot_backend_runtime_ir::OP_call { return blot_support::some(Kind.function); }
    if inst.op == blot_backend_runtime_ir::OP_call_import { return blot_support::some(Kind.import_); }
    if inst.op == blot_backend_runtime_ir::OP_call_indirect { return blot_support::some(Kind.signature); }
    if inst.op == blot_backend_runtime_ir::OP_global_get || inst.op == blot_backend_runtime_ir::OP_global_set { return blot_support::some(Kind.global); }
    return blot_support::none<Kind>();
}
fn hash(module: blot_backend_wasm::Module&, function: blot_backend_runtime_ir::Function) -> u64 {
    var bytes: u8[>..] = [];
    blot_backend_runtime_function_key::appendWord(bytes, function.parameters.len as u64, 8); bytes.append(blot_backend_wasm::parameters(module, function)); bytes.push(function.result); bytes.push(function.result_role);
    var entry: u8 = 0; if function.entry { entry = 1; } bytes.push(entry);
    blot_backend_runtime_function_key::appendWord(bytes, function.parameter_roles, 8); bytes.push(function.provider_parameter); blot_backend_runtime_function_key::appendWord(bytes, function.callable_layout, 4);
    blot_backend_runtime_function_key::appendWord(bytes, function.locals.len as u64, 8); bytes.append(blot_backend_wasm::locals(module, function));
    for inst in blot_backend_wasm::instructions(module, function) {
        bytes.push(inst.op); var flag: u8 = 0; if inst.table_reference { flag = 1; } bytes.push(flag); bytes.push(inst.table_kind);
        if !reference(inst) { blot_backend_runtime_function_key::appendWord(bytes, inst.operand, 4); }
    }
    return blot_support_wyhash::hash(0, bytes);
}
fn equalLocal(before_module: blot_backend_wasm::Module&, before: blot_backend_runtime_ir::Function, after_module: blot_backend_wasm::Module&, after: blot_backend_runtime_ir::Function) -> bool {
    if before.result_role != after.result_role || before.entry != after.entry || before.parameter_roles != after.parameter_roles || before.provider_parameter != after.provider_parameter || before.callable_layout != after.callable_layout || before.result != after.result ||
       !blot_backend_wasm::equal(blot_backend_wasm::parameters(before_module, before), blot_backend_wasm::parameters(after_module, after)) ||
       !blot_backend_wasm::equal(blot_backend_wasm::locals(before_module, before), blot_backend_wasm::locals(after_module, after)) || before.instructions.len != after.instructions.len { return false; }
    let a = blot_backend_wasm::instructions(before_module, before); let b = blot_backend_wasm::instructions(after_module, after);
    for left, index in a { let right = b[index]; if left.op != right.op || left.table_reference != right.table_reference || left.table_kind != right.table_kind || (!reference(left) && left.operand != right.operand) { return false; } }
    return true;
}
