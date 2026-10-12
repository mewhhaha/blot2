import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

Deno.test("constant receipts retain qualified scalar and owning graphs with fresh bytes and fuel", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-constant-receipts-",
  });
  const entry = `${directory}/main.blot`;
  let expression = "1";
  for (let index = 0; index < 80; index++) {
    expression = `@u32.add 1 (${expression})`;
  }
  const source = (seed = "2", element = "40") =>
    `const seed = ${seed}
const expensive: U32 where { type_rep U32 } = do:
  let local = fn value => value
  return ${expression}
const collection = #[${
      Array.from({ length: 80 }, () => `@u32.add 0 (@u32.add 0 ${element})`)
        .join(", ")
    }]
entry const run = fn (value: U32) => @u32.add value (@u32.add expensive seed)
entry const owning = fn () => collection
`;
  const options = { executable, entry, prelude: null };
  const retained = await createZigProjectCompiler(options);
  try {
    const revisions = [
      [source(), 123, 40],
      [source("3"), 124, 40],
      [source("3", "41"), 124, 41],
      [source("missing_name"), null, null],
      [source("3"), 124, 40],
      [source(), 123, 40],
    ] as const;
    for (const [revision, [text, scalar, element]] of revisions.entries()) {
      const fresh = await createZigProjectCompiler(options);
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const actual = await retained.build({ sources });
        assert.equal(actual.success, expected.success);
        if (!actual.success || !expected.success) {
          assert.ok(!actual.success && !expected.success);
          assert.deepEqual(actual.diagnostics, expected.diagnostics);
          if (scalar !== null) console.error(expected.diagnostics);
          assert.equal(scalar, null);
          continue;
        }
        assert.deepEqual(actual.bytes, expected.bytes);
        assert.equal(
          actual.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
        if (revision === 1) {
          const traffic = actual.stats.constantReceipts as {
            [key: string]: number;
          };
          assert.ok(
            traffic.reused >= 2,
            JSON.stringify({
              actual: traffic,
              fresh: expected.stats.constantReceipts,
            }),
          );
          assert.ok(traffic.source_steps_replayed > 200);
        }
        const guest = await instantiateGuest(actual.bytes);
        try {
          assert.equal(guest.call("run", 40), scalar);
          assert.ok(element !== null);
          assert.deepEqual(
            guest.call("owning", null),
            new Uint32Array(Array.from({ length: 80 }, () => element)),
          );
        } finally {
          await guest.dispose();
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("subfloor scalars and known compound heads keep ordinary execution without receipt lookup", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-constant-floor-" });
  const entry = `${directory}/main.blot`;
  let small = "1";
  for (let index = 0; index < 52; index++) small = `@u32.add 1 (${small})`;
  let compound = "1";
  for (let index = 0; index < 80; index++) {
    compound = `@u32.add 1 (${compound})`;
  }
  const source = (sibling: number) =>
    `const small = ${small}\nconst compound = #[{ value: ${compound} }]\nentry const run = fn () => small\nentry const count = fn () => @array.length compound\nentry const sibling = ${sibling}\n`;
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: false as const,
  };
  const retained = await createZigProjectCompiler(options);
  try {
    for (const sibling of [1, 2, 1]) {
      const fresh = await createZigProjectCompiler(options);
      try {
        const sources = { [entry]: source(sibling) };
        const expected = await fresh.build({ sources });
        const actual = await retained.build({ sources });
        assert.ok(actual.success && expected.success);
        if (!actual.success || !expected.success) {
          throw new Error("compile failed");
        }
        assert.deepEqual(actual.bytes, expected.bytes);
        assert.equal(
          actual.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
        const receipts = actual.stats.constantReceipts as Record<
          string,
          number
        >;
        assert.equal(receipts.recorded, 0);
        assert.equal(receipts.lookups, 0);
        assert.equal(receipts.owned_payload_bytes, 0);
        const guest = await instantiateGuest(actual.bytes);
        try {
          assert.equal(guest.call("run", null), 53);
          assert.equal(guest.call("count", null), 1);
        } finally {
          await guest.dispose();
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});
