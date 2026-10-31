import { strict as assert } from "node:assert";
import {
  createZigProjectCompiler,
  type ZigProjectBuildResult,
} from "../compiler/zig_project_client.ts";
import { instantiateGuest } from "../compiler/guest.ts";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

// Recreated full-Ink acceptance inputs for the lost local v0/v1/v3 repros.
// Run with --before-root pointing at the exact pre-fix compiler AND its std.
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const { values } = parseArgs({
  args: Deno.args,
  options: {
    ink: { type: "string", default: resolve(root, "../ink") },
    compiler: {
      type: "string",
      default: resolve(root, "zig-native/zig-out/bin/blotc"),
    },
    output: {
      type: "string",
      default: resolve(root, "build/bench/static-capture-rows"),
    },
    "before-root": { type: "string" },
  },
});
assert(
  values["before-root"],
  "--before-root must name a pinned pre-fix checkout with a built compiler",
);
const ink = resolve(values.ink!), out = resolve(values.output!);
const beforeRoot = resolve(values["before-root"]);
await Deno.mkdir(out);
const hash = async (path: string) =>
  [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", await Deno.readFile(path)),
    ),
  ].map((x) => x.toString(16).padStart(2, "0")).join("");
const executable = resolve(values.compiler!);
const cases = [
  {
    name: "one_resource",
    builder:
      "ecs.insert_resource $Clock { tick: 0, remainder: 0.25 } (ecs.new ())",
    body:
      "  use advance (func () => return ecs.checkpoint engine) delta\n  break ()",
    expected: (x: number, _edited: boolean) => x,
  },
  {
    name: "two_resources",
    builder:
      "ecs.insert_resource ($Counter 7) (ecs.insert_resource ($Clock { tick: 0, remainder: 0.25 }) (ecs.new ()))",
    body:
      "  use advance (func () => return ecs.checkpoint engine) delta\n  use clock <- ecs.get $Clock\n  let $Clock { remainder } = clock\n  use counter <- ecs.get $Counter\n  let $Counter count = counter\n  break delta + remainder + U32.to_f32 count",
    expected: (x: number, edited: boolean) =>
      Math.fround(Math.fround(x + (edited ? .5 : .25)) + 7),
  },
  {
    name: "snapshot_resource",
    builder:
      "ecs.insert_snapshotted_resource $Clock { tick: 0, remainder: 0.25 } (ecs.new ())",
    body:
      "  use ecs.set $Clock { tick: 1, remainder: delta }\n  use advance (func () => return ecs.checkpoint engine) delta\n  use snapshot <- ecs.previous $Clock\n  let $Clock { remainder } = snapshot\n  break remainder",
    expected: (x: number, _edited: boolean) => x,
  },
];
const pins: Record<string, string> = {
  [executable]: await hash(executable),
  [new URL(import.meta.url).pathname]: await hash(
    new URL(import.meta.url).pathname,
  ),
};
async function pinTree(dir: string) {
  for await (const f of Deno.readDir(dir)) {
    const p = dir + "/" + f.name;
    if (f.isDirectory) await pinTree(p);
    else if (f.isFile && f.name.endsWith(".blot")) pins[p] = await hash(p);
  }
}
await pinTree(ink + "/lib");
await pinTree(root + "/std");
const rows: unknown[] = [];
for (const c of cases) {
  const dir = out + "/" + c.name;
  await Deno.mkdir(dir);
  const entry = dir + "/main.blot";
  const source = `import * as ecs from "ink/ecs"
type Clock is data = $Clock { tick: U32, remainder: F32 }
type Counter is data = $Counter U32
const advance = func checkpoint => return func (delta: F32) => return do:
  use checkpoint ()
  break ()
const engine = ecs.build (${c.builder})
const scoped = func engine => return func (delta: F32) => return do:
${c.body}
entry const main = func (delta: F32) => return do:
  let (_, result) = ecs.create engine (func () => return scoped engine delta)
  break ${c.name === "one_resource" ? "delta" : "result"}
`;
  await Deno.writeTextFile(entry, source);
  pins[entry] = await hash(entry);
  const edited = source.replace("remainder: 0.25", "remainder: 0.5");
  await Deno.writeTextFile(dir + "/edited.blot", edited);
  pins[dir + "/edited.blot"] = await hash(dir + "/edited.blot");
  for (const tier of ["development", "optimized"] as const) {
    const options = {
      executable,
      entry,
      imports: { "ink/": ink + "/lib/" },
      stdRoot: root + "/std",
      prelude: root + "/std/prelude.blot",
      cacheDirectory: false as const,
      codegenTier: tier,
      codegenWorkers: 1,
    };
    const compiler = await createZigProjectCompiler(options);
    try {
      const first = await compiler.build();
      assert(first.success, JSON.stringify(first));
      for (
        const [phase, text, isEdited] of [["initial", source, false], [
          "edit",
          edited,
          true,
        ], ["revert", source, false]] as const
      ) {
        const built: ZigProjectBuildResult = phase === "initial"
          ? first
          : await compiler.build({ sources: { [entry]: text } });
        assert(built.success, JSON.stringify(built));
        const fresh = await createZigProjectCompiler(options);
        try {
          const control = await fresh.build({ sources: { [entry]: text } });
          assert(control.success, JSON.stringify(control));
          assert.deepEqual(built.bytes, control.bytes);
        } finally {
          await fresh.dispose();
        }
        if (phase === "revert") assert.deepEqual(built.bytes, first.bytes);
        await Deno.writeFile(`${dir}/${tier}-${phase}.wasm`, built.bytes);
        const module: WebAssembly.Module = new WebAssembly.Module(built.bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        const guest: Awaited<ReturnType<typeof instantiateGuest>> =
          await instantiateGuest(module);
        try {
          for (const x of [0, 2.5, -1.5]) {
            assert.equal(guest.call("main", x), c.expected(x, isEdited));
          }
          const warm = guest.memoryBytes();
          for (let i = 0; i < 100; i++) {
            assert.equal(guest.call("main", 2.5), c.expected(2.5, isEdited));
          }
          assert.equal(guest.memoryBytes(), warm);
          rows.push({
            case: c.name,
            tier,
            phase,
            calls: 103,
            memory_bytes: warm,
            expected: c.expected(2.5, isEdited),
            fresh_parity: true,
            stats: built.stats,
          });
          console.log(
            JSON.stringify({
              case: c.name,
              tier,
              phase,
              memory: warm,
              expected: c.expected(2.5, isEdited),
            }),
          );
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler.dispose();
    }
  }
}
const before = beforeRoot + "/zig-native/zig-out/bin/blotc";
pins[before] = await hash(before);
await pinTree(beforeRoot + "/std");
const controls = [];
for (const c of cases) {
  const compiled = await new Deno.Command(before, {
    args: [
      "build-project",
      out + "/" + c.name + "/main.blot",
      out + "/" + c.name + "/before.wasm",
      "--std-root",
      beforeRoot + "/std",
      "--prelude",
      beforeRoot + "/std/prelude.blot",
      "--alias",
      "ink/=" + ink + "/lib/",
    ],
    stdout: "piped",
    stderr: "piped",
  }).output();
  await Deno.writeFile(out + "/" + c.name + "/before.jsonl", compiled.stdout);
  await Deno.writeFile(out + "/" + c.name + "/before.stderr", compiled.stderr);
  const codes = new TextDecoder().decode(compiled.stdout).trim().split("\n")
    .flatMap((line) => {
      try {
        const d = JSON.parse(line);
        return d.kind === "diagnostic" ? [d.code] : [];
      } catch {
        return [];
      }
    });
  controls.push({ case: c.name, success: compiled.success, codes });
  if (c.name === "one_resource") {
    assert(
      !compiled.success && codes.includes("effect_mismatch"),
      JSON.stringify(controls),
    );
  }
}
await Deno.writeTextFile(
  out + "/results.json",
  JSON.stringify(
    {
      controls,
      note:
        "Owner-approved replacement acceptance inputs; these are not the missing original v0/v1/v3 files.",
      pins,
      rows,
    },
    null,
    2,
  ) + "\n",
);
