// A variable's principal and historical views must survive rollback and
// suspension with the same node IDs and the same cursor semantics.
import check.types;
import check.effects;
import check.type_store_snapshot;
import support.error;

fn main() {
    functionUnification();
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

fn arrow(store:blot_check_types::Store&,a:u32,b:u32,r:u32=0)->u32 {
    let id,error=store.functionWithEffects(a,b,r);
    assert(error==blot_error::Error.none);return id;
}

fn functionUnification() {
    let ok=blot_error::Error.none;
    let u=blot_check_types::u32_type;let b=blot_check_types::boolean;let unit=blot_check_types::unit;
    var store,init=blot_check_types::initWithOptions(blot_check_types::Options{closed_graphs:true,..});
    assert(init==ok);
    let x,xe=store.fresh();assert(xe==ok);
    let shared=arrow(store,x,x);
    let conflict=arrow(store,u,b);
    let checkpoint=store.mark();
    assert(store.unify(shared,conflict)==blot_error::Error.type_mismatch);
    assert(store.cursor()==checkpoint.effects.next_position && store.versions.len==checkpoint.versions);
    let unbound,e0=store.resolve(x,0);assert(e0==ok && unbound==x);
    let equals=arrow(store,b,b);
    assert(store.unify(shared,equals)==ok);
    let fixed,e1=store.resolve(x,0);assert(e1==ok && fixed==b);

    // A parent alias created between writes selects a later child and a later effect.
    let child,ce=store.fresh();let alias,ae=store.fresh();assert(ce==ok && ae==ok);
    let row,re=store.freshEffects();let open,oe=store.freshEffects();assert(re==ok && oe==ok);
    let signature=arrow(store,child,child,row);
    match store.effects.node(row).tail {
        variable v => {
            assert(store.effects.appendVersion(v.value,0)==ok);
            assert(store.appendVersion(child,u)==ok);
            assert(store.appendVersion(alias,signature)==ok);
            assert(store.effects.appendVersion(v.value,open)==ok);
            assert(store.appendVersion(child,b)==ok);
        },
        _ => {assert(false);},
    }
    let old_case=arrow(store,u,u);
    assert(store.unify(signature,old_case)==ok);
    let wrong=store.mark();
    assert(store.unify(alias,old_case)==blot_error::Error.type_mismatch);
    assert(store.cursor()==wrong.effects.next_position && store.versions.len==wrong.versions);
    assert(store.unify(alias,equals)==ok);
    let closed,e2=store.resolveEffects(open,0);assert(e2==ok && closed==0);

    // The parameter closes the shared effect. The result requires that same
    // effect to contain Foreign and must fail, rolling back both effect stores.
    let tail,te=store.freshEffects();assert(te==ok);
    let foreign,fe=store.effects.row([blot_check_types::foreign_operation],blot_check_effects::Tail.closed);assert(fe==ok);
    let effectful=arrow(store,unit,unit,tail);
    let left=arrow(store,effectful,effectful);
    let pure=arrow(store,unit,unit);
    let impure=arrow(store,unit,unit,foreign);
    let right=arrow(store,pure,impure);
    let mark=store.mark();
    assert(store.unify(left,right)==blot_error::Error.effect_mismatch);
    assert(store.effects.versions.len==mark.effects.versions && store.cursor()==mark.effects.next_position);
    let retained,e3=store.resolveEffects(tail,0);assert(e3==ok && retained==tail);
    store.deinit();
}
