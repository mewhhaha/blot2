import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";
import {
  type Analysis,
  analyze,
  CompilerError,
  type EffectRow,
} from "./host.ts";

function signature(analysis: Analysis, name: string) {
  const found = analysis.functions.find((fn) => fn.name === name);
  ok(found, `missing function ${name}`);
  return found;
}

function labels(row: EffectRow) {
  return row.operations.map((identity) => identity.declaration).sort();
}

Deno.test("datatype value parameters cannot be reused as effect-row binders", () => {
  throws(() =>
    analyze({
      constants: [],
      functions: [],
      data_types: [{
        identity: { $: "TypeId", module_name: "test", declaration: "Callback" },
        parameters: 1n,
        constructors: [{
          name: "Callback",
          payload: {
            $: "FunctionTy",
            parameter: { $: "UnitTy" },
            result: { $: "U32Ty" },
            effects: {
              $: "EffectRow",
              operations: [],
              tail: { $: "RowParameter", index: 0n },
            },
          },
        }],
      }],
    }), (error) => {
    ok(error instanceof CompilerError);
    equal(error.code, "kind_mismatch");
    equal(error.subject, "Callback");
    ok(error.message.includes("value types, not effect rows"));
    return true;
  });
});

Deno.test("one rank-1 callback helper instantiates separately for distinct effects and pure calls", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const analysis = compiler.analyze(`
effect Reader.ask: Unit -> U32
effect Clock.now: Unit -> U32
fn invoke action => action ()
fn read_reader () => invoke Reader.ask
fn read_clock () => invoke Clock.now
fn pure () => invoke (fn () => 42)
`);
    equal(labels(signature(analysis, "read_reader").effect_row), [
      "Reader.ask",
    ]);
    equal(labels(signature(analysis, "read_clock").effect_row), ["Clock.now"]);
    equal(signature(analysis, "pure").effect_row, {
      $: "EffectRow",
      operations: [],
      tail: { $: "ClosedRow" },
    });
    const invoke = signature(analysis, "invoke");
    ok(invoke.parameter.$ === "FunctionTy");
    equal(invoke.parameter.effects.tail, invoke.effect_row.tail);
    ok(invoke.effect_row.tail.$ === "RowVariable");
    ok(invoke.variables.includes(invoke.effect_row.tail.index));
  } finally {
    compiler.dispose();
  }
});

Deno.test("curried composition joins distinct callback effects without effecting partial application", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const analysis = compiler.analyze(`
effect Reader.adjust: U32 -> U32
effect Clock.advance: U32 -> U32
fn compose left => fn right => fn value => left (right value)
fn partial () => compose Reader.adjust Clock.advance
fn both value => compose Reader.adjust Clock.advance value
`);
    equal(labels(signature(analysis, "both").effect_row), [
      "Clock.advance",
      "Reader.adjust",
    ]);
    equal(labels(signature(analysis, "partial").effect_row), []);
    const partial = signature(analysis, "partial");
    ok(partial.result.$ === "FunctionTy");
    equal(labels(partial.result.effects), ["Clock.advance", "Reader.adjust"]);
  } finally {
    compiler.dispose();
  }
});

Deno.test("pure let generalizes latent rows without coupling independent uses", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const analysis = compiler.analyze(`
effect Reader.ask: Unit -> U32
fn answer () => do:
  let invoke = fn action => action ()
  use value <- invoke Reader.ask
  let unrelated = invoke (fn () => True)
  if unrelated:
    return value
  return 0
`);
    equal(labels(signature(analysis, "answer").effect_row), ["Reader.ask"]);
    equal(signature(analysis, "answer").result, { $: "U32Ty" });
  } finally {
    compiler.dispose();
  }
});

Deno.test("returned closures preserve rows shared with an outer callback parameter", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const source = `
effect Reader.ask: Unit -> U32
fn defer action => fn () => action ()
export fn read () => (defer Reader.ask) ()
`;
    const analysis = compiler.analyze(source);
    const defer = signature(analysis, "defer");
    ok(defer.parameter.$ === "FunctionTy");
    ok(defer.result.$ === "FunctionTy");
    equal(defer.parameter.effects.tail, defer.result.effects.tail);
    ok(defer.result.effects.tail.$ === "RowVariable");
    equal(labels(signature(analysis, "read").effect_row), ["Reader.ask"]);
    throws(
      () => compiler.compile(source),
      (error) =>
        error instanceof SourceError && error.code === "backend_effect",
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("returned providers preserve handler effects shared with their constructor parameter", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const source = `
effect Reader.ask: Unit -> U32
fn forward action => @effect.provider Reader.ask action
const provider = forward Reader.ask
export fn missing () => do provider:
  return Reader.ask ()
`;
    const analysis = compiler.analyze(source);
    const forward = signature(analysis, "forward");
    ok(forward.parameter.$ === "FunctionTy");
    ok(forward.result.$ === "ProviderTy");
    equal(forward.parameter.effects.tail, forward.result.effects.tail);
    ok(forward.result.effects.tail.$ === "RowVariable");
    equal(labels(signature(analysis, "missing").effect_row), ["Reader.ask"]);
    throws(
      () => compiler.compile(source),
      (error) =>
        error instanceof SourceError && error.code === "backend_effect",
    );
  } finally {
    compiler.dispose();
  }
});
