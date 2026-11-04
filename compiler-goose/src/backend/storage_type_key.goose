namespace blot_backend_storage_type_key;
import dictionary;
import support.error;
import support.option;
import support.wyhash;

struct Reference { unit: u32 = 0, ty: u32 = 0, environment: i64 = 0, environment_len: i64 = 0, captured: bool = false }
fn hash(reference: Reference) -> u64 {
    var state = blot_support_wyhash::init(0); blot_support_wyhash::value(state, reference.unit); blot_support_wyhash::value(state, reference.ty);
    blot_support_wyhash::value(state, reference.environment as u64); blot_support_wyhash::value(state, reference.environment_len as u64); blot_support_wyhash::value(state, reference.captured); return blot_support_wyhash::final(state);
}
struct Result { id: u32 = 0, height: i64 = 0 }
struct Options { encoded_words: i64 = 65536, word_work: i64 = 262144, hash_mask: u64 = 18446744073709551615 }
struct Node { start: i64 = 0, len: i64 = 0, height: i64 = 0, next: blot_support::Option<u32> }
enum Memo { active { depth: i64 }, complete { result: Result } }
struct Builder {
    remaining: i64&, options: Options, word_work: i64,
    words: u32[>..<]&, scratch: u32[>..<]&, nodes: Node[>..<]&, buckets: dictionary<u64, u32>&, memo: dictionary<Reference, Memo>&,
    inline_memo: blot_support::Option<Memo>[5] = [blot_support::Option<Memo> {}; 5], poisoned: bool = false, finished: bool = false,
}
fn init(remaining: i64&, options: Options, words: u32[>..<]&, scratch: u32[>..<]&, nodes: Node[>..<]&, buckets: dictionary<u64, u32>&, memo: dictionary<Reference, Memo>&) -> Builder {
    return Builder { remaining: remaining, options: options, word_work: options.word_work, words: words, scratch: scratch, nodes: nodes, buckets: buckets, memo: memo };
}
fn fail(builder: Builder&, error: blot_error::Error) -> blot_error::Error { builder.poisoned = true; return error; }
fn charge(builder: Builder&) -> blot_error::Error { if builder.poisoned || builder.finished || builder.remaining == 0 { return blot_error::Error.limit; } builder.remaining--; return blot_error::Error.none; }
fn wordWork(builder: Builder&, count: i64) -> blot_error::Error { if builder.poisoned || builder.finished || count > builder.word_work { return blot_error::Error.limit; } builder.word_work -= count; return blot_error::Error.none; }
fn encodedSize(builder: Builder&) -> i64, blot_error::Error {
    if builder.nodes.len > 9223372036854775803 - builder.words.len { return 0, blot_error::Error.limit; } return builder.words.len + builder.nodes.len + 4, blot_error::Error.none;
}
fn inlineIndex(reference: Reference) -> blot_support::Option<i64> { if reference.unit != 0 || reference.ty < 1 || reference.ty > 5 || reference.environment != 0 || reference.environment_len != 0 || reference.captured { return blot_support::none<i64>(); } return blot_support::some(reference.ty as i64 - 1); }
fn completedAtDepth(entry: Memo, depth: i64) -> blot_support::Option<Result>, blot_error::Error {
    match entry { active a => return blot_support::none<Result>(), blot_error::Error.cycle, complete c => { if c.result.height > 128 - depth { return blot_support::none<Result>(), blot_error::Error.limit; } return blot_support::some(c.result), blot_error::Error.none; } }
}
fn enter(builder: Builder&, reference: Reference, depth: i64) -> blot_support::Option<Result>, blot_error::Error {
    let error = charge(builder); if error != blot_error::Error.none { return blot_support::none<Result>(), fail(builder, error); }
    if depth > 128 { return blot_support::none<Result>(), fail(builder, blot_error::Error.limit); }
    let index = inlineIndex(reference);
    if index.present {
        let known = builder.inline_memo[index.value];
        if known.present { let result, error = completedAtDepth(known.value, depth); if error != blot_error::Error.none { return result, fail(builder, error); } return result, error; }
        builder.inline_memo[index.value] = blot_support::some<Memo>(Memo.active { depth: depth }); return blot_support::none<Result>(), blot_error::Error.none;
    }
    var known = blot_support::none<Memo>(); block { let entry = builder.memo.get(reference); if entry { known = blot_support::some(copy(entry)); } }
    if known.present { let result, error = completedAtDepth(known.value, depth); if error != blot_error::Error.none { return result, fail(builder, error); } return result, error; }
    builder.memo.insert(reference, Memo.active { depth: depth }); return blot_support::none<Result>(), blot_error::Error.none;
}
fn addWord(builder: Builder&, descriptor: u32[>..<]&, word: u32) -> blot_error::Error {
    if descriptor.len >= builder.options.encoded_words { return fail(builder, blot_error::Error.limit); } let error = wordWork(builder, 1); if error != blot_error::Error.none { return fail(builder, error); } descriptor.push(word); return blot_error::Error.none;
}
fn addWords(builder: Builder&, descriptor: u32[>..<]&, words: const u32[:]) -> blot_error::Error {
    if descriptor.len > builder.options.encoded_words || words.len > builder.options.encoded_words - descriptor.len { return fail(builder, blot_error::Error.limit); }
    let error = wordWork(builder, words.len); if error != blot_error::Error.none { return fail(builder, error); } descriptor.append(words); return blot_error::Error.none;
}
fn beginDescriptor(builder: Builder&) -> i64 { builder.scratch.len }
fn endDescriptor(builder: Builder&, start: i64) { builder.scratch.resize(start); }
fn descriptorWord(builder: Builder&, start: i64, word: u32) -> blot_error::Error {
    if start > builder.scratch.len || builder.scratch.len - start >= builder.options.encoded_words { return fail(builder, blot_error::Error.limit); }
    let error = wordWork(builder, 1); if error != blot_error::Error.none { return fail(builder, error); } builder.scratch.push(word); return blot_error::Error.none;
}
fn descriptorWords(builder: Builder&, start: i64, words: const u32[:]) -> blot_error::Error {
    if start > builder.scratch.len { return fail(builder, blot_error::Error.limit); } let length = builder.scratch.len - start;
    if length > builder.options.encoded_words || words.len > builder.options.encoded_words - length { return fail(builder, blot_error::Error.limit); }
    let error = wordWork(builder, words.len); if error != blot_error::Error.none { return fail(builder, error); } builder.scratch.append(words); return blot_error::Error.none;
}
fn completeDescriptor(builder: Builder&, reference: Reference, start: i64, height: i64) -> Result, blot_error::Error {
    if start > builder.scratch.len { return Result {}, fail(builder, blot_error::Error.limit); } return complete(builder, reference, builder.scratch[start..], height);
}
fn equal(builder: Builder&, stored: const u32[:], candidate: const u32[:]) -> bool, blot_error::Error {
    if stored.len != candidate.len { return false, blot_error::Error.none; }
    for a, index in stored { let error = wordWork(builder, 1); if error != blot_error::Error.none { return false, error; } if a != candidate[index] { return false, blot_error::Error.none; } } return true, blot_error::Error.none;
}
fn getMemo(builder: Builder&, reference: Reference) -> blot_support::Option<Memo> {
    let inline = inlineIndex(reference); if inline.present { return builder.inline_memo[inline.value]; }
    let found = builder.memo.get(reference); if found { return blot_support::some(copy(found)); } return blot_support::none<Memo>();
}
fn setMemo(builder: Builder&, reference: Reference, result: Result) {
    let value = Memo.complete { result: result }; let inline = inlineIndex(reference);
    if inline.present { builder.inline_memo[inline.value] = blot_support::some<Memo>(value); } else { builder.memo.insert(reference, value); }
}
fn complete(builder: Builder&, reference: Reference, descriptor: const u32[:], height: i64) -> Result, blot_error::Error {
    if builder.poisoned || builder.finished || height > 128 { return Result {}, fail(builder, blot_error::Error.limit); }
    let pending = getMemo(builder, reference); if !pending.present { return Result {}, fail(builder, blot_error::Error.cycle); }
    var active_depth: i64 = -1; match pending.value { active a => active_depth = a.depth, complete c => {} }
    if active_depth < 0 { return Result {}, fail(builder, blot_error::Error.cycle); }
    if height > 128 - active_depth { return Result {}, fail(builder, blot_error::Error.limit); }
    var error = wordWork(builder, descriptor.len); if error != blot_error::Error.none { return Result {}, fail(builder, error); }
    var state = blot_support_wyhash::init(0); for word in descriptor { blot_support_wyhash::value(state, word); } let hash = blot_support_wyhash::final(state) & builder.options.hash_mask;
    var next = blot_support::none<u32>(); block { let found = builder.buckets.get(hash); if found { next = blot_support::some(copy(found)); } }
    while next.present {
        error = charge(builder); if error != blot_error::Error.none { return Result {}, fail(builder, error); }
        let node = builder.nodes[next.value]; let same, compared = equal(builder, builder.words[node.start..node.start + node.len], descriptor); if compared != blot_error::Error.none { return Result {}, fail(builder, compared); }
        if same { if node.height != height { return Result {}, fail(builder, blot_error::Error.cycle); } let result = Result { id: next.value, height: height }; setMemo(builder, reference, result); return result, blot_error::Error.none; }
        next = node.next;
    }
    if descriptor.len == 9223372036854775807 { return Result {}, fail(builder, blot_error::Error.limit); }
    let growth = descriptor.len + 1; let encoded, size_error = encodedSize(builder); if size_error != blot_error::Error.none { return Result {}, fail(builder, size_error); }
    if encoded > builder.options.encoded_words || growth > builder.options.encoded_words - encoded || builder.nodes.len > 4294967295 { return Result {}, fail(builder, blot_error::Error.limit); }
    error = wordWork(builder, descriptor.len); if error != blot_error::Error.none { return Result {}, fail(builder, error); }
    let id = builder.nodes.len as u32; var previous = blot_support::none<u32>(); block { let old = builder.buckets.get(hash); if old { previous = blot_support::some(copy(old)); } }
    let start = builder.words.len; builder.words.append(descriptor); builder.nodes.push(Node { start: start, len: descriptor.len, height: height, next: previous }); builder.buckets.insert(hash, id);
    let result = Result { id: id, height: height }; setMemo(builder, reference, result); return result, blot_error::Error.none;
}
fn root(builder: Builder&, output: u32[>..<]&, result: Result) -> blot_error::Error {
    if result.id >= builder.nodes.len || builder.nodes[result.id].height != result.height { return fail(builder, blot_error::Error.limit); }
    let table, error = encodedSize(builder); if error != blot_error::Error.none { return fail(builder, error); }
    if table >= builder.options.encoded_words || output.len >= builder.options.encoded_words - table { return fail(builder, blot_error::Error.limit); }
    let work_error = wordWork(builder, 1); if work_error != blot_error::Error.none { return fail(builder, work_error); } output.push(result.id); return blot_error::Error.none;
}
fn finish(builder: Builder&, output: u32[>..<]&) -> blot_error::Error {
    if builder.poisoned || builder.finished { return fail(builder, blot_error::Error.limit); }
    for maybe in builder.inline_memo { if !maybe.present { continue; } let error = charge(builder); if error != blot_error::Error.none { return fail(builder, error); } match maybe.value { active a => return fail(builder, blot_error::Error.cycle), complete c => {} } }
    // Dictionary traversal order cannot change success: each memo costs exactly
    // one charge, and unfinished entries all reject before publication.
    var memo_error = blot_error::Error.none;
    builder.memo.each() { key, value =>
        if memo_error == blot_error::Error.none { memo_error = charge(builder); }
        if memo_error == blot_error::Error.none { match value { active a => memo_error = blot_error::Error.cycle, complete c => {} } }
    };
    if memo_error != blot_error::Error.none { return fail(builder, memo_error); }
    let count, error = encodedSize(builder); if error != blot_error::Error.none { return fail(builder, error); }
    if count > builder.options.encoded_words || output.len > builder.options.encoded_words - count { return fail(builder, blot_error::Error.limit); }
    let work_error = wordWork(builder, count); if work_error != blot_error::Error.none { return fail(builder, work_error); }
    output.append([0x53444b31, 1, builder.nodes.len as u32, builder.words.len as u32]);
    for node in builder.nodes { output.push(node.len as u32); output.append(builder.words[node.start..node.start + node.len]); }
    builder.finished = true; return blot_error::Error.none;
}
fn deinit(builder: Builder&) { builder.memo.clear(); builder.buckets.clear(); builder.nodes.clear(); builder.words.clear(); builder.scratch.clear(); }
