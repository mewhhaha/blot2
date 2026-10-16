import { strict as assert } from "node:assert";
import { fileURLToPath } from "node:url";

// Qualification command: compile each subsystem independently and compare the
// exact discovered test names with the complete gate, including inline laws.
const suites = [
  "all",
  "syntax",
  "types",
  "runtime",
  "checker",
  "evaluator",
  "backend",
  "retained",
];
const zig = Deno.env.get("ZIG") ?? "zig";
const version = await new Deno.Command(zig, { args: ["version"] }).output();
assert.equal(new TextDecoder().decode(version.stdout).trim(), "0.17.0");
const native = fileURLToPath(new URL("../zig-native/", import.meta.url));
const directory = await Deno.makeTempDir({ prefix: "blot-suite-inventory-" });
const inventories = new Map<string, Set<string>>();
try {
  for (const suite of suites) {
    const prefix = `${directory}/${suite}`;
    const start = performance.now();
    const result = await new Deno.Command(zig, {
      cwd: native,
      args: [
        "build",
        "test-compile",
        "-Doptimize=safe",
        "-Dllvm=false",
        `-Dtest-suite=${suite}`,
        "--prefix",
        prefix,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.equal(result.code, 0, new TextDecoder().decode(result.stderr));
    const listed = await new Deno.Command(`${prefix}/bin/blot-tests`, {
      args: ["--list"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.equal(listed.code, 0, new TextDecoder().decode(listed.stderr));
    const names = new TextDecoder().decode(listed.stdout).trim().split("\n")
      .filter(Boolean);
    assert.equal(
      new Set(names).size,
      names.length,
      `${suite} repeated a test name`,
    );
    inventories.set(suite, new Set(names));
    console.log(
      `${suite}: ${names.length} tests, ${
        ((performance.now() - start) / 1000).toFixed(2)
      }s`,
    );
  }
  const all = inventories.get("all")!;
  const union = new Set<string>();
  for (const suite of suites.slice(1)) {
    for (const name of inventories.get(suite)!) {
      assert(all.has(name), `${suite} has an unregistered test: ${name}`);
      union.add(name);
    }
  }
  assert.deepEqual(
    [...union].sort(),
    [...all].sort(),
    "subsystem union differs from the full gate",
  );
  console.log(`Exact subsystem union: ${union.size} tests.`);
} finally {
  await Deno.remove(directory, { recursive: true });
}
