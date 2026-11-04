namespace blot_backend_wasm_local_order;
import .runtime_ir;

fn local(op: blot_backend_runtime_ir::Op) -> bool { op == blot_backend_runtime_ir::OP_local_get || op == blot_backend_runtime_ir::OP_local_set || op == blot_backend_runtime_ir::OP_local_tee }
fn uleb(value: i64) -> u64 { var rest = value; var bytes: u64 = 1; while rest >= 128 { rest >>= 7; bytes++; } return bytes; }
fn declarationBytes(types: const blot_backend_runtime_ir::ValueType[:], order: const u32[:], ordered: bool) -> u64 {
    var groups = 0; var bytes: u64 = 0; var start = 0;
    while start < types.len {
        var first = start; if ordered { first = order[start]; }
        var end = start + 1;
        while end < types.len { var next = end; if ordered { next = order[end]; } if types[next] != types[first] { break; } end++; }
        groups++; bytes += uleb(end - start) + 1; start = end;
    }
    return uleb(groups) + bytes;
}
// Destination buffers are caller-owned. A decline publishes no output.
fn run(parameters: i64, types: const blot_backend_runtime_ir::ValueType[:], instructions: const blot_backend_runtime_ir::Instruction[:], output_locals: blot_backend_runtime_ir::ValueType[>..<]&, output_code: blot_backend_runtime_ir::Instruction[>..<]&) -> bool {
    let count = types.len; if count < 2 { return false; }
    let total = parameters + count;
    if total > 4294967295 || instructions.len > 4294967295 || uleb(parameters) == uleb(total - 1) { return false; }
    for inst in instructions {
        if inst.op == blot_backend_runtime_ir::OP_ownership || inst.op == blot_backend_runtime_ir::OP_resource_retire || inst.op == blot_backend_runtime_ir::OP_wide_layouts { return false; }
        if local(inst.op) && inst.operand >= total { return false; }
    }
    var weights: u32[>..<] = []; var order: u32[>..<] = []; var mapping: u32[>..<] = [];
    for index in 0..count { weights.push(0); order.push(index as u32); mapping.push(0); }
    for inst in instructions { if local(inst.op) && inst.operand >= parameters { weights[inst.operand - parameters]++; } }
    // Stable merge sort keeps equal-frequency locals in source order.
    var scratch: u32[>..<] = []; for index in 0..count { scratch.push(0); }
    var width = 1;
    while width < count {
        var start = 0;
        while start < count {
            var middle = start + width; if middle > count { middle = count; }
            var end = middle + width; if end > count { end = count; }
            var left = start; var right = middle;
            for target in start..end {
                var take_left = left < middle;
                if take_left && right < end { take_left = weights[order[left]] > weights[order[right]] || (weights[order[left]] == weights[order[right]] && order[left] < order[right]); }
                if take_left { scratch[target] = order[left]; left++; } else { scratch[target] = order[right]; right++; }
            }
            start = end;
        }
        for index in 0..count { order[index] = scratch[index]; }
        width *= 2;
    }
    var before = declarationBytes(types, [], false); var after = declarationBytes(types, order, true);
    for original, next in order { before += weights[original] as u64 * uleb(parameters + original); after += weights[original] as u64 * uleb(parameters + next); }
    if after >= before { return false; }
    output_locals.clear(); output_code.clear();
    for original, next in order { mapping[original] = (parameters + next) as u32; output_locals.push(types[original]); }
    for inst in instructions { var output = inst; if local(inst.op) && inst.operand >= parameters { output.operand = mapping[inst.operand - parameters]; } output_code.push(output); }
    return true;
}
