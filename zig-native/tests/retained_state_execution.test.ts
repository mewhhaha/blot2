import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("retained State witnesses template-local-state-scopes sync", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
const witness32 = func ignored : Cell U32 => return @panic "witness called"
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witness32
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witnessf
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State witnesses template-local-state-scopes JSPI", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
const witness32 = func ignored : Cell U32 => return @panic "witness called"
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witness32
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witnessf
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State witnesses local-aliases sync", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
const witness32 = func ignored : Cell U32 => return @panic "witness called"
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let alias = witness32
    let alias_again = alias
    let computation = make alias_again
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let alias = witnessf
    let alias_again = alias
    let computation = make alias_again
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State witnesses local-aliases JSPI", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
const witness32 = func ignored : Cell U32 => return @panic "witness called"
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let alias = witness32
    let alias_again = alias
    let computation = make alias_again
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let alias = witnessf
    let alias_again = alias
    let computation = make alias_again
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State witnesses local-snapshots sync", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let captured = 41
    let witness = func ignored => return $Cell captured
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witness
    captured := 99
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let captured = 3.5
    let witness = func ignored => return $Cell captured
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witness
    captured := 199.5
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State witnesses local-snapshots JSPI", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let captured = 41
    let witness = func ignored => return $Cell captured
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witness
    captured := 99
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let captured = 3.5
    let witness = func ignored => return $Cell captured
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witness
    captured := 199.5
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State witnesses local-snapshots-called sync", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let captured = 41
    let witness = func ignored => return $Cell captured
    let make = func witness => return @computation (func () => return do:
      use current <- @state.get witness
      let $Cell stored = current
      let $Cell captured = witness ()
      break $Cell (@u32.add stored captured)
    )
    let computation = make witness
    captured := 99
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let captured = 3.5
    let witness = func ignored => return $Cell captured
    let make = func witness => return @computation (func () => return do:
      use current <- @state.get witness
      let $Cell stored = current
      let $Cell captured = witness ()
      break $Cell (@f32.add stored captured)
    )
    let computation = make witness
    captured := 199.5
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 87);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 87);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State witnesses local-snapshots-called JSPI", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let captured = 41
    let witness = func ignored => return $Cell captured
    let make = func witness => return @computation (func () => return do:
      use current <- @state.get witness
      let $Cell stored = current
      let $Cell captured = witness ()
      break $Cell (@u32.add stored captured)
    )
    let computation = make witness
    captured := 99
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let captured = 3.5
    let witness = func ignored => return $Cell captured
    let make = func witness => return @computation (func () => return do:
      use current <- @state.get witness
      let $Cell stored = current
      let $Cell captured = witness ()
      break $Cell (@f32.add stored captured)
    )
    let computation = make witness
    captured := 199.5
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 87);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 87);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State witnesses latent-never-called sync", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
type Tick is effect = { read: Unit -> U32 }
const witness32 = func ignored : Cell U32 => return do:
  use Tick.read ()
  break @panic "witness called"
const witnessf = func ignored : Cell F32 => return do:
  use Tick.read ()
  break @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witness32
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witnessf
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State witnesses latent-never-called JSPI", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
type Tick is effect = { read: Unit -> U32 }
const witness32 = func ignored : Cell U32 => return do:
  use Tick.read ()
  break @panic "witness called"
const witnessf = func ignored : Cell F32 => return do:
  use Tick.read ()
  break @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witness32
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witnessf
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State witnesses local-initializer-effects sync", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
type Count is data = $Count U32
const witness32 = func ignored : Cell U32 => return @panic "witness called"
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Count count, result) = @state.run ($Count 0) (func () => return do:
    use result32 <- @state.run ($Cell 40) (func () => return do:
      let make = func witness => return do:
        use previous_cell <- @state.get $Count
        let $Count previous = previous_cell
        use @state.set ($Count (@u32.add previous 1))
        break @computation (func () => return @state.get witness)
      use computation <- make witness32
      break handled computation
    )
    let ($Cell state32, $Cell value32) = result32
    use resultf <- @state.run ($Cell 2.5) (func () => return do:
      let make = func witness => return do:
        use previous_cell <- @state.get $Count
        let $Count previous = previous_cell
        use @state.set ($Count (@u32.add previous 1))
        break @computation (func () => return @state.get witness)
      use computation <- make witnessf
      break handled computation
    )
    let ($Cell statef, $Cell valuef) = resultf
    break @f32.add (@u32.to_f32 value32) valuef
  )
  break @f32.add result (@u32.to_f32 count)
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 44.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 44.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State witnesses local-initializer-effects JSPI", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
type Count is data = $Count U32
const witness32 = func ignored : Cell U32 => return @panic "witness called"
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Count count, result) = @state.run ($Count 0) (func () => return do:
    use result32 <- @state.run ($Cell 40) (func () => return do:
      let make = func witness => return do:
        use previous_cell <- @state.get $Count
        let $Count previous = previous_cell
        use @state.set ($Count (@u32.add previous 1))
        break @computation (func () => return @state.get witness)
      use computation <- make witness32
      break handled computation
    )
    let ($Cell state32, $Cell value32) = result32
    use resultf <- @state.run ($Cell 2.5) (func () => return do:
      let make = func witness => return do:
        use previous_cell <- @state.get $Count
        let $Count previous = previous_cell
        use @state.set ($Count (@u32.add previous 1))
        break @computation (func () => return @state.get witness)
      use computation <- make witnessf
      break handled computation
    )
    let ($Cell statef, $Cell valuef) = resultf
    break @f32.add (@u32.to_f32 value32) valuef
  )
  break @f32.add result (@u32.to_f32 count)
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 44.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 44.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State witnesses reject template-local-state-identity", async () => {
  await compileExpectedFailure(`type Cell value is data = $Cell value
const witness32 = func ignored : Cell U32 => return @panic "witness called"
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let make = func witness => return @computation (func () => return @state.get witness)
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let computation = make witness32
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let computation = make witnessf
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, "type_mismatch", undefined, { prelude: "none" });
});

Deno.test("retained State witnesses reject shared-higher-order", async () => {
  await compileExpectedFailure(`type Cell value is data = $Cell value
const witness32 = func ignored : Cell U32 => return @panic "witness called"
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let make = func witness => return @computation (func () => return @state.get witness)
  let alias = (func factory => return factory) make
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let computation = alias witness32
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let computation = alias witnessf
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, "type_mismatch", undefined, { prelude: "none" });
});

Deno.test("retained State witnesses reject wrong-input", async () => {
  await compileExpectedFailure(`type Cell value is data = $Cell value
const witness = func (value: U32) => return $Cell value
entry const answer = func () => return do:
  let ($Cell _, $Cell value) = @state.run ($Cell 40) (func () => return do:
    let make = func witness => return @computation (func () => return do:
      use @state.get witness
      break witness ()
    )
    for request in @requests (make witness):
      case request of
        complete result =>
          break result
  )
  break value
`, "type_mismatch", undefined, { prelude: "none" });
});

Deno.test("retained State witnesses reject wrong-family", async () => {
  await compileExpectedFailure(`type Cell value is data = $Cell value
type Other value is data = $Other value
const witness = func ignored : Other U32 => return @panic "witness called"
entry const answer: Unit -> U32 ! {} = func () => return do:
  let ($Cell _, $Other value) = @state.run ($Cell 40) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    for request in @requests (make witness):
      case request of
        complete result =>
          break result
  )
  break value
`, "effect_mismatch", undefined, { prelude: "none" });
});

Deno.test("retained State annotation lifetime state-annotation-scopes sync", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
const witness32 = func ignored : Cell U32 => return @panic "witness called"
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let make: a -> b = func witness => return @computation (func () => return @state.get witness)
    let computation = make witness32
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let make: a -> b = func witness => return @computation (func () => return @state.get witness)
    let computation = make witnessf
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State annotation lifetime state-annotation-scopes JSPI", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
const witness32 = func ignored : Cell U32 => return @panic "witness called"
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let make: a -> b = func witness => return @computation (func () => return @state.get witness)
    let computation = make witness32
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let make: a -> b = func witness => return @computation (func () => return @state.get witness)
    let computation = make witnessf
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State annotation lifetime state-annotation-shared sync", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
const witness32 = func ignored : Cell U32 => return @panic "witness called"
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let make: a -> b = func witness => return @computation (func () => return @state.get witness)
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let computation = make witness32
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let computation = make witnessf
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State annotation lifetime state-annotation-shared JSPI", async () => {
  await compileAndRun(`type Cell value is data = $Cell value
const witness32 = func ignored : Cell U32 => return @panic "witness called"
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let make: a -> b = func witness => return @computation (func () => return @state.get witness)
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let computation = make witness32
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let computation = make witnessf
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State annotation lifetime plain-annotation-scope sync", async () => {
  await compileAndRun(`const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let make: a -> b = func value => return @computation (func () => return value)
  let integer = handled (make 40)
  let fraction = handled (make 2.5)
  break @f32.add (@u32.to_f32 integer) fraction
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State annotation lifetime plain-annotation-scope JSPI", async () => {
  await compileAndRun(`const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let make: a -> b = func value => return @computation (func () => return value)
  let integer = handled (make 40)
  let fraction = handled (make 2.5)
  break @f32.add (@u32.to_f32 integer) fraction
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State annotation lifetime where-annotation-scope sync", async () => {
  await compileAndRun(`const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let make: a -> b where { type_rep a } = func value => return @computation (func () => return value)
  let integer = handled (make 40)
  let fraction = handled (make 2.5)
  break @f32.add (@u32.to_f32 integer) fraction
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(guest.call("answer", null), 42.5);
  }, { prelude: "none", asynchronous: false });
});

Deno.test("retained State annotation lifetime where-annotation-scope JSPI", async () => {
  await compileAndRun(`const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let make: a -> b where { type_rep a } = func value => return @computation (func () => return value)
  let integer = handled (make 40)
  let fraction = handled (make 2.5)
  break @f32.add (@u32.to_f32 integer) fraction
entry const folded = answer ()
`, async guest => {
    equal(guest.read("folded"), 42.5);
    for (let count = 0; count < 100; count++) equal(await guest.callAsync("answer", null), 42.5);
  }, { prelude: "none", asynchronous: true });
});

Deno.test("retained State selected proof rejects plain-shared-scope", async () => {
  await compileExpectedFailure(`const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let make = func value => return @computation (func () => return value)
  let integer = handled (make 40)
  let fraction = handled (make 2.5)
  break @f32.add (@u32.to_f32 integer) fraction
entry const folded = answer ()
`, "type_mismatch", undefined, { prelude: "none" });
});

Deno.test("retained State selected proof rejects unmet-qualifier", async () => {
  await compileExpectedFailure(`type Cell value is data = $Cell value
const witness32: a -> Cell U32 where { associated "missing" Bool Bool Bool } = func ignored => return @panic "witness called"
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witness32
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let make = func witness => return @computation (func () => return @state.get witness)
    let computation = make witnessf
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, "missing_associated", undefined, { prelude: "none", span: [640, 651] });
});

Deno.test("retained State selected proof rejects invoked-missing-member", async () => {
  await compileExpectedFailure(`type Cell value is data = $Cell value
const witness32 = func ignored : Cell U32 => return $Cell ignored.missing
const witnessf = func ignored : Cell F32 => return @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let make = func witness => return @computation (func () => return do:
      use @state.get witness
      break witness ()
    )
    let computation = make witness32
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let make = func witness => return @computation (func () => return do:
      use @state.get witness
      break witness ()
    )
    let computation = make witnessf
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, "missing_member", undefined, { prelude: "none" });
});

Deno.test("retained State selected proof rejects invoked-extra-effect", async () => {
  await compileExpectedFailure(`type Cell value is data = $Cell value
type Tick is effect = { read: Unit -> U32 }
const witness32 = func ignored : Cell U32 => return do:
  use Tick.read ()
  break @panic "witness called"
const witnessf = func ignored : Cell F32 => return do:
  use Tick.read ()
  break @panic "witness called"
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      complete value =>
        break value
entry const answer: Unit -> F32 ! {} = func () => return do:
  let ($Cell state32, $Cell value32) = @state.run ($Cell 40) (func () => return do:
    let make = func witness => return @computation (func () => return do:
      use @state.get witness
      break witness ()
    )
    let computation = make witness32
    break handled computation
  )
  let ($Cell statef, $Cell valuef) = @state.run ($Cell 2.5) (func () => return do:
    let make = func witness => return @computation (func () => return do:
      use @state.get witness
      break witness ()
    )
    let computation = make witnessf
    break handled computation
  )
  break @f32.add (@u32.to_f32 value32) valuef
entry const folded = answer ()
`, "let_effect", undefined, { prelude: "none" });
});
