// Short ticket-lock critical sections around typed reusable pool operations.
namespace blot_eval_parallel_allocator;
import support.native;
struct TicketLock { next: u64=0,serving: u64=0 }
fn enter(lock: TicketLock&) { let ticket=blot_native::atomic_add(lock.next,1); while blot_native::atomic_load(lock.serving)!=ticket {} }
fn leave(lock: TicketLock&) { blot_native::atomic_add(lock.serving,1); }
struct LockedAllocator { backing_owner: u64,shareable: bool,mutex: TicketLock& }
fn alloc<T>(self: LockedAllocator&,pool: T[>..]&,count: i64) -> T[:] {
 if self.shareable { return pool.alloc_slice(count); } enter(self.mutex); defer { leave(self.mutex); } return pool.alloc_slice(count);
}
fn resize<T>(self: LockedAllocator&,pool: T[>..]&,old: T[:],count: i64) -> T[:] {
 if self.shareable { return pool.realloc_slice(old,count); } enter(self.mutex); defer { leave(self.mutex); } return pool.realloc_slice(old,count);
}
fn remap<T>(self: LockedAllocator&,pool: T[>..]&,old: T[:],count: i64) -> T[:] { return resize(self,pool,old,count); }
fn free<T>(self: LockedAllocator&,pool: T[>..]&,memory: T[:]) {
 if self.shareable { pool.free_slice(memory); return; } enter(self.mutex); defer { leave(self.mutex); } pool.free_slice(memory);
}
