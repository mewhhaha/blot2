import owned_scalar_source;
import owned_scalar_verify;
import owned_scalar_runtime;
fn main() {
    let source = "owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,4294967295)\n";
    let parsed = owned_scalar_source::parse(source);
    assert(parsed.status == 0 && parsed.core.terminal == 1 && parsed.core.value == 4294967295);
    assert(owned_scalar_verify::verify(source, parsed.core));
    let aborted = "owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  abort(free,#Cancelled)\n";
    let abort_core = owned_scalar_source::parse(aborted);
    assert(abort_core.status == 0 && abort_core.core.terminal == 2 && owned_scalar_verify::verify(aborted, abort_core.core));
    for invalid in [
        "owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  return 4\n",
        "owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  break 4\n",
        "owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(other,4)\n",
        "owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,4294967296)\n",
        "owned@[ScalarPayload[_],# Cancelled](0) as r free in do:\n  abort(free,#Cancelled)\n",
        "owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  abort(free,# Cancelled)\n",
        "owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,4)\n  seal(free,5)\n"
    ] {
        assert(owned_scalar_source::parse(invalid).status != 0);
        assert(!owned_scalar_verify::verify(invalid, parsed.core));
    }
    var clock = owned_scalar_runtime::Clock {};
    var state = owned_scalar_runtime::State {};
    assert(owned_scalar_runtime::initialize(state, clock));
    let clock_before = clock.next;
    assert(!owned_scalar_runtime::initialize(state, clock) && clock.next == clock_before);
    var exhausted_clock = owned_scalar_runtime::Clock { next: 18446744073709551615 };
    var uninitialized = owned_scalar_runtime::State {};
    assert(!owned_scalar_runtime::initialize(uninitialized, exhausted_clock) && uninitialized.owner == 0);
    let empty_memory = copy(state.memory);
    var forged = parsed.core; forged.value = 0;
    assert(!owned_scalar_verify::verify(source, forged));
    assert(owned_scalar_runtime::construct(state, source, forged).status == 2);
    assert(state.slots[0].state == 0 && state.bitmap[0] == 0 && state.memory[..] == empty_memory[..]);
    forged = parsed.core; forged.terminal = 2; forged.value = 0;
    assert(!owned_scalar_verify::verify(source, forged));
    assert(owned_scalar_runtime::construct(state, source, forged).status == 2);
    let built = owned_scalar_runtime::construct(state, source, parsed.core);
    assert(built.status == 0 && state.slot == 1 && state.slots[0].state == 2);
    let base = state.slots[0].base;
    assert(base == 4096 && state.slots[0].requested == 256 && state.slots[0].top == 256);
    assert(state.slots[0].root_schema == 1 && state.slots[0].root_words == 1);
    for i in 4 { assert(state.memory[base+i] == 255); }
    for i in 4..256 { assert(state.memory[base+i] == 0); }
    let first = owned_scalar_runtime::open(state, built.handle);
    let second = owned_scalar_runtime::open(state, built.handle);
    assert(first.status == 0 && second.status == 0 && first.value == 4294967295 && second.value == first.value && first.loan.serial != second.loan.serial);
    assert(owned_scalar_runtime::move(state, built.handle).status == 2);
    assert(owned_scalar_runtime::close(state, built.handle).status == 2);
    assert(owned_scalar_runtime::end_open(state, built.handle, first.loan).status == 1);
    assert(owned_scalar_runtime::end_open(state, built.handle, second.loan).status == 0);
    assert(owned_scalar_runtime::end_open(state, built.handle, first.loan).status == 0);
    assert(owned_scalar_runtime::end_open(state, built.handle, first.loan).status == 1);
    let moved = owned_scalar_runtime::move(state, built.handle);
    assert(moved.status == 0 && moved.handle.stamp != built.handle.stamp && moved.handle.slot == built.handle.slot);
    assert(state.slots[0].base == base && state.memory[base] == 255);
    assert(owned_scalar_runtime::open(state, built.handle).status == 1);
    assert(owned_scalar_runtime::close(state, built.handle).status == 1);
    let reopened = owned_scalar_runtime::open(state, moved.handle);
    assert(reopened.status == 0 && reopened.loan.serial != first.loan.serial && reopened.value == 4294967295);
    assert(owned_scalar_runtime::end_open(state, moved.handle, reopened.loan).status == 0);
    assert(owned_scalar_runtime::close(state, moved.handle).status == 0);
    assert(state.slots[0].state == 0 && state.bitmap[0] == 0 && state.slot == 0);
    assert(owned_scalar_runtime::close(state, moved.handle).status == 1);
    assert(owned_scalar_runtime::construct(state, aborted, abort_core.core).status == 1);
    assert(state.slots[0].state == 0 && state.bitmap[0] == 0 && state.slot == 0);
    let rebuilt = owned_scalar_runtime::construct(state, source, parsed.core);
    assert(rebuilt.status == 0 && rebuilt.handle.generation != moved.handle.generation && rebuilt.handle.stamp != moved.handle.stamp);
    assert(owned_scalar_runtime::open(state, moved.handle).status == 1);
    var loans: owned_scalar_runtime::Loan[32] = [owned_scalar_runtime::Loan {}; 32];
    for i in 32 {
        let opening = owned_scalar_runtime::open(state, rebuilt.handle);
        assert(opening.status == 0 && opening.loan.serial != 0 && opening.value == 4294967295);
        loans[i] = opening.loan;
    }
    assert(owned_scalar_runtime::open(state, rebuilt.handle).status == 2);
    assert(owned_scalar_runtime::move(state, rebuilt.handle).status == 2);
    assert(owned_scalar_runtime::close(state, rebuilt.handle).status == 2);
    for j in 32 { assert(owned_scalar_runtime::end_open(state, rebuilt.handle, loans[31-j]).status == 0); }
    assert(owned_scalar_runtime::close(state, rebuilt.handle).status == 0);
    // Each state from the same live clock has distinct local ownership and
    // loans. Equal slot/generation/stamp counters cannot be transferred.
    var left = owned_scalar_runtime::State {}; var right = owned_scalar_runtime::State {};
    assert(owned_scalar_runtime::initialize(left, clock) && owned_scalar_runtime::initialize(right, clock));
    let a = owned_scalar_runtime::construct(left, source, parsed.core);
    let b = owned_scalar_runtime::construct(right, source, parsed.core);
    assert(a.status == 0 && b.status == 0 && a.handle.slot == b.handle.slot && a.handle.generation == b.handle.generation && a.handle.stamp == b.handle.stamp);
    assert(a.handle.owner != b.handle.owner);
    assert(owned_scalar_runtime::open(right, a.handle).status == 1);
    assert(owned_scalar_runtime::move(right, a.handle).status == 1);
    assert(owned_scalar_runtime::close(right, a.handle).status == 1);
    let la = owned_scalar_runtime::open(left, a.handle);
    let lb = owned_scalar_runtime::open(right, b.handle);
    assert(la.loan.serial == lb.loan.serial && la.loan.owner != lb.loan.owner);
    assert(owned_scalar_runtime::end_open(right, b.handle, la.loan).status == 1);
    assert(owned_scalar_runtime::end_open(left, a.handle, lb.loan).status == 1);
    assert(owned_scalar_runtime::end_open(left, a.handle, la.loan).status == 0);
    assert(owned_scalar_runtime::end_open(right, b.handle, lb.loan).status == 0);
    assert(owned_scalar_runtime::close(left, a.handle).status == 0 && owned_scalar_runtime::close(right, b.handle).status == 0);
    // Oversized work and lack of contiguous backing fail before publication.
    for request in ["owned@[ScalarPayload[_],#Cancelled](4294967295) as r free in do:\n  seal(free,7)\n",
                    "owned@[ScalarPayload[_],#Cancelled](3841) as r free in do:\n  seal(free,7)\n"] {
        let p = owned_scalar_source::parse(request); assert(p.status == 0);
        let before = state.slots[0]; let snapshot = copy(state.memory);
        let failed = owned_scalar_runtime::construct(state, request, p.core);
        assert(failed.status == 3 && state.slot == 0 && state.bitmap[0] == 0 && state.memory[..] == snapshot[..]);
        assert(state.slots[0].state == before.state && state.slots[0].generation == before.generation);
    }
    var retired = owned_scalar_runtime::State {};
    assert(owned_scalar_runtime::initialize(retired, clock));
    retired.slots[0].generation = 4294967294;
    let last = owned_scalar_runtime::construct(retired, source, parsed.core);
    assert(last.status == 0 && last.handle.generation == 4294967295);
    assert(owned_scalar_runtime::close(retired, last.handle).status == 0);
    assert(retired.slots[0].state == 3 && retired.bitmap[0] == 0);
    assert(owned_scalar_runtime::construct(retired, source, parsed.core).status == 3);
    // Every one-byte mutation is independently re-recognized: a matching
    // candidate may run, while source/Core disagreement never reaches reserve.
    for i in source.len {
        var mutated: u8[>..] = []; mutated.append(source);
        mutated[i] ^= 1;
        let candidate = owned_scalar_source::parse(mutated);
        if candidate.status == 0 {
            assert(owned_scalar_verify::verify(mutated, candidate.core));
        }
        if !owned_scalar_verify::verify(mutated, parsed.core) {
            var fresh = owned_scalar_runtime::State {};
            assert(owned_scalar_runtime::initialize(fresh, clock));
            assert(owned_scalar_runtime::construct(fresh, mutated, parsed.core).status == 2);
            assert(fresh.slot == 0 && fresh.slots[0].generation == 0 && fresh.bitmap[0] == 0);
        }
    }
    print("source-checked private scalar Owned lifecycle passed");
}
