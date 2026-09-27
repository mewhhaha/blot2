import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createNativeCompiler } from "../compiler/native.ts";
import {
  loadSourceProject,
  type SourceInput,
} from "../compiler/source_project.ts";

// Compare two separately built native compilers; this script builds neither.
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
  `const ${prefix}x = fn () => 17\nconst ${prefix}y = fn () => 25\nentry const answer = fn () => @u32.add (${prefix}x ()) (${prefix}y ())\n`;
const entry = new URL("file:///native-kernel-oracle/main.blot");
const unicodeModules = new Map([
  [
    entry.href,
    'import * as first from "./café"\nimport * as second from "./café"\nentry const answer = fn () => @u32.add (first.value ()) (second.value ())\n',
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
const witnessHelper = (body: string) => `
const helper = fn () => ${body}
const witness_matches_u32 = Type.eq (Type (helper ())) (Type 0)
entry const answer = fn () => witness_matches_u32
`;
const providerRows = `
type Left is effect = Unit -> U32
type Right is effect = Unit -> U32
const read_left = fn () => Left ()
const read_right = fn () => Right ()
entry const answer: Unit -> U32 = fn () => do (@effect.provider Left (fn () => 40)):
  return do (@effect.provider Right (fn () => 2)):
    use left <- read_left ()
    use right <- read_right ()
    return @u32.add left right
`;
const independentHelpers = `
const first = fn () => @u32.add 40 1
const second = fn () => @u32.add 1 0
entry const answer = fn () => @u32.add (first ()) (second ())
`;
interface OracleCase {
  name: string;
  source: SourceInput;
  expected?: "success" | "type_mismatch" | "effect_mismatch";
}
const cases: OracleCase[] = [
  { name: "shared prefix", source: prefixSource },
  {
    name: "long shared prefix",
    source: prefixSource.replaceAll(prefix, prefix.repeat(20)),
  },
  { name: "distinct Unicode modules", source: unicodeProject },
  {
    name: "nested polymorphism",
    source: "const id = fn x => x\nentry const answer = fn () => id 42\n",
  },
  {
    name: "product ownership",
    source: "entry const answer = fn x => (x, x)\n",
  },
  {
    name: "nested product ownership",
    source: "entry const answer = fn x => fn y => (x, y, x)\n",
  },
  { name: "array type", source: "entry const answer = fn x => [x, x, x]\n" },
  {
    name: "nominal type",
    source:
      "type Maybe<T> = Some(T) | Nothing\nentry const answer = fn x => Some x\n",
  },
  {
    name: "unification failure",
    source: "entry const answer = fn () => @u32.add True 1\n",
  },
  { name: "occurs failure", source: "entry const answer = fn x => x x\n" },
  {
    name: "effect rows",
    source: await Deno.readTextFile("examples/generic_effects.blot"),
  },
  {
    name: "records",
    source: await Deno.readTextFile("examples/records.blot"),
  },
  {
    name: "arrays",
    source: await Deno.readTextFile("examples/arrays.blot"),
  },
  {
    name: "distinct nominal type witnesses",
    source: `
type Count is data = Count U32
type Other is data = Other U32
const same = Type.eq (Type (Count 1)) (Type (Count 2))
const different = Type.eq (Type (Count 1)) (Type (Other 2))
entry const answer = fn () => case same, different of
  True, False => 42
  _, _ => 0
`,
    expected: "success",
  },
  // Adjacent revisions exercise one compiler process after its source changes.
  {
    name: "witness helper revision U32",
    source: witnessHelper("1"),
    expected: "success",
  },
  {
    name: "witness helper revision F32",
    source: witnessHelper("1.0"),
    expected: "success",
  },
  {
    name: "shared monomorphic argument conflict",
    source: `
const use_u32 = fn apply => @u32.add (apply 1) 1
const use_bool = fn apply => case apply True of
  True => 1
  False => 0
entry const answer = fn apply => @u32.add (use_u32 apply) (use_bool apply)
`,
    expected: "type_mismatch",
  },
  {
    name: "ordered helper diagnostics",
    source: independentHelpers.replace("@u32.add 40 1", "@u32.add True 1")
      .replace("@u32.add 1 0", "@u32.add 1.0 0"),
    expected: "type_mismatch",
  },
  {
    name: "independent helpers recover",
    source: independentHelpers,
    expected: "success",
  },
  {
    name: "distinct provider rows",
    source: providerRows,
    expected: "success",
  },
  {
    name: "missing second provider",
    source: providerRows.replace(
      "return do (@effect.provider Right (fn () => 2)):",
      "return do:",
    ),
    expected: "effect_mismatch",
  },
  { name: "provider rows recover", source: providerRows, expected: "success" },
  {
    name: "qualified pure invocation under Tick provider",
    source: `
type Tick is effect = Unit -> Unit
const twice: a -> a ! {Tick} where { associated "add" a a a ! {} } = fn value => do:
  use Tick ()
  return value + value
entry const answer = fn () => do (@effect.provider Tick (fn () => ())):
  return twice 21
`,
    expected: "success",
  },
  {
    name: "reached qualified alias rejects invalid invocation",
    source: `
type Tick is effect = Unit -> Unit
const twice: a -> a where { associated "add" U32 U32 U32 ! {Tick} } = fn value => value
const alias = twice
entry const answer = fn () => alias 21
`,
    expected: "effect_mismatch",
  },
  {
    name: "qualified FreeRow clones remain distinct",
    source: `
type Tick is effect = Unit -> Unit
type Box is data = Box U32
const Box.add: Box -> (Box -> Box ! {Tick}) = fn (left: Box) => fn (right: Box) => do:
  use Tick ()
  return Box 42
const twice: a -> a ! {| e} where { associated "add" a a a ! {| e} } = fn value => value + value
entry const integer = fn () => twice 21
entry const boxed = fn () => do (@effect.provider Tick (fn () => ())):
  use result <- twice (Box 21)
  let Box value = result
  return value
`,
    expected: "success",
  },
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
          if (test.expected !== undefined) {
            const observed = left as {
              success: boolean;
              error?: { code?: unknown };
            };
            if (test.expected === "success") {
              ok(observed.success, `${test.name} must compile successfully`);
            } else {
              equal(
                observed.error?.code,
                test.expected,
                `${test.name} must report ${test.expected}`,
              );
            }
          }
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
