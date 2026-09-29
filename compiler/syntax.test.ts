import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createFrontend, type Cst, SourceError } from "./syntax.ts";
import { bendArray } from "./bend_list.ts";

Deno.test("selector markers remain ordinary text inside comments and strings", async () => {
  const frontend = await createFrontend();
  try {
    frontend.parse('// a · b\nconst failure = fn () => @panic "a · b"\n');
    throws(() => frontend.parse("const field = ·name\n"), (error) => {
      ok(error instanceof SourceError);
      equal(error.code, "reserved_selector_marker");
      return true;
    });
  } finally {
    frontend.dispose();
  }
});

Deno.test("from is contextual to imports and the internal marker cannot bypass its spelling", async () => {
  const frontend = await createFrontend();
  try {
    frontend.parse(
      'import { value } from "./value"\nconst from = fn value => value\nconst converted = from 1\n',
    );
    const source = '// before\nimport { value } froM "./value"\n';
    throws(() => frontend.parse(source), (error) => {
      ok(error instanceof SourceError);
      equal(error.code, "reserved_import_marker");
      equal(source.slice(error.start, error.end), "froM");
      return true;
    });
  } finally {
    frontend.dispose();
  }
});

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

Deno.test("kinded declarations and applied effect rows preserve their CST shape", async () => {
  const frontend = await createFrontend();
  try {
    const root = frontend.parse(`
data Old a = #Old a
type Maybe a is data = #Some a | #Nothing
type Get a is effect = Unit -> a
type State a is effect = {
  get: Unit -> a,
  set: a -> Unit,
}
type Store a is effect = {
  get: Unit -> a
  set: a -> Unit
}
const use_state = fn (unit: Unit) -> U32 ! {State U32, Reader.ask} => 1
`).root;
    const pending = [root];
    const nodes: Cst[] = [];
    for (let node = pending.pop(); node; node = pending.pop()) {
      nodes.push(node);
      pending.push(...bendArray(node.children));
    }
    equal(nodes.filter((node) => node.kind === "data_type").length, 2);
    equal(nodes.filter((node) => node.kind === "effect_type").length, 3);
    equal(
      nodes.filter((node) =>
        node.kind === "effect_operation" &&
        node.field === "fields"
      ).length,
      4,
    );
    const row = nodes.find((node) => node.kind === "effect_row");
    ok(row);
    const labels = bendArray(row.children).filter((node) =>
      node.kind === "type_application" && node.field === "labels"
    );
    equal(labels.length, 2);
    equal(
      bendArray(labels[0].children).filter((node) =>
        node.kind === "type_atom" && node.field === "arguments"
      ).length,
      1,
    );
  } finally {
    frontend.dispose();
  }
});

Deno.test("layout line indexing preserves CST origins across LF, CRLF, CR and mixed endings", async () => {
  const frontend = await createFrontend();
  const lines = [
    "// leading comment",
    "const before = fn () => 1",
    "const answer = fn (condition: Bool) => do:",
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
