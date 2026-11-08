// Interned physical representation evidence, independently owned from inference.
namespace blot_backend_layout;
import parse.ast;
import std;
import dictionary;
import .runtime_ir;
import .wasm;
import check.core;
import check.types;
import check.record_order;
import check.task_types;
import check.typed_staging;
import check.rank_equal;
import eval.type_evidence;
import check.effect_evidence;
import .opaque_storage;
import reuse.code_expectation;
import reuse.principal_interface;
import support.error;
import support.option;
import support.wyhash;
import support.pooled_buffer;

type Id = u32;
let word: Id = 3;
let erased: Id = 6;
let capability_layout_decl: u32 = 7;
let unknown_row: u32 = 4294967295;
enum Tag { invalid, unit, boolean, unsigned32, floating32, never, product, record, nominal, array, list, cursor, function, type_constructor, resolver, erased, provider, state_provider, erased_proof, existential, opened, universal, scoped, owning, associated }
let tags = [Tag.invalid, Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32, Tag.never, Tag.product, Tag.record, Tag.nominal, Tag.array, Tag.list, Tag.cursor, Tag.function, Tag.type_constructor, Tag.resolver, Tag.erased, Tag.provider, Tag.state_provider, Tag.erased_proof, Tag.existential, Tag.opened, Tag.universal, Tag.scoped, Tag.owning, Tag.associated];
fn tagCode(tag: Tag) -> u8 { for value, index in tags { if value == tag { return index as u8; } } abort("invalid layout tag"); }
fn tagFromCode(code: u8) -> Tag, blot_error::Error { if code >= tags.len { return Tag.invalid, blot_error::Error.type_mismatch; } return tags[code], blot_error::Error.none; }
struct Node { tag: Tag = Tag.invalid, a: u32 = 0, b: u32 = 0, c: u32 = 0 }
struct Mapping { variable: blot_check_types::Id, layout: Id, instance: blot_check_types::NominalIdentity }
struct MappingBuffer { storage: Mapping[:]=default<Mapping[:]>(),items: Mapping[:]=default<Mapping[:]>(),failure: blot_error::Error=blot_error::Error.none }
reusable[] var pool_MappingBuffer: Mapping[>..]=[];
fn push(self_:MappingBuffer&,value:Mapping) { if self_.failure==blot_error::Error.none {self_.failure=blot_support_pooled_buffer::push(self_,value,pool_MappingBuffer);} }
fn deinit(self_:MappingBuffer&) {blot_support_pooled_buffer::deinit(self_,pool_MappingBuffer);self_.failure=blot_error::Error.none;}
struct RowMapping { variable: u32, row: u32 }
struct UniversalDictionaries { owner: Id, start: u32, len: u32 }
fn mappedInstance(original: blot_check_types::NominalIdentity, mappings: const Mapping[:]) -> blot_check_types::NominalIdentity {
    if original.unit != 0 || original.decl == 0 { return original; }
    for mapping in mappings { if mapping.variable == original.decl && mapping.instance.decl != 0 { return mapping.instance; } } return original;
}
struct ClosedUnit { kinds: blot_backend_runtime_ir::Range }
struct ClosedLayouts {
    units: const blot_check_core::Module[:], kinds: ClosedUnit[>..<]&, kind_bytes: u8[>..<]&, layouts: dictionary<u64, Id>&,
}
struct Store {
    closed: ClosedLayouts, opaque_sources: const blot_check_core::Module[:], record_names: blot_check_record_order::Names,
    effects: blot_check_effect_evidence::Store,
    nodes: Node[>..<]&, extra: u32[>..<]&, universal_dictionaries: UniversalDictionaries[>..<]&, next: Id[>..<]&, buckets: dictionary<u64, Id>&,
    solver_owners: blot_backend_runtime_ir::Range[>..<]&, solver_binders: u32[>..<]&, type_owners: blot_check_types::Id[>..<]&,
}
// Private probes enter with one lexical set of typed owners. Their callback
// returns before any of this physical store's backing storage is released.
fn withStore<C,F>(context: C&) -> blot_error::Error {
    var closed_units: ClosedUnit[>..<] = []; var closed_kind_bytes: u8[>..<] = []; var closed_layouts: dictionary<u64,Id> = dictionary<u64,Id>{}; var names: dictionary<u32,const u8[:]> = dictionary<u32,const u8[:]>{};
    var nodes: Node[>..<] = []; var extra: u32[>..<] = []; var universal_dictionaries: UniversalDictionaries[>..<] = []; var next: u32[>..<] = []; var buckets: dictionary<u64,u32> = dictionary<u64,u32>{}; var solver_owners: blot_backend_runtime_ir::Range[>..<] = []; var solver_binders: u32[>..<] = []; var type_owners: u32[>..<] = [];
    let effects,error = blot_check_effect_evidence::init(); if error != blot_error::Error.none { return error; }
    var store = Store { closed: ClosedLayouts { units: [],kinds: closed_units,kind_bytes: closed_kind_bytes,layouts: closed_layouts , ..},opaque_sources: [],record_names: blot_check_record_order::init(names),effects: effects,nodes: nodes,extra: extra,universal_dictionaries: universal_dictionaries,next: next,buckets: buckets,solver_owners: solver_owners,solver_binders: solver_binders,type_owners: type_owners , ..};
    let initialized = init(store); if initialized != blot_error::Error.none { store.deinit(); return initialized; } let result = F(context,store); store.deinit(); return result;
}
fn init(store: Store&) -> blot_error::Error {
    store.nodes.clear(); store.next.clear(); store.extra.clear(); store.universal_dictionaries.clear(); store.buckets.clear(); store.solver_owners.clear(); store.solver_binders.clear(); store.type_owners.clear();
    assert(store.effects.rows.len != 0); // Caller initializes the effect-evidence context from its Tables first.
    for tag in [Tag.invalid, Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32, Tag.never, Tag.erased] { store.nodes.push(Node { tag: tag , ..}); store.next.push(0); }
    return blot_error::Error.none;
}
fn node(store: const Store&, id: Id) -> Node { store.nodes[id] }
fn children(store: const Store&, id: Id) -> const Id[:] {
    let n = node(store, id);
    if n.tag == Tag.product { return store.extra[n.a..n.a + n.b]; }
    if n.tag == Tag.record { return store.extra[n.a..n.a + n.b * 2]; }
    if n.tag == Tag.nominal { return store.extra[n.c + 1..n.c + 1 + store.extra[n.c]]; }
    if n.tag == Tag.universal || n.tag == Tag.existential { return store.extra[n.c..n.c + n.b]; }
    return store.extra[..0];
}
fn dictionaryRecord(store: const Store&, owner: Id) -> blot_support::Option<UniversalDictionaries> {
    var low = 0; var high = store.universal_dictionaries.len;
    while low < high { let middle = low + (high - low) / 2; let record = store.universal_dictionaries[middle]; if record.owner < owner { low = middle + 1; } else { high = middle; } }
    if low == store.universal_dictionaries.len || store.universal_dictionaries[low].owner != owner { return blot_support::none<UniversalDictionaries>(); }
    return blot_support::some(store.universal_dictionaries[low]);
}
fn hasDictionaryABI(store: const Store&, owner: Id) -> bool { dictionaryRecord(store, owner).present }
fn dictionarySlots(store: const Store&, owner: Id) -> const Id[:] { let record = dictionaryRecord(store, owner); if !record.present { return store.extra[..0]; } return store.extra[record.value.start..record.value.start + record.value.len]; }
fn internAssociated(store: Store&, goal: u32, member: u32, scope: u32) -> Id, blot_error::Error {
    if goal >= 4096 || member == 0 || scope >= 128 { return 0, blot_error::Error.type_mismatch; }
    return internFields(store, Tag.associated, goal, member, scope, []);
}
fn internUniversalWithDictionaries(store: Store&, body: Id, binders: const Id[:], slots: const Id[:]) -> Id, blot_error::Error {
    if slots.len > 65536 { return 0, blot_error::Error.layout_limit; }
    let ordinary, error = intern(store, Tag.universal, body, binders.len as u32, binders); if error != blot_error::Error.none { return 0, error; }
    for slot in slots { if slot == 0 { continue; } if slot >= store.nodes.len || node(store, slot).tag != Tag.function { return 0, blot_error::Error.type_mismatch; } }
    return internFieldsWithDictionaries(store, Tag.universal, body, binders.len as u32, 0, binders, slots, true);
}
fn hasOwners(store: const Store&, root: Id) -> bool, blot_error::Error {
    var nodes: Id[4096] = [0; 4096]; nodes[0] = root; var count = 1; var cursor = 0;
    while cursor < count {
        let id = nodes[cursor]; cursor++;
        if id >= store.nodes.len { return false, blot_error::Error.layout_limit; }
        let n = node(store, id); if n.tag == Tag.owning { return true, blot_error::Error.none; }
        var direct: Id[3] = [n.a, n.b, n.c]; var selected: const Id[:] = direct[..0];
        if n.tag == Tag.array || n.tag == Tag.list || n.tag == Tag.cursor || n.tag == Tag.resolver || n.tag == Tag.provider || n.tag == Tag.scoped || n.tag == Tag.universal || n.tag == Tag.existential { selected = direct[..1]; }
        else if n.tag == Tag.function { selected = direct[..2]; }
        else if n.tag == Tag.state_provider { selected = direct[..]; }
        else if n.tag == Tag.product || n.tag == Tag.nominal || n.tag == Tag.record { selected = children(store, id); }
        for child, index in selected {
            if n.tag == Tag.record && index % 2 == 0 { continue; }
            var known = false; for prior in nodes[..count] { if prior == child { known = true; break; } }
            if known { continue; } if count == 4096 { return false, blot_error::Error.layout_limit; } nodes[count] = child; count++;
        }
    }
    return false, blot_error::Error.none;
}
fn equal<T>(left: const T[:], right: const T[:]) -> bool { if left.len != right.len { return false; } for value, index in left { if value != right[index] { return false; } } return true; }
fn machine(store: const Store&, id: Id) -> blot_backend_runtime_ir::ValueType { let selected = scalar(store, id); if selected.present { return blot_backend_runtime_ir::machine(selected.value); } return blot_backend_runtime_ir::VT_i32; }
fn listInput(store: const Store&, id: Id) -> bool { let n = node(store, id); return n.tag == Tag.list || (n.tag == Tag.cursor && node(store, n.a).tag == Tag.list); }
fn scalarEnvironment(store: const Store&, captures: Id) -> bool {
    if node(store, captures).tag != Tag.product { return false; } let fields = children(store, captures); if fields.len != 1 { return false; }
    let selected = scalar(store, fields[0]); return selected.present && selected.value != blot_backend_runtime_ir::SC_f32;
}
fn scalar(store: const Store&, id: Id) -> blot_support::Option<blot_backend_runtime_ir::Scalar> { scalarDepth(store, id, 0) }
recursive fn scalarDepth(store: const Store&, id: Id, depth: i64) -> blot_support::Option<blot_backend_runtime_ir::Scalar> {
    if depth >= 128 { return blot_support::none<blot_backend_runtime_ir::Scalar>(); }
    let tag = node(store, id).tag; if tag == Tag.nominal { return opaqueScalar(store, id, depth + 1); }
    if tag == Tag.unit { return blot_support::some(blot_backend_runtime_ir::SC_unit); }
    if tag == Tag.boolean { return blot_support::some(blot_backend_runtime_ir::SC_bool); }
    if tag == Tag.unsigned32 { return blot_support::some(blot_backend_runtime_ir::SC_u32); }
    if tag == Tag.floating32 { return blot_support::some(blot_backend_runtime_ir::SC_f32); }
    return blot_support::none<blot_backend_runtime_ir::Scalar>();
}
recursive fn opaqueScalar(store: const Store&, id: Id, depth: i64) -> blot_support::Option<blot_backend_runtime_ir::Scalar> {
    let n = node(store, id); if n.a == 0 || n.a > store.opaque_sources.len { return blot_support::none<blot_backend_runtime_ir::Scalar>(); }
    let source .= store.opaque_sources[n.a - 1];
    for nominal in source.nominals {
        if !nominal.is_opaque || nominal.identity.decl != n.b { continue; }
        if nominal.storage.kind == blot_backend_opaque_storage::Kind.unit { return blot_support::some(blot_backend_runtime_ir::SC_unit); }
        if nominal.storage.kind == blot_backend_opaque_storage::Kind.boolean { return blot_support::some(blot_backend_runtime_ir::SC_bool); }
        if nominal.storage.kind == blot_backend_opaque_storage::Kind.unsigned32 { return blot_support::some(blot_backend_runtime_ir::SC_u32); }
        if nominal.storage.kind == blot_backend_opaque_storage::Kind.floating32 { return blot_support::some(blot_backend_runtime_ir::SC_f32); }
        if nominal.storage.kind == blot_backend_opaque_storage::Kind.parameter {
            let arguments = children(store, id); if nominal.storage.parameter >= arguments.len { return blot_support::none<blot_backend_runtime_ir::Scalar>(); }
            var ordinal: u32 = 0; var remaining: i64 = 1000000;
            let selected = opaqueParameter(store, source, source.types.list(nominal.parameters)[nominal.storage.parameter], arguments[nominal.storage.parameter], nominal.storage.selector, ordinal, depth + 1, remaining);
            if !selected.present { return blot_support::none<blot_backend_runtime_ir::Scalar>(); } return scalarDepth(store, selected.value, depth + 1);
        }
        return blot_support::none<blot_backend_runtime_ir::Scalar>();
    }
    return blot_support::none<blot_backend_runtime_ir::Scalar>();
}
recursive fn opaqueParameter(store: const Store&, module: const blot_check_core::Module&, parameter: blot_check_types::Id, actual: Id, target: u32, ordinal: u32&, depth: i64, remaining: i64&) -> blot_support::Option<Id> {
    if depth >= 128 || remaining == 0 { return blot_support::none<Id>(); } remaining--;
    let n = module.types.node(parameter);
    if n.tag == blot_check_types::Tag.variable { let selected = ordinal; ordinal++; if selected == target { return blot_support::some(actual); } return blot_support::none<Id>(); }
    let argument = node(store, actual);
    if n.tag == blot_check_types::Tag.product && argument.tag == Tag.product && n.b == argument.b {
        let parameters = module.types.list(blot_check_types::List { start: n.a, len: n.b , ..});
        for child, index in parameters { let selected = opaqueParameter(store, module, child, children(store, actual)[index], target, ordinal, depth + 1, remaining); if selected.present { return selected; } }
    } else if n.tag == blot_check_types::Tag.record && argument.tag == Tag.record {
        for index in 0..n.b { let field = module.types.recordField(n, index); let fields = children(store, actual); for slot in 0..fields.len / 2 { if fields[slot * 2] != field.name { continue; } let selected = opaqueParameter(store, module, field.ty, fields[slot * 2 + 1], target, ordinal, depth + 1, remaining); if selected.present { return selected; } break; } }
    }
    return blot_support::none<Id>();
}
fn abi(store: const Store&, id: Id) -> blot_support::Option<blot_backend_runtime_ir::Scalar> {
    let selected = scalar(store, id); if selected.present { return selected; }
    let n = node(store, id); if n.tag != Tag.array { return blot_support::none<blot_backend_runtime_ir::Scalar>(); }
    if node(store, n.a).tag == Tag.unsigned32 { return blot_support::some(blot_backend_runtime_ir::SC_array_u32); }
    if node(store, n.a).tag == Tag.floating32 { return blot_support::some(blot_backend_runtime_ir::SC_array_f32); }
    return blot_support::none<blot_backend_runtime_ir::Scalar>();
}
recursive fn intern(store: Store&, tag: Tag, a: u32, b: u32, values: const u32[:]) -> Id, blot_error::Error { return internWithEffects(store, tag, a, b, 0, values); }
recursive fn internWithEffects(store: Store&, tag: Tag, a: u32, b: u32, row: u32, values: const u32[:]) -> Id, blot_error::Error {
    if tag == Tag.opened && (a >= 128 || b >= 128 || row > 2 || values.len != 0) { return 0, blot_error::Error.type_mismatch; }
    if tag == Tag.existential || tag == Tag.universal {
        if a == 0 || a >= store.nodes.len || b == 0 || b > 128 || row != 0 { return 0, blot_error::Error.type_mismatch; }
        if values.len == 0 {
            var binders: Id[128] = [0; 128];
            for ordinal in 0..b { let binder, error = intern(store, Tag.opened, ordinal as u32, 0, []); if error != blot_error::Error.none { return 0, error; } binders[ordinal] = binder; }
            return internWithEffects(store, tag, a, b, row, binders[..b]);
        }
        if values.len != b { return 0, blot_error::Error.type_mismatch; }
        for binder, ordinal in values { if binder >= store.nodes.len { return 0, blot_error::Error.type_mismatch; } let leaf = node(store, binder); if leaf.tag != Tag.opened || leaf.a != ordinal || leaf.b != 0 || leaf.c > 2 || (tag == Tag.existential && leaf.c != 0) { return 0, blot_error::Error.type_mismatch; } }
    }
    if tag == Tag.nominal && a != 0 && a <= store.opaque_sources.len {
        for nominal in store.opaque_sources[a - 1].nominals { if nominal.identity.decl == b && nominal.is_opaque && nominal.storage.kind == blot_backend_opaque_storage::Kind.unknown { return 0, blot_error::Error.unresolved_type; } }
    }
    return internFields(store, tag, a, b, row, values);
}
fn internStateProvider(store: Store&, read: Id, write: Id, state: Id) -> Id, blot_error::Error { return internFields(store, Tag.state_provider, read, write, state, []); }
fn internRecord(store: Store&, values: const u32[:]) -> Id, blot_error::Error {
    if values.len % 2 != 0 { return 0, blot_error::Error.type_mismatch; }
    var ordered = true; var offset = 2;
    while offset < values.len { if !store.record_names.less(values[offset - 2], values[offset]) { ordered = false; break; } offset += 2; }
    if ordered { return intern(store, Tag.record, 0, 0, values); }
    var fields: u32[>..<] = []; fields.append(values); let count = values.len / 2;
    for index in 1..count {
        let field_name = fields[index * 2]; let field_type = fields[index * 2 + 1]; var next = index;
        while next > 0 && store.record_names.less(field_name, fields[(next - 1) * 2]) { fields[next * 2] = fields[(next - 1) * 2]; fields[next * 2 + 1] = fields[(next - 1) * 2 + 1]; next--; }
        fields[next * 2] = field_name; fields[next * 2 + 1] = field_type;
    }
    for index in 1..count { if fields[index * 2] == fields[(index - 1) * 2] { return 0, blot_error::Error.type_mismatch; } }
    return intern(store, Tag.record, 0, 0, fields);
}
recursive fn internFields(store: Store&, tag: Tag, a: u32, b: u32, row: u32, values: const u32[:]) -> Id, blot_error::Error { return internFieldsWithDictionaries(store, tag, a, b, row, values, [], false); }
recursive fn internFieldsWithDictionaries(store: Store&, tag: Tag, a: u32, b: u32, row: u32, values: const u32[:], slots: const Id[:], dictionary_abi: bool) -> Id, blot_error::Error {
    if tag == Tag.nominal && a == blot_check_task_types::handle.unit && b == blot_check_task_types::handle.decl { return intern(store, Tag.product, 0, 0, [blot_check_types::u32_type, blot_check_types::u32_type]); }
    if tag == Tag.nominal && blot_check_typed_staging::isIdentity(a, b) { return 0, blot_error::Error.unresolved_type; }
    if tag != Tag.state_provider && tag != Tag.scoped && tag != Tag.opened && tag != Tag.associated && ((row != unknown_row && row >= store.effects.rows.len) || (row != 0 && tag != Tag.function && tag != Tag.provider)) { return 0, blot_error::Error.type_mismatch; }
    if tag == Tag.owning && (a == 0 || a >= store.nodes.len || row != 0 || values.len != 0 || (b != blot_parse_ast::usagekind_unique && b != blot_parse_ast::usagekind_shared)) { return 0, blot_error::Error.type_mismatch; }
    if tag == Tag.scoped && (a == 0 || a >= store.nodes.len || node(store, a).tag != Tag.nominal || b == 0 || row == 0 || values.len != 0) { return 0, blot_error::Error.type_mismatch; }
    if tag == Tag.state_provider && (a == 0 || b == 0 || row == 0 || a >= store.nodes.len || b >= store.nodes.len || row >= store.nodes.len || values.len != 0) { return 0, blot_error::Error.type_mismatch; }
    var hash = blot_support_wyhash::init(0); blot_support_wyhash::value(hash, tagCode(tag)); blot_support_wyhash::value(hash, a); blot_support_wyhash::value(hash, b); blot_support_wyhash::value(hash, row);
    for value in values { blot_support_wyhash::value(hash, value); }
    if tag == Tag.universal { blot_support_wyhash::value(hash, dictionary_abi); if dictionary_abi { for slot in slots { blot_support_wyhash::value(hash, slot); } } }
    let fingerprint = blot_support_wyhash::final(hash); var candidate: u32 = 0; let bucket = store.buckets.get(fingerprint); if bucket { candidate = bucket; }
    while candidate != 0 {
        let n = node(store, candidate); var same = n.tag == tag;
        if same {
            if tag == Tag.product || tag == Tag.record { same = equal(children(store, candidate), values); }
            else if tag == Tag.nominal || tag == Tag.universal || tag == Tag.existential { same = n.a == a && n.b == b && equal(children(store, candidate), values); }
            else { same = n.a == a && n.b == b && n.c == row; }
        }
        if same && tag == Tag.universal { same = hasDictionaryABI(store, candidate) == dictionary_abi; if same && dictionary_abi { same = equal(slots, dictionarySlots(store, candidate)); } }
        if same { return candidate, blot_error::Error.none; } candidate = store.next[candidate];
    }
    if store.nodes.len == 4294967295 || values.len >= 4294967295 || store.extra.len > 4294967295 - values.len - 1 || store.extra.len + values.len + 1 > 4294967295 - slots.len { return 0, blot_error::Error.layout_limit; }
    var n = Node { tag: tag, a: a, b: b, c: row , ..};
    if tag == Tag.product || tag == Tag.record { n.a = store.extra.len as u32; n.b = values.len as u32; if tag == Tag.record { n.b /= 2; } store.extra.append(values); }
    else if tag == Tag.universal || tag == Tag.existential { n.c = store.extra.len as u32; store.extra.append(values); }
    else if tag == Tag.nominal { n.c = store.extra.len as u32; store.extra.push(values.len as u32); store.extra.append(values); }
    let id = store.nodes.len as u32;
    if dictionary_abi { store.universal_dictionaries.push(UniversalDictionaries { owner: id, start: store.extra.len as u32, len: slots.len as u32 , ..}); store.extra.append(slots); }
    var previous: u32 = 0; let old = store.buckets.get(fingerprint); if old { previous = old; }
    store.nodes.push(n); store.next.push(previous); store.buckets.insert(fingerprint, id); return id, blot_error::Error.none;
}
fn effectError(error: blot_error::Error) -> blot_error::Error { if error == blot_error::Error.out_of_memory { return error; } if error == blot_error::Error.type_mismatch { return error; } return blot_error::Error.layout_limit; }
fn mergePartial(store: Store&, left: Id, right: Id) -> Id, blot_error::Error { var budget: i64 = 1000000; return mergePartialDepth(store, left, right, 0, budget); }
recursive fn mergePartialDepth(store: Store&, left: Id, right: Id, depth: i64, budget: i64&) -> Id, blot_error::Error {
    if depth >= 1024 || budget == 0 { return 0, blot_error::Error.layout_limit; } budget--;
    if left == right || right == erased { return left, blot_error::Error.none; } if left == erased { return right, blot_error::Error.none; }
    let a = node(store, left); let b = node(store, right); if a.tag != b.tag { return 0, blot_error::Error.type_mismatch; }
    if a.tag == Tag.owning {
        if a.b != b.b { return 0, blot_error::Error.type_mismatch; } let payload, error = mergePartialDepth(store, a.a, b.a, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } return intern(store, Tag.owning, payload, a.b, []);
    }
    if a.tag == Tag.universal || a.tag == Tag.existential {
        if a.b != b.b || !equal(children(store, left), children(store, right)) || hasDictionaryABI(store, left) != hasDictionaryABI(store, right) || !equal(dictionarySlots(store, left), dictionarySlots(store, right)) { return 0, blot_error::Error.type_mismatch; }
        let body, error = mergePartialDepth(store, a.a, b.a, depth + 1, budget); if error != blot_error::Error.none { return 0, error; }
        var binders: Id[>..<] = []; binders.append(children(store, left));
        if hasDictionaryABI(store, left) { var slots: Id[>..<] = []; slots.append(dictionarySlots(store, left)); return internUniversalWithDictionaries(store, body, binders, slots); }
        return intern(store, a.tag, body, a.b, binders);
    }
    if a.tag == Tag.array || a.tag == Tag.list || a.tag == Tag.cursor || a.tag == Tag.resolver {
        let payload, error = mergePartialDepth(store, a.a, b.a, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } return intern(store, a.tag, payload, 0, []);
    }
    if a.tag == Tag.function || a.tag == Tag.provider {
        var row = a.c; if row == unknown_row { row = b.c; } if b.c != unknown_row && row != b.c { return 0, blot_error::Error.type_mismatch; }
        let input, input_error = mergePartialDepth(store, a.a, b.a, depth + 1, budget); if input_error != blot_error::Error.none { return 0, input_error; }
        var output: Id = 0;
        if a.tag == Tag.function { let merged, error = mergePartialDepth(store, a.b, b.b, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } output = merged; }
        return internWithEffects(store, a.tag, input, output, row, []);
    }
    if a.tag == Tag.state_provider {
        let read, read_error = mergePartialDepth(store, a.a, b.a, depth + 1, budget); if read_error != blot_error::Error.none { return 0, read_error; }
        let write, write_error = mergePartialDepth(store, a.b, b.b, depth + 1, budget); if write_error != blot_error::Error.none { return 0, write_error; }
        let state, state_error = mergePartialDepth(store, a.c, b.c, depth + 1, budget); if state_error != blot_error::Error.none { return 0, state_error; }
        return internStateProvider(store, read, write, state);
    }
    if a.tag == Tag.product || a.tag == Tag.record || a.tag == Tag.nominal {
        if a.tag == Tag.nominal && (a.a != b.a || a.b != b.b) { return 0, blot_error::Error.type_mismatch; }
        let count = children(store, left).len; if count != children(store, right).len { return 0, blot_error::Error.type_mismatch; }

        var values=blot_eval_type_evidence::WordBuffer{};
        recursive fn convertChildren()->Id,blot_error::Error {

        for index in 0..count {
            let first = children(store, left)[index]; let second = children(store, right)[index]; var value = first;
            if a.tag == Tag.record && index % 2 == 0 { if first != second { return 0, blot_error::Error.type_mismatch; } }
            else { let merged, error = mergePartialDepth(store, first, second, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } value = merged; }
            values.push(value);if values.failure!=blot_error::Error.none {return 0,values.failure;}
        }
        if a.tag == Tag.nominal { return intern(store, Tag.nominal, a.a, a.b, values.items); } return intern(store, a.tag, 0, 0, values.items);

        }
        let result,error=convertChildren();values.deinit();return result,error;
    }
    return 0, blot_error::Error.type_mismatch;
}
recursive fn closedType(module: const blot_check_core::Module&, kinds: u8[:], ty: blot_check_types::Id, depth: i64) -> bool {
    if kinds[ty] != 0 { return kinds[ty] == 1; } if depth >= 1024 { return false; }
    let n = module.types.node(ty); var closed = false;
    if n.tag == blot_check_types::Tag.unit || n.tag == blot_check_types::Tag.boolean || n.tag == blot_check_types::Tag.unsigned32 || n.tag == blot_check_types::Tag.floating32 || n.tag == blot_check_types::Tag.never || n.tag == blot_check_types::Tag.erased_proof || n.tag == blot_check_types::Tag.type_constructor { closed = true; }
    else if n.tag == blot_check_types::Tag.array || n.tag == blot_check_types::Tag.list || n.tag == blot_check_types::Tag.cursor || n.tag == blot_check_types::Tag.resolver || n.tag == blot_check_types::Tag.usage { closed = closedType(module, kinds, n.a, depth + 1); }
    else if n.tag == blot_check_types::Tag.function { closed = closedType(module, kinds, n.a, depth + 1) && closedType(module, kinds, n.b, depth + 1) && tailClosed(module.types.row(n.c).tail) && module.types.rowLabels(n.c).len == 0; }
    else if n.tag == blot_check_types::Tag.product || n.tag == blot_check_types::Tag.nominal {
        var fields = module.types.list(blot_check_types::List { start: n.a, len: n.b , ..}); if n.tag == blot_check_types::Tag.nominal { fields = module.types.nominalArguments(n); }
        closed = true; for child in fields { if !closedType(module, kinds, child, depth + 1) { closed = false; break; } }
    } else if n.tag == blot_check_types::Tag.record {
        closed = true; for index in 0..n.b { if !closedType(module, kinds, module.types.recordField(n, index).ty, depth + 1) { closed = false; break; } }
    }
    kinds[ty] = 2; if closed { kinds[ty] = 1; } return closed;
}
fn closedKey(closed: ClosedLayouts&, module: const blot_check_core::Module&, ty: blot_check_types::Id) -> blot_support::Option<u64> {
    if closed.units.len == 0 { return blot_support::none<u64>(); }
    var unit: i64 = -1; for &source, index in closed.units { if source .== module { unit = index; break; } }
    if unit < 0 || ty >= module.types.nodes.len { return blot_support::none<u64>(); }
    if closed.kinds.len == 0 { for index in 0..closed.units.len { closed.kinds.push(ClosedUnit {..}); } }
    if closed.kinds[unit].kinds.len != module.types.nodes.len {
        let range = blot_backend_runtime_ir::Range { start: closed.kind_bytes.len, len: module.types.nodes.len , ..};
        for index in 0..range.len { closed.kind_bytes.push(0); } closed.kinds[unit].kinds = range;
    }
    let kinds = closed.kinds[unit].kinds;
    if !closedType(module, closed.kind_bytes[kinds.start..kinds.start + kinds.len], ty, 0) { return blot_support::none<u64>(); }
    return blot_support::some((unit as u64 << 32) | ty);
}
fn checkSubstitutions(closed: ClosedLayouts&, module: const blot_check_core::Module&, mappings: const Mapping[:]) {
    var unit: i64 = -1; for &source, index in closed.units { if source .== module { unit = index; break; } } assert(unit >= 0);
    let kinds = closed.kinds[unit].kinds;
    for mapping in mappings { if mapping.variable >= module.types.nodes.len { continue; } assert(!closedType(module, closed.kind_bytes[kinds.start..kinds.start + kinds.len], mapping.variable, 0)); }
}
fn fromType(store: Store&, module: const blot_check_core::Module&, ty: blot_check_types::Id, mappings: const Mapping[:]) -> Id, blot_error::Error { return fromTypeDepth(store, module, ty, mappings, [], 0, false); }
fn fromTypePartial(store: Store&, module: const blot_check_core::Module&, ty: blot_check_types::Id, mappings: const Mapping[:]) -> Id, blot_error::Error { return fromTypeDepth(store, module, ty, mappings, [], 0, true); }
fn fromTypeWithRows(store: Store&, module: const blot_check_core::Module&, ty: blot_check_types::Id, mappings: const Mapping[:], rows: const RowMapping[:], partial: bool) -> Id, blot_error::Error { return fromTypeDepth(store, module, ty, mappings, rows, 0, partial); }
recursive fn fromTypeDepth(store: Store&, module: const blot_check_core::Module&, ty: blot_check_types::Id, mappings: const Mapping[:], rows: const RowMapping[:], depth: i64, allow_erased: bool) -> Id, blot_error::Error {
    if depth >= 1024 { return 0, blot_error::Error.layout_limit; }
    for mapping in mappings { if mapping.variable == ty { return mapping.layout, blot_error::Error.none; } }
    let key = closedKey(store.closed, module, ty); if !key.present { return fromTypeNode(store, module, ty, mappings, rows, depth, allow_erased); }
    checkSubstitutions(store.closed, module, mappings);
    block { let known = store.closed.layouts.get(key.value); if known { return copy(known), blot_error::Error.none; } }
    let result, error = fromTypeNode(store, module, ty, mappings, rows, depth, allow_erased); if error != blot_error::Error.none { return 0, error; }
    store.closed.layouts.insert(key.value, result); return result, blot_error::Error.none;
}
fn tailClosed<T>(tail: T) -> bool { match tail { closed => true, _ => false } }
fn tailInfo<T>(tail: T) -> u8, u32 {
    match tail { closed => { return 0, 0; }, variable v => { return 1, v.value; }, parameter v => { return 2, v.value; }, formal v => { return 3, v.value; } }
}
recursive fn fromTypeToken(store: Store&, module: const blot_check_core::Module&, ty: blot_check_types::Id, mappings: const Mapping[:], rows: const RowMapping[:], depth: i64, allow_erased: bool) -> Id, blot_error::Error {
    let n = module.types.node(ty); if n.tag != blot_check_types::Tag.scoped { return fromTypeDepth(store, module, ty, mappings, rows, depth, allow_erased); }
    let instance = blot_check_types::selectionAtom(module.types, mappedInstance(blot_check_types::NominalIdentity { unit: n.b, decl: n.c , ..}, mappings));
    if instance.unit == 0 || instance.decl == 0 { return 0, blot_error::Error.unresolved_type; }
    let payload, error = fromTypeDepth(store, module, n.a, mappings, rows, depth + 1, allow_erased); if error != blot_error::Error.none { return 0, error; }
    return internWithEffects(store, Tag.scoped, payload, instance.unit, instance.decl, []);
}
recursive fn fromTypeNode(store: Store&, module: const blot_check_core::Module&, ty: blot_check_types::Id, mappings: const Mapping[:], rows: const RowMapping[:], depth: i64, allow_erased: bool) -> Id, blot_error::Error {
    let n = module.types.node(ty);
    if n.tag == blot_check_types::Tag.unit || n.tag == blot_check_types::Tag.boolean || n.tag == blot_check_types::Tag.unsigned32 || n.tag == blot_check_types::Tag.floating32 || n.tag == blot_check_types::Tag.never { return ty, blot_error::Error.none; }
    if n.tag == blot_check_types::Tag.variable { if allow_erased { return erased, blot_error::Error.none; } return 0, blot_error::Error.unresolved_type; }
    if n.tag == blot_check_types::Tag.usage {
        let payload, error = fromTypeDepth(store, module, n.a, mappings, rows, depth + 1, allow_erased); if error != blot_error::Error.none { return 0, error; }
        if n.b == blot_parse_ast::usagekind_unique || n.b == blot_parse_ast::usagekind_shared { return intern(store, Tag.owning, payload, n.b, []); } return payload, blot_error::Error.none;
    }
    if n.tag == blot_check_types::Tag.forall || n.tag == blot_check_types::Tag.existential {
        if n.c == 0 || n.c > 128 || depth >= 128 || store.type_owners.len >= 128 { return 0, blot_error::Error.layout_limit; }
        store.type_owners.push(ty); let result, error = fromTypeQuantified(store, module, n, mappings, rows, depth, allow_erased); store.type_owners.pop(); return result, error;
    }
    if n.tag == blot_check_types::Tag.projection {
        let argument_count = module.types.nominalArguments(n).len; var scope = store.type_owners.len;
        while scope != 0 {
            scope--; let owner = store.type_owners[scope];
            let goal_count=module.types.quantifierGoals(owner).len;for ordinal in 0..goal_count {let goal=module.types.quantifierGoals(owner)[ordinal];
                if goal.kind != blot_check_types::ObligationKind.contract || goal.identity.unit != n.a || goal.identity.decl != n.b { continue; }
                let tuple = module.types.node(goal.ty); if tuple.tag != blot_check_types::Tag.product || tuple.b != argument_count { continue; }
                var matches = true; let expected = module.types.list(blot_check_types::List { start: tuple.a, len: tuple.b , ..});
                for value, index in expected { let same, error = blot_check_rank_equal::equal(module.types, value, module.types.nominalArguments(n)[index], true); if error != blot_error::Error.none { return 0, blot_error::Error.layout_limit; } if !same { matches = false; } }
                if !matches { continue; }
                let member_name = module.types.projectionMember(n);
                for contract_index in 0..module.contracts.len {let contract=module.contracts[contract_index];
                    if contract.identity.unit != n.a || contract.identity.decl != n.b { continue; }
                    if contract.members.start > module.contract_members.len || contract.members.len > module.contract_members.len - contract.members.start { return 0, blot_error::Error.unresolved_type; }
                    for member_index in 0..contract.members.len {let member=module.contract_members[contract.members.start+member_index];
                        if member.name == member_name && member.kind != blot_reuse_principal_interface::ContractMemberKind.value { return internAssociated(store, ordinal as u32, member_name, (store.type_owners.len - 1 - scope) as u32); }
                    }
                }
                return 0, blot_error::Error.unresolved_type;
            }
        }
        return 0, blot_error::Error.unresolved_type;
    }
    if n.tag == blot_check_types::Tag.erased_proof { return intern(store, Tag.erased_proof, 0, 0, []); }
    if n.tag == blot_check_types::Tag.scoped { return intern(store, Tag.nominal, 4294967295, capability_layout_decl, []); }
    if n.tag == blot_check_types::Tag.type_constructor { return intern(store, Tag.type_constructor, n.a, n.b, []); }
    if n.tag == blot_check_types::Tag.array || n.tag == blot_check_types::Tag.list || n.tag == blot_check_types::Tag.cursor || n.tag == blot_check_types::Tag.resolver {
        let payload, error = fromTypeDepth(store, module, n.a, mappings, rows, depth + 1, allow_erased); if error != blot_error::Error.none { return 0, error; }
        var tag = Tag.resolver; if n.tag == blot_check_types::Tag.array { tag = Tag.array; } else if n.tag == blot_check_types::Tag.list { tag = Tag.list; } else if n.tag == blot_check_types::Tag.cursor { tag = Tag.cursor; }
        return intern(store, tag, payload, 0, []);
    }
    if n.tag == blot_check_types::Tag.function || n.tag == blot_check_types::Tag.provider {
        var input: Id = 0;
        if n.tag == blot_check_types::Tag.provider { let selected, error = fromTypeToken(store, module, n.a, mappings, rows, depth + 1, allow_erased); if error != blot_error::Error.none { return 0, error; } input = selected; }
        else { let selected, error = fromTypeDepth(store, module, n.a, mappings, rows, depth + 1, allow_erased); if error != blot_error::Error.none { return 0, error; } input = selected; }
        var output: Id = 0; var tag = Tag.provider;
        if n.tag == blot_check_types::Tag.function { let selected, error = fromTypeDepth(store, module, n.b, mappings, rows, depth + 1, allow_erased); if error != blot_error::Error.none { return 0, error; } output = selected; tag = Tag.function; }
        let row, error = fromTypeRow(store, module, n.c, mappings, rows, depth + 1, allow_erased); if error != blot_error::Error.none { return 0, error; }
        return internWithEffects(store, tag, input, output, row, []);
    }
    if n.tag == blot_check_types::Tag.state_provider {
        let read, read_error = fromTypeToken(store, module, n.a, mappings, rows, depth + 1, allow_erased); if read_error != blot_error::Error.none { return 0, read_error; }
        let write, write_error = fromTypeToken(store, module, n.b, mappings, rows, depth + 1, allow_erased); if write_error != blot_error::Error.none { return 0, write_error; }
        let state, state_error = fromTypeDepth(store, module, n.c, mappings, rows, depth + 1, allow_erased); if state_error != blot_error::Error.none { return 0, state_error; }
        return internStateProvider(store, read, write, state);
    }
    if n.tag == blot_check_types::Tag.product || n.tag == blot_check_types::Tag.record || n.tag == blot_check_types::Tag.nominal {
        if n.tag == blot_check_types::Tag.nominal && n.a == blot_check_task_types::handle.unit && n.b == blot_check_task_types::handle.decl { return intern(store, Tag.product, 0, 0, [blot_check_types::u32_type, blot_check_types::u32_type]); }

        var values=blot_eval_type_evidence::WordBuffer{};
        recursive fn convertChildren()->Id,blot_error::Error {

        if n.tag == blot_check_types::Tag.record {
            for index in 0..n.b { let field = module.types.recordField(n, index); values.push(field.name);if values.failure!=blot_error::Error.none {return 0,values.failure;} let child, error = fromTypeDepth(store, module, field.ty, mappings, rows, depth + 1, allow_erased); if error != blot_error::Error.none { return 0, error; } values.push(child);if values.failure!=blot_error::Error.none {return 0,values.failure;} }
            return internRecord(store, values.items);
        }
        var children = module.types.list(blot_check_types::List { start: n.a, len: n.b , ..}); if n.tag == blot_check_types::Tag.nominal { children = module.types.nominalArguments(n); }
        for child in children { let value, error = fromTypeDepth(store, module, child, mappings, rows, depth + 1, allow_erased); if error != blot_error::Error.none { return 0, error; } values.push(value);if values.failure!=blot_error::Error.none {return 0,values.failure;} }
        if n.tag == blot_check_types::Tag.nominal { return intern(store, Tag.nominal, n.a, n.b, values.items); } return intern(store, Tag.product, 0, 0, values.items);

        }
        let result,error=convertChildren();values.deinit();return result,error;
    }
    return 0, blot_error::Error.unresolved_type;
}
recursive fn fromTypeQuantified(store: Store&, module: const blot_check_core::Module&, n: blot_check_types::Node, mappings: const Mapping[:], rows: const RowMapping[:], depth: i64, allow_erased: bool) -> Id, blot_error::Error {

        var owned=MappingBuffer{};
        recursive fn convertChildren()->Id,blot_error::Error {

    for ordinal in 0..n.c { let binder=module.types.list(blot_check_types::List { start: n.b, len: n.c })[ordinal];
        let leaf = module.types.node(binder); if leaf.tag != blot_check_types::Tag.bound || leaf.a != ordinal || leaf.b > 2 || leaf.c != 0 { return 0, blot_error::Error.unresolved_type; }
        let layout, error = internWithEffects(store, Tag.opened, ordinal as u32, 0, leaf.b, []); if error != blot_error::Error.none { return 0, error; }
        owned.push(Mapping { variable: binder, layout: layout , ..});if owned.failure!=blot_error::Error.none {return 0,owned.failure;}
    }
    for index in 0..mappings.len { let mapping=mappings[index];
        var outer = mapping; let representation = node(store, mapping.layout);
        if representation.tag == Tag.opened { if representation.b >= 127 { return 0, blot_error::Error.layout_limit; } let layout, error = internWithEffects(store, Tag.opened, representation.a, representation.b + 1, representation.c, []); if error != blot_error::Error.none { return 0, error; } outer.layout = layout; }
        owned.push(outer);if owned.failure!=blot_error::Error.none {return 0,owned.failure;}
    }
    var tag = Tag.existential; if n.tag == blot_check_types::Tag.forall { tag = Tag.universal; }
    var binders: Id[128] = [0; 128]; for index in 0..n.c { binders[index] = owned.items[index].layout; }
    let body, error = fromTypeDepth(store, module, n.a, owned.items, rows, depth + 1, allow_erased); if error != blot_error::Error.none { return 0, error; }
    return intern(store, tag, body, n.c, binders[..n.c]);

        }
        let result,error=convertChildren();owned.deinit();return result,error;
    }
fn rowFromType(store: Store&, module: const blot_check_core::Module&, row: u32, mappings: const Mapping[:], rows: const RowMapping[:], partial: bool) -> u32, blot_error::Error { return fromTypeRow(store, module, row, mappings, rows, 0, partial); }
recursive fn fromTypeRow(store: Store&, module: const blot_check_core::Module&, row: u32, mappings: const Mapping[:], rows: const RowMapping[:], depth: i64, allow_erased: bool) -> u32, blot_error::Error {
    if depth >= 1024 { return 0, blot_error::Error.layout_limit; }
    let kind, tail = tailInfo(module.types.row(row).tail); var suffix: u32 = 0; var formal: Id = 0;
    if kind == 2 { if allow_erased { return unknown_row, blot_error::Error.none; } return 0, blot_error::Error.unresolved_type; }
    if kind == 1 || kind == 3 {
        var key = tail;
        if kind == 3 { let converted, error = blot_check_types::formalRowKey(tail); if error != blot_error::Error.none { return 0, blot_error::Error.unresolved_type; } key = converted; }
        var replaced = false;
        for mapping in rows {
            if mapping.variable != key { continue; }
            if mapping.row == unknown_row { if allow_erased { return unknown_row, blot_error::Error.none; } return 0, blot_error::Error.unresolved_type; }
            if mapping.row >= store.effects.rows.len { return 0, blot_error::Error.type_mismatch; } suffix = mapping.row; replaced = true; break;
        }
        if !replaced {
            if kind == 1 { if allow_erased { return unknown_row, blot_error::Error.none; } return 0, blot_error::Error.unresolved_type; }
            let selected, error = fromTypeDepth(store, module, tail, mappings, rows, depth + 1, allow_erased); if error != blot_error::Error.none { return 0, error; } formal = selected;
            let leaf = node(store, formal); if leaf.tag != Tag.opened || leaf.c != 1 { return 0, blot_error::Error.type_mismatch; }
        }
    }

        var labels=blot_eval_type_evidence::WordBuffer{}; var arguments=blot_eval_type_evidence::WordBuffer{};
        recursive fn convertChildren()->Id,blot_error::Error {

    let label_count=module.types.rowLabels(row).len;for label_index in 0..label_count {let label=module.types.rowLabels(row)[label_index];
        arguments.clear();
        let argument_count=module.types.operationArguments(label).len;for argument_index in 0..argument_count {let argument=module.types.operationArguments(label)[argument_index]; let selected, error = fromTypeDepth(store, module, argument, mappings, rows, depth + 1, allow_erased); if error != blot_error::Error.none { return 0, error; } arguments.push(selected);if arguments.failure!=blot_error::Error.none {return 0,arguments.failure;} }
        let operation = module.types.operation(label); let instance = blot_check_types::selectionAtom(module.types, mappedInstance(operation.instance, mappings));
        let mapped, error = store.effects.internOperationInstance(operation.identity, arguments.items, instance); if error != blot_error::Error.none { return 0, effectError(error); } labels.push(mapped);if labels.failure!=blot_error::Error.none {return 0,labels.failure;}
    }
    labels.append(store.effects.view().rowLabels(suffix));if labels.failure!=blot_error::Error.none {return 0,labels.failure;} if suffix != 0 { formal = store.effects.rows.items[suffix].formal; }
    let result, error = store.effects.internRowWithFormal(labels.items, formal); if error != blot_error::Error.none { return 0, effectError(error); } return result, blot_error::Error.none;

        }
        let result,error=convertChildren();arguments.deinit();labels.deinit();return result,error;
    }
fn fromEvidence(store: Store&, view: blot_eval_type_evidence::View, id: u32) -> Id, blot_error::Error { var budget: i64 = 1000000; return fromEvidenceDepth(store, view, id, 0, budget); }
fn toEvidence(store: Store&, target: blot_eval_type_evidence::Store&, id: Id) -> u32, blot_error::Error { var budget: i64 = 1000000; return toEvidenceDepth(store, target, id, 0, budget, 0); }
recursive fn toEvidenceDepth(store: Store&, target: blot_eval_type_evidence::Store&, id: Id, depth: i64, budget: i64&, bound_arity: u32) -> u32, blot_error::Error {
    if depth >= 1024 || budget == 0 { return 0, blot_error::Error.evidence_limit; } budget--;
    if id == 0 || id >= store.nodes.len { return 0, blot_error::Error.unresolved_type; }
    let n = node(store, id);
    if n.tag == Tag.nominal && n.a == 4294967295 && n.b == capability_layout_decl { return 0, blot_error::Error.unresolved_type; }
    if n.tag == Tag.invalid || n.tag == Tag.erased || n.tag == Tag.associated { return 0, blot_error::Error.unresolved_type; }
    if n.tag == Tag.opened {
        if (n.b == 0 && n.a >= bound_arity) || n.b >= 128 { return 0, blot_error::Error.unresolved_type; }
        return target.internWithEffects(blot_eval_type_evidence::Tag.bound, n.a, n.c, n.b, []);
    }
    if n.tag == Tag.universal || n.tag == Tag.existential {
        if hasDictionaryABI(store, id) { return 0, blot_error::Error.unresolved_type; }
        var binders: u32[128] = [0; 128];
        for index in 0..n.b { let formal = children(store, id)[index]; let value, error = toEvidenceDepth(store, target, formal, depth + 1, budget, n.b); if error != blot_error::Error.none { return 0, error; } binders[index] = value; }
        var tag = blot_eval_type_evidence::Tag.existential; if n.tag == Tag.universal { tag = blot_eval_type_evidence::Tag.forall; }
        let body, error = toEvidenceDepth(store, target, n.a, depth + 1, budget, n.b); if error != blot_error::Error.none { return 0, error; } return target.intern(tag, body, n.b, binders[..n.b]);
    }
    if n.tag == Tag.erased_proof { return target.intern(blot_eval_type_evidence::Tag.erased_proof, 0, 0, []); }
    if n.tag == Tag.unit || n.tag == Tag.boolean || n.tag == Tag.unsigned32 || n.tag == Tag.floating32 || n.tag == Tag.never { return id, blot_error::Error.none; }
    if n.tag == Tag.type_constructor { return target.intern(blot_eval_type_evidence::Tag.type_constructor, n.a, n.b, []); }
    if n.tag == Tag.owning || n.tag == Tag.array || n.tag == Tag.list || n.tag == Tag.cursor || n.tag == Tag.resolver || n.tag == Tag.scoped {
        let payload, error = toEvidenceDepth(store, target, n.a, depth + 1, budget, bound_arity); if error != blot_error::Error.none { return 0, error; }
        if n.tag == Tag.owning { return target.intern(blot_eval_type_evidence::Tag.usage, payload, n.b, []); }
        if n.tag == Tag.scoped { return target.internWithEffects(blot_eval_type_evidence::Tag.scoped, payload, n.b, n.c, []); }
        var tag = blot_eval_type_evidence::Tag.resolver;
        if n.tag == Tag.array { tag = blot_eval_type_evidence::Tag.array; } else if n.tag == Tag.list { tag = blot_eval_type_evidence::Tag.list; } else if n.tag == Tag.cursor { tag = blot_eval_type_evidence::Tag.cursor; }
        return target.intern(tag, payload, 0, []);
    }
    if n.tag == Tag.provider || n.tag == Tag.function {
        let input, input_error = toEvidenceDepth(store, target, n.a, depth + 1, budget, bound_arity); if input_error != blot_error::Error.none { return 0, input_error; }
        var output: u32 = 0; var tag = blot_eval_type_evidence::Tag.provider;
        if n.tag == Tag.function { let selected, error = toEvidenceDepth(store, target, n.b, depth + 1, budget, bound_arity); if error != blot_error::Error.none { return 0, error; } output = selected; tag = blot_eval_type_evidence::Tag.function; }
        let row, error = toEvidenceRow(store, target, n.c, depth + 1, budget, bound_arity); if error != blot_error::Error.none { return 0, error; }
        return target.internWithEffects(tag, input, output, row, []);
    }
    if n.tag == Tag.state_provider {
        let read, read_error = toEvidenceDepth(store, target, n.a, depth + 1, budget, bound_arity); if read_error != blot_error::Error.none { return 0, read_error; }
        let write, write_error = toEvidenceDepth(store, target, n.b, depth + 1, budget, bound_arity); if write_error != blot_error::Error.none { return 0, write_error; }
        let state, state_error = toEvidenceDepth(store, target, n.c, depth + 1, budget, bound_arity); if state_error != blot_error::Error.none { return 0, state_error; }
        return target.internStateProvider(read, write, state);
    }
    if n.tag == Tag.product || n.tag == Tag.record || n.tag == Tag.nominal {

        var values=blot_eval_type_evidence::WordBuffer{};
        recursive fn convertChildren()->Id,blot_error::Error {
 let count = children(store, id).len;
        for index in 0..count { let child = children(store, id)[index]; if n.tag == Tag.record && index % 2 == 0 { values.push(child);if values.failure!=blot_error::Error.none {return 0,values.failure;} } else { let value, error = toEvidenceDepth(store, target, child, depth + 1, budget, bound_arity); if error != blot_error::Error.none { return 0, error; } values.push(value);if values.failure!=blot_error::Error.none {return 0,values.failure;} } }
        if n.tag == Tag.nominal { return target.intern(blot_eval_type_evidence::Tag.nominal, n.a, n.b, values.items); }
        if n.tag == Tag.record { return target.intern(blot_eval_type_evidence::Tag.record, 0, 0, values.items); }
        return target.intern(blot_eval_type_evidence::Tag.product, 0, 0, values.items);

        }
        let result,error=convertChildren();values.deinit();return result,error;
    }
    return 0, blot_error::Error.unresolved_type;
}
recursive fn fromEvidenceDepth(store: Store&, view: blot_eval_type_evidence::View, id: u32, depth: i64, budget: i64&) -> Id, blot_error::Error {
    if depth >= 1024 || budget == 0 { return 0, blot_error::Error.layout_limit; } budget--;
    if id == 0 || id >= view.nodes.len { return 0, blot_error::Error.unresolved_type; } let n = view.node(id);
    if n.tag == blot_eval_type_evidence::Tag.projection { let descriptor = view.projection(id); return internAssociated(store, descriptor.goal, descriptor.member, descriptor.scope); }
    if n.tag == blot_eval_type_evidence::Tag.forall || n.tag == blot_eval_type_evidence::Tag.existential {
        var binders: Id[128] = [0; 128]; if n.b == 0 || n.b > 128 { return 0, blot_error::Error.type_mismatch; }
        for index in 0..n.b { let formal = view.children(id)[index]; let selected, error = fromEvidenceDepth(store, view, formal, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } binders[index] = selected; }
        var tag = Tag.existential; if n.tag == blot_eval_type_evidence::Tag.forall { tag = Tag.universal; }
        let body, error = fromEvidenceDepth(store, view, n.a, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } return intern(store, tag, body, n.b, binders[..n.b]);
    }
    if n.tag == blot_eval_type_evidence::Tag.bound { return internWithEffects(store, Tag.opened, n.a, n.c, n.b, []); }
    if n.tag == blot_eval_type_evidence::Tag.usage {
        let payload, error = fromEvidenceDepth(store, view, n.a, depth + 1, budget); if error != blot_error::Error.none { return 0, error; }
        if n.b == blot_parse_ast::usagekind_unique || n.b == blot_parse_ast::usagekind_shared { return intern(store, Tag.owning, payload, n.b, []); } return payload, blot_error::Error.none;
    }
    if n.tag == blot_eval_type_evidence::Tag.erased_proof { return intern(store, Tag.erased_proof, 0, 0, []); }
    if n.tag == blot_eval_type_evidence::Tag.absent { return 0, blot_error::Error.unresolved_type; }
    if n.tag == blot_eval_type_evidence::Tag.unit || n.tag == blot_eval_type_evidence::Tag.boolean || n.tag == blot_eval_type_evidence::Tag.unsigned32 || n.tag == blot_eval_type_evidence::Tag.floating32 || n.tag == blot_eval_type_evidence::Tag.never { return id, blot_error::Error.none; }
    if n.tag == blot_eval_type_evidence::Tag.type_constructor { return intern(store, Tag.type_constructor, n.a, n.b, []); }
    if n.tag == blot_eval_type_evidence::Tag.scoped { return intern(store, Tag.nominal, 4294967295, capability_layout_decl, []); }
    if n.tag == blot_eval_type_evidence::Tag.array || n.tag == blot_eval_type_evidence::Tag.list || n.tag == blot_eval_type_evidence::Tag.cursor || n.tag == blot_eval_type_evidence::Tag.resolver {
        let payload, error = fromEvidenceDepth(store, view, n.a, depth + 1, budget); if error != blot_error::Error.none { return 0, error; }
        var tag = Tag.resolver; if n.tag == blot_eval_type_evidence::Tag.array { tag = Tag.array; } else if n.tag == blot_eval_type_evidence::Tag.list { tag = Tag.list; } else if n.tag == blot_eval_type_evidence::Tag.cursor { tag = Tag.cursor; }
        return intern(store, tag, payload, 0, []);
    }
    if n.tag == blot_eval_type_evidence::Tag.provider || n.tag == blot_eval_type_evidence::Tag.function {
        var input: Id = 0;
        if n.tag == blot_eval_type_evidence::Tag.provider { let selected, error = fromEvidenceToken(store, view, n.a, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } input = selected; }
        else { let selected, error = fromEvidenceDepth(store, view, n.a, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } input = selected; }
        var output: Id = 0; var tag = Tag.provider;
        if n.tag == blot_eval_type_evidence::Tag.function { let selected, error = fromEvidenceDepth(store, view, n.b, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } output = selected; tag = Tag.function; }
        let row, error = fromEvidenceRow(store, view, n.c, depth + 1, budget); if error != blot_error::Error.none { return 0, error; }
        return internWithEffects(store, tag, input, output, row, []);
    }
    if n.tag == blot_eval_type_evidence::Tag.state_provider {
        let read, read_error = fromEvidenceToken(store, view, n.a, depth + 1, budget); if read_error != blot_error::Error.none { return 0, read_error; }
        let write, write_error = fromEvidenceToken(store, view, n.b, depth + 1, budget); if write_error != blot_error::Error.none { return 0, write_error; }
        let state, state_error = fromEvidenceDepth(store, view, n.c, depth + 1, budget); if state_error != blot_error::Error.none { return 0, state_error; }
        return internStateProvider(store, read, write, state);
    }
    if n.tag == blot_eval_type_evidence::Tag.product || n.tag == blot_eval_type_evidence::Tag.record || n.tag == blot_eval_type_evidence::Tag.nominal {
        if n.tag == blot_eval_type_evidence::Tag.nominal && n.a == blot_check_task_types::handle.unit && n.b == blot_check_task_types::handle.decl { return intern(store, Tag.product, 0, 0, [blot_check_types::u32_type, blot_check_types::u32_type]); }

        var values=blot_eval_type_evidence::WordBuffer{};
        recursive fn convertChildren()->Id,blot_error::Error {

        let count=view.children(id).len;for index in 0..count { let child=view.children(id)[index];if n.tag == blot_eval_type_evidence::Tag.record && index % 2 == 0 { values.push(child);if values.failure!=blot_error::Error.none {return 0,values.failure;} } else { let selected, error = fromEvidenceDepth(store, view, child, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } values.push(selected);if values.failure!=blot_error::Error.none {return 0,values.failure;} } }
        if n.tag == blot_eval_type_evidence::Tag.record { return internRecord(store, values.items); }
        if n.tag == blot_eval_type_evidence::Tag.nominal { return intern(store, Tag.nominal, n.a, n.b, values.items); } return intern(store, Tag.product, 0, 0, values.items);

        }
        let result,error=convertChildren();values.deinit();return result,error;
    }
    return 0, blot_error::Error.unresolved_type;
}
recursive fn fromEvidenceToken(store: Store&, view: blot_eval_type_evidence::View, ty: u32, depth: i64, budget: i64&) -> Id, blot_error::Error {
    let n = view.node(ty); if n.tag != blot_eval_type_evidence::Tag.scoped { return fromEvidenceDepth(store, view, ty, depth, budget); }
    let payload, error = fromEvidenceDepth(store, view, n.a, depth + 1, budget); if error != blot_error::Error.none { return 0, error; }
    return internWithEffects(store, Tag.scoped, payload, n.b, n.c, []);
}
fn rowToEvidence(store: Store&, target: blot_eval_type_evidence::Store&, row: u32) -> u32, blot_error::Error { var budget: i64 = 1000000; return toEvidenceRow(store, target, row, 0, budget, 0); }
fn rowFromEvidence(store: Store&, view: blot_eval_type_evidence::View, row: u32) -> u32, blot_error::Error { var budget: i64 = 1000000; return fromEvidenceRow(store, view, row, 0, budget); }
recursive fn toEvidenceRow(store: Store&, target: blot_eval_type_evidence::Store&, row: u32, depth: i64, budget: i64&, bound_arity: u32) -> u32, blot_error::Error {
    if depth >= 1024 || budget == 0 { return 0, blot_error::Error.evidence_limit; } if row == unknown_row { return 0, blot_error::Error.unresolved_type; } budget--;
        var labels=blot_eval_type_evidence::WordBuffer{};
    var arguments=blot_eval_type_evidence::WordBuffer{};
    recursive fn convertRow()->u32,blot_error::Error {

    let source = store.effects.view();
    let label_count=source.rowLabels(row).len;for label_index in 0..label_count {let label=source.rowLabels(row)[label_index];
        arguments.clear();
        let argument_count=source.operationArguments(label).len;for argument_index in 0..argument_count {let argument=source.operationArguments(label)[argument_index]; let selected, error = toEvidenceDepth(store, target, argument, depth + 1, budget, bound_arity); if error != blot_error::Error.none { return 0, error; } arguments.push(selected);if arguments.failure!=blot_error::Error.none {return 0,arguments.failure;} }
        let operation = source.operation(label); let mapped, error = target.effects.internOperationInstance(operation.identity, arguments.items, operation.instance); if error != blot_error::Error.none { return 0, error; } labels.push(mapped);if labels.failure!=blot_error::Error.none {return 0,labels.failure;}
    }
    let old_formal = store.effects.rows.items[row].formal; var formal: u32 = 0;
    if old_formal != 0 { let selected, error = toEvidenceDepth(store, target, old_formal, depth + 1, budget, bound_arity); if error != blot_error::Error.none { return 0, error; } formal = selected; }
    return target.effects.internRowWithFormal(labels.items, formal);

    }
    let result,error=convertRow();arguments.deinit();labels.deinit();return result,error;
}
recursive fn fromEvidenceRow(store: Store&, view: blot_eval_type_evidence::View, row: u32, depth: i64, budget: i64&) -> u32, blot_error::Error {
    if row >= view.effects.rows.len { return 0, blot_error::Error.unresolved_type; } if depth >= 1024 || budget == 0 { return 0, blot_error::Error.layout_limit; } budget--;
        var labels=blot_eval_type_evidence::WordBuffer{};
    var arguments=blot_eval_type_evidence::WordBuffer{};
    recursive fn convertRow()->u32,blot_error::Error {

    let label_count=view.effects.rowLabels(row).len;for label_index in 0..label_count {let label=view.effects.rowLabels(row)[label_index];
        arguments.clear();
        let argument_count=view.effects.operationArguments(label).len;for argument_index in 0..argument_count {let argument=view.effects.operationArguments(label)[argument_index]; let selected, error = fromEvidenceDepth(store, view, argument, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } arguments.push(selected);if arguments.failure!=blot_error::Error.none {return 0,arguments.failure;} }
        let operation = view.effects.operation(label); let mapped, error = store.effects.internOperationInstance(operation.identity, arguments.items, operation.instance); if error != blot_error::Error.none { return 0, effectError(error); } labels.push(mapped);if labels.failure!=blot_error::Error.none {return 0,labels.failure;}
    }
    let old_formal = view.effects.rows[row].formal; var formal: Id = 0;
    if old_formal != 0 { let selected, error = fromEvidenceDepth(store, view, old_formal, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } formal = selected; }
    let result, error = store.effects.internRowWithFormal(labels.items, formal); if error != blot_error::Error.none { return 0, effectError(error); } return result, blot_error::Error.none;

    }
    let result,error=convertRow();arguments.deinit();labels.deinit();return result,error;
}
fn toCodeExpectation(store: Store&, target: blot_reuse_code_expectation::Store&, id: Id) -> u32, blot_error::Error { var budget: i64 = 1000000; return toExpectationDepth(store, target, id, 0, budget); }
fn expectationError(error: blot_error::Error) -> blot_error::Error { if error == blot_error::Error.out_of_memory { return error; } return blot_error::Error.layout_limit; }
fn internExpectation(store: Store&, target: blot_reuse_code_expectation::Store&, tag: blot_reuse_code_expectation::Tag, a: u32, b: u32, values: const u32[:]) -> u32, blot_error::Error {
    let result, error = target.intern(tag, a, b, values); if error != blot_error::Error.none { return 0, expectationError(error); } return result, blot_error::Error.none;
}
recursive fn toExpectationDepth(store: Store&, target: blot_reuse_code_expectation::Store&, id: Id, depth: i64, budget: i64&) -> u32, blot_error::Error {
    if depth >= 1024 || budget == 0 { return 0, blot_error::Error.layout_limit; } budget--;
    if id == 0 || id >= store.nodes.len { return 0, blot_error::Error.unresolved_type; }
    let n = node(store, id);
    if (n.tag == Tag.nominal && n.a == 4294967295 && n.b == capability_layout_decl) || n.tag == Tag.associated || n.tag == Tag.scoped || n.tag == Tag.erased { return 0, blot_error::Error.none; }
    if n.tag == Tag.invalid { return 0, blot_error::Error.unresolved_type; }
    if n.tag == Tag.universal || n.tag == Tag.existential {
        if hasDictionaryABI(store, id) { return 0, blot_error::Error.unresolved_type; }
        var binders: u32[128] = [0; 128];
        for index in 0..n.b { let formal = children(store, id)[index]; let selected, error = toExpectationDepth(store, target, formal, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } binders[index] = selected; }
        var tag = blot_eval_type_evidence::Tag.existential; if n.tag == Tag.universal { tag = blot_eval_type_evidence::Tag.forall; }
        let body, error = toExpectationDepth(store, target, n.a, depth + 1, budget); if error != blot_error::Error.none { return 0, error; }
        return internExpectation(store, target, tag, body, n.b, binders[..n.b]);
    }
    if n.tag == Tag.opened { let result, error = target.internBound(n.a, n.c, n.b); if error != blot_error::Error.none { return 0, expectationError(error); } return result, blot_error::Error.none; }
    if n.tag == Tag.erased_proof { return internExpectation(store, target, blot_eval_type_evidence::Tag.erased_proof, 0, 0, []); }
    if n.tag == Tag.unit || n.tag == Tag.boolean || n.tag == Tag.unsigned32 || n.tag == Tag.floating32 || n.tag == Tag.never { return id, blot_error::Error.none; }
    if n.tag == Tag.type_constructor { return internExpectation(store, target, blot_eval_type_evidence::Tag.type_constructor, n.a, n.b, []); }
    if n.tag == Tag.owning || n.tag == Tag.array || n.tag == Tag.list || n.tag == Tag.cursor || n.tag == Tag.resolver || n.tag == Tag.provider {
        let child, error = toExpectationDepth(store, target, n.a, depth + 1, budget); if error != blot_error::Error.none { return 0, error; }
        if n.tag == Tag.owning { return internExpectation(store, target, blot_eval_type_evidence::Tag.usage, child, n.b, []); }
        var tag = blot_eval_type_evidence::Tag.resolver;
        if n.tag == Tag.array { tag = blot_eval_type_evidence::Tag.array; } else if n.tag == Tag.list { tag = blot_eval_type_evidence::Tag.list; } else if n.tag == Tag.cursor { tag = blot_eval_type_evidence::Tag.cursor; } else if n.tag == Tag.provider { tag = blot_eval_type_evidence::Tag.provider; }
        return internExpectation(store, target, tag, child, 0, []);
    }
    if n.tag == Tag.state_provider {
        let read, read_error = toExpectationDepth(store, target, n.a, depth + 1, budget); if read_error != blot_error::Error.none { return 0, read_error; }
        let write, write_error = toExpectationDepth(store, target, n.b, depth + 1, budget); if write_error != blot_error::Error.none { return 0, write_error; }
        let state, state_error = toExpectationDepth(store, target, n.c, depth + 1, budget); if state_error != blot_error::Error.none { return 0, state_error; }
        let result, error = target.internStateProvider(read, write, state); if error != blot_error::Error.none { return 0, expectationError(error); } return result, blot_error::Error.none;
    }
    if n.tag == Tag.function {
        let input, input_error = toExpectationDepth(store, target, n.a, depth + 1, budget); if input_error != blot_error::Error.none { return 0, input_error; }
        let output, output_error = toExpectationDepth(store, target, n.b, depth + 1, budget); if output_error != blot_error::Error.none { return 0, output_error; }
        return internExpectation(store, target, blot_eval_type_evidence::Tag.function, input, output, []);
    }
    if n.tag == Tag.product || n.tag == Tag.record || n.tag == Tag.nominal {

        var values=blot_eval_type_evidence::WordBuffer{};
        recursive fn convertChildren()->Id,blot_error::Error {
 let count = children(store, id).len;
        for index in 0..count { let child = children(store, id)[index]; if n.tag == Tag.record && index % 2 == 0 { values.push(child);if values.failure!=blot_error::Error.none {return 0,values.failure;} } else { let value, error = toExpectationDepth(store, target, child, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } values.push(value);if values.failure!=blot_error::Error.none {return 0,values.failure;} } }
        if n.tag == Tag.nominal { return internExpectation(store, target, blot_eval_type_evidence::Tag.nominal, n.a, n.b, values.items); }
        if n.tag == Tag.record { return internExpectation(store, target, blot_eval_type_evidence::Tag.record, 0, 0, values.items); }
        return internExpectation(store, target, blot_eval_type_evidence::Tag.product, 0, 0, values.items);

        }
        let result,error=convertChildren();values.deinit();return result,error;
    }
    return 0, blot_error::Error.unresolved_type;
}
fn solverError(error: blot_error::Error) -> blot_error::Error { if error == blot_error::Error.out_of_memory || error == blot_error::Error.type_mismatch { return error; } return blot_error::Error.layout_limit; }
fn fromSolver(store: Store&, source: blot_check_types::Store&, ty: blot_check_types::Id) -> Id, blot_error::Error { var budget: i64 = 1000000; return fromSolverDepth(store, source, ty, 0, budget); }
recursive fn fromSolverDepth(store: Store&, source: blot_check_types::Store&, ty: blot_check_types::Id, depth: i64, budget: i64&) -> Id, blot_error::Error {
    if depth >= 1024 || budget == 0 { return 0, blot_error::Error.layout_limit; } budget--;
    let root, resolved = source.resolve(ty, 0); if resolved != blot_error::Error.none { return 0, solverError(resolved); }
    let n = source.node(root);
    if n.tag == blot_check_types::Tag.unit || n.tag == blot_check_types::Tag.boolean || n.tag == blot_check_types::Tag.unsigned32 || n.tag == blot_check_types::Tag.floating32 || n.tag == blot_check_types::Tag.never { return root, blot_error::Error.none; }
    if n.tag == blot_check_types::Tag.variable { return erased, blot_error::Error.none; }
    if n.tag == blot_check_types::Tag.usage {
        let payload, error = fromSolverDepth(store, source, n.a, depth + 1, budget); if error != blot_error::Error.none { return 0, error; }
        if n.b == blot_parse_ast::usagekind_unique || n.b == blot_parse_ast::usagekind_shared { return intern(store, Tag.owning, payload, n.b, []); } return payload, blot_error::Error.none;
    }
    if n.tag == blot_check_types::Tag.forall || n.tag == blot_check_types::Tag.existential {
        if n.c == 0 || n.c > 128 { return 0, blot_error::Error.layout_limit; }
        var owned: u32[128] = [0; 128]; for index in 0..n.c { owned[index]=source.list(blot_check_types::List { start: n.b, len: n.c , ..})[index]; } var binders: Id[128] = [0; 128];
        for ordinal in 0..n.c { let formal=owned[ordinal];
            let leaf = source.node(formal); if leaf.tag != blot_check_types::Tag.bound || leaf.a != ordinal || leaf.b > 2 || leaf.c != 0 { return 0, blot_error::Error.unresolved_type; }
            let value, error = internWithEffects(store, Tag.opened, ordinal as u32, 0, leaf.b, []); if error != blot_error::Error.none { return 0, error; } binders[ordinal] = value;
        }
        if store.solver_owners.len >= 128 { return 0, blot_error::Error.layout_limit; }
        let mark = store.solver_binders.len; let range = blot_backend_runtime_ir::Range { start: mark, len: n.c , ..}; store.solver_binders.append(owned[..n.c]); store.solver_owners.push(range);
        let body, error = fromSolverDepth(store, source, n.a, depth + 1, budget); store.solver_owners.pop(); store.solver_binders.resize(mark); if error != blot_error::Error.none { return 0, error; }
        var tag = Tag.existential; if n.tag == blot_check_types::Tag.forall { tag = Tag.universal; } return intern(store, tag, body, n.c, binders[..n.c]);
    }
    if n.tag == blot_check_types::Tag.bound {
        if n.a >= 128 || n.b > 2 || n.c != 0 { return 0, blot_error::Error.unresolved_type; }
        var index = store.solver_owners.len;
        while index != 0 { index--; let owner = store.solver_owners[index]; if n.a >= owner.len || store.solver_binders[owner.start + n.a] != root { continue; } return internWithEffects(store, Tag.opened, n.a, (store.solver_owners.len - 1 - index) as u32, n.b, []); }
        return internWithEffects(store, Tag.opened, n.a, 0, n.b, []);
    }
    if n.tag == blot_check_types::Tag.erased_proof { return intern(store, Tag.erased_proof, 0, 0, []); }
    if n.tag == blot_check_types::Tag.scoped { return intern(store, Tag.nominal, 4294967295, capability_layout_decl, []); }
    if n.tag == blot_check_types::Tag.type_constructor { return intern(store, Tag.type_constructor, n.a, n.b, []); }
    if n.tag == blot_check_types::Tag.array || n.tag == blot_check_types::Tag.list || n.tag == blot_check_types::Tag.cursor || n.tag == blot_check_types::Tag.resolver {
        let child, error = fromSolverDepth(store, source, n.a, depth + 1, budget); if error != blot_error::Error.none { return 0, error; }
        var tag = Tag.resolver; if n.tag == blot_check_types::Tag.array { tag = Tag.array; } else if n.tag == blot_check_types::Tag.list { tag = Tag.list; } else if n.tag == blot_check_types::Tag.cursor { tag = Tag.cursor; } return intern(store, tag, child, 0, []);
    }
    if n.tag == blot_check_types::Tag.function || n.tag == blot_check_types::Tag.provider {
        let input, input_error = fromSolverDepth(store, source, n.a, depth + 1, budget); if input_error != blot_error::Error.none { return 0, input_error; }
        var output: Id = 0; var tag = Tag.provider;
        if n.tag == blot_check_types::Tag.function { let selected, error = fromSolverDepth(store, source, n.b, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } output = selected; tag = Tag.function; }
        let row, error = fromSolverRow(store, source, n.c, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } return internWithEffects(store, tag, input, output, row, []);
    }
    if n.tag == blot_check_types::Tag.state_provider {
        let read, read_error = fromSolverDepth(store, source, n.a, depth + 1, budget); if read_error != blot_error::Error.none { return 0, read_error; }
        let write, write_error = fromSolverDepth(store, source, n.b, depth + 1, budget); if write_error != blot_error::Error.none { return 0, write_error; }
        let state, state_error = fromSolverDepth(store, source, n.c, depth + 1, budget); if state_error != blot_error::Error.none { return 0, state_error; }
        return internStateProvider(store, read, write, state);
    }
    if n.tag == blot_check_types::Tag.product || n.tag == blot_check_types::Tag.record || n.tag == blot_check_types::Tag.nominal {
        if n.tag == blot_check_types::Tag.nominal && n.a == blot_check_task_types::handle.unit && n.b == blot_check_task_types::handle.decl { return intern(store, Tag.product, 0, 0, [blot_check_types::u32_type, blot_check_types::u32_type]); }

        var values=blot_eval_type_evidence::WordBuffer{}; var source_children=blot_eval_type_evidence::WordBuffer{};
        recursive fn convertChildren()->Id,blot_error::Error {

        if n.tag == blot_check_types::Tag.record {
            for index in 0..n.b { let field = source.recordField(n, index); values.push(field.name);if values.failure!=blot_error::Error.none {return 0,values.failure;} let child, error = fromSolverDepth(store, source, field.ty, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } values.push(child);if values.failure!=blot_error::Error.none {return 0,values.failure;} } return internRecord(store, values.items);
        }

        if n.tag == blot_check_types::Tag.nominal { source_children.append(source.nominalArguments(n));if source_children.failure!=blot_error::Error.none {return 0,source_children.failure;} } else { source_children.append(source.list(blot_check_types::List { start: n.a, len: n.b , ..}));if source_children.failure!=blot_error::Error.none {return 0,source_children.failure;} }
        for index in 0..source_children.len {let child=source_children.items[index]; let value, error = fromSolverDepth(store, source, child, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } values.push(value);if values.failure!=blot_error::Error.none {return 0,values.failure;} }
        if n.tag == blot_check_types::Tag.nominal { return intern(store, Tag.nominal, n.a, n.b, values.items); } return intern(store, Tag.product, 0, 0, values.items);

        }
        let result,error=convertChildren();source_children.deinit();values.deinit();return result,error;
    }
    return 0, blot_error::Error.unresolved_type;
}
recursive fn fromSolverRow(store: Store&, source: blot_check_types::Store&, row: u32, depth: i64, budget: i64&) -> u32, blot_error::Error {
    if depth >= 1024 || budget == 0 { return 0, blot_error::Error.layout_limit; } budget--;
    let root, resolved = source.resolveEffects(row, 0); if resolved != blot_error::Error.none { return 0, solverError(resolved); }
    let kind, tail = tailInfo(source.row(root).tail); if kind != 0 && kind != 3 { return unknown_row, blot_error::Error.none; }
    var formal: Id = 0;
    if kind == 3 { let selected, error = fromSolverDepth(store, source, tail, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } formal = selected; if node(store, formal).tag != Tag.opened || node(store, formal).c != 1 { return 0, blot_error::Error.type_mismatch; } }
        var labels=blot_eval_type_evidence::WordBuffer{};
    var arguments=blot_eval_type_evidence::WordBuffer{};
    var source_labels=blot_eval_type_evidence::WordBuffer{};
    var source_arguments=blot_eval_type_evidence::WordBuffer{};
    recursive fn convertRow()->u32,blot_error::Error {
   source_labels.append(source.rowLabels(root));if source_labels.failure!=blot_error::Error.none {return 0,source_labels.failure;}
    for label_index in 0..source_labels.len {let label=source_labels.items[label_index];
        arguments.clear();  source_arguments.clear();source_arguments.append(source.operationArguments(label));if source_arguments.failure!=blot_error::Error.none {return 0,source_arguments.failure;} let identity = source.operation(label).identity;
        for argument_index in 0..source_arguments.len {let argument=source_arguments.items[argument_index]; let child, error = fromSolverDepth(store, source, argument, depth + 1, budget); if error != blot_error::Error.none { return 0, error; } arguments.push(child);if arguments.failure!=blot_error::Error.none {return 0,arguments.failure;} }
        let mapped, error = store.effects.internOperationInstance(identity, arguments.items, blot_check_types::selectionAtom(source, source.operation(label).instance)); if error != blot_error::Error.none { return 0, effectError(error); } labels.push(mapped);if labels.failure!=blot_error::Error.none {return 0,labels.failure;}
    }
    let result, error = store.effects.internRowWithFormal(labels.items, formal); if error != blot_error::Error.none { return 0, effectError(error); } return result, blot_error::Error.none;

    }
    let result,error=convertRow();source_arguments.deinit();source_labels.deinit();arguments.deinit();labels.deinit();return result,error;
}
fn deinit(closed: ClosedLayouts&) { closed.kinds.clear(); closed.kind_bytes.clear(); closed.layouts.clear(); }
fn deinit(store: Store&) {
    store.effects.deinit();
    deinit(store.closed); store.record_names.map.clear();
    store.nodes.clear(); store.extra.clear(); store.universal_dictionaries.clear(); store.next.clear(); store.buckets.clear();
    store.solver_owners.clear(); store.solver_binders.clear(); store.type_owners.clear();
}
fn reset(store: Store&) -> blot_error::Error {
    deinit(store);
    let effects,error = blot_check_effect_evidence::init();
    if error != blot_error::Error.none { return error; } store.effects = effects; return init(store);
}
