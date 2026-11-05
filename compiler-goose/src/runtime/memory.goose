// Requested payload bytes are distinct from pool capacity and process RSS.
// A runtime integration supplies successful allocate/change/free observations.
namespace blot_runtime_memory;
import support.native;
import support.error;
import support.json;
import support.option;
type Error=blot_error::Error;
struct Counts {live_bytes:u64=0,peak_bytes:u64=0,allocated_bytes:u64=0,allocations:u64=0,complete:bool=false}
fn jsonStringify(self:Counts,writer:blot_json::Writer&)->Error {
    writer.beginObject();if self.complete {writer.field("live_bytes",self.live_bytes);writer.field("peak_bytes",self.peak_bytes);writer.field("allocated_bytes",self.allocated_bytes);writer.field("allocations",self.allocations);}
    else {writer.field("live_bytes",blot_support::none<u64>());writer.field("peak_bytes",blot_support::none<u64>());writer.field("allocated_bytes",blot_support::none<u64>());writer.field("allocations",blot_support::none<u64>());writer.field("coverage","unavailable");}writer.endObject();return writer.failure;
}
enum Sharing {single,shared}
struct TrackedAllocator {counts:Counts=Counts{..},sharing:Sharing=Sharing.single}
fn added(self:TrackedAllocator&,bytes:u64) {var live:u64=0;if self.sharing==Sharing.single {self.counts.live_bytes+=bytes;self.counts.allocated_bytes+=bytes;live=self.counts.live_bytes;self.counts.peak_bytes=max(self.counts.peak_bytes,live);}else {live=blot_native::atomic_add(self.counts.live_bytes,bytes)+bytes;blot_native::atomic_add(self.counts.allocated_bytes,bytes);blot_native::atomic_max(self.counts.peak_bytes,live);}}
fn allocated(self:TrackedAllocator&,bytes:u64) {self.added(bytes);if self.sharing==Sharing.single {self.counts.allocations++;}else {blot_native::atomic_add(self.counts.allocations,1);}}
fn freed(self:TrackedAllocator&,bytes:u64) {if self.sharing==Sharing.single {assert(self.counts.live_bytes>=bytes);self.counts.live_bytes-=bytes;}else {let before=blot_native::atomic_sub(self.counts.live_bytes,bytes);assert(before>=bytes);}}
fn changed(self:TrackedAllocator&,old:u64,new:u64) {if new>=old {self.added(new-old);}else {self.freed(old-new);}}
// Shared typed pools are coordinated by their concrete owning process. This
// reports only the meter's mode, not unsupplied runtime allocator guarantees.
fn shareable(self:const TrackedAllocator&)->bool {return self.sharing==Sharing.shared;}
