import { deepStrictEqual as equal, ok } from "node:assert/strict";

const [executable] = Deno.args;
ok(
  executable && Deno.args.length === 1,
  "Usage: verify.ts <native-executable>",
);
for (const threads of [1, 8]) {
  for (const variant of ["scalar", "pair"]) {
    const result = await new Deno.Command(executable, {
      args: ["--threads", String(threads)],
      clearEnv: true,
      env: { BEND_REPRO_CASE: variant },
      stdout: "piped",
      stderr: "piped",
    }).output();
    equal(result.code, 0, new TextDecoder().decode(result.stderr));
    const lines = new TextDecoder().decode(result.stdout).trim().split("\n");
    equal(lines.length, 4);
    const allocations = lines.map((line) => {
      const match = /^count=1 in_use_bytes=(\d+)$/.exec(line);
      ok(match, `Unexpected result: ${line}`);
      return Number(match[1]);
    });
    const deltas = allocations.slice(1).map((bytes, i) =>
      bytes - allocations[i]
    );
    equal(deltas, variant === "scalar" ? [16, 16, 16] : [0, 0, 0]);
    console.log(JSON.stringify({ threads, variant, allocations, deltas }));
  }
}
console.log("Leak reproduced: Scalar loses 16 bytes/call; Pair loses none.");
