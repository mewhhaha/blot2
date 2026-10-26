function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
const root = new URL("../", import.meta.url).pathname;
const decoder = new TextDecoder();
const modes = ["off", "fast", "release"];
async function invoke(args: string[]) {
  return await new Deno.Command(root + "build/blot", {
    cwd: root,
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
}
Deno.test("CMP-02 unused required-static exhaustion rejects in check and every optimizer mode", async () => {
  const source = "build/unused-static-limit.blot";
  const original = await Deno.readTextFile(root + "examples/static_loop.blot");
  await Deno.writeTextFile(
    root + source,
    original.replace("count(42)", "count(100000)").replace(
      "return answer",
      "return 1",
    ),
  );
  const commands = [
    ["check", source],
    ...modes.map(
      (mode) => [
        "build",
        source,
        "-o",
        `build/unused-static-${mode}.wasm`,
        `--opt=${mode}`,
      ],
    ),
  ];
  for (const command of commands) {
    const result = await invoke(command);
    assert(!result.success, "unused static declaration was skipped");
    assert(
      decoder.decode(result.stderr).includes("k1_static_limit"),
      decoder.decode(result.stderr),
    );
  }
});
Deno.test("OPT-01 executed scalar, generic and ownership behavior agrees across all enabled tiers", async () => {
  const cases = [
    { file: "examples/counted_loop.blot", name: "count", arg: 0, expected: 10 },
    {
      file: "tests/runtime_compound_dictionary.blot",
      name: "run",
      arg: 0xffffffff,
      expected: 0xffffffff,
    },
    { file: "tests/runtime_singleton.blot", name: "run", arg: 0, expected: 41 },
    {
      file: "tests/runtime_static_nested.blot",
      name: "run",
      arg: 40,
      expected: 42,
    },
  ];
  for (const [i, item] of cases.entries()) {
    for (const mode of modes) {
      const output = `build/differential-${i}-${mode}.wasm`;
      const result = await invoke([
        "build",
        item.file,
        "-o",
        output,
        `--opt=${mode}`,
      ]);
      assert(result.success, decoder.decode(result.stderr));
      const { instance } = await WebAssembly.instantiate(
        await Deno.readFile(root + output),
      );
      const value =
        (instance.exports[item.name] as (x: number) => number)(item.arg) >>> 0;
      assert(value === item.expected, `${item.file}/${mode}: ${value}`);
    }
  }
});
Deno.test("OPT-01 F32 signed-zero infinity NaN and rounding boundaries agree across tiers", async () => {
  for (const mode of modes) {
    const output = `build/differential-f32-${mode}.wasm`;
    const result = await invoke([
      "build",
      "tests/runtime_generic_closure.blot",
      "-o",
      output,
      `--opt=${mode}`,
    ]);
    assert(result.success, decoder.decode(result.stderr));
    const { instance } = await WebAssembly.instantiate(
      await Deno.readFile(root + output),
    );
    const run = instance.exports.run_float as (x: number) => number;
    for (
      const x of [
        0,
        -0,
        1.0000001192092896,
        Math.fround(1e-40),
        Infinity,
        -Infinity,
      ]
    ) assert(Object.is(run(x), x), `${mode} changed ${x}`);
    assert(Number.isNaN(run(NaN)), `${mode} changed NaN`);
  }
});
