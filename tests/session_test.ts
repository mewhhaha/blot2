function assert(value: unknown): asserts value {
  if (!value) throw new Error("session assertion failed");
}
function assertEquals(a: unknown, b: unknown) {
  if (a instanceof Uint8Array && b instanceof Uint8Array) {
    assert(a.length === b.length && a.every((x, i) => x === b[i]));
  } else if (a !== b) throw new Error(`expected ${b}, got ${a}`);
}
Deno.test("retained session cuts off unchanged callers and rolls back failed or cancelled revisions", async () => {
  const dir = await Deno.makeTempDir({ prefix: "blot-session-" });
  const source = `${dir}/input.blot`,
    output = `${dir}/output.wasm`,
    cancel = `${dir}/cancel`;
  const body = (n: number, bad = false) =>
    `pub let dependency: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn value => return ${
      bad ? "true" : `U32.wrapping_add(value,${n})`
    }\npub let caller: U32 -> U32 ! {} resources {depth: 2, frame: 0} = fn value => return dependency(value)\n`;
  const process = new Deno.Command("build/blot", {
    args: ["serve"],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = process.stdin.getWriter();
  const lines = process.stdout.pipeThrough(new TextDecoderStream()).pipeThrough(
    new TransformStream<string, string>({
      start() {},
      transform(chunk, controller) {
        pending += chunk;
        let at: number;
        while ((at = pending.indexOf("\n")) >= 0) {
          controller.enqueue(pending.slice(0, at));
          pending = pending.slice(at + 1);
        }
      },
    }),
  ).getReader();
  let pending = "";
  const stderrPromise = new Response(process.stderr).text();
  async function request(cancelled = false) {
    await writer.write(
      new TextEncoder().encode(
        JSON.stringify({
          input: source,
          output,
          package_root: dir,
          ...(cancelled ? { cancel_file: cancel } : {}),
        }) + "\n",
      ),
    );
    const line = await lines.read();
    assert(!line.done);
    return JSON.parse(line.value);
  }
  async function execute() {
    const instance = await WebAssembly.instantiate(await Deno.readFile(output));
    return (instance.instance.exports.caller as (x: number) => number)(40);
  }
  try {
    await Deno.writeTextFile(source, body(1));
    const first = await request();
    assert(first.ok);
    assertEquals(first.revision, 1);
    assertEquals(first.completed_bodies, 2);
    assertEquals(await execute(), 41);
    await Deno.writeTextFile(source, body(2));
    const second = await request();
    assert(second.ok);
    assertEquals(second.revision, 2);
    assertEquals(second.completed_bodies, 1);
    assertEquals(second.reused_bodies, 1);
    assertEquals(await execute(), 42);
    const stable = await Deno.readFile(output);
    await Deno.writeTextFile(source, body(3, true));
    const invalid = await request();
    assert(!invalid.ok);
    assertEquals(invalid.revision, 2);
    assertEquals(await Deno.readFile(output), stable);
    await Deno.writeTextFile(source, body(3));
    await Deno.writeTextFile(cancel, "");
    const cancelled = await request(true);
    assert(!cancelled.ok);
    assertEquals(cancelled.revision, 2);
    assertEquals(await Deno.readFile(output), stable);
    await Deno.remove(cancel);
    const recovered = await request();
    assert(recovered.ok);
    assertEquals(recovered.revision, 3);
    assertEquals(recovered.reused_bodies, 1);
    assertEquals(await execute(), 43);
  } finally {
    await writer.close();
    await process.status;
    await lines.cancel();
    await stderrPromise;
    await Deno.remove(dir, { recursive: true });
  }
});
