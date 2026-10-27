import { assert } from "./session_harness.ts";
function lines(stream: ReadableStream<Uint8Array>) {
  let pending = "";
  return stream.pipeThrough(new TextDecoderStream()).pipeThrough(
    new TransformStream<string, string>({
      transform(chunk, controller) {
        pending += chunk;
        let end: number;
        while ((end = pending.indexOf("\n")) >= 0) {
          controller.enqueue(pending.slice(0, end));
          pending = pending.slice(end + 1);
        }
      },
    }),
  );
}
Deno.test("REV-01 cancellation after completed dependency modules preserves the last revision", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-cancellation-" });
  const input = `${dir}/input.blot`,
    output = `${dir}/output.wasm`,
    cancel = `${dir}/cancel`;
  const original =
    "pub let run: Unit -> U32 ! {} resources {depth:1,frame:0} = fn () => return 41\n";
  let candidate = "";
  for (let m = 0; m < 16; m++) {
    candidate += `import "./m${m}.blot" as m${m}\n`;
    let source = "";
    for (let f = 0; f < 100; f++) {
      source +=
        `let f${f}: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return U32.wrapping_add(x,${f})\n`;
    }
    await Deno.writeTextFile(`${dir}/m${m}.blot`, source);
  }
  candidate += original.replace("41", "42");
  const process = new Deno.Command("build/blot", {
    args: ["serve"],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = process.stdin.getWriter(),
    reader = lines(process.stdout).getReader();
  let interrupted = false, errors = "";
  const drain = (async () => {
    for await (const line of lines(process.stderr)) {
      errors += line + "\n";
      if (!interrupted && line.includes('"phase":"module-complete"')) {
        interrupted = true;
        await Deno.writeTextFile(cancel, "");
      }
    }
  })();
  async function request(trace = false) {
    await writer.write(
      new TextEncoder().encode(
        JSON.stringify({
          input,
          output,
          package_root: dir,
          ...(trace ? { trace: true, cancel_file: cancel } : {}),
        }) + "\n",
      ),
    );
    const line = await reader.read();
    assert(!line.done, errors);
    return JSON.parse(line.value);
  }
  try {
    await Deno.writeTextFile(input, original);
    assert((await request()).ok);
    const stable = await Deno.readFile(output);
    await Deno.writeTextFile(input, candidate);
    const cancelled = await request(true);
    assert(interrupted && !cancelled.ok && cancelled.revision === 1, errors);
    assert(
      cancelled.completed_modules > 0 && cancelled.completed_modules < 17,
      "cancellation did not occur during module completion",
    );
    const after = await Deno.readFile(output);
    assert(
      after.length === stable.length && after.every((b, i) => b === stable[i]),
    );
    await Deno.remove(cancel);
    await Deno.writeTextFile(input, original);
    const recovered = await request();
    assert(
      recovered.ok && recovered.reused_bodies === 1 && recovered.revision === 2,
    );
    assert(
      recovered.active_regions === 0 && recovered.downstream_regions === 0,
    );
    const { instance } = await WebAssembly.instantiate(
      await Deno.readFile(output),
    );
    assert((instance.exports.run as () => number)() === 41);
  } finally {
    await writer.close();
    await process.status;
    await drain;
    await reader.cancel();
    await Deno.remove(dir, { recursive: true });
  }
});
