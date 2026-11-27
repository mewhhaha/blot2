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
let u8_: Ty = 4;
let i32_: Ty = 5;
let u64_: Ty = 6;
let i64_: Ty = 7;
let f64_: Ty = 8;
let never: Ty = 9;
// The concrete IDs follow the checked primitive IDs without the absent slot.
fn lowerBuiltin(ty: u32) -> Ty { return ty - blot_check_types::unit; }
type Module = blot_check_core::Module;
type ValType = blot_direct_writer::ValType;
type TId = blot_check_types::Id;
type TTag = blot_check_types::Tag;
type Text = const u8[:];
type U64Map = blot_direct_map::U64Map;

// Zig's `A.Error || error{Unsupported}`, and emit.zig's Diverged. Allocation
// failure is not an error value here.
enum Error { none, unsupported, diverged }

enum Tag { unit, boolean, u32_, f32_, u8_, i32_, u64_, i64_, f64_, never, tuple, record, nominal, function, array, packed, seq, ref, view, link, provider, state_provider, cell }
fn tagCode(tag: Tag) -> u32 {
    match tag {
        unit => { return 0; }, boolean => { return 1; }, u32_ => { return 2; }, f32_ => { return 3; }, never => { return 4; },
        u8_ => { return 18; },
        i32_ => { return 19; },
        u64_ => { return 20; },
        i64_ => { return 21; },
        f64_ => { return 22; },
        tuple => { return 5; }, record => { return 6; }, nominal => { return 7; }, function => { return 8; }, array => { return 9; },
        packed => { return 23; },
        seq => { return 24; },
        ref => { return 12; },
        view => { return 13; }, link => { return 14; }, provider => { return 15; }, state_provider => { return 16; }, cell => { return 17; },
    }
}
// The Zig spelling of each tag, for diagnostics.
fn tagName(tag: Tag) -> Text {
    match tag {
        unit => { return "unit"; }, boolean => { return "boolean"; }, u32_ => { return "u32"; }, f32_ => { return "f32"; }, never => { return "never"; },
        u8_ => { return "u8"; },
        i32_ => { return "i32"; },
        u64_ => { return "u64"; },
        i64_ => { return "i64"; },
        f64_ => { return "f64"; },
        tuple => { return "tuple"; }, record => { return "record"; }, nominal => { return "nominal"; }, function => { return "function"; }, array => { return "array"; },
        packed => { return "packed"; },
        seq => { return "seq"; },
        ref => { return "ref"; },
        view => { return "view"; }, link => { return "link"; }, provider => { return "provider"; }, state_provider => { return "state_provider"; }, cell => { return "cell"; },
    }
}
// The Zig spelling of a Core type tag, for `fail(m, ty, @tagName(n.tag))`.
fn coreTypeTagName(tag: TTag) -> Text {
    match tag {
        absent => { return "absent"; }, unit => { return "unit"; }, boolean => { return "boolean"; }, unsigned32 => { return "u32"; }, floating32 => { return "f32"; },
        unsigned8 => { return "u8"; },
        signed32 => { return "i32"; },
        unsigned64 => { return "u64"; },
        signed64 => { return "i64"; },
        floating64 => { return "f64"; },
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
    // Cached register layout (one pointer if boxed/recursive, else flat layout).
    reg_layouts: Slot[>..] = [],
    // 0 = unknown, 1 = unboxed, 2 = boxed.
    boxed_vals: u8[>..] = [],
    // Cached flat byte width (0xffffffff = uncomputed).
    flat_bytes_vals: u32[>..] = [],
    // Cached memory alignment (0 = uncomputed, 1/2/4).
    flat_align_vals: u8[>..] = [],
    // Cached plain-memory flag (0 = uncomputed, 1 = packed/reordered/sub-word, 2 = plain sequential register words).
    plain_mem_vals: u8[>..] = [],
    // Cached block byte width (0xffffffff = uncomputed; differs from flat_bytes_vals for recursive nominals).
    block_bytes_vals: u32[>..] = [],
    // Cached memory-holding flag for layout decisions (0 = unknown, 1 = false, 2 = true).
    holds_mem_vals: u8[>..] = [],
    in_holds_mem: bool[>..] = [],
    in_mem_layout: bool[>..] = [],
    // Bitmask of outlined cold variants (< 64) for non-recursive multi-constructor nominals.
    outlined_mask: u64[>..] = [],
    // 0 = uncomputed, 1 = computed (tagged), 2 = computed (2-variant nullable-pointer niche).
    outlined_computed: u8[>..] = [],
    // For outlined_computed == 2: variant index (0 or 1) of the 0-byte null constructor.
    niche_null_idx: u8[>..] = [],
    // Cached record field / tuple item byte offsets and register word offsets.
    field_byte_offs_slot: Slot[>..] = [],
    field_byte_offs: u32[>..] = [],
    field_word_offs_slot: Slot[>..] = [],
    field_word_offs: u32[>..] = [],
    // Direct `(record_ty, field_name) -> position` index for records with >= 12 fields.
    record_field_index: U64Map = U64Map {},
    variant_tags: u32[>..] = [],
    variant_payloads: Ty[>..] = [],
    variant_cache: VariantSlot[>..] = [],
    // Lowered closed Core types; open ones depend on an environment.
    closed_base: u32[>..] = [],
    closed_len: u32[>..] = [],
    closed_vals: u32[>..] = [],
    // Per-unit closed/no-vars marker for matchInner/refine: 0 = unknown, 2 = proven no variables.
    no_vars_vals: u8[>..] = [],
    field_id_base: u32[>..] = [],
    field_id_len: u32[>..] = [],
    field_ids: u32[>..] = [],
    // Direct-mapped cache for fieldNameOf: key64(unit, symbol) -> field_id.
    fn_cache_keys: u64[256] = [0; 256],
    fn_cache_vals: u32[256] = [0; 256],
    nominal_positions: U64Map = U64Map {},
    in_layout: bool[>..] = [],
    // Nominal types that contain themselves: always one pointer to an
    // immutable block, even inside other values; the slot is the block.
    recursive_: Slot[>..] = [],
    // Max leaf depth (0..65) for concrete types, or 255 if any descendant is `never`.
    concrete_depth: u8[>..] = [],
    // The Core type that last failed to lower, for diagnostics.
    has_failure: bool = false,
    failure: VarKey = VarKey {},
    holes: bool = false,
    // What an unbound variable lowers to while `holes` is set.
    hole_fill: Ty = never,
    failure_reason: Text = "",
    env_nodes: EnvNode[>..] = [],
    // Scratch shared by the recursive walks; grows only, top tracked by *_len.
    scratch: u32[>..] = [],
    scratch_len: i64 = 0,
    scratch_fields: Field[>..] = [],
    scratch_fields_len: i64 = 0,
    scratch_layout: ValType[>..] = [],
    scratch_layout_len: i64 = 0,
    has_seq_type: bool = false,
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
fn isNoVars(self_: const Types&, unit_id: u32, ty: TId) -> bool {
    let idx = (self_.closed_base[unit_id - 1] as i64) + (ty as i64);
    return self_.closed_vals[idx] != 0xffffffff || self_.no_vars_vals[idx] == 2;
}

let fill_ffffffff: u32[256] = [0xffffffff; 256];
let fill_zeros_u8: u8[256] = [0; 256];
fn growFill(buf: u32[>..]&, count: i64) {
    var rem = count;
    while rem >= 256 { buf.append(fill_ffffffff[..]); rem -= 256; }
    if rem > 0 { buf.append(fill_ffffffff[..rem]); }
}
fn growZerosU8(buf: u8[>..]&, count: i64) {
    var rem = count;
    while rem >= 256 { buf.append(fill_zeros_u8[..]); rem -= 256; }
    if rem > 0 { buf.append(fill_zeros_u8[..rem]); }
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
    if self_.closed_vals.len < total_types { growFill(self_.closed_vals, total_types - self_.closed_vals.len); }
    if self_.no_vars_vals.len < total_types { growZerosU8(self_.no_vars_vals, total_types - self_.no_vars_vals.len); }
    if self_.field_ids.len < total_fields { growFill(self_.field_ids, total_fields - self_.field_ids.len); }
}

fn resetClosedUnit(self_: Types&, unit_id: u32) {
    let idx = (unit_id - 1) as i64;
    let need = self_.units[idx].types.nodes.len;
    if need <= (self_.closed_len[idx] as i64) {
        let base = self_.closed_base[idx] as i64;
        for at in base..base + need {
            self_.closed_vals[at] = 0xffffffff;
            self_.no_vars_vals[at] = 0;
        }
    } else {
        let base = self_.closed_vals.len as u32;
        self_.closed_base[idx] = base;
        self_.closed_len[idx] = need as u32;
        growFill(self_.closed_vals, need);
        growZerosU8(self_.no_vars_vals, need);
    }
    let fneed = self_.units[idx].field_names.len;
    if fneed <= (self_.field_id_len[idx] as i64) {
        let fbase = self_.field_id_base[idx] as i64;
        for at in fbase..fbase + fneed { self_.field_ids[at] = 0xffffffff; }
    } else {
        let fbase = self_.field_ids.len as u32;
        self_.field_id_base[idx] = fbase;
        self_.field_id_len[idx] = fneed as u32;
        growFill(self_.field_ids, fneed);
    }
    for ci in 0..256 { self_.fn_cache_keys[ci] = 0; }
}

fn resetClosed(self_: Types&) {
    for idx in 0..self_.units.len { resetClosedUnit(self_, (idx + 1) as u32); }
}

fn init(self_: Types&) {
    // Pre-seed canonical layout patterns:
    // [0..1] = [VT_i32] (boxed ptr, boolean, u32_, cell)
    // [1..2] = [VT_f32] (f32_)
    // [2..6] = [VT_i32 x 4] ([2..4] fn/provider/array, [2..5] ref/link, [2..6] view)
    self_.layout_words.push(blot_direct_writer::VT_i32);
    self_.layout_words.push(blot_direct_writer::VT_f32);
    self_.layout_words.push(blot_direct_writer::VT_i32);
    self_.layout_words.push(blot_direct_writer::VT_i32);
    self_.layout_words.push(blot_direct_writer::VT_i32);
    self_.layout_words.push(blot_direct_writer::VT_i32);
    // [6..7] = [VT_i64], [7..8] = [VT_f64]
    self_.layout_words.push(blot_direct_writer::VT_i64);
    self_.layout_words.push(blot_direct_writer::VT_f64);
    // Environment node 0 ends every list.
    self_.env_nodes.push(EnvNode { 0, 0, 0, 0 });
    initUnitTables(self_);
    for tag in [Tag.unit, Tag.boolean, Tag.u32_, Tag.f32_, Tag.u8_, Tag.i32_, Tag.u64_, Tag.i64_, Tag.f64_, Tag.never] {
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
        array, packed, seq, ref, view, link, provider, cell => { arity = 1; },
        state_provider => { arity = 3; },
        _ => {},
    }
    if tag == Tag.seq { self_.has_seq_type = true; }
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
        unit, boolean, u32_, f32_, u8_, i32_, u64_, i64_, f64_, never => {},
        tuple, state_provider => { value = Node { tag, start, payload.len as u32 }; },
        record => { value = Node { tag, start, (payload.len / 2) as u32 }; },
        nominal => { value = Node { tag, start, (payload.len - 2) as u32 }; },
        function => { value = Node { tag, first, payload[payload.len - 1] }; },
        array, packed, seq, ref, view, link, provider, cell => { value = Node { tag, first, 0 }; },
    }
    var cdepth: u8 = 0;
    match tag {
        never => { cdepth = 255; },
        unit, boolean, u32_, f32_, u8_, i32_, u64_, i64_, f64_ => { cdepth = 0; },
        function => {
            var md = self_.concrete_depth[payload[0]];
            let d1 = self_.concrete_depth[payload[1]];
            if d1 > md { md = d1; }
            if md == 255 { cdepth = 255; } else if md >= 65 { cdepth = 65; } else { cdepth = md + 1; }
        },
        array, packed, seq, ref, view, link, provider, cell => {
            let md = self_.concrete_depth[payload[0]];
            if md == 255 { cdepth = 255; } else if md >= 65 { cdepth = 65; } else { cdepth = md + 1; }
        },
        tuple, state_provider => {
            if payload.len > 0 {
                var md: u8 = 0;
                for child in payload {
                    let d = self_.concrete_depth[child];
                    if d > md { md = d; }
                }
                if md == 255 { cdepth = 255; } else if md >= 65 { cdepth = 65; } else { cdepth = md + 1; }
            }
        },
        record => {
            if payload.len > 0 {
                var md: u8 = 0;
                for idx in 0..(payload.len / 2) {
                    let d = self_.concrete_depth[payload[idx * 2 + 1]];
                    if d > md { md = d; }
                }
                if md == 255 { cdepth = 255; } else if md >= 65 { cdepth = 65; } else { cdepth = md + 1; }
            }
        },
        nominal => {
            if payload.len > 2 {
                var md: u8 = 0;
                for idx in 2..payload.len {
                    let d = self_.concrete_depth[payload[idx]];
                    if d > md { md = d; }
                }
                if md == 255 { cdepth = 255; } else if md >= 65 { cdepth = 65; } else { cdepth = md + 1; }
            }
        },
    }
    var init_flat = Slot {};
    var init_reg = Slot {};
    var init_boxed: u8 = 0;
    var init_fbytes: u32 = 0xffffffff;
    var init_falign: u8 = 0;
    var init_plain: u8 = 0;
    var init_bbytes: u32 = 0xffffffff;
    var init_hmem: u8 = 0;
    match tag {
        unit, never => { init_flat = Slot { true, 0, 0 }; init_reg = init_flat; init_boxed = 1; init_fbytes = 0; init_falign = 1; init_plain = 2; init_bbytes = 0; init_hmem = 1; },
        boolean, u8_ => { init_flat = Slot { true, 0, 1 }; init_reg = init_flat; init_boxed = 1; init_fbytes = 1; init_falign = 1; init_plain = 1; init_bbytes = 1; init_hmem = 1; },
        u32_, i32_ => { init_flat = Slot { true, 0, 1 }; init_reg = init_flat; init_boxed = 1; init_fbytes = 4; init_falign = 4; init_plain = 2; init_bbytes = 4; init_hmem = 1; },
        cell => { init_flat = Slot { true, 0, 1 }; init_reg = init_flat; init_boxed = 1; init_fbytes = 4; init_falign = 4; init_plain = 2; init_bbytes = 4; init_hmem = 2; },
        u64_, i64_ => { init_flat = Slot { true, 6, 1 }; init_reg = init_flat; init_boxed = 1; init_fbytes = 8; init_falign = 4; init_plain = 2; init_bbytes = 8; init_hmem = 1; },
        f64_ => { init_flat = Slot { true, 7, 1 }; init_reg = init_flat; init_boxed = 1; init_fbytes = 8; init_falign = 4; init_plain = 2; init_bbytes = 8; init_hmem = 1; },
        f32_ => { init_flat = Slot { true, 1, 1 }; init_reg = init_flat; init_boxed = 1; init_fbytes = 4; init_falign = 4; init_plain = 2; init_bbytes = 4; init_hmem = 1; },
        function, provider, array, packed, seq => { init_flat = Slot { true, 2, 2 }; init_reg = init_flat; init_boxed = 1; init_fbytes = 8; init_falign = 4; init_plain = 2; init_bbytes = 8; init_hmem = 2; },
        ref, link => { init_flat = Slot { true, 2, 3 }; init_reg = init_flat; init_boxed = 1; init_fbytes = 12; init_falign = 4; init_plain = 2; init_bbytes = 12; init_hmem = 2; },
        view => { init_flat = Slot { true, 2, 4 }; init_reg = init_flat; init_boxed = 1; init_fbytes = 16; init_falign = 4; init_plain = 2; init_bbytes = 16; init_hmem = 2; },
        _ => {},
    }
    let id = self_.nodes.len as Ty;
    let span = Span { self_.encodings.len as u32, (payload.len + 1) as u32 };
    self_.encodings.push(code);
    self_.encodings.append(payload);
    self_.nodes.push(value);
    self_.keys.push(span);
    self_.layouts.push(init_flat);
    self_.reg_layouts.push(init_reg);
    self_.boxed_vals.push(init_boxed);
    self_.flat_bytes_vals.push(init_fbytes);
    self_.flat_align_vals.push(init_falign);
    self_.plain_mem_vals.push(init_plain);
    self_.block_bytes_vals.push(init_bbytes);
    self_.holds_mem_vals.push(init_hmem);
    self_.in_holds_mem.push(false);
    self_.in_mem_layout.push(false);
    self_.outlined_mask.push(0);
    self_.outlined_computed.push(0);
    self_.niche_null_idx.push(0);
    self_.field_byte_offs_slot.push(Slot {});
    self_.field_word_offs_slot.push(Slot {});
    self_.variant_cache.push(VariantSlot {});
    self_.in_layout.push(false);
    self_.recursive_.push(Slot {});
    self_.concrete_depth.push(cdepth);
    self_.index_next.push(head);
    self_.index.put(hashed, id + 1);
    if tag == Tag.record && payload.len >= 24 {
        for idx in 0..(payload.len / 2) {
            self_.record_field_index.put(key64(id, payload[idx * 2]), idx as u32);
        }
    }
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
    let fkey = key64(m.unit, symbol);
    let fslot = (((m.unit * 2654435761) ^ (symbol * 2246822507)) & 255) as i64;
    if self_.fn_cache_keys[fslot] == fkey { return self_.fn_cache_vals[fslot], true; }
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
            if cached != 0xffffffff {
                self_.fn_cache_keys[fslot] = fkey;
                self_.fn_cache_vals[fslot] = cached;
                return cached, true;
            }
            let text = m.name(value.spelling);
            if intern_missing {
                let id = fieldName(self_, text);
                self_.field_ids[slot] = id;
                self_.fn_cache_keys[fslot] = fkey;
                self_.fn_cache_vals[fslot] = id;
                return id, true;
            }
            let id, known = findName(self_, text);
            if known {
                self_.field_ids[slot] = id;
                self_.fn_cache_keys[fslot] = fkey;
                self_.fn_cache_vals[fslot] = id;
                return id, true;
            }
            return 0, false;
        }
    }
    return 0, false;
}
fn findField(self_: const Types&, ty: Ty, name: u32) -> i64 {
    let n = self_.node(ty);
    if n.tag != Tag.record { return -1; }
    if n.b >= 12 {
        let pos, ok = self_.record_field_index.get(key64(ty, name));
        if ok { return pos as i64; }
        return -1;
    }
    var at = n.a as i64;
    for index in 0..(n.b as i64) {
        if self_.words[at] == name { return index; }
        at += 2;
    }
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
    if ty >= blot_check_types::unit && ty <= blot_check_types::never { return lowerBuiltin(ty), Error.none; }
    if depth > 256 { return 0, fail(self_, m, ty, "type nesting exceeds 256"); }
    let closed_idx = (self_.closed_base[m.unit - 1] as i64) + (ty as i64);
    let hit = self_.closed_vals[closed_idx];
    if hit != 0xffffffff { return hit, Error.none; }
    var child_open = false;
    let n = m.types.node(ty);
    var result: Ty = 0;
    match n.tag {
        variable, bound, rigid => {
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
                    let made, error = intern(self_, Tag.array, [element]);
                    if error != Error.none { return 0, error; }
                    result = made;
                } else {
                    if arguments.len != 1 { return 0, fail(self_, m, ty, "storage type arity"); }
                    let element, error = lowerInner(self_, m, arguments[0], env, child_open, depth + 1);
                    if error != Error.none { return 0, error; }
                    var tag = Tag.link;
                    if kind.value == blot_check_storage_types::ref { tag = Tag.ref; }
                    else if kind.value == blot_check_storage_types::view { tag = Tag.view; }
                    else if kind.value == blot_check_storage_types::packed { tag = Tag.packed; }
                    else if kind.value == blot_check_storage_types::seq { tag = Tag.seq; }
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
                        var dummy_match_open = false;
                        matchInner(self_, self_.units[unit_idx], harg_ids[pi], proj_args[pi], match_env, dummy_match_open, 0);
                        var dummy_open = false;
                        let resolved_harg, herr = lowerInner(self_, self_.units[unit_idx], harg_ids[pi], match_env, dummy_open, depth + 1);
                        if herr != Error.none { matches = false; break; }
                        if resolved_harg != proj_args[pi] {
                            matches = false; break;
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
fn match_(self_: Types&, m: const Module&, pattern: TId, actual: Ty, env: Env&) {
    var open = false;
    matchInner(self_, m, pattern, actual, env, open, 0);
}
recursive fn matchInner(self_: Types&, m: const Module&, pattern: TId, actual: Ty, env: Env&, open: bool&, depth: i64) {
    if pattern <= blot_check_types::never { return; }
    if depth > 256 { open = true; return; }
    let cidx = (self_.closed_base[m.unit - 1] as i64) + (pattern as i64);
    if self_.closed_vals[cidx] != 0xffffffff || self_.no_vars_vals[cidx] == 2 { return; }
    var sub_open = false;
    let n = m.types.node(pattern);
    let have = self_.node(actual);
    match n.tag {
        variable, bound, rigid => {
            sub_open = true;
            if actual != never { envBind(self_, env, m.unit, pattern, actual); }
        },
        usage, forall => { matchInner(self_, m, n.a, actual, env, sub_open, depth + 1); },
        function => {
            if have.tag == Tag.function {
                matchInner(self_, m, n.a, have.a, env, sub_open, depth + 1);
                matchInner(self_, m, n.b, have.b, env, sub_open, depth + 1);
            } else { sub_open = true; }
        },
        product => {
            if have.tag == Tag.tuple && have.b == n.b {
                let children = m.types.list(blot_check_types::List { n.a, n.b });
                for child, at in children { matchInner(self_, m, child, self_.words[have.a + at], env, sub_open, depth + 1); }
            } else { sub_open = true; }
        },
        record => {
            if have.tag == Tag.record {
                for index in 0..(n.b as i64) {
                    let source = m.types.recordField(n, index);
                    let name, known = fieldNameOf(self_, m, source.name, false);
                    if !known { sub_open = true; continue; }
                    let position = self_.findField(actual, name);
                    if position < 0 { sub_open = true; continue; }
                    matchInner(self_, m, source.ty, self_.recordField(actual, position).ty, env, sub_open, depth + 1);
                }
            } else { sub_open = true; }
        },
        nominal => {
            let arguments = m.types.nominalArguments(n);
            let skind = blot_check_storage_types::identity(n.a, n.b);
            if skind.present {
                if skind.value == blot_check_storage_types::shared && arguments.len == 1 {
                    matchInner(self_, m, arguments[0], actual, env, sub_open, depth + 1);
                } else if blot_check_storage_types::isSized(skind.value) && arguments.len == 2 {
                    if isContainer(have.tag) {
                        // Length arg[0] might be a variable or literal; mark conservative if not length literal.
                        let len_node = m.types.node(arguments[0]);
                        if len_node.tag != blot_check_types::Tag.nominal || !blot_check_storage_types::isLengthLiteral(len_node.a, len_node.b) { sub_open = true; }
                        matchInner(self_, m, arguments[1], have.a, env, sub_open, depth + 1);
                    } else { sub_open = true; }
                } else if arguments.len == 1 && isContainer(have.tag) {
                    matchInner(self_, m, arguments[0], have.a, env, sub_open, depth + 1);
                } else { sub_open = true; }
            } else if have.tag == Tag.nominal {
                let identity = self_.nominalIdentity(actual);
                if identity.unit != n.a || identity.decl != n.b || have.b != arguments.len {
                    sub_open = true;
                } else {
                    for argument, at in arguments { matchInner(self_, m, argument, self_.words[have.a + 2 + at], env, sub_open, depth + 1); }
                }
            } else { sub_open = true; }
        },
        array => { if isContainer(have.tag) { matchInner(self_, m, n.a, have.a, env, sub_open, depth + 1); } else { sub_open = true; } },
        provider => { if have.tag == Tag.provider { matchInner(self_, m, n.a, have.a, env, sub_open, depth + 1); } else { sub_open = true; } },
        state_provider => {
            if have.tag == Tag.state_provider {
                // Zig zips three children with the stored list (always three).
                matchInner(self_, m, n.a, self_.words[have.a], env, sub_open, depth + 1);
                matchInner(self_, m, n.b, self_.words[have.a + 1], env, sub_open, depth + 1);
                matchInner(self_, m, n.c, self_.words[have.a + 2], env, sub_open, depth + 1);
            } else { sub_open = true; }
        },
        _ => { sub_open = true; },
    }
    if sub_open { open = true; } else { self_.no_vars_vals[cidx] = 2; }
}

// Whether `ty` has no hole (`never`) anywhere, even under functions and
// containers.
fn concrete(self_: const Types&, ty: Ty, depth: i64) -> bool {
    return (self_.concrete_depth[ty] as i64) <= 64 - depth;
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
    let cached = self_.boxed_vals[ty];
    if cached != 0 { return cached == 2, Error.none; }
    let tag = self_.node(ty).tag;
    if tag != Tag.tuple && tag != Tag.record && tag != Tag.nominal {
        self_.boxed_vals[ty] = 1;
        return false, Error.none;
    }
    let slot, error = flatSlot(self_, ty);
    if error != Error.none { return false, error; }
    let is_b = self_.recursive_[ty].present || (slot.len as i64) > box_words;
    if is_b {
        self_.boxed_vals[ty] = 2;
        self_.reg_layouts[ty] = Slot { true, 0, 1 };
    } else {
        self_.boxed_vals[ty] = 1;
        self_.reg_layouts[ty] = slot;
    }
    return is_b, Error.none;
}
// Whether `ty` contains itself and so is always held by pointer.
fn isRecursive(self_: Types&, ty: Ty) -> bool, Error {
    if self_.node(ty).tag != Tag.nominal { return false, Error.none; }
    let _, error = flatSlot(self_, ty);
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
    for kind in words { bytes += blot_direct_writer::wordBytes(kind); }
    return bytes;
}
fn alignUp(v: u32, a: u32) -> u32 {
    if a <= 1 { return v; }
    return (v + a - 1) & ~(a - 1);
}
// Pure type-level check matching `contentsHoldMemory`: whether values of `ty`
// already hold scope/heap references (arrays, views, refs, links, closures,
// providers, cells, or recursive nominals). Used so cold-variant outlining only
// triggers on sums that already hold memory (preserving zero-leak scope-arena
// rewind for pure-data mutable arrays).
recursive fn tyHoldsMemory(self_: Types&, ty: Ty) -> bool, Error {
    let cached = self_.holds_mem_vals[ty];
    if cached != 0 { return cached == 2, Error.none; }
    if self_.recursive_[ty].present || self_.in_holds_mem[ty] {
        return true, Error.none;
    }
    let n = self_.node(ty);
    var res = false;
    match n.tag {
        unit, boolean, u32_, f32_, u8_, i32_, u64_, i64_, f64_, never => {},
        function, provider, array, packed, seq, ref, view, link, cell => { res = true; },
        state_provider => {
            let h, err = tyHoldsMemory(self_, self_.words[n.a + 2]);
            if err != Error.none { return false, err; }
            res = h;
        },
        tuple => {
            for at in 0..(n.b as i64) {
                let h, err = tyHoldsMemory(self_, self_.words[n.a + at]);
                if err != Error.none { return false, err; }
                if h { res = true; break; }
            }
        },
        record => {
            for idx in 0..(n.b as i64) {
                let h, err = tyHoldsMemory(self_, self_.recordField(ty, idx).ty);
                if err != Error.none { return false, err; }
                if h { res = true; break; }
            }
        },
        nominal => {
            self_.in_holds_mem[ty] = true;
            let cases, cerr = variants(self_, ty);
            if cerr != Error.none { self_.in_holds_mem[ty] = false; return false, cerr; }
            for ci in 0..(cases.len as i64) {
                let h, err = tyHoldsMemory(self_, self_.variant_payloads[cases.payloads + ci]);
                if err != Error.none { self_.in_holds_mem[ty] = false; return false, err; }
                if h { res = true; break; }
            }
            self_.in_holds_mem[ty] = false;
        },
    }
    self_.holds_mem_vals[ty] = if res { 2 } else { 1 };
    return res, Error.none;
}
fn variantOutlinedBit(self_: const Types&, ty: Ty, ci: i64) -> bool {
    return ci >= 0 && ci < 64 && ((self_.outlined_mask[ty] >> (ci as u64)) & 1) != 0;
}
fn variantOutlined(self_: Types&, ty: Ty, ci: i64) -> bool, Error {
    if self_.node(ty).tag != Tag.nominal || ci < 0 || ci >= 64 { return false, Error.none; }
    let _, err = flatSlot(self_, ty);
    if err != Error.none { return false, err; }
    return variantOutlinedBit(self_, ty, ci), Error.none;
}
fn hasOutlinedVariants(self_: Types&, ty: Ty) -> bool, Error {
    if self_.node(ty).tag != Tag.nominal { return false, Error.none; }
    let _, err = flatSlot(self_, ty);
    if err != Error.none { return false, err; }
    return self_.outlined_mask[ty] != 0, Error.none;
}
fn nullableNiche(self_: Types&, ty: Ty) -> bool, u32, u32, Ty, Error {
    if self_.node(ty).tag != Tag.nominal { return false, 0, 0, 0, Error.none; }
    let _, err = flatSlot(self_, ty);
    if err != Error.none { return false, 0, 0, 0, err; }
    if self_.outlined_computed[ty] != 2 { return false, 0, 0, 0, Error.none; }
    let cases = self_.variant_cache[ty].value;
    let null_i = self_.niche_null_idx[ty] as i64;
    let some_i = 1 - null_i;
    return true, self_.variant_tags[cases.tags + null_i], self_.variant_tags[cases.tags + some_i], self_.variant_payloads[cases.payloads + some_i], Error.none;
}
// Computes cold-variant outlining and 2-variant nullable-pointer niche for
// non-recursive multi-constructor nominal `ty` after all variant `flatSlot`s
// have finished.
fn computeSumOutlining(self_: Types&, ty: Ty, cases: Variants) -> Error {
    if self_.outlined_computed[ty] != 0 { return Error.none; }
    if self_.recursive_[ty].present || cases.len <= 1 || cases.len > 64 {
        self_.outlined_mask[ty] = 0;
        self_.outlined_computed[ty] = 1;
        return Error.none;
    }
    let holds, herr = tyHoldsMemory(self_, ty);
    if herr != Error.none { return herr; }
    if !holds {
        self_.outlined_mask[ty] = 0;
        self_.outlined_computed[ty] = 1;
        return Error.none;
    }
    var min_psize: u32 = 0xffffffff;
    var max_psize: u32 = 0;
    for ci in 0..(cases.len as i64) {
        let pty = self_.variant_payloads[cases.payloads + ci];
        let cerr = computeMemLayout(self_, pty);
        if cerr != Error.none { return cerr; }
        let psz = self_.flat_bytes_vals[pty];
        if psz < min_psize { min_psize = psz; }
        if psz > max_psize { max_psize = psz; }
    }
    if !(max_psize > 24 && (min_psize == 0 || max_psize >= 2 * min_psize + 16)) {
        self_.outlined_mask[ty] = 0;
        self_.outlined_computed[ty] = 1;
        return Error.none;
    }
    let cap: u32 = if min_psize > 24 { min_psize } else { 24 };
    var mask: u64 = 0;
    for ci in 0..(cases.len as i64) {
        let pty = self_.variant_payloads[cases.payloads + ci];
        let psz = self_.flat_bytes_vals[pty];
        if psz > cap && !self_.recursive_[pty].present {
            mask |= (1 as u64) << (ci as u64);
        }
    }
    self_.outlined_mask[ty] = mask;
    if cases.len == 2 {
        let p0 = self_.variant_payloads[cases.payloads];
        let p1 = self_.variant_payloads[cases.payloads + 1];
        if self_.flat_bytes_vals[p0] == 0 && ((mask & 2) != 0) {
            self_.outlined_computed[ty] = 2;
            self_.niche_null_idx[ty] = 0;
            return Error.none;
        }
        if self_.flat_bytes_vals[p1] == 0 && ((mask & 1) != 0) {
            self_.outlined_computed[ty] = 2;
            self_.niche_null_idx[ty] = 1;
            return Error.none;
        }
    }
    self_.outlined_computed[ty] = 1;
    return Error.none;
}
// Computes and caches byte size, alignment (1/2/4), plain-memory flag, block bytes,
// and alignment-sorted field/item byte offsets for `ty`.
recursive fn computeMemLayout(self_: Types&, ty: Ty) -> Error {
    if self_.flat_bytes_vals[ty] != 0xffffffff && self_.block_bytes_vals[ty] != 0xffffffff {
        return Error.none;
    }
    if self_.in_mem_layout[ty] {
        return Error.none;
    }
    let _, ferr = flatSlot(self_, ty);
    if ferr != Error.none { return ferr; }
    if self_.flat_bytes_vals[ty] != 0xffffffff && self_.block_bytes_vals[ty] != 0xffffffff {
        return Error.none;
    }
    let n = self_.node(ty);
    let is_rec = n.tag == Tag.nominal && self_.recursive_[ty].present;
    if is_rec {
        self_.flat_bytes_vals[ty] = 4;
        self_.flat_align_vals[ty] = 4;
        self_.plain_mem_vals[ty] = 2;
        if self_.in_layout[ty] { return Error.none; }
    }
    self_.in_mem_layout[ty] = true;
    let err = computeMemLayoutBody(self_, ty, n, is_rec);
    self_.in_mem_layout[ty] = false;
    return err;
}
recursive fn computeMemLayoutBody(self_: Types&, ty: Ty, n: Node, is_rec: bool) -> Error {
    match n.tag {
        state_provider => {
            let inner = self_.words[n.a + 2];
            let err = computeMemLayout(self_, inner);
            if err != Error.none { return err; }
            self_.flat_bytes_vals[ty] = self_.flat_bytes_vals[inner];
            self_.flat_align_vals[ty] = self_.flat_align_vals[inner];
            self_.plain_mem_vals[ty] = self_.plain_mem_vals[inner];
            self_.block_bytes_vals[ty] = self_.block_bytes_vals[inner];
            return Error.none;
        },
        record, tuple => {
            let count = n.b as i64;
            for i in 0..count {
                let fty = if n.tag == Tag.record {
                    self_.words[(n.a as i64) + i * 2 + 1]
                } else {
                    self_.words[(n.a as i64) + i]
                };
                let err = computeMemLayout(self_, fty);
                if err != Error.none { return err; }
            }
            let start = self_.field_byte_offs.len;
            for i in 0..count { self_.field_byte_offs.push(0); }
            var all_plain = true;
            var off: u32 = 0;
            var max_align: u32 = 1;
            for tier in [4 as u8, 2 as u8, 1 as u8] {
                for i in 0..count {
                    let fty = if n.tag == Tag.record {
                        self_.words[(n.a as i64) + i * 2 + 1]
                    } else {
                        self_.words[(n.a as i64) + i]
                    };
                    let falign = self_.flat_align_vals[fty];
                    if falign != tier { continue; }
                    if self_.plain_mem_vals[fty] != 2 { all_plain = false; }
                    let fsize = self_.flat_bytes_vals[fty];
                    if fsize == 0 {
                        self_.field_byte_offs[start + i] = off;
                        continue;
                    }
                    let a = tier as u32;
                    if a > max_align { max_align = a; }
                    off = alignUp(off, a);
                    self_.field_byte_offs[start + i] = off;
                    off += fsize;
                }
            }
            let total = alignUp(off, max_align);
            self_.field_byte_offs_slot[ty] = Slot { true, start as u32, count as u32 };
            self_.flat_bytes_vals[ty] = total;
            self_.flat_align_vals[ty] = max_align as u8;
            self_.plain_mem_vals[ty] = if all_plain { 2 } else { 1 };
            self_.block_bytes_vals[ty] = total;
            return Error.none;
        },
        nominal => {
            let cases, cerr = variants(self_, ty);
            if cerr != Error.none { return cerr; }
            if cases.len == 0 {
                self_.block_bytes_vals[ty] = 0;
                if !is_rec {
                    self_.flat_bytes_vals[ty] = 0;
                    self_.flat_align_vals[ty] = 1;
                    self_.plain_mem_vals[ty] = 2;
                }
                return Error.none;
            }
            if cases.len == 1 {
                let pty = self_.variant_payloads[cases.payloads];
                let err = computeMemLayout(self_, pty);
                if err != Error.none { return err; }
                self_.block_bytes_vals[ty] = self_.flat_bytes_vals[pty];
                if !is_rec {
                    self_.flat_bytes_vals[ty] = self_.flat_bytes_vals[pty];
                    self_.flat_align_vals[ty] = self_.flat_align_vals[pty];
                    self_.plain_mem_vals[ty] = self_.plain_mem_vals[pty];
                }
                return Error.none;
            }
            if !is_rec && self_.outlined_computed[ty] == 2 {
                self_.block_bytes_vals[ty] = 4;
                self_.flat_bytes_vals[ty] = 4;
                self_.flat_align_vals[ty] = 4;
                self_.plain_mem_vals[ty] = 2;
                return Error.none;
            }
            var max_tag: u32 = 0;
            var max_psize: u32 = 0;
            var max_palign: u32 = 1;
            var all_pplain = true;
            for ci in 0..(cases.len as i64) {
                let ctag = self_.variant_tags[cases.tags + ci];
                if ctag > max_tag { max_tag = ctag; }
                let pty = self_.variant_payloads[cases.payloads + ci];
                let err = computeMemLayout(self_, pty);
                if err != Error.none { return err; }
                let is_out = !is_rec && variantOutlinedBit(self_, ty, ci);
                let psz = if is_out { 4 } else { self_.flat_bytes_vals[pty] };
                let pal = if is_out { 4 } else { self_.flat_align_vals[pty] as u32 };
                if psz > max_psize { max_psize = psz; }
                if psz > 0 && pal > max_palign { max_palign = pal; }
                if !is_out && self_.plain_mem_vals[pty] != 2 { all_pplain = false; }
            }
            var tag_bytes: u32 = 4;
            var sum_align: u32 = 4;
            var sum_size: u32 = 0;
            if max_psize == 0 {
                if max_tag <= 0xff { tag_bytes = 1; }
                else if max_tag <= 0xffff { tag_bytes = 2; }
                sum_align = tag_bytes;
                sum_size = tag_bytes;
            } else if max_palign == 1 {
                if max_tag <= 0xff { tag_bytes = 1; }
                else if max_tag <= 0xffff { tag_bytes = 2; }
                sum_align = tag_bytes;
                sum_size = alignUp(tag_bytes + max_psize, sum_align);
            } else if max_palign == 2 {
                if max_tag <= 0xffff { tag_bytes = 2; }
                sum_align = tag_bytes;
                sum_size = alignUp(tag_bytes + max_psize, sum_align);
            } else {
                tag_bytes = 4;
                sum_align = 4;
                sum_size = alignUp(4 + max_psize, 4);
            }
            let bwords, bwerr = blockFlat(self_, ty);
            if bwerr != Error.none { return bwerr; }
            let sum_plain: u8 = if tag_bytes == 4 && all_pplain && wordBytes(bwords) == sum_size { 2 } else { 1 };
            self_.block_bytes_vals[ty] = sum_size;
            if !is_rec {
                self_.flat_bytes_vals[ty] = sum_size;
                self_.flat_align_vals[ty] = sum_align as u8;
                self_.plain_mem_vals[ty] = sum_plain;
            }
            return Error.none;
        },
        _ => {
            let words, error = flat(self_, ty);
            if error != Error.none { return error; }
            let bytes = wordBytes(words);
            self_.flat_bytes_vals[ty] = bytes;
            self_.flat_align_vals[ty] = if bytes == 0 { 1 } else { 4 };
            self_.plain_mem_vals[ty] = 2;
            self_.block_bytes_vals[ty] = bytes;
            return Error.none;
        },
    }
}
fn blockBytes(self_: Types&, ty: Ty) -> u32, Error {
    let err = computeMemLayout(self_, ty);
    if err != Error.none { return 0, err; }
    return self_.block_bytes_vals[ty], Error.none;
}
// A value's register words: its flat words, or one pointer if boxed.
fn layout(self_: Types&, ty: Ty) -> const ValType[:], Error {
    let rslot = self_.reg_layouts[ty];
    if rslot.present { return layoutSlice(self_, rslot), Error.none; }
    let is_boxed, error = boxed(self_, ty);
    if error != Error.none { return self_.layout_words[0..0], error; }
    if is_boxed { return onePointer(self_), Error.none; }
    let fslot, ferr = flatSlot(self_, ty);
    if ferr != Error.none { return self_.layout_words[0..0], ferr; }
    self_.reg_layouts[ty] = fslot;
    return layoutSlice(self_, fslot), Error.none;
}
// Bytes of a value's flat form in memory.
fn flatBytes(self_: Types&, ty: Ty) -> u32, Error {
    let cached = self_.flat_bytes_vals[ty];
    if cached != 0xffffffff { return cached, Error.none; }
    let err = computeMemLayout(self_, ty);
    if err != Error.none { return 0, err; }
    return self_.flat_bytes_vals[ty], Error.none;
}
fn flatAlign(self_: Types&, ty: Ty) -> u32, Error {
    if self_.flat_align_vals[ty] != 0 { return self_.flat_align_vals[ty] as u32, Error.none; }
    let err = computeMemLayout(self_, ty);
    if err != Error.none { return 1, err; }
    return self_.flat_align_vals[ty] as u32, Error.none;
}
fn isPlainMem(self_: Types&, ty: Ty) -> bool, Error {
    if self_.plain_mem_vals[ty] != 0 { return self_.plain_mem_vals[ty] == 2, Error.none; }
    let err = computeMemLayout(self_, ty);
    if err != Error.none { return false, err; }
    return self_.plain_mem_vals[ty] == 2, Error.none;
}
// Tag byte width (1/2/4) and payload byte offset for a multi-constructor nominal.
fn sumTagInfo(self_: Types&, ty: Ty) -> u32, u32, Error {
    let err = computeMemLayout(self_, ty);
    if err != Error.none { return 4, 4, err; }
    let cases, cerr = variants(self_, ty);
    if cerr != Error.none { return 4, 4, cerr; }
    if cases.len <= 1 { return 0, 0, Error.none; }
    if self_.outlined_computed[ty] == 2 { return 4, 0, Error.none; }
    var max_tag: u32 = 0;
    var max_psize: u32 = 0;
    var max_palign: u32 = 1;
    for ci in 0..(cases.len as i64) {
        let ctag = self_.variant_tags[cases.tags + ci];
        if ctag > max_tag { max_tag = ctag; }
        let pty = self_.variant_payloads[cases.payloads + ci];
        let is_out = !self_.recursive_[ty].present && variantOutlinedBit(self_, ty, ci);
        let psz = if is_out { 4 } else { self_.flat_bytes_vals[pty] };
        let pal = if is_out { 4 } else { self_.flat_align_vals[pty] as u32 };
        if psz > max_psize { max_psize = psz; }
        if psz > 0 && pal > max_palign { max_palign = pal; }
    }
    var tag_bytes: u32 = 4;
    if max_psize == 0 || max_palign == 1 {
        if max_tag <= 0xff { tag_bytes = 1; }
        else if max_tag <= 0xffff { tag_bytes = 2; }
    } else if max_palign == 2 {
        if max_tag <= 0xffff { tag_bytes = 2; }
    }
    let payload_off = if max_psize == 0 { tag_bytes } else { alignUp(tag_bytes, max_palign) };
    return tag_bytes, payload_off, Error.none;
}
// Cached byte offset of record field `index` in flat form.
fn recordFieldByteOffset(self_: Types&, ty: Ty, index: i64) -> u32, Error {
    let cached = self_.field_byte_offs_slot[ty];
    if cached.present { return self_.field_byte_offs[(cached.start as i64) + index], Error.none; }
    let err = computeMemLayout(self_, ty);
    if err != Error.none { return 0, err; }
    let slot = self_.field_byte_offs_slot[ty];
    return self_.field_byte_offs[(slot.start as i64) + index], Error.none;
}
// Cached byte offset of tuple item `index` in flat form.
fn tupleItemByteOffset(self_: Types&, ty: Ty, index: i64) -> u32, Error {
    let cached = self_.field_byte_offs_slot[ty];
    if cached.present { return self_.field_byte_offs[(cached.start as i64) + index], Error.none; }
    let err = computeMemLayout(self_, ty);
    if err != Error.none { return 0, err; }
    let slot = self_.field_byte_offs_slot[ty];
    return self_.field_byte_offs[(slot.start as i64) + index], Error.none;
}
// Cached register word offset and width of record field `index`.
fn recordFieldWordSlice(self_: Types&, ty: Ty, index: i64) -> u32, u32, Error {
    var cached = self_.field_word_offs_slot[ty];
    if !cached.present {
        let n = self_.node(ty);
        let count = n.b as i64;
        var offs: u32[>..<] = [];
        var woff: u32 = 0;
        for i in 0..count {
            offs.push(woff);
            let fw, err = layout(self_, self_.words[(n.a as i64) + i * 2 + 1]);
            if err != Error.none { return 0, 0, err; }
            woff += fw.len as u32;
        }
        offs.push(woff);
        let start = self_.field_word_offs.len as u32;
        self_.field_word_offs.append(offs[..]);
        cached = Slot { true, start, (count + 1) as u32 };
        self_.field_word_offs_slot[ty] = cached;
    }
    let base = (cached.start as i64) + index;
    let s = self_.field_word_offs[base];
    return s, self_.field_word_offs[base + 1] - s, Error.none;
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
        boolean, u32_, u8_, i32_ => { self_.pushScratchLayout(i32w); },
        u64_, i64_ => { self_.pushScratchLayout(blot_direct_writer::VT_i64); },
        f64_ => { self_.pushScratchLayout(blot_direct_writer::VT_f64); },
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
                // Each payload's layout slot, kept on the word scratch.
                let mark = self_.scratch_len;
                for at in 0..(cases.len as i64) {
                    let item, error = flatSlot(self_, self_.variant_payloads[cases.payloads + at]);
                    if error != Error.none { self_.scratch_len = mark; return error; }
                    self_.pushScratch(item.start);
                    self_.pushScratch(item.len);
                }
                let oerr = computeSumOutlining(self_, ty, cases);
                if oerr != Error.none { self_.scratch_len = mark; return oerr; }
                if self_.outlined_computed[ty] == 2 {
                    // 2-variant nullable-pointer niche: single VT_i32 (0 = null, non-null = outlined payload ptr).
                    self_.scratch_len = mark;
                    self_.pushScratchLayout(i32w);
                    return Error.none;
                }
                self_.pushScratchLayout(i32w);
                var width: i64 = 0;
                for at in 0..(cases.len as i64) {
                    if !self_.recursive_[ty].present && variantOutlinedBit(self_, ty, at) {
                        self_.scratch[mark + at * 2] = 0;
                        self_.scratch[mark + at * 2 + 1] = 1;
                    }
                    let len = self_.scratch[mark + at * 2 + 1] as i64;
                    width = max(width, len);
                }
                for position in 0..width {
                    var all_f32 = true;
                    var all_f64 = true;
                    var any_wide = false;
                    var any_present = false;
                    var any_v128 = false;
                    for at in 0..(cases.len as i64) {
                        let start = self_.scratch[mark + at * 2];
                        let len = self_.scratch[mark + at * 2 + 1];
                        if position < len {
                            any_present = true;
                            let kind = self_.layout_words[start + position];
                            if kind != blot_direct_writer::VT_f32 { all_f32 = false; }
                            if kind != blot_direct_writer::VT_f64 { all_f64 = false; }
                            if kind == blot_direct_writer::VT_i64 || kind == blot_direct_writer::VT_f64 { any_wide = true; }
                            if kind == blot_direct_writer::VT_v128 { any_v128 = true; }
                        }
                    }
                    if any_v128 {
                        self_.scratch_len = mark;
                        self_.failure_reason = "SIMD payload in a sum type";
                        return Error.unsupported;
                    }
                    if any_present && all_f64 { self_.pushScratchLayout(blot_direct_writer::VT_f64); }
                    else if any_wide { self_.pushScratchLayout(blot_direct_writer::VT_i64); }
                    else if any_present && all_f32 { self_.pushScratchLayout(blot_direct_writer::VT_f32); }
                    else { self_.pushScratchLayout(i32w); }
                }
                self_.scratch_len = mark;
            }
        },
        // Owner handles: (slot, generation); views add (start, length),
        // element references and links add an index.
        array, packed, seq => { self_.pushScratchLayout(i32w); self_.pushScratchLayout(i32w); },
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
        array, packed, seq, ref, view, link => { return true; },
        _ => { return false; },
    }
}
