// Associated-type binders and storage validation use explicit linear caller-owned scratch.
namespace blot_check_frozen_core_validation;
import reuse.principal_interface;

import check.core;
import check.storage_core;
import check.types;
import eval.implementation_admission;
import eval.selected_implementation_admission;
import support.error;
import support.option;

import .frozen_core_validation;
import .frozen_core_bounds;
import .frozen_core_graph;
fn stagingBindingCount(m: const Module&) -> i64 { return 0; }
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
    { let propagated_error = validateBounds(module,context); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = require(module.implementations.len == 0 && module.member_templates.len == 0 && module.selected_proofs.len == 0); if propagated_error != blot_error::Error.none { return propagated_error; } } for node in module.types.nodes {{ let propagated_error = require(node.tag != blot_check_types::Tag.erased_proof); if propagated_error != blot_error::Error.none { return propagated_error; } }}
    let graph,error=initGraph(module); { let propagated_error = error; if propagated_error != blot_error::Error.none { return propagated_error; } } let needed,requirements_error=scratchRequirements(module); { let propagated_error = requirements_error; if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = require(scratch.colors.len >= needed.colors && scratch.path.len >= needed.path); if propagated_error != blot_error::Error.none { return propagated_error; } }
    let start=graph.count(); { let propagated_error = listRoles(module,scratch.colors[start..start+module.types.extra.len],scratch.colors[start+module.types.extra.len..start+module.types.extra.len+module.extra.len]); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = cycles(graph,scratch); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = blot_check_storage_core::validate(module); if propagated_error != blot_error::Error.none { return propagated_error; } }
    var remaining: i64=1000000; return associatedScopes(graph,scratch,remaining);
}
reusable[] var validation_colors: u8[>..]=[];
reusable[] var validation_path: Frame[>..]=[];
fn releaseScratch(scratch: Scratch) {
    if scratch.colors.len != 0 {validation_colors.free_slice(scratch.colors);}
    if scratch.path.len != 0 {validation_path.free_slice(scratch.path);}
}
fn validate(module: const Module&,context: Context) -> Error {var remaining: i64=1000000; return validateWithBudget(module,context,remaining);}
fn validateWithBudget(module: const Module&,context: Context,remaining: i64&) -> Error {return validateBatchWithBudget(module,context,remaining,null);}
fn validateBatchWithBudget(module: const Module&,context: Context,remaining: i64&,batch: const Batch?) -> Error {
    { let propagated_error = validateBounds(module,context); if propagated_error != blot_error::Error.none { return propagated_error; } } let graph,error=initGraph(module); { let propagated_error = error; if propagated_error != blot_error::Error.none { return propagated_error; } } let needed,requirements_error=scratchRequirements(module); { let propagated_error = requirements_error; if propagated_error != blot_error::Error.none { return propagated_error; } }
    let scratch=Scratch{validation_colors.alloc_slice(needed.colors),validation_path.alloc_slice(needed.path), ..};
    let failure=validateAllocated(graph,context,scratch,remaining,batch); releaseScratch(scratch); return failure;
}
fn validateAllocated(graph: Graph,context: Context,scratch: Scratch,remaining: i64&,batch: const Batch?) -> Error {
    let module .= graph.m; let start=graph.count(); { let propagated_error = listRoles(module,scratch.colors[start..start+module.types.extra.len],scratch.colors[start+module.types.extra.len..start+module.types.extra.len+module.extra.len]); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = cycles(graph,scratch); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = blot_check_storage_core::validate(module); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = associatedScopes(graph,scratch,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = blot_eval_implementation_admission::scopes(module.types,module,module.obligations,remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } return blot_eval_selected_implementation_admission::core(module,remaining);
}
