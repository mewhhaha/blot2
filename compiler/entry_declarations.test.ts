import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { instantiateGuest, readGuestAbi } from "./guest.ts";
import { createIncrementalCompiler } from "./incremental.ts";
import { createNativeCompiler } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { createNativeProjectCompiler } from "./native_project.ts";
import { createSourceCompiler } from "./source.ts";
import { loadSourceProject, type SourceProject } from "./source_project.ts";
import { createFrontend, SourceError } from "./syntax.ts";

function exportNames(bytes: Uint8Array<ArrayBuffer>) {
  const module = new WebAssembly.Module(bytes);
  const abi = readGuestAbi(module);
  const raw = WebAssembly.Module.exports(module).map((item) => item.name)
    .filter((name) => !name.startsWith("blot:"))
    .sort();
  equal(
    raw,
    [...abi.functions, ...abi.constants].map((item) => item.name)
      .sort(),
  );
  return {
    functions: abi.functions.map((fn) => fn.name).sort(),
    constants: abi.constants.map((constant) => constant.name).sort(),
  };
}

function names(values: readonly { readonly name: string }[]) {
  return values.map((value) => value.name);
}

function inMemory(modules: Record<string, string>) {
  return {
    readSource(url: URL) {
      const source = modules[url.pathname.slice(1)];
      if (source === undefined) {
        return Promise.reject(new Deno.errors.NotFound(url.href));
      }
      return Promise.resolve(source);
    },
  };
}

function project(
  entry: string,
  modules: Record<string, string>,
): Promise<SourceProject> {
  return loadSourceProject(new URL(`file:///${entry}`), inMemory(modules));
}

function sourceError(code: string, start?: number, filename?: string) {
  return (error: unknown) => {
    ok(error instanceof SourceError, String(error));
    equal(error.code, code, error.message);
    if (start !== undefined) equal(error.start, start, error.message);
    if (filename !== undefined) equal(error.origin?.filename, filename);
    return true;
  };
}

const exported = `
const helper = fn (value: U32) => value + 1
const unused_helper = fn (value: U32) => value * 3
const adder = fn (step: U32) => fn (value: U32) => value + step
const internal: U32 = 7
entry const inferred = fn value => @u32.add value 1
entry const annotated: U32 -> U32 = fn value => helper value
entry const lambda = fn (value: U32) -> U32 => value * 2
entry const answer = 42
entry const typed: F32 = 1.5
entry const add_ten = adder 10
entry const array_first = fn (values: Array U32) => values[0]
entry let counter: U32 = helper 41
entry let runtime = fn (value: U32) => helper value
entry let add_five = adder 5
`;

Deno.test("entry const and entry let export exactly the entry declarations", async () => {
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler({ threads: 4 });
  try {
    const artifact = reference.compile(exported);
    equal(await native.compile(exported), artifact);
    equal(exportNames(artifact.bytes), {
      functions: [
        "add_five",
        "add_ten",
        "annotated",
        "array_first",
        "inferred",
        "lambda",
        "runtime",
      ],
      constants: ["answer", "counter", "typed"],
    });
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("inferred", 41), 42);
      equal(guest.call("annotated", 41), 42);
      equal(guest.call("lambda", 21), 42);
      equal(guest.call("add_ten", 32), 42);
      equal(guest.call("runtime", 41), 42);
      equal(guest.call("add_five", 37), 42);
      equal(guest.read("answer"), 42);
      equal(guest.read("typed"), 1.5);
      equal(guest.read("counter"), 42);
    } finally {
      guest.dispose();
    }
    // Declarations the entries do not reach are neither checked finally,
    // evaluated nor emitted: the analysis lists only reachable declarations.
    const functions = names(artifact.analysis.functions);
    ok(!functions.includes("unused_helper"), functions.join(","));
    ok(functions.includes("helper"));
    const constants = names(artifact.analysis.constants);
    ok(!constants.includes("internal"), constants.join(","));
    // Wasm-only builds produce the same bytes.
    equal(
      (await native.compile(exported, { analysis: false })).bytes,
      artifact.bytes,
    );
    equal(
      (reference.compile(exported, { analysis: false })).bytes,
      artifact.bytes,
    );
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("entry is a contextual keyword and an ordinary name elsewhere", async () => {
  const source = `
type Holder is data = Holder { entry: U32 }
const entry = fn (entry: U32) => do:
  let (first, second) = (entry, entry)
  return @u32.add first second
const pick = fn holder => case holder of
  Holder { entry } => entry
const bind = fn (value: U32) => do:
  let entry = value
  return case entry of
    entry => entry
const project = fn (holder: Holder) => holder.entry
const lambda = fn entry => entry
entry const run = fn (value: U32) => do:
  let holder = Holder { entry: entry value }
  let Holder { entry: field } = holder
  return @u32.add (pick holder) (@u32.add (bind field) (project (lambda holder)))
`;
  const frontend = await createFrontend();
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    ok(frontend.parse(source).root);
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    equal(exportNames(artifact.bytes), { functions: ["run"], constants: [] });
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("run", 7), 42);
    } finally {
      guest.dispose();
    }
    // `entry const entry` declares an entrypoint named entry.
    const named = reference.compile("entry const entry = fn () => 7\n");
    equal(exportNames(named.bytes), { functions: ["entry"], constants: [] });
    equal(await native.compile("entry const entry = fn () => 7\n"), named);
  } finally {
    frontend.dispose();
    reference.dispose();
    await native.dispose();
  }
});

const library = `
type Box is data = Box U32
const base = 40
const unbox = fn (box: Box) => case box of
  Box value => value
const unused = fn (value: U32) => value
`;

const application = `
import * as lib from "./lib"
import { base, Box } from "./lib"
const local = fn (value: U32) => value + 1
entry const answer = fn () => lib.unbox (Box (local (base + 1)))
entry const twice = fn (value: U32) => value + value
entry const four = fn () => twice 2
const also = fn () => four ()
entry const five = fn () => also () + 1
entry const base_alias = lib.base
`;

Deno.test("entry changes only exports and roots, never module visibility", async () => {
  const modules = { "lib.blot": library, "main.blot": application };
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler({ threads: 4 });
  try {
    const loaded = await project("main.blot", modules);
    const artifact = reference.compile(loaded);
    equal(await native.compile(loaded), artifact);
    equal(exportNames(artifact.bytes), {
      functions: ["answer", "five", "four", "twice"],
      constants: ["base_alias"],
    });
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("answer", null), 42);
      equal(guest.call("four", null), 4);
      equal(guest.call("five", null), 5);
      equal(guest.read("base_alias"), 40);
    } finally {
      guest.dispose();
    }
    const functions = names(artifact.analysis.functions);
    ok(!functions.includes("$module[lib].unused"), functions.join(","));
    // Only the entry module reaches the host. A library, or an application
    // imported by another build, cannot declare entrypoints.
    for (
      const [entry, files, filename, start] of [
        [
          "main.blot",
          {
            "lib.blot": library + "entry const leaked = fn () => base\n",
            "main.blot": application,
          },
          "/lib.blot",
          library.length,
        ],
        [
          "tool.blot",
          {
            ...modules,
            "tool.blot":
              'import { twice } from "./main"\nentry const run = fn () => twice 21\n',
          },
          "/main.blot",
          application.indexOf("entry const base_alias"),
        ],
      ] as const
    ) {
      const loadedProject = await project(entry, files);
      throws(
        () => reference.compile(loadedProject),
        sourceError("entry_outside_entry_module", start, filename),
      );
      await rejects(
        () => native.compile(loadedProject),
        sourceError("entry_outside_entry_module", start, filename),
      );
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("entry diagnostics cover ABI misfits, runtime values, missing entries and unused declarations", async () => {
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    for (
      const [source, code, message] of [
        [
          "entry const pair = fn (value: U32) => (value, value)\n",
          "entry_type",
          "does not fit the guest ABI",
        ],
        [
          "entry const values: Array U32 = [1, 2]\n",
          "entry_type",
          "does not fit the guest ABI",
        ],
        [
          "entry const identity = fn value => value\n",
          "entry_type",
          "generic type",
        ],
        [
          "effect Reader.ask: Unit -> U32\nentry const read = fn () => Reader.ask ()\n",
          "entry_type",
          "does not fit the guest ABI",
        ],
        [
          "entry let values: Array U32 = [1, 2]\n",
          "entry_let_type",
          "runtime-initialized",
        ],
        [
          "pub const answer = fn () => 42\n",
          "unknown_modifier",
          "only `entry`",
        ],
      ] as const
    ) {
      const expected = (error: unknown) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code, error.message);
        ok(error.message.includes(message), error.message);
        return true;
      };
      throws(() => reference.compile(source), expected);
      await rejects(() => native.compile(source), expected);
      // Analysis reports the same diagnostic.
      throws(() => reference.analyze(source), expected);
      await rejects(() => native.analyze(source), expected);
    }
    // A build needs an entrypoint; analysis alone may have none.
    const library = "const helper = fn (value: U32) => value + 1\n";
    for (const options of [{}, { analysis: false }] as const) {
      throws(
        () => reference.compile(library, options),
        sourceError("no_entry"),
      );
      await rejects(
        () => native.compile(library, options),
        sourceError("no_entry"),
      );
    }
    equal(reference.analyze(library).functions, []);
    equal(await native.analyze(library), reference.analyze(library));
    // Every declaration still passes the initial type check.
    const typeError = "const unused = fn () => @u32.add True 1\n" +
      "entry const answer = fn () => 42\n";
    throws(() => reference.compile(typeError), sourceError("type_mismatch"));
    await rejects(
      () => native.compile(typeError),
      sourceError("type_mismatch"),
    );
    throws(() => reference.analyze(typeError), sourceError("type_mismatch"));
    await rejects(
      () => native.analyze(typeError),
      sourceError("type_mismatch"),
    );
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("unreachable declarations are not evaluated, specialized, initialized or emitted", async () => {
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler({ threads: 4 });
  try {
    const source = `
const count = fn (value: U32) => case @u32.eq value 0 of
  True => 0
  False => count (@u32.sub value 1)
const exhausted = count 100000000
const panicked: U32 = @panic "never evaluated"
let startup: U32 = @panic "never initialized"
const generic = fn value => value + value
const mismatched = fn () => True + False
entry const answer = fn () => 42
entry const doubled = fn (value: U32) => value * 2
`;
    const artifact = reference.compile(source, { const_steps: 1000n });
    equal(await native.compile(source, { const_steps: 1000n }), artifact);
    equal(exportNames(artifact.bytes), {
      functions: ["answer", "doubled"],
      constants: [],
    });
    const functions = names(artifact.analysis.functions);
    for (const name of ["count", "generic", "mismatched"]) {
      ok(
        !functions.some((fn) => fn === name || fn.includes(`${name}`)),
        `${name} in ${functions.join(",")}`,
      );
    }
    equal(names(artifact.analysis.constants), []);
    equal(artifact.analysis.remaining_steps, 1000n);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("answer", null), 42);
      equal(guest.call("doubled", 21), 42);
    } finally {
      guest.dispose();
    }
    // The same declarations fail once an entry reaches them.
    for (
      const [root, code] of [
        ["entry const reached = exhausted\n", "const_budget"],
        ["entry const reached = panicked\n", "const_panic"],
        [
          "entry const reached = fn () => mismatched ()\n",
          "missing_associated",
        ],
      ] as const
    ) {
      const expected = (error: unknown) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code, error.message);
        return true;
      };
      throws(
        () => reference.compile(source + root, { const_steps: 1000n }),
        expected,
      );
      await rejects(
        () => native.compile(source + root, { const_steps: 1000n }),
        expected,
      );
    }
    // A reachable let initializer runs when the module starts.
    const started = reference.compile(
      source + "entry const read = fn () => startup\n",
    );
    throws(
      () => new WebAssembly.Instance(new WebAssembly.Module(started.bytes)),
      WebAssembly.RuntimeError,
    );
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("unused constructor and effect wrappers add no Wasm code", async () => {
  const base = "entry const run = fn () => 42\n";
  const unused = base +
    "type Dead is data = Dead U32\n" +
    "effect Unused.ping: Unit -> Unit\n";
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const expected = reference.compile(base);
    for (const source of [base, unused]) {
      const artifact = reference.compile(source);
      equal(artifact.bytes, expected.bytes);
      equal(await native.compile(source), artifact);
      equal(exportNames(artifact.bytes), {
        functions: ["run"],
        constants: [],
      });
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("a reached constructor value keeps its wrapper", async () => {
  const source = "type Box is data = Box U32\n" +
    "const make = Box\n" +
    "entry const run = fn () => case make 42 of\n  Box value => value\n";
  const reference = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none" });
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      equal(guest.call("run", null), 42);
    } finally {
      guest.dispose();
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("sessions key declarations by their entry modifier", async () => {
  const revisions = [
    "entry const a = fn () => 1\nconst b = fn () => 2\n",
    "entry const a = fn () => 1\nentry const b = fn () => 2\n",
    "const a = fn () => 1\nentry const b = fn () => 2\n",
    "entry const a = fn () => 1\nconst b = fn () => 2\n",
  ];
  const session = await createNativeIncrementalCompiler({ threads: 4 });
  const jsSession = await createIncrementalCompiler();
  const clean = await createNativeCompiler({ threads: 4 });
  const modules: Record<string, string> = { "lib.blot": library };
  const projects = await createNativeProjectCompiler({
    threads: 4,
    ...inMemory(modules),
  });
  try {
    for (const source of revisions) {
      const expected = await clean.compile(source);
      const actual = await session.compile(source);
      equal(actual.artifact, expected);
      equal((await jsSession.compile(source)).artifact.bytes, expected.bytes);
      modules["main.blot"] = 'import * as lib from "./lib"\n' + source;
      const fromProject = await projects.compile(
        new URL("file:///main.blot"),
      );
      equal(
        exportNames(fromProject.artifact.bytes),
        exportNames(expected.bytes),
      );
    }
    await rejects(
      () => session.compile("const a = fn () => 1\n"),
      sourceError("no_entry"),
    );
    await rejects(
      () => jsSession.compile("const a = fn () => 1\n"),
      sourceError("no_entry"),
    );
    equal(
      (await session.compile(revisions[0])).artifact,
      await clean.compile(revisions[0]),
    );
  } finally {
    await session.dispose();
    jsSession.dispose();
    await clean.dispose();
    await projects.dispose();
  }
});
