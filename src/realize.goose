// Finite dictionary realization follows admitted calls; shared function bodies
// remain unchanged. Runtime lookup keys are canonical argument schema IDs.
import .model;
import .validate;

struct RealizationInstance { function: u32, substitutions: Span }
struct RealizationMemo { type_id: u32, substitutions: Span, concrete: u32 }
fn realize_dictionaries(b: CoreBuilder, diagnostics: Diagnostic[>..]&) -> bool {
    var active:u32=0; var charges:u64[>..]=[]; for f in b.functions { charges.push(0); }
    var generated_types:u32=0; var generated_terms:u32=0;
    var instances:RealizationInstance[>..] = [];
    var memo:RealizationMemo[>..] = [];
    var pending:u32[>..<] = [];
    let first_type = b.types.len;
    fn tick() { charges[active]++; if charges[active] > LIMIT_VISITS { diagnostics.push(Diagnostic {4017,0,0,0}); return false from realize_dictionaries; } }
    fn rows(span:Span) -> const u32[:] { b.refs[span.start..span.start+span.count] }
    fn replacement(subs:Span, binder:u32) -> u32 {
        for id in rows(subs) { tick(); let sub=b.substitutions[id]; if sub.kind==KIND_TYPE && sub.binder==binder { return sub.value; } }
        return 0;
    }
    fn same_subs(a:Span, z:Span) -> bool {
        if a.count!=z.count { return false; }
        for id in rows(a) { let sub=b.substitutions[id]; if replacement(z,sub.binder)!=sub.value { return false; } } return true;
    }
    recursive fn parameters(ty:u32, out:u32[>..]&, depth:u32) {
        tick(); if depth>64 { diagnostics.push(Diagnostic {4017,0,0,0}); return false from realize_dictionaries; }
        if ty==0 { return; } let t=b.types[ty];
        if t.tag==TY_PARAM { for old in out { if old==t.binder { return; } } out.push(t.binder); return; }
        // Higher-rank Type binders are not runtime arguments to this template.
        if t.tag==TY_FORALL { return; }
        for child in rows(t.children) { parameters(child,out,depth+1); }
        for field in rows(t.fields) { parameters(b.fields[field].type_id,out,depth+1); }
        if t.tag==TY_FN { let ct=b.contracts[t.contract]; parameters(ct.arg,out,depth+1); parameters(ct.result,out,depth+1); }
    }
    fn parameter_ids(ty:u32)->Span { var found:u32[>..]=[]; parameters(ty,found,0); return ref_span(b,found); }
    fn closed(ty:u32)->bool { return parameter_ids(ty).count==0; }
    recursive fn term(id:u32, subs:Span, old_contract:u32, new_contract:u32, depth:u32)->u32 {
        if id==0 { return 0; } tick(); if depth>64 { diagnostics.push(Diagnostic {4017,0,0,0}); return false from realize_dictionaries; }
        let old=b.terms[id]; var next=old;
        next.type_id=shape(old.type_id,subs,depth+1);
        if (old.tag==EXPR_ARG || old.tag==EXPR_RESULT) && old.binder==old_contract { next.binder=new_contract; }
        let mark=pending.len; var changed=next.type_id!=old.type_id || next.binder!=old.binder;
        for index in old.args.count { let child=b.refs[old.args.start+index]; let mapped=term(child,subs,old_contract,new_contract,depth+1); pending.push(mapped); changed=changed || mapped!=child; }
        if !changed { pending.resize(mark); return id; }
        if generated_terms>=LIMIT_TERMS || (b.terms.len as u64+1)*48>LIMIT_ARTIFACT { diagnostics.push(Diagnostic {2032,0,2032,active}); return false from realize_dictionaries; }
        generated_terms++;
        next.args=ref_span(b,pending[mark..]); pending.resize(mark); let result=b.terms.len as u32; b.terms.push(next); return result;
    }
    fn facts(ids:Span, subs:Span, old_contract:u32, new_contract:u32)->Span {
        let mark=pending.len;
        for index in ids.count { let id=b.refs[ids.start+index]; var f=b.facts[id]; f.left=term(f.left,subs,old_contract,new_contract,0); f.right=term(f.right,subs,old_contract,new_contract,0); f.third=term(f.third,subs,old_contract,new_contract,0); let next=b.facts.len as u32; b.facts.push(f); pending.push(next); }
        let result=ref_span(b,pending[mark..]); pending.resize(mark); return result;
    }
    fn premises(ids:Span,subs:Span)->Span {
        let mark=pending.len;
        for i in ids.count { let old=b.layout_premises[b.refs[ids.start+i]]; let ty=shape(old.type_id,subs,0); let id=b.layout_premises.len as u32; b.layout_premises.push(LayoutPremise {ty,old.kind}); pending.push(id); }
        let result=ref_span(b,pending[mark..]); pending.resize(mark); return result;
    }
    recursive fn shape(ty:u32, subs:Span, depth:u32)->u32 {
        tick(); if ty==0 { return 0; }
        if depth>64 { diagnostics.push(Diagnostic {4017,0,0,0}); return false from realize_dictionaries; }
        let old=b.types[ty];
        if old.tag==TY_PARAM { let selected=replacement(subs,old.binder); return if selected==0 {ty} else {selected}; }
        if old.tag==TY_FORALL { return ty; }
        let params=parameter_ids(ty);
        if params.count==0 { return ty; }
        for entry in memo { tick(); if entry.type_id==ty && same_subs(entry.substitutions,subs) { return entry.concrete; } }
        var next=old; let mark=pending.len; var changed=false;
        for index in old.children.count { let child=b.refs[old.children.start+index]; let mapped=shape(child,subs,depth+1); pending.push(mapped); changed=changed || mapped!=child; }
        let children=ref_span(b,pending[mark..]); pending.resize(mark);
        for index in old.fields.count { let id=b.refs[old.fields.start+index]; var field=b.fields[id]; let mapped=shape(field.type_id,subs,depth+1); if mapped==field.type_id { pending.push(id); } else { changed=true; field.type_id=mapped; pending.push(b.fields.len as u32); b.fields.push(field); } }
        let fields=ref_span(b,pending[mark..]); pending.resize(mark);
        if old.tag==TY_FN {
            let ct=b.contracts[old.contract]; var mapped=ct;
            mapped.arg=shape(ct.arg,subs,depth+1); mapped.result=shape(ct.result,subs,depth+1);
            if mapped.arg!=ct.arg || mapped.result!=ct.result {
                changed=true; next.contract=b.contracts.len as u32; b.contracts.push(mapped);
                b.contracts[next.contract].layout_premises=premises(ct.layout_premises,subs);
                b.contracts[next.contract].requires=facts(ct.requires,subs,old.contract,next.contract);
                b.contracts[next.contract].ensures=facts(ct.ensures,subs,old.contract,next.contract);
                b.contracts[next.contract].on_true=facts(ct.on_true,subs,old.contract,next.contract);
                b.contracts[next.contract].on_false=facts(ct.on_false,subs,old.contract,next.contract);
            }
        }
        if !changed { return ty; }
        if generated_types>=LIMIT_TYPES || (b.types.len as u64+1)*64>LIMIT_ARTIFACT { diagnostics.push(Diagnostic {2031,0,2031,active}); return false from realize_dictionaries; }
        generated_types++;
        next.children=children; next.fields=fields;
        let result=b.types.len as u32; b.types.push(next); memo.push(RealizationMemo {ty,subs,result});
        if closed(result) {
            var args:u32[>..]=[]; for binder in rows(params) { let arg=replacement(subs,binder); if arg==0 { return result; } args.push(arg); }
            var exists=false;
            for row in b.dictionary_realizations { tick(); if row.type_id!=ty || row.arguments.count!=args.len { continue; } var same=true; for arg,i in args { if b.refs[row.arguments.start+i]!=arg { same=false; break; } } if same { exists=true; break; } }
            if !exists { b.dictionary_realizations.push(DictionaryRealization {ty,params,ref_span(b,args),result,0}); }
        }
        return result;
    }
    fn add_instance(fid:u32, incoming:Span) {
        let f=b.functions[fid]; var required:u32[>..]=[];
        for bid in rows(b.contracts[f.contract].binders) { if b.binders[bid].kind==KIND_TYPE { required.push(bid); } }
        for eid in rows(f.environment_bindings) { let env=b.environment_bindings[eid]; if env.kind==KIND_TYPE { var seen=false; for bid in required { if bid==env.binder { seen=true; break; } } if !seen { required.push(env.binder); } } }
        var subs:u32[>..]=[];
        for bid in required {
            let selected=replacement(incoming,bid); if selected==0 || !closed(selected) { return; }
            let id=b.substitutions.len as u32; b.substitutions.push(Substitution {bid,KIND_TYPE,selected}); subs.push(id);
        }
        let ids=ref_span(b,subs);
        for previous in instances { tick(); if previous.function==fid && same_subs(previous.substitutions,ids) { return; } }
        if (instances.len as u64)*12>LIMIT_ARTIFACT { diagnostics.push(Diagnostic {4017,0,0,0}); return false from realize_dictionaries; }
        instances.push(RealizationInstance {fid,ids});
    }
    for f,i in b.functions { if i!=0 { active=i as u32; add_instance(i as u32,Span {..}); } }
    for ex,i in b.exports { if i!=0 { active=ex.function; add_instance(ex.function,ex.substitutions); } }
    var cursor:i64=0;
    while cursor<instances.len {
        let instance=instances[cursor]; cursor++; active=instance.function; generated_types=0; generated_terms=0; let f=b.functions[instance.function];
        let obligations=b.contracts[f.contract].layout_premises;
        for pi in obligations.count { let premise=b.layout_premises[b.refs[obligations.start+pi]]; shape(premise.type_id,instance.substitutions,0); }
        shape(b.contracts[f.contract].arg,instance.substitutions,0); shape(b.contracts[f.contract].result,instance.substitutions,0);
        for vid in 1..b.values.len { tick(); let v=b.values[vid]; if v.block_id!=0 && b.blocks[v.block_id].function==instance.function { shape(v.type_id,instance.substitutions,0); } }
        for bi in f.blocks.count { let block_id=b.refs[f.blocks.start+bi]; let operations=b.blocks[block_id].ops; for oi in operations.count { let oid=b.refs[operations.start+oi]; tick();
            let op=b.ops[oid];
            if op.tag==OP_TRY_ALLOC { shape(op.imm0,instance.substitutions,0); }
            if op.tag!=OP_CALL && op.tag!=OP_CLOSURE && op.tag!=OP_FN_PLACE { continue; }
            var incoming:u32[>..]=[];
            for si in op.substitutions.count { let sid=b.refs[op.substitutions.start+si]; let sub=b.substitutions[sid]; if sub.kind!=KIND_TYPE { continue; } let selected=shape(sub.value,instance.substitutions,0); let id=b.substitutions.len as u32; b.substitutions.push(Substitution {sub.binder,KIND_TYPE,selected}); incoming.push(id); }
            // Compiler-owned environment captures inherit the constructing
            // activation's already selected Type witnesses.
            for sid in rows(instance.substitutions) { let sub=b.substitutions[sid]; var seen=false; for old in incoming { if b.substitutions[old].binder==sub.binder { seen=true; break; } } if !seen { incoming.push(sid); } }
            add_instance(op.imm0,ref_span(b,incoming));
        } }
    }
    for ty in first_type..b.types.len { var work=Work {..}; let row,ok=validator::derive_layout(core_view(b),ty as u32,work,diagnostics); if !ok { return false; } b.layouts.push(row); }
    for row,i in b.dictionary_realizations { if i==0 { continue; } for layout,j in b.layouts { if j!=0 && layout.type_id==row.concrete_type { b.dictionary_realizations[i].layout=j as u32; break; } } }
    return true;
}
