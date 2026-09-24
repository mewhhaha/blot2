import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import { NativeProcess } from "./native_process.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

type Session = Awaited<ReturnType<typeof createNativeIncrementalCompiler>>;

async function withSession(
  run: (
    compiler: Session,
    requests: () => number,
    clean: Awaited<ReturnType<typeof createSourceCompiler>>,
  ) => Promise<void>,
) {
  const request = NativeProcess.prototype.request;
  let requestCount = 0;
  NativeProcess.prototype.request = function (payload) {
    requestCount++;
    return request.call(this, payload);
  };
  let compiler: Session | undefined;
  let clean: Awaited<ReturnType<typeof createSourceCompiler>> | undefined;
  try {
    compiler = await createNativeIncrementalCompiler({ prelude: "none" });
    clean = await createSourceCompiler({ prelude: "none" });
    await run(compiler, () => requestCount, clean);
  } finally {
    await compiler?.dispose();
    clean?.dispose();
    NativeProcess.prototype.request = request;
  }
}

async function answer(bytes: Uint8Array<ArrayBuffer>) {
  const { instance } = await WebAssembly.instantiate(bytes);
  const exported = instance.exports.answer;
  ok(typeof exported === "function");
  return exported(0) as number;
}

function sourceError(code: string, start?: number) {
  return (error: unknown) => {
    ok(error instanceof SourceError, String(error));
    equal(error.code, code, error.message);
    if (start !== undefined) equal(error.start, start, error.message);
    return true;
  };
}

Deno.test("native unchanged and trivia revisions skip transport and isolate public results", () =>
  withSession(async (compiler, requests, clean) => {
    const source =
      `const saved = (fn offset => fn value => @u32.add value offset) 1
const calculated = saved 41
const answer = fn () => calculated
`;
    equal(requests(), 1);
    const first = await compiler.compile(source);
    const expected = structuredClone(first.artifact);
    const totalGroups = first.stats.groups_checked + first.stats.groups_reused;
    equal(first.artifact.bytes, clean.compile(source).bytes);
    equal(requests(), 2);
    first.artifact.bytes.fill(0);
    (first.artifact.analysis.constants as unknown[]).length = 0;
    Object.assign(first.stats, { groups_checked: 999, entries_compiled: 999 });
    const second = await compiler.compile(source);
    equal(second.artifact, expected);
    equal(second.stats.result_reused, true);
    equal(second.stats.source_reused, true);
    equal(second.stats.parsed_ms, 0);
    equal(second.stats.groups_reused, totalGroups);
    equal(requests(), 2);
    const saved = second.artifact.analysis.constants.find((entry) =>
      entry.name === "saved"
    );
    ok(saved?.value.$ === "ClosureValue");
    Object.assign(saved.value.body, { $: "U32Expr", value: 0 });
    const trivia = "// physical offsets shift 😀\r\n" +
      source.replaceAll("\n", "\r\n");
    const third = await compiler.compile(trivia);
    equal(third.artifact, expected);
    equal(third.artifact.bytes, clean.compile(trivia).bytes);
    equal(third.stats.result_reused, true);
    equal(third.stats.source_reused, false);
    equal(third.stats.islands_parsed, 0);
    equal(third.stats.islands_reused, 3);
    equal(requests(), 2);
    equal(await answer(third.artifact.bytes), 42);
    const edited = trivia.replace("offset) 1", "offset) 2");
    const changed = await compiler.compile(edited);
    equal(changed.artifact.bytes, clean.compile(edited).bytes);
    equal(changed.stats.result_reused, false);
    equal(changed.stats.islands_parsed, 1);
    equal(changed.stats.islands_reused, 2);
    equal(changed.stats.declarations_lowered, 1);
    equal(requests(), 3);
    equal(await answer(changed.artifact.bytes), 43);
  }));

Deno.test("native unchanged cache keys include operation and const budget, with success-only publication", () =>
  withSession(async (compiler, requests, clean) => {
    const source =
      "const value = @u32.add 40 2\nconst answer = fn () => value\n";
    const first = await compiler.compile(source, { const_steps: 100n });
    const sent = requests();
    await rejects(
      () => compiler.compile(source, { const_steps: 0n }),
      sourceError("const_budget"),
    );
    equal(requests(), sent + 1);
    const recovered = await compiler.compile(source, { const_steps: 100n });
    equal(recovered.artifact, first.artifact);
    equal(recovered.stats.result_reused, true);
    equal(requests(), sent + 1);
    const newBudget = await compiler.compile(source, { const_steps: 101n });
    equal(newBudget.stats.result_reused, false);
    equal(
      newBudget.artifact.analysis.remaining_steps,
      first.artifact.analysis.remaining_steps + 1n,
    );
    const analyzed = await compiler.analyze(source, { const_steps: 101n });
    equal(analyzed.stats.result_reused, false);
    equal(analyzed.analysis, newBudget.artifact.analysis);
    equal(
      (await compiler.analyze(source, { const_steps: 101n })).stats
        .result_reused,
      true,
    );
    const restoredMode = await compiler.compile(source, { const_steps: 101n });
    equal(restoredMode.stats.result_reused, false);
    equal(restoredMode.artifact.bytes, clean.compile(source).bytes);
    const invalid = "// revised\n" + source.replace("40 2", "True 2");
    await rejects(
      () => compiler.compile(invalid),
      sourceError("type_mismatch"),
    );
    const shifted = "// another offset\n" + invalid;
    await rejects(
      () => compiler.compile(shifted),
      sourceError("type_mismatch"),
    );
    const afterFailure = await compiler.compile(source, { const_steps: 101n });
    equal(afterFailure.artifact, restoredMode.artifact);
    equal(afterFailure.stats.result_reused, true);
  }));

Deno.test("native cached replies preserve queued revision order, option snapshots and disposal", () =>
  withSession(async (compiler, requests, clean) => {
    const source =
      "const value = @u32.add 40 1\nconst answer = fn () => value\n";
    await compiler.compile(source, { const_steps: 100n });
    const options = { const_steps: 100n };
    const ordered: string[] = [];
    const unchanged = compiler.compile(source, options).then((result) => {
      ordered.push("unchanged");
      return result;
    });
    const invalid = compiler.compile("const broken = fn () =>\n", options).then(
      () => {
        throw new Error("Expected malformed source to fail");
      },
      (error) => {
        ordered.push("invalid");
        ok(error instanceof SourceError);
      },
    );
    const changedSource = source.replace("40 1", "40 2");
    const changed = compiler.compile(changedSource, options).then((result) => {
      ordered.push("changed");
      return result;
    });
    options.const_steps = 0n;
    const [old, , next] = await Promise.all([unchanged, invalid, changed]);
    equal(ordered, ["unchanged", "invalid", "changed"]);
    equal(old.stats.result_reused, true);
    equal(await answer(old.artifact.bytes), 41);
    equal(next.artifact.bytes, clean.compile(changedSource).bytes);
    equal(await answer(next.artifact.bytes), 42);
    const sent = requests();
    const queued = compiler.compile(changedSource, { const_steps: 100n });
    const disposedReply = rejects(queued, /disposed/);
    await compiler.dispose();
    await disposedReply;
    await rejects(() => compiler.compile(source), /disposed/);
    equal(requests(), sent);
  }));
