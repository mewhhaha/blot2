import { strict as assert } from "node:assert";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
// Constants are computed at instantiation, so an explicit scalar entry whose
// value traps compiles and traps when the module is instantiated.
Deno.test("generic value interfaces reject before constant bounds while explicit scalar entries trap at instantiation", async () => {
  for (
    const source of [
      "#entry const answer = @array.get #[] 0\n",
      '#entry const answer = @panic "boom"\n',
      '#entry const earlier: U32 = @panic "earlier"\n#entry const answer = @array.get #[] 0\n',
    ]
  ) await compileExpectedFailure(source, "entry_type");
  for (const type of ["U32", "F32"]) {
    await assert.rejects(
      compileAndRun(`#entry const answer: ${type} = @array.get #[] 0\n`, () => {}),
      WebAssembly.RuntimeError,
    );
  }
  const prelude =
    new URL("./entry-interface-order/prelude.blot", import.meta.url).pathname;
  await compileExpectedFailure(
    "#entry const answer = #[].first\n",
    "entry_type",
    undefined,
    { prelude },
  );
  await assert.rejects(
    compileAndRun("#entry const answer: U32 = #[].first\n", () => {}, { prelude }),
    WebAssembly.RuntimeError,
  );
});

Deno.test("explicit scalar entries initialized by a panic trap at instantiation", async () => {
  await assert.rejects(
    compileAndRun('#entry const answer: U32 = @panic "boom"\n', () => {}),
    WebAssembly.RuntimeError,
  );
});

// Pending the traits redesign (tasks/LANGUAGE_COHERENCE.md C).
Deno.test.ignore("written associated requirements reject before the generic value interface", async () => {
  await compileExpectedFailure(
    `#entry const answer = do:
  let selected: U32 where {associated "missing" Bool Bool Bool} = 42
  break @array.get #[] 0
`,
    "missing_associated",
  );
});
const source =
  `const maker = func captured => return func (value: U32) => return @u32.add captured value
#entry const selected = maker 21
#entry const answer = if true then 42 else @panic "unreachable"
#entry const typed: Unit -> U32 = func () => return @array.get #[] 0
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

// Imported helpers and earlier declarations reject the generic interface
// before any constant value.
for (
  const [name, code, origin] of [
    ["imported-index", "entry_type", undefined],
    ["runtime-array-prefix", "entry_let_type", 11],
    ["generic-function-prefix", "entry_type", 13],
  ] as const
) {
  // Direct backend: an `#entry let` runtime array reports entry_type ("exported constants must be scalars") at its value instead of entry_let_type at its name (tasks/DELETE_SCOPED.md).
  // Direct backend: a generic entry function reports entry_type at its body instead of its name (tasks/DELETE_SCOPED.md).
  const ignored = name === "runtime-array-prefix" ||
    name === "generic-function-prefix";
  const test = ignored ? Deno.test.ignore : Deno.test;
  test(`entry interface ${name} reports ${code}`, async () => {
    const compiler = Deno.args[0] ??
      new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
    const directory = await Deno.makeTempDir({
      dir: new URL("../../build", import.meta.url).pathname,
      prefix: "entry-interface-import-",
    });
    try {
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
      if (origin !== undefined) equal(diagnostic.start, origin);
      equal(metrics.memory.live_bytes, 0);
      try {
        await Deno.stat(output);
      } catch (error) {
        if (error instanceof Deno.errors.NotFound) return;
        throw error;
      }
      throw new Error("Failed compilation published output");
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
