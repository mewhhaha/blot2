import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const stdRoot = new URL("../../std/", import.meta.url).pathname;
const paths = `
import * as path from "std/path"
const position = path.make (fn source => source.position)
  (fn replacement => fn source => @record.merge source { position: replacement })
const x = path.make (fn source => source.x)
  (fn replacement => fn source => @record.merge source { x: replacement })
const position_x = path.compose position x
`;
const deepPaths = `
const inner = path.make (fn source => source.inner)
  (fn replacement => fn source => @record.merge source { inner: replacement })
const p0 = path.make (fn source => source.x)
  (fn replacement => fn source => @record.merge source { x: replacement })
${
  Array.from({ length: 12 }, (_, index) =>
    `const p${index + 1} = path.compose inner p${index}`).join("\n")
}
`;
function nestedSource(depth: number, leaf: string, callback: string): string {
  let source = leaf;
  for (let index = 0; index < depth; index++) {
    source = `{ inner: ${source}, callback: ${callback} }`;
  }
  return source;
}
const longGetter = Array.from({ length: 80 }).reduce<string>(
  (value) => `@u32.add (${value}) 1`,
  "source.x",
);

for (const asynchronous of [false, true]) {
  Deno.test(`typed paths compose beyond inlining bounds and support large returning accessors (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(
      paths + deepPaths + `
const long = path.make (fn source => do:
  if @u32.eq source.x 0:
    return 7
  return ${longGetter})
  (fn replacement => fn source => @record.merge source { x: replacement })
entry const deep = fn (input: U32) => do:
  let original = ${
        nestedSource(
          12,
          "{ x: input, callback: fn value => @u32.add value input }",
          "fn value => @u32.add value input",
        )
      }
  let changed = path.set p12 2.5 original
  return @f32.add (path.get p12 changed) (@u32.to_f32 (original.callback 2))
entry const large = fn (input: U32) => do:
  let original = { x: input, callback: fn value => @u32.add value input }
  return @u32.add input (path.get long original)
entry const closed = fn (input: U32) => path.get p12 ${
        nestedSource(12, "{ x: input, callback: #False }", "#False")
      }
entry const effects = fn (send: U32 -> U32 ! {Foreign}) => do:
  let original = ${
        nestedSource(
          12,
          "{ x: 40, callback: fn value => send value }",
          "fn value => send value",
        )
      }
  let changed = path.set p12 2.5 original
  return @f32.add (path.get p12 changed) (@u32.to_f32 (changed.callback 2))
`,
      async (guest) => {
        const call = asynchronous ? guest.callAsync : guest.call;
        assert.equal(await call("deep", 37), 41.5);
        assert.equal(await call("closed", 37), 37);
        for (const input of [0, 37, 0xffff_ffff]) {
          assert.equal(
            await call("large", input),
            input === 0 ? 7 : (input + ((input + 80) >>> 0)) >>> 0,
          );
        }
        const events: number[] = [];
        const send = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => {
            events.push(value);
            return value;
          },
        });
        assert.equal(
          await call("effects", send),
          4.5,
        );
        assert.deepEqual(events, [2]);
      },
      { prelude: "none", stdRoot, asynchronous },
    );
  });

  Deno.test(`typed paths preserve type-changing updates aliases and captures (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(
      paths + `
const wrap = path.make (fn source => source.wrapped)
  (fn replacement => fn source => @record.merge source { wrapped: replacement })
const left = path.compose (path.compose wrap position) x
const right = path.compose wrap (path.compose position x)
entry const answer = fn (input: U32) => do:
  let original: { position: { x: U32, y: U32 }, health: U32, callback: U32 -> U32 } = { position: { x: input, y: 7 }, health: 3, callback: fn value => @u32.add value input }
  let changed = path.set position_x 2.5 original
  let again = path.modify position_x (fn value => @f32.add value 0.5) changed
  return @f32.add (path.get position_x again) (@u32.to_f32 (@u32.add original.position.x again.health))
entry const captured = fn (input: U32) => do:
  let original = { position: { x: input, y: 7 }, callback: fn value => @u32.add value input }
  let changed = path.set position_x #True original
  return changed.callback 2
entry const associated = fn (input: U32) => do:
  let original = { wrapped: { position: { x: input, y: 7 }, health: 3 }, kept: 9 }
  let a = path.set left 2.5 original
  let b = path.set right 2.5 original
  return @f32.add (path.get left a) (path.get right b)
entry const whole = fn (input: U32) => path.set path.identity (@u32.add input 2) #False
entry const empty = fn (input: U32) => path.get path.identity input
`,
      async (guest) => {
        const call = asynchronous ? guest.callAsync : guest.call;
        for (const value of [0, 37, 0xffff_ffff]) {
          assert.equal(
            await call("answer", value),
            Math.fround(Math.fround((value + 3) >>> 0) + 3),
          );
          assert.equal(await call("captured", value), (value + 2) >>> 0);
          assert.equal(await call("associated", value), 5);
          assert.equal(await call("whole", value), (value + 2) >>> 0);
          assert.equal(await call("empty", value), value);
        }
      },
      { prelude: "none", stdRoot, asynchronous },
    );
  });

  Deno.test(`typed paths retain effects of callbacks in untouched fields (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(
      paths + `
entry const answer = fn (send: U32 -> U32 ! {Foreign}) => do:
  let original = { position: { x: 40, y: 7 }, callback: fn value => send value }
  let changed = path.set position_x 2.5 original
  let focus = path.get position_x changed
  return @f32.add focus (@u32.to_f32 (changed.callback 2))
`,
      async (guest) => {
        const calls: number[] = [];
        const send = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => {
            calls.push(value);
            return value;
          },
        });
        assert.equal(
          await (asynchronous ? guest.callAsync : guest.call)("answer", send),
          4.5,
        );
        assert.deepEqual(calls, [2]);
      },
      { prelude: "none", stdRoot, asynchronous },
    );
  });

  Deno.test(`path modification sequences arguments and its effectful transform once (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(
      paths + `
entry const answer = fn (send: U32 -> U32 ! {Foreign}) => do:
  use original <- do:
    return { position: { x: send 1, y: 7 }, health: 3 }
  use changed <- do:
    return path.set position_x (send 2) original
  use modified <- path.modify position_x (fn value => send value) changed
  return @u32.add modified.position.x (@u32.add original.position.x modified.health)
`,
      async (guest) => {
        const calls: number[] = [];
        const send = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => {
            calls.push(value);
            return value;
          },
        });
        assert.equal(
          await (asynchronous ? guest.callAsync : guest.call)("answer", send),
          6,
        );
        assert.deepEqual(calls, [1, 2, 2]);
      },
      { prelude: "none", stdRoot, asynchronous },
    );
  });
}

Deno.test("typed paths reject incompatible source types and effectful accessors", async () => {
  for (
    const source of [
      `import * as path from "std/path"\nconst wrong = path.make (fn (value: U32) => value) (fn replacement => fn (value: F32) => value)\nentry const answer = 42\n`,
      `import * as path from "std/path"\nconst whole = path.make (fn (value: U32) => value) (fn replacement => fn (value: U32) => replacement)\nconst boolean = path.make (fn (value: Bool) => value) (fn replacement => fn (value: Bool) => replacement)\nentry const answer = path.get (path.compose whole boolean) 0\n`,
    ]
  ) {
    await compileExpectedFailure(source, "type_mismatch", undefined, {
      prelude: "none",
      stdRoot,
    });
  }
  await compileExpectedFailure(
    `import * as path from "std/path"\neffect Read: Unit -> U32\nconst wrong = path.make (fn () => Read ()) (fn replacement => fn () => replacement)\nentry const answer = 42\n`,
    "effect_mismatch",
    undefined,
    { prelude: "none", stdRoot },
  );
  await compileExpectedFailure(
    `import * as path from "std/path"
const call = path.make (fn source => source.callback ())
  (fn replacement => fn source => @record.merge source { stored: replacement })
entry const answer = fn (send: Unit -> U32 ! {Foreign}) => path.get call { callback: send, stored: 0 }
`,
    "effect_mismatch",
    undefined,
    { prelude: "none", stdRoot },
  );
});

Deno.test("typed path dependencies and checkpoints preserve edited output and failed revision recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const dependencies = `${directory}/library.blotdep`;
  const options = {
    executable,
    entry,
    prelude: null,
    stdRoot,
    cacheDirectory: false as const,
  };
  try {
    const librarySource = paths + deepPaths;
    await Deno.writeTextFile(library, librarySource);
    await Deno.writeTextFile(
      entry,
      `import * as path from "std/path"\nimport { position_x, p4 } from "./library"\nentry const answer = fn (input: U32) => do:\n  let original = { position: { x: input, y: 7 }, health: 3, callback: fn value => @u32.add value input }\n  let changed = path.set position_x 2.5 original\n  return @f32.add (path.get position_x changed) (@u32.to_f32 original.position.x)\nentry const deep = fn (input: U32) => do:\n  let original = ${
        nestedSource(
          4,
          "{ x: input, callback: fn value => @u32.add value input }",
          "fn value => @u32.add value input",
        )
      }\n  let changed = path.set p4 2.5 original\n  return path.get p4 changed\n`,
    );
    const packed = await new Deno.Command(executable, {
      args: [
        "dependencies",
        entry,
        dependencies,
        "--prelude",
        "none",
        "--std-root",
        stdRoot,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(packed.success, new TextDecoder().decode(packed.stdout));
    const producer = await createZigProjectCompiler(options);
    let checkpoint: Uint8Array<ArrayBuffer>;
    let expected: Uint8Array<ArrayBuffer>;
    try {
      const first = await producer.build();
      assert(first.success, JSON.stringify(first));
      checkpoint = await producer.exportCheckpoint();
      expected = first.bytes;
    } finally {
      await producer.dispose();
    }
    const retained = await createZigProjectCompiler({
      ...options,
      dependencies,
      checkpoint,
    });
    try {
      const restored = await retained.build();
      assert(restored.success, JSON.stringify(restored));
      assert(restored.stats.cachedModules > 0);
      assert.deepEqual(restored.bytes, expected);
      for (const member of ["position", "missing", "position"]) {
        const sources = {
          [library]: librarySource.replace(
            "source.position",
            `source.${member}`,
          ),
        };
        const current = await retained.build({ sources });
        assert.equal(
          current.success,
          member === "position",
          JSON.stringify(current),
        );
        const fresh = await createZigProjectCompiler(options);
        try {
          const reference = await fresh.build({ sources });
          assert.equal(current.success, reference.success);
          if (current.success && reference.success) {
            assert.deepEqual(current.bytes, reference.bytes);
            const guest = await instantiateGuest(current.bytes);
            try {
              assert.equal(guest.call("answer", 40), 42.5);
              assert.equal(guest.call("deep", 40), 2.5);
            } finally {
              guest.dispose();
            }
          } else if (!current.success && !reference.success) {
            assert.deepEqual(current.diagnostics, reference.diagnostics);
          }
        } finally {
          await fresh.dispose();
        }
      }
    } finally {
      await retained.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
