// Short ticket-lock critical sections around typed reusable pool operations.
namespace blot_eval_parallel_allocator;
import support.native;

struct TicketLock { next: u64=0,serving: u64=0 }
fn enter(lock: TicketLock&) { let ticket=blot_native::atomic_add(lock.next,1); while blot_native::atomic_load(lock.serving)!=ticket {} }
fn leave(lock: TicketLock&) { blot_native::atomic_add(lock.serving,1); }
struct LockedAllocator { backing_owner: u64,shareable: bool,mutex: TicketLock& }
fn alloc<T>(self_: LockedAllocator&,pool: T[>..]&,count: i64) -> T[:] {
 if self_.shareable { return pool.alloc_slice(count); } enter(self_.mutex);  let __cleanup_result_149_0: T[:] = pool.alloc_slice(count); { leave(self_.mutex); } return __cleanup_result_149_0;
 { leave(self_.mutex); } }
fn resize<T>(self_: LockedAllocator&,pool: T[>..]&,old: T[:],count: i64) -> T[:] {
 if self_.shareable { return pool.realloc_slice(old,count); } enter(self_.mutex);  let __cleanup_result_150_0: T[:] = pool.realloc_slice(old,count); { leave(self_.mutex); } return __cleanup_result_150_0;
 { leave(self_.mutex); } }
fn remap<T>(self_: LockedAllocator&,pool: T[>..]&,old: T[:],count: i64) -> T[:] { return resize(self_,pool,old,count); }
fn free<T>(self_: LockedAllocator&,pool: T[>..]&,memory: T[:]) {
 if self_.shareable { pool.free_slice(memory); return; } enter(self_.mutex);  pool.free_slice(memory);
 { leave(self_.mutex); } }
