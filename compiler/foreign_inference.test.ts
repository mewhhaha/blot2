import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import {
  type Analysis,
  analyze,
  CompilerError,
  type CoreModule,
  emptyRow,
  type Expr,
  type Operation,
  type Type,
  type TypeId,
} from "./host.ts";
import { createSourceCompiler } from "./source.ts";
import { createIncrementalCompiler } from "./incremental.ts";
import { SourceError } from "./syntax.ts";

const foreign: TypeId = {
  $: "TypeId",
  module_name: "blot:compiler",
  declaration: "Foreign",
};
const unit: Type = { $: "UnitTy" };
const u32: Type = { $: "U32Ty" };
const foreignRow = {
  $: "EffectRow" as const,
  operations: [foreign],
  tail: { $: "ClosedRow" as const },
};

// Analysis lists what an entry reaches; the probe keeps the inspected
// declarations reachable without calling them.
function keep(...names: string[]) {
  return "entry const probe = fn () => do:\n" +
    names.map((name, index) => `  let kept_${index} = ${name}\n`).join("") +
    "  return 0\n";
}

function signature(analysis: Analysis, name: string) {
  const found = analysis.functions.find((fn) => fn.name === name);
  ok(found, `missing function ${name}`);
  return found;
}

function definition(body: Expr, parameter_type: Type = unit): CoreModule {
  return {
    constants: [],
    functions: [{
      name: "test",
      exported: false,
      parameter: "value",
      parameter_type,
      result_type: null,
      body,
    }],
  };
}

function rejectsCore(source: CoreModule, code: string) {
  throws(
    () => analyze(source),
    (error) => error instanceof CompilerError && error.code === code,
  );
}

Deno.test("Foreign is a sealed row label, not an operation declaration or provider", () => {
  const operation: Operation = {
    identity: foreign,
    parameter: unit,
    result: u32,
  };
  rejectsCore(
    { constants: [], functions: [], operations: [operation] },
    "sealed_effect",
  );
  rejectsCore(
    definition({ $: "OperationExpr", identity: foreign }),
    "sealed_effect",
  );
  rejectsCore(
    definition({
      $: "ProviderExpr",
      identity: foreign,
      implementation: {
        $: "LambdaExpr",
        identity: 1n,
        parameter: "ignored",
        parameter_type: unit,
        result_type: u32,
        body: { $: "U32Expr", value: 0 },
      },
    }),
    "sealed_effect",
  );
  rejectsCore(
    definition({ $: "UnitExpr" }, {
      $: "ProviderTy",
      identity: foreign,
      effects: emptyRow(),
    }),
    "sealed_effect",
  );
});

Deno.test("Foreign sealing uses the entire nominal identity and descriptors stay const values", () => {
  const ordinary: TypeId = { ...foreign, module_name: "user/module" };
  const analysis = analyze({
    constants: [{
      name: "same",
      exported: false,
      annotation: null,
      value: {
        $: "EffectSameExpr",
        left: { $: "OperationDescriptorExpr", identity: foreign },
        right: { $: "OperationDescriptorExpr", identity: ordinary },
      },
    }],
    functions: [],
    operations: [{ identity: ordinary, parameter: unit, result: u32 }],
  });
  equal(analysis.constants[0].value, { $: "BoolValue", value: false });
});

Deno.test("source Foreign annotations propagate through higher-order calls and reflect nominally", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const analysis = compiler.analyze(`
const invoke = fn action => action 7
const call = fn (io: U32 -> U32 ! {Foreign}) => invoke io
const twice = fn (io: U32 -> U32 ! {Foreign}) => do:
  use first <- call io
  return io first
const requirements = @effect.of twice
const descriptor = @effect.descriptor Foreign
entry const count = @effect.count requirements
entry const has_foreign = @effect.has requirements Foreign
entry const same = @effect.same descriptor (@effect.descriptor Foreign)
`);
    equal(signature(analysis, "call").effect_row, foreignRow);
    equal(signature(analysis, "twice").effect_row, foreignRow);
    equal(analysis.constants.find((entry) => entry.name === "count")?.value, {
      $: "U32Value",
      value: 1,
    });
    for (const name of ["has_foreign", "same"]) {
      equal(analysis.constants.find((entry) => entry.name === name)?.value, {
        $: "BoolValue",
        value: true,
      });
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("Foreign callback evaluation cannot hide in pure let, const, or pure-arrow annotations", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const cases = [{
      code: "let_effect",
      source: `const bad = fn (io: U32 -> U32 ! {Foreign}) => do:
  let value = io 1
  return value
`,
    }, {
      code: "const_effect",
      source: `const callback: U32 -> U32 ! {Foreign} = fn value => value
entry const denied = callback 1
`,
    }, {
      code: "effect_mismatch",
      source: `const pure = fn (callback: U32 -> U32) => callback 1
const bad = fn (io: U32 -> U32 ! {Foreign}) => pure io
`,
    }];
    for (const { source, code } of cases) {
      throws(() => compiler.analyze(source), (error) => {
        ok(error instanceof SourceError);
        equal(error.code, code, error.message);
        return true;
      });
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("Foreign remains latent when a callback is retained in a returned closure", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const analysis = compiler.analyze(`
const retain = fn (io: U32 -> U32 ! {Foreign}) => fn value => io value
${keep("retain")}`);
    const retained = signature(analysis, "retain");
    equal(retained.effect_row, emptyRow());
    ok(retained.result.$ === "FunctionTy");
    equal(retained.result.effects, foreignRow);
  } finally {
    compiler.dispose();
  }
});

Deno.test("closed row suffixes annotate the outermost arrow unless grouped", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const analysis = compiler.analyze(`
const outer = fn (io: U32 -> U32 -> U32 ! {Foreign}) => ()
const inner = fn (io: U32 -> (U32 -> U32 ! {Foreign})) => ()
const explicitly_pure = fn (io: U32 -> U32 ! {}) => io 1
${keep("outer", "inner", "explicitly_pure")}`);
    const outer = signature(analysis, "outer").parameter;
    const inner = signature(analysis, "inner").parameter;
    ok(outer.$ === "FunctionTy" && outer.result.$ === "FunctionTy");
    ok(inner.$ === "FunctionTy" && inner.result.$ === "FunctionTy");
    equal(outer.effects, foreignRow);
    equal(outer.result.effects, emptyRow());
    equal(inner.effects, emptyRow());
    equal(inner.result.effects, foreignRow);
    equal(signature(analysis, "explicitly_pure").effect_row, emptyRow());
  } finally {
    compiler.dispose();
  }
});

Deno.test("closed rows resolve declared operations, deduplicate sets, and preserve ordinary handling", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const analysis = compiler.analyze(`
effect Reader.ask: U32 -> U32
const mixed = fn (callback: U32 -> U32 ! {Reader.ask, Foreign, Reader.ask}) => callback 1
const provider = @effect.provider Reader.ask (fn value => value)
const supplied = fn (callback: U32 -> U32 ! {Reader.ask}) => do provider:
  return callback 1
data Callback = Callback (U32 -> U32 ! {Foreign})
const unwrap = fn wrapped => case wrapped of
  Callback io => io
${keep("mixed", "supplied", "unwrap")}`);
    equal(signature(analysis, "mixed").effect_row.operations, [
      foreign,
      { $: "TypeId", module_name: "main", declaration: "Reader.ask" },
    ]);
    equal(signature(analysis, "supplied").effect_row, emptyRow());
    equal(signature(analysis, "unwrap").result, {
      $: "FunctionTy",
      parameter: u32,
      result: u32,
      effects: foreignRow,
    });
  } finally {
    compiler.dispose();
  }
});

Deno.test("source cannot shadow Foreign, provide it, or silently discard invalid rows", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const cases = [{
      source: "effect Foreign: Unit -> U32\n",
      code: "sealed_effect",
    }, {
      source: "const denied = @effect.provider Foreign (fn () => 1)\n",
      code: "sealed_effect",
    }, {
      source: "const bad = fn (value: U32 ! {Foreign}) => value\n",
      code: "invalid_effect_annotation",
    }, {
      source: "const bad = fn (value: U32 -> U32 ! {Missing}) => value\n",
      code: "unknown_effect",
    }, {
      source: "effect Reader.ask: Unit -> U32 ! {Foreign}\n",
      code: "operation_signature",
    }];
    for (const { source, code } of cases) {
      throws(() => compiler.analyze(source), (error) => {
        ok(error instanceof SourceError);
        equal(error.code, code, error.message);
        return true;
      });
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("closed row annotation edits invalidate reflected constants without stale group reuse", async () => {
  const incremental = await createIncrementalCompiler({ prelude: "none" });
  const clean = await createSourceCompiler({ prelude: "none" });
  try {
    for (const labels of ["", "Foreign", "Foreign, Reader.ask", ""]) {
      const source = `
effect Reader.ask: U32 -> U32
const call = fn (callback: U32 -> U32 ! {${labels}}) => callback 1
const requirements = @effect.of call
entry const count = @effect.count requirements
entry const has_foreign = @effect.has requirements Foreign
`;
      const result = await incremental.compile(source);
      const expected = clean.compile(source);
      equal(result.artifact.bytes, expected.bytes);
      equal(result.artifact.analysis.constants, expected.analysis.constants);
      const instance = new WebAssembly.Instance(
        new WebAssembly.Module(result.artifact.bytes),
        {
          "blot:host/1": {
            call_u32_u32: () => {
              throw new Error(
                "Effect reflection must not invoke a host callback",
              );
            },
          },
        },
      );
      const count = instance.exports.count;
      const hasForeign = instance.exports.has_foreign;
      ok(count instanceof WebAssembly.Global);
      ok(hasForeign instanceof WebAssembly.Global);
      equal(count.value, labels === "" ? 0 : labels.includes(",") ? 2 : 1);
      equal(hasForeign.value, labels === "" ? 0 : 1);
      const repeated = await incremental.compile(source);
      equal(repeated.stats.groups_checked, 0);
      equal(repeated.stats.constants_evaluated, 0);
      equal(repeated.artifact.bytes, result.artifact.bytes);
    }
  } finally {
    clean.dispose();
    incremental.dispose();
  }
});
