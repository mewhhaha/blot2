import { createHash } from "node:crypto";

/** Native Bend 2.0.27 String traversal. The device keeps Bend's generated cases. */
export type BorrowedStringBase = { map: string; string: string; char: string };

const VERSION = "bend 2.0.27";
const BASE_CONTRACTS = [
  [
    "Map.bit",
    "map",
    "def Map.bit.u(",
    "law Map.msb.u:",
    "31934d72749b4b78f06c58863f44c7b5be177844ca315660f59844367a441452",
  ],
  [
    "String.cmp",
    "string",
    "def String.cmp.rec(",
    "def String.eq.fin(",
    "3aaa6385ce381eccdbc3f04af9fad23ab7c620709031c5c34717a07e1293b8b5",
  ],
  [
    "Char.cmp",
    "char",
    "def Char.cmp(",
    "def Char.to_u32(",
    "b8e5398dea2e0244b3783d1e6b9fa6d50c1c0a61f8f625df3946f3e7e9c51b68",
  ],
] as const;
const FIXTURE_DIGEST =
  "e2ce49b89791de222f066b4314e849f96582134cdf319dfa4b5dde4f38006b45";
const MAP_ASSET_DIGEST =
  "aa8c4eb1819e9baca96997176d6f8752c7b044a5d03d2e9378ea9e02b0fd9064";
const CMP_ASSET_DIGEST =
  "239c0ae0cfbb182284a43adc10215c360ca2d0bb4ae812f68bd0f95c98514dd4";

function digest(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function unique(source: string, marker: string, label: string): number {
  const at = source.indexOf(marker);
  if (at < 0 || source.indexOf(marker, at + marker.length) >= 0) {
    throw new Error(`Borrowed String ${label} missing or ambiguous`);
  }
  return at;
}

function baseSection(
  source: string,
  first: string,
  last: string,
  label: string,
): string {
  const start = unique(source, first, `${label} start`);
  const end = unique(source, last, `${label} end`);
  if (end <= start) {
    throw new Error(`Borrowed String ${label} section reversed`);
  }
  return source.slice(start, end).trim();
}

function verifyBase(base: BorrowedStringBase, version: string): void {
  if (version.trim() !== VERSION) {
    throw new Error(
      `Borrowed String requires ${VERSION}; got ${version.trim()}`,
    );
  }
  for (const [label, key, first, last, expected] of BASE_CONTRACTS) {
    if (digest(baseSection(base[key], first, last, label)) !== expected) {
      throw new Error(`Borrowed String Base semantics changed: ${label}`);
    }
  }
}

function functionBody(source: string, name: string): string {
  const pattern = new RegExp(
    `^(?:INLINE|OUTLINE|FAR) [^\\n]*\\b${name}\\([^\\n]*\\) \\{`,
    "gm",
  );
  const matches = [...source.matchAll(pattern)];
  if (matches.length !== 1) {
    throw new Error(`Borrowed String runtime/helper changed: ${name}`);
  }
  const start = matches[0].index;
  let depth = 0;
  for (let at = start + matches[0][0].length - 1; at < source.length; at++) {
    if (source[at] === "{") depth++;
    if (source[at] === "}" && --depth === 0) return source.slice(start, at + 1);
  }
  throw new Error(`Borrowed String runtime/helper malformed: ${name}`);
}

function generatedShape(
  body: string,
  continuations = new Map<string, string>(),
): string {
  const names = new Map<string, string>();
  const spins = new Map<string, string>();
  const canonical = body
    .replace(
      /\bFID_([A-Z_]+)_([KC])\d+\b/g,
      (name, base: string, kind: string) => {
        if (!continuations.has(name)) {
          continuations.set(name, `FID_${base}_${kind}N${continuations.size}`);
        }
        return continuations.get(name)!;
      },
    )
    .replace(/\bspin_\d+\b/g, (name) => {
      if (!spins.has(name)) spins.set(name, `spin_N${spins.size}`);
      return spins.get(name)!;
    })
    .replace(/\b(_?[A-Za-z][A-Za-z0-9]*_\d+)\b/g, (name) => {
      if (!names.has(name)) {
        names.set(name, `${name.replace(/_\d+$/, "")}_N${names.size}`);
      }
      return names.get(name)!;
    })
    .replace(/\s+/g, "");
  return digest(canonical);
}

function nativeCase(
  source: string,
  name: string,
  continuation = false,
): { start: number; end: number; body: string } {
  const pattern = new RegExp(
    `^#if !DEVICE\\n  WL_CASE\\(FID_${name}${
      continuation ? "_[KC]\\d+" : ""
    }\\)\\n`,
    "gm",
  );
  const matches = [...source.matchAll(pattern)];
  if (matches.length !== 1) {
    throw new Error(
      `Borrowed String generated case missing or ambiguous: ${name}${
        continuation ? " continuation" : ""
      }`,
    );
  }
  const start = matches[0].index;
  const close = source.indexOf("\n#endif", start + matches[0][0].length);
  if (close < 0) {
    throw new Error(`Borrowed String generated case unterminated: ${name}`);
  }
  return {
    start,
    end: close + "\n#endif".length,
    body: source.slice(start, close + "\n#endif".length),
  };
}

function symbol(source: string, prefix: "CID" | "FID", name: string): void {
  const found = [
    ...source.matchAll(new RegExp(`^#define ${prefix}_${name} \\d+$`, "gm")),
  ];
  if (found.length !== 1) {
    throw new Error(
      `Borrowed String generated symbol changed: ${prefix}_${name}`,
    );
  }
}

function verifyRuntime(source: string, reference: string): void {
  for (
    const line of [
      "#define DEVICE  0",
      "typedef uint64_t u64;",
      "typedef uint32_t u32;",
      "typedef u64 Loc;",
      "typedef u64 Term;",
      "#define NAT_IMM ((1ull << 48) - 1)",
      "#define LOC_MASK ((1ull << 40) - 1)",
      "#define RFC_BIT  (1ull << 63)",
      "#define RFC_CNT  ((1u << 24) - 1)",
      "#define a32_load(p)         __atomic_load_n(p, __ATOMIC_RELAXED)",
      "#define a32_load_acq(p)     __atomic_load_n(p, __ATOMIC_ACQUIRE)",
      "#define a32_acq(p)          ((void)a32_load_acq(p))",
      "#define a32_at(H, word) ((DEV u32*)&(H)[word])",
      "#define err_seen(H)    (DEVICE && a32_load(a32_at(H, H_ERROR_CODE)) != 0)",
      "#define err_spun(H, n) ((++*(n) & 4095) == 0 && err_seen(H))",
      "#define WL_RETN(N)  { rn = (N); sp -= LANE_STEP; WL_DYN((Fid)STK(0)); }",
      "#define WL_OPEN    { WL_BANK u32 rn;",
    ]
  ) {
    if (!reference.includes(line)) {
      throw new Error(
        `Borrowed String reference lacks runtime contract: ${line}`,
      );
    }
    unique(source, `${line}\n`, `runtime contract ${line}`);
  }
  for (
    const name of ["term_aux", "term_rfc", "term_loc", "rfc_view", "term_peek"]
  ) {
    if (
      functionBody(source, name).replace(/\s+/g, "") !==
        functionBody(reference, name).replace(/\s+/g, "")
    ) {
      throw new Error(`Borrowed String runtime helper changed: ${name}`);
    }
  }
  for (const name of ["SNIL", "SCON", "CHR"]) symbol(source, "CID", name);
  for (const name of ["MAP_BIT", "MAP_BIT_GO", "STRING_CMP"]) {
    symbol(source, "FID", name);
  }
}

function verifyGenerated(
  source: string,
  reference: string,
): { map: ReturnType<typeof nativeCase>; cmp: ReturnType<typeof nativeCase> } {
  const map = nativeCase(source, "MAP_BIT");
  const cmp = nativeCase(source, "STRING_CMP");
  // Preserve continuation identity across all cases; each case has its own
  // local-variable namespace, but its K/C symbols connect entries to callers.
  const actualContinuations = new Map<string, string>();
  const expectedContinuations = new Map<string, string>();
  for (
    const [label, name, continuation] of [
      ["Map.bit", "MAP_BIT", false],
      ["Map.bit.go", "MAP_BIT_GO", false],
      ["Map.bit.go continuation", "MAP_BIT_GO", true],
      ["String.cmp", "STRING_CMP", false],
      ["String.cmp continuation", "STRING_CMP", true],
    ] as const
  ) {
    if (
      generatedShape(
        nativeCase(source, name, continuation).body,
        actualContinuations,
      ) !==
        generatedShape(
          nativeCase(reference, name, continuation).body,
          expectedContinuations,
        )
    ) {
      throw new Error(`Borrowed String generated case changed: ${label}`);
    }
  }
  // The consumed SCon projection, U32 bit, character comparison and owned
  // reconstruction helpers must agree with the reviewed Bend 2.0.27 emission.
  const mapGo = nativeCase(source, "MAP_BIT_GO").body;
  const mapSpins = [...mapGo.matchAll(/\b(spin_\d+)\(e,/g)].map((match) =>
    match[1]
  );
  if (mapSpins.length !== 2) {
    throw new Error("Borrowed String Map.bit helper calls changed");
  }
  const bitSpin = functionBody(source, mapSpins[0]);
  const u32Calls = [...bitSpin.matchAll(/\b(spin_\d+)\(e,/g)].map((match) =>
    match[1]
  );
  if (u32Calls.length !== 1) {
    throw new Error("Borrowed String Map.bit U32 helper changed");
  }
  const cmpSpins = [...cmp.body.matchAll(/\b(spin_\d+)\(e,/g)].map((match) =>
    match[1]
  );
  if (cmpSpins.length !== 1) {
    throw new Error("Borrowed String Char.cmp helper changed");
  }
  const helperPairs = [
    [bitSpin, functionBody(reference, "spin_579")],
    [functionBody(source, u32Calls[0]), functionBody(reference, "spin_489")],
    [functionBody(source, mapSpins[1]), functionBody(reference, "spin_580")],
    [functionBody(source, cmpSpins[0]), functionBody(reference, "spin_686")],
  ];
  for (const [actual, expected] of helperPairs) {
    if (generatedShape(actual) !== generatedShape(expected)) {
      throw new Error("Borrowed String generated U32/Char helper changed");
    }
  }
  return { map, cmp };
}

export async function optimizeNativeBorrowedStrings(
  generatedC: string,
  base: BorrowedStringBase,
  bendVersion: string,
): Promise<string> {
  verifyBase(base, bendVersion);
  const reference = await Deno.readTextFile(
    new URL("./fixtures/native_borrowed_strings_2_0_27.c", import.meta.url),
  );
  if (digest(reference) !== FIXTURE_DIGEST) {
    throw new Error("Borrowed String reviewed fixture changed");
  }
  verifyRuntime(generatedC, reference);
  const { map, cmp } = verifyGenerated(generatedC, reference);
  const mapAsset = await Deno.readTextFile(
    new URL("./native_kernels/map_bit.c.inc", import.meta.url),
  );
  const cmpAsset = await Deno.readTextFile(
    new URL("./native_kernels/string_cmp.c.inc", import.meta.url),
  );
  if (
    digest(mapAsset) !== MAP_ASSET_DIGEST ||
    digest(cmpAsset) !== CMP_ASSET_DIGEST
  ) {
    throw new Error("Borrowed String reviewed C assets changed");
  }
  const replacements = [
    { ...map, asset: mapAsset.trimEnd() },
    { ...cmp, asset: cmpAsset.trimEnd() },
  ].sort((a, b) => a.start - b.start);
  if (replacements[0].end > replacements[1].start) {
    throw new Error("Borrowed String generated cases overlap");
  }
  return generatedC.slice(0, replacements[0].start) + replacements[0].asset +
    generatedC.slice(replacements[0].end, replacements[1].start) +
    replacements[1].asset + generatedC.slice(replacements[1].end);
}
