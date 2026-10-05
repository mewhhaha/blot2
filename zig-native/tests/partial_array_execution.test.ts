import { instantiateGuest } from "../../compiler/guest.ts";
import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("real array library retains generic empty chunks alongside ordinary filtering and zipping", async () => {
  const dir = await Deno.makeTempDir({
    dir: new URL("../../build", import.meta.url).pathname,
    prefix: "zig-native-empty-chunks-",
  });
  try {
    await Deno.writeTextFile(
      `${dir}/array.blot`,
      await Deno.readTextFile(
        new URL("../../std/array.blot", import.meta.url),
      ),
    );
    await Deno.writeTextFile(
      `${dir}/main.blot`,
      `
import * as array from "./array"
const numbers = #[1, 2, 3, 4, 5]
const even = fn value => value % 2 == 0
const choose = fn value => if even value then #Some (value * 10) else #Nothing
entry const answer = fn () => do:
  let selected = array.filter even numbers
  let mapped = array.filter_map choose numbers
  let flat = array.flatten #[#[], selected, #[], #[6]]
  let (left, right) = array.unzip (array.zip flat mapped)
  return left[0] + right[1]
entry const empties = array.length (array.flatten #[#[], #[]])
entry const last = array.fold_left add 0 (array.push 6 (array.slice 1 2 numbers))
`,
    );
    const compiler = Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url).pathname;
    const output = `${dir}/main.wasm`;
    const result = await new Deno.Command(compiler, {
      args: [
        "build",
        `${dir}/main.blot`,
        output,
        "--prelude",
        new URL("../../std/prelude.blot", import.meta.url).pathname,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const text = new TextDecoder().decode(result.stdout);
    if (!result.success) throw new Error(text);
    const metrics = text.trim().split("\n").map((line) => JSON.parse(line))
      .find((row) => row.kind === "compilation");
    equal(metrics.memory.live_bytes, 0);
    const bytes = await Deno.readFile(output);
    equal(WebAssembly.validate(bytes), true);
    const guest = await instantiateGuest(bytes);
    try {
      for (let index = 0; index < 10; index++) {
        equal(guest.call("answer", null), 42);
      }
      equal(guest.read("empties"), 0);
      equal(guest.read("last"), 11);
    } finally {
      guest.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("partial Array methods keep result evidence without constraining shared empty element variables", async () => {
  const dir = await Deno.makeTempDir({
    dir: new URL("../../build", import.meta.url).pathname,
    prefix: "zig-native-partial-array-",
  });
  try {
    const prelude = await Deno.readTextFile(
      new URL("../../std/prelude.blot", import.meta.url),
    );
    await Deno.writeTextFile(
      `${dir}/prelude.blot`,
      prelude +
        '\nconst Array.convert = fn values => @type.result "from" (@array.length values)\n',
    );
    await compileAndRun(
      `
const values = #[]
const map = fn transform => fn items => @array.generate items.length (fn index => transform items[index])
entry const zero: F32 = values.convert
entry const nested: F32 = #[#[], #[]].convert
entry const concrete: F32 = #[1, 2].convert
entry const length = values.length
entry const mapped = (map .length #[#[], #[]])[1]
entry const runtime = fn () -> F32 => #[].convert
`,
      (guest) => {
        equal(guest.read("zero"), 0);
        equal(guest.read("nested"), 2);
        equal(guest.read("concrete"), 2);
        equal(guest.read("length"), 0);
        equal(guest.read("mapped"), 0);
        for (let index = 0; index < 10; index++) {
          equal(guest.call("runtime", null), 0);
        }
      },
      { prelude: `${dir}/prelude.blot` },
    );
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
