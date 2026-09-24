import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { CompilerError } from "./diagnostics.ts";
import { NativeProcess } from "./native_process.ts";
import { createNativeProjectCompiler } from "./native_project.ts";
import { createSourceCompiler } from "./source.ts";
import { loadSourceProject } from "./source_project.ts";
import { SourceError } from "./syntax.ts";

const entry = new URL("file:///virtual-project/main.blot");
const library = new URL("file:///virtual-project/lib.blot");
const other = new URL("file:///virtual-project/other.blot");

function virtualProject(initial: ReadonlyMap<string, string>) {
  const files = new Map(initial);
  const readSource = (url: URL) => {
    const source = files.get(url.href);
    if (source === undefined) throw new Error(`Missing virtual module ${url}`);
    return Promise.resolve(source);
  };
  return { files, readSource };
}

async function answer(bytes: Uint8Array<ArrayBuffer>): Promise<number> {
  const module = await WebAssembly.compile(bytes);
  const instance = await WebAssembly.instantiate(module);
  const exported = instance.exports.answer;
  ok(typeof exported === "function");
  return exported() as number;
}

Deno.test("native project session reuses imported declarations and isolates returned artifacts", async () => {
  const { files, readSource } = virtualProject(
    new Map([
      [
        entry.href,
        'import * as lib from "./lib"\nconst answer = fn () => @u32.add (lib.value ()) 1\n',
      ],
      [
        library.href,
        "const value = fn () => 40\nconst independent = fn () => 99\n",
      ],
    ]),
  );
  const session = await createNativeProjectCompiler({
    prelude: "none",
    threads: 1,
    readSource,
  });
  try {
    const first = await session.compile(entry);
    equal(await answer(first.artifact.bytes), 41);
    const originalBytes = first.artifact.bytes.slice();
    first.artifact.bytes[0] = 0;
    (first.artifact.analysis.functions[0] as { name: string }).name = "corrupt";
    const unchanged = await session.compile(entry);
    equal(unchanged.stats.result_reused, true);
    equal(unchanged.stats.declarations_sent, 0);
    equal(unchanged.artifact.bytes, originalBytes);
    ok(
      unchanged.artifact.analysis.functions.every((fn) =>
        fn.name !== "corrupt"
      ),
    );

    files.set(
      library.href,
      "// trivia in imported module\n" + files.get(library.href),
    );
    const trivia = await session.compile(entry);
    equal(trivia.stats.result_reused, true);
    equal(trivia.stats.declarations_sent, 0);
    equal(await answer(trivia.artifact.bytes), 41);

    files.set(
      library.href,
      files.get(library.href)!.replace("() => 40", "() => 41"),
    );
    const changed = await session.compile(entry);
    equal(changed.stats.result_reused, false);
    equal(changed.stats.declarations_sent, 1);
    ok(changed.stats.declarations_retained >= 2);
    equal(await answer(changed.artifact.bytes), 42);
  } finally {
    await session.dispose();
  }
});

Deno.test("native project session rolls back invalid imported edits and const budgets", async () => {
  const valid = "const base = @u32.add 40 1\nconst value = fn () => base\n";
  const { files, readSource } = virtualProject(
    new Map([
      [
        entry.href,
        'import * as lib from "./lib"\nconst answer = fn () => @u32.add (lib.value ()) 1\n',
      ],
      [library.href, valid],
    ]),
  );
  const session = await createNativeProjectCompiler({
    prelude: "none",
    threads: 1,
    readSource,
  });
  try {
    const first = await session.compile(entry, { const_steps: 100n });
    equal(await answer(first.artifact.bytes), 42);
    const invalid =
      "// shifted location\nconst base = @u32.add 40 missing_value\nconst value = fn () => base\n";
    files.set(library.href, invalid);
    await rejects(
      () => session.compile(entry, { const_steps: 100n }),
      (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, "unknown_value");
        equal(error.origin?.filename, "/virtual-project/lib.blot");
        equal(error.origin?.source, invalid);
        equal(error.start, invalid.indexOf("missing_value"));
        return true;
      },
    );
    files.set(library.href, valid);
    const recovered = await session.compile(entry, { const_steps: 100n });
    equal(await answer(recovered.artifact.bytes), 42);
    equal(recovered.stats.result_reused, true);
    await rejects(
      () => session.compile(entry, { const_steps: 0n }),
      (error) => {
        ok(error instanceof CompilerError, String(error));
        equal(error.code, "const_budget");
        return true;
      },
    );
    const afterBudgetFailure = await session.compile(entry, {
      const_steps: 100n,
    });
    equal(afterBudgetFailure.stats.result_reused, true);
    equal(await answer(afterBudgetFailure.artifact.bytes), 42);
  } finally {
    await session.dispose();
  }
});

Deno.test("native project session invalidates schema and import-target changes", async () => {
  const main =
    'import * as lib from "./lib"\nconst answer = fn () => lib.read (lib.make ())\n';
  const firstLibrary = `type Box is data = Box U32
const make = fn () => Box 40
const read = fn (box: Box) => case box of
  Box value => value
`;
  const secondLibrary = `type Box is data = Box Bool
const make = fn () => Box True
const read = fn (box: Box) => case box of
  Box True => 41
  Box False => 0
`;
  const { files, readSource } = virtualProject(
    new Map([
      [entry.href, main],
      [library.href, firstLibrary],
      [other.href, secondLibrary.replace("41", "43")],
    ]),
  );
  const session = await createNativeProjectCompiler({
    prelude: "none",
    threads: 1,
    readSource,
  });
  try {
    const first = await session.compile(entry);
    equal(await answer(first.artifact.bytes), 40);
    files.set(library.href, secondLibrary);
    const schema = await session.compile(entry);
    equal(schema.stats.result_reused, false);
    ok(schema.stats.declarations_sent > 0);
    equal(await answer(schema.artifact.bytes), 41);
    files.set(library.href, secondLibrary.replace("Box Bool", "Box Missing"));
    await rejects(() => session.compile(entry), (error) => {
      ok(error instanceof SourceError || error instanceof CompilerError);
      equal(error.code, "unsupported_type");
      return true;
    });
    files.set(library.href, secondLibrary);
    const afterInvalidSchema = await session.compile(entry);
    equal(afterInvalidSchema.stats.result_reused, true);
    equal(afterInvalidSchema.artifact.bytes, schema.artifact.bytes);
    files.set(entry.href, main.replace('"./lib"', '"./other"'));
    const importChanged = await session.compile(entry);
    equal(importChanged.stats.result_reused, false);
    ok(importChanged.stats.declarations_sent > 0);
    equal(await answer(importChanged.artifact.bytes), 43);

    const validImport = files.get(entry.href)!;
    files.set(entry.href, validImport.replace("as lib", "as renamed"));
    await rejects(() => session.compile(entry), (error) => {
      ok(error instanceof SourceError, String(error));
      equal(error.origin?.filename, "/virtual-project/main.blot");
      return true;
    });
    files.set(entry.href, validImport);
    const recovered = await session.compile(entry);
    equal(recovered.stats.result_reused, true);
    equal(await answer(recovered.artifact.bytes), 43);
  } finally {
    await session.dispose();
  }
});

Deno.test("project load timing excludes time waiting for an earlier compile", async () => {
  let releaseRead!: () => void;
  let reportRead!: () => void;
  const holdRead = new Promise<void>((resolve) => releaseRead = resolve);
  const readStarted = new Promise<void>((resolve) => reportRead = resolve);
  let reads = 0;
  const session = await createNativeProjectCompiler({
    prelude: "none",
    threads: 1,
    async readSource(url) {
      equal(url.href, entry.href);
      if (++reads === 1) {
        reportRead();
        await holdRead;
      }
      return "const answer = fn () => 42\n";
    },
  });
  try {
    const first = session.compile(entry);
    await readStarted;
    const second = session.compile(entry);
    await new Promise((resolve) => setTimeout(resolve, 100));
    releaseRead();
    const [initial, repeated] = await Promise.all([first, second]);
    equal(await answer(initial.artifact.bytes), 42);
    equal(repeated.stats.result_reused, true);
    ok(
      repeated.stats.total_ms - repeated.stats.project_ms >= 80,
      `queued ${repeated.stats.total_ms} ms, project ${repeated.stats.project_ms} ms`,
    );
  } finally {
    releaseRead();
    await session.dispose();
  }
});

Deno.test("native project session preserves clean operation order across imported effect rows", async () => {
  const original = `effect Ping: Unit -> U32
type Get a is effect = Unit -> a
const annotation_only = fn (callback: Unit -> U32 ! {Get U32}) => 0
const both = fn () => do:
  use first <- Ping ()
  use second <- Get U32 ()
  return @u32.add first second
`;
  const { files, readSource } = virtualProject(
    new Map([
      [
        entry.href,
        `import { Ping, Get, both } from "./lib"
const answer = fn () => do (@effect.provider Ping (fn () => 40)):
  return do (@effect.provider (Get U32) (fn () => 2)):
    return both ()
`,
      ],
      [library.href, original],
    ]),
  );
  const session = await createNativeProjectCompiler({
    prelude: "none",
    threads: 1,
    readSource,
  });
  const clean = await createSourceCompiler({ prelude: "none" });
  try {
    const first = await session.compile(entry);
    const firstOracle = clean.compile(
      await loadSourceProject(entry, {
        readSource,
      }),
    );
    equal(first.artifact.analysis, firstOracle.analysis);
    const both = first.artifact.analysis.functions.find((fn) =>
      fn.name.endsWith(".both")
    );
    ok(both);
    equal(both.effect_row.operations.length, 2);
    equal(
      both.effect_row.operations,
      firstOracle.analysis.functions.find((fn) => fn.name.endsWith(".both"))
        ?.effect_row.operations,
    );
    equal(await answer(first.artifact.bytes), 42);
    equal(await answer(firstOracle.bytes), 42);

    files.set(library.href, original.replace("=> 0", "=> 1"));
    const edited = await session.compile(entry);
    equal(edited.stats.declarations_sent, 1);
    const editedOracle = clean.compile(
      await loadSourceProject(entry, {
        readSource,
      }),
    );
    equal(edited.artifact.analysis, editedOracle.analysis);
    equal(await answer(edited.artifact.bytes), 42);
    equal(await answer(editedOracle.bytes), 42);
  } finally {
    clean.dispose();
    await session.dispose();
  }
});

Deno.test("native project process recycling resends complete revisions and keeps the last successful result", async () => {
  const { files, readSource } = virtualProject(
    new Map([
      [
        entry.href,
        'import * as lib from "./lib"\nconst answer = fn () => lib.value ()\n',
      ],
      [library.href, "const value = fn () => 40\nconst spare = fn () => 99\n"],
    ]),
  );
  const session = await createNativeProjectCompiler({
    prelude: "none",
    readSource,
    maxRevisions: 1,
  });
  const clean = await createSourceCompiler({ prelude: "none" });
  const oracle = async () =>
    clean.compile(await loadSourceProject(entry, { readSource }));
  try {
    const first = await session.compile(entry);
    equal(first.stats.session_restarted, false);
    equal(first.artifact.bytes, (await oracle()).bytes);
    equal((await session.compile(entry)).stats.result_reused, true);
    files.set(library.href, "// trivia\n" + files.get(library.href));
    const trivia = await session.compile(entry);
    equal(trivia.stats.result_reused, true);
    equal(trivia.stats.session_restarted, false);

    files.set(library.href, files.get(library.href)!.replace("40", "41"));
    const changed = await session.compile(entry);
    equal(changed.stats.session_restarted, true);
    equal(changed.stats.declarations_retained, 0);
    equal(changed.stats.declarations_sent, 3);
    equal(changed.artifact.bytes, (await oracle()).bytes);
    equal(await answer(changed.artifact.bytes), 41);

    files.set(library.href, files.get(library.href)!.replace("41", "missing"));
    await rejects(() => session.compile(entry), (error) => {
      ok(error instanceof SourceError, String(error));
      equal(error.code, "unknown_value");
      return true;
    });
    files.set(library.href, files.get(library.href)!.replace("missing", "41"));
    const recovered = await session.compile(entry);
    equal(recovered.stats.result_reused, true);
    equal(recovered.stats.session_restarted, false);
    equal(await answer(recovered.artifact.bytes), 41);

    files.set(library.href, files.get(library.href)!.replace("41", "42"));
    const afterFailure = await session.compile(entry);
    equal(afterFailure.stats.session_restarted, true);
    equal(afterFailure.stats.declarations_sent, 3);
    equal(afterFailure.stats.declarations_retained, 0);
    equal(afterFailure.artifact.bytes, (await oracle()).bytes);
    equal(await answer(afterFailure.artifact.bytes), 42);
  } finally {
    clean.dispose();
    await session.dispose();
  }
});

Deno.test("native project revision limit counts analyze requests and disposal stops queued revisions", async () => {
  let releaseRead!: () => void;
  let reportRead!: () => void;
  const held = new Promise<void>((resolve) => releaseRead = resolve);
  const reading = new Promise<void>((resolve) => reportRead = resolve);
  let blocked = false;
  const { files, readSource } = virtualProject(
    new Map([
      [entry.href, "const answer = fn () => 40\n"],
    ]),
  );
  const session = await createNativeProjectCompiler({
    prelude: "none",
    maxRevisions: 2,
    async readSource(url) {
      if (blocked) {
        reportRead();
        await held;
      }
      return readSource(url);
    },
  });
  try {
    const first = await session.compile(entry);
    equal(first.stats.session_restarted, false);
    const analyzed = await session.analyze(entry);
    equal(analyzed.stats.session_restarted, false);
    files.set(entry.href, "const answer = fn () => 41\n");
    const changed = await session.compile(entry);
    equal(changed.stats.session_restarted, true);
    equal(changed.stats.declarations_sent, 1);
    equal(changed.stats.declarations_retained, 0);
    equal(await answer(changed.artifact.bytes), 41);

    blocked = true;
    files.set(entry.href, "const answer = fn () => 42\n");
    const pending = session.compile(entry);
    await reading;
    const disposal = session.dispose();
    releaseRead();
    await rejects(pending, /disposed/);
    await disposal;
  } finally {
    releaseRead();
    await session.dispose();
  }
});

Deno.test("native project revision limit rejects non-positive values", async () => {
  for (const maxRevisions of [0, -1, 1.5, Infinity, NaN]) {
    await rejects(
      () => createNativeProjectCompiler({ maxRevisions }),
      RangeError,
    );
  }
});

Deno.test("disposing during process restart reaps the replacement before returning", async () => {
  const originalStart = NativeProcess.start;
  let releaseStart!: () => void;
  let reportStart!: () => void;
  const held = new Promise<void>((resolve) => releaseStart = resolve);
  const restarting = new Promise<void>((resolve) => reportStart = resolve);
  let starts = 0;
  let replacement: NativeProcess | undefined;
  NativeProcess.start = async (options) => {
    if (++starts === 2) {
      reportStart();
      await held;
      replacement = await originalStart(options);
      return replacement;
    }
    return originalStart(options);
  };
  const { files, readSource } = virtualProject(
    new Map([
      [entry.href, "const answer = fn () => 40\n"],
    ]),
  );
  let session:
    | Awaited<ReturnType<typeof createNativeProjectCompiler>>
    | undefined;
  try {
    session = await createNativeProjectCompiler({
      prelude: "none",
      maxRevisions: 1,
      readSource,
    });
    await session.compile(entry);
    files.set(entry.href, "const answer = fn () => 41\n");
    const pending = session.compile(entry);
    await restarting;
    const disposal = session.dispose();
    releaseStart();
    await rejects(pending, /disposed/);
    await disposal;
    ok(replacement);
    await rejects(replacement.request(new Uint8Array(0)), /disposed/);
  } finally {
    releaseStart();
    NativeProcess.start = originalStart;
    await session?.dispose();
  }
});
