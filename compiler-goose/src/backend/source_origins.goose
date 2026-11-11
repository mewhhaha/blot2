// Diagnostic origins never authorize ownership, reuse, or semantic rewriting.
namespace blot_backend_source_origins;
import std;
import dictionary;
import check.core;
import check.types;
import .wasm;
import .runtime_ir;
import .runtime_identity;
import .cohort_candidate;
import support.error;
import support.option;
import support.pooled_buffer;
import support.json;
type Error = blot_error::Error;
let max_sites: i64 = 65536;
struct Context { unit: u32,node: u32,parent: u32 }
fn hash(context: Context) -> u64 { ::hash_combine(::hash_combine(::hash(context.unit),::hash(context.node)),::hash(context.parent)) }
struct ContextPool { records: Context[>..<]&,ids: dictionary<Context,u32>& }
fn init(records: Context[>..<]&,ids: dictionary<Context,u32>&) -> ContextPool { ContextPool { records,ids } }
fn deinit(pool: ContextPool&) { pool.records.clear(); pool.ids.clear(); }
fn intern(pool: ContextPool&,value: Context) -> u32,Error { { let id .= pool.ids.get(value); if id != null { return id,blot_error::Error.none; } } if pool.records.len == max_sites { return 0,blot_error::Error.module_too_large; } let id = (pool.records.len + 1) as u32; pool.records.push(value); pool.ids.insert(value,id); return id,blot_error::Error.none; }
struct Frame { unit: u32 = 0,node: u32 = 0,start: u32 = 0,end: u32 = 0,filename: const u8[:] = "" }
struct Site {
    unit: u32,node: u32,start: u32,end: u32,filename: const u8[:],operation: const u8[:] = "",source_type: const u8[:] = "",source_blake3: blot_support::Option<u8[32]>,
    inline_context: Frame[4] = [Frame {..};4],inline_depth: u8 = 0,inline_truncated: bool = false,
}
struct Sites { storage: Site[:] = default<Site[:]>(),items: Site[:] = default<Site[:]>() }
reusable[] var site_runs: Site[>..] = [];
fn push(sites: Sites&,site: Site) -> Error {
 let count=sites.items.len;let error=blot_support_pooled_buffer::ensure(sites,count+1,site_runs);if error!=blot_error::Error.none {return error;}
 let owned=site_runs.realloc_slice(sites.storage,sites.storage.len);owned[count]=site;sites.items=owned[..count+1];return blot_error::Error.none;
}
fn deinit(sites: Sites&) { blot_support_pooled_buffer::deinit(sites,site_runs); }
struct View { code: blot_backend_cohort_candidate::Extension&,identity:blot_backend_runtime_identity::Metadata=blot_backend_runtime_identity::Metadata{..},sites: Site[:] = default<Site[:]>(),owned: Sites }
fn init(code: blot_backend_cohort_candidate::Extension&) -> View { View { code } }
fn deinit(view: View&) { view.owned.deinit(); view.sites=default<Site[:]>();view.identity.deinit(); view.code.deinit(); }
fn spelling<T>(value: T) -> const u8[:] { match value { const for <N,V> in variants<T> { V payload=>{ return blot_json::sourceName(N); }, } } }
fn filename(names:blot_backend_runtime_identity::Metadata,unit:u32)->const u8[:] {
 let bytes=blot_backend_runtime_identity::registeredMetadataBytes(names.bytes);
 let symbols=blot_backend_runtime_identity::registeredMetadataNames(names.symbols);
 let owners=blot_backend_runtime_identity::registeredMetadataNames(names.owners);
 if unit==0 || unit>owners.len {return "";}
 let name=owners[unit-1];
 if name.start>bytes.len || name.len>bytes.len-name.start {return "";}
 return bytes[name.start..name.start+name.len];
}
fn initInto(result: View&,source: const blot_backend_wasm::Module&,units: const blot_check_core::Module[:],names: blot_support::Option<blot_backend_runtime_identity::View>,source_digests: const u8[32][:],contexts: const Context[:]) -> Error {
    result.deinit(); let detached = blot_backend_cohort_candidate::detachedInto(result.code,source); if detached != blot_error::Error.none { return detached; }
    if names.present {let owned,error=blot_backend_runtime_identity::copy(names.value);if error!=blot_error::Error.none {result.deinit();return error;}result.identity=owned;}
    var indexes = dictionary<Context,u32> {};
    fn populate() -> Error {
        for record in source.semantic_sites {
            if record.unit == 0 || record.unit > units.len || record.node == 0 { continue; } let unit .= units[record.unit - 1]; if record.node >= unit.nodes.len || record.function >= source.functions.len { continue; } if record.place >= source.functions[record.function].instructions.len { continue; } let key = Context { unit: record.unit,node: record.node,parent: record.diagnostic_context , ..}; var entry: u32 = 0; var found = false; { let previous .= indexes.get(key); if previous != null { entry = previous; found = true; } }
            if !found {
                if result.owned.items.len == max_sites { return blot_error::Error.module_too_large; } let span = unit.span(record.node); var digest = blot_support::none<u8[32]>(); if record.unit <= source_digests.len { digest = blot_support::some(source_digests[record.unit - 1]); } let operation = spelling(unit.node(record.node).tag); let source_type = spelling(unit.types.node(unit.typeOf(record.node)).tag); let source_filename = filename(result.identity,record.unit); let appended = result.owned.push(Site { unit: record.unit, node: record.node, start: span.start, end: span.end, filename: source_filename, operation: operation, source_type: source_type, source_blake3: digest, .. }); if appended != blot_error::Error.none { return appended; } entry = result.owned.items.len as u32; indexes.insert(key,entry);
                let site: Site& = result.owned.items[result.owned.items.len - 1]; var context = record.diagnostic_context;
                while context != 0 && context <= contexts.len && site.inline_depth < 4 { let frame = contexts[context - 1]; if frame.unit == 0 || frame.unit > units.len || frame.node >= units[frame.unit - 1].nodes.len { break; } let location = units[frame.unit - 1].span(frame.node); site.inline_context[site.inline_depth] = Frame { unit: frame.unit,node: frame.node,start: location.start,end: location.end,filename: filename(result.identity,frame.unit) , ..}; site.inline_depth++; context = frame.parent; } site.inline_truncated = context != 0;
            }
            let instructions,error = blot_backend_cohort_candidate::mutableInstructions(result.code,record.function); if error != blot_error::Error.none { return error; } instructions[record.place].origin = entry;
        }
        result.sites = result.owned.items; return blot_error::Error.none;
    }
    let error = populate(); if error != blot_error::Error.none { result.deinit(); } return error;
}
fn same(left: blot_backend_runtime_ir::Instruction,right: blot_backend_runtime_ir::Instruction) -> bool { return left.operand == right.operand && left.op == right.op && left.table_reference == right.table_reference && left.table_kind == right.table_kind; }
