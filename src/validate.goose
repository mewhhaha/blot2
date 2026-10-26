// Independent, bounded validator. No parser/checker pointers or inferred facts are consulted.
namespace validator;
import src.model;
import src.canonical;
import src.hash;
import src.coverage;
import src.layout_premises;
import std;

let FRESH: u32 = 0;
let OPTIONAL: u32 = 1;
let REQUIRED: u32 = 2;
struct DominanceEntry { definition:u32, target:u32, epoch:u32, result:bool }
// Rebuilt only from structurally checked Core. These are attempt-local lookup
// tables, never transported authority or a substitute for ownership validation.
struct ValidationIndex {
    op_blocks:const u32[:], op_positions:const u32[:], incoming:const u32[:],
    dominance:DominanceEntry[:], seen:u64[:], queue:u32[:], stamp:u64[:],
    plan_heads:const u32[:], plan_next:const u32[:], adapter_heads:const u32[:], adapter_next:const u32[:]
}
// Contexts borrow the enclosing attempt's immutable Core view. Origin/proof
// contexts copy account and index references, without copying every table span.
struct Context { c: const Core&, mode: u32, work: Work&, diags: Diagnostic[>..]&, visit_limit:u64 = LIMIT_VISITS, proof_limit:u64 = LIMIT_PROOF_VISITS, origin:u32 = 0, proof_mode:bool = false, indexes:ValidationIndex&? = null, epoch:u32 = 0 }
struct Geometry { dependent: bool, minimum: u32, min_nodes: u32, min_leaves: u32, min_guards: u32, size: u32, align: u32, plain: bool, share: bool, must_handle: bool, nodes: u32, leaves: u32, guards: u32, depth: u32 }
fn reject(v: Context, cause: u32, subject: u32) -> bool {
    // A caller may observe a false helper result after its account exhausted.
    // Preserve the original limit category instead of appending a type error.
    if v.work.exhausted && cause!=2030 && cause!=2032 && v.diags.len!=0 {
        let previous=v.diags[v.diags.len-1];if previous.detail==2030 || previous.detail==2032 {return false;}
    }
    var code = cause;
    if v.mode == REQUIRED { code = 2034; }
    v.diags.push(Diagnostic { code: code, origin: if v.mode==REQUIRED {0}else{diagnostic_origin(v.c,v.origin)}, detail: cause, related: subject });
    return false;
}
fn visit(v: Context, count: u64) -> bool {
    if !charge(v.work, count, v.visit_limit) { return reject(v, 2030, 0); }
    if v.proof_mode {
        if v.work.proof_visits>v.proof_limit || count>v.proof_limit-v.work.proof_visits {v.work.exhausted=true;return reject(v,2032,0);}
        v.work.proof_visits+=count;
    }
    return true;
}
fn proof_visit(v: Context, count: u64) -> bool {
    if !visit(v, count) { return false; }
    if v.proof_mode {return true;}
    if v.work.proof_visits > v.proof_limit || count > v.proof_limit - v.work.proof_visits { v.work.exhausted=true; return reject(v, 2032, 0); }
    v.work.proof_visits += count; return true;
}
fn refs_ok(v: Context, span: Span, length: i64) -> bool {
    if !span_ok(span, v.c.refs.len) { return false; }
    for i in span.count {
        if !visit(v, 1) || !id_ok(v.c.refs[span.start + i], length) { return false; }
    }
    return true;
}
fn at(c: Core, span: Span, index: u32) -> u32 { return c.refs[span.start + index]; }
fn contains(v:Context, span: Span, id: u32) -> bool {
    if !visit(v,1) { return false; }
    let c=v.c;
    for i in span.count { if !visit(v,1) { return false; } if at(c, span, i) == id { return true; } }
    return false;
}
fn structure(v: Context) -> bool {
    let c = v.c;
    if c.dictionary_realizations.len == 0 { return reject(v,2034,0); }
    for row, index in c.dictionary_realizations {
        if !visit(v,1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.type_id,c.types.len) || !id_ok(row.concrete_type,c.types.len) || !id_ok(row.layout,c.layouts.len) ||
            !refs_ok(v,row.parameters,c.binders.len) || !refs_ok(v,row.arguments,c.types.len) || row.parameters.count != row.arguments.count { return reject(v,2034,index as u32); }
    }
    if c.static_objects.len == 0 || c.static_relocations.len == 0 || c.callable_adapters.len == 0 || c.adapter_captures.len == 0 { return reject(v, 2034, 0); }
    for row, index in c.static_objects {
        if !visit(v,1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.type_id,c.types.len) || row.element_type != 0 && !id_ok(row.element_type,c.types.len) || row.domain != 0 && !id_ok(row.domain,c.binders.len) ||
            (row.function!=0 && !id_ok(row.function,c.functions.len)) || (row.constructor!=0 && !id_ok(row.constructor,c.ops.len)) || !span_ok(row.bytes,c.bytes.len) || row.bytes.count > 4194304 || !refs_ok(v,row.relocations,c.static_relocations.len) || row.producer != 0 && !id_ok(row.producer,c.definitions.len) || row.steps > 100000 { return reject(v,2034,index as u32); }
    }
    for row, index in c.static_relocations {
        if !visit(v,1) { return false; }
        if index == 0 { continue; }
        if row.kind == STATIC_ADDRESS { if !id_ok(row.target,c.static_objects.len) { return reject(v,2034,index as u32); } }
        else if row.kind == STATIC_FUNCTION { if !id_ok(row.target,c.functions.len) { return reject(v,2034,index as u32); } }
        else if row.kind == STATIC_DICTIONARY { if !id_ok(row.target,c.types.len) || row.addend!=0 { return reject(v,2034,index as u32); } }
        else if row.kind == STATIC_CLOSURE { if !id_ok(row.target,c.ops.len) || row.addend!=0 && !id_ok(row.addend,c.static_objects.len) { return reject(v,2034,index as u32); } }
        else { return reject(v,2034,index as u32); }
    }
    for row, index in c.callable_adapters {
        if !visit(v,1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.op,c.ops.len) || !id_ok(row.target_function,c.functions.len) || !id_ok(row.callback_contract,c.contracts.len) ||
            !refs_ok(v,row.captures,c.adapter_captures.len) || !id_ok(row.environment_layout,c.layouts.len) { return reject(v,2034,index as u32); }
    }
    for row, index in c.adapter_captures { if !visit(v,1) { return false from structure; }
        if index == 0 { continue; }
        if row.kind == KIND_TYPE { if !id_ok(row.source,c.types.len) { return reject(v,2034,index as u32); } }
        else if row.kind == KIND_NAT { if !id_ok(row.source,c.terms.len) { return reject(v,2034,index as u32); } }
        else { return reject(v,2004,index as u32); }
    }
    if c.names.len == 0 { return reject(v, 2034, 1); }
    for row, index in c.names {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !span_ok(row.bytes, c.bytes.len) { return reject(v, 2034, index as u32); }
    }
    if c.origins.len == 0 { return reject(v, 2034, 2); }
    for row, index in c.origins {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
    }
    if c.modules.len == 0 { return reject(v, 2034, 3); }
    for row, index in c.modules {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if row.name != 0 && !id_ok(row.name, c.names.len) { return reject(v, 2034, index as u32); }
        if row.path != 0 && !id_ok(row.path, c.names.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.imports, c.modules.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.declarations, c.definitions.len) { return reject(v, 2034, index as u32); }
        if !span_ok(row.source, c.bytes.len) { return reject(v, 2034, index as u32); }
    }
    if c.binders.len == 0 { return reject(v, 2034, 4); }
    for row, index in c.binders {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if row.introduction_kind == INTRO_NONE { if row.introduction != 0 { return reject(v,2034,index as u32); } }
        else if row.introduction_kind == INTRO_FUNCTION { if !id_ok(row.introduction,c.functions.len) || row.kind != KIND_REGION { return reject(v,2034,index as u32); } }
        else if row.introduction_kind == INTRO_OPERATION { if !id_ok(row.introduction,c.ops.len) { return reject(v,2034,index as u32); } }
        else { return reject(v,2034,index as u32); }
        if row.scope != 0 && !id_ok(row.scope, c.scopes.len) { return reject(v, 2034, index as u32); }
        if row.name != 0 && !id_ok(row.name, c.names.len) { return reject(v, 2034, index as u32); }
        if row.origin != 0 && !id_ok(row.origin, c.origins.len) { return reject(v, 2034, index as u32); }
    }
    if c.scopes.len == 0 { return reject(v, 2034, 5); }
    for row, index in c.scopes {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if row.parent != 0 && !id_ok(row.parent, c.scopes.len) { return reject(v, 2034, index as u32); }
        if row.binder != 0 && !id_ok(row.binder, c.binders.len) { return reject(v, 2034, index as u32); }
        if row.origin != 0 && !id_ok(row.origin, c.origins.len) { return reject(v, 2034, index as u32); }
    }
    if c.types.len == 0 { return reject(v, 2034, 6); }
    for row, index in c.types {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !refs_ok(v, row.children, c.types.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.fields, c.fields.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.binders, c.binders.len) { return reject(v, 2034, index as u32); }
        if row.region != 0 && !id_ok(row.region, c.binders.len) { return reject(v, 2034, index as u32); }
        if row.nat != 0 && !id_ok(row.nat, c.terms.len) { return reject(v, 2034, index as u32); }
        if row.domain != 0 && !id_ok(row.domain, c.binders.len) { return reject(v, 2034, index as u32); }
        if row.capacity != 0 && !id_ok(row.capacity, c.terms.len) { return reject(v, 2034, index as u32); }
        if row.contract != 0 && !id_ok(row.contract, c.contracts.len) { return reject(v, 2034, index as u32); }
        if row.binder != 0 && !id_ok(row.binder, c.binders.len) { return reject(v, 2034, index as u32); }
        if row.origin != 0 && !id_ok(row.origin, c.origins.len) { return reject(v, 2034, index as u32); }
    }
    if c.fields.len == 0 { return reject(v, 2034, 7); }
    for row, index in c.fields {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if row.name != 0 && !id_ok(row.name, c.names.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.type_id, c.types.len) { return reject(v, 2034, index as u32); }
    }
    if c.layout_premises.len==0 { return reject(v,2034,8); }
    for row,id in c.layout_premises { if !visit(v,1) { return false from structure; } if id!=0 && (!visit(v,1) || !id_ok(row.type_id,c.types.len) || row.kind!=LAYOUT_AGGREGATE && row.kind!=LAYOUT_PLAIN) { return reject(v,2034,id as u32); } }
    if c.contracts.len == 0 { return reject(v, 2034, 8); }
    for row, index in c.contracts {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !refs_ok(v,row.layout_premises,c.layout_premises.len) { return reject(v,2034,index as u32); }
        if !id_ok(row.arg, c.types.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.result, c.types.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.binders, c.binders.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.requires, c.facts.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.ensures, c.facts.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.on_true, c.facts.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.on_false, c.facts.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.effects, c.effects.len) { return reject(v, 2034, index as u32); }
        if row.origin != 0 && !id_ok(row.origin, c.origins.len) { return reject(v, 2034, index as u32); }
    }
    if c.effects.len == 0 { return reject(v, 2034, 9); }
    for row, index in c.effects {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if row.region != 0 && !id_ok(row.region, c.binders.len) { return reject(v, 2034, index as u32); }
    }
    if c.values.len == 0 { return reject(v, 2034, 10); }
    for row, index in c.values {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.type_id, c.types.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.block_id, c.blocks.len) { return reject(v, 2034, index as u32); }
        if row.op != 0 && !id_ok(row.op, c.ops.len) { return reject(v, 2034, index as u32); }
        if row.scope != 0 && !id_ok(row.scope, c.scopes.len) { return reject(v, 2034, index as u32); }
        if row.origin != 0 && !id_ok(row.origin, c.origins.len) { return reject(v, 2034, index as u32); }
    }
    if c.ops.len == 0 { return reject(v, 2034, 11); }
    for row, index in c.ops {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !refs_ok(v, row.args, c.values.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.results, c.values.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.evidence, c.evidence.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.substitutions, c.substitutions.len) { return reject(v, 2034, index as u32); }
        if row.scope != 0 && !id_ok(row.scope, c.scopes.len) { return reject(v, 2034, index as u32); }
        if row.origin != 0 && !id_ok(row.origin, c.origins.len) { return reject(v, 2034, index as u32); }
    }
    if c.blocks.len == 0 { return reject(v, 2034, 12); }
    for row, index in c.blocks {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if row.merge != 0 && (!id_ok(row.merge, c.blocks.len) || row.merge == index) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.params, c.values.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.evidence_params, c.evidence.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.ops, c.ops.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.term, c.terminators.len) { return reject(v, 2034, index as u32); }
        if row.scope != 0 && !id_ok(row.scope, c.scopes.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.function, c.functions.len) { return reject(v, 2034, index as u32); }
        if row.origin != 0 && !id_ok(row.origin, c.origins.len) { return reject(v, 2034, index as u32); }
    }
    if c.terminators.len == 0 { return reject(v, 2034, 13); }
    for row, index in c.terminators {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !refs_ok(v,row.evidence,c.evidence.len) { return reject(v,2034,index as u32); }
        if row.subject != 0 && !id_ok(row.subject, c.values.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.edges, c.edges.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.discharge, c.values.len) { return reject(v, 2034, index as u32); }
        if row.origin != 0 && !id_ok(row.origin, c.origins.len) { return reject(v, 2034, index as u32); }
    }
    if c.edges.len == 0 { return reject(v, 2034, 14); }
    for row, index in c.edges {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.from, c.blocks.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.to, c.blocks.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.args, c.values.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.evidence, c.evidence.len) { return reject(v, 2034, index as u32); }
        if row.loop_id != 0 && !id_ok(row.loop_id, c.loops.len) { return reject(v, 2034, index as u32); }
        if row.args.count != c.blocks[row.to].params.count || c.blocks[row.from].function != c.blocks[row.to].function || row.kind < EDGE_NORMAL || row.kind > EDGE_LOOP_STOP { return reject(v, 2034, index as u32); }
    }
    if c.terms.len == 0 { return reject(v, 2034, 15); }
    for row, index in c.terms {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.type_id, c.types.len) { return reject(v, 2034, index as u32); }
        if row.value != 0 && !id_ok(row.value, c.values.len) { return reject(v, 2034, index as u32); }
        if row.binder != 0 && row.tag != EXPR_ARG && row.tag != EXPR_RESULT && !id_ok(row.binder, c.binders.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.args, c.terms.len) { return reject(v, 2034, index as u32); }
        if row.scope != 0 && !id_ok(row.scope, c.scopes.len) { return reject(v, 2034, index as u32); }
    }
    if c.facts.len == 0 { return reject(v, 2034, 16); }
    for row, index in c.facts {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.left, c.terms.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.right, c.terms.len) { return reject(v, 2034, index as u32); }
        if row.third != 0 && !id_ok(row.third, c.terms.len) { return reject(v, 2034, index as u32); }
        if row.domain != 0 && !id_ok(row.domain, c.binders.len) { return reject(v, 2034, index as u32); }
    }
    if c.evidence.len == 0 { return reject(v, 2034, 17); }
    for row, index in c.evidence {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.fact, c.facts.len) || row.contract != 0 && !id_ok(row.contract, c.contracts.len) || row.formal_fact != 0 && !id_ok(row.formal_fact, c.facts.len) || row.call != 0 && !id_ok(row.call, c.ops.len) { return reject(v, 2034, index as u32); }
        if row.scope != 0 && !id_ok(row.scope, c.scopes.len) { return reject(v, 2034, index as u32); }
        if row.edge != 0 && !id_ok(row.edge, c.edges.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.operands, c.values.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.premises, c.evidence.len) { return reject(v, 2034, index as u32); }
        if row.origin != 0 && !id_ok(row.origin, c.origins.len) { return reject(v, 2034, index as u32); }
    }
    if c.loops.len == 0 { return reject(v, 2034, 18); }
    for row, index in c.loops {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.header, c.blocks.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.body, c.blocks.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.exit, c.blocks.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.index, c.values.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.lower, c.terms.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.upper, c.terms.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.carries, c.values.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.invariant, c.evidence.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.backedges, c.edges.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.exits, c.edges.len) { return reject(v, 2034, index as u32); }
    }
    if c.functions.len == 0 { return reject(v, 2034, 19); }
    for row, index in c.functions {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if row.name != 0 && !id_ok(row.name, c.names.len) { return reject(v, 2034, index as u32); }
        if row.module != 0 && !id_ok(row.module, c.modules.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.type_id, c.types.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.contract, c.contracts.len) { return reject(v, 2034, index as u32); }
        if row.param != 0 && !id_ok(row.param, c.values.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.entry, c.blocks.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.blocks, c.blocks.len) { return reject(v, 2034, index as u32); }
        if row.producer != 0 && (!id_ok(row.producer,c.definitions.len) || c.definitions[row.producer].kind==DEF_TYPE) { return reject(v,2034,index as u32); }
        if !refs_ok(v, row.environment_bindings, c.environment_bindings.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.captures, c.captures.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.calls, c.calls.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.binders, c.binders.len) { return reject(v, 2034, index as u32); }
        if row.origin != 0 && !id_ok(row.origin, c.origins.len) { return reject(v, 2034, index as u32); }
    }
    if c.calls.len == 0 { return reject(v, 2034, 20); }
    for row, index in c.calls {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.op, c.ops.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.caller, c.functions.len) { return reject(v, 2034, index as u32); }
        if row.callee != 0 && !id_ok(row.callee, c.functions.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.contract, c.contracts.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.substitutions, c.substitutions.len) { return reject(v, 2034, index as u32); }
    }
    if c.substitutions.len == 0 { return reject(v, 2034, 21); }
    for row, index in c.substitutions {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.binder, c.binders.len) { return reject(v, 2034, index as u32); }
    }
    if c.captures.len == 0 { return reject(v, 2034, 22); }
    for row, index in c.captures {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.function, c.functions.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.value, c.values.len) || !id_ok(row.local_value, c.values.len) { return reject(v, 2034, index as u32); }
        if row.scope != 0 && !id_ok(row.scope, c.scopes.len) { return reject(v, 2034, index as u32); }
    }
    if c.loans.len == 0 { return reject(v, 2034, 23); }
    for row, index in c.loans {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.value, c.values.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.owner, c.values.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.scope, c.scopes.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.begin_op, c.ops.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.end_op, c.ops.len) { return reject(v, 2034, index as u32); }
    }
    if c.transitions.len == 0 { return reject(v, 2034, 24); }
    for row, index in c.transitions {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.op, c.ops.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.value, c.values.len) { return reject(v, 2034, index as u32); }
        if row.before != 0 && !id_ok(row.before, c.values.len) { return reject(v, 2034, index as u32); }
        if row.after != 0 && !id_ok(row.after, c.values.len) { return reject(v, 2034, index as u32); }
        if row.scope != 0 && !id_ok(row.scope, c.scopes.len) { return reject(v, 2034, index as u32); }
    }
    if c.schemas.len == 0 { return reject(v, 2034, 25); }
    for row, index in c.schemas {
        if !visit(v,1) { return false; }
        if index == 0 { continue; }
        if !span_ok(row.bytes, c.bytes.len) || row.bytes.count > LIMIT_ARTIFACT || !span_ok(row.digest, c.bytes.len) || row.digest.count != 32 { return reject(v, 2034, index as u32); }
    }
    if c.layouts.len == 0 { return reject(v, 2034, 25); }
    for row, index in c.layouts {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.type_id, c.types.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.fields, c.fields.len) { return reject(v, 2034, index as u32); }
    }
    if c.interfaces.len == 0 { return reject(v, 2034, 26); }
    for row, index in c.interfaces {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.function, c.functions.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.type_id, c.types.len) { return reject(v, 2034, index as u32); }
        if !id_ok(row.contract, c.contracts.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.dependencies, c.dependencies.len) { return reject(v, 2034, index as u32); }
        if !span_ok(row.digest, c.bytes.len) { return reject(v, 2034, index as u32); }
    }
    if c.dependencies.len == 0 { return reject(v, 2034, 27); }
    for row, index in c.dependencies {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !span_ok(row.identity, c.bytes.len) { return reject(v, 2034, index as u32); }
        if !span_ok(row.digest, c.bytes.len) { return reject(v, 2034, index as u32); }
    }
    if c.receipts.len == 0 { return reject(v, 2034, 28); }
    for row, index in c.receipts {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !span_ok(row.source_digest, c.bytes.len) { return reject(v, 2034, index as u32); }
        if !span_ok(row.semantic_digest, c.bytes.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.dependencies, c.dependencies.len) { return reject(v, 2034, index as u32); }
    }
    if c.exports.len == 0 { return reject(v, 2034, 29); }
    for row, index in c.exports {
        if !visit(v, 1) { return false; }
        if index == 0 { continue; }
        if !id_ok(row.function, c.functions.len) { return reject(v, 2034, index as u32); }
        if row.name != 0 && !id_ok(row.name, c.names.len) { return reject(v, 2034, index as u32); }
        if !refs_ok(v, row.fields, c.fields.len) { return reject(v, 2034, index as u32); }
        if !span_ok(row.input_maxima, c.refs.len) { return reject(v, 2034, index as u32); }
        if !span_ok(row.abi_digest, c.bytes.len) { return reject(v, 2034, index as u32); }
    }
    for row, id in c.definitions { if !visit(v,1) { return false from structure; }
        if id == 0 { continue; }
        if row.kind < DEF_FUNCTION || row.kind > DEF_STATIC || !id_ok(row.type_id, c.types.len) ||
            row.name != 0 && !id_ok(row.name, c.names.len) || row.module != 0 && !id_ok(row.module, c.modules.len) ||
            row.function != 0 && !id_ok(row.function, c.functions.len) || row.value != 0 && !id_ok(row.value, c.values.len) ||
            !refs_ok(v, row.binders, c.binders.len) || row.visibility > VIS_PUBLIC { return reject(v, 2034, id as u32); }
    }
    for row, id in c.abi_plans { if !visit(v,1) { return false from structure; }
        if id == 0 { continue; }
        if row.function != 0 && !id_ok(row.function, c.functions.len) || !id_ok(row.contract, c.contracts.len) || !id_ok(row.arg_layout, c.layouts.len) ||
            !id_ok(row.result_layout, c.layouts.len) || row.env_layout != 0 && !id_ok(row.env_layout, c.layouts.len) ||
            !refs_ok(v, row.dictionaries, c.binders.len) || !refs_ok(v, row.nat_witnesses, c.nat_witnesses.len) || row.version != ABI_VERSION {
            return reject(v, 2034, id as u32);
        }
        let con = c.contracts[row.contract];
        if row.function != 0 && c.functions[row.function].contract != row.contract { return reject(v, 2034, id as u32); }
        if row.frame < con.frame || row.depth < con.depth || row.depth > 128 { return reject(v, 2023, id as u32); }
    }
    for row, id in c.nat_witnesses { if !visit(v,1) { return false from structure; }
        if id == 0 { continue; }
        if !id_ok(row.binder, c.binders.len) || c.binders[row.binder].kind != KIND_NAT ||
            !span_ok(row.argument_path, c.refs.len) || row.selector > NAT_PACKAGE_PREFIX { return reject(v, 2034, id as u32); }
    }
    for row, id in c.environment_bindings { if !visit(v,1) { return false from structure; }
        if id == 0 { continue; }
        if !id_ok(row.function, c.functions.len) || !id_ok(row.binder, c.binders.len) || row.kind != KIND_TYPE && row.kind != KIND_NAT ||
            c.binders[row.binder].kind != row.kind || row.offset % 4 != 0 || row.offset >= 256 || row.source_value != 0 && !id_ok(row.source_value, c.values.len) { return reject(v, 2034, id as u32); }
    }
    for row, i in c.binders { if !visit(v,1) { return false from structure; }
        if i == 0 { continue; }
        if row.kind < KIND_TYPE || row.kind > KIND_DOMAIN || row.constraints & ~3 != 0 { return reject(v, 2004, i as u32); }
        if row.kind != KIND_TYPE && row.constraints != 0 { return reject(v, 2004, i as u32); }
    }
    for row, i in c.scopes { if !visit(v,1) { return false from structure; }
        if i == 0 { continue; }
        if row.kind < SCOPE_MODULE || row.kind > SCOPE_OWNED { return reject(v, 2034, i as u32); }
        var parent = row.parent;
        var depth: u32 = 0;
        while parent != 0 {
            if !visit(v, 1) { return false; }
            if parent == i || depth >= LIMIT_NEST { return reject(v, 2034, i as u32); }
            parent = c.scopes[parent].parent; depth++;
        }
    }
    for row, i in c.ops { if !visit(v,1) { return false from structure; }
        if i == 0 { continue; }
        if row.tag == OP_INVALID || row.registry != row.tag || row.tag > OP_GENERIC_BIND || !registry_arity(row) { return reject(v, 2034, i as u32); }
    }
    for row, i in c.effects { if !visit(v,1) { return false from structure; }
        if i == 0 { continue; }
        if row.kind < EFFECT_READ || row.kind > EFFECT_HOST { return reject(v, 2006, i as u32); }
        if row.region != 0 && c.binders[row.region].kind != KIND_REGION { return reject(v, 2004, i as u32); }
    }
    return true;
}

fn in_scope(v: Context, inner: u32, outer: u32) -> bool {
    if outer == 0 { return true; }
    var current = inner;
    for depth in 65 {
        if !visit(v, 1) { return false; }
        if current == outer { return true; }
        if current == 0 { return false; }
        current = v.c.scopes[current].parent;
    }
    return false;
}
fn type_child(c: Core, t: TypeNode, i: u32) -> u32 {
    if t.fields.count != 0 { return c.fields[at(c, t.fields, i)].type_id; }
    return at(c, t.children, i);
}
fn type_count(t: TypeNode) -> u32 {
    if t.fields.count != 0 { return t.fields.count; } return t.children.count;
}
recursive fn type_node(v: Context, id: u32, colors: u32[>..]&, geometry: Geometry[>..]&, depth: u32, stamp: u32 = 1) -> bool {
    if !visit(v, 1) { return false; }
    if colors[id] == stamp + 1 { return true; }
    if colors[id] == stamp || depth > LIMIT_NEST { return reject(v, 2024, id); }
    colors[id] = stamp;
    let c = v.c;
    let t = c.types[id];
    if t.tag < TY_UNIT || t.tag > TY_OWNED_CONSTRUCTION { return reject(v, 2034, id); }
    if t.region != 0 && c.binders[t.region].kind != KIND_REGION { return reject(v, 2004, id); }
    if t.domain != 0 && c.binders[t.domain].kind != KIND_DOMAIN { return reject(v, 2004, id); }
    if t.binders.count > LIMIT_BINDERS { return reject(v, 2031, id); }
    let n = type_count(t);
    if t.fields.count != 0 && (t.tag==TY_RECORD || t.tag==TY_SUM || t.tag==TY_RESULT) {
        for i in t.fields.count { if !visit(v,1) { return false from type_node; }
            let field=c.fields[at(c,t.fields,i)];
            if field.name==0 || (t.tag==TY_SUM || t.tag==TY_RESULT) && field.tag!=i { return reject(v,2003,id); }
            for j in i { if !visit(v,1) { return false from type_node; } if name_bytes(c,field.name)==name_bytes(c,c.fields[at(c,t.fields,j)].name) { return reject(v,2003,id); } }
        }
    }
    var g = Geometry { dependent: false, minimum: 0, min_nodes: 1, min_leaves: 0, min_guards: 0, size: 0, align: 1, plain: true, share: true, must_handle: false, nodes: 1, leaves: 0, guards: 0, depth: 1 };
    for i in n { if !visit(v,1) { return false from type_node; }
        let child = type_child(c, t, i);
        if !type_node(v, child, colors, geometry, depth + 1, stamp) { return false; }
        let cg = geometry[child];
        if t.tag==TY_TUPLE || t.tag==TY_RECORD || t.tag==TY_SUM || t.tag==TY_RESULT || t.tag==TY_EXISTS || t.tag==TY_ALIAS || t.tag==TY_FORALL { g.dependent=g.dependent || cg.dependent; }
        if !g.dependent && (g.nodes > 8192 - cg.nodes || g.leaves > 8192 - cg.leaves || g.guards > 8192 - cg.guards) { return reject(v, 2024, id); }
        g.min_nodes += cg.min_nodes; g.min_leaves += cg.min_leaves; g.min_guards += cg.min_guards;
        g.nodes += cg.nodes; g.leaves += cg.leaves; g.guards += cg.guards;
        if cg.depth + 1 > g.depth { g.depth = cg.depth + 1; }
        g.plain = g.plain && cg.plain; g.share = g.share && cg.share;
        g.must_handle = g.must_handle || cg.must_handle;
        if t.tag == TY_SUM || t.tag == TY_RESULT {
            if cg.size > g.size { g.size = cg.size; }
            if cg.minimum > g.minimum { g.minimum = cg.minimum; }
        } else if t.tag == TY_TUPLE || t.tag == TY_RECORD || t.tag == TY_ALIAS || t.tag == TY_EXISTS || t.tag == TY_FORALL {
            g.size += cg.size; g.minimum += cg.minimum;
        }
    }
    if t.tag == TY_UNIT { if n != 0 { return reject(v, 2003, id); } }
    else if t.tag == TY_BOOL || t.tag == TY_U32 || t.tag == TY_F32 || t.tag == TY_INDEX {
        if n != 0 { return reject(v, 2003, id); }
        g.size = 4; g.minimum = 4; g.leaves = 1; g.min_leaves = 1;
        if t.tag == TY_BOOL || t.tag == TY_INDEX { g.guards = 1; g.min_guards = 1; }
        if t.tag == TY_INDEX && (t.domain == 0 || t.nat == 0) { return reject(v, 2012, id); }
    } else if t.tag == TY_TUPLE || t.tag == TY_RECORD { }
    else if t.tag == TY_SUM || t.tag == TY_RESULT {
        if n == 0 || n > 4 || (t.tag == TY_RESULT && n != 2) || !g.dependent && g.size > 252 { return reject(v, 2024, id); }
        g.size += 4; g.minimum += 4; g.guards += 1; g.min_guards += 1;
        if t.tag == TY_RESULT { g.plain = false; g.share = false; g.must_handle = true; }
    } else if t.tag == TY_ALIAS {
        if n != 1 { return reject(v, 2003, id); }
        g = geometry[type_child(c, t, 0)];
    } else if t.tag == TY_EXISTS || t.tag == TY_FORALL {
        if n != 1 { return reject(v, 2003, id); }
        for i in t.binders.count { if !visit(v,1) { return false from type_node; }
            let binder = c.binders[at(c, t.binders, i)];
            if t.tag == TY_EXISTS && binder.kind != KIND_NAT && binder.kind != KIND_DOMAIN { return reject(v, 2004, id); }
            if t.tag == TY_EXISTS && binder.kind == KIND_NAT { g.size += 4; g.minimum += 4; g.leaves++; g.nodes++; g.min_leaves++; g.min_nodes++; }
        }
        if !g.dependent && g.size > 256 { return reject(v, 2024, id); }
    } else if t.tag == TY_PARAM {
        if n != 0 || t.binder == 0 || c.binders[t.binder].kind != KIND_TYPE { return reject(v, 2004, id); }
        let constraints = c.binders[t.binder].constraints; g.dependent=true;
        g.plain = constraints & CONSTRAINT_PLAIN != 0;
        g.share = constraints & (CONSTRAINT_PLAIN | CONSTRAINT_SHARE) != 0;
        g.size = 256;
        if g.plain { g.size = 64; }
        g.nodes = 32; g.leaves = 64; g.guards = 32;
    } else if t.tag == TY_VIEW || t.tag == TY_DEST || t.tag == TY_BUILDER {
        if n != 1 || t.nat == 0 && t.tag != TY_DEST { return reject(v, 2003, id); }
        if !geometry[type_child(c,t,0)].plain { return reject(v,if plain_structure(v,type_child(c,t,0),0) {2024} else {2003},id); }
        if t.tag != TY_VIEW && t.region == 0 { return reject(v, 2016, id); }
        if t.tag == TY_VIEW && t.domain == 0 { return reject(v, 2012, id); }
        if t.tag != TY_VIEW && t.capacity == 0 { return reject(v, 2026, id); }
        if t.tag == TY_BUILDER && c.terms[t.nat].tag == EXPR_LITERAL && c.terms[t.capacity].tag == EXPR_LITERAL && c.terms[t.nat].literal > c.terms[t.capacity].literal { return reject(v, 2018, id); }
        if t.tag == TY_BUILDER && t.mode != MODE_APPEND && t.mode != MODE_RESIZE { return reject(v, 2003, id); }
        g.size = 8; if t.tag == TY_BUILDER { g.size = 12; }
        g.plain = false; g.share = t.tag == TY_VIEW;
    } else if t.tag == TY_FN {
        if n != 2 || t.contract == 0 || t.mode != MODE_MANY && t.mode != MODE_ONCE { return reject(v, 2026, id); }
        if c.contracts[t.contract].arg != type_child(c, t, 0) || c.contracts[t.contract].result != type_child(c, t, 1) { return reject(v, 2003, id); }
        g.size = 8; g.plain = false; g.share = t.mode == MODE_MANY; g.must_handle = false;
    } else if t.tag == TY_OWNED {
        if n != 1 || !geometry[type_child(c, t, 0)].share || t.binders.count != 1 || c.binders[at(c, t.binders, 0)].kind != KIND_REGION || !owned_payload(v, type_child(c, t, 0), at(c, t.binders, 0), 0) { return reject(v, 2020, id); }
        g.size = 8; g.plain = false; g.share = false;
    } else if t.tag == TY_REGION_OWNER || t.tag == TY_OWNED_CONSTRUCTION || t.tag == TY_SPACE || t.tag == TY_ENV_DEST {
        if n != 0 || t.region == 0 { return reject(v, 2003, id); }
        g.size = 8; g.plain = false; g.share = false;
    } else { return reject(v, 2028, id); }
    if !g.dependent { g.minimum=g.size; g.min_nodes=g.nodes; g.min_leaves=g.leaves; g.min_guards=g.guards; }
    if g.minimum > 256 || g.size > 256 && !g.dependent || g.depth > 64 { return reject(v, 2024, id); }
    if g.dependent && g.size > 256 { g.size=256; }
    if g.plain && (g.minimum > 64 || g.min_nodes > 32 || g.min_leaves > 64 || g.min_guards > 32 || !g.dependent && (g.size > 64 || g.nodes > 32 || g.leaves > 64 || g.guards > 32)) { g.plain = false; }
    if g.dependent { g.nodes=min(g.nodes,8192); g.leaves=min(g.leaves,8192); g.guards=min(g.guards,8192); }
    if g.size != 0 { g.align = 4; }
    geometry[id] = g; colors[id] = stamp + 1; return true;
}
fn equal_fact(a: Fact, b: Fact) -> bool {
    return a.tag == b.tag && a.left == b.left && a.right == b.right && a.third == b.third && a.domain == b.domain && a.version == b.version;
}
fn literal_fact(v: Context, f: Fact) -> bool {
    let a, a_known = literal_term(v, f.left, 0); let b, b_known = literal_term(v, f.right, 0);
    if !a_known || !b_known { return false; }
    let x = a as u64; let y = b as u64;
    if f.tag == FACT_EQ { return x == y; }
    if f.tag == FACT_LT { return x < y; }
    if f.tag == FACT_LE { return x <= y; }
    if f.tag == FACT_ADD_FITS { return x + y <= MAX_U32; }
    if f.tag == FACT_SUB_FITS { return y <= x; }
    if f.tag == FACT_MUL_FITS { return x * y <= MAX_U32; }
    return false;
}
recursive fn literal_term(v: Context, id: u32, depth: u32) -> u32, bool {
    if !proof_visit(v, 1) || depth > LIMIT_TERMS { return 0, false; }
    let c = v.c; let term = c.terms[id];
    if term.tag == EXPR_LITERAL { return term.literal, true; }
    if term.tag == EXPR_MAX_MINUS && term.args.count == 1 {
        let x, known = literal_term(v, at(c, term.args, 0), depth + 1);
        return 0xffffffff - x, known;
    }
    if term.args.count != 2 || term.tag != EXPR_ADD && term.tag != EXPR_SUB && term.tag != EXPR_MUL { return 0, false; }
    let a, a_known = literal_term(v, at(c, term.args, 0), depth + 1); let b, b_known = literal_term(v, at(c, term.args, 1), depth + 1);
    if !a_known || !b_known { return 0, false; }
    if term.tag == EXPR_SUB { if a < b { return 0, false; } return a - b, true; }
    var result: u64 = 0;
    if term.tag == EXPR_ADD { result = (a as u64) + b; } else { result = (a as u64) * b; }
    if result > MAX_U32 { return 0, false; }
    return result as u32, true;
}
fn value_term(v:Context, term_id: u32, value: u32) -> bool {
    if !visit(v,1) { return false; }
    let c=v.c;
    let t = c.terms[term_id];
    if t.tag == EXPR_VALUE { return t.value == value && t.version == c.values[value].version; }
    if t.tag == EXPR_LITERAL && c.values[value].op != 0 {
        let op = c.ops[c.values[value].op];
        if op.tag == OP_U32 { return op.imm0 == t.literal; }
        if op.tag == OP_STATIC && id_ok(op.imm0,c.static_objects.len) {
            let object=c.static_objects[op.imm0];
            return object.kind==STATIC_VALUE && object.bytes.count==4 && object.relocations.count==0 && c.types[terminal(v,object.type_id)].tag==TY_U32 && static_word(c,object.bytes,0)==t.literal;
        }
        return false;
    }
    return false;
}
fn term_structure(parent:Context) -> bool {
    let v=proof_context(parent);
    let c = v.c;
    for t, id in c.terms {
        if !proof_visit(v, 1) { return false; }
        if id == 0 { continue; }
        if t.tag < EXPR_LITERAL || t.tag > EXPR_RESULT { return reject(v, 2027, id as u32); }
        if t.tag == EXPR_ARG || t.tag == EXPR_RESULT {
            if !id_ok(t.binder, c.contracts.len) || t.args.count != 0 || t.value != 0 { return reject(v, 2034, id as u32); }
            let contract = c.contracts[t.binder]; var wanted = contract.arg; if t.tag == EXPR_RESULT { wanted = contract.result; }
            if t.type_id != wanted { return reject(v, 2003, id as u32); }
        } else if t.tag == EXPR_FIELD {
            if t.args.count != 1 { return reject(v, 2034, id as u32); }
            let parent = at(c, t.args, 0); if parent >= id { return reject(v, 2034, id as u32); }
            let ty = c.types[c.terms[parent].type_id];
            if ty.tag != TY_TUPLE && ty.tag != TY_RECORD || t.literal >= type_count(ty) || !same_type(v, type_child(c, ty, t.literal), t.type_id, 0) { return reject(v, 2003, id as u32); }
        } else if t.tag == EXPR_LITERAL { if t.value != 0 || t.args.count != 0 { return reject(v, 2034, id as u32); } }
        else if t.tag == EXPR_BINDER {
            if t.binder == 0 || c.binders[t.binder].kind != KIND_NAT { return reject(v, 2004, id as u32); }
        } else if t.tag == EXPR_VALUE || t.tag == EXPR_LEN || t.tag == EXPR_CAP || t.tag == EXPR_INIT {
            if t.value == 0 && t.tag != EXPR_VALUE && t.args.count == 1 {
                let base = at(c, t.args, 0); if base >= id { return reject(v, 2034, id as u32); }
                let ty = c.types[c.terms[base].type_id].tag;
                if t.tag == EXPR_LEN && ty != TY_VIEW || t.tag == EXPR_INIT && ty != TY_BUILDER || t.tag == EXPR_CAP && ty != TY_DEST && ty != TY_BUILDER { return reject(v, 2003, id as u32); }
                continue;
            }
            if t.value == 0 || t.version != c.values[t.value].version { return reject(v, 2034, id as u32); }
            let ty = c.types[c.values[t.value].type_id].tag;
            if t.tag == EXPR_VALUE && t.type_id != c.values[t.value].type_id { return reject(v, 2003, id as u32); }
            if t.tag == EXPR_LEN && ty != TY_VIEW || t.tag == EXPR_INIT && ty != TY_BUILDER || t.tag == EXPR_CAP && ty != TY_DEST && ty != TY_BUILDER { return reject(v, 2003, id as u32); }
        } else {
            // Arithmetic terms must have explicit, earlier provenance. This is a DAG, never a symbolic expression solver.
            for i in t.args.count { if !proof_visit(v,1) { return false from term_structure; } if at(c, t.args, i) >= id { return reject(v, 2034, id as u32); } }
            if t.tag == EXPR_MAX_MINUS && t.args.count != 1 || t.tag >= EXPR_ADD && t.args.count != 2 { return reject(v, 2034, id as u32); }
        }
    }
    for f, id in c.facts {
        if !proof_visit(v, 1) { return false; }
        if id == 0 { continue; }
        if c.types[c.terms[f.left].type_id].tag != TY_U32 || c.types[c.terms[f.right].type_id].tag != TY_U32 { return reject(v, 2003, id as u32); }
        if f.tag < FACT_EQ || f.tag > FACT_INDEX { return reject(v, 2027, id as u32); }
        if f.tag == FACT_INDEX && (f.domain == 0 || c.binders[f.domain].kind != KIND_DOMAIN) { return reject(v, 2012, id as u32); }
        if f.tag != FACT_INDEX && f.domain != 0 { return reject(v, 2034, id as u32); }
    }
    return true;
}

fn compare_fact(v: Context, evidence: Evidence, fact: Fact) -> bool {
    let c = v.c;
    if evidence.edge == 0 || evidence.operands.count != 1 { return false; }
    let edge = c.edges[evidence.edge];
    let terminator = c.terminators[c.blocks[edge.from].term];
    let condition = at(c, evidence.operands, 0);
    if terminator.tag != TERM_BRANCH || !contains(v, terminator.edges, evidence.edge) || terminator.subject != condition || c.values[condition].op == 0 { return false; }
    var yes = evidence.rule == RULE_COMPARE_TRUE;
    if yes && edge.kind != EDGE_TRUE || !yes && edge.kind != EDGE_FALSE { return false; }
    return comparison_value_fact(v,condition,yes,fact);
}
fn comparison_value_fact(v:Context,condition:u32,truth:bool,fact:Fact)->bool {
    let c=v.c; if c.values[condition].op==0 { return false; } var yes=truth;
    var op = c.ops[c.values[condition].op];
    for nesting in LIMIT_NEST {
        if !proof_visit(v, 1) { return false; }
        if op.tag != OP_BOOL_NOT { break; }
        if op.args.count != 1 { return false; }
        let input = at(c, op.args, 0); if c.values[input].op == 0 { return false; }
        yes = !yes; op = c.ops[c.values[input].op];
    }
    if op.args.count != 2 { return false; }
    let left = at(c, op.args, 0); let right = at(c, op.args, 1);
    if op.tag == OP_U32_NE && yes || op.tag == OP_U32_EQ && !yes {
        if fact.tag != FACT_LT { return false; }
        let a, ak = literal_value(c, left); let b, bk = literal_value(c, right);
        return ak && a == 0 && term_literal(c, fact.left, 0) && term_operand(v, fact.right, right) ||
            bk && b == 0 && term_literal(c, fact.left, 0) && term_operand(v, fact.right, left) ||
            ak && a == 0xffffffff && term_operand(v, fact.left, right) && term_literal(c, fact.right, 0xffffffff) ||
            bk && b == 0xffffffff && term_operand(v, fact.left, left) && term_literal(c, fact.right, 0xffffffff);
    }
    if !yes && op.tag == OP_SUB_FITS { return fact.tag == FACT_LT && term_operand(v,fact.left,left) && term_operand(v,fact.right,right); }
    if !yes && op.tag == OP_ADD_FITS {
        let complement=c.terms[fact.left];
        return fact.tag == FACT_LT && complement.tag == EXPR_MAX_MINUS && complement.args.count == 1 && term_operand(v,at(c,complement.args,0),left) && term_operand(v,fact.right,right);
    }
    var tag = FACT_INVALID;
    var reverse = false;
    if op.tag == OP_U32_LT { if yes { tag = FACT_LT; } else { tag = FACT_LE; reverse = true; } }
    else if op.tag == OP_U32_LE { if yes { tag = FACT_LE; } else { tag = FACT_LT; reverse = true; } }
    else if op.tag == OP_U32_GT { if yes { tag = FACT_LT; reverse = true; } else { tag = FACT_LE; } }
    else if op.tag == OP_U32_GE { if yes { tag = FACT_LE; reverse = true; } else { tag = FACT_LT; } }
    else if op.tag == OP_U32_EQ && yes || op.tag == OP_U32_NE && !yes { tag = FACT_EQ; }
    else if op.tag == OP_ADD_FITS && yes { tag = FACT_ADD_FITS; }
    else if op.tag == OP_SUB_FITS && yes { tag = FACT_SUB_FITS; }
    else if op.tag == OP_MUL_FITS && yes { tag = FACT_MUL_FITS; }
    if fact.tag != tag { return false; }
    if reverse { return term_operand(v, fact.left, right) && term_operand(v, fact.right, left); }
    return term_operand(v, fact.left, left) && term_operand(v, fact.right, right);
}
recursive fn evidence_node(parent:Context, id: u32, colors: u32[>..]&, depth: u32) -> bool {
    let v=proof_context(parent);
    if !proof_visit(v, 1) { return false; }
    if colors[id] == 2 { return true; }
    if colors[id] == 1 || depth > LIMIT_TERMS { return reject(v, 2034, id); }
    colors[id] = 1;
    let c = v.c; let e = c.evidence[id]; let f = c.facts[e.fact];
    for i in e.premises.count { if !proof_visit(v,1) { return false from evidence_node; }
        let p = at(c, e.premises, i);
        if !evidence_node(v, p, colors, depth + 1) { return false; }
        if e.rule != RULE_JOIN && e.rule != RULE_CAPTURE && !in_scope(v, e.scope, c.evidence[p].scope) { return reject(v, 2034, id); }
        // Conditional prerequisites keep their own edge authority; every use recursively checks it.
    }
    var ok = false;
    if e.rule == RULE_REFLEXIVE {
        ok = e.premises.count == 0 && (f.tag == FACT_EQ || f.tag == FACT_LE) && f.left == f.right;
    } else if e.rule == RULE_LITERAL || e.rule == RULE_CONST_EVAL {
        ok = e.premises.count == 0 && literal_fact(v, f);
    } else if e.rule == RULE_U32_BOUNDS {
        let left = c.terms[f.left]; let right = c.terms[f.right];
        ok = f.tag == FACT_LE && (left.tag == EXPR_LITERAL && left.literal == 0 || right.tag == EXPR_LITERAL && right.literal == 0xffffffff);
    } else if e.rule == RULE_COMPARE_TRUE || e.rule == RULE_COMPARE_FALSE {
        ok = e.premises.count == 0 && compare_fact(v, e, f);
    } else if e.rule == RULE_ASSUMPTION {
        if !id_ok(e.contract, c.contracts.len) || !id_ok(e.formal_fact, c.facts.len) || e.call != 0 || e.operands.count != 1 { return reject(v, 2034, id); }
        for fun, fi in c.functions {
            if !proof_visit(v, 1) { return false; }
            if fi == 0 { continue; }
            if fun.contract == e.contract && c.blocks[fun.entry].scope == e.scope && at(c, e.operands, 0) == fun.param &&
                contains(v, c.contracts[fun.contract].requires, e.formal_fact) &&
                instantiated_fact(v, c.facts[e.formal_fact], f, fun.param, 0, Span {..}) { ok = true; }
        }
    } else if e.rule == RULE_CONTRACT {
        if !id_ok(e.contract, c.contracts.len) || !id_ok(e.formal_fact, c.facts.len) || !id_ok(e.call, c.ops.len) || e.operands.count != 2 { return reject(v, 2034, id); }
        let call = c.ops[e.call];
        var argument_index: u32 = 0;
        if call.tag == OP_CALL_INDIRECT { argument_index = 1; }
        if call.tag != OP_CALL && call.tag != OP_CALL_INDIRECT || call.args.count != argument_index + 1 || call.results.count != 1 { return reject(v, 2034, id); }
        if call.tag == OP_CALL && (!id_ok(call.imm0, c.functions.len) || c.functions[call.imm0].contract != e.contract) { return reject(v, 2034, id); }
        if call.tag == OP_CALL_INDIRECT { let callable = c.types[terminal(v, c.values[at(c, call.args, 0)].type_id)]; if callable.tag != TY_FN || callable.contract != e.contract { return reject(v, 2034, id); } }
        let arg = at(c, call.args, argument_index); let result = at(c, call.results, 0); let contract = c.contracts[e.contract];
        var clause = contract.ensures;
        if e.edge != 0 {
            let edge = c.edges[e.edge]; let term = c.terminators[c.blocks[edge.from].term];
            if term.tag != TERM_BRANCH || !contains(v, term.edges, e.edge) { return reject(v, 2034, id); }
            if edge.kind != EDGE_TRUE && edge.kind != EDGE_FALSE { return reject(v,2034,id); }
            let truth=edge.kind==EDGE_TRUE;
            if contains(v,contract.on_true,e.formal_fact) && boolean_implies(v,term.subject,truth,result,true,0) { clause=contract.on_true; }
            else if contains(v,contract.on_false,e.formal_fact) && boolean_implies(v,term.subject,truth,result,false,0) { clause=contract.on_false; }
            else { return reject(v,2034,id); }
        }
        ok = at(c, e.operands, 0) == arg && at(c, e.operands, 1) == result && contains(v, clause, e.formal_fact) &&
            instantiated_fact(v, c.facts[e.formal_fact], f, arg, result, call.substitutions);
    } else if e.rule == RULE_TRANSITIVE && e.premises.count == 2 {
        let p = c.facts[c.evidence[at(c, e.premises, 0)].fact];
        let q = c.facts[c.evidence[at(c, e.premises, 1)].fact];
        if p.left == f.left && p.right == q.left && q.right == f.right && p.tag >= FACT_EQ && p.tag <= FACT_LE && q.tag >= FACT_EQ && q.tag <= FACT_LE {
            if f.tag == FACT_EQ { ok = p.tag == FACT_EQ && q.tag == FACT_EQ; }
            if f.tag == FACT_LE { ok = true; }
            if f.tag == FACT_LT { ok = p.tag == FACT_LT || q.tag == FACT_LT; }
        }
    } else if e.rule == RULE_SUB_FROM_LE && e.premises.count == 1 {
        let p = c.facts[c.evidence[at(c, e.premises, 0)].fact];
        ok = (f.tag == FACT_SUB_FITS && p.tag == FACT_LE || f.tag == FACT_LE && p.tag == FACT_SUB_FITS) && p.left == f.right && p.right == f.left;
    } else if e.rule == RULE_ADD_FROM_COMPLEMENT && e.premises.count == 1 {
        let p = c.facts[c.evidence[at(c, e.premises, 0)].fact]; let rhs = c.terms[p.right];
        ok = f.tag == FACT_ADD_FITS && p.tag == FACT_LE && p.left == f.left && rhs.tag == EXPR_MAX_MINUS && rhs.args.count == 1 && at(c, rhs.args, 0) == f.right;
        if !ok && f.tag == FACT_LE && p.tag == FACT_ADD_FITS {
            let complement = c.terms[f.right];
            ok = p.left == f.left && complement.tag == EXPR_MAX_MINUS && complement.args.count == 1 && at(c, complement.args, 0) == p.right;
        }
    } else if e.rule == RULE_MUL_CONSTANT {
        ok = f.tag == FACT_MUL_FITS && literal_fact(v, f);
        let a = c.terms[f.left]; let b = c.terms[f.right];
        if a.tag == EXPR_LITERAL && a.literal == 0 || b.tag == EXPR_LITERAL && b.literal == 0 { ok = f.tag == FACT_MUL_FITS; }
        if !ok && e.premises.count == 1 && b.tag == EXPR_LITERAL && b.literal != 0 {
            let p = c.facts[c.evidence[at(c, e.premises, 0)].fact]; let rhs = c.terms[p.right];
            ok = f.tag == FACT_MUL_FITS && p.tag == FACT_LE && p.left == f.left && rhs.tag == EXPR_LITERAL && rhs.literal <= 0xffffffff / b.literal;
        }
    } else if e.rule == RULE_EQUALITY && e.premises.count == 2 {
        let eq = c.facts[c.evidence[at(c, e.premises, 0)].fact];
        let p = c.facts[c.evidence[at(c, e.premises, 1)].fact];
        if eq.tag == FACT_EQ && f.tag == p.tag && f.domain == p.domain && f.version == p.version && f.third == p.third {
            ok = f.left == p.left && (f.right == eq.left && p.right == eq.right || f.right == eq.right && p.right == eq.left) ||
                 f.right == p.right && (f.left == eq.left && p.left == eq.right || f.left == eq.right && p.left == eq.left);
        }
    } else if e.rule == RULE_ADD_SYMMETRY && e.premises.count == 1 {
        let premise = c.facts[c.evidence[at(c,e.premises,0)].fact];
        ok = f.tag == FACT_ADD_FITS && premise.tag == FACT_ADD_FITS && f.left == premise.right && f.right == premise.left;
    } else if e.rule == RULE_COMPLEMENT_ORDER && e.premises.count == 1 {
        let premise = c.facts[c.evidence[at(c,e.premises,0)].fact];
        let left = c.terms[f.left]; let right = c.terms[f.right];
        ok = (f.tag == FACT_LE || f.tag == FACT_LT || f.tag == FACT_EQ) && f.tag == premise.tag && left.tag == EXPR_MAX_MINUS && right.tag == EXPR_MAX_MINUS &&
            left.args.count == 1 && right.args.count == 1 && at(c,left.args,0) == premise.right && at(c,right.args,0) == premise.left;
        if !ok && f.tag == premise.tag && (f.tag == FACT_LE || f.tag == FACT_LT || f.tag == FACT_EQ) {
            let a = c.terms[premise.left]; let b = c.terms[premise.right];
            ok = a.tag == EXPR_MAX_MINUS && b.tag == EXPR_MAX_MINUS && a.args.count == 1 && b.args.count == 1 && at(c,a.args,0) == f.right && at(c,b.args,0) == f.left;
        }
    } else if e.rule == RULE_CHECKED_SUCCESS { ok = checked_success(v, e, f) || checked_congruence(v, e, f);
    } else if e.rule == RULE_CAPTURE { ok = capture_fact(v,e,f);
    } else if e.rule == RULE_BOOL_PATH { ok = boolean_fact(v,e,f);
    } else if e.rule == RULE_LEN { ok = observation_fact(v, e, f);
    } else if e.rule == RULE_LOOP_RANGE { ok = loop_range(v, e, f);
    } else if e.rule == RULE_LOOP_INVARIANT { ok = loop_assumption(v, id);
    } else if e.rule == RULE_JOIN { ok = join_evidence(v, id);
    } else if e.rule == RULE_SUCCESSOR { ok = successor_fact(v, e, f);
    } else if e.rule == RULE_INDEX_BOUND && (e.operands.count == 1 || e.operands.count == 2) && e.premises.count == 0 {
        let value = at(c, e.operands, 0); let ty = c.types[c.values[value].type_id]; var raw = value;
        if e.operands.count == 2 {
            raw = at(c, e.operands, 1); let definition = c.values[raw].op;
            if definition == 0 || c.ops[definition].tag != OP_INDEX_VALUE || at(c, c.ops[definition].args, 0) != value { return reject(v, 2034, id); }
        }
        ok = ty.tag == TY_INDEX && f.tag == FACT_LT && value_term(v, f.left, raw) && f.right == ty.nat;
    } else { return reject(v, 2027, id); }
    if !ok { return reject(v, 2034, id); }
    colors[id] = 2; return true;
}
// Each stored edge counts, including one not listed by its source terminator.
// This preserves the conservative authority test for hostile unused edges.
fn index_core(v:Context,op_blocks:u32[>..]&,op_positions:u32[>..]&,incoming:u32[>..]&) -> bool {
    for op in v.c.ops { op_blocks.push(0); op_positions.push(0); }
    for basic in v.c.blocks { incoming.push(0); }
    for basic,id in v.c.blocks {
        if !visit(v,1) { return false; } if id==0 { continue; }
        for i in basic.ops.count {
            if !visit(v,1) { return false; } let operation=at(v.c,basic.ops,i);
            // The first occurrence matches operation_block's scan. Duplicate
            // membership still rejects in independent function ownership checks.
            if op_blocks[operation]==0 { op_blocks[operation]=id as u32; op_positions[operation]=i; }
        }
    }
    for edge,id in v.c.edges { if !visit(v,1) { return false; } if id!=0 { incoming[edge.to]++; } }
    return true;
}
// Keep every row, including repeated owners and contract-only ABI plans.
// Reverse insertion preserves the original ascending table traversal order.
fn index_layout_owners(v:Context,plan_heads:u32[>..]&,plan_next:u32[>..]&,adapter_heads:u32[>..]&,adapter_next:u32[>..]&) -> bool {
    let c=v.c;
    for function in c.functions { plan_heads.push(0); }
    for plan in c.abi_plans { plan_next.push(0); }
    for operation in c.ops { adapter_heads.push(0); }
    for adapter in c.callable_adapters { adapter_next.push(0); }
    var cursor=c.abi_plans.len;
    while cursor>1 {
        if !visit(v,1) { return false; } cursor--; let plan=c.abi_plans[cursor];
        plan_next[cursor]=plan_heads[plan.function]; plan_heads[plan.function]=cursor as u32;
    }
    cursor=c.callable_adapters.len;
    while cursor>1 {
        if !visit(v,1) { return false; } cursor--; let adapter=c.callable_adapters[cursor];
        adapter_next[cursor]=adapter_heads[adapter.op]; adapter_heads[adapter.op]=cursor as u32;
    }
    return true;
}
fn unique_incoming(parent:Context,edge_id:u32)->bool {
    let v=proof_context(parent); let edge=v.c.edges[edge_id];
    let index=v.indexes; if index { if !proof_visit(v,1) { return false; } return index.incoming[edge.to]==1; }
    for other,id in v.c.edges { if !proof_visit(v,1) { return false; } if id!=0 && id!=edge_id && other.to==edge.to { return false; } }
    return true;
}
// A block dominates target iff every entry path reaches it. Reachability is bounded
// and uses explicit edges only. Structured loop identities are checked separately.
fn dominates(v: Context, definition: u32, target: u32) -> bool {
    if definition == target { return true; }
    let c = v.c;
    if c.blocks[definition].function != c.blocks[target].function { return false; }
    let entry = c.functions[c.blocks[target].function].entry;
    if definition == entry { return true; }
    let index=v.indexes; if index {
        if !visit(v,1) { return false; }
        let slot=((definition as u64*131+target)%index.dominance.len as u64) as u32;
        let cached=index.dominance[slot];
        if cached.definition==definition && cached.target==target && cached.epoch==v.epoch { return cached.result; }
        index.stamp[0]++; let stamp=index.stamp[0];
        var cursor:u32=0; var end:u32=1; index.queue[0]=entry; index.seen[entry]=stamp; var result=true;
        while cursor<end {
            if !visit(v,1) { return false; } let current=index.queue[cursor]; cursor++;
            if current==target { result=false; break; }
            let term=c.terminators[c.blocks[current].term];
            for i in term.edges.count {
                if !visit(v,1) { return false; } let to=c.edges[at(c,term.edges,i)].to;
                if to!=definition && index.seen[to]!=stamp { index.seen[to]=stamp; index.queue[end]=to; end++; }
            }
        }
        index.dominance[slot]=DominanceEntry{definition,target,v.epoch,result}; return result;
    }
    var seen: u32[>..] = []; for fill in c.blocks.len { seen.push(0); }
    var queue: u32[>..] = []; queue.push(entry); seen[entry] = 1;
    var cursor: i64 = 0;
    while cursor < queue.len { if !visit(v,1) { return false from dominates; }
        let current = queue[cursor]; cursor++;
        if current == target { return false; }
        let term = c.terminators[c.blocks[current].term];
        for i in term.edges.count {
            if !visit(v, 1) { return false; }
            let to = c.edges[at(c, term.edges, i)].to;
            if to != definition && seen[to] == 0 { seen[to] = 1; queue.push(to); }
        }
    }
    return true;
}
fn use_value(v: Context, value: u32, block_id: u32, position: u32) -> bool {
    if !visit(v, 1) { return false; }
    let c = v.c; let val = c.values[value];
    if !in_scope(v, c.blocks[block_id].scope, val.scope) { return reject(v, 2016, value); }
    if val.block_id != block_id {
        if !dominates(v, val.block_id, block_id) { return reject(v, 2034, value); }
    } else if val.op != 0 {
        let index=v.indexes; if index {
            if !visit(v,1) { return false; }
            if index.op_blocks[val.op]!=block_id || index.op_positions[val.op]>=position { return reject(v,2034,value); }
        } else {
            let ops = c.blocks[block_id].ops; var found = false;
            for i in position { if !visit(v,1) { return false from use_value; } if at(c, ops, i) == val.op { found = true; } }
            if !found { return reject(v, 2034, value); }
        }
    } else if !contains(v, c.blocks[block_id].params, value) { return reject(v, 2034, value); }
    return true;
}
fn evidence_available(parent:Context, id: u32, block_id: u32) -> bool {
    let v=proof_context(parent);
    let e = v.c.evidence[id];
    if !in_scope(v, v.c.blocks[block_id].scope, e.scope) { return false; }
    if e.edge == 0 { return true; }
    let edge = v.c.edges[e.edge];
    // Edge evidence is valid only while its edge controls entry. A second incoming
    // edge to that target would require a checked intersection, not this shortcut.
    if !unique_incoming(v,e.edge) { return false; }
    return dominates(v, edge.to, block_id);
}
fn obligation(parent:Context, op: Operation, block_id: u32, tag: u32, left: u32, right: u32) -> bool {
    let v=proof_context(parent);
    for i in op.evidence.count {
        if !proof_visit(v, 1) { return false; }
        let id = at(v.c, op.evidence, i); let f = v.c.facts[v.c.evidence[id].fact];
        if f.tag == tag && value_term(v, f.left, left) && value_term(v, f.right, right) && evidence_available(v, id, block_id) { return true; }
    }
    return false;
}

fn derive_layout_scratch(c: Core, type_id: u32, work: Work&, diags: Diagnostic[>..]&, colors: u32[>..]&, geometry: Geometry[>..]&, stamp: u32) -> Layout, bool {
    let v = Context { c, FRESH, work, diags, LIMIT_VISITS, LIMIT_PROOF_VISITS };
    if !id_ok(type_id, c.types.len) { reject(v, 2034, type_id); return Layout { .. }, false; }
    if !type_node(v, type_id, colors, geometry, 0, stamp) { return Layout { .. }, false; }
    let g = geometry[type_id];
    var flags: u32 = 0;
    if g.plain { flags |= 1; } if g.share { flags |= 2; } if g.size == 0 { flags |= 4; }
    var abi = ABI_INDIRECT;
    var representation = type_id;
    for unwrap in 65 { if !visit(v,1) { return Layout{..},false from derive_layout_scratch; }
        if c.types[representation].tag != TY_ALIAS && c.types[representation].tag != TY_FORALL { break; }
        representation = type_child(c, c.types[representation], 0);
    }
    let tag = c.types[representation].tag;
    if tag == TY_UNIT { abi = ABI_UNIT; }
    if tag == TY_BOOL || tag == TY_U32 || tag == TY_INDEX { abi = ABI_I32; }
    if tag == TY_F32 { abi = ABI_F32; }
    return Layout { type_id: type_id, size: g.size, align: g.align, flags: flags, abi: abi, schema: type_id,
        fields: c.types[type_id].fields, depth: g.depth, leaves: g.leaves, guards: g.guards }, true;
}

fn derive_layout(c: Core, type_id: u32, work: Work&, diags: Diagnostic[>..]&) -> Layout, bool {
    var colors: u32[>..] = []; var geometry: Geometry[>..] = [];
    for fill in c.types.len { colors.push(0); geometry.push(Geometry { .. }); }
    return derive_layout_scratch(c, type_id, work, diags, colors, geometry, 1);
}
fn append_layouts(b: CoreBuilder, first: u32, skip_templates: bool, diags: Diagnostic[>..]&) -> bool {
    let c = core_view(b);
    if first >= c.types.len { return true; }
    if c.types.len > 0x7fffffff { diags.push(Diagnostic {2031,0,0,0}); return false; }
    var colors: u32[>..] = []; var geometry: Geometry[>..] = [];
    for fill in c.types.len { colors.push(0); geometry.push(Geometry { .. }); }
    for i in first..c.types.len {
        if skip_templates && type_is_template(c, i as u32, 0) { continue; }
        // A new epoch for every root preserves the exact independent traversal
        // and work budget. Only scratch allocation/zeroing is shared.
        var work = Work { .. };
        let row, ok = derive_layout_scratch(c, i as u32, work, diags, colors, geometry, i as u32 * 2 + 1);
        if !ok { return false; }
        b.layouts.push(row);
    }
    return true;
}

recursive fn same_type(v: Context, a: u32, b: u32, depth: u32) -> bool {
    if !visit(v, 1) || depth > LIMIT_NEST { return false; }
    if a == b { return true; }
    let x = v.c.types[a]; let y = v.c.types[b];
    if x.tag == TY_ALIAS { return same_type(v, type_child(v.c, x, 0), b, depth + 1); }
    if y.tag == TY_ALIAS { return same_type(v, a, type_child(v.c, y, 0), depth + 1); }
    if !field_labels(v,x,y) { return false; }
    if x.tag != y.tag || x.region != y.region || x.nat != y.nat || x.domain != y.domain ||
        x.capacity != y.capacity || x.mode != y.mode || x.binder != y.binder || x.contract != y.contract || x.binders.count != y.binders.count || type_count(x) != type_count(y) { return false; }
    for i in type_count(x) { if !visit(v,1) { return false from same_type; } if !same_type(v, type_child(v.c, x, i), type_child(v.c, y, i), depth + 1) { return false; } }
    return true;
}
fn scalar_binary(tag: u32) -> u32 {
    if tag >= OP_U32_ADD && tag <= OP_U32_SHR || tag >= OP_ADD_FITS && tag <= OP_MUL_FITS { return TY_U32; }
    if tag >= OP_F32_ADD && tag <= OP_F32_DIV || tag >= OP_F32_EQ && tag <= OP_F32_GE { return TY_F32; }
    if tag == OP_BOOL_AND || tag == OP_BOOL_OR { return TY_BOOL; }
    return 0;
}
fn comparison(tag: u32) -> bool {
    return tag >= OP_U32_EQ && tag <= OP_U32_GE || tag >= OP_F32_EQ && tag <= OP_F32_GE || tag >= OP_ADD_FITS && tag <= OP_MUL_FITS;
}
fn result_tag(c: Core, op: Operation) -> u32 {
    if op.results.count != 1 { return TY_INVALID; }
    return c.types[c.values[at(c, op.results, 0)].type_id].tag;
}
fn literal_value(c: Core, id: u32) -> u32, bool {
    let value = c.values[id];
    if value.op == 0 || c.ops[value.op].tag != OP_U32 { return 0, false; }
    return c.ops[value.op].imm0, true;
}
fn call_effects(v: Context, caller: Contract, callee: Contract, subs: Span) -> bool {
    for i in callee.effects.count {
        if !visit(v, 1) { return false; }
        let wanted = v.c.effects[at(v.c, callee.effects, i)]; var found = false;
        for j in caller.effects.count {
            if !visit(v, 1) { return false; }
            let allowed = v.c.effects[at(v.c, caller.effects, j)];
            if allowed.kind == wanted.kind && binder_match(v,wanted.region,allowed.region,subs) { found = true; }
        }
        if !found { return false; }
    }
    return true;
}
fn operation(v: Context, id: u32, block_id: u32, geometry: const Geometry[:]) -> bool {
    if !visit(v, 1) { return false; }
    let c = v.c; let op = c.ops[id]; let result = result_tag(c, op);
    if op.tag == OP_CHECKED_ADD || op.tag == OP_CHECKED_SUB || op.tag == OP_CHECKED_MUL || op.tag == OP_CHECKED_DIV || op.tag == OP_CHECKED_SHL || op.tag == OP_CHECKED_SHR || op.tag == OP_F32_TO_U32 { return storage_extended(v, id, block_id, geometry); }
    if op.tag == OP_STATIC {
        if !id_ok(op.imm0,c.static_objects.len) || op.args.count != 0 || op.results.count != 1 || !same_type(v,c.values[at(c,op.results,0)].type_id,c.static_objects[op.imm0].type_id,0) { return reject(v,2003,id); }
        return true;
    }
    if op.tag == OP_LAYOUT_SIZE || op.tag == OP_LAYOUT_ALIGN {
        if !id_ok(op.imm0,c.types.len) || op.args.count != 0 || result != TY_U32 { return reject(v,2003,id); } return true;
    }
    if op.tag >= OP_F32_SQRT && op.tag <= OP_F32_TO_BITS {
        let binary = op.tag == OP_F32_MIN || op.tag == OP_F32_MAX;
        if op.args.count != (if binary {2} else {1}) || op.results.count != 1 { return reject(v,2003,id); }
        let input = if op.tag == OP_F32_FROM_BITS {TY_U32} else {TY_F32}; let output = if op.tag == OP_F32_TO_BITS {TY_U32} else {TY_F32};
        if result != output { return reject(v,2003,id); }
        for i in op.args.count { if !proof_visit(v,1) { return false from operation; } if c.types[terminal(v,c.values[at(c,op.args,i)].type_id)].tag != input { return reject(v,2003,id); } }
        return true;
    }
    if op.tag == OP_NAT_VALUE {
        let fun = c.functions[c.blocks[block_id].function];
        if op.args.count != 0 || op.results.count != 1 || result != TY_U32 || !id_ok(op.imm0, c.binders.len) || c.binders[op.imm0].kind != KIND_NAT || !contains(v, c.contracts[fun.contract].binders, op.imm0) && !environment_binder(v, fun.environment_bindings, op.imm0, KIND_NAT) { return reject(v, 2004, id); }
        return true;
    }
    if op.tag >= OP_UNIT && op.tag <= OP_F32 {
        if op.args.count != 0 || op.results.count != 1 || result != op.tag || op.tag == OP_BOOL && op.imm0 > 1 { return reject(v, 2003, id); }
        return true;
    }
    let scalar = scalar_binary(op.tag);
    if scalar != 0 {
        if op.args.count != 2 || op.results.count != 1 { return reject(v, 2003, id); }
        let left = at(c, op.args, 0); let right = at(c, op.args, 1);
        if c.types[c.values[left].type_id].tag != scalar || c.types[c.values[right].type_id].tag != scalar { return reject(v, 2003, id); }
        var target = scalar; if comparison(op.tag) { target = TY_BOOL; }
        if result != target { return reject(v, 2003, id); }
        var required: u32 = 0;
        if op.tag == OP_U32_ADD { required = FACT_ADD_FITS; }
        if op.tag == OP_U32_SUB { required = FACT_SUB_FITS; }
        if op.tag == OP_U32_MUL { required = FACT_MUL_FITS; }
        if required != 0 && !obligation(v, op, block_id, required, left, right) { return reject(v, 2011, id); }
        if op.tag == OP_U32_DIV || op.tag == OP_U32_REM || op.tag == OP_U32_SHL || op.tag == OP_U32_SHR {
            var ok = false;
            for i in op.evidence.count { if !proof_visit(v,1) { return false from operation; }
                let ev = at(c, op.evidence, i); let f = c.facts[c.evidence[ev].fact];
                if !proof_visit(v, 1) { return false; }
                if !evidence_available(v, ev, block_id) || f.tag != FACT_LT { continue; }
                if op.tag == OP_U32_DIV || op.tag == OP_U32_REM {
                    let lhs = c.terms[f.left];
                    if lhs.tag == EXPR_LITERAL && lhs.literal == 0 && value_term(v, f.right, right) { ok = true; }
                } else {
                    let rhs = c.terms[f.right];
                    if rhs.tag == EXPR_LITERAL && rhs.literal <= 32 && value_term(v, f.left, right) { ok = true; }
                }
            }
            if !ok { return reject(v, 2011, id); }
        }
        return true;
    }
    if op.tag == OP_F32_NEG || op.tag == OP_BOOL_NOT || op.tag == OP_U32_NOT || op.tag == OP_U32_TO_F32 {
        if op.args.count != 1 || op.results.count != 1 { return reject(v, 2003, id); }
        var want = TY_F32; if op.tag == OP_BOOL_NOT { want = TY_BOOL; } if op.tag == OP_U32_NOT || op.tag == OP_U32_TO_F32 { want = TY_U32; }
        var output = want; if op.tag == OP_U32_TO_F32 { output = TY_F32; }
        if c.types[c.values[at(c, op.args, 0)].type_id].tag != want || result != output { return reject(v, 2003, id); }
        return true;
    }
    if op.tag == OP_FN_WEAKEN {
        if op.args.count != 1 || op.results.count != 1 || !weaken_callable(v, c.values[at(c, op.args, 0)].type_id, c.values[at(c, op.results, 0)].type_id) { return reject(v, 2003, id); }
        return true;
    }
    if op.tag == OP_REFINE {
        if op.args.count != 1 || op.results.count != 1 || !refine_type(v, c.values[at(c, op.args, 0)].type_id, c.values[at(c, op.results, 0)].type_id, op, block_id, 0) { return reject(v, 2007, id); }
        return true;
    }
    if op.tag == OP_COPY {
        if op.args.count != 1 || op.results.count != 1 || !same_type(v, c.values[at(c, op.args, 0)].type_id, c.values[at(c, op.results, 0)].type_id, 0) { return reject(v, 2003, id); }
        return true;
    }
    if op.tag == OP_TUPLE || op.tag == OP_RECORD {
        if op.results.count != 1 || result != TY_TUPLE && result != TY_RECORD { return reject(v, 2003, id); }
        let t = c.types[c.values[at(c, op.results, 0)].type_id];
        if type_count(t) != op.args.count { return reject(v, 2018, id); }
        for i in op.args.count { if !proof_visit(v,1) { return false from operation; } if !same_type(v, c.values[at(c, op.args, i)].type_id, type_child(c, t, i), 0) { return reject(v, 2018, id); } }
        return true;
    }
    if op.tag == OP_PROJECT {
        if op.args.count != 1 || op.results.count != 1 { return reject(v, 2003, id); }
        let arg = at(c, op.args, 0); let ty = c.values[arg].type_id; let t = c.types[ty];
        if !geometry[ty].share { return reject(v, 2014, id); }
        if t.tag != TY_TUPLE && t.tag != TY_RECORD || op.imm0 >= type_count(t) || !same_type(v, type_child(c, t, op.imm0), c.values[at(c, op.results, 0)].type_id, 0) { return reject(v, 2003, id); }
        return true;
    }
    if op.tag == OP_DESTRUCTURE {
        if op.args.count != 1 { return reject(v, 2003, id); }
        let t = c.types[c.values[at(c, op.args, 0)].type_id];
        if t.tag != TY_TUPLE && t.tag != TY_RECORD || op.results.count != type_count(t) { return reject(v, 2003, id); }
        for i in op.results.count { if !proof_visit(v,1) { return false from operation; } if !same_type(v, type_child(c, t, i), c.values[at(c, op.results, i)].type_id, 0) { return reject(v, 2003, id); } }
        return true;
    }
    if op.tag == OP_TAG || op.tag == OP_PAYLOAD {
        if op.args.count != 1 || op.results.count != 1 { return reject(v, 2003, id); }
        let arg = at(c, op.args, 0); let t = c.types[c.values[arg].type_id];
        if t.tag != TY_SUM && t.tag != TY_RESULT { return reject(v, 2003, id); }
        if op.tag == OP_TAG { if result != TY_U32 { return reject(v, 2003, id); } return true; }
        if op.imm0 >= type_count(t) || !same_type(v, type_child(c, t, op.imm0), c.values[at(c, op.results, 0)].type_id, 0) { return reject(v, 2003, id); }
        if !case_payload_allowed(v, arg, op.imm0, block_id) { return reject(v, 2034, id); }
        return true;
    }
    if op.tag == OP_SUM {
        if op.results.count != 1 || op.args.count != 1 || result != TY_SUM && result != TY_RESULT { return reject(v, 2003, id); }
        let t = c.types[c.values[at(c, op.results, 0)].type_id];
        if op.imm0 >= type_count(t) || !same_type(v, type_child(c, t, op.imm0), c.values[at(c, op.args, 0)].type_id, 0) { return reject(v, 2018, id); }
        return true;
    }
    if op.tag == OP_CALL || op.tag == OP_CALL_INDIRECT {
        var argument_index: u32 = 0; if op.tag == OP_CALL_INDIRECT { argument_index = 1; }
        if op.args.count != argument_index + 1 || op.results.count != 1 { return reject(v, 2003, id); }
        let argument = at(c, op.args, argument_index);
        var contract_id: u32 = 0;
        if op.tag == OP_CALL {
            if !id_ok(op.imm0, c.functions.len) { return reject(v, 2034, id); }
            if c.functions[op.imm0].evaluator_only || c.functions[op.imm0].captures.count != 0 || c.functions[op.imm0].environment_bindings.count != 0 { return reject(v, 2019, id); }
            contract_id = c.functions[op.imm0].contract;
        } else {
            if op.imm0 != 0 { return reject(v, 2034, id); }
            let t = c.types[terminal(v, c.values[at(c, op.args, 0)].type_id)];
            if t.tag != TY_FN { return reject(v, 2003, id); } contract_id = t.contract;
        }
        let con = c.contracts[contract_id]; let caller = c.contracts[c.functions[c.blocks[block_id].function].contract];
        if !substitutions_valid(v, con.binders, op.substitutions, geometry) { return reject(v, 2004, id); }
        if !instantiated_type(v, con.arg, c.values[argument].type_id, op.substitutions, 0) || !instantiated_type(v, con.result, c.values[at(c, op.results, 0)].type_id, op.substitutions, 0) { return reject(v, 2003, id); }
        if !c.functions[c.blocks[block_id].function].evaluator_only && (caller.depth <= con.depth || caller.frame < con.frame) { return reject(v, 2023, id); }
        for ei in con.effects.count { if !proof_visit(v,1) { return false from operation; } let effect=c.effects[at(c,con.effects,ei)]; var region=effect.region;
            if region!=0 { let mapped,found=substitution(v,op.substitutions,region); if found { region=mapped; } }
            if !effect_allowed(v,block_id,effect.kind,region) { return reject(v,2006,id); }
        }
        for i in con.requires.count { if !proof_visit(v,1) { return false from operation; }
            let wanted = at(c, con.requires, i); var found = false;
            for j in op.evidence.count { if !proof_visit(v,1) { return false from operation; } let ev = at(c, op.evidence, j); if instantiated_fact(v, c.facts[wanted], c.facts[c.evidence[ev].fact], argument, 0, op.substitutions) && evidence_available(v, ev, block_id) { found = true; } }
            if !found { return reject(v, 2007, id); }
        }
        return true;
    }
    if op.tag == OP_OWNED_SEAL || op.tag == OP_OWNED_ABORT || op.tag == OP_OWNED_OPEN || op.tag == OP_OWNED_CLOSE { return owned_operation(v, id, block_id, geometry); }
    if op.tag == OP_PACK || op.tag == OP_OPEN { return package_operation(v, id, geometry); }
    if op.tag==OP_GENERIC_BIND { return generic_binding(v,id,geometry); }
    if op.tag == OP_CLOSURE || op.tag == OP_FN_PLACE { return closure_operation(v, id, geometry); }
    if op.tag >= OP_RESERVE && op.tag <= OP_DISCARD_ONCE || op.tag >= OP_ENV_TRY_ALLOC && op.tag <= OP_DEST_CAP { return storage_operation(v, id, block_id, geometry); }
    return reject(v, 2028, id);
}

fn consume(v: Context, geometry: const Geometry[:], live: u32[>..]&, value: u32) -> bool {
    if geometry[v.c.values[value].type_id].share { return true; }
    if live[value] == 0 { return reject(v, 2013, value); }
    live[value] = 0; return true;
}
fn live_exit(v: Context, geometry: const Geometry[:], live: const u32[:], affine: const u32[:]) -> bool {
    for value in affine { if !visit(v,1) { return false from live_exit; }
        if live[value] != 0 {
            if geometry[v.c.values[value].type_id].must_handle { return reject(v, 2021, value); }
            return reject(v, 2015, value);
        }
    }
    return true;
}
fn validate_function(parent: Context, id: u32, geometry: const Geometry[:], definitions: u32[>..]&, operation_owners: u32[>..]&, block_owners: u32[>..]&, live: u32[>..]&, outgoing: u32[>..]&) -> bool {
    let c = parent.c; let f = c.functions[id]; let v=with_origin(parent,f.origin); let contract = c.contracts[f.contract];
    if !f.evaluator_only && (contract.depth == 0 || contract.depth > 128 || contract.frame > 16777216) { return reject(v, 2023, id); }
    if f.evaluator_only && (f.visibility != VIS_PRIVATE || f.export_id != 0 || f.captures.count != 0 || f.environment_bindings.count != 0 || c.types[terminal(v,contract.arg)].tag != TY_UNIT) { return reject(v,2034,id); }
    if f.blocks.count == 0 || f.blocks.count > LIMIT_BLOCKS || !contains(v, f.blocks, f.entry) { return reject(v, 2031, id); }
    var callable_type = f.type_id;
    for unwrap in 65 { if !visit(v,1) { return false from validate_function; }
        let kind = c.types[callable_type].tag;
        if kind != TY_ALIAS && kind != TY_FORALL { break; }
        callable_type = type_child(c, c.types[callable_type], 0);
    }
    if c.types[callable_type].tag != TY_FN || c.types[callable_type].contract != f.contract { return reject(v, 2026, id); }
    if f.param == 0 || !same_type(v, c.values[f.param].type_id, contract.arg, 0) || c.values[f.param].block_id != f.entry || c.values[f.param].op != 0 { return reject(v, 2003, id); }
    if !contains(v, c.blocks[f.entry].params, f.param) { return reject(v, 2034, id); }
    for i in f.environment_bindings.count { if !visit(v,1) { return false from validate_function; }
        let binding = c.environment_bindings[at(c, f.environment_bindings, i)];
        if binding.function != id || binding.offset != i * 4 || binding.kind == KIND_TYPE && binding.source_value != 0 ||
            binding.kind == KIND_NAT && binding.source_value != 0 && (c.types[c.values[binding.source_value].type_id].tag != TY_U32 || !nat_operand(v,binding.binder,binding.source_value)) { return reject(v, 2019, id); }
        for j in i { if !visit(v,1) { return false from validate_function; } if c.environment_bindings[at(c, f.environment_bindings, j)].binder == binding.binder { return reject(v, 2019, id); } }
    }
    if c.blocks[f.entry].params.count != f.captures.count + 1 { return reject(v, 2019, id); }
    for i in f.captures.count { if !visit(v,1) { return false from validate_function; }
        let capture = c.captures[at(c, f.captures, i)];
        if capture.function != id || capture.field != i || !id_ok(capture.local_value, c.values.len) ||
            at(c, c.blocks[f.entry].params, i + 1) != capture.local_value || !geometry[c.values[capture.value].type_id].share ||
            !same_type(v, c.values[capture.value].type_id, c.values[capture.local_value].type_id, 0) { return reject(v, 2019, id); }
    }
    if f.binders.count > LIMIT_BINDERS || contract.binders.count > LIMIT_BINDERS { return reject(v, 2031, id); }
    var count: u64 = f.blocks.count;
    var own_frame: u64 = 0;
    var callee_frame: u32 = 0;
    for bi in f.blocks.count { if !visit(v,1) { return false from validate_function; }
        let block_id = at(c, f.blocks, bi); let basic = c.blocks[block_id]; let v=with_origin(v,if basic.origin==0 {f.origin}else{basic.origin});
        if !visit(v, 1) { return false; }
        if basic.function != id || block_owners[block_id] != 0 { return reject(v, 2034, block_id); }
        block_owners[block_id] = id; count += basic.ops.count;
        if count > LIMIT_OPS { return reject(v, 2031, id); }
        // Only this block's affine definitions can become live. Indexed scratch
        // is shared by the validation attempt and cleared at each completed block.
        var affine: u32[>..] = [];
        for pi in basic.params.count { if !visit(v,1) { return false from validate_function; }
            let parameter = at(c, basic.params, pi); let val = c.values[parameter];
            if val.op != 0 || val.block_id != block_id || definitions[parameter] != 0 { return reject(v, 2034, parameter); }
            definitions[parameter] = 1;
            if !geometry[val.type_id].share { live[parameter] = 1; affine.push(parameter); }
            let parameter_tag = c.types[terminal(v, val.type_id)].tag;
            if parameter_tag != TY_UNIT && parameter_tag != TY_U32 && parameter_tag != TY_F32 && parameter_tag != TY_BOOL && parameter_tag != TY_INDEX { own_frame += geometry[val.type_id].size; }
        }
        for oi in basic.ops.count { if !visit(v,1) { return false from validate_function; }
            let op_id = at(c, basic.ops, oi); let op = c.ops[op_id]; let v=with_origin(v,if op.origin==0 {basic.origin}else{op.origin});
            if operation_owners[op_id] != 0 { return reject(v, 2034, op_id); }
            operation_owners[op_id] = block_id;
            if !in_scope(v, basic.scope, op.scope) { return reject(v, 2016, op_id); }
            if op.args.count != 0 && (op.tag == OP_REGION_CLOSE || op.tag == OP_REGION_RESET) {
                let authority = at(c, op.args, 0); let region = c.types[c.values[authority].type_id].region;
                if scope_conflict(v, region, authority, block_id, oi, geometry, live) { return reject(v, 2017, op_id); }
            }
            if op.tag == OP_OWNED_SEAL || op.tag == OP_OWNED_ABORT {
                if op.args.count == 0 || !construction_exit(v, op, block_id, oi, geometry, live, affine) { return false; }
            }
            for ai in op.args.count { if !visit(v,1) { return false from validate_function; }
                let value = at(c, op.args, ai);
                if !borrows_operand(op.tag, ai) && c.types[terminal(v, c.values[value].type_id)].tag == TY_OWNED && owned_borrow_conflict(v, value, basic.scope) { return reject(v, 2017, value); }
                if !use_value(v, value, block_id, oi) { return false; }
                if !geometry[c.values[value].type_id].share && live[value] == 0 { return reject(v, 2013, value); }
                if !borrows_operand(op.tag, ai) && !consume(v, geometry, live, value) { return false; }
            }
            for evidence_index in op.evidence.count { if !visit(v,1) { return false from validate_function; }
                if !evidence_usable(v, at(c, op.evidence, evidence_index), block_id, oi, 0) { return reject(v, 2034, op_id); }
            }
            if op.tag == OP_CLOSURE || op.tag == OP_FN_PLACE {
                if !id_ok(op.imm0, c.functions.len) { return reject(v, 2034, op_id); }
                let bindings = c.functions[op.imm0].environment_bindings;
                for i in bindings.count { if !visit(v,1) { return false from validate_function; }
                    let binding = c.environment_bindings[at(c, bindings, i)];
                    if binding.source_value!=0 {
                        if c.blocks[c.values[binding.source_value].block_id].function==id {
                            if !use_value(v,binding.source_value,block_id,oi) { return reject(v,2019,op_id); }
                        } else {
                            var forwarded=false;
                            for fi in f.environment_bindings.count { if !visit(v,1) { return false from validate_function; } let source=c.environment_bindings[at(c,f.environment_bindings,fi)]; if source.kind==KIND_NAT && source.binder==binding.binder { forwarded=true; } }
                            if !forwarded { return reject(v,2019,op_id); }
                        }
                    }
                }
            }
            if !operation(v, op_id, block_id, geometry) { return false; }
            for ri in op.results.count { if !visit(v,1) { return false from validate_function; }
                let value = at(c, op.results, ri); let val = c.values[value];
                if val.op != op_id || val.block_id != block_id || definitions[value] != 0 || val.version == 0 { return reject(v, 2034, value); }
                definitions[value] = 1;
                if !geometry[val.type_id].share { live[value] = 1; affine.push(value); }
                let tag = c.types[val.type_id].tag;
                if tag != TY_UNIT && tag != TY_U32 && tag != TY_F32 && tag != TY_BOOL && tag != TY_INDEX { own_frame += geometry[val.type_id].size; }
            }
            if op.tag == OP_CALL {
                let cf = c.contracts[c.functions[op.imm0].contract].frame;
                if cf > callee_frame { callee_frame = cf; }
            } else if op.tag == OP_CALL_INDIRECT {
                let callable = c.types[terminal(v, c.values[at(c, op.args, 0)].type_id)];
                let cf = c.contracts[callable.contract].frame; if cf > callee_frame { callee_frame = cf; }
            } else if op.tag == OP_CLOSURE {
                var bundle:u32=0; var has_bundle=false;
                for adapter, ai in c.callable_adapters { if !visit(v,1) { return false from validate_function; } if ai != 0 && adapter.op == op_id { bundle=geometry[c.layouts[adapter.environment_layout].type_id].size; has_bundle=true; } }
                own_frame += if has_bundle {bundle} else {closure_environment_bound(v,op.imm0,geometry)};
            }
        }
        let term = c.terminators[basic.term];
        if basic.merge != 0 && (c.blocks[basic.merge].function != id || term.tag != TERM_BRANCH && term.tag != TERM_SWITCH || dominates(v, basic.merge, block_id)) { return reject(v, 2034, block_id); }
        if term.tag < TERM_JUMP || term.tag > TERM_UNREACHABLE { return reject(v, 2034, basic.term); }
        if term.subject != 0 && !use_value(v, term.subject, block_id, basic.ops.count) { return false; }
        if term.tag == TERM_RETURN {
            if term.subject == 0 || term.edges.count != 0 || !same_type(v, c.values[term.subject].type_id, contract.result, 0) { return reject(v, 2003, basic.term); }
            if !consume(v, geometry, live, term.subject) || !live_exit(v, geometry, live, affine) { return false; }
            for ei in contract.ensures.count { if !visit(v,1) { return false from validate_function; }
                let formal = c.facts[at(c, contract.ensures, ei)]; var proved = false;
                for evidence, ev in c.evidence {
                    if !proof_visit(v, 1) { return false; }
                    if ev == 0 { continue; }
                    if instantiated_fact(v, formal, c.facts[evidence.fact], f.param, term.subject, Span {..}) && evidence_usable(v, ev as u32, block_id, basic.ops.count, 0) { proved = true; }
                }
                if !proved { return reject(v, 2007, basic.term); }
            }
            if contract.on_true.count != 0 || contract.on_false.count != 0 {
                if c.types[terminal(v, contract.result)].tag != TY_BOOL { return reject(v, 2026, basic.term); }
                let returned = c.values[term.subject]; var known = false; var truth = false;
                if returned.op != 0 && c.ops[returned.op].tag == OP_BOOL { known = true; truth = c.ops[returned.op].imm0 != 0; }
                for side in 2 { if !visit(v,1) { return false from validate_function; }
                    if known && (side == 0) != truth { continue; }
                    let clause = if side == 0 { contract.on_true } else { contract.on_false };
                    for pi in clause.count { if !visit(v,1) { return false from validate_function; }
                        let formal = c.facts[at(c, clause, pi)]; var proved = false;
                        for evidence, ev in c.evidence {
                            if !proof_visit(v, 1) { return false; }
                            if ev == 0 { continue; }
                            if instantiated_fact(v, formal, c.facts[evidence.fact], f.param, term.subject, Span {..}) && evidence_usable(v, ev as u32, block_id, basic.ops.count, 0) { proved = true; }
                        }
                        if !proved { return reject(v, 2007, basic.term); }
                    }
                }
            }
        } else if term.tag == TERM_UNREACHABLE {
            if !unreachable_terminator(v,block_id,term) { return reject(v,2008,basic.term); }
        } else {
            if term.tag == TERM_JUMP && term.edges.count != 1 || term.tag == TERM_BRANCH && term.edges.count != 2 { return reject(v, 2034, basic.term); }
            if term.tag == TERM_BRANCH && (term.subject == 0 || c.types[c.values[term.subject].type_id].tag != TY_BOOL) { return reject(v, 2003, basic.term); }
            var cases: u32 = 0;
            if term.tag == TERM_SWITCH {
                if term.subject == 0 { return reject(v, 2003, basic.term); }
                let ty = c.types[c.values[term.subject].type_id];
                if ty.tag != TY_SUM && ty.tag != TY_RESULT || term.edges.count != type_count(ty) { return reject(v, 2005, basic.term); }
            }
            var kinds: u32 = 0;
            for ei in term.edges.count { if !visit(v,1) { return false from validate_function; }
                let edge_id = at(c, term.edges, ei); let edge = c.edges[edge_id]; let target = c.blocks[edge.to];
                if !visit(v, 1) { return false; }
                if edge.from != block_id || target.function != id || edge.args.count != target.params.count { return reject(v, 2034, edge_id); }
                if edge.kind == EDGE_TRUE { kinds |= 1; } if edge.kind == EDGE_FALSE { kinds |= 2; }
                if term.tag == TERM_BRANCH && (ei == 0 && edge.kind != EDGE_TRUE || ei == 1 && edge.kind != EDGE_FALSE) { return reject(v, 2034, edge_id); }
                if term.tag == TERM_SWITCH {
                    if edge.kind != EDGE_CASE || edge.case_tag >= term.edges.count || cases & (1 << edge.case_tag) != 0 { return reject(v, 2005, edge_id); }
                    cases |= 1 << edge.case_tag;
                } else if edge.kind != EDGE_NORMAL && edge.kind != EDGE_TRUE && edge.kind != EDGE_FALSE && edge.kind != EDGE_LOOP_ENTRY && edge.kind != EDGE_LOOP_NEXT && edge.kind != EDGE_LOOP_STOP { return reject(v, 2028, edge_id); }
                if edge.kind >= EDGE_LOOP_ENTRY && !id_ok(edge.loop_id, c.loops.len) { return reject(v, 2034, edge_id); }
                for value in affine { if !visit(v,1) { return false from validate_function; } outgoing[value] = live[value]; }
                for ai in edge.args.count { if !visit(v,1) { return false from validate_function; }
                    let arg = at(c, edge.args, ai); let parameter = at(c, target.params, ai);
                    if !use_value(v, arg, block_id, basic.ops.count) || !edge_type(v, c.values[parameter].type_id, c.values[arg].type_id, edge_id, 0) { return reject(v, 2003, edge_id); }
                    if !consume(v, geometry, outgoing, arg) { return false; }
                }
                if !live_exit(v, geometry, outgoing, affine) { return false; }
                // Backedges require explicit finite-range loop records, checked below.
                if dominates(v, edge.to, block_id) && edge.kind != EDGE_LOOP_NEXT { return reject(v, 2028, edge_id); }
            }
            if term.tag == TERM_BRANCH && kinds != 3 { return reject(v, 2034, basic.term); }
        }
        if term.discharge.count != 0 { return reject(v, 2034, basic.term); }
        for value in affine { if !visit(v,1) { return false from validate_function; } live[value] = 0; outgoing[value] = 0; }
    }
    if !f.evaluator_only && own_frame + callee_frame > contract.frame { return reject(v, 2023, id); }
    return true;
}

fn validate_core(c: Core, mode: u32, work: Work&, diags: Diagnostic[>..]&) -> bool {
    // Input integrity has a byte/table-derived bound. It is not one source
    // declaration's semantic budget shared by an entire project.
    let input_limit=validation_input_limit(c);
    var v = Context { c, mode, work, diags, input_limit, input_limit };
    if !structure(v) || !producer_identities(v) { return false; }
    var op_blocks:u32[>..]=[]; var op_positions:u32[>..]=[]; var incoming:u32[>..]=[];
    if !index_core(v,op_blocks,op_positions,incoming) { return false; }
    var dominance:DominanceEntry[>..]=[]; for fill in 1024 { dominance.push(DominanceEntry{..}); }
    var seen:u64[>..]=[]; var queue:u32[>..]=[]; for basic in c.blocks { seen.push(0); queue.push(0); }
    var plan_heads:u32[>..]=[]; var plan_next:u32[>..]=[]; var adapter_heads:u32[>..]=[]; var adapter_next:u32[>..]=[];
    if !index_layout_owners(v,plan_heads,plan_next,adapter_heads,adapter_next) { return false; }
    var stamp:u64[>..]=[0]; var indexes=ValidationIndex{op_blocks,op_positions,incoming,dominance,seen,queue,stamp,plan_heads,plan_next,adapter_heads,adapter_next};
    v.indexes .= indexes;
    var colors: u32[>..] = []; for fill in c.types.len { colors.push(0); }
    var geometry: Geometry[>..] = []; for fill in c.types.len { geometry.push(Geometry { .. }); }
    for t, id in c.types { if !visit(v,1) { return false from validate_core; } if id != 0 && !template_type(v,id as u32,0) && !type_node(v, id as u32, colors, geometry, 0) { return false; } }
    // A template is never a license for an oversized runtime value. Every
    // demanded representation is checked even if its syntax named an alias.
    for value,id in c.values { if !visit(v,1) { return false from validate_core; } if id != 0 && !type_node(v,value.type_id,colors,geometry,0) { return false; } }
    for function,id in c.functions { if !visit(v,1) { return false from validate_core; } if id != 0 && !type_node(v,function.type_id,colors,geometry,0) { return false; } }
    for layout,id in c.layouts { if !visit(v,1) { return false from validate_core; } if id != 0 && !type_node(v,layout.type_id,colors,geometry,0) { return false; } }
    for object,id in c.static_objects { if !visit(v,1) { return false from validate_core; } if id != 0 && !type_node(v,object.type_id,colors,geometry,0) { return false; } }
    if !term_structure(v) { return false; }
    var evidence_colors: u32[>..] = []; for fill in c.evidence.len { evidence_colors.push(0); }
    for e, id in c.evidence { if !visit(v,1) { return false from validate_core; } if id != 0 && !evidence_node(v, id as u32, evidence_colors, 0) { return false; } }
    // Failure destroys both scratch tables with this validation attempt; no
    // partially checked block can leak ownership state into a later attempt.
    var live: u32[>..] = []; var outgoing: u32[>..] = [];
    var definitions: u32[>..] = []; for fill in c.values.len { definitions.push(0); live.push(0); outgoing.push(0); }
    var operation_owners: u32[>..] = []; for fill in c.ops.len { operation_owners.push(0); }
    var block_owners: u32[>..] = []; for fill in c.blocks.len { block_owners.push(0); }
    var scope_owner:u32[>..]=[]; for scope in c.scopes { scope_owner.push(0); }
    for function,id in c.functions { if !visit(v,1) { return false from validate_core; } if id != 0 { let scope=c.blocks[function.entry].scope; if scope != 0 { scope_owner[scope]=id as u32; } } }
    var proof_heads:u32[>..]=[]; for function in c.functions { proof_heads.push(0); }
    var proof_next:u32[>..]=[]; for evidence in c.evidence { proof_next.push(0); }
    for evidence,id in c.evidence { if !visit(v,1) { return false from validate_core; }
        if id==0 { continue; } var scope=evidence.scope;
        for depth in LIMIT_NEST+1 { if !visit(v,1) { return false from validate_core; } if scope==0 || scope_owner[scope]!=0 { break; } scope=c.scopes[scope].parent; }
        let owner=scope_owner[scope]; if owner!=0 { proof_next[id]=proof_heads[owner]; proof_heads[owner]=id as u32; }
    }
    var type_marks:u32[>..]=[]; for row in c.types { type_marks.push(0); }
    var term_marks:u32[>..]=[]; for row in c.terms { term_marks.push(0); }
    var fact_marks:u32[>..]=[]; for row in c.facts { fact_marks.push(0); }
    var proof_marks:u32[>..]=[]; for row in c.evidence { proof_marks.push(0); }
    var contract_marks:u32[>..]=[]; for row in c.contracts { contract_marks.push(0); }
    var local_colors:u32[>..]=[]; for row in c.evidence { local_colors.push(0); }
    var owners:u32[>..]=[]; if !declaration_owners(v,owners) { return false; }
    var accounts:Work[>..]=[]; var inventory:InventoryCounts[>..]=[];
    for function in c.functions { accounts.push(Work{..}); inventory.push(InventoryCounts{..}); }
    var semantic_total:u64=0; var proof_total:u64=0;
    for f, id in c.functions { if !visit(v,1) { return false from validate_core; }
        if id == 0 { continue; }
        if f.producer!=0 && c.definitions[f.producer].kind==DEF_FUNCTION || f.visibility==VIS_PUBLIC {
            var bound:u32[>..<]=[];
            for i in c.contracts[f.contract].binders.count { if !visit(v,1) { return false from validate_core; } bound.push(at(c,c.contracts[f.contract].binders,i)); }
            if !closed_interface(v,f.type_id,bound,0) { return reject(v,2016,id as u32); }
        }
        let owner=owners[id]; var local=Context {c,mode,accounts[owner],diags,LIMIT_VISITS,LIMIT_PROOF_VISITS,diagnostic_origin(c,f.origin)};
        local.indexes .= indexes; local.epoch=id as u32;
        let marks=InventoryMarks{type_marks,term_marks,fact_marks,proof_marks,contract_marks};
        if !declaration_inventory(local,id as u32,owner,inventory[owner],marks,proof_heads[id],proof_next) { work.exhausted=accounts[owner].exhausted; return false; }
        var evidence=proof_heads[id];
        while evidence!=0 { if !visit(v,1) { return false from validate_core; } if !evidence_node(local,evidence,local_colors,0) { work.exhausted=accounts[owner].exhausted; return false; } evidence=proof_next[evidence]; }
        if c.abi_plans.len>1 && !validate_layout_premises(local,id as u32,geometry) { work.exhausted=accounts[owner].exhausted; return false; }
        if !validate_function(local, id as u32, geometry, definitions, operation_owners, block_owners, live, outgoing) || accounts[owner].exhausted { work.exhausted=accounts[owner].exhausted; return false; }
        for row,li in c.loops { if !visit(v,1) { return false from validate_core; } if li!=0 && c.blocks[row.header].function==id && !validate_loop(local,li as u32) { work.exhausted=accounts[owner].exhausted; return false; } }
    }
    // A type-only declaration has no Function body but still owns a complete
    // bounded interface graph. It cannot evade frozen type/proof limits.
    for definition,id in c.definitions {
        if !visit(v,1) {return false;}if id==0 || definition.kind!=DEF_TYPE {continue;}
        var account=Work{..};var counts=InventoryCounts{..};let local=Context{c,mode,account,diags,LIMIT_VISITS,LIMIT_PROOF_VISITS,diagnostic_origin(c,definition.origin)};
        let marks=InventoryMarks{type_marks,term_marks,fact_marks,proof_marks,contract_marks};
        if !declaration_inventory(local,0,c.functions.len as u32+id as u32,counts,marks,0,proof_next,definition.type_id) {work.exhausted=account.exhausted;return false;}
        var bound:u32[>..<]=[];for i in definition.binders.count {if !visit(local,1) {work.exhausted=account.exhausted;return false;}bound.push(at(c,definition.binders,i));}
        if definition.visibility==VIS_PUBLIC && !closed_interface(local,definition.type_id,bound,0) {work.exhausted=account.exhausted;return reject(local,2016,id as u32);}
        semantic_total+=account.visits;proof_total+=account.proof_visits;
    }
    for account in accounts { if !visit(v,1) { return false from validate_core; } semantic_total+=account.visits; proof_total+=account.proof_visits; }
    for count, id in definitions { if !visit(v,1) { return false from validate_core; } if id != 0 && count != 1 { return reject(v, 2034, id as u32); } }
    for owner, id in operation_owners { if !visit(v,1) { return false from validate_core; } if id != 0 && owner == 0 { return reject(v, 2034, id as u32); } }
    for owner, id in block_owners { if !visit(v,1) { return false from validate_core; } if id != 0 && owner == 0 { return reject(v, 2034, id as u32); } }
    for l, id in c.layouts { if !visit(v,1) { return false from validate_core; }
        if id == 0 { continue; }
        let g = geometry[l.type_id]; var flags: u32 = 0;
        if g.plain { flags |= 1; } if g.share { flags |= 2; } if g.size == 0 { flags |= 4; }
        if l.size != g.size || l.align != g.align || l.flags != flags || l.abi != representation_abi(v, l.type_id) { return reject(v, 2024, id as u32); }
        if c.abi_plans.len > 1 || c.schemas.len > 1 { if !layout_schema(v, l) { return reject(v, 2024, id as u32); } }
    }
    for dictionary, id in c.dictionary_realizations { if !visit(v,1) { return false from validate_core; } if id != 0 && !validate_dictionary(v,id as u32,geometry) { return false; } }
    for object, id in c.static_objects { if !visit(v,1) { return false from validate_core; } if id != 0 && !static_object(v,id as u32,geometry) { return false; } }
    for adapter, id in c.callable_adapters { if !visit(v,1) { return false from validate_core; } if id != 0 && !validate_adapter(v,id as u32,geometry) { return false; } }
    for plan, id in c.abi_plans { if !visit(v,1) { return false from validate_core; } if id != 0 && !validate_abi_plan(v, plan, geometry) { return false; } }
    for ex, id in c.exports { if !visit(v,1) { return false from validate_core; } if id != 0 && !bridge_export(v, id as u32, geometry) { return false; } }
    if c.abi_plans.len > 1 {
        for row, id in c.interfaces { if !visit(v,1) { return false from validate_core; } if id != 0 && !abi_digest(v, row.abi_digest) { return reject(v, 2035, id as u32); } }
        for row, id in c.exports { if !visit(v,1) { return false from validate_core; } if id != 0 && !abi_digest(v, row.abi_digest) { return reject(v, 2035, id as u32); } }
    }
    if c.loans.len > 1 || c.transitions.len > 1 { return reject(v, 2028, 0); }
    if c.phase.active != 0 || c.phase.created != c.phase.completed { return reject(v, 2034, 0); }
    if c.abi_plans.len > 1 && !check_dictionary_coverage(c,work,diags) { return false; }
    work.visits+=semantic_total; work.proof_visits+=proof_total;
    return !work.exhausted;
}
fn validator_diagnostic_name(code: u32) -> const u8[:] {
    if code == 2003 { return "k1_type_mismatch"; }
    if code == 2004 { return "k1_kind_mismatch"; }
    if code == 2005 { return "k1_nonexhaustive_case"; }
    if code == 2006 { return "k1_effect_mismatch"; }
    if code == 2007 { return "k1_contract_not_established"; }
    if code == 2008 { return "k1_missing_return"; }
    if code == 2010 { return "k1_bounds_not_established"; }
    if code == 2011 { return "k1_arithmetic_not_established"; }
    if code == 2012 { return "k1_domain_mismatch"; }
    if code == 2013 { return "k1_use_after_move"; }
    if code == 2014 { return "k1_usage_not_permitted"; }
    if code == 2015 { return "k1_ownership_not_discharged"; }
    if code == 2016 { return "k1_lifetime_escape"; }
    if code == 2017 { return "k1_loan_conflict"; }
    if code == 2018 { return "k1_incomplete_initialization"; }
    if code == 2019 { return "k1_invalid_capture"; }
    if code == 2020 { return "k1_invalid_owned_payload"; }
    if code == 2021 { return "k1_unhandled_result"; }
    if code == 2023 { return "k1_resource_bound"; }
    if code == 2024 { return "k1_layout_limit"; }
    if code == 2025 { return "k1_environment_capacity"; }
    if code == 2026 { return "k1_incomplete_interface"; }
    if code == 2027 { return "k1_unsupported_fact"; }
    if code == 2028 { return "k1_unsupported_feature"; }
    if code == 2030 { return "k1_semantic_limit"; }
    if code == 2031 { return "k1_core_limit"; }
    if code == 2032 { return "k1_proof_limit"; }
    if code == 2034 { return "k1_invalid_artifact"; }
    if code == 2035 { return "k1_incompatible_artifact"; }
    return "k1_invalid_artifact";
}

fn case_payload_allowed(v: Context, value: u32, tag: u32, block_id: u32) -> bool {
    let c = v.c;
    let producer = c.values[value].op;
    if producer != 0 && c.ops[producer].tag == OP_SUM && c.ops[producer].imm0 == tag { return true; }
    for edge, id in c.edges {
        if !visit(v, 1) { return false; }
        if id == 0 || edge.kind != EDGE_CASE || edge.case_tag != tag { continue; }
        let term = c.terminators[c.blocks[edge.from].term];
        if term.tag != TERM_SWITCH || !contains(v, term.edges, id as u32) { continue; }
        var exact = term.subject == value;
        let target = c.blocks[edge.to];
        for i in target.params.count { if !visit(v,1) { return false from case_payload_allowed; }
            if at(c, target.params, i) == value && at(c, edge.args, i) == term.subject { exact = true; }
        }
        if !exact { continue; }
        var incoming: u32 = 0;
        for e, j in c.edges { if !visit(v,1) { return false from case_payload_allowed; } if j != 0 && e.to == edge.to { incoming++; } }
        if incoming == 1 && dominates(v, edge.to, block_id) { return true; }
    }
    return false;
}

recursive fn type_region(v: Context, type_id: u32, region: u32, depth: u32) -> bool {
    if !visit(v, 1) || depth > LIMIT_NEST { return true; }
    let t = v.c.types[type_id];
    if t.tag == TY_OWNED { return false; }
    if t.region == region && region != 0 { return true; }
    for i in type_count(t) { if !visit(v,1) { return false from type_region; } if type_region(v, type_child(v.c, t, i), region, depth + 1) { return true; } }
    return false;
}
fn scope_conflict(v: Context, region: u32, except: u32, block_id: u32, position: u32, geometry: const Geometry[:], live: const u32[:]) -> bool {
    for value, id in v.c.values {
        if !visit(v, 1) { return true; }
        if id == 0 || id == except || !type_region(v, value.type_id, region, 0) { continue; }
        if !geometry[value.type_id].share { if live[id] != 0 { return true; } continue; }
        if !in_scope(v, v.c.blocks[block_id].scope, value.scope) { continue; }
        if value.block_id == block_id {
            if value.op == 0 { return true; }
            for i in position { if !visit(v,1) { return false from scope_conflict; } if at(v.c, v.c.blocks[block_id].ops, i) == value.op { return true; } }
        } else if dominates(v, value.block_id, block_id) { return true; }
    }
    return false;
}
fn term_literal(c: Core, term: u32, literal: u32) -> bool {
    return term != 0 && c.terms[term].tag == EXPR_LITERAL && c.terms[term].literal == literal;
}
fn term_operand(v:Context, term: u32, value: u32) -> bool {
    if !visit(v,1) { return false; }
    let c=v.c;
    if value_term(v, term, value) { return true; }
    let t = c.terms[term]; let op_id = c.values[value].op;
    if op_id == 0 { return false; } let op = c.ops[op_id];
    if t.tag == EXPR_BINDER { return nat_operand(v, t.binder, value); }
    if op.args.count != 1 { return false; }
    return t.value == at(c, op.args, 0) && t.version == c.values[t.value].version &&
        (t.tag == EXPR_LEN && op.tag == OP_VIEW_LEN || t.tag == EXPR_INIT && op.tag == OP_BUILDER_LEN || t.tag == EXPR_CAP && (op.tag == OP_BUILDER_CAP || op.tag == OP_DEST_CAP));
}
fn nat_operand(v:Context,binder:u32,value:u32)->bool {
    if !visit(v,1) { return false; }
    let c=v.c;
    let op_id=c.values[value].op;if op_id==0 {return false;}let op=c.ops[op_id];
    if op.tag==OP_NAT_VALUE {return binder==op.imm0;}
    if op.tag == OP_OPEN && op.args.count == 1 {
        let package_type = c.types[terminal(v, c.values[at(c, op.args, 0)].type_id)]; var ordinal: u32 = 1;
        for i in package_type.binders.count { if !visit(v,1) { return false; }
            let bid = at(c, package_type.binders, i); if c.binders[bid].kind != KIND_NAT { continue; }
            let witness, found = substitution(v, op.substitutions, bid);
            if ordinal < op.results.count && at(c, op.results, ordinal) == value { return found && c.terms[witness].tag == EXPR_BINDER && c.terms[witness].binder == binder; }
            ordinal++;
        }
    }
    return false;
}
fn term_relation(parent:Context, op: Operation, block_id: u32, tag: u32, left: u32, right: u32) -> bool {
    let v=proof_context(parent);
    for i in op.evidence.count {
        if !proof_visit(v, 1) { return false; }
        let id = at(v.c, op.evidence, i); let f = v.c.facts[v.c.evidence[id].fact];
        if f.tag == tag && f.left == left && f.right == right && evidence_available(v, id, block_id) { return true; }
    }
    return false;
}
fn index_bound(parent:Context, op: Operation, block_id: u32, collection: u32, index: u32) -> bool {
    let v=proof_context(parent);
    let c = v.c; let ct = c.types[c.values[collection].type_id]; let it = c.types[c.values[index].type_id];
    if it.tag == TY_INDEX { return ct.tag == TY_VIEW && it.domain == ct.domain && it.nat == ct.nat; }
    if it.tag != TY_U32 { return false; }
    for i in op.evidence.count {
        if !proof_visit(v, 1) { return false; }
        let ev = at(c, op.evidence, i); let f = c.facts[c.evidence[ev].fact];
        if f.tag != FACT_LT || !term_operand(v, f.left, index) || !evidence_available(v, ev, block_id) { continue; }
        if f.right == ct.nat { return true; }
        let right = c.terms[f.right];
        if right.value == collection && right.version == c.values[collection].version &&
            (ct.tag == TY_VIEW && right.tag == EXPR_LEN || ct.tag == TY_BUILDER && right.tag == EXPR_INIT) { return true; }
    }
    return false;
}
fn storage_operation(v: Context, id: u32, block_id: u32, geometry: const Geometry[:]) -> bool {
    let c = v.c; let op = c.ops[id];
    if op.tag == OP_RESERVE || op.tag == OP_OWNED_BEGIN || op.tag == OP_TRY_ALLOC || op.tag == OP_ENV_TRY_ALLOC || op.tag == OP_BUILDER_FREEZE || op.tag == OP_TRY_INDEX || op.tag == OP_BUILDER_TRY_APPEND { return storage_extended(v, id, block_id, geometry); }
    if op.tag == OP_VIEW_LEN || op.tag == OP_BUILDER_LEN || op.tag == OP_BUILDER_CAP || op.tag == OP_DEST_CAP {
        if op.args.count != 1 || result_tag(c, op) != TY_U32 { return reject(v, 2003, id); }
        let t = c.types[c.values[at(c, op.args, 0)].type_id];
        var expected = TY_BUILDER; if op.tag == OP_VIEW_LEN { expected = TY_VIEW; } if op.tag == OP_DEST_CAP { expected = TY_DEST; }
        if t.tag != expected { return reject(v, 2003, id); } return true;
    }
    if op.tag == OP_VIEW_INDEX || op.tag == OP_BUILDER_GET {
        if op.args.count != 2 || op.results.count != 1 { return reject(v, 2003, id); }
        let value = at(c, op.args, 0); let t = c.types[c.values[value].type_id];
        var expected = TY_VIEW; if op.tag == OP_BUILDER_GET { expected = TY_BUILDER; }
        if t.tag != expected || !same_type(v, type_child(c, t, 0), c.values[at(c, op.results, 0)].type_id, 0) { return reject(v, 2003, id); }
        if !index_bound(v, op, block_id, value, at(c, op.args, 1)) { return reject(v, 2010, id); }
        if !effect_allowed(v, block_id, EFFECT_READ, t.region) { return reject(v, 2006, id); }
        return true;
    }
    if op.tag == OP_INDEX_VALUE {
        if op.args.count != 1 || result_tag(c, op) != TY_U32 || c.types[c.values[at(c, op.args, 0)].type_id].tag != TY_INDEX { return reject(v, 2003, id); } return true;
    }
    if op.tag == OP_SPACE_END || op.tag == OP_DEST_DISCARD || op.tag == OP_BUILDER_DISCARD || op.tag == OP_DISCARD_ONCE {
        if op.args.count != 1 || result_tag(c, op) != TY_UNIT { return reject(v, 2003, id); }
        let t = c.types[c.values[at(c, op.args, 0)].type_id]; var expected = TY_SPACE;
        if op.tag == OP_DEST_DISCARD { expected = TY_DEST; } if op.tag == OP_BUILDER_DISCARD { expected = TY_BUILDER; } if op.tag == OP_DISCARD_ONCE { expected = TY_FN; }
        if t.tag != expected || expected == TY_FN && t.mode != MODE_ONCE { return reject(v, 2003, id); }
        return true;
    }
    if op.tag == OP_BUILDER_BEGIN {
        if op.args.count != 1 || op.results.count != 1 { return reject(v, 2003, id); }
        let a = c.types[c.values[at(c, op.args, 0)].type_id]; let b = c.types[c.values[at(c, op.results, 0)].type_id];
        if a.tag != TY_DEST || b.tag != TY_BUILDER || a.region != b.region || a.capacity != b.capacity || !term_literal(c, b.nat, 0) ||
            !same_type(v, type_child(c, a, 0), type_child(c, b, 0), 0) || b.mode != op.imm0 { return reject(v, 2018, id); }
        return true;
    }
    if op.tag == OP_BUILDER_APPEND || op.tag == OP_BUILDER_SET || op.tag == OP_BUILDER_TRUNCATE {
        if op.args.count != 2 && op.tag != OP_BUILDER_SET || op.tag == OP_BUILDER_SET && op.args.count != 3 || op.results.count != 1 { return reject(v, 2003, id); }
        let input = at(c, op.args, 0); let a = c.types[c.values[input].type_id]; let b = c.types[c.values[at(c, op.results, 0)].type_id];
        if a.tag != TY_BUILDER || b.tag != TY_BUILDER || a.region != b.region || a.capacity != b.capacity || a.mode != b.mode || !same_type(v, type_child(c, a, 0), type_child(c, b, 0), 0) { return reject(v, 2003, id); }
        if !effect_allowed(v, block_id, EFFECT_WRITE, a.region) { return reject(v, 2006, id); }
        if op.tag == OP_BUILDER_APPEND {
            if !same_type(v, type_child(c, a, 0), c.values[at(c, op.args, 1)].type_id, 0) || !term_relation(v, op, block_id, FACT_LT, a.nat, a.capacity) { return reject(v, 2010, id); }
            let next = c.terms[b.nat];
            if next.tag != EXPR_ADD || next.args.count != 2 || at(c, next.args, 0) != a.nat || !term_literal(c, at(c, next.args, 1), 1) { return reject(v, 2018, id); }
        } else if op.tag == OP_BUILDER_SET {
            if a.nat != b.nat || !same_type(v, type_child(c, a, 0), c.values[at(c, op.args, 2)].type_id, 0) || !index_bound(v, op, block_id, input, at(c, op.args, 1)) { return reject(v, 2010, id); }
        } else {
            if a.mode != MODE_RESIZE || !term_operand(v, b.nat, at(c, op.args, 1)) || !term_relation(v, op, block_id, FACT_LE, b.nat, a.nat) { return reject(v, 2010, id); }
        }
        return true;
    }
    if op.tag == OP_DEST_SPLIT {
        if op.args.count != 2 || op.results.count != 1 { return reject(v, 2003, id); }
        let source = c.types[terminal(v, c.values[at(c, op.args, 0)].type_id)];
        let amount = at(c, op.args, 1); let result_id = c.values[at(c, op.results, 0)].type_id;
        if source.tag != TY_DEST || c.types[terminal(v, c.values[amount].type_id)].tag != TY_U32 || !pair(v, result_id) { return reject(v, 2003, id); }
        let result = c.types[terminal(v, result_id)]; let left = c.types[terminal(v, type_child(c, result, 0))]; let right = c.types[terminal(v, type_child(c, result, 1))];
        if left.tag != TY_DEST || right.tag != TY_DEST || left.region != source.region || right.region != source.region ||
            !same_type(v, type_child(c, source, 0), type_child(c, left, 0), 0) || !same_type(v, type_child(c, source, 0), type_child(c, right, 0), 0) ||
            !term_operand(v, left.capacity, amount) { return reject(v, 2003, id); }
        let remainder = c.terms[right.capacity];
        if remainder.tag != EXPR_SUB || remainder.args.count != 2 || at(c, remainder.args, 0) != source.capacity || at(c, remainder.args, 1) != left.capacity ||
            !term_relation(v, op, block_id, FACT_LE, left.capacity, source.capacity) { return reject(v, 2010, id); }
        return true;
    }
    if op.tag == OP_VIEW_SLICE {
        if op.args.count != 3 || op.results.count != 1 { return reject(v, 2003, id); }
        let source = c.types[terminal(v, c.values[at(c, op.args, 0)].type_id)];
        let start = at(c, op.args, 1); let count = at(c, op.args, 2);
        let package = c.types[terminal(v, c.values[at(c, op.results, 0)].type_id)];
        if source.tag != TY_VIEW || c.types[terminal(v, c.values[start].type_id)].tag != TY_U32 || c.types[terminal(v, c.values[count].type_id)].tag != TY_U32 ||
            package.tag != TY_EXISTS || package.binders.count != 1 { return reject(v, 2003, id); }
        let view = c.types[terminal(v, type_child(c, package, 0))]; let domain = at(c, package.binders, 0);
        if view.tag != TY_VIEW || view.region != source.region || view.domain != domain || c.binders[domain].kind != KIND_DOMAIN ||
            c.binders[domain].introduction != id || c.binders[domain].introduction_kind != INTRO_OPERATION || !same_type(v, type_child(c, source, 0), type_child(c, view, 0), 0) || !term_operand(v, view.nat, count) { return reject(v, 2012, id); }
        var start_ok = false; var count_ok = false;
        for i in op.evidence.count {
            if !proof_visit(v, 1) { return false; }
            let ev = at(c, op.evidence, i); let fact = c.facts[c.evidence[ev].fact];
            if fact.tag != FACT_LE || !evidence_available(v, ev, block_id) { continue; }
            if term_operand(v, fact.left, start) && fact.right == source.nat { start_ok = true; }
            let bound = c.terms[fact.right];
            if term_operand(v, fact.left, count) && bound.tag == EXPR_SUB && bound.args.count == 2 && at(c, bound.args, 0) == source.nat && term_operand(v, at(c, bound.args, 1), start) { count_ok = true; }
        }
        if !start_ok || !count_ok { return reject(v, 2010, id); }
        return true;
    }
    if op.tag == OP_REGION_RESET {
        if op.args.count != 1 || op.results.count != 1 || op.substitutions.count != 1 || !id_ok(op.imm0, c.binders.len) { return reject(v, 2003, id); }
        let owner = c.types[terminal(v, c.values[at(c, op.args, 0)].type_id)]; let output = c.values[at(c, op.results, 0)].type_id;
        if owner.tag != TY_REGION_OWNER || !pair(v, output) { return reject(v, 2003, id); }
        let pair_type = c.types[terminal(v, output)]; let next_owner = c.types[terminal(v, type_child(c, pair_type, 0))]; let next_space = c.types[terminal(v, type_child(c, pair_type, 1))];
        let fresh = c.binders[op.imm0]; let sub = c.substitutions[at(c, op.substitutions, 0)];
        if next_owner.tag != TY_REGION_OWNER || next_space.tag != TY_SPACE || next_owner.region != op.imm0 || next_space.region != op.imm0 || op.imm0 == owner.region ||
            fresh.kind != KIND_REGION || fresh.introduction != id || fresh.introduction_kind != INTRO_OPERATION || fresh.scope != op.scope || op.scope == 0 || c.scopes[op.scope].kind != SCOPE_REGION ||
            sub.kind != KIND_REGION || sub.binder != owner.region || sub.value != op.imm0 { return reject(v, 2016, id); }
        if !effect_allowed(v, block_id, EFFECT_RESET, owner.region) { return reject(v, 2006, id); }
        if c.contracts[c.functions[c.blocks[block_id].function].contract].depth < 3 { return reject(v, 2023, id); }
        return true;
    }
    if op.tag == OP_REGION_CLOSE {
        if op.args.count != 1 || result_tag(c, op) != TY_UNIT || c.types[c.values[at(c, op.args, 0)].type_id].tag != TY_REGION_OWNER { return reject(v, 2003, id); }
        if !effect_allowed(v, block_id, EFFECT_RELEASE, 0) { return reject(v, 2006, id); }
        if c.contracts[c.functions[c.blocks[block_id].function].contract].depth < 3 { return reject(v, 2023, id); } return true;
    }
    return reject(v, 2028, id);
}

fn borrows_operand(tag: u32, index: u32) -> bool {
    return index == 0 && (tag == OP_TAG || tag == OP_VIEW_LEN || tag == OP_VIEW_INDEX || tag == OP_BUILDER_LEN || tag == OP_BUILDER_CAP || tag == OP_DEST_CAP || tag == OP_BUILDER_GET || tag == OP_INDEX_VALUE || tag == OP_OWNED_OPEN);
}

fn substitution(v:Context, span: Span, binder: u32) -> u32, bool {
    if !visit(v,1) { return 0, false; }
    let c=v.c;
    for i in span.count { if !visit(v,1) { return 0, false; } let s = c.substitutions[at(c, span, i)]; if s.binder == binder { return s.value, true; } }
    return 0, false;
}
fn binder_match(v:Context, generic: u32, concrete: u32, subs: Span) -> bool {
    if !visit(v,1) { return false; }
    let c=v.c;
    if generic == 0 { return concrete == 0; }
    let replacement, found = substitution(v, subs, generic);
    if found { return replacement == concrete; } return generic == concrete;
}
fn nat_match(v:Context, generic: u32, concrete: u32, subs: Span) -> bool {
    if !visit(v,1) { return false; }
    let c=v.c;
    if generic == 0 { return concrete == 0; }
    let term = c.terms[generic];
    if term.tag == EXPR_BINDER { let replacement, found = substitution(v, subs, term.binder); if found { return replacement == concrete; } }
    return generic == concrete;
}
recursive fn instantiated_type(v: Context, generic: u32, concrete: u32, subs: Span, depth: u32) -> bool {
    if !visit(v, 1) || depth > LIMIT_NEST { return false; }
    let a = v.c.types[generic]; let b = v.c.types[concrete];
    if a.tag == TY_ALIAS || a.tag == TY_FORALL { return instantiated_type(v, type_child(v.c, a, 0), concrete, subs, depth + 1); }
    if b.tag == TY_ALIAS || b.tag == TY_FORALL { return instantiated_type(v, generic, type_child(v.c, b, 0), subs, depth + 1); }
    if a.tag == TY_PARAM { let replacement, found = substitution(v, subs, a.binder); if found { return same_type(v, replacement, concrete, depth + 1); } }
    if !field_labels(v,a,b) { return false; }
    if a.tag != b.tag || a.mode != b.mode || a.binder != b.binder || type_count(a) != type_count(b) ||
        !binder_match(v, a.region, b.region, subs) || !binder_match(v, a.domain, b.domain, subs) ||
        !nat_match(v, a.nat, b.nat, subs) || !nat_match(v, a.capacity, b.capacity, subs) { return false; }
    for i in type_count(a) { if !visit(v,1) { return false from instantiated_type; } if !instantiated_type(v, type_child(v.c, a, i), type_child(v.c, b, i), subs, depth + 1) { return false; } }
    // Callable effects/resources/preconditions are part of type identity.
    if a.tag == TY_FN && !instantiated_callable_contract(v, a.contract, b.contract, subs) { return false; }
    return true;
}
fn substitutions_valid(v: Context, binders: Span, subs: Span, geometry: const Geometry[:]) -> bool {
    if binders.count != subs.count { return false; }
    for i in subs.count {
        if !visit(v, 1) { return false; }
        let sub = v.c.substitutions[at(v.c, subs, i)]; let binder = v.c.binders[sub.binder];
        if !contains(v, binders, sub.binder) || binder.kind != sub.kind { return false; }
        for j in i { if !visit(v,1) { return false from substitutions_valid; } if v.c.substitutions[at(v.c, subs, j)].binder == sub.binder { return false; } }
        if sub.kind == KIND_TYPE {
            if !id_ok(sub.value, v.c.types.len) { return false; }
            if binder.constraints & CONSTRAINT_PLAIN != 0 && !geometry[sub.value].plain || binder.constraints & CONSTRAINT_SHARE != 0 && !geometry[sub.value].share { return false; }
        } else if sub.kind == KIND_NAT {
            if !id_ok(sub.value, v.c.terms.len) { return false; }
        } else if sub.kind == KIND_REGION {
            if sub.value != 0 && (!id_ok(sub.value, v.c.binders.len) || v.c.binders[sub.value].kind != KIND_REGION) { return false; }
        } else if sub.kind == KIND_DOMAIN {
            if !id_ok(sub.value, v.c.binders.len) || v.c.binders[sub.value].kind != KIND_DOMAIN { return false; }
        } else { return false; }
    }
    return true;
}
fn package_operation(v: Context, id: u32, geometry: const Geometry[:]) -> bool {
    let c = v.c; let op = c.ops[id]; var package_id: u32 = 0;
    if op.tag == OP_PACK {
        if op.results.count != 1 || op.args.count == 0 { return reject(v, 2003, id); }
        package_id = c.values[at(c, op.results, 0)].type_id;
    } else {
        if op.args.count != 1 || op.results.count == 0 { return reject(v, 2003, id); }
        package_id = c.values[at(c, op.args, 0)].type_id;
    }
    let ty = c.types[package_id];
    if ty.tag != TY_EXISTS || !substitutions_valid(v, ty.binders, op.substitutions, geometry) { return reject(v, 2004, id); }
    var nats: u32 = 0;
    for i in ty.binders.count { if !visit(v,1) { return false from package_operation; }
        let binder_id = at(c, ty.binders, i); let binder = c.binders[binder_id];
        let witness, found = substitution(v, op.substitutions, binder_id);
        if !found { return reject(v, 2004, id); }
        if op.tag == OP_OPEN {
            var fresh = witness;
            if binder.kind == KIND_NAT { if c.terms[witness].tag != EXPR_BINDER { return reject(v, 2004, id); } fresh = c.terms[witness].binder; }
            if fresh == 0 || c.binders[fresh].scope != op.scope || c.scopes[op.scope].kind != SCOPE_PACKAGE || c.binders[fresh].introduction != id || c.binders[fresh].introduction_kind != INTRO_OPERATION { return reject(v, 2016, id); }
            for j in i { if !visit(v,1) { return false from package_operation; }
                let other, present = substitution(v, op.substitutions, at(c, ty.binders, j));
                if present && witness == other && binder.kind == c.binders[at(c, ty.binders, j)].kind { return reject(v, 2012, id); }
            }
        }
        if binder.kind == KIND_NAT {
            if op.tag == OP_PACK {
                if nats >= op.args.count - 1 || !term_operand(v, witness, at(c, op.args, nats)) { return reject(v, 2003, id); }
            } else if nats + 1 >= op.results.count || c.types[c.values[at(c, op.results, nats + 1)].type_id].tag != TY_U32 { return reject(v, 2003, id); }
            nats++;
        }
    }
    if op.tag == OP_PACK {
        if op.args.count != nats + 1 || !instantiated_type(v, type_child(c, ty, 0), c.values[at(c, op.args, nats)].type_id, op.substitutions, 0) { return reject(v, 2003, id); }
    } else {
        if op.results.count != nats + 1 || !instantiated_type(v, type_child(c, ty, 0), c.values[at(c, op.results, 0)].type_id, op.substitutions, 0) { return reject(v, 2003, id); }
    }
    return true;
}
fn closure_operation(v: Context, id: u32, geometry: const Geometry[:]) -> bool {
    let c = v.c; let op = c.ops[id];
    if !id_ok(op.imm0, c.functions.len) || op.results.count != 1 || c.functions[op.imm0].evaluator_only { return reject(v, 2034, id); }
    let fun = c.functions[op.imm0]; let t = c.types[c.values[at(c, op.results, 0)].type_id];
    if t.tag != TY_FN { return reject(v, 2003, id); }
    let source_contract = c.contracts[fun.contract];
    if op.substitutions.count == 0 {
        if source_contract.binders.count != 0 || t.contract != fun.contract { return reject(v, 2003, id); }
    } else if !specialized_contract(v, fun.contract, t.contract, op.substitutions, geometry) { return reject(v, 2007, id); }
    var offset: u32 = 0;
    if op.tag == OP_FN_PLACE { offset = 1; }
    if op.args.count != fun.captures.count + offset { return reject(v, 2019, id); }
    var size: u32 = fun.environment_bindings.count * 4; var minimum=size; var dependent=false;
    for i in fun.captures.count { if !visit(v,1) { return false from closure_operation; }
        let capture = c.captures[at(c, fun.captures, i)]; let value = at(c, op.args, i + offset);
        if capture.function != op.imm0 || !capture_alias(v,value,capture.value,0) || capture.field != i || !geometry[c.values[value].type_id].share { return reject(v, 2019, id); }
        let layout=geometry[c.values[value].type_id]; dependent=dependent || layout.dependent;
        size += layout.size; minimum+=layout.minimum;
        if !in_scope(v, op.scope, c.values[value].scope) || !capture_lifetime(v, c.values[value].type_id, t.region, 0) { return reject(v, 2016, id); }
    }
    if minimum>256 || size>256 && !dependent { return reject(v,2024,id); }
    if dependent && size>256 { size=256; }
    if op.tag == OP_FN_PLACE {
        let dest = c.types[c.values[at(c, op.args, 0)].type_id];
        if dest.tag != TY_ENV_DEST || dest.region != t.region || !term_literal(c, dest.capacity, size) &&
            (c.terms[dest.capacity].tag != EXPR_LITERAL || c.terms[dest.capacity].literal < size) { return reject(v, 2025, id); }
    } else if fun.captures.count != 0 {
        if t.region == 0 { if !c.functions[c.blocks[c.values[at(c,op.results,0)].block_id].function].evaluator_only { return reject(v,2016,id); } }
        else if c.binders[t.region].scope != op.scope { return reject(v, 2016, id); }
    }
    return true;
}

recursive fn actual_term(parent:Context, formal_id: u32, actual_id: u32, arg: u32, result: u32, subs: Span, depth: u32) -> bool {
    let v=proof_context(parent);
    if !proof_visit(v, 1) || depth > LIMIT_NEST { return false; }
    let c = v.c; let formal = c.terms[formal_id]; let actual = c.terms[actual_id];
    if formal.tag == EXPR_ARG { return arg != 0 && value_term(v, actual_id, arg); }
    if formal.tag == EXPR_RESULT { return result != 0 && value_term(v, actual_id, result); }
    if formal.tag == EXPR_BINDER {
        let replacement, found = substitution(v, subs, formal.binder);
        if found { return replacement == actual_id; } return formal_id == actual_id;
    }
    if formal.tag == EXPR_LITERAL { return actual.tag == EXPR_LITERAL && formal.literal == actual.literal; }
    if formal.tag == EXPR_FIELD {
        let value = formal_value(v, formal_id, arg, result, 0);
        if value != 0 && term_operand(v, actual_id, value) { return true; }
    }
    if formal.tag == EXPR_FIELD && formal.args.count == 1 && actual.tag == EXPR_VALUE && actual.value != 0 {
        let definition = c.values[actual.value].op;
        if definition != 0 && c.ops[definition].tag == OP_PROJECT && c.ops[definition].imm0 == formal.literal {
            let source = at(c, c.ops[definition].args, 0);
            for term, id in c.terms { if !proof_visit(v,1) { return false from actual_term; }
                if id != 0 && term.tag == EXPR_VALUE && term.value == source && term.version == c.values[source].version &&
                    actual_term(v, at(c, formal.args, 0), id as u32, arg, result, subs, depth + 1) { return true; }
            }
        }
    }
    if (formal.tag == EXPR_LEN || formal.tag == EXPR_CAP || formal.tag == EXPR_INIT) && formal.args.count == 1 && actual.tag == formal.tag && actual.value != 0 {
        for term, term_id in c.terms { if !proof_visit(v,1) { return false from actual_term; }
            if term_id != 0 && term.tag == EXPR_VALUE && term.value == actual.value && term.version == actual.version &&
                actual_term(v, at(c, formal.args, 0), term_id as u32, arg, result, subs, depth + 1) { return true; }
        }
        return false;
    }
    if formal.tag != actual.tag || formal.literal != actual.literal || formal.args.count != actual.args.count { return false; }
    if formal.tag == EXPR_VALUE { return formal.value == actual.value && formal.version == actual.version; }
    if formal.args.count == 0 { return formal_id == actual_id; }
    for i in formal.args.count { if !proof_visit(v,1) { return false from actual_term; }
        if !actual_term(v, at(c, formal.args, i), at(c, actual.args, i), arg, result, subs, depth + 1) { return false; }
    }
    return true;
}
fn instantiated_fact(parent:Context, formal: Fact, actual: Fact, arg: u32, result: u32, subs: Span) -> bool {
    let v=proof_context(parent);
    if formal.tag != actual.tag || !binder_match(v, formal.domain, actual.domain, subs) { return false; }
    if !actual_term(v, formal.left, actual.left, arg, result, subs, 0) || !actual_term(v, formal.right, actual.right, arg, result, subs, 0) { return false; }
    if formal.third != 0 && actual.third != 0 { return actual_term(v, formal.third, actual.third, arg, result, subs, 0); }
    return formal.third == actual.third;
}

recursive fn evidence_usable(parent:Context, id: u32, block_id: u32, position: u32, depth: u32) -> bool {
    let v=proof_context(parent);
    if !proof_visit(v, 1) || depth > LIMIT_TERMS || !evidence_available(v, id, block_id) { return false; }
    let e = v.c.evidence[id];
    var first:u32=0; if e.rule==RULE_CAPTURE { first=e.operands.count/2; }
    let end=if e.rule==RULE_BOOL_PATH {1} else if e.rule==RULE_CONTRACT && e.edge!=0 {0} else {e.operands.count};
    for i in first..end { if !proof_visit(v,1) { return false from evidence_usable; } if !use_value(v, at(v.c, e.operands, i), block_id, position) { return false; } }
    if e.rule == RULE_JOIN || e.rule == RULE_LOOP_INVARIANT || e.rule==RULE_CAPTURE { return true; }
    for i in e.premises.count { if !proof_visit(v,1) { return false from evidence_usable; } if !evidence_usable(v, at(v.c, e.premises, i), block_id, position, depth + 1) { return false; } }
    return true;
}

fn terminal(v:Context, id: u32) -> u32 {
    if !visit(v,1) { return 0; }
    let c=v.c;
    var current = id;
    for i in 65 { if !visit(v,1) { return 0; }
        let t = c.types[current]; if t.tag != TY_ALIAS && t.tag != TY_FORALL { return current; }
        current = type_child(c, t, 0);
    }
    return 0;
}
recursive fn wire_plain(v: Context, id: u32, geometry: const Geometry[:], depth: u32) -> bool {
    if !visit(v, 1) || depth > LIMIT_NEST || !geometry[id].plain { return false; }
    let t = v.c.types[id];
    if t.tag == TY_INDEX || t.domain != 0 || t.region != 0 { return false; }
    for i in t.binders.count { if !visit(v,1) { return false from wire_plain; } if v.c.binders[at(v.c, t.binders, i)].kind == KIND_DOMAIN { return false; } }
    for i in type_count(t) { if !visit(v,1) { return false from wire_plain; } if !wire_plain(v, type_child(v.c, t, i), geometry, depth + 1) { return false; } }
    return true;
}
fn bridge_export(v: Context, id: u32, geometry: const Geometry[:]) -> bool {
    let c = v.c; let ex = c.exports[id]; let fun = c.functions[ex.function]; let contract = c.contracts[fun.contract];
    if fun.evaluator_only { return reject(v,2034,id); }
    if !id_ok(ex.arg_type, c.types.len) || !id_ok(ex.result_type, c.types.len) || !refs_ok(v, ex.substitutions, c.substitutions.len) { return reject(v, 2034, id); }
    if ex.frame < contract.frame || ex.frame > 16777216 || ex.depth <= contract.depth || ex.depth > 128 { return reject(v, 2023, id); }
    if ex.kind == EXPORT_SCALAR {
        if contract.binders.count != 0 || fun.captures.count != 0 || !same_type(v, ex.arg_type, contract.arg, 0) || !same_type(v, ex.result_type, contract.result, 0) { return reject(v, 2026, id); }
        let a = c.types[terminal(v, ex.arg_type)].tag; let r = c.types[terminal(v, ex.result_type)].tag;
        if a != TY_UNIT && a != TY_BOOL && a != TY_U32 && a != TY_F32 || r != TY_UNIT && r != TY_BOOL && r != TY_U32 && r != TY_F32 { return reject(v, 2028, id); }
        return true;
    }
    if ex.kind != EXPORT_BRIDGE || fun.captures.count != 0 || c.types[terminal(v, fun.type_id)].mode != MODE_MANY { return reject(v, 2028, id); }
    // Type parameters are explicit metadata. Region/Nat/Domain parameters are
    // independently matched to invocation fields below; metadata cannot invent them.
    var type_binders: u32 = 0;
    for i in contract.binders.count { if !visit(v,1) { return false from bridge_export; }
        let bid = at(c, contract.binders, i); let binder = c.binders[bid];
        if binder.kind != KIND_TYPE { continue; }
        type_binders++; let value, found = substitution(v, ex.substitutions, bid);
        if !found || !id_ok(value, c.types.len) || binder.constraints & CONSTRAINT_PLAIN != 0 && !geometry[value].plain ||
            binder.constraints & CONSTRAINT_SHARE != 0 && !geometry[value].share { return reject(v, 2004, id); }
    }
    if type_binders != ex.substitutions.count { return reject(v, 2004, id); }
    for i in ex.substitutions.count { if !visit(v,1) { return false from bridge_export; }
        let sub = c.substitutions[at(c, ex.substitutions, i)];
        if sub.kind != KIND_TYPE || !contains(v, contract.binders, sub.binder) { return reject(v, 2004, id); }
        for j in i { if !visit(v,1) { return false from bridge_export; } if c.substitutions[at(c, ex.substitutions, j)].binder == sub.binder { return reject(v, 2004, id); } }
    }
    if !instantiated_type(v, contract.arg, ex.arg_type, ex.substitutions, 0) || !instantiated_type(v, contract.result, ex.result_type, ex.substitutions, 0) { return reject(v, 2003, id); }
    let argument = c.types[terminal(v, ex.arg_type)]; let result = c.types[terminal(v, ex.result_type)];
    if argument.tag != TY_RECORD || result.tag != TY_RESULT { return reject(v, 2028, id); }
    let success = c.types[terminal(v, type_child(c, result, 0))]; let failure_id = terminal(v, type_child(c, result, 1)); let failure = c.types[failure_id];
    if success.tag != TY_EXISTS || success.binders.count != 2 { return reject(v, 2028, id); }
    var nats: u32 = 0; var domains: u32 = 0;
    for i in success.binders.count { if !visit(v,1) { return false from bridge_export; } let kind = c.binders[at(c, success.binders, i)].kind; if kind == KIND_NAT { nats++; } if kind == KIND_DOMAIN { domains++; } }
    if nats != 1 || domains != 1 { return reject(v, 2028, id); }
    let output = c.types[terminal(v, type_child(c, success, 0))];
    if output.tag != TY_VIEW || !wire_plain(v, type_child(c, output, 0), geometry, 0) { return reject(v, 2028, id); }
    if failure.tag != TY_UNIT {
        if failure.tag != TY_SUM { return reject(v, 2028, id); }
        for i in type_count(failure) { if !visit(v,1) { return false from bridge_export; } if c.types[terminal(v, type_child(c, failure, i))].tag != TY_UNIT { return reject(v, 2028, id); } }
    }
    var mapped: u32[>..] = []; for i in c.binders.len { mapped.push(0); }
    var input_domains: u32[>..] = []; var read_regions: u32[>..] = [];
    var input_count: u32 = 0; var output_count: u32 = 0; var output_region: u32 = 0; var bytes: u64 = 0;
    if ex.fields.count != argument.fields.count { return reject(v, 2034, id); }
    for i in argument.fields.count { if !visit(v,1) { return false from bridge_export; }
        let field_id = at(c, argument.fields, i); if at(c, ex.fields, i) != field_id { return reject(v, 2034, id); }
        let field = c.fields[field_id]; let field_type = terminal(v, field.type_id); let t = c.types[field_type];
        if t.tag != TY_VIEW && t.tag != TY_DEST {
            if !wire_plain(v, field_type, geometry, 0) { return reject(v, 2028, id); } continue;
        }
        if t.region == 0 || !wire_plain(v, type_child(c, t, 0), geometry, 0) { return reject(v, 2028, id); }
        mapped[t.region] = 1; read_regions.push(t.region);
        var count: u32 = 0; var witness = t.nat;
        if t.tag == TY_VIEW {
            if input_count >= ex.input_maxima.count { return reject(v, 2034, id); }
            count = at(c, ex.input_maxima, input_count); input_count++;
            for domain in input_domains { if !visit(v,1) { return false from bridge_export; } if domain == t.domain { return reject(v, 2012, id); } }
            input_domains.push(t.domain); mapped[t.domain] = 1;
        } else {
            output_count++; count = ex.output_capacity; output_region = t.region; witness = t.capacity;
            if !same_type(v, type_child(c, output, 0), type_child(c, t, 0), 0) { return reject(v, 2003, id); }
        }
        if c.terms[witness].tag == EXPR_BINDER { mapped[c.terms[witness].binder] = 1; }
        else if c.terms[witness].tag != EXPR_LITERAL { return reject(v, 2028, id); }
        let size = geometry[type_child(c, t, 0)].size;
        if size != 0 { bytes = (bytes + 3) / 4 * 4; bytes += (count as u64) * size; }
        if bytes > MAX_U32 { return reject(v, 2023, id); }
    }
    if output_count != 1 || input_count != ex.input_maxima.count || bytes > ex.work_bytes || output.region != output_region { return reject(v, 2023, id); }
    for i in contract.binders.count { if !visit(v,1) { return false from bridge_export; } let bid = at(c, contract.binders, i); if c.binders[bid].kind != KIND_TYPE && mapped[bid] == 0 { return reject(v, 2026, id); } }
    for i in contract.effects.count { if !visit(v,1) { return false from bridge_export; }
        let effect = c.effects[at(c, contract.effects, i)]; var present = false;
        if effect.kind == EFFECT_WRITE { present = effect.region == output_region; }
        if effect.kind == EFFECT_READ { for region in read_regions { if !visit(v,1) { return false from bridge_export; } if region == effect.region { present = true; } } }
        if !present || effect.region == 0 { return reject(v, 2006, id); }
    }
    if ex.depth < 2 + max(contract.depth, 2) || (geometry[ex.arg_type].size as u64) + geometry[ex.result_type].size + 20 + contract.frame > ex.frame { return reject(v, 2023, id); }
    return true;
}

recursive fn edge_term(v: Context, formal: u32, actual: u32, edge_id: u32, depth: u32) -> bool {
    if !proof_visit(v, 1) || depth > LIMIT_NEST { return false; }
    let c = v.c; let edge = c.edges[edge_id]; let params = c.blocks[edge.to].params;
    let a = c.terms[formal]; let b = c.terms[actual];
    if a.tag == EXPR_VALUE {
        for i in params.count { if !proof_visit(v,1) { return false from edge_term; } if at(c, params, i) == a.value { return term_operand(v, actual, at(c, edge.args, i)); } }
        return formal == actual;
    }
    if a.tag == EXPR_LEN || a.tag == EXPR_CAP || a.tag == EXPR_INIT {
        for i in params.count { if !proof_visit(v,1) { return false from edge_term; }
            if at(c, params, i) != a.value { continue; }
            let incoming = at(c, edge.args, i); let ty = c.types[c.values[incoming].type_id];
            if a.tag == EXPR_LEN && ty.tag == TY_VIEW || a.tag == EXPR_INIT && ty.tag == TY_BUILDER { if actual == ty.nat { return true; } }
            if a.tag == EXPR_CAP && (ty.tag == TY_DEST || ty.tag == TY_BUILDER) { if actual == ty.capacity { return true; } }
            return b.tag == a.tag && b.value == incoming && b.version == c.values[incoming].version;
        }
        return formal == actual;
    }
    if a.tag != b.tag || a.literal != b.literal || a.binder != b.binder || a.args.count != b.args.count { return false; }
    if a.args.count == 0 { return formal == actual || a.tag == EXPR_LITERAL && a.literal == b.literal; }
    for i in a.args.count { if !proof_visit(v,1) { return false from edge_term; } if !edge_term(v, at(c, a.args, i), at(c, b.args, i), edge_id, depth + 1) { return false; } }
    return true;
}
fn edge_fact(v: Context, formal: Fact, actual: Fact, edge: u32) -> bool {
    if formal.tag != actual.tag || formal.domain != actual.domain { return false; }
    if !edge_term(v, formal.left, actual.left, edge, 0) || !edge_term(v, formal.right, actual.right, edge, 0) { return false; }
    if formal.third != 0 && actual.third != 0 { return edge_term(v, formal.third, actual.third, edge, 0); }
    return formal.third == actual.third;
}
recursive fn edge_type(v: Context, target: u32, incoming: u32, edge: u32, depth: u32) -> bool {
    if !visit(v, 1) || depth > LIMIT_NEST { return false; }
    let c = v.c; let a = c.types[target]; let b = c.types[incoming];
    if !field_labels(v,a,b) { return false; }
    if a.tag != b.tag || a.region != b.region || a.domain != b.domain || a.mode != b.mode || a.binder != b.binder || a.contract != b.contract || type_count(a) != type_count(b) { return false; }
    if a.nat != b.nat && (a.nat == 0 || b.nat == 0 || !edge_term(v, a.nat, b.nat, edge, 0)) { return false; }
    if a.capacity != b.capacity && (a.capacity == 0 || b.capacity == 0 || !edge_term(v, a.capacity, b.capacity, edge, 0)) { return false; }
    for i in type_count(a) { if !visit(v,1) { return false from edge_type; } if !edge_type(v, type_child(c, a, i), type_child(c, b, i), edge, depth + 1) { return false; } }
    return true;
}
fn loop_assumption(v: Context, id: u32) -> bool {
    let c = v.c; let e = c.evidence[id];
    if e.edge != 0 || e.premises.count != 0 { return false; }
    for loop_info, index in c.loops { if !visit(v,1) { return false from loop_assumption; }
        if index == 0 || !contains(v, loop_info.invariant, id) { continue; }
        let header = c.blocks[loop_info.header];
        if e.scope != header.scope || e.operands.count != header.params.count { return false; }
        for i in header.params.count { if !visit(v,1) { return false from loop_assumption; } if at(c, e.operands, i) != at(c, header.params, i) { return false; } }
        return true;
    }
    return false;
}
fn join_evidence(v: Context, id: u32) -> bool {
    let c = v.c; let e = c.evidence[id];
    if e.operands.count == 0 || e.edge != 0 { return false; }
    let target = c.values[at(c, e.operands, 0)].block_id; let block_info = c.blocks[target];
    if e.scope != block_info.scope { return false; }
    for i in e.operands.count { if !proof_visit(v,1) { return false from join_evidence; } if !contains(v, block_info.params, at(c, e.operands, i)) { return false; } }
    var predecessors: u32 = 0;
    for edge, ei in c.edges {
        if !proof_visit(v, 1) { return false; }
        if ei == 0 || edge.to != target { continue; }
        let terminator = c.terminators[c.blocks[edge.from].term];
        if !contains(v, terminator.edges, ei as u32) { return false; }
        predecessors++; var found = false;
        for pi in e.premises.count { if !proof_visit(v,1) { return false from join_evidence; }
            let premise = at(c, e.premises, pi); let p = c.evidence[premise];
            if edge_fact(v, c.facts[e.fact], c.facts[p.fact], ei as u32) && on_edge(v, premise, ei as u32, 0) { found = true; }
        }
        if !found { return false; }
    }
    return predecessors != 0 && e.premises.count == predecessors;
}
fn successor_fact(v: Context, e: Evidence, f: Fact) -> bool {
    if e.premises.count != 1 { return false; }
    let c = v.c; let p = c.facts[c.evidence[at(c, e.premises, 0)].fact];
    if p.tag != FACT_LT { return false; }
    if f.tag == FACT_ADD_FITS { return f.left == p.left && term_literal(c, f.right, 1); }
    if f.tag == FACT_LE && f.right == p.right {
        let t = c.terms[f.left];
        if t.tag == EXPR_ADD && t.args.count == 2 { return at(c, t.args, 0) == p.left && term_literal(c, at(c, t.args, 1), 1); }
        if t.tag == EXPR_VALUE && t.value != 0 && c.values[t.value].op != 0 {
            let op = c.ops[c.values[t.value].op];
            if op.tag != OP_U32_ADD || op.args.count != 2 { return false; }
            let one, known = literal_value(c, at(c, op.args, 1));
            return known && one == 1 && term_operand(v, p.left, at(c, op.args, 0));
        }
    }
    return false;
}
fn validate_loop(v: Context, id: u32) -> bool {
    let c = v.c; let loop_info = c.loops[id]; let header = c.blocks[loop_info.header]; let term = c.terminators[header.term];
    if header.params.count == 0 || at(c, header.params, 0) != loop_info.index || c.types[c.values[loop_info.index].type_id].tag != TY_U32 ||
        loop_info.carries.count + 1 != header.params.count || term.tag != TERM_BRANCH || term.edges.count != 2 || term.subject == 0 { return reject(v, 2034, id); }
    for i in loop_info.carries.count { if !proof_visit(v,1) { return false from validate_loop; } if at(c, loop_info.carries, i) != at(c, header.params, i + 1) { return reject(v, 2034, id); } }
    let condition_id = c.values[term.subject].op;
    if condition_id == 0 { return reject(v, 2034, id); }
    let condition = c.ops[condition_id];
    if condition.tag != OP_U32_LT || condition.args.count != 2 || at(c, condition.args, 0) != loop_info.index || !term_operand(v, loop_info.upper, at(c, condition.args, 1)) { return reject(v, 2034, id); }
    var entries: u32 = 0; var nexts: u32 = 0; var natural: u32 = 0;
    for edge, ei in c.edges {
        if !proof_visit(v, 1) { return false; }
        if ei == 0 { continue; }
        if edge.from == loop_info.header {
            if edge.kind == EDGE_TRUE && edge.to != loop_info.body || edge.kind == EDGE_FALSE && edge.to != loop_info.exit { return reject(v, 2034, id); }
            if edge.kind == EDGE_FALSE { natural++; if !contains(v, loop_info.exits, ei as u32) { return reject(v, 2034, id); } }
        }
        if edge.to == loop_info.header {
            if edge.loop_id != id || edge.args.count != header.params.count { return reject(v, 2034, ei as u32); }
            if edge.kind == EDGE_LOOP_ENTRY {
                entries++; if !term_operand(v, loop_info.lower, at(c, edge.args, 0)) { return reject(v, 2034, ei as u32); }
                var ordered = false;
                if literal_fact(v, Fact {tag: FACT_LE, left: loop_info.lower, right: loop_info.upper, ..}) { ordered = true; }
                for i in edge.evidence.count { if !proof_visit(v,1) { return false from validate_loop; } let f = c.facts[c.evidence[at(c, edge.evidence, i)].fact]; if f.tag == FACT_LE && f.left == loop_info.lower && f.right == loop_info.upper { ordered = true; } }
                if !ordered { return reject(v, 2011, ei as u32); }
            } else if edge.kind == EDGE_LOOP_NEXT {
                nexts++; if !contains(v, loop_info.backedges, ei as u32) { return reject(v, 2034, ei as u32); }
                let successor = c.values[at(c, edge.args, 0)].op;
                if successor == 0 { return reject(v, 2034, ei as u32); }
                let op = c.ops[successor];
                if op.tag != OP_U32_ADD || op.args.count != 2 || at(c, op.args, 0) != loop_info.index { return reject(v, 2034, ei as u32); }
                let one, literal = literal_value(c, at(c, op.args, 1)); if !literal || one != 1 { return reject(v, 2034, ei as u32); }
            } else { return reject(v, 2034, ei as u32); }
            for i in loop_info.invariant.count { if !proof_visit(v,1) { return false from validate_loop; }
                let invariant = c.facts[c.evidence[at(c, loop_info.invariant, i)].fact]; var established = false;
                for j in edge.evidence.count { if !proof_visit(v,1) { return false from validate_loop; }
                    let proof = at(c, edge.evidence, j);
                    if edge_fact(v, invariant, c.facts[c.evidence[proof].fact], ei as u32) && evidence_usable(v, proof, edge.from, c.blocks[edge.from].ops.count, 0) { established = true; }
                }
                if !established { return reject(v, 2007, ei as u32); }
            }
        }
        if edge.loop_id == id && edge.kind == EDGE_LOOP_STOP {
            if edge.to != loop_info.exit || !contains(v, loop_info.exits, ei as u32) { return reject(v, 2034, ei as u32); }
            // Stop never inherits natural exhaustion; its facts must be explicit
            // and are intersected with the natural edge by RULE_JOIN.
            for i in edge.evidence.count { if !proof_visit(v,1) { return false from validate_loop; } if !evidence_usable(v, at(c, edge.evidence, i), edge.from, c.blocks[edge.from].ops.count, 0) { return reject(v, 2034, ei as u32); } }
        }
    }
    if entries != 1 || natural != 1 || nexts != loop_info.backedges.count { return reject(v, 2034, id); }
    return true;
}

recursive fn on_edge(v: Context, evidence_id: u32, edge_id: u32, depth: u32) -> bool {
    if !proof_visit(v, 1) || depth > LIMIT_TERMS { return false; }
    let c = v.c; let e = c.evidence[evidence_id]; let edge = c.edges[edge_id]; let source = c.blocks[edge.from];
    if e.edge != edge_id { return evidence_usable(v, evidence_id, edge.from, source.ops.count, 0); }
    for i in e.operands.count { if !proof_visit(v,1) { return false from on_edge; } if !use_value(v, at(c, e.operands, i), edge.from, source.ops.count) { return false; } }
    for i in e.premises.count { if !proof_visit(v,1) { return false from on_edge; } if !on_edge(v, at(c, e.premises, i), edge_id, depth + 1) { return false; } }
    return true;
}

fn abi_digest(v:Context, span: Span) -> bool {
    if !visit(v,1) { return false; }
    let c=v.c;
    if !span_ok(span, c.bytes.len) || span.count != 32 { return false; }
    for i in 32 { if !visit(v,1) { return false; } if c.bytes[span.start + i] != ABI_HASH[i] { return false; } }
    return true;
}

recursive fn formal_value(v:Context, formal: u32, arg: u32, result: u32, depth: u32) -> u32 {
    if !visit(v,1) { return 0; }
    let c=v.c;
    if depth > LIMIT_NEST { return 0; }
    let t = c.terms[formal];
    if t.tag == EXPR_ARG { return arg; }
    if t.tag == EXPR_RESULT { return result; }
    if t.tag == EXPR_FIELD && t.args.count == 1 {
        let parent = formal_value(v, at(c, t.args, 0), arg, result, depth + 1);
        if parent == 0 || c.values[parent].op == 0 { return 0; }
        let op = c.ops[c.values[parent].op];
        if (op.tag == OP_TUPLE || op.tag == OP_RECORD) && t.literal < op.args.count { return at(c, op.args, t.literal); }
    }
    return 0;
}
fn loop_range(v: Context, e: Evidence, fact: Fact) -> bool {
    let c = v.c;
    for info, id in c.loops {
        if !proof_visit(v, 1) { return false; }
        if id == 0 { continue; }
        if !contains(v, e.operands, info.index) { continue; }
        if fact.tag == FACT_LE && e.edge == 0 && e.scope == c.blocks[info.header].scope &&
            (fact.left == info.lower && term_operand(v, fact.right, info.index) || term_operand(v, fact.left, info.index) && fact.right == info.upper) { return true; }
        if fact.tag == FACT_EQ && e.edge != 0 {
            let edge = c.edges[e.edge];
            if edge.from == info.header && edge.to == info.exit && edge.kind == EDGE_FALSE &&
                term_operand(v, fact.left, info.index) && fact.right == info.upper { return true; }
        }
    }
    return false;
}

fn environment_binder(v:Context, span: Span, binder: u32, kind: u32) -> bool {
    if !visit(v,1) { return false; }
    let c=v.c;
    for i in span.count { if !visit(v,1) { return false; } let binding = c.environment_bindings[at(c, span, i)]; if binding.binder == binder && binding.kind == kind { return true; } }
    return false;
}

fn checked_congruence(v: Context, e: Evidence, f: Fact) -> bool {
    let c = v.c;
    if f.tag != FACT_EQ || e.premises.count != 2 { return false; }
    if e.operands.count == 1 {
        let result = at(c, e.operands, 0); let operation_id = c.values[result].op;
        if operation_id == 0 { return false; } let op = c.ops[operation_id];
        if op.tag != OP_U32_ADD && op.tag != OP_U32_SUB || op.args.count != 2 { return false; }
        var expression = f.left; var value = f.right;
        if term_operand(v, f.left, result) { expression = f.right; value = f.left; }
        let t = c.terms[expression];
        if !term_operand(v, value, result) || t.args.count != 2 || t.tag != (if op.tag == OP_U32_ADD { EXPR_ADD } else { EXPR_SUB }) { return false; }
        for i in t.args.count { if !visit(v,1) { return false from checked_congruence; }
            let p = c.facts[c.evidence[at(c, e.premises, i)].fact];
            if p.tag != FACT_EQ || p.left != at(c, t.args, i) || !term_operand(v, p.right, at(c, op.args, i)) { return false; }
        }
        return true;
    }
    if e.operands.count != 2 { return false; }
    let a = at(c, e.operands, 0); let b = at(c, e.operands, 1);
    if !term_operand(v, f.left, a) || !term_operand(v, f.right, b) || c.values[a].op == 0 || c.values[b].op == 0 { return false; }
    let left = c.ops[c.values[a].op]; let right = c.ops[c.values[b].op];
    if left.tag != right.tag || left.tag != OP_U32_ADD && left.tag != OP_U32_SUB || left.args.count != 2 || right.args.count != 2 { return false; }
    for i in 2 { if !visit(v,1) { return false from checked_congruence; }
        let p = c.facts[c.evidence[at(c, e.premises, i as u32)].fact];
        if p.tag != FACT_EQ || !term_operand(v, p.left, at(c, left.args, i as u32)) || !term_operand(v, p.right, at(c, right.args, i as u32)) { return false; }
    }
    return true;
}
fn observation_fact(v: Context, e: Evidence, f: Fact) -> bool {
    if f.tag != FACT_EQ || e.operands.count != 1 || e.premises.count != 0 { return false; }
    let c = v.c; let value = at(c, e.operands, 0); let ty = c.types[c.values[value].type_id]; let term = c.terms[f.left];
    if term.value != value || term.version != c.values[value].version { return false; }
    if term.tag == EXPR_LEN && ty.tag == TY_VIEW || term.tag == EXPR_INIT && ty.tag == TY_BUILDER { return f.right == ty.nat; }
    if term.tag == EXPR_CAP && (ty.tag == TY_BUILDER || ty.tag == TY_DEST) { return f.right == ty.capacity; }
    return false;
}

fn unit_error(v:Context, type_id: u32, count: u32) -> bool {
    if !visit(v,1) { return false; }
    let c=v.c;
    let t = c.types[terminal(v, type_id)];
    if t.tag != TY_SUM || type_count(t) != count { return false; }
    for i in count { if !visit(v,1) { return false; } if c.types[terminal(v, type_child(c, t, i))].tag != TY_UNIT { return false; } }
    return true;
}
fn pair(v:Context, type_id: u32) -> bool {
    if !visit(v,1) { return false; }
    let c=v.c;
    let t = c.types[terminal(v, type_id)]; return (t.tag == TY_TUPLE || t.tag == TY_RECORD) && type_count(t) == 2;
}
fn effect_allowed(v: Context, block_id: u32, kind: u32, region: u32) -> bool {
    let c = v.c; let fun = c.functions[c.blocks[block_id].function]; let contract = c.contracts[fun.contract];
    if region != 0 && (kind == EFFECT_READ || kind == EFFECT_WRITE || kind == EFFECT_PLACE || kind == EFFECT_RESET) &&
        !contains(v, contract.binders, region) && c.binders[region].introduction != 0 &&
        in_scope(v,c.blocks[block_id].scope,c.binders[region].scope) && in_scope(v,c.binders[region].scope,c.blocks[fun.entry].scope) { return true; }
    for i in contract.effects.count {
        if !visit(v, 1) { return false; }
        let e = c.effects[at(c, contract.effects, i)];
        if e.kind == kind && (e.region == region || kind == EFFECT_RESERVE || kind == EFFECT_RELEASE) { return true; }
    }
    return false;
}
fn storage_extended(v: Context, id: u32, block_id: u32, geometry: const Geometry[:]) -> bool {
    let c = v.c; let op = c.ops[id];
    if op.results.count != 1 { return reject(v, 2003, id); }
    let result_id = c.values[at(c, op.results, 0)].type_id; let result = c.types[terminal(v, result_id)];
    if op.tag == OP_CHECKED_ADD || op.tag == OP_CHECKED_SUB || op.tag == OP_CHECKED_MUL || op.tag == OP_CHECKED_DIV || op.tag == OP_CHECKED_SHL || op.tag == OP_CHECKED_SHR || op.tag == OP_F32_TO_U32 {
        var arity: u32 = 2; var input = TY_U32; if op.tag == OP_F32_TO_U32 { arity = 1; input = TY_F32; }
        if op.args.count != arity || result.tag != TY_RESULT || c.types[type_child(c, result, 0)].tag != TY_U32 || c.types[type_child(c, result, 1)].tag != TY_UNIT { return reject(v, 2003, id); }
        for i in op.args.count { if !visit(v,1) { return false from storage_extended; } if c.types[c.values[at(c, op.args, i)].type_id].tag != input { return reject(v, 2003, id); } }
        return true;
    }
    if op.tag == OP_RESERVE || op.tag == OP_OWNED_BEGIN {
        if op.args.count != 1 || c.types[c.values[at(c, op.args, 0)].type_id].tag != TY_U32 || result.tag != TY_RESULT || !pair(v, type_child(c, result, 0)) || !unit_error(v, type_child(c, result, 1), 3) { return reject(v, 2003, id); }
        let success = c.types[terminal(v, type_child(c, result, 0))]; let owner = c.types[type_child(c, success, 0)]; let space = c.types[type_child(c, success, 1)];
        var wanted = TY_REGION_OWNER; var scope = SCOPE_REGION;
        if op.tag == OP_OWNED_BEGIN { wanted = TY_OWNED_CONSTRUCTION; scope = SCOPE_OWNED; }
        if owner.tag != wanted || space.tag != TY_SPACE || owner.region != space.region || owner.region == 0 || op.scope == 0 || c.scopes[op.scope].kind != scope ||
            c.binders[owner.region].scope != op.scope || c.binders[owner.region].introduction != id || c.binders[owner.region].introduction_kind != INTRO_OPERATION { return reject(v, 2016, id); }
        if !effect_allowed(v, block_id, EFFECT_RESERVE, 0) { return reject(v, 2006, id); }
        if c.contracts[c.functions[c.blocks[block_id].function].contract].depth < 3 { return reject(v, 2023, id); }
        return true;
    }
    if op.tag == OP_TRY_ALLOC || op.tag == OP_ENV_TRY_ALLOC {
        if op.args.count != 2 || result.tag != TY_RESULT || !pair(v, type_child(c, result, 0)) || !pair(v, type_child(c, result, 1)) { return reject(v, 2003, id); }
        let space_id = c.values[at(c, op.args, 0)].type_id; let space = c.types[space_id];
        if space.tag != TY_SPACE || c.types[c.values[at(c, op.args, 1)].type_id].tag != TY_U32 { return reject(v, 2003, id); }
        let yes = c.types[type_child(c, result, 0)]; let no = c.types[type_child(c, result, 1)];
        if !same_type(v, type_child(c, yes, 0), space_id, 0) || !same_type(v, type_child(c, no, 0), space_id, 0) || !unit_error(v, type_child(c, no, 1), 2) { return reject(v, 2003, id); }
        let dest = c.types[type_child(c, yes, 1)]; var wanted = TY_DEST; if op.tag == OP_ENV_TRY_ALLOC { wanted = TY_ENV_DEST; }
        if dest.tag != wanted || dest.region != space.region || !term_operand(v, dest.capacity, at(c, op.args, 1)) { return reject(v, 2003, id); }
        if op.tag == OP_TRY_ALLOC && (!id_ok(op.imm0, c.types.len) || !geometry[op.imm0].plain || !same_type(v, type_child(c, dest, 0), op.imm0, 0)) { return reject(v, 2003, id); }
        if !effect_allowed(v, block_id, EFFECT_PLACE, space.region) { return reject(v, 2006, id); }
        if c.contracts[c.functions[c.blocks[block_id].function].contract].depth < 3 { return reject(v, 2023, id); }
        return true;
    }
    if op.tag == OP_BUILDER_FREEZE {
        if op.args.count != 1 || result.tag != TY_EXISTS { return reject(v, 2003, id); }
        let builder = c.types[c.values[at(c, op.args, 0)].type_id]; let view = c.types[type_child(c, result, 0)];
        if builder.tag != TY_BUILDER || view.tag != TY_VIEW || builder.region != view.region || !same_type(v, type_child(c, builder, 0), type_child(c, view, 0), 0) || !contains(v, result.binders, view.domain) { return reject(v, 2003, id); }
        if builder.nat != view.nat {
            let witness = c.terms[view.nat];
            if witness.tag != EXPR_BINDER || !contains(v, result.binders, witness.binder) { return reject(v, 2018, id); }
        }
        var nat_count: u32 = 0; var domain_count: u32 = 0;
        for i in result.binders.count { if !visit(v,1) { return false from storage_extended; } let bid = at(c, result.binders, i); if c.binders[bid].kind == KIND_NAT { nat_count++; } if c.binders[bid].kind == KIND_DOMAIN { domain_count++; } }
        if nat_count > 1 || domain_count != 1 { return reject(v, 2004, id); }
        return true;
    }
    if op.tag == OP_TRY_INDEX {
        if op.args.count != 2 || result.tag != TY_SUM || type_count(result) != 2 || c.types[type_child(c, result, 0)].tag != TY_UNIT { return reject(v, 2003, id); }
        let view = c.types[c.values[at(c, op.args, 0)].type_id]; let index = c.types[type_child(c, result, 1)];
        if view.tag != TY_VIEW || c.types[c.values[at(c, op.args, 1)].type_id].tag != TY_U32 || index.tag != TY_INDEX || index.domain != view.domain || index.nat != view.nat { return reject(v, 2012, id); }
        if !effect_allowed(v, block_id, EFFECT_READ, view.region) { return reject(v, 2006, id); }
        return true;
    }
    if op.tag == OP_BUILDER_TRY_APPEND {
        if op.args.count != 2 || result.tag != TY_RESULT || !pair(v, type_child(c, result, 1)) { return reject(v, 2003, id); }
        let before_id = c.values[at(c, op.args, 0)].type_id; let before = c.types[before_id]; let after = c.types[type_child(c, result, 0)]; let failed = c.types[type_child(c, result, 1)];
        if before.tag != TY_BUILDER || after.tag != TY_BUILDER || before.region != after.region || before.mode != after.mode || before.capacity != after.capacity ||
            !same_type(v, type_child(c, before, 0), type_child(c, after, 0), 0) || !same_type(v, before_id, type_child(c, failed, 0), 0) ||
            !same_type(v, c.values[at(c, op.args, 1)].type_id, type_child(c, failed, 1), 0) || !same_type(v, type_child(c, before, 0), type_child(c, failed, 1), 0) { return reject(v, 2003, id); }
        let next = c.terms[after.nat];
        if next.tag != EXPR_ADD || next.args.count != 2 || at(c, next.args, 0) != before.nat || !term_literal(c, at(c, next.args, 1), 1) { return reject(v, 2018, id); }
        if !effect_allowed(v, block_id, EFFECT_WRITE, before.region) { return reject(v, 2006, id); }
        return true;
    }
    return reject(v, 2028, id);
}

fn representation_abi(v:Context, type_id: u32) -> u32 {
    if !visit(v,1) { return 0; }
    let c=v.c;
    let t = c.types[terminal(v, type_id)].tag;
    if t == TY_UNIT { return ABI_UNIT; }
    if t == TY_U32 || t == TY_BOOL || t == TY_INDEX { return ABI_I32; }
    if t == TY_F32 { return ABI_F32; }
    return ABI_INDIRECT;
}
fn validate_abi_plan(v: Context, plan: AbiPlan, geometry: const Geometry[:]) -> bool {
    let c = v.c; let contract = c.contracts[plan.contract];
    if !same_type(v, c.layouts[plan.arg_layout].type_id, contract.arg, 0) || !same_type(v, c.layouts[plan.result_layout].type_id, contract.result, 0) { return reject(v, 2034, plan.contract); }
    var dictionary: u32 = 0; var nat: u32 = 0;
    for i in contract.binders.count {
        if !visit(v, 1) { return false; }
        let bid = at(c, contract.binders, i); let binder = c.binders[bid];
        if binder.kind == KIND_TYPE {
            if dictionary >= plan.dictionaries.count || at(c, plan.dictionaries, dictionary) != bid { return reject(v, 2034, bid); } dictionary++;
        }
        if binder.kind == KIND_NAT {
            if nat >= plan.nat_witnesses.count { return reject(v, 2034, bid); }
            let witness = c.nat_witnesses[at(c, plan.nat_witnesses, nat)]; nat++;
            if witness.binder != bid { return reject(v, 2034, bid); }
            if witness.selector == NAT_HIDDEN { if witness.argument_path.count != 0 { return reject(v, 2034, bid); } continue; }
            var type_id = contract.arg;
            for p in witness.argument_path.count { if !visit(v,1) { return false from validate_abi_plan; }
                let t = c.types[terminal(v, type_id)]; let field = at(c, witness.argument_path, p);
                if t.tag != TY_TUPLE && t.tag != TY_RECORD || field >= type_count(t) { return reject(v, 2034, bid); }
                type_id = type_child(c, t, field);
            }
            let t = c.types[terminal(v, type_id)]; var term: u32 = 0;
            if witness.selector == NAT_VIEW_LEN && t.tag == TY_VIEW || witness.selector == NAT_BUILDER_INIT && t.tag == TY_BUILDER { term = t.nat; }
            if witness.selector == NAT_DEST_CAP && t.tag == TY_DEST || witness.selector == NAT_BUILDER_CAP && t.tag == TY_BUILDER { term = t.capacity; }
            if term == 0 || c.terms[term].tag != EXPR_BINDER || c.terms[term].binder != bid { return reject(v, 2034, bid); }
        }
    }
    if dictionary != plan.dictionaries.count || nat != plan.nat_witnesses.count { return reject(v, 2034, plan.contract); }
    if plan.function != 0 {
        let f = c.functions[plan.function];
        if plan.env_layout == 0 { return reject(v, 2034, plan.function); }
        let env = c.types[terminal(v, c.layouts[plan.env_layout].type_id)];
        if f.environment_bindings.count + f.captures.count == 0 { if env.tag != TY_UNIT { return reject(v, 2019, plan.function); } }
        else {
            if env.tag != TY_TUPLE || type_count(env) != f.environment_bindings.count + f.captures.count { return reject(v, 2019, plan.function); }
            for i in f.environment_bindings.count { if !visit(v,1) { return false from validate_abi_plan; } if c.types[type_child(c, env, i)].tag != TY_U32 { return reject(v, 2019, plan.function); } }
            for i in f.captures.count { if !visit(v,1) { return false from validate_abi_plan; } let capture = c.captures[at(c, f.captures, i)]; if !same_type(v, type_child(c, env, i + f.environment_bindings.count), c.values[capture.value].type_id, 0) { return reject(v, 2019, plan.function); } }
        }
    }
    return true;
}

recursive fn refine_type(parent:Context, source: u32, target: u32, op: Operation, block_id: u32, depth: u32) -> bool {
    let v=proof_context(parent);
    if !visit(v, 1) || depth > LIMIT_NEST { return false; }
    let c = v.c; let a = c.types[terminal(v, source)]; let b = c.types[terminal(v, target)];
    if !field_labels(v,a,b) { return false; }
    if a.tag != b.tag || a.region != b.region || a.domain != b.domain || a.capacity != b.capacity || a.mode != b.mode || a.contract != b.contract || a.binder != b.binder || type_count(a) != type_count(b) || a.binders.count != b.binders.count { return false; }
    for i in a.binders.count { if !visit(v,1) { return false from refine_type; } if at(c, a.binders, i) != at(c, b.binders, i) { return false; } }
    if a.nat != b.nat {
        if a.nat == 0 || b.nat == 0 || !(term_relation(v, op, block_id, FACT_EQ, a.nat, b.nat) || term_relation(v, op, block_id, FACT_EQ, b.nat, a.nat)) { return false; }
    }
    for i in type_count(a) { if !visit(v,1) { return false from refine_type; } if !refine_type(v, type_child(c, a, i), type_child(c, b, i), op, block_id, depth + 1) { return false; } }
    return true;
}

recursive fn capture_lifetime(v: Context, type_id: u32, target_region: u32, depth: u32) -> bool {
    if !visit(v, 1) || depth > LIMIT_NEST { return false; }
    let c = v.c; let t = c.types[type_id];
    if t.tag == TY_VIEW || t.tag == TY_FN {
        if t.region != 0 && t.region != target_region {
            if target_region == 0 || c.binders[target_region].introduction == 0 || !in_scope(v, c.binders[target_region].scope, c.binders[t.region].scope) { return false; }
        }
        if t.tag == TY_FN { return true; }
    }
    for i in type_count(t) { if !visit(v,1) { return false from capture_lifetime; } if !capture_lifetime(v, type_child(c, t, i), target_region, depth + 1) { return false; } }
    return true;
}

fn owned_payload(v: Context, type_id: u32, hole: u32, depth: u32) -> bool {
    var bound:u32[>..<]=[]; return owned_payload_closed(v,type_id,hole,bound,depth);
}
recursive fn owned_witness(v:Context,term_id:u32,bound:const u32[:],depth:u32)->bool {
    if term_id==0 { return true; } if !visit(v,1) || depth>LIMIT_NEST { return false; } let c=v.c; let term=c.terms[term_id];
    if term.value!=0 || term.tag==EXPR_ARG || term.tag==EXPR_RESULT { return false; }
    if term.tag==EXPR_BINDER && !interface_binder(v,term.binder,bound) { return false; }
    for i in term.args.count { if !visit(v,1) { return false from owned_witness; } if !owned_witness(v,at(c,term.args,i),bound,depth+1) { return false; } } return true;
}
recursive fn owned_payload_closed(v:Context,type_id:u32,hole:u32,bound:u32[>..<]&,depth:u32)->bool {
    if !visit(v,1) || depth>LIMIT_NEST { return false; } let c=v.c; let t=c.types[type_id];
    if t.tag==TY_OWNED || t.tag==TY_FN && t.mode!=MODE_MANY || t.region!=0 && t.region!=hole { return false; }
    if t.tag==TY_PARAM && c.binders[t.binder].constraints & CONSTRAINT_PLAIN==0 { return false; }
    let mark=bound.len; if t.tag==TY_EXISTS { for i in t.binders.count { if !visit(v,1) { return false from owned_payload_closed; } bound.push(at(c,t.binders,i)); } }
    if !interface_binder(v,t.domain,bound) || !owned_witness(v,t.nat,bound,0) || !owned_witness(v,t.capacity,bound,0) { return false; }
    for i in type_count(t) { if !visit(v,1) { return false from owned_payload_closed; } if !owned_payload_closed(v,type_child(c,t,i),hole,bound,depth+1) { return false; } }
    bound.resize(mark); return true;
}
fn owned_borrow_conflict(v: Context, owner: u32, scope: u32) -> bool {
    let c = v.c;
    for op, id in c.ops {
        if !visit(v, 1) { return true; }
        if id == 0 || op.tag != OP_OWNED_OPEN || op.args.count != 1 { continue; }
        if in_scope(v, scope, op.scope) && owned_alias(v, at(c, op.args, 0), owner, 0) { return true; }
    }
    return false;
}
fn owned_operation(v: Context, id: u32, block_id: u32, geometry: const Geometry[:]) -> bool {
    let c = v.c; let op = c.ops[id];
    if op.results.count != 1 || op.args.count == 0 { return reject(v, 2003, id); }
    let owner_id = c.values[at(c, op.args, 0)].type_id; let owner = c.types[terminal(v, owner_id)];
    let result_id = c.values[at(c, op.results, 0)].type_id; let result = c.types[terminal(v, result_id)];
    if c.contracts[c.functions[c.blocks[block_id].function].contract].depth < 3 { return reject(v, 2023, id); }
    if op.tag == OP_OWNED_ABORT {
        if op.args.count != 1 || owner.tag != TY_OWNED_CONSTRUCTION || result.tag != TY_UNIT || c.scopes[op.scope].kind != SCOPE_OWNED || c.binders[owner.region].scope != op.scope { return reject(v, 2003, id); }
        if !effect_allowed(v, block_id, EFFECT_RELEASE, 0) { return reject(v, 2006, id); }
        return true;
    }
    if op.tag == OP_OWNED_CLOSE {
        if op.args.count != 1 || owner.tag != TY_OWNED || result.tag != TY_UNIT { return reject(v, 2003, id); }
        if !effect_allowed(v, block_id, EFFECT_RELEASE, 0) { return reject(v, 2006, id); }
        return true;
    }
    if op.tag == OP_OWNED_SEAL {
        if op.args.count != 2 || owner.tag != TY_OWNED_CONSTRUCTION || result.tag != TY_OWNED || c.scopes[op.scope].kind != SCOPE_OWNED || c.binders[owner.region].scope != op.scope { return reject(v, 2003, id); }
        let payload = c.values[at(c, op.args, 1)].type_id;
        if !geometry[payload].share || !substitutions_valid(v, result.binders, op.substitutions, geometry) ||
            !instantiated_type(v, type_child(c, result, 0), payload, op.substitutions, 0) { return reject(v, 2020, id); }
        let mapped, found = substitution(v, op.substitutions, at(c, result.binders, 0));
        if !found || mapped != owner.region || !owned_payload(v, payload, owner.region, 0) { return reject(v, 2020, id); }
        return true;
    }
    if op.tag == OP_OWNED_OPEN {
        if op.args.count != 1 || owner.tag != TY_OWNED || op.scope == 0 || c.scopes[op.scope].kind != SCOPE_LOAN || !substitutions_valid(v, owner.binders, op.substitutions, geometry) ||
            !instantiated_type(v, type_child(c, owner, 0), result_id, op.substitutions, 0) { return reject(v, 2020, id); }
        let fresh, found = substitution(v, op.substitutions, at(c, owner.binders, 0));
        if !found || fresh == 0 || c.binders[fresh].scope != op.scope || c.binders[fresh].introduction != id { return reject(v, 2016, id); }
        return true;
    }
    return reject(v, 2028, id);
}
fn construction_exit(v: Context, op: Operation, block_id: u32, position: u32, geometry: const Geometry[:], live: const u32[:], affine: const u32[:]) -> bool {
    let c = v.c; let owner = at(c, op.args, 0); let region = c.types[c.values[owner].type_id].region;
    for value in affine { if !visit(v,1) { return false from construction_exit; }
        if live[value] != 0 && value != owner && type_region(v, c.values[value].type_id, region, 0) { return reject(v, 2015, value); }
    }
    let basic = c.blocks[block_id];
    for i in position + 1..basic.ops.count { if !visit(v,1) { return false from construction_exit; }
        let later = c.ops[at(c, basic.ops, i)];
        for j in later.args.count { if !visit(v,1) { return false from construction_exit; } if type_region(v, c.values[at(c, later.args, j)].type_id, region, 0) { return reject(v, 2016, at(c, basic.ops, i)); } }
    }
    let term = c.terminators[basic.term];
    for i in term.edges.count { if !visit(v,1) { return false from construction_exit; }
        let edge = c.edges[at(c, term.edges, i)];
        if in_scope(v, c.blocks[edge.to].scope, op.scope) { return reject(v, 2016, block_id); }
        for j in edge.args.count { if !visit(v,1) { return false from construction_exit; } if type_region(v, c.values[at(c, edge.args, j)].type_id, region, 0) { return reject(v, 2016, at(c, edge.args, j)); } }
    }
    if term.tag == TERM_RETURN && type_region(v, c.values[term.subject].type_id, region, 0) { return reject(v, 2016, term.subject); }
    return true;
}

recursive fn owned_alias(v: Context, left: u32, right: u32, depth: u32) -> bool {
    if left == right { return true; }
    if !visit(v, 1) || depth > LIMIT_NEST { return true; }
    let c = v.c;
    let lv = c.values[left]; let rv = c.values[right];
    if lv.op != 0 && (c.ops[lv.op].tag == OP_COPY || c.ops[lv.op].tag == OP_REFINE) { return owned_alias(v, at(c, c.ops[lv.op].args, 0), right, depth + 1); }
    if rv.op != 0 {
        let op = c.ops[rv.op];
        if op.tag == OP_COPY || op.tag == OP_REFINE { return owned_alias(v, left, at(c, op.args, 0), depth + 1); }
        if op.tag == OP_PAYLOAD {
            let container = c.values[at(c, op.args, 0)].op;
            if container != 0 && c.ops[container].tag == OP_SUM && c.ops[container].imm0 == op.imm0 { return owned_alias(v, left, at(c, c.ops[container].args, 0), depth + 1); }
        }
        if op.tag == OP_DESTRUCTURE {
            let container = c.values[at(c, op.args, 0)].op;
            if container != 0 && (c.ops[container].tag == OP_TUPLE || c.ops[container].tag == OP_RECORD) {
                for i in op.results.count { if !visit(v,1) { return false from owned_alias; } if at(c, op.results, i) == right { return owned_alias(v, left, at(c, c.ops[container].args, i), depth + 1); } }
            }
        }
        return false;
    }
    let basic = c.blocks[rv.block_id];
    if rv.block_id == c.functions[basic.function].entry { return false; }
    for i in basic.params.count { if !visit(v,1) { return false from owned_alias; }
        if at(c, basic.params, i) != right { continue; }
        for edge, ei in c.edges { if !visit(v,1) { return false from owned_alias; }
            if ei != 0 && edge.to == rv.block_id && owned_alias(v, left, at(c, edge.args, i), depth + 1) { return true; }
        }
    }
    return false;
}

fn registry_arity(op: Operation) -> bool {
    if op.tag==OP_GENERIC_BIND { return op.results.count==0; }
    let tag = op.tag;
    if tag == OP_DESTRUCTURE { return op.args.count == 1; }
    if tag == OP_OPEN { return op.args.count == 1 && op.results.count >= 1; }
    if op.results.count != 1 { return false; }
    if tag == OP_TUPLE || tag == OP_RECORD || tag == OP_CLOSURE { return true; }
    if tag == OP_PACK || tag == OP_FN_PLACE { return op.args.count >= 1; }
    if tag >= OP_UNIT && tag <= OP_F32 || tag == OP_NAT_VALUE || tag == OP_STATIC || tag == OP_LAYOUT_SIZE || tag == OP_LAYOUT_ALIGN { return op.args.count == 0; }
    if tag == OP_BUILDER_SET || tag == OP_VIEW_SLICE { return op.args.count == 3; }
    if scalar_binary(tag) != 0 || tag == OP_CALL_INDIRECT || tag == OP_CHECKED_ADD || tag == OP_CHECKED_SUB || tag == OP_CHECKED_MUL ||
        tag == OP_TRY_ALLOC || tag == OP_ENV_TRY_ALLOC || tag == OP_DEST_SPLIT || tag == OP_BUILDER_APPEND || tag == OP_BUILDER_TRY_APPEND ||
        tag == OP_BUILDER_TRUNCATE || tag == OP_VIEW_INDEX || tag == OP_BUILDER_GET || tag == OP_TRY_INDEX || tag == OP_OWNED_SEAL ||
        tag == OP_F32_MIN || tag == OP_F32_MAX || tag == OP_CHECKED_DIV || tag == OP_CHECKED_SHL || tag == OP_CHECKED_SHR { return op.args.count == 2; }
    return op.args.count == 1;
}

recursive fn formal_same(v: Context, a: u32, b: u32, left_contract: u32, right_contract: u32, depth: u32) -> bool {
    if !proof_visit(v, 1) || depth > LIMIT_NEST { return false; }
    let c = v.c; let x = c.terms[a]; let y = c.terms[b];
    if x.tag != y.tag || x.literal != y.literal || x.args.count != y.args.count { return false; }
    if x.tag == EXPR_ARG || x.tag == EXPR_RESULT { return x.binder == left_contract && y.binder == right_contract; }
    if x.tag == EXPR_BINDER { return x.binder == y.binder; }
    if x.value != y.value || x.version != y.version { return false; }
    for i in x.args.count { if !proof_visit(v,1) { return false from formal_same; } if !formal_same(v, at(c, x.args, i), at(c, y.args, i), left_contract, right_contract, depth + 1) { return false; } }
    return true;
}
fn clause_included(v: Context, left: Span, right: Span, a: u32, b: u32) -> bool {
    if left.count != right.count { return false; }
    let c = v.c;
    for i in left.count { if !visit(v,1) { return false from clause_included; }
        let x = c.facts[at(c, left, i)]; var found = false;
        for j in right.count { if !visit(v,1) { return false from clause_included; }
            let y = c.facts[at(c, right, j)];
            if x.tag == y.tag && x.domain == y.domain && formal_same(v, x.left, y.left, a, b, 0) && formal_same(v, x.right, y.right, a, b, 0) {
                if x.third == 0 && y.third == 0 { found = true; }
                else if x.third != 0 && y.third != 0 && formal_same(v, x.third, y.third, a, b, 0) { found = true; }
            }
        }
        if !found { return false; }
    }
    return true;
}
fn weaken_callable(v: Context, source: u32, target: u32) -> bool {
    let c = v.c; let a = c.types[terminal(v, source)]; let b = c.types[terminal(v, target)];
    if a.tag != TY_FN || b.tag != TY_FN || a.mode == MODE_ONCE && b.mode != MODE_ONCE || !same_type(v, type_child(c, a, 0), type_child(c, b, 0), 0) || !same_type(v, type_child(c, a, 1), type_child(c, b, 1), 0) { return false; }
    if a.region != b.region && a.region != 0 {
        if b.region == 0 || c.binders[b.region].introduction == 0 || !in_scope(v, c.binders[b.region].scope, c.binders[a.region].scope) { return false; }
    }
    return weaken_contract(v,a.contract,b.contract);
}
fn weaken_contract(v:Context,source:u32,target:u32)->bool {
    let c=v.c; let x = c.contracts[source]; let y = c.contracts[target];
    if x.depth > y.depth || x.frame > y.frame || x.binders.count != y.binders.count || !call_effects(v, y, x, Span{..}) { return false; }
    for i in x.binders.count { if !visit(v,1) { return false from weaken_contract; } if at(c, x.binders, i) != at(c, y.binders, i) { return false; } }
    return clause_same(v, x.requires, y.requires, source, target) && clause_same(v, x.ensures, y.ensures, source, target) &&
        clause_same(v, x.on_true, y.on_true, source, target) && clause_same(v, x.on_false, y.on_false, source, target);
}

fn clause_same(v: Context, left: Span, right: Span, a: u32, b: u32) -> bool {
    return clause_included(v,left,right,a,b) && clause_included(v,right,left,b,a);
}

// An instantiated first-class generic callable has its own complete callback
// contract. Reconstruct its interface from the generic declaration; a producer
// cannot change facts/effects while merely changing the callback ABI.
recursive fn specialized_term(v: Context, left: u32, right: u32, a: u32, b: u32, subs: Span, depth: u32) -> bool {
    if !proof_visit(v, 1) || depth > LIMIT_NEST { return false; }
    let c = v.c; let x = c.terms[left]; let y = c.terms[right];
    if x.tag == EXPR_BINDER {
        let replacement, found = substitution(v, subs, x.binder);
        if found { return replacement == right; }
        return y.tag == EXPR_BINDER && x.binder == y.binder;
    }
    if x.tag != y.tag || x.literal != y.literal || x.args.count != y.args.count { return false; }
    if x.tag == EXPR_ARG || x.tag == EXPR_RESULT { return x.binder == a && y.binder == b; }
    if x.value != y.value || x.version != y.version { return false; }
    for i in x.args.count { if !proof_visit(v,1) { return false from specialized_term; } if !specialized_term(v, at(c, x.args, i), at(c, y.args, i), a, b, subs, depth + 1) { return false; } }
    return true;
}
fn specialized_clause(v: Context, left: Span, right: Span, a: u32, b: u32, subs: Span) -> bool {
    if left.count != right.count { return false; }
    let c = v.c;
    for i in left.count { if !visit(v,1) { return false from specialized_clause; }
        let x = c.facts[at(c, left, i)]; var found = false;
        for j in right.count { if !visit(v,1) { return false from specialized_clause; }
            let y = c.facts[at(c, right, j)];
            if x.tag == y.tag && binder_match(v, x.domain, y.domain, subs) && specialized_term(v, x.left, y.left, a, b, subs, 0) && specialized_term(v, x.right, y.right, a, b, subs, 0) {
                if x.third == 0 && y.third == 0 { found = true; }
                else if x.third != 0 && y.third != 0 && specialized_term(v, x.third, y.third, a, b, subs, 0) { found = true; }
            }
        }
        if !found { return false; }
    }
    return true;
}
fn specialized_contract(v: Context, source: u32, target: u32, subs: Span, geometry: const Geometry[:]) -> bool {
    let c = v.c; let a = c.contracts[source]; let b = c.contracts[target];
    if b.binders.count != 0 || !substitutions_valid(v, a.binders, subs, geometry) || !instantiated_type(v, a.arg, b.arg, subs, 0) || !instantiated_type(v, a.result, b.result, subs, 0) { return false; }
    if !specialized_clause(v, a.requires, b.requires, source, target, subs) || !specialized_clause(v, a.ensures, b.ensures, source, target, subs) ||
        !specialized_clause(v, a.on_true, b.on_true, source, target, subs) || !specialized_clause(v, a.on_false, b.on_false, source, target, subs) || a.effects.count != b.effects.count { return false; }
    for i in a.effects.count { if !visit(v,1) { return false from specialized_contract; }
        let x = c.effects[at(c, a.effects, i)]; var found = false;
        for j in b.effects.count { if !visit(v,1) { return false from specialized_contract; } let y = c.effects[at(c, b.effects, j)]; if x.kind == y.kind && binder_match(v, x.region, y.region, subs) { found = true; } }
        if !found { return false; }
    }
    var spill: u32 = 0;
    if representation_abi(v, a.arg) == ABI_INDIRECT && representation_abi(v, b.arg) != ABI_INDIRECT { spill += geometry[b.arg].size; }
    if representation_abi(v, a.result) == ABI_INDIRECT && representation_abi(v, b.result) != ABI_INDIRECT { spill += geometry[b.result].size; }
    return b.depth > a.depth && b.frame >= a.frame && b.frame - a.frame >= spill;
}

fn checked_success(v: Context, e: Evidence, f: Fact) -> bool {
    let c = v.c;
    if e.operands.count != 2 || e.premises.count != 0 || e.edge == 0 { return false; }
    let original = at(c, e.operands, 0); let payload = at(c, e.operands, 1);
    if c.values[original].op == 0 || c.values[payload].op == 0 { return false; }
    let op = c.ops[c.values[original].op]; let extract = c.ops[c.values[payload].op]; let edge = c.edges[e.edge];
    let branch = c.terminators[c.blocks[edge.from].term];
    if edge.kind != EDGE_CASE || edge.case_tag != 0 || branch.tag != TERM_SWITCH || branch.subject != original || !contains(v, branch.edges, e.edge) ||
        extract.tag != OP_PAYLOAD || extract.imm0 != 0 || !case_payload_allowed(v, at(c, extract.args, 0), 0, c.values[payload].block_id) { return false; }
    var exact = at(c, extract.args, 0) == original;
    let target = c.blocks[edge.to];
    for i in target.params.count { if !visit(v,1) { return false from checked_success; } if at(c, target.params, i) == at(c, extract.args, 0) && at(c, edge.args, i) == original { exact = true; } }
    if !exact || !dominates(v, edge.to, c.values[payload].block_id) { return false; }
    if op.args.count != 2 { return false; }
    let left = at(c, op.args, 0); let right = at(c, op.args, 1);
    if op.tag == OP_CHECKED_ADD { return f.tag == FACT_ADD_FITS && term_operand(v, f.left, left) && term_operand(v, f.right, right); }
    if op.tag == OP_CHECKED_SUB { return f.tag == FACT_SUB_FITS && term_operand(v, f.left, left) && term_operand(v, f.right, right); }
    if op.tag == OP_CHECKED_MUL { return f.tag == FACT_MUL_FITS && term_operand(v, f.left, left) && term_operand(v, f.right, right); }
    if op.tag == OP_CHECKED_DIV { return f.tag == FACT_LT && term_literal(c, f.left, 0) && term_operand(v, f.right, right); }
    if op.tag == OP_CHECKED_SHL || op.tag == OP_CHECKED_SHR { return f.tag == FACT_LT && term_operand(v, f.left, right) && term_literal(c, f.right, 32); }
    return false;
}

fn layout_schema(v: Context, layout: Layout) -> bool {
    let c = v.c; if !id_ok(layout.schema, c.schemas.len) { return false; }
    let schema = c.schemas[layout.schema]; var exact: u8[>..] = [];
    if !canonical_interface(c, layout.type_id, exact) { return false; }
    for word in [layout.size,layout.align,layout.flags,layout.abi] { if !visit(v,1) { return false from layout_schema; } for byte in 4 { if !visit(v,1) { return false from layout_schema; } exact.push((word >> (8*byte)) as! u8); } }
    if !visit(v, exact.len as u64) || exact != c.bytes[schema.bytes.start..schema.bytes.start+schema.bytes.count] { return false; }
    let digest = k1hash::blake3(exact);
    for word, index in digest.words { if !visit(v,1) { return false from layout_schema; } for byte in 4 { if !visit(v,1) { return false from layout_schema; } if c.bytes[schema.digest.start + index*4 + byte] != (word >> (8*byte)) as! u8 { return false; } } }
    return true;
}

fn instantiated_callable_contract(v: Context, source: u32, target: u32, subs: Span) -> bool {
    if source == target { return true; }
    let c = v.c; let a = c.contracts[source]; let b = c.contracts[target];
    if a.depth != b.depth || a.frame != b.frame || a.binders.count != b.binders.count || a.effects.count != b.effects.count { return false; }
    for i in a.binders.count { if !visit(v,1) { return false from instantiated_callable_contract; } if at(c, a.binders, i) != at(c, b.binders, i) { return false; } }
    if !specialized_clause(v, a.requires, b.requires, source, target, subs) || !specialized_clause(v, a.ensures, b.ensures, source, target, subs) ||
        !specialized_clause(v, a.on_true, b.on_true, source, target, subs) || !specialized_clause(v, a.on_false, b.on_false, source, target, subs) { return false; }
    for i in a.effects.count { if !visit(v,1) { return false from instantiated_callable_contract; }
        let x = c.effects[at(c, a.effects, i)]; var found = false;
        for j in b.effects.count { if !visit(v,1) { return false from instantiated_callable_contract; } let y = c.effects[at(c, b.effects, j)]; if x.kind == y.kind && binder_match(v, x.region, y.region, subs) { found = true; } }
        if !found { return false; }
    }
    return true;
}

fn static_word(c: Core, bytes: Span, offset: u32) -> u32 {
    let at = bytes.start + offset;
    return c.bytes[at] as u32 | (c.bytes[at+1] as u32 << 8) | (c.bytes[at+2] as u32 << 16) | (c.bytes[at+3] as u32 << 24);
}
fn static_relocation(v: Context, object: StaticObject, offset: u32, used: u32[>..]&) -> u32 {
    var result:u32=0;
    for i in object.relocations.count {
        if !visit(v,1) { return 0; }
        let id=at(v.c,object.relocations,i); let relocation=v.c.static_relocations[id];
        if relocation.offset==offset { if result != 0 || used[id] != 0 { return 0; } result=id; }
    }
    if result != 0 { used[result]=1; }
    return result;
}
struct StaticWitness { binder:u32, kind:u32, value:u32, object:u32, addend:u32, count:u32, established:bool }
recursive fn static_nat(v:Context,id:u32,bindings:const StaticWitness[:],depth:u32)->u32,bool {
    if !visit(v,1) || depth>LIMIT_TERMS { return 0,false; } let c=v.c; let t=c.terms[id];
    if t.tag==EXPR_LITERAL { return t.literal,true; }
    if t.tag==EXPR_BINDER { var i=bindings.len; while i>0 { if !visit(v,1) { return 0,false from static_nat; } i--; let bound=bindings[i]; if bound.kind==KIND_NAT && bound.binder==t.binder { return bound.value,true; } } return 0,false; }
    if t.tag==EXPR_MAX_MINUS && t.args.count==1 { let value,known=static_nat(v,at(c,t.args,0),bindings,depth+1); return 0xffffffff-value,known; }
    if t.args.count!=2 || t.tag!=EXPR_ADD && t.tag!=EXPR_SUB && t.tag!=EXPR_MUL { return 0,false; }
    let a,ak=static_nat(v,at(c,t.args,0),bindings,depth+1); let b,bk=static_nat(v,at(c,t.args,1),bindings,depth+1); if !ak || !bk { return 0,false; }
    if t.tag==EXPR_SUB { return a-b,a>=b; }
    let value=if t.tag==EXPR_ADD { (a as u64)+b } else { (a as u64)*b }; return value as! u32,value<=MAX_U32;
}
fn static_domain(v:Context,domain:u32,object:u32,addend:u32,count:u32,bindings:StaticWitness[>..<]&)->bool {
    var index=bindings.len;
    while index>0 { if !visit(v,1) { return false from static_domain; } index--; let bound=bindings[index];
        if bound.kind!=KIND_DOMAIN || bound.binder!=domain { continue; }
        if bound.established { return bound.object==object && bound.addend==addend && bound.count==count; }
        bindings[index].object=object; bindings[index].addend=addend; bindings[index].count=count; bindings[index].established=true; return true;
    }
    if object==0 { return domain!=0; }
    let array=v.c.static_objects[object]; return array.domain==domain && addend==0 && count==array.count;
}
recursive fn static_value(v: Context, object: StaticObject, type_id:u32, offset:u32, geometry:const Geometry[:], used:u32[>..]&, bindings:StaticWitness[>..<]&, depth:u32) -> bool {
    if !visit(v,1) || depth > LIMIT_NEST { return false; }
    let c=v.c; let t=c.types[terminal(v,type_id)]; let size=geometry[type_id].size;
    if offset > object.bytes.count || size > object.bytes.count-offset || !geometry[type_id].share { return false; }
    if t.tag==TY_UNIT { return true; }
    if t.tag==TY_U32 || t.tag==TY_F32 { return true; }
    if t.tag==TY_BOOL { return static_word(c,object.bytes,offset) <= 1; }
    if t.tag==TY_INDEX {
        let extent, known=static_nat(v,t.nat,bindings,0); return known && static_word(c,object.bytes,offset) < extent;
    }
    if t.tag==TY_EXISTS {
        let mark=bindings.len; var next=offset;
        for i in t.binders.count { if !visit(v,1) { return false from static_value; } let id=at(c,t.binders,i); let binder=c.binders[id]; var row=StaticWitness{binder:id,kind:binder.kind,..};
            if binder.kind==KIND_NAT { row.value=static_word(c,object.bytes,next); next+=4; }
            else if binder.kind!=KIND_DOMAIN { return false; }
            bindings.push(row);
        }
        let valid=static_value(v,object,type_child(c,t,0),next,geometry,used,bindings,depth+1); bindings.resize(mark); return valid;
    }
    if t.tag==TY_TUPLE || t.tag==TY_RECORD {
        var next=offset;
        for i in type_count(t) { if !visit(v,1) { return false from static_value; } let child=type_child(c,t,i); if !static_value(v,object,child,next,geometry,used,bindings,depth+1) { return false; } next+=geometry[child].size; }
        return true;
    }
    if t.tag==TY_SUM || t.tag==TY_RESULT {
        let variant=static_word(c,object.bytes,offset); if variant >= type_count(t) { return false; }
        let child=type_child(c,t,variant); if !static_value(v,object,child,offset+4,geometry,used,bindings,depth+1) { return false; }
        var padding=offset+4+geometry[child].size;
        while padding < offset+size { if !visit(v,1) || c.bytes[object.bytes.start+padding] != 0 { return false; } padding++; }
        return true;
    }
    if t.tag==TY_VIEW {
        let count, known=static_nat(v,t.nat,bindings,0);
        if !known || t.region != 0 || static_word(c,object.bytes,offset) != 0 || static_word(c,object.bytes,offset+4) != count { return false; }
        let relocation=static_relocation(v,object,offset,used);
        if count==0 || geometry[type_child(c,t,0)].size==0 { return relocation==0 && static_domain(v,t.domain,0,0,count,bindings); }
        if relocation==0 { return false; } let r=c.static_relocations[relocation];
        if r.kind != STATIC_ADDRESS { return false; }
        let array=c.static_objects[r.target]; let stride=geometry[type_child(c,t,0)].size;
        if array.kind!=STATIC_ARRAY || stride==0 || r.addend%stride!=0 || r.addend>array.bytes.count || (count as u64)*stride>array.bytes.count-r.addend { return false; }
        return static_domain(v,t.domain,r.target,r.addend,count,bindings) && same_type(v,array.element_type,type_child(c,t,0),0);
    }
    if t.tag==TY_FN {
        if t.region != 0 || t.mode != MODE_MANY || static_word(c,object.bytes,offset) != 0 || static_word(c,object.bytes,offset+4) != 0 { return false; }
        let relocation=static_relocation(v,object,offset,used); if relocation==0 { return false; }
        let r=c.static_relocations[relocation];
        if r.kind==STATIC_FUNCTION {
            if r.addend!=0 { return false; } let function=c.functions[r.target];
            return !function.evaluator_only && function.captures.count==0 && function.environment_bindings.count==0 && c.contracts[function.contract].binders.count==0 && weaken_callable(v,function.type_id,type_id);
        }
        if r.kind!=STATIC_CLOSURE { return false; } let op=c.ops[r.target];
        if op.tag!=OP_CLOSURE || op.results.count!=1 || !id_ok(op.imm0,c.functions.len) { return false; }
        let source=c.types[terminal(v,c.values[at(c,op.results,0)].type_id)];
        if source.tag!=TY_FN || !same_type(v,type_child(c,source,0),type_child(c,t,0),0) || !same_type(v,type_child(c,source,1),type_child(c,t,1),0) || !weaken_contract(v,source.contract,t.contract) { return false; }
        let envreloc=static_relocation(v,object,offset+4,used);
        if r.addend==0 { return envreloc==0 && c.functions[op.imm0].captures.count==0 && c.functions[op.imm0].environment_bindings.count==0; }
        let env=c.static_objects[r.addend];
        if env.kind!=STATIC_ENVIRONMENT || env.function!=op.imm0 || env.constructor!=r.target { return false; }
        if env.bytes.count==0 { return envreloc==0; }
        if envreloc==0 { return false; } let envref=c.static_relocations[envreloc];
        return envref.kind==STATIC_ADDRESS && envref.target==r.addend && envref.addend==0;
    }
    return false;
}
fn static_object(v: Context, id:u32, geometry:const Geometry[:]) -> bool {
    let c=v.c; let object=c.static_objects[id];
    var bindings:StaticWitness[>..<]=[];
    var used:u32[>..]=[]; for row in c.static_relocations { used.push(0); }
    for i in object.relocations.count { if !visit(v,1) { return false from static_object; }
        let relocation=c.static_relocations[at(c,object.relocations,i)];
        if relocation.offset % 4 != 0 || relocation.offset > object.bytes.count || 4 > object.bytes.count-relocation.offset { return reject(v,2034,id); }
    }
    if object.kind!=STATIC_ENVIRONMENT && (object.function!=0 || object.constructor!=0) { return reject(v,2034,id); }
    if object.kind==STATIC_ENVIRONMENT {
        if !static_environment(v,object,geometry,used,bindings) { return reject(v,2034,id); }
    } else if object.kind==STATIC_ARRAY {
        let view=c.types[terminal(v,object.type_id)]; let length, known=literal_term(v,view.nat,0);
        if view.tag != TY_VIEW || view.region != 0 || object.element_type==0 || !geometry[object.element_type].plain || view.domain != object.domain || !known || length != object.count ||
            !same_type(v,type_child(c,view,0),object.element_type,0) || (object.count as u64)*geometry[object.element_type].size != object.bytes.count { return reject(v,2034,id); }
        let stride=geometry[object.element_type].size;
        if stride==0 { if !static_value(v,object,object.element_type,0,geometry,used,bindings,0) { return reject(v,2034,id); } }
        else { for i in object.count { if !visit(v,1) { return false from static_object; } if !static_value(v,object,object.element_type,i*stride,geometry,used,bindings,0) { return reject(v,2034,id); } } }
    } else if object.kind==STATIC_VALUE {
        if object.element_type != 0 || object.count != 1 || object.domain != 0 || object.bytes.count != geometry[object.type_id].size || !static_value(v,object,object.type_id,0,geometry,used,bindings,0) { return reject(v,2034,id); }
    } else { return reject(v,2034,id); }
    for i in object.relocations.count { if !visit(v,1) { return false from static_object; } if used[at(c,object.relocations,i)] != 1 { return reject(v,2034,id); } }
    return true;
}
fn validate_adapter(v: Context,id:u32,geometry:const Geometry[:]) -> bool {
    let c=v.c; let adapter=c.callable_adapters[id]; let op=c.ops[adapter.op];
    if op.tag != OP_CLOSURE && op.tag != OP_FN_PLACE || op.imm0 != adapter.target_function || op.results.count != 1 { return reject(v,2034,id); }
    let result=c.types[terminal(v,c.values[at(c,op.results,0)].type_id)];
    if result.tag != TY_FN || result.contract != adapter.callback_contract { return reject(v,2003,id); }
    let environment=c.layouts[adapter.environment_layout]; let shape=c.types[terminal(v,environment.type_id)];
    var target_environment:u32=0;
    for plan,pi in c.abi_plans { if !visit(v,1) { return false from validate_adapter; } if pi!=0 && plan.function==adapter.target_function && plan.env_layout!=0 { target_environment=c.layouts[plan.env_layout].type_id; } }
    if target_environment==0 || adapter.target_environment_offset!=adapter.captures.count*4 { return reject(v,2024,id); }
    let tail=if geometry[target_environment].size!=0 {1} else {0};
    if (shape.tag!=TY_TUPLE && shape.tag!=TY_RECORD) || type_count(shape)!=adapter.captures.count+tail { return reject(v,2024,id); }
    if tail!=0 && !same_type(v,type_child(c,shape,adapter.captures.count),target_environment,0) { return reject(v,2024,id); }
    for i in adapter.captures.count { if !visit(v,1) { return false from validate_adapter; }
        let capture=c.adapter_captures[at(c,adapter.captures,i)];
        if capture.offset != i*4 || c.types[terminal(v,type_child(c,shape,i))].tag != TY_U32 { return reject(v,2024,id); }
        var found=false;
        for j in op.substitutions.count { if !visit(v,1) { return false from validate_adapter; } let sub=c.substitutions[at(c,op.substitutions,j)]; if sub.kind==capture.kind && sub.value==capture.source { found=true; } }
        if !found { return reject(v,2004,id); }
        for j in i { if !visit(v,1) { return false from validate_adapter; } let prior=c.adapter_captures[at(c,adapter.captures,j)]; if prior.kind==capture.kind && prior.source==capture.source { return reject(v,2034,id); } }
    }
    if adapter.captures.count != 0 {
        if result.region==0 && !c.functions[c.blocks[c.values[at(c,op.results,0)].block_id].function].evaluator_only { return reject(v,2016,id); }
        if result.region!=0 && op.tag==OP_CLOSURE && c.binders[result.region].scope != op.scope { return reject(v,2016,id); }
        if op.tag==OP_FN_PLACE {
            let dest=c.types[terminal(v,c.values[at(c,op.args,0)].type_id)]; let capacity, known=literal_term(v,dest.capacity,0);
            if !known || capacity < geometry[environment.type_id].size { return reject(v,2025,id); }
        }
    }
    for other,index in c.callable_adapters { if !visit(v,1) { return false from validate_adapter; } if index != 0 && index != id && other.op==adapter.op { return reject(v,2034,id); } }
    return true;
}

recursive fn closed_dictionary_type(v:Context,type_id:u32,depth:u32) -> bool {
    if !visit(v,1) || depth > LIMIT_NEST { return false; }
    let t=v.c.types[type_id]; if t.tag==TY_PARAM || t.tag==TY_FORALL { return false; }
    for i in type_count(t) { if !visit(v,1) { return false from closed_dictionary_type; } if !closed_dictionary_type(v,type_child(v.c,t,i),depth+1) { return false; } }
    return true;
}
recursive fn dictionary_type(v:Context,generic:u32,concrete:u32,parameters:Span,arguments:Span,depth:u32) -> bool {
    if !visit(v,1) || depth > LIMIT_NEST { return false; }
    let c=v.c; let a=c.types[terminal(v,generic)]; let b=c.types[terminal(v,concrete)];
    if a.tag==TY_PARAM {
        for i in parameters.count { if !visit(v,1) { return false from dictionary_type; } if at(c,parameters,i)==a.binder { return same_type(v,at(c,arguments,i),concrete,0); } }
        return false;
    }
    if !field_labels(v,a,b) { return false; }
    if a.tag!=b.tag || a.mode!=b.mode || a.region!=b.region || a.nat!=b.nat || a.domain!=b.domain || a.capacity!=b.capacity || a.binder!=b.binder || type_count(a)!=type_count(b) || a.binders.count!=b.binders.count { return false; }
    for i in a.binders.count { if !visit(v,1) { return false from dictionary_type; } if at(c,a.binders,i)!=at(c,b.binders,i) { return false; } }
    for i in type_count(a) { if !visit(v,1) { return false from dictionary_type; } if !dictionary_type(v,type_child(c,a,i),type_child(c,b,i),parameters,arguments,depth+1) { return false; } }
    if a.tag==TY_FN && !instantiated_callable_contract(v,a.contract,b.contract,Span{..}) { return false; }
    return true;
}
fn validate_dictionary(v:Context,id:u32,geometry:const Geometry[:]) -> bool {
    let c=v.c; let row=c.dictionary_realizations[id];
    if !closed_dictionary_type(v,row.concrete_type,0) || !dictionary_type(v,row.type_id,row.concrete_type,row.parameters,row.arguments,0) || !same_type(v,c.layouts[row.layout].type_id,row.concrete_type,0) { return reject(v,2024,id); }
    for i in row.parameters.count { if !visit(v,1) { return false from validate_dictionary; }
        let binder=c.binders[at(c,row.parameters,i)]; let argument=at(c,row.arguments,i);
        if binder.kind!=KIND_TYPE || !closed_dictionary_type(v,argument,0) || binder.constraints & CONSTRAINT_PLAIN != 0 && !geometry[argument].plain || binder.constraints & CONSTRAINT_SHARE != 0 && !geometry[argument].share { return reject(v,2004,id); }
        for j in i { if !visit(v,1) { return false from validate_dictionary; } if at(c,row.parameters,i)==at(c,row.parameters,j) { return reject(v,2034,id); } }
    }
    for prior,index in c.dictionary_realizations { if !visit(v,1) { return false from validate_dictionary; }
        if index==0 || index>=id || prior.type_id!=row.type_id || prior.arguments.count!=row.arguments.count || prior.parameters.count!=row.parameters.count { continue; }
        var same=true;
        for i in row.arguments.count { if !visit(v,1) { return false from validate_dictionary; } if at(c,prior.parameters,i)!=at(c,row.parameters,i) || !same_type(v,at(c,prior.arguments,i),at(c,row.arguments,i),0) { same=false; } }
        if same { return reject(v,2034,id); }
    }
    return true;
}

// Alias parameters describe uninstantiated layout templates. Concrete uses must
// substitute them before acquiring a value/dictionary representation.
recursive fn template_type(v:Context,type_id:u32,depth:u32) -> bool {
    if !visit(v,1) { return false; }
    let c=v.c;
    if depth > LIMIT_NEST || !id_ok(type_id,c.types.len) { return false; }
    let t=c.types[type_id];
    if t.tag==TY_PARAM {
        for definition,index in c.definitions { if !visit(v,1) { return false; }
            if index != 0 && definition.kind==DEF_TYPE && contains(v,definition.binders,t.binder) { return true; }
        }
    }
    for i in type_count(t) { if !visit(v,1) { return false; } if template_type(v,type_child(c,t,i),depth+1) { return true; } }
    return false;
}

fn validation_input_limit(c:Core) -> u64 {
    let rows=(c.types.len+c.values.len+c.ops.len+c.blocks.len+c.edges.len+c.terms.len+c.facts.len+c.evidence.len+c.scopes.len+c.binders.len+c.contracts.len+c.functions.len+c.definitions.len+c.layouts.len+c.static_objects.len+c.dictionary_realizations.len) as u64;
    return LIMIT_VISITS + (rows+c.refs.len as u64)*256 + c.bytes.len as u64;
}
struct InventoryMarks { types:u32[>..]&, terms:u32[>..]&, facts:u32[>..]&, evidence:u32[>..]&, contracts:u32[>..]& }
struct InventoryItem { kind:u32, id:u32 }
struct InventoryCounts { types:u32, terms:u32, edges:u32, operations:u32, blocks:u32 }
fn declaration_inventory(v:Context,function_id:u32,owner:u32,counts:InventoryCounts&,marks:InventoryMarks,head:u32,next:const u32[:],root_type:u32=0) -> bool {
    let c=v.c; let function=c.functions[function_id]; var queue:InventoryItem[>..]=[];
    counts.blocks+=function.blocks.count;
    if counts.blocks>LIMIT_BLOCKS { v.work.exhausted=true; return reject(v,2031,owner); }
    fn add(kind:u32,id:u32) {
        if !visit(v,1) { return false from declaration_inventory; } if id==0 { return; }
        if kind==1 { if marks.types[id]==owner { return; } marks.types[id]=owner; counts.types++; if counts.types>LIMIT_TYPES { v.work.exhausted=true; return reject(v,2031,function_id) from declaration_inventory; } }
        if kind==2 { if marks.terms[id]==owner { return; } marks.terms[id]=owner; counts.terms++; if counts.terms>LIMIT_TERMS { v.work.exhausted=true; return reject(v,2032,function_id) from declaration_inventory; } }
        if kind==3 { if marks.facts[id]==owner { return; } marks.facts[id]=owner; counts.edges++; }
        if kind==4 { if marks.evidence[id]==owner { return; } marks.evidence[id]=owner; counts.edges++; }
        if kind==5 { if marks.contracts[id]==owner { return; } marks.contracts[id]=owner; }
        if counts.edges>LIMIT_FACT_EDGES { v.work.exhausted=true; return reject(v,2032,function_id) from declaration_inventory; }
        queue.push(InventoryItem{kind,id});
    }
    fn span(kind:u32,values:Span) { for i in values.count { if !visit(v,1) { return false from declaration_inventory; } add(kind,at(c,values,i)); } }
    fn value(id:u32) { if id!=0 { add(1,c.values[id].type_id); } }
    add(1,root_type); add(1,function.type_id); add(5,function.contract);
    var proof=head; while proof!=0 { if !visit(v,1) { return false from declaration_inventory; } add(4,proof); proof=next[proof]; }
    for i in function.blocks.count { if !visit(v,1) { return false from declaration_inventory; }
        let basic=c.blocks[at(c,function.blocks,i)]; span(4,basic.evidence_params);
        counts.operations+=basic.ops.count+1; if counts.operations>LIMIT_OPS { v.work.exhausted=true; return reject(v,2031,owner); }
        for j in basic.params.count { if !visit(v,1) { return false from declaration_inventory; } value(at(c,basic.params,j)); }
        for j in basic.ops.count { if !visit(v,1) { return false from declaration_inventory; }
            let op=c.ops[at(c,basic.ops,j)]; span(4,op.evidence);
            for k in op.args.count { if !visit(v,1) { return false from declaration_inventory; } value(at(c,op.args,k)); } for k in op.results.count { if !visit(v,1) { return false from declaration_inventory; } value(at(c,op.results,k)); }
            for k in op.substitutions.count { if !visit(v,1) { return false from declaration_inventory; } let sub=c.substitutions[at(c,op.substitutions,k)]; if sub.kind==KIND_TYPE {add(1,sub.value);} if sub.kind==KIND_NAT {add(2,sub.value);} }
            if op.tag==OP_TRY_ALLOC || op.tag==OP_LAYOUT_SIZE || op.tag==OP_LAYOUT_ALIGN { add(1,op.imm0); }
        }
        let term=c.terminators[basic.term]; value(term.subject); span(4,term.evidence);
        for j in term.edges.count { if !visit(v,1) { return false from declaration_inventory; } let edge=c.edges[at(c,term.edges,j)]; span(4,edge.evidence); }
    }
    var cursor:i64=0;
    while cursor<queue.len {
        if !visit(v,1) { return false; } let item=queue[cursor]; cursor++;
        if item.kind==1 {
            let row=c.types[item.id]; for i in type_count(row) { if !visit(v,1) { return false from declaration_inventory; } add(1,type_child(c,row,i)); }
            add(2,row.nat); add(2,row.capacity); add(5,row.contract);
        } else if item.kind==2 {
            let row=c.terms[item.id]; add(1,row.type_id); span(2,row.args); value(row.value);
        } else if item.kind==3 {
            let row=c.facts[item.id]; add(2,row.left); add(2,row.right); add(2,row.third);
        } else if item.kind==4 {
            let row=c.evidence[item.id]; add(3,row.fact); add(3,row.formal_fact); span(4,row.premises);
            for i in row.operands.count { if !visit(v,1) { return false from declaration_inventory; } value(at(c,row.operands,i)); }
        } else {
            let row=c.contracts[item.id]; for i in row.layout_premises.count { if !visit(v,1) { return false from declaration_inventory; } add(1,c.layout_premises[at(c,row.layout_premises,i)].type_id); } add(1,row.arg); add(1,row.result); span(3,row.requires); span(3,row.ensures); span(3,row.on_true); span(3,row.on_false);
        }
    }
    return true;
}

recursive fn captured_term(v:Context,source:u32,target:u32,captures:Span,depth:u32) -> bool {
    if !proof_visit(v,1) || depth>LIMIT_NEST { return false; }
    let c=v.c; let a=c.terms[source]; let b=c.terms[target];
    if a.tag==EXPR_LITERAL && b.tag==EXPR_VALUE && b.value!=0 {
        for i in captures.count { if !proof_visit(v,1) { return false from captured_term; } let capture=c.captures[at(c,captures,i)];
            if capture.local_value==b.value && b.version==c.values[b.value].version && value_term(v,source,capture.value) { return true; }
        }
        return false;
    }
    if a.tag!=b.tag || a.literal!=b.literal || a.binder!=b.binder || a.args.count!=b.args.count { return false; }
    if a.value!=0 {
        var found=false;
        for i in captures.count { if !proof_visit(v,1) { return false from captured_term; } let capture=c.captures[at(c,captures,i)]; if capture.value==a.value && capture.local_value==b.value && a.version==c.values[a.value].version && b.version==c.values[b.value].version { found=true; } }
        if !found { return false; }
    } else if b.value!=0 { return false; }
    for i in a.args.count { if !proof_visit(v,1) { return false from captured_term; } if !captured_term(v,at(c,a.args,i),at(c,b.args,i),captures,depth+1) { return false; } }
    return true;
}
fn capture_fact(v:Context,e:Evidence,f:Fact) -> bool {
    let c=v.c;
    if !id_ok(e.call,c.ops.len) || e.premises.count!=1 || e.edge!=0 { return false; }
    let constructor=c.ops[e.call];
    if constructor.tag!=OP_CLOSURE && constructor.tag!=OP_FN_PLACE && constructor.tag!=OP_GENERIC_BIND || !id_ok(constructor.imm0,c.functions.len) { return false; }
    let function=c.functions[constructor.imm0]; let captures=function.captures;
    if e.contract!=function.contract || e.scope!=c.blocks[function.entry].scope || e.operands.count!=captures.count*2 { return false; }
    for i in captures.count { if !visit(v,1) { return false from capture_fact; } let capture=c.captures[at(c,captures,i)]; if at(c,e.operands,i)!=capture.value || at(c,e.operands,i+captures.count)!=capture.local_value { return false; } }
    let premise=at(c,e.premises,0); let old=c.facts[c.evidence[premise].fact];
    if old.tag!=f.tag || old.domain!=f.domain || old.version!=f.version || !captured_term(v,old.left,f.left,captures,0) || !captured_term(v,old.right,f.right,captures,0) { return false; }
    if old.third!=0 && f.third!=0 { if !captured_term(v,old.third,f.third,captures,0) { return false; } }
    else if old.third!=f.third { return false; }
    let block_id=operation_block(v,e.call); if block_id==0 { return false; } let basic=c.blocks[block_id];
    for i in basic.ops.count { if !visit(v,1) { return false from capture_fact; } if at(c,basic.ops,i)==e.call { return evidence_usable(v,premise,block_id,i,0); } }
    return false;
}

fn declaration_owners(v:Context,owners:u32[>..]&) -> bool {
    let c=v.c; var producers:u32[>..]=[]; for row in c.definitions { producers.push(0); }
    var parents:u32[>..]=[];
    for function,id in c.functions { if !visit(v,1) { return false from declaration_owners; }
        var owner=id as u32;
        if id!=0 && function.producer!=0 {
            if producers[function.producer]==0 { producers[function.producer]=id as u32; }
            owner=producers[function.producer];
        }
        parents.push(owner); owners.push(0);
    }
    var bound:bool[>..]=[]; for function in c.functions { bound.push(false); }
    for op,id in c.ops { if !visit(v,1) { return false from declaration_owners; } if id!=0 && op.tag==OP_GENERIC_BIND {
        if !id_ok(op.imm0,c.functions.len) || bound[op.imm0] { return reject(v,2034,id as u32); }
        let owner=operation_block(v,id as u32); if owner==0 { return reject(v,2034,id as u32); }
        parents[op.imm0]=c.blocks[owner].function; bound[op.imm0]=true;
    } }
    for op,id in c.ops {
        if !visit(v,1) { return false; }
        if id==0 || op.tag!=OP_CLOSURE && op.tag!=OP_FN_PLACE { continue; }
        if !id_ok(op.imm0,c.functions.len) { return reject(v,2034,id as u32); }
        if c.functions[op.imm0].producer!=0 || bound[op.imm0] { continue; }
        let parent=c.blocks[c.values[at(c,op.results,0)].block_id].function;
        if parent==op.imm0 || parents[op.imm0]!=op.imm0 && parents[op.imm0]!=parent { return reject(v,2034,id as u32); }
        parents[op.imm0]=parent;
    }
    for function,id in c.functions { if !visit(v,1) { return false from declaration_owners; }
        if id==0 { continue; } var owner=id as u32; var finished=false;
        for depth in LIMIT_NEST+1 {
            if !visit(v,1) { return false; }
            if parents[owner]==owner { finished=true; break; }
            owner=parents[owner];
        }
        if !finished { return reject(v,2034,id as u32); } owners[id]=owner;
    }
    return true;
}

fn field_labels(v:Context,a:TypeNode,b:TypeNode) -> bool {
    if a.tag!=TY_RECORD && a.tag!=TY_SUM && a.tag!=TY_RESULT { return true; }
    if a.fields.count!=b.fields.count { return false; }
    for i in a.fields.count {
        if !visit(v,1) { return false; }
        let x=v.c.fields[at(v.c,a.fields,i)]; let y=v.c.fields[at(v.c,b.fields,i)];
        if name_bytes(v.c,x.name)!=name_bytes(v.c,y.name) || x.tag!=y.tag { return false; }
    }
    return true;
}

fn interface_binder(v:Context,binder:u32,bound:const u32[:]) -> bool {
    if !visit(v,1) { return false; }
    let c=v.c;
    if binder==0 { return true; }
    for known in bound { if !visit(v,1) { return false; } if known==binder { return true; } }
    // A module's immutable array has a stable abstract module-instance Domain.
    if c.binders[binder].kind==KIND_DOMAIN && c.binders[binder].introduction_kind==INTRO_NONE && c.binders[binder].scope==0 {
        for object,id in c.static_objects { if !visit(v,1) { return false; } if id!=0 && object.kind==STATIC_ARRAY && object.domain==binder { return true; } }
    }
    return false;
}
recursive fn closed_interface_term(v:Context,id:u32,bound:const u32[:],contract:u32,depth:u32) -> bool {
    if id==0 { return true; } if !proof_visit(v,1) || depth>LIMIT_NEST { return false; }
    let c=v.c; let term=c.terms[id];
    if term.value!=0 { return false; }
    if term.tag==EXPR_BINDER && !interface_binder(v,term.binder,bound) { return false; }
    if (term.tag==EXPR_ARG || term.tag==EXPR_RESULT) && (contract==0 || term.binder!=contract) { return false; }
    for i in term.args.count { if !proof_visit(v,1) { return false from closed_interface_term; } if !closed_interface_term(v,at(c,term.args,i),bound,contract,depth+1) { return false; } }
    return true;
}
recursive fn closed_interface(v:Context,type_id:u32,bound:u32[>..<]&,depth:u32) -> bool {
    if !visit(v,1) || depth>LIMIT_NEST { return false; }
    let c=v.c; let t=c.types[type_id]; let mark=bound.len;
    for i in t.binders.count { if !visit(v,1) { return false from closed_interface; } bound.push(at(c,t.binders,i)); }
    if !interface_binder(v,t.region,bound) || !interface_binder(v,t.domain,bound) || !interface_binder(v,t.binder,bound) ||
        !closed_interface_term(v,t.nat,bound,0,0) || !closed_interface_term(v,t.capacity,bound,0,0) { return false; }
    for i in type_count(t) { if !visit(v,1) { return false from closed_interface; } if !closed_interface(v,type_child(c,t,i),bound,depth+1) { return false; } }
    if t.contract!=0 {
        let contract=c.contracts[t.contract];
        for i in contract.binders.count { if !visit(v,1) { return false from closed_interface; } bound.push(at(c,contract.binders,i)); }
        for clause in [contract.requires,contract.ensures,contract.on_true,contract.on_false] { if !visit(v,1) { return false from closed_interface; }
            for i in clause.count { if !visit(v,1) { return false from closed_interface; }
                let fact=c.facts[at(c,clause,i)];
                if !interface_binder(v,fact.domain,bound) || !closed_interface_term(v,fact.left,bound,t.contract,0) || !closed_interface_term(v,fact.right,bound,t.contract,0) || !closed_interface_term(v,fact.third,bound,t.contract,0) { return false; }
            }
        }
        for i in contract.effects.count { if !visit(v,1) { return false from closed_interface; } if !interface_binder(v,c.effects[at(c,contract.effects,i)].region,bound) { return false; } }
    }
    bound.resize(mark); return true;
}

fn layout_required(v:Context,contract:Contract,ty:u32,kind:u32,geometry:const Geometry[:])->bool {
    if !visit(v,1) { return false; }
    if kind==LAYOUT_PLAIN && !geometry[ty].plain { return reject(v,2024,ty); }
    if !geometry[ty].dependent { return true; }
    if !layout_premise_has(v.c,contract.layout_premises,ty,kind,Span{..},v.work,v.visit_limit) { return reject(v,if v.work.exhausted {2030} else {2024},ty); }
    return true;
}
recursive fn layout_required_type(v:Context,contract:Contract,ty:u32,geometry:const Geometry[:],depth:u32)->bool {
    if !visit(v,1) || depth>LIMIT_NEST { return false; } let c=v.c; let t=c.types[ty];
    if (t.tag==TY_TUPLE || t.tag==TY_RECORD || t.tag==TY_SUM || t.tag==TY_RESULT || t.tag==TY_EXISTS) && !layout_required(v,contract,ty,LAYOUT_AGGREGATE,geometry) { return false; }
    if (t.tag==TY_VIEW || t.tag==TY_DEST || t.tag==TY_BUILDER) && !layout_required(v,contract,type_child(c,t,0),LAYOUT_PLAIN,geometry) { return false; }
    for i in type_count(t) { if !visit(v,1) { return false from layout_required_type; } if !layout_required_type(v,contract,type_child(c,t,i),geometry,depth+1) { return false; } }
    return true;
}
struct BoundGeometry { size:u32, nodes:u32, leaves:u32, guards:u32, plain:bool, dependent:bool }
recursive fn instantiated_layout(v:Context,ty:u32,subs:Span,depth:u32)->BoundGeometry,bool {
    if !visit(v,1) || depth>LIMIT_NEST { return BoundGeometry{..},false; } let c=v.c; let t=c.types[ty];
    if t.tag==TY_ALIAS || t.tag==TY_FORALL { return instantiated_layout(v,type_child(c,t,0),subs,depth+1); }
    if t.tag==TY_PARAM {
        let actual,found=substitution(v,subs,t.binder);
        if found { return instantiated_layout(v,actual,Span{..},depth+1); }
        return BoundGeometry{size:0,nodes:1,plain:c.binders[t.binder].constraints & CONSTRAINT_PLAIN!=0,dependent:true,..},true;
    }
    var g=BoundGeometry{nodes:1,plain:true,..};
    if t.tag==TY_UNIT { return g,true; }
    if t.tag==TY_U32 || t.tag==TY_F32 || t.tag==TY_BOOL || t.tag==TY_INDEX { g.size=4; g.leaves=1; if t.tag==TY_BOOL || t.tag==TY_INDEX { g.guards=1; } return g,true; }
    if t.tag==TY_TUPLE || t.tag==TY_RECORD || t.tag==TY_SUM || t.tag==TY_RESULT || t.tag==TY_EXISTS {
        for i in type_count(t) { if !visit(v,1) { return BoundGeometry{..},false from instantiated_layout; }
            let child,ok=instantiated_layout(v,type_child(c,t,i),subs,depth+1); if !ok { return g,false; }
            g.nodes+=child.nodes; g.leaves+=child.leaves; g.guards+=child.guards; g.plain=g.plain && child.plain; g.dependent=g.dependent || child.dependent;
            if t.tag==TY_SUM || t.tag==TY_RESULT { g.size=max(g.size,child.size); } else { g.size+=child.size; }
        }
        if t.tag==TY_SUM || t.tag==TY_RESULT { g.size+=4; g.guards++; }
        if t.tag==TY_RESULT { g.plain=false; }
        if t.tag==TY_EXISTS { for i in t.binders.count { if !visit(v,1) { return BoundGeometry{..},false from instantiated_layout; } if c.binders[at(c,t.binders,i)].kind==KIND_NAT { g.size+=4; g.nodes++; g.leaves++; } } }
        return g,g.size<=256;
    }
    g.plain=false; g.size=8; if t.tag==TY_BUILDER { g.size=12; }
    return g,true;
}
fn validate_layout_premises(v:Context,function_id:u32,geometry:const Geometry[:])->bool {
    let c=v.c; let f=c.functions[function_id]; let ct=c.contracts[f.contract];
    if !layout_required_type(v,ct,ct.arg,geometry,0) || !layout_required_type(v,ct,ct.result,geometry,0) { return false; }
    let index=v.indexes;
    if index {
        var pi=index.plan_heads[function_id];
        while pi!=0 {
            if !visit(v,1) { return false; } let plan=c.abi_plans[pi];
            if plan.env_layout!=0 && !layout_required_type(v,ct,c.layouts[plan.env_layout].type_id,geometry,0) { return false; }
            pi=index.plan_next[pi];
        }
    } else {
        for plan,pi in c.abi_plans { if !visit(v,1) { return false from validate_layout_premises; } if pi!=0 && plan.function==function_id && plan.env_layout!=0 && !layout_required_type(v,ct,c.layouts[plan.env_layout].type_id,geometry,0) { return false; } }
    }
    for bi in f.blocks.count { if !visit(v,1) { return false from validate_layout_premises; } let basic=c.blocks[at(c,f.blocks,bi)];
        for pi in basic.params.count { if !visit(v,1) { return false from validate_layout_premises; } if !layout_required_type(v,ct,c.values[at(c,basic.params,pi)].type_id,geometry,0) { return false; } }
        for oi in basic.ops.count { if !visit(v,1) { return false from validate_layout_premises; } let op=c.ops[at(c,basic.ops,oi)];
            for ri in op.results.count { if !visit(v,1) { return false from validate_layout_premises; } if !layout_required_type(v,ct,c.values[at(c,op.results,ri)].type_id,geometry,0) { return false; } }
            if index {
                var ai=index.adapter_heads[at(c,basic.ops,oi)];
                while ai!=0 {
                    if !visit(v,1) { return false; } let adapter=c.callable_adapters[ai];
                    if !layout_required_type(v,ct,c.layouts[adapter.environment_layout].type_id,geometry,0) { return false; }
                    ai=index.adapter_next[ai];
                }
            } else {
                for adapter,ai in c.callable_adapters { if !visit(v,1) { return false from validate_layout_premises; } if ai!=0 && adapter.op==at(c,basic.ops,oi) && !layout_required_type(v,ct,c.layouts[adapter.environment_layout].type_id,geometry,0) { return false; } }
            }
            if op.tag==OP_TRY_ALLOC && !layout_required(v,ct,op.imm0,LAYOUT_PLAIN,geometry) { return false; }
            for si in op.substitutions.count { if !visit(v,1) { return false from validate_layout_premises; } let sub=c.substitutions[at(c,op.substitutions,si)]; if sub.kind==KIND_TYPE && c.binders[sub.binder].constraints & CONSTRAINT_PLAIN!=0 && !layout_required(v,ct,sub.value,LAYOUT_PLAIN,geometry) { return false; } }
            if op.tag!=OP_CALL && op.tag!=OP_CLOSURE && op.tag!=OP_FN_PLACE { continue; }
            let requirements=c.contracts[c.functions[op.imm0].contract].layout_premises;
            for pi in requirements.count { if !visit(v,1) { return false from validate_layout_premises; } let premise=c.layout_premises[at(c,requirements,pi)];
                let exact,ok=instantiated_layout(v,premise.type_id,op.substitutions,0);
                if !ok || premise.kind==LAYOUT_PLAIN && (!exact.plain || exact.size>64 || exact.nodes>32 || exact.leaves>64 || exact.guards>32) { return reject(v,2024,at(c,basic.ops,oi)); }
                if exact.dependent && !layout_premise_has(c,ct.layout_premises,premise.type_id,premise.kind,op.substitutions,v.work,v.visit_limit) { return reject(v,if v.work.exhausted {2030} else {2024},at(c,basic.ops,oi)); }
            }
        }
    }
    return true;
}

fn static_binding(v:Context,bindings:const StaticWitness[:],binder:u32,kind:u32)->u32,bool {
    if !visit(v,1) { return 0, false; }
    var i=bindings.len; while i>0 { if !visit(v,1) { return 0, false; } i--; let row=bindings[i]; if row.binder==binder && row.kind==kind { return row.value,true; } } return 0,false;
}
recursive fn static_type_match(v:Context,generic:u32,actual:u32,bindings:const StaticWitness[:],depth:u32)->bool {
    if !visit(v,1) || depth>LIMIT_NEST { return false; } let c=v.c; let a=c.types[terminal(v,generic)]; let b=c.types[terminal(v,actual)];
    if a.tag==TY_PARAM { let ty,known=static_binding(v,bindings,a.binder,KIND_TYPE); return known && same_type(v,ty,actual,0); }
    if a.tag!=b.tag || a.mode!=b.mode || a.region!=b.region && !(a.tag==TY_FN && b.region==0) || a.domain!=b.domain || type_count(a)!=type_count(b) || !field_labels(v,a,b) { return false; }
    if a.nat!=b.nat { let av,ak=static_nat(v,a.nat,bindings,0); let bv,bk=static_nat(v,b.nat,bindings,0); if !ak || !bk || av!=bv { return false; } }
    if a.capacity!=b.capacity { let av,ak=static_nat(v,a.capacity,bindings,0); let bv,bk=static_nat(v,b.capacity,bindings,0); if !ak || !bk || av!=bv { return false; } }
    for i in type_count(a) { if !visit(v,1) { return false from static_type_match; } if !static_type_match(v,type_child(c,a,i),type_child(c,b,i),bindings,depth+1) { return false; } }
    if a.tag==TY_FN && !instantiated_callable_contract(v,a.contract,b.contract,Span{..}) { return false; }
    return true;
}
struct StaticLocation { type_id:u32, offset:u32 }
fn static_capture_location(v:Context,object:StaticObject,value:u32,geometry:const Geometry[:])->StaticLocation,bool {
    let c=v.c; let f=c.functions[object.function]; let shape=c.types[terminal(v,object.type_id)]; var prefix:u32=0;
    for adapter,ai in c.callable_adapters { if !visit(v,1) { return StaticLocation{..},false from static_capture_location; } if ai!=0 && adapter.op==object.constructor { prefix=adapter.captures.count; } }
    var offset=(prefix+f.environment_bindings.count)*4;
    for i in f.captures.count { if !visit(v,1) { return StaticLocation{..},false from static_capture_location; } let capture=c.captures[at(c,f.captures,i)]; let ty=type_child(c,shape,prefix+f.environment_bindings.count+i);
        if capture.local_value==value { return StaticLocation{ty,offset},true; } offset+=geometry[ty].size;
    } return StaticLocation{..},false;
}
recursive fn static_term_location(v:Context,object:StaticObject,id:u32,geometry:const Geometry[:],depth:u32)->StaticLocation,bool {
    if !visit(v,1) || depth>LIMIT_NEST { return StaticLocation{..},false; } let c=v.c; let term=c.terms[id];
    if term.tag==EXPR_VALUE { return static_capture_location(v,object,term.value,geometry); }
    if term.tag==EXPR_FIELD && term.args.count==1 {
        let base,known=static_term_location(v,object,at(c,term.args,0),geometry,depth+1); if !known { return base,false; }
        let t=c.types[terminal(v,base.type_id)]; if t.tag!=TY_TUPLE && t.tag!=TY_RECORD || term.literal>=type_count(t) { return base,false; }
        var offset=base.offset; for i in term.literal { if !visit(v,1) { return StaticLocation{..},false from static_term_location; } offset+=geometry[type_child(c,t,i)].size; }
        return StaticLocation{type_child(c,t,term.literal),offset},true;
    } return StaticLocation{..},false;
}
recursive fn static_capture_term(v:Context,object:StaticObject,id:u32,geometry:const Geometry[:],bindings:const StaticWitness[:],depth:u32)->u32,bool {
    if !visit(v,1) || depth>LIMIT_NEST { return 0,false; } let c=v.c; let term=c.terms[id];
    if term.tag==EXPR_LITERAL { return term.literal,true; }
    if term.tag==EXPR_BINDER { return static_binding(v,bindings,term.binder,KIND_NAT); }
    if term.tag==EXPR_VALUE || term.tag==EXPR_FIELD {
        let location,known=static_term_location(v,object,id,geometry,0); if !known { return 0,false; }
        let tag=c.types[terminal(v,location.type_id)].tag; if tag!=TY_U32 && tag!=TY_INDEX { return 0,false; }
        return static_word(c,object.bytes,location.offset),true;
    }
    if term.tag==EXPR_LEN {
        var location=StaticLocation{..}; var known=false;
        if term.value!=0 { location,known=static_capture_location(v,object,term.value,geometry); }
        else if term.args.count==1 { location,known=static_term_location(v,object,at(c,term.args,0),geometry,0); }
        if !known || c.types[terminal(v,location.type_id)].tag!=TY_VIEW { return 0,false; }
        return static_word(c,object.bytes,location.offset+4),true;
    }
    if term.tag==EXPR_MAX_MINUS && term.args.count==1 { let x,known=static_capture_term(v,object,at(c,term.args,0),geometry,bindings,depth+1); return 0xffffffff-x,known; }
    if term.args.count!=2 || term.tag!=EXPR_ADD && term.tag!=EXPR_SUB && term.tag!=EXPR_MUL { return 0,false; }
    let a,ak=static_capture_term(v,object,at(c,term.args,0),geometry,bindings,depth+1); let b,bk=static_capture_term(v,object,at(c,term.args,1),geometry,bindings,depth+1); if !ak || !bk { return 0,false; }
    if term.tag==EXPR_SUB { return a-b,a>=b; } let n=if term.tag==EXPR_ADD { (a as u64)+b } else { (a as u64)*b }; return n as! u32,n<=MAX_U32;
}
fn static_capture_facts(v:Context,object:StaticObject,geometry:const Geometry[:],bindings:const StaticWitness[:])->bool {
    let c=v.c;
    for e,ei in c.evidence { if !visit(v,1) { return false from static_capture_facts; }
        if ei==0 || e.rule!=RULE_CAPTURE || e.call!=object.constructor { continue; }
        let fact=c.facts[e.fact]; let a,ak=static_capture_term(v,object,fact.left,geometry,bindings,0); let b,bk=static_capture_term(v,object,fact.right,geometry,bindings,0); if !ak || !bk { return false; }
        var valid=false;
        if fact.tag==FACT_EQ { valid=a==b; } else if fact.tag==FACT_LT || fact.tag==FACT_INDEX { valid=a<b; } else if fact.tag==FACT_LE { valid=a<=b; }
        else if fact.tag==FACT_ADD_FITS { valid=(a as u64)+b<=MAX_U32; } else if fact.tag==FACT_SUB_FITS { valid=b<=a; } else if fact.tag==FACT_MUL_FITS { valid=(a as u64)*b<=MAX_U32; }
        if !valid { return false; }
    }
    return true;
}
fn static_environment(v:Context,object:StaticObject,geometry:const Geometry[:],used:u32[>..]&,bindings:StaticWitness[>..<]&)->bool {
    let c=v.c;
    if object.function==0 || object.constructor==0 || object.element_type!=0 || object.domain!=0 || object.count!=1 { return false; }
    let f=c.functions[object.function]; let op=c.ops[object.constructor]; let shape=c.types[terminal(v,object.type_id)];
    if f.evaluator_only || op.tag!=OP_CLOSURE || op.imm0!=object.function || op.results.count!=1 || shape.tag!=TY_TUPLE && shape.tag!=TY_RECORD || object.bytes.count!=geometry[object.type_id].size { return false; }
    var adapter_id:u32=0; for row,id in c.callable_adapters { if !visit(v,1) { return false from static_environment; } if id!=0 && row.op==object.constructor { adapter_id=id as u32; } }
    var prefix:u32=0;
    if adapter_id!=0 {
        let adapter=c.callable_adapters[adapter_id]; prefix=adapter.captures.count;
        if adapter.target_environment_offset!=prefix*4 || type_count(shape)!=prefix+f.environment_bindings.count+f.captures.count { return false; }
        for i in adapter.captures.count { if !visit(v,1) { return false from static_environment; } let capture=c.adapter_captures[at(c,adapter.captures,i)];
            if capture.offset!=i*4 || c.types[terminal(v,type_child(c,shape,i))].tag!=TY_U32 { return false; }
            if capture.kind==KIND_TYPE {
                let relocation=static_relocation(v,object,i*4,used); if relocation==0 { return false; } let r=c.static_relocations[relocation];
                if r.kind!=STATIC_DICTIONARY || r.addend!=0 || static_word(c,object.bytes,i*4)!=0 || !closed_dictionary_type(v,r.target,0) { return false; }
                // Closed adapter dictionaries must equal the declared selected type.
                // Ambient parameter dictionaries bind their exact declared source.
                let source=c.types[terminal(v,capture.source)];
                if source.tag==TY_PARAM {
                    let constraints=c.binders[source.binder].constraints;
                    if constraints & CONSTRAINT_PLAIN!=0 && !geometry[r.target].plain || constraints & CONSTRAINT_SHARE!=0 && !geometry[r.target].share { return false; }
                    bindings.push(StaticWitness{binder:source.binder,kind:KIND_TYPE,value:r.target,..});
                }
                else if !same_type(v,capture.source,r.target,0) { return false; }
            } else {
                let source=c.terms[capture.source]; let value=static_word(c,object.bytes,i*4);
                if source.tag==EXPR_BINDER { bindings.push(StaticWitness{binder:source.binder,kind:KIND_NAT,value:value,..}); }
                else { let exact,known=static_nat(v,capture.source,bindings,0); if !known || exact!=value { return false; } }
            }
        }
    }
    if type_count(shape)!=prefix+f.environment_bindings.count+f.captures.count { return false; }
    for i in f.environment_bindings.count { if !visit(v,1) { return false from static_environment; } let binding=c.environment_bindings[at(c,f.environment_bindings,i)];
        if binding.offset!=i*4 || c.types[terminal(v,type_child(c,shape,prefix+i))].tag!=TY_U32 { return false; }
        var value=static_word(c,object.bytes,(prefix+i)*4);
        if binding.kind==KIND_TYPE {
            let relocation=static_relocation(v,object,(prefix+i)*4,used); if relocation==0 { return false; } let r=c.static_relocations[relocation];
            if r.kind!=STATIC_DICTIONARY || r.addend!=0 || value!=0 || !closed_dictionary_type(v,r.target,0) { return false; } value=r.target;
            let constraints=c.binders[binding.binder].constraints;
            if constraints & CONSTRAINT_PLAIN!=0 && !geometry[value].plain || constraints & CONSTRAINT_SHARE!=0 && !geometry[value].share { return false; }
        }
        bindings.push(StaticWitness{binder:binding.binder,kind:binding.kind,value:value,..});
    }
    var offset=(prefix+f.environment_bindings.count)*4;
    for i in f.captures.count { if !visit(v,1) { return false from static_environment; } let capture=c.captures[at(c,f.captures,i)]; let actual=type_child(c,shape,prefix+f.environment_bindings.count+i);
        if !static_type_match(v,c.values[capture.local_value].type_id,actual,bindings,0) || !static_value(v,object,actual,offset,geometry,used,bindings,0) { return false; }
        offset+=geometry[actual].size;
    }
    return static_capture_facts(v,object,geometry,bindings);
}

recursive fn plain_structure(v:Context,ty:u32,depth:u32)->bool {
    if !visit(v,1) { return false; }
    let c=v.c;
    if depth>LIMIT_NEST { return false; } let t=c.types[ty];
    if t.tag==TY_UNIT || t.tag==TY_BOOL || t.tag==TY_U32 || t.tag==TY_F32 || t.tag==TY_INDEX { return true; }
    if t.tag==TY_PARAM { return c.binders[t.binder].constraints & CONSTRAINT_PLAIN!=0; }
    if t.tag!=TY_TUPLE && t.tag!=TY_RECORD && t.tag!=TY_SUM && t.tag!=TY_EXISTS && t.tag!=TY_ALIAS { return false; }
    for i in type_count(t) { if !visit(v,1) { return false; } if !plain_structure(v,type_child(c,t,i),depth+1) { return false; } } return true;
}

recursive fn boolean_path(v:Context,incoming:u32,wanted:u32,truth:bool,depth:u32)->bool {
    if !proof_visit(v,1) || depth>LIMIT_NEST { return false; } let c=v.c; let edge=c.edges[incoming];
    for candidate,id in c.edges { if !proof_visit(v,1) { return false from boolean_path; }
        if id==0 || candidate.kind!=EDGE_TRUE && candidate.kind!=EDGE_FALSE || c.blocks[candidate.from].function!=c.blocks[edge.from].function { continue; }
        if !proof_visit(v,1) { return false; } let term=c.terminators[c.blocks[candidate.from].term];
        if term.tag!=TERM_BRANCH || !contains(v,term.edges,id as u32) { continue; }
        var controls=id==incoming;
        if !controls {
            var unique=true;
            for other,oi in c.edges { if !proof_visit(v,1) { return false from boolean_path; } if oi!=0 && oi!=id && other.to==candidate.to && contains(v,c.terminators[c.blocks[other.from].term].edges,oi as u32) { unique=false; break; } }
            controls=unique && dominates(v,candidate.to,edge.from);
        }
        if controls && boolean_implies(v,term.subject,candidate.kind==EDGE_TRUE,wanted,truth,depth+1) { return true; }
    }
    return false;
}
recursive fn boolean_implies(v:Context,value:u32,truth:bool,wanted:u32,wanted_truth:bool,depth:u32)->bool {
    if !proof_visit(v,1) || depth>LIMIT_NEST { return false; } let c=v.c;
    if value==wanted { return truth==wanted_truth; }
    let target=c.values[wanted]; if target.op!=0 && c.ops[target.op].tag==OP_BOOL_NOT { return boolean_implies(v,value,truth,at(c,c.ops[target.op].args,0),!wanted_truth,depth+1); }
    let val=c.values[value];
    if val.op!=0 {
        let op=c.ops[val.op];
        if op.tag==OP_BOOL { return (op.imm0!=0)!=truth; }
        if op.tag==OP_BOOL_NOT { return boolean_implies(v,at(c,op.args,0),!truth,wanted,wanted_truth,depth+1); }
        if op.tag==OP_BOOL_AND && truth || op.tag==OP_BOOL_OR && !truth {
            return boolean_implies(v,at(c,op.args,0),truth,wanted,wanted_truth,depth+1) || boolean_implies(v,at(c,op.args,1),truth,wanted,wanted_truth,depth+1);
        }
        return false;
    }
    let basic=c.blocks[val.block_id]; var ordinal:u32=0; var found=false;
    for i in basic.params.count { if !proof_visit(v,1) { return false from boolean_implies; } if at(c,basic.params,i)==value { ordinal=i; found=true; break; } }
    if !found || val.block_id==c.functions[basic.function].entry { return false; }
    var predecessors:u32=0;
    for edge,id in c.edges {
        if !proof_visit(v,1) { return false; }
        if id==0 || edge.to!=val.block_id || !contains(v,c.terminators[c.blocks[edge.from].term].edges,id as u32) { continue; } predecessors++;
        if !boolean_implies(v,at(c,edge.args,ordinal),truth,wanted,wanted_truth,depth+1) && !boolean_path(v,id as u32,wanted,wanted_truth,depth+1) { return false; }
    }
    return predecessors!=0;
}
fn boolean_fact(v:Context,e:Evidence,f:Fact)->bool {
    let c=v.c; if e.operands.count!=2 || e.edge==0 || e.premises.count!=0 { return false; }
    let edge=c.edges[e.edge]; let term=c.terminators[c.blocks[edge.from].term];
    let outer=at(c,e.operands,0); let constituent=at(c,e.operands,1);
    if term.tag!=TERM_BRANCH || term.subject!=outer || !contains(v,term.edges,e.edge) || edge.kind!=EDGE_TRUE && edge.kind!=EDGE_FALSE { return false; }
    for side in 2 { if !visit(v,1) { return false from boolean_fact; } let truth=side==0;
        if comparison_value_fact(v,constituent,truth,f) && boolean_implies(v,outer,edge.kind==EDGE_TRUE,constituent,truth,0) { return true; }
    } return false;
}

recursive fn known_boolean(v:Context,value:u32,depth:u32)->bool,bool {
    if !proof_visit(v,1) || depth>LIMIT_NEST { return false,false; } let c=v.c; let id=c.values[value].op; if id==0 { return false,false; } let op=c.ops[id];
    if op.tag==OP_BOOL { return op.imm0!=0,true; }
    if op.tag==OP_BOOL_NOT { let result,known=known_boolean(v,at(c,op.args,0),depth+1); return !result,known; }
    if op.tag==OP_BOOL_AND || op.tag==OP_BOOL_OR {
        let a,ak=known_boolean(v,at(c,op.args,0),depth+1); let b,bk=known_boolean(v,at(c,op.args,1),depth+1);
        if op.tag==OP_BOOL_AND { if ak && !a || bk && !b { return false,true; } return a && b,ak && bk; }
        if ak && a || bk && b { return true,true; } return a || b,ak && bk;
    }
    if op.args.count!=2 { return false,false; }
    let a,ak=literal_value(c,at(c,op.args,0)); let b,bk=literal_value(c,at(c,op.args,1)); if !ak || !bk { return false,false; }
    if op.tag==OP_U32_EQ {return a==b,true;} if op.tag==OP_U32_NE {return a!=b,true;}
    if op.tag==OP_U32_LT {return a<b,true;} if op.tag==OP_U32_LE {return a<=b,true;}
    if op.tag==OP_U32_GT {return a>b,true;} if op.tag==OP_U32_GE {return a>=b,true;}
    if op.tag==OP_ADD_FITS {return (a as u64)+b<=MAX_U32,true;} if op.tag==OP_SUB_FITS {return b<=a,true;} if op.tag==OP_MUL_FITS {return (a as u64)*b<=MAX_U32,true;}
    return false,false;
}
fn literal_unreachable(v:Context,target:u32)->bool {
    let c=v.c; let f=c.functions[c.blocks[target].function];
    var seen:bool[>..]=[]; for row in c.blocks { seen.push(false); } var queue:u32[>..]=[]; queue.push(f.entry); seen[f.entry]=true; var cursor:i64=0;
    while cursor<queue.len {
        if !proof_visit(v,1) { return false; } let current=queue[cursor]; cursor++; if current==target { return false; }
        let term=c.terminators[c.blocks[current].term]; var known=false; var truth=false;
        if term.tag==TERM_BRANCH { truth,known=known_boolean(v,term.subject,0); }
        var variant:u32=0; var sum_known=false;
        if term.tag==TERM_SWITCH && c.values[term.subject].op!=0 { let op=c.ops[c.values[term.subject].op]; if op.tag==OP_SUM { sum_known=true; variant=op.imm0; } }
        for i in term.edges.count {
            if !proof_visit(v,1) { return false; } let edge=c.edges[at(c,term.edges,i)];
            if known && (edge.kind==EDGE_TRUE)!=truth { continue; }
            if sum_known && edge.case_tag!=variant { continue; }
            if !seen[edge.to] { seen[edge.to]=true; queue.push(edge.to); }
        }
    }
    return true;
}
fn contradictory_fact(v:Context,f:Fact)->bool {
    if (f.tag==FACT_LT || f.tag==FACT_INDEX) && f.left==f.right { return true; }
    let a,ak=literal_term(v,f.left,0); let b,bk=literal_term(v,f.right,0); if !ak || !bk { return false; }
    if f.tag==FACT_INDEX { return a>=b; }
    return !literal_fact(v,f);
}
fn contradictory_pair(a:Fact,b:Fact)->bool {
    if a.tag==FACT_EQ && (b.tag==FACT_LT || b.tag==FACT_INDEX) { return a.left==b.left && a.right==b.right || a.left==b.right && a.right==b.left; }
    if (a.tag==FACT_LE || a.tag==FACT_LT) && b.tag==FACT_LT { return a.left==b.right && a.right==b.left; }
    return false;
}
fn unreachable_terminator(v:Context,block_id:u32,term:Terminator)->bool {
    let c=v.c; let basic=c.blocks[block_id]; if term.subject!=0 || term.edges.count!=0 || term.discharge.count!=0 { return false; }
    for i in term.evidence.count { if !proof_visit(v,1) { return false from unreachable_terminator; } if !evidence_usable(v,at(c,term.evidence,i),block_id,basic.ops.count,0) { return false; } }
    for i in term.evidence.count { if !proof_visit(v,1) { return false from unreachable_terminator; }
        let a=c.facts[c.evidence[at(c,term.evidence,i)].fact]; if contradictory_fact(v,a) { return true; }
        for j in i { if !proof_visit(v,1) { return false; } let b=c.facts[c.evidence[at(c,term.evidence,j)].fact]; if contradictory_pair(a,b) || contradictory_pair(b,a) { return true; } }
    }
    return literal_unreachable(v,block_id);
}

fn closure_environment_bound(v:Context,function_id:u32,geometry:const Geometry[:])->u32 {
    let c=v.c;
    for plan,id in c.abi_plans { if !visit(v,1) { return 0; } if id!=0 && plan.function==function_id && plan.env_layout!=0 { return geometry[c.layouts[plan.env_layout].type_id].size; } }
    let f=c.functions[function_id]; var size=f.environment_bindings.count*4; var dependent=false;
    for i in f.captures.count { if !visit(v,1) { return 0 from closure_environment_bound; } let g=geometry[c.values[c.captures[at(c,f.captures,i)].value].type_id]; size+=g.size; dependent=dependent || g.dependent; }
    return if dependent { min(size,256) } else {size};
}

fn operation_block(v:Context,operation:u32)->u32 {
    let index=v.indexes; if index { if !visit(v,1) { return 0; } return index.op_blocks[operation]; }
    for basic,id in v.c.blocks { if !visit(v,1) { return 0 from operation_block; } if id==0 {continue;} for i in basic.ops.count { if !visit(v,1) {return 0;} if at(v.c,basic.ops,i)==operation {return id as u32;} } } return 0;
}
recursive fn capture_alias(v:Context,value:u32,original:u32,depth:u32)->bool {
    if value==original {return true;} if !visit(v,1) || depth>LIMIT_NEST {return false;}
    for capture,id in v.c.captures { if !visit(v,1) { return false from capture_alias; } if id!=0 && capture.local_value==value {return capture_alias(v,capture.value,original,depth+1);} } return false;
}
fn generic_binding(v:Context,id:u32,geometry:const Geometry[:])->bool {
    let c=v.c; let op=c.ops[id]; if op.results.count!=0 || !id_ok(op.imm0,c.functions.len) || op.substitutions.count!=0 {return reject(v,2034,id);}
    let f=c.functions[op.imm0]; if f.evaluator_only || c.contracts[f.contract].binders.count==0 || op.args.count!=f.captures.count {return reject(v,2026,id);}
    for i in f.captures.count { if !visit(v,1) { return false from generic_binding; } let capture=c.captures[at(c,f.captures,i)];let value=at(c,op.args,i);if capture.value!=value || !geometry[c.values[value].type_id].share {return reject(v,2019,id);} }
    return true;
}

// Producer identity is the exact module path plus source declaration name.
// Sorting gives bounded duplicate detection without trusting an interned Name ID.
fn producer_identities(v:Context)->bool {
    let c=v.c;var modules:u32[>..]=[];var definitions:u32[>..]=[];
    fn compare(a:const u8[:],b:const u8[:])->i32 {for i in min(a.len,b.len) {if !visit(v,1) {return false from producer_identities;}if a[i]<b[i] {return -1;}if a[i]>b[i] {return 1;}}if a.len<b.len {return -1;}if a.len>b.len {return 1;}return 0;}
    for row,id in c.modules { if !visit(v,1) { return false from producer_identities; }if id!=0 {modules.push(id as u32);}}
    sort(modules[..]) {a,b=>compare(name_bytes(c,c.modules[a].path),name_bytes(c,c.modules[b].path))<0};
    for i in 1..modules.len { if !visit(v,1) { return false from producer_identities; }if compare(name_bytes(c,c.modules[modules[i-1]].path),name_bytes(c,c.modules[modules[i]].path))==0 {return reject(v,2034,modules[i]);}}
    for row,id in c.definitions { if !visit(v,1) { return false from producer_identities; }if id!=0 {definitions.push(id as u32);}}
    sort(definitions[..]) {a,b=>let x=c.definitions[a];let y=c.definitions[b];if x.module!=y.module {x.module<y.module}else{compare(name_bytes(c,x.name),name_bytes(c,y.name))<0}};
    for i in 1..definitions.len { if !visit(v,1) { return false from producer_identities; }let a=c.definitions[definitions[i-1]];let b=c.definitions[definitions[i]];if a.module==b.module && compare(name_bytes(c,a.name),name_bytes(c,b.name))==0 {return reject(v,2034,definitions[i]);}}
    var owners:u32[>..]=[];for row in c.definitions {owners.push(0);}
    for module,id in c.modules { if !visit(v,1) { return false from producer_identities; }if id==0 {continue;}for i in module.declarations.count {if !visit(v,1) {return false;}let definition=at(c,module.declarations,i);if owners[definition]!=0 || c.definitions[definition].module!=id {return reject(v,2034,definition);}owners[definition]=id as u32;}}
    for row,id in c.definitions { if !visit(v,1) { return false from producer_identities; }if id!=0 && row.module!=0 && owners[id]!=row.module {return reject(v,2034,id as u32);}}
    return true;
}

// Planning compatibility entrypoint: classification is bounded independently;
// independent validation calls template_type with its actual admission account.
fn type_is_template(c:Core,type_id:u32,depth:u32)->bool {
    var work=Work{..};var diagnostics:Diagnostic[>..]=[];
    return template_type(Context{c,FRESH,work,diagnostics,validation_input_limit(c),LIMIT_PROOF_VISITS},type_id,depth);
}

fn diagnostic_origin(c:Core,id:u32)->u32 {
    if !id_ok(id,c.origins.len) {return 0;}let origin=c.origins[id];if !id_ok(origin.module,c.modules.len) || origin.start>origin.end {return 0;}let module=c.modules[origin.module];
    if !span_ok(module.source,c.bytes.len) || origin.end>module.source.count || module.path!=0 && (!id_ok(module.path,c.names.len) || !span_ok(c.names[module.path].bytes,c.bytes.len)) {return 0;}return id;
}
fn with_origin(v:Context,origin:u32)->Context {var result=v;result.origin=diagnostic_origin(v.c,origin);return result;}

fn proof_context(v:Context)->Context {var result=v;result.proof_mode=true;return result;}
