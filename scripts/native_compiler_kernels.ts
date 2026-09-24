import { createHash } from "node:crypto";

/**
 * Guarded native-only Bend 2.0.27 kernels. The Bend definitions remain the
 * semantic implementation and the fallback on every unsupported input.
 * This transform runs after native_string_compare.ts, whose selected String
 * comparator is called by the path-consuming Index kernel.
 */
export type NativeKernelSources = {
  index: string;
  types: string;
  model: string;
};

const SOURCE_CONTRACTS = [
  [
    "index.find",
    "index",
    "def character_bit(",
    "def fallback(",
    "f9f75f276df606617ee45132815150bda24435fccf72b0781a61d00cf6f5a355",
  ],
  [
    "types.TypeWork",
    "types",
    "type TypeWork is Data:",
    "type Replacement is Data:",
    "ce610668e2b137f155dc64bb6acc782b82c297aa0874e594a77c965f48a0b7f0",
  ],
  [
    "types.free union",
    "types",
    "def put(",
    "def difference(",
    "41bf9dc5e7931270f268284234cd0f8d9c41ed7581538205451b819e99bca31e",
  ],
  [
    "types.free_work",
    "types",
    "def row_free(",
    "def free(",
    "f5885eacd66737fa5411ba5eb9103ef32abc674542951be2d2b88e689a15f4a5",
  ],
  [
    "types.flat_step",
    "types",
    "def flat_step(",
    "def flat_result(",
    "4e75287ea50fb2df1abb9b5dda75d8457385df7ad3bf918567ce84fc9f1b21a0",
  ],
  [
    "types.resolve dispatch",
    "types",
    "def flat_result(",
    "def contains(",
    "9f6523480565b42bc6428eff23a54815dc5846a8d9d6fb919ab6f32630401467",
  ],
  [
    "model.Ty/rows",
    "model",
    "type RowTail is Data:",
    "type Operation is Data:",
    "896a3a1e93a3fa83eeae225e8da217ef450e90e34d7ee497ec56161d58565c65",
  ],
] as const;

// Each digest covers the complete function, including ownership and error
// behavior. Whitespace is ignored, numeric constructor IDs are checked below.
const RUNTIME_CONTRACTS: Record<string, string> = {
  term_aux: "2858d07f9ea333536fa10c96d7bf90e7dd6e56c3ddefa20c1d34f7968320db34",
  term_peek: "47fb6315f041740e2085980daadab98785c18329cb5b1b8a462c0832405c1596",
  term_sink: "960cdf90bebb2c1880fd9dd1d37acdf3e5ac5704528816d1d63ae224c3ce0b17",
  term_triv: "4971dcadcb211816ac5e4b2fc07d5fadd1f7783ec35dc59e17081be5b03f84eb",
  rfc_seal: "bd24b528498feced79eb2a3d33fe3305efc14f674b2903edbba93fd5ceecdc63",
  rfc_wrap: "b65b971d4a70bab30d91c425e70b4d55e1778060eceae99ba30b8376f52a0880",
  ctr_take: "dd928efa0fdc7adb2c309eaa2e8ef6634a78dcee0eb92c322850d4f222de4902",
  span_fade: "e8e53248c3c38b687f96bdc55b0ce666db02010d653bbf0e7b987db26f389e24",
  heap_alloc:
    "a8533c307d8670f739075bb73d7d425feb92bbac22c3bb0724a8cd3349527e83",
  spare_free:
    "680254d7c8a90d6abd3f2da30472dbec03de8f2dfa31798e0af32914e9b7eeaa",
  term_keep: "1434d7ce3ac4bb32ab9dac62509b421a6314f31ee831fe27a15bcca953c09b4b",
};

const TY_VARIANTS = new Set([
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
]);

// Generated projection shapes were extracted from the Bend 2.0.27 compiler
// emission. They certify the actual flattened constructor fields read by the
// borrowed C helpers, beyond the source declaration and constructor names.
const INDEX_CASE_SHAPE =
  "c8b00256a9ff014e0ee2b83442ee06d3f0b4c657973155679d71c4878e840c45";
const PROBE_INDEX_CASE_SHAPE =
  "04ea8f63cde5b7d997dfaaeed42e1ef735bc81898d5ebce9716a3e06f41dff3d";
const RESOLVE_CASE_SHAPE =
  "badd132037e1284813ea7eb4e810015ba020bae1f59ce3b4210d006982bc0208";
// The combined compiler also keeps Substitutions' first three fields before
// the first spin, whose helper now sinks those copies; its original post-spin
// keeps remain for the continuation. The optimized entry runs before either
// keep group and consumes the original owned fields exactly once.
const RESOLVE_PREKEEP_CASE_SHAPE =
  "b89399b41f87a40de7386060a29dfe9a7050fa9fe31a2262a2463b07a5430ba8";
const PROBE_PROVIDER_BRANCH_SHAPE =
  "9e9eac13f5a7b4dd4442c54c3d79195daba636dfef0ff0323379985198007b85";
const FREE_BRANCH_SHAPES: Record<string, string> = {
  VARIABLETY:
    "3af39347eb23e8b4edbca2f69691ee4159cc16f74a73a66b825bf69bc3ead0b9",
  FUNCTIONTY:
    "7ecc8ef2a70de08114b90d8b7f3cfca3920ec4bcda454c27843e0bd1ebf18d45",
  STATEPROVIDERTY:
    "58bec17ab09df2d26126cd91b181da7514330c0003f94d2a6a7b7b3a318ca0fb",
  PROVIDERTY:
    "82575e513369549489538e5f5d8ece16d51e069967c4850c83e0fc7dc6407ef9",
  APPLIEDTY: "cf2ab96d2737feaad5a66f10ae00e03f850d6b0c04f31deeb2ba5edf925c0d20",
  PRODUCTTY: "640ee4add70017cb334a8fd74941b106214a8b9664c8cb98dc0ac1a8a012b64e",
  ARRAYTY: "8bda2377f210658cbb8b11358a12628ea1c17e91fe22e023749990f5abb3ac78",
};

function digest(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function generatedShape(body: string): string {
  const names = new Map<string, string>();
  const canonical = body.replace(/STAT_OFF \+ \d+/g, "STAT_OFF + N")
    .replace(/\b(FID_[A-Z_]+_[KC])\d+\b/g, "$1N")
    .replace(
      /(?<![A-Za-z0-9_])(_?[A-Za-z][A-Za-z0-9_]*_\d+)(?![A-Za-z0-9_])/g,
      (name) => {
        let symbol = names.get(name);
        if (symbol === undefined) {
          symbol = `${name.replace(/_\d+$/, "")}_N${names.size}`;
          names.set(name, symbol);
        }
        return symbol;
      },
    ).replace(/\s+/g, "");
  return digest(canonical);
}

function once(source: string, needle: string, context: string): number {
  const at = source.indexOf(needle);
  if (at < 0 || source.indexOf(needle, at + needle.length) >= 0) {
    throw new Error(`Native kernel ${context} missing or ambiguous: ${needle}`);
  }
  return at;
}

function section(
  source: string,
  start: string,
  end: string,
  context: string,
): string {
  const a = once(source, start, context);
  const b = source.indexOf(end, a + start.length);
  if (b < 0) throw new Error(`Native kernel ${context} end marker missing`);
  return source.slice(a, b);
}

function verifySources(sources: NativeKernelSources, version: string): void {
  if (version.trim() !== "bend 2.0.27") {
    throw new Error(
      `Native compiler kernels require bend 2.0.27; got ${version.trim()}`,
    );
  }
  for (const [label, file, start, end, expected] of SOURCE_CONTRACTS) {
    if (digest(section(sources[file], start, end, label).trim()) !== expected) {
      throw new Error(`Native kernel Bend source contract changed: ${label}`);
    }
  }
  const block = section(
    sources.model,
    "type Ty is Data:",
    "type Operation is Data:",
    "model.Ty",
  );
  const found = new Set(
    [...block.matchAll(/^  ([A-Za-z0-9_]+)\{/gm)].map((m) =>
      m[1].toUpperCase()
    ),
  );
  if (
    found.size !== TY_VARIANTS.size ||
    [...TY_VARIANTS].some((name) => !found.has(name))
  ) {
    throw new Error("Native kernel model.Ty constructor set changed");
  }
}

function functionBody(source: string, name: string): string {
  const matches = [
    ...source.matchAll(
      new RegExp(
        `^(?:INLINE|OUTLINE|FAR) [^\\n]*\\b${name}\\([^\\n]*\\) \\{`,
        "gm",
      ),
    ),
  ];
  if (matches.length !== 1) {
    throw new Error(`Native kernel runtime helper changed: ${name}`);
  }
  const start = matches[0].index;
  let depth = 0;
  for (let at = start + matches[0][0].length - 1; at < source.length; at++) {
    if (source[at] === "{") depth++;
    if (source[at] === "}" && --depth === 0) return source.slice(start, at + 1);
  }
  throw new Error(`Native kernel runtime helper malformed: ${name}`);
}

function symbol(source: string, name: string): string {
  const prefix = name === "INDEX_FIND_WORK" || name.startsWith("TYPES_")
    ? "FID"
    : "CID";
  const found = [
    ...source.matchAll(new RegExp(`^#define (${prefix}_${name}) \\d+$`, "gm")),
  ];
  if (found.length !== 1) {
    throw new Error(`Native kernel generated symbol changed: ${name}`);
  }
  return found[0][1];
}

function requireSnippet(
  source: string,
  snippet: string,
  context: string,
): void {
  if (!source.includes(snippet)) {
    throw new Error(`Native kernel ${context} layout changed: ${snippet}`);
  }
}

function verifyRuntime(source: string): void {
  for (const [name, expected] of Object.entries(RUNTIME_CONTRACTS)) {
    if (digest(functionBody(source, name).replace(/\s+/g, "")) !== expected) {
      throw new Error(`Native kernel runtime helper changed: ${name}`);
    }
  }
  for (
    const line of [
      "#define err_seen(H)    (DEVICE && a32_load(a32_at(H, H_ERROR_CODE)) != 0)",
      "#define err_spun(H, n) ((++*(n) & 4095) == 0 && err_seen(H))",
      "#define WL_SPIN     for (;;) { if (err_spun(e.mem, &wpoll)) { return 0; }",
      "#define WL_OPEN    { WL_BANK u32 rn;",
      "#define WL_RETN(N)  { rn = (N); sp -= LANE_STEP; WL_DYN((Fid)STK(0)); }",
    ]
  ) requireSnippet(source, line, "runtime macro");
  if (
    source.includes("static inline bool compact_free_work") ||
    source.includes("static inline bool compact_closed_work")
  ) {
    throw new Error("Native compiler kernels already patched");
  }
}

function verifyGenerated(source: string): void {
  verifyRuntime(source);
  const generatedTypes = new Set(
    [...source.matchAll(/^#define CID_MODEL_([A-Z_0-9]*TY) \d+$/gm)].map((m) =>
      m[1]
    ),
  );
  if (
    generatedTypes.size !== TY_VARIANTS.size ||
    [...TY_VARIANTS].some((name) => !generatedTypes.has(name))
  ) {
    throw new Error("Native kernel generated model.Ty constructor set changed");
  }
  for (const name of ["MTIP", "MLEAF", "MNODE", "SNIL", "SCON", "CON", "NIL"]) {
    symbol(source, name);
  }
}

type WorkCase = { start: number; end: number; body: string; fid: string };
function workCase(source: string, suffix: string): WorkCase {
  const fid = symbol(source, suffix);
  const marker = `#if !DEVICE\n  WL_CASE(${fid})\n`;
  const start = once(source, marker, suffix);
  const end = source.indexOf(
    "\n#if !DEVICE\n  WL_CASE(",
    start + marker.length,
  );
  if (end < 0) throw new Error(`Native kernel work case truncated: ${suffix}`);
  return { start, end, body: source.slice(start, end), fid };
}

function replaceCase(
  source: string,
  old: WorkCase,
  replacement: string,
): string {
  return source.slice(0, old.start) + replacement + source.slice(old.end);
}

function injectAfterOpen(
  body: string,
  entry: string,
  requireSpin: boolean,
): string {
  const anchor = requireSpin ? "    WL_OPEN\n    WL_SPIN\n" : "    WL_OPEN\n";
  const at = once(body, anchor, "work entry");
  return body.slice(0, at) + `    WL_OPEN\n\n${entry}` +
    (requireSpin ? "    WL_SPIN\n" : "") + body.slice(at + anchor.length);
}

function mapPlaceholders(
  template: string,
  values: Record<string, string>,
): string {
  let result = template;
  for (const [key, value] of Object.entries(values)) {
    result = result.replaceAll(key, value);
  }
  return result;
}

function insertHelper(source: string, helper: string): string {
  const at = once(source, "INLINE Term spin_0(", "spin insertion anchor");
  return source.slice(0, at) + helper + "\n" + source.slice(at);
}

function indexKernel(source: string, asset: string, probe = false): string {
  const old = workCase(source, "INDEX_FIND_WORK");
  const actualShape = generatedShape(old.body);
  if (
    actualShape !== INDEX_CASE_SHAPE &&
    (!probe || actualShape !== PROBE_INDEX_CASE_SHAPE)
  ) {
    throw new Error("Native kernel Index.find generated shape changed");
  }
  const match =
    /Term (\w+) = r0;\s+Term (\w+) = r1;\s+Term (\w+) = r2;\s+Term (\w+) = r3;/
      .exec(old.body);
  if (!match || old.body.indexOf(match[0]) > 160) {
    throw new Error("Native Index.find entry layout changed");
  }
  const [, index, name, remaining] = match;
  for (
    const snippet of [
      `ctr_take(e, ${index}, 2,`,
      `ctr_take(e, ${index}, 3,`,
      "CID_MTIP",
      "CID_MLEAF",
      `term_clo(${old.fid}`,
      "33ull",
      `term_sink(e, ${remaining})`,
    ]
  ) requireSnippet(old.body, snippet, "Index.find");
  if ((old.body.match(/33ull/g) ?? []).length !== 2) {
    throw new Error("Native kernel Index.find layout changed: position radix");
  }
  const comparator = [
    ...old.body.matchAll(
      new RegExp(`if \\((spin_\\d+)\\(e, \\w+, \\w+, ${name}\\) == 0\\)`, "g"),
    ),
  ];
  if (comparator.length !== 1) {
    throw new Error("Native Index.find comparator layout changed");
  }
  if (
    !asset.includes("spin_3(e, result") ||
    !asset.includes("FID_INDEX_FIND_WORK")
  ) {
    throw new Error("Native Index.find asset placeholder changed");
  }
  const replacement = asset.replaceAll("FID_INDEX_FIND_WORK", old.fid)
    .replace("spin_3(e, result", `${comparator[0][1]}(e, result`);
  return replaceCase(source, old, replacement);
}

function typeCids(source: string): Record<string, string> {
  return Object.fromEntries(
    [
      "VARIABLETY",
      "FUNCTIONTY",
      "STATEPROVIDERTY",
      "PROVIDERTY",
      "APPLIEDTY",
      "PRODUCTTY",
      "ARRAYTY",
    ]
      .map((name) => [`CID_MODEL_${name}`, symbol(source, `MODEL_${name}`)]),
  );
}

function freeKernel(source: string, helper: string, probe = false): string {
  const old = workCase(source, "TYPES_FREE_WORK");
  const match = /Term (\w+) = r0;\s+u32 (\w+) = r1;\s+Term (\w+) = r2;/.exec(
    old.body,
  );
  if (!match || old.body.indexOf(match[0]) > 170) {
    throw new Error("Native free_work entry layout changed");
  }
  const [, fuel, tag, work] = match;
  const kinds = Object.keys(FREE_BRANCH_SHAPES);
  for (let i = 0; i < kinds.length; i++) {
    const start = old.body.indexOf(
      `if (term_aux(${work}) == CID_MODEL_${kinds[i]})`,
    );
    const end = i + 1 < kinds.length
      ? old.body.indexOf(
        `} else if (term_aux(${work}) == CID_MODEL_${kinds[i + 1]})`,
        start,
      )
      : old.body.indexOf(`} else {\n          term_sink(e, ${work});`, start);
    const actualShape = start < 0 || end <= start
      ? ""
      : generatedShape(old.body.slice(start, end));
    if (
      actualShape !== FREE_BRANCH_SHAPES[kinds[i]] &&
      (!probe || kinds[i] !== "PROVIDERTY" ||
        actualShape !== PROBE_PROVIDER_BRANCH_SHAPE)
    ) {
      throw new Error(
        `Native kernel free_work generated field shape changed: ${kinds[i]}`,
      );
    }
  }
  const beforeK = old.body;
  requireSnippet(beforeK, `${old.fid}_K`, "free_work continuation");
  const cids = typeCids(source);
  for (
    const name of [
      "FUNCTIONTY",
      "STATEPROVIDERTY",
      "PROVIDERTY",
      "APPLIEDTY",
      "PRODUCTTY",
      "ARRAYTY",
    ]
  ) {
    requireSnippet(beforeK, `${cids[`CID_MODEL_${name}`]})`, "free_work");
  }
  requireSnippet(beforeK, `ctr_take(e, ${work}, 5,`, "free_work");
  if (
    (beforeK.match(new RegExp(`ctr_take\\(e, ${work}, 5,`, "g")) ?? [])
      .length !== 3
  ) {
    throw new Error("Native kernel free_work layout changed: five-field rows");
  }
  const entry =
    `    if (err_seen(e.mem)) return 0;\n    CompactFree compact_result = { .size = 0 };\n    if (compact_free_work(e, ${tag}, ${work}, ${fuel}, &compact_result)) {\n      Term compact_list = compact_free_list(e, &compact_result);\n      term_sink(e, ${work});\n      r0 = 1;\n      r1 = compact_list;\n      r2 = 0;\n      r3 = 0;\n      WL_RETN(4);\n    }\n`;
  return insertHelper(
    replaceCase(source, old, injectAfterOpen(old.body, entry, true)),
    mapPlaceholders(helper, cids),
  );
}

function closedKernel(source: string, helper: string): string {
  const old = workCase(source, "TYPES_RESOLVE_WORK");
  const shape = generatedShape(old.body);
  if (shape !== RESOLVE_CASE_SHAPE && shape !== RESOLVE_PREKEEP_CASE_SHAPE) {
    throw new Error("Native kernel resolve_work generated shape changed");
  }
  const match =
    /Term (\w+) = r0;\s+Term (\w+) = r1;\s+Term (\w+) = r2;\s+Term (\w+) = r3;\s+Term (\w+) = r4;\s+u32 (\w+) = r5;\s+Term (\w+) = r6;/
      .exec(old.body);
  if (!match || old.body.indexOf(match[0]) > 350) {
    throw new Error("Native resolve_work entry layout changed");
  }
  const [, history, values, rows, count, fuel, tag, work] = match;
  const flat = symbol(source, "TYPES_FLAT_STEP");
  for (const snippet of [flat, `term_keep(e, ${work})`]) {
    requireSnippet(old.body, snippet, "resolve_work");
  }
  const entry =
    `    if (err_seen(e.mem)) return 0;\n    if (${count} != 0 && compact_closed_work(e, ${tag}, ${work}, ${fuel})) {\n      Term compact_result = compact_closed_result(e, ${tag}, ${work});\n      term_sink(e, ${history});\n      term_sink(e, ${values});\n      term_sink(e, ${rows});\n      r0 = 1;\n      r1 = compact_result;\n      r2 = 0;\n      r3 = 0;\n      WL_RETN(4);\n    }\n`;
  return insertHelper(
    replaceCase(source, old, injectAfterOpen(old.body, entry, false)),
    mapPlaceholders(helper, typeCids(source)),
  );
}

export async function optimizeNativeCompilerKernels(
  generatedC: string,
  sources: NativeKernelSources,
  bendVersion: string,
): Promise<string> {
  verifySources(sources, bendVersion);
  verifyGenerated(generatedC);
  const [indexAsset, freeAsset, closedAsset] = await Promise.all([
    "index.c.inc",
    "free.c.inc",
    "closed.c.inc",
  ].map((name) =>
    Deno.readTextFile(new URL(`./native_kernels/${name}`, import.meta.url))
  ));
  let output = indexKernel(generatedC, indexAsset);
  output = freeKernel(output, freeAsset);
  output = closedKernel(output, closedAsset);
  return output;
}

/** Standalone native C oracle mode. Symbols are namespaced by each probe's import path. */
export async function optimizeNativeCompilerKernelProbe(
  generatedC: string,
  sources: NativeKernelSources,
  bendVersion: string,
  kernel: "index" | "free" | "closed",
): Promise<string> {
  verifySources(sources, bendVersion);
  const normalized = generatedC
    .replace(/FID_[A-Z_0-9]*COMPILER_INDEX_/g, "FID_INDEX_")
    .replace(/FID_[A-Z_0-9]*COMPILER_TYPES_/g, "FID_TYPES_")
    .replace(/CID_[A-Z_0-9]*COMPILER_MODEL_/g, "CID_MODEL_");
  verifyRuntime(normalized);
  const asset = await Deno.readTextFile(
    new URL(
      `./native_kernels/${kernel === "closed" ? "closed" : kernel}.c.inc`,
      import.meta.url,
    ),
  );
  if (kernel === "index") return indexKernel(normalized, asset, true);
  const generatedTypes = new Set(
    [...normalized.matchAll(/^#define CID_MODEL_([A-Z_0-9]*TY) \d+$/gm)].map((
      m,
    ) => m[1]),
  );
  if (
    generatedTypes.size !== TY_VARIANTS.size ||
    [...TY_VARIANTS].some((name) => !generatedTypes.has(name))
  ) {
    throw new Error("Native probe generated model.Ty constructor set changed");
  }
  return kernel === "free"
    ? freeKernel(normalized, asset, true)
    : closedKernel(normalized, asset);
}
