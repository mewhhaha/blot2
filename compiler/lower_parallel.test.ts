import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import generated from "../generated/compiler/compiler.js";
import { createSourceFrontend } from "./source_frontend.ts";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";
import type { Cst } from "./syntax.ts";
import { bendArray, type BendList, bendList } from "./bend_list.ts";

type Result<T> = { readonly $: "Done"; readonly value: T } | {
  readonly $: "Fail";
  readonly error: unknown;
};
type LowerDeclarations = (
  nodes: BendList<Cst>,
  prefix: string,
  module: string,
  exported: boolean,
  fuel: bigint,
  scope: unknown,
) => Result<unknown>;
const lower = generated as unknown as {
  "lower.classify"(kind: string): { readonly $: string };
  "lower.prepare_prelude"(root: Cst, fuel: bigint): Result<unknown>;
  "lower.prepare_source"(root: Cst, prelude: unknown): Result<{
    readonly declarations: BendList<Cst>;
    readonly scope: unknown;
  }>;
  "lower.lower_declarations": LowerDeclarations;
  "lower.lower_declarations_sequential": LowerDeclarations;
};

Deno.test("lowering classification retains exact labels and rejects prefix collisions", () => {
  const kinds: Record<string, string> = {
    expression: "Wrapper",
    atom: "Wrapper",
    INTEGER: "Integer",
    FLOAT: "Float",
    prefix_expression: "PrefixNode",
    True: "Truth",
    False: "Falsehood",
    qualified_name: "Name",
    INTRINSIC: "Intrinsic",
    value_declaration: "ValueDeclaration",
    data_type: "DataNode",
    symbolic_fixity: "SymbolicFixity",
    named_fixity: "NamedFixity",
    group: "GroupNode",
    array: "ArrayNode",
    record: "RecordNode",
    application: "ApplicationNode",
    infix_expression: "InfixNode",
    lambda: "LambdaNode",
    case_expression: "CaseNode",
    do_block: "Block",
    binding: "Binding",
    effect_binding: "EffectBinding",
    effect_step: "EffectBinding",
    result: "Return",
    conditional: "Conditional",
    pattern_conditional: "PatternConditional",
    pattern: "PatternWrapper",
    pattern_group: "PatternGroup",
    constructor_pattern: "PatternConstructor",
    IDENT: "PatternName",
    effect_declaration: "EffectNode",
  };
  for (const [kind, expected] of Object.entries(kinds)) {
    equal(lower["lower.classify"](kind), { $: expected });
    for (
      const unknown of [
        kind[0],
        `${kind}_suffix`,
        `prefix_${kind}`,
        kind.slice(1),
      ]
    ) {
      equal(lower["lower.classify"](unknown), {
        $: kinds[unknown] ?? "Unsupported",
      });
    }
  }
  for (
    const unknown of [
      "",
      "🙂",
      "𐐀name",
      "Expression",
      "INTEGER\0",
      "EffectBinding",
    ]
  ) {
    equal(lower["lower.classify"](unknown), { $: "Unsupported" });
  }
});

Deno.test("parallel lowering agrees with serial lowering across batch boundaries", async () => {
  const frontend = await createSourceFrontend({ prelude: "none" });
  try {
    for (const count of [0, 1, 4, 5, 17, 64]) {
      const source = Array.from(
        { length: count },
        (_, index) =>
          `entry const entry_${index} = fn value => @u32.add value ${index}`,
      ).join("\n");
      for (const invalid of [false, true]) {
        const prepared = frontend.prepare(
          invalid
            ? source.replaceAll("@u32.add", "@missing.operation")
            : source,
        );
        const prelude = lower["lower.prepare_prelude"](
          prepared.prelude,
          prepared.nodeCount,
        );
        ok(prelude.$ === "Done");
        const plan = lower["lower.prepare_source"](
          prepared.root,
          prelude.value,
        );
        ok(plan.$ === "Done");
        const args = [
          plan.value.declarations,
          "",
          "main",
          true,
          prepared.nodeCount,
          plan.value.scope,
        ] as const;
        equal(
          lower["lower.lower_declarations"](...args),
          lower["lower.lower_declarations_sequential"](...args),
        );
        const declarations = bendArray(plan.value.declarations);
        for (const position of [0, declarations.length - 1]) {
          if (declarations.length === 0) continue;
          const malformed = declarations.map((node, index) =>
            index === position ? { ...node, children: bendList<Cst>([]) } : node
          );
          const malformedArgs = [
            bendList(malformed),
            ...args.slice(1),
          ] as Parameters<LowerDeclarations>;
          equal(
            lower["lower.lower_declarations"](...malformedArgs),
            lower["lower.lower_declarations_sequential"](...malformedArgs),
          );
        }
      }
    }
  } finally {
    frontend.dispose();
  }
});

Deno.test("native lowering preserves ordered artifacts and diagnostics at 1/2/4/8 threads", async () => {
  const source = Array.from(
    { length: 33 },
    (_, index) =>
      `entry const entry_${index} = fn value => @u32.add value ${index}`,
  ).join("\n");
  const invalid = source.replaceAll("@u32.add", "@missing.operation");
  const js = await createSourceCompiler({ prelude: "none" });
  try {
    const expected = js.compile(source);
    let diagnostic: SourceError | undefined;
    try {
      js.compile(invalid);
    } catch (error) {
      ok(error instanceof SourceError);
      diagnostic = error;
    }
    ok(diagnostic);
    for (const threads of [1, 2, 4, 8]) {
      const native = await createNativeCompiler({ prelude: "none", threads });
      try {
        const artifact = await native.compile(source);
        equal(artifact, expected);
        const { instance } = await WebAssembly.instantiate(artifact.bytes);
        for (let index = 0; index < 33; index++) {
          const fn = instance.exports[`entry_${index}`];
          ok(typeof fn === "function");
          equal(fn(10), index + 10);
        }
        await rejects(() => native.compile(invalid), (error) => {
          ok(error instanceof SourceError);
          equal([error.code, error.start, error.message], [
            diagnostic.code,
            diagnostic.start,
            diagnostic.message,
          ]);
          return true;
        });
        equal(await native.compile(source), expected);
      } finally {
        await native.dispose();
      }
    }
  } finally {
    js.dispose();
  }
});

type Batch = { $: "DeclarationLeaf"; nodes: BendList<Cst> } | {
  $: "DeclarationFork";
  left: Batch;
  right: Batch;
};
const planner = generated as unknown as {
  "lower.declaration_batches"(
    depth: bigint,
    nodes: BendList<Cst>,
    count: bigint,
    small: boolean,
  ): Batch;
  "lower.declaration_cost"(
    fuel: bigint,
    nodes: BendList<Cst>,
    cost: bigint,
  ): bigint;
};
function node(identity: number, cost: number): Cst {
  const leaf: Cst = {
    $: "Cst",
    kind: "leaf",
    field: "",
    text: "",
    offset: BigInt(identity),
    children: bendList([]),
  };
  return {
    ...leaf,
    children: bendList(Array.from({ length: cost - 1 }, () => leaf)),
  };
}
function leaves(batch: Batch): Cst[][] {
  return batch.$ === "DeclarationLeaf"
    ? [bendArray(batch.nodes)]
    : [...leaves(batch.left), ...leaves(batch.right)];
}
Deno.test("lowering cost counts nodes once and saturates at its traversal bound", () => {
  equal(
    planner["lower.declaration_cost"](65536n, bendList([node(0, 70000)]), 0n),
    65536n,
  );
  equal(
    planner["lower.declaration_cost"](
      20n,
      bendList([node(0, 7), node(1, 5)]),
      0n,
    ),
    12n,
  );
});
Deno.test("lowering partitions clustered work without empty leaves or source reordering", () => {
  for (
    const costs of [
      Array(64).fill(20),
      [...Array(8).fill(80), ...Array(56).fill(10)],
      [1, 1, 500, 1, 1],
      [500, 1, 1, 1, 1],
      [1, 1, 1, 1, 500],
    ]
  ) {
    const nodes = costs.map((cost, index) => node(index, cost));
    const batch = planner["lower.declaration_batches"](
      48n,
      bendList(nodes),
      BigInt(nodes.length),
      false,
    );
    const groups = leaves(batch);
    equal(groups.flat(), nodes);
    ok(
      groups.every((group) => group.length >= 1 && group.length <= 4),
      JSON.stringify({
        costs,
        groups: groups.map((group) => group.map((node) => Number(node.offset))),
      }),
    );
    ok(batch.$ === "DeclarationFork");
    const left = leaves(batch.left).flat().reduce(
      (cost, node) => cost + costs[Number(node.offset)],
      0,
    );
    const right = costs.reduce((a, b) => a + b, 0) - left;
    ok(Math.abs(left - right) <= Math.max(...costs));
  }
  const tiny = [node(0, 500), node(1, 1)];
  equal(
    planner["lower.declaration_batches"](48n, bendList(tiny), 2n, true),
    { $: "DeclarationLeaf", nodes: bendList(tiny) },
  );
});
