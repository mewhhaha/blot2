import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { CompilerError } from "./diagnostics.ts";
import { createSourceFrontend, declarationOffsets } from "./source_frontend.ts";
import { createFrontend, type Cst, SourceError } from "./syntax.ts";

function nodes(root: Cst): Cst[] {
  const pending = [root];
  const result: Cst[] = [];
  for (let node = pending.pop(); node; node = pending.pop()) {
    result.push(node);
    for (let child = node.children; child.$ === "Con"; child = child.tail) {
      pending.push(child.head);
    }
  }
  return result;
}

for (const prelude of ["none", "default"] as const) {
  Deno.test(`source materialization keeps local diagnostics with ${prelude} prelude`, async () => {
    const syntax = await createFrontend();
    const frontend = await createSourceFrontend({ prelude });
    const base = prelude === "none" ? 1 : (await Deno.readTextFile(
      new URL("../std/prelude.blot", import.meta.url),
    )).length + 1;
    try {
      for (const newline of ["\n", "\r", "\r\n"]) {
        const source = [
          "// Unicode 🙂",
          "const answer = fn () => do:",
          "  let value = 40",
          "  return @u32.add value 2",
        ].join(newline);
        const local = syntax.parse(source);
        const prepared = frontend.prepare(source);
        equal(
          nodes(prepared.root).map(({ children: _, ...node }) => node),
          nodes(local.root).map(({ children: _, ...node }) => ({
            ...node,
            offset: node.offset + BigInt(base),
          })),
        );
        equal(
          declarationOffsets(prepared.root).get("answer"),
          source.indexOf("answer") + base,
        );
        for (
          const subject of [
            `offset:${base + source.indexOf("@u32.add")}`,
            "answer",
            "main::answer",
          ]
        ) {
          throws(
            () =>
              prepared.translate(
                new CompilerError({
                  code: "test",
                  subject,
                  message: "diagnostic",
                }),
              ),
            (error) => {
              ok(error instanceof SourceError);
              equal(
                error.start,
                subject.startsWith("offset:")
                  ? source.indexOf("@u32.add")
                  : source.indexOf("answer"),
              );
              return true;
            },
          );
        }
        // Project inputs own local CSTs and can be frozen/reused by callers.
        for (const node of nodes(local.root)) Object.freeze(node);
        const before = structuredClone(local.root);
        frontend.prepare({
          kind: "source_project",
          entry: "main",
          modules: [{ name: "main", filename: "main.blot", source, ...local }],
        });
        equal(local.root, before);
      }
    } finally {
      frontend.dispose();
      syntax.dispose();
    }
  });
}
