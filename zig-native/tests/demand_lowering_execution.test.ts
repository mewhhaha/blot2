import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
type Site = {
  filename: string;
  start: number;
  end: number;
  lowering: string;
  reason: string;
};
type Report = { sites: Site[]; omitted: number };

async function execute(
  bytes: Uint8Array<ArrayBuffer>,
  name: string,
  value: number,
) {
  const guest = await instantiateGuest(bytes);
  try {
    return guest.call(name, value);
  } finally {
    guest.dispose();
  }
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`Boolean demand guarantee covers foreign forwarding, captures, fixities and archives (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const leaf = `${directory}/leaf.blot`;
    const archive = `${directory}/deps.blotdep`;
    const leafSource = `const enabled = true
const conjunction = func (condition: Bool) => return func ~(value: Bool) => return
  if enabled then if condition then @demand value else false else false
const disjunction = func (condition: Bool) => return func ~(value: Bool) => return
  if condition then true else @demand value
`;
    const source = `import { alias, alternate } from "./forward"
infixr 35 (<&>) = alias
infixr 34 (<|>) = alternate
entry const conjunction = func (value: U32) => return (@u32.eq value 10) <&> (@u32.eq (@u32.div 100 value) 10)
entry const disjunction = func (value: U32) => return (@u32.eq value 0) <|> (@u32.eq (@u32.div 100 value) 10)
entry const explicit_and = func (value: U32) => return if @u32.eq value 10 then @u32.eq (@u32.div 100 value) 10 else false
entry const explicit_or = func (value: U32) => return if @u32.eq value 0 then true else @u32.eq (@u32.div 100 value) 10
entry const loop = func (value: U32) => return do:
  let total = 0
  for index in 0..8:
    total := @u32.add total (if (@u32.eq value 10) <&> (@u32.eq (@u32.div 100 value) 10) then 1 else 0)
  break total
`;
    try {
      await Deno.writeTextFile(entry, source);
      await Deno.writeTextFile(leaf, leafSource);
      await Deno.writeTextFile(
        `${directory}/forward.blot`,
        `import { conjunction, disjunction } from "./leaf"
const forward = func (condition: Bool) => return func ~(value: Bool) => return conjunction condition (@demand value)
const alias = forward
const alternate = func (condition: Bool) => return func ~(value: Bool) => return disjunction condition (@demand value)
`,
      );
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, archive, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(
        packed.success,
        new TextDecoder().decode(packed.stdout) +
          new TextDecoder().decode(packed.stderr),
      );
      let expected: Uint8Array<ArrayBuffer> | undefined;
      for (const dependencies of [undefined, archive]) {
        const options = {
          executable,
          entry,
          prelude: null,
          codegenTier,
          dependencies,
          explainDemands: true,
          cacheDirectory: false as const,
        };
        const compiler = await createZigProjectCompiler(options);
        const plain = await createZigProjectCompiler({
          ...options,
          explainDemands: false,
        });
        try {
          const result = await compiler.build();
          assert(result.success, JSON.stringify(result));
          const ordinary = await plain.build();
          assert(ordinary.success);
          assert.deepEqual(result.bytes, ordinary.bytes);
          if (expected) assert.deepEqual(result.bytes, expected);
          expected = result.bytes;
          noStorage(result.bytes);
          const counters = result.stats.workCounters as Record<string, number>;
          assert.equal(counters.demand_allocations, 0);
          assert.equal(counters.demand_local_memo_slots, 0);
          assert.equal(counters.demand_indirect_calls, 0);
          const report = result.stats.demandLowering as unknown as Report;
          assert(report.sites.length > 0);
          assert(report.sites.every((site) => site.lowering === "direct"));
          for (const value of [0, 1, 10, 100]) {
            assert.equal(
              await execute(result.bytes, "conjunction", value),
              await execute(result.bytes, "explicit_and", value),
            );
            assert.equal(
              await execute(result.bytes, "disjunction", value),
              await execute(result.bytes, "explicit_or", value),
            );
            let total = 0;
            if (value === 10) total = 8;
            assert.equal(await execute(result.bytes, "loop", value), total);
          }
          // An immutable captured value is a code dependency, even though the
          // callable's public type and its branch shape remain unchanged.
          const changed = leafSource.replace(
            "enabled = true",
            "enabled = false",
          );
          const edited = await compiler.build({ sources: { [leaf]: changed } });
          assert(edited.success, JSON.stringify(edited));
          const ordinaryEdit = await plain.build({
            sources: { [leaf]: changed },
          });
          assert(ordinaryEdit.success);
          assert.deepEqual(edited.bytes, ordinaryEdit.bytes);
          noStorage(edited.bytes);
          assert.equal(await execute(edited.bytes, "conjunction", 10), false);
          const fresh = await createZigProjectCompiler(options);
          try {
            const rebuilt = await fresh.build({ sources: { [leaf]: changed } });
            assert(rebuilt.success);
            assert.deepEqual(edited.bytes, rebuilt.bytes);
            assert.deepEqual(
              edited.stats.demandLowering,
              rebuilt.stats.demandLowering,
            );
          } finally {
            await fresh.dispose();
          }
          const checkpoint = await compiler.exportCheckpoint();
          const failed = await compiler.build({
            sources: {
              [leaf]: changed.replace("enabled = false", "enabled = missing"),
            },
          });
          assert(!failed.success);
          assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          const recovered = await compiler.build({
            sources: { [leaf]: leafSource },
          });
          const ordinaryRecovery = await plain.build({
            sources: { [leaf]: leafSource },
          });
          assert(recovered.success && ordinaryRecovery.success);
          assert.deepEqual(recovered.bytes, result.bytes);
          assert.deepEqual(recovered.bytes, ordinaryRecovery.bytes);
        } finally {
          await plain.dispose();
          await compiler.dispose();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
function noStorage(bytes: Uint8Array<ArrayBuffer>) {
  let at = 8;
  while (at < bytes.length) {
    const section = bytes[at++];
    assert(section !== 4 && section !== 5, "demand introduced table or memory");
    let size = 0;
    let shift = 0;
    let byte: number;
    do {
      byte = bytes[at++];
      size += (byte & 127) * 2 ** shift;
      shift += 7;
    } while (byte & 128);
    at += size;
  }
}

function booleanChain(count: number, operator: string) {
  return Array.from({ length: count + 1 }, () => "(@u32.eq value 0)").join(
    ` ${operator} `,
  );
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`Boolean demand chains stay bounded through 256 operators and loops (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    try {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        codegenTier,
        explainDemands: true,
        cacheDirectory: false,
      });
      try {
        for (const count of [1, 8, 64, 256]) {
          const and = booleanChain(count, "<&>");
          const or = booleanChain(count, "<|>");
          const source = `infixl 35 (<&>) = and_then
infixl 34 (<|>) = or_else
const and_then = func (condition: Bool) => return func ~(value: Bool) => return if condition then @demand value else false
const or_else = func (condition: Bool) => return func ~(value: Bool) => return if condition then true else @demand value
entry const conjunction = func (value: U32) => return ${and}
entry const disjunction = func (value: U32) => return ${or}
entry const loop = func (value: U32) => return do:
  let total = 0
  for index in 0..8:
    total := @u32.add total (if ${and} then 1 else 0)
  break total
`;
          const result = await compiler.build({ sources: { [entry]: source } });
          assert(result.success, `${count}: ${JSON.stringify(result)}`);
          noStorage(result.bytes);
          const counters = result.stats.workCounters as Record<string, number>;
          assert.equal(counters.demand_allocations, 0);
          assert.equal(counters.demand_local_memo_slots, 0);
          assert.equal(counters.demand_indirect_calls, 0);
          assert(counters.demand_inline_nodes <= 96 * 3 * count);
          const report = result.stats.demandLowering as unknown as Report;
          assert(report.sites.length <= 256);
          if (count === 256) assert(report.omitted > 0);
          const guest = await instantiateGuest(result.bytes);
          try {
            for (const value of [0, 1]) {
              assert.equal(guest.call("conjunction", value), value === 0);
              assert.equal(guest.call("disjunction", value), value === 0);
              let total = 0;
              if (value === 0) total = 8;
              assert.equal(guest.call("loop", value), total);
            }
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await compiler.dispose();
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}

Deno.test("demand explanation follows actual local storage without changing bytes", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const source = `
const ignore = func ~(value: U32) => return 42
const once = func ~(value: U32) => return @demand value
const twice = func ~(value: U32) => return @u32.add (@demand value) (@demand value)
const stored = func ~(value: U32) => return func () => return @demand value
const unknown = func (next: ~U32 -> U32) => return func ~(value: U32) => return next (@demand value)
entry const eliminated = func (value: U32) => return ignore value
entry const direct = func (value: U32) => return once value
entry const memo = func (value: U32) => return twice value
entry const escape = func (value: U32) => return (stored value) ()
entry const indirect = func (value: U32) => return unknown once value
`;
  try {
    await Deno.writeTextFile(entry, source);
    const options = {
      executable,
      entry,
      prelude: null,
      cacheDirectory: false as const,
    };
    const plain = await createZigProjectCompiler(options);
    const explained = await createZigProjectCompiler({
      ...options,
      explainDemands: true,
    });
    try {
      const reference = await plain.build();
      const result = await explained.build();
      assert(reference.success && result.success);
      assert.deepEqual(result.bytes, reference.bytes);
      assert.equal(reference.stats.demandLowering, null);
      const report = result.stats.demandLowering as unknown as Report;
      assert.equal(report.omitted, 0);
      assert.deepEqual(
        new Set(report.sites.map((site) => site.lowering)),
        new Set(["eliminated", "direct", "local_memo", "stored"]),
      );
      const sourceBytes = new TextEncoder().encode(source).length;
      for (const site of report.sites) {
        assert.equal(site.filename, entry);
        assert(
          site.start >= 0 && site.end >= site.start && site.end <= sourceBytes,
        );
      }
      assert(
        report.sites.some((site) => site.reason === "escaping_use"),
        JSON.stringify(report),
      );
      assert(report.sites.some((site) => site.reason === "unknown_callee"));
      assert.equal(await execute(result.bytes, "eliminated", 0), 42);
      assert.equal(await execute(result.bytes, "direct", 21), 21);
      assert.equal(await execute(result.bytes, "memo", 21), 42);
      assert.equal(await execute(result.bytes, "escape", 21), 21);
      assert.equal(await execute(result.bytes, "indirect", 21), 21);
      const repeated = await explained.build();
      assert(repeated.success);
      assert.deepEqual(
        repeated.stats.demandLowering,
        result.stats.demandLowering,
      );
      assert.deepEqual(repeated.bytes, result.bytes);
      assert.equal(
        (repeated.stats.workCounters as Record<string, number>)
          .demand_allocations,
        0,
      );
      const prefix = "// shifted source\n";
      const shifted = await explained.build({
        sources: { [entry]: prefix + source },
      });
      assert(shifted.success);
      assert.deepEqual(shifted.bytes, result.bytes);
      const shiftedReport = shifted.stats.demandLowering as unknown as Report;
      assert.deepEqual(
        shiftedReport.sites,
        report.sites.map((site) => ({
          ...site,
          start: site.start + prefix.length,
          end: site.end + prefix.length,
        })),
      );
    } finally {
      await plain.dispose();
      await explained.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`Boolean demand guarantee across aliases and imports (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`;
    const library = `${directory}/library.blot`;
    try {
      await Deno.writeTextFile(
        library,
        `const choose = func (condition: Bool) => return func ~(value: Bool) => return if condition then @demand value else false\nconst alias = choose\n`,
      );
      await Deno.writeTextFile(
        entry,
        'import { alias } from "./library"\nentry const run = func (value: U32) => return alias (value != 0) (100 / value == 10)\nentry const explicit = func (value: U32) => return if value != 0 then 100 / value == 10 else false\n',
      );
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude,
        codegenTier,
        explainDemands: true,
        cacheDirectory: false,
      });
      try {
        const result = await compiler.build();
        assert(result.success, JSON.stringify(result));
        noStorage(result.bytes);
        const counters = result.stats.workCounters as Record<string, number>;
        assert.equal(counters.demand_allocations, 0);
        assert.equal(counters.demand_local_memo_slots, 0);
        assert.equal(counters.demand_indirect_calls, 0);
        assert(Number(counters.demand_direct) > 0);
        for (const value of [0, 1, 10, 100]) {
          assert.equal(
            await execute(result.bytes, "run", value),
            await execute(result.bytes, "explicit", value),
          );
        }
        const checkpoint = await compiler.exportCheckpoint();
        const restarted = await createZigProjectCompiler({
          executable,
          entry,
          prelude,
          codegenTier,
          explainDemands: true,
          checkpoint,
          cacheDirectory: false,
        });
        try {
          const rebuilt = await restarted.build();
          assert(rebuilt.success);
          assert.deepEqual(rebuilt.bytes, result.bytes);
          assert.deepEqual(
            rebuilt.stats.demandLowering,
            result.stats.demandLowering,
          );
        } finally {
          await restarted.dispose();
        }
      } finally {
        await compiler.dispose();
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
