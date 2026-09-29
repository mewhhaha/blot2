/** Freeze real protocol requests for the native RSS/CPU experiment. */
import { join } from "node:path";
import { benchmarkWorkloads } from "../benchmark_workloads.ts";
import { createSourceFrontend } from "../source_frontend.ts";

const output = Deno.args[0];
if (!output || Deno.args.length !== 1) {
  throw new Error("Usage: memory_fixtures.ts <output-directory>");
}
await Deno.mkdir(output, { recursive: true });
const fixtures = benchmarkWorkloads.filter((w) =>
  ["lexical_256", "nominal_256", "balanced_64"].includes(w.name)
).map(({ name, source }) => ({ name, source }));
fixtures.push({
  name: "wide_8192",
  source: "entry const values = fn () => [" +
    Array.from({ length: 8192 }, (_, i) => i).join(",") +
    "]\nentry const answer = fn () => @array.get (values ()) 8191\n",
});
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
const frontend = await createSourceFrontend({ prelude: "none" });
const rows = [];
try {
  for (const { name, source } of fixtures) {
    const payload = (await frontend.prepareNative(source)).encode(
      "compile",
      10000n,
    );
    const frame = new Uint8Array(payload.length + 4);
    new DataView(frame.buffer).setUint32(0, payload.length / 4, true);
    frame.set(payload, 4);
    await Deno.writeFile(join(output, `${name}.frame`), frame);
    rows.push({
      name,
      source_sha256: await hash(new TextEncoder().encode(source)),
      frame_sha256: await hash(frame),
      frame_bytes: frame.length,
    });
  }
} finally {
  frontend.dispose();
}
await Deno.writeTextFile(
  join(output, "manifest.json"),
  JSON.stringify(rows, null, 2) + "\n",
);
