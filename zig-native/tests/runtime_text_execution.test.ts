import { strict as assert } from "node:assert";
import { decodeText, encodeText } from "../../compiler/text.ts";
import { compileAndRun } from "./compile_helpers.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

// One-shot emission did not freeze dependency capability contracts and missed
// this source/Core disagreement. Exercise the retained path used by Pen.
Deno.test("retained text modules preserve literal capability shapes through edits and restart", async () => {
  const root = new URL("../../", import.meta.url);
  const directory = await Deno.makeTempDir({ dir: new URL("build/", root).pathname, prefix: "retained-text-" });
  const entry = `${directory}/main.blot`;
  const words = `${directory}/words.blot`;
  const original = 'const words = fn value => if value then "Hi, 世界🙂" else ""\n';
  await Deno.writeTextFile(words, original);
  await Deno.writeTextFile(entry, `
import * as text from "std/text"
import * as words from "./words"
entry const answer = fn () => text.concat (words.words #True) (text.format #False)
`);
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable: Deno.args[0] ?? new URL("zig-native/zig-out/bin/blotc", root),
        entry, prelude: new URL("std/prelude.blot", root), stdRoot: new URL("std/", root),
        codegenTier, cacheDirectory: false as const,
      };
      const compiler = await createZigProjectCompiler(options);
      let checkpoint: Uint8Array<ArrayBuffer>;
      try {
        for (const [source, expected] of [[original, "Hi, 世界🙂false"],
          ['const words = fn value => if value then "x" else "\\n"\n', "xfalse"],
          [original, "Hi, 世界🙂false"]]) {
          const result = await compiler.build({ sources: { [words]: source } });
          assert(result.success, JSON.stringify(result));
          const guest = await instantiateGuest(result.bytes);
          try { assert.equal(decodeText(guest.call("answer", null) as Uint32Array), expected); }
          finally { guest.dispose(); }
        }
        checkpoint = await compiler.exportCheckpoint();
      } finally { await compiler.dispose(); }
      const restored = await createZigProjectCompiler({ ...options, checkpoint });
      try {
        const result = await restored.build();
        assert(result.success, JSON.stringify(result));
        const guest = await instantiateGuest(result.bytes);
        try { assert.equal(decodeText(guest.call("answer", null) as Uint32Array), "Hi, 世界🙂false"); }
        finally { guest.dispose(); }
      } finally { await restored.dispose(); }
    }
  } finally { await Deno.remove(directory, { recursive: true }); }
});

Deno.test("runtime text literals, formatting, collections and host adapters preserve Unicode scalars", async () => {
  await compileAndRun(
    `
import * as text from "std/text"
type Ticket is data = #Ticket U32
impl TicketFormat : text.Format Ticket = {
  const format = fn (#Ticket number) => text.concat "ticket " (text.from_u32 number),
}
entry const empty = fn () => ""
entry const unicode = fn () => "Hi, 世界🙂"
entry const length = fn () => Array.length "Hi, 世界🙂"
entry const same = fn () => text.equal "世界" "世界"
entry const different = fn () => text.equal "e\u0301" "é"
entry const joined = fn () => text.join ":" #["hi", "世界", "🙂"]
entry const built = fn (count: U32) => do:
  let out = text.builder ()
  for index in 0..count:
    out := text.append "x" self
  break text.finish out
entry const decimal = fn (number: U32) => text.format number
entry const custom = fn (number: U32) => text.format (#Ticket number)
entry const fixed = fn (value: F32) => case text.from_f32_fixed 2 value of
  #Some formatted => formatted
  #Nothing => "invalid"
entry const bad_precision = fn () => case text.from_f32_fixed 7 1.0 of
  #Nothing => 1
  #Some _ => 0
entry const invalid = fn (host: U32 -> Array U32 ! {Foreign}) => do:
  use input <- host 0
  break case text.from_scalars input of
    #Nothing => 0
    #Some _ => 1
entry const roundtrip = fn (host: Array U32 -> Array U32 ! {Foreign}) => do:
  use output <- host "Hi, 世界🙂"
  break output
entry const assertion = fn (host: Array U32 -> U32 ! {Foreign}) => do:
  let message = text.join "" #["expected ", text.from_u32 42, ", got ", text.from_u32 41]
  use code <- host message
  break code
`,
    (guest) => {
      assert.equal(decodeText(guest.call("empty", null) as Uint32Array), "");
      assert.equal(
        decodeText(guest.call("unicode", null) as Uint32Array),
        "Hi, 世界🙂",
      );
      assert.equal(guest.call("length", null), 7);
      assert.equal(guest.call("same", null), true);
      assert.equal(guest.call("different", null), false);
      assert.equal(
        decodeText(guest.call("joined", null) as Uint32Array),
        "hi:世界:🙂",
      );
      const built = guest.call("built", 8193) as Uint32Array;
      assert.equal(built.length, 8193);
      assert.equal(built[0], 120);
      assert.equal(built[8192], 120);
      assert(guest.memoryBytes() <= 2 * 1024 * 1024);
      for (const number of [0, 7, 42, 4294967295]) {
        assert.equal(
          decodeText(guest.call("decimal", number) as Uint32Array),
          String(number),
        );
        assert.equal(
          decodeText(guest.call("custom", number) as Uint32Array),
          `ticket ${number}`,
        );
      }
      for (
        const [value, expected] of [
          [1.25, "1.25"],
          [-2.5, "-2.50"],
          [0, "0.00"],
          [Number.POSITIVE_INFINITY, "invalid"],
          [Number.NaN, "invalid"],
          [1e30, "invalid"],
        ] as const
      ) {
        assert.equal(
          decodeText(guest.call("fixed", value) as Uint32Array),
          expected,
        );
      }
      assert.equal(guest.call("bad_precision", null), 1);
      const invalid = guest.capability({
        parameter: "U32",
        result: "Array U32",
        call: () => Uint32Array.of(0xD800),
      });
      assert.equal(guest.call("invalid", invalid), 0);
      const roundtrip = guest.capability({
        parameter: "Array U32",
        result: "Array U32",
        call: (input) => {
          assert.equal(decodeText(input as Uint32Array), "Hi, 世界🙂");
          return encodeText("↩️ 世界");
        },
      });
      assert.equal(
        decodeText(guest.call("roundtrip", roundtrip) as Uint32Array),
        "↩️ 世界",
      );
      const messages: string[] = [];
      const assertion = guest.capability({
        parameter: "Array U32",
        result: "U32",
        call: (message) => {
          messages.push(decodeText(message as Uint32Array));
          return 9;
        },
      });
      assert.equal(guest.call("assertion", assertion), 9);
      assert.deepEqual(messages, ["expected 42, got 41"]);
    },
    { stdRoot: new URL("../../std/", import.meta.url).pathname },
  );
  assert.deepEqual(encodeText(""), new Uint32Array());
  assert.deepEqual(encodeText("é🙂"), Uint32Array.of(233, 128578));
  assert.throws(() => encodeText("\uD800"), RangeError);
  for (const values of [[0xD800], [0x110000], [-1], [1.5]]) {
    assert.throws(() => decodeText(values), RangeError);
  }
});
