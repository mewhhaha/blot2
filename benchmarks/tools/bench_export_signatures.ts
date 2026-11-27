// Compare the original and public-annotated Ink motion module on fixed Gdev inputs.
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { gdevProject } from "../../scripts/integration/gdev_project.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const [exe, gdev, original, exported, rounds = "6"] = Deno.args;
assert(
  exported,
  "Expected compiler, Gdev root, original motion.sq, public motion.sq",
);
const count = Number(rounds);
assert(Number.isInteger(count) && count > 0);
const root = resolve(gdev);
const options = await gdevProject(root, resolve("std"), "src/main.sq", exe);
const path = resolve(root, "../ink/lib/motion.sq");
const bytesHash = async (bytes: Uint8Array<ArrayBuffer>) =>
  new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)).toHex();
const inferred = await Deno.readTextFile(original);
const published = await Deno.readTextFile(exported);
const privateResults = new Map([
  ["spring_parts", "Spring"],
  ["finite_inputs", "Bool"],
  ["valid_rates", "Bool"],
  ["finite_pair", "Bool"],
  ["spring3_parts", "Spring3"],
]);
const annotated = published.replace(
  /^private func (\w+) (.*) => return/gm,
  (_, name: string, parameters: string) => {
    const result = privateResults.get(name);
    assert(result, `Unrecognized private helper ${name}`);
    privateResults.delete(name);
    return `private func ${name} ${parameters}: ${result} => return`;
  },
);
assert.equal(privateResults.size, 0, "Missing private helpers in motion.sq");
const cases = await Promise.all(
  [inferred, published, annotated].map(async (text, id) => {
    const bytes = new TextEncoder().encode(text);
    const needle = "if x >= 88.0:";
    assert.equal(text.split(needle).length, 2);
    return {
      mode: ["inferred", "exports", "all"][id],
      text,
      edit: text.replace(needle, "if x >= 87.0:"),
      sourceHash: await bytesHash(bytes),
    };
  }),
);
const expected = new Map<string, string>();
const compilerHash = await bytesHash(await Deno.readFile(resolve(exe)));
// All six orders balance first/last position and immediate predecessors.
const orders = [
  [0, 1, 2],
  [2, 1, 0],
  [1, 2, 0],
  [0, 2, 1],
  [2, 0, 1],
  [1, 0, 2],
];
for (const workers of [1, 8]) {
  for (let round = 0; round < count; round++) {
    for (const index of orders[round % orders.length]) {
      const variant = cases[index];
      let start = performance.now();
      const client = await createZigProjectCompiler({
        ...options,
        frontendWorkers: workers,
      });
      try {
        for (const step of ["fresh", "edit"]) {
          if (step === "edit") start = performance.now();
          const source = step === "edit" ? variant.edit : variant.text;
          const result = await client.build({
            sources: { [path]: source },
            signal: AbortSignal.timeout(20_000),
          });
          const ms = performance.now() - start;
          assert(result.success, JSON.stringify(result.diagnostics));
          assert(WebAssembly.validate(result.bytes));
          const sha256 = await bytesHash(result.bytes);
          const prior = expected.get(step);
          if (prior) {
            assert.equal(sha256, prior, "Signatures changed generated Wasm");
          }
          expected.set(step, sha256);
          console.log(JSON.stringify({
            round,
            workers,
            mode: variant.mode,
            step,
            ms,
            modules: result.stats.freshModules,
            bytes: result.bytes.length,
            sha256,
            sourceHash: variant.sourceHash,
            compilerHash,
          }));
        }
      } finally {
        await client.dispose();
      }
    }
  }
}
assert.notEqual(
  expected.get("fresh"),
  expected.get("edit"),
  "Expected a reachable edit",
);
