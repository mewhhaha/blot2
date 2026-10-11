import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
const definition = '@type.call "add" left right';
const preludeSource = await Deno.readTextFile(prelude);
function range(source: string, expression: string) {
  const start =
    new TextEncoder().encode(source.slice(0, source.indexOf(expression)))
      .length;
  return { start, end: start + new TextEncoder().encode(expression).length };
}

Deno.test("specialization uses survive fresh CLI, retained project rejection and recovery", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude,
    cacheDirectory: false,
  });
  try {
    const good = {
      [entry]:
        'import { plus } from "./library"\nentry const answer=fn()=>plus 20 22\n',
      [library]: "const plus=fn a=>fn b=>a + b\n",
    };
    const baseline = await compiler.build({ sources: good });
    ok(baseline.success, JSON.stringify(baseline));
    const cases = [
      {
        source:
          "type Box is data=#Box U32\nentry const answer=fn()=>do:\n  let result=#Box 1 + #Box 2\n  return 7\n",
        use: "#Box 1 + #Box 2",
      },
      {
        source:
          'import { plus } from "./library"\ntype Box is data=#Box U32\nentry const answer=fn()=>do:\n  let result=plus (#Box 1) (#Box 2)\n  return 7\n',
        use: "plus (#Box 1) (#Box 2)",
      },
      {
        source:
          'import { nested } from "./library"\ntype Box is data=#Box U32\nentry const answer=fn()=>do:\n  let result=nested (#Box 1) (#Box 2)\n  return 7\n',
        use: "nested (#Box 1) (#Box 2)",
      },
      {
        source:
          "const twice=fn f=>fn x=>f (f x)\nentry const answer=fn()=>do:\n  let result=twice (fn v=>v + v) #True\n  return 7\n",
        use: "twice (fn v=>v + v) #True",
      },
    ];
    for (const item of cases) {
      const sources = {
        [entry]: item.source,
        [library]:
          "const plus=fn a=>fn b=>a + b\nconst nested=fn a=>fn b=>plus a b\n",
      };
      const retained = await compiler.build({ sources });
      ok(!retained.success, JSON.stringify(retained));
      ok(retained.revision >= baseline.revision);
      const diagnostic = retained.diagnostics[0];
      equal(diagnostic.filename, entry);
      equal(
        { start: diagnostic.start, end: diagnostic.end },
        range(item.source, item.use),
      );
      equal(diagnostic.code, "missing_associated");
      ok(diagnostic.related, JSON.stringify(diagnostic));
      equal(diagnostic.related.filename, prelude);
      equal(
        { start: diagnostic.related.start, end: diagnostic.related.end },
        range(preludeSource, definition),
      );
      equal(diagnostic.related.offset_encoding, "utf8_bytes");
      equal(
        diagnostic.explanation?.candidates.map((candidate) =>
          candidate.outcome
        ),
        ["no_member"],
      );
      await Deno.writeTextFile(entry, item.source);
      await Deno.writeTextFile(library, sources[library]);
      const fresh = await new Deno.Command(executable, {
        args: [
          "build-project",
          entry,
          `${directory}/out.wasm`,
          "--prelude",
          prelude,
        ],
        stdout: "piped",
        stderr: "piped",
      }).output();
      equal(fresh.success, false);
      equal(fresh.stderr.length, 0);
      const rows = new TextDecoder().decode(fresh.stdout).trim().split("\n")
        .map((line) => JSON.parse(line));
      const wire = rows.find((row) => row.kind === "diagnostic");
      equal(wire.filename, diagnostic.filename);
      equal({ start: wire.start, end: wire.end }, range(item.source, item.use));
      equal(wire.related, diagnostic.related);
      equal(wire.details.explanation, diagnostic.explanation);
      const recovered = await compiler.build({ sources: good });
      ok(recovered.success, JSON.stringify(recovered));
      equal(recovered.bytes, baseline.bytes);
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("a concrete invalid operation in a library stays in that library", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude,
    cacheDirectory: false,
  });
  try {
    const source = "const broken=fn ignored=>#True + #False\n";
    const result = await compiler.build({
      sources: {
        [entry]:
          'import { broken } from "./library"\nentry const answer=fn()=>do:\n  let result=broken 42\n  return 7\n',
        [library]: source,
      },
    });
    ok(!result.success, JSON.stringify(result));
    equal(result.diagnostics[0].filename, library);
    equal({
      start: result.diagnostics[0].start,
      end: result.diagnostics[0].end,
    }, range(source, "#True + #False"));
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("compiled callback definitions preserve source origins", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const library = `${directory}/library.blot`;
  const dependencies = `${directory}/dependencies.blotdep`;
  try {
    await Deno.writeTextFile(
      library,
      "const plus=fn a=>fn b=>a + b\nconst twice=fn f=>fn x=>f (f x)\nconst callback=fn v=>v + v\n",
    );
    await Deno.writeTextFile(
      entry,
      'import { twice, callback } from "./library"\nentry const answer=7\n',
    );
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, dependencies, "--prelude", prelude],
      stdout: "piped",
      stderr: "piped",
    }).output();
    ok(packed.success, new TextDecoder().decode(packed.stdout));
    const source =
      'import { twice, callback } from "./library"\nentry const answer=fn()=>do:\n  let result=twice callback #True\n  return 7\n';
    await Deno.writeTextFile(entry, source);
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude,
      dependencies,
      cacheDirectory: false,
    });
    try {
      const result = await compiler.build();
      ok(!result.success, JSON.stringify(result));
      const diagnostic = result.diagnostics[0];
      equal(diagnostic.filename, entry);
      equal(
        { start: diagnostic.start, end: diagnostic.end },
        range(source, "twice callback #True"),
      );
      ok(diagnostic.related?.filename.endsWith("prelude.blot"));
      equal(diagnostic.code, "missing_associated");
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
