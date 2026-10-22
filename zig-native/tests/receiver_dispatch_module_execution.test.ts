import { ok } from "node:assert/strict";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { equal } from "./compile_helpers.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

Deno.test("generic receiver calls select members of a caller's type their module never imports", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`, helper = `${directory}/mix.blot`;
  const prelude = new URL("../../std/prelude.blot", import.meta.url);
  const compiler = await createZigProjectCompiler({ executable, entry, prelude });
  try {
    const built = await compiler.build({
      sources: {
        [entry]: `import * as mix from "./mix"
type Gauge is data = #Gauge F32
const Gauge.lerp = fn (a: Gauge) => fn (b: Gauge) => fn (t: F32) => do:
  let #Gauge x = a
  let #Gauge y = b
  break #Gauge (x + (y - x) * t)
entry const main = fn (x: F32) -> F32 => do:
  let #Gauge v = mix.halfway (#Gauge 0.0) (#Gauge x)
  break v
`,
        [helper]: "const halfway = fn a => fn b => a.lerp b 0.5\n",
      },
    });
    ok(built.success, JSON.stringify(built));
    const guest = await instantiateGuest(built.bytes);
    try {
      equal(guest.call("main", 4), 2);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
