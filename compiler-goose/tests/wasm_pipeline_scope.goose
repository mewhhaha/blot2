import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.wasm;
import backend.runtime_pipeline;
import support.error;
fn observeDecoded(count: u32&,module: blot_backend_wasm::Module&) -> blot_error::Error {
    assert(module.functions.len == 1);
    let function = module.functions[0];
    assert(module.parameters(function) == [blot_backend_runtime_ir::VT_i32]);
    assert(module.locals(function) == [blot_backend_runtime_ir::VT_i32]);
    let code = blot_backend_wasm::instructions(module,function);
    assert(code.len == 2 && code[0].op == blot_backend_runtime_ir::OP_i32_const && code[0].operand == 42 && code[1].op == blot_backend_runtime_ir::OP_end);
    count++;
    return blot_error::Error.none;
}
fn profileDigests(module: const blot_backend_wasm::Module&) {
    var source_profile = blot_backend_memory_profile::Profile{module:module,..};
    var source_bodies: blot_backend_wasm::Prepared[1] = [blot_backend_wasm::Prepared{..}];
    assert(source_profile.bind(source_bodies[..]) == blot_error::Error.none);
    let function = module.functions[0];
    var detached,error = blot_backend_runtime_ir::cloneBody(module.locals(function),blot_backend_wasm::instructions(module,function));
    assert(error == blot_error::Error.none);
    var detached_bodies: blot_backend_wasm::Prepared[1] = [blot_backend_wasm::Prepared{body:blot_support::Option<blot_backend_runtime_ir::DetachedBody>{true,detached},..}];
    var equal_profile = blot_backend_memory_profile::Profile{module:module,..};
    assert(equal_profile.bind(detached_bodies[..]) == blot_error::Error.none && equal_profile.identity == source_profile.identity);
    detached.instructions[0].operand = 43;
    var changed_profile = blot_backend_memory_profile::Profile{module:module,..};
    assert(changed_profile.bind(detached_bodies[..]) == blot_error::Error.none && changed_profile.identity != source_profile.identity);
    changed_profile.deinit(); equal_profile.deinit(); source_profile.deinit(); detached.deinit();
}
fn assembleCase(mode: u32) {
    let nonempty = mode != 0;
    var types: blot_backend_wasm::ValueType[>..<] = [];
    var instructions: blot_backend_wasm::Instruction[>..<] = [];
    var names: u8[>..<] = [];
    var functions: blot_backend_wasm::Function[>..<] = [];
    var signatures: blot_backend_wasm::Signature[>..<] = [];
    var imports: blot_backend_wasm::Import[>..<] = [];
    var globals: blot_backend_wasm::Global[>..<] = [];
    var exports: blot_backend_wasm::Export[>..<] = [];
    var data: u8[>..<] = [];
    var static_fields: u32[>..<] = [];
    var table_functions: u32[>..<] = [];
    var table_origins: blot_backend_wasm::TableOrigin[>..<] = [];
    var semantic_sites: blot_backend_wasm::SemanticSite[>..<] = [];
    var module = blot_backend_wasm::init(types,instructions,names,functions,signatures,imports,globals,exports,data,static_fields,table_functions,table_origins,semantic_sites);
    module.memory_model = blot_backend_wasm::MemoryModel.data_stacks;
    if nonempty {
        let function,error = module.addTypedFunction([blot_backend_runtime_ir::VT_i32],blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::ROLE_scalar);
        assert(error == blot_error::Error.none);
        let local,local_error = module.addLocal(function,blot_backend_runtime_ir::VT_i32); assert(local_error == blot_error::Error.none && local == 1);
        assert(module.emit(function,blot_backend_runtime_ir::Instruction{op:blot_backend_runtime_ir::OP_i32_const,operand:42,..}) == blot_error::Error.none);
        assert(module.emit(function,blot_backend_runtime_ir::Instruction{op:blot_backend_runtime_ir::OP_end,..}) == blot_error::Error.none);
    }
    // Mode 2 requires a collector certificate from the unchecked assembly API.
    if mode != 2 {
        var session,error = blot_backend_runtime_pipeline::init(module);
        assert(error == blot_error::Error.none && session.module .== module && !session.roots);
        if nonempty { let body,error = session.optimize(0); assert(error == blot_error::Error.none); if body.present { var owned = body.value; owned.deinit(); } }
        session.deinit(); assert(session.module == null);
    }
    var output: u8[>..<] = [];
    var stats = blot_backend_optimized_bodies::Stats{..};
    let assembled = module.assembleWithOptions(blot_backend_wasm::AssembleOptions{require_collector_free:mode == 2,workers:1,stats:stats,..},output);
    if mode == 2 { assert(assembled == blot_error::Error.collector_free_unproven); }
    else {
        assert(assembled == blot_error::Error.none && output.len >= 8);
        assert(output[0] == 0 && output[1] == 97 && output[2] == 115 && output[3] == 109 && output[4] == 1);
        assert(stats.functions == module.functions.len);
    }
    if mode == 1 {
        profileDigests(module);
        let image = blot_backend_runtime_job::capture(module);
        var packet: u8[>..<] = [];
        assert(blot_backend_runtime_job::encode(module,packet) == blot_error::Error.none);
        module.deinit();
        // Reuse the retired source buffers before reading either owned image.
        types.push(blot_backend_runtime_ir::VT_f32);
        instructions.push(blot_backend_runtime_ir::Instruction{op:blot_backend_runtime_ir::OP_i32_const,operand:99,..});
        var observed: u32 = 0;
        assert(blot_backend_runtime_job::withModule(image,observed,observeDecoded) == blot_error::Error.none);
        assert(blot_backend_runtime_job::decodeWithModule(packet[..],observed,observeDecoded) == blot_error::Error.none);
        assert(observed == 2);
    } else { module.deinit(); }
}
fn main() {
    for cycle in 0..3 { assembleCase(0); assembleCase(1); assembleCase(2); }
    print("Wasm pipeline scope passed: empty/nonempty assembly, collector rejection cleanup, owned packet round trips, profile digests, repeated scratch cleanup");
}
