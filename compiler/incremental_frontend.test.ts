import {
  deepStrictEqual as equal,
  ok,
  strictEqual,
  throws,
} from "node:assert/strict";
import { bendArray } from "./bend_list.ts";
import { CompilerError } from "./diagnostics.ts";
import { createIncrementalFrontend } from "./incremental_frontend.ts";
import { createFrontend, type Cst, SourceError } from "./syntax.ts";

type Incremental = Awaited<ReturnType<typeof createIncrementalFrontend>>;
type Prepared = ReturnType<Incremental["prepare"]>;

function physicalOffset(prepared: Prepared, identity: bigint): number {
  try {
    prepared.translate(
      new CompilerError({
        code: "test_origin",
        subject: `offset:${identity}`,
        message: "test source origin",
      }),
    );
  } catch (error) {
    ok(error instanceof SourceError);
    equal(error.code, "test_origin");
    return error.start;
  }
  throw new Error("Origin translation did not reject the diagnostic");
}

function flattened(root: Cst, offsetAt = (offset: bigint) => Number(offset)) {
  const result: unknown[] = [];
  const pending = [root];
  for (let node = pending.pop(); node; node = pending.pop()) {
    const children = bendArray(node.children);
    result.push([
      node.kind,
      node.field,
      node.text,
      node === root ? 0 : offsetAt(node.offset),
      children.length,
    ]);
    for (let index = children.length - 1; index >= 0; index--) {
      pending.push(children[index]);
    }
  }
  return result;
}

function diagnostic(action: () => unknown): SourceError {
  try {
    action();
  } catch (error) {
    ok(error instanceof SourceError, String(error));
    return error;
  }
  throw new Error("Expected source rejection");
}

async function withFrontends(
  run: (
    incremental: Incremental,
    clean: Awaited<ReturnType<typeof createFrontend>>,
    equivalent: (source: string) => Prepared,
  ) => void,
) {
  const incremental = await createIncrementalFrontend({ prelude: "none" });
  const clean = await createFrontend();
  try {
    run(incremental, clean, (source) => {
      const actual = incremental.prepare(source);
      const expected = clean.parse(source);
      equal(actual.nodeCount, expected.nodeCount + incremental.preludeCount);
      const offsets = new Map<bigint, number>();
      equal(
        flattened(actual.root, (identity) => {
          if (!offsets.has(identity)) {
            offsets.set(identity, physicalOffset(actual, identity));
          }
          return offsets.get(identity)!;
        }),
        flattened(expected.root),
      );
      return actual;
    });
  } finally {
    incremental.dispose();
    clean.dispose();
  }
}

Deno.test("frontend body edits parse one island and preserve untouched syntax identities", () =>
  withFrontends((incremental, _clean, equivalent) => {
    const source = Array.from(
      { length: 64 },
      (_, index) => `fn value_${index} input => @u32.add input ${index}\n`,
    ).join("");
    const first = equivalent(source);
    equal(first.syntax.full_parses, 1);
    const revision = source.replace("input 32\n", "input 42\n");
    const changed = equivalent(revision);
    equal(changed.syntax, {
      source_reused: false,
      islands_parsed: 1,
      islands_reused: 63,
      full_parses: 0,
      characters_lexed: revision.length,
      characters_reused: 0,
    });
    const before = bendArray(first.root.children);
    const after = bendArray(changed.root.children);
    for (let index = 0; index < before.length; index++) {
      if (index !== 32) strictEqual(after[index], before[index]);
    }
    const repeated = incremental.prepare(revision);
    strictEqual(repeated.root, changed.root);
    equal(repeated.syntax, {
      source_reused: true,
      islands_parsed: 0,
      islands_reused: 64,
      full_parses: 0,
      characters_lexed: 0,
      characters_reused: revision.length,
    });
    ok(Object.isFrozen(changed.root));
    ok(Object.isFrozen(after[0].children));
  }));

Deno.test("frontend reuses tokens across trivia, CRLF, insertion, removal, and reorder", () =>
  withFrontends((_incremental, _clean, equivalent) => {
    const left = "fn left value => @u32.add value 1\n";
    const right = "fn right value => @u32.add value 2\n";
    const first = equivalent(left + right);
    const trivia = equivalent(
      "// Unicode 🙂 and keywords fn const of are trivia.\r\n\r\n" +
        (left + right).replaceAll("value =>", "value  =>").replaceAll(
          "\n",
          "\r\n",
        ),
    );
    equal(trivia.syntax.islands_parsed, 0);
    equal(trivia.syntax.islands_reused, 2);
    equal(trivia.root, first.root);
    const inserted = equivalent("const unrelated = 7\n" + left + right);
    equal(inserted.syntax.islands_parsed, 1);
    equal(inserted.syntax.islands_reused, 2);
    equal(equivalent(right + left).syntax.islands_parsed, 0);
    equal(equivalent(right).syntax.islands_parsed, 0);
    // Removed islands are not an unbounded historical cache.
    equal(equivalent(left + right).syntax.islands_parsed, 1);
    equal(equivalent("").syntax.islands_parsed, 0);
    equivalent("// Only a comment, without a final newline");
  }));

Deno.test("warm frontend lexes only changed fragments and evicts removed fragments", () =>
  withFrontends((incremental, clean, equivalent) => {
    const left = "fn left value => @u32.add value 1\r\n";
    const right = "fn right value => @u32.add value 2\r\n";
    const warm = left.replace("value 1", "value 3");
    equivalent(left + right);
    equivalent(warm + right);
    const edited = warm.replace("value 3", "value 4");
    const changed = equivalent(edited + right);
    equal(changed.syntax.characters_lexed, edited.length);
    equal(changed.syntax.characters_reused, right.length);
    equal(changed.syntax.islands_parsed, 1);
    equal(changed.syntax.islands_reused, 1);
    const reordered = equivalent(right + edited);
    equal(reordered.syntax.characters_lexed, 0);
    equal(reordered.syntax.characters_reused, right.length + edited.length);

    const malformed = right + edited.replace("value 4", "(value 4");
    const expected = diagnostic(() => clean.parse(malformed));
    const actual = diagnostic(() => incremental.prepare(malformed));
    equal([actual.code, actual.start], [expected.code, expected.start]);
    // Failed revisions must not publish their partially constructed caches.
    equal(equivalent(edited + right).syntax.characters_lexed, 0);
    equal(equivalent(right).syntax.characters_lexed, 0);
    const restored = equivalent(edited + right);
    equal(restored.syntax.characters_lexed, edited.length);
    equal(restored.syntax.characters_reused, right.length);
  }));

Deno.test("frontend islands retain nested suites, delimiters, records and token spellings", () =>
  withFrontends((_incremental, _clean, equivalent) => {
    const source = `data Pair = Pair { left: U32, right: U32 }
const text = "fn fake () => [case value of] // still text"
fn choose input => do:
  let values = [
    Pair { left: 1, right: 2 },
    Pair { left: 3, right: 4 },
  ]
  if True:
    return case input of
      (True, number) => number
      (False, _) => 0
  return @array.length values
export fn answer () => choose (True, 41)
`;
    equivalent(source);
    for (
      const revision of [
        source.replace("True, 41", "True, 42"),
        source.replace("left: 3", "left: 0xFFFF_FFFF"),
        source.replace("right: 4", "right: 4_096"),
        source.replace("still text", "still {new} text"),
        source.replace("=> number", "=> do:\n        return number"),
      ]
    ) {
      const parsed = equivalent(revision);
      equal(parsed.syntax.full_parses, 0);
      ok(parsed.syntax.islands_reused >= 2);
    }
  }));

Deno.test("frontend malformed layout and boundaries retain exact clean diagnostics", () =>
  withFrontends((incremental, clean, equivalent) => {
    const valid = "fn first () => 1\nexport fn answer () => 42\n";
    equivalent(valid);
    for (
      const malformed of [
        " fn first () => 1\n",
        "fn first () => do:\n\treturn 1\n",
        "fn first () => do:\nreturn 1\n",
        "fn first () => do:\n  if True:\n    return 1\n return 2\n",
        "fn first () => (1\nexport fn answer () => 42\n",
        "fn first () => [1)\nexport fn answer () => 42\n",
        "fn first () => 1 export fn answer () => 42\n",
        "fn first () => case True of\n  True => 1\n  False =>\n",
        'fn first () => "unfinished\n',
        "fn first () => 1\n#[tag]\n",
        "fn first () => 1\n\uE000",
        "fn first () => 1\n@\n",
        'fn first () => 1\nimport * as imported from "./other"\n',
      ]
    ) {
      for (const revision of [malformed, "// shift 🙂\r\n" + malformed]) {
        const expected = diagnostic(() => clean.parse(revision));
        const actual = diagnostic(() => incremental.prepare(revision));
        equal(
          [actual.code, actual.message, actual.start, actual.end],
          [expected.code, expected.message, expected.start, expected.end],
          revision,
        );
      }
    }
    const recovered = equivalent(valid);
    equal(recovered.syntax.source_reused, true);
  }));

Deno.test("frontend attribute boundaries fall back to the complete grammar", () =>
  withFrontends((_incremental, _clean, equivalent) => {
    const source = "#[first]\n#[second]\nexport fn answer () => 41\n";
    equivalent(source);
    const changed = equivalent(source.replace("41", "42"));
    equal(changed.syntax.full_parses, 1);
    const removed = equivalent("export fn answer () => 42\n");
    equal(removed.syntax.islands_parsed, 1);
    equal(removed.syntax.full_parses, 0);
  }));

Deno.test("frontend origins belong to their source revision and imports cannot enter caches", () =>
  withFrontends((incremental, _clean, equivalent) => {
    const source = "fn capture value => fn extra => @u32.add value extra\n";
    const first = equivalent(source);
    const firstDeclaration = bendArray(first.root.children)[0];
    const prefix = "// shifted 😀\r\n\r\n";
    const second = equivalent(prefix + source);
    strictEqual(bendArray(second.root.children)[0], firstDeclaration);
    equal(physicalOffset(first, firstDeclaration.offset), 0);
    const namedOrigin = (prepared: Prepared) =>
      diagnostic(() =>
        prepared.translate(
          new CompilerError({
            code: "test_named_origin",
            subject: "main::capture",
            message: "test named source origin",
          }),
        )
      ).start;
    equal(namedOrigin(first), source.indexOf("capture"));
    equal(namedOrigin(second), prefix.length + source.indexOf("capture"));
    equal(physicalOffset(second, firstDeclaration.offset), prefix.length);
    equal(physicalOffset(first, firstDeclaration.offset), 0);
    const imported = prefix + 'import * as imported from "./other"\n' + source;
    const error = diagnostic(() => incremental.prepare(imported));
    equal(error.code, "module_loader_required");
    equal(error.start, prefix.length);
    equal(equivalent(prefix + source).syntax.source_reused, true);
    incremental.dispose();
    equal(namedOrigin(first), source.indexOf("capture"));
    equal(physicalOffset(second, firstDeclaration.offset), prefix.length);
    throws(() => incremental.prepare(source), /disposed/);
  }));

Deno.test("large lazy origin tables retain deep offsets across revisions and disposal", async () => {
  const incremental = await createIncrementalFrontend({ prelude: "none" });
  try {
    const source = "fn values () => [" +
      Array.from({ length: 8192 }, (_, index) => index).join(",") + "]\n";
    const first = incremental.prepare(source);
    const pending = [first.root];
    let literal: Cst | undefined;
    for (let node = pending.pop(); node; node = pending.pop()) {
      if (node.text === "8191") literal = node;
      pending.push(...bendArray(node.children));
    }
    ok(literal);
    const prefix = "// shifted 😀\r\n\r\n";
    const second = incremental.prepare(prefix + source);
    strictEqual(
      bendArray(first.root.children)[0],
      bendArray(second.root.children)[0],
    );
    equal(physicalOffset(first, literal.offset), source.indexOf("8191"));
    equal(
      physicalOffset(second, literal.offset),
      prefix.length + source.indexOf("8191"),
    );
    incremental.dispose();
    equal(physicalOffset(first, literal.offset), source.indexOf("8191"));
    equal(
      physicalOffset(second, literal.offset),
      prefix.length + source.indexOf("8191"),
    );
  } finally {
    incremental.dispose();
  }
});
