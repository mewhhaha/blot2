import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { instantiateGuest } from "../../host/guest.ts";
import { compile } from "./test_compile.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

Deno.test("trait output types execute nested records arrays and exact callback rows", async () => {
  const artifact = await compile(`
type Identity a { item } is trait = { id: a -> item }
const U32.Identity: Identity U32 { item: U32 } = { id: func value => return value }
type RecordBox a = { value: Identity.item a, items: #[Identity.item a] }
const keep: a -> a.item where { Identity a } = func value => return Identity.id value
const relay: (Unit -> a ! {Foreign}) -> (Unit -> a ! {Foreign}) = func value => return value
io const count: U32 -> U32 = func (value: U32) => return do:
  let record: RecordBox U32 = { value: keep value, items: #[value] }
  break @u32.add record.value (@array.length record.items)
io const run = func (callback: Unit -> U32 ! {Foreign}) => return do:
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

Deno.test("trait output type edits preserve the last good revision", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "squid-associated-revisions-",
  });
  const entry = `${directory}/main.sq`;
  const library = `${directory}/library.sq`;
  const source = `import { Identity, make } from "./library"
io const answer: Unit -> (Identity.item U32) = func () => return make 42
`;
  const producer = `type Identity a { item } is trait = { id: a -> item }
const U32.Identity: Identity U32 { item: U32 } = { id: func value => return value }
const make: a -> a.item where { Identity a } = func value => return Identity.id value
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
          "{ item: U32 }",
          "{ item: Identity.item U32 }",
        ),
      },
    });
    ok(!broken.success);
    equal(broken.revision, first.revision);
    ok(
      broken.diagnostics.some((issue) =>
        issue.code === "recursive_associated_type" ||
        issue.code === "invalid_constraint"
      ),
      JSON.stringify(broken.diagnostics),
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
