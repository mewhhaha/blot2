import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const preludePath = new URL("../../std/prelude.blot", import.meta.url).pathname;
const fold = `const fold = func reduce => return func initial => return func values => return do:
  let state = initial
  for value in values:
    use next <- reduce state value
    state := next
  break state
`;
const program = `${fold}
entry const run = func (count: U32) => return fold add 0 (@list.generate count identity)
entry const arrays = func (count: U32) => return fold add 0 (@array.generate count identity)
entry const references = func (count: U32) => return fold (func total => return func row => return total + row[0]) 0 (@list.generate count (func index => return #[index]))
entry const nested = func (count: U32) => return fold (func total => return func row => return total + fold add 0 row) 0 (@list.generate count (func index => return [index, index + 1, index + 2]))
entry const floating = func () => return fold (func before => return func value => return value) 1.5 [-0.0]
const bounded = func values => return do:
  let total = 0
  for value in values:
    if value % 2 == 0:
      total := self + value
    else:
      total := self + 1
    if value >= 3:
      break
  break total
entry const joined = func (count: U32) => return bounded (@list.generate count identity)
const first = func values => return do:
  for value in values:
    break value
  break 0
entry const early = func () => return first [7, 8, 9]
entry const forks = func () => return do:
  let values = [0, 1, 2, 3]
  let cursor = values.iter
  let saved = cursor
  let total = 0
  for ever:
    use step <- cursor.next
    let #Some (value, rest) = step else:
      break
    cursor := rest
    total := self + value
    if total >= 1:
      break
  break total + @cursor.value cursor + @cursor.value saved
`;
async function session(
  source: string,
  check: (guest: Awaited<ReturnType<typeof instantiateGuest>>) => void,
) {
  const directory = await Deno.makeTempDir();
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const entry = `${directory}/main.blot`;
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        codegenTier,
        prelude: preludePath,
        cacheDirectory: false,
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        const module = new WebAssembly.Module(result.bytes);
        assert.deepEqual(
          Array.from(
            new Uint8Array(
              WebAssembly.Module.customSections(module, "blot:ownership")[0],
            ),
          ),
          [2, 2, 0],
        );
        const guest = await instantiateGuest(result.bytes);
        try {
          check(guest);
        } finally {
          guest.dispose();
        }
      } finally {
        compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}
Deno.test("resolved collection iteration preserves references nested reentry floats and observable cursor forks in both tiers", async () => {
  await session(program, (guest) => {
    for (const count of [0, 1, 3, 245, 4096]) {
      const sum = (count * (count - 1) / 2) >>> 0;
      assert.equal(guest.call("run", count), sum);
      assert.equal(guest.call("arrays", count), sum);
      assert.equal(guest.call("references", count), sum);
      assert.equal(guest.call("nested", count), 3 * sum + 3 * count);
      let joined = 4;
      if (count < 4) {
        joined = Math.floor(count / 2) +
          Math.floor((count - 1) / 2) * (Math.floor((count - 1) / 2) + 1);
      }
      if (count === 0) joined = 0;
      assert.equal(guest.call("joined", count), joined);
    }
    assert.equal(guest.call("early", null), 7);
    assert(Object.is(guest.call("floating", null), -0));
    assert.equal(guest.call("forks", null), 3);
  });
});
Deno.test("resolved collection iteration rechecks exact cursor producers through retained method edits", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const original = await Deno.readTextFile(preludePath);
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable,
        entry,
        codegenTier,
        prelude: preludePath,
        cacheDirectory: false as const,
      };
      const compiler = await createZigProjectCompiler(options);
      try {
        for (const offset of [0, 10, 0]) {
          const changed = original.replace(
            "#Some (@cursor.value cursor, @cursor.advance cursor)",
            `#Some (@u32.add (@cursor.value cursor) ${offset}, @cursor.advance cursor)`,
          );
          const sources = {
            [entry]: `${fold}entry const run = func () => return fold add 0 [0, 1, 2]\n`,
            [preludePath]: changed,
          };
          const result = await compiler.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            assert(result.success && expected.success, JSON.stringify(result));
            assert.deepEqual(result.bytes, expected.bytes);
            const guest = await instantiateGuest(result.bytes);
            try {
              assert.equal(guest.call("run", null), 3 + 3 * offset);
            } finally {
              guest.dispose();
            }
          } finally {
            fresh.dispose();
          }
        }
      } finally {
        compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
Deno.test("effectful collection iter and next retain written pulls and early exit", async () => {
  const original = await Deno.readTextFile(preludePath);
  const changed = original
    .replace(
      "const List.iter = func values => return @list.cursor values",
      "const List.iter = func values => return do:\n  use Audit.pull 1\n  break @list.cursor values",
    )
    .replace(
      "const Cursor.next = func cursor => return\n  if @cursor.has cursor\n  then #Some (@cursor.value cursor, @cursor.advance cursor)\n  else #Nothing",
      "const Cursor.next = func cursor => return do:\n  use Audit.pull 0\n  if @cursor.has cursor:\n    break #Some (@cursor.value cursor, @cursor.advance cursor)\n  break #Nothing",
    ) + "\ntype Audit is effect = { pull: U32 -> Unit }\n";
  const source = `${fold}
const measured = func action => return do:
  let pulls = 0
  for request in @requests action:
    case request of
      effect Audit.pull value =>
        pulls := self + 1
        yield ()
      complete value =>
        break #[value, pulls]
entry const run = func (count: U32) => return measured (@computation (func () => return fold add 0 (@list.generate count identity)))
const first = func values => return do:
  for value in values:
    break value
  break 0
entry const early = func () => return measured (@computation (func () => return first [3, 4, 5]))
`;
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        codegenTier,
        prelude: preludePath,
        cacheDirectory: false,
      });
      try {
        const result = await compiler.build({
          sources: { [entry]: source, [preludePath]: changed },
        });
        assert(result.success, JSON.stringify(result));
        const guest = await instantiateGuest(result.bytes);
        try {
          for (const count of [0, 1, 3, 245]) {
            assert.deepEqual(
              Array.from(guest.call("run", count) as Uint32Array),
              [
                (count * (count - 1) / 2) >>> 0,
                count + 2,
              ],
            );
          }
          assert.deepEqual(
            Array.from(guest.call("early", null) as Uint32Array),
            [3, 2],
          );
        } finally {
          guest.dispose();
        }
      } finally {
        compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

// The iteration proof reads a per-unit def-use index, so it no longer stops
// at 4,096 Core nodes: a thousand padding functions put this program above
// that size, and its loops, including one that matches optional entries as
// src/robots.blot's `pick_along` does, still take the physical form.
Deno.test("resolved collection iteration applies in units above 4,096 Core nodes", async () => {
  const padding = Array.from({ length: 1000 }, (_, index) => `const pad${index} = func (x: U32) => return @u32.add (@u32.mul x ${index + 1}) ${index}`).join("\n");
  await session(`${program}${padding}
const smallest = func entries => return do:
  let closest = 1000000
  for entry in entries:
    if let #Some value = entry:
      if value < closest:
        closest := value
  break closest
entry const optional = func (count: U32) => return smallest (@array.generate count (func index => return if index % 3 == 0 then #Nothing else #Some (count - index)))
`, (guest) => {
    for (const count of [0, 1, 2, 3, 4, 245, 4096]) {
      const sum = (count * (count - 1) / 2) >>> 0;
      assert.equal(guest.call("run", count), sum);
      assert.equal(guest.call("arrays", count), sum);
      assert.equal(guest.call("nested", count), 3 * sum + 3 * count);
      let closest = 1000000;
      for (let index = 0; index < count; index++) if (index % 3 !== 0) closest = Math.min(closest, count - index);
      assert.equal(guest.call("optional", count), closest);
    }
    assert.equal(guest.call("forks", null), 3);
  });
});
