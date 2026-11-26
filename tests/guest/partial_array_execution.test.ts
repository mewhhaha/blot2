import { instantiateGuest } from "../../host/guest.ts";
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
const even = func value => return value % 2 == 0
const choose = func value => return if even value then $Some (value * 10) else $Nothing
io const answer = func () => return do:
  let selected = array.filter even numbers
  let mapped = array.filter_map choose numbers
  let payload = array.concat selected #[6]
  let flat = array.flatten #[{start: 0, count: 0}, {start: 0, count: selected.length},
    {start: selected.length, count: 0}, {start: selected.length, count: 1}] payload
  let (left, right) = array.unzip (array.zip flat mapped)
  break left[0] + right[1]
const no_payload: Array U32 = #[]
io const empties = array.length (array.flatten #[{start: 0, count: 0}, {start: 0, count: 0}] no_payload)
io const last = array.fold_left add 0 (array.push 6 (array.slice 1 2 numbers))
`,
    );
    const compiler = Deno.args[0] ??
      new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
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

// Direct backend gap: a member result chosen by `@type.result` and an empty array whose element type no use fixes are unresolved type variables (tasks/DELETE_SCOPED.md).
Deno.test.ignore("partial Array methods keep result evidence without constraining shared empty element variables", async () => {
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
        '\nconst Array.convert = func values => return @type.result "from" (@array.length values)\n',
    );
    await compileAndRun(
      `
const values = #[]
const map = func transform => return func items => return @array.generate items.length (func index => return transform items[index])
io const zero: F32 = values.convert
io const nested: F32 = #[#[], #[]].convert
io const concrete: F32 = #[1, 2].convert
io const length = values.length
io const mapped = (map .length #[#[], #[]])[1]
io const runtime = func () : F32 => return #[].convert
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
