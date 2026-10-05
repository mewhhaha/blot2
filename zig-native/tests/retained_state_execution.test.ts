import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("retained State witnesses template-local-state-scopes sync", async () => {
  await compileAndRun(`data Cell value = #Cell value
const witness32 = fn ignored -> Cell U32 => @panic "witness called"
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witness32
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witnessf
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State witnesses template-local-state-scopes JSPI", async () => {
  await compileAndRun(`data Cell value = #Cell value
const witness32 = fn ignored -> Cell U32 => @panic "witness called"
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witness32
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witnessf
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State witnesses local-aliases sync", async () => {
  await compileAndRun(`data Cell value = #Cell value
const witness32 = fn ignored -> Cell U32 => @panic "witness called"
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let alias = witness32
    let alias_again = alias
    let computation = make alias_again
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let alias = witnessf
    let alias_again = alias
    let computation = make alias_again
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State witnesses local-aliases JSPI", async () => {
  await compileAndRun(`data Cell value = #Cell value
const witness32 = fn ignored -> Cell U32 => @panic "witness called"
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let alias = witness32
    let alias_again = alias
    let computation = make alias_again
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let alias = witnessf
    let alias_again = alias
    let computation = make alias_again
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State witnesses local-snapshots sync", async () => {
  await compileAndRun(`data Cell value = #Cell value
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let captured = 41
    let witness = fn ignored => #Cell captured
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witness
    captured := 99
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let captured = 3.5
    let witness = fn ignored => #Cell captured
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witness
    captured := 199.5
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State witnesses local-snapshots JSPI", async () => {
  await compileAndRun(`data Cell value = #Cell value
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let captured = 41
    let witness = fn ignored => #Cell captured
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witness
    captured := 99
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let captured = 3.5
    let witness = fn ignored => #Cell captured
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witness
    captured := 199.5
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State witnesses local-snapshots-called sync", async () => {
  await compileAndRun(`data Cell value = #Cell value
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let captured = 41
    let witness = fn ignored => #Cell captured
    let make = fn witness => @computation (fn () => do:
      use current <- @state.get witness
      let #Cell stored = current
      let #Cell captured = witness ()
      return #Cell (@u32.add stored captured)
    )
    let computation = make witness
    captured := 99
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let captured = 3.5
    let witness = fn ignored => #Cell captured
    let make = fn witness => @computation (fn () => do:
      use current <- @state.get witness
      let #Cell stored = current
      let #Cell captured = witness ()
      return #Cell (@f32.add stored captured)
    )
    let computation = make witness
    captured := 199.5
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 87);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 87);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State witnesses local-snapshots-called JSPI", async () => {
  await compileAndRun(`data Cell value = #Cell value
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let captured = 41
    let witness = fn ignored => #Cell captured
    let make = fn witness => @computation (fn () => do:
      use current <- @state.get witness
      let #Cell stored = current
      let #Cell captured = witness ()
      return #Cell (@u32.add stored captured)
    )
    let computation = make witness
    captured := 99
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let captured = 3.5
    let witness = fn ignored => #Cell captured
    let make = fn witness => @computation (fn () => do:
      use current <- @state.get witness
      let #Cell stored = current
      let #Cell captured = witness ()
      return #Cell (@f32.add stored captured)
    )
    let computation = make witness
    captured := 199.5
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 87);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 87);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State witnesses latent-never-called sync", async () => {
  await compileAndRun(`data Cell value = #Cell value
type Tick is effect = { read: Unit -> U32 }
const witness32 = fn ignored -> Cell U32 => do:
  use Tick.read ()
  return @panic "witness called"
const witnessf = fn ignored -> Cell F32 => do:
  use Tick.read ()
  return @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witness32
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witnessf
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State witnesses latent-never-called JSPI", async () => {
  await compileAndRun(`data Cell value = #Cell value
type Tick is effect = { read: Unit -> U32 }
const witness32 = fn ignored -> Cell U32 => do:
  use Tick.read ()
  return @panic "witness called"
const witnessf = fn ignored -> Cell F32 => do:
  use Tick.read ()
  return @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witness32
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witnessf
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State witnesses local-initializer-effects sync", async () => {
  await compileAndRun(`data Cell value = #Cell value
data Count = #Count U32
const witness32 = fn ignored -> Cell U32 => @panic "witness called"
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Count count, result) = @state.run (#Count 0) (fn () => do:
    use result32 <- @state.run (#Cell 40) (fn () => do:
      let make = fn witness => do:
        use previous_cell <- @state.get #Count
        let #Count previous = previous_cell
        use @state.set (#Count (@u32.add previous 1))
        return @computation (fn () => @state.get witness)
      use computation <- make witness32
      return handled computation
    )
    let (#Cell state32, #Cell value32) = result32
    use resultf <- @state.run (#Cell 2.5) (fn () => do:
      let make = fn witness => do:
        use previous_cell <- @state.get #Count
        let #Count previous = previous_cell
        use @state.set (#Count (@u32.add previous 1))
        return @computation (fn () => @state.get witness)
      use computation <- make witnessf
      return handled computation
    )
    let (#Cell statef, #Cell valuef) = resultf
    return @f32.add (@u32.to_f32 value32) valuef
  )
  return @f32.add result (@u32.to_f32 count)
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 44.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 44.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State witnesses local-initializer-effects JSPI", async () => {
  await compileAndRun(`data Cell value = #Cell value
data Count = #Count U32
const witness32 = fn ignored -> Cell U32 => @panic "witness called"
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Count count, result) = @state.run (#Count 0) (fn () => do:
    use result32 <- @state.run (#Cell 40) (fn () => do:
      let make = fn witness => do:
        use previous_cell <- @state.get #Count
        let #Count previous = previous_cell
        use @state.set (#Count (@u32.add previous 1))
        return @computation (fn () => @state.get witness)
      use computation <- make witness32
      return handled computation
    )
    let (#Cell state32, #Cell value32) = result32
    use resultf <- @state.run (#Cell 2.5) (fn () => do:
      let make = fn witness => do:
        use previous_cell <- @state.get #Count
        let #Count previous = previous_cell
        use @state.set (#Count (@u32.add previous 1))
        return @computation (fn () => @state.get witness)
      use computation <- make witnessf
      return handled computation
    )
    let (#Cell statef, #Cell valuef) = resultf
    return @f32.add (@u32.to_f32 value32) valuef
  )
  return @f32.add result (@u32.to_f32 count)
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 44.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 44.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State witnesses reject template-local-state-identity", async () => {
  await compileExpectedFailure(`data Cell value = #Cell value
const witness32 = fn ignored -> Cell U32 => @panic "witness called"
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let make = fn witness => @computation (fn () => @state.get witness)
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let computation = make witness32
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let computation = make witnessf
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, "type_mismatch", undefined, { prelude: "none" });
});

Deno.test("retained State witnesses reject shared-higher-order", async () => {
  await compileExpectedFailure(`data Cell value = #Cell value
const witness32 = fn ignored -> Cell U32 => @panic "witness called"
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let make = fn witness => @computation (fn () => @state.get witness)
  let alias = (fn factory => factory) make
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let computation = alias witness32
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let computation = alias witnessf
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, "type_mismatch", undefined, { prelude: "none" });
});

Deno.test("retained State witnesses reject wrong-input", async () => {
  await compileExpectedFailure(`data Cell value = #Cell value
const witness = fn (value: U32) => #Cell value
entry const answer = fn () => do:
  let (#Cell _, #Cell value) = @state.run (#Cell 40) (fn () => do:
    let make = fn witness => @computation (fn () => do:
      use @state.get witness
      return witness ()
    )
    for request in @requests (make witness):
      case request of
        complete result =>
          return result
  )
  return value
`, "type_mismatch", undefined, { prelude: "none" });
});

Deno.test("retained State witnesses reject wrong-family", async () => {
  await compileExpectedFailure(`data Cell value = #Cell value
data Other value = #Other value
const witness = fn ignored -> Other U32 => @panic "witness called"
entry const answer: Unit -> U32 ! {} = fn () => do:
  let (#Cell _, #Other value) = @state.run (#Cell 40) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    for request in @requests (make witness):
      case request of
        complete result =>
          return result
  )
  return value
`, "effect_mismatch", undefined, { prelude: "none" });
});

Deno.test("retained State annotation lifetime state-annotation-scopes sync", async () => {
  await compileAndRun(`data Cell value = #Cell value
const witness32 = fn ignored -> Cell U32 => @panic "witness called"
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let make: a -> b = fn witness => @computation (fn () => @state.get witness)
    let computation = make witness32
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let make: a -> b = fn witness => @computation (fn () => @state.get witness)
    let computation = make witnessf
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State annotation lifetime state-annotation-scopes JSPI", async () => {
  await compileAndRun(`data Cell value = #Cell value
const witness32 = fn ignored -> Cell U32 => @panic "witness called"
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let make: a -> b = fn witness => @computation (fn () => @state.get witness)
    let computation = make witness32
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let make: a -> b = fn witness => @computation (fn () => @state.get witness)
    let computation = make witnessf
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State annotation lifetime state-annotation-shared sync", async () => {
  await compileAndRun(`data Cell value = #Cell value
const witness32 = fn ignored -> Cell U32 => @panic "witness called"
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let make: a -> b = fn witness => @computation (fn () => @state.get witness)
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let computation = make witness32
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let computation = make witnessf
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State annotation lifetime state-annotation-shared JSPI", async () => {
  await compileAndRun(`data Cell value = #Cell value
const witness32 = fn ignored -> Cell U32 => @panic "witness called"
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let make: a -> b = fn witness => @computation (fn () => @state.get witness)
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let computation = make witness32
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let computation = make witnessf
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State annotation lifetime plain-annotation-scope sync", async () => {
  await compileAndRun(`const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let make: a -> b = fn value => @computation (fn () => value)
  let integer = handled (make 40)
  let fraction = handled (make 2.5)
  return @f32.add (@u32.to_f32 integer) fraction
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State annotation lifetime plain-annotation-scope JSPI", async () => {
  await compileAndRun(`const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let make: a -> b = fn value => @computation (fn () => value)
  let integer = handled (make 40)
  let fraction = handled (make 2.5)
  return @f32.add (@u32.to_f32 integer) fraction
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State annotation lifetime where-annotation-scope sync", async () => {
  await compileAndRun(`const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let make: a -> b where { type_rep a } = fn value => @computation (fn () => value)
  let integer = handled (make 40)
  let fraction = handled (make 2.5)
  return @f32.add (@u32.to_f32 integer) fraction
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State annotation lifetime where-annotation-scope JSPI", async () => {
  await compileAndRun(`const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let make: a -> b where { type_rep a } = fn value => @computation (fn () => value)
  let integer = handled (make 40)
  let fraction = handled (make 2.5)
  return @f32.add (@u32.to_f32 integer) fraction
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State selected proof rejects plain-shared-scope", async () => {
  await compileExpectedFailure(`const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let make = fn value => @computation (fn () => value)
  let integer = handled (make 40)
  let fraction = handled (make 2.5)
  return @f32.add (@u32.to_f32 integer) fraction
entry const folded = answer ()
`, "type_mismatch", undefined, { prelude: "none" });
});

Deno.test("retained State selected proof rejects unmet-qualifier", async () => {
  await compileExpectedFailure(`data Cell value = #Cell value
const witness32: a -> Cell U32 where { associated "missing" Bool Bool Bool } = fn ignored => @panic "witness called"
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witness32
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let make = fn witness => @computation (fn () => @state.get witness)
    let computation = make witnessf
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, "missing_associated", undefined, { prelude: "none" });
});

Deno.test("retained State selected proof rejects invoked-missing-member", async () => {
  await compileExpectedFailure(`data Cell value = #Cell value
const witness32 = fn ignored -> Cell U32 => #Cell ignored.missing
const witnessf = fn ignored -> Cell F32 => @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let make = fn witness => @computation (fn () => do:
      use @state.get witness
      return witness ()
    )
    let computation = make witness32
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let make = fn witness => @computation (fn () => do:
      use @state.get witness
      return witness ()
    )
    let computation = make witnessf
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, "missing_member", undefined, { prelude: "none" });
});

Deno.test("retained State selected proof rejects invoked-extra-effect", async () => {
  await compileExpectedFailure(`data Cell value = #Cell value
type Tick is effect = { read: Unit -> U32 }
const witness32 = fn ignored -> Cell U32 => do:
  use Tick.read ()
  return @panic "witness called"
const witnessf = fn ignored -> Cell F32 => do:
  use Tick.read ()
  return @panic "witness called"
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer: Unit -> F32 ! {} = fn () => do:
  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:
    let make = fn witness => @computation (fn () => do:
      use @state.get witness
      return witness ()
    )
    let computation = make witness32
    return handled computation
  )
  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:
    let make = fn witness => @computation (fn () => do:
      use @state.get witness
      return witness ()
    )
    let computation = make witnessf
    return handled computation
  )
  return @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, "let_effect", undefined, { prelude: "none" });
});
