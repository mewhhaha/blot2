// Copied module headers may share one exact immutable payload catalog.
// A process-local owner number alone is never a correspondence proof.
namespace blot_reuse_catalog_storage;
import check.core;
fn same(left:const blot_check_core::Module[:],right:const blot_check_core::Module[:])->bool {
    if left.len!=right.len {return false;}
    for before,index in left {
        let after=right[index];
        if before.owner_id==0 || after.owner_id==0 || before.types.owner_id==0 || after.types.owner_id==0 {return false;}
        // Composite equality compares every scalar and exact nested slice/ref
        // identity; it does not accept an equal digest or equal payload bytes.
        if before!=after {return false;}
    }
    return true;
}
