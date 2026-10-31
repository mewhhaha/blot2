import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const program = `import * as iter from "std/iter"
entry const strict = func count => return iter.fold_left (func total => return func pair => return do:
  let (left, right) = pair
  break total + left + right) 0 (iter.zip_strict (iter.range 0 count) (iter.range 0 count))
entry const alternatives = func input => return do:
  let mode = input / 8192
  let count = input % 8192
  let total = 0
  for round in 0..count:
    let selected = do:
      if mode % 3 == 0:
        break case round % 3, round % 2 of
          0, 0 => $Nothing
          0, _ => $Some (round * 3 + 1, round + 7)
          _, _ => $Some (round * 3 + 1, round + 7)
      else:
        if mode % 3 == 1:
          if round % 2 == 0:
            break $Some (round * 3 + 1, round + 7)
          else:
            if round % 5 == 0:
              break $Some (round * 3 + 1, round + 7)
            break $Nothing
        else:
          for inner in 0..3:
            if inner == round % 3:
              break $Some (round * 3 + 1, round + 7)
          break $Nothing
    if let $Some (left, right) = selected:
      total := self + left + right
  break total
entry const snapshots = func count => return do:
  let previous = {value: 41}
  let total = 0
  for index in 0..count:
    let current = {value: index}
    let saved = previous
    previous := current
    total := self + saved.value + current.value
  break total
`;

Deno.test("private constructor alternatives and outward loop returns preserve snapshots across reentry in both tiers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-iterator-control-exits-",
  });
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
        const result = await compiler.build({ sources: { [entry]: program } });
        assert(result.success, JSON.stringify(result));
        const guest = await instantiateGuest(result.bytes);
        try {
          for (const count of [0, 1, 2, 3, 17, 65, 4096, 0, 17]) {
            assert.equal(
              guest.call("strict", count),
              (count * (count - 1)) >>> 0,
            );
            let expectedSnapshots = 0;
            if (count !== 0) expectedSnapshots = 41 + (count - 1) ** 2;
            assert.equal(
              guest.call("snapshots", count),
              expectedSnapshots >>> 0,
            );
            for (const mode of [0, 1, 2, 3, 4, 5]) {
              let expected = 0;
              for (let round = 0; round < count; round++) {
                let selected = true;
                if (mode % 3 === 0 && round % 6 === 0) selected = false;
                if (mode % 3 === 1 && round % 2 !== 0 && round % 5 !== 0) {
                  selected = false;
                }
                if (selected) expected += round * 4 + 8;
              }
              assert.equal(
                guest.call("alternatives", mode * 8192 + count),
                expected >>> 0,
              );
            }
          }
        } finally {
          guest.dispose();
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
