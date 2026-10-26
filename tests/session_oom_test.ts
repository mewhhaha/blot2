function ensure(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
const root = new URL("../", import.meta.url).pathname;
const decoder = new TextDecoder();
Deno.test("OOM-01 retained decode, reuse and candidate publication preserve the last output", async () => {
  const path = root + "build/session-oom.blot",
    output = root + "build/session-oom.wasm";
  const text = (n: number) =>
    `pub let dependency: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return U32.wrapping_add(x,${n})\npub let caller: U32 -> U32 ! {} resources {depth: 2, frame: 0} = fn x => return dependency(x)\n`;
  const growth = Array.from(
    { length: 64 },
    (_, i) =>
      `pub let padding_${i}: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n${
        Array.from(
          { length: 64 },
          (_, j) => `  let value_${j} = U32.wrapping_add(x,${j})\n`,
        ).join("")
      }  return x\n`,
  ).join("");
  async function run(fault: number, second: boolean) {
    await Deno.writeTextFile(path, text(1));
    const process = new Deno.Command(root + "build/blot", {
      cwd: root,
      args: ["serve"],
      stdin: "piped",
      stdout: "piped",
      stderr: "piped",
      env: {
        LD_PRELOAD: root + "build/arena_fault.so",
        BLOT_FAULT_AT: String(fault),
        BLOT_FAULT_COMMIT: "1",
      },
    }).spawn();
    const writer = process.stdin.getWriter(),
      reader = process.stdout.getReader();
    const stderr = new Response(process.stderr).text();
    let buffered = "";
    const request = new TextEncoder().encode(
      JSON.stringify({ input: path, output, package_root: root }) + "\n",
    );
    async function response() {
      while (!buffered.includes("\n")) {
        const chunk = await reader.read();
        if (chunk.done) return null;
        buffered += decoder.decode(chunk.value);
      }
      const at = buffered.indexOf("\n");
      const value = JSON.parse(buffered.slice(0, at));
      buffered = buffered.slice(at + 1);
      return value;
    }
    let first: Record<string, unknown> | null = null,
      last: Record<string, unknown> | null = null;
    try {
      await writer.write(request);
      first = await response();
      if (first?.ok && second) {
        await Deno.writeTextFile(path, text(2) + growth);
        await writer.write(request);
        last = await response();
      }
    } catch (error) {
      if (
        !(error instanceof Deno.errors.BrokenPipe) &&
        !(error instanceof TypeError)
      ) throw error;
    }
    try {
      await writer.close();
    } catch { /* A failed arena terminates the process. */ }
    const status = await process.status;
    await reader.cancel();
    const log = await stderr;
    return {
      first,
      last,
      status,
      events: log.split("BLOT_ALLOC_EVENT\n").length - 1,
      log,
    };
  }
  const first = await run(0, false);
  ensure(first.status.success && first.first?.ok, first.log);
  const stable = await Deno.readFile(output);
  const both = await run(0, true);
  ensure(both.status.success && both.last?.ok, both.log);
  ensure(
    both.events > first.events && both.events < 10000,
    "invalid retained boundary inventory",
  );
  let rejected = 0;
  for (let point = first.events + 1; point <= both.events; point++) {
    await Deno.writeFile(output, stable);
    const result = await run(point, true);
    ensure(
      result.first?.ok === true,
      `first revision failed at retained point ${point}`,
    );
    const bytes = await Deno.readFile(output);
    if (!result.status.success || !result.last?.ok) {
      rejected++;
      ensure(
        bytes.length === stable.length &&
          bytes.every((x, i) => x === stable[i]),
        `partial candidate published at ${point}`,
      );
    } else {
      const { instance } = await WebAssembly.instantiate(bytes);
      ensure(
        (instance.exports.caller as CallableFunction)(40) === 42,
        `incorrect recovery at ${point}`,
      );
    }
  }
  await Deno.writeTextFile(
    root + "test-results/session-arena-faults.json",
    JSON.stringify(
      {
        initialBoundaries: first.events,
        retainedBoundaries: both.events - first.events,
        rejected,
        coverage:
          "Every observed subsequent arena reservation and protected 64 KiB commit boundary for this retained decode/reuse/publication workload; process OOM is fatal, previous Wasm output remains usable.",
      },
      null,
      2,
    ),
  );
});
