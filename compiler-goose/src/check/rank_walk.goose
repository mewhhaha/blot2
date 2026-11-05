// Bounded scope-aware walks retain lexical binder handles.
namespace blot_check_rank_walk;
import check.effects;
import check.types;
import support.error;
import support.pooled_buffer;

type Id=blot_check_types::Id;
type Store=blot_check_types::Store;
struct Walker {
    rigid_scope: u32, free_bound: bool,
    collecting: bool = false, budgeted: bool = false, quantifier: bool = false,
    scopes: blot_check_types::List[128] = [blot_check_types::List {..}; 128],
    scope_depth: i64 = 0, steps: i64 = 0,
}
recursive fn visit<C>(self_: Walker&,store:Store&,collected:C&,pool:Id[>..]&,remaining:i64&,excluded_ids:const Id[:], root: blot_check_types::Id, depth: i64) -> bool, blot_error::Error {
    if root == 0 { return false, blot_error::Error.none; }
    if depth >= 128 || self_.steps >= 4096 { return false, blot_error::Error.type_limit; }
    self_.steps += 1;
    if self_.budgeted {
        if remaining == 0 { return false, blot_error::Error.type_limit; }
        remaining -= 1;
    }
    let id, error = store.resolve(root, 0);
    if error != blot_error::Error.none { return false, error; }
    let node = store.node(id);
    match node.tag {
        rigid => {
            if self_.free_bound || (self_.rigid_scope != 0 && node.a != self_.rigid_scope) { return false, blot_error::Error.none; }
            for excluded in excluded_ids { if excluded == id { return false, blot_error::Error.none; } }
            if self_.collecting {
                for previous in collectedValues(collected) { if previous == id { return false, blot_error::Error.none; } }
                let append_error=collectId(collected,pool,id);if append_error!=blot_error::Error.none {return false,append_error;}
                return false, blot_error::Error.none;
            }
            return true, blot_error::Error.none;
        },
        bound => {
            if !self_.free_bound { return false, blot_error::Error.none; }
            for scope in self_.scopes[..self_.scope_depth] {
                for binder in store.list(scope) { if binder == id { return false, blot_error::Error.none; } }
            }
            return true, blot_error::Error.none;
        },
        forall, existential => {
            if self_.quantifier { return true, blot_error::Error.none; }
            if self_.scope_depth == self_.scopes.len { return false, blot_error::Error.type_limit; }
            self_.scopes[self_.scope_depth] = blot_check_types::List { node.b, node.c , ..};
            self_.scope_depth += 1;
            let result, error = visitQuantifier(self_,store,collected,pool,remaining,excluded_ids, id, node.a, depth);
            self_.scope_depth -= 1;
            return result, error;
        },
        function => {
            let first, e1 = visit(self_,store,collected,pool,remaining,excluded_ids, node.a, depth + 1); if e1 != blot_error::Error.none || first { return first, e1; }
            let second, e2 = visit(self_,store,collected,pool,remaining,excluded_ids, node.b, depth + 1); if e2 != blot_error::Error.none || second { return second, e2; }
            return row(self_,store,collected,pool,remaining,excluded_ids, node.c, depth + 1);
        },
        provider => {
            let first, error = visit(self_,store,collected,pool,remaining,excluded_ids, node.a, depth + 1); if error != blot_error::Error.none || first { return first, error; }
            return row(self_,store,collected,pool,remaining,excluded_ids, node.c, depth + 1);
        },
        usage => {
            let first, error = visit(self_,store,collected,pool,remaining,excluded_ids, node.a, depth + 1); if error != blot_error::Error.none || first { return first, error; }
            if node.c != 0 { return visit(self_,store,collected,pool,remaining,excluded_ids, node.c, depth + 1); }
        },
        scoped => {
            let first, error = visit(self_,store,collected,pool,remaining,excluded_ids, node.a, depth + 1); if error != blot_error::Error.none || first { return first, error; }
            if node.b == 0 { return visit(self_,store,collected,pool,remaining,excluded_ids, node.c, depth + 1); }
        },
        state_provider => {
            for child in [node.a, node.b, node.c] {
                let found, error = visit(self_,store,collected,pool,remaining,excluded_ids, child, depth + 1); if error != blot_error::Error.none || found { return found, error; }
            }
        },
        array, list, cursor, resolver => { return visit(self_,store,collected,pool,remaining,excluded_ids, node.a, depth + 1); },
        product => {
            for index in node.b {
                let found, error = visit(self_,store,collected,pool,remaining,excluded_ids, store.extra.items[node.a + index], depth + 1);
                if error != blot_error::Error.none || found { return found, error; }
            }
        },
        record => {
            for index in node.b {
                let found, error = visit(self_,store,collected,pool,remaining,excluded_ids, store.recordField(node, index).ty, depth + 1);
                if error != blot_error::Error.none || found { return found, error; }
            }
        },
        nominal, projection, instance_selection => {
            let length = store.nominalArguments(node).len;
            for index in length {
                let found, error = visit(self_,store,collected,pool,remaining,excluded_ids, store.nominalArguments(node)[index], depth + 1);
                if error != blot_error::Error.none || found { return found, error; }
            }
        },
        _ => {},
    }
    return false, blot_error::Error.none;
}
recursive fn visitQuantifier<C>(self_: Walker&,store:Store&,collected:C&,pool:Id[>..]&,remaining:i64&,excluded_ids:const Id[:],id:u32,body:u32,depth:i64)->bool,blot_error::Error {let found,error=visit(self_,store,collected,pool,remaining,excluded_ids,body,depth+1);if error!=blot_error::Error.none || found {return found,error;}let goals=goal_runs.alloc_slice(store.quantifierGoals(id).len);for goal,index in store.quantifierGoals(id) {goals[index]=goal;}let result,failure=visitGoals(self_,store,collected,pool,remaining,excluded_ids,goals,depth);goal_runs.free_slice(goals);return result,failure;}
recursive fn visitGoals<C>(self_:Walker&,store:Store&,collected:C&,pool:Id[>..]&,remaining:i64&,excluded_ids:const Id[:],goals:const blot_check_types::Obligation[:],depth:i64)->bool,blot_error::Error {for goal in goals {for endpoint in [goal.ty,goal.other,goal.result,goal.signature] {let found,error=visit(self_,store,collected,pool,remaining,excluded_ids,endpoint,depth+1);if error!=blot_error::Error.none || found {return found,error;}}if goal.identity.unit==0 && goal.identity.decl!=0 {let found,error=visit(self_,store,collected,pool,remaining,excluded_ids,goal.identity.decl,depth+1);if error!=blot_error::Error.none || found {return found,error;}}}return false,blot_error::Error.none;}
recursive fn row<C>(self_: Walker&,store:Store&,collected:C&,pool:Id[>..]&,remaining:i64&,excluded_ids:const Id[:], root: blot_check_effects::Id, depth: i64) -> bool, blot_error::Error {
    let id, resolution = store.resolveEffects(root, 0);
    if resolution != blot_error::Error.none { return false, resolution; }
    let row_ = store.row(id);
    match row_.tail { formal v => {
        let found, error = visit(self_,store,collected,pool,remaining,excluded_ids, v.value, depth + 1);
        if error != blot_error::Error.none || found { return found, error; }
    }, _ => {}, }
    for index in row_.labels.len {
        let label = store.effects.list(row_.labels)[index];
        let operation = store.operation(label);
        for argument in operation.arguments.len {
            let found, error = visit(self_,store,collected,pool,remaining,excluded_ids, store.list(operation.arguments)[argument], depth + 1);
            if error != blot_error::Error.none || found { return found, error; }
        }
        if operation.instance.unit == 0 && operation.instance.decl != 0 {
            let found, error = visit(self_,store,collected,pool,remaining,excluded_ids, operation.instance.decl, depth + 1);
            if error != blot_error::Error.none || found { return found, error; }
        }
    }
    return false, blot_error::Error.none;
}
fn contains(store:Store&,root:Id,rigid_scope:u32,free_bound:bool)->bool,blot_error::Error {
 var collected=blot_support_pooled_buffer::Buffer<u32>{..};var remaining:i64=0;var walker=Walker{rigid_scope:rigid_scope,free_bound:free_bound,..};
 let result,error=visit(walker,store,collected,rigid_runs,remaining,default<const Id[:]>(),root,0);blot_support_pooled_buffer::deinit(collected,rigid_runs);return result,error;
}
fn quantified(store:Store&,root:Id)->bool,blot_error::Error {
 var collected=blot_support_pooled_buffer::Buffer<u32>{..};var remaining:i64=0;var walker=Walker{rigid_scope:0,free_bound:false,quantifier:true,..};
 let result,error=visit(walker,store,collected,rigid_runs,remaining,default<const Id[:]>(),root,0);blot_support_pooled_buffer::deinit(collected,rigid_runs);return result,error;
}
fn containsRow(store:Store&,root:blot_check_effects::Id,rigid_scope:u32)->bool,blot_error::Error {
 var collected=blot_support_pooled_buffer::Buffer<u32>{..};var remaining:i64=0;var walker=Walker{rigid_scope:rigid_scope,free_bound:false,..};
 let result,error=row(walker,store,collected,rigid_runs,remaining,default<const Id[:]>(),root,0);blot_support_pooled_buffer::deinit(collected,rigid_runs);return result,error;
}
fn containsExcept(store:Store&,root:Id,scope:u32,excluded:const Id[:],remaining:i64&)->bool,blot_error::Error {
 var collected=blot_support_pooled_buffer::Buffer<u32>{..};var walker=Walker{rigid_scope:scope,free_bound:false,budgeted:true,..};
 let result,error=visit(walker,store,collected,rigid_runs,remaining,excluded,root,0);blot_support_pooled_buffer::deinit(collected,rigid_runs);return result,error;
}
fn collectRigids(store:Store&,root:Id,scope:u32,collected:u32[>..]&,remaining:i64&)->blot_error::Error {var walker=Walker{rigid_scope:scope,free_bound:false,collecting:true,budgeted:true,..};let found,error=visit(walker,store,collected,rigid_runs,remaining,default<const Id[:]>(),root,0);return error;}
fn collectRigids(store:Store&,root:Id,scope:u32,collected:blot_support_pooled_buffer::Buffer<u32>&,pool:u32[>..]&,remaining:i64&)->blot_error::Error {var walker=Walker{rigid_scope:scope,free_bound:false,collecting:true,budgeted:true,..};let found,error=visit(walker,store,collected,pool,remaining,default<const Id[:]>(),root,0);return error;}
reusable[] var rigid_runs:u32[>..];
reusable[] var goal_runs:blot_check_types::Obligation[>..];
fn collectedValues(collected:const u32[>..]&)->const u32[:] {return collected;}
fn collectedValues(collected:const blot_support_pooled_buffer::Buffer<u32>&)->const u32[:] {return collected.items;}
fn collectId(collected:u32[>..]&,pool:u32[>..]&,id:u32)->blot_error::Error {collected.push(id);return blot_error::Error.none;}
fn collectId(collected:blot_support_pooled_buffer::Buffer<u32>&,pool:u32[>..]&,id:u32)->blot_error::Error {return blot_support_pooled_buffer::push(collected,id,pool);}
