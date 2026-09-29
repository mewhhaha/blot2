import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { instantiateGuest } from "./guest.ts";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

for (const threads of [1, 4]) {
  Deno.test(`native ${threads}-thread host callback ABI matches JS and executes`, async () => {
    const js = await createSourceCompiler();
    const native = await createNativeCompiler({ threads });
    try {
      const source = await Deno.readTextFile(
        new URL("../examples/host_io.blot", import.meta.url),
      );
      const artifact = await native.compile(source);
      equal(artifact, js.compile(source));
      const guest = await instantiateGuest(artifact.bytes);
      try {
        const callback = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => value + 1,
        });
        equal(guest.call("main", callback), 42);
        equal(guest.call("mocked", null), 42);
        equal(guest.read("uses_host"), true);
      } finally {
        guest.dispose();
      }
      for (
        const library of [
          "const main = fn (io: U32 -> U32) => io 0\nentry const answer = fn () => 42\n",
          "effect Reader.ask: Unit -> U32\nconst main = fn (io: U32 -> U32 ! {Foreign}) => Reader.ask ()\nentry const answer = fn () => 42\n",
        ]
      ) {
        // Values outside the guest ABI stay library code: only entries export.
        const artifact = await native.compile(library);
        equal(artifact, js.compile(library));
        equal(
          WebAssembly.Module.exports(new WebAssembly.Module(artifact.bytes))
            .map((item) => item.name),
          ["answer"],
        );
      }
      for (
        const invalid of [
          "effect Foreign: U32 -> U32\n",
          "entry const main = fn (io: U32 -> U32 ! {Foreign}) => do:\n  let value = io 0\n  return value\n",
          "effect Reader.ask: Unit -> U32\nconst main: (U32 -> U32 ! {Foreign}) -> U32 = fn io => Reader.ask ()\n",
        ]
      ) {
        let expected: SourceError | undefined;
        try {
          js.compile(invalid);
        } catch (error) {
          ok(error instanceof SourceError);
          expected = error;
        }
        ok(
          expected,
          "Invalid capability source must fail in the reference compiler",
        );
        await rejects(() => native.compile(invalid), (error) => {
          ok(error instanceof SourceError);
          equal([error.code, error.message, error.start, error.end], [
            expected.code,
            expected.message,
            expected.start,
            expected.end,
          ]);
          return true;
        });
      }
      equal(await native.compile(source), artifact);
    } finally {
      js.dispose();
      await native.dispose();
    }
  });
}

Deno.test("native cached bodies relink when callback imports appear, reorder, and disappear", async () => {
  const session = await createNativeIncrementalCompiler({
    prelude: "none",
    threads: 1,
  });
  const clean = await createNativeCompiler({ prelude: "none", threads: 1 });
  const js = await createSourceCompiler({ prelude: "none" });
  const scalar = `
data Maybe a = #Some a | #Nothing
const saved = #Some 7
entry const compute = fn value => @u32.add value 1
entry const pure = fn () => case saved of
  #Some value => compute value
  #Nothing => 0
entry const count = 12
`;
  const integer = (value: number) => `
entry const main = fn (io: U32 -> U32 ! {Foreign}) => do:
  use next <- io (compute ${value})
  return next
`;
  const float = `
entry const float = fn (io: F32 -> F32 ! {Foreign}) => do:
  use next <- io 1.5
  return next
`;
  try {
    let revision = 0;
    for (
      const source of [
        scalar,
        scalar + integer(40),
        float + scalar + integer(40),
        float + scalar + integer(41),
        float + scalar,
        scalar,
      ]
    ) {
      const result = await session.compile(source);
      equal(result.artifact.bytes, (await clean.compile(source)).bytes);
      equal(result.artifact.bytes, js.compile(source).bytes);
      if (revision++ > 0) {
        ok(result.stats.entries_reused >= 2, JSON.stringify(result.stats));
      }
      const guest = await instantiateGuest(result.artifact.bytes);
      try {
        equal(guest.call("pure", null), 8);
        equal(guest.read("count"), 12);
        if (source.includes("const main = fn")) {
          const callback = guest.capability({
            parameter: "U32",
            result: "U32",
            call: (value) => value + 1,
          });
          equal(
            guest.call("main", callback),
            source.includes("compute 41") ? 43 : 42,
          );
        }
        if (source.includes("const float = fn")) {
          const callback = guest.capability({
            parameter: "F32",
            result: "F32",
            call: (value) => value * 2,
          });
          equal(guest.call("float", callback), 3);
        }
      } finally {
        guest.dispose();
      }
      await rejects(
        () =>
          session.compile(`${source}\nconst bad = fn () => @render.clear 0\n`),
        (error) =>
          error instanceof SourceError && error.code === "unknown_intrinsic",
      );
      const unchanged = await session.compile(source);
      equal(unchanged.artifact.bytes, result.artifact.bytes);
      equal(unchanged.stats.groups_checked, 0);
      equal(unchanged.stats.entries_compiled, 0);
    }
  } finally {
    js.dispose();
    await Promise.all([session.dispose(), clean.dispose()]);
  }
});
