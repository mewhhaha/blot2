import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { readMemoryProfile } from "../../compiler/memory_profile.ts";

const helper = `type Row is data = #Blank | #Present {value: U32, other: U32}
const row = fn (i: U32) -> Row => if i % 2 == 0 then #Blank else #Present {value: i, other: i + 1}
const lane = fn (i: U32) => fn (j: U32) => i * 24 + j
const flatten = fn chunks => @array.flatten chunks
`;
const source = `import * as array from "std/array"
import {Row, Blank, Present, row, lane, flatten} from "./helper"
type Command is data = #Command {lanes: Array U32}
entry const variants = fn (count: U32) => do:
  let values = array.generate count row
  let sum = 0
  for value in values:
    sum := self + case value of
      #Blank => 0
      #Present (a, b) => a + b
  break sum
entry const pipeline = fn (count: U32) => do:
  let commands = array.generate count (fn i => #Command {lanes: array.generate 24 (fn j => lane i j)})
  let chunks = array.map (fn command => command.lanes) commands
  let values = flatten chunks
  break array.fold_left (fn sum value => sum + value) 0 values
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`runtime proofs and origins follow imported body edit revert and restart (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-runtime-revisions-",
    });
    const entry = `${directory}/main.blot`,
      dependency = `${directory}/helper.blot`;
    const options = {
      executable: Deno.args[0],
      entry,
      codegenTier,
      prelude: new URL("../../std/prelude.blot", import.meta.url),
      stdRoot: new URL("../../std", import.meta.url),
      cacheDirectory: `${directory}/cache`,
      profileMemory: true,
    };
    const check = async (bytes: Uint8Array<ArrayBuffer>, delta: number) => {
      const guest = await instantiateGuest(bytes);
      try {
        assert.equal(guest.call("variants", 32), 528);
        assert.equal(guest.call("pipeline", 32), 768 * 767 / 2 + 768 * delta);
      } finally {
        guest.dispose();
      }
      const module = new WebAssembly.Module(bytes);
      const raw = new WebAssembly.Instance(module).exports;
      (raw["blot:ownership_enter"] as CallableFunction)();
      (raw.variants as CallableFunction)(32);
      (raw["blot:ownership_leave"] as CallableFunction)(0);
      const report = readMemoryProfile(module, raw);
      assert(report.complete);
      assert(report.sites.some((site) => site.filename === dependency));
      return report;
    };
    let finalBytes: Uint8Array<ArrayBuffer> | undefined;
    const retained = await createZigProjectCompiler(options);
    try {
      for (const delta of [0, 1, 0]) {
        const edited = delta
          ? helper.replace("i * 24 + j", "i * 24 + j + 1")
          : helper;
        const sources = { [entry]: source, [dependency]: edited };
        const built = await retained.build({ sources });
        assert(built.success, JSON.stringify(built));
        await check(built.bytes, delta);
        const fresh = await createZigProjectCompiler({
          ...options,
          cacheDirectory: false,
        });
        try {
          const clean = await fresh.build({ sources });
          assert(clean.success, JSON.stringify(clean));
          assert.deepEqual(
            built.bytes,
            clean.bytes,
            "retained proof and provenance match fresh emission",
          );
        } finally {
          await fresh.dispose();
        }
        finalBytes = built.bytes;
      }
    } finally {
      await retained.dispose();
    }
    try {
      const restarted = await createZigProjectCompiler(options);
      try {
        const built = await restarted.build({
          sources: { [entry]: source, [dependency]: helper },
        });
        assert(built.success, JSON.stringify(built));
        assert.deepEqual(built.bytes, finalBytes);
        await check(built.bytes, 0);
      } finally {
        await restarted.dispose();
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
