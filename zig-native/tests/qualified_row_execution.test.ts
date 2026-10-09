import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("qualified pure associated calls compose with ambient handled effects", async () => {
  for (const name of ["associated", "associated-direct"]) {
    const source = await Deno.readTextFile(
      new URL(`../src/qualified-row-fixtures/${name}.blot`, import.meta.url),
    );
    await compileAndRun(source, (guest) => {
      equal(guest.read("folded"), 42);
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 42);
    }, { prelude: "none" });
  }
});

Deno.test("qualified primitive associated calls preserve pure implementations through aliases", async () => {
  for (const direct of [false, true]) {
    for (const local of [false, true]) {
      const source = `type Tick is effect = Unit -> Unit
const twice: a -> a ! {Tick} where { associated "add" a a a ! {} } = fn value => do:
  use Tick ()
  return ${direct ? '@type.call "add" value value' : "value + value"}
entry const answer = fn () => do (@effect.provider Tick (fn () => ())):
  ${local ? "let alias=twice\n  return alias 21" : "return twice 21"}
entry const folded=answer ()
`;
      await compileAndRun(source, (guest) => {
        equal(guest.read("folded"), 42);
        for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 42);
      }, {
        prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
      });
    }
  }
});

Deno.test("qualified clauses still enforce exact actual implementation rows", async () => {
  for (const name of ["reject-effectful", "reject-pure"]) {
    const source = await Deno.readTextFile(
      new URL(`../src/qualified-row-fixtures/${name}.blot`, import.meta.url),
    );
    await compileExpectedFailure(source, "effect_mismatch", undefined, {
      prelude: "none",
    });
  }
});

Deno.test("dispatched written schemes retain implementation effects and unsatisfied residuals", async () => {
  await compileAndRun(
    `effect Read: Unit -> U32
type Box is data = #Box U32
const Box.twice: Box -> (Unit -> Box ! {Read}) where { associated "add" U32 U32 U32 ! {} } = fn box => fn () => do:
  let #Box value = box
  use offset <- Read ()
  return #Box (@u32.add (@type.call "add" value value) offset)
entry const answer = fn (value: U32) => do (@effect.provider Read (fn () => 1)):
  use box <- (#Box value).twice ()
  let #Box result = box
  return result
`,
    (guest) => {
      for (const value of [0, 21, 0xffff_ffff]) {
        equal(guest.call("answer", value), (value * 2 + 1) >>> 0);
      }
    },
  );
  await compileExpectedFailure(
    `type Box a is data = #Box a
const Box.twice: Box a -> Box a where { associated "add" a a a } = fn box => box
entry const answer = fn () => do:
  let #Box value = (#Box #True).twice
  return 42
`,
    "missing_associated",
  );
});
