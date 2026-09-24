import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createNativeCompiler } from "../compiler/native.ts";
import { loadSourceProject } from "../compiler/source_project.ts";

// Compare two separately built native compilers. Run after the guarded
// transformer has produced the candidate binary; this script builds neither.
if (Deno.args.length !== 2) {
  throw new Error(
    "Usage: deno run --allow-read --allow-run scripts/native_compiler_kernels_oracle.ts BASELINE_BLOTC CANDIDATE_BLOTC",
  );
}
const [baseline, candidate] = Deno.args.map((path) =>
  pathToFileURL(resolve(path))
);

const prefix = "shared_".repeat(32);
const prefixSource =
  `const ${prefix}x = fn () => 17\nconst ${prefix}y = fn () => 25\nconst answer = fn () => @u32.add (${prefix}x ()) (${prefix}y ())\n`;
const entry = new URL("file:///native-kernel-oracle/main.blot");
const unicodeModules = new Map([
  [
    entry.href,
    'import * as first from "./café"\nimport * as second from "./café"\nconst answer = fn () => @u32.add (first.value ()) (second.value ())\n',
  ],
  [new URL("./café.blot", entry).href, "const value = fn () => 17\n"],
  [new URL("./café.blot", entry).href, "const value = fn () => 25\n"],
]);
const unicodeProject = await loadSourceProject(entry, {
  readSource: (url) => {
    const source = unicodeModules.get(url.href);
    if (source === undefined) {
      throw new Error(`Missing oracle source: ${url.href}`);
    }
    return Promise.resolve(source);
  },
});
const cases = [
  { name: "shared prefix", source: prefixSource },
  {
    name: "long shared prefix",
    source: prefixSource.replaceAll(prefix, prefix.repeat(20)),
  },
  { name: "distinct Unicode modules", source: unicodeProject },
  {
    name: "nested polymorphism",
    source: "const id = fn x => x\nconst answer = fn () => id 42\n",
  },
  { name: "product ownership", source: "const answer = fn x => (x, x)\n" },
  {
    name: "nested product ownership",
    source: "const answer = fn x => fn y => (x, y, x)\n",
  },
  { name: "array type", source: "const answer = fn x => [x, x, x]\n" },
  {
    name: "nominal type",
    source:
      "type Maybe<T> = Some(T) | Nothing\nconst answer = fn x => Some x\n",
  },
  {
    name: "unification failure",
    source: "const answer = fn () => @u32.add True 1\n",
  },
  { name: "occurs failure", source: "const answer = fn x => x x\n" },
  {
    name: "effect rows",
    source: await Deno.readTextFile("examples/generic_effects.blot"),
  },
  { name: "records", source: await Deno.readTextFile("examples/records.blot") },
  { name: "arrays", source: await Deno.readTextFile("examples/arrays.blot") },
];

function failure(error: unknown) {
  const e = error as Record<string, unknown>;
  return {
    kind: e?.constructor?.name,
    code: e?.code,
    subject: e?.subject,
    message: e?.message,
    start: e?.start,
    end: e?.end,
    origin: e?.origin,
  };
}

for (const threads of [1, 4]) {
  const a = await createNativeCompiler({ executable: baseline, threads });
  const b = await createNativeCompiler({ executable: candidate, threads });
  try {
    for (let repetition = 0; repetition < 2; repetition++) {
      for (const test of cases) {
        for (const method of ["analyze", "compile"] as const) {
          let left: unknown;
          let right: unknown;
          try {
            left = { success: true, result: await a[method](test.source) };
          } catch (error) {
            left = { success: false, error: failure(error) };
          }
          try {
            right = { success: true, result: await b[method](test.source) };
          } catch (error) {
            right = { success: false, error: failure(error) };
          }
          equal(
            right,
            left,
            `${test.name}, repeat ${repetition}, ${method}, ${threads} threads`,
          );
          if (
            method === "compile" && (right as { success?: boolean }).success
          ) {
            const bytes =
              (right as { result: { bytes: Uint8Array } }).result.bytes;
            ok(
              WebAssembly.validate(new Uint8Array(bytes)),
              `${test.name} produced invalid Wasm`,
            );
          }
        }
      }
    }
  } finally {
    await a.dispose();
    await b.dispose();
  }
  console.log(
    `Native kernel oracle matched ${
      cases.length * 2 * 2
    } operations at ${threads} threads`,
  );
}
