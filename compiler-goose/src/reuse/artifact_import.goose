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
struct Solved { mappings: blot_backend_layout::Mapping[:] = [], rows: blot_backend_layout::RowMapping[:] = [], templates: blot_reuse_substitution_keys::Entry[:] = [] }
struct IdentityMetadata { bytes: u8[:] = [], symbols: blot_backend_runtime_identity::Name[:] = [], owners: blot_backend_runtime_identity::Name[:] = [] }
reusable[] var identity_bytes: u8[>..] = [];
reusable[] var identity_names: blot_backend_runtime_identity::Name[>..] = [];
reusable[] var unit_words: u32[>..] = [];
reusable[] var stable_flags: bool[>..] = [];
reusable[] var operation_scope_runs: OperationScope[>..] = [];
fn view(self: IdentityMetadata) -> View { return View { self.bytes, self.symbols, self.owners , ..}; }
fn copyIdentity(source: View) -> IdentityMetadata {
    let bytes = identity_bytes.alloc_slice(source.bytes.len); let symbols = identity_names.alloc_slice(source.symbols.len); let owners = identity_names.alloc_slice(source.owners.len);
    for byte, index in source.bytes { bytes[index] = byte; } for name, index in source.symbols { symbols[index] = name; } for owner, index in source.owners { owners[index] = owner; }
    return IdentityMetadata { bytes, symbols, owners , ..};
}
fn deinit(self: IdentityMetadata&) { if self.bytes.len != 0 { identity_bytes.free_slice(self.bytes); } if self.symbols.len != 0 { identity_names.free_slice(self.symbols); } if self.owners.len != 0 { identity_names.free_slice(self.owners); } self = IdentityMetadata {..}; }

struct WordMap { table: blot_support_pooled_map::Map<u32,u32> = blot_support_pooled_map::Map<u32,u32> {..} }
reusable[] var wordmap_slots: dictionary_slot<u32,u32>[>..] = [];
fn get(self: const WordMap&, key: u32) -> u32? { return blot_support_pooled_map::get(self.table, key); }
fn contains(self: const WordMap&, key: u32) -> bool { return blot_support_pooled_map::contains(self.table, key); }
fn insert(self: WordMap&, key: u32, value: u32) { blot_support_pooled_map::insert(self.table, key, value, wordmap_slots); }
fn deinit(self: WordMap&) { blot_support_pooled_map::deinit(self.table, wordmap_slots); }

struct EvidenceMap { table: blot_support_pooled_map::Map<EvidenceKey,u32> = blot_support_pooled_map::Map<EvidenceKey,u32> {..} }
reusable[] var evidencemap_slots: dictionary_slot<EvidenceKey,u32>[>..] = [];
fn get(self: const EvidenceMap&, key: EvidenceKey) -> u32? { return blot_support_pooled_map::get(self.table, key); }
fn contains(self: const EvidenceMap&, key: EvidenceKey) -> bool { return blot_support_pooled_map::contains(self.table, key); }
fn insert(self: EvidenceMap&, key: EvidenceKey, value: u32) { blot_support_pooled_map::insert(self.table, key, value, evidencemap_slots); }
fn deinit(self: EvidenceMap&) { blot_support_pooled_map::deinit(self.table, evidencemap_slots); }

struct RowMap { table: blot_support_pooled_map::Map<RowKey,u32> = blot_support_pooled_map::Map<RowKey,u32> {..} }
reusable[] var rowmap_slots: dictionary_slot<RowKey,u32>[>..] = [];
fn get(self: const RowMap&, key: RowKey) -> u32? { return blot_support_pooled_map::get(self.table, key); }
fn contains(self: const RowMap&, key: RowKey) -> bool { return blot_support_pooled_map::contains(self.table, key); }
fn insert(self: RowMap&, key: RowKey, value: u32) { blot_support_pooled_map::insert(self.table, key, value, rowmap_slots); }
fn deinit(self: RowMap&) { blot_support_pooled_map::deinit(self.table, rowmap_slots); }

struct SubstitutionMap { table: blot_support_pooled_map::Map<SubstitutionKey,u32> = blot_support_pooled_map::Map<SubstitutionKey,u32> {..} }
reusable[] var substitutionmap_slots: dictionary_slot<SubstitutionKey,u32>[>..] = [];
fn get(self: const SubstitutionMap&, key: SubstitutionKey) -> u32? { return blot_support_pooled_map::get(self.table, key); }
fn contains(self: const SubstitutionMap&, key: SubstitutionKey) -> bool { return blot_support_pooled_map::contains(self.table, key); }
fn insert(self: SubstitutionMap&, key: SubstitutionKey, value: u32) { blot_support_pooled_map::insert(self.table, key, value, substitutionmap_slots); }
fn deinit(self: SubstitutionMap&) { blot_support_pooled_map::deinit(self.table, substitutionmap_slots); }

struct ExpressionMap { table: blot_support_pooled_map::Map<ExpressionKey,const u32[:]> = blot_support_pooled_map::Map<ExpressionKey,const u32[:]> {..} }
reusable[] var expressionmap_slots: dictionary_slot<ExpressionKey,const u32[:]>[>..] = [];
fn get(self: const ExpressionMap&, key: ExpressionKey) -> const u32[:]? { return blot_support_pooled_map::get(self.table, key); }
fn contains(self: const ExpressionMap&, key: ExpressionKey) -> bool { return blot_support_pooled_map::contains(self.table, key); }
fn insert(self: ExpressionMap&, key: ExpressionKey, value: const u32[:]) { blot_support_pooled_map::insert(self.table, key, value, expressionmap_slots); }
fn deinit(self: ExpressionMap&) { blot_support_pooled_map::deinit(self.table, expressionmap_slots); }

struct PlanMap { table: blot_support_pooled_map::Map<u32,blot_reuse_source_value_template::Plan> = blot_support_pooled_map::Map<u32,blot_reuse_source_value_template::Plan> {..} }
reusable[] var planmap_slots: dictionary_slot<u32,blot_reuse_source_value_template::Plan>[>..] = [];
fn get(self: const PlanMap&, key: u32) -> blot_reuse_source_value_template::Plan? { return blot_support_pooled_map::get(self.table, key); }
fn contains(self: const PlanMap&, key: u32) -> bool { return blot_support_pooled_map::contains(self.table, key); }
fn insert(self: PlanMap&, key: u32, value: blot_reuse_source_value_template::Plan) { blot_support_pooled_map::insert(self.table, key, value, planmap_slots); }
fn deinit(self: PlanMap&) { blot_support_pooled_map::deinit(self.table, planmap_slots); }
struct TextMap { table: blot_support_pooled_map::Map<const u8[:],u32> = blot_support_pooled_map::Map<const u8[:],u32> {..} }
reusable[] var textmap_slots: dictionary_slot<const u8[:],u32>[>..] = [];
fn get(self: const TextMap&, key: const u8[:]) -> u32? { return blot_support_pooled_map::get(self.table, key); }
fn contains(self: const TextMap&, key: const u8[:]) -> bool { return blot_support_pooled_map::contains(self.table, key); }
fn insert(self: TextMap&, key: const u8[:], value: u32) { blot_support_pooled_map::insert(self.table, key, value, textmap_slots); }
fn deinit(self: TextMap&) { blot_support_pooled_map::deinit(self.table, textmap_slots); }
struct Importer {
    allocation_owner: u64 = 0, census: Census = Census {..}, old: const Pools? = null, units: const Module[:] = [],
    names: blot_support::Option<IdentityMetadata>, unit_map: u32[:] = [], symbol_map: u32[:] = [], stable: bool[:] = [],
    code_gate: blot_support::Option<blot_reuse_code_body_validity::Gate>, semantic_catalogs: bool = false,
    closed_evidence: blot_support::Option<blot_eval_semantic_evidence_import::PooledImporter>, enabled: bool = false, generator_owner: u64 = 0,
    expression_nodes: ExpressionMap = ExpressionMap {..}, layouts: WordMap = WordMap {..}, semantic: EvidenceMap = EvidenceMap {..},
    rows: RowMap = RowMap {..}, template_keys: SubstitutionMap = SubstitutionMap {..}, row_keys: SubstitutionMap = SubstitutionMap {..},
    captures: WordMap = WordMap {..}, value_anchors: WordMap = WordMap {..},
    static_scratch: blot_support::Option<blot_reuse_source_value_template::QueryScratch>, static_plans: PlanMap = PlanMap {..}, static_plan_nodes: i64 = 0,
    operation_labels: u32[:] = [], operation_scopes: OperationScope[:] = [], operations_indexed: bool = false,
    knowledge: Knowledge = Knowledge {..},
}
fn init(allocation_owner: u64, old: const Pools&, units: const Module[:], names: blot_support::Option<View>, cached_units: i64) -> Importer, Error { return initWithStamps(allocation_owner, old, units, names, cached_units, null); }
fn initWithStamps(allocation_owner: u64, old: const Pools&, units: const Module[:], names: blot_support::Option<View>, cached_units: i64, stamps: blot_reuse_code_artifacts::ModuleStamps?) -> Importer, Error {
    let unit_map = unit_words.alloc_slice(old.modules.len); let stable = stable_flags.alloc_slice(old.modules.len);
    var symbol_count: i64 = 0; if old.identity.present { symbol_count = old.identity.value.symbols.len; } let symbol_map = unit_words.alloc_slice(symbol_count);
    for &word in unit_map { word = 0; } for &flag in stable { flag = false; } for &word in symbol_map { word = 0; }
    var result = Importer { allocation_owner: allocation_owner, old: old, units: units, unit_map: unit_map, symbol_map: symbol_map, stable: stable , ..};
    let error = result.initialize(names, cached_units, stamps); if error != Error.none { result.deinit(); return Importer {..}, error; } return result, Error.none;
}
fn initialize(self: Importer&, names: blot_support::Option<View>, cached_units: i64, stamps: blot_reuse_code_artifacts::ModuleStamps?) -> Error {
    var producers = TextMap {..}; var spellings = TextMap {..};
    let error = self.initializeMaps(names, cached_units, stamps, producers, spellings);
    producers.deinit(); spellings.deinit(); return error;
}
fn initializeMaps(self: Importer&, names: blot_support::Option<View>, cached_units: i64, stamps: blot_reuse_code_artifacts::ModuleStamps?, producers: TextMap&, spellings: TextMap&) -> Error {
    assert(self.old); let old .= self.old;
    if !old.project_identity || !names.present || !old.identity.present || cached_units > self.units.len { return Error.none; }
    self.names = blot_support::some(copyIdentity(names.value)); let current = self.names.value.view(); let old_names = old.identity.value.view();
    if current.owners.len != self.units.len || old_names.owners.len != old.modules.len || current.symbols.len == 0 || old_names.symbols.len == 0 { return Error.none; }
    for module, index in self.units {
        if module.unit != 0 && module.unit != index + 1 { return Error.none; } let path = current.owner((index + 1) as u32);
        if !path.present || path.value.len == 0 || !blot_backend_runtime_identity::validUtf8(path.value) { return Error.none; }
        for byte in path.value { if byte == 0 { return Error.none; } } if producers.contains(path.value) { return Error.none; } producers.insert(path.value, (index + 1) as u32);
    }
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
    return blot_support::some(Importer { allocation_owner: allocation_owner, old: old, units: units, names: blot_support::some(copyIdentity(names)), unit_map: unit_map, symbol_map: symbol_map, stable: stable, semantic_catalogs: true, enabled: true , ..}), Error.none;
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
    self = Importer {..};
}
fn bind<G>(self: Importer&, generator: G&) -> Error {
    if !self.enabled || generator.owner_id == 0 { return Error.declined; }
    if self.generator_owner != 0 { if self.generator_owner != generator.owner_id { return Error.declined; } }
    else { let error = self.checkFields(generator); if error != Error.none { return error; } self.generator_owner = generator.owner_id; } return Error.none;
}
fn unit(self: const Importer&, old_unit: u32, require_stable: bool) -> u32, Error { if old_unit == 0 || old_unit > self.unit_map.len { return 0, Error.declined; } let mapped = self.unit_map[old_unit - 1]; if mapped == 0 || (require_stable && !self.stable[old_unit - 1]) { return 0, Error.declined; } return mapped, Error.none; }
fn symbol(self: const Importer&, old_symbol: u32) -> u32, Error { if old_symbol == 0 || old_symbol >= self.symbol_map.len || self.symbol_map[old_symbol] == 0 { return 0, Error.declined; } return self.symbol_map[old_symbol], Error.none; }
fn nominalDeclaration(self: const Importer&, decl: u32) -> u32, Error { if decl & blot_check_types::opaque_name_bit != 0 { let value, error = self.symbol(decl & ~blot_check_types::opaque_name_bit); return value | blot_check_types::opaque_name_bit, error; } return decl, Error.none; }
fn admitsBody(self: const Importer&, value: blot_check_core::BindingRef) -> bool { if value.unit == 0 || value.unit > self.unit_map.len { return false; } if self.stable[value.unit - 1] { return true; } if !self.code_gate.present { return false; } return self.code_gate.value.body(blot_check_core::BindingRef { self.unit_map[value.unit - 1], value.binding , ..}); }
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

// Bounded transport never treats a numeric old ID as current-owner authority.
fn convert(error: Error) -> Error {
    if error == Error.none || error == Error.out_of_memory { return error; }
    return Error.declined;
}
fn bounded<T>(values: const T[:], start: u32, len: u32) -> const T[:], Error {
    if start > values.len || len > values.len - start { return [], Error.declined; }
    return values[start..start + len], Error.none;
}
fn uniqueFields(fields: const u32[:]) -> Error {
    if fields.len % 2 != 0 { return Error.declined; }
    for index in 0..fields.len / 2 {
        let name = fields[index * 2];
        if name == 0 { return Error.declined; }
        for previous in 0..index { if fields[previous * 2] == name { return Error.declined; } }
    }
    return Error.none;
}
fn shapeChildren(source: const blot_reuse_code_artifacts::Layouts&, id: u32) -> const u32[:], Error {
    let node = source.nodes[id];
    if node.tag == LayoutTag.product { return bounded(source.extra, node.a, node.b); }
    if node.tag == LayoutTag.record {
        if node.b > 0x7fffffff { return [], Error.declined; }
        return bounded(source.extra, node.a, node.b * 2);
    }
    if node.tag == LayoutTag.nominal {
        if node.c >= source.extra.len { return [], Error.declined; }
        return bounded(source.extra, node.c + 1, source.extra[node.c]);
    }
    return [], Error.declined;
}
fn evidenceChildren(source: blot_eval_type_evidence::View, id: u32) -> const u32[:], Error {
    let node = source.nodes[id];
    if node.tag == EvidenceTag.product { return bounded(source.extra, node.a, node.b); }
    if node.tag == EvidenceTag.record {
        if node.b > 0x7fffffff { return [], Error.declined; }
        return bounded(source.extra, node.a, node.b * 2);
    }
    if node.tag == EvidenceTag.nominal {
        if node.c >= source.extra.len { return [], Error.declined; }
        return bounded(source.extra, node.c + 1, source.extra[node.c]);
    }
    return [], Error.declined;
}
fn oldModule(self: const Importer&, owner: u32) -> const Module?, Error {
    let mapped, error = self.typeUnit(owner);
    if error != Error.none { return null, error; }
    assert(self.old); return self.old.modules[owner - 1].module, Error.none;
}
recursive fn shape<G>(self: Importer&, g: G&, id: u32, depth: i64) -> u32, Error {
    assert(self.old);
    if depth >= depth_limit || id == 0 || id >= self.old.layouts.nodes.len { return 0, Error.declined; }
    let known = self.layouts.get(id); if known { return known, Error.none; }
    var values = blot_reuse_source_value_template::WordBuffer {..};
    let result, error = self.shapeInto(g, id, depth, values);
    values.deinit(); return result, error;
}
recursive fn shapeInto<G>(self: Importer&, g: G&, id: u32, depth: i64, values: blot_reuse_source_value_template::WordBuffer&) -> u32, Error {
    assert(self.old);
    let n = self.old.layouts.nodes[id];
    var a = n.a; var b = n.b; var c = n.c;
    match n.tag {
        LayoutTag.associated, LayoutTag.scoped, LayoutTag.universal, LayoutTag.existential, LayoutTag.opened, LayoutTag.invalid, LayoutTag.erased_proof => { return 0, Error.declined; },
        LayoutTag.unit, LayoutTag.boolean, LayoutTag.unsigned32, LayoutTag.floating32, LayoutTag.never, LayoutTag.erased => {
            if a != 0 || b != 0 || c != 0 { return 0, Error.declined; }
            var mapped: u32 = 0;
            match n.tag {
                LayoutTag.unit => { mapped = 1; }, LayoutTag.boolean => { mapped = 2; },
                LayoutTag.unsigned32 => { mapped = 3; }, LayoutTag.floating32 => { mapped = 4; },
                LayoutTag.never => { mapped = 5; }, LayoutTag.erased => { mapped = 6; },
                _ => { abort("unreachable scalar layout"); },
            }
            if g.representations.store.node(mapped).tag != n.tag { return 0, Error.declined; }
            self.layouts.insert(id, mapped); return mapped, Error.none;
        },
        LayoutTag.product, LayoutTag.record, LayoutTag.nominal => {
            if n.tag != LayoutTag.nominal && c != 0 { return 0, Error.declined; }
            let children, import_error_1 = shapeChildren(self.old.layouts, id); if import_error_1 != Error.none { return 0, convert(import_error_1); }
            { let import_error_2 = values.ensure(children.len); if import_error_2 != Error.none { return 0, convert(import_error_2); } }
            if n.tag == LayoutTag.nominal { { let imported_3, import_error_3 = self.nominal(a, b); if import_error_3 != Error.none { return 0, convert(import_error_3); } a = imported_3; } { let imported_4, import_error_4 = self.nominalDeclaration(b); if import_error_4 != Error.none { return 0, convert(import_error_4); } b = imported_4; } }
            else { a = 0; b = 0; }
            for child, index in children {
                var mapped: u32 = 0;
                if n.tag == LayoutTag.record && index % 2 == 0 { { let imported_5, import_error_5 = self.symbol(child); if import_error_5 != Error.none { return 0, convert(import_error_5); } mapped = imported_5; } }
                else { { let imported_6, import_error_6 = self.shape(g, child, depth + 1); if import_error_6 != Error.none { return 0, convert(import_error_6); } mapped = imported_6; } }
                { let import_error_7 = values.push(mapped); if import_error_7 != Error.none { return 0, convert(import_error_7); } }
            }
            if n.tag == LayoutTag.record { { let import_error_8 = uniqueFields(values.items); if import_error_8 != Error.none { return 0, convert(import_error_8); } } }
            c = 0;
        },
        LayoutTag.owning => {
            if c != 0 || (b != blot_check_types::usageKindCode(blot_check_types::UsageKind.unique) && b != blot_check_types::usageKindCode(blot_check_types::UsageKind.shared)) { return 0, Error.declined; }
            { let imported_9, import_error_9 = self.shape(g, a, depth + 1); if import_error_9 != Error.none { return 0, convert(import_error_9); } a = imported_9; }
        },
        LayoutTag.function => { { let imported_10, import_error_10 = self.shape(g, a, depth + 1); if import_error_10 != Error.none { return 0, convert(import_error_10); } a = imported_10; } { let imported_11, import_error_11 = self.shape(g, b, depth + 1); if import_error_11 != Error.none { return 0, convert(import_error_11); } b = imported_11; } { let imported_12, import_error_12 = self.row(g, Domain.layout, c, depth + 1); if import_error_12 != Error.none { return 0, convert(import_error_12); } c = imported_12; } },
        LayoutTag.array, LayoutTag.list, LayoutTag.cursor, LayoutTag.resolver => {
            if b != 0 || c != 0 { return 0, Error.declined; } { let imported_13, import_error_13 = self.shape(g, a, depth + 1); if import_error_13 != Error.none { return 0, convert(import_error_13); } a = imported_13; }
        },
        LayoutTag.provider => { if b != 0 { return 0, Error.declined; } { let imported_14, import_error_14 = self.shape(g, a, depth + 1); if import_error_14 != Error.none { return 0, convert(import_error_14); } a = imported_14; } { let imported_15, import_error_15 = self.row(g, Domain.layout, c, depth + 1); if import_error_15 != Error.none { return 0, convert(import_error_15); } c = imported_15; } },
        LayoutTag.state_provider => { { let imported_16, import_error_16 = self.shape(g, a, depth + 1); if import_error_16 != Error.none { return 0, convert(import_error_16); } a = imported_16; } { let imported_17, import_error_17 = self.shape(g, b, depth + 1); if import_error_17 != Error.none { return 0, convert(import_error_17); } b = imported_17; } { let imported_18, import_error_18 = self.shape(g, c, depth + 1); if import_error_18 != Error.none { return 0, convert(import_error_18); } c = imported_18; } },
        LayoutTag.type_constructor => { if c != 0 { return 0, Error.declined; } { let imported_19, import_error_19 = self.nominal(a, b); if import_error_19 != Error.none { return 0, convert(import_error_19); } a = imported_19; } { let imported_20, import_error_20 = self.nominalDeclaration(b); if import_error_20 != Error.none { return 0, convert(import_error_20); } b = imported_20; } },
    }
    var mapped: u32 = 0;
    if n.tag == LayoutTag.state_provider { { let imported_21, import_error_21 = g.representations.store.internStateProvider(a, b, c); if import_error_21 != Error.none { return 0, convert(import_error_21); } mapped = imported_21; } }
    else { { let imported_22, import_error_22 = g.representations.store.internWithEffects(n.tag, a, b, c, values.items); if import_error_22 != Error.none { return 0, convert(import_error_22); } mapped = imported_22; } }
    self.layouts.insert(id, mapped); return mapped, Error.none;
}
recursive fn semanticType<G>(self: Importer&, g: G&, id: u32, depth: i64) -> u32, Error {
    assert(self.old);
    if depth >= depth_limit || id == 0 || id >= self.old.evaluator.evidence.nodes.len { return 0, Error.declined; }
    self.census.semantic_queries++;
    let key = EvidenceKey { id: id , ..}; let known = self.semantic.get(key);
    if known { self.census.semantic_hits++; return known, Error.none; }
    var values = blot_reuse_source_value_template::WordBuffer {..};
    let result, error = self.semanticTypeInto(g, id, depth, values);
    values.deinit(); return result, error;
}
recursive fn semanticTypeInto<G>(self: Importer&, g: G&, id: u32, depth: i64, values: blot_reuse_source_value_template::WordBuffer&) -> u32, Error {
    assert(self.old);
    let n = self.old.evaluator.evidence.nodes[id];
    var a = n.a; var b = n.b; var c = n.c;
    match n.tag {
        EvidenceTag.projection, EvidenceTag.scoped, EvidenceTag.forall, EvidenceTag.existential, EvidenceTag.bound, EvidenceTag.usage, EvidenceTag.absent, EvidenceTag.erased_proof => { return 0, Error.declined; },
        EvidenceTag.unit, EvidenceTag.boolean, EvidenceTag.unsigned32, EvidenceTag.floating32, EvidenceTag.never => { if a != 0 || b != 0 || c != 0 { return 0, Error.declined; } },
        EvidenceTag.product, EvidenceTag.record, EvidenceTag.nominal => {
            if n.tag != EvidenceTag.nominal && c != 0 { return 0, Error.declined; }
            let children, import_error_23 = evidenceChildren(self.old.evaluator.evidence.view(), id); if import_error_23 != Error.none { return 0, convert(import_error_23); }
            { let import_error_24 = values.ensure(children.len); if import_error_24 != Error.none { return 0, convert(import_error_24); } }
            if n.tag == EvidenceTag.nominal { { let imported_25, import_error_25 = self.semanticNominal(a, b); if import_error_25 != Error.none { return 0, convert(import_error_25); } a = imported_25; } { let imported_26, import_error_26 = self.nominalDeclaration(b); if import_error_26 != Error.none { return 0, convert(import_error_26); } b = imported_26; } }
            else { a = 0; b = 0; }
            for child, index in children {
                var mapped: u32 = 0;
                if n.tag == EvidenceTag.record && index % 2 == 0 { { let imported_27, import_error_27 = self.symbol(child); if import_error_27 != Error.none { return 0, convert(import_error_27); } mapped = imported_27; } }
                else { { let imported_28, import_error_28 = self.semanticType(g, child, depth + 1); if import_error_28 != Error.none { return 0, convert(import_error_28); } mapped = imported_28; } }
                { let import_error_29 = values.push(mapped); if import_error_29 != Error.none { return 0, convert(import_error_29); } }
            }
            if n.tag == EvidenceTag.record { { let import_error_30 = uniqueFields(values.items); if import_error_30 != Error.none { return 0, convert(import_error_30); } } }
            c = 0;
        },
        EvidenceTag.function => { { let imported_31, import_error_31 = self.semanticType(g, a, depth + 1); if import_error_31 != Error.none { return 0, convert(import_error_31); } a = imported_31; } { let imported_32, import_error_32 = self.semanticType(g, b, depth + 1); if import_error_32 != Error.none { return 0, convert(import_error_32); } b = imported_32; } { let imported_33, import_error_33 = self.row(g, Domain.semantic, c, depth + 1); if import_error_33 != Error.none { return 0, convert(import_error_33); } c = imported_33; } },
        EvidenceTag.array, EvidenceTag.list, EvidenceTag.cursor, EvidenceTag.resolver => { if b != 0 || c != 0 { return 0, Error.declined; } { let imported_34, import_error_34 = self.semanticType(g, a, depth + 1); if import_error_34 != Error.none { return 0, convert(import_error_34); } a = imported_34; } },
        EvidenceTag.provider => { if b != 0 { return 0, Error.declined; } { let imported_35, import_error_35 = self.semanticType(g, a, depth + 1); if import_error_35 != Error.none { return 0, convert(import_error_35); } a = imported_35; } { let imported_36, import_error_36 = self.row(g, Domain.semantic, c, depth + 1); if import_error_36 != Error.none { return 0, convert(import_error_36); } c = imported_36; } },
        EvidenceTag.state_provider => { { let imported_37, import_error_37 = self.semanticType(g, a, depth + 1); if import_error_37 != Error.none { return 0, convert(import_error_37); } a = imported_37; } { let imported_38, import_error_38 = self.semanticType(g, b, depth + 1); if import_error_38 != Error.none { return 0, convert(import_error_38); } b = imported_38; } { let imported_39, import_error_39 = self.semanticType(g, c, depth + 1); if import_error_39 != Error.none { return 0, convert(import_error_39); } c = imported_39; } },
        EvidenceTag.type_constructor => { if c != 0 { return 0, Error.declined; } { let imported_40, import_error_40 = self.semanticNominal(a, b); if import_error_40 != Error.none { return 0, convert(import_error_40); } a = imported_40; } { let imported_41, import_error_41 = self.nominalDeclaration(b); if import_error_41 != Error.none { return 0, convert(import_error_41); } b = imported_41; } },
    }
    var mapped: u32 = 0;
    if n.tag == EvidenceTag.state_provider { { let imported_42, import_error_42 = g.evaluator.storage.evidence.internStateProvider(a, b, c); if import_error_42 != Error.none { return 0, convert(import_error_42); } mapped = imported_42; } }
    else { { let imported_43, import_error_43 = g.evaluator.storage.evidence.internWithEffects(n.tag, a, b, c, values.items); if import_error_43 != Error.none { return 0, convert(import_error_43); } mapped = imported_43; } }
    self.semantic.insert(EvidenceKey { id: id , ..}, mapped);
    self.census.semantic_nodes++; self.census.semantic_child_words += values.items.len;
    return mapped, Error.none;
}
recursive fn row<G>(self: Importer&, g: G&, domain: Domain, id: u32, depth: i64) -> u32, Error {
    if depth >= depth_limit { return 0, Error.declined; }
    if domain == Domain.layout && id == blot_backend_layout::unknown_row { return id, Error.none; }
    self.census.row_queries++;
    let key = RowKey { domain, id , ..}; let known = self.rows.get(key);
    if known { self.census.row_hits++; return known, Error.none; }
    var imported = blot_reuse_source_value_template::WordBuffer {..};
    var arguments = blot_reuse_source_value_template::WordBuffer {..};
    let mapped, error = self.rowInto(g, domain, id, depth, imported, arguments);
    imported.deinit(); arguments.deinit(); return mapped, error;
}
recursive fn rowInto<G>(self: Importer&, g: G&, domain: Domain, id: u32, depth: i64, imported: blot_reuse_source_value_template::WordBuffer&, arguments: blot_reuse_source_value_template::WordBuffer&) -> u32, Error {
    let old .= self.old; assert(old);
    var source = old.layouts.effects.view();
    if domain == Domain.semantic { source = old.evaluator.evidence.effects.view(); }
    if id >= source.rows.len { return 0, Error.declined; }
    let span = source.rows[id]; let labels, import_error_44 = bounded(source.labels, span.start, span.len); if import_error_44 != Error.none { return 0, convert(import_error_44); }
    if id == 0 && labels.len != 0 { return 0, Error.declined; }
    { let import_error_45 = imported.ensure(labels.len); if import_error_45 != Error.none { return 0, convert(import_error_45); } }
    for label in labels {
        if label == 0 || label >= source.operations.len { return 0, Error.declined; }
        let operation = source.operations[label];
        if operation.instance.unit != 0 || operation.instance.decl != 0 { return 0, Error.declined; }
        let old_args, import_error_46 = bounded(source.arguments, operation.arguments.start, operation.arguments.len); if import_error_46 != Error.none { return 0, convert(import_error_46); }
        self.census.row_argument_words += old_args.len;
        var owner: u32 = 0;
        if operation.identity.unit == 0 {
            if operation.identity.decl != 1 || old_args.len != 0 { return 0, Error.declined; }
        } else if domain == Domain.semantic { { let imported_47, import_error_47 = self.semanticNominal(operation.identity.unit, operation.identity.decl); if import_error_47 != Error.none { return 0, convert(import_error_47); } owner = imported_47; } }
        else { { let imported_48, import_error_48 = self.nominal(operation.identity.unit, operation.identity.decl); if import_error_48 != Error.none { return 0, convert(import_error_48); } owner = imported_48; } }
        arguments.clear(); { let import_error_49 = arguments.ensure(old_args.len); if import_error_49 != Error.none { return 0, convert(import_error_49); } }
        for argument in old_args {
            var mapped: u32 = 0;
            if domain == Domain.layout { { let imported_50, import_error_50 = self.shape(g, argument, depth + 1); if import_error_50 != Error.none { return 0, convert(import_error_50); } mapped = imported_50; } }
            else { { let imported_51, import_error_51 = self.semanticType(g, argument, depth + 1); if import_error_51 != Error.none { return 0, convert(import_error_51); } mapped = imported_51; } }
            { let import_error_52 = arguments.push(mapped); if import_error_52 != Error.none { return 0, convert(import_error_52); } }
        }
        var new_label: u32 = 0;
        let identity = blot_check_types::NominalIdentity { owner, operation.identity.decl , ..};
        if domain == Domain.layout { { let imported_53, import_error_53 = g.representations.store.effects.internOperation(identity, arguments.items); if import_error_53 != Error.none { return 0, convert(import_error_53); } new_label = imported_53; } }
        else { { let imported_54, import_error_54 = g.evaluator.storage.evidence.effects.internOperation(identity, arguments.items); if import_error_54 != Error.none { return 0, convert(import_error_54); } new_label = imported_54; } }
        { let import_error_55 = imported.push(new_label); if import_error_55 != Error.none { return 0, convert(import_error_55); } }
    }
    var mapped: u32 = 0;
    if domain == Domain.layout { { let imported_56, import_error_56 = g.representations.store.effects.internRow(imported.items); if import_error_56 != Error.none { return 0, convert(import_error_56); } mapped = imported_56; } }
    else { { let imported_57, import_error_57 = g.evaluator.storage.evidence.effects.internRow(imported.items); if import_error_57 != Error.none { return 0, convert(import_error_57); } mapped = imported_57; } }
    self.rows.insert(RowKey { domain, id , ..}, mapped); self.census.row_nodes++;
    return mapped, Error.none;
}

fn expressionUnit(self: const Importer&, source: u32, root: u32) -> u32, Error {
    let mapped, import_error_1 = self.unit(source, false); if import_error_1 != Error.none { return 0, convert(import_error_1); }
    if self.stable[source - 1] || self.expression_nodes.contains(ExpressionKey { source, root , ..}) { return mapped, Error.none; }
    if !self.code_gate.present { return 0, Error.declined; }
    let gate .= self.code_gate.value.semantic;
    if !gate.enabled { return 0, Error.declined; }
    if !gate.structural_units[source - 1] {
        if !self.code_gate.value.expressionRoot(mapped, root) { return 0, Error.declined; }
        return mapped, Error.none;
    }
    assert(self.old);
    let references, import_error_2 = blot_reuse_declaration_dependencies::expressionReferences(self.old.modules[source - 1].module, root); if import_error_2 != Error.none { return 0, convert(import_error_2); }
    var admitted = true;
    for reference in references {
        var unit = reference.unit; if unit == 0 { unit = source; }
        if unit == 0 || unit >= gate.offsets.len || reference.binding >= gate.units[unit - 1].bindings.len || gate.dirty[gate.offsets[unit - 1] + reference.binding] { admitted = false; break; }
    }
    blot_reuse_declaration_dependencies::releaseReferences(references);
    if !admitted { return 0, Error.declined; }
    return mapped, Error.none;
}
fn checkFields<G>(self: const Importer&, g: G&) -> Error {
    assert(self.old);
    if self.old.field_locations.len != g.evaluator.field_locations.count() { return Error.declined; }
    for field in self.old.field_locations {
        let source_unit = (field.family >> 32) as u32; let decl = field.family as! u32;
        var mapped = source_unit;
        if source_unit != 0xffffffff { let value, error = self.unit(source_unit, false); if error != Error.none { return error; } mapped = value; }
        let family = (mapped as u64) << 32 | decl;
        let name, error = self.symbol(field.name); if error != Error.none { return error; }
        let found = g.evaluator.field_locations.get(blot_eval_core_eval::FieldKey { family, field.tag, name , ..});
        if !found || found.field != field.field || found.len != field.len { return Error.declined; }
    }
    return Error.none;
}
fn staticEntries(self: const Importer&, id: u32) -> const blot_reuse_substitution_keys::Entry[:], Error {
    assert(self.old);
    if id == 0 { return [], Error.none; }
    if id > self.old.static_values.spans.len { return [], Error.declined; }
    let span = self.old.static_values.spans[id - 1];
    let entries, error = bounded(self.old.static_values.entries, span.start, span.len);
    if error != Error.none { return [], error; }
    for entry, index in entries {
        if entry.variable == 0 || entry.value >= self.old.evaluator.values.len { return [], Error.declined; }
        if index != 0 && entry.variable <= entries[index - 1].variable { return [], Error.declined; }
    }
    return entries, Error.none;
}
fn substitutionEntries(pool: const blot_reuse_code_artifacts::Substitutions&, id: u32) -> const blot_reuse_substitution_keys::Entry[:], Error {
    if id == 0 { return [], Error.none; }
    if id > pool.spans.len { return [], Error.declined; }
    let span = pool.spans[id - 1]; let entries, error = bounded(pool.entries, span.start, span.len);
    if error != Error.none { return [], error; }
    for entry, index in entries { if index != 0 && entry.variable <= entries[index - 1].variable { return [], Error.declined; } }
    return entries, Error.none;
}
fn recordValueAnchorIds(self: Importer&, anchors: const u32[:], ids: u32[:]) -> bool, Error {
    assert(self.old);
    if anchors.len != self.old.evaluator.values.len { return false, Error.none; }
    sortWords(ids);
    for old in ids {
        let current = anchors[old]; if current == 0 { continue; }
        let known = self.value_anchors.get(old); if known && known != current { return false, Error.none; }
    }
    for old in ids { let current = anchors[old]; if current != 0 { self.value_anchors.insert(old, current); } }
    return true, Error.none;
}
fn recordValueAnchors(self: Importer&, anchors: const u32[:]) -> bool, Error {
    assert(self.old);
    if anchors.len != self.old.evaluator.values.len { return false, Error.none; }
    for current, old in anchors { if current == 0 { continue; } let known = self.value_anchors.get(old as u32); if known && known != current { return false, Error.none; } }
    for current, old in anchors { if current != 0 { self.value_anchors.insert(old as u32, current); } }
    return true, Error.none;
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
fn closedShape<G>(self: Importer&, g: G&, old_id: u32) -> u32, Error {
    let actual, import_error_3 = self.shape(g, old_id, 0); if import_error_3 != Error.none { return 0, convert(import_error_3); }
    let known, import_error_4 = self.knowledge.knownLayout(g.representations.store, actual); if import_error_4 != Error.none { return 0, convert(import_error_4); }
    if !known { return 0, Error.declined; } return actual, Error.none;
}

fn target(self: const Importer&, value: blot_check_core::BindingRef) -> blot_check_core::BindingRef, Error {
    if !self.admitsBody(value) { return default<blot_check_core::BindingRef>(), Error.declined; }
    let mapped, error = self.unit(value.unit, false);
    if error != Error.none { return default<blot_check_core::BindingRef>(), error; }
    if value.binding == 0 || value.binding >= self.units[mapped - 1].bindings.len || !self.units[mapped - 1].body(value.binding) { return default<blot_check_core::BindingRef>(), Error.declined; }
    return blot_check_core::BindingRef { mapped, value.binding , ..}, Error.none;
}
fn importRequest<G>(self: Importer&, g: G&, old: blot_reuse_code_artifacts::Request) -> blot_support::Option<blot_reuse_code_artifacts::Request>, Error {
    let value, error = self.request(g, old, true);
    if error == Error.none { return blot_support::some(value), Error.none; }
    if error == Error.out_of_memory { return blot_support::none<blot_reuse_code_artifacts::Request>(), error; }
    return blot_support::none<blot_reuse_code_artifacts::Request>(), Error.none;
}
fn matches<G>(self: Importer&, g: G&, old: blot_reuse_code_artifacts::Request, current: blot_reuse_code_artifacts::Request) -> bool, Error {
    match old {
        blot_reuse_code_artifacts::Request.closure old_closure => {
            match current {
                blot_reuse_code_artifacts::Request.closure current_closure => {
                    if old_closure.key.static_values != 0 || current_closure.key.static_values != 0 {
                        var actual = current_closure.key; actual.static_values = 0;
                        let imported, error = self.request(g, old, false);
                        if error == Error.out_of_memory { return false, error; }
                        if error != Error.none || imported != (blot_reuse_code_artifacts::Request.closure { actual , ..}) { return false, Error.none; }
                        return self.matchStaticKey(g, old_closure.key.static_values, current_closure.key.static_values);
                    }
                }, _ => {},
            }
        }, _ => {},
    }
    let imported, error = self.importRequest(g, old);
    return imported.present && imported.value == current, error;
}
fn request<G>(self: Importer&, g: G&, old: blot_reuse_code_artifacts::Request, import_static: bool) -> blot_reuse_code_artifacts::Request, Error {
    { let import_error_1 = self.bind(g); if import_error_1 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_1); } }
    assert(self.old);
    match old {
        blot_reuse_code_artifacts::Request.named payload => {
            var key = payload.key;
            if key.instance_arguments != 0 || key.dictionaries || key.count > blot_reuse_code_artifacts::max_parameters { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            { let imported_2, import_error_2 = self.target(key.target); if import_error_2 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_2); } key.target = imported_2; }
            for index in 0..blot_reuse_code_artifacts::max_parameters {
                if index >= key.count {
                    if key.parameters[index] != 1 || key.effects[index] != 0 { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
                    continue;
                }
                { let imported_3, import_error_3 = self.shape(g, key.parameters[index], 0); if import_error_3 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_3); } key.parameters[index] = imported_3; }
                let known, import_error_4 = self.knowledge.knownLayout(g.representations.store, key.parameters[index]); if import_error_4 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_4); }
                if !known || key.effects[index] == blot_backend_layout::unknown_row { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
                { let imported_5, import_error_5 = self.row(g, Domain.layout, key.effects[index], 0); if import_error_5 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_5); } key.effects[index] = imported_5; }
                let row_known, import_error_6 = self.knowledge.knownRow(g.representations.store, key.effects[index]); if import_error_6 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_6); }
                if !row_known { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            }
            { let imported_7, import_error_7 = self.closedShape(g, key.result); if import_error_7 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_7); } key.result = imported_7; }
            { let imported_8, import_error_8 = self.templateKey(g, payload.key.target.unit, key.templates, 0); if import_error_8 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_8); } key.templates = imported_8; }
            return blot_reuse_code_artifacts::Request.named { key , ..}, Error.none;
        },
        blot_reuse_code_artifacts::Request.closure payload => {
            var key = payload.key; let source = payload.key;
            if key.dictionaries || source.unit == 0 || source.unit > self.old.modules.len || source.catalog >= self.old.modules[source.unit - 1].module.closures.len { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            { let imported_9, import_error_9 = self.expressionUnit(source.unit, self.old.modules[source.unit - 1].module.closures[source.catalog].body); if import_error_9 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_9); } key.unit = imported_9; }
            if key.catalog >= self.units[key.unit - 1].closures.len { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            { let imported_10, import_error_10 = self.shape(g, key.ty, 0); if import_error_10 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_10); } key.ty = imported_10; }
            { let imported_11, import_error_11 = self.shape(g, key.captures, 0); if import_error_11 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_11); } key.captures = imported_11; }
            if g.representations.store.node(key.ty).tag != LayoutTag.function || g.representations.store.node(key.captures).tag != LayoutTag.product { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            let known, import_error_12 = self.knowledge.knownLayout(g.representations.store, key.ty); if import_error_12 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_12); }
            if !known { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            if source.static_values == 0 {
                let captures_known, import_error_13 = self.knowledge.knownLayout(g.representations.store, key.captures); if import_error_13 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_13); }
                if !captures_known { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            } else {
                let module .= self.old.modules[source.unit - 1].module; let span = module.closures[source.catalog].captures;
                let bindings = module.extra[span.start..span.start + span.len];
                let layouts = g.representations.store.children(key.captures);
                if bindings.len != layouts.len { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
                let statics, import_error_14 = self.staticEntries(source.static_values); if import_error_14 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_14); }
                for binding, index in bindings {
                    var is_static = false;
                    for item in statics { if item.variable == binding { is_static = true; break; } }
                    if !is_static {
                        let capture_known, import_error_15 = self.knowledge.knownLayout(g.representations.store, layouts[index]); if import_error_15 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_15); }
                        if !capture_known { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
                    }
                }
            }
            { let imported_16, import_error_16 = self.templateKey(g, source.unit, key.templates, 0); if import_error_16 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_16); } key.templates = imported_16; }
            { let imported_17, import_error_17 = self.mappingEvidence(g, source.unit, key.evidence, 0); if import_error_17 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_17); } key.evidence = imported_17; }
            { let imported_18, import_error_18 = self.rowKey(g, source.unit, key.rows, 0); if import_error_18 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_18); } key.rows = imported_18; }
            if key.parameter_template != 0 { { let imported_19, import_error_19 = self.capture(g, key.parameter_template, 0); if import_error_19 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_19); } key.parameter_template = imported_19; } }
            key.static_values = 0;
            if import_static { { let imported_20, import_error_20 = self.staticKey(g, source.static_values); if import_error_20 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_20); } key.static_values = imported_20; } }
            if key.scalar_environment && (!g.representations.store.scalarEnvironment(key.captures) || key.templates != 0 || key.static_values != 0) { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            return blot_reuse_code_artifacts::Request.closure { key , ..}, Error.none;
        },
        blot_reuse_code_artifacts::Request.callable payload => {
            let old_key = payload.key;
            if old_key.dictionaries || old_key.bound_dictionaries || old_key.instance_arguments != 0 { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            let target, import_error_21 = self.target(old_key.target); if import_error_21 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_21); }
            let ty, import_error_22 = self.closedShape(g, old_key.ty); if import_error_22 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_22); }
            let templates, import_error_23 = self.templateKey(g, old_key.target.unit, old_key.templates, 0); if import_error_23 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_23); }
            return blot_reuse_code_artifacts::Request.callable { blot_reuse_code_artifacts::CallableKey { target: target, ty: ty, applied: old_key.applied, templates: templates } , ..}, Error.none;
        },
        blot_reuse_code_artifacts::Request.constructor payload => {
            let owner, import_error_24 = self.typeUnit(payload.key.unit); if import_error_24 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_24); }
            if payload.key.catalog >= self.units[owner - 1].constructors.len { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            let ty, import_error_25 = self.closedShape(g, payload.key.ty); if import_error_25 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_25); }
            return blot_reuse_code_artifacts::Request.constructor { blot_reuse_code_artifacts::ConstructorKey { owner, payload.key.catalog, ty } , ..}, Error.none;
        },
        blot_reuse_code_artifacts::Request.primitive payload => {
            let owner, import_error_26 = self.unit(payload.key.unit, true); if import_error_26 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_26); }
            if payload.key.catalog >= self.units[owner - 1].primitives.len { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            let ty, import_error_27 = self.closedShape(g, payload.key.ty); if import_error_27 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_27); }
            return blot_reuse_code_artifacts::Request.primitive { blot_reuse_code_artifacts::PrimitiveKey { owner, payload.key.catalog, ty, payload.key.applied } , ..}, Error.none;
        },
        blot_reuse_code_artifacts::Request.operation payload => {
            if payload.key.operation == 0 || payload.key.operation > self.old.operations.len { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            let operation = self.old.operations[payload.key.operation - 1];
            { let import_error_28 = self.operationScope(g, payload.key.operation); if import_error_28 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_28); } }
            for current, index in g.planning.runtime_operations.entries {
                if current.foreign != operation.foreign || g.planning.runtime_operations.key(current) != operation.key { continue; }
                let ty, import_error_29 = self.closedShape(g, payload.key.ty); if import_error_29 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_29); }
                return blot_reuse_code_artifacts::Request.operation { blot_reuse_code_artifacts::OperationKey { operation: (index + 1) as u32, ty: ty } , ..}, Error.none;
            }
            return default<blot_reuse_code_artifacts::Request>(), Error.declined;
        },
        blot_reuse_code_artifacts::Request.host payload => {
            let ty, import_error_30 = self.closedShape(g, payload.key.ty); if import_error_30 != Error.none { return default<blot_reuse_code_artifacts::Request>(), convert(import_error_30); }
            let arrow = g.representations.store.node(ty);
            if arrow.tag != LayoutTag.function { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            let cleanup = g.representations.store.node(arrow.a).tag == LayoutTag.owning;
            if payload.key.owned != (cleanup && g.persistent_outputs) { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            if cleanup {
                let input = g.representations.store.node(arrow.a).a;
                if !g.representations.store.abi(input).present || g.representations.store.node(input).tag == LayoutTag.nominal { return default<blot_reuse_code_artifacts::Request>(), Error.declined; }
            }
            return blot_reuse_code_artifacts::Request.host { blot_reuse_code_artifacts::HostKey { ty, payload.key.owned } , ..}, Error.none;
        },
        blot_reuse_code_artifacts::Request.constant, blot_reuse_code_artifacts::Request.runtime_global => { return default<blot_reuse_code_artifacts::Request>(), Error.declined; },
    }
}

struct EntryBuffer { storage: blot_reuse_substitution_keys::Entry[:] = [], items: blot_reuse_substitution_keys::Entry[:] = [] }
reusable[] var entry_buffer_runs: blot_reuse_substitution_keys::Entry[>..] = [];
fn push(self: EntryBuffer&, value: blot_reuse_substitution_keys::Entry) -> Error { return blot_support_pooled_buffer::push(self, value, entry_buffer_runs); }
fn deinit(self: EntryBuffer&) { blot_support_pooled_buffer::deinit(self, entry_buffer_runs); }
recursive fn mappingEvidence<G>(self: Importer&, g: G&, owner: u32, id: u32, depth: i64) -> u32, Error {
    if id == 0 { return 0, Error.none; } assert(self.old);
    if depth >= depth_limit || id >= self.old.evaluator.evidence.nodes.len { return 0, Error.declined; }
    let key = EvidenceKey { id: id, owner: owner, mappings: true , ..};
    let known = self.semantic.get(key); if known { return known, Error.none; }
    var words = blot_reuse_source_value_template::WordBuffer {..};
    let result, error = self.mappingEvidenceInto(g, owner, id, depth, words);
    words.deinit(); return result, error;
}
recursive fn mappingEvidenceInto<G>(self: Importer&, g: G&, owner: u32, id: u32, depth: i64, words: blot_reuse_source_value_template::WordBuffer&) -> u32, Error {
    assert(self.old);
    let module, import_error_1 = self.oldModule(owner); if import_error_1 != Error.none { return 0, convert(import_error_1); } assert(module);
    if self.old.evaluator.evidence.nodes[id].tag != EvidenceTag.record { return 0, Error.declined; }
    let children, import_error_2 = evidenceChildren(self.old.evaluator.evidence.view(), id); if import_error_2 != Error.none { return 0, convert(import_error_2); }
    for index in 0..children.len / 2 {
        let variable = children[index * 2];
        if variable == 0 || variable >= module.types.nodes.len { return 0, Error.declined; }
        let evidence, import_error_3 = self.semanticType(g, children[index * 2 + 1], depth + 1); if import_error_3 != Error.none { return 0, convert(import_error_3); }
        { let import_error_4 = words.push(variable); if import_error_4 != Error.none { return 0, convert(import_error_4); } } { let import_error_5 = words.push(evidence); if import_error_5 != Error.none { return 0, convert(import_error_5); } }
    }
    { let import_error_6 = uniqueFields(words.items); if import_error_6 != Error.none { return 0, convert(import_error_6); } }
    let mapped, import_error_7 = g.evaluator.storage.evidence.intern(EvidenceTag.record, 0, 0, words.items); if import_error_7 != Error.none { return 0, convert(import_error_7); }
    self.semantic.insert(EvidenceKey { id: id, owner: owner, mappings: true , ..}, mapped);
    return mapped, Error.none;
}
recursive fn templateKey<G>(self: Importer&, g: G&, owner: u32, id: u32, depth: i64) -> u32, Error {
    if id == 0 { return 0, Error.none; }
    if depth >= depth_limit { return 0, Error.declined; }
    let key = SubstitutionKey { id, owner , ..}; let known = self.template_keys.get(key);
    if known { return known, Error.none; }
    var imported = EntryBuffer {..};
    let result, error = self.substitutionInto(g, owner, id, depth, false, imported);
    imported.deinit(); return result, error;
}
recursive fn rowKey<G>(self: Importer&, g: G&, owner: u32, id: u32, depth: i64) -> u32, Error {
    if id == 0 { return 0, Error.none; }
    if depth >= depth_limit { return 0, Error.declined; }
    let key = SubstitutionKey { id, owner , ..}; let known = self.row_keys.get(key);
    if known { return known, Error.none; }
    var imported = EntryBuffer {..};
    let result, error = self.substitutionInto(g, owner, id, depth, true, imported);
    imported.deinit(); return result, error;
}
recursive fn substitutionInto<G>(self: Importer&, g: G&, owner: u32, id: u32, depth: i64, row_key: bool, imported: EntryBuffer&) -> u32, Error {
    assert(self.old);
    let module, import_error_8 = self.oldModule(owner); if import_error_8 != Error.none { return 0, convert(import_error_8); } assert(module);
    var source .= self.old.templates; if row_key { source .= self.old.rows; }
    let entries, import_error_9 = substitutionEntries(source, id); if import_error_9 != Error.none { return 0, convert(import_error_9); }
    for entry in entries {
        var value: u32 = 0;
        if row_key {
            if entry.variable >= module.types.effects.variable_count || entry.value == blot_backend_layout::unknown_row { return 0, Error.declined; }
            { let imported_10, import_error_10 = self.row(g, Domain.semantic, entry.value, depth + 1); if import_error_10 != Error.none { return 0, convert(import_error_10); } value = imported_10; }
        } else {
            if entry.variable == 0 || entry.variable >= module.bindings.len { return 0, Error.declined; }
            { let imported_11, import_error_11 = self.capture(g, entry.value, depth + 1); if import_error_11 != Error.none { return 0, convert(import_error_11); } value = imported_11; }
        }
        { let import_error_12 = imported.push(blot_reuse_substitution_keys::Entry { entry.variable, value , ..}); if import_error_12 != Error.none { return 0, convert(import_error_12); } }
    }
    var mapped: u32 = 0;
    if row_key { { let imported_13, import_error_13 = g.representations.row_keys.intern(imported.items); if import_error_13 != Error.none { return 0, convert(import_error_13); } mapped = imported_13; } self.row_keys.insert(SubstitutionKey { id, owner , ..}, mapped); }
    else { { let imported_14, import_error_14 = g.representations.template_keys.intern(imported.items); if import_error_14 != Error.none { return 0, convert(import_error_14); } mapped = imported_14; } self.template_keys.insert(SubstitutionKey { id, owner , ..}, mapped); }
    return mapped, Error.none;
}
recursive fn capture<G>(self: Importer&, g: G&, id: u32, depth: i64) -> u32, Error {
    assert(self.old);
    if depth >= depth_limit || id == 0 || id > self.old.captures.len { return 0, Error.declined; }
    let known = self.captures.get(id); if known { return known, Error.none; }
    let old = self.old.captures[id - 1];
    if old.callable_instances != 0 { return 0, Error.declined; }
    let owner, import_error_15 = self.expressionUnit(old.unit, old.node); if import_error_15 != Error.none { return 0, convert(import_error_15); }
    if old.node == 0 || old.node >= self.units[owner - 1].nodes.len { return 0, Error.declined; }
    let captures, import_error_16 = self.shape(g, old.captures, depth + 1); if import_error_16 != Error.none { return 0, convert(import_error_16); }
    let templates, import_error_17 = self.templateKey(g, old.unit, old.templates, depth + 1); if import_error_17 != Error.none { return 0, convert(import_error_17); }
    let evidence, import_error_18 = self.mappingEvidence(g, old.unit, old.evidence, depth + 1); if import_error_18 != Error.none { return 0, convert(import_error_18); }
    let rows, import_error_19 = self.rowKey(g, old.unit, old.rows, depth + 1); if import_error_19 != Error.none { return 0, convert(import_error_19); }
    let imported = blot_reuse_code_artifacts::CapturedTemplate { unit: owner, node: old.node, captures: captures, templates: templates, has_environment: old.has_environment, scalar_environment: old.scalar_environment, computation: old.computation, evidence: evidence, rows: rows , ..};
    let closed, import_error_20 = self.knowledge.knownLayout(g.representations.store, imported.captures); if import_error_20 != Error.none { return 0, convert(import_error_20); }
    if !closed || (imported.scalar_environment && (!imported.has_environment || imported.templates != 0 || !g.representations.store.scalarEnvironment(imported.captures) || self.units[owner - 1].node(imported.node).tag != blot_check_core::Tag.closure)) { return 0, Error.declined; }
    var mapped: u32 = 0; let existing = g.planning.template_instances.get(imported);
    if existing { mapped = existing; }
    else {
        if g.planning.template_catalog.len >= 0xffffffff { return 0, Error.declined; }
        mapped = (g.planning.template_catalog.len + 1) as u32;
        g.planning.template_catalog.push(imported); g.planning.template_instances.insert(imported, mapped);
    }
    self.captures.insert(id, mapped); return mapped, Error.none;
}
fn staticKey<G>(self: Importer&, g: G&, id: u32) -> u32, Error {
    if id == 0 { return 0, Error.none; }
    var entries = EntryBuffer {..};
    let result, error = self.staticKeyInto(g, id, entries);
    entries.deinit(); return result, error;
}
fn staticKeyInto<G>(self: Importer&, g: G&, id: u32, entries: EntryBuffer&) -> u32, Error {
    let source, import_error_21 = self.staticEntries(id); if import_error_21 != Error.none { return 0, convert(import_error_21); }
    for old in source {
        var current: u32 = 0;
        if old.value != 0 { let known = self.value_anchors.get(old.value); if !known { return 0, Error.declined; } current = known; }
        { let import_error_22 = entries.push(blot_reuse_substitution_keys::Entry { old.variable, current , ..}); if import_error_22 != Error.none { return 0, convert(import_error_22); } }
    }
    let result, import_error_23 = g.representations.static_keys.intern(entries.items); if import_error_23 != Error.none { return 0, convert(import_error_23); }
    return result, Error.none;
}
fn optionalImported<T>(value: T, error: Error) -> blot_support::Option<T>, Error {
    if error == Error.none { return blot_support::some(value), Error.none; }
    if error == Error.out_of_memory { return blot_support::none<T>(), error; }
    return blot_support::none<T>(), Error.none;
}
fn importLayout<G>(self: Importer&, g: G&, id: u32) -> blot_support::Option<u32>, Error {
    let bound = self.bind(g); if bound != Error.none { return optionalImported(0 as u32, bound); }
    let value, error = self.shape(g, id, 0); return optionalImported(value, error);
}
fn importCallableLayout<G>(self: Importer&, g: G&, id: u32, expected: blot_support::Option<u32>) -> blot_support::Option<u32>, Error {
    assert(self.old);
    if id == 0 || id >= self.old.layouts.nodes.len || self.old.layouts.nodes[id].tag != LayoutTag.function || (expected.present && id != expected.value) { return blot_support::none<u32>(), Error.none; }
    let actual, error = self.importLayout(g, id); if error != Error.none || !actual.present { return actual, error; }
    let known, failure = self.knowledge.knownLayout(g.representations.store, actual.value);
    if failure != Error.none { return blot_support::none<u32>(), failure; }
    if !known { return blot_support::none<u32>(), Error.none; }
    return actual, Error.none;
}
fn importEvidence<G>(self: Importer&, g: G&, id: u32) -> blot_support::Option<u32>, Error {
    let bound = self.bind(g); if bound != Error.none { return optionalImported(0 as u32, bound); }
    let value, error = self.semanticType(g, id, 0); return optionalImported(value, error);
}
fn importClosedEvidence<G>(self: Importer&, g: G&, id: u32) -> blot_support::Option<u32>, Error {
    let ordinary, error = self.importEvidence(g, id);
    if error != Error.none || ordinary.present { return ordinary, error; }
    if !self.semantic_catalogs { return blot_support::none<u32>(), Error.none; }
    let bound = self.bind(g); if bound != Error.none { return optionalImported(0 as u32, bound); }
    let key = EvidenceKey { id: id , ..}; let known = self.semantic.get(key);
    if known { return blot_support::some(known as u32), Error.none; }
    assert(self.old); let view = self.old.evaluator.evidence.view(); var remaining: i64 = 65536;
    if view.closed(id, 0, remaining) != Error.none { return blot_support::none<u32>(), Error.none; }
    if !self.closed_evidence.present {
        self.closed_evidence = blot_support::some(blot_eval_semantic_evidence_import::initPooled(view, g.evaluator.storage.evidence, depth_limit, false));
    }
    let value, failure = self.closed_evidence.value.ty(id, 0);
    if failure == Error.none { self.semantic.insert(key, value); }
    return optionalImported(value, failure);
}
fn importSemanticRow<G>(self: Importer&, g: G&, id: u32) -> blot_support::Option<u32>, Error {
    let bound = self.bind(g); if bound != Error.none { return optionalImported(0 as u32, bound); }
    let value, error = self.row(g, Domain.semantic, id, 0); return optionalImported(value, error);
}
fn importResultTemplate<G>(self: Importer&, g: G&, id: u32) -> blot_support::Option<u32>, Error {
    let bound = self.bind(g); if bound != Error.none { return optionalImported(0 as u32, bound); }
    let value, error = self.capture(g, id, 0); return optionalImported(value, error);
}

struct StaticMatchScratch {
    old_roots: blot_reuse_source_value_template::WordBuffer = blot_reuse_source_value_template::WordBuffer {..},
    current_roots: blot_reuse_source_value_template::WordBuffer = blot_reuse_source_value_template::WordBuffer {..},
    temporary: blot_support::Option<blot_reuse_source_value_template::Plan>,
}
fn deinit(self: StaticMatchScratch&) {
    self.old_roots.deinit(); self.current_roots.deinit();
    if self.temporary.present { self.temporary.value.deinit(); self.temporary.present = false; }
}
fn matchStaticKey<G>(self: Importer&, g: G&, old_id: u32, current_id: u32) -> bool, Error {
    var scratch = StaticMatchScratch {..};
    let result, error = self.matchStaticKeyInto(g, old_id, current_id, scratch);
    scratch.deinit(); return result, error;
}
fn matchStaticKeyInto<G>(self: Importer&, g: G&, old_id: u32, current_id: u32, temporary: StaticMatchScratch&) -> bool, Error {
    let before, invalid = self.staticEntries(old_id);
    if invalid != Error.none { return false, Error.none; }
    let after = g.representations.static_keys.get(current_id);
    if before.len != after.len || before.len == 0 || !self.code_gate.present { return false, Error.none; }
    let gate .= self.code_gate.value.semantic;
    { let import_error_1 = temporary.old_roots.ensure(before.len); if import_error_1 != Error.none { return false, convert(import_error_1); } } { let import_error_2 = temporary.current_roots.ensure(before.len); if import_error_2 != Error.none { return false, convert(import_error_2); } }
    for old, index in before {
        let current = after[index];
        if old.variable != current.variable { return false, Error.none; }
        { let import_error_3 = temporary.old_roots.push(old.value); if import_error_3 != Error.none { return false, convert(import_error_3); } } { let import_error_4 = temporary.current_roots.push(current.value); if import_error_4 != Error.none { return false, convert(import_error_4); } }
    }
    var plan: const blot_reuse_source_value_template::Plan? = self.static_plans.get(old_id);
    if plan { self.census.static_plan_hits++; }
    else {
        self.census.static_plan_inspections++; assert(self.old);
        let inspection, import_error_5 = blot_reuse_source_value_template::inspectRootsWithRows(self.old, gate, temporary.old_roots.items, blot_reuse_source_value_template::RowPolicy.source_declared); if import_error_5 != Error.none { return false, convert(import_error_5); }
        temporary.temporary = inspection.plan;
        if !temporary.temporary.present { return false, Error.none; }
        if self.static_plans.table.count < 64 && temporary.temporary.value.order.len <= 65536 - self.static_plan_nodes {
            self.static_plan_nodes += temporary.temporary.value.order.len;
            self.static_plans.insert(old_id, temporary.temporary.value); temporary.temporary.present = false;
            plan .= self.static_plans.get(old_id);
        } else { plan .= temporary.temporary.value; }
    }
    assert(plan);
    if !self.static_scratch.present { self.static_scratch = blot_support::some(blot_reuse_source_value_template::QueryScratch { allocation_owner: g.allocation_owner , ..}); }
    let scratch .= self.static_scratch.value;
    let anchors, begin_error = scratch.begin(plan, g);
    if begin_error != Error.none { if begin_error == Error.out_of_memory { return false, begin_error; } return false, Error.none; }
    let matched, error = plan.matchRootsIntoWithScratch(g, self, temporary.old_roots.items, temporary.current_roots.items, anchors, scratch);
    if error != Error.none { if error == Error.out_of_memory { return false, error; } return false, Error.none; }
    if !matched { return false, Error.none; }
    return self.recordValueAnchorIds(anchors, scratch.anchor_ids.items);
}
fn admitOperation<G>(self: Importer&, g: G&, id: u32) -> bool, Error {
    let error = self.operationScope(g, id);
    if error == Error.out_of_memory { return false, error; }
    return error == Error.none, Error.none;
}
fn indexOperations(self: Importer&) -> Error {
    if self.operations_indexed { return Error.none; }
    assert(self.old);
    let labels = unit_words.alloc_slice(self.old.operations.len); for &label in labels { label = 0; }
    let scopes = operation_scope_runs.alloc_slice(labels.len); for &scope in scopes { scope = OperationScope.unchecked; }
    var symbols = TextMap {..};
    let error = self.indexOperationLabels(labels, symbols); symbols.deinit();
    if error != Error.none {
        if labels.len != 0 { unit_words.free_slice(labels); operation_scope_runs.free_slice(scopes); }
        return error;
    }
    self.operation_labels = labels; self.operation_scopes = scopes; self.operations_indexed = true;
    return Error.none;
}
fn indexOperationLabels(self: const Importer&, labels: u32[:], symbols: TextMap&) -> Error {
    assert(self.old);
    for operation, index in self.old.operations {
        if operation.key.len < 2 || operation.key[0] != 1 || operation.key[1] != 'P' { continue; }
        if symbols.contains(operation.key) { return Error.declined; }
        symbols.insert(operation.key, index as u32);
    }
    if !self.old.identity.present { return Error.declined; }
    var entries: blot_backend_runtime_operations::Entry[>..<] = []; var bytes: u8[>..<] = [];
    var keys: dictionary<u64,u32>; var relocations: blot_backend_runtime_operations::Relocation[>..<] = [];
    var scratch = blot_backend_runtime_operations::initProject(entries, bytes, keys, relocations, self.old.identity.value.view());
    let view = self.old.evaluator.evidence.view(); var failure = Error.none;
    for label in 1..view.effects.operations.len {
        let candidate, error = scratch.intern(view, label as u32);
        if error == Error.out_of_memory { failure = error; break; }
        if error != Error.none { continue; }
        let index = symbols.get(scratch.key(scratch.entries[candidate - 1]));
        if index && labels[index] == 0 { labels[index] = label as u32; }
    }
    scratch.deinit(); return failure;
}
fn operationScope<G>(self: Importer&, g: G&, id: u32) -> Error {
    let bound = self.bind(g); if bound != Error.none { return bound; }
    assert(self.old);
    if id == 0 || id > self.old.operations.len { return Error.declined; }
    let indexed = self.indexOperations(); if indexed != Error.none { return indexed; }
    match self.operation_scopes[id - 1] {
        OperationScope.admitted => { return Error.none; },
        OperationScope.declined => { return Error.declined; },
        OperationScope.unchecked => {},
    }
    let error = self.qualifyOperation(g, id);
    if error != Error.none {
        if error == Error.declined { self.operation_scopes[id - 1] = OperationScope.declined; }
        return error;
    }
    self.operation_scopes[id - 1] = OperationScope.admitted; return Error.none;
}
fn qualifyOperation<G>(self: Importer&, g: G&, id: u32) -> Error {
    assert(self.old);
    let label = self.operation_labels[id - 1]; if label == 0 { return Error.declined; }
    let operation = self.old.operations[id - 1]; let view = self.old.evaluator.evidence.view(); let producer = view.effects.operations[label];
    let arguments, error = bounded(view.effects.arguments, producer.arguments.start, producer.arguments.len);
    if error != Error.none { return error; }
    if producer.identity.unit == 0 {
        if producer.identity.decl != 1 || arguments.len != 0 || !operation.foreign { return Error.declined; }
    } else {
        let mapped, failure = self.nominal(producer.identity.unit, producer.identity.decl); if failure != Error.none { return failure; }
        if operation.foreign { return Error.declined; }
    }
    for argument in arguments { let mapped, failure = self.semanticType(g, argument, 0); if failure != Error.none { return failure; } }
    return Error.none;
}

recursive fn principalType(self: const Importer&, id: u32, depth: i64, remaining: i64&) -> Error {
    assert(self.old);
    if depth >= depth_limit || remaining == 0 || id == 0 || id >= self.old.evaluator.evidence.nodes.len { return Error.declined; }
    remaining--; let node = self.old.evaluator.evidence.nodes[id];
    match node.tag {
        EvidenceTag.projection, EvidenceTag.scoped, EvidenceTag.forall, EvidenceTag.existential, EvidenceTag.bound, EvidenceTag.usage, EvidenceTag.absent, EvidenceTag.provider, EvidenceTag.state_provider, EvidenceTag.resolver, EvidenceTag.type_constructor, EvidenceTag.erased_proof => { return Error.declined; },
        EvidenceTag.unit, EvidenceTag.boolean, EvidenceTag.unsigned32, EvidenceTag.floating32, EvidenceTag.never => { if node.a != 0 || node.b != 0 || node.c != 0 { return Error.declined; } },
        EvidenceTag.array, EvidenceTag.list, EvidenceTag.cursor => { if node.b != 0 || node.c != 0 { return Error.declined; } { let propagated_error = self.principalType(node.a, depth + 1, remaining); if propagated_error != Error.none { return propagated_error; } } },
        EvidenceTag.function => {
            { let propagated_error = self.principalType(node.a, depth + 1, remaining); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.principalType(node.b, depth + 1, remaining); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = self.principalRow(node.c, depth + 1, remaining); if propagated_error != Error.none { return propagated_error; } }
        },
        EvidenceTag.product, EvidenceTag.record, EvidenceTag.nominal => {
            if node.tag == EvidenceTag.nominal {
                if node.a == 0xffffffff || node.b == 0 { return Error.declined; }
                let unit, error = self.unit(node.a, true); if error != Error.none { return error; }
                let decl, failure = self.nominalDeclaration(node.b); if failure != Error.none { return failure; }
                let current .= self.units[unit - 1]; var found = false;
                for nominal in current.nominals {
                    if nominal.identity.decl == decl && (nominal.identity.unit == 0 || nominal.identity.unit == current.unit || nominal.identity.unit == self.unit_map[node.a - 1]) { found = true; break; }
                }
                if !found { return Error.declined; }
            } else if node.c != 0 { return Error.declined; }
            let children, error = evidenceChildren(self.old.evaluator.evidence.view(), id); if error != Error.none { return error; }
            for child, index in children {
                if node.tag == EvidenceTag.record && index % 2 == 0 { let symbol, failure = self.symbol(child); if failure != Error.none { return failure; } }
                else { { let propagated_error = self.principalType(child, depth + 1, remaining); if propagated_error != Error.none { return propagated_error; } } }
            }
            if node.tag == EvidenceTag.record { { let propagated_error = uniqueFields(children); if propagated_error != Error.none { return propagated_error; } } }
        },
    }
    return Error.none;
}
recursive fn principalRow(self: const Importer&, id: u32, depth: i64, remaining: i64&) -> Error {
    assert(self.old); let source = self.old.evaluator.evidence.effects.view();
    if depth >= depth_limit || remaining == 0 || id >= source.rows.len { return Error.declined; }
    remaining--; let span = source.rows[id];
    let labels, error = bounded(source.labels, span.start, span.len); if error != Error.none { return error; }
    if id == 0 && labels.len != 0 { return Error.declined; }
    for label in labels {
        if label == 0 || label >= source.operations.len { return Error.declined; }
        let operation = source.operations[label];
        if operation.instance.unit != 0 || operation.instance.decl != 0 || operation.identity.unit == 0xffffffff { return Error.declined; }
        let arguments, failure = bounded(source.arguments, operation.arguments.start, operation.arguments.len); if failure != Error.none { return failure; }
        if operation.identity.unit == 0 { if operation.identity.decl != 1 || arguments.len != 0 { return Error.declined; } }
        else { let owner, invalid = self.nominal(operation.identity.unit, operation.identity.decl); if invalid != Error.none { return invalid; } }
        for argument in arguments { { let propagated_error = self.principalType(argument, depth + 1, remaining); if propagated_error != Error.none { return propagated_error; } } }
    }
    return Error.none;
}
fn validatePrincipalMappings(self: const Importer&, owner: u32, types: const blot_eval_type_evidence::Mapping[:], rows: const blot_eval_type_evidence::RowMapping[:]) -> Error {
    let module, old_error = self.oldModule(owner); if old_error != Error.none { return old_error; } assert(module);
    let unit, error = self.unit(owner, true); if error != Error.none { return error; }
    let current .= self.units[unit - 1]; var remaining: i64 = 1000000;
    for mapping, index in types {
        if mapping.variable == 0 || mapping.variable >= module.types.nodes.len || mapping.variable >= current.types.nodes.len || module.types.nodes[mapping.variable].tag != blot_check_types::Tag.variable || current.types.nodes[mapping.variable].tag != blot_check_types::Tag.variable { return Error.declined; }
        for previous in types[..index] { if previous.variable == mapping.variable { return Error.declined; } }
        { let propagated_error = self.principalType(mapping.evidence, 0, remaining); if propagated_error != Error.none { return propagated_error; } }
    }
    for mapping, index in rows {
        if mapping.variable >= module.types.effects.variable_count || mapping.variable >= current.types.effects.variable_count { return Error.declined; }
        for previous in rows[..index] { if previous.variable == mapping.variable { return Error.declined; } }
        { let propagated_error = self.principalRow(mapping.evidence, 0, remaining); if propagated_error != Error.none { return propagated_error; } }
    }
    return Error.none;
}
fn principalEvidenceInto<G>(self: Importer&, g: G&, imported: blot_eval_core_eval::SolvedEvidence&) -> Error {
    for &mapping in imported.types { let evidence, error = self.semanticType(g, mapping.evidence, 0); if error != Error.none { return error; } mapping.evidence = evidence; }
    for &mapping in imported.rows { let evidence, error = self.row(g, Domain.semantic, mapping.evidence, 0); if error != Error.none { return error; } mapping.evidence = evidence; }
    return Error.none;
}
fn importPrincipalEvidence<G>(self: Importer&, g: G&, owner: u32, types: const blot_eval_type_evidence::Mapping[:], rows: const blot_eval_type_evidence::RowMapping[:]) -> blot_support::Option<blot_eval_core_eval::SolvedEvidence>, Error {
    let no = blot_support::none<blot_eval_core_eval::SolvedEvidence>();
    let bound = self.bind(g); if bound != Error.none { return optionalImported(default<blot_eval_core_eval::SolvedEvidence>(), bound); }
    let validated = self.validatePrincipalMappings(owner, types, rows);
    if validated != Error.none { return optionalImported(default<blot_eval_core_eval::SolvedEvidence>(), validated); }
    var imported = blot_eval_core_eval::SolvedEvidence { blot_eval_core_eval::copySolvedTypes(types), blot_eval_core_eval::copySolvedRows(rows) , ..};
    let error = self.principalEvidenceInto(g, imported);
    if error != Error.none { imported.deinit(); return optionalImported(default<blot_eval_core_eval::SolvedEvidence>(), error); }
    return blot_support::some(imported), Error.none;
}
fn importPrincipalInput<G>(self: Importer&, g: G&, actual: u32) -> blot_support::Option<u32>, Error {
    let bound = self.bind(g); if bound != Error.none { return optionalImported(0 as u32, bound); }
    var remaining: i64 = 1000000; let checked = self.principalType(actual, 0, remaining);
    if checked != Error.none { return optionalImported(0 as u32, checked); }
    assert(self.old);
    if self.old.evaluator.evidence.nodes[actual].tag != EvidenceTag.product { return blot_support::none<u32>(), Error.none; }
    let value, error = self.semanticType(g, actual, 0); return optionalImported(value, error);
}
fn importPrincipalCall<G>(self: Importer&, g: G&, reference: blot_check_core::BindingRef, actual: u32) -> blot_support::Option<u32>, Error {
    let bound = self.bind(g); if bound != Error.none { return optionalImported(0 as u32, bound); }
    let previous, old_error = self.oldModule(reference.unit); if old_error != Error.none { return optionalImported(0 as u32, old_error); } assert(previous);
    let unit, invalid = self.unit(reference.unit, true); if invalid != Error.none { return optionalImported(0 as u32, invalid); }
    let current .= self.units[unit - 1];
    if reference.binding == 0 || reference.binding >= previous.bindings.len || reference.binding >= current.bindings.len || previous.binding(reference.binding).kind != blot_check_check::Kind.global || current.binding(reference.binding).kind != blot_check_check::Kind.global || !previous.body(reference.binding) || !current.body(reference.binding) { return blot_support::none<u32>(), Error.none; }
    var remaining: i64 = 1000000; let checked = self.principalType(actual, 0, remaining);
    if checked != Error.none { return optionalImported(0 as u32, checked); }
    assert(self.old);
    if self.old.evaluator.evidence.nodes[actual].tag != EvidenceTag.function { return blot_support::none<u32>(), Error.none; }
    let value, error = self.semanticType(g, actual, 0); return optionalImported(value, error);
}
fn importSemanticSite<G>(self: Importer&, g: G&, site: blot_backend_wasm::SemanticSite) -> blot_support::Option<blot_backend_wasm::SemanticSite>, Error {
    let value, error = self.semanticSite(g, site); return optionalImported(value, error);
}

fn semanticSite<G>(self: Importer&, g: G&, site: blot_backend_wasm::SemanticSite) -> blot_backend_wasm::SemanticSite, Error {
    { let import_error_1 = self.bind(g); if import_error_1 != Error.none { return default<blot_backend_wasm::SemanticSite>(), convert(import_error_1); } }
    if site.node == 0 || site.root == 0 { return default<blot_backend_wasm::SemanticSite>(), Error.declined; }
    let unit, import_error_2 = self.expressionUnit(site.unit, site.root); if import_error_2 != Error.none { return default<blot_backend_wasm::SemanticSite>(), convert(import_error_2); }
    let source, import_error_3 = self.oldModule(site.unit); if import_error_3 != Error.none { return default<blot_backend_wasm::SemanticSite>(), convert(import_error_3); } assert(source);
    if site.node >= source.nodes.len || site.root >= source.nodes.len || site.node >= self.units[unit - 1].nodes.len || site.root >= self.units[unit - 1].nodes.len { return default<blot_backend_wasm::SemanticSite>(), Error.declined; }
    if !self.stable[site.unit - 1] {
        let key = ExpressionKey { site.unit, site.root , ..};
        var nodes: const u32[:] = [];
        let known = self.expression_nodes.get(key);
        if known { nodes = known; }
        else {
            let proved, import_error_4 = blot_reuse_declaration_projection::expressionNodes(source, self.units[unit - 1], site.root); if import_error_4 != Error.none { return default<blot_backend_wasm::SemanticSite>(), convert(import_error_4); }
            if !proved.present { return default<blot_backend_wasm::SemanticSite>(), Error.declined; }
            self.expression_nodes.insert(key, proved.value); nodes = proved.value;
        }
        var low: i64 = 0; var high = nodes.len;
        while low < high { let middle = low + (high - low) / 2; if nodes[middle] < site.node { low = middle + 1; } else { high = middle; } }
        if low == nodes.len || nodes[low] != site.node { return default<blot_backend_wasm::SemanticSite>(), Error.declined; }
    }
    var result = site; result.unit = unit;
    { let imported_5, import_error_5 = self.mappingEvidence(g, site.unit, site.mappings, 0); if import_error_5 != Error.none { return default<blot_backend_wasm::SemanticSite>(), convert(import_error_5); } result.mappings = imported_5; }
    { let imported_6, import_error_6 = self.rowKey(g, site.unit, site.rows, 0); if import_error_6 != Error.none { return default<blot_backend_wasm::SemanticSite>(), convert(import_error_6); } result.rows = imported_6; }
    return result, Error.none;
}
reusable[] var solved_layouts: blot_backend_layout::Mapping[>..] = [];
reusable[] var solved_layout_rows: blot_backend_layout::RowMapping[>..] = [];
reusable[] var solved_templates: blot_reuse_substitution_keys::Entry[>..] = [];
fn deinit(self: Solved&) {
    if self.mappings.len != 0 { solved_layouts.free_slice(self.mappings); }
    if self.rows.len != 0 { solved_layout_rows.free_slice(self.rows); }
    if self.templates.len != 0 { solved_templates.free_slice(self.templates); }
    self = Solved {..};
}
// Job tables retain typed ranges, so the source journal accompanies its header.
fn importSolved<G>(self: Importer&, g: G&, job: const blot_reuse_code_artifacts::Job&, source: const blot_reuse_code_artifacts::Context&) -> blot_support::Option<Solved>, Error {
    let bound = self.bind(g); if bound != Error.none { return optionalImported(Solved {..}, bound); }
    if !job.solved || job.state != blot_reuse_code_artifacts::State.complete { return blot_support::none<Solved>(), Error.none; }
    var owner: u32 = 0;
    match job.request {
        blot_reuse_code_artifacts::Request.named key => { owner = key.key.target.unit; },
        blot_reuse_code_artifacts::Request.closure key => { owner = key.key.unit; },
        _ => { return blot_support::none<Solved>(), Error.none; },
    }
    let module, invalid = self.oldModule(owner); if invalid != Error.none { return optionalImported(Solved {..}, invalid); } assert(module);
    let mappings, mapping_error = bounded(source.mappings.items, job.mappings.start, job.mappings.len);
    if mapping_error != Error.none { return optionalImported(Solved {..}, mapping_error); }
    let rows, row_error = bounded(source.rows.items, job.rows.start, job.rows.len);
    if row_error != Error.none { return optionalImported(Solved {..}, row_error); }
    let templates, template_error = bounded(source.templates.items, job.templates.start, job.templates.len);
    if template_error != Error.none { return optionalImported(Solved {..}, template_error); }
    var result = Solved { solved_layouts.alloc_slice(mappings.len), solved_layout_rows.alloc_slice(rows.len), solved_templates.alloc_slice(templates.len) , ..};
    let error = self.importSolvedInto(g, module, mappings, rows, templates, result);
    if error != Error.none { result.deinit(); return optionalImported(Solved {..}, error); }
    return blot_support::some(result), Error.none;
}
fn importSolvedInto<G>(self: Importer&, g: G&, module: const Module&, mappings: const blot_backend_layout::Mapping[:], rows: const blot_backend_layout::RowMapping[:], templates: const blot_reuse_substitution_keys::Entry[:], result: Solved&) -> Error {
    for from, index in mappings {
        if from.variable == 0 || from.variable >= module.types.nodes.len { return Error.declined; }
        for prior in mappings[..index] { if prior.variable == from.variable { return Error.declined; } }
        let layout, error = self.closedShape(g, from.layout); if error != Error.none { return error; }
        result.mappings[index] = blot_backend_layout::Mapping { variable: from.variable, layout: layout, instance: blot_check_types::NominalIdentity { 0, 0 , ..} , ..};
    }
    for from, index in rows {
        if from.variable >= module.types.effects.variable_count || from.row == blot_backend_layout::unknown_row { return Error.declined; }
        for prior in rows[..index] { if prior.variable == from.variable { return Error.declined; } }
        let row, error = self.row(g, Domain.layout, from.row, 0); if error != Error.none { return error; }
        result.rows[index] = blot_backend_layout::RowMapping { from.variable, row , ..};
        let known, failure = self.knowledge.knownRow(g.representations.store, row);
        if failure != Error.none { return failure; } if !known { return Error.declined; }
    }
    for from, index in templates {
        if from.variable == 0 || from.variable >= module.bindings.len { return Error.declined; }
        for prior in templates[..index] { if prior.variable == from.variable { return Error.declined; } }
        let value, error = self.capture(g, from.value, 0); if error != Error.none { return error; }
        result.templates[index] = blot_reuse_substitution_keys::Entry { from.variable, value , ..};
    }
    return Error.none;
}
