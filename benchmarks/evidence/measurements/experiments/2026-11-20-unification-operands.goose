// Thread CPU time in nanoseconds. Run as a main beside the compiler modules.
import check.types;
import support.error;
import support.native;

fn scalarPairs() -> u64 {
    let ok=blot_error::Error.none;
    var store,e=blot_check_types::initWithOptions(blot_check_types::Options{closed_graphs:true,..});assert(e==ok);
    let start=blot_native::thread_cpu_ns();
    for i in 100000 {assert(store.unify(blot_check_types::u32_type,blot_check_types::u32_type)==ok);}
    let elapsed=blot_native::thread_cpu_ns()-start;
    store.deinit();return elapsed;
}

fn openArrows(ranked:bool) -> u64 {
    let ok=blot_error::Error.none;
    var store,e=blot_check_types::initWithOptions(blot_check_types::Options{closed_graphs:true,..});assert(e==ok);
    if ranked {let region,re=store.freshRegion();assert(re==ok);}
    let x,xe=store.fresh();let effect,ee=store.freshEffects();assert(xe==ok && ee==ok);
    let left,le=store.functionWithEffects(blot_check_types::u32_type,x,effect);
    let right,re=store.functionWithEffects(blot_check_types::u32_type,x,effect);assert(le==ok && re==ok && left!=right);
    let outer,oe=store.function(blot_check_types::boolean,left);
    let other,te=store.function(blot_check_types::boolean,right);assert(oe==ok && te==ok);
    let start=blot_native::thread_cpu_ns();
    for i in 12000 {
        let variable,ve=store.fresh();assert(ve==ok);
        assert(store.unify(variable,blot_check_types::boolean)==ok);
        assert(store.unify(outer,other)==ok);
    }
    let elapsed=blot_native::thread_cpu_ns()-start;
    store.deinit();return elapsed;
}

fn main() {
    print(scalarPairs());
    print(openArrows(false));
    print(openArrows(true));
}
