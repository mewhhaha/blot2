import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";
import { gdevProject } from "../../scripts/integration/gdev_project.ts";

export const sizes = [2, 8, 64];

export async function captureIntents(root: string, compilerPath: string) {
  const project = await gdevProject(
    root,
    resolve("std"),
    "performance/modernize/pile_handles.blot",
    compilerPath,
  );
  const original = await Deno.readTextFile(project.entry);
  function insert(source: string, old: string, text: string) {
    assert.equal(source.split(old).length, 2, old);
    return source.replace(old, text);
  }
  // Collect the entering and exiting plan of each real successful lookup.
  let source = insert(
    original,
    "  let output =",
    "  let events: GrowArray U32 = #[]\n  let output =",
  );
  source = insert(
    source,
    "        output[size + worker] := self + U32.to_f32 got.cargo",
    `        for value in #[chosen, got]:
          let encoded = plan.encode value
          for index in 5 .. encoded.length:
            @storage.push events encoded[index]
        output[size + worker] := self + U32.to_f32 got.cargo`,
  );
  source = insert(source, "  return output", "  return @storage.freeze events");
  const compiler = await createZigProjectCompiler(project);
  let emitted: Uint8Array<ArrayBuffer>;
  try {
    const r = await compiler.build({ sources: { [project.entry]: source } });
    if (!r.success) throw new Error(JSON.stringify(r.diagnostics));
    emitted = r.bytes;
  } finally {
    await compiler.dispose();
  }
  const guest = await instantiateGuest(emitted);
  const trace: number[][] = [];
  const payloadWords = [0, 4, 1, 1];
  try {
    for (const n of sizes) {
      const stream = guest.call("handles", n) as Uint32Array;
      for (let i = 0; i < stream.length;) {
        const tag = stream[i++];
        assert(tag < 4 && i + payloadWords[tag] <= stream.length);
        trace.push([tag, ...stream.subarray(i, i + payloadWords[tag])]);
        i += payloadWords[tag];
      }
    }
  } finally {
    guest.dispose();
  }
  assert(trace.length > 0);
  return trace;
}
