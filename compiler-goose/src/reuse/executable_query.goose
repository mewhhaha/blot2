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
fn deinit(self: FragmentKey&) {}
struct FragmentDependencies {
    inline_bodies: blot_check_core::BindingRef[:], static_reads: blot_reuse_code_artifacts::StaticRead[:],
    replay_job: u32, reusable: bool,
}
struct FragmentResult { function: u32, job: u32 }
fn deinit(self: FragmentResult&) {}
struct FragmentAdapter {}
type FragmentRecord = blot_reuse_semantic_query_table::OwnedRecord<FragmentKey,FragmentDependencies,FragmentResult,FragmentAdapter>;
type FragmentTable = blot_reuse_semantic_query_table::Table<FragmentKey,FragmentDependencies,FragmentResult,FragmentAdapter>;
reusable[] var body_reads: blot_check_core::BindingRef[>..] = [];
reusable[] var static_reads: blot_reuse_code_artifacts::StaticRead[>..] = [];
fn copyBodyReads(source: const blot_check_core::BindingRef[:]) -> blot_check_core::BindingRef[:] {
    if source.len == 0 { return []; } let out = body_reads.alloc_slice(source.len); for value, index in source { out[index] = value; } return out;
}
fn copyStaticReads(source: const blot_reuse_code_artifacts::StaticRead[:]) -> blot_reuse_code_artifacts::StaticRead[:] {
    if source.len == 0 { return []; } let out = static_reads.alloc_slice(source.len); for value, index in source { out[index] = value; } return out;
}
fn deinit(self: FragmentDependencies&) {
    if self.inline_bodies.len != 0 { let first: const blot_check_core::BindingRef& = self.inline_bodies[0]; let at = body_reads.index_of(first); body_reads.free_slice(body_reads[at..at + self.inline_bodies.len]); }
    if self.static_reads.len != 0 { let first: const blot_reuse_code_artifacts::StaticRead& = self.static_reads[0]; let at = static_reads.index_of(first); static_reads.free_slice(static_reads[at..at + self.static_reads.len]); }
    self.inline_bodies = []; self.static_reads = [];
}
fn fragmentFingerprint(request: blot_reuse_code_artifacts::Request) -> u64 {
    var hash = blot_support_wyhash::init(0); hash.value(blot_reuse_code_artifacts::requestCode(request));
    match request {
        blot_reuse_code_artifacts::Request.named item => { hash.value(item.key.target.unit); hash.value(item.key.target.binding); },
        blot_reuse_code_artifacts::Request.closure item => { hash.value(item.key.unit); hash.value(item.key.catalog); }, _ => {},
    }
    return hash.final();
}
fn fingerprint(self: FragmentAdapter, key: FragmentKey) -> u64 { fragmentFingerprint(key.request) }
fn complete(self: FragmentAdapter, record: FragmentRecord) -> bool {
    var candidate = false;
    match record.key.request { blot_reuse_code_artifacts::Request.named, blot_reuse_code_artifacts::Request.closure => { candidate = true; }, _ => {} }
    return candidate && record.dependencies.reusable && record.value.job != 0 && record.dependencies.replay_job == record.value.job;
}
fn bytes(self: FragmentAdapter, record: FragmentRecord) -> i64 {
    let size = dependencyBytes<blot_check_core::BindingRef,blot_reuse_code_artifacts::StaticRead>(record.dependencies.inline_bodies.len, record.dependencies.static_reads.len);
    if size.present { return size.value; } return 9223372036854775807;
}
reusable[] var fragment_records: FragmentRecord[>..] = [];
fn allocateRecords(self: FragmentAdapter, len: i64) -> FragmentRecord[:], Error { return fragment_records.alloc_slice(len), Error.none; }
fn releaseRecords(self: FragmentAdapter, source: const FragmentRecord[:]) {
    if source.len == 0 { return; } let first: const FragmentRecord& = source[0]; let at = fragment_records.index_of(first); fragment_records.free_slice(fragment_records[at..at + source.len]);
}
// Request is its u8 tag plus max payload Key (151 packed bytes).
fn recordBytes(self: FragmentAdapter) -> i64 { return 152 + 2 * 16 + 4 + 1 + 8; }
fn initFragments(limits: blot_reuse_semantic_query_table::Limits = blot_reuse_semantic_query_table::Limits { records: 16384, retained_capacity: 8388608 }) -> FragmentTable {
    return blot_reuse_semantic_query_table::init<FragmentKey,FragmentDependencies,FragmentResult,FragmentAdapter>(FragmentAdapter {}, limits);
}
struct OptimizerKey { local_fingerprint: u64, tier: blot_compilation_tier::Tier }
fn deinit(self: OptimizerKey&) {}
struct OptimizerDependencies {
    callees: u32[:], parameters: blot_backend_wasm_lifetimes::Parameter[:], invalidates: bool,
    owned_result_bytes: blot_support::Option<u32>, context_complete: bool,
}
struct OptimizerResult { function: u32, ready: bool }
fn deinit(self: OptimizerResult&) {}
struct OptimizerAdapter {}
type OptimizerRecord = blot_reuse_semantic_query_table::OwnedRecord<OptimizerKey,OptimizerDependencies,OptimizerResult,OptimizerAdapter>;
type OptimizerTable = blot_reuse_semantic_query_table::Table<OptimizerKey,OptimizerDependencies,OptimizerResult,OptimizerAdapter>;
reusable[] var callees: u32[>..] = [];
reusable[] var parameters: blot_backend_wasm_lifetimes::Parameter[>..] = [];
reusable[] var optimizer_records: OptimizerRecord[>..] = [];
fn copyCallees(source: const u32[:]) -> u32[:] {
    if source.len == 0 { return []; } let out = callees.alloc_slice(source.len); for value, index in source { out[index] = value; } return out;
}
fn copyParameters(source: const blot_backend_wasm_lifetimes::Parameter[:]) -> blot_backend_wasm_lifetimes::Parameter[:] {
    if source.len == 0 { return []; } let out = parameters.alloc_slice(source.len); for value, index in source { out[index] = value; } return out;
}
fn deinit(self: OptimizerDependencies&) {
    if self.callees.len != 0 { let first: const u32& = self.callees[0]; let at = callees.index_of(first); callees.free_slice(callees[at..at + self.callees.len]); }
    if self.parameters.len != 0 { let first: const blot_backend_wasm_lifetimes::Parameter& = self.parameters[0]; let at = parameters.index_of(first); parameters.free_slice(parameters[at..at + self.parameters.len]); }
    self.callees = []; self.parameters = [];
}
fn fingerprint(self: OptimizerAdapter, key: OptimizerKey) -> u64 { key.local_fingerprint }
fn complete(self: OptimizerAdapter, record: OptimizerRecord) -> bool { record.value.ready && record.dependencies.context_complete }
fn bytes(self: OptimizerAdapter, record: OptimizerRecord) -> i64 {
    let size = dependencyBytes<u32,blot_backend_wasm_lifetimes::Parameter>(record.dependencies.callees.len, record.dependencies.parameters.len);
    if size.present { return size.value; } return 9223372036854775807;
}
fn allocateRecords(self: OptimizerAdapter, len: i64) -> OptimizerRecord[:], Error { return optimizer_records.alloc_slice(len), Error.none; }
fn releaseRecords(self: OptimizerAdapter, source: const OptimizerRecord[:]) {
    if source.len == 0 { return; } let first: const OptimizerRecord& = source[0]; let at = optimizer_records.index_of(first); optimizer_records.free_slice(optimizer_records[at..at + source.len]);
}
fn recordBytes(self: OptimizerAdapter) -> i64 { return 8 + 1 + 2 * 16 + 1 + 5 + 1 + 4 + 1; }
fn initOptimizer(limits: blot_reuse_semantic_query_table::Limits = blot_reuse_semantic_query_table::Limits {}) -> OptimizerTable {
    return blot_reuse_semantic_query_table::init<OptimizerKey,OptimizerDependencies,OptimizerResult,OptimizerAdapter>(OptimizerAdapter {}, limits);
}
