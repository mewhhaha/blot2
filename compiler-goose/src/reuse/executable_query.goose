// Executable inquiries refer only to one immutable capture's owned graphs.
namespace blot_reuse_executable_query;
import reuse.semantic_query_table;
import reuse.code_artifacts;
import check.core;
import backend.wasm_lifetimes;
import compilation_tier;
import support.error;
import support.option;
import support.wyhash;
type Error = blot_error::Error;
fn dependencyBytes<L,R>(left: i64, right: i64) -> blot_support::Option<i64> {
    let left_width = bytes_of([default<L>()]).len; let right_width = bytes_of([default<R>()]).len;
    if left < 0 || right < 0 || left > 9223372036854775807 / left_width || right > 9223372036854775807 / right_width { return blot_support::none<i64>(); }
    let a = left * left_width; let b = right * right_width;
    if b > 9223372036854775807 - a { return blot_support::none<i64>(); } return blot_support::some(a + b);
}
struct FragmentKey { request: blot_reuse_code_artifacts::Request }
fn deinit(self_: FragmentKey&) {}
struct FragmentDependencies {
    inline_bodies: blot_check_core::BindingRef[:], static_reads: blot_reuse_code_artifacts::StaticRead[:],
    replay_job: u32, reusable_: bool,
}
struct FragmentResult { function: u32, job: u32 }
fn deinit(self_: FragmentResult&) {}
struct FragmentAdapter {}
type FragmentRecord = blot_reuse_semantic_query_table::OwnedRecord<FragmentKey,FragmentDependencies,FragmentResult,FragmentAdapter>;
type FragmentTable = blot_reuse_semantic_query_table::Table<FragmentKey,FragmentDependencies,FragmentResult,FragmentAdapter>;
reusable[] var body_reads: blot_check_core::BindingRef[>..] = [];
reusable[] var static_reads: blot_reuse_code_artifacts::StaticRead[>..] = [];
fn copyBodyReads(source: const blot_check_core::BindingRef[:]) -> blot_check_core::BindingRef[:] {
    if source.len == 0 { return default<blot_check_core::BindingRef[:]>(); } let out = body_reads.alloc_slice(source.len); for value, index in source { out[index] = value; } return out;
}
fn copyStaticReads(source: const blot_reuse_code_artifacts::StaticRead[:]) -> blot_reuse_code_artifacts::StaticRead[:] {
    if source.len == 0 { return default<blot_reuse_code_artifacts::StaticRead[:]>(); } let out = static_reads.alloc_slice(source.len); for value, index in source { out[index] = value; } return out;
}
fn deinit(self_: FragmentDependencies&) {
    if self_.inline_bodies.len != 0 { body_reads.free_slice(self_.inline_bodies); }
    if self_.static_reads.len != 0 { static_reads.free_slice(self_.static_reads); }
    self_.inline_bodies = []; self_.static_reads = [];
}
fn fragmentFingerprint(request: blot_reuse_code_artifacts::Request) -> u64 {
    var hash = blot_support_wyhash::init(0); hash.value(blot_reuse_code_artifacts::requestCode(request));
    match request {
        named item => { hash.value(item.key.target.unit); hash.value(item.key.target.binding); },
        closure item => { hash.value(item.key.unit); hash.value(item.key.catalog); }, _ => {},
    }
    return hash.final();
}
fn fingerprint(self_: FragmentAdapter, key: FragmentKey) -> u64 { fragmentFingerprint(key.request) }
fn complete(self_: FragmentAdapter, record: FragmentRecord) -> bool {
    var candidate = false;
    match record.key.request { named, closure => { candidate = true; }, _ => {} }
    return candidate && record.dependencies.reusable_ && record.value.job != 0 && record.dependencies.replay_job == record.value.job;
}
fn bytes(self_: FragmentAdapter, record: FragmentRecord) -> i64 {
    let size = dependencyBytes<blot_check_core::BindingRef,blot_reuse_code_artifacts::StaticRead>(record.dependencies.inline_bodies.len, record.dependencies.static_reads.len);
    if size.present { return size.value; } return 9223372036854775807;
}
reusable[] var fragment_records: FragmentRecord[>..] = [];
fn allocateRecords(self_: FragmentAdapter, len: i64) -> FragmentRecord[:], Error { return fragment_records.alloc_slice(len), blot_error::Error.none; }
fn releaseRecords(self_: FragmentAdapter, source: const FragmentRecord[:]) {
    if source.len == 0 { return; } fragment_records.free_slice(source);
}
// Request is its u8 tag plus max payload Key (151 packed bytes).
fn recordBytes(self_: FragmentAdapter) -> i64 { return 152 + 2 * 16 + 4 + 1 + 8; }
fn initFragments(limits: blot_reuse_semantic_query_table::Limits = blot_reuse_semantic_query_table::Limits { records: 16384, retained_capacity: 8388608 , ..}) -> FragmentTable {
    return blot_reuse_semantic_query_table::init<FragmentKey,FragmentDependencies,FragmentResult,FragmentAdapter>(FragmentAdapter {..}, limits);
}
struct OptimizerKey { local_fingerprint: u64, tier: blot_compilation_tier::Tier }
fn deinit(self_: OptimizerKey&) {}
struct OptimizerDependencies {
    callees: u32[:], parameters: blot_backend_wasm_lifetimes::Parameter[:], invalidates: bool,
    owned_result_bytes: blot_support::Option<u32>, context_complete: bool,
}
struct OptimizerResult { function: u32, ready: bool }
fn deinit(self_: OptimizerResult&) {}
struct OptimizerAdapter {}
type OptimizerRecord = blot_reuse_semantic_query_table::OwnedRecord<OptimizerKey,OptimizerDependencies,OptimizerResult,OptimizerAdapter>;
type OptimizerTable = blot_reuse_semantic_query_table::Table<OptimizerKey,OptimizerDependencies,OptimizerResult,OptimizerAdapter>;
reusable[] var callees: u32[>..] = [];
reusable[] var parameters: blot_backend_wasm_lifetimes::Parameter[>..] = [];
reusable[] var optimizer_records: OptimizerRecord[>..] = [];
fn copyCallees(source: const u32[:]) -> u32[:] {
    if source.len == 0 { return default<u32[:]>(); } let out = callees.alloc_slice(source.len); for value, index in source { out[index] = value; } return out;
}
fn copyParameters(source: const blot_backend_wasm_lifetimes::Parameter[:]) -> blot_backend_wasm_lifetimes::Parameter[:] {
    if source.len == 0 { return default<blot_backend_wasm_lifetimes::Parameter[:]>(); } let out = parameters.alloc_slice(source.len); for value, index in source { out[index] = value; } return out;
}
fn deinit(self_: OptimizerDependencies&) {
    if self_.callees.len != 0 { callees.free_slice(self_.callees); }
    if self_.parameters.len != 0 { parameters.free_slice(self_.parameters); }
    self_.callees = []; self_.parameters = [];
}
fn fingerprint(self_: OptimizerAdapter, key: OptimizerKey) -> u64 { key.local_fingerprint }
fn complete(self_: OptimizerAdapter, record: OptimizerRecord) -> bool { record.value.ready && record.dependencies.context_complete }
fn bytes(self_: OptimizerAdapter, record: OptimizerRecord) -> i64 {
    let size = dependencyBytes<u32,blot_backend_wasm_lifetimes::Parameter>(record.dependencies.callees.len, record.dependencies.parameters.len);
    if size.present { return size.value; } return 9223372036854775807;
}
fn allocateRecords(self_: OptimizerAdapter, len: i64) -> OptimizerRecord[:], Error { return optimizer_records.alloc_slice(len), blot_error::Error.none; }
fn releaseRecords(self_: OptimizerAdapter, source: const OptimizerRecord[:]) {
    if source.len == 0 { return; } optimizer_records.free_slice(source);
}
fn recordBytes(self_: OptimizerAdapter) -> i64 { return 8 + 1 + 2 * 16 + 1 + 5 + 1 + 4 + 1; }
fn initOptimizer(limits: blot_reuse_semantic_query_table::Limits = blot_reuse_semantic_query_table::Limits {..}) -> OptimizerTable {
    return blot_reuse_semantic_query_table::init<OptimizerKey,OptimizerDependencies,OptimizerResult,OptimizerAdapter>(OptimizerAdapter {..}, limits);
}
