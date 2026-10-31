import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const adjacentSource = `import * as iter from "std/iter"
const sum = func (total: U32) => return func (value: U32) => return total + value
entry const arrays = func (input: U32) => return iter.fold_left (func total => return func window => return total + iter.fold_left sum 0 window) 0 (iter.windows (input / 1024 + 1) (@array.generate (input % 1024) identity))
entry const lists = func (input: U32) => return iter.fold_left (func total => return func window => return total + iter.fold_left sum 0 window) 0 (iter.windows (input / 1024 + 1) (@list.generate (input % 1024) identity))
entry const references = func (seed: U32) => return do:
  let original = #[#[seed, seed + 1], #[9, 10]].iter
  use step <- original.next
  let $Some (value, rest) = step else:
    break #[999]
  for index in 0..24:
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      @panic "pressure"
  use again <- original.next
  let $Some (saved, _) = again else:
    break #[998]
  use next <- rest.next
  let $Some (second, _) = next else:
    break #[997]
  break #[value[0], value[1], saved[0], second[0]]
entry const retained = func (seed: U32) => return do:
  use step <- #[seed, seed + 1].iter.next
  let $Some (first, rest) = step else:
    break 999
  use next <- rest.next
  let $Some (second, _) = next else:
    break 998
  let $Some (again, _) = step else:
    break 997
  break first + second + again
const make = func (host: U32 -> U32 ! {Foreign}) => return do:
  use seed <- host 41
  break (@array.fill 2 seed).iter
entry const ordered = func (host: U32 -> U32 ! {Foreign}) => return do:
  use step <- (make host).next
  let $Some (value, rest) = step else:
    break 999
  use result <- host value
  break result
`;

function directPatterns(text: string) {
  return text.replaceAll(
    /  use (\w+) <- ([^\n]+)\n  let ($Some [^\n]+) = \1 else:/g,
    "  let $3 = $2 else:",
  );
}

for (const direct of [false, true]) {
  let source = adjacentSource;
  let label = "adjacent";
  if (direct) {
    source = directPatterns(source);
    // This control deliberately observes its step twice and must retain it.
    const start = adjacentSource.indexOf("entry const retained");
    const end = adjacentSource.indexOf("const make");
    source = source.slice(0, source.indexOf("entry const retained")) +
      adjacentSource.slice(start, end) +
      source.slice(source.indexOf("const make"));
    source = source.replace(
      "  let $Some (value, rest) = (make host).next else:",
      "  use cursor <- make host\n  let $Some (value, rest) = cursor.next else:",
    );
    label = "direct";
  }

  Deno.test(`${label} pure cursor steps preserve windows reference snapshots saved steps and receiver effects`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-step-sink-" });
    const entry = `${directory}/main.blot`;
    try {
      for (const codegenTier of ["optimized", "development"] as const) {
        const compiler = await createZigProjectCompiler({
          executable: Deno.args[0],
          entry,
          codegenTier,
          prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
          stdRoot: new URL("../../std", import.meta.url).pathname,
          cacheDirectory: false,
        });
        try {
          const built = await compiler.build({ sources: { [entry]: source } });
          assert(built.success, JSON.stringify(built));
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(built.bytes, { asynchronous });
            const invoke = async (name: string, argument: unknown) => {
              if (asynchronous) return await guest.callAsync(name, argument);
              return guest.call(name, argument);
            };
            try {
              for (const width of [1, 2, 3, 17]) {
                for (
                  const count of [0, 1, width - 1, width, width + 1, 245, 501]
                ) {
                  const expected =
                    (width * Math.max(0, count - width + 1) * (count - 1) /
                      2) >>>
                    0;
                  for (const name of ["arrays", "lists"]) {
                    assert.equal(
                      await invoke(name, (width - 1) * 1024 + count),
                      expected,
                    );
                  }
                }
              }
              assert.deepEqual(
                await invoke("references", 41),
                Uint32Array.of(41, 42, 41, 9),
              );
              assert.equal(await invoke("retained", 41), 124);
              const trace: number[] = [];
              const host = (value: number) => {
                trace.push(value);
                return value + 1;
              };
              let capability;
              if (asynchronous) {
                capability = guest.capabilityAsync({
                  parameter: "U32",
                  result: "U32",
                  call: async (value) => {
                    await Promise.resolve();
                    return host(value);
                  },
                });
              } else {capability = guest.capability({
                  parameter: "U32",
                  result: "U32",
                  call: host,
                });}
              assert.equal(await invoke("ordered", capability), 43);
              assert.deepEqual(trace, [41, 42]);
              const stopped: number[] = [];
              const stop = (value: number): never => {
                stopped.push(value);
                throw new Error("receiver stop");
              };
              let rejected;
              if (asynchronous) {
                rejected = guest.capabilityAsync({
                  parameter: "U32",
                  result: "U32",
                  call: async (value) => {
                    await Promise.resolve();
                    return stop(value);
                  },
                });
              } else {rejected = guest.capability({
                  parameter: "U32",
                  result: "U32",
                  call: stop,
                });}
              await assert.rejects(
                invoke("ordered", rejected),
                /Host callback (threw|rejected)/,
              );
              assert.deepEqual(stopped, [41]);
              assert.equal(await invoke("ordered", capability), 43);
              assert.deepEqual(trace, [41, 42, 41, 42]);
            } finally {
              guest.dispose();
            }
          }
        } finally {
          await compiler.dispose();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });

  Deno.test(`${label} collection steps rederive archived producers retained edits and checkpoint restart`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-step-archive-" });
    const entry = `${directory}/main.blot`;
    const dependencies = `${directory}/inputs.blotdep`;
    const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const original = await Deno.readTextFile(prelude);
    const needle = "then $Some (@cursor.value cursor, @cursor.advance cursor)";
    const changed = original.replace(
      needle,
      "then $Some (@u32.add (@cursor.value cursor) 1, @cursor.advance cursor)",
    );
    assert.notEqual(original, changed);
    let text = `entry const pull = func (seed: U32) => return do:
  use step <- (@array.fill 1 seed).iter.next
  let $Some (value, _) = step else:
    break 999
  break value
`;
    if (direct) text = directPatterns(text);
    try {
      await Deno.writeTextFile(entry, text);
      const packed = await new Deno.Command(Deno.args[0], {
        args: [
          "dependencies",
          entry,
          dependencies,
          "--prelude",
          prelude,
          "--std-root",
          stdRoot,
        ],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(
        packed.success,
        new TextDecoder().decode(packed.stdout) +
          new TextDecoder().decode(packed.stderr),
      );
      for (const codegenTier of ["optimized", "development"] as const) {
        const options = {
          executable: Deno.args[0],
          entry,
          prelude,
          stdRoot,
          codegenTier,
          cacheDirectory: false as const,
        };
        const compiler = await createZigProjectCompiler({
          ...options,
          dependencies,
        });
        let checkpoint: Uint8Array<ArrayBuffer>;
        let expected: Uint8Array<ArrayBuffer>;
        try {
          for (const producer of [original, changed, original]) {
            const sources = { [prelude]: producer };
            const built = await compiler.build({ sources });
            assert(built.success, JSON.stringify(built));
            const fresh = await createZigProjectCompiler(options);
            try {
              const control = await fresh.build({ sources });
              assert(control.success, JSON.stringify(control));
              assert.deepEqual(built.bytes, control.bytes);
            } finally {
              await fresh.dispose();
            }
            const guest = await instantiateGuest(built.bytes);
            try {
              let value = 41;
              if (producer === changed) value = 42;
              assert.equal(guest.call("pull", 41), value);
            } finally {
              guest.dispose();
            }
            expected = built.bytes;
          }
          checkpoint = await compiler.exportCheckpoint();
        } finally {
          await compiler.dispose();
        }
        const restarted = await createZigProjectCompiler({
          ...options,
          dependencies,
          checkpoint: checkpoint!,
        });
        try {
          const built = await restarted.build();
          assert(built.success, JSON.stringify(built));
          assert.deepEqual(built.bytes, expected!);
          const guest = await instantiateGuest(built.bytes);
          try {
            assert.equal(guest.call("pull", 41), 41);
          } finally {
            guest.dispose();
          }
        } finally {
          await restarted.dispose();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
