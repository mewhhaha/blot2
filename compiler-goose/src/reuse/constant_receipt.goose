// Successful constant-slot receipts own ordered work and observations.
namespace blot_reuse_constant_receipt;
import std;
import dictionary;
import support.pooled_buffer;
import support.pooled_map;
import check.core;
import check.types;
import eval.core_eval;
import eval.type_evidence;
import eval.eval_collection_growth;
import reuse.specialization_receipt;
import backend.core_backend;
import support.error;
import support.host_layout;
import support.option;
import support.structural;
type Error = blot_error::Error;
type Session = blot_eval_core_eval::Session;
type BindingRef = blot_check_core::BindingRef;
type ValueId = u32;
type Span = blot_eval_eval_collection_growth::Span;
type Frontier = blot_eval_eval_collection_growth::Frontier;
type BufferEffect = blot_eval_eval_collection_growth::BufferEffect;
type ViewEffect = blot_reuse_specialization_receipt::ViewEffect;
let minimum_steps: i64 = 128;
let minimum_query_steps: i64 = 1024;
fn literal(module: const blot_check_core::Module&, id: u32) -> bool {
    if module.node(id).tag == blot_check_core::Tag.constant { return true; }
    if module.node(id).tag != blot_check_core::Tag.array { return false; }
    for child in module.children(id) { if module.node(child).tag != blot_check_core::Tag.constant { return false; } }
    return true;
}
fn recordable(module: const blot_check_core::Module&, root: u32, declared: u32) -> bool {
    if literal(module, root) { return false; }
    match module.types.node(declared).tag {
        unit, boolean, unsigned32,
        floating32, variable, projection,
        nominal, product, record,
        function, cursor, array,
        list, existential, forall => { return true; },
        _ => { return false; },
    }
}
fn hasProductiveRecord(records: const Record[:], floor: i64) -> bool {
    for record in records { if record.productive(floor) { return true; } } return false;
}
struct Resources { steps: i64 = 0, values: i64 = 0, children: i64 = 0, depth: i64 = 0, call_depth: i64 = 0 }
struct Read { target: BindingRef, value: ValueId, depth: i64 = 0, call_depth: i64 = 0 }
enum Source { named { target: BindingRef }, anonymous { unit: u32, catalog: u32 } }
struct Growth { mutations: u64, frontier: blot_support::Option<Frontier> }
enum QueryKind { inferred, entry, specialized, source, array_member, judgment }
enum JudgmentKind { match_, covariant, scheme, body }
struct Inputs {
    types: const blot_eval_type_evidence::Mapping[:] = default<const blot_eval_type_evidence::Mapping[:]>(), rows: const blot_eval_type_evidence::RowMapping[:] = default<const blot_eval_type_evidence::RowMapping[:]>(),
}
struct Judgment {
    kind: JudgmentKind, unit: u32, producer: u32 = 0, source: u32, root: u32 = 0,
    scheme: blot_check_types::Scheme = blot_check_types::Scheme {..}, closed_rows: blot_check_types::List = blot_check_types::List {..},
    allow_remaining: bool = false, matched: bool = true, inputs: Inputs = Inputs {..}, outputs: Inputs = Inputs {..},
    selected: const BindingRef[:] = default<const BindingRef[:]>(),
}
struct Query {
    kind: QueryKind, input: u32 = 0, expected: u32 = 0, selected: u32 = 0,
    target: BindingRef = BindingRef { 0, 0 , ..}, result: blot_eval_core_eval::SourceInterface = blot_eval_core_eval::SourceInterface {..},
    judgment: Judgment&? = null, depth: i64 = 0, call_depth: i64 = 0,
}
enum Event {
    work { value: Resources }, read { value: Read }, growth { value: Growth },
    view { value: ViewEffect }, query { value: Query& },
}
struct Record {
    buffers: const BufferEffect[:] = default<const BufferEffect[:]>(), ordered_reads: bool = false, values_before: i64 = 0,
    target: BindingRef, value: ValueId, options: blot_eval_core_eval::Options,
    events: Event[:], sources: Source[:], inputs: Inputs = Inputs {..}, outputs: Inputs&? = null,
}
reusable[] var owned_buffers: BufferEffect[>..] = [];
fn copyOwned(source: const BufferEffect[:]) -> BufferEffect[:] {
    if source.len == 0 { return default<BufferEffect[:]>(); } let out = owned_buffers.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const BufferEffect[:]) {
    if source.len == 0 { return; } owned_buffers.free_slice(source);
}
reusable[] var owned_events: Event[>..] = [];
fn copyOwned(source: const Event[:]) -> Event[:] {
    if source.len == 0 { return default<Event[:]>(); } let out = owned_events.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const Event[:]) {
    if source.len == 0 { return; } owned_events.free_slice(source);
}
reusable[] var owned_sources: Source[>..] = [];
fn copyOwned(source: const Source[:]) -> Source[:] {
    if source.len == 0 { return default<Source[:]>(); } let out = owned_sources.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const Source[:]) {
    if source.len == 0 { return; } owned_sources.free_slice(source);
}
reusable[] var owned_types: blot_eval_type_evidence::Mapping[>..] = [];
fn copyOwned(source: const blot_eval_type_evidence::Mapping[:]) -> blot_eval_type_evidence::Mapping[:] {
    if source.len == 0 { return default<blot_eval_type_evidence::Mapping[:]>(); } let out = owned_types.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const blot_eval_type_evidence::Mapping[:]) {
    if source.len == 0 { return; } owned_types.free_slice(source);
}
reusable[] var owned_rows: blot_eval_type_evidence::RowMapping[>..] = [];
fn copyOwned(source: const blot_eval_type_evidence::RowMapping[:]) -> blot_eval_type_evidence::RowMapping[:] {
    if source.len == 0 { return default<blot_eval_type_evidence::RowMapping[:]>(); } let out = owned_rows.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const blot_eval_type_evidence::RowMapping[:]) {
    if source.len == 0 { return; } owned_rows.free_slice(source);
}
reusable[] var owned_selected: BindingRef[>..] = [];
fn copyOwned(source: const BindingRef[:]) -> BindingRef[:] {
    if source.len == 0 { return default<BindingRef[:]>(); } let out = owned_selected.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const BindingRef[:]) {
    if source.len == 0 { return; } owned_selected.free_slice(source);
}
reusable var queries: Query[>..] = [];
reusable var judgments: Judgment[>..] = [];
reusable var output_inputs: Inputs[>..] = [];
fn cloneMutable(self_: Inputs) -> blot_eval_type_evidence::Mapping[:], blot_eval_type_evidence::RowMapping[:], Error {
    return copyOwned(self_.types), copyOwned(self_.rows), blot_error::Error.none;
}
fn clone(self_: Inputs) -> Inputs, Error { return Inputs { copyOwned(self_.types), copyOwned(self_.rows) , ..}, blot_error::Error.none; }
fn deinit(self_: Inputs&) { releaseOwned(self_.types); releaseOwned(self_.rows); self_ = Inputs {..}; }
fn clone(self_: Judgment) -> Judgment&?, Error {
    let inputs, e1 = self_.inputs.clone(); if e1 != blot_error::Error.none { return null, e1; }
    let outputs, e2 = self_.outputs.clone();
    if e2 != blot_error::Error.none { var partial = inputs; partial.deinit(); return null, e2; }
    var value = self_; value.inputs = inputs; value.outputs = outputs; value.selected = copyOwned(self_.selected);
    let index = judgments.alloc_index(value); return judgments[index], blot_error::Error.none;
}
fn destroy(self_: Judgment&) {
    self_.inputs.deinit(); self_.outputs.deinit(); releaseOwned(self_.selected);
    let index = judgments.index_of(self_); assert(index >= 0); judgments.free(index);
}
fn ownedBytes(self_: Judgment) -> i64 {
    return blot_host_layout::constant_judgment + bytes_of(self_.inputs.types).len + bytes_of(self_.outputs.types).len +
        bytes_of(self_.inputs.rows).len + bytes_of(self_.outputs.rows).len + bytes_of(self_.selected).len;
}
fn clone(self_: Query) -> Query&?, Error {
    var value = self_;
    { let optional_source_53 .= self_.judgment; if optional_source_53 { let judgment .= optional_source_53;
        let cloned, error = judgment.clone(); if error != blot_error::Error.none { return null, error; }
        assert(cloned != null); value.judgment = cloned;
     } }
    let index = queries.alloc_index(value); return queries[index], blot_error::Error.none;
}
fn destroy(self_: Query&) {
    { let optional_source_52 .= self_.judgment; if optional_source_52 { let judgment .= optional_source_52; judgment.destroy();  } }
    let index = queries.index_of(self_); assert(index >= 0); queries.free(index);
}
fn ownedBytes(self_: Query) -> i64 {
    var bytes = blot_host_layout::constant_query; { let optional_source_51 .= self_.judgment; if optional_source_51 { let judgment .= optional_source_51; bytes += judgment.ownedBytes();  } } return bytes;
}
fn clone(self_: Event) -> Event, Error {
    match self_ {
        query query => { let value, error = query.value.clone(); if error != blot_error::Error.none { return default<Event>(), error; } assert(value != null); return Event.query { value , ..}, blot_error::Error.none; },
        _ => { return self_, blot_error::Error.none; },
    }
}
fn deinit(self_: Event&) { match self_ { query query => { query.value.destroy(); }, _ => {} } }
fn sourceSteps(self_: Record) -> i64 {
    var total: i64 = 0;
    for event in self_.events { match event { work work => { blot_reuse_specialization_receipt::addBytes(total, work.value.steps); }, _ => {} } }
    return total;
}
fn productive(self_: Record, floor: i64) -> bool {
    let steps = self_.sourceSteps(); if steps < floor { return false; }
    if steps < minimum_query_steps { for event in self_.events { match event { query => { return false; }, _ => {} } } }
    return true;
}
fn ownedBytes(self_: Record) -> i64 {
    var total = blot_host_layout::constant_record + bytes_of(self_.buffers).len + self_.events.len * blot_host_layout::constant_event + bytes_of(self_.sources).len +
        bytes_of(self_.inputs.types).len + bytes_of(self_.inputs.rows).len;
    for event in self_.events { match event { query query => { total += query.value.ownedBytes(); }, _ => {} } }
    { let optional_source_50 .= self_.outputs; if optional_source_50 { let outputs .= optional_source_50; total += blot_host_layout::constant_inputs + bytes_of(outputs.types).len + bytes_of(outputs.rows).len;  } }
    return total;
}
fn deinit(self_: Record&) {
    releaseOwned(self_.buffers); for &event in self_.events { event.deinit(); } releaseOwned(self_.events); releaseOwned(self_.sources);
    self_.inputs.deinit();
    { let optional_source_49 .= self_.outputs; if optional_source_49 { let outputs .= optional_source_49; outputs.deinit(); let index = output_inputs.index_of(outputs); assert(index >= 0); output_inputs.free(index);  } }
    self_ = default<Record>();
}
fn clone(self_: Record) -> Record, Error {
    var result = self_; result.buffers = []; result.events = []; result.sources = []; result.inputs = Inputs {..}; result.outputs = null;
    result.buffers = copyOwned(self_.buffers);
    let events = owned_events.alloc_slice(self_.events.len);
    for index in self_.events.len { events[index] = default<Event>(); }
    result.events = events;
    for event, index in self_.events {
        let value, error = event.clone(); if error != blot_error::Error.none { result.deinit(); return default<Record>(), error; } events[index] = value;
    }
    result.sources = copyOwned(self_.sources);
    let inputs, error = self_.inputs.clone(); if error != blot_error::Error.none { result.deinit(); return default<Record>(), error; } result.inputs = inputs;
    { let optional_source_48 .= self_.outputs; if optional_source_48 { let outputs .= optional_source_48;
        let inputs, error = outputs.clone(); if error != blot_error::Error.none { result.deinit(); return default<Record>(), error; }
        let index = output_inputs.alloc_index(inputs); result.outputs = output_inputs[index];
     } }
    return result, blot_error::Error.none;
}
enum Reason { mode, source, resource, ready, graph, read, imported }
struct Stats {
    retries: i64 = 0, reasons: i64[7] = [0; 7], lookups: i64 = 0, candidates: i64 = 0,
    reused: i64 = 0, scalar_reused: i64 = 0, recorded: i64 = 0, declined: i64 = 0,
    source_steps_replayed: i64 = 0, values_imported: i64 = 0, queries_recorded: i64 = 0,
    queries_replayed: i64 = 0, owned_payload_bytes: i64 = 0, lookup_comparisons: i64 = 0,
    graph_values_examined: i64 = 0, graph_index_bytes: i64 = 0,
}
struct Lookup { value: ValueId, outputs: Inputs }
struct Provider { context: blot_backend_core_backend::Generator& }
fn lookup(self_: Provider, session: Session&, target: BindingRef, inputs: Inputs) -> blot_support::Option<Lookup>, Error {
    return self_.context.lookupConstant(session, target, inputs);
}
fn sourceMappingKey(module: const blot_check_core::Module&, id: u32) -> bool {
    if id == 0 || id >= module.types.nodes.len { return false; }
    let node = module.types.node(id); if node.tag == blot_check_types::Tag.variable { return true; }
    if node.tag != blot_check_types::Tag.bound || node.b != 0 { return false; }
    for owner in module.types.nodes {
        if owner.tag != blot_check_types::Tag.forall && owner.tag != blot_check_types::Tag.existential { continue; }
        for binder, ordinal in module.types.list(blot_check_types::List { owner.b, owner.c , ..}) {
            if binder == id && node.a == ordinal { return true; }
        }
    }
    for value, source in module.nodes {
        if value.tag != blot_check_core::Tag.package_unpack { continue; }
        let opening = module.packageOpening(source as u32);
        for binder, ordinal in module.types.list(opening.binders) {
            if binder == id && node.a == ordinal && node.c == value.b { return true; }
        }
    }
    return false;
}
fn validView<S>(snapshot: const S&, effect: ViewEffect) -> bool {
    if effect.value == 0 || effect.selected == 0 || effect.value >= snapshot.values.len || effect.selected >= snapshot.values.len || snapshot.value_evidence[effect.selected] != effect.evidence { return false; }
    var left = snapshot.values[effect.value]; var right = snapshot.values[effect.selected];
    if left.len == 0 { left.start = 0; } if right.len == 0 { right.start = 0; }
    if left.kind == blot_eval_eval_values::ValueKind.closure && right.kind == blot_eval_eval_values::ValueKind.closure {
        var before = snapshot.closures[left.bits]; var after = snapshot.closures[right.bits];
        if before.mappings.len != after.mappings.len || before.row_mappings.len != after.row_mappings.len { return false; }
        if snapshot.type_mappings[before.mappings.start..before.mappings.start + before.mappings.len] != snapshot.type_mappings[after.mappings.start..after.mappings.start + after.mappings.len] { return false; }
        if snapshot.row_mappings[before.row_mappings.start..before.row_mappings.start + before.row_mappings.len] != snapshot.row_mappings[after.row_mappings.start..after.row_mappings.start + after.row_mappings.len] { return false; }
        before.mappings.start = 0; after.mappings.start = 0; before.row_mappings.start = 0; after.row_mappings.start = 0;
        if before != after { return false; } left.bits = 0; right.bits = 0;
    }
    if left != right { return false; }
    let lr = snapshot.value_records[effect.value]; let rr = snapshot.value_records[effect.selected];
    if lr == 0 || rr == 0 { return lr == rr; }
    let before = snapshot.record_layouts[lr]; let after = snapshot.record_layouts[rr];
    return snapshot.field_names[before.start..before.start + before.len] == snapshot.field_names[after.start..after.start + after.len];
}
fn position(session: const Session&) -> Resources { Resources { steps: session.steps, values: session.constantValueCount(), children: session.constantChildCount() } }
fn queryBudgets(session: const Session&) -> i64[8] {
    var enabled: i64 = 0; if session.specializations.canonical_specializations.enabled { enabled = 1; }
    return [session.specializations.canonical_specializations.examined_words,
        session.specializations.canonical_specializations.retained_words, enabled,
        session.specializations.lexical_inputs.examined_words, session.specializations.lexical_inputs.retained_words,
        session.specializations.lexical_inputs.interface_visits, session.specializations.lexical_inputs.inputs.len,
        session.specializations.canonical_specializations.table.records.len];
}
fn admittedGraph<S>(snapshot: const S&, value: u32) -> bool {
    if value >= snapshot.values.len { return false; }
    match snapshot.values[value].kind {
        scalar, product, record,
        nominal, array, list,
        cursor, closure, package => { return true; },
        _ => { return false; },
    }
}

struct ViewKey { value: u32, evidence: u32 }
struct RecorderTables {
    events: RecorderEventsBuffer&, sources: RecorderSourcesBuffer&, view_inputs: RecorderViewInputsMap&,
    ready_reads: RecorderReadyReadsMap&, cached_views: RecorderCachedViewsMap&,
    owned_children: RecorderOwnedChildrenBuffer&, buffers: RecorderBuffersBuffer&,
}
struct Recorder {
    events: RecorderEventsBuffer&, sources: RecorderSourcesBuffer&, view_inputs: RecorderViewInputsMap&,
    ready_reads: RecorderReadyReadsMap&, cached_views: RecorderCachedViewsMap&,
    inputs: Inputs = Inputs {..}, owns_inputs: bool = false, mark: Resources,
    values_before: i64, base_depth: i64, base_calls: i64, inference_serial: u64,
    collection_serial: u64, child_mark: i64, owned_children: RecorderOwnedChildrenBuffer&,
    growth_mutations: u64 = 0, buffers: RecorderBuffersBuffer&, summary_transitions: i64,
    summary_work: i64, summary_exhausted: bool, query_budgets: i64[8],
    depth: i64 = 0, call_depth: i64 = 0, eligible: bool = true,
}
fn init(session: const Session&, t: RecorderTables) -> Recorder {
    return Recorder {
        events: t.events, sources: t.sources, view_inputs: t.view_inputs, ready_reads: t.ready_reads,
        cached_views: t.cached_views, mark: position(session), values_before: session.storage.values.len,
        base_depth: session.depth, base_calls: session.call_depth, inference_serial: session.constant_inference_serial,
        collection_serial: session.storage.collection_buffers.mutation_serial, child_mark: session.storage.children.len,
        owned_children: t.owned_children, buffers: t.buffers, summary_transitions: session.summary_transitions,
        summary_work: session.summary_graph_work, summary_exhausted: session.summary_exhausted, query_budgets: queryBudgets(session),
     ..};
}
fn captureInputs(self_: Recorder&, inputs: Inputs) -> Error {
    let owned, error = inputs.clone(); if error != blot_error::Error.none { return error; }
    if self_.owns_inputs { self_.inputs.deinit(); } self_.inputs = owned; self_.owns_inputs = true; return blot_error::Error.none;
}
fn deinit(self_: Recorder&) {
    if self_.owns_inputs { self_.inputs.deinit(); self_.owns_inputs = false; }
    for &event in self_.events.items { event.deinit(); } self_.events.clear(); self_.sources.clear();
    self_.view_inputs.clear(); self_.ready_reads.clear(); self_.cached_views.clear(); self_.owned_children.clear(); self_.buffers.clear();
}
fn view(self_: Recorder&, input: u32) -> Error {
    if !self_.eligible || self_.view_inputs.contains(input) { return blot_error::Error.none; }
    if self_.view_inputs.count >= 4096 { self_.eligible = false; return blot_error::Error.none; }
    self_.view_inputs.insert(input, false); return blot_error::Error.none;
}
fn prepareView(self_: Recorder&) -> Error {
    if self_.eligible {
        // Exercise the upcoming two append slots while no view publication
        // has occurred. Both elements are inert work records and are removed.
        self_.events.push(Event.work { Resources {} , ..}); self_.events.push(Event.work { Resources {} , ..});
        self_.events.pop_n(2);
    }
    return blot_error::Error.none;
}
fn cacheView(self_: Recorder&, session: const Session&, effect: ViewEffect) -> Error {
    if !self_.eligible { return blot_error::Error.none; }
    let error = self_.flush(session); if error != blot_error::Error.none { return error; }
    if !self_.eligible { return blot_error::Error.none; }
    if self_.cached_views.count >= 16384 { self_.eligible = false; return blot_error::Error.none; }
    let key = ViewKey { effect.value, effect.evidence , ..};
    { let optional_source_47 .= self_.cached_views.get(key); if optional_source_47 { let known = optional_source_47;
        if !effect.existed || known != effect.selected { self_.eligible = false; }
     } else { self_.cached_views.insert(key, effect.selected); self_.events.push(Event.view { effect , ..}); } }
    { let optional_source_46 .= self_.view_inputs.get(effect.value); if optional_source_46 { let complete .= optional_source_46; complete = true;  }
    else { assert(false); } }
    return blot_error::Error.none;
}
fn ownsChildren(self_: const Recorder&, session: const Session&, span: Span) -> bool {
    let end = span.start as i64 + span.len;
    if span.start >= self_.child_mark && end <= session.storage.children.len { return true; }
    for owned in self_.owned_children.items { if span.start >= owned.start && end <= owned.start as i64 + owned.len { return true; } }
    return false;
}
fn viewsEscape(self_: Recorder&, session: const Session&, result: u32) -> bool, Error {
    if self_.view_inputs.count == 0 && self_.growth_mutations == 0 { return false, blot_error::Error.none; }
    var pending: u32[>..<] = []; var seen = dictionary<u32,bool> {}; pending.push(result);
    for event in self_.events.items {
        match event {
            read dependency => { pending.push(dependency.value.value); },
            query query => { if query.value.input != 0 { pending.push(query.value.input); } if query.value.selected != 0 { pending.push(query.value.selected); } },
            _ => {},
        }
    }
    while pending.len != 0 {
        let id = pending[pending.len - 1]; pending.resize(pending.len - 1);
        if ::contains(seen,id) { continue; }
        { let optional_source_45 .= self_.view_inputs.get(id); if optional_source_45 { let complete .= optional_source_45; if !complete { return true, blot_error::Error.none; }  } }
        if seen.count >= 65536 { return true, blot_error::Error.none; } ::insert(seen,id, true);
        let info = session.valueInfo(id);
        if info.kind == blot_eval_eval_values::ValueKind.array || info.kind == blot_eval_eval_values::ValueKind.list {
            { let optional_source_44 .= session.storage.collection_buffers.buffers.get(Span { info.start, info.len , ..}); if optional_source_44 { let buffer = optional_source_44;
                if self_.ownsChildren(session, buffer) {
                    var duplicate = false;
                    for effect in self_.buffers.items { let prior = session.valueInfo(effect.value); if prior.start == info.start && prior.len == info.len { duplicate = true; } }
                    if !duplicate { self_.buffers.push(BufferEffect { id, Frontier { info.start - buffer.start, buffer.len , ..} , ..}); }
                }
             } }
        }
        let children = session.valueChildren(id);
        if pending.len > 65536 || children.len > 65536 - pending.len { return true, blot_error::Error.none; }
        pending.append(children);
    }
    var count: i64 = 0; let length = self_.events.len;
    for index in length {
        let event = self_.events.items[index]; var keep = true;
        match event { view view => { keep = ::contains(seen,view.value.value); }, _ => {} }
        if keep { self_.events.items[count] = event; count++; }
    }
    self_.events.resize(count); return false, blot_error::Error.none;
}
fn observe(self_: Recorder&, session: const Session&) {
    let depth = session.depth - self_.base_depth; let calls = session.call_depth - self_.base_calls;
    if depth > self_.depth { self_.depth = depth; } if calls > self_.call_depth { self_.call_depth = calls; }
}
fn canGrow(self_: const Recorder&, session: const Session&, before: Span) -> bool {
    if !self_.eligible || self_.collection_serial == 0xffffffffffffffff || self_.collection_serial != session.storage.collection_buffers.mutation_serial { return false; }
    if before.len != 0 && !self_.ownsChildren(session, before) { return false; }
    { let optional_source_43 .= session.storage.collection_buffers.buffers.get(before); if optional_source_43 { let buffer = optional_source_43; if !self_.ownsChildren(session, buffer) { return false; }  } }
    return true;
}
fn grew(self_: Recorder&, session: const Session&) {
    assert(self_.collection_serial + 1 == session.storage.collection_buffers.mutation_serial);
    self_.collection_serial++; self_.growth_mutations++;
}
fn source(self_: Recorder&, target: BindingRef) -> Error { self_.observed(Source.named { target , ..}) }
fn closure(self_: Recorder&, unit: u32, catalog: u32) -> Error { self_.observed(Source.anonymous { unit, catalog , ..}) }
fn observed(self_: Recorder&, target: Source) -> Error {
    if !self_.eligible { return blot_error::Error.none; }
    for old in self_.sources.items { if old == target { return blot_error::Error.none; } }
    if self_.sources.len >= 4096 { self_.eligible = false; return blot_error::Error.none; }
    self_.sources.push(target); return blot_error::Error.none;
}
fn flush(self_: Recorder&, session: const Session&) -> Error {
    if !self_.eligible { return blot_error::Error.none; }
    let now = position(session);
    let work = Resources { now.steps - self_.mark.steps, now.values - self_.mark.values,
        now.children - self_.mark.children, self_.depth, self_.call_depth , ..};
    if self_.events.len >= 16384 { self_.eligible = false; return blot_error::Error.none; }
    if session.storage.children.len != self_.child_mark {
        self_.owned_children.push(Span { self_.child_mark as u32, (session.storage.children.len - self_.child_mark) as u32 , ..});
    }
    var appended = false;
    if self_.events.len != 0 {
        let index = self_.events.len - 1;
        match self_.events.items[index] {
            work previous => {
                var combined = previous.value; combined.steps += work.steps; combined.values += work.values; combined.children += work.children;
                if work.depth > combined.depth { combined.depth = work.depth; } if work.call_depth > combined.call_depth { combined.call_depth = work.call_depth; }
                self_.events.items[index] = Event.work { combined , ..}; appended = true;
            },
            _ => {},
        }
    }
    if !appended { self_.events.push(Event.work { work , ..}); }
    self_.reset(session); return blot_error::Error.none;
}
fn reset(self_: Recorder&, session: const Session&) { self_.mark = position(session); self_.child_mark = session.storage.children.len; self_.depth = 0; self_.call_depth = 0; }
fn stable(self_: const Recorder&, session: const Session&) -> bool {
    return session.constant_inference_serial != 0xffffffffffffffff && session.constant_inference_serial == self_.inference_serial &&
        session.summary_transitions == self_.summary_transitions && session.summary_graph_work == self_.summary_work &&
        session.summary_exhausted == self_.summary_exhausted && self_.query_budgets == queryBudgets(session);
}
fn beforeRead(self_: Recorder&, session: const Session&) -> Error { if !self_.stable(session) { self_.eligible = false; } return self_.flush(session); }
fn read(self_: Recorder&, session: const Session&, target: BindingRef, value: ValueId) -> Error {
    if self_.ready_reads.count >= 4096 { self_.eligible = false; }
    if self_.eligible {
        { let optional_source_42 .= self_.ready_reads.get(target); if optional_source_42 { let known = optional_source_42; if known != value { self_.eligible = false; }  }
        else {
            self_.ready_reads.insert(target, value);
            self_.events.push(Event.read { Read { target, value, session.depth - self_.base_depth, session.call_depth - self_.base_calls } , ..});
        } }
    }
    self_.inference_serial = session.constant_inference_serial; self_.summary_transitions = session.summary_transitions;
    self_.summary_work = session.summary_graph_work; self_.summary_exhausted = session.summary_exhausted;
    self_.query_budgets = queryBudgets(session); self_.reset(session); return blot_error::Error.none;
}
fn query(self_: Recorder&, session: const Session&, observation: Query) -> Error {
    if !self_.eligible || session.constant_inference_serial == 0xffffffffffffffff { return blot_error::Error.none; }
    var owned = observation; owned.depth = session.depth - self_.base_depth; owned.call_depth = session.call_depth - self_.base_calls;
    let payload, error = owned.clone(); if error != blot_error::Error.none { return error; } assert(payload != null);
    self_.events.push(Event.query { payload , ..});
    self_.inference_serial = session.constant_inference_serial; self_.summary_transitions = session.summary_transitions;
    self_.summary_work = session.summary_graph_work; self_.summary_exhausted = session.summary_exhausted;
    self_.query_budgets = queryBudgets(session); self_.collection_serial = session.storage.collection_buffers.mutation_serial;
    self_.reset(session); return blot_error::Error.none;
}
fn finish(self_: Recorder&, session: const Session&, target: BindingRef, value: ValueId, outputs: Inputs) -> blot_support::Option<Record>, Error { let allocation_error=self_.failure(); if allocation_error!=blot_error::Error.none { return blot_support::none<Record>(),allocation_error; }
    let error = self_.flush(session); if error != blot_error::Error.none { return blot_support::none<Record>(), error; }
    if !self_.eligible || self_.collection_serial == 0xffffffffffffffff || session.storage.collection_buffers.mutation_serial != self_.collection_serial ||
        session.constant_inference_serial == 0xffffffffffffffff || session.constant_inference_serial != self_.inference_serial ||
        session.summary_transitions != self_.summary_transitions || session.summary_graph_work != self_.summary_work || session.summary_exhausted != self_.summary_exhausted ||
        self_.query_budgets != queryBudgets(session) { return blot_support::none<Record>(), blot_error::Error.none; }
    var steps: i64 = 0;
    for event in self_.events.items { match event { work work => { steps += work.value.steps; }, _ => {} } }
    if steps < session.minimum_constant_steps { return blot_support::none<Record>(), blot_error::Error.none; }
    if steps < minimum_query_steps { for event in self_.events.items { match event { query => { return blot_support::none<Record>(), blot_error::Error.none; }, _ => {} } } }
    if !admittedGraph(session.snapshot(), value) { return blot_support::none<Record>(), blot_error::Error.none; }
    for event in self_.events.items {
        match event { read dependency => { if !admittedGraph(session.snapshot(), dependency.value.value) { return blot_support::none<Record>(), blot_error::Error.none; } }, _ => {} }
    }
    let info = session.valueInfo(value);
    if (info.kind == blot_eval_eval_values::ValueKind.array || info.kind == blot_eval_eval_values::ValueKind.list) && info.len > steps / 4 { return blot_support::none<Record>(), blot_error::Error.none; }
    let escaping, error = self_.viewsEscape(session, value); if error != blot_error::Error.none { return blot_support::none<Record>(), error; }
    if escaping { return blot_support::none<Record>(), blot_error::Error.none; }
    if self_.growth_mutations != 0 {
        var growth = Growth { mutations: self_.growth_mutations , ..}; var plain = true;
        for event in self_.events.items { match event { read, view, query => { plain = false; }, _ => {} } }
        if plain && self_.buffers.len == 1 && self_.buffers.items[0].value == value &&
            (info.kind == blot_eval_eval_values::ValueKind.array || info.kind == blot_eval_eval_values::ValueKind.list) {
            var primitive = true;
            for child in session.valueChildren(value) { if session.valueInfo(child).kind != blot_eval_eval_values::ValueKind.scalar { primitive = false; } }
            if primitive { growth.frontier = blot_support::some(self_.buffers.items[0].frontier); self_.buffers.clear(); }
        }
        self_.events.push(Event.growth { growth , ..});
    }
    // Transfer Event ownership to persistent typed runs. Query objects already
    // belong to their reusable pool; no borrowed lexical reference is retained.
    var result = Record {
        buffers: copyOwned(self_.buffers.items), ordered_reads: true, values_before: self_.values_before,
        target: target, value: value, options: session.options, events: copyOwned(self_.events.items), sources: copyOwned(self_.sources.items),
     ..};
    self_.buffers.clear(); self_.events.clear(); self_.sources.clear();
    let inputs, error = self_.inputs.clone(); if error != blot_error::Error.none { result.deinit(); return blot_support::none<Record>(), error; }
    result.inputs = inputs;
    if self_.inputs.types != outputs.types || self_.inputs.rows != outputs.rows {
        let payload, error = outputs.clone(); if error != blot_error::Error.none { result.deinit(); return blot_support::none<Record>(), error; }
        let index = output_inputs.alloc_index(payload); result.outputs = output_inputs[index];
    }
    return blot_support::some(result), blot_error::Error.none;
}
fn withRecorder<C,F>(session: const Session&,context: C&) -> Error { var owner,error=initRecorderOwner(session); if error!=blot_error::Error.none { return error; } let recorder=owner.borrow(); assert(recorder); let result=F(context,recorder); let allocation_error=recorder.failure(); owner.deinit(); if result!=blot_error::Error.none { return result; } return allocation_error; }

struct RecorderEventsBuffer { storage: Event[:]=default<Event[:]>(),items: Event[:]=default<Event[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderEventsBuffer: Event[>..]=[];
fn ensure(self_: RecorderEventsBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderEventsBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderEventsBuffer&,value: Event) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderEventsBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderEventsBuffer&,values: const Event[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderEventsBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderEventsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderEventsBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderEventsBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderEventsBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecorderSourcesBuffer { storage: Source[:]=default<Source[:]>(),items: Source[:]=default<Source[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderSourcesBuffer: Source[>..]=[];
fn ensure(self_: RecorderSourcesBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderSourcesBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderSourcesBuffer&,value: Source) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderSourcesBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderSourcesBuffer&,values: const Source[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderSourcesBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderSourcesBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderSourcesBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderSourcesBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderSourcesBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecorderViewInputsMap { count: i64=0,slots: dictionary_slot<u32,bool>[:]=default<dictionary_slot<u32,bool>[:]>() }
reusable[] var pool_RecorderViewInputsMap: dictionary_slot<u32,bool>[>..]=[];
fn get(self_: const RecorderViewInputsMap&,key: u32) -> bool? { return blot_support_pooled_map::getSlots(self_.slots,key); }
fn contains(self_: const RecorderViewInputsMap&,key: u32) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecorderViewInputsMap&,key: u32,value: bool) { var view=blot_support_pooled_map::Map<u32,bool> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderViewInputsMap); self_.count=view.count; self_.slots=view.slots; }
fn remove(self_: RecorderViewInputsMap&,key: u32) { var view=blot_support_pooled_map::Map<u32,bool> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecorderViewInputsMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecorderViewInputsMap&) { if self_.slots.len!=0 { pool_RecorderViewInputsMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<u32,bool>[:]>(); self_.count=0; }
struct RecorderReadyReadsMap { count: i64=0,slots: dictionary_slot<BindingRef,u32>[:]=default<dictionary_slot<BindingRef,u32>[:]>() }
reusable[] var pool_RecorderReadyReadsMap: dictionary_slot<BindingRef,u32>[>..]=[];
fn get(self_: const RecorderReadyReadsMap&,key: BindingRef) -> u32? { return blot_support_pooled_map::getSlots(self_.slots,key); }
fn contains(self_: const RecorderReadyReadsMap&,key: BindingRef) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecorderReadyReadsMap&,key: BindingRef,value: u32) { var view=blot_support_pooled_map::Map<BindingRef,u32> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderReadyReadsMap); self_.count=view.count; self_.slots=view.slots; }
fn remove(self_: RecorderReadyReadsMap&,key: BindingRef) { var view=blot_support_pooled_map::Map<BindingRef,u32> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecorderReadyReadsMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecorderReadyReadsMap&) { if self_.slots.len!=0 { pool_RecorderReadyReadsMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<BindingRef,u32>[:]>(); self_.count=0; }
struct RecorderCachedViewsMap { count: i64=0,slots: dictionary_slot<ViewKey,u32>[:]=default<dictionary_slot<ViewKey,u32>[:]>() }
reusable[] var pool_RecorderCachedViewsMap: dictionary_slot<ViewKey,u32>[>..]=[];
fn get(self_: const RecorderCachedViewsMap&,key: ViewKey) -> u32? { return blot_support_pooled_map::getSlots(self_.slots,key); }
fn contains(self_: const RecorderCachedViewsMap&,key: ViewKey) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecorderCachedViewsMap&,key: ViewKey,value: u32) { var view=blot_support_pooled_map::Map<ViewKey,u32> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderCachedViewsMap); self_.count=view.count; self_.slots=view.slots; }
fn remove(self_: RecorderCachedViewsMap&,key: ViewKey) { var view=blot_support_pooled_map::Map<ViewKey,u32> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecorderCachedViewsMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecorderCachedViewsMap&) { if self_.slots.len!=0 { pool_RecorderCachedViewsMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<ViewKey,u32>[:]>(); self_.count=0; }
struct RecorderOwnedChildrenBuffer { storage: Span[:]=default<Span[:]>(),items: Span[:]=default<Span[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderOwnedChildrenBuffer: Span[>..]=[];
fn ensure(self_: RecorderOwnedChildrenBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderOwnedChildrenBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderOwnedChildrenBuffer&,value: Span) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderOwnedChildrenBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderOwnedChildrenBuffer&,values: const Span[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderOwnedChildrenBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderOwnedChildrenBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderOwnedChildrenBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderOwnedChildrenBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderOwnedChildrenBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecorderBuffersBuffer { storage: BufferEffect[:]=default<BufferEffect[:]>(),items: BufferEffect[:]=default<BufferEffect[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderBuffersBuffer: BufferEffect[>..]=[];
fn ensure(self_: RecorderBuffersBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderBuffersBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderBuffersBuffer&,value: BufferEffect) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderBuffersBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderBuffersBuffer&,values: const BufferEffect[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderBuffersBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderBuffersBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderBuffersBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderBuffersBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderBuffersBuffer); self_.len=0; self_.failure=blot_error::Error.none; }

struct RecorderBacking { events: RecorderEventsBuffer=RecorderEventsBuffer {..},sources: RecorderSourcesBuffer=RecorderSourcesBuffer {..},view_inputs: RecorderViewInputsMap=RecorderViewInputsMap {..},ready_reads: RecorderReadyReadsMap=RecorderReadyReadsMap {..},cached_views: RecorderCachedViewsMap=RecorderCachedViewsMap {..},owned_children: RecorderOwnedChildrenBuffer=RecorderOwnedChildrenBuffer {..},buffers: RecorderBuffersBuffer=RecorderBuffersBuffer {..} }
reusable var recorder_backings: RecorderBacking[>..]=[];
struct RecorderOwnerState { value: Recorder,backing: u32,generation: u64,live: bool=true }
struct RecorderOwner { lease: u32=0,generation: u64=0 }
reusable var recorder_owners: RecorderOwnerState[>..]=[];
var next_recorder_generation: u64=1;
fn initRecorderOwner(session: const Session&) -> RecorderOwner,Error { if next_recorder_generation==0xffffffffffffffff||recorder_owners.len>=0xffffffff||recorder_backings.len>=0xffffffff { return RecorderOwner {..},blot_error::Error.out_of_memory; } let generation=next_recorder_generation; next_recorder_generation++; let at=recorder_backings.alloc_index(RecorderBacking {..}); let backing: RecorderBacking& =recorder_backings[at]; let tables=RecorderTables {events:backing.events,sources:backing.sources,view_inputs:backing.view_inputs,ready_reads:backing.ready_reads,cached_views:backing.cached_views,owned_children:backing.owned_children,buffers:backing.buffers, ..}; let value=init(session,tables); let owner=recorder_owners.alloc_index(RecorderOwnerState {value,at as u32,generation,true, ..}); return RecorderOwner {(owner+1) as u32,generation, ..},blot_error::Error.none; }
fn borrow(self_: RecorderOwner) -> Recorder? { if self_.lease==0||self_.lease-1>=recorder_owners.len { return null; } let owner: RecorderOwnerState& =recorder_owners[self_.lease-1]; if !owner.live||owner.generation!=self_.generation { return null; } return owner.value; }
fn deinit(self_: RecorderOwner&) { if self_.lease==0 { return; } let at=self_.lease-1; assert(at<recorder_owners.len&&recorder_owners[at].live&&recorder_owners[at].generation==self_.generation); let owner: RecorderOwnerState& =recorder_owners[at]; owner.value.deinit(); let backing: RecorderBacking& =recorder_backings[owner.backing]; backing.events.deinit(); backing.sources.deinit(); release(backing.view_inputs); release(backing.ready_reads); release(backing.cached_views); backing.owned_children.deinit(); backing.buffers.deinit(); recorder_backings.free(owner.backing); owner.live=false; recorder_owners.free(at); self_=RecorderOwner {..}; }
fn failure(self_: const Recorder&) -> Error { if self_.events.failure!=blot_error::Error.none { return self_.events.failure; } if self_.sources.failure!=blot_error::Error.none { return self_.sources.failure; } if self_.owned_children.failure!=blot_error::Error.none { return self_.owned_children.failure; } if self_.buffers.failure!=blot_error::Error.none { return self_.buffers.failure; } return blot_error::Error.none; }
