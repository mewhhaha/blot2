// Private closed-call judgments; only the outer query publishes their result.
namespace blot_reuse_independent_call_proof;
import std;
import check.core;
import eval.core_eval;
import backend.layout;
import reuse.artifact_import;
import reuse.code_artifacts;
import reuse.specialization_receipt;
import reuse.refinement_receipt;
import support.error;
import support.option;
import support.structural;
type Error = blot_error::Error;
type BindingRef = blot_check_core::BindingRef;
enum DeclineReason { inputs, imports, query, proof, diagnostic, unknown, nested, views, regions, incomplete, steps, values, calls, scalar, source }
fn reasonCode(value: DeclineReason) -> i64 { match value { inputs => 0, imports => 1, query => 2, proof => 3, diagnostic => 4, unknown => 5, nested => 6, views => 7, regions => 8, incomplete => 9, steps => 10, values => 11, calls => 12, scalar => 13, source => 14 } }
struct ScalarInput { target: BindingRef, evidence: u32, value: blot_support::Option<blot_eval_core_eval::Value> }
struct Record {
    target: BindingRef, evidence: u32, options: blot_eval_core_eval::Options, depth: i64,
    sources: BindingRef[:] = default<BindingRef[:]>(), scalar_reads: ScalarInput[:] = default<ScalarInput[:]>(),
}
reusable[] var proof_sources: BindingRef[>..] = [];
reusable[] var proof_scalars: ScalarInput[>..] = [];
fn copySources(source: const BindingRef[:]) -> BindingRef[:] { if source.len == 0 { return default<BindingRef[:]>(); } let out = proof_sources.alloc_slice(source.len); for value, index in source { out[index] = value; } return out; }
fn copyScalars(source: const ScalarInput[:]) -> ScalarInput[:] { if source.len == 0 { return default<ScalarInput[:]>(); } let out = proof_scalars.alloc_slice(source.len); for value, index in source { out[index] = value; } return out; }
fn releaseSources(source: const BindingRef[:]) { if source.len != 0 { proof_sources.free_slice(source); } }
fn releaseScalars(source: const ScalarInput[:]) { if source.len != 0 { proof_scalars.free_slice(source); } }
fn deinit(self_: Record&) { releaseSources(self_.sources); releaseScalars(self_.scalar_reads); self_.sources = default<BindingRef[:]>(); self_.scalar_reads = default<ScalarInput[:]>(); }
fn clone(self_: Record) -> Record, Error { var result = self_; result.sources = copySources(self_.sources); result.scalar_reads = copyScalars(self_.scalar_reads); return result, blot_error::Error.none; }
// The record owns these runs until transfer or deinit.
fn ownedSources(values:const BindingRef[:])->BindingRef[:] {
 if values.len==0 {return default<BindingRef[:]>();}let registered=proof_sources.realloc_slice(values,values.len);assert(blot_support::same_slice_identity(registered,values));let start=proof_sources.index_of(registered[0]);return proof_sources[start..start+values.len];
}
fn ownedScalars(values:const ScalarInput[:])->ScalarInput[:] {
 if values.len==0 {return default<ScalarInput[:]>();}let registered=proof_scalars.realloc_slice(values,values.len);assert(blot_support::same_slice_identity(registered,values));let start=proof_scalars.index_of(registered[0]);return proof_scalars[start..start+values.len];
}
fn canonicalOwned(source:Record)->Record {return Record{target:source.target,evidence:source.evidence,options:source.options,depth:source.depth,sources:ownedSources(source.sources),scalar_reads:ownedScalars(source.scalar_reads)};}
fn canonicalOwned(source:blot_support::Option<Record>)->blot_support::Option<Record> {
 if source.present {return blot_support::Option<Record>{true,canonicalOwned(source.value)};}
 return blot_support::none<Record>();
}
fn reject<S>(state: S&, reason: DeclineReason) -> blot_support::Option<Record> { state.stats.independent_rejections[reasonCode(reason)]++; return blot_support::none<Record>(); }
fn scalarInput<G>(g: const G&, target: BindingRef) -> blot_support::Option<ScalarInput> {
    let no = blot_support::none<ScalarInput>();
    if target.unit == 0 || target.unit > g.evaluator.units.len { return no; } let module = g.evaluator.units[target.unit - 1];
    if target.binding >= module.bindings.len { return no; } let body .= module.body(target.binding); if !body { return no; }
    let slot = g.evaluator.slots[g.evaluator.binding_offsets[target.unit - 1] + target.binding]; var actual: u32 = 0;
    if !body.runtime && slot.state == blot_eval_core_eval::State.complete && g.evaluator.valueInfo(slot.value).kind == blot_eval_eval_values::ValueKind.scalar { actual = g.evaluator.valueEvidence(slot.value); }
    if actual > 4 { return no; } var value = blot_support::none<blot_eval_core_eval::Value>(); if actual != 0 { value = g.evaluator.valueScalar(slot.value); }
    return blot_support::some(ScalarInput { target, actual, value , ..});
}
fn scalarMatches<G>(g: const G&, read: ScalarInput) -> bool { let actual = scalarInput(g, read.target); return actual.present && blot_structural::equal(actual.value, read); }
recursive fn acquire<S,G>(state: S&, g: G&, read: blot_reuse_specialization_receipt::CallRead, actual: u32) -> blot_support::Option<Record>, Error {
    let target = BindingRef { read.unit, read.binding , ..}; if !state.gate.admits(target) { return blot_support::none<Record>(), blot_error::Error.none; }
    for record in recordsView(state.completed_worker_proofs) {
        if record.target != target || record.evidence != actual || record.depth != g.evaluator.depth || !blot_structural::equal(record.options, g.evaluator.options) { continue; }
        var valid = true; for source in record.sources { if !state.gate.admits(source) { valid = false; break; } }
        if valid { for input in record.scalar_reads { if !scalarMatches(g, input) { valid = false; break; } } }
        if !valid { continue; } let cloned, error = record.clone(); if error != blot_error::Error.none { return blot_support::none<Record>(), error; } state.stats.independent_reused++; return blot_support::some(cloned), blot_error::Error.none;
    }
    for record in recordsView(state.old.metadata().independent_calls) {
        if record.target != target || record.evidence != read.evidence || record.depth != g.evaluator.depth || !blot_structural::equal(record.options, g.evaluator.options) { continue; }
        var valid = true; for source in record.sources { if !state.gate.admits(source) { valid = false; break; } }
        if valid { for input in record.scalar_reads { if !state.gate.admits(input.target) || !scalarMatches(g, input) { valid = false; break; } } }
        if !valid { continue; } var cloned, error = record.clone(); if error != blot_error::Error.none { return blot_support::none<Record>(), error; } cloned.evidence = actual; state.stats.independent_reused++; return blot_support::some(cloned), blot_error::Error.none;
    }
    var context = makeProofRecheck(state,g,read,actual); let error = blot_eval_core_eval::withSharedSession<Recheck<S,G>>(g.evaluator, state.gate.allocation_owner, context, probeSession);
    if error != blot_error::Error.none { return blot_support::none<Record>(), error; }
    if context.result.present { state.stats.independent_rechecked++; } else { state.stats.independent_declined++; } return context.result, blot_error::Error.none;
}
struct Recheck<S,G> { state: S&, generator: G&, read: blot_reuse_specialization_receipt::CallRead, actual: u32, result: blot_support::Option<Record> }
struct Representations { store: blot_backend_layout::Store& }
struct Probe { evaluator: blot_eval_core_eval::Session&, representations: Representations, owner_id: u64 }
struct ProbeContext<S,G> { query: Recheck<S,G>&, session: blot_eval_core_eval::Session&,expected:u32=0 }
recursive fn probeSession<S,G>(context: Recheck<S,G>&, session: blot_eval_core_eval::Session&) -> Error {
    var invocation = makeProbeContext(context,session);
    var error = blot_backend_layout::withStore<ProbeContext<S,G>>(invocation,probeLayout);
    if error==blot_error::Error.none&&invocation.expected!=0 {error=runProbeProof(context,session,invocation.expected);}
    context.state.stats.independent_regions += session.counters.inference_regions;
    context.state.stats.independent_nodes += session.counters.inference_general_nodes + session.counters.inference_specialization_nodes + session.counters.inference_preparation_nodes + session.counters.inference_lowering_nodes;
    return error;
}
fn probeLayout<S,G>(context: ProbeContext<S,G>&, store: blot_backend_layout::Store&) -> Error {
    let query .= context.query; let session .= context.session;
    session.options = query.generator.evaluator.options; session.depth = query.generator.evaluator.depth;
    let seeded = session.seedScalarInputs(query.generator.evaluator);
    if seeded == blot_error::Error.out_of_memory { return seeded; } if seeded != blot_error::Error.none { setProofResult(query,reject(query.state,DeclineReason.inputs)); return blot_error::Error.none; }
    assert(query.state.old.metadata().pools.present);
    let prepared, error = blot_reuse_artifact_import::initIndependentQuery(query.state.gate.allocation_owner, query.state.old.metadata().pools.value, session.units, query.state.gate);
    if error != blot_error::Error.none { return error; } if !prepared.present { setProofResult(query,reject(query.state,DeclineReason.imports)); return blot_error::Error.none; }
    var maps = prepared.value; var probe = makeIndependentProbe(session,store,session.owner_id);
    let expected, imported = maps.importEvidence(probe, query.read.evidence);
    if imported != blot_error::Error.none || !expected.present { maps.deinit(); if imported != blot_error::Error.none { return imported; } setProofResult(query,reject(query.state,DeclineReason.imports)); return blot_error::Error.none; }
    context.expected=expected.value; maps.deinit(); return blot_error::Error.none;
}
recursive fn probeProof<S,G>(context: Recheck<S,G>&, session: blot_eval_core_eval::Session&, expected: u32, tape: blot_reuse_specialization_receipt::Tape&, observation: blot_reuse_refinement_receipt::Observation&) -> Error {
    let state .= context.state; let g .= context.generator; let target = BindingRef { context.read.unit, context.read.binding , ..};
    let before_values = session.storage.values.len; let before_children = session.storage.children.len;
    let proved, error = session.recheckCallProof(target, expected);
    if error == blot_error::Error.out_of_memory { return error; } if error != blot_error::Error.none { setProofResult(context,reject(state, DeclineReason.query)); return blot_error::Error.none; }
    var reason = blot_support::none<DeclineReason>();
    if !proved { reason = blot_support::some(DeclineReason.proof); }
    else if session.diagnostic.present { reason = blot_support::some(DeclineReason.diagnostic); }
    else if tape.unknown { reason = blot_support::some(DeclineReason.unknown); }
    else if tape.nested { reason = blot_support::some(DeclineReason.nested); }
    else if tape.views.len != 0 { reason = blot_support::some(DeclineReason.views); }
    else if observation.regions != 1 { reason = blot_support::some(DeclineReason.regions); }
    else if !observation.complete { reason = blot_support::some(DeclineReason.incomplete); }
    else if session.steps != 0 { reason = blot_support::some(DeclineReason.steps); }
    else if session.storage.values.len != before_values || session.storage.children.len != before_children { reason = blot_support::some(DeclineReason.values); }
    if reason.present { setProofResult(context,reject(state, reason.value)); return blot_error::Error.none; }
    for input in tape.call_reads.items { if input.present { setProofResult(context,reject(state, DeclineReason.calls)); return blot_error::Error.none; } }
    let scalars = proof_scalars.alloc_slice(tape.scalar_reads.len); var count: i64 = 0;
    for input in tape.scalar_reads.items {
        let read = scalarInput(g, input.target);
        if !state.gate.admits(input.target) || !read.present || read.value.evidence != input.evidence { releaseScalars(scalars); setProofResult(context,reject(state, DeclineReason.scalar)); return blot_error::Error.none; }
        scalars[count] = read.value; count++;
    }
    let appended = tape.sources.push(target); if appended != blot_error::Error.none { releaseScalars(scalars); return appended; }
    for source in tape.sources.items { if !state.gate.admits(source) { releaseScalars(scalars); setProofResult(context,reject(state, DeclineReason.source)); return blot_error::Error.none; } }
    let failures = [tape.sources.failure, tape.scalar_reads.failure, tape.call_reads.failure, tape.call_publications.failure, tape.views.failure, tape.plain_facts.failure];
    for failure in failures { if failure != blot_error::Error.none { releaseScalars(scalars); return failure; } }
    setProofResult(context,blot_support::some(makeProofRecord(target,context.actual,g.evaluator.options,g.evaluator.depth,copySources(tape.sources.items),scalars))); return blot_error::Error.none;
}

fn recordsView(records:const Record[:])->const Record[:] {return records;}
fn recordsView(records:const blot_eval_semantic_parallel::Records&)->const Record[:] {return records.items;}

fn recordsView(records:const blot_reuse_code_artifacts::Context_blot_reuse_independent_call_proof__Record&)->const Record[:] {return records.items;}

fn makeProofRecheck<S,G>(state:S&,g:G&,read:blot_reuse_specialization_receipt::CallRead,actual:u32)->Recheck<S,G> {return Recheck<S,G>{state,g,read,actual,..};}

fn makeProbeContext<S,G>(context:Recheck<S,G>&,session:blot_eval_core_eval::Session&)->ProbeContext<S,G> {return ProbeContext<S,G>{context,session,..};}

fn makeProofRecord(target:BindingRef,evidence:u32,options:blot_eval_core_eval::Options,depth:i64,sources:BindingRef[:],scalar_reads:ScalarInput[:])->Record {return Record{target:target,evidence:evidence,options:options,depth:depth,sources:sources,scalar_reads:scalar_reads,..};}
fn setProofResult<S,G>(context:Recheck<S,G>&,value:blot_support::Option<Record>) {context.result=value;}

fn setProbeObservation(session:blot_eval_core_eval::Session&,value:blot_reuse_refinement_receipt::Observation?) {session.refinement_observation .= value;}

fn makeIndependentProbe(session:blot_eval_core_eval::Session&,store:blot_backend_layout::Store&,owner_id:u64)->Probe {return Probe{session,Representations{store,..},owner_id,..};}

recursive fn runProbeProof<S,G>(query:Recheck<S,G>&,session:blot_eval_core_eval::Session&,expected:u32)->Error {
    var tape_owner, tape_error = blot_reuse_specialization_receipt::initTapeOwner(); if tape_error != blot_error::Error.none { return tape_error; }
    let tape .= tape_owner.borrow(); assert(tape);
    var observation_owner, observation_error = blot_reuse_refinement_receipt::initObservationOwner(); if observation_error != blot_error::Error.none { tape_owner.deinit(); return observation_error; }
    let observation .= observation_owner.borrow(); assert(observation);
    blot_eval_core_eval::setSccReceiptTape(session,tape); setProbeObservation(session,observation);
    let failure = probeProof(query, session, expected, tape, observation);
    blot_eval_core_eval::setSccReceiptTape(session,null); setProbeObservation(session,null); tape_owner.deinit(); observation_owner.deinit(); return failure;
}
