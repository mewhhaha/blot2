// Receipt admission keeps only validated scalar authority, including shared owners.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import reuse.dependency_closure;
import reuse.dependency_payload;
import reuse.frozen_dependency;
import backend.runtime_identity;
import support.error;
import driver.compile_workspace;
import support.native;
type FrozenModule=blot_reuse_frozen_dependency::Module;
fn receiptBorrow() {
    var owner,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
    let symbols,error=blot_reuse_dependency_payload::alloc<blot_reuse_frozen_dependency::Symbol>(owner,1);assert(error==blot_error::Error.none);
    symbols[0]=blot_reuse_frozen_dependency::Symbol{text:default<u8[:]>()};
    let modules,error=blot_reuse_dependency_payload::alloc<FrozenModule>(owner,0);assert(error==blot_error::Error.none);
    let graph=blot_reuse_frozen_dependency::FrozenDependency{symbols,modules};
    let invalid=default<blot_reuse_frozen_dependency::FrozenDependency>();
    let rejected,error=blot_reuse_dependency_closure::completedCoreValidation(invalid,owner);assert(error==blot_error::Error.invalid_artifact && rejected==null && owner.unique());
    let receipt,error=blot_reuse_dependency_closure::completedCoreValidation(graph,owner);assert(error==blot_error::Error.none && receipt);
    let alternate_symbols,error=blot_reuse_dependency_payload::alloc<blot_reuse_frozen_dependency::Symbol>(owner,1);assert(error==blot_error::Error.none);alternate_symbols[0]=blot_reuse_frozen_dependency::Symbol{text:default<u8[:]>()};
    let alternate_modules,error=blot_reuse_dependency_payload::alloc<FrozenModule>(owner,1);assert(error==blot_error::Error.none);alternate_modules[0]=default<FrozenModule>();
    var shared,error=owner.retain();assert(error==blot_error::Error.none && !owner.unique());
    let admitted=receipt.borrow(graph);assert(admitted.receipt.slot==receipt.slot && admitted.receipt.generation==receipt.generation);
    let symbol_graph=blot_reuse_frozen_dependency::FrozenDependency{alternate_symbols,modules};let wrong_symbols=receipt.borrow(symbol_graph);assert(wrong_symbols.receipt.slot==0);
    let module_graph=blot_reuse_frozen_dependency::FrozenDependency{symbols,alternate_modules};let wrong_modules=receipt.borrow(module_graph);assert(wrong_modules.receipt.slot==0);
    var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
    assert(blot_reuse_dependency_closure::validReceipt(admitted.receipt) && receipt.borrow(graph).receipt.slot==receipt.slot);
    let stale=admitted.receipt;receipt.deinit();
    assert(!blot_reuse_dependency_closure::validReceipt(stale));
    assert(stale.borrow(graph).receipt.slot==0);
    assert(admitted.prefix(default<blot_check_core::Module[:]>(),0,default<blot_backend_runtime_identity::View>())==0);
    shared.deinit();owner.deinit();
}
fn main() {for cycle in 0..3 {receiptBorrow();}}
