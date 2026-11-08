// Private source-owned representation transport. No slot, fuel or call authority.
namespace blot_reuse_source_value_template;
import reuse.catalog_storage;
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
fn requiredPools(value:const Pools?)->const Pools& {assert(value);return value;}
fn requiredGate(value:const Gate?)->const Gate& {assert(value);return value;}
type ValueInfo = blot_eval_eval_values::ValueInfo;
type ValueKind = blot_eval_eval_values::ValueKind;
type ClosureOrigin = blot_eval_eval_values::ClosureOrigin;
type EvidenceTag = blot_eval_type_evidence::Tag;
type TypeTag = blot_check_types::Tag;
recursive fn versionType(types: const blot_check_core::Types&, id: u32, budget: i64&, depth: i64) -> bool {
    if id == 0 { return false; } if id >= types.nodes.len || depth == 128 || budget == 0 { return true; } budget--;
    let n = types.node(id);
    if n.tag == blot_check_types::Tag.function || n.tag == blot_check_types::Tag.provider { for label in types.rowLabels(n.c) { let operation = types.operation(label); if operation.instance.unit == 0 && versionType(types, operation.instance.decl, budget, depth + 1) { return true; } for argument in types.operationArguments(label) { if versionType(types, argument, budget, depth + 1) { return true; } } } }
    match n.tag {
        instance_version => { return true; },
        function => { return versionType(types, n.a, budget, depth + 1) || versionType(types, n.b, budget, depth + 1); },
        usage, scoped => { if versionType(types, n.a, budget, depth + 1) { return true; } if (n.tag == blot_check_types::Tag.usage && n.c != 0) || (n.tag == blot_check_types::Tag.scoped && n.b == 0) { return versionType(types, n.c, budget, depth + 1); } },
        array, list, cursor, resolver, provider, forall, existential => { return versionType(types, n.a, budget, depth + 1); },
        state_provider => { return versionType(types, n.a, budget, depth + 1) || versionType(types, n.b, budget, depth + 1) || versionType(types, n.c, budget, depth + 1); },
        product => { for child in types.list(blot_check_types::List { n.a, n.b , ..}) { if versionType(types, child, budget, depth + 1) { return true; } } },
        record => { for index in 0..n.b { if versionType(types, types.recordField(n, index).ty, budget, depth + 1) { return true; } } },
        nominal, projection, instance_selection => { for child in types.nominalArguments(n) { if versionType(types, child, budget, depth + 1) { return true; } } }, _ => {},
    } return false;
}
fn moduleGenerative(module: const Module&) -> bool { for binding in module.bindings { if binding.scheme.generative.len != 0 { return true; } } for body in module.bodies { if body.scheme.generative.len != 0 { return true; } } for node in module.types.nodes { if node.tag == blot_check_types::Tag.instance_version { return true; } } return false; }
fn generativeBody(module: const Module&, root: u32, ty: u32) -> bool, Error {
    var versions = false; for n in module.types.nodes { if n.tag == blot_check_types::Tag.instance_version { versions = true; break; } } if !versions { return false, blot_error::Error.none; }
    var budget: i64 = 4096; if versionType(module.types, ty, budget, 0) { return true, blot_error::Error.none; }
    var items: u32[>..<] = []; var work = blot_eval_body_recipe::Pending { items, 4096 , ..}; items.push(root); var visits: i64 = 0;
    loop {
        let id, present = work.pop(); if !present { break; } if id == 0 { continue; } if id >= module.nodes.len || visits == 4096 { return true, blot_error::Error.none; } visits++;
        let n = module.node(id); budget = 4096; if versionType(module.types, n.ty, budget, 0) { return true, blot_error::Error.none; }
        if n.tag == blot_check_core::Tag.call && versionType(module.types, module.call(id).callee_type, budget, 0) { return true, blot_error::Error.none; }
        if n.tag == blot_check_core::Tag.closure { let closure = module.closure(id); if versionType(module.types, closure.function_type, budget, 0) || versionType(module.types, closure.parameter.ty, budget, 0) { return true, blot_error::Error.none; } let error = work.append(closure.body); if error == blot_error::Error.out_of_memory { return false, error; } if error != blot_error::Error.none { return true, blot_error::Error.none; } }
        let error = blot_eval_body_recipe::appendChildren(work, module, id, false); if error == blot_error::Error.out_of_memory { return false, error; } if error != blot_error::Error.none { return true, blot_error::Error.none; }
    } return false, blot_error::Error.none;
}
fn generativeNamed(module: const Module&, binding: u32) -> bool, Error { if binding >= module.bindings.len { return true, blot_error::Error.none; } let definition .= module.body(binding); if !definition || definition.scheme.generative.len != 0 || module.binding(binding).scheme.generative.len != 0 { return true, blot_error::Error.none; } return generativeBody(module, definition.root, module.binding(binding).ty); }
fn generativeClosure(module: const Module&, catalog: u32) -> bool, Error { if catalog >= module.closures.len { return true, blot_error::Error.none; } let closure = module.closures[catalog]; if closure.qualifier != 0 && closure.qualifier < module.bindings.len { if module.bindings[closure.qualifier].scheme.generative.len != 0 { return true, blot_error::Error.none; } let definition .= module.body(closure.qualifier); if definition && definition.scheme.generative.len != 0 { return true, blot_error::Error.none; } } return generativeBody(module, closure.body, closure.function_type); }
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
    let info = snapshot.values[id]; if info.kind != blot_eval_eval_values::ValueKind.scalar || info.nominal != 0 || info.len != 0 || info.start > snapshot.children.len || snapshot.value_records[id] != 0 { return no; }
    var expected = blot_eval_type_evidence::Tag.absent;
    match info.scalar { blot_backend_runtime_ir::SC_unit => { expected = blot_eval_type_evidence::Tag.unit; }, blot_backend_runtime_ir::SC_bool => { expected = blot_eval_type_evidence::Tag.boolean; }, blot_backend_runtime_ir::SC_u32 => { expected = blot_eval_type_evidence::Tag.unsigned32; }, blot_backend_runtime_ir::SC_f32 => { expected = blot_eval_type_evidence::Tag.floating32; }, _ => { return no; } }
    if (info.scalar == blot_backend_runtime_ir::SC_unit && info.bits != 0) || (info.scalar == blot_backend_runtime_ir::SC_bool && info.bits > 1) { return no; }
    let semantic = snapshot.value_evidence[id]; if semantic == 0 || semantic >= snapshot.evidence.nodes.len { return no; } let node = snapshot.evidence.nodes[semantic];
    if node.tag != expected || node.a != 0 || node.b != 0 || node.c != 0 { return no; } return blot_support::some(info);
}
fn materializeScalarRoot(session: blot_eval_core_eval::Session&, info: ValueInfo) -> u32, Error {
    if info.kind != blot_eval_eval_values::ValueKind.scalar || info.len != 0 || info.nominal != 0 { return 0, blot_error::Error.declined; }
    var semantic: u32 = 0; match info.scalar { blot_backend_runtime_ir::SC_unit => { semantic = blot_check_types::unit; }, blot_backend_runtime_ir::SC_bool => { semantic = blot_check_types::boolean; }, blot_backend_runtime_ir::SC_u32 => { semantic = blot_check_types::u32_type; }, blot_backend_runtime_ir::SC_f32 => { semantic = blot_check_types::f32_type; }, _ => { return 0, blot_error::Error.declined; } }
    if (info.scalar == blot_backend_runtime_ir::SC_unit && info.bits != 0) || (info.scalar == blot_backend_runtime_ir::SC_bool && info.bits > 1) || session.constantValueCount() >= session.options.max_values || session.storage.values.len >= 0xffffffff { return 0, blot_error::Error.declined; }
    var value = info; value.start = session.storage.children.len as u32; let id = session.storage.values.len as u32;
    session.storage.values.push(value); session.storage.value_evidence.push(semantic); session.storage.value_records.push(0); return id, blot_error::Error.none;
}

struct WordBuffer { storage: u32[:] = default<u32[:]>(), items: u32[:] = default<u32[:]>() }
reusable[] var scratch_wordbuffer: u32[>..] = [];
fn ensure(self_: WordBuffer&, minimum: i64) -> Error { return blot_support_pooled_buffer::ensure(self_, minimum, scratch_wordbuffer); }
fn push(self_: WordBuffer&, value: u32) -> Error { return blot_support_pooled_buffer::push(self_, value, scratch_wordbuffer); }
fn append(self_: WordBuffer&, values: const u32[:]) -> Error { return blot_support_pooled_buffer::append(self_, values, scratch_wordbuffer); }
fn resize(self_: WordBuffer&, length: i64, initial: u32) -> Error {
    if length < 0 { return blot_error::Error.out_of_memory; } let before = self_.items.len; let error = self_.ensure(length); if error != blot_error::Error.none { return error; }
    for index in before..length { self_.storage[index] = initial; } self_.items = self_.storage[..length]; return blot_error::Error.none;
}
fn resize(self_: WordBuffer&, length: i64) { blot_support_pooled_buffer::resize(self_, length); }
fn clear(self_: WordBuffer&) { blot_support_pooled_buffer::clear(self_); }
fn deinit(self_: WordBuffer&) { blot_support_pooled_buffer::deinit(self_, scratch_wordbuffer); }
fn payloadBytes(self_: const WordBuffer&) -> i64 { return self_.storage.len * 4; }

struct SizeBuffer { storage: i64[:] = default<i64[:]>(), items: i64[:] = default<i64[:]>() }
reusable[] var scratch_sizebuffer: i64[>..] = [];
fn ensure(self_: SizeBuffer&, minimum: i64) -> Error { return blot_support_pooled_buffer::ensure(self_, minimum, scratch_sizebuffer); }
fn push(self_: SizeBuffer&, value: i64) -> Error { return blot_support_pooled_buffer::push(self_, value, scratch_sizebuffer); }
fn append(self_: SizeBuffer&, values: const i64[:]) -> Error { return blot_support_pooled_buffer::append(self_, values, scratch_sizebuffer); }
fn resize(self_: SizeBuffer&, length: i64, initial: i64) -> Error {
    if length < 0 { return blot_error::Error.out_of_memory; } let before = self_.items.len; let error = self_.ensure(length); if error != blot_error::Error.none { return error; }
    for index in before..length { self_.storage[index] = initial; } self_.items = self_.storage[..length]; return blot_error::Error.none;
}
fn resize(self_: SizeBuffer&, length: i64) { blot_support_pooled_buffer::resize(self_, length); }
fn clear(self_: SizeBuffer&) { blot_support_pooled_buffer::clear(self_); }
fn deinit(self_: SizeBuffer&) { blot_support_pooled_buffer::deinit(self_, scratch_sizebuffer); }
fn payloadBytes(self_: const SizeBuffer&) -> i64 { return self_.storage.len * 8; }

struct BitBuffer { storage: bool[:] = default<bool[:]>(), items: bool[:] = default<bool[:]>() }
reusable[] var scratch_bitbuffer: bool[>..] = [];
fn ensure(self_: BitBuffer&, minimum: i64) -> Error { return blot_support_pooled_buffer::ensure(self_, minimum, scratch_bitbuffer); }
fn push(self_: BitBuffer&, value: bool) -> Error { return blot_support_pooled_buffer::push(self_, value, scratch_bitbuffer); }
fn append(self_: BitBuffer&, values: const bool[:]) -> Error { return blot_support_pooled_buffer::append(self_, values, scratch_bitbuffer); }
fn resize(self_: BitBuffer&, length: i64, initial: bool) -> Error {
    if length < 0 { return blot_error::Error.out_of_memory; } let before = self_.items.len; let error = self_.ensure(length); if error != blot_error::Error.none { return error; }
    for index in before..length { self_.storage[index] = initial; } self_.items = self_.storage[..length]; return blot_error::Error.none;
}
fn resize(self_: BitBuffer&, length: i64) { blot_support_pooled_buffer::resize(self_, length); }
fn clear(self_: BitBuffer&) { blot_support_pooled_buffer::clear(self_); }
fn deinit(self_: BitBuffer&) { blot_support_pooled_buffer::deinit(self_, scratch_bitbuffer); }
fn payloadBytes(self_: const BitBuffer&) -> i64 { return self_.storage.len * 1; }

struct MappingBuffer { storage: blot_eval_type_evidence::Mapping[:] = default<blot_eval_type_evidence::Mapping[:]>(), items: blot_eval_type_evidence::Mapping[:] = default<blot_eval_type_evidence::Mapping[:]>() }
reusable[] var scratch_mappingbuffer: blot_eval_type_evidence::Mapping[>..] = [];
fn ensure(self_: MappingBuffer&, minimum: i64) -> Error { return blot_support_pooled_buffer::ensure(self_, minimum, scratch_mappingbuffer); }
fn push(self_: MappingBuffer&, value: blot_eval_type_evidence::Mapping) -> Error { return blot_support_pooled_buffer::push(self_, value, scratch_mappingbuffer); }
fn append(self_: MappingBuffer&, values: const blot_eval_type_evidence::Mapping[:]) -> Error { return blot_support_pooled_buffer::append(self_, values, scratch_mappingbuffer); }
fn resize(self_: MappingBuffer&, length: i64, initial: blot_eval_type_evidence::Mapping) -> Error {
    if length < 0 { return blot_error::Error.out_of_memory; } let before = self_.items.len; let error = self_.ensure(length); if error != blot_error::Error.none { return error; }
    for index in before..length { self_.storage[index] = initial; } self_.items = self_.storage[..length]; return blot_error::Error.none;
}
fn resize(self_: MappingBuffer&, length: i64) { blot_support_pooled_buffer::resize(self_, length); }
fn clear(self_: MappingBuffer&) { blot_support_pooled_buffer::clear(self_); }
fn deinit(self_: MappingBuffer&) { blot_support_pooled_buffer::deinit(self_, scratch_mappingbuffer); }
fn payloadBytes(self_: const MappingBuffer&) -> i64 { return self_.storage.len * 8; }

struct RowBuffer { storage: blot_eval_type_evidence::RowMapping[:] = default<blot_eval_type_evidence::RowMapping[:]>(), items: blot_eval_type_evidence::RowMapping[:] = default<blot_eval_type_evidence::RowMapping[:]>() }
reusable[] var scratch_rowbuffer: blot_eval_type_evidence::RowMapping[>..] = [];
fn ensure(self_: RowBuffer&, minimum: i64) -> Error { return blot_support_pooled_buffer::ensure(self_, minimum, scratch_rowbuffer); }
fn push(self_: RowBuffer&, value: blot_eval_type_evidence::RowMapping) -> Error { return blot_support_pooled_buffer::push(self_, value, scratch_rowbuffer); }
fn append(self_: RowBuffer&, values: const blot_eval_type_evidence::RowMapping[:]) -> Error { return blot_support_pooled_buffer::append(self_, values, scratch_rowbuffer); }
fn resize(self_: RowBuffer&, length: i64, initial: blot_eval_type_evidence::RowMapping) -> Error {
    if length < 0 { return blot_error::Error.out_of_memory; } let before = self_.items.len; let error = self_.ensure(length); if error != blot_error::Error.none { return error; }
    for index in before..length { self_.storage[index] = initial; } self_.items = self_.storage[..length]; return blot_error::Error.none;
}
fn resize(self_: RowBuffer&, length: i64) { blot_support_pooled_buffer::resize(self_, length); }
fn clear(self_: RowBuffer&) { blot_support_pooled_buffer::clear(self_); }
fn deinit(self_: RowBuffer&) { blot_support_pooled_buffer::deinit(self_, scratch_rowbuffer); }
fn payloadBytes(self_: const RowBuffer&) -> i64 { return self_.storage.len * 8; }
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
fn deinit(self_: QueryScratch&) { self_.anchors.deinit(); self_.anchor_ids.deinit(); self_.positions.deinit(); self_.candidate.deinit(); self_.inverse.deinit(); self_.inverse_ids.deinit(); self_.semantic.deinit(); self_.types.deinit(); self_.rows.deinit(); self_.children.deinit(); self_.child_ids.deinit(); self_.append_children.deinit(); self_.owner = 0; self_.generator = 0; self_.session = 0; self_.pools .= null; self_.gate .= null; self_.policy = blot_support::none<RowPolicy>(); }
fn payloadBytes(self_: const QueryScratch&) -> i64 { return self_.anchors.payloadBytes() + self_.anchor_ids.payloadBytes() + self_.positions.payloadBytes() + self_.candidate.payloadBytes() + self_.inverse.payloadBytes() + self_.inverse_ids.payloadBytes() + self_.semantic.payloadBytes() + self_.types.payloadBytes() + self_.rows.payloadBytes() + self_.children.payloadBytes() + self_.child_ids.payloadBytes() + self_.append_children.payloadBytes(); }
struct Plan {
    pools: const Pools? = null, gate: const Gate? = null, root: u32 = 0,
    order: const u32[:] = default<const u32[:]>(), stats: Stats = Stats {..}, row_policy: RowPolicy = RowPolicy.empty_only,
}
reusable[] var plan_order: u32[>..] = [];
fn deinit(self_: Plan&) { if self_.order.len != 0 { plan_order.free_slice(self_.order); } self_ = Plan {..}; }
fn bind<G>(self_: QueryScratch&, plan: Plan, g: G&) -> Error {
    if !plan.gate || !plan.pools || self_.allocation_owner == 0 || self_.allocation_owner != g.evaluator.allocation_owner || !blot_reuse_catalog_storage::same(g.evaluator.units, requiredGate(plan.gate).units) { return blot_error::Error.declined; }
    if self_.owner != 0 { if self_.owner != self_.owner_id || self_.generator != g.owner_id || self_.session != g.evaluator.owner_id || self_.pools .!= plan.pools || self_.gate .!= plan.gate || !self_.policy.present || self_.policy.value != plan.row_policy { return blot_error::Error.declined; } }
    else { if self_.owner_id == 0 || g.owner_id == 0 || g.evaluator.owner_id == 0 { return blot_error::Error.declined; } self_.owner = self_.owner_id; self_.generator = g.owner_id; self_.session = g.evaluator.owner_id; self_.pools .= plan.pools; self_.gate .= plan.gate; self_.policy = blot_support::some(plan.row_policy); }
    return blot_error::Error.none;
}
fn grow<B,T>(self_: QueryScratch&, buffer: B&, length: i64, initial: T) -> Error { let before = buffer.items.len; let error = buffer.resize(length, initial); if error != blot_error::Error.none { return error; } if length > before { self_.stats.initialized_slots += length - before; } return blot_error::Error.none; }
fn begin<G>(self_: QueryScratch&, plan: Plan, g: G&) -> u32[:], Error {
    let bound = self_.bind(plan, g); if bound != blot_error::Error.none { return default<u32[:]>(), bound; }
    for id in self_.anchor_ids.items { self_.anchors.items[id] = 0; } self_.stats.anchor_resets += self_.anchor_ids.items.len; self_.anchor_ids.clear();
    let error = self_.grow(self_.anchors, requiredPools(plan.pools).evaluator.values.len, 0 as u32); if error != blot_error::Error.none { return default<u32[:]>(), error; } if self_.anchors.items.len==0 { return default<u32[:]>(),blot_error::Error.none; } let storage=scratch_wordbuffer.realloc_slice(self_.anchors.storage,self_.anchors.storage.len); return storage[..self_.anchors.items.len], blot_error::Error.none;
}
fn finishMatch(self_: QueryScratch&, order: const u32[:]) { for id in order { self_.positions.items[id] = 0x7fffffffffffffff; self_.candidate.items[id] = 0; } for id in self_.inverse_ids.items { self_.inverse.items[id] = 0; } self_.stats.inverse_positions += self_.inverse_ids.items.len; self_.inverse_ids.clear(); }
fn finishChildren(self_: QueryScratch&, order: const u32[:]) { for id in self_.child_ids.items { self_.children.items[id] = 0xffffffff; } self_.stats.child_positions += self_.child_ids.items.len; self_.child_ids.clear(); for id in order { self_.append_children.items[id] = false; } }
struct Inspection { reason: Reason, stats: Stats, plan: blot_support::Option<Plan> }
struct VisitStates { pages: blot_support_pooled_map::Map<u32,u8[256]> = blot_support_pooled_map::Map<u32,u8[256]> {..} }
reusable[] var visit_pages: dictionary_slot<u32,u8[256]>[>..] = [];
fn deinit(self_: VisitStates&) { blot_support_pooled_map::deinit(self_.pages, visit_pages); }
fn get(self_: const VisitStates&, id: u32) -> u8 { let page .= blot_support_pooled_map::get(self_.pages, id / 256); if !page { return 0; } return page[id % 256]; }
fn put(self_: VisitStates&, id: u32, state: u8) -> Error {
    if !blot_support_pooled_map::contains(self_.pages, id / 256) { blot_support_pooled_map::insert(self_.pages, id / 256, [0; 256], visit_pages); }
    let page .= blot_support_pooled_map::get(self_.pages, id / 256); assert(page); page[id % 256] = state; return blot_error::Error.none;
}
fn finish(self_: VisitStates&, id: u32, state: u8) { let page .= blot_support_pooled_map::get(self_.pages, id / 256); assert(page); page[id % 256] = state; }
fn payloadBytes(self_: const VisitStates&) -> i64 { return self_.pages.slots.len * 260; }
struct Checker {
    pools: const Pools&, gate: const Gate&, seen: VisitStates = VisitStates {..}, semantic: VisitStates = VisitStates {..},
    order: WordBuffer = WordBuffer {..}, stats: Stats = Stats {..}, reason: Reason = Reason.none,
    row_policy: RowPolicy = RowPolicy.empty_only, source_reads_owned: bool = false,
}
fn deinit(self_: Checker&) { self_.seen.deinit(); self_.semantic.deinit(); self_.order.deinit(); }
fn reject(self_: Checker&, reason: Reason) { if self_.reason == Reason.none { self_.reason = reason; } }
fn sourceOwner(self_: const Checker&, unit: u32) -> bool { return unit != 0 && unit <= self_.pools.modules.len && unit <= self_.gate.structural_units.len && self_.gate.structural_units[unit - 1]; }
fn nominal(self_: const Checker&, unit: u32, decl: u32) -> bool {
    if !self_.gate.admitsCatalog(self_.pools, unit) || decl == 0 { return false; }
    for item in self_.pools.modules[unit - 1].module.nominals { if item.identity.decl == decl && (item.identity.unit == 0 || item.identity.unit == unit) { return true; } } return false;
}
fn sourceArrows(module: const Module&, source: u32, applied: u32) -> bool {
    var current = source;
    for index in 0..applied as i64 + 1 {
        if current == 0 || current >= module.types.nodes.len { return false; } var node = module.types.nodes[current];
        if node.tag == blot_check_types::Tag.forall { current = node.a; if current == 0 || current >= module.types.nodes.len { return false; } node = module.types.nodes[current]; }
        if node.tag != blot_check_types::Tag.function { return false; } if index < applied { current = node.b; }
    } return true;
}
fn nominalShape(self_: const Checker&, info: ValueInfo) -> bool {
    let unit = (info.nominal >> 32) as u32; let decl = info.nominal as! u32; let module .= self_.pools.modules[unit - 1].module;
    for constructor in module.constructors { if constructor.nominal >= module.nominals.len { return false; } let family = module.nominals[constructor.nominal].identity;
        if family.decl == decl && (family.unit == 0 || family.unit == unit) && constructor.tag == info.bits { var arity: u32 = 0; if constructor.payload != 0 { arity = 1; } return info.len == arity; }
    } return false;
}
recursive fn rowOwned(self_: Checker&, id: u32, depth: i64, quantified: bool) -> bool, Error {
    if self_.row_policy == RowPolicy.empty_only { return id == 0, blot_error::Error.none; }
    let effects = self_.pools.evaluator.evidence.effects.view(); if depth >= 128 || id >= effects.rows.len { return false, blot_error::Error.none; } let span = effects.rows[id];
    if span.formal != 0 { if !quantified { return false, blot_error::Error.none; } let valid, error = self_.tyOwned(span.formal, depth + 1, true); if error != blot_error::Error.none || !valid { return false, error; } }
    if !range(span.start, span.len, effects.labels.len) || (id == 0 && span.len != 0) { return false, blot_error::Error.none; }
    for label in effects.labels[span.start..span.start + span.len] {
        if label == 0 || label >= effects.operations.len { return false, blot_error::Error.none; } let operation = effects.operations[label]; if operation.instance.unit != 0 || operation.instance.decl != 0 { return false, blot_error::Error.none; }
        let args = operation.arguments; if !range(args.start, args.len, effects.arguments.len) { return false, blot_error::Error.none; }
        if operation.identity.unit == 0 { if operation.identity.decl != 1 || args.len != 0 { return false, blot_error::Error.none; } }
        else {
            if !self_.gate.admitsCatalog(self_.pools, operation.identity.unit) || operation.identity.decl == 0 { return false, blot_error::Error.none; }
            let module .= self_.pools.modules[operation.identity.unit - 1].module; var declared = false;
            for item in module.types.operations { if item.identity == operation.identity { declared = true; break; } }
            if !declared { for item in module.operation_values { if item.identity == operation.identity { declared = true; break; } } }
            if !declared { return false, blot_error::Error.none; }
        }
        for argument in effects.arguments[args.start..args.start + args.len] { let valid, error = self_.tyOwned(argument, depth + 1, quantified); if error != blot_error::Error.none || !valid { return false, error; } }
    } return true, blot_error::Error.none;
}
fn row(self_: Checker&, id: u32, depth: i64) -> bool, Error { return self_.rowOwned(id, depth, false); }
fn ty(self_: Checker&, id: u32, depth: i64) -> bool, Error { return self_.tyOwned(id, depth, false); }
recursive fn tyOwned(self_: Checker&, id: u32, depth: i64, quantified: bool) -> bool, Error {
    let view = self_.pools.evaluator.evidence.view(); if id == 0 || id >= view.nodes.len || depth >= 128 { return false, blot_error::Error.none; } let n = view.nodes[id];
    if n.tag == blot_eval_type_evidence::Tag.bound { return quantified, blot_error::Error.none; }
    if !quantified { let state = self_.semantic.get(id); if state == 2 { return true, blot_error::Error.none; } if state == 1 || state == 3 { return false, blot_error::Error.none; } let error = self_.semantic.put(id, 1); if error != blot_error::Error.none { return false, error; } }
    let valid, error = self_.typeShape(view, id, n, depth, quantified); if error != blot_error::Error.none { return false, error; }
    if !quantified { var state: u8 = 3; if valid { state = 2; } self_.semantic.finish(id, state); } return valid, blot_error::Error.none;
}
recursive fn typeShape(self_: Checker&, view: blot_eval_type_evidence::View, id: u32, n: blot_eval_type_evidence::Node, depth: i64, quantified: bool) -> bool, Error {
    match n.tag {
        scoped => { return false, blot_error::Error.none; }, bound => { abort("bound handled before type shape"); },
        forall, existential => {
            if !quantified { var remaining: i64 = 65536; if view.closed(id, 0, remaining) != blot_error::Error.none { return false, blot_error::Error.none; } }
            let valid, error = self_.tyOwned(n.a, depth + 1, true); if error != blot_error::Error.none || !valid { return false, error; }
            for goal in view.quantifierGoals(id) { let ends = [goal.ty, goal.other, goal.result, goal.signature]; for endpoint in ends { if endpoint == 0 { continue; } let admitted, failure = self_.tyOwned(endpoint, depth + 1, true); if failure != blot_error::Error.none || !admitted { return false, failure; } } }
            return true, blot_error::Error.none;
        },
        projection => {
            if !quantified || !self_.gate.admitsCatalog(self_.pools, n.a) { return false, blot_error::Error.none; }
            let module .= self_.pools.modules[n.a - 1].module; var declared = false;
            for contract in module.contracts { if contract.identity.decl == n.b && (contract.identity.unit == 0 || contract.identity.unit == n.a) { declared = true; } }
            for family in module.nominals { if family.identity.decl == n.b && (family.identity.unit == 0 || family.identity.unit == n.a) { declared = true; } }
            if !declared { return false, blot_error::Error.none; }
            for child in view.children(id) { let valid, error = self_.tyOwned(child, depth + 1, true); if error != blot_error::Error.none || !valid { return false, error; } } return true, blot_error::Error.none;
        },
        unit, boolean, unsigned32, floating32, never => { return n.a == 0 && n.b == 0 && n.c == 0, blot_error::Error.none; },
        function => {
            let a, first = self_.tyOwned(n.a, depth + 1, quantified); if first != blot_error::Error.none || !a { return false, first; }
            let b, second = self_.tyOwned(n.b, depth + 1, quantified); if second != blot_error::Error.none || !b { return false, second; }
            return self_.rowOwned(n.c, depth + 1, quantified);
        },
        array, list, cursor => { if n.b != 0 || n.c != 0 { return false, blot_error::Error.none; } return self_.tyOwned(n.a, depth + 1, quantified); },
        product, record => {
            if n.c != 0 { return false, blot_error::Error.none; } var words = n.b as i64; if n.tag == blot_eval_type_evidence::Tag.record { words *= 2; } if !range(n.a, words, view.extra.len) { return false, blot_error::Error.none; }
            for child, index in view.extra[n.a..n.a + words] { if n.tag == blot_eval_type_evidence::Tag.record && index % 2 == 0 { if !self_.pools.identity.present || child == 0 || child >= self_.pools.identity.value.symbols.len { return false, blot_error::Error.none; } }
                else { let valid, error = self_.tyOwned(child, depth + 1, quantified); if error != blot_error::Error.none || !valid { return false, error; } }
            } return true, blot_error::Error.none;
        },
        nominal => {
            if !self_.nominal(n.a, n.b) || n.c >= view.extra.len { return false, blot_error::Error.none; } let count = view.extra[n.c]; if !range(n.c as i64 + 1, count, view.extra.len) { return false, blot_error::Error.none; }
            for child in view.extra[n.c + 1..n.c + 1 + count] { let valid, error = self_.tyOwned(child, depth + 1, quantified); if error != blot_error::Error.none || !valid { return false, error; } } return true, blot_error::Error.none;
        },
        usage, absent, type_constructor, resolver, provider, state_provider, erased_proof => { return false, blot_error::Error.none; },
    }
}
fn scalarEvidenceTag(scalar: u8) -> EvidenceTag { match scalar { blot_backend_runtime_ir::SC_unit => blot_eval_type_evidence::Tag.unit, blot_backend_runtime_ir::SC_bool => blot_eval_type_evidence::Tag.boolean, blot_backend_runtime_ir::SC_u32 => blot_eval_type_evidence::Tag.unsigned32, blot_backend_runtime_ir::SC_f32 => blot_eval_type_evidence::Tag.floating32, _ => blot_eval_type_evidence::Tag.absent } }
fn compatible(info: ValueInfo, shape: blot_eval_type_evidence::Node, snapshot: const blot_eval_eval_values::Snapshot&) -> bool {
    match info.kind {
        scalar => { return shape.tag == scalarEvidenceTag(info.scalar); }, product => { return shape.tag == blot_eval_type_evidence::Tag.product && shape.b == info.len; },
        array => { return shape.tag == blot_eval_type_evidence::Tag.array; }, list => { return shape.tag == blot_eval_type_evidence::Tag.list; }, cursor => { return shape.tag == blot_eval_type_evidence::Tag.cursor && info.len == 1; },
        record => { return shape.tag == blot_eval_type_evidence::Tag.record && shape.b == info.len; }, nominal => { return shape.tag == blot_eval_type_evidence::Tag.nominal && shape.a == (info.nominal >> 32) as u32 && shape.b == info.nominal as! u32; },
        closure => { return shape.tag == blot_eval_type_evidence::Tag.function || ((shape.tag == blot_eval_type_evidence::Tag.forall || shape.tag == blot_eval_type_evidence::Tag.existential) && shape.a < snapshot.evidence.nodes.len && snapshot.evidence.nodes[shape.a].tag == blot_eval_type_evidence::Tag.function); },
        package => { return shape.tag == blot_eval_type_evidence::Tag.existential; }, _ => { return false; },
    }
}
recursive fn value(self_: Checker&, id: u32, depth: i64) -> Error {
    let snapshot .= self_.pools.evaluator; if id == 0 { return blot_error::Error.none; }
    if id >= snapshot.values.len || id >= snapshot.value_evidence.len || id >= snapshot.value_records.len { self_.reject(Reason.bounds); return blot_error::Error.none; }
    if depth >= 128 { self_.reject(Reason.quota); return blot_error::Error.none; } let seen = self_.seen.get(id); if seen == 2 { return blot_error::Error.none; } if seen == 1 { self_.reject(Reason.cycle); return blot_error::Error.none; }
    if self_.stats.values >= 65536 { self_.reject(Reason.quota); return blot_error::Error.none; } let entered = self_.seen.put(id, 1); if entered != blot_error::Error.none { return entered; }
    let info = snapshot.values[id]; self_.stats.values++; self_.stats.kinds[blot_eval_eval_values::valueKindCode(info.kind)]++; let semantic = snapshot.value_evidence[id];
    if semantic == 0 { self_.stats.open_evidence++; match info.kind { array, list, cursor, product, record, nominal, closure, package => { self_.stats.template_holes++; }, _ => { self_.reject(Reason.open_evidence); } } }
    else { let valid, error = self_.ty(semantic, 0); if error != blot_error::Error.none { return error; } if !valid { self_.stats.unsupported_evidence++; self_.reject(Reason.domain); } }
    if semantic != 0 && semantic < snapshot.evidence.nodes.len && !compatible(info, snapshot.evidence.nodes[semantic], snapshot) { self_.reject(Reason.domain); }
    if !range(info.start, info.len, snapshot.children.len) { self_.reject(Reason.bounds); return blot_error::Error.none; } self_.stats.children += info.len;
    match info.kind {
        scalar => { if scalarEvidenceTag(info.scalar) == blot_eval_type_evidence::Tag.absent { self_.reject(Reason.domain); } else if info.len != 0 { self_.reject(Reason.bounds); } },
        array, list, product, record => {},
        package => {
            if info.len == 0 || info.nominal >= snapshot.evidence.nodes.len || info.bits >= snapshot.evidence.nodes.len { self_.reject(Reason.bounds); }
            else { let dictionary = snapshot.evidence.nodes[info.nominal as u32]; let recipe = snapshot.evidence.nodes[info.bits]; var valid = dictionary.tag == blot_eval_type_evidence::Tag.product && recipe.tag == blot_eval_type_evidence::Tag.existential && dictionary.b == recipe.b;
                if valid { let result, error = self_.ty(info.nominal as u32, depth + 1); if error != blot_error::Error.none { return error; } valid = result; }
                if valid { let result, error = self_.ty(info.bits, depth + 1); if error != blot_error::Error.none { return error; } valid = result; } if !valid { self_.reject(Reason.domain); }
            }
        },
        cursor => { if info.len != 1 || snapshot.children[info.start] >= snapshot.values.len { self_.reject(Reason.bounds); } else { let source = snapshot.values[snapshot.children[info.start]]; if (source.kind != blot_eval_eval_values::ValueKind.array && source.kind != blot_eval_eval_values::ValueKind.list) || info.bits > source.len { self_.reject(Reason.bounds); } } },
        nominal => { if !self_.nominal((info.nominal >> 32) as u32, info.nominal as! u32) { self_.reject(Reason.owner); } else if !self_.nominalShape(info) { self_.reject(Reason.bounds); } },
        closure => { let error = self_.closureValue(info, depth); if error != blot_error::Error.none { return error; } },
        _ => { self_.stats.unsupported_kinds[blot_eval_eval_values::valueKindCode(info.kind)]++; self_.reject(Reason.domain); },
    }
    let record = snapshot.value_records[id]; if (info.kind == blot_eval_eval_values::ValueKind.record) != (record != 0) { self_.reject(Reason.bounds); }
    if record != 0 {
        if record >= snapshot.record_layouts.len { self_.reject(Reason.bounds); }
        else { let names = snapshot.record_layouts[record]; if !range(names.start, names.len, snapshot.field_names.len) || names.len != info.len { self_.reject(Reason.bounds); }
            else { self_.stats.fields += names.len; for name in snapshot.field_names[names.start..names.start + names.len] { if name == 0 || !self_.pools.identity.present || name >= self_.pools.identity.value.symbols.len { self_.reject(Reason.bounds); } } }
        }
    }
    for child in snapshot.children[info.start..info.start + info.len] { let error = self_.value(child, depth + 1); if error != blot_error::Error.none { return error; } }
    self_.seen.finish(id, 2); return self_.order.push(id);
}
fn closureValue(self_: Checker&, info: ValueInfo, depth: i64) -> Error {
    let snapshot .= self_.pools.evaluator; self_.stats.closures++; if info.bits >= snapshot.closures.len { self_.reject(Reason.bounds); return blot_error::Error.none; }
    let meta = snapshot.closures[info.bits]; if meta.staged != 0 { self_.reject(Reason.domain); }
    if !self_.sourceOwner(meta.unit) { self_.reject(Reason.owner); return blot_error::Error.none; } let module .= self_.pools.modules[meta.unit - 1].module; self_.stats.origins[blot_eval_eval_values::closureOriginCode(meta.origin)]++;
    match meta.origin {
        named => {
            let target = blot_check_core::BindingRef { meta.unit, meta.identity , ..}; var admitted = self_.gate.admits(target); if self_.source_reads_owned { admitted = self_.gate.admitsLocalSource(target); }
            var generative = false; if admitted { let result, error = generativeNamed(module, meta.identity); if error != blot_error::Error.none { return error; } generative = result; }
            if !admitted || generative { self_.reject(Reason.source); }
            else { let definition .= module.body(meta.identity); if !definition { self_.reject(Reason.source); } else if !definition.is_function || info.len != meta.applied || meta.applied >= definition.parameters.len || !sourceArrows(module, module.binding(meta.identity).ty, meta.applied) { self_.reject(Reason.bounds); } }
        },
        anonymous => {
            if meta.identity >= module.closures.len { self_.reject(Reason.bounds); }
            else {
                let template = module.closures[meta.identity]; let generative, error = generativeClosure(module, meta.identity); if error != blot_error::Error.none { return error; } if generative { self_.reject(Reason.source); }
                if meta.applied != 0 || info.len != template.captures.len { self_.reject(Reason.bounds); }
                if template.qualifier != 0 {
                    if template.qualifier >= module.bindings.len { self_.reject(Reason.bounds); }
                    else { let binding = module.bindings[template.qualifier]; if binding.kind == blot_reuse_principal_interface::Kind.global { let target = blot_check_core::BindingRef { meta.unit, template.qualifier , ..}; var admitted = self_.gate.admits(target); if self_.source_reads_owned { admitted = self_.gate.admitsLocalSource(target); } if !admitted { self_.reject(Reason.source); } }
                        else if binding.kind == blot_reuse_principal_interface::Kind.local { if binding.initializer == 0 || binding.initializer >= module.nodes.len || module.nodes[binding.initializer].tag != blot_check_core::Tag.closure || module.nodes[binding.initializer].a != meta.identity { self_.reject(Reason.source); } }
                        else { self_.reject(Reason.source); }
                    }
                }
            }
        },
        constructor => { if meta.identity >= module.constructors.len { self_.reject(Reason.bounds); } else { let constructor = module.constructors[meta.identity]; if constructor.payload == 0 || meta.applied != 0 || info.len != 0 || !sourceArrows(module, constructor.scheme.root, 0) { self_.reject(Reason.bounds); } } },
        primitive, operation => { self_.reject(Reason.domain); },
    }
    if meta.ty != 0 && meta.ty >= module.types.nodes.len { self_.reject(Reason.bounds); }
    if !range(meta.mappings.start, meta.mappings.len, snapshot.type_mappings.len) || !range(meta.row_mappings.start, meta.row_mappings.len, snapshot.row_mappings.len) { self_.reject(Reason.bounds); return blot_error::Error.none; }
    self_.stats.type_maps += meta.mappings.len; self_.stats.row_maps += meta.row_mappings.len;
    for mapping, index in snapshot.type_mappings[meta.mappings.start..meta.mappings.start + meta.mappings.len] {
        let valid, error = self_.ty(mapping.evidence, 0); if error != blot_error::Error.none { return error; } if !blot_reuse_constant_receipt::sourceMappingKey(module, mapping.variable) || !valid { self_.reject(Reason.bounds); }
        for prior in snapshot.type_mappings[meta.mappings.start..meta.mappings.start + index] { if prior.variable == mapping.variable { self_.reject(Reason.bounds); } }
    }
    for mapping, index in snapshot.row_mappings[meta.row_mappings.start..meta.row_mappings.start + meta.row_mappings.len] {
        let valid, error = self_.row(mapping.evidence, 0); if error != blot_error::Error.none { return error; } if mapping.variable >= module.types.effects.variable_count || !valid { self_.reject(Reason.bounds); }
        for prior in snapshot.row_mappings[meta.row_mappings.start..meta.row_mappings.start + index] { if prior.variable == mapping.variable { self_.reject(Reason.bounds); } }
    } return blot_error::Error.none;
}
fn inspect(pools: const Pools&, gate: const Gate&, target: blot_check_core::BindingRef) -> Inspection, Error {
    if gate.source_pools .!= pools { return Inspection { Reason.owner, Stats {..}, blot_support::none<Plan>() , ..}, blot_error::Error.none; }
    if !gate.admits(target) || target.unit > pools.modules.len || target.unit > pools.binding_offsets.len { return Inspection { Reason.source, Stats {..}, blot_support::none<Plan>() , ..}, blot_error::Error.none; }
    let module .= pools.modules[target.unit - 1].module; let body .= module.body(target.binding); if !body || body.runtime || body.is_function { return Inspection { Reason.source, Stats {..}, blot_support::none<Plan>() , ..}, blot_error::Error.none; }
    let offset = pools.binding_offsets[target.unit - 1]; if target.binding > 0x7fffffffffffffff - offset { return Inspection { Reason.bounds, Stats {..}, blot_support::none<Plan>() , ..}, blot_error::Error.none; }
    let index = offset + target.binding; if index >= pools.slots.len || pools.slots[index].state != 2 { return Inspection { Reason.slot, Stats {..}, blot_support::none<Plan>() , ..}, blot_error::Error.none; }
    let roots = [pools.slots[index].value]; return inspectRoots(pools, gate, roots);
}
fn inspectRoots(pools: const Pools&, gate: const Gate&, roots: const u32[:]) -> Inspection, Error { return inspectRootsWithRows(pools, gate, roots, RowPolicy.empty_only); }
fn inspectRootsWithRows(pools: const Pools&, gate: const Gate&, roots: const u32[:], row_policy: RowPolicy) -> Inspection, Error { return inspectOwnedRoots(pools, gate, roots, row_policy, false); }
fn inspectConstantRoots(pools: const Pools&, gate: const Gate&, roots: const u32[:]) -> Inspection, Error { return inspectOwnedRoots(pools, gate, roots, RowPolicy.source_declared, true); }
fn inspectOwnedRoots(pools: const Pools&, gate: const Gate&, roots: const u32[:], row_policy: RowPolicy, source_reads_owned: bool) -> Inspection, Error {
    if roots.len == 0 || gate.source_pools .!= pools || !gate.enabled { return Inspection { Reason.owner, Stats {..}, blot_support::none<Plan>() , ..}, blot_error::Error.none; }
    let snapshot .= pools.evaluator;
    if snapshot.values.len == 0 || snapshot.value_evidence.len == 0 || snapshot.value_records.len == 0 || snapshot.values[0].kind != blot_eval_eval_values::ValueKind.scalar || snapshot.values[0].scalar != blot_backend_runtime_ir::SC_unit || snapshot.values[0].len != 0 || snapshot.value_evidence[0] != 1 || snapshot.value_records[0] != 0 || snapshot.evidence.nodes.len <= 1 || snapshot.evidence.nodes[1] != (blot_eval_type_evidence::Node { blot_eval_type_evidence::Tag.unit , ..}) { return Inspection { Reason.bounds, Stats {..}, blot_support::none<Plan>() , ..}, blot_error::Error.none; }
    var checker = Checker { pools: pools, gate: gate, row_policy: row_policy, source_reads_owned: source_reads_owned , ..}; var failure = blot_error::Error.none;
    for root in roots { let error = checker.value(root, 0); if error != blot_error::Error.none { failure = error; break; } }
    checker.stats.inspection_index_bytes = checker.seen.payloadBytes() + checker.semantic.payloadBytes(); let stats = checker.stats; let reason = checker.reason;
    var plan = blot_support::none<Plan>();
    if failure == blot_error::Error.none && reason == Reason.none { let order = plan_order.alloc_slice(checker.order.items.len); for value, index in checker.order.items { order[index] = value; } plan = blot_support::some(Plan { pools, gate, roots[0], order, stats, row_policy , ..}); }
    checker.deinit(); return Inspection { reason, stats, plan , ..}, failure;
}
fn paired<G>(self_: const Plan&, g: G&, graphs: const blot_reuse_artifact_import::Importer&) -> bool {
    if !self_.gate || !self_.pools || requiredGate(self_.gate).source_pools .!= self_.pools || graphs.old .!= self_.pools || !graphs.enabled || !blot_support::same_slice_identity(g.evaluator.units, requiredGate(self_.gate).units) || graphs.unit_map.len != requiredGate(self_.gate).units.len || !blot_support::same_slice_identity(graphs.units, requiredGate(self_.gate).units) { return false; }
    for unit, index in graphs.unit_map { if unit != index + 1 { return false; } } for symbol, index in graphs.symbol_map { if symbol != index { return false; } } return true;
}
recursive fn matchesAnchor<G>(self_: const Plan&, g: G&, graphs: blot_reuse_artifact_import::Importer&, positions: const i64[:], semantic: const u32[:], mapped: const u32[:], candidate: u32[:], inverse: u32[:], old_id: u32, current: u32, depth: i64, inverse_ids: WordBuffer?) -> bool, Error {
    if old_id == 0 { return current == 0, blot_error::Error.none; }
    if depth >= 128 || old_id >= positions.len || positions[old_id] == 0x7fffffffffffffff || current == 0 || current >= g.evaluator.storage.values.len { return false, blot_error::Error.none; }
    if mapped[old_id] != 0 && mapped[old_id] != current { return false, blot_error::Error.none; } if candidate[old_id] != 0 { return candidate[old_id] == current, blot_error::Error.none; }
    if inverse[current] != 0 && inverse[current] != old_id { return false, blot_error::Error.none; }
    assert(self_.pools); let old .= requiredPools(self_.pools).evaluator; let left = old.values[old_id]; let right = g.evaluator.valueInfo(current);
    if left.kind != right.kind || left.scalar != right.scalar || left.len != right.len || semantic[positions[old_id]] != g.evaluator.valueEvidence(current) { return false, blot_error::Error.none; }
    if left.kind == blot_eval_eval_values::ValueKind.package {
        let dictionary, first = graphs.importClosedEvidence(g, left.nominal as u32); if first != blot_error::Error.none || !dictionary.present { return false, first; }
        let recipe, second = graphs.importClosedEvidence(g, left.bits); if second != blot_error::Error.none || !recipe.present { return false, second; }
        if dictionary.value != right.nominal || recipe.value != right.bits { return false, blot_error::Error.none; }
    } else if left.nominal != right.nominal { return false, blot_error::Error.none; }
    if left.kind == blot_eval_eval_values::ValueKind.closure {
        let meta = old.closures[left.bits]; let actual = g.evaluator.closureInfo(current);
        if meta.unit != actual.unit || meta.identity != actual.identity || meta.applied != actual.applied || meta.origin != actual.origin || meta.ty != actual.ty || meta.mappings.len != actual.mappings.len || meta.row_mappings.len != actual.row_mappings.len { return false, blot_error::Error.none; }
        for seed, index in old.type_mappings[meta.mappings.start..meta.mappings.start + meta.mappings.len] {
            let target = g.evaluator.storage.type_mappings.items[actual.mappings.start + index]; if seed.variable != target.variable { return false, blot_error::Error.none; }
            let imported, error = graphs.importClosedEvidence(g, seed.evidence); if error != blot_error::Error.none || !imported.present { return false, error; } if imported.value != target.evidence { return false, blot_error::Error.none; }
        }
        for seed, index in old.row_mappings[meta.row_mappings.start..meta.row_mappings.start + meta.row_mappings.len] {
            let target = g.evaluator.storage.row_mappings.items[actual.row_mappings.start + index]; if seed.variable != target.variable { return false, blot_error::Error.none; } var row: u32 = 0;
            if seed.evidence != 0 { let imported, error = graphs.importSemanticRow(g, seed.evidence); if error != blot_error::Error.none || !imported.present { return false, error; } row = imported.value; }
            if row != target.evidence { return false, blot_error::Error.none; }
        }
    } else if left.kind != blot_eval_eval_values::ValueKind.package && left.bits != right.bits { return false, blot_error::Error.none; }
    let record = old.value_records[old_id]; let names=selectedRecordNames(old,record);
    if names != g.evaluator.recordFieldNames(current) { return false, blot_error::Error.none; }
    candidate[old_id] = current;
    if inverse[current] == 0 && inverse_ids { let error = inverse_ids.push(current); if error != blot_error::Error.none { return false, error; } } inverse[current] = old_id;
    let current_children = g.evaluator.valueChildren(current);
    for child, index in old.children[left.start..left.start + left.len] { let valid, error = self_.matchesAnchor(g, graphs, positions, semantic, mapped, candidate, inverse, child, current_children[index], depth + 1, inverse_ids); if error != blot_error::Error.none || !valid { return false, error; } }
    return true, blot_error::Error.none;
}
fn matchInto<G>(self_: Plan, g: G&, graphs: blot_reuse_artifact_import::Importer&, old_root: u32, current_root: u32, mapped: u32[:]) -> bool, Error {
    var scratch = QueryScratch { allocation_owner: g.evaluator.allocation_owner , ..}; let roots = [old_root]; let current = [current_root];
    let result, error = self_.matchEngine(g, graphs, roots, current, mapped, scratch, false); scratch.deinit(); return result, error;
}
fn matchIntoWithScratch<G>(self_: Plan, g: G&, graphs: blot_reuse_artifact_import::Importer&, old_root: u32, current_root: u32, mapped: u32[:], scratch: QueryScratch&) -> bool, Error { let roots = [old_root]; let current = [current_root]; return self_.matchRootsIntoWithScratch(g, graphs, roots, current, mapped, scratch); }
fn matchRootsIntoWithScratch<G>(self_: Plan, g: G&, graphs: blot_reuse_artifact_import::Importer&, old_roots: const u32[:], current_roots: const u32[:], mapped: u32[:], scratch: QueryScratch&) -> bool, Error { return self_.matchEngine(g, graphs, old_roots, current_roots, mapped, scratch, true); }
fn matchEngine<G>(self_: Plan, g: G&, graphs: blot_reuse_artifact_import::Importer&, old_roots: const u32[:], current_roots: const u32[:], mapped: u32[:], scratch: QueryScratch&, borrowed_anchors: bool) -> bool, Error {
    if old_roots.len == 0 || old_roots.len != current_roots.len { return false, blot_error::Error.none; }
    let bound = scratch.bind(self_, g); if bound != blot_error::Error.none { return false, bound; }
    if !self_.paired(g, graphs) || mapped.len != requiredPools(self_.pools).evaluator.values.len || (borrowed_anchors && !blot_support::same_slice_identity(mapped, scratch.anchors.items)) { return false, blot_error::Error.declined; }
    let p = scratch.grow(scratch.positions, mapped.len, 0x7fffffffffffffff as i64); if p != blot_error::Error.none { return false, p; }
    let c = scratch.grow(scratch.candidate, mapped.len, 0 as u32); if c != blot_error::Error.none { return false, c; }
    let i = scratch.grow(scratch.inverse, g.evaluator.storage.values.len, 0 as u32); if i != blot_error::Error.none { return false, i; }
    let s = scratch.semantic.resize(self_.order.len, 0 as u32); if s != blot_error::Error.none { return false, s; }
    let inverse_capacity = scratch.inverse_ids.ensure(scratch.anchor_ids.items.len + self_.order.len); if inverse_capacity != blot_error::Error.none { return false, inverse_capacity; }
    let anchor_capacity = scratch.anchor_ids.ensure(self_.order.len); if anchor_capacity != blot_error::Error.none { return false, anchor_capacity; }
    if !borrowed_anchors { scratch.anchor_ids.clear(); for current, old in mapped { if current != 0 { let error = scratch.anchor_ids.push(old as u32); if error != blot_error::Error.none { return false, error; } } } }
    scratch.stats.match_calls++; scratch.stats.plan_positions += self_.order.len; scratch.stats.baseline_match_index_entries += mapped.len * 4 + g.evaluator.storage.values.len;
    for id, index in self_.order { scratch.positions.items[id] = index; }
    let anchors_before = scratch.anchor_ids.items.len;
    let matched, failure = self_.matchPrepared(g, graphs, old_roots, current_roots, mapped, scratch);
    if !matched || failure != blot_error::Error.none { for old in scratch.anchor_ids.items[anchors_before..] { mapped[old] = 0; } scratch.anchor_ids.resize(anchors_before); }
    scratch.finishMatch(self_.order); return matched, failure;
}
fn matchPrepared<G>(self_: const Plan&, g: G&, graphs: blot_reuse_artifact_import::Importer&, old_roots: const u32[:], current_roots: const u32[:], mapped: u32[:], scratch: QueryScratch&) -> bool, Error {
    assert(self_.pools);
    for id, index in self_.order {
        var actual: u32 = 0; if requiredPools(self_.pools).evaluator.value_evidence[id] != 0 { let imported, error = graphs.importClosedEvidence(g, requiredPools(self_.pools).evaluator.value_evidence[id]); if error != blot_error::Error.none || !imported.present { return false, error; } actual = imported.value; } scratch.semantic.items[index] = actual;
    }
    for old in scratch.anchor_ids.items { let current = mapped[old]; if current >= scratch.inverse.items.len { return false, blot_error::Error.none; } if scratch.inverse.items[current] == 0 { let error = scratch.inverse_ids.push(current); if error != blot_error::Error.none { return false, error; } } scratch.inverse.items[current] = old; }
    for old_root, index in old_roots {
        let matched, error = self_.matchesAnchor(g, graphs, scratch.positions.items, scratch.semantic.items, mapped, scratch.candidate.items, scratch.inverse.items, old_root, current_roots[index], 0, scratch.inverse_ids); if error != blot_error::Error.none || !matched { return false, error; }
        for old in self_.order { let current = scratch.candidate.items[old]; if current == 0 { continue; } if mapped[old] == 0 { let failure = scratch.anchor_ids.push(old); if failure != blot_error::Error.none { return false, failure; } } mapped[old] = current; scratch.candidate.items[old] = 0; }
    } return true, blot_error::Error.none;
}

fn transportRequire(value: bool) -> Error {if !value {return blot_error::Error.declined;} return blot_error::Error.none;}
// Materialization converts every graph and reserves outputs before publication.
struct QueryStorage { values_before: i64, values_added: i64, children_added: i64, exact: bool=true, precharged: bool=false, buffers: const blot_eval_eval_collection_growth::BufferEffect[:]=default<const blot_eval_eval_collection_growth::BufferEffect[:]>(), root_buffer: blot_support::Option<blot_eval_eval_collection_growth::Frontier> }
struct Transport { old: blot_eval_eval_collection_growth::Span, start: u32 }
struct Package { dictionary: u32, recipe: u32 }
reusable[] var transport_runs: Transport[>..]=[];
reusable[] var package_slots: dictionary_slot<u32,Package>[>..]=[];
struct Material<G> {
    plan: const Plan&, generator: G&, graphs: blot_reuse_artifact_import::Importer&, scratch: QueryScratch&,
    entry: blot_support::Option<u32>, storage: blot_support::Option<QueryStorage>,
    root_buffer: blot_support::Option<blot_eval_eval_collection_growth::Frontier>, transported: Transport[:]=default<Transport[:]>(),
    packages: blot_support_pooled_map::Map<u32,Package> = blot_support_pooled_map::Map<u32,Package>{..}, count: i64=0, added_children: i64=0, children_prepared: bool=false,
}
fn deinit<G>(self_: Material<G>&) { if self_.transported.len != 0 {transport_runs.free_slice(self_.transported);} self_.transported=default<Transport[:]>(); blot_support_pooled_map::deinit(self_.packages,package_slots); }
fn materialize<G>(self_: const Plan&,g: G&) -> u32,Error { return self_.materializeWithGlobalAnchors(g,blot_support::none<u32>()); }
fn materializeWithGlobalAnchors<G>(self_: const Plan&,g: G&,entry: blot_support::Option<u32>) -> u32,Error { let mapped,error=self_.materializeMapped(g,entry,blot_support::none<const u32[:]>()); if error!=blot_error::Error.none {return 0,error;} let result=mapped[self_.root]; releaseMapped(mapped); return result,blot_error::Error.none; }
fn releaseMapped(mapped: u32[:]) { if mapped.len!=0 {scratch_wordbuffer.free_slice(mapped);} }
fn materializeMapped<G>(self_: const Plan&,g: G&,entry: blot_support::Option<u32>,seeds: blot_support::Option<const u32[:]>) -> u32[:],Error {return self_.materializeImpl(g,entry,seeds,blot_support::none<QueryStorage>(),null,null);}
fn materializeReachableMapped<G>(self_: const Plan&,g: G&,graphs: blot_reuse_artifact_import::Importer&,seeds: const u32[:]) -> u32[:],Error {let storage=QueryStorage{values_before:0,values_added:0x7fffffffffffffff,children_added:0x7fffffffffffffff,exact:false, ..}; return self_.materializeImpl(g,blot_support::none<u32>(),blot_support::some(seeds),blot_support::some(storage),graphs,null);}
fn materializeReceiptMapped<G>(self_: const Plan&,g: G&,seeds: const u32[:],storage: QueryStorage) -> u32[:],Error {return self_.materializeImpl(g,blot_support::none<u32>(),blot_support::some(seeds),blot_support::some(storage),null,null);}
fn materializeReceiptMappedWithImporter<G>(self_: const Plan&,g: G&,graphs: blot_reuse_artifact_import::Importer&,seeds: const u32[:],storage: QueryStorage) -> u32[:],Error {return self_.materializeImpl(g,blot_support::none<u32>(),blot_support::some(seeds),blot_support::some(storage),graphs,null);}
fn materializeReceiptWithScratch<G>(self_: Plan,g: G&,graphs: blot_reuse_artifact_import::Importer&,seeds: const u32[:],storage: QueryStorage,scratch: QueryScratch&) -> u32[:],Error {
    let error=scratch.bind(self_,g); if error!=blot_error::Error.none {return default<u32[:]>(),error;} if !blot_support::same_slice_identity(seeds,scratch.anchors.items) {return default<u32[:]>(),blot_error::Error.declined;}
    return self_.materializeImpl(g,blot_support::none<u32>(),blot_support::some(seeds),blot_support::some(storage),graphs,scratch);
}
fn chooseMaterialImporter(paired:blot_reuse_artifact_import::Importer?,owned:blot_support::Option<blot_reuse_artifact_import::Importer>&)->blot_reuse_artifact_import::Importer? { if paired { return paired; } assert(owned.present); return owned.value; }
fn chooseMaterialScratch(scratch:QueryScratch?,temporary:QueryScratch&)->QueryScratch? { if scratch { return scratch; } return temporary; }
fn materializedRun(storage:u32[:],mapped:u32[:],error:Error)->u32[:] { if error!=blot_error::Error.none||mapped.len==0 {return default<u32[:]>();} assert(storage.len>=mapped.len); assert(storage[0] .== mapped[0]); let run=scratch_wordbuffer.realloc_slice(storage,storage.len); return run[..mapped.len]; }
fn materializeImpl<G>(self_: const Plan&,g: G&,entry: blot_support::Option<u32>,seeds: blot_support::Option<const u32[:]>,storage: blot_support::Option<QueryStorage>,paired: blot_reuse_artifact_import::Importer?,scratch: QueryScratch?) -> u32[:],Error {
    if !self_.gate || !self_.pools || requiredGate(self_.gate).source_pools .!= self_.pools || !requiredGate(self_.gate).enabled || !blot_support::same_slice_identity(g.evaluator.units,requiredGate(self_.gate).units) {return default<u32[:]>(),blot_error::Error.declined;}
    var owned=blot_support::none<blot_reuse_artifact_import::Importer>();
    if !paired {let created,error=blot_reuse_artifact_import::init(g.evaluator.allocation_owner,requiredPools(self_.pools),requiredGate(self_.gate).units,blot_support::some(requiredPools(self_.pools).identity.value.view()),requiredGate(self_.gate).units.len); if error!=blot_error::Error.none {return default<u32[:]>(),error;} owned=blot_support::some(created);}
    let graphs=chooseMaterialImporter(paired,owned); assert(graphs); var temporary=QueryScratch{allocation_owner:g.evaluator.allocation_owner, ..};
    if !scratch {let run=scratch_wordbuffer.alloc_slice(requiredPools(self_.pools).evaluator.values.len); for &word in run {word=0;} temporary.anchors=WordBuffer{run,run, ..};}
    let buffers=chooseMaterialScratch(scratch,temporary); assert(buffers); let mapped,error=self_.materializeOwned(g,graphs,entry,seeds,storage,buffers,scratch!=null);
    let result=materializedRun(buffers.anchors.storage,mapped,error);
    if owned.present {owned.value.deinit();}
    if error==blot_error::Error.none && !scratch {temporary.anchors.storage=default<u32[:]>(); temporary.anchors.items=default<u32[:]>();}
    if !scratch {temporary.deinit();} return result,error;
}
fn materializeOwned<G>(self_: const Plan&,g: G&,graphs: blot_reuse_artifact_import::Importer&,entry: blot_support::Option<u32>,seeds: blot_support::Option<const u32[:]>,storage: blot_support::Option<QueryStorage>,buffers: QueryScratch&,retained_scratch: bool) -> u32[:],Error {
    assert(self_.gate && self_.pools);
    if !graphs.enabled || graphs.old .!= self_.pools || !blot_support::same_slice_identity(graphs.units,requiredGate(self_.gate).units) || graphs.unit_map.len!=requiredGate(self_.gate).units.len || graphs.allocation_owner!=g.evaluator.allocation_owner || (graphs.generator_owner!=0 && graphs.generator_owner!=g.owner_id) {return default<u32[:]>(),blot_error::Error.declined;}
    for mapped_unit,unit in graphs.unit_map {if mapped_unit!=unit+1 {return default<u32[:]>(),blot_error::Error.declined;} graphs.stable[unit]=requiredGate(self_.gate).structural_units[unit];}
    for mapped_symbol,symbol in graphs.symbol_map {if mapped_symbol!=symbol {return default<u32[:]>(),blot_error::Error.declined;}}
    let mapped=buffers.anchors.items; if seeds.present {if seeds.value.len!=mapped.len {return default<u32[:]>(),blot_error::Error.declined;} if !retained_scratch {for value,index in seeds.value {mapped[index]=value;}}}
    var state=Material<G>{self_,g,graphs,buffers,entry,storage, ..}; let error=state.prepareMaterial(retained_scratch);
    if error==blot_error::Error.none {state.publishMaterial(retained_scratch);} if retained_scratch && state.children_prepared {buffers.finishChildren(self_.order);} state.deinit(); if error!=blot_error::Error.none {return default<u32[:]>(),error;} return mapped,blot_error::Error.none;
}
fn prepareMaterial<G>(self_: Material<G>&,retained_scratch: bool) -> Error {
    let plan .= self_.plan; assert(plan.pools); let old .= requiredPools(plan.pools).evaluator; let mapped=self_.scratch.anchors.items;
    if self_.storage.present && self_.storage.value.root_buffer.present {
        let buffer=self_.storage.value.root_buffer.value; let root=old.values[plan.root];
        if mapped[plan.root]!=0 || (root.kind!=blot_eval_eval_values::ValueKind.array && root.kind!=blot_eval_eval_values::ValueKind.list) || root.len==0 || buffer.capacity<root.len || buffer.offset>buffer.capacity-root.len {return blot_error::Error.declined;}
        for id in plan.order {if id!=plan.root && old.values[id].kind!=blot_eval_eval_values::ValueKind.scalar {return blot_error::Error.declined;}} self_.root_buffer=blot_support::some(buffer);
    }
    { let propagated_error = self_.scratch.semantic.resize(plan.order.len,0 as u32); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.scratch.types.resize(plan.stats.type_maps,default<blot_eval_type_evidence::Mapping>()); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.scratch.rows.resize(plan.stats.row_maps,default<blot_eval_type_evidence::RowMapping>()); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.scratch.anchor_ids.ensure(plan.order.len); if propagated_error != blot_error::Error.none { return propagated_error; } }
    var type_index: i64=0; var row_index: i64=0;
    for id,index in plan.order {
        var actual: u32=0; if old.value_evidence[id]!=0 {let value,error=self_.graphs.importClosedEvidence(self_.generator,old.value_evidence[id]); { let propagated_error = error; if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = transportRequire(value.present); if propagated_error != blot_error::Error.none { return propagated_error; } } actual=value.value;} self_.scratch.semantic.items[index]=actual;
        if old.values[id].kind!=blot_eval_eval_values::ValueKind.closure {continue;} let meta=old.closures[old.values[id].bits];
        for mapping in old.type_mappings[meta.mappings.start..meta.mappings.start+meta.mappings.len] {let value,error=self_.graphs.importClosedEvidence(self_.generator,mapping.evidence); { let propagated_error = error; if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = transportRequire(value.present); if propagated_error != blot_error::Error.none { return propagated_error; } } self_.scratch.types.items[type_index]=blot_eval_type_evidence::Mapping{mapping.variable,value.value, ..}; type_index++;}
        for mapping in old.row_mappings[meta.row_mappings.start..meta.row_mappings.start+meta.row_mappings.len] {if mapping.evidence!=0 && plan.row_policy==RowPolicy.empty_only {return blot_error::Error.declined;} var imported: u32=0; if mapping.evidence!=0 {let value,error=self_.graphs.importSemanticRow(self_.generator,mapping.evidence); { let propagated_error = error; if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = transportRequire(value.present); if propagated_error != blot_error::Error.none { return propagated_error; } } imported=value.value;} self_.scratch.rows.items[row_index]=blot_eval_type_evidence::RowMapping{mapping.variable,imported, ..}; row_index++;}
    }
    if self_.entry.present {{ let propagated_error = plan.anchorGlobals(self_.generator,self_.graphs,self_.scratch.semantic.items,mapped,self_.entry.value); if propagated_error != blot_error::Error.none { return propagated_error; } }}
    for id in plan.order {if mapped[id]==0 {self_.count++;}}
    if retained_scratch || self_.storage.present {{ let propagated_error = self_.scratch.grow(self_.scratch.children,old.children.len,0xffffffff as u32); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.scratch.grow(self_.scratch.append_children,old.values.len,false); if propagated_error != blot_error::Error.none { return propagated_error; } }}
    { let propagated_error = self_.scratch.child_ids.ensure(plan.stats.children); if propagated_error != blot_error::Error.none { return propagated_error; } } if retained_scratch {self_.scratch.stats.materializations++; self_.scratch.stats.baseline_material_index_entries+=old.values.len*3+old.children.len;}
    self_.children_prepared=true; let effects=selectedMaterialEffects(self_); self_.transported=transport_runs.alloc_slice(effects.len);
    if self_.storage.present {{ let propagated_error = self_.prepareSpans(self_.storage.value,effects,retained_scratch); if propagated_error != blot_error::Error.none { return propagated_error; } }}
    for id in plan.order {if old.values[id].kind!=blot_eval_eval_values::ValueKind.package || mapped[id]!=0 {continue;} let info=old.values[id]; let dictionary,first=self_.graphs.importClosedEvidence(self_.generator,info.nominal as u32); { let propagated_error = first; if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = transportRequire(dictionary.present); if propagated_error != blot_error::Error.none { return propagated_error; } } let recipe,second=self_.graphs.importClosedEvidence(self_.generator,info.bits); { let propagated_error = second; if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = transportRequire(recipe.present); if propagated_error != blot_error::Error.none { return propagated_error; } } blot_support_pooled_map::insert(self_.packages,id,Package{dictionary.value,recipe.value, ..},package_slots);}
    let session .= self_.generator.evaluator; var child_count=plan.stats.children; if self_.storage.present {child_count=self_.added_children;}
    var values_before=session.constantValueCount(); var children_before=session.constantChildCount();
    if self_.storage.present && self_.storage.value.precharged {if self_.count>session.constant_value_debt || child_count>session.constant_child_debt {return blot_error::Error.declined;} values_before-=self_.count; children_before-=child_count;}
    var value_room=session.options.max_values-values_before; if value_room<0 {value_room=0;} var child_room=session.options.max_children-children_before; if child_room<0 {child_room=0;} if self_.count>value_room || child_count>child_room {return blot_error::Error.declined;}
    var reserve_children=plan.stats.children; if self_.storage.present {reserve_children=self_.added_children;}
    if !room(session.storage.values.len,plan.order.len) || !room(session.storage.children.len,reserve_children) || !room(session.storage.closures.len,plan.stats.closures) || !room(session.storage.type_mappings.len,self_.scratch.types.items.len) || !room(session.storage.row_mappings.len,self_.scratch.rows.items.len) || !room(session.storage.record_layouts.len,plan.order.len) || !room(session.storage.field_names.len,plan.stats.fields) {return blot_error::Error.declined;}
    let reserve_error_0=reserve(session.storage.values,plan.order.len); if reserve_error_0!=blot_error::Error.none { return reserve_error_0; }
    let reserve_error_1=reserve(session.storage.value_evidence,plan.order.len); if reserve_error_1!=blot_error::Error.none { return reserve_error_1; }
    let reserve_error_2=reserve(session.storage.value_records,plan.order.len); if reserve_error_2!=blot_error::Error.none { return reserve_error_2; }
    let reserve_error_3=reserve(session.storage.children,reserve_children); if reserve_error_3!=blot_error::Error.none { return reserve_error_3; }
    let reserve_error_4=reserve(session.storage.closures,plan.stats.closures); if reserve_error_4!=blot_error::Error.none { return reserve_error_4; }
    let reserve_error_5=reserve(session.storage.type_mappings,self_.scratch.types.items.len); if reserve_error_5!=blot_error::Error.none { return reserve_error_5; }
    let reserve_error_6=reserve(session.storage.row_mappings,self_.scratch.rows.items.len); if reserve_error_6!=blot_error::Error.none { return reserve_error_6; }
    let reserve_error_7=reserve(session.storage.record_layouts,plan.order.len); if reserve_error_7!=blot_error::Error.none { return reserve_error_7; }
    let reserve_error_8=reserve(session.storage.field_names,plan.stats.fields); if reserve_error_8!=blot_error::Error.none { return reserve_error_8; }
    let map_error=session.storage.collection_buffers.buffers.reserve(session.storage.collection_buffers.buffers.count+effects.len); if map_error!=blot_error::Error.none {return map_error;}
    return blot_error::Error.none;
}
fn reserve<B>(values:B&,added:i64)->Error {return values.ensure(values.len+added);}
fn prepareSpans<G>(self_: Material<G>&,query: QueryStorage,effects: const blot_eval_eval_collection_growth::BufferEffect[:],retained_scratch: bool) -> Error {
    assert(self_.plan.pools); let plan .= self_.plan; let old .= requiredPools(plan.pools).evaluator; let session .= self_.generator.evaluator; let mapped=self_.scratch.anchors.items; let positions=self_.scratch.children.items; let append_children=self_.scratch.append_children.items;
    if self_.count>query.values_added || (query.exact && self_.count!=query.values_added) {return blot_error::Error.declined;}
    for id in plan.order {
        let info=old.values[id]; if mapped[id]==0 {if id<query.values_before {return blot_error::Error.declined;} continue;}
        if mapped[id]>=session.storage.values.len {return blot_error::Error.declined;} let current=session.valueInfo(mapped[id]); if current.len!=info.len {return blot_error::Error.declined;}
        for &position,index in positions[info.start..info.start+info.len] {let expected=current.start+index as u32; if position!=0xffffffff && position!=expected {return blot_error::Error.declined;} if position==0xffffffff && retained_scratch {{ let propagated_error = self_.scratch.child_ids.push(info.start+index as u32); if propagated_error != blot_error::Error.none { return propagated_error; } }} position=expected;}
    }
    if effects.len!=0 && self_.root_buffer.present {return blot_error::Error.declined;}
    for effect,index in effects {
        if effect.value==0 || effect.value>=old.values.len || mapped[effect.value]!=0 {return blot_error::Error.declined;} var reachable=false; for id in plan.order {if id==effect.value {reachable=true; break;}} if !reachable {return blot_error::Error.declined;}
        let latest=old.values[effect.value]; let frontier=effect.frontier;
        if (latest.kind!=blot_eval_eval_values::ValueKind.array && latest.kind!=blot_eval_eval_values::ValueKind.list) || latest.len==0 || frontier.capacity<latest.len || frontier.offset>frontier.capacity-latest.len || frontier.offset>latest.start {return blot_error::Error.declined;}
        let span=blot_eval_eval_collection_growth::Span{latest.start-frontier.offset,frontier.capacity, ..}; if !range(span.start,span.len,old.children.len) {return blot_error::Error.declined;}
        for prior in self_.transported[..index] {if span.start as i64<prior.old.start as i64+prior.old.len && prior.old.start as i64<span.start as i64+span.len {return blot_error::Error.declined;}}
        if !room(session.storage.children.len,self_.added_children+frontier.capacity) {return blot_error::Error.declined;} let start=(session.storage.children.len+self_.added_children) as u32; self_.transported[index]=Transport{span,start, ..};
        for id in plan.order {
            let info=old.values[id]; if info.len==0 || info.start as i64>=span.start as i64+span.len || span.start as i64>=info.start as i64+info.len {continue;}
            if mapped[id]!=0 || info.start<span.start || info.start as i64+info.len>span.start as i64+span.len {return blot_error::Error.declined;}
            for &position,child_index in positions[info.start..info.start+info.len] {let expected=start+info.start-span.start+child_index as u32; if position!=0xffffffff && position!=expected {return blot_error::Error.declined;} if position==0xffffffff && retained_scratch {{ let propagated_error = self_.scratch.child_ids.push(info.start+child_index as u32); if propagated_error != blot_error::Error.none { return propagated_error; } }} position=expected;}
        }
        self_.added_children+=frontier.capacity;
    }
    for id in plan.order {
        if mapped[id]!=0 {continue;} let info=old.values[id]; if info.len==0 {continue;} let span=positions[info.start..info.start+info.len];
        if span[0]==0xffffffff {
            for position in span {if position!=0xffffffff {return blot_error::Error.declined;}} var capacity=info.len; var offset: u32=0; if id==plan.root && self_.root_buffer.present {capacity=self_.root_buffer.value.capacity; offset=self_.root_buffer.value.offset;}
            if !room(session.storage.children.len,self_.added_children+capacity) {return blot_error::Error.declined;} let start=(session.storage.children.len+self_.added_children+offset) as u32;
            for &position,index in span {if retained_scratch {{ let propagated_error = self_.scratch.child_ids.push(info.start+index as u32); if propagated_error != blot_error::Error.none { return propagated_error; } }} position=start+index as u32;} append_children[id]=true; self_.added_children+=capacity;
        } else {for position,index in span {if position!=span[0]+index {return blot_error::Error.declined;}}}
    }
    if self_.added_children>query.children_added || (query.exact && self_.added_children!=query.children_added) {return blot_error::Error.declined;} return blot_error::Error.none;
}
fn publishMaterial<G>(self_: Material<G>&,retained_scratch: bool) {
    assert(self_.plan.pools); let plan .= self_.plan; let old .= requiredPools(plan.pools).evaluator; let session .= self_.generator.evaluator; let mapped=self_.scratch.anchors.items;
    var child_count=plan.stats.children; if self_.storage.present {child_count=self_.added_children;} if self_.storage.present && self_.storage.value.precharged {session.constant_value_debt-=self_.count; session.constant_child_debt-=child_count;}
    for buffer in self_.transported {assert(buffer.start==session.storage.children.len); session.storage.children.resize(session.storage.children.len+buffer.old.len,0);}
    var type_index: i64=0; var row_index: i64=0;
    for id,index in plan.order {
        if mapped[id]!=0 {if old.values[id].kind==blot_eval_eval_values::ValueKind.closure {let meta=old.closures[old.values[id].bits]; type_index+=meta.mappings.len; row_index+=meta.row_mappings.len;} continue;}
        var info=old.values[id]; let package .= blot_support_pooled_map::get(self_.packages,id); if package {info.nominal=package.dictionary; info.bits=package.recipe;}
        let children=old.children[info.start..info.start+info.len]; if self_.storage.present && info.len!=0 {info.start=self_.scratch.children.items[info.start];} else {info.start=session.storage.children.len as u32;}
        if !self_.storage.present || self_.scratch.append_children.items[id] {
            if id==plan.root && self_.root_buffer.present {let buffer=self_.root_buffer.value; let start=session.storage.children.len; session.storage.children.resize(start+buffer.capacity,0); for child,child_index in children {session.storage.children.items[start+buffer.offset+child_index]=mapped[child];}}
            else {for child in children {session.storage.children.push(mapped[child]);}}
        }
        if self_.storage.present && info.len!=0 && !self_.scratch.append_children.items[id] {
            for buffer in self_.transported {let original=old.values[id]; if original.start>=buffer.old.start && original.start as i64+original.len<=buffer.old.start as i64+buffer.old.len {for child,child_index in children {session.storage.children.items[info.start+child_index]=mapped[child];} break;}}
        }
        if info.kind==blot_eval_eval_values::ValueKind.closure {var meta=old.closures[info.bits]; let length=meta.mappings.len; meta.mappings.start=session.storage.type_mappings.len as u32; session.storage.type_mappings.append(self_.scratch.types.items[type_index..type_index+length]); type_index+=length; let rows=meta.row_mappings.len; meta.row_mappings.start=session.storage.row_mappings.len as u32; session.storage.row_mappings.append(self_.scratch.rows.items[row_index..row_index+rows]); row_index+=rows; info.bits=session.storage.closures.len as u32; session.storage.closures.push(meta);}
        var record: u32=0; if old.value_records[id]!=0 {let fields=old.record_layouts[old.value_records[id]]; record=session.storage.record_layouts.len as u32; session.storage.record_layouts.push(blot_check_core::List{session.storage.field_names.len as u32,fields.len, ..}); session.storage.field_names.append(old.field_names[fields.start..fields.start+fields.len]);}
        if retained_scratch {let error=self_.scratch.anchor_ids.push(id); assert(error==blot_error::Error.none);} mapped[id]=session.storage.values.len as u32; session.storage.values.push(info); session.storage.value_evidence.push(self_.scratch.semantic.items[index]); session.storage.value_records.push(record);
    }
    if self_.storage.present {for effect,index in self_.storage.value.buffers {let latest=session.valueInfo(mapped[effect.value]); let buffer=self_.transported[index]; session.storage.collection_buffers.buffers.insert(blot_eval_eval_collection_growth::Span{latest.start,latest.len, ..},blot_eval_eval_collection_growth::Span{buffer.start,buffer.old.len, ..});}}
}
fn anchorGlobals<G>(self_: const Plan&, g: G&, graphs: blot_reuse_artifact_import::Importer&, semantic: const u32[:], mapped: u32[:], entry: u32) -> Error {
    assert(self_.pools); var positions = SizeBuffer {..}; var candidate = WordBuffer {..}; var inverse = WordBuffer {..};
    var error = positions.resize(requiredPools(self_.pools).evaluator.values.len, 0x7fffffffffffffff as i64);
    if error == blot_error::Error.none { error = candidate.resize(positions.items.len, 0 as u32); }
    if error == blot_error::Error.none { error = inverse.resize(g.evaluator.storage.values.len, 0 as u32); }
    if error == blot_error::Error.none { for id, index in self_.order { positions.items[id] = index; } error = self_.anchorGlobalsPrepared(g, graphs, semantic, mapped, entry, positions.items, candidate.items, inverse.items); }
    positions.deinit(); candidate.deinit(); inverse.deinit(); return error;
}
fn anchorGlobalsPrepared<G>(self_: const Plan&, g: G&, graphs: blot_reuse_artifact_import::Importer&, semantic: const u32[:], mapped: u32[:], entry: u32, positions: const i64[:], candidate: u32[:], inverse: u32[:]) -> Error {
    assert(self_.pools && self_.gate);
    for pin in requiredPools(self_.pools).modules {
        if pin.unit == entry { continue; }
        for body in pin.module.bodies[1..] {
            if body.runtime || !requiredGate(self_.gate).admits(blot_check_core::BindingRef { pin.unit, body.binding , ..}) { continue; }
            let old_slot = requiredPools(self_.pools).slots[requiredPools(self_.pools).binding_offsets[pin.unit - 1] + body.binding];
            if old_slot.state != 2 || old_slot.value == 0 || old_slot.value >= positions.len || positions[old_slot.value] == 0x7fffffffffffffff { continue; }
            let slot = g.evaluator.slots[g.evaluator.binding_offsets[pin.unit - 1] + body.binding]; if slot.state != blot_eval_core_eval::State.complete { return blot_error::Error.declined; }
            for &value in candidate { value = 0; } for &value in inverse { value = 0; }
            for current, old in mapped { if current != 0 { if current >= inverse.len { return blot_error::Error.declined; } inverse[current] = old as u32; } }
            let matched, error = self_.matchesAnchor(g, graphs, positions, semantic, mapped, candidate, inverse, old_slot.value, slot.value, 0, null);
            if error != blot_error::Error.none { return error; } if !matched { return blot_error::Error.declined; }
            for current, old in candidate { if current != 0 { mapped[old] = current; } }
        }
    } return blot_error::Error.none;
}
fn reasonCode(reason: Reason) -> i64 { match reason { none => 0, source => 1, slot => 2, bounds => 3, open_evidence => 4, domain => 5, owner => 6, cycle => 7, quota => 8 } }
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
        var found, error = inspect(pools, gate, target); if error != blot_error::Error.none { return result, error; }
        result.requests++; result.reasons[reasonCode(found.reason)]++;
        if found.plan.present { let plan = found.plan.value; result.admitted++; result.graph_values += plan.stats.values; result.graph_closures += plan.stats.closures; result.root_kinds[blot_eval_eval_values::valueKindCode(pools.evaluator.values[plan.root].kind)]++; found.plan.value.deinit(); }
        if pin.unit > cached_units { if result.fresh_count < result.fresh.len { result.fresh[result.fresh_count] = RootObservation { target, body.span, found.reason, found.stats , ..}; result.fresh_count++; } else { result.fresh_truncated++; } }
    } } return result, blot_error::Error.none;
}

fn selectedRecordNames<S>(old:const S&,record:u32)->const u32[:] {if record!=0 {let fields=old.record_layouts[record];return old.field_names[fields.start..fields.start+fields.len];}return default<const u32[:]>();}
fn selectedMaterialEffects<G>(self_:const Material<G>&)->const blot_eval_eval_collection_growth::BufferEffect[:] {if self_.storage.present {return self_.storage.value.buffers;}return default<const blot_eval_eval_collection_growth::BufferEffect[:]>();}
