import std;
import backend.wasm_copy_coalesce;
import backend.runtime_ir;
import support.error;
fn I(op:blot_backend_runtime_ir::Op,operand:u32=0)->blot_backend_runtime_ir::Instruction {
    return blot_backend_runtime_ir::instruction(op,operand);
}
fn main() {
    var types:u8[>..<]=[];
    var instructions:blot_backend_runtime_ir::Instruction[>..<]=[];
    for cycle in 0..3 {
        types.push(blot_backend_runtime_ir::VT_i32);
        types.push(blot_backend_runtime_ir::VT_i32);
        let source=blot_backend_runtime_ir::Function{parameters:blot_backend_runtime_ir::Range{start:0,len:1},locals:blot_backend_runtime_ir::Range{start:1,len:1},instructions:blot_backend_runtime_ir::Range{start:0,len:4},..};
        instructions.push(I(blot_backend_runtime_ir::OP_local_get,0));
        instructions.push(I(blot_backend_runtime_ir::OP_local_set,1));
        instructions.push(I(blot_backend_runtime_ir::OP_local_get,1));
        instructions.push(I(blot_backend_runtime_ir::OP_drop));
        var single,error=blot_backend_wasm_copy_coalesce::runSingle(types[..],instructions[..],source);
        assert(error==blot_error::Error.none && single.present);
        assert(single.value.locals.len==0 && single.value.instructions.len==2);
        assert(single.value.instructions[0].op==blot_backend_runtime_ir::OP_local_get && single.value.instructions[0].operand==0);
        single.value.deinit();
        var detached,detached_error=blot_backend_runtime_ir::cloneBody([blot_backend_runtime_ir::VT_i32],instructions[..]);
        assert(detached_error==blot_error::Error.none);
        var borrowed=source;
        borrowed.borrowed_body=true;
        borrowed.borrowed_locals=detached.locals;
        borrowed.borrowed_instructions=detached.instructions;
        var borrowed_result,borrowed_error=blot_backend_wasm_copy_coalesce::runSingle(types[..],[],borrowed);
        assert(borrowed_error==blot_error::Error.none && borrowed_result.present);
        assert(borrowed_result.value.locals.len==0 && borrowed_result.value.instructions.len==2 && borrowed_result.value.instructions[0].operand==0);
        assert(detached.instructions.len==4 && detached.instructions[1].operand==1);
        borrowed_result.value.deinit();
        detached.deinit();
        instructions.clear();
        instructions.push(I(blot_backend_runtime_ir::OP_local_get,0));
        instructions.push(I(blot_backend_runtime_ir::OP_local_set,1));
        instructions.push(I(blot_backend_runtime_ir::OP_call,1));
        instructions.push(I(blot_backend_runtime_ir::OP_local_get,1));
        instructions.push(I(blot_backend_runtime_ir::OP_drop));
        var root=source;
        root.instructions.len=3;
        var helper=source;
        helper.instructions.start=3;
        helper.instructions.len=2;
        let bodies=[blot_backend_wasm_copy_coalesce::body(0,root),blot_backend_wasm_copy_coalesce::body(1,helper)];
        var selected,multi_error=blot_backend_wasm_copy_coalesce::run(types[..],instructions[..],root,bodies);
        assert(multi_error==blot_error::Error.none && selected.present);
        assert(selected.value.removed_copies==1 && selected.value.forwarded_reads==1);
        assert(selected.value.bodies[0].instructions.len==1 && selected.value.bodies[0].instructions[0].op==blot_backend_runtime_ir::OP_call);
        assert(selected.value.bodies[1].instructions.len==2 && selected.value.bodies[1].instructions[0].operand==0);
        selected.value.deinit();
        instructions.clear();
        instructions.push(I(blot_backend_runtime_ir::OP_local_get,0));
        instructions.push(I(blot_backend_runtime_ir::OP_local_set,1));
        instructions.push(I(blot_backend_runtime_ir::OP_i32_const,4));
        instructions.push(I(blot_backend_runtime_ir::OP_local_set,0));
        instructions.push(I(blot_backend_runtime_ir::OP_local_get,1));
        instructions.push(I(blot_backend_runtime_ir::OP_drop));
        var changed_source=source;
        changed_source.instructions.len=6;
        let declined,declined_error=blot_backend_wasm_copy_coalesce::runSingle(types[..],instructions[..],changed_source);
        assert(declined_error==blot_error::Error.none && !declined.present);
        types.clear();
        instructions.clear();
    }
    print("copy coalescing passed: single/cross-body forwarding, detached ownership, invalidation and three pool reuse cycles");
}
