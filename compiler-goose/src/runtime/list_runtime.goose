// Persistent AVL sequences detach a shared spine and consume exclusive nodes.
// Tokens preserve owning allocation bases; spare reference words stay zero.
namespace blot_runtime_list_runtime;
import backend.wasm;
import backend.runtime_ir;
import backend.runtime_code;
import runtime.runtime_layout;
import runtime.arena_runtime;
import runtime.cycles_runtime;
import runtime.root_runtime;
import reuse.artifact_emitter;
import support.emitter;
import support.error;
import support.option;
type Error = blot_error::Error;
type Module = blot_backend_wasm::Module;
type Arena = blot_backend_wasm::Arena;
type Local = blot_backend_runtime_code::Local;
type Code = blot_emitter::Emitter<Module>;
type Instruction = blot_backend_runtime_ir::Instruction;
struct Runtime {
    new: u32,
    address: u32,
    copy: u32,
    push: u32,
    set: u32,
    from_array: u32,
    to_array: u32,
    chunk_new: u32,
    edit: u32,
    branch: u32,
    own: u32,
    insert: u32,
    replace: u32,
    refresh: u32,
    rotate_left: u32,
    rotate_right: u32,
    balance: u32,
    concat: u32,
    slice: u32,
    join: u32,
    cut: u32,
    directory: u32,
    leaf_count: u32,
    write_leaves: u32,
    address_unchecked: blot_support::Option<u32>,
    set_unchecked: blot_support::Option<u32>,
    snapshot: blot_support::Option<u32>,
}
fn functionId(receiver: Runtime, field: const u8[:]) -> blot_support::Option<u32> {
    if field == "new" { return blot_support::some(receiver.new); }
    if field == "address" { return blot_support::some(receiver.address); }
    if field == "copy" { return blot_support::some(receiver.copy); }
    if field == "push" { return blot_support::some(receiver.push); }
    if field == "set" { return blot_support::some(receiver.set); }
    if field == "from_array" { return blot_support::some(receiver.from_array); }
    if field == "to_array" { return blot_support::some(receiver.to_array); }
    if field == "chunk_new" { return blot_support::some(receiver.chunk_new); }
    if field == "edit" { return blot_support::some(receiver.edit); }
    if field == "branch" { return blot_support::some(receiver.branch); }
    if field == "own" { return blot_support::some(receiver.own); }
    if field == "insert" { return blot_support::some(receiver.insert); }
    if field == "replace" { return blot_support::some(receiver.replace); }
    if field == "refresh" { return blot_support::some(receiver.refresh); }
    if field == "rotate_left" { return blot_support::some(receiver.rotate_left); }
    if field == "rotate_right" { return blot_support::some(receiver.rotate_right); }
    if field == "balance" { return blot_support::some(receiver.balance); }
    if field == "concat" { return blot_support::some(receiver.concat); }
    if field == "slice" { return blot_support::some(receiver.slice); }
    if field == "join" { return blot_support::some(receiver.join); }
    if field == "cut" { return blot_support::some(receiver.cut); }
    if field == "directory" { return blot_support::some(receiver.directory); }
    if field == "leaf_count" { return blot_support::some(receiver.leaf_count); }
    if field == "write_leaves" { return blot_support::some(receiver.write_leaves); }
    if field == "address_unchecked" { return receiver.address_unchecked; }
    if field == "set_unchecked" { return receiver.set_unchecked; }
    if field == "snapshot" { return receiver.snapshot; }
    return blot_support::none<u32>();
}
let frozen: u32 = 1; let acyclic_elements: u32 = 2; let acyclic_kind: u32 = acyclic_elements << 7; let width_bits: u32 = acyclic_kind - 1;
let header: u32 = blot_runtime_runtime_layout::ListNode_bytes;
let capacity: u32 = (1024 - blot_runtime_runtime_layout::ArenaHeader_bytes - header) / 4;
let descriptor_bytes: u32 = blot_runtime_runtime_layout::ListDescriptor_bytes; let limit: u32 = 0x10000000;
fn leafLimit(words: u32) -> u32 { assert(words >= 1 && words <= 16); return capacity / words * words; }
let d_length: u32 = blot_runtime_runtime_layout::ListDescriptor_length;
let d_root: u32 = blot_runtime_runtime_layout::ListDescriptor_root;
let d_cached_leaf: u32 = blot_runtime_runtime_layout::ListDescriptor_cached_leaf;
let d_cached_base: u32 = blot_runtime_runtime_layout::ListDescriptor_cached_base;
let d_scalar_elements: u32 = blot_runtime_runtime_layout::ListDescriptor_scalar_elements;
let d_immutable: u32 = blot_runtime_runtime_layout::ListDescriptor_immutable;
let d_leaf_limit: u32 = blot_runtime_runtime_layout::ListDescriptor_leaf_limit;
let d_directory: u32 = blot_runtime_runtime_layout::ListDescriptor_directory;
let n_owner_token: u32 = blot_runtime_runtime_layout::ListBranch_owner_token;
let n_height: u32 = blot_runtime_runtime_layout::ListBranch_height;
let n_length: u32 = blot_runtime_runtime_layout::ListBranch_length;
let n_capacity: u32 = blot_runtime_runtime_layout::ListBranch_capacity;
let n_left: u32 = blot_runtime_runtime_layout::ListBranch_left;
let n_right: u32 = blot_runtime_runtime_layout::ListBranch_right;
fn function(module: Module&, parameters: i64, result: blot_backend_runtime_ir::ValueType) -> u32, Error {
    assert(parameters >= 0 && parameters <= 4); let types = [blot_backend_runtime_ir::VT_i32; 4]; return module.addFunction(types[..parameters], result);
}
fn reference(c: Code&, address: u32) {
    if c.failure != blot_error::Error.none { return; }
    c.failure = c.code.module.emitReference(c.code.function, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,address), blot_reuse_artifact_emitter::Role.static_address);
}
fn proof(descriptor: Local) -> Instruction[7] {
    return [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,descriptor.id), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,d_scalar_elements), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,descriptor.id), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,d_immutable), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,acyclic_elements), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_and), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_or)];
}
fn kindOf(descriptor: Local) -> Instruction[9] {
    return [blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,descriptor.id), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,d_scalar_elements), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,descriptor.id), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,d_immutable), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,acyclic_elements), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_and), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,7), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_shl), blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_or)];
}
fn acyclic(c: Code&, arena: Arena, value: Local, proven: const Instruction[:]) {
    c.globalGet(arena.rc_enabled); c.when(); c.value(proven); c.when();
    c.value(value); c.value(blot_runtime_runtime_layout::ArenaHeader_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(value); c.value(blot_runtime_runtime_layout::ArenaHeader_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.load(blot_runtime_runtime_layout::ArenaHeader_flags); c.value(blot_runtime_cycles_runtime::no_cycle); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(blot_runtime_runtime_layout::ArenaHeader_flags);
    c.end(); c.end();
}
fn freeze(c: Code&, descriptor: Local) { c.value(descriptor); c.value(descriptor); c.value(d_immutable); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(descriptor); c.load(d_immutable); c.value(frozen); c.op(blot_backend_runtime_ir::OP_i32_or); c.call(c.code.module.arena.value.store_word); }
fn emit(module: Module&, arena: Arena) -> Runtime, Error {
    var r = default<Runtime>();
    { let id, error = function(module, 3, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.new = id; }
    { let id, error = function(module, 2, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.address = id; }
    { let id, error = function(module, 2, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.copy = id; }
    { let id, error = function(module, 4, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.push = id; }
    { let id, error = function(module, 4, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.set = id; }
    { let id, error = function(module, 2, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.from_array = id; }
    { let id, error = function(module, 1, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.to_array = id; }
    { let id, error = function(module, 2, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.chunk_new = id; }
    { let id, error = function(module, 2, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.edit = id; }
    { let id, error = function(module, 3, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.branch = id; }
    { let id, error = function(module, 2, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.own = id; }
    { let id, error = function(module, 4, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.insert = id; }
    { let id, error = function(module, 4, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.replace = id; }
    { let id, error = function(module, 1, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.refresh = id; }
    { let id, error = function(module, 2, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.rotate_left = id; }
    { let id, error = function(module, 2, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.rotate_right = id; }
    { let id, error = function(module, 2, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.balance = id; }
    { let id, error = function(module, 2, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.concat = id; }
    { let id, error = function(module, 3, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.slice = id; }
    { let id, error = function(module, 3, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.join = id; }
    { let id, error = function(module, 4, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.cut = id; }
    { let id, error = function(module, 1, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.directory = id; }
    { let id, error = function(module, 1, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.leaf_count = id; }
    { let id, error = function(module, 3, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return default<Runtime>(), error; } r.write_leaves = id; }
    { var c = blot_emitter::init(module, r.chunk_new); emitNode(c, r, arena); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.branch); emitBranch(c, r, arena); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.refresh); emitRefresh(c); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.own); emitOwn(c, arena); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.rotate_left); emitRotate(c, r, true); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.rotate_right); emitRotate(c, r, false); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.balance); emitBalance(c, r); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.insert); emitInsert(c, r); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.replace); emitReplace(c, r); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.new); emitNew(c, r, arena); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.address); emitAddress(c, true); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.copy); emitCopy(c, r); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.edit); emitEdit(c, arena); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.push); emitPush(c, r); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.set); emitSet(c, r, true); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.from_array); emitConversion(c, r, arena, true); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.to_array); emitConversion(c, r, arena, false); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.join); emitJoin(c, r); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.cut); emitCut(c, r); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.concat); emitConcat(c, r, arena); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.slice); emitSlice(c, r, arena); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.leaf_count); emitLeafCount(c, r); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.write_leaves); emitWriteLeaves(c, r); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    { var c = blot_emitter::init(module, r.directory); emitDirectory(c, r, arena); if c.failure != blot_error::Error.none { return default<Runtime>(), c.failure; } }
    return r, blot_error::Error.none;
}
fn emitNode(c: Code&, r: Runtime, arena: Arena) {
    let count = Local { 0 , ..};
    let owner = Local { 1 , ..};
    let node = c.temp();
    let bucket = c.temp();
    let left = c.temp();
    let split = c.temp();
    let leaf_limit = c.temp();
    c.value(owner); c.load(d_leaf_limit); c.set(leaf_limit);
    c.value(count); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(0); c.ret();
    c.end();
    c.value(count); c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when();
    // Split by leaf count, not element count, to keep initial leaves dense.
    c.value(count); c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.value(2); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_mul); c.set(split);
    c.value(split); c.value(owner); c.call(r.chunk_new); c.set(left);
    c.value(left); c.value(count); c.value(split); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(owner); c.call(r.chunk_new); c.value(owner); c.call(r.branch); c.ret();
    c.end();
    // Buckets are exact power-of-two allocator classes. Leaves skip the 1.5x
    // companion classes so that growth by one element keeps doubling capacity.
    c.value(64); c.set(bucket);
    c.loopStart(); c.value(bucket); c.value(blot_runtime_runtime_layout::ArenaHeader_bytes + header); c.value(count); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.loopTest();
    c.value(bucket); c.value(2); c.op(blot_backend_runtime_ir::OP_i32_mul); c.set(bucket);
    c.again();
    c.value(bucket); c.value(blot_runtime_runtime_layout::ArenaHeader_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(owner); c.load(d_scalar_elements); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.value(0xfffffff0); c.op(blot_backend_runtime_ir::OP_i32_mul); c.call(arena.allocate_typed); c.set(node);
    acyclic(c, arena, node, proof(owner));
    c.value(node); c.value(0); c.value(bucket); c.value(blot_runtime_runtime_layout::ArenaHeader_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.zero();
    c.value(node); c.value(node); c.value(n_owner_token); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(owner); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.value(node); c.value(n_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(count); c.call(c.code.module.arena.value.store_word);
    // Capacity carries the row-aligned bound as well as the physical bucket.
    // Writers need the descriptor limit only when this capacity is full.
    c.value(bucket); c.value(blot_runtime_runtime_layout::ArenaHeader_bytes + header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.set(bucket);
    c.value(bucket); c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when();
    c.value(leaf_limit); c.set(bucket);
    c.end();
    c.value(node); c.value(node); c.value(n_capacity); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(bucket); c.call(c.code.module.arena.value.store_word);
    // Packed constructors already visit leaves in sequence order. Fill their
    // directory here instead of counting and traversing this tree afterward.
    let directory = c.temp();
    let index = c.temp();
    c.value(owner); c.load(d_directory); c.set(directory);
    c.value(directory); c.when();
    c.value(directory); c.load(blot_runtime_runtime_layout::Array_length); c.set(index);
    c.value(directory); c.value(directory); c.value(index); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(blot_runtime_runtime_layout::Array_bytes); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(node); c.call(c.code.module.arena.value.store_word);
    c.value(directory); c.value(directory); c.value(blot_runtime_runtime_layout::Array_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(index); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.call(c.code.module.arena.value.store_word);
    c.end();
    c.value(node);
}
// List trees have only downward private branch/cache edges. A scalar row width
// or an exact acyclic element proof therefore covers every descriptor and node
// of the tree; all descriptor constructors and clones preserve both. Reference
// Lists without the proof remain candidates even when their contents are null.

/// Nonzero when the descriptor's whole tree is acyclic.

/// The `new` row argument that reproduces the descriptor's element proof.

/// Freezing keeps the element proof bit.

fn emitBranch(c: Code&, r: Runtime, arena: Arena) {
    let left = Local { 0 , ..};
    let right = Local { 1 , ..};
    let owner = Local { 2 , ..};
    let node = c.temp();
    c.value(24); c.value(0x30); c.call(arena.allocate_typed); c.set(node);
    acyclic(c, arena, node, proof(owner));
    c.value(node); c.value(node); c.value(n_owner_token); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(owner); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.value(node); c.value(n_capacity); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.value(node); c.value(n_left); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(left); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.value(node); c.value(n_right); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(right); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.call(r.refresh);
}
fn emitRefresh(c: Code&) {
    let node = Local { 0 , ..};
    let left = c.temp();
    let right = c.temp();
    let height = c.temp();
    c.value(node); c.load(n_left); c.set(left);
    c.value(node); c.load(n_right); c.set(right);
    c.value(node); c.value(node); c.value(n_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(left); c.load(n_length); c.value(right); c.load(n_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.call(c.code.module.arena.value.store_word);
    c.value(left); c.load(n_height); c.set(height);
    c.value(right); c.load(n_height); c.value(height); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when();
    c.value(right); c.load(n_height); c.set(height);
    c.end();
    c.value(node); c.value(node); c.value(n_height); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(height); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.call(c.code.module.arena.value.store_word);
    c.value(node);
}
fn emitOwn(c: Code&, arena: Arena) {
    let node = Local { 0 , ..};
    let owner = Local { 1 , ..};
    let result = c.temp();
    let bytes = c.temp();
    c.value(node); c.load(n_owner_token); c.value(owner); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.value(node); c.ret();
    c.end();
    c.value(header); c.value(node); c.load(n_capacity); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(bytes);
    c.value(node); c.load(n_height); c.when();
    c.value(24); c.set(bytes);
    c.value(node); c.load(n_left); c.value(node); c.load(n_left); c.value(n_owner_token); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.load(n_right); c.value(node); c.load(n_right); c.value(n_owner_token); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.end();
    let mask = c.temp();
    c.value(0x30); c.set(mask);
    c.value(node); c.load(n_height); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(owner); c.load(d_scalar_elements); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.value(0xfffffff0); c.op(blot_backend_runtime_ir::OP_i32_mul); c.set(mask);
    c.end();
    c.value(bytes); c.value(mask); c.call(arena.allocate_typed); c.set(result);
    acyclic(c, arena, result, proof(owner));
    c.value(result); c.value(result); c.value(node); c.value(bytes); c.call(c.code.module.arena.value.copy_words);
    c.value(result); c.value(result); c.value(n_owner_token); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(owner); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.call(c.code.module.arena.value.store_word);
    c.value(result);
}
fn emitRotate(c: Code&, r: Runtime, leftward: bool) {
    let node = Local { 0 , ..};
    let owner = Local { 1 , ..};
    let pivot = c.temp();
    var side = n_left; if leftward { side = n_right; }
    var opposite = n_right; if leftward { opposite = n_left; }
    c.value(node); c.value(owner); c.call(r.own); c.set(node);
    c.value(node); c.load(side); c.value(owner); c.call(r.own); c.set(pivot);
    blot_runtime_root_runtime::retainBorrow(c, c.code.module.arena.value, pivot);
    c.value(node); c.value(node); c.value(side); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(pivot); c.load(opposite); c.call(c.code.module.arena.value.store_word);
    c.value(pivot); c.value(pivot); c.value(opposite); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(node); c.call(r.refresh); c.call(c.code.module.arena.value.store_word);
    c.value(pivot); c.call(r.refresh);
}
fn emitBalance(c: Code&, r: Runtime) {
    let node = Local { 0 , ..};
    let owner = Local { 1 , ..};
    let child = c.temp();
    c.value(node); c.call(r.refresh); c.set(node);
    for left_heavy in [true, false] {
        var side = n_right; if left_heavy { side = n_left; }
        var other = n_left; if left_heavy { other = n_right; }
        var inner_rotation = r.rotate_right; var outer_rotation = r.rotate_left; if left_heavy { inner_rotation = r.rotate_left; outer_rotation = r.rotate_right; }
        c.value(node); c.load(side); c.load(n_height); c.value(node); c.load(other); c.load(n_height); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when();
        c.value(node); c.load(side); c.set(child);
        c.value(child); c.load(side); c.load(n_height); c.value(child); c.load(other); c.load(n_height); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.when();
        c.value(node); c.value(node); c.value(side); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(child); c.value(owner); c.call(inner_rotation); c.call(c.code.module.arena.value.store_word);
        c.end();
        c.value(node); c.value(owner); c.call(outer_rotation); c.ret();
        c.end();
    }
    c.value(node);
}
fn emitInsert(c: Code&, r: Runtime) {
    let node = Local { 0 , ..};
    let value = Local { 1 , ..};
    let front = Local { 2 , ..};
    let owner = Local { 3 , ..};
    let count = c.temp();
    let added = c.temp();
    let child_height = c.temp();
    c.value(node); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(1); c.value(owner); c.call(r.chunk_new); c.set(added);
    c.value(added); c.value(added); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(value); c.call(c.code.module.arena.value.store_word);
    c.value(added); c.ret();
    c.end();
    c.value(node); c.load(n_height); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(node); c.load(n_length); c.set(count);
    c.value(count); c.value(node); c.load(n_capacity); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.value(count); c.value(owner); c.load(d_leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.value(1); c.value(owner); c.call(r.chunk_new); c.set(added);
    c.value(added); c.value(added); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(value); c.call(c.code.module.arena.value.store_word);
    c.value(front); c.when();
    c.value(added); c.value(node); c.value(owner); c.call(r.branch); c.ret();
    c.end();
    c.value(node); c.value(added); c.value(owner); c.call(r.branch); c.ret();
    c.end();
    c.value(count); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(owner); c.call(r.chunk_new); c.set(added);
    c.value(added); c.value(added); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(node); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(count); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.call(c.code.module.arena.value.copy_words);
    c.value(added); c.set(node);
    c.op(blot_backend_runtime_ir::OP_else_, 0);
    c.value(node); c.load(n_owner_token); c.value(owner); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.op(blot_backend_runtime_ir::OP_i32_ne); c.when();
    c.value(node); c.value(owner); c.call(r.own); c.set(node);
    c.end();
    c.end();
    c.value(front); c.when();
    c.value(node); c.value(node); c.value(header + 4); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(node); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(count); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.call(c.code.module.arena.value.copy_words);
    c.value(node); c.value(node); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(value); c.call(c.code.module.arena.value.store_word);
    c.op(blot_backend_runtime_ir::OP_else_, 0);
    c.value(node); c.value(node); c.value(count); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(value); c.call(c.code.module.arena.value.store_word);
    c.end();
    c.value(node); c.value(node); c.value(n_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(count); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.ret();
    c.end();
    c.value(node); c.load(n_owner_token); c.value(owner); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.op(blot_backend_runtime_ir::OP_i32_ne); c.when();
    c.value(node); c.value(owner); c.call(r.own); c.set(node);
    c.end();
    c.value(front); c.when();
    for side in [16 as u32, 20 as u32] {
        c.value(node); c.load(side); c.load(n_height); c.set(child_height);
        c.value(node); c.load(side); c.value(value); c.value(front); c.value(owner); c.call(r.insert); c.set(added);
        c.value(node); c.value(node); c.value(side); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(added); c.call(c.code.module.arena.value.store_word);
        if side == 16 { c.op(blot_backend_runtime_ir::OP_else_, 0); }
    }
    c.end();
    // Inserting into an existing leaf does not change subtree height. Update
    // the path counts without recomputing heights or checking rotations.
    c.value(added); c.load(n_height); c.value(child_height); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.value(node); c.value(node); c.value(n_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(node); c.load(n_length); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.ret();
    c.end();
    c.value(node); c.value(owner); c.call(r.balance);
}
fn emitReplace(c: Code&, r: Runtime) {
    let node = Local { 0 , ..};
    let index = Local { 1 , ..};
    let value = Local { 2 , ..};
    let owner = Local { 3 , ..};
    let left_count = c.temp();
    c.value(node); c.value(owner); c.call(r.own); c.set(node);
    c.value(node); c.load(n_height); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(node); c.value(node); c.value(index); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(value); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.ret();
    c.end();
    c.value(node); c.load(n_left); c.load(n_length); c.set(left_count);
    c.value(index); c.value(left_count); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.when();
    c.value(node); c.value(node); c.value(n_left); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(node); c.load(n_left); c.value(index); c.value(value); c.value(owner); c.call(r.replace); c.call(c.code.module.arena.value.store_word);
    c.op(blot_backend_runtime_ir::OP_else_, 0);
    c.value(node); c.value(node); c.value(n_right); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(node); c.load(n_right); c.value(index); c.value(left_count); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(value); c.value(owner); c.call(r.replace); c.call(c.code.module.arena.value.store_word);
    c.end();
    c.value(node);
}
fn emitNew(c: Code&, r: Runtime, arena: Arena) {
    let count = Local { 0 , ..};
    let kind = Local { 1 , ..};
    let leaf_limit = Local { 2 , ..};
    let row_words = c.temp();
    let result = c.temp();
    c.value(count); c.value(limit); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
    c.value(kind); c.value(acyclic_kind | width_bits); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
    c.value(kind); c.value(width_bits); c.op(blot_backend_runtime_ir::OP_i32_and); c.set(row_words);
    c.value(row_words); c.value(16); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
    c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.value(leaf_limit); c.value(capacity); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
    // Empty lists are immutable and carry no per-value state. Reuse one static
    // descriptor, including through conversions and empty slices. Any writer
    // must go through edit(), which detaches immutable descriptors.
    let empty = blot_runtime_arena_runtime::empty_list_address;
    let scalar_empty = blot_runtime_arena_runtime::empty_scalar_list_address;
    let acyclic_empty = blot_runtime_arena_runtime::empty_acyclic_list_address;
    c.value(count); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    for words in 2..17 {
        let aligned = leafLimit(words as u32);
        let address = blot_runtime_arena_runtime::empty_rows_address + ((words - 2) as u32) * descriptor_bytes;
        c.value(row_words); c.value(words as u32); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
        c.value(leaf_limit); c.value(aligned); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
        reference(c, address);
        c.op(blot_backend_runtime_ir::OP_return_, 0);
        c.end();
        c.end();
    }
    c.value(leaf_limit); c.value(capacity); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.value(row_words); c.when();
    reference(c, scalar_empty);
    c.op(blot_backend_runtime_ir::OP_return_, 0);
    c.end();
    c.value(kind); c.value(acyclic_kind); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    reference(c, acyclic_empty);
    c.op(blot_backend_runtime_ir::OP_return_, 0);
    c.end();
    reference(c, empty);
    c.op(blot_backend_runtime_ir::OP_return_, 0);
    c.end();
    c.end();
    c.value(descriptor_bytes); c.value(134); c.call(arena.allocate_typed); c.set(result);
    c.value(result); c.value(0); c.value(descriptor_bytes); c.zero();
    c.value(result); c.value(result); c.value(d_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(count); c.call(c.code.module.arena.value.store_word);
    // Word four is checked scalar row width: zero denotes references. Leaf
    // flags normalize it to two; no descriptor field or allocation class grows.
    c.value(result); c.value(result); c.value(d_scalar_elements); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(row_words); c.call(c.code.module.arena.value.store_word);
    c.value(result); c.value(result); c.value(d_immutable); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(kind); c.value(acyclic_kind); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(7); c.op(blot_backend_runtime_ir::OP_i32_shr_u); c.call(c.code.module.arena.value.store_word);
    c.value(row_words); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when();
    let leaves = c.temp();
    let directory = c.temp();
    c.value(count); c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.set(leaves);
    c.value(leaves); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when();
    c.value(blot_runtime_runtime_layout::Array_bytes); c.value(leaves); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(arena.allocate_typed); c.set(directory);
    c.value(directory); c.value(directory); c.value(blot_runtime_runtime_layout::Array_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.value(result); c.value(result); c.value(d_directory); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(directory); c.call(c.code.module.arena.value.store_word);
    c.end();
    c.end();
    c.value(result); c.value(result); c.value(d_leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(leaf_limit); c.call(c.code.module.arena.value.store_word);
    acyclic(c, arena, result, proof(result));
    c.value(result); c.value(result); c.value(d_root); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(count); c.value(result); c.call(r.chunk_new); c.call(c.code.module.arena.value.store_word);
    c.value(result);
}
// The directory owns scalar addresses, not leaf edges. Its descriptor keeps
// the immutable tree alive; traversal holders also root uncached static cases.
fn emitLeafCount(c: Code&, r: Runtime) {
    let node = Local { 0 , ..};
    c.value(node); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(0); c.ret();
    c.end();
    c.value(node); c.load(n_height); c.when();
    c.value(node); c.load(n_left); c.call(r.leaf_count); c.value(node); c.load(n_right); c.call(r.leaf_count); c.op(blot_backend_runtime_ir::OP_i32_add); c.ret();
    c.end();
    c.value(1);
}
fn emitWriteLeaves(c: Code&, r: Runtime) {
    let node = Local { 0 , ..};
    let array = Local { 1 , ..};
    let index = Local { 2 , ..};
    c.value(node); c.load(n_height); c.when();
    c.value(node); c.load(n_left); c.value(array); c.value(index); c.call(r.write_leaves); c.set(index);
    c.value(node); c.load(n_right); c.value(array); c.value(index); c.call(r.write_leaves); c.ret();
    c.end();
    c.value(array); c.value(array); c.value(index); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(blot_runtime_runtime_layout::Array_bytes); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(node); c.call(c.code.module.arena.value.store_word);
    c.value(index); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add);
}
fn emitDirectory(c: Code&, r: Runtime, arena: Arena) {
    let sequence = Local { 0 , ..};
    let array = c.temp();
    let count = c.temp();
    c.value(sequence); c.load(d_directory); c.set(array);
    c.value(array); c.when();
    c.value(array); c.ret();
    c.end();
    c.value(sequence); c.load(d_root); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(0); c.ret();
    c.end();
    // For one leaf, the descriptor's root word is already a complete
    // one-entry view at the Array payload offset. Return its exact owning
    // allocation; no separate directory or self-owning cache is published.
    assert(d_root == blot_runtime_runtime_layout::Array_bytes);
    c.value(sequence); c.load(d_root); c.load(n_height); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(sequence); c.ret();
    c.end();
    c.value(sequence); c.load(d_root); c.call(r.leaf_count); c.set(count);
    c.value(blot_runtime_runtime_layout::Array_bytes); c.value(count); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(arena.allocate_typed); c.set(array);
    c.value(array); c.value(array); c.value(blot_runtime_runtime_layout::Array_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(count); c.call(c.code.module.arena.value.store_word);
    c.value(sequence); c.load(d_root); c.value(array); c.value(0); c.call(r.write_leaves);
    c.op(blot_backend_runtime_ir::OP_drop, 0);
    // Counted descriptors own this edge. In tracing mode, an older descriptor
    // must not pin unrelated traffic by promoting the whole arena frontier.
    // Its traversal holder owns this uncached directory until the read ends.
    c.value(sequence); c.globalGet(arena.base); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.globalGet(arena.root_enabled); c.op(blot_backend_runtime_ir::OP_i32_or); c.when();
    c.value(sequence); c.value(sequence); c.value(d_directory); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(array); c.call(c.code.module.arena.value.store_word);
    c.end();
    c.value(array);
}
fn emitUncheckedAddress(module: Module&) -> u32, Error {
    let id, error = function(module, 2, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return 0, error; }
    var c = blot_emitter::init(module, id); emitAddress(c, false); return id, c.failure;
}
fn emitUncheckedSet(module: Module&, runtime: Runtime) -> u32, Error {
    assert(runtime.address_unchecked.present);
    let id, error = function(module, 4, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return 0, error; }
    var c = blot_emitter::init(module, id); emitSet(c, runtime, false); return id, c.failure;
}
fn emitAddress(c: Code&, checked: bool) {
    let sequence = Local { 0 , ..};
    let index = Local { 1 , ..};
    let node = c.temp();
    let base = c.temp();
    let left = c.temp();
    let split = c.temp();
    if checked { c.value(index); c.value(sequence); c.load(d_length); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.trap(); }
    c.value(sequence); c.load(d_cached_leaf); c.set(node);
    c.value(sequence); c.load(d_cached_base); c.set(base);
    c.value(node); c.when();
    c.value(index); c.value(base); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.value(index); c.value(base); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(node); c.load(n_length); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.value(node); c.value(index); c.value(base); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.ret();
    c.end();
    c.end();
    let directory = c.temp();
    let leaf_limit = c.temp();
    c.value(sequence); c.load(d_directory); c.set(directory);
    c.value(directory); c.when();
    c.value(sequence); c.load(d_leaf_limit); c.set(leaf_limit);
    c.value(leaf_limit); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.value(leaf_limit); c.value(capacity); c.op(blot_backend_runtime_ir::OP_i32_le_u); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.value(directory); c.load(blot_runtime_runtime_layout::Array_length); c.set(left);
    c.value(left); c.when();
    c.value(left); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(split);
    // Guard the product before evaluating it, including highly shared trees.
    c.value(split); c.value(sequence); c.load(d_length); c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.op(blot_backend_runtime_ir::OP_i32_le_u); c.when();
    c.value(directory); c.value(split); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(blot_runtime_runtime_layout::Array_bytes); c.op(blot_backend_runtime_ir::OP_i32_add); c.load(0); c.set(node);
    c.value(node); c.load(n_length); c.set(base);
    c.value(base); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.value(base); c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_le_u); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    // Each ordered leaf is bounded by leaf_limit. Equality proves every
    // preceding occurrence is full, even when leaf addresses are repeated.
    c.value(sequence); c.load(d_length); c.value(split); c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(base); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.value(index); c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.set(split);
    c.value(directory); c.value(split); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(blot_runtime_runtime_layout::Array_bytes); c.op(blot_backend_runtime_ir::OP_i32_add); c.load(0); c.set(node);
    c.value(split); c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_mul); c.set(base);
    c.value(sequence); c.value(sequence); c.value(d_cached_leaf); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(node); c.call(c.code.module.arena.value.store_word);
    c.value(sequence); c.value(sequence); c.value(d_cached_base); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(base); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.value(index); c.value(base); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.ret();
    for ignored in 0..6 { c.end(); }
    c.value(sequence); c.load(d_root); c.set(node);
    c.value(0); c.set(base);
    c.loopStart(); c.value(node); c.load(n_height); c.loopTest();
    c.value(node); c.load(n_left); c.set(left);
    c.value(base); c.value(left); c.load(n_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(split);
    c.value(index); c.value(split); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.when();
    c.value(left); c.set(node);
    c.op(blot_backend_runtime_ir::OP_else_, 0);
    c.value(node); c.load(n_right); c.set(node);
    c.value(split); c.set(base);
    c.end();
    c.again();
    c.value(sequence); c.value(sequence); c.value(d_cached_leaf); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(node); c.call(c.code.module.arena.value.store_word);
    c.value(sequence); c.value(sequence); c.value(d_cached_base); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(base); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.value(index); c.value(base); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add);
}
fn emitCopy(c: Code&, r: Runtime) {
    let sequence = Local { 0 , ..};
    let count = Local { 1 , ..};
    let result = c.temp();
    let index = c.temp();
    let from = c.temp();
    let to = c.temp();
    let span = c.temp();
    let available = c.temp();
    c.value(sequence); c.load(d_length); c.value(count); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
    c.value(count); c.value(kindOf(sequence)); c.value(sequence); c.load(d_leaf_limit); c.call(r.new); c.set(result);
    c.loopStart(); c.value(index); c.value(sequence); c.load(d_length); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.loopTest();
    c.value(sequence); c.value(index); c.call(r.address); c.set(from);
    c.value(result); c.value(index); c.call(r.address); c.set(to);
    c.value(sequence); c.load(d_cached_leaf); c.load(n_length); c.value(index); c.value(sequence); c.load(d_cached_base); c.op(blot_backend_runtime_ir::OP_i32_sub); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(span);
    c.value(result); c.load(d_cached_leaf); c.load(n_length); c.value(index); c.value(result); c.load(d_cached_base); c.op(blot_backend_runtime_ir::OP_i32_sub); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(available);
    c.value(available); c.value(span); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.when();
    c.value(available); c.set(span);
    c.end();
    c.value(result); c.load(d_cached_leaf); c.value(to); c.value(from); c.value(span); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.call(c.code.module.arena.value.copy_words);
    c.value(index); c.value(span); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(index);
    c.again();
    c.value(result);
}
/// A read snapshot can share its descriptor. Freezing the current descriptor
/// forces every later writer through edit's existing copy-on-write branch;
/// sharing the tree root also prevents a writer from consuming its old nodes.
/// Cursor progress and leaf caches remain in each cursor's independent fields.
fn emitSnapshot(module: Module&) -> u32, Error {
    let id, error = function(module, 1, blot_backend_runtime_ir::VT_i32); if error != blot_error::Error.none { return 0, error; }
    var c = blot_emitter::init(module, id);
    let sequence = Local { 0 , ..};
    freeze(c, sequence);
    c.value(sequence); c.load(d_root); c.when();
    c.value(sequence); c.load(d_root); c.value(sequence); c.load(d_root); c.value(n_owner_token); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.end();
    c.value(sequence);
    return id, c.failure;
}
fn emitEdit(c: Code&, arena: Arena) {
    let sequence = Local { 0 , ..};
    let owned = Local { 1 , ..};
    let result = c.temp();
    c.value(owned); c.value(sequence); c.load(d_immutable); c.value(frozen); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.value(sequence); c.ret();
    c.end();
    c.value(descriptor_bytes); c.value(134); c.call(arena.allocate_typed); c.set(result);
    c.value(result); c.value(result); c.value(sequence); c.value(descriptor_bytes); c.call(c.code.module.arena.value.copy_words);
    // This copy retains the identical tree and its typed directory edge.
    // Writers invalidate the directory before changing that tree.
    acyclic(c, arena, result, proof(sequence));
    c.value(result); c.value(result); c.value(d_cached_leaf); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.value(result); c.value(result); c.value(d_immutable); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(sequence); c.load(d_immutable); c.value(acyclic_elements); c.op(blot_backend_runtime_ir::OP_i32_and); c.call(c.code.module.arena.value.store_word);
    c.value(sequence); c.load(d_root); c.when();
    // This write is metadata only: both versions retain identical contents.
    c.value(sequence); c.load(d_root); c.value(sequence); c.load(d_root); c.value(n_owner_token); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.end();
    c.value(result);
}
fn emitPush(c: Code&, r: Runtime) {
    let sequence = Local { 0 , ..};
    let value = Local { 1 , ..};
    let front = Local { 2 , ..};
    let owned = Local { 3 , ..};
    c.value(sequence); c.load(d_length); c.value(limit); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.trap();
    c.value(sequence); c.value(owned); c.call(r.edit); c.set(sequence);
    // Borrowed leaf bases are valid only while this exact tree is retained.
    c.value(sequence); c.value(sequence); c.value(d_directory); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.value(sequence); c.value(sequence); c.value(d_root); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(sequence); c.load(d_root); c.value(value); c.value(front); c.value(sequence); c.call(r.insert); c.call(c.code.module.arena.value.store_word);
    c.value(sequence); c.value(sequence); c.value(d_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(sequence); c.load(d_length); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.call(c.code.module.arena.value.store_word);
    c.value(sequence); c.value(sequence); c.value(d_cached_leaf); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.value(sequence);
}
fn emitSet(c: Code&, r: Runtime, checked: bool) {
    let sequence = Local { 0 , ..};
    let index = Local { 1 , ..};
    let value = Local { 2 , ..};
    let owned = Local { 3 , ..};
    if checked { c.value(index); c.value(sequence); c.load(d_length); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.trap(); }
    // Compare stored bits, not language equality: this is also sound for NaNs,
    // signed zero and reference-valued elements. A borrowed no-op may create
    // a second owner of this very descriptor; freeze it before returning it.
    var address = r.address;
    if !checked { assert(r.address_unchecked.present); address = r.address_unchecked.value; }
    c.value(sequence); c.value(index); c.call(address); c.load(0); c.value(value); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.value(owned); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    freeze(c, sequence);
    c.end();
    c.value(sequence); c.ret();
    c.end();
    c.value(sequence); c.value(owned); c.call(r.edit); c.set(sequence);
    // Borrowed leaf bases are valid only while this exact tree is retained.
    c.value(sequence); c.value(sequence); c.value(d_directory); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.value(sequence); c.value(sequence); c.value(d_root); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(sequence); c.load(d_root); c.value(index); c.value(value); c.value(sequence); c.call(r.replace); c.call(c.code.module.arena.value.store_word);
    c.value(sequence); c.value(sequence); c.value(d_cached_leaf); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.value(sequence);
}
fn emitConversion(c: Code&, r: Runtime, arena: Arena, to_list: bool) {
    let source = Local { 0 , ..};
    let result = c.temp();
    let count = c.temp();
    let index = c.temp();
    let address = c.temp();
    let span = c.temp();
    var length_offset = d_length; if to_list { length_offset = blot_runtime_runtime_layout::Array_length; }
    c.value(source); c.load(length_offset); c.set(count);
    if to_list {
        // Zero denotes reference words; positive values are the checked number
        // of scalar words per logical Array element. The tree stores words.
        // `new` checks and keeps the acyclic element bit of the kind.
        let kind = Local { 1 , ..};
        let width = c.temp();
        c.value(kind); c.value(width_bits); c.op(blot_backend_runtime_ir::OP_i32_and); c.set(width);
        c.value(width); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when();
        c.value(count); c.value(limit); c.value(width); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
        c.value(count); c.value(width); c.op(blot_backend_runtime_ir::OP_i32_mul); c.set(count);
        c.end();
        let leaf_limit = c.temp();
        c.value(capacity); c.set(leaf_limit);
        c.value(width); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when();
        c.value(width); c.value(16); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
        c.value(capacity); c.value(width); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.value(width); c.op(blot_backend_runtime_ir::OP_i32_mul); c.set(leaf_limit);
        c.end();
        c.value(count); c.value(kind); c.value(leaf_limit); c.call(r.new); c.set(result);
    } else {
        c.value(4); c.value(count); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(source); c.load(d_scalar_elements); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.value(0xfffffffe); c.op(blot_backend_runtime_ir::OP_i32_mul); c.call(arena.allocate_typed); c.set(result);
        // The Array holds the same elements, so the tree's proof covers it.
        acyclic(c, arena, result, proof(source));
        c.value(result); c.value(result); c.value(blot_runtime_runtime_layout::Array_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(count); c.call(c.code.module.arena.value.store_word);
    }
    c.loopStart(); c.value(index); c.value(count); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.loopTest();
    var list = source; if to_list { list = result; }
    c.value(list); c.value(index); c.call(r.address); c.set(address);
    c.value(list); c.load(d_cached_leaf); c.load(n_length); c.value(index); c.value(list); c.load(d_cached_base); c.op(blot_backend_runtime_ir::OP_i32_sub); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(span);
    if to_list {
        c.value(result); c.load(d_cached_leaf); c.value(address); c.value(source); c.value(index); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(span); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.call(c.code.module.arena.value.copy_words);
    } else {
        c.value(result); c.value(result); c.value(index); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(address); c.value(span); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.call(c.code.module.arena.value.copy_words);
    }
    c.value(index); c.value(span); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(index);
    c.again();
    c.value(result);
}
// Join retains covered subtrees and only rebuilds the taller boundary spine.
// Small adjacent leaves coalesce with bounded copying to avoid tiny packets.
fn emitJoin(c: Code&, r: Runtime) {
    let left = Local { 0 , ..};
    let right = Local { 1 , ..};
    let owner = Local { 2 , ..};
    let node = c.temp();
    let count = c.temp();
    c.value(left); c.when();
    c.value(left); c.value(left); c.value(n_owner_token); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.end();
    c.value(right); c.when();
    c.value(right); c.value(right); c.value(n_owner_token); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.end();
    c.value(left); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(right); c.ret();
    c.end();
    c.value(right); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(left); c.ret();
    c.end();
    c.value(left); c.load(n_length); c.value(right); c.load(n_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(count);
    c.value(count); c.value(64); c.op(blot_backend_runtime_ir::OP_i32_le_u); c.value(count); c.value(owner); c.load(d_leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_le_u); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    // Both operands need to be leaves; a fragmented small tree is handled by
    // the same structural path instead of unbounded recursive flattening.
    c.value(left); c.load(n_height); c.value(right); c.load(n_height); c.op(blot_backend_runtime_ir::OP_i32_or); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(count); c.value(owner); c.call(r.chunk_new); c.set(node);
    c.value(node); c.value(node); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(left); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(left); c.load(n_length); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.call(c.code.module.arena.value.copy_words);
    c.value(node); c.value(node); c.value(left); c.load(n_length); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(right); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(right); c.load(n_length); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.call(c.code.module.arena.value.copy_words);
    c.value(node); c.ret();
    c.end();
    c.end();
    c.value(left); c.load(n_height); c.value(right); c.load(n_height); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when();
    c.value(left); c.value(owner); c.call(r.own); c.set(node);
    c.value(node); c.value(node); c.value(n_right); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(node); c.load(n_right); c.value(right); c.value(owner); c.call(r.join); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.value(owner); c.call(r.balance); c.ret();
    c.end();
    c.value(right); c.load(n_height); c.value(left); c.load(n_height); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when();
    c.value(right); c.value(owner); c.call(r.own); c.set(node);
    c.value(node); c.value(node); c.value(n_left); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(left); c.value(node); c.load(n_left); c.value(owner); c.call(r.join); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.value(owner); c.call(r.balance); c.ret();
    c.end();
    c.value(left); c.value(right); c.value(owner); c.call(r.branch);
}
fn emitCut(c: Code&, r: Runtime) {
    let node = Local { 0 , ..};
    let start = Local { 1 , ..};
    let count = Local { 2 , ..};
    let owner = Local { 3 , ..};
    let left = c.temp();
    let split = c.temp();
    let result = c.temp();
    c.value(count); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(0); c.ret();
    c.end();
    c.value(count); c.value(node); c.load(n_length); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.value(node); c.value(node); c.value(n_owner_token); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.call(c.code.module.arena.value.store_word);
    c.value(node); c.ret();
    c.end();
    c.value(node); c.load(n_height); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(count); c.value(owner); c.call(r.chunk_new); c.set(result);
    c.value(result); c.value(result); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(node); c.value(start); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(count); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.call(c.code.module.arena.value.copy_words);
    c.value(result); c.ret();
    c.end();
    c.value(node); c.load(n_left); c.set(left);
    c.value(left); c.load(n_length); c.set(split);
    c.value(start); c.value(split); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.when();
    c.value(node); c.load(n_right); c.value(start); c.value(split); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(count); c.value(owner); c.call(r.cut); c.ret();
    c.end();
    c.value(split); c.value(start); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(split);
    c.value(count); c.value(split); c.op(blot_backend_runtime_ir::OP_i32_le_u); c.when();
    c.value(left); c.value(start); c.value(count); c.value(owner); c.call(r.cut); c.ret();
    c.end();
    c.value(left); c.value(start); c.value(split); c.value(owner); c.call(r.cut); c.value(node); c.load(n_right); c.value(0); c.value(count); c.value(split); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(owner); c.call(r.cut); c.value(owner); c.call(r.join);
}
fn emitConcat(c: Code&, r: Runtime, arena: Arena) {
    let left = Local { 0 , ..};
    let right = Local { 1 , ..};
    let count = c.temp();
    let result = c.temp();
    let leaf_limit = c.temp();
    c.value(left); c.load(d_length); c.value(right); c.load(d_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(count);
    c.value(count); c.value(limit); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
    c.value(count); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(0); c.value(kindOf(left)); c.value(kindOf(right)); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(left); c.load(d_leaf_limit); c.call(r.new); c.ret();
    c.end();
    for pair in [[left, right], [right, left]] {
        c.value(pair[0]); c.load(d_length); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
        freeze(c, pair[1]);
        c.value(pair[1]); c.ret();
        c.end();
    }
    c.value(descriptor_bytes); c.value(134); c.call(arena.allocate_typed); c.set(result);
    c.value(result); c.value(0); c.value(descriptor_bytes); c.zero();
    c.value(result); c.value(result); c.value(d_scalar_elements); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(left); c.load(d_scalar_elements); c.value(right); c.load(d_scalar_elements); c.op(blot_backend_runtime_ir::OP_i32_and); c.call(c.code.module.arena.value.store_word);
    // Keep the bound valid for every reused leaf, including mixed runtime
    // descriptors. Checked equal-row source concatenations keep their limit.
    c.value(left); c.load(d_leaf_limit); c.set(leaf_limit);
    c.value(right); c.load(d_leaf_limit); c.value(leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when();
    c.value(right); c.load(d_leaf_limit); c.set(leaf_limit);
    c.end();
    c.value(result); c.value(result); c.value(d_leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(leaf_limit); c.call(c.code.module.arena.value.store_word);
    // Equal element types carry equal proofs; mixed descriptors keep neither.
    c.value(result); c.value(result); c.value(d_immutable); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(left); c.load(d_immutable); c.value(right); c.load(d_immutable); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(acyclic_elements); c.op(blot_backend_runtime_ir::OP_i32_and); c.call(c.code.module.arena.value.store_word);
    acyclic(c, arena, result, proof(result));
    c.value(result); c.value(result); c.value(d_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(count); c.call(c.code.module.arena.value.store_word);
    c.value(result); c.value(result); c.value(d_root); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(left); c.load(d_root); c.value(right); c.load(d_root); c.value(result); c.call(r.join); c.call(c.code.module.arena.value.store_word);
    c.value(result);
}
fn emitSlice(c: Code&, r: Runtime, arena: Arena) {
    let source = Local { 0 , ..};
    let start = Local { 1 , ..};
    let count = Local { 2 , ..};
    let result = c.temp();
    c.value(start); c.value(source); c.load(d_length); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
    c.value(count); c.value(source); c.load(d_length); c.value(start); c.op(blot_backend_runtime_ir::OP_i32_sub); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
    c.value(count); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(0); c.value(kindOf(source)); c.value(source); c.load(d_leaf_limit); c.call(r.new); c.ret();
    c.end();
    c.value(count); c.value(source); c.load(d_length); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    freeze(c, source);
    c.value(source); c.ret();
    c.end();
    c.value(descriptor_bytes); c.value(134); c.call(arena.allocate_typed); c.set(result);
    c.value(result); c.value(0); c.value(descriptor_bytes); c.zero();
    c.value(result); c.value(result); c.value(d_scalar_elements); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(source); c.load(d_scalar_elements); c.call(c.code.module.arena.value.store_word);
    c.value(result); c.value(result); c.value(d_leaf_limit); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(source); c.load(d_leaf_limit); c.call(c.code.module.arena.value.store_word);
    c.value(result); c.value(result); c.value(d_immutable); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(source); c.load(d_immutable); c.value(acyclic_elements); c.op(blot_backend_runtime_ir::OP_i32_and); c.call(c.code.module.arena.value.store_word);
    acyclic(c, arena, result, proof(result));
    c.value(result); c.value(result); c.value(d_length); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(count); c.call(c.code.module.arena.value.store_word);
    c.value(result); c.value(result); c.value(d_root); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(source); c.load(d_root); c.value(start); c.value(count); c.value(result); c.call(r.cut); c.call(c.code.module.arena.value.store_word);
    c.value(result);
}
fn staticChunk(module: Module&, words: const u32[:]) -> u32, Error {
    assert(words.len > 0 && words.len <= capacity);
    let arena, error = module.ensureArena(); if error != blot_error::Error.none { return 0, error; }
    var buffer: u32[248] = [0; 248];
    buffer[n_length / 4] = words.len as u32; buffer[n_capacity / 4] = words.len as u32;
    for word, index in words { buffer[header / 4 + index] = word; }
    if words.len > 0x7fffffffffffffff - header / 4 { return 0, blot_error::Error.module_too_large; }
    let used = header / 4 + words.len; return module.dataWords(buffer[..used]);
}
struct StaticNode { address: u32, height: u32, count: u32 }
recursive fn staticTree(module: Module&, leaves: const u32[:]) -> StaticNode, Error {
    if leaves.len == 0 { return StaticNode { 0, 0, 0 , ..}, blot_error::Error.none; }
    if leaves.len == 1 { return StaticNode { leaves[0], 0, module.readDataWord(leaves[0] + n_length) , ..}, blot_error::Error.none; }
    let left, left_error = staticTree(module, leaves[..leaves.len / 2]); if left_error != blot_error::Error.none { return default<StaticNode>(), left_error; }
    let right, right_error = staticTree(module, leaves[leaves.len / 2..]); if right_error != blot_error::Error.none { return default<StaticNode>(), right_error; }
    let height = max(left.height, right.height) + 1;
    let address, error = module.dataObject([0 as u32, height, left.count + right.count, 0 as u32, left.address, right.address]);
    if error != blot_error::Error.none { return default<StaticNode>(), error; }
    let left_reference = module.dataReference(address + n_left, blot_reuse_artifact_emitter::Operand { blot_reuse_artifact_emitter::Role.static_address, left.address , ..});
    if left_reference != blot_error::Error.none { return default<StaticNode>(), left_reference; }
    let right_reference = module.dataReference(address + n_right, blot_reuse_artifact_emitter::Operand { blot_reuse_artifact_emitter::Role.static_address, right.address , ..});
    if right_reference != blot_error::Error.none { return default<StaticNode>(), right_reference; }
    return StaticNode { address, height, left.count + right.count , ..}, blot_error::Error.none;
}
fn staticDescriptor(module: Module&, length: u32, leaves: const u32[:]) -> u32, Error { return staticDescriptorKind(module, length, leaves, 0, capacity); }
fn staticScalarDescriptor(module: Module&, length: u32, leaves: const u32[:], row_words: u32) -> u32, Error { return staticDescriptorKind(module, length, leaves, row_words, leafLimit(row_words)); }
fn staticDescriptorKind(module: Module&, length: u32, leaves: const u32[:], row_words: u32, leaf_limit: u32) -> u32, Error {
    let root, error = staticTree(module, leaves); if error != blot_error::Error.none { return 0, error; } assert(root.count == length);
    var directory: u32 = 0;
    if row_words != 0 && leaves.len > 1 {
        var words: u32[>..<] = []; words.push(leaves.len as u32); words.append(leaves);
        let data, failure = module.dataWords(words); if failure != blot_error::Error.none { return 0, failure; } directory = data;
        for leaf, index in leaves {
            let reference = module.dataReference(directory + ((index + 1) * 4) as u32, blot_reuse_artifact_emitter::Operand { blot_reuse_artifact_emitter::Role.static_address, leaf , ..});
            if reference != blot_error::Error.none { return 0, reference; }
        }
    }
    let address, failure = module.dataObject([length, root.address, 0 as u32, 0 as u32, row_words, 1 as u32, leaf_limit, directory]);
    if failure != blot_error::Error.none { return 0, failure; }
    let cached_leaf = module.staticField(address + d_cached_leaf, blot_backend_runtime_ir::ROLE_reference); if cached_leaf != blot_error::Error.none { return 0, cached_leaf; }
    let cached_base = module.staticField(address + d_cached_base, blot_backend_runtime_ir::ROLE_scalar); if cached_base != blot_error::Error.none { return 0, cached_base; }
    let immutable = module.staticField(address + d_immutable, blot_backend_runtime_ir::ROLE_scalar); if immutable != blot_error::Error.none { return 0, immutable; }
    let directory_field = module.staticField(address + d_directory, blot_backend_runtime_ir::ROLE_reference); if directory_field != blot_error::Error.none { return 0, directory_field; }
    if directory != 0 { let reference = module.dataReference(address + d_directory, blot_reuse_artifact_emitter::Operand { blot_reuse_artifact_emitter::Role.static_address, directory , ..}); if reference != blot_error::Error.none { return 0, reference; } }
    if root.address != 0 { let reference = module.dataReference(address + d_root, blot_reuse_artifact_emitter::Operand { blot_reuse_artifact_emitter::Role.static_address, root.address , ..}); if reference != blot_error::Error.none { return 0, reference; } }
    return address, blot_error::Error.none;
}
