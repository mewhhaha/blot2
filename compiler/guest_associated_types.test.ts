import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { instantiateGuest } from "./guest.ts";
import { compile } from "./test_compile.ts";
import { createZigProjectCompiler } from "./zig_project_client.ts";

Deno.test("defined associated outputs execute nested records arrays and exact callback rows", async () => {
  const artifact = await compile(`
type Identity a is contract = { type Item = a }
type Record a is contract = { type Item = {value: Identity.Item a, items: Array (Identity.Item a)} }
type Callable f is contract = { type Run = f }
type Alias a = Record.Item a
const keep: a -> (Identity.Item a) where { Identity a, type_eq (Identity.Item a) a } = fn value => value
const relay: f -> (Callable.Run f) = fn value => value
entry const count: U32 -> U32 = fn value => do:
  let record: Alias U32 = {value: keep value, items: #[value]}
  break @u32.add record.value (@array.length record.items)
entry const run = fn (callback: Unit -> U32 ! {Foreign}) => do:
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

Deno.test("defined associated equations retain equality prerequisites at executable uses", async () => {
  const header = `type Required a is contract = { type Item = a, type_eq a U32 }
const keep: a -> (Required.Item a) where { Required a } = fn value => value
const chain: a -> U32 where { type_eq a b, type_eq b U32 } = fn value => value
`;
  const artifact = await compile(
    header + "entry const answer = fn () => chain (keep 42)\n",
  );
  const guest = await instantiateGuest(artifact.bytes);
  try {
    equal(guest.call("answer", null), 42);
  } finally {
    guest.dispose();
  }
  await rejects(
    () => compile(header + "entry const answer = fn () => keep 42.0\n"),
    /type_mismatch/,
  );
  await rejects(
    () =>
      compile(`type Source s is contract = { type Item }
entry const answer: U32 -> U32 where { Source U32 } = fn value => value
`),
    /missing_implementation/,
  );
});

Deno.test("associated equation edits preserve last good revision and checkpoint source parity", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-associated-revisions-",
  });
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const source = `import {Identity, make} from "./library"
entry const answer: Unit -> (Identity.Item U32) = fn () => make 42
`;
  const producer = `type Identity a is contract = { type Item = a }
const make: a -> (Identity.Item a) = fn value => value
`;
  await Deno.writeTextFile(entry, source);
  await Deno.writeTextFile(library, producer);
  const options = {
    executable: Deno.args[0],
    entry,
    prelude: null,
    cacheDirectory: `${directory}/cache`,
  };
  const compiler = await createZigProjectCompiler(options);
  let checkpoint: Uint8Array<ArrayBuffer>;
  let bytes: Uint8Array<ArrayBuffer>;
  try {
    const first = await compiler.build();
    ok(first.success, JSON.stringify(first));
    bytes = first.bytes;
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
    checkpoint = await compiler.exportCheckpoint();
  } finally {
    await compiler.dispose();
  }
  const restarted = await createZigProjectCompiler(options);
  const fresh = await createZigProjectCompiler({
    ...options,
    checkpoint,
    cacheDirectory: false,
  });
  try {
    const recovered = await restarted.build();
    const reference = await fresh.build();
    ok(
      recovered.success && reference.success,
      JSON.stringify([recovered, reference]),
    );
    equal(recovered.bytes, bytes);
    equal(recovered.bytes, reference.bytes);
    equal(recovered.stats.restartCacheLoaded, true);
    const guest = await instantiateGuest(recovered.bytes);
    try {
      equal(guest.call("answer", null), 42);
    } finally {
      guest.dispose();
    }
  } finally {
    await restarted.dispose();
    await fresh.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
