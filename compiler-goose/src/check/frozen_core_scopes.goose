// Staging and associated-type binders use explicit linear caller-owned scratch.
namespace blot_check_frozen_core_validation;
import reuse.principal_interface;

import check.capability_invocations;
import check.capability_lifetimes;
import check.core;
import check.numeric_proof_core;
import check.rank_portable;
import check.scheme_equations;
import check.staging_capture_rights;
import check.staging_core;
import check.storage_core;
import check.task_core;
import check.typed_staging;
import check.types;
import eval.implementation_admission;
import eval.selected_implementation_admission;
import support.error;
import support.option;

import .frozen_core_validation;
import .frozen_core_bounds;
import .frozen_core_graph;
fn stageBinding(bindings: u8[:],binding: u32,stage: u8) -> Error { if binding == 0 { return blot_error::Error.none; } let encoded=stage+1; { let propagated_error = require(bindings[binding] == 0 || bindings[binding] == encoded); if propagated_error != blot_error::Error.none { return propagated_error; } } bindings[binding]=encoded; return blot_error::Error.none; }
fn stageCarries(m: const Module&,bindings: u8[:],carries: blot_check_core::List,stage: u8) -> Error { for carry in m.loop_carries[carries.start..carries.start+carries.len] { { let propagated_error = stageBinding(bindings,carry.incoming,stage); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = stageBinding(bindings,carry.iteration,stage); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = stageBinding(bindings,carry.backedge,stage); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = stageBinding(bindings,carry.outgoing,stage); if propagated_error != blot_error::Error.none { return propagated_error; } } } return blot_error::Error.none; }
fn stagingBindingCount(m: const Module&) -> i64 { for node in m.nodes { if node.tag == blot_check_core::Tag.staging { return m.bindings.len; } } return 0; }
fn equationError(error: Error,workspace: blot_check_scheme_equations::Workspace?) -> Error { if error != blot_error::Error.none && workspace && workspace.oom { return blot_error::Error.out_of_memory; } return error; }
fn stagingScopes(graph: Graph,context: Context,scratch: Scratch,allocating: bool,workspace: blot_check_scheme_equations::Workspace?) -> Error {
    if stagingBindingCount(graph.m) == 0 { return blot_error::Error.none; }
    var remaining: i64=1000000; var reports: blot_check_staging_capture_rights::Entry[>..<]=[];
    var capture_rights=blot_check_staging_capture_rights::Checker{allocating,graph.m,context.units,remaining,reports, ..};
    let error=stagingWalk(graph,context,scratch,workspace,remaining,capture_rights); capture_rights.deinit(); return error;
}
fn stagingWalk(graph: Graph,context: Context,scratch: Scratch,workspace: blot_check_scheme_equations::Workspace?,remaining: i64&,capture_rights: blot_check_staging_capture_rights::Checker&) -> Error {
    let m .= graph.m; let bindings=scratch.colors[graph.count()+m.types.extra.len+m.extra.len..graph.count()+m.types.extra.len+m.extra.len+m.bindings.len];
    for &value in bindings { value=0; } for &color in scratch.colors[..graph.count()] { color=0; }
    let node_start=graph.starts[kindCode(Kind.node)]; let node_end=graph.starts[kindCode(Kind.node)+1];
    let pattern_start=graph.starts[kindCode(Kind.pattern)]; let pattern_end=graph.starts[kindCode(Kind.pattern)+1]; let closure_start=graph.starts[kindCode(Kind.closure)]; let closure_end=graph.starts[kindCode(Kind.closure)+1];
    for body in m.bodies[1..] {
        for parameter in m.parameters[body.parameters.start..body.parameters.start+body.parameters.len] { { let propagated_error = stageBinding(bindings,parameter.binding,0); if propagated_error != blot_error::Error.none { return propagated_error; } } }
        let root=graph.vertex(Kind.node,body.root); if scratch.colors[root] != 0 { { let propagated_error = require(scratch.colors[root] == 1); if propagated_error != blot_error::Error.none { return propagated_error; } } continue; }
        scratch.colors[root]=1; var depth: i64=1; scratch.path[0]=Frame{root, ..};
        while depth != 0 {
            let top: Frame& =scratch.path[depth-1]; let current_stage=scratch.colors[top.vertex]-1; let is_node=top.vertex >= node_start && top.vertex < node_end;
            if top.edge == 0 {
                if is_node {
                    let id=(top.vertex-node_start) as u32; let n=m.nodes[id]; let quote=n.tag == blot_check_core::Tag.staging && n.c == blot_check_typed_staging::opCode(blot_check_typed_staging::Op.quote); let evaluate=n.tag == blot_check_core::Tag.staging && n.c == blot_check_typed_staging::opCode(blot_check_typed_staging::Op.evaluate);
                    var future_reference=n.tag == blot_check_core::Tag.reference && current_stage != 0;
                    if future_reference { let reference=m.reference(id); if reference.unit == 0 || reference.unit == m.unit { let kind=m.binding(reference.binding).kind; future_reference=kind != blot_reuse_principal_interface::Kind.parameter && kind != blot_reuse_principal_interface::Kind.local; } }
                    if quote || evaluate || future_reference || (n.tag == blot_check_core::Tag.call && current_stage != 0) {
                        var closed_rows=body.closed_rows; var owner_depth=depth;
                        while owner_depth != 0 { owner_depth--; let vertex=scratch.path[owner_depth].vertex; if vertex >= closure_start && vertex < closure_end { closed_rows=m.closures[vertex-closure_start].closed_rows; break; } }
                        if quote { { let propagated_error = equationError(blot_check_staging_core::quoteEffectsContextWorkspace(m,context.units,n,closed_rows,remaining,workspace),workspace); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                        else if evaluate { { let propagated_error = equationError(blot_check_staging_core::evaluateEffects(m,context.units,n,closed_rows,remaining,workspace),workspace); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                        else if future_reference { { let propagated_error = equationError(blot_check_staging_core::namedReferenceContextWorkspace(m,context.units,id,closed_rows,remaining,workspace),workspace); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                        else { let ignored,error=blot_check_staging_core::namedCallContextWorkspace(m,context.units,id,remaining,workspace); { let propagated_error = equationError(error,workspace); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                    }
                    for use in m.dictionary_uses { if use.introduction != 0 && use.introduction == id { { let propagated_error = stageBinding(bindings,use.binding,current_stage); if propagated_error != blot_error::Error.none { return propagated_error; } } } }
                    if n.tag == blot_check_core::Tag.bind { { let propagated_error = stageBinding(bindings,n.a,current_stage); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                    if n.tag == blot_check_core::Tag.package_unpack { { let propagated_error = stageBinding(bindings,n.b,current_stage); if propagated_error != blot_error::Error.none { return propagated_error; } } for use in m.dictionary_uses { if use.opening == n.b { { let propagated_error = stageBinding(bindings,use.binding,current_stage); if propagated_error != blot_error::Error.none { return propagated_error; } } } } }
                    for merge in m.merges[m.merge_ranges[id].start..m.merge_ranges[id].start+m.merge_ranges[id].len] { { let propagated_error = stageBinding(bindings,merge.result,current_stage); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = stageBinding(bindings,merge.then_binding,current_stage); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = stageBinding(bindings,merge.else_binding,current_stage); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                    if n.tag == blot_check_core::Tag.loop_ { { let propagated_error = stageCarries(m,bindings,m.loops[n.a].carries,current_stage); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                    if n.tag == blot_check_core::Tag.request_loop { let request=m.request_loops[n.a]; { let propagated_error = stageCarries(m,bindings,request.carries,current_stage); if propagated_error != blot_error::Error.none { return propagated_error; } } for binding in m.extra[request.completion_state_bindings.start..request.completion_state_bindings.start+request.completion_state_bindings.len] { { let propagated_error = stageBinding(bindings,binding,current_stage); if propagated_error != blot_error::Error.none { return propagated_error; } } } }
                    if n.tag == blot_check_core::Tag.update { { let propagated_error = stageBinding(bindings,m.updates[n.a].self_binding,current_stage); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                } else if top.vertex >= pattern_start && top.vertex < pattern_end {
                    let pattern=m.patterns[top.vertex-pattern_start]; if pattern.tag == blot_check_core::PatternTag.bind { { let propagated_error = stageBinding(bindings,pattern.a,current_stage); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                } else if top.vertex >= closure_start && top.vertex < closure_end {
                    let catalog=top.vertex-closure_start; let closure=m.closures[catalog]; { let propagated_error = stageBinding(bindings,closure.parameter.binding,current_stage); if propagated_error != blot_error::Error.none { return propagated_error; } }
                    if current_stage != 0 {
                        var scopes: u32[128]=[0;128]; var scope_count: i64=0; var loans: u32[128]=[0;128]; var loan_count: i64=0; var closure_node: u32=0;
                        for entry,position in scratch.path[..depth] {
                            if entry.vertex < node_start || entry.vertex >= node_end || scratch.colors[entry.vertex] != current_stage+1 { continue; }
                            let id=(entry.vertex-node_start) as u32; let node=m.node(id);
                            if blot_check_capability_lifetimes::isScope(node) { { let propagated_error = require(scope_count < scopes.len); if propagated_error != blot_error::Error.none { return propagated_error; } } scopes[scope_count]=id; scope_count++; }
                            if node.tag == blot_check_core::Tag.usage_borrow || node.tag == blot_check_core::Tag.resource_scope {
                                var callback=node.b; if node.tag == blot_check_core::Tag.resource_scope { callback=node.c; } { let propagated_error = require(m.node(callback).tag == blot_check_core::Tag.closure); if propagated_error != blot_error::Error.none { return propagated_error; } } let owner=graph.vertex(Kind.closure,m.node(callback).a);
                                for ancestor in scratch.path[position+1..depth] { if ancestor.vertex != owner || scratch.colors[owner] != current_stage+1 { continue; } { let propagated_error = require(loan_count < loans.len); if propagated_error != blot_error::Error.none { return propagated_error; } } loans[loan_count]=id; loan_count++; break; }
                            }
                            if node.tag == blot_check_core::Tag.closure && node.a == catalog { closure_node=id; }
                        }
                        if loan_count != 0 { { let propagated_error = require(closure_node != 0); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = capture_rights.requireLoanCaptures(closure_node,loans[..loan_count]); if propagated_error != blot_error::Error.none { return propagated_error; } } }
                        for binding in m.extra[closure.captures.start..closure.captures.start+closure.captures.len] {
                            { let propagated_error = require(binding != closure.parameter.binding); if propagated_error != blot_error::Error.none { return propagated_error; } } let free,error=blot_check_staging_core::authorityFree(m,m.bindings[binding].ty); { let propagated_error = error; if propagated_error != blot_error::Error.none { return propagated_error; } } if free { continue; } { let propagated_error = require(closure_node != 0); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = capture_rights.capture(closure_node,binding,scopes[..scope_count],loans[..loan_count]); if propagated_error != blot_error::Error.none { return propagated_error; } }
                        }
                    }
                }
            }
            let child=graph.edge(top.vertex,top.edge);
            if child.present {
                top.edge++; if child.value == node_start || (m.patterns.len != 0 && child.value == graph.vertex(Kind.pattern,0)) { continue; }
                var stage=current_stage;
                if is_node { let n=m.nodes[top.vertex-node_start]; if n.tag == blot_check_core::Tag.staging { if n.c == blot_check_typed_staging::opCode(blot_check_typed_staging::Op.quote) { { let propagated_error = require(stage < 128); if propagated_error != blot_error::Error.none { return propagated_error; } } stage++; } else if n.c == blot_check_typed_staging::opCode(blot_check_typed_staging::Op.lift) || n.c == blot_check_typed_staging::opCode(blot_check_typed_staging::Op.splice) { { let propagated_error = require(stage != 0); if propagated_error != blot_error::Error.none { return propagated_error; } } stage--; } } }
                if scratch.colors[child.value] != 0 { { let propagated_error = require(scratch.colors[child.value] == stage+1); if propagated_error != blot_error::Error.none { return propagated_error; } } continue; } scratch.colors[child.value]=stage+1; scratch.path[depth]=Frame{child.value, ..}; depth++;
            } else { depth--; }
        }
    }
    for n,id in m.nodes {
        let stage=scratch.colors[graph.vertex(Kind.node,id)]; if stage == 0 { continue; }
        if n.tag == blot_check_core::Tag.closure && stage > 1 { let captures=m.closures[n.a].captures; for binding in m.extra[captures.start..captures.start+captures.len] { let captured=m.bindings[binding]; { let propagated_error = require((captured.kind == blot_reuse_principal_interface::Kind.parameter || captured.kind == blot_reuse_principal_interface::Kind.local) && bindings[binding] == stage); if propagated_error != blot_error::Error.none { return propagated_error; } } } }
        var ref=blot_support::none<blot_check_core::BindingRef>(); if n.tag == blot_check_core::Tag.reference { ref=blot_support::some(m.references[n.a]); } if n.tag == blot_check_core::Tag.call { ref=blot_support::some(m.calls[n.a].target); }
        if ref.present { let target=ref.value; if target.unit == 0 || target.unit == m.unit { let binding=m.bindings[target.binding]; if binding.kind == blot_reuse_principal_interface::Kind.parameter || binding.kind == blot_reuse_principal_interface::Kind.local { { let propagated_error = require(bindings[target.binding] == stage); if propagated_error != blot_error::Error.none { return propagated_error; } } continue; } } if stage > 1 { { let propagated_error = require(n.tag == blot_check_core::Tag.call || n.tag == blot_check_core::Tag.reference); if propagated_error != blot_error::Error.none { return propagated_error; } } } }
    } return blot_error::Error.none;
}
fn associatedCharge(remaining: i64&) -> Error { { let propagated_error = require(remaining != 0); if propagated_error != blot_error::Error.none { return propagated_error; } } remaining--; return blot_error::Error.none; }
fn associatedScope(graph: Graph,contract: blot_check_core::Contract,root: u32,member: bool,scratch: Scratch,remaining: i64&) -> Error {
    let type_count=graph.starts[kindCode(Kind.row)]; let row_start=type_count; let operation_start=graph.starts[kindCode(Kind.operation)]; let count=graph.starts[kindCode(Kind.node)];
    for &color in scratch.colors[..count] { color=0; } var depth: i64=1; scratch.path[0]=Frame{root, ..};
    while depth != 0 {
        let top: Frame& =scratch.path[depth-1];
        if scratch.colors[top.vertex] == 0 {
            { let propagated_error = associatedCharge(remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = require(depth <= 256); if propagated_error != blot_error::Error.none { return propagated_error; } } scratch.colors[top.vertex]=1;
            if top.vertex < type_count { let node=graph.m.types.nodes[top.vertex]; if node.tag == blot_check_types::Tag.variable { var bound=false; for id in graph.m.types.list(contract.variables) { let declared=graph.m.types.node(id); if declared.tag == blot_check_types::Tag.variable && declared.a == node.a { bound=true; break; } } { let propagated_error = require(bound); if propagated_error != blot_error::Error.none { return propagated_error; } } } }
            else if top.vertex < operation_start { let row=graph.m.types.effects.rows[top.vertex-row_start]; match row.tail {
                parameter=>{return blot_error::Error.invalid_artifact;},
                variable tail=>{ var bound=false; if member { for id in graph.m.types.list(contract.row_parameters) { let declared=graph.m.types.effects.rows[id]; match declared.tail { variable v=>{if v.value == tail.value {bound=true;}},_=>{} } } } else { for id in graph.m.types.list(contract.row_variables) { if tail.value == id {bound=true;} } } { let propagated_error = require(bound); if propagated_error != blot_error::Error.none { return propagated_error; } } },_=>{}
            } }
        }
        let recipe_edge=top.vertex < type_count && graph.m.types.nodes[top.vertex].tag == blot_check_types::Tag.projection && top.edge == graph.m.types.extra[graph.m.types.nodes[top.vertex].c];
        var child=blot_support::none<i64>(); if !recipe_edge { child=graph.edge(top.vertex,top.edge); }
        if child.present { top.edge++; if scratch.colors[child.value] == 0 {scratch.path[depth]=Frame{child.value, ..}; depth++;} } else {depth--;}
    } return blot_error::Error.none;
}
fn associatedScopes(graph: Graph,scratch: Scratch,remaining: i64&) -> Error {
    let m .= graph.m; if m.contract_members.len == 0 {return blot_error::Error.none;}
    for contract,ordinal in m.contracts {
        { let propagated_error = associatedCharge(remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = require(contract.identity.unit != 0 && contract.identity.decl == (blot_check_types::opaque_name_bit | contract.name)); if propagated_error != blot_error::Error.none { return propagated_error; } }
        for previous in m.contracts[..ordinal] { { let propagated_error = associatedCharge(remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = require(previous.identity != contract.identity); if propagated_error != blot_error::Error.none { return propagated_error; } } }
        for member in m.contract_members[contract.members.start..contract.members.start+contract.members.len] {{ let propagated_error = associatedScope(graph,contract,member.root,true,scratch,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } }}
        for predicate in m.obligations[contract.predicates.start..contract.predicates.start+contract.predicates.len] { { let propagated_error = associatedScope(graph,contract,predicate.ty,false,scratch,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = associatedScope(graph,contract,predicate.other,false,scratch,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = associatedScope(graph,contract,predicate.result,false,scratch,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = associatedScope(graph,contract,predicate.signature,false,scratch,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    }
    for index in m.contract_members.len {var claims: i64=0; for contract in m.contracts {{ let propagated_error = associatedCharge(remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } if index >= contract.members.start && index-contract.members.start < contract.members.len {claims++;}} { let propagated_error = require(claims == 1); if propagated_error != blot_error::Error.none { return propagated_error; } }} return blot_error::Error.none;
}
fn validateWithScratch(module: const Module&,context: Context,scratch: Scratch) -> Error {
    { let propagated_error = validateBounds(module,context); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = require(module.implementations.len == 0 && module.member_templates.len == 0 && module.selected_proofs.len == 0); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = require(!module.has_numeric_proofs && module.proof_contracts.len == 0); if propagated_error != blot_error::Error.none { return propagated_error; } } for node in module.types.nodes {{ let propagated_error = require(node.tag != blot_check_types::Tag.erased_proof); if propagated_error != blot_error::Error.none { return propagated_error; } }}
    let graph,error=initGraph(module); { let propagated_error = error; if propagated_error != blot_error::Error.none { return propagated_error; } } let needed,requirements_error=scratchRequirements(module); { let propagated_error = requirements_error; if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = require(scratch.colors.len >= needed.colors && scratch.path.len >= needed.path); if propagated_error != blot_error::Error.none { return propagated_error; } }
    let start=graph.count(); { let propagated_error = listRoles(module,scratch.colors[start..start+module.types.extra.len],scratch.colors[start+module.types.extra.len..start+module.types.extra.len+module.extra.len]); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = cycles(graph,scratch); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = blot_check_task_core::validateContext(module,context.units); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = blot_check_staging_core::shapes(module); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = blot_check_storage_core::validate(module); if propagated_error != blot_error::Error.none { return propagated_error; } }
    if stagingScopes(graph,context,scratch,false,null) != blot_error::Error.none {return blot_error::Error.invalid_artifact;} var remaining: i64=1000000; { let propagated_error = associatedScopes(graph,scratch,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = blot_check_rank_portable::executable(module,context); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = blot_check_capability_invocations::validateWithScratch(module,context.units); if propagated_error != blot_error::Error.none { return propagated_error; } } return blot_check_capability_lifetimes::rejectSupportedEscapesWithScratch(module,context.units);
}
reusable[] var validation_colors: u8[>..]=[];
reusable[] var validation_path: Frame[>..]=[];
fn releaseScratch(scratch: Scratch) {
    if scratch.colors.len != 0 {let first: const u8& =scratch.colors[0]; let at=validation_colors.index_of(first); assert(at >= 0); validation_colors.free_slice(validation_colors[at..at+scratch.colors.len]);}
    if scratch.path.len != 0 {let first: const Frame& =scratch.path[0]; let at=validation_path.index_of(first); assert(at >= 0); validation_path.free_slice(validation_path[at..at+scratch.path.len]);}
}
fn validate(module: const Module&,context: Context) -> Error {var remaining: i64=1000000; return validateWithBudget(module,context,remaining);}
fn validateWithBudget(module: const Module&,context: Context,remaining: i64&) -> Error {return validateBatchWithBudget(module,context,remaining,null);}
fn validateBatchWithBudget(module: const Module&,context: Context,remaining: i64&,batch: const Batch?) -> Error {
    { let propagated_error = validateBounds(module,context); if propagated_error != blot_error::Error.none { return propagated_error; } } let graph,error=initGraph(module); { let propagated_error = error; if propagated_error != blot_error::Error.none { return propagated_error; } } let needed,requirements_error=scratchRequirements(module); { let propagated_error = requirements_error; if propagated_error != blot_error::Error.none { return propagated_error; } }
    let scratch=Scratch{validation_colors.alloc_slice(needed.colors),validation_path.alloc_slice(needed.path), ..};
    var equations=blot_check_scheme_equations::initWorkspace(blot_check_scheme_equations::WorkspaceTables{..});
    let failure=validateAllocated(graph,context,scratch,remaining,batch,equations); equations.deinit(); releaseScratch(scratch); return failure;
}
fn validateAllocated(graph: Graph,context: Context,scratch: Scratch,remaining: i64&,batch: const Batch?,equations: blot_check_scheme_equations::Workspace&) -> Error {
    let module .= graph.m; let start=graph.count(); { let propagated_error = listRoles(module,scratch.colors[start..start+module.types.extra.len],scratch.colors[start+module.types.extra.len..start+module.types.extra.len+module.extra.len]); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = cycles(graph,scratch); if propagated_error != blot_error::Error.none { return propagated_error; } }
    var task_result=blot_error::Error.none; if batch {task_result=blot_check_task_core::validateBatchWorkspace(module,batch,equations);} else {task_result=blot_check_task_core::validateContextWorkspace(module,context.units,equations);}
    { let propagated_error = equationError(task_result,equations); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = blot_check_staging_core::shapes(module); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = blot_check_storage_core::validate(module); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = stagingScopes(graph,context,scratch,true,equations); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = associatedScopes(graph,scratch,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = blot_eval_implementation_admission::scopes(module.types,module,module.obligations,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = blot_eval_selected_implementation_admission::core(module,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = blot_check_numeric_proof_core::validate(module,context.units,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = blot_check_rank_portable::executableWorkspace(module,context,equations); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = blot_check_capability_invocations::validate(module,context.units); if propagated_error != blot_error::Error.none { return propagated_error; } } return blot_check_capability_lifetimes::rejectSupportedEscapes(module,context.units);
}
