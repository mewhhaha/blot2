import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";
import type { AnalyzedArtifact as Artifact } from "./host.ts";

async function observed(artifact: Artifact, name: string, argument = 0) {
  const { instance } = await WebAssembly.instantiate(artifact.bytes, {
    "blot:host/1": {
      call_u32_u32: () => {
        throw new Error("effect reflection must not invoke a host callback");
      },
    },
  });
  const value = instance.exports[name];
  if (typeof value === "function") return value(argument) as number;
  ok(value instanceof WebAssembly.Global, `missing export ${name}`);
  return value.value as number;
}

async function checkRevisions(
  revisions: readonly { source: string; export: string; expected: number }[],
  prelude: "none" | "default" = "default",
) {
  const options = { prelude, threads: 1 } as const;
  const session = await createNativeIncrementalCompiler(options);
  const clean = await createNativeCompiler(options);
  const independent = await createSourceCompiler(options);
  try {
    for (const { source, export: name, expected } of revisions) {
      const fresh = await clean.compile(source);
      const reference = independent.compile(source);
      const edited = await session.compile(source);
      equal(await observed(reference, name, 4), expected);
      equal(await observed(edited.artifact, name, 4), expected);
      equal(await observed(fresh, name, 4), expected);
    }
  } finally {
    independent.dispose();
    await clean.dispose();
    await session.dispose();
  }
}

Deno.test("typed evidence follows associated selection despite one generic call shape", async () => {
  const source = (left: string) => `
data Left = #Left F32
data Right = #Right F32
${left}
const Right.add = fn (left: Left) => fn (right: Right) => 20.0
const combine = fn left => fn right => left + right
entry const run = fn (value: F32) => combine (#Left value) (#Right value)
`;
  await checkRevisions([
    {
      source: source(
        "const Left.add = fn (left: Left) => fn (right: Right) => 10.0",
      ),
      export: "run",
      expected: 10,
    },
    { source: source(""), export: "run", expected: 20 },
    {
      source: source(
        "const Left.add = fn (left: Left) => fn (right: Right) => 30.0",
      ),
      export: "run",
      expected: 30,
    },
  ]);
});

Deno.test("typed evidence distinguishes nominal owners with the same payload and result type", async () => {
  const source = (owner: string, both = false) => `
data First = #First F32
data Second = #Second F32
const First.distance = fn (left: First) => fn (right: First) => 10.0
const Second.distance = fn (left: Second) => fn (right: Second) => 20.0
const distance = fn left => fn right => @type.call "distance" left right
entry const run = fn (value: F32) => ${
    both
      ? "distance (#First value) (#First value) + distance (#Second value) (#Second value)"
      : `distance (#${owner} value) (#${owner} value)`
  }
`;
  await checkRevisions([
    { source: source("First"), export: "run", expected: 10 },
    { source: source("Second"), export: "run", expected: 20 },
    { source: source("First", true), export: "run", expected: 30 },
    { source: source("First"), export: "run", expected: 10 },
  ]);
});

Deno.test("typed evidence follows operation identity and scoped provider selection", async () => {
  const source = (chosen: string) => `
effect First.ask: Unit -> U32
effect Second.ask: Unit -> U32
const first = @effect.provider First.ask (fn () => 11)
const second = @effect.provider Second.ask (fn () => 22)
const chosen = ${chosen}.ask
const invoke = fn operation => operation ()
entry const run = fn () => do first:
  return do second:
    return invoke chosen
`;
  await checkRevisions([
    { source: source("First"), export: "run", expected: 11 },
    { source: source("Second"), export: "run", expected: 22 },
    { source: source("First"), export: "run", expected: 11 },
  ], "none");
});

Deno.test("typed evidence follows captured constants with unchanged function types", async () => {
  const source = (captured: string) => `
const make = fn captured => fn value => value + captured
const saved = make ${captured}
entry const run = fn (value: F32) => saved value
`;
  await checkRevisions([
    { source: source("2.0"), export: "run", expected: 6 },
    { source: source("3.0"), export: "run", expected: 7 },
    { source: source("2.0"), export: "run", expected: 6 },
  ]);
});

Deno.test("typed evidence follows annotation rows and effect reflection", async () => {
  const source = (row: string) => `
effect Reader.ask: U32 -> U32
const call = fn (callback: U32 -> U32 ! {${row}}) => callback 1
const requirements = @effect.of call
entry const count = @effect.count requirements
entry const has_foreign = @effect.has requirements Foreign
`;
  await checkRevisions([
    { source: source(""), export: "count", expected: 0 },
    { source: source("Foreign"), export: "count", expected: 1 },
    { source: source("Foreign, Reader.ask"), export: "count", expected: 2 },
    { source: source(""), export: "has_foreign", expected: 0 },
  ], "none");
});

Deno.test("failed typed-evidence edits keep exact diagnostics and recover", async () => {
  const options = { prelude: "none", threads: 1 } as const;
  const session = await createNativeIncrementalCompiler(options);
  const clean = await createNativeCompiler(options);
  const independent = await createSourceCompiler(options);
  const valid = `entry const classify = fn (flag: Bool) => case flag of
  #True => 1
  #False => 0
entry const run = fn () => classify #True
`;
  const invalid = valid.replace("  #False => 0\n", "");
  const detail = (error: unknown) => {
    ok(error instanceof SourceError, String(error));
    return [error.code, error.message, error.start, error.end];
  };
  try {
    equal(await observed((await session.compile(valid)).artifact, "run"), 1);
    equal(await observed(await clean.compile(valid), "run"), 1);
    let reference: readonly unknown[] | undefined;
    throws(() => independent.compile(invalid), (error) => {
      reference = detail(error);
      return true;
    });
    ok(reference);
    await rejects(() => clean.compile(invalid), (error) => {
      equal(detail(error), reference);
      return true;
    });
    await rejects(() => session.compile(invalid), (error) => {
      equal(detail(error), reference);
      return true;
    });
    const restored = await session.compile(valid);
    equal(await observed(restored.artifact, "run"), 1);
    equal(await observed(await clean.compile(valid), "run"), 1);
  } finally {
    independent.dispose();
    await clean.dispose();
    await session.dispose();
  }
});

Deno.test("failed associated selection after a catalog edit cannot reuse a solved call", async () => {
  const options = { prelude: "default", threads: 1 } as const;
  const session = await createNativeIncrementalCompiler(options);
  const clean = await createNativeCompiler(options);
  const independent = await createSourceCompiler(options);
  const source = (implementation: string) => `
data Box = #Box F32
${implementation}
const combine = fn left => fn right => left + right
entry const run = fn (value: F32) => combine (#Box value) (#Box value)
`;
  const valid = source(
    "const Box.add = fn (left: Box) => fn (right: Box) => 42.0",
  );
  const invalid = source("");
  const detail = (error: unknown) => {
    ok(error instanceof SourceError, String(error));
    return [error.code, error.message, error.start, error.end];
  };
  try {
    equal(
      await observed((await session.compile(valid)).artifact, "run", 4),
      42,
    );
    let reference: readonly unknown[] | undefined;
    throws(() => independent.compile(invalid), (error) => {
      reference = detail(error);
      return true;
    });
    ok(reference);
    equal(reference[0], "missing_associated");
    await rejects(() => clean.compile(invalid), (error) => {
      equal(detail(error), reference);
      return true;
    });
    await rejects(() => session.compile(invalid), (error) => {
      equal(detail(error), reference);
      return true;
    });
    equal(
      await observed((await session.compile(valid)).artifact, "run", 4),
      42,
    );
  } finally {
    independent.dispose();
    await clean.dispose();
    await session.dispose();
  }
});
