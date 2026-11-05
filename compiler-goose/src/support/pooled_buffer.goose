// The run owns capacity; items names only its initialized prefix.
namespace blot_support_pooled_buffer;
import std;
import support.error;
type Error = blot_error::Error;
struct Buffer<T> { storage: T[:] = default<T[:]>(), items: T[:] = default<T[:]>() }
fn ensure<T,B>(buffer: B&,minimum: i64,pool: T[>..]&) -> Error {
    if minimum <= buffer.storage.len { return blot_error::Error.none; } if minimum > 0x5555555555555540 { return blot_error::Error.out_of_memory; }
    let capacity = max(8,minimum + minimum / 2); let length = buffer.items.len;
    let source = pool.realloc_slice(buffer.storage,buffer.storage.len); let replacement = pool.alloc_slice(capacity);
    for index in length { replacement[index] = source[index]; }
    if source.len != 0 { pool.free_slice(source); } buffer.storage = replacement; buffer.items = replacement[..length]; return blot_error::Error.none;
}
fn push<T,B>(buffer: B&,value: T,pool: T[>..]&) -> Error { let length = buffer.items.len; let error = ensure(buffer,length + 1,pool); if error != blot_error::Error.none { return error; } buffer.storage[length] = value; buffer.items = buffer.storage[..length + 1]; return blot_error::Error.none; }
fn append<T,B>(buffer: B&,values: const T[:],pool: T[>..]&) -> Error { let length = buffer.items.len; if values.len > 0x7fffffffffffffff - length { return blot_error::Error.out_of_memory; } let error = ensure(buffer,length + values.len,pool); if error != blot_error::Error.none { return error; } for value,index in values { buffer.storage[length + index] = value; } buffer.items = buffer.storage[..length + values.len]; return blot_error::Error.none; }
fn resize<B>(buffer: B&,length: i64) { assert(length >= 0 && length <= buffer.items.len); buffer.items = buffer.storage[..length]; }
fn clear<B>(buffer: B&) { buffer.items = buffer.storage[..0]; }
fn deinit<T,B>(buffer: B&,pool: T[>..]&) { if buffer.storage.len != 0 { pool.free_slice(buffer.storage); } buffer.storage = default<T[:]>(); buffer.items = default<T[:]>(); }
