import { Worker } from "node:worker_threads";
import { rejects } from "node:assert/strict";
import { SparkCopyBudget, SparkPool } from "../../host/sparks.ts";
import { compileAndRun, equal } from "./compile_helpers.ts";

const fixture = `
entry func with_world (packet: Array U32): Array U32 => return @array.generate (packet.length - 2) (func i => return @u32.bit_xor packet[1] packet[i + 2])
entry func malformed (packet: Array U32): Array U32 => return if packet.length == 1 then #[55, 55] else packet
entry func fault (packet: Array U32): Array U32 => return if packet.length == 1 then @panic "worker trap" else packet
entry func stalled (packet: Array U32): Array U32 => return do:
  if packet.length == 1:
    for ever:
      continue
  return packet
`;

Deno.test("spark reserves preparation and both live and fallback copies before dispatch", async () => {
  await compileAndRun(fixture, async (guest, bytes) => {
    const module = await WebAssembly.compile(bytes);
    const packetBound = guest.numericPacketCapacity();
    const direct = packetBound + 40;
    const parallel = 3 * packetBound + 120;
    const settings = {
      entry: "with_world",
      width: 1,
      workers: 2,
      waitMs: 2000,
    };
    const firstSnapshot = Uint32Array.of(7, 0x0100_0001);
    const secondSnapshot = Uint32Array.of(7, 0xffff_0000);
    const input = Uint32Array.of(0, 1);
    const budget = new SparkCopyBudget(parallel + direct);
    const first = await SparkPool.open(module, {
      ...settings,
      prefix: firstSnapshot,
      copyBudget: budget,
    });
    const second = await SparkPool.open(module, {
      ...settings,
      prefix: secondSnapshot,
      copyBudget: budget,
    });
    try {
      equal(budget.reserved, 48);
      equal(first.copiedBytes.prepare, 8);
      equal(first.copiedBytes.install, 16);
      equal(second.copiedBytes.install, 16);
      firstSnapshot[1] = 0; // Preparation owns the original bits.
      budget.beginFrame();
      const pending = first.run(input);
      equal(budget.reserved, parallel);
      equal(first.copiedBytes.dispatch, 8);
      equal(first.copiedBytes.assemble, 0);
      budget.beginFrame();
      equal(budget.reserved, parallel);
      // The second worker attempt cannot fit. Its direct copy fits exactly.
      equal(String(await second.run(input)), "4294901760,4294901761");
      equal(budget.reserved, parallel + direct);
      equal(second.copiedBytes.snapshot, 0);
      equal(second.copiedBytes.guestInput, 16);
      equal(second.copiedBytes.guestOutput, 8);
      equal(String(await pending), "16777217,16777216");
      equal(first.fallbacks, 0);
      equal(first.copiedBytes.snapshot, 8);
      equal(first.copiedBytes.guestInput, 24);
      equal(first.copiedBytes.guestUnpack, 24);
      equal(first.copiedBytes.guestPack, 8);
      equal(first.copiedBytes.guestOutput, 8);
      equal(first.copiedBytes.assemble, 8);
      equal(budget.reserved, parallel + direct); // Completion earns no same-frame credit.
      budget.beginFrame();
      equal(budget.reserved, 0);
    } finally {
      await Promise.all([first.close(), second.close()]);
    }

    const limited = new SparkCopyBudget(parallel - 1);
    const below = await SparkPool.open(module, {
      ...settings,
      prefix: secondSnapshot,
      copyBudget: limited,
    });
    try {
      limited.beginFrame();
      equal(String(await below.run(input)), "4294901760,4294901761");
      equal(below.copiedBytes.dispatch, 0);
      equal(limited.reserved, direct);
    } finally {
      await below.close();
    }

    const cold = new SparkCopyBudget(23);
    const unprepared = await SparkPool.open(module, {
      ...settings,
      prefix: secondSnapshot,
      copyBudget: cold,
    });
    try {
      equal(cold.reserved, 8);
      equal(unprepared.copiedBytes.prepare, 8);
      equal(unprepared.copiedBytes.install, 0);
      await rejects(unprepared.run(input), /copy allowance/);
      equal(unprepared.copiedBytes.guestInput, 0);
    } finally {
      await unprepared.close();
    }
    await rejects(
      SparkPool.open(module, {
        ...settings,
        prefix: secondSnapshot,
        copyBudget: new SparkCopyBudget(7),
      }),
      /preparation exceeds copy allowance/,
    );
  });
});

Deno.test("spark discards malformed or obsolete replies after an in-flight retirement", async () => {
  await compileAndRun(fixture, async (guest, bytes) => {
    const module = await WebAssembly.compile(bytes);
    const parallel = 3 * (guest.numericPacketCapacity()) + 120;
    const budget = new SparkCopyBudget(2 * parallel);
    const options = { entry: "with_world", width: 1, workers: 2, waitMs: 2000 };
    const rows = Uint32Array.of(0, 1);
    const old = await SparkPool.open(module, {
      ...options,
      prefix: Uint32Array.of(7, 10),
      copyBudget: budget,
    });
    const next = await SparkPool.open(module, {
      ...options,
      prefix: Uint32Array.of(7, 20),
      copyBudget: budget,
    });
    const send = Worker.prototype.postMessage;
    let obsolete: object | undefined;
    try {
      budget.beginFrame();
      Worker.prototype.postMessage = function (data, transfer) {
        if (data.attempt && !obsolete) {
          obsolete = {
            identity: data.identity,
            attempt: data.attempt,
            start: data.start,
            values: Uint32Array.of(999),
          };
        }
        send.call(this, data, transfer);
      };
      const pending = old.run(rows);
      const stopped = old.retireWorkers();
      budget.beginFrame();
      equal(budget.reserved, parallel);
      equal(String(await pending), "10,11");
      equal(old.fallbacks, 1);
      await stopped;
      equal(budget.reserved, parallel);
      budget.beginFrame();
      equal(budget.reserved, 0);
      equal(Boolean(obsolete), true);
      Worker.prototype.postMessage = function (data, transfer) {
        if (data.attempt) {
          const message = data.start === 0 ? obsolete : null;
          queueMicrotask(() => this.emit("message", message));
        }
        send.call(this, data, transfer);
      };
      const result = await next.run(rows);
      equal(String(result), "20,21");
      equal(next.fallbacks, 1);
      equal(next.copiedBytes.assemble, 0);
      equal(budget.reserved, parallel);
    } finally {
      Worker.prototype.postMessage = send;
      await Promise.all([old.close(), next.close()]);
    }
  });
});

Deno.test("spark pools keep shared worker slots and linear memory reserved until exit", async () => {
  await compileAndRun(fixture, async (guest, bytes) => {
    const module = await WebAssembly.compile(bytes);
    const memory = guest.memoryBytes();
    const ceiling = 8 * guest.numericPacketCapacity();
    const budget = new SparkCopyBudget(ceiling, {
      workers: 2,
      linearBytes: 2 * memory,
    });
    const options = {
      entry: "with_world",
      width: 1,
      workers: 2,
      prefix: Uint32Array.of(7, 20),
      copyBudget: budget,
    };
    const first = await SparkPool.open(module, options);
    const saturated = await SparkPool.open(module, options);
    const rows = Uint32Array.of(0, 1);
    try {
      equal(budget.workersInUse, 2);
      equal(budget.workerLinearBytes, 2 * memory);
      equal(saturated.copiedBytes.install, 0);
      equal(String(await saturated.run(rows)), "20,21");
      const pending = first.run(rows);
      const retired = first.retireWorkers();
      equal(budget.workersInUse, 2);
      equal(budget.workerLinearBytes, 2 * memory);
      equal(String(await pending), "20,21");
      await retired;
      equal(budget.workersInUse, 0);
      equal(budget.workerLinearBytes, 0);
      const replacement = await SparkPool.open(module, options);
      equal(replacement.copiedBytes.install, 16);
      await replacement.close();
    } finally {
      await Promise.all([first.close(), saturated.close()]);
    }
    const tooLittle = new SparkCopyBudget(ceiling, {
      workers: 2,
      linearBytes: 2 * memory - 1,
    });
    const directOnly = await SparkPool.open(module, {
      ...options,
      copyBudget: tooLittle,
    });
    try {
      equal(tooLittle.workersInUse, 0);
      equal(directOnly.copiedBytes.install, 0);
      equal(String(await directOnly.run(rows)), "20,21");
    } finally {
      await directOnly.close();
    }
  });
});

Deno.test("spark stages replies by their input index even when completion is reversed", async () => {
  await compileAndRun(fixture, async (_guest, bytes) => {
    const module = await WebAssembly.compile(bytes);
    for (const workers of [1, 2, 4]) {
      const pool = await SparkPool.open(module, {
        entry: "with_world",
        width: 1,
        prefix: Uint32Array.of(7, 0x0100_0000),
        workers,
        waitMs: 2000,
      });
      const deliver = Worker.prototype.emit;
      const staged: { worker: Worker; reply: { start: number } }[] = [];
      try {
        equal((await pool.run(new Uint32Array())).length, 0);
        Worker.prototype.emit = function (
          event: string | symbol,
          ...args: unknown[]
        ) {
          const reply = args[0] as
            | { attempt?: number; start: number }
            | undefined;
          if (event !== "message" || !reply?.attempt) {
            return deliver.call(this, event, ...args);
          }
          staged.push({ worker: this, reply });
          if (staged.length === workers) {
            for (
              const part of staged.toSorted((a, b) =>
                b.reply.start - a.reply.start
              )
            ) {
              deliver.call(part.worker, "message", part.reply);
            }
          }
          return true;
        };
        const rows = Uint32Array.of(5, 4, 3, 2, 1, 0, 0xffffffff);
        equal(String(await pool.run(rows)), String(pool.direct(rows)));
        equal(staged.length, workers);
        equal(pool.fallbacks, 0);
      } finally {
        Worker.prototype.emit = deliver;
        await pool.close();
      }
    }
  });
});

Deno.test("spark recovery handles real Wasm traps, oversized replies and a stuck worker", async () => {
  await compileAndRun(fixture, async (guest, bytes) => {
    const module = await WebAssembly.compile(bytes);
    const parallel = 3 * guest.numericPacketCapacity() + 72;
    for (const entry of ["fault", "malformed", "stalled"]) {
      const budget = new SparkCopyBudget(parallel);
      let waitMs = 1000;
      if (entry === "stalled") waitMs = 50;
      const pool = await SparkPool.open(module, {
        entry,
        width: 1,
        workers: 2,
        waitMs,
        copyBudget: budget,
      });
      try {
        const rows = Uint32Array.of(0xff00_0000, 1);
        const started = performance.now();
        equal(String(await pool.run(rows)), "4278190080,1");
        equal(performance.now() - started < 3000, true);
        equal(budget.reserved, parallel);
        equal(pool.fallbacks, 1);
        await pool.retireWorkers();
        equal(pool.copiedBytes.guestOutput, 8);
        if (entry === "malformed") {
          equal(pool.copiedBytes.guestPack >= 16, true);
        } else equal(pool.copiedBytes.guestPack, 8);
        equal(pool.copiedBytes.assemble, 0);
        budget.beginFrame();
        equal(budget.reserved, 0);
      } finally {
        await pool.close();
      }
    }
  });
});
