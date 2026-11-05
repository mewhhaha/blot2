// Zig 0.17 x86_64 FixedBufferAllocator accounting, without byte storage or casts.
namespace blot_check_logical_scratch_budget;
import support.error;

type Error=blot_error::Error;
struct Budget {limit:i64,end:i64=0}
struct ArrayBlock {offset:i64=-1,capacity:i64=0,element_size:i64,alignment:i64}
fn ensure(budget:Budget&,block_:ArrayBlock&,minimum:i64)->Error {
    if minimum<=block_.capacity {return blot_error::Error.none;}
    let initial=max(1,64/block_.element_size);if minimum>0x5555555555555540-initial {return blot_error::Error.out_of_memory;}let capacity=minimum+minimum/2+initial;
    if capacity>budget.limit/block_.element_size {return blot_error::Error.out_of_memory;}let bytes=capacity*block_.element_size;let old_bytes=block_.capacity*block_.element_size;
    if block_.offset>=0 && block_.offset+old_bytes==budget.end {
        if bytes>budget.limit-block_.offset {return blot_error::Error.out_of_memory;}budget.end=block_.offset+bytes;block_.capacity=capacity;return blot_error::Error.none;
    }
    let offset=(budget.end+block_.alignment-1)& ~(block_.alignment-1);
    if offset>budget.limit || bytes>budget.limit-offset {return blot_error::Error.out_of_memory;}
    budget.end=offset+bytes;block_.offset=offset;block_.capacity=capacity;return blot_error::Error.none;
}
fn release(budget:Budget&,block_:ArrayBlock&) {if block_.offset>=0 && block_.offset+block_.capacity*block_.element_size==budget.end {budget.end=block_.offset;}block_.offset=-1;block_.capacity=0;}
