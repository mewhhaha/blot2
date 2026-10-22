import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createFrontend, type Cst, SourceError } from "./syntax.ts";
const syntaxChildren = (children: readonly Cst[]) => children;

Deno.test("typed staging CST owns result rows and descriptor boundaries", async () => {
  const frontend = await createFrontend();
  const source = `const code = 1
const descriptor = fn code => code
const left: code [U32, row {}] = @code.quote 40
const shape: descriptor (code [U32, row {Foreign}]) = @code.describe left
type Generator = forall [row e] => code [U32, row e]
`;
  try {
    for (const input of [source, source.replaceAll("\n", "\r\n")]) {
      const nodes = normalizedNodes(frontend.parse(input).root, input);
      equal(nodes.filter((node) => node.kind === "code_type").length, 3);
      equal(nodes.filter((node) => node.kind === "code_row").length, 3);
      equal(nodes.filter((node) => node.kind === "descriptor_type").length, 1);
    }
    for (
      const annotation of [
        "code [U32]",
        "code [U32, {}]",
        "code [U32, row]",
        "descriptor () ->",
      ]
    ) {
      throws(
        () => frontend.parse(`const invalid: ${annotation} = ()\n`),
        SourceError,
      );
    }
  } finally {
    frontend.dispose();
  }
});

Deno.test("numeric proof syntax preserves bounded operands and rejects arbitrary computations", async () => {
  const frontend = await createFrontend();
  const names = [
    "U32Eq",
    "U32Lt",
    "U32Le",
    "U32AddFits",
    "U32SubFits",
    "Index",
  ];
  const source =
    names.map((name, index) =>
      `const proof_${index}: (values: Array U32) -> (index: U32) -> @proof.${name} values index = fn values => fn index => @proof.index values index\n`
    ).join("") +
    "const bounded: (values: List U32) -> @proof.U32Lt (0) (@list.length values) = fn values => @proof.lt 0 (@list.length values)\n";
  try {
    for (const input of [source, source.replaceAll("\n", "\r\n")]) {
      const rows = normalizedNodes(frontend.parse(input).root, input);
      equal(rows.filter((row) => row.kind === "proof_type").length, 7);
      for (const name of names) {
        ok(rows.some((row) => row.text === `@proof.${name}`));
      }
      ok(rows.some((row) => row.kind === "proof_length"));
    }
    for (
      const annotation of [
        "@proof.U32Lt x",
        "@proof.U32Lt (make x) y",
        "@proof.U32Lt (@u32.add x 1) y",
        "@proof.Other x y",
        "@proof.U32LtExtra x y",
        "@foreign.U32Lt x y",
      ]
    ) {
      throws(
        () => frontend.parse(`const invalid: ${annotation} = ()\n`),
        SourceError,
      );
    }
    frontend.parse(
      "const length = @array.length #[1, 2]\nconst checked = @proof.lt 0 1\n",
    );
  } finally {
    frontend.dispose();
  }
});

Deno.test("dependent arrow binders remain distinct from type groups", async () => {
  const frontend = await createFrontend();
  const source = `type State a is effect = {get: Unit -> a, set: a -> Unit}
const apply: (state: State a) -> ((Unit -> a ! {state.get | e}) -> a ! {state.get | e}) = fn input => fn callback => callback ()
`;
  try {
    for (const input of [source, source.replaceAll("\n", "\r\n")]) {
      const rows = normalizedNodes(frontend.parse(input).root, input);
      equal(
        rows.filter((row) => row.field === "name" && row.text === "state")
          .length,
        1,
      );
      ok(rows.some((row) => row.kind === "type_group"));
    }
  } finally {
    frontend.dispose();
  }
});

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
    const children = syntaxChildren(node.children);
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

Deno.test("privacy opacity exports and constructor parameters preserve contextual names and origins", async () => {
  const frontend = await createFrontend();
  try {
    const source = `// 🌱 declaration offsets stay original
export {Token as Ticket, make} from "./tokens"
private opaque type Token = U32
opaque type Box a = {value: a}
private type Alias = U32
private type Choice is data = #Choice U32
private type Read a is contract = {type_rep a}
private effect Hidden: Unit -> U32
private type HiddenFamily is effect = {ask: Unit -> U32}
private const private = fn opaque => opaque
private entry const exported = fn export => private export
const unwrap = fn (#Box value) => value.value
const typed = fn (value: U32) => value
const ordinary = fn opaque => fn private => fn export => (opaque, private, export)
export {Box} from "./tokens"
`;
    const rows = normalizedNodes(frontend.parse(source).root, source);
    equal(rows.filter((row) => row.kind === "opaque_type").length, 2);
    equal(rows.filter((row) => row.kind === "export_declaration").length, 2);
    ok(rows.some((row) => row.kind === "constructor_pattern"));
    ok(rows.some((row) => row.kind === "typed_parameter"));
    for (const row of rows) {
      if (row.field === "visibility") {
        equal(source.slice(row.offset, row.offset + 7), "private");
      }
      if (row.text === "opaque") {
        equal(source.slice(row.offset, row.offset + 6), "opaque");
      }
    }
    equal(
      normalizedNodes(
        frontend.parse(source.replaceAll("\n", "\r\n")).root,
        source.replaceAll("\n", "\r\n"),
      ),
      rows,
    );
    for (
      const text of [
        "privatE const answer = 42\n",
        "opaquE type Token = U32\n",
        'exporT {Token} from "./tokens"\n',
      ]
    ) {
      throws(() => frontend.parse(text), (error) => {
        ok(error instanceof SourceError);
        equal(error.code, "reserved_declaration_marker");
        equal(error.start, 0);
        return true;
      });
    }
    throws(
      () => frontend.parse('export {Token} froM "./tokens"\n'),
      (error) => {
        ok(error instanceof SourceError);
        equal(error.code, "reserved_import_marker");
        return true;
      },
    );
    for (
      const text of [
        'private import {Token} from "./tokens"\n',
        'private export {Token} from "./tokens"\n',
        'export * as tokens from "./tokens"\n',
        "private private const value = 42\n",
        "opaque type Token is data = #Token U32\n",
        'const value = 42\nimport {Token} from "./tokens"\n',
      ]
    ) throws(() => frontend.parse(text));
  } finally {
    frontend.dispose();
  }
});

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
      pending.push(...syntaxChildren(node.children));
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
    const labels = syntaxChildren(row.children).filter((node) =>
      node.kind === "type_application" && node.field === "labels"
    );
    equal(labels.length, 2);
    equal(
      syntaxChildren(labels[0].children).filter((node) =>
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
    "      break 40",
    "    break 41",
    "  break @u32.add value 1",
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
          "  break @u32.add",
          `${indentation}break @u32.add`,
        );
        throws(() => frontend.parse(invalid), (error) => {
          ok(error instanceof SourceError);
          equal(error.code, code);
          equal(
            error.start,
            invalid.indexOf(
              code === "layout_tab" ? "\tbreak @u32.add" : "break @u32.add",
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

Deno.test("implementation headers are contextual and retain explicit row and type binders", async () => {
  const frontend = await createFrontend();
  try {
    for (
      const source of [
        "impl ArraySource a : Source (Array a) = { type Item = a, const first = fn values => @array.get values 0 }\n",
        "private impl Arrow (a,b,e) : Callable (a -> b ! {| e}) where { type_eq a U32 } = { type Run = a -> b ! {| e} }\n",
        "impl Curried a => type b : Pair (a,b) = { type Item = a }\n",
        "const impl = fn impl => impl\nentry const answer = impl 42\n",
      ]
    ) frontend.parse(source);
    throws(() => frontend.parse("impL Name : Source U32 = {}\n"), SourceError);
  } finally {
    frontend.dispose();
  }
});

Deno.test("usage and quantified package CST retains semantic syntax boundaries", async () => {
  const frontend = await createFrontend();
  const source = `type Item=exists [a] where {Render a}=>a
const f:once (borrow r U32->shared U32)=fn x=>x
const make=pack [U32] 42 as Item
const read=fn item=>unpack item as [a] value in Render.show value
`;
  try {
    const rows = normalizedNodes(frontend.parse(source).root, source);
    for (
      const kind of [
        "usage_type",
        "quantified_type",
        "quantified_binder",
        "package_pack",
        "package_unpack",
      ]
    ) {
      ok(rows.some((row) => row.kind === kind), kind);
    }
  } finally {
    frontend.dispose();
  }
});
