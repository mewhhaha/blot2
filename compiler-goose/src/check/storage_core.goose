// Shape evidence exposes every operand; emission separately proves lifetimes.
namespace blot_check_storage_core;
import std;
import support.error;
struct Pair { expected: blot_check_types::Id, actual: blot_check_types::Id }
struct Contract { pairs: Pair[4] = [default<Pair>(); 4], len: i64 = 0 }
fn same(self: Contract&, expected: blot_check_types::Id, actual: blot_check_types::Id) { self.pairs[self.len] = Pair { expected, actual }; self.len += 1; }
fn contract(m: const blot_check_core::Module&, id: blot_check_core::Id) -> Contract, blot_error::Error {
    let n = m.node(id); let op, error = blot_check_storage_ops::opFromCode(n.c);
    if error != blot_error::Error.none { return Contract {}, blot_error::Error.invalid_artifact; }
    let args = m.children(id); if args.len != blot_check_storage_ops::arity(op) { return Contract {}, blot_error::Error.invalid_artifact; }
    let input = m.typeOf(args[0]); let kind = blot_check_storage_types::info(m.types, input);
    var element = blot_check_storage_types::arrayElement(m.types, input);
    if !element.present && kind.present && kind.value.kind == blot_check_storage_types::view { element = blot_support::Option<blot_check_types::Id> { true, kind.value.element }; }
    var result = Contract {};
    match op {
        ref, at, link, view => {
            let out = blot_check_storage_types::info(m.types, n.ty); if !out.present { return Contract {}, blot_error::Error.invalid_artifact; }
            var expected = blot_check_storage_types::view;
            if op == blot_check_storage_ops::Op.ref || op == blot_check_storage_ops::Op.at { expected = blot_check_storage_types::ref; }
            else if op == blot_check_storage_ops::Op.link { expected = blot_check_storage_types::link; }
            if out.value.kind != expected { return Contract {}, blot_error::Error.invalid_artifact; }
            if op == blot_check_storage_ops::Op.ref { let place = m.node(args[0]); if place.tag != blot_check_core::Tag.reference && place.tag != blot_check_core::Tag.project { return Contract {}, blot_error::Error.invalid_artifact; } same(result, input, out.value.element); }
            else { if !element.present || (op == blot_check_storage_ops::Op.link && kind.present && kind.value.kind != blot_check_storage_types::grow) { return Contract {}, blot_error::Error.invalid_artifact; }
                same(result, element.value, out.value.element); for arg in args[1..] { same(result, blot_check_types::u32_type, m.typeOf(arg)); } }
        },
        load, write => { if !kind.present || (kind.value.kind != blot_check_storage_types::ref && kind.value.kind != blot_check_storage_types::link) { return Contract {}, blot_error::Error.invalid_artifact; }
            if op == blot_check_storage_ops::Op.load { same(result, kind.value.element, n.ty); } else { same(result, kind.value.element, m.typeOf(args[1])); same(result, blot_check_types::unit, n.ty); } },
        length => { if !element.present { return Contract {}, blot_error::Error.invalid_artifact; } same(result, blot_check_types::u32_type, n.ty); },
        read => { if !element.present { return Contract {}, blot_error::Error.invalid_artifact; } same(result, element.value, n.ty); same(result, blot_check_types::u32_type, m.typeOf(args[1])); },
        push, reserve => { if !kind.present || (kind.value.kind != blot_check_storage_types::grow && kind.value.kind != blot_check_storage_types::resize) { return Contract {}, blot_error::Error.invalid_artifact; }
            if op == blot_check_storage_ops::Op.push { same(result, kind.value.element, m.typeOf(args[1])); }
            else { let count = m.node(args[1]); if count.tag != blot_check_core::Tag.constant || count.b != 0 || count.c != 0 || m.types.node(count.ty).tag != blot_check_types::Tag.unsigned32 { return Contract {}, blot_error::Error.invalid_artifact; } same(result, blot_check_types::u32_type, m.typeOf(args[1])); }
            same(result, blot_check_types::unit, n.ty); },
        pop, truncate => { if !kind.present || kind.value.kind != blot_check_storage_types::resize { return Contract {}, blot_error::Error.invalid_artifact; }
            if op == blot_check_storage_ops::Op.pop { same(result, kind.value.element, n.ty); } else { same(result, blot_check_types::u32_type, m.typeOf(args[1])); same(result, blot_check_types::unit, n.ty); } },
        freeze => { if !kind.present || (kind.value.kind != blot_check_storage_types::grow && kind.value.kind != blot_check_storage_types::resize) { return Contract {}, blot_error::Error.invalid_artifact; }
            let out = m.types.node(n.ty); if out.tag != blot_check_types::Tag.array { return Contract {}, blot_error::Error.invalid_artifact; } same(result, kind.value.element, out.a); },
        copy => { if !element.present || (kind.present && kind.value.kind == blot_check_storage_types::view) { return Contract {}, blot_error::Error.invalid_artifact; } same(result, input, n.ty); },
    }
    return result, blot_error::Error.none;
}
fn validate(m: const blot_check_core::Module&) -> blot_error::Error {
    var present = false;
    for node in m.types.nodes {
        if node.tag != blot_check_types::Tag.nominal && node.tag != blot_check_types::Tag.projection && node.tag != blot_check_types::Tag.type_constructor { continue; }
        if !blot_check_storage_types::identity(node.a, node.b).present { continue; }
        if node.tag != blot_check_types::Tag.nominal || m.types.nominalArguments(node).len != 1 { return blot_error::Error.invalid_artifact; } present = true;
    }
    for node in m.nodes { if node.tag == blot_check_core::Tag.storage || blot_check_storage_types::info(m.types, node.ty).present { present = true; break; } }
    if !present { return blot_error::Error.none; } var remaining: i64 = 1000000;
    for node, index in m.nodes {
        if node.tag == blot_check_core::Tag.storage {
            let evidence, error = contract(m, index as u32); if error != blot_error::Error.none { return error; }
            for pair in evidence.pairs[..evidence.len] { if pair.actual == blot_check_types::never { continue; } let same, error = blot_check_rank_equal::equalWithBudget(m.types, pair.expected, pair.actual, true, remaining); if error != blot_error::Error.none || !same { return blot_error::Error.invalid_artifact; } }
        } else if node.tag == blot_check_core::Tag.array {
            let shape = m.types.node(node.ty); var element = blot_check_storage_types::arrayElement(m.types, node.ty);
            if shape.tag == blot_check_types::Tag.list { element = blot_support::Option<blot_check_types::Id> { true, shape.a }; } if !element.present { return blot_error::Error.invalid_artifact; }
            for child in m.children(index as u32) { if m.typeOf(child) == blot_check_types::never { continue; } let same, error = blot_check_rank_equal::equalWithBudget(m.types, element.value, m.typeOf(child), true, remaining); if error != blot_error::Error.none || !same { return blot_error::Error.invalid_artifact; } }
        }
    }
    return blot_error::Error.none;
}
