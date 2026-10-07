import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import type { DiagnosticType } from "../../compiler/type_diagnostics.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
Deno.test("typed holes reach project diagnostics and preserve the last successful revision", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({ executable, entry });
  try {
    const original =
      'import { next } from "./library"\nentry const answer = fn () => next 41\n';
    const sources = {
      [entry]: original,
      [`${directory}/library.blot`]:
        "const next = fn (value: U32) -> U32 => @u32.add value 1\n",
    };
    const first = await compiler.build({ sources });
    ok(first.success, JSON.stringify(first));
    const failed = await compiler.build({
      sources: {
        ...sources,
        [`${directory}/library.blot`]:
          "// 雪\nconst next = fn (value: U32) -> U32 => @hole\n",
      },
    });
    ok(!failed.success);
    equal(failed.revision, first.revision);
    equal(failed.diagnostics[0].code, "typed_hole");
    ok(failed.diagnostics[0].message.includes("expected: U32"));
    ok(failed.diagnostics[0].message.includes("value: U32"));
    equal(failed.diagnostics[0].filename, `${directory}/library.blot`);
    const diagnostic = failed.diagnostics[0];
    ok(diagnostic.hole);
    equal(diagnostic.hole.nodes[diagnostic.hole.expected].kind, "u32");
    const binding = diagnostic.hole.scope.find((item) => item.name === "value");
    ok(binding);
    equal(diagnostic.hole.nodes[binding.type].kind, "u32");
    equal(diagnostic.start - diagnostic.utf16!.start, 2);
    equal(diagnostic.end - diagnostic.utf16!.end, 2);
    const fixed = await compiler.build({ sources });
    ok(fixed.success);
    equal(fixed.bytes, first.bytes);
    const guest = await instantiateGuest(fixed.bytes);
    try {
      equal(guest.call("answer", null), 42);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("typed holes expose shared generic requirements and repeated structured rows", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({ executable, entry });
  try {
    const built = await compiler.build({
      sources: {
        [entry]: `type Add a is contract = { associated "add" a a a }
const incomplete: a -> a where { Add a } = fn value => @hole
entry const answer = 42
`,
      },
    });
    ok(!built.success);
    const hole = built.diagnostics[0].hole;
    ok(hole);
    equal(hole.nodes[hole.expected].kind, "variable");
    equal(hole.enclosing.len, 1);
    const requirement = hole.requirements[hole.enclosing.start];
    equal(requirement.kind, "dispatch");
    equal(requirement.name, "add");
    equal(requirement.subject, hole.expected);
    equal(requirement.result, hole.expected);
    const effects = await compiler.build({
      sources: {
        [entry]: `type Read a is effect = Unit -> a
const incomplete: Unit -> {value: U32} ! {Read U32, Read U32 | e} = @hole
entry const answer = 42
`,
      },
    });
    ok(!effects.success);
    const typed = effects.diagnostics[0].hole;
    ok(typed);
    const fn = typed.nodes[typed.expected];
    const record = typed.nodes[typed.edges[fn.children.start + 1].type];
    equal(record.kind, "record");
    const field = typed.edges[record.children.start];
    equal(field.name, "value");
    equal(typed.nodes[field.type].kind, "u32");
    const row = typed.nodes[fn.effects!];
    equal(row.children.len, 3);
    for (let i = 0; i < 2; i++) {
      const operation: DiagnosticType =
        typed.nodes[typed.edges[row.children.start + i].type];
      equal(operation.name, "Read");
      equal(
        typed.nodes[typed.edges[operation.children.start].type].kind,
        "u32",
      );
    }
    equal(
      typed.nodes[typed.edges[row.children.start + 2].type].kind,
      "row_variable",
    );
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
