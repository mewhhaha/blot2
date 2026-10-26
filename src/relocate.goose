// Generated explicit table relocation; runtime implementation is Goose only.
// External definitions are projections, never copied historical implementations.
namespace relocation;
import src.model;
import src.canonical;
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
    var map_layout_premises:u32[>..]=[]; for row in source.layout_premises { map_layout_premises.push(0); }
    var map_dictionary_realizations:u32[>..]=[]; for row in source.dictionary_realizations { map_dictionary_realizations.push(0); }
    var map_static_relocations:u32[>..]=[]; for row in source.static_relocations { map_static_relocations.push(0); }
    var map_static_objects:u32[>..]=[]; for row in source.static_objects { map_static_objects.push(0); }
    var map_adapter_captures:u32[>..]=[]; for row in source.adapter_captures { map_adapter_captures.push(0); }
    var map_callable_adapters:u32[>..]=[]; for row in source.callable_adapters { map_callable_adapters.push(0); }
    var map_schemas:u32[>..]=[]; for row in source.schemas { map_schemas.push(0); }
    var map_environment_bindings:u32[>..]=[]; for row in source.environment_bindings { map_environment_bindings.push(0); }
    var map_nat_witnesses:u32[>..]=[]; for row in source.nat_witnesses { map_nat_witnesses.push(0); }
    var map_abi_plans:u32[>..]=[]; for row in source.abi_plans { map_abi_plans.push(0); }
    var map_definitions:u32[>..]=[]; for row in source.definitions { map_definitions.push(0); }
    var map_names:u32[>..]=[]; for row in source.names { map_names.push(0); }
    var map_origins:u32[>..]=[]; for row in source.origins { map_origins.push(0); }
    var map_modules:u32[>..]=[]; for row in source.modules { map_modules.push(0); }
    var map_binders:u32[>..]=[]; for row in source.binders { map_binders.push(0); }
    var map_scopes:u32[>..]=[]; for row in source.scopes { map_scopes.push(0); }
    var map_types:u32[>..]=[]; for row in source.types { map_types.push(0); }
    var map_fields:u32[>..]=[]; for row in source.fields { map_fields.push(0); }
    var map_contracts:u32[>..]=[]; for row in source.contracts { map_contracts.push(0); }
    var map_effects:u32[>..]=[]; for row in source.effects { map_effects.push(0); }
    var map_values:u32[>..]=[]; for row in source.values { map_values.push(0); }
    var map_ops:u32[>..]=[]; for row in source.ops { map_ops.push(0); }
    var map_blocks:u32[>..]=[]; for row in source.blocks { map_blocks.push(0); }
    var map_terminators:u32[>..]=[]; for row in source.terminators { map_terminators.push(0); }
    var map_edges:u32[>..]=[]; for row in source.edges { map_edges.push(0); }
    var map_terms:u32[>..]=[]; for row in source.terms { map_terms.push(0); }
    var map_facts:u32[>..]=[]; for row in source.facts { map_facts.push(0); }
    var map_evidence:u32[>..]=[]; for row in source.evidence { map_evidence.push(0); }
    var map_loops:u32[>..]=[]; for row in source.loops { map_loops.push(0); }
    var map_functions:u32[>..]=[]; for row in source.functions { map_functions.push(0); }
    var map_calls:u32[>..]=[]; for row in source.calls { map_calls.push(0); }
    var map_substitutions:u32[>..]=[]; for row in source.substitutions { map_substitutions.push(0); }
    var map_captures:u32[>..]=[]; for row in source.captures { map_captures.push(0); }
    var map_loans:u32[>..]=[]; for row in source.loans { map_loans.push(0); }
    var map_transitions:u32[>..]=[]; for row in source.transitions { map_transitions.push(0); }
    var map_layouts:u32[>..]=[]; for row in source.layouts { map_layouts.push(0); }
    var map_interfaces:u32[>..]=[]; for row in source.interfaces { map_interfaces.push(0); }
    var map_dependencies:u32[>..]=[]; for row in source.dependencies { map_dependencies.push(0); }
    var map_receipts:u32[>..]=[]; for row in source.receipts { map_receipts.push(0); }
    var map_exports:u32[>..]=[]; for row in source.exports { map_exports.push(0); }
    var queue:Ref[>..]=[]; var paired:Pair[>..]=[];
    fn tick() { if !charge(work,1,LIMIT_VISITS) { return false from relocate_function; } }
    fn mapped(table:u32,id:u32) -> u32 {
        if id == 0 || table == 0 { return id; }
        if table == 1 { return map_layout_premises[id]; }
        if table == 2 { return map_dictionary_realizations[id]; }
        if table == 3 { return map_static_relocations[id]; }
        if table == 4 { return map_static_objects[id]; }
        if table == 5 { return map_adapter_captures[id]; }
        if table == 6 { return map_callable_adapters[id]; }
        if table == 7 { return map_schemas[id]; }
        if table == 8 { return map_environment_bindings[id]; }
        if table == 9 { return map_nat_witnesses[id]; }
        if table == 10 { return map_abi_plans[id]; }
        if table == 11 { return map_definitions[id]; }
        if table == 12 { return map_names[id]; }
        if table == 13 { return map_origins[id]; }
        if table == 14 { return map_modules[id]; }
        if table == 15 { return map_binders[id]; }
        if table == 16 { return map_scopes[id]; }
        if table == 17 { return map_types[id]; }
        if table == 18 { return map_fields[id]; }
        if table == 19 { return map_contracts[id]; }
        if table == 20 { return map_effects[id]; }
        if table == 21 { return map_values[id]; }
        if table == 22 { return map_ops[id]; }
        if table == 23 { return map_blocks[id]; }
        if table == 24 { return map_terminators[id]; }
        if table == 25 { return map_edges[id]; }
        if table == 26 { return map_terms[id]; }
        if table == 27 { return map_facts[id]; }
        if table == 28 { return map_evidence[id]; }
        if table == 29 { return map_loops[id]; }
        if table == 30 { return map_functions[id]; }
        if table == 31 { return map_calls[id]; }
        if table == 32 { return map_substitutions[id]; }
        if table == 33 { return map_captures[id]; }
        if table == 34 { return map_loans[id]; }
        if table == 35 { return map_transitions[id]; }
        if table == 36 { return map_layouts[id]; }
        if table == 37 { return map_interfaces[id]; }
        if table == 38 { return map_dependencies[id]; }
        if table == 39 { return map_receipts[id]; }
        if table == 40 { return map_exports[id]; }
        return 0;
    }
    fn assign(table:u32,id:u32,value:u32) {
        if table == 1 { map_layout_premises[id]=value; return; }
        if table == 2 { map_dictionary_realizations[id]=value; return; }
        if table == 3 { map_static_relocations[id]=value; return; }
        if table == 4 { map_static_objects[id]=value; return; }
        if table == 5 { map_adapter_captures[id]=value; return; }
        if table == 6 { map_callable_adapters[id]=value; return; }
        if table == 7 { map_schemas[id]=value; return; }
        if table == 8 { map_environment_bindings[id]=value; return; }
        if table == 9 { map_nat_witnesses[id]=value; return; }
        if table == 10 { map_abi_plans[id]=value; return; }
        if table == 11 { map_definitions[id]=value; return; }
        if table == 12 { map_names[id]=value; return; }
        if table == 13 { map_origins[id]=value; return; }
        if table == 14 { map_modules[id]=value; return; }
        if table == 15 { map_binders[id]=value; return; }
        if table == 16 { map_scopes[id]=value; return; }
        if table == 17 { map_types[id]=value; return; }
        if table == 18 { map_fields[id]=value; return; }
        if table == 19 { map_contracts[id]=value; return; }
        if table == 20 { map_effects[id]=value; return; }
        if table == 21 { map_values[id]=value; return; }
        if table == 22 { map_ops[id]=value; return; }
        if table == 23 { map_blocks[id]=value; return; }
        if table == 24 { map_terminators[id]=value; return; }
        if table == 25 { map_edges[id]=value; return; }
        if table == 26 { map_terms[id]=value; return; }
        if table == 27 { map_facts[id]=value; return; }
        if table == 28 { map_evidence[id]=value; return; }
        if table == 29 { map_loops[id]=value; return; }
        if table == 30 { map_functions[id]=value; return; }
        if table == 31 { map_calls[id]=value; return; }
        if table == 32 { map_substitutions[id]=value; return; }
        if table == 33 { map_captures[id]=value; return; }
        if table == 34 { map_loans[id]=value; return; }
        if table == 35 { map_transitions[id]=value; return; }
        if table == 36 { map_layouts[id]=value; return; }
        if table == 37 { map_interfaces[id]=value; return; }
        if table == 38 { map_dependencies[id]=value; return; }
        if table == 39 { map_receipts[id]=value; return; }
        if table == 40 { map_exports[id]=value; return; }
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
        map_definitions[a]=b; map_modules[x.module]=y.module;
        if a != source_definition { if x.function != 0 { if y.function == 0 { return false from relocate_function; } map_functions[x.function]=y.function; } }
        if x.kind == DEF_STATIC {
            if !id_ok(x.value,source.values.len) || !id_ok(y.value,target.values.len) { return false from relocate_function; }
            let old_op=source.values[x.value].op; let new_op=target.values[y.value].op;
            if old_op == 0 || new_op == 0 || source.ops[old_op].tag != OP_STATIC || target.ops[new_op].tag != OP_STATIC { return false from relocate_function; }
            let a=source.ops[old_op].imm0; let b=target.ops[new_op].imm0; let old_static=source.static_objects[a]; let new_static=target.static_objects[b];
            if old_static.kind != new_static.kind || old_static.count != new_static.count || old_static.relocations.count != 0 || new_static.relocations.count != 0 ||
                source.bytes[old_static.bytes.start..old_static.bytes.start+old_static.bytes.count] != target.bytes[new_static.bytes.start..new_static.bytes.start+new_static.bytes.count] { return false from relocate_function; }
            map_values[x.value]=y.value; map_ops[old_op]=new_op; map_static_objects[a]=b;
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
            for row,index in target.modules { tick(); if index != 0 && path == name_bytes(core_view(target),row.path) { map_modules[id]=index as u32; return; } }
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
                    if map_scopes[scope] == PENDING { mark(28,id as u32); break; }
                    scope=source.scopes[scope].parent;
                }
            }
            for row,id in source.loops { if id != 0 && map_functions[source.blocks[row.header].function] == PENDING { mark(29,id as u32); } }
            for row,id in source.interfaces { if id != 0 && map_functions[row.function] == PENDING { mark(37,id as u32); } }
            for row,id in source.receipts { if id != 0 && row.producer == source_definition { mark(39,id as u32); } }
            for row,id in source.callable_adapters { if id != 0 && map_ops[row.op] == PENDING { mark(6,id as u32); } }
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
    for value,id in map_layout_premises { if value == PENDING { map_layout_premises[id]=target.layout_premises.len as u32; target.layout_premises.push(LayoutPremise {..}); } }
    for value,id in map_dictionary_realizations { if value == PENDING { map_dictionary_realizations[id]=target.dictionary_realizations.len as u32; target.dictionary_realizations.push(DictionaryRealization {..}); } }
    for value,id in map_static_relocations { if value == PENDING { map_static_relocations[id]=target.static_relocations.len as u32; target.static_relocations.push(StaticRelocation {..}); } }
    for value,id in map_static_objects { if value == PENDING { map_static_objects[id]=target.static_objects.len as u32; target.static_objects.push(StaticObject {..}); } }
    for value,id in map_adapter_captures { if value == PENDING { map_adapter_captures[id]=target.adapter_captures.len as u32; target.adapter_captures.push(AdapterCapture {..}); } }
    for value,id in map_callable_adapters { if value == PENDING { map_callable_adapters[id]=target.callable_adapters.len as u32; target.callable_adapters.push(CallableAdapter {..}); } }
    for value,id in map_schemas { if value == PENDING { map_schemas[id]=target.schemas.len as u32; target.schemas.push(Schema {..}); } }
    for value,id in map_environment_bindings { if value == PENDING { map_environment_bindings[id]=target.environment_bindings.len as u32; target.environment_bindings.push(EnvironmentBinding {..}); } }
    for value,id in map_nat_witnesses { if value == PENDING { map_nat_witnesses[id]=target.nat_witnesses.len as u32; target.nat_witnesses.push(NatWitness {..}); } }
    for value,id in map_abi_plans { if value == PENDING { map_abi_plans[id]=target.abi_plans.len as u32; target.abi_plans.push(AbiPlan {..}); } }
    for value,id in map_names { if value == PENDING { map_names[id]=target.names.len as u32; target.names.push(Name {..}); } }
    for value,id in map_origins { if value == PENDING { map_origins[id]=target.origins.len as u32; target.origins.push(Origin {..}); } }
    for value,id in map_binders { if value == PENDING { map_binders[id]=target.binders.len as u32; target.binders.push(Binder {..}); } }
    for value,id in map_scopes { if value == PENDING { map_scopes[id]=target.scopes.len as u32; target.scopes.push(Scope {..}); } }
    for value,id in map_types { if value == PENDING { map_types[id]=target.types.len as u32; target.types.push(TypeNode {..}); } }
    for value,id in map_fields { if value == PENDING { map_fields[id]=target.fields.len as u32; target.fields.push(Field {..}); } }
    for value,id in map_contracts { if value == PENDING { map_contracts[id]=target.contracts.len as u32; target.contracts.push(Contract {..}); } }
    for value,id in map_effects { if value == PENDING { map_effects[id]=target.effects.len as u32; target.effects.push(Effect {..}); } }
    for value,id in map_values { if value == PENDING { map_values[id]=target.values.len as u32; target.values.push(Value {..}); } }
    for value,id in map_ops { if value == PENDING { map_ops[id]=target.ops.len as u32; target.ops.push(Operation {..}); } }
    for value,id in map_blocks { if value == PENDING { map_blocks[id]=target.blocks.len as u32; target.blocks.push(Block {..}); } }
    for value,id in map_terminators { if value == PENDING { map_terminators[id]=target.terminators.len as u32; target.terminators.push(Terminator {..}); } }
    for value,id in map_edges { if value == PENDING { map_edges[id]=target.edges.len as u32; target.edges.push(Edge {..}); } }
    for value,id in map_facts { if value == PENDING { map_facts[id]=target.facts.len as u32; target.facts.push(Fact {..}); } }
    for value,id in map_evidence { if value == PENDING { map_evidence[id]=target.evidence.len as u32; target.evidence.push(Evidence {..}); } }
    for value,id in map_loops { if value == PENDING { map_loops[id]=target.loops.len as u32; target.loops.push(Loop {..}); } }
    for value,id in map_functions { if value == PENDING { map_functions[id]=target.functions.len as u32; target.functions.push(Function {..}); } }
    for value,id in map_calls { if value == PENDING { map_calls[id]=target.calls.len as u32; target.calls.push(Call {..}); } }
    for value,id in map_substitutions { if value == PENDING { map_substitutions[id]=target.substitutions.len as u32; target.substitutions.push(Substitution {..}); } }
    for value,id in map_captures { if value == PENDING { map_captures[id]=target.captures.len as u32; target.captures.push(Capture {..}); } }
    for value,id in map_loans { if value == PENDING { map_loans[id]=target.loans.len as u32; target.loans.push(Loan {..}); } }
    for value,id in map_transitions { if value == PENDING { map_transitions[id]=target.transitions.len as u32; target.transitions.push(Transition {..}); } }
    for value,id in map_layouts { if value == PENDING { map_layouts[id]=target.layouts.len as u32; target.layouts.push(Layout {..}); } }
    for value,id in map_interfaces { if value == PENDING { map_interfaces[id]=target.interfaces.len as u32; target.interfaces.push(Interface {..}); } }
    for value,id in map_dependencies { if value == PENDING { map_dependencies[id]=target.dependencies.len as u32; target.dependencies.push(Dependency {..}); } }
    for value,id in map_receipts { if value == PENDING { map_receipts[id]=target.receipts.len as u32; target.receipts.push(Receipt {..}); } }
    for value,id in map_exports { if value == PENDING { map_exports[id]=target.exports.len as u32; target.exports.push(Export {..}); } }
    fn span(table:u32,old:Span) -> Span {
        let result=Span {start:target.refs.len as u32,count:old.count};
        for i in old.count { target.refs.push(mapped(table,source.refs[old.start+i])); } return result;
    }
    fn bytes(old:Span) -> Span {
        let result=Span {start:target.bytes.len as u32,count:old.count}; target.bytes.append(source.bytes[old.start..old.start+old.count]); return result;
    }
    for old,id in source.terms {
        if id == 0 || map_terms[id] != PENDING { continue; }
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
        map_terms[id]=existing;
    }
    for item in queue { if item.table != 1 { continue; } let old=source.layout_premises[item.id]; var row=old;
        row.type_id=mapped(17,old.type_id);
        target.layout_premises[map_layout_premises[item.id]]=row;
    }
    for item in queue { if item.table != 2 { continue; } let old=source.dictionary_realizations[item.id]; var row=old;
        row.type_id=mapped(17,old.type_id);
        row.parameters=span(15,old.parameters);
        row.arguments=span(17,old.arguments);
        row.concrete_type=mapped(17,old.concrete_type);
        row.layout=mapped(36,old.layout);
        target.dictionary_realizations[map_dictionary_realizations[item.id]]=row;
    }
    for item in queue { if item.table != 3 { continue; } let old=source.static_relocations[item.id]; var row=old;
        row.target=mapped((if row.kind == STATIC_ADDRESS { 4 } else if row.kind == STATIC_FUNCTION { 30 } else if row.kind == STATIC_DICTIONARY { 17 } else { 22 }),old.target);
        row.addend=mapped((if row.kind == STATIC_CLOSURE { 4 } else { 0 }),old.addend);
        target.static_relocations[map_static_relocations[item.id]]=row;
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
        target.static_objects[map_static_objects[item.id]]=row;
    }
    for item in queue { if item.table != 5 { continue; } let old=source.adapter_captures[item.id]; var row=old;
        row.source=mapped((if row.kind == KIND_TYPE { 17 } else { 26 }),old.source);
        target.adapter_captures[map_adapter_captures[item.id]]=row;
    }
    for item in queue { if item.table != 6 { continue; } let old=source.callable_adapters[item.id]; var row=old;
        row.op=mapped(22,old.op);
        row.target_function=mapped(30,old.target_function);
        row.callback_contract=mapped(19,old.callback_contract);
        row.captures=span(5,old.captures);
        row.environment_layout=mapped(36,old.environment_layout);
        target.callable_adapters[map_callable_adapters[item.id]]=row;
    }
    for item in queue { if item.table != 7 { continue; } let old=source.schemas[item.id]; var row=old;
        row.bytes=bytes(old.bytes);
        row.digest=bytes(old.digest);
        target.schemas[map_schemas[item.id]]=row;
    }
    for item in queue { if item.table != 8 { continue; } let old=source.environment_bindings[item.id]; var row=old;
        row.function=mapped(30,old.function);
        row.binder=mapped(15,old.binder);
        row.source_value=mapped(21,old.source_value);
        target.environment_bindings[map_environment_bindings[item.id]]=row;
    }
    for item in queue { if item.table != 9 { continue; } let old=source.nat_witnesses[item.id]; var row=old;
        row.binder=mapped(15,old.binder);
        row.argument_path=span(0,old.argument_path);
        target.nat_witnesses[map_nat_witnesses[item.id]]=row;
    }
    for item in queue { if item.table != 10 { continue; } let old=source.abi_plans[item.id]; var row=old;
        row.contract=mapped(19,old.contract);
        row.function=mapped(30,old.function);
        row.arg_layout=mapped(36,old.arg_layout);
        row.result_layout=mapped(36,old.result_layout);
        row.env_layout=mapped(36,old.env_layout);
        row.dictionaries=span(15,old.dictionaries);
        row.nat_witnesses=span(9,old.nat_witnesses);
        target.abi_plans[map_abi_plans[item.id]]=row;
    }
    for item in queue { if item.table != 12 { continue; } let old=source.names[item.id]; var row=old;
        row.bytes=bytes(old.bytes);
        target.names[map_names[item.id]]=row;
    }
    for item in queue { if item.table != 13 { continue; } let old=source.origins[item.id]; var row=old;
        row.module=mapped(14,old.module);
        row.start=old.start-source.origins[original.origin].start+target.origins[replacement.origin].start;
        row.end=old.end-source.origins[original.origin].start+target.origins[replacement.origin].start;
        target.origins[map_origins[item.id]]=row;
    }
    for item in queue { if item.table != 15 { continue; } let old=source.binders[item.id]; var row=old;
        row.scope=mapped(16,old.scope);
        row.introduction=mapped((if row.introduction_kind == INTRO_FUNCTION { 30 } else if row.introduction_kind == INTRO_OPERATION { 22 } else { 0 }),old.introduction);
        row.name=mapped(12,old.name);
        row.origin=mapped(13,old.origin);
        target.binders[map_binders[item.id]]=row;
    }
    for item in queue { if item.table != 16 { continue; } let old=source.scopes[item.id]; var row=old;
        row.parent=mapped(16,old.parent);
        row.binder=mapped(15,old.binder);
        row.origin=mapped(13,old.origin);
        target.scopes[map_scopes[item.id]]=row;
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
        target.types[map_types[item.id]]=row;
    }
    for item in queue { if item.table != 18 { continue; } let old=source.fields[item.id]; var row=old;
        row.name=mapped(12,old.name);
        row.type_id=mapped(17,old.type_id);
        target.fields[map_fields[item.id]]=row;
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
        target.contracts[map_contracts[item.id]]=row;
    }
    for item in queue { if item.table != 20 { continue; } let old=source.effects[item.id]; var row=old;
        row.region=mapped(15,old.region);
        target.effects[map_effects[item.id]]=row;
    }
    for item in queue { if item.table != 21 { continue; } let old=source.values[item.id]; var row=old;
        row.type_id=mapped(17,old.type_id);
        row.block_id=mapped(23,old.block_id);
        row.op=mapped(22,old.op);
        row.scope=mapped(16,old.scope);
        row.origin=mapped(13,old.origin);
        target.values[map_values[item.id]]=row;
    }
    for item in queue { if item.table != 22 { continue; } let old=source.ops[item.id]; var row=old;
        row.args=span(21,old.args);
        row.results=span(21,old.results);
        row.evidence=span(28,old.evidence);
        row.substitutions=span(32,old.substitutions);
        row.scope=mapped(16,old.scope);
        row.origin=mapped(13,old.origin);
        row.imm0=mapped(operation_reference(row.tag),old.imm0);
        target.ops[map_ops[item.id]]=row;
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
        target.blocks[map_blocks[item.id]]=row;
    }
    for item in queue { if item.table != 24 { continue; } let old=source.terminators[item.id]; var row=old;
        row.evidence=span(28,old.evidence);
        row.subject=mapped(21,old.subject);
        row.edges=span(25,old.edges);
        row.discharge=span(21,old.discharge);
        row.origin=mapped(13,old.origin);
        target.terminators[map_terminators[item.id]]=row;
    }
    for item in queue { if item.table != 25 { continue; } let old=source.edges[item.id]; var row=old;
        row.from=mapped(23,old.from);
        row.to=mapped(23,old.to);
        row.args=span(21,old.args);
        row.evidence=span(28,old.evidence);
        row.loop_id=mapped(29,old.loop_id);
        target.edges[map_edges[item.id]]=row;
    }
    for item in queue { if item.table != 27 { continue; } let old=source.facts[item.id]; var row=old;
        row.left=mapped(26,old.left);
        row.right=mapped(26,old.right);
        row.third=mapped(26,old.third);
        row.domain=mapped(15,old.domain);
        target.facts[map_facts[item.id]]=row;
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
        target.evidence[map_evidence[item.id]]=row;
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
        target.loops[map_loops[item.id]]=row;
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
        target.functions[map_functions[item.id]]=row;
    }
    for item in queue { if item.table != 31 { continue; } let old=source.calls[item.id]; var row=old;
        row.op=mapped(22,old.op);
        row.caller=mapped(30,old.caller);
        row.callee=mapped(30,old.callee);
        row.contract=mapped(19,old.contract);
        row.substitutions=span(32,old.substitutions);
        target.calls[map_calls[item.id]]=row;
    }
    for item in queue { if item.table != 32 { continue; } let old=source.substitutions[item.id]; var row=old;
        row.binder=mapped(15,old.binder);
        row.value=mapped((if row.kind == KIND_TYPE { 17 } else if row.kind == KIND_NAT { 26 } else { 15 }),old.value);
        target.substitutions[map_substitutions[item.id]]=row;
    }
    for item in queue { if item.table != 33 { continue; } let old=source.captures[item.id]; var row=old;
        row.function=mapped(30,old.function);
        row.value=mapped(21,old.value);
        row.local_value=mapped(21,old.local_value);
        row.scope=mapped(16,old.scope);
        target.captures[map_captures[item.id]]=row;
    }
    for item in queue { if item.table != 34 { continue; } let old=source.loans[item.id]; var row=old;
        row.value=mapped(21,old.value);
        row.owner=mapped(21,old.owner);
        row.scope=mapped(16,old.scope);
        row.begin_op=mapped(22,old.begin_op);
        row.end_op=mapped(22,old.end_op);
        target.loans[map_loans[item.id]]=row;
    }
    for item in queue { if item.table != 35 { continue; } let old=source.transitions[item.id]; var row=old;
        row.op=mapped(22,old.op);
        row.value=mapped(21,old.value);
        row.before=mapped(21,old.before);
        row.after=mapped(21,old.after);
        row.scope=mapped(16,old.scope);
        target.transitions[map_transitions[item.id]]=row;
    }
    for item in queue { if item.table != 36 { continue; } let old=source.layouts[item.id]; var row=old;
        row.type_id=mapped(17,old.type_id);
        row.schema=mapped(7,old.schema);
        row.fields=span(18,old.fields);
        target.layouts[map_layouts[item.id]]=row;
    }
    for item in queue { if item.table != 37 { continue; } let old=source.interfaces[item.id]; var row=old;
        row.abi_digest=bytes(old.abi_digest);
        row.function=mapped(30,old.function);
        row.type_id=mapped(17,old.type_id);
        row.contract=mapped(19,old.contract);
        row.dependencies=span(38,old.dependencies);
        row.digest=bytes(old.digest);
        row.producer=mapped(11,old.producer);
        target.interfaces[map_interfaces[item.id]]=row;
    }
    for item in queue { if item.table != 38 { continue; } let old=source.dependencies[item.id]; var row=old;
        row.producer=mapped(11,old.producer);
        row.identity=bytes(old.identity);
        row.digest=bytes(old.digest);
        target.dependencies[map_dependencies[item.id]]=row;
    }
    for item in queue { if item.table != 39 { continue; } let old=source.receipts[item.id]; var row=old;
        row.producer=mapped(11,old.producer);
        row.source_digest=bytes(old.source_digest);
        row.semantic_digest=bytes(old.semantic_digest);
        row.dependencies=span(38,old.dependencies);
        target.receipts[map_receipts[item.id]]=row;
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
        target.exports[map_exports[item.id]]=row;
    }
    target.definitions[target_definition].function=map_functions[original.function];
    return true;
}
