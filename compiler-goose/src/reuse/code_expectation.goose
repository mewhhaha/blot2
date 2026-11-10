// Partial machine requirements own a separate namespace. Hole zero never
// becomes semantic type evidence or guest authority.
namespace blot_reuse_code_expectation;
import std;
import dictionary;
import eval.type_evidence_schema;
import support.error;
import support.bytes;
import support.native;
import support.wyhash;
import support.pooled_buffer;

type Error = blot_error::Error;
type Id = u32;
type Tag = blot_eval_type_evidence::Tag;
type Node = blot_eval_type_evidence::Node;
struct View { nodes: const Node[:], extra: const Id[:] }
struct Nodes {storage:Node[:]=default<Node[:]>(),items:Node[:]=default<Node[:]>(),len:i64=0}
reusable[] var pool_Nodes:Node[>..]=[];
fn ensure(self_:Nodes&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self_,minimum,pool_Nodes);}
fn push(self_:Nodes&,value:Node)->Error {let error=blot_support_pooled_buffer::push(self_,value,pool_Nodes);self_.len=self_.items.len;return error;}
fn append(self_:Nodes&,values:const Node[:])->Error {let error=blot_support_pooled_buffer::append(self_,values,pool_Nodes);self_.len=self_.items.len;return error;}
fn clear(self_:Nodes&) {blot_support_pooled_buffer::clear(self_);self_.len=0;}
fn deinit(self_:Nodes&) {blot_support_pooled_buffer::deinit(self_,pool_Nodes);self_.len=0;}
struct Ids {storage:Id[:]=default<Id[:]>(),items:Id[:]=default<Id[:]>(),len:i64=0}
reusable[] var pool_Ids:Id[>..]=[];
fn ensure(self_:Ids&,minimum:i64)->Error {return blot_support_pooled_buffer::ensure(self_,minimum,pool_Ids);}
fn push(self_:Ids&,value:Id)->Error {let error=blot_support_pooled_buffer::push(self_,value,pool_Ids);self_.len=self_.items.len;return error;}
fn append(self_:Ids&,values:const Id[:])->Error {let error=blot_support_pooled_buffer::append(self_,values,pool_Ids);self_.len=self_.items.len;return error;}
fn clear(self_:Ids&) {blot_support_pooled_buffer::clear(self_);self_.len=0;}
fn deinit(self_:Ids&) {blot_support_pooled_buffer::deinit(self_,pool_Ids);self_.len=0;}
struct Store {
    owner_id: u64, nodes: Nodes&, extra: Ids&,
    next: Ids&, buckets: dictionary<u64, Id>&,
}
fn node(view: View, id: Id) -> Node { view.nodes[id] }
fn children(view: View, id: Id) -> const Id[:] {
    let n = view.node(id);
    match n.tag {
        product => { return view.extra[n.a..n.a + n.b]; },
        record => { return view.extra[n.a..n.a + n.b * 2]; },
        nominal => { return view.extra[n.c + 1..n.c + 1 + view.extra[n.c]]; },
        forall => { return view.extra[n.c..n.c + n.b]; },
        existential => { return view.extra[n.c..n.c + n.b]; },
        _ => { return view.extra[..0]; },
    }
}
fn seed(store:Store&)->u64,Error {
    store.nodes.clear();store.extra.clear();store.next.clear();::clear(store.buckets);
    let owner=blot_native::fresh_owner_id();
    let node_error=store.nodes.ensure(6);if node_error!=blot_error::Error.none {return owner,node_error;}
    let next_error=store.next.ensure(6);if next_error!=blot_error::Error.none {return owner,next_error;}
    let tags=[blot_eval_type_evidence::Tag.absent,blot_eval_type_evidence::Tag.unit,blot_eval_type_evidence::Tag.boolean,blot_eval_type_evidence::Tag.unsigned32,blot_eval_type_evidence::Tag.floating32,blot_eval_type_evidence::Tag.never];
    for tag in tags {store.nodes.push(Node{tag:tag,..});store.next.push(0);}
    return owner,blot_error::Error.none;
}
fn init(nodes:Nodes&,extra:Ids&,next:Ids&,buckets:dictionary<u64,Id>&)->Store,Error {
    var store=Store{0,nodes,extra,next,buckets};let owner,error=seed(store);store.owner_id=owner;return store,error;
}
fn reset(store:Store&)->Error {
    let owner,error=seed(store);if error==blot_error::Error.none {store.owner_id=owner;}return error;
}
fn deinit(store: Store&) { store.nodes.clear(); store.extra.clear(); store.next.clear(); ::clear(store.buckets); }
fn view(store: Store&) -> View { View { store.nodes.items, store.extra.items } }
recursive fn intern(store: Store&, tag: Tag, a: u32, b: u32, values: const Id[:]) -> Id, Error {
    return internFields(store, tag, a, b, 0, values);
}
fn internBound(store: Store&, ordinal: u32, sort: u32, depth: u32) -> Id, Error {
    return internFields(store, blot_eval_type_evidence::Tag.bound, ordinal, sort, depth, []);
}
fn internStateProvider(store: Store&, read: Id, write: Id, state: Id) -> Id, Error {
    return internFields(store, blot_eval_type_evidence::Tag.state_provider, read, write, state, []);
}
recursive fn internFields(store: Store&, tag: Tag, a: u32, b: u32, c: u32, values: const Id[:]) -> Id, Error {
    if (tag == blot_eval_type_evidence::Tag.forall || tag == blot_eval_type_evidence::Tag.existential) && values.len == 0 {
        if b == 0 || b > 128 { return 0, blot_error::Error.type_mismatch; }
        var binders: Id[128] = default<Id[128]>();
        for ordinal in b {
            let value, error = intern(store, blot_eval_type_evidence::Tag.bound, ordinal, 0, []);
            if error != blot_error::Error.none { return 0, error; }
            binders[ordinal] = value;
        }
        return internFields(store, tag, a, b, c, binders[..b]);
    }
    match tag {
        scoped => { return 0, blot_error::Error.type_mismatch; },
        projection => { return 0, blot_error::Error.type_mismatch; },
        forall, existential => {
            if a == 0 || a >= store.nodes.len || b == 0 || b > 128 || c != 0 || values.len != b {
                return 0, blot_error::Error.type_mismatch;
            }
            for binder, ordinal in values {
                if binder == 0 || binder >= store.nodes.len { return 0, blot_error::Error.type_mismatch; }
                let leaf = store.nodes.items[binder];
                if leaf.tag != blot_eval_type_evidence::Tag.bound || leaf.a != ordinal || leaf.b > 2 || leaf.c != 0 ||
                    tag == blot_eval_type_evidence::Tag.existential && leaf.b != 0 { return 0, blot_error::Error.type_mismatch; }
            }
        },
        bound => {
            if a >= 128 || b > 2 || c >= 128 || values.len != 0 { return 0, blot_error::Error.type_mismatch; }
        },
        usage => {
            if a >= store.nodes.len || b > 2 || c != 0 || values.len != 0 { return 0, blot_error::Error.type_mismatch; }
        },
        erased_proof => {
            if a != 0 || b != 0 || c != 0 || values.len != 0 { return 0, blot_error::Error.type_mismatch; }
        },
        absent, unit, boolean, unsigned32, floating32, never => {
            if a != 0 || b != 0 || values.len != 0 { return 0, blot_error::Error.type_mismatch; }
            return blot_eval_type_evidence::tagCode(tag) as u32, blot_error::Error.none;
        },
        function => {
            if values.len != 0 || a >= store.nodes.len || b >= store.nodes.len { return 0, blot_error::Error.type_mismatch; }
        },
        array, list, cursor, resolver, provider => {
            if values.len != 0 || a >= store.nodes.len || b != 0 { return 0, blot_error::Error.type_mismatch; }
        },
        state_provider => {
            if values.len != 0 || a >= store.nodes.len || b >= store.nodes.len || c >= store.nodes.len {
                return 0, blot_error::Error.type_mismatch;
            }
        },
        product, record => {
            if a != 0 || b != 0 || tag == blot_eval_type_evidence::Tag.record && values.len % 2 != 0 { return 0, blot_error::Error.type_mismatch; }
        },
        nominal, type_constructor => {
            if a == 0 || b == 0 || tag == blot_eval_type_evidence::Tag.type_constructor && values.len != 0 { return 0, blot_error::Error.type_mismatch; }
        },
    }
    for value, index in values {
        if tag == blot_eval_type_evidence::Tag.record && index % 2 == 0 {
            if value == 0 { return 0, blot_error::Error.type_mismatch; }
        } else if value >= store.nodes.len { return 0, blot_error::Error.type_mismatch; }
    }
    var hash = blot_support_wyhash::init(0);
    hash.value(blot_eval_type_evidence::tagCode(tag)); hash.value(a); hash.value(b); hash.value(c);
    for value in values { hash.value(value); }
    let fingerprint = hash.final();
    var head: Id = 0;
    { let optional_source_2 .= ::get(store.buckets,fingerprint); if optional_source_2 { let found = optional_source_2; head = found;  } }
    var candidate = head;
    while candidate != 0 {
        let n = store.nodes.items[candidate];
        var same = n.tag == tag;
        if same {
            match tag {
                product, record => { same = children(store.view(), candidate) == values; },
                nominal, forall, existential => {
                    same = n.a == a && n.b == b && children(store.view(), candidate) == values;
                },
                _ => { same = n.a == a && n.b == b && n.c == c; },
            }
        }
        if same { return candidate, blot_error::Error.none; }
        candidate = store.next.items[candidate];
    }
    if store.nodes.len >= 4294967295 || values.len >= 4294967295 ||
        store.extra.len > 4294967295 - values.len - 1 { return 0, blot_error::Error.expectation_limit; }
    let node_error=store.nodes.ensure(store.nodes.len+1);if node_error!=blot_error::Error.none {return 0,node_error;}
    let next_error=store.next.ensure(store.next.len+1);if next_error!=blot_error::Error.none {return 0,next_error;}
    let extra_error=store.extra.ensure(store.extra.len+values.len+1);if extra_error!=blot_error::Error.none {return 0,extra_error;}
    var n = Node { tag, a, b, c , ..};
    match tag {
        product, record => {
            n.a = store.extra.len as u32;
            n.b = values.len as u32;
            if tag == blot_eval_type_evidence::Tag.record { n.b /= 2; }
            store.extra.append(values);
        },
        forall, existential => { n.c = store.extra.len as u32; store.extra.append(values); },
        nominal => {
            n.c = store.extra.len as u32; store.extra.push(values.len as u32); store.extra.append(values);
        },
        _ => {},
    }
    let id = store.nodes.len as Id;
    store.nodes.push(n); store.next.push(head); ::insert(store.buckets,fingerprint,id);
    return id, blot_error::Error.none;
}
