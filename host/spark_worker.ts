import { parentPort } from "node:worker_threads";
import {
  type Guest,
  instantiateGuest,
  numericArrayCopySites,
} from "./guest.ts";

const port = parentPort!;
let guest: Guest | undefined;
let entry = "";
let identity = 0;
let prefix: Uint32Array;
let copies: Uint32Array<SharedArrayBuffer>;
port.on("message", async (data) => {
  try {
    if (data.module) {
      if (identity) throw new Error("Worker is already prepared");
      guest = await instantiateGuest(data.module);
      entry = data.entry;
      prefix = data.prefix;
      copies = data.copies;
      identity = data.identity;
      port.postMessage({ ready: true, identity });
      return;
    }
    if (!guest || !identity || data.identity !== identity) {
      throw new Error("Worker has a different preparation");
    }
    const values = guest.call(entry, data.input, {
      prefix,
      resultLength: data.resultLength,
      observeCopy: (site, bytes) => {
        Atomics.add(copies, numericArrayCopySites.indexOf(site), bytes);
      },
    });
    if (
      !(values instanceof Uint32Array || values instanceof Float32Array) ||
      !(values.buffer instanceof ArrayBuffer)
    ) throw new Error("Expected numeric spark rows");
    port.postMessage({
      identity,
      attempt: data.attempt,
      start: data.start,
      values,
    }, [
      values.buffer,
    ]);
  } catch (error) {
    port.postMessage({ error: String(error) });
  }
});
