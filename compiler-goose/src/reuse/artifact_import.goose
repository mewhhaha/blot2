// Imported IDs are meaningful only in one exact pinned source/destination pair.
namespace blot_reuse_artifact_import;
import std;
import dictionary;
import check.core;
import check.types;
import check.check;
import eval.core_eval;
import eval.type_evidence;
import eval.semantic_evidence_import;
import backend.layout;
import backend.runtime_identity;
import backend.runtime_operations;
import backend.wasm;
import reuse.code_artifacts;
import reuse.code_body_validity;
import reuse.principal_reuse_gate;
import reuse.source_value_template;
import reuse.declaration_dependencies;
import reuse.declaration_projection;
import reuse.substitution_keys;
import reuse.artifact_import_knowledge;
import support.error;
import support.option;
import support.native;
import support.structural;
import support.pooled_map;
import support.pooled_buffer;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type Pools = blot_reuse_code_artifacts::Pools;
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
struct OwnerCensus { principals: Census = Census {}, queries: Census = Census {}, fragments: Census = Census {} }
struct Solved { mappings: blot_backend_layout::Mapping[:] = [], rows: blot_backend_layout::RowMapping[:] = [], templates: blot_reuse_substitution_keys::Entry[:] = [] }
struct IdentityMetadata { bytes: u8[:] = [], symbols: blot_backend_runtime_identity::Name[:] = [], owners: blot_backend_runtime_identity::Name[:] = [] }
reusable[] var identity_bytes: u8[>..] = [];
reusable[] var identity_names: blot_backend_runtime_identity::Name[>..] = [];
reusable[] var unit_words: u32[>..] = [];
reusable[] var stable_flags: bool[>..] = [];
reusable[] var operation_scope_runs: OperationScope[>..] = [];
fn view(self: IdentityMetadata) -> View { return View { self.bytes, self.symbols, self.owners }; }
fn copyIdentity(source: View) -> IdentityMetadata {
    let bytes = identity_bytes.alloc_slice(source.bytes.len); let symbols = identity_names.alloc_slice(source.symbols.len); let owners = identity_names.alloc_slice(source.owners.len);
    for byte, index in source.bytes { bytes[index] = byte; } for name, index in source.symbols { symbols[index] = name; } for owner, index in source.owners { owners[index] = owner; }
    return IdentityMetadata { bytes, symbols, owners };
}
fn deinit(self: IdentityMetadata&) { if self.bytes.len != 0 { identity_bytes.free_slice(self.bytes); } if self.symbols.len != 0 { identity_names.free_slice(self.symbols); } if self.owners.len != 0 { identity_names.free_slice(self.owners); } self = IdentityMetadata {}; }

struct WordMap { table: blot_support_pooled_map::Map<u32,u32> = blot_support_pooled_map::Map<u32,u32> {} }
reusable[] var wordmap_slots: dictionary_slot<u32,u32>[>..] = [];
fn get(self: const WordMap&, key: u32) -> u32? { return blot_support_pooled_map::get(self.table, key); }
fn contains(self: const WordMap&, key: u32) -> bool { return blot_support_pooled_map::contains(self.table, key); }
fn insert(self: WordMap&, key: u32, value: u32) { blot_support_pooled_map::insert(self.table, key, value, wordmap_slots); }
fn deinit(self: WordMap&) { blot_support_pooled_map::deinit(self.table, wordmap_slots); }

struct EvidenceMap { table: blot_support_pooled_map::Map<EvidenceKey,u32> = blot_support_pooled_map::Map<EvidenceKey,u32> {} }
reusable[] var evidencemap_slots: dictionary_slot<EvidenceKey,u32>[>..] = [];
fn get(self: const EvidenceMap&, key: EvidenceKey) -> u32? { return blot_support_pooled_map::get(self.table, key); }
fn contains(self: const EvidenceMap&, key: EvidenceKey) -> bool { return blot_support_pooled_map::contains(self.table, key); }
fn insert(self: EvidenceMap&, key: EvidenceKey, value: u32) { blot_support_pooled_map::insert(self.table, key, value, evidencemap_slots); }
fn deinit(self: EvidenceMap&) { blot_support_pooled_map::deinit(self.table, evidencemap_slots); }

struct RowMap { table: blot_support_pooled_map::Map<RowKey,u32> = blot_support_pooled_map::Map<RowKey,u32> {} }
reusable[] var rowmap_slots: dictionary_slot<RowKey,u32>[>..] = [];
fn get(self: const RowMap&, key: RowKey) -> u32? { return blot_support_pooled_map::get(self.table, key); }
fn contains(self: const RowMap&, key: RowKey) -> bool { return blot_support_pooled_map::contains(self.table, key); }
fn insert(self: RowMap&, key: RowKey, value: u32) { blot_support_pooled_map::insert(self.table, key, value, rowmap_slots); }
fn deinit(self: RowMap&) { blot_support_pooled_map::deinit(self.table, rowmap_slots); }

struct SubstitutionMap { table: blot_support_pooled_map::Map<SubstitutionKey,u32> = blot_support_pooled_map::Map<SubstitutionKey,u32> {} }
reusable[] var substitutionmap_slots: dictionary_slot<SubstitutionKey,u32>[>..] = [];
fn get(self: const SubstitutionMap&, key: SubstitutionKey) -> u32? { return blot_support_pooled_map::get(self.table, key); }
fn contains(self: const SubstitutionMap&, key: SubstitutionKey) -> bool { return blot_support_pooled_map::contains(self.table, key); }
fn insert(self: SubstitutionMap&, key: SubstitutionKey, value: u32) { blot_support_pooled_map::insert(self.table, key, value, substitutionmap_slots); }
fn deinit(self: SubstitutionMap&) { blot_support_pooled_map::deinit(self.table, substitutionmap_slots); }

struct ExpressionMap { table: blot_support_pooled_map::Map<ExpressionKey,const u32[:]> = blot_support_pooled_map::Map<ExpressionKey,const u32[:]> {} }
reusable[] var expressionmap_slots: dictionary_slot<ExpressionKey,const u32[:]>[>..] = [];
fn get(self: const ExpressionMap&, key: ExpressionKey) -> const u32[:]? { return blot_support_pooled_map::get(self.table, key); }
fn contains(self: const ExpressionMap&, key: ExpressionKey) -> bool { return blot_support_pooled_map::contains(self.table, key); }
fn insert(self: ExpressionMap&, key: ExpressionKey, value: const u32[:]) { blot_support_pooled_map::insert(self.table, key, value, expressionmap_slots); }
fn deinit(self: ExpressionMap&) { blot_support_pooled_map::deinit(self.table, expressionmap_slots); }

struct PlanMap { table: blot_support_pooled_map::Map<u32,blot_reuse_source_value_template::Plan> = blot_support_pooled_map::Map<u32,blot_reuse_source_value_template::Plan> {} }
reusable[] var planmap_slots: dictionary_slot<u32,blot_reuse_source_value_template::Plan>[>..] = [];
fn get(self: const PlanMap&, key: u32) -> blot_reuse_source_value_template::Plan? { return blot_support_pooled_map::get(self.table, key); }
fn contains(self: const PlanMap&, key: u32) -> bool { return blot_support_pooled_map::contains(self.table, key); }
fn insert(self: PlanMap&, key: u32, value: blot_reuse_source_value_template::Plan) { blot_support_pooled_map::insert(self.table, key, value, planmap_slots); }
fn deinit(self: PlanMap&) { blot_support_pooled_map::deinit(self.table, planmap_slots); }
struct Importer {
    allocation_owner: u64 = 0, census: Census = Census {}, old: const Pools? = null, units: const Module[:] = [],
    names: blot_support::Option<IdentityMetadata>, unit_map: u32[:] = [], symbol_map: u32[:] = [], stable: bool[:] = [],
    code_gate: blot_support::Option<blot_reuse_code_body_validity::Gate>, semantic_catalogs: bool = false,
    closed_evidence: blot_support::Option<blot_eval_semantic_evidence_import::PooledImporter>, enabled: bool = false, generator_owner: u64 = 0,
    expression_nodes: ExpressionMap = ExpressionMap {}, layouts: WordMap = WordMap {}, semantic: EvidenceMap = EvidenceMap {},
    rows: RowMap = RowMap {}, template_keys: SubstitutionMap = SubstitutionMap {}, row_keys: SubstitutionMap = SubstitutionMap {},
    captures: WordMap = WordMap {}, value_anchors: WordMap = WordMap {},
    static_scratch: blot_support::Option<blot_reuse_source_value_template::QueryScratch>, static_plans: PlanMap = PlanMap {}, static_plan_nodes: i64 = 0,
    operation_labels: u32[:] = [], operation_scopes: OperationScope[:] = [], operations_indexed: bool = false,
    knowledge: Knowledge = Knowledge {},
}
fn init(allocation_owner: u64, old: const Pools&, units: const Module[:], names: blot_support::Option<View>, cached_units: i64) -> Importer, Error { return initWithStamps(allocation_owner, old, units, names, cached_units, null); }
fn initWithStamps(allocation_owner: u64, old: const Pools&, units: const Module[:], names: blot_support::Option<View>, cached_units: i64, stamps: blot_reuse_code_artifacts::ModuleStamps?) -> Importer, Error {
    let unit_map = unit_words.alloc_slice(old.modules.len); let stable = stable_flags.alloc_slice(old.modules.len);
    var symbol_count: i64 = 0; if old.identity.present { symbol_count = old.identity.value.symbols.len; } let symbol_map = unit_words.alloc_slice(symbol_count);
    for &word in unit_map { word = 0; } for &flag in stable { flag = false; } for &word in symbol_map { word = 0; }
    var result = Importer { allocation_owner: allocation_owner, old: old, units: units, unit_map: unit_map, symbol_map: symbol_map, stable: stable };
    let error = result.initialize(names, cached_units, stamps); if error != Error.none { result.deinit(); return Importer {}, error; } return result, Error.none;
}
fn initialize(self: Importer&, names: blot_support::Option<View>, cached_units: i64, stamps: blot_reuse_code_artifacts::ModuleStamps?) -> Error {
    assert(self.old); let old .= self.old;
    if !old.project_identity || !names.present || !old.identity.present || cached_units > self.units.len { return Error.none; }
    self.names = blot_support::some(copyIdentity(names.value)); let current = self.names.value.view(); let old_names = old.identity.value.view();
    if current.owners.len != self.units.len || old_names.owners.len != old.modules.len || current.symbols.len == 0 || old_names.symbols.len == 0 { return Error.none; }
    var producers: dictionary<const u8[:],u32> = default<dictionary<const u8[:],u32>>();
    for module, index in self.units {
        if module.unit != 0 && module.unit != index + 1 { return Error.none; } let path = current.owner((index + 1) as u32);
        if !path.present || path.value.len == 0 || !blot_backend_runtime_identity::validUtf8(path.value) { return Error.none; }
        for byte in path.value { if byte == 0 { return Error.none; } } if producers.contains(path.value) { return Error.none; } producers.insert(path.value, (index + 1) as u32);
    }
    var spellings: dictionary<const u8[:],u32> = default<dictionary<const u8[:],u32>>();
    for index in 1..current.symbols.len { let spelling = current.symbol(index as u32); if !spelling.present || spelling.value.len == 0 || !blot_backend_runtime_identity::validUtf8(spelling.value) || spellings.contains(spelling.value) { return Error.none; } spellings.insert(spelling.value, index as u32); }
    for pin, index in old.modules {
        if pin.unit != index + 1 || pin.canonical_path.len == 0 || (pin.module.unit != 0 && pin.module.unit != pin.unit) { return Error.none; }
        let path = old_names.owner(pin.unit); if !path.present || path.value != pin.canonical_path { return Error.none; } for previous in old.modules[..index] { if previous.canonical_path == path.value { return Error.none; } }
        let mapped = producers.get(path.value); if mapped { self.unit_map[index] = mapped; }
    }
    for index in 1..self.symbol_map.len { let spelling = old_names.symbol(index as u32); if !spelling.present || spelling.value.len == 0 { return Error.none; } let mapped = spellings.get(spelling.value); if mapped { self.symbol_map[index] = mapped; } }
    self.enabled = true;
    for &pin, index in old.modules {
        let mapped = self.unit_map[index]; if mapped == 0 || mapped > cached_units { continue; }
        let intact, error = blot_reuse_code_artifacts::pinIntact(pin, stamps); if error != Error.none { return error; } if !intact { continue; }
        let equal, failure = self.coreEqual(pin.module, self.units[mapped - 1]); if failure == Error.out_of_memory { return failure; } self.stable[index] = failure == Error.none && equal;
    }
    let gate, error = blot_reuse_code_body_validity::init(self.allocation_owner, old, self.units, names, stamps); if error != Error.none { return error; } self.code_gate = blot_support::some(gate); return Error.none;
}
fn initCheckedQuery(allocation_owner: u64, old: const Pools&, units: const Module[:], checked: const Gate&) -> blot_support::Option<Importer>, Error {
    if allocation_owner == 0 || checked.allocation_owner != allocation_owner { return blot_support::none<Importer>(), Error.none; } return initIndependentQuery(allocation_owner, old, units, checked);
}
fn initIndependentQuery(allocation_owner: u64, old: const Pools&, units: const Module[:], checked: const Gate&) -> blot_support::Option<Importer>, Error {
    let no = blot_support::none<Importer>();
    if !checked.enabled || checked.source_pools .!= old || !blot_support::same_slice_identity(checked.units, units) || old.modules.len != units.len || checked.structural_units.len != units.len || !old.project_identity || !old.identity.present { return no, Error.none; }
    let names = old.identity.value.view(); if names.owners.len != units.len || names.symbols.len == 0 || names.symbols.len > 0xffffffff || units.len >= 0xffffffff { return no, Error.none; }
    let unit_map = unit_words.alloc_slice(units.len); for &word, index in unit_map { word = (index + 1) as u32; }
    let symbol_map = unit_words.alloc_slice(names.symbols.len); for &word, index in symbol_map { word = index as u32; }
    let stable = stable_flags.alloc_slice(units.len); for &flag, index in stable { flag = checked.structural_units[index]; }
    return blot_support::some(Importer { allocation_owner: allocation_owner, old: old, units: units, names: blot_support::some(copyIdentity(names)), unit_map: unit_map, symbol_map: symbol_map, stable: stable, semantic_catalogs: true, enabled: true }), Error.none;
}
fn deinit(self: Importer&) {
    if self.closed_evidence.present { self.closed_evidence.value.deinit(); self.closed_evidence.present = false; }
    for slot in self.expression_nodes.table.slots { if slot.tag != 0 { blot_reuse_declaration_projection::release(slot.val); } } self.expression_nodes.deinit();
    self.layouts.deinit(); self.semantic.deinit(); self.rows.deinit(); self.template_keys.deinit(); self.row_keys.deinit(); self.captures.deinit(); self.value_anchors.deinit();
    for &slot in self.static_plans.table.slots { if slot.tag != 0 { slot.val.deinit(); } } self.static_plans.deinit();
    if self.static_scratch.present { self.static_scratch.value.deinit(); self.static_scratch.present = false; } self.knowledge.deinit();
    if self.operation_labels.len != 0 { unit_words.free_slice(self.operation_labels); } if self.operation_scopes.len != 0 { operation_scope_runs.free_slice(self.operation_scopes); }
    if self.names.present { self.names.value.deinit(); self.names.present = false; }
    if self.unit_map.len != 0 { unit_words.free_slice(self.unit_map); } if self.symbol_map.len != 0 { unit_words.free_slice(self.symbol_map); }
    if self.code_gate.present { self.code_gate.value.deinit(); self.code_gate.present = false; } if self.stable.len != 0 { stable_flags.free_slice(self.stable); }
    self = Importer {};
}
fn bind<G>(self: Importer&, generator: G&) -> Error {
    if !self.enabled || generator.owner_id == 0 { return Error.declined; }
    if self.generator_owner != 0 { if self.generator_owner != generator.owner_id { return Error.declined; } }
    else { let error = self.checkFields(generator); if error != Error.none { return error; } self.generator_owner = generator.owner_id; } return Error.none;
}
fn unit(self: const Importer&, old_unit: u32, require_stable: bool) -> u32, Error { if old_unit == 0 || old_unit > self.unit_map.len { return 0, Error.declined; } let mapped = self.unit_map[old_unit - 1]; if mapped == 0 || (require_stable && !self.stable[old_unit - 1]) { return 0, Error.declined; } return mapped, Error.none; }
fn symbol(self: const Importer&, old_symbol: u32) -> u32, Error { if old_symbol == 0 || old_symbol >= self.symbol_map.len || self.symbol_map[old_symbol] == 0 { return 0, Error.declined; } return self.symbol_map[old_symbol], Error.none; }
fn nominalDeclaration(self: const Importer&, decl: u32) -> u32, Error { if decl & blot_check_types::opaque_name_bit != 0 { let value, error = self.symbol(decl & ~blot_check_types::opaque_name_bit); return value | blot_check_types::opaque_name_bit, error; } return decl, Error.none; }
fn admitsBody(self: const Importer&, value: blot_check_core::BindingRef) -> bool { if value.unit == 0 || value.unit > self.unit_map.len { return false; } if self.stable[value.unit - 1] { return true; } if !self.code_gate.present { return false; } return self.code_gate.value.body(blot_check_core::BindingRef { self.unit_map[value.unit - 1], value.binding }); }
fn typeUnit(self: const Importer&, source: u32) -> u32, Error { let exact_catalog = self.code_gate.present && self.code_gate.value.catalog(source); return self.unit(source, !exact_catalog); }
fn nominal(self: const Importer&, old_unit: u32, decl: u32) -> u32, Error { return self.nominalInDomain(old_unit, decl, true); }
fn semanticNominal(self: const Importer&, old_unit: u32, decl: u32) -> u32, Error { return self.nominalInDomain(old_unit, decl, !self.semantic_catalogs); }
fn nominalInDomain(self: const Importer&, old_unit: u32, decl: u32, require_stable: bool) -> u32, Error {
    if decl == 0 { return 0, Error.declined; } if old_unit == 0xffffffff { if decl > 6 { return 0, Error.declined; } return old_unit, Error.none; }
    var mapped: u32 = 0; var failure = Error.none;
    if require_stable { let value, error = self.typeUnit(old_unit); mapped = value; failure = error; } else { let value, error = self.unit(old_unit, false); mapped = value; failure = error; }
    if failure != Error.none { return 0, failure; } let module = self.units[mapped - 1]; let declaration, error = self.nominalDeclaration(decl); if error != Error.none { return 0, error; }
    for value in module.nominals { if value.identity.decl == declaration && (value.identity.unit == 0 || value.identity.unit == mapped) { return mapped, Error.none; } }
    for value in module.types.operations { if value.identity.decl == decl && value.identity.unit == mapped { return mapped, Error.none; } } for value in module.operation_values { if value.identity.decl == decl && value.identity.unit == mapped { return mapped, Error.none; } } return 0, Error.declined;
}
