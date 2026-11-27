// Requested payload bytes are distinct from pool capacity and process RSS.
// A runtime integration supplies successful allocate/change/free observations.
namespace squid_runtime_memory;
import support.native;
import support.error;
import support.json;
import support.option;
type Error=squid_error::Error;
struct Counts {live_bytes:u64=0,peak_bytes:u64=0,allocated_bytes:u64=0,allocations:u64=0,complete:bool=false}
// A command's counts are those of its pooled owners: the buffers the compiler
// takes and releases by hand, as every allocation of the Zig compiler was.
// An array that belongs to a scope is released with it and is not counted.
struct Meter {allocated:u64=0,freed:u64=0,allocations:u64=0,observed:bool=false}
fn start()->Meter {let coverage=squid_native::runtime_observation(0);if (coverage&1)==0 {return Meter{..};}squid_native::runtime_memory_mark();return Meter{allocated:squid_native::runtime_observation(8),freed:squid_native::runtime_observation(9),allocations:squid_native::runtime_observation(4),observed:true};}
fn below(value:u64,base:u64)->u64 {if value<base {return 0;}return value-base;}
// Call after the command's owners are released.
fn counts(self_:Meter)->Counts {
    if !self_.observed {return Counts{..};}squid_native::runtime_observation(0);let allocated=squid_native::runtime_observation(8);let freed=squid_native::runtime_observation(9);let base=below(self_.allocated,self_.freed);
    return Counts{live_bytes:below(below(allocated,freed),base),peak_bytes:below(squid_native::runtime_observation(20),base),allocated_bytes:below(allocated,self_.allocated),allocations:below(squid_native::runtime_observation(4),self_.allocations),complete:true};
}
fn jsonStringify(receiver:Counts,writer:squid_json::Writer&)->Error {
    let coverage=squid_native::runtime_observation(0);
    writer.beginObject();if receiver.complete {writer.field("live_bytes",receiver.live_bytes);writer.field("peak_bytes",receiver.peak_bytes);writer.field("allocated_bytes",receiver.allocated_bytes);writer.field("allocations",receiver.allocations);}
    else {writer.field("live_bytes",squid_support::none<u64>());writer.field("peak_bytes",squid_support::none<u64>());writer.field("allocated_bytes",squid_support::none<u64>());writer.field("allocations",squid_support::none<u64>());writer.field("coverage","unavailable");}
    writer.key("runtime_observations");runtimeObservations(writer,coverage);writer.endObject();return writer.failure;
}
// Request-local operation totals and process-total virtual reservations are
// separate from active payload, retained pool capacity, scratch and RSS.
// Native field zero captures the counters before JSON output can allocate.
fn runtimeObservations(writer:squid_json::Writer&,coverage:u64)->Error {
    writer.beginObject();
    if coverage==0 {writer.field("coverage","unavailable");}
    else {
        writer.field("coverage","pool-operations-and-region-reservations");
        writer.field("scope","request-counters-and-process-region-reservations");
        writer.field("request",squid_native::runtime_observation(1));
        writer.field("attempts",squid_native::runtime_observation(2));
        writer.field("refusals",squid_native::runtime_observation(3));
        writer.field("pool_allocations",squid_native::runtime_observation(4));
        writer.field("pool_reallocations",squid_native::runtime_observation(5));
        writer.field("pool_frees",squid_native::runtime_observation(6));
        writer.field("pool_reuses",squid_native::runtime_observation(7));
        writer.field("pool_payload_allocated_bytes",squid_native::runtime_observation(8));
        writer.field("pool_payload_freed_bytes",squid_native::runtime_observation(9));
        writer.field("pool_capacity_growth_bytes",squid_native::runtime_observation(10));
        writer.field("region_reservations",squid_native::runtime_observation(11));
        writer.field("region_releases",squid_native::runtime_observation(12));
        writer.field("region_reserved_bytes",squid_native::runtime_observation(13));
        writer.field("region_reserved_peak_bytes",squid_native::runtime_observation(14));
        writer.field("explicit_capacity_requests",squid_native::runtime_observation(15));
        writer.field("explicit_capacity_requested_bytes",squid_native::runtime_observation(16));
        writer.field("registry_allocated_bytes",squid_native::runtime_observation(17));
    }
    writer.field("pool_operations",(coverage&1)!=0);
    writer.field("region_reservations_observed",(coverage&2)!=0);
    writer.field("explicit_capacity_requests_observed",(coverage&4)!=0);
    writer.field("registry_allocation_observed",(coverage&8)!=0);
    writer.field("whole_runtime_fault_coverage",false);
    writer.field("active_pool_payload_bytes",squid_support::none<u64>());
    writer.field("retained_pool_capacity_bytes",squid_support::none<u64>());
    writer.field("scratch_bytes",squid_support::none<u64>());
    writer.field("rss_bytes",squid_support::none<u64>());
    writer.endObject();return writer.failure;
}
enum Sharing {single,shared}
struct TrackedAllocator {counts:Counts=Counts{..},sharing:Sharing=Sharing.single}
fn added(receiver:TrackedAllocator&,bytes:u64) {var live:u64=0;if receiver.sharing==Sharing.single {receiver.counts.live_bytes+=bytes;receiver.counts.allocated_bytes+=bytes;live=receiver.counts.live_bytes;receiver.counts.peak_bytes=max(receiver.counts.peak_bytes,live);}else {live=squid_native::atomic_add(receiver.counts.live_bytes,bytes)+bytes;squid_native::atomic_add(receiver.counts.allocated_bytes,bytes);squid_native::atomic_max(receiver.counts.peak_bytes,live);}}
fn allocated(receiver:TrackedAllocator&,bytes:u64) {receiver.added(bytes);if receiver.sharing==Sharing.single {receiver.counts.allocations++;}else {squid_native::atomic_add(receiver.counts.allocations,1);}}
fn freed(receiver:TrackedAllocator&,bytes:u64) {if receiver.sharing==Sharing.single {assert(receiver.counts.live_bytes>=bytes);receiver.counts.live_bytes-=bytes;}else {let before=squid_native::atomic_sub(receiver.counts.live_bytes,bytes);assert(before>=bytes);}}
fn changed(receiver:TrackedAllocator&,old:u64,new:u64) {if new>=old {receiver.added(new-old);}else {receiver.freed(old-new);}}
// Shared typed pools are coordinated by their concrete owning process. This
// reports only the meter's mode, not unsupplied runtime allocator guarantees.
fn shareable(receiver:const TrackedAllocator&)->bool {return receiver.sharing==Sharing.shared;}
