import { createHash } from "node:crypto";

// Bend 2.0.24 and 2.0.27 emit model.name_equal as a consuming String traversal. This
// guarded native-only specialization keeps both owned roots alive, borrows
// their immutable nodes, and releases each root exactly once at the end.
// Unknown compiler versions or code shapes fail closed.
const SUPPORTED_BEND_VERSIONS = ["bend 2.0.24", "bend 2.0.27"];
const EXPECTED_MODEL =
  `def name_equal_tail(left: String, right: String, same: Bool) -> Bool:
  match left right same:
    case _ _ False{}:
      False{}
    case SNil{} SNil{} True{}:
      True{}
    case SCon{a, left_tail} SCon{b, right_tail} True{}:
      name_equal_tail(left_tail, right_tail, Char.is_eq(a, b))
    case _ _ True{}:
      False{}

def name_equal(left: String, right: String) -> Bool:
  name_equal_tail(left, right, True{})`;

// SHA-256 of whitespace-free generated functions after alpha-renaming each
// numbered local on first occurrence. Confirmed against both saved final and
// first candidate C emissions, whose temporary numbers differ.
const WRAPPER_SHAPE =
  "2528e96fc294b482a54d50f7b5b395dd957656aabf59dd1581202b136e0b5d3d";
const TAIL_SHAPE =
  "fc8a3e3f151e2ae340f17a8c6a4f4fa2c1f99ebcd5bcccce2d210fe9d8f4ddd8";
const CHAR_EQUAL_SHAPE =
  "9ed92fa22ca86dd8db70114676b142a26131a416a3c3229daf0ffd1b4d5bb2cc";

const RUNTIME_FUNCTIONS = [
  `INLINE u64 term_tag(Term t) {
  return (t >> 56) & 0x7f;
}`,
  `INLINE bool term_rfc(Term t) {
  return (t & RFC_BIT) != 0;
}`,
  `INLINE u64 term_aux(Term t) {
  return (t >> 40) & 0xFFFF;
}`,
  `INLINE Loc term_loc(Term t) {
  return t & LOC_MASK;
}`,
  `INLINE bool term_triv(Term t) {
  return term_tag(t) <= TAG_PAK || t == TERM_HOLE || term_loc(t) < HEAP_OFF;
}`,
  `INLINE u64 rfc_view(Env e, Loc r) {
  DEV u32* w = a32_at(e.mem, r);
  u64 cell = ((u64)a32_load(w + 1) << 32) | a32_load(w);
  if ((cell & RFC_CNT) == 1) {
    a32_acq(w);
  }
  return cell;
}`,
  `INLINE Loc term_peek(Env e, Term t) {
  if (term_rfc(t)) {
    return rfc_view(e, term_loc(t)) >> 24;
  }
  return term_loc(t);
}`,
  `INLINE void term_sink(Env e, Term t) {
  if (!term_triv(t)) {
    term_drop(e, t);
  }
}`,
] as const;

const RUNTIME_DEFINES = [
  "#define LOC_MASK ((1ull << 40) - 1)",
  "#define RFC_BIT  (1ull << 63)",
  "#define RFC_CNT  ((1u << 24) - 1)",
  "#define HEAP_OFF (STAT_OFF + PAGE_UP(STAT_LEN))",
] as const;

type Spin = {
  name: string;
  parameters: string;
  start: number;
  end: number;
  body: string;
};

function spins(source: string): Spin[] {
  const found = [...source.matchAll(
    /^INLINE Term (spin_\d+)\(Env e, THR Term\* o, ([^)]*)\) \{/gm,
  )];
  return found.map((match, index) => {
    const start = match.index;
    const end = index + 1 < found.length
      ? found[index + 1].index - 1
      : source.indexOf("\n// Work", start);
    if (end < start) {
      throw new Error("Bend generated spin section is malformed");
    }
    return {
      name: match[1],
      parameters: match[2],
      start,
      end,
      body: source.slice(start, end),
    };
  });
}

function shape(body: string): string {
  const names = new Map<string, string>();
  const canonical = body.replace(
    /\b_?([a-zA-Z][a-zA-Z0-9]*_\d+)\b/g,
    (name, unprefixed: string) => {
      let symbol = names.get(name);
      if (symbol === undefined) {
        symbol = `${unprefixed.replace(/_\d+$/, "")}_N${names.size}`;
        names.set(name, symbol);
      }
      return symbol;
    },
  ).replace(/\s+/g, "");
  return createHash("sha256").update(canonical).digest("hex");
}

function functionBody(source: string, signature: string): string | undefined {
  const start = source.indexOf(signature);
  if (start < 0 || source.indexOf(signature, start + 1) >= 0) return undefined;
  let depth = 0;
  for (let at = start + signature.length - 1; at < source.length; at++) {
    if (source[at] === "{") depth++;
    if (source[at] === "}" && --depth === 0) {
      return source.slice(start, at + 1);
    }
  }
  return undefined;
}

function verifyRuntime(source: string): void {
  for (const expected of RUNTIME_FUNCTIONS) {
    const signature = expected.slice(0, expected.indexOf("{") + 1);
    const actual = functionBody(source, signature);
    if (actual?.replace(/\s+/g, "") !== expected.replace(/\s+/g, "")) {
      throw new Error(`Bend native runtime helper changed: ${signature}`);
    }
  }
  for (const definition of RUNTIME_DEFINES) {
    const line = `\n${definition}\n`;
    const first = source.indexOf(line);
    if (first < 0 || source.indexOf(line, first + 1) >= 0) {
      throw new Error(`Bend native runtime definition changed: ${definition}`);
    }
  }
  if (
    !/^#define CID_SNIL \d+$/m.test(source) ||
    !/^#define CID_SCON \d+$/m.test(source)
  ) {
    throw new Error("Bend native String constructor IDs changed");
  }
}

function verifySource(modelSource: string, bendVersion: string): void {
  if (!SUPPORTED_BEND_VERSIONS.includes(bendVersion.trim())) {
    throw new Error(
      `Native String comparison specialization requires ${
        SUPPORTED_BEND_VERSIONS.join(" or ")
      }; got ${bendVersion.trim()}`,
    );
  }
  const first = modelSource.indexOf("def name_equal_tail(");
  const last = modelSource.indexOf("def type_id_equal(", first);
  if (
    first < 0 || last < 0 ||
    modelSource.indexOf("def name_equal_tail(", first + 1) >= 0 ||
    modelSource.slice(first, last).trimEnd() !== EXPECTED_MODEL
  ) {
    throw new Error("compiler/model.bend String comparison semantics changed");
  }
}

function borrowedComparison(name: string): string {
  return `INLINE Term ${name}(Env e, THR Term* o, Term r0, Term r1) {
  // Both arguments are owned. Their roots keep every traversed String node
  // alive while term_peek borrows its immutable fields. Release roots once.
  u32 wpoll = 0;
  u32 equal = 1;
  Term left = r0;
  Term right = r1;
  WL_SPIN
    if (left == right) {
      break;
    }
    u32 left_kind = term_aux(left);
    u32 right_kind = term_aux(right);
    if (left_kind != right_kind) {
      equal = 0;
      break;
    }
    if (left_kind == CID_SNIL) {
      break;
    }
    if (left_kind != CID_SCON) {
      equal = 0;
      break;
    }
    Loc left_loc = term_peek(e, left);
    Loc right_loc = term_peek(e, right);
    if (e.mem[left_loc] != e.mem[right_loc]) {
      equal = 0;
      break;
    }
    left = e.mem[left_loc + 1];
    right = e.mem[right_loc + 1];
    WL_AGAIN(${name});
  }
  term_sink(e, r0);
  term_sink(e, r1);
  o[0] = equal;
  return 1;
}`;
}

export function optimizeNativeStringComparison(
  generatedC: string,
  modelSource: string,
  bendVersion: string,
): { source: string; wrapper: string; helper: string } {
  verifySource(modelSource, bendVersion);
  verifyRuntime(generatedC);
  const entries = spins(generatedC);
  const byName = new Map(entries.map((entry) => [entry.name, entry]));
  const candidates = entries.flatMap((wrapper) => {
    if (
      wrapper.parameters !== "Term r0, Term r1" ||
      shape(wrapper.body) !== WRAPPER_SHAPE
    ) return [];
    const helperName = /if \((spin_\d+)\(e, _?o_\d+, \w+, \w+, 1\) == 0\)/
      .exec(wrapper.body)?.[1];
    const helper = helperName && byName.get(helperName);
    if (
      !helper || helper.parameters !== "Term r0, Term r1, u32 r2" ||
      shape(helper.body) !== TAIL_SHAPE
    ) return [];
    const charName = /if \((spin_\d+)\(e, _?o_\d+, _?f_\d+, _?f_\d+\) == 0\)/
      .exec(helper.body)?.[1];
    const charEqual = charName && byName.get(charName);
    return charEqual && charEqual.parameters === "u32 r0, u32 r1" &&
        shape(charEqual.body) === CHAR_EQUAL_SHAPE
      ? [{ wrapper, helper }]
      : [];
  });
  if (candidates.length !== 1) {
    throw new Error(
      `Expected one generated model.name_equal wrapper and tail pair; found ${candidates.length}`,
    );
  }
  const { wrapper, helper } = candidates[0];
  const replacement = borrowedComparison(wrapper.name);
  return {
    source: generatedC.slice(0, wrapper.start) + replacement +
      generatedC.slice(wrapper.end),
    wrapper: wrapper.name,
    helper: helper.name,
  };
}

if (import.meta.main) {
  if (Deno.args.length !== 2) {
    throw new Error(
      "Usage: deno run --allow-read --allow-write --allow-run scripts/native_string_compare.ts <generated.c> <optimized.c>",
    );
  }
  const version = new TextDecoder().decode(
    (await new Deno.Command("bend", {
      args: ["version"],
    }).output()).stdout,
  ).trim();
  const model = await Deno.readTextFile(
    new URL("../compiler/model.bend", import.meta.url),
  );
  const source = await Deno.readTextFile(Deno.args[0]);
  const optimized = optimizeNativeStringComparison(source, model, version);
  await Deno.writeTextFile(Deno.args[1], optimized.source);
  console.log(
    `Specialized ${optimized.wrapper} (model.name_equal via ${optimized.helper})`,
  );
}
