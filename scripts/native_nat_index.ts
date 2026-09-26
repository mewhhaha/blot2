import { createHash } from "node:crypto";

/** Bend 2.0.27/2.0.28 native-only replacement for NatIndex.find's branch closures. */
export type NativeNatIndexSources = { natIndex: string };

const SOURCE_CONTRACTS = [
  [
    "data layout",
    "type Index<-V: Data> is Data:",
    "type Difference is Data:",
    "aa85ce34f8c06f426af20cf9002296671960006e4c94fcef1b03ad03f4141b32",
  ],
  [
    "lookup semantics",
    "def prefix(",
    "def fallback(",
    "e1fb6778b2ffbc3b89f1a17621ca2d734f0bc13bc56793e923ee0c4dcc4b1a75",
  ],
] as const;

const RUNTIME_CONTRACTS: Record<string, string> = {
  term_aux: "2858d07f9ea333536fa10c96d7bf90e7dd6e56c3ddefa20c1d34f7968320db34",
  term_rfc: "66baf49d928ad6e940b370c9bc0fe3b5b77b18546f66d54cfdfc61954ec5ec93",
  term_peek: "47fb6315f041740e2085980daadab98785c18329cb5b1b8a462c0832405c1596",
  term_sink: "960cdf90bebb2c1880fd9dd1d37acdf3e5ac5704528816d1d63ae224c3ce0b17",
  term_triv: "4971dcadcb211816ac5e4b2fc07d5fadd1f7783ec35dc59e17081be5b03f84eb",
  rfc_seal: "bd24b528498feced79eb2a3d33fe3305efc14f674b2903edbba93fd5ceecdc63",
  rfc_wrap: "b65b971d4a70bab30d91c425e70b4d55e1778060eceae99ba30b8376f52a0880",
  term_keep: "1434d7ce3ac4bb32ab9dac62509b421a6314f31ee831fe27a15bcca953c09b4b",
  ctr_take: "dd928efa0fdc7adb2c309eaa2e8ef6634a78dcee0eb92c322850d4f222de4902",
  span_fade: "e8e53248c3c38b687f96bdc55b0ce666db02010d653bbf0e7b987db26f389e24",
  spare_free:
    "680254d7c8a90d6abd3f2da30472dbec03de8f2dfa31798e0af32914e9b7eeaa",
};

// Owned-resolver's checked case remains unchanged by its insertion. The
// standalone probe has a different closure-ID numbering but identical fields.
const FULL_CASE_SHAPE =
  "1557718927e2b8b3e00a8f28ef4bc01098477c31d2f587c2a2d3881f7fbb6606";
const PROBE_CASE_SHAPE =
  "7c5fd09075c8cbc40693076efb5036c108814785629e298f6504b3c637f38e1b";
const PROBE_UNSHARED_CASE_SHAPE =
  "fb9400a7738585dba2b4c29d92632a2784c28e28ed8d44ea9b182ffd6ca7645f";
const ASSET_DIGEST =
  "9c3da62bc462f38c4ff70ced89a1f84b3eea6e1bc9f703ac0d714b5b939bb66f";

function digest(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function unique(source: string, marker: string, label: string): number {
  const at = source.indexOf(marker);
  if (at < 0 || source.indexOf(marker, at + marker.length) >= 0) {
    throw new Error(`Native NatIndex ${label} missing or ambiguous`);
  }
  return at;
}

function section(
  source: string,
  first: string,
  last: string,
  label: string,
): string {
  const start = unique(source, first, label);
  const end = source.indexOf(last, start + first.length);
  if (end < 0) throw new Error(`Native NatIndex ${label} end marker missing`);
  return source.slice(start, end).trim();
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
    throw new Error(`Native NatIndex runtime helper changed: ${name}`);
  }
  const start = matches[0].index;
  let depth = 0;
  for (let at = start + matches[0][0].length - 1; at < source.length; at++) {
    if (source[at] === "{") depth++;
    if (source[at] === "}" && --depth === 0) return source.slice(start, at + 1);
  }
  throw new Error(`Native NatIndex runtime helper malformed: ${name}`);
}

function caseShape(body: string): string {
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

function symbol(source: string, prefix: "CID" | "FID", name: string): string {
  const found = [
    ...source.matchAll(new RegExp(`^#define (${prefix}_${name}) \\d+$`, "gm")),
  ];
  if (found.length !== 1) {
    throw new Error(
      `Native NatIndex generated symbol changed: ${prefix}_${name}`,
    );
  }
  return found[0][1];
}

function verify(
  source: string,
  natIndex: string,
  bendVersion: string,
  probe: boolean,
): { start: number; end: number } {
  if (
    bendVersion.trim() !== "bend 2.0.27" && bendVersion.trim() !== "bend 2.0.28"
  ) {
    throw new Error(
      `Native NatIndex requires bend 2.0.27 or 2.0.28; got ${bendVersion.trim()}`,
    );
  }
  for (const [label, start, end, hash] of SOURCE_CONTRACTS) {
    if (digest(section(natIndex, start, end, label)) !== hash) {
      throw new Error(`Native NatIndex Bend source contract changed: ${label}`);
    }
  }
  if (
    source.includes(
      "// Bend Nat.div(x, 0) is 0, so an explicit zero-mask Branch follows low.",
    )
  ) {
    throw new Error("Native NatIndex already patched");
  }
  for (const [name, hash] of Object.entries(RUNTIME_CONTRACTS)) {
    if (digest(functionBody(source, name).replace(/\s+/g, "")) !== hash) {
      throw new Error(`Native NatIndex runtime helper changed: ${name}`);
    }
  }
  for (
    const macro of [
      "#define NAT_IMM ((1ull << 48) - 1)",
      "#define err_spun(H, n) ((++*(n) & 4095) == 0 && err_seen(H))",
      "#define WL_RETN(N)  { rn = (N); sp -= LANE_STEP; WL_DYN((Fid)STK(0)); }",
    ]
  ) {
    if (!source.includes(macro)) {
      throw new Error(`Native NatIndex runtime macro changed: ${macro}`);
    }
  }
  for (const name of ["EMPTY", "LEAF", "BRANCH"]) {
    symbol(source, "CID", `NAT_INDEX_${name}`);
  }
  const fid = symbol(source, "FID", "NAT_INDEX_FIND");
  const start = unique(source, `#if !DEVICE\n  WL_CASE(${fid})\n`, "find case");
  const end = source.indexOf("\n#if !DEVICE\n  WL_CASE(", start + 1);
  if (end < 0) throw new Error("Native NatIndex find case truncated");
  const actual = caseShape(source.slice(start, end));
  if (
    actual !== FULL_CASE_SHAPE &&
    (!probe ||
      (actual !== PROBE_CASE_SHAPE && actual !== PROBE_UNSHARED_CASE_SHAPE))
  ) {
    throw new Error(`Native NatIndex generated find shape changed: ${actual}`);
  }
  if (
    !probe &&
    (!source.includes("static inline bool compact_closed_work") ||
      !source.includes("static bool owned_plan("))
  ) {
    throw new Error(
      "Native NatIndex requires compiler kernels and owned resolver first",
    );
  }
  return { start, end };
}

async function transform(
  generatedC: string,
  sources: NativeNatIndexSources,
  bendVersion: string,
  probe: boolean,
): Promise<string> {
  const source = probe
    ? generatedC.replace(/FID_[A-Z_0-9]*COMPILER_NAT_INDEX_/g, "FID_NAT_INDEX_")
      .replace(/CID_[A-Z_0-9]*COMPILER_NAT_INDEX_/g, "CID_NAT_INDEX_")
    : generatedC;
  const { start, end } = verify(source, sources.natIndex, bendVersion, probe);
  const asset = await Deno.readTextFile(
    new URL("./native_kernels/nat_index.c.inc", import.meta.url),
  );
  if (digest(asset) !== ASSET_DIGEST) {
    throw new Error("Native NatIndex replacement asset changed");
  }
  return source.slice(0, start) + asset.trimEnd() + source.slice(end);
}

export async function optimizeNativeNatIndex(
  generatedC: string,
  sources: NativeNatIndexSources,
  bendVersion: string,
): Promise<string> {
  return transform(generatedC, sources, bendVersion, false);
}

/** The direct Bend oracle contains a namespace-qualified NatIndex import. */
export async function optimizeNativeNatIndexProbe(
  generatedC: string,
  sources: NativeNatIndexSources,
  bendVersion: string,
): Promise<string> {
  return transform(generatedC, sources, bendVersion, true);
}
