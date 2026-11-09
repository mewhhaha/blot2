// Outline readers carry only a module borrow and a checked state key.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import driver.compile_workspace_backing;
import backend.wasm_scope_outline;
import support.error;
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
        assert(module.emit(function,blot_backend_runtime_ir::Instruction{op:blot_backend_runtime_ir::OP_end,..})==blot_error::Error.none);
        assert(context.sync(0)==blot_error::Error.none && !context.canRewriteSuffix(function,0));
        let stats,error=context.finalize();assert(error==blot_error::Error.none && stats.regions==0 && stats.globals==0);
        assert(!context.begin(function,blot_backend_wasm_scope_outline::Work{0,0}).present);
        context.deinit();assert(!context.live() && !stale.live());
        module.deinit();blot_compile_workspace::clearBacking();blot_compile_workspace::resetBackingDescriptors();
    }
    print("scope outline passed: checked state, roots, copy patching, finalization and cleanup");
}
