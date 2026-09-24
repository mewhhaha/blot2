import { deepStrictEqual as equal, ok, strictEqual } from "node:assert/strict";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { optimizeNativeBorrowedStrings } from "../../native_borrowed_strings.ts";

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

const temporary = await Deno.makeTempDir({ prefix: "blot-borrowed-strings-" });
try {
  const probe = fileURLToPath(
    new URL("./borrowed_strings.bend", import.meta.url),
  );
  const rawC = resolve(temporary, "borrowed.raw.c");
  const optimizedC = resolve(temporary, "borrowed.optimized.c");
  const rawBinary = resolve(temporary, "borrowed.raw");
  const candidateBinary = resolve(temporary, "borrowed.optimized");
  const sanitizerBinary = resolve(temporary, "borrowed.sanitized");
  const tracedC = resolve(temporary, "borrowed.traced.c");
  const tracedBinary = resolve(temporary, "borrowed.traced");
  const version = (await must("bend", ["version"])).stdout.trim();
  const [map, string, char] = await Promise.all(
    (["Map", "String", "Char"] as const).map(async (name) =>
      (await must("bend", ["base", name])).stdout
    ),
  );
  await must("bend", [probe, "--check-only"]);
  await must("bend", [probe, "-o", rawC]);
  const raw = await Deno.readTextFile(rawC);
  const optimized = await optimizeNativeBorrowedStrings(raw, {
    map,
    string,
    char,
  }, version);
  await Deno.writeTextFile(optimizedC, optimized);
  ok(optimized.includes("Term root_a = r0, root_b = r1;"));
  ok(optimized.includes("u64 character_index = r1 / 33ull;"));
  strictEqual(optimized.split("Term key = r0;").length, 2);
  strictEqual(optimized.split("Term root_a = r0, root_b = r1;").length, 2);
  await Deno.writeTextFile(
    tracedC,
    optimized
      .replace(
        "Term key = r0;",
        'fprintf(stderr, "BORROWED_MAP\\n");\n    Term key = r0;',
      )
      .replace(
        "Term root_a = r0, root_b = r1;",
        'fprintf(stderr, "BORROWED_CMP\\n");\n    Term root_a = r0, root_b = r1;',
      ),
  );
  await must("clang", [
    "-std=c11",
    "-O1",
    "-w",
    "-pthread",
    rawC,
    "-lm",
    "-o",
    rawBinary,
  ]);
  await must("clang", [
    "-std=c11",
    "-O1",
    "-w",
    "-pthread",
    optimizedC,
    "-lm",
    "-o",
    candidateBinary,
  ]);
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
    sanitizerBinary,
  ]);
  await must("clang", [
    "-std=c11",
    "-O1",
    "-w",
    "-pthread",
    tracedC,
    "-lm",
    "-o",
    tracedBinary,
  ]);
  for (const threads of [1, 4]) {
    const traced = await must(tracedBinary, ["--threads", String(threads)]);
    ok(
      (traced.stderr.match(/BORROWED_MAP/g) ?? []).length >= 4,
      "Map.bit kernel must execute",
    );
    ok(
      (traced.stderr.match(/BORROWED_CMP/g) ?? []).length >= 4,
      "String.cmp kernel must execute",
    );
    for (let repeat = 0; repeat < 3; repeat++) {
      const args = ["--threads", String(threads)];
      const baseline = await command(rawBinary, args);
      const candidate = await command(candidateBinary, args);
      const sanitized = await command(sanitizerBinary, args);
      equal(
        candidate,
        baseline,
        `native differential threads=${threads}, repeat=${repeat}`,
      );
      equal(
        sanitized,
        baseline,
        `sanitized differential threads=${threads}, repeat=${repeat}`,
      );
      strictEqual(candidate.code, 0);
      ok(candidate.stdout.includes("[1, 0, 2,"));
      ok(
        !candidate.stdout.includes("99"),
        "both returned Strings must equal their owned inputs",
      );
    }
  }
  // The Nat48 overflow must retain the original native diagnostic path.
  const overflowProbe = fileURLToPath(
    new URL("./borrowed_strings_overflow.bend", import.meta.url),
  );
  const overflowRawC = resolve(temporary, "overflow.raw.c");
  const overflowOptimizedC = resolve(temporary, "overflow.optimized.c");
  const overflowRaw = resolve(temporary, "overflow.raw");
  const overflowCandidate = resolve(temporary, "overflow.optimized");
  await must("bend", [overflowProbe, "--check-only"]);
  await must("bend", [overflowProbe, "-o", overflowRawC]);
  await Deno.writeTextFile(
    overflowOptimizedC,
    await optimizeNativeBorrowedStrings(
      await Deno.readTextFile(overflowRawC),
      { map, string, char },
      version,
    ),
  );
  await must("clang", [
    "-std=c11",
    "-O1",
    "-w",
    "-pthread",
    overflowRawC,
    "-lm",
    "-o",
    overflowRaw,
  ]);
  await must("clang", [
    "-std=c11",
    "-O1",
    "-w",
    "-pthread",
    overflowOptimizedC,
    "-lm",
    "-o",
    overflowCandidate,
  ]);
  for (const threads of [1, 4]) {
    const args = ["--threads", String(threads)];
    const baseline = await command(overflowRaw, args);
    const candidate = await command(overflowCandidate, args);
    equal(candidate, baseline, `Nat48 overflow threads=${threads}`);
    strictEqual(candidate.code, 1);
    ok(candidate.stderr.includes("a Nat past the largest immediate 2^48-1"));
  }
  console.log(
    "Borrowed String direct Bend probes: 1/4 workers, native differential, Nat48 error recovery, and ASan/UBSan passed.",
  );
} finally {
  await Deno.remove(temporary, { recursive: true });
}
