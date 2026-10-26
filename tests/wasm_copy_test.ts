function assert(
  ok: unknown,
  message = "word-copy assertion failed",
): asserts ok {
  if (!ok) throw new Error(message);
}
class Reader {
  at = 0;
  constructor(readonly bytes: Uint8Array) {}
  byte() {
    return this.bytes[this.at++];
  }
  leb() {
    let value = 0, shift = 0;
    for (let i = 0; i < 5; i++) {
      const byte = this.byte();
      value += (byte & 127) * 2 ** shift;
      if (byte < 128) return value;
      shift += 7;
    }
    throw new Error("invalid LEB");
  }
  word() {
    const n = new DataView(
      this.bytes.buffer,
      this.bytes.byteOffset + this.at,
      4,
    ).getUint32(0, true);
    this.at += 4;
    return n;
  }
  take(n: number) {
    const bytes = this.bytes.subarray(this.at, this.at + n);
    this.at += n;
    return bytes;
  }
}
function codeBodies(bytes: Uint8Array): Uint8Array[] {
  const r = new Reader(bytes);
  r.at = 8;
  while (r.at < bytes.length) {
    const id = r.byte(), section = new Reader(r.take(r.leb()));
    if (id === 10) {
      return Array.from(
        { length: section.leb() },
        () => section.take(section.leb()),
      );
    }
  }
  throw new Error("missing code section");
}
function opcodes(body: Uint8Array): number[] {
  const r = new Reader(body), ops = [];
  for (let i = 0, count = r.leb(); i < count; i++) {
    r.leb();
    r.byte();
  }
  while (r.at < body.length) {
    const op = r.byte();
    ops.push(op);
    if ([2, 3, 4].includes(op)) r.byte();
    else if ([12, 13, 16, 32, 33, 34, 65].includes(op)) r.leb();
    else if (op === 17 || [40, 42, 45, 54, 56].includes(op)) {
      r.leb();
      r.leb();
    } else if (op === 67) r.take(4);
    else if (op === 252) {
      const sub = r.leb();
      r.leb();
      if (sub === 10) r.leb();
    }
  }
  return ops;
}
async function copyModule() {
  return WebAssembly.compile(
    await Deno.readFile("/tmp/blot-k1-word-copy.wasm"),
  );
}
Deno.test("M07/M10 word-copy guard matches bulk memmove for zero other sizes and overlaps", async () => {
  const module = await copyModule();
  for (const size of [0, 1, 2, 3, 4, 5, 8, 12, 64, 256]) {
    for (const delta of [0, 1, -1, 4, -4, 512]) {
      const ex = (await WebAssembly.instantiate(module)).exports;
      const bytes = new Uint8Array((ex.memory as WebAssembly.Memory).buffer);
      for (let i = 0; i < bytes.length; i++) bytes[i] = (i * 17 + 23) & 255;
      const source = 1024,
        destination = source + delta,
        expected = bytes.slice();
      expected.copyWithin(destination, source, source + size);
      (ex.copy as (dst: number, src: number, n: number) => void)(
        destination,
        source,
        size,
      );
      assert(
        bytes.every((byte, i) => byte === expected[i]),
        `copy size${size} delta${delta}`,
      );
    }
  }
  for (
    const bits of [
      0,
      0x80000000,
      0x7fa12345,
      0xffa12345,
      0x7fffffff,
      0xffffffff,
    ]
  ) {
    for (const delta of [0, 1, -1, 4, 8]) {
      const ex = (await WebAssembly.instantiate(module)).exports;
      const bytes = new Uint8Array((ex.memory as WebAssembly.Memory).buffer);
      const data = new DataView(bytes.buffer);
      data.setUint32(1024, bits, true);
      const expected = bytes.slice();
      expected.copyWithin(1024 + delta, 1024, 1028);
      (ex.word as (dst: number, src: number) => void)(1024 + delta, 1024);
      assert(
        bytes.every((byte, i) => byte === expected[i]),
        `fixed word payload${bits.toString(16)} delta${delta}`,
      );
    }
  }
});
Deno.test("M07/M10 word-copy traps never publish a partial word and zero bounds stay unchanged", async () => {
  const module = await copyModule();
  for (const name of ["copy", "bulk"]) {
    for (
      const fault of [
        "source",
        "destination",
        "zero-source",
        "zero-destination",
      ]
    ) {
      const ex = (await WebAssembly.instantiate(module)).exports;
      const bytes = new Uint8Array((ex.memory as WebAssembly.Memory).buffer);
      bytes.fill(91);
      const end = bytes.length,
        zero = fault.startsWith("zero"),
        source = fault.endsWith("source") ? end + (zero ? 1 : -3) : 1024;
      const destination = fault.endsWith("destination")
        ? end + (zero ? 1 : -3)
        : 2048;
      const before = bytes.slice();
      let trapped = false;
      try {
        (ex[name] as (dst: number, src: number, n: number) => void)(
          destination,
          source,
          zero ? 0 : 4,
        );
      } catch (error) {
        trapped = error instanceof WebAssembly.RuntimeError;
      }
      assert(
        trapped && bytes.every((byte, i) => byte === before[i]),
        `${name}/${fault} changed memory before trap`,
      );
      // Observe memory only; never resume the trapped instance.
    }
    const ex = (await WebAssembly.instantiate(module)).exports,
      end = (ex.memory as WebAssembly.Memory).buffer.byteLength;
    (ex[name] as (dst: number, src: number, n: number) => void)(end, end, 0);
  }
});
function counter(ex: WebAssembly.Exports, id: number): bigint {
  const read = ex["blot.telemetry"] as (word: number) => number;
  return BigInt(read(id * 2) >>> 0) | BigInt(read(id * 2 + 1) >>> 0) << 32n;
}
Deno.test("C07/M10 typed fixed and generic copies preserve scalar bits fallback and byte telemetry", async () => {
  const root = new URL("../", import.meta.url).pathname;
  for (const telemetry of [false, true]) {
    const output = root + `build/runtime-word-copy-${telemetry}.wasm`;
    const built = await new Deno.Command(root + "build/blot", {
      cwd: root,
      args: [
        "build",
        "tests/runtime_word_copy.blot",
        "--opt=off",
        "-o",
        output,
        ...(telemetry ? ["--telemetry"] : []),
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(built.success, new TextDecoder().decode(built.stderr));
    const bytes = await Deno.readFile(output),
      module = await WebAssembly.compile(bytes);
    const instance = await WebAssembly.instantiate(module),
      ex = instance.exports;
    const invoke = (
      name: string,
      value: number,
      initialized: number,
      copied: number,
    ) => {
      const before = telemetry
        ? [counter(ex, 9), counter(ex, 10), counter(ex, 11)]
        : [];
      const answer = (ex[name] as (n: number) => number)(value);
      if (telemetry) {
        assert(
          counter(ex, 9) - before[0] === BigInt(initialized),
          `${name} initialized bytes`,
        );
        assert(
          counter(ex, 10) - before[1] === BigInt(copied),
          `${name} copied bytes`,
        );
        assert(counter(ex, 11) - before[2] === 2n, `${name} source calls`);
      }
      return answer;
    };
    for (const n of [0, 1, 40, 0x7fffffff, 0xffffffff]) {
      for (
        const [name, initialized, copied] of [["run", 8, 4], ["pair", 16, 8], [
          "fixed",
          12,
          4,
        ], ["fixed_eight", 24, 8]] as const
      ) {
        assert(
          invoke(name, n, initialized, copied) >>> 0 === n,
          `${name}/${n}`,
        );
      }
    }
    for (const n of [0, -0, 1.25, -1.25, Infinity, -Infinity, NaN]) {
      assert(
        Object.is(invoke("run_float", n, 8, 4), Math.fround(n)),
        "generic F32 bit transfer",
      );
    }
    assert(invoke("unit", 0, 0, 0) === 7, "zero-sized generic transfer");
    if (!telemetry) {
      const certificate = new Reader(
        new Uint8Array(
          WebAssembly.Module.customSections(module, "blot.k1.certificate")[0],
        ),
      );
      certificate.take(8 + 96 + 72 + 8);
      const direct = new Map<number, number[]>();
      for (let i = 0, count = certificate.word(); i < count; i++) {
        const index = certificate.word();
        certificate.take(6 * 4 + 32);
        const calls = Array.from(
          { length: certificate.word() },
          () => certificate.word(),
        );
        certificate.take(certificate.word() * 8);
        direct.set(index, calls);
      }
      // Export wrappers and their source entrypoints each make one direct call.
      const exports = WebAssembly.Module.exports(module).filter((row) =>
        row.kind === "function"
      ).map((row) => row.name);
      const raw = new Reader(bytes);
      raw.at = 8;
      const indices = new Map<string, number>();
      while (raw.at < bytes.length) {
        const id = raw.byte(), section = new Reader(raw.take(raw.leb()));
        if (id !== 7) continue;
        for (let i = 0, count = section.leb(); i < count; i++) {
          const name = new TextDecoder().decode(section.take(section.leb())),
            kind = section.byte(),
            index = section.leb();
          if (kind === 0) indices.set(name, index);
        }
      }
      const bodies = codeBodies(bytes),
        target = (name: string) => {
          assert(exports.includes(name));
          const entry = direct.get(indices.get(name)!)!;
          assert(entry.length === 1);
          const target = direct.get(entry[0])!;
          assert(target.length === 1);
          return opcodes(bodies[target[0]]);
        };
      const generic = target("run"),
        fixed = target("fixed"),
        other = target("fixed_eight");
      assert(
        generic.filter((op) => op === 252).length === 1 &&
          generic.filter((op) => op === 54).length === 1 && generic.includes(4),
        "dynamic word guard retains one bulk fallback",
      );
      assert(
        !fixed.includes(252) && fixed.filter((op) => op === 4).length === 1 &&
          fixed.includes(40) &&
          fixed.includes(54),
        "fixed four-byte copy is direct with no dispatch",
      );
      assert(
        other.filter((op) => op === 252).length === 1,
        "known eight-byte copy remains bulk",
      );
    }
  }
});
