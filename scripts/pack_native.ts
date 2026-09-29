// Compress the generated executable as package data without changing Bend's
// emitted C or JavaScript. Rename only after the archive is complete.
import { fileURLToPath } from "node:url";

const directory = new URL("../generated/compiler/", import.meta.url);
const source = new URL("blotc", directory);
const destination = new URL("blotc.gz", directory);
const temporary = await Deno.makeTempFile({
  dir: fileURLToPath(directory),
  prefix: ".blotc-",
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
    `Packed generated/compiler/blotc.gz (${compressed.byteLength} bytes)`,
  );
} finally {
  try {
    await Deno.remove(temporary);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
}
