import { strict as assert } from "node:assert";

function leb(value: number): number[] {
  const bytes = [];
  do {
    const next = value & 127;
    value >>>= 7;
    bytes.push(next | (value ? 128 : 0));
  } while (value);
  return bytes;
}

// Add telemetry exports only. Function bodies, data and ownership metadata
// retain their original bytes. The four-global pattern is Arena's declared
// heap/base/static_end/allocated prefix in src/backend/wasm.zig.
function telemetry(bytes: Uint8Array<ArrayBuffer>) {
  let cursor = 8, arena: number | undefined, memories = 0;
  const read = () => {
    let value = 0, shift = 0, byte: number;
    do {
      assert(cursor < bytes.length && shift < 35);
      byte = bytes[cursor++];
      value += (byte & 127) * 2 ** shift;
      shift += 7;
    } while (byte & 128);
    return value >>> 0;
  };
  const parts: Uint8Array<ArrayBuffer>[] = [bytes.slice(0, 8)];
  while (cursor < bytes.length) {
    const start = cursor, section = bytes[cursor++], length = read();
    const payload = cursor, end = cursor + length;
    assert(end <= bytes.length);
    if (section === 5) memories = read();
    if (section === 6) {
      const globals: { type: number; mutable: number; value: number }[] = [];
      for (let count = read(); count > 0; count--) {
        const type = bytes[cursor++], mutable = bytes[cursor++];
        const opcode = bytes[cursor++];
        let value = 0;
        if (opcode === 0x41) value = read();
        else if (opcode === 0x43) cursor += 4;
        else throw new Error(`Unsupported global initializer ${opcode}`);
        assert.equal(bytes[cursor++], 0x0b);
        globals.push({ type, mutable, value });
      }
      const candidates = globals.flatMap((g, i) =>
        g.type === 0x7f && g.mutable === 1 && g.value > 0 &&
          globals[i + 1]?.type === 0x7f &&
          globals[i + 1]?.mutable === 1 &&
          globals[i + 1]?.value === g.value &&
          globals[i + 2]?.type === 0x7f &&
          globals[i + 2]?.mutable === 0 &&
          globals[i + 2]?.value === g.value &&
          globals[i + 3]?.type === 0x7f &&
          globals[i + 3]?.mutable === 1 &&
          globals[i + 3]?.value === 0
          ? [i]
          : []
      );
      assert.equal(candidates.length, memories ? 1 : 0);
      arena = candidates[0];
    }
    if (section === 7 && arena !== undefined) {
      cursor = payload;
      const count = read(), entries = [...bytes.slice(cursor, end)];
      for (
        const [name, kind, index] of [
          ["qual:heap", 3, arena],
          ["qual:allocated", 3, arena + 3],
          ["qual:memory", 2, 0],
        ] as const
      ) {
        const encoded = new TextEncoder().encode(name);
        entries.push(...leb(encoded.length), ...encoded, kind, ...leb(index));
      }
      const next = Uint8Array.from([...leb(count + 3), ...entries]);
      parts.push(Uint8Array.from([7, ...leb(next.length)]), next);
    } else parts.push(bytes.slice(start, end));
    cursor = end;
  }
  assert(memories === 0 || memories === 1 && arena !== undefined);
  const observed = new Uint8Array(
    parts.reduce((sum, part) => sum + part.length, 0),
  );
  let offset = 0;
  for (const part of parts) {
    observed.set(part, offset);
    offset += part.length;
  }
  assert(WebAssembly.validate(observed));
  return observed;
}

type Call = readonly [
  name: string,
  argument: number,
  expected: number | "trap",
];

/** Arena traffic includes recycled blocks and rounds each allocation to its
 * size class; it is not a requested-payload-byte or live-byte counter. */
export function observeGuestAllocations(
  bytes: Uint8Array<ArrayBuffer>,
  calls: readonly Call[],
  options: {
    host?: (module: string, name: string, args: readonly number[]) => number;
  } = {},
) {
  const original = new WebAssembly.Module(bytes);
  const observedModule = new WebAssembly.Module(telemetry(bytes));
  const hasArena = WebAssembly.Module.exports(observedModule).some((entry) =>
    entry.name === "qual:memory"
  );
  if (hasArena) {
    const exports = new Map(
      WebAssembly.Module.exports(original).map((
        entry,
      ) => [entry.name, entry.kind]),
    );
    for (const name of ["blot:ownership_enter", "blot:ownership_leave"]) {
      assert.equal(exports.get(name), "function");
    }
    for (const name of ["blot:rc_roots", "blot:rc_leases"]) {
      assert.equal(exports.get(name), "global");
    }
    if (options.host) assert.equal(exports.get("blot:rc_host_refs"), "global");
    assert.deepEqual(
      [
        ...new Uint8Array(
          WebAssembly.Module.customSections(original, "blot:ownership")[0],
        ),
      ],
      [2, 2, 0],
    );
  }
  const imports: WebAssembly.Imports = {};
  for (const imported of WebAssembly.Module.imports(original)) {
    assert.equal(imported.kind, "function");
    (imports[imported.module] ??= {})[imported.name] = (...args: number[]) => {
      if (options.host) {
        return options.host(imported.module, imported.name, args);
      }
      throw new Error("A pure allocation probe invoked a host capability");
    };
  }
  const invoke = (exports: WebAssembly.Exports) => {
    for (const [name, argument, expected] of calls) {
      (exports["blot:ownership_enter"] as CallableFunction | undefined)?.();
      try {
        const run = () => (exports[name] as CallableFunction)(argument);
        if (expected === "trap") assert.throws(run, WebAssembly.RuntimeError);
        // Callers supply the raw Wasm result (signed i32 for U32).
        else assert.equal(run(), expected);
      } finally {
        (exports["blot:ownership_leave"] as CallableFunction | undefined)?.();
      }
      for (
        const name of ["blot:rc_roots", "blot:rc_leases", "blot:rc_host_refs"]
      ) {
        const count = exports[name] as WebAssembly.Global | undefined;
        if (count) assert.equal(count.value, 0);
      }
    }
  };
  invoke(new WebAssembly.Instance(original, imports).exports);
  const observed = new WebAssembly.Instance(
    observedModule,
    imports,
  ).exports;
  const global = (name: string) =>
    Number((observed[name] as WebAssembly.Global | undefined)?.value ?? 0) >>>
    0;
  const memory = () =>
    (observed["qual:memory"] as WebAssembly.Memory | undefined)?.buffer
      .byteLength ?? 0;
  for (let warm = 0; warm < 3; warm++) invoke(observed);
  const names = [
    "qual:allocated",
    "blot:rc_retains",
    "blot:rc_releases",
    "blot:rc_destroyed",
  ];
  const before = names.map(global), committed = memory();
  for (let repeat = 0; repeat < 100; repeat++) invoke(observed);
  assert.equal(memory(), committed);
  return {
    calls: calls.length * 100,
    traps: calls.filter(([, , expected]) => expected === "trap").length * 100,
    committed_bytes: committed,
    arena_high_water: global("qual:heap"),
    rounded_allocation_bytes: (global(names[0]) - before[0]) >>> 0,
    retains: (global(names[1]) - before[1]) >>> 0,
    releases: (global(names[2]) - before[2]) >>> 0,
    destroyed: (global(names[3]) - before[3]) >>> 0,
  };
}
