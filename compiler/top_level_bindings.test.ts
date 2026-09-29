import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createFrontend, SourceError } from "./syntax.ts";

Deno.test("top-level const and let lambdas accept whole-binding annotations", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(`
const identity: a -> a = fn value => value
entry const increment: U32 -> U32 = fn value => @u32.add value 1
entry let runtime: U32 -> U32 = fn value => increment value
entry const answer = fn () => runtime (identity 41)
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes)).exports;
    equal((exports.answer as CallableFunction)(), 42);
    equal((exports.runtime as CallableFunction)(41), 42);
    throws(
      () =>
        compiler.compile(
          "const invalid: U32 -> Bool = fn value => @u32.add value 1",
        ),
      (error) => error instanceof SourceError && error.code === "type_mismatch",
    );
  } finally {
    compiler.dispose();
  }
});

Deno.test("grouped top-level lambdas retain mutually recursive function bindings", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(`
entry const recurse = (fn (value: U32) -> U32 => step value)
entry const step = fn (value: U32) -> U32 => case @u32.eq value 0 of
  #True => 42
  #False => recurse (@u32.sub value 1)
entry const answer = fn () => recurse 5
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes)).exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("qualified top-level function bindings use ordinary annotations and calls", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(`
type Counter is data = #Counter U32
const Counter.increment: Counter -> Counter = fn value => case value of
  #Counter number => #Counter (@u32.add number 1)
entry const answer = fn () => case Counter.increment (#Counter 41) of
  #Counter number => number
`);
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(artifact.bytes)).exports;
    equal((exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("top-level named fn and pub modifiers are rejected while pub is an ordinary identifier", async () => {
  const frontend = await createFrontend();
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    for (
      const source of [
        "fn answer () => 42",
        "pub type Box is data = Box U32",
        "pub type Read is effect = Unit -> U32",
        "entry type Box is data = Box U32",
      ]
    ) {
      throws(() => frontend.parse(source), SourceError);
    }
    // Only `entry` may precede const or let; the grammar reads the modifier
    // as an identifier so that `entry` stays an ordinary name elsewhere.
    for (
      const source of [
        "pub const answer = fn () => 42",
        "pub let answer = fn () => 42",
      ]
    ) {
      throws(
        () => compiler.compile(source),
        (error) =>
          error instanceof SourceError && error.code === "unknown_modifier" &&
          error.start === 0,
      );
    }
    ok(frontend.parse("const pub = 42\nconst answer = fn () => pub\n").root);
  } finally {
    frontend.dispose();
    compiler.dispose();
  }
});
