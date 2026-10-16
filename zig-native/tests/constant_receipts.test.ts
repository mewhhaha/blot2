import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);

Deno.test("constant receipts restore growing collection frontiers across edits and failed revisions", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-constant-growth-" });
  const entry = `${directory}/main.blot`;
  const source = (sibling: string, count: number) => `
const grown: List U32 = do:
  let values = []
  for index in 0..${count}:
    values := if @u32.lt index 16 then @list.append values index else @list.prepend values index
  return values
const later = @list.prepend (@list.append grown 99) 100
entry const first = fn () => @array.from_list grown
entry const following = fn () => @array.from_list later
entry const sibling = ${sibling}
`;
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: false,
  } as const;
  const retained = await createZigProjectCompiler(options);
  try {
    const revisions = [
      ["1", 32],
      ["2", 32],
      ["3", 33],
      ["missing", 33],
      ["4", 33],
      ["5", 32],
      ["6", 32],
    ] as const;
    for (const [revision, [sibling, count]] of revisions.entries()) {
      const fresh = await createZigProjectCompiler(options);
      try {
        const sources = { [entry]: source(sibling, count) };
        const expected = await fresh.build({ sources });
        const actual = await retained.build({ sources });
        assert.equal(actual.success, expected.success);
        if (!expected.success || !actual.success) {
          assert.equal(sibling, "missing");
          assert.ok(!actual.success && !expected.success);
          assert.deepEqual(actual.diagnostics, expected.diagnostics);
          continue;
        }
        assert.deepEqual(actual.bytes, expected.bytes);
        assert.equal(
          actual.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
        if (revision === 1 || revision === 6) {
          const traffic = actual.stats.constantReceipts as Record<
            string,
            number
          >;
          assert.equal(traffic.reused, 1);
        }
        const values: number[] = [];
        for (let index = 0; index < count; index++) {
          if (index < 16) values.push(index);
          else values.unshift(index);
        }
        const guest = await instantiateGuest(actual.bytes);
        try {
          assert.deepEqual(guest.call("first", null), new Uint32Array(values));
          assert.deepEqual(
            guest.call("following", null),
            new Uint32Array([100, ...values, 99]),
          );
        } finally {
          await guest.dispose();
        }
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await retained.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("constant receipts retain qualified scalar and owning graphs with fresh bytes and fuel", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-constant-receipts-",
  });
  const entry = `${directory}/main.blot`;
  let expression = "1";
  for (let index = 0; index < 80; index++) {
    expression = `@u32.add 1 (${expression})`;
  }
  const source = (seed = "2", element = "40") =>
    `const seed = ${seed}
const expensive: U32 where { type_rep U32 } = do:
  let local = fn value => value
  return ${expression}
const collection = #[${
      Array.from({ length: 80 }, () => `@u32.add 0 (@u32.add 0 ${element})`)
        .join(", ")
    }]
entry const run = fn (value: U32) => @u32.add value (@u32.add expensive seed)
entry const owning = fn () => collection
`;
  const options = { executable, entry, prelude: null };
  const retained = await createZigProjectCompiler(options);
  try {
    const revisions = [
      [source(), 123, 40],
      [source("3"), 124, 40],
      [source("3", "41"), 124, 41],
      [source("missing_name"), null, null],
      [source("3"), 124, 40],
      [source(), 123, 40],
    ] as const;
    for (const [revision, [text, scalar, element]] of revisions.entries()) {
      const fresh = await createZigProjectCompiler(options);
      try {
        const sources = { [entry]: text };
        const expected = await fresh.build({ sources });
        const actual = await retained.build({ sources });
        assert.equal(actual.success, expected.success);
        if (!actual.success || !expected.success) {
          assert.ok(!actual.success && !expected.success);
          assert.deepEqual(actual.diagnostics, expected.diagnostics);
          if (scalar !== null) console.error(expected.diagnostics);
          assert.equal(scalar, null);
          continue;
        }
        assert.deepEqual(actual.bytes, expected.bytes);
        assert.equal(
          actual.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
        if (revision === 1) {
          const traffic = actual.stats.constantReceipts as {
            [key: string]: number;
          };
          assert.ok(
            traffic.reused >= 2,
            JSON.stringify({
              actual: traffic,
              fresh: expected.stats.constantReceipts,
            }),
          );
          assert.ok(traffic.source_steps_replayed > 200);
        }
        const guest = await instantiateGuest(actual.bytes);
        try {
          assert.equal(guest.call("run", 40), scalar);
          assert.ok(element !== null);
          assert.deepEqual(
            guest.call("owning", null),
            new Uint32Array(Array.from({ length: 80 }, () => element)),
          );
        } finally {
          await guest.dispose();
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("subfloor scalars stay ordinary while compound graphs replay exact value work", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-constant-floor-" });
  const entry = `${directory}/main.blot`;
  let small = "1";
  for (let index = 0; index < 52; index++) small = `@u32.add 1 (${small})`;
  let compound = "1";
  for (let index = 0; index < 80; index++) {
    compound = `@u32.add 1 (${compound})`;
  }
  const source = (sibling: number) =>
    `const small = ${small}\nconst compound = #[{ value: ${compound} }]\nentry const run = fn () => small\nentry const count = fn () => @array.length compound\nentry const sibling = ${sibling}\n`;
  const options = {
    executable,
    entry,
    prelude: null,
    cacheDirectory: false as const,
  };
  const retained = await createZigProjectCompiler(options);
  try {
    for (const sibling of [1, 2, 1]) {
      const fresh = await createZigProjectCompiler(options);
      try {
        const sources = { [entry]: source(sibling) };
        const expected = await fresh.build({ sources });
        const actual = await retained.build({ sources });
        assert.ok(actual.success && expected.success);
        if (!actual.success || !expected.success) {
          throw new Error("compile failed");
        }
        assert.deepEqual(actual.bytes, expected.bytes);
        assert.equal(
          actual.stats.nativeWorkSteps,
          expected.stats.nativeWorkSteps,
        );
        const receipts = actual.stats.constantReceipts as Record<
          string,
          number
        >;
        assert.equal(receipts.scalar_reused, 0);
        assert.equal(receipts.recorded + receipts.reused, 1);
        if (sibling === 2) {
          assert.equal(receipts.reused, 1);
          assert.ok(receipts.source_steps_replayed >= 161);
        }
        const guest = await instantiateGuest(actual.bytes);
        try {
          assert.equal(guest.call("run", null), 53);
          assert.equal(guest.call("count", null), 1);
        } finally {
          await guest.dispose();
        }
      } finally {
        await fresh.close();
      }
    }
  } finally {
    await retained.close();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("enclosing constant member judgments retain exact executed authority in both tiers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-enclosing-member-",
  });
  const entry = `${directory}/main.blot`;
  const prelude = `${directory}/prelude.blot`;
  const library = "";
  await Deno.writeTextFile(
    prelude,
    library + "\nconst Array.count = fn values => @array.length values\n",
  );
  const source = (
    sibling = "1",
    seed = "2",
    delta = "0",
    receiver = "#[]",
    twice = false,
    alias = false,
  ) => {
    let method = "@u32.add seed (@array.length values)";
    let expression = `${receiver}.count`;
    for (let index = 0; index < 80; index++) {
      method = `@u32.add ${delta} (${method})`;
      expression = `@u32.add 1 (${expression})`;
    }
    method =
      `do:\n  let total = (${method})\n  for index in 0..128:\n    total := @u32.add self 1\n  return total`;
    if (twice) expression = `@u32.add (#[].count) (${expression})`;
    let prefix = "";
    if (alias) prefix = "const alias: Array U32 = #[]\n";
    return {
      [prelude]:
        `${library}\nconst seed = ${seed}\nconst Array.count = fn values => ${method}\n`,
      [entry]: `${prefix}entry const warm: U32 = #[].count
entry const enclosing: U32 = ${expression}
entry const run = fn () => enclosing
entry const sibling = ${sibling}
`,
    };
  };
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude,
        cacheDirectory: false as const,
        codegenTier,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        const revisions = [
          [source(), 210, false],
          [source("2"), 210, true],
          [source("3"), 210, true],
          [source("3", "3"), 211, false],
          [source("3", "3", "1"), 291, false],
          [source("3", "3", "1", "#[1]"), 292, false],
          [source("3", "3", "1", "#[]", true), 502, false],
          [source("3", "3", "1", "alias", false, true), 291, false],
          [source('@panic "failed"'), null, false],
          // An independent warm scalar retains its ordinary query owner
          // while the enclosing typed alias preserves exact publication.
          [source("5", "3", "1", "alias", false, true), 291, true],
          [source("4", "3", "1", "alias", false, true), 291, true],
          [source(), 210, false],
          [source("2"), 210, true],
        ] as const;
        for (const [text, answer, hit] of revisions) {
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = text;
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.ok(!actual.success && !expected.success);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              assert.equal(answer, null, JSON.stringify(expected.diagnostics));
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            assert.equal(
              actual.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            const receipts = actual.stats.constantReceipts as Record<
              string,
              number
            >;
            if (hit) {
              assert.equal(
                receipts.queries_replayed > 0,
                true,
                JSON.stringify(receipts),
              );
            }
            const guest = await instantiateGuest(actual.bytes);
            try {
              assert.equal(guest.call("run", null), answer);
            } finally {
              await guest.dispose();
            }
          } finally {
            await fresh.close();
          }
        }
      } finally {
        await retained.close();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("compound receipts preserve ready nominal aliases, captured callbacks and failed revisions in both tiers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-compound-receipts-",
  });
  const entry = `${directory}/main.blot`;
  let cost = "1";
  for (let index = 0; index < 80; index++) cost = `@u32.add 1 (${cost})`;
  const source = (sibling = "1", seed = "2", delta = "0", ready = true) => {
    let qualifier = "";
    if (ready) qualifier = "entry ";
    return `data Box = #Box { value: U32 }
const seed = ${seed}
const ready = #Box { value: seed }
${qualifier}const warmed = fn () => ready.value
const compound = do:
  let cost = ${cost}
  return { first: ready, second: ready, values: #[ready, ready], answer: cost, callback: fn (value: U32) => @u32.add value (@u32.add cost ${delta}) }
entry const run = fn (value: U32) => compound.callback value
entry const answer = fn () => compound.first.value
entry const count = fn () => @array.length compound.values
entry const sibling = ${sibling}
`;
  };
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false as const,
        codegenTier,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        const revisions = [
          [source(), 2, 0, false],
          [source("2"), 2, 0, true],
          [source("3", "3"), 3, 0, false],
          [source("4", "3", "1"), 3, 1, false],
          [source("missing", "3", "1"), null, null, false],
          [source("5", "3", "1"), 3, 1, true],
          [source(), 2, 0, false],
          [source("2"), 2, 0, true],
          [source("2", "2", "0", false), 2, 0, false],
        ] as const;
        for (const [text, seed, delta, hit] of revisions) {
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = { [entry]: text };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.ok(!actual.success && !expected.success);
              assert.equal(seed, null, JSON.stringify(expected));
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            assert.equal(
              actual.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            const traffic = actual.stats.constantReceipts as Record<
              string,
              number
            >;
            assert.equal(traffic.reused, Number(hit), JSON.stringify(traffic));
            if (hit) {
              assert.ok(traffic.source_steps_replayed >= 161);
              assert.ok(traffic.values_imported > 1);
            }
            const guest = await instantiateGuest(actual.bytes);
            try {
              assert.equal(guest.call("run", 40), 121 + Number(delta));
              assert.equal(guest.call("answer", null), seed);
              assert.equal(guest.call("count", null), 2);
            } finally {
              await guest.dispose();
            }
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("compound buffer receipts retain aliases branches and cold reads in both tiers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-compound-buffers-",
  });
  const entry = `${directory}/main.blot`;
  const source = (sibling = "1", seed = "2", count = 32) => `
data Bundle = #Bundle { earlier: List U32, current: List U32, alias: List U32, other: List U32, answer: U32 }
const seed = ${seed}
const grown = do:
  let values: List U32 = []
  let earlier: List U32 = []
  let other: List U32 = []
  for index in 0..${count}:
    values := if @u32.lt index 16 then @list.append values index else @list.prepend values index
    other := @list.append other (@u32.add index 100)
    earlier := if @u32.eq index 30 then values else earlier
  return #Bundle { earlier: earlier, current: values, alias: values, other: other, answer: seed }
const later = @list.prepend (@list.append grown.current 99) 100
const branched = @list.append grown.earlier 200
entry const first = fn () => @array.from_list grown.current
entry const alias = fn () => @array.from_list grown.alias
entry const old = fn () => @array.from_list grown.earlier
entry const other = fn () => @array.from_list grown.other
entry const following = fn () => @array.from_list later
entry const branch = fn () => @array.from_list branched
entry const answer = fn () => grown.answer
entry const sibling = ${sibling}
`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        codegenTier,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        const revisions = [
          ["1", "2", 32, false],
          ["2", "2", 32, true],
          ["3", "3", 32, false],
          ["missing", "3", 32, false],
          ["4", "3", 32, true],
          ["5", "3", 33, false],
          ["6", "3", 33, true],
          ["1", "2", 32, false],
          ["2", "2", 32, true],
        ] as const;
        for (const [sibling, seed, count, hit] of revisions) {
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = { [entry]: source(sibling, seed, count) };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.equal(sibling, "missing");
              assert.ok(!actual.success && !expected.success);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            assert.equal(
              actual.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            const traffic = actual.stats.constantReceipts as Record<
              string,
              number
            >;
            assert.equal(traffic.reused, Number(hit), JSON.stringify(traffic));
            const values: number[] = [];
            let earlier: number[] = [];
            for (let index = 0; index < count; index++) {
              if (index < 16) values.push(index);
              else values.unshift(index);
              if (index === 30) earlier = [...values];
            }
            const guest = await instantiateGuest(actual.bytes);
            try {
              assert.deepEqual(
                guest.call("first", null),
                new Uint32Array(values),
              );
              assert.deepEqual(
                guest.call("alias", null),
                new Uint32Array(values),
              );
              assert.deepEqual(
                guest.call("old", null),
                new Uint32Array(earlier),
              );
              assert.deepEqual(
                guest.call("other", null),
                new Uint32Array(
                  Array.from({ length: count }, (_, i) => i + 100),
                ),
              );
              assert.deepEqual(
                guest.call("following", null),
                new Uint32Array([100, ...values, 99]),
              );
              assert.deepEqual(
                guest.call("branch", null),
                new Uint32Array([...earlier, 200]),
              );
              assert.equal(guest.call("answer", null), Number(seed));
            } finally {
              await guest.dispose();
            }
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("receipt closure templates preserve deferred global and capture edits in both tiers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-receipt-deferred-",
  });
  const entry = `${directory}/main.blot`;
  let cost = "1";
  for (let index = 0; index < 80; index++) cost = `@u32.add 1 (${cost})`;
  const source = (
    global = "2",
    capture = "3",
    delta = "0",
    body = "0",
    sibling = "1",
  ) => `
const global = ${global}
const capture = ${capture}
const delayed = fn ~(value: U32) => @demand value
const named = fn (value: U32) => @u32.add (delayed value) (@u32.add global ${body})
const saved = do:
  let cost = ${cost}
  let captured = capture
  return { named: named, anonymous: fn (value: U32) => @u32.add (delayed value) (@u32.add global ${delta}), captured: fn (value: U32) => @u32.add (delayed value) (@u32.add cost captured) }
entry const run_named = fn (value: U32) => saved.named value
entry const run_anonymous = fn (value: U32) => saved.anonymous value
entry const run_captured = fn (value: U32) => saved.captured value
entry const sibling = ${sibling}
`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        codegenTier,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      try {
        const revisions = [
          ["2", "3", "0", "0", "1", false],
          ["4", "3", "0", "0", "2", true],
          ["4", "5", "0", "0", "3", false],
          ["4", "5", "1", "0", "4", false],
          ["4", "5", "1", "1", "5", false],
          ["4", "5", "1", "1", "missing", false],
          ["4", "5", "1", "1", "6", true],
          ["2", "3", "0", "0", "1", false],
          ["4", "3", "0", "0", "2", true],
        ] as const;
        for (const [global, capture, delta, body, sibling, hit] of revisions) {
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = {
              [entry]: source(global, capture, delta, body, sibling),
            };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.equal(sibling, "missing");
              assert.ok(!actual.success && !expected.success);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            assert.equal(
              actual.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            const traffic = actual.stats.constantReceipts as Record<
              string,
              number
            >;
            assert.equal(
              traffic.reused,
              Number(hit),
              JSON.stringify({ traffic, global, capture, delta, body }),
            );
            const guest = await instantiateGuest(actual.bytes);
            try {
              assert.equal(
                guest.call("run_named", 40),
                40 + Number(global) + Number(body),
              );
              assert.equal(
                guest.call("run_anonymous", 40),
                40 + Number(global) + Number(delta),
              );
              assert.equal(
                guest.call("run_captured", 40),
                121 + Number(capture),
              );
            } finally {
              await guest.dispose();
            }
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("ordinary compound receipts remain reusable beside erased generative helper bodies", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-generative-receipt-",
  });
  const entry = `${directory}/main.blot`;
  let expression = "1";
  for (let index = 0; index < 80; index++) {
    expression = `@u32.add 1 (${expression})`;
  }
  const source = (sibling: string, answer: number) => `
type State a is effect = {get: Unit -> a, set: a -> Unit}
const choose = fn flag => fn (left: State a) => fn (right: State a) => if flag then left else right
const hidden = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let picked = choose #True left right
  let deferred = fn () => picked.get ()
  return ${answer}
))
const expensive = #[{answer: ${expression}}]
entry const value = fn () => (@array.get expensive 0).answer
entry const selected = fn () => hidden ()
entry const sibling = ${sibling}
`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        codegenTier,
        cacheDirectory: false,
      } as const;
      const retained = await createZigProjectCompiler(options);
      try {
        const revisions = [["1", 11], ["2", 11], ["missing", 12], ["3", 12], [
          "1",
          11,
        ]] as const;
        for (const [revision, [sibling, answer]] of revisions.entries()) {
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = { [entry]: source(sibling, answer) };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.equal(sibling, "missing");
              assert.ok(!actual.success && !expected.success);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            assert.equal(
              actual.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            if (revision > 0) {
              const traffic = actual.stats.constantReceipts as Record<
                string,
                number
              >;
              assert.equal(traffic.reused, 1);
              assert.equal(traffic.retries, 0);
            }
            const guest = await instantiateGuest(actual.bytes);
            try {
              assert.equal(guest.call("value", null), 81);
              assert.equal(guest.call("selected", null), answer);
            } finally {
              guest.dispose();
            }
          } finally {
            await fresh.close();
          }
        }
      } finally {
        await retained.close();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("constant solver judgments preserve mapped rows archives recovery and current callable owners in both tiers", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-constant-judgments-",
  });
  const entry = `${directory}/main.blot`;
  const library = `${directory}/helpers.blot`;
  const archive = `${directory}/helpers.blotdep`;
  const helper = "const identity = fn value => value\n";
  const source = (seed = "2", answer = "35") => `
import {identity} from "./helpers"
const seed = ${seed}
const answer = do:
  let callback = fn () => ${answer}
  let generic = identity
  let nested = {callback, value: generic 7}
  let selected: U32 where { type_rep U32 } = nested.callback ()
  let cost = 0
  for index in 0..256:
    cost := @u32.add self 1
  return {selected, cost, value: nested.value}
entry const run = fn () => @u32.add answer.selected (@u32.add answer.cost answer.value)
entry const unrelated = seed
`;
  try {
    await Deno.writeTextFile(entry, source());
    await Deno.writeTextFile(library, helper);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      } as const;
      const retained = await createZigProjectCompiler(options);
      const archived = await createZigProjectCompiler({
        ...options,
        dependencies: archive,
      });
      try {
        const initial = await retained.build();
        const imported = await archived.build();
        assert.ok(initial.success, JSON.stringify(initial));
        assert.ok(imported.success, JSON.stringify(imported));
        assert.deepEqual(imported.bytes, initial.bytes);
        let checkpoint: Uint8Array<ArrayBuffer> | undefined;
        let checkpointBytes = initial.bytes;
        const revisions = [
          ["3", "35", helper, true],
          ["3", "36", helper, false],
          ["missing", "36", helper, false],
          ["4", "36", helper, true],
          [
            "4",
            "36",
            "const identity = fn (value: U32) => @u32.add value 1\n",
            false,
          ],
          ["2", "35", helper, false],
          ["3", "35", helper, true],
        ] as const;
        for (const [seed, answer, selected, hit] of revisions) {
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = {
              [entry]: source(seed, answer),
              [library]: selected,
            };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.equal(seed, "missing");
              assert.ok(!actual.success && !expected.success);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            assert.equal(
              actual.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            const receipts = actual.stats.constantReceipts as Record<
              string,
              number
            >;
            if (hit) {
              assert.ok(receipts.reused > 0, JSON.stringify(receipts));
              assert.ok(
                receipts.queries_replayed > 0,
                JSON.stringify(receipts),
              );
            }
            let increment = 0;
            if (selected !== helper) increment = 1;
            for (const asynchronous of [false, true]) {
              const guest = await instantiateGuest(actual.bytes, {
                asynchronous,
              });
              try {
                let actualAnswer: unknown;
                if (asynchronous) {
                  actualAnswer = await guest.callAsync("run", null);
                } else actualAnswer = guest.call("run", null);
                assert.equal(actualAnswer, Number(answer) + 263 + increment);
              } finally {
                await guest.dispose();
              }
            }
            checkpoint = await retained.exportCheckpoint();
            checkpointBytes = actual.bytes;
          } finally {
            await fresh.dispose();
          }
        }
        assert.ok(checkpoint);
        const restarted = await createZigProjectCompiler({
          ...options,
          checkpoint,
        });
        try {
          const result = await restarted.build({
            sources: { [entry]: source("3"), [library]: helper },
          });
          assert.ok(result.success, JSON.stringify(result));
          assert.deepEqual(result.bytes, checkpointBytes);
        } finally {
          await restarted.dispose();
        }
      } finally {
        await retained.dispose();
        await archived.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("immutable package witnesses dictionaries and proof temporaries retain exact data across source archives edits and recovery", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-immutable-receipts-",
  });
  const entry = `${directory}/main.blot`;
  const library = `${directory}/packages.blot`;
  const archive = `${directory}/packages.blotdep`;
  const producer = (value = "35", increment = "0") => {
    let cost = value;
    for (let index = 0; index < 80; index++) cost = `@u32.add 1 (${cost})`;
    return `type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = fn value => @u32.add value ${increment} }
type Item = exists [a] where { Render a } => a
const packet = pack [U32] (${cost}) as Item
const alias = packet
const packets = #[packet, alias]
const read = fn (item: Item) => unpack item as [a] value in Render.show value
const result = fn () => @u32.add (read packet) (read (@array.get packets 1))
`;
  };
  const consumer = (seed = "2", limit = "1") =>
    `import {result} from "./packages"
const seed = ${seed}
const limit = ${limit}
const checked = do:
  let valid = @proof.lt 0 limit
  return 0
entry const run = fn () => result ()
entry const unrelated = @u32.add seed checked
`;
  try {
    await Deno.writeTextFile(library, producer());
    await Deno.writeTextFile(entry, consumer());
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      } as const;
      const retained = await createZigProjectCompiler(options);
      const imported = await createZigProjectCompiler({
        ...options,
        dependencies: archive,
      });
      try {
        const initial = await retained.build();
        const archived = await imported.build();
        assert.ok(initial.success, JSON.stringify(initial));
        assert.ok(archived.success, JSON.stringify(archived));
        assert.deepEqual(archived.bytes, initial.bytes);
        const archivedEdit = await imported.build({
          sources: { [entry]: consumer("3") },
        });
        const sourceEdit = await retained.build({
          sources: { [entry]: consumer("3") },
        });
        assert.ok(archivedEdit.success, JSON.stringify(archivedEdit));
        assert.ok(sourceEdit.success, JSON.stringify(sourceEdit));
        assert.deepEqual(archivedEdit.bytes, sourceEdit.bytes);
        for (const result of [archivedEdit, sourceEdit]) {
          const traffic = result.stats.constantReceipts as Record<
            string,
            number
          >;
          assert.ok(traffic.reused > 0, JSON.stringify(traffic));
        }
        const revisions = [
          ["4", "35", "0", "1", true],
          ["4", "36", "0", "1", false],
          ["4", "36", "1", "1", false],
          ["missing", "36", "1", "1", false],
          ["5", "36", "1", "0", false],
          ["5", "36", "1", "1", true],
          ["2", "35", "0", "1", false],
          ["3", "35", "0", "1", true],
        ] as const;
        let checkpoint: Uint8Array<ArrayBuffer> | undefined;
        let checkpointBytes = initial.bytes;
        for (const [seed, value, increment, limit, hit] of revisions) {
          const fresh = await createZigProjectCompiler(options);
          try {
            const sources = {
              [entry]: consumer(seed, limit),
              [library]: producer(value, increment),
            };
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.ok(seed === "missing" || limit === "0");
              assert.ok(!actual.success && !expected.success);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            assert.equal(
              actual.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            if (hit) {
              const traffic = actual.stats.constantReceipts as Record<
                string,
                number
              >;
              assert.ok(traffic.reused > 0, JSON.stringify(traffic));
            }
            for (const asynchronous of [false, true]) {
              const guest = await instantiateGuest(actual.bytes, {
                asynchronous,
              });
              try {
                let answer: unknown;
                if (asynchronous) answer = await guest.callAsync("run", null);
                else answer = guest.call("run", null);
                assert.equal(
                  answer,
                  2 * (Number(value) + 80 + Number(increment)),
                );
              } finally {
                await guest.dispose();
              }
            }
            checkpoint = await retained.exportCheckpoint();
            checkpointBytes = actual.bytes;
          } finally {
            await fresh.dispose();
          }
        }
        assert.ok(checkpoint);
        const restarted = await createZigProjectCompiler({
          ...options,
          checkpoint,
        });
        try {
          const built = await restarted.build({
            sources: { [entry]: consumer("3"), [library]: producer() },
          });
          assert.ok(built.success, JSON.stringify(built));
          assert.deepEqual(built.bytes, checkpointBytes);
        } finally {
          await restarted.dispose();
        }
      } finally {
        await retained.dispose();
        await imported.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
