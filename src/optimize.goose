// Bounded optional local rewriting. Every returned candidate is independently
// validated; budget decline keeps the caller's already admitted baseline.
namespace optimize;
import src.model;
import src.validate;
import src.artifact;
import src.evaluate;
import math;
import src.inline;

struct Limits { release: bool = false, visits: u64 = 0, rewrites: u64 = 0, output: u64 = 0 }
struct Stats { inline_sites:u64=0, inline_growth:u64=0, inline_declines:u64=0, inline_max_callee:u64=0, inline_max_depth:u64=0, visits: u64 = 0, applications: u64 = 0, declines: u64 = 0, candidates: u64 = 0, r01: u64 = 0, r02: u64 = 0, r05: u64 = 0, r09: u64 = 0, r10: u64 = 0, r03: u64 = 0, r04: u64 = 0, r06: u64 = 0, r07: u64 = 0, r08: u64 = 0, r11: u64 = 0, r12: u64 = 0 }
fn tick(stats: Stats&, limit: u64) -> bool {
    if stats.visits >= limit { return false; } stats.visits++; return true;
}
fn constant(c: Core, value: u32) -> Operation, bool {
    let op_id = c.values[value].op;
    if op_id == 0 { return Operation {..}, false; }
    let op = c.ops[op_id];
    return op, op.tag >= OP_UNIT && op.tag <= OP_F32;
}
fn rewrite_literal(b: CoreBuilder, index: u32) -> bool {
    let op = b.ops[index];
    if op.args.count != 2 || op.results.count != 1 { return false; }
    let c = core_view(b);
    let a, a_ok = constant(c, c.refs[op.args.start]); let d, d_ok = constant(c, c.refs[op.args.start + 1]);
    if !a_ok || !d_ok || a.tag != OP_U32 || d.tag != OP_U32 { return false; }
    var result: u32 = 0; var tag = OP_U32;
    if op.tag == OP_U32_ADD || op.tag == OP_U32_ADD_WRAP { result = (((a.imm0 as u64) + d.imm0) & MAX_U32) as! u32; }
    else if op.tag == OP_U32_SUB || op.tag == OP_U32_SUB_WRAP { result = (((a.imm0 as u64) + 4294967296 - d.imm0) & MAX_U32) as! u32; }
    else if op.tag == OP_U32_MUL || op.tag == OP_U32_MUL_WRAP { result = (((a.imm0 as u64) * d.imm0) & MAX_U32) as! u32; }
    else if op.tag == OP_U32_DIV && d.imm0 != 0 { result = a.imm0 / d.imm0; }
    else if op.tag == OP_U32_REM && d.imm0 != 0 { result = a.imm0 % d.imm0; }
    else if op.tag == OP_U32_AND { result = a.imm0 & d.imm0; }
    else if op.tag == OP_U32_OR { result = a.imm0 | d.imm0; }
    else if op.tag == OP_U32_XOR { result = a.imm0 ^ d.imm0; }
    else if op.tag == OP_U32_SHL && d.imm0 < 32 { result = a.imm0 << d.imm0; }
    else if op.tag == OP_U32_SHR && d.imm0 < 32 { result = a.imm0 >> d.imm0; }
    else if op.tag >= OP_U32_EQ && op.tag <= OP_U32_GE {
        tag = OP_BOOL; var yes = false;
        if op.tag == OP_U32_EQ { yes = a.imm0 == d.imm0; }
        if op.tag == OP_U32_NE { yes = a.imm0 != d.imm0; }
        if op.tag == OP_U32_LT { yes = a.imm0 < d.imm0; }
        if op.tag == OP_U32_LE { yes = a.imm0 <= d.imm0; }
        if op.tag == OP_U32_GT { yes = a.imm0 > d.imm0; }
        if op.tag == OP_U32_GE { yes = a.imm0 >= d.imm0; }
        if yes { result = 1; }
    } else { return false; }
    // Checked overflow is already required in baseline; retain an exact defensive
    // equivalence test so an optimizer bug never launders invalid arithmetic.
    if op.tag == OP_U32_ADD && (a.imm0 as u64) + d.imm0 > MAX_U32 { return false; }
    if op.tag == OP_U32_SUB && a.imm0 < d.imm0 { return false; }
    if op.tag == OP_U32_MUL && (a.imm0 as u64) * d.imm0 > MAX_U32 { return false; }
    b.ops[index].tag = tag; b.ops[index].registry = tag;
    b.ops[index].args = Span {..}; b.ops[index].evidence = Span {..}; b.ops[index].imm0 = result;
    return true;
}
fn rewrite_projection(b: CoreBuilder, index: u32) -> bool {
    let op = b.ops[index]; if op.tag != OP_PROJECT || op.args.count != 1 { return false; }
    let arg = b.refs[op.args.start]; let producer = b.values[arg].op;
    if producer == 0 { return false; }
    let product = b.ops[producer];
    if product.tag != OP_TUPLE && product.tag != OP_RECORD || op.imm0 >= product.args.count { return false; }
    let field = b.refs[product.args.start + op.imm0];
    b.ops[index].tag = OP_COPY; b.ops[index].registry = OP_COPY;
    b.ops[index].args = Span { product.args.start + op.imm0, 1 }; b.ops[index].imm0 = 0;
    return true;
}
fn rewrite_identity(b: CoreBuilder, index: u32) -> bool {
    let op = b.ops[index]; if op.tag != OP_CALL || op.substitutions.count != 0 { return false; }
    let c = core_view(b); let f = c.functions[op.imm0]; let contract = c.contracts[f.contract];
    if f.blocks.count != 1 || f.captures.count != 0 || f.environment_bindings.count != 0 || contract.effects.count != 0 || contract.binders.count != 0 { return false; }
    let basic = c.blocks[f.entry]; let term = c.terminators[basic.term];
    if basic.ops.count != 0 || term.tag != TERM_RETURN || term.subject != f.param { return false; }
    b.ops[index].tag = OP_COPY; b.ops[index].registry = OP_COPY; b.ops[index].imm0 = 0;
    return true;
}
fn optimize(c: Core, limits: Limits, output: CoreBuilder, stats: Stats&, diags: Diagnostic[>..]&) -> bool {
    let n = c.ops.len - 1 + c.terminators.len - 1;
    var visit_limit = (n as u64) * 8 + 1024;
    var rewrite_limit = n as u64 + 256;
    var output_limit = n as u64 + 64;
    if limits.visits != 0 && limits.visits < visit_limit { visit_limit = limits.visits; }
    if limits.rewrites != 0 && limits.rewrites < rewrite_limit { rewrite_limit = limits.rewrites; }
    if limits.output != 0 && limits.output < output_limit { output_limit = limits.output; }
    if (n as u64) > output_limit { stats.declines++; return false; }
    var encoded: u8[>..] = [];
    if !artifact::encode_tables(c, encoded) { stats.declines++; return false; }
    if !artifact::artifact_decode(encoded, output, diags) { return false; }
    output.phase = c.phase; // Current-process clone preserves the sealed admission guard.
    var uses: u32[>..] = []; for i in c.values.len { uses.push(0); }
    var pinned: bool[>..] = []; for i in c.ops.len { pinned.push(false); }
    for op, index in c.ops {
        if index == 0 { continue; }
        for i in op.args.count { if !tick(stats, visit_limit) { stats.declines++; return false; } uses[c.refs[op.args.start + i]]++; }

    }
    for term in c.terminators { if !tick(stats, visit_limit) { stats.declines++; return false; } if term.subject != 0 { uses[term.subject]++; } }
    for edge in c.edges { for i in edge.args.count { if !tick(stats, visit_limit) { stats.declines++; return false; } uses[c.refs[edge.args.start + i]]++; } }
    for term in c.terms {
        if !tick(stats, visit_limit) { stats.declines++; return false; }
        if term.value != 0 { uses[term.value]++; pinned[c.values[term.value].op] = true; }
    }
    for ev in c.evidence {
        if !tick(stats, visit_limit) { stats.declines++; return false; }
        if ev.call != 0 { pinned[ev.call] = true; }
        for i in ev.operands.count {
            if !tick(stats, visit_limit) { stats.declines++; return false; }
            let value = c.refs[ev.operands.start + i]; uses[value]++; pinned[c.values[value].op] = true;
        }
    }
    // Operation identities appearing in evidence remain fixed until a rule also
    // transports their derivations. A changed producer is not justified merely
    // because its scalar result happens to be equivalent.
    var order: u32[>..] = [];
    if !reverse_postorder(c, order, stats, visit_limit) { stats.declines++; return false; }
    var queue: u32[>..] = [];
    for block_id in order {
        let basic = c.blocks[block_id];
        for oi in basic.ops.count {
            if !tick(stats, visit_limit) { stats.declines++; return false; }
            queue.push(c.refs[basic.ops.start + oi]);
        }
    }
    var cursor: i64 = 0;
    while cursor < queue.len {
            if !tick(stats, visit_limit) || stats.applications >= rewrite_limit { stats.declines++; return false; }
            let id = queue[cursor]; cursor++; stats.candidates++;
            if pinned[id] { continue; }
            var changed = false;
            if rewrite_identity(output, id) { stats.r03++; changed = true; }
            else if rewrite_projection(output, id) { stats.r04++; changed = true; }
            else if rewrite_copy(output, id) { stats.r06++; changed = true; }
            else if rewrite_literal(output, id) || rewrite_float(output,id) { stats.r07++; changed = true; }
            else if rewrite_length(output, id) { stats.r08++; changed = true; }
            else if rewrite_store_read(output, id) { stats.r09++; changed = true; }
            else if rewrite_descriptor(output, id) { stats.r10++; changed = true; }
            else if rewrite_callable(output, id) { stats.r11++; changed = true; }
            else if rewrite_dead(output, id, uses) { stats.r12++; changed = true; }
            if changed { stats.applications++; }
    }
    for block_id in order {
        if !tick(stats,visit_limit) || stats.applications >= rewrite_limit { stats.declines++; return false; }
        let rule = rewrite_control(output,block_id,stats,visit_limit);
        if stats.visits >= visit_limit { stats.declines++; return false; }
        if rule == 1 { stats.r01++; stats.applications++; }
        if rule == 2 { stats.r02++; stats.applications++; }
        if rule == 5 { stats.r05++; stats.applications++; }
    }
    if limits.release {
        var expansion=inlining::Stats{};
        let accepted=inlining::run(c,output,pinned,inlining::Limits{visit_limit-stats.visits,rewrite_limit-stats.applications,output_limit-n as u64,encoded.len as u64},expansion);
        stats.visits+=expansion.visits;stats.applications+=expansion.sites;
        stats.inline_sites=expansion.sites;stats.inline_growth=expansion.growth;stats.inline_declines=expansion.declines;
        stats.inline_max_callee=expansion.max_callee;stats.inline_max_depth=expansion.max_depth;
        if !accepted { if expansion.exhausted { stats.declines++; } return false; }
    }
    var work = Work {..}; var validation_diags: Diagnostic[>..] = [];
    if !validator::validate_core(core_view(output), validator::FRESH, work, validation_diags) {
        // Exhaustion means optional decline. Other failures are an optimizer bug:
        // propagate diagnostics and require the caller to abort publication.
        if work.exhausted { stats.declines++; return false; }
        diags.append(validation_diags); return false;
    }
    return true;
}

fn rewrite_copy(b: CoreBuilder, index: u32) -> bool {
    let op = b.ops[index]; if op.tag != OP_COPY || op.args.count != 1 { return false; }
    let source, known = constant(core_view(b), b.refs[op.args.start]);
    if !known { return false; }
    b.ops[index].tag = source.tag; b.ops[index].registry = source.tag; b.ops[index].args = Span {..}; b.ops[index].imm0 = source.imm0; return true;
}
fn rewrite_length(b: CoreBuilder, index: u32) -> bool {
    let op = b.ops[index]; if op.tag != OP_VIEW_LEN || op.args.count != 1 { return false; }
    let ty = b.types[b.values[b.refs[op.args.start]].type_id];
    if ty.tag != TY_VIEW || ty.nat == 0 || b.terms[ty.nat].tag != EXPR_LITERAL { return false; }
    b.ops[index].tag = OP_U32; b.ops[index].registry = OP_U32; b.ops[index].args = Span {..}; b.ops[index].imm0 = b.terms[ty.nat].literal; return true;
}
fn rewrite_callable(b: CoreBuilder, index: u32) -> bool {
    let op = b.ops[index]; if op.tag != OP_CALL_INDIRECT { return false; }
    if op.args.count != 2 { return false; }
    let callable = b.refs[op.args.start]; let definition = b.values[callable].op; if definition == 0 || b.ops[definition].tag != OP_CLOSURE || b.ops[definition].args.count != 0 { return false; }
    let target = b.functions[b.ops[definition].imm0]; if target.captures.count != 0 || target.environment_bindings.count != 0 { return false; }
    let ty = b.types[b.values[callable].type_id]; if ty.mode != MODE_MANY { return false; }
    b.ops[index].tag = OP_CALL; b.ops[index].registry = OP_CALL; b.ops[index].imm0 = b.ops[definition].imm0; b.ops[index].args = Span { op.args.start + 1, 1 }; b.ops[index].substitutions = b.ops[definition].substitutions; return true;
}
fn rewrite_dead(b: CoreBuilder, index: u32, uses: const u32[:]) -> bool {
    let op = b.ops[index]; if op.results.count != 1 || uses[b.refs[op.results.start]] != 0 { return false; }
    let total = op.tag == OP_U32_ADD_WRAP || op.tag == OP_U32_SUB_WRAP || op.tag == OP_U32_MUL_WRAP ||
        op.tag >= OP_U32_EQ && op.tag <= OP_U32_XOR || op.tag >= OP_F32_ADD && op.tag <= OP_F32_GE || op.tag == OP_BOOL_NOT;
    if !total { return false; }
    let tag = b.types[b.values[b.refs[op.results.start]].type_id].tag;
    var replacement = OP_U32; if tag == TY_BOOL { replacement = OP_BOOL; } if tag == TY_F32 { replacement = OP_F32; }
    b.ops[index].tag = replacement; b.ops[index].registry = replacement; b.ops[index].args = Span {..}; b.ops[index].evidence = Span {..}; b.ops[index].imm0 = 0; return true;
}

struct Walk { block_id: u32, edge: u32 }
fn reverse_postorder(c: Core, output: u32[>..]&, stats: Stats&, limit: u64) -> bool {
    var seen: bool[>..] = []; for row in c.blocks { seen.push(false); }
    var stack: Walk[>..<] = []; var finished: u32[>..<] = [];
    for fun, fid in c.functions {
        if fid == 0 { continue; }
        // Unreachable rows are still independently validated. Give them a stable
        // component order without letting allocation order reorder reachable CFG.
        for component in fun.blocks.count + 1 {
            let root = if component == 0 { fun.entry } else { c.refs[fun.blocks.start + component - 1] };
            if seen[root] { continue; }
            stack.push(Walk {root, 0}); seen[root] = true;
            while stack.len != 0 {
                if !tick(stats, limit) { return false; }
                let last = stack.len - 1; let item = stack[last]; let term = c.terminators[c.blocks[item.block_id].term];
                if item.edge < term.edges.count {
                    stack[last].edge++;
                    let child = c.edges[c.refs[term.edges.start + item.edge]].to;
                    if !seen[child] { seen[child] = true; stack.push(Walk {child, 0}); }
                } else { finished.push(item.block_id); stack.pop(); }
            }
            while finished.len != 0 { output.push(finished.pop()); }
        }
    }
    return true;
}

fn rewrite_store_read(b:CoreBuilder,index:u32) -> bool {
    let op=b.ops[index]; if op.tag != OP_BUILDER_GET || op.args.count != 2 { return false; }
    let builder=b.refs[op.args.start]; let producer=b.values[builder].op;
    if producer==0 { return false; } let store=b.ops[producer];
    if store.tag != OP_BUILDER_SET || store.args.count != 3 { return false; }
    // The exact successor Builder is still exclusive and initialized. Reusing
    // the stored Plain value preserves the original mutation and its checks.
    let load_index=b.refs[op.args.start+1]; let store_index=b.refs[store.args.start+1];
    var equal=load_index==store_index;
    if !equal {
        let a,ak=constant(core_view(b),load_index); let c,ck=constant(core_view(b),store_index);
        equal=ak && ck && a.tag==OP_U32 && c.tag==OP_U32 && a.imm0==c.imm0;
    }
    if !equal { return false; }
    b.ops[index].tag=OP_COPY; b.ops[index].registry=OP_COPY; b.ops[index].args=Span {store.args.start+2,1}; b.ops[index].evidence=Span{..};
    return true;
}
fn rewrite_descriptor(b:CoreBuilder,index:u32) -> bool {
    let op=b.ops[index]; if op.args.count != 1 { return false; }
    let input=b.refs[op.args.start]; let producer=b.values[input].op; if producer==0 { return false; }
    let construction=b.ops[producer];
    if op.tag==OP_TAG && construction.tag==OP_SUM {
        b.ops[index].tag=OP_U32; b.ops[index].registry=OP_U32; b.ops[index].args=Span{..}; b.ops[index].imm0=construction.imm0; return true;
    }
    if op.tag==OP_INDEX_VALUE && construction.tag==OP_PAYLOAD && construction.imm0==1 {
        let result=b.refs[construction.args.start]; let checked=b.values[result].op;
        if checked != 0 && b.ops[checked].tag==OP_TRY_INDEX {
            b.ops[index].tag=OP_COPY; b.ops[index].registry=OP_COPY; b.ops[index].args=Span {b.ops[checked].args.start+1,1}; b.ops[index].imm0=0; return true;
        }
    }
    return false;
}
fn rewrite_control(b:CoreBuilder,block_id:u32,stats:Stats&,limit:u64) -> u32 {
    let c=core_view(b); let basic=c.blocks[block_id]; let term=c.terminators[basic.term];
    if term.tag==TERM_JUMP && term.edges.count==1 {
        let edge=c.edges[c.refs[term.edges.start]]; let next=c.blocks[edge.to]; let exit=c.terminators[next.term];
        let contract=c.contracts[c.functions[basic.function].contract];
        if edge.kind!=EDGE_NORMAL || edge.evidence.count!=0 || next.scope!=basic.scope || next.ops.count!=0 || next.evidence_params.count!=0 || exit.tag!=TERM_RETURN ||
            exit.discharge.count!=0 || contract.ensures.count!=0 || contract.on_true.count!=0 || contract.on_false.count!=0 { return 0; }
        var result=exit.subject; var rule:u32=1;
        if next.params.count==1 && c.refs[next.params.start]==result { result=c.refs[edge.args.start]; rule=2; }
        else if next.params.count!=0 { return 0; }
        b.terminators[basic.term].tag=TERM_RETURN; b.terminators[basic.term].subject=result; b.terminators[basic.term].edges=Span{..}; b.blocks[block_id].merge=0;
        return rule;
    }
    if term.tag==TERM_BRANCH && term.edges.count==2 {
        let value,known=constant(c,term.subject); if !known || value.tag!=OP_BOOL { return 0; }
        let yes=c.refs[term.edges.start]; let no=c.refs[term.edges.start+1];
        for proof in c.evidence { if !tick(stats,limit) { return 0; } if proof.edge==yes || proof.edge==no { return 0; } }
        for loop_info in c.loops { if !tick(stats,limit) { return 0; } if loop_info.header==block_id { return 0; } }
        // Keep the first catalogue case deliberately small: terminal arms have
        // no shared continuation whose evidence would need edge transport.
        if c.terminators[c.blocks[c.edges[yes].to].term].tag!=TERM_RETURN || c.terminators[c.blocks[c.edges[no].to].term].tag!=TERM_RETURN { return 0; }
        let selected:u32=if value.imm0!=0 {0}else{1}; let chosen=c.refs[term.edges.start+selected];
        b.terminators[basic.term].tag=TERM_JUMP; b.terminators[basic.term].subject=0; b.terminators[basic.term].edges=Span{term.edges.start+selected,1};
        b.edges[chosen].kind=EDGE_NORMAL; b.blocks[block_id].merge=0; return 5;
    }
    return 0;
}

fn rewrite_float(b:CoreBuilder,index:u32) -> bool {
    let op=b.ops[index]; if op.args.count==0 || op.args.count>2 || op.results.count!=1 { return false; }
    let left, known=constant(core_view(b),b.refs[op.args.start]); if !known { return false; }
    var right=Operation{..};
    if op.args.count==2 { let candidate, found=constant(core_view(b),b.refs[op.args.start+1]); if !found { return false; } right=candidate; }
    let tag=op.tag; var output=OP_F32; var bits:u32=0;
    if tag==OP_U32_TO_F32 && left.tag==OP_U32 { bits=static_bits(left.imm0 as f32); }
    else if tag==OP_F32_FROM_BITS && left.tag==OP_U32 { bits=left.imm0; }
    else if left.tag==OP_F32 {
        if tag==OP_F32_TO_BITS { bits=left.imm0; output=OP_U32; }
        else if tag==OP_F32_NEG { bits=left.imm0^0x80000000; }
        else if tag==OP_F32_ABS { bits=left.imm0&0x7fffffff; }
        else {
            if op.args.count==2 && right.tag!=OP_F32 { return false; }
            let x=static_f32(left.imm0); let y=static_f32(right.imm0); var value:f32=0.0;
            if tag>=OP_F32_EQ && tag<=OP_F32_GE {
                var truth=false; output=OP_BOOL;
                if tag==OP_F32_EQ {truth=x==y;} if tag==OP_F32_NE {truth=x!=y;} if tag==OP_F32_LT {truth=x<y;}
                if tag==OP_F32_LE {truth=x<=y;} if tag==OP_F32_GT {truth=x>y;} if tag==OP_F32_GE {truth=x>=y;}
                bits=if truth {1}else{0};
            } else {
                if tag==OP_F32_ADD {value=x+y;} else if tag==OP_F32_SUB {value=x-y;} else if tag==OP_F32_MUL {value=x*y;} else if tag==OP_F32_DIV {value=x/y;}
                else if tag==OP_F32_SQRT {value=sqrt(x);} else if tag==OP_F32_CEIL {value=ceil(x);} else if tag==OP_F32_FLOOR {value=floor(x);}
                else if tag==OP_F32_TRUNC {value=trunc(x);} else if tag==OP_F32_NEAREST {value=static_nearest(x);}
                else if tag==OP_F32_MIN || tag==OP_F32_MAX {
                    if x!=x || y!=y {value=static_f32(0x7fc00000);}
                    else if x==y {value=static_f32(if tag==OP_F32_MIN {left.imm0|right.imm0}else{left.imm0&right.imm0});}
                    else {value=if tag==OP_F32_MIN {min(x,y)}else{max(x,y)};}
                } else { return false; }
                bits=static_arithmetic_bits(value);
            }
        }
    } else { return false; }
    b.ops[index].tag=output; b.ops[index].registry=output; b.ops[index].args=Span{..}; b.ops[index].evidence=Span{..}; b.ops[index].imm0=bits; return true;
}
