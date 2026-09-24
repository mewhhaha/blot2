import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { optimizeNativeOwnedResolverProbe } from "../../native_owned_resolver.ts";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const sources = {
  types: await Deno.readTextFile(resolve(root, "compiler/types.bend")),
  natIndex: await Deno.readTextFile(resolve(root, "compiler/nat_index.bend")),
  model: await Deno.readTextFile(resolve(root, "compiler/model.bend")),
};

async function command(executable: string, args: string[]) {
  const result = await new Deno.Command(executable, {
    args,
    env: { BEND_NO_TELEMETRY: "1" },
    stdout: "piped",
    stderr: "piped",
  }).output();
  const stdout = new TextDecoder().decode(result.stdout);
  const stderr = new TextDecoder().decode(result.stderr);
  if (!result.success) {
    throw new Error(
      `${executable} ${
        args.join(" ")
      } failed (${result.code})\n${stdout}${stderr}`,
    );
  }
  return { stdout, stderr };
}

const version = (await command("bend", ["version"])).stdout.trim();
const temp = await Deno.makeTempDir({ prefix: "blot-owned-resolver-" });
try {
  const rawC = resolve(temp, "baseline.c");
  const ownedC = resolve(temp, "owned.c");
  const traceC = resolve(temp, "owned-trace.c");
  const rawBin = resolve(temp, "baseline");
  const ownedBin = resolve(temp, "owned");
  const traceBin = resolve(temp, "owned-trace");
  await command("bend", [
    fileURLToPath(new URL("owned_solver_regression.bend", import.meta.url)),
    "-o",
    rawC,
  ]);
  const generated = await Deno.readTextFile(rawC);
  const patched = await optimizeNativeOwnedResolverProbe(
    generated,
    sources,
    version,
  );
  await Deno.writeTextFile(ownedC, patched);
  const marker =
    "      Term owned_output = owned_changed ? owned_freeze(e, &owned_plan_scratch,\n";
  equal(patched.split(marker).length, 2, "owned success marker must be unique");
  await Deno.writeTextFile(
    traceC,
    patched.replace(
      marker,
      '      fprintf(stderr, "OWNED_HIT changed=%d\\n", (int)owned_changed);\n' +
        marker,
    ),
  );
  for (
    const [input, output] of [[rawC, rawBin], [ownedC, ownedBin], [
      traceC,
      traceBin,
    ]]
  ) {
    await command("clang", [
      "-std=c11",
      "-O3",
      "-w",
      "-pthread",
      input,
      "-lm",
      "-o",
      output,
    ]);
  }
  for (const threads of [1, 4]) {
    for (const args of [[], ["miss"]]) {
      const flags = ["--threads", String(threads), ...args];
      const baseline = await command(rawBin, flags);
      const owned = await command(ownedBin, flags);
      equal(owned, baseline, `threads=${threads}, args=${args.join(",")}`);
      const lines = owned.stdout.split(/\r?\n/).filter(Boolean);
      equal(lines.length, 4);
      equal(lines[2], "F32");
      ok(lines[3].startsWith("FAIL type_complexity "));
      if (args.length === 0) {
        ok(lines[0].includes("regression::Box"));
        ok(lines[1].includes("Array (Bool)"));
      }
    }
  }
  const trace = await command(traceBin, ["--threads", "1"]);
  ok((trace.stderr.match(/OWNED_HIT changed=1/g) ?? []).length >= 3);
  console.log(
    "Owned resolver direct native oracle passed at 1 and 4 threads, with changed-path hits",
  );
} finally {
  await Deno.remove(temp, { recursive: true });
}
