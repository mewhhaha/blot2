namespace blot_backend_runtime_function_key;
import .runtime_ir;
import .wasm;
import support.wyhash;

fn equal(left_module: blot_backend_wasm::Module&, left: blot_backend_runtime_ir::Function, right_module: blot_backend_wasm::Module&, right: blot_backend_runtime_ir::Function) -> bool {
    if left.result != right.result || !blot_backend_wasm::equal(blot_backend_wasm::parameters(left_module, left), blot_backend_wasm::parameters(right_module, right)) || !blot_backend_wasm::equal(blot_backend_wasm::locals(left_module, left), blot_backend_wasm::locals(right_module, right)) { return false; }
    let left_code = blot_backend_wasm::instructions(left_module, left); let right_code = blot_backend_wasm::instructions(right_module, right); var i = 0; var j = 0;
    loop {
        while i < left_code.len && left_code[i].op == blot_backend_runtime_ir::OP_ownership { i++; }
        while j < right_code.len && right_code[j].op == blot_backend_runtime_ir::OP_ownership { j++; }
        if i == left_code.len || j == right_code.len { return i == left_code.len && j == right_code.len; }
        let a = left_code[i]; let b = right_code[j];
        if a.op != b.op || a.operand != b.operand || a.table_reference != b.table_reference || a.table_kind != b.table_kind || a.origin != b.origin { return false; }
        i++; j++;
    }
}
fn hash(module: blot_backend_wasm::Module&, function: blot_backend_runtime_ir::Function) -> u64 {
    var bytes: u8[>..] = [];
    appendWord(bytes, function.parameters.len as u64, 8); bytes.append(blot_backend_wasm::parameters(module, function)); bytes.push(function.result);
    appendWord(bytes, function.locals.len as u64, 8); bytes.append(blot_backend_wasm::locals(module, function));
    for inst in blot_backend_wasm::instructions(module, function) {
        if inst.op == blot_backend_runtime_ir::OP_ownership { continue; }
        bytes.push(inst.op); appendWord(bytes, inst.operand, 4); var flag: u8 = 0; if inst.table_reference { flag = 1; } bytes.push(flag);
    }
    return blot_support_wyhash::hash(0, bytes);
}
fn appendWord(bytes: u8[>..]&, value: u64, width: i64) { for index in 0..width { bytes.push((value >> (index * 8)) as! u8); } }
