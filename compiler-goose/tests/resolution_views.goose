// A variable's principal and historical views must survive rollback and
// suspension with the same node IDs and the same cursor semantics.
import check.types;
import check.type_store_snapshot;
import support.error;

fn main() {
    let ok=blot_error::Error.none;
    var store,init_error=blot_check_types::initWithOptions(blot_check_types::Options{closed_graphs:true,..});
    assert(init_error==ok);
    let root,created=store.fresh();assert(created==ok);
    let index=store.node(root).a;
    let clock=store.cursor();
    let initial,initial_error=store.variableView(index,clock);
    assert(initial_error==ok && initial==root);
    let future,future_error=store.variableView(index,clock+1);
    assert(future_error==ok && future!=root);

    let original=store.mark();
    assert(store.appendVersion(root,blot_check_types::u32_type)==ok);
    let first,e1=store.resolve(root,clock);assert(e1==ok && first==blot_check_types::u32_type);
    let later,e2=store.resolve(root,clock+1);assert(e2==ok && later==future);
    let record,e3=store.record([blot_check_types::Field{1,root},blot_check_types::Field{2,future}]);
    assert(e3==ok);
    let resolved,e4=store.resolve(record,0);assert(e4==ok);
    let shape=store.node(resolved);
    assert(store.recordField(shape,0).ty==blot_check_types::u32_type && store.recordField(shape,1).ty==future);

    var snapshot,se=blot_check_type_store_snapshot::suspendStore(store);assert(se==ok);
    assert(blot_check_type_store_snapshot::restoreStore(snapshot,store)==ok);
    assert(snapshot.deinit()==ok);
    let resumed,e5=store.variableView(index,0);assert(e5==ok && resumed==root);
    let resumed_later,e6=store.variableView(index,clock+1);assert(e6==ok && resumed_later==future);
    store.rollback(original);
    let unbound,e7=store.resolve(root,0);assert(e7==ok && unbound==root);
    assert(store.appendVersion(root,blot_check_types::boolean)==ok);
    let rebound,e8=store.resolve(root,0);assert(e8==ok && rebound==blot_check_types::boolean);
    let limit=store.resolution_depth_limit;
    store.resolution_depth_limit=1;
    let deep,de=blot_check_types::resolveDepth(store,blot_check_types::u32_type,0,1);assert(de==blot_error::Error.type_limit);
    store.resolution_depth_limit=limit;
    store.deinit();
}
