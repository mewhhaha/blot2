// Imported IDs are meaningful only in one exact pinned source/destination pair.
namespace blot_reuse_artifact_import;
import std;
import dictionary;
import parse.ast;
import check.core;
import check.types;
import check.check;
import eval.core_eval;
import eval.type_evidence;
import eval.semantic_evidence_import;
import backend.layout;
import backend.runtime_identity;
import backend.runtime_operations;
import backend.optimizer_buffers;
import backend.wasm;
import reuse.code_artifacts;
import reuse.code_body_validity;
import reuse.principal_reuse_gate;
import reuse.source_value_template;
import reuse.declaration_dependencies;
import reuse.declaration_projection;
import reuse.substitution_keys;
import reuse.artifact_import_knowledge;
import reuse.artifact_import_core;
import support.error;
import support.option;
import support.native;
import support.structural;
import support.pooled_map;
import support.pooled_buffer;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Pools = blot_reuse_code_artifacts::Pools;
fn requiredPools(pools:const Pools?)->const Pools& {assert(pools);return pools;}
type View = blot_backend_runtime_identity::View;
type Gate = blot_reuse_principal_reuse_gate::Gate;
type LayoutTag = blot_backend_layout::Tag;
type EvidenceTag = blot_eval_type_evidence::Tag;
let depth_limit: i64 = 128;
enum Domain { layout, semantic }
struct RowKey { domain: Domain, id: u32 }
struct EvidenceKey { id: u32, owner: u32 = 0, mappings: bool = false }
struct SubstitutionKey { id: u32, owner: u32 }
struct ExpressionKey { unit: u32, root: u32 }
enum OperationScope { unchecked, admitted, declined }
fn hash(key: RowKey) -> u64 { var domain: u32 = 0; if key.domain == Domain.semantic { domain = 1; } return ::hash_combine(::hash(key.id), ::hash(domain)); }
fn hash(key: EvidenceKey) -> u64 { return ::hash_combine(::hash_combine(::hash(key.id), ::hash(key.owner)), ::hash(key.mappings)); }
fn hash(key: SubstitutionKey) -> u64 { return ::hash((key.id as u64) << 32 | key.owner); }
fn hash(key: ExpressionKey) -> u64 { return ::hash((key.unit as u64) << 32 | key.root); }
struct Census { static_plan_inspections: i64 = 0, static_plan_hits: i64 = 0, semantic_queries: i64 = 0, semantic_hits: i64 = 0, semantic_nodes: i64 = 0, semantic_child_words: i64 = 0, row_queries: i64 = 0, row_hits: i64 = 0, row_nodes: i64 = 0, row_argument_words: i64 = 0 }
struct OwnerCensus { principals: Census = Census {..}, queries: Census = Census {..}, fragments: Census = Census {..} }
struct Solved { mappings: blot_backend_layout::Mapping[:] = default<blot_backend_layout::Mapping[:]>(), rows: blot_backend_layout::RowMapping[:] = default<blot_backend_layout::RowMapping[:]>(), templates: blot_reuse_substitution_keys::Entry[:] = default<blot_reuse_substitution_keys::Entry[:]>() }
struct IdentityMetadata { bytes: u8[:] = default<u8[:]>(), symbols: blot_backend_runtime_identity::Name[:] = default<blot_backend_runtime_identity::Name[:]>(), owners: blot_backend_runtime_identity::Name[:] = default<blot_backend_runtime_identity::Name[:]>() }
reusable[] var identity_bytes: u8[>..] = [];
reusable[] var identity_names: blot_backend_runtime_identity::Name[>..] = [];
reusable[] var unit_words: u32[>..] = [];
reusable[] var stable_flags: bool[>..] = [];
reusable[] var operation_scope_runs: OperationScope[>..] = [];
fn view(self_: IdentityMetadata) -> View { return View { self_.bytes, self_.symbols, self_.owners , ..}; }
fn copyIdentity(source: View) -> IdentityMetadata {
    let bytes = identity_bytes.alloc_slice(source.bytes.len); let symbols = identity_names.alloc_slice(source.symbols.len); let owners = identity_names.alloc_slice(source.owners.len);
    for byte, index in source.bytes { bytes[index] = byte; } for name, index in source.symbols { symbols[index] = name; } for owner, index in source.owners { owners[index] = owner; }
    return IdentityMetadata { bytes, symbols, owners , ..};
}
fn deinit(self_: IdentityMetadata&) { if self_.bytes.len != 0 { identity_bytes.free_slice(self_.bytes); } if self_.symbols.len != 0 { identity_names.free_slice(self_.symbols); } if self_.owners.len != 0 { identity_names.free_slice(self_.owners); } self_ = IdentityMetadata {..}; }

struct WordMap { table: blot_support_pooled_map::Map<u32,u32> = blot_support_pooled_map::Map<u32,u32> {..} }
reusable[] var wordmap_slots: dictionary_slot<u32,u32>[>..] = [];
fn get(self_: const WordMap&, key: u32) -> u32? { return blot_support_pooled_map::get(self_.table, key); }
fn contains(self_: const WordMap&, key: u32) -> bool { return blot_support_pooled_map::contains(self_.table, key); }
fn insert(self_: WordMap&, key: u32, value: u32) { blot_support_pooled_map::insert(self_.table, key, value, wordmap_slots); }
fn deinit(self_: WordMap&) { blot_support_pooled_map::deinit(self_.table, wordmap_slots); }

struct EvidenceMap { table: blot_support_pooled_map::Map<EvidenceKey,u32> = blot_support_pooled_map::Map<EvidenceKey,u32> {..} }
reusable[] var evidencemap_slots: dictionary_slot<EvidenceKey,u32>[>..] = [];
fn get(self_: const EvidenceMap&, key: EvidenceKey) -> u32? { return blot_support_pooled_map::get(self_.table, key); }
fn contains(self_: const EvidenceMap&, key: EvidenceKey) -> bool { return blot_support_pooled_map::contains(self_.table, key); }
fn insert(self_: EvidenceMap&, key: EvidenceKey, value: u32) { blot_support_pooled_map::insert(self_.table, key, value, evidencemap_slots); }
fn deinit(self_: EvidenceMap&) { blot_support_pooled_map::deinit(self_.table, evidencemap_slots); }

struct RowMap { table: blot_support_pooled_map::Map<RowKey,u32> = blot_support_pooled_map::Map<RowKey,u32> {..} }
reusable[] var rowmap_slots: dictionary_slot<RowKey,u32>[>..] = [];
fn get(self_: const RowMap&, key: RowKey) -> u32? { return blot_support_pooled_map::get(self_.table, key); }
fn contains(self_: const RowMap&, key: RowKey) -> bool { return blot_support_pooled_map::contains(self_.table, key); }
fn insert(self_: RowMap&, key: RowKey, value: u32) { blot_support_pooled_map::insert(self_.table, key, value, rowmap_slots); }
fn deinit(self_: RowMap&) { blot_support_pooled_map::deinit(self_.table, rowmap_slots); }

struct SubstitutionMap { table: blot_support_pooled_map::Map<SubstitutionKey,u32> = blot_support_pooled_map::Map<SubstitutionKey,u32> {..} }
reusable[] var substitutionmap_slots: dictionary_slot<SubstitutionKey,u32>[>..] = [];
fn get(self_: const SubstitutionMap&, key: SubstitutionKey) -> u32? { return blot_support_pooled_map::get(self_.table, key); }
fn contains(self_: const SubstitutionMap&, key: SubstitutionKey) -> bool { return blot_support_pooled_map::contains(self_.table, key); }
fn insert(self_: SubstitutionMap&, key: SubstitutionKey, value: u32) { blot_support_pooled_map::insert(self_.table, key, value, substitutionmap_slots); }
fn deinit(self_: SubstitutionMap&) { blot_support_pooled_map::deinit(self_.table, substitutionmap_slots); }

struct ExpressionMap { table: blot_support_pooled_map::Map<ExpressionKey,const u32[:]> = blot_support_pooled_map::Map<ExpressionKey,const u32[:]> {..} }
reusable[] var expressionmap_slots: dictionary_slot<ExpressionKey,const u32[:]>[>..] = [];
fn get(self_: const ExpressionMap&, key: ExpressionKey) -> const u32[:]? { return blot_support_pooled_map::get(self_.table, key); }
fn contains(self_: const ExpressionMap&, key: ExpressionKey) -> bool { return blot_support_pooled_map::contains(self_.table, key); }
fn insert(self_: ExpressionMap&, key: ExpressionKey, value: const u32[:]) { blot_support_pooled_map::insert(self_.table, key, value, expressionmap_slots); }
fn deinit(self_: ExpressionMap&) { blot_support_pooled_map::deinit(self_.table, expressionmap_slots); }

struct PlanMap { table: blot_support_pooled_map::Map<u32,blot_reuse_source_value_template::Plan> = blot_support_pooled_map::Map<u32,blot_reuse_source_value_template::Plan> {..} }
reusable[] var planmap_slots: dictionary_slot<u32,blot_reuse_source_value_template::Plan>[>..] = [];
fn get(self_: const PlanMap&, key: u32) -> blot_reuse_source_value_template::Plan? { return blot_support_pooled_map::get(self_.table, key); }
fn contains(self_: const PlanMap&, key: u32) -> bool { return blot_support_pooled_map::contains(self_.table, key); }
fn insert(self_: PlanMap&, key: u32, value: blot_reuse_source_value_template::Plan) { blot_support_pooled_map::insert(self_.table, key, value, planmap_slots); }
fn deinit(self_: PlanMap&) { blot_support_pooled_map::deinit(self_.table, planmap_slots); }
struct TextMap { table: blot_support_pooled_map::Map<const u8[:],u32> = blot_support_pooled_map::Map<const u8[:],u32> {..} }
reusable[] var textmap_slots: dictionary_slot<const u8[:],u32>[>..] = [];
fn get(self_: const TextMap&, key: const u8[:]) -> u32? { return blot_support_pooled_map::get(self_.table, key); }
fn contains(self_: const TextMap&, key: const u8[:]) -> bool { return blot_support_pooled_map::contains(self_.table, key); }
reusable[] var textmap_bytes:u8[>..]=[];
fn insert(self_:TextMap&,key:const u8[:],value:u32) {
 if self_.table.slots.len==0 {blot_support_pooled_map::grow(self_.table,8,textmap_slots);}else if (self_.table.count+1)*3>self_.table.slots.len*2 {blot_support_pooled_map::grow(self_.table,self_.table.slots.len*2,textmap_slots);}
 let slots=textmap_slots.realloc_slice(self_.table.slots,self_.table.slots.len);let hash=::hash(key);let tag=(hash as! u32)|2147483648;let mask=slots.len-1;var index=(hash & (mask as u64)) as i64;
 loop {let present=slots[index].tag;if present==0 {let owned=textmap_bytes.alloc_slice(key.len);for byte,at in key {owned[at]=byte;}let copied:const u8[:]=owned;slots[index]=dictionary_slot<const u8[:],u32>{copied,value,tag};self_.table.count++;return;}if present==tag && slots[index].key==key {slots[index].val=value;return;}index=(index+1)&mask;}
}
fn deinit(self_:TextMap&) {for slot in self_.table.slots {if slot.tag!=0 && slot.key.len!=0 {textmap_bytes.free_slice(slot.key);}}blot_support_pooled_map::deinit(self_.table,textmap_slots);}
struct Importer {
    allocation_owner: u64 = 0, census: Census = Census {..}, old: const Pools? = null, units: const Module[:] = default<const Module[:]>(),
    names: blot_support::Option<IdentityMetadata>, unit_map: u32[:] = default<u32[:]>(), symbol_map: u32[:] = default<u32[:]>(), stable: bool[:] = default<bool[:]>(),
    code_gate: blot_support::Option<blot_reuse_code_body_validity::Gate>, semantic_catalogs: bool = false,
    closed_evidence: blot_support::Option<blot_eval_semantic_evidence_import::PooledImporter>, enabled: bool = false, generator_owner: u64 = 0,
    expression_nodes: ExpressionMap = ExpressionMap {..}, layouts: WordMap = WordMap {..}, semantic: EvidenceMap = EvidenceMap {..},
    rows: RowMap = RowMap {..}, template_keys: SubstitutionMap = SubstitutionMap {..}, row_keys: SubstitutionMap = SubstitutionMap {..},
    captures: WordMap = WordMap {..}, value_anchors: WordMap = WordMap {..},
    static_scratch: blot_support::Option<blot_reuse_source_value_template::QueryScratch>, static_plans: PlanMap = PlanMap {..}, static_plan_nodes: i64 = 0,
    operation_labels: u32[:] = default<u32[:]>(), operation_scopes: OperationScope[:] = default<OperationScope[:]>(), operations_indexed: bool = false,
    knowledge: Knowledge = Knowledge {..},
}
fn init(allocation_owner: u64, old: const Pools&, units: const Module[:], names: blot_support::Option<View>, cached_units: i64) -> Importer, Error { return initWithStamps(allocation_owner, old, units, names, cached_units, null); }
fn initWithStamps(allocation_owner: u64, old: const Pools&, units: const Module[:], names: blot_support::Option<View>, cached_units: i64, stamps: blot_reuse_code_artifacts::ModuleStamps?) -> Importer, Error {
    let unit_map = unit_words.alloc_slice(old.modules.len); let stable = stable_flags.alloc_slice(old.modules.len);
    var symbol_count: i64 = 0; if old.identity.present { symbol_count = old.identity.value.symbols.len; } let symbol_map = unit_words.alloc_slice(symbol_count);
    for &word in unit_map { word = 0; } for &flag in stable { flag = false; } for &word in symbol_map { word = 0; }
    var result = Importer { allocation_owner: allocation_owner, old: old, units: units, unit_map: unit_map, symbol_map: symbol_map, stable: stable , ..};
    let error = result.initialize(old, units, names, cached_units, stamps); if error != blot_error::Error.none { result.deinit(); return Importer {..}, error; } return result, blot_error::Error.none;
}
fn initialize(self_: Importer&, old: const Pools&, units: const Module[:], names: blot_support::Option<View>, cached_units: i64, stamps: blot_reuse_code_artifacts::ModuleStamps?) -> Error {
    var producers = TextMap {..}; var spellings = TextMap {..};
    let error = self_.initializeMaps(old, units, names, cached_units, stamps, producers, spellings);
    producers.deinit(); spellings.deinit(); return error;
}
fn initializeMaps(self_: Importer&, old: const Pools&, units: const Module[:], names: blot_support::Option<View>, cached_units: i64, stamps: blot_reuse_code_artifacts::ModuleStamps?, producers: TextMap&, spellings: TextMap&) -> Error {
    if !old.project_identity || !names.present || !old.identity.present || cached_units > self_.units.len { return blot_error::Error.none; }
    self_.names = blot_support::some(copyIdentity(names.value)); let current = self_.names.value.view(); let old_names = old.identity.value.view();
    if current.owners.len != self_.units.len || old_names.owners.len != old.modules.len || current.symbols.len == 0 || old_names.symbols.len == 0 { return blot_error::Error.none; }
    for module, index in self_.units {
        if module.unit != 0 && module.unit != index + 1 { return blot_error::Error.none; } let path = current.owner((index + 1) as u32);
        if !path.present || path.value.len == 0 || !blot_backend_runtime_identity::validUtf8(path.value) { return blot_error::Error.none; }
        for byte in path.value { if byte == 0 { return blot_error::Error.none; } } if producers.contains(path.value) { return blot_error::Error.none; } producers.insert(path.value, (index + 1) as u32);
    }
    for index in 1..current.symbols.len { let spelling = current.symbol(index as u32); if !spelling.present || spelling.value.len == 0 || !blot_backend_runtime_identity::validUtf8(spelling.value) || spellings.contains(spelling.value) { return blot_error::Error.none; } spellings.insert(spelling.value, index as u32); }
    for pin, index in old.modules {
        if pin.unit != index + 1 || pin.canonical_path.len == 0 || (pin.module.unit != 0 && pin.module.unit != pin.unit) { return blot_error::Error.none; }
        let path = old_names.owner(pin.unit); if !path.present || path.value != pin.canonical_path { return blot_error::Error.none; } for previous in old.modules[..index] { if previous.canonical_path == path.value { return blot_error::Error.none; } }
        let mapped = producers.get(path.value); if mapped { self_.unit_map[index] = mapped; }
    }
    for index in 1..self_.symbol_map.len { let spelling = old_names.symbol(index as u32); if !spelling.present || spelling.value.len == 0 { return blot_error::Error.none; } let mapped = spellings.get(spelling.value); if mapped { self_.symbol_map[index] = mapped; } }
    self_.enabled = true;
    for &pin, index in old.modules {
        let mapped = self_.unit_map[index]; if mapped == 0 || mapped > cached_units { continue; }
        let intact, error = blot_reuse_code_artifacts::pinIntact(pin, stamps); if error != blot_error::Error.none { return error; } if !intact { continue; }
        let equal, failure = self_.coreEqual(pin.module, self_.units[mapped - 1]); if failure == blot_error::Error.out_of_memory { return failure; } self_.stable[index] = failure == blot_error::Error.none && equal;
    }
    let gate, error = blot_reuse_code_body_validity::init(self_.allocation_owner, old, units, names, stamps); if error != blot_error::Error.none { return error; } self_.code_gate = blot_support::some(gate); return blot_error::Error.none;
}
fn initCheckedQuery(allocation_owner: u64, old: const Pools&, units: const Module[:], checked: const Gate&) -> blot_support::Option<Importer>, Error {
    if allocation_owner == 0 || checked.allocation_owner != allocation_owner { return blot_support::none<Importer>(), blot_error::Error.none; } return initIndependentQuery(allocation_owner, old, units, checked);
}
fn initIndependentQuery(allocation_owner: u64, old: const Pools&, units: const Module[:], checked: const Gate&) -> blot_support::Option<Importer>, Error {
    let no = blot_support::none<Importer>();
    if !checked.enabled || checked.source_pools .!= old || !blot_support::same_slice_identity(checked.units, units) || old.modules.len != units.len || checked.structural_units.len != units.len || !old.project_identity || !old.identity.present { return no, blot_error::Error.none; }
    let names = old.identity.value.view(); if names.owners.len != units.len || names.symbols.len == 0 || names.symbols.len > 0xffffffff || units.len >= 0xffffffff { return no, blot_error::Error.none; }
    let unit_map = unit_words.alloc_slice(units.len); for &word, index in unit_map { word = (index + 1) as u32; }
    let symbol_map = unit_words.alloc_slice(names.symbols.len); for &word, index in symbol_map { word = index as u32; }
    let stable = stable_flags.alloc_slice(units.len); for &flag, index in stable { flag = checked.structural_units[index]; }
    return blot_support::some(Importer { allocation_owner: allocation_owner, old: old, units: units, names: blot_support::some(copyIdentity(names)), unit_map: unit_map, symbol_map: symbol_map, stable: stable, semantic_catalogs: true, enabled: true , ..}), blot_error::Error.none;
}
fn deinit(self_: Importer&) {
    if self_.closed_evidence.present { self_.closed_evidence.value.deinit(); self_.closed_evidence.present = false; }
    for slot in self_.expression_nodes.table.slots { if slot.tag != 0 { blot_reuse_declaration_projection::release(slot.val); } } self_.expression_nodes.deinit();
    self_.layouts.deinit(); self_.semantic.deinit(); self_.rows.deinit(); self_.template_keys.deinit(); self_.row_keys.deinit(); self_.captures.deinit(); self_.value_anchors.deinit();
    for &slot in self_.static_plans.table.slots { if slot.tag != 0 { slot.val.deinit(); } } self_.static_plans.deinit();
    if self_.static_scratch.present { self_.static_scratch.value.deinit(); self_.static_scratch.present = false; } self_.knowledge.deinit();
    if self_.operation_labels.len != 0 { unit_words.free_slice(self_.operation_labels); } if self_.operation_scopes.len != 0 { operation_scope_runs.free_slice(self_.operation_scopes); }
    if self_.names.present { self_.names.value.deinit(); self_.names.present = false; }
    if self_.unit_map.len != 0 { unit_words.free_slice(self_.unit_map); } if self_.symbol_map.len != 0 { unit_words.free_slice(self_.symbol_map); }
    if self_.code_gate.present { self_.code_gate.value.deinit(); self_.code_gate.present = false; } if self_.stable.len != 0 { stable_flags.free_slice(self_.stable); }
    self_ = Importer {..};
}
fn bind<G>(self_: Importer&, generator: G&) -> Error {
    if !self_.enabled || generator.owner_id == 0 { return blot_error::Error.declined; }
    if self_.generator_owner != 0 { if self_.generator_owner != generator.owner_id { return blot_error::Error.declined; } }
    else { let error = self_.checkFields(generator); if error != blot_error::Error.none { return error; } self_.generator_owner = generator.owner_id; } return blot_error::Error.none;
}
fn unit(self_: const Importer&, old_unit: u32, require_stable: bool) -> u32, Error { if old_unit == 0 || old_unit > self_.unit_map.len { return 0, blot_error::Error.declined; } let mapped = self_.unit_map[old_unit - 1]; if mapped == 0 || (require_stable && !self_.stable[old_unit - 1]) { return 0, blot_error::Error.declined; } return mapped, blot_error::Error.none; }
fn symbol(self_: const Importer&, old_symbol: u32) -> u32, Error { if old_symbol == 0 || old_symbol >= self_.symbol_map.len || self_.symbol_map[old_symbol] == 0 { return 0, blot_error::Error.declined; } return self_.symbol_map[old_symbol], blot_error::Error.none; }
fn nominalDeclaration(self_: const Importer&, decl: u32) -> u32, Error { if decl & blot_check_types::opaque_name_bit != 0 { let value, error = self_.symbol(decl & ~blot_check_types::opaque_name_bit); return value | blot_check_types::opaque_name_bit, error; } return decl, blot_error::Error.none; }
fn admitsBody(self_: const Importer&, value: blot_check_core::BindingRef) -> bool { if value.unit == 0 || value.unit > self_.unit_map.len { return false; } if self_.stable[value.unit - 1] { return true; } if !self_.code_gate.present { return false; } return self_.code_gate.value.body(blot_check_core::BindingRef { self_.unit_map[value.unit - 1], value.binding , ..}); }
fn typeUnit(self_: const Importer&, source: u32) -> u32, Error { let exact_catalog = self_.code_gate.present && self_.code_gate.value.catalog(source); return self_.unit(source, !exact_catalog); }
fn nominal(self_: const Importer&, old_unit: u32, decl: u32) -> u32, Error { return self_.nominalInDomain(old_unit, decl, true); }
fn semanticNominal(self_: const Importer&, old_unit: u32, decl: u32) -> u32, Error { return self_.nominalInDomain(old_unit, decl, !self_.semantic_catalogs); }
fn nominalInDomain(self_: const Importer&, old_unit: u32, decl: u32, require_stable: bool) -> u32, Error {
    if decl == 0 { return 0, blot_error::Error.declined; } if old_unit == 0xffffffff { if decl > 6 { return 0, blot_error::Error.declined; } return old_unit, blot_error::Error.none; }
    var mapped: u32 = 0; var failure = blot_error::Error.none;
    if require_stable { let value, error = self_.typeUnit(old_unit); mapped = value; failure = error; } else { let value, error = self_.unit(old_unit, false); mapped = value; failure = error; }
    if failure != blot_error::Error.none { return 0, failure; } let module = self_.units[mapped - 1]; let declaration, error = self_.nominalDeclaration(decl); if error != blot_error::Error.none { return 0, error; }
    for value in module.nominals { if value.identity.decl == declaration && (value.identity.unit == 0 || value.identity.unit == mapped) { return mapped, blot_error::Error.none; } }
    for value in module.types.operations { if value.identity.decl == decl && value.identity.unit == mapped { return mapped, blot_error::Error.none; } } for value in module.operation_values { if value.identity.decl == decl && value.identity.unit == mapped { return mapped, blot_error::Error.none; } } return 0, blot_error::Error.declined;
}

// Bounded transport never treats a numeric old ID as current-owner authority.
fn convert(error: Error) -> Error {
    if error == blot_error::Error.none || error == blot_error::Error.out_of_memory { return error; }
    return blot_error::Error.declined;
}
fn bounded<T>(values: const T[:], start: u32, len: u32) -> const T[:], Error {
    if start > values.len || len > values.len - start { return default<const T[:]>(), blot_error::Error.declined; }
    return values[start..start + len], blot_error::Error.none;
}
fn uniqueFields(fields: const u32[:]) -> Error {
    if fields.len % 2 != 0 { return blot_error::Error.declined; }
    for index in 0..fields.len / 2 {
        let name = fields[index * 2];
        if name == 0 { return blot_error::Error.declined; }
        for previous in 0..index { if fields[previous * 2] == name { return blot_error::Error.declined; } }
    }
    return blot_error::Error.none;
}
fn shapeChildren(source: const blot_reuse_code_artifacts::Layouts&, id: u32) -> const u32[:], Error {
    let node = source.nodes[id];
    if node.tag == blot_backend_layout::Tag.product { return bounded(source.extra, node.a, node.b); }
    if node.tag == blot_backend_layout::Tag.record {
        if node.b > 0x7fffffff { return default<const u32[:]>(), blot_error::Error.declined; }
        return bounded(source.extra, node.a, node.b * 2);
    }
    if node.tag == blot_backend_layout::Tag.nominal {
        if node.c >= source.extra.len { return default<const u32[:]>(), blot_error::Error.declined; }
        return bounded(source.extra, node.c + 1, source.extra[node.c]);
    }
    return default<const u32[:]>(), blot_error::Error.declined;
}
fn evidenceChildren(source: blot_eval_type_evidence::View, id: u32) -> const u32[:], Error {
    let node = source.nodes[id];
    if node.tag == blot_eval_type_evidence::Tag.product { return bounded(source.extra, node.a, node.b); }
    if node.tag == blot_eval_type_evidence::Tag.record {
        if node.b > 0x7fffffff { return default<const u32[:]>(), blot_error::Error.declined; }
        return bounded(source.extra, node.a, node.b * 2);
    }
    if node.tag == blot_eval_type_evidence::Tag.nominal {
        if node.c >= source.extra.len { return default<const u32[:]>(), blot_error::Error.declined; }
        return bounded(source.extra, node.c + 1, source.extra[node.c]);
    }
    return default<const u32[:]>(), blot_error::Error.declined;
}
fn oldModule(self_: const Importer&, owner: u32) -> const Module?, Error {
    let mapped, error = self_.typeUnit(owner);
    if error != blot_error::Error.none { return null, error; }
    let __old:const Pools& =requiredPools(self_.old); return __old.modules[owner - 1].module, blot_error::Error.none;
}
recursive fn shape<G>(self_: Importer&, g: G&, id: u32, depth: i64) -> u32, Error {
    let __old:const Pools& =requiredPools(self_.old);
    if depth >= depth_limit || id == 0 || id >= __old.layouts.nodes.len { return 0, blot_error::Error.declined; }
    let known = self_.layouts.get(id); if known { return known, blot_error::Error.none; }
    var values = blot_reuse_source_value_template::WordBuffer {..};
    let result, error = self_.shapeInto(g, id, depth, values);
    values.deinit(); return result, error;
}
recursive fn shapeInto<G>(self_: Importer&, g: G&, id: u32, depth: i64, values: blot_reuse_source_value_template::WordBuffer&) -> u32, Error {
    let __old:const Pools& =requiredPools(self_.old);
    let n = __old.layouts.nodes[id];
    var a = n.a; var b = n.b; var c = n.c;
    match n.tag {
        associated, scoped, universal, existential, opened, invalid, erased_proof => { return 0, blot_error::Error.declined; },
        unit, boolean, unsigned32, floating32, never, erased => {
            if a != 0 || b != 0 || c != 0 { return 0, blot_error::Error.declined; }
            var mapped: u32 = 0;
            match n.tag {
                unit => { mapped = 1; }, boolean => { mapped = 2; },
                unsigned32 => { mapped = 3; }, floating32 => { mapped = 4; },
                never => { mapped = 5; }, erased => { mapped = 6; },
                _ => { abort("unreachable scalar layout"); },
            }
            if g.representations.store.node(mapped).tag != n.tag { return 0, blot_error::Error.declined; }
            self_.layouts.insert(id, mapped); return mapped, blot_error::Error.none;
        },
        product, record, nominal => {
            if n.tag != blot_backend_layout::Tag.nominal && c != 0 { return 0, blot_error::Error.declined; }
            let children, import_error_1 = shapeChildren(__old.layouts, id); if import_error_1 != blot_error::Error.none { return 0, convert(import_error_1); }
            { let import_error_2 = values.ensure(children.len); if import_error_2 != blot_error::Error.none { return 0, convert(import_error_2); } }
            if n.tag == blot_backend_layout::Tag.nominal { { let imported_3, import_error_3 = self_.nominal(a, b); if import_error_3 != blot_error::Error.none { return 0, convert(import_error_3); } a = imported_3; } { let imported_4, import_error_4 = self_.nominalDeclaration(b); if import_error_4 != blot_error::Error.none { return 0, convert(import_error_4); } b = imported_4; } }
            else { a = 0; b = 0; }
            for child, index in children {
                var mapped: u32 = 0;
                if n.tag == blot_backend_layout::Tag.record && index % 2 == 0 { { let imported_5, import_error_5 = self_.symbol(child); if import_error_5 != blot_error::Error.none { return 0, convert(import_error_5); } mapped = imported_5; } }
                else { { let imported_6, import_error_6 = self_.shape(g, child, depth + 1); if import_error_6 != blot_error::Error.none { return 0, convert(import_error_6); } mapped = imported_6; } }
                { let import_error_7 = values.push(mapped); if import_error_7 != blot_error::Error.none { return 0, convert(import_error_7); } }
            }
            if n.tag == blot_backend_layout::Tag.record { { let import_error_8 = uniqueFields(values.items); if import_error_8 != blot_error::Error.none { return 0, convert(import_error_8); } } }
            c = 0;
        },
        owning => {
            if c != 0 || (b != blot_check_types::usageKindCode(blot_parse_ast::usagekind_unique) && b != blot_check_types::usageKindCode(blot_parse_ast::usagekind_shared)) { return 0, blot_error::Error.declined; }
            { let imported_9, import_error_9 = self_.shape(g, a, depth + 1); if import_error_9 != blot_error::Error.none { return 0, convert(import_error_9); } a = imported_9; }
        },
        function => { { let imported_10, import_error_10 = self_.shape(g, a, depth + 1); if import_error_10 != blot_error::Error.none { return 0, convert(import_error_10); } a = imported_10; } { let imported_11, import_error_11 = self_.shape(g, b, depth + 1); if import_error_11 != blot_error::Error.none { return 0, convert(import_error_11); } b = imported_11; } { let imported_12, import_error_12 = self_.row(g, Domain.layout, c, depth + 1); if import_error_12 != blot_error::Error.none { return 0, convert(import_error_12); } c = imported_12; } },
        array, list, cursor, resolver => {
            if b != 0 || c != 0 { return 0, blot_error::Error.declined; } { let imported_13, import_error_13 = self_.shape(g, a, depth + 1); if import_error_13 != blot_error::Error.none { return 0, convert(import_error_13); } a = imported_13; }
        },
        provider => { if b != 0 { return 0, blot_error::Error.declined; } { let imported_14, import_error_14 = self_.shape(g, a, depth + 1); if import_error_14 != blot_error::Error.none { return 0, convert(import_error_14); } a = imported_14; } { let imported_15, import_error_15 = self_.row(g, Domain.layout, c, depth + 1); if import_error_15 != blot_error::Error.none { return 0, convert(import_error_15); } c = imported_15; } },
        state_provider => { { let imported_16, import_error_16 = self_.shape(g, a, depth + 1); if import_error_16 != blot_error::Error.none { return 0, convert(import_error_16); } a = imported_16; } { let imported_17, import_error_17 = self_.shape(g, b, depth + 1); if import_error_17 != blot_error::Error.none { return 0, convert(import_error_17); } b = imported_17; } { let imported_18, import_error_18 = self_.shape(g, c, depth + 1); if import_error_18 != blot_error::Error.none { return 0, convert(import_error_18); } c = imported_18; } },
        type_constructor => { if c != 0 { return 0, blot_error::Error.declined; } { let imported_19, import_error_19 = self_.nominal(a, b); if import_error_19 != blot_error::Error.none { return 0, convert(import_error_19); } a = imported_19; } { let imported_20, import_error_20 = self_.nominalDeclaration(b); if import_error_20 != blot_error::Error.none { return 0, convert(import_error_20); } b = imported_20; } },
    }
    var mapped: u32 = 0;
    if n.tag == blot_backend_layout::Tag.state_provider { { let imported_21, import_error_21 = g.representations.store.internStateProvider(a, b, c); if import_error_21 != blot_error::Error.none { return 0, convert(import_error_21); } mapped = imported_21; } }
    else { { let imported_22, import_error_22 = g.representations.store.internWithEffects(n.tag, a, b, c, values.items); if import_error_22 != blot_error::Error.none { return 0, convert(import_error_22); } mapped = imported_22; } }
    self_.layouts.insert(id, mapped); return mapped, blot_error::Error.none;
}
recursive fn semanticType<G>(self_: Importer&, g: G&, id: u32, depth: i64) -> u32, Error {
    let __old:const Pools& =requiredPools(self_.old);
    if depth >= depth_limit || id == 0 || id >= __old.evaluator.evidence.nodes.len { return 0, blot_error::Error.declined; }
    self_.census.semantic_queries++;
    let key = EvidenceKey { id: id , ..}; let known = self_.semantic.get(key);
    if known { self_.census.semantic_hits++; return known, blot_error::Error.none; }
    var values = blot_reuse_source_value_template::WordBuffer {..};
    let result, error = self_.semanticTypeInto(g, id, depth, values);
    values.deinit(); return result, error;
}
recursive fn semanticTypeInto<G>(self_: Importer&, g: G&, id: u32, depth: i64, values: blot_reuse_source_value_template::WordBuffer&) -> u32, Error {
    let __old:const Pools& =requiredPools(self_.old);
    let n = __old.evaluator.evidence.nodes[id];
    var a = n.a; var b = n.b; var c = n.c;
    match n.tag {
        projection, scoped, forall, existential, bound, usage, absent, erased_proof => { return 0, blot_error::Error.declined; },
        unit, boolean, unsigned32, floating32, never => { if a != 0 || b != 0 || c != 0 { return 0, blot_error::Error.declined; } },
        product, record, nominal => {
            if n.tag != blot_eval_type_evidence::Tag.nominal && c != 0 { return 0, blot_error::Error.declined; }
            let children, import_error_23 = evidenceChildren(__old.evaluator.evidence.view(), id); if import_error_23 != blot_error::Error.none { return 0, convert(import_error_23); }
            { let import_error_24 = values.ensure(children.len); if import_error_24 != blot_error::Error.none { return 0, convert(import_error_24); } }
            if n.tag == blot_eval_type_evidence::Tag.nominal { { let imported_25, import_error_25 = self_.semanticNominal(a, b); if import_error_25 != blot_error::Error.none { return 0, convert(import_error_25); } a = imported_25; } { let imported_26, import_error_26 = self_.nominalDeclaration(b); if import_error_26 != blot_error::Error.none { return 0, convert(import_error_26); } b = imported_26; } }
            else { a = 0; b = 0; }
            for child, index in children {
                var mapped: u32 = 0;
                if n.tag == blot_eval_type_evidence::Tag.record && index % 2 == 0 { { let imported_27, import_error_27 = self_.symbol(child); if import_error_27 != blot_error::Error.none { return 0, convert(import_error_27); } mapped = imported_27; } }
                else { { let imported_28, import_error_28 = self_.semanticType(g, child, depth + 1); if import_error_28 != blot_error::Error.none { return 0, convert(import_error_28); } mapped = imported_28; } }
                { let import_error_29 = values.push(mapped); if import_error_29 != blot_error::Error.none { return 0, convert(import_error_29); } }
            }
            if n.tag == blot_eval_type_evidence::Tag.record { { let import_error_30 = uniqueFields(values.items); if import_error_30 != blot_error::Error.none { return 0, convert(import_error_30); } } }
            c = 0;
        },
        function => { { let imported_31, import_error_31 = self_.semanticType(g, a, depth + 1); if import_error_31 != blot_error::Error.none { return 0, convert(import_error_31); } a = imported_31; } { let imported_32, import_error_32 = self_.semanticType(g, b, depth + 1); if import_error_32 != blot_error::Error.none { return 0, convert(import_error_32); } b = imported_32; } { let imported_33, import_error_33 = self_.row(g, Domain.semantic, c, depth + 1); if import_error_33 != blot_error::Error.none { return 0, convert(import_error_33); } c = imported_33; } },
        array, list, cursor, resolver => { if b != 0 || c != 0 { return 0, blot_error::Error.declined; } { let imported_34, import_error_34 = self_.semanticType(g, a, depth + 1); if import_error_34 != blot_error::Error.none { return 0, convert(import_error_34); } a = imported_34; } },
        provider => { if b != 0 { return 0, blot_error::Error.declined; } { let imported_35, import_error_35 = self_.semanticType(g, a, depth + 1); if import_error_35 != blot_error::Error.none { return 0, convert(import_error_35); } a = imported_35; } { let imported_36, import_error_36 = self_.row(g, Domain.semantic, c, depth + 1); if import_error_36 != blot_error::Error.none { return 0, convert(import_error_36); } c = imported_36; } },
        state_provider => { { let imported_37, import_error_37 = self_.semanticType(g, a, depth + 1); if import_error_37 != blot_error::Error.none { return 0, convert(import_error_37); } a = imported_37; } { let imported_38, import_error_38 = self_.semanticType(g, b, depth + 1); if import_error_38 != blot_error::Error.none { return 0, convert(import_error_38); } b = imported_38; } { let imported_39, import_error_39 = self_.semanticType(g, c, depth + 1); if import_error_39 != blot_error::Error.none { return 0, convert(import_error_39); } c = imported_39; } },
        type_constructor => { if c != 0 { return 0, blot_error::Error.declined; } { let imported_40, import_error_40 = self_.semanticNominal(a, b); if import_error_40 != blot_error::Error.none { return 0, convert(import_error_40); } a = imported_40; } { let imported_41, import_error_41 = self_.nominalDeclaration(b); if import_error_41 != blot_error::Error.none { return 0, convert(import_error_41); } b = imported_41; } },
    }
    var mapped: u32 = 0;
    if n.tag == blot_eval_type_evidence::Tag.state_provider { { let imported_42, import_error_42 = g.evaluator.storage.evidence.internStateProvider(a, b, c); if import_error_42 != blot_error::Error.none { return 0, convert(import_error_42); } mapped = imported_42; } }
    else { { let imported_43, import_error_43 = g.evaluator.storage.evidence.internWithEffects(n.tag, a, b, c, values.items); if import_error_43 != blot_error::Error.none { return 0, convert(import_error_43); } mapped = imported_43; } }
    self_.semantic.insert(EvidenceKey { id: id , ..}, mapped);
    self_.census.semantic_nodes++; self_.census.semantic_child_words += values.items.len;
    return mapped, blot_error::Error.none;
}
recursive fn row<G>(self_: Importer&, g: G&, domain: Domain, id: u32, depth: i64) -> u32, Error {
    if depth >= depth_limit { return 0, blot_error::Error.declined; }
    if domain == Domain.layout && id == blot_backend_layout::unknown_row { return id, blot_error::Error.none; }
    self_.census.row_queries++;
    let key = RowKey { domain, id , ..}; let known = self_.rows.get(key);
    if known { self_.census.row_hits++; return known, blot_error::Error.none; }
    var imported = blot_reuse_source_value_template::WordBuffer {..};
    var arguments = blot_reuse_source_value_template::WordBuffer {..};
    let mapped, error = self_.rowInto(g, domain, id, depth, imported, arguments);
    imported.deinit(); arguments.deinit(); return mapped, error;
}
recursive fn rowInto<G>(self_: Importer&, g: G&, domain: Domain, id: u32, depth: i64, imported: blot_reuse_source_value_template::WordBuffer&, arguments: blot_reuse_source_value_template::WordBuffer&) -> u32, Error {
    let old:const Pools& =requiredPools(self_.old);
    var source = old.layouts.effects.view();
    if domain == Domain.semantic { source = old.evaluator.evidence.effects.view(); }
    if id >= source.rows.len { return 0, blot_error::Error.declined; }
    let span = source.rows[id]; let labels, import_error_44 = bounded(source.labels, span.start, span.len); if import_error_44 != blot_error::Error.none { return 0, convert(import_error_44); }
    if id == 0 && labels.len != 0 { return 0, blot_error::Error.declined; }
    { let import_error_45 = imported.ensure(labels.len); if import_error_45 != blot_error::Error.none { return 0, convert(import_error_45); } }
    for label in labels {
        if label == 0 || label >= source.operations.len { return 0, blot_error::Error.declined; }
        let operation = source.operations[label];
        if operation.instance.unit != 0 || operation.instance.decl != 0 { return 0, blot_error::Error.declined; }
        let old_args, import_error_46 = bounded(source.arguments, operation.arguments.start, operation.arguments.len); if import_error_46 != blot_error::Error.none { return 0, convert(import_error_46); }
        self_.census.row_argument_words += old_args.len;
        var owner: u32 = 0;
        if operation.identity.unit == 0 {
            if operation.identity.decl != 1 || old_args.len != 0 { return 0, blot_error::Error.declined; }
        } else if domain == Domain.semantic { { let imported_47, import_error_47 = self_.semanticNominal(operation.identity.unit, operation.identity.decl); if import_error_47 != blot_error::Error.none { return 0, convert(import_error_47); } owner = imported_47; } }
        else { { let imported_48, import_error_48 = self_.nominal(operation.identity.unit, operation.identity.decl); if import_error_48 != blot_error::Error.none { return 0, convert(import_error_48); } owner = imported_48; } }
        arguments.clear(); { let import_error_49 = arguments.ensure(old_args.len); if import_error_49 != blot_error::Error.none { return 0, convert(import_error_49); } }
        for argument in old_args {
            var mapped: u32 = 0;
            if domain == Domain.layout { { let imported_50, import_error_50 = self_.shape(g, argument, depth + 1); if import_error_50 != blot_error::Error.none { return 0, convert(import_error_50); } mapped = imported_50; } }
            else { { let imported_51, import_error_51 = self_.semanticType(g, argument, depth + 1); if import_error_51 != blot_error::Error.none { return 0, convert(import_error_51); } mapped = imported_51; } }
            { let import_error_52 = arguments.push(mapped); if import_error_52 != blot_error::Error.none { return 0, convert(import_error_52); } }
        }
        var new_label: u32 = 0;
        let identity = blot_check_types::NominalIdentity { owner, operation.identity.decl , ..};
        if domain == Domain.layout { { let imported_53, import_error_53 = g.representations.store.effects.internOperation(identity, arguments.items); if import_error_53 != blot_error::Error.none { return 0, convert(import_error_53); } new_label = imported_53; } }
        else { { let imported_54, import_error_54 = g.evaluator.storage.evidence.effects.internOperation(identity, arguments.items); if import_error_54 != blot_error::Error.none { return 0, convert(import_error_54); } new_label = imported_54; } }
        { let import_error_55 = imported.push(new_label); if import_error_55 != blot_error::Error.none { return 0, convert(import_error_55); } }
    }
    var mapped: u32 = 0;
    if domain == Domain.layout { { let imported_56, import_error_56 = g.representations.store.effects.internRow(imported.items); if import_error_56 != blot_error::Error.none { return 0, convert(import_error_56); } mapped = imported_56; } }
    else { { let imported_57, import_error_57 = g.evaluator.storage.evidence.effects.internRow(imported.items); if import_error_57 != blot_error::Error.none { return 0, convert(import_error_57); } mapped = imported_57; } }
    self_.rows.insert(RowKey { domain, id , ..}, mapped); self_.census.row_nodes++;
    return mapped, blot_error::Error.none;
}

fn expressionUnit(self_: const Importer&, source: u32, root: u32) -> u32, Error {
    let mapped, import_error_1 = self_.unit(source, false); if import_error_1 != blot_error::Error.none { return 0, convert(import_error_1); }
    if self_.stable[source - 1] || self_.expression_nodes.contains(ExpressionKey { source, root , ..}) { return mapped, blot_error::Error.none; }
    if !self_.code_gate.present { return 0, blot_error::Error.declined; }
    let gate .= self_.code_gate.value.semantic;
    if !gate.enabled { return 0, blot_error::Error.declined; }
    if !gate.structural_units[source - 1] {
        if !self_.code_gate.value.expressionRoot(mapped, root) { return 0, blot_error::Error.declined; }
        return mapped, blot_error::Error.none;
    }
    let __old:const Pools& =requiredPools(self_.old);
    let references, import_error_2 = blot_reuse_declaration_dependencies::expressionReferences(__old.modules[source - 1].module, root); if import_error_2 != blot_error::Error.none { return 0, convert(import_error_2); }
    var admitted = true;
    for reference in references {
        var unit = reference.unit; if unit == 0 { unit = source; }
        if unit == 0 || unit >= gate.offsets.len || reference.binding >= gate.units[unit - 1].bindings.len || gate.dirty[gate.offsets[unit - 1] + reference.binding] { admitted = false; break; }
    }
    blot_reuse_declaration_dependencies::releaseReferences(references);
    if !admitted { return 0, blot_error::Error.declined; }
    return mapped, blot_error::Error.none;
}
fn checkFields<G>(self_: const Importer&, g: G&) -> Error {
    let __old:const Pools& =requiredPools(self_.old);
    if __old.field_locations.len != g.evaluator.field_locations.count { return blot_error::Error.declined; }
    for field in __old.field_locations {
        let source_unit = (field.family >> 32) as u32; let decl = field.family as! u32;
        var mapped = source_unit;
        if source_unit != 0xffffffff { let value, error = self_.unit(source_unit, false); if error != blot_error::Error.none { return error; } mapped = value; }
        let family = (mapped as u64) << 32 | decl;
        let name, error = self_.symbol(field.name); if error != blot_error::Error.none { return error; }
        let found = g.evaluator.field_locations.get(blot_eval_core_eval::FieldKey { family, field.tag, name , ..});
        if !found || found.field != field.field || found.len != field.len { return blot_error::Error.declined; }
    }
    return blot_error::Error.none;
}
fn staticEntries(self_: const Importer&, id: u32) -> const blot_reuse_substitution_keys::Entry[:], Error {
    let __old:const Pools& =requiredPools(self_.old);
    if id == 0 { return default<const blot_reuse_substitution_keys::Entry[:]>(), blot_error::Error.none; }
    if id > __old.static_values.spans.len { return default<const blot_reuse_substitution_keys::Entry[:]>(), blot_error::Error.declined; }
    let span = __old.static_values.spans[id - 1];
    let entries, error = bounded(__old.static_values.entries, span.start, span.len);
    if error != blot_error::Error.none { return default<const blot_reuse_substitution_keys::Entry[:]>(), error; }
    for entry, index in entries {
        if entry.variable == 0 || entry.value >= __old.evaluator.values.len { return default<const blot_reuse_substitution_keys::Entry[:]>(), blot_error::Error.declined; }
        if index != 0 && entry.variable <= entries[index - 1].variable { return default<const blot_reuse_substitution_keys::Entry[:]>(), blot_error::Error.declined; }
    }
    return entries, blot_error::Error.none;
}
fn substitutionEntries(pool: const blot_reuse_code_artifacts::Substitutions&, id: u32) -> const blot_reuse_substitution_keys::Entry[:], Error {
    if id == 0 { return default<const blot_reuse_substitution_keys::Entry[:]>(), blot_error::Error.none; }
    if id > pool.spans.len { return default<const blot_reuse_substitution_keys::Entry[:]>(), blot_error::Error.declined; }
    let span = pool.spans[id - 1]; let entries, error = bounded(pool.entries, span.start, span.len);
    if error != blot_error::Error.none { return default<const blot_reuse_substitution_keys::Entry[:]>(), error; }
    for entry, index in entries { if index != 0 && entry.variable <= entries[index - 1].variable { return default<const blot_reuse_substitution_keys::Entry[:]>(), blot_error::Error.declined; } }
    return entries, blot_error::Error.none;
}
fn recordValueAnchorIds(self_: Importer&, anchors: const u32[:], ids: u32[:]) -> bool, Error {
    let __old:const Pools& =requiredPools(self_.old);
    if anchors.len != __old.evaluator.values.len { return false, blot_error::Error.none; }
    sortWords(ids);
    for old in ids {
        let current = anchors[old]; if current == 0 { continue; }
        let known = self_.value_anchors.get(old); if known && known != current { return false, blot_error::Error.none; }
    }
    for old in ids { let current = anchors[old]; if current != 0 { self_.value_anchors.insert(old, current); } }
    return true, blot_error::Error.none;
}
fn recordValueAnchors(self_: Importer&, anchors: const u32[:]) -> bool, Error {
    let __old:const Pools& =requiredPools(self_.old);
    if anchors.len != __old.evaluator.values.len { return false, blot_error::Error.none; }
    for current, old in anchors { if current == 0 { continue; } let known = self_.value_anchors.get(old as u32); if known && known != current { return false, blot_error::Error.none; } }
    for current, old in anchors { if current != 0 { self_.value_anchors.insert(old as u32, current); } }
    return true, blot_error::Error.none;
}
// Heap sort bounds scratch to two words even for large sparse correspondences.
fn sortWords(values: u32[:]) {
    var start = values.len / 2;
    while start > 0 { start--; siftWords(values, start, values.len); }
    var end = values.len;
    while end > 1 { end--; let first = values[0]; values[0] = values[end]; values[end] = first; siftWords(values, 0, end); }
}
fn siftWords(values: u32[:], start: i64, end: i64) {
    var root = start;
    while root < end / 2 {
        var child = root * 2 + 1;
        if child + 1 < end && values[child] < values[child + 1] { child++; }
        if values[root] >= values[child] { return; }
        let value = values[root]; values[root] = values[child]; values[child] = value; root = child;
    }
}
fn closedShape<G>(self_: Importer&, g: G&, old_id: u32) -> u32, Error {
    let actual, import_error_3 = self_.shape(g, old_id, 0); if import_error_3 != blot_error::Error.none { return 0, convert(import_error_3); }
    let known, import_error_4 = self_.knowledge.knownLayout(g.representations.store, actual); if import_error_4 != blot_error::Error.none { return 0, convert(import_error_4); }
    if !known { return 0, blot_error::Error.declined; } return actual, blot_error::Error.none;
}

fn target(self_: const Importer&, value: blot_check_core::BindingRef) -> blot_check_core::BindingRef, Error {
    if !self_.admitsBody(value) { return default<blot_check_core::BindingRef>(), blot_error::Error.declined; }
    let mapped, error = self_.unit(value.unit, false);
    if error != blot_error::Error.none { return default<blot_check_core::BindingRef>(), error; }
    if value.binding == 0 || value.binding >= self_.units[mapped - 1].bindings.len || !self_.units[mapped - 1].body(value.binding) { return default<blot_check_core::BindingRef>(), blot_error::Error.declined; }
    return blot_check_core::BindingRef { mapped, value.binding , ..}, blot_error::Error.none;
}
fn importRequest<G>(self_: Importer&, g: G&, old: blot_reuse_code_artifacts::Request) -> blot_support::Option<blot_reuse_code_artifacts::Request>, Error {
    let value, error = self_.request(g, old, true);
    if error == blot_error::Error.none { return blot_support::some(value), blot_error::Error.none; }
    if error == blot_error::Error.out_of_memory { return blot_support::none<blot_reuse_code_artifacts::Request>(), error; }
    return blot_support::none<blot_reuse_code_artifacts::Request>(), blot_error::Error.none;
}
fn matches<G>(self_: Importer&, g: G&, old: blot_reuse_code_artifacts::Request, current: blot_reuse_code_artifacts::Request) -> bool, Error {
    match old {
        closure old_closure => {
            match current {
                closure current_closure => {
                    if old_closure.key.static_values != 0 || current_closure.key.static_values != 0 {
                        var actual = current_closure.key; actual.static_values = 0;
                        let imported, error = self_.request(g, old, false);
                        if error == blot_error::Error.out_of_memory { return false, error; }
                        if error != blot_error::Error.none || imported != (blot_reuse_code_artifacts::Request.closure { actual , ..}) { return false, blot_error::Error.none; }
                        return self_.matchStaticKey(g, old_closure.key.static_values, current_closure.key.static_values);
                    }
                }, _ => {},
            }
        }, _ => {},
    }
    let imported, error = self_.importRequest(g, old);
    return imported.present && imported.value == current, error;
}
fn request<G>(self_: Importer&, g: G&, old: blot_reuse_code_artifacts::Request, import_static: bool) -> blot_reuse_code_artifacts::Request, Error {
    { let import_error_1 = self_.bind(g); if import_error_1 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_1); } }
    let __old:const Pools& =requiredPools(self_.old);
    match old {
        named payload => {
            var key = payload.key;
            if key.instance_arguments != 0 || key.dictionaries || key.count > blot_reuse_code_artifacts::max_parameters { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            { let imported_2, import_error_2 = self_.target(key.target); if import_error_2 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_2); } key.target = imported_2; }
            for index in 0..blot_reuse_code_artifacts::max_parameters {
                if index >= key.count {
                    if key.parameters[index] != 1 || key.effects[index] != 0 { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
                    continue;
                }
                { let imported_3, import_error_3 = self_.shape(g, key.parameters[index], 0); if import_error_3 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_3); } key.parameters[index] = imported_3; }
                let known, import_error_4 = self_.knowledge.knownLayout(g.representations.store, key.parameters[index]); if import_error_4 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_4); }
                if !known || key.effects[index] == blot_backend_layout::unknown_row { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
                { let imported_5, import_error_5 = self_.row(g, Domain.layout, key.effects[index], 0); if import_error_5 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_5); } key.effects[index] = imported_5; }
                let row_known, import_error_6 = self_.knowledge.knownRow(g.representations.store, key.effects[index]); if import_error_6 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_6); }
                if !row_known { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            }
            { let imported_7, import_error_7 = self_.closedShape(g, key.result); if import_error_7 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_7); } key.result = imported_7; }
            { let imported_8, import_error_8 = self_.templateKey(g, payload.key.target.unit, key.templates, 0); if import_error_8 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_8); } key.templates = imported_8; }
            return blot_reuse_code_artifacts::Request.named { key , ..}, blot_error::Error.none;
        },
        closure payload => {
            var key = payload.key; let source = payload.key;
            if key.dictionaries || source.unit == 0 || source.unit > __old.modules.len || source.catalog >= __old.modules[source.unit - 1].module.closures.len { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            { let imported_9, import_error_9 = self_.expressionUnit(source.unit, __old.modules[source.unit - 1].module.closures[source.catalog].body); if import_error_9 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_9); } key.unit = imported_9; }
            if key.catalog >= self_.units[key.unit - 1].closures.len { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            { let imported_10, import_error_10 = self_.shape(g, key.ty, 0); if import_error_10 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_10); } key.ty = imported_10; }
            { let imported_11, import_error_11 = self_.shape(g, key.captures, 0); if import_error_11 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_11); } key.captures = imported_11; }
            if g.representations.store.node(key.ty).tag != blot_backend_layout::Tag.function || g.representations.store.node(key.captures).tag != blot_backend_layout::Tag.product { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            let known, import_error_12 = self_.knowledge.knownLayout(g.representations.store, key.ty); if import_error_12 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_12); }
            if !known { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            if source.static_values == 0 {
                let captures_known, import_error_13 = self_.knowledge.knownLayout(g.representations.store, key.captures); if import_error_13 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_13); }
                if !captures_known { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            } else {
                let module .= __old.modules[source.unit - 1].module; let span = module.closures[source.catalog].captures;
                let bindings = module.extra[span.start..span.start + span.len];
                let layouts = g.representations.store.children(key.captures);
                if bindings.len != layouts.len { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
                let statics, import_error_14 = self_.staticEntries(source.static_values); if import_error_14 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_14); }
                for binding, index in bindings {
                    var is_static = false;
                    for item in statics { if item.variable == binding { is_static = true; break; } }
                    if !is_static {
                        let capture_known, import_error_15 = self_.knowledge.knownLayout(g.representations.store, layouts[index]); if import_error_15 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_15); }
                        if !capture_known { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
                    }
                }
            }
            { let imported_16, import_error_16 = self_.templateKey(g, source.unit, key.templates, 0); if import_error_16 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_16); } key.templates = imported_16; }
            { let imported_17, import_error_17 = self_.mappingEvidence(g, source.unit, key.evidence, 0); if import_error_17 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_17); } key.evidence = imported_17; }
            { let imported_18, import_error_18 = self_.rowKey(g, source.unit, key.rows, 0); if import_error_18 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_18); } key.rows = imported_18; }
            if key.parameter_template != 0 { { let imported_19, import_error_19 = self_.capture(g, key.parameter_template, 0); if import_error_19 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_19); } key.parameter_template = imported_19; } }
            key.static_values = 0;
            if import_static { { let imported_20, import_error_20 = self_.staticKey(g, source.static_values); if import_error_20 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_20); } key.static_values = imported_20; } }
            if key.scalar_environment && (!g.representations.store.scalarEnvironment(key.captures) || key.templates != 0 || key.static_values != 0) { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            return blot_reuse_code_artifacts::Request.closure { key , ..}, blot_error::Error.none;
        },
        callable payload => {
            let old_key = payload.key;
            if old_key.dictionaries || old_key.bound_dictionaries || old_key.instance_arguments != 0 { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            let target, import_error_21 = self_.target(old_key.target); if import_error_21 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_21); }
            let ty, import_error_22 = self_.closedShape(g, old_key.ty); if import_error_22 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_22); }
            let templates, import_error_23 = self_.templateKey(g, old_key.target.unit, old_key.templates, 0); if import_error_23 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_23); }
            return blot_reuse_code_artifacts::Request.callable { blot_reuse_code_artifacts::CallableKey { target: target, ty: ty, applied: old_key.applied, templates: templates } , ..}, blot_error::Error.none;
        },
        constructor payload => {
            let owner, import_error_24 = self_.typeUnit(payload.key.unit); if import_error_24 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_24); }
            if payload.key.catalog >= self_.units[owner - 1].constructors.len { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            let ty, import_error_25 = self_.closedShape(g, payload.key.ty); if import_error_25 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_25); }
            return blot_reuse_code_artifacts::Request.constructor { blot_reuse_code_artifacts::ConstructorKey { owner, payload.key.catalog, ty } , ..}, blot_error::Error.none;
        },
        primitive payload => {
            let owner, import_error_26 = self_.unit(payload.key.unit, true); if import_error_26 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_26); }
            if payload.key.catalog >= self_.units[owner - 1].primitives.len { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            let ty, import_error_27 = self_.closedShape(g, payload.key.ty); if import_error_27 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_27); }
            return blot_reuse_code_artifacts::Request.primitive { blot_reuse_code_artifacts::PrimitiveKey { owner, payload.key.catalog, ty, payload.key.applied } , ..}, blot_error::Error.none;
        },
        operation payload => {
            if payload.key.operation == 0 || payload.key.operation > __old.operations.len { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            let operation = __old.operations[payload.key.operation - 1];
            { let import_error_28 = self_.operationScope(g, payload.key.operation); if import_error_28 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_28); } }
            for current, index in g.planning.runtime_operations.entries {
                if current.foreign != operation.foreign || g.planning.runtime_operations.key(current) != operation.key { continue; }
                let ty, import_error_29 = self_.closedShape(g, payload.key.ty); if import_error_29 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_29); }
                return blot_reuse_code_artifacts::Request.operation { blot_reuse_code_artifacts::OperationKey { operation: (index + 1) as u32, ty: ty } , ..}, blot_error::Error.none;
            }
            return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined;
        },
        host payload => {
            let ty, import_error_30 = self_.closedShape(g, payload.key.ty); if import_error_30 != blot_error::Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_30); }
            let arrow = g.representations.store.node(ty);
            if arrow.tag != blot_backend_layout::Tag.function { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            let cleanup = g.representations.store.node(arrow.a).tag == blot_backend_layout::Tag.owning;
            if payload.key.owned != (cleanup && g.persistent_outputs) { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            if cleanup {
                let input = g.representations.store.node(arrow.a).a;
                if !g.representations.store.abi(input).present || g.representations.store.node(input).tag == blot_backend_layout::Tag.nominal { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; }
            }
            return blot_reuse_code_artifacts::Request.host { blot_reuse_code_artifacts::HostKey { ty, payload.key.owned } , ..}, blot_error::Error.none;
        },
        constant, runtime_global => { return default<blot_reuse_code_artifacts::Request>(), blot_error::Error.declined; },
    }
}

struct EntryBuffer { storage: blot_reuse_substitution_keys::Entry[:] = default<blot_reuse_substitution_keys::Entry[:]>(), items: blot_reuse_substitution_keys::Entry[:] = default<blot_reuse_substitution_keys::Entry[:]>() }
reusable[] var entry_buffer_runs: blot_reuse_substitution_keys::Entry[>..] = [];
fn push(self_: EntryBuffer&, value: blot_reuse_substitution_keys::Entry) -> Error { return blot_support_pooled_buffer::push(self_, value, entry_buffer_runs); }
fn deinit(self_: EntryBuffer&) { blot_support_pooled_buffer::deinit(self_, entry_buffer_runs); }
recursive fn mappingEvidence<G>(self_: Importer&, g: G&, owner: u32, id: u32, depth: i64) -> u32, Error {
    if id == 0 { return 0, blot_error::Error.none; } let __old:const Pools& =requiredPools(self_.old);
    if depth >= depth_limit || id >= __old.evaluator.evidence.nodes.len { return 0, blot_error::Error.declined; }
    let key = EvidenceKey { id: id, owner: owner, mappings: true , ..};
    let known = self_.semantic.get(key); if known { return known, blot_error::Error.none; }
    var words = blot_reuse_source_value_template::WordBuffer {..};
    let result, error = self_.mappingEvidenceInto(g, owner, id, depth, words);
    words.deinit(); return result, error;
}
recursive fn mappingEvidenceInto<G>(self_: Importer&, g: G&, owner: u32, id: u32, depth: i64, words: blot_reuse_source_value_template::WordBuffer&) -> u32, Error {
    let __old:const Pools& =requiredPools(self_.old);
    let module, import_error_1 = self_.oldModule(owner); if import_error_1 != blot_error::Error.none { return 0, convert(import_error_1); } assert(module);
    if __old.evaluator.evidence.nodes[id].tag != blot_eval_type_evidence::Tag.record { return 0, blot_error::Error.declined; }
    let children, import_error_2 = evidenceChildren(__old.evaluator.evidence.view(), id); if import_error_2 != blot_error::Error.none { return 0, convert(import_error_2); }
    for index in 0..children.len / 2 {
        let variable = children[index * 2];
        if variable == 0 || variable >= module.types.nodes.len { return 0, blot_error::Error.declined; }
        let evidence, import_error_3 = self_.semanticType(g, children[index * 2 + 1], depth + 1); if import_error_3 != blot_error::Error.none { return 0, convert(import_error_3); }
        { let import_error_4 = words.push(variable); if import_error_4 != blot_error::Error.none { return 0, convert(import_error_4); } } { let import_error_5 = words.push(evidence); if import_error_5 != blot_error::Error.none { return 0, convert(import_error_5); } }
    }
    { let import_error_6 = uniqueFields(words.items); if import_error_6 != blot_error::Error.none { return 0, convert(import_error_6); } }
    let mapped, import_error_7 = g.evaluator.storage.evidence.intern(blot_eval_type_evidence::Tag.record, 0, 0, words.items); if import_error_7 != blot_error::Error.none { return 0, convert(import_error_7); }
    self_.semantic.insert(EvidenceKey { id: id, owner: owner, mappings: true , ..}, mapped);
    return mapped, blot_error::Error.none;
}
recursive fn templateKey<G>(self_: Importer&, g: G&, owner: u32, id: u32, depth: i64) -> u32, Error {
    if id == 0 { return 0, blot_error::Error.none; }
    if depth >= depth_limit { return 0, blot_error::Error.declined; }
    let key = SubstitutionKey { id, owner , ..}; let known = self_.template_keys.get(key);
    if known { return known, blot_error::Error.none; }
    var imported = EntryBuffer {..};
    let result, error = self_.substitutionInto(g, owner, id, depth, false, imported);
    imported.deinit(); return result, error;
}
recursive fn rowKey<G>(self_: Importer&, g: G&, owner: u32, id: u32, depth: i64) -> u32, Error {
    if id == 0 { return 0, blot_error::Error.none; }
    if depth >= depth_limit { return 0, blot_error::Error.declined; }
    let key = SubstitutionKey { id, owner , ..}; let known = self_.row_keys.get(key);
    if known { return known, blot_error::Error.none; }
    var imported = EntryBuffer {..};
    let result, error = self_.substitutionInto(g, owner, id, depth, true, imported);
    imported.deinit(); return result, error;
}
recursive fn substitutionInto<G>(self_: Importer&, g: G&, owner: u32, id: u32, depth: i64, row_key: bool, imported: EntryBuffer&) -> u32, Error {
    let __old:const Pools& =requiredPools(self_.old);
    let module, import_error_8 = self_.oldModule(owner); if import_error_8 != blot_error::Error.none { return 0, convert(import_error_8); } assert(module);
    var source .= __old.templates; if row_key { source .= __old.rows; }
    let entries, import_error_9 = substitutionEntries(source, id); if import_error_9 != blot_error::Error.none { return 0, convert(import_error_9); }
    for entry in entries {
        var value: u32 = 0;
        if row_key {
            if entry.variable >= module.types.effects.variable_count || entry.value == blot_backend_layout::unknown_row { return 0, blot_error::Error.declined; }
            { let imported_10, import_error_10 = self_.row(g, Domain.semantic, entry.value, depth + 1); if import_error_10 != blot_error::Error.none { return 0, convert(import_error_10); } value = imported_10; }
        } else {
            if entry.variable == 0 || entry.variable >= module.bindings.len { return 0, blot_error::Error.declined; }
            { let imported_11, import_error_11 = self_.capture(g, entry.value, depth + 1); if import_error_11 != blot_error::Error.none { return 0, convert(import_error_11); } value = imported_11; }
        }
        { let import_error_12 = imported.push(blot_reuse_substitution_keys::Entry { entry.variable, value , ..}); if import_error_12 != blot_error::Error.none { return 0, convert(import_error_12); } }
    }
    var mapped: u32 = 0;
    if row_key { { let imported_13, import_error_13 = g.representations.row_keys.intern(imported.items); if import_error_13 != blot_error::Error.none { return 0, convert(import_error_13); } mapped = imported_13; } self_.row_keys.insert(SubstitutionKey { id, owner , ..}, mapped); }
    else { { let imported_14, import_error_14 = g.representations.template_keys.intern(imported.items); if import_error_14 != blot_error::Error.none { return 0, convert(import_error_14); } mapped = imported_14; } self_.template_keys.insert(SubstitutionKey { id, owner , ..}, mapped); }
    return mapped, blot_error::Error.none;
}
recursive fn capture<G>(self_: Importer&, g: G&, id: u32, depth: i64) -> u32, Error {
    let __old:const Pools& =requiredPools(self_.old);
    if depth >= depth_limit || id == 0 || id > __old.captures.len { return 0, blot_error::Error.declined; }
    let known = self_.captures.get(id); if known { return known, blot_error::Error.none; }
    let old = __old.captures[id - 1];
    if old.callable_instances != 0 { return 0, blot_error::Error.declined; }
    let owner, import_error_15 = self_.expressionUnit(old.unit, old.node); if import_error_15 != blot_error::Error.none { return 0, convert(import_error_15); }
    if old.node == 0 || old.node >= self_.units[owner - 1].nodes.len { return 0, blot_error::Error.declined; }
    let captures, import_error_16 = self_.shape(g, old.captures, depth + 1); if import_error_16 != blot_error::Error.none { return 0, convert(import_error_16); }
    let templates, import_error_17 = self_.templateKey(g, old.unit, old.templates, depth + 1); if import_error_17 != blot_error::Error.none { return 0, convert(import_error_17); }
    let evidence, import_error_18 = self_.mappingEvidence(g, old.unit, old.evidence, depth + 1); if import_error_18 != blot_error::Error.none { return 0, convert(import_error_18); }
    let rows, import_error_19 = self_.rowKey(g, old.unit, old.rows, depth + 1); if import_error_19 != blot_error::Error.none { return 0, convert(import_error_19); }
    let imported = blot_reuse_code_artifacts::CapturedTemplate { scalar_environment: old.scalar_environment, unit: owner, node: old.node, captures: captures, templates: templates, has_environment: old.has_environment, computation: old.computation, evidence: evidence, rows: rows, .. };
    let closed, import_error_20 = self_.knowledge.knownLayout(g.representations.store, imported.captures); if import_error_20 != blot_error::Error.none { return 0, convert(import_error_20); }
    if !closed || (imported.scalar_environment && (!imported.has_environment || imported.templates != 0 || !g.representations.store.scalarEnvironment(imported.captures) || self_.units[owner - 1].node(imported.node).tag != blot_check_core::Tag.closure)) { return 0, blot_error::Error.declined; }
    var mapped: u32 = 0; let existing = g.planning.template_instances.get(imported);
    if existing { mapped = existing; }
    else {
        if g.planning.template_catalog.len >= 0xffffffff { return 0, blot_error::Error.declined; }
        mapped = (g.planning.template_catalog.len + 1) as u32;
        g.planning.template_catalog.push(imported); g.planning.template_instances.insert(imported, mapped);
    }
    self_.captures.insert(id, mapped); return mapped, blot_error::Error.none;
}
fn staticKey<G>(self_: Importer&, g: G&, id: u32) -> u32, Error {
    if id == 0 { return 0, blot_error::Error.none; }
    var entries = EntryBuffer {..};
    let result, error = self_.staticKeyInto(g, id, entries);
    entries.deinit(); return result, error;
}
fn staticKeyInto<G>(self_: Importer&, g: G&, id: u32, entries: EntryBuffer&) -> u32, Error {
    let source, import_error_21 = self_.staticEntries(id); if import_error_21 != blot_error::Error.none { return 0, convert(import_error_21); }
    for old in source {
        var current: u32 = 0;
        if old.value != 0 { let known = self_.value_anchors.get(old.value); if !known { return 0, blot_error::Error.declined; } current = known; }
        { let import_error_22 = entries.push(blot_reuse_substitution_keys::Entry { old.variable, current , ..}); if import_error_22 != blot_error::Error.none { return 0, convert(import_error_22); } }
    }
    let result, import_error_23 = g.representations.static_keys.intern(entries.items); if import_error_23 != blot_error::Error.none { return 0, convert(import_error_23); }
    return result, blot_error::Error.none;
}
fn optionalImported<T>(value: T, error: Error) -> blot_support::Option<T>, Error {
    if error == blot_error::Error.none { return blot_support::some(value), blot_error::Error.none; }
    if error == blot_error::Error.out_of_memory { return blot_support::none<T>(), error; }
    return blot_support::none<T>(), blot_error::Error.none;
}
fn importLayout<G>(self_: Importer&, g: G&, id: u32) -> blot_support::Option<u32>, Error {
    let bound = self_.bind(g); if bound != blot_error::Error.none { return optionalImported(0 as u32, bound); }
    let value, error = self_.shape(g, id, 0); return optionalImported(value, error);
}
fn importCallableLayout<G>(self_: Importer&, g: G&, id: u32, expected: blot_support::Option<u32>) -> blot_support::Option<u32>, Error {
    let __old:const Pools& =requiredPools(self_.old);
    if id == 0 || id >= __old.layouts.nodes.len || __old.layouts.nodes[id].tag != blot_backend_layout::Tag.function || (expected.present && id != expected.value) { return blot_support::none<u32>(), blot_error::Error.none; }
    let actual, error = self_.importLayout(g, id); if error != blot_error::Error.none || !actual.present { return actual, error; }
    let known, failure = self_.knowledge.knownLayout(g.representations.store, actual.value);
    if failure != blot_error::Error.none { return blot_support::none<u32>(), failure; }
    if !known { return blot_support::none<u32>(), blot_error::Error.none; }
    return actual, blot_error::Error.none;
}
fn importEvidence<G>(self_: Importer&, g: G&, id: u32) -> blot_support::Option<u32>, Error {
    let bound = self_.bind(g); if bound != blot_error::Error.none { return optionalImported(0 as u32, bound); }
    let value, error = self_.semanticType(g, id, 0); return optionalImported(value, error);
}
fn importClosedEvidence<G>(self_: Importer&, g: G&, id: u32) -> blot_support::Option<u32>, Error {
    let ordinary, error = self_.importEvidence(g, id);
    if error != blot_error::Error.none || ordinary.present { return ordinary, error; }
    if !self_.semantic_catalogs { return blot_support::none<u32>(), blot_error::Error.none; }
    let bound = self_.bind(g); if bound != blot_error::Error.none { return optionalImported(0 as u32, bound); }
    let key = EvidenceKey { id: id , ..}; let known = self_.semantic.get(key);
    if known { return blot_support::some(known as u32), blot_error::Error.none; }
    let __old:const Pools& =requiredPools(self_.old); let view = __old.evaluator.evidence.view(); var remaining: i64 = 65536;
    if view.closed(id, 0, remaining) != blot_error::Error.none { return blot_support::none<u32>(), blot_error::Error.none; }
    if !self_.closed_evidence.present {
        self_.closed_evidence = blot_support::some(blot_eval_semantic_evidence_import::initPooled(view, g.evaluator.storage.evidence, depth_limit, false));
    }
    let value, failure = self_.closed_evidence.value.ty(id, 0);
    if failure == blot_error::Error.none { self_.semantic.insert(key, value); }
    return optionalImported(value, failure);
}
fn importSemanticRow<G>(self_: Importer&, g: G&, id: u32) -> blot_support::Option<u32>, Error {
    let bound = self_.bind(g); if bound != blot_error::Error.none { return optionalImported(0 as u32, bound); }
    let value, error = self_.row(g, Domain.semantic, id, 0); return optionalImported(value, error);
}
fn importResultTemplate<G>(self_: Importer&, g: G&, id: u32) -> blot_support::Option<u32>, Error {
    let bound = self_.bind(g); if bound != blot_error::Error.none { return optionalImported(0 as u32, bound); }
    let value, error = self_.capture(g, id, 0); return optionalImported(value, error);
}

struct StaticMatchScratch {
    old_roots: blot_reuse_source_value_template::WordBuffer = blot_reuse_source_value_template::WordBuffer {..},
    current_roots: blot_reuse_source_value_template::WordBuffer = blot_reuse_source_value_template::WordBuffer {..},
    temporary: blot_support::Option<blot_reuse_source_value_template::Plan>,
}
fn deinit(self_: StaticMatchScratch&) {
    self_.old_roots.deinit(); self_.current_roots.deinit();
    if self_.temporary.present { self_.temporary.value.deinit(); self_.temporary.present = false; }
}
fn matchStaticKey<G>(self_: Importer&, g: G&, old_id: u32, current_id: u32) -> bool, Error {
    var scratch = StaticMatchScratch {..};
    let result, error = self_.matchStaticKeyInto(g, old_id, current_id, scratch);
    scratch.deinit(); return result, error;
}
fn matchStaticKeyInto<G>(self_: Importer&, g: G&, old_id: u32, current_id: u32, temporary: StaticMatchScratch&) -> bool, Error {
    let before, invalid = self_.staticEntries(old_id);
    if invalid != blot_error::Error.none { return false, blot_error::Error.none; }
    let after = g.representations.static_keys.get(current_id);
    if before.len != after.len || before.len == 0 || !self_.code_gate.present { return false, blot_error::Error.none; }
    let gate .= self_.code_gate.value.semantic;
    { let import_error_1 = temporary.old_roots.ensure(before.len); if import_error_1 != blot_error::Error.none { return false, convert(import_error_1); } } { let import_error_2 = temporary.current_roots.ensure(before.len); if import_error_2 != blot_error::Error.none { return false, convert(import_error_2); } }
    for old, index in before {
        let current = after[index];
        if old.variable != current.variable { return false, blot_error::Error.none; }
        { let import_error_3 = temporary.old_roots.push(old.value); if import_error_3 != blot_error::Error.none { return false, convert(import_error_3); } } { let import_error_4 = temporary.current_roots.push(current.value); if import_error_4 != blot_error::Error.none { return false, convert(import_error_4); } }
    }
    var plan: const blot_reuse_source_value_template::Plan? = self_.static_plans.get(old_id);
    if plan { self_.census.static_plan_hits++; }
    else {
        self_.census.static_plan_inspections++; let __old:const Pools& =requiredPools(self_.old);
        let inspection, import_error_5 = blot_reuse_source_value_template::inspectRootsWithRows(__old, gate, temporary.old_roots.items, blot_reuse_source_value_template::RowPolicy.source_declared); if import_error_5 != blot_error::Error.none { return false, convert(import_error_5); }
        temporary.temporary = inspection.plan;
        if !temporary.temporary.present { return false, blot_error::Error.none; }
        if self_.static_plans.table.count < 64 && temporary.temporary.value.order.len <= 65536 - self_.static_plan_nodes {
            self_.static_plan_nodes += temporary.temporary.value.order.len;
            self_.static_plans.insert(old_id, temporary.temporary.value); temporary.temporary.present = false;
            plan .= self_.static_plans.get(old_id);
        } else { plan .= temporary.temporary.value; }
    }
    assert(plan);
    if !self_.static_scratch.present { self_.static_scratch = blot_support::some(blot_reuse_source_value_template::QueryScratch { allocation_owner: g.allocation_owner , ..}); }
    let scratch .= self_.static_scratch.value;
    let anchors, begin_error = scratch.begin(plan, g);
    if begin_error != blot_error::Error.none { if begin_error == blot_error::Error.out_of_memory { return false, begin_error; } return false, blot_error::Error.none; }
    let matched, error = plan.matchRootsIntoWithScratch(g, self_, temporary.old_roots.items, temporary.current_roots.items, anchors, scratch);
    if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return false, error; } return false, blot_error::Error.none; }
    if !matched { return false, blot_error::Error.none; }
    return self_.recordValueAnchorIds(anchors, scratch.anchor_ids.items);
}
fn admitOperation<G>(self_: Importer&, g: G&, id: u32) -> bool, Error {
    let error = self_.operationScope(g, id);
    if error == blot_error::Error.out_of_memory { return false, error; }
    return error == blot_error::Error.none, blot_error::Error.none;
}
fn indexOperations(self_: Importer&) -> Error {
    if self_.operations_indexed { return blot_error::Error.none; }
    let __old:const Pools& =requiredPools(self_.old);
    let labels = unit_words.alloc_slice(__old.operations.len); for &label in labels { label = 0; }
    let scopes = operation_scope_runs.alloc_slice(labels.len); for &scope in scopes { scope = OperationScope.unchecked; }
    var symbols = TextMap {..};
    let error = self_.indexOperationLabels(labels, symbols); symbols.deinit();
    if error != blot_error::Error.none {
        if labels.len != 0 { unit_words.free_slice(labels); operation_scope_runs.free_slice(scopes); }
        return error;
    }
    self_.operation_labels = labels; self_.operation_scopes = scopes; self_.operations_indexed = true;
    return blot_error::Error.none;
}
fn indexOperationLabels(self_: const Importer&, labels: u32[:], symbols: TextMap&) -> Error {
    let __old:const Pools& =requiredPools(self_.old);
    for operation, index in __old.operations {
        if operation.key.len < 2 || operation.key[0] != 1 || operation.key[1] != 'P' { continue; }
        if symbols.contains(operation.key) { return blot_error::Error.declined; }
        symbols.insert(operation.key, index as u32);
    }
    if !__old.identity.present { return blot_error::Error.declined; }
    var entries: blot_backend_runtime_operations::Entry[>..<] = []; var bytes=blot_backend_optimizer_buffers::Bytes{};
    var keys: dictionary<u64,u32> = dictionary<u64,u32>{}; var relocations: blot_backend_runtime_operations::Relocation[>..<] = [];
    var scratch = blot_backend_runtime_operations::initProject(entries, bytes, keys, relocations, __old.identity.value.view());
    let view = __old.evaluator.evidence.view(); var failure = blot_error::Error.none;
    for label in 1..view.effects.operations.len {
        let candidate, error = scratch.intern(view, label as u32);
        if error == blot_error::Error.out_of_memory { failure = error; break; }
        if error != blot_error::Error.none { continue; }
        let index = symbols.get(scratch.key(scratch.entries[candidate - 1]));
        if index && labels[index] == 0 { labels[index] = label as u32; }
    }
    scratch.deinit();bytes.deinit();return failure;
}
fn operationScope<G>(self_: Importer&, g: G&, id: u32) -> Error {
    let bound = self_.bind(g); if bound != blot_error::Error.none { return bound; }
    let __old:const Pools& =requiredPools(self_.old);
    if id == 0 || id > __old.operations.len { return blot_error::Error.declined; }
    let indexed = self_.indexOperations(); if indexed != blot_error::Error.none { return indexed; }
    match self_.operation_scopes[id - 1] {
        admitted => { return blot_error::Error.none; },
        declined => { return blot_error::Error.declined; },
        unchecked => {},
    }
    let error = self_.qualifyOperation(g, id);
    if error != blot_error::Error.none {
        if error == blot_error::Error.declined { self_.operation_scopes[id - 1] = OperationScope.declined; }
        return error;
    }
    self_.operation_scopes[id - 1] = OperationScope.admitted; return blot_error::Error.none;
}
fn qualifyOperation<G>(self_: Importer&, g: G&, id: u32) -> Error {
    let __old:const Pools& =requiredPools(self_.old);
    let label = self_.operation_labels[id - 1]; if label == 0 { return blot_error::Error.declined; }
    let operation = __old.operations[id - 1]; let view = __old.evaluator.evidence.view(); let producer = view.effects.operations[label];
    let arguments, error = bounded(view.effects.arguments, producer.arguments.start, producer.arguments.len);
    if error != blot_error::Error.none { return error; }
    if producer.identity.unit == 0 {
        if producer.identity.decl != 1 || arguments.len != 0 || !operation.foreign { return blot_error::Error.declined; }
    } else {
        let mapped, failure = self_.nominal(producer.identity.unit, producer.identity.decl); if failure != blot_error::Error.none { return failure; }
        if operation.foreign { return blot_error::Error.declined; }
    }
    for argument in arguments { let mapped, failure = self_.semanticType(g, argument, 0); if failure != blot_error::Error.none { return failure; } }
    return blot_error::Error.none;
}

recursive fn principalType(self_: const Importer&, id: u32, depth: i64, remaining: i64&) -> Error {
    let __old:const Pools& =requiredPools(self_.old);
    if depth >= depth_limit || remaining == 0 || id == 0 || id >= __old.evaluator.evidence.nodes.len { return blot_error::Error.declined; }
    remaining--; let node = __old.evaluator.evidence.nodes[id];
    match node.tag {
        projection, scoped, forall, existential, bound, usage, absent, provider, state_provider, resolver, type_constructor, erased_proof => { return blot_error::Error.declined; },
        unit, boolean, unsigned32, floating32, never => { if node.a != 0 || node.b != 0 || node.c != 0 { return blot_error::Error.declined; } },
        array, list, cursor => { if node.b != 0 || node.c != 0 { return blot_error::Error.declined; } { let propagated_error = self_.principalType(node.a, depth + 1, remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } },
        function => {
            { let propagated_error = self_.principalType(node.a, depth + 1, remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.principalType(node.b, depth + 1, remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = self_.principalRow(node.c, depth + 1, remaining); if propagated_error != blot_error::Error.none { return propagated_error; } }
        },
        product, record, nominal => {
            if node.tag == blot_eval_type_evidence::Tag.nominal {
                if node.a == 0xffffffff || node.b == 0 { return blot_error::Error.declined; }
                let unit, error = self_.unit(node.a, true); if error != blot_error::Error.none { return error; }
                let decl, failure = self_.nominalDeclaration(node.b); if failure != blot_error::Error.none { return failure; }
                let current .= self_.units[unit - 1]; var found = false;
                for nominal in current.nominals {
                    if nominal.identity.decl == decl && (nominal.identity.unit == 0 || nominal.identity.unit == current.unit || nominal.identity.unit == self_.unit_map[node.a - 1]) { found = true; break; }
                }
                if !found { return blot_error::Error.declined; }
            } else if node.c != 0 { return blot_error::Error.declined; }
            let children, error = evidenceChildren(__old.evaluator.evidence.view(), id); if error != blot_error::Error.none { return error; }
            for child, index in children {
                if node.tag == blot_eval_type_evidence::Tag.record && index % 2 == 0 { let symbol, failure = self_.symbol(child); if failure != blot_error::Error.none { return failure; } }
                else { { let propagated_error = self_.principalType(child, depth + 1, remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } }
            }
            if node.tag == blot_eval_type_evidence::Tag.record { { let propagated_error = uniqueFields(children); if propagated_error != blot_error::Error.none { return propagated_error; } } }
        },
    }
    return blot_error::Error.none;
}
recursive fn principalRow(self_: const Importer&, id: u32, depth: i64, remaining: i64&) -> Error {
    let __old:const Pools& =requiredPools(self_.old); let source = __old.evaluator.evidence.effects.view();
    if depth >= depth_limit || remaining == 0 || id >= source.rows.len { return blot_error::Error.declined; }
    remaining--; let span = source.rows[id];
    let labels, error = bounded(source.labels, span.start, span.len); if error != blot_error::Error.none { return error; }
    if id == 0 && labels.len != 0 { return blot_error::Error.declined; }
    for label in labels {
        if label == 0 || label >= source.operations.len { return blot_error::Error.declined; }
        let operation = source.operations[label];
        if operation.instance.unit != 0 || operation.instance.decl != 0 || operation.identity.unit == 0xffffffff { return blot_error::Error.declined; }
        let arguments, failure = bounded(source.arguments, operation.arguments.start, operation.arguments.len); if failure != blot_error::Error.none { return failure; }
        if operation.identity.unit == 0 { if operation.identity.decl != 1 || arguments.len != 0 { return blot_error::Error.declined; } }
        else { let owner, invalid = self_.nominal(operation.identity.unit, operation.identity.decl); if invalid != blot_error::Error.none { return invalid; } }
        for argument in arguments { { let propagated_error = self_.principalType(argument, depth + 1, remaining); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    }
    return blot_error::Error.none;
}
fn validatePrincipalMappings(self_: const Importer&, owner: u32, types: const blot_eval_type_evidence::Mapping[:], rows: const blot_eval_type_evidence::RowMapping[:]) -> Error {
    let module, old_error = self_.oldModule(owner); if old_error != blot_error::Error.none { return old_error; } assert(module);
    let unit, error = self_.unit(owner, true); if error != blot_error::Error.none { return error; }
    let current .= self_.units[unit - 1]; var remaining: i64 = 1000000;
    for mapping, index in types {
        if mapping.variable == 0 || mapping.variable >= module.types.nodes.len || mapping.variable >= current.types.nodes.len || module.types.nodes[mapping.variable].tag != blot_check_types::Tag.variable || current.types.nodes[mapping.variable].tag != blot_check_types::Tag.variable { return blot_error::Error.declined; }
        for previous in types[..index] { if previous.variable == mapping.variable { return blot_error::Error.declined; } }
        { let propagated_error = self_.principalType(mapping.evidence, 0, remaining); if propagated_error != blot_error::Error.none { return propagated_error; } }
    }
    for mapping, index in rows {
        if mapping.variable >= module.types.effects.variable_count || mapping.variable >= current.types.effects.variable_count { return blot_error::Error.declined; }
        for previous in rows[..index] { if previous.variable == mapping.variable { return blot_error::Error.declined; } }
        { let propagated_error = self_.principalRow(mapping.evidence, 0, remaining); if propagated_error != blot_error::Error.none { return propagated_error; } }
    }
    return blot_error::Error.none;
}
fn principalEvidenceInto<G>(self_: Importer&, g: G&, imported: blot_eval_core_eval::SolvedEvidence&) -> Error {
    for &mapping in imported.types { let evidence, error = self_.semanticType(g, mapping.evidence, 0); if error != blot_error::Error.none { return error; } mapping.evidence = evidence; }
    for &mapping in imported.rows { let evidence, error = self_.row(g, Domain.semantic, mapping.evidence, 0); if error != blot_error::Error.none { return error; } mapping.evidence = evidence; }
    return blot_error::Error.none;
}
fn importPrincipalEvidence<G>(self_: Importer&, g: G&, owner: u32, types: const blot_eval_type_evidence::Mapping[:], rows: const blot_eval_type_evidence::RowMapping[:]) -> blot_support::Option<blot_eval_core_eval::SolvedEvidence>, Error {
    let no = blot_support::none<blot_eval_core_eval::SolvedEvidence>();
    let bound = self_.bind(g); if bound != blot_error::Error.none { return optionalImported(default<blot_eval_core_eval::SolvedEvidence>(), bound); }
    let validated = self_.validatePrincipalMappings(owner, types, rows);
    if validated != blot_error::Error.none { return optionalImported(default<blot_eval_core_eval::SolvedEvidence>(), validated); }
    var imported = blot_eval_core_eval::SolvedEvidence { blot_eval_core_eval::copySolvedTypes(types), blot_eval_core_eval::copySolvedRows(rows) , ..};
    let error = self_.principalEvidenceInto(g, imported);
    if error != blot_error::Error.none { imported.deinit(); return optionalImported(default<blot_eval_core_eval::SolvedEvidence>(), error); }
    return blot_support::some(imported), blot_error::Error.none;
}
fn importPrincipalInput<G>(self_: Importer&, g: G&, actual: u32) -> blot_support::Option<u32>, Error {
    let bound = self_.bind(g); if bound != blot_error::Error.none { return optionalImported(0 as u32, bound); }
    var remaining: i64 = 1000000; let checked = self_.principalType(actual, 0, remaining);
    if checked != blot_error::Error.none { return optionalImported(0 as u32, checked); }
    let __old:const Pools& =requiredPools(self_.old);
    if __old.evaluator.evidence.nodes[actual].tag != blot_eval_type_evidence::Tag.product { return blot_support::none<u32>(), blot_error::Error.none; }
    let value, error = self_.semanticType(g, actual, 0); return optionalImported(value, error);
}
fn importPrincipalCall<G>(self_: Importer&, g: G&, reference: blot_check_core::BindingRef, actual: u32) -> blot_support::Option<u32>, Error {
    let bound = self_.bind(g); if bound != blot_error::Error.none { return optionalImported(0 as u32, bound); }
    let previous, old_error = self_.oldModule(reference.unit); if old_error != blot_error::Error.none { return optionalImported(0 as u32, old_error); } assert(previous);
    let unit, invalid = self_.unit(reference.unit, true); if invalid != blot_error::Error.none { return optionalImported(0 as u32, invalid); }
    let current .= self_.units[unit - 1];
    if reference.binding == 0 || reference.binding >= previous.bindings.len || reference.binding >= current.bindings.len || previous.binding(reference.binding).kind != blot_reuse_principal_interface::Kind.global || current.binding(reference.binding).kind != blot_reuse_principal_interface::Kind.global || !previous.body(reference.binding) || !current.body(reference.binding) { return blot_support::none<u32>(), blot_error::Error.none; }
    var remaining: i64 = 1000000; let checked = self_.principalType(actual, 0, remaining);
    if checked != blot_error::Error.none { return optionalImported(0 as u32, checked); }
    let __old:const Pools& =requiredPools(self_.old);
    if __old.evaluator.evidence.nodes[actual].tag != blot_eval_type_evidence::Tag.function { return blot_support::none<u32>(), blot_error::Error.none; }
    let value, error = self_.semanticType(g, actual, 0); return optionalImported(value, error);
}
fn importSemanticSite<G>(self_: Importer&, g: G&, site: blot_backend_wasm::SemanticSite) -> blot_support::Option<blot_backend_wasm::SemanticSite>, Error {
    let value, error = self_.semanticSite(g, site); return optionalImported(value, error);
}

fn semanticSite<G>(self_: Importer&, g: G&, site: blot_backend_wasm::SemanticSite) -> blot_backend_wasm::SemanticSite, Error {
    { let import_error_1 = self_.bind(g); if import_error_1 != blot_error::Error.none { return default<blot_backend_wasm::SemanticSite>(), convert(import_error_1); } }
    if site.node == 0 || site.root == 0 { return default<blot_backend_wasm::SemanticSite>(), blot_error::Error.declined; }
    let unit, import_error_2 = self_.expressionUnit(site.unit, site.root); if import_error_2 != blot_error::Error.none { return default<blot_backend_wasm::SemanticSite>(), convert(import_error_2); }
    let source, import_error_3 = self_.oldModule(site.unit); if import_error_3 != blot_error::Error.none { return default<blot_backend_wasm::SemanticSite>(), convert(import_error_3); } assert(source);
    if site.node >= source.nodes.len || site.root >= source.nodes.len || site.node >= self_.units[unit - 1].nodes.len || site.root >= self_.units[unit - 1].nodes.len { return default<blot_backend_wasm::SemanticSite>(), blot_error::Error.declined; }
    if !self_.stable[site.unit - 1] {
        let key = ExpressionKey { site.unit, site.root , ..};
        let known = self_.expression_nodes.get(key);
        if known {if !selectedExpressionContains(known,site.node) {return default<blot_backend_wasm::SemanticSite>(),blot_error::Error.declined;}}
        else {
            let proved, import_error_4 = blot_reuse_declaration_projection::expressionNodes(source, self_.units[unit - 1], site.root); if import_error_4 != blot_error::Error.none { return default<blot_backend_wasm::SemanticSite>(), convert(import_error_4); }
            if !proved.present { return default<blot_backend_wasm::SemanticSite>(), blot_error::Error.declined; }
            self_.expression_nodes.insert(key, proved.value); if !selectedExpressionContains(proved.value,site.node) {return default<blot_backend_wasm::SemanticSite>(),blot_error::Error.declined;}
        }
    }
    var result = site; result.unit = unit;
    { let imported_5, import_error_5 = self_.mappingEvidence(g, site.unit, site.mappings, 0); if import_error_5 != blot_error::Error.none { return default<blot_backend_wasm::SemanticSite>(), convert(import_error_5); } result.mappings = imported_5; }
    { let imported_6, import_error_6 = self_.rowKey(g, site.unit, site.rows, 0); if import_error_6 != blot_error::Error.none { return default<blot_backend_wasm::SemanticSite>(), convert(import_error_6); } result.rows = imported_6; }
    return result, blot_error::Error.none;
}
reusable[] var solved_layouts: blot_backend_layout::Mapping[>..] = [];
reusable[] var solved_layout_rows: blot_backend_layout::RowMapping[>..] = [];
reusable[] var solved_templates: blot_reuse_substitution_keys::Entry[>..] = [];
fn deinit(self_: Solved&) {
    if self_.mappings.len != 0 { solved_layouts.free_slice(self_.mappings); }
    if self_.rows.len != 0 { solved_layout_rows.free_slice(self_.rows); }
    if self_.templates.len != 0 { solved_templates.free_slice(self_.templates); }
    self_ = Solved {..};
}
// Job tables retain typed ranges, so the source journal accompanies its header.
fn importSolved<G>(self_: Importer&, g: G&, job: const blot_reuse_code_artifacts::Job&, source: const blot_reuse_code_artifacts::Context&) -> blot_support::Option<Solved>, Error {
    let bound = self_.bind(g); if bound != blot_error::Error.none { return optionalImported(Solved {..}, bound); }
    if !job.solved || job.state != blot_reuse_code_artifacts::State.complete { return blot_support::none<Solved>(), blot_error::Error.none; }
    var owner: u32 = 0;
    match job.request {
        named key => { owner = key.key.target.unit; },
        closure key => { owner = key.key.unit; },
        _ => { return blot_support::none<Solved>(), blot_error::Error.none; },
    }
    let module, invalid = self_.oldModule(owner); if invalid != blot_error::Error.none { return optionalImported(Solved {..}, invalid); } assert(module);
    let mappings, mapping_error = bounded(source.mappings.items, job.mappings.start, job.mappings.len);
    if mapping_error != blot_error::Error.none { return optionalImported(Solved {..}, mapping_error); }
    let rows, row_error = bounded(source.rows.items, job.rows.start, job.rows.len);
    if row_error != blot_error::Error.none { return optionalImported(Solved {..}, row_error); }
    let templates, template_error = bounded(source.templates.items, job.templates.start, job.templates.len);
    if template_error != blot_error::Error.none { return optionalImported(Solved {..}, template_error); }
    var result = Solved { solved_layouts.alloc_slice(mappings.len), solved_layout_rows.alloc_slice(rows.len), solved_templates.alloc_slice(templates.len) , ..};
    let error = self_.importSolvedInto(g, module, mappings, rows, templates, result);
    if error != blot_error::Error.none { result.deinit(); return optionalImported(Solved {..}, error); }
    return blot_support::some(result), blot_error::Error.none;
}
fn importSolvedInto<G>(self_: Importer&, g: G&, module: const Module&, mappings: const blot_backend_layout::Mapping[:], rows: const blot_backend_layout::RowMapping[:], templates: const blot_reuse_substitution_keys::Entry[:], result: Solved&) -> Error {
    for from, index in mappings {
        if from.variable == 0 || from.variable >= module.types.nodes.len { return blot_error::Error.declined; }
        for prior in mappings[..index] { if prior.variable == from.variable { return blot_error::Error.declined; } }
        let layout, error = self_.closedShape(g, from.layout); if error != blot_error::Error.none { return error; }
        result.mappings[index] = blot_backend_layout::Mapping { variable: from.variable, layout: layout, instance: blot_check_types::NominalIdentity { 0, 0 , ..} , ..};
    }
    for from, index in rows {
        if from.variable >= module.types.effects.variable_count || from.row == blot_backend_layout::unknown_row { return blot_error::Error.declined; }
        for prior in rows[..index] { if prior.variable == from.variable { return blot_error::Error.declined; } }
        let row, error = self_.row(g, Domain.layout, from.row, 0); if error != blot_error::Error.none { return error; }
        result.rows[index] = blot_backend_layout::RowMapping { from.variable, row , ..};
        let known, failure = self_.knowledge.knownRow(g.representations.store, row);
        if failure != blot_error::Error.none { return failure; } if !known { return blot_error::Error.declined; }
    }
    for from, index in templates {
        if from.variable == 0 || from.variable >= module.bindings.len { return blot_error::Error.declined; }
        for prior in templates[..index] { if prior.variable == from.variable { return blot_error::Error.declined; } }
        let value, error = self_.capture(g, from.value, 0); if error != blot_error::Error.none { return error; }
        result.templates[index] = blot_reuse_substitution_keys::Entry { from.variable, value , ..};
    }
    return blot_error::Error.none;
}

fn selectedExpressionContains(nodes:const u32[:],node:u32)->bool {var low:i64=0;var high=nodes.len;while low<high {let middle=low+(high-low)/2;if nodes[middle]<node {low=middle+1;}else {high=middle;}}return low!=nodes.len && nodes[low]==node;}
