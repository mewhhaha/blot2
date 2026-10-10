// Ordinary guest programs use the real std/prelude source module. Tests of
// absent catalogs or fixities explicitly request prelude: "none". The CLI
// continues to default to none.
import { instantiateGuest } from "../../compiler/guest.ts";
const compiler = Deno.args[0] ?? new URL("../zig-out/bin/blotc", import.meta.url).pathname;

export async function compileAndRun(
  source: string,
  run: (guest: Awaited<ReturnType<typeof instantiateGuest>>, bytes: Uint8Array<ArrayBuffer>) => void | Promise<void>,
  options: { prelude?: string; stdRoot?: string; asynchronous?: boolean } = {},
): Promise<void> {
  const dir = await Deno.makeTempDir({ dir: new URL("../../build", import.meta.url).pathname, prefix: "zig-native-rich-" });
  try {
    const input = `${dir}/program.blot`;
    const output = `${dir}/program.wasm`;
    await Deno.writeTextFile(input, source);
    const result = await new Deno.Command(compiler, {
      args: ["build", input, output, "--prelude", options.prelude ?? new URL("../../std/prelude.blot", import.meta.url).pathname, ...(options.stdRoot ? ["--std-root", options.stdRoot] : [])], stdout: "piped", stderr: "piped",
    }).output();
    const text = new TextDecoder().decode(result.stdout);
    if (!result.success) throw new Error(`${text}\n${new TextDecoder().decode(result.stderr)}`);
    const metrics = text.trim().split("\n").map(line => JSON.parse(line)).find(value => value.kind === "compilation");
    if (!metrics.success || metrics.memory.live_bytes !== 0) throw new Error(text);
    const bytes = await Deno.readFile(output);
    if (!WebAssembly.validate(bytes)) throw new Error("Invalid native Wasm");
    const guest = await instantiateGuest(bytes, { asynchronous: options.asynchronous });
    try { await run(guest, bytes); } finally { guest.dispose(); }
  } finally { await Deno.remove(dir, { recursive: true }); }
}

export function equal(actual: unknown, expected: unknown): void {
  if (!Object.is(actual, expected)) throw new Error(`Expected ${String(expected)}, received ${String(actual)}`);
}

export async function compileExpectedFailure(source: string, code: string, message?: string, options: { prelude?: string; stdRoot?: string; span?: readonly [number, number] } = {}): Promise<void> {
  const dir = await Deno.makeTempDir({ dir: new URL("../../build", import.meta.url).pathname, prefix: "zig-native-failure-" });
  try {
    const input = `${dir}/program.blot`;
    const output = `${dir}/program.wasm`;
    await Deno.writeTextFile(input, source);
    const execution = await new Deno.Command(compiler, { args: ["build", input, output, "--prelude", options.prelude ?? new URL("../../std/prelude.blot", import.meta.url).pathname, ...(options.stdRoot ? ["--std-root", options.stdRoot] : [])], stdout: "piped", stderr: "piped" }).output();
    const text = new TextDecoder().decode(execution.stdout);
    if (execution.success) throw new Error("Expected compilation to fail");
    const records = text.trim().split("\n").map(line => JSON.parse(line));
    const diagnostic = records.find(record => record.kind === "diagnostic");
    const metrics = records.find(record => record.kind === "compilation");
    equal(diagnostic?.code, code);
    if (options.span !== undefined) {
      equal(diagnostic?.start, options.span[0]);
      equal(diagnostic?.end, options.span[1]);
    }
    if (message !== undefined) equal(diagnostic.message, message);
    equal(metrics?.success, false);
    equal(metrics?.memory.live_bytes, 0);
    try { await Deno.stat(output); } catch (error) {
      if (error instanceof Deno.errors.NotFound) return;
      throw error;
    }
    throw new Error("Failed compilation published output");
  } finally { await Deno.remove(dir, { recursive: true }); }
}
