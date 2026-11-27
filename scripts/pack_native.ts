// Package the compiler executable. Publish only a complete compressed archive.
import { fileURLToPath } from "node:url";

const directory = new URL("../generated/compiler/", import.meta.url);
const source = new URL(
  "../compiler-goose/build/squidc-goose",
  import.meta.url,
);
const destination = new URL("squidc.gz", directory);
await Deno.mkdir(directory, { recursive: true });
const temporary = await Deno.makeTempFile({
  dir: fileURLToPath(directory),
  prefix: ".squidc-",
  suffix: ".gz",
});
try {
  const binary = await Deno.readFile(source);
  const compressed = await new Response(
    new Blob([binary]).stream().pipeThrough(new CompressionStream("gzip")),
  ).arrayBuffer();
  await Deno.writeFile(temporary, new Uint8Array(compressed));
  await Deno.rename(temporary, destination);
  console.log(
    `Packed generated/compiler/squidc.gz (${compressed.byteLength} bytes)`,
  );
} finally {
  try {
    await Deno.remove(temporary);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
}
