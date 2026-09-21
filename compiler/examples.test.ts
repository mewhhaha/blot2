import { deepStrictEqual as equal } from "node:assert/strict";
import { instantiateGuest } from "./guest.ts";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { loadSourceProject } from "./source_project.ts";

Deno.test("ported examples compile identically in JS/native and execute on the current ABI", async () => {
  const js = await createSourceCompiler();
  const native = await createNativeCompiler({ threads: 8 });
  try {
    for (const name of ["ecs", "syntax", "host_capabilities"]) {
      const source = await Deno.readTextFile(
        new URL(`../examples/${name}.blot`, import.meta.url),
      );
      const expected = js.compile(source);
      const artifact = await native.compile(source);
      equal(artifact, expected, name);
      const project = await loadSourceProject(
        new URL(`../examples/${name}.blot`, import.meta.url),
      );
      equal(
        await native.compile(project),
        js.compile(project),
        `${name} project`,
      );
      const guest = await instantiateGuest(artifact.bytes);
      try {
        if (name === "ecs") {
          for (const ticks of [0, 1, 2, 10]) {
            equal(guest.call("run", ticks), 33 + 6 * ticks);
            equal(guest.call("ghost_count", ticks), ticks === 0 ? 0 : 4);
          }
          equal(guest.call("snapshot", null), 6);
          equal(guest.call("run", 0), 33);
        } else if (name === "syntax") {
          equal(guest.read("operator_example"), 7);
          equal(guest.call("recursive_example", 5), 120);
          equal(guest.call("short_circuit", null), false);
          equal(guest.call("lazy_fallback", null), 42);
          equal(guest.call("matching_example", null), 42);
          equal(guest.call("event_example", null), 42);
          equal(guest.call("vector_example", null), 50);
          equal(guest.call("array_snapshot", null), 22);
          equal(guest.call("provider_example", null), 42);
        } else {
          const calls: number[] = [];
          const dispatch = guest.capability({
            parameter: "U32",
            result: "U32",
            call(command) {
              calls.push(command);
              return command === 1007 ? 0 : command;
            },
          });
          equal(guest.read("uses_host"), true);
          equal(guest.call("main", dispatch), 2042);
          equal(calls.splice(0), [1007, 2042]);
          equal(guest.call("render_only", dispatch), 42);
          equal(calls.splice(0), [42]);
          const denied = guest.capability({
            parameter: "U32",
            result: "U32",
            call(command) {
              calls.push(command);
              return 9;
            },
          });
          equal(guest.call("main", denied), 9);
          equal(calls, [1007]);
        }
      } finally {
        guest.dispose();
      }
    }
  } finally {
    js.dispose();
    await native.dispose();
  }
});
