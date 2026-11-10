// Each inlined instance owns its use counts; backedges pin future loop uses.
namespace blot_backend_storage_liveness;
import check.core;
import support.error;
type Error = blot_error::Error;
reusable[] var use_runs: u32[>..] = [];
// Invocation-owned coordinates; release ends this run's lifetime.
struct UseRun {start:i64=0,len:i64=0}
fn ownedUses(run:UseRun)->u32[:] {
 assert(run.start>=0&&run.len>=0&&run.start<=use_runs.len&&run.len<=use_runs.len-run.start);
 if run.len==0 {return default<u32[:]>();}
 let source=use_runs[run.start..run.start+run.len];let owned=use_runs.realloc_slice(source,source.len);
 assert(blot_support::same_slice_identity(owned,source));return owned;
}
fn at(run:UseRun,index:i64)->u32 {assert(index>=0&&index<run.len);let owned=ownedUses(run);return owned[index];}
fn count(module:const blot_check_core::Module&,root:u32)->UseRun,Error {
 let uses=use_runs.alloc_slice(module.bindings.len);for &use in uses {use=0;}
 var budget:i64=100000;let error=visit(module,root,uses,0,budget);
 if error!=blot_error::Error.none {use_runs.free_slice(uses);return UseRun{},error;}
 if uses.len==0 {return UseRun{},blot_error::Error.none;}
 return UseRun{start:use_runs.index_of(uses[0]),len:uses.len},blot_error::Error.none;
}
fn release(run:UseRun) {if run.len!=0 {use_runs.free_slice(ownedUses(run));}}
fn reference(module: const blot_check_core::Module&,binding: blot_check_core::BindingRef,uses: u32[:]) { if (binding.unit == 0 || binding.unit == module.unit) && binding.binding < uses.len { if uses[binding.binding] != 4294967295 { uses[binding.binding]++; } } }
recursive fn visit(module: const blot_check_core::Module&,id: u32,uses: u32[:],depth: i64,budget: i64&) -> Error {
    if id == 0 { return blot_error::Error.none; } if depth > 128 || budget == 0 { return blot_error::Error.limit; } budget--; let node = module.node(id); for child in module.children(id) { let error = visit(module,child,uses,depth + 1,budget); if error != blot_error::Error.none { return error; } }
    match node.tag {
        reference=>{ reference(module,module.reference(id),uses); },
        scalar,associated,logical,apply,record_merge,proof_guard=>{ let left = visit(module,node.a,uses,depth + 1,budget); if left != blot_error::Error.none { return left; } let right = visit(module,node.b,uses,depth + 1,budget); if right != blot_error::Error.none { return right; } },
        if_value,if_stmt=>{ let condition = visit(module,node.a,uses,depth + 1,budget); if condition != blot_error::Error.none { return condition; } let yes = visit(module,node.b,uses,depth + 1,budget); if yes != blot_error::Error.none { return yes; } let no = visit(module,node.c,uses,depth + 1,budget); if no != blot_error::Error.none { return no; } for merge in module.branchMerges(id) { reference(module,blot_check_core::BindingRef { binding: merge.then_binding,..},uses); reference(module,blot_check_core::BindingRef { binding: merge.else_binding,..},uses); } },
        bind,construct,pattern_bind=>{ return visit(module,node.b,uses,depth + 1,budget); },
        update=>{ let info = module.updateInfo(id); let root = visit(module,info.root,uses,depth + 1,budget); if root != blot_error::Error.none { return root; } for selector in module.updateSelectors(id) { match selector.kind { index=>{ let error = visit(module,selector.index,uses,depth + 1,budget); if error != blot_error::Error.none { return error; } },_=>{}, } } return visit(module,info.value,uses,depth + 1,budget); },
        return_,project,usage_read,usage_share=>{ return visit(module,node.a,uses,depth + 1,budget); },
        closure=>{ for binding in module.closureCaptures(id) { reference(module,blot_check_core::BindingRef { binding: binding,..},uses); } },
        loop_=>{ let loop_ = module.loopInfo(id); let first = visit(module,loop_.first,uses,depth + 1,budget); if first != blot_error::Error.none { return first; } let end = visit(module,loop_.end,uses,depth + 1,budget); if end != blot_error::Error.none { return end; } let body = visit(module,loop_.body,uses,depth + 1,budget); if body != blot_error::Error.none { return body; } for carry in module.loopCarries(id) { reference(module,blot_check_core::BindingRef { binding: carry.incoming,..},uses); reference(module,blot_check_core::BindingRef { binding: carry.backedge,..},uses); } },
        match_=>{ for input in module.matchInputs(id) { let error = visit(module,input,uses,depth + 1,budget); if error != blot_error::Error.none { return error; } } for arm in module.matchArms(id) { let guard_ = visit(module,arm.guard_,uses,depth + 1,budget); if guard_ != blot_error::Error.none { return guard_; } let body = visit(module,arm.body,uses,depth + 1,budget); if body != blot_error::Error.none { return body; } } for merge in module.branchMerges(id) { reference(module,blot_check_core::BindingRef { binding: merge.then_binding,..},uses); reference(module,blot_check_core::BindingRef { binding: merge.else_binding,..},uses); } },
        _=>{},
    } return blot_error::Error.none;
}
