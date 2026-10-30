import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun } from "./reduction_helpers.ts";

const source = `
entry const lexical = func (seed: U32) => return do:
  let cursor = do:
    break { values: @array.fill 16 seed, index: 8192 }
  let saved = cursor
  cursor := { values: @array.fill 16 (seed + 1), index: 65536 }
  for index in 0..128:
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      @panic "lexical pressure"
  break #[saved.values[saved.index % 16], cursor.values[cursor.index % 16]]
entry const suspend = func (host: Array U32 -> Array U32 ! {Foreign}) => return do:
  let cursor = do:
    break { values: #[41, 42], index: 1 }
  let saved = cursor
  use next <- host cursor.values
  cursor := { values: next, index: 0 }
  break #[saved.values[saved.index], cursor.values[cursor.index]]
`;

Deno.test("owned cursor fields preserve nested-scope snapshots suspension rejection and recovery", async () => {
  await compileAndRun(source, async (_, bytes) => {
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        const definition = {
          parameter: "Array U32",
          result: "Array U32",
          call: (values: Uint32Array) =>
            Uint32Array.from(values, (value) => value + 100),
        } as const;
        let capability;
        let rejected;
        if (asynchronous) {
          capability = guest.capabilityAsync({
            ...definition,
            call: async (values) => {
              await Promise.resolve();
              return definition.call(values);
            },
          });
          rejected = guest.capabilityAsync({
            ...definition,
            call: async () => {
              throw new Error("reference cursor");
            },
          });
        } else {
          capability = guest.capability(definition);
          rejected = guest.capability({
            ...definition,
            call: () => {
              throw new Error("reference cursor");
            },
          });
        }
        for (let repetition = 0; repetition < 3; repetition++) {
          if (asynchronous) {
            assert.deepEqual(
              await guest.callAsync("suspend", capability),
              Uint32Array.of(42, 141),
            );
            await assert.rejects(guest.callAsync("suspend", rejected));
            assert.deepEqual(
              await guest.callAsync("lexical", 65536),
              Uint32Array.of(65536, 65537),
            );
          } else {
            assert.deepEqual(
              guest.call("suspend", capability),
              Uint32Array.of(42, 141),
            );
            assert.throws(() => guest.call("suspend", rejected));
            assert.deepEqual(
              guest.call("lexical", 65536),
              Uint32Array.of(65536, 65537),
            );
          }
        }
      } finally {
        guest.dispose();
      }
    }
  }, { stdRoot: new URL("../../std", import.meta.url).pathname });
});
