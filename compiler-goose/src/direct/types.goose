// Concrete types of one direct compilation, hash-consed across all units, so
// type equality is handle equality and each layout is computed once.
// Port of compiler/src/direct/types.zig.
namespace blot_direct_types;
import std;
import check.core;
import check.types;
import check.storage_types;
import reuse.principal_interface;
import support.option;
import direct.writer;
import direct.map;

type Ty = u32;
let unit: Ty = 0;
let boolean: Ty = 1;
let u32_: Ty = 2;
let f32_: Ty = 3;
let never: Ty = 4;
type Module = blot_check_core::Module;
type ValType = blot_direct_writer::ValType;
type TId = blot_check_types::Id;
type TTag = blot_check_types::Tag;
type Text = const u8[:];
type U64Map = blot_direct_map::U64Map;

// Zig's `A.Error || error{Unsupported}`, and emit.zig's Diverged. Allocation
// failure is not an error value here.
enum Error { none, unsupported, diverged }

enum Tag { unit, boolean, u32_, f32_, never, tuple, record, nominal, function, array, grow, resize, ref, view, link, provider, state_provider, cell }
fn tagCode(tag: Tag) -> u32 {
    match tag {
        unit => { return 0; }, boolean => { return 1; }, u32_ => { return 2; }, f32_ => { return 3; }, never => { return 4; },
        tuple => { return 5; }, record => { return 6; }, nominal => { return 7; }, function => { return 8; }, array => { return 9; },
        grow => { return 10; }, resize => { return 11; }, ref => { return 12; },
        view => { return 13; }, link => { return 14; }, provider => { return 15; }, state_provider => { return 16; }, cell => { return 17; },
    }
}
// The Zig spelling of each tag, for diagnostics.
fn tagName(tag: Tag) -> Text {
    match tag {
        unit => { return "unit"; }, boolean => { return "boolean"; }, u32_ => { return "u32"; }, f32_ => { return "f32"; }, never => { return "never"; },
        tuple => { return "tuple"; }, record => { return "record"; }, nominal => { return "nominal"; }, function => { return "function"; }, array => { return "array"; },
        grow => { return "grow"; }, resize => { return "resize"; }, ref => { return "ref"; },
        view => { return "view"; }, link => { return "link"; }, provider => { return "provider"; }, state_provider => { return "state_provider"; }, cell => { return "cell"; },
    }
}
// The Zig spelling of a Core type tag, for `fail(m, ty, @tagName(n.tag))`.
fn coreTypeTagName(tag: TTag) -> Text {
    match tag {
        absent => { return "absent"; }, unit => { return "unit"; }, boolean => { return "boolean"; }, unsigned32 => { return "u32"; }, floating32 => { return "f32"; },
        never => { return "never"; }, variable => { return "variable"; }, function => { return "function"; }, product => { return "product"; }, record => { return "record"; },
        nominal => { return "nominal"; }, array => { return "array"; }, type_constructor => { return "type_constructor"; },
        provider => { return "provider"; }, state_provider => { return "state_provider"; }, projection => { return "projection"; },
        scoped => { return "scoped"; }, instance_selection => { return "instance_selection"; }, erased_proof => { return "erased_proof"; }, forall => { return "forall"; },
        existential => { return "existential"; }, bound => { return "bound"; }, rigid => { return "rigid"; }, usage => { return "usage"; }, instance_version => { return "instance_version"; },
        _ => { return "retired"; },
    }
}

// tuple/record: a = list start, b = count (records store name/type pairs in
// spelling order); nominal: a = list start ([unit, decl, arguments...]), b =
// argument count; function: a = parameter, b = result; containers: a = element.
struct Node { tag: Tag, a: u32 = 0, b: u32 = 0 }
struct Field { name: u32, ty: Ty }
let chunk_words: i64 = 65536;

struct VarKey { unit: u32 = 0, ty: TId = 0 }
// Bindings of Core type variables (by unit and type node) to concrete types.
// Zig holds a hash map per environment. Here an environment is a persistent
// list in `Types.env_nodes`: binding prepends a node, so a copy of the header
// is a clone that later bindings to either copy do not disturb.
struct Env { head: u32 = 0, count: u32 = 0 }
struct EnvNode { unit: u32, ty: TId, value: Ty, next: u32 }

// The constructors of one concrete nominal type, in declaration order: `len`
// tags from `tags` in Types.variant_tags and payloads in Types.variant_payloads.
struct Variants { tags: u32 = 0, payloads: u32 = 0, len: u32 = 0 }
struct Span { start: u32 = 0, len: u32 = 0 }
struct Slot { present: bool = false, start: u32 = 0, len: u32 = 0 }
struct VariantSlot { present: bool = false, value: Variants = Variants {} }

root struct Types {
    units: const Module[:],
    nodes: Node[>..] = [],
    // Interned type lists. The array only grows, so a slice from `list`
    // stays valid while more types are interned.
    words: u32[>..] = [],
    keys: Span[>..] = [],
    encodings: u32[>..] = [],
    // Hash of an encoding to the newest type with that hash (id + 1), and
    // each type's next older one.
    index: U64Map = U64Map {},
    index_next: u32[>..] = [],
    // Field names: hash of a spelling to the newest name (id + 1).
    names: U64Map = U64Map {},
    name_next: u32[>..] = [],
    spelling_bytes: u8[>..] = [],
    spellings: Span[>..] = [],
    layout_words: ValType[>..] = [],
    layouts: Slot[>..] = [],
    variant_tags: u32[>..] = [],
    variant_payloads: Ty[>..] = [],
    variant_cache: VariantSlot[>..] = [],
    // Lowered closed Core types; open ones depend on an environment.
    closed_base: u32[>..] = [],
    closed_len: u32[>..] = [],
    closed_vals: u32[>..] = [],
    field_id_base: u32[>..] = [],
    field_id_len: u32[>..] = [],
    field_ids: u32[>..] = [],
    nominal_positions: U64Map = U64Map {},
    in_layout: bool[>..] = [],
    // Nominal types that contain themselves: always one pointer to an
    // immutable block, even inside other values; the slot is the block.
    recursive_: Slot[>..] = [],
    // The Core type that last failed to lower, for diagnostics.
    has_failure: bool = false,
    failure: VarKey = VarKey {},
    holes: bool = false,
    // What an unbound variable lowers to while `holes` is set.
    hole_fill: Ty = 4,
    failure_reason: Text = "",
    env_nodes: EnvNode[>..] = [],
    // Scratch shared by the recursive walks; grows only, top tracked by *_len.
    scratch: u32[>..] = [],
    scratch_len: i64 = 0,
    scratch_fields: Field[>..] = [],
    scratch_fields_len: i64 = 0,
    scratch_layout: ValType[>..] = [],
    scratch_layout_len: i64 = 0,
}

fn pushScratch(self_: Types&, value: u32) {
    if self_.scratch_len < self_.scratch.len { self_.scratch[self_.scratch_len] = value; }
    else { self_.scratch.push(value); }
    self_.scratch_len += 1;
}
fn pushScratchField(self_: Types&, value: Field) {
    if self_.scratch_fields_len < self_.scratch_fields.len { self_.scratch_fields[self_.scratch_fields_len] = value; }
    else { self_.scratch_fields.push(value); }
    self_.scratch_fields_len += 1;
}
fn pushScratchLayout(self_: Types&, value: ValType) {
    if self_.scratch_layout_len < self_.scratch_layout.len { self_.scratch_layout[self_.scratch_layout_len] = value; }
    else { self_.scratch_layout.push(value); }
    self_.scratch_layout_len += 1;
}

fn key64(unit_id: u32, id: u32) -> u64 { let high: u64 = unit_id; return (high << 32) | id; }

fn isClosed(self_: const Types&, unit_id: u32, ty: TId) -> bool {
    return self_.closed_vals[(self_.closed_base[unit_id - 1] as i64) + (ty as i64)] != 0xffffffff;
}

fn initUnitTables(self_: Types&) {
    var total_types: i64 = 0;
    var total_fields: i64 = 0;
    for m in self_.units {
        self_.closed_base.push(total_types as u32);
        self_.closed_len.push(m.types.nodes.len as u32);
        total_types += m.types.nodes.len;
        self_.field_id_base.push(total_fields as u32);
        self_.field_id_len.push(m.field_names.len as u32);
        total_fields += m.field_names.len;
    }
    while self_.closed_vals.len < total_types { self_.closed_vals.push(0xffffffff); }
    while self_.field_ids.len < total_fields { self_.field_ids.push(0xffffffff); }
}

fn resetClosedUnit(self_: Types&, unit_id: u32) {
    let idx = (unit_id - 1) as i64;
    let need = self_.units[idx].types.nodes.len;
    if need <= (self_.closed_len[idx] as i64) {
        let base = self_.closed_base[idx] as i64;
        for at in base..base + need { self_.closed_vals[at] = 0xffffffff; }
    } else {
        let base = self_.closed_vals.len as u32;
        self_.closed_base[idx] = base;
        self_.closed_len[idx] = need as u32;
        for at in 0..need { self_.closed_vals.push(0xffffffff); }
    }
    let fneed = self_.units[idx].field_names.len;
    if fneed <= (self_.field_id_len[idx] as i64) {
        let fbase = self_.field_id_base[idx] as i64;
        for at in fbase..fbase + fneed { self_.field_ids[at] = 0xffffffff; }
    } else {
        let fbase = self_.field_ids.len as u32;
        self_.field_id_base[idx] = fbase;
        self_.field_id_len[idx] = fneed as u32;
        for at in 0..fneed { self_.field_ids.push(0xffffffff); }
    }
}

fn resetClosed(self_: Types&) {
    for idx in 0..self_.units.len { resetClosedUnit(self_, (idx + 1) as u32); }
}

fn init(self_: Types&) {
    // Layout word 0 is the one pointer of a boxed or recursive value.
    self_.layout_words.push(blot_direct_writer::VT_i32);
    // Environment node 0 ends every list.
    self_.env_nodes.push(EnvNode { 0, 0, 0, 0 });
    initUnitTables(self_);
    for tag in [Tag.unit, Tag.boolean, Tag.u32_, Tag.f32_, Tag.never] {
        let id, error = intern(self_, tag, []);
        assert(error == Error.none);
    }
}
fn node(self_: const Types&, ty: Ty) -> Node { return self_.nodes[ty]; }
fn list(self_: const Types&, start: u32, len: u32) -> const u32[:] {
    if len == 0 { return self_.words[0..0]; }
    return self_.words[start..start + len];
}
fn storeList(self_: Types&, payload: const u32[:]) -> u32, Error {
    if payload.len == 0 { return 0, Error.none; }
    if payload.len > chunk_words { return 0, Error.unsupported; }
    let start = self_.words.len as u32;
    self_.words.append(payload);
    return start, Error.none;
}
fn tupleItems(self_: const Types&, ty: Ty) -> const Ty[:] {
    let n = self_.node(ty);
    assert(n.tag == Tag.tuple);
    return self_.list(n.a, n.b);
}
fn recordField(self_: const Types&, ty: Ty, index: i64) -> Field {
    let n = self_.node(ty);
    assert(n.tag == Tag.record);
    let pair = self_.list(n.a + (index * 2) as u32, 2);
    return Field { pair[0], pair[1] };
}
fn nominalIdentity(self_: const Types&, ty: Ty) -> blot_check_types::NominalIdentity {
    let n = self_.node(ty);
    assert(n.tag == Tag.nominal);
    let pair = self_.list(n.a, 2);
    return blot_check_types::NominalIdentity { pair[0], pair[1] };
}
fn nominalArguments(self_: const Types&, ty: Ty) -> const Ty[:] {
    let n = self_.node(ty);
    assert(n.tag == Tag.nominal);
    return self_.list(n.a + 2, n.b);
}
// Units are numbered from one in compilation order.
fn module(self_: const Types&, unit_id: u32) -> const Module? {
    if unit_id == 0 || unit_id > self_.units.len { return null; }
    return self_.units[unit_id - 1];
}

// --- Environments -------------------------------------------------------

fn envGet(self_: const Types&, env: Env, unit_id: u32, ty: TId) -> Ty, bool {
    var at = env.head;
    while at != 0 {
        let entry = self_.env_nodes[at];
        if entry.ty == ty && entry.unit == unit_id { return entry.value, true; }
        at = entry.next;
    }
    return 0, false;
}
// Zig's getOrPut that keeps a present binding. True when it added one.
fn envBind(self_: Types&, env: Env&, unit_id: u32, ty: TId, value: Ty) -> bool {
    let found, present = envGet(self_, env, unit_id, ty);
    if present { return false; }
    self_.env_nodes.push(EnvNode { unit_id, ty, value, env.head });
    env.head = (self_.env_nodes.len - 1) as u32;
    env.count += 1;
    return true;
}
// Zig's put: the binding is replaced when present.
fn envPut(self_: Types&, env: Env&, unit_id: u32, ty: TId, value: Ty) {
    let found, present = envGet(self_, env, unit_id, ty);
    if present && found == value { return; }
    self_.env_nodes.push(EnvNode { unit_id, ty, value, env.head });
    env.head = (self_.env_nodes.len - 1) as u32;
    if !present { env.count += 1; }
}

// --- Interning ----------------------------------------------------------

fn hashEncoding(tag: u32, payload: const u32[:]) -> u64 {
    var h = ::hash(tag);
    for word in payload { h = ::hash_combine(h, ::hash(word)); }
    return h;
}
fn sameEncoding(self_: const Types&, id: Ty, tag: u32, payload: const u32[:]) -> bool {
    let span = self_.keys[id];
    if span.len != payload.len + 1 { return false; }
    if self_.encodings[span.start] != tag { return false; }
    for word, at in payload { if self_.encodings[span.start + 1 + at] != word { return false; } }
    return true;
}
fn intern(self_: Types&, tag: Tag, payload: const u32[:]) -> Ty, Error {
    let code = tagCode(tag);
    let hashed = hashEncoding(code, payload);
    let head, known = self_.index.get(hashed);
    var at = head;
    while at != 0 {
        if sameEncoding(self_, at - 1, code, payload) { return at - 1, Error.none; }
        at = self_.index_next[at - 1];
    }
    var arity: i64 = -1;
    match tag {
        function => { arity = 2; },
        array, grow, resize, ref, view, link, provider, cell => { arity = 1; },
        state_provider => { arity = 3; },
        _ => {},
    }
    if arity >= 0 && payload.len != arity { return 0, Error.unsupported; }
    if tag == Tag.nominal && payload.len < 2 { return 0, Error.unsupported; }
    let listed = tag == Tag.tuple || tag == Tag.record || tag == Tag.nominal || tag == Tag.state_provider;
    var start: u32 = 0;
    if listed {
        let stored, error = storeList(self_, payload);
        if error != Error.none { return 0, error; }
        start = stored;
    }
    // The arity check above gives a function two words and a container one.
    var first: u32 = 0;
    if arity >= 0 { first = payload[0]; }
    var value = Node { tag: tag };
    match tag {
        unit, boolean, u32_, f32_, never => {},
        tuple, state_provider => { value = Node { tag, start, payload.len as u32 }; },
        record => { value = Node { tag, start, (payload.len / 2) as u32 }; },
        nominal => { value = Node { tag, start, (payload.len - 2) as u32 }; },
        function => { value = Node { tag, first, payload[payload.len - 1] }; },
        array, grow, resize, ref, view, link, provider, cell => { value = Node { tag, first, 0 }; },
    }
    let id = self_.nodes.len as Ty;
    let span = Span { self_.encodings.len as u32, (payload.len + 1) as u32 };
    self_.encodings.push(code);
    self_.encodings.append(payload);
    self_.nodes.push(value);
    self_.keys.push(span);
    self_.layouts.push(Slot {});
    self_.variant_cache.push(VariantSlot {});
    self_.in_layout.push(false);
    self_.recursive_.push(Slot {});
    self_.index_next.push(head);
    self_.index.put(hashed, id + 1);
    return id, Error.none;
}
fn function(self_: Types&, parameter: Ty, result: Ty) -> Ty, Error { return intern(self_, Tag.function, [parameter, result]); }
fn cell(self_: Types&, element: Ty) -> Ty, Error { return intern(self_, Tag.cell, [element]); }
fn tuple(self_: Types&, items: const Ty[:]) -> Ty, Error {
    if items.len == 0 { return unit, Error.none; }
    return intern(self_, Tag.tuple, items);
}
fn spelling(self_: const Types&, name: u32) -> Text {
    let span = self_.spellings[name];
    return self_.spelling_bytes[span.start..span.start + span.len];
}
fn lessText(left: Text, right: Text) -> bool {
    let shared = min(left.len, right.len);
    for at in 0..shared { if left[at] != right[at] { return left[at] < right[at]; } }
    return left.len < right.len;
}
// Field order is the UTF-8 spelling order, independent of source order.
// `fields` is sorted in place, as Zig sorts its argument.
fn record(self_: Types&, fields: Field[:]) -> Ty, Error {
    for at in 1..fields.len {
        let moved = fields[at];
        var slot = at;
        while slot > 0 && lessText(self_.spelling(moved.name), self_.spelling(fields[slot - 1].name)) {
            fields[slot] = fields[slot - 1];
            slot -= 1;
        }
        fields[slot] = moved;
    }
    let mark = self_.scratch_len;
    for field in fields { self_.pushScratch(field.name); self_.pushScratch(field.ty); }
    let id, error = intern(self_, Tag.record, self_.scratch[mark..self_.scratch_len]);
    self_.scratch_len = mark;
    return id, error;
}
fn findName(self_: const Types&, text: Text) -> u32, bool {
    let first, known = self_.names.get(::hash(text));
    var at = first;
    while at != 0 {
        if self_.spelling(at - 1) == text { return at - 1, true; }
        at = self_.name_next[at - 1];
    }
    return 0, false;
}
fn fieldName(self_: Types&, text: Text) -> u32 {
    let found, present = findName(self_, text);
    if present { return found; }
    let hashed = ::hash(text);
    let head, known = self_.names.get(hashed);
    let id = self_.spellings.len as u32;
    self_.spellings.push(Span { self_.spelling_bytes.len as u32, text.len as u32 });
    self_.spelling_bytes.append(text);
    self_.name_next.push(head);
    self_.names.put(hashed, id + 1);
    return id;
}
fn fieldNameOf(self_: Types&, m: const Module&, symbol: u32, intern_missing: bool) -> u32, bool {
    var low: i64 = 0;
    var high = m.field_names.len;
    while low < high {
        let middle = low + (high - low) / 2;
        let value = m.field_names[middle];
        if value.symbol < symbol { low = middle + 1; }
        else if value.symbol > symbol { high = middle; }
        else {
            let slot = (self_.field_id_base[m.unit - 1] as i64) + middle;
            let cached = self_.field_ids[slot];
            if cached != 0xffffffff { return cached, true; }
            let text = m.name(value.spelling);
            if intern_missing {
                let id = fieldName(self_, text);
                self_.field_ids[slot] = id;
                return id, true;
            }
            let id, known = findName(self_, text);
            if known { self_.field_ids[slot] = id; return id, true; }
            return 0, false;
        }
    }
    return 0, false;
}
fn findField(self_: const Types&, ty: Ty, name: u32) -> i64 {
    let n = self_.node(ty);
    if n.tag != Tag.record { return -1; }
    for index in 0..(n.b as i64) { if self_.recordField(ty, index).name == name { return index; } }
    return -1;
}

fn fail(self_: Types&, m: const Module&, ty: TId, reason: Text) -> Error {
    self_.has_failure = true;
    self_.failure = VarKey { m.unit, ty };
    self_.failure_reason = reason;
    return Error.unsupported;
}

// --- Lowering Core types ------------------------------------------------

// Lowers a Core type under `env`, which binds the type variables of the
// instance being compiled.
fn lower(self_: Types&, m: const Module&, ty: TId, env: Env) -> Ty, Error {
    var open = false;
    return lowerInner(self_, m, ty, env, open, 0);
}
// Like lower, but unbound variables become `never` holes, which `match_`
// skips: an expected type known only in part.
fn lowerHoles(self_: Types&, m: const Module&, ty: TId, env: Env) -> Ty, Error { return lowerFilled(self_, m, ty, env, never); }
// Like lowerHoles, with `fill` in place of each unbound variable.
fn lowerFilled(self_: Types&, m: const Module&, ty: TId, env: Env, fill: Ty) -> Ty, Error {
    self_.holes = true;
    self_.hole_fill = fill;
    var open = false;
    let result, error = lowerInner(self_, m, ty, env, open, 0);
    self_.holes = false;
    self_.hole_fill = never;
    return result, error;
}
recursive fn lowerInner(self_: Types&, m: const Module&, ty: TId, env: Env, open: bool&, depth: i64) -> Ty, Error {
    if ty == blot_check_types::unit { return unit, Error.none; }
    if ty == blot_check_types::boolean { return boolean, Error.none; }
    if ty == blot_check_types::u32_type { return u32_, Error.none; }
    if ty == blot_check_types::f32_type { return f32_, Error.none; }
    if ty == blot_check_types::never { return never, Error.none; }
    if depth > 256 { return 0, fail(self_, m, ty, "type nesting exceeds 256"); }
    let closed_idx = (self_.closed_base[m.unit - 1] as i64) + (ty as i64);
    let hit = self_.closed_vals[closed_idx];
    if hit != 0xffffffff { return hit, Error.none; }
    var child_open = false;
    let n = m.types.node(ty);
    var result: Ty = 0;
    match n.tag {
        variable, bound => {
            child_open = true;
            let bound_to, present = envGet(self_, env, m.unit, ty);
            if present { result = bound_to; }
            else if self_.holes { result = self_.hole_fill; }
            else { return 0, fail(self_, m, ty, "unresolved type variable"); }
        },
        usage, forall => {
            let inner, error = lowerInner(self_, m, n.a, env, child_open, depth + 1);
            if error != Error.none { return 0, error; }
            result = inner;
        },
        function => {
            let parameter, error = lowerInner(self_, m, n.a, env, child_open, depth + 1);
            if error != Error.none { return 0, error; }
            let returned, error = lowerInner(self_, m, n.b, env, child_open, depth + 1);
            if error != Error.none { return 0, error; }
            let made, error = function(self_, parameter, returned);
            if error != Error.none { return 0, error; }
            result = made;
        },
        product => {
            let children = m.types.list(blot_check_types::List { n.a, n.b });
            let mark = self_.scratch_len;
            for child in children {
                let item, error = lowerInner(self_, m, child, env, child_open, depth + 1);
                if error != Error.none { self_.scratch_len = mark; return 0, error; }
                self_.pushScratch(item);
            }
            let made, error = tuple(self_, self_.scratch[mark..self_.scratch_len]);
            self_.scratch_len = mark;
            if error != Error.none { return 0, error; }
            result = made;
        },
        record => {
            let mark = self_.scratch_fields_len;
            for index in 0..(n.b as i64) {
                let source = m.types.recordField(n, index);
                let name, ok = fieldNameOf(self_, m, source.name, true);
                if !ok { self_.scratch_fields_len = mark; return 0, fail(self_, m, ty, "record field without a spelling"); }
                let field_ty, error = lowerInner(self_, m, source.ty, env, child_open, depth + 1);
                if error != Error.none { self_.scratch_fields_len = mark; return 0, error; }
                self_.pushScratchField(Field { name, field_ty });
            }
            let made, error = record(self_, self_.scratch_fields[mark..self_.scratch_fields_len]);
            self_.scratch_fields_len = mark;
            if error != Error.none { return 0, error; }
            result = made;
        },
        nominal => {
            let arguments = m.types.nominalArguments(n);
            if blot_check_storage_types::isLengthLiteral(n.a, n.b) {
                result = unit;
            } else {
            let kind = blot_check_storage_types::identity(n.a, n.b);
            if kind.present {
                if kind.value == blot_check_storage_types::shared {
                    if arguments.len != 1 { return 0, fail(self_, m, ty, "storage type arity"); }
                    let inner, error = lowerInner(self_, m, arguments[0], env, child_open, depth + 1);
                    if error != Error.none { return 0, error; }
                    result = inner;
                } else if blot_check_storage_types::isSized(kind.value) {
                    if arguments.len != 2 { return 0, fail(self_, m, ty, "storage type arity"); }
                    let element, error = lowerInner(self_, m, arguments[1], env, child_open, depth + 1);
                    if error != Error.none { return 0, error; }
                    var tag = Tag.array;
                    if kind.value == blot_check_storage_types::sized_grow { tag = Tag.grow; }
                    else if kind.value == blot_check_storage_types::sized_resize { tag = Tag.resize; }
                    let made, error = intern(self_, tag, [element]);
                    if error != Error.none { return 0, error; }
                    result = made;
                } else {
                    if arguments.len != 1 { return 0, fail(self_, m, ty, "storage type arity"); }
                    let element, error = lowerInner(self_, m, arguments[0], env, child_open, depth + 1);
                    if error != Error.none { return 0, error; }
                    var tag = Tag.link;
                    if kind.value == blot_check_storage_types::grow { tag = Tag.grow; }
                    else if kind.value == blot_check_storage_types::resize { tag = Tag.resize; }
                    else if kind.value == blot_check_storage_types::ref { tag = Tag.ref; }
                    else if kind.value == blot_check_storage_types::view { tag = Tag.view; }
                    let made, error = intern(self_, tag, [element]);
                    if error != Error.none { return 0, error; }
                    result = made;
                }
            } else {
                if n.a == 0xffffffff { return 0, fail(self_, m, ty, "compiler-owned nominal type"); }
                let mark = self_.scratch_len;
                self_.pushScratch(n.a);
                self_.pushScratch(n.b);
                for argument in arguments {
                    let item, error = lowerInner(self_, m, argument, env, child_open, depth + 1);
                    if error != Error.none { self_.scratch_len = mark; return 0, error; }
                    self_.pushScratch(item);
                }
                let made, error = intern(self_, Tag.nominal, self_.scratch[mark..self_.scratch_len]);
                self_.scratch_len = mark;
                if error != Error.none { return 0, error; }
                result = made;
            }
            }
        },
        provider => {
            let operand, error = operation(self_, m, n.a, env, child_open, depth + 1);
            if error != Error.none { return 0, error; }
            let made, error = intern(self_, Tag.provider, [operand]);
            if error != Error.none { return 0, error; }
            result = made;
        },
        state_provider => {
            let get, error = operation(self_, m, n.a, env, child_open, depth + 1);
            if error != Error.none { return 0, error; }
            let set, error = operation(self_, m, n.b, env, child_open, depth + 1);
            if error != Error.none { return 0, error; }
            let state, error = lowerInner(self_, m, n.c, env, child_open, depth + 1);
            if error != Error.none { return 0, error; }
            let made, error = intern(self_, Tag.state_provider, [get, set, state]);
            if error != Error.none { return 0, error; }
            result = made;
        },
        array => {
            let element, error = lowerInner(self_, m, n.a, env, child_open, depth + 1);
            if error != Error.none { return 0, error; }
            let made, error = intern(self_, Tag.array, [element]);
            if error != Error.none { return 0, error; }
            result = made;
        },
        projection => {
            let contract_id = blot_check_types::NominalIdentity { n.a, n.b };
            let proj_member = m.types.projectionMember(n);
            let raw_args = m.types.nominalArguments(n);
            if raw_args.len > 16 { return 0, fail(self_, m, ty, "projection"); }
            var raw_arg_ids: TId[16] = [0; 16];
            let proj_len = raw_args.len;
            for ai in 0..proj_len { raw_arg_ids[ai] = raw_args[ai]; }
            var proj_args: Ty[16] = [0; 16];
            for ai in 0..proj_len {
                let lowered_arg, aerr = lowerInner(self_, m, raw_arg_ids[ai], env, child_open, depth + 1);
                if aerr != Error.none { return 0, aerr; }
                proj_args[ai] = lowered_arg;
            }
            var found = false;
            var found_ty: Ty = 0;
            let unit_count = self_.units.len;
            for unit_idx in 0..unit_count {
                var want_name = proj_member;
                if self_.units[unit_idx].unit != m.unit {
                    want_name = 0;
                    for declared in m.contracts {
                        if declared.identity != contract_id { continue; }
                        for member, mi in m.contract_members[declared.members.start..declared.members.start + declared.members.len] {
                            if member.name != proj_member { continue; }
                            for observed in self_.units[unit_idx].contracts {
                                if observed.identity == contract_id && mi < observed.members.len {
                                    want_name = self_.units[unit_idx].contract_members[observed.members.start + mi].name;
                                }
                            }
                        }
                    }
                }
                if want_name == 0 { continue; }
                let impl_count = self_.units[unit_idx].implementations.len;
                for impl_idx in 0..impl_count {
                    let impl_ = self_.units[unit_idx].implementations[impl_idx];
                    if impl_.contract != contract_id { continue; }
                    if impl_.head.len != proj_len { continue; }
                    var harg_ids: TId[16] = [0; 16];
                    for pi in 0..proj_len { harg_ids[pi] = self_.units[unit_idx].types.list(impl_.head)[pi]; }
                    var match_env = Env {};
                    var matches = true;
                    for pi in 0..proj_len {
                        matchInner(self_, self_.units[unit_idx], harg_ids[pi], proj_args[pi], match_env, 0);
                        var dummy_open = false;
                        let resolved_harg, herr = lowerInner(self_, self_.units[unit_idx], harg_ids[pi], match_env, dummy_open, depth + 1);
                        if herr != Error.none { matches = false; break; }
                        if resolved_harg != proj_args[pi] {
                            let pn = self_.node(proj_args[pi]);
                            let rn = self_.node(resolved_harg);
                            let array_lift = (pn.tag == Tag.grow || pn.tag == Tag.resize) && rn.tag == Tag.array && pn.a == rn.a;
                            if !array_lift { matches = false; break; }
                        }
                    }
                    if !matches { continue; }
                    var mem_root: TId = 0;
                    var has_mem = false;
                    let mem_start = impl_.members.start as i64;
                    let mem_end = mem_start + (impl_.members.len as i64);
                    for mi in mem_start..mem_end {
                        let member = self_.units[unit_idx].implementation_members[mi];
                        if member.kind == blot_reuse_principal_interface::ImplementationMemberKind.type_ && member.name == want_name {
                            mem_root = member.root;
                            has_mem = true;
                            break;
                        }
                    }
                    if has_mem {
                        var mem_open = false;
                        let lowered_mem, merr = lowerInner(self_, self_.units[unit_idx], mem_root, match_env, mem_open, depth + 1);
                        if merr != Error.none { return 0, merr; }
                        found_ty = lowered_mem;
                        found = true;
                        break;
                    }
                }
                if found { break; }
            }
            if !found { return 0, fail(self_, m, ty, "projection"); }
            result = found_ty;
        },
        _ => { return 0, fail(self_, m, ty, coreTypeTagName(n.tag)); },
    }
    if child_open { open = true; } else { self_.closed_vals[closed_idx] = result; }
    return result, Error.none;
}

// An effect operation's nominal type: only an identity, so compiler-owned
// operations (the builtin State family) lower like declared ones.
recursive fn operation(self_: Types&, m: const Module&, ty: TId, env: Env, open: bool&, depth: i64) -> Ty, Error {
    let n = m.types.node(ty);
    if n.tag != blot_check_types::Tag.nominal { return lowerInner(self_, m, ty, env, open, depth); }
    let arguments = m.types.nominalArguments(n);
    let mark = self_.scratch_len;
    self_.pushScratch(n.a);
    self_.pushScratch(n.b);
    for argument in arguments {
        let item, error = lowerInner(self_, m, argument, env, open, depth + 1);
        if error != Error.none { self_.scratch_len = mark; return 0, error; }
        self_.pushScratch(item);
    }
    let made, error = intern(self_, Tag.nominal, self_.scratch[mark..self_.scratch_len]);
    self_.scratch_len = mark;
    return made, error;
}
// Binds the variables of `pattern` (a Core type of `m`) so that it lowers to
// `actual`. Already bound variables keep their binding.
fn match_(self_: Types&, m: const Module&, pattern: TId, actual: Ty, env: Env&) { matchInner(self_, m, pattern, actual, env, 0); }
recursive fn matchInner(self_: Types&, m: const Module&, pattern: TId, actual: Ty, env: Env&, depth: i64) {
    if pattern <= blot_check_types::never || depth > 256 { return; }
    let n = m.types.node(pattern);
    let have = self_.node(actual);
    match n.tag {
        variable, bound => {
            if actual == never { return; } // a hole in a partly known type
            envBind(self_, env, m.unit, pattern, actual);
        },
        usage, forall => { matchInner(self_, m, n.a, actual, env, depth + 1); },
        function => {
            if have.tag == Tag.function {
                matchInner(self_, m, n.a, have.a, env, depth + 1);
                matchInner(self_, m, n.b, have.b, env, depth + 1);
            }
        },
        product => {
            if have.tag == Tag.tuple && have.b == n.b {
                let children = m.types.list(blot_check_types::List { n.a, n.b });
                for child, at in children { matchInner(self_, m, child, self_.words[have.a + at], env, depth + 1); }
            }
        },
        record => {
            if have.tag == Tag.record {
                for index in 0..(n.b as i64) {
                    let source = m.types.recordField(n, index);
                    let name, known = fieldNameOf(self_, m, source.name, false);
                    if !known { continue; }
                    let position = self_.findField(actual, name);
                    if position < 0 { continue; }
                    matchInner(self_, m, source.ty, self_.recordField(actual, position).ty, env, depth + 1);
                }
            }
        },
        nominal => {
            let arguments = m.types.nominalArguments(n);
            let skind = blot_check_storage_types::identity(n.a, n.b);
            if skind.present {
                if skind.value == blot_check_storage_types::shared && arguments.len == 1 {
                    matchInner(self_, m, arguments[0], actual, env, depth + 1);
                } else if blot_check_storage_types::isSized(skind.value) && arguments.len == 2 {
                    if isContainer(have.tag) { matchInner(self_, m, arguments[1], have.a, env, depth + 1); }
                } else if arguments.len == 1 && isContainer(have.tag) {
                    matchInner(self_, m, arguments[0], have.a, env, depth + 1);
                }
            } else if have.tag == Tag.nominal {
                let identity = self_.nominalIdentity(actual);
                if identity.unit != n.a || identity.decl != n.b { return; }
                if have.b != arguments.len { return; }
                for argument, at in arguments { matchInner(self_, m, argument, self_.words[have.a + 2 + at], env, depth + 1); }
            }
        },
        array => { if isContainer(have.tag) { matchInner(self_, m, n.a, have.a, env, depth + 1); } },
        provider => { if have.tag == Tag.provider { matchInner(self_, m, n.a, have.a, env, depth + 1); } },
        state_provider => {
            if have.tag == Tag.state_provider {
                // Zig zips three children with the stored list (always three).
                matchInner(self_, m, n.a, self_.words[have.a], env, depth + 1);
                matchInner(self_, m, n.b, self_.words[have.a + 1], env, depth + 1);
                matchInner(self_, m, n.c, self_.words[have.a + 2], env, depth + 1);
            }
        },
        _ => {},
    }
}

// Whether `ty` has no hole (`never`) anywhere, even under functions and
// containers.
recursive fn concrete(self_: const Types&, ty: Ty, depth: i64) -> bool {
    if depth > 64 { return false; }
    let n = self_.node(ty);
    match n.tag {
        never => { return false; },
        unit, boolean, u32_, f32_ => { return true; },
        function => { return concrete(self_, n.a, depth + 1) && concrete(self_, n.b, depth + 1); },
        array, grow, resize, ref, view, link, provider, cell => { return concrete(self_, n.a, depth + 1); },
        tuple, state_provider => {
            for at in 0..(n.b as i64) { if !concrete(self_, self_.words[n.a + at], depth + 1) { return false; } }
            return true;
        },
        record => {
            for index in 0..(n.b as i64) { if !concrete(self_, self_.recordField(ty, index).ty, depth + 1) { return false; } }
            return true;
        },
        nominal => {
            for at in 0..(n.b as i64) { if !concrete(self_, self_.words[n.a + 2 + at], depth + 1) { return false; } }
            return true;
        },
    }
}
fn variantTags(self_: const Types&, value: Variants) -> const u32[:] { return self_.variant_tags[value.tags..value.tags + value.len]; }
fn variantPayloads(self_: const Types&, value: Variants) -> const Ty[:] { return self_.variant_payloads[value.payloads..value.payloads + value.len]; }
// The constructors of a concrete nominal type and their payload types.
fn variants(self_: Types&, ty: Ty) -> Variants, Error {
    if self_.variant_cache[ty].present { return self_.variant_cache[ty].value, Error.none; }
    if self_.node(ty).tag != Tag.nominal {
        self_.failure_reason = "constructor of a non-nominal type";
        return Variants {}, Error.unsupported;
    }
    let identity = self_.nominalIdentity(ty);
    let owner .= self_.module(identity.unit);
    if !owner { return Variants {}, Error.unsupported; }
    let ordinal, error = nominalOrdinal(self_, owner, identity);
    if error != Error.none { return Variants {}, error; }
    let constructors = owner.nominalConstructors(ordinal);
    // A hole argument (a type no use determines) leaves holes.
    var holed = false;
    for argument in self_.nominalArguments(ty) { if argument == never { holed = true; } }
    let mark = self_.scratch_len;
    for constructor_id in constructors { self_.pushScratch(owner.constructor(constructor_id).tag); }
    for constructor_id in constructors {
        let constructor = owner.constructor(constructor_id);
        let signature = owner.types.node(constructor.scheme.root);
        var result = constructor.scheme.root;
        if signature.tag == blot_check_types::Tag.function { result = signature.b; }
        var env = Env {};
        match_(self_, owner, result, ty, env);
        var payload = unit;
        if constructor.payload != 0 {
            if holed {
                let lowered, error = lowerHoles(self_, owner, constructor.payload, env);
                if error != Error.none { self_.scratch_len = mark; return Variants {}, error; }
                payload = lowered;
            } else {
                let lowered, error = lower(self_, owner, constructor.payload, env);
                if error != Error.none { self_.scratch_len = mark; return Variants {}, error; }
                payload = lowered;
            }
        }
        self_.pushScratch(payload);
    }
    let count = constructors.len;
    let value = Variants { self_.variant_tags.len as u32, self_.variant_payloads.len as u32, count as u32 };
    self_.variant_tags.append(self_.scratch[mark..mark + count]);
    self_.variant_payloads.append(self_.scratch[mark + count..self_.scratch_len]);
    self_.scratch_len = mark;
    self_.variant_cache[ty] = VariantSlot { true, value };
    return value, Error.none;
}
fn nominalOrdinal(self_: Types&, owner: const Module&, identity: blot_check_types::NominalIdentity) -> u32, Error {
    let key = key64(identity.unit, identity.decl);
    let hit, cached = self_.nominal_positions.get(key);
    if cached { return hit, Error.none; }
    for nominal, ordinal in owner.nominals {
        if nominal.identity.unit == identity.unit && nominal.identity.decl == identity.decl {
            self_.nominal_positions.put(key, ordinal as u32);
            return ordinal as u32, Error.none;
        }
    }
    return 0, Error.unsupported;
}

// --- Layouts ------------------------------------------------------------

// Values wider than this many words are passed and held as a pointer to an
// immutable copy (decision 5: one fixed layout per type).
let box_words: i64 = 16;
fn layoutSlice(self_: const Types&, slot: Slot) -> const ValType[:] { return self_.layout_words[slot.start..slot.start + slot.len]; }
fn onePointer(self_: const Types&) -> const ValType[:] { return self_.layout_words[0..1]; }
// Whether values of `ty` are boxed: a pointer to their flat words.
fn boxed(self_: Types&, ty: Ty) -> bool, Error {
    let tag = self_.node(ty).tag;
    if tag != Tag.tuple && tag != Tag.record && tag != Tag.nominal { return false, Error.none; }
    let words, error = flat(self_, ty);
    if error != Error.none { return false, error; }
    return self_.recursive_[ty].present || words.len > box_words, Error.none;
}
// Whether `ty` contains itself and so is always held by pointer.
fn isRecursive(self_: Types&, ty: Ty) -> bool, Error {
    if self_.node(ty).tag != Tag.nominal { return false, Error.none; }
    let words, error = flat(self_, ty);
    if error != Error.none { return false, error; }
    return self_.recursive_[ty].present, Error.none;
}
// The machine words of a boxed value's block: a recursive type's contents,
// otherwise its flat form.
fn blockFlat(self_: Types&, ty: Ty) -> const ValType[:], Error {
    let words, error = flat(self_, ty);
    if error != Error.none { return words, error; }
    if self_.recursive_[ty].present { return layoutSlice(self_, self_.recursive_[ty]), Error.none; }
    return words, Error.none;
}
fn wordBytes(words: const ValType[:]) -> u32 {
    var bytes: u32 = 0;
    for kind in words { if kind == blot_direct_writer::VT_v128 { bytes += 16; } else { bytes += 4; } }
    return bytes;
}
fn blockBytes(self_: Types&, ty: Ty) -> u32, Error {
    let words, error = blockFlat(self_, ty);
    if error != Error.none { return 0, error; }
    return wordBytes(words), Error.none;
}
// A value's register words: its flat words, or one pointer if boxed.
fn layout(self_: Types&, ty: Ty) -> const ValType[:], Error {
    let is_boxed, error = boxed(self_, ty);
    if error != Error.none { return self_.layout_words[0..0], error; }
    if is_boxed { return onePointer(self_), Error.none; }
    return flat(self_, ty);
}
// Bytes of a value's flat form in memory.
fn flatBytes(self_: Types&, ty: Ty) -> u32, Error {
    let words, error = flat(self_, ty);
    if error != Error.none { return 0, error; }
    return wordBytes(words), Error.none;
}
// The flattened machine words of a value of type `ty`: nested values inline,
// as stored in memory.
fn flat(self_: Types&, ty: Ty) -> const ValType[:], Error {
    let slot, error = flatSlot(self_, ty);
    return layoutSlice(self_, slot), error;
}
recursive fn flatSlot(self_: Types&, ty: Ty) -> Slot, Error {
    if self_.layouts[ty].present { return self_.layouts[ty], Error.none; }
    if self_.in_layout[ty] {
        // A nominal reached from its own layout is held by pointer.
        if self_.node(ty).tag == Tag.nominal {
            if !self_.recursive_[ty].present { self_.recursive_[ty] = Slot { true, 0, 0 }; }
            return Slot { true, 0, 1 }, Error.none;
        }
        self_.failure_reason = "recursive data type needs an indirection";
        return Slot {}, Error.unsupported;
    }
    self_.in_layout[ty] = true;
    let mark = self_.scratch_layout_len;
    let error = flatWords(self_, ty);
    self_.in_layout[ty] = false;
    if error != Error.none { self_.scratch_layout_len = mark; return Slot {}, error; }
    let owned = Slot { true, self_.layout_words.len as u32, (self_.scratch_layout_len - mark) as u32 };
    self_.layout_words.append(self_.scratch_layout[mark..self_.scratch_layout_len]);
    self_.scratch_layout_len = mark;
    if self_.recursive_[ty].present {
        self_.recursive_[ty] = owned;
        self_.layouts[ty] = Slot { true, 0, 1 };
        return self_.layouts[ty], Error.none;
    }
    self_.layouts[ty] = owned;
    return owned, Error.none;
}
// Pushes the flat words of `ty` on scratch_layout.
recursive fn flatWords(self_: Types&, ty: Ty) -> Error {
    let i32w = blot_direct_writer::VT_i32;
    let n = self_.node(ty);
    match n.tag {
        unit, never => {},
        boolean, u32_ => { self_.pushScratchLayout(i32w); },
        f32_ => { self_.pushScratchLayout(blot_direct_writer::VT_f32); },
        tuple => {
            for at in 0..(n.b as i64) {
                let item, error = flatSlot(self_, self_.words[n.a + at]);
                if error != Error.none { return error; }
                pushSlot(self_, item);
            }
        },
        record => {
            for index in 0..(n.b as i64) {
                let item, error = flatSlot(self_, self_.recordField(ty, index).ty);
                if error != Error.none { return error; }
                pushSlot(self_, item);
            }
        },
        // A provider is its implementation closure; a state provider is its
        // initial state.
        function, provider => { self_.pushScratchLayout(i32w); self_.pushScratchLayout(i32w); },
        state_provider => {
            let item, error = flatSlot(self_, self_.words[n.a + 2]);
            if error != Error.none { return error; }
            pushSlot(self_, item);
        },
        nominal => {
            let cases, error = variants(self_, ty);
            if error != Error.none { return error; }
            if cases.len == 1 {
                let item, error = flatSlot(self_, self_.variant_payloads[cases.payloads]);
                if error != Error.none { return error; }
                pushSlot(self_, item);
            } else if cases.len > 1 {
                self_.pushScratchLayout(i32w);
                // Each payload's layout slot, kept on the word scratch.
                let mark = self_.scratch_len;
                var width: i64 = 0;
                for at in 0..(cases.len as i64) {
                    let item, error = flatSlot(self_, self_.variant_payloads[cases.payloads + at]);
                    if error != Error.none { self_.scratch_len = mark; return error; }
                    self_.pushScratch(item.start);
                    self_.pushScratch(item.len);
                    width = max(width, item.len as i64);
                }
                for position in 0..width {
                    var all_f32 = true;
                    var any_v128 = false;
                    for at in 0..(cases.len as i64) {
                        let start = self_.scratch[mark + at * 2];
                        let len = self_.scratch[mark + at * 2 + 1];
                        if position < len {
                            let kind = self_.layout_words[start + position];
                            if kind != blot_direct_writer::VT_f32 { all_f32 = false; }
                            if kind == blot_direct_writer::VT_v128 { any_v128 = true; }
                        }
                    }
                    if any_v128 {
                        self_.scratch_len = mark;
                        self_.failure_reason = "SIMD payload in a sum type";
                        return Error.unsupported;
                    }
                    if all_f32 { self_.pushScratchLayout(blot_direct_writer::VT_f32); } else { self_.pushScratchLayout(i32w); }
                }
                self_.scratch_len = mark;
            }
        },
        // Owner handles: (slot, generation); views add (start, length),
        // element references and links add an index.
        array, grow, resize => { self_.pushScratchLayout(i32w); self_.pushScratchLayout(i32w); },
        view => { for at in 0..4 { self_.pushScratchLayout(i32w); } },
        ref, link => { for at in 0..3 { self_.pushScratchLayout(i32w); } },
        cell => { self_.pushScratchLayout(i32w); },
    }
    return Error.none;
}
fn pushSlot(self_: Types&, slot: Slot) {
    for at in 0..(slot.len as i64) { self_.pushScratchLayout(self_.layout_words[slot.start + at]); }
}

fn isContainer(tag: Tag) -> bool {
    match tag {
        array, grow, resize, ref, view, link => { return true; },
        _ => { return false; },
    }
}
