// Caller-owned metadata/emission frames outlive this capture and its readers.
namespace blot_reuse_artifact_capture;
import reuse.code_artifacts;
import reuse.artifact_emitter;
import reuse.executable_query;
import check.core;
import check.types;
import check.check;
import backend.runtime_identity;
import backend.optimized_bodies;
import support.error;
import support.option;
import support.structural;
type Error = blot_error::Error;
struct Capture {
    metadata: blot_reuse_code_artifacts::Context&, emission: blot_reuse_artifact_emitter::Recorder&,
    cached_units: i64 = 0, optimized: blot_backend_optimized_bodies::Capture&? = null,
    executable_queries: blot_reuse_executable_query::FragmentTable&,
    executable_queries_complete: bool = false,
}
fn init(metadata: blot_reuse_code_artifacts::Context&, emission: blot_reuse_artifact_emitter::Recorder&,
    queries: blot_reuse_executable_query::FragmentTable&, cached_units: i64 = 0) -> Capture {
    return Capture { metadata: metadata, emission: emission, cached_units: cached_units, executable_queries: queries , ..};
}

fn sealExecutableQueries(self: Capture&) -> Error {
    assert(self.executable_queries.records.len == 0 && !self.executable_queries_complete);
    if !self.metadata.pools.present { return Error.none; }
    let pools = self.metadata.pools.value;
    for function in pools.functions {
        var supported = false;
        match function.request {
            blot_reuse_code_artifacts::Request.named, blot_reuse_code_artifacts::Request.closure => { supported = true; }, _ => {},
        }
        if !supported { continue; }
        let owner = self.emission.functions[function.function].owner;
        let job = self.metadata.jobs[owner - 1];
        assert(job.state == blot_reuse_code_artifacts::State.complete && job.function.present && job.function.value == function.function);
        if !job.reusable { continue; }
        let size = blot_reuse_executable_query::dependencyBytes<blot_check_core::BindingRef,blot_reuse_code_artifacts::StaticRead>(job.inline_bodies.len, job.static_reads.len);
        if !size.present || !self.executable_queries.canAdmit(size.value) { self.executable_queries.saturate(); return Error.none; }
        var builder = self.executable_queries.begin(blot_reuse_executable_query::FragmentKey { function.request , ..});
        let bodies = self.metadata.inline_bodies[job.inline_bodies.start..job.inline_bodies.start + job.inline_bodies.len];
        let reads = self.metadata.static_reads[job.static_reads.start..job.static_reads.start + job.static_reads.len];
        builder.read(blot_reuse_executable_query::FragmentDependencies {
            blot_reuse_executable_query::copyBodyReads(bodies), blot_reuse_executable_query::copyStaticReads(reads), owner, job.reusable,
         ..});
        builder.stage(blot_reuse_executable_query::FragmentResult { function.function, owner , ..});
        var candidate = builder.complete(); builder.abort(); assert(candidate.present);
        let prepared, error = self.executable_queries.prepare(candidate.value);
        if error != Error.none { candidate.value.abort(); return error; }
        if !prepared.present { candidate.value.abort(); return Error.none; }
        let handle = self.executable_queries.publish(prepared.value, candidate.value); candidate.value.abort();
    }
    self.executable_queries_complete = true; return Error.none;
}
fn selectionStable(self: const Capture&, units: const blot_check_core::Module[:],
    names: blot_support::Option<blot_backend_runtime_identity::View>, cached: i64) -> bool {
    if !self.metadata.pools.present { return false; }
    let pools = self.metadata.pools.value; if !pools.identity.present || !names.present { return false; }
    let old_names = pools.identity.value.view(); let current_names = names.value;
    if cached != self.cached_units || cached > units.len || units.len != pools.modules.len { return false; }
    for pin, index in pools.modules {
        let unit = units[index]; let path = current_names.owner(unit.unit);
        if !path.present || pin.unit != unit.unit || pin.canonical_path != path.value { return false; }
        if index + 1 <= cached { continue; }
        let previous = pin.module;
        if !blot_structural::equal(previous.associated, unit.associated) { return false; }
        for method in previous.associated {
            if method.member != 0 {
                let before = old_names.symbol(method.member); let after = current_names.symbol(method.member);
                if !before.present || !after.present || before.value != after.value { return false; }
            }
            if method.identity.unit == 0 {
                match method.identity.decl { 1, 2, 3, 4, 4294967295, 4294967294 => {}, _ => { return false; } }
            } else if method.identity.unit > cached { return false; }
            if method.target.unit == 0 || method.target.unit > cached { return false; }
            let producer = units[method.target.unit - 1];
            if method.target.binding == 0 || method.target.binding >= producer.bindings.len ||
                producer.bindings[method.target.binding].kind == blot_check_check::Kind.external || producer.body(method.target.binding) == null { return false; }
        }
        if !blot_structural::equal(blot_check_core::typesStampView(previous.types), blot_check_core::typesStampView(unit.types)) ||
            !blot_structural::equal(previous.nominals, unit.nominals) || !blot_structural::equal(previous.constructors, unit.constructors) { return false; }
        for old, at in previous.nominals {
            let current = unit.nominals[at];
            if !blot_structural::equal(previous.extra[old.constructors.start..old.constructors.start + old.constructors.len],
                unit.extra[current.constructors.start..current.constructors.start + current.constructors.len]) { return false; }
        }
        for node in previous.types.nodes {
            if node.tag != blot_check_types::Tag.record { continue; }
            for field in node.b {
                let symbol = previous.types.extra[node.a + field * 2];
                let before = old_names.symbol(symbol); let after = current_names.symbol(symbol);
                if !before.present || !after.present || before.value != after.value { return false; }
            }
        }
    }
    return true;
}
fn deinit(self: Capture&) {
    self.executable_queries.deinit();
    if self.optimized { self.optimized.deinit(); self.optimized .= null; }
    self.emission.deinit(); self.metadata.deinit(); self.executable_queries_complete = false;
}
