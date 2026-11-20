import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url);
const producer = (offset: number) =>
  `type Token is opaque = F32
private const offset = ${offset}.0
const make: F32 -> Token = func value => return $Token (@f32.add value offset)
const read: Token -> F32 = func ($Token value) => return value
const Token.observe = read
private const Token.hidden = read
private const Token.add = func left => return func right => return $Token (@f32.add (read left) (read right))
const internal = func value => return read (@type.call "add" (make value) (make value))
`;
const main = `import {Token, make} from "./tokens"
import * as facade from "./outward"
type Alias = facade.Ticket
const pass: Token -> Alias = func value => return value
entry const answer = func (value: F32) => return facade.read (pass (make value))
entry const associated = func (value: F32) => return (make value).observe
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

Deno.test("opaque source and compiled forwarding keep privacy through failed edits", async () => {
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
    let expected: Uint8Array<ArrayBuffer>;
    try {
      const first = await source.build();
      const cached = await compiled.build();
      assert(first.success, JSON.stringify(first));
      assert(cached.success, JSON.stringify(cached));
      assert(cached.stats.cachedModules > 0);
      assert.deepEqual(cached.bytes, first.bytes);
      await run(cached.bytes, 42);
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
          ) + 'const combine = func value => return @type.call "add" value value\n',
          main.replace(
            "facade.read (pass (make value))",
            "reveal (make value)",
          ) + "const reveal = func value => return value.hidden\n",
          'import {Token} from "./tokens"\nentry const answer = $Token 42.0\n',
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
      "type Box is opaque = {value:U32}\nconst make = func value => return $Box {value:value}\n",
    );
    await Deno.writeTextFile(
      entry,
      'import {make} from "./library"\nconst reveal = func value => return value.value\nentry const runtime = func (value:U32) => return reveal (make value)\nentry const staged = reveal (make 42)\n',
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
      'import {make, read} from "./library"\nentry const answer = func (value:U32) => return read (make value)\nentry const folded = read (make 42)\n',
    );
    await Deno.writeTextFile(
      library,
      "type Token is opaque = U32\nconst make: U32 -> Token = func value => return $Token value\nconst read: Token -> U32 = func ($Token value) => return value\n",
    );
    const retained = await createZigProjectCompiler(options);
    try {
      const scalar = await retained.build();
      assert(scalar.success, JSON.stringify(scalar));
      await Deno.writeTextFile(
        library,
        "type Token is opaque = {word: U32}\nconst make: U32 -> Token = func value => return $Token {word: value}\nconst read: Token -> U32 = func ($Token value) => return value.word\n",
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

Deno.test("forwarded record layouts survive producer edits and recovery across workers", async () => {
  const dir = await Deno.makeTempDir();
  const entry = dir + "/main.blot";
  const point = dir + "/point.blot";
  const definition = (field: string, value: number) =>
    `type Point is data = $Point { other: U32, ${field}: U32 }
func make () => return $Point { other: 90, ${field}: ${value} }
`;
  const options = { executable, entry, prelude: null };
  try {
    await Deno.writeTextFile(point, definition("x", 7));
    await Deno.writeTextFile(
      dir + "/bridge.blot",
      'import { make } from "./point"\nfunc carry () => return make ()\n',
    );
    const imports: string[] = [];
    let sum = "0";
    for (let i = 0; i < 16; i++) {
      await Deno.writeTextFile(
        dir + `/r${i}.blot`,
        'import { carry } from "./bridge"\nfunc read () => return (carry ()).x\n',
      );
      imports.push(`import { read as read${i} } from "./r${i}"`);
      sum = `@u32.add (${sum}) (read${i} ())`;
    }
    await Deno.writeTextFile(
      entry,
      imports.join("\n") + "\nentry func answer (unused: U32): U32 => return " +
        sum + "\n",
    );
    const workers = await createZigProjectCompiler({
      ...options,
      frontendWorkers: 8,
      profileBackend: true,
    });
    try {
      const revisions = [["x", 7], ["x", 9], ["y", 11], ["x", 7]] as const;
      for (const [step, [field, value]] of revisions.entries()) {
        const sources = { [point]: definition(field, value) };
        const fresh = await createZigProjectCompiler({
          ...options,
          frontendWorkers: 1,
        });
        try {
          const result = await workers.build({ sources });
          const reference = await fresh.build({ sources });
          assert.equal(result.success, reference.success);
          if (field === "y") {
            assert(!result.success && !reference.success);
            assert.deepEqual(result.diagnostics, reference.diagnostics);
            continue;
          }
          if (!result.success) assert.fail(JSON.stringify(result.diagnostics));
          assert(reference.success);
          assert.deepEqual(result.bytes, reference.bytes);
          if (Deno.build.os === "linux" && step === 0) {
            const profile = result.stats.phaseProfile as {
              checking: { parallel_jobs: number };
            };
            assert.equal(profile.checking.parallel_jobs, 19);
          }
          const guest = await instantiateGuest(result.bytes);
          try {
            assert.equal(guest.call("answer", 0), value * 16);
          } finally {
            guest.dispose();
          }
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await workers.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
