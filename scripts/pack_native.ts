// Package the Zig executable. Publish only a complete compressed archive.
import { fileURLToPath } from "node:url";

const directory = new URL("../generated/compiler/", import.meta.url);
const source = new URL("../zig-native/zig-out/bin/blotc", import.meta.url);
const destination = new URL("blotc.gz", directory);
await Deno.mkdir(directory, { recursive: true });
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
