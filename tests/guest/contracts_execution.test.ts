import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url);
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;

Deno.test("trait methods select caller evidence and preserve a defining module's private implementation", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    await Deno.writeTextFile(`${directory}/convert.blot`, `
type Read a is trait = { read: a -> U32 }
private const U32.Read: Read U32 = {
  read: func (value: U32) => return value + 1,
}
func generic (value: a): U32 where { Read a } => return Read.read value
func closed (value: U32): U32 => return Read.read value
`);
    await Deno.writeTextFile(entry, `
import * as convert from "./convert"
type Wrapped is data = $Wrapped U32
func doubled (value: Wrapped): U32 => return case value of
  $Wrapped number => number * 2
const Wrapped.Read: convert.Read Wrapped = {
  read: func value => return doubled value,
}
func invoke (callback: Wrapped -> U32) -> (value: Wrapped): U32 => return callback value
io run (value: U32): U32 => return convert.generic ($Wrapped value) + convert.closed value
io as_value (value: U32): U32 => return invoke convert.Read.read ($Wrapped value)
`);
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude,
    });
    try {
      const product = await compiler.build();
      ok(product.success, JSON.stringify(product));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(product.bytes, { asynchronous });
        try {
          if (asynchronous) {
            equal(await guest.callAsync("run", 42), 127);
            equal(await guest.callAsync("as_value", 42), 84);
          } else {
            equal(guest.call("run", 42), 127);
            equal(guest.call("as_value", 42), 84);
          }
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("imported and qualified traits survive retained edits, errors and serialized dependencies", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`,
    library = `${directory}/contracts.blot`;
  const bundle = `${directory}/dependencies.blotdep`;
  const librarySource = `
type Read a is trait = { read: a -> U32 }
type Action a = Unit -> a ! {| e}
const read: a -> U32 where { Read a } = func box => return Read.read box
const invoke = func (action: Action a) => return action ()
`;
  const source = `
import { Read, Action, invoke } from "./contracts"
import * as contracts from "./contracts"
type Box is data = $Box { value: U32 }
const Box.Read: Read Box = { read: func box => return box.value }
const local: a -> U32 where { Read a } = func box => return Read.read box
const qualified: a -> U32 where { contracts.Read a } = func box => return contracts.Read.read box
const call = func (action: Action U32) => return invoke action
io const answer = func () => return call (func () => return qualified ($Box { value: local ($Box { value: 42 }) }))
io const effectful = func (send: U32 -> U32 ! {Foreign}) => return call (func () => return send 41)
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
          "read: a -> U32",
          "missing: a -> U32",
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
