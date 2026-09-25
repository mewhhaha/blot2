import { createNativeCompiler } from "./native.ts";

const compiler = await createNativeCompiler();
let artifact;
try {
  artifact = await compiler.compile(
    await Deno.readTextFile(
      new URL("../examples/prelude.blot", import.meta.url),
    ),
    { analysis: false },
  );
} finally {
  await compiler.dispose();
}
const { instance } = await WebAssembly.instantiate(artifact.bytes);
const answer = instance.exports.answer as (unit: number) => number;
await Deno.mkdir("build", { recursive: true });
await Deno.writeFile("build/example.wasm", artifact.bytes);
console.log(`build/example.wasm: answer(0) = ${answer(0)}`);
const constAnswer = instance.exports.const_answer as WebAssembly.Global;
if (answer(0) !== 42 || constAnswer.value !== 42) {
  throw new Error(
    "Prelude example disagrees between const evaluation and Wasm",
  );
}
console.log(
  `const_answer = ${constAnswer.value}; generic prelude compiled to Wasm`,
);
