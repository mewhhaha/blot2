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

type Ty =
  | {
    readonly $:
      | "model.UnitTy"
      | "model.U32Ty"
      | "model.BoolTy"
      | "model.NeverTy";
  }
  | { readonly $: "VariableTy" | "ParameterTy"; readonly index: bigint }
  | { readonly $: "NominalTy"; readonly identity: TypeId }
  | {
    readonly $: "AppliedTy";
    readonly identity: TypeId;
    readonly arguments: List<Ty>;
  }
  | { readonly $: "FunctionTy"; readonly parameter: Ty; readonly result: Ty };

interface Substitution {
  readonly $: "Substitution";
  readonly variable: bigint;
  readonly replacement: Ty;
}

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
const arrow = (parameter: Ty, result: Ty): Ty => ({
  $: "FunctionTy",
  parameter,
  result,
});
const u32: Ty = { $: "model.U32Ty" };
const boolean: Ty = { $: "model.BoolTy" };
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

const complexity = {
  $: "Diagnostic" as const,
  code: "type_complexity",
  subject: "inference",
  message: "type traversal exceeded the 65536-node nesting/width limit",
};

// The oracle deliberately retains the old algorithm: rewrite the entire type
// once per substitution, without visiting freshly inserted replacements.
function replace(ty: Ty, entry: Substitution, fuel: number): Ty {
  if (fuel === 0) throw complexity;
  switch (ty.$) {
    case "VariableTy":
      return ty.index === entry.variable ? entry.replacement : ty;
    case "FunctionTy":
      return arrow(
        replace(ty.parameter, entry, fuel - 1),
        replace(ty.result, entry, fuel - 1),
      );
    case "AppliedTy":
      return {
        ...ty,
        arguments: replaceArguments(ty.arguments, entry, fuel - 1),
      };
    default:
      return ty;
  }
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
    [[substitution(0, u32)], { $: "NominalTy", identity }],
  ];
  for (const [entries, ty] of cases) {
    equal(types["types.resolve"](list(entries), ty), oracle(entries, ty));
  }
});

Deno.test("variable-directed resolution agrees with sequential whole-type rewriting", () => {
  let seed = 197;
  const random = (bound: number) => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return (seed >>> 8) % bound;
  };
  const generate = (depth: number): Ty => {
    switch (random(depth === 0 ? 7 : 9)) {
      case 0:
        return u32;
      case 1:
        return boolean;
      case 2:
        return { $: "model.UnitTy" };
      case 3:
        return { $: "model.NeverTy" };
      case 4:
        return { $: "NominalTy", identity };
      case 5:
        return { $: "ParameterTy", index: BigInt(random(5)) };
      case 6:
        return variable(random(5));
      case 7:
        return arrow(generate(depth - 1), generate(depth - 1));
      default:
        return applied(
          ...Array.from({ length: random(4) }, () => generate(depth - 1)),
        );
    }
  };

  for (let trial = 0; trial < 512; trial++) {
    const ty = generate(4);
    const entries = Array.from(
      { length: random(9) },
      () => substitution(random(5), generate(3)),
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
