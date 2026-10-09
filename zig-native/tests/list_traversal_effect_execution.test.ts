import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

const source = `
type Tick is effect = { read: U32 -> U32 }
let rows = @list.generate 257 (fn i => {a: i, b: i + 1, c: i + 2})
const work = @computation (fn () => do:
  let total = 0
  for row in rows:
    use value <- Tick.read row.a
    total := self + row.b + value + row.c
  return total)
entry const resumed = fn (host: U32 -> U32 ! {Foreign}) => do:
  for request in @requests work:
    case request of
      effect Tick.read value =>
        use next <- host value
        yield next
      complete value =>
        return value
  return 0
entry const returned = fn (host: U32 -> U32 ! {Foreign}) => do:
  for request in @requests work:
    case request of
      effect Tick.read value =>
        use next <- host value
        if value == 83:
          return value
        yield next
      complete value =>
        return value
  return 7
entry const broken = fn (host: U32 -> U32 ! {Foreign}) => do:
  for request in @requests work:
    case request of
      effect Tick.read value =>
        use next <- host value
        if value == 83:
          break
        yield next
      complete value =>
        return value
  return 7
`;
for (const asynchronous of [false, true]) {
  Deno.test(`List row views survive resumed and cancelled effects (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(source, async (guest) => {
      const seen: number[] = [];
      let fail = false;
      const call = (value: number) => {
        if (fail && value === 83) throw new Error("test host failure");
        seen.push(value);
        return value;
      };
      const host = asynchronous
        ? guest.capabilityAsync({
          parameter: "U32",
          result: "U32",
          call: async (value) => {
            await Promise.resolve();
            return call(value);
          },
        })
        : guest.capability({ parameter: "U32", result: "U32", call });
      const run = async (entry: string) =>
        asynchronous
          ? await guest.callAsync(entry, host)
          : guest.call(entry, host);
      let warmed = 0;
      for (let repeat = 0; repeat < 4; repeat++) {
        for (
          const [entry, count, expected] of [
            ["resumed", 257, 3 * 257 * 258 / 2],
            ["returned", 84, 83],
            ["broken", 84, 7],
          ] as const
        ) {
          seen.length = 0;
          assert.equal(await run(entry), expected);
          assert.deepEqual(seen, Array.from({ length: count }, (_, i) => i));
        }
        if (repeat === 0) warmed = guest.memoryBytes();
      }
      assert(guest.memoryBytes() <= warmed + 65536);
      fail = true;
      await assert.rejects(() => run("resumed"));
      fail = false;
      assert.equal(await run("resumed"), 3 * 257 * 258 / 2);
    }, { asynchronous });
  });
}
