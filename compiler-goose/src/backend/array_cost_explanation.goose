// These bounded sites report ownership proof decisions, not allocator traffic.
namespace blot_backend_array_cost_explanation;
import check.core;
import .owned_arrays;
import support.error;
import support.pooled_buffer;
import support.json;
type Error = blot_error::Error;
let max_sites: i64 = 16384;
struct Site { filename: u8[160] = [0;160],filename_len: u8 = 0,filename_truncated: bool = false,unit: u32,span: blot_check_core::Span,decision: blot_backend_owned_arrays::Decision }
fn jsonStringify(site: const Site&,writer: blot_json::Writer&) -> Error {
    writer.beginObject(); writer.field("filename",site.filename[..site.filename_len]); writer.field("filename_truncated",site.filename_truncated); writer.field("unit",site.unit); writer.field("start",site.span.start); writer.field("end",site.span.end); writer.field("offset_encoding","utf8_bytes"); var result: const u8[:] = "copy_required"; if site.decision == blot_backend_owned_arrays::Decision.reused { result = "reuse_eligible"; } writer.field("result",result); writer.field("reason",site.decision); writer.endObject(); return writer.failure;
}
struct Snapshot { sites: Site[:] = default<Site[:]>(),omitted: i64 = 0 }
reusable[] var site_runs: Site[>..] = [];
struct Sites { storage: Site[:] = default<Site[:]>(),items: Site[:] = default<Site[:]>() }
reusable[] var scratch_runs: Site[>..] = [];
fn clone(snapshot: Snapshot) -> Snapshot,Error { let sites = site_runs.alloc_slice(snapshot.sites.len); for site,index in snapshot.sites { sites[index] = site; } return Snapshot { sites: sites,omitted: snapshot.omitted , ..},blot_error::Error.none; }
fn deinit(snapshot: Snapshot&) { if snapshot.sites.len != 0 { site_runs.free_slice(snapshot.sites); } snapshot = Snapshot {..}; }
fn analyze(units: const blot_check_core::Module[:],filenames: const u8[:][:],entry: u32,prelude: u32) -> Snapshot,Error {
    assert(filenames.len == units.len); var sites = Sites {..}; var omitted: i64 = 0;
    recursive fn gather() -> Error {
        for order in 0..units.len { var unit: u32; if order == 0 { unit = entry; } else if order < entry { unit = order as u32; } else { unit = (order + 1) as u32; } if unit == prelude { continue; } let module: const blot_check_core::Module& = units[unit - 1]; var proof,error = blot_backend_owned_arrays::initWithDecisions(units,unit,true); if error != blot_error::Error.none { return error; }
            recursive fn collectSites() -> Error { for maybe,index in proof.decisions { if !maybe.present { continue; } let span = module.span(index as u32); if span.end <= span.start { continue; } if sites.items.len == max_sites { omitted++; continue; } var site = Site { unit: unit,span: span,decision: maybe.value , ..}; let path = filenames[unit - 1]; var length = min(path.len,site.filename.len); while length != 0 && length < path.len && (path[length] & 0xc0) == 0x80 { length--; } for byte,index in path[..length] { site.filename[index] = byte; } site.filename_len = length as u8; site.filename_truncated = length != path.len; let appended = blot_support_pooled_buffer::push(sites,site,scratch_runs); if appended != blot_error::Error.none { return appended; } } return blot_error::Error.none; }
            let collected = collectSites(); proof.deinit(); if collected != blot_error::Error.none { return collected; }
        } return blot_error::Error.none;
    }
    let error = gather(); if error != blot_error::Error.none { blot_support_pooled_buffer::deinit(sites,scratch_runs); return Snapshot {..},error; } let owned = site_runs.alloc_slice(sites.items.len); for site,index in sites.items { owned[index] = site; } blot_support_pooled_buffer::deinit(sites,scratch_runs); return Snapshot { sites: owned,omitted: omitted , ..},blot_error::Error.none;
}
