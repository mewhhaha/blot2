import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

Deno.test("constant receipts restore growing collection frontiers across edits and failed revisions", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-constant-growth-" });
  const entry = `${directory}/main.blot`;
  const source = (sibling: string, count: number) => `
const grown: List U32 = do:
  let values = []
  for index in 0..${count}:
    values := if @u32.lt index 16 then @list.append values index else @list.prepend values index
  return values
const later = @list.prepend (@list.append grown 99) 100
entry const first = fn () => @array.from_list grown
entry const following = fn () => @array.from_list later
entry const sibling = ${sibling}
`;
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: false,
  } as const;
  const retained = await createZigProjectCompiler(options);
  try {
    const revisions = [
      ["1", 32],
      ["2", 32],
      ["3", 33],
      ["missing", 33],
      ["4", 33],
      ["5", 32],
      ["6", 32],
    ] as const;
    for (const [revision, [sibling, count]] of revisions.entries()) {
      const fresh = await createZigProjectCompiler(options);
      try {
        const sources = { [entry]: source(sibling, count) };
        const expected = await fresh.build({ sources });
        const actual = await retained.build({ sources });
        assert.equal(actual.success, expected.success);
        if (!expected.success || !actual.success) {
          assert.equal(sibling, "missing");
          assert.ok(!actual.success && !expected.success);
          assert.deepEqual(actual.diagnostics, expected.diagnostics);
          continue;
        }
        assert.deepEqual(actual.bytes, expected.bytes);
        assert.equal(
          actual.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
        if (revision === 1 || revision === 6) {
          const traffic = actual.stats.constantReceipts as Record<
            string,
            number
          >;
          assert.equal(traffic.reused, 1);
        }
        const values: number[] = [];
        for (let index = 0; index < count; index++) {
          if (index < 16) values.push(index);
          else values.unshift(index);
        }
        const guest = await instantiateGuest(actual.bytes);
        try {
          assert.deepEqual(guest.call("first", null), new Uint32Array(values));
          assert.deepEqual(
            guest.call("following", null),
            new Uint32Array([100, ...values, 99]),
          );
        } finally {
          await guest.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

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

Deno.test("enclosing constant member judgments retain exact executed authority in both tiers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-enclosing-member-",
  });
  const entry = `${directory}/main.blot`;
  const prelude = `${directory}/prelude.blot`;
  const library = "";
  await Deno.writeTextFile(
    prelude,
    library + "\nconst Array.count = fn values => @array.length values\n",
  );
  const source = (
    sibling = "1",
    seed = "2",
    delta = "0",
    receiver = "#[]",
    twice = false,
    alias = false,
  ) => {
    let method = "@u32.add seed (@array.length values)";
    let expression = `${receiver}.count`;
    for (let index = 0; index < 80; index++) {
      method = `@u32.add ${delta} (${method})`;
      expression = `@u32.add 1 (${expression})`;
    }
    method =
      `do:\n  let total = (${method})\n  for index in 0..128:\n    total := @u32.add self 1\n  return total`;
    if (twice) expression = `@u32.add (#[].count) (${expression})`;
    let prefix = "";
    if (alias) prefix = "const alias: Array U32 = #[]\n";
    return {
      [prelude]:
        `${library}\nconst seed = ${seed}\nconst Array.count = fn values => ${method}\n`,
      [entry]: `${prefix}entry const warm: U32 = #[].count
entry const enclosing: U32 = ${expression}
entry const run = fn () => enclosing
entry const sibling = ${sibling}
`,
    };
  };
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude,
        cacheDirectory: false as const,
        codegenTier,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        const revisions = [
          [source(), 210, false],
          [source("2"), 210, true],
          [source("3"), 210, true],
          [source("3", "3"), 211, false],
          [source("3", "3", "1"), 291, false],
          [source("3", "3", "1", "#[1]"), 292, false],
          [source("3", "3", "1", "#[]", true), 502, false],
          [source("3", "3", "1", "alias", false, true), 291, false],
          [source('@panic "failed"'), null, false],
          // The independent warm scalar can retain its own admitted judgment
          // while the enclosing typed alias continues ordinary evaluation.
          [source("5", "3", "1", "alias", false, true), 291, true],
          [source("4", "3", "1", "alias", false, true), 291, true],
          [source(), 210, false],
          [source("2"), 210, true],
        ] as const;
        for (const [revision, [text, answer, hit]] of revisions.entries()) {
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = text;
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.ok(!actual.success && !expected.success);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              assert.equal(answer, null, JSON.stringify(expected.diagnostics));
              continue;
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
            if (hit) {
              assert.equal(
                receipts.member_replayed,
                1,
                JSON.stringify(receipts),
              );
            }
            if (!hit) {
              assert.equal(
                receipts.member_replayed,
                0,
                `${codegenTier} revision ${revision}: ${
                  JSON.stringify(receipts)
                }`,
              );
            }
            const guest = await instantiateGuest(actual.bytes);
            try {
              assert.equal(guest.call("run", null), answer);
            } finally {
              await guest.dispose();
            }
          } finally {
            await fresh.close();
          }
        }
      } finally {
        await retained.close();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
