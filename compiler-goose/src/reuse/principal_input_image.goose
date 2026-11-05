// Constraint inputs erase only primitive literal bits, retaining all source
// operators, branches, capture lists, positions and catalogs.
namespace blot_reuse_principal_input_image;
import check.core;
import check.types;
import support.structural;
fn moduleEqual(old: const blot_check_core::Module&, current: const blot_check_core::Module&) -> bool {
    if !blot_structural::equal(old.has_rank_contracts, current.has_rank_contracts) { return false; }
    if !blot_structural::equal(old.has_usage_contracts, current.has_usage_contracts) { return false; }
    if !blot_structural::equal(old.has_numeric_proofs, current.has_numeric_proofs) { return false; }
    if !blot_structural::equal(old.proof_contracts, current.proof_contracts) { return false; }
    if !blot_structural::equal(old.capability_contracts, current.capability_contracts) { return false; }
    if !blot_structural::equal(old.field_names, current.field_names) { return false; }
    if !blot_structural::equal(old.runtime_names, current.runtime_names) { return false; }
    if !blot_structural::equal(old.source_names, current.source_names) { return false; }
    if !blot_structural::equal(old.declaration_dependencies, current.declaration_dependencies) { return false; }
    if !blot_structural::equal(old.dependency_references, current.dependency_references) { return false; }
    if !blot_structural::equal(old.dependency_members, current.dependency_members) { return false; }
    if !blot_structural::equal(old.erased_declaration_references, current.erased_declaration_references) { return false; }
    if !blot_structural::equal(old.request_loops, current.request_loops) { return false; }
    if !blot_structural::equal(old.request_arms, current.request_arms) { return false; }
    if !blot_structural::equal(old.tag_calls, current.tag_calls) { return false; }
    if !blot_structural::equal(old.unit, current.unit) { return false; }
    if !blot_structural::equal(blot_check_core::typesStampView(old.types), blot_check_core::typesStampView(current.types)) { return false; }
    if !blot_structural::equal(old.spans, current.spans) { return false; }
    if !blot_structural::equal(old.extra, current.extra) { return false; }
    if !blot_structural::equal(old.bindings, current.bindings) { return false; }
    if !blot_structural::equal(old.bodies, current.bodies) { return false; }
    if !blot_structural::equal(old.parameters, current.parameters) { return false; }
    if !blot_structural::equal(old.references, current.references) { return false; }
    if !blot_structural::equal(old.calls, current.calls) { return false; }
    if !blot_structural::equal(old.merges, current.merges) { return false; }
    if !blot_structural::equal(old.merge_ranges, current.merge_ranges) { return false; }
    if !blot_structural::equal(old.names, current.names) { return false; }
    if !blot_structural::equal(old.obligations, current.obligations) { return false; }
    if !blot_structural::equal(old.nominals, current.nominals) { return false; }
    if !blot_structural::equal(old.operation_names, current.operation_names) { return false; }
    if !blot_structural::equal(old.constructors, current.constructors) { return false; }
    if !blot_structural::equal(old.projections, current.projections) { return false; }
    if !blot_structural::equal(old.projection_variants, current.projection_variants) { return false; }
    if !blot_structural::equal(old.patterns, current.patterns) { return false; }
    if !blot_structural::equal(old.pattern_rows, current.pattern_rows) { return false; }
    if !blot_structural::equal(old.match_arms, current.match_arms) { return false; }
    if !blot_structural::equal(old.matches, current.matches) { return false; }
    if !blot_structural::equal(old.updates, current.updates) { return false; }
    if !blot_structural::equal(old.update_steps, current.update_steps) { return false; }
    if !blot_structural::equal(old.closures, current.closures) { return false; }
    if !blot_structural::equal(old.associated, current.associated) { return false; }
    if !blot_structural::equal(old.contracts, current.contracts) { return false; }
    if !blot_structural::equal(old.contract_members, current.contract_members) { return false; }
    if !blot_structural::equal(old.implementations, current.implementations) { return false; }
    if !blot_structural::equal(old.implementation_members, current.implementation_members) { return false; }
    if !blot_structural::equal(old.member_templates, current.member_templates) { return false; }
    if !blot_structural::equal(old.selected_proofs, current.selected_proofs) { return false; }
    if !blot_structural::equal(old.selected_members, current.selected_members) { return false; }
    if !blot_structural::equal(old.selected_edges, current.selected_edges) { return false; }
    if !blot_structural::equal(old.selected_uses, current.selected_uses) { return false; }
    if !blot_structural::equal(old.dictionary_selections, current.dictionary_selections) { return false; }
    if !blot_structural::equal(old.dictionary_uses, current.dictionary_uses) { return false; }
    if !blot_structural::equal(old.primitives, current.primitives) { return false; }
    if !blot_structural::equal(old.loops, current.loops) { return false; }
    if !blot_structural::equal(old.loop_carries, current.loop_carries) { return false; }
    if !blot_structural::equal(old.resolver_ops, current.resolver_ops) { return false; }
    if !blot_structural::equal(old.operation_values, current.operation_values) { return false; }
    if !blot_structural::equal(old.handle_effects, current.handle_effects) { return false; }
    if !blot_structural::equal(old.dispatch_signatures, current.dispatch_signatures) { return false; }
    if !blot_structural::equal(old.diagnostics, current.diagnostics) { return false; }
    if !blot_structural::equal(old.body_lowerings, current.body_lowerings) { return false; }
    if old.nodes.len != current.nodes.len { return false; }
    for before, index in old.nodes {
        var projected = current.nodes[index];
        if before.tag == blot_check_core::Tag.constant && projected.tag == blot_check_core::Tag.constant && before.ty == projected.ty && (before.ty == blot_check_types::unit || before.ty == blot_check_types::boolean || before.ty == blot_check_types::u32_type || before.ty == blot_check_types::f32_type) { projected.a = before.a; }
        if before != projected { return false; }
    }
    return true;
}
