// The same entry runs in a headless page and in each isolated module Worker.
import { instantiateGuest } from "../../host/guest.ts";
import { selectFour } from "./route_result.js";

const seed = 11;
const width = 392;
const prefix = Uint32Array.of(seed);
const queries = Uint32Array.of(0, 1, 2, 3);

function rows(guest, part) {
  const packet = new Uint32Array(part.length + 1);
  packet.set(prefix);
  packet.set(part, 1);
  return guest.call("routes", packet);
}

if (typeof document === "undefined") {
  let guest;
  self.onmessage = async ({ data }) => {
    try {
      if (data.module) {
        guest = await instantiateGuest(data.module);
        self.postMessage({ memory: guest.memoryBytes() });
      } else if (data.load) {
        // Simulate other callers doing useful work on this CPU.
        self.postMessage({ started: true });
        while (true) guest.call("serial_shared", seed);
      } else {
        const values = rows(guest, data.part);
        self.postMessage({ values, memory: guest.memoryBytes() }, { transfer: [values.buffer] });
      }
    } catch (error) {
      self.postMessage({ error: String(error) });
    }
  };
} else {
  measure().then(
    (result) => post({ result }),
    (error) => post({ error: String(error), stack: error.stack }),
  );
}

async function post(value) {
  await fetch("/result", { method: "POST", body: JSON.stringify(value) });
}

function message(worker, value, transfer = []) {
  return new Promise((resolve, reject) => {
    worker.onerror = (e) => reject(new Error(e.message));
    worker.onmessage = ({ data }) => {
      if (data.error) reject(new Error(data.error));
      else resolve(data);
    };
    worker.postMessage(value, { transfer });
  });
}

async function workerSet(module, n) {
  const workers = Array.from({ length: n }, () => new Worker(import.meta.url, { type: "module" }));
  try {
    const ready = await Promise.all(workers.map((w) => message(w, { module })));
    return { workers, memory: ready.reduce((sum, x) => sum + x.memory, 0) };
  } catch (error) {
    workers.forEach((worker) => worker.terminate());
    throw error;
  }
}

function equalBits(a, b) {
  const aa = new Uint32Array(a.buffer, a.byteOffset, a.length);
  const bb = new Uint32Array(b.buffer, b.byteOffset, b.length);
  if (aa.length !== bb.length || !aa.every((v, i) => v === bb[i])) throw Error("route results differ");
}

async function measure() {
  const raw = await (await fetch("/routes.wasm")).arrayBuffer();
  const start = performance.now();
  const module = await WebAssembly.compile(raw);
  const compiled = performance.now();
  const game = await instantiateGuest(module);
  const installed = performance.now();
  const expected = game.call("serial_shared", seed);
  const cold = performance.now() - installed;
  equalBits(selectFour(rows(game, queries)), expected);
  const result = { browser: navigator.userAgent, cores: navigator.hardwareConcurrency,
    compileMs: compiled - start, instantiateMs: installed - compiled, coldGuestMs: cold, runs: [] };
  for (const contention of [0, 2]) {
    const load = await workerSet(module, contention);
    try {
      await Promise.all(load.workers.map((w) => message(w, { load: true })));
      for (const count of [1, 2, 4, 8]) {
        const init = performance.now();
        const pool = await workerSet(module, count);
        const setupMs = performance.now() - init;
        const samples = [];
        const coldMs = {};
        const workerBytes = Array(count).fill(0);
        try {
          let lastFrame;
          let lastSample;
          // The four real queries impose a four-shard limit even on an eight-worker pool.
          const active = Math.min(queries.length, count);
          for (let i = -2; i < 101; i++) {
            const modes = ["serial_shared", "batched_rows", "workers"];
            for (let k = 0; k < modes.length; k++) {
              const mode = modes[(k + i + 3) % 3];
              const frame = await new Promise(requestAnimationFrame);
              if (lastSample) lastSample.frameIntervalMs = frame - lastFrame;
              lastSample = undefined;
              lastFrame = frame;
              const begin = performance.now();
              let value;
              let shardMs = 0;
              let joinMs = 0;
              let applyMs = 0;
              if (mode === "serial_shared") {
                value = game.call(mode, seed);
              } else if (mode === "batched_rows") {
                value = selectFour(rows(game, queries));
              } else {
                const parts = [];
                for (let at = 0; at < active; at++) {
                  const part = queries.slice(Math.floor(at * 4 / active), Math.floor((at + 1) * 4 / active));
                  parts.push(message(pool.workers[at], { part }, [part.buffer]));
                }
                const sent = performance.now();
                const replies = await Promise.all(parts);
                const returned = performance.now();
                const joined = new Float32Array(4 * width);
                let pos = 0;
                for (const [index, reply] of replies.entries()) {
                  workerBytes[index] = reply.memory;
                  joined.set(reply.values, pos);
                  pos += reply.values.length;
                }
                if (pos !== joined.length) throw Error("incomplete route rows");
                value = selectFour(joined);
                shardMs = sent - begin;
                joinMs = returned - sent;
                applyMs = performance.now() - returned;
              }
              const total = performance.now() - begin;
              equalBits(value, expected);
              if (i === -2) coldMs[mode] = total;
              if (i >= 0) {
                lastSample = { mode, workMs: total, frameIntervalMs: 0, shardMs, joinMs, applyMs };
                samples.push(lastSample);
              }
            }
          }
          lastSample.frameIntervalMs = (await new Promise(requestAnimationFrame)) - lastFrame;
          result.runs.push({ contention, count, active, setupMs, coldMs, workerBytes, mainBytes: game.memoryBytes(),
            workerInitialBytes: pool.memory, loadWorkerInitialBytes: load.memory, samples });
        } finally {
          pool.workers.forEach((w) => w.terminate());
        }
      }
    } finally {
      load.workers.forEach((w) => w.terminate());
    }
  }
  game.dispose();
  return result;
}
