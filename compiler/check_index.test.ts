import { deepStrictEqual as equal, ok } from "node:assert/strict";
import compiled from "../generated/compiler/compiler.js";
import { toBendModel } from "./bend_abi.ts";
import {
  analyze,
  CompilerError,
  type CoreModule,
  type DataType,
  type Operation,
  type TypeId,
} from "./host.ts";
import { fn, module, operation, u32Type, unit } from "./fixtures.ts";

type List<A> = { readonly $: "Nil" } | {
  readonly $: "Con";
  readonly head: A;
  readonly tail: List<A>;
};

interface Diagnostic {
  readonly $: "model.Diagnostic";
  readonly code: string;
  readonly subject: string;
  readonly message: string;
}

type Result<A> = { readonly $: "Done"; readonly value: A } | {
  readonly $: "Fail";
  readonly error: Diagnostic;
};

function list<A>(values: readonly A[]): List<A> {
  return values.reduceRight<List<A>>(
    (tail, head) => ({ $: "Con", head, tail }),
    { $: "Nil" },
  );
}

function call<A>(name: string, ...args: unknown[]): A {
  const exports = compiled as unknown as Record<
    string,
    (...args: unknown[]) => A
  >;
  return exports[name](...args.map(toBendModel));
}

const done = <A>(value: A): Result<A> => ({ $: "Done", value });
const fail = (
  code: string,
  subject: string,
  message: string,
): Result<never> => ({
  $: "Fail",
  error: { $: "model.Diagnostic", code, subject, message },
});
const unitResult = done({ $: "Unit" });
const sameIdentity = (left: TypeId, right: TypeId) =>
  left.module_name === right.module_name &&
  left.declaration === right.declaration;
const showIdentity = ({ module_name, declaration }: TypeId) =>
  `${module_name}::${declaration}`;

const wireOperation = (value: Operation) =>
  toBendModel({
    $: "Operation",
    ...value,
  });

function firstDuplicate<A>(
  values: readonly A[],
  same: (a: A, b: A) => boolean,
) {
  return values.find((value, index) =>
    values.slice(index + 1).some((other) => same(value, other))
  );
}

Deno.test("indexed name and lambda validation retain first-duplicate priority", () => {
  const alphabets = ["a", "b", "雪", "🙂", "__proto__", "constructor", ""];
  let seed = 1931;
  const random = () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed >>> 8;
  };
  const examples = [[], ["a"], ["a", "b", "b", "a"]];
  for (let trial = 0; trial < 128; trial++) {
    examples.push(Array.from(
      { length: random() % 24 },
      () => alphabets[random() % alphabets.length],
    ));
  }
  for (const names of examples) {
    const duplicate = firstDuplicate(names, (a, b) => a === b);
    equal(
      call("check.unique_names", list(names)),
      duplicate === undefined
        ? unitResult
        : fail("duplicate_name", duplicate, "duplicate top-level definition"),
    );
    const identities = names.map((name) => BigInt(alphabets.indexOf(name)));
    const lambdaDuplicate = firstDuplicate(identities, (a, b) => a === b);
    equal(
      call("check.unique_lambdas", list(identities)),
      lambdaDuplicate === undefined ? unitResult : fail(
        "duplicate_lambda",
        String(lambdaDuplicate),
        "lambda identity must be unique within its module",
      ),
    );
  }
});

Deno.test("operation indexes preserve first matches and distinct nominal identities", () => {
  const identities: TypeId[] = [
    { $: "TypeId", module_name: "a::b", declaration: "c" },
    { $: "TypeId", module_name: "a", declaration: "b::c" },
    { $: "TypeId", module_name: "雪🙂", declaration: "Type" },
    { $: "TypeId", module_name: "雪", declaration: "🙂Type" },
    { $: "TypeId", module_name: "", declaration: "" },
  ];
  const operations: Operation[] = identities.map((identity) => ({
    ...operation("ignored"),
    identity,
  }));
  const reordered = [
    operations[0],
    operations[1],
    { ...operations[1], result: { $: "BoolTy" as const } },
    { ...operations[0], result: { $: "BoolTy" as const } },
  ];
  for (
    const registrations of [
      [],
      operations,
      reordered,
      [...operations].reverse(),
    ]
  ) {
    const duplicate = firstDuplicate(
      registrations,
      (a, b) => sameIdentity(a.identity, b.identity),
    );
    const raw = list(registrations.map(wireOperation));
    equal(
      call("check.validate_operations", raw, list([])),
      duplicate === undefined ? unitResult : fail(
        "duplicate_type",
        showIdentity(duplicate.identity),
        "duplicate nominal identity",
      ),
    );
    for (const identity of identities) {
      const found = registrations.find((entry) =>
        sameIdentity(entry.identity, identity)
      );
      equal(
        call("type_data.operation", raw, identity),
        found ? { $: "Some", value: wireOperation(found) } : { $: "None" },
      );
    }
  }
});

function diagnosis(source: CoreModule) {
  try {
    analyze(source);
    throw new Error("expected a compiler diagnostic");
  } catch (error) {
    ok(error instanceof CompilerError);
    return { code: error.code, subject: error.subject, detail: error.detail };
  }
}

Deno.test("indexed datatype validation preserves interleaved error ordering", () => {
  const a = operation("A").identity;
  const b = operation("B").identity;
  const type = (identity: TypeId): DataType => ({
    identity,
    parameters: 0n,
    constructors: [{ name: identity.declaration, payload: u32Type }],
  });
  const empty: DataType = { ...type(a), constructors: [] };
  equal(diagnosis(module([], { data_types: [empty, type(b), type(b)] })), {
    code: "invalid_annotation",
    subject: showIdentity(a),
    detail: "data declarations need at least one constructor",
  });
  equal(diagnosis(module([], { data_types: [empty, type(b), empty] })), {
    code: "duplicate_type",
    subject: showIdentity(a),
    detail: "duplicate nominal identity",
  });
  equal(
    diagnosis(module([], {
      data_types: [type(a), { ...type(b), parameters: 1n }, type(a)],
      operations: [operation("read")],
    })),
    {
      code: "duplicate_type",
      subject: showIdentity(a),
      detail: "duplicate nominal identity",
    },
  );
  equal(
    diagnosis(module([fn("duplicate", unit), fn("duplicate", unit)], {
      data_types: [type(a)],
      operations: [
        operation("b"),
        operation("a"),
        operation("a"),
        operation("b"),
      ],
    })),
    {
      code: "duplicate_type",
      subject: showIdentity(operation("b").identity),
      detail: "duplicate nominal identity",
    },
  );
});

Deno.test("operation signatures reject open or malformed types before duplicate values", () => {
  const identity = operation("Reader.ask").identity;
  const invalid: Operation = {
    identity,
    parameter: { $: "VariableTy", index: 0n },
    result: u32Type,
  };
  equal(
    diagnosis(module([fn("duplicate", unit), fn("duplicate", unit)], {
      operations: [invalid],
    })),
    {
      code: "invalid_annotation",
      subject: showIdentity(identity),
      detail: "inference variables are compiler-owned",
    },
  );
  equal(
    diagnosis(module([], { operations: [invalid, invalid] })),
    {
      code: "duplicate_type",
      subject: showIdentity(identity),
      detail: "duplicate nominal identity",
    },
  );
  for (
    const tail of [
      { $: "RowVariable" as const, index: 0n },
      { $: "RowParameter" as const, index: 0n },
    ]
  ) {
    const diagnosed = diagnosis(module([], {
      operations: [{
        identity,
        parameter: {
          $: "FunctionTy",
          parameter: u32Type,
          result: u32Type,
          effects: { $: "EffectRow", operations: [], tail },
        },
        result: u32Type,
      }],
    }));
    equal(diagnosed.code, "invalid_annotation");
    equal(diagnosed.subject, showIdentity(identity));
  }
});
