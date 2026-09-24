import { deepStrictEqual as equal, ok, strictEqual } from "node:assert/strict";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { optimizeNativeNatIndexProbe } from "../../native_nat_index.ts";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const natIndex = await Deno.readTextFile(
  resolve(root, "compiler/nat_index.bend"),
);
const decoder = new TextDecoder();
async function command(name: string, args: string[]) {
  const result = await new Deno.Command(name, {
    args,
    env: { BEND_NO_TELEMETRY: "1" },
    stdout: "piped",
    stderr: "piped",
  }).output();
  return {
    code: result.code,
    stdout: decoder.decode(result.stdout),
    stderr: decoder.decode(result.stderr),
  };
}
async function must(name: string, args: string[]) {
  const result = await command(name, args);
  if (result.code !== 0) {
    throw new Error(
      `${name} ${
        args.join(" ")
      } failed (${result.code})\n${result.stdout}${result.stderr}`,
    );
  }
  return result;
}

const version = (await must("bend", ["version"])).stdout.trim();
const temporary = await Deno.makeTempDir({ prefix: "blot-nat-index-" });
try {
  for (
    const [kind, file] of [["normal", "nat_index_oracle.bend"], [
      "overflow",
      "nat_index_overflow.bend",
    ]] as const
  ) {
    const originalC = resolve(temporary, `${kind}.raw.c`);
    const optimizedC = resolve(temporary, `${kind}.optimized.c`);
    const original = resolve(temporary, `${kind}.raw`);
    const optimized = resolve(temporary, `${kind}.optimized`);
    await must("bend", [
      fileURLToPath(new URL(file, import.meta.url)),
      "-o",
      originalC,
    ]);
    const patched = await optimizeNativeNatIndexProbe(
      await Deno.readTextFile(originalC),
      { natIndex },
      version,
    );
    await Deno.writeTextFile(optimizedC, patched);
    await must("clang", [
      "-std=c11",
      "-O3",
      "-w",
      "-pthread",
      originalC,
      "-lm",
      "-o",
      original,
    ]);
    await must("clang", [
      "-std=c11",
      "-O3",
      "-w",
      "-pthread",
      optimizedC,
      "-lm",
      "-o",
      optimized,
    ]);
    for (const threads of [1, 4]) {
      for (let repeat = 0; repeat < 3; repeat++) {
        const args = ["--threads", String(threads)];
        const baseline = await command(original, args);
        const candidate = await command(optimized, args);
        equal(
          candidate,
          baseline,
          `${kind}, threads=${threads}, repeat=${repeat}`,
        );
        if (kind === "normal") {
          strictEqual(candidate.code, 0);
          strictEqual(candidate.stdout, "NAT_INDEX_OK\n");
        } else {
          strictEqual(candidate.code, 1);
          ok(
            candidate.stderr.includes(
              "a Nat past the largest immediate 2^48-1",
            ),
          );
        }
      }
    }
    if (kind === "normal") {
      const traceC = resolve(temporary, "normal.trace.c");
      const trace = resolve(temporary, "normal.trace");
      const marker =
        "    WL_OPEN\n    for (;;) {\n      if (err_spun(e.mem, &wpoll)) return 0;";
      strictEqual(
        patched.split(marker).length,
        2,
        "optimized find loop must be unique",
      );
      await Deno.writeTextFile(
        traceC,
        patched.replace(
          marker,
          '    WL_OPEN\n    fprintf(stderr, "NAT_FIND\\n");\n    for (;;) {\n      if (err_spun(e.mem, &wpoll)) return 0;',
        ),
      );
      await must("clang", [
        "-std=c11",
        "-O3",
        "-w",
        "-pthread",
        traceC,
        "-lm",
        "-o",
        trace,
      ]);
      const traced = await must(trace, ["--threads", "1"]);
      ok(
        (traced.stderr.match(/NAT_FIND/g) ?? []).length >= 1000,
        "direct loop must be exercised repeatedly",
      );

      const sanitizer = resolve(temporary, "normal.sanitized");
      await must("clang", [
        "-std=c11",
        "-O1",
        "-g",
        "-w",
        "-pthread",
        "-fsanitize=address,undefined",
        "-fno-omit-frame-pointer",
        optimizedC,
        "-lm",
        "-o",
        sanitizer,
      ]);
      for (const threads of [1, 4]) {
        const sanitized = await must(sanitizer, ["--threads", String(threads)]);
        strictEqual(sanitized.stdout, "NAT_INDEX_OK\n");
        strictEqual(sanitized.stderr, "");
      }
    }
    console.log(
      `${kind}: baseline/candidate exact differential passed at 1 and 4 workers, three repeats`,
    );
  }
  console.log("NatIndex direct path trace and AddressSanitizer/UBSan passed");
} finally {
  await Deno.remove(temporary, { recursive: true });
}
