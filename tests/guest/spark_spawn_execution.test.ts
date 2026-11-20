import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
import { ProcessHost } from "../../host/processes.ts";
import { SparkPool } from "../../host/sparks.ts";

const program = await Deno.readTextFile(
  new URL("../../benchmarks/language/spark_spawn.blot", import.meta.url),
);

Deno.test("spark source maps and worker recovery preserve bits, cardinality and order", async () => {
  await compileAndRun(
    program + `
entry func snapshot (read: U32 -> Array U32 ! { Foreign }): Array U32 => return @spark #[@u32.add x x | x <- read 7]
entry func keep_float (xs: Array F32): Array F32 => return @spark #[x | x <- xs]
entry func negative (xs: Array U32): Array F32 => return @spark #[@f32.neg (@u32.to_f32 x) | x <- xs]
entry func reciprocal (xs: Array U32): Array F32 => return @spark #[@f32.div 1.0 (@u32.to_f32 x) | x <- xs]
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
      const module = await WebAssembly.compile(bytes);
      const pool = await SparkPool.open(module, {
        entry: "negative",
        width: 1,
        workers: 3,
        waitMs: 2000,
      });
      try {
        for (
          const xs of [
            new Uint32Array(),
            Uint32Array.of(0),
            Uint32Array.of(8, 0, 5, 2, 5, 3, 0xffffffff),
          ]
        ) {
          const direct = pool.direct(xs);
          const copied = await pool.run(xs);
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
        equal(pool.fallbacks, 0);
        const xs = Uint32Array.of(7, 0, 12);
        const pending = pool.run(xs);
        xs.fill(255);
        pool.retireWorkers();
        const result = await pending;
        equal(result[0], -7);
        equal(result[1], -0);
        equal(result[2], -12);
        equal(pool.fallbacks, 1);
        equal((await pool.run(xs))[0], -255);
      } finally {
        await pool.close();
      }
      const reciprocal = await SparkPool.open(module, {
        entry: "reciprocal",
        width: 1,
        workers: 2,
        waitMs: 2000,
      });
      try {
        const rows = Uint32Array.of(1, 0, 4);
        const direct = reciprocal.direct(rows);
        const copied = await reciprocal.run(rows);
        equal(direct[1], Infinity);
        equal(
          String(new Uint32Array(copied.buffer)),
          String(new Uint32Array(direct.buffer)),
        );
        equal(reciprocal.fallbacks, 0);
      } finally {
        await reciprocal.close();
      }
    },
  );
});

Deno.test("spawn uses scoped admission and isolated budgeted turns with reserved terminal events", async () => {
  await compileAndRun(
    program + `
entry func faulty (seed: U32): U32 => return @panic "initialization"
entry func faulty_step (pair: Array U32): U32 => return 0
entry func fragile (seed: U32): U32 => return seed
entry func fragile_step (pair: Array U32): U32 => return @panic "step"
`,
    async (guest, bytes) => {
      const module = await WebAssembly.compile(bytes);
      const host = new ProcessHost(
        module,
        ["planner", "faulty", "fragile"].map((name) => ({
          name,
          initWork: 2,
          stepWork: 1,
        })),
        2,
        2,
      );
      const cap = guest.capability({
        parameter: "Array U32",
        result: "U32",
        call: (packet) => host.admit(packet),
      });
      const start = () => guest.call("live", cap) as number;
      const raw = (name: string) =>
        host.admit(Uint32Array.of(11, ...new TextEncoder().encode(name)));
      equal(guest.call("local", 7), 7);
      const a = start(), b = start();
      equal(a > 0 && b > a, true);
      equal(start(), 0);
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
        JSON.stringify({ ticket: aa, status: "done", value: 13 }),
      );
      equal(
        JSON.stringify(host.poll(b)),
        JSON.stringify({ ticket: ba, status: "done", value: 16 }),
      );
      host.send(a, 1);
      host.close(a);
      equal(host.release(a), false);
      equal(host.poll(a)?.status, "cancelled");
      equal(host.release(a), true);
      host.close(b);
      equal(host.release(b), true);
      const bad = raw("faulty"), fail = raw("fragile");
      await host.advance(4);
      equal(host.status(bad), "failed");
      host.send(fail, 1);
      host.send(fail, 2);
      await host.advance(1);
      equal(host.status(fail), "failed");
      equal(host.poll(fail)?.status, "failed");
      equal(host.poll(fail)?.status, "failed");
      host.restore();
      equal(host.send(a, 3), "closed");
      const old = start(), turn = host.advance(8);
      host.restore();
      const fresh = start();
      await turn;
      equal(host.status(old), "closed");
      equal(host.status(fresh), "starting");
      equal(await host.advance(2), 2);
      equal(host.status(fresh), "ready");
      const done = host.send(fresh, 2), pending = host.send(fresh, 3);
      await host.advance(1);
      equal(host.send(fresh, 4), "full");
      const retired = host.restore();
      equal(
        JSON.stringify(retired.get(fresh)),
        JSON.stringify([
          { ticket: done, status: "done", value: 13 },
          { ticket: pending, status: "cancelled" },
        ]),
      );
      equal(host.poll(fresh), undefined);
      equal(host.restore().size, 0);
    },
  );
});

Deno.test("a process skipped for the remaining work gets the next full allowance", async () => {
  await compileAndRun(
    program + `
entry func slower (seed: U32): U32 => return seed
entry func slower_step (pair: Array U32): U32 => return @u32.add pair[0] pair[1]
`,
    async (_guest, bytes) => {
      const host = new ProcessHost(
        await WebAssembly.compile(bytes),
        [
          { name: "planner", initWork: 1, stepWork: 1 },
          { name: "slower", initWork: 1, stepWork: 2 },
        ],
        3,
        1,
      );
      try {
        const admit = (name: string) =>
          host.admit(Uint32Array.of(10, ...new TextEncoder().encode(name)));
        const left = admit("planner"),
          deferred = admit("slower"),
          right = admit("planner");
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
          }),
        );
        equal(host.poll(left), undefined);
        equal(host.poll(right), undefined);
        equal(await host.advance(2), 2);
        equal(host.poll(left)?.ticket, nextLeft);
        equal(host.poll(right)?.ticket, nextRight);
      } finally {
        host.restore();
      }
    },
  );
});

Deno.test("spark rejects unknown work and spawn checks its start operation and child entries", async () => {
  for (
    const body of ["@u32.div x 0", '@panic "fault"', "hidden x", "captured"]
  ) {
    await compileExpectedFailure(
      `func hidden x => return x\nconst captured = 5\nentry func nope (xs: Array U32) => return @spark #[${body} | x <- xs]\n`,
      "spark_kernel",
    );
  }
  await compileExpectedFailure(
    "entry func nope (xs: Array U32) => return @spark #[x | x <- xs, x <- xs]\n",
    "spark_generator",
  );
  await compileExpectedFailure(
    "entry func nope (xs: Array U32) => return @spark #[x | x <- xs, x < 8]\n",
    "spark_generator",
  );
  await compileExpectedFailure(
    "entry func nope (xs: List U32) => return @spark #[x | x <- xs]\n",
    "type_mismatch",
  );
  await compileExpectedFailure(
    "entry func nope (xs: Array U32) => return @spark.within 100 #[x | x <- xs]\n",
    "unknown_intrinsic",
  );
  await compileExpectedFailure(
    program.replace("entry func planner_step", "func planner_step"),
    "spawn_program",
  );
  const impostor = `func admit (packet: Array U32): U32 => return 0
entry func planner (seed: U32): U32 => return seed
entry func planner_step (pair: Array U32): U32 => return pair[0]
entry func invalid (x: U32) => return @spawn admit planner x
`;
  await compileExpectedFailure(impostor, "operation_target");
  await compileExpectedFailure(
    "entry func nope (xs: Array (Array U32)) => return @spark #[x | x <- xs]\n",
    "type_mismatch",
  );
  const wrongConfig = program.replace(
    "@spawn Start planner config",
    "@spawn Start planner 1.5",
  );
  await compileExpectedFailure(wrongConfig, "type_mismatch");
  const wrongStep = program.replace(
    "planner_step (pair: Array U32): U32",
    "planner_step (pair: Array F32): F32",
  ).replace("@u32.add pair[0] pair[1]", "@f32.add pair[0] pair[1]");
  await compileExpectedFailure(wrongStep, "type_mismatch");
});
