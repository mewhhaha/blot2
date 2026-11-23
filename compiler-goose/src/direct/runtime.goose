// Storage runtime of the direct backend: a 2-level paged owner table of
// (base, length, capacity, generation) entries addressed by (slot, generation)
// handles, an active-only exact-capacity free-list bump stack for fixed arrays
// and closure environments, a power-of-two free-list heap for growable storage,
// a dedicated transport free-list bank, and on-demand persistent/undo regions.
// Modules commit 1 Wasm page (64 KiB) initially and grow on demand via
// `memory.grow` up to the planned budget ceiling, reusing chunks and free lists
// across invocations while keeping logical stack/heap budgets history-independent.
namespace blot_direct_runtime;
import std;
import direct.writer;

let entry_bytes: u32 = 16;
let entry_base: u32 = 0;
let entry_length: u32 = 4;
let entry_capacity: u32 = 8;
let entry_generation: u32 = 12;
// Capacity flags:
// - frozen_flag (sign bit): growth authority removed
// - heap_flag: backing owned by rt.heap (free via heap_free)
// - static_pool_flag: on persistent slots (>= persistent_split) marks a deeply-immutable
//   static const pool; on temporary slots (< persistent_split) with heap_flag == 0 marks
//   a transport pin (free via free_transport)
// - live_flag: entry is currently live and valid
let frozen_flag: u32 = 0x80000000;
let heap_flag: u32 = 0x40000000;
let static_pool_flag: u32 = 0x20000000;
let live_flag: u32 = 0x10000000;
let flag_mask: u32 = 0xf0000000;
let capacity_mask: u32 = 0x0fffffff;
// Speculative fork undo journal budget (2 MiB, allocated lazily only when a module executes `fork`).
let undo_bytes: u32 = 2097152;
// Fixed page-0 layout:
//   [0..512)    zero guard
//   [512..640)  heap free lists (32 power-of-two classes)
//   [640..644)  arena_oom_flag (1u32 on physical retained-chunk/free-list/alloc_raw OOM; zeroed on reset)
//   [644..772)  transport free lists (32 power-of-two classes)
//   [1024..2048) 256-entry owner block directory
//   [2048..65536) initial arena
let arena_oom_offset: u32 = 640;
let transport_free_lists_offset: u32 = 644;
let owner_block_bytes: u32 = 4096;
let arena_start: u32 = 2048;
let initial_page_bytes: u32 = 65536;
// Active-only chunked stack: 32-byte header (+0=prev, +4=next/free_next, +8=limit, +12=cap, +16=used_end).
let stack_header_bytes: u32 = 32;
let stack_chunk_std: u32 = 32768;

// Defaults: 65536 owners, 4 MiB persistent, 128 MiB stack, 128 MiB heap, 2 MiB transport.
struct Budgets {
    owners: u32 = 65536,
    persistent: u32 = 4194304,
    stack: u32 = 134217728,
    heap: u32 = 134217728,
    transport: u32 = 2097152
}
struct Layout {
    free_lists: u32 = 512,
    arena_oom_offset: u32 = 640,
    transport_free_lists: u32 = 644,
    owner_table: u32 = 1024,
    owner_capacity: u32 = 0,
    persistent_split: u32 = 0,
    persistent_base: u32 = 0,
    persistent_end: u32 = 0,
    stack_base: u32 = 0,
    stack_end: u32 = 0,
    heap_base: u32 = 0,
    heap_end: u32 = 0,
    transport_base: u32 = 0,
    transport_end: u32 = 0,
    undo_base: u32 = 0,
    undo_end: u32 = 0,
    total: u32 = 0
}
fn init(budgets: Budgets) -> Layout { return initWithFork(budgets, false); }
fn initWithFork(budgets: Budgets, has_fork: bool) -> Layout {
    let owner_bytes = budgets.owners * entry_bytes;
    var split = ((budgets.owners * 3) / 4) & 0xffffff00;
    if split == 0 { split = budgets.owners / 2; }
    if split >= budgets.owners { split = budgets.owners - 1; }
    let persistent_base = arena_start + owner_bytes;
    let stack_base = persistent_base + budgets.persistent;
    let heap_base = stack_base + budgets.stack;
    let transport_base = heap_base + budgets.heap;
    let transport_end = transport_base + budgets.transport;
    var undo_end = transport_end;
    if has_fork { undo_end = transport_end + undo_bytes; }
    // Allow small overhead for chunk headers and alignment rounding.
    var total = undo_end + 262144;
    if total < initial_page_bytes { total = initial_page_bytes; }
    return Layout {
        owner_capacity: budgets.owners,
        persistent_split: split,
        persistent_base: persistent_base,
        persistent_end: stack_base,
        stack_base: stack_base,
        stack_end: heap_base,
        heap_base: heap_base,
        heap_end: transport_base,
        transport_base: transport_base,
        transport_end: transport_end,
        undo_base: transport_end,
        undo_end: undo_end,
        total: total,
        ..
    };
}

struct Runtime {
    layout: Layout,
    has_fork: bool = false,
    has_persistent_state: bool = false,
    owner_top: u32 = 0,
    persistent_bottom: u32 = 0,
    arena_top: u32 = 0,
    page_top: u32 = 0,
    stack_head: u32 = 0,
    stack_chunk: u32 = 0,
    stack_pointer: u32 = 0,
    stack_limit: u32 = 0,
    stack_total: u32 = 0,
    stack_live_bytes: u32 = 0,
    stack_free_32k: u32 = 0,
    stack_free_large: u32 = 0,
    heap_top: u32 = 0,
    heap_live_bytes: u32 = 0,
    persistent_top: u32 = 0,
    transport_base: u32 = 0,
    transport_cap: u32 = 0,
    transport_top: u32 = 0,
    // The installed providers: the newest frame of
    // {operation id, closure slot, closure environment, previous frame}.
    effect_context: u32 = 0,
    // Inter-procedural escape tracker: minimum normalized owner slot written to
    // inside the active scope (0 for persistent/untracked stores, 0xffffffff = none).
    escape_min_slot: u32 = 0,
    // Persistent slot free-list (singly linked through entry_base).
    persistent_free_head: u32 = 0,
    persistent_free_count: u32 = 0,
    // Deeply-immutable static const box registry: (addr, logical_bytes, ty_id) triples.
    static_blocks_ptr: u32 = 0,
    static_blocks_len: u32 = 0,
    static_blocks_cap: u32 = 0,
    // Speculative `fork` state: owner slots below `fork_owner_mark` (or persistent
    // slots >= persistent_split) predate the active `fork` and journal writes onto `undo_sp`.
    fork_owner_mark: u32 = 0,
    fork_depth: u32 = 0,
    undo_base: u32 = 0,
    undo_end: u32 = 0,
    undo_sp: u32 = 0,
    alloc_raw: u32 = 0,
    open: u32 = 0,
    open_persistent: u32 = 0,
    open_heap: u32 = 0,
    detach_temp_slot: u32 = 0,
    release: u32 = 0,
    check: u32 = 0,
    stack: u32 = 0,
    stack_slow: u32 = 0,
    rewind_stack: u32 = 0,
    rewind_stack_slow: u32 = 0,
    heap_alloc: u32 = 0,
    heap_free: u32 = 0,
    alloc_transport: u32 = 0,
    open_transport_pin: u32 = 0,
    free_transport: u32 = 0,
    alloc_persistent: u32 = 0,
    address: u32 = 0,
    length: u32 = 0,
    push: u32 = 0,
    pop: u32 = 0,
    truncate: u32 = 0,
    freeze: u32 = 0,
    create: u32 = 0,
    copy: u32 = 0,
    persist: u32 = 0,
    allocate: u32 = 0,
    reset: u32 = 0,
    packet_length: u32 = 0,
    free_persistent: u32 = 0,
    ensure_persistent_slots: u32 = 0,
    is_stack_range: u32 = 0,
    record_static_block: u32 = 0,
    open_vec: u32 = 0,
    scratch_push: u32 = 0,
    open_hmap: u32 = 0,
    hmap_get: u32 = 0,
    hmap_put: u32 = 0,
    undo_reserve: u32 = 0,
    undo_record: u32 = 0,
    undo_rewind: u32 = 0
}

// A helper body under construction. Every local is an i32, so `locals` counts
// the parameters and then the temporaries.
struct H {
    parameters: u32 = 0,
    locals: u32 = 0,
    code: u8[>..<] = []
}
fn temp(h: H&) -> u32 {
    let id = h.locals;
    h.locals += 1;
    return id;
}
fn op(h: H&, value: blot_direct_writer::Op) { blot_direct_writer::byte(h.code, value); }
fn idx(h: H&, value: blot_direct_writer::Op, index: u32) {
    op(h, value);
    blot_direct_writer::uleb(h.code, index);
}
fn get(h: H&, local: u32) { idx(h, blot_direct_writer::OP_local_get, local); }
fn set(h: H&, local: u32) { idx(h, blot_direct_writer::OP_local_set, local); }
fn tee(h: H&, local: u32) { idx(h, blot_direct_writer::OP_local_tee, local); }
fn gget(h: H&, global: u32) { idx(h, blot_direct_writer::OP_global_get, global); }
fn gset(h: H&, global: u32) { idx(h, blot_direct_writer::OP_global_set, global); }
fn k(h: H&, value: u32) {
    op(h, blot_direct_writer::OP_i32_const);
    blot_direct_writer::sleb(h.code, value as! i32);
}
fn load(h: H&, offset: u32) {
    op(h, blot_direct_writer::OP_i32_load);
    blot_direct_writer::uleb(h.code, 2);
    blot_direct_writer::uleb(h.code, offset);
}
fn store(h: H&, offset: u32) {
    op(h, blot_direct_writer::OP_i32_store);
    blot_direct_writer::uleb(h.code, 2);
    blot_direct_writer::uleb(h.code, offset);
}
// Traps when the i32 on the stack is nonzero (logical failure: leaves arena_oom_flag = 0).
fn trapIf(h: H&) {
    op(h, blot_direct_writer::OP_if_);
    blot_direct_writer::byte(h.code, 0x40);
    op(h, blot_direct_writer::OP_unreachable_);
    op(h, blot_direct_writer::OP_end);
}
// Traps when the i32 on the stack is nonzero, recording physical arena OOM at Page-0 offset 640.
fn trapOomIf(h: H&, oom_offset: u32) {
    op(h, blot_direct_writer::OP_if_);
    blot_direct_writer::byte(h.code, 0x40);
    k(h, oom_offset);
    k(h, 1);
    store(h, 0);
    op(h, blot_direct_writer::OP_unreachable_);
    op(h, blot_direct_writer::OP_end);
}
fn open(h: H&, kind: blot_direct_writer::Op) {
    op(h, kind);
    blot_direct_writer::byte(h.code, 0x40);
}
fn call(h: H&, function: u32) { idx(h, blot_direct_writer::OP_call, function); }
fn memoryCopy(h: H&) {
    op(h, blot_direct_writer::OP_prefix_fc);
    blot_direct_writer::uleb(h.code, 10);
    blot_direct_writer::byte(h.code, 0);
    blot_direct_writer::byte(h.code, 0);
}
fn memoryFill(h: H&) {
    op(h, blot_direct_writer::OP_prefix_fc);
    blot_direct_writer::uleb(h.code, 11);
    blot_direct_writer::byte(h.code, 0);
}
fn memoryGrow(h: H&) {
    op(h, blot_direct_writer::OP_memory_grow);
    blot_direct_writer::byte(h.code, 0);
}
fn finish(h: H&, module: blot_direct_writer::Module&, function: u32) {
    op(h, blot_direct_writer::OP_end);
    var out: u8[>..<] = [];
    let declared = h.locals - h.parameters;
    if declared == 0 { blot_direct_writer::uleb(out, 0); } else {
        blot_direct_writer::uleb(out, 1);
        blot_direct_writer::uleb(out, declared);
        blot_direct_writer::byte(out, blot_direct_writer::VT_i32);
    }
    blot_direct_writer::raw(out, h.code[..]);
    blot_direct_writer::setBody(module, function, out[..]);
}

// A signature of `params` i32 parameters and `results` i32 results (at most six each).
fn sig(module: blot_direct_writer::Module&, params: i64, results: i64) -> u32 {
    let all: blot_direct_writer::ValType[6] = [blot_direct_writer::VT_i32; 6];
    return blot_direct_writer::signature(module, all[..params], all[..results]);
}
fn helper(module: blot_direct_writer::Module&, params: i64, results: i64) -> u32 {
    return blot_direct_writer::addFunction(module, sig(module, params, results));
}

// Emits `owner_dir[slot >> 8]` address onto the stack.
fn emitOwnerDirAddr(h: H&, slot_local: u32, owner_dir: u32) {
    get(h, slot_local);
    k(h, 8);
    op(h, blot_direct_writer::OP_i32_shr_u);
    k(h, 2);
    op(h, blot_direct_writer::OP_i32_shl);
    k(h, owner_dir);
    op(h, blot_direct_writer::OP_i32_add);
}
// Emits `block + ((slot & 255) << 4)` onto the stack.
fn emitOwnerEntryFromBlock(h: H&, block_local: u32, slot_local: u32) {
    get(h, block_local);
    get(h, slot_local);
    k(h, 255);
    op(h, blot_direct_writer::OP_i32_and);
    k(h, 4);
    op(h, blot_direct_writer::OP_i32_shl);
    op(h, blot_direct_writer::OP_i32_add);
}
// Emits `(fork_depth != 0) && ((slot < fork_owner_mark) || (slot >= persistent_split))`.
fn emitMustUndo(h: H&, r: const Runtime&, slot_local: u32) {
    gget(h, r.fork_depth);
    k(h, 0);
    op(h, blot_direct_writer::OP_i32_ne);
    get(h, slot_local);
    gget(h, r.fork_owner_mark);
    op(h, blot_direct_writer::OP_i32_lt_u);
    get(h, slot_local);
    k(h, r.layout.persistent_split);
    op(h, blot_direct_writer::OP_i32_ge_u);
    op(h, blot_direct_writer::OP_i32_or);
    op(h, blot_direct_writer::OP_i32_and);
}
// Emits `size_class` and `size = next_pow2(max(bytes_local, 16))` into locals.
fn emitPow2Class(h: H&, bytes_local: u32, class_local: u32, size_local: u32) {
    k(h, 32);
    get(h, bytes_local);
    k(h, 16);
    get(h, bytes_local);
    k(h, 16);
    op(h, blot_direct_writer::OP_i32_gt_u);
    op(h, blot_direct_writer::OP_select);
    k(h, 1);
    op(h, blot_direct_writer::OP_i32_sub);
    op(h, blot_direct_writer::OP_i32_clz);
    op(h, blot_direct_writer::OP_i32_sub);
    set(h, class_local);
    k(h, 1);
    get(h, class_local);
    op(h, blot_direct_writer::OP_i32_shl);
    set(h, size_local);
}
// Push an unlinked stack chunk onto its exact-capacity free list.
fn emitPushStackFree(h: H&, r: const Runtime&, chunk_local: u32, std_cap: u32) {
    get(h, chunk_local);
    load(h, 12);
    k(h, std_cap);
    op(h, blot_direct_writer::OP_i32_eq);
    open(h, blot_direct_writer::OP_if_);
    get(h, chunk_local);
    gget(h, r.stack_free_32k);
    store(h, 4);
    get(h, chunk_local);
    gset(h, r.stack_free_32k);
    op(h, blot_direct_writer::OP_else_);
    get(h, chunk_local);
    gget(h, r.stack_free_large);
    store(h, 4);
    get(h, chunk_local);
    gset(h, r.stack_free_large);
    op(h, blot_direct_writer::OP_end);
}

// open(base, length, capacity) -> (slot, generation)
// Initializes generation = 1 when 0, ORs `live_flag` into capacity.
// Persistent variant pops `persistent_free_head` before bumping `persistent_bottom`.
fn emitOpen(module: blot_direct_writer::Module&, r: const Runtime&, function: u32, persistent: bool) {
    var h = H { parameters: 3, locals: 3, .. };
    let slot = temp(h);
    let dir = temp(h);
    let blk = temp(h);
    let entry = temp(h);
    let gen = temp(h);
    if persistent {
        gget(h, r.persistent_free_head);
        tee(h, slot);
        open(h, blot_direct_writer::OP_if_);
        emitOwnerDirAddr(h, slot, r.layout.owner_table);
        load(h, 0);
        set(h, blk);
        emitOwnerEntryFromBlock(h, blk, slot);
        tee(h, entry);
        load(h, entry_base);
        gset(h, r.persistent_free_head);
        gget(h, r.persistent_free_count);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_sub);
        gset(h, r.persistent_free_count);
        op(h, blot_direct_writer::OP_else_);
        gget(h, r.persistent_bottom);
        tee(h, slot);
        k(h, r.layout.owner_capacity);
        op(h, blot_direct_writer::OP_i32_ge_u);
        trapIf(h);
        emitOwnerDirAddr(h, slot, r.layout.owner_table);
        tee(h, dir);
        load(h, 0);
        tee(h, blk);
        op(h, blot_direct_writer::OP_i32_eqz);
        open(h, blot_direct_writer::OP_if_);
        k(h, owner_block_bytes);
        call(h, r.alloc_raw);
        tee(h, blk);
        get(h, dir);
        get(h, blk);
        store(h, 0);
        op(h, blot_direct_writer::OP_drop);
        op(h, blot_direct_writer::OP_end);
        // Advance slot pointer only after the backing block is committed (trap-safe).
        get(h, slot);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.persistent_bottom);
        emitOwnerEntryFromBlock(h, blk, slot);
        set(h, entry);
        op(h, blot_direct_writer::OP_end);
    } else {
        gget(h, r.owner_top);
        tee(h, slot);
        k(h, r.layout.persistent_split);
        op(h, blot_direct_writer::OP_i32_ge_u);
        trapIf(h);
        emitOwnerDirAddr(h, slot, r.layout.owner_table);
        tee(h, dir);
        load(h, 0);
        tee(h, blk);
        op(h, blot_direct_writer::OP_i32_eqz);
        open(h, blot_direct_writer::OP_if_);
        k(h, owner_block_bytes);
        call(h, r.alloc_raw);
        tee(h, blk);
        get(h, dir);
        get(h, blk);
        store(h, 0);
        op(h, blot_direct_writer::OP_drop);
        op(h, blot_direct_writer::OP_end);
        get(h, slot);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.owner_top);
        emitOwnerEntryFromBlock(h, blk, slot);
        set(h, entry);
    }
    get(h, entry);
    get(h, 0);
    store(h, entry_base);
    get(h, entry);
    get(h, 1);
    store(h, entry_length);
    get(h, entry);
    get(h, 2);
    k(h, live_flag);
    op(h, blot_direct_writer::OP_i32_or);
    store(h, entry_capacity);
    get(h, entry);
    load(h, entry_generation);
    tee(h, gen);
    op(h, blot_direct_writer::OP_i32_eqz);
    open(h, blot_direct_writer::OP_if_);
    k(h, 1);
    tee(h, gen);
    get(h, entry);
    get(h, gen);
    store(h, entry_generation);
    op(h, blot_direct_writer::OP_drop);
    op(h, blot_direct_writer::OP_end);
    get(h, slot);
    get(h, gen);
    finish(h, module, function);
}

// Emits the globals and helpers. Call before any other function is added
// only if imports are already declared (imports precede functions).
fn emit(module: blot_direct_writer::Module&, budgets: Budgets) -> Runtime {
    return emitWithOptions(module, budgets, false, false);
}
fn emitWithFork(module: blot_direct_writer::Module&, budgets: Budgets, has_fork: bool) -> Runtime {
    return emitWithOptions(module, budgets, has_fork, false);
}
fn emitWithOptions(module: blot_direct_writer::Module&, budgets: Budgets, has_fork: bool, has_persistent_state: bool) -> Runtime {
    let layout = initWithFork(budgets, has_fork);
    let i32t = blot_direct_writer::VT_i32;
    var r = Runtime { layout: layout, has_fork: has_fork, has_persistent_state: has_persistent_state, .. };
    r.owner_top = blot_direct_writer::addGlobal(module, i32t, true, 1);
    r.persistent_bottom = blot_direct_writer::addGlobal(module, i32t, true, layout.persistent_split);
    r.arena_top = blot_direct_writer::addGlobal(module, i32t, true, arena_start);
    r.page_top = blot_direct_writer::addGlobal(module, i32t, true, initial_page_bytes);
    r.stack_head = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.stack_chunk = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.stack_pointer = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.stack_limit = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.stack_total = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.stack_live_bytes = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.stack_free_32k = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.stack_free_large = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.heap_top = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.heap_live_bytes = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.persistent_top = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.transport_base = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.transport_cap = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.transport_top = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.effect_context = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.escape_min_slot = blot_direct_writer::addGlobal(module, i32t, true, 0xffffffff);
    r.persistent_free_head = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.persistent_free_count = blot_direct_writer::addGlobal(module, i32t, true, 0);
    if has_persistent_state {
        r.static_blocks_ptr = blot_direct_writer::addGlobal(module, i32t, true, 0);
        r.static_blocks_len = blot_direct_writer::addGlobal(module, i32t, true, 0);
        r.static_blocks_cap = blot_direct_writer::addGlobal(module, i32t, true, 0);
    }
    if has_fork {
        r.fork_owner_mark = blot_direct_writer::addGlobal(module, i32t, true, 0);
        r.fork_depth = blot_direct_writer::addGlobal(module, i32t, true, 0);
        r.undo_base = blot_direct_writer::addGlobal(module, i32t, true, 0);
        r.undo_end = blot_direct_writer::addGlobal(module, i32t, true, 0);
        r.undo_sp = blot_direct_writer::addGlobal(module, i32t, true, 0);
    }
    r.alloc_raw = helper(module, 1, 1);
    r.open = helper(module, 3, 2);
    r.open_persistent = helper(module, 3, 2);
    r.open_heap = helper(module, 2, 4);
    r.detach_temp_slot = helper(module, 1, 0);
    r.release = helper(module, 1, 0);
    r.check = helper(module, 2, 1);
    r.stack = helper(module, 1, 1);
    r.stack_slow = helper(module, 1, 1);
    r.rewind_stack = helper(module, 1, 0);
    r.rewind_stack_slow = helper(module, 1, 0);
    r.heap_alloc = helper(module, 1, 2);
    r.heap_free = helper(module, 2, 0);
    r.alloc_transport = helper(module, 1, 2);
    r.open_transport_pin = helper(module, 1, 4);
    r.free_transport = helper(module, 2, 0);
    r.alloc_persistent = helper(module, 1, 1);
    r.address = helper(module, 4, 1);
    r.length = helper(module, 2, 1);
    r.push = helper(module, 3, 1);
    r.pop = helper(module, 3, 1);
    r.truncate = helper(module, 3, 0);
    r.freeze = helper(module, 2, 0);
    r.create = helper(module, 3, 2);
    r.copy = helper(module, 4, 2);
    r.persist = helper(module, 4, 2);
    r.allocate = helper(module, 1, 1);
    r.reset = helper(module, 1, 1);
    r.packet_length = helper(module, 1, 1);
    if has_persistent_state {
        r.free_persistent = helper(module, 2, 0);
        r.ensure_persistent_slots = helper(module, 1, 0);
        r.is_stack_range = helper(module, 2, 1);
        r.record_static_block = helper(module, 3, 0);
        r.open_vec = helper(module, 1, 1);
        r.scratch_push = helper(module, 2, 1);
        r.open_hmap = helper(module, 0, 1);
        r.hmap_get = helper(module, 4, 2);
        r.hmap_put = helper(module, 5, 0);
    }
    if has_fork {
        r.undo_reserve = helper(module, 1, 0);
        r.undo_record = helper(module, 2, 0);
        r.undo_rewind = helper(module, 1, 0);
    }
    let ot = layout.owner_table;
    let stack_budget = layout.stack_end - layout.stack_base;
    let heap_budget = layout.heap_end - layout.heap_base;
    let persistent_budget = layout.persistent_end - layout.persistent_base;
    let transport_budget = layout.transport_end - layout.transport_base;
    var std_cap: u32 = stack_chunk_std;
    if stack_budget < stack_chunk_std + stack_header_bytes {
        if stack_budget > stack_header_bytes { std_cap = (stack_budget - stack_header_bytes) & 0xfffffff0; } else { std_cap = 0; }
    }

    // alloc_raw(bytes) -> 16-byte aligned address, growing Wasm pages on demand.
    // Sets Page-0 offset 640 (`arena_oom_flag`) before trapping on physical exhaustion.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let address = temp(h);
        let next = temp(h);
        let need_pages = temp(h);
        let old_pages = temp(h);
        gget(h, r.arena_top);
        k(h, 15);
        op(h, blot_direct_writer::OP_i32_add);
        k(h, 0xfffffff0);
        op(h, blot_direct_writer::OP_i32_and);
        tee(h, address);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_add);
        tee(h, next);
        get(h, address);
        op(h, blot_direct_writer::OP_i32_lt_u);
        get(h, next);
        k(h, layout.total);
        op(h, blot_direct_writer::OP_i32_gt_u);
        op(h, blot_direct_writer::OP_i32_or);
        trapOomIf(h, layout.arena_oom_offset);
        get(h, next);
        gget(h, r.page_top);
        op(h, blot_direct_writer::OP_i32_gt_u);
        open(h, blot_direct_writer::OP_if_);
        get(h, next);
        gget(h, r.page_top);
        op(h, blot_direct_writer::OP_i32_sub);
        k(h, 65535);
        op(h, blot_direct_writer::OP_i32_add);
        k(h, 16);
        op(h, blot_direct_writer::OP_i32_shr_u);
        tee(h, need_pages);
        memoryGrow(h);
        tee(h, old_pages);
        k(h, 0xffffffff);
        op(h, blot_direct_writer::OP_i32_eq);
        trapOomIf(h, layout.arena_oom_offset);
        get(h, old_pages);
        get(h, need_pages);
        op(h, blot_direct_writer::OP_i32_add);
        k(h, 16);
        op(h, blot_direct_writer::OP_i32_shl);
        gset(h, r.page_top);
        op(h, blot_direct_writer::OP_end);
        get(h, next);
        gset(h, r.arena_top);
        get(h, address);
        finish(h, module, r.alloc_raw);
    }

    emitOpen(module, r, r.open, false);
    emitOpen(module, r, r.open_persistent, true);

    // heap_free(address, size): decrement heap_live_bytes and push onto size class free list.
    {
        var h = H { parameters: 2, locals: 2, .. };
        let head = temp(h);
        get(h, 1);
        op(h, blot_direct_writer::OP_i32_eqz);
        open(h, blot_direct_writer::OP_if_);
        op(h, blot_direct_writer::OP_return_);
        op(h, blot_direct_writer::OP_end);
        gget(h, r.heap_live_bytes);
        get(h, 1);
        op(h, blot_direct_writer::OP_i32_sub);
        gset(h, r.heap_live_bytes);
        k(h, 31);
        get(h, 1);
        op(h, blot_direct_writer::OP_i32_clz);
        op(h, blot_direct_writer::OP_i32_sub);
        k(h, 4);
        op(h, blot_direct_writer::OP_i32_mul);
        k(h, layout.free_lists);
        op(h, blot_direct_writer::OP_i32_add);
        set(h, head);
        get(h, 0);
        get(h, head);
        load(h, 0);
        store(h, 0);
        get(h, head);
        get(h, 0);
        store(h, 0);
        finish(h, module, r.heap_free);
    }

    // free_transport(address, size): push onto dedicated transport free list (never touches heap_live_bytes).
    {
        var h = H { parameters: 2, locals: 2, .. };
        let head = temp(h);
        get(h, 1);
        op(h, blot_direct_writer::OP_i32_eqz);
        open(h, blot_direct_writer::OP_if_);
        op(h, blot_direct_writer::OP_return_);
        op(h, blot_direct_writer::OP_end);
        k(h, 31);
        get(h, 1);
        op(h, blot_direct_writer::OP_i32_clz);
        op(h, blot_direct_writer::OP_i32_sub);
        k(h, 4);
        op(h, blot_direct_writer::OP_i32_mul);
        k(h, layout.transport_free_lists);
        op(h, blot_direct_writer::OP_i32_add);
        set(h, head);
        get(h, 0);
        get(h, head);
        load(h, 0);
        store(h, 0);
        get(h, head);
        get(h, 0);
        store(h, 0);
        finish(h, module, r.free_transport);
    }

    // alloc_transport(want) -> (address, size): dedicated power-of-two transport pool.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let class = temp(h);
        let head = temp(h);
        let address = temp(h);
        let size = temp(h);
        get(h, 0);
        k(h, transport_budget);
        op(h, blot_direct_writer::OP_i32_gt_u);
        trapIf(h);
        emitPow2Class(h, 0, class, size);
        get(h, class);
        k(h, 4);
        op(h, blot_direct_writer::OP_i32_mul);
        k(h, layout.transport_free_lists);
        op(h, blot_direct_writer::OP_i32_add);
        tee(h, head);
        load(h, 0);
        tee(h, address);
        open(h, blot_direct_writer::OP_if_);
        get(h, head);
        get(h, address);
        load(h, 0);
        store(h, 0);
        op(h, blot_direct_writer::OP_else_);
        get(h, size);
        call(h, r.alloc_raw);
        set(h, address);
        op(h, blot_direct_writer::OP_end);
        get(h, address);
        get(h, size);
        finish(h, module, r.alloc_transport);
    }

    // open_transport_pin(want) -> (slot, gen, base, actual_cap): reserve temp slot FIRST,
    // then allocate from transport pool, tagging slot with static_pool_flag | live_flag.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let slot = temp(h);
        let gen = temp(h);
        let base = temp(h);
        let size = temp(h);
        let blk = temp(h);
        let entry = temp(h);
        k(h, 0);
        k(h, 0);
        k(h, 0);
        call(h, r.open);
        set(h, gen);
        set(h, slot);
        get(h, 0);
        call(h, r.alloc_transport);
        set(h, size);
        set(h, base);
        emitOwnerDirAddr(h, slot, ot);
        load(h, 0);
        set(h, blk);
        emitOwnerEntryFromBlock(h, blk, slot);
        tee(h, entry);
        get(h, base);
        store(h, entry_base);
        get(h, entry);
        k(h, 0);
        store(h, entry_length);
        get(h, entry);
        get(h, size);
        k(h, static_pool_flag | live_flag);
        op(h, blot_direct_writer::OP_i32_or);
        store(h, entry_capacity);
        get(h, slot);
        get(h, gen);
        get(h, base);
        get(h, size);
        finish(h, module, r.open_transport_pin);
    }

    // open_heap(bytes, length) -> (slot, gen, base, actual_cap): reserve temp slot FIRST,
    // then allocate from rt.heap, writing heap_flag | live_flag.
    {
        var h = H { parameters: 2, locals: 2, .. };
        let slot = temp(h);
        let gen = temp(h);
        let base = temp(h);
        let size = temp(h);
        let blk = temp(h);
        let entry = temp(h);
        k(h, 0);
        k(h, 0);
        k(h, 0);
        call(h, r.open);
        set(h, gen);
        set(h, slot);
        get(h, 0);
        call(h, r.heap_alloc);
        set(h, size);
        set(h, base);
        emitOwnerDirAddr(h, slot, ot);
        load(h, 0);
        set(h, blk);
        emitOwnerEntryFromBlock(h, blk, slot);
        tee(h, entry);
        get(h, base);
        store(h, entry_base);
        get(h, entry);
        get(h, 1);
        store(h, entry_length);
        get(h, entry);
        get(h, size);
        k(h, heap_flag | live_flag);
        op(h, blot_direct_writer::OP_i32_or);
        store(h, entry_capacity);
        get(h, slot);
        get(h, gen);
        get(h, base);
        get(h, size);
        finish(h, module, r.open_heap);
    }

    // detach_temp_slot(slot): zero base/length/capacity so release(1) does not free transferred backing.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let blk = temp(h);
        let entry = temp(h);
        emitOwnerDirAddr(h, 0, ot);
        load(h, 0);
        set(h, blk);
        emitOwnerEntryFromBlock(h, blk, 0);
        tee(h, entry);
        k(h, 0);
        store(h, entry_base);
        get(h, entry);
        k(h, 0);
        store(h, entry_length);
        get(h, entry);
        k(h, 0);
        store(h, entry_capacity);
        finish(h, module, r.detach_temp_slot);
    }

    // release(mark): every temp owner opened above mark is invalidated and its backing freed.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let slot = temp(h);
        let blk = temp(h);
        let entry = temp(h);
        let capacity = temp(h);
        let base = temp(h);
        let next_gen = temp(h);
        open(h, blot_direct_writer::OP_block);
        open(h, blot_direct_writer::OP_loop);
        gget(h, r.owner_top);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_le_u);
        idx(h, blot_direct_writer::OP_br_if, 1);
        gget(h, r.owner_top);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_sub);
        tee(h, slot);
        gset(h, r.owner_top);
        emitOwnerDirAddr(h, slot, ot);
        load(h, 0);
        set(h, blk);
        emitOwnerEntryFromBlock(h, blk, slot);
        tee(h, entry);
        load(h, entry_generation);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_add);
        tee(h, next_gen);
        op(h, blot_direct_writer::OP_i32_eqz);
        open(h, blot_direct_writer::OP_if_);
        k(h, 1);
        set(h, next_gen);
        op(h, blot_direct_writer::OP_end);
        get(h, entry);
        get(h, next_gen);
        store(h, entry_generation);
        get(h, entry);
        load(h, entry_base);
        set(h, base);
        get(h, entry);
        load(h, entry_capacity);
        set(h, capacity);
        get(h, entry);
        k(h, 0);
        store(h, entry_base);
        get(h, entry);
        k(h, 0);
        store(h, entry_length);
        get(h, entry);
        k(h, 0);
        store(h, entry_capacity);
        get(h, capacity);
        k(h, heap_flag);
        op(h, blot_direct_writer::OP_i32_and);
        open(h, blot_direct_writer::OP_if_);
        get(h, base);
        get(h, capacity);
        k(h, capacity_mask);
        op(h, blot_direct_writer::OP_i32_and);
        call(h, r.heap_free);
        op(h, blot_direct_writer::OP_else_);
        get(h, capacity);
        k(h, static_pool_flag);
        op(h, blot_direct_writer::OP_i32_and);
        open(h, blot_direct_writer::OP_if_);
        get(h, base);
        get(h, capacity);
        k(h, capacity_mask);
        op(h, blot_direct_writer::OP_i32_and);
        call(h, r.free_transport);
        op(h, blot_direct_writer::OP_end);
        op(h, blot_direct_writer::OP_end);
        idx(h, blot_direct_writer::OP_br, 0);
        op(h, blot_direct_writer::OP_end);
        op(h, blot_direct_writer::OP_end);
        finish(h, module, r.release);
    }

    // check(slot, generation) -> entry; requires valid bounds, non-null block, live_flag, and non-zero matching generation.
    {
        var h = H { parameters: 2, locals: 2, .. };
        let blk = temp(h);
        let entry = temp(h);
        get(h, 0);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_sub);
        k(h, layout.owner_capacity - 1);
        op(h, blot_direct_writer::OP_i32_ge_u);
        get(h, 1);
        op(h, blot_direct_writer::OP_i32_eqz);
        op(h, blot_direct_writer::OP_i32_or);
        trapIf(h);
        get(h, 0);
        k(h, 8);
        op(h, blot_direct_writer::OP_i32_shr_u);
        k(h, 2);
        op(h, blot_direct_writer::OP_i32_shl);
        load(h, ot);
        tee(h, blk);
        op(h, blot_direct_writer::OP_i32_eqz);
        trapIf(h);
        emitOwnerEntryFromBlock(h, blk, 0);
        tee(h, entry);
        load(h, entry_capacity);
        k(h, live_flag);
        op(h, blot_direct_writer::OP_i32_and);
        op(h, blot_direct_writer::OP_i32_eqz);
        get(h, entry);
        load(h, entry_generation);
        get(h, 1);
        op(h, blot_direct_writer::OP_i32_ne);
        op(h, blot_direct_writer::OP_i32_or);
        trapIf(h);
        get(h, entry);
        finish(h, module, r.check);
    }

    // stack_slow(need) -> address: active-only order-independent canonical-cap free lists.
    // Caller (`rt.stack`) has already checked logical `stack_live_bytes + need <= stack_budget`.
    // Allocations in `(std_cap .. min(16 MiB, stack_budget / 4)]` use power-of-two physical
    // chunk capacities (`cur + 12`) so varying frame-to-frame large arrays reuse existing chunks
    // without unbounded `stack_total` growth, while `cur + 8` (`stack_limit`) is ALWAYS clamped
    // to `result + need` for `need > std_cap` so warm workers NEVER pack more into a large chunk
    // than a fresh worker (`warm_memory_bytes(P) >= fresh_memory_bytes(P)`).
    {
        var h = H { parameters: 1, locals: 1, .. };
        let want_cap = temp(h);
        let tmp_class = temp(h);
        let cur = temp(h);
        let prev_free = temp(h);
        let chunk_bytes = temp(h);
        let tail = temp(h);
        let result = temp(h);
        let limit = temp(h);
        var pow2_cap_limit: u32 = 16777216;
        if stack_budget / 4 < pow2_cap_limit { pow2_cap_limit = stack_budget / 4; }
        // Canonical want_cap = std_cap (need <= std_cap), next_pow2(need) (std_cap < need <= pow2_cap_limit), else need.
        get(h, 0);
        k(h, std_cap);
        op(h, blot_direct_writer::OP_i32_le_u);
        open(h, blot_direct_writer::OP_if_);
        k(h, std_cap);
        set(h, want_cap);
        gget(h, r.stack_free_32k);
        tee(h, cur);
        open(h, blot_direct_writer::OP_if_);
        get(h, cur);
        load(h, 4);
        gset(h, r.stack_free_32k);
        op(h, blot_direct_writer::OP_end);
        op(h, blot_direct_writer::OP_else_);
        get(h, 0);
        k(h, pow2_cap_limit);
        op(h, blot_direct_writer::OP_i32_le_u);
        open(h, blot_direct_writer::OP_if_);
        emitPow2Class(h, 0, tmp_class, want_cap);
        op(h, blot_direct_writer::OP_else_);
        get(h, 0);
        set(h, want_cap);
        op(h, blot_direct_writer::OP_end);
        k(h, 0);
        set(h, prev_free);
        gget(h, r.stack_free_large);
        set(h, cur);
        open(h, blot_direct_writer::OP_block);
        open(h, blot_direct_writer::OP_loop);
        get(h, cur);
        op(h, blot_direct_writer::OP_i32_eqz);
        idx(h, blot_direct_writer::OP_br_if, 1);
        get(h, cur);
        load(h, 12);
        get(h, want_cap);
        op(h, blot_direct_writer::OP_i32_eq);
        open(h, blot_direct_writer::OP_if_);
        get(h, prev_free);
        open(h, blot_direct_writer::OP_if_);
        get(h, prev_free);
        get(h, cur);
        load(h, 4);
        store(h, 4);
        op(h, blot_direct_writer::OP_else_);
        get(h, cur);
        load(h, 4);
        gset(h, r.stack_free_large);
        op(h, blot_direct_writer::OP_end);
        idx(h, blot_direct_writer::OP_br, 2);
        op(h, blot_direct_writer::OP_end);
        get(h, cur);
        set(h, prev_free);
        get(h, cur);
        load(h, 4);
        set(h, cur);
        idx(h, blot_direct_writer::OP_br, 0);
        op(h, blot_direct_writer::OP_end);
        op(h, blot_direct_writer::OP_end);
        op(h, blot_direct_writer::OP_end);
        // Miss: carve a new canonical-cap chunk (`want_cap + 32` bytes), marking offset 640 on physical ceiling.
        get(h, cur);
        op(h, blot_direct_writer::OP_i32_eqz);
        open(h, blot_direct_writer::OP_if_);
        get(h, want_cap);
        k(h, stack_header_bytes);
        op(h, blot_direct_writer::OP_i32_add);
        tee(h, chunk_bytes);
        get(h, want_cap);
        op(h, blot_direct_writer::OP_i32_lt_u);
        gget(h, r.stack_total);
        get(h, chunk_bytes);
        op(h, blot_direct_writer::OP_i32_add);
        gget(h, r.stack_total);
        op(h, blot_direct_writer::OP_i32_lt_u);
        op(h, blot_direct_writer::OP_i32_or);
        gget(h, r.stack_total);
        get(h, chunk_bytes);
        op(h, blot_direct_writer::OP_i32_add);
        k(h, stack_budget);
        op(h, blot_direct_writer::OP_i32_gt_u);
        op(h, blot_direct_writer::OP_i32_or);
        trapOomIf(h, layout.arena_oom_offset);
        get(h, chunk_bytes);
        call(h, r.alloc_raw);
        set(h, cur);
        gget(h, r.stack_total);
        get(h, chunk_bytes);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.stack_total);
        get(h, cur);
        get(h, want_cap);
        store(h, 12);
        op(h, blot_direct_writer::OP_end);
        // Append `cur` to tail of active-only chain and save outgoing chunk's used_end.
        gget(h, r.stack_chunk);
        tee(h, tail);
        open(h, blot_direct_writer::OP_if_);
        get(h, tail);
        gget(h, r.stack_pointer);
        store(h, 16);
        get(h, tail);
        get(h, cur);
        store(h, 4);
        op(h, blot_direct_writer::OP_else_);
        get(h, cur);
        gset(h, r.stack_head);
        op(h, blot_direct_writer::OP_end);
        get(h, cur);
        get(h, tail);
        store(h, 0);
        get(h, cur);
        k(h, 0);
        store(h, 4);
        get(h, cur);
        k(h, stack_header_bytes);
        op(h, blot_direct_writer::OP_i32_add);
        tee(h, result);
        get(h, cur);
        get(h, result);
        store(h, 16);
        op(h, blot_direct_writer::OP_drop);
        // Effective active limit: `result + std_cap` for standard chunks, `result + need` for large chunks.
        get(h, result);
        k(h, std_cap);
        get(h, 0);
        get(h, 0);
        k(h, std_cap);
        op(h, blot_direct_writer::OP_i32_le_u);
        op(h, blot_direct_writer::OP_select);
        op(h, blot_direct_writer::OP_i32_add);
        tee(h, limit);
        gset(h, r.stack_limit);
        get(h, cur);
        get(h, limit);
        store(h, 8);
        get(h, cur);
        gset(h, r.stack_chunk);
        get(h, result);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.stack_pointer);
        gget(h, r.stack_live_bytes);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.stack_live_bytes);
        get(h, result);
        finish(h, module, r.stack_slow);
    }

    // stack(bytes) -> address, 16-byte aligned; checks logical stack_live_bytes FIRST.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let need = temp(h);
        let next_live = temp(h);
        let address = temp(h);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_eqz);
        open(h, blot_direct_writer::OP_if_);
        k(h, 16);
        op(h, blot_direct_writer::OP_return_);
        op(h, blot_direct_writer::OP_end);
        get(h, 0);
        k(h, 15);
        op(h, blot_direct_writer::OP_i32_add);
        k(h, 0xfffffff0);
        op(h, blot_direct_writer::OP_i32_and);
        tee(h, need);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_lt_u);
        gget(h, r.stack_live_bytes);
        get(h, need);
        op(h, blot_direct_writer::OP_i32_add);
        tee(h, next_live);
        gget(h, r.stack_live_bytes);
        op(h, blot_direct_writer::OP_i32_lt_u);
        op(h, blot_direct_writer::OP_i32_or);
        get(h, next_live);
        k(h, stack_budget);
        op(h, blot_direct_writer::OP_i32_gt_u);
        op(h, blot_direct_writer::OP_i32_or);
        trapIf(h);
        get(h, need);
        gget(h, r.stack_limit);
        gget(h, r.stack_pointer);
        op(h, blot_direct_writer::OP_i32_sub);
        op(h, blot_direct_writer::OP_i32_gt_u);
        open(h, blot_direct_writer::OP_if_);
        get(h, need);
        call(h, r.stack_slow);
        op(h, blot_direct_writer::OP_return_);
        op(h, blot_direct_writer::OP_end);
        gget(h, r.stack_pointer);
        tee(h, address);
        get(h, need);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.stack_pointer);
        get(h, next_live);
        gset(h, r.stack_live_bytes);
        get(h, address);
        finish(h, module, r.stack);
    }

    // rewind_stack(mark): fast path in current active chunk; slow path unlinks unwound chunks.
    {
        var h = H { parameters: 1, locals: 1, .. };
        gget(h, r.stack_chunk);
        k(h, 0);
        op(h, blot_direct_writer::OP_i32_ne);
        get(h, 0);
        gget(h, r.stack_chunk);
        k(h, stack_header_bytes);
        op(h, blot_direct_writer::OP_i32_add);
        op(h, blot_direct_writer::OP_i32_ge_u);
        op(h, blot_direct_writer::OP_i32_and);
        get(h, 0);
        gget(h, r.stack_pointer);
        op(h, blot_direct_writer::OP_i32_le_u);
        op(h, blot_direct_writer::OP_i32_and);
        open(h, blot_direct_writer::OP_if_);
        gget(h, r.stack_live_bytes);
        gget(h, r.stack_pointer);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_sub);
        op(h, blot_direct_writer::OP_i32_sub);
        gset(h, r.stack_live_bytes);
        get(h, 0);
        gset(h, r.stack_pointer);
        op(h, blot_direct_writer::OP_return_);
        op(h, blot_direct_writer::OP_end);
        get(h, 0);
        call(h, r.rewind_stack_slow);
        finish(h, module, r.rewind_stack);
    }

    // rewind_stack_slow(mark): unlinks unwound chunks onto exact-cap free lists and maintains stack_live_bytes.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let cur = temp(h);
        let prev = temp(h);
        let used = temp(h);
        let start = temp(h);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_eqz);
        open(h, blot_direct_writer::OP_if_);
        gget(h, r.stack_chunk);
        set(h, cur);
        open(h, blot_direct_writer::OP_block);
        open(h, blot_direct_writer::OP_loop);
        get(h, cur);
        op(h, blot_direct_writer::OP_i32_eqz);
        idx(h, blot_direct_writer::OP_br_if, 1);
        get(h, cur);
        load(h, 0);
        set(h, prev);
        emitPushStackFree(h, r, cur, std_cap);
        get(h, prev);
        set(h, cur);
        idx(h, blot_direct_writer::OP_br, 0);
        op(h, blot_direct_writer::OP_end);
        op(h, blot_direct_writer::OP_end);
        k(h, 0);
        gset(h, r.stack_head);
        k(h, 0);
        gset(h, r.stack_chunk);
        k(h, 0);
        gset(h, r.stack_pointer);
        k(h, 0);
        gset(h, r.stack_limit);
        k(h, 0);
        gset(h, r.stack_live_bytes);
        op(h, blot_direct_writer::OP_return_);
        op(h, blot_direct_writer::OP_end);
        gget(h, r.stack_chunk);
        set(h, cur);
        gget(h, r.stack_pointer);
        set(h, used);
        open(h, blot_direct_writer::OP_block);
        open(h, blot_direct_writer::OP_loop);
        get(h, cur);
        op(h, blot_direct_writer::OP_i32_eqz);
        open(h, blot_direct_writer::OP_if_);
        k(h, 0);
        gset(h, r.stack_head);
        k(h, 0);
        gset(h, r.stack_chunk);
        k(h, 0);
        gset(h, r.stack_pointer);
        k(h, 0);
        gset(h, r.stack_limit);
        k(h, 0);
        gset(h, r.stack_live_bytes);
        idx(h, blot_direct_writer::OP_br, 2);
        op(h, blot_direct_writer::OP_end);
        get(h, cur);
        k(h, stack_header_bytes);
        op(h, blot_direct_writer::OP_i32_add);
        set(h, start);
        get(h, 0);
        get(h, start);
        op(h, blot_direct_writer::OP_i32_ge_u);
        get(h, 0);
        get(h, used);
        op(h, blot_direct_writer::OP_i32_le_u);
        op(h, blot_direct_writer::OP_i32_and);
        open(h, blot_direct_writer::OP_if_);
        gget(h, r.stack_live_bytes);
        get(h, used);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_sub);
        op(h, blot_direct_writer::OP_i32_sub);
        gset(h, r.stack_live_bytes);
        get(h, cur);
        k(h, 0);
        store(h, 4);
        get(h, cur);
        gset(h, r.stack_chunk);
        get(h, cur);
        load(h, 8);
        gset(h, r.stack_limit);
        get(h, 0);
        gset(h, r.stack_pointer);
        idx(h, blot_direct_writer::OP_br, 2);
        op(h, blot_direct_writer::OP_end);
        gget(h, r.stack_live_bytes);
        get(h, used);
        get(h, start);
        op(h, blot_direct_writer::OP_i32_sub);
        op(h, blot_direct_writer::OP_i32_sub);
        gset(h, r.stack_live_bytes);
        get(h, cur);
        load(h, 0);
        set(h, prev);
        emitPushStackFree(h, r, cur, std_cap);
        get(h, prev);
        tee(h, cur);
        open(h, blot_direct_writer::OP_if_);
        get(h, cur);
        load(h, 16);
        set(h, used);
        op(h, blot_direct_writer::OP_end);
        idx(h, blot_direct_writer::OP_br, 0);
        op(h, blot_direct_writer::OP_end);
        op(h, blot_direct_writer::OP_end);
        finish(h, module, r.rewind_stack_slow);
    }

    // heap_alloc(bytes) -> (address, size): power-of-two classes from 16 bytes.
    // Checks deterministic logical `heap_live_bytes + size <= heap_budget` FIRST;
    // sets Page-0 offset 640 on physical retained-free-list `heap_top` or `alloc_raw` OOM.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let class = temp(h);
        let head = temp(h);
        let address = temp(h);
        let size = temp(h);
        let next_live = temp(h);
        get(h, 0);
        k(h, heap_budget);
        op(h, blot_direct_writer::OP_i32_gt_u);
        trapIf(h);
        emitPow2Class(h, 0, class, size);
        // Logical heap budget check FIRST (history-independent, offset 640 == 0).
        gget(h, r.heap_live_bytes);
        get(h, size);
        op(h, blot_direct_writer::OP_i32_add);
        tee(h, next_live);
        gget(h, r.heap_live_bytes);
        op(h, blot_direct_writer::OP_i32_lt_u);
        get(h, next_live);
        k(h, heap_budget);
        op(h, blot_direct_writer::OP_i32_gt_u);
        op(h, blot_direct_writer::OP_i32_or);
        trapIf(h);
        get(h, class);
        k(h, 4);
        op(h, blot_direct_writer::OP_i32_mul);
        k(h, layout.free_lists);
        op(h, blot_direct_writer::OP_i32_add);
        tee(h, head);
        load(h, 0);
        tee(h, address);
        open(h, blot_direct_writer::OP_if_);
        get(h, head);
        get(h, address);
        load(h, 0);
        store(h, 0);
        op(h, blot_direct_writer::OP_else_);
        gget(h, r.heap_top);
        get(h, size);
        op(h, blot_direct_writer::OP_i32_add);
        gget(h, r.heap_top);
        op(h, blot_direct_writer::OP_i32_lt_u);
        gget(h, r.heap_top);
        get(h, size);
        op(h, blot_direct_writer::OP_i32_add);
        k(h, heap_budget);
        op(h, blot_direct_writer::OP_i32_gt_u);
        op(h, blot_direct_writer::OP_i32_or);
        trapOomIf(h, layout.arena_oom_offset);
        get(h, size);
        call(h, r.alloc_raw);
        set(h, address);
        gget(h, r.heap_top);
        get(h, size);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.heap_top);
        op(h, blot_direct_writer::OP_end);
        get(h, next_live);
        gset(h, r.heap_live_bytes);
        get(h, address);
        get(h, size);
        finish(h, module, r.heap_alloc);
    }

    // alloc_persistent(bytes) -> address in persistent bump region (start-time static pools).
    {
        var h = H { parameters: 1, locals: 1, .. };
        let aligned = temp(h);
        let address = temp(h);
        get(h, 0);
        k(h, 15);
        op(h, blot_direct_writer::OP_i32_add);
        k(h, 0xfffffff0);
        op(h, blot_direct_writer::OP_i32_and);
        tee(h, aligned);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_lt_u);
        gget(h, r.persistent_top);
        get(h, aligned);
        op(h, blot_direct_writer::OP_i32_add);
        gget(h, r.persistent_top);
        op(h, blot_direct_writer::OP_i32_lt_u);
        op(h, blot_direct_writer::OP_i32_or);
        gget(h, r.persistent_top);
        get(h, aligned);
        op(h, blot_direct_writer::OP_i32_add);
        k(h, persistent_budget);
        op(h, blot_direct_writer::OP_i32_gt_u);
        op(h, blot_direct_writer::OP_i32_or);
        trapIf(h);
        get(h, aligned);
        call(h, r.alloc_raw);
        set(h, address);
        gget(h, r.persistent_top);
        get(h, aligned);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.persistent_top);
        get(h, address);
        finish(h, module, r.alloc_persistent);
    }

    // address(slot, generation, index, stride) -> element address
    {
        var h = H { parameters: 4, locals: 4, .. };
        let entry = temp(h);
        get(h, 0);
        get(h, 1);
        call(h, r.check);
        tee(h, entry);
        get(h, 2);
        get(h, entry);
        load(h, entry_length);
        op(h, blot_direct_writer::OP_i32_ge_u);
        trapIf(h);
        load(h, entry_base);
        get(h, 2);
        get(h, 3);
        op(h, blot_direct_writer::OP_i32_mul);
        op(h, blot_direct_writer::OP_i32_add);
        finish(h, module, r.address);
    }

    // length(slot, generation)
    {
        var h = H { parameters: 2, locals: 2, .. };
        get(h, 0);
        get(h, 1);
        call(h, r.check);
        load(h, entry_length);
        finish(h, module, r.length);
    }

    // push(slot, generation, stride) -> address of the new last element.
    {
        var h = H { parameters: 3, locals: 3, .. };
        let entry = temp(h);
        let capacity = temp(h);
        let length = temp(h);
        let need = temp(h);
        let fresh = temp(h);
        let size = temp(h);
        get(h, 0);
        get(h, 1);
        call(h, r.check);
        tee(h, entry);
        load(h, entry_capacity);
        tee(h, capacity);
        k(h, frozen_flag);
        op(h, blot_direct_writer::OP_i32_and);
        trapIf(h);
        if has_fork {
            emitMustUndo(h, r, 0);
            open(h, blot_direct_writer::OP_if_);
            get(h, entry);
            k(h, 12);
            call(h, r.undo_record);
            op(h, blot_direct_writer::OP_end);
        }
        get(h, entry);
        load(h, entry_length);
        tee(h, length);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_add);
        get(h, 2);
        op(h, blot_direct_writer::OP_i32_mul);
        tee(h, need);
        get(h, capacity);
        k(h, capacity_mask);
        op(h, blot_direct_writer::OP_i32_and);
        op(h, blot_direct_writer::OP_i32_gt_u);
        open(h, blot_direct_writer::OP_if_);
        if has_fork {
            emitMustUndo(h, r, 0);
            open(h, blot_direct_writer::OP_if_);
            k(h, 32);
            call(h, r.undo_reserve);
            op(h, blot_direct_writer::OP_end);
        }
        // Grow: at least double, into the heap; free the old heap block unless protected by fork.
        get(h, need);
        get(h, capacity);
        k(h, capacity_mask);
        op(h, blot_direct_writer::OP_i32_and);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_shl);
        get(h, need);
        get(h, capacity);
        k(h, capacity_mask);
        op(h, blot_direct_writer::OP_i32_and);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_shl);
        op(h, blot_direct_writer::OP_i32_gt_u);
        op(h, blot_direct_writer::OP_select);
        call(h, r.heap_alloc);
        set(h, size);
        set(h, fresh);
        if has_fork {
            emitMustUndo(h, r, 0);
            open(h, blot_direct_writer::OP_if_);
            gget(h, r.undo_sp);
            get(h, fresh);
            store(h, 0);
            gget(h, r.undo_sp);
            get(h, size);
            k(h, 0x80000000);
            op(h, blot_direct_writer::OP_i32_or);
            store(h, 4);
            gget(h, r.undo_sp);
            k(h, 8);
            op(h, blot_direct_writer::OP_i32_add);
            gset(h, r.undo_sp);
            op(h, blot_direct_writer::OP_end);
        }
        get(h, fresh);
        get(h, entry);
        load(h, entry_base);
        get(h, length);
        get(h, 2);
        op(h, blot_direct_writer::OP_i32_mul);
        memoryCopy(h);
        get(h, capacity);
        k(h, heap_flag);
        op(h, blot_direct_writer::OP_i32_and);
        k(h, 0);
        op(h, blot_direct_writer::OP_i32_ne);
        get(h, capacity);
        k(h, capacity_mask);
        op(h, blot_direct_writer::OP_i32_and);
        k(h, 0);
        op(h, blot_direct_writer::OP_i32_ne);
        op(h, blot_direct_writer::OP_i32_and);
        if has_fork {
            emitMustUndo(h, r, 0);
            op(h, blot_direct_writer::OP_i32_eqz);
            op(h, blot_direct_writer::OP_i32_and);
        }
        open(h, blot_direct_writer::OP_if_);
        get(h, entry);
        load(h, entry_base);
        get(h, capacity);
        k(h, capacity_mask);
        op(h, blot_direct_writer::OP_i32_and);
        call(h, r.heap_free);
        op(h, blot_direct_writer::OP_end);
        get(h, entry);
        get(h, fresh);
        store(h, entry_base);
        get(h, entry);
        get(h, size);
        k(h, heap_flag | live_flag);
        op(h, blot_direct_writer::OP_i32_or);
        store(h, entry_capacity);
        op(h, blot_direct_writer::OP_end);
        get(h, entry);
        get(h, length);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_add);
        store(h, entry_length);
        get(h, entry);
        load(h, entry_base);
        get(h, length);
        get(h, 2);
        op(h, blot_direct_writer::OP_i32_mul);
        op(h, blot_direct_writer::OP_i32_add);
        finish(h, module, r.push);
    }

    // pop(slot, generation, stride) -> address of the removed element.
    {
        var h = H { parameters: 3, locals: 3, .. };
        let entry = temp(h);
        let length = temp(h);
        get(h, 0);
        get(h, 1);
        call(h, r.check);
        tee(h, entry);
        load(h, entry_capacity);
        k(h, frozen_flag);
        op(h, blot_direct_writer::OP_i32_and);
        trapIf(h);
        get(h, entry);
        load(h, entry_length);
        tee(h, length);
        op(h, blot_direct_writer::OP_i32_eqz);
        trapIf(h);
        if has_fork {
            emitMustUndo(h, r, 0);
            open(h, blot_direct_writer::OP_if_);
            get(h, entry);
            k(h, entry_length);
            op(h, blot_direct_writer::OP_i32_add);
            k(h, 4);
            call(h, r.undo_record);
            op(h, blot_direct_writer::OP_end);
        }
        get(h, entry);
        get(h, length);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_sub);
        tee(h, length);
        store(h, entry_length);
        get(h, entry);
        load(h, entry_base);
        get(h, length);
        get(h, 2);
        op(h, blot_direct_writer::OP_i32_mul);
        op(h, blot_direct_writer::OP_i32_add);
        finish(h, module, r.pop);
    }

    // truncate(slot, generation, count)
    {
        var h = H { parameters: 3, locals: 3, .. };
        let entry = temp(h);
        get(h, 0);
        get(h, 1);
        call(h, r.check);
        tee(h, entry);
        load(h, entry_capacity);
        k(h, frozen_flag);
        op(h, blot_direct_writer::OP_i32_and);
        trapIf(h);
        get(h, 2);
        get(h, entry);
        load(h, entry_length);
        op(h, blot_direct_writer::OP_i32_gt_u);
        trapIf(h);
        if has_fork {
            emitMustUndo(h, r, 0);
            open(h, blot_direct_writer::OP_if_);
            get(h, entry);
            k(h, entry_length);
            op(h, blot_direct_writer::OP_i32_add);
            k(h, 4);
            call(h, r.undo_record);
            op(h, blot_direct_writer::OP_end);
        }
        get(h, entry);
        get(h, 2);
        store(h, entry_length);
        finish(h, module, r.truncate);
    }

    // freeze(slot, generation)
    {
        var h = H { parameters: 2, locals: 2, .. };
        let entry = temp(h);
        get(h, 0);
        get(h, 1);
        call(h, r.check);
        tee(h, entry);
        if has_fork {
            emitMustUndo(h, r, 0);
            open(h, blot_direct_writer::OP_if_);
            get(h, entry);
            k(h, entry_capacity);
            op(h, blot_direct_writer::OP_i32_add);
            k(h, 4);
            call(h, r.undo_record);
            op(h, blot_direct_writer::OP_end);
        }
        get(h, entry);
        load(h, entry_capacity);
        k(h, frozen_flag);
        op(h, blot_direct_writer::OP_i32_or);
        store(h, entry_capacity);
        finish(h, module, r.freeze);
    }

    // create(length, stride, growable) -> (slot, generation), zeroed, reserve-slot-first.
    {
        var h = H { parameters: 3, locals: 3, .. };
        let bytes = temp(h);
        let slot = temp(h);
        let gen = temp(h);
        let address = temp(h);
        let size = temp(h);
        let blk = temp(h);
        let entry = temp(h);
        get(h, 0);
        k(h, 0x04000000);
        op(h, blot_direct_writer::OP_i32_gt_u);
        trapIf(h);
        get(h, 0);
        get(h, 1);
        op(h, blot_direct_writer::OP_i32_mul);
        set(h, bytes);
        get(h, 2);
        open(h, blot_direct_writer::OP_if_);
        get(h, bytes);
        get(h, 0);
        call(h, r.open_heap);
        set(h, size);
        set(h, address);
        set(h, gen);
        set(h, slot);
        op(h, blot_direct_writer::OP_else_);
        k(h, 0);
        k(h, 0);
        k(h, 0);
        call(h, r.open);
        set(h, gen);
        set(h, slot);
        get(h, bytes);
        call(h, r.stack);
        set(h, address);
        emitOwnerDirAddr(h, slot, ot);
        load(h, 0);
        set(h, blk);
        emitOwnerEntryFromBlock(h, blk, slot);
        tee(h, entry);
        get(h, address);
        store(h, entry_base);
        get(h, entry);
        get(h, 0);
        store(h, entry_length);
        get(h, entry);
        get(h, bytes);
        k(h, live_flag);
        op(h, blot_direct_writer::OP_i32_or);
        store(h, entry_capacity);
        op(h, blot_direct_writer::OP_end);
        get(h, address);
        k(h, 0);
        get(h, bytes);
        memoryFill(h);
        get(h, slot);
        get(h, gen);
        finish(h, module, r.create);
    }

    // copy(slot, generation, stride, growable) -> independent (slot, generation)
    {
        var h = H { parameters: 4, locals: 4, .. };
        let entry = temp(h);
        let slot = temp(h);
        let generation = temp(h);
        get(h, 0);
        get(h, 1);
        call(h, r.check);
        tee(h, entry);
        load(h, entry_length);
        get(h, 2);
        get(h, 3);
        call(h, r.create);
        set(h, generation);
        set(h, slot);
        get(h, slot);
        get(h, generation);
        call(h, r.check);
        load(h, entry_base);
        get(h, entry);
        load(h, entry_base);
        get(h, entry);
        load(h, entry_length);
        get(h, 2);
        op(h, blot_direct_writer::OP_i32_mul);
        memoryCopy(h);
        get(h, slot);
        get(h, generation);
        finish(h, module, r.copy);
    }

    // persist(slot, generation, stride, mode) -> persistent copy, reserve-slot-first.
    // mode: 0 = non-growable mutable/not deeply immutable (live_flag),
    //       1 = growable on rt.heap (heap_flag | live_flag),
    //       2 = non-growable deeply-immutable static const pool (frozen_flag | static_pool_flag | live_flag).
    {
        var h = H { parameters: 4, locals: 4, .. };
        let entry = temp(h);
        let length = temp(h);
        let bytes = temp(h);
        let p_slot = temp(h);
        let p_gen = temp(h);
        let address = temp(h);
        let size = temp(h);
        let blk = temp(h);
        let p_entry = temp(h);
        get(h, 0);
        get(h, 1);
        call(h, r.check);
        tee(h, entry);
        load(h, entry_length);
        tee(h, length);
        get(h, 2);
        op(h, blot_direct_writer::OP_i32_mul);
        set(h, bytes);
        k(h, 0);
        k(h, 0);
        k(h, 0);
        call(h, r.open_persistent);
        set(h, p_gen);
        set(h, p_slot);
        get(h, 3);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_eq);
        open(h, blot_direct_writer::OP_if_);
        get(h, bytes);
        call(h, r.heap_alloc);
        set(h, size);
        set(h, address);
        get(h, size);
        k(h, heap_flag | live_flag);
        op(h, blot_direct_writer::OP_i32_or);
        set(h, size);
        op(h, blot_direct_writer::OP_else_);
        get(h, bytes);
        call(h, r.alloc_persistent);
        set(h, address);
        get(h, 3);
        k(h, 2);
        op(h, blot_direct_writer::OP_i32_eq);
        open(h, blot_direct_writer::OP_if_);
        get(h, bytes);
        k(h, frozen_flag | static_pool_flag | live_flag);
        op(h, blot_direct_writer::OP_i32_or);
        set(h, size);
        op(h, blot_direct_writer::OP_else_);
        get(h, bytes);
        k(h, live_flag);
        op(h, blot_direct_writer::OP_i32_or);
        set(h, size);
        op(h, blot_direct_writer::OP_end);
        op(h, blot_direct_writer::OP_end);
        get(h, address);
        get(h, entry);
        load(h, entry_base);
        get(h, bytes);
        memoryCopy(h);
        emitOwnerDirAddr(h, p_slot, ot);
        load(h, 0);
        set(h, blk);
        emitOwnerEntryFromBlock(h, blk, p_slot);
        tee(h, p_entry);
        get(h, address);
        store(h, entry_base);
        get(h, p_entry);
        get(h, length);
        store(h, entry_length);
        get(h, p_entry);
        get(h, size);
        store(h, entry_capacity);
        get(h, p_slot);
        get(h, p_gen);
        finish(h, module, r.persist);
    }

    // Host transport: allocate(bytes) -> zeroed packet address; grows via dedicated transport pool
    // preserving callback `used != 0` prefix bytes when growing without an intervening reset.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let address = temp(h);
        let used = temp(h);
        let need = temp(h);
        let new_base = temp(h);
        let new_cap = temp(h);
        let want = temp(h);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_eqz);
        get(h, 0);
        k(h, 3);
        op(h, blot_direct_writer::OP_i32_and);
        op(h, blot_direct_writer::OP_i32_or);
        trapIf(h);
        gget(h, r.transport_top);
        gget(h, r.transport_base);
        op(h, blot_direct_writer::OP_i32_sub);
        set(h, used);
        get(h, 0);
        k(h, transport_budget);
        get(h, used);
        op(h, blot_direct_writer::OP_i32_sub);
        op(h, blot_direct_writer::OP_i32_gt_u);
        trapIf(h);
        get(h, used);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_add);
        tee(h, need);
        gget(h, r.transport_cap);
        op(h, blot_direct_writer::OP_i32_gt_u);
        open(h, blot_direct_writer::OP_if_);
        var default_init: u32 = 4096;
        if default_init > transport_budget { default_init = transport_budget; }
        get(h, need);
        k(h, default_init);
        get(h, need);
        k(h, default_init);
        op(h, blot_direct_writer::OP_i32_gt_u);
        op(h, blot_direct_writer::OP_select);
        set(h, want);
        get(h, want);
        call(h, r.alloc_transport);
        set(h, new_cap);
        set(h, new_base);
        gget(h, r.transport_cap);
        open(h, blot_direct_writer::OP_if_);
        get(h, used);
        open(h, blot_direct_writer::OP_if_);
        get(h, new_base);
        gget(h, r.transport_base);
        get(h, used);
        memoryCopy(h);
        op(h, blot_direct_writer::OP_end);
        gget(h, r.transport_base);
        gget(h, r.transport_cap);
        call(h, r.free_transport);
        op(h, blot_direct_writer::OP_end);
        get(h, new_base);
        gset(h, r.transport_base);
        get(h, new_cap);
        gset(h, r.transport_cap);
        get(h, new_base);
        get(h, used);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.transport_top);
        op(h, blot_direct_writer::OP_end);
        gget(h, r.transport_top);
        tee(h, address);
        k(h, 0);
        get(h, 0);
        memoryFill(h);
        get(h, address);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.transport_top);
        get(h, address);
        finish(h, module, r.allocate);
    }

    // reset(ignored) -> 0: zero arena_oom_flag and release active transport bank back to transport_free_lists.
    {
        var h = H { parameters: 1, locals: 1, .. };
        k(h, layout.arena_oom_offset);
        k(h, 0);
        store(h, 0);
        gget(h, r.transport_cap);
        open(h, blot_direct_writer::OP_if_);
        gget(h, r.transport_base);
        gget(h, r.transport_cap);
        call(h, r.free_transport);
        k(h, 0);
        gset(h, r.transport_base);
        k(h, 0);
        gset(h, r.transport_cap);
        k(h, 0);
        gset(h, r.transport_top);
        op(h, blot_direct_writer::OP_end);
        k(h, 0);
        finish(h, module, r.reset);
    }

    // packet_length(address): checked word count of a host packet bounded by exact `transport_top`.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let end = temp(h);
        let length = temp(h);
        gget(h, r.transport_cap);
        op(h, blot_direct_writer::OP_i32_eqz);
        trapIf(h);
        gget(h, r.transport_top);
        set(h, end);
        get(h, end);
        k(h, 4);
        op(h, blot_direct_writer::OP_i32_lt_u);
        get(h, 0);
        gget(h, r.transport_base);
        op(h, blot_direct_writer::OP_i32_lt_u);
        op(h, blot_direct_writer::OP_i32_or);
        get(h, 0);
        k(h, 3);
        op(h, blot_direct_writer::OP_i32_and);
        op(h, blot_direct_writer::OP_i32_or);
        get(h, 0);
        get(h, end);
        k(h, 4);
        op(h, blot_direct_writer::OP_i32_sub);
        op(h, blot_direct_writer::OP_i32_gt_u);
        op(h, blot_direct_writer::OP_i32_or);
        trapIf(h);
        get(h, 0);
        load(h, 0);
        tee(h, length);
        get(h, end);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_sub);
        k(h, 4);
        op(h, blot_direct_writer::OP_i32_sub);
        k(h, 2);
        op(h, blot_direct_writer::OP_i32_shr_u);
        op(h, blot_direct_writer::OP_i32_gt_u);
        trapIf(h);
        get(h, length);
        finish(h, module, r.packet_length);
    }

    if has_persistent_state {
        // free_persistent(slot, gen): free heap backing if any, clear entry, bump gen;
        // permanently retire slot if next_gen wraps to 0.
        {
            var h = H { parameters: 2, locals: 2, .. };
            let entry = temp(h);
            let cap = temp(h);
            let base = temp(h);
            let next_gen = temp(h);
            get(h, 0);
            k(h, layout.persistent_split);
            op(h, blot_direct_writer::OP_i32_lt_u);
            trapIf(h);
            get(h, 0);
            get(h, 1);
            call(h, r.check);
            tee(h, entry);
            load(h, entry_capacity);
            tee(h, cap);
            k(h, static_pool_flag);
            op(h, blot_direct_writer::OP_i32_and);
            trapIf(h);
            get(h, entry);
            load(h, entry_base);
            set(h, base);
            get(h, entry);
            k(h, 0);
            store(h, entry_base);
            get(h, entry);
            k(h, 0);
            store(h, entry_length);
            get(h, entry);
            k(h, 0);
            store(h, entry_capacity);
            get(h, cap);
            k(h, heap_flag);
            op(h, blot_direct_writer::OP_i32_and);
            open(h, blot_direct_writer::OP_if_);
            get(h, base);
            get(h, cap);
            k(h, capacity_mask);
            op(h, blot_direct_writer::OP_i32_and);
            call(h, r.heap_free);
            op(h, blot_direct_writer::OP_end);
            get(h, 1);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_add);
            tee(h, next_gen);
            get(h, entry);
            get(h, next_gen);
            store(h, entry_generation);
            open(h, blot_direct_writer::OP_if_);
            get(h, entry);
            gget(h, r.persistent_free_head);
            store(h, entry_base);
            get(h, 0);
            gset(h, r.persistent_free_head);
            gget(h, r.persistent_free_count);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_add);
            gset(h, r.persistent_free_count);
            op(h, blot_direct_writer::OP_end);
            finish(h, module, r.free_persistent);
        }

        // ensure_persistent_slots(needed): pre-allocate owner directory blocks so Phase 2 commit is trap-free.
        {
            var h = H { parameters: 1, locals: 1, .. };
            let fresh = temp(h);
            let end_slot = temp(h);
            let block_idx = temp(h);
            let last_block = temp(h);
            let dir = temp(h);
            get(h, 0);
            gget(h, r.persistent_free_count);
            op(h, blot_direct_writer::OP_i32_le_u);
            open(h, blot_direct_writer::OP_if_);
            op(h, blot_direct_writer::OP_return_);
            op(h, blot_direct_writer::OP_end);
            get(h, 0);
            gget(h, r.persistent_free_count);
            op(h, blot_direct_writer::OP_i32_sub);
            set(h, fresh);
            gget(h, r.persistent_bottom);
            get(h, fresh);
            op(h, blot_direct_writer::OP_i32_add);
            tee(h, end_slot);
            gget(h, r.persistent_bottom);
            op(h, blot_direct_writer::OP_i32_lt_u);
            get(h, end_slot);
            k(h, layout.owner_capacity);
            op(h, blot_direct_writer::OP_i32_gt_u);
            op(h, blot_direct_writer::OP_i32_or);
            trapIf(h);
            gget(h, r.persistent_bottom);
            k(h, 8);
            op(h, blot_direct_writer::OP_i32_shr_u);
            set(h, block_idx);
            get(h, end_slot);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_sub);
            k(h, 8);
            op(h, blot_direct_writer::OP_i32_shr_u);
            set(h, last_block);
            open(h, blot_direct_writer::OP_block);
            open(h, blot_direct_writer::OP_loop);
            get(h, block_idx);
            get(h, last_block);
            op(h, blot_direct_writer::OP_i32_gt_u);
            idx(h, blot_direct_writer::OP_br_if, 1);
            get(h, block_idx);
            k(h, 2);
            op(h, blot_direct_writer::OP_i32_shl);
            k(h, ot);
            op(h, blot_direct_writer::OP_i32_add);
            tee(h, dir);
            load(h, 0);
            op(h, blot_direct_writer::OP_i32_eqz);
            open(h, blot_direct_writer::OP_if_);
            get(h, dir);
            k(h, owner_block_bytes);
            call(h, r.alloc_raw);
            store(h, 0);
            op(h, blot_direct_writer::OP_end);
            get(h, block_idx);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_add);
            set(h, block_idx);
            idx(h, blot_direct_writer::OP_br, 0);
            op(h, blot_direct_writer::OP_end);
            op(h, blot_direct_writer::OP_end);
            finish(h, module, r.ensure_persistent_slots);
        }

        // is_stack_range(ptr, logical_bytes) -> 1 if [ptr, ptr + logical_bytes) lies inside active stack chunks.
        {
            var h = H { parameters: 2, locals: 2, .. };
            let end = temp(h);
            let cur = temp(h);
            let used = temp(h);
            gget(h, r.stack_chunk);
            tee(h, cur);
            op(h, blot_direct_writer::OP_i32_eqz);
            open(h, blot_direct_writer::OP_if_);
            k(h, 0);
            op(h, blot_direct_writer::OP_return_);
            op(h, blot_direct_writer::OP_end);
            get(h, 0);
            get(h, 1);
            op(h, blot_direct_writer::OP_i32_add);
            tee(h, end);
            get(h, 0);
            op(h, blot_direct_writer::OP_i32_lt_u);
            open(h, blot_direct_writer::OP_if_);
            k(h, 0);
            op(h, blot_direct_writer::OP_return_);
            op(h, blot_direct_writer::OP_end);
            gget(h, r.stack_pointer);
            set(h, used);
            open(h, blot_direct_writer::OP_block);
            open(h, blot_direct_writer::OP_loop);
            get(h, cur);
            op(h, blot_direct_writer::OP_i32_eqz);
            idx(h, blot_direct_writer::OP_br_if, 1);
            get(h, 0);
            get(h, cur);
            k(h, stack_header_bytes);
            op(h, blot_direct_writer::OP_i32_add);
            op(h, blot_direct_writer::OP_i32_ge_u);
            get(h, end);
            get(h, used);
            op(h, blot_direct_writer::OP_i32_le_u);
            op(h, blot_direct_writer::OP_i32_and);
            open(h, blot_direct_writer::OP_if_);
            k(h, 1);
            op(h, blot_direct_writer::OP_return_);
            op(h, blot_direct_writer::OP_end);
            get(h, cur);
            load(h, 0);
            tee(h, cur);
            open(h, blot_direct_writer::OP_if_);
            get(h, cur);
            load(h, 16);
            set(h, used);
            op(h, blot_direct_writer::OP_end);
            idx(h, blot_direct_writer::OP_br, 0);
            op(h, blot_direct_writer::OP_end);
            op(h, blot_direct_writer::OP_end);
            k(h, 0);
            finish(h, module, r.is_stack_range);
        }

        // record_static_block(addr, logical_bytes, ty_id): appends 3-word entry at Wasm start.
        {
            var h = H { parameters: 3, locals: 3, .. };
            let new_cap = temp(h);
            let new_ptr = temp(h);
            let dst = temp(h);
            gget(h, r.static_blocks_len);
            gget(h, r.static_blocks_cap);
            op(h, blot_direct_writer::OP_i32_ge_u);
            open(h, blot_direct_writer::OP_if_);
            gget(h, r.static_blocks_cap);
            open(h, blot_direct_writer::OP_if_);
            gget(h, r.static_blocks_cap);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_shl);
            set(h, new_cap);
            op(h, blot_direct_writer::OP_else_);
            k(h, 16);
            set(h, new_cap);
            op(h, blot_direct_writer::OP_end);
            get(h, new_cap);
            k(h, 12);
            op(h, blot_direct_writer::OP_i32_mul);
            call(h, r.alloc_raw);
            set(h, new_ptr);
            gget(h, r.static_blocks_len);
            open(h, blot_direct_writer::OP_if_);
            get(h, new_ptr);
            gget(h, r.static_blocks_ptr);
            gget(h, r.static_blocks_len);
            k(h, 12);
            op(h, blot_direct_writer::OP_i32_mul);
            memoryCopy(h);
            op(h, blot_direct_writer::OP_end);
            get(h, new_ptr);
            gset(h, r.static_blocks_ptr);
            get(h, new_cap);
            gset(h, r.static_blocks_cap);
            op(h, blot_direct_writer::OP_end);
            gget(h, r.static_blocks_ptr);
            gget(h, r.static_blocks_len);
            k(h, 12);
            op(h, blot_direct_writer::OP_i32_mul);
            op(h, blot_direct_writer::OP_i32_add);
            tee(h, dst);
            get(h, 0);
            store(h, 0);
            get(h, dst);
            get(h, 1);
            store(h, 4);
            get(h, dst);
            get(h, 2);
            store(h, 8);
            gget(h, r.static_blocks_len);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_add);
            gset(h, r.static_blocks_len);
            finish(h, module, r.record_static_block);
        }

        // open_vec(init_bytes) -> slot: opens a temp heap-backed scratch vector (len = 0).
        {
            var h = H { parameters: 1, locals: 1, .. };
            let slot = temp(h);
            get(h, 0);
            k(h, 0);
            call(h, r.open_heap);
            op(h, blot_direct_writer::OP_drop);
            op(h, blot_direct_writer::OP_drop);
            op(h, blot_direct_writer::OP_drop);
            set(h, slot);
            get(h, slot);
            finish(h, module, r.open_vec);
        }

        // scratch_push(slot, elem_bytes) -> dst_addr: appends 1 element of `elem_bytes` to temp heap vector.
        {
            var h = H { parameters: 2, locals: 2, .. };
            let blk = temp(h);
            let entry = temp(h);
            let len = temp(h);
            let cap = temp(h);
            let need = temp(h);
            let dbl = temp(h);
            let new_base = temp(h);
            let new_cap = temp(h);
            let old_base = temp(h);
            emitOwnerDirAddr(h, 0, ot);
            load(h, 0);
            set(h, blk);
            emitOwnerEntryFromBlock(h, blk, 0);
            tee(h, entry);
            load(h, entry_length);
            set(h, len);
            get(h, entry);
            load(h, entry_capacity);
            k(h, capacity_mask);
            op(h, blot_direct_writer::OP_i32_and);
            set(h, cap);
            get(h, len);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_add);
            get(h, 1);
            op(h, blot_direct_writer::OP_i32_mul);
            tee(h, need);
            get(h, cap);
            op(h, blot_direct_writer::OP_i32_gt_u);
            open(h, blot_direct_writer::OP_if_);
            get(h, cap);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_shl);
            set(h, dbl);
            get(h, need);
            get(h, dbl);
            get(h, need);
            get(h, dbl);
            op(h, blot_direct_writer::OP_i32_gt_u);
            op(h, blot_direct_writer::OP_select);
            call(h, r.heap_alloc);
            set(h, new_cap);
            set(h, new_base);
            get(h, entry);
            load(h, entry_base);
            set(h, old_base);
            get(h, new_base);
            get(h, old_base);
            get(h, len);
            get(h, 1);
            op(h, blot_direct_writer::OP_i32_mul);
            memoryCopy(h);
            get(h, old_base);
            get(h, cap);
            call(h, r.heap_free);
            get(h, entry);
            get(h, new_base);
            store(h, entry_base);
            get(h, entry);
            get(h, new_cap);
            k(h, heap_flag | live_flag);
            op(h, blot_direct_writer::OP_i32_or);
            store(h, entry_capacity);
            op(h, blot_direct_writer::OP_end);
            get(h, entry);
            get(h, len);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_add);
            store(h, entry_length);
            get(h, entry);
            load(h, entry_base);
            get(h, len);
            get(h, 1);
            op(h, blot_direct_writer::OP_i32_mul);
            op(h, blot_direct_writer::OP_i32_add);
            finish(h, module, r.scratch_push);
        }

        // open_hmap() -> slot: opens a 16-bucket (256-byte) zeroed open-addressed hash table on rt.heap.
        {
            var h = H { parameters: 0, locals: 0, .. };
            let slot = temp(h);
            let base = temp(h);
            k(h, 256);
            k(h, 0);
            call(h, r.open_heap);
            op(h, blot_direct_writer::OP_drop);
            set(h, base);
            op(h, blot_direct_writer::OP_drop);
            set(h, slot);
            get(h, base);
            k(h, 0);
            k(h, 256);
            memoryFill(h);
            get(h, slot);
            finish(h, module, r.open_hmap);
        }

        // hmap_get(map_slot, k0, k1, k2) -> (val, found): O(1) lookup (k0 != 0 invariant).
        {
            var h = H { parameters: 4, locals: 4, .. };
            let blk = temp(h);
            let entry = temp(h);
            let base = temp(h);
            let mask = temp(h);
            let idx_loc = temp(h);
            let cell = temp(h);
            let ck0 = temp(h);
            emitOwnerDirAddr(h, 0, ot);
            load(h, 0);
            set(h, blk);
            emitOwnerEntryFromBlock(h, blk, 0);
            tee(h, entry);
            load(h, entry_base);
            set(h, base);
            get(h, entry);
            load(h, entry_capacity);
            k(h, capacity_mask);
            op(h, blot_direct_writer::OP_i32_and);
            k(h, 4);
            op(h, blot_direct_writer::OP_i32_shr_u);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_sub);
            set(h, mask);
            get(h, 1);
            k(h, 0x9e3779b1);
            op(h, blot_direct_writer::OP_i32_mul);
            get(h, 2);
            k(h, 0x85ebca77);
            op(h, blot_direct_writer::OP_i32_mul);
            op(h, blot_direct_writer::OP_i32_xor);
            get(h, 3);
            k(h, 0xc2b2ae3d);
            op(h, blot_direct_writer::OP_i32_mul);
            op(h, blot_direct_writer::OP_i32_xor);
            get(h, mask);
            op(h, blot_direct_writer::OP_i32_and);
            set(h, idx_loc);
            open(h, blot_direct_writer::OP_block);
            open(h, blot_direct_writer::OP_loop);
            get(h, base);
            get(h, idx_loc);
            k(h, 4);
            op(h, blot_direct_writer::OP_i32_shl);
            op(h, blot_direct_writer::OP_i32_add);
            tee(h, cell);
            load(h, 0);
            tee(h, ck0);
            op(h, blot_direct_writer::OP_i32_eqz);
            idx(h, blot_direct_writer::OP_br_if, 1);
            get(h, ck0);
            get(h, 1);
            op(h, blot_direct_writer::OP_i32_eq);
            get(h, cell);
            load(h, 4);
            get(h, 2);
            op(h, blot_direct_writer::OP_i32_eq);
            op(h, blot_direct_writer::OP_i32_and);
            get(h, cell);
            load(h, 8);
            get(h, 3);
            op(h, blot_direct_writer::OP_i32_eq);
            op(h, blot_direct_writer::OP_i32_and);
            open(h, blot_direct_writer::OP_if_);
            get(h, cell);
            load(h, 12);
            k(h, 1);
            op(h, blot_direct_writer::OP_return_);
            op(h, blot_direct_writer::OP_end);
            get(h, idx_loc);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_add);
            get(h, mask);
            op(h, blot_direct_writer::OP_i32_and);
            set(h, idx_loc);
            idx(h, blot_direct_writer::OP_br, 0);
            op(h, blot_direct_writer::OP_end);
            op(h, blot_direct_writer::OP_end);
            k(h, 0);
            k(h, 0);
            finish(h, module, r.hmap_get);
        }

        // hmap_put(map_slot, k0, k1, k2, val): O(1) amortized insert/overwrite with 2x rehash.
        {
            var h = H { parameters: 5, locals: 5, .. };
            let blk = temp(h);
            let entry = temp(h);
            let old_base = temp(h);
            let old_cap = temp(h);
            let count = temp(h);
            let buckets = temp(h);
            let new_base = temp(h);
            let new_cap = temp(h);
            let new_mask = temp(h);
            let ri = temp(h);
            let src = temp(h);
            let rk0 = temp(h);
            let rk1 = temp(h);
            let rk2 = temp(h);
            let rval = temp(h);
            let pidx = temp(h);
            let dst = temp(h);
            emitOwnerDirAddr(h, 0, ot);
            load(h, 0);
            set(h, blk);
            emitOwnerEntryFromBlock(h, blk, 0);
            tee(h, entry);
            load(h, entry_length);
            set(h, count);
            get(h, entry);
            load(h, entry_capacity);
            k(h, capacity_mask);
            op(h, blot_direct_writer::OP_i32_and);
            tee(h, old_cap);
            k(h, 4);
            op(h, blot_direct_writer::OP_i32_shr_u);
            set(h, buckets);
            // Rehash if (count + 1) * 2 > buckets.
            get(h, count);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_add);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_shl);
            get(h, buckets);
            op(h, blot_direct_writer::OP_i32_gt_u);
            open(h, blot_direct_writer::OP_if_);
            get(h, old_cap);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_shl);
            call(h, r.heap_alloc);
            set(h, new_cap);
            set(h, new_base);
            get(h, new_base);
            k(h, 0);
            get(h, new_cap);
            memoryFill(h);
            get(h, new_cap);
            k(h, 4);
            op(h, blot_direct_writer::OP_i32_shr_u);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_sub);
            set(h, new_mask);
            get(h, entry);
            load(h, entry_base);
            set(h, old_base);
            k(h, 0);
            set(h, ri);
            open(h, blot_direct_writer::OP_block);
            open(h, blot_direct_writer::OP_loop);
            get(h, ri);
            get(h, buckets);
            op(h, blot_direct_writer::OP_i32_ge_u);
            idx(h, blot_direct_writer::OP_br_if, 1);
            get(h, old_base);
            get(h, ri);
            k(h, 4);
            op(h, blot_direct_writer::OP_i32_shl);
            op(h, blot_direct_writer::OP_i32_add);
            tee(h, src);
            load(h, 0);
            tee(h, rk0);
            open(h, blot_direct_writer::OP_if_);
            get(h, src);
            load(h, 4);
            set(h, rk1);
            get(h, src);
            load(h, 8);
            set(h, rk2);
            get(h, src);
            load(h, 12);
            set(h, rval);
            get(h, rk0);
            k(h, 0x9e3779b1);
            op(h, blot_direct_writer::OP_i32_mul);
            get(h, rk1);
            k(h, 0x85ebca77);
            op(h, blot_direct_writer::OP_i32_mul);
            op(h, blot_direct_writer::OP_i32_xor);
            get(h, rk2);
            k(h, 0xc2b2ae3d);
            op(h, blot_direct_writer::OP_i32_mul);
            op(h, blot_direct_writer::OP_i32_xor);
            get(h, new_mask);
            op(h, blot_direct_writer::OP_i32_and);
            set(h, pidx);
            open(h, blot_direct_writer::OP_block);
            open(h, blot_direct_writer::OP_loop);
            get(h, new_base);
            get(h, pidx);
            k(h, 4);
            op(h, blot_direct_writer::OP_i32_shl);
            op(h, blot_direct_writer::OP_i32_add);
            tee(h, dst);
            load(h, 0);
            op(h, blot_direct_writer::OP_i32_eqz);
            open(h, blot_direct_writer::OP_if_);
            get(h, dst);
            get(h, rk0);
            store(h, 0);
            get(h, dst);
            get(h, rk1);
            store(h, 4);
            get(h, dst);
            get(h, rk2);
            store(h, 8);
            get(h, dst);
            get(h, rval);
            store(h, 12);
            idx(h, blot_direct_writer::OP_br, 2);
            op(h, blot_direct_writer::OP_end);
            get(h, pidx);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_add);
            get(h, new_mask);
            op(h, blot_direct_writer::OP_i32_and);
            set(h, pidx);
            idx(h, blot_direct_writer::OP_br, 0);
            op(h, blot_direct_writer::OP_end);
            op(h, blot_direct_writer::OP_end);
            op(h, blot_direct_writer::OP_end);
            get(h, ri);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_add);
            set(h, ri);
            idx(h, blot_direct_writer::OP_br, 0);
            op(h, blot_direct_writer::OP_end);
            op(h, blot_direct_writer::OP_end);
            get(h, old_base);
            get(h, old_cap);
            call(h, r.heap_free);
            get(h, entry);
            get(h, new_base);
            store(h, entry_base);
            get(h, entry);
            get(h, new_cap);
            k(h, heap_flag | live_flag);
            op(h, blot_direct_writer::OP_i32_or);
            store(h, entry_capacity);
            op(h, blot_direct_writer::OP_end);
            // Insert or overwrite (k0, k1, k2, val).
            get(h, entry);
            load(h, entry_base);
            set(h, new_base);
            get(h, entry);
            load(h, entry_capacity);
            k(h, capacity_mask);
            op(h, blot_direct_writer::OP_i32_and);
            k(h, 4);
            op(h, blot_direct_writer::OP_i32_shr_u);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_sub);
            set(h, new_mask);
            get(h, 1);
            k(h, 0x9e3779b1);
            op(h, blot_direct_writer::OP_i32_mul);
            get(h, 2);
            k(h, 0x85ebca77);
            op(h, blot_direct_writer::OP_i32_mul);
            op(h, blot_direct_writer::OP_i32_xor);
            get(h, 3);
            k(h, 0xc2b2ae3d);
            op(h, blot_direct_writer::OP_i32_mul);
            op(h, blot_direct_writer::OP_i32_xor);
            get(h, new_mask);
            op(h, blot_direct_writer::OP_i32_and);
            set(h, pidx);
            open(h, blot_direct_writer::OP_block);
            open(h, blot_direct_writer::OP_loop);
            get(h, new_base);
            get(h, pidx);
            k(h, 4);
            op(h, blot_direct_writer::OP_i32_shl);
            op(h, blot_direct_writer::OP_i32_add);
            tee(h, dst);
            load(h, 0);
            tee(h, rk0);
            op(h, blot_direct_writer::OP_i32_eqz);
            open(h, blot_direct_writer::OP_if_);
            get(h, dst);
            get(h, 1);
            store(h, 0);
            get(h, dst);
            get(h, 2);
            store(h, 4);
            get(h, dst);
            get(h, 3);
            store(h, 8);
            get(h, dst);
            get(h, 4);
            store(h, 12);
            get(h, entry);
            get(h, count);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_add);
            store(h, entry_length);
            idx(h, blot_direct_writer::OP_br, 2);
            op(h, blot_direct_writer::OP_end);
            get(h, rk0);
            get(h, 1);
            op(h, blot_direct_writer::OP_i32_eq);
            get(h, dst);
            load(h, 4);
            get(h, 2);
            op(h, blot_direct_writer::OP_i32_eq);
            op(h, blot_direct_writer::OP_i32_and);
            get(h, dst);
            load(h, 8);
            get(h, 3);
            op(h, blot_direct_writer::OP_i32_eq);
            op(h, blot_direct_writer::OP_i32_and);
            open(h, blot_direct_writer::OP_if_);
            get(h, dst);
            get(h, 4);
            store(h, 12);
            idx(h, blot_direct_writer::OP_br, 2);
            op(h, blot_direct_writer::OP_end);
            get(h, pidx);
            k(h, 1);
            op(h, blot_direct_writer::OP_i32_add);
            get(h, new_mask);
            op(h, blot_direct_writer::OP_i32_and);
            set(h, pidx);
            idx(h, blot_direct_writer::OP_br, 0);
            op(h, blot_direct_writer::OP_end);
            op(h, blot_direct_writer::OP_end);
            finish(h, module, r.hmap_put);
        }
    }

    if has_fork {
        // undo_reserve(bytes): lazily allocate undo journal and verify `bytes` of headroom exist.
        {
            var h = H { parameters: 1, locals: 1, .. };
            let base = temp(h);
            let next = temp(h);
            gget(h, r.undo_base);
            op(h, blot_direct_writer::OP_i32_eqz);
            open(h, blot_direct_writer::OP_if_);
            k(h, undo_bytes);
            call(h, r.alloc_raw);
            tee(h, base);
            gset(h, r.undo_base);
            get(h, base);
            k(h, undo_bytes);
            op(h, blot_direct_writer::OP_i32_add);
            gset(h, r.undo_end);
            get(h, base);
            gset(h, r.undo_sp);
            op(h, blot_direct_writer::OP_end);
            gget(h, r.undo_sp);
            get(h, 0);
            op(h, blot_direct_writer::OP_i32_add);
            tee(h, next);
            gget(h, r.undo_end);
            op(h, blot_direct_writer::OP_i32_gt_u);
            get(h, next);
            gget(h, r.undo_sp);
            op(h, blot_direct_writer::OP_i32_lt_u);
            op(h, blot_direct_writer::OP_i32_or);
            trapIf(h);
            finish(h, module, r.undo_reserve);
        }
        // undo_record(addr, bytes): lazily allocate undo journal and save slice.
        {
            var h = H { parameters: 2, locals: 2, .. };
            let aligned = temp(h);
            let sp = temp(h);
            let next = temp(h);
            get(h, 1);
            k(h, 3);
            op(h, blot_direct_writer::OP_i32_add);
            k(h, 0xfffffffc);
            op(h, blot_direct_writer::OP_i32_and);
            tee(h, aligned);
            k(h, 8);
            op(h, blot_direct_writer::OP_i32_add);
            call(h, r.undo_reserve);
            gget(h, r.undo_sp);
            tee(h, sp);
            get(h, aligned);
            op(h, blot_direct_writer::OP_i32_add);
            k(h, 8);
            op(h, blot_direct_writer::OP_i32_add);
            set(h, next);
            get(h, sp);
            get(h, 0);
            get(h, 1);
            memoryCopy(h);
            get(h, sp);
            get(h, aligned);
            op(h, blot_direct_writer::OP_i32_add);
            get(h, 0);
            store(h, 0);
            get(h, sp);
            get(h, aligned);
            op(h, blot_direct_writer::OP_i32_add);
            get(h, 1);
            store(h, 4);
            get(h, next);
            gset(h, r.undo_sp);
            finish(h, module, r.undo_record);
        }
        // undo_rewind(saved_sp): LIFO restore every journaled slice and free realloc sentinels down to saved_sp.
        {
            var h = H { parameters: 1, locals: 1, .. };
            let target = temp(h);
            let sp = temp(h);
            let raw_bytes = temp(h);
            let addr = temp(h);
            let src = temp(h);
            gget(h, r.undo_base);
            op(h, blot_direct_writer::OP_i32_eqz);
            open(h, blot_direct_writer::OP_if_);
            op(h, blot_direct_writer::OP_return_);
            op(h, blot_direct_writer::OP_end);
            get(h, 0);
            gget(h, r.undo_base);
            get(h, 0);
            op(h, blot_direct_writer::OP_select);
            set(h, target);
            open(h, blot_direct_writer::OP_block);
            open(h, blot_direct_writer::OP_loop);
            gget(h, r.undo_sp);
            tee(h, sp);
            get(h, target);
            op(h, blot_direct_writer::OP_i32_le_u);
            idx(h, blot_direct_writer::OP_br_if, 1);
            get(h, sp);
            k(h, 4);
            op(h, blot_direct_writer::OP_i32_sub);
            load(h, 0);
            set(h, raw_bytes);
            get(h, sp);
            k(h, 8);
            op(h, blot_direct_writer::OP_i32_sub);
            load(h, 0);
            set(h, addr);
            get(h, raw_bytes);
            k(h, 0x80000000);
            op(h, blot_direct_writer::OP_i32_and);
            open(h, blot_direct_writer::OP_if_);
            get(h, sp);
            k(h, 8);
            op(h, blot_direct_writer::OP_i32_sub);
            gset(h, r.undo_sp);
            get(h, addr);
            get(h, raw_bytes);
            k(h, 0x7fffffff);
            op(h, blot_direct_writer::OP_i32_and);
            call(h, r.heap_free);
            op(h, blot_direct_writer::OP_else_);
            get(h, sp);
            k(h, 8);
            op(h, blot_direct_writer::OP_i32_sub);
            get(h, raw_bytes);
            k(h, 3);
            op(h, blot_direct_writer::OP_i32_add);
            k(h, 0xfffffffc);
            op(h, blot_direct_writer::OP_i32_and);
            op(h, blot_direct_writer::OP_i32_sub);
            set(h, src);
            get(h, addr);
            get(h, src);
            get(h, raw_bytes);
            memoryCopy(h);
            get(h, src);
            gset(h, r.undo_sp);
            op(h, blot_direct_writer::OP_end);
            idx(h, blot_direct_writer::OP_br, 0);
            op(h, blot_direct_writer::OP_end);
            op(h, blot_direct_writer::OP_end);
            finish(h, module, r.undo_rewind);
        }
    }

    module.has_memory = true;
    module.memory_pages = 1;
    module.memory_max_pages = (layout.total + 0xffff) / 0x10000;
    // Helper names for traces, in the order of the struct's fields.
    blot_direct_writer::setName(module, r.alloc_raw, "runtime.alloc_raw");
    blot_direct_writer::setName(module, r.open, "runtime.open");
    blot_direct_writer::setName(module, r.open_persistent, "runtime.open_persistent");
    blot_direct_writer::setName(module, r.open_heap, "runtime.open_heap");
    blot_direct_writer::setName(module, r.detach_temp_slot, "runtime.detach_temp_slot");
    blot_direct_writer::setName(module, r.release, "runtime.release");
    blot_direct_writer::setName(module, r.check, "runtime.check");
    blot_direct_writer::setName(module, r.stack, "runtime.stack");
    blot_direct_writer::setName(module, r.stack_slow, "runtime.stack_slow");
    blot_direct_writer::setName(module, r.rewind_stack, "runtime.rewind_stack");
    blot_direct_writer::setName(module, r.rewind_stack_slow, "runtime.rewind_stack_slow");
    blot_direct_writer::setName(module, r.heap_alloc, "runtime.heap_alloc");
    blot_direct_writer::setName(module, r.heap_free, "runtime.heap_free");
    blot_direct_writer::setName(module, r.alloc_transport, "runtime.alloc_transport");
    blot_direct_writer::setName(module, r.open_transport_pin, "runtime.open_transport_pin");
    blot_direct_writer::setName(module, r.free_transport, "runtime.free_transport");
    blot_direct_writer::setName(module, r.alloc_persistent, "runtime.alloc_persistent");
    blot_direct_writer::setName(module, r.address, "runtime.address");
    blot_direct_writer::setName(module, r.length, "runtime.length");
    blot_direct_writer::setName(module, r.push, "runtime.push");
    blot_direct_writer::setName(module, r.pop, "runtime.pop");
    blot_direct_writer::setName(module, r.truncate, "runtime.truncate");
    blot_direct_writer::setName(module, r.freeze, "runtime.freeze");
    blot_direct_writer::setName(module, r.create, "runtime.create");
    blot_direct_writer::setName(module, r.copy, "runtime.copy");
    blot_direct_writer::setName(module, r.persist, "runtime.persist");
    blot_direct_writer::setName(module, r.allocate, "runtime.allocate");
    blot_direct_writer::setName(module, r.reset, "runtime.reset");
    blot_direct_writer::setName(module, r.packet_length, "runtime.packet_length");
    if has_persistent_state {
        blot_direct_writer::setName(module, r.free_persistent, "runtime.free_persistent");
        blot_direct_writer::setName(module, r.ensure_persistent_slots, "runtime.ensure_persistent_slots");
        blot_direct_writer::setName(module, r.is_stack_range, "runtime.is_stack_range");
        blot_direct_writer::setName(module, r.record_static_block, "runtime.record_static_block");
        blot_direct_writer::setName(module, r.open_vec, "runtime.open_vec");
        blot_direct_writer::setName(module, r.scratch_push, "runtime.scratch_push");
        blot_direct_writer::setName(module, r.open_hmap, "runtime.open_hmap");
        blot_direct_writer::setName(module, r.hmap_get, "runtime.hmap_get");
        blot_direct_writer::setName(module, r.hmap_put, "runtime.hmap_put");
    }
    if has_fork {
        blot_direct_writer::setName(module, r.undo_reserve, "runtime.undo_reserve");
        blot_direct_writer::setName(module, r.undo_record, "runtime.undo_record");
        blot_direct_writer::setName(module, r.undo_rewind, "runtime.undo_rewind");
    }
    return r;
}
