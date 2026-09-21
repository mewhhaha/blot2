import { deepStrictEqual as equal } from "node:assert/strict";
import { instantiateGuest } from "./guest.ts";
import { createNativeCompiler } from "./native.ts";

const source = await Deno.readTextFile(
  new URL("../examples/ecs.blot", import.meta.url),
);
const start = performance.now();
const compiler = await createNativeCompiler({ threads: 8 });
let artifact;
try {
  artifact = await compiler.compile(source);
} finally {
  await compiler.dispose();
}
const compileMilliseconds = performance.now() - start;
const guest = await instantiateGuest(artifact.bytes);
try {
  const ticks = 100;
  const runStart = performance.now();
  const checksum = guest.call("run", ticks);
  const runMilliseconds = performance.now() - runStart;
  equal(checksum, 33 + 6 * ticks);
  equal(guest.call("ghost_count", 1), 4);
  equal(guest.call("snapshot", null), 6);
  equal(guest.call("run", 0), 33);
  console.log(
    `Headless source ECS: compile ${compileMilliseconds.toFixed(2)} ms ` +
      `(including compiler startup/shutdown); ${ticks} ticks ` +
      `${runMilliseconds.toFixed(2)} ms; checksum ${checksum}`,
  );
  console.log("The archived graphical sandbox is not part of this demo.");
} finally {
  guest.dispose();
}
