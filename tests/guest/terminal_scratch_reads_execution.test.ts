import { throws } from "node:assert/strict";
import { compileAndRun, equal } from "./compile_helpers.ts";

const fixture = new URL(
  "../../compiler-goose/tests/fixtures/direct/terminal_scratch_reads.sq",
  import.meta.url,
);

Deno.test("a terminal scalar read releases scratch before the fresh loop result", async () => {
  const source = await Deno.readTextFile(fixture);
  const check = async (program: string) => {
    await compileAndRun(program, (guest) => {
      equal(guest.call("fresh", 16384), 16837);
      equal(guest.call("in_place", 16384), 16837);
      equal(guest.call("nested", 16384), 16837);
      equal(guest.call("alias_result", 16384), 33081);
    });
  };
  await check(source);
  // An additional Array field puts the carried structural record in memory.
  await check(source.replace("g: Array U32 }", "g: Array U32, h: Array U32 }")
    .replace("g: #[7] }", "g: #[7], h: #[8] }"));
});

Deno.test("terminal release preserves later reads, publication and trapping expressions", async () => {
  await compileAndRun(await Deno.readTextFile(fixture), (guest) => {
    equal(guest.call("future_read", 4), 31);
    equal(guest.call("later_capture", 4), 31);
    equal(guest.call("mapper_publication", 4), 63);
    equal(guest.call("nested_fill", 16384), 11250);
    throws(() => guest.call("mapper_trap", 1), /divide by zero/);
  });
});
