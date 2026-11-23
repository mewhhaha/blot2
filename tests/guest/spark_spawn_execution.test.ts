import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
import { compileKernelModule } from "../../host/guest.ts";
import { KernelPool } from "../../host/kernels.ts";
import { Processes, type ProcessHandle } from "../../host/processes.ts";

const program = await Deno.readTextFile(
  new URL("../../benchmarks/language/spark_spawn.blot", import.meta.url),
);

Deno.test("spark source maps and KernelPool execution preserve bits, cardinality and order", async () => {
  await compileAndRun(
    program + `
entry func snapshot (read: U32 -> Array U32 ! { Foreign }): Array U32 => return spark #[@u32.add x x | x <- read 7]
entry func keep_float (xs: Array F32): Array F32 => return spark #[x | x <- xs]
entry kernel func negative (x: U32): F32 => return @f32.neg (@u32.to_f32 x)
entry kernel func reciprocal (x: U32): F32 => return @f32.div 1.0 (@u32.to_f32 x)
`,
    async (guest, bytes) => {
      const floating = Float32Array.of(-0, Infinity, -Infinity, 1.25);
      const unchanged = guest.call("keep_float", floating) as Float32Array;
      equal(
        String(new Uint32Array(unchanged.buffer)),
        String(new Uint32Array(floating.buffer)),
      );
      let calls = 0;
      const read = guest.capability({
        parameter: "U32",
        result: "Array U32",
        call: (key) => {
          equal(key, 7);
          calls++;
          return Uint32Array.of(0xffffffff, 8, 1);
        },
      });
      equal(String(guest.call("snapshot", read)), "4294967294,16,2");
      equal(calls, 1);

      const receipt = compileKernelModule(bytes);
      const directPool = await KernelPool.open(receipt, "negative", {
        workers: 0,
      });
      const pool = await KernelPool.open(receipt, "negative", {
        workers: 3,
        defaultChunkItems: 2,
        deadlineMs: 2000,
      });
      try {
        for (
          const xs of [
            new Uint32Array(),
            Uint32Array.of(0),
            Uint32Array.of(8, 0, 5, 2, 5, 3, 0xffffffff),
          ]
        ) {
          const directWords = await directPool.runFixed(xs);
          const copiedWords = await pool.runFixed(xs);
          const direct = new Float32Array(directWords.buffer);
          const copied = new Float32Array(copiedWords.buffer);
          equal(copied.length, xs.length);
          for (const [i, x] of xs.entries()) {
            equal(direct[i], -Math.fround(x));
            equal(copied[i], direct[i]);
          }
          equal(
            String(guest.call("spark_mix", xs)),
            String(guest.call("ordinary_mix", xs)),
          );
          equal(
            String(guest.call("spark_mix", xs)),
            String(guest.call("indexed_mix", xs)),
          );
        }
        // Mutating caller input right after runFixed must not alter snapshot bytes.
        const xs = Uint32Array.of(7, 0, 12);
        const pending = pool.runFixed(xs);
        xs.fill(255);
        const resultWords = await pending;
        const result = new Float32Array(resultWords.buffer);
        equal(result[0], -7);
        equal(result[1], -0);
        equal(result[2], -12);
        const afterWords = await pool.runFixed(xs);
        equal(new Float32Array(afterWords.buffer)[0], -255);
      } finally {
        await Promise.all([directPool.close(), pool.close()]);
      }

      const directRecip = await KernelPool.open(receipt, "reciprocal", {
        workers: 0,
      });
      const reciprocal = await KernelPool.open(receipt, "reciprocal", {
        workers: 2,
        defaultChunkItems: 1,
        deadlineMs: 2000,
      });
      try {
        const rows = Uint32Array.of(1, 0, 4);
        const direct = await directRecip.runFixed(rows);
        const copied = await reciprocal.runFixed(rows);
        equal(new Float32Array(direct.buffer)[1], Infinity);
        equal(String(copied), String(direct));
      } finally {
        await Promise.all([directRecip.close(), reciprocal.close()]);
      }
    },
  );
});

Deno.test("Processes uses scoped admission and isolated budgeted turns with reserved terminal events", async () => {
  await compileAndRun(
    program + `
func faulty_init (seed: U32): U32 => return @panic "initialization"
func faulty_step (st: own U32) -> (cmd: U32): (U32, U32) => return (st, 0)
entry process faulty: Process [U32, U32, U32] = { init: faulty_init, step: faulty_step }

func fragile_init (seed: U32): U32 => return seed
func fragile_step (st: own U32) -> (cmd: U32): (U32, U32) => return @panic "step"
entry process fragile: Process [U32, U32, U32] = { init: fragile_init, step: fragile_step }
`,
    async (guest, bytes) => {
      const host = new Processes(
        bytes,
        ["planner", "faulty", "fragile"].map((name) => ({
          name,
          initWork: 2,
          stepWork: 1,
          mailbox: 2,
          mailboxBytes: 64,
          maxReplyBytes: 4,
        })),
        { slots: 2 },
      );
      const handles = new Map<number, ProcessHandle>();
      const cap = guest.capability({
        parameter: "Array U32",
        result: "U32",
        call: (packet) => {
          const name = new TextDecoder().decode(
            Uint8Array.from(packet.subarray(1)),
          );
          const h = host.admit(name, packet[0]);
          if (h === null) return 0;
          handles.set(h.endpoint, h);
          return h.endpoint;
        },
      });
      const start = () => {
        const id = guest.call("live", cap) as number;
        return id === 0 ? null : handles.get(id)!;
      };
      equal(guest.call("local", 7), 7);
      const a = start()!, b = start()!;
      equal(a.endpoint > 0 && b.endpoint > a.endpoint, true);
      equal(start(), null);
      equal(host.send(a, 1), "starting");
      equal(await host.advance(1), 0);
      equal(await host.advance(2), 2);
      equal(host.status(a), "ready");
      equal(host.status(b), "starting");
      equal(await host.advance(2), 2);
      const aa = host.send(a, 2) as number,
        ab = host.send(a, 3) as number,
        ba = host.send(b, 5) as number;
      equal(host.send(a, 4), "full");
      equal(host.cancel(a, ab), true);
      equal(host.cancel(a, ab), false);
      equal(await host.advance(2), 2);
      equal(host.cancel(a, aa), false);
      equal(host.send(a, 4), "full");
      equal(
        JSON.stringify(host.poll(a)),
        JSON.stringify({ ticket: ab, status: "cancelled" }),
      );
      equal(
        JSON.stringify(host.poll(a)),
        JSON.stringify({
          ticket: aa,
          status: "done",
          value: 13,
          logicalReplyBytes: 4,
        }),
      );
      equal(
        JSON.stringify(host.poll(b)),
        JSON.stringify({
          ticket: ba,
          status: "done",
          value: 16,
          logicalReplyBytes: 4,
        }),
      );
      host.send(a, 1);
      await host.close(a);
      equal(host.release(a), false);
      equal(host.poll(a)?.status, "cancelled");
      equal(host.release(a), true);
      await host.close(b);
      equal(host.release(b), true);

      const bad = host.admit("faulty", 11)!, fail = host.admit("fragile", 11)!;
      await host.advance(4);
      equal(host.status(bad), "failed");
      host.send(fail, 1);
      host.send(fail, 2);
      await host.advance(1);
      equal(host.status(fail), "failed");
      equal(host.poll(fail)?.status, "failed");
      equal(host.poll(fail)?.status, "failed");
      await host.restore();
      equal(host.send(a, 3), "stale");

      const old = start()!;
      const turn = host.advance(8);
      await host.restore();
      const fresh = start()!;
      await turn;
      equal(host.status(old), "closed");
      equal(host.status(fresh), "starting");
      equal(await host.advance(2), 2);
      equal(host.status(fresh), "ready");
      const done = host.send(fresh, 2), pending = host.send(fresh, 3);
      await host.advance(1);
      equal(host.send(fresh, 4), "full");
      const retired = await host.restore();
      equal(
        JSON.stringify(retired.get(fresh)),
        JSON.stringify([
          { ticket: done, status: "done", value: 13, logicalReplyBytes: 4 },
          { ticket: pending, status: "cancelled" },
        ]),
      );
      equal(host.poll(fresh), undefined);
      equal((await host.restore()).size, 0);
    },
  );
});

Deno.test("a process skipped for the remaining work gets the next full allowance", async () => {
  await compileAndRun(
    program + `
func slower_init (seed: U32): U32 => return seed
func slower_step (st: own U32) -> (delta: U32): (U32, U32) =>
  let next = @u32.add st delta
  return (next, next)
entry process slower: Process [U32, U32, U32] = { init: slower_init, step: slower_step }
`,
    async (_guest, bytes) => {
      const host = new Processes(
        bytes,
        [
          {
            name: "planner",
            initWork: 1,
            stepWork: 1,
            mailbox: 1,
            mailboxBytes: 64,
            maxReplyBytes: 4,
          },
          {
            name: "slower",
            initWork: 1,
            stepWork: 2,
            mailbox: 1,
            mailboxBytes: 64,
            maxReplyBytes: 4,
          },
        ],
        { slots: 3 },
      );
      try {
        const left = host.admit("planner", 10)!,
          deferred = host.admit("slower", 10)!,
          right = host.admit("planner", 10)!;
        equal(await host.advance(3), 3);
        const first = host.send(left, 1);
        const later = host.send(deferred, 20);
        const third = host.send(right, 3);

        equal(await host.advance(2), 2);
        equal(host.poll(left)?.ticket, first);
        equal(host.poll(right)?.ticket, third);
        equal(host.poll(deferred), undefined);
        const nextLeft = host.send(left, 4);
        const nextRight = host.send(right, 5);

        equal(await host.advance(2), 2);
        equal(
          JSON.stringify(host.poll(deferred)),
          JSON.stringify({
            ticket: later,
            status: "done",
            value: 30,
            logicalReplyBytes: 4,
          }),
        );
        equal(host.poll(left), undefined);
        equal(host.poll(right), undefined);
        equal(await host.advance(2), 2);
        equal(host.poll(left)?.ticket, nextLeft);
        equal(host.poll(right)?.ticket, nextRight);
      } finally {
        await host.restore();
      }
    },
  );
});

Deno.test("spark accepts pure helpers and captures while rejecting invalid generators, effects, and legacy intrinsics", async () => {
  await compileAndRun(
    `func hidden (x: U32): U32 => return @u32.add x 1
const captured: U32 = 5
entry func pure_spark (xs: Array U32): Array U32 => return spark #[@u32.add (hidden x) captured | x <- xs]
entry func range_spark (n: U32): Array U32 => return spark #[@u32.add x 10 | x <- 0..n]
`,
    (guest) => {
      equal(String(guest.call("pure_spark", Uint32Array.of(1, 2, 3))), "7,8,9");
      equal(String(guest.call("range_spark", 4)), "10,11,12,13");
    },
  );
  await compileExpectedFailure(
    "entry func nope (xs: Array U32) => return spark #[x | x <- xs, x <- xs]\n",
    "spark_generator",
  );
  await compileExpectedFailure(
    "entry func nope (xs: Array U32) => return spark #[x | x <- xs, x < 8]\n",
    "spark_generator",
  );
  await compileExpectedFailure(
    "entry func nope (xs: U32) => return spark #[x | x <- xs]\n",
    "type_mismatch",
  );
  await compileExpectedFailure(
    "entry func nope (xs: Array U32) => return @spark #[x | x <- xs]\n",
    "unknown_intrinsic",
  );
  await compileExpectedFailure(
    "entry func nope (xs: Array U32) => return @spark.within 100 #[x | x <- xs]\n",
    "unknown_intrinsic",
  );
  await compileExpectedFailure(
    `effect Ping: Unit -> U32
entry func nope (xs: Array U32): Array U32 ! { Ping } => return spark #[Ping () | x <- xs]
`,
    "spark_effectful",
  );
  await compileExpectedFailure(
    `func bad_step (st: U32) -> (cmd: U32): (U32, U32) => return (st, cmd)
func init_p (seed: U32): U32 => return seed
entry process p: Process [U32, U32, U32] = { init: init_p, step: bad_step }
`,
    "kernel_callable",
  );
});
