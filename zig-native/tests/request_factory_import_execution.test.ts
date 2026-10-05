import { strictEqual } from "node:assert/strict";
import { instantiateGuest } from "../../compiler/guest.ts";

const compiler = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const buildDir = new URL("../../build", import.meta.url).pathname;
const asyncWasm = WebAssembly as typeof WebAssembly & {
  Suspending?: unknown;
  promising?: unknown;
};
const jspi = typeof asyncWasm.Suspending === "function" &&
  typeof asyncWasm.promising === "function";

// The arguments increment State in source order; the imported factory runs
// once and retains the caller's original captured value across later updates.
// Reordering, replaying construction or capturing the changed value changes 99.
const mainSource =
  'import * as factory from "./factory"\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect factory.Tick.read value =>\n        yield @f32.add (@u32.to_f32 value) 2.5\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let (#factory.Count count, value) = @state.run (#factory.Count 0) (fn () => do:\n    let bias = 40\n    use computation <- factory.make (do:\n      use previous <- @state.get factory.witness\n      let #factory.Count old = previous\n      use @state.set (#factory.Count (@u32.add old 1))\n      return old\n    ) (do:\n      use previous <- @state.get factory.witness\n      let #factory.Count old = previous\n      use @state.set (#factory.Count (@u32.add old 1))\n      return old\n    ) (fn () => factory.Tick.read bias)\n    bias := 99\n    let selected = computation\n    let read = fn () => handled selected\n    return @f32.add (read ()) (read ())\n  )\n  return @f32.add (@u32.to_f32 count) value\nentry const folded = answer ()\n';
const factorySource =
  'data Count value = #Count value\ntype Tick is effect = { read: U32 -> F32 }\nconst witness = fn () -> Count U32 => @panic "type witness executed"\nconst make = fn first => fn second => fn action => do:\n  use previous <- @state.get witness\n  let #Count count = previous\n  use @state.set (#Count (@u32.add count 10))\n  let offset = @u32.add (@u32.mul first 10) second\n  return @computation (fn () => @f32.add (@u32.to_f32 offset) (action ()))\n';

for (const asynchronous of [false, true]) {
  Deno.test({
    name:
      `Requests imported factories preserve argument order, State and captures (${
        asynchronous ? "JSPI" : "sync"
      })`,
    ignore: asynchronous && !jspi,
    fn: async () => {
      const directory = await Deno.makeTempDir({
        dir: buildDir,
        prefix: "zig-native-request-factory-",
      });
      try {
        await Deno.writeTextFile(`${directory}/main.blot`, mainSource);
        await Deno.writeTextFile(`${directory}/factory.blot`, factorySource);
        const output = `${directory}/program.wasm`;
        const built = await new Deno.Command(compiler, {
          args: [
            "build-project",
            `${directory}/main.blot`,
            output,
            "--prelude",
            "none",
          ],
          stdout: "piped",
          stderr: "piped",
        }).output();
        const text = new TextDecoder().decode(built.stdout);
        if (!built.success) {
          throw new Error(`${text}\n${new TextDecoder().decode(built.stderr)}`);
        }
        const metrics = text.trim().split("\n").map((line) => JSON.parse(line))
          .find((row) => row.kind === "compilation");
        strictEqual(metrics?.success, true);
        strictEqual(metrics?.memory.live_bytes, 0);
        const bytes = await Deno.readFile(output);
        strictEqual(WebAssembly.validate(bytes), true);
        await WebAssembly.compile(bytes);
        const guest = await instantiateGuest(bytes, { asynchronous });
        try {
          strictEqual(guest.read("folded"), 99);
          for (let iteration = 0; iteration < 100; iteration++) {
            strictEqual(
              asynchronous
                ? await guest.callAsync("answer", null)
                : guest.call("answer", null),
              99,
            );
          }
        } finally {
          guest.dispose();
        }
      } finally {
        await Deno.remove(directory, { recursive: true });
      }
    },
  });
}
