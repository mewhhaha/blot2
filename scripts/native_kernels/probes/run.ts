import { strictEqual as equal } from "node:assert/strict";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  type NativeKernelSources,
  optimizeNativeCompilerKernelProbe,
} from "../../native_compiler_kernels.ts";

const root = fileURLToPath(new URL("../../../", import.meta.url));
const sources: NativeKernelSources = {
  index: await Deno.readTextFile(resolve(root, "compiler/index.bend")),
  types: await Deno.readTextFile(resolve(root, "compiler/types.bend")),
  model: await Deno.readTextFile(resolve(root, "compiler/model.bend")),
};
const version = (await command("bend", ["version"])).stdout.trim();
const temp = await Deno.makeTempDir({ prefix: "blot-native-kernels-" });

async function command(
  executable: string,
  args: string[],
  env: Record<string, string> = {},
): Promise<{ stdout: string; stderr: string }> {
  const result = await new Deno.Command(executable, {
    args,
    env: { BEND_NO_TELEMETRY: "1", ...env },
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

try {
  for (
    const [kernel, probe] of [
      ["index", "index_oracle.bend"],
      ["free", "free_oracle.bend"],
      ["closed", "resolve_oracle.bend"],
    ] as const
  ) {
    const originalC = resolve(temp, `${kernel}-baseline.c`);
    const optimizedC = resolve(temp, `${kernel}-candidate.c`);
    const baseline = resolve(temp, `${kernel}-baseline`);
    const candidate = resolve(temp, `${kernel}-candidate`);
    await command("bend", [
      fileURLToPath(new URL(probe, import.meta.url)),
      "-o",
      originalC,
    ]);
    const generated = await Deno.readTextFile(originalC);
    await Deno.writeTextFile(
      optimizedC,
      await optimizeNativeCompilerKernelProbe(
        generated,
        sources,
        version,
        kernel,
      ),
    );
    for (
      const [input, output] of [[originalC, baseline], [optimizedC, candidate]]
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
    let comparisons = 0;
    for (const threads of [1, 4]) {
      for (const seed of [0, 1, 17]) {
        const args = ["--threads", String(threads)];
        const env = { BORROW_ORACLE_SEED: String(seed) };
        const expected = await command(baseline, args, env);
        const actual = await command(candidate, args, env);
        equal(
          actual.stdout,
          expected.stdout,
          `${kernel}, ${threads} threads, seed ${seed}`,
        );
        equal(
          actual.stderr,
          expected.stderr,
          `${kernel}, ${threads} threads, seed ${seed}`,
        );
        comparisons++;
      }
    }
    console.log(`${kernel}: ${comparisons} native oracle pairs passed`);
  }
} finally {
  await Deno.remove(temp, { recursive: true });
}
