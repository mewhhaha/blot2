import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("qualified calls prove named aliases and generic local aliases separately at each use", async () => {
  await compileAndRun(
    `
const twice: a -> a where { associated "add" a a a } = fn value => value + value
const alias = twice
entry const answer = fn () => do:
  let local = alias
  let integer = local 20
  return @u32.add integer (@f32.to_u32 (local 1.0))
`,
    (guest) => equal(guest.call("answer", null), 42),
    { prelude: "std/prelude.blot" },
  );
  await compileAndRun(
    `
const twice: a -> a where { associated "add" a a a } = fn value => value + value
entry const answer = fn () => do:
  let selected = case #True of
    #True => twice
    #False => twice
  return selected 21
`,
    (guest) => equal(guest.call("answer", null), 42),
    { prelude: "std/prelude.blot" },
  );
});
Deno.test("qualified extras survive scalar entries runtime values and function alias entries", async () => {
  for (
    const source of [
      'entry const answer: U32 where { associated "missing" Bool Bool Bool } = 42\n',
      'entry let answer: U32 where { associated "missing" Bool Bool Bool } = 42\n',
      'const identity=fn value=>value\nentry const answer: U32->U32 where {associated "missing" Bool Bool Bool}=identity\n',
      'entry const answer=fn()=>do:\n  let unused:U32 where {associated "missing" Bool Bool Bool}=42\n  return 42\n',
      'const identity=fn value=>value\nentry const answer=fn()=>do:\n  let restricted:a->a where {associated "missing" Bool Bool Bool}=identity\n  return restricted 42\n',
      'const make=fn()=>do:\n  let restricted:a->a where {associated "missing" Bool Bool Bool}=fn value=>value\n  return restricted\nentry const answer=fn()=>(make ()) 42\n',
    ]
  ) await compileExpectedFailure(source, "missing_associated");
  await compileAndRun(
    `
const unused: a -> a where { associated "missing" a a a } = fn value => @panic "uncalled"
entry const answer = fn () => do:
  let untouched: U32 -> U32 where { associated "missing" Bool Bool Bool } = fn value => @panic "uncalled"
  return 42
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
});
Deno.test("qualified physical fields cannot be supplied by methods and keep member ambiguity", async () => {
  await compileAndRun(
    `
type Box is data = #Box {first: U32}
const first: a -> b where { field "first" a b } = fn value => value.first
entry const answer = fn () => first (#Box {first: 42})
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
  await compileExpectedFailure(
    `
type Box is data = #Box U32
const Box.first = fn (box: Box) => 42
const unchanged: a -> a where { field "first" a U32 } = fn value => value
entry const answer = fn () => do:
  let #Box number = unchanged (#Box 42)
  return number
`,
    "missing_field",
  );
  await compileExpectedFailure(
    `
type Box is data = #Box {first: U32}
const Box.first = fn (box: Box) => 42
const unchanged: a -> a where { field "first" a U32 } = fn value => value
entry const answer = fn () => do:
  let #Box {first} = unchanged (#Box {first:42})
  return first
`,
    "ambiguous_member",
  );
});
Deno.test("qualified invocation rows retain multiset counts and reject independent representation holes", async () => {
  for (
    const source of [
      "entry const answer:U32 where {type_rep a}=42\n",
      "entry const answer:U32 where {effect_rep ! {|e}}=42\n",
      "entry const answer=fn()=>do:\n  let unused:U32 where {effect_rep ! {|e}}=42\n  return 42\n",
    ]
  ) await compileExpectedFailure(source, "ambiguous_qualified");
  await compileExpectedFailure(
    "const identity:a->a where {effect_rep ! {|e}}=fn value=>value\nentry const answer=fn()=>identity 42\n",
    "ambiguous_qualified",
  );
  await compileExpectedFailure(
    "const identity:a->a where {type_rep b}=fn value=>value\nentry const answer=fn()=>identity 42\n",
    "ambiguous_qualified",
  );
  const primitiveClause = 'type Tick is effect=Unit->Unit\nconst identity:a->a where {associated "add" U32 U32 U32 ! {Tick}}=fn value=>value\nentry const answer=fn()=>identity 42\n';
  await compileExpectedFailure(primitiveClause, "missing_associated", undefined, { prelude: "none" });
  await compileExpectedFailure(primitiveClause, "effect_mismatch", undefined, { prelude: "std/prelude.blot" });
  await compileAndRun(
    `
type Tick is effect = Unit -> Unit
type Box is data = #Box U32
const Box.add: Box -> (Box -> Box ! {Tick, Tick}) = fn (left: Box) => fn (right: Box) => do:
  use Tick ()
  use Tick ()
  return #Box 42
const twice: Box -> Box ! {Tick, Tick} where { associated "add" Box Box Box ! {Tick, Tick} } = fn value => value + value
entry const answer = fn () => do (@effect.provider Tick (fn () => ())):
  return do (@effect.provider Tick (fn () => ())):
    use boxed <- twice (#Box 21)
    let #Box result = boxed
    return result
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
});
Deno.test("captured generic local callable templates retain their environment at separate concrete uses", async () => {
  await compileAndRun(
    `
data Cell value = #Cell value
entry const answer = fn (offset: U32) => do:
  let read = fn witness => do:
    let next = @u32.add offset 1
    if @u32.lt next offset:
      return @panic "unreachable"
    return @state.get witness
  let (_, #Cell integer) = @state.run (#Cell offset) (fn () =>
    read (fn ignored -> Cell U32 => @panic "unused integer witness"))
  let (_, #Cell fraction) = @state.run (#Cell 2.5) (fn () =>
    read (fn ignored -> Cell F32 => @panic "unused fraction witness"))
  return @f32.add (@u32.to_f32 integer) fraction
`,
    (guest) => {
      for (let offset = 0; offset < 100; offset++) {
        equal(
          guest.call("answer", offset),
          offset + 2.5,
        );
      }
    },
  );
});
