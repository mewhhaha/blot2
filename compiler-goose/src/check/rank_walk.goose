// Bounded scope-aware walks retain lexical binder handles.
namespace blot_check_rank_walk;
import support.error;
struct Walker {
    store: blot_check_types::Store&, rigid_scope: u32, free_bound: bool,
    collected: blot_check_types::Id[>..]&, remaining: i64&,
    collecting: bool = false, budgeted: bool = false, quantifier: bool = false,
    scopes: blot_check_types::List[128] = [blot_check_types::List {}; 128],
    scope_depth: i64 = 0, steps: i64 = 0,
    excluded: const blot_check_types::Id[:] = [],
}
recursive fn visit(self: Walker&, root: blot_check_types::Id, depth: i64) -> bool, blot_error::Error {
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
                for previous in self.collected { if previous == id { return false, blot_error::Error.none; } }
                self.collected.push(id);
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
                let found, error = visit(self, self.store.extra[node.a + index], depth + 1);
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
recursive fn visitQuantifier(self: Walker&, id: blot_check_types::Id, body: blot_check_types::Id, depth: i64) -> bool, blot_error::Error {
    let found, error = visit(self, body, depth + 1);
    if error != blot_error::Error.none || found { return found, error; }
    var goals: blot_check_types::Obligation[>..] = [];
    goals.append(self.store.quantifierGoals(id));
    for goal in goals {
        for endpoint in [goal.ty, goal.other, goal.result, goal.signature] {
            let found, error = visit(self, endpoint, depth + 1);
            if error != blot_error::Error.none || found { return found, error; }
        }
        if goal.identity.unit == 0 && goal.identity.decl != 0 {
            let found, error = visit(self, goal.identity.decl, depth + 1);
            if error != blot_error::Error.none || found { return found, error; }
        }
    }
    return false, blot_error::Error.none;
}
recursive fn row(self: Walker&, root: blot_check_effects::Id, depth: i64) -> bool, blot_error::Error {
    let id, resolution = self.store.resolveEffects(root, 0);
    if resolution != blot_error::Error.none { return false, resolution; }
    let row_ = self.store.row(id);
    match row_.tail { formal v => {
        let found, error = visit(self, v.value, depth + 1);
        if error != blot_error::Error.none || found { return found, error; }
    }, _ => {} }
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
    var collected: blot_check_types::Id[>..] = []; var remaining: i64 = 0;
    var walker = Walker { store, rigid_scope, free_bound, collected, remaining };
    return visit(walker, root, 0);
}
fn quantified(store: blot_check_types::Store&, root: blot_check_types::Id) -> bool, blot_error::Error {
    var collected: blot_check_types::Id[>..] = []; var remaining: i64 = 0;
    var walker = Walker { store, 0, false, collected, remaining, quantifier: true };
    return visit(walker, root, 0);
}
fn containsRow(store: blot_check_types::Store&, root: blot_check_effects::Id, rigid_scope: u32) -> bool, blot_error::Error {
    var collected: blot_check_types::Id[>..] = []; var remaining: i64 = 0;
    var walker = Walker { store, rigid_scope, false, collected, remaining };
    return row(walker, root, 0);
}
fn containsExcept(store: blot_check_types::Store&, root: blot_check_types::Id, scope: u32,
                  excluded: const blot_check_types::Id[:], remaining: i64&) -> bool, blot_error::Error {
    var collected: blot_check_types::Id[>..] = [];
    var walker = Walker { store, scope, false, collected, remaining, excluded: excluded, budgeted: true };
    return visit(walker, root, 0);
}
fn collectRigids(store: blot_check_types::Store&, root: blot_check_types::Id, scope: u32,
                 collected: blot_check_types::Id[>..]&, remaining: i64&) -> blot_error::Error {
    var walker = Walker { store, scope, false, collected, remaining, collecting: true, budgeted: true };
    let found, error = visit(walker, root, 0);
    return error;
}
