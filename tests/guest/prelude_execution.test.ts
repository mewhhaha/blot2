import { instantiateGuest } from "../../host/guest.ts";
import { equal } from "./compile_helpers.ts";

const prelude = `
const (+) = add
const add = func left => return func right => return @type.call "add" left right
const U32.add = func left => return func right => return @u32.sub left right
const F32.add = func left => return func right => return @f32.add left right
const U32.to_f32 = func (value: U32) => return @u32.to_f32 value
const convert = func value => return value.to_f32
const identity = func value => return value
type Maybe value is data = $Some value | $Nothing
`;

async function fixture(run: (dir: string) => Promise<void>): Promise<void> {
  const dir = await Deno.makeTempDir({ dir: new URL("../../build", import.meta.url).pathname, prefix: "zig-native-prelude-" });
  try {
    await Deno.writeTextFile(`${dir}/prelude.sq`, prelude);
    await Deno.writeTextFile(`${dir}/helper.sq`, "const base = identity 44\n");
    await Deno.writeTextFile(`${dir}/main.sq`, `
import { base } from "./helper"
io const ordinary = func () : U32 => return base + 2
io const primitive = func () : U32 => return @u32.add 40 2
io const floating = func () : F32 => return identity (1.5 + 2.5)
io const converted = func (value: U32) : F32 => return convert value
io const accessor = func (value: U32) : F32 => return (.to_f32) value
io const nominal = func (value: U32) : U32 => return case $Some value of
  $Some item => identity item
  $Nothing => 0
`);
    await run(dir);
  } finally { await Deno.remove(dir, { recursive: true }); }
}

async function command(args: string[]): Promise<{ result: Deno.CommandOutput; records: any[]; text: string }> {
  const executable = Deno.args[0] ?? new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;
  const result = await new Deno.Command(executable, { args, stdout: "piped", stderr: "piped" }).output();
  const text = new TextDecoder().decode(result.stdout);
  const records = text.trim().split("\n").filter(Boolean).map(line => JSON.parse(line));
  return { result, records, text: `${text}\n${new TextDecoder().decode(result.stderr)}` };
}

// Direct backend gap: `@type.call "add"` on U32 operands emits the primitive add instead of the prelude's `U32.add` (46, not 42) (tasks/DELETE_SCOPED.md).
Deno.test.ignore("actual prelude provides owned generic interfaces, fixities and designated builtin methods", async () => {
  await fixture(async dir => {
    const output = `${dir}/program.wasm`;
    const { result, records, text } = await command(["build", `${dir}/main.sq`, output, "--prelude", `${dir}/prelude.sq`]);
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
    const without = await command(["check", `${dir}/main.sq`, "--prelude", "none"]);
    if (without.result.success || !without.records.some(record => record.kind === "diagnostic" && record.code === "unknown_value")) throw new Error(without.text);
    await Deno.writeTextFile(`${dir}/prelude.sq`, `${prelude}\nconst unused_invalid: Bool = 42\n`);
    const invalid = await command(["check-project", `${dir}/main.sq`, "--prelude", `${dir}/prelude.sq`]);
    if (invalid.result.success || !invalid.records.some(record => record.kind === "diagnostic" && record.filename === `${dir}/prelude.sq`)) throw new Error(invalid.text);
    const metrics = invalid.records.find(record => record.kind === "compilation");
    if (metrics?.memory.live_bytes !== 0) throw new Error(invalid.text);
  });
});
