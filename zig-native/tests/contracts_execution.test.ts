import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;

Deno.test("named contracts compose ordinary operations and shaped field requirements without sharing instances", async () => {
  await compileAndRun(
    `
type Add a is contract = { associated "add" a a a }
type Arithmetic a is contract = { Add a, associated "mul" a a a }
type Project [owner, value] is contract = { field "value" owner value }
type Box a is data = #Box { value: a }
const contract = 1
const twice: a -> a where { Arithmetic a } = fn value => value + value
const read: a -> b where { Project [a, b] } = fn box => box.value
entry const answer = fn () => twice (read (#Box { value: 21 }))
entry const fraction = fn () => twice (read (#Box { value: 1.5 }))
`,
    (guest) => {
      equal(guest.call("answer", null), 42);
      equal(guest.call("fraction", null), 3);
    },
  );
  await compileExpectedFailure(
    `
type Project [a, b] is contract = { field "value" a b }
const bad: a -> U32 where { Project [a, U32] } = fn value => value.missing
entry const answer = 42
`,
    "missing_predicate",
  );
});

Deno.test("imported and qualified contracts survive retained edits, errors and serialized dependencies", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`,
    library = `${directory}/contracts.blot`;
  const bundle = `${directory}/dependencies.blotdep`;
  const librarySource = `
type Project [owner, value] is contract = { field "value" owner value }
type Read a is contract = { Project [a, U32] }
type Action a = Unit -> a ! {| e}
const read: a -> U32 where { Read a } = fn box => box.value
const invoke = fn (action: Action a) => action ()
`;
  const source = `
import { Read, Action, invoke } from "./contracts"
import * as contracts from "./contracts"
type Box is data = #Box { value: U32 }
const local: a -> U32 where { Read a } = fn box => box.value
const qualified: a -> U32 where { contracts.Project [a, U32] } = fn box => box.value
const call = fn (action: Action U32) => invoke action
entry const answer = fn () => call (fn () => qualified (#Box { value: local (#Box { value: 42 }) }))
entry const effectful = fn (send: U32 -> U32 ! {Foreign}) => call (fn () => send 41)
`;
  await Deno.writeTextFile(library, librarySource);
  await Deno.writeTextFile(entry, source);
  const compiler = await createZigProjectCompiler({ executable, entry });
  try {
    const first = await compiler.build();
    ok(first.success, JSON.stringify(first));
    const fail = await compiler.build({
      sources: {
        [library]: librarySource.replace(
          '"value" owner value',
          '"missing" owner value',
        ),
      },
    });
    ok(!fail.success);
    equal(fail.revision, first.revision);
    const restored = await compiler.build();
    ok(restored.success, JSON.stringify(restored));
    equal(restored.bytes, first.bytes);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    ok(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    const bundled = await createZigProjectCompiler({
      executable,
      entry,
      dependencies: bundle,
    });
    try {
      const built = await bundled.build();
      ok(built.success, JSON.stringify(built));
      ok(built.stats.cachedModules > 0);
      equal(built.bytes, restored.bytes);
      const guest = await instantiateGuest(built.bytes);
      try {
        equal(guest.call("answer", null), 42);
        const send = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => value + 1,
        });
        equal(guest.call("effectful", send), 42);
      } finally {
        guest.dispose();
      }
    } finally {
      await bundled.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("a contract's invocation effects remain distinct at each use", async () => {
  await compileAndRun(
    `
type Run [owner, result] is contract = { receiver "run" owner Unit (Unit -> result ! {| e}) }
type Pure is data = #Pure U32
type Sending is data = #Sending (U32 -> U32 ! {Foreign})
const Pure.run = fn value => fn () => case value of
  #Pure number => number
const Sending.run = fn value => fn () => case value of
  #Sending send => send 41
const run: a -> b ! {| e} where { Run [a, b] } = fn value => value.run ()
entry const answer = fn () => run (#Pure 42)
entry const effectful = fn (send: U32 -> U32 ! {Foreign}) => run (#Sending send)
`,
    (guest) => {
      equal(guest.call("answer", null), 42);
      const send = guest.capability({
        parameter: "U32",
        result: "U32",
        call: (value) => value + 1,
      });
      equal(guest.call("effectful", send), 42);
    },
    { prelude },
  );
});
