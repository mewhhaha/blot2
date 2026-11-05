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
fn lessThan(self: FieldSort, left: i64, right: i64) -> bool { return self.values[left].symbol < self.values[right].symbol; }
fn swap(self: FieldSort, left: i64, right: i64) { let value = self.values[left]; self.values[left] = self.values[right]; self.values[right] = value; }
fn remapIdentity(self: const Importer&, value: blot_check_types::NominalIdentity&) -> Error {
    if value.unit == 0 || value.unit == 0xffffffff { return Error.none; }
    let unit, error = self.unit(value.unit, false); if error != Error.none { return error; }
    let declaration, failure = self.nominalDeclaration(value.decl); if failure != Error.none { return failure; }
    value.unit = unit; value.decl = declaration; return Error.none;
}
fn remapReference(self: const Importer&, value: blot_check_core::BindingRef&) -> Error {
    if value.unit != 0 { let unit, error = self.unit(value.unit, false); if error != Error.none { return error; } value.unit = unit; }
    return Error.none;
}
fn optionalSymbol(self: const Importer&, value: u32&) -> Error {
    if value != 0 { let symbol, error = self.symbol(value); if error != Error.none { return error; } value = symbol; }
    return Error.none;
}
fn remapTarget<T>(self: const Importer&, value: T&) -> Error {
    if value.binding != 0 {
        var target = blot_check_core::BindingRef { value.unit, value.binding , ..};
        { let propagated_error = self.remapReference(target); if propagated_error != Error.none { return propagated_error; } } value.unit = target.unit; value.binding = target.binding;
    }
    return Error.none;
}
fn remapPredicate<P>(self: const Importer&, value: P&) -> Error {
    { let propagated_error = self.remapIdentity(value.identity); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.optionalSymbol(value.name); if propagated_error != Error.none { return propagated_error; } }
    if value.qualification_unit != 0 { let unit, error = self.unit(value.qualification_unit, false); if error != Error.none { return error; } value.qualification_unit = unit; }
    return Error.none;
}
fn mapTypeNode(self: const Importer&, value: blot_check_types::Node&) -> Error {
    if value.tag == blot_check_types::Tag.nominal || value.tag == blot_check_types::Tag.projection || value.tag == blot_check_types::Tag.type_constructor {
        if value.a != 0 && value.a != 0xffffffff {
            let unit, error = self.unit(value.a, false); if error != Error.none { return error; }
            let decl, failure = self.nominalDeclaration(value.b); if failure != Error.none { return failure; }
            value.a = unit; value.b = decl;
        }
    }
    return Error.none;
}
fn mapTypeOperation(self: const Importer&, value: blot_check_types::Operation&) -> Error { return self.remapIdentity(value.identity); }
fn mapBinding(self: const Importer&, value: blot_check_core::Binding&) -> Error { return self.remapReference(value.target); }
fn mapReference(self: const Importer&, value: blot_check_core::BindingRef&) -> Error { return self.remapReference(value); }
fn mapErased(self: const Importer&, value: blot_check_core::ErasedDeclarationReference&) -> Error { return self.remapReference(value.target); }
fn mapDependencyMember(self: const Importer&, value: blot_check_core::DependencyMember&) -> Error { return self.optionalSymbol(value.name); }
fn mapCall(self: const Importer&, value: blot_check_core::CallInfo&) -> Error { return self.remapReference(value.target); }
fn mapObligation(self: const Importer&, value: blot_check_core::Obligation&) -> Error { return self.remapPredicate(value); }
fn mapNominal(self: const Importer&, value: blot_check_core::Nominal&) -> Error { return self.remapIdentity(value.identity); }
fn mapContract(self: const Importer&, value: blot_check_core::Contract&) -> Error {
    { let propagated_error = self.remapIdentity(value.identity); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.optionalSymbol(value.name); if propagated_error != Error.none { return propagated_error; } } return Error.none;
}
fn mapContractMember(self: const Importer&, value: blot_check_core::ContractMember&) -> Error {
    { let propagated_error = self.remapIdentity(value.contract); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.optionalSymbol(value.name); if propagated_error != Error.none { return propagated_error; } } return Error.none;
}
fn mapImplementation(self: const Importer&, value: blot_check_core::Implementation&) -> Error {
    { let propagated_error = self.remapIdentity(value.identity); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.remapIdentity(value.contract); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.optionalSymbol(value.name); if propagated_error != Error.none { return propagated_error; } } return Error.none;
}
fn mapImplementationMember(self: const Importer&, value: blot_check_core::ImplementationMember&) -> Error {
    { let propagated_error = self.optionalSymbol(value.name); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.remapTarget(value.target); if propagated_error != Error.none { return propagated_error; } } return Error.none;
}
fn mapMemberTemplate(self: const Importer&, value: blot_check_core::MemberTemplate&) -> Error {
    { let propagated_error = self.remapIdentity(value.contract); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.optionalSymbol(value.name); if propagated_error != Error.none { return propagated_error; } } return Error.none;
}
fn mapSelectedProof(self: const Importer&, value: blot_check_core::SelectedProof&) -> Error {
    { let propagated_error = self.remapTarget(value.predicate_target); if propagated_error != Error.none { return propagated_error; } }
    if value.context != 0 { let unit, error = self.unit(value.context, false); if error != Error.none { return error; } value.context = unit; }
    { let propagated_error = self.remapIdentity(value.implementation); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.remapIdentity(value.contract); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.remapPredicate(value.predicate); if propagated_error != Error.none { return propagated_error; } }
    return Error.none;
}
fn mapOperationName(self: const Importer&, value: blot_check_core::OperationName&) -> Error { return self.remapIdentity(value.identity); }
fn mapConstructor(self: const Importer&, value: blot_check_core::Constructor&) -> Error { return self.remapIdentity(value.identity); }
fn mapProjection(self: const Importer&, value: blot_check_core::Projection&) -> Error {
    { let propagated_error = self.remapIdentity(value.nominal); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.optionalSymbol(value.field); if propagated_error != Error.none { return propagated_error; } } return Error.none;
}
fn mapAssociated(self: const Importer&, value: blot_check_core::Associated&) -> Error {
    { let propagated_error = self.remapIdentity(value.identity); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.remapReference(value.target); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.optionalSymbol(value.member); if propagated_error != Error.none { return propagated_error; } } return Error.none;
}
fn mapResolver(self: const Importer&, value: blot_check_core::ResolverInfo&) -> Error {
    { let propagated_error = self.remapReference(value.method); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.optionalSymbol(value.member); if propagated_error != Error.none { return propagated_error; } } return Error.none;
}
fn mapOperationValue(self: const Importer&, value: blot_check_core::OperationValue&) -> Error { return self.remapIdentity(value.identity); }
fn mapNode(self: const Importer&, value: blot_check_core::Node&) -> Error {
    if value.tag == blot_check_core::Tag.associated { return self.optionalSymbol(value.c); }
    if value.tag == blot_check_core::Tag.result_associated { return self.optionalSymbol(value.b); }
    return Error.none;
}
fn mappedEqual<T,F>(self: const Importer&, left: const T[:], right: const T[:]) -> bool, Error {
    if left.len != right.len { return false, Error.none; }
    for source, index in left {
        var value = source; let error = F(self, value); if error != Error.none { return false, error; }
        if !blot_structural::equal(value, right[index]) { return false, Error.none; }
    }
    return true, Error.none;
}
fn coreEqual(self: const Importer&, old: const Module&, current: const Module&) -> bool, Error {
    var identical_namespaces = true;
    for mapped, index in self.unit_map { if mapped != index + 1 { identical_namespaces = false; } }
    for mapped, index in self.symbol_map { if mapped != index { identical_namespaces = false; } }
    if identical_namespaces && blot_structural::equal(blot_check_core::stampView(old), blot_check_core::stampView(current)) { return true, Error.none; }
    let roles = core_symbol_roles.alloc_slice(old.types.extra.len);
    let fields = mapped_field_names.alloc_slice(old.field_names.len);
    let equal, error = self.coreEqualMapped(old, current, roles, fields);
    if roles.len != 0 { core_symbol_roles.free_slice(roles); } if fields.len != 0 { mapped_field_names.free_slice(fields); }
    return equal, error;
}

fn coreEqualMapped(self: const Importer&, old: const Module&, current: const Module&, roles: u8[:], fields: blot_check_core::FieldName[:]) -> bool, Error {
    let role_error = blot_reuse_dependency_symbol_slots::coreRoles(roles, old);
    if role_error != Error.none { return false, convert(role_error); }
    for field, index in old.field_names {
        fields[index] = field; let error = self.optionalSymbol(fields[index].symbol);
        if error != Error.none { return false, error; }
    }
    blot_check_source_sort::pdqContext(0, fields.len, FieldSort { fields , ..});
    if !blot_structural::equal(fields, current.field_names) { return false, Error.none; }
    var unit = old.unit;
    if unit != 0 { let mapped, error = self.unit(unit, false); if error != Error.none { return false, error; } unit = mapped; }
    if unit != current.unit { return false, Error.none; }
    if old.types.extra.len != current.types.extra.len { return false, Error.none; }
    for original, index in old.types.extra {
        var word = original;
        if roles[index] == 1 { let mapped, error = self.symbol(word); if error != Error.none { return false, error; } word = mapped; }
        if word != current.types.extra[index] { return false, Error.none; }
    }
    { let equal, error = self.mappedEqual(old.types.nodes, current.types.nodes, mapTypeNode); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.types.operations, current.types.operations, mapTypeOperation); if error != Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.types.effects, current.types.effects) { return false, Error.none; }
    if !blot_structural::equal(old.types.quantifier_goals, current.types.quantifier_goals) { return false, Error.none; }
    if !blot_structural::equal(old.types.quantifier_obligations, current.types.quantifier_obligations) { return false, Error.none; }
    if !blot_structural::equal(old.has_rank_contracts, current.has_rank_contracts) { return false, Error.none; }
    if !blot_structural::equal(old.has_usage_contracts, current.has_usage_contracts) { return false, Error.none; }
    if !blot_structural::equal(old.has_numeric_proofs, current.has_numeric_proofs) { return false, Error.none; }
    if !blot_structural::equal(old.proof_contracts, current.proof_contracts) { return false, Error.none; }
    if !blot_structural::equal(old.capability_contracts, current.capability_contracts) { return false, Error.none; }
    if !blot_structural::equal(old.runtime_names, current.runtime_names) { return false, Error.none; }
    if !blot_structural::equal(old.source_names, current.source_names) { return false, Error.none; }
    if !blot_structural::equal(old.declaration_dependencies, current.declaration_dependencies) { return false, Error.none; }
    { let equal, error = self.mappedEqual(old.dependency_references, current.dependency_references, mapReference); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.dependency_members, current.dependency_members, mapDependencyMember); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.erased_declaration_references, current.erased_declaration_references, mapErased); if error != Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.request_loops, current.request_loops) { return false, Error.none; }
    if !blot_structural::equal(old.request_arms, current.request_arms) { return false, Error.none; }
    if !blot_structural::equal(old.tag_calls, current.tag_calls) { return false, Error.none; }
    { let equal, error = self.mappedEqual(old.nodes, current.nodes, mapNode); if error != Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.spans, current.spans) { return false, Error.none; }
    if !blot_structural::equal(old.extra, current.extra) { return false, Error.none; }
    { let equal, error = self.mappedEqual(old.bindings, current.bindings, mapBinding); if error != Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.bodies, current.bodies) { return false, Error.none; }
    if !blot_structural::equal(old.parameters, current.parameters) { return false, Error.none; }
    { let equal, error = self.mappedEqual(old.references, current.references, mapReference); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.calls, current.calls, mapCall); if error != Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.merges, current.merges) { return false, Error.none; }
    if !blot_structural::equal(old.merge_ranges, current.merge_ranges) { return false, Error.none; }
    if !blot_structural::equal(old.names, current.names) { return false, Error.none; }
    { let equal, error = self.mappedEqual(old.obligations, current.obligations, mapObligation); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.nominals, current.nominals, mapNominal); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.operation_names, current.operation_names, mapOperationName); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.constructors, current.constructors, mapConstructor); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.projections, current.projections, mapProjection); if error != Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.projection_variants, current.projection_variants) { return false, Error.none; }
    if !blot_structural::equal(old.patterns, current.patterns) { return false, Error.none; }
    if !blot_structural::equal(old.pattern_rows, current.pattern_rows) { return false, Error.none; }
    if !blot_structural::equal(old.match_arms, current.match_arms) { return false, Error.none; }
    if !blot_structural::equal(old.matches, current.matches) { return false, Error.none; }
    if !blot_structural::equal(old.updates, current.updates) { return false, Error.none; }
    if !blot_structural::equal(old.update_steps, current.update_steps) { return false, Error.none; }
    if !blot_structural::equal(old.closures, current.closures) { return false, Error.none; }
    { let equal, error = self.mappedEqual(old.associated, current.associated, mapAssociated); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.contracts, current.contracts, mapContract); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.contract_members, current.contract_members, mapContractMember); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.implementations, current.implementations, mapImplementation); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.implementation_members, current.implementation_members, mapImplementationMember); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.member_templates, current.member_templates, mapMemberTemplate); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.selected_proofs, current.selected_proofs, mapSelectedProof); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.selected_members, current.selected_members, mapImplementationMember); if error != Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.selected_edges, current.selected_edges) { return false, Error.none; }
    if !blot_structural::equal(old.selected_uses, current.selected_uses) { return false, Error.none; }
    if !blot_structural::equal(old.dictionary_selections, current.dictionary_selections) { return false, Error.none; }
    if !blot_structural::equal(old.dictionary_uses, current.dictionary_uses) { return false, Error.none; }
    if !blot_structural::equal(old.primitives, current.primitives) { return false, Error.none; }
    if !blot_structural::equal(old.loops, current.loops) { return false, Error.none; }
    if !blot_structural::equal(old.loop_carries, current.loop_carries) { return false, Error.none; }
    { let equal, error = self.mappedEqual(old.resolver_ops, current.resolver_ops, mapResolver); if error != Error.none || !equal { return false, error; } }
    { let equal, error = self.mappedEqual(old.operation_values, current.operation_values, mapOperationValue); if error != Error.none || !equal { return false, error; } }
    if !blot_structural::equal(old.handle_effects, current.handle_effects) { return false, Error.none; }
    if !blot_structural::equal(old.dispatch_signatures, current.dispatch_signatures) { return false, Error.none; }
    if !blot_structural::equal(old.diagnostics, current.diagnostics) { return false, Error.none; }
    if !blot_structural::equal(old.body_lowerings, current.body_lowerings) { return false, Error.none; }
    return true, Error.none;
}
