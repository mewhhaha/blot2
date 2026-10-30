import { deepStrictEqual as equal, rejects } from "node:assert/strict";
import { instantiateGuest } from "./guest.ts";
import { compile } from "./test_compile.ts";

const source =
  `type Source s is contract = { type Item, const first: s -> (Source.Item s) }
impl ArraySource a : Source (Array a) = { type Item = a, const first = func values => return @array.get values 0 }
`;

for (
  const [name, body, input, expected] of [
    [
      "direct scalar",
      "entry const answer = func (value: U32) => return Source.first #[value]",
      42,
      42,
    ],
    [
      "generic given",
      "const read: s -> (Source.Item s) where { Source s } = func values => return Source.first values\nentry const answer = func (value: U32) => return read #[value]",
      42,
      42,
    ],
    [
      "reference",
      "entry const answer = func (value: Array U32) => return Source.first #[value]",
      new Uint32Array([20, 22]),
      new Uint32Array([20, 22]),
    ],
    [
      "callback",
      "entry const answer = func (value: U32) => return do:\n  let selected: (Array U32) -> U32 = Source.first\n  break selected #[value]",
      42,
      42,
    ],
  ] as const
) {
  Deno.test(`implementation selected methods execute ${name}`, async () => {
    const artifact = await compile(source + body + "\n");
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("answer", input), expected);
    } finally {
      guest.dispose();
    }
  });
}

Deno.test("implementation witness proofs preserve anonymous callback rows without executing prerequisites", async () => {
  const artifact = await compile(`type Token a is data = #Token a
const Token.add = func (left: Token a) => return func (right: Token a) => return case left of
  #Token witness => @state.reader witness (func () => return @panic "proof executed") (func () => return do:
    use unused <- @state.get witness
    break left)
type Source s is contract = { associated "add" s s s ! {}, type Item, const first: s -> (Source.Item s) }
impl TokenSource a : Source (Token a) = { type Item = U32, const first = func value => return 42 }
entry const answer: Unit -> U32 = func () => return Source.first (#Token (func () : U32 => return 7))
`);
  const guest = await instantiateGuest(artifact.bytes);
  try {
    equal(guest.call("answer", null), 42);
  } finally {
    guest.dispose();
  }
});

Deno.test("implementation overlap and missing witnesses reject before execution", async () => {
  await rejects(
    () =>
      compile(
        source +
          `impl Other a : Source (Array a) = { type Item = a, const first = func values => return @array.get values 0 }
entry const answer = func () => return 42
`,
      ),
    /overlapping_implementation/,
  );
  await rejects(
    () =>
      compile(
        source + `entry const answer = func () => return Source.first 42
`,
      ),
    /missing_implementation/,
  );
});

Deno.test("implementation generic operation heads preserve selected callback rows", async () => {
  const artifact = await compile(
    `type State a is effect = { get: Unit -> a, set: a -> Unit }
const read: Unit -> a ! {State.get a} = func () => return State.get ()
type Callable f is contract = { type Run, const keep: f -> f }
impl Callback a : Callable (Unit -> a ! {State.get a}) = { type Run = a, const keep = func value => return value }
entry const answer: Unit -> U32 = func () => return @product.get (@effect.run State.get State.set 42 (func () => return Callable.keep read ())) 1
`,
  );
  const guest = await instantiateGuest(artifact.bytes);
  try {
    equal(guest.call("answer", null), 42);
  } finally {
    guest.dispose();
  }
});

Deno.test("implementation methods retain captures and curried argument order", async () => {
  const artifact = await compile(`const seed = 40
type Source s is contract = { type Item, const at: s -> U32 -> (Source.Item s) }
impl ArraySource a : Source (Array a) = { type Item = a, const at = func values => return func index => return @array.get values index }
entry const answer = func (value: U32) => return Source.at #[seed, value] 1
`);
  const guest = await instantiateGuest(artifact.bytes);
  try {
    equal(guest.call("answer", 42), 42);
  } finally {
    guest.dispose();
  }
});

Deno.test("implementation complete prerequisite chains normalize nested arrays", async () => {
  const artifact = await compile(
    `type Source s is contract = { type Item, const first: s -> (Source.Item s) }
impl Scalar : Source U32 = { type Item = U32, const first = func value => return value }
impl ArraySource a : Source (Array a) where { Source a } = { type Item = Source.Item a, const first = func values => return Source.first (@array.get values 0) }
entry const answer = func (value: U32) => return Source.first #[#[value]]
`,
  );
  const guest = await instantiateGuest(artifact.bytes);
  try {
    equal(guest.call("answer", 42), 42);
  } finally {
    guest.dispose();
  }
});

for (const asynchronous of [false, true]) {
  Deno.test(`implementation selected Foreign method preserves callback order (${asynchronous})`, async () => {
    const artifact = await compile(
      `type Callable f is contract = { type Run, const run: f -> (Unit -> (Callable.Run f) ! {Foreign}) }
impl Callback a : Callable (Unit -> a ! {Foreign}) = { type Run = a, const run = func callback => return func () => return do:
  use value <- callback ()
  break value }
entry const answer = func (callback: Unit -> U32 ! {Foreign}) => return do:
  use first <- Callable.run callback ()
  use second <- Callable.run callback ()
  break @u32.add first second
`,
    );
    const guest = await instantiateGuest(artifact.bytes, { asynchronous });
    const seen: number[] = [];
    const callback = () => {
      const result = 20 + seen.length * 2;
      seen.push(result);
      return result;
    };
    let capability;
    if (asynchronous) {
      capability = guest.capabilityAsync({
        parameter: "Unit",
        result: "U32",
        call: () => Promise.resolve(callback()),
      });
    } else {
      capability = guest.capability({
        parameter: "Unit",
        result: "U32",
        call: callback,
      });
    }
    try {
      let result: unknown;
      if (asynchronous) result = await guest.callAsync("answer", capability);
      else result = guest.call("answer", capability);
      equal(result, 42);
      equal(seen, [20, 22]);
    } finally {
      guest.dispose();
    }
  });
}
