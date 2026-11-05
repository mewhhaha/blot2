// Declaration-only recipes never retain a caller's substitution or value facts.
namespace blot_backend_storage_field_plan;
import dictionary;
import check.core;
import check.types;
import support.option;
import support.pooled_map;
import support.error;
struct Recipe { index: u32,ty: blot_check_types::Id }
struct Key { query_unit: u32,query_symbol: u32,receiver_unit: u32,record: blot_check_types::Id }
fn hash(key: Key) -> u64 { ::hash((key.query_unit as u64 << 32) | key.query_symbol) ^ ::hash((key.receiver_unit as u64 << 32) | key.record) }
reusable[] var entry_slots: dictionary_slot<Key,blot_support::Option<Recipe>>[>..] = [];
struct Cache { entries: blot_support_pooled_map::Map<Key,blot_support::Option<Recipe>>,maximum_entries: i64 = 65536,hits: u64 = 0,misses: u64 = 0,probes: u64 = 0 }
fn init() -> Cache { Cache {} }
fn deinit(cache: Cache&) { blot_support_pooled_map::deinit(cache.entries,entry_slots); }
fn increase(value: u64&) { if value != 18446744073709551615 { value++; } }
fn get(cache: Cache&,query: const blot_check_core::Module&,name: u32,owner: const blot_check_core::Module&,record: u32) -> blot_support::Option<Recipe>,blot_error::Error {
    let key = Key { query_unit: query.unit,query_symbol: name,receiver_unit: owner.unit,record }; let existing .= blot_support_pooled_map::get(cache.entries,key); if existing { increase(cache.hits); return existing,blot_error::Error.none; } increase(cache.misses); let recipe = lookup(cache,query,name,owner,record); if cache.entries.count < cache.maximum_entries { blot_support_pooled_map::insert(cache.entries,key,recipe,entry_slots); } return recipe,blot_error::Error.none;
}
fn lookup(cache: Cache&,query: const blot_check_core::Module&,name: u32,owner: const blot_check_core::Module&,record: u32) -> blot_support::Option<Recipe> {
    let node = owner.types.node(record); if node.tag != blot_check_types::Tag.record { return blot_support::none<Recipe>(); } let spelling = query.fieldSpelling(name); if !spelling.present { return blot_support::none<Recipe>(); }
    for index in 0..node.b { increase(cache.probes); let field = owner.types.recordField(node,index); let candidate = owner.fieldSpelling(field.name); if !candidate.present { continue; } if spelling.value == candidate.value { return blot_support::some(Recipe { index: index as u32,ty: field.ty }); } } return blot_support::none<Recipe>();
}
