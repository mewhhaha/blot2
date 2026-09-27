import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type List<A> =
  | { readonly $: "Nil" }
  | { readonly $: "Con"; readonly head: A; readonly tail: List<A> };

interface TypeId {
  readonly $: "model.TypeId";
  readonly module_name: string;
  readonly declaration: string;
}

interface EffectRow {
  readonly $: "model.EffectRow";
  readonly operations: List<TypeId>;
  readonly tail:
    | { readonly $: "model.ClosedRow" }
    | {
      readonly $: "model.RowVariable" | "model.RowParameter";
      readonly index: bigint;
    };
}

type Ty =
  | { readonly $: "model.ProductTy"; readonly elements: List<Ty> }
  | { readonly $: "model.ArrayTy"; readonly element: Ty }
  | {
    readonly $:
      | "model.UnitTy"
      | "model.U32Ty"
      | "model.F32Ty"
      | "model.BoolTy"
      | "model.NeverTy";
  }
  | {
    readonly $: "model.VariableTy" | "model.ParameterTy";
    readonly index: bigint;
  }
  | {
    readonly $: "model.ProviderTy";
    readonly identity: TypeId;
    readonly effects: EffectRow;
  }
  | {
    readonly $: "model.AppliedTy";
    readonly identity: TypeId;
    readonly arguments: List<Ty>;
  }
  | {
    readonly $: "model.FunctionTy";
    readonly parameter: Ty;
    readonly result: Ty;
    readonly effects: EffectRow;
  };

type Substitution = {
  readonly $: "types.Substitution";
  readonly variable: bigint;
  readonly replacement: Ty;
} | {
  readonly $: "types.RowSubstitution";
  readonly variable: bigint;
  readonly replacement: EffectRow;
};

type Result<A> =
  | { readonly $: "Done"; readonly value: A }
  | {
    readonly $: "Fail";
    readonly error: {
      readonly $: "model.Diagnostic";
      readonly code: string;
      readonly subject: string;
      readonly message: string;
    };
  };

type Substitutions = { readonly $: "types.Substitutions" };

const types = compiled as unknown as {
  "types.from_list"(entries: List<Substitution>): Substitutions;
  "types.resolve"(substitutions: Substitutions, ty: Ty): Result<Ty>;
  "types.resolve_work"(
    substitutions: Substitutions,
    fuel: bigint,
    work: { readonly $: "types.OneType"; readonly value: Ty },
  ): Result<List<Ty>>;
  "types.unify"(
    left: Ty,
    right: Ty,
    substitutions: Substitutions,
    subject: string,
  ): Result<Substitutions>;
  "types.pair_arguments"(
    left: List<Ty>,
    right: List<Ty>,
    subject: string,
  ): Result<
    List<{
      readonly $: "types.Equation";
      readonly left: Ty;
      readonly right: Ty;
      readonly subject: string;
    }>
  >;
};

function list<A>(values: readonly A[]): List<A> {
  return values.reduceRight<List<A>>(
    (tail, head) => ({ $: "Con", head, tail }),
    { $: "Nil" },
  );
}

const variable = (index: number): Ty => ({
  $: "model.VariableTy",
  index: BigInt(index),
});
const row = (
  operations: readonly TypeId[] = [],
  tail: EffectRow["tail"] = { $: "model.ClosedRow" },
): EffectRow => ({ $: "model.EffectRow", operations: list(operations), tail });
const arrow = (parameter: Ty, result: Ty, effects = row()): Ty => ({
  $: "model.FunctionTy",
  parameter,
  result,
  effects,
});
const u32: Ty = { $: "model.U32Ty" };
const boolean: Ty = { $: "model.BoolTy" };
const identity: TypeId = {
  $: "model.TypeId",
  module_name: "test",
  declaration: "Box",
};
const applied = (...arguments_: Ty[]): Ty => ({
  $: "model.AppliedTy",
  identity,
  arguments: list(arguments_),
});
const substitution = (index: number, replacement: Ty): Substitution => ({
  $: "types.Substitution",
  variable: BigInt(index),
  replacement,
});
const rowSubstitution = (
  index: number,
  replacement: EffectRow,
): Substitution => ({
  $: "types.RowSubstitution",
  variable: BigInt(index),
  replacement,
});
const provider = (effects: EffectRow): Ty => ({
  $: "model.ProviderTy",
  identity,
  effects,
});

const complexity = {
  $: "model.Diagnostic" as const,
  code: "type_complexity",
  subject: "inference",
  message: "type traversal exceeded the 65536-node nesting/width limit",
};

Deno.test("type substitution resolves wide product fields without recursive sibling frames", () => {
  const width = 8192;
  const result = types["types.resolve"](indexed([substitution(0, boolean)]), {
    $: "model.ProductTy",
    elements: list(
      Array.from(
        { length: width },
        (_, index) => index % 2 === 0 ? variable(0) : u32,
      ),
    ),
  });
  equal(result.$, "Done");
  if (result.$ !== "Done" || result.value.$ !== "model.ProductTy") {
    throw new Error("wide substitution did not return a product");
  }
  let index = 0;
  for (
    let fields = result.value.elements;
    fields.$ === "Con";
    fields = fields.tail
  ) {
    equal(fields.head, index % 2 === 0 ? boolean : u32);
    index++;
  }
  equal(index, width);
});

Deno.test("wide product unification preserves equation order without recursive sibling frames", () => {
  const width = 8192;
  const result = types["types.pair_arguments"](
    list(Array.from({ length: width }, (_, index) => variable(index))),
    list(Array.from({ length: width }, () => u32)),
    "wide",
  );
  equal(result.$, "Done");
  if (result.$ !== "Done") throw new Error("wide product equations failed");
  let index = 0;
  for (
    let equations = result.value;
    equations.$ === "Con";
    equations = equations.tail
  ) {
    equal(equations.head, {
      $: "types.Equation",
      left: variable(index++),
      right: u32,
      subject: "wide",
    });
  }
  equal(index, width);
  equal(types["types.pair_arguments"](list([u32]), list([]), "mismatch"), {
    $: "Fail",
    error: {
      $: "model.Diagnostic",
      code: "type_arity",
      subject: "mismatch",
      message: "type constructor argument counts differ",
    },
  });
});

// The oracle deliberately retains the old algorithm: rewrite the entire type
// once per substitution, without visiting freshly inserted replacements.
function replace(ty: Ty, entry: Substitution, fuel: number): Ty {
  if (fuel === 0) throw complexity;
  switch (ty.$) {
    case "model.VariableTy":
      return entry.$ === "types.Substitution" && ty.index === entry.variable
        ? entry.replacement
        : ty;
    case "model.FunctionTy":
      return arrow(
        replace(ty.parameter, entry, fuel - 1),
        replace(ty.result, entry, fuel - 1),
        replaceRow(ty.effects, entry),
      );
    case "model.ProviderTy":
      return { ...ty, effects: replaceRow(ty.effects, entry) };
    case "model.AppliedTy":
      return {
        ...ty,
        arguments: replaceArguments(ty.arguments, entry, fuel - 1),
      };
    case "model.ProductTy":
      return {
        ...ty,
        elements: replaceArguments(ty.elements, entry, fuel - 1),
      };
    case "model.ArrayTy":
      return { ...ty, element: replace(ty.element, entry, fuel - 1) };
    default:
      return ty;
  }
}

function append<A>(left: List<A>, right: List<A>): List<A> {
  return left.$ === "Nil"
    ? right
    : { $: "Con", head: left.head, tail: append(left.tail, right) };
}

function replaceRow(value: EffectRow, entry: Substitution): EffectRow {
  if (
    entry.$ !== "types.RowSubstitution" ||
    value.tail.$ !== "model.RowVariable" ||
    value.tail.index !== entry.variable
  ) return value;
  return {
    $: "model.EffectRow",
    operations: append(value.operations, entry.replacement.operations),
    tail: entry.replacement.tail,
  };
}

function replaceArguments(
  arguments_: List<Ty>,
  entry: Substitution,
  fuel: number,
): List<Ty> {
  if (fuel === 0) throw complexity;
  if (arguments_.$ === "Nil") return arguments_;
  return {
    $: "Con",
    head: replace(arguments_.head, entry, fuel - 1),
    tail: replaceArguments(arguments_.tail, entry, fuel - 1),
  };
}

function oracle(
  substitutions: readonly Substitution[],
  ty: Ty,
  fuel = 65_536,
): Result<Ty> {
  try {
    return {
      $: "Done",
      value: substitutions.reduce(
        (current, entry) => replace(current, entry, fuel),
        ty,
      ),
    };
  } catch (error) {
    if (error !== complexity) throw error;
    return { $: "Fail", error: complexity };
  }
}

Deno.test("substitution resolution preserves order, repeated entries and replacement boundaries", () => {
  const cases: readonly [readonly Substitution[], Ty][] = [
    [[], arrow(variable(0), applied(variable(1)))],
    [[substitution(0, variable(1)), substitution(1, u32)], variable(0)],
    [[substitution(1, u32), substitution(0, variable(1))], variable(0)],
    [[
      substitution(0, variable(1)),
      substitution(0, boolean),
      substitution(1, u32),
    ], variable(0)],
    [[substitution(0, arrow(variable(0), variable(1)))], variable(0)],
    [[
      substitution(0, arrow(variable(0), variable(2))),
      substitution(2, boolean),
      substitution(0, u32),
    ], variable(0)],
    [[substitution(0, variable(1)), substitution(1, variable(0))], variable(0)],
    [
      [substitution(0, applied(variable(1))), substitution(1, u32)],
      arrow(variable(0), variable(1)),
    ],
    [[substitution(0, u32)], applied({ $: "model.ParameterTy", index: 0n })],
    [[substitution(0, u32)], provider(row([identity]))],
  ];
  for (const [entries, ty] of cases) {
    equal(types["types.resolve"](indexed(entries), ty), oracle(entries, ty));
  }
});

Deno.test("effect row substitution preserves scoped duplicates and distinct variable kinds", () => {
  const tail = { $: "model.RowVariable" as const, index: 100n };
  const ty = arrow(
    variable(100),
    provider(row([identity], tail)),
    row([], tail),
  );
  const entries = [
    rowSubstitution(
      100,
      row([identity], { $: "model.RowVariable", index: 101n }),
    ),
    substitution(100, u32),
    rowSubstitution(101, row([identity])),
  ];
  equal(types["types.resolve"](indexed(entries), ty), {
    $: "Done",
    value: arrow(
      u32,
      provider(row([identity, identity, identity])),
      row([identity, identity]),
    ),
  });
  equal(
    types["types.resolve"](indexed([...entries].reverse()), ty),
    oracle([...entries].reverse(), ty),
  );
  const parameter = provider(row([], { $: "model.RowParameter", index: 100n }));
  equal(types["types.resolve"](indexed(entries), parameter), {
    $: "Done",
    value: parameter,
  });
});

Deno.test("variable-directed resolution agrees with sequential whole-type rewriting", () => {
  let seed = 197;
  const random = (bound: number) => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return (seed >>> 8) % bound;
  };
  const generate = (depth: number): Ty => {
    switch (random(depth === 0 ? 7 : 11)) {
      case 0:
        return u32;
      case 1:
        return boolean;
      case 2:
        return { $: "model.UnitTy" };
      case 3:
        return { $: "model.NeverTy" };
      case 4:
        return provider(row([identity], {
          $: "model.RowVariable",
          index: BigInt(100 + random(5)),
        }));
      case 5:
        return { $: "model.ParameterTy", index: BigInt(random(5)) };
      case 6:
        return variable(random(5));
      case 7:
        return arrow(
          generate(depth - 1),
          generate(depth - 1),
          row(
            random(2) === 0 ? [] : [identity],
            { $: "model.RowVariable", index: BigInt(100 + random(5)) },
          ),
        );
      case 8:
        return applied(
          ...Array.from({ length: random(4) }, () => generate(depth - 1)),
        );
      case 9:
        return {
          $: "model.ProductTy",
          elements: list([generate(depth - 1), generate(depth - 1)]),
        };
      default:
        return { $: "model.ArrayTy", element: generate(depth - 1) };
    }
  };

  for (let trial = 0; trial < 512; trial++) {
    const ty = generate(4);
    const entries = Array.from(
      { length: random(9) },
      () =>
        random(3) === 0
          ? rowSubstitution(
            100 + random(5),
            row(
              random(2) === 0 ? [] : [identity],
              random(2) === 0
                ? { $: "model.ClosedRow" }
                : { $: "model.RowVariable", index: BigInt(100 + random(5)) },
            ),
          )
          : substitution(random(5), generate(3)),
    );
    equal(
      types["types.resolve"](indexed(entries), ty),
      oracle(entries, ty),
      `substitution sequence ${trial}`,
    );
    for (let fuel = 0; fuel <= 9; fuel++) {
      const expected = oracle(entries, ty, fuel);
      equal(
        types["types.resolve_work"](
          indexed(entries),
          BigInt(fuel),
          { $: "types.OneType", value: ty },
        ),
        expected.$ === "Done"
          ? { $: "Done", value: list([expected.value]) }
          : expected,
        `structural bound ${fuel}, substitution sequence ${trial}`,
      );
    }
  }
});

Deno.test("substitution optimization retains occurs checks and unification diagnostics", () => {
  const recursive = types["types.unify"](
    variable(0),
    arrow(u32, variable(0)),
    indexed([]),
    "recursive",
  );
  equal(recursive, {
    $: "Fail",
    error: {
      $: "model.Diagnostic",
      code: "infinite_type",
      subject: "recursive",
      message: "occurs check failed: ?0 occurs in (U32 -> ?0)",
    },
  });
  const mismatch = types["types.unify"](
    variable(0),
    boolean,
    indexed([substitution(0, variable(1)), substitution(1, u32)]),
    "annotation",
  );
  equal(mismatch, {
    $: "Fail",
    error: {
      $: "model.Diagnostic",
      code: "type_mismatch",
      subject: "annotation",
      message: "cannot unify U32 with Bool",
    },
  });
});

function indexed(entries: readonly Substitution[]): Substitutions {
  return types["types.from_list"](list(entries));
}
