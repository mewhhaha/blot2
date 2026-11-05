// Requested payload bytes are distinct from pool capacity and process RSS.
// A runtime integration supplies successful allocate/change/free observations.
namespace blot_runtime_memory;
import support.native;
import support.error;
import support.json;
import support.option;
type Error=blot_error::Error;
struct Counts {live_bytes:u64=0,peak_bytes:u64=0,allocated_bytes:u64=0,allocations:u64=0,complete:bool=false}
fn jsonStringify(receiver:Counts,writer:blot_json::Writer&)->Error {
    writer.beginObject();if receiver.complete {writer.field("live_bytes",receiver.live_bytes);writer.field("peak_bytes",receiver.peak_bytes);writer.field("allocated_bytes",receiver.allocated_bytes);writer.field("allocations",receiver.allocations);}
    else {writer.field("live_bytes",blot_support::none<u64>());writer.field("peak_bytes",blot_support::none<u64>());writer.field("allocated_bytes",blot_support::none<u64>());writer.field("allocations",blot_support::none<u64>());writer.field("coverage","unavailable");}writer.endObject();return writer.failure;
}
enum Sharing {single,shared}
struct TrackedAllocator {counts:Counts=Counts{..},sharing:Sharing=Sharing.single}
fn added(receiver:TrackedAllocator&,bytes:u64) {var live:u64=0;if receiver.sharing==Sharing.single {receiver.counts.live_bytes+=bytes;receiver.counts.allocated_bytes+=bytes;live=receiver.counts.live_bytes;receiver.counts.peak_bytes=max(receiver.counts.peak_bytes,live);}else {live=blot_native::atomic_add(receiver.counts.live_bytes,bytes)+bytes;blot_native::atomic_add(receiver.counts.allocated_bytes,bytes);blot_native::atomic_max(receiver.counts.peak_bytes,live);}}
fn allocated(receiver:TrackedAllocator&,bytes:u64) {receiver.added(bytes);if receiver.sharing==Sharing.single {receiver.counts.allocations++;}else {blot_native::atomic_add(receiver.counts.allocations,1);}}
fn freed(receiver:TrackedAllocator&,bytes:u64) {if receiver.sharing==Sharing.single {assert(receiver.counts.live_bytes>=bytes);receiver.counts.live_bytes-=bytes;}else {let before=blot_native::atomic_sub(receiver.counts.live_bytes,bytes);assert(before>=bytes);}}
fn changed(receiver:TrackedAllocator&,old:u64,new:u64) {if new>=old {receiver.added(new-old);}else {receiver.freed(old-new);}}
// Shared typed pools are coordinated by their concrete owning process. This
// reports only the meter's mode, not unsupplied runtime allocator guarantees.
fn shareable(receiver:const TrackedAllocator&)->bool {return receiver.sharing==Sharing.shared;}
