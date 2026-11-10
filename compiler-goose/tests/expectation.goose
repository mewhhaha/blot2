import std;
import support.u64_id_map;
import reuse.code_expectation;
import support.error;
fn main() {
    var nodes=blot_reuse_code_expectation::Nodes{..};
    var extra=blot_reuse_code_expectation::Ids{..};
    var next=blot_reuse_code_expectation::Ids{..};
    var buckets=blot_support_u64_id_map::Buckets{};
    for cycle in 0..3 {
        var store,error=blot_reuse_code_expectation::init(nodes,extra,next,buckets);
        assert(error==blot_error::Error.none);
        assert(nodes.len==6 && next.len==6 && extra.len==0);
        let nominal,error=store.intern(blot_eval_type_evidence::Tag.nominal,1,42,[0]);
        assert(error==blot_error::Error.none);
        let function,error=store.intern(blot_eval_type_evidence::Tag.function,0,nominal,[]);
        assert(error==blot_error::Error.none);
        let duplicate,error=store.intern(blot_eval_type_evidence::Tag.function,0,nominal,[]);
        assert(error==blot_error::Error.none && duplicate==function);
        assert(store.view().node(function).a==0 && store.view().children(nominal)==[0 as u32]);
        for ordinal in 0..128 {
            let bound,error=store.internBound(ordinal as u32,0,0);
            assert(error==blot_error::Error.none);
            assert(store.view().node(bound).a==ordinal);
        }
        let product,error=store.intern(blot_eval_type_evidence::Tag.product,0,0,[nominal,function]);
        assert(error==blot_error::Error.none);
        assert(store.view().children(product)==[nominal,function]);
        let quantified,error=store.intern(blot_eval_type_evidence::Tag.forall,function,2,[]);
        assert(error==blot_error::Error.none);
        assert(store.view().children(quantified).len==2);
        let rejected,error=store.intern(blot_eval_type_evidence::Tag.scoped,0,0,[]);
        assert(error==blot_error::Error.type_mismatch && rejected==0);
        store.deinit();
        assert(nodes.len==0 && extra.len==0 && next.len==0);
    }
    buckets.deinit();
    nodes.deinit();
    extra.deinit();
    next.deinit();
    print("code expectation passed:holes,interning,children,quantifiers,growth,reuse");
}
