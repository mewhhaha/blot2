import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const producer = (offset: number) =>
  `opaque type Token = F32
private const offset = ${offset}.0
const make: F32 -> Token = fn value => #Token (@f32.add value offset)
const read: Token -> F32 = fn (#Token value) => value
const Token.observe = read
private const Token.hidden = read
private const Token.add = fn left => fn right => #Token (@f32.add (read left) (read right))
const internal = fn value => read (@type.call "add" (make value) (make value))
`;
const main = `import {Token, make} from "./tokens"
import * as facade from "./outward"
type Alias = facade.Ticket
const pass: Token -> Alias = fn value => value
entry const answer = fn (value: F32) => facade.read (pass (make value))
entry const associated = fn (value: F32) => (make value).observe
`;
async function run(bytes: Uint8Array<ArrayBuffer>, expected: number) {
  const guest = await instantiateGuest(bytes);
  try {
    assert.equal(guest.call("answer", 40), expected);
    assert.equal(guest.call("associated", 40), expected);
  } finally {
    guest.dispose();
  }
}

Deno.test("opaque source compiled forwarding and checkpoints keep privacy through failed edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-opacity-" });
  const entry = `${directory}/main.blot`;
  const tokens = `${directory}/tokens.blot`;
  const bundle = `${directory}/deps.blotdep`;
  try {
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(tokens, producer(2));
    await Deno.writeTextFile(
      `${directory}/facade.blot`,
      'export {Token as Ticket, make, read} from "./tokens"\n',
    );
    await Deno.writeTextFile(
      `${directory}/outward.blot`,
      'export {Ticket, make, read} from "./facade"\n',
    );
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, bundle, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    const options = { executable, entry, prelude: null };
    const source = await createZigProjectCompiler(options);
    const compiled = await createZigProjectCompiler({
      ...options,
      dependencies: bundle,
    });
    let checkpoint: Uint8Array<ArrayBuffer>;
    let expected: Uint8Array<ArrayBuffer>;
    try {
      const first = await source.build();
      const cached = await compiled.build();
      assert(first.success, JSON.stringify(first));
      assert(cached.success, JSON.stringify(cached));
      assert(cached.stats.cachedModules > 0);
      assert.deepEqual(cached.bytes, first.bytes);
      await run(cached.bytes, 42);
      checkpoint = await compiled.exportCheckpoint();
      expected = first.bytes;
      for (
        const rejected of [
          main.replace(
            "facade.read (pass (make value))",
            "(make value).hidden",
          ),
          main.replace("facade.read (pass (make value))", "(make value).value"),
          main.replace(
            "facade.read (pass (make value))",
            "facade.read (combine (make value))",
          ) + 'const combine = fn value => @type.call "add" value value\n',
          main.replace(
            "facade.read (pass (make value))",
            "reveal (make value)",
          ) + "const reveal = fn value => value.hidden\n",
          'import {Token} from "./tokens"\nentry const answer = #Token 42.0\n',
        ]
      ) {
        const fromSource = await source.build({
          sources: { [entry]: rejected },
        });
        const fromArchive = await compiled.build({
          sources: { [entry]: rejected },
        });
        assert(!fromSource.success && !fromArchive.success);
        assert.deepEqual(fromArchive.diagnostics, fromSource.diagnostics);
        assert.deepEqual(await compiled.exportCheckpoint(), checkpoint);
      }
      for (
        const changed of [
          producer(3),
          `private const inserted = 7\n${producer(2)}`,
        ]
      ) {
        const retained = await source.build({
          sources: { [tokens]: changed, [entry]: main },
        });
        const fresh = await createZigProjectCompiler(options);
        try {
          const rebuilt = await fresh.build({
            sources: { [tokens]: changed, [entry]: main },
          });
          assert(
            retained.success && rebuilt.success,
            JSON.stringify({ retained, rebuilt }),
          );
          assert.deepEqual(retained.bytes, rebuilt.bytes);
          let answer = 42;
          if (changed === producer(3)) answer = 43;
          await run(retained.bytes, answer);
        } finally {
          await fresh.dispose();
        }
      }
      const recovered = await compiled.build({ sources: { [entry]: main } });
      assert(recovered.success);
      assert.deepEqual(recovered.bytes, expected);
    } finally {
      await source.dispose();
      await compiled.dispose();
    }
    const restored = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      dependencies: bundle,
      checkpoint: checkpoint!,
    });
    try {
      const built = await restored.build();
      assert(built.success, JSON.stringify(built));
      assert.deepEqual(built.bytes, expected!);
      await run(built.bytes, 42);
    } finally {
      await restored.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("opaque generic field requirements cannot derive hidden producer payloads", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-opaque-field-" });
  const entry = `${directory}/main.blot`;
  try {
    await Deno.writeTextFile(
      `${directory}/library.blot`,
      "opaque type Box = {value:U32}\nconst make = fn value => #Box {value:value}\n",
    );
    await Deno.writeTextFile(
      entry,
      'import {make} from "./library"\nconst reveal = fn value => value.value\nentry const runtime = fn (value:U32) => reveal (make value)\nentry const staged = reveal (make 42)\n',
    );
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
    });
    try {
      const built = await compiler.build();
      assert(!built.success, JSON.stringify(built));
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("opaque representation edits invalidate storage while preserving the public nominal", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-opacity-abi-" });
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const options = { executable, entry, prelude: null };
  try {
    await Deno.writeTextFile(
      entry,
      'import {make, read} from "./library"\nentry const answer = fn (value:U32) => read (make value)\nentry const folded = read (make 42)\n',
    );
    await Deno.writeTextFile(
      library,
      "opaque type Token = U32\nconst make: U32 -> Token = fn value => #Token value\nconst read: Token -> U32 = fn (#Token value) => value\n",
    );
    const retained = await createZigProjectCompiler(options);
    try {
      const scalar = await retained.build();
      assert(scalar.success, JSON.stringify(scalar));
      await Deno.writeTextFile(
        library,
        "opaque type Token = {word: U32}\nconst make: U32 -> Token = fn value => #Token {word: value}\nconst read: Token -> U32 = fn (#Token value) => value.word\n",
      );
      const reference = await retained.build();
      assert(reference.success, JSON.stringify(reference));
      const fresh = await createZigProjectCompiler(options);
      try {
        const built = await fresh.build();
        assert(built.success, JSON.stringify(built));
        assert.deepEqual(reference.bytes, built.bytes);
      } finally {
        await fresh.dispose();
      }
      const bundle = `${directory}/deps.blotdep`;
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, bundle, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(packed.success, new TextDecoder().decode(packed.stdout));
      const imported = await createZigProjectCompiler({
        ...options,
        dependencies: bundle,
      });
      try {
        const built = await imported.build();
        assert(built.success, JSON.stringify(built));
        assert.deepEqual(reference.bytes, built.bytes);
        const guest = await instantiateGuest(built.bytes);
        try {
          for (let index = 0; index < 1000; index++) {
            assert.equal(guest.call("answer", 42), 42);
          }
          assert.equal(guest.read("folded"), 42);
        } finally {
          guest.dispose();
        }
      } finally {
        await imported.dispose();
      }
    } finally {
      await retained.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
