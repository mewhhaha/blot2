import { deepStrictEqual as equal } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";

type List<A> =
  | { readonly $: "Nil" }
  | { readonly $: "Con"; readonly head: A; readonly tail: List<A> };

interface TypeId {
  readonly $: "TypeId";
  readonly module_name: string;
  readonly declaration: string;
}

interface EffectRow {
  readonly $: "EffectRow";
  readonly operations: List<TypeId>;
  readonly tail:
    | { readonly $: "ClosedRow" }
    | { readonly $: "RowVariable" | "RowParameter"; readonly index: bigint };
}

type Ty =
  | { readonly $: "ProductTy"; readonly elements: List<Ty> }
  | { readonly $: "ArrayTy"; readonly element: Ty }
  | {
    readonly $:
      | "UnitTy"
      | "U32Ty"
      | "F32Ty"
      | "BoolTy"
      | "NeverTy";
  }
  | { readonly $: "VariableTy" | "ParameterTy"; readonly index: bigint }
  | {
    readonly $: "ProviderTy";
    readonly identity: TypeId;
    readonly effects: EffectRow;
  }
  | {
    readonly $: "AppliedTy";
    readonly identity: TypeId;
    readonly arguments: List<Ty>;
  }
  | {
    readonly $: "FunctionTy";
    readonly parameter: Ty;
    readonly result: Ty;
    readonly effects: EffectRow;
  };

type Substitution = {
  readonly $: "Substitution";
  readonly variable: bigint;
  readonly replacement: Ty;
} | {
  readonly $: "RowSubstitution";
  readonly variable: bigint;
  readonly replacement: EffectRow;
};

type Result<A> =
  | { readonly $: "Done"; readonly value: A }
  | {
    readonly $: "Fail";
    readonly error: {
      readonly $: "Diagnostic";
      readonly code: string;
      readonly subject: string;
      readonly message: string;
    };
  };

const types = compiled as unknown as {
  "types.resolve"(substitutions: List<Substitution>, ty: Ty): Result<Ty>;
  "types.resolve_work"(
    substitutions: List<Substitution>,
    fuel: bigint,
    work: { readonly $: "OneType"; readonly value: Ty },
  ): Result<List<Ty>>;
  "types.unify"(
    left: Ty,
    right: Ty,
    substitutions: List<Substitution>,
    subject: string,
  ): Result<List<Substitution>>;
  "types.pair_arguments"(
    left: List<Ty>,
    right: List<Ty>,
    subject: string,
  ): Result<
    List<{
      readonly $: "Equation";
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
  $: "VariableTy",
  index: BigInt(index),
});
const row = (
  operations: readonly TypeId[] = [],
  tail: EffectRow["tail"] = { $: "ClosedRow" },
): EffectRow => ({ $: "EffectRow", operations: list(operations), tail });
const arrow = (parameter: Ty, result: Ty, effects = row()): Ty => ({
  $: "FunctionTy",
  parameter,
  result,
  effects,
});
const u32: Ty = { $: "U32Ty" };
const boolean: Ty = { $: "BoolTy" };
const identity: TypeId = {
  $: "TypeId",
  module_name: "test",
  declaration: "Box",
};
const applied = (...arguments_: Ty[]): Ty => ({
  $: "AppliedTy",
  identity,
  arguments: list(arguments_),
});
const substitution = (index: number, replacement: Ty): Substitution => ({
  $: "Substitution",
  variable: BigInt(index),
  replacement,
});
const rowSubstitution = (
  index: number,
  replacement: EffectRow,
): Substitution => ({
  $: "RowSubstitution",
  variable: BigInt(index),
  replacement,
});
const provider = (effects: EffectRow): Ty => ({
  $: "ProviderTy",
  identity,
  effects,
});

const complexity = {
  $: "Diagnostic" as const,
  code: "type_complexity",
  subject: "inference",
  message: "type traversal exceeded the 65536-node nesting/width limit",
};

Deno.test("type substitution resolves wide product fields without recursive sibling frames", () => {
  const width = 8192;
  const result = types["types.resolve"](list([substitution(0, boolean)]), {
    $: "ProductTy",
    elements: list(
      Array.from(
        { length: width },
        (_, index) => index % 2 === 0 ? variable(0) : u32,
      ),
    ),
  });
  equal(result.$, "Done");
  if (result.$ !== "Done" || result.value.$ !== "ProductTy") {
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
      $: "Equation",
      left: variable(index++),
      right: u32,
      subject: "wide",
    });
  }
  equal(index, width);
  equal(types["types.pair_arguments"](list([u32]), list([]), "mismatch"), {
    $: "Fail",
    error: {
      $: "Diagnostic",
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
    case "VariableTy":
      return entry.$ === "Substitution" && ty.index === entry.variable
        ? entry.replacement
        : ty;
    case "FunctionTy":
      return arrow(
        replace(ty.parameter, entry, fuel - 1),
        replace(ty.result, entry, fuel - 1),
        replaceRow(ty.effects, entry),
      );
    case "ProviderTy":
      return { ...ty, effects: replaceRow(ty.effects, entry) };
    case "AppliedTy":
      return {
        ...ty,
        arguments: replaceArguments(ty.arguments, entry, fuel - 1),
      };
    case "ProductTy":
      return {
        ...ty,
        elements: replaceArguments(ty.elements, entry, fuel - 1),
      };
    case "ArrayTy":
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
    entry.$ !== "RowSubstitution" || value.tail.$ !== "RowVariable" ||
    value.tail.index !== entry.variable
  ) return value;
  return {
    $: "EffectRow",
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
    [[substitution(0, u32)], applied({ $: "ParameterTy", index: 0n })],
    [[substitution(0, u32)], provider(row([identity]))],
  ];
  for (const [entries, ty] of cases) {
    equal(types["types.resolve"](list(entries), ty), oracle(entries, ty));
  }
});

Deno.test("effect row substitution preserves scoped duplicates and distinct variable kinds", () => {
  const tail = { $: "RowVariable" as const, index: 100n };
  const ty = arrow(
    variable(100),
    provider(row([identity], tail)),
    row([], tail),
  );
  const entries = [
    rowSubstitution(100, row([identity], { $: "RowVariable", index: 101n })),
    substitution(100, u32),
    rowSubstitution(101, row([identity])),
  ];
  equal(types["types.resolve"](list(entries), ty), {
    $: "Done",
    value: arrow(
      u32,
      provider(row([identity, identity, identity])),
      row([identity, identity]),
    ),
  });
  equal(
    types["types.resolve"](list([...entries].reverse()), ty),
    oracle([...entries].reverse(), ty),
  );
  const parameter = provider(row([], { $: "RowParameter", index: 100n }));
  equal(types["types.resolve"](list(entries), parameter), {
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
        return { $: "UnitTy" };
      case 3:
        return { $: "NeverTy" };
      case 4:
        return provider(row([identity], {
          $: "RowVariable",
          index: BigInt(100 + random(5)),
        }));
      case 5:
        return { $: "ParameterTy", index: BigInt(random(5)) };
      case 6:
        return variable(random(5));
      case 7:
        return arrow(
          generate(depth - 1),
          generate(depth - 1),
          row(
            random(2) === 0 ? [] : [identity],
            { $: "RowVariable", index: BigInt(100 + random(5)) },
          ),
        );
      case 8:
        return applied(
          ...Array.from({ length: random(4) }, () => generate(depth - 1)),
        );
      case 9:
        return {
          $: "ProductTy",
          elements: list([generate(depth - 1), generate(depth - 1)]),
        };
      default:
        return { $: "ArrayTy", element: generate(depth - 1) };
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
                ? { $: "ClosedRow" }
                : { $: "RowVariable", index: BigInt(100 + random(5)) },
            ),
          )
          : substitution(random(5), generate(3)),
    );
    equal(
      types["types.resolve"](list(entries), ty),
      oracle(entries, ty),
      `substitution sequence ${trial}`,
    );
    for (let fuel = 0; fuel <= 9; fuel++) {
      const expected = oracle(entries, ty, fuel);
      equal(
        types["types.resolve_work"](
          list(entries),
          BigInt(fuel),
          { $: "OneType", value: ty },
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
    list([]),
    "recursive",
  );
  equal(recursive, {
    $: "Fail",
    error: {
      $: "Diagnostic",
      code: "infinite_type",
      subject: "recursive",
      message: "occurs check failed: ?0 occurs in (U32 -> ?0)",
    },
  });
  const mismatch = types["types.unify"](
    variable(0),
    boolean,
    list([substitution(0, variable(1)), substitution(1, u32)]),
    "annotation",
  );
  equal(mismatch, {
    $: "Fail",
    error: {
      $: "Diagnostic",
      code: "type_mismatch",
      subject: "annotation",
      message: "cannot unify U32 with Bool",
    },
  });
});
