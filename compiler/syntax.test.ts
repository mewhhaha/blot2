import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createFrontend, type Cst, SourceError } from "./syntax.ts";
import { bendArray } from "./bend_list.ts";

function normalizedNodes(root: Cst, source: string) {
  const pending = [root];
  const nodes = [];
  for (let node = pending.pop(); node; node = pending.pop()) {
    const children = bendArray(node.children);
    nodes.push({
      kind: node.kind,
      field: node.field,
      text: node.text,
      offset: source.slice(0, Number(node.offset)).replace(/\r\n|\r/g, "\n")
        .length,
      children: children.length,
    });
    pending.push(...children.toReversed());
  }
  return nodes;
}

Deno.test("layout line indexing preserves CST origins across LF, CRLF, CR and mixed endings", async () => {
  const frontend = await createFrontend();
  const lines = [
    "// leading comment",
    "fn before () => 1",
    "export fn answer (condition: Bool) => do:",
    "  let value = do:",
    "    if condition:",
    "      return 40",
    "    return 41",
    "  return @u32.add value 1",
    "",
  ];
  try {
    const reference = lines.join("\n");
    const expected = normalizedNodes(frontend.parse(reference).root, reference);
    for (const endings of [["\n"], ["\r\n"], ["\r"], ["\n", "\r", "\r\n"]]) {
      const source = lines.map((line, index) =>
        index === lines.length - 1
          ? line
          : line + endings[index % endings.length]
      ).join("");
      equal(normalizedNodes(frontend.parse(source).root, source), expected);
      for (
        const [indentation, code] of [["\t", "layout_tab"], [
          "   ",
          "layout_dedent",
        ]]
      ) {
        const invalid = source.replace(
          "  return @u32.add",
          `${indentation}return @u32.add`,
        );
        throws(() => frontend.parse(invalid), (error) => {
          ok(error instanceof SourceError);
          equal(error.code, code);
          equal(
            error.start,
            invalid.indexOf(
              code === "layout_tab" ? "\treturn @u32.add" : "return @u32.add",
            ),
          );
          return true;
        });
      }
    }
  } finally {
    frontend.dispose();
  }
});
