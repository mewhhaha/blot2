// Shared u64-to-ID headers use one existing append-only slot owner.
namespace blot_support_u64_id_map;
import std;
import dictionary;
import support.error;
import support.option;
import support.pooled_map;
type Error=blot_error::Error;
struct Buckets { count: i64=0,slots: dictionary_slot<u64,u32>[:]=default<dictionary_slot<u64,u32>[:]>() }
reusable[] var bucket_slots: dictionary_slot<u64,u32>[>..]=[];
fn get(self_: const Buckets&,key: u64) -> u32? { let view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots}; let index=blot_support_pooled_map::probe(view,key); if index<0 { return null; } return self_.slots[index].val; }
fn canonicalBucketsSlots(source: const dictionary_slot<u64,u32>[:]) -> dictionary_slot<u64,u32>[:] {
 if source.len==0 {return default<dictionary_slot<u64,u32>[:]>();}
 let owned=bucket_slots.realloc_slice(source,source.len);
 assert(blot_support::same_slice_identity(owned,source));
 let start=bucket_slots.index_of(owned[0]);
 assert(start>=0 && source.len<=bucket_slots.len-start);
 return bucket_slots[start..start+source.len];
}
fn insert(self_: Buckets&,key: u64,value: u32) { var view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::insert(view,key,value,bucket_slots); self_.count=view.count; self_.slots=canonicalBucketsSlots(view.slots); }
fn clear(self_: Buckets&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn deinit(self_: Buckets&) { if self_.slots.len!=0 { bucket_slots.free_slice(self_.slots); } self_.slots=default<dictionary_slot<u64,u32>[:]>(); self_.count=0; }
fn reserve(self_: Buckets&,count: i64) -> Error { if count<0||count>0x1555555555555555 { return blot_error::Error.out_of_memory; } var capacity=max(8,self_.slots.len); while count*3>capacity*2 { capacity*=2; } if capacity>self_.slots.len { var view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::grow(view,capacity,bucket_slots); self_.count=view.count; self_.slots=canonicalBucketsSlots(view.slots); } return blot_error::Error.none; }
fn copyBuckets(destination: Buckets&,source: const Buckets&) { if destination.slots.len!=0 { bucket_slots.free_slice(destination.slots); } destination.slots=default<dictionary_slot<u64,u32>[:]>(); destination.count=source.count; if source.slots.len!=0 { destination.slots=bucket_slots.alloc_slice(source.slots.len); for slot,index in source.slots { destination.slots[index]=slot; } } }
fn ownedBuckets(value:const Buckets&)->Buckets {
 assert(value.count>=0 && value.count<=value.slots.len);
 if value.slots.len==0 {assert(value.count==0);return Buckets{};}
 let registered=bucket_slots.realloc_slice(value.slots,value.slots.len);assert(blot_support::same_slice_identity(registered,value.slots));
 let start=bucket_slots.index_of(registered[0]);return Buckets{count:value.count,slots:bucket_slots[start..start+registered.len]};
}
