// Copy open graphs between owners, preserving aliases and freshening binders.
namespace blot_reuse_principal_type_graph;
import std;
import dictionary;
import check.types;
import check.effects;
import check.frozen_types;
import check.core;
import support.error;
import support.option;
import support.native;
import support.pooled_map;
import support.pooled_buffer;
type Error = blot_error::Error;
type Id = u32;
type Tag = blot_check_types::Tag;
type Store = blot_check_types::Store;
type Source = blot_check_frozen_types::Source;
type Tail = blot_check_effects::Tail;
fn allUnknown(source: const Store&, root: Id, max_depth: i64) -> bool {
    var cursor = root;
    for depth in max_depth {
        let node = source.node(cursor); if node.tag != Tag.function { return node.tag == Tag.variable; }
        if source.node(node.a).tag != Tag.variable { return false; }
        let row = source.row(node.c);
        if row.labels.len != 0 { return false; }
        match row.tail { Tail.parameter => { return false; }, _ => {} }
        cursor = node.b;
    }
    return false;
}
struct Pair { principal: Id, actual: Id, ambient: bool }
fn hash(pair:Pair)->u64 {var value=(pair.principal as u64)<<32|pair.actual as u64;if pair.ambient {value^=0x9e3779b185ebca87;}return value;}
struct Item { pair: Pair, depth: i64 }
struct MatchedRow { variable: blot_support::Option<u32>, cursor: u32 }
fn matchesOpen(source: const Store&, principal: Id, caller: const Store&, actual: Id, max_depth: i64, max_nodes: i64) -> bool, Error {
    return matches(source, principal, caller, actual, max_depth, max_nodes, false);
}
fn sameOpen(source: const Store&, left: Id, right: Id, max_depth: i64, max_nodes: i64) -> bool, Error {
    return matches(source, left, source, right, max_depth, max_nodes, true);
}
fn room(maximum: i64, used: i64, needed: i64) -> bool { used <= maximum && needed <= maximum - used }
fn matches(source: const Store&, principal: Id, caller: const Store&, actual: Id,
    max_depth: i64, max_nodes: i64, exact_binders: bool) -> bool, Error {
    var pending: Item[>..<] = [];
    var seen: dictionary<Pair,bool> = dictionary<Pair,bool> {};
    var variables: dictionary<u32,Id> = dictionary<u32,Id> {};
    var rows: dictionary<u32,MatchedRow> = dictionary<u32,MatchedRow> {};
    pending.push(Item { Pair { principal, actual, true }, 0 , ..});
    while pending.len != 0 {
        let item = pending[pending.len - 1]; pending.resize(pending.len - 1);
        if item.depth >= max_depth { return false, Error.none; }
        let original = source.head(item.pair.principal, 0); let live = caller.head(item.pair.actual, 0);
        let key = Pair { original, live, item.pair.ambient , ..};
        if seen.contains(key) { continue; }
        if seen.count >= max_nodes { return false, Error.none; } seen.insert(key, true);
        let from = source.node(original); let to = caller.node(live);
        if from.tag == Tag.variable {
            if to.tag != Tag.variable || exact_binders && original != live { return false, Error.none; }
            { let optional_source_25 .= variables.get(from.a); if optional_source_25 { let known = optional_source_25; if known != live { return false, Error.none; }  }
            else { variables.insert(from.a, live); } }
            continue;
        }
        if from.tag != to.tag { return false, Error.none; }
        let depth = item.depth + 1;
        match from.tag {
            Tag.usage => {
                if from.b != to.b || (from.c == 0) != (to.c == 0) { return false, Error.none; }
                pending.push(Item { Pair { from.a, to.a, false }, depth , ..});
                if from.c != 0 { pending.push(Item { Pair { from.c, to.c, false }, depth , ..}); }
            },
            Tag.scoped => {
                if from.b != to.b { return false, Error.none; }
                if from.b == 0 { pending.push(Item { Pair { from.c, to.c, false }, depth , ..}); }
                else if from.c != to.c { return false, Error.none; }
                pending.push(Item { Pair { from.a, to.a, false }, depth , ..});
            },
            Tag.function => {
                let before = source.row(from.c); let after = caller.row(to.c);
                if before.labels.len > max_nodes { return false, Error.none; }
                if exact_binders && (before.tail != after.tail || before.cursor != after.cursor) { return false, Error.none; }
                if before.labels.len != after.labels.len { return false, Error.none; }
                match before.tail { Tail.parameter => { return false, Error.none; }, _ => {} }
                match after.tail { Tail.parameter => { return false, Error.none; }, _ => {} }
                let left_labels = source.rowLabels(from.c); let right_labels = caller.rowLabels(to.c);
                for left, index in left_labels {
                    let right = right_labels[index]; let old = source.operation(left); let current = caller.operation(right);
                    if old.identity != current.identity { return false, Error.none; }
                    if old.instance.unit == 0 && old.instance.decl != 0 && current.instance.unit == 0 && current.instance.decl != 0 {
                        pending.push(Item { Pair { old.instance.decl, current.instance.decl, false }, depth , ..});
                    } else if old.instance != current.instance { return false, Error.none; }
                    let arguments = source.operationArguments(left); let actuals = caller.operationArguments(right);
                    if arguments.len != actuals.len || !room(max_nodes, pending.len, arguments.len) { return false, Error.none; }
                    for argument, i in arguments { pending.push(Item { Pair { argument, actuals[i], false }, depth , ..}); }
                }
                // Only the covariant ambient return spine may keep an open
                // caller view of a pure source row. Callback inputs stay exact.
                if before.tail == Tail.closed && (before.labels.len != 0 || !item.pair.ambient) && after.tail != Tail.closed {
                    return false, Error.none;
                }
                match before.tail {
                    Tail.variable variable => {
                        var row = MatchedRow { cursor: after.cursor , ..};
                        match after.tail { Tail.variable value => { row.variable = blot_support::some(value.value); }, _ => {} }
                        { let optional_source_24 .= rows.get(variable.value); if optional_source_24 { let known = optional_source_24; if known != row { return false, Error.none; }  }
                        else { rows.insert(variable.value, row); } }
                    },
                    _ => {},
                }
                pending.push(Item { Pair { from.a, to.a, false }, depth , ..});
                pending.push(Item { Pair { from.b, to.b, item.pair.ambient }, depth , ..});
            },
            Tag.array, Tag.list, Tag.cursor => { pending.push(Item { Pair { from.a, to.a, false }, depth , ..}); },
            Tag.product, Tag.nominal, Tag.instance_selection => {
                let nominal = from.tag == Tag.nominal || from.tag == Tag.instance_selection;
                if nominal && (from.a != to.a || from.b != to.b) { return false, Error.none; }
                var left: const Id[:] = []; var right: const Id[:] = [];
                if nominal { left = source.nominalArguments(from); right = caller.nominalArguments(to); }
                else { left = source.list(blot_check_types::List { from.a, from.b , ..}); right = caller.list(blot_check_types::List { to.a, to.b , ..}); }
                if left.len != right.len || !room(max_nodes, pending.len, left.len) { return false, Error.none; }
                for child, index in left { pending.push(Item { Pair { child, right[index], false }, depth , ..}); }
            },
            Tag.record => {
                if from.b != to.b || !room(max_nodes, pending.len, from.b) { return false, Error.none; }
                for index in from.b {
                    let left = source.recordField(from, index); let right = caller.recordField(to, index);
                    if left.name != right.name { return false, Error.none; }
                    pending.push(Item { Pair { left.ty, right.ty, false }, depth , ..});
                }
            },
            Tag.instance_version => { if from.a != to.a || from.b != to.b || from.c != to.c { return false, Error.none; } },
            Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32, Tag.never => {},
            _ => { return false, Error.none; },
        }
    }
    return true, Error.none;
}

type WordMap=blot_support_pooled_map::Map<u32,u32>;
reusable[] var copy_map_slots:dictionary_slot<u32,u32>[>..]=[];
fn get(self:const WordMap&,key:u32)->u32? {return blot_support_pooled_map::get(self,key);}
fn insert(self:WordMap&,key:u32,value:u32) {blot_support_pooled_map::insert(self,key,value,copy_map_slots);}
fn restore(self:WordMap&,slots:const dictionary_slot<u32,u32>[:],count:i64) {
 blot_support_pooled_map::deinit(self,copy_map_slots);
 if slots.len!=0 {self.slots=copy_map_slots.alloc_slice(slots.len);for slot,index in slots {self.slots[index]=slot;}}
 self.count=count;
}
fn clear(self:WordMap&) {blot_support_pooled_map::clear(self);}
struct CopyMaps {live:bool=false,generation:u64=0,types:WordMap=WordMap {..},variables:WordMap=WordMap {..},rows:WordMap=WordMap {..},row_variables:WordMap=WordMap {..},labels:WordMap=WordMap {..}}
reusable var map_owners:CopyMaps[>..]=[];
var inactive_maps:CopyMaps=CopyMaps {..};
struct Copier {
 source:Source=Source.inactive,destination:Store=Store {..},max_depth:i64=0,max_nodes:i64=0,frozen:bool=false,remaining:i64?=null,projection_observed:i64?=null,
 types:WordMap&=inactive_maps.types,variables:WordMap&=inactive_maps.variables,rows:WordMap&=inactive_maps.rows,row_variables:WordMap&=inactive_maps.row_variables,labels:WordMap&=inactive_maps.labels,
 lease:u32=0,generation:u64=0,
}
type Copy=Copier;
type NormalizedCopy=Copier;
type FrozenCopy=Copier;
fn valid(self:const Copier&)->bool {return self.lease!=0&&self.lease-1<map_owners.len&&map_owners[self.lease-1].live&&map_owners[self.lease-1].generation==self.generation;}
fn initPooled(source:Source,destination:Store,max_depth:i64,max_nodes:i64,frozen:bool,remaining:i64?=null,observed:i64?=null)->Copier,Error {
 if map_owners.len>=0xffffffff {return Copier {..},Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=map_owners.alloc_index(CopyMaps {live:true,generation:generation, ..});let maps:CopyMaps&=map_owners[at];
 return Copier {source,destination,max_depth,max_nodes,frozen,remaining,observed,maps.types,maps.variables,maps.rows,maps.row_variables,maps.labels,(at+1) as u32,generation, ..},Error.none;
}
fn deinit(self:Copier&) {
 if self.lease==0 {return;}assert(valid(self));blot_support_pooled_map::deinit(self.types,copy_map_slots);blot_support_pooled_map::deinit(self.variables,copy_map_slots);blot_support_pooled_map::deinit(self.rows,copy_map_slots);blot_support_pooled_map::deinit(self.row_variables,copy_map_slots);blot_support_pooled_map::deinit(self.labels,copy_map_slots);let at=self.lease-1;map_owners[at].live=false;self=Copier {..};map_owners.free(at);
}
struct Words {storage:u32[:]=[],items:u32[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var word_scratch:u32[>..]=[];
fn push(self:Words&,value:u32) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,word_scratch);self.len=self.items.len;}
fn append(self:Words&,values:const u32[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,word_scratch);self.len=self.items.len;}
fn deinit(self:Words&) {blot_support_pooled_buffer::deinit(self,word_scratch);self.len=0;self.failure=Error.none;}
struct Goals {storage:blot_check_types::Obligation[:]=[],items:blot_check_types::Obligation[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var goal_scratch:blot_check_types::Obligation[>..]=[];
fn push(self:Goals&,value:blot_check_types::Obligation) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,goal_scratch);self.len=self.items.len;}
fn deinit(self:Goals&) {blot_support_pooled_buffer::deinit(self,goal_scratch);self.len=0;self.failure=Error.none;}
struct Fields {storage:blot_check_types::Field[:]=[],items:blot_check_types::Field[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var field_scratch:blot_check_types::Field[>..]=[];
fn push(self:Fields&,value:blot_check_types::Field) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,field_scratch);self.len=self.items.len;}
fn deinit(self:Fields&) {blot_support_pooled_buffer::deinit(self,field_scratch);self.len=0;self.failure=Error.none;}
fn charge(self: Copier&) -> Error {
    { let optional_source_23 .= self.remaining; if optional_source_23 { let remaining .= optional_source_23;
        { let optional_source_22 .= self.projection_observed; if optional_source_22 { let observed .= optional_source_22;
            let spent = self.destination.projection_steps - observed;
            if spent > remaining { return Error.type_limit; }
            remaining -= spent; observed = self.destination.projection_steps;
         } }
        if remaining == 0 { return Error.type_limit; } remaining--;
        if self.projection_observed != null { self.destination.projection_limit = self.destination.projection_steps + remaining; }
     } }
    return Error.none;
}
recursive fn ty(self: Copier&, original: Id, depth: i64) -> Id, Error {
    assert(valid(self));
    if self.frozen {
        match self.source {
            Source.store store => { assert(store.value.versions.len == 0 && store.value.effects.versions.len == 0); },
            _ => {},
        }
    }
    if original <= 5 { return original, Error.none; }
    if depth >= self.max_depth || self.types.count >= self.max_nodes { return 0, Error.type_limit; }
    { let optional_source_21 .= self.types.get(original); if optional_source_21 { let known = optional_source_21; return known, Error.none;  } }
    let charged = self.charge(); if charged != Error.none { return 0, charged; }
    let root = self.source.head(original, 0);
    if root != original {
        let result, error = self.ty(root, depth + 1); if error != Error.none { return 0, error; }
        self.types.insert(original, result); return result, Error.none;
    }
    let node = self.source.node(root);
    var result: Id = 0; var failure = Error.none;
    match node.tag {
        Tag.bound, Tag.rigid, Tag.erased_proof => { return 0, Error.type_limit; },
        Tag.forall,Tag.existential=>{let value,error=self.copyQuantified(node,root,depth);result=value;failure=error;},
        Tag.instance_version => { let value, error = self.destination.instanceVersion(blot_check_types::NominalIdentity { node.a, node.b , ..}, node.c); result = value; failure = error; },
        Tag.variable => {
            { let optional_source_20 .= self.variables.get(node.a); if optional_source_20 { let known = optional_source_20; result = known;  }
            else { let value, error = self.destination.fresh(); if error != Error.none { return 0, error; } self.variables.insert(node.a, value); result = value; } }
        },
        Tag.usage => {
            let payload, error = self.ty(node.a, depth + 1); if error != Error.none { return 0, error; }
            var region: Id = 0;
            if node.c != 0 { let value, error = self.ty(node.c, depth + 1); if error != Error.none { return 0, error; } region = value; }
            let value, error = self.destination.usage(payload, node.b as blot_check_types::UsageKind, region); result = value; failure = error;
        },
        Tag.scoped => {
            let descriptor, error = self.ty(node.a, depth + 1); if error != Error.none { return 0, error; }
            var identity = blot_check_types::NominalIdentity { node.b, node.c , ..};
            if node.b == 0 { let value, error = self.ty(node.c, depth + 1); if error != Error.none { return 0, error; } identity.decl = value; }
            let value, error = self.destination.scoped(descriptor, identity); result = value; failure = error;
        },
        Tag.function => {
            let parameter, e1 = self.ty(node.a, depth + 1); if e1 != Error.none { return 0, e1; }
            let output, e2 = self.ty(node.b, depth + 1); if e2 != Error.none { return 0, e2; }
            let row, e3 = self.row(node.c, depth + 1); if e3 != Error.none { return 0, e3; }
            let value, error = self.destination.functionWithEffects(parameter, output, row); result = value; failure = error;
        },
        Tag.array, Tag.list, Tag.cursor => {
            let element, error = self.ty(node.a, depth + 1); if error != Error.none { return 0, error; }
            let value, error = self.destination.sequence(node.tag, element); result = value; failure = error;
        },
        Tag.provider => {
            let operation, e1 = self.ty(node.a, depth + 1); if e1 != Error.none { return 0, e1; }
            let effects, e2 = self.row(node.c, depth + 1); if e2 != Error.none { return 0, e2; }
            let value, error = self.destination.provider(operation, effects); result = value; failure = error;
        },
        Tag.resolver => {
            let target, error = self.ty(node.a, depth + 1); if error != Error.none { return 0, error; }
            let value, error = self.destination.resolver(target); result = value; failure = error;
        },
        Tag.state_provider => {
            let read, e1 = self.ty(node.a, depth + 1); if e1 != Error.none { return 0, e1; }
            let write, e2 = self.ty(node.b, depth + 1); if e2 != Error.none { return 0, e2; }
            let state, e3 = self.ty(node.c, depth + 1); if e3 != Error.none { return 0, e3; }
            let value, error = self.destination.stateProvider(read, write, state); result = value; failure = error;
        },
        Tag.type_constructor => { let value, error = self.destination.typeConstructor(blot_check_types::NominalIdentity { node.a, node.b , ..}); result = value; failure = error; },
        Tag.record=>{let value,error=self.copyRecord(node,depth);result=value;failure=error;},
        Tag.product,Tag.nominal,Tag.projection,Tag.instance_selection=>{let value,error=self.copyChildren(node,depth);result=value;failure=error;},
        Tag.absent, Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32, Tag.never => { assert(false); },
    }
    if failure != Error.none { return 0, failure; } self.types.insert(original, result); return result, Error.none;
}
fn rowVariable(self: Copier&, variable: u32) -> Id, Error {
    { let optional_source_19 .= self.row_variables.get(variable); if optional_source_19 { let known = optional_source_19; return known, Error.none;  } }
    if self.row_variables.count >= self.max_nodes { return 0, Error.type_limit; }
    let charged = self.charge(); if charged != Error.none { return 0, charged; }
    let fresh, error = self.destination.freshEffects(); if error != Error.none { return 0, error; }
    self.row_variables.insert(variable, fresh); return fresh, Error.none;
}
recursive fn row(self: Copier&, original: Id, depth: i64) -> Id, Error {
    assert(valid(self));
    if original == 0 { return 0, Error.none; }
    if depth >= self.max_depth || self.rows.count >= self.max_nodes { return 0, Error.type_limit; }
    { let optional_source_18 .= self.rows.get(original); if optional_source_18 { let known = optional_source_18; return known, Error.none;  } }
    let charged = self.charge(); if charged != Error.none { return 0, charged; }
    var copied=Words {..};
    recursive fn cleanup_continuation_6() -> Id, Error {

let source = self.source.row(original);
    for operation in self.source.rowLabels(source.labels) {
        let value, error = self.label(operation, depth + 1); if error != Error.none { return 0, error; } copied.push(value);if copied.failure!=Error.none {return 0,copied.failure;}
    }
    if copied.failure!=Error.none {return 0,copied.failure;}
    var result: Id = 0; var failure = Error.none;
    match source.tail {
        Tail.closed => { let value, error = self.destination.effects.row(copied.items, Tail.closed); result = value; failure = blot_check_types::effectError(error); },
        Tail.variable variable => {
            let replacement, error = self.rowVariable(variable.value); if error != Error.none { return 0, error; }
            if copied.len == 0 { result = replacement; }
            else {
                let resolved, error = self.destination.resolveEffects(replacement, 0); if error != Error.none { return 0, error; }
                let row = self.destination.row(resolved); copied.append(self.destination.rowLabels(resolved));
                if copied.failure!=Error.none {return 0,copied.failure;}let value, error = self.destination.effects.rowAt(copied.items, row.tail, row.cursor); result = value; failure = blot_check_types::effectError(error);
            }
        },
        Tail.formal formal => {
            let ty, error = self.ty(formal.value, depth + 1); if error != Error.none { return 0, error; }
            let value, error = self.destination.effects.row(copied.items, Tail.formal { ty , ..}); result = value; failure = blot_check_types::effectError(error);
        },
        Tail.parameter => { return 0, Error.type_limit; },
    }
    if failure != Error.none { return 0, failure; } self.rows.insert(original, result); return result, Error.none;

    }
    let cleanup_result_6_0,cleanup_result_6_1 = cleanup_continuation_6();
    copied.deinit();
    return cleanup_result_6_0,cleanup_result_6_1;
}
recursive fn label(self: Copier&, original: Id, depth: i64) -> Id, Error {
    assert(valid(self));
    if depth >= self.max_depth || self.labels.count >= self.max_nodes { return 0, Error.type_limit; }
    { let optional_source_17 .= self.labels.get(original); if optional_source_17 { let known = optional_source_17; return known, Error.none;  } }
    let charged = self.charge(); if charged != Error.none { return 0, charged; }
    let operation = self.source.operation(original); var arguments=Words {..};
    recursive fn cleanup_continuation_5() -> Id, Error {

    for old in self.source.list(operation.arguments) {
        let value, error = self.ty(old, depth + 1); if error != Error.none { return 0, error; } arguments.push(value);if arguments.failure!=Error.none {return 0,arguments.failure;}
    }
    if arguments.failure!=Error.none {return 0,arguments.failure;}
    var instance = operation.instance;
    if instance.unit == 0 && instance.decl != 0 {
        let value, error = self.ty(instance.decl, depth + 1); if error != Error.none { return 0, error; } instance.decl = value;
    }
    let result, error = self.destination.internScopedOperation(operation.identity, instance, arguments.items);
    if error != Error.none { return 0, error; } self.labels.insert(original, result); return result, Error.none;

    }
    let cleanup_result_5_0,cleanup_result_5_1 = cleanup_continuation_5();
    arguments.deinit();
    return cleanup_result_5_0,cleanup_result_5_1;
}

recursive fn copyQuantified(self:Copier&,node:blot_check_types::Node,root:u32,depth:i64)->Id,Error {

            var binders=Words {..};
    recursive fn cleanup_continuation_4() -> Id,Error {

var goals=Goals {..};
    recursive fn cleanup_continuation_3() -> Id,Error {

            let old = self.source.list(blot_check_types::List { node.b, node.c , ..});
            for binder_source in old {
                let leaf = self.source.node(binder_source); if leaf.tag != Tag.bound { return 0, Error.type_limit; }
                let binder, error = self.destination.boundType(leaf.a, leaf.b); if error != Error.none { return 0, error; }
                binders.push(binder);if binders.failure!=Error.none {return 0,binders.failure;} self.types.insert(binder_source, binder);
            }
            let body, error = self.ty(node.a, depth + 1); if error != Error.none { return 0, error; }
            
            if binders.failure!=Error.none {return 0,binders.failure;}
for old_goal in self.source.quantifierGoals(root) {
                var goal = old_goal;
                let ty, ty_error = self.ty(goal.ty, depth + 1); if ty_error != Error.none { return 0, ty_error; } goal.ty = ty;
                let other, other_error = self.ty(goal.other, depth + 1); if other_error != Error.none { return 0, other_error; } goal.other = other;
                let selected, result_error = self.ty(goal.result, depth + 1); if result_error != Error.none { return 0, result_error; } goal.result = selected;
                let signature, sig_error = self.ty(goal.signature, depth + 1); if sig_error != Error.none { return 0, sig_error; } goal.signature = signature;
                goal.source = 0; goals.push(goal);if goals.failure!=Error.none {return 0,goals.failure;}
            }
            if goals.failure!=Error.none {return 0,goals.failure;}return self.destination.quantifiedWithGoals(node.tag,body,binders.items,goals.items);
        

    }
    let cleanup_result_3_0,cleanup_result_3_1 = cleanup_continuation_3();
    goals.deinit();
    return cleanup_result_3_0,cleanup_result_3_1;

    }
    let cleanup_result_4_0,cleanup_result_4_1 = cleanup_continuation_4();
    binders.deinit();
    return cleanup_result_4_0,cleanup_result_4_1;
}

recursive fn copyRecord(self:Copier&,node:blot_check_types::Node,depth:i64)->Id,Error {

            var fields=Fields {..};
    recursive fn cleanup_continuation_2() -> Id,Error {

            for index in node.b {
                let old = self.source.recordField(node, index); let ty, error = self.ty(old.ty, depth + 1); if error != Error.none { return 0, error; }
                fields.push(blot_check_types::Field { old.name, ty , ..});if fields.failure!=Error.none {return 0,fields.failure;}
            }
            if fields.failure!=Error.none {return 0,fields.failure;}return self.destination.record(fields.items);
        

    }
    let cleanup_result_2_0,cleanup_result_2_1 = cleanup_continuation_2();
    fields.deinit();
    return cleanup_result_2_0,cleanup_result_2_1;
}

recursive fn copyChildren(self:Copier&,node:blot_check_types::Node,depth:i64)->Id,Error {

            var children: const Id[:] = [];
            if node.tag == Tag.product { children = self.source.list(blot_check_types::List { node.a, node.b , ..}); }
            else { children = self.source.nominalArguments(node); }
            var copied=Words {..};
    recursive fn cleanup_continuation_1() -> Id,Error {

            for child in children { let value, error = self.ty(child, depth + 1); if error != Error.none { return 0, error; } copied.push(value);if copied.failure!=Error.none {return 0,copied.failure;} }
            if copied.failure!=Error.none {return 0,copied.failure;}let identity = blot_check_types::NominalIdentity { node.a, node.b , ..};
            if node.tag == Tag.instance_selection { return self.destination.instanceSelection(identity,copied.items); }
            else if node.tag == Tag.projection { return self.destination.projection(identity,self.source.projectionMember(node),copied.items); }
            else if node.tag == Tag.nominal { return self.destination.nominal(identity,copied.items); }
            else { return self.destination.product(copied.items); }
        

    }
    let cleanup_result_1_0,cleanup_result_1_1 = cleanup_continuation_1();
    copied.deinit();
    return cleanup_result_1_0,cleanup_result_1_1;
}
fn withCopy<C,F>(source:Source,destination:Store&,max_depth:i64,max_nodes:i64,remaining:i64&,observed:i64&,context:C&)->Error {
 var copier,error=initPooled(source,destination,max_depth,max_nodes,false,remaining,observed);if error!=Error.none {return error;}let result=F(context,copier);copier.deinit();return result;
}
fn withFrozenCopy<C,F>(source:Source,destination:Store&,max_depth:i64,max_nodes:i64,remaining:i64&,observed:i64&,context:C&)->Error {
 var copier,error=initPooled(source,destination,max_depth,max_nodes,true,remaining,observed);if error!=Error.none {return error;}let result=F(context,copier);copier.deinit();return result;
}
