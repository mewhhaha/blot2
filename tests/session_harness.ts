export function assert(
  ok: unknown,
  message = "session assertion failed",
): asserts ok {
  if (!ok) throw new Error(message);
}
export type SessionResult = {
  ok: boolean;
  revision: number;
  completed_bodies: number;
  reused_bodies: number;
  [key: string]: unknown;
};
export async function sessionCase(
  run: (session: {
    dir: string;
    input: string;
    output: string;
    request: (extra?: Record<string, unknown>) => Promise<SessionResult>;
    raw: (line: string) => Promise<SessionResult>;
    execute: (name?: string, arg?: number) => Promise<number>;
    cold: () => Promise<number>;
  }) => Promise<void>,
) {
  const dir = await Deno.makeTempDir({ prefix: "blot-session-edits-" });
  const input = `${dir}/input.blot`, output = `${dir}/output.wasm`;
  const process = new Deno.Command("build/blot", {
    args: ["serve"],
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = process.stdin.getWriter();
  let pending = "";
  const reader = process.stdout.pipeThrough(new TextDecoderStream())
    .pipeThrough(
      new TransformStream<string, string>({
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
  const errors = new Response(process.stderr).text();
  async function raw(line: string) {
    await writer.write(new TextEncoder().encode(line + "\n"));
    const result = await reader.read();
    assert(!result.done, "session exited unexpectedly");
    return JSON.parse(result.value) as SessionResult;
  }
  async function executeFile(file: string, name = "run", arg = 40) {
    const { instance } = await WebAssembly.instantiate(
      await Deno.readFile(file),
    );
    return (instance.exports[name] as (n: number) => number)(arg) >>> 0;
  }
  try {
    await run({
      dir,
      input,
      output,
      raw,
      request: (extra = {}) =>
        raw(JSON.stringify({ input, output, package_root: dir, ...extra })),
      execute: (name, arg) => executeFile(output, name, arg),
      cold: async () => {
        const file = `${dir}/cold.wasm`;
        const r = await new Deno.Command("build/blot", {
          args: ["build", input, "-o", file, `--package-root=${dir}`],
          stdout: "piped",
          stderr: "piped",
        }).output();
        assert(r.success, new TextDecoder().decode(r.stderr));
        return executeFile(file);
      },
    });
  } finally {
    await writer.close();
    await process.status;
    await reader.cancel();
    const diagnostics = await errors;
    await Deno.remove(dir, { recursive: true });
    if ((await process.status).code !== 0) throw new Error(diagnostics);
  }
}
