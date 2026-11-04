import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("qualified calls prove named aliases and generic local aliases separately at each use", async () => {
  await compileAndRun(
    `
const twice: a -> a where { associated "add" a a a } = func value => return value + value
const alias = twice
entry const answer = func () => return do:
  let local = alias
  let integer = local 20
  break @u32.add integer (@f32.to_u32 (local 1.0))
`,
    (guest) => equal(guest.call("answer", null), 42),
    { prelude: "std/prelude.blot" },
  );
  await compileAndRun(
    `
const twice: a -> a where { associated "add" a a a } = func value => return value + value
entry const answer = func () => return do:
  let selected = case true of
    true => twice
    false => twice
  break selected 21
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
      'const identity=func value=> return value\nentry const answer: U32->U32 where {associated "missing" Bool Bool Bool}=identity\n',
      'entry const answer=func()=> return do:\n  let unused:U32 where {associated "missing" Bool Bool Bool}=42\n  break 42\n',
      'const identity=func value=> return value\nentry const answer=func()=> return do:\n  let restricted:a->a where {associated "missing" Bool Bool Bool}=identity\n  break restricted 42\n',
      'const make=func()=> return do:\n  let restricted:a->a where {associated "missing" Bool Bool Bool}=func value=> return value\n  break restricted\nentry const answer=func()=> return (make ()) 42\n',
    ]
  ) await compileExpectedFailure(source, "missing_associated");
  await compileAndRun(
    `
const unused: a -> a where { associated "missing" a a a } = func value => return @panic "uncalled"
entry const answer = func () => return do:
  let untouched: U32 -> U32 where { associated "missing" Bool Bool Bool } = func value => return @panic "uncalled"
  break 42
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
});
Deno.test("qualified physical fields cannot be supplied by methods and keep member ambiguity", async () => {
  await compileAndRun(
    `
type Box is data = $Box {first: U32}
const first: a -> b where { field "first" a b } = func value => return value.first
entry const answer = func () => return first ($Box {first: 42})
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
  await compileExpectedFailure(
    `
type Box is data = $Box U32
const Box.first = func (box: Box) => return 42
const unchanged: a -> a where { field "first" a U32 } = func value => return value
entry const answer = func () => return do:
  let $Box number = unchanged ($Box 42)
  break number
`,
    "missing_field",
  );
  await compileExpectedFailure(
    `
type Box is data = $Box {first: U32}
const Box.first = func (box: Box) => return 42
const unchanged: a -> a where { field "first" a U32 } = func value => return value
entry const answer = func () => return do:
  let $Box {first} = unchanged ($Box {first:42})
  break first
`,
    "ambiguous_member",
  );
});
Deno.test("qualified invocation rows retain multiset counts and reject independent representation holes", async () => {
  for (
    const source of [
      "entry const answer:U32 where {type_rep a}=42\n",
      "entry const answer:U32 where {effect_rep ! {|e}}=42\n",
      "entry const answer=func()=> return do:\n  let unused:U32 where {effect_rep ! {|e}}=42\n  break 42\n",
    ]
  ) await compileExpectedFailure(source, "ambiguous_qualified");
  await compileExpectedFailure(
    "const identity:a->a where {effect_rep ! {|e}}=func value=> return value\nentry const answer=func()=> return identity 42\n",
    "ambiguous_qualified",
  );
  await compileExpectedFailure(
    "const identity:a->a where {type_rep b}=func value=> return value\nentry const answer=func()=> return identity 42\n",
    "ambiguous_qualified",
  );
  const primitiveClause = 'type Tick is effect=Unit->Unit\nconst identity:a->a where {associated "add" U32 U32 U32 ! {Tick}}=func value=> return value\nentry const answer=func()=> return identity 42\n';
  await compileExpectedFailure(primitiveClause, "missing_associated", undefined, { prelude: "none" });
  await compileExpectedFailure(primitiveClause, "effect_mismatch", undefined, { prelude: "std/prelude.blot" });
  await compileAndRun(
    `
type Tick is effect = Unit -> Unit
type Box is data = $Box U32
const Box.add: Box -> (Box -> Box ! {Tick, Tick}) = func (left: Box) => return func (right: Box) => return do:
  use Tick ()
  use Tick ()
  break $Box 42
const twice: Box -> Box ! {Tick, Tick} where { associated "add" Box Box Box ! {Tick, Tick} } = func value => return value + value
entry const answer = func () => return do (@effect.provider Tick (func () => return ())):
  break do (@effect.provider Tick (func () => return ())):
    use boxed <- twice ($Box 21)
    let $Box result = boxed
    break result
`,
    (guest) => equal(guest.call("answer", null), 42),
  );
});
Deno.test("captured generic local callable templates retain their environment at separate concrete uses", async () => {
  await compileAndRun(
    `
type Cell value is data = $Cell value
entry const answer = func (offset: U32) => return do:
  let read = func witness => return do:
    let next = @u32.add offset 1
    if @u32.lt next offset:
      break @panic "unreachable"
    break @state.get witness
  let (_, $Cell integer) = @state.run ($Cell offset) (func () => return
    read (func ignored : Cell U32 => return @panic "unused integer witness"))
  let (_, $Cell fraction) = @state.run ($Cell 2.5) (func () => return
    read (func ignored : Cell F32 => return @panic "unused fraction witness"))
  break @f32.add (@u32.to_f32 integer) fraction
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
