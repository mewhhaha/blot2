// Shape evidence exposes every operand; emission separately proves lifetimes.
namespace squid_check_storage_core;
import check.core;
import check.effects;
import check.storage_ops;
import check.storage_types;
import check.types;
import support.error;
import support.option;

import std;
recursive fn equalStorageType(types: const squid_check_core::Types&, left: squid_check_types::Id, right: squid_check_types::Id, remaining: i64&, depth: i64) -> bool, squid_error::Error {
    if remaining == 0 || depth >= 128 { return false, squid_error::Error.type_limit; }
    remaining -= 1;
    if left == right { return true, squid_error::Error.none; }
    let a = types.node(left);
    let b = types.node(right);
    if a.tag != b.tag { return false, squid_error::Error.none; }
    match a.tag {
        unit, boolean, unsigned32, floating32, unsigned8, signed32, unsigned64, signed64, floating64, never => { return true, squid_error::Error.none; },
        variable => { return a.a == b.a, squid_error::Error.none; },
        array => { return equalStorageType(types, a.a, b.a, remaining, depth + 1); },
        usage => {
            if a.b != b.b || a.c != b.c { return false, squid_error::Error.none; }
            return equalStorageType(types, a.a, b.a, remaining, depth + 1);
        },
        function => {
            if a.c != b.c {
                let ra = types.row(a.c); let rb = types.row(b.c);
                if ra.tail != rb.tail { return false, squid_error::Error.none; }
                let la = types.rowLabels(a.c); let lb = types.rowLabels(b.c);
                if la.len != lb.len { return false, squid_error::Error.none; }
                for x, i in la { if x != lb[i] { return false, squid_error::Error.none; } }
            }
            let same_a, err_a = equalStorageType(types, a.a, b.a, remaining, depth + 1);
            if err_a != squid_error::Error.none || !same_a { return same_a, err_a; }
            return equalStorageType(types, a.b, b.b, remaining, depth + 1);
        },
        product => {
            if a.b != b.b { return false, squid_error::Error.none; }
            let xs = types.list(squid_check_types::List { a.a, a.b , ..});
            let ys = types.list(squid_check_types::List { b.a, b.b , ..});
            for x, i in xs {
                let same, err = equalStorageType(types, x, ys[i], remaining, depth + 1);
                if err != squid_error::Error.none || !same { return same, err; }
            }
            return true, squid_error::Error.none;
        },
        record => {
            if a.b != b.b { return false, squid_error::Error.none; }
            for i in 0..a.b {
                let fa = types.recordField(a, i);
                var found = false;
                for j in 0..b.b {
                    let fb = types.recordField(b, j);
                    if fa.name == fb.name {
                        let same, err = equalStorageType(types, fa.ty, fb.ty, remaining, depth + 1);
                        if err != squid_error::Error.none || !same { return same, err; }
                        found = true; break;
                    }
                }
                if !found { return false, squid_error::Error.none; }
            }
            return true, squid_error::Error.none;
        },
        nominal, projection => {
            if a.a != b.a || a.b != b.b { return false, squid_error::Error.none; }
            if a.tag == squid_check_types::Tag.projection && types.projectionMember(a) != types.projectionMember(b) { return false, squid_error::Error.none; }
            let xs = types.nominalArguments(a);
            let ys = types.nominalArguments(b);
            if xs.len != ys.len { return false, squid_error::Error.none; }
            for x, i in xs {
                let same, err = equalStorageType(types, x, ys[i], remaining, depth + 1);
                if err != squid_error::Error.none || !same { return same, err; }
            }
            return true, squid_error::Error.none;
        },
        _ => { return a.a == b.a && a.b == b.b && a.c == b.c, squid_error::Error.none; },
    }
}
struct Pair { expected: squid_check_types::Id, actual: squid_check_types::Id }
struct Contract { pairs: Pair[4] = [default<Pair>(); 4], len: i64 = 0 }
fn same(self_: Contract&, expected: squid_check_types::Id, actual: squid_check_types::Id) { self_.pairs[self_.len] = Pair { expected, actual , ..}; self_.len += 1; }
fn contract(m: const squid_check_core::Module&, id: squid_check_core::Id) -> Contract, squid_error::Error {
    let n = m.node(id); let op, error = squid_check_storage_ops::opFromCode(n.c);
    if error != squid_error::Error.none { return Contract {..}, squid_error::Error.invalid_artifact; }
    let args = m.children(id); if args.len != squid_check_storage_ops::arity(op) { return Contract {..}, squid_error::Error.invalid_artifact; }
    let input = m.typeOf(args[0]); let kind = squid_check_storage_types::info(m.types, input);
    var element = squid_check_storage_types::readableElement(m.types, input);
    let index_element = squid_check_storage_types::indexReadableElement(m.types, input);
    let iter_element = squid_check_storage_types::iterableElement(m.types, input);
    let is_owned_packed = squid_check_storage_types::isOwnedPacked(m.types, input);
    let is_owned_seq = squid_check_storage_types::isOwnedSeq(m.types, input);
    let seq_elem = squid_check_storage_types::seqElement(m.types, input);
    let is_growable = m.types.node(input).tag == squid_check_types::Tag.array || is_owned_packed || is_owned_seq;
    var result = Contract {..};
    match op {
        ref, at, link, view => {
            let out = squid_check_storage_types::info(m.types, n.ty); if !out.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            var expected = squid_check_storage_types::view;
            if op == squid_check_storage_ops::Op.ref || op == squid_check_storage_ops::Op.at { expected = squid_check_storage_types::ref; }
            else if op == squid_check_storage_ops::Op.link { expected = squid_check_storage_types::link; }
            if out.value.kind != expected { return Contract {..}, squid_error::Error.invalid_artifact; }
            if op == squid_check_storage_ops::Op.ref { let place = m.node(args[0]); if place.tag != squid_check_core::Tag.reference && place.tag != squid_check_core::Tag.project { return Contract {..}, squid_error::Error.invalid_artifact; } same(result, input, out.value.element); }
            else { if !element.present || (op == squid_check_storage_ops::Op.link && kind.present && kind.value.kind != squid_check_storage_types::sized_array) { return Contract {..}, squid_error::Error.invalid_artifact; }
                same(result, element.value, out.value.element); for arg in args[1..] { same(result, squid_check_types::u32_type, m.typeOf(arg)); } }
        },
        load => { if !kind.present || (kind.value.kind != squid_check_storage_types::ref && kind.value.kind != squid_check_storage_types::link) { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, kind.value.element, n.ty); },
        length => { if !iter_element.present { return Contract {..}, squid_error::Error.invalid_artifact; } same(result, squid_check_types::u32_type, n.ty); },
        read => { if !index_element.present { return Contract {..}, squid_error::Error.invalid_artifact; } same(result, index_element.value, n.ty); same(result, squid_check_types::u32_type, m.typeOf(args[1])); },
        push => {
            if !is_growable || !iter_element.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, iter_element.value, m.typeOf(args[1]));
            same(result, input, n.ty); },
        pop => {
            if !is_growable || !iter_element.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, iter_element.value, n.ty); },
        truncate => {
            if m.types.node(input).tag != squid_check_types::Tag.array { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, squid_check_types::u32_type, m.typeOf(args[1])); same(result, squid_check_types::unit, n.ty); },
        share => {
            let out = squid_check_storage_types::info(m.types, n.ty);
            if !out.present || out.value.kind != squid_check_storage_types::shared { return Contract {..}, squid_error::Error.invalid_artifact; }
            if kind.present && kind.value.kind == squid_check_storage_types::shared {
                same(result, input, n.ty);
            } else {
                same(result, input, out.value.element);
            }
        },
        copy => {
            if kind.present && kind.value.kind == squid_check_storage_types::view { return Contract {..}, squid_error::Error.invalid_artifact; }
            let expected = squid_check_storage_types::unwrapShared(m.types, input);
            same(result, expected, n.ty);
        },
        with_capacity => {
            if m.types.node(n.ty).tag != squid_check_types::Tag.array && !squid_check_storage_types::isOwnedPacked(m.types, n.ty) && !squid_check_storage_types::isOwnedSeq(m.types, n.ty) { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, squid_check_types::u32_type, input);
        },
        reserve => {
            if !is_growable { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, squid_check_types::u32_type, m.typeOf(args[1]));
            same(result, input, n.ty);
        },
        extend => {
            if !is_growable || !iter_element.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            let src_elem = squid_check_storage_types::iterableElement(m.types, m.typeOf(args[1]));
            if !src_elem.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, iter_element.value, src_elem.value);
            same(result, input, n.ty);
        },
        push_front => {
            if !is_owned_seq || !seq_elem.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, seq_elem.value, m.typeOf(args[1]));
            same(result, input, n.ty);
        },
        pop_front => {
            if !is_owned_seq || !seq_elem.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, seq_elem.value, n.ty);
        },
        insert => {
            if !is_owned_seq || !seq_elem.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, squid_check_types::u32_type, m.typeOf(args[1]));
            same(result, seq_elem.value, m.typeOf(args[2]));
            same(result, input, n.ty);
        },
        remove => {
            if !is_owned_seq || !seq_elem.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, squid_check_types::u32_type, m.typeOf(args[1]));
            same(result, seq_elem.value, n.ty);
        },
        reverse => {
            if !seq_elem.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, squid_check_storage_types::unwrapShared(m.types, input), n.ty);
        },
        split => {
            if !seq_elem.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, squid_check_types::u32_type, m.typeOf(args[1]));
            let out_node = m.types.node(n.ty);
            if out_node.tag != squid_check_types::Tag.product || out_node.b != 2 { return Contract {..}, squid_error::Error.invalid_artifact; }
            let out_items = m.types.list(squid_check_types::List { out_node.a, out_node.b , ..});
            let out_seq = squid_check_storage_types::unwrapShared(m.types, input);
            same(result, out_seq, out_items[0]);
            same(result, out_seq, out_items[1]);
        },
        concat => {
            if !seq_elem.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            let rhs_elem = squid_check_storage_types::seqElement(m.types, m.typeOf(args[1]));
            if !rhs_elem.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, seq_elem.value, rhs_elem.value);
            same(result, squid_check_storage_types::unwrapShared(m.types, input), n.ty);
        },
        slice => {
            if !seq_elem.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, squid_check_types::u32_type, m.typeOf(args[1]));
            same(result, squid_check_types::u32_type, m.typeOf(args[2]));
            same(result, squid_check_storage_types::unwrapShared(m.types, input), n.ty);
        },
        repeat => {
            let out_seq = squid_check_storage_types::ownedSeqElement(m.types, n.ty);
            if !out_seq.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, squid_check_types::u32_type, input);
            same(result, out_seq.value, m.typeOf(args[1]));
        },
        ramp => {
            let out_seq = squid_check_storage_types::ownedSeqElement(m.types, n.ty);
            if !out_seq.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, squid_check_types::u32_type, input);
            same(result, squid_check_types::u32_type, m.typeOf(args[1]));
            same(result, squid_check_types::u32_type, m.typeOf(args[2]));
            same(result, squid_check_types::u32_type, out_seq.value);
        },
        from_frozen => {
            let sh = squid_check_storage_types::sharedInner(m.types, input);
            if !sh.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            let arr_elem = squid_check_storage_types::arrayElement(m.types, sh.value);
            if !arr_elem.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            let out_seq = squid_check_storage_types::ownedSeqElement(m.types, n.ty);
            if !out_seq.present { return Contract {..}, squid_error::Error.invalid_artifact; }
            same(result, arr_elem.value, out_seq.value);
        },
    }
    return result, squid_error::Error.none;
}
fn validate(m: const squid_check_core::Module&) -> squid_error::Error {
    var present = false;
    for node in m.types.nodes {
        if node.tag != squid_check_types::Tag.nominal && node.tag != squid_check_types::Tag.projection && node.tag != squid_check_types::Tag.type_constructor { continue; }
        let kind = squid_check_storage_types::identity(node.a, node.b);
        if !kind.present { continue; }
        if node.tag != squid_check_types::Tag.nominal || m.types.nominalArguments(node).len != squid_check_storage_types::arity(kind.value) { return squid_error::Error.invalid_artifact; } present = true;
    }
    for node in m.nodes { if node.tag == squid_check_core::Tag.storage || squid_check_storage_types::info(m.types, node.ty).present { present = true; break; } }
    if !present { return squid_error::Error.none; } var remaining: i64 = 1000000;
    for node, index in m.nodes {
        if node.tag == squid_check_core::Tag.storage {
            let evidence, error = contract(m, index as u32); if error != squid_error::Error.none { return error; }
            for pair in evidence.pairs[..evidence.len] { if pair.actual == squid_check_types::never { continue; } let same, error = equalStorageType(m.types, pair.expected, pair.actual, remaining, 0); if error != squid_error::Error.none || !same { return squid_error::Error.invalid_artifact; } }
        } else if node.tag == squid_check_core::Tag.array {
            var element = squid_check_storage_types::arrayElement(m.types, node.ty);
            if !element.present { element = squid_check_storage_types::packedElement(m.types, node.ty); }
            if !element.present { element = squid_check_storage_types::seqElement(m.types, node.ty); }
            if !element.present { return squid_error::Error.invalid_artifact; }
            for child in m.children(index as u32) { if m.typeOf(child) == squid_check_types::never { continue; } let same, error = equalStorageType(m.types, element.value, m.typeOf(child), remaining, 0); if error != squid_error::Error.none || !same { return squid_error::Error.invalid_artifact; } }
        }
    }
    return squid_error::Error.none;
}
