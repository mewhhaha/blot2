// Private demonstration wrapper for bridge_wasm_fixture only. The Wasm
// instance and its exported memory stay in this closure, and results are
// decoded into new host-owned values. This is not a generated K1 host API.
const integer = value => Number.isInteger(value) && value >= 0 && value <= 0xffffffff;
export function createBridgeFixture(bytes) {
  const instance = new WebAssembly.Instance(new WebAssembly.Module(bytes));
  const {memory, invoke} = instance.exports;
  if (!(memory instanceof WebAssembly.Memory) || typeof invoke !== 'function' || memory.buffer.byteLength !== 65536) {
    throw new Error('invalid fixture module');
  }
  let poisoned = false;
  let running = false;
  return Object.freeze({
    call(values, mask, capacity) {
      if (poisoned) return {status: 'Poisoned'};
      if (running) return {status: 'Busy'};
      running = true;
      try {
      if (!Array.isArray(values) || !integer(mask) || !integer(capacity) || capacity > 96) throw new TypeError('invalid fixture input');
      // Snapshot own data properties before touching private memory. Reject
      // holes and accessors instead of invoking user getters. Proxies may run
      // traps during descriptor lookup, so running also blocks reentry.
      const length = Object.getOwnPropertyDescriptor(values, 'length');
      if (!length || !('value' in length) || !integer(length.value) || length.value > 4) throw new TypeError('invalid fixture input');
      const snapshot = [];
      for (let i = 0; i < length.value; i++) {
        const item = Object.getOwnPropertyDescriptor(values, String(i));
        if (!item || !('value' in item) || !integer(item.value)) throw new TypeError('invalid fixture input');
        snapshot.push(item.value);
      }
      const view = new DataView(memory.buffer);
      const put = (p, x) => view.setUint32(p, x, true);
      const get = p => view.getUint32(p, true);
      const count = snapshot.length, payload = 12 + 4 * count;
      // Clear the complete ingress window before encoding. Its raw bytes are
      // never returned, and no callback runs while the guest is executing.
      new Uint8Array(memory.buffer, 32768, 128).fill(0);
      put(32768, 0x4b310001); put(32772, 17); put(32780, payload);
      put(32800, mask); put(32804, count); put(32808, 12);
      snapshot.forEach((value, i) => put(32812 + 4 * i, value));
      let status;
      try { status = invoke(17, 32 + payload, capacity) >>> 0; }
      catch { poisoned = true; return {status: 'Poisoned'}; }
      const payloadBytes = get(33036), required = get(33040), items = get(33044), detail = get(33048);
      const malformed = () => { poisoned = true; return {status: 'Poisoned'}; };
      if (get(33024) !== 0x4b310001 || get(33028) !== 17 || get(33032) !== status || get(33052) !== 0 || status > 6) return malformed();
      if (status !== 0) {
        if (payloadBytes !== 0) return malformed();
        if (status === 2) {
          if (items > 4 || required !== 8 + items * 4 || required <= capacity || detail !== 0) return malformed();
          return {status: 'OutputTooSmall', required, count: items};
        }
        if (required !== 0 || items !== 0) return malformed();
        return {status: ['Ok', 'InvalidInput', 'OutputTooSmall', 'ReservationFailed', 'Busy', 'FrameLimit', 'LanguageError'][status], detail};
      }
      if (detail !== 0 || items > 4 || required !== 8 + items * 4 || required !== payloadBytes || required > capacity ||
          get(33056) !== items || get(33060) !== 8) return malformed();
      const result = new Uint32Array(items);
      for (let i = 0; i < items; i++) result[i] = get(33064 + 4 * i);
      return {status: 'Ok', values: result};
      } finally { running = false; }
    },
  });
}
