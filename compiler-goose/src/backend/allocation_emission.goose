namespace blot_backend_allocation_emission;
import check.core;
import .runtime_ir;
import .runtime_identity;
import .wasm;
import .backend_timing;
import support.option;

let max_sites: i64 = 16384;
enum Kind { closure_storage, constructor_storage, aggregate_storage, boxed_constant, call_materialization, array_storage, other_materialization }
struct Site {
    filename: u8[160] = [0; 160], filename_len: u8 = 0, filename_truncated: bool = false, unit: u32 = 0,
    span: blot_check_core::Span, kind: Kind = Kind.other_materialization, requested_bytes: blot_support::Option<u32>, emissions: u32 = 1,
}
struct Snapshot { sites: Site[>..<]&, omitted: i64 = 0 }
fn clone(source: Snapshot&, sites: Site[>..<]&) -> Snapshot { sites.clear(); sites.append(source.sites[..]); return Snapshot { sites: sites, omitted: source.omitted }; }
fn deinit(snapshot: Snapshot&) { snapshot.sites.clear(); snapshot.omitted = 0; }
fn category(tag: blot_check_core::Tag) -> Kind {
    if tag == blot_check_core::Tag.closure { return Kind.closure_storage; }
    if tag == blot_check_core::Tag.construct { return Kind.constructor_storage; }
    if tag == blot_check_core::Tag.product || tag == blot_check_core::Tag.record || tag == blot_check_core::Tag.record_merge { return Kind.aggregate_storage; }
    if tag == blot_check_core::Tag.constant { return Kind.boxed_constant; }
    if tag == blot_check_core::Tag.call || tag == blot_check_core::Tag.apply { return Kind.call_materialization; }
    if tag == blot_check_core::Tag.array || tag == blot_check_core::Tag.array_op || tag == blot_check_core::Tag.update { return Kind.array_storage; }
    return Kind.other_materialization;
}
fn capture(sites: Site[>..<]&, units: const blot_check_core::Module[:], names: blot_support::Option<blot_backend_runtime_identity::View>, module: blot_backend_wasm::Module&, entry: u32, prelude: u32) -> Snapshot {
    sites.clear(); var omitted = 0;
    for pass in 0..2 {
        for record in module.semantic_sites {
            if record.kind != blot_backend_wasm::SemanticKind.allocation || record.unit == 0 || record.unit > units.len || record.unit == prelude || (record.unit == entry) != (pass == 0) { continue; }
            let source .= units[record.unit - 1];
            if record.node == 0 || record.node >= source.nodes.len || record.function >= module.functions.len { continue; }
            let span = source.span(record.node); if span.end <= span.start { continue; }
            let function = module.functions[record.function]; if record.place >= function.instructions.len { continue; }
            var bytes = blot_support::none<u32>();
            if record.place != 0 { let previous = module.instructions[function.instructions.start + record.place - 1]; if previous.op == blot_backend_runtime_ir::OP_i32_const && previous.operand != 0 { bytes = blot_support::some(previous.operand); } }
            let kind = category(source.node(record.node).tag); var found = false; let count = sites.len;
            for index in 0..count {
                let site = sites[index];
                if site.unit == record.unit && site.span == span && site.kind == kind && site.requested_bytes == bytes {
                    if sites[index].emissions != 4294967295 { sites[index].emissions++; } found = true; break;
                }
            }
            if found { continue; } if sites.len == max_sites { omitted++; continue; }
            var site = Site { unit: record.unit, span: span, kind: kind, requested_bytes: bytes }; var path: const u8[:] = "";
            if names.present { let value = blot_backend_runtime_identity::owner(names.value, record.unit); if value.present { path = value.value; } }
            var length = path.len; if length > 160 { length = 160; }
            while length != 0 && length < path.len && (path[length] & 192) == 128 { length--; }
            for index in 0..length { site.filename[index] = path[index]; } site.filename_len = length as u8; site.filename_truncated = length != path.len; sites.push(site);
        }
    }
    return Snapshot { sites: sites, omitted: omitted };
}
fn kindName(kind: Kind) -> const u8[:] {
    if kind == Kind.closure_storage { return "closure_storage"; } if kind == Kind.constructor_storage { return "constructor_storage"; }
    if kind == Kind.aggregate_storage { return "aggregate_storage"; } if kind == Kind.boxed_constant { return "boxed_constant"; }
    if kind == Kind.call_materialization { return "call_materialization"; } if kind == Kind.array_storage { return "array_storage"; } return "other_materialization";
}
fn jsonStringify(site: Site, out: u8[>..]&) {
    out.append("{\"filename\":"); blot_backend_backend_timing::jsonString(out, site.filename[..site.filename_len]);
    blot_backend_backend_timing::jsonField(out, "filename_truncated", site.filename_truncated); blot_backend_backend_timing::jsonField(out, "unit", site.unit);
    blot_backend_backend_timing::jsonField(out, "start", site.span.start); blot_backend_backend_timing::jsonField(out, "end", site.span.end);
    out.append(",\"offset_encoding\":\"utf8_bytes\",\"kind\":"); blot_backend_backend_timing::jsonString(out, kindName(site.kind)); out.append(",\"requested_bytes\":");
    if site.requested_bytes.present { format(out, site.requested_bytes.value); } else { out.append("null"); }
    blot_backend_backend_timing::jsonField(out, "emissions", site.emissions); out.push('}');
}
