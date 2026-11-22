// Storage runtime of the direct backend: a 2-level paged owner table of
// (base, length, capacity, generation) entries addressed by (slot, generation)
// handles, a chunk-list contiguous bump stack for fixed arrays and closure
// environments, a power-of-two free-list heap for growable storage, and
// on-demand transport/persistent/undo regions. Modules commit 1 Wasm page
// (64 KiB) initially and grow on demand via `memory.grow` up to the planned
// budget ceiling, reusing all chunks and free lists across invocations.
namespace blot_direct_runtime;
import std;
import direct.writer;

let entry_bytes: u32 = 16;
let entry_base: u32 = 0;
let entry_length: u32 = 4;
let entry_capacity: u32 = 8;
let entry_generation: u32 = 12;
// Capacity flags: growth authority removed; storage owned by the heap.
let frozen_flag: u32 = 0x80000000;
let heap_flag: u32 = 0x40000000;
let capacity_mask: u32 = 0x3fffffff;
// Speculative fork undo journal budget (2 MiB, allocated lazily only when a module executes `fork`).
let undo_bytes: u32 = 2097152;
// Fixed page-0 layout: [0..512) zero guard, [512..640) free lists,
// [1024..2048) 256-entry owner block directory, [2048..65536) initial arena.
let owner_block_bytes: u32 = 4096;
let arena_start: u32 = 2048;
let initial_page_bytes: u32 = 65536;
// Chunked stack sizing: starts at 16 KiB, doubles up to 256 KiB automatic chunks.
let stack_chunk_min: u32 = 16384;
let stack_chunk_max_auto: u32 = 262144;

// Defaults: 65536 owners, 4 MiB persistent, 16 MiB stack, 32 MiB heap, 2 MiB transport.
struct Budgets {
    owners: u32 = 65536,
    persistent: u32 = 4194304,
    stack: u32 = 16777216,
    heap: u32 = 33554432,
    transport: u32 = 2097152
}
struct Layout {
    free_lists: u32 = 512,
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
    let owner_table: u32 = 1024;
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
    owner_top: u32 = 0,
    persistent_bottom: u32 = 0,
    arena_top: u32 = 0,
    page_top: u32 = 0,
    stack_head: u32 = 0,
    stack_chunk: u32 = 0,
    stack_pointer: u32 = 0,
    stack_limit: u32 = 0,
    stack_total: u32 = 0,
    heap_top: u32 = 0,
    persistent_top: u32 = 0,
    transport_base: u32 = 0,
    transport_cap: u32 = 0,
    transport_top: u32 = 0,
    // The installed providers: the newest frame of
    // {operation id, closure slot, closure environment, previous frame}.
    effect_context: u32 = 0,
    // Speculative `fork` state: owner slots below `fork_owner_mark` predate
    // the active `fork` and journal writes onto `undo_sp`. Zero outside `fork`.
    fork_owner_mark: u32 = 0,
    fork_depth: u32 = 0,
    undo_base: u32 = 0,
    undo_end: u32 = 0,
    undo_sp: u32 = 0,
    alloc_raw: u32 = 0,
    open: u32 = 0,
    open_persistent: u32 = 0,
    release: u32 = 0,
    check: u32 = 0,
    stack: u32 = 0,
    stack_slow: u32 = 0,
    rewind_stack: u32 = 0,
    rewind_stack_slow: u32 = 0,
    heap_alloc: u32 = 0,
    heap_free: u32 = 0,
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
// Traps when the i32 on the stack is nonzero.
fn trapIf(h: H&) {
    op(h, blot_direct_writer::OP_if_);
    blot_direct_writer::byte(h.code, 0x40);
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

// A signature of `params` i32 parameters and `results` i32 results (at most four each).
fn sig(module: blot_direct_writer::Module&, params: i64, results: i64) -> u32 {
    let all: blot_direct_writer::ValType[4] = [blot_direct_writer::VT_i32; 4];
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

// open(base, length, capacity) -> (slot, generation)
fn emitOpen(module: blot_direct_writer::Module&, r: const Runtime&, function: u32, persistent: bool) {
    var h = H { parameters: 3, locals: 3, .. };
    let slot = temp(h);
    let dir = temp(h);
    let blk = temp(h);
    let entry = temp(h);
    if persistent {
        gget(h, r.persistent_bottom);
        tee(h, slot);
        k(h, r.layout.owner_capacity);
        op(h, blot_direct_writer::OP_i32_ge_u);
        trapIf(h);
    } else {
        gget(h, r.owner_top);
        tee(h, slot);
        k(h, r.layout.persistent_split);
        op(h, blot_direct_writer::OP_i32_ge_u);
        trapIf(h);
    }
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
    if persistent {
        get(h, slot);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.persistent_bottom);
    } else {
        get(h, slot);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.owner_top);
    }
    emitOwnerEntryFromBlock(h, blk, slot);
    set(h, entry);
    get(h, entry);
    get(h, 0);
    store(h, entry_base);
    get(h, entry);
    get(h, 1);
    store(h, entry_length);
    get(h, entry);
    get(h, 2);
    store(h, entry_capacity);
    get(h, slot);
    get(h, entry);
    load(h, entry_generation);
    finish(h, module, function);
}

// Emits the globals and helpers. Call before any other function is added
// only if imports are already declared (imports precede functions).
fn emit(module: blot_direct_writer::Module&, budgets: Budgets) -> Runtime {
    return emitWithFork(module, budgets, false);
}
fn emitWithFork(module: blot_direct_writer::Module&, budgets: Budgets, has_fork: bool) -> Runtime {
    let layout = initWithFork(budgets, has_fork);
    let i32t = blot_direct_writer::VT_i32;
    var r = Runtime { layout: layout, has_fork: has_fork, .. };
    r.owner_top = blot_direct_writer::addGlobal(module, i32t, true, 1);
    r.persistent_bottom = blot_direct_writer::addGlobal(module, i32t, true, layout.persistent_split);
    r.arena_top = blot_direct_writer::addGlobal(module, i32t, true, arena_start);
    r.page_top = blot_direct_writer::addGlobal(module, i32t, true, initial_page_bytes);
    r.stack_head = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.stack_chunk = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.stack_pointer = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.stack_limit = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.stack_total = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.heap_top = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.persistent_top = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.transport_base = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.transport_cap = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.transport_top = blot_direct_writer::addGlobal(module, i32t, true, 0);
    r.effect_context = blot_direct_writer::addGlobal(module, i32t, true, 0);
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
    r.release = helper(module, 1, 0);
    r.check = helper(module, 2, 1);
    r.stack = helper(module, 1, 1);
    r.stack_slow = helper(module, 1, 1);
    r.rewind_stack = helper(module, 1, 0);
    r.rewind_stack_slow = helper(module, 1, 0);
    r.heap_alloc = helper(module, 1, 2);
    r.heap_free = helper(module, 2, 0);
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
    if has_fork {
        r.undo_record = helper(module, 2, 0);
        r.undo_rewind = helper(module, 1, 0);
    }
    let ot = layout.owner_table;
    let stack_budget = layout.stack_end - layout.stack_base;
    let heap_budget = layout.heap_end - layout.heap_base;
    let persistent_budget = layout.persistent_end - layout.persistent_base;
    let transport_budget = layout.transport_end - layout.transport_base;

    // alloc_raw(bytes) -> 16-byte aligned address, growing Wasm pages on demand.
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
        trapIf(h);
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
        trapIf(h);
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

    // heap_free(address, size): push onto the size class's free list.
    {
        var h = H { parameters: 2, locals: 2, .. };
        let head = temp(h);
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
    // release(mark): every owner opened above mark is invalidated.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let slot = temp(h);
        let blk = temp(h);
        let entry = temp(h);
        let capacity = temp(h);
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
        get(h, entry);
        load(h, entry_generation);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_add);
        store(h, entry_generation);
        get(h, entry);
        load(h, entry_capacity);
        tee(h, capacity);
        k(h, heap_flag);
        op(h, blot_direct_writer::OP_i32_and);
        open(h, blot_direct_writer::OP_if_);
        get(h, entry);
        load(h, entry_base);
        get(h, capacity);
        k(h, capacity_mask);
        op(h, blot_direct_writer::OP_i32_and);
        call(h, r.heap_free);
        op(h, blot_direct_writer::OP_end);
        idx(h, blot_direct_writer::OP_br, 0);
        op(h, blot_direct_writer::OP_end);
        op(h, blot_direct_writer::OP_end);
        finish(h, module, r.release);
    }
    // check(slot, generation) -> entry; slot zero or unallocated block traps.
    {
        var h = H { parameters: 2, locals: 2, .. };
        let blk = temp(h);
        let entry = temp(h);
        get(h, 0);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_sub);
        k(h, layout.owner_capacity - 1);
        op(h, blot_direct_writer::OP_i32_ge_u);
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
        load(h, entry_generation);
        get(h, 1);
        op(h, blot_direct_writer::OP_i32_ne);
        trapIf(h);
        get(h, entry);
        finish(h, module, r.check);
    }
    // stack_slow(need) -> address: reuse a chained chunk or allocate a new one.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let cur = temp(h);
        let tail = temp(h);
        let result = temp(h);
        let prev_cap = temp(h);
        let grow = temp(h);
        let cap = temp(h);
        let chunk_bytes = temp(h);
        let chunk = temp(h);
        let limit = temp(h);
        gget(h, r.stack_chunk);
        tee(h, tail);
        open(h, blot_direct_writer::OP_if_);
        get(h, tail);
        load(h, 4);
        set(h, cur);
        op(h, blot_direct_writer::OP_else_);
        gget(h, r.stack_head);
        set(h, cur);
        op(h, blot_direct_writer::OP_end);
        open(h, blot_direct_writer::OP_block); // $found
        open(h, blot_direct_writer::OP_block); // $miss
        open(h, blot_direct_writer::OP_loop);  // $scan
        get(h, cur);
        op(h, blot_direct_writer::OP_i32_eqz);
        idx(h, blot_direct_writer::OP_br_if, 1); // -> $miss
        get(h, cur);
        load(h, 12);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_ge_u);
        open(h, blot_direct_writer::OP_if_);
        get(h, cur);
        gset(h, r.stack_chunk);
        get(h, cur);
        load(h, 8);
        gset(h, r.stack_limit);
        get(h, cur);
        k(h, 16);
        op(h, blot_direct_writer::OP_i32_add);
        tee(h, result);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.stack_pointer);
        idx(h, blot_direct_writer::OP_br, 3); // -> $found
        op(h, blot_direct_writer::OP_end);
        get(h, cur);
        set(h, tail);
        get(h, cur);
        load(h, 4);
        set(h, cur);
        idx(h, blot_direct_writer::OP_br, 0);
        op(h, blot_direct_writer::OP_end); // end $scan
        op(h, blot_direct_writer::OP_end); // end $miss
        // No existing chunk fits: compute cap = max(need, min(prev_cap * 2, 256 KiB)).
        get(h, tail);
        open(h, blot_direct_writer::OP_if_);
        get(h, tail);
        load(h, 12);
        set(h, prev_cap);
        op(h, blot_direct_writer::OP_else_);
        k(h, stack_chunk_min / 2);
        set(h, prev_cap);
        op(h, blot_direct_writer::OP_end);
        get(h, prev_cap);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_shl);
        tee(h, grow);
        k(h, stack_chunk_max_auto);
        get(h, grow);
        k(h, stack_chunk_max_auto);
        op(h, blot_direct_writer::OP_i32_lt_u);
        op(h, blot_direct_writer::OP_select);
        set(h, grow);
        get(h, 0);
        get(h, grow);
        get(h, 0);
        get(h, grow);
        op(h, blot_direct_writer::OP_i32_gt_u);
        op(h, blot_direct_writer::OP_select);
        tee(h, cap);
        k(h, 16);
        op(h, blot_direct_writer::OP_i32_add);
        tee(h, chunk_bytes);
        get(h, cap);
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
        trapIf(h);
        get(h, chunk_bytes);
        call(h, r.alloc_raw);
        set(h, chunk);
        gget(h, r.stack_total);
        get(h, chunk_bytes);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.stack_total);
        get(h, chunk);
        get(h, tail);
        store(h, 0);
        get(h, chunk);
        k(h, 0);
        store(h, 4);
        get(h, chunk);
        k(h, 16);
        op(h, blot_direct_writer::OP_i32_add);
        tee(h, result);
        get(h, cap);
        op(h, blot_direct_writer::OP_i32_add);
        set(h, limit);
        get(h, chunk);
        get(h, limit);
        store(h, 8);
        get(h, chunk);
        get(h, cap);
        store(h, 12);
        get(h, tail);
        open(h, blot_direct_writer::OP_if_);
        get(h, tail);
        get(h, chunk);
        store(h, 4);
        op(h, blot_direct_writer::OP_else_);
        get(h, chunk);
        gset(h, r.stack_head);
        op(h, blot_direct_writer::OP_end);
        get(h, chunk);
        gset(h, r.stack_chunk);
        get(h, limit);
        gset(h, r.stack_limit);
        get(h, result);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.stack_pointer);
        op(h, blot_direct_writer::OP_end); // end $found
        get(h, result);
        finish(h, module, r.stack_slow);
    }
    // stack(bytes) -> address, 16-byte aligned; contiguous fast path in active chunk.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let need = temp(h);
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
        get(h, address);
        finish(h, module, r.stack);
    }
    // rewind_stack(mark): loop-free fast path in current chunk; slow path crosses chunks or resets to head.
    {
        var h = H { parameters: 1, locals: 1, .. };
        get(h, 0);
        gget(h, r.stack_chunk);
        k(h, 16);
        op(h, blot_direct_writer::OP_i32_add);
        op(h, blot_direct_writer::OP_i32_ge_u);
        get(h, 0);
        gget(h, r.stack_limit);
        op(h, blot_direct_writer::OP_i32_le_u);
        op(h, blot_direct_writer::OP_i32_and);
        open(h, blot_direct_writer::OP_if_);
        get(h, 0);
        gset(h, r.stack_pointer);
        op(h, blot_direct_writer::OP_return_);
        op(h, blot_direct_writer::OP_end);
        get(h, 0);
        call(h, r.rewind_stack_slow);
        finish(h, module, r.rewind_stack);
    }
    // rewind_stack_slow(mark): walks back across chunks or resets to stack_head on mark == 0.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let cur = temp(h);
        let lim = temp(h);
        get(h, 0);
        op(h, blot_direct_writer::OP_i32_eqz);
        open(h, blot_direct_writer::OP_if_);
        gget(h, r.stack_head);
        tee(h, cur);
        open(h, blot_direct_writer::OP_if_);
        get(h, cur);
        gset(h, r.stack_chunk);
        get(h, cur);
        k(h, 16);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.stack_pointer);
        get(h, cur);
        load(h, 8);
        gset(h, r.stack_limit);
        op(h, blot_direct_writer::OP_else_);
        k(h, 0);
        gset(h, r.stack_chunk);
        k(h, 0);
        gset(h, r.stack_pointer);
        k(h, 0);
        gset(h, r.stack_limit);
        op(h, blot_direct_writer::OP_end);
        op(h, blot_direct_writer::OP_return_);
        op(h, blot_direct_writer::OP_end);
        gget(h, r.stack_chunk);
        set(h, cur);
        open(h, blot_direct_writer::OP_block);
        open(h, blot_direct_writer::OP_loop);
        get(h, cur);
        op(h, blot_direct_writer::OP_i32_eqz);
        open(h, blot_direct_writer::OP_if_);
        k(h, 0);
        gset(h, r.stack_chunk);
        k(h, 0);
        gset(h, r.stack_pointer);
        k(h, 0);
        gset(h, r.stack_limit);
        idx(h, blot_direct_writer::OP_br, 2);
        op(h, blot_direct_writer::OP_end);
        get(h, cur);
        load(h, 8);
        set(h, lim);
        get(h, 0);
        get(h, cur);
        k(h, 16);
        op(h, blot_direct_writer::OP_i32_add);
        op(h, blot_direct_writer::OP_i32_ge_u);
        get(h, 0);
        get(h, lim);
        op(h, blot_direct_writer::OP_i32_le_u);
        op(h, blot_direct_writer::OP_i32_and);
        open(h, blot_direct_writer::OP_if_);
        get(h, cur);
        gset(h, r.stack_chunk);
        get(h, lim);
        gset(h, r.stack_limit);
        get(h, 0);
        gset(h, r.stack_pointer);
        idx(h, blot_direct_writer::OP_br, 2);
        op(h, blot_direct_writer::OP_end);
        get(h, cur);
        load(h, 0);
        set(h, cur);
        idx(h, blot_direct_writer::OP_br, 0);
        op(h, blot_direct_writer::OP_end);
        op(h, blot_direct_writer::OP_end);
        finish(h, module, r.rewind_stack_slow);
    }
    // heap_alloc(bytes) -> (address, size): power-of-two classes from 16 bytes.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let class = temp(h);
        let head = temp(h);
        let address = temp(h);
        let size = temp(h);
        get(h, 0);
        k(h, heap_budget);
        op(h, blot_direct_writer::OP_i32_gt_u);
        trapIf(h);
        k(h, 32);
        get(h, 0);
        k(h, 16);
        get(h, 0);
        k(h, 16);
        op(h, blot_direct_writer::OP_i32_gt_u);
        op(h, blot_direct_writer::OP_select);
        k(h, 1);
        op(h, blot_direct_writer::OP_i32_sub);
        op(h, blot_direct_writer::OP_i32_clz);
        op(h, blot_direct_writer::OP_i32_sub);
        set(h, class);
        k(h, 1);
        get(h, class);
        op(h, blot_direct_writer::OP_i32_shl);
        set(h, size);
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
        trapIf(h);
        get(h, size);
        call(h, r.alloc_raw);
        set(h, address);
        gget(h, r.heap_top);
        get(h, size);
        op(h, blot_direct_writer::OP_i32_add);
        gset(h, r.heap_top);
        op(h, blot_direct_writer::OP_end);
        get(h, address);
        get(h, size);
        finish(h, module, r.heap_alloc);
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
            get(h, 0);
            gget(h, r.fork_owner_mark);
            op(h, blot_direct_writer::OP_i32_lt_u);
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
        // Grow: at least double, into the heap; free the old heap block.
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
        tee(h, fresh);
        get(h, entry);
        load(h, entry_base);
        get(h, length);
        get(h, 2);
        op(h, blot_direct_writer::OP_i32_mul);
        memoryCopy(h);
        get(h, capacity);
        k(h, heap_flag);
        op(h, blot_direct_writer::OP_i32_and);
        if has_fork {
            get(h, 0);
            gget(h, r.fork_owner_mark);
            op(h, blot_direct_writer::OP_i32_ge_u);
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
        k(h, heap_flag);
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
            get(h, 0);
            gget(h, r.fork_owner_mark);
            op(h, blot_direct_writer::OP_i32_lt_u);
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
            get(h, 0);
            gget(h, r.fork_owner_mark);
            op(h, blot_direct_writer::OP_i32_lt_u);
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
            get(h, 0);
            gget(h, r.fork_owner_mark);
            op(h, blot_direct_writer::OP_i32_lt_u);
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
    // create(length, stride, growable) -> (slot, generation), zeroed.
    {
        var h = H { parameters: 3, locals: 3, .. };
        let bytes = temp(h);
        let address = temp(h);
        let size = temp(h);
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
        call(h, r.heap_alloc);
        set(h, size);
        set(h, address);
        get(h, size);
        k(h, heap_flag);
        op(h, blot_direct_writer::OP_i32_or);
        set(h, size);
        op(h, blot_direct_writer::OP_else_);
        get(h, bytes);
        call(h, r.stack);
        set(h, address);
        get(h, bytes);
        set(h, size);
        op(h, blot_direct_writer::OP_end);
        get(h, address);
        k(h, 0);
        get(h, bytes);
        memoryFill(h);
        get(h, address);
        get(h, 0);
        get(h, size);
        call(h, r.open);
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
    // persist(slot, generation, stride, growable) -> persistent copy.
    {
        var h = H { parameters: 4, locals: 4, .. };
        let entry = temp(h);
        let bytes = temp(h);
        let address = temp(h);
        let size = temp(h);
        let aligned = temp(h);
        get(h, 0);
        get(h, 1);
        call(h, r.check);
        tee(h, entry);
        load(h, entry_length);
        get(h, 2);
        op(h, blot_direct_writer::OP_i32_mul);
        set(h, bytes);
        get(h, 3);
        open(h, blot_direct_writer::OP_if_);
        get(h, bytes);
        call(h, r.heap_alloc);
        set(h, size);
        set(h, address);
        get(h, size);
        k(h, heap_flag);
        op(h, blot_direct_writer::OP_i32_or);
        set(h, size);
        op(h, blot_direct_writer::OP_else_);
        get(h, bytes);
        k(h, 15);
        op(h, blot_direct_writer::OP_i32_add);
        k(h, 0xfffffff0);
        op(h, blot_direct_writer::OP_i32_and);
        tee(h, aligned);
        get(h, bytes);
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
        get(h, bytes);
        set(h, size);
        op(h, blot_direct_writer::OP_end);
        get(h, address);
        get(h, entry);
        load(h, entry_base);
        get(h, bytes);
        memoryCopy(h);
        get(h, address);
        get(h, entry);
        load(h, entry_length);
        get(h, size);
        call(h, r.open_persistent);
        finish(h, module, r.persist);
    }
    // Host transport: allocate(bytes) -> zeroed packet address; grows lazily via heap_alloc.
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
        call(h, r.heap_alloc);
        set(h, new_cap);
        set(h, new_base);
        gget(h, r.transport_cap);
        open(h, blot_direct_writer::OP_if_);
        gget(h, r.transport_base);
        gget(h, r.transport_cap);
        call(h, r.heap_free);
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
    // reset(ignored) -> 0
    {
        var h = H { parameters: 1, locals: 1, .. };
        gget(h, r.transport_base);
        gset(h, r.transport_top);
        k(h, 0);
        finish(h, module, r.reset);
    }
    // packet_length(address): the checked word count of a host packet.
    {
        var h = H { parameters: 1, locals: 1, .. };
        let end = temp(h);
        let length = temp(h);
        gget(h, r.transport_cap);
        op(h, blot_direct_writer::OP_i32_eqz);
        trapIf(h);
        gget(h, r.transport_base);
        gget(h, r.transport_cap);
        op(h, blot_direct_writer::OP_i32_add);
        set(h, end);
        get(h, 0);
        gget(h, r.transport_base);
        op(h, blot_direct_writer::OP_i32_lt_u);
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
    if has_fork {
        // undo_record(addr, bytes): lazily allocate undo journal and save slice.
        {
            var h = H { parameters: 2, locals: 2, .. };
            let aligned = temp(h);
            let sp = temp(h);
            let next = temp(h);
            let base = temp(h);
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
            get(h, 1);
            k(h, 3);
            op(h, blot_direct_writer::OP_i32_add);
            k(h, 0xfffffffc);
            op(h, blot_direct_writer::OP_i32_and);
            set(h, aligned);
            gget(h, r.undo_sp);
            tee(h, sp);
            get(h, aligned);
            op(h, blot_direct_writer::OP_i32_add);
            k(h, 8);
            op(h, blot_direct_writer::OP_i32_add);
            tee(h, next);
            gget(h, r.undo_end);
            op(h, blot_direct_writer::OP_i32_gt_u);
            get(h, next);
            get(h, sp);
            op(h, blot_direct_writer::OP_i32_lt_u);
            op(h, blot_direct_writer::OP_i32_or);
            trapIf(h);
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
        // undo_rewind(saved_sp): LIFO restore every journaled slice down to saved_sp.
        {
            var h = H { parameters: 1, locals: 1, .. };
            let target = temp(h);
            let sp = temp(h);
            let bytes = temp(h);
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
            set(h, bytes);
            get(h, sp);
            k(h, 8);
            op(h, blot_direct_writer::OP_i32_sub);
            load(h, 0);
            set(h, addr);
            get(h, sp);
            k(h, 8);
            op(h, blot_direct_writer::OP_i32_sub);
            get(h, bytes);
            k(h, 3);
            op(h, blot_direct_writer::OP_i32_add);
            k(h, 0xfffffffc);
            op(h, blot_direct_writer::OP_i32_and);
            op(h, blot_direct_writer::OP_i32_sub);
            set(h, src);
            get(h, addr);
            get(h, src);
            get(h, bytes);
            memoryCopy(h);
            get(h, src);
            gset(h, r.undo_sp);
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
    blot_direct_writer::setName(module, r.release, "runtime.release");
    blot_direct_writer::setName(module, r.check, "runtime.check");
    blot_direct_writer::setName(module, r.stack, "runtime.stack");
    blot_direct_writer::setName(module, r.stack_slow, "runtime.stack_slow");
    blot_direct_writer::setName(module, r.rewind_stack, "runtime.rewind_stack");
    blot_direct_writer::setName(module, r.rewind_stack_slow, "runtime.rewind_stack_slow");
    blot_direct_writer::setName(module, r.heap_alloc, "runtime.heap_alloc");
    blot_direct_writer::setName(module, r.heap_free, "runtime.heap_free");
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
    if has_fork {
        blot_direct_writer::setName(module, r.undo_record, "runtime.undo_record");
        blot_direct_writer::setName(module, r.undo_rewind, "runtime.undo_rewind");
    }
    return r;
}
