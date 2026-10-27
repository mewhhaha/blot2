// Independent admission check: supplied realization rows are evidence to verify,
// never an enumeration of the contexts that must exist.
import .model;
struct CoverageBinding { binder:u32, type_id:u32 }
struct CoverageContext { function:u32, bindings:Span }
fn check_dictionary_coverage(c:Core, work:Work&, diagnostics:Diagnostic[>..]&) -> bool {
    var bindings:CoverageBinding[>..]=[]; var contexts:CoverageContext[>..]=[];
    var active:u32=0; var charges:u64[>..]=[]; for f in c.functions { charges.push(0); }
    var layout_ids:u32[>..]=[]; for ty in c.types { layout_ids.push(0); }
    for row,i in c.layouts { if i!=0 { layout_ids[row.type_id]=i as u32; } }
    fn fail(related:u32) { diagnostics.push(Diagnostic {2034,0,2034,related}); return false from check_dictionary_coverage; }
    fn tick() { work.visits++; charges[active]++; if charges[active]>LIMIT_VISITS { work.exhausted=true; diagnostics.push(Diagnostic {2030,0,2030,active}); return false from check_dictionary_coverage; } }
    // Rebuild owner-local lookup lists from the independently admitted Core.
    // Ascending Value IDs preserve the old demand order within each function.
    var value_heads:u32[>..]=[]; var context_heads:u32[>..]=[];
    for f in c.functions { value_heads.push(0); context_heads.push(0); }
    var value_next:u32[>..]=[]; for v in c.values { value_next.push(0); }
    var context_next:u32[>..]=[]; var cursor=c.values.len;
    while cursor>1 {
        cursor--; let value=c.values[cursor];
        active=if value.block_id!=0 {c.blocks[value.block_id].function} else {0}; tick();
        if value.block_id!=0 { value_next[cursor]=value_heads[active]; value_heads[active]=cursor as u32; }
    }
    fn rows(span:Span)->const u32[:] { c.refs[span.start..span.start+span.count] }
    fn selected(span:Span,binder:u32)->u32 { for row in bindings[span.start..span.start+span.count] { tick(); if row.binder==binder { return row.type_id; } } return 0; }
    fn same_type(a:u32,b:u32)->bool {
        tick(); if a==b { return true; }
        let ai=layout_ids[a]; let bi=layout_ids[b]; if ai==0 || bi==0 { return false; }
        let x=c.layouts[ai].schema; let y=c.layouts[bi].schema; if x==0 || y==0 { return false; }
        if x==y { return true; }
        let xs=c.schemas[x].bytes; let ys=c.schemas[y].bytes;
        return c.bytes[xs.start..xs.start+xs.count]==c.bytes[ys.start..ys.start+ys.count];
    }
    recursive fn parameters(ty:u32,out:u32[>..]&,depth:u32) {
        tick(); if depth>64 { fail(ty); } let t=c.types[ty];
        if t.tag==TY_PARAM { for old in out { if old==t.binder { return; } } out.push(t.binder); return; }
        if t.tag==TY_FORALL { return; }
        for child in rows(t.children) { parameters(child,out,depth+1); }
        for field in rows(t.fields) { parameters(c.fields[field].type_id,out,depth+1); }
        if t.tag==TY_FN { let ct=c.contracts[t.contract]; parameters(ct.arg,out,depth+1); parameters(ct.result,out,depth+1); }
    }
    fn closed(ty:u32)->bool { var ids:u32[>..]=[]; parameters(ty,ids,0); return ids.len==0; }
    fn resolve(ty:u32,context:Span)->u32 {
        var terminal=ty;
        for depth in 65 { let t=c.types[terminal]; if t.tag!=TY_ALIAS { break; } terminal=c.refs[t.children.start]; }
        if c.types[terminal].tag==TY_PARAM { let result=selected(context,c.types[terminal].binder); if result==0 { fail(ty); } return result; }
        var params:u32[>..]=[]; parameters(ty,params,0); if params.len==0 { return ty; }
        for row,i in c.dictionary_realizations {
            tick(); if i==0 || row.type_id!=ty || row.parameters.count!=params.len { continue; }
            var matches=true;
            for binder,j in rows(row.parameters) {
                let actual=selected(context,binder);
                if actual==0 || !same_type(actual,c.refs[row.arguments.start+j]) { matches=false; break; }
            }
            if matches { return row.concrete_type; }
        }
        fail(ty); return 0;
    }
    recursive fn demand(ty:u32,context:Span,depth:u32) {
        tick(); if depth>64 { fail(ty); } let t=c.types[ty];
        if t.tag==TY_FORALL { return; }
        resolve(ty,context);
        for child in rows(t.children) { demand(child,context,depth+1); }
        for field in rows(t.fields) { demand(c.fields[field].type_id,context,depth+1); }
        if t.tag==TY_FN { let ct=c.contracts[t.contract]; demand(ct.arg,context,depth+1); demand(ct.result,context,depth+1); }
    }
    fn add_context(fid:u32,incoming:Span,optional:bool) {
        let f=c.functions[fid]; var required:u32[>..]=[];
        for id in rows(c.contracts[f.contract].binders) { if c.binders[id].kind==KIND_TYPE { required.push(id); } }
        for id in rows(f.environment_bindings) { let row=c.environment_bindings[id]; if row.kind==KIND_TYPE { var seen=false; for old in required { if old==row.binder { seen=true; break; } } if !seen { required.push(row.binder); } } }
        let start=bindings.len as u32;
        for binder in required {
            let ty=selected(incoming,binder);
            if ty==0 || !closed(ty) { bindings.resize(start as i64); if optional { return; } fail(fid); }
            bindings.push(CoverageBinding {binder,ty});
        }
        let key=Span {start,required.len as u32};
        var previous_id=context_heads[fid];
        while previous_id!=0 {
            tick(); let previous=contexts[previous_id-1]; previous_id=context_next[previous_id-1];
            if previous.bindings.count!=key.count { continue; }
            var equal=true;
            for row in bindings[key.start..key.start+key.count] { let old=selected(previous.bindings,row.binder); if old==0 || !same_type(old,row.type_id) { equal=false; break; } }
            if equal { bindings.resize(start as i64); return; }
        }
        if (contexts.len as u64)*12+(bindings.len as u64)*8+12>LIMIT_ARTIFACT { work.exhausted=true; diagnostics.push(Diagnostic {2030,0,2030,fid}); return false from check_dictionary_coverage; } contexts.push(CoverageContext {fid,key}); context_next.push(context_heads[fid]); context_heads[fid]=contexts.len as u32;
    }
    for f,i in c.functions { if i!=0 { active=i as u32; add_context(i as u32,Span {..},true); } }
    for ex,i in c.exports {
        if i==0 { continue; } active=ex.function; let start=bindings.len as u32;
        for id in rows(ex.substitutions) { let sub=c.substitutions[id]; if sub.kind==KIND_TYPE { bindings.push(CoverageBinding {sub.binder,sub.value}); } }
        add_context(ex.function,Span {start,bindings.len as u32-start},false);
    }
    var next:i64=0;
    while next<contexts.len {
        let context=contexts[next]; next++; active=context.function; let f=c.functions[context.function];
        for pid in rows(c.contracts[f.contract].layout_premises) {
            let premise=c.layout_premises[pid]; demand(premise.type_id,context.bindings,0);
            let concrete=resolve(premise.type_id,context.bindings); let id=layout_ids[concrete];
            if id==0 { fail(premise.type_id); } let layout=c.layouts[id];
            if (premise.kind==LAYOUT_AGGREGATE && layout.size>256) || (premise.kind==LAYOUT_PLAIN && (layout.size>64 || (layout.flags&1)==0)) { fail(premise.type_id); }
        }
        demand(c.contracts[f.contract].arg,context.bindings,0); demand(c.contracts[f.contract].result,context.bindings,0);
        var vid=value_heads[context.function];
        while vid!=0 { tick(); demand(c.values[vid].type_id,context.bindings,0); vid=value_next[vid]; }
        for block_id in rows(f.blocks) { for oid in rows(c.blocks[block_id].ops) {
            tick(); let op=c.ops[oid]; if op.tag==OP_TRY_ALLOC { demand(op.imm0,context.bindings,0); }
            if op.tag!=OP_CALL && op.tag!=OP_CLOSURE && op.tag!=OP_FN_PLACE { continue; }
            let start=bindings.len as u32;
            for id in rows(op.substitutions) { let sub=c.substitutions[id]; if sub.kind==KIND_TYPE { demand(sub.value,context.bindings,0); let concrete=resolve(sub.value,context.bindings); bindings.push(CoverageBinding {sub.binder,concrete}); } }
            let own=Span {start,bindings.len as u32-start};
            for pi in context.bindings.count { let parent=bindings[context.bindings.start+pi]; if selected(own,parent.binder)==0 { bindings.push(parent); } }
            add_context(op.imm0,Span {start,bindings.len as u32-start},false);
        } }
    }
    return true;
}
