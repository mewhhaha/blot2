// Canonical FlatNumeric wire layouts, PersistentSafe validation, and FNV-1a 64-bit
// schema / implementation / binding hashes (tasks/CONCURRENCY_VNEXT.md §2.4 & §4.2.2).
namespace blot_check_wire_schema;

import std;
import dictionary;
import check.core;
import check.effects;
import check.types;
import check.storage_types;
import check.diagnostic_code;
import reuse.principal_interface;
import support.option;

type Module = blot_check_core::Module;
type TId = blot_check_types::Id;
type TTag = blot_check_types::Tag;
type Identity = blot_check_types::NominalIdentity;
type BindingRef = blot_check_core::BindingRef;
type Code = blot_check_diagnostic_code::Code;
type Chars = const u8[:];

let COMPILER_SEMANTICS_VERSION: u8 = 1;
let TRANSPORT_BUDGET: u64 = 2097152;
let MAX_WIRE_WORDS: u64 = (TRANSPORT_BUDGET - 4) / 4;

let SCHEMA_KIND_UNIT: u8 = 0;
let SCHEMA_KIND_FLAT_FIXED: u8 = 1;
let SCHEMA_KIND_VAR_U32: u8 = 2;
let SCHEMA_KIND_VAR_F32: u8 = 3;

let WIRE_TAG_UNIT: u8 = 0;
let WIRE_TAG_U32: u8 = 1;
let WIRE_TAG_BOOL: u8 = 2;
let WIRE_TAG_F32: u8 = 3;
let WIRE_TAG_ARRAY_U32: u8 = 5;
let WIRE_TAG_ARRAY_F32: u8 = 6;

let FNV_OFFSET: u64 = 0xcbf29ce484222325;
let FNV_PRIME: u64 = 0x100000001b3;

struct WireSchema {
    kind: u8 = 0,
    wire_tag: u8 = 0,
    stride: u32 = 0,
    tags_start: u32 = 0,
    tags_len: u32 = 0,
    schema_hash: u64 = 0,
}

struct KernelInfo {
    decl_index: u32 = 0,
    has_context: bool = false,
    variable_output: bool = false,
    flags: u8 = 0,
    ctx_schema: WireSchema = WireSchema {},
    in_schema: WireSchema = WireSchema {},
    out_schema: WireSchema = WireSchema {},
    io_schema_hash: u64 = 0,
    impl_hash: u64 = 0,
    binding_hash: u64 = 0,
}

struct ProcessInfo {
    decl_index: u32 = 0,
    config_schema: WireSchema = WireSchema {},
    cmd_schema: WireSchema = WireSchema {},
    reply_schema: WireSchema = WireSchema {},
    binding_hash: u64 = 0,
}

struct Issue {
    failed: bool = false,
    unit: u32 = 0,
    span: blot_check_core::Span = blot_check_core::Span { start: 0, end: 0 },
    code: Code = blot_check_diagnostic_code::Code.kernel_type,
    message: Chars = "",
}

root struct ProgramInfo {
    kernels: KernelInfo[>..] = [],
    processes: ProcessInfo[>..] = [],
    word_tags: u8[>..] = [],
    has_fork: bool = false,
    has_persistent_state: bool = false,
    kernel_staging_sites_count: u32 = 0,
    kernel_staging_sites_digest: u64 = FNV_OFFSET,
    process_closures_digest: u64 = FNV_OFFSET,
    dep_units: u32[>..] = [],
    issue: Issue = Issue {},
}

fn noteDepUnit(deps: u32[>..]&, unit: u32) {
    if unit == 0 { return; }
    for existing in deps { if existing == unit { return; } }
    deps.push(unit);
}

struct NonStagedReceipt {
    has_fork: bool = false,
    has_persistent_state: bool = false,
    exported_storage: bool = false,
    kernel_count: u32 = 0,
    process_count: u32 = 0,
    kernel_staging_sites_count: u32 = 0,
    kernel_staging_sites_digest: u64 = FNV_OFFSET,
    schemas_and_closures_digest: u64 = FNV_OFFSET,
}

fn sameNonStagedReceipt(a: NonStagedReceipt, b: NonStagedReceipt) -> bool {
    return a.has_fork == b.has_fork
        && a.has_persistent_state == b.has_persistent_state
        && a.exported_storage == b.exported_storage
        && a.kernel_count == b.kernel_count
        && a.process_count == b.process_count
        && a.kernel_staging_sites_count == b.kernel_staging_sites_count
        && a.kernel_staging_sites_digest == b.kernel_staging_sites_digest
        && a.schemas_and_closures_digest == b.schemas_and_closures_digest;
}

struct TypeRef {
    unit: u32 = 0,
    id: TId = 0,
}

struct SubstEntry {
    def_unit: u32 = 0,
    var_id: TId = 0,
    arg_unit: u32 = 0,
    arg_id: TId = 0,
}

struct ActiveNominal {
    unit: u32 = 0,
    decl: u32 = 0,
}

struct NamedIndex {
    name: Chars = "",
    index: i64 = 0,
}

struct Hasher {
    h: u64 = FNV_OFFSET,
}

fn boolByte(b: bool) -> u8 { if b { return 1; } return 0; }

fn fnvByte(s: Hasher&, b: u8) {
    s.h = (s.h ^ (b as u64)) * FNV_PRIME;
}
fn fnvBytes(s: Hasher&, data: Chars) {
    for b in data { fnvByte(s, b); }
}
fn fnvU32Le(s: Hasher&, v: u32) {
    fnvByte(s, (v & 0xff) as u8);
    fnvByte(s, ((v >> 8) & 0xff) as u8);
    fnvByte(s, ((v >> 16) & 0xff) as u8);
    fnvByte(s, ((v >> 24) & 0xff) as u8);
}
fn fnvU64Le(s: Hasher&, v: u64) {
    for i in 0..8 {
        fnvByte(s, ((v >> ((i * 8) as u64)) & 0xff) as u8);
    }
}
fn fnvUleb(s: Hasher&, value: u64) {
    var v = value;
    loop {
        var b = (v & 0x7f) as u8;
        v = v >> 7;
        if v != 0 { b = b | 0x80; }
        fnvByte(s, b);
        if v == 0 { break; }
    }
}
fn fnvStr(s: Hasher&, text: Chars) {
    fnvUleb(s, text.len as u64);
    fnvBytes(s, text);
}

fn pushUleb(out: u8[>..]&, value: u64) {
    var v = value;
    loop {
        var b = (v & 0x7f) as u8;
        v = v >> 7;
        if v != 0 { b = b | 0x80; }
        out.push(b);
        if v == 0 { break; }
    }
}
fn pushStr(out: u8[>..]&, text: Chars) {
    pushUleb(out, text.len as u64);
    out.append(text);
}

fn bytesLess(a: Chars, b: Chars) -> bool {
    let n = min(a.len, b.len);
    for i in 0..n {
        if a[i] != b[i] { return a[i] < b[i]; }
    }
    return a.len < b.len;
}

fn sortNamedRange(items: NamedIndex[>..]&, start: i64, end: i64) {
    for i in (start + 1)..end {
        let moved = items[i];
        var j = i;
        while j > start && bytesLess(moved.name, items[j - 1].name) {
            items[j] = items[j - 1];
            j -= 1;
        }
        items[j] = moved;
    }
}

fn hasUnit(units: const Module[:], unit: u32) -> bool {
    return unit != 0 && (unit as i64) <= units.len;
}

fn findNominalInUnit(m: const Module&, identity: Identity) -> i64 {
    for i in 1..m.nominals.len {
        if m.nominals[i].identity == identity { return i; }
    }
    return -1;
}

fn unitOriginText(units: const Module[:], unit: u32) -> Chars {
    if !hasUnit(units, unit) { return ""; }
    let m .= units[unit - 1];
    for i in 1..m.nominals.len {
        let nom = m.nominals[i];
        if nom.identity.unit == unit && nom.diagnostic_origin.len != 0 {
            return m.name(nom.diagnostic_origin);
        }
    }
    return "";
}

fn isStdOrigin(origin: Chars) -> bool {
    if origin == "std" || origin == "prelude" || origin == "std/prelude" { return true; }
    if origin.len >= 4 && origin[0] == ('s' as u8) && origin[1] == ('t' as u8) && origin[2] == ('d' as u8) && origin[3] == ('/' as u8) { return true; }
    return false;
}

fn hexDigit(v: u8) -> u8 {
    if v < 10 { return ('0' as u8) + v; }
    return ('a' as u8) + (v - 10);
}

fn appendHex64(out: u8[>..]&, value: u64) {
    var i: i64 = 15;
    while i >= 0 {
        let shift = (i * 4) as u64;
        let nibble = ((value >> shift) & 0xf) as u8;
        out.push(hexDigit(nibble));
        i -= 1;
    }
}

root struct UnitIdCache {
    computed: bool[>..] = [],
    computing: bool[>..] = [],
    starts: u32[>..] = [],
    lens: u32[>..] = [],
    bytes: u8[>..] = [],
    // §7.8 recursion scratch pools (mark & truncate around recursive calls).
    out_buf: u8[>..] = [],
    fields_pool: NamedIndex[>..] = [],
    subst_pool: SubstEntry[>..] = [],
    i64_pool: i64[>..] = [],
    active_pool: ActiveNominal[>..] = [],
    dep_units: u32[>..] = [],
}

fn initUnitIdCache(units: const Module[:], c: UnitIdCache&) {
    for _ in 0..units.len {
        c.computed.push(false);
        c.computing.push(false);
        c.starts.push(0);
        c.lens.push(0);
    }
}

fn lookupSubstRange(pool: const SubstEntry[:], start: i64, len: i64, unit: u32, var_id: TId) -> TypeRef, bool {
    var i = start + len;
    while i > start {
        i -= 1;
        if pool[i].def_unit == unit && pool[i].var_id == var_id {
            return TypeRef { unit: pool[i].arg_unit, id: pool[i].arg_id }, true;
        }
    }
    return TypeRef {}, false;
}

fn lookupGenericParam(params: const TId[:], var_id: TId) -> i64 {
    for i in 0..params.len {
        if params[i] == var_id { return i; }
    }
    return -1;
}

fn findActiveRange(active: const ActiveNominal[:], base: i64, unit: u32, decl: u32) -> i64 {
    var i = active.len;
    while i > base {
        i -= 1;
        if active[i].unit == unit && active[i].decl == decl {
            return (active.len - 1) - i;
        }
    }
    return -1;
}

fn findNominalName(units: const Module[:], id: Identity) -> Chars {
    if !hasUnit(units, id.unit) { return ""; }
    let dm .= units[id.unit - 1];
    let idx = findNominalInUnit(dm, id);
    if idx < 0 { return ""; }
    return dm.name(dm.nominals[idx].diagnostic_name);
}

fn findOperationName(units: const Module[:], id: Identity) -> Chars {
    if !hasUnit(units, id.unit) { return ""; }
    let dm .= units[id.unit - 1];
    for op in dm.operation_names {
        if op.identity == id { return dm.name(op.diagnostic_name); }
    }
    return "";
}

recursive fn pushUnitIdStr(
    units: const Module[:],
    cache: UnitIdCache&,
    unit: u32,
    self_unit: u32
) -> bool {
    if self_unit != 0 && unit == self_unit {
        pushStr(cache.out_buf, "self");
        return true;
    }
    if !hasUnit(units, unit) { return false; }
    noteDepUnit(cache.dep_units, unit);
    let idx = (unit - 1) as i64;
    if cache.computed[idx] {
        let s = cache.starts[idx] as i64;
        let l = cache.lens[idx] as i64;
        pushUleb(cache.out_buf, l as u64);
        for k in 0..l { cache.out_buf.push(cache.bytes[s + k]); }
        return true;
    }
    if cache.computing[idx] {
        pushStr(cache.out_buf, "cycle");
        return true;
    }
    cache.computing[idx] = true;
    let origin = unitOriginText(units, unit);
    var digest: u64 = 0;
    let is_std = isStdOrigin(origin);
    if !is_std {
        digest = computeUnitInterfaceDigest(units, cache, unit);
    }
    let start = cache.bytes.len;
    if is_std {
        if origin.len >= 4 && origin[0] == ('s' as u8) && origin[1] == ('t' as u8) && origin[2] == ('d' as u8) && origin[3] == ('/' as u8) {
            cache.bytes.append(origin);
        } else {
            cache.bytes.append("std/");
            cache.bytes.append(origin);
        }
    } else {
        cache.bytes.append(origin);
        cache.bytes.push('#' as u8);
        appendHex64(cache.bytes, digest);
    }
    let len = cache.bytes.len - start;
    cache.computing[idx] = false;
    cache.computed[idx] = true;
    cache.starts[idx] = start as u32;
    cache.lens[idx] = len as u32;
    pushUleb(cache.out_buf, len as u64);
    for k in 0..len { cache.out_buf.push(cache.bytes[start + k]); }
    return true;
}

recursive fn encodeNomId(
    units: const Module[:],
    cache: UnitIdCache&,
    id: Identity,
    self_unit: u32,
    is_op: bool
) -> bool {
    if id.unit == 0 && id.decl == 0 {
        cache.out_buf.push(0x00);
        return true;
    }
    if id.unit == 0 && id.decl == 1 {
        cache.out_buf.push(0x03);
        return true;
    }
    if id.unit == 0 && id.decl > 1 {
        return false;
    }
    if id.unit == 0xffffffff {
        cache.out_buf.push(0x01);
        pushUleb(cache.out_buf, id.decl as u64);
        return true;
    }
    if !hasUnit(units, id.unit) { return false; }
    cache.out_buf.push(0x02);
    if !pushUnitIdStr(units, cache, id.unit, self_unit) { return false; }
    if is_op { pushStr(cache.out_buf, findOperationName(units, id)); }
    else { pushStr(cache.out_buf, findNominalName(units, id)); }
    return true;
}

recursive fn encodeEffectRow(
    units: const Module[:],
    cache: UnitIdCache&,
    unit: u32,
    row_id: blot_check_effects::Id,
    subst_start: i64,
    subst_len: i64,
    active_base: i64,
    allow_generic: bool,
    generic_params: const TId[:],
    generic_rows: const u32[:],
    self_unit: u32,
    depth: i64
) -> bool {
    if depth > 128 { return false; }
    if row_id == 0 {
        cache.out_buf.push(0x00);
        cache.out_buf.push(0x00);
        return true;
    }
    if !hasUnit(units, unit) { return false; }
    let m .= units[unit - 1];
    if (row_id as i64) >= m.types.effects.rows.len { return false; }
    let row = m.types.row(row_id);
    var tail_is_param = false;
    var tail_idx: u64 = 0;
    match row.tail {
        closed => {},
        parameter p => {
            if !allow_generic { return false; }
            tail_is_param = true;
            tail_idx = p.value as u64;
        },
        variable v => {
            if !allow_generic { return false; }
            var found: i64 = -1;
            for i in 0..generic_rows.len {
                if generic_rows[i] == v.value { found = i; break; }
            }
            if found < 0 { return false; }
            tail_is_param = true;
            tail_idx = found as u64;
        },
        formal _ => { return false; },
    }
    let labels = m.types.rowLabels(row_id);
    let out_mark = cache.out_buf.len;
    let imark = cache.i64_pool.len;
    var ok = true;
    for label in labels {
        let op = m.types.operation(label);
        let op_start = cache.out_buf.len;
        if !encodeNomId(units, cache, op.identity, self_unit, true) { ok = false; break; }
        if !encodeNomId(units, cache, op.instance, self_unit, false) { ok = false; break; }
        let args = m.types.list(op.arguments);
        pushUleb(cache.out_buf, args.len as u64);
        for arg in args {
            if !encodeTypeId(units, cache, unit, arg, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1) { ok = false; break; }
        }
        if !ok { break; }
        let op_len = cache.out_buf.len - op_start;
        cache.i64_pool.push(op_start);
        cache.i64_pool.push(op_len);
    }
    if !ok {
        cache.i64_pool.resize(imark);
        cache.out_buf.resize(out_mark);
        return false;
    }
    let op_count = (cache.i64_pool.len - imark) / 2;
    {
        var raw_ops: u8[>..] = [];
        for bi in out_mark..cache.out_buf.len { raw_ops.push(cache.out_buf[bi]); }
        var order: i64[>..] = [];
        for i in 0..op_count { order.push(i); }
        for i in 1..op_count {
            let moved = order[i];
            let ms = cache.i64_pool[imark + moved * 2] - out_mark;
            let ml = cache.i64_pool[imark + moved * 2 + 1];
            var j = i;
            while j > 0 {
                let prev = order[j - 1];
                let ps = cache.i64_pool[imark + prev * 2] - out_mark;
                let pl = cache.i64_pool[imark + prev * 2 + 1];
                if !bytesLess(raw_ops[ms..ms + ml], raw_ops[ps..ps + pl]) { break; }
                order[j] = prev;
                j -= 1;
            }
            order[j] = moved;
        }
        cache.out_buf.resize(out_mark);
        pushUleb(cache.out_buf, op_count as u64);
        for idx in order {
            let os = cache.i64_pool[imark + idx * 2] - out_mark;
            let ol = cache.i64_pool[imark + idx * 2 + 1];
            cache.out_buf.append(raw_ops[os..os + ol]);
        }
    }
    cache.i64_pool.resize(imark);
    if tail_is_param {
        cache.out_buf.push(0x01);
        pushUleb(cache.out_buf, tail_idx);
    } else {
        cache.out_buf.push(0x00);
    }
    return true;
}

recursive fn encodeTypeId(
    units: const Module[:],
    cache: UnitIdCache&,
    unit: u32,
    tid: TId,
    subst_start: i64,
    subst_len: i64,
    active_base: i64,
    allow_generic: bool,
    generic_params: const TId[:],
    generic_rows: const u32[:],
    self_unit: u32,
    depth: i64
) -> bool {
    if depth > 128 { return false; }
    if !hasUnit(units, unit) { return false; }
    let m .= units[unit - 1];
    if (tid as i64) >= m.types.nodes.len { return false; }
    let node = m.types.node(tid);
    match node.tag {
        unit => { cache.out_buf.push(0x00); return true; },
        unsigned32 => { cache.out_buf.push(0x01); return true; },
        boolean => { cache.out_buf.push(0x02); return true; },
        floating32 => { cache.out_buf.push(0x03); return true; },
        never => { cache.out_buf.push(0x06); return true; },
        variable => {
            let mapped, ok = lookupSubstRange(cache.subst_pool[..], subst_start, subst_len, unit, tid);
            if ok {
                return encodeTypeId(units, cache, mapped.unit, mapped.id, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1);
            }
            if allow_generic {
                let gidx = lookupGenericParam(generic_params, tid);
                if gidx >= 0 {
                    cache.out_buf.push(0x15);
                    pushUleb(cache.out_buf, gidx as u64);
                    return true;
                }
            }
            return false;
        },
        array => {
            cache.out_buf.push(0x20);
            return encodeTypeId(units, cache, unit, node.a, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1);
        },
        product => {
            cache.out_buf.push(0x10);
            pushUleb(cache.out_buf, node.b as u64);
            let items = m.types.list(blot_check_types::List { start: node.a, len: node.b });
            for child in items {
                if !encodeTypeId(units, cache, unit, child, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1) { return false; }
            }
            return true;
        },
        record => {
            cache.out_buf.push(0x11);
            pushUleb(cache.out_buf, node.b as u64);
            let fmark = cache.fields_pool.len;
            for i in 0..(node.b as i64) {
                let f = m.types.recordField(node, i);
                let sp = m.fieldSpelling(f.name);
                if !sp.present { cache.fields_pool.resize(fmark); return false; }
                cache.fields_pool.push(NamedIndex { name: sp.value, index: i });
            }
            let fend = cache.fields_pool.len;
            sortNamedRange(cache.fields_pool, fmark, fend);
            var ok = true;
            for fi in fmark..fend {
                let item = cache.fields_pool[fi];
                let f = m.types.recordField(node, item.index);
                pushStr(cache.out_buf, item.name);
                if !encodeTypeId(units, cache, unit, f.ty, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1) { ok = false; break; }
            }
            cache.fields_pool.resize(fmark);
            return ok;
        },
        function => {
            cache.out_buf.push(0x26);
            var own_flag: u8 = 0;
            var param_ty = node.a;
            let pnode = m.types.node(param_ty);
            if pnode.tag == blot_check_types::Tag.usage && pnode.b == blot_check_types::usageCode(blot_parse_ast::usagekind_own) {
                own_flag = 1;
                param_ty = pnode.a;
            }
            cache.out_buf.push(own_flag);
            if !encodeTypeId(units, cache, unit, param_ty, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1) { return false; }
            if !encodeEffectRow(units, cache, unit, node.c, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1) { return false; }
            return encodeTypeId(units, cache, unit, node.b, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1);
        },
        provider => {
            cache.out_buf.push(0x27);
            if !encodeTypeId(units, cache, unit, node.a, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1) { return false; }
            return encodeEffectRow(units, cache, unit, node.c, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1);
        },
        state_provider => {
            cache.out_buf.push(0x2c);
            if !encodeTypeId(units, cache, unit, node.a, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1) { return false; }
            if !encodeTypeId(units, cache, unit, node.b, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1) { return false; }
            return encodeTypeId(units, cache, unit, node.c, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1);
        },
        nominal => {
            let sinfo = blot_check_storage_types::info(m.types, tid);
            if sinfo.present {
                let kind = sinfo.value.kind;
                let elem = sinfo.value.element;
                if blot_check_storage_types::isSized(kind) {
                    let len_opt = blot_check_storage_types::lengthOf(m.types, tid);
                    if !len_opt.present { return false; }
                    let lnode = m.types.node(len_opt.value);
                    if lnode.tag != blot_check_types::Tag.nominal || !blot_check_storage_types::isLengthLiteral(lnode.a, lnode.b) { return false; }
                    let k = blot_check_storage_types::lengthLiteralValue(lnode.b);
                    if kind == blot_check_storage_types::sized_array { cache.out_buf.push(0x12); }
                    else { return false; }
                    pushUleb(cache.out_buf, k as u64);
                    return encodeTypeId(units, cache, unit, elem, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1);
                }
                if kind == blot_check_storage_types::view { cache.out_buf.push(0x23); }
                else if kind == blot_check_storage_types::shared { cache.out_buf.push(0x24); }
                else if kind == blot_check_storage_types::ref { cache.out_buf.push(0x2a); }
                else if kind == blot_check_storage_types::link { cache.out_buf.push(0x2b); }
                else if kind == blot_check_storage_types::packed { cache.out_buf.push(0x2d); }
                else if kind == blot_check_storage_types::seq { cache.out_buf.push(0x2e); }
                else { return false; }
                return encodeTypeId(units, cache, unit, elem, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1);
            }
            if node.a == 0 && node.b > 1 { return false; }
            if node.a == 0xffffffff {
                if blot_check_storage_types::isLengthLiteral(node.a, node.b) {
                    cache.out_buf.push(0x16);
                    pushUleb(cache.out_buf, blot_check_storage_types::lengthLiteralValue(node.b) as u64);
                    return true;
                }
                return false;
            }
            if !hasUnit(units, node.a) { return false; }
            noteDepUnit(cache.dep_units, node.a);
            let back = findActiveRange(cache.active_pool[..], active_base, node.a, node.b);
            if back >= 0 {
                cache.out_buf.push(0x14);
                pushUleb(cache.out_buf, back as u64);
                return true;
            }
            let dm .= units[node.a - 1];
            let nidx = findNominalInUnit(dm, Identity { unit: node.a, decl: node.b });
            if nidx < 0 { return false; }
            let nom = dm.nominals[nidx];
            cache.out_buf.push(0x13);
            if !pushUnitIdStr(units, cache, node.a, self_unit) { return false; }
            pushStr(cache.out_buf, dm.name(nom.diagnostic_name));
            let args = m.types.nominalArguments(node);
            pushUleb(cache.out_buf, args.len as u64);
            for arg in args {
                if !encodeTypeId(units, cache, unit, arg, subst_start, subst_len, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1) { return false; }
            }
            let smark = cache.subst_pool.len;
            let vars = dm.types.list(nom.variables);
            if vars.len == args.len {
                for vi in 0..vars.len {
                    var target_u = unit;
                    var target_id = args[vi];
                    if m.types.node(target_id).tag == blot_check_types::Tag.variable {
                        let mapped, ok = lookupSubstRange(cache.subst_pool[..], subst_start, subst_len, unit, target_id);
                        if ok { target_u = mapped.unit; target_id = mapped.id; }
                    }
                    cache.subst_pool.push(SubstEntry { def_unit: node.a, var_id: vars[vi], arg_unit: target_u, arg_id: target_id });
                }
            }
            let slen = cache.subst_pool.len - smark;
            cache.active_pool.push(ActiveNominal { unit: node.a, decl: node.b });
            let ctors = dm.nominalConstructors(nidx as u32);
            pushUleb(cache.out_buf, ctors.len as u64);
            var ok = true;
            for cid in ctors {
                let ctor = dm.constructor(cid);
                let csp = dm.fieldSpelling(ctor.name);
                if csp.present { pushStr(cache.out_buf, csp.value); }
                else { pushStr(cache.out_buf, ""); }
                if ctor.payload == 0 {
                    cache.out_buf.push(0x00);
                } else {
                    if !encodeTypeId(units, cache, node.a, ctor.payload, smark, slen, active_base, allow_generic, generic_params, generic_rows, self_unit, depth + 1) {
                        ok = false;
                        break;
                    }
                }
            }
            cache.active_pool.resize(cache.active_pool.len - 1);
            cache.subst_pool.resize(smark);
            return ok;
        },
        _ => { return false; },
    }
}

recursive fn computeUnitInterfaceDigest(units: const Module[:], cache: UnitIdCache&, unit: u32) -> u64 {
    if !hasUnit(units, unit) { return FNV_OFFSET; }
    let m .= units[unit - 1];
    let dmark = cache.fields_pool.len;
    for i in 1..m.nominals.len {
        let nom = m.nominals[i];
        if nom.identity.unit != unit { continue; }
        cache.fields_pool.push(NamedIndex { name: m.name(nom.diagnostic_name), index: i });
    }
    let dend = cache.fields_pool.len;
    sortNamedRange(cache.fields_pool, dmark, dend);
    var hasher = Hasher {};
    fnvUleb(hasher, (dend - dmark) as u64);
    let empty_rows: u32[0] = [];
    for di in dmark..dend {
        let entry = cache.fields_pool[di];
        let nom = m.nominals[entry.index];
        fnvStr(hasher, entry.name);
        fnvByte(hasher, boolByte(nom.is_opaque));
        let vars = m.types.list(nom.variables);
        fnvUleb(hasher, vars.len as u64);
        let ctors = m.nominalConstructors(entry.index as u32);
        fnvUleb(hasher, ctors.len as u64);
        let amark = cache.active_pool.len;
        cache.active_pool.push(ActiveNominal { unit: unit, decl: nom.identity.decl });
        for cid in ctors {
            let ctor = m.constructor(cid);
            let csp = m.fieldSpelling(ctor.name);
            if csp.present { fnvStr(hasher, csp.value); }
            else { fnvStr(hasher, ""); }
            if ctor.payload == 0 {
                fnvByte(hasher, 0x00);
            } else {
                let omark = cache.out_buf.len;
                let ok = encodeTypeId(units, cache, unit, ctor.payload, 0, 0, amark, true, vars, empty_rows[..], unit, 0);
                if ok { fnvBytes(hasher, cache.out_buf[omark..]); }
                else { fnvByte(hasher, 0xff); }
                cache.out_buf.resize(omark);
            }
        }
        cache.active_pool.resize(amark);
    }
    cache.fields_pool.resize(dmark);
    return hasher.h;
}

// Recursive FlatNumeric collector (§2.4).
recursive fn collectFlatNumeric(
    units: const Module[:],
    cache: UnitIdCache&,
    unit: u32,
    tid: TId,
    subst_start: i64,
    subst_len: i64,
    active_base: i64,
    word_tags: u8[>..]&,
    all_f32: bool&,
    depth: i64
) -> bool {
    if depth > 64 { return false; }
    if !hasUnit(units, unit) { return false; }
    let m .= units[unit - 1];
    if (tid as i64) >= m.types.nodes.len { return false; }
    let node = m.types.node(tid);
    match node.tag {
        unsigned32 => {
            if (word_tags.len as u64) >= MAX_WIRE_WORDS { return false; }
            word_tags.push(WIRE_TAG_U32);
            all_f32 = false;
            return true;
        },
        boolean => {
            if (word_tags.len as u64) >= MAX_WIRE_WORDS { return false; }
            word_tags.push(WIRE_TAG_BOOL);
            all_f32 = false;
            return true;
        },
        floating32 => {
            if (word_tags.len as u64) >= MAX_WIRE_WORDS { return false; }
            word_tags.push(WIRE_TAG_F32);
            return true;
        },
        variable => {
            let mapped, ok = lookupSubstRange(cache.subst_pool[..], subst_start, subst_len, unit, tid);
            if !ok { return false; }
            return collectFlatNumeric(units, cache, mapped.unit, mapped.id, subst_start, subst_len, active_base, word_tags, all_f32, depth + 1);
        },
        product => {
            if node.b == 0 { return false; }
            let items = m.types.list(blot_check_types::List { start: node.a, len: node.b });
            for child in items {
                if !collectFlatNumeric(units, cache, unit, child, subst_start, subst_len, active_base, word_tags, all_f32, depth + 1) { return false; }
            }
            return true;
        },
        record => {
            if node.b == 0 { return false; }
            let fmark = cache.fields_pool.len;
            for i in 0..(node.b as i64) {
                let f = m.types.recordField(node, i);
                let sp = m.fieldSpelling(f.name);
                if !sp.present { cache.fields_pool.resize(fmark); return false; }
                cache.fields_pool.push(NamedIndex { name: sp.value, index: i });
            }
            let fend = cache.fields_pool.len;
            sortNamedRange(cache.fields_pool, fmark, fend);
            var ok = true;
            for fi in fmark..fend {
                let item = cache.fields_pool[fi];
                let f = m.types.recordField(node, item.index);
                if !collectFlatNumeric(units, cache, unit, f.ty, subst_start, subst_len, active_base, word_tags, all_f32, depth + 1) { ok = false; break; }
            }
            cache.fields_pool.resize(fmark);
            return ok;
        },
        nominal => {
            let sinfo = blot_check_storage_types::info(m.types, tid);
            if sinfo.present {
                if sinfo.value.kind != blot_check_storage_types::sized_array { return false; }
                let len_opt = blot_check_storage_types::lengthOf(m.types, tid);
                if !len_opt.present { return false; }
                let lnode = m.types.node(len_opt.value);
                if lnode.tag != blot_check_types::Tag.nominal || !blot_check_storage_types::isLengthLiteral(lnode.a, lnode.b) { return false; }
                let k = blot_check_storage_types::lengthLiteralValue(lnode.b) as u64;
                if k == 0 { return false; }
                let tmark = word_tags.len;
                var elem_f32 = true;
                if !collectFlatNumeric(units, cache, unit, sinfo.value.element, subst_start, subst_len, active_base, word_tags, elem_f32, depth + 1) { return false; }
                let elem_w = (word_tags.len - tmark) as u64;
                if elem_w == 0 { return false; }
                if elem_w > MAX_WIRE_WORDS / k { return false; }
                let total_add = elem_w * k;
                if (tmark as u64) + total_add > MAX_WIRE_WORDS { return false; }
                if !elem_f32 { all_f32 = false; }
                let elem_len = elem_w as i64;
                for _ in 1..(k as i64) {
                    for ei in 0..elem_len { word_tags.push(word_tags[tmark + ei]); }
                }
                return true;
            }
            if node.a == 0 || node.a == 0xffffffff { return false; }
            if !hasUnit(units, node.a) { return false; }
            noteDepUnit(cache.dep_units, node.a);
            if findActiveRange(cache.active_pool[..], active_base, node.a, node.b) >= 0 { return false; }
            let dm .= units[node.a - 1];
            let nidx = findNominalInUnit(dm, Identity { unit: node.a, decl: node.b });
            if nidx < 0 { return false; }
            let nom = dm.nominals[nidx];
            if nom.is_opaque { return false; }
            let ctors = dm.nominalConstructors(nidx as u32);
            if ctors.len != 1 { return false; }
            let ctor = dm.constructor(ctors[0]);
            if ctor.payload == 0 { return false; }
            let args = m.types.nominalArguments(node);
            let vars = dm.types.list(nom.variables);
            if vars.len != args.len { return false; }
            let smark = cache.subst_pool.len;
            for vi in 0..vars.len {
                var target_u = unit;
                var target_id = args[vi];
                if m.types.node(target_id).tag == blot_check_types::Tag.variable {
                    let mapped, ok = lookupSubstRange(cache.subst_pool[..], subst_start, subst_len, unit, target_id);
                    if ok { target_u = mapped.unit; target_id = mapped.id; }
                }
                cache.subst_pool.push(SubstEntry { def_unit: node.a, var_id: vars[vi], arg_unit: target_u, arg_id: target_id });
            }
            let slen = cache.subst_pool.len - smark;
            cache.active_pool.push(ActiveNominal { unit: node.a, decl: node.b });
            let ok = collectFlatNumeric(units, cache, node.a, ctor.payload, smark, slen, active_base, word_tags, all_f32, depth + 1);
            cache.active_pool.resize(cache.active_pool.len - 1);
            cache.subst_pool.resize(smark);
            return ok;
        },
        _ => { return false; },
    }
}

fn buildWireSchema(
    units: const Module[:],
    cache: UnitIdCache&,
    word_tags_pool: u8[>..]&,
    unit: u32,
    tid: TId,
    allow_unit: bool,
    allow_var_array: bool,
    var_f32_uses_u32_wire: bool,
    allow_scalar_wire: bool
) -> WireSchema, bool {
    var result = WireSchema {};
    if !hasUnit(units, unit) { return result, false; }
    let m .= units[unit - 1];
    if (tid as i64) >= m.types.nodes.len { return result, false; }
    let omark = cache.out_buf.len;
    let amark = cache.active_pool.len;
    let empty_params: TId[0] = [];
    let empty_rows: u32[0] = [];
    if !encodeTypeId(units, cache, unit, tid, 0, 0, amark, false, empty_params[..], empty_rows[..], 0, 0) {
        cache.out_buf.resize(omark);
        cache.active_pool.resize(amark);
        return result, false;
    }
    var enc: u8[>..] = [];
    enc.append(cache.out_buf[omark..]);
    cache.out_buf.resize(omark);
    cache.active_pool.resize(amark);

    let node = m.types.node(tid);
    if node.tag == blot_check_types::Tag.unit {
        if !allow_unit { return result, false; }
        result.kind = SCHEMA_KIND_UNIT;
        result.wire_tag = WIRE_TAG_UNIT;
        result.stride = 0;
    } else if node.tag == blot_check_types::Tag.array {
        if !allow_var_array { return result, false; }
        let elem = m.types.node(node.a);
        if elem.tag == blot_check_types::Tag.unsigned32 {
            result.kind = SCHEMA_KIND_VAR_U32;
            result.wire_tag = WIRE_TAG_ARRAY_U32;
            result.stride = 0;
        } else if elem.tag == blot_check_types::Tag.floating32 {
            result.kind = SCHEMA_KIND_VAR_F32;
            result.wire_tag = WIRE_TAG_ARRAY_F32;
            if var_f32_uses_u32_wire { result.wire_tag = WIRE_TAG_ARRAY_U32; }
            result.stride = 0;
        } else {
            return result, false;
        }
    } else {
        var tags: u8[>..] = [];
        var all_f32 = true;
        let flat_amark = cache.active_pool.len;
        if !collectFlatNumeric(units, cache, unit, tid, 0, 0, flat_amark, tags, all_f32, 0) {
            cache.active_pool.resize(flat_amark);
            return result, false;
        }
        cache.active_pool.resize(flat_amark);
        if tags.len == 0 || (tags.len as u64) > MAX_WIRE_WORDS { return result, false; }
        result.kind = SCHEMA_KIND_FLAT_FIXED;
        result.stride = tags.len as u32;
        result.tags_start = word_tags_pool.len as u32;
        result.tags_len = tags.len as u32;
        for wt in tags { word_tags_pool.push(wt); }
        if allow_scalar_wire && result.stride == 1 {
            result.wire_tag = word_tags_pool[result.tags_start];
        } else if all_f32 {
            result.wire_tag = WIRE_TAG_ARRAY_F32;
        } else {
            result.wire_tag = WIRE_TAG_ARRAY_U32;
        }
    }
    var h = Hasher {};
    fnvByte(h, 0x01);
    fnvByte(h, result.kind);
    fnvByte(h, result.wire_tag);
    fnvUleb(h, result.stride as u64);
    if result.kind == SCHEMA_KIND_FLAT_FIXED {
        for ti in 0..(result.tags_len as i64) { fnvByte(h, word_tags_pool[(result.tags_start as i64) + ti]); }
    }
    fnvBytes(h, enc[..]);
    result.schema_hash = h.h;
    return result, true;
}

// Standalone schema hash helper for `@flat.schema_hash` (accepts FlatNumeric, Unit, or #[U32]/#[F32]).
fn computeSchemaHash(units: const Module[:], unit: u32, tid: TId) -> u64, bool {
    var cache = UnitIdCache {};
    initUnitIdCache(units, cache);
    var scratch_tags: u8[>..] = [];
    // Unwrap prelude `Type T` witness wrapper if given (single-ctor `Type` whose payload is `Unit` and 1 type arg `T`).
    var target = tid;
    if hasUnit(units, unit) {
        let m .= units[unit - 1];
        if (tid as i64) < m.types.nodes.len {
            let n = m.types.node(tid);
            if n.tag == blot_check_types::Tag.nominal && hasUnit(units, n.a) && n.a != 0xffffffff {
                let dm .= units[n.a - 1];
                let nidx = findNominalInUnit(dm, Identity { unit: n.a, decl: n.b });
                if nidx >= 0 && dm.name(dm.nominals[nidx].diagnostic_name) == "Type" {
                    let args = m.types.nominalArguments(n);
                    if args.len == 1 { target = args[0]; }
                }
            }
        }
    }
    let schema, ok = buildWireSchema(units, cache, scratch_tags, unit, target, true, true, false, false);
    if !ok { return 0, false; }
    return schema.schema_hash, true;
}

// PersistentSafe validator (§4.2.2):
// Allows scalars, tuples, closed records, data/opaque sums (incl. recursive & boxed),
// owned arrays `#[T]` / `#[+T]` / `#[~T]` / `#[n; T]` / `#[+n; T]` / `#[~n; T]` / `*T`.
// Rejects functions/closures, `&[T]` views, `Ref`, `Link`, cells, effect providers, open vars.
recursive fn checkPersistentSafe(
    units: const Module[:],
    cache: UnitIdCache&,
    unit: u32,
    tid: TId,
    subst_start: i64,
    subst_len: i64,
    active_base: i64,
    depth: i64
) -> bool {
    if depth > 128 { return false; }
    if !hasUnit(units, unit) { return false; }
    let m .= units[unit - 1];
    if (tid as i64) >= m.types.nodes.len { return false; }
    let node = m.types.node(tid);
    match node.tag {
        unit, boolean, unsigned32, floating32, never => { return true; },
        variable => {
            let mapped, ok = lookupSubstRange(cache.subst_pool[..], subst_start, subst_len, unit, tid);
            if !ok { return false; }
            return checkPersistentSafe(units, cache, mapped.unit, mapped.id, subst_start, subst_len, active_base, depth + 1);
        },
        array => {
            return checkPersistentSafe(units, cache, unit, node.a, subst_start, subst_len, active_base, depth + 1);
        },
        product => {
            let items = m.types.list(blot_check_types::List { start: node.a, len: node.b });
            for child in items {
                if !checkPersistentSafe(units, cache, unit, child, subst_start, subst_len, active_base, depth + 1) { return false; }
            }
            return true;
        },
        record => {
            for i in 0..(node.b as i64) {
                let f = m.types.recordField(node, i);
                if !checkPersistentSafe(units, cache, unit, f.ty, subst_start, subst_len, active_base, depth + 1) { return false; }
            }
            return true;
        },
        nominal => {
            let sinfo = blot_check_storage_types::info(m.types, tid);
            if sinfo.present {
                let kind = sinfo.value.kind;
                if kind == blot_check_storage_types::shared ||
                   kind == blot_check_storage_types::sized_array ||
                   kind == blot_check_storage_types::packed ||
                   kind == blot_check_storage_types::seq {
                    if blot_check_storage_types::isSized(kind) {
                        let len_opt = blot_check_storage_types::lengthOf(m.types, tid);
                        if !len_opt.present { return false; }
                        let lnode = m.types.node(len_opt.value);
                        if lnode.tag != blot_check_types::Tag.nominal || !blot_check_storage_types::isLengthLiteral(lnode.a, lnode.b) { return false; }
                    }
                    return checkPersistentSafe(units, cache, unit, sinfo.value.element, subst_start, subst_len, active_base, depth + 1);
                }
                return false;
            }
            if node.a == 0 || node.a == 0xffffffff { return false; }
            if !hasUnit(units, node.a) { return false; }
            noteDepUnit(cache.dep_units, node.a);
            if findActiveRange(cache.active_pool[..], active_base, node.a, node.b) >= 0 { return true; }
            let dm .= units[node.a - 1];
            let nidx = findNominalInUnit(dm, Identity { unit: node.a, decl: node.b });
            if nidx < 0 { return false; }
            let nom = dm.nominals[nidx];
            let args = m.types.nominalArguments(node);
            let vars = dm.types.list(nom.variables);
            if vars.len != args.len { return false; }
            let smark = cache.subst_pool.len;
            for vi in 0..vars.len {
                var target_u = unit;
                var target_id = args[vi];
                if m.types.node(target_id).tag == blot_check_types::Tag.variable {
                    let mapped, ok = lookupSubstRange(cache.subst_pool[..], subst_start, subst_len, unit, target_id);
                    if ok { target_u = mapped.unit; target_id = mapped.id; }
                }
                cache.subst_pool.push(SubstEntry { def_unit: node.a, var_id: vars[vi], arg_unit: target_u, arg_id: target_id });
            }
            let slen = cache.subst_pool.len - smark;
            cache.active_pool.push(ActiveNominal { unit: node.a, decl: node.b });
            let ctors = dm.nominalConstructors(nidx as u32);
            var ok = true;
            for cid in ctors {
                let ctor = dm.constructor(cid);
                if ctor.payload != 0 {
                    if !checkPersistentSafe(units, cache, node.a, ctor.payload, smark, slen, active_base, depth + 1) {
                        ok = false;
                        break;
                    }
                }
            }
            cache.active_pool.resize(cache.active_pool.len - 1);
            cache.subst_pool.resize(smark);
            return ok;
        },
        _ => { return false; },
    }
}

fn resolveBindingTargetTracked(units: const Module[:], from_unit: u32, ref_: BindingRef, deps: u32[>..]&) -> BindingRef {
    var u = ref_.unit;
    if u == 0 { u = from_unit; }
    var b = ref_.binding;
    for _ in 0..16 {
        if !hasUnit(units, u) || b == 0 { return BindingRef { 0, 0 }; }
        noteDepUnit(deps, u);
        let m .= units[u - 1];
        if (b as i64) >= m.bindings.len { return BindingRef { 0, 0 }; }
        let info = m.binding(b);
        if info.kind == blot_reuse_principal_interface::Kind.external && info.target.binding != 0 {
            u = info.target.unit;
            b = info.target.binding;
            continue;
        }
        return BindingRef { u, b };
    }
    return BindingRef { 0, 0 };
}

fn resolveBindingTarget(units: const Module[:], from_unit: u32, ref_: BindingRef) -> BindingRef {
    var u = ref_.unit;
    if u == 0 { u = from_unit; }
    var b = ref_.binding;
    for _ in 0..16 {
        if !hasUnit(units, u) || b == 0 { return BindingRef { 0, 0 }; }
        let m .= units[u - 1];
        if (b as i64) >= m.bindings.len { return BindingRef { 0, 0 }; }
        let info = m.binding(b);
        if info.kind == blot_reuse_principal_interface::Kind.external && info.target.binding != 0 {
            u = info.target.unit;
            b = info.target.binding;
            continue;
        }
        return BindingRef { u, b };
    }
    return BindingRef { 0, 0 };
}

// Transitive Core implementation hasher for `impl_hash` (§2.4 & §4.1 item 3).
struct AssocIndexEntry {
    unit: u32 = 0,
    identity: Identity = Identity { 0, 0 },
    target: BindingRef = BindingRef { 0, 0 },
    name: Chars = "",
    next: u32 = 0,
}

struct ImplIndexEntry {
    unit: u32 = 0,
    target: BindingRef = BindingRef { 0, 0 },
    next: u32 = 0,
}

root struct SharedHashIndex {
    assoc_indexed: bool = false,
    assoc_heads: dictionary<u64, u32> = dictionary<u64, u32>{},
    assoc_entries: AssocIndexEntry[>..] = [],
    impl_indexed: bool = false,
    impl_heads: dictionary<u64, u32> = dictionary<u64, u32>{},
    impl_entries: ImplIndexEntry[>..] = [],
}

root struct ImplHashCtx {
    h: Hasher = Hasher {},
    visited: dictionary<BindingRef, bool> = dictionary<BindingRef, bool>{},
    queue: BindingRef[>..] = [],
    staging_sites: u64[>..] = [],
    dep_units: u32[>..] = [],
    seen_assoc_heads: dictionary<u64, u32> = dictionary<u64, u32>{},
    seen_assoc_names: Chars[>..] = [],
    seen_assoc_next: u32[>..] = [],
    seen_contracts: dictionary<u64, bool> = dictionary<u64, bool>{},
}

fn hashCharsFnv(s: Chars) -> u64 {
    var h: u64 = FNV_OFFSET;
    for b in s { h = (h ^ (b as u64)) * FNV_PRIME; }
    return h;
}

fn enqueueBody(ctx: ImplHashCtx&, units: const Module[:], from_unit: u32, ref_: BindingRef) {
    let resolved = resolveBindingTargetTracked(units, from_unit, ref_, ctx.dep_units);
    if resolved.unit == 0 || resolved.binding == 0 { return; }
    if !ctx.visited.contains(resolved) {
        ctx.visited.insert(resolved, true);
        ctx.queue.push(resolved);
    }
}

fn buildAssocIndex(shared: SharedHashIndex&, units: const Module[:]) {
    shared.assoc_indexed = true;
    // Traverse in reverse so linked-list prepends yield exact forward (unit, associated) order.
    var ui = units.len;
    while ui > 0 {
        ui -= 1;
        let u_mod .= units[ui];
        var ai = u_mod.associated.len;
        while ai > 0 {
            ai -= 1;
            let assoc = u_mod.associated[ai];
            let asp = u_mod.fieldSpelling(assoc.member);
            if !asp.present { continue; }
            let h = hashCharsFnv(asp.value);
            var prev: u32 = 0;
            let found = shared.assoc_heads.get(h);
            if found { prev = found; }
            let idx = (shared.assoc_entries.len as u32) + 1;
            shared.assoc_entries.push(AssocIndexEntry { unit: u_mod.unit, identity: assoc.identity, target: assoc.target, name: asp.value, next: prev });
            shared.assoc_heads.insert(h, idx);
        }
    }
}

fn buildImplIndex(shared: SharedHashIndex&, units: const Module[:]) {
    shared.impl_indexed = true;
    // Traverse in reverse so linked-list prepends yield exact forward (unit, impl, member) order.
    var ui = units.len;
    while ui > 0 {
        ui -= 1;
        let u_mod .= units[ui];
        var ii = u_mod.implementations.len;
        while ii > 0 {
            ii -= 1;
            let impl_ = u_mod.implementations[ii];
            let key = ((impl_.contract.unit as u64) << 32) | (impl_.contract.decl as u64);
            let m_start = impl_.members.start as i64;
            var mi = (impl_.members.len as i64);
            while mi > 0 {
                mi -= 1;
                let im = u_mod.implementation_members[m_start + mi];
                if im.kind != blot_reuse_principal_interface::ImplementationMemberKind.value { continue; }
                var prev: u32 = 0;
                let found = shared.impl_heads.get(key);
                if found { prev = found; }
                let idx = (shared.impl_entries.len as u32) + 1;
                shared.impl_entries.push(ImplIndexEntry { unit: u_mod.unit, target: BindingRef { im.target.unit, im.target.binding }, next: prev });
                shared.impl_heads.insert(key, idx);
            }
        }
    }
}

fn enqueueAssociatedBySpelling(ctx: ImplHashCtx&, shared: SharedHashIndex&, units: const Module[:], want: Chars) {
    let h = hashCharsFnv(want);
    var cur: u32 = 0;
    let sh = ctx.seen_assoc_heads.get(h);
    if sh { cur = sh; }
    var at = cur;
    while at != 0 {
        if ctx.seen_assoc_names[(at - 1) as i64] == want { return; }
        at = ctx.seen_assoc_next[(at - 1) as i64];
    }
    let sid = (ctx.seen_assoc_names.len as u32) + 1;
    ctx.seen_assoc_names.push(want);
    ctx.seen_assoc_next.push(cur);
    ctx.seen_assoc_heads.insert(h, sid);
    if !shared.assoc_indexed { buildAssocIndex(shared, units); }
    let head = shared.assoc_heads.get(h);
    if !head { return; }
    var entry_idx: u32 = head;
    while entry_idx != 0 {
        let e = shared.assoc_entries[(entry_idx - 1) as i64];
        if e.name == want {
            enqueueBody(ctx, units, e.unit, e.target);
        }
        entry_idx = e.next;
    }
}

fn enqueueAssociatedForNominal(ctx: ImplHashCtx&, shared: SharedHashIndex&, units: const Module[:], nominal: Identity, want: Chars) {
    if !shared.assoc_indexed { buildAssocIndex(shared, units); }
    let h = hashCharsFnv(want);
    let head = shared.assoc_heads.get(h);
    if !head { return; }
    var entry_idx: u32 = head;
    while entry_idx != 0 {
        let e = shared.assoc_entries[(entry_idx - 1) as i64];
        if e.identity == nominal && e.name == want {
            enqueueBody(ctx, units, e.unit, e.target);
        }
        entry_idx = e.next;
    }
}

fn enqueueContractImpls(ctx: ImplHashCtx&, shared: SharedHashIndex&, units: const Module[:], contract: Identity) {
    let key = ((contract.unit as u64) << 32) | (contract.decl as u64);
    if ctx.seen_contracts.contains(key) { return; }
    ctx.seen_contracts.insert(key, true);
    if !shared.impl_indexed { buildImplIndex(shared, units); }
    let head = shared.impl_heads.get(key);
    if !head { return; }
    var entry_idx: u32 = head;
    while entry_idx != 0 {
        let e = shared.impl_entries[(entry_idx - 1) as i64];
        enqueueBody(ctx, units, e.unit, e.target);
        entry_idx = e.next;
    }
}

fn recordStagingSite(ctx: ImplHashCtx&, unit: u32, node_id: u32) {
    let key = ((unit as u64) << 32) | (node_id as u64);
    for existing in ctx.staging_sites { if existing == key { return; } }
    ctx.staging_sites.push(key);
}

recursive fn hashPattern(ctx: ImplHashCtx&, shared: SharedHashIndex&, units: const Module[:], m: const Module&, pid: u32, depth: i64) {
    if pid == 0 || depth > 128 || (pid as i64) >= m.patterns.len { fnvByte(ctx.h, 0); return; }
    let p = m.pattern(pid);
    fnvByte(ctx.h, blot_check_core::patternTagCode(p.tag) as u8);
    match p.tag {
        constant => { fnvU32Le(ctx.h, p.a); },
        value => { hashNode(ctx, shared, units, m, p.a, depth + 1); },
        product => {
            let kids = m.patternChildren(pid);
            fnvUleb(ctx.h, kids.len as u64);
            for k in kids { hashPattern(ctx, shared, units, m, k, depth + 1); }
        },
        constructor => {
            let c = m.constructor(p.a);
            fnvU32Le(ctx.h, c.tag);
            hashPattern(ctx, shared, units, m, p.b, depth + 1);
        },
        record_payload => {
            fnvU32Le(ctx.h, p.a);
            hashPattern(ctx, shared, units, m, p.b, depth + 1);
        },
        _ => {},
    }
}

recursive fn hashNode(ctx: ImplHashCtx&, shared: SharedHashIndex&, units: const Module[:], m: const Module&, id: u32, depth: i64) {
    if id == 0 || depth > 256 || (id as i64) >= m.nodes.len { fnvByte(ctx.h, 0); return; }
    let n = m.node(id);
    fnvByte(ctx.h, blot_check_core::tagCode(n.tag) as u8);
    fnvByte(ctx.h, blot_check_core::opCode(n.op) as u8);
    match n.tag {
        constant => {
            fnvU32Le(ctx.h, n.a);
            fnvByte(ctx.h, blot_check_types::tagCode(m.types.node(n.ty).tag) as u8);
        },
        reference => {
            let r = m.reference(id);
            if r.unit == 0 && (r.binding as i64) < m.bindings.len {
                let bk = m.binding(r.binding).kind;
                if bk == blot_reuse_principal_interface::Kind.global || bk == blot_reuse_principal_interface::Kind.external {
                    fnvByte(ctx.h, 1);
                    enqueueBody(ctx, units, m.unit, r);
                } else {
                    fnvByte(ctx.h, 2);
                }
            } else {
                fnvByte(ctx.h, 1);
                enqueueBody(ctx, units, m.unit, r);
            }
        },
        call => {
            let ci = m.call(id);
            enqueueBody(ctx, units, m.unit, ci.target);
            fnvU32Le(ctx.h, ci.own);
            fnvUleb(ctx.h, ci.arguments.len as u64);
            for arg in ci.arguments { hashNode(ctx, shared, units, m, arg, depth + 1); }
        },
        scalar, logical, apply, type_same, effect_provider, handle => {
            fnvU32Le(ctx.h, n.c);
            hashNode(ctx, shared, units, m, n.a, depth + 1);
            hashNode(ctx, shared, units, m, n.b, depth + 1);
        },
        staging => {
            recordStagingSite(ctx, m.unit, id);
            fnvU32Le(ctx.h, n.c);
            hashNode(ctx, shared, units, m, n.a, depth + 1);
            hashNode(ctx, shared, units, m, n.b, depth + 1);
        },
        associated => {
            let sp = m.fieldSpelling(n.c);
            if sp.present {
                fnvStr(ctx.h, sp.value);
                enqueueAssociatedBySpelling(ctx, shared, units, sp.value);
            }
            hashNode(ctx, shared, units, m, n.a, depth + 1);
            hashNode(ctx, shared, units, m, n.b, depth + 1);
        },
        result_associated => {
            let sp = m.fieldSpelling(n.b);
            if sp.present {
                fnvStr(ctx.h, sp.value);
                enqueueAssociatedBySpelling(ctx, shared, units, sp.value);
            }
            hashNode(ctx, shared, units, m, n.a, depth + 1);
        },
        if_value, if_stmt, state_provider, comptime_if => {
            hashNode(ctx, shared, units, m, n.a, depth + 1);
            hashNode(ctx, shared, units, m, n.b, depth + 1);
            hashNode(ctx, shared, units, m, n.c, depth + 1);
        },
        block_, suite, product, array, array_op, storage => {
            fnvU32Le(ctx.h, n.c);
            let kids = m.children(id);
            fnvUleb(ctx.h, kids.len as u64);
            for k in kids { hashNode(ctx, shared, units, m, k, depth + 1); }
        },
        contract_method => {
            fnvU32Le(ctx.h, n.c);
            if (n.a as i64) < m.member_templates.len {
                let tmpl = m.member_templates[n.a];
                enqueueContractImpls(ctx, shared, units, tmpl.contract);
            }
            let kids = m.children(id);
            fnvUleb(ctx.h, kids.len as u64);
            for k in kids { hashNode(ctx, shared, units, m, k, depth + 1); }
        },
        record => {
            let kids = m.children(id);
            let dests = m.recordDestinations(id);
            fnvUleb(ctx.h, kids.len as u64);
            for i in 0..kids.len {
                fnvU32Le(ctx.h, dests[i]);
                hashNode(ctx, shared, units, m, kids[i], depth + 1);
            }
        },
        bind => {
            fnvU32Le(ctx.h, n.c);
            hashNode(ctx, shared, units, m, n.b, depth + 1);
        },
        return_ => { hashNode(ctx, shared, units, m, n.a, depth + 1); },
        construct => {
            let c = m.constructor(n.a);
            fnvU32Le(ctx.h, c.tag);
            fnvU32Le(ctx.h, n.c);
            hashNode(ctx, shared, units, m, n.b, depth + 1);
        },
        constructor_function => {
            let c = m.constructor(n.a);
            fnvU32Le(ctx.h, c.tag);
        },
        primitive_function => {
            let p = m.primitive(id);
            fnvByte(ctx.h, p.arity);
            fnvByte(ctx.h, blot_check_core::opCode(p.op) as u8);
        },
        project => {
            let pr = m.projection(n.b);
            let sp = m.fieldSpelling(pr.field);
            if sp.present { fnvStr(ctx.h, sp.value); }
            // Also enqueue any matching associated member target on that nominal so impl changes invalidate impl_hash.
            if pr.nominal.decl != 0 && sp.present {
                enqueueAssociatedForNominal(ctx, shared, units, pr.nominal, sp.value);
            }
            hashNode(ctx, shared, units, m, n.a, depth + 1);
        },
        pattern_bind => {
            hashPattern(ctx, shared, units, m, n.a, depth + 1);
            hashNode(ctx, shared, units, m, n.b, depth + 1);
            hashNode(ctx, shared, units, m, n.c, depth + 1);
        },
        match_ => {
            let ins = m.matchInputs(id);
            fnvUleb(ctx.h, ins.len as u64);
            for x in ins { hashNode(ctx, shared, units, m, x, depth + 1); }
            let arms = m.matchArms(id);
            fnvUleb(ctx.h, arms.len as u64);
            for arm in arms {
                let rows = m.armRows(arm);
                fnvUleb(ctx.h, rows.len as u64);
                for row in rows {
                    for p in m.rowPatterns(row) { hashPattern(ctx, shared, units, m, p, depth + 1); }
                }
                hashNode(ctx, shared, units, m, arm.guard_, depth + 1);
                hashNode(ctx, shared, units, m, arm.body, depth + 1);
            }
        },
        loop_ => {
            let li = m.loopInfo(id);
            fnvByte(ctx.h, blot_check_core::loopKindCode(li.kind) as u8);
            hashNode(ctx, shared, units, m, li.first, depth + 1);
            hashNode(ctx, shared, units, m, li.end, depth + 1);
            hashPattern(ctx, shared, units, m, li.pattern, depth + 1);
            hashNode(ctx, shared, units, m, li.body, depth + 1);
        },
        break_ => {
            for v in m.breakValues(id) { hashNode(ctx, shared, units, m, v, depth + 1); }
        },
        update => {
            let ui = m.updateInfo(id);
            hashNode(ctx, shared, units, m, ui.root, depth + 1);
            for st in m.updateSelectors(id) {
                fnvByte(ctx.h, blot_check_core::updateKindCode(st.kind) as u8);
                if st.kind == blot_check_core::UpdateKind.index { hashNode(ctx, shared, units, m, st.index, depth + 1); }
            }
            hashNode(ctx, shared, units, m, ui.value, depth + 1);
        },
        closure => {
            let cl = m.closure(id);
            hashNode(ctx, shared, units, m, cl.body, depth + 1);
        },
        panic => {
            fnvStr(ctx.h, m.panicMessage(id));
        },
        fork_ => {
            fnvU32Le(ctx.h, n.b);
            hashNode(ctx, shared, units, m, n.a, depth + 1);
        },
        with_handle => {
            for ch in m.children(id) { hashNode(ctx, shared, units, m, ch, depth + 1); }
            hashNode(ctx, shared, units, m, n.a, depth + 1);
        },
        comptime_for => {
            if m.extra[n.c + 2] == 2 { fnvByte(ctx.h, 2); }
            hashNode(ctx, shared, units, m, n.b, depth + 1);
        },
        comptime_meta => {
            fnvU32Le(ctx.h, n.c);
            if n.c == 0 { hashNode(ctx, shared, units, m, n.a, depth + 1); }
            else if n.c == 8 || n.c == 9 { hashNode(ctx, shared, units, m, n.b, depth + 1); }
        },
        spark => {
            let si = m.sparkInfo(id);
            fnvByte(ctx.h, boolByte(si.is_range));
            hashNode(ctx, shared, units, m, si.source, depth + 1);
            if si.end != 0 { hashNode(ctx, shared, units, m, si.end, depth + 1); }
            hashPattern(ctx, shared, units, m, si.pattern, depth + 1);
            hashNode(ctx, shared, units, m, si.body, depth + 1);
        },
        flat_op => {
            fnvU32Le(ctx.h, n.c);
            if n.c <= blot_check_core::flat_op_process_binding_hash {
                hashNode(ctx, shared, units, m, n.a, depth + 1);
            } else {
                fnvU32Le(ctx.h, n.a);
            }
        },
        _ => {},
    }
}

fn drainImplHashQueue(ctx: ImplHashCtx&, shared: SharedHashIndex&, units: const Module[:]) {
    var cursor: i64 = 0;
    while cursor < ctx.queue.len {
        let target = ctx.queue[cursor];
        cursor += 1;
        if !hasUnit(units, target.unit) { continue; }
        let tm .= units[target.unit - 1];
        let body .= tm.body(target.binding);
        if body {
            fnvByte(ctx.h, 1);
            fnvByte(ctx.h, boolByte(body.is_function));
            fnvByte(ctx.h, boolByte(body.is_kernel));
            fnvUleb(ctx.h, body.parameters.len as u64);
            hashNode(ctx, shared, units, tm, body.root, 0);
        } else if (target.binding as i64) < tm.bindings.len {
            let bi = tm.binding(target.binding);
            fnvByte(ctx.h, 2);
            if bi.initializer != 0 { hashNode(ctx, shared, units, tm, bi.initializer, 0); }
        }
    }
}

fn computeImplHash(shared: SharedHashIndex&, units: const Module[:], entry: u32, decl: blot_check_core::KernelDecl, all_staging_sites: u64[>..]&, dep_units: u32[>..]&) -> u64 {
    var ctx = ImplHashCtx {};
    fnvByte(ctx.h, 0x03);
    fnvByte(ctx.h, COMPILER_SEMANTICS_VERSION);
    if decl.has_context {
        enqueueBody(ctx, units, entry, decl.prepare_target);
    }
    enqueueBody(ctx, units, entry, decl.run_target);
    drainImplHashQueue(ctx, shared, units);
    for u in ctx.dep_units { noteDepUnit(dep_units, u); }
    for site in ctx.staging_sites {
        var seen = false;
        for ex in all_staging_sites { if ex == site { seen = true; break; } }
        if !seen { all_staging_sites.push(site); }
    }
    return ctx.h.h;
}

fn computeProcessClosureHash(shared: SharedHashIndex&, units: const Module[:], entry: u32, decl: blot_check_core::ProcessDecl, dep_units: u32[>..]&) -> u64 {
    var ctx = ImplHashCtx {};
    fnvByte(ctx.h, 0x05);
    fnvByte(ctx.h, COMPILER_SEMANTICS_VERSION);
    enqueueBody(ctx, units, entry, decl.init_target);
    enqueueBody(ctx, units, entry, decl.step_target);
    drainImplHashQueue(ctx, shared, units);
    for u in ctx.dep_units { noteDepUnit(dep_units, u); }
    return ctx.h.h;
}

fn sortU64(items: u64[>..]& ) {
    for i in 1..items.len {
        let key = items[i];
        var j = i;
        while j > 0 && items[j - 1] > key {
            items[j] = items[j - 1];
            j -= 1;
        }
        items[j] = key;
    }
}

fn hashWireSchemaFull(h: Hasher&, info: const ProgramInfo&, s: WireSchema) {
    fnvByte(h, s.kind);
    fnvByte(h, s.wire_tag);
    fnvUleb(h, s.stride as u64);
    if s.kind == SCHEMA_KIND_FLAT_FIXED {
        for ti in 0..(s.tags_len as i64) {
            fnvByte(h, info.word_tags[(s.tags_start as i64) + ti]);
        }
    }
    fnvU64Le(h, s.schema_hash);
}

fn isCoreArrayType(m: const Module&, tid: TId) -> bool {
    var cur = tid;
    for _ in 0..32 {
        if cur == 0 || (cur as i64) >= m.types.nodes.len { return false; }
        let n = m.types.node(cur);
        if n.tag == blot_check_types::Tag.usage || n.tag == blot_check_types::Tag.forall { cur = n.a; continue; }
        if n.tag == blot_check_types::Tag.array { return true; }
        if blot_check_storage_types::info(m.types, cur).present { return true; }
        return false;
    }
    return false;
}

fn unwrapCoreType(m: const Module&, tid: TId) -> TId {
    var cur = tid;
    for _ in 0..32 {
        if cur == 0 || (cur as i64) >= m.types.nodes.len { return cur; }
        let n = m.types.node(cur);
        if n.tag == blot_check_types::Tag.usage || n.tag == blot_check_types::Tag.forall { cur = n.a; continue; }
        return cur;
    }
    return cur;
}

fn computeExportedStorage(units: const Module[:], entry: u32, info: const ProgramInfo&) -> bool {
    if info.kernels.len != 0 { return true; }
    for p in info.processes {
        if p.config_schema.wire_tag >= 5 || p.cmd_schema.wire_tag >= 5 || p.reply_schema.wire_tag >= 5 { return true; }
    }
    if !hasUnit(units, entry) { return false; }
    let m .= units[entry - 1];
    for body in m.bodies {
        if !body.exported || (body.binding as i64) >= m.bindings.len { continue; }
        let bty = unwrapCoreType(m, m.binding(body.binding).ty);
        if bty == 0 || (bty as i64) >= m.types.nodes.len { continue; }
        let fn_node = m.types.node(bty);
        if fn_node.tag != blot_check_types::Tag.function { continue; }
        let param_ty = unwrapCoreType(m, fn_node.a);
        let res_ty = unwrapCoreType(m, fn_node.b);
        if isCoreArrayType(m, param_ty) || isCoreArrayType(m, res_ty) { return true; }
        if param_ty != 0 && (param_ty as i64) < m.types.nodes.len {
            let pn = m.types.node(param_ty);
            if pn.tag == blot_check_types::Tag.function && (isCoreArrayType(m, pn.a) || isCoreArrayType(m, pn.b)) { return true; }
        }
    }
    return false;
}

fn computeNonStagedReceipt(units: const Module[:], entry: u32, info: const ProgramInfo&) -> NonStagedReceipt {
    let has_fork = info.has_fork;
    let has_persistent = info.has_persistent_state;
    var h = Hasher {};
    fnvByte(h, 0x10);
    if hasUnit(units, entry) {
        let m .= units[entry - 1];
        fnvUleb(h, m.kernels.len as u64);
        for ki in 0..info.kernels.len {
            let decl = m.kernels[ki];
            let kinfo = info.kernels[ki];
            fnvStr(h, m.name(decl.name));
            fnvByte(h, kinfo.flags);
            if kinfo.has_context { hashWireSchemaFull(h, info, kinfo.ctx_schema); }
            hashWireSchemaFull(h, info, kinfo.in_schema);
            hashWireSchemaFull(h, info, kinfo.out_schema);
            fnvU64Le(h, kinfo.io_schema_hash);
            fnvU64Le(h, kinfo.impl_hash);
            fnvU64Le(h, kinfo.binding_hash);
        }
        fnvUleb(h, m.processes.len as u64);
        for pi in 0..info.processes.len {
            let decl = m.processes[pi];
            let pinfo = info.processes[pi];
            fnvStr(h, m.name(decl.name));
            hashWireSchemaFull(h, info, pinfo.config_schema);
            hashWireSchemaFull(h, info, pinfo.cmd_schema);
            hashWireSchemaFull(h, info, pinfo.reply_schema);
        }
        fnvU64Le(h, info.process_closures_digest);
    }
    return NonStagedReceipt {
        has_fork: has_fork,
        has_persistent_state: has_persistent,
        exported_storage: computeExportedStorage(units, entry, info),
        kernel_count: info.kernels.len as u32,
        process_count: info.processes.len as u32,
        kernel_staging_sites_count: info.kernel_staging_sites_count,
        kernel_staging_sites_digest: info.kernel_staging_sites_digest,
        schemas_and_closures_digest: h.h,
    };
}

fn verifyNamedFunctionArity(units: const Module[:], from_unit: u32, ref_: BindingRef, expected_arity: i64) -> bool {
    let resolved = resolveBindingTarget(units, from_unit, ref_);
    if !hasUnit(units, resolved.unit) || resolved.binding == 0 { return false; }
    let tm .= units[resolved.unit - 1];
    let body .= tm.body(resolved.binding);
    if !body || !body.is_function || body.exported || body.runtime { return false; }
    return (body.parameters.len as i64) == expected_arity;
}

// Validate all `#kernel` and `#process` declarations in `entry` module and compute
// canonical wire schemas and hashes.
fn analyze(units: const Module[:], entry: u32, info: ProgramInfo&) {
    analyzeWithForkFlags(units, entry, default<const u8[:]>(), info);
}
fn analyzeWithForkFlags(units: const Module[:], entry: u32, fork_flags: const u8[:], info: ProgramInfo&) {
    if !hasUnit(units, entry) { return; }
    // `#kernel` and `#process` are only valid in the entry module (§2.3).
    // Scan `has_fork` in the same single pass (reusing precomputed worker/retained flags
    // when available) so neither `computeNonStagedReceipt` nor `direct/emit::runtime_`
    // has to re-walk every Core node of every module.
    for u, ui in units {
        if u.unit != entry {
            if u.kernels.len != 0 {
                info.issue = Issue { failed: true, unit: u.unit, span: u.kernels[0].span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#kernel is only valid in the entry module" };
                return;
            }
            if u.processes.len != 0 {
                info.issue = Issue { failed: true, unit: u.unit, span: u.processes[0].span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#process is only valid in the entry module" };
                return;
            }
        }
        if !info.has_fork {
            if ui < fork_flags.len && fork_flags[ui] != 0 {
                if fork_flags[ui] == 2 { info.has_fork = true; }
            } else {
                for node in u.nodes {
                    if node.tag == blot_check_core::Tag.fork_ { info.has_fork = true; break; }
                }
            }
        }
    }
    let m .= units[entry - 1];
    info.has_persistent_state = m.kernels.len != 0 || m.processes.len != 0;
    if !info.has_persistent_state { return; }
    var cache = UnitIdCache {};
    initUnitIdCache(units, cache);
    var shared_hash_index = SharedHashIndex {};
    let empty_subst: SubstEntry[0] = [];
    var all_kernel_staging_sites: u64[>..] = [];

    for ki in 0..m.kernels.len {
        let decl = m.kernels[ki];
        var kinfo = KernelInfo { decl_index: ki as u32, has_context: decl.has_context };
        // Verify named-function targets and exact arities across modules.
        if decl.has_context {
            if !verifyNamedFunctionArity(units, entry, decl.prepare_target, 1) {
                info.issue = Issue { failed: true, unit: entry, span: decl.span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#kernel prepare must resolve to a 1-argument named function" };
                return;
            }
            if !verifyNamedFunctionArity(units, entry, decl.run_target, 2) {
                info.issue = Issue { failed: true, unit: entry, span: decl.span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#kernel run must resolve to a 2-argument named function" };
                return;
            }
            // Validate WireCtx (`#[U32]`, `#[F32]`, or `FlatNumeric`).
            let ctx_s, ctx_ok = buildWireSchema(units, cache, info.word_tags, entry, decl.ctx_type, false, true, false, false);
            if !ctx_ok {
                info.issue = Issue { failed: true, unit: entry, span: decl.span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#kernel WireCtx must be FlatNumeric, #[U32], or #[F32]" };
                return;
            }
            kinfo.ctx_schema = ctx_s;
            // Validate PreparedCtx is PersistentSafe.
            let ps_amark = cache.active_pool.len;
            let ps_ok = decl.prepared_type != 0 && checkPersistentSafe(units, cache, entry, decl.prepared_type, 0, 0, ps_amark, 0);
            cache.active_pool.resize(ps_amark);
            if !ps_ok {
                info.issue = Issue { failed: true, unit: entry, span: decl.span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#kernel PreparedCtx must be PersistentSafe" };
                return;
            }
        } else {
            if !verifyNamedFunctionArity(units, entry, decl.run_target, 1) {
                info.issue = Issue { failed: true, unit: entry, span: decl.span, code: blot_check_diagnostic_code::Code.kernel_type, message: "stateless #kernel must be a 1-argument named function" };
                return;
            }
            kinfo.ctx_schema = WireSchema { kind: SCHEMA_KIND_UNIT, wire_tag: WIRE_TAG_UNIT, stride: 0, schema_hash: 0 };
        }
        // Item must be non-zero-width FlatNumeric.
        let in_s, in_ok = buildWireSchema(units, cache, info.word_tags, entry, decl.item_type, false, false, false, false);
        if !in_ok {
            info.issue = Issue { failed: true, unit: entry, span: decl.span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#kernel Item must be a non-zero-width FlatNumeric type within the transport budget" };
            return;
        }
        kinfo.in_schema = in_s;
        // Out must be FlatNumeric OR #[U32] / #[F32].
        let out_s, out_ok = buildWireSchema(units, cache, info.word_tags, entry, decl.out_type, false, true, true, false);
        if !out_ok {
            info.issue = Issue { failed: true, unit: entry, span: decl.span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#kernel Out must be FlatNumeric, #[U32], or #[F32]" };
            return;
        }
        kinfo.out_schema = out_s;
        kinfo.variable_output = out_s.kind == SCHEMA_KIND_VAR_U32 || out_s.kind == SCHEMA_KIND_VAR_F32;
        var flags: u8 = 0;
        if kinfo.has_context { flags = flags | 1; }
        if kinfo.variable_output { flags = flags | 2; }
        kinfo.flags = flags;
        // io_schema_hash = fnv1a64(0x02 || in_schema_hash_le || out_schema_hash_le || [flags])
        var ioh = Hasher {};
        fnvByte(ioh, 0x02);
        fnvU64Le(ioh, kinfo.in_schema.schema_hash);
        fnvU64Le(ioh, kinfo.out_schema.schema_hash);
        fnvByte(ioh, flags);
        kinfo.io_schema_hash = ioh.h;
        // impl_hash
        kinfo.impl_hash = computeImplHash(shared_hash_index, units, entry, decl, all_kernel_staging_sites, info.dep_units);
        // binding_hash = fnv1a64(0x04 || ctx_schema_hash_le || in_schema_hash_le || out_schema_hash_le || [flags] || impl_hash_le)
        var bh = Hasher {};
        fnvByte(bh, 0x04);
        var ctx_h: u64 = 0;
        if kinfo.has_context { ctx_h = kinfo.ctx_schema.schema_hash; }
        fnvU64Le(bh, ctx_h);
        fnvU64Le(bh, kinfo.in_schema.schema_hash);
        fnvU64Le(bh, kinfo.out_schema.schema_hash);
        fnvByte(bh, flags);
        fnvU64Le(bh, kinfo.impl_hash);
        kinfo.binding_hash = bh.h;
        info.kernels.push(kinfo);
    }
    sortU64(all_kernel_staging_sites);
    info.kernel_staging_sites_count = all_kernel_staging_sites.len as u32;
    var sth = Hasher {};
    fnvByte(sth, 0x11);
    for site in all_kernel_staging_sites { fnvU64Le(sth, site); }
    info.kernel_staging_sites_digest = sth.h;

    var pch = Hasher {};
    fnvByte(pch, 0x12);
    for pi in 0..m.processes.len {
        let decl = m.processes[pi];
        var pinfo = ProcessInfo { decl_index: pi as u32 };
        if !verifyNamedFunctionArity(units, entry, decl.init_target, 1) {
            info.issue = Issue { failed: true, unit: entry, span: decl.span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#process init must resolve to a 1-argument named function" };
            return;
        }
        if !verifyNamedFunctionArity(units, entry, decl.step_target, 2) {
            info.issue = Issue { failed: true, unit: entry, span: decl.span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#process step must resolve to a 2-argument named function" };
            return;
        }
        let cfg_s, cfg_ok = buildWireSchema(units, cache, info.word_tags, entry, decl.config_type, true, true, false, true);
        if !cfg_ok {
            info.issue = Issue { failed: true, unit: entry, span: decl.span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#process Config must be Unit, FlatNumeric, #[U32], or #[F32]" };
            return;
        }
        let cmd_s, cmd_ok = buildWireSchema(units, cache, info.word_tags, entry, decl.cmd_type, true, true, false, true);
        if !cmd_ok {
            info.issue = Issue { failed: true, unit: entry, span: decl.span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#process Cmd must be Unit, FlatNumeric, #[U32], or #[F32]" };
            return;
        }
        let rep_s, rep_ok = buildWireSchema(units, cache, info.word_tags, entry, decl.reply_type, true, true, false, true);
        if !rep_ok {
            info.issue = Issue { failed: true, unit: entry, span: decl.span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#process Reply must be Unit, FlatNumeric, #[U32], or #[F32]" };
            return;
        }
        let ps_amark = cache.active_pool.len;
        let ps_ok = decl.state_type != 0 && checkPersistentSafe(units, cache, entry, decl.state_type, 0, 0, ps_amark, 0);
        cache.active_pool.resize(ps_amark);
        if !ps_ok {
            info.issue = Issue { failed: true, unit: entry, span: decl.span, code: blot_check_diagnostic_code::Code.kernel_type, message: "#process State must be PersistentSafe" };
            return;
        }
        pinfo.config_schema = cfg_s;
        pinfo.cmd_schema = cmd_s;
        pinfo.reply_schema = rep_s;
        var pbh = Hasher {};
        fnvByte(pbh, 0x13);
        fnvU64Le(pbh, cfg_s.schema_hash);
        fnvU64Le(pbh, cmd_s.schema_hash);
        fnvU64Le(pbh, rep_s.schema_hash);
        pinfo.binding_hash = pbh.h;
        fnvU64Le(pch, computeProcessClosureHash(shared_hash_index, units, entry, decl, info.dep_units));
        info.processes.push(pinfo);
    }
    info.process_closures_digest = pch.h;
    noteDepUnit(info.dep_units, entry);
    for u in cache.dep_units { noteDepUnit(info.dep_units, u); }
}
