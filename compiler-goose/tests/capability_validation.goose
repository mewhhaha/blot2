import check.capability_contracts;
import support.error;

type Term = blot_check_capability_contracts::Term;
type View = blot_check_capability_contracts::View;

fn main() {
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
