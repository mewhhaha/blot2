import { Blot } from "../host/blot.ts";

function assert(ok: unknown, message = "particle assertion failed"): asserts ok {
  if (!ok) throw new Error(message);
}
class Reader {
  at = 0;
  constructor(readonly bytes: Uint8Array) {}
  byte() { assert(this.at < this.bytes.length, "truncated binary"); return this.bytes[this.at++]; }
  leb() {
    let value = 0, shift = 0;
    for (let i = 0; i < 5; i++) { const next = this.byte(); value += (next & 127) * 2 ** shift; if (next < 128) return value >>> 0; shift += 7; }
    throw new Error("invalid LEB");
  }
  word() { const n = new DataView(this.bytes.buffer, this.bytes.byteOffset + this.at, 4).getUint32(0, true); this.at += 4; return n; }
  take(size: number) { assert(size <= this.bytes.length - this.at); const b = this.bytes.subarray(this.at, this.at + size); this.at += size; return b; }
}
function bodies(bytes: Uint8Array): Uint8Array[] {
  const r = new Reader(bytes); r.at = 8;
  while (r.at < bytes.length) {
    const id = r.byte(), section = new Reader(r.take(r.leb()));
    if (id !== 10) continue;
    return Array.from({ length: section.leb() }, () => section.take(section.leb()));
  }
  throw new Error("missing code section");
}
function sourceFunction(module: WebAssembly.Module): number {
  const sections = WebAssembly.Module.customSections(module, "blot.k1.certificate");
  assert(sections.length === 1);
  const r = new Reader(new Uint8Array(sections[0]));
  assert(new TextDecoder().decode(r.take(8)) === "K1CERT01");
  r.take(32 * 3 + 18 * 4 + 8);
  const count = r.word(); const source: number[] = [];
  for (let i = 0; i < count; i++) {
    const index = r.word(); r.word(); const role = r.word(); r.word();
    r.take(3 * 4 + 32);
    if (role === 2) source.push(index);
    r.take(r.word() * 4); r.take(r.word() * 8);
  }
  assert(source.length === 1, "fixture must contain exactly one source function");
  return source[0];
}
function loopCounts(body: Uint8Array): Map<number, number>[] {
  const r = new Reader(body), groups = r.leb();
  for (let i = 0; i < groups; i++) { r.leb(); r.byte(); }
  const scopes: (Map<number, number> | null)[] = [], loops: Map<number, number>[] = [];
  while (r.at < body.length) {
    const op = r.byte();
    for (const scope of scopes) if (scope) scope.set(op, (scope.get(op) ?? 0) + 1);
    if ([2, 3, 4].includes(op)) {
      r.byte(); const scope = op === 3 ? new Map<number, number>() : null;
      scopes.push(scope); if (scope) loops.push(scope);
    } else if (op === 11) scopes.pop();
    else if ([12, 13, 16, 32, 33, 34, 65].includes(op)) r.leb();
    else if (op === 17 || [40, 42, 45, 54, 56].includes(op)) { r.leb(); r.leb(); }
    else if (op === 67) r.take(4);
    else if (op === 252) { const sub = r.leb(); r.leb(); if (sub === 10) r.leb(); }
    else assert([0, 5, 15, 26, 27, 169, 179, 188, 190].includes(op) ||
      op >= 69 && op <= 79 || op >= 91 && op <= 96 || op >= 106 && op <= 118 || op >= 139 && op <= 151,
      `unrecognized opcode ${op.toString(16)}`);
  }
  return loops;
}
Deno.test("K1-04 particle baseline has one loop and exact row operations", async () => {
  const root = new URL("../", import.meta.url).pathname;
  const config = root + "build/particle-benchmark.json", output = root + "build/particle-baseline.wasm";
  await Deno.writeTextFile(config, JSON.stringify({ language: "k1", function: "project", input_maxima: [1024], output_capacity: 1024 }));
  const build = await new Deno.Command(root + "build/blot", {
    cwd: root, args: ["build", "examples/particles.blot", "--opt=off", "-o", output, "--bridge-config=" + config], stdout: "piped", stderr: "piped",
  }).output();
  assert(build.success, new TextDecoder().decode(build.stderr));
  const bytes = await Deno.readFile(output), module = await WebAssembly.compile(bytes);
  const loops = loopCounts(bodies(bytes)[sourceFunction(module)]);
  assert(loops.length === 1, "baseline must be one counted loop");
  const c = loops[0], n = (op: number) => c.get(op) ?? 0;
  assert(n(40) + n(42) + n(45) === 4, "exactly four element loads per row");
  assert(n(54) + n(56) === 2, "exactly two element stores per row");
  assert(n(148) === 2 && n(146) === 2, "two separately rounded f32 multiply/add pairs");
  assert(n(16) === 0 && n(17) === 0 && n(252) === 0, "no helpers, indirect calls, or aggregate spills in the row loop");
  const instance = await Blot.load(bytes), dt = Math.fround(0.137);
  const source = Array.from({ length: 127 }, (_, i) => ({ x: i / 13, y: -i / 17, vx: (i * 7 % 23) / 3, vy: (i * 5 % 29) / -7 }));
  const result = instance.invoke("project", { source, dt });
  assert(result.status === "Ok" && Array.isArray(result.items));
  result.items.forEach((value: unknown, i: number) => {
    const actual = value as { x: number; y: number }, row = source[i];
    assert(Object.is(actual.x, Math.fround(Math.fround(row.x) + Math.fround(Math.fround(row.vx) * dt))));
    assert(Object.is(actual.y, Math.fround(Math.fround(row.y) + Math.fround(Math.fround(row.vy) * dt))));
  });
  const tooSmall = instance.invoke("project", { source, dt }, 8);
  assert(tooSmall.status === "OutputTooSmall" && tooSmall.requiredBytes === 8 + source.length * 8);
  const empty = instance.invoke("project", { source: [], dt });
  assert(empty.status === "Ok" && Array.isArray(empty.items) && empty.items.length === 0);
});

async function particleGuest(source: string, name: string, count: number, capacity: number, telemetry = false) {
  const root = new URL("../", import.meta.url).pathname;
  const config = `build/${name}-bridge.json`, output = `build/${name}.wasm`;
  await Deno.writeTextFile(root + config, JSON.stringify({ language: "k1", function: name, input_maxima: [count], output_capacity: capacity }));
  const built = await new Deno.Command(root + "build/blot", { cwd: root, args: ["build", source, "--opt=off", "-o", output, "--bridge-config=" + config, ...(telemetry ? ["--telemetry"] : [])], stdout: "piped", stderr: "piped" }).output();
  assert(built.success, new TextDecoder().decode(built.stderr));
  return Blot.load(await Deno.readFile(root + output));
}
Deno.test("K1-04 particle empty singleton and full-capacity extents execute", async () => {
  const guest = await particleGuest("examples/particles.blot", "project", 1024, 1024);
  for (const count of [0, 1, 1024]) {
    const source = Array.from({ length: count }, (_, i) => ({ x: i, y: -i, vx: 2, vy: -3 }));
    const result = guest.invoke("project", { source, dt: 0.5 });
    assert(result.status === "Ok" && Array.isArray(result.items) && result.items.length === count);
    result.items.forEach((item: unknown, i: number) => { const row = item as { x: number; y: number }; assert(row.x === i + 1 && row.y === -i - 1.5); });
  }
});
Deno.test("K1-04 particle partial-write failure publishes no result and releases storage", async () => {
  const guest = await particleGuest("tests/runtime_particles_early.blot", "project_early", 8, 8, true);
  const good = Array.from({ length: 8 }, (_, i) => ({ x: i, y: i, vx: 2, vy: 3 }));
  for (let repeat = 0; repeat < 100; repeat++) {
    for (let failedAt = 0; failedAt <= good.length; failedAt++) {
      const source = good.map((row, i) => ({ ...row, x: i === failedAt ? -1 : row.x }));
      const before = guest.telemetry();
      assert(before !== null);
      // Negative dt fails after the final append, covering the full prefix too.
      const failure = guest.invoke("project_early", { source, dt: failedAt === good.length ? -1 : 1 });
      assert(failure.status === "LanguageError" && failure.detail === 0 && !("items" in failure));
      const after = guest.telemetry();
      assert(after !== null && after.backing_live_bytes === 0n);
      assert(after.backing_reservations - before.backing_reservations === 1n);
      assert(after.region_releases - before.region_releases === 1n);
      assert(after.source_calls - before.source_calls === 1n);
      const success = guest.invoke("project_early", { source: good, dt: 1 });
      assert(success.status === "Ok" && Array.isArray(success.items) && success.items.length === 8);
      success.items.forEach((item, i) => {
        const row = item as { x: number; y: number };
        assert(row.x === i + 2 && row.y === i + 3);
      });
    }
  }
});
Deno.test("K1-04 insufficient destination capacity returns the typed source error", async () => {
  const guest = await particleGuest("tests/runtime_particles_capacity.blot", "project_checked", 5, 4);
  const source = Array.from({ length: 5 }, (_, i) => ({ x: i, y: i, vx: 2, vy: 3 }));
  const failure = guest.invoke("project_checked", { source, dt: 1 });
  assert(failure.status === "LanguageError");
  const success = guest.invoke("project_checked", { source: source.slice(0, 4), dt: 1 });
  assert(success.status === "Ok" && Array.isArray(success.items) && success.items.length === 4);
});
Deno.test("K1-06 particle higher-order map accepts named and captured callbacks", async () => {
  for (const name of ["project_named", "project_local"]) {
    const guest = await particleGuest("examples/particles_callbacks.blot", name, 16, 16);
    const dt = Math.fround(0.137);
    for (const count of [0, 1, 16]) {
      const source = Array.from({ length: count }, (_, i) => ({ x: i / 7, y: -i / 11, vx: (i + 3) / 13, vy: -(i + 2) / 17 }));
      const result = guest.invoke(name, { source, dt });
      assert(result.status === "Ok" && Array.isArray(result.items) && result.items.length === count);
      result.items.forEach((item: unknown, i: number) => {
        const actual = item as { x: number; y: number }, row = source[i];
        const step = name === "project_named" ? 1 : dt;
        assert(Object.is(actual.x, Math.fround(Math.fround(row.x) + Math.fround(Math.fround(row.vx) * step))));
        assert(Object.is(actual.y, Math.fround(Math.fround(row.y) + Math.fround(Math.fround(row.vy) * step))));
      });
    }
  }
});
