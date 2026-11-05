// Immutable principal relocation never imports caller inference authority.
namespace blot_check_check_scheme_import;
import support.error;
import support.option;
import .types;
type Error = blot_error::Error;
type Id = blot_check_types::Id;
type Identity = blot_check_types::NominalIdentity;
type List = blot_check_types::List;
type Tag = blot_check_types::Tag;
struct Tables { private_scopes: WordMap&, mapping: WordMap&, row_variables: WordMap&, rows: WordMap&, labels: WordMap& }
struct Copier {
    private_namespace: u32 = 0, private_qualifications: const blot_parse_ast::Span[:] = [], private_unit: u32 = 0,
    private_nodes: const blot_parse_ast::Id[:] = [], private_bindings: const u32[:] = [], private_tree: const blot_parse_ast::Tree? = null,
    private_scopes: WordMap&, operation_mapping: const IdentityMap? = null,
    field_mapping: const u32[:] = [], has_field_mapping: bool = false, nominal_mapping: const IdentityMap? = null,
    fresh_variables: bool = false, fresh_rows: bool = false, source: blot_check_frozen_types::Source, destination: blot_check_types::Store,
    associated: bool = false, mapping: WordMap&, row_variables: WordMap&, rows: WordMap&, labels: WordMap&,
}
fn init(source: blot_check_frozen_types::Source, destination: blot_check_types::Store&, tables: Tables) -> Copier { return Copier { private_scopes: tables.private_scopes, source, destination, mapping: tables.mapping, row_variables: tables.row_variables, rows: tables.rows, labels: tables.labels }; }
fn deinit(self: Copier&) { self.private_scopes.deinit(); self.mapping.deinit(); self.row_variables.deinit(); self.rows.deinit(); self.labels.deinit(); }
fn copyPhysical(self: Copier&, identity: Identity) -> Identity, Error {
    if self.private_namespace == 0 || identity.unit != self.private_namespace || identity.decl == 0 || identity.decl > self.private_nodes.len { return Identity {}, Error.type_limit; }
    return Identity { self.private_unit, self.private_nodes[identity.decl - 1] }, Error.none;
}
fn copyVersion(self: Copier&, node: blot_check_types::Node) -> Id, Error {
    if self.private_namespace == 0 { return self.destination.instanceVersion(Identity { node.a, node.b }, node.c); }
    if (node.a & 0x7fffffff) != self.private_namespace || node.b == 0 { return 0, Error.type_limit; } var declaration: u32 = 0;
    if node.a & 0x80000000 != 0 { if node.b > self.private_bindings.len { return 0, Error.type_limit; } declaration = self.private_bindings[node.b - 1]; }
    else { if node.b > self.private_nodes.len { return 0, Error.type_limit; } { let optional_binding_60 .= self.private_tree; if optional_binding_60 { let tree .= optional_binding_60; let end = tree.span(self.private_nodes[node.b - 1]).end; if end == 0xffffffff { return 0, Error.type_limit; } declaration = end + 1;  } else { return 0, Error.type_limit; } } }
    return self.destination.instanceVersion(Identity { self.private_unit, declaration }, node.c);
}
fn copyScope(self: Copier&, source: u32) -> u32, Error {
    if self.private_namespace == 0 || source == 0 { return 0, Error.type_limit; } { let optional_binding_59 .= self.private_scopes.get(source); if optional_binding_59 { let known .= optional_binding_59; return known, Error.none;  } }
    let fresh, error = self.destination.rigidScope(); if error != Error.none { return 0, error; } self.private_scopes.insert(source, fresh); return fresh, Error.none;
}
fn rowVariable(self: Copier&, source: u32) -> blot_check_effects::Id, Error {
    { let optional_binding_58 .= self.row_variables.get(source); if optional_binding_58 { let known .= optional_binding_58; return known, Error.none;  } } let fresh, error = self.destination.freshEffects(); if error != Error.none { return 0, error; } self.row_variables.insert(source, fresh); return fresh, Error.none;
}
fn variableOf(self: Copier&, row: blot_check_effects::Id) -> u32, Error { match self.destination.effects.node(row).tail { blot_check_effects::Tail.variable match_payload_26 => { let value = match_payload_26.value;  return value, Error.none; }, _ => { return 0, Error.type_limit; }, } }
fn relocatedRows(self: Copier&, source: const u32[:]) -> List, Error {
    var rows: u32[>..] = []; for old in source { let formal = blot_check_types::rowKeyFormal(old);
        if formal.present { let copied, error = copy(self, formal.value, 0); if error != Error.none { return List {}, error; } let key, error = blot_check_types::formalRowKey(copied); if error != Error.none { return List {}, error; } rows += key; continue; }
        let fresh, error = rowVariable(self, old); if error != Error.none { return List {}, error; } let variable, error = variableOf(self, fresh); if error != Error.none { return List {}, error; } rows += variable;
    } return self.destination.saveList(rows);
}
fn quantifiedRows(self: Copier&, values: List) -> List, Error {
    var variables: u32[>..] = []; for index in self.source.list(values) { let fresh, error = self.destination.freshEffects(); if error != Error.none { return List {}, error; } self.row_variables.insert(index, fresh); let variable, error = variableOf(self, fresh); if error != Error.none { return List {}, error; } variables += variable; } return self.destination.saveList(variables);
}
fn copyGenerative(self: Copier&, source: List) -> List, Error { if source.len > 32 || source.len % 2 != 0 { return List {}, Error.type_limit; } var roots: Id[>..] = []; for root in self.source.list(source) { let id, error = copy(self, root, 0); if error != Error.none { return List {}, error; } roots += id; } return self.destination.saveList(roots); }
recursive fn copyLabel(self: Copier&, label: blot_check_effects::Label, depth: i64) -> blot_check_effects::Label, Error {
    if depth >= 1024 || label == 0 || label >= self.source.operationCount() { return 0, Error.type_limit; } { let optional_binding_57 .= self.labels.get(label); if optional_binding_57 { let known .= optional_binding_57; return known, Error.none;  } }
    if self.associated { let error = self.destination.chargeProjection(); if error != Error.none { return 0, error; } }
    let operation = self.source.operation(label); var args: Id[>..] = []; for arg in self.source.list(operation.arguments) { let copied, error = copy(self, arg, depth + 1); if error != Error.none { return 0, error; } args += copied; }
    var instance = operation.instance; if instance.unit != 0 && self.private_namespace != 0 { let copied, error = copyPhysical(self, instance); if error != Error.none { return 0, error; } instance = copied; }
    else if instance.unit == 0 && instance.decl != 0 { let copied, error = copy(self, instance.decl, depth + 1); if error != Error.none { return 0, error; } instance.decl = copied; }
    var identity = operation.identity; { let optional_binding_56 .= self.operation_mapping; if optional_binding_56 { let mapping .= optional_binding_56; if label != blot_check_types::foreign_operation { { let optional_binding_55 .= mapping.get(identity); if optional_binding_55 { let copied .= optional_binding_55; identity = copied;  } else { return 0, Error.type_limit; } } }  } }
    let result, error = self.destination.internScopedOperation(identity, instance, args); if error != Error.none { return 0, error; } self.labels.insert(label, result); return result, Error.none;
}
recursive fn copyRow(self: Copier&, source_row: blot_check_effects::Id, depth: i64) -> blot_check_effects::Id, Error {
    if depth >= 1024 { return 0, Error.type_limit; } if source_row == 0 { return 0, Error.none; } { let optional_binding_54 .= self.rows.get(source_row); if optional_binding_54 { let known .= optional_binding_54; return known, Error.none;  } }
    if self.associated { let error = self.destination.chargeProjection(); if error != Error.none { return 0, error; } }
    let row = self.source.row(source_row); var labels: blot_check_effects::Label[>..] = [];
    for label in self.source.rowLabels(row.labels) { let copied, error = copyLabel(self, label, depth + 1); if error != Error.none { return 0, error; } labels += copied; }
    var tail = blot_check_effects::Tail.closed;
    match row.tail {
        blot_check_effects::Tail.closed => {},
        blot_check_effects::Tail.parameter match_payload_23 => { let value = match_payload_23.value;  tail = blot_check_effects::Tail.parameter { value }; },
        blot_check_effects::Tail.formal match_payload_24 => { let value = match_payload_24.value;  let copied, error = copy(self, value, depth + 1); if error != Error.none { return 0, error; } tail = blot_check_effects::Tail.formal { copied }; },
        blot_check_effects::Tail.variable match_payload_25 => { let value = match_payload_25.value; 
            var mapped = blot_support::none<u32>(); { let optional_binding_53 .= self.row_variables.get(value); if optional_binding_53 { let known .= optional_binding_53; mapped = blot_support::some(known);  } }
            if !mapped.present && self.fresh_rows { let fresh, error = self.destination.freshEffects(); if error != Error.none { return 0, error; } self.row_variables.insert(value, fresh); mapped = blot_support::some(fresh); }
            if !mapped.present { return 0, Error.type_limit; } let replacement = self.destination.effects.node(mapped.value);
            for label in self.destination.effects.list(replacement.labels) {
                if self.associated { let error = self.destination.chargeProjection(); if error != Error.none { return 0, error; } }
                var present = false; for existing in labels { if self.associated { let error = self.destination.chargeProjection(); if error != Error.none { return 0, error; } } if existing == label { present = true; break; } } if !present { labels += label; }
            } tail = replacement.tail;
        },
    }
    let result, error = self.destination.effects.row(labels, tail); if error != Error.none { return 0, blot_check_types::effectError(error); } self.rows.insert(source_row, result); return result, Error.none;
}
fn quantifier(self: Copier&, node: blot_check_types::Node, depth: i64, id: Id) -> Id, Error {
    var binders: Id[>..] = []; for original in self.source.list(List { node.b, node.c }) { let leaf = self.source.node(original); if leaf.tag != Tag.bound { return 0, Error.type_limit; }
        var binder: Id = 0; { let optional_binding_52 .= self.mapping.get(original); if optional_binding_52 { let known .= optional_binding_52; binder = known;  } else { let fresh, error = self.destination.boundType(leaf.a, leaf.b); if error != Error.none { return 0, error; } binder = fresh; } } self.mapping.insert(original, binder); binders += binder;
    }
    let body, error = copy(self, node.a, depth + 1); if error != Error.none { return 0, error; } var goals: blot_check_types::Obligation[>..] = []; goals += self.source.quantifierGoals(id);
    for &goal in goals { let ty, error = copy(self, goal.ty, depth + 1); if error != Error.none { return 0, error; } goal.ty = ty; let other, error = copy(self, goal.other, depth + 1); if error != Error.none { return 0, error; } goal.other = other; let result, error = copy(self, goal.result, depth + 1); if error != Error.none { return 0, error; } goal.result = result; let signature, error = copy(self, goal.signature, depth + 1); if error != Error.none { return 0, error; } goal.signature = signature; goal.source = 0;
        if self.private_namespace != 0 {
            if goal.qualification_span.present { let origin = goal.qualification_span.value; if goal.qualification_unit != 0 || origin.start == 0 || origin.start > self.private_qualifications.len || origin.end != 0 { return 0, Error.type_limit; } goal.qualification_span = blot_support::some(self.private_qualifications[origin.start - 1]); goal.qualification_unit = self.private_unit; }
            if goal.name != 0 { if !self.has_field_mapping { return 0, Error.type_limit; } goal.name = self.field_mapping[goal.name - 1]; }
            if goal.kind == blot_check_types::ObligationKind.contract { { let optional_binding_51 .= self.nominal_mapping; if optional_binding_51 { let mapping .= optional_binding_51; { let optional_binding_50 .= mapping.get(goal.identity); if optional_binding_50 { let identity .= optional_binding_50; goal.identity = identity;  } else { return 0, Error.type_limit; } }  } else { return 0, Error.type_limit; } } }
            if goal.kind == blot_check_types::ObligationKind.effect_operation { { let optional_binding_49 .= self.operation_mapping; if optional_binding_49 { let mapping .= optional_binding_49; { let optional_binding_48 .= mapping.get(goal.identity); if optional_binding_48 { let identity .= optional_binding_48; goal.identity = identity;  } else { return 0, Error.type_limit; } }  } else { return 0, Error.type_limit; } } }
        }
    } return self.destination.quantifiedWithGoals(node.tag, body, binders, goals);
}
fn nominal(self: Copier&, node: blot_check_types::Node, depth: i64) -> Id, Error {
    var args: Id[>..] = []; for arg in self.source.nominalArguments(node) { let copied, error = copy(self, arg, depth + 1); if error != Error.none { return 0, error; } args += copied; }
    var identity = Identity { node.a, node.b }; let arity = blot_check_types::compilerNominalArity(identity);
    if !arity.present { { let optional_binding_47 .= self.nominal_mapping; if optional_binding_47 { let mapping .= optional_binding_47; { let optional_binding_46 .= mapping.get(identity); if optional_binding_46 { let relocated .= optional_binding_46; identity = relocated;  }
        else { { let optional_binding_45 .= self.operation_mapping; if optional_binding_45 { let operations .= optional_binding_45; { let optional_binding_44 .= operations.get(identity); if optional_binding_44 { let relocated .= optional_binding_44; identity = relocated;  } else { return 0, Error.type_limit; } }  } else { return 0, Error.type_limit; } } } }
     } } }
    if node.tag == Tag.projection { var name = self.source.projectionMember(node); if self.has_field_mapping { name = self.field_mapping[name]; } return self.destination.projection(identity, name, args); }
    return self.destination.nominal(identity, args);
}
recursive fn copy(self: Copier&, source_id: Id, depth: i64) -> Id, Error {
    self.destination.normalization.import_depth_entries +|= 1; let before = self.destination.nodes.len;
    let result, error = copyDepth(self, source_id, depth); if depth == 0 { self.destination.normalization.import_nodes_added +|= (self.destination.nodes.len - before) as u64; } return result, error;
}
fn copyDepth(self: Copier&, source_id: Id, depth: i64) -> Id, Error {
    if depth >= 1024 { return 0, Error.type_limit; } let id = self.source.head(source_id, 0); { let optional_binding_43 .= self.mapping.get(id); if optional_binding_43 { let known .= optional_binding_43; return known, Error.none;  } }
    if self.associated { let error = self.destination.chargeProjection(); if error != Error.none { return 0, error; } }
    let node = self.source.node(id); var result: Id = 0; var failure = Error.none;
    match node.tag {
        Tag.bound => { if self.private_namespace == 0 { return 0, Error.type_limit; } let value, error = self.destination.boundType(node.a, node.b); result = value; failure = error; },
        Tag.rigid => { let scope, error = copyScope(self, node.a); if error != Error.none { return 0, error; } let value, error = self.destination.rigid(scope, node.b, node.c); result = value; failure = error; },
        Tag.forall, Tag.existential => { let value, error = quantifier(self, node, depth, id); result = value; failure = error; },
        Tag.instance_version => { let value, error = copyVersion(self, node); result = value; failure = error; },
        Tag.instance_selection => { var choices: Id[>..] = []; let original = self.source.nominalArguments(node); if original.len != 2 && original.len != 3 { return 0, Error.type_limit; }
            for choice in original { let value, error = copy(self, choice, depth + 1); if error != Error.none { return 0, error; } choices += value; } var identity = Identity { node.a, node.b };
            if self.private_namespace != 0 { let value, error = copyPhysical(self, identity); if error != Error.none { return 0, error; } identity = value; } let value, error = self.destination.instanceSelection(identity, choices); result = value; failure = error;
        },
        Tag.usage => { let payload, error = copy(self, node.a, depth + 1); if error != Error.none { return 0, error; } var region: Id = 0; if node.c != 0 { let value, error = copy(self, node.c, depth + 1); if error != Error.none { return 0, error; } region = value; } let kind, error = blot_check_types::usageFromCode(node.b); if error != Error.none { return 0, error; } let value, error = self.destination.usage(payload, kind, region); result = value; failure = error; },
        Tag.erased_proof => { let value, error = self.destination.proofKind(); result = value; failure = error; },
        Tag.scoped => { let payload, error = copy(self, node.a, depth + 1); if error != Error.none { return 0, error; } var identity = Identity { node.b, node.c };
            if node.b == 0 { let value, error = copy(self, node.c, depth + 1); if error != Error.none { return 0, error; } identity = Identity { 0, value }; }
            else { let value, error = copyPhysical(self, identity); if error != Error.none { return 0, error; } identity = value; } let value, error = self.destination.scoped(payload, identity); result = value; failure = error;
        },
        Tag.absent, Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32, Tag.never => { result = id; },
        Tag.array, Tag.list, Tag.cursor => { let payload, error = copy(self, node.a, depth + 1); if error != Error.none { return 0, error; } let value, error = self.destination.sequence(node.tag, payload); result = value; failure = error; },
        Tag.provider => { let payload, error = copy(self, node.a, depth + 1); if error != Error.none { return 0, error; } let row, error = copyRow(self, node.c, depth + 1); if error != Error.none { return 0, error; } let value, error = self.destination.provider(payload, row); result = value; failure = error; },
        Tag.state_provider => { let a, error = copy(self, node.a, depth + 1); if error != Error.none { return 0, error; } let b, error = copy(self, node.b, depth + 1); if error != Error.none { return 0, error; } let c, error = copy(self, node.c, depth + 1); if error != Error.none { return 0, error; } let value, error = self.destination.stateProvider(a, b, c); result = value; failure = error; },
        Tag.resolver => { let a, error = copy(self, node.a, depth + 1); if error != Error.none { return 0, error; } let value, error = self.destination.resolver(a); result = value; failure = error; },
        Tag.type_constructor => { var identity = Identity { node.a, node.b }; { let optional_binding_42 .= self.nominal_mapping; if optional_binding_42 { let mapping .= optional_binding_42; { let optional_binding_41 .= mapping.get(identity); if optional_binding_41 { let value .= optional_binding_41; identity = value;  } else { return 0, Error.type_limit; } }  } } let value, error = self.destination.typeConstructor(identity); result = value; failure = error; },
        Tag.record => { var fields: blot_check_types::Field[>..] = []; for i in 0..node.b { let field = self.source.recordField(node, i); var name = field.name; if self.has_field_mapping { name = self.field_mapping[field.name]; } let ty, error = copy(self, field.ty, depth + 1); if error != Error.none { return 0, error; } fields += blot_check_types::Field { name, ty }; } let value, error = self.destination.record(fields); result = value; failure = error; },
        Tag.nominal, Tag.projection => { let value, error = nominal(self, node, depth); result = value; failure = error; },
        Tag.variable => { if !self.fresh_variables { return 0, Error.type_limit; } let value, error = self.destination.fresh(); result = value; failure = error; },
        Tag.function => { let a, error = copy(self, node.a, depth + 1); if error != Error.none { return 0, error; } let b, error = copy(self, node.b, depth + 1); if error != Error.none { return 0, error; } let c, error = copyRow(self, node.c, depth + 1); if error != Error.none { return 0, error; } let value, error = self.destination.functionWithEffects(a, b, c); result = value; failure = error; },
        Tag.product => { var fields: Id[>..] = []; for child in self.source.list(List { node.a, node.b }) { let value, error = copy(self, child, depth + 1); if error != Error.none { return 0, error; } fields += value; } let value, error = self.destination.product(fields); result = value; failure = error; },
    }
    if failure != Error.none { return 0, failure; } self.mapping.insert(id, result); return result, Error.none;
}
fn withCopier<C,F>(source: blot_check_frozen_types::Source, destination: blot_check_types::Store&, context: C&) -> Error {
    var scopes: WordMap = WordMap {}; var mapping: WordMap = WordMap {}; var row_variables: WordMap = WordMap {}; var rows: WordMap = WordMap {}; var labels: WordMap = WordMap {};
    var copier = init(source, destination, Tables { scopes, mapping, row_variables, rows, labels }); let error = F(context, copier); deinit(copier); return error;
}

struct WordMap { count: i64 = 0, failure:Error=Error.none, slots: dictionary_slot<u32,u32>[:] = [] }
fn probe(map: const WordMap&,key: u32) -> i64 {
    if map.count == 0 { return -1; } let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn get(map: const WordMap&,key: u32) -> u32? { let index = probe(map,key); if index < 0 { return null; } return map.slots[index].val; }
fn contains(map: const WordMap&,key: u32) -> bool { return probe(map,key) >= 0; }
fn release(slots: dictionary_slot<u32,u32>[:]) { if slots.len != 0 { pool_WordMap.free_slice(slots); } }
fn grow(map: WordMap&,capacity: i64) {
    let replacement = pool_WordMap.alloc_slice(capacity); for &slot in replacement { slot = dictionary_slot<u32,u32> { default<u32>(),default<u32>(),0 }; }
    for slot in map.slots { if slot.tag != 0 { var index = (slot.key.hash() & ((capacity - 1) as u64)) as i64; while replacement[index].tag != 0 { index = (index + 1) & (capacity - 1); } replacement[index] = slot; } }
    release(map.slots); map.slots = replacement;
}
fn insert(map: WordMap&,key: u32,value: u32) -> bool {
    if map.slots.len == 0 { grow(map,8); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2); }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == 0 { map.slots[index] = dictionary_slot<u32,u32> { key,value,tag }; map.count++; return true; } if present == tag && map.slots[index].key == key { map.slots[index] = dictionary_slot<u32,u32> { map.slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove(map: WordMap&,key: u32) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    map.slots[hole] = dictionary_slot<u32,u32> { default<u32>(),default<u32>(),0 }; map.count--; return true;
}
fn clear(map: WordMap&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit(map: WordMap&) { release(map.slots); map.slots = []; map.count = 0;map.failure=Error.none; }
fn clone(map: const WordMap&) -> WordMap { var copy = WordMap {}; if map.slots.len != 0 { let slots = pool_WordMap.alloc_slice(map.slots.len); for slot,index in map.slots { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<F>(map: WordMap&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }

reusable[] var pool_WordMap:dictionary_slot<u32,u32>[>..];
fn restore(map:WordMap&,slots:const dictionary_slot<u32,u32>[:],count:i64)->Error {map.deinit();if slots.len==0 {if count!=0 {return Error.invalid_artifact;}return Error.none;}let run=pool_WordMap.alloc_slice(slots.len);for slot,index in slots {run[index]=slot;}map.slots=run;map.count=count;return Error.none;}
struct IdentityMap { count: i64 = 0, failure:Error=Error.none, slots: dictionary_slot<Identity,Identity>[:] = [] }
fn probe(map: const IdentityMap&,key: Identity) -> i64 {
    if map.count == 0 { return -1; } let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn get(map: const IdentityMap&,key: Identity) -> Identity? { let index = probe(map,key); if index < 0 { return null; } return map.slots[index].val; }
fn contains(map: const IdentityMap&,key: Identity) -> bool { return probe(map,key) >= 0; }
fn release(slots: dictionary_slot<Identity,Identity>[:]) { if slots.len != 0 { pool_IdentityMap.free_slice(slots); } }
fn grow(map: IdentityMap&,capacity: i64) {
    let replacement = pool_IdentityMap.alloc_slice(capacity); for &slot in replacement { slot = dictionary_slot<Identity,Identity> { default<Identity>(),default<Identity>(),0 }; }
    for slot in map.slots { if slot.tag != 0 { var index = (slot.key.hash() & ((capacity - 1) as u64)) as i64; while replacement[index].tag != 0 { index = (index + 1) & (capacity - 1); } replacement[index] = slot; } }
    release(map.slots); map.slots = replacement;
}
fn insert(map: IdentityMap&,key: Identity,value: Identity) -> bool {
    if map.slots.len == 0 { grow(map,8); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2); }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == 0 { map.slots[index] = dictionary_slot<Identity,Identity> { key,value,tag }; map.count++; return true; } if present == tag && map.slots[index].key == key { map.slots[index] = dictionary_slot<Identity,Identity> { map.slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove(map: IdentityMap&,key: Identity) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    map.slots[hole] = dictionary_slot<Identity,Identity> { default<Identity>(),default<Identity>(),0 }; map.count--; return true;
}
fn clear(map: IdentityMap&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit(map: IdentityMap&) { release(map.slots); map.slots = []; map.count = 0;map.failure=Error.none; }
fn clone(map: const IdentityMap&) -> IdentityMap { var copy = IdentityMap {}; if map.slots.len != 0 { let slots = pool_IdentityMap.alloc_slice(map.slots.len); for slot,index in map.slots { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<F>(map: IdentityMap&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }

reusable[] var pool_IdentityMap:dictionary_slot<Identity,Identity>[>..];
fn restore(map:IdentityMap&,slots:const dictionary_slot<Identity,Identity>[:],count:i64)->Error {map.deinit();if slots.len==0 {if count!=0 {return Error.invalid_artifact;}return Error.none;}let run=pool_IdentityMap.alloc_slice(slots.len);for slot,index in slots {run[index]=slot;}map.slots=run;map.count=count;return Error.none;}
