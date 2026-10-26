// Mechanically derived bounded layout expressions, independent of source syntax.
import .model;
fn layout_child(c:Core,t:TypeNode,i:u32)->u32 { if t.fields.count!=0 { return c.fields[c.refs[t.fields.start+i]].type_id; } return c.refs[t.children.start+i]; }
fn layout_count(t:TypeNode)->u32 { if t.fields.count!=0 { return t.fields.count; } return t.children.count; }
recursive fn layout_dependent(c:Core,ty:u32,depth:u32,work:Work&,limit:u64)->bool {
    if !charge(work,1,limit) || depth>LIMIT_NEST { return false; } let t=c.types[ty];
    if t.tag==TY_PARAM { return true; }
    if t.tag!=TY_TUPLE && t.tag!=TY_RECORD && t.tag!=TY_SUM && t.tag!=TY_RESULT && t.tag!=TY_EXISTS && t.tag!=TY_ALIAS && t.tag!=TY_FORALL { return false; }
    for i in layout_count(t) { if layout_dependent(c,layout_child(c,t,i),depth+1,work,limit) { return true; } }
    return false;
}
recursive fn layout_shape(c:Core,a:u32,b:u32,subs:Span,depth:u32,work:Work&,limit:u64)->bool {
    if !charge(work,1,limit) || depth>LIMIT_NEST { return false; } let x=c.types[a]; let y=c.types[b];
    if x.tag==TY_ALIAS || x.tag==TY_FORALL { return layout_shape(c,layout_child(c,x,0),b,subs,depth+1,work,limit); }
    if y.tag==TY_ALIAS || y.tag==TY_FORALL { return layout_shape(c,a,layout_child(c,y,0),subs,depth+1,work,limit); }
    if x.tag==TY_PARAM {
        for i in subs.count { if !charge(work,1,limit) { return false; } let sub=c.substitutions[c.refs[subs.start+i]]; if sub.kind==KIND_TYPE && sub.binder==x.binder { return layout_shape(c,sub.value,b,Span{..},depth+1,work,limit); } }
        return y.tag==TY_PARAM && x.binder==y.binder;
    }
    if x.tag!=y.tag { return false; }
    if x.tag==TY_FN || x.tag==TY_VIEW || x.tag==TY_DEST || x.tag==TY_ENV_DEST || x.tag==TY_BUILDER || x.tag==TY_OWNED || x.tag==TY_OWNED_CONSTRUCTION || x.tag==TY_REGION_OWNER || x.tag==TY_SPACE || x.tag==TY_INDEX { return true; }
    if layout_count(x)!=layout_count(y) { return false; }
    if x.tag==TY_EXISTS {
        var nx:u32=0; var ny:u32=0;
        for i in x.binders.count { if c.binders[c.refs[x.binders.start+i]].kind==KIND_NAT { nx++; } }
        for i in y.binders.count { if c.binders[c.refs[y.binders.start+i]].kind==KIND_NAT { ny++; } }
        if nx!=ny { return false; }
    }
    for i in layout_count(x) { if !layout_shape(c,layout_child(c,x,i),layout_child(c,y,i),subs,depth+1,work,limit) { return false; } }
    return true;
}
fn layout_premise_has(c:Core,span:Span,type_id:u32,kind:u32,subs:Span,work:Work&,limit:u64)->bool {
    for i in span.count { if !charge(work,1,limit) { return false; } let p=c.layout_premises[c.refs[span.start+i]]; if (p.kind==kind || kind==LAYOUT_AGGREGATE && p.kind==LAYOUT_PLAIN) && layout_shape(c,type_id,p.type_id,subs,0,work,limit) { return true; } }
    return false;
}
fn build_layout_premises(b:CoreBuilder,environment_types:const u32[:],adapter_environment_types:const u32[:],diagnostics:Diagnostic[>..]&)->bool {
    var accounts:Work[>..]=[]; for ct in b.contracts { accounts.push(Work{..}); }
    var active:u32=0;
    var heads:u32[>..]=[]; for ct in b.contracts { heads.push(0); }
    var next:u32[>..]=[]; for f,id in b.functions { next.push(0); if id!=0 { next[id]=heads[f.contract]; heads[f.contract]=id as u32; } }
    var seen:u32[>..]=[]; for ty in b.types { seen.push(0); }
    fn fail(code:u32) { diagnostics.push(Diagnostic{code:code,related:active,..}); return false from build_layout_premises; }
    fn tick() { if accounts[active].exhausted || !charge(accounts[active],1,LIMIT_VISITS) { fail(2030); } }
    fn add(out:u32[>..]&,ty:u32,kind:u32) {
        tick(); if !layout_dependent(core_view(b),ty,0,accounts[active],LIMIT_VISITS) { tick(); return; }
        for id in out { tick(); let p=b.layout_premises[id]; if p.kind==kind && layout_shape(core_view(b),ty,p.type_id,Span{..},0,accounts[active],LIMIT_VISITS) { return; } }
        if out.len>=LIMIT_TYPES { fail(2031); }
        let id=b.layout_premises.len as u32; b.layout_premises.push(LayoutPremise{ty,kind}); out.push(id);
    }
    recursive fn gather(ty:u32,out:u32[>..]&,depth:u32) {
        tick(); if depth>LIMIT_NEST { fail(2024); } if seen[ty]==active { return; } seen[ty]=active; let t=b.types[ty];
        if t.tag==TY_TUPLE || t.tag==TY_RECORD || t.tag==TY_SUM || t.tag==TY_RESULT || t.tag==TY_EXISTS { add(out,ty,LAYOUT_AGGREGATE); }
        if t.tag==TY_VIEW || t.tag==TY_DEST || t.tag==TY_BUILDER { add(out,layout_child(core_view(b),t,0),LAYOUT_PLAIN); }
        for i in layout_count(t) { gather(layout_child(core_view(b),t,i),out,depth+1); }
    }
    // Interface schemas and every body-local representation are explicit inputs.
    for ct,cid in b.contracts {
        if cid==0 { continue; } active=cid as u32; var out:u32[>..]=[];
        gather(ct.arg,out,0); gather(ct.result,out,0);
        var fid=heads[cid];
        while fid!=0 {
            let f=b.functions[fid];
            if fid<environment_types.len { gather(environment_types[fid],out,0); }
            for bi in f.blocks.count { let basic=b.blocks[b.refs[f.blocks.start+bi]];
                for pi in basic.params.count { gather(b.values[b.refs[basic.params.start+pi]].type_id,out,0); }
                for oi in basic.ops.count { let oid=b.refs[basic.ops.start+oi]; let op=b.ops[oid];
                    for adapter,ai in b.callable_adapters { if ai!=0 && ai<adapter_environment_types.len && adapter.op==oid { gather(adapter_environment_types[ai],out,0); } }
                    for ri in op.results.count { gather(b.values[b.refs[op.results.start+ri]].type_id,out,0); }
                    if op.tag==OP_TRY_ALLOC { gather(op.imm0,out,0); add(out,op.imm0,LAYOUT_PLAIN); }
                    for si in op.substitutions.count { let sub=b.substitutions[b.refs[op.substitutions.start+si]]; if sub.kind==KIND_TYPE && b.binders[sub.binder].constraints & CONSTRAINT_PLAIN!=0 { add(out,sub.value,LAYOUT_PLAIN); } }
                }
            }
            fid=next[fid];
        }
        b.contracts[cid].layout_premises=ref_span(b,out);
    }
    var scratch:u32[>..<]=[];
    recursive fn substitute(ty:u32,subs:Span,depth:u32)->u32 {
        tick(); if depth>LIMIT_NEST { fail(2024); } let t=b.types[ty];
        if t.tag==TY_PARAM { for i in subs.count { let sub=b.substitutions[b.refs[subs.start+i]]; if sub.kind==KIND_TYPE && sub.binder==t.binder { return sub.value; } } return ty; }
        if !layout_dependent(core_view(b),ty,0,accounts[active],LIMIT_VISITS) { tick(); return ty; }
        let start=scratch.len; var changed=false;
        for i in layout_count(t) { let old=layout_child(core_view(b),t,i); let child=substitute(old,subs,depth+1); if child!=old { changed=true; } scratch.push(child); }
        if !changed { scratch.resize(start); return ty; }
        var row=t;
        if t.fields.count!=0 {
            let begin=b.refs.len as u32;
            for i in t.fields.count { var field=b.fields[b.refs[t.fields.start+i]]; field.type_id=scratch[start+i]; let id=b.fields.len as u32; b.fields.push(field); b.refs.push(id); }
            row.fields=Span{begin,t.fields.count};
        } else { row.children=ref_span(b,scratch[start..]); }
        scratch.resize(start); let id=b.types.len as u32; b.types.push(row); return id;
    }
    // A deterministic postorder consumes completed callee premises once.
    // Constructors are dependencies too, since captured generic bodies require
    // the same bounded environment guarantees at their creation site.
    var dependency_heads:u32[>..]=[]; for ct in b.contracts { dependency_heads.push(0); }
    var dependency_next:u32[>..]=[0]; var dependency_target:u32[>..]=[0];
    for f,fid in b.functions { if fid==0 { continue; } active=f.contract;
        for bi in f.blocks.count { let basic=b.blocks[b.refs[f.blocks.start+bi]]; for oi in basic.ops.count {
            tick(); let op=b.ops[b.refs[basic.ops.start+oi]]; if op.tag!=OP_CALL && op.tag!=OP_CLOSURE && op.tag!=OP_FN_PLACE { continue; }
            let target=b.functions[op.imm0].contract; let id=dependency_target.len as u32;
            dependency_target.push(target); dependency_next.push(dependency_heads[f.contract]); dependency_heads[f.contract]=id;
        } }
    }
    var colors:u32[>..]=[]; for ct in b.contracts { colors.push(0); }
    var stack_contract:u32[>..<]=[]; var stack_edge:u32[>..<]=[]; var order:u32[>..]=[];
    for ct,cid in b.contracts {
        if cid==0 || colors[cid]!=0 { continue; } stack_contract.push(cid as u32); stack_edge.push(dependency_heads[cid]); colors[cid]=1;
        while stack_contract.len!=0 {
            let last=stack_contract.len-1; active=stack_contract[last]; tick(); let edge_id=stack_edge[last];
            if edge_id==0 { colors[active]=2; order.push(active); stack_contract.pop(); stack_edge.pop(); continue; }
            stack_edge[last]=dependency_next[edge_id]; let target=dependency_target[edge_id];
            if colors[target]==1 { fail(2023); }
            if colors[target]==0 { colors[target]=1; stack_contract.push(target); stack_edge.push(dependency_heads[target]); }
        }
    }
    for cid in order {
        active=cid; var out:u32[>..]=[]; let prior=b.contracts[cid].layout_premises;
        for i in prior.count { tick(); out.push(b.refs[prior.start+i]); }
        var fid=heads[cid];
        while fid!=0 { let f=b.functions[fid];
            for bi in f.blocks.count { let basic=b.blocks[b.refs[f.blocks.start+bi]]; for oi in basic.ops.count {
                tick(); let op=b.ops[b.refs[basic.ops.start+oi]];
                if op.tag!=OP_CALL && op.tag!=OP_CLOSURE && op.tag!=OP_FN_PLACE { continue; }
                let premises=b.contracts[b.functions[op.imm0].contract].layout_premises;
                for pi in premises.count { tick(); let p=b.layout_premises[b.refs[premises.start+pi]];
                    var exists=false; for id in out { tick(); let q=b.layout_premises[id]; if q.kind==p.kind && layout_shape(core_view(b),p.type_id,q.type_id,op.substitutions,0,accounts[active],LIMIT_VISITS) { exists=true; break; } }
                    if exists { continue; } let ty=substitute(p.type_id,op.substitutions,0); add(out,ty,p.kind);
                }
            } }
            fid=next[fid];
        }
        if out.len!=prior.count { b.contracts[cid].layout_premises=ref_span(b,out); } tick();
    }
    return true;
}
