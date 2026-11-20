// A variable's principal and historical views must survive rollback and
// suspension with the same node IDs and the same cursor semantics.
import check.types;
import check.effects;
import check.type_store_snapshot;
import support.error;

fn effectHistory() {
    let ok=blot_error::Error.none;
    var store,init=blot_check_effects::initWithOptions(blot_check_effects::Options{..});assert(init==ok);
    let row,error=store.fresh();assert(error==ok);
    let saved=store.mark();
    let future,err=store.resolve(row,5);assert(err==ok && store.node(future).cursor==5);
    let labelled,le=store.row([1 as u32],blot_check_effects::Tail.closed);assert(le==ok);
    match store.node(row).tail {
        variable v => {
            assert(store.appendVersionAt(v.value,0,2)==ok);
            assert(store.appendVersionAt(v.value,labelled,4)==ok);
        },
        _ => {assert(false);},
    }
    let first,e1=store.resolve(row,0);assert(e1==ok && first==0);
    let second,e2=store.resolve(row,3);assert(e2==ok && store.node(second).labels.len==1);
    let past,e3=store.resolve(future,0);assert(e3==ok && past==future);
    let later,e4=store.resolve(future,7);assert(e4==ok && store.node(later).cursor==7);
    store.rollback(saved);
    let reset,e5=store.resolve(row,0);assert(e5==ok && reset==row);
    store.deinit();
}

fn sharedSignatures() {
    let ok=blot_error::Error.none;
    var store,init_error=blot_check_types::init();assert(init_error==ok);
    let a,ae=store.fresh();let b,be=store.fresh();assert(ae==ok && be==ok);
    let future,fe=store.variableView(store.node(a).a,store.cursor()+1);assert(fe==ok && a!=future);
    let one,e1=store.product([a,b]);let two,e2=store.product([a,b]);assert(e1==ok && e2==ok);
    let swapped,e3=store.product([b,a]);let later,e4=store.product([future,b]);assert(e3==ok && e4==ok);
    let left,e5=store.record([blot_check_types::Field{1,one}]);let right,e6=store.record([blot_check_types::Field{1,two}]);
    let renamed,e7=store.record([blot_check_types::Field{2,one}]);assert(e5==ok && e6==ok && e7==ok);
    let output,oe=store.product([one,two,swapped,later,left,right,renamed]);assert(oe==ok);
    let inner,ie=store.function(b,output);let arrow,re=store.function(a,inner);assert(ie==ok && re==ok);
    let result,error=store.compactSignature(arrow);assert(error==ok && result!=arrow);
    let outer=store.node(result);assert(outer.a==a && outer.c==0);
    let nested=store.node(outer.b);assert(nested.a==b && nested.c==0);
    let shape=store.node(nested.b);let children=store.list(blot_check_types::List{shape.a,shape.b});
    assert(children==[one,one,swapped,later,left,left,renamed]);
    let original=store.node(output);
    assert(store.list(blot_check_types::List{original.a,original.b})==[one,two,swapped,later,left,right,renamed]);
    store.has_projections=true;
    let unchanged,pe=store.compactSignature(arrow);assert(pe==ok && unchanged==arrow);
    store.deinit();
}

// Rehash can move every remembered slot just before a sparse epoch ends.
fn rehashedResolutionCache() {
    for width in [6,22,32,33] {
        var map=blot_check_types::Map_projection_resolutions{..};
        for i in width {
            let key=blot_check_types::ProjectionResolution{i as u32,0,1,..};
            assert(map.insert(key,1));
            assert(!map.insert(key,2));
        }
        var restored=blot_check_types::Map_projection_resolutions{..};
        assert(restored.restore(map.slots,map.count)==blot_error::Error.none);
        map.clear(); restored.clear();
        for i in width {
            let key=blot_check_types::ProjectionResolution{i as u32,0,1,..};
            assert(map.insert(key,3) && restored.insert(key,3));
        }
        map.deinit(); restored.deinit();
    }
}

// A dense cache followed by short inference epochs must forget old results.
// The next dense phase and a restored live entry keep their exact charges.
fn sparseResolutionEpochs() {
    let ok=blot_error::Error.none;
    var store,init=blot_check_types::init();
    assert(init==ok);
    store.has_projections=true;
    var roots:u32[512]=[0;512];
    for &root in roots {
        let fresh,error=store.fresh();
        assert(error==ok);
        root=fresh;
    }
    for phase in 2 {
        for root,index in roots {
            let value,error=store.resolveDepth(root,0,1);
            var expected=root;
            if index<phase*64 {expected=blot_check_types::boolean;}
            assert(error==ok && value==expected);
        }
        for i in 64 {
            let changed=roots[phase*64+i];
            assert(store.appendVersion(changed,blot_check_types::boolean)==ok);
            let start=store.projection_steps;
            let value,error=store.resolveDepth(changed,0,1);
            assert(error==ok && value==blot_check_types::boolean && store.projection_steps==start+2);
            if i==63 {
                var snapshot,se=blot_check_type_store_snapshot::suspendStore(store);
                assert(se==ok && blot_check_type_store_snapshot::restoreStore(snapshot,store)==ok);
                assert(snapshot.deinit()==ok);
            }
            let cached,ce=store.resolveDepth(changed,0,1);
            assert(ce==ok && cached==value && store.projection_steps==start+3);
        }
    }
    store.deinit();
}

fn main() {
    rehashedResolutionCache();
    sparseResolutionEpochs();
    sharedSignatures();
    effectHistory();
    functionUnification();
    assert(selectionUnification(false)==blot_error::Error.type_limit);
    assert(selectionUnification(true)==blot_error::Error.type_limit);
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

// Selection interning matches scope identities. A shallow type may resolve to an
// older representative with a deep descriptor, and selection has its own node cap.
fn selectionUnification(fill_store:bool)->blot_error::Error {
    let ok=blot_error::Error.none;let unit=blot_check_types::unit;let never=blot_check_types::never;
    var s,init=blot_check_types::initWithOptions(blot_check_types::Options{closed_graphs:true,..});assert(init==ok);
    let a=blot_check_types::NominalIdentity{1,1};let b=blot_check_types::NominalIdentity{1,2};
    let sel=blot_check_types::NominalIdentity{2,1};
    var descriptor=unit;
    if !fill_store {for i in 0..1025 {let next,ne=s.sequence(blot_check_types::Tag.array,descriptor);assert(ne==ok);descriptor=next;}}
    let known,ke=s.scoped(descriptor,a);let other,oe=s.scoped(unit,b);assert(ke==ok && oe==ok);
    let first,fe=s.instanceSelection(sel,[known,other]);assert(fe==ok);
    let cap,ce=s.fresh();assert(ce==ok);
    let dynamic,de=s.scoped(unit,blot_check_types::NominalIdentity{0,cap});assert(de==ok);
    let proposal,pe=s.instanceSelection(sel,[dynamic,other]);assert(pe==ok && proposal!=first);
    let fixed,xe=s.scoped(unit,a);assert(xe==ok && s.appendVersion(cap,fixed)==ok);
    var left_arg=proposal;var right_arg=never;
    if fill_store {
        let x,te=s.fresh();assert(te==ok && s.appendVersion(x,never)==ok);
        left_arg=x;right_arg=proposal;
    }
    let left,le=s.function(left_arg,unit);let right,re=s.function(right_arg,unit);assert(le==ok && re==ok);
    if fill_store {while s.nodes.len<65535 {let unused,ue=s.function(unit,unit);assert(ue==ok);}}
    let result=s.unify(left,right);
    s.deinit();return result;
}
