import check.capability_contracts;
import support.error;

type Term = blot_check_capability_contracts::Term;
type View = blot_check_capability_contracts::View;

fn instantiation() {
    var store,error=blot_check_capability_contracts::init();
    assert(error==blot_error::Error.none);
    var terms:Term[4096]=default<Term[4096]>();
    var fields:u32[2]=[7000,1];
    var arguments:u32[1]=[0];
    terms[1]=Term{blot_check_capability_contracts::Tag.parameter,0,..};
    for root in [0 as u32,31 as u32,32 as u32,4095 as u32] {
        if root!=0 {terms[root]=Term{blot_check_capability_contracts::Tag.record,0,2,..};}
        let recipe=blot_check_capability_contracts::Recipe{1,root,terms[..root+1],fields[..]};
        let before=store.visits;
        let result,failure=store.instantiate(recipe,arguments[..]);
        assert(failure==blot_error::Error.none);
        if root==0 {assert(result==0 && store.visits==before);}
        else {
            let term=store.nodes.items[result];
            assert(term.tag==blot_check_capability_contracts::Tag.record);
            let children=store.view().children(term);
            assert(children.len==2 && children[0]==7000 && children[1]==0);
            assert(store.visits==before+2);
        }
    }

    let large=blot_check_capability_contracts::Recipe{1,4095,terms[..],fields[..]};
    let saved=store.mark();
    store.limits.visits=store.visits+1;
    let _,limited=store.instantiate(large,arguments[..]);
    assert(limited==blot_error::Error.capability_analysis_limit && store.mark()==saved);
    // The portable recipe is validated in full even when the selected root is small.
    terms[4095]=Term{blot_check_capability_contracts::Tag.wrapped,4095,..};
    let bad=blot_check_capability_contracts::Recipe{1,1,terms[..],fields[..]};
    let _,invalid=store.instantiate(bad,arguments[..]);
    assert(invalid==blot_error::Error.invalid_capability_contract && store.mark()==saved);
    store.deinit();
}

fn main() {
    instantiation();
    let ok = blot_error::Error.none;
    let invalid = blot_error::Error.invalid_capability_contract;
    var nodes: Term[33] = default<Term[33]>();
    var words: u32[65] = [0; 65];

    // The same argument is legal under arity 16 and illegal under arity 1.
    nodes[1] = Term {blot_check_capability_contracts::Tag.argument, 15, ..};
    nodes[2] = Term {blot_check_capability_contracts::Tag.callable, 16, 0, 1};
    nodes[3] = Term {blot_check_capability_contracts::Tag.callable, 1, 0, 1};
    nodes[4] = Term {blot_check_capability_contracts::Tag.product, 0, 2, ..};
    words[0] = 2; words[1] = 3;
    for count in [5 as i64, 33 as i64] {
        let view = View {nodes[..count], words[..2]};
        assert(view.validate(2, 0, true) == ok);
        assert(view.validate(4, 0, true) == invalid);
    }

    // Word slots may be shared only when both uses agree on their role.
    words[0] = 1; words[1] = 0;
    nodes[3] = Term {blot_check_capability_contracts::Tag.record, 0, 2, ..};
    nodes[4] = Term {blot_check_capability_contracts::Tag.product, 0, 1, ..};
    let large = View {nodes[..], words[..]};
    assert(large.validate(0, 0, true) == invalid);
    nodes[4] = Term {blot_check_capability_contracts::Tag.product, 1, 1, ..};
    assert(large.validate(0, 0, true) == ok);
    let no_words = View {nodes[..], words[..0]};
    nodes[3] = Term {blot_check_capability_contracts::Tag.empty, ..}; nodes[4] = Term {blot_check_capability_contracts::Tag.empty, ..};
    assert(no_words.validate(0, 0, true) == ok);
}
