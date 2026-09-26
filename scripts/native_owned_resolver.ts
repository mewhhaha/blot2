import { createHash } from "node:crypto";

/** A separately guarded Bend 2.0.27/2.0.28 owned, bounded native type resolver. */
export type OwnedResolverSources = {
  types: string;
  natIndex: string;
  model: string;
};

const SOURCE_CONTRACTS = [
  [
    "types substitutions/version",
    "types",
    "type Substitution is Data:",
    "type TypeWork is Data:",
    "8a8c5792855409feda4cbd01bb27a5fdea7a53884a19975bc418dc470ebe9287",
  ],
  [
    "types flat resolution",
    "types",
    "def flat_variable(",
    "def contains(",
    "3e0e527c9fbf58e545b144bff8b67edc3895a960242441612a239e4bc75be227",
  ],
  [
    "NatIndex data",
    "natIndex",
    "type Index<-V: Data> is Data:",
    "type Difference is Data:",
    "aa85ce34f8c06f426af20cf9002296671960006e4c94fcef1b03ad03f4141b32",
  ],
  [
    "NatIndex find",
    "natIndex",
    "def prefix(",
    "def fallback(",
    "e1fb6778b2ffbc3b89f1a17621ca2d734f0bc13bc56793e923ee0c4dcc4b1a75",
  ],
  [
    "NatIndex insert",
    "natIndex",
    "def difference(",
    "def choose(",
    "1a043be951112ab5e6f10d95fe19510d3da51bb45cdb792722a4a80b9555e39d",
  ],
  [
    "model Ty/rows",
    "model",
    "type RowTail is Data:",
    "type Operation is Data:",
    "896a3a1e93a3fa83eeae225e8da217ef450e90e34d7ee497ec56161d58565c65",
  ],
] as const;

// Complete helper bodies, normalized only for whitespace. These pin RFC
// acquisition, borrowed reads, allocation and root release semantics.
const RUNTIME_CONTRACTS: Record<string, string> = {
  term_aux: "2858d07f9ea333536fa10c96d7bf90e7dd6e56c3ddefa20c1d34f7968320db34",
  term_rfc: "66baf49d928ad6e940b370c9bc0fe3b5b77b18546f66d54cfdfc61954ec5ec93",
  term_peek: "47fb6315f041740e2085980daadab98785c18329cb5b1b8a462c0832405c1596",
  term_sink: "960cdf90bebb2c1880fd9dd1d37acdf3e5ac5704528816d1d63ae224c3ce0b17",
  term_triv: "4971dcadcb211816ac5e4b2fc07d5fadd1f7783ec35dc59e17081be5b03f84eb",
  rfc_seal: "bd24b528498feced79eb2a3d33fe3305efc14f674b2903edbba93fd5ceecdc63",
  rfc_wrap: "b65b971d4a70bab30d91c425e70b4d55e1778060eceae99ba30b8376f52a0880",
  term_keep: "1434d7ce3ac4bb32ab9dac62509b421a6314f31ee831fe27a15bcca953c09b4b",
  heap_alloc:
    "a8533c307d8670f739075bb73d7d425feb92bbac22c3bb0724a8cd3349527e83",
  nat_chk: "d895bb30d62d55f349809881acd0297ff0796fce3334de180a9ec27600fc92d0",
};

const CASE_SHAPES: Record<string, string> = {
  FID_NAT_INDEX_FIND:
    "1557718927e2b8b3e00a8f28ef4bc01098477c31d2f587c2a2d3881f7fbb6606",
  FID_TYPES_APPEND_SUBSTITUTION:
    "2933683a3baea68a9e7f3b459ab5a5ee881362862c326353e41d5e5b68188baf",
  FID_TYPES_RESOLVE_WORK:
    "1b73fe61dcf5a4932dc9ddc7339c71434c2c20ad1f51f7d4457a316a354fa259",
};
// Exact combined emission adds three pre-spin keeps because that spin now
// sinks its arguments. The later owned entry runs before those keeps.
const RESOLVE_PREKEEP_CASE_SHAPE =
  "313c3b0fd978936fd6697504c5b03b558d6101ab10c9b3192fd78577ba28eec5";
const PROBE_CASE_SHAPES: Record<string, string> = {
  FID_NAT_INDEX_FIND:
    "7c5fd09075c8cbc40693076efb5036c108814785629e298f6504b3c637f38e1b",
  FID_TYPES_RESOLVE_WORK:
    "badd132037e1284813ea7eb4e810015ba020bae1f59ce3b4210d006982bc0208",
};
const VERSION_CONSTRUCTION_SHAPES = new Set([
  "e52a183c092457344106bca2df1cf930b38547376fe8b0d7b1e33a4eaa7828c3",
  "c00aff3ef2bfc2cff205fd69b7bd261842902e9fbb6a3f0d76731f2bc55a2335",
]);

const TY_VARIANTS = [
  "UNITTY",
  "U32TY",
  "BOOLTY",
  "APPLIEDTY",
  "FUNCTIONTY",
  "PARAMETERTY",
  "VARIABLETY",
  "NEVERTY",
  "F32TY",
  "PROVIDERTY",
  "STATEPROVIDERTY",
  "EFFECTDESCRIPTORTY",
  "EFFECTSETTY",
  "PRODUCTTY",
  "ARRAYTY",
  "FREETY",
] as const;

function digest(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function unique(source: string, text: string, label: string): number {
  const first = source.indexOf(text);
  if (first < 0 || source.indexOf(text, first + text.length) >= 0) {
    throw new Error(`Owned resolver ${label} missing or ambiguous: ${text}`);
  }
  return first;
}

function section(
  source: string,
  begin: string,
  end: string,
  label: string,
): string {
  const start = unique(source, begin, label);
  const stop = source.indexOf(end, start + begin.length);
  if (stop < 0) throw new Error(`Owned resolver ${label} end marker missing`);
  return source.slice(start, stop);
}

function verifySources(
  sources: OwnedResolverSources,
  bendVersion: string,
): void {
  if (
    bendVersion.trim() !== "bend 2.0.27" && bendVersion.trim() !== "bend 2.0.28"
  ) {
    throw new Error(
      `Owned resolver requires bend 2.0.27 or 2.0.28; got ${bendVersion.trim()}`,
    );
  }
  for (const [label, file, start, end, expected] of SOURCE_CONTRACTS) {
    if (digest(section(sources[file], start, end, label).trim()) !== expected) {
      throw new Error(`Owned resolver Bend source contract changed: ${label}`);
    }
  }
  const modelTy = section(
    sources.model,
    "type Ty is Data:",
    "type Operation is Data:",
    "model.Ty",
  );
  const types = new Set(
    [...modelTy.matchAll(/^  ([A-Za-z0-9_]+)\{/gm)].map((m) =>
      m[1].toUpperCase()
    ),
  );
  if (
    types.size !== TY_VARIANTS.length ||
    TY_VARIANTS.some((name) => !types.has(name))
  ) {
    throw new Error("Owned resolver model.Ty constructor set changed");
  }
}

function functionBody(source: string, name: string): string {
  const found = [
    ...source.matchAll(
      new RegExp(
        `^(?:INLINE|OUTLINE|FAR) [^\\n]*\\b${name}\\([^\\n]*\\) \\{`,
        "gm",
      ),
    ),
  ];
  if (found.length !== 1) {
    throw new Error(`Owned resolver runtime helper changed: ${name}`);
  }
  const start = found[0].index;
  let depth = 0;
  for (let at = start + found[0][0].length - 1; at < source.length; at++) {
    if (source[at] === "{") depth++;
    if (source[at] === "}" && --depth === 0) return source.slice(start, at + 1);
  }
  throw new Error(`Owned resolver runtime helper malformed: ${name}`);
}

function shape(body: string): string {
  const names = new Map<string, string>();
  const canonical = body.replace(/STAT_OFF \+ \d+/g, "STAT_OFF + N")
    .replace(/\b(FID_[A-Z_]+_[KC])\d+\b/g, "$1N")
    .replace(
      /(?<![A-Za-z0-9_])(_?[A-Za-z][A-Za-z0-9_]*_\d+)(?![A-Za-z0-9_])/g,
      (name) => {
        let value = names.get(name);
        if (value === undefined) {
          value = `${name.replace(/_\d+$/, "")}_N${names.size}`;
          names.set(name, value);
        }
        return value;
      },
    ).replace(/\s+/g, "");
  return digest(canonical);
}

function symbol(source: string, prefix: "FID" | "CID", name: string): string {
  const found = [
    ...source.matchAll(new RegExp(`^#define (${prefix}_${name}) \\d+$`, "gm")),
  ];
  if (found.length !== 1) {
    throw new Error(
      `Owned resolver generated symbol changed: ${prefix}_${name}`,
    );
  }
  return found[0][1];
}

function workCase(source: string, fid: string): string {
  const start = unique(source, `#if !DEVICE\n  WL_CASE(${fid})\n`, fid);
  const end = source.indexOf("\n#if !DEVICE\n  WL_CASE(", start + 1);
  if (end < 0) throw new Error(`Owned resolver work case truncated: ${fid}`);
  return source.slice(start, end);
}

function verifyGenerated(source: string, probe = false): void {
  if (source.includes("static bool owned_plan(")) {
    throw new Error("Owned resolver already patched");
  }
  for (const [name, expected] of Object.entries(RUNTIME_CONTRACTS)) {
    if (digest(functionBody(source, name).replace(/\s+/g, "")) !== expected) {
      throw new Error(`Owned resolver runtime helper changed: ${name}`);
    }
  }
  for (
    const macro of [
      "#define NAT_IMM ((1ull << 48) - 1)",
      "#define err_seen(H)    (DEVICE && a32_load(a32_at(H, H_ERROR_CODE)) != 0)",
      "#define err_spun(H, n) ((++*(n) & 4095) == 0 && err_seen(H))",
      "#define WL_RETN(N)  { rn = (N); sp -= LANE_STEP; WL_DYN((Fid)STK(0)); }",
    ]
  ) {
    if (!source.includes(macro)) {
      throw new Error(`Owned resolver runtime macro changed: ${macro}`);
    }
  }
  const generatedTy = new Set(
    [...source.matchAll(/^#define CID_MODEL_([A-Z_0-9]*TY) \d+$/gm)].map((m) =>
      m[1]
    ),
  );
  if (
    generatedTy.size !== TY_VARIANTS.length ||
    TY_VARIANTS.some((name) => !generatedTy.has(name))
  ) {
    throw new Error(
      "Owned resolver generated model.Ty constructor set changed",
    );
  }
  for (const name of TY_VARIANTS) symbol(source, "CID", `MODEL_${name}`);
  for (
    const name of [
      "NAT_INDEX_EMPTY",
      "NAT_INDEX_LEAF",
      "NAT_INDEX_BRANCH",
      "TYPES_VERSION",
      "TYPES_SUBSTITUTIONS",
      "CON",
      "NIL",
    ]
  ) {
    symbol(source, "CID", name);
  }
  for (const [fid, expected] of Object.entries(CASE_SHAPES)) {
    symbol(source, "FID", fid.slice(4));
    const actual = shape(workCase(source, fid));
    if (
      actual !== expected &&
      !(fid === "FID_TYPES_RESOLVE_WORK" &&
        actual === RESOLVE_PREKEEP_CASE_SHAPE) &&
      (!probe || actual !== PROBE_CASE_SHAPES[fid])
    ) {
      throw new Error(`Owned resolver generated field shape changed: ${fid}`);
    }
  }
  const versionCases = [
    ...source.matchAll(
      /^#if !DEVICE\n  WL_CASE\((FID_TYPES_APPEND_SUBSTITUTION_K\d+)\)\n/gm,
    ),
  ]
    .map((match) => workCase(source, match[1]))
    .filter((body) => body.includes("term_ctr(CID_TYPES_VERSION"));
  const versionShapes = new Set(versionCases.map(shape));
  if (
    versionShapes.size !== VERSION_CONSTRUCTION_SHAPES.size ||
    [...VERSION_CONSTRUCTION_SHAPES].some((expected) =>
      !versionShapes.has(expected)
    )
  ) {
    throw new Error(
      "Owned resolver generated Version/Substitutions construction shape changed",
    );
  }
  if (!probe && !source.includes("static inline bool compact_closed_work")) {
    throw new Error("Owned resolver requires guarded closed-type kernel first");
  }
}

export async function optimizeNativeOwnedResolver(
  generatedC: string,
  sources: OwnedResolverSources,
  bendVersion: string,
): Promise<string> {
  return ownedTransform(generatedC, sources, bendVersion, false);
}

/** Direct Bend oracle adapter; it uses the same C helper with reviewed standalone shapes. */
export async function optimizeNativeOwnedResolverProbe(
  generatedC: string,
  sources: OwnedResolverSources,
  bendVersion: string,
): Promise<string> {
  const normalized = generatedC
    .replace(/FID_[A-Z_0-9]*COMPILER_TYPES_/g, "FID_TYPES_")
    .replace(/FID_[A-Z_0-9]*COMPILER_NAT_INDEX_/g, "FID_NAT_INDEX_")
    .replace(/CID_[A-Z_0-9]*COMPILER_MODEL_/g, "CID_MODEL_")
    .replace(/CID_[A-Z_0-9]*COMPILER_NAT_INDEX_/g, "CID_NAT_INDEX_")
    .replace(/CID_[A-Z_0-9]*COMPILER_TYPES_/g, "CID_TYPES_");
  return ownedTransform(normalized, sources, bendVersion, true);
}

async function ownedTransform(
  generatedC: string,
  sources: OwnedResolverSources,
  bendVersion: string,
  probe: boolean,
): Promise<string> {
  verifySources(sources, bendVersion);
  verifyGenerated(generatedC, probe);
  const fid = symbol(generatedC, "FID", "TYPES_RESOLVE_WORK");
  const start = unique(generatedC, `WL_CASE(${fid})`, "resolve entry");
  const first = generatedC.indexOf("    WL_OPEN\n", start);
  if (first < 0 || first - start > 350) {
    throw new Error("Owned resolver entry boundary changed");
  }
  const original = generatedC.slice(start, first);
  const fields =
    /Term (\w+) = r0;\s+Term (\w+) = r1;\s+Term (\w+) = r2;\s+Term (\w+) = r3;\s+Term (\w+) = r4;\s+u32 (\w+) = r5;\s+Term (\w+) = r6;/
      .exec(original);
  if (!fields) {
    throw new Error(
      "Owned resolver split Substitutions/TypeWork layout changed",
    );
  }
  const [, history, values, rows, count, fuel, tag, work] = fields;
  const afterOpen = first + "    WL_OPEN\n".length;
  const next = generatedC.indexOf(`WL_CASE(${fid}_K`, afterOpen);
  if (next < 0) throw new Error("Owned resolver continuation boundary changed");
  const body = generatedC.slice(afterOpen, next);
  let insert = afterOpen;
  let poll = "";
  if (probe) {
    poll = "\n    if (err_seen(e.mem)) return 0;\n";
  } else {
    if (!body.startsWith("\n    if (err_seen(e.mem)) return 0;\n")) {
      throw new Error("Owned resolver cancellation poll changed");
    }
    const closedAt = body.indexOf("compact_closed_work(e, ");
    if (
      closedAt < 0 || body.indexOf("compact_closed_work(e, ", closedAt + 1) >= 0
    ) {
      throw new Error("Owned resolver closed-type predecessor changed");
    }
    const closing = "      WL_RETN(4);\n    }\n";
    const closedEnd = body.indexOf(closing, closedAt);
    if (closedEnd < 0) {
      throw new Error("Owned resolver closed-type return changed");
    }
    insert += closedEnd + closing.length;
  }
  const entry =
    `\n    OwnedTypePlan owned_plan_scratch;\n    unsigned owned_root = 0;\n    if (${tag} == 0 && owned_plan(e, ${work}, ${values}, ${count},\n                                    ${fuel}, &owned_plan_scratch, &owned_root)) {\n      bool owned_changed = owned_plan_scratch.nodes[owned_root].changed;\n      Term owned_output = owned_changed ? owned_freeze(e, &owned_plan_scratch,\n                                                      owned_root) : ${work};\n      Loc owned_at = heap_alloc(e, cls_fit(2));\n      e.mem[owned_at] = rfc_seal(e, owned_output);\n      e.mem[owned_at + 1] = rfc_seal(e, term_pak(CID_NIL, 0));\n      if (owned_changed) term_sink(e, ${work});\n      term_sink(e, ${history});\n      term_sink(e, ${values});\n      term_sink(e, ${rows});\n      r0 = 1;\n      r1 = term_ctr(CID_CON, owned_at);\n      r2 = 0;\n      r3 = 0;\n      WL_RETN(4);\n    }\n`;
  let output = generatedC.slice(0, insert) + poll + entry +
    generatedC.slice(insert);
  let helper = await Deno.readTextFile(
    new URL("./native_kernels/owned_active.c.inc", import.meta.url),
  );
  for (const name of TY_VARIANTS) {
    helper = helper.replaceAll(
      `CID_MODEL_${name}`,
      symbol(generatedC, "CID", `MODEL_${name}`),
    );
  }
  for (const name of ["EMPTY", "LEAF", "BRANCH"]) {
    helper = helper.replaceAll(
      `CID_NAT_INDEX_${name}`,
      symbol(generatedC, "CID", `NAT_INDEX_${name}`),
    );
  }
  helper = helper.replaceAll(
    "CID_TYPES_VERSION",
    symbol(generatedC, "CID", "TYPES_VERSION"),
  );
  const anchor = unique(output, "INLINE Term spin_0(", "spin insertion anchor");
  output = output.slice(0, anchor) + helper + "\n" + output.slice(anchor);
  return output;
}
