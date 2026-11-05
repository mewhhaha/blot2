// Lexical positions and immutable environments; no resolved type facts are cached.
namespace blot_backend_storage_type_arguments;
import dictionary;
import support.error;
import support.option;
import support.native;
import support.pooled_buffer;
import support.pooled_map;
type Error = blot_error::Error;
let absent: i64 = 9223372036854775807;
struct Stats { lookups: u64 = 0,synchronized: u64 = 0,captures: u64 = 0,capture_hits: u64 = 0 }
struct Positions { any: blot_support::Option<i64>,nonidentity: blot_support::Option<i64> }
struct Snapshot<A> { items: const A[:],owner_id: u64 }
struct Undo<A> { positions: Positions,snapshot: blot_support::Option<Snapshot<A>>,previous: i64,next: i64 = absent }
struct Pools<A> { arguments: A[>..]&,undo: Undo<A>[>..]&,positions: dictionary_slot<u64,Positions>[>..]&,snapshots: A[>..]&,indexes: i64[>..]& }
struct Stack<A> {
    pools: Pools<A>? = null,items: A[..] = [],arguments: blot_support_pooled_buffer::Buffer<A>,undo: blot_support_pooled_buffer::Buffer<Undo<A>>,positions: blot_support_pooled_map::Map<u64,Positions>,
    active_count: i64 = 0,first_active: i64 = absent,last_active: i64 = absent,snapshot: blot_support::Option<Snapshot<A>>,stats: Stats,
}
fn init<A>(pools: Pools<A>&) -> Stack<A> { Stack<A> { pools } }
fn emptyFrom<A>(source: const Stack<A>&) -> Stack<A> { Stack<A> { pools: source.pools } }
fn increase(counter: u64&) { if counter != 18446744073709551615 { counter++; } }
fn key(unit: u32,parameter: u32) -> u64 { (unit as u64 << 32) | parameter as u64 }
fn deinit<A>(stack: Stack<A>&) { if stack.pools == null { return; } blot_support_pooled_buffer::deinit(stack.arguments,stack.pools.arguments); blot_support_pooled_buffer::deinit(stack.undo,stack.pools.undo); blot_support_pooled_map::deinit(stack.positions,stack.pools.positions); stack.items = []; stack.active_count = 0; stack.first_active = absent; stack.last_active = absent; stack.snapshot = blot_support::none<Snapshot<A>>(); stack.stats = Stats {..}; }
fn reserve<A>(stack: Stack<A>&,count: i64) -> Error {
    assert(stack.pools != null); let arguments = blot_support_pooled_buffer::ensure(stack.arguments,stack.arguments.items.len + count,stack.pools.arguments); stack.items = stack.arguments.items; if arguments != blot_error::Error.none { return arguments; } let undo = blot_support_pooled_buffer::ensure(stack.undo,stack.undo.items.len + count,stack.pools.undo); if undo != blot_error::Error.none { return undo; } if count > 4294967295 { return blot_error::Error.out_of_memory; }
    var capacity = stack.positions.slots.len; if capacity == 0 { capacity = 8; } while (stack.positions.count + count) * 3 > capacity * 2 { if capacity > 4611686018427387903 { return blot_error::Error.out_of_memory; } capacity *= 2; } if capacity != stack.positions.slots.len { blot_support_pooled_map::grow(stack.positions,capacity,stack.pools.positions); } return blot_error::Error.none;
}
fn unlink<A>(stack: Stack<A>&,index: i64) { let links = stack.undo.items[index]; if links.previous == absent { stack.first_active = links.next; } else { stack.undo.items[links.previous].next = links.next; } if links.next == absent { stack.last_active = links.previous; } else { stack.undo.items[links.next].previous = links.previous; } }
fn link<A>(stack: Stack<A>&,index: i64) { let links = stack.undo.items[index]; if links.previous == absent { stack.first_active = index; } else { stack.undo.items[links.previous].next = index; } if links.next == absent { stack.last_active = index; } else { stack.undo.items[links.next].previous = index; } }
fn appendAssumeCapacity<A>(stack: Stack<A>&,argument: A) {
    assert(stack.pools != null); let lookup = key(argument.unit,argument.parameter); var positions = Positions {..}; { let held .= blot_support_pooled_map::get(stack.positions,lookup); if held != null { positions = held; } }
    if !positions.any.present { stack.active_count++; } else { unlink(stack,positions.any.value); }
    let at = stack.undo.items.len; assert(at < stack.undo.storage.len); stack.undo.storage[at] = Undo<A> { positions: positions,snapshot: stack.snapshot,previous: stack.last_active , ..}; stack.undo.items = stack.undo.storage[..at + 1]; let position = stack.arguments.items.len; link(stack,position); assert(position < stack.arguments.storage.len); stack.arguments.storage[position] = argument; stack.arguments.items = stack.arguments.storage[..position + 1]; stack.items = stack.arguments.items; positions.any = blot_support::some(position); if argument.argument_unit != argument.unit || argument.argument != argument.parameter { positions.nonidentity = blot_support::some(position); } blot_support_pooled_map::insert(stack.positions,lookup,positions,stack.pools.positions); stack.snapshot = blot_support::none<Snapshot<A>>(); increase(stack.stats.synchronized);
}
fn append<A>(stack: Stack<A>&,argument: A) -> Error { let error = reserve(stack,1); if error != blot_error::Error.none { return error; } appendAssumeCapacity(stack,argument); return blot_error::Error.none; }
fn appendSlice<A>(stack: Stack<A>&,arguments: const A[:]) -> Error { if arguments.len == 0 { return blot_error::Error.none; } let error = reserve(stack,arguments.len); if error != blot_error::Error.none { return error; } for argument in arguments { appendAssumeCapacity(stack,argument); } return blot_error::Error.none; }
fn sift(indexes: i64[:],start: i64,end: i64) { var root = start; while root * 2 + 1 < end { var child = root * 2 + 1; if child + 1 < end && indexes[child] < indexes[child + 1] { child++; } if indexes[root] >= indexes[child] { return; } let value = indexes[root]; indexes[root] = indexes[child]; indexes[child] = value; root = child; } }
fn sort(indexes: i64[:]) { var start = indexes.len / 2; while start != 0 { start--; sift(indexes,start,indexes.len); } var end = indexes.len; while end > 1 { end--; let value = indexes[0]; indexes[0] = indexes[end]; indexes[end] = value; sift(indexes,0,end); } }
fn inheritActive<A>(stack: Stack<A>&,source: const Stack<A>&) -> i64,Error {
    assert(stack.items.len == 0 && stack.pools != null); if source.items.len == 0 || source.active_count > source.items.len / 8 { let error = appendSlice(stack,source.items); return source.items.len,error; }
    var count = source.active_count; var cursor = source.first_active; while cursor != absent { let argument = source.items[cursor]; let heads .= blot_support_pooled_map::get(source.positions,key(argument.unit,argument.parameter)); assert(heads != null); if heads.nonidentity.present && heads.nonidentity.value != cursor { count++; } cursor = source.undo.items[cursor].next; }
    let indexes = stack.pools.indexes.alloc_slice(count); var next: i64 = 0; cursor = source.first_active; while cursor != absent { indexes[next] = cursor; next++; let argument = source.items[cursor]; let heads .= blot_support_pooled_map::get(source.positions,key(argument.unit,argument.parameter)); assert(heads != null); if heads.nonidentity.present && heads.nonidentity.value != cursor { indexes[next] = heads.nonidentity.value; next++; } cursor = source.undo.items[cursor].next; } assert(next == indexes.len); sort(indexes); let error = reserve(stack,count); if error == blot_error::Error.none { for position in indexes { appendAssumeCapacity(stack,source.items[position]); } } stack.pools.indexes.free_slice(indexes); return count,error;
}
fn shrinkRetainingCapacity<A>(stack: Stack<A>&,length: i64) {
    assert(length <= stack.items.len && stack.pools != null); if length == stack.items.len { return; } var at = stack.items.len;
    while at > length { at--; let argument = stack.items[at]; let original = stack.undo.items[at]; let slot = key(argument.unit,argument.parameter); unlink(stack,at); if original.positions.any.present { link(stack,original.positions.any.value); } else { stack.active_count--; } let positions .= blot_support_pooled_map::get(stack.positions,slot); assert(positions != null); positions = original.positions; stack.snapshot = original.snapshot; }
    blot_support_pooled_buffer::resize(stack.arguments,length); blot_support_pooled_buffer::resize(stack.undo,length); stack.items = stack.arguments.items;
}
fn clearRetainingCapacity<A>(stack: Stack<A>&) { if stack.positions.count == 0 { return; } blot_support_pooled_buffer::clear(stack.arguments); blot_support_pooled_buffer::clear(stack.undo); blot_support_pooled_map::clear(stack.positions); stack.active_count = 0; stack.first_active = absent; stack.last_active = absent; stack.items = stack.arguments.items; stack.snapshot = blot_support::none<Snapshot<A>>(); }
fn latestAny<A>(stack: Stack<A>&,unit: u32,parameter: u32) -> blot_support::Option<i64> { increase(stack.stats.lookups); let positions .= blot_support_pooled_map::get(stack.positions,key(unit,parameter)); if positions == null { return blot_support::none<i64>(); } return positions.any; }
fn latestNonidentity<A>(stack: Stack<A>&,unit: u32,parameter: u32) -> blot_support::Option<i64> { increase(stack.stats.lookups); let positions .= blot_support_pooled_map::get(stack.positions,key(unit,parameter)); if positions == null { return blot_support::none<i64>(); } return positions.nonidentity; }
fn capture<A>(stack: Stack<A>&) -> const A[:],Error {
    assert(stack.pools != null); if stack.snapshot.present { increase(stack.stats.capture_hits); return stack.snapshot.value.items,blot_error::Error.none; } var result: A[..] = []; if stack.active_count != 0 { result = stack.pools.snapshots.alloc_slice(stack.active_count); } var count: i64 = 0; var index = stack.first_active; while index != absent { result[count] = stack.items[index]; count++; index = stack.undo.items[index].next; } assert(count == result.len); stack.snapshot = blot_support::some(Snapshot<A> { items: result,owner_id: blot_native::fresh_owner_id() , ..}); increase(stack.stats.captures); return result,blot_error::Error.none;
}
