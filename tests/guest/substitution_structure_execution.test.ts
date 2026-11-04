import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

function source(bump: number): string {
  const fields = Array.from({ length: 64 }, (_, index) => `f${index}: U32`)
    .join(", ");
  const values = Array.from({ length: 64 }, (_, index) => `f${index}: ${index}`)
    .join(", ");
  return `type Box a is data = $Box {fixed: {${fields}}, value: a}
const fixed = {${values}}
const record = func (fixed: {${fields}}) -> payload => return {fixed, payload}
const boxed = func fixed -> value => return $Box {value, fixed}
const visit = func callback -> value => return callback value
entry const integers = func (input: U32) => return do:
  let marker: GrowArray U32 = #[input]
  let plain = record fixed marker[0]
  let nominal = boxed plain.fixed (@u32.add plain.payload ${bump})
  let result = visit (func (value: U32) => return @u32.add value nominal.fixed.f63) nominal.value
  return #[plain.fixed.f0, plain.fixed.f31, nominal.fixed.f63, plain.payload, nominal.value, result]
entry const floating = func (input: F32) => return do:
  let plain = record fixed input
  let nominal = boxed plain.fixed (@f32.add plain.payload 1.5)
  return #[plain.payload, nominal.value, @u32.to_f32 nominal.fixed.f63, visit (func value => return value) plain.payload]
entry const host = func (callback: U32 -> U32 ! {Foreign}): U32 ! {Foreign} => return do:
  let plain = record fixed 7
  let nominal = boxed plain.fixed plain.payload
  return visit callback nominal.value
`;
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`generic substitution preserves fixed structure and per-use effects (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-substitution-structure-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
      startupTimeoutMs: 5_000,
    });
    let original: Uint8Array | undefined;
    try {
      for (const bump of [1, 9, 1]) {
        const built = await compiler.build({
          sources: { [entry]: source(bump) },
          signal: AbortSignal.timeout(5_000),
        });
        assert(built.success, JSON.stringify(built));
        if (bump === 1) {
          if (original) assert.deepEqual(built.bytes, original);
          else original = built.bytes;
        }
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            const call = async (
              name: string,
              input: Parameters<typeof guest.call>[1],
            ) => {
              if (asynchronous) return await guest.callAsync(name, input);
              return guest.call(name, input);
            };
            for (const input of [0, 1, 41, 0xfffffffd, 3, 0]) {
              assert.deepEqual(
                await call("integers", input),
                new Uint32Array([
                  0,
                  31,
                  63,
                  input,
                  input + bump,
                  input + bump + 63,
                ]),
              );
            }
            for (const input of [-0, 1.25, -10.5, -0]) {
              assert.deepEqual(
                await call("floating", input),
                new Float32Array([
                  input,
                  input + 1.5,
                  63,
                  input,
                ]),
              );
            }
            let calls = 0;
            let callback: ReturnType<typeof guest.capability>;
            if (asynchronous) {
              callback = guest.capabilityAsync({
                parameter: "U32",
                result: "U32",
                call: async (value) => {
                  calls++;
                  await Promise.resolve();
                  return value + 5;
                },
              });
            } else {
              callback = guest.capability({
                parameter: "U32",
                result: "U32",
                call: (value) => {
                  calls++;
                  return value + 5;
                },
              });
            }
            for (let index = 0; index < 3; index++) {
              assert.equal(await call("host", callback), 12);
            }
            assert.equal(calls, 3);
          } finally {
            guest.dispose();
          }
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
