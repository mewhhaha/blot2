// Fixed descriptors share durable typed scratch headers during recursive emission.
namespace blot_backend_substitution_buffers;
import .layout;
import eval.type_evidence;
import eval.core_eval;
import reuse.substitution_keys;
import support.pooled_buffer;
import support.native;
import support.error;
type Error = blot_error::Error;

struct MappingsHead { owner_id: u64,storage: blot_backend_layout::Mapping[:] = [],items: blot_backend_layout::Mapping[:] = [] }
reusable var Mappings_heads: MappingsHead[>..] = [];
reusable[] var Mappings_runs: blot_backend_layout::Mapping[>..] = [];
var Mappings_inactive_storage: blot_backend_layout::Mapping[:] = [];
var Mappings_inactive_items: blot_backend_layout::Mapping[:] = [];
struct Mappings { owner_id: u64 = 0,lease: u32 = 0,storage: blot_backend_layout::Mapping[:]& = Mappings_inactive_storage,items: blot_backend_layout::Mapping[:]& = Mappings_inactive_items }
fn valid(buffer: const Mappings&) -> bool { return buffer.lease != 0 && buffer.lease - 1 < Mappings_heads.len && Mappings_heads[buffer.lease - 1].owner_id == buffer.owner_id && buffer.owner_id != 0; }
fn prepare(buffer: Mappings&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return Error.none; }
    if Mappings_heads.len >= 4294967295 { return Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Mappings_heads.alloc_index(MappingsHead { owner_id , ..}); let head: MappingsHead& = Mappings_heads[index]; buffer = Mappings { owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return Error.none;
}
fn push(buffer: Mappings&,value: blot_backend_layout::Mapping) -> Error { let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::push(buffer,value,Mappings_runs); }
fn append(buffer: Mappings&,values: const blot_backend_layout::Mapping[:]) -> Error { if values.len == 0 { return Error.none; } let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::append(buffer,values,Mappings_runs); }
fn clear(buffer: Mappings&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Mappings&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Mappings&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::deinit(buffer,Mappings_runs); let index = buffer.lease - 1; Mappings_heads[index].owner_id = 0; Mappings_heads.free(index); buffer = Mappings {..}; }

struct RowsHead { owner_id: u64,storage: blot_backend_layout::RowMapping[:] = [],items: blot_backend_layout::RowMapping[:] = [] }
reusable var Rows_heads: RowsHead[>..] = [];
reusable[] var Rows_runs: blot_backend_layout::RowMapping[>..] = [];
var Rows_inactive_storage: blot_backend_layout::RowMapping[:] = [];
var Rows_inactive_items: blot_backend_layout::RowMapping[:] = [];
struct Rows { owner_id: u64 = 0,lease: u32 = 0,storage: blot_backend_layout::RowMapping[:]& = Rows_inactive_storage,items: blot_backend_layout::RowMapping[:]& = Rows_inactive_items }
fn valid(buffer: const Rows&) -> bool { return buffer.lease != 0 && buffer.lease - 1 < Rows_heads.len && Rows_heads[buffer.lease - 1].owner_id == buffer.owner_id && buffer.owner_id != 0; }
fn prepare(buffer: Rows&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return Error.none; }
    if Rows_heads.len >= 4294967295 { return Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Rows_heads.alloc_index(RowsHead { owner_id , ..}); let head: RowsHead& = Rows_heads[index]; buffer = Rows { owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return Error.none;
}
fn push(buffer: Rows&,value: blot_backend_layout::RowMapping) -> Error { let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::push(buffer,value,Rows_runs); }
fn append(buffer: Rows&,values: const blot_backend_layout::RowMapping[:]) -> Error { if values.len == 0 { return Error.none; } let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::append(buffer,values,Rows_runs); }
fn clear(buffer: Rows&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Rows&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Rows&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::deinit(buffer,Rows_runs); let index = buffer.lease - 1; Rows_heads[index].owner_id = 0; Rows_heads.free(index); buffer = Rows {..}; }

struct EvidenceMappingsHead { owner_id: u64,storage: blot_eval_type_evidence::Mapping[:] = [],items: blot_eval_type_evidence::Mapping[:] = [] }
reusable var EvidenceMappings_heads: EvidenceMappingsHead[>..] = [];
reusable[] var EvidenceMappings_runs: blot_eval_type_evidence::Mapping[>..] = [];
var EvidenceMappings_inactive_storage: blot_eval_type_evidence::Mapping[:] = [];
var EvidenceMappings_inactive_items: blot_eval_type_evidence::Mapping[:] = [];
struct EvidenceMappings { owner_id: u64 = 0,lease: u32 = 0,storage: blot_eval_type_evidence::Mapping[:]& = EvidenceMappings_inactive_storage,items: blot_eval_type_evidence::Mapping[:]& = EvidenceMappings_inactive_items }
fn valid(buffer: const EvidenceMappings&) -> bool { return buffer.lease != 0 && buffer.lease - 1 < EvidenceMappings_heads.len && EvidenceMappings_heads[buffer.lease - 1].owner_id == buffer.owner_id && buffer.owner_id != 0; }
fn prepare(buffer: EvidenceMappings&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return Error.none; }
    if EvidenceMappings_heads.len >= 4294967295 { return Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = EvidenceMappings_heads.alloc_index(EvidenceMappingsHead { owner_id , ..}); let head: EvidenceMappingsHead& = EvidenceMappings_heads[index]; buffer = EvidenceMappings { owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return Error.none;
}
fn push(buffer: EvidenceMappings&,value: blot_eval_type_evidence::Mapping) -> Error { let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::push(buffer,value,EvidenceMappings_runs); }
fn append(buffer: EvidenceMappings&,values: const blot_eval_type_evidence::Mapping[:]) -> Error { if values.len == 0 { return Error.none; } let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::append(buffer,values,EvidenceMappings_runs); }
fn clear(buffer: EvidenceMappings&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: EvidenceMappings&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: EvidenceMappings&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::deinit(buffer,EvidenceMappings_runs); let index = buffer.lease - 1; EvidenceMappings_heads[index].owner_id = 0; EvidenceMappings_heads.free(index); buffer = EvidenceMappings {..}; }

struct EvidenceRowsHead { owner_id: u64,storage: blot_eval_type_evidence::RowMapping[:] = [],items: blot_eval_type_evidence::RowMapping[:] = [] }
reusable var EvidenceRows_heads: EvidenceRowsHead[>..] = [];
reusable[] var EvidenceRows_runs: blot_eval_type_evidence::RowMapping[>..] = [];
var EvidenceRows_inactive_storage: blot_eval_type_evidence::RowMapping[:] = [];
var EvidenceRows_inactive_items: blot_eval_type_evidence::RowMapping[:] = [];
struct EvidenceRows { owner_id: u64 = 0,lease: u32 = 0,storage: blot_eval_type_evidence::RowMapping[:]& = EvidenceRows_inactive_storage,items: blot_eval_type_evidence::RowMapping[:]& = EvidenceRows_inactive_items }
fn valid(buffer: const EvidenceRows&) -> bool { return buffer.lease != 0 && buffer.lease - 1 < EvidenceRows_heads.len && EvidenceRows_heads[buffer.lease - 1].owner_id == buffer.owner_id && buffer.owner_id != 0; }
fn prepare(buffer: EvidenceRows&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return Error.none; }
    if EvidenceRows_heads.len >= 4294967295 { return Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = EvidenceRows_heads.alloc_index(EvidenceRowsHead { owner_id , ..}); let head: EvidenceRowsHead& = EvidenceRows_heads[index]; buffer = EvidenceRows { owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return Error.none;
}
fn push(buffer: EvidenceRows&,value: blot_eval_type_evidence::RowMapping) -> Error { let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::push(buffer,value,EvidenceRows_runs); }
fn append(buffer: EvidenceRows&,values: const blot_eval_type_evidence::RowMapping[:]) -> Error { if values.len == 0 { return Error.none; } let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::append(buffer,values,EvidenceRows_runs); }
fn clear(buffer: EvidenceRows&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: EvidenceRows&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: EvidenceRows&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::deinit(buffer,EvidenceRows_runs); let index = buffer.lease - 1; EvidenceRows_heads[index].owner_id = 0; EvidenceRows_heads.free(index); buffer = EvidenceRows {..}; }

struct WordsHead { owner_id: u64,storage: u32[:] = [],items: u32[:] = [] }
reusable var Words_heads: WordsHead[>..] = [];
reusable[] var Words_runs: u32[>..] = [];
var Words_inactive_storage: u32[:] = [];
var Words_inactive_items: u32[:] = [];
struct Words { owner_id: u64 = 0,lease: u32 = 0,storage: u32[:]& = Words_inactive_storage,items: u32[:]& = Words_inactive_items }
fn valid(buffer: const Words&) -> bool { return buffer.lease != 0 && buffer.lease - 1 < Words_heads.len && Words_heads[buffer.lease - 1].owner_id == buffer.owner_id && buffer.owner_id != 0; }
fn prepare(buffer: Words&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return Error.none; }
    if Words_heads.len >= 4294967295 { return Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Words_heads.alloc_index(WordsHead { owner_id , ..}); let head: WordsHead& = Words_heads[index]; buffer = Words { owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return Error.none;
}
fn push(buffer: Words&,value: u32) -> Error { let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::push(buffer,value,Words_runs); }
fn append(buffer: Words&,values: const u32[:]) -> Error { if values.len == 0 { return Error.none; } let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::append(buffer,values,Words_runs); }
fn clear(buffer: Words&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Words&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Words&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::deinit(buffer,Words_runs); let index = buffer.lease - 1; Words_heads[index].owner_id = 0; Words_heads.free(index); buffer = Words {..}; }

struct FlagsHead { owner_id: u64,storage: bool[:] = [],items: bool[:] = [] }
reusable var Flags_heads: FlagsHead[>..] = [];
reusable[] var Flags_runs: bool[>..] = [];
var Flags_inactive_storage: bool[:] = [];
var Flags_inactive_items: bool[:] = [];
struct Flags { owner_id: u64 = 0,lease: u32 = 0,storage: bool[:]& = Flags_inactive_storage,items: bool[:]& = Flags_inactive_items }
fn valid(buffer: const Flags&) -> bool { return buffer.lease != 0 && buffer.lease - 1 < Flags_heads.len && Flags_heads[buffer.lease - 1].owner_id == buffer.owner_id && buffer.owner_id != 0; }
fn prepare(buffer: Flags&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return Error.none; }
    if Flags_heads.len >= 4294967295 { return Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Flags_heads.alloc_index(FlagsHead { owner_id , ..}); let head: FlagsHead& = Flags_heads[index]; buffer = Flags { owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return Error.none;
}
fn push(buffer: Flags&,value: bool) -> Error { let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::push(buffer,value,Flags_runs); }
fn append(buffer: Flags&,values: const bool[:]) -> Error { if values.len == 0 { return Error.none; } let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::append(buffer,values,Flags_runs); }
fn clear(buffer: Flags&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Flags&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Flags&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::deinit(buffer,Flags_runs); let index = buffer.lease - 1; Flags_heads[index].owner_id = 0; Flags_heads.free(index); buffer = Flags {..}; }

struct HintsHead { owner_id: u64,storage: blot_eval_core_eval::RetainedCapture[:] = [],items: blot_eval_core_eval::RetainedCapture[:] = [] }
reusable var Hints_heads: HintsHead[>..] = [];
reusable[] var Hints_runs: blot_eval_core_eval::RetainedCapture[>..] = [];
var Hints_inactive_storage: blot_eval_core_eval::RetainedCapture[:] = [];
var Hints_inactive_items: blot_eval_core_eval::RetainedCapture[:] = [];
struct Hints { owner_id: u64 = 0,lease: u32 = 0,storage: blot_eval_core_eval::RetainedCapture[:]& = Hints_inactive_storage,items: blot_eval_core_eval::RetainedCapture[:]& = Hints_inactive_items }
fn valid(buffer: const Hints&) -> bool { return buffer.lease != 0 && buffer.lease - 1 < Hints_heads.len && Hints_heads[buffer.lease - 1].owner_id == buffer.owner_id && buffer.owner_id != 0; }
fn prepare(buffer: Hints&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return Error.none; }
    if Hints_heads.len >= 4294967295 { return Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Hints_heads.alloc_index(HintsHead { owner_id , ..}); let head: HintsHead& = Hints_heads[index]; buffer = Hints { owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return Error.none;
}
fn push(buffer: Hints&,value: blot_eval_core_eval::RetainedCapture) -> Error { let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::push(buffer,value,Hints_runs); }
fn append(buffer: Hints&,values: const blot_eval_core_eval::RetainedCapture[:]) -> Error { if values.len == 0 { return Error.none; } let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::append(buffer,values,Hints_runs); }
fn clear(buffer: Hints&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Hints&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Hints&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::deinit(buffer,Hints_runs); let index = buffer.lease - 1; Hints_heads[index].owner_id = 0; Hints_heads.free(index); buffer = Hints {..}; }

struct ValuesHead { owner_id: u64,storage: blot_eval_core_eval::RetainedValue[:] = [],items: blot_eval_core_eval::RetainedValue[:] = [] }
reusable var Values_heads: ValuesHead[>..] = [];
reusable[] var Values_runs: blot_eval_core_eval::RetainedValue[>..] = [];
var Values_inactive_storage: blot_eval_core_eval::RetainedValue[:] = [];
var Values_inactive_items: blot_eval_core_eval::RetainedValue[:] = [];
struct Values { owner_id: u64 = 0,lease: u32 = 0,storage: blot_eval_core_eval::RetainedValue[:]& = Values_inactive_storage,items: blot_eval_core_eval::RetainedValue[:]& = Values_inactive_items }
fn valid(buffer: const Values&) -> bool { return buffer.lease != 0 && buffer.lease - 1 < Values_heads.len && Values_heads[buffer.lease - 1].owner_id == buffer.owner_id && buffer.owner_id != 0; }
fn prepare(buffer: Values&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return Error.none; }
    if Values_heads.len >= 4294967295 { return Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Values_heads.alloc_index(ValuesHead { owner_id , ..}); let head: ValuesHead& = Values_heads[index]; buffer = Values { owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return Error.none;
}
fn push(buffer: Values&,value: blot_eval_core_eval::RetainedValue) -> Error { let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::push(buffer,value,Values_runs); }
fn append(buffer: Values&,values: const blot_eval_core_eval::RetainedValue[:]) -> Error { if values.len == 0 { return Error.none; } let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::append(buffer,values,Values_runs); }
fn clear(buffer: Values&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Values&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Values&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::deinit(buffer,Values_runs); let index = buffer.lease - 1; Values_heads[index].owner_id = 0; Values_heads.free(index); buffer = Values {..}; }

struct EntriesHead { owner_id: u64,storage: blot_reuse_substitution_keys::Entry[:] = [],items: blot_reuse_substitution_keys::Entry[:] = [] }
reusable var Entries_heads: EntriesHead[>..] = [];
reusable[] var Entries_runs: blot_reuse_substitution_keys::Entry[>..] = [];
var Entries_inactive_storage: blot_reuse_substitution_keys::Entry[:] = [];
var Entries_inactive_items: blot_reuse_substitution_keys::Entry[:] = [];
struct Entries { owner_id: u64 = 0,lease: u32 = 0,storage: blot_reuse_substitution_keys::Entry[:]& = Entries_inactive_storage,items: blot_reuse_substitution_keys::Entry[:]& = Entries_inactive_items }
fn valid(buffer: const Entries&) -> bool { return buffer.lease != 0 && buffer.lease - 1 < Entries_heads.len && Entries_heads[buffer.lease - 1].owner_id == buffer.owner_id && buffer.owner_id != 0; }
fn prepare(buffer: Entries&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return Error.none; }
    if Entries_heads.len >= 4294967295 { return Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Entries_heads.alloc_index(EntriesHead { owner_id , ..}); let head: EntriesHead& = Entries_heads[index]; buffer = Entries { owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return Error.none;
}
fn push(buffer: Entries&,value: blot_reuse_substitution_keys::Entry) -> Error { let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::push(buffer,value,Entries_runs); }
fn append(buffer: Entries&,values: const blot_reuse_substitution_keys::Entry[:]) -> Error { if values.len == 0 { return Error.none; } let error = prepare(buffer); if error != Error.none { return error; } return blot_support_pooled_buffer::append(buffer,values,Entries_runs); }
fn clear(buffer: Entries&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: Entries&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: Entries&) { if buffer.lease == 0 { return; } assert(valid(buffer)); blot_support_pooled_buffer::deinit(buffer,Entries_runs); let index = buffer.lease - 1; Entries_heads[index].owner_id = 0; Entries_heads.free(index); buffer = Entries {..}; }
