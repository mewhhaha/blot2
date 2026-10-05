import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
Deno.test("generic value interfaces reject before constant bounds or panic while explicit scalar entries preserve evaluation errors", async () => {
  for (
    const source of [
      "entry const answer = @array.get #[] 0\n",
      'entry const answer = @panic "boom"\n',
      'entry const earlier: U32 = @panic "earlier"\nentry const answer = @array.get #[] 0\n',
    ]
  ) await compileExpectedFailure(source, "entry_type");
  for (const type of ["U32", "F32"]) {
    await compileExpectedFailure(
      `entry const answer: ${type} = @array.get #[] 0\n`,
      "array_bounds",
    );
  }
  await compileExpectedFailure(
    'entry const answer: U32 = @panic "boom"\n',
    "const_panic",
  );
  await compileExpectedFailure(
    `entry const answer = do:
  let selected: U32 where {associated "missing" Bool Bool Bool} = 42
  return @array.get #[] 0
`,
    "missing_associated",
  );
  const prelude =
    new URL("./entry-interface-order/prelude.blot", import.meta.url).pathname;
  await compileExpectedFailure(
    "entry const answer = #[].first\n",
    "entry_type",
    undefined,
    { prelude },
  );
  await compileExpectedFailure(
    "entry const answer: U32 = #[].first\n",
    "array_bounds",
    undefined,
    { prelude },
  );
});
const source =
  `const maker = fn captured => fn (value: U32) => @u32.add captured value
entry const selected = maker 21
entry const answer = if #True then 42 else @panic "unreachable"
entry const typed: Unit -> U32 = fn () => @array.get #[] 0
`;
for (const asynchronous of [false, true]) {
  Deno.test(`interface preflight preserves staged closures and runtime traps (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(source, async (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(
          asynchronous
            ? await guest.callAsync("selected", 21)
            : guest.call("selected", 21),
          42,
        );
        equal(guest.read("answer"), 42);
      }
      try {
        if (asynchronous) await guest.callAsync("typed", null);
        else guest.call("typed", null);
      } catch (error) {
        if (error instanceof WebAssembly.RuntimeError) return;
        throw error;
      }
      throw new Error("Expected typed empty index to trap at runtime");
    }, { asynchronous });
  });
}

// Frozen source selection diagnoses witnesses before ABI and constant values.
Deno.test("imported helpers and aliases preserve deferred witness validation while ordinary index helpers reject the generic interface", async () => {
  const compiler = Deno.args[0] ??
    new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  const directory = await Deno.makeTempDir({
    dir: new URL("../../build", import.meta.url).pathname,
    prefix: "entry-interface-import-",
  });
  try {
    for (
      const [name, code, steps, origin] of [
        ["imported-witness", "invalid_annotation", false, 46],
        ["imported-alias-witness", "ambiguous_associated", false, 39],
        ["imported-index", "entry_type", false, undefined],
        ["runtime-array-prefix", "entry_let_type", false, 10],
        ["generic-function-prefix", "entry_type", false, 12],
      ] as const
    ) {
      const output = `${directory}/${name}.wasm`;
      const result = await new Deno.Command(compiler, {
        args: [
          "build",
          new URL(`./entry-interface-order/${name}.blot`, import.meta.url)
            .pathname,
          output,
          "--prelude",
          new URL("./entry-interface-order/prelude.blot", import.meta.url)
            .pathname,
        ],
        stdout: "piped",
        stderr: "piped",
      }).output();
      equal(result.success, false);
      const records = new TextDecoder().decode(result.stdout).trim().split("\n")
        .map((line) => JSON.parse(line));
      const diagnostic = records.find((record) => record.kind === "diagnostic");
      const metrics = records.find((record) => record.kind === "compilation");
      equal(diagnostic?.code, code);
      if (code === "invalid_annotation") equal(diagnostic.message, "Never is an internal control-flow type");
      if (origin !== undefined) equal(diagnostic.start, origin);
      equal(metrics.memory.live_bytes, 0);
      equal(metrics.constant_steps > 0, steps);
      try {
        await Deno.stat(output);
      } catch (error) {
        if (error instanceof Deno.errors.NotFound) continue;
        throw error;
      }
      throw new Error("Failed compilation published output");
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
