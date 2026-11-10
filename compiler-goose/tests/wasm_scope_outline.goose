// Outline readers carry only a module borrow and a checked state key.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import driver.compile_workspace_backing;
import backend.wasm_scope_outline;
import backend.storage_deferred_join;
import support.error;
fn deferredCopies(module:blot_backend_wasm::Module&,function:u32,other:u32,context:blot_backend_wasm_scope_outline::Context&) {
 var code=blot_backend_runtime_code::Code<blot_backend_wasm::Module>{module:module,function:function,..};var mutable_words=blot_backend_scoped_backend::IndexSet{};
 var shared=blot_backend_storage_deferred_join::init(code);assert(shared.add(code,context,[blot_backend_runtime_code::Local{0}])==blot_error::Error.none);assert(shared.add(code,context,[blot_backend_runtime_code::Local{0}])==blot_error::Error.none);
 let controls=blot_backend_scoped_backend::Controls_runs.alloc_slice(1);controls[0]=blot_backend_scoped_backend::Control{result:blot_backend_scoped_backend::registeredJoin(blot_backend_scoped_backend::ValueJoin{physical:shared,..}),..};shared=blot_backend_storage_deferred_join::Join{entry_locals:0,..};
 let count,error=controls[0].result.physical.finish(code,context,mutable_words,false);assert(error==blot_error::Error.none && count==2 && controls[0].result.physical.word(0).id==0);controls[0].result.physical.deinit();blot_backend_scoped_backend::Controls_runs.free_slice(controls);
 var distinct=blot_backend_storage_deferred_join::init(code);assert(distinct.add(code,context,[blot_backend_runtime_code::Local{0}])==blot_error::Error.none);assert(distinct.add(code,context,[blot_backend_runtime_code::Local{other}])==blot_error::Error.none);
 let count,error=distinct.finish(code,context,mutable_words,false);assert(error==blot_error::Error.none && count==0 && distinct.word(0).id!=0 && distinct.word(0).id!=other);distinct.deinit();mutable_words.deinit();
}
fn main() {
    var inactive=blot_backend_wasm_scope_outline::Context{..};
    assert(!inactive.live() && !inactive.rootIndex(0).present && !inactive.begin(0,blot_backend_wasm_scope_outline::Work{0,0}).present);
    inactive.deinit();
    for cycle in 0..4 {
        let module:blot_backend_wasm::Module& =blot_compile_workspace::backing_generator_module;
        module.memory_model=blot_backend_wasm::MemoryModel.data_stacks;
        let function,error=module.addFunction([blot_backend_runtime_ir::VT_i32],blot_backend_runtime_ir::VT_none);assert(error==blot_error::Error.none);
        let local,error=module.addLocal(function,blot_backend_runtime_ir::VT_i32);assert(error==blot_error::Error.none);
        var context=blot_backend_wasm_scope_outline::init(module,blot_backend_wasm_scope_outline::Contract.scoped_numeric_adapter_nonreentrant,blot_backend_wasm_scope_outline::Options{..});
        let stale=context;assert(context.live() && context.registerRoot(function)==blot_error::Error.none && context.rootIndex(function).value==0);
        let ticket=context.begin(function,blot_backend_wasm_scope_outline::Work{10,20});assert(ticket.present);
        let copy_index,error=context.reserveCopy(function);assert(error==blot_error::Error.none && context.releaseCopy(function,copy_index)==blot_error::Error.none);
        let patched,error=context.reserveCopy(function);assert(error==blot_error::Error.none && context.patchCopy(function,patched,0,local)==blot_error::Error.none);
        deferredCopies(module,function,local,context);
        assert(module.emit(function,blot_backend_runtime_ir::Instruction{op:blot_backend_runtime_ir::OP_end,..})==blot_error::Error.none);
        assert(context.sync(0)==blot_error::Error.none && !context.canRewriteSuffix(function,0));
        let stats,error=context.finalize();assert(error==blot_error::Error.none && stats.regions==0 && stats.globals==0);
        assert(!context.begin(function,blot_backend_wasm_scope_outline::Work{0,0}).present);
        context.deinit();assert(!context.live() && !stale.live());
        module.deinit();blot_compile_workspace::clearBacking();blot_compile_workspace::resetBackingDescriptors();
    }
    print("scope outline passed: checked state, roots, copy patching, finalization and cleanup");
}
