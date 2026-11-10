// A published result has independent fixed headers and actual typed byte runs.
namespace blot_backend_result_owner;
import .allocation_emission;
import .startup_emission_facts;
import .backend_timing;
import reuse.dispatch_explanation;
import support.error;
import support.native;
import support.pooled_buffer;
type Error = blot_error::Error;
struct ByteBuffer { storage: u8[:] = default<u8[:]>(),items: u8[:] = default<u8[:]>(),len: i64 = 0 }
reusable[] var byte_runs: u8[>..] = [];
fn append(self_: ByteBuffer&,bytes: const u8[:]) -> Error { let error = blot_support_pooled_buffer::append(self_,bytes,byte_runs); self_.len = self_.items.len; return error; }
// Reborrow the initialized prefix of an exact existing byte allocation.
fn registeredBytes(value:ByteBuffer)->const u8[:] {
 assert(value.len==value.items.len && value.len>=0 && value.len<=value.storage.len);
 if value.len==0 {return default<const u8[:]>();}
 let owned=byte_runs.realloc_slice(value.storage,value.storage.len);assert(blot_support::same_slice_identity(owned,value.storage));
 let start=byte_runs.index_of(owned[0]);assert(start>=0 && value.storage.len<=byte_runs.len-start);
 let items=byte_runs[start..start+value.len];assert(blot_support::same_slice_identity(items,value.items));return items;
}
fn clear(self_: ByteBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len = 0; }
fn deinit(self_: ByteBuffer&) { blot_support_pooled_buffer::deinit(self_,byte_runs); self_.len = 0; }
var inactive_bytes = ByteBuffer {..};
var inactive_message = ByteBuffer {..};
struct Owner { slot: u32 = 0,generation: u64 = 0 }
struct Entry {
    live: bool = false,generation: u64 = 0,bytes: ByteBuffer,message: ByteBuffer,diagnostic_text: ByteBuffer,timing_names: ByteBuffer,
    allocation: blot_backend_allocation_emission::Snapshot,startup: blot_backend_startup_emission_facts::Snapshot,explanation: blot_reuse_dispatch_explanation::Explanation,
}
reusable var entries: Entry[>..] = [];
fn valid(owner: Owner) -> bool { return owner.slot != 0 && owner.slot - 1 < entries.len && entries[owner.slot - 1].live && entries[owner.slot - 1].generation == owner.generation; }
fn init() -> Owner,Error { if entries.len >= 4294967295 { return Owner {..},blot_error::Error.out_of_memory; } let generation = blot_native::fresh_owner_id(); let index = entries.alloc_index(Entry { live: true,generation: generation,..}); return Owner { slot: (index + 1) as u32,generation: generation,..},blot_error::Error.none; }
fn get(owner: Owner) -> Entry& { assert(valid(owner)); return entries[owner.slot - 1]; }
fn deinit(owner: Owner&) { if owner.slot == 0 { return; } let entry .= get(owner); entry.bytes.deinit(); entry.message.deinit(); entry.diagnostic_text.deinit(); entry.timing_names.deinit(); entry.allocation.deinit(); entry.startup.deinit(); entry.explanation.deinit(); entry.live = false; entries.free(owner.slot - 1); owner = Owner {..}; }

// Candidate publication consumes one detached result. Labels become owned before
// its invocation-local metadata header is discarded.
fn timingName(storage:u8[:],name:const u8[:],offset:i64&)->const u8[:] {
 if name=="overflow" {return "overflow";}if name.len==0 {return default<const u8[:]>();}
 assert(offset>=0 && offset<=storage.len && name.len<=storage.len-offset);let start=offset;for byte,index in name {storage[start+index]=byte;}offset+=name.len;
 let owned=byte_runs.realloc_slice(storage,storage.len);assert(blot_support::same_slice_identity(owned,storage));let at=byte_runs.index_of(owned[0]);assert(at>=0 && storage.len<=byte_runs.len-at);return byte_runs[at+start..at+offset];
}
fn ownedTimingCost(storage:u8[:],value:blot_backend_backend_timing::RegionCost,offset:i64&)->blot_backend_backend_timing::RegionCost {
 let owned=timingName(storage,value.caller.function,offset);
 return blot_backend_backend_timing::RegionCost{caller:blot_backend_backend_timing::RegionCaller{function:owned,line:value.caller.line},stage:value.stage,regions:value.regions,inclusive_us:value.inclusive_us,scopes:value.scopes,nodes:value.nodes,solver_bytes:value.solver_bytes,scratch_bytes:value.scratch_bytes,solver_allocations:value.solver_allocations,scratch_allocations:value.scratch_allocations};
}
fn timingStorage(owner:Owner)->u8[:] {
 let entry .= get(owner);assert(entry.timing_names.len==0 && entry.timing_names.items.len==0);let storage=entry.timing_names.storage;if storage.len==0 {return default<u8[:]>();}
 let owned=byte_runs.realloc_slice(storage,storage.len);assert(blot_support::same_slice_identity(owned,storage));let start=byte_runs.index_of(owned[0]);assert(start>=0 && storage.len<=byte_runs.len-start);return byte_runs[start..start+storage.len];
}
fn ownedTiming(owner:Owner,value:blot_backend_backend_timing::Stats)->blot_backend_backend_timing::Stats,Error {
 let entry .= get(owner);assert(entry.timing_names.len==0);var total:i64=0;let overflow_name=value.work.region_callers.overflow.caller.function;if overflow_name!="overflow" {total=overflow_name.len;}
 for cost in value.work.region_callers.entries {if cost.caller.function=="overflow" {continue;}if cost.caller.function.len>0x7fffffffffffffff-total {return blot_backend_backend_timing::Stats{..},blot_error::Error.out_of_memory;}total+=cost.caller.function.len;}
 var names=ByteBuffer{storage:timingStorage(owner),..};let error=blot_support_pooled_buffer::ensure(names,total,byte_runs);if error!=blot_error::Error.none {return blot_backend_backend_timing::Stats{..},error;}
 var census=blot_backend_backend_timing::RegionCensus{..};var offset:i64=0;
 for cost,index in value.work.region_callers.entries {census.entries[index]=ownedTimingCost(names.storage,cost,offset);}census.overflow=ownedTimingCost(names.storage,value.work.region_callers.overflow,offset);
 assert(offset==total);names.items=names.storage[..total];names.len=total;entry.timing_names=names;
 let work=blot_backend_backend_timing::WorkStats{regions:value.work.regions,region_callers:census,refinements:value.work.refinements,thread_cpu_us:value.work.thread_cpu_us,lookup_us:value.work.lookup_us,query_prepare_us:value.work.query_prepare_us,query_scan_us:value.work.query_scan_us,query_source_us:value.work.query_source_us,query_import_us:value.work.query_import_us,query_match_us:value.work.query_match_us,query_validate_us:value.work.query_validate_us,query_publish_us:value.work.query_publish_us,replay_us:value.work.replay_us,specialization_us:value.work.specialization_us,constants_us:value.work.constants_us,principals_us:value.work.principals_us,interfaces_us:value.work.interfaces_us,startup_us:value.work.startup_us,layouts_us:value.work.layouts_us,evaluation_us:value.work.evaluation_us,inference_us:value.work.inference_us,semantic_coordination_us:value.work.semantic_coordination_us,semantic_dispatch_us:value.work.semantic_dispatch_us,semantic_publication_us:value.work.semantic_publication_us,semantic_job_sum_us:value.work.semantic_job_sum_us};
 return blot_backend_backend_timing::Stats{prepare_us:value.prepare_us,generate_us:value.generate_us,initialize_us:value.initialize_us,assemble_us:value.assemble_us,capture_us:value.capture_us,profiled:value.profiled,work:work},blot_error::Error.none;
}
