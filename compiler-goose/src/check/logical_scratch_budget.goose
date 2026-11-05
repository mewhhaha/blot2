// Zig 0.17 x86_64 FixedBufferAllocator accounting, without byte storage or casts.
namespace blot_check_logical_scratch_budget;
import support.error;
type Error=blot_error::Error;
struct Budget {limit:i64,end:i64=0}
struct ArrayBlock {offset:i64=-1,capacity:i64=0,element_size:i64,alignment:i64}
fn ensure(budget:Budget&,block:ArrayBlock&,minimum:i64)->Error {
    if minimum<=block.capacity {return Error.none;}
    let initial=max(1,64/block.element_size);if minimum>0x5555555555555540-initial {return Error.out_of_memory;}let capacity=minimum+minimum/2+initial;
    if capacity>budget.limit/block.element_size {return Error.out_of_memory;}let bytes=capacity*block.element_size;let old_bytes=block.capacity*block.element_size;
    if block.offset>=0 && block.offset+old_bytes==budget.end {
        if bytes>budget.limit-block.offset {return Error.out_of_memory;}budget.end=block.offset+bytes;block.capacity=capacity;return Error.none;
    }
    let offset=(budget.end+block.alignment-1)& ~(block.alignment-1);
    if offset>budget.limit || bytes>budget.limit-offset {return Error.out_of_memory;}
    budget.end=offset+bytes;block.offset=offset;block.capacity=capacity;return Error.none;
}
fn release(budget:Budget&,block:ArrayBlock&) {if block.offset>=0 && block.offset+block.capacity*block.element_size==budget.end {budget.end=block.offset;}block.offset=-1;block.capacity=0;}
