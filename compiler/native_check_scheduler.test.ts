import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";
import {
  diamondSource,
  sharedFrontierDiamondSource,
  sharedRootDiamondSource,
  staggeredSource,
} from "./benchmark_workloads.ts";

const genericSource = `effect Reader.ask: Unit -> U32
data Maybe a = #Some a | #Nothing
const identity = fn value => value
const defer = fn action => fn () => action ()
const ask = fn () => Reader.ask ()
entry const read_handler = fn () => 40
const reader = @effect.provider Reader.ask read_handler
entry const even = fn value => case @u32.eq value 0 of
  #True => #True
  #False => odd (@u32.sub value 1)
entry const odd = fn value => case @u32.eq value 0 of
  #True => #False
  #False => even (@u32.sub value 1)
entry const reader_effects = @effect.count (@effect.of ask)
entry const answer = fn () => do reader:
  use value <- (defer ask) ()
  return case identity (#Some value), identity #True, even 4 of
    #Some number, #True, #True => @u32.add number 2
    _, _, _ => 0
`;

async function answer(bytes: Uint8Array<ArrayBuffer>) {
  const { instance } = await WebAssembly.instantiate(bytes);
  const fn = instance.exports.answer;
  ok(typeof fn === "function");
  return fn(0);
}

Deno.test("ready inference preserves generic SCCs and latent effects in JS and one/four-thread native compilation", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  try {
    const expected = reference.compile(genericSource);
    equal(await answer(expected.bytes), 42);
    for (const threads of [1, 4]) {
      const native = await createNativeCompiler({ prelude: "none", threads });
      const session = await createNativeIncrementalCompiler({
        prelude: "none",
        threads,
      });
      try {
        equal(await native.compile(genericSource), expected);
        const initial = await session.compile(genericSource);
        equal(initial.artifact, expected);
        // Export flags no longer change after the initial check, so its
        // certificates can retain every group of the first revision.
        ok(initial.stats.groups_checked + initial.stats.groups_reused > 0);
        const edited = genericSource.replace(
          "read_handler = fn () => 40",
          "read_handler = fn () => 41",
        );
        const update = await session.compile(edited);
        equal(update.artifact, reference.compile(edited));
        equal(update.artifact, await native.compile(edited));
        equal(await answer(update.artifact.bytes), 43);
        // The changed group is checked in the source pass; its exact certificate
        // joins retained groups in the final pass counted by these statistics.
        equal(update.stats.groups_checked, 0);
        ok(update.stats.groups_reused > 0);
      } finally {
        await native.dispose();
        await session.dispose();
      }
    }
  } finally {
    reference.dispose();
  }
});

function fanout() {
  const branches = Array.from({ length: 24 }, (_, branch) => {
    const lines = [
      `entry const branch_${branch} = fn () => do:`,
      "  let value_0 = seed ()",
    ];
    for (let step = 1; step <= 16; step++) {
      lines.push(`  let value_${step} = @u32.add value_${step - 1} 1`);
    }
    lines.push("  return value_16");
    return lines.join("\n");
  });
  return [
    "entry const seed = fn () => 40",
    ...branches,
    "entry const answer = fn () => branch_0 ()",
    "",
  ].join("\n");
}

Deno.test("retained nominal scans follow constructor moves, edits, failures and eviction", async () => {
  const wrap = [
    "const wrap = fn value => do:",
    ...Array.from(
      { length: 64 },
      (_, index) =>
        `  let value_${index} = @u32.add ${
          index === 0 ? "value" : `value_${index - 1}`
        } 0`,
    ),
    "  return #Carry value_63",
  ].join("\n");
  const original = `data Left = #Carry U32 | #EmptyLeft
data Right = #EmptyRight
${wrap}
entry const answer = fn () => case wrap 40 of
  #Carry value => @u32.add value 2
  _ => 0
`;
  const moved = original.replace(
    "data Left = #Carry U32 | #EmptyLeft\ndata Right = #EmptyRight",
    "data Left = #EmptyLeft\ndata Right = #Carry U32 | #EmptyRight",
  );
  const edited = moved.replace("wrap 40", "wrap 41");
  const reference = await createSourceCompiler({ prelude: "none" });
  try {
    for (const threads of [1, 8]) {
      const session = await createNativeIncrementalCompiler({
        prelude: "none",
        threads,
      });
      try {
        for (
          const source of [
            original,
            moved,
            edited,
            moved.replace(wrap, "const wrap = fn value => #Carry value"),
            original,
          ]
        ) {
          const result = await session.compile(source);
          equal(result.artifact, reference.compile(source));
          equal(
            await answer(result.artifact.bytes),
            source === edited ? 43 : 42,
          );
        }
        await rejects(
          () => session.compile(moved.replace("Carry U32", "Carry Bool")),
          SourceError,
        );
        equal(
          (await session.compile(edited)).artifact,
          reference.compile(edited),
        );
        await session.compile("entry const answer = fn () => 42\n");
        equal(
          (await session.compile(moved)).artifact,
          reference.compile(moved),
        );
      } finally {
        await session.dispose();
      }
    }
  } finally {
    reference.dispose();
  }
});

async function diagnostic(run: () => unknown | Promise<unknown>) {
  let found: SourceError | undefined;
  await rejects(async () => await run(), (error: unknown) => {
    ok(error instanceof SourceError, String(error));
    found = error;
    return true;
  });
  ok(found);
  return {
    code: found.code,
    message: found.message,
    start: found.start,
    end: found.end,
  };
}

Deno.test("dependency chains preserve artifacts, cache counts and rollback at one/eight workers", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  const original = staggeredSource(false);
  const edited = staggeredSource(true);
  const broken = edited.replace(
    "value_0 = @u32.add value 2",
    "value_0 = @u32.add #True 2",
  );
  try {
    const firstExpected = reference.compile(original);
    const editExpected = reference.compile(edited);
    const expectedDiagnostic = await diagnostic(() =>
      reference.compile(broken)
    );
    for (const threads of [1, 8]) {
      const native = await createNativeCompiler({ prelude: "none", threads });
      const session = await createNativeIncrementalCompiler({
        prelude: "none",
        threads,
      });
      try {
        equal(await native.compile(original), firstExpected);
        const first = await session.compile(original);
        equal(first.artifact.bytes, firstExpected.bytes);
        equal(first.stats.groups_checked + first.stats.groups_reused, 64);
        const changed = await session.compile(edited);
        equal(changed.artifact.bytes, editExpected.bytes);
        equal(
          changed.artifact.analysis.functions,
          editExpected.analysis.functions,
        );
        equal(changed.stats.groups_checked, 0);
        equal(changed.stats.groups_reused, 64);
        equal(
          await diagnostic(() => native.compile(broken)),
          expectedDiagnostic,
        );
        equal(
          await diagnostic(() => session.compile(broken)),
          expectedDiagnostic,
        );
        const recovered = await session.compile(edited, { const_steps: 9999n });
        equal(recovered.stats.groups_checked, 0);
        equal(recovered.stats.groups_reused, 64);
        equal(recovered.artifact.bytes, editExpected.bytes);
        const { instance } = await WebAssembly.instantiate(
          changed.artifact.bytes,
        );
        for (let chain = 0; chain < 8; chain++) {
          const entry = instance.exports[`entry_${chain}`];
          ok(typeof entry === "function");
          equal(entry(0), chain === 0 ? 79 : 78);
        }
      } finally {
        await native.dispose();
        await session.dispose();
      }
    }
  } finally {
    reference.dispose();
  }
});

for (
  const source of [
    diamondSource,
    sharedRootDiamondSource,
    sharedFrontierDiamondSource,
  ]
) {
  Deno.test(`${source.name} regions retain cache counts, diagnostic order and rollback`, async () => {
    const original = source(false);
    const edited = source(true);
    const broken = edited.replace(
      "const join_0_7 = fn value => @u32.add",
      "const join_0_7 = fn value => @f32.add",
    ).replace(
      /const seed_7 = fn value => [^\n]+/,
      "const seed_7 = fn value => @u32.add #True 1",
    );
    const reference = await createSourceCompiler({ prelude: "none" });
    try {
      const firstExpected = reference.compile(original);
      const editExpected = reference.compile(edited);
      const expectedDiagnostic = await diagnostic(() =>
        reference.compile(broken)
      );
      for (const threads of [1, 8]) {
        const native = await createNativeCompiler({ prelude: "none", threads });
        const session = await createNativeIncrementalCompiler({
          prelude: "none",
          threads,
        });
        try {
          equal(await native.compile(original), firstExpected);
          const first = await session.compile(original);
          equal(first.artifact.bytes, firstExpected.bytes);
          const groupCount = first.stats.groups_checked +
            first.stats.groups_reused;
          const changed = await session.compile(edited);
          equal(changed.artifact.bytes, editExpected.bytes);
          equal(changed.stats.groups_checked, 0);
          equal(changed.stats.groups_reused, groupCount);
          equal(
            await diagnostic(() => native.compile(broken)),
            expectedDiagnostic,
          );
          equal(
            await diagnostic(() => session.compile(broken)),
            expectedDiagnostic,
          );
          const recovered = await session.compile(edited, {
            const_steps: 9999n,
          });
          equal(recovered.stats.groups_checked, 0);
          equal(recovered.stats.groups_reused, groupCount);
          equal(recovered.artifact.bytes, editExpected.bytes);
          const { instance } = await WebAssembly.instantiate(
            changed.artifact.bytes,
          );
          const entry = instance.exports.entry_0;
          ok(typeof entry === "function");
          equal(entry(0), 16893);
        } finally {
          await native.dispose();
          await session.dispose();
        }
      }
    } finally {
      reference.dispose();
    }
  });
}

Deno.test("native ready batches retain interface hits and roll back all caches after parallel inference failure", async () => {
  const reference = await createSourceCompiler({ prelude: "none" });
  try {
    const original = fanout();
    const edited = original.replace("seed = fn () => 40", "seed = fn () => 41");
    const broken = edited.replace(
      "seed = fn () => 41",
      "seed = fn () => #True",
    );
    const expected = reference.compile(edited);
    const expectedDiagnostic = await diagnostic(() =>
      reference.compile(broken)
    );
    equal(expectedDiagnostic.code, "type_mismatch");
    for (const threads of [1, 4]) {
      const native = await createNativeCompiler({ prelude: "none", threads });
      const session = await createNativeIncrementalCompiler({
        prelude: "none",
        threads,
      });
      try {
        const first = await session.compile(original);
        const groupCount = first.stats.groups_checked +
          first.stats.groups_reused;
        const changed = await session.compile(edited);
        equal(changed.artifact, expected);
        equal(await native.compile(edited), expected);
        equal(await answer(changed.artifact.bytes), 57);
        equal(changed.stats.groups_checked, 0);
        equal(changed.stats.groups_reused, groupCount);
        equal(
          await diagnostic(() => native.compile(broken)),
          expectedDiagnostic,
        );
        equal(
          await diagnostic(() => session.compile(broken)),
          expectedDiagnostic,
        );
        // A changed const budget bypasses the host's whole-result fast path.
        // Type keys do not contain it, so all last-successful groups must hit.
        const recovered = await session.compile(edited, { const_steps: 9999n });
        equal(recovered.stats.result_reused, false);
        equal(recovered.stats.groups_checked, 0);
        equal(recovered.stats.groups_reused, groupCount);
        equal(
          recovered.artifact,
          reference.compile(edited, { const_steps: 9999n }),
        );
      } finally {
        await native.dispose();
        await session.dispose();
      }
    }
  } finally {
    reference.dispose();
  }
});

Deno.test("cached inference plans invalidate for dependency rewiring, SCCs and source order", async () => {
  const revisions = [
    `entry const seed = fn () => 40
entry const left = fn () => 41
entry const right = fn () => 1
entry const answer = fn () => 42`,
    `entry const seed = fn () => 40
entry const left = fn () => seed ()
entry const right = fn () => left ()
entry const answer = fn () => right ()`,
    `entry const seed = fn () => 40
entry const left = fn () => @u32.add (seed ()) 1
entry const right = fn () => seed ()
entry const answer = fn () => @u32.add (left ()) (right ())`,
    `entry const seed = fn () => 40
entry const left = fn value => case @u32.eq value 0 of
  #True => seed ()
  #False => right (@u32.sub value 1)
entry const right = fn value => left value
entry const answer = fn () => right 2`,
    `entry const answer = fn () => right 2
entry const right = fn value => left value
entry const left = fn value => case @u32.eq value 0 of
  #True => seed ()
  #False => right (@u32.sub value 1)
entry const seed = fn () => 40`,
  ];
  for (const threads of [1, 8]) {
    const session = await createNativeIncrementalCompiler({
      prelude: "none",
      threads,
    });
    const clean = await createNativeCompiler({ prelude: "none", threads });
    try {
      for (const source of [...revisions, ...revisions.toReversed()]) {
        const actual = await session.compile(source);
        const expected = await clean.compile(source);
        equal(actual.artifact.bytes, expected.bytes);
        equal(actual.artifact.analysis.functions, expected.analysis.functions);
        equal(
          await answer(actual.artifact.bytes),
          await answer(expected.bytes),
        );
      }
    } finally {
      await session.dispose();
      await clean.dispose();
    }
  }
});
