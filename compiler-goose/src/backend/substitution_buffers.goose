// Typed scratch leases for recursive specialization and code generation.
namespace blot_backend_substitution_buffers;
import .layout;
import eval.type_evidence;
import eval.core_eval;
import reuse.substitution_keys;
import support.pooled_buffer;
import support.error;
type Error = blot_error::Error;
struct Mappings { storage: blot_backend_layout::Mapping[:] = [],items: blot_backend_layout::Mapping[:] = [] }
reusable[] var Mappings_runs: blot_backend_layout::Mapping[>..] = [];
fn push(buffer: Mappings&,value: blot_backend_layout::Mapping) -> Error { return blot_support_pooled_buffer::push(buffer,value,Mappings_runs); }
fn append(buffer: Mappings&,values: const blot_backend_layout::Mapping[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,Mappings_runs); }
fn clear(buffer: Mappings&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Mappings&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Mappings&) { blot_support_pooled_buffer::deinit(buffer,Mappings_runs); }
struct Rows { storage: blot_backend_layout::RowMapping[:] = [],items: blot_backend_layout::RowMapping[:] = [] }
reusable[] var Rows_runs: blot_backend_layout::RowMapping[>..] = [];
fn push(buffer: Rows&,value: blot_backend_layout::RowMapping) -> Error { return blot_support_pooled_buffer::push(buffer,value,Rows_runs); }
fn append(buffer: Rows&,values: const blot_backend_layout::RowMapping[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,Rows_runs); }
fn clear(buffer: Rows&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Rows&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Rows&) { blot_support_pooled_buffer::deinit(buffer,Rows_runs); }
struct EvidenceMappings { storage: blot_eval_type_evidence::Mapping[:] = [],items: blot_eval_type_evidence::Mapping[:] = [] }
reusable[] var EvidenceMappings_runs: blot_eval_type_evidence::Mapping[>..] = [];
fn push(buffer: EvidenceMappings&,value: blot_eval_type_evidence::Mapping) -> Error { return blot_support_pooled_buffer::push(buffer,value,EvidenceMappings_runs); }
fn append(buffer: EvidenceMappings&,values: const blot_eval_type_evidence::Mapping[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,EvidenceMappings_runs); }
fn clear(buffer: EvidenceMappings&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: EvidenceMappings&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: EvidenceMappings&) { blot_support_pooled_buffer::deinit(buffer,EvidenceMappings_runs); }
struct EvidenceRows { storage: blot_eval_type_evidence::RowMapping[:] = [],items: blot_eval_type_evidence::RowMapping[:] = [] }
reusable[] var EvidenceRows_runs: blot_eval_type_evidence::RowMapping[>..] = [];
fn push(buffer: EvidenceRows&,value: blot_eval_type_evidence::RowMapping) -> Error { return blot_support_pooled_buffer::push(buffer,value,EvidenceRows_runs); }
fn append(buffer: EvidenceRows&,values: const blot_eval_type_evidence::RowMapping[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,EvidenceRows_runs); }
fn clear(buffer: EvidenceRows&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: EvidenceRows&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: EvidenceRows&) { blot_support_pooled_buffer::deinit(buffer,EvidenceRows_runs); }
struct Words { storage: u32[:] = [],items: u32[:] = [] }
reusable[] var Words_runs: u32[>..] = [];
fn push(buffer: Words&,value: u32) -> Error { return blot_support_pooled_buffer::push(buffer,value,Words_runs); }
fn append(buffer: Words&,values: const u32[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,Words_runs); }
fn clear(buffer: Words&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Words&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Words&) { blot_support_pooled_buffer::deinit(buffer,Words_runs); }
struct Flags { storage: bool[:] = [],items: bool[:] = [] }
reusable[] var Flags_runs: bool[>..] = [];
fn push(buffer: Flags&,value: bool) -> Error { return blot_support_pooled_buffer::push(buffer,value,Flags_runs); }
fn append(buffer: Flags&,values: const bool[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,Flags_runs); }
fn clear(buffer: Flags&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Flags&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Flags&) { blot_support_pooled_buffer::deinit(buffer,Flags_runs); }

struct Hints { storage: blot_eval_core_eval::RetainedCapture[:] = [],items: blot_eval_core_eval::RetainedCapture[:] = [] }
reusable[] var Hints_runs: blot_eval_core_eval::RetainedCapture[>..] = [];
fn push(buffer: Hints&,value: blot_eval_core_eval::RetainedCapture) -> Error { return blot_support_pooled_buffer::push(buffer,value,Hints_runs); }
fn append(buffer: Hints&,values: const blot_eval_core_eval::RetainedCapture[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,Hints_runs); }
fn clear(buffer: Hints&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Hints&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Hints&) { blot_support_pooled_buffer::deinit(buffer,Hints_runs); }

struct Values { storage: blot_eval_core_eval::RetainedValue[:] = [],items: blot_eval_core_eval::RetainedValue[:] = [] }
reusable[] var Values_runs: blot_eval_core_eval::RetainedValue[>..] = [];
fn push(buffer: Values&,value: blot_eval_core_eval::RetainedValue) -> Error { return blot_support_pooled_buffer::push(buffer,value,Values_runs); }
fn append(buffer: Values&,values: const blot_eval_core_eval::RetainedValue[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,Values_runs); }
fn clear(buffer: Values&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Values&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Values&) { blot_support_pooled_buffer::deinit(buffer,Values_runs); }

struct Entries { storage: blot_reuse_substitution_keys::Entry[:] = [],items: blot_reuse_substitution_keys::Entry[:] = [] }
reusable[] var Entries_runs: blot_reuse_substitution_keys::Entry[>..] = [];
fn push(buffer: Entries&,value: blot_reuse_substitution_keys::Entry) -> Error { return blot_support_pooled_buffer::push(buffer,value,Entries_runs); }
fn append(buffer: Entries&,values: const blot_reuse_substitution_keys::Entry[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,Entries_runs); }
fn clear(buffer: Entries&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Entries&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Entries&) { blot_support_pooled_buffer::deinit(buffer,Entries_runs); }
