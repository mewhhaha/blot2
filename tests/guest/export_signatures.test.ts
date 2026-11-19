import { deepStrictEqual as equal } from "node:assert/strict";

Deno.test("export signatures are available before body checking and private helpers may infer", async () => {
  const compiler = Deno.args[0] ?? new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
  const dir = await Deno.makeTempDir();
  try {
    const path = dir + "/module.blot";
    const source = `type Box is data = $Box { value: U32 }
private func read box => return box.value
func get (box: Box): U32 => return missing_implementation box
func id (x: a): a => return x
const callback: U32 -> U32 = unknown_callback
`;
    async function check(body: string, all = false) {
      await Deno.writeTextFile(path, body);
      const {code, stdout} = await new Deno.Command(compiler, {
        args: ["check-exports", ...(all ? ["--include-private"] : []), path], stdout: "piped",
      }).output();
      const records = new TextDecoder().decode(stdout).trim().split("\n").map(s => JSON.parse(s));
      return [code, records.at(-1).checked, records.at(-1).missing,
        records.slice(0, -1).map(x => [x.code, body.slice(x.start, x.end)])];
    }
    equal(await check(source), [0, 3, 0, []]);
    equal(await check(source, true), [1, 4, 1, [["missing_signature", "box"]]]);
    equal(await check(source + "func curried (x: U32) -> y: U32 => return x\nconst amount = 3\n"),
      [1, 5, 2, [["missing_signature", "y"], ["missing_signature", "amount"]]]);
  } finally { await Deno.remove(dir, {recursive: true}); }
});
