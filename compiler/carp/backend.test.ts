import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import {
  carpExecutable,
  createCarpCompiler,
  createCarpIncrementalCompiler,
  createCarpProjectCompiler,
} from "../carp.ts";
import { instantiateGuest } from "../guest.ts";
import { CompilerError } from "../diagnostics.ts";
import { SourceError } from "../syntax.ts";
import { loadSourceProject } from "../source_project.ts";

Deno.test("Carp executable identifies itself and rejects invalid thread counts", async () => {
  const version = await new Deno.Command(carpExecutable, {
    args: ["--version"],
  }).output();
  equal(version.code, 0);
  ok(
    new TextDecoder().decode(version.stdout).includes(
      "blotc-carp native semantic port",
    ),
  );
  for (const n of ["0", "65", "invalid", "-1"]) {
    const result = await new Deno.Command(carpExecutable, {
      args: ["--threads", n],
    }).output();
    equal(result.code, 1);
    equal(result.stdout.length, 0);
  }
});

Deno.test("Carp supports captured closures, generics, ADTs and lexical patterns", async () => {
  const compiler = await createCarpCompiler({ prelude: "none" });
  try {
    const artifact = await compiler.compile(`
type Box a is data = Box a
const identity = fn value => value
const make = fn offset => fn (value: U32) => @u32.add offset value
entry const answer = fn () => do:
  let add = make 40
  let Box value = Box (identity 2)
  return add value
entry const flag = identity True
`);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("answer", null), 42);
      equal(guest.read("flag"), true);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
  }
});

Deno.test("Carp imports the source prelude and std/array without Bend", async () => {
  const compiler = await createCarpCompiler();
  try {
    for (const example of ["records", "arrays"]) {
      const project = await loadSourceProject(
        new URL(`../../examples/${example}.blot`, import.meta.url),
        {
          imports: { "std/": new URL("../../std/", import.meta.url) },
        },
      );
      const artifact = await compiler.compile(project);
      const guest = await instantiateGuest(artifact.bytes);
      try {
        equal(guest.call("answer", null), 42);
        equal(guest.read("expected"), 42);
        if (example === "arrays") {
          equal(guest.call("unchanged", null), 42);
          equal(guest.call("nested", null), 42);
          equal(guest.call("checked", 0), 10);
          equal(guest.call("checked", 2), 12);
          equal(guest.call("checked", 3), 0);
        }
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await compiler.dispose();
  }
});

Deno.test("Carp preserves source operators, recursion, laziness and effects", async () => {
  const compiler = await createCarpCompiler();
  try {
    const artifact = await compiler.compile(
      await Deno.readTextFile(
        new URL("../../examples/syntax.blot", import.meta.url),
      ),
    );
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.read("operator_example"), 7);
      equal(guest.call("recursive_example", 5), 120);
      equal(guest.call("short_circuit", null), false);
      for (
        const name of [
          "lazy_fallback",
          "matching_example",
          "event_example",
          "provider_example",
        ]
      ) {
        equal(guest.call(name, null), 42);
      }
      equal(guest.call("vector_example", null), 50);
      equal(guest.call("array_snapshot", null), 22);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
  }
});

Deno.test("Carp emits checked numeric-array and asynchronous callback ABIs", async () => {
  const compiler = await createCarpCompiler({ prelude: "none" });
  try {
    const artifact = await compiler.compile(
      `
entry const integers = fn (values: Array U32) => values
entry const change = fn (values: Array F32) => @array.set values 0 42.5
entry const main = fn (host: U32 -> U32 ! {Foreign}) => do:
  use first <- host 40
  use second <- host first
  return @u32.add first second
`,
      { analysis: false },
    );
    equal(Object.keys(artifact), ["bytes"]);
    const guest = await instantiateGuest(artifact.bytes, {
      asynchronous: true,
    });
    try {
      const original = new Uint32Array([0, 42, 0xffffffff]);
      const copy = await guest.callAsync("integers", original);
      equal(copy, original);
      ok(copy !== original);
      const floats = new Float32Array(70000).fill(2.25);
      const changed = await guest.callAsync("change", floats);
      ok(changed instanceof Float32Array);
      equal(changed[0], 42.5);
      equal(changed[69999], 2.25);
      equal(floats[0], 2.25);
      const host = guest.capabilityAsync({
        parameter: "U32",
        result: "U32",
        call: (value) => Promise.resolve(value + 1),
      });
      equal(await guest.callAsync("main", host), 83);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
  }
});

Deno.test("Carp incremental revisions retain caches and roll back failures", async () => {
  const compiler = await createCarpIncrementalCompiler({
    prelude: "none",
    threads: 4,
  });
  const source =
    "const base = @u32.add 40 1\nentry const answer = fn () => @u32.add base 1\n";
  async function value(bytes: Uint8Array<ArrayBuffer>) {
    const guest = await instantiateGuest(bytes);
    try {
      return guest.call("answer", null);
    } finally {
      guest.dispose();
    }
  }
  try {
    const first = await compiler.compile(source);
    equal(await value(first.artifact.bytes), 42);
    const repeated = await compiler.compile(source);
    equal(repeated.stats.result_reused, true);
    equal(repeated.artifact, first.artifact);
    await rejects(
      () => compiler.compile(source.replace("40 1", "40 missing")),
      (error) => {
        ok(error instanceof SourceError);
        equal(error.code, "unknown_value");
        return true;
      },
    );
    const recovered = await compiler.compile(source);
    equal(await value(recovered.artifact.bytes), 42);
    await rejects(
      () => compiler.compile(source, { const_steps: 0n }),
      (error) => {
        ok(error instanceof CompilerError || error instanceof SourceError);
        equal(error.code, "const_budget");
        return true;
      },
    );
    const edited = await compiler.compile(source.replace("40 1", "40 2"));
    equal(await value(edited.artifact.bytes), 43);
    equal(edited.stats.result_reused, false);
    ok(edited.stats.declarations_reused > 0);
  } finally {
    await compiler.dispose();
  }
});

Deno.test("Carp project sessions invalidate imports and restore valid revisions", async () => {
  const entry = new URL("file:///carp-test/main.blot");
  const library = new URL("file:///carp-test/lib.blot");
  const files = new Map([
    [
      entry.href,
      'import * as lib from "./lib"\nentry const answer = fn () => lib.value ()\n',
    ],
    [library.href, "const value = fn () => 42\n"],
  ]);
  const compiler = await createCarpProjectCompiler({
    prelude: "none",
    threads: 4,
    readSource: (url) => {
      const source = files.get(url.href);
      if (source === undefined) throw new Error(`missing ${url}`);
      return Promise.resolve(source);
    },
  });
  async function answer() {
    const result = await compiler.compile(entry);
    const guest = await instantiateGuest(result.artifact.bytes);
    try {
      return { value: guest.call("answer", null), stats: result.stats };
    } finally {
      guest.dispose();
    }
  }
  try {
    equal((await answer()).value, 42);
    equal((await answer()).stats.result_reused, true);
    files.set(library.href, "const value = fn () => 43\n");
    const changed = await answer();
    equal(changed.value, 43);
    equal(changed.stats.declarations_sent, 1);
    files.set(library.href, "const value = fn () => missing\n");
    await rejects(answer, (error) => {
      ok(error instanceof SourceError);
      equal(error.origin?.filename, "/carp-test/lib.blot");
      return true;
    });
    files.set(library.href, "const value = fn () => 43\n");
    equal((await answer()).value, 43);
  } finally {
    await compiler.dispose();
  }
});

Deno.test("Carp const evaluation has stack-safe continuations and budget recovery", async () => {
  const compiler = await createCarpCompiler({ prelude: "none", threads: 4 });
  const source = `const count = fn value => case @u32.eq value 0 of
  True => 0
  False => count (@u32.sub value 1)
entry const answer = count 20000
`;
  try {
    await rejects(
      () => compiler.compile(source, { const_steps: 10n }),
      (error) => {
        ok(error instanceof CompilerError || error instanceof SourceError);
        equal(error.code, "const_budget");
        return true;
      },
    );
    const artifact = await compiler.compile(source, {
      const_steps: 2_000_000n,
    });
    equal(artifact.analysis.constants, [{
      name: "answer",
      value: { $: "U32Value", value: 0 },
    }]);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.read("answer"), 0);
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
  }
});

Deno.test("Carp serial and parallel compilation are byte-for-byte deterministic", async () => {
  const one = await createCarpCompiler({ prelude: "none", threads: 1 });
  const four = await createCarpCompiler({ prelude: "none", threads: 4 });
  const source = Array.from(
    { length: 128 },
    (_, i) => `entry const f${i} = fn (x: U32) => @u32.add x ${i}`,
  ).join("\n") + "\n";
  try {
    const [a, b, c] = await Promise.all([
      one.compile(source),
      four.compile(source),
      four.compile(source),
    ]);
    equal(a, b);
    equal(b, c);
    const invalid = source + "entry const invalid = not_defined\n";
    let first: unknown;
    try {
      await one.compile(invalid);
    } catch (error) {
      first = error;
    }
    ok(first instanceof SourceError);
    await rejects(() => four.compile(invalid), (error) => {
      ok(error instanceof SourceError);
      equal([error.code, error.start, error.end, error.message], [
        first.code,
        first.start,
        first.end,
        first.message,
      ]);
      return true;
    });
  } finally {
    await one.dispose();
    await four.dispose();
  }
});
