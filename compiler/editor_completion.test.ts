import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { readCompletion } from "./editor_completion.ts";
import { createZigProjectCompiler } from "./zig_project_client.ts";
import { jsonAssetParser } from "./assets.ts";

const executable = Deno.args[0] ??
  new URL("../zig-native/zig-out/bin/blotc", import.meta.url);
const encoder = new TextEncoder();
const echo = { revision: 0, snapshot: 7, filename: "/query.blot", position: 3 };
function reply() {
  return {
    ...echo,
    epoch: "1",
    success: true,
    replace: { start: 3, end: 3 },
    context: null,
    items: [{
      label: "value",
      insertText: "value",
      kind: "value",
      detail: "U32",
      match: "exact",
    }],
    truncated: false,
    diagnostics: [],
  };
}
function decode(metadata: unknown, payload = new Uint8Array()) {
  return readCompletion(
    metadata as Record<string, unknown>,
    echo,
    "1",
    payload,
    encoder.encode("雪\n"),
    (value) => value as never,
    (message) => {
      throw new Error(message);
    },
  );
}
Deno.test("completion replies own their fields and reject malformed ranges graphs names and echoes", () => {
  const source = reply();
  const owned = decode(source);
  ok(owned.success);
  source.items[0].label = "changed";
  equal(owned.items[0].label, "value");
  for (
    const bad of [
      { ...reply(), revision: 1 },
      { ...reply(), epoch: "old" },
      { ...reply(), snapshot: 8 },
      { ...reply(), filename: "/other" },
      { ...reply(), position: 4 },
      { ...reply(), context: {} },
      { ...reply(), replace: { start: 1, end: 3 } },
      { ...reply(), replace: { start: 3, end: 99 } },
      { ...reply(), items: [{ ...reply().items[0], extra: 1 }] },
      { ...reply(), items: [{ ...reply().items[0], kind: "snippet" }] },
      { ...reply(), items: [{ ...reply().items[0], match: "guessed" }] },
      { ...reply(), items: [{ ...reply().items[0], insertText: "\ud800" }] },
      { ...reply(), items: [{ ...reply().items[0], insertText: "" }] },
      {
        ...reply(),
        items: [{ ...reply().items[0], detail: "雪".repeat(342) }],
      },
      { ...reply(), items: Array(129).fill(reply().items[0]) },
      { ...reply(), diagnostics: Array(17).fill({}) },
    ]
  ) throws(() => decode(bad));
  throws(() => decode(reply(), Uint8Array.of(1)));
});

Deno.test("completion has no entry or build dependency and never publishes its repaired overlays", async () => {
  const directory = await Deno.makeTempDir();
  const entry = directory + "/main.blot";
  await Deno.writeTextFile(entry, "entry const answer = 42\n");
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
    cacheDirectory: false,
  });
  try {
    let snapshot = 0;
    const query = async (marked: string) => {
      const at = marked.indexOf("<cursor>");
      const text = marked.replace("<cursor>", "");
      return await compiler.complete({
        filename: entry,
        position: encoder.encode(marked.slice(0, at)).length,
        snapshot: ++snapshot,
        sources: { [entry]: text },
      });
    };
    const initial = await query(
      "// 雪\nconst work = fn (value: U32) -> U32 => va<cursor>\n",
    );
    ok(initial.success, JSON.stringify(initial));
    equal(initial.revision, 0);
    equal(initial.items.map((item) => [item.insertText, item.match]), [[
      "value",
      "exact",
    ]]);
    const owned = structuredClone(initial);
    const built = await compiler.build();
    ok(built.success);
    equal(built.revision, 1);
    const argument = await query(
      "const take = fn (value: U32) => value\nconst work = fn (value: U32) => take (<cursor>",
    );
    ok(argument.success, JSON.stringify(argument));
    equal(argument.items[0].insertText, "value");
    equal(argument.items[0].match, "exact");
    const rebinding = await query(
      "const work = fn (value: U32) => do:\n  value := @hole<cursor>",
    );
    ok(rebinding.success, JSON.stringify(rebinding));
    const context = rebinding.context;
    ok(context);
    for (const name of ["value", "self"]) {
      const index: number = context.scope.findIndex((entry) =>
        entry.name === name
      );
      ok(index >= 0, name);
      equal(context.nodes[context.scope[index].type].kind, "u32");
    }
    const generic = await query(
      'type Add a is contract = { associated "add" a a a }\nconst twice: a -> a where { Add a } = fn value => value\nconst work: a -> a where { Add a } = tw<cursor>',
    );
    ok(generic.success, JSON.stringify(generic));
    equal(generic.items[0].match, "compatible");
    const conflicting = await query(
      'type Add a is contract = { associated "add" a a a }\nconst twice: a -> a where { Add a } = fn value => value\nconst work: a -> a = tw<cursor>',
    );
    ok(conflicting.success, JSON.stringify(conflicting));
    equal(conflicting.items[0].match, "unknown");
    const missing = await compiler.complete({
      filename: directory + "/missing.blot",
      position: 0,
      snapshot: ++snapshot,
    });
    ok(!missing.success);
    equal(missing.diagnostics[0].code, "missing_source");
    equal(missing.revision, 1);
    await rejects(
      compiler.complete({
        filename: "/" + "雪".repeat(1366),
        position: 0,
        snapshot: ++snapshot,
      }),
      RangeError,
    );
    await rejects(
      compiler.complete({
        filename: entry,
        position: 1,
        snapshot: ++snapshot,
        sources: { [entry]: "雪" },
      }),
      /position/,
    );
    const later = await compiler.build();
    ok(later.success);
    equal(later.revision, 2);
    equal(later.bytes, built.bytes);
    await compiler.dispose();
    equal(initial, owned);
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("asset completion reads generated names without publishing parser caches or resources", async () => {
  const directory = await Deno.makeTempDir();
  const entry = directory + "/main.blot";
  await Deno.writeTextFile(directory + "/config.json", '{"offset":42}');
  await Deno.writeTextFile(
    entry,
    'import * as config from "./asset"\nentry const answer = (config.value).offset\n',
  );
  let parses = 0;
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
    cacheDirectory: false,
    assets: {
      "./asset": {
        path: "./config.json",
        parser(context) {
          parses++;
          return jsonAssetParser(context);
        },
      },
    },
  });
  try {
    const text = 'import * as config from "./asset"\nconst work = config.va';
    const result = await compiler.complete({
      filename: entry,
      position: encoder.encode(text).length,
      snapshot: 1,
      sources: { [entry]: text },
    });
    ok(result.success, JSON.stringify(result));
    equal(result.revision, 0);
    equal(result.items.map((item) => item.insertText), ["value"]);
    equal(parses, 1);
    const built = await compiler.build();
    ok(built.success, JSON.stringify(built));
    equal(built.revision, 1);
    equal(parses, 2);
    equal(built.assetStats?.parsed, 1);
    await compiler.complete({
      filename: entry,
      position: encoder.encode(text).length,
      snapshot: 2,
      sources: { [entry]: text },
    });
    equal(parses, 2);
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("completion retains the deterministic best prefix in an oversized semantic scope", async () => {
  const directory = await Deno.makeTempDir();
  const entry = directory + "/main.blot";
  const names = Array.from(
    { length: 4200 },
    (_, index) => "candidate" + String(index).padStart(4, "0"),
  );
  const text = names.map((name) => `const ${name}: U32 = 0`).join("\n") +
    "\nconst work = fn () -> U32 => candidate";
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
    cacheDirectory: false,
  });
  try {
    const query = {
      filename: entry,
      position: encoder.encode(text).length,
      snapshot: 1,
      sources: { [entry]: text },
    };
    const first = await compiler.complete(query);
    const second = await compiler.complete({ ...query, snapshot: 2 });
    ok(first.success, JSON.stringify(first));
    ok(second.success, JSON.stringify(second));
    equal(first.items.map((item) => item.insertText), names.slice(0, 128));
    equal(first.items, second.items);
    ok(
      first.items.every((item) =>
        item.match === "exact" || item.match === "unknown"
      ),
    );
    equal(first.truncated, true);
    equal(first.diagnostics[0].code, "completion_limit");
    ok(encoder.encode(JSON.stringify(first)).length <= 256 * 1024);
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("completion bounds asset parser failure messages at a UTF-8 boundary", async () => {
  const directory = await Deno.makeTempDir();
  const entry = directory + "/main.blot";
  await Deno.writeTextFile(
    entry,
    'import * as config from "./asset"\nconst work = config.va',
  );
  await Deno.writeTextFile(directory + "/config.json", "{}");
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: null,
    cacheDirectory: false,
    assets: {
      "./asset": {
        path: "./config.json",
        parser() {
          throw new Error("雪".repeat(1000));
        },
      },
    },
  });
  try {
    const result = await compiler.complete({
      filename: entry,
      position: 0,
      snapshot: 1,
    });
    ok(!result.success);
    equal(result.revision, 0);
    equal(encoder.encode(result.diagnostics[0].message).length, 1023);
    equal(result.diagnostics[0].message, "雪".repeat(341));
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
