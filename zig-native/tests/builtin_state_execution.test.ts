import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("builtin State keeps nominal instances separate and never invokes type witnesses", async () => {
  await compileAndRun(`
data Cell value = #Cell value
const read = fn witness => @state.get witness
const write = fn value => @state.set value
const advance = fn () => do:
  use integer <- read (fn () => #Cell 0)
  let #Cell count = integer
  use fraction <- read (fn () => #Cell 0.0)
  let #Cell amount = fraction
  use write (#Cell (count + 1))
  use write (#Cell (amount + 0.5))
  return count
const answer = fn () => do:
  let (#Cell count, (#Cell amount, previous)) = @state.run (#Cell 40) (fn () =>
    @state.run (#Cell 1.0) advance)
  return U32.to_f32 count + amount + U32.to_f32 previous
entry const run = fn () => answer ()
entry const expected = answer ()
entry const witness = fn () => do:
  let (_, #Cell result) = @state.run (#Cell 42) (fn () =>
    read (fn ignored -> Cell U32 => @panic "type witnesses must never be called"))
  return result
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
entry const run = fn () => do:
  let read_local = fn witness => @state.get witness
  let (_, #Cell integer) = @state.run (#Cell 40) (fn () =>
    read_local (fn ignored -> Cell U32 => @panic "integer witness called"))
  let (_, #Cell fraction) = @state.run (#Cell 2.5) (fn () =>
    read_local (fn ignored -> Cell F32 => @panic "floating witness called"))
  return @f32.add (@u32.to_f32 integer) fraction
`, guest => equal(guest.call("run", null), 42.5));
});

Deno.test("builtin State readers and writers retain residual effects and shadow exact instances", async () => {
  await compileAndRun(`
data Count = #Count U32
effect Notice: U32 -> Unit
const read = fn witness => @state.get witness
const write = fn value => @state.set value
const reader = fn witness => fn implementation => fn action => @state.reader witness implementation action
const writer = fn witness => fn implementation => fn action => @state.writer witness implementation action
entry const run = fn () => do (@effect.provider Notice (fn value => ())):
  return reader #Count (fn () => #Count 7) (fn () => do:
    use cell_before <- read #Count
    let #Count before = cell_before
    use outcome <- @state.run (#Count 41) (fn () => do:
      use cell_value <- read #Count
      let #Count value = cell_value
      use write (#Count (@u32.add value 1))
      use Notice value
      return value)
    let (_, nested) = outcome
    use cell_after <- read #Count
    let #Count after = cell_after
    return @u32.add before (@u32.add nested after))
entry const written = fn () => do:
  let (final, _) = @state.run (#Count 0) (fn () => writer #Count (fn value => @state.set value) (fn () =>
    @state.set (#Count 42)))
  let #Count result = final
  return result
`, guest => {
    for (let count = 0; count < 50; count++) {
      equal(guest.call("run", null), 55);
      equal(guest.call("written", null), 42);
    }
  });
});

Deno.test("builtin State rejects unhandled and mismatched instances without publishing Wasm", async () => {
  await compileExpectedFailure(`data Count = #Count U32
const invalid: Unit -> Count = fn () => @state.get #Count
entry const run = fn () => 42
`, "effect_mismatch");
  await compileExpectedFailure(`data Cell value = #Cell value
entry const run = fn () => @state.run (#Cell 42) (fn () => @state.get (fn () => #Cell 0.0))
`, "entry_type");
});
