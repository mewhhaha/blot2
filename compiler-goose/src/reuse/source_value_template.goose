// Private source-owned representation transport. No slot, fuel or call authority.
namespace blot_reuse_source_value_template;
import std;
import dictionary;
import check.core;
import check.types;
import check.check;
import eval.core_eval;
import eval.eval_values;
import eval.type_evidence;
import eval.body_recipe;
import eval.eval_collection_growth;
import backend.runtime_ir;
import reuse.code_artifacts;
import reuse.principal_reuse_gate;
import reuse.artifact_import;
import reuse.constant_receipt;
import support.error;
import support.option;
import support.native;
import support.pooled_buffer;
import support.pooled_map;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Pools = blot_reuse_code_artifacts::Pools;
type Gate = blot_reuse_principal_reuse_gate::Gate;
type ValueInfo = blot_eval_eval_values::ValueInfo;
type ValueKind = blot_eval_eval_values::ValueKind;
type ClosureOrigin = blot_eval_eval_values::ClosureOrigin;
type EvidenceTag = blot_eval_type_evidence::Tag;
type TypeTag = blot_check_types::Tag;
recursive fn versionType(types: const blot_check_core::Types&, id: u32, budget: i64&, depth: i64) -> bool {
    if id == 0 { return false; } if id >= types.nodes.len || depth == 128 || budget == 0 { return true; } budget--;
    let n = types.node(id);
    if n.tag == TypeTag.function || n.tag == TypeTag.provider { for label in types.rowLabels(n.c) { let operation = types.operation(label); if operation.instance.unit == 0 && versionType(types, operation.instance.decl, budget, depth + 1) { return true; } for argument in types.operationArguments(label) { if versionType(types, argument, budget, depth + 1) { return true; } } } }
    match n.tag {
        TypeTag.instance_version => { return true; },
        TypeTag.function => { return versionType(types, n.a, budget, depth + 1) || versionType(types, n.b, budget, depth + 1); },
        TypeTag.usage, TypeTag.scoped => { if versionType(types, n.a, budget, depth + 1) { return true; } if (n.tag == TypeTag.usage && n.c != 0) || (n.tag == TypeTag.scoped && n.b == 0) { return versionType(types, n.c, budget, depth + 1); } },
        TypeTag.array, TypeTag.list, TypeTag.cursor, TypeTag.resolver, TypeTag.provider, TypeTag.forall, TypeTag.existential => { return versionType(types, n.a, budget, depth + 1); },
        TypeTag.state_provider => { return versionType(types, n.a, budget, depth + 1) || versionType(types, n.b, budget, depth + 1) || versionType(types, n.c, budget, depth + 1); },
        TypeTag.product => { for child in types.list(blot_check_types::List { n.a, n.b , ..}) { if versionType(types, child, budget, depth + 1) { return true; } } },
        TypeTag.record => { for index in 0..n.b { if versionType(types, types.recordField(n, index).ty, budget, depth + 1) { return true; } } },
        TypeTag.nominal, TypeTag.projection, TypeTag.instance_selection => { for child in types.nominalArguments(n) { if versionType(types, child, budget, depth + 1) { return true; } } }, _ => {},
    } return false;
}
fn moduleGenerative(module: const Module&) -> bool { for binding in module.bindings { if binding.scheme.generative.len != 0 { return true; } } for body in module.bodies { if body.scheme.generative.len != 0 { return true; } } for node in module.types.nodes { if node.tag == TypeTag.instance_version { return true; } } return false; }
fn generativeBody(module: const Module&, root: u32, ty: u32) -> bool, Error {
    var versions = false; for n in module.types.nodes { if n.tag == TypeTag.instance_version { versions = true; break; } } if !versions { return false, Error.none; }
    var budget: i64 = 4096; if versionType(module.types, ty, budget, 0) { return true, Error.none; }
    var items: u32[>..<] = []; var work = blot_eval_body_recipe::Pending { items, 4096 , ..}; items.push(root); var visits: i64 = 0;
    loop {
        let id, present = work.pop(); if !present { break; } if id == 0 { continue; } if id >= module.nodes.len || visits == 4096 { return true, Error.none; } visits++;
        let n = module.node(id); budget = 4096; if versionType(module.types, n.ty, budget, 0) { return true, Error.none; }
        if n.tag == blot_check_core::Tag.call && versionType(module.types, module.call(id).callee_type, budget, 0) { return true, Error.none; }
        if n.tag == blot_check_core::Tag.closure { let closure = module.closure(id); if versionType(module.types, closure.function_type, budget, 0) || versionType(module.types, closure.parameter.ty, budget, 0) { return true, Error.none; } let error = work.append(closure.body); if error == Error.out_of_memory { return false, error; } if error != Error.none { return true, Error.none; } }
        let error = blot_eval_body_recipe::appendChildren(work, module, id, false); if error == Error.out_of_memory { return false, error; } if error != Error.none { return true, Error.none; }
    } return false, Error.none;
}
fn generativeNamed(module: const Module&, binding: u32) -> bool, Error { if binding >= module.bindings.len { return true, Error.none; } let definition .= module.body(binding); if !definition || definition.scheme.generative.len != 0 || module.binding(binding).scheme.generative.len != 0 { return true, Error.none; } return generativeBody(module, definition.root, module.binding(binding).ty); }
fn generativeClosure(module: const Module&, catalog: u32) -> bool, Error { if catalog >= module.closures.len { return true, Error.none; } let closure = module.closures[catalog]; if closure.qualifier != 0 && closure.qualifier < module.bindings.len { if module.bindings[closure.qualifier].scheme.generative.len != 0 { return true, Error.none; } let definition .= module.body(closure.qualifier); if definition && definition.scheme.generative.len != 0 { return true, Error.none; } } return generativeBody(module, closure.body, closure.function_type); }
enum Reason { none, source, slot, bounds, open_evidence, domain, owner, cycle, quota }
enum RowPolicy { empty_only, source_declared }
struct Stats {
    values: i64 = 0, inspection_index_bytes: i64 = 0, kinds: i64[22] = [0; 22], unsupported_kinds: i64[22] = [0; 22],
    open_evidence: i64 = 0, template_holes: i64 = 0, origins: i64[5] = [0; 5], unsupported_evidence: i64 = 0,
    closures: i64 = 0, children: i64 = 0, fields: i64 = 0, type_maps: i64 = 0, row_maps: i64 = 0,
}
fn room(current: i64, added: i64) -> bool { return current >= 0 && current <= 0xffffffff && added >= 0 && added <= 0xffffffff - current; }
fn range(start: i64, len: i64, total: i64) -> bool { return start >= 0 && len >= 0 && start <= total && len <= total - start; }
fn scalarRoot<S>(snapshot: const S&, id: u32) -> blot_support::Option<ValueInfo> {
    let no = blot_support::none<ValueInfo>(); if id == 0 || id >= snapshot.values.len || id >= snapshot.value_records.len || id >= snapshot.value_evidence.len { return no; }
    let info = snapshot.values[id]; if info.kind != ValueKind.scalar || info.nominal != 0 || info.len != 0 || info.start > snapshot.children.len || snapshot.value_records[id] != 0 { return no; }
    var expected = EvidenceTag.absent;
    match info.scalar { blot_backend_runtime_ir::SC_unit => { expected = EvidenceTag.unit; }, blot_backend_runtime_ir::SC_bool => { expected = EvidenceTag.boolean; }, blot_backend_runtime_ir::SC_u32 => { expected = EvidenceTag.unsigned32; }, blot_backend_runtime_ir::SC_f32 => { expected = EvidenceTag.floating32; }, _ => { return no; } }
    if (info.scalar == blot_backend_runtime_ir::SC_unit && info.bits != 0) || (info.scalar == blot_backend_runtime_ir::SC_bool && info.bits > 1) { return no; }
    let semantic = snapshot.value_evidence[id]; if semantic == 0 || semantic >= snapshot.evidence.nodes.len { return no; } let node = snapshot.evidence.nodes[semantic];
    if node.tag != expected || node.a != 0 || node.b != 0 || node.c != 0 { return no; } return blot_support::some(info);
}
fn materializeScalarRoot(session: blot_eval_core_eval::Session&, info: ValueInfo) -> u32, Error {
    if info.kind != ValueKind.scalar || info.len != 0 || info.nominal != 0 { return 0, Error.declined; }
    var semantic: u32 = 0; match info.scalar { blot_backend_runtime_ir::SC_unit => { semantic = blot_check_types::unit; }, blot_backend_runtime_ir::SC_bool => { semantic = blot_check_types::boolean; }, blot_backend_runtime_ir::SC_u32 => { semantic = blot_check_types::u32_type; }, blot_backend_runtime_ir::SC_f32 => { semantic = blot_check_types::f32_type; }, _ => { return 0, Error.declined; } }
    if (info.scalar == blot_backend_runtime_ir::SC_unit && info.bits != 0) || (info.scalar == blot_backend_runtime_ir::SC_bool && info.bits > 1) || session.constantValueCount() >= session.options.max_values || session.storage.values.len >= 0xffffffff { return 0, Error.declined; }
    var value = info; value.start = session.storage.children.len as u32; let id = session.storage.values.len as u32;
    session.storage.values.push(value); session.storage.value_evidence.push(semantic); session.storage.value_records.push(0); return id, Error.none;
}

struct WordBuffer { storage: u32[:] = [], items: u32[:] = [] }
reusable[] var scratch_wordbuffer: u32[>..] = [];
fn ensure(self: WordBuffer&, minimum: i64) -> Error { return blot_support_pooled_buffer::ensure(self, minimum, scratch_wordbuffer); }
fn push(self: WordBuffer&, value: u32) -> Error { return blot_support_pooled_buffer::push(self, value, scratch_wordbuffer); }
fn append(self: WordBuffer&, values: const u32[:]) -> Error { return blot_support_pooled_buffer::append(self, values, scratch_wordbuffer); }
fn resize(self: WordBuffer&, length: i64, initial: u32) -> Error {
    if length < 0 { return Error.out_of_memory; } let before = self.items.len; let error = self.ensure(length); if error != Error.none { return error; }
    for index in before..length { self.storage[index] = initial; } self.items = self.storage[..length]; return Error.none;
}
fn resize(self: WordBuffer&, length: i64) { blot_support_pooled_buffer::resize(self, length); }
fn clear(self: WordBuffer&) { blot_support_pooled_buffer::clear(self); }
fn deinit(self: WordBuffer&) { blot_support_pooled_buffer::deinit(self, scratch_wordbuffer); }
fn payloadBytes(self: const WordBuffer&) -> i64 { return self.storage.len * 4; }

struct SizeBuffer { storage: i64[:] = [], items: i64[:] = [] }
reusable[] var scratch_sizebuffer: i64[>..] = [];
fn ensure(self: SizeBuffer&, minimum: i64) -> Error { return blot_support_pooled_buffer::ensure(self, minimum, scratch_sizebuffer); }
fn push(self: SizeBuffer&, value: i64) -> Error { return blot_support_pooled_buffer::push(self, value, scratch_sizebuffer); }
fn append(self: SizeBuffer&, values: const i64[:]) -> Error { return blot_support_pooled_buffer::append(self, values, scratch_sizebuffer); }
fn resize(self: SizeBuffer&, length: i64, initial: i64) -> Error {
    if length < 0 { return Error.out_of_memory; } let before = self.items.len; let error = self.ensure(length); if error != Error.none { return error; }
    for index in before..length { self.storage[index] = initial; } self.items = self.storage[..length]; return Error.none;
}
fn resize(self: SizeBuffer&, length: i64) { blot_support_pooled_buffer::resize(self, length); }
fn clear(self: SizeBuffer&) { blot_support_pooled_buffer::clear(self); }
fn deinit(self: SizeBuffer&) { blot_support_pooled_buffer::deinit(self, scratch_sizebuffer); }
fn payloadBytes(self: const SizeBuffer&) -> i64 { return self.storage.len * 8; }

struct BitBuffer { storage: bool[:] = [], items: bool[:] = [] }
reusable[] var scratch_bitbuffer: bool[>..] = [];
fn ensure(self: BitBuffer&, minimum: i64) -> Error { return blot_support_pooled_buffer::ensure(self, minimum, scratch_bitbuffer); }
fn push(self: BitBuffer&, value: bool) -> Error { return blot_support_pooled_buffer::push(self, value, scratch_bitbuffer); }
fn append(self: BitBuffer&, values: const bool[:]) -> Error { return blot_support_pooled_buffer::append(self, values, scratch_bitbuffer); }
fn resize(self: BitBuffer&, length: i64, initial: bool) -> Error {
    if length < 0 { return Error.out_of_memory; } let before = self.items.len; let error = self.ensure(length); if error != Error.none { return error; }
    for index in before..length { self.storage[index] = initial; } self.items = self.storage[..length]; return Error.none;
}
fn resize(self: BitBuffer&, length: i64) { blot_support_pooled_buffer::resize(self, length); }
fn clear(self: BitBuffer&) { blot_support_pooled_buffer::clear(self); }
fn deinit(self: BitBuffer&) { blot_support_pooled_buffer::deinit(self, scratch_bitbuffer); }
fn payloadBytes(self: const BitBuffer&) -> i64 { return self.storage.len * 1; }

struct MappingBuffer { storage: blot_eval_type_evidence::Mapping[:] = [], items: blot_eval_type_evidence::Mapping[:] = [] }
reusable[] var scratch_mappingbuffer: blot_eval_type_evidence::Mapping[>..] = [];
fn ensure(self: MappingBuffer&, minimum: i64) -> Error { return blot_support_pooled_buffer::ensure(self, minimum, scratch_mappingbuffer); }
fn push(self: MappingBuffer&, value: blot_eval_type_evidence::Mapping) -> Error { return blot_support_pooled_buffer::push(self, value, scratch_mappingbuffer); }
fn append(self: MappingBuffer&, values: const blot_eval_type_evidence::Mapping[:]) -> Error { return blot_support_pooled_buffer::append(self, values, scratch_mappingbuffer); }
fn resize(self: MappingBuffer&, length: i64, initial: blot_eval_type_evidence::Mapping) -> Error {
    if length < 0 { return Error.out_of_memory; } let before = self.items.len; let error = self.ensure(length); if error != Error.none { return error; }
    for index in before..length { self.storage[index] = initial; } self.items = self.storage[..length]; return Error.none;
}
fn resize(self: MappingBuffer&, length: i64) { blot_support_pooled_buffer::resize(self, length); }
fn clear(self: MappingBuffer&) { blot_support_pooled_buffer::clear(self); }
fn deinit(self: MappingBuffer&) { blot_support_pooled_buffer::deinit(self, scratch_mappingbuffer); }
fn payloadBytes(self: const MappingBuffer&) -> i64 { return self.storage.len * 8; }

struct RowBuffer { storage: blot_eval_type_evidence::RowMapping[:] = [], items: blot_eval_type_evidence::RowMapping[:] = [] }
reusable[] var scratch_rowbuffer: blot_eval_type_evidence::RowMapping[>..] = [];
fn ensure(self: RowBuffer&, minimum: i64) -> Error { return blot_support_pooled_buffer::ensure(self, minimum, scratch_rowbuffer); }
fn push(self: RowBuffer&, value: blot_eval_type_evidence::RowMapping) -> Error { return blot_support_pooled_buffer::push(self, value, scratch_rowbuffer); }
fn append(self: RowBuffer&, values: const blot_eval_type_evidence::RowMapping[:]) -> Error { return blot_support_pooled_buffer::append(self, values, scratch_rowbuffer); }
fn resize(self: RowBuffer&, length: i64, initial: blot_eval_type_evidence::RowMapping) -> Error {
    if length < 0 { return Error.out_of_memory; } let before = self.items.len; let error = self.ensure(length); if error != Error.none { return error; }
    for index in before..length { self.storage[index] = initial; } self.items = self.storage[..length]; return Error.none;
}
fn resize(self: RowBuffer&, length: i64) { blot_support_pooled_buffer::resize(self, length); }
fn clear(self: RowBuffer&) { blot_support_pooled_buffer::clear(self); }
fn deinit(self: RowBuffer&) { blot_support_pooled_buffer::deinit(self, scratch_rowbuffer); }
fn payloadBytes(self: const RowBuffer&) -> i64 { return self.storage.len * 8; }
struct ScratchStats {
    match_calls: i64 = 0, materializations: i64 = 0, initialized_slots: i64 = 0,
    plan_positions: i64 = 0, inverse_positions: i64 = 0, anchor_resets: i64 = 0,
    child_positions: i64 = 0, baseline_match_index_entries: i64 = 0, baseline_material_index_entries: i64 = 0,
}
struct QueryScratch {
    allocation_owner: u64 = 0, owner_id: u64 = blot_native::fresh_owner_id(), owner: u64 = 0,
    generator: u64 = 0, session: u64 = 0, pools: const Pools? = null, gate: const Gate? = null,
    policy: blot_support::Option<RowPolicy>, stats: ScratchStats = ScratchStats {..},
    anchors: WordBuffer = WordBuffer {..}, anchor_ids: WordBuffer = WordBuffer {..}, positions: SizeBuffer = SizeBuffer {..},
    candidate: WordBuffer = WordBuffer {..}, inverse: WordBuffer = WordBuffer {..}, inverse_ids: WordBuffer = WordBuffer {..},
    semantic: WordBuffer = WordBuffer {..}, types: MappingBuffer = MappingBuffer {..}, rows: RowBuffer = RowBuffer {..},
    children: WordBuffer = WordBuffer {..}, child_ids: WordBuffer = WordBuffer {..}, append_children: BitBuffer = BitBuffer {..},
}
fn deinit(self: QueryScratch&) { self.anchors.deinit(); self.anchor_ids.deinit(); self.positions.deinit(); self.candidate.deinit(); self.inverse.deinit(); self.inverse_ids.deinit(); self.semantic.deinit(); self.types.deinit(); self.rows.deinit(); self.children.deinit(); self.child_ids.deinit(); self.append_children.deinit(); self.owner = 0; self.generator = 0; self.session = 0; self.pools .= null; self.gate .= null; self.policy = blot_support::none<RowPolicy>(); }
fn payloadBytes(self: const QueryScratch&) -> i64 { return self.anchors.payloadBytes() + self.anchor_ids.payloadBytes() + self.positions.payloadBytes() + self.candidate.payloadBytes() + self.inverse.payloadBytes() + self.inverse_ids.payloadBytes() + self.semantic.payloadBytes() + self.types.payloadBytes() + self.rows.payloadBytes() + self.children.payloadBytes() + self.child_ids.payloadBytes() + self.append_children.payloadBytes(); }
struct Plan {
    pools: const Pools? = null, gate: const Gate? = null, root: u32 = 0,
    order: const u32[:] = [], stats: Stats = Stats {..}, row_policy: RowPolicy = RowPolicy.empty_only,
}
reusable[] var plan_order: u32[>..] = [];
fn deinit(self: Plan&) { if self.order.len != 0 { let first: const u32& = self.order[0]; let at = plan_order.index_of(first); assert(at >= 0); plan_order.free_slice(plan_order[at..at + self.order.len]); } self = Plan {..}; }
fn bind<G>(self: QueryScratch&, plan: const Plan&, g: G&) -> Error {
    if !plan.gate || !plan.pools || self.allocation_owner == 0 || self.allocation_owner != g.evaluator.allocation_owner || !blot_support::same_slice_identity(g.evaluator.units, plan.gate.units) { return Error.declined; }
    if self.owner != 0 { if self.owner != self.owner_id || self.generator != g.owner_id || self.session != g.evaluator.owner_id || self.pools .!= plan.pools || self.gate .!= plan.gate || !self.policy.present || self.policy.value != plan.row_policy { return Error.declined; } }
    else { if self.owner_id == 0 || g.owner_id == 0 || g.evaluator.owner_id == 0 { return Error.declined; } self.owner = self.owner_id; self.generator = g.owner_id; self.session = g.evaluator.owner_id; self.pools .= plan.pools; self.gate .= plan.gate; self.policy = blot_support::some(plan.row_policy); }
    return Error.none;
}
fn grow<B,T>(self: QueryScratch&, buffer: B&, length: i64, initial: T) -> Error { let before = buffer.items.len; let error = buffer.resize(length, initial); if error != Error.none { return error; } if length > before { self.stats.initialized_slots += length - before; } return Error.none; }
fn begin<G>(self: QueryScratch&, plan: const Plan&, g: G&) -> u32[:], Error {
    let bound = self.bind(plan, g); if bound != Error.none { return [], bound; }
    for id in self.anchor_ids.items { self.anchors.items[id] = 0; } self.stats.anchor_resets += self.anchor_ids.items.len; self.anchor_ids.clear();
    let error = self.grow(self.anchors, plan.pools.evaluator.values.len, 0 as u32); if error != Error.none { return [], error; } return self.anchors.items, Error.none;
}
fn finishMatch(self: QueryScratch&, order: const u32[:]) { for id in order { self.positions.items[id] = 0x7fffffffffffffff; self.candidate.items[id] = 0; } for id in self.inverse_ids.items { self.inverse.items[id] = 0; } self.stats.inverse_positions += self.inverse_ids.items.len; self.inverse_ids.clear(); }
fn finishChildren(self: QueryScratch&, order: const u32[:]) { for id in self.child_ids.items { self.children.items[id] = 0xffffffff; } self.stats.child_positions += self.child_ids.items.len; self.child_ids.clear(); for id in order { self.append_children.items[id] = false; } }
struct Inspection { reason: Reason, stats: Stats, plan: blot_support::Option<Plan> }
struct VisitStates { pages: blot_support_pooled_map::Map<u32,u8[256]> = blot_support_pooled_map::Map<u32,u8[256]> {..} }
reusable[] var visit_pages: dictionary_slot<u32,u8[256]>[>..] = [];
fn deinit(self: VisitStates&) { blot_support_pooled_map::deinit(self.pages, visit_pages); }
fn get(self: const VisitStates&, id: u32) -> u8 { let page .= blot_support_pooled_map::get(self.pages, id / 256); if !page { return 0; } return page[id % 256]; }
fn put(self: VisitStates&, id: u32, state: u8) -> Error {
    if !blot_support_pooled_map::contains(self.pages, id / 256) { blot_support_pooled_map::insert(self.pages, id / 256, [0; 256], visit_pages); }
    let page .= blot_support_pooled_map::get(self.pages, id / 256); assert(page); page[id % 256] = state; return Error.none;
}
fn finish(self: VisitStates&, id: u32, state: u8) { let page .= blot_support_pooled_map::get(self.pages, id / 256); assert(page); page[id % 256] = state; }
fn payloadBytes(self: const VisitStates&) -> i64 { return self.pages.slots.len * 260; }
struct Checker {
    pools: const Pools&, gate: const Gate&, seen: VisitStates = VisitStates {..}, semantic: VisitStates = VisitStates {..},
    order: WordBuffer = WordBuffer {..}, stats: Stats = Stats {..}, reason: Reason = Reason.none,
    row_policy: RowPolicy = RowPolicy.empty_only, source_reads_owned: bool = false,
}
fn deinit(self: Checker&) { self.seen.deinit(); self.semantic.deinit(); self.order.deinit(); }
fn reject(self: Checker&, reason: Reason) { if self.reason == Reason.none { self.reason = reason; } }
fn sourceOwner(self: const Checker&, unit: u32) -> bool { return unit != 0 && unit <= self.pools.modules.len && unit <= self.gate.structural_units.len && self.gate.structural_units[unit - 1]; }
fn nominal(self: const Checker&, unit: u32, decl: u32) -> bool {
    if !self.gate.admitsCatalog(self.pools, unit) || decl == 0 { return false; }
    for item in self.pools.modules[unit - 1].module.nominals { if item.identity.decl == decl && (item.identity.unit == 0 || item.identity.unit == unit) { return true; } } return false;
}
fn sourceArrows(module: const Module&, source: u32, applied: u32) -> bool {
    var current = source;
    for index in 0..applied as i64 + 1 {
        if current == 0 || current >= module.types.nodes.len { return false; } var node = module.types.nodes[current];
        if node.tag == TypeTag.forall { current = node.a; if current == 0 || current >= module.types.nodes.len { return false; } node = module.types.nodes[current]; }
        if node.tag != TypeTag.function { return false; } if index < applied { current = node.b; }
    } return true;
}
fn nominalShape(self: const Checker&, info: ValueInfo) -> bool {
    let unit = (info.nominal >> 32) as u32; let decl = info.nominal as! u32; let module .= self.pools.modules[unit - 1].module;
    for constructor in module.constructors { if constructor.nominal >= module.nominals.len { return false; } let family = module.nominals[constructor.nominal].identity;
        if family.decl == decl && (family.unit == 0 || family.unit == unit) && constructor.tag == info.bits { var arity: u32 = 0; if constructor.payload != 0 { arity = 1; } return info.len == arity; }
    } return false;
}
recursive fn rowOwned(self: Checker&, id: u32, depth: i64, quantified: bool) -> bool, Error {
    if self.row_policy == RowPolicy.empty_only { return id == 0, Error.none; }
    let effects = self.pools.evaluator.evidence.effects.view(); if depth >= 128 || id >= effects.rows.len { return false, Error.none; } let span = effects.rows[id];
    if span.formal != 0 { if !quantified { return false, Error.none; } let valid, error = self.tyOwned(span.formal, depth + 1, true); if error != Error.none || !valid { return false, error; } }
    if !range(span.start, span.len, effects.labels.len) || (id == 0 && span.len != 0) { return false, Error.none; }
    for label in effects.labels[span.start..span.start + span.len] {
        if label == 0 || label >= effects.operations.len { return false, Error.none; } let operation = effects.operations[label]; if operation.instance.unit != 0 || operation.instance.decl != 0 { return false, Error.none; }
        let args = operation.arguments; if !range(args.start, args.len, effects.arguments.len) { return false, Error.none; }
        if operation.identity.unit == 0 { if operation.identity.decl != 1 || args.len != 0 { return false, Error.none; } }
        else {
            if !self.gate.admitsCatalog(self.pools, operation.identity.unit) || operation.identity.decl == 0 { return false, Error.none; }
            let module .= self.pools.modules[operation.identity.unit - 1].module; var declared = false;
            for item in module.types.operations { if item.identity == operation.identity { declared = true; break; } }
            if !declared { for item in module.operation_values { if item.identity == operation.identity { declared = true; break; } } }
            if !declared { return false, Error.none; }
        }
        for argument in effects.arguments[args.start..args.start + args.len] { let valid, error = self.tyOwned(argument, depth + 1, quantified); if error != Error.none || !valid { return false, error; } }
    } return true, Error.none;
}
fn row(self: Checker&, id: u32, depth: i64) -> bool, Error { return self.rowOwned(id, depth, false); }
fn ty(self: Checker&, id: u32, depth: i64) -> bool, Error { return self.tyOwned(id, depth, false); }
recursive fn tyOwned(self: Checker&, id: u32, depth: i64, quantified: bool) -> bool, Error {
    let view = self.pools.evaluator.evidence.view(); if id == 0 || id >= view.nodes.len || depth >= 128 { return false, Error.none; } let n = view.nodes[id];
    if n.tag == EvidenceTag.bound { return quantified, Error.none; }
    if !quantified { let state = self.semantic.get(id); if state == 2 { return true, Error.none; } if state == 1 || state == 3 { return false, Error.none; } let error = self.semantic.put(id, 1); if error != Error.none { return false, error; } }
    let valid, error = self.typeShape(view, id, n, depth, quantified); if error != Error.none { return false, error; }
    if !quantified { var state: u8 = 3; if valid { state = 2; } self.semantic.finish(id, state); } return valid, Error.none;
}
recursive fn typeShape(self: Checker&, view: blot_eval_type_evidence::View, id: u32, n: blot_eval_type_evidence::Node, depth: i64, quantified: bool) -> bool, Error {
    match n.tag {
        EvidenceTag.scoped => { return false, Error.none; }, EvidenceTag.bound => { abort("bound handled before type shape"); },
        EvidenceTag.forall, EvidenceTag.existential => {
            if !quantified { var remaining: i64 = 65536; if view.closed(id, 0, remaining) != Error.none { return false, Error.none; } }
            let valid, error = self.tyOwned(n.a, depth + 1, true); if error != Error.none || !valid { return false, error; }
            for goal in view.quantifierGoals(id) { let ends = [goal.ty, goal.other, goal.result, goal.signature]; for endpoint in ends { if endpoint == 0 { continue; } let admitted, failure = self.tyOwned(endpoint, depth + 1, true); if failure != Error.none || !admitted { return false, failure; } } }
            return true, Error.none;
        },
        EvidenceTag.projection => {
            if !quantified || !self.gate.admitsCatalog(self.pools, n.a) { return false, Error.none; }
            let module .= self.pools.modules[n.a - 1].module; var declared = false;
            for contract in module.contracts { if contract.identity.decl == n.b && (contract.identity.unit == 0 || contract.identity.unit == n.a) { declared = true; } }
            for family in module.nominals { if family.identity.decl == n.b && (family.identity.unit == 0 || family.identity.unit == n.a) { declared = true; } }
            if !declared { return false, Error.none; }
            for child in view.children(id) { let valid, error = self.tyOwned(child, depth + 1, true); if error != Error.none || !valid { return false, error; } } return true, Error.none;
        },
        EvidenceTag.unit, EvidenceTag.boolean, EvidenceTag.unsigned32, EvidenceTag.floating32, EvidenceTag.never => { return n.a == 0 && n.b == 0 && n.c == 0, Error.none; },
        EvidenceTag.function => {
            let a, first = self.tyOwned(n.a, depth + 1, quantified); if first != Error.none || !a { return false, first; }
            let b, second = self.tyOwned(n.b, depth + 1, quantified); if second != Error.none || !b { return false, second; }
            return self.rowOwned(n.c, depth + 1, quantified);
        },
        EvidenceTag.array, EvidenceTag.list, EvidenceTag.cursor => { if n.b != 0 || n.c != 0 { return false, Error.none; } return self.tyOwned(n.a, depth + 1, quantified); },
        EvidenceTag.product, EvidenceTag.record => {
            if n.c != 0 { return false, Error.none; } var words = n.b as i64; if n.tag == EvidenceTag.record { words *= 2; } if !range(n.a, words, view.extra.len) { return false, Error.none; }
            for child, index in view.extra[n.a..n.a + words] { if n.tag == EvidenceTag.record && index % 2 == 0 { if !self.pools.identity.present || child == 0 || child >= self.pools.identity.value.symbols.len { return false, Error.none; } }
                else { let valid, error = self.tyOwned(child, depth + 1, quantified); if error != Error.none || !valid { return false, error; } }
            } return true, Error.none;
        },
        EvidenceTag.nominal => {
            if !self.nominal(n.a, n.b) || n.c >= view.extra.len { return false, Error.none; } let count = view.extra[n.c]; if !range(n.c as i64 + 1, count, view.extra.len) { return false, Error.none; }
            for child in view.extra[n.c + 1..n.c + 1 + count] { let valid, error = self.tyOwned(child, depth + 1, quantified); if error != Error.none || !valid { return false, error; } } return true, Error.none;
        },
        EvidenceTag.usage, EvidenceTag.absent, EvidenceTag.type_constructor, EvidenceTag.resolver, EvidenceTag.provider, EvidenceTag.state_provider, EvidenceTag.erased_proof => { return false, Error.none; },
    }
}
fn scalarEvidenceTag(scalar: u8) -> EvidenceTag { match scalar { blot_backend_runtime_ir::SC_unit => EvidenceTag.unit, blot_backend_runtime_ir::SC_bool => EvidenceTag.boolean, blot_backend_runtime_ir::SC_u32 => EvidenceTag.unsigned32, blot_backend_runtime_ir::SC_f32 => EvidenceTag.floating32, _ => EvidenceTag.absent } }
fn compatible(info: ValueInfo, shape: blot_eval_type_evidence::Node, snapshot: const blot_eval_eval_values::Snapshot&) -> bool {
    match info.kind {
        ValueKind.scalar => { return shape.tag == scalarEvidenceTag(info.scalar); }, ValueKind.product => { return shape.tag == EvidenceTag.product && shape.b == info.len; },
        ValueKind.array => { return shape.tag == EvidenceTag.array; }, ValueKind.list => { return shape.tag == EvidenceTag.list; }, ValueKind.cursor => { return shape.tag == EvidenceTag.cursor && info.len == 1; },
        ValueKind.record => { return shape.tag == EvidenceTag.record && shape.b == info.len; }, ValueKind.nominal => { return shape.tag == EvidenceTag.nominal && shape.a == (info.nominal >> 32) as u32 && shape.b == info.nominal as! u32; },
        ValueKind.closure => { return shape.tag == EvidenceTag.function || ((shape.tag == EvidenceTag.forall || shape.tag == EvidenceTag.existential) && shape.a < snapshot.evidence.nodes.len && snapshot.evidence.nodes[shape.a].tag == EvidenceTag.function); },
        ValueKind.package => { return shape.tag == EvidenceTag.existential; }, _ => { return false; },
    }
}
recursive fn value(self: Checker&, id: u32, depth: i64) -> Error {
    let snapshot .= self.pools.evaluator; if id == 0 { return Error.none; }
    if id >= snapshot.values.len || id >= snapshot.value_evidence.len || id >= snapshot.value_records.len { self.reject(Reason.bounds); return Error.none; }
    if depth >= 128 { self.reject(Reason.quota); return Error.none; } let seen = self.seen.get(id); if seen == 2 { return Error.none; } if seen == 1 { self.reject(Reason.cycle); return Error.none; }
    if self.stats.values >= 65536 { self.reject(Reason.quota); return Error.none; } let entered = self.seen.put(id, 1); if entered != Error.none { return entered; }
    let info = snapshot.values[id]; self.stats.values++; self.stats.kinds[blot_eval_eval_values::valueKindCode(info.kind)]++; let semantic = snapshot.value_evidence[id];
    if semantic == 0 { self.stats.open_evidence++; match info.kind { ValueKind.array, ValueKind.list, ValueKind.cursor, ValueKind.product, ValueKind.record, ValueKind.nominal, ValueKind.closure, ValueKind.package => { self.stats.template_holes++; }, _ => { self.reject(Reason.open_evidence); } } }
    else { let valid, error = self.ty(semantic, 0); if error != Error.none { return error; } if !valid { self.stats.unsupported_evidence++; self.reject(Reason.domain); } }
    if semantic != 0 && semantic < snapshot.evidence.nodes.len && !compatible(info, snapshot.evidence.nodes[semantic], snapshot) { self.reject(Reason.domain); }
    if !range(info.start, info.len, snapshot.children.len) { self.reject(Reason.bounds); return Error.none; } self.stats.children += info.len;
    match info.kind {
        ValueKind.scalar => { if scalarEvidenceTag(info.scalar) == EvidenceTag.absent { self.reject(Reason.domain); } else if info.len != 0 { self.reject(Reason.bounds); } },
        ValueKind.array, ValueKind.list, ValueKind.product, ValueKind.record => {},
        ValueKind.package => {
            if info.len == 0 || info.nominal >= snapshot.evidence.nodes.len || info.bits >= snapshot.evidence.nodes.len { self.reject(Reason.bounds); }
            else { let dictionary = snapshot.evidence.nodes[info.nominal as u32]; let recipe = snapshot.evidence.nodes[info.bits]; var valid = dictionary.tag == EvidenceTag.product && recipe.tag == EvidenceTag.existential && dictionary.b == recipe.b;
                if valid { let result, error = self.ty(info.nominal as u32, depth + 1); if error != Error.none { return error; } valid = result; }
                if valid { let result, error = self.ty(info.bits, depth + 1); if error != Error.none { return error; } valid = result; } if !valid { self.reject(Reason.domain); }
            }
        },
        ValueKind.cursor => { if info.len != 1 || snapshot.children[info.start] >= snapshot.values.len { self.reject(Reason.bounds); } else { let source = snapshot.values[snapshot.children[info.start]]; if (source.kind != ValueKind.array && source.kind != ValueKind.list) || info.bits > source.len { self.reject(Reason.bounds); } } },
        ValueKind.nominal => { if !self.nominal((info.nominal >> 32) as u32, info.nominal as! u32) { self.reject(Reason.owner); } else if !self.nominalShape(info) { self.reject(Reason.bounds); } },
        ValueKind.closure => { let error = self.closureValue(info, depth); if error != Error.none { return error; } },
        _ => { self.stats.unsupported_kinds[blot_eval_eval_values::valueKindCode(info.kind)]++; self.reject(Reason.domain); },
    }
    let record = snapshot.value_records[id]; if (info.kind == ValueKind.record) != (record != 0) { self.reject(Reason.bounds); }
    if record != 0 {
        if record >= snapshot.record_layouts.len { self.reject(Reason.bounds); }
        else { let names = snapshot.record_layouts[record]; if !range(names.start, names.len, snapshot.field_names.len) || names.len != info.len { self.reject(Reason.bounds); }
            else { self.stats.fields += names.len; for name in snapshot.field_names[names.start..names.start + names.len] { if name == 0 || !self.pools.identity.present || name >= self.pools.identity.value.symbols.len { self.reject(Reason.bounds); } } }
        }
    }
    for child in snapshot.children[info.start..info.start + info.len] { let error = self.value(child, depth + 1); if error != Error.none { return error; } }
    self.seen.finish(id, 2); return self.order.push(id);
}
fn closureValue(self: Checker&, info: ValueInfo, depth: i64) -> Error {
    let snapshot .= self.pools.evaluator; self.stats.closures++; if info.bits >= snapshot.closures.len { self.reject(Reason.bounds); return Error.none; }
    let meta = snapshot.closures[info.bits]; if meta.staged != 0 { self.reject(Reason.domain); }
    if !self.sourceOwner(meta.unit) { self.reject(Reason.owner); return Error.none; } let module .= self.pools.modules[meta.unit - 1].module; self.stats.origins[blot_eval_eval_values::closureOriginCode(meta.origin)]++;
    match meta.origin {
        ClosureOrigin.named => {
            let target = blot_check_core::BindingRef { meta.unit, meta.identity , ..}; var admitted = self.gate.admits(target); if self.source_reads_owned { admitted = self.gate.admitsLocalSource(target); }
            var generative = false; if admitted { let result, error = generativeNamed(module, meta.identity); if error != Error.none { return error; } generative = result; }
            if !admitted || generative { self.reject(Reason.source); }
            else { let definition .= module.body(meta.identity); if !definition { self.reject(Reason.source); } else if !definition.is_function || info.len != meta.applied || meta.applied >= definition.parameters.len || !sourceArrows(module, module.binding(meta.identity).ty, meta.applied) { self.reject(Reason.bounds); } }
        },
        ClosureOrigin.anonymous => {
            if meta.identity >= module.closures.len { self.reject(Reason.bounds); }
            else {
                let template = module.closures[meta.identity]; let generative, error = generativeClosure(module, meta.identity); if error != Error.none { return error; } if generative { self.reject(Reason.source); }
                if meta.applied != 0 || info.len != template.captures.len { self.reject(Reason.bounds); }
                if template.qualifier != 0 {
                    if template.qualifier >= module.bindings.len { self.reject(Reason.bounds); }
                    else { let binding = module.bindings[template.qualifier]; if binding.kind == blot_check_check::Kind.global { let target = blot_check_core::BindingRef { meta.unit, template.qualifier , ..}; var admitted = self.gate.admits(target); if self.source_reads_owned { admitted = self.gate.admitsLocalSource(target); } if !admitted { self.reject(Reason.source); } }
                        else if binding.kind == blot_check_check::Kind.local { if binding.initializer == 0 || binding.initializer >= module.nodes.len || module.nodes[binding.initializer].tag != blot_check_core::Tag.closure || module.nodes[binding.initializer].a != meta.identity { self.reject(Reason.source); } }
                        else { self.reject(Reason.source); }
                    }
                }
            }
        },
        ClosureOrigin.constructor => { if meta.identity >= module.constructors.len { self.reject(Reason.bounds); } else { let constructor = module.constructors[meta.identity]; if constructor.payload == 0 || meta.applied != 0 || info.len != 0 || !sourceArrows(module, constructor.scheme.root, 0) { self.reject(Reason.bounds); } } },
        ClosureOrigin.primitive, ClosureOrigin.operation => { self.reject(Reason.domain); },
    }
    if meta.ty != 0 && meta.ty >= module.types.nodes.len { self.reject(Reason.bounds); }
    if !range(meta.mappings.start, meta.mappings.len, snapshot.type_mappings.len) || !range(meta.row_mappings.start, meta.row_mappings.len, snapshot.row_mappings.len) { self.reject(Reason.bounds); return Error.none; }
    self.stats.type_maps += meta.mappings.len; self.stats.row_maps += meta.row_mappings.len;
    for mapping, index in snapshot.type_mappings[meta.mappings.start..meta.mappings.start + meta.mappings.len] {
        let valid, error = self.ty(mapping.evidence, 0); if error != Error.none { return error; } if !blot_reuse_constant_receipt::sourceMappingKey(module, mapping.variable) || !valid { self.reject(Reason.bounds); }
        for prior in snapshot.type_mappings[meta.mappings.start..meta.mappings.start + index] { if prior.variable == mapping.variable { self.reject(Reason.bounds); } }
    }
    for mapping, index in snapshot.row_mappings[meta.row_mappings.start..meta.row_mappings.start + meta.row_mappings.len] {
        let valid, error = self.row(mapping.evidence, 0); if error != Error.none { return error; } if mapping.variable >= module.types.effects.variable_count || !valid { self.reject(Reason.bounds); }
        for prior in snapshot.row_mappings[meta.row_mappings.start..meta.row_mappings.start + index] { if prior.variable == mapping.variable { self.reject(Reason.bounds); } }
    } return Error.none;
}
fn inspect(pools: const Pools&, gate: const Gate&, target: blot_check_core::BindingRef) -> Inspection, Error {
    if gate.source_pools .!= pools { return Inspection { Reason.owner, Stats {..}, blot_support::none<Plan>() , ..}, Error.none; }
    if !gate.admits(target) || target.unit > pools.modules.len || target.unit > pools.binding_offsets.len { return Inspection { Reason.source, Stats {..}, blot_support::none<Plan>() , ..}, Error.none; }
    let module .= pools.modules[target.unit - 1].module; let body .= module.body(target.binding); if !body || body.runtime || body.is_function { return Inspection { Reason.source, Stats {..}, blot_support::none<Plan>() , ..}, Error.none; }
    let offset = pools.binding_offsets[target.unit - 1]; if target.binding > 0x7fffffffffffffff - offset { return Inspection { Reason.bounds, Stats {..}, blot_support::none<Plan>() , ..}, Error.none; }
    let index = offset + target.binding; if index >= pools.slots.len || pools.slots[index].state != 2 { return Inspection { Reason.slot, Stats {..}, blot_support::none<Plan>() , ..}, Error.none; }
    let roots = [pools.slots[index].value]; return inspectRoots(pools, gate, roots);
}
fn inspectRoots(pools: const Pools&, gate: const Gate&, roots: const u32[:]) -> Inspection, Error { return inspectRootsWithRows(pools, gate, roots, RowPolicy.empty_only); }
fn inspectRootsWithRows(pools: const Pools&, gate: const Gate&, roots: const u32[:], row_policy: RowPolicy) -> Inspection, Error { return inspectOwnedRoots(pools, gate, roots, row_policy, false); }
fn inspectConstantRoots(pools: const Pools&, gate: const Gate&, roots: const u32[:]) -> Inspection, Error { return inspectOwnedRoots(pools, gate, roots, RowPolicy.source_declared, true); }
fn inspectOwnedRoots(pools: const Pools&, gate: const Gate&, roots: const u32[:], row_policy: RowPolicy, source_reads_owned: bool) -> Inspection, Error {
    if roots.len == 0 || gate.source_pools .!= pools || !gate.enabled { return Inspection { Reason.owner, Stats {..}, blot_support::none<Plan>() , ..}, Error.none; }
    let snapshot .= pools.evaluator;
    if snapshot.values.len == 0 || snapshot.value_evidence.len == 0 || snapshot.value_records.len == 0 || snapshot.values[0].kind != ValueKind.scalar || snapshot.values[0].scalar != blot_backend_runtime_ir::SC_unit || snapshot.values[0].len != 0 || snapshot.value_evidence[0] != 1 || snapshot.value_records[0] != 0 || snapshot.evidence.nodes.len <= 1 || snapshot.evidence.nodes[1] != blot_eval_type_evidence::Node { EvidenceTag.unit , ..} { return Inspection { Reason.bounds, Stats {..}, blot_support::none<Plan>() , ..}, Error.none; }
    var checker = Checker { pools: pools, gate: gate, row_policy: row_policy, source_reads_owned: source_reads_owned , ..}; var failure = Error.none;
    for root in roots { let error = checker.value(root, 0); if error != Error.none { failure = error; break; } }
    checker.stats.inspection_index_bytes = checker.seen.payloadBytes() + checker.semantic.payloadBytes(); let stats = checker.stats; let reason = checker.reason;
    var plan = blot_support::none<Plan>();
    if failure == Error.none && reason == Reason.none { let order = plan_order.alloc_slice(checker.order.items.len); for value, index in checker.order.items { order[index] = value; } plan = blot_support::some(Plan { pools, gate, roots[0], order, stats, row_policy , ..}); }
    checker.deinit(); return Inspection { reason, stats, plan , ..}, failure;
}
fn paired<G>(self: const Plan&, g: G&, graphs: const blot_reuse_artifact_import::Importer&) -> bool {
    if !self.gate || !self.pools || self.gate.source_pools .!= self.pools || graphs.old .!= self.pools || !graphs.enabled || !blot_support::same_slice_identity(g.evaluator.units, self.gate.units) || graphs.unit_map.len != self.gate.units.len || !blot_support::same_slice_identity(graphs.units, self.gate.units) { return false; }
    for unit, index in graphs.unit_map { if unit != index + 1 { return false; } } for symbol, index in graphs.symbol_map { if symbol != index { return false; } } return true;
}
recursive fn matchesAnchor<G>(self: const Plan&, g: G&, graphs: blot_reuse_artifact_import::Importer&, positions: const i64[:], semantic: const u32[:], mapped: const u32[:], candidate: u32[:], inverse: u32[:], old_id: u32, current: u32, depth: i64, inverse_ids: WordBuffer?) -> bool, Error {
    if old_id == 0 { return current == 0, Error.none; }
    if depth >= 128 || old_id >= positions.len || positions[old_id] == 0x7fffffffffffffff || current == 0 || current >= g.evaluator.storage.values.len { return false, Error.none; }
    if mapped[old_id] != 0 && mapped[old_id] != current { return false, Error.none; } if candidate[old_id] != 0 { return candidate[old_id] == current, Error.none; }
    if inverse[current] != 0 && inverse[current] != old_id { return false, Error.none; }
    assert(self.pools); let old .= self.pools.evaluator; let left = old.values[old_id]; let right = g.evaluator.valueInfo(current);
    if left.kind != right.kind || left.scalar != right.scalar || left.len != right.len || semantic[positions[old_id]] != g.evaluator.valueEvidence(current) { return false, Error.none; }
    if left.kind == ValueKind.package {
        let dictionary, first = graphs.importClosedEvidence(g, left.nominal as u32); if first != Error.none || !dictionary.present { return false, first; }
        let recipe, second = graphs.importClosedEvidence(g, left.bits); if second != Error.none || !recipe.present { return false, second; }
        if dictionary.value != right.nominal || recipe.value != right.bits { return false, Error.none; }
    } else if left.nominal != right.nominal { return false, Error.none; }
    if left.kind == ValueKind.closure {
        let meta = old.closures[left.bits]; let actual = g.evaluator.closureInfo(current);
        if meta.unit != actual.unit || meta.identity != actual.identity || meta.applied != actual.applied || meta.origin != actual.origin || meta.ty != actual.ty || meta.mappings.len != actual.mappings.len || meta.row_mappings.len != actual.row_mappings.len { return false, Error.none; }
        for seed, index in old.type_mappings[meta.mappings.start..meta.mappings.start + meta.mappings.len] {
            let target = g.evaluator.storage.type_mappings[actual.mappings.start + index]; if seed.variable != target.variable { return false, Error.none; }
            let imported, error = graphs.importClosedEvidence(g, seed.evidence); if error != Error.none || !imported.present { return false, error; } if imported.value != target.evidence { return false, Error.none; }
        }
        for seed, index in old.row_mappings[meta.row_mappings.start..meta.row_mappings.start + meta.row_mappings.len] {
            let target = g.evaluator.storage.row_mappings[actual.row_mappings.start + index]; if seed.variable != target.variable { return false, Error.none; } var row: u32 = 0;
            if seed.evidence != 0 { let imported, error = graphs.importSemanticRow(g, seed.evidence); if error != Error.none || !imported.present { return false, error; } row = imported.value; }
            if row != target.evidence { return false, Error.none; }
        }
    } else if left.kind != ValueKind.package && left.bits != right.bits { return false, Error.none; }
    let record = old.value_records[old_id]; var names: const u32[:] = []; if record != 0 { let fields = old.record_layouts[record]; names = old.field_names[fields.start..fields.start + fields.len]; }
    if names != g.evaluator.recordFieldNames(current) { return false, Error.none; }
    candidate[old_id] = current;
    if inverse[current] == 0 && inverse_ids { let error = inverse_ids.push(current); if error != Error.none { return false, error; } } inverse[current] = old_id;
    let current_children = g.evaluator.valueChildren(current);
    for child, index in old.children[left.start..left.start + left.len] { let valid, error = self.matchesAnchor(g, graphs, positions, semantic, mapped, candidate, inverse, child, current_children[index], depth + 1, inverse_ids); if error != Error.none || !valid { return false, error; } }
    return true, Error.none;
}
fn matchInto<G>(self: const Plan&, g: G&, graphs: blot_reuse_artifact_import::Importer&, old_root: u32, current_root: u32, mapped: u32[:]) -> bool, Error {
    var scratch = QueryScratch { allocation_owner: g.evaluator.allocation_owner , ..}; let roots = [old_root]; let current = [current_root];
    let result, error = self.matchEngine(g, graphs, roots, current, mapped, scratch, false); scratch.deinit(); return result, error;
}
fn matchIntoWithScratch<G>(self: const Plan&, g: G&, graphs: blot_reuse_artifact_import::Importer&, old_root: u32, current_root: u32, mapped: u32[:], scratch: QueryScratch&) -> bool, Error { let roots = [old_root]; let current = [current_root]; return self.matchRootsIntoWithScratch(g, graphs, roots, current, mapped, scratch); }
fn matchRootsIntoWithScratch<G>(self: const Plan&, g: G&, graphs: blot_reuse_artifact_import::Importer&, old_roots: const u32[:], current_roots: const u32[:], mapped: u32[:], scratch: QueryScratch&) -> bool, Error { return self.matchEngine(g, graphs, old_roots, current_roots, mapped, scratch, true); }
fn matchEngine<G>(self: const Plan&, g: G&, graphs: blot_reuse_artifact_import::Importer&, old_roots: const u32[:], current_roots: const u32[:], mapped: u32[:], scratch: QueryScratch&, borrowed_anchors: bool) -> bool, Error {
    if old_roots.len == 0 || old_roots.len != current_roots.len { return false, Error.none; }
    let bound = scratch.bind(self, g); if bound != Error.none { return false, bound; }
    if !self.paired(g, graphs) || mapped.len != self.pools.evaluator.values.len || (borrowed_anchors && !blot_support::same_slice_identity(mapped, scratch.anchors.items)) { return false, Error.declined; }
    let p = scratch.grow(scratch.positions, mapped.len, 0x7fffffffffffffff as i64); if p != Error.none { return false, p; }
    let c = scratch.grow(scratch.candidate, mapped.len, 0 as u32); if c != Error.none { return false, c; }
    let i = scratch.grow(scratch.inverse, g.evaluator.storage.values.len, 0 as u32); if i != Error.none { return false, i; }
    let s = scratch.semantic.resize(self.order.len, 0 as u32); if s != Error.none { return false, s; }
    let inverse_capacity = scratch.inverse_ids.ensure(scratch.anchor_ids.items.len + self.order.len); if inverse_capacity != Error.none { return false, inverse_capacity; }
    let anchor_capacity = scratch.anchor_ids.ensure(self.order.len); if anchor_capacity != Error.none { return false, anchor_capacity; }
    if !borrowed_anchors { scratch.anchor_ids.clear(); for current, old in mapped { if current != 0 { let error = scratch.anchor_ids.push(old as u32); if error != Error.none { return false, error; } } } }
    scratch.stats.match_calls++; scratch.stats.plan_positions += self.order.len; scratch.stats.baseline_match_index_entries += mapped.len * 4 + g.evaluator.storage.values.len;
    for id, index in self.order { scratch.positions.items[id] = index; }
    let anchors_before = scratch.anchor_ids.items.len;
    let matched, failure = self.matchPrepared(g, graphs, old_roots, current_roots, mapped, scratch);
    if !matched || failure != Error.none { for old in scratch.anchor_ids.items[anchors_before..] { mapped[old] = 0; } scratch.anchor_ids.resize(anchors_before); }
    scratch.finishMatch(self.order); return matched, failure;
}
fn matchPrepared<G>(self: const Plan&, g: G&, graphs: blot_reuse_artifact_import::Importer&, old_roots: const u32[:], current_roots: const u32[:], mapped: u32[:], scratch: QueryScratch&) -> bool, Error {
    assert(self.pools);
    for id, index in self.order {
        var actual: u32 = 0; if self.pools.evaluator.value_evidence[id] != 0 { let imported, error = graphs.importClosedEvidence(g, self.pools.evaluator.value_evidence[id]); if error != Error.none || !imported.present { return false, error; } actual = imported.value; } scratch.semantic.items[index] = actual;
    }
    for old in scratch.anchor_ids.items { let current = mapped[old]; if current >= scratch.inverse.items.len { return false, Error.none; } if scratch.inverse.items[current] == 0 { let error = scratch.inverse_ids.push(current); if error != Error.none { return false, error; } } scratch.inverse.items[current] = old; }
    for old_root, index in old_roots {
        let matched, error = self.matchesAnchor(g, graphs, scratch.positions.items, scratch.semantic.items, mapped, scratch.candidate.items, scratch.inverse.items, old_root, current_roots[index], 0, scratch.inverse_ids); if error != Error.none || !matched { return false, error; }
        for old in self.order { let current = scratch.candidate.items[old]; if current == 0 { continue; } if mapped[old] == 0 { let failure = scratch.anchor_ids.push(old); if failure != Error.none { return false, failure; } } mapped[old] = current; scratch.candidate.items[old] = 0; }
    } return true, Error.none;
}

fn transportRequire(value: bool) -> Error {if !value {return Error.declined;} return Error.none;}
// Materialization converts every graph and reserves outputs before publication.
struct QueryStorage { values_before: i64, values_added: i64, children_added: i64, exact: bool=true, precharged: bool=false, buffers: const blot_eval_eval_collection_growth::BufferEffect[:]=[], root_buffer: blot_support::Option<blot_eval_eval_collection_growth::Frontier> }
struct Transport { old: blot_eval_eval_collection_growth::Span, start: u32 }
struct Package { dictionary: u32, recipe: u32 }
reusable[] var transport_runs: Transport[>..]=[];
reusable[] var package_slots: dictionary_slot<u32,Package>[>..]=[];
struct Material<G> {
    plan: const Plan&, generator: G&, graphs: blot_reuse_artifact_import::Importer&, scratch: QueryScratch&,
    entry: blot_support::Option<u32>, storage: blot_support::Option<QueryStorage>,
    root_buffer: blot_support::Option<blot_eval_eval_collection_growth::Frontier>, transported: Transport[:]=[],
    packages: blot_support_pooled_map::Map<u32,Package> = blot_support_pooled_map::Map<u32,Package>{..}, count: i64=0, added_children: i64=0, children_prepared: bool=false,
}
fn deinit<G>(self: Material<G>&) { if self.transported.len != 0 {transport_runs.free_slice(self.transported);} self.transported=[]; blot_support_pooled_map::deinit(self.packages,package_slots); }
fn materialize<G>(self: const Plan&,g: G&) -> u32,Error { return self.materializeWithGlobalAnchors(g,blot_support::none<u32>()); }
fn materializeWithGlobalAnchors<G>(self: const Plan&,g: G&,entry: blot_support::Option<u32>) -> u32,Error { let mapped,error=self.materializeMapped(g,entry,blot_support::none<const u32[:]>()); if error!=Error.none {return 0,error;} let result=mapped[self.root]; releaseMapped(mapped); return result,Error.none; }
fn releaseMapped(mapped: u32[:]) { if mapped.len!=0 {scratch_wordbuffer.free_slice(mapped);} }
fn materializeMapped<G>(self: const Plan&,g: G&,entry: blot_support::Option<u32>,seeds: blot_support::Option<const u32[:]>) -> u32[:],Error {return self.materializeImpl(g,entry,seeds,blot_support::none<QueryStorage>(),null,null);}
fn materializeReachableMapped<G>(self: const Plan&,g: G&,graphs: blot_reuse_artifact_import::Importer&,seeds: const u32[:]) -> u32[:],Error {let storage=QueryStorage{values_before:0,values_added:0x7fffffffffffffff,children_added:0x7fffffffffffffff,exact:false, ..}; return self.materializeImpl(g,blot_support::none<u32>(),blot_support::some(seeds),blot_support::some(storage),graphs,null);}
fn materializeReceiptMapped<G>(self: const Plan&,g: G&,seeds: const u32[:],storage: QueryStorage) -> u32[:],Error {return self.materializeImpl(g,blot_support::none<u32>(),blot_support::some(seeds),blot_support::some(storage),null,null);}
fn materializeReceiptMappedWithImporter<G>(self: const Plan&,g: G&,graphs: blot_reuse_artifact_import::Importer&,seeds: const u32[:],storage: QueryStorage) -> u32[:],Error {return self.materializeImpl(g,blot_support::none<u32>(),blot_support::some(seeds),blot_support::some(storage),graphs,null);}
fn materializeReceiptWithScratch<G>(self: const Plan&,g: G&,graphs: blot_reuse_artifact_import::Importer&,seeds: const u32[:],storage: QueryStorage,scratch: QueryScratch&) -> u32[:],Error {
    let error=scratch.bind(self,g); if error!=Error.none {return [],error;} if !blot_support::same_slice_identity(seeds,scratch.anchors.items) {return [],Error.declined;}
    return self.materializeImpl(g,blot_support::none<u32>(),blot_support::some(seeds),blot_support::some(storage),graphs,scratch);
}
fn materializeImpl<G>(self: const Plan&,g: G&,entry: blot_support::Option<u32>,seeds: blot_support::Option<const u32[:]>,storage: blot_support::Option<QueryStorage>,paired: blot_reuse_artifact_import::Importer?,scratch: QueryScratch?) -> u32[:],Error {
    if !self.gate || !self.pools || self.gate.source_pools .!= self.pools || !self.gate.enabled || !blot_support::same_slice_identity(g.evaluator.units,self.gate.units) {return [],Error.declined;}
    var owned=blot_support::none<blot_reuse_artifact_import::Importer>(); var graphs: blot_reuse_artifact_import::Importer?=paired;
    if !graphs {let created,error=blot_reuse_artifact_import::init(g.evaluator.allocation_owner,self.pools,self.gate.units,self.pools.identity.value.view(),self.gate.units.len); if error!=Error.none {return [],error;} owned=blot_support::some(created); graphs .= owned.value;}
    assert(graphs); var temporary=QueryScratch{allocation_owner:g.evaluator.allocation_owner, ..}; var buffers: QueryScratch?=scratch;
    if !buffers {let run=scratch_wordbuffer.alloc_slice(self.pools.evaluator.values.len); for &word in run {word=0;} temporary.anchors=WordBuffer{run,run, ..}; buffers .= temporary;}
    assert(buffers); let mapped,error=self.materializeOwned(g,graphs,entry,seeds,storage,buffers,scratch!=null);
    if owned.present {owned.value.deinit();}
    if error==Error.none && !scratch {temporary.anchors.storage=[]; temporary.anchors.items=[];}
    if !scratch {temporary.deinit();} return mapped,error;
}
fn materializeOwned<G>(self: const Plan&,g: G&,graphs: blot_reuse_artifact_import::Importer&,entry: blot_support::Option<u32>,seeds: blot_support::Option<const u32[:]>,storage: blot_support::Option<QueryStorage>,buffers: QueryScratch&,retained_scratch: bool) -> u32[:],Error {
    assert(self.gate && self.pools);
    if !graphs.enabled || graphs.old .!= self.pools || !blot_support::same_slice_identity(graphs.units,self.gate.units) || graphs.unit_map.len!=self.gate.units.len || graphs.allocation_owner!=g.evaluator.allocation_owner || (graphs.generator_owner!=0 && graphs.generator_owner!=g.owner_id) {return [],Error.declined;}
    for mapped_unit,unit in graphs.unit_map {if mapped_unit!=unit+1 {return [],Error.declined;} graphs.stable[unit]=self.gate.structural_units[unit];}
    for mapped_symbol,symbol in graphs.symbol_map {if mapped_symbol!=symbol {return [],Error.declined;}}
    let mapped=buffers.anchors.items; if seeds.present {if seeds.value.len!=mapped.len {return [],Error.declined;} if !retained_scratch {for value,index in seeds.value {mapped[index]=value;}}}
    var state=Material<G>{self,g,graphs,buffers,entry,storage, ..}; let error=state.prepareMaterial(retained_scratch);
    if error==Error.none {state.publishMaterial(retained_scratch);} if retained_scratch && state.children_prepared {buffers.finishChildren(self.order);} state.deinit(); if error!=Error.none {return [],error;} return mapped,Error.none;
}
fn prepareMaterial<G>(self: Material<G>&,retained_scratch: bool) -> Error {
    let plan .= self.plan; assert(plan.pools); let old .= plan.pools.evaluator; let mapped=self.scratch.anchors.items;
    if self.storage.present && self.storage.value.root_buffer.present {
        let buffer=self.storage.value.root_buffer.value; let root=old.values[plan.root];
        if mapped[plan.root]!=0 || (root.kind!=ValueKind.array && root.kind!=ValueKind.list) || root.len==0 || buffer.capacity<root.len || buffer.offset>buffer.capacity-root.len {return Error.declined;}
        for id in plan.order {if id!=plan.root && old.values[id].kind!=ValueKind.scalar {return Error.declined;}} self.root_buffer=blot_support::some(buffer);
    }
    { let propagated_error = self.scratch.semantic.resize(plan.order.len,0 as u32); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.scratch.types.resize(plan.stats.type_maps,default<blot_eval_type_evidence::Mapping>()); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.scratch.rows.resize(plan.stats.row_maps,default<blot_eval_type_evidence::RowMapping>()); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.scratch.anchor_ids.ensure(plan.order.len); if propagated_error != Error.none { return propagated_error; } }
    var type_index: i64=0; var row_index: i64=0;
    for id,index in plan.order {
        var actual: u32=0; if old.value_evidence[id]!=0 {let value,error=self.graphs.importClosedEvidence(self.generator,old.value_evidence[id]); { let propagated_error = error; if propagated_error != Error.none { return propagated_error; } } { let propagated_error = transportRequire(value.present); if propagated_error != Error.none { return propagated_error; } } actual=value.value;} self.scratch.semantic.items[index]=actual;
        if old.values[id].kind!=ValueKind.closure {continue;} let meta=old.closures[old.values[id].bits];
        for mapping in old.type_mappings[meta.mappings.start..meta.mappings.start+meta.mappings.len] {let value,error=self.graphs.importClosedEvidence(self.generator,mapping.evidence); { let propagated_error = error; if propagated_error != Error.none { return propagated_error; } } { let propagated_error = transportRequire(value.present); if propagated_error != Error.none { return propagated_error; } } self.scratch.types.items[type_index]=blot_eval_type_evidence::Mapping{mapping.variable,value.value, ..}; type_index++;}
        for mapping in old.row_mappings[meta.row_mappings.start..meta.row_mappings.start+meta.row_mappings.len] {if mapping.evidence!=0 && plan.row_policy==RowPolicy.empty_only {return Error.declined;} var imported: u32=0; if mapping.evidence!=0 {let value,error=self.graphs.importSemanticRow(self.generator,mapping.evidence); { let propagated_error = error; if propagated_error != Error.none { return propagated_error; } } { let propagated_error = transportRequire(value.present); if propagated_error != Error.none { return propagated_error; } } imported=value.value;} self.scratch.rows.items[row_index]=blot_eval_type_evidence::RowMapping{mapping.variable,imported, ..}; row_index++;}
    }
    if self.entry.present {{ let propagated_error = plan.anchorGlobals(self.generator,self.graphs,self.scratch.semantic.items,mapped,self.entry.value); if propagated_error != Error.none { return propagated_error; } }}
    for id in plan.order {if mapped[id]==0 {self.count++;}}
    if retained_scratch || self.storage.present {{ let propagated_error = self.scratch.grow(self.scratch.children,old.children.len,0xffffffff as u32); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.scratch.grow(self.scratch.append_children,old.values.len,false); if propagated_error != Error.none { return propagated_error; } }}
    { let propagated_error = self.scratch.child_ids.ensure(plan.stats.children); if propagated_error != Error.none { return propagated_error; } } if retained_scratch {self.scratch.stats.materializations++; self.scratch.stats.baseline_material_index_entries+=old.values.len*3+old.children.len;}
    self.children_prepared=true; var effects: const blot_eval_eval_collection_growth::BufferEffect[:]=[]; if self.storage.present {effects=self.storage.value.buffers;} self.transported=transport_runs.alloc_slice(effects.len);
    if self.storage.present {{ let propagated_error = self.prepareSpans(self.storage.value,effects,retained_scratch); if propagated_error != Error.none { return propagated_error; } }}
    for id in plan.order {if old.values[id].kind!=ValueKind.package || mapped[id]!=0 {continue;} let info=old.values[id]; let dictionary,first=self.graphs.importClosedEvidence(self.generator,info.nominal as u32); { let propagated_error = first; if propagated_error != Error.none { return propagated_error; } } { let propagated_error = transportRequire(dictionary.present); if propagated_error != Error.none { return propagated_error; } } let recipe,second=self.graphs.importClosedEvidence(self.generator,info.bits); { let propagated_error = second; if propagated_error != Error.none { return propagated_error; } } { let propagated_error = transportRequire(recipe.present); if propagated_error != Error.none { return propagated_error; } } blot_support_pooled_map::insert(self.packages,id,Package{dictionary.value,recipe.value, ..},package_slots);}
    let session .= self.generator.evaluator; var child_count=plan.stats.children; if self.storage.present {child_count=self.added_children;}
    var values_before=session.constantValueCount(); var children_before=session.constantChildCount();
    if self.storage.present && self.storage.value.precharged {if self.count>session.constant_value_debt || child_count>session.constant_child_debt {return Error.declined;} values_before-=self.count; children_before-=child_count;}
    var value_room=session.options.max_values-values_before; if value_room<0 {value_room=0;} var child_room=session.options.max_children-children_before; if child_room<0 {child_room=0;} if self.count>value_room || child_count>child_room {return Error.declined;}
    var reserve_children=plan.stats.children; if self.storage.present {reserve_children=self.added_children;}
    if !room(session.storage.values.len,plan.order.len) || !room(session.storage.children.len,reserve_children) || !room(session.storage.closures.len,plan.stats.closures) || !room(session.storage.type_mappings.len,self.scratch.types.items.len) || !room(session.storage.row_mappings.len,self.scratch.rows.items.len) || !room(session.storage.record_layouts.len,plan.order.len) || !room(session.storage.field_names.len,plan.stats.fields) {return Error.declined;}
    reserve(session.storage.values,plan.order.len,default<ValueInfo>()); reserve(session.storage.value_evidence,plan.order.len,0 as u32); reserve(session.storage.value_records,plan.order.len,0 as u32); reserve(session.storage.children,reserve_children,0 as u32); reserve(session.storage.closures,plan.stats.closures,default<blot_eval_eval_values::ClosureValue>()); reserve(session.storage.type_mappings,self.scratch.types.items.len,default<blot_eval_type_evidence::Mapping>()); reserve(session.storage.row_mappings,self.scratch.rows.items.len,default<blot_eval_type_evidence::RowMapping>()); reserve(session.storage.record_layouts,plan.order.len,blot_check_core::List{..}); reserve(session.storage.field_names,plan.stats.fields,0 as u32); session.storage.collection_buffers.buffers.reserve(session.storage.collection_buffers.buffers.count+effects.len);
    return Error.none;
}
fn reserve<T>(values: T[>..<]&,added: i64,initial: T) {let length=values.len; values.resize(length+added,initial); values.resize(length);}
fn prepareSpans<G>(self: Material<G>&,query: QueryStorage,effects: const blot_eval_eval_collection_growth::BufferEffect[:],retained_scratch: bool) -> Error {
    assert(self.plan.pools); let plan .= self.plan; let old .= plan.pools.evaluator; let session .= self.generator.evaluator; let mapped=self.scratch.anchors.items; let positions=self.scratch.children.items; let append_children=self.scratch.append_children.items;
    if self.count>query.values_added || (query.exact && self.count!=query.values_added) {return Error.declined;}
    for id in plan.order {
        let info=old.values[id]; if mapped[id]==0 {if id<query.values_before {return Error.declined;} continue;}
        if mapped[id]>=session.storage.values.len {return Error.declined;} let current=session.valueInfo(mapped[id]); if current.len!=info.len {return Error.declined;}
        for &position,index in positions[info.start..info.start+info.len] {let expected=current.start+index as u32; if position!=0xffffffff && position!=expected {return Error.declined;} if position==0xffffffff && retained_scratch {{ let propagated_error = self.scratch.child_ids.push(info.start+index as u32); if propagated_error != Error.none { return propagated_error; } }} position=expected;}
    }
    if effects.len!=0 && self.root_buffer.present {return Error.declined;}
    for effect,index in effects {
        if effect.value==0 || effect.value>=old.values.len || mapped[effect.value]!=0 {return Error.declined;} var reachable=false; for id in plan.order {if id==effect.value {reachable=true; break;}} if !reachable {return Error.declined;}
        let latest=old.values[effect.value]; let frontier=effect.frontier;
        if (latest.kind!=ValueKind.array && latest.kind!=ValueKind.list) || latest.len==0 || frontier.capacity<latest.len || frontier.offset>frontier.capacity-latest.len || frontier.offset>latest.start {return Error.declined;}
        let span=blot_eval_eval_collection_growth::Span{latest.start-frontier.offset,frontier.capacity, ..}; if !range(span.start,span.len,old.children.len) {return Error.declined;}
        for prior in self.transported[..index] {if span.start as i64<prior.old.start as i64+prior.old.len && prior.old.start as i64<span.start as i64+span.len {return Error.declined;}}
        if !room(session.storage.children.len,self.added_children+frontier.capacity) {return Error.declined;} let start=(session.storage.children.len+self.added_children) as u32; self.transported[index]=Transport{span,start, ..};
        for id in plan.order {
            let info=old.values[id]; if info.len==0 || info.start as i64>=span.start as i64+span.len || span.start as i64>=info.start as i64+info.len {continue;}
            if mapped[id]!=0 || info.start<span.start || info.start as i64+info.len>span.start as i64+span.len {return Error.declined;}
            for &position,child_index in positions[info.start..info.start+info.len] {let expected=start+info.start-span.start+child_index as u32; if position!=0xffffffff && position!=expected {return Error.declined;} if position==0xffffffff && retained_scratch {{ let propagated_error = self.scratch.child_ids.push(info.start+child_index as u32); if propagated_error != Error.none { return propagated_error; } }} position=expected;}
        }
        self.added_children+=frontier.capacity;
    }
    for id in plan.order {
        if mapped[id]!=0 {continue;} let info=old.values[id]; if info.len==0 {continue;} let span=positions[info.start..info.start+info.len];
        if span[0]==0xffffffff {
            for position in span {if position!=0xffffffff {return Error.declined;}} var capacity=info.len; var offset: u32=0; if id==plan.root && self.root_buffer.present {capacity=self.root_buffer.value.capacity; offset=self.root_buffer.value.offset;}
            if !room(session.storage.children.len,self.added_children+capacity) {return Error.declined;} let start=(session.storage.children.len+self.added_children+offset) as u32;
            for &position,index in span {if retained_scratch {{ let propagated_error = self.scratch.child_ids.push(info.start+index as u32); if propagated_error != Error.none { return propagated_error; } }} position=start+index as u32;} append_children[id]=true; self.added_children+=capacity;
        } else {for position,index in span {if position!=span[0]+index {return Error.declined;}}}
    }
    if self.added_children>query.children_added || (query.exact && self.added_children!=query.children_added) {return Error.declined;} return Error.none;
}
fn publishMaterial<G>(self: Material<G>&,retained_scratch: bool) {
    assert(self.plan.pools); let plan .= self.plan; let old .= plan.pools.evaluator; let session .= self.generator.evaluator; let mapped=self.scratch.anchors.items;
    var child_count=plan.stats.children; if self.storage.present {child_count=self.added_children;} if self.storage.present && self.storage.value.precharged {session.constant_value_debt-=self.count; session.constant_child_debt-=child_count;}
    for buffer in self.transported {assert(buffer.start==session.storage.children.len); session.storage.children.resize(session.storage.children.len+buffer.old.len,0);}
    var type_index: i64=0; var row_index: i64=0;
    for id,index in plan.order {
        if mapped[id]!=0 {if old.values[id].kind==ValueKind.closure {let meta=old.closures[old.values[id].bits]; type_index+=meta.mappings.len; row_index+=meta.row_mappings.len;} continue;}
        var info=old.values[id]; let package .= blot_support_pooled_map::get(self.packages,id); if package {info.nominal=package.dictionary; info.bits=package.recipe;}
        let children=old.children[info.start..info.start+info.len]; if self.storage.present && info.len!=0 {info.start=self.scratch.children.items[info.start];} else {info.start=session.storage.children.len as u32;}
        if !self.storage.present || self.scratch.append_children.items[id] {
            if id==plan.root && self.root_buffer.present {let buffer=self.root_buffer.value; let start=session.storage.children.len; session.storage.children.resize(start+buffer.capacity,0); for child,child_index in children {session.storage.children[start+buffer.offset+child_index]=mapped[child];}}
            else {for child in children {session.storage.children.push(mapped[child]);}}
        }
        if self.storage.present && info.len!=0 && !self.scratch.append_children.items[id] {
            for buffer in self.transported {let original=old.values[id]; if original.start>=buffer.old.start && original.start as i64+original.len<=buffer.old.start as i64+buffer.old.len {for child,child_index in children {session.storage.children[info.start+child_index]=mapped[child];} break;}}
        }
        if info.kind==ValueKind.closure {var meta=old.closures[info.bits]; let length=meta.mappings.len; meta.mappings.start=session.storage.type_mappings.len as u32; session.storage.type_mappings.append(self.scratch.types.items[type_index..type_index+length]); type_index+=length; let rows=meta.row_mappings.len; meta.row_mappings.start=session.storage.row_mappings.len as u32; session.storage.row_mappings.append(self.scratch.rows.items[row_index..row_index+rows]); row_index+=rows; info.bits=session.storage.closures.len as u32; session.storage.closures.push(meta);}
        var record: u32=0; if old.value_records[id]!=0 {let fields=old.record_layouts[old.value_records[id]]; record=session.storage.record_layouts.len as u32; session.storage.record_layouts.push(blot_check_core::List{session.storage.field_names.len as u32,fields.len, ..}); session.storage.field_names.append(old.field_names[fields.start..fields.start+fields.len]);}
        if retained_scratch {let error=self.scratch.anchor_ids.push(id); assert(error==Error.none);} mapped[id]=session.storage.values.len as u32; session.storage.values.push(info); session.storage.value_evidence.push(self.scratch.semantic.items[index]); session.storage.value_records.push(record);
    }
    if self.storage.present {for effect,index in self.storage.value.buffers {let latest=session.valueInfo(mapped[effect.value]); let buffer=self.transported[index]; session.storage.collection_buffers.buffers.insert(blot_eval_eval_collection_growth::Span{latest.start,latest.len, ..},blot_eval_eval_collection_growth::Span{buffer.start,buffer.old.len, ..});}}
}
fn anchorGlobals<G>(self: const Plan&, g: G&, graphs: blot_reuse_artifact_import::Importer&, semantic: const u32[:], mapped: u32[:], entry: u32) -> Error {
    assert(self.pools); var positions = SizeBuffer {..}; var candidate = WordBuffer {..}; var inverse = WordBuffer {..};
    var error = positions.resize(self.pools.evaluator.values.len, 0x7fffffffffffffff as i64);
    if error == Error.none { error = candidate.resize(positions.items.len, 0 as u32); }
    if error == Error.none { error = inverse.resize(g.evaluator.storage.values.len, 0 as u32); }
    if error == Error.none { for id, index in self.order { positions.items[id] = index; } error = self.anchorGlobalsPrepared(g, graphs, semantic, mapped, entry, positions.items, candidate.items, inverse.items); }
    positions.deinit(); candidate.deinit(); inverse.deinit(); return error;
}
fn anchorGlobalsPrepared<G>(self: const Plan&, g: G&, graphs: blot_reuse_artifact_import::Importer&, semantic: const u32[:], mapped: u32[:], entry: u32, positions: const i64[:], candidate: u32[:], inverse: u32[:]) -> Error {
    assert(self.pools && self.gate);
    for pin in self.pools.modules {
        if pin.unit == entry { continue; }
        for body in pin.module.bodies[1..] {
            if body.runtime || !self.gate.admits(blot_check_core::BindingRef { pin.unit, body.binding , ..}) { continue; }
            let old_slot = self.pools.slots[self.pools.binding_offsets[pin.unit - 1] + body.binding];
            if old_slot.state != 2 || old_slot.value == 0 || old_slot.value >= positions.len || positions[old_slot.value] == 0x7fffffffffffffff { continue; }
            let slot = g.evaluator.slots[g.evaluator.binding_offsets[pin.unit - 1] + body.binding]; if slot.state != blot_eval_core_eval::State.complete { return Error.declined; }
            for &value in candidate { value = 0; } for &value in inverse { value = 0; }
            for current, old in mapped { if current != 0 { if current >= inverse.len { return Error.declined; } inverse[current] = old as u32; } }
            let matched, error = self.matchesAnchor(g, graphs, positions, semantic, mapped, candidate, inverse, old_slot.value, slot.value, 0, null);
            if error != Error.none { return error; } if !matched { return Error.declined; }
            for current, old in candidate { if current != 0 { mapped[old] = current; } }
        }
    } return Error.none;
}
fn reasonCode(reason: Reason) -> i64 { match reason { Reason.none => 0, Reason.source => 1, Reason.slot => 2, Reason.bounds => 3, Reason.open_evidence => 4, Reason.domain => 5, Reason.owner => 6, Reason.cycle => 7, Reason.quota => 8 } }
struct RootObservation { target: blot_check_core::BindingRef = blot_check_core::BindingRef { binding: 0 , ..}, span: blot_check_core::Span = blot_check_core::Span { 0, 0 , ..}, reason: Reason = Reason.none, stats: Stats = Stats {..} }
struct Probe {
    enabled: bool = false, gate: bool = false, requests: i64 = 0, admitted: i64 = 0,
    reasons: i64[9] = [0; 9], root_kinds: i64[22] = [0; 22], graph_values: i64 = 0, graph_closures: i64 = 0,
    fresh_count: i64 = 0, fresh_truncated: i64 = 0, fresh: RootObservation[32] = [RootObservation {..}; 32],
}
fn observe(pools: const Pools&, gate: const Gate&, cached_units: i64) -> Probe, Error {
    var result = Probe { enabled: true, gate: gate.enabled , ..};
    for pin in pools.modules { for body in pin.module.bodies[1..] {
        if body.is_function || body.runtime { continue; } let target = blot_check_core::BindingRef { pin.unit, body.binding , ..};
        var found, error = inspect(pools, gate, target); if error != Error.none { return result, error; }
        result.requests++; result.reasons[reasonCode(found.reason)]++;
        if found.plan.present { let plan = found.plan.value; result.admitted++; result.graph_values += plan.stats.values; result.graph_closures += plan.stats.closures; result.root_kinds[blot_eval_eval_values::valueKindCode(pools.evaluator.values[plan.root].kind)]++; found.plan.value.deinit(); }
        if pin.unit > cached_units { if result.fresh_count < result.fresh.len { result.fresh[result.fresh_count] = RootObservation { target, body.span, found.reason, found.stats , ..}; result.fresh_count++; } else { result.fresh_truncated++; } }
    } } return result, Error.none;
}
