// Fixed descriptors share durable typed scratch headers during recursive emission.
namespace blot_backend_substitution_buffers;
import .layout;
import eval.type_evidence;
import eval.core_eval;
import reuse.substitution_keys;
import support.pooled_buffer;
import support.native;
import support.error;
import support.option;
type Error = blot_error::Error;

struct MappingsHead { owner_id: u64,storage: blot_backend_layout::Mapping[:] = default<blot_backend_layout::Mapping[:]>(),items: blot_backend_layout::Mapping[:] = default<blot_backend_layout::Mapping[:]>() }
reusable var Mappings_heads: MappingsHead[>..] = [];
reusable[] var Mappings_runs: blot_backend_layout::Mapping[>..] = [];
var Mappings_inactive_storage: blot_backend_layout::Mapping[:] = default<blot_backend_layout::Mapping[:]>();
var Mappings_inactive_items: blot_backend_layout::Mapping[:] = default<blot_backend_layout::Mapping[:]>();
struct Mappings { owner_id: u64 = 0,lease: u32 = 0,storage: blot_backend_layout::Mapping[:]& = Mappings_inactive_storage,items: blot_backend_layout::Mapping[:]& = Mappings_inactive_items }
fn valid(buffer: const Mappings&) -> bool {
 if buffer.lease==0||buffer.lease-1>=Mappings_heads.len||buffer.owner_id==0 {return false;}
 let storage:(blot_backend_layout::Mapping[:])& =Mappings_heads[buffer.lease-1].storage;let items:(blot_backend_layout::Mapping[:])& =Mappings_heads[buffer.lease-1].items;
 return Mappings_heads[buffer.lease-1].owner_id==buffer.owner_id && buffer.storage .== storage && buffer.items .== items;
}
fn prepare(buffer: Mappings&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return blot_error::Error.none; }
    if Mappings_heads.len >= 4294967295 { return blot_error::Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Mappings_heads.alloc_index(MappingsHead { owner_id , ..}); let head: MappingsHead& = Mappings_heads[index]; buffer = Mappings { owner_id: owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return blot_error::Error.none;
}
fn publishMappings(head: MappingsHead&,view: blot_support_pooled_buffer::Buffer<blot_backend_layout::Mapping>) {
 assert(view.items.len<=view.storage.len);
 if view.storage.len==0 {assert(view.items.len==0);head.storage=default<blot_backend_layout::Mapping[:]>();head.items=default<blot_backend_layout::Mapping[:]>();return;}
 let owned=Mappings_runs.realloc_slice(view.storage,view.storage.len);assert(blot_support::same_slice_identity(owned,view.storage));
 let start=Mappings_runs.index_of(owned[0]);assert(start>=0 && view.storage.len<=Mappings_runs.len-start);let storage=Mappings_runs[start..start+view.storage.len];
 assert(blot_support::same_slice_identity(view.items,storage[..view.items.len]));head.storage=storage;head.items=storage[..view.items.len];
}

fn push(buffer: Mappings&,value: blot_backend_layout::Mapping) -> Error { let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:MappingsHead& =Mappings_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_backend_layout::Mapping> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::push(view,value,Mappings_runs);publishMappings(head,view);return result; }
fn append(buffer: Mappings&,values: const blot_backend_layout::Mapping[:]) -> Error { if values.len == 0 { return blot_error::Error.none; } let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:MappingsHead& =Mappings_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_backend_layout::Mapping> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::append(view,values,Mappings_runs);publishMappings(head,view);return result; }
fn clear(buffer: Mappings&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:MappingsHead& =Mappings_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_backend_layout::Mapping> {storage:head.storage,items:head.items};blot_support_pooled_buffer::clear(view);publishMappings(head,view); }
fn resize(buffer: Mappings&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); let head:MappingsHead& =Mappings_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_backend_layout::Mapping> {storage:head.storage,items:head.items};blot_support_pooled_buffer::resize(view,length);publishMappings(head,view); }
fn deinit(buffer: Mappings&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:MappingsHead& =Mappings_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_backend_layout::Mapping> {storage:head.storage,items:head.items};blot_support_pooled_buffer::deinit(view,Mappings_runs);publishMappings(head,view); let index = buffer.lease - 1; Mappings_heads[index].owner_id = 0; Mappings_heads.free(index); buffer = Mappings {..}; }

struct RowsHead { owner_id: u64,storage: blot_backend_layout::RowMapping[:] = default<blot_backend_layout::RowMapping[:]>(),items: blot_backend_layout::RowMapping[:] = default<blot_backend_layout::RowMapping[:]>() }
reusable var Rows_heads: RowsHead[>..] = [];
reusable[] var Rows_runs: blot_backend_layout::RowMapping[>..] = [];
var Rows_inactive_storage: blot_backend_layout::RowMapping[:] = default<blot_backend_layout::RowMapping[:]>();
var Rows_inactive_items: blot_backend_layout::RowMapping[:] = default<blot_backend_layout::RowMapping[:]>();
struct Rows { owner_id: u64 = 0,lease: u32 = 0,storage: blot_backend_layout::RowMapping[:]& = Rows_inactive_storage,items: blot_backend_layout::RowMapping[:]& = Rows_inactive_items }
fn valid(buffer: const Rows&) -> bool {
 if buffer.lease==0||buffer.lease-1>=Rows_heads.len||buffer.owner_id==0 {return false;}
 let storage:(blot_backend_layout::RowMapping[:])& =Rows_heads[buffer.lease-1].storage;let items:(blot_backend_layout::RowMapping[:])& =Rows_heads[buffer.lease-1].items;
 return Rows_heads[buffer.lease-1].owner_id==buffer.owner_id && buffer.storage .== storage && buffer.items .== items;
}
fn prepare(buffer: Rows&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return blot_error::Error.none; }
    if Rows_heads.len >= 4294967295 { return blot_error::Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Rows_heads.alloc_index(RowsHead { owner_id , ..}); let head: RowsHead& = Rows_heads[index]; buffer = Rows { owner_id: owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return blot_error::Error.none;
}
fn publishRows(head: RowsHead&,view: blot_support_pooled_buffer::Buffer<blot_backend_layout::RowMapping>) {
 assert(view.items.len<=view.storage.len);
 if view.storage.len==0 {assert(view.items.len==0);head.storage=default<blot_backend_layout::RowMapping[:]>();head.items=default<blot_backend_layout::RowMapping[:]>();return;}
 let owned=Rows_runs.realloc_slice(view.storage,view.storage.len);assert(blot_support::same_slice_identity(owned,view.storage));
 let start=Rows_runs.index_of(owned[0]);assert(start>=0 && view.storage.len<=Rows_runs.len-start);let storage=Rows_runs[start..start+view.storage.len];
 assert(blot_support::same_slice_identity(view.items,storage[..view.items.len]));head.storage=storage;head.items=storage[..view.items.len];
}

fn push(buffer: Rows&,value: blot_backend_layout::RowMapping) -> Error { let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:RowsHead& =Rows_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_backend_layout::RowMapping> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::push(view,value,Rows_runs);publishRows(head,view);return result; }
fn append(buffer: Rows&,values: const blot_backend_layout::RowMapping[:]) -> Error { if values.len == 0 { return blot_error::Error.none; } let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:RowsHead& =Rows_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_backend_layout::RowMapping> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::append(view,values,Rows_runs);publishRows(head,view);return result; }
fn clear(buffer: Rows&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:RowsHead& =Rows_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_backend_layout::RowMapping> {storage:head.storage,items:head.items};blot_support_pooled_buffer::clear(view);publishRows(head,view); }
fn resize(buffer: Rows&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); let head:RowsHead& =Rows_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_backend_layout::RowMapping> {storage:head.storage,items:head.items};blot_support_pooled_buffer::resize(view,length);publishRows(head,view); }
fn deinit(buffer: Rows&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:RowsHead& =Rows_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_backend_layout::RowMapping> {storage:head.storage,items:head.items};blot_support_pooled_buffer::deinit(view,Rows_runs);publishRows(head,view); let index = buffer.lease - 1; Rows_heads[index].owner_id = 0; Rows_heads.free(index); buffer = Rows {..}; }

struct EvidenceMappingsHead { owner_id: u64,storage: blot_eval_type_evidence::Mapping[:] = default<blot_eval_type_evidence::Mapping[:]>(),items: blot_eval_type_evidence::Mapping[:] = default<blot_eval_type_evidence::Mapping[:]>() }
reusable var EvidenceMappings_heads: EvidenceMappingsHead[>..] = [];
reusable[] var EvidenceMappings_runs: blot_eval_type_evidence::Mapping[>..] = [];
var EvidenceMappings_inactive_storage: blot_eval_type_evidence::Mapping[:] = default<blot_eval_type_evidence::Mapping[:]>();
var EvidenceMappings_inactive_items: blot_eval_type_evidence::Mapping[:] = default<blot_eval_type_evidence::Mapping[:]>();
struct EvidenceMappings { owner_id: u64 = 0,lease: u32 = 0,storage: blot_eval_type_evidence::Mapping[:]& = EvidenceMappings_inactive_storage,items: blot_eval_type_evidence::Mapping[:]& = EvidenceMappings_inactive_items }
fn valid(buffer: const EvidenceMappings&) -> bool {
 if buffer.lease==0||buffer.lease-1>=EvidenceMappings_heads.len||buffer.owner_id==0 {return false;}
 let storage:(blot_eval_type_evidence::Mapping[:])& =EvidenceMappings_heads[buffer.lease-1].storage;let items:(blot_eval_type_evidence::Mapping[:])& =EvidenceMappings_heads[buffer.lease-1].items;
 return EvidenceMappings_heads[buffer.lease-1].owner_id==buffer.owner_id && buffer.storage .== storage && buffer.items .== items;
}
fn prepare(buffer: EvidenceMappings&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return blot_error::Error.none; }
    if EvidenceMappings_heads.len >= 4294967295 { return blot_error::Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = EvidenceMappings_heads.alloc_index(EvidenceMappingsHead { owner_id , ..}); let head: EvidenceMappingsHead& = EvidenceMappings_heads[index]; buffer = EvidenceMappings { owner_id: owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return blot_error::Error.none;
}
fn publishEvidenceMappings(head: EvidenceMappingsHead&,view: blot_support_pooled_buffer::Buffer<blot_eval_type_evidence::Mapping>) {
 assert(view.items.len<=view.storage.len);
 if view.storage.len==0 {assert(view.items.len==0);head.storage=default<blot_eval_type_evidence::Mapping[:]>();head.items=default<blot_eval_type_evidence::Mapping[:]>();return;}
 let owned=EvidenceMappings_runs.realloc_slice(view.storage,view.storage.len);assert(blot_support::same_slice_identity(owned,view.storage));
 let start=EvidenceMappings_runs.index_of(owned[0]);assert(start>=0 && view.storage.len<=EvidenceMappings_runs.len-start);let storage=EvidenceMappings_runs[start..start+view.storage.len];
 assert(blot_support::same_slice_identity(view.items,storage[..view.items.len]));head.storage=storage;head.items=storage[..view.items.len];
}

fn push(buffer: EvidenceMappings&,value: blot_eval_type_evidence::Mapping) -> Error { let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:EvidenceMappingsHead& =EvidenceMappings_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_type_evidence::Mapping> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::push(view,value,EvidenceMappings_runs);publishEvidenceMappings(head,view);return result; }
fn append(buffer: EvidenceMappings&,values: const blot_eval_type_evidence::Mapping[:]) -> Error { if values.len == 0 { return blot_error::Error.none; } let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:EvidenceMappingsHead& =EvidenceMappings_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_type_evidence::Mapping> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::append(view,values,EvidenceMappings_runs);publishEvidenceMappings(head,view);return result; }
fn clear(buffer: EvidenceMappings&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:EvidenceMappingsHead& =EvidenceMappings_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_type_evidence::Mapping> {storage:head.storage,items:head.items};blot_support_pooled_buffer::clear(view);publishEvidenceMappings(head,view); }
fn resize(buffer: EvidenceMappings&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); let head:EvidenceMappingsHead& =EvidenceMappings_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_type_evidence::Mapping> {storage:head.storage,items:head.items};blot_support_pooled_buffer::resize(view,length);publishEvidenceMappings(head,view); }
fn deinit(buffer: EvidenceMappings&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:EvidenceMappingsHead& =EvidenceMappings_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_type_evidence::Mapping> {storage:head.storage,items:head.items};blot_support_pooled_buffer::deinit(view,EvidenceMappings_runs);publishEvidenceMappings(head,view); let index = buffer.lease - 1; EvidenceMappings_heads[index].owner_id = 0; EvidenceMappings_heads.free(index); buffer = EvidenceMappings {..}; }

struct EvidenceRowsHead { owner_id: u64,storage: blot_eval_type_evidence::RowMapping[:] = default<blot_eval_type_evidence::RowMapping[:]>(),items: blot_eval_type_evidence::RowMapping[:] = default<blot_eval_type_evidence::RowMapping[:]>() }
reusable var EvidenceRows_heads: EvidenceRowsHead[>..] = [];
reusable[] var EvidenceRows_runs: blot_eval_type_evidence::RowMapping[>..] = [];
var EvidenceRows_inactive_storage: blot_eval_type_evidence::RowMapping[:] = default<blot_eval_type_evidence::RowMapping[:]>();
var EvidenceRows_inactive_items: blot_eval_type_evidence::RowMapping[:] = default<blot_eval_type_evidence::RowMapping[:]>();
struct EvidenceRows { owner_id: u64 = 0,lease: u32 = 0,storage: blot_eval_type_evidence::RowMapping[:]& = EvidenceRows_inactive_storage,items: blot_eval_type_evidence::RowMapping[:]& = EvidenceRows_inactive_items }
fn valid(buffer: const EvidenceRows&) -> bool {
 if buffer.lease==0||buffer.lease-1>=EvidenceRows_heads.len||buffer.owner_id==0 {return false;}
 let storage:(blot_eval_type_evidence::RowMapping[:])& =EvidenceRows_heads[buffer.lease-1].storage;let items:(blot_eval_type_evidence::RowMapping[:])& =EvidenceRows_heads[buffer.lease-1].items;
 return EvidenceRows_heads[buffer.lease-1].owner_id==buffer.owner_id && buffer.storage .== storage && buffer.items .== items;
}
fn prepare(buffer: EvidenceRows&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return blot_error::Error.none; }
    if EvidenceRows_heads.len >= 4294967295 { return blot_error::Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = EvidenceRows_heads.alloc_index(EvidenceRowsHead { owner_id , ..}); let head: EvidenceRowsHead& = EvidenceRows_heads[index]; buffer = EvidenceRows { owner_id: owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return blot_error::Error.none;
}
fn publishEvidenceRows(head: EvidenceRowsHead&,view: blot_support_pooled_buffer::Buffer<blot_eval_type_evidence::RowMapping>) {
 assert(view.items.len<=view.storage.len);
 if view.storage.len==0 {assert(view.items.len==0);head.storage=default<blot_eval_type_evidence::RowMapping[:]>();head.items=default<blot_eval_type_evidence::RowMapping[:]>();return;}
 let owned=EvidenceRows_runs.realloc_slice(view.storage,view.storage.len);assert(blot_support::same_slice_identity(owned,view.storage));
 let start=EvidenceRows_runs.index_of(owned[0]);assert(start>=0 && view.storage.len<=EvidenceRows_runs.len-start);let storage=EvidenceRows_runs[start..start+view.storage.len];
 assert(blot_support::same_slice_identity(view.items,storage[..view.items.len]));head.storage=storage;head.items=storage[..view.items.len];
}

fn push(buffer: EvidenceRows&,value: blot_eval_type_evidence::RowMapping) -> Error { let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:EvidenceRowsHead& =EvidenceRows_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_type_evidence::RowMapping> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::push(view,value,EvidenceRows_runs);publishEvidenceRows(head,view);return result; }
fn append(buffer: EvidenceRows&,values: const blot_eval_type_evidence::RowMapping[:]) -> Error { if values.len == 0 { return blot_error::Error.none; } let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:EvidenceRowsHead& =EvidenceRows_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_type_evidence::RowMapping> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::append(view,values,EvidenceRows_runs);publishEvidenceRows(head,view);return result; }
fn clear(buffer: EvidenceRows&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:EvidenceRowsHead& =EvidenceRows_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_type_evidence::RowMapping> {storage:head.storage,items:head.items};blot_support_pooled_buffer::clear(view);publishEvidenceRows(head,view); }
fn resize(buffer: EvidenceRows&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); let head:EvidenceRowsHead& =EvidenceRows_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_type_evidence::RowMapping> {storage:head.storage,items:head.items};blot_support_pooled_buffer::resize(view,length);publishEvidenceRows(head,view); }
fn deinit(buffer: EvidenceRows&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:EvidenceRowsHead& =EvidenceRows_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_type_evidence::RowMapping> {storage:head.storage,items:head.items};blot_support_pooled_buffer::deinit(view,EvidenceRows_runs);publishEvidenceRows(head,view); let index = buffer.lease - 1; EvidenceRows_heads[index].owner_id = 0; EvidenceRows_heads.free(index); buffer = EvidenceRows {..}; }

struct WordsHead { owner_id: u64,storage: u32[:] = default<u32[:]>(),items: u32[:] = default<u32[:]>() }
reusable var Words_heads: WordsHead[>..] = [];
reusable[] var Words_runs: u32[>..] = [];
var Words_inactive_storage: u32[:] = default<u32[:]>();
var Words_inactive_items: u32[:] = default<u32[:]>();
struct Words { owner_id: u64 = 0,lease: u32 = 0,storage: u32[:]& = Words_inactive_storage,items: u32[:]& = Words_inactive_items }
fn valid(buffer: const Words&) -> bool {
 if buffer.lease==0||buffer.lease-1>=Words_heads.len||buffer.owner_id==0 {return false;}
 let storage:(u32[:])& =Words_heads[buffer.lease-1].storage;let items:(u32[:])& =Words_heads[buffer.lease-1].items;
 return Words_heads[buffer.lease-1].owner_id==buffer.owner_id && buffer.storage .== storage && buffer.items .== items;
}
fn prepare(buffer: Words&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return blot_error::Error.none; }
    if Words_heads.len >= 4294967295 { return blot_error::Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Words_heads.alloc_index(WordsHead { owner_id , ..}); let head: WordsHead& = Words_heads[index]; buffer = Words { owner_id: owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return blot_error::Error.none;
}
fn publishWords(head: WordsHead&,view: blot_support_pooled_buffer::Buffer<u32>) {
 assert(view.items.len<=view.storage.len);
 if view.storage.len==0 {assert(view.items.len==0);head.storage=default<u32[:]>();head.items=default<u32[:]>();return;}
 let owned=Words_runs.realloc_slice(view.storage,view.storage.len);assert(blot_support::same_slice_identity(owned,view.storage));
 let start=Words_runs.index_of(owned[0]);assert(start>=0 && view.storage.len<=Words_runs.len-start);let storage=Words_runs[start..start+view.storage.len];
 assert(blot_support::same_slice_identity(view.items,storage[..view.items.len]));head.storage=storage;head.items=storage[..view.items.len];
}

fn push(buffer: Words&,value: u32) -> Error { let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:WordsHead& =Words_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<u32> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::push(view,value,Words_runs);publishWords(head,view);return result; }
fn append(buffer: Words&,values: const u32[:]) -> Error { if values.len == 0 { return blot_error::Error.none; } let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:WordsHead& =Words_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<u32> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::append(view,values,Words_runs);publishWords(head,view);return result; }
fn clear(buffer: Words&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:WordsHead& =Words_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<u32> {storage:head.storage,items:head.items};blot_support_pooled_buffer::clear(view);publishWords(head,view); }
fn resize(buffer: Words&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); let head:WordsHead& =Words_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<u32> {storage:head.storage,items:head.items};blot_support_pooled_buffer::resize(view,length);publishWords(head,view); }
fn deinit(buffer: Words&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:WordsHead& =Words_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<u32> {storage:head.storage,items:head.items};blot_support_pooled_buffer::deinit(view,Words_runs);publishWords(head,view); let index = buffer.lease - 1; Words_heads[index].owner_id = 0; Words_heads.free(index); buffer = Words {..}; }

struct FlagsHead { owner_id: u64,storage: bool[:] = default<bool[:]>(),items: bool[:] = default<bool[:]>() }
reusable var Flags_heads: FlagsHead[>..] = [];
reusable[] var Flags_runs: bool[>..] = [];
var Flags_inactive_storage: bool[:] = default<bool[:]>();
var Flags_inactive_items: bool[:] = default<bool[:]>();
struct Flags { owner_id: u64 = 0,lease: u32 = 0,storage: bool[:]& = Flags_inactive_storage,items: bool[:]& = Flags_inactive_items }
fn valid(buffer: const Flags&) -> bool {
 if buffer.lease==0||buffer.lease-1>=Flags_heads.len||buffer.owner_id==0 {return false;}
 let storage:(bool[:])& =Flags_heads[buffer.lease-1].storage;let items:(bool[:])& =Flags_heads[buffer.lease-1].items;
 return Flags_heads[buffer.lease-1].owner_id==buffer.owner_id && buffer.storage .== storage && buffer.items .== items;
}
fn prepare(buffer: Flags&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return blot_error::Error.none; }
    if Flags_heads.len >= 4294967295 { return blot_error::Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Flags_heads.alloc_index(FlagsHead { owner_id , ..}); let head: FlagsHead& = Flags_heads[index]; buffer = Flags { owner_id: owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return blot_error::Error.none;
}
fn publishFlags(head: FlagsHead&,view: blot_support_pooled_buffer::Buffer<bool>) {
 assert(view.items.len<=view.storage.len);
 if view.storage.len==0 {assert(view.items.len==0);head.storage=default<bool[:]>();head.items=default<bool[:]>();return;}
 let owned=Flags_runs.realloc_slice(view.storage,view.storage.len);assert(blot_support::same_slice_identity(owned,view.storage));
 let start=Flags_runs.index_of(owned[0]);assert(start>=0 && view.storage.len<=Flags_runs.len-start);let storage=Flags_runs[start..start+view.storage.len];
 assert(blot_support::same_slice_identity(view.items,storage[..view.items.len]));head.storage=storage;head.items=storage[..view.items.len];
}

fn push(buffer: Flags&,value: bool) -> Error { let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:FlagsHead& =Flags_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<bool> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::push(view,value,Flags_runs);publishFlags(head,view);return result; }
fn append(buffer: Flags&,values: const bool[:]) -> Error { if values.len == 0 { return blot_error::Error.none; } let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:FlagsHead& =Flags_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<bool> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::append(view,values,Flags_runs);publishFlags(head,view);return result; }
fn clear(buffer: Flags&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:FlagsHead& =Flags_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<bool> {storage:head.storage,items:head.items};blot_support_pooled_buffer::clear(view);publishFlags(head,view); }
fn resize(buffer: Flags&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); let head:FlagsHead& =Flags_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<bool> {storage:head.storage,items:head.items};blot_support_pooled_buffer::resize(view,length);publishFlags(head,view); }
fn deinit(buffer: Flags&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:FlagsHead& =Flags_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<bool> {storage:head.storage,items:head.items};blot_support_pooled_buffer::deinit(view,Flags_runs);publishFlags(head,view); let index = buffer.lease - 1; Flags_heads[index].owner_id = 0; Flags_heads.free(index); buffer = Flags {..}; }

struct HintsHead { owner_id: u64,storage: blot_eval_core_eval::RetainedCapture[:] = default<blot_eval_core_eval::RetainedCapture[:]>(),items: blot_eval_core_eval::RetainedCapture[:] = default<blot_eval_core_eval::RetainedCapture[:]>() }
reusable var Hints_heads: HintsHead[>..] = [];
reusable[] var Hints_runs: blot_eval_core_eval::RetainedCapture[>..] = [];
var Hints_inactive_storage: blot_eval_core_eval::RetainedCapture[:] = default<blot_eval_core_eval::RetainedCapture[:]>();
var Hints_inactive_items: blot_eval_core_eval::RetainedCapture[:] = default<blot_eval_core_eval::RetainedCapture[:]>();
struct Hints { owner_id: u64 = 0,lease: u32 = 0,storage: blot_eval_core_eval::RetainedCapture[:]& = Hints_inactive_storage,items: blot_eval_core_eval::RetainedCapture[:]& = Hints_inactive_items }
fn valid(buffer: const Hints&) -> bool {
 if buffer.lease==0||buffer.lease-1>=Hints_heads.len||buffer.owner_id==0 {return false;}
 let storage:(blot_eval_core_eval::RetainedCapture[:])& =Hints_heads[buffer.lease-1].storage;let items:(blot_eval_core_eval::RetainedCapture[:])& =Hints_heads[buffer.lease-1].items;
 return Hints_heads[buffer.lease-1].owner_id==buffer.owner_id && buffer.storage .== storage && buffer.items .== items;
}
fn prepare(buffer: Hints&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return blot_error::Error.none; }
    if Hints_heads.len >= 4294967295 { return blot_error::Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Hints_heads.alloc_index(HintsHead { owner_id , ..}); let head: HintsHead& = Hints_heads[index]; buffer = Hints { owner_id: owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return blot_error::Error.none;
}
fn publishHints(head: HintsHead&,view: blot_support_pooled_buffer::Buffer<blot_eval_core_eval::RetainedCapture>) {
 assert(view.items.len<=view.storage.len);
 if view.storage.len==0 {assert(view.items.len==0);head.storage=default<blot_eval_core_eval::RetainedCapture[:]>();head.items=default<blot_eval_core_eval::RetainedCapture[:]>();return;}
 let owned=Hints_runs.realloc_slice(view.storage,view.storage.len);assert(blot_support::same_slice_identity(owned,view.storage));
 let start=Hints_runs.index_of(owned[0]);assert(start>=0 && view.storage.len<=Hints_runs.len-start);let storage=Hints_runs[start..start+view.storage.len];
 assert(blot_support::same_slice_identity(view.items,storage[..view.items.len]));head.storage=storage;head.items=storage[..view.items.len];
}

fn push(buffer: Hints&,value: blot_eval_core_eval::RetainedCapture) -> Error { let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:HintsHead& =Hints_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_core_eval::RetainedCapture> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::push(view,value,Hints_runs);publishHints(head,view);return result; }
fn append(buffer: Hints&,values: const blot_eval_core_eval::RetainedCapture[:]) -> Error { if values.len == 0 { return blot_error::Error.none; } let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:HintsHead& =Hints_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_core_eval::RetainedCapture> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::append(view,values,Hints_runs);publishHints(head,view);return result; }
fn clear(buffer: Hints&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:HintsHead& =Hints_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_core_eval::RetainedCapture> {storage:head.storage,items:head.items};blot_support_pooled_buffer::clear(view);publishHints(head,view); }
fn resize(buffer: Hints&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); let head:HintsHead& =Hints_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_core_eval::RetainedCapture> {storage:head.storage,items:head.items};blot_support_pooled_buffer::resize(view,length);publishHints(head,view); }
fn deinit(buffer: Hints&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:HintsHead& =Hints_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_core_eval::RetainedCapture> {storage:head.storage,items:head.items};blot_support_pooled_buffer::deinit(view,Hints_runs);publishHints(head,view); let index = buffer.lease - 1; Hints_heads[index].owner_id = 0; Hints_heads.free(index); buffer = Hints {..}; }

struct ValuesHead { owner_id: u64,storage: blot_eval_core_eval::RetainedValue[:] = default<blot_eval_core_eval::RetainedValue[:]>(),items: blot_eval_core_eval::RetainedValue[:] = default<blot_eval_core_eval::RetainedValue[:]>() }
reusable var Values_heads: ValuesHead[>..] = [];
reusable[] var Values_runs: blot_eval_core_eval::RetainedValue[>..] = [];
var Values_inactive_storage: blot_eval_core_eval::RetainedValue[:] = default<blot_eval_core_eval::RetainedValue[:]>();
var Values_inactive_items: blot_eval_core_eval::RetainedValue[:] = default<blot_eval_core_eval::RetainedValue[:]>();
struct Values { owner_id: u64 = 0,lease: u32 = 0,storage: blot_eval_core_eval::RetainedValue[:]& = Values_inactive_storage,items: blot_eval_core_eval::RetainedValue[:]& = Values_inactive_items }
fn valid(buffer: const Values&) -> bool {
 if buffer.lease==0||buffer.lease-1>=Values_heads.len||buffer.owner_id==0 {return false;}
 let storage:(blot_eval_core_eval::RetainedValue[:])& =Values_heads[buffer.lease-1].storage;let items:(blot_eval_core_eval::RetainedValue[:])& =Values_heads[buffer.lease-1].items;
 return Values_heads[buffer.lease-1].owner_id==buffer.owner_id && buffer.storage .== storage && buffer.items .== items;
}
fn prepare(buffer: Values&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return blot_error::Error.none; }
    if Values_heads.len >= 4294967295 { return blot_error::Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Values_heads.alloc_index(ValuesHead { owner_id , ..}); let head: ValuesHead& = Values_heads[index]; buffer = Values { owner_id: owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return blot_error::Error.none;
}
fn publishValues(head: ValuesHead&,view: blot_support_pooled_buffer::Buffer<blot_eval_core_eval::RetainedValue>) {
 assert(view.items.len<=view.storage.len);
 if view.storage.len==0 {assert(view.items.len==0);head.storage=default<blot_eval_core_eval::RetainedValue[:]>();head.items=default<blot_eval_core_eval::RetainedValue[:]>();return;}
 let owned=Values_runs.realloc_slice(view.storage,view.storage.len);assert(blot_support::same_slice_identity(owned,view.storage));
 let start=Values_runs.index_of(owned[0]);assert(start>=0 && view.storage.len<=Values_runs.len-start);let storage=Values_runs[start..start+view.storage.len];
 assert(blot_support::same_slice_identity(view.items,storage[..view.items.len]));head.storage=storage;head.items=storage[..view.items.len];
}

fn push(buffer: Values&,value: blot_eval_core_eval::RetainedValue) -> Error { let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:ValuesHead& =Values_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_core_eval::RetainedValue> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::push(view,value,Values_runs);publishValues(head,view);return result; }
fn append(buffer: Values&,values: const blot_eval_core_eval::RetainedValue[:]) -> Error { if values.len == 0 { return blot_error::Error.none; } let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:ValuesHead& =Values_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_core_eval::RetainedValue> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::append(view,values,Values_runs);publishValues(head,view);return result; }
fn clear(buffer: Values&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:ValuesHead& =Values_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_core_eval::RetainedValue> {storage:head.storage,items:head.items};blot_support_pooled_buffer::clear(view);publishValues(head,view); }
fn resize(buffer: Values&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); let head:ValuesHead& =Values_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_core_eval::RetainedValue> {storage:head.storage,items:head.items};blot_support_pooled_buffer::resize(view,length);publishValues(head,view); }
fn deinit(buffer: Values&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:ValuesHead& =Values_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_eval_core_eval::RetainedValue> {storage:head.storage,items:head.items};blot_support_pooled_buffer::deinit(view,Values_runs);publishValues(head,view); let index = buffer.lease - 1; Values_heads[index].owner_id = 0; Values_heads.free(index); buffer = Values {..}; }

struct EntriesHead { owner_id: u64,storage: blot_reuse_substitution_keys::Entry[:] = default<blot_reuse_substitution_keys::Entry[:]>(),items: blot_reuse_substitution_keys::Entry[:] = default<blot_reuse_substitution_keys::Entry[:]>() }
reusable var Entries_heads: EntriesHead[>..] = [];
reusable[] var Entries_runs: blot_reuse_substitution_keys::Entry[>..] = [];
var Entries_inactive_storage: blot_reuse_substitution_keys::Entry[:] = default<blot_reuse_substitution_keys::Entry[:]>();
var Entries_inactive_items: blot_reuse_substitution_keys::Entry[:] = default<blot_reuse_substitution_keys::Entry[:]>();
struct Entries { owner_id: u64 = 0,lease: u32 = 0,storage: blot_reuse_substitution_keys::Entry[:]& = Entries_inactive_storage,items: blot_reuse_substitution_keys::Entry[:]& = Entries_inactive_items }
fn valid(buffer: const Entries&) -> bool {
 if buffer.lease==0||buffer.lease-1>=Entries_heads.len||buffer.owner_id==0 {return false;}
 let storage:(blot_reuse_substitution_keys::Entry[:])& =Entries_heads[buffer.lease-1].storage;let items:(blot_reuse_substitution_keys::Entry[:])& =Entries_heads[buffer.lease-1].items;
 return Entries_heads[buffer.lease-1].owner_id==buffer.owner_id && buffer.storage .== storage && buffer.items .== items;
}
fn prepare(buffer: Entries&) -> Error {
    if buffer.lease != 0 { assert(valid(buffer)); return blot_error::Error.none; }
    if Entries_heads.len >= 4294967295 { return blot_error::Error.out_of_memory; } let owner_id = blot_native::fresh_owner_id(); let index = Entries_heads.alloc_index(EntriesHead { owner_id , ..}); let head: EntriesHead& = Entries_heads[index]; buffer = Entries { owner_id: owner_id,lease: (index + 1) as u32,storage: head.storage,items: head.items , ..}; return blot_error::Error.none;
}
fn publishEntries(head: EntriesHead&,view: blot_support_pooled_buffer::Buffer<blot_reuse_substitution_keys::Entry>) {
 assert(view.items.len<=view.storage.len);
 if view.storage.len==0 {assert(view.items.len==0);head.storage=default<blot_reuse_substitution_keys::Entry[:]>();head.items=default<blot_reuse_substitution_keys::Entry[:]>();return;}
 let owned=Entries_runs.realloc_slice(view.storage,view.storage.len);assert(blot_support::same_slice_identity(owned,view.storage));
 let start=Entries_runs.index_of(owned[0]);assert(start>=0 && view.storage.len<=Entries_runs.len-start);let storage=Entries_runs[start..start+view.storage.len];
 assert(blot_support::same_slice_identity(view.items,storage[..view.items.len]));head.storage=storage;head.items=storage[..view.items.len];
}

fn push(buffer: Entries&,value: blot_reuse_substitution_keys::Entry) -> Error { let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:EntriesHead& =Entries_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_reuse_substitution_keys::Entry> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::push(view,value,Entries_runs);publishEntries(head,view);return result; }
fn append(buffer: Entries&,values: const blot_reuse_substitution_keys::Entry[:]) -> Error { if values.len == 0 { return blot_error::Error.none; } let error = prepare(buffer); if error != blot_error::Error.none { return error; } let head:EntriesHead& =Entries_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_reuse_substitution_keys::Entry> {storage:head.storage,items:head.items};let result=blot_support_pooled_buffer::append(view,values,Entries_runs);publishEntries(head,view);return result; }
fn clear(buffer: Entries&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:EntriesHead& =Entries_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_reuse_substitution_keys::Entry> {storage:head.storage,items:head.items};blot_support_pooled_buffer::clear(view);publishEntries(head,view); }
fn resize(buffer: Entries&,length: i64) { if buffer.lease == 0 { assert(length == 0); return; } assert(valid(buffer)); let head:EntriesHead& =Entries_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_reuse_substitution_keys::Entry> {storage:head.storage,items:head.items};blot_support_pooled_buffer::resize(view,length);publishEntries(head,view); }
fn deinit(buffer: Entries&) { if buffer.lease == 0 { return; } assert(valid(buffer)); let head:EntriesHead& =Entries_heads[buffer.lease-1];var view=blot_support_pooled_buffer::Buffer<blot_reuse_substitution_keys::Entry> {storage:head.storage,items:head.items};blot_support_pooled_buffer::deinit(view,Entries_runs);publishEntries(head,view); let index = buffer.lease - 1; Entries_heads[index].owner_id = 0; Entries_heads.free(index); buffer = Entries {..}; }

struct MappingsRead { lease:u32=0,owner_id:u64=0,offset:i64=0,len:i64=0 }
fn valid(key:MappingsRead)->bool {if key.lease==0 {return key.owner_id==0 && key.offset==0 && key.len==0;}if key.lease-1>=Mappings_heads.len || key.owner_id==0 {return false;}let head:const MappingsHead& =Mappings_heads[key.lease-1];return head.owner_id==key.owner_id && key.offset>=0 && key.len>=0 && key.offset<=head.items.len && key.len<=head.items.len-key.offset;}
fn readKey(buffer:const Mappings&)->MappingsRead {if buffer.lease==0 {assert(buffer.items.len==0);return MappingsRead{};}assert(valid(buffer));return MappingsRead{lease:buffer.lease,owner_id:buffer.owner_id,len:buffer.items.len,..};}
fn read(key:MappingsRead)->const blot_backend_layout::Mapping[:] {assert(valid(key));if key.lease==0 {return default<const blot_backend_layout::Mapping[:]>();}let head:const MappingsHead& =Mappings_heads[key.lease-1];if key.len==0 {return default<const blot_backend_layout::Mapping[:]>();}let owned=Mappings_runs.realloc_slice(head.storage,head.storage.len);assert(blot_support::same_slice_identity(owned,head.storage));let start=Mappings_runs.index_of(owned[0]);assert(start>=0 && head.storage.len<=Mappings_runs.len-start && blot_support::same_slice_identity(head.items,owned[..head.items.len]));return Mappings_runs[start+key.offset..start+key.offset+key.len];}
fn takeRead(buffer:Mappings&)->MappingsRead {let key=readKey(buffer);buffer=Mappings{};return key;}
fn release(key:MappingsRead&) {if key.lease==0 {return;}assert(valid(key));let head:MappingsHead& =Mappings_heads[key.lease-1];assert(key.offset==0 && key.len==head.items.len);var owner=Mappings{owner_id:key.owner_id,lease:key.lease,storage:head.storage,items:head.items};owner.deinit();key=MappingsRead{};}
struct RowsRead { lease:u32=0,owner_id:u64=0,offset:i64=0,len:i64=0 }
fn valid(key:RowsRead)->bool {if key.lease==0 {return key.owner_id==0 && key.offset==0 && key.len==0;}if key.lease-1>=Rows_heads.len || key.owner_id==0 {return false;}let head:const RowsHead& =Rows_heads[key.lease-1];return head.owner_id==key.owner_id && key.offset>=0 && key.len>=0 && key.offset<=head.items.len && key.len<=head.items.len-key.offset;}
fn readKey(buffer:const Rows&)->RowsRead {if buffer.lease==0 {assert(buffer.items.len==0);return RowsRead{};}assert(valid(buffer));return RowsRead{lease:buffer.lease,owner_id:buffer.owner_id,len:buffer.items.len,..};}
fn read(key:RowsRead)->const blot_backend_layout::RowMapping[:] {assert(valid(key));if key.lease==0 {return default<const blot_backend_layout::RowMapping[:]>();}let head:const RowsHead& =Rows_heads[key.lease-1];if key.len==0 {return default<const blot_backend_layout::RowMapping[:]>();}let owned=Rows_runs.realloc_slice(head.storage,head.storage.len);assert(blot_support::same_slice_identity(owned,head.storage));let start=Rows_runs.index_of(owned[0]);assert(start>=0 && head.storage.len<=Rows_runs.len-start && blot_support::same_slice_identity(head.items,owned[..head.items.len]));return Rows_runs[start+key.offset..start+key.offset+key.len];}
fn takeRead(buffer:Rows&)->RowsRead {let key=readKey(buffer);buffer=Rows{};return key;}
fn release(key:RowsRead&) {if key.lease==0 {return;}assert(valid(key));let head:RowsHead& =Rows_heads[key.lease-1];assert(key.offset==0 && key.len==head.items.len);var owner=Rows{owner_id:key.owner_id,lease:key.lease,storage:head.storage,items:head.items};owner.deinit();key=RowsRead{};}
