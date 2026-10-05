import { deepStrictEqual as equal, ok } from "node:assert/strict";
import {
  blotCompilerBinary,
  blotStdRoot,
  createCompiler,
  instantiateGuest,
} from "../mod.ts";
import { fileURLToPath } from "node:url";
import { runCli } from "./cli.ts";

const executable = Deno.args[0] ??
  new URL("../zig-native/zig-out/bin/blotc", import.meta.url);

for (const packaged of [false, true]) {
  Deno.test(`${packaged ? "packaged" : "local"} Zig API builds, edits, rejects and recovers`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const compiler = await createCompiler({
      entry,
      ...(packaged ? {} : { executable }),
    });
    try {
      const original =
        "entry const answer = fn () => (Array.from_list [40, 2])[0] + 2\n";
      const first = await compiler.build({ sources: { [entry]: original } });
      ok(first.success, JSON.stringify(first));
      const guest = await instantiateGuest(first.bytes);
      try {
        equal(guest.call("answer", null), 42);
      } finally {
        guest.dispose();
      }
      const broken = await compiler.build({
        sources: { [entry]: "entry const answer = missing\n" },
      });
      equal(broken.success, false);
      equal(broken.revision, first.revision);
      const changed = await compiler.build({
        sources: { [entry]: original.replace("40, 2", "41, 2") },
      });
      ok(changed.success, JSON.stringify(changed));
      ok(changed.revision > first.revision);
      const next = await instantiateGuest(changed.bytes);
      try {
        equal(next.call("answer", null), 43);
      } finally {
        next.dispose();
      }
      const reverted = await compiler.build({ sources: { [entry]: original } });
      ok(reverted.success);
      equal(reverted.bytes, first.bytes);
      await compiler.close();
      await compiler.close();
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

Deno.test("standalone host exposes its embedded compiler and prelude to the native child", async () => {
  const directory = await Deno.makeTempDir();
  try {
    const source = `${directory}/host.ts`, output = `${directory}/host`;
    await Deno.writeTextFile(
      source,
      `import { createCompiler, instantiateGuest } from ${
        JSON.stringify(new URL("../mod.ts", import.meta.url).href)
      };
if (!Deno.build.standalone) throw new Error("Expected a standalone executable");
const entry = ${JSON.stringify(`${directory}/main.blot`)};
const compiler = await createCompiler({ entry });
try {
  for (const number of [40, 41]) {
    const result = await compiler.build({ sources: { [entry]:
      'import * as array from "std/array"\\nentry const answer = fn () => (Array.from_list [' + number + ', 2])[0] + 2\\n'
    } });
    if (!result.success) throw new Error(JSON.stringify(result));
    const guest = await instantiateGuest(result.bytes);
    try {
      if (guest.call("answer", null) !== number + 2) throw new Error("Wrong result");
    } finally { guest.dispose(); }
  }
} finally { await compiler.dispose(); }
`,
    );
    const compiled = await new Deno.Command(Deno.execPath(), {
      args: [
        "compile",
        "--allow-read",
        "--allow-write",
        "--allow-run",
        "--include",
        fileURLToPath(blotStdRoot),
        "--include",
        fileURLToPath(blotCompilerBinary),
        "--output",
        output,
        source,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    ok(compiled.success, new TextDecoder().decode(compiled.stderr));
    const result = await new Deno.Command(output, {
      stdout: "piped",
      stderr: "piped",
    }).output();
    ok(result.success, new TextDecoder().decode(result.stderr));
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("CLI builds projects and dependencies, and fails without publishing invalid output", async () => {
  const directory = await Deno.makeTempDir();
  try {
    const input = `${directory}/main.blot`,
      output = `${directory}/program.wasm`,
      bundle = `${directory}/project.blotdep`;
    await Deno.writeTextFile(input, "entry const answer = fn () => 42\n");
    equal(await runCli(executable, ["check", input]), 0);
    equal(await runCli(executable, ["build", input, output]), 0);
    const original = await Deno.readFile(output);
    ok(WebAssembly.validate(original));
    equal(await runCli(executable, ["dependencies", input, bundle]), 0);
    equal(
      await runCli(executable, [
        "build",
        input,
        output,
        "--dependencies",
        bundle,
      ]),
      0,
    );
    equal(await Deno.readFile(output), original);
    await Deno.writeTextFile(input, "entry const answer = unknown\n");
    equal(await runCli(executable, ["build", input, output]), 1);
    equal(await Deno.readFile(output), original);
    equal(await runCli(executable, ["build", input, "--prelude"]), 2);
    equal(await runCli(executable, ["check", input, "unexpected"]), 2);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
