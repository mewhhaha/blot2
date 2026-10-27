// Generated explicit table relocation; runtime implementation is Goose only.
// External definitions are projections, never copied historical implementations.
namespace relocation;
import src.model;
import src.canonical;
import std;
struct Projection { source_definition:u32, target_definition:u32 }
struct Ref { table:u32, id:u32 }
struct Pair { table:u32, source:u32, target:u32 }
let PENDING:u32 = 0xffffffff;
fn operation_reference(tag:u32) -> u32 {
    if tag == OP_CALL || tag == OP_CLOSURE || tag == OP_FN_PLACE || tag == OP_GENERIC_BIND { return 30; }
    if tag == OP_TRY_ALLOC || tag == OP_LAYOUT_SIZE || tag == OP_LAYOUT_ALIGN { return 17; }
    if tag == OP_NAT_VALUE || tag == OP_REGION_RESET { return 15; }
    if tag == OP_STATIC { return 4; }
    return 0;
}
fn relocate_function(source:Core, source_definition:u32, target:CoreBuilder, target_definition:u32,
                     projections:const Projection[:], work:Work&) -> bool {
    if !id_ok(source_definition,source.definitions.len) || !id_ok(target_definition,target.definitions.len) { return false; }
    let original=source.definitions[source_definition]; let replacement=target.definitions[target_definition];
    if original.kind != DEF_FUNCTION || replacement.kind != DEF_FUNCTION || original.function == 0 || replacement.function != 0 || replacement.type_id == 0 { return false; }
    // Sparse keys include their table: equal numeric IDs in different arenas
    // are distinct. Only the reached graph occupies workspace.
    var mappings:Pair[>..]=[]; var slots:u32[>..]=[0;64];
    var queue:Ref[>..]=[]; var paired:Pair[>..]=[]; var prepared=false;
    fn tick() { if !charge(work,1,LIMIT_VISITS) { return false from relocate_function; } }
    fn hash_key(table:u32,id:u32) -> u32 { return (id * 16777619) ^ (table * 2654435761); }
    fn locate(table:u32,id:u32) -> u32 {
        var slot=hash_key(table,id) & (slots.len as u32-1);
        // Insertion bounds each successful key's displacement. Lookups after
        // preparation cannot exhaust optional work after target mutation.
        for probe in 128 {
            if !prepared { tick(); }
            if slots[slot]==0 { return slot; }
            let row=mappings[slots[slot]-1];
            if row.table==table && row.source==id { return slot; }
            slot=(slot+1)&(slots.len as u32-1);
        }
        if prepared { assert(false); } return false from relocate_function;
    }
    fn mapped(table:u32,id:u32) -> u32 {
        if id==0 || table==0 { return id; }
        let slot=locate(table,id); return if slots[slot]==0 { 0 } else { mappings[slots[slot]-1].target };
    }
    fn assign(table:u32,id:u32,value:u32) {
        let slot=locate(table,id);
        if slots[slot]!=0 { mappings[slots[slot]-1].target=value; return; }
        assert(!prepared);
        if (mappings.len+1)*2>slots.len {
            if slots.len==1048576 { return false from relocate_function; }
            let capacity=slots.len*2; slots.resize(0); for i in capacity { slots.push(0); }
            for row,index in mappings { let next=locate(row.table,row.source); slots[next]=index as u32+1; }
        }
        let next=locate(table,id); mappings.push(Pair {table,id,value}); slots[next]=mappings.len as u32;
    }
    fn pair(table:u32,a:u32,b:u32) {
        tick(); if a == 0 || b == 0 { if a != b { return false from relocate_function; } return; }
        let old=mapped(table,a); if old != 0 { if old != b { return false from relocate_function; } return; }
        assign(table,a,b); paired.push(Pair {table,a,b});
    }
    fn pair_span(table:u32,a:Span,b:Span) {
        if a.count != b.count { return false from relocate_function; }
        for i in a.count { pair(table,source.refs[a.start+i],target.refs[b.start+i]); }
    }
    fn project(a:u32,b:u32) {
        tick(); if !id_ok(a,source.definitions.len) || !id_ok(b,target.definitions.len) { return false from relocate_function; }
        let x=source.definitions[a]; let y=target.definitions[b];
        if x.kind != y.kind || name_bytes(source,x.name) != name_bytes(core_view(target),y.name) ||
            name_bytes(source,source.modules[x.module].path) != name_bytes(core_view(target),target.modules[y.module].path) { return false from relocate_function; }
        var left:u8[>..]=[]; var right:u8[>..]=[];
        if !canonical_interface(source,x.type_id,left) || !canonical_interface(core_view(target),y.type_id,right) || left != right { return false from relocate_function; }
        assign(11,a,b); assign(14,x.module,y.module);
        if a != source_definition { if x.function != 0 { if y.function == 0 { return false from relocate_function; } assign(30,x.function,y.function); } }
        if x.kind == DEF_STATIC {
            if !id_ok(x.value,source.values.len) || !id_ok(y.value,target.values.len) { return false from relocate_function; }
            let old_op=source.values[x.value].op; let new_op=target.values[y.value].op;
            if old_op == 0 || new_op == 0 || source.ops[old_op].tag != OP_STATIC || target.ops[new_op].tag != OP_STATIC { return false from relocate_function; }
            let a=source.ops[old_op].imm0; let b=target.ops[new_op].imm0; let old_static=source.static_objects[a]; let new_static=target.static_objects[b];
            if old_static.kind != new_static.kind || old_static.count != new_static.count || old_static.relocations.count != 0 || new_static.relocations.count != 0 ||
                source.bytes[old_static.bytes.start..old_static.bytes.start+old_static.bytes.count] != target.bytes[new_static.bytes.start..new_static.bytes.start+new_static.bytes.count] { return false from relocate_function; }
            assign(21,x.value,y.value); assign(22,old_op,new_op); assign(4,a,b);
        }
        pair(17,x.type_id,y.type_id); pair_span(15,x.binders,y.binders);
    }
    project(source_definition,target_definition);
    for projection in projections { if projection.source_definition == source_definition { return false; } project(projection.source_definition,projection.target_definition); }
    var cursor:i64=0;
    while cursor < paired.len {
        tick(); let item=paired[cursor]; cursor++;
        if item.table == 15 { let row=source.binders[item.source]; let other=target.binders[item.target];
        }
        if item.table == 17 { let row=source.types[item.source]; let other=target.types[item.target];
            pair_span(17,row.children,other.children);
            pair_span(18,row.fields,other.fields);
            pair_span(15,row.binders,other.binders);
            pair(15,row.region,other.region);
            pair(26,row.nat,other.nat);
            pair(15,row.domain,other.domain);
            pair(26,row.capacity,other.capacity);
            pair(19,row.contract,other.contract);
            pair(15,row.binder,other.binder);
        }
        if item.table == 18 { let row=source.fields[item.source]; let other=target.fields[item.target];
            pair(17,row.type_id,other.type_id);
        }
        if item.table == 19 { let row=source.contracts[item.source]; let other=target.contracts[item.target];
            pair_span(1,row.layout_premises,other.layout_premises);
            pair(17,row.arg,other.arg);
            pair(17,row.result,other.result);
            pair_span(15,row.binders,other.binders);
            pair_span(27,row.requires,other.requires);
            pair_span(27,row.ensures,other.ensures);
            pair_span(27,row.on_true,other.on_true);
            pair_span(27,row.on_false,other.on_false);
            pair_span(20,row.effects,other.effects);
        }
        if item.table == 20 { let row=source.effects[item.source]; let other=target.effects[item.target];
            pair(15,row.region,other.region);
        }
        if item.table == 26 { let row=source.terms[item.source]; let other=target.terms[item.target];
            pair(17,row.type_id,other.type_id);
            pair(21,row.value,other.value);
            pair((if row.tag == EXPR_ARG || row.tag == EXPR_RESULT { 19 } else { 15 }),row.binder,other.binder);
            pair_span(26,row.args,other.args);
        }
        if item.table == 27 { let row=source.facts[item.source]; let other=target.facts[item.target];
            pair(26,row.left,other.left);
            pair(26,row.right,other.right);
            pair(26,row.third,other.third);
            pair(15,row.domain,other.domain);
        }
    }
    fn mark(table:u32,id:u32) {
        tick(); if id == 0 || table == 0 || mapped(table,id) != 0 { return; }
        if table == 11 { return false from relocate_function; }
        if table == 30 && source.functions[id].producer != 0 && source.functions[id].producer != source_definition { return false from relocate_function; }
        if table == 14 {
            let path=name_bytes(source,source.modules[id].path);
            for row,index in target.modules { tick(); if index != 0 && path == name_bytes(core_view(target),row.path) { assign(14,id,index as u32); return; } }
            return false from relocate_function;
        }
        assign(table,id,PENDING); queue.push(Ref {table,id});
    }
    fn mark_span(table:u32,span:Span) { for i in span.count { mark(table,source.refs[span.start+i]); } }
    mark(30,original.function);
    cursor=0;
    var scanned:i64=-1;
    while cursor < queue.len || scanned != queue.len {
        if cursor == queue.len {
            scanned=queue.len;
            for row,id in source.evidence {
                if id == 0 { continue; } var scope=row.scope;
                for depth in 65 {
                    if scope == 0 { break; }
                    if mapped(16,scope) == PENDING { mark(28,id as u32); break; }
                    scope=source.scopes[scope].parent;
                }
            }
            for row,id in source.loops { if id != 0 && mapped(30,source.blocks[row.header].function) == PENDING { mark(29,id as u32); } }
            for row,id in source.interfaces { if id != 0 && mapped(30,row.function) == PENDING { mark(37,id as u32); } }
            for row,id in source.receipts { if id != 0 && row.producer == source_definition { mark(39,id as u32); } }
            for row,id in source.callable_adapters { if id != 0 && mapped(22,row.op) == PENDING { mark(6,id as u32); } }
            if cursor == queue.len { break; }
        }
        tick(); let item=queue[cursor]; cursor++;
        if item.table == 1 { let row=source.layout_premises[item.id];
            mark(17,row.type_id);
        }
        if item.table == 2 { let row=source.dictionary_realizations[item.id];
            mark(17,row.type_id);
            mark_span(15,row.parameters);
            mark_span(17,row.arguments);
            mark(17,row.concrete_type);
            mark(36,row.layout);
        }
        if item.table == 3 { let row=source.static_relocations[item.id];
            mark((if row.kind == STATIC_ADDRESS { 4 } else if row.kind == STATIC_FUNCTION { 30 } else if row.kind == STATIC_DICTIONARY { 17 } else { 22 }),row.target);
            mark((if row.kind == STATIC_CLOSURE { 4 } else { 0 }),row.addend);
        }
        if item.table == 4 { let row=source.static_objects[item.id];
            mark(30,row.function);
            mark(22,row.constructor);
            mark(17,row.type_id);
            mark(17,row.element_type);
            mark(15,row.domain);
            mark_span(3,row.relocations);
            mark(11,row.producer);
        }
        if item.table == 5 { let row=source.adapter_captures[item.id];
            mark((if row.kind == KIND_TYPE { 17 } else { 26 }),row.source);
        }
        if item.table == 6 { let row=source.callable_adapters[item.id];
            mark(22,row.op);
            mark(30,row.target_function);
            mark(19,row.callback_contract);
            mark_span(5,row.captures);
            mark(36,row.environment_layout);
        }
        if item.table == 7 { let row=source.schemas[item.id];
        }
        if item.table == 8 { let row=source.environment_bindings[item.id];
            mark(30,row.function);
            mark(15,row.binder);
            mark(21,row.source_value);
        }
        if item.table == 9 { let row=source.nat_witnesses[item.id];
            mark(15,row.binder);
        }
        if item.table == 10 { let row=source.abi_plans[item.id];
            mark(19,row.contract);
            mark(30,row.function);
            mark(36,row.arg_layout);
            mark(36,row.result_layout);
            mark(36,row.env_layout);
            mark_span(15,row.dictionaries);
            mark_span(9,row.nat_witnesses);
        }
        if item.table == 11 { let row=source.definitions[item.id];
            mark(12,row.name);
            mark(14,row.module);
            mark(17,row.type_id);
            mark(21,row.value);
            mark(30,row.function);
            mark_span(15,row.binders);
            mark(13,row.origin);
        }
        if item.table == 12 { let row=source.names[item.id];
        }
        if item.table == 13 { let row=source.origins[item.id];
            if row.module != original.module || row.start < source.origins[original.origin].start || row.end > source.origins[original.origin].end { return false; }
            mark(14,row.module);
        }
        if item.table == 14 { let row=source.modules[item.id];
            mark(12,row.name);
            mark(12,row.path);
            mark_span(14,row.imports);
            mark_span(11,row.declarations);
        }
        if item.table == 15 { let row=source.binders[item.id];
            mark(16,row.scope);
            mark((if row.introduction_kind == INTRO_FUNCTION { 30 } else if row.introduction_kind == INTRO_OPERATION { 22 } else { 0 }),row.introduction);
            mark(12,row.name);
            mark(13,row.origin);
        }
        if item.table == 16 { let row=source.scopes[item.id];
            mark(16,row.parent);
            mark(15,row.binder);
            mark(13,row.origin);
        }
        if item.table == 17 { let row=source.types[item.id];
            mark_span(17,row.children);
            mark_span(18,row.fields);
            mark_span(15,row.binders);
            mark(15,row.region);
            mark(26,row.nat);
            mark(15,row.domain);
            mark(26,row.capacity);
            mark(19,row.contract);
            mark(15,row.binder);
            mark(13,row.origin);
        }
        if item.table == 18 { let row=source.fields[item.id];
            mark(12,row.name);
            mark(17,row.type_id);
        }
        if item.table == 19 { let row=source.contracts[item.id];
            mark_span(1,row.layout_premises);
            mark(17,row.arg);
            mark(17,row.result);
            mark_span(15,row.binders);
            mark_span(27,row.requires);
            mark_span(27,row.ensures);
            mark_span(27,row.on_true);
            mark_span(27,row.on_false);
            mark_span(20,row.effects);
            mark(13,row.origin);
        }
        if item.table == 20 { let row=source.effects[item.id];
            mark(15,row.region);
        }
        if item.table == 21 { let row=source.values[item.id];
            mark(17,row.type_id);
            mark(23,row.block_id);
            mark(22,row.op);
            mark(16,row.scope);
            mark(13,row.origin);
        }
        if item.table == 22 { let row=source.ops[item.id];
            mark_span(21,row.args);
            mark_span(21,row.results);
            mark_span(28,row.evidence);
            mark_span(32,row.substitutions);
            mark(16,row.scope);
            mark(13,row.origin);
            mark(operation_reference(row.tag),row.imm0);
        }
        if item.table == 23 { let row=source.blocks[item.id];
            mark(23,row.merge);
            mark_span(21,row.params);
            mark_span(28,row.evidence_params);
            mark_span(22,row.ops);
            mark(24,row.term);
            mark(16,row.scope);
            mark(30,row.function);
            mark(13,row.origin);
        }
        if item.table == 24 { let row=source.terminators[item.id];
            mark_span(28,row.evidence);
            mark(21,row.subject);
            mark_span(25,row.edges);
            mark_span(21,row.discharge);
            mark(13,row.origin);
        }
        if item.table == 25 { let row=source.edges[item.id];
            mark(23,row.from);
            mark(23,row.to);
            mark_span(21,row.args);
            mark_span(28,row.evidence);
            mark(29,row.loop_id);
        }
        if item.table == 26 { let row=source.terms[item.id];
            mark(17,row.type_id);
            mark(21,row.value);
            mark((if row.tag == EXPR_ARG || row.tag == EXPR_RESULT { 19 } else { 15 }),row.binder);
            mark_span(26,row.args);
            mark(16,row.scope);
        }
        if item.table == 27 { let row=source.facts[item.id];
            mark(26,row.left);
            mark(26,row.right);
            mark(26,row.third);
            mark(15,row.domain);
        }
        if item.table == 28 { let row=source.evidence[item.id];
            mark(27,row.fact);
            mark(19,row.contract);
            mark(27,row.formal_fact);
            mark(22,row.call);
            mark(16,row.scope);
            mark(25,row.edge);
            mark_span(21,row.operands);
            mark_span(28,row.premises);
            mark(13,row.origin);
        }
        if item.table == 29 { let row=source.loops[item.id];
            mark(23,row.header);
            mark(23,row.body);
            mark(23,row.exit);
            mark(21,row.index);
            mark(26,row.lower);
            mark(26,row.upper);
            mark_span(21,row.carries);
            mark_span(28,row.invariant);
            mark_span(25,row.backedges);
            mark_span(25,row.exits);
        }
        if item.table == 30 { let row=source.functions[item.id];
            mark_span(8,row.environment_bindings);
            mark(12,row.name);
            mark(14,row.module);
            mark(17,row.type_id);
            mark(19,row.contract);
            mark(21,row.param);
            mark(23,row.entry);
            mark_span(23,row.blocks);
            mark_span(33,row.captures);
            mark_span(31,row.calls);
            mark_span(15,row.binders);
            mark(11,row.producer);
            mark(13,row.origin);
        }
        if item.table == 31 { let row=source.calls[item.id];
            mark(22,row.op);
            mark(30,row.caller);
            mark(30,row.callee);
            mark(19,row.contract);
            mark_span(32,row.substitutions);
        }
        if item.table == 32 { let row=source.substitutions[item.id];
            mark(15,row.binder);
            mark((if row.kind == KIND_TYPE { 17 } else if row.kind == KIND_NAT { 26 } else { 15 }),row.value);
        }
        if item.table == 33 { let row=source.captures[item.id];
            mark(30,row.function);
            mark(21,row.value);
            mark(21,row.local_value);
            mark(16,row.scope);
        }
        if item.table == 34 { let row=source.loans[item.id];
            mark(21,row.value);
            mark(21,row.owner);
            mark(16,row.scope);
            mark(22,row.begin_op);
            mark(22,row.end_op);
        }
        if item.table == 35 { let row=source.transitions[item.id];
            mark(22,row.op);
            mark(21,row.value);
            mark(21,row.before);
            mark(21,row.after);
            mark(16,row.scope);
        }
        if item.table == 36 { let row=source.layouts[item.id];
            mark(17,row.type_id);
            mark(7,row.schema);
            mark_span(18,row.fields);
        }
        if item.table == 37 { let row=source.interfaces[item.id];
            mark(30,row.function);
            mark(17,row.type_id);
            mark(19,row.contract);
            mark_span(38,row.dependencies);
            mark(11,row.producer);
        }
        if item.table == 38 { let row=source.dependencies[item.id];
            mark(11,row.producer);
        }
        if item.table == 39 { let row=source.receipts[item.id];
            mark(11,row.producer);
            mark_span(38,row.dependencies);
        }
        if item.table == 40 { let row=source.exports[item.id];
            mark(30,row.function);
            mark(12,row.name);
            mark(17,row.arg_type);
            mark(17,row.result_type);
            mark_span(32,row.substitutions);
            mark_span(18,row.fields);
        }
    }
    // No optional decline occurs after this point. The owning build transaction
    // handles process allocation failure and atomically publishes only validation.
    sort(queue[..]) {a,z=>a.table<z.table || (a.table==z.table && a.id<z.id)};
    prepared=true;
    for item in queue { if item.table == 1 { assign(1,item.id,target.layout_premises.len as u32); target.layout_premises.push(LayoutPremise {..}); } }
    for item in queue { if item.table == 2 { assign(2,item.id,target.dictionary_realizations.len as u32); target.dictionary_realizations.push(DictionaryRealization {..}); } }
    for item in queue { if item.table == 3 { assign(3,item.id,target.static_relocations.len as u32); target.static_relocations.push(StaticRelocation {..}); } }
    for item in queue { if item.table == 4 { assign(4,item.id,target.static_objects.len as u32); target.static_objects.push(StaticObject {..}); } }
    for item in queue { if item.table == 5 { assign(5,item.id,target.adapter_captures.len as u32); target.adapter_captures.push(AdapterCapture {..}); } }
    for item in queue { if item.table == 6 { assign(6,item.id,target.callable_adapters.len as u32); target.callable_adapters.push(CallableAdapter {..}); } }
    for item in queue { if item.table == 7 { assign(7,item.id,target.schemas.len as u32); target.schemas.push(Schema {..}); } }
    for item in queue { if item.table == 8 { assign(8,item.id,target.environment_bindings.len as u32); target.environment_bindings.push(EnvironmentBinding {..}); } }
    for item in queue { if item.table == 9 { assign(9,item.id,target.nat_witnesses.len as u32); target.nat_witnesses.push(NatWitness {..}); } }
    for item in queue { if item.table == 10 { assign(10,item.id,target.abi_plans.len as u32); target.abi_plans.push(AbiPlan {..}); } }
    for item in queue { if item.table == 12 { assign(12,item.id,target.names.len as u32); target.names.push(Name {..}); } }
    for item in queue { if item.table == 13 { assign(13,item.id,target.origins.len as u32); target.origins.push(Origin {..}); } }
    for item in queue { if item.table == 15 { assign(15,item.id,target.binders.len as u32); target.binders.push(Binder {..}); } }
    for item in queue { if item.table == 16 { assign(16,item.id,target.scopes.len as u32); target.scopes.push(Scope {..}); } }
    for item in queue { if item.table == 17 { assign(17,item.id,target.types.len as u32); target.types.push(TypeNode {..}); } }
    for item in queue { if item.table == 18 { assign(18,item.id,target.fields.len as u32); target.fields.push(Field {..}); } }
    for item in queue { if item.table == 19 { assign(19,item.id,target.contracts.len as u32); target.contracts.push(Contract {..}); } }
    for item in queue { if item.table == 20 { assign(20,item.id,target.effects.len as u32); target.effects.push(Effect {..}); } }
    for item in queue { if item.table == 21 { assign(21,item.id,target.values.len as u32); target.values.push(Value {..}); } }
    for item in queue { if item.table == 22 { assign(22,item.id,target.ops.len as u32); target.ops.push(Operation {..}); } }
    for item in queue { if item.table == 23 { assign(23,item.id,target.blocks.len as u32); target.blocks.push(Block {..}); } }
    for item in queue { if item.table == 24 { assign(24,item.id,target.terminators.len as u32); target.terminators.push(Terminator {..}); } }
    for item in queue { if item.table == 25 { assign(25,item.id,target.edges.len as u32); target.edges.push(Edge {..}); } }
    for item in queue { if item.table == 27 { assign(27,item.id,target.facts.len as u32); target.facts.push(Fact {..}); } }
    for item in queue { if item.table == 28 { assign(28,item.id,target.evidence.len as u32); target.evidence.push(Evidence {..}); } }
    for item in queue { if item.table == 29 { assign(29,item.id,target.loops.len as u32); target.loops.push(Loop {..}); } }
    for item in queue { if item.table == 30 { assign(30,item.id,target.functions.len as u32); target.functions.push(Function {..}); } }
    for item in queue { if item.table == 31 { assign(31,item.id,target.calls.len as u32); target.calls.push(Call {..}); } }
    for item in queue { if item.table == 32 { assign(32,item.id,target.substitutions.len as u32); target.substitutions.push(Substitution {..}); } }
    for item in queue { if item.table == 33 { assign(33,item.id,target.captures.len as u32); target.captures.push(Capture {..}); } }
    for item in queue { if item.table == 34 { assign(34,item.id,target.loans.len as u32); target.loans.push(Loan {..}); } }
    for item in queue { if item.table == 35 { assign(35,item.id,target.transitions.len as u32); target.transitions.push(Transition {..}); } }
    for item in queue { if item.table == 36 { assign(36,item.id,target.layouts.len as u32); target.layouts.push(Layout {..}); } }
    for item in queue { if item.table == 37 { assign(37,item.id,target.interfaces.len as u32); target.interfaces.push(Interface {..}); } }
    for item in queue { if item.table == 38 { assign(38,item.id,target.dependencies.len as u32); target.dependencies.push(Dependency {..}); } }
    for item in queue { if item.table == 39 { assign(39,item.id,target.receipts.len as u32); target.receipts.push(Receipt {..}); } }
    for item in queue { if item.table == 40 { assign(40,item.id,target.exports.len as u32); target.exports.push(Export {..}); } }
    fn span(table:u32,old:Span) -> Span {
        let result=Span {start:target.refs.len as u32,count:old.count};
        for i in old.count { target.refs.push(mapped(table,source.refs[old.start+i])); } return result;
    }
    fn bytes(old:Span) -> Span {
        let result=Span {start:target.bytes.len as u32,count:old.count}; target.bytes.append(source.bytes[old.start..old.start+old.count]); return result;
    }
    for item in queue {
        if item.table != 26 { continue; } let id=item.id; let old=source.terms[id];
        var row=old;
        row.type_id=mapped(17,old.type_id);
        row.value=mapped(21,old.value);
        row.binder=mapped((if row.tag == EXPR_ARG || row.tag == EXPR_RESULT { 19 } else { 15 }),old.binder);
        row.args=span(26,old.args);
        row.scope=mapped(16,old.scope);
        var existing:u32=0;
        for candidate,index in target.terms {
            if index == 0 { continue; }
            if row.tag == EXPR_LITERAL && candidate.tag == EXPR_LITERAL && row.literal == candidate.literal { existing=index as u32; break; }
            if row.tag == EXPR_BINDER && candidate.tag == EXPR_BINDER && row.binder == candidate.binder { existing=index as u32; break; }
        }
        if existing == 0 { existing=target.terms.len as u32; target.terms.push(row); }
        assign(26,id,existing);
    }
    for item in queue { if item.table != 1 { continue; } let old=source.layout_premises[item.id]; var row=old;
        row.type_id=mapped(17,old.type_id);
        target.layout_premises[mapped(1,item.id)]=row;
    }
    for item in queue { if item.table != 2 { continue; } let old=source.dictionary_realizations[item.id]; var row=old;
        row.type_id=mapped(17,old.type_id);
        row.parameters=span(15,old.parameters);
        row.arguments=span(17,old.arguments);
        row.concrete_type=mapped(17,old.concrete_type);
        row.layout=mapped(36,old.layout);
        target.dictionary_realizations[mapped(2,item.id)]=row;
    }
    for item in queue { if item.table != 3 { continue; } let old=source.static_relocations[item.id]; var row=old;
        row.target=mapped((if row.kind == STATIC_ADDRESS { 4 } else if row.kind == STATIC_FUNCTION { 30 } else if row.kind == STATIC_DICTIONARY { 17 } else { 22 }),old.target);
        row.addend=mapped((if row.kind == STATIC_CLOSURE { 4 } else { 0 }),old.addend);
        target.static_relocations[mapped(3,item.id)]=row;
    }
    for item in queue { if item.table != 4 { continue; } let old=source.static_objects[item.id]; var row=old;
        row.function=mapped(30,old.function);
        row.constructor=mapped(22,old.constructor);
        row.type_id=mapped(17,old.type_id);
        row.element_type=mapped(17,old.element_type);
        row.domain=mapped(15,old.domain);
        row.bytes=bytes(old.bytes);
        row.relocations=span(3,old.relocations);
        row.producer=mapped(11,old.producer);
        target.static_objects[mapped(4,item.id)]=row;
    }
    for item in queue { if item.table != 5 { continue; } let old=source.adapter_captures[item.id]; var row=old;
        row.source=mapped((if row.kind == KIND_TYPE { 17 } else { 26 }),old.source);
        target.adapter_captures[mapped(5,item.id)]=row;
    }
    for item in queue { if item.table != 6 { continue; } let old=source.callable_adapters[item.id]; var row=old;
        row.op=mapped(22,old.op);
        row.target_function=mapped(30,old.target_function);
        row.callback_contract=mapped(19,old.callback_contract);
        row.captures=span(5,old.captures);
        row.environment_layout=mapped(36,old.environment_layout);
        target.callable_adapters[mapped(6,item.id)]=row;
    }
    for item in queue { if item.table != 7 { continue; } let old=source.schemas[item.id]; var row=old;
        row.bytes=bytes(old.bytes);
        row.digest=bytes(old.digest);
        target.schemas[mapped(7,item.id)]=row;
    }
    for item in queue { if item.table != 8 { continue; } let old=source.environment_bindings[item.id]; var row=old;
        row.function=mapped(30,old.function);
        row.binder=mapped(15,old.binder);
        row.source_value=mapped(21,old.source_value);
        target.environment_bindings[mapped(8,item.id)]=row;
    }
    for item in queue { if item.table != 9 { continue; } let old=source.nat_witnesses[item.id]; var row=old;
        row.binder=mapped(15,old.binder);
        row.argument_path=span(0,old.argument_path);
        target.nat_witnesses[mapped(9,item.id)]=row;
    }
    for item in queue { if item.table != 10 { continue; } let old=source.abi_plans[item.id]; var row=old;
        row.contract=mapped(19,old.contract);
        row.function=mapped(30,old.function);
        row.arg_layout=mapped(36,old.arg_layout);
        row.result_layout=mapped(36,old.result_layout);
        row.env_layout=mapped(36,old.env_layout);
        row.dictionaries=span(15,old.dictionaries);
        row.nat_witnesses=span(9,old.nat_witnesses);
        target.abi_plans[mapped(10,item.id)]=row;
    }
    for item in queue { if item.table != 12 { continue; } let old=source.names[item.id]; var row=old;
        row.bytes=bytes(old.bytes);
        target.names[mapped(12,item.id)]=row;
    }
    for item in queue { if item.table != 13 { continue; } let old=source.origins[item.id]; var row=old;
        row.module=mapped(14,old.module);
        row.start=old.start-source.origins[original.origin].start+target.origins[replacement.origin].start;
        row.end=old.end-source.origins[original.origin].start+target.origins[replacement.origin].start;
        target.origins[mapped(13,item.id)]=row;
    }
    for item in queue { if item.table != 15 { continue; } let old=source.binders[item.id]; var row=old;
        row.scope=mapped(16,old.scope);
        row.introduction=mapped((if row.introduction_kind == INTRO_FUNCTION { 30 } else if row.introduction_kind == INTRO_OPERATION { 22 } else { 0 }),old.introduction);
        row.name=mapped(12,old.name);
        row.origin=mapped(13,old.origin);
        target.binders[mapped(15,item.id)]=row;
    }
    for item in queue { if item.table != 16 { continue; } let old=source.scopes[item.id]; var row=old;
        row.parent=mapped(16,old.parent);
        row.binder=mapped(15,old.binder);
        row.origin=mapped(13,old.origin);
        target.scopes[mapped(16,item.id)]=row;
    }
    for item in queue { if item.table != 17 { continue; } let old=source.types[item.id]; var row=old;
        row.children=span(17,old.children);
        row.fields=span(18,old.fields);
        row.binders=span(15,old.binders);
        row.region=mapped(15,old.region);
        row.nat=mapped(26,old.nat);
        row.domain=mapped(15,old.domain);
        row.capacity=mapped(26,old.capacity);
        row.contract=mapped(19,old.contract);
        row.binder=mapped(15,old.binder);
        row.origin=mapped(13,old.origin);
        target.types[mapped(17,item.id)]=row;
    }
    for item in queue { if item.table != 18 { continue; } let old=source.fields[item.id]; var row=old;
        row.name=mapped(12,old.name);
        row.type_id=mapped(17,old.type_id);
        target.fields[mapped(18,item.id)]=row;
    }
    for item in queue { if item.table != 19 { continue; } let old=source.contracts[item.id]; var row=old;
        row.layout_premises=span(1,old.layout_premises);
        row.arg=mapped(17,old.arg);
        row.result=mapped(17,old.result);
        row.binders=span(15,old.binders);
        row.requires=span(27,old.requires);
        row.ensures=span(27,old.ensures);
        row.on_true=span(27,old.on_true);
        row.on_false=span(27,old.on_false);
        row.effects=span(20,old.effects);
        row.origin=mapped(13,old.origin);
        target.contracts[mapped(19,item.id)]=row;
    }
    for item in queue { if item.table != 20 { continue; } let old=source.effects[item.id]; var row=old;
        row.region=mapped(15,old.region);
        target.effects[mapped(20,item.id)]=row;
    }
    for item in queue { if item.table != 21 { continue; } let old=source.values[item.id]; var row=old;
        row.type_id=mapped(17,old.type_id);
        row.block_id=mapped(23,old.block_id);
        row.op=mapped(22,old.op);
        row.scope=mapped(16,old.scope);
        row.origin=mapped(13,old.origin);
        target.values[mapped(21,item.id)]=row;
    }
    for item in queue { if item.table != 22 { continue; } let old=source.ops[item.id]; var row=old;
        row.args=span(21,old.args);
        row.results=span(21,old.results);
        row.evidence=span(28,old.evidence);
        row.substitutions=span(32,old.substitutions);
        row.scope=mapped(16,old.scope);
        row.origin=mapped(13,old.origin);
        row.imm0=mapped(operation_reference(row.tag),old.imm0);
        target.ops[mapped(22,item.id)]=row;
    }
    for item in queue { if item.table != 23 { continue; } let old=source.blocks[item.id]; var row=old;
        row.merge=mapped(23,old.merge);
        row.params=span(21,old.params);
        row.evidence_params=span(28,old.evidence_params);
        row.ops=span(22,old.ops);
        row.term=mapped(24,old.term);
        row.scope=mapped(16,old.scope);
        row.function=mapped(30,old.function);
        row.origin=mapped(13,old.origin);
        target.blocks[mapped(23,item.id)]=row;
    }
    for item in queue { if item.table != 24 { continue; } let old=source.terminators[item.id]; var row=old;
        row.evidence=span(28,old.evidence);
        row.subject=mapped(21,old.subject);
        row.edges=span(25,old.edges);
        row.discharge=span(21,old.discharge);
        row.origin=mapped(13,old.origin);
        target.terminators[mapped(24,item.id)]=row;
    }
    for item in queue { if item.table != 25 { continue; } let old=source.edges[item.id]; var row=old;
        row.from=mapped(23,old.from);
        row.to=mapped(23,old.to);
        row.args=span(21,old.args);
        row.evidence=span(28,old.evidence);
        row.loop_id=mapped(29,old.loop_id);
        target.edges[mapped(25,item.id)]=row;
    }
    for item in queue { if item.table != 27 { continue; } let old=source.facts[item.id]; var row=old;
        row.left=mapped(26,old.left);
        row.right=mapped(26,old.right);
        row.third=mapped(26,old.third);
        row.domain=mapped(15,old.domain);
        target.facts[mapped(27,item.id)]=row;
    }
    for item in queue { if item.table != 28 { continue; } let old=source.evidence[item.id]; var row=old;
        row.fact=mapped(27,old.fact);
        row.contract=mapped(19,old.contract);
        row.formal_fact=mapped(27,old.formal_fact);
        row.call=mapped(22,old.call);
        row.scope=mapped(16,old.scope);
        row.edge=mapped(25,old.edge);
        row.operands=span(21,old.operands);
        row.premises=span(28,old.premises);
        row.origin=mapped(13,old.origin);
        target.evidence[mapped(28,item.id)]=row;
    }
    for item in queue { if item.table != 29 { continue; } let old=source.loops[item.id]; var row=old;
        row.header=mapped(23,old.header);
        row.body=mapped(23,old.body);
        row.exit=mapped(23,old.exit);
        row.index=mapped(21,old.index);
        row.lower=mapped(26,old.lower);
        row.upper=mapped(26,old.upper);
        row.carries=span(21,old.carries);
        row.invariant=span(28,old.invariant);
        row.backedges=span(25,old.backedges);
        row.exits=span(25,old.exits);
        target.loops[mapped(29,item.id)]=row;
    }
    for item in queue { if item.table != 30 { continue; } let old=source.functions[item.id]; var row=old;
        row.environment_bindings=span(8,old.environment_bindings);
        row.name=mapped(12,old.name);
        row.module=mapped(14,old.module);
        row.type_id=mapped(17,old.type_id);
        row.contract=mapped(19,old.contract);
        row.param=mapped(21,old.param);
        row.entry=mapped(23,old.entry);
        row.blocks=span(23,old.blocks);
        row.captures=span(33,old.captures);
        row.calls=span(31,old.calls);
        row.binders=span(15,old.binders);
        row.export_id=0;
        row.producer=mapped(11,old.producer);
        row.origin=mapped(13,old.origin);
        target.functions[mapped(30,item.id)]=row;
    }
    for item in queue { if item.table != 31 { continue; } let old=source.calls[item.id]; var row=old;
        row.op=mapped(22,old.op);
        row.caller=mapped(30,old.caller);
        row.callee=mapped(30,old.callee);
        row.contract=mapped(19,old.contract);
        row.substitutions=span(32,old.substitutions);
        target.calls[mapped(31,item.id)]=row;
    }
    for item in queue { if item.table != 32 { continue; } let old=source.substitutions[item.id]; var row=old;
        row.binder=mapped(15,old.binder);
        row.value=mapped((if row.kind == KIND_TYPE { 17 } else if row.kind == KIND_NAT { 26 } else { 15 }),old.value);
        target.substitutions[mapped(32,item.id)]=row;
    }
    for item in queue { if item.table != 33 { continue; } let old=source.captures[item.id]; var row=old;
        row.function=mapped(30,old.function);
        row.value=mapped(21,old.value);
        row.local_value=mapped(21,old.local_value);
        row.scope=mapped(16,old.scope);
        target.captures[mapped(33,item.id)]=row;
    }
    for item in queue { if item.table != 34 { continue; } let old=source.loans[item.id]; var row=old;
        row.value=mapped(21,old.value);
        row.owner=mapped(21,old.owner);
        row.scope=mapped(16,old.scope);
        row.begin_op=mapped(22,old.begin_op);
        row.end_op=mapped(22,old.end_op);
        target.loans[mapped(34,item.id)]=row;
    }
    for item in queue { if item.table != 35 { continue; } let old=source.transitions[item.id]; var row=old;
        row.op=mapped(22,old.op);
        row.value=mapped(21,old.value);
        row.before=mapped(21,old.before);
        row.after=mapped(21,old.after);
        row.scope=mapped(16,old.scope);
        target.transitions[mapped(35,item.id)]=row;
    }
    for item in queue { if item.table != 36 { continue; } let old=source.layouts[item.id]; var row=old;
        row.type_id=mapped(17,old.type_id);
        row.schema=mapped(7,old.schema);
        row.fields=span(18,old.fields);
        target.layouts[mapped(36,item.id)]=row;
    }
    for item in queue { if item.table != 37 { continue; } let old=source.interfaces[item.id]; var row=old;
        row.abi_digest=bytes(old.abi_digest);
        row.function=mapped(30,old.function);
        row.type_id=mapped(17,old.type_id);
        row.contract=mapped(19,old.contract);
        row.dependencies=span(38,old.dependencies);
        row.digest=bytes(old.digest);
        row.producer=mapped(11,old.producer);
        target.interfaces[mapped(37,item.id)]=row;
    }
    for item in queue { if item.table != 38 { continue; } let old=source.dependencies[item.id]; var row=old;
        row.producer=mapped(11,old.producer);
        row.identity=bytes(old.identity);
        row.digest=bytes(old.digest);
        target.dependencies[mapped(38,item.id)]=row;
    }
    for item in queue { if item.table != 39 { continue; } let old=source.receipts[item.id]; var row=old;
        row.producer=mapped(11,old.producer);
        row.source_digest=bytes(old.source_digest);
        row.semantic_digest=bytes(old.semantic_digest);
        row.dependencies=span(38,old.dependencies);
        target.receipts[mapped(39,item.id)]=row;
    }
    for item in queue { if item.table != 40 { continue; } let old=source.exports[item.id]; var row=old;
        row.function=mapped(30,old.function);
        row.name=mapped(12,old.name);
        row.arg_type=mapped(17,old.arg_type);
        row.result_type=mapped(17,old.result_type);
        row.substitutions=span(32,old.substitutions);
        row.fields=span(18,old.fields);
        row.input_maxima=span(0,old.input_maxima);
        row.abi_digest=bytes(old.abi_digest);
        target.exports[mapped(40,item.id)]=row;
    }
    target.definitions[target_definition].function=mapped(30,original.function);
    return true;
}
