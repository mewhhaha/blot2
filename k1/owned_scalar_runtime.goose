// Executed private scalar Owned experiment. Only one fixture owner and one
// closed U32 capsule are supported. Runtime stamps/opening counters detect
// stale test handles but do not provide source-level affine proof, checked
// brands, closure/view closedness, general type metadata, or a K1 certificate.
namespace owned_scalar_runtime;
import owned_scalar_source;
import owned_scalar_verify;
import pool;

// All states in one fixture run must be initialized using the same live,
// non-copied Clock. An initialized State must not be copied, and caller code
// must not construct or mutate handles, loans, or internal state directly.
// These are trusted fixture preconditions; numeric fields are not unforgeable
// authority and do not establish portable or source-level provenance.
struct Clock { next: u64 = 0 }
struct Handle { owner: u64 = 0, slot: u32 = 0, generation: u32 = 0, stamp: u64 = 0 }
struct Loan { owner: u64 = 0, serial: u64 = 0 }
struct State {
    slots: pool::Slot[1] = [pool::Slot {}; 1], bitmap: u32[1] = [0; 1], memory: u8[8192] = [0; 8192],
    owner: u64 = 0, slot: u32 = 0, generation: u32 = 0, stamp: u64 = 0,
    loan_count: u32 = 0, loan_stack: u64[32] = [0; 32], next_loan: u64 = 0
}
// 0 sealed, 1 aborted, 2 invalid source/Core/state, 3 reservation failure.
struct Build { status: u32 = 2, handle: Handle = Handle {}, reserve_error: i64 = 0 }
// 0 success, 1 invalid/stale authority/state, 2 outstanding loan/limit.
struct Operation { status: u32 = 1, handle: Handle = Handle {}, loan: Loan = Loan {}, value: u32 = 0 }
fn initialize(state: State&, clock: Clock&) -> bool {
    if state.owner != 0 || state.slot != 0 || state.loan_count != 0 || clock.next == 18446744073709551615 { return false; }
    clock.next += 1; state.owner = clock.next; return true;
}
fn live(state: State&, h: Handle) -> bool {
    return h.owner != 0 && h.owner == state.owner && h.slot != 0 && h.slot == state.slot && h.generation == state.generation &&
        h.stamp != 0 && h.stamp == state.stamp &&
        pool::valid_state(state.slots, h.slot, h.generation, 2) &&
        pool::valid_extent(state.slots[h.slot - 1], 4096, 1) &&
        state.slots[h.slot - 1].root_schema == 1 && state.slots[h.slot - 1].root_words == 1;
}
fn construct(state: State&, source: u8[:], core: owned_scalar_source::Core) -> Build {
    // No mutation, reservation, or data publication until independent source
    // recognition and lifecycle preconditions have completed.
    if !owned_scalar_verify::verify(source, core) || state.owner == 0 || state.slot != 0 || state.loan_count != 0 ||
       state.stamp == 18446744073709551615 { return Build {}; }
    let reserve = pool::owned_begin(state.slots, state.bitmap, 4096, 1, core.work_bytes);
    if reserve.status != 0 { return Build { status: 3, reserve_error: reserve.status }; }
    if core.terminal == 2 {
        assert(pool::owned_abort(state.slots, state.bitmap, 4096, 1, reserve.slot, reserve.generation));
        return Build { status: 1 };
    }
    let index = reserve.slot - 1;
    let base = state.slots[index].base;
    assert(base >= 4096 && base + 256 <= state.memory.len);
    // Initialize the entire root before publishing SealedOwned.
    for i in 256 { state.memory[base + i] = 0; }
    for i in 4 { state.memory[base + i] = (core.value >> (8 * i) & 255) as u8; }
    state.slots[index].root_schema = 1; state.slots[index].root_words = 1;
    state.slots[index].state = 2;
    state.slot = reserve.slot; state.generation = reserve.generation; state.stamp += 1;
    return Build { status: 0, handle: Handle { owner: state.owner, slot: reserve.slot, generation: reserve.generation, stamp: state.stamp } };
}
fn open(state: State&, h: Handle) -> Operation {
    if !live(state,h) { return Operation {}; }
    if state.loan_count >= 32 || state.next_loan == 18446744073709551615 { return Operation { status: 2 }; }
    let base = state.slots[h.slot-1].base;
    if base < 4096 || base + 4 > state.memory.len { return Operation {}; }
    let value = state.memory[base] | (state.memory[base+1] as u32 << 8) |
        (state.memory[base+2] as u32 << 16) | (state.memory[base+3] as u32 << 24);
    state.next_loan += 1; state.loan_stack[state.loan_count] = state.next_loan; state.loan_count += 1;
    return Operation { status: 0, handle: h, loan: Loan { owner: state.owner, serial: state.next_loan }, value: value };
}
fn end_open(state: State&, h: Handle, loan: Loan) -> Operation {
    if !live(state,h) || loan.owner != state.owner || state.loan_count == 0 || state.loan_count > 32 ||
       loan.serial == 0 || state.loan_stack[state.loan_count-1] != loan.serial { return Operation {}; }
    state.loan_count -= 1; state.loan_stack[state.loan_count] = 0;
    return Operation { status: 0, handle: h };
}
fn move(state: State&, h: Handle) -> Operation {
    if !live(state,h) { return Operation {}; }
    if state.loan_count != 0 || state.stamp == 18446744073709551615 { return Operation { status: 2 }; }
    state.stamp += 1;
    return Operation { status: 0, handle: Handle { owner: state.owner, slot: h.slot, generation: h.generation, stamp: state.stamp } };
}
fn close(state: State&, h: Handle) -> Operation {
    if !live(state,h) { return Operation {}; }
    if state.loan_count != 0 { return Operation { status: 2 }; }
    if !pool::owned_close(state.slots,state.bitmap,4096,1,h.slot,h.generation) { return Operation {}; }
    state.slot = 0; state.generation = 0;
    return Operation { status: 0 };
}
