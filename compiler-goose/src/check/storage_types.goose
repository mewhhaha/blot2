// Storage identities belong to the compiler and never coerce ordinary arrays.
namespace squid_check_storage_types;
import check.types;
import support.error;
import support.option;

import std;
type Kind = u32;
let ref: Kind = 22;
let view: Kind = 23;
let link: Kind = 24;
let shared: Kind = 25;
let sized_array: Kind = 26;
let packed: Kind = 27;
let seq: Kind = 28;
let length_literal_base: u32 = 0x10000000;
let length_literal_limit: u32 = 0x80000000;

struct Info { kind: Kind, element: squid_check_types::Id }

fn isLengthLiteral(unit: u32, declaration: u32) -> bool {
    return unit == 0xffffffff && declaration >= length_literal_base && declaration < length_literal_limit;
}
fn lengthLiteralValue(declaration: u32) -> u32 { return declaration - length_literal_base; }
fn parseLengthLiteral(spelling: const u8[:]) -> squid_support::Option<u32> {
    if !starts_with(spelling, "@storage.Len.") { return squid_support::Option<u32> { false, 0, .. }; }
    let digits = spelling[13..];
    if digits.len == 0 { return squid_support::Option<u32> { false, 0, .. }; }
    var value: u32 = 0;
    for ch in digits {
        if ch < '0' as u8 || ch > '9' as u8 { return squid_support::Option<u32> { false, 0, .. }; }
        let d = (ch - '0' as u8) as u32;
        if value > (0x6fffffff - d) / 10 { return squid_support::Option<u32> { false, 0, .. }; }
        value = value * 10 + d;
    }
    return squid_support::Option<u32> { true, value, .. };
}
fn makeLengthLiteral(store: squid_check_types::Store&, value: u32) -> squid_check_types::Id, squid_error::Error {
    return store.nominal(squid_check_types::NominalIdentity { 0xffffffff, length_literal_base + value, .. }, []);
}
fn arity(kind: Kind) -> u32 {
    if kind == sized_array { return 2; }
    return 1;
}
fn isSized(kind: Kind) -> bool { return kind == sized_array; }

fn named(spelling: const u8[:]) -> squid_support::Option<Kind> {
    var text = spelling;
    if starts_with(text, "@storage.") { text = text[9..]; }
    if text == "Ref" { return squid_support::Option<Kind> { true, ref , ..}; }
    if text == "View" { return squid_support::Option<Kind> { true, view , ..}; }
    if text == "Link" { return squid_support::Option<Kind> { true, link , ..}; }
    if text == "Shared" { return squid_support::Option<Kind> { true, shared , ..}; }
    if text == "SizedArray" { return squid_support::Option<Kind> { true, sized_array , ..}; }
    if text == "Packed" { return squid_support::Option<Kind> { true, packed , ..}; }
    if text == "Seq" { return squid_support::Option<Kind> { true, seq , ..}; }
    return squid_support::Option<Kind> { false, 0 , ..};
}
fn name(kind: Kind) -> const u8[:] {
    match kind {
        22 => { return "Ref"; },
        23 => { return "View"; },
        24 => { return "Link"; },
        25 => { return "Shared"; },
        26 => { return "SizedArray"; },
        27 => { return "Packed"; },
        28 => { return "Seq"; },
        _ => { assert(false); return ""; },
    }
}
fn identity(unit: u32, declaration: u32) -> squid_support::Option<Kind> {
    if unit == 0xffffffff && declaration >= ref && declaration <= seq {
        return squid_support::Option<Kind> { true, declaration , ..};
    }
    return squid_support::Option<Kind> { false, 0 , ..};
}
fn make(store: squid_check_types::Store&, kind: Kind, element: squid_check_types::Id) -> squid_check_types::Id, squid_error::Error {
    return store.nominal(squid_check_types::NominalIdentity { 0xffffffff, kind , ..}, [element]);
}
fn makeSized(store: squid_check_types::Store&, kind: Kind, length: squid_check_types::Id, element: squid_check_types::Id) -> squid_check_types::Id, squid_error::Error {
    return store.nominal(squid_check_types::NominalIdentity { 0xffffffff, kind , ..}, [length, element]);
}
fn info(store, id: squid_check_types::Id) -> squid_support::Option<Info> {
    let node = store.node(id);
    if node.tag != squid_check_types::Tag.nominal { return squid_support::Option<Info> { false, default<Info>() , ..}; }
    let kind = identity(node.a, node.b);
    if !kind.present { return squid_support::Option<Info> { false, default<Info>() , ..}; }
    let arguments = store.nominalArguments(node);
    if isSized(kind.value) {
        if arguments.len != 2 { return squid_support::Option<Info> { false, default<Info>() , ..}; }
        return squid_support::Option<Info> { true, Info { kind.value, arguments[1] , ..} , ..};
    }
    if arguments.len != 1 { return squid_support::Option<Info> { false, default<Info>() , ..}; }
    return squid_support::Option<Info> { true, Info { kind.value, arguments[0] , ..} , ..};
}
fn lengthOf(store, id: squid_check_types::Id) -> squid_support::Option<squid_check_types::Id> {
    let node = store.node(id);
    if node.tag != squid_check_types::Tag.nominal { return squid_support::Option<squid_check_types::Id> { false, 0 , ..}; }
    let kind = identity(node.a, node.b);
    if !kind.present || !isSized(kind.value) { return squid_support::Option<squid_check_types::Id> { false, 0 , ..}; }
    let arguments = store.nominalArguments(node);
    if arguments.len != 2 { return squid_support::Option<squid_check_types::Id> { false, 0 , ..}; }
    return squid_support::Option<squid_check_types::Id> { true, arguments[0] , ..};
}
fn sharedInner(store, id: squid_check_types::Id) -> squid_support::Option<squid_check_types::Id> {
    let value = info(store, id);
    if value.present && value.value.kind == shared {
        return squid_support::Option<squid_check_types::Id> { true, value.value.element , ..};
    }
    return squid_support::Option<squid_check_types::Id> { false, 0 , ..};
}
fn isShared(store, id: squid_check_types::Id) -> bool { return sharedInner(store, id).present; }
fn unwrapShared(store, id: squid_check_types::Id) -> squid_check_types::Id {
    let inner = sharedInner(store, id);
    if inner.present { return inner.value; }
    return id;
}
fn arrayElement(store, id: squid_check_types::Id) -> squid_support::Option<squid_check_types::Id> {
    let node = store.node(id);
    if node.tag == squid_check_types::Tag.array { return squid_support::Option<squid_check_types::Id> { true, node.a , ..}; }
    let value = info(store, id);
    if value.present && value.value.kind == sized_array {
        return squid_support::Option<squid_check_types::Id> { true, value.value.element , ..};
    }
    return squid_support::Option<squid_check_types::Id> { false, 0 , ..};
}
fn isArray(store, id: squid_check_types::Id) -> bool { return arrayElement(store, id).present; }
fn readableElement(store, id: squid_check_types::Id) -> squid_support::Option<squid_check_types::Id> {
    let element = arrayElement(store, id);
    if element.present { return element; }
    let value = info(store, id);
    if value.present && value.value.kind == view { return squid_support::Option<squid_check_types::Id> { true, value.value.element , ..}; }
    if value.present && value.value.kind == shared {
        let inner = arrayElement(store, value.value.element);
        if inner.present { return inner; }
    }
    return squid_support::Option<squid_check_types::Id> { false, 0 , ..};
}


fn packedElement(store, id: squid_check_types::Id) -> squid_support::Option<squid_check_types::Id> {
    let value = info(store, id);
    if value.present && value.value.kind == packed {
        return squid_support::Option<squid_check_types::Id> { true, value.value.element , ..};
    }
    if value.present && value.value.kind == shared {
        let inner = info(store, value.value.element);
        if inner.present && inner.value.kind == packed {
            return squid_support::Option<squid_check_types::Id> { true, inner.value.element , ..};
        }
    }
    return squid_support::Option<squid_check_types::Id> { false, 0 , ..};
}
fn isPacked(store, id: squid_check_types::Id) -> bool { return packedElement(store, id).present; }
fn isOwnedPacked(store, id: squid_check_types::Id) -> bool {
    let value = info(store, id);
    return value.present && value.value.kind == packed;
}
fn seqElement(store, id: squid_check_types::Id) -> squid_support::Option<squid_check_types::Id> {
    let value = info(store, id);
    if value.present && value.value.kind == seq {
        return squid_support::Option<squid_check_types::Id> { true, value.value.element , ..};
    }
    if value.present && value.value.kind == shared {
        let inner = info(store, value.value.element);
        if inner.present && inner.value.kind == seq {
            return squid_support::Option<squid_check_types::Id> { true, inner.value.element , ..};
        }
    }
    return squid_support::Option<squid_check_types::Id> { false, 0 , ..};
}
fn isSeq(store, id: squid_check_types::Id) -> bool { return seqElement(store, id).present; }
fn isOwnedSeq(store, id: squid_check_types::Id) -> bool {
    let value = info(store, id);
    return value.present && value.value.kind == seq;
}
fn ownedSeqElement(store, id: squid_check_types::Id) -> squid_support::Option<squid_check_types::Id> {
    let value = info(store, id);
    if value.present && value.value.kind == seq {
        return squid_support::Option<squid_check_types::Id> { true, value.value.element , ..};
    }
    return squid_support::Option<squid_check_types::Id> { false, 0 , ..};
}
fn indexReadableElement(store, id: squid_check_types::Id) -> squid_support::Option<squid_check_types::Id> {
    let element = readableElement(store, id);
    if element.present { return element; }
    return seqElement(store, id);
}
fn indexWritableElement(store, id: squid_check_types::Id) -> squid_support::Option<squid_check_types::Id> {
    let element = arrayElement(store, id);
    if element.present { return element; }
    return ownedSeqElement(store, id);
}
fn iterableElement(store, id: squid_check_types::Id) -> squid_support::Option<squid_check_types::Id> {
    let element = readableElement(store, id);
    if element.present { return element; }
    let packed_elem = packedElement(store, id);
    if packed_elem.present { return packed_elem; }
    return seqElement(store, id);
}


// A collection obligation carries its access mode in the existing signature
// slot. The marker survives scheme instantiation and project transport.
let iteration: u32 = 0;       // Absent signature.
let indexed_read: u32 = 1;    // Built-in Unit type ID.
let indexed_write: u32 = 2;   // Built-in Bool type ID.

fn collectionElement(store, id: squid_check_types::Id, mode: u32) -> squid_support::Option<squid_check_types::Id> {
    if mode == indexed_write { return indexWritableElement(store, id); }
    if mode == indexed_read { return indexReadableElement(store, id); }
    return iterableElement(store, id);
}
