import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
Deno.test("shaped effects retain array record curried and empty source parameters", async () => {
  await compileAndRun(
    `
type Convert [input, output] is effect = input -> output
type Curried input => type output is effect = input -> output
type Named {input, output} is effect = input -> output
type Token () is data = #Token
type Ping () is effect = Unit -> U32
const convert = fn value => Convert value
const explicit = fn (value:a) -> b => Named {output:b,input:a} value
const curried = Curried
entry const answer = fn () => do (@effect.provider (Convert [U32,F32]) (fn value => @u32.to_f32 value)):
  return do (@effect.provider ((Curried U32) F32) (fn value => @u32.to_f32 value)):
    return do (@effect.provider (Named {output:F32,input:U32}) (fn value => @u32.to_f32 value)):
      return do (@effect.provider (Ping ()) (fn () => 42)):
        let token: Token () = #Token
        use first <- convert 20
        use second <- explicit 12
        use third <- ((Curried U32) F32) 10
        use fourth <- Ping () ()
        return @f32.add first (@f32.add second (@f32.add third (@u32.to_f32 fourth)))
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 84);
    },
    { prelude: "none" },
  );
});
Deno.test("empty runtime arrays remain operands of implicitly instantiated effects", async () => {
  await compileAndRun(
    `
type Inspect a is effect = Array a -> a
entry const answer = fn () => do (@effect.provider (Inspect U32) (fn values => @array.length values)):
  use first <- Inspect #[]
  use second <- Inspect #[1,2,3]
  return @u32.add first second
`,
    (guest) => {
      for (let i = 0; i < 100; i++) equal(guest.call("answer", null), 3);
    },
    { prelude: "none" },
  );
});
Deno.test("bare structural annotations and mismatched source argument patterns are rejected", async () => {
  for (
    const source of [
      "type Box [a,b] is data = #Box\nconst value: Box (U32,F32) = #Box\nentry const answer = 42\n",
      "type Box (a,b) is data = #Box\nconst value: Box [U32,F32] = #Box\nentry const answer = 42\n",
      "type Read is effect = Unit -> [U32,F32]\nentry const answer = 42\n",
    ]
  ) {
    await compileExpectedFailure(source, "type_argument", undefined, {
      prelude: "none",
    });
  }
});
