import { assert, sessionCase } from "./session_harness.ts";
import { Blot } from "../host/blot.ts";

Deno.test("REV-02 interface, origins and namespace edits preserve justified cutoffs", () =>
  sessionCase(async (s) => {
    const source = (depth: number, extra = "") =>
      `${extra}pub let leaf: U32 -> U32 ! {} resources {depth:${depth},frame:0} = fn x => return U32.wrapping_add(x,2)\npub let run: U32 -> U32 ! {} resources {depth:3,frame:0} = fn x => return leaf(x)\n`;
    await Deno.writeTextFile(s.input, source(1));
    assert((await s.request()).ok);
    const unchanged = await s.request();
    assert(unchanged.ok && unchanged.reused_bodies === 2);
    assert(
      Number(unchanged.cache_admission_visits) > 0 &&
        Number(unchanged.dependency_visits) > 0,
    );
    assert(
      unchanged.dependency_invalidations === 0 && unchanged.cache_hits === 2,
    );
    for (
      const clock of ["cache_admit_ns", "cache_encode_ns", "publication_ns"]
    ) {
      assert(
        Number.isSafeInteger(unchanged[clock]) && Number(unchanged[clock]) >= 0,
      );
    }
    await Deno.writeTextFile(s.input, source(1, "// new source origins\n\n"));
    const moved = await s.request();
    assert(moved.ok && moved.reused_bodies === 2);
    await Deno.writeTextFile(s.input, source(2));
    const contract = await s.request();
    assert(
      contract.ok && contract.completed_bodies === 2 &&
        contract.reused_bodies === 0,
    );
    assert(Number(contract.dependency_invalidations) > 0);
    assert(await s.execute() === 42 && await s.cold() === 42);
    await Deno.writeTextFile(
      s.input,
      source(2) +
        "let unused: Unit -> Unit ! {} resources {depth:1,frame:0} = fn () => return ()\n",
    );
    const namespace = await s.request();
    assert(namespace.ok && namespace.reused_bodies === 0);
    assert(await s.execute() === await s.cold());
  }));

Deno.test("REV-02 import rebinding and imported body/interface changes match cold builds", () =>
  sessionCase(async (s) => {
    const module = (n: number, depth = 1) =>
      `pub let leaf: U32 -> U32 ! {} resources {depth:${depth},frame:0} = fn x => return U32.wrapping_add(x,${n})\n`;
    const entry = (path: string) =>
      `import "./${path}.blot" as lib\npub let run: U32 -> U32 ! {} resources {depth:3,frame:0} = fn x => return lib.leaf(x)\n`;
    await Deno.writeTextFile(`${s.dir}/a.blot`, module(1));
    await Deno.writeTextFile(`${s.dir}/b.blot`, module(2));
    await Deno.writeTextFile(s.input, entry("a"));
    assert((await s.request()).ok);
    assert(await s.execute() === 41);
    await Deno.writeTextFile(`${s.dir}/a.blot`, module(3));
    const body = await s.request();
    assert(body.ok && body.reused_bodies === 1);
    assert(await s.execute() === 43);
    await Deno.writeTextFile(`${s.dir}/a.blot`, module(3, 2));
    const contract = await s.request();
    assert(contract.ok && contract.reused_bodies === 0);
    await Deno.writeTextFile(s.input, entry("b"));
    assert((await s.request()).ok);
    assert(await s.execute() === 42 && await s.cold() === 42);
  }));

Deno.test("REV-02 required static transitive bodies and captured values invalidate old results", () =>
  sessionCase(async (s) => {
    const source = (n: number) =>
      `let leaf: Unit -> U32 ! {} resources {depth:1,frame:0} = fn () => return ${n}\nlet middle: Unit -> U32 ! {} resources {depth:2,frame:0} = fn () => return leaf()\nstatic let answer = middle()\npub let run: Unit -> U32 ! {} resources {depth:1,frame:0} = fn () => return answer\n`;
    await Deno.writeTextFile(s.input, source(41));
    assert((await s.request()).ok);
    assert(await s.execute() === 41);
    await Deno.writeTextFile(s.input, source(42));
    assert((await s.request()).ok);
    assert(await s.execute() === 42 && await s.cold() === 42);
    const closure = (extra: boolean) =>
      `pub let run: U32 -> U32 ! {} resources {depth:2,frame:1024} = fn seed => do:\n  let other = 2\n  let add = fn (x: U32) => return U32.wrapping_add(x,${
        extra ? "U32.wrapping_add(seed,other)" : "seed"
      })\n  return add(0)\n`;
    await Deno.writeTextFile(s.input, closure(false));
    assert((await s.request()).ok);
    assert(await s.execute() === 40);
    await Deno.writeTextFile(s.input, closure(true));
    assert((await s.request()).ok);
    assert(await s.execute() === 42 && await s.cold() === 42);
  }));

Deno.test("REV-01 publication failure and bounded malformed requests retain the prior revision", () =>
  sessionCase(async (s) => {
    await Deno.writeTextFile(
      s.input,
      "pub let run: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => return x\n",
    );
    const first = await s.request();
    assert(first.ok);
    const stable = await Deno.readFile(s.output);
    const bad = await s.request({ output: `${s.dir}/missing/out.wasm` });
    assert(!bad.ok && bad.revision === first.revision);
    assert((await Deno.readFile(s.output)).every((v, i) => v === stable[i]));
    assert(!(await s.raw("x".repeat(65537))).ok);
    assert(!(await s.raw("[".repeat(20000) + "]".repeat(20000))).ok);
    assert(!(await s.raw("{broken")).ok);
    const recovered = await s.request();
    assert(
      recovered.ok && recovered.reused_bodies === 1 && recovered.revision === 2,
    );
    assert(await s.execute() === 40);
  }));

Deno.test("REV-02 changed ABI bridge geometry rebuilds wrappers around reusable source", () =>
  sessionCase(async (s) => {
    await Deno.copyFile("examples/bridge_identity.blot", s.input);
    const bridge = `${s.dir}/bridge.json`;
    const config = JSON.parse(
      await Deno.readTextFile("examples/bridge_identity.json"),
    );
    await Deno.writeTextFile(bridge, JSON.stringify(config));
    assert((await s.request({ bridge_config: bridge })).ok);
    const first = await Blot.load(await Deno.readFile(s.output));
    assert(first.invoke("copy_identity", { src: [1, 2, 3] }).status === "Ok");
    config.input_maxima = [2];
    config.output_capacity = 2;
    await Deno.writeTextFile(bridge, JSON.stringify(config));
    assert((await s.request({ bridge_config: bridge })).ok);
    const second = await Blot.load(await Deno.readFile(s.output));
    assert(
      second.invoke("copy_identity", { src: [1, 2, 3] }).status ===
        "InvalidInput",
    );
    const result = second.invoke("copy_identity", { src: [7, 8] });
    assert(
      result.status === "Ok" && Array.isArray(result.items) &&
        result.items.join() === "7,8",
    );
  }));
