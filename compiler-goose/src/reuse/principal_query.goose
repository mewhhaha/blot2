// A source principal proof is distinct from a selected specialization.
namespace blot_reuse_principal_query;
import check.core;
import eval.core_eval;
import reuse.principal_inputs;
import reuse.semantic_query_table;
import support.error;
import support.host_layout;
import support.option;
import support.wyhash;
import support.structural;
type Error = blot_error::Error;
struct Key { target: blot_check_core::BindingRef, options: blot_eval_core_eval::Options }
fn deinit(self_: Key&) {}
struct Dependencies { inputs: blot_support::Option<blot_reuse_principal_inputs::Key> }
fn deinit(self_: Dependencies&) { if self_.inputs.present { self_.inputs.value.deinit(); self_.inputs.present = false; } }
struct Adapter {}
type Value = blot_eval_core_eval::SolvedEvidence;
type Record = blot_reuse_semantic_query_table::OwnedRecord<Key,Dependencies,Value,Adapter>;
type Table = blot_reuse_semantic_query_table::Table<Key,Dependencies,Value,Adapter>;
type Builder = blot_reuse_semantic_query_table::Builder<Key,Dependencies,Value,Adapter>;
type Candidate = blot_reuse_semantic_query_table::Candidate<Key,Dependencies,Value,Adapter>;
let kind = blot_reuse_semantic_query_table::Kind.principal;
fn fingerprint(target: blot_check_core::BindingRef) -> u64 {
    var hash = blot_support_wyhash::init(0); hash.value(target.unit); hash.value(target.binding); return hash.final();
}
fn fingerprint(self_: Adapter, key: Key) -> u64 { fingerprint(key.target) }
fn complete(self_: Adapter, record: Record) -> bool { record.value.selected.len == 0 }
fn addBytes(total: i64&, bytes: i64) {
    if bytes > 9223372036854775807 - total { total = 9223372036854775807; }
    else { total += bytes; }
}
fn bytes(self_: Adapter, record: Record) -> i64 {
    var total: i64 = 0;
    if record.dependencies.inputs.present {
        let observed = record.dependencies.inputs.value;
        addBytes(total, bytes_of(observed.interfaces).len); addBytes(total, bytes_of(observed.sources).len);
        addBytes(total, bytes_of(observed.source_units).len); addBytes(total, bytes_of(observed.scalar_reads).len);
        addBytes(total, bytes_of(observed.plain_reads).len); addBytes(total, bytes_of(observed.plain_publications).len);
        addBytes(total, bytes_of(observed.call_publications).len); addBytes(total, bytes_of(observed.call_reads).len);
        addBytes(total, bytes_of(observed.summary_reads).len); addBytes(total, bytes_of(observed.summary_publications).len);
    }
    addBytes(total, bytes_of(record.value.types).len); addBytes(total, bytes_of(record.value.rows).len);
    addBytes(total, bytes_of(record.value.selected).len); return total;
}
reusable[] var records: Record[>..] = [];
fn allocateRecords(self_: Adapter, len: i64) -> Record[:], Error { return records.alloc_slice(len), blot_error::Error.none; }
fn releaseRecords(self_: Adapter, items: const Record[:]) {
    if items.len == 0 { return; }
    records.free_slice(items);
}
fn recordBytes(self_: Adapter) -> i64 { blot_host_layout::principal_record }
fn init(limits: blot_reuse_semantic_query_table::Limits = blot_reuse_semantic_query_table::Limits {..}) -> Table {
    return blot_reuse_semantic_query_table::init<Key,Dependencies,Value,Adapter>(Adapter {..}, limits);
}

fn canonicalRecords(self_:Adapter,source:const Record[:])->Record[:] {return records.realloc_slice(source,source.len);}
fn canonicalRecord(self_:Adapter,source:Record)->Record {
 let value=blot_eval_core_eval::canonicalSolvedEvidence(source.value);
 if source.dependencies.inputs.present {
  return Record{source.key,Dependencies{blot_support::some<blot_reuse_principal_inputs::Key>(blot_reuse_principal_inputs::canonicalOwned(source.dependencies.inputs.value))},value};
 }
 return Record{source.key,Dependencies{blot_support::none<blot_reuse_principal_inputs::Key>()},value};
}
