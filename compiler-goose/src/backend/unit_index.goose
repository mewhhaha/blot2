// Immutable per-unit indexes are built once per attempt, in source node order.
namespace blot_backend_unit_index;
import std;
import dictionary;
import check.core;
import check.types;
import .collection_ops;
import support.error;
import support.option;
type Error = blot_error::Error;
type SetSlot = dictionary_slot<u32,bool>;
struct Set { slots: const SetSlot[:] = [] }
struct Quantified { types: Set,rows: Set }
reusable[] var owned_sets: SetSlot[>..] = [];
fn freezeSet(values: const dictionary<u32,bool>&) -> Set { if values.slots.len == 0 { return Set {}; } let out = owned_sets.alloc_slice(values.slots.len); for slot,index in values.slots { out[index] = slot; } return Set { out }; }
fn contains(set: Set,key: u32) -> bool {
    if set.slots.len == 0 { return false; } let hash = ::hash(key); let tag = (hash as! u32) | 2147483648; let mask = set.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    while true { let slot = set.slots[index]; if slot.tag == tag && slot.key == key { return true; } if slot.tag == 0 { return false; } index = (index + 1) & mask; }
}
fn deinit(set: Set&) { if set.slots.len != 0 { let first: const SetSlot& = set.slots[0]; let at = owned_sets.index_of(first); owned_sets.free_slice(owned_sets[at..at + set.slots.len]); } set.slots = []; }
fn deinit(quantified: Quantified&) { quantified.types.deinit(); quantified.rows.deinit(); }
fn has(quantified: Quantified,variable: u32,row: bool) -> bool { if row { return quantified.rows.contains(variable); } return quantified.types.contains(variable); }
fn addVariables<T>(set: dictionary<u32,bool>&,types: const T&,lists: const blot_check_types::List[:]) { for list in lists { for variable in types.list(list) { set.insert(variable,true); } } }
fn initQuantified(source: const blot_check_core::Module&) -> Quantified,Error {
    var types: dictionary<u32,bool>; var rows: dictionary<u32,bool>;
    for binding in source.bindings { addVariables(types,source.types,[binding.scheme.variables,binding.scheme.generative,binding.public_variables]); addVariables(rows,source.types,[binding.scheme.row_variables,binding.scheme.closed_rows,binding.public_rows]); }
    for body in source.bodies { addVariables(types,source.types,[body.scheme.variables,body.scheme.generative]); addVariables(rows,source.types,[body.scheme.row_variables,body.scheme.closed_rows,body.closed_rows]); }
    for constructor in source.constructors { addVariables(types,source.types,[constructor.scheme.variables,constructor.scheme.generative]); addVariables(rows,source.types,[constructor.scheme.row_variables]); }
    for nominal in source.nominals { addVariables(types,source.types,[nominal.parameters,nominal.variables]); } for operation in source.operation_names { addVariables(types,source.types,[operation.variables,operation.parameters]); }
    for closure in source.closures { addVariables(rows,source.types,[closure.closed_rows]); }
    for contract in source.contracts { addVariables(types,source.types,[contract.parameters,contract.variables]); addVariables(rows,source.types,[contract.row_variables,contract.row_parameters]); }
    for implementation in source.implementations { addVariables(types,source.types,[implementation.variables,implementation.head]); addVariables(rows,source.types,[implementation.row_variables,implementation.row_parameters]); }
    return Quantified { freezeSet(types),freezeSet(rows) },Error.none;
}
struct Table<T> { offsets: u32[:] = [],items: T[:] = [] }
struct Builder<T> { offsets: u32[:],items: T[:] = [],filling: bool = false }
fn add<T>(builder: Builder<T>&,key: u32,value: T) { if !builder.filling { builder.offsets[key + 1]++; return; } builder.items[builder.offsets[key]] = value; builder.offsets[key]++; }
reusable[] var owned_words: u32[>..] = [];
struct Exit { exit: u32,position: u32 }
reusable[] var owned_exits: Exit[>..] = [];
fn build<T,C,F>(keys: i64,context: C,item_pool: T[>..]&) -> Table<T>,Error {
    let offsets = owned_words.alloc_slice(keys + 1); var builder = Builder<T> { offsets }; F(context,builder); for index in 1..offsets.len { offsets[index] += offsets[index - 1]; }
    let items = item_pool.alloc_slice(offsets[keys]); builder.items = items; builder.filling = true; F(context,builder); var index = keys;
    while index > 0 { offsets[index] = offsets[index - 1]; index--; } offsets[0] = 0; return Table<T> { offsets,items },Error.none;
}
fn deinit<T>(table: Table<T>&,item_pool: T[>..]&) {
    if table.offsets.len != 0 { let first: const u32& = table.offsets[0]; let at = owned_words.index_of(first); owned_words.free_slice(owned_words[at..at + table.offsets.len]); }
    if table.items.len != 0 { item_pool.free_slice(table.items); } table.offsets = []; table.items = [];
}
fn deinit(table: Table<u32>&) { deinit(table,owned_words); }
fn deinit(table: Table<Exit>&) { deinit(table,owned_exits); }
fn get<T>(table: const Table<T>&,key: u32) -> const T[:] { if key as i64 + 1 >= table.offsets.len { return []; } return table.items[table.offsets[key]..table.offsets[key + 1]]; }
fn ownReference(source: const blot_check_core::Module&,unit: u32,id: u32) -> blot_support::Option<u32> {
    let reference = source.reference(id); if reference.unit != 0 && reference.unit != unit && reference.unit != source.unit { return blot_support::none<u32>(); } if reference.binding >= source.bindings.len { return blot_support::none<u32>(); } return blot_support::some(reference.binding);
}
struct Scope { source: const blot_check_core::Module&,unit: u32 }
fn visitReferences(scope: Scope,builder: Builder<u32>&) { for node,index in scope.source.nodes { if node.tag != blot_check_core::Tag.reference { continue; } let binding = ownReference(scope.source,scope.unit,index as u32); if binding.present { builder.add(binding.value,index as u32); } } }
fn references(source: const blot_check_core::Module&,unit: u32) -> Table<u32>,Error { build(source.bindings.len,Scope { source,unit },owned_words,visitReferences) }
fn visitDefinitions(scope: Scope,builder: Builder<u32>&) { for node,index in scope.source.nodes { if node.tag == blot_check_core::Tag.bind && node.a < scope.source.bindings.len { builder.add(node.a,index as u32); } } }
fn visitInputs(scope: Scope,builder: Builder<u32>&) {
    let source .= scope.source; for node,index in source.nodes {
        if node.tag != blot_check_core::Tag.bind { continue; } var input = node.b;
        if input != 0 && source.node(input).tag == blot_check_core::Tag.array_op { let operation = source.arrayOperation(input); if operation == blot_backend_collection_ops::Op.cursor_advance { input = source.children(input)[0]; } }
        if input == 0 || source.node(input).tag != blot_check_core::Tag.reference { continue; } let binding = ownReference(source,scope.unit,input); if binding.present { builder.add(binding.value,index as u32); }
    }
}
fn visitExits(scope: Scope,builder: Builder<u32>&) { for node,index in scope.source.nodes { if node.tag == blot_check_core::Tag.break_ && node.a < scope.source.nodes.len { builder.add(node.a,index as u32); } } }
fn visitValues(scope: Scope,builder: Builder<Exit>&) { for node,index in scope.source.nodes { if node.tag != blot_check_core::Tag.break_ { continue; } for value,position in scope.source.breakValues(index as u32) { builder.add(value,Exit { index as u32,position as u32 }); } } }
fn visitCarries(scope: Scope,builder: Builder<u32>&) {
    for carry,index in scope.source.loop_carries { let named: u32[4] = [carry.incoming,carry.iteration,carry.backedge,carry.outgoing]; for held,position in named { if held >= scope.source.bindings.len { continue; } var duplicate = false; for prior in named[..position] { if prior == held { duplicate = true; break; } } if !duplicate { builder.add(held,index as u32); } } }
}
struct Flags { captured: bool = false,merge_branch: bool = false,merge_result: bool = false,carried: bool = false }
struct Parent { node: u32 = 0,position: u32 = 0,count: u8 = 0 }
struct Carry { loop: u32 = 0,position: u32 = 0 }
struct Need { parents: bool = false,flow: bool = false }
struct Uses { references: Table<u32>,flags: Flags[:] = [],parents: u64[:] = [],has_parents: bool = false,definitions: Table<u32>,inputs: Table<u32>,carries: Table<u32>,exits: Table<u32>,values: Table<Exit>,carry_loops: Carry[:] = [],has_flow: bool = false }
reusable[] var owned_flags: Flags[>..] = [];
reusable[] var owned_parents: u64[>..] = [];
reusable[] var owned_carries: Carry[>..] = [];
reusable var owned_uses: Uses[>..] = [];
fn createUses(source: const blot_check_core::Module&,unit: u32) -> Uses&,Error {
    let owner .= owned_uses.alloc_ref(Uses {}); let initialized,error = initBase(source,unit); if error != Error.none { owned_uses.free(owned_uses.index_of(owner)); return owner,error; } owner = initialized; return owner,Error.none;
}
fn release(owner: Uses&) { owned_uses.free(owned_uses.index_of(owner)); }
fn init(source: const blot_check_core::Module&,unit: u32) -> Uses,Error {
    let base,error = initBase(source,unit); if error != Error.none { return base,error; } var result = base; let completed = result.ensure(source,unit,Need { true,true }); if completed != Error.none { result.deinit(); return Uses {},completed; } return result,Error.none;
}
fn initBase(source: const blot_check_core::Module&,unit: u32) -> Uses,Error {
    var result = Uses {}; let grouped,error = references(source,unit); if error != Error.none { return result,error; } result.references = grouped; result.flags = owned_flags.alloc_slice(source.bindings.len);
    for closure in source.closures { for held in source.extra[closure.captures.start..closure.captures.start + closure.captures.len] { if held < result.flags.len { result.flags[held].captured = true; } } }
    for merge in source.merges { for held in [merge.then_binding,merge.else_binding] { if held < result.flags.len { result.flags[held].merge_branch = true; } } if merge.result < result.flags.len { result.flags[merge.result].merge_result = true; } }
    for carry in source.loop_carries { for held in [carry.incoming,carry.iteration,carry.backedge,carry.outgoing] { if held < result.flags.len { result.flags[held].carried = true; } } } return result,Error.none;
}
fn packParent(parent: Parent) -> u64 { assert(parent.position < 1073741824 && parent.count <= 3); return parent.node as u64 | ((parent.position as u64) << 32) | ((parent.count as u64) << 62); }
fn unpackParent(parent: u64) -> Parent { Parent { parent as! u32,((parent >> 32) & 1073741823) as u32,(parent >> 62) as u8 } }
fn ensure(uses: Uses&,source: const blot_check_core::Module&,unit: u32,need: Need) -> Error {
    let scope = Scope { source,unit };
    if need.parents && !uses.has_parents {
        let parents = owned_parents.alloc_slice(source.nodes.len);
        for node,index in source.nodes {
            if node.tag != blot_check_core::Tag.block_ && node.tag != blot_check_core::Tag.suite { continue; }
            for child,position in source.children(index as u32) {
                var parent = unpackParent(parents[child]); if parent.count == 0 { assert(position < 1073741824); parent = Parent { index as u32,position as u32 }; }
                if parent.count < 3 { parent.count++; } parents[child] = packParent(parent);
            }
        }
        if uses.parents.len != 0 { let first: const u64& = uses.parents[0]; let at = owned_parents.index_of(first); owned_parents.free_slice(owned_parents[at..at + uses.parents.len]); } uses.parents = parents; uses.has_parents = true;
    }
    if need.flow && !uses.has_flow {
        var definitions = Table<u32> {}; var inputs = Table<u32> {}; var carries = Table<u32> {}; var exits = Table<u32> {}; var values = Table<Exit> {}; var carry_loops: Carry[:] = []; var published = false;
        defer {
            if !published { definitions.deinit(); inputs.deinit(); carries.deinit(); exits.deinit(); values.deinit(); if carry_loops.len != 0 { owned_carries.free_slice(carry_loops); } }
        }
        let definition_table,definition_error = build(source.bindings.len,scope,owned_words,visitDefinitions); if definition_error != Error.none { return definition_error; } definitions = definition_table;
        let input_table,input_error = build(source.bindings.len,scope,owned_words,visitInputs); if input_error != Error.none { return input_error; } inputs = input_table;
        let carry_table,carry_error = build(source.bindings.len,scope,owned_words,visitCarries); if carry_error != Error.none { return carry_error; } carries = carry_table;
        let exit_table,exit_error = build(source.nodes.len,scope,owned_words,visitExits); if exit_error != Error.none { return exit_error; } exits = exit_table;
        let value_table,value_error = build(source.nodes.len,scope,owned_exits,visitValues); if value_error != Error.none { return value_error; } values = value_table;
        carry_loops = owned_carries.alloc_slice(source.loop_carries.len);
        for node,index in source.nodes { if node.tag != blot_check_core::Tag.loop_ { continue; } let range = source.loopInfo(index as u32).carries; for position in 0..range.len { carry_loops[range.start + position] = Carry { index as u32,position as u32 }; } }
        uses.definitions.deinit(); uses.inputs.deinit(); uses.carries.deinit(); uses.exits.deinit(); uses.values.deinit(); if uses.carry_loops.len != 0 { let first: const Carry& = uses.carry_loops[0]; let at = owned_carries.index_of(first); owned_carries.free_slice(owned_carries[at..at + uses.carry_loops.len]); }
        uses.definitions = definitions; uses.inputs = inputs; uses.carries = carries; uses.exits = exits; uses.values = values; uses.carry_loops = carry_loops; uses.has_flow = true; published = true;
    }
    return Error.none;
}
fn deinit(uses: Uses&) {
    uses.references.deinit(); if uses.flags.len != 0 { let first: const Flags& = uses.flags[0]; let at = owned_flags.index_of(first); owned_flags.free_slice(owned_flags[at..at + uses.flags.len]); }
    if uses.parents.len != 0 { let first: const u64& = uses.parents[0]; let at = owned_parents.index_of(first); owned_parents.free_slice(owned_parents[at..at + uses.parents.len]); }
    uses.definitions.deinit(); uses.inputs.deinit(); uses.carries.deinit(); uses.exits.deinit(); uses.values.deinit(); if uses.carry_loops.len != 0 { let first: const Carry& = uses.carry_loops[0]; let at = owned_carries.index_of(first); owned_carries.free_slice(owned_carries[at..at + uses.carry_loops.len]); } uses = Uses {};
}
fn flagsOf(uses: const Uses&,binding: u32) -> Flags { if binding < uses.flags.len { return uses.flags[binding]; } return Flags {}; }
fn parentOf(uses: const Uses&,id: u32) -> Parent { assert(uses.has_parents); if id >= uses.parents.len { return Parent {}; } return unpackParent(uses.parents[id]); }
