// Bounded scope-aware walks retain lexical binder handles.
namespace blot_check_rank_walk;
import support.error;
import support.pooled_buffer;
struct Walker<C> {
    store: blot_check_types::Store, rigid_scope: u32, free_bound: bool,
    collected: C&, remaining: i64&,
    collecting: bool = false, budgeted: bool = false, quantifier: bool = false,
    scopes: blot_check_types::List[128] = [blot_check_types::List {}; 128],
    scope_depth: i64 = 0, steps: i64 = 0,
    excluded: const blot_check_types::Id[:] = [],
}
recursive fn visit<C>(self: Walker<C>&, root: blot_check_types::Id, depth: i64) -> bool, blot_error::Error {
    if root == 0 { return false, blot_error::Error.none; }
    if depth >= 128 || self.steps >= 4096 { return false, blot_error::Error.type_limit; }
    self.steps += 1;
    if self.budgeted {
        if self.remaining == 0 { return false, blot_error::Error.type_limit; }
        self.remaining -= 1;
    }
    let id, error = self.store.resolve(root, 0);
    if error != blot_error::Error.none { return false, error; }
    let node = self.store.node(id);
    match node.tag {
        rigid => {
            if self.free_bound || (self.rigid_scope != 0 && node.a != self.rigid_scope) { return false, blot_error::Error.none; }
            for excluded in self.excluded { if excluded == id { return false, blot_error::Error.none; } }
            if self.collecting {
                for previous in self.collected.values() { if previous == id { return false, blot_error::Error.none; } }
                let append_error=self.collected.push(id);if append_error!=blot_error::Error.none {return false,append_error;}
                return false, blot_error::Error.none;
            }
            return true, blot_error::Error.none;
        },
        bound => {
            if !self.free_bound { return false, blot_error::Error.none; }
            for scope in self.scopes[..self.scope_depth] {
                for binder in self.store.list(scope) { if binder == id { return false, blot_error::Error.none; } }
            }
            return true, blot_error::Error.none;
        },
        forall, existential => {
            if self.quantifier { return true, blot_error::Error.none; }
            if self.scope_depth == self.scopes.len { return false, blot_error::Error.type_limit; }
            self.scopes[self.scope_depth] = blot_check_types::List { node.b, node.c };
            self.scope_depth += 1;
            let result, error = visitQuantifier(self, id, node.a, depth);
            self.scope_depth -= 1;
            return result, error;
        },
        function => {
            let first, e1 = visit(self, node.a, depth + 1); if e1 != blot_error::Error.none || first { return first, e1; }
            let second, e2 = visit(self, node.b, depth + 1); if e2 != blot_error::Error.none || second { return second, e2; }
            return row(self, node.c, depth + 1);
        },
        provider => {
            let first, error = visit(self, node.a, depth + 1); if error != blot_error::Error.none || first { return first, error; }
            return row(self, node.c, depth + 1);
        },
        usage => {
            let first, error = visit(self, node.a, depth + 1); if error != blot_error::Error.none || first { return first, error; }
            if node.c != 0 { return visit(self, node.c, depth + 1); }
        },
        scoped => {
            let first, error = visit(self, node.a, depth + 1); if error != blot_error::Error.none || first { return first, error; }
            if node.b == 0 { return visit(self, node.c, depth + 1); }
        },
        state_provider => {
            for child in [node.a, node.b, node.c] {
                let found, error = visit(self, child, depth + 1); if error != blot_error::Error.none || found { return found, error; }
            }
        },
        array, list, cursor, resolver => { return visit(self, node.a, depth + 1); },
        product => {
            for index in node.b {
                let found, error = visit(self, self.store.extra.items[node.a + index], depth + 1);
                if error != blot_error::Error.none || found { return found, error; }
            }
        },
        record => {
            for index in node.b {
                let found, error = visit(self, self.store.recordField(node, index).ty, depth + 1);
                if error != blot_error::Error.none || found { return found, error; }
            }
        },
        nominal, projection, instance_selection => {
            let length = self.store.nominalArguments(node).len;
            for index in length {
                let found, error = visit(self, self.store.nominalArguments(node)[index], depth + 1);
                if error != blot_error::Error.none || found { return found, error; }
            }
        },
        _ => {},
    }
    return false, blot_error::Error.none;
}
recursive fn visitQuantifier<C>(self: Walker<C>&,id:u32,body:u32,depth:i64)->bool,blot_error::Error {let found,error=visit(self,body,depth+1);if error!=blot_error::Error.none || found {return found,error;}let goals=goal_runs.alloc_slice(self.store.quantifierGoals(id).len);for goal,index in self.store.quantifierGoals(id) {goals[index]=goal;}let result,failure=visitGoals(self,goals,depth);goal_runs.free_slice(goals);return result,failure;}
fn visitGoals<C>(self:Walker<C>&,goals:const blot_check_types::Obligation[:],depth:i64)->bool,blot_error::Error {for goal in goals {for endpoint in [goal.ty,goal.other,goal.result,goal.signature] {let found,error=visit(self,endpoint,depth+1);if error!=blot_error::Error.none || found {return found,error;}}if goal.identity.unit==0 && goal.identity.decl!=0 {let found,error=visit(self,goal.identity.decl,depth+1);if error!=blot_error::Error.none || found {return found,error;}}}return false,blot_error::Error.none;}
recursive fn row<C>(self: Walker<C>&, root: blot_check_effects::Id, depth: i64) -> bool, blot_error::Error {
    let id, resolution = self.store.resolveEffects(root, 0);
    if resolution != blot_error::Error.none { return false, resolution; }
    let row_ = self.store.row(id);
    match row_.tail { formal v => {
        let found, error = visit(self, v.value, depth + 1);
        if error != blot_error::Error.none || found { return found, error; }
    }, _ => {}, }
    for index in row_.labels.len {
        let label = self.store.effects.list(row_.labels)[index];
        let operation = self.store.operation(label);
        for argument in operation.arguments.len {
            let found, error = visit(self, self.store.list(operation.arguments)[argument], depth + 1);
            if error != blot_error::Error.none || found { return found, error; }
        }
        if operation.instance.unit == 0 && operation.instance.decl != 0 {
            let found, error = visit(self, operation.instance.decl, depth + 1);
            if error != blot_error::Error.none || found { return found, error; }
        }
    }
    return false, blot_error::Error.none;
}
fn contains(store: blot_check_types::Store&, root: blot_check_types::Id, rigid_scope: u32, free_bound: bool) -> bool, blot_error::Error {
    var backing=blot_support_pooled_buffer::Buffer<u32>{};var collected=PooledCollector{backing,rigid_runs}; var remaining: i64 = 0;
    var walker = Walker { store, rigid_scope, free_bound, collected, remaining };
    let result,error=visit(walker,root,0);backing.deinit(rigid_runs);return result,error;
}
fn quantified(store: blot_check_types::Store&, root: blot_check_types::Id) -> bool, blot_error::Error {
    var backing=blot_support_pooled_buffer::Buffer<u32>{};var collected=PooledCollector{backing,rigid_runs}; var remaining: i64 = 0;
    var walker = Walker { store, 0, false, collected, remaining, quantifier: true };
    let result,error=visit(walker,root,0);backing.deinit(rigid_runs);return result,error;
}
fn containsRow(store: blot_check_types::Store&, root: blot_check_effects::Id, rigid_scope: u32) -> bool, blot_error::Error {
    var backing=blot_support_pooled_buffer::Buffer<u32>{};var collected=PooledCollector{backing,rigid_runs}; var remaining: i64 = 0;
    var walker = Walker { store, rigid_scope, false, collected, remaining };
    let result,error=row(walker,root,0);backing.deinit(rigid_runs);return result,error;
}
fn containsExcept(store: blot_check_types::Store&, root: blot_check_types::Id, scope: u32,
                  excluded: const blot_check_types::Id[:], remaining: i64&) -> bool, blot_error::Error {
    var backing=blot_support_pooled_buffer::Buffer<u32>{};var collected=PooledCollector{backing,rigid_runs};
    var walker = Walker { store, scope, false, collected, remaining, excluded: excluded, budgeted: true };
    let result,error=visit(walker,root,0);backing.deinit(rigid_runs);return result,error;
}
fn collectRigids(store: blot_check_types::Store&, root: blot_check_types::Id, scope: u32,
                 collected: C&, remaining: i64&) -> blot_error::Error {
    var destination=NativeCollector{collected};var walker = Walker { store, scope, false, destination, remaining, collecting: true, budgeted: true };
    let found, error = visit(walker, root, 0);
    return error;
}

reusable[] var rigid_runs:u32[>..];
reusable[] var goal_runs:blot_check_types::Obligation[>..];
struct NativeCollector {items:u32[>..]&}
fn values(self:NativeCollector&)->const u32[:] {return self.items;}
fn push(self:NativeCollector&,id:u32)->blot_error::Error {self.items.push(id);return blot_error::Error.none;}
struct PooledCollector {items:blot_support_pooled_buffer::Buffer<u32>&,pool:u32[>..]&}
fn values(self:PooledCollector&)->const u32[:] {return self.items.items;}
fn push(self:PooledCollector&,id:u32)->blot_error::Error {return blot_support_pooled_buffer::push(self.items,id,self.pool);}
fn collectRigids(store:blot_check_types::Store&,root:u32,scope:u32,collected:blot_support_pooled_buffer::Buffer<u32>&,pool:u32[>..]&,remaining:i64&)->blot_error::Error {var destination=PooledCollector{collected,pool};var walker=Walker{store,scope,false,destination,remaining,collecting:true,budgeted:true};let found,error=visit(walker,root,0);return error;}
