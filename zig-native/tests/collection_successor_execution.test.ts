import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = `const progress = fn count => fn values => do:
  let original = values.iter
  let cursor = original
  let index = 0
  for ever:
    if index == count:
      break
    use step <- cursor.next
    let #Some (_, rest) = step else:
      break
    cursor := rest
    index := self + 1
  return (original, cursor, index)
const inspect = fn count => fn values => do:
  let (original, rest, index) = progress count values
  if @cursor.has rest:
    return #[index, @cursor.value original, @cursor.value rest]
  return #[index, 999, 999]
entry const arrays = fn (count: U32) => inspect count (@array.generate 700 identity)
entry const lists = fn (count: U32) => inspect count (@list.generate 700 identity)
entry const redirected = fn (count: U32) => do:
  let cursor = (@list.generate 700 identity).iter
  let index = 0
  for ever:
    if index == count:
      cursor := (@list.fill 2 99).iter
      break
    use step <- cursor.next
    let #Some (_, rest) = step else:
      break
    cursor := rest
    index := self + 1
  return #[index, @cursor.value cursor]
entry const references = fn (count: U32) => do:
  let values = @list.generate 700 (fn index => #[index, index + 1])
  let original = values.iter
  let cursor = original
  let saved = #[999]
  let index = 0
  for ever:
    if index == count:
      break
    use step <- cursor.next
    let #Some (value, rest) = step else:
      break
    saved := value
    cursor := rest
    index := self + 1
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      @panic "pressure"
  let again = @cursor.value original
  return #[index, saved[0], again[0], again[1]]
entry const captured = fn (count: U32) => do:
  let original = (@list.generate 700 identity).iter
  let read = fn () => @cursor.value original
  let cursor = original
  let index = 0
  for ever:
    if index == count:
      break
    use step <- cursor.next
    let #Some (_, rest) = step else:
      break
    cursor := rest
    index := self + 1
  return read () + @cursor.value cursor
const observe = fn (cursor: Cursor (List U32)) => @cursor.value cursor
entry const unknown = fn (count: U32) => do:
  let cursor = (@list.generate 700 identity).iter
  let total = 0
  let index = 0
  for ever:
    if index == count:
      break
    use step <- cursor.next
    let #Some (value, rest) = step else:
      break
    total := self + observe cursor + value
    cursor := rest
    index := self + 1
  return total
entry const suspend = fn (host: U32 -> U32 ! {Foreign}) => do:
  let original = (@list.generate 700 identity).iter
  let cursor = original
  let total = 0
  let index = 0
  for index in 0..300:
    use step <- cursor.next
    let #Some (value, rest) = step else:
      return 999
    use actual <- host value
    total := self + actual
    cursor := rest
  return total + @cursor.value cursor + @cursor.value original
`;

Deno.test("private pure cursor successors preserve break snapshots returned headers forks references and fallback", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-successor-" });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        codegenTier,
        prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
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
            for (const count of [0, 1, 243, 244, 245, 500, 699, 700, 701]) {
              const steps = Math.min(count, 700);
              const expected = Uint32Array.of(steps, 999, 999);
              if (steps < 700) {
                expected[1] = 0;
                expected[2] = steps;
              }
              assert.deepEqual(await invoke("arrays", count), expected);
              assert.deepEqual(await invoke("lists", count), expected);
              if (count < 700) {
                assert.deepEqual(
                  await invoke("redirected", count),
                  Uint32Array.of(count, 99),
                );
                assert.equal(await invoke("captured", count), count);
                assert.equal(
                  await invoke("unknown", count),
                  (count * (count - 1)) >>> 0,
                );
              }
            }
            assert.deepEqual(
              await invoke("references", 300),
              Uint32Array.of(300, 299, 0, 1),
            );
            const trace: number[] = [];
            let host;
            let rejected;
            const record = (value: number) => {
              trace.push(value);
              return value + 1;
            };
            const stop = (value: number) => {
              trace.push(value);
              if (value === 17) throw new Error("stop");
              return value + 1;
            };
            if (asynchronous) {
              host = guest.capabilityAsync({
                parameter: "U32",
                result: "U32",
                call: async (value) => {
                  await Promise.resolve();
                  return record(value);
                },
              });
              rejected = guest.capabilityAsync({
                parameter: "U32",
                result: "U32",
                call: async (value) => {
                  await Promise.resolve();
                  return stop(value);
                },
              });
            } else {
              host = guest.capability({
                parameter: "U32",
                result: "U32",
                call: record,
              });
              rejected = guest.capability({
                parameter: "U32",
                result: "U32",
                call: stop,
              });
            }
            const expected = 300 * 301 / 2 + 300;
            assert.equal(await invoke("suspend", host), expected);
            assert.deepEqual(trace, Array.from({ length: 300 }, (_, i) => i));
            trace.length = 0;
            await assert.rejects(invoke("suspend", rejected));
            assert.deepEqual(trace, Array.from({ length: 18 }, (_, i) => i));
            trace.length = 0;
            assert.equal(await invoke("suspend", host), expected);
            assert.deepEqual(trace, Array.from({ length: 300 }, (_, i) => i));
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

Deno.test("private cursor families rederive dependency archives local edits and checkpoint restart", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-successor-archive-",
  });
  const entry = `${directory}/main.blot`;
  const dependencies = `${directory}/inputs.blotdep`;
  const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
  const edited = source.replace("cursor := rest", "cursor := original");
  assert.notEqual(edited, source);
  try {
    await Deno.writeTextFile(entry, source);
    const packed = await new Deno.Command(Deno.args[0], {
      args: ["dependencies", entry, dependencies, "--prelude", prelude],
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
        for (const text of [source, edited, source]) {
          const built = await compiler.build({ sources: { [entry]: text } });
          assert(built.success, JSON.stringify(built));
          const fresh = await createZigProjectCompiler(options);
          try {
            const control = await fresh.build({ sources: { [entry]: text } });
            assert(control.success, JSON.stringify(control));
            assert.deepEqual(built.bytes, control.bytes);
          } finally {
            await fresh.dispose();
          }
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(built.bytes, { asynchronous });
            try {
              let position = 245;
              if (text === edited) position = 0;
              for (const name of ["arrays", "lists"]) {
                let actual;
                if (asynchronous) actual = await guest.callAsync(name, 245);
                else actual = guest.call(name, 245);
                assert.deepEqual(actual, Uint32Array.of(245, 0, position));
              }
            } finally {
              guest.dispose();
            }
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
          assert.deepEqual(
            guest.call("lists", 245),
            Uint32Array.of(245, 0, 245),
          );
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
