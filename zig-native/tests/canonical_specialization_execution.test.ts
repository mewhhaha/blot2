import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { compileAndRun } from "./compile_helpers.ts";

function source(amount: number): string {
  return `type Box is data = #Box { value: U32 }
type Other is data = #Other { value: U32 }
const make = fn left => fn right => fn (value: U32) => @u32.add (@u32.add left.value right.value) value
const box = #Box { value: ${amount} }
const shared = make box box
const shared_again = make box box
const separate = make (#Box { value: ${amount} }) (#Box { value: ${amount} })
const separate_again = make (#Box { value: ${amount} }) (#Box { value: ${amount} })
const nominal = make (#Other { value: ${amount + 1} }) (#Other { value: ${
    amount + 1
  } })
const capture = fn captured => fn (value: U32) => captured value
const nested = capture separate_again
entry const first: U32 -> U32 = fn value => shared value
entry const again: U32 -> U32 = fn value => shared_again value
entry const fresh: U32 -> U32 = fn value => separate value
entry const equivalent: U32 -> U32 = fn value => nested value
entry const distinct: U32 -> U32 = fn value => nominal value
`;
}

Deno.test("typed specialization and principal queries preserve imported captures through relocation failure and checkpoint restart", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/dep.blot`;
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: false as const,
  };
  const main = `import {amount, other} from "./dep"\n` + source(0)
    .replaceAll("value: 0", "value: amount")
    .replaceAll("value: 1", "value: other");
  const clients: Awaited<ReturnType<typeof createZigProjectCompiler>>[] = [];
  try {
    clients.push(await createZigProjectCompiler(options));
    clients.push(
      await createZigProjectCompiler({ ...options, semanticWorkers: 4 }),
    );
    let restored: Record<string, string> = {};
    let expectedBytes: Uint8Array<ArrayBuffer> | undefined;
    for (
      const [amount, reordered] of [[20, false], [21, false], [20, true], [
        20,
        false,
      ], [20, false]] as const
    ) {
      const sources = {
        [entry]: main,
        [dependency]: `${
          reordered ? "const untouched = fn value => value\n" : ""
        }const amount = ${amount}\nconst other = ${amount + 1}\n${
          reordered ? "" : "const untouched = fn value => value\n"
        }`,
      };
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        ok(expected.success, JSON.stringify(expected));
        expectedBytes = expected.bytes;
        for (const client of clients) {
          const result = await client.build({ sources });
          ok(result.success, JSON.stringify(result));
          equal(result.bytes, expected.bytes);
          await execute(result.bytes, amount);
        }
      } finally {
        await fresh.dispose();
      }
      restored = sources;
    }
    const diagnostics = [];
    for (const client of clients) {
      const failed = await client.build({
        sources: { ...restored, [entry]: main + "const unused: U32 = false\n" },
      });
      ok(!failed.success);
      diagnostics.push(failed.diagnostics);
      const corrected = await client.build({ sources: restored });
      ok(corrected.success);
      equal(corrected.bytes, expectedBytes);
      const checkpoint = await client.exportCheckpoint();
      const restarted = await createZigProjectCompiler({
        ...options,
        checkpoint,
      });
      try {
        const result = await restarted.build({ sources: restored });
        ok(result.success);
        equal(result.bytes, expectedBytes);
        await execute(result.bytes, 20);
      } finally {
        await restarted.dispose();
      }
    }
    equal(diagnostics[0], diagnostics[1]);
  } finally {
    await Promise.all(clients.map((client) => client.dispose()));
    await Deno.remove(directory, { recursive: true });
  }
});

async function execute(bytes: Uint8Array<ArrayBuffer>, amount: number) {
  const guest = await instantiateGuest(bytes);
  try {
    for (const value of [0, 2, 0xFFFF_FFFF]) {
      for (const name of ["first", "again", "fresh", "equivalent"]) {
        equal(guest.call(name, value), (2 * amount + value) >>> 0);
      }
      equal(guest.call("distinct", value), (2 * (amount + 1) + value) >>> 0);
    }
  } finally {
    guest.dispose();
  }
}

Deno.test("canonical closure proofs preserve current aggregate captures aliases and nested callbacks in Wasm", async () => {
  await compileAndRun(source(20), (_guest, bytes) => execute(bytes, 20), {
    prelude: "none",
  });
});

Deno.test("canonical closure proofs survive retained edits rejected edits and recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
  });
  try {
    for (const amount of [20, 21, 20]) {
      const text = source(amount);
      const result = await compiler.build({ sources: { [entry]: text } });
      ok(
        result.success,
        result.success ? undefined : JSON.stringify(result.diagnostics),
      );
      await execute(result.bytes, amount);
      const invalid = await compiler.build({
        sources: {
          [entry]: text.replace("value: 20", "value: 1.5").replace(
            "value: 21",
            "value: 1.5",
          ),
        },
      });
      ok(!invalid.success);
      ok(
        invalid.diagnostics.some((diagnostic) =>
          diagnostic.code === "type_mismatch"
        ),
      );
      const recovered = await compiler.build({ sources: { [entry]: text } });
      ok(
        recovered.success,
        recovered.success ? undefined : JSON.stringify(recovered.diagnostics),
      );
      await execute(recovered.bytes, amount);
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
