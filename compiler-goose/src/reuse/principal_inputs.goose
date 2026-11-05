// Dynamic observations qualify principal constraints, never evaluated values.
namespace blot_reuse_principal_inputs;
import std;
import dictionary;
import check.core;
import eval.core_eval;
import eval.type_evidence;
import support.error;
import support.option;
type Error = blot_error::Error;
type BindingRef = blot_check_core::BindingRef;
struct ScalarRead { target: BindingRef, evidence: u32 }
struct PlainRead { key: u64, value: blot_support::Option<bool> }
struct PlainPublication { key: u64, value: bool }
struct CallPublication { target: BindingRef, evidence: u32 }
struct CallRead { target: BindingRef, evidence: u32, present: bool }
struct SummaryKey { target: BindingRef, inputs: u32, deferred_member: bool = false }
struct Summary { key: SummaryKey, result: u32 }
struct Key {
    empty_call_inputs: bool = true, source_complete: bool = false,
    sources: const BindingRef[:] = [], interfaces: const BindingRef[:] = [],
    source_units: const u32[:] = [], scalar_reads: const ScalarRead[:],
    plain_reads: const PlainRead[:] = [], plain_publications: const PlainPublication[:] = [],
    call_publications: CallPublication[:] = [], call_reads: CallRead[:] = [],
    summary_reads: Summary[:] = [], summary_publications: Summary[:] = [],
}
reusable[] var owned_binding: BindingRef[>..] = [];
fn copyOwned(source: const BindingRef[:]) -> BindingRef[:] {
    if source.len == 0 { return []; } let out = owned_binding.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const BindingRef[:]) {
    if source.len == 0 { return; } let first: const BindingRef& = source[0];
    let at = owned_binding.index_of(first); assert(at >= 0); owned_binding.free_slice(owned_binding[at..at + source.len]);
}
reusable[] var owned_units: u32[>..] = [];
fn copyOwned(source: const u32[:]) -> u32[:] {
    if source.len == 0 { return []; } let out = owned_units.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const u32[:]) {
    if source.len == 0 { return; } let first: const u32& = source[0];
    let at = owned_units.index_of(first); assert(at >= 0); owned_units.free_slice(owned_units[at..at + source.len]);
}
reusable[] var owned_scalar: ScalarRead[>..] = [];
fn copyOwned(source: const ScalarRead[:]) -> ScalarRead[:] {
    if source.len == 0 { return []; } let out = owned_scalar.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const ScalarRead[:]) {
    if source.len == 0 { return; } let first: const ScalarRead& = source[0];
    let at = owned_scalar.index_of(first); assert(at >= 0); owned_scalar.free_slice(owned_scalar[at..at + source.len]);
}
reusable[] var owned_plain_reads: PlainRead[>..] = [];
fn copyOwned(source: const PlainRead[:]) -> PlainRead[:] {
    if source.len == 0 { return []; } let out = owned_plain_reads.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const PlainRead[:]) {
    if source.len == 0 { return; } let first: const PlainRead& = source[0];
    let at = owned_plain_reads.index_of(first); assert(at >= 0); owned_plain_reads.free_slice(owned_plain_reads[at..at + source.len]);
}
reusable[] var owned_plain_publications: PlainPublication[>..] = [];
fn copyOwned(source: const PlainPublication[:]) -> PlainPublication[:] {
    if source.len == 0 { return []; } let out = owned_plain_publications.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const PlainPublication[:]) {
    if source.len == 0 { return; } let first: const PlainPublication& = source[0];
    let at = owned_plain_publications.index_of(first); assert(at >= 0); owned_plain_publications.free_slice(owned_plain_publications[at..at + source.len]);
}
reusable[] var owned_call_publications: CallPublication[>..] = [];
fn copyOwned(source: const CallPublication[:]) -> CallPublication[:] {
    if source.len == 0 { return []; } let out = owned_call_publications.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const CallPublication[:]) {
    if source.len == 0 { return; } let first: const CallPublication& = source[0];
    let at = owned_call_publications.index_of(first); assert(at >= 0); owned_call_publications.free_slice(owned_call_publications[at..at + source.len]);
}
reusable[] var owned_call_reads: CallRead[>..] = [];
fn copyOwned(source: const CallRead[:]) -> CallRead[:] {
    if source.len == 0 { return []; } let out = owned_call_reads.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const CallRead[:]) {
    if source.len == 0 { return; } let first: const CallRead& = source[0];
    let at = owned_call_reads.index_of(first); assert(at >= 0); owned_call_reads.free_slice(owned_call_reads[at..at + source.len]);
}
reusable[] var owned_summaries: Summary[>..] = [];
fn copyOwned(source: const Summary[:]) -> Summary[:] {
    if source.len == 0 { return []; } let out = owned_summaries.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const Summary[:]) {
    if source.len == 0 { return; } let first: const Summary& = source[0];
    let at = owned_summaries.index_of(first); assert(at >= 0); owned_summaries.free_slice(owned_summaries[at..at + source.len]);
}
fn clone(self: Key) -> Key, Error {
    var result = self;
    result.sources = copyOwned(self.sources);
    result.interfaces = copyOwned(self.interfaces);
    result.source_units = copyOwned(self.source_units);
    result.scalar_reads = copyOwned(self.scalar_reads);
    result.plain_reads = copyOwned(self.plain_reads);
    result.plain_publications = copyOwned(self.plain_publications);
    result.call_publications = copyOwned(self.call_publications);
    result.call_reads = copyOwned(self.call_reads);
    result.summary_reads = copyOwned(self.summary_reads);
    result.summary_publications = copyOwned(self.summary_publications);
    return result, Error.none;
}
fn deinit(self: Key&) {
    releaseOwned(self.sources); self.sources = [];
    releaseOwned(self.interfaces); self.interfaces = [];
    releaseOwned(self.source_units); self.source_units = [];
    releaseOwned(self.scalar_reads); self.scalar_reads = [];
    releaseOwned(self.plain_reads); self.plain_reads = [];
    releaseOwned(self.plain_publications); self.plain_publications = [];
    releaseOwned(self.call_publications); self.call_publications = [];
    releaseOwned(self.call_reads); self.call_reads = [];
    releaseOwned(self.summary_reads); self.summary_reads = [];
    releaseOwned(self.summary_publications); self.summary_publications = [];
}
fn proofKey(target: BindingRef, evidence: u32) -> blot_eval_core_eval::CallProofKey {
    return blot_eval_core_eval::CallProofKey { target: BindingRef { target.unit - 1, target.binding }, evidence: evidence };
}
fn matches<S>(self: Key, session: const S&) -> bool {
    if !self.matchesBase(session) { return false; }
    for read in self.call_reads {
        if read.target.unit == 0 || read.target.unit > session.units.len || read.target.binding == 0 || read.target.binding >= session.units[read.target.unit - 1].bindings.len { return false; }
        if session.specializations.validated_calls.contains(proofKey(read.target, read.evidence)) != read.present { return false; }
    }
    for read in self.summary_reads { if !session.principalSummaryMatches(read) { return false; } } return true;
}
fn matchesBase<S>(self: Key, session: const S&) -> bool {
    if self.empty_call_inputs && session.specializations.validated_calls.count != 0 { return false; }
    let tags = [blot_eval_type_evidence::Tag.absent, blot_eval_type_evidence::Tag.unit,
        blot_eval_type_evidence::Tag.boolean, blot_eval_type_evidence::Tag.unsigned32,
        blot_eval_type_evidence::Tag.floating32, blot_eval_type_evidence::Tag.never];
    if session.storage.evidence.nodes.len < tags.len { return false; }
    for tag, index in tags { if session.storage.evidence.nodes[index] != blot_eval_type_evidence::Node { tag: tag } { return false; } }
    for read in self.scalar_reads {
        if read.evidence > 5 || read.target.unit == 0 || read.target.unit > session.units.len { return false; }
        let module = session.units[read.target.unit - 1];
        if read.target.binding == 0 || read.target.binding >= module.bindings.len { return false; }
        let body = module.body(read.target.binding); if body == null { return false; }
        let slot = session.slots[session.binding_offsets[read.target.unit - 1] + read.target.binding];
        var actual: u32 = 0;
        if !body.runtime && slot.state == blot_eval_core_eval::State.complete && session.valueInfo(slot.value).kind == blot_eval_core_eval::ValueKind.scalar {
            actual = session.valueEvidence(slot.value);
        }
        if actual != read.evidence { return false; }
    }
    for read in self.plain_reads {
        let actual = session.specializations.plain_nominals.get(read.key);
        if read.value.present { { let optional_source_41 .= actual; if optional_source_41 { let found .= optional_source_41; if found != read.value.value { return false; }  } else { return false; } } }
        else if actual != null { return false; }
    }
    return true;
}
fn publish<S>(self: Key, session: S&) -> Error {
    session.specializations.plain_nominals.reserve(session.specializations.plain_nominals.count + self.plain_publications.len);
    session.specializations.validated_calls.reserve(session.specializations.validated_calls.count + self.call_publications.len);
    let error = session.reservePrincipalSummaries(self.summary_publications.len); if error != Error.none { return error; }
    for fact in self.plain_publications { session.specializations.plain_nominals.insert(fact.key, fact.value); }
    for call in self.call_publications {
        let key = proofKey(call.target, call.evidence);
        if !session.specializations.validated_calls.contains(key) { session.proofs.proof_published++; }
        session.specializations.validated_calls.insert(key, true);
    }
    for summary in self.summary_publications { session.publishPrincipalSummary(summary); } return Error.none;
}
enum Reason { unsupported, runtime_source, call_read, call_publication, evaluate, specialize, scalar_domain, changed_input, read_limit }
fn reasonCode(value: Reason) -> u32 {
    match value { Reason.unsupported => 0, Reason.runtime_source => 1, Reason.call_read => 2, Reason.call_publication => 3,
        Reason.evaluate => 4, Reason.specialize => 5, Reason.scalar_domain => 6, Reason.changed_input => 7, Reason.read_limit => 8 }
}
struct PlainSeen { initial: blot_support::Option<bool>, publication: blot_support::Option<i64> }
struct Recorder {
    rejected: u16 = 0, eligible: bool, empty_call_inputs: bool = true, source_complete: bool = true,
    root: BindingRef = BindingRef { 0, 0 }, serial: u64 = 0, max_reads: i64,
    sources: BindingRef[>..<]&,
    sources_seen: dictionary<BindingRef,bool>&,
    interfaces: BindingRef[>..<]&,
    interfaces_seen: dictionary<BindingRef,bool>&,
    source_units: u32[>..<]&,
    source_units_seen: dictionary<u32,bool>&,
    reads: ScalarRead[>..<]&,
    seen: dictionary<u64,u32>&,
    plain_reads: PlainRead[>..<]&,
    plain_publications: PlainPublication[>..<]&,
    plain_seen: dictionary<u64,PlainSeen>&,
    call_publications: CallPublication[>..<]&,
    calls_seen: dictionary<CallPublication,bool>&,
    call_reads: CallRead[>..<]&,
    call_reads_seen: dictionary<CallPublication,bool>&,
    summary_reads: Summary[>..<]&,
    summary_publications: Summary[>..<]&,
    summaries_seen: dictionary<SummaryKey,u32>&,
    summary_reads_seen: dictionary<SummaryKey,u32>&,
}
struct RecorderTables {
    sources: BindingRef[>..<]&,
    sources_seen: dictionary<BindingRef,bool>&,
    interfaces: BindingRef[>..<]&,
    interfaces_seen: dictionary<BindingRef,bool>&,
    source_units: u32[>..<]&,
    source_units_seen: dictionary<u32,bool>&,
    reads: ScalarRead[>..<]&,
    seen: dictionary<u64,u32>&,
    plain_reads: PlainRead[>..<]&,
    plain_publications: PlainPublication[>..<]&,
    plain_seen: dictionary<u64,PlainSeen>&,
    call_publications: CallPublication[>..<]&,
    calls_seen: dictionary<CallPublication,bool>&,
    call_reads: CallRead[>..<]&,
    call_reads_seen: dictionary<CallPublication,bool>&,
    summary_reads: Summary[>..<]&,
    summary_publications: Summary[>..<]&,
    summaries_seen: dictionary<SummaryKey,u32>&,
    summary_reads_seen: dictionary<SummaryKey,u32>&,
}
fn init(t: RecorderTables, eligible: bool, max_reads: i64) -> Recorder {
    return Recorder { eligible: eligible, max_reads: max_reads,
        sources: t.sources,
        sources_seen: t.sources_seen,
        interfaces: t.interfaces,
        interfaces_seen: t.interfaces_seen,
        source_units: t.source_units,
        source_units_seen: t.source_units_seen,
        reads: t.reads,
        seen: t.seen,
        plain_reads: t.plain_reads,
        plain_publications: t.plain_publications,
        plain_seen: t.plain_seen,
        call_publications: t.call_publications,
        calls_seen: t.calls_seen,
        call_reads: t.call_reads,
        call_reads_seen: t.call_reads_seen,
        summary_reads: t.summary_reads,
        summary_publications: t.summary_publications,
        summaries_seen: t.summaries_seen,
        summary_reads_seen: t.summary_reads_seen,
    };
}
fn deinit(self: Recorder&) {
    self.sources.clear();
    self.sources_seen.clear();
    self.interfaces.clear();
    self.interfaces_seen.clear();
    self.source_units.clear();
    self.source_units_seen.clear();
    self.reads.clear();
    self.seen.clear();
    self.plain_reads.clear();
    self.plain_publications.clear();
    self.plain_seen.clear();
    self.call_publications.clear();
    self.calls_seen.clear();
    self.call_reads.clear();
    self.call_reads_seen.clear();
    self.summary_reads.clear();
    self.summary_publications.clear();
    self.summaries_seen.clear();
    self.summary_reads_seen.clear();
}
fn invalidate(self: Recorder&, reason: Reason) { self.eligible = false; self.rejected |= (1 as u16) << reasonCode(reason); }
fn scalar(self: Recorder&, target: BindingRef, actual: u32) -> Error {
    if !self.eligible { return Error.none; }
    let error = self.source(target); if error != Error.none { return error; }
    if actual > 5 || target.unit == 0 || target.binding == 0 { self.invalidate(Reason.scalar_domain); return Error.none; }
    let id = (target.unit as u64 << 32) | target.binding;
    { let optional_source_40 .= self.seen.get(id); if optional_source_40 { let previous = optional_source_40; if previous != actual { self.invalidate(Reason.changed_input); } return Error.none;  } }
    if self.plain_reads.len >= self.max_reads || self.reads.len >= self.max_reads - self.plain_reads.len { self.invalidate(Reason.read_limit); return Error.none; }
    self.seen.insert(id, actual); self.reads.push(ScalarRead { target, actual }); return Error.none;
}
fn plainRead(self: Recorder&, key: u64, actual: blot_support::Option<bool>) -> Error {
    if !self.eligible { return Error.none; }
    { let optional_source_39 .= self.plain_seen.get(key); if optional_source_39 { let previous .= optional_source_39;
        var expected = previous.initial;
        if previous.publication.present { expected = blot_support::some(self.plain_publications[previous.publication.value].value); }
        if expected != actual { self.invalidate(Reason.changed_input); } return Error.none;
     } }
    if self.plain_reads.len >= self.max_reads || self.reads.len >= self.max_reads - self.plain_reads.len { self.invalidate(Reason.read_limit); return Error.none; }
    self.plain_seen.insert(key, PlainSeen { initial: actual }); self.plain_reads.push(PlainRead { key, actual }); return Error.none;
}
fn plainRead(self: Recorder&, key: u64, actual: const bool?) -> Error {
    { let optional_source_38 .= actual; if optional_source_38 { let value .= optional_source_38; return self.plainRead(key, blot_support::some(value));  } } return self.plainRead(key, blot_support::none<bool>());
}
fn plainPublish(self: Recorder&, key: u64, value: bool) -> Error {
    if !self.eligible { return Error.none; }
    { let optional_source_37 .= self.plain_seen.get(key); if optional_source_37 { let observed .= optional_source_37;
        if observed.publication.present { self.plain_publications[observed.publication.value].value = value; }
        else {
            let at = self.plain_publications.len; self.plain_publications.push(PlainPublication { key, value });
            observed.publication = blot_support::some(at);
        }
     } else { self.invalidate(Reason.changed_input); } }
    return Error.none;
}
fn callPublish(self: Recorder&, target: BindingRef, actual: u32) -> Error {
    if !self.eligible { return Error.none; } let call = CallPublication { target, actual };
    if self.calls_seen.contains(call) { return Error.none; }
    if self.call_publications.len >= self.max_reads { self.invalidate(Reason.read_limit); return Error.none; }
    self.calls_seen.insert(call, true); self.call_publications.push(call); return Error.none;
}
fn callRead(self: Recorder&, target: BindingRef, actual: u32, present: bool) -> Error {
    if !self.eligible { return Error.none; } let call = CallPublication { target, actual };
    if self.calls_seen.contains(call) { if !present { self.invalidate(Reason.changed_input); } return Error.none; }
    if self.empty_call_inputs { if present { self.invalidate(Reason.call_read); } return Error.none; }
    { let optional_source_36 .= self.call_reads_seen.get(call); if optional_source_36 { let previous = optional_source_36; if previous != present { self.invalidate(Reason.changed_input); } return Error.none;  } }
    if self.call_reads.len >= self.max_reads { self.invalidate(Reason.read_limit); return Error.none; }
    self.call_reads_seen.insert(call, present); self.call_reads.push(CallRead { target, actual, present }); return Error.none;
}
fn summaryRead(self: Recorder&, value: Summary) -> Error {
    if !self.eligible { return Error.none; }
    { let optional_source_35 .= self.summaries_seen.get(value.key); if optional_source_35 { let previous = optional_source_35; if previous != value.result { self.invalidate(Reason.changed_input); } return Error.none;  } }
    { let optional_source_34 .= self.summary_reads_seen.get(value.key); if optional_source_34 { let previous = optional_source_34; if previous != value.result { self.invalidate(Reason.changed_input); } return Error.none;  } }
    if self.summary_reads.len >= self.max_reads { self.invalidate(Reason.read_limit); return Error.none; }
    self.summary_reads_seen.insert(value.key, value.result); self.summary_reads.push(value); return Error.none;
}
fn summaryPublish(self: Recorder&, value: Summary) -> Error {
    if !self.eligible { return Error.none; }
    { let optional_source_33 .= self.summaries_seen.get(value.key); if optional_source_33 { let previous = optional_source_33; if previous != value.result { self.invalidate(Reason.changed_input); } return Error.none;  } }
    if self.summary_publications.len >= self.max_reads { self.invalidate(Reason.read_limit); return Error.none; }
    self.summaries_seen.insert(value.key, value.result); self.summary_publications.push(value); return Error.none;
}
fn sourceRoom(self: const Recorder&) -> bool { return self.sources.len + self.source_units.len + self.interfaces.len < self.max_reads; }
fn source(self: Recorder&, target: BindingRef) -> Error {
    if !self.eligible || !self.source_complete || self.sources_seen.contains(target) { return Error.none; }
    if target.unit == 0 || target.binding == 0 || !self.sourceRoom() { self.source_complete = false; return Error.none; }
    self.sources_seen.insert(target, true); self.sources.push(target); return Error.none;
}
fn interface(self: Recorder&, target: BindingRef) -> Error {
    if !self.eligible || !self.source_complete || self.interfaces_seen.contains(target) { return Error.none; }
    if target.unit == 0 || target.binding == 0 || !self.sourceRoom() { self.source_complete = false; return Error.none; }
    self.interfaces_seen.insert(target, true); self.interfaces.push(target); return Error.none;
}
fn sourceUnit(self: Recorder&, unit: u32) -> Error {
    if !self.eligible || !self.source_complete || self.source_units_seen.contains(unit) { return Error.none; }
    if unit == 0 || !self.sourceRoom() { self.source_complete = false; return Error.none; }
    self.source_units_seen.insert(unit, true); self.source_units.push(unit); return Error.none;
}
fn key(self: const Recorder&) -> blot_support::Option<Key> {
    if !self.eligible { return blot_support::none<Key>(); }
    return blot_support::some(Key { self.empty_call_inputs, self.source_complete, self.sources, self.interfaces, self.source_units,
        self.reads, self.plain_reads, self.plain_publications, self.call_publications, self.call_reads, self.summary_reads, self.summary_publications });
}
fn withRecorder<C,F>(session: const blot_eval_core_eval::Session&, context: C&) -> Error {
    var sources: BindingRef[>..<] = [];
    var sources_seen: dictionary<BindingRef,bool> = dictionary<BindingRef,bool> {};
    var interfaces: BindingRef[>..<] = [];
    var interfaces_seen: dictionary<BindingRef,bool> = dictionary<BindingRef,bool> {};
    var source_units: u32[>..<] = [];
    var source_units_seen: dictionary<u32,bool> = dictionary<u32,bool> {};
    var reads: ScalarRead[>..<] = [];
    var seen: dictionary<u64,u32> = dictionary<u64,u32> {};
    var plain_reads: PlainRead[>..<] = [];
    var plain_publications: PlainPublication[>..<] = [];
    var plain_seen: dictionary<u64,PlainSeen> = dictionary<u64,PlainSeen> {};
    var call_publications: CallPublication[>..<] = [];
    var calls_seen: dictionary<CallPublication,bool> = dictionary<CallPublication,bool> {};
    var call_reads: CallRead[>..<] = [];
    var call_reads_seen: dictionary<CallPublication,bool> = dictionary<CallPublication,bool> {};
    var summary_reads: Summary[>..<] = [];
    var summary_publications: Summary[>..<] = [];
    var summaries_seen: dictionary<SummaryKey,u32> = dictionary<SummaryKey,u32> {};
    var summary_reads_seen: dictionary<SummaryKey,u32> = dictionary<SummaryKey,u32> {};
    let tables = RecorderTables { sources, sources_seen, interfaces, interfaces_seen, source_units, source_units_seen, reads, seen, plain_reads, plain_publications, plain_seen, call_publications, calls_seen, call_reads, call_reads_seen, summary_reads, summary_publications, summaries_seen, summary_reads_seen };
    var recorder = init(tables, true, session.options.max_values);
    recorder.empty_call_inputs = session.specializations.validated_calls.count == 0;
    recorder.serial = session.principal_recordings;
    return F(context, recorder);
}
