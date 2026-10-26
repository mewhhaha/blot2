import owned_scalar_runtime;
import owned_program_source;
import owned_program_verify;
import owned_program_runtime;
fn main() {
    let direct = "let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,4294967295)\ncase built:\n  #Err(e) => return #Err(e)\n  #Ok(h) => do:\n    let value = owned.open(h) as s payload in do:\n      break payload\n    owned.close(h)\n    return #Ok(value)\n";
    let moved = "let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,7)\ncase built:\n  #Err(e) => return #Err(e)\n  #Ok(h) => do:\n    let m = h\n    let value = owned.open(m) as s payload in do:\n      break payload\n    owned.close(m)\n    return #Ok(value)\n";
    let abort = "let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  abort(free,#Cancelled)\ncase built:\n  #Err(e) => return #Err(e)\n  #Ok(h) => do:\n    let value = owned.open(h) as s payload in do:\n      break payload\n    owned.close(h)\n    return #Ok(value)\n";
    let overflow = "let built = owned@[ScalarPayload[_],#Cancelled](4294967295) as r free in do:\n  seal(free,7)\ncase built:\n  #Err(e) => return #Err(e)\n  #Ok(h) => do:\n    let value = owned.open(h) as s payload in do:\n      break payload\n    owned.close(h)\n    return #Ok(value)\n";
    let a = owned_program_source::parse(direct); let b = owned_program_source::parse(moved);
    let c = owned_program_source::parse(abort); let d = owned_program_source::parse(overflow);
    assert(a.status == 0 && b.status == 0 && c.status == 0 && d.status == 0);
    assert(!a.core.moved && b.core.moved && c.core.owned.terminal == 2);
    assert(owned_program_verify::verify(direct,a.core) && owned_program_verify::verify(moved,b.core) &&
           owned_program_verify::verify(abort,c.core) && owned_program_verify::verify(overflow,d.core));
    var clock = owned_scalar_runtime::Clock {}; var state = owned_scalar_runtime::State {};
    assert(owned_scalar_runtime::initialize(state,clock));
    let first = owned_program_runtime::run(state,direct,a.core);
    assert(first.status == 0 && first.value == 4294967295 && state.slot == 0 && state.bitmap[0] == 0 && state.loan_count == 0);
    let second = owned_program_runtime::run(state,moved,b.core);
    assert(second.status == 0 && second.value == 7 && state.slot == 0 && state.bitmap[0] == 0 && state.loan_count == 0);
    let fail = owned_program_runtime::run(state,abort,c.core);
    assert(fail.status == 1 && state.slot == 0 && state.bitmap[0] == 0);
    let reserve = owned_program_runtime::run(state,overflow,d.core);
    assert(reserve.status == 2 && reserve.reserve_error == 1 && state.slot == 0 && state.bitmap[0] == 0);
    // A forged completion cannot skip a move, change source offsets, or
    // replace a source-bound payload; no owner slot is touched on rejection.
    var forged = b.core; forged.moved = false;
    assert(!owned_program_verify::verify(moved,forged));
    let before = state.slots[0]; let memory = copy(state.memory);
    assert(owned_program_runtime::run(state,moved,forged).status == 3);
    assert(state.slots[0].generation == before.generation && state.bitmap[0] == 0 && state.memory[..] == memory[..]);
    forged = a.core; forged.owned_start += 1;
    assert(!owned_program_verify::verify(direct,forged));
    forged = a.core; forged.owned.value = 1;
    assert(!owned_program_verify::verify(direct,forged));
    // Incomplete handling, old-handle use after move, close while open,
    // escaped hidden payload, duplicate close and owner omission are rejected.
    for bad in [
      "let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,7)\ncase built:\n  #Ok(h) => do:\n    let value = owned.open(h) as s payload in do:\n      break payload\n    owned.close(h)\n    return #Ok(value)\n",
      "let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,7)\ncase built:\n  #Err(e) => return #Err(e)\n  #Ok(h) => do:\n    let m = h\n    let value = owned.open(h) as s payload in do:\n      break payload\n    owned.close(m)\n    return #Ok(value)\n",
      "let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,7)\ncase built:\n  #Err(e) => return #Err(e)\n  #Ok(h) => do:\n    let value = owned.open(h) as s payload in do:\n      owned.close(h)\n      break payload\n    return #Ok(value)\n",
      "let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,7)\ncase built:\n  #Err(e) => return #Err(e)\n  #Ok(h) => do:\n    let value = owned.open(h) as s payload in do:\n      break h\n    owned.close(h)\n    return #Ok(value)\n",
      "let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,7)\ncase built:\n  #Err(e) => return #Err(e)\n  #Ok(h) => do:\n    let value = owned.open(h) as s payload in do:\n      break payload\n    return #Ok(value)\n",
      "let built = owned@[ScalarPayload[_],#Cancelled](0) as r free in do:\n  seal(free,7)\ncase built:\n  #Err(e) => return #Err(e)\n  #Ok(h) => do:\n    let value = owned.open(h) as s payload in do:\n      break payload\n    owned.close(h)\n    owned.close(h)\n    return #Ok(value)\n"
    ] {
        assert(owned_program_source::parse(bad).status != 0);
        assert(!owned_program_verify::verify(bad,a.core) && !owned_program_verify::verify(bad,b.core));
    }
    // The private runtime preflights counters before reserving so a late
    // model exhaustion cannot strand an affine owner or partial capsule.
    state.next_loan = 18446744073709551615;
    let previous = state.slots[0];
    assert(owned_program_runtime::run(state,direct,a.core).status == 3);
    assert(state.slot == 0 && state.bitmap[0] == 0 && state.slots[0].generation == previous.generation);
    state.next_loan = 0; state.stamp = 18446744073709551614;
    assert(owned_program_runtime::run(state,moved,b.core).status == 3);
    assert(state.slot == 0 && state.bitmap[0] == 0 && state.slots[0].generation == previous.generation);
    print("source-bound owned move/borrow/close program passed");
}
