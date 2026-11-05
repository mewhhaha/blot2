// Semantic call arrows are selected before function indices are materialized.
namespace blot_backend_resolved_call;
import .layout;
import reuse.code_artifacts;
import support.error;
struct Arrow { parameter: u32,result: u32,row: u32 }
struct Named { key: blot_reuse_code_artifacts::Key,extra: Arrow[:] = [] }
enum Callee { direct { key: blot_reuse_code_artifacts::Key },wrapper { key: blot_reuse_code_artifacts::CallableKey } }
struct Applied { callee: Callee,consumed: i64,extra: Arrow[:] = [] }
reusable[] var owned_arrows: Arrow[>..] = [];
fn release(values: const Arrow[:]) { if values.len != 0 { let first: const Arrow& = values[0]; let at = owned_arrows.index_of(first); owned_arrows.free_slice(owned_arrows[at..at + values.len]); } }
fn deinit(plan: Named&) { release(plan.extra); plan.extra = []; }
fn deinit(plan: Applied&) { release(plan.extra); plan.extra = []; }
fn copyArrows(values: const Arrow[:]) -> Arrow[:] { if values.len == 0 { return []; } let copied = owned_arrows.alloc_slice(values.len); for value,index in values { copied[index] = value; } return copied; }
fn arrows(store: const blot_backend_layout::Store&,ty: u32,count: i64,out: Arrow[>..<]&) -> u32,blot_error::Error {
    var current = ty; for index in 0..count { let node = store.nodes[current]; if node.tag != blot_backend_layout::Tag.function { return 0,blot_error::Error.not_function; } out.push(Arrow { node.a,node.b,node.c , ..}); current = node.b; } return current,blot_error::Error.none;
}
fn arrows(store: const blot_backend_layout::Store&,ty: u32,count: i64,out: Arrow[:]& ) -> u32,blot_error::Error {
    let before = out.len; var extended = owned_arrows.realloc_slice(out,before + count); var current = ty; var appended: i64 = 0;
    for index in 0..count {
        let node = store.nodes[current]; if node.tag != blot_backend_layout::Tag.function { out = owned_arrows.realloc_slice(extended,before + appended); return 0,blot_error::Error.not_function; }
        extended[before + appended] = Arrow { node.a,node.b,node.c , ..}; appended++; current = node.b;
    }
    out = extended; return current,blot_error::Error.none;
}
