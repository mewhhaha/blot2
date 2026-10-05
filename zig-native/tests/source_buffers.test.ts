import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import {
  createZigProjectCompiler,
  type ZigProjectBuildResult,
} from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0];
async function answer(result: ZigProjectBuildResult, expected: number) {
  ok(result.success, JSON.stringify(result));
  const { instance } = await WebAssembly.instantiate(result.bytes);
  const exported = instance.exports.answer;
  equal(
    typeof exported === "function"
      ? exported()
      : (exported as WebAssembly.Global).value,
    expected,
  );
}
async function fixture() {
  const root = await Deno.makeTempDir({ prefix: "blot-source-overlays-" });
  const entry = root + "/main.blot", dependency = root + "/dep.blot";
  return {
    root,
    entry,
    dependency,
    cleanup: () => Deno.remove(root, { recursive: true }),
  };
}
const main = 'import {value} from "./dep"\nentry const answer: U32 = value\n';
const value = (n: number) => `const value: U32 = ${n}\n`;

Deno.test("source buffers compile virtual entry dependencies prelude and aliases without writes", async () => {
  const item = await fixture();
  const root = item.root + "/never-created";
  const compiler = await createZigProjectCompiler({
    executable,
    entry: root + "/main.blot",
    prelude: root + "/prelude.blot",
    imports: { "pkg/": root + "/packages" },
  });
  try {
    const result = await compiler.build({
      sources: {
        [root + "/main.blot"]:
          'import {value} from "./dep"\nimport {extra} from "pkg/extra"\nentry const answer: U32 = @u32.add value extra\n',
        [root + "/dep.blot"]:
          "const values = [1, 2]\nconst value: U32 = (@array.from_list values)[1]\n",
        [root + "/prelude.blot"]:
          "const increment = fn (x: U32) -> U32 => @u32.add x 1\n",
        [root + "/packages/extra.blot"]: "const extra: U32 = increment 39\n",
      },
    });
    await answer(result, 42);
    await rejects(Deno.stat(root), Deno.errors.NotFound);
  } finally {
    await compiler.dispose();
    await item.cleanup();
  }
});

Deno.test("source buffers are copied when queued and an omitted set returns to disk", async () => {
  const item = await fixture();
  await Deno.writeTextFile(item.entry, main);
  await Deno.writeTextFile(item.dependency, value(41));
  const compiler = await createZigProjectCompiler({
    executable,
    entry: item.entry,
  });
  try {
    const sources = { [item.dependency]: value(42) };
    const first = compiler.build({ sources });
    sources[item.dependency] = value(43);
    const second = compiler.build({ sources });
    sources[item.dependency] = "invalid";
    delete sources[item.dependency];
    const third = compiler.build();
    const results = await Promise.all([first, second, third]);
    equal(results.map((result) => result.revision), [1, 2, 3]);
    await answer(results[0], 42);
    await answer(results[1], 43);
    await answer(results[2], 41);
    equal(await Deno.readTextFile(item.dependency), value(41));
  } finally {
    await compiler.dispose();
    await item.cleanup();
  }
});

Deno.test("source buffers preserve the last good revision through errors deletion and recovery", async () => {
  const item = await fixture();
  const compiler = await createZigProjectCompiler({
    executable,
    entry: item.entry,
  });
  const sources = { [item.entry]: main, [item.dependency]: value(42) };
  try {
    await answer(await compiler.build({ sources }), 42);
    for (
      const text of ["const value: U32 = false\n", "const value =\n", null]
    ) {
      const rejected = await compiler.build({
        sources: { ...sources, [item.dependency]: text },
      });
      ok(!rejected.success);
      equal(rejected.revision, 1);
    }
    const recovered = await compiler.build({ sources });
    await answer(recovered, 42);
    equal(recovered.revision, 2);
    ok(recovered.success && recovered.stats.attemptStats.reused_output);
    const missing = await compiler.build({ sources: { [item.entry]: main } });
    ok(!missing.success);
    equal(missing.revision, 2);
    await answer(
      await compiler.build({
        sources: { ...sources, [item.dependency]: value(43) },
      }),
      43,
    );
  } finally {
    await compiler.dispose();
    await item.cleanup();
  }
});

Deno.test("source buffers use binary frames beyond the metadata limit", async () => {
  const item = await fixture();
  const compiler = await createZigProjectCompiler({
    executable,
    entry: item.entry,
  });
  try {
    const source = "// " + "x".repeat(1024 * 1024 + 17) +
      "\nentry const answer: U32 = 42\n";
    const result = await compiler.build({ sources: { [item.entry]: source } });
    await answer(result, 42);
    ok(result.success && result.stats.sourceBytes > 1024 * 1024);
  } finally {
    await compiler.dispose();
    await item.cleanup();
  }
});

Deno.test("source buffer validation leaves the process usable and detects canonical alias conflicts", async () => {
  const item = await fixture();
  await Deno.symlink(item.root, item.root + "/alias", { type: "dir" });
  const compiler = await createZigProjectCompiler({
    executable,
    entry: item.entry,
  });
  try {
    await rejects(
      compiler.build({ sources: { [item.entry]: "\ud800" } }),
      /well-formed/,
    );
    await rejects(
      compiler.build({
        sources: { [item.entry]: "x".repeat(16 * 1024 * 1024 + 1) },
      }),
      /limit/,
    );
    const conflict = await compiler.build({
      sources: {
        [item.entry]: "entry const answer = 1\n",
        [item.root + "/alias/main.blot"]: "entry const answer = 2\n",
      },
    });
    ok(!conflict.success);
    equal(conflict.revision, 0);
    equal(conflict.diagnostics[0].code, "DuplicateSourcePath");
    await answer(
      await compiler.build({
        sources: { [item.entry]: "entry const answer: U32 = 42\n" },
      }),
      42,
    );
  } finally {
    await compiler.dispose();
    await item.cleanup();
  }
});
