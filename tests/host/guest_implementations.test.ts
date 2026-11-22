import { deepStrictEqual as equal, rejects } from "node:assert/strict";
import { instantiateGuest } from "../../host/guest.ts";
import { compile } from "./test_compile.ts";

const source = `type Source s { item } is trait = { first: s -> item }
const Array.Source: Source #[a] { item: a } = { first: func values => return copy (@array.get values 0) }
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
      "const read: s -> s.item where { Source s } = func values => return Source.first values\nentry const answer = func (value: U32) => return read #[value]",
      42,
      42,
    ],
    [
      "reference",
      "entry const answer = func (value: #[U32]) => return Source.first #[value]",
      new Uint32Array([20, 22]),
      new Uint32Array([20, 22]),
    ],
    [
      "callback",
      "entry const answer = func (value: U32) => return do:\n  let selected: #[U32] -> U32 = func values => return Source.first values\n  break selected #[value]",
      42,
      42,
    ],
  ] as const
) {
  Deno.test(
    `nominal trait selected methods execute ${name}`,
    async () => {
      const artifact = await compile(source + body + "\n");
      const guest = await instantiateGuest(artifact.bytes);
      try {
        equal(guest.call("answer", input), expected);
      } finally {
        guest.dispose();
      }
    },
  );
}

Deno.test("nominal trait overlap and missing witnesses reject before execution", async () => {
  await rejects(
    () =>
      compile(
        source +
          `const Other.Source: Source #[a] { item: a } = { first: func values => return @array.get values 0 }
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

Deno.test("nominal trait methods retain captures and curried argument order", async () => {
  const artifact = await compile(`const seed = 40
type Source s { item } is trait = { at: s -> U32 -> item }
const Array.Source: Source #[a] { item: a } = { at: func values => return func index => return @array.get values index }
entry const answer = func (value: U32) => return Source.at #[seed, value] 1
`);
  const guest = await instantiateGuest(artifact.bytes);
  try {
    equal(guest.call("answer", 42), 42);
  } finally {
    guest.dispose();
  }
});

Deno.test("nominal trait prerequisite chains normalize nested arrays", async () => {
  const artifact = await compile(
    `type Source s is trait = { first: s -> U32 }
const U32.Source: Source U32 = { first: func value => return value }
const Array.Source: Source #[a] where { Source a } = { first: func values => return Source.first (@array.get values 0) }
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
