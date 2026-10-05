import { instantiateGuest } from "../../compiler/guest.ts";
import { equal } from "./compile_helpers.ts";

const prelude = `
infixl 60 (+) = add
const add = fn left => fn right => @type.call "add" left right
const U32.add = fn left => fn right => @u32.sub left right
const F32.add = fn left => fn right => @f32.add left right
const U32.to_f32 = fn (value: U32) => @u32.to_f32 value
const convert = fn value => value.to_f32
const identity = fn value => value
type Maybe value is data = #Some value | #Nothing
`;

async function fixture(run: (dir: string) => Promise<void>): Promise<void> {
  const dir = await Deno.makeTempDir({ dir: new URL("../../build", import.meta.url).pathname, prefix: "zig-native-prelude-" });
  try {
    await Deno.writeTextFile(`${dir}/prelude.blot`, prelude);
    await Deno.writeTextFile(`${dir}/helper.blot`, "const base = identity 44\n");
    await Deno.writeTextFile(`${dir}/main.blot`, `
import { base } from "./helper"
entry const ordinary = fn () -> U32 => base + 2
entry const primitive = fn () -> U32 => @u32.add 40 2
entry const floating = fn () -> F32 => identity (1.5 + 2.5)
entry const converted = fn (value: U32) -> F32 => convert value
entry const accessor = fn (value: U32) -> F32 => (.to_f32) value
entry const nominal = fn (value: U32) -> U32 => case #Some value of
  #Some item => identity item
  #Nothing => 0
`);
    await run(dir);
  } finally { await Deno.remove(dir, { recursive: true }); }
}

async function command(args: string[]): Promise<{ result: Deno.CommandOutput; records: any[]; text: string }> {
  const executable = Deno.args[0] ?? new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  const result = await new Deno.Command(executable, { args, stdout: "piped", stderr: "piped" }).output();
  const text = new TextDecoder().decode(result.stdout);
  const records = text.trim().split("\n").filter(Boolean).map(line => JSON.parse(line));
  return { result, records, text: `${text}\n${new TextDecoder().decode(result.stderr)}` };
}

Deno.test("actual prelude provides owned generic interfaces, fixities and designated builtin methods", async () => {
  await fixture(async dir => {
    const output = `${dir}/program.wasm`;
    const { result, records, text } = await command(["build", `${dir}/main.blot`, output, "--prelude", `${dir}/prelude.blot`]);
    if (!result.success) throw new Error(text);
    const metrics = records.find(record => record.kind === "compilation");
    if (!metrics?.success || metrics.memory.live_bytes !== 0 || metrics.files !== 3) throw new Error(text);
    const bytes = await Deno.readFile(output);
    if (!WebAssembly.validate(bytes)) throw new Error("Invalid native Wasm");
    const guest = await instantiateGuest(bytes);
    try {
      equal(guest.call("ordinary", null), 42);
      equal(guest.call("primitive", null), 42);
      equal(guest.call("floating", null), 4);
      equal(guest.call("converted", 42), 42);
      equal(guest.call("accessor", 42), 42);
      equal(guest.call("nominal", 42), 42);
    } finally { guest.dispose(); }
  });
});

Deno.test("explicit prelude none and invalid unused producer definitions remain visible", async () => {
  await fixture(async dir => {
    const without = await command(["check", `${dir}/main.blot`, "--prelude", "none"]);
    if (without.result.success || !without.records.some(record => record.kind === "diagnostic" && record.code === "unknown_value")) throw new Error(without.text);
    await Deno.writeTextFile(`${dir}/prelude.blot`, `${prelude}\nconst unused_invalid: Bool = 42\n`);
    const invalid = await command(["check-project", `${dir}/main.blot`, "--prelude", `${dir}/prelude.blot`]);
    if (invalid.result.success || !invalid.records.some(record => record.kind === "diagnostic" && record.filename === `${dir}/prelude.blot`)) throw new Error(invalid.text);
    const metrics = invalid.records.find(record => record.kind === "compilation");
    if (metrics?.memory.live_bytes !== 0) throw new Error(invalid.text);
  });
});
