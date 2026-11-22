// Shape evidence exposes every operand; emission separately proves lifetimes.
namespace blot_check_storage_core;
import check.core;
import check.effects;
import check.storage_ops;
import check.storage_types;
import check.types;
import support.error;
import support.option;

import std;
recursive fn equalStorageType(types: const blot_check_core::Types&, left: blot_check_types::Id, right: blot_check_types::Id, remaining: i64&, depth: i64) -> bool, blot_error::Error {
    if remaining == 0 || depth >= 128 { return false, blot_error::Error.type_limit; }
    remaining -= 1;
    if left == right { return true, blot_error::Error.none; }
    let a = types.node(left);
    let b = types.node(right);
    if a.tag != b.tag { return false, blot_error::Error.none; }
    match a.tag {
        unit, boolean, unsigned32, floating32, never => { return true, blot_error::Error.none; },
        variable => { return a.a == b.a, blot_error::Error.none; },
        array => { return equalStorageType(types, a.a, b.a, remaining, depth + 1); },
        usage => {
            if a.b != b.b || a.c != b.c { return false, blot_error::Error.none; }
            return equalStorageType(types, a.a, b.a, remaining, depth + 1);
        },
        function => {
            if a.c != b.c {
                let ra = types.row(a.c); let rb = types.row(b.c);
                if ra.tail != rb.tail { return false, blot_error::Error.none; }
                let la = types.rowLabels(a.c); let lb = types.rowLabels(b.c);
                if la.len != lb.len { return false, blot_error::Error.none; }
                for x, i in la { if x != lb[i] { return false, blot_error::Error.none; } }
            }
            let same_a, err_a = equalStorageType(types, a.a, b.a, remaining, depth + 1);
            if err_a != blot_error::Error.none || !same_a { return same_a, err_a; }
            return equalStorageType(types, a.b, b.b, remaining, depth + 1);
        },
        product => {
            if a.b != b.b { return false, blot_error::Error.none; }
            let xs = types.list(blot_check_types::List { a.a, a.b , ..});
            let ys = types.list(blot_check_types::List { b.a, b.b , ..});
            for x, i in xs {
                let same, err = equalStorageType(types, x, ys[i], remaining, depth + 1);
                if err != blot_error::Error.none || !same { return same, err; }
            }
            return true, blot_error::Error.none;
        },
        record => {
            if a.b != b.b { return false, blot_error::Error.none; }
            for i in 0..a.b {
                let fa = types.recordField(a, i);
                var found = false;
                for j in 0..b.b {
                    let fb = types.recordField(b, j);
                    if fa.name == fb.name {
                        let same, err = equalStorageType(types, fa.ty, fb.ty, remaining, depth + 1);
                        if err != blot_error::Error.none || !same { return same, err; }
                        found = true; break;
                    }
                }
                if !found { return false, blot_error::Error.none; }
            }
            return true, blot_error::Error.none;
        },
        nominal, projection => {
            if a.a != b.a || a.b != b.b { return false, blot_error::Error.none; }
            if a.tag == blot_check_types::Tag.projection && types.projectionMember(a) != types.projectionMember(b) { return false, blot_error::Error.none; }
            let xs = types.nominalArguments(a);
            let ys = types.nominalArguments(b);
            if xs.len != ys.len { return false, blot_error::Error.none; }
            for x, i in xs {
                let same, err = equalStorageType(types, x, ys[i], remaining, depth + 1);
                if err != blot_error::Error.none || !same { return same, err; }
            }
            return true, blot_error::Error.none;
        },
        _ => { return a.a == b.a && a.b == b.b && a.c == b.c, blot_error::Error.none; },
    }
}
struct Pair { expected: blot_check_types::Id, actual: blot_check_types::Id }
struct Contract { pairs: Pair[4] = [default<Pair>(); 4], len: i64 = 0 }
fn same(self_: Contract&, expected: blot_check_types::Id, actual: blot_check_types::Id) { self_.pairs[self_.len] = Pair { expected, actual , ..}; self_.len += 1; }
fn contract(m: const blot_check_core::Module&, id: blot_check_core::Id) -> Contract, blot_error::Error {
    let n = m.node(id); let op, error = blot_check_storage_ops::opFromCode(n.c);
    if error != blot_error::Error.none { return Contract {..}, blot_error::Error.invalid_artifact; }
    let args = m.children(id); if args.len != blot_check_storage_ops::arity(op) { return Contract {..}, blot_error::Error.invalid_artifact; }
    let input = m.typeOf(args[0]); let kind = blot_check_storage_types::info(m.types, input);
    var element = blot_check_storage_types::readableElement(m.types, input);
    var result = Contract {..};
    match op {
        ref, at, link, view => {
            let out = blot_check_storage_types::info(m.types, n.ty); if !out.present { return Contract {..}, blot_error::Error.invalid_artifact; }
            var expected = blot_check_storage_types::view;
            if op == blot_check_storage_ops::Op.ref || op == blot_check_storage_ops::Op.at { expected = blot_check_storage_types::ref; }
            else if op == blot_check_storage_ops::Op.link { expected = blot_check_storage_types::link; }
            if out.value.kind != expected { return Contract {..}, blot_error::Error.invalid_artifact; }
            if op == blot_check_storage_ops::Op.ref { let place = m.node(args[0]); if place.tag != blot_check_core::Tag.reference && place.tag != blot_check_core::Tag.project { return Contract {..}, blot_error::Error.invalid_artifact; } same(result, input, out.value.element); }
            else { if !element.present || (op == blot_check_storage_ops::Op.link && kind.present && kind.value.kind != blot_check_storage_types::grow && kind.value.kind != blot_check_storage_types::sized_grow) { return Contract {..}, blot_error::Error.invalid_artifact; }
                same(result, element.value, out.value.element); for arg in args[1..] { same(result, blot_check_types::u32_type, m.typeOf(arg)); } }
        },
        load => { if !kind.present || (kind.value.kind != blot_check_storage_types::ref && kind.value.kind != blot_check_storage_types::link) { return Contract {..}, blot_error::Error.invalid_artifact; }
            same(result, kind.value.element, n.ty); },
        length => { if !element.present { return Contract {..}, blot_error::Error.invalid_artifact; } same(result, blot_check_types::u32_type, n.ty); },
        read => { if !element.present { return Contract {..}, blot_error::Error.invalid_artifact; } same(result, element.value, n.ty); same(result, blot_check_types::u32_type, m.typeOf(args[1])); },
        push, reserve => { if !kind.present || !blot_check_storage_types::isGrowable(kind.value.kind) { return Contract {..}, blot_error::Error.invalid_artifact; }
            if op == blot_check_storage_ops::Op.push { same(result, kind.value.element, m.typeOf(args[1])); }
            else { let count = m.node(args[1]); if count.tag != blot_check_core::Tag.constant || count.b != 0 || count.c != 0 || m.types.node(count.ty).tag != blot_check_types::Tag.unsigned32 { return Contract {..}, blot_error::Error.invalid_artifact; } same(result, blot_check_types::u32_type, m.typeOf(args[1])); }
            same(result, blot_check_types::unit, n.ty); },
        pop, truncate => { if !kind.present || !blot_check_storage_types::isResizable(kind.value.kind) { return Contract {..}, blot_error::Error.invalid_artifact; }
            if op == blot_check_storage_ops::Op.pop { same(result, kind.value.element, n.ty); } else { same(result, blot_check_types::u32_type, m.typeOf(args[1])); same(result, blot_check_types::unit, n.ty); } },
        freeze => {
            if !kind.present || !blot_check_storage_types::isGrowable(kind.value.kind) { return Contract {..}, blot_error::Error.invalid_artifact; }
            let out = m.types.node(n.ty);
            let out_info = blot_check_storage_types::info(m.types, n.ty);
            if blot_check_storage_types::isSized(kind.value.kind) && out_info.present && out_info.value.kind == blot_check_storage_types::sized_array {
                same(result, kind.value.element, out_info.value.element);
            } else if out.tag == blot_check_types::Tag.array {
                same(result, kind.value.element, out.a);
            } else {
                return Contract {..}, blot_error::Error.invalid_artifact;
            }
        },
        share => {
            let out = blot_check_storage_types::info(m.types, n.ty);
            if !out.present || out.value.kind != blot_check_storage_types::shared { return Contract {..}, blot_error::Error.invalid_artifact; }
            if kind.present && kind.value.kind == blot_check_storage_types::shared {
                same(result, input, n.ty);
            } else if kind.present && blot_check_storage_types::isGrowable(kind.value.kind) {
                let inner_elem = blot_check_storage_types::arrayElement(m.types, out.value.element);
                if !inner_elem.present { return Contract {..}, blot_error::Error.invalid_artifact; }
                same(result, kind.value.element, inner_elem.value);
            } else {
                same(result, input, out.value.element);
            }
        },
        copy => {
            if kind.present && kind.value.kind == blot_check_storage_types::view { return Contract {..}, blot_error::Error.invalid_artifact; }
            let expected = blot_check_storage_types::unwrapShared(m.types, input);
            same(result, expected, n.ty);
        },
    }
    return result, blot_error::Error.none;
}
fn validate(m: const blot_check_core::Module&) -> blot_error::Error {
    var present = false;
    for node in m.types.nodes {
        if node.tag != blot_check_types::Tag.nominal && node.tag != blot_check_types::Tag.projection && node.tag != blot_check_types::Tag.type_constructor { continue; }
        let kind = blot_check_storage_types::identity(node.a, node.b);
        if !kind.present { continue; }
        if node.tag != blot_check_types::Tag.nominal || m.types.nominalArguments(node).len != blot_check_storage_types::arity(kind.value) { return blot_error::Error.invalid_artifact; } present = true;
    }
    for node in m.nodes { if node.tag == blot_check_core::Tag.storage || blot_check_storage_types::info(m.types, node.ty).present { present = true; break; } }
    if !present { return blot_error::Error.none; } var remaining: i64 = 1000000;
    for node, index in m.nodes {
        if node.tag == blot_check_core::Tag.storage {
            let evidence, error = contract(m, index as u32); if error != blot_error::Error.none { return error; }
            for pair in evidence.pairs[..evidence.len] { if pair.actual == blot_check_types::never { continue; } let same, error = equalStorageType(m.types, pair.expected, pair.actual, remaining, 0); if error != blot_error::Error.none || !same { return blot_error::Error.invalid_artifact; } }
        } else if node.tag == blot_check_core::Tag.array {
            let shape = m.types.node(node.ty); var element = blot_check_storage_types::arrayElement(m.types, node.ty);
            if !element.present { return blot_error::Error.invalid_artifact; }
            for child in m.children(index as u32) { if m.typeOf(child) == blot_check_types::never { continue; } let same, error = equalStorageType(m.types, element.value, m.typeOf(child), remaining, 0); if error != blot_error::Error.none || !same { return blot_error::Error.invalid_artifact; } }
        }
    }
    return blot_error::Error.none;
}
