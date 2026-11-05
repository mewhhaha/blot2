// Partial machine requirements own a separate namespace. Hole zero never
// becomes semantic type evidence or guest authority.
namespace blot_reuse_code_expectation;
import std;
import dictionary;
import eval.type_evidence;
import support.error;
import support.bytes;
import support.native;
import support.wyhash;

type Error = blot_error::Error;
type Id = u32;
type Tag = blot_eval_type_evidence::Tag;
type Node = blot_eval_type_evidence::Node;
struct View { nodes: const Node[:], extra: const Id[:] }
struct Store {
    owner_id: u64, nodes: Node[>..<]&, extra: Id[>..<]&,
    next: Id[>..<]&, buckets: dictionary<u64, Id>&,
}
fn node(view: View, id: Id) -> Node { view.nodes[id] }
fn children(view: View, id: Id) -> const Id[:] {
    let n = view.node(id);
    match n.tag {
        Tag.product => { return view.extra[n.a..n.a + n.b]; },
        Tag.record => { return view.extra[n.a..n.a + n.b * 2]; },
        Tag.nominal => { return view.extra[n.c + 1..n.c + 1 + view.extra[n.c]]; },
        Tag.forall => { return view.extra[n.c..n.c + n.b]; },
        Tag.existential => { return view.extra[n.c..n.c + n.b]; },
        _ => { return view.extra[..0]; },
    }
}
fn init(nodes: Node[>..<]&, extra: Id[>..<]&, next: Id[>..<]&, buckets: dictionary<u64, Id>&) -> Store, Error {
    nodes.clear(); extra.clear(); next.clear(); buckets.clear();
    let tags = [Tag.absent, Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32, Tag.never];
    for tag in tags { nodes.push(Node { tag: tag }); next.push(0); }
    return Store { blot_native::fresh_owner_id(), nodes, extra, next, buckets }, Error.none;
}
fn deinit(store: Store&) { store.nodes.clear(); store.extra.clear(); store.next.clear(); store.buckets.clear(); }
fn view(store: Store&) -> View { View { store.nodes, store.extra } }
fn intern(store: Store&, tag: Tag, a: u32, b: u32, values: const Id[:]) -> Id, Error {
    return internFields(store, tag, a, b, 0, values);
}
fn internBound(store: Store&, ordinal: u32, sort: u32, depth: u32) -> Id, Error {
    return internFields(store, Tag.bound, ordinal, sort, depth, []);
}
fn internStateProvider(store: Store&, read: Id, write: Id, state: Id) -> Id, Error {
    return internFields(store, Tag.state_provider, read, write, state, []);
}
recursive fn internFields(store: Store&, tag: Tag, a: u32, b: u32, c: u32, values: const Id[:]) -> Id, Error {
    if (tag == Tag.forall || tag == Tag.existential) && values.len == 0 {
        if b == 0 || b > 128 { return 0, Error.type_mismatch; }
        var binders: Id[128] = default<Id[128]>();
        for ordinal in b {
            let value, error = intern(store, Tag.bound, ordinal, 0, []);
            if error != Error.none { return 0, error; }
            binders[ordinal] = value;
        }
        return internFields(store, tag, a, b, c, binders[..b]);
    }
    match tag {
        Tag.scoped => { return 0, Error.type_mismatch; },
        Tag.projection => { return 0, Error.type_mismatch; },
        Tag.forall, Tag.existential => {
            if a == 0 || a >= store.nodes.len || b == 0 || b > 128 || c != 0 || values.len != b {
                return 0, Error.type_mismatch;
            }
            for binder, ordinal in values {
                if binder == 0 || binder >= store.nodes.len { return 0, Error.type_mismatch; }
                let leaf = store.nodes[binder];
                if leaf.tag != Tag.bound || leaf.a != ordinal || leaf.b > 2 || leaf.c != 0 ||
                    tag == Tag.existential && leaf.b != 0 { return 0, Error.type_mismatch; }
            }
        },
        Tag.bound => {
            if a >= 128 || b > 2 || c >= 128 || values.len != 0 { return 0, Error.type_mismatch; }
        },
        Tag.usage => {
            if a >= store.nodes.len || b > 2 || c != 0 || values.len != 0 { return 0, Error.type_mismatch; }
        },
        Tag.erased_proof => {
            if a != 0 || b != 0 || c != 0 || values.len != 0 { return 0, Error.type_mismatch; }
        },
        Tag.absent, Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32, Tag.never => {
            if a != 0 || b != 0 || values.len != 0 { return 0, Error.type_mismatch; }
            return blot_eval_type_evidence::tagCode(tag) as u32, Error.none;
        },
        Tag.function => {
            if values.len != 0 || a >= store.nodes.len || b >= store.nodes.len { return 0, Error.type_mismatch; }
        },
        Tag.array, Tag.list, Tag.cursor, Tag.resolver, Tag.provider => {
            if values.len != 0 || a >= store.nodes.len || b != 0 { return 0, Error.type_mismatch; }
        },
        Tag.state_provider => {
            if values.len != 0 || a >= store.nodes.len || b >= store.nodes.len || c >= store.nodes.len {
                return 0, Error.type_mismatch;
            }
        },
        Tag.product, Tag.record => {
            if a != 0 || b != 0 || tag == Tag.record && values.len % 2 != 0 { return 0, Error.type_mismatch; }
        },
        Tag.nominal, Tag.type_constructor => {
            if a == 0 || b == 0 || tag == Tag.type_constructor && values.len != 0 { return 0, Error.type_mismatch; }
        },
    }
    for value, index in values {
        if tag == Tag.record && index % 2 == 0 {
            if value == 0 { return 0, Error.type_mismatch; }
        } else if value >= store.nodes.len { return 0, Error.type_mismatch; }
    }
    var hash = blot_support_wyhash::init(0);
    hash.value(blot_eval_type_evidence::tagCode(tag)); hash.value(a); hash.value(b); hash.value(c);
    for value in values { hash.value(value); }
    let fingerprint = hash.final();
    var head: Id = 0;
    { let optional_source_2 .= store.buckets.get(fingerprint); if optional_source_2 { let found = optional_source_2; head = found;  } }
    var candidate = head;
    while candidate != 0 {
        let n = store.nodes[candidate];
        var same = n.tag == tag;
        if same {
            match tag {
                Tag.product, Tag.record => { same = children(store.view(), candidate) == values; },
                Tag.nominal, Tag.forall, Tag.existential => {
                    same = n.a == a && n.b == b && children(store.view(), candidate) == values;
                },
                _ => { same = n.a == a && n.b == b && n.c == c; },
            }
        }
        if same { return candidate, Error.none; }
        candidate = store.next[candidate];
    }
    if store.nodes.len >= 4294967295 || values.len >= 4294967295 ||
        store.extra.len > 4294967295 - values.len - 1 { return 0, Error.expectation_limit; }
    var n = Node { tag, a, b, c };
    match tag {
        Tag.product, Tag.record => {
            n.a = store.extra.len as u32;
            n.b = values.len as u32;
            if tag == Tag.record { n.b /= 2; }
            store.extra.append(values);
        },
        Tag.forall, Tag.existential => { n.c = store.extra.len as u32; store.extra.append(values); },
        Tag.nominal => {
            n.c = store.extra.len as u32; store.extra.push(values.len as u32); store.extra.append(values);
        },
        _ => {},
    }
    let id = store.nodes.len as Id;
    store.nodes.push(n); store.next.push(head); store.buckets.insert(fingerprint, id);
    return id, Error.none;
}
