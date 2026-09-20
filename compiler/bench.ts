import { createSourceCompiler } from "./source.ts";

// Measure source-to-Wasm work with a reusable frontend, excluding Bend bootstrap
// generation and Wasm instantiation. The prelude is still linked and checked.
const compiler = await createSourceCompiler();
globalThis.addEventListener("unload", () => compiler.dispose(), { once: true });
const preludeExample = await Deno.readTextFile(
  new URL("../examples/prelude.blot", import.meta.url),
);
const wideModule = [
  ...Array.from(
    { length: 130 },
    (_, index) => `fn helper_${index} () => ${index}`,
  ),
  "export fn answer () => helper_129 ()",
].join("\n");
const dependencyChain = [
  ...Array.from(
    { length: 128 },
    (_, index) =>
      `fn chain_${index} () => ${
        index === 127 ? "42" : `chain_${index + 1} ()`
      }`,
  ),
  "export fn answer () => chain_0 ()",
].join("\n");

for (
  const [name, source] of [
    ["generic prelude example", preludeExample],
    ["131 functions plus prelude", wideModule],
    ["128 forward dependencies plus prelude", dependencyChain],
  ]
) {
  if (!WebAssembly.validate(compiler.compile(source).bytes)) {
    throw new Error(`${name}: benchmark input must compile to valid Wasm`);
  }
  Deno.bench(name, () => {
    compiler.compile(source);
  });
}
