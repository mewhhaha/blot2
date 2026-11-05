// A published result has independent fixed headers and actual typed byte runs.
namespace blot_backend_result_owner;
import .allocation_emission;
import .startup_emission_facts;
import reuse.dispatch_explanation;
import support.error;
import support.native;
import support.pooled_buffer;
type Error = blot_error::Error;
struct ByteBuffer { storage: u8[:] = default<u8[:]>(),items: u8[:] = default<u8[:]>(),len: i64 = 0 }
reusable[] var byte_runs: u8[>..] = [];
fn append(self_: ByteBuffer&,bytes: const u8[:]) -> Error { let error = blot_support_pooled_buffer::append(self_,bytes,byte_runs); self_.len = self_.items.len; return error; }
fn clear(self_: ByteBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len = 0; }
fn deinit(self_: ByteBuffer&) { blot_support_pooled_buffer::deinit(self_,byte_runs); self_.len = 0; }
var inactive_bytes = ByteBuffer {..};
var inactive_message = ByteBuffer {..};
struct Owner { slot: u32 = 0,generation: u64 = 0 }
struct Entry {
    live: bool = false,generation: u64 = 0,bytes: ByteBuffer,message: ByteBuffer,diagnostic_text: ByteBuffer,
    allocation: blot_backend_allocation_emission::Snapshot,startup: blot_backend_startup_emission_facts::Snapshot,explanation: blot_reuse_dispatch_explanation::Explanation,
}
reusable var entries: Entry[>..] = [];
fn valid(owner: Owner) -> bool { return owner.slot != 0 && owner.slot - 1 < entries.len && entries[owner.slot - 1].live && entries[owner.slot - 1].generation == owner.generation; }
fn init() -> Owner,Error { if entries.len >= 4294967295 { return Owner {..},blot_error::Error.out_of_memory; } let generation = blot_native::fresh_owner_id(); let index = entries.alloc_index(Entry { live: true,generation: generation,..}); return Owner { slot: (index + 1) as u32,generation: generation,..},blot_error::Error.none; }
fn get(owner: Owner) -> Entry& { assert(valid(owner)); return entries[owner.slot - 1]; }
fn deinit(owner: Owner&) { if owner.slot == 0 { return; } let entry .= get(owner); entry.bytes.deinit(); entry.message.deinit(); entry.diagnostic_text.deinit(); entry.allocation.deinit(); entry.startup.deinit(); entry.explanation.deinit(); entry.live = false; entries.free(owner.slot - 1); owner = Owner {..}; }
