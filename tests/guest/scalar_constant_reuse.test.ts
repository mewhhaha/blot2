import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

Deno.test("retained callers validate scalar constants through edits traps and reverts", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-scalar-constant-" });
  const entry = `${directory}/main.blot`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../../compiler-goose/build/blotc-goose", import.meta.url),
    entry,
    prelude: null,
  };
  const source = (offset: string, other: number) =>
    `const offset = ${offset}
const other = ${other}
entry const answer = func (x: U32) => return @u32.add (@u32.add x offset) (@u32.add offset x)
entry const unrelated = func () => return other
`;
  const retained = await createZigProjectCompiler(options);
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
        assert(result.success && expected.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, expected.bytes);
        const guest = await instantiateGuest(result.bytes);
        try {
          // Constants run at run time, so the division by zero traps at the
          // first read of `offset`.
          if (offset.includes("div")) {
            assert.throws(
              () => guest.call("answer", 1),
              WebAssembly.RuntimeError,
            );
          } else {
            assert.equal(guest.call("answer", 1), Number(offset) * 2 + 2);
          }
          assert.equal(guest.call("unrelated", null), other);
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

Deno.test("runtime body cutoff rebuilds executable and staged results through trapping revisions", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-body-cutoff-" });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/values.blot`;
  const options = {
    executable: Deno.args[0] ??
      new URL("../../compiler-goose/build/blotc-goose", import.meta.url),
    entry,
    prelude: null,
  };
  const main = `import * as values from "./values"
const unused = func (value: U32) => return @u32.sub (@u32.div value 1) 1
entry const warm = func (value: U32) => return values.adjust value
entry const answer = func (value: U32) => return @u32.add (values.adjust value) 40
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
          `const adjust = func (value: U32) => return @u32.${op} value ${amount}\n`,
      };
      const result = await retained.build({ sources });
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build({ sources });
        assert(result.success && expected.success, JSON.stringify(result));
        assert.deepEqual(result.bytes, expected.bytes);
        if (op === "div") {
          // Entry constants run at instantiation, so `folded` traps there.
          await assert.rejects(
            instantiateGuest(result.bytes),
            WebAssembly.RuntimeError,
          );
          continue;
        }
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
