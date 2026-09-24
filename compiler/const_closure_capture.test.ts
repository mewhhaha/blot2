import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";

Deno.test("nested const builders retain only live captures and transport grows linearly", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const layers = 24;
    const source = `
data Builder = Builder { run: U32 -> U32, version: U32 }
const extend = fn builder => do:
  let Builder { run, version } = builder
  return Builder {
    run: fn value => @u32.add (run value) 1,
    version: @u32.add version 1,
  }
const built = do:
  let builder = Builder { run: fn value => value, version: 0 }
${Array.from({ length: layers }, () => "  builder := extend self").join("\n")}
  return builder
const run = fn (value: U32) => do:
  let Builder { run } = built
  return run value
`;
    const artifact = compiler.compile(source);
    const built = artifact.analysis.constants.find((constant) =>
      constant.name === "built"
    );
    ok(built);
    const encoded = JSON.stringify(
      built.value,
      (_, value) => typeof value === "bigint" ? String(value) : value,
    );
    ok(
      encoded.length < layers * 3_000,
      `closure transport retained unrelated builder graphs: ${encoded.length} bytes`,
    );
    const instance = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.bytes),
    );
    const run = instance.exports.run;
    ok(typeof run === "function");
    equal(run(19), 19 + layers);
  } finally {
    compiler.dispose();
  }
});

Deno.test("const closures retain pin references and captured values across shadowing", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    const artifact = compiler.compile(`
const make = fn (expected: U32) => do:
  let unused = [1, 2, 3, 4]
  let matches = fn value => case value of
    ^expected => 7
    _ => 3
  return fn value => do:
    let expected = 99
    return matches value
const check = make 42
const run = fn (value: U32) => check value
`);
    const instance = new WebAssembly.Instance(
      new WebAssembly.Module(artifact.bytes),
    );
    const run = instance.exports.run;
    ok(typeof run === "function");
    equal(run(42), 7);
    equal(run(99), 3);
  } finally {
    compiler.dispose();
  }
});
