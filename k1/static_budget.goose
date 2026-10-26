// Private fixture budget helpers. Steps and output bytes use the stated K1
// numeric ceilings, but expression-tree depth 128 is a separate conservative
// fixture cap: this subset has no static calls and does not implement K1's
// static call-depth limit. This is not the shared semantic policy or receipt.
namespace static_budget;
struct Budget {steps:u32=0,bytes:u32=0,failed:bool=false}
fn enter(depth:u32) -> bool {return depth<=128;}
fn step(b:Budget&) -> bool {
    if b.failed || b.steps>=100000 {b.failed=true;return false;}
    b.steps+=1;return true;
}
fn produce(b:Budget&,n:u32) -> bool {
    if b.failed || b.bytes>4194304 || n>4194304-b.bytes {b.failed=true;return false;}
    b.bytes+=n;return true;
}
