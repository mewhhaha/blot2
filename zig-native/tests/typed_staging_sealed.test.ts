import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

for (const consumerQuote of [false, true]) {
  Deno.test(`quoted opaque operations preserve abstraction through imports and restart (consumer quote: ${consumerQuote})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-staging-sealed-",
    });
    const entry = `${directory}/main.blot`;
    const producer = `${directory}/producer.blot`;
    const archive = `${directory}/producer.blotdep`;
    const executable = Deno.args[0] ??
      new URL("../zig-out-dev/bin/blotc", import.meta.url).pathname;
    let source = `import {generated} from "./producer"
entry const answer = func () => return @code.emit generated
`;
    if (consumerQuote) {
      source = `import {Token, make, read} from "./producer"
const generated = @code.quote (read (make ()))
entry const answer = func () => return @code.emit generated
`;
    }
    const library = (value: number) => {
      if (consumerQuote) {
        return `opaque type Token = U32
const make = func () => return $Token ${value}
const read = func (value: Token) => return case value of
  $Token number => number
`;
      }
      return `private type Packet a is data = $Packet {payload: a}
opaque type Token = U32
private const make = func value => return $Packet {payload: $Token value}
private const token = func (value: Token) => return case value of
  $Token number => number
private const read = func () => return token (make ${value}).payload
const generated = @code.quote (read ())
`;
    };
    try {
      for (const codegenTier of ["optimized", "development"] as const) {
        const options = { executable, entry, prelude: null, codegenTier };
        const cached = {
          ...options,
          cacheDirectory: `${directory}/cache-${codegenTier}`,
        };
        const retained = await createZigProjectCompiler(cached);
        const observe = async (
          bytes: Uint8Array<ArrayBuffer>,
          value: number,
        ) => {
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(bytes, { asynchronous });
            try {
              let answer;
              if (asynchronous) answer = await guest.callAsync("answer", null);
              else answer = guest.call("answer", null);
              assert.equal(answer, value);
            } finally {
              guest.dispose();
            }
          }
        };
        try {
          for (const value of [42, 43, 42]) {
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
              const failed = await retained.build({
                sources: {
                  ...sources,
                  [entry]: source + "const forbidden = $Token 0\n",
                },
              });
              assert(!failed.success, JSON.stringify(failed));
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
}
