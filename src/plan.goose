// Deterministic lowering plans; this phase never invokes source completion.
import .model;
import .validate;
import .wasm;
import .loader;
import .realize;
import .layout_premises;

fn layout_id(c: Core, type_id: u32) -> u32 {
    for row, i in c.layouts { if i != 0 && row.type_id == type_id { return i as u32; } }
    return 0;
}
fn abi_plan_id(c: Core, function_id: u32) -> u32 {
    for row, i in c.abi_plans { if i != 0 && row.function == function_id { return i as u32; } }
    return 0;
}
fn terminal_type(c: Core, type_id: u32) -> u32 {
    var id = type_id;
    for step in 65 {
        if !id_ok(id, c.types.len) { return 0; }
        let t = c.types[id];
        if t.tag != TY_ALIAS && t.tag != TY_FORALL { return id; }
        if t.children.count != 1 || !span_ok(t.children, c.refs.len) { return 0; }
        id = c.refs[t.children.start];
    }
    return 0;
}
fn term_binder(c: Core, term_id: u32) -> u32 {
    if id_ok(term_id, c.terms.len) && c.terms[term_id].tag == EXPR_BINDER { return c.terms[term_id].binder; }
    return 0;
}
recursive fn find_nat_source(b: CoreBuilder, type_id: u32, binder: u32, path: u32[>..<]&, depth: u32) -> NatWitness, bool {
    if depth > 64 { return NatWitness { .. }, false; }
    let c = core_view(b); let id = terminal_type(c, type_id);
    if id == 0 { return NatWitness { .. }, false; }
    let t = c.types[id];
    var selector: u32 = NAT_HIDDEN;
    if term_binder(c, t.nat) == binder {
        if t.tag == TY_VIEW { selector = NAT_VIEW_LEN; }
        if t.tag == TY_BUILDER { selector = NAT_BUILDER_INIT; }
    }
    if term_binder(c, t.capacity) == binder {
        if t.tag == TY_DEST { selector = NAT_DEST_CAP; }
        if t.tag == TY_BUILDER { selector = NAT_BUILDER_CAP; }
    }
    if selector != NAT_HIDDEN {
        return NatWitness { binder: binder, argument_path: ref_span(b, path), selector: selector, prefix_index: 0 }, true;
    }
    // Only a guaranteed-present product field can designate a witness. A sum
    // payload is conditional, so it cannot silently remove a hidden parameter.
    if t.tag == TY_RECORD || t.tag == TY_TUPLE {
        let count = if t.tag == TY_RECORD { t.fields.count } else { t.children.count };
        for i in count {
            let child = if t.tag == TY_RECORD { c.fields[c.refs[t.fields.start + i]].type_id } else { c.refs[t.children.start + i] };
            path.push(i as u32);
            let witness, found = find_nat_source(b, child, binder, path, depth + 1);
            path.pop();
            if found { return witness, true; }
        }
    }
    return NatWitness { binder: binder, selector: NAT_HIDDEN, .. }, false;
}
recursive fn plan_resources(b: CoreBuilder, function_id: u32, colors: u32[:], diagnostics: Diagnostic[>..]&, depth: u32) -> bool {
    if depth > 128 || colors[function_id] == 1 { return loader_error(diagnostics, 4013, b.functions[function_id].origin); }
    if colors[function_id] == 2 { return true; }
    colors[function_id] = 1;
    let f = b.functions[function_id];
    let own, own_ok = wasm_own_frame(core_view(b), function_id);
    if !own_ok { return loader_error(diagnostics, 4012, f.origin); }
    var callee_frame: u32 = 0; var callee_depth: u32 = 0;
    for i in f.blocks.count {
        let block_id = b.refs[f.blocks.start + i]; let block_row = b.blocks[block_id];
        for j in block_row.ops.count {
            let op = b.ops[b.refs[block_row.ops.start + j]];
            var contract_id: u32 = 0;
            if op.tag == OP_CLOSURE || op.tag == OP_FN_PLACE {
                // Constructing a callable needs its complete interface, without
                // charging its invocation resources as a call at this site.
                if id_ok(op.imm0,b.functions.len) && b.functions[op.imm0].evaluator_only { return loader_error(diagnostics,4013,op.origin); }
                if !id_ok(op.imm0, b.functions.len) || !plan_resources(b, op.imm0, colors, diagnostics, depth + 1) { return false; }
                if op.substitutions.count != 0 {
                    let target = b.contracts[b.functions[op.imm0].contract];
                    let result = b.values[b.refs[op.results.start]];
                    let callback = b.types[terminal_type(core_view(b), result.type_id)].contract;
                    var extra:u32 = 0;
                    let argument = b.layouts[layout_id(core_view(b),b.contracts[callback].arg)];
                    let output = b.layouts[layout_id(core_view(b),b.contracts[callback].result)];
                    if b.layouts[layout_id(core_view(b),target.arg)].abi == ABI_INDIRECT && (argument.abi == ABI_I32 || argument.abi == ABI_F32 || b.types[terminal_type(core_view(b),b.contracts[callback].arg)].tag==TY_PARAM) { extra += 4; }
                    if b.layouts[layout_id(core_view(b),target.result)].abi == ABI_INDIRECT && (output.abi == ABI_I32 || output.abi == ABI_F32 || b.types[terminal_type(core_view(b),b.contracts[callback].result)].tag==TY_PARAM) { extra += 4; }
                    if target.depth >= 128 || target.frame > 16777216-extra { return loader_error(diagnostics,4013,op.origin); }
                    if b.contracts[callback].depth == 0 { b.contracts[callback].depth = target.depth+1; b.contracts[callback].frame = target.frame+extra; }
                }
            }
            if op.tag == OP_CALL {
                if !id_ok(op.imm0, b.functions.len) || (!f.evaluator_only && b.functions[op.imm0].evaluator_only) { return loader_error(diagnostics, 4013, op.origin); }
                if !plan_resources(b, op.imm0, colors, diagnostics, depth + 1) { return false; }
                contract_id = b.functions[op.imm0].contract;
            } else if op.tag == OP_CALL_INDIRECT {
                if op.args.count != 2 { return loader_error(diagnostics, 4013, op.origin); }
                let callee = b.values[b.refs[op.args.start]];
                let type_id = terminal_type(core_view(b), callee.type_id);
                if type_id == 0 { return loader_error(diagnostics, 4013, op.origin); }
                contract_id = b.types[type_id].contract;
            }
            if op.tag == OP_RESERVE || op.tag == OP_TRY_ALLOC || op.tag == OP_ENV_TRY_ALLOC ||
                op.tag == OP_REGION_CLOSE || op.tag == OP_REGION_RESET || op.tag == OP_OWNED_BEGIN ||
                op.tag == OP_OWNED_SEAL || op.tag == OP_OWNED_ABORT || op.tag == OP_OWNED_OPEN || op.tag == OP_OWNED_CLOSE {
                callee_depth = max(callee_depth, 2);
            }
            if contract_id != 0 {
                if b.contracts[contract_id].depth == 0 {
                    var target:u32 = 0;
                    for callee, fi in b.functions { if fi != 0 && callee.contract == contract_id { target = fi as u32; break; } }
                    if target == 0 || !plan_resources(b, target, colors, diagnostics, depth + 1) { return loader_error(diagnostics, 4013, op.origin); }
                }
                let ct = b.contracts[contract_id];
                callee_frame = max(callee_frame, ct.frame); callee_depth = max(callee_depth, ct.depth);
            }
        }
    }
    if (callee_depth >= 128 && !f.evaluator_only) || own > 16777216 || callee_frame > 16777216 - own { return loader_error(diagnostics, 4013, f.origin); }
    var required_depth = if f.evaluator_only {max(callee_depth,1)} else {callee_depth+1};
    var required_frame = if f.evaluator_only {callee_frame} else {own+callee_frame};
    let ct = b.contracts[f.contract];
    // A closure whose ambient Type parameters choose scalar/indirect ABI classes
    // promises room for its fixed concrete adapter as well as the shared body.
    if ct.binders.count==0 && !wasm::closed_dictionary(core_view(b),f.type_id,0) {
        var spills:u32=0;
        if !wasm::closed_dictionary(core_view(b),ct.arg,0) && b.types[terminal_type(core_view(b),ct.arg)].tag==TY_PARAM { spills+=4; }
        if !wasm::closed_dictionary(core_view(b),ct.result,0) && b.types[terminal_type(core_view(b),ct.result)].tag==TY_PARAM { spills+=4; }
        required_depth++; required_frame+=spills;
        if required_depth>128 || required_frame>16777216 { return loader_error(diagnostics,4013,f.origin); }
    }
    if ct.depth == 0 {
        b.contracts[f.contract].depth = required_depth;
        b.contracts[f.contract].frame = required_frame;
    } else if ct.depth < required_depth || ct.frame < required_frame {
        return loader_error(diagnostics, 4013, f.origin);
    }
    let pi = abi_plan_id(core_view(b), function_id);
    b.abi_plans[pi].depth = b.contracts[f.contract].depth;
    b.abi_plans[pi].frame = b.contracts[f.contract].frame;
    colors[function_id] = 2; return true;
}
fn complete_static_resources(b:CoreBuilder,diagnostics:Diagnostic[>..]&)->bool {
    recursive fn value(object:StaticObject,type_id:u32,offset:u32,depth:u32) {
        if depth>64 { diagnostics.push(Diagnostic {4013,0,type_id,0}); return false from complete_static_resources; }
        let id=terminal_type(core_view(b),type_id); let ty=b.types[id];
        if ty.tag==TY_FN {
            if b.contracts[ty.contract].depth!=0 { return; }
            var source:u32=0;
            for ri in object.relocations.count {
                let rel=b.static_relocations[b.refs[object.relocations.start+ri]]; if rel.offset!=offset { continue; }
                if rel.kind==STATIC_FUNCTION { source=b.functions[rel.target].contract; }
                if rel.kind==STATIC_CLOSURE { let op=b.ops[rel.target]; let result=b.values[b.refs[op.results.start]].type_id; source=b.types[terminal_type(core_view(b),result)].contract; }
            }
            if source==0 || b.contracts[source].depth==0 { diagnostics.push(Diagnostic {4013,0,ty.contract,0}); return false from complete_static_resources; }
            b.contracts[ty.contract].depth=b.contracts[source].depth; b.contracts[ty.contract].frame=b.contracts[source].frame; return;
        }
        if ty.tag==TY_TUPLE || ty.tag==TY_RECORD {
            var field_offset=offset; let count=if ty.fields.count!=0 {ty.fields.count} else {ty.children.count};
            for i in count {
                let child=if ty.fields.count!=0 {b.fields[b.refs[ty.fields.start+i]].type_id} else {b.refs[ty.children.start+i]};
                value(object,child,field_offset,depth+1); let layout=layout_id(core_view(b),child);
                if layout==0 { diagnostics.push(Diagnostic {4013,0,child,0}); return false from complete_static_resources; } field_offset+=b.layouts[layout].size;
            }
        } else if ty.tag==TY_SUM || ty.tag==TY_RESULT {
            if offset>object.bytes.count || 4>object.bytes.count-offset { diagnostics.push(Diagnostic {4013,0,id,0}); return false from complete_static_resources; }
            var tag:u32=0; for i in 4 { tag|=(b.bytes[object.bytes.start+offset+i] as u32)<<(i*8); }
            let count=if ty.fields.count!=0 {ty.fields.count} else {ty.children.count}; if tag>=count { diagnostics.push(Diagnostic {4013,0,id,0}); return false from complete_static_resources; }
            let child=if ty.fields.count!=0 {b.fields[b.refs[ty.fields.start+tag]].type_id} else {b.refs[ty.children.start+tag]}; value(object,child,offset+4,depth+1);
        } else if ty.tag==TY_EXISTS {
            var prefix:u32=0; for i in ty.binders.count { if b.binders[b.refs[ty.binders.start+i]].kind==KIND_NAT { prefix+=4; } }
            value(object,b.refs[ty.children.start],offset+prefix,depth+1);
        }
    }
    for object,i in b.static_objects { if i!=0 && object.kind!=STATIC_ARRAY { value(object,object.type_id,0,0); } }
    return true;
}
fn scalar_export_type(c: Core, type_id: u32) -> bool {
    let id = terminal_type(c, type_id); if id == 0 { return false; }
    let t = c.types[id].tag; t == TY_UNIT || t == TY_U32 || t == TY_BOOL || t == TY_F32
}
fn build_plans(b: CoreBuilder, requested_export: const u8[:], diagnostics: Diagnostic[>..]&) -> bool {
    // Environment types are explicit layouts; no later codegen inference.
    var env_types:u32[>..] = [0];
    var unit_type:u32 = 0;
    for t, i in b.types { if i != 0 && t.tag == TY_UNIT { unit_type = i as u32; break; } }
    if unit_type == 0 { unit_type = b.types.len as u32; b.types.push(TypeNode { tag: TY_UNIT, .. }); }
    for f, index in b.functions {
        if index == 0 { continue; }
        var children:u32[>..] = [];
        if f.environment_bindings.count != 0 {
            var u32_type:u32 = 0;
            for t, i in b.types { if i != 0 && t.tag == TY_U32 { u32_type = i as u32; break; } }
            if u32_type == 0 { u32_type = b.types.len as u32; b.types.push(TypeNode { tag: TY_U32, .. }); }
            for i in f.environment_bindings.count {
                let id = b.refs[f.environment_bindings.start + i];
                b.environment_bindings[id].offset = i * 4;
                children.push(u32_type);
            }
        }
        for i in f.captures.count {
            let capture = b.captures[b.refs[f.captures.start + i]];
            children.push(b.values[capture.value].type_id);
        }
        if children.len == 0 { env_types.push(unit_type); }
        else {
            let id = b.types.len as u32;
            b.types.push(TypeNode { tag: TY_TUPLE, children: ref_span(b, children), .. }); env_types.push(id);
        }
    }
    var adapter_env_types:u32[>..] = [0];
    for adapter, i in b.callable_adapters {
        if i == 0 { continue; }
        var children:u32[>..] = [];
        var u32_type:u32 = 0;
        for t, ti in b.types { if ti != 0 && t.tag == TY_U32 { u32_type = ti as u32; break; } }
        if u32_type == 0 { u32_type = b.types.len as u32; b.types.push(TypeNode {tag:TY_U32,..}); }
        for cid in wasm::refs(core_view(b),adapter.captures) { children.push(u32_type); }
        b.callable_adapters[i].target_environment_offset=adapter.captures.count*4;
        let target_env=env_types[adapter.target_function];
        if b.types[target_env].tag!=TY_UNIT { children.push(target_env); }
        if children.len == 0 { adapter_env_types.push(unit_type); }
        else { let id = b.types.len as u32; b.types.push(TypeNode {tag:TY_TUPLE,children:ref_span(b,children),..}); adapter_env_types.push(id); }
    }
    if !build_layout_premises(b,env_types,adapter_env_types,diagnostics) { return false; }
    let type_count = b.types.len;
    for i in 1..type_count {
        if validator::type_is_template(core_view(b),i as u32,0) { continue; }
        var work = Work { .. };
        let layout, ok = validator::derive_layout(core_view(b), i as u32, work, diagnostics);
        if !ok { return false; }
        b.layouts.push(layout);
    }
    for ty, i in adapter_env_types { if i != 0 { b.callable_adapters[i].environment_layout = layout_id(core_view(b),ty); } }
    for f, index in b.functions {
        if index == 0 { continue; }
        let ct = b.contracts[f.contract];
        var dictionaries:u32[>..] = []; var witnesses:u32[>..] = [];
        for i in ct.binders.count {
            let binder_id = b.refs[ct.binders.start + i]; let binder = b.binders[binder_id];
            if binder.kind == KIND_TYPE { dictionaries.push(binder_id); }
            if binder.kind == KIND_NAT {
                var path:u32[>..<] = [];
                let witness, found = find_nat_source(b, ct.arg, binder_id, path, 0);
                let id = b.nat_witnesses.len as u32; b.nat_witnesses.push(witness); witnesses.push(id);
            }
        }
        b.abi_plans.push(AbiPlan { contract: f.contract, function: index as u32,
            arg_layout: layout_id(core_view(b), ct.arg), result_layout: layout_id(core_view(b), ct.result),
            env_layout: layout_id(core_view(b), env_types[index]), dictionaries: ref_span(b, dictionaries),
            nat_witnesses: ref_span(b, witnesses), frame: ct.frame, depth: ct.depth, version: ABI_VERSION });
    }
    // Complete callable interfaces have their own canonical ABI even when no
    // named declaration has that exact contract (higher-order parameters).
    for ct, contract_id in b.contracts {
        if contract_id == 0 || layout_id(core_view(b),ct.arg)==0 || layout_id(core_view(b),ct.result)==0 { continue; }
        var exists = false;
        for p in b.abi_plans { if p.contract == contract_id { exists = true; break; } }
        if exists { continue; }
        var dictionaries:u32[>..] = []; var witnesses:u32[>..] = [];
        for i in ct.binders.count {
            let binder_id = b.refs[ct.binders.start + i]; let binder = b.binders[binder_id];
            if binder.kind == KIND_TYPE { dictionaries.push(binder_id); }
            if binder.kind == KIND_NAT {
                var path:u32[>..<] = [];
                let witness, found = find_nat_source(b, ct.arg, binder_id, path, 0);
                let id = b.nat_witnesses.len as u32; b.nat_witnesses.push(witness); witnesses.push(id);
            }
        }
        b.abi_plans.push(AbiPlan { contract: contract_id as u32, function: 0,
            arg_layout: layout_id(core_view(b), ct.arg), result_layout: layout_id(core_view(b), ct.result),
            env_layout: layout_id(core_view(b), unit_type), dictionaries: ref_span(b, dictionaries),
            nat_witnesses: ref_span(b, witnesses), frame: ct.frame, depth: ct.depth, version: ABI_VERSION });
    }
    var colors:u32[>..] = []; for i in b.functions.len { colors.push(0); }
    for i in 1..b.functions.len { if !plan_resources(b, i as u32, colors, diagnostics, 0) { return false; } }
    if !complete_static_resources(b,diagnostics) { return false; }
    if !realize_dictionaries(b,diagnostics) { return false; }
    for ct, cid in b.contracts {
        if cid == 0 || layout_id(core_view(b),ct.arg)==0 || layout_id(core_view(b),ct.result)==0 { continue; }
        var found=false; for p in b.abi_plans { if p.contract==cid { found=true; break; } }
        if !found { b.abi_plans.push(AbiPlan {contract:cid as u32,arg_layout:layout_id(core_view(b),ct.arg),result_layout:layout_id(core_view(b),ct.result),env_layout:layout_id(core_view(b),unit_type),frame:ct.frame,depth:ct.depth,version:ABI_VERSION,..}); }
    }
    for plan, i in b.abi_plans {
        if i != 0 { b.abi_plans[i].frame = b.contracts[plan.contract].frame; b.abi_plans[i].depth = b.contracts[plan.contract].depth; }
    }
    var matched = requested_export.len == 0;
    for f, index in b.functions {
        if index == 0 || f.evaluator_only || f.module != 1 || f.visibility != VIS_PUBLIC { continue; }
        let name = name_bytes(core_view(b), f.name);
        if requested_export.len != 0 && name != requested_export { continue; }
        let ct = b.contracts[f.contract];
        let eligible = f.captures.count == 0 && ct.binders.count == 0 &&
            scalar_export_type(core_view(b), ct.arg) && scalar_export_type(core_view(b), ct.result);
        if !eligible {
            if requested_export.len != 0 { return loader_error(diagnostics, 4007, f.origin); }
            continue;
        }
        matched = true;
        let id = b.exports.len as u32;
        b.functions[index].export_id = id;
        b.exports.push(Export { function: index as u32, name: f.name, kind: EXPORT_SCALAR, arg_type: ct.arg, result_type: ct.result, frame: ct.frame, depth: ct.depth + 1, .. });
    }
    if !matched { return loader_error(diagnostics, 4007, 0); }
    let abi_digest = Span { start: b.bytes.len as u32, count: 32 };
    b.bytes.append(ABI_HASH);
    for i in 1..b.interfaces.len { b.interfaces[i].abi_digest = abi_digest; }
    for i in 1..b.exports.len { b.exports[i].abi_digest = abi_digest; }
    return true;
}
