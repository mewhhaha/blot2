import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { instantiateGuest } from "../../host/guest.ts";
import { compile } from "./test_compile.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

Deno.test("defined associated outputs execute nested records arrays and exact callback rows", async () => {
  const artifact = await compile(`
type Identity a is contract = { type Item = a }
type Record a is contract = { type Item = {value: Identity.Item a, items: Array (Identity.Item a)} }
type Callable f is contract = { type Run = f }
type Alias a = Record.Item a
const keep: a -> (Identity.Item a) where { Identity a, type_eq (Identity.Item a) a } = func value => return value
const relay: f -> (Callable.Run f) = func value => return value
entry const count: U32 -> U32 = func value => return do:
  let record: Alias U32 = {value: keep value, items: #[value]}
  break @u32.add record.value (@array.length record.items)
entry const run = func (callback: Unit -> U32 ! {Foreign}) => return do:
  let selected = relay callback
  use value <- selected ()
  break keep value
`);
  const guest = await instantiateGuest(artifact.bytes);
  try {
    equal(guest.call("count", 41), 42);
    let calls = 0;
    const callback = guest.capability({
      parameter: "Unit",
      result: "U32",
      call() {
        calls++;
        return 42;
      },
    });
    equal(guest.call("run", callback), 42);
    equal(calls, 1);
  } finally {
    guest.dispose();
  }
});

// Pending the traits redesign (tasks/LANGUAGE_COHERENCE.md C).
Deno.test.ignore(
  "defined associated equations retain equality prerequisites at executable uses",
  async () => {
    const header =
      `type Required a is contract = { type Item = a, type_eq a U32 }
const keep: a -> (Required.Item a) where { Required a } = func value => return value
const chain: a -> U32 where { type_eq a b, type_eq b U32 } = func value => return value
`;
    const artifact = await compile(
      header + "entry const answer = func () => return chain (keep 42)\n",
    );
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("answer", null), 42);
    } finally {
      guest.dispose();
    }
    await rejects(
      () =>
        compile(header + "entry const answer = func () => return keep 42.0\n"),
      /type_mismatch/,
    );
    await rejects(
      () =>
        compile(`type Source s is contract = { type Item }
entry const answer: U32 -> U32 where { Source U32 } = func value => return value
`),
      /missing_implementation/,
    );
  },
);

Deno.test("associated equation edits preserve the last good revision", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-associated-revisions-",
  });
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const source = `import {Identity, make} from "./library"
entry const answer: Unit -> (Identity.Item U32) = func () => return make 42
`;
  const producer = `type Identity a is contract = { type Item = a }
const make: a -> (Identity.Item a) = func value => return value
`;
  await Deno.writeTextFile(entry, source);
  await Deno.writeTextFile(library, producer);
  const options = {
    executable: Deno.args[0],
    entry,
    prelude: null,
  };
  const compiler = await createZigProjectCompiler(options);
  try {
    const first = await compiler.build();
    ok(first.success, JSON.stringify(first));
    const bytes = first.bytes;
    const broken = await compiler.build({
      sources: {
        [library]: producer.replace(
          "type Item = a",
          "type Item = Identity.Item a",
        ),
      },
    });
    ok(!broken.success);
    equal(broken.revision, first.revision);
    ok(
      broken.diagnostics.some((issue) =>
        issue.code === "recursive_associated_type"
      ),
    );
    const restored = await compiler.build();
    ok(restored.success, JSON.stringify(restored));
    equal(restored.bytes, bytes);
    const guest = await instantiateGuest(restored.bytes);
    try {
      equal(guest.call("answer", null), 42);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
