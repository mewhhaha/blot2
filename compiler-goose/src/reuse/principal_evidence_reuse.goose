// Principal facts have a separate source/input gate from executable artifacts.
namespace blot_reuse_principal_evidence_reuse;
import check.core;
import check.check;
import check.types;
import eval.core_eval;
import eval.type_evidence;
import reuse.artifact_capture;
import reuse.artifact_import;
import reuse.code_artifacts;
import reuse.principal_reuse_gate;
import reuse.principal_query;
import reuse.principal_inputs;
import reuse.principal_input_image;
import reuse.semantic_query_table;
import reuse.declaration_origins;
import backend.runtime_identity;
import support.error;
import support.option;
import support.json;
type Error = blot_error::Error;
type BindingRef = blot_check_core::BindingRef;
type SolvedEvidence = blot_eval_core_eval::SolvedEvidence;
type Inputs = blot_reuse_principal_inputs::Key;
type Gate = blot_reuse_principal_reuse_gate::Gate;
enum SourceReason { none, disabled, constant_types, incomplete, identity, changed_source, module_image, missing_root }
struct SourceDecline {
    target: BindingRef = BindingRef { 0, 0 , ..}, source: BindingRef = BindingRef { 0, 0 , ..}, reason: SourceReason = SourceReason.none,
    identity_failure: blot_reuse_principal_reuse_gate::IdentityFailure = blot_reuse_principal_reuse_gate::IdentityFailure.none,
    source_name_utf8: u8[96] = [0; 96], source_name_truncated: bool = false, source_point: u32 = 0,
    interface_observation: bool = false, binding_requirements: u32 = 0, inferred_requirements: u32 = 0, callee_requirements: u32 = 0, body_requirements: u32 = 0,
}
struct Stats {
    persisted_requests: i64 = 0,
    persisted_hits: i64 = 0,
    persisted_nonempty_hits: i64 = 0,
    persisted_call_proofs: i64 = 0,
    persisted_declines: i64 = 0,
    projected_empty_hits: i64 = 0,
    projected_nonempty_hits: i64 = 0,
    projected_source_hits: i64 = 0,
    projected_empty_declines: i64 = 0,
    projected_owner_declines: i64 = 0,
    projected_result_declines: i64 = 0,
    projected_unrecorded_declines: i64 = 0,
    projected_input_declines: i64 = 0,
    projected_image_declines: i64 = 0,
    projected_import_declines: i64 = 0,
    input_image_checks: i64 = 0,
    dependency_validations: i64 = 0,
    reused_dependency_validations: i64 = 0,
    projection_scans: i64 = 0,
    projection_visits: i64 = 0,
    projection_workspace_peak_bytes: i64 = 0,
    graph_importers_initialized: i64 = 0,
    graph_importers_prepared: i64 = 0,
    empty_hits: i64 = 0,
    primitive_hits: i64 = 0,
    primitive_fallbacks: i64 = 0,
    primitive_key_declined: i64 = 0,
    nonempty_requests: i64 = 0,
    requests: i64 = 0,
    fresh_unit_requests: i64 = 0,
    fresh_unit_hits: i64 = 0,
    hits: i64 = 0,
    changed_or_unsupported: i64 = 0,
    missing: i64 = 0,
    evidence_declined: i64 = 0,
    options_declined: i64 = 0,
    captured: i64 = 0,
    fresh_regions: i64 = 0,
    call_publications_replayed: i64 = 0,
    call_publications_declined: i64 = 0,
    summary_publications_replayed: i64 = 0,
    summary_publications_declined: i64 = 0,
    source_declines: SourceDecline[8] = [SourceDecline {..}; 8],
}
struct State {
    allocation_owner: u64 = 0, old: const blot_reuse_artifact_capture::Capture? = null,
    gate: Gate = Gate {..}, names: blot_support::Option<blot_backend_runtime_identity::View>,
    graphs: blot_support::Option<blot_reuse_artifact_import::Importer>, input_image_equal: blot_support::Option<bool>,
    last_inputs: const Inputs? = null, imported_inputs: blot_support::Option<Inputs>, stats: Stats = Stats {..},
}
enum PrimitiveResult { fallback, declined, solved { value: SolvedEvidence } }
fn init(allocation_owner: u64, old: const blot_reuse_artifact_capture::Capture&, units: const blot_check_core::Module[:], names: blot_support::Option<blot_backend_runtime_identity::View>, stamps: blot_reuse_code_artifacts::ModuleStamps?) -> State, Error {
    var result = State {..};
    let error = initInto(result, old, units, names, stamps, allocation_owner, blot_support::none<Gate>());
    return result, error;
}
fn initInto(result: State&, old: const blot_reuse_artifact_capture::Capture&, units: const blot_check_core::Module[:], names: blot_support::Option<blot_backend_runtime_identity::View>, stamps: blot_reuse_code_artifacts::ModuleStamps?, allocation_owner: u64, admitted: blot_support::Option<Gate>) -> Error {
    assert(old.metadata.pools.present);
    var admission = admitted;
    if !admission.present {
        let gate, error = blot_reuse_principal_reuse_gate::initWithStamps(allocation_owner, old.metadata.pools.value, units, names, stamps);
        if error != Error.none { return error; } admission = blot_support::some(gate);
    }
    result = State { allocation_owner: allocation_owner, old: old, gate: admission.value, names: names, stats: Stats {
        dependency_validations: admission.value.dependency_validations,
        reused_dependency_validations: admission.value.reused_dependency_validations,
        projection_scans: admission.value.projection_scans, projection_visits: admission.value.projection_visits,
        projection_workspace_peak_bytes: admission.value.projection_workspace_peak_bytes,
     ..} , ..};
    return Error.none;
}
fn deinit(self: State&) {
    if self.imported_inputs.present { self.imported_inputs.value.deinit(); self.imported_inputs.present = false; }
    if self.graphs.present { self.graphs.value.deinit(); self.graphs.present = false; }
    self.gate.deinit(); self.last_inputs .= null; self.old .= null;
}
fn ensureGraphs(self: State&) -> bool, Error {
    if self.graphs.present { return self.graphs.value.enabled, Error.none; }
    if !self.gate.enabled { return false, Error.none; } assert(self.old);
    let prepared, error = blot_reuse_artifact_import::initCheckedQuery(self.allocation_owner, self.old.metadata.pools.value, self.gate.units, self.gate);
    if error != Error.none { return false, error; }
    var graphs = prepared;
    if !graphs.present {
        let fresh, failure = blot_reuse_artifact_import::init(self.allocation_owner, self.old.metadata.pools.value, self.gate.units, self.names, self.gate.units.len);
        if failure != Error.none { return false, failure; } graphs = blot_support::some(fresh);
    }
    if !graphs.value.enabled { graphs.value.deinit(); return false, Error.none; }
    for &stable, index in graphs.value.stable { stable = self.gate.structural_units[index]; }
    self.graphs = graphs; self.stats.graph_importers_initialized++;
    if prepared.present { self.stats.graph_importers_prepared++; }
    return true, Error.none;
}
fn canonicalPrefix(view: blot_eval_type_evidence::View) -> bool {
    let tags = [blot_eval_type_evidence::Tag.absent, blot_eval_type_evidence::Tag.unit, blot_eval_type_evidence::Tag.boolean, blot_eval_type_evidence::Tag.unsigned32, blot_eval_type_evidence::Tag.floating32, blot_eval_type_evidence::Tag.never];
    if view.nodes.len < tags.len || view.effects.rows.len == 0 || view.effects.rows[0].start != 0 || view.effects.rows[0].len != 0 { return false; }
    for tag, index in tags { if view.nodes[index] != (blot_eval_type_evidence::Node { tag: tag , ..}) { return false; } }
    return true;
}
fn sourceU32(module: const blot_check_core::Module&) -> bool {
    if module.types.nodes.len <= blot_check_types::u32_type { return false; }
    let node = module.types.nodes[blot_check_types::u32_type];
    return node.tag == blot_check_types::Tag.unsigned32 && node.a == 0 && node.b == 0 && node.c == 0;
}
fn primitiveEvidence<G>(self: const State&, g: G&, owner: u32, types: const blot_eval_type_evidence::Mapping[:], rows: const blot_eval_type_evidence::RowMapping[:]) -> PrimitiveResult, Error {
    if rows.len != 0 || types.len == 0 { return PrimitiveResult.fallback, Error.none; }
    if !blot_support::same_slice_identity(g.evaluator.units, self.gate.units) { return PrimitiveResult.declined, Error.none; }
    assert(self.old); let pools .= self.old.metadata.pools.value;
    if owner == 0 || owner > pools.modules.len || owner > self.gate.units.len { return PrimitiveResult.declined, Error.none; }
    let pin = pools.modules[owner - 1];
    if pin.unit != owner || !self.gate.structural_units[owner - 1] { return PrimitiveResult.declined, Error.none; }
    let previous .= pin.module; let current .= self.gate.units[owner - 1];
    for mapping, index in types {
        if mapping.variable == 0 || mapping.variable >= previous.types.nodes.len || mapping.variable >= current.types.nodes.len || previous.types.nodes[mapping.variable].tag != blot_check_types::Tag.variable || current.types.nodes[mapping.variable].tag != blot_check_types::Tag.variable || previous.types.nodes[mapping.variable] != current.types.nodes[mapping.variable] { return PrimitiveResult.declined, Error.none; }
        for prior in types[..index] { if prior.variable == mapping.variable { return PrimitiveResult.declined, Error.none; } }
    }
    let old_view = pools.evaluator.evidence.view(); let current_view = g.evaluator.storage.evidence.view();
    if !canonicalPrefix(old_view) || !canonicalPrefix(current_view) || !sourceU32(previous) || !sourceU32(current) { return PrimitiveResult.fallback, Error.none; }
    for mapping in types { if mapping.evidence != blot_check_types::u32_type { return PrimitiveResult.fallback, Error.none; } }
    let current_u32, error = g.evaluator.storage.evidence.intern(blot_eval_type_evidence::Tag.unsigned32, 0, 0, []);
    if error == Error.out_of_memory { return PrimitiveResult.fallback, error; }
    if error != Error.none || current_u32 >= current_view.nodes.len || current_view.nodes[current_u32] != (blot_eval_type_evidence::Node { blot_eval_type_evidence::Tag.unsigned32 , ..}) { return PrimitiveResult.fallback, Error.none; }
    let copied = blot_eval_core_eval::copySolvedTypes(types);
    for &mapping in copied { mapping.evidence = current_u32; }
    return PrimitiveResult.solved { SolvedEvidence { copied, [] } , ..}, Error.none;
}
fn inputImageEqual(self: State&) -> bool {
    if self.input_image_equal.present { return self.input_image_equal.value; }
    self.stats.input_image_checks++; assert(self.old);
    for &current, index in self.gate.units {
        if !blot_reuse_principal_input_image::moduleEqual(self.old.metadata.pools.value.modules[index].module, current) { self.input_image_equal = blot_support::some(false); return false; }
    }
    self.input_image_equal = blot_support::some(true); return true;
}
fn sourceDeclined(self: State&, detail: SourceDecline) -> bool {
    for &slot in self.stats.source_declines {
        if slot.target == detail.target { return false; }
        if slot.reason != SourceReason.none { continue; }
        slot = detail;
        if detail.reason == SourceReason.identity { slot.identity_failure = self.gate.callIdentityFailure(detail.source); }
        if detail.source.unit != 0 && detail.source.unit <= self.gate.units.len {
            let module .= self.gate.units[detail.source.unit - 1];
            if detail.source.binding != 0 && detail.source.binding < module.bindings.len {
                slot.source_point = module.sourceNamePoint(detail.source.binding);
                let requirements = module.binding(detail.source.binding).scheme.obligations; slot.binding_requirements = requirements.len;
                for requirement in module.obligations[requirements.start..requirements.start + requirements.len] {
                    if requirement.kind == blot_check_types::ObligationKind.callee_use { slot.callee_requirements++; }
                    else if !requirement.explicit { slot.inferred_requirements++; }
                }
                let body = module.body(detail.source.binding);
                if body {
                    slot.body_requirements = body.scheme.obligations.len;
                    let name = blot_reuse_declaration_origins::name(module, body);
                    if name.present {
                        var length = min(name.value.len, slot.source_name_utf8.len);
                        while length != 0 && !blot_backend_runtime_identity::validUtf8(name.value[..length]) { length--; }
                        for byte, index in name.value[..length] { slot.source_name_utf8[index] = byte; }
                        slot.source_name_truncated = length != name.value.len;
                    }
                }
            }
        }
        break;
    }
    return false;
}
fn sourceReason(self: const State&, source: BindingRef) -> SourceReason {
    if self.gate.admitsCallIdentity(source) { return SourceReason.changed_source; }
    return SourceReason.identity;
}
fn sourcesEqual(self: State&, target: BindingRef, inputs: const Inputs&) -> bool, Error {
    if !self.gate.enabled { return self.sourceDeclined(SourceDecline { target: target, reason: SourceReason.disabled , ..}), Error.none; }
    if self.gate.constant_types { return self.sourceDeclined(SourceDecline { target: target, reason: SourceReason.constant_types , ..}), Error.none; }
    if !inputs.source_complete { return self.sourceDeclined(SourceDecline { target: target, reason: SourceReason.incomplete , ..}), Error.none; }
    assert(self.old);
    for unit in inputs.source_units {
        if unit == 0 || unit > self.gate.units.len || !blot_reuse_principal_input_image::moduleEqual(self.old.metadata.pools.value.modules[unit - 1].module, self.gate.units[unit - 1]) { return self.sourceDeclined(SourceDecline { target: target, source: BindingRef { unit, 0 , ..}, reason: SourceReason.module_image , ..}), Error.none; }
    }
    for source in inputs.interfaces {
        let admitted, error = self.gate.admitsCompletedInterface(source); if error != Error.none { return false, error; }
        if !admitted { return self.sourceDeclined(SourceDecline { target: target, source: source, interface_observation: true, reason: self.sourceReason(source) , ..}), Error.none; }
    }
    var root = false;
    for source in inputs.sources {
        if !self.gate.admitsLocalSource(source) { return self.sourceDeclined(SourceDecline { target: target, source: source, reason: self.sourceReason(source) , ..}), Error.none; }
        root = root || source == target;
    }
    if root { return true, Error.none; }
    return self.sourceDeclined(SourceDecline { target: target, reason: SourceReason.missing_root , ..}), Error.none;
}
fn currentInputs<G>(self: State&, g: G&, target: BindingRef, inputs: const Inputs&) -> const Inputs?, Error {
    if inputs.call_publications.len == 0 && inputs.call_reads.len == 0 && inputs.summary_reads.len == 0 && inputs.summary_publications.len == 0 { return inputs, Error.none; }
    if !self.inputImageEqual() {
        let source_matches, error = self.sourcesEqual(target, inputs); if error != Error.none { return null, error; }
        if !source_matches { return null, Error.none; }
    }
    let ready, error = self.ensureGraphs(); if error != Error.none { return null, error; }
    if !ready { return null, Error.none; }
    for &stable in self.graphs.value.stable { stable = true; }
    var translated, clone_error = inputs.clone(); if clone_error != Error.none { return null, clone_error; }
    let admitted, failure = self.translateInputs(g, translated);
    if failure != Error.none || !admitted { translated.deinit(); return null, failure; }
    self.imported_inputs = blot_support::some(translated);
    return self.imported_inputs.value, Error.none;
}
fn translateInputs<G>(self: State&, g: G&, translated: Inputs&) -> bool, Error {
    assert(self.graphs.present); let graphs .= self.graphs.value;
    for &read in translated.call_reads {
        let actual, error = graphs.importPrincipalCall(g, read.target, read.evidence);
        if error != Error.none || !actual.present { return false, error; } read.evidence = actual.value;
    }
    for &read in translated.summary_reads {
        let inputs, error = graphs.importPrincipalInput(g, read.key.inputs);
        if error != Error.none || !inputs.present { return false, error; } read.key.inputs = inputs.value;
        let result, failure = graphs.importPrincipalCall(g, read.key.target, read.result);
        if failure != Error.none || !result.present { return false, failure; } read.result = result.value;
    }
    if !translated.matches(g.evaluator) { return false, Error.none; }
    var kept: i64 = 0;
    for call in translated.call_publications {
        let actual, error = graphs.importPrincipalCall(g, call.target, call.evidence);
        if error != Error.none { return false, error; }
        if !actual.present { self.stats.call_publications_declined++; continue; }
        translated.call_publications[kept] = blot_reuse_principal_inputs::CallPublication { call.target, actual.value , ..}; kept++;
    }
    translated.shrinkCallPublications(kept); kept = 0;
    for summary in translated.summary_publications {
        let actual_inputs, error = graphs.importPrincipalInput(g, summary.key.inputs);
        if error != Error.none { return false, error; }
        if !actual_inputs.present { self.stats.summary_publications_declined++; continue; }
        let result, failure = graphs.importPrincipalCall(g, summary.key.target, summary.result);
        if failure != Error.none { return false, failure; }
        if !result.present { self.stats.summary_publications_declined++; continue; }
        translated.summary_publications[kept] = blot_reuse_principal_inputs::Summary { blot_reuse_principal_inputs::SummaryKey { summary.key.target, actual_inputs.value, summary.key.deferred_member }, result.value , ..}; kept++;
    }
    translated.shrinkSummaryPublications(kept); return true, Error.none;
}
fn publishInputs<G>(self: State&, g: G&, inputs: const Inputs&) -> Error {
    let error = inputs.publish(g.evaluator); if error != Error.none { return error; }
    self.last_inputs .= inputs;
    self.stats.call_publications_replayed += inputs.call_publications.len;
    self.stats.summary_publications_replayed += inputs.summary_publications.len;
    return Error.none;
}
fn lookup<G>(self: State&, g: G&, target: BindingRef, options: blot_eval_core_eval::Options) -> blot_support::Option<SolvedEvidence>, Error {
    self.last_inputs .= null;
    if self.imported_inputs.present { self.imported_inputs.value.deinit(); self.imported_inputs.present = false; }
    self.stats.requests++;
    let no = blot_support::none<SolvedEvidence>();
    if target.unit == 0 || target.unit > self.gate.units.len || target.binding == 0 || target.binding >= self.gate.units[target.unit - 1].bindings.len { self.stats.changed_or_unsupported++; return no, Error.none; }
    assert(self.old);
    if target.unit > self.old.cached_units { self.stats.fresh_unit_requests++; }
    let exact = self.gate.admitsPrincipal(target);
    if !exact && !self.gate.enabled { self.stats.changed_or_unsupported++; return no, Error.none; }
    let table .= self.old.metadata.principal_queries;
    var cursor = table.candidates(blot_reuse_principal_query::fingerprint(target), blot_reuse_semantic_query_table::Order.oldest_first);
    loop {
        let position = cursor.next(); if !position.present { break; }
        let proof: const blot_reuse_principal_query::Record& = table.records[position.value];
        if proof.key.target != target { continue; }
        if proof.key.options != options { self.stats.options_declined++; return no, Error.none; }
        let empty = proof.value.types.len == 0 && proof.value.rows.len == 0;
        if !exact { return self.projectedLookup(g, target, proof, empty); }
        if !empty { self.stats.nonempty_requests++; }
        var solved = SolvedEvidence { [], [] , ..};
        if !empty {
            let primitive, error = self.primitiveEvidence(g, target.unit, proof.value.types, proof.value.rows);
            if error != Error.none { return no, error; }
            var fallback = false;
            match primitive {
                PrimitiveResult.solved facts => { self.stats.primitive_hits++; solved = facts.value; },
                PrimitiveResult.declined => { self.stats.primitive_key_declined++; self.stats.evidence_declined++; return no, Error.none; },
                PrimitiveResult.fallback => { self.stats.primitive_fallbacks++; fallback = true; },
            }
            if fallback {
                let ready, failure = self.ensureGraphs(); if failure != Error.none { return no, failure; }
                if !ready { self.stats.evidence_declined++; return no, Error.none; }
                let imported, invalid = self.graphs.value.importPrincipalEvidence(g, target.unit, proof.value.types, proof.value.rows);
                if invalid != Error.none { return no, invalid; }
                if !imported.present { self.stats.evidence_declined++; return no, Error.none; }
                solved = imported.value;
            }
        }
        let replay_error = self.replayExactInputs(g, target, proof);
        if replay_error != Error.none { solved.deinit(); return no, replay_error; }
        if empty { self.stats.empty_hits++; }
        self.stats.hits++; if target.unit > self.old.cached_units { self.stats.fresh_unit_hits++; }
        return blot_support::some(solved), Error.none;
    }
    self.stats.missing++; return no, Error.none;
}
fn replayExactInputs<G>(self: State&, g: G&, target: BindingRef, proof: const blot_reuse_principal_query::Record&) -> Error {
    if !proof.dependencies.inputs.present { return Error.none; }
    let inputs .= proof.dependencies.inputs.value;
    if !inputs.matchesBase(g.evaluator) { return Error.none; }
    let current, error = self.currentInputs(g, target, inputs); if error != Error.none { return error; }
    if current { return self.publishInputs(g, current); }
    return Error.none;
}
fn projectedLookup<G>(self: State&, g: G&, target: BindingRef, proof: const blot_reuse_principal_query::Record&, empty: bool) -> blot_support::Option<SolvedEvidence>, Error {
    let no = blot_support::none<SolvedEvidence>();
    if !blot_support::same_slice_identity(g.evaluator.units, self.gate.units) { self.stats.projected_owner_declines++; self.stats.projected_empty_declines++; return no, Error.none; }
    if !proof.dependencies.inputs.present { self.stats.projected_unrecorded_declines++; self.stats.projected_empty_declines++; return no, Error.none; }
    let inputs .= proof.dependencies.inputs.value;
    if !inputs.matchesBase(g.evaluator) { self.stats.projected_input_declines++; self.stats.projected_empty_declines++; return no, Error.none; }
    let complete_image = self.inputImageEqual();
    if !complete_image {
        let equal, error = self.sourcesEqual(target, inputs); if error != Error.none { return no, error; }
        if !equal { self.stats.projected_image_declines++; self.stats.projected_empty_declines++; return no, Error.none; }
    }
    let current, error = self.currentInputs(g, target, inputs); if error != Error.none { return no, error; }
    if !current { self.stats.projected_import_declines++; self.stats.projected_empty_declines++; return no, Error.none; }
    var solved = SolvedEvidence { [], [] , ..};
    if !empty {
        let ready, failure = self.ensureGraphs(); if failure != Error.none { return no, failure; }
        if !ready { self.stats.projected_result_declines++; self.stats.projected_empty_declines++; return no, Error.none; }
        for &stable in self.graphs.value.stable { stable = true; }
        let imported, invalid = self.graphs.value.importPrincipalEvidence(g, target.unit, proof.value.types, proof.value.rows);
        if invalid != Error.none { return no, invalid; }
        if !imported.present { self.stats.projected_result_declines++; self.stats.projected_empty_declines++; return no, Error.none; }
        solved = imported.value;
    }
    let published = self.publishInputs(g, current);
    if published != Error.none { solved.deinit(); return no, published; }
    if empty { self.stats.projected_empty_hits++; self.stats.empty_hits++; }
    else { self.stats.projected_nonempty_hits++; }
    if !complete_image { self.stats.projected_source_hits++; }
    self.stats.hits++; assert(self.old);
    if target.unit > self.old.cached_units { self.stats.fresh_unit_hits++; }
    return blot_support::some(solved), Error.none;
}

fn sourceReasonName(value: SourceReason) -> const u8[:] { match value {
    SourceReason.none => "none",
    SourceReason.disabled => "disabled",
    SourceReason.constant_types => "constant_types",
    SourceReason.incomplete => "incomplete",
    SourceReason.identity => "identity",
    SourceReason.changed_source => "changed_source",
    SourceReason.module_image => "module_image",
    SourceReason.missing_root => "missing_root",
} }
fn identityFailureName(value: blot_reuse_principal_reuse_gate::IdentityFailure) -> const u8[:] { match value {
    blot_reuse_principal_reuse_gate::IdentityFailure.none => "none",
    blot_reuse_principal_reuse_gate::IdentityFailure.disabled => "disabled",
    blot_reuse_principal_reuse_gate::IdentityFailure.bounds => "bounds",
    blot_reuse_principal_reuse_gate::IdentityFailure.kind => "kind",
    blot_reuse_principal_reuse_gate::IdentityFailure.binding_type => "binding_type",
    blot_reuse_principal_reuse_gate::IdentityFailure.source_position => "source_position",
    blot_reuse_principal_reuse_gate::IdentityFailure.declaration_origin => "declaration_origin",
    blot_reuse_principal_reuse_gate::IdentityFailure.body => "body",
    blot_reuse_principal_reuse_gate::IdentityFailure.scheme_root => "scheme_root",
    blot_reuse_principal_reuse_gate::IdentityFailure.scheme => "scheme",
    blot_reuse_principal_reuse_gate::IdentityFailure.flags => "flags",
} }
fn jsonStringify(self: SourceDecline, writer: blot_json::Writer&) -> Error {
    { let propagated_error = writer.beginObject(); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = writer.field("target", self.target); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = writer.field("source", self.source); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = writer.field("reason", sourceReasonName(self.reason)); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = writer.field("identity_failure", identityFailureName(self.identity_failure)); if propagated_error != Error.none { return propagated_error; } }
    var length: i64 = 0; while length < self.source_name_utf8.len && self.source_name_utf8[length] != 0 { length++; }
    { let propagated_error = writer.field("source_name", self.source_name_utf8[..length]); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = writer.field("source_name_truncated", self.source_name_truncated); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = writer.field("source_point", self.source_point); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = writer.field("interface_observation", self.interface_observation); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = writer.field("binding_requirements", self.binding_requirements); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = writer.field("body_requirements", self.body_requirements); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = writer.field("inferred_requirements", self.inferred_requirements); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = writer.field("callee_requirements", self.callee_requirements); if propagated_error != Error.none { return propagated_error; } }
    return writer.endObject();
}
