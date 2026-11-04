import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const fixture = (name: string) =>
  Deno.readTextFile(new URL(`../../compiler/fixtures/${name}`, import.meta.url));
const template = await fixture("input_alias_callbacks.blot.in");
const floatTemplate = await fixture("input_alias_f32.blot.in");

function callbackSource(width: number, distinct: boolean) {
  const types: string[] = [];
  const original: string[] = [];
  const later: string[] = [];
  const reads: string[] = [];
  const declarations: string[] = [];
  for (let index = 0; index < width; index++) {
    types.push(`f${index}: Array U32,`);
    let first = "original";
    let second = "later";
    if (distinct) {
      let owner = index;
      if (index % 4 === 3) owner--;
      first = `original_${owner}`;
      second = `later_${owner}`;
      if (owner === index) {
        declarations.push(
          `  let ${first}: Array U32 = #[@u32.add input ${index}]`,
        );
        declarations.push(
          `  let ${second}: Array U32 = #[@u32.add input ${index + 7}]`,
        );
      }
    }
    original.push(`f${index}: ${first},`);
    later.push(`f${index}: ${second},`);
    reads.push(`  result := @u32.add self bundle.f${index}[0]`);
  }
  let secondBundle = "bundle";
  if (distinct) secondBundle = "next";
  return template.replace("__TYPES__", types.join(""))
    .replace("__ORIGINAL__", original.join(""))
    .replace("__LATER__", later.join(""))
    .replace("__READS__", reads.join("\n"))
    .replace("__SECOND_BUNDLE__", secondBundle)
    .replace("__DECLARATIONS__", declarations.join("\n"));
}

function floatSource(distinct: boolean) {
  const types: string[] = [];
  const fields: string[] = [];
  const reads: string[] = [];
  for (let index = 0; index < 192; index++) {
    types.push(`f${index}: Array F32,`);
    let value = "words";
    if (distinct) value = `#[@f32.add input ${index}.0]`;
    fields.push(`f${index}: ${value},`);
    reads.push(`  result := @f32.add self row.f${index}[0]`);
  }
  return floatTemplate.replace("__TYPES__", types.join(""))
    .replace("__FIELDS__", fields.join(""))
    .replace("__READS__", reads.join("\n"));
}

function floatExpected(bits: number, distinct: boolean) {
  const bytes = new DataView(new ArrayBuffer(4));
  bytes.setUint32(0, bits, true);
  const input = bytes.getFloat32(0, true);
  let total = 0;
  for (let index = 0; index < 192; index++) {
    let value = input;
    if (distinct) value = Math.fround(input + index);
    total = Math.fround(total + value);
  }
  bytes.setFloat32(0, total, true);
  const result = bytes.getUint32(0, true);
  return new Uint32Array([result, result, bits, bits]);
}

function partitionExpected(input: number) {
  return new Uint32Array([
    input * 11,
    input * 11 + 7,
    input * 11 + 77,
    input * 11 + 70,
    input * 11 + 10,
    input,
  ]);
}

function descriptorExpected(input: number) {
  let mixed = input * 11 + 200;
  let inactive = mixed;
  if (input === 0) {
    mixed = input * 11;
    inactive = input + 70;
  }
  return new Uint32Array([
    mixed,
    inactive,
    input * 11,
    2112 + input * 11,
    2311 + input * 11,
    2211 + input * 11,
    2,
    3,
    1,
    99,
    input + 3,
    3,
    4,
    1,
    99,
    input + 6,
    4,
    1,
  ]);
}

async function execute(
  bytes: Uint8Array<ArrayBuffer>,
  expected: (input: number) => Uint32Array,
  inputs = [0, 1, 7, 0xffff_ffff, 0, 7],
) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      assert.equal(guest.abi.version, 8);
      // Repeated calls use different scalar partitions, live branch origins and
      // wrapping values without retaining an earlier invocation's descriptors.
      for (const input of inputs) {
        let actual: unknown;
        if (asynchronous) actual = await guest.callAsync("answer", input);
        else actual = guest.call("answer", input);
        assert.deepEqual(actual, expected(input));
      }
    } finally {
      guest.dispose();
    }
  }
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`exact input aliases retain scalar partitions snapshots and descriptor facts (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-input-alias-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
      storage: {
        temporaryBytes: 65536,
        growerBytes: 16384,
        persistentBytes: 256,
        transportBytes: 65536,
        ownerCapacity: 1024,
      },
    });
    try {
      for (
        const [name, expected] of [
          ["input_alias_partition.blot", partitionExpected],
          ["input_alias_descriptors.blot", descriptorExpected],
        ] as const
      ) {
        const built = await compiler.build({
          sources: { [entry]: await fixture(name) },
          signal: AbortSignal.timeout(5000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        assert(work.scoped_input_alias_words_avoided > 0, JSON.stringify(work));
        assert(work.scoped_function_plan_hits > 0, JSON.stringify(work));
        if (name === "input_alias_partition.blot") {
          assert(work.scoped_completed_plan_definitions >= 2);
          assert.equal(
            work.scoped_completed_plan_rollbacks,
            work.scoped_addressed_retries,
          );
          assert(work.scoped_direct_input_words_avoided > 0);
          assert(work.scoped_direct_argument_words_avoided > 0);
        } else {
          assert(work.scoped_function_plan_read_events > 0);
          assert(work.scoped_function_plan_write_events > 0);
        }
        await execute(built.bytes, expected);
      }
      for (
        const { width, distinct } of [
          { width: 32, distinct: false },
          { width: 128, distinct: false },
          { width: 256, distinct: true },
        ]
      ) {
        const built = await compiler.build({
          sources: { [entry]: callbackSource(width, distinct) },
          signal: AbortSignal.timeout(5000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        assert(
          work.scoped_input_alias_words_avoided >= width,
          JSON.stringify({ width, distinct, work }),
        );
        assert(work.scoped_function_plan_hits > 0);
        if (work.scoped_addressed_definitions > 0) {
          assert(work.scoped_addressed_calls > 0, JSON.stringify(work));
          assert(work.scoped_addressed_input_loads > 0, JSON.stringify(work));
          assert(
            work.scoped_addressed_snapshot_words > 0,
            JSON.stringify(work),
          );
        } else if (distinct) {
          assert(work.scoped_owned_packed_calls > 0);
          assert(work.scoped_packed_input_words_avoided > 0);
          assert(work.scoped_packed_argument_words_avoided > 0);
        } else {
          assert(work.scoped_owned_word_calls > 0);
          assert(work.scoped_direct_argument_words_avoided > 0);
        }
        await execute(built.bytes, (input) => {
          if (distinct) {
            const total = width * input + width * (width - 1) / 2 - width / 4;
            return new Uint32Array([
              total * 3 + width * 7,
              total * 3 + width * 7 + 2,
              (total + width * 7) * 3,
            ]);
          }
          return new Uint32Array([
            input * width * 3,
            (input + 1) * width * 3,
            (input + 7) * width * 3,
          ]);
        });
      }
      for (const distinct of [false, true]) {
        const built = await compiler.build({
          sources: { [entry]: floatSource(distinct) },
          signal: AbortSignal.timeout(5000),
        });
        assert(built.success, JSON.stringify(built));
        const work = built.stats.workCounters as Record<string, number>;
        assert(work.scoped_function_plan_hits > 0);
        if (work.scoped_addressed_definitions > 0) {
          assert(work.scoped_addressed_calls > 0, JSON.stringify(work));
          assert(work.scoped_addressed_input_loads > 0, JSON.stringify(work));
          assert(
            work.scoped_addressed_snapshot_words > 0,
            JSON.stringify(work),
          );
        } else if (distinct) {
          assert(work.scoped_owned_packed_calls > 0, JSON.stringify(work));
        } else {
          assert(work.scoped_packed_plans_promoted > 0, JSON.stringify(work));
          assert(work.scoped_input_alias_words_avoided >= 192);
          assert(work.scoped_owned_word_calls > 0);
        }
        await execute(built.bytes, (bits) => floatExpected(bits, distinct), [
          0,
          0x8000_0000,
          0x3fa0_0000,
          0xc050_0000,
          0x7f80_0000,
          0xff80_0000,
          0,
        ]);
      }
      const escaped = await compiler.build({
        sources: { [entry]: await fixture("input_alias_borrow_escape.blot") },
        signal: AbortSignal.timeout(5000),
      });
      assert(!escaped.success);
      assert(
        escaped.diagnostics.some((item) => item.code === "storage_escape"),
        JSON.stringify(escaped),
      );
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
