import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRuntime } from "../../host/runtime.ts";
import { copyPrivateBytes, instantiateGuest } from "../../host/guest.ts";

const compilerExecutable = Deno.args[0] ??
  fileURLToPath(
    new URL("../../compiler-goose/build/blotc-goose", import.meta.url),
  );
const stdRoot = fileURLToPath(new URL("../../std", import.meta.url));
const preludePath = join(stdRoot, "prelude.blot");

async function compileWasm(source: string): Promise<Uint8Array<ArrayBuffer>> {
  const dir = await Deno.makeTempDir({ prefix: "blot-rt-coord-" });
  try {
    const entry = join(dir, "main.blot");
    const out = join(dir, "main.wasm");
    await Deno.writeTextFile(entry, source);
    const res = await new Deno.Command(compilerExecutable, {
      args: [
        "build-project",
        entry,
        out,
        "--std-root",
        stdRoot,
        "--prelude",
        preludePath,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    if (!res.success) {
      throw new Error(
        new TextDecoder().decode(res.stdout) + "\n" +
          new TextDecoder().decode(res.stderr),
      );
    }
    return copyPrivateBytes(await Deno.readFile(out));
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test("in-language Blot coordinates stateless and prepared #kernel plus isolated #process", async () => {
  const source = `
import * as kernel from "std/kernel"
import * as process from "std/process"
import * as runtime from "std/runtime"
import { Vec2 } from "std/vector"

// 1. Stateless scalar kernel
#kernel func double_u32 (x: U32): U32 => x * 2 + 1

// 2. Stateless FlatNumeric record kernel (Vec2 -> F32)
#kernel func vec2_mag_sq (v: Vec2): F32 => v.x * v.x + v.y * v.y

// 3. Prepared-context kernel with variable-length output
func prep_scale (scale: U32): U32 => scale
func run_expand (scale: U32) -> (n: U32): #[U32] =>
  let out: #[U32] = #[]
  for i in 0..n:
    @storage.push out ((i + 1) * scale)
  return out
#kernel const expand: Kernel [U32, U32, #[U32]] = {
  prepare: prep_scale,
  run: run_expand,
}

// 4. Isolated stateful actor process
type AccState is data = $AccState { total: U32, count: U32 }
type AccCmd is data = $AccCmd { delta: U32 }
type AccReply is data = $AccReply { total: U32, count: U32 }

func acc_init (seed: U32): AccState => $AccState { total: seed, count: 0 }
func acc_step (s: own AccState) -> (cmd: AccCmd): (AccState, AccReply) =>
  let $AccCmd { delta } = cmd
  let next_total = s.total + delta
  let next_count = s.count + 1
  return ($AccState { total: next_total, count: next_count }, $AccReply { total: next_total, count: next_count })

#process const acc: Process [U32, AccCmd, AccReply] = {
  init: acc_init,
  step: acc_step,
}

io main (host: #[U32] -> #[U32] ! {Foreign}): U32 ! {Foreign} => do (runtime.provider host):
    // Run stateless scalar kernel
    use doubled_res <- kernel.run double_u32 #[1, 2, 3, 4]
    let $Ok doubled = doubled_res else:
      break 9001

    // Run stateless FlatNumeric Vec2 kernel
    use mags_res <- kernel.run vec2_mag_sq #[$Vec2 { x: 3.0, y: 4.0 }, $Vec2 { x: 1.0, y: 2.0 }]
    let $Ok mags = mags_res else:
      break 9002

    // Prepare and run variable-output kernel, then clear context
    use prep_res <- kernel.prepare expand 10
    let $Ok prep = prep_res else:
      break 9003
    use expanded_res <- kernel.run_prepared prep #[2, 3]
    let $Ok expanded = expanded_res else:
      break 9004
    use kernel.clear prep

    // Spawn stateful process and fold all results into it
    use pid_res <- process.spawn acc 100
    let $Ok pid = pid_res else:
      break 9005

    let last_total = 0
    let last_count = 0
    for v in doubled:
      use rep_res <- process.call pid ($AccCmd { delta: v })
      let $Ok ($AccReply { total, count }) = rep_res else:
        break 9006
      last_total := total
      last_count := count

    // Add squared magnitudes (25 + 5 = 30) and expanded sums ((10+20) + (10+20+30) = 90)
    let extra = F32.to_u32 mags[0] + F32.to_u32 mags[1]
    for row in expanded:
      for x in row:
        extra := self + x
    use rep2_res <- process.call pid ($AccCmd { delta: extra })
    let $Ok ($AccReply { total, count }) = rep2_res else:
      break 9007
    last_total := total
    last_count := count

    use process.close pid
    // Expected: seed(100) + doubled(3+5+7+9 = 24) + extra(30 + 90 = 120) = 244, count = 5
    break last_total * 10 + last_count
`;
  const wasm = await compileWasm(source);
  const rt = createRuntime(wasm, { workers: 0 });
  try {
    const result = await rt.run("main");
    equal(result, 2445);
  } finally {
    await rt.dispose();
  }
});

Deno.test("in-language Blot supports non-blocking kernel fan-out and multi-process wave scheduling", async () => {
  const source = `
import * as kernel from "std/kernel"
import * as process from "std/process"
import * as runtime from "std/runtime"

#kernel func square (x: U32): U32 => x * x

type Counter is data = $Counter { value: U32 }
func c_init (seed: U32): Counter => $Counter { value: seed }
func c_step (s: own Counter) -> (inc: U32): (Counter, U32) =>
  let next = s.value + inc
  return ($Counter { value: next }, next)

#process const counter: Process [U32, U32, U32] = {
  init: c_init,
  step: c_step,
}

io main (host: #[U32] -> #[U32] ! {Foreign}): U32 ! {Foreign} => do (runtime.provider host):
    // Fan out two kernel jobs concurrently, then await both
    use j1_res <- kernel.submit square #[2, 3]
    let $Ok j1 = j1_res else:
      break 1
    use j2_res <- kernel.submit square #[4, 5]
    let $Ok j2 = j2_res else:
      break 2
    use r1_res <- kernel.await_job j1
    let $Ok r1 = r1_res else:
      break 3
    use r2_res <- kernel.await_job j2
    let $Ok r2 = r2_res else:
      break 4

    // Spawn two independent processes, enqueue commands on both, advance wave, poll both
    use p1_res <- process.spawn counter 10
    let $Ok p1 = p1_res else:
      break 5
    use p2_res <- process.spawn counter 20
    let $Ok p2 = p2_res else:
      break 6
    use t1_res <- process.send p1 (r1[0] + r1[1])
    let $Ok t1 = t1_res else:
      break 7
    use t2_res <- process.send p2 (r2[0] + r2[1])
    let $Ok t2 = t2_res else:
      break 8
    use _ <- process.advance 16
    use a1_poll <- process.poll t1
    let $Some ($Ok a1) = a1_poll else:
      break 9
    use a2_poll <- process.poll t2
    let $Some ($Ok a2) = a2_poll else:
      break 10
    use process.close p1
    use process.close p2
    // a1 = 10 + (4 + 9) = 23, a2 = 20 + (16 + 25) = 61 -> sum = 84
    break a1 + a2
`;
  const wasm = await compileWasm(source);
  const rt = createRuntime(wasm, { workers: 0 });
  try {
    const result = await rt.run("main");
    equal(result, 84);
  } finally {
    await rt.dispose();
  }
});

Deno.test("in-language coordination contains kernel traps and process failures as typed Result errors", async () => {
  const source = `
import * as kernel from "std/kernel"
import * as process from "std/process"
import * as runtime from "std/runtime"

#kernel func risky_k (x: U32): U32 =>
  if x == 99:
    @panic "bad item"
  return x + 1

type S is data = $S { n: U32 }
func p_init (n: U32): S => $S { n }
func p_step (s: own S) -> (cmd: U32): (S, U32) =>
  if cmd == 0:
    @panic "zero forbidden"
  return ($S { n: s.n + cmd }, s.n + cmd)

#process const risky_p: Process [U32, U32, U32] = {
  init: p_init,
  step: p_step,
}

io main (host: #[U32] -> #[U32] ! {Foreign}): U32 ! {Foreign} => do (runtime.provider host):
    let flags = 0
    // Kernel trap returns $Err ($Trap _) without crashing the coordinator
    use k_res <- kernel.run risky_k #[1, 99]
    let f1 = case k_res of
      $Err ($kernel.Trap _) => 1
      _ => 0
    flags := self | f1

    // Subsequent valid kernel run still succeeds!
    use ok_res <- kernel.run risky_k #[5]
    let $Ok ok_vals = ok_res else:
      break 0
    if ok_vals.length == 1 and ok_vals[0] == 6:
      flags := self | 2

    // Process panic returns $Err $Failed without crashing the coordinator
    use pid_res <- process.spawn risky_p 1
    let $Ok pid = pid_res else:
      break 0
    use p_res <- process.call pid 0
    let f4 = case p_res of
      $Err $process.Failed => 4
      _ => 0
    flags := self | f4
    use process.close pid
    break flags
`;
  const wasm = await compileWasm(source);
  const rt = createRuntime(wasm, { workers: 0 });
  try {
    const result = await rt.run("main");
    equal(result, 7);
  } finally {
    await rt.dispose();
  }
});

Deno.test("pure Blot unit test can mock Runtime effect without any host", async () => {
  const source = `
import * as kernel from "std/kernel"
import * as runtime from "std/runtime"

#kernel func triple (x: U32): U32 => x * 3

func mock_host (req: #[U32]): #[U32] =>
  // Return [BRT1, STATUS_OK, 30, 60] for any kernel run
  return #[runtime.magic, runtime.status_ok, 30, 60]

io main (): U32 => do (@effect.provider runtime.Runtime.call mock_host):
    use vals_res <- kernel.run triple #[10, 20]
    let $Ok vals = vals_res else:
      break 0
    break vals[0] + vals[1]
`;
  const wasm = await compileWasm(source);
  const guest = await instantiateGuest(wasm);
  try {
    const out = guest.call("main", null);
    ok(out === 90, `expected 90, got ${out}`);
  } finally {
    guest.dispose();
  }
});

Deno.test("in-language coordination works with multi-worker KernelPool (workers: 2), #[4; F32] items, and Unit/#[U32] process wire types", async () => {
  const source = `
import * as kernel from "std/kernel"
import * as process from "std/process"
import * as runtime from "std/runtime"

#kernel func sum4 (v: #[4; F32]): F32 => v[0] + v[1] + v[2] + v[3]

type LogState is data = $LogState { items: #[U32] }
func log_init (_: Unit): LogState => $LogState { items: #[] }
func log_step (s: own LogState) -> (batch: #[U32]): (LogState, #[U32]) =>
  let $LogState { items } = s
  for x in batch:
    @storage.push items x
  let snap = items.copy
  return ($LogState { items }, snap)

#process const logger: Process [Unit, #[U32], #[U32]] = {
  init: log_init,
  step: log_step,
}

io main (host: #[U32] -> #[U32] ! {Foreign}): U32 ! {Foreign} => do (runtime.provider host):
  let r0: #[4; F32] = #[1.0, 2.0, 3.0, 4.0]
  let r1: #[4; F32] = #[10.0, 20.0, 30.0, 40.0]
  let rows: #[#[4; F32]] = #[r0, r1]
  use sums_res <- kernel.run sum4 rows
  let $Ok sums = sums_res else:
    break 1
  use pid_res <- process.spawn logger ()
  let $Ok pid = pid_res else:
    break 2
  use r1_res <- process.call pid #[F32.to_u32 sums[0]]
  let $Ok _ = r1_res else:
    break 3
  use r2_res <- process.call pid #[F32.to_u32 sums[1]]
  let $Ok snap = r2_res else:
    break 4
  use process.close pid
  // snap should be #[10, 100] -> sum = 110
  break snap[0] + snap[1]
`;
  const wasm = await compileWasm(source);
  const rt = createRuntime(wasm, { workers: 2 });
  try {
    const result = await rt.run("main");
    equal(result, 110);
  } finally {
    await rt.dispose();
  }
});

Deno.test("shipped examples io_entries.blot and runtime_coordination.blot execute cleanly", async () => {
  const ioSource = await Deno.readTextFile(
    new URL("../../examples/io_entries.blot", import.meta.url),
  );
  const ioWasm = await compileWasm(ioSource);
  const ioGuest = await instantiateGuest(ioWasm);
  equal(ioGuest.call("main", 20), 41);
  equal(ioGuest.call("internal_probe", 3), 10);

  const coordSource = await Deno.readTextFile(
    new URL("../../examples/runtime_coordination.blot", import.meta.url),
  );
  const coordWasm = await compileWasm(coordSource);
  const rt = createRuntime(coordWasm, { workers: 2 });
  try {
    // tile_sum = (2^2+1)+(3^2+1)+(4^2+1) = 5+10+17 = 32
    // scaled_sum = 3*2 + 5*4 = 26
    // r1 = 10^2+1 = 101, r2 = 20^2+1 = 401
    // recorded_total = 100 + 32 = 132, final_total = 132 + 26 = 158
    // result = 158 + 132 + 101 + 401 = 792
    equal(await rt.run("main"), 792);
  } finally {
    await rt.dispose();
  }
  const mockedGuest = await instantiateGuest(coordWasm);
  equal(mockedGuest.call("mocked", null), 60);
});
