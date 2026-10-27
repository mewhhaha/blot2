import { Blot } from "../host/blot.ts";
import { assert } from "./session_harness.ts";
Deno.test("K1-10 migration includes imported generic helper and copy-only host boundary", async () => {
  const report = await new Deno.Command("build/blot", {
    args: ["migrate", "migration/legacy/copy.blot"],
    stdout: "piped",
    stderr: "piped",
  }).output();
  assert(report.success, new TextDecoder().decode(report.stderr));
  const result = JSON.parse(new TextDecoder().decode(report.stdout));
  assert(result.automatic_changes === 0 && result.review_required);
  const source = await Deno.readTextFile("migration/legacy/copy.blot");
  for (const finding of result.findings) {
    assert(
      finding.start >= 0 && finding.end > finding.start &&
        finding.end <= source.length,
    );
  }
  for (const code of [1, 3, 4]) {
    assert(result.findings.some((f: { code: number }) => f.code === code));
  }
  assert(
    !result.findings.some((f: { code: number }) => f.code === 5),
    "import path mistaken for runtime string",
  );
  const compile = await new Deno.Command("build/blot", {
    args: [
      "build",
      "examples/migration/copy.blot",
      "-o",
      "build/migrated.wasm",
      "--bridge-config=examples/migration/copy.json",
    ],
    stdout: "piped",
    stderr: "piped",
  }).output();
  assert(compile.success, new TextDecoder().decode(compile.stderr));
  const host = await Blot.load(await Deno.readFile("build/migrated.wasm"));
  for (
    const input of [
      [],
      [0],
      [1, 42, 4294967295],
      Array.from({ length: 1024 }, (_, i) => i),
    ]
  ) {
    const output = host.invoke("copy_identity", { src: input });
    assert(
      output.status === "Ok" && Array.isArray(output.items) &&
        output.items.join() === input.join(),
    );
    input.fill(7);
    assert(output.items !== input);
  }
  assert(
    host.invoke("copy_identity", { src: [42] }, 8).status === "OutputTooSmall",
  );
  assert(host.invoke("copy_identity", { src: [-1] }).status === "InvalidInput");
});
