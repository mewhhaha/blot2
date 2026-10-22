import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

Deno.test("quoted resources and requests retain effect and lifetime owners across archive edits and restart", async () => {
  const executable = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  const directory = await Deno.makeTempDir({ prefix: "blot-staged-resource-" });
  const entry = `${directory}/main.blot`;
  const producer = `${directory}/producer.blot`;
  const archive = `${directory}/producer.blotdep`;
  const source =
    `import {scoped, released, failed, handled, unused, owned, nested, spliced, owned_once, captured} from "./producer"
entry const answer = fn (host: Unit -> U32 ! {Foreign}) => (@code.emit scoped) host
entry const again = fn (host: Unit -> U32 ! {Foreign}) => (@code.emit scoped) host
entry const release = fn () => (@code.emit released) ()
entry const cleanup_failure = fn () => (@code.emit failed) ()
entry const handled_result = fn (host: Unit -> U32 ! {Foreign}) => (@code.emit handled) host
entry const unused_result = fn (host: Unit -> U32 ! {Foreign}) => (@code.emit unused) host
entry const owned_result = fn () => @code.emit owned
entry const nested_result = fn () => @code.emit nested
entry const spliced_result = fn () => @code.emit spliced
entry const once_result = fn () => @code.emit owned_once
const captured_read: unique U32 -> U32 = @code.emit captured
entry const captured_result = fn () => captured_read 42
`;
  const library = (value: number) =>
    `effect Read: Unit -> U32
const scoped = @code.quote (fn (host: Unit -> U32 ! {Foreign}) => @resource.scope (fn () => ${value}) (fn owner => ()) (fn loan => @u32.add (@usage.read loan) (host ())))
const released = @code.quote (fn () => do:
  use owner <- @resource.acquire (fn () => ${value}) (fn value => ())
  use @resource.release owner
  break ${value})
const failed = @code.quote (fn () => @resource.scope (fn () => ${value}) (fn owner => @panic "quoted cleanup") (fn loan => @usage.read loan))
const handled = @code.quote (fn (host: Unit -> U32 ! {Foreign}) => do:
  let calculation = @computation (fn () => @u32.add (Read ()) ${value})
  for request in @requests calculation:
    case request of
      effect Read () =>
        yield host ()
      complete value =>
        break value)
const unused = @code.quote (fn (host: Unit -> U32 ! {Foreign}) => do:
  let calculation = @computation (fn () => ${value})
  for request in @requests calculation:
    case request of
      effect Read () =>
        yield host ()
      complete value =>
        break value)
const consume = fn (value: unique U32) => @usage.borrow value (fn loan => @usage.read loan)
const make = fn (value: unique U32) => @code.quote (@code.lift (consume value))
const make_nested = fn (value: unique U32) => @code.quote (@code.quote (@code.lift (@code.lift (consume value))))
const make_spliced = fn (value: unique U32) => @code.quote (@code.splice (make value))
const make_once = fn (value: unique U32) => do:
  let build: once (Unit -> code [U32, row {}]) = fn () => @code.quote (@code.lift (consume value))
  break build ()
const owned = make ${value}
const nested = @code.run (make_nested ${value})
const spliced = make_spliced ${value}
const owned_once = make_once ${value}
const captured = @code.quote (fn (value: unique U32) => @usage.borrow value (fn loan => do:
  let read = fn () => @usage.read loan
  break read ()))
`;
  const observe = async (bytes: Uint8Array<ArrayBuffer>, value: number) => {
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        const call = async (name: string, input: unknown = null) => {
          if (asynchronous) return await guest.callAsync(name, input as never);
          return guest.call(name, input as never);
        };
        let host;
        let calls = 0;
        if (asynchronous) {
          host = guest.capabilityAsync({
            parameter: "Unit",
            result: "U32",
            call: async () => {
              calls += 1;
              await Promise.resolve();
              return 2;
            },
          });
        } else {host = guest.capability({
            parameter: "Unit",
            result: "U32",
            call: () => {
              calls += 1;
              return 2;
            },
          });}
        assert.equal(await call("answer", host), value + 2);
        assert.equal(await call("again", host), value + 2);
        assert.equal(await call("handled_result", host), value + 2);
        const beforeUnused = calls;
        assert.equal(await call("unused_result", host), value);
        assert.equal(calls, beforeUnused);
        for (
          const name of [
            "owned_result",
            "nested_result",
            "spliced_result",
            "once_result",
          ]
        ) {
          assert.equal(await call(name), value);
        }
        assert.equal(await call("captured_result"), 42);
        assert.equal(await call("release"), value);
        await assert.rejects(
          () => call("cleanup_failure"),
          WebAssembly.RuntimeError,
        );
        assert.equal(await call("answer", host), value + 2);
        const memory = guest.memoryBytes();
        for (let index = 0; index < 32; index++) {
          assert.equal(await call("release"), value);
        }
        assert.equal(guest.memoryBytes(), memory);
      } finally {
        guest.dispose();
      }
    }
  };
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = { executable, entry, prelude: null, codegenTier };
      const cached = {
        ...options,
        cacheDirectory: `${directory}/cache-${codegenTier}`,
      };
      const retained = await createZigProjectCompiler(cached);
      try {
        for (const value of [40, 45, 40]) {
          const sources = { [entry]: source, [producer]: library(value) };
          await Deno.writeTextFile(entry, source);
          await Deno.writeTextFile(producer, sources[producer]);
          const fresh = await createZigProjectCompiler({
            ...options,
            cacheDirectory: false,
          });
          try {
            const expected = await fresh.build({ sources });
            assert(expected.success, JSON.stringify(expected));
            const built = await retained.build({ sources });
            assert(built.success, JSON.stringify(built));
            assert.deepEqual(built.bytes, expected.bytes);
            await observe(built.bytes, value);
            const moved = await retained.build({
              sources: {
                ...sources,
                [producer]: sources[producer].replace(
                  "@code.lift (consume value)",
                  "@code.lift (@u32.add (consume value) (consume value))",
                ),
              },
            });
            assert(!moved.success, JSON.stringify(moved));
            assert(
              moved.diagnostics.some((item) => item.code === "use_after_move"),
            );
            await observe(built.bytes, value);
            const invalid = await retained.build({
              sources: {
                ...sources,
                [producer]: sources[producer].replace(
                  "@usage.read loan",
                  "loan",
                ),
              },
            });
            assert(!invalid.success, JSON.stringify(invalid));
            await observe(built.bytes, value);
            const escapedCapture = await retained.build({
              sources: {
                ...sources,
                [producer]: sources[producer].replace(
                  "let read = fn () => @usage.read loan",
                  "let read = fn () => loan",
                ),
              },
            });
            assert(!escapedCapture.success, JSON.stringify(escapedCapture));
            await observe(built.bytes, value);
            const recovered = await retained.build({ sources });
            assert(recovered.success, JSON.stringify(recovered));
            assert.deepEqual(recovered.bytes, expected.bytes);
            assert.equal(recovered.stats.nativeWorkSteps, 0);
            const checkpoint = await retained.exportCheckpoint();
            const packed = await new Deno.Command(executable, {
              args: ["dependencies", entry, archive, "--prelude", "none"],
              stdout: "piped",
              stderr: "piped",
            }).output();
            assert(packed.success, new TextDecoder().decode(packed.stderr));
            for (
              const replay of [cached, {
                ...options,
                cacheDirectory: false as const,
                dependencies: archive,
              }, { ...options, cacheDirectory: false as const, checkpoint }]
            ) {
              const restarted = await createZigProjectCompiler(replay);
              try {
                const resumed = await restarted.build({ sources });
                assert(resumed.success, JSON.stringify(resumed));
                assert.deepEqual(resumed.bytes, expected.bytes);
                await observe(resumed.bytes, value);
              } finally {
                await restarted.dispose();
              }
            }
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
