import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source = `type Actor is data = $Actor U32
type Pose is data = $Pose U32
const consume = func ($Actor actor) -> ($Pose pose) => return @u32.add (@u32.mul actor 100) pose
entry const answer = func (input: U32) => return do:
  let owner: ResizeArray U32 = #[input]
  let actors: Maybe Actor = if @u32.eq (@u32.bit_and input 1) 0 then $Nothing else $Some ($Actor (@u32.add owner[0] 1))
  let poses: Maybe Pose = if @u32.eq (@u32.bit_and input 2) 0 then $Nothing else $Some ($Pose (@u32.add owner[0] 2))
  let actor = Maybe.unwrap_or ($Actor 10) actors
  let pose = Maybe.unwrap_or ($Pose 20) poses
  let retained = Maybe.unwrap_or ($Actor 30) actors
  return #[consume actor pose, consume retained pose]
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`inline results preserve distinct nominal instantiations (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-inline-witness-",
    });
    const entry = `${directory}/main.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const result = await compiler.build({ sources: { [entry]: source } });
      assert(result.success, JSON.stringify(result));
      assert(
        (result.stats.workCounters as Record<string, number>)
          .scoped_emission_expressions > 0,
      );
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        try {
          for (const input of [0, 1, 2, 3, 100]) {
            const value = asynchronous
              ? await guest.callAsync("answer", input)
              : guest.call("answer", input);
            const actor = input & 1 ? input + 1 : 10;
            const retained = input & 1 ? input + 1 : 30;
            const pose = input & 2 ? input + 2 : 20;
            assert.deepEqual(
              value,
              new Uint32Array([actor * 100 + pose, retained * 100 + pose]),
            );
          }
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
