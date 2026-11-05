// Alpha equality has an explicit lexical binder correspondence.
namespace blot_check_rank_equal;
import check.effects;
import check.quantifier_goals;
import check.types;
import support.error;

struct Frame { left: blot_check_types::List, right: blot_check_types::List }
struct Walker<S> {
    store: S, symbolic: bool, budget: i64&,
    frames: Frame[128] = [default<Frame>(); 128],
    depth: i64 = 0, steps: i64 = 0, height: i64 = 0, budgeted: bool = false,
}
fn work<S>(self_: Walker<S>&) -> blot_error::Error {
    if self_.budgeted {
        if self_.budget == 0 { return blot_error::Error.type_limit; }
        self_.budget -= 1;
    }
    return blot_error::Error.none;
}
recursive fn walkEqual<S>(self_: Walker<S>&, left: blot_check_types::Id, right: blot_check_types::Id) -> bool, blot_error::Error {
    if self_.steps >= 4096 || self_.height >= 128 { return false, blot_error::Error.type_limit; }
    self_.height += 1; self_.steps += 1;
    let result, error = walkNode(self_, left, right);
    self_.height -= 1;
    return result, error;
}
recursive fn walkNode<S>(self_: Walker<S>&, left: blot_check_types::Id, right: blot_check_types::Id) -> bool, blot_error::Error {
    let charged = work(self_); if charged != blot_error::Error.none { return false, charged; }
    let a = self_.store.node(left); let b = self_.store.node(right);
    if a.tag != b.tag { return false, blot_error::Error.none; }
    match a.tag {
        absent => { return false, blot_error::Error.none; },
        variable => { return self_.symbolic && a.a == b.a && a.b == b.b, blot_error::Error.none; },
        instance_version => { return a.a == b.a && a.b == b.b && a.c == b.c, blot_error::Error.none; },
        rigid => { return self_.symbolic && a.a == b.a && a.b == b.b && a.c == b.c, blot_error::Error.none; },
        bound => {
            var index = self_.depth;
            while index != 0 {
                index -= 1;
                let charged = work(self_); if charged != blot_error::Error.none { return false, charged; }
                let frame = self_.frames[index];
                let first = self_.store.list(frame.left); let second = self_.store.list(frame.right);
                for av, i in first {
                    let bv = second[i];
                    let charged = work(self_); if charged != blot_error::Error.none { return false, charged; }
                    if av == left || bv == right { return av == left && bv == right, blot_error::Error.none; }
                }
            }
            return left == right, blot_error::Error.none;
        },
        forall, existential => {
            if a.c != b.c { return false, blot_error::Error.none; }
            if self_.depth == self_.frames.len { return false, blot_error::Error.type_limit; }
            let frame = Frame { blot_check_types::List { a.b, a.c }, blot_check_types::List { b.b, b.c , ..} , ..};
            let first = self_.store.list(frame.left); let second = self_.store.list(frame.right);
            for av, i in first {
                let bv = second[i];
                let charged = work(self_); if charged != blot_error::Error.none { return false, charged; }
                let aa = self_.store.node(av); let bb = self_.store.node(bv);
                if aa.tag != blot_check_types::Tag.bound || bb.tag != blot_check_types::Tag.bound || aa.b != bb.b { return false, blot_error::Error.none; }
            }
            self_.frames[self_.depth] = frame; self_.depth += 1;
            let result, error = walkQuantifier(self_, left, right, a.a, b.a);
            self_.depth -= 1;
            return result, error;
        },
        function => {
            let first, e1 = walkEqual(self_, a.a, b.a); if e1 != blot_error::Error.none || !first { return first, e1; }
            let second, e2 = walkEqual(self_, a.b, b.b); if e2 != blot_error::Error.none || !second { return second, e2; }
            return walkRow(self_, a.c, b.c);
        },
        provider => {
            let first, error = walkEqual(self_, a.a, b.a); if error != blot_error::Error.none || !first { return first, error; }
            return walkRow(self_, a.c, b.c);
        },
        array, list, cursor, resolver => { return walkEqual(self_, a.a, b.a); },
        state_provider => {
            let first = [a.a, a.b, a.c]; let second = [b.a, b.b, b.c];
            for av, i in first {
                let equal, error = walkEqual(self_, av, second[i]); if error != blot_error::Error.none || !equal { return equal, error; }
            }
            return true, blot_error::Error.none;
        },
        usage => {
            if a.b != b.b || (a.c == 0) != (b.c == 0) { return false, blot_error::Error.none; }
            let first, error = walkEqual(self_, a.a, b.a); if error != blot_error::Error.none || !first { return first, error; }
            if a.c == 0 { return true, blot_error::Error.none; }
            return walkEqual(self_, a.c, b.c);
        },
        scoped => {
            if a.b != b.b { return false, blot_error::Error.none; }
            if a.b == 0 {
                let child, error = walkEqual(self_, a.c, b.c); if error != blot_error::Error.none || !child { return child, error; }
            } else if a.c != b.c { return false, blot_error::Error.none; }
            return walkEqual(self_, a.a, b.a);
        },
        product => {
            if a.b != b.b { return false, blot_error::Error.none; }
            let first = self_.store.list(blot_check_types::List { a.a, a.b , ..});
            let second = self_.store.list(blot_check_types::List { b.a, b.b , ..});
            for av, i in first {
                let child, error = walkEqual(self_, av, second[i]); if error != blot_error::Error.none || !child { return child, error; }
            }
        },
        record => {
            if a.b != b.b { return false, blot_error::Error.none; }
            for index in a.b {
                let field = self_.store.recordField(a, index); var matched = false;
                for other in b.b {
                    let charged = work(self_); if charged != blot_error::Error.none { return false, charged; }
                    let candidate = self_.store.recordField(b, other);
                    if field.name != candidate.name { continue; }
                    let child, error = walkEqual(self_, field.ty, candidate.ty); if error != blot_error::Error.none || !child { return child, error; }
                    matched = true; break;
                }
                if !matched { return false, blot_error::Error.none; }
            }
        },
        nominal, projection, instance_selection => {
            if a.a != b.a || a.b != b.b { return false, blot_error::Error.none; }
            if a.tag == blot_check_types::Tag.projection && self_.store.projectionMember(a) != self_.store.projectionMember(b) { return false, blot_error::Error.none; }
            let aa = self_.store.nominalArguments(a); let bb = self_.store.nominalArguments(b);
            if aa.len != bb.len { return false, blot_error::Error.none; }
            for av, i in aa {
                let child, error = walkEqual(self_, av, bb[i]); if error != blot_error::Error.none || !child { return child, error; }
            }
        },
        type_constructor => { return a.a == b.a && a.b == b.b, blot_error::Error.none; },
        _ => {},
    }
    return true, blot_error::Error.none;
}
recursive fn walkQuantifier<S>(self_: Walker<S>&, left: blot_check_types::Id, right: blot_check_types::Id,
                               left_body: blot_check_types::Id, right_body: blot_check_types::Id) -> bool, blot_error::Error {
    let left_goals = self_.store.quantifierGoals(left); let right_goals = self_.store.quantifierGoals(right);
    if left_goals.len != right_goals.len { return false, blot_error::Error.none; }
    for left_goal, i in left_goals {
        let right_goal = right_goals[i];
        let charged = work(self_); if charged != blot_error::Error.none { return false, charged; }
        if !blot_check_quantifier_goals::sameHead(left_goal, right_goal) { return false, blot_error::Error.none; }
        let first = [left_goal.ty, left_goal.other, left_goal.result, left_goal.signature];
        let second = [right_goal.ty, right_goal.other, right_goal.result, right_goal.signature];
        for left_child, j in first {
            let right_child = second[j];
            if (left_child == 0) != (right_child == 0) { return false, blot_error::Error.none; }
            if left_child != 0 {
                let child, error = walkEqual(self_, left_child, right_child); if error != blot_error::Error.none || !child { return child, error; }
            }
        }
    }
    return walkEqual(self_, left_body, right_body);
}
recursive fn walkOperation<S>(self_: Walker<S>&, left: blot_check_effects::Label, right: blot_check_effects::Label) -> bool, blot_error::Error {
    let charged = work(self_); if charged != blot_error::Error.none { return false, charged; }
    let a = self_.store.operation(left); let b = self_.store.operation(right);
    if a.identity.unit != b.identity.unit || a.identity.decl != b.identity.decl || a.instance.unit != b.instance.unit || a.arguments.len != b.arguments.len { return false, blot_error::Error.none; }
    if a.instance.unit == 0 && a.instance.decl != 0 && b.instance.decl != 0 {
        let child, error = walkEqual(self_, a.instance.decl, b.instance.decl); if error != blot_error::Error.none || !child { return child, error; }
    } else if a.instance.decl != b.instance.decl { return false, blot_error::Error.none; }
    let first = self_.store.list(a.arguments); let second = self_.store.list(b.arguments);
    for av, i in first {
        let child, error = walkEqual(self_, av, second[i]); if error != blot_error::Error.none || !child { return child, error; }
    }
    return true, blot_error::Error.none;
}
recursive fn walkRow<S>(self_: Walker<S>&, left: blot_check_effects::Id, right: blot_check_effects::Id) -> bool, blot_error::Error {
    let charged = work(self_); if charged != blot_error::Error.none { return false, charged; }
    let a = self_.store.effects.node(left); let b = self_.store.effects.node(right);
    if a.labels.len != b.labels.len { return false, blot_error::Error.none; }
    match a.tail {
        formal av => { match b.tail {
            formal bv => { let child, error = walkEqual(self_, av.value, bv.value); if error != blot_error::Error.none || !child { return child, error; } },
            _ => { return false, blot_error::Error.none; },
        } },
        _ => {
            if a.tail != b.tail || (!self_.symbolic && a.tail != blot_check_effects::Tail.closed) { return false, blot_error::Error.none; }
        },
    }
    for label in self_.store.effects.list(a.labels) {
        var ac: i64 = 0; var bc: i64 = 0;
        for other in self_.store.effects.list(a.labels) {
            let same, error = walkOperation(self_, label, other); if error != blot_error::Error.none { return false, error; }
            if same { ac += 1; }
        }
        for other in self_.store.effects.list(b.labels) {
            let same, error = walkOperation(self_, label, other); if error != blot_error::Error.none { return false, error; }
            if same { bc += 1; }
        }
        if ac != bc { return false, blot_error::Error.none; }
    }
    return true, blot_error::Error.none;
}
fn equal<S>(store: S, left: blot_check_types::Id, right: blot_check_types::Id, symbolic: bool) -> bool, blot_error::Error {
    var budget: i64 = 0; var walker = Walker<S> { store, symbolic, budget , ..};
    return walkEqual(walker, left, right);
}
fn operationEqual<S>(store: S, left: blot_check_effects::Label, right: blot_check_effects::Label, symbolic: bool) -> bool, blot_error::Error {
    var budget: i64 = 0; var walker = Walker<S> { store, symbolic, budget , ..};
    return walkOperation(walker, left, right);
}
fn equalWithBudget<S>(store: S, left: blot_check_types::Id, right: blot_check_types::Id, symbolic: bool, budget: i64&) -> bool, blot_error::Error {
    var walker = Walker<S> { store: store, symbolic: symbolic, budget: budget, budgeted: true , ..};
    return walkEqual(walker, left, right);
}
