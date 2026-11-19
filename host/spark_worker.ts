/// <reference lib="webworker" />
import { type Guest, instantiateGuest } from "./guest.ts";

let guest: Guest | undefined;
let entry = "";
self.onmessage = async ({ data }) => {
  try {
    if (data.module) {
      guest = await instantiateGuest(data.module);
      entry = data.entry;
      self.postMessage({ ready: true });
      return;
    }
    const values = guest!.call(entry, data.input);
    if (!(values instanceof Uint32Array || values instanceof Float32Array)) {
      throw new Error("Expected numeric spark rows");
    }
    self.postMessage({ attempt: data.attempt, start: data.start, values }, {
      transfer: [values.buffer],
    });
  } catch (error) {
    self.postMessage({ error: String(error) });
  }
};
