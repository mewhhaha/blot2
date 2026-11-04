import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const width = 64;
const lanes = Array.from({ length: width }, (_, index) => index);
const fields = (value: (index: number) => string) =>
  lanes.map((index) => `f${index}: ${value(index)},`).join("");
const wide = (input: string, offset = 0) =>
  `$Wide {${fields((index) => `@u32.add ${input} ${index + offset}`)}}`;
const scalarDefinitions = `type Wide is data = $Wide {${fields(() => "U32")}}
const sum_stage = func (row: Wide): U32 => return do:
  let result = 0
${lanes.map((index) => `  result := @u32.add self row.f${index}`).join("\n")}
  return result
const total = func (row: Wide): U32 => return sum_stage row
const relay = func (row: Wide): U32 => return total row
const keep = func (row: Wide): Wide => return row
const changed = func (row: Wide) -> (delta: U32): Wide => return
  $Wide {${
  fields((index) => {
    if (index === 0) return "@u32.add row.f0 delta";
    return `row.f${index}`;
  })
}}
`;
const sum = (input: number, offset = 0) => width * (input + offset) + 2016;
type Work = Record<string, number>;
type Expected = (input: number) => Uint32Array;
type Tier = "development" | "optimized";

async function withCompiler(
  codegenTier: Tier,
  run: (
    build: (source: string) => Promise<{
      bytes: Uint8Array<ArrayBuffer>;
      work: Work;
    }>,
    rejectEscape: () => Promise<void>,
  ) => Promise<void>,
) {
  const directory = await Deno.makeTempDir({ prefix: "blot-addressed-input-" });
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
  const build = async (source: string) => {
    const built = await compiler.build({
      sources: { [entry]: source },
      signal: AbortSignal.timeout(5000),
    });
    assert(built.success, JSON.stringify(built));
    const work = built.stats.workCounters as Work;
    assert(work.scoped_addressed_definitions > 0, JSON.stringify(work));
    assert(work.scoped_addressed_calls > 0, JSON.stringify(work));
    assert(work.scoped_addressed_input_loads > 0, JSON.stringify(work));
    assert(work.scoped_addressed_retained_slots_max <= 8, JSON.stringify(work));
    assert(
      work.scoped_addressed_retained_bytes_max <= 32 * 1024,
      JSON.stringify(work),
    );
    return { bytes: built.bytes, work };
  };
  const rejectEscape = async () => {
    const source = await Deno.readTextFile(
      new URL("../fixtures/input_alias_borrow_escape.blot", import.meta.url),
    );
    const built = await compiler.build({
      sources: { [entry]: source },
      signal: AbortSignal.timeout(5000),
    });
    assert(!built.success);
    assert(
      built.diagnostics.some((item) => item.code === "storage_escape"),
      JSON.stringify(built),
    );
  };
  try {
    await run(build, rejectEscape);
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
}

async function execute(
  bytes: Uint8Array<ArrayBuffer>,
  expected: Expected,
  inputs = [0, 1, 7, 0xffff_ffff, 0, 7],
) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      assert.equal(guest.abi.version, 8);
      // Every witness repeats exports on one instance, including the initial
      // input again after different snapshots and invocation-local cleanup.
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

function repeatedSource(distinct: boolean) {
  const declarations: string[] = [];
  const results: string[] = [];
  if (!distinct) declarations.push(`  let row = ${wide("input")}`);
  for (let index = 0; index < 8; index++) {
    let row = "row";
    if (distinct) {
      row = `row_${index}`;
      declarations.push(`  let ${row} = ${wide("input", index)}`);
    }
    declarations.push(`  let result_${index} = relay ${row}`);
    results.push(`result_${index}`);
  }
  return `${scalarDefinitions}
entry const answer = func (argument: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[argument]
  let input = marker[0]
${declarations.join("\n")}
  return #[${results.join(",")}]
`;
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`addressed helper provenance and rejected borrowed children stay separate in both call orders (${codegenTier})`, async () => {
    await withCompiler(codegenTier, async (build) => {
      for (const borrowedFirst of [false, true]) {
        let calls = "  let direct = sum_stage row\n  let borrowed = total row";
        if (borrowedFirst) {
          calls = "  let borrowed = total row\n  let direct = sum_stage row";
        }
        const built = await build(`${scalarDefinitions}
const sparse_leaf = func (row: Wide): U32 => return do:
  let whole = keep row
  let result = 0
${
          lanes.slice(0, 4).map((index) =>
            `  result := @u32.add self whole.f${index}`
          ).join("\n")
        }
  return result
const sparse_parent = func (row: Wide): U32 => return sparse_leaf row
entry const answer = func (argument: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[argument]
  let input = marker[0]
  let row = ${wide("input")}
${calls}
  let discarded_child = sparse_parent row
  let ordinary_child = sparse_leaf row
  let retried_parent = sparse_parent row
  let direct_again = sum_stage row
  let borrowed_again = total row
  return #[direct, borrowed, discarded_child, ordinary_child, retried_parent, direct_again, borrowed_again]
`);
        assert(
          built.work.scoped_addressed_retries > 0,
          JSON.stringify(built.work),
        );
        assert(
          built.work.scoped_owned_word_calls > 0,
          JSON.stringify(built.work),
        );
        assert.equal(built.work.scoped_input_alias_retries, 0);
        await execute(built.bytes, (input) =>
          new Uint32Array([
            sum(input),
            sum(input),
            4 * input + 6,
            4 * input + 6,
            4 * input + 6,
            sum(input),
            sum(input),
          ]));
      }
    });
  });

  Deno.test(`addressed snapshot masks expand before a wider callee can reuse them (${codegenTier})`, async () => {
    await withCompiler(codegenTier, async (build) => {
      const built = await build(`${scalarDefinitions}
const first_stage = func (row: Wide): U32 => return do:
  let whole = keep row
  let result = 0
${
        lanes.slice(0, 16).map((index) =>
          `  result := @u32.add self whole.f${index}`
        ).join("\n")
      }
  return result
const first = func (row: Wide): U32 => return first_stage row
entry const answer = func (argument: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[argument]
  let input = marker[0]
  let row = ${wide("input")}
  let narrow = first row
  let all_words = total row
  let repeated = total row
  return #[narrow, all_words, repeated]
`);
      assert(
        built.work.scoped_addressed_cached_words > 0,
        JSON.stringify(built.work),
      );
      assert(
        built.work.scoped_addressed_snapshot_words > width,
        JSON.stringify(built.work),
      );
      await execute(
        built.bytes,
        (input) => new Uint32Array([16 * input + 120, sum(input), sum(input)]),
      );
    });
  });

  Deno.test(`addressed bundles reuse eight exact snapshots and forward nested calls (${codegenTier})`, async () => {
    await withCompiler(codegenTier, async (build) => {
      const repeated = await build(repeatedSource(false));
      const distinct = await build(repeatedSource(true));
      assert(repeated.work.scoped_addressed_cached_words > 0);
      assert(repeated.work.scoped_addressed_forwarded_words > 0);
      assert(distinct.work.scoped_addressed_forwarded_words > 0);
      assert(
        repeated.work.scoped_addressed_snapshot_words <
          distinct.work.scoped_addressed_snapshot_words,
        JSON.stringify({ repeated: repeated.work, distinct: distinct.work }),
      );
      await execute(
        repeated.bytes,
        (input) => new Uint32Array(Array.from({ length: 8 }, () => sum(input))),
      );
      await execute(
        distinct.bytes,
        (input) =>
          new Uint32Array(Array.from({ length: 8 }, (_, i) => sum(input, i))),
      );
    });
  });

  Deno.test(`addressed bundles preserve old closure scalar snapshots after rebinding (${codegenTier})`, async () => {
    await withCompiler(codegenTier, async (build) => {
      const built = await build(`${scalarDefinitions}
entry const answer = func (argument: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[argument]
  let input = marker[0]
  let row = ${wide("input")}
  let before = total row
  let old = func (): U32 => return total row
  row := ${wide("input", 7)}
  let after = total row
  let captured = old ()
  let again = total row
  return #[before, after, captured, again]
`);
      await execute(
        built.bytes,
        (input) =>
          new Uint32Array([
            sum(input),
            sum(input, 7),
            sum(input),
            sum(input, 7),
          ]),
      );
    });
  });

  Deno.test(`addressed descriptors retain owner payload mutation fresh results and borrowed escape checks (${codegenTier})`, async () => {
    await withCompiler(codegenTier, async (build, rejectEscape) => {
      const descriptorLanes = Array.from({ length: 16 }, (_, index) => index);
      const descriptorFields = (value: (index: number) => string) =>
        descriptorLanes.map((index) => `f${index}: ${value(index)},`).join("");
      const source = `type Bundle is data = $Bundle {${
        descriptorFields(() => "Array U32")
      }}
const total = func (row: Bundle): U32 => return do:
  let result = 0
${
        descriptorLanes.map((index) =>
          `  result := @u32.add self row.f${index}[0]`
        ).join("\n")
      }
  return result
const fresh = func (row: Bundle): Array U32 => return #[total row]
entry const answer = func (argument: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[argument]
  let input = marker[0]
${
        descriptorLanes.map((index) =>
          `  let owner_${index}: Array U32 = #[@u32.add input ${index}]`
        ).join("\n")
      }
  let row = $Bundle {${descriptorFields((index) => `owner_${index}`)}}
  let first = total row
  let old = func (): U32 => return total row
  let retained = fresh row
  row.f0[0] := @u32.add self 9
  let second = total row
  let captured = old ()
  let later = fresh row
  return #[first, retained[0], second, captured, later[0], row.f0[0]]
`;
      const built = await build(source);
      await execute(built.bytes, (input) => {
        const initial = input * 16 + 120;
        return new Uint32Array([
          initial,
          initial,
          initial + 9,
          initial + 9,
          initial + 9,
          input + 9,
        ]);
      });
      await rejectEscape();
    });
  });

  Deno.test(`addressed first-use branches zero loops and changing loop carriers stay invocation local (${codegenTier})`, async () => {
    await withCompiler(codegenTier, async (build) => {
      const built = await build(`${scalarDefinitions}
entry const answer = func (argument: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[argument]
  let input = marker[0]
  let row = ${wide("input")}
  let branch = 0
  if @u32.eq (@u32.rem input 2) 0:
    branch := total row
  let after_branch = total row
  let accumulated = 0
  let count = @u32.rem input 4
  for index in 0..count:
    accumulated := @u32.add self (total row)
    row.f0 := @u32.add self 1
  let after_loop = total row
  return #[branch, after_branch, accumulated, after_loop, row.f0]
`);
      await execute(built.bytes, (input) => {
        let branch = 0;
        if (input % 2 === 0) branch = sum(input);
        const count = input % 4;
        return new Uint32Array([
          branch,
          sum(input),
          count * sum(input) + count * (count - 1) / 2,
          sum(input) + count,
          input + count,
        ]);
      });
    });
  });

  Deno.test(`addressed snapshot caps keep scratch results and later calls valid (${codegenTier})`, async () => {
    await withCompiler(codegenTier, async (build) => {
      const declarations: string[] = [];
      const results: string[] = [];
      // More than eight distinct wide arguments force the bounded one-call
      // allocation path; each partial result also needs output scratch storage.
      for (let index = 0; index < 12; index++) {
        declarations.push(`  let row_${index} = ${wide("input", index)}`);
        declarations.push(`  let next_${index} = changed row_${index} 3`);
        declarations.push(`  let result_${index} = total next_${index}`);
        results.push(`result_${index}`);
      }
      declarations.push("  let original = total row_0");
      const built = await build(`${scalarDefinitions}
entry const answer = func (argument: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[argument]
  let input = marker[0]
${declarations.join("\n")}
  return #[${results.join(",")}, original]
`);
      assert(
        built.work.scoped_addressed_calls >= 12,
        JSON.stringify(built.work),
      );
      assert.equal(built.work.scoped_addressed_retained_slots_max, 8);
      await execute(built.bytes, (input) =>
        new Uint32Array([
          ...Array.from({ length: 12 }, (_, index) => sum(input, index) + 3),
          sum(input),
        ]));
    });
  });

  Deno.test(`addressed F32 words retain exact bits through input aliases fresh results and scratch rewind (${codegenTier})`, async () => {
    await withCompiler(codegenTier, async (build) => {
      const source = `type Floats is data = $Floats {${fields(() => "F32")}}
const sum_stage = func (row: Floats): F32 => return do:
  let result = 0.0
${lanes.map((index) => `  result := @f32.add self row.f${index}`).join("\n")}
  return result
const total = func (row: Floats): F32 => return sum_stage row
const keep = func (row: Floats): Floats => return row
const changed = func (row: Floats): Floats => return $Floats {${
        fields((index) => {
          if (index === 0) return "@f32.neg row.f0";
          return `row.f${index}`;
        })
      }}
entry const answer = func (argument: U32): Array U32 => return do:
  let marker: GrowArray U32 = #[argument]
  let bits = marker[0]
  let (input, ignored_a, ignored_b, ignored_c) = @simd.u32x4.from_bits (bits,bits,bits,bits)
  let row = $Floats {${
        fields((index) => {
          if (index === 0) return "input";
          return `@f32.add input ${index}.0`;
        })
      }}
  let checksum = total row
  let old = keep row
  let fresh = changed row
  let again = keep row
  let fresh_again = changed again
  let (a,b,c,d) = @simd.f32x4.bits (old.f0,old.f63,fresh.f0,fresh.f63)
  let (e,f,g,h) = @simd.f32x4.bits (again.f0,again.f63,fresh_again.f0,fresh_again.f63)
  let (check, ignored_d, ignored_e, ignored_f) = @simd.f32x4.bits (checksum,input,input,input)
  return #[a,b,c,d,e,f,g,h,check]
`;
      const built = await build(source);
      await execute(built.bytes, (bits) => {
        const view = new DataView(new ArrayBuffer(4));
        view.setUint32(0, bits, true);
        const input = view.getFloat32(0, true);
        const last = Math.fround(input + 63);
        let checksum = 0;
        for (let index = 0; index < width; index++) {
          let value = input;
          if (index !== 0) value = Math.fround(input + index);
          checksum = Math.fround(checksum + value);
        }
        view.setFloat32(0, last, true);
        const lastBits = view.getUint32(0, true);
        view.setFloat32(0, checksum, true);
        const checksumBits = view.getUint32(0, true);
        return new Uint32Array([
          bits,
          lastBits,
          bits ^ 0x8000_0000,
          lastBits,
          bits,
          lastBits,
          bits ^ 0x8000_0000,
          lastBits,
          checksumBits,
        ]);
      }, [
        0,
        0x8000_0000,
        0x3fc0_0000,
        0xc050_0000,
        0x7f80_0000,
        0xff80_0000,
        0,
        0x8000_0000,
      ]);
    });
  });
}
