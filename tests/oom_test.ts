function assert(ok: unknown, message: string): asserts ok {
  if (!ok) throw new Error(message);
}
const root = new URL("../", import.meta.url).pathname;
const decoder = new TextDecoder();
function same(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}
Deno.test("OOM-01 real Goose arena failures preserve previous publication", async () => {
  assert(
    Deno.build.os === "linux",
    "arena fault qualification currently requires Linux",
  );
  await Deno.mkdir(root + "test-results", { recursive: true });
  const args = [
    "build",
    "build/oom-candidate.blot",
    "-o",
    "build/oom-output.wasm",
  ];
  await Deno.writeTextFile(
    root + "build/oom-candidate.blot",
    "pub let candidate: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\n",
  );
  async function run(failAt: number, command = args) {
    return await new Deno.Command(root + "build/blot", {
      cwd: root,
      args: command,
      stdout: "piped",
      stderr: "piped",
      env: {
        LD_PRELOAD: root + "build/arena_fault.so",
        BLOT_FAULT_AT: String(failAt),
        BLOT_FAULT_COMMIT: "1",
      },
    }).output();
  }
  const initial = await new Deno.Command(root + "build/blot", {
    cwd: root,
    args: [
      "build",
      "examples/identity.blot",
      "-o",
      "build/oom-previous.wasm",
      "--emit-core=build/oom-core.bk1",
    ],
    stdout: "piped",
    stderr: "piped",
  }).output();
  assert(initial.success, decoder.decode(initial.stderr));
  const previous = await Deno.readFile(root + "build/oom-previous.wasm");
  const baseline = await run(0);
  assert(baseline.success, decoder.decode(baseline.stderr));
  const events =
    decoder.decode(baseline.stderr).split("BLOT_ALLOC_EVENT\n").length - 1;
  assert(
    events > 0 && events < 10000,
    `invalid arena event inventory: ${events}`,
  );
  let rejected = 0;
  for (let point = 1; point <= events; point++) {
    await Deno.writeFile(root + "build/oom-output.wasm", previous);
    const result = await run(point);
    const output = await Deno.readFile(root + "build/oom-output.wasm");
    if (!result.success) {
      rejected++;
      assert(
        same(previous, output),
        `failure point ${point} replaced the previous revision`,
      );
    } else {
      assert(
        WebAssembly.validate(output),
        `recovery at ${point} published invalid Wasm`,
      );
      const { instance } = await WebAssembly.instantiate(output);
      assert(
        (instance.exports.candidate as CallableFunction)(0) === 7,
        `recovery at ${point} changed semantics`,
      );
    }
  }
  const inspection = ["inspect", "build/oom-core.bk1"];
  const decoded = await run(0, inspection);
  assert(decoded.success, decoder.decode(decoded.stderr));
  const decodeEvents =
    decoder.decode(decoded.stderr).split("BLOT_ALLOC_EVENT\n").length - 1;
  for (let point = 1; point <= decodeEvents; point++) {
    const result = await run(point, inspection);
    // A rejected process is not an admitted artifact. Recovery is allowed only
    // if the independent validation reached its successful final report.
    if (result.success) {
      assert(
        decoder.decode(result.stdout).startsWith("valid K1 Core:"),
        "partial decoder completion reported success",
      );
    }
  }
  await Deno.writeTextFile(
    root + "test-results/arena-faults.json",
    JSON.stringify(
      {
        platform: Deno.build.os,
        buildBoundaries: events,
        rejected,
        decodeBoundaries: decodeEvents,
        coverage:
          "Every observed arena reservation and protected 64 KiB commit growth for these workloads under the Linux commit-on-touch test adapter; not arbitrary libc malloc or every language feature.",
      },
      null,
      2,
    ),
  );
  console.log(
    `arena failure sweep: ${events} construction/lowering + ${decodeEvents} decode boundaries`,
  );
});
