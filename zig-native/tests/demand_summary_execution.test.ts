import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun, equal } from "./compile_helpers.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;

Deno.test("dynamic demand branch joins preserve first-use effects and skip traps", async () => {
  await compileAndRun(
    `
const exclusive = fn (condition: Bool) => fn ~(value: U32) =>
  if condition then @demand value else @demand value
const sequence = fn (condition: Bool) => fn ~(value: U32) =>
  @u32.add (if condition then @demand value else 0) (@demand value)
const skip = fn ~(value: U32) => if #False then @demand value else 42
entry const left = fn (host: U32 -> U32 ! {Foreign}) => exclusive #True (host 21)
entry const right = fn (host: U32 -> U32 ! {Foreign}) => exclusive #False (host 21)
entry const repeated = fn (host: U32 -> U32 ! {Foreign}) => sequence #True (host 21)
entry const skipped = fn (x: U32) => skip (@u32.div 1 x)
`,
    (guest) => {
      const calls: number[] = [];
      const host = guest.capability({
        parameter: "U32",
        result: "U32",
        call(value) {
          calls.push(value);
          return value;
        },
      });
      for (let iteration = 0; iteration < 4; iteration++) {
        equal(guest.call("left", host), 21);
        equal(guest.call("right", host), 21);
        equal(guest.call("repeated", host), 42);
        equal(guest.call("skipped", 0), 42);
      }
      assert.deepEqual(calls, Array.from({ length: 12 }, () => 21));
    },
  );
});

function body(right: boolean): string {
  let expression = "if condition then @demand value else 42";
  if (right) expression = "if condition then 42 else @demand value";
  return `const leaf = fn (condition: Bool) => fn ~(value: U32) => ${expression}\nconst forward = fn (condition: Bool) => fn ~(value: U32) => leaf condition (@demand value)\n`;
}
Deno.test("imported demand summaries follow branch moves with stable types and recover after failed revisions", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const source =
    'import { forward } from "./library"\nentry const run = fn (x: U32) => forward (@u32.eq x 0) (@u32.div 100 x)\n';
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: false as const,
  };
  try {
    await Deno.writeTextFile(entry, source);
    await Deno.writeTextFile(library, body(false));
    const retained = await createZigProjectCompiler(options);
    try {
      for (const right of [false, false, true, true, false]) {
        const sources = { [library]: body(right) };
        const current = await retained.build({ sources });
        assert(current.success, JSON.stringify(current));
        const fresh = await createZigProjectCompiler(options);
        try {
          const reference = await fresh.build({ sources });
          assert(reference.success, JSON.stringify(reference));
          assert.deepEqual(current.bytes, reference.bytes);
          const guest = await instantiateGuest(current.bytes);
          try {
            if (right) {
              equal(guest.call("run", 0), 42);
              equal(guest.call("run", 10), 10);
            } else {
              equal(guest.call("run", 10), 42);
              assert.throws(() => guest.call("run", 0));
            }
          } finally {
            guest.dispose();
          }
        } finally {
          await fresh.dispose();
        }
        const failed = await retained.build({
          sources: { [library]: "const leaf = @demand 42\n" },
        });
        assert.equal(failed.success, false);
      }
    } finally {
      await retained.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
