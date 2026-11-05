// Only completed structural descriptors enter the canonical selected-call DAG.
namespace blot_backend_storage_type_key;
import dictionary;
import support.error;
import support.option;
import support.wyhash;
import support.pooled_buffer;
import support.pooled_map;
type Error = blot_error::Error;
struct Reference { unit: u32 = 0,ty: u32 = 0,environment: i64 = 0,environment_len: i64 = 0,captured: bool = false }
fn hash(reference: Reference) -> u64 { var state = blot_support_wyhash::init(0); blot_support_wyhash::value(state,reference.unit); blot_support_wyhash::value(state,reference.ty); blot_support_wyhash::value(state,reference.environment as u64); blot_support_wyhash::value(state,reference.environment_len as u64); blot_support_wyhash::value(state,reference.captured); return blot_support_wyhash::final(state); }
struct Result { id: u32 = 0,height: i64 = 0 }
struct Options { encoded_words: i64 = 65536,word_work: i64 = 262144,hash_mask: u64 = 18446744073709551615 }
struct Node { start: i64 = 0,len: i64 = 0,height: i64 = 0,next: blot_support::Option<u32> }
enum Memo { active { depth: i64 },complete { result: Result } }
struct Words { storage: u32[:] = default<u32[:]>(),items: u32[:] = default<u32[:]>() }
struct Nodes { storage: Node[:] = default<Node[:]>(),items: Node[:] = default<Node[:]>() }
reusable[] var word_runs: u32[>..] = [];
reusable[] var owned_words: u32[>..] = [];
reusable[] var node_runs: Node[>..] = [];
reusable[] var bucket_slots: dictionary_slot<u64,u32>[>..] = [];
reusable[] var memo_slots: dictionary_slot<Reference,Memo>[>..] = [];
fn push(words: Words&,word: u32) -> Error { blot_support_pooled_buffer::push(words,word,word_runs) }
fn append(words: Words&,values: const u32[:]) -> Error { blot_support_pooled_buffer::append(words,values,word_runs) }
fn resize(words: Words&,length: i64) { blot_support_pooled_buffer::resize(words,length); }
fn deinit(words: Words&) { blot_support_pooled_buffer::deinit(words,word_runs); }
fn toOwned(words: Words&) -> const u32[:],Error { let values = owned_words.alloc_slice(words.items.len); for value,index in words.items { values[index] = value; } words.deinit(); return values,blot_error::Error.none; }
fn release(values: const u32[:]) { if values.len != 0 { owned_words.free_slice(values); } }
fn length(words: Words&) -> i64 { words.items.len }
fn length(words: u32[>..<]&) -> i64 { words.len }
fn appendOutput(words: Words&,word: u32) -> Error { words.push(word) }
fn appendOutput(words: Words&,values: const u32[:]) -> Error { words.append(values) }
fn appendOutput(words: u32[>..<]&,word: u32) -> Error { words.push(word); return blot_error::Error.none; }
fn appendOutput(words: u32[>..<]&,values: const u32[:]) -> Error { words.append(values); return blot_error::Error.none; }
struct Builder {
    remaining: i64,options: Options,word_work: i64,words: Words,scratch: Words,nodes: Nodes,buckets: blot_support_pooled_map::Map<u64,u32>,memo: blot_support_pooled_map::Map<Reference,Memo>,
    inline_memo: blot_support::Option<Memo>[5] = [blot_support::Option<Memo> {..};5],poisoned: bool = false,finished: bool = false,
}
fn init(remaining: i64,options: Options = Options {..}) -> Builder { Builder { remaining: remaining,options: options,word_work: options.word_work,.. } }
fn deinit(builder: Builder&) { blot_support_pooled_map::deinit(builder.memo,memo_slots); blot_support_pooled_map::deinit(builder.buckets,bucket_slots); blot_support_pooled_buffer::deinit(builder.nodes,node_runs); builder.words.deinit(); builder.scratch.deinit(); }
fn fail(builder: Builder&,error: Error) -> Error { builder.poisoned = true; return error; }
fn charge(builder: Builder&) -> Error { if builder.poisoned || builder.finished || builder.remaining == 0 { return blot_error::Error.limit; } builder.remaining--; return blot_error::Error.none; }
fn wordWork(builder: Builder&,count: i64) -> Error { if builder.poisoned || builder.finished || count > builder.word_work { return blot_error::Error.limit; } builder.word_work -= count; return blot_error::Error.none; }
fn encodedSize(builder: Builder&) -> i64,Error { if builder.nodes.items.len > 9223372036854775803 - builder.words.items.len { return 0,blot_error::Error.limit; } return builder.words.items.len + builder.nodes.items.len + 4,blot_error::Error.none; }
fn inlineIndex(reference: Reference) -> blot_support::Option<i64> { if reference.unit != 0 || reference.ty < 1 || reference.ty > 5 || reference.environment != 0 || reference.environment_len != 0 || reference.captured { return blot_support::none<i64>(); } return blot_support::some(reference.ty as i64 - 1); }
fn completedAtDepth(entry: Memo,depth: i64) -> blot_support::Option<Result>,Error { match entry { active a=>{ return blot_support::none<Result>(),blot_error::Error.cycle; },complete c=>{ if c.result.height > 128 - depth { return blot_support::none<Result>(),blot_error::Error.limit; } return blot_support::some(c.result),blot_error::Error.none; }, } }
fn enter(builder: Builder&,reference: Reference,depth: i64) -> blot_support::Option<Result>,Error {
    let charged = charge(builder); if charged != blot_error::Error.none { return blot_support::none<Result>(),fail(builder,charged); } if depth > 128 { return blot_support::none<Result>(),fail(builder,blot_error::Error.limit); } let inline = inlineIndex(reference);
    if inline.present { let known = builder.inline_memo[inline.value]; if known.present { let result,error = completedAtDepth(known.value,depth); if error != blot_error::Error.none { return result,fail(builder,error); } return result,error; } builder.inline_memo[inline.value] = blot_support::some<Memo>(Memo.active { depth , ..}); return blot_support::none<Result>(),blot_error::Error.none; }
    let known .= blot_support_pooled_map::get(builder.memo,reference); if known { let result,error = completedAtDepth(known,depth); if error != blot_error::Error.none { return result,fail(builder,error); } return result,error; } let pending:Memo=Memo.active{depth:depth};blot_support_pooled_map::insert(builder.memo,reference,pending,memo_slots); return blot_support::none<Result>(),blot_error::Error.none;
}
fn addWord<D>(builder: Builder&,descriptor: D&,word: u32) -> Error { if length(descriptor) >= builder.options.encoded_words { return fail(builder,blot_error::Error.limit); } let work = wordWork(builder,1); if work != blot_error::Error.none { return fail(builder,work); } let appended = appendOutput(descriptor,word); if appended != blot_error::Error.none { return fail(builder,appended); } return blot_error::Error.none; }
fn addWords<D>(builder: Builder&,descriptor: D&,words: const u32[:]) -> Error { let count = length(descriptor); if count > builder.options.encoded_words || words.len > builder.options.encoded_words - count { return fail(builder,blot_error::Error.limit); } let work = wordWork(builder,words.len); if work != blot_error::Error.none { return fail(builder,work); } let appended = appendOutput(descriptor,words); if appended != blot_error::Error.none { return fail(builder,appended); } return blot_error::Error.none; }
fn beginDescriptor(builder: Builder&) -> i64 { builder.scratch.items.len }
fn endDescriptor(builder: Builder&,start: i64) { builder.scratch.resize(start); }
fn descriptorWord(builder: Builder&,start: i64,word: u32) -> Error { if start > builder.scratch.items.len || builder.scratch.items.len - start >= builder.options.encoded_words { return fail(builder,blot_error::Error.limit); } let work = wordWork(builder,1); if work != blot_error::Error.none { return fail(builder,work); } let appended = builder.scratch.push(word); if appended != blot_error::Error.none { return fail(builder,appended); } return blot_error::Error.none; }
fn descriptorWords(builder: Builder&,start: i64,words: const u32[:]) -> Error { if start > builder.scratch.items.len { return fail(builder,blot_error::Error.limit); } let count = builder.scratch.items.len - start; if count > builder.options.encoded_words || words.len > builder.options.encoded_words - count { return fail(builder,blot_error::Error.limit); } let work = wordWork(builder,words.len); if work != blot_error::Error.none { return fail(builder,work); } let appended = builder.scratch.append(words); if appended != blot_error::Error.none { return fail(builder,appended); } return blot_error::Error.none; }
fn completeDescriptor(builder: Builder&,reference: Reference,start: i64,height: i64) -> Result,Error { if start > builder.scratch.items.len { return Result {..},fail(builder,blot_error::Error.limit); } return complete(builder,reference,builder.scratch.items[start..],height); }
fn equal(builder: Builder&,stored: const u32[:],candidate: const u32[:]) -> bool,Error { if stored.len != candidate.len { return false,blot_error::Error.none; } for value,index in stored { let work = wordWork(builder,1); if work != blot_error::Error.none { return false,work; } if value != candidate[index] { return false,blot_error::Error.none; } } return true,blot_error::Error.none; }
fn getMemo(builder: Builder&,reference: Reference) -> blot_support::Option<Memo> { let inline = inlineIndex(reference); if inline.present { return builder.inline_memo[inline.value]; } let found .= blot_support_pooled_map::get(builder.memo,reference); if found { return blot_support::some<Memo>(found); } return blot_support::none<Memo>(); }
fn setMemo(builder: Builder&,reference: Reference,result: Result) { let value:Memo = Memo.complete { result , ..}; let inline = inlineIndex(reference); if inline.present { builder.inline_memo[inline.value] = blot_support::some<Memo>(value); } else { blot_support_pooled_map::insert(builder.memo,reference,value,memo_slots); } }
fn complete(builder: Builder&,reference: Reference,descriptor: const u32[:],height: i64) -> Result,Error {
    if builder.poisoned || builder.finished || height > 128 { return Result {..},fail(builder,blot_error::Error.limit); } let pending = getMemo(builder,reference); if !pending.present { return Result {..},fail(builder,blot_error::Error.cycle); } var active_depth: i64 = -1; match pending.value { active a=>{ active_depth = a.depth; },complete=>{}, } if active_depth < 0 { return Result {..},fail(builder,blot_error::Error.cycle); } if height > 128 - active_depth { return Result {..},fail(builder,blot_error::Error.limit); }
    let work = wordWork(builder,descriptor.len); if work != blot_error::Error.none { return Result {..},fail(builder,work); } var state = blot_support_wyhash::init(0); for word in descriptor { blot_support_wyhash::value(state,word); } let hash = blot_support_wyhash::final(state) & builder.options.hash_mask; var next = blot_support::none<u32>(); let first .= blot_support_pooled_map::get(builder.buckets,hash); if first { next = blot_support::some<u32>(first); }
    while next.present { let charged = charge(builder); if charged != blot_error::Error.none { return Result {..},fail(builder,charged); } let node = builder.nodes.items[next.value]; let same,error = equal(builder,builder.words.items[node.start..node.start + node.len],descriptor); if error != blot_error::Error.none { return Result {..},fail(builder,error); } if same { if node.height != height { return Result {..},fail(builder,blot_error::Error.cycle); } let result = Result { id: next.value,height: height , ..}; setMemo(builder,reference,result); return result,blot_error::Error.none; } next = node.next; }
    if descriptor.len == 9223372036854775807 { return Result {..},fail(builder,blot_error::Error.limit); } let growth = descriptor.len + 1; let encoded,encoded_error = encodedSize(builder); if encoded_error != blot_error::Error.none { return Result {..},fail(builder,encoded_error); } if encoded > builder.options.encoded_words || growth > builder.options.encoded_words - encoded || builder.nodes.items.len > 4294967295 { return Result {..},fail(builder,blot_error::Error.limit); }
    let charged = wordWork(builder,descriptor.len); if charged != blot_error::Error.none { return Result {..},fail(builder,charged); } let id = builder.nodes.items.len as u32; var previous = blot_support::none<u32>(); let bucket .= blot_support_pooled_map::get(builder.buckets,hash); if bucket { previous = blot_support::some<u32>(bucket); } let start = builder.words.items.len; let appended = builder.words.append(descriptor); if appended != blot_error::Error.none { return Result {..},fail(builder,appended); } let pushed = blot_support_pooled_buffer::push(builder.nodes,Node { start: start,len: descriptor.len,height: height,next: previous , ..},node_runs); if pushed != blot_error::Error.none { return Result {..},fail(builder,pushed); } blot_support_pooled_map::insert(builder.buckets,hash,id,bucket_slots); let result = Result { id,height , ..}; setMemo(builder,reference,result); return result,blot_error::Error.none;
}
fn root<D>(builder: Builder&,output: D&,result: Result) -> Error { if result.id >= builder.nodes.items.len || builder.nodes.items[result.id].height != result.height { return fail(builder,blot_error::Error.limit); } let table,error = encodedSize(builder); if error != blot_error::Error.none { return fail(builder,error); } let count = length(output); if table >= builder.options.encoded_words || count >= builder.options.encoded_words - table { return fail(builder,blot_error::Error.limit); } let work = wordWork(builder,1); if work != blot_error::Error.none { return fail(builder,work); } let appended = appendOutput(output,result.id); if appended != blot_error::Error.none { return fail(builder,appended); } return blot_error::Error.none; }
fn finish<D>(builder: Builder&,output: D&) -> Error {
    if builder.poisoned || builder.finished { return fail(builder,blot_error::Error.limit); } for maybe in builder.inline_memo { if !maybe.present { continue; } let charged = charge(builder); if charged != blot_error::Error.none { return fail(builder,charged); } match maybe.value { active=>{ return fail(builder,blot_error::Error.cycle); },complete=>{}, } }
    for slot in builder.memo.slots { if slot.tag == 0 { continue; } let charged = charge(builder); if charged != blot_error::Error.none { return fail(builder,charged); } match slot.val { active=>{ return fail(builder,blot_error::Error.cycle); },complete=>{}, } }
    let count,error = encodedSize(builder); if error != blot_error::Error.none { return fail(builder,error); } if count > builder.options.encoded_words || length(output) > builder.options.encoded_words - count { return fail(builder,blot_error::Error.limit); } let work = wordWork(builder,count); if work != blot_error::Error.none { return fail(builder,work); }
    let header = appendOutput(output,[0x53444b31,1,builder.nodes.items.len as u32,builder.words.items.len as u32]); if header != blot_error::Error.none { return fail(builder,header); }
    for node in builder.nodes.items { let size = appendOutput(output,node.len as u32); if size != blot_error::Error.none { return fail(builder,size); } let words = appendOutput(output,builder.words.items[node.start..node.start + node.len]); if words != blot_error::Error.none { return fail(builder,words); } } builder.finished = true; return blot_error::Error.none;
}
fn clear(words: Words&) { words.resize(0); }
