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
        if error != blot_error::Error.none { return error; } admission = blot_support::some(gate);
    }
    result = State { allocation_owner: allocation_owner, old: old, gate: admission.value, names: names, stats: Stats {
        dependency_validations: admission.value.dependency_validations,
        reused_dependency_validations: admission.value.reused_dependency_validations,
        projection_scans: admission.value.projection_scans, projection_visits: admission.value.projection_visits,
        projection_workspace_peak_bytes: admission.value.projection_workspace_peak_bytes,
     ..} , ..};
    return blot_error::Error.none;
}
fn deinit(self_: State&) {
    if self_.imported_inputs.present { self_.imported_inputs.value.deinit(); self_.imported_inputs.present = false; }
    if self_.graphs.present { self_.graphs.value.deinit(); self_.graphs.present = false; }
    self_.gate.deinit(); self_.last_inputs .= null; self_.old .= null;
}
fn ensureGraphs(self_: State&) -> bool, Error {
    if self_.graphs.present { return self_.graphs.value.enabled, blot_error::Error.none; }
    if !self_.gate.enabled { return false, blot_error::Error.none; } assert(self_.old);
    let prepared, error = blot_reuse_artifact_import::initCheckedQuery(self_.allocation_owner, self_.old.metadata.pools.value, self_.gate.units, self_.gate);
    if error != blot_error::Error.none { return false, error; }
    var graphs = prepared;
    if !graphs.present {
        let fresh, failure = blot_reuse_artifact_import::init(self_.allocation_owner, self_.old.metadata.pools.value, self_.gate.units, self_.names, self_.gate.units.len);
        if failure != blot_error::Error.none { return false, failure; } graphs = blot_support::some(fresh);
    }
    if !graphs.value.enabled { graphs.value.deinit(); return false, blot_error::Error.none; }
    for &stable, index in graphs.value.stable { stable = self_.gate.structural_units[index]; }
    self_.graphs = graphs; self_.stats.graph_importers_initialized++;
    if prepared.present { self_.stats.graph_importers_prepared++; }
    return true, blot_error::Error.none;
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
fn primitiveEvidence<G>(self_: const State&, g: G&, owner: u32, types: const blot_eval_type_evidence::Mapping[:], rows: const blot_eval_type_evidence::RowMapping[:]) -> PrimitiveResult, Error {
    if rows.len != 0 || types.len == 0 { return PrimitiveResult.fallback, blot_error::Error.none; }
    if !blot_support::same_slice_identity(g.evaluator.units, self_.gate.units) { return PrimitiveResult.declined, blot_error::Error.none; }
    assert(self_.old); let pools .= self_.old.metadata.pools.value;
    if owner == 0 || owner > pools.modules.len || owner > self_.gate.units.len { return PrimitiveResult.declined, blot_error::Error.none; }
    let pin = pools.modules[owner - 1];
    if pin.unit != owner || !self_.gate.structural_units[owner - 1] { return PrimitiveResult.declined, blot_error::Error.none; }
    let previous .= pin.module; let current .= self_.gate.units[owner - 1];
    for mapping, index in types {
        if mapping.variable == 0 || mapping.variable >= previous.types.nodes.len || mapping.variable >= current.types.nodes.len || previous.types.nodes[mapping.variable].tag != blot_check_types::Tag.variable || current.types.nodes[mapping.variable].tag != blot_check_types::Tag.variable || previous.types.nodes[mapping.variable] != current.types.nodes[mapping.variable] { return PrimitiveResult.declined, blot_error::Error.none; }
        for prior in types[..index] { if prior.variable == mapping.variable { return PrimitiveResult.declined, blot_error::Error.none; } }
    }
    let old_view = pools.evaluator.evidence.view(); let current_view = g.evaluator.storage.evidence.view();
    if !canonicalPrefix(old_view) || !canonicalPrefix(current_view) || !sourceU32(previous) || !sourceU32(current) { return PrimitiveResult.fallback, blot_error::Error.none; }
    for mapping in types { if mapping.evidence != blot_check_types::u32_type { return PrimitiveResult.fallback, blot_error::Error.none; } }
    let current_u32, error = g.evaluator.storage.evidence.intern(blot_eval_type_evidence::Tag.unsigned32, 0, 0, []);
    if error == blot_error::Error.out_of_memory { return PrimitiveResult.fallback, error; }
    if error != blot_error::Error.none || current_u32 >= current_view.nodes.len || current_view.nodes[current_u32] != (blot_eval_type_evidence::Node { blot_eval_type_evidence::Tag.unsigned32 , ..}) { return PrimitiveResult.fallback, blot_error::Error.none; }
    let copied = blot_eval_core_eval::copySolvedTypes(types);
    for &mapping in copied { mapping.evidence = current_u32; }
    return PrimitiveResult.solved { SolvedEvidence { copied, [] } , ..}, blot_error::Error.none;
}
fn inputImageEqual(self_: State&) -> bool {
    if self_.input_image_equal.present { return self_.input_image_equal.value; }
    self_.stats.input_image_checks++; assert(self_.old);
    for &current, index in self_.gate.units {
        if !blot_reuse_principal_input_image::moduleEqual(self_.old.metadata.pools.value.modules[index].module, current) { self_.input_image_equal = blot_support::some(false); return false; }
    }
    self_.input_image_equal = blot_support::some(true); return true;
}
fn sourceDeclined(self_: State&, detail: SourceDecline) -> bool {
    for &slot in self_.stats.source_declines {
        if slot.target == detail.target { return false; }
        if slot.reason != SourceReason.none { continue; }
        slot = detail;
        if detail.reason == SourceReason.identity { slot.identity_failure = self_.gate.callIdentityFailure(detail.source); }
        if detail.source.unit != 0 && detail.source.unit <= self_.gate.units.len {
            let module .= self_.gate.units[detail.source.unit - 1];
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
fn sourceReason(self_: const State&, source: BindingRef) -> SourceReason {
    if self_.gate.admitsCallIdentity(source) { return SourceReason.changed_source; }
    return SourceReason.identity;
}
fn sourcesEqual(self_: State&, target: BindingRef, inputs: const Inputs&) -> bool, Error {
    if !self_.gate.enabled { return self_.sourceDeclined(SourceDecline { target: target, reason: SourceReason.disabled , ..}), blot_error::Error.none; }
    if self_.gate.constant_types { return self_.sourceDeclined(SourceDecline { target: target, reason: SourceReason.constant_types , ..}), blot_error::Error.none; }
    if !inputs.source_complete { return self_.sourceDeclined(SourceDecline { target: target, reason: SourceReason.incomplete , ..}), blot_error::Error.none; }
    assert(self_.old);
    for unit in inputs.source_units {
        if unit == 0 || unit > self_.gate.units.len || !blot_reuse_principal_input_image::moduleEqual(self_.old.metadata.pools.value.modules[unit - 1].module, self_.gate.units[unit - 1]) { return self_.sourceDeclined(SourceDecline { target: target, source: BindingRef { unit, 0 , ..}, reason: SourceReason.module_image , ..}), blot_error::Error.none; }
    }
    for source in inputs.interfaces {
        let admitted, error = self_.gate.admitsCompletedInterface(source); if error != blot_error::Error.none { return false, error; }
        if !admitted {        let __field_order_478_target: blot_reuse_principal_evidence_reuse::BindingRef = target; let __field_order_479_source: blot_reuse_principal_evidence_reuse::BindingRef = source; let __field_order_480_interface_observation: bool = true; let __field_order_481_reason: blot_reuse_principal_evidence_reuse::SourceReason = self_.sourceReason(source); return self_.sourceDeclined(SourceDecline { target: __field_order_478_target, source: __field_order_479_source, reason: __field_order_481_reason, interface_observation: __field_order_480_interface_observation, .. }), blot_error::Error.none; }
    }
    var root = false;
    for source in inputs.sources {
        if !self_.gate.admitsLocalSource(source) { return self_.sourceDeclined(SourceDecline { target: target, source: source, reason: self_.sourceReason(source) , ..}), blot_error::Error.none; }
        root = root || source == target;
    }
    if root { return true, blot_error::Error.none; }
    return self_.sourceDeclined(SourceDecline { target: target, reason: SourceReason.missing_root , ..}), blot_error::Error.none;
}
fn currentInputs<G>(self_: State&, g: G&, target: BindingRef, inputs: const Inputs&) -> const Inputs?, Error {
    if inputs.call_publications.len == 0 && inputs.call_reads.len == 0 && inputs.summary_reads.len == 0 && inputs.summary_publications.len == 0 { return inputs, blot_error::Error.none; }
    if !self_.inputImageEqual() {
        let source_matches, error = self_.sourcesEqual(target, inputs); if error != blot_error::Error.none { return null, error; }
        if !source_matches { return null, blot_error::Error.none; }
    }
    let ready, error = self_.ensureGraphs(); if error != blot_error::Error.none { return null, error; }
    if !ready { return null, blot_error::Error.none; }
    for &stable in self_.graphs.value.stable { stable = true; }
    var translated, clone_error = inputs.clone(); if clone_error != blot_error::Error.none { return null, clone_error; }
    let admitted, failure = self_.translateInputs(g, translated);
    if failure != blot_error::Error.none || !admitted { translated.deinit(); return null, failure; }
    self_.imported_inputs = blot_support::some(translated);
    return self_.imported_inputs.value, blot_error::Error.none;
}
fn translateInputs<G>(self_: State&, g: G&, translated: Inputs&) -> bool, Error {
    assert(self_.graphs.present); let graphs .= self_.graphs.value;
    for &read in translated.call_reads {
        let actual, error = graphs.importPrincipalCall(g, read.target, read.evidence);
        if error != blot_error::Error.none || !actual.present { return false, error; } read.evidence = actual.value;
    }
    for &read in translated.summary_reads {
        let inputs, error = graphs.importPrincipalInput(g, read.key.inputs);
        if error != blot_error::Error.none || !inputs.present { return false, error; } read.key.inputs = inputs.value;
        let result, failure = graphs.importPrincipalCall(g, read.key.target, read.result);
        if failure != blot_error::Error.none || !result.present { return false, failure; } read.result = result.value;
    }
    if !translated.matches(g.evaluator) { return false, blot_error::Error.none; }
    var kept: i64 = 0;
    for call in translated.call_publications {
        let actual, error = graphs.importPrincipalCall(g, call.target, call.evidence);
        if error != blot_error::Error.none { return false, error; }
        if !actual.present { self_.stats.call_publications_declined++; continue; }
        translated.call_publications[kept] = blot_reuse_principal_inputs::CallPublication { call.target, actual.value , ..}; kept++;
    }
    translated.shrinkCallPublications(kept); kept = 0;
    for summary in translated.summary_publications {
        let actual_inputs, error = graphs.importPrincipalInput(g, summary.key.inputs);
        if error != blot_error::Error.none { return false, error; }
        if !actual_inputs.present { self_.stats.summary_publications_declined++; continue; }
        let result, failure = graphs.importPrincipalCall(g, summary.key.target, summary.result);
        if failure != blot_error::Error.none { return false, failure; }
        if !result.present { self_.stats.summary_publications_declined++; continue; }
        translated.summary_publications[kept] = blot_reuse_principal_inputs::Summary { blot_reuse_principal_inputs::SummaryKey { summary.key.target, actual_inputs.value, summary.key.deferred_member }, result.value , ..}; kept++;
    }
    translated.shrinkSummaryPublications(kept); return true, blot_error::Error.none;
}
fn publishInputs<G>(self_: State&, g: G&, inputs: const Inputs&) -> Error {
    let error = inputs.publish(g.evaluator); if error != blot_error::Error.none { return error; }
    self_.last_inputs .= inputs;
    self_.stats.call_publications_replayed += inputs.call_publications.len;
    self_.stats.summary_publications_replayed += inputs.summary_publications.len;
    return blot_error::Error.none;
}
fn lookup<G>(self_: State&, g: G&, target: BindingRef, options: blot_eval_core_eval::Options) -> blot_support::Option<SolvedEvidence>, Error {
    self_.last_inputs .= null;
    if self_.imported_inputs.present { self_.imported_inputs.value.deinit(); self_.imported_inputs.present = false; }
    self_.stats.requests++;
    let no = blot_support::none<SolvedEvidence>();
    if target.unit == 0 || target.unit > self_.gate.units.len || target.binding == 0 || target.binding >= self_.gate.units[target.unit - 1].bindings.len { self_.stats.changed_or_unsupported++; return no, blot_error::Error.none; }
    assert(self_.old);
    if target.unit > self_.old.cached_units { self_.stats.fresh_unit_requests++; }
    let exact = self_.gate.admitsPrincipal(target);
    if !exact && !self_.gate.enabled { self_.stats.changed_or_unsupported++; return no, blot_error::Error.none; }
    let table .= self_.old.metadata.principal_queries;
    var cursor = table.candidates(blot_reuse_principal_query::fingerprint(target), blot_reuse_semantic_query_table::Order.oldest_first);
    loop {
        let position = cursor.next(); if !position.present { break; }
        let proof: const blot_reuse_principal_query::Record& = table.records[position.value];
        if proof.key.target != target { continue; }
        if proof.key.options != options { self_.stats.options_declined++; return no, blot_error::Error.none; }
        let empty = proof.value.types.len == 0 && proof.value.rows.len == 0;
        if !exact { return self_.projectedLookup(g, target, proof, empty); }
        if !empty { self_.stats.nonempty_requests++; }
        var solved = SolvedEvidence { [], [] , ..};
        if !empty {
            let primitive, error = self_.primitiveEvidence(g, target.unit, proof.value.types, proof.value.rows);
            if error != blot_error::Error.none { return no, error; }
            var fallback = false;
            match primitive {
                solved facts => { self_.stats.primitive_hits++; solved = facts.value; },
                declined => { self_.stats.primitive_key_declined++; self_.stats.evidence_declined++; return no, blot_error::Error.none; },
                fallback => { self_.stats.primitive_fallbacks++; fallback = true; },
            }
            if fallback {
                let ready, failure = self_.ensureGraphs(); if failure != blot_error::Error.none { return no, failure; }
                if !ready { self_.stats.evidence_declined++; return no, blot_error::Error.none; }
                let imported, invalid = self_.graphs.value.importPrincipalEvidence(g, target.unit, proof.value.types, proof.value.rows);
                if invalid != blot_error::Error.none { return no, invalid; }
                if !imported.present { self_.stats.evidence_declined++; return no, blot_error::Error.none; }
                solved = imported.value;
            }
        }
        let replay_error = self_.replayExactInputs(g, target, proof);
        if replay_error != blot_error::Error.none { solved.deinit(); return no, replay_error; }
        if empty { self_.stats.empty_hits++; }
        self_.stats.hits++; if target.unit > self_.old.cached_units { self_.stats.fresh_unit_hits++; }
        return blot_support::some(solved), blot_error::Error.none;
    }
    self_.stats.missing++; return no, blot_error::Error.none;
}
fn replayExactInputs<G>(self_: State&, g: G&, target: BindingRef, proof: const blot_reuse_principal_query::Record&) -> Error {
    if !proof.dependencies.inputs.present { return blot_error::Error.none; }
    let inputs .= proof.dependencies.inputs.value;
    if !inputs.matchesBase(g.evaluator) { return blot_error::Error.none; }
    let current, error = self_.currentInputs(g, target, inputs); if error != blot_error::Error.none { return error; }
    if current { return self_.publishInputs(g, current); }
    return blot_error::Error.none;
}
fn projectedLookup<G>(self_: State&, g: G&, target: BindingRef, proof: const blot_reuse_principal_query::Record&, empty: bool) -> blot_support::Option<SolvedEvidence>, Error {
    let no = blot_support::none<SolvedEvidence>();
    if !blot_support::same_slice_identity(g.evaluator.units, self_.gate.units) { self_.stats.projected_owner_declines++; self_.stats.projected_empty_declines++; return no, blot_error::Error.none; }
    if !proof.dependencies.inputs.present { self_.stats.projected_unrecorded_declines++; self_.stats.projected_empty_declines++; return no, blot_error::Error.none; }
    let inputs .= proof.dependencies.inputs.value;
    if !inputs.matchesBase(g.evaluator) { self_.stats.projected_input_declines++; self_.stats.projected_empty_declines++; return no, blot_error::Error.none; }
    let complete_image = self_.inputImageEqual();
    if !complete_image {
        let equal, error = self_.sourcesEqual(target, inputs); if error != blot_error::Error.none { return no, error; }
        if !equal { self_.stats.projected_image_declines++; self_.stats.projected_empty_declines++; return no, blot_error::Error.none; }
    }
    let current, error = self_.currentInputs(g, target, inputs); if error != blot_error::Error.none { return no, error; }
    if !current { self_.stats.projected_import_declines++; self_.stats.projected_empty_declines++; return no, blot_error::Error.none; }
    var solved = SolvedEvidence { [], [] , ..};
    if !empty {
        let ready, failure = self_.ensureGraphs(); if failure != blot_error::Error.none { return no, failure; }
        if !ready { self_.stats.projected_result_declines++; self_.stats.projected_empty_declines++; return no, blot_error::Error.none; }
        for &stable in self_.graphs.value.stable { stable = true; }
        let imported, invalid = self_.graphs.value.importPrincipalEvidence(g, target.unit, proof.value.types, proof.value.rows);
        if invalid != blot_error::Error.none { return no, invalid; }
        if !imported.present { self_.stats.projected_result_declines++; self_.stats.projected_empty_declines++; return no, blot_error::Error.none; }
        solved = imported.value;
    }
    let published = self_.publishInputs(g, current);
    if published != blot_error::Error.none { solved.deinit(); return no, published; }
    if empty { self_.stats.projected_empty_hits++; self_.stats.empty_hits++; }
    else { self_.stats.projected_nonempty_hits++; }
    if !complete_image { self_.stats.projected_source_hits++; }
    self_.stats.hits++; assert(self_.old);
    if target.unit > self_.old.cached_units { self_.stats.fresh_unit_hits++; }
    return blot_support::some(solved), blot_error::Error.none;
}

fn sourceReasonName(value: SourceReason) -> const u8[:] { match value {
    none => "none",
    disabled => "disabled",
    constant_types => "constant_types",
    incomplete => "incomplete",
    identity => "identity",
    changed_source => "changed_source",
    module_image => "module_image",
    missing_root => "missing_root",
} }
fn identityFailureName(value: blot_reuse_principal_reuse_gate::IdentityFailure) -> const u8[:] { match value {
    none => "none",
    disabled => "disabled",
    bounds => "bounds",
    kind => "kind",
    binding_type => "binding_type",
    source_position => "source_position",
    declaration_origin => "declaration_origin",
    body => "body",
    scheme_root => "scheme_root",
    scheme => "scheme",
    flags => "flags",
} }
fn jsonStringify(self_: SourceDecline, writer: blot_json::Writer&) -> Error {
    { let propagated_error = writer.beginObject(); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = writer.field("target", self_.target); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = writer.field("source", self_.source); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = writer.field("reason", sourceReasonName(self_.reason)); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = writer.field("identity_failure", identityFailureName(self_.identity_failure)); if propagated_error != blot_error::Error.none { return propagated_error; } }
    var length: i64 = 0; while length < self_.source_name_utf8.len && self_.source_name_utf8[length] != 0 { length++; }
    { let propagated_error = writer.field("source_name", self_.source_name_utf8[..length]); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = writer.field("source_name_truncated", self_.source_name_truncated); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = writer.field("source_point", self_.source_point); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = writer.field("interface_observation", self_.interface_observation); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = writer.field("binding_requirements", self_.binding_requirements); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = writer.field("body_requirements", self_.body_requirements); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = writer.field("inferred_requirements", self_.inferred_requirements); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = writer.field("callee_requirements", self_.callee_requirements); if propagated_error != blot_error::Error.none { return propagated_error; } }
    return writer.endObject();
}
