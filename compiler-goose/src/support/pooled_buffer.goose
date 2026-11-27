// The run owns capacity; items names only its initialized prefix.
namespace squid_support_pooled_buffer;
import std;
import support.error;
type Error = squid_error::Error;
struct Buffer<T> { storage: T[:] = default<T[:]>(), items: T[:] = default<T[:]>() }
fn ensure<T,B>(buffer: B&,minimum: i64,pool: T[>..]&) -> Error {
    if minimum <= buffer.storage.len { return squid_error::Error.none; } if minimum > 0x5555555555555540 { return squid_error::Error.out_of_memory; }
    let capacity = max(8,minimum + minimum / 2); let length = buffer.items.len;
    let replacement = pool.realloc_slice(buffer.storage,capacity);
    buffer.storage = replacement; buffer.items = replacement[..length]; return squid_error::Error.none;
}
fn ensureExact<T,B>(buffer: B&,minimum: i64,pool: T[>..]&) -> Error {
    if minimum <= buffer.storage.len { return squid_error::Error.none; } if minimum > 0x5555555555555540 { return squid_error::Error.out_of_memory; }
    let length = buffer.items.len;
    let replacement = pool.realloc_slice(buffer.storage,minimum);
    buffer.storage = replacement; buffer.items = replacement[..length]; return squid_error::Error.none;
}
fn push<T,B>(buffer: B&,value: T,pool: T[>..]&) -> Error {
    let length = buffer.items.len;
    if length >= buffer.storage.len {
        let error = ensure(buffer,length + 1,pool);
        if error != squid_error::Error.none { return error; }
    }
    buffer.storage[length] = value;
    buffer.items = buffer.storage[..length + 1];
    return squid_error::Error.none;
}
fn append<T,B>(buffer: B&,values: const T[:],pool: T[>..]&) -> Error { let length = buffer.items.len; if values.len > 0x7fffffffffffffff - length { return squid_error::Error.out_of_memory; } let error = ensure(buffer,length + values.len,pool); if error != squid_error::Error.none { return error; } if values.len != 0 { buffer.storage[length..length + values.len].move_from(values); } buffer.items = buffer.storage[..length + values.len]; return squid_error::Error.none; }
fn resize<B>(buffer: B&,length: i64) { assert(length >= 0 && length <= buffer.items.len); buffer.items = buffer.storage[..length]; }
fn clear<B>(buffer: B&) { buffer.items = buffer.storage[..0]; }
fn deinit<T,B>(buffer: B&,pool: T[>..]&) { if buffer.storage.len != 0 { pool.free_slice(buffer.storage); } buffer.storage = default<T[:]>(); buffer.items = default<T[:]>(); }
