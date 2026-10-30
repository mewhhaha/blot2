import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("builtin State keeps nominal instances separate and never invokes type witnesses", async () => {
  await compileAndRun(`
data Cell value = #Cell value
const read = func witness => return @state.get witness
const write = func value => return @state.set value
const advance = func () => return do:
  use integer <- read (func () => return #Cell 0)
  let #Cell count = integer
  use fraction <- read (func () => return #Cell 0.0)
  let #Cell amount = fraction
  use write (#Cell (count + 1))
  use write (#Cell (amount + 0.5))
  break count
const answer = func () => return do:
  let (#Cell count, (#Cell amount, previous)) = @state.run (#Cell 40) (func () => return
    @state.run (#Cell 1.0) advance)
  break U32.to_f32 count + amount + U32.to_f32 previous
entry const run = func () => return answer ()
entry const expected = answer ()
entry const witness = func () => return do:
  let (_, #Cell result) = @state.run (#Cell 42) (func () => return
    read (func ignored : Cell U32 => return @panic "type witnesses must never be called"))
  break result
`, guest => {
    equal(guest.read("expected"), 82.5);
    for (let count = 0; count < 100; count++) {
      equal(guest.call("run", null), 82.5);
      equal(guest.call("witness", null), 42);
    }
  }, { prelude: "std/prelude.blot" });
});

Deno.test("builtin State instantiates local generic witness helpers at each use", async () => {
  await compileAndRun(`
data Cell value = #Cell value
entry const run = func () => return do:
  let read_local = func witness => return @state.get witness
  let (_, #Cell integer) = @state.run (#Cell 40) (func () => return
    read_local (func ignored : Cell U32 => return @panic "integer witness called"))
  let (_, #Cell fraction) = @state.run (#Cell 2.5) (func () => return
    read_local (func ignored : Cell F32 => return @panic "floating witness called"))
  break @f32.add (@u32.to_f32 integer) fraction
`, guest => equal(guest.call("run", null), 42.5));
});

Deno.test("builtin State readers and writers retain residual effects and shadow exact instances", async () => {
  await compileAndRun(`
data Count = #Count U32
effect Notice: U32 -> Unit
const read = func witness => return @state.get witness
const write = func value => return @state.set value
const reader = func witness => return func implementation => return func action => return @state.reader witness implementation action
const writer = func witness => return func implementation => return func action => return @state.writer witness implementation action
entry const run = func () => return do (@effect.provider Notice (func value => return ())):
  break reader #Count (func () => return #Count 7) (func () => return do:
    use cell_before <- read #Count
    let #Count before = cell_before
    use outcome <- @state.run (#Count 41) (func () => return do:
      use cell_value <- read #Count
      let #Count value = cell_value
      use write (#Count (@u32.add value 1))
      use Notice value
      break value)
    let (_, nested) = outcome
    use cell_after <- read #Count
    let #Count after = cell_after
    break @u32.add before (@u32.add nested after))
entry const written = func () => return do:
  let (final, _) = @state.run (#Count 0) (func () => return writer #Count (func value => return @state.set value) (func () => return
    @state.set (#Count 42)))
  let #Count result = final
  break result
`, guest => {
    for (let count = 0; count < 50; count++) {
      equal(guest.call("run", null), 55);
      equal(guest.call("written", null), 42);
    }
  });
});

Deno.test("builtin State rejects unhandled and mismatched instances without publishing Wasm", async () => {
  await compileExpectedFailure(`data Count = #Count U32
const invalid: Unit -> Count = func () => return @state.get #Count
entry const run = func () => return 42
`, "effect_mismatch");
  await compileExpectedFailure(`data Cell value = #Cell value
entry const run = func () => return @state.run (#Cell 42) (func () => return @state.get (func () => return #Cell 0.0))
`, "entry_type");
});
