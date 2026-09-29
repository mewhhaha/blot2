import {
  deepStrictEqual as equal,
  notDeepStrictEqual as notEqual,
  ok,
} from "node:assert/strict";
import compiler from "../generated/compiler/compiler.js";
import session from "../generated/compiler/native_session.js";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Node = { readonly $: string; readonly [field: string]: unknown };
type Encoded = { readonly $: "Done"; readonly value: BendList<number> } | {
  readonly $: "Fail";
  readonly error: Node;
};
const compiled = { ...compiler, ...session };
const core = compiled as unknown as {
  "core_compare.same_module"(left: Node, right: Node): boolean;
  "native_cache_keys.module"(module: Node): Encoded;
};
const some = (value: Node): Node => ({ $: "Some", value });
const id = (declaration: string): Node => ({
  $: "model.TypeId",
  module_name: "scope",
  declaration,
});
const empty: Node = { $: "model.UnitExpr" };
const u32: Node = { $: "model.U32Ty" };
const row = (
  operations: readonly Node[],
  tail: Node = { $: "model.ClosedRow" },
): Node => ({
  $: "model.EffectRow",
  operations: bendList(operations),
  tail,
});
const arm = (pattern: Node): Node => ({
  $: "model.MatchArm",
  patterns: bendList([pattern]),
  body: empty,
});

function moduleWith({
  expr = empty,
  annotation = { $: "None" },
  functions = [],
  constants,
  dataTypes = [],
  operations = [],
}: {
  expr?: Node;
  annotation?: Node;
  functions?: readonly Node[];
  constants?: readonly Node[];
  dataTypes?: readonly Node[];
  operations?: readonly Node[];
} = {}): Node {
  return {
    $: "model.Module",
    constants: bendList(
      constants ?? [{
        $: "model.Constant",
        name: "answer",
        exported: false,
        annotation,
        value: expr,
      }],
    ),
    functions: bendList(functions),
    data_types: bendList(dataTypes),
    operations: bendList(operations),
  };
}

function specimen(type: string, changed = false): unknown {
  if (type.startsWith("List<&2, ") && type.endsWith(">")) {
    const inner = type.slice("List<&2, ".length, -1);
    return bendList(changed ? [] : [specimen(inner)]);
  }
  if (type.startsWith("Maybe<&2, ") && type.endsWith(">")) {
    const inner = type.slice("Maybe<&2, ".length, -1);
    return changed ? { $: "None" } : some(specimen(inner) as Node);
  }
  switch (type) {
    case "String":
      return changed ? "other" : "first";
    case "Nat":
      return changed ? 2n : 1n;
    case "U32":
      return changed ? 2 : 1;
    case "F32":
      return changed ? -0 : 0;
    case "Bool":
      return !changed;
    case "TypeId":
      return id(changed ? "Other" : "Thing");
    case "RowTail":
      return changed
        ? { $: "model.RowVariable", index: 1n }
        : { $: "model.ClosedRow" };
    case "EffectRow":
      return row(changed ? [id("Thing")] : [id("Thing"), id("Thing")]);
    case "Ty":
      return changed ? { $: "model.F32Ty" } : u32;
    case "Predicate":
      return {
        $: "model.TypeRepPredicate",
        represented: changed ? { $: "model.F32Ty" } : u32,
      };

    case "Operation":
      return {
        $: "model.Operation",
        identity: id(changed ? "Other" : "Thing"),
        parameter: u32,
        result: u32,
      };
    case "Constructor":
      return {
        $: "model.Constructor",
        name: changed ? "Other" : "Thing",
        payload: { $: "None" },
        fields: bendList([]),
      };
    case "ValueReference":
      return changed
        ? { $: "model.ConstantReference", name: "first" }
        : { $: "model.LocalReference", name: "first" };
    case "Pattern":
      return { $: "model.BindingPattern", name: changed ? "other" : "first" };
    case "MatchArm<Expr>":
      return changed
        ? arm({ $: "model.BindingPattern", name: "other" })
        : arm({ $: "model.BindingPattern", name: "first" });
    case "Expr":
      return { $: "model.U32Expr", value: changed ? 2 : 1 };
    case "ScalarOp":
      return { $: changed ? "model.Subtract" : "model.Add" };
    case "UnaryOp":
      return { $: changed ? "model.F32Absolute" : "model.F32Negate" };
    case "Dispatch":
      return { $: changed ? "model.MemberDispatch" : "model.BinaryDispatch" };
    default:
      throw new Error(`Add a comparator fixture for ${type}`);
  }
}

function constructors(source: string, type: string) {
  const beginning = source.indexOf(`type ${type} is Data:\n`);
  ok(beginning >= 0, `missing model type ${type}`);
  const block = source.slice(beginning).split("\n\n", 1)[0];
  return [...block.matchAll(/^  (\w+)\{([^\n]*)\}$/gm)].map((match) => {
    const fields = match[2] === "" ? [] : splitFields(match[2]).map((entry) => {
      const separator = entry.indexOf(": ");
      ok(separator >= 0, entry);
      return [entry.slice(0, separator), entry.slice(separator + 2)] as const;
    });
    return { name: match[1], fields };
  });
}

function splitFields(fields: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let start = 0;
  for (let index = 0; index < fields.length; index++) {
    if (fields[index] === "<") depth++;
    if (fields[index] === ">") depth--;
    if (fields[index] === "," && depth === 0) {
      parts.push(fields.slice(start, index).trim());
      start = index + 1;
    }
  }
  parts.push(fields.slice(start).trim());
  return parts;
}

function modelNode(entry: ReturnType<typeof constructors>[number]): Node {
  return Object.fromEntries([
    ["$", `model.${entry.name}`],
    ...entry.fields.map(([name, type]) => [name, specimen(type)]),
  ]) as Node;
}

function embed(type: string, value: Node): Node {
  switch (type) {
    case "Expr":
      return moduleWith({ expr: value });
    case "Ty":
      return moduleWith({ annotation: some(value) });
    case "Pattern":
      return moduleWith({
        expr: {
          $: "model.MatchExpr",
          values: bendList([empty]),
          arms: bendList([arm(value)]),
        },
      });
    case "Operation":
      return moduleWith({ operations: [value] });
    case "EffectRow":
      return embed("Ty", {
        $: "model.FunctionTy",
        parameter: u32,
        result: u32,
        effects: value,
      });
    case "RowTail":
      return embed("EffectRow", row([id("Thing")], value));
    case "Predicate":
      return embed("Expr", {
        $: "model.QualifiedExpr",
        offset: 1n,
        annotation: u32,
        predicates: bendList([value]),
        value: empty,
      });
    case "ScalarOp":
      return embed("Expr", {
        $: "model.ScalarExpr",
        operator: value,
        left: empty,
        right: empty,
      });
    case "UnaryOp":
      return embed("Expr", {
        $: "model.UnaryExpr",
        operator: value,
        value: empty,
      });
    case "Dispatch":
      return embed("Expr", {
        $: "model.AssociatedExpr",
        identity: 1n,
        dispatch: value,
        member: "choose",
        templates: bendList([]),
        left: empty,
        right: empty,
      });
    case "ValueReference":
      return embed("Pattern", { $: "model.ValuePattern", reference: value });
    default:
      throw new Error(`Add a module embedding for ${type}`);
  }
}

function key(module: Node): number[] {
  const encoded = core["native_cache_keys.module"](module);
  equal(encoded.$, "Done");
  if (encoded.$ !== "Done") throw new Error("module key failed");
  return bendArray(encoded.value);
}

function comparison(left: Node, right: Node, expected: boolean) {
  const actual = core["core_compare.same_module"](left, right);
  equal(actual, expected);
  if (expected) equal(key(left), key(right));
  else notEqual(key(left), key(right));
}

Deno.test("certificate module comparison covers every expression, type and operator field", async () => {
  const source = await Deno.readTextFile(
    new URL("./model.bend", import.meta.url),
  );
  for (
    const [type, count] of [
      ["Expr", 52],
      ["Ty", 16],
      ["Predicate", 7],
      ["Pattern", 8],
      ["Operation", 3],
      ["RowTail", 4],
      ["ScalarOp", 22],
      ["UnaryOp", 8],
      ["Dispatch", 3],
      ["ValueReference", 2],
    ] as const
  ) {
    const variants = constructors(source, type);
    equal(variants.length, count, `${type} fixture coverage changed`);
    for (const [index, entry] of variants.entries()) {
      const base = modelNode(entry);
      comparison(embed(type, base), embed(type, base), true);
      for (const [field, fieldType] of entry.fields) {
        comparison(
          embed(type, base),
          embed(type, { ...base, [field]: specimen(fieldType, true) }),
          false,
        );
      }
      const next = modelNode(variants[(index + 1) % variants.length]);
      comparison(embed(type, base), embed(type, next), false);
    }
  }
});

Deno.test("certificate comparison preserves float bits, duplicate effects, and source provenance", () => {
  const f32 = (bits: number) =>
    new Float32Array(new Uint32Array([bits]).buffer)[0];
  const expression = (value: Node) => moduleWith({ expr: value });
  for (
    const [left, right] of [
      [0x00000000, 0x80000000],
      [0x7fc00001, 0x7fc00002],
    ]
  ) {
    comparison(
      expression({ $: "model.F32Expr", value: f32(left) }),
      expression({ $: "model.F32Expr", value: f32(right) }),
      false,
    );
  }
  const functionType = (effects: Node): Node => ({
    $: "model.FunctionTy",
    parameter: u32,
    result: u32,
    effects,
  });
  const typed = (effects: Node) =>
    moduleWith({ annotation: some(functionType(effects)) });
  comparison(
    typed(row([id("Read"), id("Read")])),
    typed(row([id("Read")])),
    false,
  );
  comparison(
    typed(row([id("Read"), id("Write")])),
    typed(row([id("Write"), id("Read")])),
    false,
  );
  comparison(
    expression({
      $: "model.SourceExpr",
      offset: 7n,
      annotation: some(u32),
      value: empty,
    }),
    expression({
      $: "model.SourceExpr",
      offset: 8n,
      annotation: some(u32),
      value: empty,
    }),
    false,
  );
  comparison(
    expression({
      $: "model.SourceExpr",
      offset: 7n,
      annotation: some(u32),
      value: empty,
    }),
    expression({
      $: "model.SourceExpr",
      offset: 7n,
      annotation: some({ $: "model.F32Ty" }),
      value: empty,
    }),
    false,
  );
  comparison(
    moduleWith({
      annotation: some({
        $: "model.AppliedTy",
        identity: id("First"),
        arguments: bendList([u32]),
      }),
    }),
    moduleWith({
      annotation: some({
        $: "model.AppliedTy",
        identity: id("Second"),
        arguments: bendList([u32]),
      }),
    }),
    false,
  );
});

Deno.test("qualified predicate comparison preserves operation templates and row tails", () => {
  const qualified = (predicate: Node) => embed("Predicate", predicate);
  const operation = (template: Node): Node => ({
    $: "model.OperationPredicate",
    template,
    arguments: bendList([u32]),
    function_type: {
      $: "model.FunctionTy",
      parameter: u32,
      result: u32,
      effects: row([]),
    },
  });
  comparison(
    qualified(operation(id("Read"))),
    qualified(operation(id("Write"))),
    false,
  );

  const reflected = (tail: Node): Node => ({
    $: "model.EffectRepPredicate",
    row: row([id("Read"), id("Read")], tail),
  });
  comparison(
    qualified(
      reflected({ $: "model.FreeRow", scope: "binding", name: "first" }),
    ),
    qualified(
      reflected({ $: "model.FreeRow", scope: "binding", name: "second" }),
    ),
    false,
  );
  comparison(
    qualified(reflected({ $: "model.RowVariable", index: 1n })),
    qualified(reflected({ $: "model.RowVariable", index: 2n })),
    false,
  );
});

Deno.test("certificate comparison checks declaration headers, constructors, and match arms", () => {
  const fn: Node = {
    $: "model.Function",
    name: "run",
    exported: true,
    parameter: "value",
    parameter_type: some(u32),
    result_type: some(u32),
    body: empty,
  };
  const functionModule = (value: Node) => moduleWith({ functions: [value] });
  for (
    const changed of [
      { name: "other" },
      { exported: false },
      { parameter: "other" },
      { parameter_type: { $: "None" } },
      { result_type: some({ $: "model.F32Ty" }) },
      { body: { $: "model.U32Expr", value: 1 } },
    ]
  ) {
    comparison(
      functionModule(fn),
      functionModule({ ...fn, ...changed }),
      false,
    );
  }

  const constant: Node = {
    $: "model.Constant",
    name: "answer",
    exported: true,
    annotation: some(u32),
    value: empty,
  };
  const constantModule = (value: Node) => moduleWith({ constants: [value] });
  for (
    const changed of [
      { name: "other" },
      { exported: false },
      { annotation: { $: "None" } },
      { value: { $: "model.U32Expr", value: 1 } },
    ]
  ) {
    comparison(
      constantModule(constant),
      constantModule({ ...constant, ...changed }),
      false,
    );
  }

  const constructor: Node = {
    $: "model.Constructor",
    name: "Box",
    payload: some(u32),
    fields: bendList(["value"]),
  };
  const dataType = (member: Node): Node => ({
    $: "model.DataType",
    identity: id("Box"),
    parameters: 1n,
    constructors: bendList([member]),
  });
  const typeModule = (member: Node) =>
    moduleWith({ dataTypes: [dataType(member)] });
  for (
    const changed of [
      { name: "Other" },
      { payload: { $: "None" } },
      { fields: bendList(["other"]) },
    ]
  ) {
    comparison(
      typeModule(constructor),
      typeModule({ ...constructor, ...changed }),
      false,
    );
  }

  const match = (arms: readonly Node[]) =>
    moduleWith({
      expr: {
        $: "model.MatchExpr",
        values: bendList([empty]),
        arms: bendList(arms),
      },
    });
  const first: Node = {
    $: "model.MatchArm",
    patterns: bendList([{ $: "model.WildcardPattern" }]),
    body: empty,
  };
  comparison(match([first]), match([first, first]), false);
  comparison(
    match([first]),
    match([{ ...first, patterns: bendList([]) }]),
    false,
  );
  comparison(
    match([first]),
    match([{ ...first, body: { $: "model.U32Expr", value: 1 } }]),
    false,
  );
});

Deno.test("certificate comparison rejects exhausted traversal budgets", () => {
  const left = moduleWith();
  equal(core["core_compare.same_module"](left, left), true);
  const limited = compiled as unknown as {
    "core_compare.compare"(
      fuel: bigint,
      work: BendList<Node>,
      matching: boolean,
    ): boolean;
  };
  for (const fuel of [0n, 1n]) {
    equal(
      limited["core_compare.compare"](
        fuel,
        bendList([{
          $: "core_compare.ModulePair",
          left,
          right: left,
        }]),
        true,
      ),
      false,
    );
  }
});
