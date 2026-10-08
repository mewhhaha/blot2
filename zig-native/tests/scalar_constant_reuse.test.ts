import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("retained callers validate scalar constants through edits errors and reverts", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-scalar-constant-" });
  const entry = `${directory}/main.blot`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
  };
  const source = (offset: string, other: number) =>
    `const offset = ${offset}
const other = ${other}
entry const answer = fn (x: U32) => @u32.add (@u32.add x offset) (@u32.add offset x)
entry const unrelated = fn () => other
`;
  const retained = await createZigProjectCompiler(options);
  let reused = 0;
  try {
    for (
      const [offset, other] of [["21", 0], ["21", 1], ["20", 1], [
        "@u32.div 1 0",
        1,
      ], ["21", 0]] as const
    ) {
      const sources = { [entry]: source(offset, other) };
      const result = await retained.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert.equal(result.success, expected.success);
        if (offset.includes("div")) {
          assert(!result.success && !expected.success);
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert(result.success && expected.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, expected.bytes);
        assert.equal(
          result.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
        reused += (result.stats.backend as Record<string, number>)
          .reused_scalar_constants;
        const guest = await instantiateGuest(result.bytes);
        try {
          assert.equal(guest.call("answer", 1), Number(offset) * 2 + 2);
          assert.equal(guest.call("unrelated", null), other);
        } finally {
          guest.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
    assert(reused > 0);
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("runtime body cutoff rebuilds executable and staged results through failure recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-cutoff-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/values.blot`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
    entry,
    prelude: null,
  };
  const main = `import * as values from "./values"
const unused = fn (value: U32) => @u32.sub (@u32.div value 1) 1
entry const warm = fn (value: U32) => values.adjust value
entry const answer = fn (value: U32) => @u32.add (values.adjust value) 40
entry const folded: U32 = values.adjust 20
`;
  const retained = await createZigProjectCompiler(options);
  try {
    for (
      const [op, amount] of [["add", 1], ["add", 2], ["sub", 2], ["div", 0], [
        "add",
        1,
      ]] as const
    ) {
      const sources = {
        [entry]: main,
        [dependency]:
          `const adjust = fn (value: U32) => @u32.${op} value ${amount}\n`,
      };
      const result = await retained.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert.equal(result.success, expected.success);
        if (op === "div") {
          assert(!result.success && !expected.success);
          assert.deepEqual(result.diagnostics, expected.diagnostics);
          continue;
        }
        assert(result.success && expected.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, expected.bytes);
        assert.equal(
          result.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
        const guest = await instantiateGuest(result.bytes);
        try {
          const adjusted = op === "add" ? 20 + amount : 20 - amount;
          assert.equal(guest.call("warm", 20), adjusted);
          assert.equal(guest.call("answer", 20), adjusted + 40);
          assert.equal(guest.read("folded"), adjusted);
        } finally {
          guest.dispose();
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
