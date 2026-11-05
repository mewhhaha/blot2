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
        blot_check_types::Tag.unit, blot_check_types::Tag.boolean, blot_check_types::Tag.unsigned32,
        blot_check_types::Tag.floating32, blot_check_types::Tag.variable, blot_check_types::Tag.projection,
        blot_check_types::Tag.nominal, blot_check_types::Tag.product, blot_check_types::Tag.record,
        blot_check_types::Tag.function, blot_check_types::Tag.cursor, blot_check_types::Tag.array,
        blot_check_types::Tag.list, blot_check_types::Tag.existential, blot_check_types::Tag.forall => { return true; },
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
    types: const blot_eval_type_evidence::Mapping[:] = [], rows: const blot_eval_type_evidence::RowMapping[:] = [],
}
struct Judgment {
    kind: JudgmentKind, unit: u32, producer: u32 = 0, source: u32, root: u32 = 0,
    scheme: blot_check_types::Scheme = blot_check_types::Scheme {..}, closed_rows: blot_check_types::List = blot_check_types::List {..},
    allow_remaining: bool = false, matched: bool = true, inputs: Inputs = Inputs {..}, outputs: Inputs = Inputs {..},
    selected: const BindingRef[:] = [],
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
    buffers: const BufferEffect[:] = [], ordered_reads: bool = false, values_before: i64 = 0,
    target: BindingRef, value: ValueId, options: blot_eval_core_eval::Options,
    events: Event[:], sources: Source[:], inputs: Inputs = Inputs {..}, outputs: Inputs&? = null,
}
reusable[] var owned_buffers: BufferEffect[>..] = [];
fn copyOwned(source: const BufferEffect[:]) -> BufferEffect[:] {
    if source.len == 0 { return []; } let out = owned_buffers.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const BufferEffect[:]) {
    if source.len == 0 { return; } let first: const BufferEffect& = source[0]; let at = owned_buffers.index_of(first);
    assert(at >= 0); owned_buffers.free_slice(owned_buffers[at..at + source.len]);
}
reusable[] var owned_events: Event[>..] = [];
fn copyOwned(source: const Event[:]) -> Event[:] {
    if source.len == 0 { return []; } let out = owned_events.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const Event[:]) {
    if source.len == 0 { return; } let first: const Event& = source[0]; let at = owned_events.index_of(first);
    assert(at >= 0); owned_events.free_slice(owned_events[at..at + source.len]);
}
reusable[] var owned_sources: Source[>..] = [];
fn copyOwned(source: const Source[:]) -> Source[:] {
    if source.len == 0 { return []; } let out = owned_sources.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const Source[:]) {
    if source.len == 0 { return; } let first: const Source& = source[0]; let at = owned_sources.index_of(first);
    assert(at >= 0); owned_sources.free_slice(owned_sources[at..at + source.len]);
}
reusable[] var owned_types: blot_eval_type_evidence::Mapping[>..] = [];
fn copyOwned(source: const blot_eval_type_evidence::Mapping[:]) -> blot_eval_type_evidence::Mapping[:] {
    if source.len == 0 { return []; } let out = owned_types.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const blot_eval_type_evidence::Mapping[:]) {
    if source.len == 0 { return; } let first: const blot_eval_type_evidence::Mapping& = source[0]; let at = owned_types.index_of(first);
    assert(at >= 0); owned_types.free_slice(owned_types[at..at + source.len]);
}
reusable[] var owned_rows: blot_eval_type_evidence::RowMapping[>..] = [];
fn copyOwned(source: const blot_eval_type_evidence::RowMapping[:]) -> blot_eval_type_evidence::RowMapping[:] {
    if source.len == 0 { return []; } let out = owned_rows.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const blot_eval_type_evidence::RowMapping[:]) {
    if source.len == 0 { return; } let first: const blot_eval_type_evidence::RowMapping& = source[0]; let at = owned_rows.index_of(first);
    assert(at >= 0); owned_rows.free_slice(owned_rows[at..at + source.len]);
}
reusable[] var owned_selected: BindingRef[>..] = [];
fn copyOwned(source: const BindingRef[:]) -> BindingRef[:] {
    if source.len == 0 { return []; } let out = owned_selected.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const BindingRef[:]) {
    if source.len == 0 { return; } let first: const BindingRef& = source[0]; let at = owned_selected.index_of(first);
    assert(at >= 0); owned_selected.free_slice(owned_selected[at..at + source.len]);
}
reusable var queries: Query[>..] = [];
reusable var judgments: Judgment[>..] = [];
reusable var output_inputs: Inputs[>..] = [];
fn cloneMutable(self: Inputs) -> blot_eval_type_evidence::Mapping[:], blot_eval_type_evidence::RowMapping[:], Error {
    return copyOwned(self.types), copyOwned(self.rows), Error.none;
}
fn clone(self: Inputs) -> Inputs, Error { return Inputs { copyOwned(self.types), copyOwned(self.rows) , ..}, Error.none; }
fn deinit(self: Inputs&) { releaseOwned(self.types); releaseOwned(self.rows); self = Inputs {..}; }
fn clone(self: Judgment) -> Judgment&?, Error {
    let inputs, e1 = self.inputs.clone(); if e1 != Error.none { return null, e1; }
    let outputs, e2 = self.outputs.clone();
    if e2 != Error.none { var partial = inputs; partial.deinit(); return null, e2; }
    var value = self; value.inputs = inputs; value.outputs = outputs; value.selected = copyOwned(self.selected);
    let index = judgments.alloc_index(value); return judgments[index], Error.none;
}
fn destroy(self: Judgment&) {
    self.inputs.deinit(); self.outputs.deinit(); releaseOwned(self.selected);
    let index = judgments.index_of(self); assert(index >= 0); judgments.free(index);
}
fn ownedBytes(self: Judgment) -> i64 {
    return blot_host_layout::constant_judgment + bytes_of(self.inputs.types).len + bytes_of(self.outputs.types).len +
        bytes_of(self.inputs.rows).len + bytes_of(self.outputs.rows).len + bytes_of(self.selected).len;
}
fn clone(self: Query) -> Query&?, Error {
    var value = self;
    { let optional_source_53 .= self.judgment; if optional_source_53 { let judgment .= optional_source_53;
        let cloned, error = judgment.clone(); if error != Error.none { return null, error; }
        assert(cloned != null); value.judgment = cloned;
     } }
    let index = queries.alloc_index(value); return queries[index], Error.none;
}
fn destroy(self: Query&) {
    { let optional_source_52 .= self.judgment; if optional_source_52 { let judgment .= optional_source_52; judgment.destroy();  } }
    let index = queries.index_of(self); assert(index >= 0); queries.free(index);
}
fn ownedBytes(self: Query) -> i64 {
    var bytes = blot_host_layout::constant_query; { let optional_source_51 .= self.judgment; if optional_source_51 { let judgment .= optional_source_51; bytes += judgment.ownedBytes();  } } return bytes;
}
fn clone(self: Event) -> Event, Error {
    match self {
        Event.query query => { let value, error = query.value.clone(); if error != Error.none { return default<Event>(), error; } assert(value != null); return Event.query { value , ..}, Error.none; },
        _ => { return self, Error.none; },
    }
}
fn deinit(self: Event&) { match self { Event.query query => { query.value.destroy(); }, _ => {} } }
fn sourceSteps(self: Record) -> i64 {
    var total: i64 = 0;
    for event in self.events { match event { Event.work work => { blot_reuse_specialization_receipt::addBytes(total, work.value.steps); }, _ => {} } }
    return total;
}
fn productive(self: Record, floor: i64) -> bool {
    let steps = self.sourceSteps(); if steps < floor { return false; }
    if steps < minimum_query_steps { for event in self.events { match event { Event.query => { return false; }, _ => {} } } }
    return true;
}
fn ownedBytes(self: Record) -> i64 {
    var total = blot_host_layout::constant_record + bytes_of(self.buffers).len + self.events.len * blot_host_layout::constant_event + bytes_of(self.sources).len +
        bytes_of(self.inputs.types).len + bytes_of(self.inputs.rows).len;
    for event in self.events { match event { Event.query query => { total += query.value.ownedBytes(); }, _ => {} } }
    { let optional_source_50 .= self.outputs; if optional_source_50 { let outputs .= optional_source_50; total += blot_host_layout::constant_inputs + bytes_of(outputs.types).len + bytes_of(outputs.rows).len;  } }
    return total;
}
fn deinit(self: Record&) {
    releaseOwned(self.buffers); for &event in self.events { event.deinit(); } releaseOwned(self.events); releaseOwned(self.sources);
    self.inputs.deinit();
    { let optional_source_49 .= self.outputs; if optional_source_49 { let outputs .= optional_source_49; outputs.deinit(); let index = output_inputs.index_of(outputs); assert(index >= 0); output_inputs.free(index);  } }
    self = default<Record>();
}
fn clone(self: Record) -> Record, Error {
    var result = self; result.buffers = []; result.events = []; result.sources = []; result.inputs = Inputs {..}; result.outputs = null;
    result.buffers = copyOwned(self.buffers);
    let events = owned_events.alloc_slice(self.events.len);
    for index in self.events.len { events[index] = default<Event>(); }
    result.events = events;
    for event, index in self.events {
        let value, error = event.clone(); if error != Error.none { result.deinit(); return default<Record>(), error; } events[index] = value;
    }
    result.sources = copyOwned(self.sources);
    let inputs, error = self.inputs.clone(); if error != Error.none { result.deinit(); return default<Record>(), error; } result.inputs = inputs;
    { let optional_source_48 .= self.outputs; if optional_source_48 { let outputs .= optional_source_48;
        let inputs, error = outputs.clone(); if error != Error.none { result.deinit(); return default<Record>(), error; }
        let index = output_inputs.alloc_index(inputs); result.outputs = output_inputs[index];
     } }
    return result, Error.none;
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
fn lookup(self: Provider, session: Session&, target: BindingRef, inputs: Inputs) -> blot_support::Option<Lookup>, Error {
    return self.context.lookupConstant(session, target, inputs);
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
    if left.kind == blot_eval_core_eval::ValueKind.closure && right.kind == blot_eval_core_eval::ValueKind.closure {
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
        blot_eval_core_eval::ValueKind.scalar, blot_eval_core_eval::ValueKind.product, blot_eval_core_eval::ValueKind.record,
        blot_eval_core_eval::ValueKind.nominal, blot_eval_core_eval::ValueKind.array, blot_eval_core_eval::ValueKind.list,
        blot_eval_core_eval::ValueKind.cursor, blot_eval_core_eval::ValueKind.closure, blot_eval_core_eval::ValueKind.package => { return true; },
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
fn captureInputs(self: Recorder&, inputs: Inputs) -> Error {
    let owned, error = inputs.clone(); if error != Error.none { return error; }
    if self.owns_inputs { self.inputs.deinit(); } self.inputs = owned; self.owns_inputs = true; return Error.none;
}
fn deinit(self: Recorder&) {
    if self.owns_inputs { self.inputs.deinit(); self.owns_inputs = false; }
    for &event in self.events.items { event.deinit(); } self.events.clear(); self.sources.clear();
    self.view_inputs.clear(); self.ready_reads.clear(); self.cached_views.clear(); self.owned_children.clear(); self.buffers.clear();
}
fn view(self: Recorder&, input: u32) -> Error {
    if !self.eligible || self.view_inputs.contains(input) { return Error.none; }
    if self.view_inputs.count >= 4096 { self.eligible = false; return Error.none; }
    self.view_inputs.insert(input, false); return Error.none;
}
fn prepareView(self: Recorder&) -> Error {
    if self.eligible {
        // Exercise the upcoming two append slots while no view publication
        // has occurred. Both elements are inert work records and are removed.
        self.events.push(Event.work { Resources {} , ..}); self.events.push(Event.work { Resources {} , ..});
        self.events.pop_n(2);
    }
    return Error.none;
}
fn cacheView(self: Recorder&, session: const Session&, effect: ViewEffect) -> Error {
    if !self.eligible { return Error.none; }
    let error = self.flush(session); if error != Error.none { return error; }
    if !self.eligible { return Error.none; }
    if self.cached_views.count >= 16384 { self.eligible = false; return Error.none; }
    let key = ViewKey { effect.value, effect.evidence , ..};
    { let optional_source_47 .= self.cached_views.get(key); if optional_source_47 { let known = optional_source_47;
        if !effect.existed || known != effect.selected { self.eligible = false; }
     } else { self.cached_views.insert(key, effect.selected); self.events.push(Event.view { effect , ..}); } }
    { let optional_source_46 .= self.view_inputs.get(effect.value); if optional_source_46 { let complete .= optional_source_46; complete = true;  }
    else { assert(false); } }
    return Error.none;
}
fn ownsChildren(self: const Recorder&, session: const Session&, span: Span) -> bool {
    let end = span.start as i64 + span.len;
    if span.start >= self.child_mark && end <= session.storage.children.len { return true; }
    for owned in self.owned_children.items { if span.start >= owned.start && end <= owned.start as i64 + owned.len { return true; } }
    return false;
}
fn viewsEscape(self: Recorder&, session: const Session&, result: u32) -> bool, Error {
    if self.view_inputs.count == 0 && self.growth_mutations == 0 { return false, Error.none; }
    var pending: u32[>..<] = []; var seen = dictionary<u32,bool> {}; pending.push(result);
    for event in self.events.items {
        match event {
            Event.read dependency => { pending.push(dependency.value.value); },
            Event.query query => { if query.value.input != 0 { pending.push(query.value.input); } if query.value.selected != 0 { pending.push(query.value.selected); } },
            _ => {},
        }
    }
    while pending.len != 0 {
        let id = pending[pending.len - 1]; pending.resize(pending.len - 1);
        if seen.contains(id) { continue; }
        { let optional_source_45 .= self.view_inputs.get(id); if optional_source_45 { let complete .= optional_source_45; if !complete { return true, Error.none; }  } }
        if seen.count >= 65536 { return true, Error.none; } seen.insert(id, true);
        let info = session.valueInfo(id);
        if info.kind == blot_eval_core_eval::ValueKind.array || info.kind == blot_eval_core_eval::ValueKind.list {
            { let optional_source_44 .= session.storage.collection_buffers.buffers.get(Span { info.start, info.len , ..}); if optional_source_44 { let buffer = optional_source_44;
                if self.ownsChildren(session, buffer) {
                    var duplicate = false;
                    for effect in self.buffers.items { let prior = session.valueInfo(effect.value); if prior.start == info.start && prior.len == info.len { duplicate = true; } }
                    if !duplicate { self.buffers.push(BufferEffect { id, Frontier { info.start - buffer.start, buffer.len , ..} , ..}); }
                }
             } }
        }
        let children = session.valueChildren(id);
        if pending.len > 65536 || children.len > 65536 - pending.len { return true, Error.none; }
        pending.append(children);
    }
    var count: i64 = 0; let length = self.events.len;
    for index in length {
        let event = self.events.items[index]; var keep = true;
        match event { Event.view view => { keep = seen.contains(view.value.value); }, _ => {} }
        if keep { self.events.items[count] = event; count++; }
    }
    self.events.resize(count); return false, Error.none;
}
fn observe(self: Recorder&, session: const Session&) {
    let depth = session.depth - self.base_depth; let calls = session.call_depth - self.base_calls;
    if depth > self.depth { self.depth = depth; } if calls > self.call_depth { self.call_depth = calls; }
}
fn canGrow(self: const Recorder&, session: const Session&, before: Span) -> bool {
    if !self.eligible || self.collection_serial == 0xffffffffffffffff || self.collection_serial != session.storage.collection_buffers.mutation_serial { return false; }
    if before.len != 0 && !self.ownsChildren(session, before) { return false; }
    { let optional_source_43 .= session.storage.collection_buffers.buffers.get(before); if optional_source_43 { let buffer = optional_source_43; if !self.ownsChildren(session, buffer) { return false; }  } }
    return true;
}
fn grew(self: Recorder&, session: const Session&) {
    assert(self.collection_serial + 1 == session.storage.collection_buffers.mutation_serial);
    self.collection_serial++; self.growth_mutations++;
}
fn source(self: Recorder&, target: BindingRef) -> Error { self.observed(Source.named { target , ..}) }
fn closure(self: Recorder&, unit: u32, catalog: u32) -> Error { self.observed(Source.anonymous { unit, catalog , ..}) }
fn observed(self: Recorder&, target: Source) -> Error {
    if !self.eligible { return Error.none; }
    for old in self.sources.items { if old == target { return Error.none; } }
    if self.sources.len >= 4096 { self.eligible = false; return Error.none; }
    self.sources.push(target); return Error.none;
}
fn flush(self: Recorder&, session: const Session&) -> Error {
    if !self.eligible { return Error.none; }
    let now = position(session);
    let work = Resources { now.steps - self.mark.steps, now.values - self.mark.values,
        now.children - self.mark.children, self.depth, self.call_depth , ..};
    if self.events.len >= 16384 { self.eligible = false; return Error.none; }
    if session.storage.children.len != self.child_mark {
        self.owned_children.push(Span { self.child_mark as u32, (session.storage.children.len - self.child_mark) as u32 , ..});
    }
    var appended = false;
    if self.events.len != 0 {
        let index = self.events.len - 1;
        match self.events.items[index] {
            Event.work previous => {
                var combined = previous.value; combined.steps += work.steps; combined.values += work.values; combined.children += work.children;
                if work.depth > combined.depth { combined.depth = work.depth; } if work.call_depth > combined.call_depth { combined.call_depth = work.call_depth; }
                self.events.items[index] = Event.work { combined , ..}; appended = true;
            },
            _ => {},
        }
    }
    if !appended { self.events.push(Event.work { work , ..}); }
    self.reset(session); return Error.none;
}
fn reset(self: Recorder&, session: const Session&) { self.mark = position(session); self.child_mark = session.storage.children.len; self.depth = 0; self.call_depth = 0; }
fn stable(self: const Recorder&, session: const Session&) -> bool {
    return session.constant_inference_serial != 0xffffffffffffffff && session.constant_inference_serial == self.inference_serial &&
        session.summary_transitions == self.summary_transitions && session.summary_graph_work == self.summary_work &&
        session.summary_exhausted == self.summary_exhausted && self.query_budgets == queryBudgets(session);
}
fn beforeRead(self: Recorder&, session: const Session&) -> Error { if !self.stable(session) { self.eligible = false; } return self.flush(session); }
fn read(self: Recorder&, session: const Session&, target: BindingRef, value: ValueId) -> Error {
    if self.ready_reads.count >= 4096 { self.eligible = false; }
    if self.eligible {
        { let optional_source_42 .= self.ready_reads.get(target); if optional_source_42 { let known = optional_source_42; if known != value { self.eligible = false; }  }
        else {
            self.ready_reads.insert(target, value);
            self.events.push(Event.read { Read { target, value, session.depth - self.base_depth, session.call_depth - self.base_calls } , ..});
        } }
    }
    self.inference_serial = session.constant_inference_serial; self.summary_transitions = session.summary_transitions;
    self.summary_work = session.summary_graph_work; self.summary_exhausted = session.summary_exhausted;
    self.query_budgets = queryBudgets(session); self.reset(session); return Error.none;
}
fn query(self: Recorder&, session: const Session&, observation: Query) -> Error {
    if !self.eligible || session.constant_inference_serial == 0xffffffffffffffff { return Error.none; }
    var owned = observation; owned.depth = session.depth - self.base_depth; owned.call_depth = session.call_depth - self.base_calls;
    let payload, error = owned.clone(); if error != Error.none { return error; } assert(payload != null);
    self.events.push(Event.query { payload , ..});
    self.inference_serial = session.constant_inference_serial; self.summary_transitions = session.summary_transitions;
    self.summary_work = session.summary_graph_work; self.summary_exhausted = session.summary_exhausted;
    self.query_budgets = queryBudgets(session); self.collection_serial = session.storage.collection_buffers.mutation_serial;
    self.reset(session); return Error.none;
}
fn finish(self: Recorder&, session: const Session&, target: BindingRef, value: ValueId, outputs: Inputs) -> blot_support::Option<Record>, Error { let allocation_error=self.failure(); if allocation_error!=Error.none { return blot_support::none<Record>(),allocation_error; }
    let error = self.flush(session); if error != Error.none { return blot_support::none<Record>(), error; }
    if !self.eligible || self.collection_serial == 0xffffffffffffffff || session.storage.collection_buffers.mutation_serial != self.collection_serial ||
        session.constant_inference_serial == 0xffffffffffffffff || session.constant_inference_serial != self.inference_serial ||
        session.summary_transitions != self.summary_transitions || session.summary_graph_work != self.summary_work || session.summary_exhausted != self.summary_exhausted ||
        self.query_budgets != queryBudgets(session) { return blot_support::none<Record>(), Error.none; }
    var steps: i64 = 0;
    for event in self.events.items { match event { Event.work work => { steps += work.value.steps; }, _ => {} } }
    if steps < session.minimum_constant_steps { return blot_support::none<Record>(), Error.none; }
    if steps < minimum_query_steps { for event in self.events.items { match event { Event.query => { return blot_support::none<Record>(), Error.none; }, _ => {} } } }
    if !admittedGraph(session.snapshot(), value) { return blot_support::none<Record>(), Error.none; }
    for event in self.events.items {
        match event { Event.read dependency => { if !admittedGraph(session.snapshot(), dependency.value.value) { return blot_support::none<Record>(), Error.none; } }, _ => {} }
    }
    let info = session.valueInfo(value);
    if (info.kind == blot_eval_core_eval::ValueKind.array || info.kind == blot_eval_core_eval::ValueKind.list) && info.len > steps / 4 { return blot_support::none<Record>(), Error.none; }
    let escaping, error = self.viewsEscape(session, value); if error != Error.none { return blot_support::none<Record>(), error; }
    if escaping { return blot_support::none<Record>(), Error.none; }
    if self.growth_mutations != 0 {
        var growth = Growth { mutations: self.growth_mutations , ..}; var plain = true;
        for event in self.events.items { match event { Event.read, Event.view, Event.query => { plain = false; }, _ => {} } }
        if plain && self.buffers.len == 1 && self.buffers.items[0].value == value &&
            (info.kind == blot_eval_core_eval::ValueKind.array || info.kind == blot_eval_core_eval::ValueKind.list) {
            var primitive = true;
            for child in session.valueChildren(value) { if session.valueInfo(child).kind != blot_eval_core_eval::ValueKind.scalar { primitive = false; } }
            if primitive { growth.frontier = blot_support::some(self.buffers.items[0].frontier); self.buffers.clear(); }
        }
        self.events.push(Event.growth { growth , ..});
    }
    // Transfer Event ownership to persistent typed runs. Query objects already
    // belong to their reusable pool; no borrowed lexical reference is retained.
    var result = Record {
        buffers: copyOwned(self.buffers.items), ordered_reads: true, values_before: self.values_before,
        target: target, value: value, options: session.options, events: copyOwned(self.events.items), sources: copyOwned(self.sources.items),
     ..};
    self.buffers.clear(); self.events.clear(); self.sources.clear();
    let inputs, error = self.inputs.clone(); if error != Error.none { result.deinit(); return blot_support::none<Record>(), error; }
    result.inputs = inputs;
    if self.inputs.types != outputs.types || self.inputs.rows != outputs.rows {
        let payload, error = outputs.clone(); if error != Error.none { result.deinit(); return blot_support::none<Record>(), error; }
        let index = output_inputs.alloc_index(payload); result.outputs = output_inputs[index];
    }
    return blot_support::some(result), Error.none;
}
fn withRecorder<C,F>(session: const Session&,context: C&) -> Error { var owner,error=initRecorderOwner(session); if error!=Error.none { return error; } let recorder=owner.borrow(); assert(recorder); let result=F(context,recorder); let allocation_error=recorder.failure(); owner.deinit(); if result!=Error.none { return result; } return allocation_error; }

struct RecorderEventsBuffer { storage: Event[:]=[],items: Event[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderEventsBuffer: Event[>..]=[];
fn ensure(self: RecorderEventsBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderEventsBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderEventsBuffer&,value: Event) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderEventsBuffer); self.len=self.items.len; }
fn append(self: RecorderEventsBuffer&,values: const Event[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderEventsBuffer); self.len=self.items.len; }
fn resize(self: RecorderEventsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderEventsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderEventsBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderEventsBuffer); self.len=0; self.failure=Error.none; }
struct RecorderSourcesBuffer { storage: Source[:]=[],items: Source[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderSourcesBuffer: Source[>..]=[];
fn ensure(self: RecorderSourcesBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderSourcesBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderSourcesBuffer&,value: Source) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderSourcesBuffer); self.len=self.items.len; }
fn append(self: RecorderSourcesBuffer&,values: const Source[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderSourcesBuffer); self.len=self.items.len; }
fn resize(self: RecorderSourcesBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderSourcesBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderSourcesBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderSourcesBuffer); self.len=0; self.failure=Error.none; }
struct RecorderViewInputsMap { count: i64=0,slots: dictionary_slot<u32,bool>[:]=[] }
reusable[] var pool_RecorderViewInputsMap: dictionary_slot<u32,bool>[>..]=[];
fn get(self: const RecorderViewInputsMap&,key: u32) -> bool? { let view=blot_support_pooled_map::Map<u32,bool> {count:self.count,slots:self.slots, ..}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecorderViewInputsMap&,key: u32) -> bool { return self.get(key)!=null; }
fn insert(self: RecorderViewInputsMap&,key: u32,value: bool) { var view=blot_support_pooled_map::Map<u32,bool> {count:self.count,slots:self.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderViewInputsMap); self.count=view.count; self.slots=view.slots; }
fn remove(self: RecorderViewInputsMap&,key: u32) { var view=blot_support_pooled_map::Map<u32,bool> {count:self.count,slots:self.slots, ..}; blot_support_pooled_map::remove(view,key); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecorderViewInputsMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecorderViewInputsMap&) { if self.slots.len!=0 { pool_RecorderViewInputsMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
struct RecorderReadyReadsMap { count: i64=0,slots: dictionary_slot<BindingRef,u32>[:]=[] }
reusable[] var pool_RecorderReadyReadsMap: dictionary_slot<BindingRef,u32>[>..]=[];
fn get(self: const RecorderReadyReadsMap&,key: BindingRef) -> u32? { let view=blot_support_pooled_map::Map<BindingRef,u32> {count:self.count,slots:self.slots, ..}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecorderReadyReadsMap&,key: BindingRef) -> bool { return self.get(key)!=null; }
fn insert(self: RecorderReadyReadsMap&,key: BindingRef,value: u32) { var view=blot_support_pooled_map::Map<BindingRef,u32> {count:self.count,slots:self.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderReadyReadsMap); self.count=view.count; self.slots=view.slots; }
fn remove(self: RecorderReadyReadsMap&,key: BindingRef) { var view=blot_support_pooled_map::Map<BindingRef,u32> {count:self.count,slots:self.slots, ..}; blot_support_pooled_map::remove(view,key); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecorderReadyReadsMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecorderReadyReadsMap&) { if self.slots.len!=0 { pool_RecorderReadyReadsMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
struct RecorderCachedViewsMap { count: i64=0,slots: dictionary_slot<ViewKey,u32>[:]=[] }
reusable[] var pool_RecorderCachedViewsMap: dictionary_slot<ViewKey,u32>[>..]=[];
fn get(self: const RecorderCachedViewsMap&,key: ViewKey) -> u32? { let view=blot_support_pooled_map::Map<ViewKey,u32> {count:self.count,slots:self.slots, ..}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecorderCachedViewsMap&,key: ViewKey) -> bool { return self.get(key)!=null; }
fn insert(self: RecorderCachedViewsMap&,key: ViewKey,value: u32) { var view=blot_support_pooled_map::Map<ViewKey,u32> {count:self.count,slots:self.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderCachedViewsMap); self.count=view.count; self.slots=view.slots; }
fn remove(self: RecorderCachedViewsMap&,key: ViewKey) { var view=blot_support_pooled_map::Map<ViewKey,u32> {count:self.count,slots:self.slots, ..}; blot_support_pooled_map::remove(view,key); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecorderCachedViewsMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecorderCachedViewsMap&) { if self.slots.len!=0 { pool_RecorderCachedViewsMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
struct RecorderOwnedChildrenBuffer { storage: Span[:]=[],items: Span[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderOwnedChildrenBuffer: Span[>..]=[];
fn ensure(self: RecorderOwnedChildrenBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderOwnedChildrenBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderOwnedChildrenBuffer&,value: Span) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderOwnedChildrenBuffer); self.len=self.items.len; }
fn append(self: RecorderOwnedChildrenBuffer&,values: const Span[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderOwnedChildrenBuffer); self.len=self.items.len; }
fn resize(self: RecorderOwnedChildrenBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderOwnedChildrenBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderOwnedChildrenBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderOwnedChildrenBuffer); self.len=0; self.failure=Error.none; }
struct RecorderBuffersBuffer { storage: BufferEffect[:]=[],items: BufferEffect[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderBuffersBuffer: BufferEffect[>..]=[];
fn ensure(self: RecorderBuffersBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderBuffersBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderBuffersBuffer&,value: BufferEffect) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderBuffersBuffer); self.len=self.items.len; }
fn append(self: RecorderBuffersBuffer&,values: const BufferEffect[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderBuffersBuffer); self.len=self.items.len; }
fn resize(self: RecorderBuffersBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderBuffersBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderBuffersBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderBuffersBuffer); self.len=0; self.failure=Error.none; }

struct RecorderBacking { events: RecorderEventsBuffer=RecorderEventsBuffer {..},sources: RecorderSourcesBuffer=RecorderSourcesBuffer {..},view_inputs: RecorderViewInputsMap=RecorderViewInputsMap {..},ready_reads: RecorderReadyReadsMap=RecorderReadyReadsMap {..},cached_views: RecorderCachedViewsMap=RecorderCachedViewsMap {..},owned_children: RecorderOwnedChildrenBuffer=RecorderOwnedChildrenBuffer {..},buffers: RecorderBuffersBuffer=RecorderBuffersBuffer {..} }
reusable var recorder_backings: RecorderBacking[>..]=[];
struct RecorderOwnerState { value: Recorder,backing: u32,generation: u64,live: bool=true }
struct RecorderOwner { lease: u32=0,generation: u64=0 }
reusable var recorder_owners: RecorderOwnerState[>..]=[];
var next_recorder_generation: u64=1;
fn initRecorderOwner(session: const Session&) -> RecorderOwner,Error { if next_recorder_generation==0xffffffffffffffff||recorder_owners.len>=0xffffffff||recorder_backings.len>=0xffffffff { return RecorderOwner {..},Error.out_of_memory; } let generation=next_recorder_generation; next_recorder_generation++; let at=recorder_backings.alloc_index(RecorderBacking {..}); let backing: RecorderBacking&=recorder_backings[at]; let tables=RecorderTables {events:backing.events,sources:backing.sources,view_inputs:backing.view_inputs,ready_reads:backing.ready_reads,cached_views:backing.cached_views,owned_children:backing.owned_children,buffers:backing.buffers, ..}; let value=init(session,tables); let owner=recorder_owners.alloc_index(RecorderOwnerState {value,at as u32,generation,true, ..}); return RecorderOwner {(owner+1) as u32,generation, ..},Error.none; }
fn borrow(self: RecorderOwner) -> Recorder? { if self.lease==0||self.lease-1>=recorder_owners.len { return null; } let owner: RecorderOwnerState&=recorder_owners[self.lease-1]; if !owner.live||owner.generation!=self.generation { return null; } return owner.value; }
fn deinit(self: RecorderOwner&) { if self.lease==0 { return; } let at=self.lease-1; assert(at<recorder_owners.len&&recorder_owners[at].live&&recorder_owners[at].generation==self.generation); let owner: RecorderOwnerState&=recorder_owners[at]; owner.value.deinit(); let backing: RecorderBacking&=recorder_backings[owner.backing]; backing.events.deinit(); backing.sources.deinit(); release(backing.view_inputs); release(backing.ready_reads); release(backing.cached_views); backing.owned_children.deinit(); backing.buffers.deinit(); recorder_backings.free(owner.backing); owner.live=false; recorder_owners.free(at); self=RecorderOwner {..}; }
fn failure(self: const Recorder&) -> Error { if self.events.failure!=Error.none { return self.events.failure; } if self.sources.failure!=Error.none { return self.sources.failure; } if self.owned_children.failure!=Error.none { return self.owned_children.failure; } if self.buffers.failure!=Error.none { return self.buffers.failure; } return Error.none; }
