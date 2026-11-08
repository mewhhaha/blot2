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
        let node = source.node(cursor); if node.tag != blot_check_types::Tag.function { return node.tag == blot_check_types::Tag.variable; }
        if source.node(node.a).tag != blot_check_types::Tag.variable { return false; }
        let row = source.row(node.c);
        if row.labels.len != 0 { return false; }
        match row.tail { parameter => { return false; }, _ => {} }
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
        if item.depth >= max_depth { return false, blot_error::Error.none; }
        let original = source.head(item.pair.principal, 0); let live = caller.head(item.pair.actual, 0);
        let key = Pair { original, live, item.pair.ambient , ..};
        if ::contains(seen,key) { continue; }
        if seen.count >= max_nodes { return false, blot_error::Error.none; } ::insert(seen,key, true);
        let from = source.node(original); let to = caller.node(live);
        if from.tag == blot_check_types::Tag.variable {
            if to.tag != blot_check_types::Tag.variable || exact_binders && original != live { return false, blot_error::Error.none; }
            { let optional_source_25 .= ::get(variables,from.a); if optional_source_25 { let known = optional_source_25; if known != live { return false, blot_error::Error.none; }  }
            else { ::insert(variables,from.a, live); } }
            continue;
        }
        if from.tag != to.tag { return false, blot_error::Error.none; }
        let depth = item.depth + 1;
        match from.tag {
            usage => {
                if from.b != to.b || (from.c == 0) != (to.c == 0) { return false, blot_error::Error.none; }
                pending.push(Item { Pair { from.a, to.a, false }, depth , ..});
                if from.c != 0 { pending.push(Item { Pair { from.c, to.c, false }, depth , ..}); }
            },
            scoped => {
                if from.b != to.b { return false, blot_error::Error.none; }
                if from.b == 0 { pending.push(Item { Pair { from.c, to.c, false }, depth , ..}); }
                else if from.c != to.c { return false, blot_error::Error.none; }
                pending.push(Item { Pair { from.a, to.a, false }, depth , ..});
            },
            function => {
                let before = source.row(from.c); let after = caller.row(to.c);
                if before.labels.len > max_nodes { return false, blot_error::Error.none; }
                if exact_binders && (before.tail != after.tail || before.cursor != after.cursor) { return false, blot_error::Error.none; }
                if before.labels.len != after.labels.len { return false, blot_error::Error.none; }
                match before.tail { parameter => { return false, blot_error::Error.none; }, _ => {} }
                match after.tail { parameter => { return false, blot_error::Error.none; }, _ => {} }
                let left_labels = source.rowLabels(from.c); let right_labels = caller.rowLabels(to.c);
                for left, index in left_labels {
                    let right = right_labels[index]; let old = source.operation(left); let current = caller.operation(right);
                    if old.identity != current.identity { return false, blot_error::Error.none; }
                    if old.instance.unit == 0 && old.instance.decl != 0 && current.instance.unit == 0 && current.instance.decl != 0 {
                        pending.push(Item { Pair { old.instance.decl, current.instance.decl, false }, depth , ..});
                    } else if old.instance != current.instance { return false, blot_error::Error.none; }
                    let arguments = source.operationArguments(left); let actuals = caller.operationArguments(right);
                    if arguments.len != actuals.len || !room(max_nodes, pending.len, arguments.len) { return false, blot_error::Error.none; }
                    for argument, i in arguments { pending.push(Item { Pair { argument, actuals[i], false }, depth , ..}); }
                }
                // Only the covariant ambient return spine may keep an open
                // caller view of a pure source row. Callback inputs stay exact.
                if before.tail == blot_check_effects::Tail.closed && (before.labels.len != 0 || !item.pair.ambient) && after.tail != blot_check_effects::Tail.closed {
                    return false, blot_error::Error.none;
                }
                match before.tail {
                    variable variable => {
                        var row = MatchedRow { cursor: after.cursor , ..};
                        match after.tail { variable value => { row.variable = blot_support::some(value.value); }, _ => {} }
                        { let optional_source_24 .= ::get(rows,variable.value); if optional_source_24 { let known = optional_source_24; if known != row { return false, blot_error::Error.none; }  }
                        else { ::insert(rows,variable.value, row); } }
                    },
                    _ => {},
                }
                pending.push(Item { Pair { from.a, to.a, false }, depth , ..});
                pending.push(Item { Pair { from.b, to.b, item.pair.ambient }, depth , ..});
            },
            array, list, cursor => { pending.push(Item { Pair { from.a, to.a, false }, depth , ..}); },
            product, nominal, instance_selection => {
                let nominal = from.tag == blot_check_types::Tag.nominal || from.tag == blot_check_types::Tag.instance_selection;
                if nominal && (from.a != to.a || from.b != to.b) { return false, blot_error::Error.none; }
                let left=selectedTypeChildren(source,from);let right=selectedTypeChildren(caller,to);
                if left.len != right.len || !room(max_nodes, pending.len, left.len) { return false, blot_error::Error.none; }
                for child, index in left { pending.push(Item { Pair { child, right[index], false }, depth , ..}); }
            },
            record => {
                if from.b != to.b || !room(max_nodes, pending.len, from.b) { return false, blot_error::Error.none; }
                for index in from.b {
                    let left = source.recordField(from, index); let right = caller.recordField(to, index);
                    if left.name != right.name { return false, blot_error::Error.none; }
                    pending.push(Item { Pair { left.ty, right.ty, false }, depth , ..});
                }
            },
            instance_version => { if from.a != to.a || from.b != to.b || from.c != to.c { return false, blot_error::Error.none; } },
            unit, boolean, unsigned32, floating32, never => {},
            _ => { return false, blot_error::Error.none; },
        }
    }
    return true, blot_error::Error.none;
}

struct WordMap { count: i64 = 0, slots: dictionary_slot<u32,u32>[:] = default<dictionary_slot<u32,u32>[:]>() }
reusable[] var copy_map_slots:dictionary_slot<u32,u32>[>..]=[];
fn get(self_:const WordMap&,key:u32)->u32? {return blot_support_pooled_map::get(self_,key);}
fn insert(self_:WordMap&,key:u32,value:u32) {blot_support_pooled_map::insert(self_,key,value,copy_map_slots);}
fn restore(self_:WordMap&,slots:const dictionary_slot<u32,u32>[:],count:i64) {
 blot_support_pooled_map::deinit(self_,copy_map_slots);
 if slots.len!=0 {self_.slots=copy_map_slots.alloc_slice(slots.len);for slot,index in slots {self_.slots[index]=slot;}}
 self_.count=count;
}
fn clear(self_:WordMap&) {blot_support_pooled_map::clear(self_);}
struct CopyMaps {live:bool=false,generation:u64=0,types:WordMap=WordMap {..},variables:WordMap=WordMap {..},rows:WordMap=WordMap {..},row_variables:WordMap=WordMap {..},labels:WordMap=WordMap {..}}
reusable var map_owners:CopyMaps[>..]=[];
var inactive_maps:CopyMaps=CopyMaps {..};
struct Copier {
 source:Source=blot_check_frozen_types::Source.inactive,destination:Store=Store {..},max_depth:i64=0,max_nodes:i64=0,frozen:bool=false,remaining:i64?=null,projection_observed:i64?=null,
 types:WordMap& =inactive_maps.types,variables:WordMap& =inactive_maps.variables,rows:WordMap& =inactive_maps.rows,row_variables:WordMap& =inactive_maps.row_variables,labels:WordMap& =inactive_maps.labels,
 lease:u32=0,generation:u64=0,
}
type Copy=Copier;
type NormalizedCopy=Copier;
type FrozenCopy=Copier;
fn valid(self_:const Copier&)->bool {return self_.lease!=0&&self_.lease-1<map_owners.len&&map_owners[self_.lease-1].live&&map_owners[self_.lease-1].generation==self_.generation;}
fn initPooled(source:Source,destination:Store,max_depth:i64,max_nodes:i64,frozen:bool,remaining:i64?=null,observed:i64?=null)->Copier,Error {
 if map_owners.len>=0xffffffff {return Copier {..},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=map_owners.alloc_index(CopyMaps {live:true,generation:generation, ..});let maps:CopyMaps& =map_owners[at];
 return Copier {source,destination,max_depth,max_nodes,frozen,remaining,observed,maps.types,maps.variables,maps.rows,maps.row_variables,maps.labels,(at+1) as u32,generation, ..},blot_error::Error.none;
}
fn deinit(self_:Copier&) {
 if self_.lease==0 {return;}assert(valid(self_));blot_support_pooled_map::deinit(self_.types,copy_map_slots);blot_support_pooled_map::deinit(self_.variables,copy_map_slots);blot_support_pooled_map::deinit(self_.rows,copy_map_slots);blot_support_pooled_map::deinit(self_.row_variables,copy_map_slots);blot_support_pooled_map::deinit(self_.labels,copy_map_slots);let at=self_.lease-1;map_owners[at].live=false;self_=Copier {..};map_owners.free(at);
}
struct Words {storage:u32[:]=default<u32[:]>(),items:u32[:]=default<u32[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var word_scratch:u32[>..]=[];
fn push(self_:Words&,value:u32) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,word_scratch);self_.len=self_.items.len;}
fn append(self_:Words&,values:const u32[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,word_scratch);self_.len=self_.items.len;}
fn deinit(self_:Words&) {blot_support_pooled_buffer::deinit(self_,word_scratch);self_.len=0;self_.failure=blot_error::Error.none;}
struct Goals {storage:blot_check_types::Obligation[:]=default<blot_check_types::Obligation[:]>(),items:blot_check_types::Obligation[:]=default<blot_check_types::Obligation[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var goal_scratch:blot_check_types::Obligation[>..]=[];
fn push(self_:Goals&,value:blot_check_types::Obligation) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,goal_scratch);self_.len=self_.items.len;}
fn deinit(self_:Goals&) {blot_support_pooled_buffer::deinit(self_,goal_scratch);self_.len=0;self_.failure=blot_error::Error.none;}
struct Fields {storage:blot_check_types::Field[:]=default<blot_check_types::Field[:]>(),items:blot_check_types::Field[:]=default<blot_check_types::Field[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var field_scratch:blot_check_types::Field[>..]=[];
fn push(self_:Fields&,value:blot_check_types::Field) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,field_scratch);self_.len=self_.items.len;}
fn deinit(self_:Fields&) {blot_support_pooled_buffer::deinit(self_,field_scratch);self_.len=0;self_.failure=blot_error::Error.none;}
fn charge(self_: Copier&) -> Error {
    { let optional_source_23 .= self_.remaining; if optional_source_23 { let remaining .= optional_source_23;
        { let optional_source_22 .= self_.projection_observed; if optional_source_22 { let observed .= optional_source_22;
            let spent = self_.destination.projection_steps - observed;
            if spent > remaining { return blot_error::Error.type_limit; }
            remaining -= spent; observed = self_.destination.projection_steps;
         } }
        if remaining == 0 { return blot_error::Error.type_limit; } remaining--;
        if self_.projection_observed != null { self_.destination.projection_limit = self_.destination.projection_steps + remaining; }
     } }
    return blot_error::Error.none;
}
recursive fn ty(self_: Copier&, original: Id, depth: i64) -> Id, Error {
    assert(valid(self_));
    if self_.frozen {
        match self_.source {
            store store => { assert(store.value.versions.len == 0 && store.value.effects.versions.len == 0); },
            _ => {},
        }
    }
    if original <= 5 { return original, blot_error::Error.none; }
    if depth >= self_.max_depth || self_.types.count >= self_.max_nodes { return 0, blot_error::Error.type_limit; }
    { let optional_source_21 .= self_.types.get(original); if optional_source_21 { let known = optional_source_21; return known, blot_error::Error.none;  } }
    let charged = self_.charge(); if charged != blot_error::Error.none { return 0, charged; }
    let root = self_.source.head(original, 0);
    if root != original {
        let result, error = self_.ty(root, depth + 1); if error != blot_error::Error.none { return 0, error; }
        self_.types.insert(original, result); return result, blot_error::Error.none;
    }
    let node = self_.source.node(root);
    var result: Id = 0; var failure = blot_error::Error.none;
    match node.tag {
        bound, rigid, erased_proof => { return 0, blot_error::Error.type_limit; },
        forall,existential=>{let value,error=self_.copyQuantified(node,root,depth);result=value;failure=error;},
        instance_version => { let value, error = self_.destination.instanceVersion(blot_check_types::NominalIdentity { node.a, node.b , ..}, node.c); result = value; failure = error; },
        variable => {
            { let optional_source_20 .= self_.variables.get(node.a); if optional_source_20 { let known = optional_source_20; result = known;  }
            else { let value, error = self_.destination.fresh(); if error != blot_error::Error.none { return 0, error; } self_.variables.insert(node.a, value); result = value; } }
        },
        usage => {
            let payload, error = self_.ty(node.a, depth + 1); if error != blot_error::Error.none { return 0, error; }
            var region: Id = 0;
            if node.c != 0 { let value, error = self_.ty(node.c, depth + 1); if error != blot_error::Error.none { return 0, error; } region = value; }
            let value, error = self_.destination.usage(payload, node.b as blot_check_types::UsageKind, region); result = value; failure = error;
        },
        scoped => {
            let descriptor, error = self_.ty(node.a, depth + 1); if error != blot_error::Error.none { return 0, error; }
            var identity = blot_check_types::NominalIdentity { node.b, node.c , ..};
            if node.b == 0 { let value, error = self_.ty(node.c, depth + 1); if error != blot_error::Error.none { return 0, error; } identity.decl = value; }
            let value, error = self_.destination.scoped(descriptor, identity); result = value; failure = error;
        },
        function => {
            let parameter, e1 = self_.ty(node.a, depth + 1); if e1 != blot_error::Error.none { return 0, e1; }
            let output, e2 = self_.ty(node.b, depth + 1); if e2 != blot_error::Error.none { return 0, e2; }
            let row, e3 = self_.row(node.c, depth + 1); if e3 != blot_error::Error.none { return 0, e3; }
            let value, error = self_.destination.functionWithEffects(parameter, output, row); result = value; failure = error;
        },
        array, list, cursor => {
            let element, error = self_.ty(node.a, depth + 1); if error != blot_error::Error.none { return 0, error; }
            let value, error = self_.destination.sequence(node.tag, element); result = value; failure = error;
        },
        provider => {
            let operation, e1 = self_.ty(node.a, depth + 1); if e1 != blot_error::Error.none { return 0, e1; }
            let effects, e2 = self_.row(node.c, depth + 1); if e2 != blot_error::Error.none { return 0, e2; }
            let value, error = self_.destination.provider(operation, effects); result = value; failure = error;
        },
        resolver => {
            let target, error = self_.ty(node.a, depth + 1); if error != blot_error::Error.none { return 0, error; }
            let value, error = self_.destination.resolver(target); result = value; failure = error;
        },
        state_provider => {
            let read, e1 = self_.ty(node.a, depth + 1); if e1 != blot_error::Error.none { return 0, e1; }
            let write, e2 = self_.ty(node.b, depth + 1); if e2 != blot_error::Error.none { return 0, e2; }
            let state, e3 = self_.ty(node.c, depth + 1); if e3 != blot_error::Error.none { return 0, e3; }
            let value, error = self_.destination.stateProvider(read, write, state); result = value; failure = error;
        },
        type_constructor => { let value, error = self_.destination.typeConstructor(blot_check_types::NominalIdentity { node.a, node.b , ..}); result = value; failure = error; },
        record=>{let value,error=self_.copyRecord(node,depth);result=value;failure=error;},
        product,nominal,projection,instance_selection=>{let value,error=self_.copyChildren(node,depth);result=value;failure=error;},
        absent, unit, boolean, unsigned32, floating32, never => { assert(false); },
    }
    if failure != blot_error::Error.none { return 0, failure; } self_.types.insert(original, result); return result, blot_error::Error.none;
}
fn rowVariable(self_: Copier&, variable: u32) -> Id, Error {
    { let optional_source_19 .= self_.row_variables.get(variable); if optional_source_19 { let known = optional_source_19; return known, blot_error::Error.none;  } }
    if self_.row_variables.count >= self_.max_nodes { return 0, blot_error::Error.type_limit; }
    let charged = self_.charge(); if charged != blot_error::Error.none { return 0, charged; }
    let fresh, error = self_.destination.freshEffects(); if error != blot_error::Error.none { return 0, error; }
    self_.row_variables.insert(variable, fresh); return fresh, blot_error::Error.none;
}
recursive fn row(self_: Copier&, original: Id, depth: i64) -> Id, Error {
    assert(valid(self_));
    if original == 0 { return 0, blot_error::Error.none; }
    if depth >= self_.max_depth || self_.rows.count >= self_.max_nodes { return 0, blot_error::Error.type_limit; }
    { let optional_source_18 .= self_.rows.get(original); if optional_source_18 { let known = optional_source_18; return known, blot_error::Error.none;  } }
    let charged = self_.charge(); if charged != blot_error::Error.none { return 0, charged; }
    var copied=Words {..};
    recursive fn cleanup_continuation_6() -> Id, Error {

let source = self_.source.row(original);
    for operation in self_.source.rowLabels(source.labels) {
        let value, error = self_.label(operation, depth + 1); if error != blot_error::Error.none { return 0, error; } copied.push(value);if copied.failure!=blot_error::Error.none {return 0,copied.failure;}
    }
    if copied.failure!=blot_error::Error.none {return 0,copied.failure;}
    var result: Id = 0; var failure = blot_error::Error.none;
    match source.tail {
        closed => { let value, error = self_.destination.effects.row(copied.items, blot_check_effects::Tail.closed); result = value; failure = blot_check_types::effectError(error); },
        variable variable => {
            let replacement, error = self_.rowVariable(variable.value); if error != blot_error::Error.none { return 0, error; }
            if copied.len == 0 { result = replacement; }
            else {
                let resolved, error = self_.destination.resolveEffects(replacement, 0); if error != blot_error::Error.none { return 0, error; }
                let row = self_.destination.row(resolved); copied.append(self_.destination.rowLabels(resolved));
                if copied.failure!=blot_error::Error.none {return 0,copied.failure;}let value, error = self_.destination.effects.rowAt(copied.items, row.tail, row.cursor); result = value; failure = blot_check_types::effectError(error);
            }
        },
        formal formal => {
            let ty, error = self_.ty(formal.value, depth + 1); if error != blot_error::Error.none { return 0, error; }
            let value, error = self_.destination.effects.row(copied.items, blot_check_effects::Tail.formal { ty , ..}); result = value; failure = blot_check_types::effectError(error);
        },
        parameter => { return 0, blot_error::Error.type_limit; },
    }
    if failure != blot_error::Error.none { return 0, failure; } self_.rows.insert(original, result); return result, blot_error::Error.none;

    }
    let cleanup_result_6_0,cleanup_result_6_1 = cleanup_continuation_6();
    copied.deinit();
    return cleanup_result_6_0,cleanup_result_6_1;
}
recursive fn label(self_: Copier&, original: Id, depth: i64) -> Id, Error {
    assert(valid(self_));
    if depth >= self_.max_depth || self_.labels.count >= self_.max_nodes { return 0, blot_error::Error.type_limit; }
    { let optional_source_17 .= self_.labels.get(original); if optional_source_17 { let known = optional_source_17; return known, blot_error::Error.none;  } }
    let charged = self_.charge(); if charged != blot_error::Error.none { return 0, charged; }
    let operation = self_.source.operation(original); var arguments=Words {..};
    recursive fn cleanup_continuation_5() -> Id, Error {

    for old in self_.source.list(operation.arguments) {
        let value, error = self_.ty(old, depth + 1); if error != blot_error::Error.none { return 0, error; } arguments.push(value);if arguments.failure!=blot_error::Error.none {return 0,arguments.failure;}
    }
    if arguments.failure!=blot_error::Error.none {return 0,arguments.failure;}
    var instance = operation.instance;
    if instance.unit == 0 && instance.decl != 0 {
        let value, error = self_.ty(instance.decl, depth + 1); if error != blot_error::Error.none { return 0, error; } instance.decl = value;
    }
    let result, error = self_.destination.internScopedOperation(operation.identity, instance, arguments.items);
    if error != blot_error::Error.none { return 0, error; } self_.labels.insert(original, result); return result, blot_error::Error.none;

    }
    let cleanup_result_5_0,cleanup_result_5_1 = cleanup_continuation_5();
    arguments.deinit();
    return cleanup_result_5_0,cleanup_result_5_1;
}

recursive fn copyQuantified(self_:Copier&,node:blot_check_types::Node,root:u32,depth:i64)->Id,Error {

            var binders=Words {..};
    recursive fn cleanup_continuation_4() -> Id,Error {

var goals=Goals {..};
    recursive fn cleanup_continuation_3() -> Id,Error {

            let old = self_.source.list(blot_check_types::List { node.b, node.c , ..});
            for binder_source in old {
                let leaf = self_.source.node(binder_source); if leaf.tag != blot_check_types::Tag.bound { return 0, blot_error::Error.type_limit; }
                let binder, error = self_.destination.boundType(leaf.a, leaf.b); if error != blot_error::Error.none { return 0, error; }
                binders.push(binder);if binders.failure!=blot_error::Error.none {return 0,binders.failure;} self_.types.insert(binder_source, binder);
            }
            let body, error = self_.ty(node.a, depth + 1); if error != blot_error::Error.none { return 0, error; }
            
            if binders.failure!=blot_error::Error.none {return 0,binders.failure;}
for old_goal in self_.source.quantifierGoals(root) {
                var goal = old_goal;
                let ty, ty_error = self_.ty(goal.ty, depth + 1); if ty_error != blot_error::Error.none { return 0, ty_error; } goal.ty = ty;
                let other, other_error = self_.ty(goal.other, depth + 1); if other_error != blot_error::Error.none { return 0, other_error; } goal.other = other;
                let selected, result_error = self_.ty(goal.result, depth + 1); if result_error != blot_error::Error.none { return 0, result_error; } goal.result = selected;
                let signature, sig_error = self_.ty(goal.signature, depth + 1); if sig_error != blot_error::Error.none { return 0, sig_error; } goal.signature = signature;
                goal.source = 0; goals.push(goal);if goals.failure!=blot_error::Error.none {return 0,goals.failure;}
            }
            if goals.failure!=blot_error::Error.none {return 0,goals.failure;}return self_.destination.quantifiedWithGoals(node.tag,body,binders.items,goals.items);
        

    }
    let cleanup_result_3_0,cleanup_result_3_1 = cleanup_continuation_3();
    goals.deinit();
    return cleanup_result_3_0,cleanup_result_3_1;

    }
    let cleanup_result_4_0,cleanup_result_4_1 = cleanup_continuation_4();
    binders.deinit();
    return cleanup_result_4_0,cleanup_result_4_1;
}

recursive fn copyRecord(self_:Copier&,node:blot_check_types::Node,depth:i64)->Id,Error {

            var fields=Fields {..};
    recursive fn cleanup_continuation_2() -> Id,Error {

            for index in node.b {
                let old = self_.source.recordField(node, index); let ty, error = self_.ty(old.ty, depth + 1); if error != blot_error::Error.none { return 0, error; }
                fields.push(blot_check_types::Field { old.name, ty , ..});if fields.failure!=blot_error::Error.none {return 0,fields.failure;}
            }
            if fields.failure!=blot_error::Error.none {return 0,fields.failure;}return self_.destination.record(fields.items);
        

    }
    let cleanup_result_2_0,cleanup_result_2_1 = cleanup_continuation_2();
    fields.deinit();
    return cleanup_result_2_0,cleanup_result_2_1;
}

recursive fn copyChildren(self_:Copier&,node:blot_check_types::Node,depth:i64)->Id,Error {

            let children=selectedTypeChildren(self_.source,node);
            var copied=Words {..};
    recursive fn cleanup_continuation_1() -> Id,Error {

            for child in children { let value, error = self_.ty(child, depth + 1); if error != blot_error::Error.none { return 0, error; } copied.push(value);if copied.failure!=blot_error::Error.none {return 0,copied.failure;} }
            if copied.failure!=blot_error::Error.none {return 0,copied.failure;}let identity = blot_check_types::NominalIdentity { node.a, node.b , ..};
            if node.tag == blot_check_types::Tag.instance_selection { return self_.destination.instanceSelection(identity,copied.items); }
            else if node.tag == blot_check_types::Tag.projection { return self_.destination.projection(identity,self_.source.projectionMember(node),copied.items); }
            else if node.tag == blot_check_types::Tag.nominal { return self_.destination.nominal(identity,copied.items); }
            else { return self_.destination.product(copied.items); }
        

    }
    let cleanup_result_1_0,cleanup_result_1_1 = cleanup_continuation_1();
    copied.deinit();
    return cleanup_result_1_0,cleanup_result_1_1;
}
recursive fn withCopy<C,F>(source:Source,destination:Store&,max_depth:i64,max_nodes:i64,remaining:i64&,observed:i64&,context:C&)->Error {
 var copier,error=initPooled(source,destination,max_depth,max_nodes,false,remaining,observed);if error!=blot_error::Error.none {return error;}let result=F(context,copier);copier.deinit();return result;
}
fn withFrozenCopy<C,F>(source:Source,destination:Store&,max_depth:i64,max_nodes:i64,remaining:i64&,observed:i64&,context:C&)->Error {
 var copier,error=initPooled(source,destination,max_depth,max_nodes,true,remaining,observed);if error!=blot_error::Error.none {return error;}let result=F(context,copier);copier.deinit();return result;
}

fn selectedTypeChildren<S>(source:const S&,node:blot_check_types::Node)->const u32[:] {if node.tag==blot_check_types::Tag.product {return source.list(blot_check_types::List{node.a,node.b});}return source.nominalArguments(node);}
