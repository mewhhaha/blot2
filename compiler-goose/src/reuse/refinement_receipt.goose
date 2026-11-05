// Exact refinement receipts share an immutable evidence owner, never a solver.
namespace blot_reuse_refinement_receipt;
import check.core;
import eval.core_eval;
import eval.type_evidence;
import reuse.code_expectation;
import reuse.specialization_receipt;
import reuse.semantic_query_table;
import reuse.source_value_template;
import support.error;
import support.host_layout;
import support.option;
import support.wyhash;
import support.structural;
import dictionary;
type Error = blot_error::Error;
enum Root { body { target: blot_check_core::BindingRef }, closure { unit: u32, catalog: u32 } }
fn namedOwner(module: const blot_check_core::Module&, binding: u32) -> bool {
    return binding < module.bindings.len && module.body(binding) != null;
}
fn rootOwner(module: const blot_check_core::Module&, root: Root) -> bool {
    match root { body body => { return namedOwner(module, body.target.binding); }, closure closure => { return closure.catalog < module.closures.len; } }
}
fn rootUnit(root: Root) -> u32 { match root { body body => body.target.unit, closure closure => closure.unit } }
fn queryOwners(units: const blot_check_core::Module[:], root: Root, sources: const blot_check_core::BindingRef[:]) -> bool {
    let unit = rootUnit(root);
    if unit == 0 || unit > units.len || !rootOwner(units[unit - 1], root) { return false; }
    for source in sources { if source.unit == 0 || source.unit > units.len || !namedOwner(units[source.unit - 1], source.binding) { return false; } }
    return true;
}
fn generativeQuery(units: const blot_check_core::Module[:], root: Root, sources: const blot_check_core::BindingRef[:]) -> bool, Error {
    if !queryOwners(units, root, sources) { return true, blot_error::Error.none; }
    let unit = rootUnit(root); if unit == 0 || unit > units.len { return true, blot_error::Error.none; }
    var generated = false;
    match root {
        body body => { let result, error = blot_reuse_source_value_template::generativeNamed(units[unit - 1], body.target.binding); if error != blot_error::Error.none { return false, error; } generated = result; },
        closure closure => { let result, error = blot_reuse_source_value_template::generativeClosure(units[unit - 1], closure.catalog); if error != blot_error::Error.none { return false, error; } generated = result; },
    }
    if generated { return true, blot_error::Error.none; }
    for source in sources {
        if source.unit == 0 || source.unit > units.len { return true, blot_error::Error.none; }
        let result, error = blot_reuse_source_value_template::generativeNamed(units[source.unit - 1], source.binding);
        if error != blot_error::Error.none { return false, error; } if result { return true, blot_error::Error.none; }
    }
    return false, blot_error::Error.none;
}
struct Observation { regions: i64 = 0, scopes: i64 = 0, nodes: i64 = 0, complete: bool = true }
fn observe<R>(self_: Observation&, region: const R&) {
    self_.regions++; self_.scopes += region.scratch.sources.len; self_.nodes += region.solver.nodes.len;
    self_.complete = self_.complete && !region.source_interface && !region.retain_selected;
    for constraint in region.scratch.constraints { self_.complete = self_.complete && constraint.solved; }
}
struct Key {
    root: Root, expected: u32, seeds: const blot_eval_type_evidence::Mapping[:],
    rows: const blot_eval_type_evidence::RowMapping[:], options: blot_eval_core_eval::Options, depth: i64,
}
reusable[] var key_seeds: blot_eval_type_evidence::Mapping[>..] = [];
reusable[] var key_rows: blot_eval_type_evidence::RowMapping[>..] = [];
fn copySeeds(source: const blot_eval_type_evidence::Mapping[:]) -> const blot_eval_type_evidence::Mapping[:] {
    if source.len == 0 { return default<const blot_eval_type_evidence::Mapping[:]>(); } let out = key_seeds.alloc_slice(source.len); for value, index in source { out[index] = value; } return out;
}
fn copyRows(source: const blot_eval_type_evidence::RowMapping[:]) -> const blot_eval_type_evidence::RowMapping[:] {
    if source.len == 0 { return default<const blot_eval_type_evidence::RowMapping[:]>(); } let out = key_rows.alloc_slice(source.len); for value, index in source { out[index] = value; } return out;
}
fn deinit(self_: Key&) {
    if self_.seeds.len != 0 { key_seeds.free_slice(self_.seeds); }
    if self_.rows.len != 0 { key_rows.free_slice(self_.rows); }
    self_.seeds = default<const blot_eval_type_evidence::Mapping[:]>(); self_.rows = default<const blot_eval_type_evidence::RowMapping[:]>();
}
struct Adapter {}
type Dependencies = blot_reuse_specialization_receipt::Record;
type Value = blot_eval_core_eval::SolvedEvidence;
type Record = blot_reuse_semantic_query_table::OwnedRecord<Key,Dependencies,Value,Adapter>;
type Table = blot_reuse_semantic_query_table::Table<Key,Dependencies,Value,Adapter>;
let kind = blot_reuse_semantic_query_table::Kind.refinement;
fn rootFingerprint(root: Root) -> u64 {
    var hash = blot_support_wyhash::init(0);
    match root {
        body body => { hash.value(0 as u8); hash.value(body.target.unit); hash.value(body.target.binding); },
        closure closure => { hash.value(1 as u8); hash.value(closure.unit); hash.value(closure.catalog); },
    }
    return hash.final();
}
fn fingerprint(self_: Adapter, key: Key) -> u64 { rootFingerprint(key.root) }
fn complete(self_: Adapter, record: Record) -> bool {
    let facts = record.dependencies;
    return facts.complete && facts.steps == 0 && facts.values_added == 0 && facts.children_added == 0 &&
        facts.views.len == 0 && record.value.selected.len == 0 && record.key.options == facts.options && record.key.depth == facts.depth;
}
fn bytes(self_: Adapter, record: Record) -> i64 {
    var total: i64 = 0;
    blot_reuse_specialization_receipt::addBytes(total, bytes_of(record.key.seeds).len);
    blot_reuse_specialization_receipt::addBytes(total, bytes_of(record.key.rows).len);
    blot_reuse_specialization_receipt::addBytes(total, bytes_of(record.dependencies.sources).len);
    blot_reuse_specialization_receipt::addBytes(total, bytes_of(record.dependencies.scalar_reads).len);
    blot_reuse_specialization_receipt::addBytes(total, bytes_of(record.dependencies.call_reads).len);
    blot_reuse_specialization_receipt::addBytes(total, bytes_of(record.dependencies.call_publications).len);
    blot_reuse_specialization_receipt::addBytes(total, bytes_of(record.dependencies.views).len);
    blot_reuse_specialization_receipt::addBytes(total, bytes_of(record.dependencies.plain_facts).len);
    blot_reuse_specialization_receipt::addBytes(total, bytes_of(record.value.types).len);
    blot_reuse_specialization_receipt::addBytes(total, bytes_of(record.value.rows).len);
    blot_reuse_specialization_receipt::addBytes(total, bytes_of(record.value.selected).len); return total;
}
reusable[] var owned_records: Record[>..] = [];
fn allocateRecords(self_: Adapter, len: i64) -> Record[:], Error { return owned_records.alloc_slice(len), blot_error::Error.none; }
fn releaseRecords(self_: Adapter, source: const Record[:]) {
    if source.len == 0 { return; } owned_records.free_slice(source);
}
fn recordBytes(self_: Adapter) -> i64 { blot_host_layout::refinement_record }
fn init(limits: blot_reuse_semantic_query_table::Limits = blot_reuse_semantic_query_table::Limits { records: 8192, retained_capacity: 8388608 , ..}) -> Table {
    return blot_reuse_semantic_query_table::init<Key,Dependencies,Value,Adapter>(Adapter {..}, limits);
}
enum Reason { mode, root, source, shape, seed, scalar, call, plain, import_ }
enum RecordDecline { owner, source, generative, incomplete, capacity }
struct Stats {
    record_declines: i64[5] = [0; 5], call_became_present: i64 = 0, call_missing: i64 = 0,
    requests: i64 = 0, recorded: i64 = 0, complete: i64 = 0, candidates: i64 = 0, hits: i64 = 0,
    collected_removed: i64 = 0, nodes_removed: i64 = 0, publications: i64 = 0,
    local_requests: i64 = 0, local_hits: i64 = 0, local_candidates: i64 = 0,
    indexed_positions: i64 = 0, retained_records: i64 = 0, retained_payload_bytes: i64 = 0,
    retained_capacity_bytes: i64 = 0, saturated: i64 = 0, body_cutoff_hits: i64 = 0, reasons: i64[9] = [0; 9],
}

fn reasonCode(value: Reason) -> u32 {
    match value { mode => 0, root => 1, source => 2, shape => 3,
        seed => 4, scalar => 5, call => 6, plain => 7, import_ => 8 }
}
fn decline<G>(g: G&, reason: Reason) { g.refinement_stats.reasons[reasonCode(reason)]++; }
fn copyResult(result: Value) -> Value, Error { return result.clone(); }
fn storageStats<G>(g: G&, table: const Table&) {
    g.refinement_stats.retained_records = table.records.len;
    g.refinement_stats.retained_payload_bytes = table.owned_bytes;
    g.refinement_stats.retained_capacity_bytes = table.capacity_bytes;
    g.refinement_stats.saturated = table.saturated;
}
fn scalarEvidence<S>(session: const S&, target: blot_check_core::BindingRef) -> u32 {
    let module = session.units[target.unit - 1]; let body = module.body(target.binding); assert(body != null);
    let slot = session.slots[session.binding_offsets[target.unit - 1] + target.binding];
    if !body.runtime && slot.state == blot_eval_core_eval::State.complete &&
        session.valueInfo(slot.value).kind == blot_eval_eval_values::ValueKind.scalar { return session.valueEvidence(slot.value); }
    return 0;
}
fn callKey(read: blot_reuse_specialization_receipt::CallRead, evidence: u32) -> blot_eval_core_eval::CallProofKey {
    return blot_eval_core_eval::CallProofKey { target: blot_check_core::BindingRef { read.unit - 1, read.binding , ..}, evidence: evidence , ..};
}
fn lookupLocal<G>(g: G&, root: Root, expected: u32, seeds: const blot_eval_type_evidence::Mapping[:],
    rows: const blot_eval_type_evidence::RowMapping[:]) -> blot_support::Option<Value>, Error {
    { let optional_source_32 .= g.refinement_owner; if optional_source_32 { let owner .= optional_source_32;
        let session = g.evaluator;
        if session.receipt_tape != null || session.principal_reads != null { return blot_support::none<Value>(), blot_error::Error.none; }
        g.refinement_stats.local_requests++;
        let table = owner.refinement_queries;
        var cursor = table.candidates(rootFingerprint(root), blot_reuse_semantic_query_table::Order.newest_first);
        loop {
            let position = cursor.next(); if !position.present { break; }
            g.refinement_stats.local_candidates++; g.refinement_stats.indexed_positions++;
            let record = table.records[position.value]; let facts = record.dependencies;
            if record.key.root != root || record.key.expected != expected || record.key.seeds != seeds || record.key.rows != rows { continue; }
            if facts.options != session.options || facts.depth != session.depth || facts.steps != 0 ||
                facts.values_added != 0 || facts.children_added != 0 || facts.views.len != 0 { continue; }
            var same = true;
            for read in facts.scalar_reads { if read.evidence != scalarEvidence(session, read.target) { same = false; break; } }
            if !same { continue; }
            for read in facts.call_reads {
                if read.present && !session.specializations.validated_calls.contains(callKey(read, read.evidence)) { same = false; break; }
            }
            if !same { continue; }
            for read in facts.call_publications {
                if !session.specializations.validated_calls.contains(callKey(read, read.evidence)) { same = false; break; }
            }
            if !same { continue; }
            for fact in facts.plain_facts {
                let actual = session.specializations.plain_nominals.get(fact.key);
                if fact.read && !fact.present || actual == null { same = false; break; }
                { let optional_source_31 .= actual; if optional_source_31 { let current .= optional_source_31; if current != fact.plain { same = false; break; }  } }
            }
            if !same { continue; }
            let result, error = copyResult(record.value); if error != blot_error::Error.none { return blot_support::none<Value>(), error; }
            g.refinement_stats.local_hits++; g.refinement_stats.collected_removed += facts.collected;
            g.refinement_stats.nodes_removed += facts.solver_nodes; return blot_support::some(result), blot_error::Error.none;
        }
     } }
    return blot_support::none<Value>(), blot_error::Error.none;
}
fn record<G>(g: G&, root: Root, expected: u32, seeds: const blot_eval_type_evidence::Mapping[:],
    rows: const blot_eval_type_evidence::RowMapping[:], result: Value, tape: blot_reuse_specialization_receipt::Tape&,
    observed: Observation, before_values: i64, before_children: i64, before_steps: i64) -> Error {
    { let optional_source_30 .= g.refinement_owner; if optional_source_30 { let owner .= optional_source_30;
        let error = recordOwned(g, owner.refinement_queries, root, expected, seeds, rows, result, tape, observed, before_values, before_children, before_steps);
        storageStats(g, owner.refinement_queries); return error;
     } }
    g.refinement_stats.record_declines[0]++; return blot_error::Error.none;
}
fn recordOwned<G>(g: G&, table: Table&, root: Root, expected: u32, seeds: const blot_eval_type_evidence::Mapping[:],
    rows: const blot_eval_type_evidence::RowMapping[:], result: Value, tape: blot_reuse_specialization_receipt::Tape&,
    observed: Observation, before_values: i64, before_children: i64, before_steps: i64) -> Error {
    if !queryOwners(g.evaluator.units, root, tape.sources.items) { g.refinement_stats.record_declines[1]++; return blot_error::Error.none; }
    if g.evaluator.has_generative_sources {
        let generative, error = generativeQuery(g.evaluator.units, root, tape.sources.items); if error != blot_error::Error.none { return error; }
        if generative { g.refinement_stats.record_declines[2]++; return blot_error::Error.none; }
    }
    match root { body body => { tape.sources.push(body.target); }, _ => {} }
    let facts, error = tape.finish(Dependencies {
        input: 0, expected: 0, selected: 0, options: g.evaluator.options, depth: g.evaluator.depth,
        values_before: before_values, children_before: before_children,
        values_added: g.evaluator.storage.values.len - before_values,
        children_added: g.evaluator.storage.children.len - before_children,
        steps: g.evaluator.steps - before_steps, collected: tape.collected, source_scopes: observed.scopes, solver_nodes: observed.nodes,
        complete: observed.complete && observed.regions == 1 && result.selected.len == 0 &&
            g.evaluator.storage.values.len == before_values && g.evaluator.storage.children.len == before_children &&
            g.evaluator.steps == before_steps && tape.views.len == 0,
        sources: [], scalar_reads: [], call_reads: [], call_publications: [], views: [], plain_facts: [],
     ..});
    if error != blot_error::Error.none { return error; }
    var builder = table.begin(Key { root, expected, copySeeds(seeds), copyRows(rows), facts.options, facts.depth , ..});
    builder.read(facts);
    let output, error = copyResult(result); if error != blot_error::Error.none { builder.abort(); return error; }
    builder.stage(output); var candidate = builder.complete(); builder.abort();
    if !candidate.present { g.refinement_stats.record_declines[3]++; return blot_error::Error.none; }
    let prepared, error = table.prepare(candidate.value);
    if error != blot_error::Error.none { candidate.value.abort(); return error; }
    if !prepared.present { candidate.value.abort(); g.refinement_stats.record_declines[4]++; return blot_error::Error.none; }
    let handle = table.publish(prepared.value, candidate.value); candidate.value.abort();
    g.refinement_stats.recorded++; g.refinement_stats.complete++; return blot_error::Error.none;
}
recursive fn sameShape(left: blot_reuse_code_expectation::View, l: u32, right: blot_reuse_code_expectation::View, r: u32,
    depth: i64, budget: i64&) -> bool {
    if depth >= 1024 || budget == 0 || l >= left.nodes.len || r >= right.nodes.len { return false; }
    budget--; if l == 0 || r == 0 { return l == 0 && r == 0; }
    let a = left.node(l); let b = right.node(r); if a.tag != b.tag { return false; }
    match a.tag {
        projection, scoped,
        forall, existential,
        bound => { return false; },
        absent, unit, boolean,
        unsigned32, floating32,
        never, erased_proof => { return true; },
        usage => { return a.b == b.b && sameShape(left, a.a, right, b.a, depth + 1, budget); },
        type_constructor => { return a.a == b.a && a.b == b.b; },
        function => { return sameShape(left, a.a, right, b.a, depth + 1, budget) && sameShape(left, a.b, right, b.b, depth + 1, budget); },
        array, list, cursor,
        resolver, provider => { return sameShape(left, a.a, right, b.a, depth + 1, budget); },
        state_provider => { return sameShape(left, a.a, right, b.a, depth + 1, budget) &&
            sameShape(left, a.b, right, b.b, depth + 1, budget) && sameShape(left, a.c, right, b.c, depth + 1, budget); },
        product, record, nominal => {
            if a.tag == blot_eval_type_evidence::Tag.nominal && (a.a != b.a || a.b != b.b) { return false; }
            let lc = left.children(l); let rc = right.children(r); if lc.len != rc.len { return false; }
            for child, index in lc {
                if a.tag == blot_eval_type_evidence::Tag.record && index % 2 == 0 { if child != rc[index] { return false; } }
                else if !sameShape(left, child, right, rc[index], depth + 1, budget) { return false; }
            }
            return true;
        },
    }
}

// The enclosing query state, old metadata and gate stay borrowed for the whole
// candidate. Imports and all destinations are prepared before publications.
fn lookup<G>(g: G&, root: Root, shape: blot_reuse_code_expectation::View, expected: u32,
    seeds: const blot_eval_type_evidence::Mapping[:], rows: const blot_eval_type_evidence::RowMapping[:]) -> blot_support::Option<Value>, Error {
    { let optional_source_29 .= g.query_state; if optional_source_29 { let state .= optional_source_29;
        { let optional_source_28 .= g.artifacts; if optional_source_28 { let owner .= optional_source_28;
            let result, error = lookupOwned(g, state, owner.refinement_queries, root, shape, expected, seeds, rows);
            storageStats(g, owner.refinement_queries); return result, error;
         } }
     } }
    return blot_support::none<Value>(), blot_error::Error.none;
}
fn lookupOwned<G,S>(g: G&, state: S&, destination: Table&, root: Root, shape: blot_reuse_code_expectation::View,
    expected: u32, seeds: const blot_eval_type_evidence::Mapping[:], rows: const blot_eval_type_evidence::RowMapping[:]) -> blot_support::Option<Value>, Error {
    let gate = state.gate; let ordinary = blot_eval_core_eval::Options { trace_runtime_dependencies: true , ..};
    if !gate.enabled || g.evaluator.receipt_tape != null || g.evaluator.options != ordinary || g.evaluator.depth != 0 ||
        !blot_support::same_slice_identity(gate.units, g.evaluator.units) || g.allocation_owner == 0 || state.allocation_owner != g.allocation_owner {
        decline(g, Reason.mode); return blot_support::none<Value>(), blot_error::Error.none;
    }
    assert(state.old.metadata.pools.present); let pools = state.old.metadata.pools.value;
    if !pools.bridge.present { return blot_support::none<Value>(), blot_error::Error.none; }
    let bridge = pools.bridge.value; let before_shape = blot_reuse_code_expectation::View { bridge.nodes, bridge.extra , ..};
    let table = state.old.metadata.refinement_queries;
    var cursor = table.candidates(rootFingerprint(root), blot_reuse_semantic_query_table::Order.oldest_first);
    loop {
        let position = cursor.next(); if !position.present { break; }
        g.refinement_stats.indexed_positions++;
        let prior = table.records[position.value]; if prior.key.root != root { continue; }
        g.refinement_stats.candidates++; let facts = prior.dependencies;
        if !facts.complete || facts.steps != 0 || facts.values_added != 0 || facts.children_added != 0 ||
            facts.views.len != 0 || facts.depth != g.evaluator.depth || facts.options != g.evaluator.options { decline(g, Reason.mode); continue; }
        let unit = rootUnit(root); var admitted = false;
        match root {
            body body => { admitted = gate.admitsLocalSource(body.target); },
            closure closure => { admitted = gate.admitsClosure(closure.unit, closure.catalog); },
        }
        if unit == 0 || unit > gate.structural_units.len || !admitted { decline(g, Reason.root); continue; }
        if !queryOwners(g.evaluator.units, root, facts.sources) || !rootOwner(pools.modules[unit - 1].module, root) { decline(g, Reason.source); continue; }
        var valid = true;
        for source in facts.sources {
            if source.unit == 0 || source.unit > pools.modules.len || !namedOwner(pools.modules[source.unit - 1].module, source.binding) { valid = false; break; }
        }
        if !valid { decline(g, Reason.source); continue; }
        if gate.has_generative_sources {
            let generated, error = generativeQuery(g.evaluator.units, root, facts.sources);
            if error != blot_error::Error.none { return blot_support::none<Value>(), error; }
            if generated { decline(g, Reason.source); continue; }
            var old_generated = false;
            let module = pools.modules[unit - 1].module;
            match root {
                body body => { let result, error = blot_reuse_source_value_template::generativeNamed(module, body.target.binding); if error != blot_error::Error.none { return blot_support::none<Value>(), error; } old_generated = result; },
                closure closure => { let result, error = blot_reuse_source_value_template::generativeClosure(module, closure.catalog); if error != blot_error::Error.none { return blot_support::none<Value>(), error; } old_generated = result; },
            }
            for source in facts.sources {
                if source.unit == 0 || source.unit > pools.modules.len { old_generated = true; break; }
                let result, error = blot_reuse_source_value_template::generativeNamed(pools.modules[source.unit - 1].module, source.binding);
                if error != blot_error::Error.none { return blot_support::none<Value>(), error; } if result { old_generated = true; break; }
            }
            if old_generated { decline(g, Reason.source); continue; }
        }
        let transitive = gate.admitsReceipt(facts); valid = transitive || gate.admitsRefinement(facts);
        if !valid { decline(g, Reason.source); continue; }
        var budget: i64 = 65536;
        if !sameShape(before_shape, prior.key.expected, shape, expected, 0, budget) { decline(g, Reason.shape); continue; }
        if seeds.len != prior.key.seeds.len || rows.len != prior.key.rows.len { decline(g, Reason.seed); continue; }
        let maps, error = state.pairedImporter(); if error != blot_error::Error.none { return blot_support::none<Value>(), error; }
        if !maps.enabled { continue; }
        for now, index in seeds {
            let old = prior.key.seeds[index]; let imported, error = maps.importEvidence(g, old.evidence);
            if error != blot_error::Error.none { return blot_support::none<Value>(), error; }
            if now.variable != old.variable || !imported.present || now.evidence != imported.value { valid = false; break; }
        }
        if valid {
            for now, index in rows {
                let old = prior.key.rows[index]; let imported, error = maps.importSemanticRow(g, old.evidence);
                if error != blot_error::Error.none { return blot_support::none<Value>(), error; }
                if now.variable != old.variable || !imported.present || now.evidence != imported.value { valid = false; break; }
            }
        }
        if !valid { decline(g, Reason.seed); continue; }
        for read in facts.scalar_reads {
            let actual = scalarEvidence(g.evaluator, read.target); var imported = blot_support::some(0 as u32);
            if read.evidence != 0 { let value, error = maps.importEvidence(g, read.evidence); if error != blot_error::Error.none { return blot_support::none<Value>(), error; } imported = value; }
            if !imported.present || imported.value != actual { valid = false; break; }
        }
        if !valid { decline(g, Reason.scalar); continue; }
        for read in facts.call_reads {
            let actual, error = maps.importEvidence(g, read.evidence); if error != blot_error::Error.none { return blot_support::none<Value>(), error; }
            if !actual.present { valid = false; break; }
            let present = g.evaluator.specializations.validated_calls.contains(callKey(read, actual.value));
            if present != read.present {
                if present { g.refinement_stats.call_became_present++; } else { g.refinement_stats.call_missing++; }
                valid = false; break;
            }
        }
        if !valid { decline(g, Reason.call); continue; }
        var plain = dictionary<u64,bool> {};
        for fact in facts.plain_facts {
            let unit = (fact.key >> 32) as u32;
            if unit == 0 || unit > gate.units.len || !gate.structural_units[unit - 1] { valid = false; break; }
            if fact.read {
                var present = false; var current = false;
                { let optional_source_27 .= plain.get(fact.key); if optional_source_27 { let found = optional_source_27; present = true; current = found;  }
                else { let optional_source_26 .= g.evaluator.specializations.plain_nominals.get(fact.key); if optional_source_26 { let found = optional_source_26; present = true; current = found;  } } }
                if fact.present && (!present || current != fact.plain) || !fact.present && present { valid = false; break; }
            } else { plain.insert(fact.key, fact.plain); }
        }
        if !valid { decline(g, Reason.plain); continue; }
        var next_facts, error = facts.clone(); if error != blot_error::Error.none { return blot_support::none<Value>(), error; }
        var output, error = copyResult(prior.value);
        if error != blot_error::Error.none { next_facts.deinit(); return blot_support::none<Value>(), error; }
        let mapped, error = mapReplay(g, maps, next_facts, output);
        if error != blot_error::Error.none { next_facts.deinit(); output.deinit(); return blot_support::none<Value>(), error; }
        if !mapped { next_facts.deinit(); output.deinit(); decline(g, Reason.import_); continue; }
        var builder = destination.begin(Key { root, expected, copySeeds(seeds), copyRows(rows), next_facts.options, next_facts.depth , ..});
        next_facts.values_before = g.evaluator.storage.values.len; next_facts.children_before = g.evaluator.storage.children.len;
        builder.read(next_facts);
        let owned_output, error = copyResult(output);
        if error != blot_error::Error.none { builder.abort(); output.deinit(); return blot_support::none<Value>(), error; }
        builder.stage(owned_output); var candidate = builder.complete(); builder.abort();
        if !candidate.present { output.deinit(); continue; }
        let prepared, error = destination.prepare(candidate.value);
        if error != blot_error::Error.none { candidate.value.abort(); output.deinit(); return blot_support::none<Value>(), error; }
        if !prepared.present { candidate.value.abort(); output.deinit(); continue; }
        // Builtin dictionary reservation precedes any replayed fact. The target
        // Goose runtime's recoverable allocation boundary remains to qualify.
        g.evaluator.specializations.validated_calls.reserve(g.evaluator.specializations.validated_calls.count + next_facts.call_publications.len);
        g.evaluator.specializations.plain_nominals.reserve(g.evaluator.specializations.plain_nominals.count + plain.count);
        for call in next_facts.call_publications {
            let key = callKey(call, call.evidence);
            if !g.evaluator.specializations.validated_calls.contains(key) { g.evaluator.proofs.proof_published++; }
            g.evaluator.specializations.validated_calls.insert(key, true);
        }
        for fact in plain.slots { if fact.tag != 0 { g.evaluator.specializations.plain_nominals.insert(fact.key, fact.val); } }
        let handle = destination.publish(prepared.value, candidate.value); candidate.value.abort();
        for read in facts.call_reads { if read.present { g.evaluator.proofs.proof_reused++; } }
        g.refinement_stats.hits++; if !transitive { g.refinement_stats.body_cutoff_hits++; }
        g.refinement_stats.recorded++; g.refinement_stats.complete++;
        g.refinement_stats.collected_removed += facts.collected; g.refinement_stats.nodes_removed += facts.solver_nodes;
        g.refinement_stats.publications += facts.call_publications.len; return blot_support::some(output), blot_error::Error.none;
    }
    return blot_support::none<Value>(), blot_error::Error.none;
}
fn mapReplay<G,M>(g: G&, maps: M&, facts: Dependencies&, output: Value&) -> bool, Error {
    for index in output.types.len {
        let imported, error = maps.importEvidence(g, output.types[index].evidence); if error != blot_error::Error.none { return false, error; }
        if !imported.present { return false, blot_error::Error.none; } output.types[index].evidence = imported.value;
    }
    for index in output.rows.len {
        let imported, error = maps.importSemanticRow(g, output.rows[index].evidence); if error != blot_error::Error.none { return false, error; }
        if !imported.present { return false, blot_error::Error.none; } output.rows[index].evidence = imported.value;
    }
    for index in facts.scalar_reads.len {
        if facts.scalar_reads[index].evidence == 0 { continue; }
        let imported, error = maps.importEvidence(g, facts.scalar_reads[index].evidence); if error != blot_error::Error.none { return false, error; }
        if !imported.present { return false, blot_error::Error.none; } facts.scalar_reads[index].evidence = imported.value;
    }
    for index in facts.call_reads.len {
        let imported, error = maps.importEvidence(g, facts.call_reads[index].evidence); if error != blot_error::Error.none { return false, error; }
        if !imported.present { return false, blot_error::Error.none; } facts.call_reads[index].evidence = imported.value;
    }
    for index in facts.call_publications.len {
        let imported, error = maps.importEvidence(g, facts.call_publications[index].evidence); if error != blot_error::Error.none { return false, error; }
        if !imported.present { return false, blot_error::Error.none; } facts.call_publications[index].evidence = imported.value;
    }
    return true, blot_error::Error.none;
}

struct ObservationOwner { lease: u32=0,generation: u64=0 }
struct ObservationOwnerState { value: Observation,generation: u64,live: bool=true }
reusable var observation_owner_slots: ObservationOwnerState[>..]=[];
var next_observation_owner_slots_generation: u64=1;
fn initObservationOwner() -> ObservationOwner,Error { if next_observation_owner_slots_generation==0xffffffffffffffff||observation_owner_slots.len>=0xffffffff { return ObservationOwner {..},blot_error::Error.out_of_memory; } let value=Observation {..}; let generation=next_observation_owner_slots_generation; next_observation_owner_slots_generation++; let at=observation_owner_slots.alloc_index(ObservationOwnerState {value,generation,true, ..}); return ObservationOwner {(at+1) as u32,generation, ..},blot_error::Error.none; }
fn borrow(self_: ObservationOwner) -> Observation? { if self_.lease==0||self_.lease-1>=observation_owner_slots.len { return null; } let slot: ObservationOwnerState& =observation_owner_slots[self_.lease-1]; if !slot.live||slot.generation!=self_.generation { return null; } return slot.value; }
fn deinit(self_: ObservationOwner&) { if self_.lease==0 { return; } let at=self_.lease-1; assert(at<observation_owner_slots.len&&observation_owner_slots[at].live&&observation_owner_slots[at].generation==self_.generation); let slot: ObservationOwnerState& =observation_owner_slots[at]; slot.value=Observation {..}; slot.live=false; observation_owner_slots.free(at); self_=ObservationOwner {..}; }
