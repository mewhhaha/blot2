// Compare the mapped immutable graph one field at a time. No clone of all Core
// tables is needed merely to prove equality in another name namespace.
namespace blot_reuse_artifact_import;
import reuse.artifact_import;
import reuse.dependency_symbol_slots;
import check.core;
import check.types;
import check.source_sort;
import support.structural;
reusable[] var mapped_field_names: blot_check_core::FieldName[>..] = [];
reusable[] var core_symbol_roles: u8[>..] = [];
struct FieldSort { values: blot_check_core::FieldName[:] }
fn lessThan(self_: FieldSort, left: i64, right: i64) -> bool { return self_.values[left].symbol < self_.values[right].symbol; }
fn swap(self_: FieldSort, left: i64, right: i64) { let value = self_.values[left]; self_.values[left] = self_.values[right]; self_.values[right] = value; }
fn remapIdentity(self_: const Importer&, value: blot_check_types::NominalIdentity&) -> Error {
    if value.unit == 0 || value.unit == 0xffffffff { return blot_error::Error.none; }
    let unit, error = self_.unit(value.unit, false); if error != blot_error::Error.none { return error; }
    let declaration, failure = self_.nominalDeclaration(value.decl); if failure != blot_error::Error.none { return failure; }
    value.unit = unit; value.decl = declaration; return blot_error::Error.none;
}
fn remapReference(self_: const Importer&, value: blot_check_core::BindingRef&) -> Error {
    if value.unit != 0 { let unit, error = self_.unit(value.unit, false); if error != blot_error::Error.none { return error; } value.unit = unit; }
    return blot_error::Error.none;
}
fn optionalSymbol(self_: const Importer&, value: u32&) -> Error {
    if value != 0 { let symbol, error = self_.symbol(value); if error != blot_error::Error.none { return error; } value = symbol; }
    return blot_error::Error.none;
}
fn remapTarget<T>(self_: const Importer&, value: T&) -> Error {
    if value.binding != 0 {
        var target = blot_check_core::BindingRef { value.unit, value.binding , ..};
        { let propagated_error = self_.remapReference(target); if propagated_error != blot_error::Error.none { return propagated_error; } } value.unit = target.unit; value.binding = target.binding;
    }
    return blot_error::Error.none;
}
fn remapPredicate<P>(self_: const Importer&, value: P&) -> Error {
    { let propagated_error = self_.remapIdentity(value.identity); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.optionalSymbol(value.name); if propagated_error != blot_error::Error.none { return propagated_error; } }
    if value.qualification_unit != 0 { let unit, error = self_.unit(value.qualification_unit, false); if error != blot_error::Error.none { return error; } value.qualification_unit = unit; }
    return blot_error::Error.none;
}
fn mapTypeNode(self_: const Importer&, value: blot_check_types::Node&) -> Error {
    if value.tag == blot_check_types::Tag.nominal || value.tag == blot_check_types::Tag.projection || value.tag == blot_check_types::Tag.type_constructor {
        if value.a != 0 && value.a != 0xffffffff {
            let unit, error = self_.unit(value.a, false); if error != blot_error::Error.none { return error; }
            let decl, failure = self_.nominalDeclaration(value.b); if failure != blot_error::Error.none { return failure; }
            value.a = unit; value.b = decl;
        }
    }
    return blot_error::Error.none;
}
fn mapTypeOperation(self_: const Importer&, value: blot_check_types::Operation&) -> Error { return self_.remapIdentity(value.identity); }
fn mapBinding(self_: const Importer&, value: blot_check_core::Binding&) -> Error { return self_.remapReference(value.target); }
fn mapReference(self_: const Importer&, value: blot_check_core::BindingRef&) -> Error { return self_.remapReference(value); }
fn mapErased(self_: const Importer&, value: blot_check_core::ErasedDeclarationReference&) -> Error { return self_.remapReference(value.target); }
fn mapDependencyMember(self_: const Importer&, value: blot_check_core::DependencyMember&) -> Error { return self_.optionalSymbol(value.name); }
fn mapCall(self_: const Importer&, value: blot_check_core::CallInfo&) -> Error { return self_.remapReference(value.target); }
fn mapObligation(self_: const Importer&, value: blot_check_core::Obligation&) -> Error { return self_.remapPredicate(value); }
fn mapNominal(self_: const Importer&, value: blot_check_core::Nominal&) -> Error { return self_.remapIdentity(value.identity); }
fn mapContract(self_: const Importer&, value: blot_check_core::Contract&) -> Error {
    { let propagated_error = self_.remapIdentity(value.identity); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.optionalSymbol(value.name); if propagated_error != blot_error::Error.none { return propagated_error; } } return blot_error::Error.none;
}
fn mapContractMember(self_: const Importer&, value: blot_check_core::ContractMember&) -> Error {
    { let propagated_error = self_.remapIdentity(value.contract); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.optionalSymbol(value.name); if propagated_error != blot_error::Error.none { return propagated_error; } } return blot_error::Error.none;
}
fn mapImplementation(self_: const Importer&, value: blot_check_core::Implementation&) -> Error {
    { let propagated_error = self_.remapIdentity(value.identity); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.remapIdentity(value.contract); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.optionalSymbol(value.name); if propagated_error != blot_error::Error.none { return propagated_error; } } return blot_error::Error.none;
}
fn mapImplementationMember(self_: const Importer&, value: blot_check_core::ImplementationMember&) -> Error {
    { let propagated_error = self_.optionalSymbol(value.name); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.remapTarget(value.target); if propagated_error != blot_error::Error.none { return propagated_error; } } return blot_error::Error.none;
}
fn mapMemberTemplate(self_: const Importer&, value: blot_check_core::MemberTemplate&) -> Error {
    { let propagated_error = self_.remapIdentity(value.contract); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.optionalSymbol(value.name); if propagated_error != blot_error::Error.none { return propagated_error; } } return blot_error::Error.none;
}
fn mapSelectedProof(self_: const Importer&, value: blot_check_core::SelectedProof&) -> Error {
    { let propagated_error = self_.remapTarget(value.predicate_target); if propagated_error != blot_error::Error.none { return propagated_error; } }
    if value.context != 0 { let unit, error = self_.unit(value.context, false); if error != blot_error::Error.none { return error; } value.context = unit; }
    { let propagated_error = self_.remapIdentity(value.implementation); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.remapIdentity(value.contract); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.remapPredicate(value.predicate); if propagated_error != blot_error::Error.none { return propagated_error; } }
    return blot_error::Error.none;
}
fn mapOperationName(self_: const Importer&, value: blot_check_core::OperationName&) -> Error { return self_.remapIdentity(value.identity); }
fn mapConstructor(self_: const Importer&, value: blot_check_core::Constructor&) -> Error { return self_.remapIdentity(value.identity); }
fn mapProjection(self_: const Importer&, value: blot_check_core::Projection&) -> Error {
    { let propagated_error = self_.remapIdentity(value.nominal); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.optionalSymbol(value.field); if propagated_error != blot_error::Error.none { return propagated_error; } } return blot_error::Error.none;
}
fn mapAssociated(self_: const Importer&, value: blot_check_core::Associated&) -> Error {
    { let propagated_error = self_.remapIdentity(value.identity); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.remapReference(value.target); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.optionalSymbol(value.member); if propagated_error != blot_error::Error.none { return propagated_error; } } return blot_error::Error.none;
}
fn mapResolver(self_: const Importer&, value: blot_check_core::ResolverInfo&) -> Error {
    { let propagated_error = self_.remapReference(value.method); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.optionalSymbol(value.member); if propagated_error != blot_error::Error.none { return propagated_error; } } return blot_error::Error.none;
}
fn mapOperationValue(self_: const Importer&, value: blot_check_core::OperationValue&) -> Error { return self_.remapIdentity(value.identity); }
fn mapNode(self_: const Importer&, value: blot_check_core::Node&) -> Error {
    if value.tag == blot_check_core::Tag.associated { return self_.optionalSymbol(value.c); }
    if value.tag == blot_check_core::Tag.result_associated { return self_.optionalSymbol(value.b); }
    return blot_error::Error.none;
}
fn mappedEqual<T,F>(self_: const Importer&, left: const T[:], right: const T[:]) -> bool, Error {
    if left.len != right.len { return false, blot_error::Error.none; }
    for source, index in left {
        var value = source; let error = F(self_, value); if error != blot_error::Error.none { return false, error; }
        if !blot_structural::equal(value, right[index]) { return false, blot_error::Error.none; }
    }
    return true, blot_error::Error.none;
}
fn coreEqual(self_: const Importer&, old: const Module&, current: const Module&) -> bool, Error {
    var identical_namespaces = true;
    for mapped, index in self_.unit_map { if mapped != index + 1 { identical_namespaces = false; } }
    for mapped, index in self_.symbol_map { if mapped != index { identical_namespaces = false; } }
    if identical_namespaces && blot_structural::equal(blot_check_core::stampView(old), blot_check_core::stampView(current)) { return true, blot_error::Error.none; }
    let roles = core_symbol_roles.alloc_slice(old.types.extra.len);
    let fields = mapped_field_names.alloc_slice(old.field_names.len);
    let equal, error = self_.coreEqualMapped(old, current, roles, fields);
    if roles.len != 0 { core_symbol_roles.free_slice(roles); } if fields.len != 0 { mapped_field_names.free_slice(fields); }
    return equal, error;
}

fn coreEqualMapped(self_: const Importer&, old: const Module&, current: const Module&, roles: u8[:], fields: blot_check_core::FieldName[:]) -> bool, Error {
    let role_error = blot_reuse_dependency_symbol_slots::coreRoles(roles, old);
    if role_error != blot_error::Error.none { return false, convert(role_error); }
    for field, index in old.field_names {
        fields[index] = field; let error = self_.optionalSymbol(fields[index].symbol);
        if error != blot_error::Error.none { return false, error; }
    }
    blot_check_source_sort::pdqContext(0, fields.len, FieldSort { fields , ..});
    if !blot_structural::equal(fields, current.field_names) { return false, blot_error::Error.none; }
    var unit = old.unit;
    if unit != 0 { let mapped, error = self_.unit(unit, false); if error != blot_error::Error.none { return false, error; } unit = mapped; }
    if unit != current.unit { return false, blot_error::Error.none; }
    if old.types.extra.len != current.types.extra.len { return false, blot_error::Error.none; }
    for original, index in old.types.extra {
        var word = original;
        if roles[index] == 1 { let mapped, error = self_.symbol(word); if error != blot_error::Error.none { return false, error; } word = mapped; }
        if word != current.types.extra[index] { return false, blot_error::Error.none; }
    }
    { let equal, error = self_.mappedEqual(old.types.nodes, current.types.nodes, mapTypeNode); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.types.operations, current.types.operations, mapTypeOperation); if error != blot_error::Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.types.effects, current.types.effects) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.types.quantifier_goals, current.types.quantifier_goals) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.types.quantifier_obligations, current.types.quantifier_obligations) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.has_rank_contracts, current.has_rank_contracts) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.has_usage_contracts, current.has_usage_contracts) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.has_numeric_proofs, current.has_numeric_proofs) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.proof_contracts, current.proof_contracts) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.capability_contracts, current.capability_contracts) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.runtime_names, current.runtime_names) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.source_names, current.source_names) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.declaration_dependencies, current.declaration_dependencies) { return false, blot_error::Error.none; }
    { let equal, error = self_.mappedEqual(old.dependency_references, current.dependency_references, mapReference); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.dependency_members, current.dependency_members, mapDependencyMember); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.erased_declaration_references, current.erased_declaration_references, mapErased); if error != blot_error::Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.request_loops, current.request_loops) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.request_arms, current.request_arms) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.tag_calls, current.tag_calls) { return false, blot_error::Error.none; }
    { let equal, error = self_.mappedEqual(old.nodes, current.nodes, mapNode); if error != blot_error::Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.spans, current.spans) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.extra, current.extra) { return false, blot_error::Error.none; }
    { let equal, error = self_.mappedEqual(old.bindings, current.bindings, mapBinding); if error != blot_error::Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.bodies, current.bodies) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.parameters, current.parameters) { return false, blot_error::Error.none; }
    { let equal, error = self_.mappedEqual(old.references, current.references, mapReference); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.calls, current.calls, mapCall); if error != blot_error::Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.merges, current.merges) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.merge_ranges, current.merge_ranges) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.names, current.names) { return false, blot_error::Error.none; }
    { let equal, error = self_.mappedEqual(old.obligations, current.obligations, mapObligation); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.nominals, current.nominals, mapNominal); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.operation_names, current.operation_names, mapOperationName); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.constructors, current.constructors, mapConstructor); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.projections, current.projections, mapProjection); if error != blot_error::Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.projection_variants, current.projection_variants) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.patterns, current.patterns) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.pattern_rows, current.pattern_rows) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.match_arms, current.match_arms) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.matches, current.matches) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.updates, current.updates) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.update_steps, current.update_steps) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.closures, current.closures) { return false, blot_error::Error.none; }
    { let equal, error = self_.mappedEqual(old.associated, current.associated, mapAssociated); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.contracts, current.contracts, mapContract); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.contract_members, current.contract_members, mapContractMember); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.implementations, current.implementations, mapImplementation); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.implementation_members, current.implementation_members, mapImplementationMember); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.member_templates, current.member_templates, mapMemberTemplate); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.selected_proofs, current.selected_proofs, mapSelectedProof); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.selected_members, current.selected_members, mapImplementationMember); if error != blot_error::Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.selected_edges, current.selected_edges) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.selected_uses, current.selected_uses) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.dictionary_selections, current.dictionary_selections) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.dictionary_uses, current.dictionary_uses) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.primitives, current.primitives) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.loops, current.loops) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.loop_carries, current.loop_carries) { return false, blot_error::Error.none; }
    { let equal, error = self_.mappedEqual(old.resolver_ops, current.resolver_ops, mapResolver); if error != blot_error::Error.none || !equal { return false, error; } }
    { let equal, error = self_.mappedEqual(old.operation_values, current.operation_values, mapOperationValue); if error != blot_error::Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.handle_effects, current.handle_effects) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.dispatch_signatures, current.dispatch_signatures) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.diagnostics, current.diagnostics) { return false, blot_error::Error.none; }
    if !blot_structural::equal(old.body_lowerings, current.body_lowerings) { return false, blot_error::Error.none; }
    return true, blot_error::Error.none;
}
