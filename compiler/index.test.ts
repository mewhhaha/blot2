import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

interface Global {
  readonly $: "Global";
  readonly source: string;
  readonly core: string;
  readonly kind: { readonly $: "lower.FunctionName" };
}

interface Context {
  readonly $: "Context";
  readonly globals: unknown;
  readonly headers: unknown;
  readonly fixities: unknown;
  readonly locals: unknown;
  readonly return_label: unknown;
}

const compiler = compiled as unknown as {
  "lower.add_global"(
    scope: Context,
    source: string,
    core: string,
    kind: Global["kind"],
    node: unknown,
  ): { $: "Done"; value: Context } | { $: "Fail"; error: unknown };
  "lower.combine_context"(own: Context, inherited: Context): Context;
  "index.find"(
    index: unknown,
    key: string,
  ): { $: "Some"; value: Global } | { $: "None" };
  "index.get"(index: unknown, key: string, fallback: Global): Global;
};

function empty(): Context {
  return {
    $: "Context",
    globals: { $: "MTip" },
    headers: { $: "MTip" },
    fixities: { $: "Nil" },
    locals: { $: "Nil" },
    return_label: { $: "None" },
  };
}

function global(source: string, core = source): Global {
  return { $: "Global", source, core, kind: { $: "lower.FunctionName" } };
}

function scope(names: readonly string[], prefix = ""): Context {
  return names.reduce((context, source) => {
    const result = compiler["lower.add_global"](
      context,
      source,
      prefix + source,
      { $: "lower.FunctionName" },
      {
        $: "Cst",
        kind: "IDENT",
        field: "",
        text: source,
        offset: 0n,
        children: { $: "Nil" },
      },
    );
    ok(result.$ === "Done", `unique name ${JSON.stringify(source)}`);
    return result.value;
  }, empty());
}

Deno.test("read-only indexes agree with Base.Map-built scopes for prefixes, Unicode, and missing keys", () => {
  const names = [
    "",
    "a",
    "ab",
    "abc",
    "a\0",
    "a\0b",
    "é",
    "e\u0301",
    "🦆",
    "🦆x",
    "日本語",
    ...Array.from(
      { length: 512 },
      (_, index) => `module_${index % 13}.system_${index}`,
    ),
  ];
  const context = scope(names);
  const snapshot = structuredClone(context);
  const expected = new Map(names.map((name) => [name, global(name)]));
  const fallback = global("$missing");
  for (const name of [...names, ...names.map((name) => `${name}missing`)]) {
    const found = expected.get(name);
    equal(
      compiler["index.find"](context.globals, name),
      found ? { $: "Some", value: found } : { $: "None" },
      name,
    );
    equal(
      compiler["index.get"](context.globals, name, fallback),
      found ?? fallback,
    );
  }
  equal(context, snapshot);
  equal(compiler["index.find"](empty().globals, ""), { $: "None" });
  equal(compiler["index.get"](empty().globals, "", fallback), fallback);
});

Deno.test("indexed source scopes retain root-over-prelude precedence without changing inherited scope", () => {
  const inherited = scope(["identity", "only_prelude"], "std.");
  const own = scope(["identity", "only_root"]);
  const combined = compiler["lower.combine_context"](own, inherited);
  for (
    const [name, core] of [
      ["identity", "identity"],
      ["only_root", "only_root"],
      ["only_prelude", "std.only_prelude"],
    ]
  ) {
    equal(compiler["index.find"](combined.globals, name), {
      $: "Some",
      value: global(name, core),
    });
  }
  equal(compiler["index.find"](inherited.globals, "identity"), {
    $: "Some",
    value: global("identity", "std.identity"),
  });
});
