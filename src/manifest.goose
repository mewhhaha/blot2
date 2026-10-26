import std;
import json;
import .model;
import .wasm;
import .plan;

fn manifest_error(diags: Diagnostic[>..]&) -> bool { loader_error(diags, 4011, 0) }
fn manifest_type(c: Core, name: const u8[:]) -> u32 {
    var tag:u32 = TY_INVALID;
    if name == "Unit" { tag = TY_UNIT; } if name == "Bool" { tag = TY_BOOL; }
    if name == "U32" { tag = TY_U32; } if name == "F32" { tag = TY_F32; }
    if tag != TY_INVALID { for t, i in c.types { if i != 0 && t.tag == tag { return i as u32; } } }
    for d in c.definitions {
        if d.kind == DEF_TYPE && d.module == 1 && d.visibility == VIS_PUBLIC && d.binders.count == 0 && name_bytes(c, d.name) == name { return d.type_id; }
    }
    return 0;
}
recursive fn manifest_substitute(b: CoreBuilder, type_id: u32, substitutions: Span, memo: u32[:], depth: u32) -> u32 {
    if depth > 64 || !id_ok(type_id, memo.len) { return 0; }
    if memo[type_id] != 0 { return memo[type_id]; }
    let t = b.types[type_id];
    if t.tag == TY_PARAM {
        for i in substitutions.count {
            let sub = b.substitutions[b.refs[substitutions.start + i]];
            if sub.binder == t.binder { memo[type_id] = sub.value; return sub.value; }
        }
        return 0;
    }
    // Scratch lives in the caller of this recursive SCC, by using append-only
    // Core refs/fields directly and retaining IDs instead of builder ownership.
    let child_start = b.refs.len as u32;
    for i in t.children.count { b.refs.push(0); }
    var changed = false;
    for i in t.children.count {
        let old = b.refs[t.children.start + i];
        let next = manifest_substitute(b, old, substitutions, memo, depth + 1);
        if next == 0 { return 0; }
        b.refs[child_start + i] = next; if old != next { changed = true; }
    }
    let field_start = b.refs.len as u32;
    for i in t.fields.count { b.refs.push(0); }
    for i in t.fields.count {
        let field = b.fields[b.refs[t.fields.start + i]];
        let next = manifest_substitute(b, field.type_id, substitutions, memo, depth + 1);
        if next == 0 { return 0; }
        let id = b.fields.len as u32;
        b.fields.push(Field { name: field.name, type_id: next, offset: field.offset, tag: field.tag });
        b.refs[field_start + i] = id; if field.type_id != next { changed = true; }
    }
    if !changed { memo[type_id] = type_id; return type_id; }
    var copy = t;
    copy.children = Span { child_start, t.children.count };
    copy.fields = Span { field_start, t.fields.count };
    let id = b.types.len as u32; b.types.push(copy); memo[type_id] = id; return id;
}
fn configure_bridge(path: const u8[:], b: CoreBuilder, diags: Diagnostic[>..]&) -> bool {
    var source:u8[>..] = [];
    if !read_bounded(path, 65536, source) { return loader_error(diags, 4000, 0); }
    var doc:json::Node[>..] = []; var decoded:u8[>..] = [];
    let root, error = json::parse(source, doc, decoded);
    guard root else { return manifest_error(diags); }
    if doc.len > 1024 { return manifest_error(diags); }
    // Reject duplicate keys instead of letting member lookup choose one.
    for &node in doc {
        match node.val {
            Obj => {
                var a = node.first;
                while a {
                    var other = a.next;
                    while other { if a.key == other.key { return manifest_error(diags); } other .= other.next; }
                    a .= a.next;
                }
            },
            _ => {},
        }
    }
    let language, language_ok = json::as_string(json::member(root, "language"));
    let name, name_ok = json::as_string(json::member(root, "function"));
    let capacity, capacity_ok = json::as_i64(json::member(root, "output_capacity"));
    if !language_ok || language != "k1" || !name_ok || !capacity_ok || capacity < 0 || capacity > 4294967295 { return manifest_error(diags); }
    var fid:u32 = 0;
    for f, i in b.functions {
        if i != 0 && f.module == 1 && f.visibility == VIS_PUBLIC && name_bytes(core_view(b), f.name) == name { fid = i as u32; }
    }
    if fid == 0 { return manifest_error(diags); }
    let ct = b.contracts[b.functions[fid].contract];
    var substitutions:u32[>..] = [];
    let type_config = json::member(root, "types");
    var type_binders:u32 = 0;
    for i in ct.binders.count {
        let bid = b.refs[ct.binders.start + i]; let binder = b.binders[bid];
        if binder.kind != KIND_TYPE { continue; }
        type_binders++;
        let type_name, ok = json::as_string(json::member(type_config, name_bytes(core_view(b), binder.name)));
        if !ok { return manifest_error(diags); }
        let type_id = manifest_type(core_view(b), type_name);
        if type_id == 0 { return manifest_error(diags); }
        let sub = b.substitutions.len as u32; b.substitutions.push(Substitution { binder: bid, kind: KIND_TYPE, value: type_id }); substitutions.push(sub);
    }
    if type_config {
        match type_config.val { Obj object => { if object.count != type_binders { return manifest_error(diags); } }, _ => { return manifest_error(diags); } }
    } else if type_binders != 0 { return manifest_error(diags); }
    let subs = ref_span(b, substitutions);
    var memo:u32[>..] = []; for i in b.types.len { memo.push(0); }
    let argument = manifest_substitute(b, ct.arg, subs, memo, 0);
    let result = manifest_substitute(b, ct.result, subs, memo, 0);
    if argument == 0 || result == 0 { return manifest_error(diags); }
    let maxima_node = json::member(root, "input_maxima");
    guard maxima_node else { return manifest_error(diags); }
    match maxima_node.val { Arr => {}, _ => { return manifest_error(diags); } }
    var maxima:u32[>..] = [];
    json::each(maxima_node) { node =>
        let number, ok = json::as_i64(node);
        if !ok || number < 0 || number > 4294967295 { return manifest_error(diags) from configure_bridge; }
        maxima.push(number as u32);
    };
    let aid = terminal_type(core_view(b), argument);
    if aid == 0 || b.types[aid].tag != TY_RECORD { return manifest_error(diags); }
    let id = b.exports.len as u32;
    b.exports.push(Export { function: fid, name: b.functions[fid].name, kind: EXPORT_BRIDGE,
        arg_type: argument, result_type: result, substitutions: subs, fields: b.types[aid].fields,
        input_maxima: ref_span(b, maxima), output_capacity: capacity as u32, .. });
    b.functions[fid].export_id = id;
    return true;
}
fn finish_bridge_plans(b: CoreBuilder, diags: Diagnostic[>..]&) -> bool {
    for ex, index in b.exports {
        if index == 0 || ex.kind != EXPORT_BRIDGE { continue; }
        let ct = b.contracts[b.functions[ex.function].contract];
        let arg_id = terminal_type(core_view(b), ex.arg_type);
        let arg = b.types[arg_id];
        var bytes:u64 = 0; var inputs:u32 = 0; var outputs:u32 = 0;
        for i in arg.fields.count {
            let field = b.fields[b.refs[arg.fields.start + i]];
            let type_id = terminal_type(core_view(b), field.type_id); let t = b.types[type_id];
            if t.tag != TY_VIEW && t.tag != TY_DEST { continue; }
            if t.children.count != 1 { return manifest_error(diags); }
            let element = b.refs[t.children.start];
            let layout = b.layouts[layout_id(core_view(b), element)];
            var count:u32 = 0;
            if t.tag == TY_VIEW {
                if inputs >= ex.input_maxima.count { return manifest_error(diags); }
                count = b.refs[ex.input_maxima.start + inputs]; inputs++;
            } else { count = ex.output_capacity; outputs++; }
            if layout.size != 0 { bytes = (bytes + layout.align - 1) / layout.align * layout.align; bytes += count as u64 * layout.size; }
            if bytes > MAX_U32 { return manifest_error(diags); }
        }
        if outputs != 1 || inputs != ex.input_maxima.count { return manifest_error(diags); }
        let a = b.layouts[layout_id(core_view(b), ex.arg_type)];
        let r = b.layouts[layout_id(core_view(b), ex.result_type)];
        let frame:u64 = ((a.size as u64 + r.size + 23) / 4 * 4) + ct.frame;
        if frame > 16777216 || ct.depth >= 128 { return manifest_error(diags); }
        b.exports[index].work_bytes = bytes as u32;
        b.exports[index].frame = frame as u32;
        b.exports[index].depth = max(ct.depth, 2) + 2;
    }
    return true;
}

import .abi;
recursive fn manifest_wire_type(c: Core, type_id: u32, out:u8[>..]&, depth:u32) -> bool {
    if depth > 64 { return false; }
    let id = terminal_type(c, type_id); if id == 0 { return false; }
    let t = c.types[id]; let l = c.layouts[layout_id(c, id)];
    var kind:const u8[:] = "";
    if t.tag == TY_UNIT { kind = "unit"; } if t.tag == TY_BOOL { kind = "bool"; }
    if t.tag == TY_U32 { kind = "u32"; } if t.tag == TY_F32 { kind = "f32"; }
    if kind.len != 0 { format(out, "{\"kind\":\"", kind, "\",\"size\":", l.size, "}"); return true; }
    if t.tag != TY_TUPLE && t.tag != TY_RECORD && t.tag != TY_SUM { return false; }
    kind = if t.tag == TY_TUPLE { "tuple" } else if t.tag == TY_RECORD { "record" } else { "sum" };
    format(out, "{\"kind\":\"", kind, "\",\"size\":", l.size, ",\"fields\":[");
    let count = if t.fields.count != 0 { t.fields.count } else { t.children.count };
    var offset:u32 = if t.tag == TY_SUM { 4 } else { 0 };
    for i in count {
        if i != 0 { out.push(','); }
        let field_type = if t.fields.count != 0 { c.fields[c.refs[t.fields.start + i]].type_id } else { c.refs[t.children.start + i] };
        out.append("{\"name\":");
        if t.tag == TY_TUPLE { format(out, "\"", i, "\""); }
        else { json::format_string(out, name_bytes(c, c.fields[c.refs[t.fields.start + i]].name)); }
        format(out, ",\"offset\":", offset, ",\"type\":");
        if !manifest_wire_type(c, field_type, out, depth + 1) { return false; }
        out.push('}');
        if t.tag != TY_SUM { offset += c.layouts[layout_id(c, field_type)].size; }
    }
    out.append("]}"); return true;
}
fn manifest_json(c:Core,out:u8[>..]&)->bool { manifest_json_mode(c,out,false) }
fn manifest_json_telemetry(c:Core,out:u8[>..]&)->bool { manifest_json_mode(c,out,true) }
fn manifest_json_mode(c: Core, out:u8[>..]&, telemetry:bool) -> bool {
    let static_bytes, static_ok = wasm_static_bytes(c);
    if !static_ok { return false; }
    let map, map_ok = runtime::make_map(runtime::Config { static_bytes: static_bytes, telemetry: telemetry });
    if !map_ok { return false; }
    format(out, "{\"language\":\"k1\",\"abi\":\"K1-WASM32-ABI1\",\"abi_hash\":\"", ABI_HASH_HEX,
        "\",\"geometry_hash\":\"", k1hash::hex(memory_geometry_hash(map)), "\",\"memory\":{\"pages\":", map.pages,
        ",\"ingress\":", map.ingress, ",\"ingress_bytes\":", map.ingress_bytes,
        ",\"egress\":", map.egress, ",\"egress_bytes\":", map.egress_bytes, "},\"exports\":[");
    var exports:u32 = 0;
    for ex, index in c.exports {
        if index == 0 || ex.kind != EXPORT_BRIDGE { continue; }
        if exports != 0 { out.push(','); } exports++;
        format(out, "{\"id\":", index, ",\"name\":"); json::format_string(out, name_bytes(c, ex.name));
        format(out, ",\"output_capacity\":", ex.output_capacity, ",\"work_bytes\":", ex.work_bytes,
            ",\"frame\":", ex.frame, ",\"depth\":", ex.depth, ",\"fields\":[");
        let argument = c.types[terminal_type(c, ex.arg_type)]; var wire_offset:u32 = 0; var inputs:u32 = 0;
        var first = true;
        for i in argument.fields.count {
            let field = c.fields[c.refs[argument.fields.start + i]];
            let field_type = terminal_type(c, field.type_id); let t = c.types[field_type];
            if t.tag == TY_DEST { continue; }
            if !first { out.push(','); } first = false;
            out.append("{\"name\":"); json::format_string(out, name_bytes(c, field.name));
            format(out, ",\"offset\":", wire_offset, ",\"kind\":\"", if t.tag == TY_VIEW { "view" } else { "plain" }, "\"");
            if t.tag == TY_VIEW {
                format(out, ",\"max_count\":", c.refs[ex.input_maxima.start + inputs]); inputs++;
                out.append(",\"type\":"); if !manifest_wire_type(c, c.refs[t.children.start], out, 0) { return false; }
                wire_offset += 8;
            } else {
                out.append(",\"type\":"); if !manifest_wire_type(c, field_type, out, 0) { return false; }
                wire_offset += c.layouts[layout_id(c, field_type)].size;
            }
            out.push('}');
        }
        let result = c.types[terminal_type(c, ex.result_type)];
        let success_type = if result.fields.count != 0 { c.fields[c.refs[result.fields.start]].type_id } else { c.refs[result.children.start] };
        let package = c.types[terminal_type(c, success_type)];
        let view = c.types[terminal_type(c, c.refs[package.children.start])];
        format(out, "],\"fixed_bytes\":", wire_offset, ",\"result_type\":");
        if !manifest_wire_type(c, c.refs[view.children.start], out, 0) { return false; }
        out.push('}');
    }
    out.push(']');
    if telemetry {
        out.append(",\"telemetry\":{\"version\":1,\"word_export\":\"blot.telemetry\",\"counter_bits\":64,\"counters\":[");
        for i in runtime::TELEMETRY_COUNT { if i!=0 { out.push(','); } json::format_string(out,runtime::telemetry_name(i as u32)); }
        out.append("]}");
    }
    out.push('}'); return true;
}
fn embed_manifest(c: Core, wasm_bytes:u8[>..]&) -> bool {
    var manifest:u8[>..] = []; if !manifest_json(c, manifest) { return false; }
    var section:u8[>..] = []; let name = "blot.k1.manifest";
    wasm::uleb(section, name.len as u32); section.append(name); section.append(manifest);
    wasm_bytes.push(0); wasm::uleb(wasm_bytes, section.len as u32); wasm_bytes.append(section); return true;
}
