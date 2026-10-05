import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const compiler = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;

Deno.test("tags stack nearest first and annotate complete scalar or function initializers", async () => {
  const source = await Deno.readTextFile(
    new URL("../../examples/tags.blot", import.meta.url),
  );
  await compileAndRun(source, (guest) => {
    equal(guest.read("answer"), 41);
    equal(guest.read("truth"), true);
    equal(guest.read("initialized"), 42);
    equal(guest.call("next", 41), 42);
    equal(guest.read("reduced"), 42);
  });
});
Deno.test("tags resolve aliases and both imported name forms", async () => {
  const dir = await Deno.makeTempDir({
    dir: new URL("../../build", import.meta.url).pathname,
    prefix: "tag-project-",
  });
  try {
    await Deno.writeTextFile(
      `${dir}/lib.blot`,
      "const inc=fn value=>value+1\nconst add=fn amount=>fn value=>value+amount\n",
    );
    await Deno.writeTextFile(
      `${dir}/main.blot`,
      'import { inc as imported } from "./lib"\nimport * as lib from "./lib"\nconst alias=imported\n@[alias] entry const local:U32=41\n@[imported] entry const named:U32=41\n@[lib.add 1] entry const qualified:U32=41\n',
    );
    const run = await new Deno.Command(compiler, {
      args: [
        "build",
        `${dir}/main.blot`,
        `${dir}/program.wasm`,
        "--std-root",
        "std",
        "--prelude",
        new URL("../../std/prelude.blot", import.meta.url).pathname,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    if (!run.success) {
      throw new Error(
        new TextDecoder().decode(run.stdout) +
          new TextDecoder().decode(run.stderr),
      );
    }
    const records = new TextDecoder().decode(run.stdout).trim().split("\n").map(
      (line) => JSON.parse(line),
    );
    equal(
      records.find((record) => record.kind === "compilation").memory.live_bytes,
      0,
    );
    const guest = await instantiateGuest(
      await Deno.readFile(`${dir}/program.wasm`),
    );
    try {
      for (const name of ["local", "named", "qualified"]) {
        equal(guest.read(name), 42);
      }
    } finally {
      guest.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
Deno.test("undemanded tagged declarations and uncalled tagged function bodies stay unevaluated", async () => {
  await compileAndRun(
    '@[fn value=>@panic "unused const"] const unused:U32=1\n@[fn value=>@panic "unused let"] let unused_let:U32=1\n@[fn function=>function] const uncalled=fn ()=>@panic "uncalled"\nentry const answer=42\n',
    (guest) => equal(guest.read("answer"), 42),
  );
  await compileExpectedFailure(
    "@[fn ~value=>@force value] entry const answer:U32=42\n",
    "type_mismatch",
  );
});
Deno.test("tag startup closures wrap the original initializer without flattening its parameters", async () => {
  await compileAndRun(
    "const decorate=fn function=>fn value=>@u32.add (function value) 1\n@[decorate] let next:U32->U32=fn(value:U32)=>value\nentry const answer=fn(value:U32)=>next value\n",
    (guest) => {
      for (const value of [0, 1, 41, 100]) {
        equal(guest.call("answer", value), value + 1);
      }
    },
  );
});
Deno.test("named and inline tag panics retain the exact tag invocation location", async () => {
  for (
    const source of [
      '@[fn value=>@panic "tag"] entry const answer:U32=42\n',
      'const decorator=fn value=>@panic "tag"\n@[decorator] entry const answer:U32=42\n',
      'const decorator=fn value=>@panic "tag"\n@[fn value=>value]\n@[decorator] entry const answer:U32=42\n',
    ]
  ) {
    const dir = await Deno.makeTempDir({
      dir: new URL("../../build", import.meta.url).pathname,
      prefix: "tag-diagnostic-",
    });
    try {
      await Deno.writeTextFile(`${dir}/main.blot`, source);
      const run = await new Deno.Command(compiler, {
        args: ["build", `${dir}/main.blot`, `${dir}/program.wasm`],
        stdout: "piped",
        stderr: "piped",
      }).output();
      equal(run.success, false);
      const records = new TextDecoder().decode(run.stdout).trim().split("\n")
        .map((line) => JSON.parse(line));
      const diagnostic = records.find((record) => record.kind === "diagnostic");
      equal(diagnostic.code, "const_panic");
      equal(diagnostic.message, "tag");
      equal(
        diagnostic.start,
        source.indexOf(source.includes("@[decorator]") ? "@[decorator]" : "@["),
      );
      equal(
        records.find((record) => record.kind === "compilation").memory
          .live_bytes,
        0,
      );
    } finally {
      await Deno.remove(dir, { recursive: true });
    }
  }
});
