// Release-only, bounded SSA transport from admitted monomorphic scalar bodies.
// The immutable input supplies every callee: prior expansions never become a
// new template. Physical rows are added only after global and caller preflight.
namespace inlining;
import .model;

struct Limits { visits:u64, rewrites:u64, growth:u64, encoded_bytes:u64 }
struct Stats { visits:u64=0, sites:u64=0, growth:u64=0, declines:u64=0, max_callee:u64=0, max_depth:u64=0, bytes:u64=0, reserved:u64=0, stopped:bool=false, exhausted:bool=false }
struct Fact { state:u32=0, operations:u32=0, arguments:u32=0, calls:u32=0 }
struct Item { op:u32, depth:u32 }
struct Planned { source:u32, operation:u32, value:u32, args:Span }
fn charge(s:Stats&, limits:Limits, n:u64=1)->bool {
    if s.visits>limits.visits { s.exhausted=true;return false; }
    let remaining=limits.visits-s.visits;
    if n>remaining || s.reserved>remaining-n {
        if s.reserved!=0 { s.stopped=true; } else { s.exhausted=true; }
        return false;
    }
    s.visits+=n;return true;
}
fn scalar(c:const Core&,type_id:u32,s:Stats&,limits:Limits)->bool {
    if !charge(s,limits) { return false; }
    let tag=c.types[type_id].tag; return tag==TY_U32 || tag==TY_BOOL || tag==TY_F32;
}
fn interface(c:const Core&,fid:u32,s:Stats&,limits:Limits)->bool {
    if !charge(s,limits,2) { return false; }
    let f=c.functions[fid];let ct=c.contracts[f.contract];
    return !f.evaluator_only && f.captures.count==0 && f.environment_bindings.count==0 && f.binders.count==0 &&
        ct.binders.count==0 && ct.requires.count==0 && ct.ensures.count==0 && ct.on_true.count==0 && ct.on_false.count==0 && ct.effects.count==0 &&
        scalar(c,ct.arg,s,limits) && scalar(c,ct.result,s,limits);
}
fn primitive(tag:u32)->bool {
    return tag==OP_BOOL || tag==OP_U32 || tag==OP_F32 || tag==OP_COPY ||
        (tag>=OP_U32_ADD_WRAP && tag<=OP_U32_XOR) || (tag>=OP_F32_ADD && tag<=OP_BOOL_NOT) ||
        tag==OP_U32_TO_F32 || tag==OP_BOOL_AND || tag==OP_BOOL_OR ||
        (tag>=OP_F32_SQRT && tag<=OP_U32_NOT);
}
fn classify(c:const Core&,fid:u32,pinned:const bool[:],facts:Fact[>..]&,s:Stats&,limits:Limits)->Fact {
    if !charge(s,limits) { return Fact{state:1}; }
    if facts[fid].state!=0 { return facts[fid]; }
    facts[fid].state=1;
    if !interface(c,fid,s,limits) { return facts[fid]; }
    let f=c.functions[fid]; if f.blocks.count!=1 { return facts[fid]; }
    if !charge(s,limits,2) { return facts[fid]; }
    let basic=c.blocks[f.entry];let term=c.terminators[basic.term];
    if basic.ops.count+1>32 || basic.params.count!=1 || basic.evidence_params.count!=0 || basic.merge!=0 || c.refs[basic.params.start]!=f.param ||
        term.tag!=TERM_RETURN || term.evidence.count!=0 || term.discharge.count!=0 || term.edges.count!=0 { return facts[fid]; }
    var result=Fact{state:2,operations:basic.ops.count};var returned=term.subject==f.param;
    for i in basic.ops.count {
        if !charge(s,limits) { return Fact{state:1}; }
        let oid=c.refs[basic.ops.start+i];let op=c.ops[oid];
        if pinned[oid] || op.results.count!=1 || op.args.count>2 || op.evidence.count!=0 || op.substitutions.count!=0 ||
            (!primitive(op.tag) && op.tag!=OP_CALL) { return facts[fid]; }
        if !charge(s,limits,2) { return Fact{state:1}; }
        let value=c.refs[op.results.start];
        if !scalar(c,c.values[value].type_id,s,limits) { return facts[fid]; }
        if value==term.subject { returned=true; }
        result.arguments+=op.args.count;
        for ai in op.args.count {
            if !charge(s,limits,2) { return Fact{state:1}; }
            if !scalar(c,c.values[c.refs[op.args.start+ai]].type_id,s,limits) { return facts[fid]; }
        }
        if op.tag==OP_CALL {
            if !interface(c,op.imm0,s,limits) { return facts[fid]; } result.calls++;
        }
    }
    // A nonempty body returning its parameter still has evaluated operations;
    // retain those until a separate rule transports that return shape.
    if !returned || (basic.ops.count!=0 && term.subject==f.param) { return facts[fid]; }
    facts[fid]=result;return result;
}
fn mapped(source:u32,from:const u32[:],to:const u32[:],s:Stats&,limits:Limits)->u32 {
    for value,i in from { if !charge(s,limits) { return 0; } if value==source { return to[i]; } }
    return 0;
}
struct Caller { fid:u32, original:u64, allowance:u64, grown:u64=0, sites:u64=0, changed:bool=false }
struct Basic { bid:u32, original:u32, changed:bool=false }
// Reserve the exact upper bound needed to flush the currently pending IDs and
// live call list. Analysis stops before spending these visits; commit is fully
// precharged and cannot stop halfway through an expanded SSA definition.
// For F finalized IDs, P pending IDs and C call records: flush costs P,
// writing the block costs F+P, and call filtering/publication costs at most2C.
fn finish_cost(final:u64,pending:u64,calls:u64,changed:bool)->u64 {
    return (if changed {final+2*pending} else {0 as u64})+2*calls;
}
fn finish_calls(b:CoreBuilder,caller:Caller,calls:const u32[:],s:Stats&,limits:Limits)->bool {
    s.reserved=0;
    if !caller.changed { return true; }
    var kept:u32[>..]=[];
    for id in calls { if !charge(s,limits) { return false; } let tag=b.ops[b.calls[id].op].tag;if tag==OP_CALL || tag==OP_CALL_INDIRECT { kept.push(id); } }
    if !charge(s,limits,kept.len as u64) { return false; }
    // Function.calls is the live listing. Unreferenced Call rows remain as
    // historical completion records, as after R03/R11; they authorize no code.
    b.functions[caller.fid].calls=ref_span(b,kept);return true;
}
fn finish_prefix(b:CoreBuilder,caller:Caller,calls:const u32[:],s:Stats&,limits:Limits)->bool {
    s.declines++;s.stopped=false;return finish_calls(b,caller,calls,s,limits);
}
fn finish_block(b:CoreBuilder,basic:Basic,final:u32[>..]&,pending:Item[>..<]&,calls:u64,s:Stats&,limits:Limits)->bool {
    s.reserved=2*calls;
    if !basic.changed { return true; }
    while pending.len!=0 { if !charge(s,limits) { return false; } final.push(pending.pop().op); }
    if !charge(s,limits,final.len as u64) { return false; } b.blocks[basic.bid].ops=ref_span(b,final);return true;
}
fn expand_site(c:const Core&,b:CoreBuilder,item:Item,call:Operation,basic:Basic&,caller:Caller&,pinned:const bool[:],facts:Fact[>..]&,calls:u32[>..]&,final:u64,pending:u64,emitted:u32[>..]&,s:Stats&,limits:Limits)->bool {
    if item.depth>=2 || caller.sites>=16 || (item.op<pinned.len && pinned[item.op]) || call.args.count!=1 || call.results.count!=1 || call.evidence.count!=0 || call.substitutions.count!=0 {
        s.declines++;return true;
    }
    let fact=classify(c,call.imm0,pinned,facts,s,limits);if s.exhausted || s.stopped { return false; }
    if fact.state!=2 { s.declines++;return true; }
    if !charge(s,limits,4) { return false; }
    let callee=c.functions[call.imm0];let contract=c.contracts[callee.contract];let body=c.blocks[callee.entry];let term=c.terminators[body.term];
    let argument=b.refs[call.args.start];let result=b.refs[call.results.start];
    if b.values[argument].type_id!=contract.arg || b.values[result].type_id!=contract.result { s.declines++;return true; }
    let growth=if fact.operations==0 {0 as u64} else {fact.operations as u64-1};
    if growth>caller.allowance-caller.grown || caller.original+caller.grown+growth>LIMIT_OPS || s.sites>=limits.rewrites || growth>limits.growth-s.growth { s.declines++;return true; }
    let block_refs=if basic.changed {0 as u64} else {basic.original as u64};
    let call_refs=if caller.changed {0 as u64} else {calls.len as u64};
    let refs=fact.arguments as u64+growth+block_refs+growth+call_refs+fact.calls;
    let bytes=growth*80+fact.calls as u64*24+refs*4;
    if bytes>LIMIT_ARTIFACT-s.bytes || b.ops.len as u64+growth>MAX_U32 || b.values.len as u64+growth>MAX_U32 ||
        b.calls.len as u64+fact.calls>MAX_U32 || b.refs.len as u64+refs>MAX_U32 { s.declines++;return true; }
    var from:u32[>..]=[callee.param];var to:u32[>..]=[argument];var args:u32[>..]=[];var plan:Planned[>..]=[];
    var next_op=b.ops.len as u32;var next_value=b.values.len as u32;var reused_call:u32=0;var new_calls=fact.calls;
    for ci in body.ops.count {
        if !charge(s,limits,2) { return false; }
        let source=c.refs[body.ops.start+ci];let op=c.ops[source];let old=c.refs[op.results.start];
        let value=if old==term.subject {result} else {next_value};let operation=if old==term.subject {item.op} else {next_op};
        if old!=term.subject { next_op++;next_value++; }
        let start=args.len as u32;
        for ai in op.args.count {
            if !charge(s,limits) { return false; }
            let replacement=mapped(c.refs[op.args.start+ai],from,to,s,limits);if replacement==0 { return false; }args.push(replacement);
        }
        if operation==item.op && op.tag==OP_CALL {
            // Appended operation IDs cannot reuse a preexisting Call record.
            for id in calls { if !charge(s,limits) { return false; } if b.calls[id].op==item.op { reused_call=id;new_calls--;break; } }
        }
        plan.push(Planned{source,operation,value,Span{start,op.args.count}});from.push(old);to.push(value);
    }
    let replacement=if fact.operations==0 {1 as u64} else {plan.len as u64};
    s.reserved=finish_cost(final,pending+replacement,calls.len as u64+new_calls,true);
    if !charge(s,limits,(plan.len*6+args.len) as u64+growth+fact.calls as u64*2+2) { return false; }
    // All fallible analysis and every commit/finalization visit are preflighted.
    s.bytes+=bytes;s.sites++;s.growth+=growth;caller.sites++;caller.grown+=growth;basic.changed=true;caller.changed=true;
    s.max_callee=max(s.max_callee,fact.operations as u64+1);s.max_depth=max(s.max_depth,item.depth as u64+1);
    if fact.operations==0 { b.ops[item.op].tag=OP_COPY;b.ops[item.op].registry=OP_COPY;b.ops[item.op].imm0=0;emitted.push(item.op);return true; }
    for row in plan {
        let old=c.ops[row.source];var copy=old;copy.scope=call.scope;copy.args=ref_span(b,args[row.args.start..row.args.start+row.args.count]);
        if row.operation==item.op { copy.results=call.results;b.ops[item.op]=copy; }
        else {
            copy.results=ref_span(b,[row.value]);assert(row.operation==b.ops.len && row.value==b.values.len);
            b.ops.push(copy);let value=c.values[c.refs[old.results.start]];
            b.values.push(Value{type_id:value.type_id,block_id:basic.bid,op:row.operation,version:row.value,scope:call.scope,origin:value.origin});
        }
        if copy.tag==OP_CALL {
            let record=Call{op:row.operation,caller:caller.fid,callee:copy.imm0,contract:c.functions[copy.imm0].contract,substitutions:Span{..}};
            if row.operation==item.op && reused_call!=0 { b.calls[reused_call]=record; }
            else { calls.push(b.calls.len as u32);b.calls.push(record); }
        }
        emitted.push(row.operation);
    }
    return true;
}
fn run(c:const Core&,b:CoreBuilder,pinned:const bool[:],limits:Limits,s:Stats&)->bool {
    s.bytes=limits.encoded_bytes;
    if s.bytes>LIMIT_ARTIFACT { s.exhausted=true;return false; }
    var facts:Fact[>..]=[];
    for row in c.functions { if !charge(s,limits) { return false; } facts.push(Fact{}); }
    for f,fid in c.functions {
        // No unprocessed function has changed. Stop before starting a header
        // scan that cannot fit, retaining only the completely finalized prefix.
        if limits.visits-s.visits<2 { s.declines++;return true; }
        if !charge(s,limits) { return false; }
        if fid==0 || f.evaluator_only { continue; }
        if f.blocks.count>limits.visits-s.visits { s.declines++;return true; }
        var original:u64=0;
        for bi in f.blocks.count { if !charge(s,limits) { return false; } original+=c.blocks[c.refs[f.blocks.start+bi]].ops.count+1; }
        let setup=f.calls.count as u64+f.blocks.count+(original-f.blocks.count)*2;
        if setup>limits.visits-s.visits { s.declines++;return true; }
        var caller=Caller{fid as u32,original,min(original/4,256 as u64)};
        var calls:u32[>..]=[];
        for ci in b.functions[fid].calls.count { if !charge(s,limits) { return false; } calls.push(b.refs[b.functions[fid].calls.start+ci]); }
        for bi in f.blocks.count {
            if !charge(s,limits) { if s.stopped {return finish_prefix(b,caller,calls,s,limits);}return false; }
            let bid=c.refs[f.blocks.start+bi];let row=b.blocks[bid];var basic=Basic{bid,row.ops.count};
            var pending:Item[>..<]=[];var final:u32[>..]=[];var oi=row.ops.count;
            while oi!=0 {
                if !charge(s,limits) { if s.stopped {return finish_prefix(b,caller,calls,s,limits);}return false; }
                oi--;pending.push(Item{b.refs[row.ops.start+oi],0});
            }
            while pending.len!=0 {
                s.reserved=finish_cost(final.len as u64,pending.len as u64,calls.len as u64,basic.changed);
                if !charge(s,limits) { break; }
                let item=pending.pop();let call=b.ops[item.op];
                if call.tag!=OP_CALL { final.push(item.op);continue; }
                var emitted:u32[>..]=[];
                if !expand_site(c,b,item,call,basic,caller,pinned,facts,calls,final.len as u64,pending.len as u64,emitted,s,limits) {
                    if !s.stopped && !s.exhausted {return false;}
                    pending.push(item);break;
                }
                if emitted.len==0 { final.push(item.op); }
                else { var i=emitted.len;while i!=0 { i--;pending.push(Item{emitted[i],item.depth+1}); } }
            }
            if s.exhausted { return false; }
            if !finish_block(b,basic,final,pending,calls.len as u64,s,limits) { return false; }
            if s.stopped {return finish_prefix(b,caller,calls,s,limits);}
        }
        if !finish_calls(b,caller,calls,s,limits) { return false; }
    }
    return true;
}
