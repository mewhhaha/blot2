// Storage identities belong to the compiler and never coerce ordinary arrays.
namespace blot_check_storage_types;
import std;
import support.error;
import support.option;
type Kind = u32;
let grow: Kind = 20; let resize: Kind = 21; let ref: Kind = 22; let view: Kind = 23; let link: Kind = 24;
struct Info { kind: Kind, element: blot_check_types::Id }
fn named(spelling: const u8[:]) -> blot_support::Option<Kind> {
    var text = spelling;
    if starts_with(text, "@storage.") { text = text[9..]; }
    if text == "GrowArray" { return blot_support::Option<Kind> { true, grow }; }
    if text == "ResizeArray" { return blot_support::Option<Kind> { true, resize }; }
    if text == "Ref" { return blot_support::Option<Kind> { true, ref }; }
    if text == "View" { return blot_support::Option<Kind> { true, view }; }
    if text == "Link" { return blot_support::Option<Kind> { true, link }; }
    return blot_support::Option<Kind> { false, 0 };
}
fn name(kind: Kind) -> const u8[:] {
    match kind { 20 => { return "GrowArray"; }, 21 => { return "ResizeArray"; },
        22 => { return "Ref"; }, 23 => { return "View"; }, 24 => { return "Link"; },
        _ => { assert(false); return ""; } }
}
fn identity(unit: u32, declaration: u32) -> blot_support::Option<Kind> {
    if unit == 0xffffffff && declaration >= grow && declaration <= link { return blot_support::Option<Kind> { true, declaration }; }
    return blot_support::Option<Kind> { false, 0 };
}
fn make(store: blot_check_types::Store&, kind: Kind, element: blot_check_types::Id) -> blot_check_types::Id, blot_error::Error {
    return store.nominal(blot_check_types::NominalIdentity { 0xffffffff, kind }, [element]);
}
fn info(store, id: blot_check_types::Id) -> blot_support::Option<Info> {
    let node = store.node(id);
    if node.tag != blot_check_types::Tag.nominal { return blot_support::Option<Info> { false, default<Info>() }; }
    let kind = identity(node.a, node.b);
    if !kind.present { return blot_support::Option<Info> { false, default<Info>() }; }
    let arguments = store.nominalArguments(node);
    if arguments.len != 1 { return blot_support::Option<Info> { false, default<Info>() }; }
    return blot_support::Option<Info> { true, Info { kind.value, arguments[0] } };
}
fn arrayElement(store, id: blot_check_types::Id) -> blot_support::Option<blot_check_types::Id> {
    let node = store.node(id);
    if node.tag == blot_check_types::Tag.array { return blot_support::Option<blot_check_types::Id> { true, node.a }; }
    let value = info(store, id);
    if value.present && (value.value.kind == grow || value.value.kind == resize) {
        return blot_support::Option<blot_check_types::Id> { true, value.value.element };
    }
    return blot_support::Option<blot_check_types::Id> { false, 0 };
}
fn isArray(store, id: blot_check_types::Id) -> bool { return arrayElement(store, id).present; }
fn readableElement(store, id: blot_check_types::Id) -> blot_support::Option<blot_check_types::Id> {
    let element = arrayElement(store, id);
    if element.present { return element; }
    let value = info(store, id);
    if value.present && value.value.kind == view { return blot_support::Option<blot_check_types::Id> { true, value.value.element }; }
    return blot_support::Option<blot_check_types::Id> { false, 0 };
}
