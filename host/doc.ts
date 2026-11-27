import {
  basename,
  dirname,
  extname,
  isAbsolute,
  join,
  relative,
  resolve,
} from "node:path";
import { fileURLToPath } from "node:url";
import {
  formatDiagnosticReport,
  type RawDiagnosticRecord,
} from "./diagnostics.ts";
import { generateHtmlDocs, type PrecompiledDocExample } from "./doc_html.ts";
import {
  guestTrapOf,
  instantiateGuest,
  readGuestAbi,
  type ValueType,
} from "./guest.ts";
import {
  extractStandardLibrary,
  findCheckoutCompiler,
} from "./packaged_native.ts";
import { resolveProject } from "./packages.ts";
import {
  decodeTestReport,
  readTestMetadata,
  TEST_REPORT_MAGIC,
  TEST_REPORT_VERSION,
} from "./test_runner.ts";
import { decodeText } from "./text.ts";

// ── Raw JSON shape emitted by `blotc doc-project` ───────────────────────────

interface RawDocField {
  name: string;
  type: string;
  has_default: boolean;
  start: number;
  end: number;
}

interface RawDocConstructor {
  name: string;
  declared_record: boolean;
  payload: string | null;
  fields: RawDocField[];
  start: number;
  end: number;
}

interface RawDocType {
  name: string;
  kind: "data" | "opaque" | "alias";
  private: boolean;
  opaque: boolean;
  params: string[];
  alias: string | null;
  constructors: RawDocConstructor[];
  start: number;
  end: number;
}

interface RawDocTraitMember {
  name: string;
  kind: "value" | "defined_type" | "abstract_type";
  type: string | null;
}

interface RawDocTrait {
  name: string;
  private: boolean;
  params: string[];
  where: string[];
  members: RawDocTraitMember[];
  start: number;
  end: number;
}

interface RawDocEffectOperation {
  name: string;
  parameter: string;
  result: string;
}

interface RawDocEffect {
  name: string;
  private: boolean;
  callable: boolean;
  params: string[];
  operations: RawDocEffectOperation[];
  start: number;
  end: number;
}

interface RawDocValue {
  name: string;
  private: boolean;
  kind: "func" | "const" | "kernel" | "process";
  modifier: string | null;
  type: string;
  own_mask: number;
  own_count: number;
  where: string[];
  associated_type: string | null;
  associated_member: string | null;
  start: number;
  end: number;
}

interface RawDocImplementation {
  name: string;
  private: boolean;
  contract: string;
  head: string[];
  where: string[];
  start: number;
  end: number;
}

interface RawDocModule {
  kind: "doc_module";
  filename: string;
  is_std: boolean;
  is_prelude: boolean;
  types: RawDocType[];
  traits: RawDocTrait[];
  effects: RawDocEffect[];
  values: RawDocValue[];
  implementations: RawDocImplementation[];
}

// ── Public documentation model ──────────────────────────────────────────────

export interface DocCodeBlock {
  id: string;
  moduleId: string;
  moduleImportPath: string;
  itemName: string | null;
  lang: string;
  mode: "run" | "check" | "no_run" | "ignore" | "other";
  code: string;
  expected: string | null;
  line: number;
}

export interface DocField {
  name: string;
  type: string;
  hasDefault: boolean;
  doc: string;
  start: number;
  end: number;
}

export interface DocConstructor {
  name: string;
  declaredRecord: boolean;
  payload: string | null;
  fields: DocField[];
  doc: string;
  start: number;
  end: number;
}

export interface DocValue {
  name: string;
  private: boolean;
  kind: "func" | "const" | "kernel" | "process";
  modifier: string | null;
  type: string;
  signature: string;
  ownMask: number;
  ownCount: number;
  where: string[];
  associatedType: string | null;
  associatedMember: string | null;
  doc: string;
  codeBlocks: DocCodeBlock[];
  start: number;
  end: number;
  anchor: string;
}

export interface DocType {
  name: string;
  kind: "data" | "opaque" | "alias";
  private: boolean;
  opaque: boolean;
  params: string[];
  alias: string | null;
  constructors: DocConstructor[];
  methods: DocValue[];
  doc: string;
  codeBlocks: DocCodeBlock[];
  start: number;
  end: number;
  anchor: string;
}

export interface DocTraitMember {
  name: string;
  kind: "value" | "defined_type" | "abstract_type";
  type: string | null;
}

export interface DocTrait {
  name: string;
  private: boolean;
  params: string[];
  where: string[];
  members: DocTraitMember[];
  doc: string;
  codeBlocks: DocCodeBlock[];
  start: number;
  end: number;
  anchor: string;
}

export interface DocEffectOperation {
  name: string;
  parameter: string;
  result: string;
}

export interface DocEffect {
  name: string;
  private: boolean;
  callable: boolean;
  params: string[];
  operations: DocEffectOperation[];
  doc: string;
  codeBlocks: DocCodeBlock[];
  start: number;
  end: number;
  anchor: string;
}

export interface DocImplementation {
  name: string;
  private: boolean;
  contract: string;
  head: string[];
  where: string[];
  doc: string;
  start: number;
  end: number;
}

export interface DocLinkRef {
  moduleId: string;
  itemName: string | null;
  target: string;
}

export interface DocModule {
  id: string;
  importPath: string;
  filename: string;
  isStd: boolean;
  isPrelude: boolean;
  doc: string;
  codeBlocks: DocCodeBlock[];
  types: DocType[];
  traits: DocTrait[];
  effects: DocEffect[];
  values: DocValue[];
  implementations: DocImplementation[];
  diagnostics: RawDiagnosticRecord[];
}

export interface DocPackage {
  schemaVersion: 1;
  name: string;
  root: string;
  modules: DocModule[];
  brokenLinks: DocLinkRef[];
}

export interface ResolvedDocSymbol {
  moduleId: string;
  importPath: string;
  name: string;
  kind: string;
  anchor: string;
  mdHref: string;
  htmlHref: string;
}

export type SymbolResolver = (
  target: string,
  fromModuleId: string,
) => ResolvedDocSymbol | null;

export interface DocProjectContext {
  name: string;
  root: string;
  files: Array<{ filename: string; id: string; importPath: string }>;
  stdRoot: string;
  prelude: string | null;
  imports: Record<string, string>;
}

export interface GenerateDocOptions {
  target?: string;
  cwd?: string;
  executable?: string | URL;
  stdRoot?: string;
  prelude?: string | null;
  imports?: Record<string, string>;
  includePrivate?: boolean;
}

export interface DocTestResult {
  id: string;
  moduleImportPath: string;
  itemName: string | null;
  mode: DocCodeBlock["mode"];
  passed: boolean;
  skipped: boolean;
  output?: string;
  error?: string;
  durationMs: number;
}

export interface DocTestReport {
  passed: number;
  failed: number;
  skipped: number;
  results: DocTestResult[];
}

// ── Type & signature formatting ─────────────────────────────────────────────

function hasTopLevelComma(s: string): boolean {
  let depth = 0;
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === "(" || ch === "{" || ch === "[") depth++;
    else if (ch === ")" || ch === "}" || ch === "]") depth--;
    else if (depth === 0 && ch === ",") return true;
  }
  return false;
}

function unwrapOuterParens(s: string): string {
  let out = s.trim();
  while (
    out.startsWith("(") && out.endsWith(")") &&
    matchingClose(out, 0) === out.length - 1
  ) {
    const inner = out.slice(1, -1).trim();
    if (hasTopLevelComma(inner)) break;
    out = inner;
  }
  return out;
}

function splitTopLevelArrow(typeStr: string): [string, string] | null {
  const s = unwrapOuterParens(typeStr);
  let depth = 0;
  for (let i = 0; i < s.length - 3; i++) {
    const ch = s[i];
    if (ch === "(" || ch === "{" || ch === "[") depth++;
    else if (ch === ")" || ch === "}" || ch === "]") depth--;
    else if (depth === 0 && s.startsWith(" -> ", i)) {
      return [s.slice(0, i).trim(), s.slice(i + 4).trim()];
    }
  }
  return null;
}

function matchingClose(s: string, openIdx: number): number {
  const open = s[openIdx];
  const close = open === "(" ? ")" : open === "{" ? "}" : "]";
  let depth = 0;
  for (let i = openIdx; i < s.length; i++) {
    if (s[i] === open) depth++;
    else if (s[i] === close) {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function splitTopLevelEffect(s: string): { body: string; effects: string } {
  let depth = 0;
  for (let i = 0; i < s.length - 2; i++) {
    const ch = s[i];
    if (ch === "(" || ch === "{" || ch === "[") depth++;
    else if (ch === ")" || ch === "}" || ch === "]") depth--;
    else if (depth === 0 && s.startsWith(" ! {", i)) {
      return { body: s.slice(0, i).trim(), effects: s.slice(i).trim() };
    }
  }
  return { body: s, effects: "" };
}

export class TypeVarRenamer {
  #seen = new Map<string, string>();
  #preferred: readonly string[];
  #usedNames = new Set<string>();

  constructor(preferred: readonly string[] = []) {
    this.#preferred = preferred;
  }

  rename(raw: string): string {
    let s = raw;
    // Convert `Array ...` to idiomatic Blot `#[...]` and `Packed ...` to `%[...]`
    let prev = "";
    while (prev !== s) {
      prev = s;
      s = s.replace(/\bArray\s+\(([^()]+)\)/g, "#[$1]");
      s = s.replace(/\bArray\s+([*#%?&A-Za-z0-9_.]+)/g, "#[$1]");
      s = s.replace(/\bPacked\s+\(([^()]+)\)/g, "%[$1]");
      s = s.replace(/\bPacked\s+([*#%?&A-Za-z0-9_.]+)/g, "%[$1]");
    }
    // Clean polymorphic open effect row tail `| ?e` -> `| e`
    s = s.replace(/\|\s*\?e\b/g, "| e");
    // Normalize solver type variables `?t123` and bound variables `a0` consistently across one declaration
    const alphabet = "abcdefghijklmnopqrstuvwxyz";
    s = s.replace(/(?:\?t|(?<![A-Za-z0-9_])a)(\d+)\b/g, (token) => {
      let mapped = this.#seen.get(token);
      if (!mapped) {
        const idx = this.#seen.size;
        if (idx < this.#preferred.length && this.#preferred[idx]) {
          mapped = this.#preferred[idx];
        } else {
          let letterIdx = 0;
          while (
            letterIdx < alphabet.length &&
            this.#usedNames.has(alphabet[letterIdx])
          ) {
            letterIdx++;
          }
          mapped = letterIdx < alphabet.length
            ? alphabet[letterIdx]
            : `t${idx}`;
        }
        this.#seen.set(token, mapped);
        this.#usedNames.add(mapped);
      }
      return mapped;
    });
    return s;
  }
}

/** Format a compiler-emitted checked type string into clean Blot syntax. */
export function formatBlotType(
  rawType: string,
  ownMask = 0,
  ownCount = 0,
  renamer?: TypeVarRenamer,
): string {
  const r = renamer ?? new TypeVarRenamer();
  const pretty = r.rename(rawType.trim());
  const params: string[] = [];
  let current = pretty;
  let trailingEffects = "";

  for (let step = 0; step < 32; step++) {
    const unwrapped = unwrapOuterParens(current);
    const { body, effects } = splitTopLevelEffect(unwrapped);
    const pair = splitTopLevelArrow(body);
    if (!pair) break;
    const [lhs, rhs] = pair;
    const isOwn = step < ownCount && ((ownMask >>> step) & 1) === 1;
    let formattedLhs = lhs;
    // Keep parens if lhs itself contains a top-level arrow
    if (
      splitTopLevelArrow(formattedLhs) &&
      !(formattedLhs.startsWith("(") && formattedLhs.endsWith(")"))
    ) {
      formattedLhs = `(${formattedLhs})`;
    }
    if (isOwn && !formattedLhs.startsWith("own ")) {
      formattedLhs = `own ${formattedLhs}`;
    }
    params.push(formattedLhs);
    if (effects) {
      const spacedEffects = effects.startsWith(" ") ? effects : ` ${effects}`;
      // Non-final effectful arrow stays grouped so effect scope stays accurate
      if (splitTopLevelArrow(rhs)) {
        const inner = formatBlotType(
          rhs,
          ownMask >>> (step + 1),
          Math.max(0, ownCount - step - 1),
          r,
        );
        return `${params.join(" -> ")} -> (${inner})${spacedEffects}`;
      }
      trailingEffects = spacedEffects;
      current = rhs;
      break;
    }
    current = rhs;
  }

  if (params.length === 0) return pretty;
  const result = unwrapOuterParens(current);
  return `${params.join(" -> ")} -> ${result}${trailingEffects}`;
}

export function formatValueSignature(raw: RawDocValue): {
  type: string;
  signature: string;
  where: string[];
} {
  const renamer = new TypeVarRenamer();
  const formattedType = formatBlotType(
    raw.type,
    raw.own_mask,
    raw.own_count,
    renamer,
  );
  const formattedWhere = raw.where.map((w) => renamer.rename(w));
  const whereSuffix = formattedWhere.length
    ? ` where { ${formattedWhere.join(", ")} }`
    : "";
  let declHead: string;
  if (raw.modifier === "io") {
    declHead = raw.kind === "const" ? "io const" : "io";
  } else {
    const prefix = raw.modifier ? `#${raw.modifier} ` : "";
    const kw = raw.kind === "const"
      ? "const"
      : raw.kind === "kernel"
      ? "kernel"
      : raw.kind === "process"
      ? "process"
      : "func";
    declHead = `${prefix}${kw}`;
  }
  return {
    type: formattedType,
    where: formattedWhere,
    signature: `${declHead} ${raw.name}: ${formattedType}${whereSuffix}`,
  };
}

// ── UTF-8 offset & doc-comment extraction ───────────────────────────────────

function buildLineStarts(bytes: Uint8Array): number[] {
  const starts = [0];
  for (let i = 0; i < bytes.length; i++) {
    if (bytes[i] === 10) starts.push(i + 1);
  }
  return starts;
}

function byteOffsetToLine(lineStarts: number[], byteOffset: number): number {
  let lo = 0;
  let hi = lineStarts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (lineStarts[mid] <= byteOffset) lo = mid;
    else hi = mid - 1;
  }
  return lo; // 0-based line index
}

function stripCommentPrefix(line: string): string | null {
  const trimmed = line.trimStart();
  if (trimmed.startsWith("///")) {
    const rest = trimmed.slice(3);
    return rest.startsWith(" ") ? rest.slice(1) : rest;
  }
  if (trimmed.startsWith("//!")) {
    const rest = trimmed.slice(3);
    return rest.startsWith(" ") ? rest.slice(1) : rest;
  }
  if (trimmed.startsWith("//")) {
    const rest = trimmed.slice(2);
    return rest.startsWith(" ") ? rest.slice(1) : rest;
  }
  return null;
}

/** Extract module header doc comments (`//!` or leading `//` block before a blank line or `import`). */
export function extractModuleDoc(lines: string[]): {
  doc: string;
  consumedEndLine: number;
} {
  // 1. Explicit `//!` module doc lines at top of file (skipping leading blank lines)
  let i = 0;
  while (i < lines.length && !lines[i].trim()) i++;
  if (i < lines.length && lines[i].trimStart().startsWith("//!")) {
    const collected: string[] = [];
    while (i < lines.length && lines[i].trimStart().startsWith("//!")) {
      const stripped = stripCommentPrefix(lines[i]);
      collected.push(stripped ?? "");
      i++;
    }
    return { doc: collected.join("\n").trim(), consumedEndLine: i };
  }

  // 2. Leading `//` / `///` block followed by a blank line or `import`
  const start = i;
  const collected: string[] = [];
  while (i < lines.length) {
    const trimmed = lines[i].trimStart();
    if (trimmed.startsWith("//")) {
      collected.push(stripCommentPrefix(lines[i]) ?? "");
      i++;
    } else {
      break;
    }
  }
  if (collected.length > 0 && i > start) {
    const nextLine = (lines[i] ?? "").trim();
    if (nextLine === "" || nextLine.startsWith("import ")) {
      return { doc: collected.join("\n").trim(), consumedEndLine: i };
    }
  }
  return { doc: "", consumedEndLine: 0 };
}

/** Extract contiguous leading `//` or `///` comments immediately preceding `declLine` (0-based). */
export function extractDeclDoc(
  lines: string[],
  declLine: number,
  minLine = 0,
): string {
  let cursor = declLine - 1;
  // Walk upward past declaration attributes like `@[...]`
  while (cursor >= minLine && /^\s*@\[.*\]\s*$/.test(lines[cursor])) {
    cursor--;
  }
  const collected: string[] = [];
  while (cursor >= minLine) {
    const trimmed = lines[cursor].trimStart();
    if (!trimmed.startsWith("//") || trimmed.startsWith("//!")) break;
    collected.push(stripCommentPrefix(lines[cursor]) ?? "");
    cursor--;
  }
  if (collected.length === 0) return "";
  collected.reverse();
  return collected.join("\n").trim();
}

// ── Markdown fenced code block & intra-doc link extraction ──────────────────

function parseExpectedComment(code: string): string | null {
  const lines = code.replace(/\r\n?/g, "\n").split("\n");
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i].trim();
    if (!line) continue;
    const match = line.match(/\/\/\s*=>\s*(.+)$/);
    return match ? match[1].trim() : null;
  }
  return null;
}

export function extractCodeBlocks(
  markdown: string,
  moduleId: string,
  moduleImportPath: string,
  itemName: string | null,
  counter: { next: number },
): DocCodeBlock[] {
  if (!markdown.trim()) return [];
  const lines = markdown.replace(/\r\n?/g, "\n").split("\n");
  const blocks: DocCodeBlock[] = [];
  let i = 0;
  while (i < lines.length) {
    const match = lines[i].match(/^(`{3,}|~{3,})\s*(.*)$/);
    if (!match) {
      i++;
      continue;
    }
    const fence = match[1];
    const info = match[2].trim();
    const tokens = info.split(/[\s,]+/).filter(Boolean).map((t) =>
      t.toLowerCase()
    );
    const lang = tokens[0] ?? "";
    const startLine = i + 1;
    const body: string[] = [];
    i++;
    while (i < lines.length && !lines[i].startsWith(fence)) {
      body.push(lines[i]);
      i++;
    }
    if (i < lines.length) i++;
    if (lang !== "blot") continue;
    const mods = new Set(tokens.slice(1));
    let mode: DocCodeBlock["mode"] = "run";
    if (mods.has("ignore")) mode = "ignore";
    else if (mods.has("no_run") || mods.has("norun")) mode = "no_run";
    else if (mods.has("check")) mode = "check";
    const code = body.join("\n");
    const slugMod = moduleId.replace(/[^A-Za-z0-9]+/g, "_");
    const slugItem = itemName
      ? itemName.replace(/[^A-Za-z0-9]+/g, "_")
      : "module";
    blocks.push({
      id: `${slugMod}__${slugItem}__${counter.next++}`,
      moduleId,
      moduleImportPath,
      itemName,
      lang,
      mode,
      code,
      expected: parseExpectedComment(code),
      line: startLine,
    });
  }
  return blocks;
}

export function makeAnchor(kind: string, name: string): string {
  const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(
    /^-+|-+$/g,
    "",
  );
  return `${kind}-${slug}`;
}

export function buildSymbolResolver(pkg: DocPackage): SymbolResolver {
  const byModuleId = new Map<string, DocModule>();
  const byImportPath = new Map<string, DocModule>();
  const moduleSymbols = new Map<string, Map<string, ResolvedDocSymbol>>();
  const globalByName = new Map<string, ResolvedDocSymbol[]>();

  const register = (mod: DocModule, sym: ResolvedDocSymbol) => {
    let table = moduleSymbols.get(mod.id);
    if (!table) {
      table = new Map();
      moduleSymbols.set(mod.id, table);
    }
    if (!table.has(sym.name)) table.set(sym.name, sym);
    const list = globalByName.get(sym.name) ?? [];
    list.push(sym);
    globalByName.set(sym.name, list);
  };

  for (const mod of pkg.modules) {
    byModuleId.set(mod.id, mod);
    byImportPath.set(mod.importPath, mod);
    const mdHrefBase = `modules/${mod.id}.md`;
    const htmlHrefBase = `modules/${mod.id}.html`;
    for (const ty of mod.types) {
      register(mod, {
        moduleId: mod.id,
        importPath: mod.importPath,
        name: ty.name,
        kind: "type",
        anchor: ty.anchor,
        mdHref: `${mdHrefBase}#${ty.anchor}`,
        htmlHref: `${htmlHrefBase}#${ty.anchor}`,
      });
      for (const c of ty.constructors) {
        register(mod, {
          moduleId: mod.id,
          importPath: mod.importPath,
          name: `$${c.name}`,
          kind: "constructor",
          anchor: ty.anchor,
          mdHref: `${mdHrefBase}#${ty.anchor}`,
          htmlHref: `${htmlHrefBase}#${ty.anchor}`,
        });
      }
      for (const m of ty.methods) {
        register(mod, {
          moduleId: mod.id,
          importPath: mod.importPath,
          name: m.name,
          kind: m.kind,
          anchor: m.anchor,
          mdHref: `${mdHrefBase}#${m.anchor}`,
          htmlHref: `${htmlHrefBase}#${m.anchor}`,
        });
      }
    }
    for (const tr of mod.traits) {
      register(mod, {
        moduleId: mod.id,
        importPath: mod.importPath,
        name: tr.name,
        kind: "trait",
        anchor: tr.anchor,
        mdHref: `${mdHrefBase}#${tr.anchor}`,
        htmlHref: `${htmlHrefBase}#${tr.anchor}`,
      });
    }
    for (const eff of mod.effects) {
      register(mod, {
        moduleId: mod.id,
        importPath: mod.importPath,
        name: eff.name,
        kind: "effect",
        anchor: eff.anchor,
        mdHref: `${mdHrefBase}#${eff.anchor}`,
        htmlHref: `${htmlHrefBase}#${eff.anchor}`,
      });
    }
    for (const val of mod.values) {
      register(mod, {
        moduleId: mod.id,
        importPath: mod.importPath,
        name: val.name,
        kind: val.kind,
        anchor: val.anchor,
        mdHref: `${mdHrefBase}#${val.anchor}`,
        htmlHref: `${htmlHrefBase}#${val.anchor}`,
      });
    }
  }

  const findModule = (ref: string): DocModule | undefined => {
    const clean = ref.replace(/\.blot$/, "");
    if (byImportPath.has(clean)) return byImportPath.get(clean);
    if (byModuleId.has(clean)) return byModuleId.get(clean);
    for (const mod of pkg.modules) {
      if (mod.importPath.endsWith(`/${clean}`) || mod.id === clean) return mod;
    }
    return undefined;
  };

  return (
    rawTarget: string,
    fromModuleId: string,
  ): ResolvedDocSymbol | null => {
    const target = rawTarget.trim();
    if (!target) return null;

    // 1. Same-module symbol lookup
    const local = moduleSymbols.get(fromModuleId)?.get(target);
    if (local) return local;

    // 2. Qualified module/Symbol or module::Symbol
    const sep = target.includes("::")
      ? target.lastIndexOf("::")
      : target.lastIndexOf("/");
    if (sep > 0) {
      const modPart = target.slice(0, sep);
      const symPart = target.slice(sep + (target.includes("::") ? 2 : 1));
      const mod = findModule(modPart);
      if (mod && symPart) {
        const hit = moduleSymbols.get(mod.id)?.get(symPart);
        if (hit) return hit;
      }
    }

    // 3. Whole-module reference (e.g. `std/vector` or `vector`)
    const modOnly = findModule(target);
    if (modOnly) {
      return {
        moduleId: modOnly.id,
        importPath: modOnly.importPath,
        name: modOnly.importPath,
        kind: "module",
        anchor: "",
        mdHref: `modules/${modOnly.id}.md`,
        htmlHref: `modules/${modOnly.id}.html`,
      };
    }

    // 4. Unique global symbol across the package
    const globals = globalByName.get(target);
    if (globals && globals.length === 1) return globals[0];

    return null;
  };
}

/** Collect all intra-doc link targets from Markdown (ignoring fenced code blocks). */
export function extractIntraDocLinkTargets(markdown: string): string[] {
  if (!markdown) return [];
  const targets: string[] = [];
  const lines = markdown.replace(/\r\n?/g, "\n").split("\n");
  let inFence = false;
  let fence = "";
  for (const line of lines) {
    const f = line.match(/^(`{3,}|~{3,})/);
    if (f) {
      if (!inFence) {
        inFence = true;
        fence = f[1];
      } else if (line.startsWith(fence)) {
        inFence = false;
        fence = "";
      }
      continue;
    }
    if (inFence) continue;
    // Match [`Target`] (not followed by `(`)
    for (const m of line.matchAll(/\[`([^`]+)`\](?!\()/g)) {
      targets.push(m[1].trim());
    }
    // Match [label](`Target`) and [label](blot:Target)
    for (
      const m of line.matchAll(/\[[^\]]+\]\((?:`([^`]+)`|blot:([^)]+))\)/g)
    ) {
      const t = (m[1] ?? m[2] ?? "").trim();
      if (t) targets.push(t);
    }
  }
  return targets;
}

/** Rewrite intra-doc links in Markdown to relative `.md#anchor` paths. */
export function rewriteMarkdownLinks(
  markdown: string,
  fromModuleId: string,
  resolveLink: SymbolResolver,
  fromDepthPrefix: string,
): string {
  if (!markdown) return "";
  const lines = markdown.replace(/\r\n?/g, "\n").split("\n");
  let inFence = false;
  let fence = "";
  const out = lines.map((line) => {
    const f = line.match(/^(`{3,}|~{3,})/);
    if (f) {
      if (!inFence) {
        inFence = true;
        fence = f[1];
      } else if (line.startsWith(fence)) {
        inFence = false;
        fence = "";
      }
      return line;
    }
    if (inFence) return line;
    let rewritten = line.replace(
      /\[`([^`]+)`\](?!\()/g,
      (full, target: string) => {
        const hit = resolveLink(target, fromModuleId);
        if (!hit) return full;
        const href = hit.moduleId === fromModuleId && hit.anchor
          ? `#${hit.anchor}`
          : `${fromDepthPrefix}${hit.mdHref}`;
        return `[\`${target}\`](${href})`;
      },
    );
    rewritten = rewritten.replace(
      /\[([^\]]+)\]\((?:`([^`]+)`|blot:([^)]+))\)/g,
      (full, label: string, backtickTarget?: string, schemeTarget?: string) => {
        const target = (backtickTarget ?? schemeTarget ?? "").trim();
        const hit = resolveLink(target, fromModuleId);
        if (!hit) return full;
        const href = hit.moduleId === fromModuleId && hit.anchor
          ? `#${hit.anchor}`
          : `${fromDepthPrefix}${hit.mdHref}`;
        return `[${label}](${href})`;
      },
    );
    return rewritten;
  });
  return out.join("\n");
}

// ── Project & library discovery (`blot.json`, `pen.json`, `std`, paths) ─────

interface PenProjectConfig {
  root: string;
  stdRoot?: string;
  prelude?: string | null;
  imports: Record<string, string>;
}

async function findPenProject(
  startDir: string,
): Promise<PenProjectConfig | null> {
  let current = resolve(startDir);
  while (true) {
    const candidate = join(current, "pen.json");
    try {
      const info = await Deno.stat(candidate);
      if (info.isFile) {
        const parsed = JSON.parse(await Deno.readTextFile(candidate)) as {
          compiler?: {
            settings?: {
              std?: string;
              prelude?: string | null;
              imports?: Record<string, string>;
            };
          };
        };
        const settings = parsed.compiler?.settings;
        const imports: Record<string, string> = Object.create(null);
        if (settings?.imports && typeof settings.imports === "object") {
          for (const [prefix, rel] of Object.entries(settings.imports)) {
            if (typeof rel === "string") {
              imports[prefix] = resolve(current, rel);
            }
          }
        }
        const stdRoot = typeof settings?.std === "string"
          ? resolve(current, settings.std)
          : undefined;
        let prelude: string | null | undefined;
        if (settings?.prelude === null) prelude = null;
        else if (typeof settings?.prelude === "string") {
          prelude = resolve(current, settings.prelude);
        }
        return { root: current, stdRoot, prelude, imports };
      }
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
    }
    const parent = dirname(current);
    if (parent === current) return null;
    current = parent;
  }
}

async function collectBlotFiles(
  dir: string,
  skipTests = true,
): Promise<string[]> {
  const results: string[] = [];
  const skipNames = new Set([
    ".git",
    "build",
    "node_modules",
    "target",
    ".cache",
    ...(skipTests ? ["tests", "test", "fixtures"] : []),
  ]);
  const walk = async (current: string) => {
    const entries: Deno.DirEntry[] = [];
    for await (const entry of Deno.readDir(current)) {
      entries.push(entry);
    }
    entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
    for (const entry of entries) {
      if (entry.name.startsWith(".")) continue;
      const full = join(current, entry.name);
      if (entry.isDirectory) {
        if (skipNames.has(entry.name)) continue;
        await walk(full);
      } else if (entry.isFile && entry.name.endsWith(".blot")) {
        results.push(full);
      }
    }
  };
  await walk(dir);
  return results;
}

async function pathExists(path: string): Promise<Deno.FileInfo | null> {
  try {
    return await Deno.stat(path);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return null;
    throw error;
  }
}

function toPosix(p: string): string {
  return p.replaceAll("\\", "/");
}

function stripBlotExt(p: string): string {
  return p.endsWith(".blot") ? p.slice(0, -5) : p;
}

export async function discoverDocContext(
  options: GenerateDocOptions,
  bundledStdRoot: string,
): Promise<DocProjectContext> {
  const cwd = resolve(options.cwd ?? Deno.cwd());
  const target = options.target?.trim();
  const baseImports: Record<string, string> = Object.create(null);

  // Merge blot.json or pen.json from cwd or target directory
  const probeDir = target && await pathExists(resolve(cwd, target))
    ? ((await pathExists(resolve(cwd, target)))!.isDirectory
      ? resolve(cwd, target)
      : dirname(resolve(cwd, target)))
    : cwd;

  const blotPkg = await resolveProject(probeDir).catch(() => undefined);
  const penPkg = !blotPkg ? await findPenProject(probeDir) : null;

  let stdRoot = options.stdRoot
    ? resolve(cwd, options.stdRoot)
    : penPkg?.stdRoot ?? bundledStdRoot;
  let prelude: string | null = options.prelude !== undefined
    ? (options.prelude === null ? null : resolve(cwd, options.prelude))
    : blotPkg
    ? blotPkg.prelude
    : penPkg?.prelude !== undefined
    ? penPkg.prelude
    : join(stdRoot, "prelude.blot");

  if (blotPkg) {
    for (const [k, v] of Object.entries(blotPkg.imports)) {
      if (k === "std/") stdRoot = v;
      else baseImports[k] = v;
    }
  } else if (penPkg) {
    for (const [k, v] of Object.entries(penPkg.imports)) {
      baseImports[k] = v;
    }
  }
  if (options.imports) {
    for (const [k, v] of Object.entries(options.imports)) {
      baseImports[k] = resolve(cwd, v);
    }
  }

  // Case 1: `std` or `std/<mod>`
  if (target === "std" || target?.startsWith("std/")) {
    const stdDir = resolve(stdRoot);
    if (target === "std") {
      const files = await collectBlotFiles(stdDir, false);
      return {
        name: "std",
        root: stdDir,
        files: files.map((f) => {
          const rel = stripBlotExt(toPosix(relative(stdDir, f)));
          return { filename: f, id: `std/${rel}`, importPath: `std/${rel}` };
        }),
        stdRoot: stdDir,
        prelude,
        imports: baseImports,
      };
    }
    const sub = target.slice(4).replace(/\.blot$/, "");
    const candidate = join(stdDir, `${sub}.blot`);
    if (await pathExists(candidate)) {
      return {
        name: "std",
        root: stdDir,
        files: [{
          filename: candidate,
          id: `std/${sub}`,
          importPath: `std/${sub}`,
        }],
        stdRoot: stdDir,
        prelude,
        imports: baseImports,
      };
    }
    throw new Error(`Standard library module not found: ${target}`);
  }

  // Case 2: Alias target from blot.json / pen.json (e.g. `ink` or `ink/codec`)
  if (target && !target.startsWith(".") && !isAbsolute(target)) {
    const firstSlash = target.indexOf("/");
    const aliasName = firstSlash === -1 ? target : target.slice(0, firstSlash);
    const aliasPrefix = `${aliasName}/`;
    const aliasDir = baseImports[aliasPrefix];
    if (aliasDir && await pathExists(aliasDir)) {
      if (firstSlash === -1) {
        const files = await collectBlotFiles(aliasDir, true);
        return {
          name: aliasName,
          root: aliasDir,
          files: files.map((f) => {
            const rel = stripBlotExt(toPosix(relative(aliasDir, f)));
            return {
              filename: f,
              id: `${aliasName}/${rel}`,
              importPath: `${aliasName}/${rel}`,
            };
          }),
          stdRoot,
          prelude,
          imports: baseImports,
        };
      }
      const sub = target.slice(firstSlash + 1).replace(/\.blot$/, "");
      const fileCandidate = join(aliasDir, `${sub}.blot`);
      if (await pathExists(fileCandidate)) {
        return {
          name: aliasName,
          root: aliasDir,
          files: [{
            filename: fileCandidate,
            id: `${aliasName}/${sub}`,
            importPath: `${aliasName}/${sub}`,
          }],
          stdRoot,
          prelude,
          imports: baseImports,
        };
      }
      const dirCandidate = join(aliasDir, sub);
      const dirInfo = await pathExists(dirCandidate);
      if (dirInfo?.isDirectory) {
        const files = await collectBlotFiles(dirCandidate, true);
        return {
          name: aliasName,
          root: aliasDir,
          files: files.map((f) => {
            const rel = stripBlotExt(toPosix(relative(aliasDir, f)));
            return {
              filename: f,
              id: `${aliasName}/${rel}`,
              importPath: `${aliasName}/${rel}`,
            };
          }),
          stdRoot,
          prelude,
          imports: baseImports,
        };
      }
    }
  }

  // Case 3: Explicit file or directory (or cwd when omitted)
  const resolvedTarget = target ? resolve(cwd, target) : cwd;
  const info = await pathExists(resolvedTarget);
  if (!info) {
    throw new Error(`Documentation target not found: ${target ?? cwd}`);
  }

  if (info.isFile) {
    const dir = dirname(resolvedTarget);
    const name = stripBlotExt(basename(resolvedTarget));
    // Check if this file falls under an import alias (e.g. `ink/codec`)
    let importPath = name;
    for (const [prefix, aliasDir] of Object.entries(baseImports)) {
      const rel = relative(aliasDir, resolvedTarget);
      if (!rel.startsWith("..") && !isAbsolute(rel)) {
        importPath = `${prefix}${stripBlotExt(toPosix(rel))}`;
        break;
      }
    }
    const relStd = relative(stdRoot, resolvedTarget);
    if (!relStd.startsWith("..") && !isAbsolute(relStd)) {
      importPath = `std/${stripBlotExt(toPosix(relStd))}`;
    }
    return {
      name: basename(dir),
      root: dir,
      files: [{
        filename: resolvedTarget,
        id: importPath,
        importPath,
      }],
      stdRoot,
      prelude,
      imports: baseImports,
    };
  }

  // Directory target: if it's a pen.json root with a matching library alias, use that library root
  const dirName = basename(resolvedTarget);
  if (penPkg && penPkg.root === resolvedTarget) {
    const ownAlias = `${dirName}/`;
    const libDir = penPkg.imports[ownAlias] ??
      (await pathExists(join(resolvedTarget, "lib"))
        ? join(resolvedTarget, "lib")
        : null);
    if (libDir) {
      const prefix = penPkg.imports[ownAlias] ? ownAlias : "";
      const files = await collectBlotFiles(libDir, true);
      return {
        name: dirName,
        root: libDir,
        files: files.map((f) => {
          const rel = stripBlotExt(toPosix(relative(libDir, f)));
          const id = prefix ? `${prefix}${rel}` : rel;
          return { filename: f, id, importPath: id };
        }),
        stdRoot,
        prelude,
        imports: baseImports,
      };
    }
  }

  const files = await collectBlotFiles(resolvedTarget, true);
  if (files.length === 0) {
    throw new Error(`No .blot files found in ${resolvedTarget}`);
  }
  return {
    name: dirName,
    root: resolvedTarget,
    files: files.map((f) => {
      const rel = stripBlotExt(toPosix(relative(resolvedTarget, f)));
      return { filename: f, id: rel, importPath: rel };
    }),
    stdRoot,
    prelude,
    imports: baseImports,
  };
}

// ── Invoke `blotc doc-project` ──────────────────────────────────────────────

async function invokeDocProject(
  compiler: string | URL,
  entry: string,
  context: {
    stdRoot: string;
    prelude: string | null;
    imports: Record<string, string>;
    includePrivate?: boolean;
  },
): Promise<{
  modules: RawDocModule[];
  diagnostics: RawDiagnosticRecord[];
  success: boolean;
}> {
  const args = ["doc-project", entry];
  if (context.includePrivate) args.push("--include-private");
  args.push("--std-root", context.stdRoot);
  args.push("--prelude", context.prelude ?? "none");
  for (const [prefix, dir] of Object.entries(context.imports)) {
    args.push("--alias", `${prefix}=${dir}`);
  }
  const output = await new Deno.Command(compiler, {
    args,
    stdout: "piped",
    stderr: "piped",
  }).output();
  const stdout = new TextDecoder().decode(output.stdout);
  const modules: RawDocModule[] = [];
  const diagnostics: RawDiagnosticRecord[] = [];
  for (const line of stdout.split("\n")) {
    if (!line.trim()) continue;
    try {
      const record = JSON.parse(line) as { kind?: string };
      if (record.kind === "doc_module") {
        modules.push(record as unknown as RawDocModule);
      } else if (record.kind === "diagnostic") {
        diagnostics.push(record as unknown as RawDiagnosticRecord);
      }
    } catch {
      // ignore non-JSON stderr/debug lines
    }
  }
  return { modules, diagnostics, success: output.success };
}

async function resolveCompilerExecutable(
  executable?: string | URL,
): Promise<string | URL> {
  if (executable) return executable;
  const found = await findCheckoutCompiler();
  if (found) return found;
  return new URL("../compiler-goose/build/blotc-goose", import.meta.url);
}

/** Generate the full checked documentation model for a Blot file, library, or package. */
export async function generateDocs(
  options: GenerateDocOptions = {},
): Promise<{
  pkg: DocPackage;
  context: DocProjectContext;
  resolveLink: SymbolResolver;
}> {
  let library: Awaited<ReturnType<typeof extractStandardLibrary>> | undefined;
  try {
    if (Deno.build.standalone && !options.stdRoot) {
      library = await extractStandardLibrary();
    }
    const bundledStd = library?.path ??
      fileURLToPath(new URL("../std/", import.meta.url));
    const context = await discoverDocContext(options, bundledStd);
    const compiler = await resolveCompilerExecutable(options.executable);

    // Map real paths -> RawDocModule
    const rawByRealPath = new Map<string, RawDocModule>();
    const diagsByRealPath = new Map<string, RawDiagnosticRecord[]>();
    const recordDiags = async (diags: RawDiagnosticRecord[]) => {
      for (const d of diags) {
        let key = d.filename ?? "";
        if (key) {
          try {
            key = await Deno.realPath(key);
          } catch {
            // keep original path
          }
        }
        const list = diagsByRealPath.get(key) ?? [];
        list.push(d);
        diagsByRealPath.set(key, list);
      }
    };

    const realPathOf = async (p: string): Promise<string> => {
      try {
        return await Deno.realPath(p);
      } catch {
        return resolve(p);
      }
    };

    const preludeReal = context.prelude
      ? await realPathOf(context.prelude)
      : null;

    if (context.files.length === 1) {
      const only = context.files[0];
      const onlyReal = await realPathOf(only.filename);
      const res = await invokeDocProject(compiler, only.filename, {
        stdRoot: context.stdRoot,
        prelude: onlyReal === preludeReal ? null : context.prelude,
        imports: context.imports,
        includePrivate: options.includePrivate,
      });
      for (const m of res.modules) {
        rawByRealPath.set(await realPathOf(m.filename), m);
      }
      await recordDiags(res.diagnostics);
    } else {
      // Batch-check all non-prelude files in one fast `blotc doc-project` pass via a temp umbrella file.
      const nonPrelude: typeof context.files = [];
      let preludeEntry: (typeof context.files)[number] | null = null;
      for (const f of context.files) {
        if (preludeReal && (await realPathOf(f.filename)) === preludeReal) {
          preludeEntry = f;
        } else {
          nonPrelude.push(f);
        }
      }

      if (nonPrelude.length > 0) {
        const tmpDir = await Deno.makeTempDir({ prefix: "blot-doc-batch-" });
        try {
          const umbrella = join(tmpDir, "_umbrella.blot");
          const lines: string[] = [];
          const batchImports: Record<string, string> = {
            ...context.imports,
            "__doc_root__/": context.root,
          };
          for (let i = 0; i < nonPrelude.length; i++) {
            const rel = stripBlotExt(
              toPosix(relative(context.root, nonPrelude[i].filename)),
            );
            lines.push(`import * as _m${i} from "__doc_root__/${rel}"`);
          }
          await Deno.writeTextFile(umbrella, lines.join("\n") + "\n");
          const res = await invokeDocProject(compiler, umbrella, {
            stdRoot: context.stdRoot,
            prelude: context.prelude,
            imports: batchImports,
            includePrivate: options.includePrivate,
          });
          for (const m of res.modules) {
            rawByRealPath.set(await realPathOf(m.filename), m);
          }
          await recordDiags(res.diagnostics);
        } finally {
          await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
        }
      }

      // Check prelude separately (or if batch already emitted it, reuse!)
      if (preludeEntry && !rawByRealPath.has(preludeReal!)) {
        const res = await invokeDocProject(compiler, preludeEntry.filename, {
          stdRoot: context.stdRoot,
          prelude: null,
          imports: context.imports,
          includePrivate: options.includePrivate,
        });
        for (const m of res.modules) {
          rawByRealPath.set(await realPathOf(m.filename), m);
        }
        await recordDiags(res.diagnostics);
      }

      // Fallback per-file for any file missing from batch (e.g. if another file failed load)
      for (const f of context.files) {
        const rp = await realPathOf(f.filename);
        if (rawByRealPath.has(rp)) continue;
        const res = await invokeDocProject(compiler, f.filename, {
          stdRoot: context.stdRoot,
          prelude: rp === preludeReal ? null : context.prelude,
          imports: context.imports,
          includePrivate: options.includePrivate,
        });
        for (const m of res.modules) {
          rawByRealPath.set(await realPathOf(m.filename), m);
        }
        await recordDiags(res.diagnostics);
      }
    }

    // Build enriched DocModules with comments, formatted signatures, and code blocks
    const modules: DocModule[] = [];
    const blockCounter = { next: 1 };

    for (const f of context.files) {
      const rp = await realPathOf(f.filename);
      const raw = rawByRealPath.get(rp);
      const sourceBytes = await Deno.readFile(f.filename);
      const sourceText = new TextDecoder().decode(sourceBytes);
      const lines = sourceText.replace(/\r\n?/g, "\n").split("\n");
      const lineStarts = buildLineStarts(sourceBytes);
      const modHeader = extractModuleDoc(lines);
      const minDeclLine = modHeader.consumedEndLine;
      const modCodeBlocks = extractCodeBlocks(
        modHeader.doc,
        f.id,
        f.importPath,
        null,
        blockCounter,
      );

      if (!raw) {
        modules.push({
          id: f.id,
          importPath: f.importPath,
          filename: f.filename,
          isStd: f.importPath.startsWith("std/"),
          isPrelude: rp === preludeReal,
          doc: modHeader.doc,
          codeBlocks: modCodeBlocks,
          types: [],
          traits: [],
          effects: [],
          values: [],
          implementations: [],
          diagnostics: diagsByRealPath.get(rp) ?? [],
        });
        continue;
      }

      // Build values first so associated members can attach cleanly to their owning type
      const associatedByType = new Map<string, DocValue[]>();
      const topValues: DocValue[] = [];
      for (const v of raw.values) {
        const vline = byteOffsetToLine(lineStarts, v.start);
        const doc = extractDeclDoc(lines, vline, minDeclLine);
        const formatted = formatValueSignature(v);
        const anchor = makeAnchor(v.kind === "const" ? "const" : "fn", v.name);
        const docVal: DocValue = {
          name: v.name,
          private: v.private,
          kind: v.kind,
          modifier: v.modifier,
          type: formatted.type,
          signature: formatted.signature,
          ownMask: v.own_mask,
          ownCount: v.own_count,
          where: formatted.where,
          associatedType: v.associated_type,
          associatedMember: v.associated_member,
          doc,
          codeBlocks: extractCodeBlocks(
            doc,
            f.id,
            f.importPath,
            v.name,
            blockCounter,
          ),
          start: v.start,
          end: v.end,
          anchor,
        };
        if (v.associated_type) {
          const list = associatedByType.get(v.associated_type) ?? [];
          list.push(docVal);
          associatedByType.set(v.associated_type, list);
        } else {
          topValues.push(docVal);
        }
      }

      const types: DocType[] = raw.types.map((t) => {
        const tline = byteOffsetToLine(lineStarts, t.start);
        const doc = extractDeclDoc(lines, tline, minDeclLine);
        const typeRenamer = new TypeVarRenamer(t.params);
        const constructors: DocConstructor[] = t.constructors.map((c) => {
          const cline = c.start > 0
            ? byteOffsetToLine(lineStarts, c.start)
            : -1;
          const cdoc = cline > tline
            ? extractDeclDoc(lines, cline, tline + 1)
            : "";
          const fields: DocField[] = c.fields.map((fld) => {
            const fline = fld.start > 0
              ? byteOffsetToLine(lineStarts, fld.start)
              : -1;
            const fdoc = fline > tline
              ? extractDeclDoc(lines, fline, tline + 1)
              : "";
            return {
              name: fld.name,
              type: formatBlotType(fld.type, 0, 0, typeRenamer),
              hasDefault: fld.has_default,
              doc: fdoc,
              start: fld.start,
              end: fld.end,
            };
          });
          return {
            name: c.name,
            declaredRecord: c.declared_record,
            payload: c.payload
              ? formatBlotType(c.payload, 0, 0, typeRenamer)
              : null,
            fields,
            doc: cdoc,
            start: c.start,
            end: c.end,
          };
        });
        const methods = associatedByType.get(t.name) ?? [];
        associatedByType.delete(t.name);
        return {
          name: t.name,
          kind: t.kind,
          private: t.private,
          opaque: t.opaque,
          params: t.params,
          alias: t.alias ? formatBlotType(t.alias, 0, 0, typeRenamer) : null,
          constructors,
          methods,
          doc,
          codeBlocks: extractCodeBlocks(
            doc,
            f.id,
            f.importPath,
            t.name,
            blockCounter,
          ),
          start: t.start,
          end: t.end,
          anchor: makeAnchor("type", t.name),
        };
      });

      // Any associated methods for imported/builtin types (e.g. `F32.lerp`, `U32.to_hex`) remain in topValues
      for (const orphanMethods of associatedByType.values()) {
        topValues.push(...orphanMethods);
      }
      topValues.sort((a, b) => a.start - b.start);

      const traits: DocTrait[] = raw.traits.map((tr) => {
        const line = byteOffsetToLine(lineStarts, tr.start);
        const doc = extractDeclDoc(lines, line, minDeclLine);
        const traitRenamer = new TypeVarRenamer(tr.params);
        return {
          name: tr.name,
          private: tr.private,
          params: tr.params,
          where: tr.where.map((w) => traitRenamer.rename(w)),
          members: tr.members.map((m) => ({
            name: m.name,
            kind: m.kind,
            type: m.type ? formatBlotType(m.type, 0, 0, traitRenamer) : null,
          })),
          doc,
          codeBlocks: extractCodeBlocks(
            doc,
            f.id,
            f.importPath,
            tr.name,
            blockCounter,
          ),
          start: tr.start,
          end: tr.end,
          anchor: makeAnchor("trait", tr.name),
        };
      });

      const effects: DocEffect[] = raw.effects.map((eff) => {
        const line = byteOffsetToLine(lineStarts, eff.start);
        const doc = extractDeclDoc(lines, line, minDeclLine);
        const effRenamer = new TypeVarRenamer(eff.params);
        return {
          name: eff.name,
          private: eff.private,
          callable: eff.callable,
          params: eff.params,
          operations: eff.operations.map((op) => ({
            name: op.name,
            parameter: formatBlotType(op.parameter, 0, 0, effRenamer),
            result: formatBlotType(op.result, 0, 0, effRenamer),
          })),
          doc,
          codeBlocks: extractCodeBlocks(
            doc,
            f.id,
            f.importPath,
            eff.name,
            blockCounter,
          ),
          start: eff.start,
          end: eff.end,
          anchor: makeAnchor("effect", eff.name),
        };
      });

      const implementations: DocImplementation[] = raw.implementations.map(
        (imp) => {
          const line = imp.start > 0
            ? byteOffsetToLine(lineStarts, imp.start)
            : 0;
          const doc = imp.start > 0
            ? extractDeclDoc(lines, line, minDeclLine)
            : "";
          const impRenamer = new TypeVarRenamer();
          return {
            name: imp.name,
            private: imp.private,
            contract: imp.contract,
            head: imp.head.map((h) => formatBlotType(h, 0, 0, impRenamer)),
            where: imp.where.map((w) => impRenamer.rename(w)),
            doc,
            start: imp.start,
            end: imp.end,
          };
        },
      );

      modules.push({
        id: f.id,
        importPath: f.importPath,
        filename: f.filename,
        isStd: raw.is_std,
        isPrelude: raw.is_prelude,
        doc: modHeader.doc,
        codeBlocks: modCodeBlocks,
        types,
        traits,
        effects,
        values: topValues,
        implementations,
        diagnostics: diagsByRealPath.get(rp) ?? [],
      });
    }

    const pkg: DocPackage = {
      schemaVersion: 1,
      name: context.name,
      root: context.root,
      modules,
      brokenLinks: [],
    };
    const resolveLink = buildSymbolResolver(pkg);

    // Check all intra-doc links across every doc comment
    const checkDoc = (
      modId: string,
      itemName: string | null,
      markdown: string,
    ) => {
      for (const target of extractIntraDocLinkTargets(markdown)) {
        if (!resolveLink(target, modId)) {
          pkg.brokenLinks.push({ moduleId: modId, itemName, target });
        }
      }
    };
    for (const mod of pkg.modules) {
      checkDoc(mod.id, null, mod.doc);
      for (const ty of mod.types) {
        checkDoc(mod.id, ty.name, ty.doc);
        for (const c of ty.constructors) {
          checkDoc(mod.id, `${ty.name}.$${c.name}`, c.doc);
          for (const fld of c.fields) {
            checkDoc(mod.id, `${ty.name}.${fld.name}`, fld.doc);
          }
        }
        for (const m of ty.methods) checkDoc(mod.id, m.name, m.doc);
      }
      for (const tr of mod.traits) checkDoc(mod.id, tr.name, tr.doc);
      for (const eff of mod.effects) checkDoc(mod.id, eff.name, eff.doc);
      for (const val of mod.values) checkDoc(mod.id, val.name, val.doc);
    }

    return { pkg, context, resolveLink };
  } finally {
    await library?.dispose();
  }
}

// ── Doctest & browser Wasm example compilation ──────────────────────────────

function collectAllCodeBlocks(pkg: DocPackage): Array<{
  block: DocCodeBlock;
  mod: DocModule;
}> {
  const out: Array<{ block: DocCodeBlock; mod: DocModule }> = [];
  for (const mod of pkg.modules) {
    for (const block of mod.codeBlocks) out.push({ block, mod });
    for (const ty of mod.types) {
      for (const block of ty.codeBlocks) out.push({ block, mod });
      for (const m of ty.methods) {
        for (const block of m.codeBlocks) out.push({ block, mod });
      }
    }
    for (const tr of mod.traits) {
      for (const block of tr.codeBlocks) out.push({ block, mod });
    }
    for (const eff of mod.effects) {
      for (const block of eff.codeBlocks) out.push({ block, mod });
    }
    for (const val of mod.values) {
      for (const block of val.codeBlocks) out.push({ block, mod });
    }
  }
  return out;
}

function modulePublicImportableNames(mod: DocModule): string[] {
  const names = new Set<string>();
  for (const ty of mod.types) {
    if (!ty.private) names.add(ty.name);
  }
  for (const tr of mod.traits) {
    if (!tr.private) names.add(tr.name);
  }
  for (const eff of mod.effects) {
    if (!eff.private) names.add(eff.name);
  }
  for (const val of mod.values) {
    if (!val.private && !val.name.includes(".")) names.add(val.name);
  }
  return [...names];
}

function buildExampleSource(
  block: DocCodeBlock,
  mod: DocModule,
  modImportSpecifier: string,
  options: { forceUnitReturn?: boolean; forCheckOnly?: boolean } = {},
): { source: string; isTestSuite: boolean; isTextHint: boolean } {
  const rawLines = block.code.replace(/\r\n?/g, "\n").split("\n");
  const importLines: string[] = [];
  const bodyLines: string[] = [];
  for (const line of rawLines) {
    // Strip trailing `// => ...` expectation comments from executable source
    const cleaned = line.replace(/\s*\/\/\s*=>.*$/, "");
    if (bodyLines.length === 0 && /^\s*import\s+/.test(cleaned)) {
      importLines.push(cleaned);
    } else {
      bodyLines.push(cleaned);
    }
  }
  while (bodyLines.length > 0 && !bodyLines[0].trim()) bodyLines.shift();
  while (bodyLines.length > 0 && !bodyLines[bodyLines.length - 1].trim()) {
    bodyLines.pop();
  }

  const joined = rawLines.join("\n");
  const isTestSuite = /^\s*test(?:\s+expect_trap)?\s+"/m.test(joined);
  const hasEntry = /^\s*(?:private\s+)?io\s+/m.test(joined);
  const isTextHint = (block.expected !== null &&
    block.expected.startsWith('"') && block.expected.endsWith('"')) ||
    /:\s*Text\s*=>/.test(joined) ||
    /"[^"]*"\s*$/.test(bodyLines[bodyLines.length - 1]?.trim() ?? "");

  // Auto-import the documented module if not already imported and not prelude
  const autoImports: string[] = [];
  if (!mod.isPrelude) {
    const alreadyImportsMod = importLines.some((l) =>
      l.includes(`"${mod.importPath}"`) || l.includes(`"${modImportSpecifier}"`)
    );
    if (!alreadyImportsMod) {
      const modAlias = basename(mod.importPath).replace(/[^A-Za-z0-9_]/g, "_");
      const aliasUsed = new RegExp(`\\b${modAlias}\\.`).test(joined);
      if (aliasUsed) {
        autoImports.push(
          `import * as ${modAlias} from "${modImportSpecifier}"`,
        );
      }
      const locallyDeclared = new Set<string>();
      for (
        const m of joined.matchAll(
          /^\s*(?:let|const|func|type)\s+([A-Za-z_][A-Za-z0-9_]*)/gm,
        )
      ) {
        locallyDeclared.add(m[1]);
      }
      const referenced = modulePublicImportableNames(mod).filter((name) =>
        !locallyDeclared.has(name) &&
        new RegExp(`\\b${name}\\b`).test(joined)
      );
      if (referenced.length > 0) {
        autoImports.push(
          `import { ${referenced.join(", ")} } from "${modImportSpecifier}"`,
        );
      }
    }
  }

  const header = [...autoImports, ...importLines].join("\n");
  const prefix = header ? `${header}\n\n` : "";

  if (isTestSuite || hasEntry) {
    return {
      source: `${prefix}${bodyLines.join("\n")}\n`,
      isTestSuite,
      isTextHint,
    };
  }

  // Wrap bare expression / statements
  const declPrefix = options.forCheckOnly ? "func" : "io";
  const nonEmptyBody = bodyLines.filter((l) =>
    l.trim() && !l.trim().startsWith("//")
  );
  if (nonEmptyBody.length === 0) {
    return {
      source: `${prefix}${declPrefix} _doc_example () : Unit => ()\n`,
      isTestSuite: false,
      isTextHint: false,
    };
  }

  // Separate top-level helper declarations (type/func/const) from executable statements
  const topDecls: string[] = [];
  const execLines: string[] = [];
  let idx = 0;
  while (idx < bodyLines.length) {
    const line = bodyLines[idx];
    if (/^(?:type|func|const|impl|effect)\s+/.test(line)) {
      topDecls.push(line);
      idx++;
      while (
        idx < bodyLines.length &&
        (/^\s+/.test(bodyLines[idx]) || !bodyLines[idx].trim())
      ) {
        topDecls.push(bodyLines[idx]);
        idx++;
      }
    } else {
      execLines.push(...bodyLines.slice(idx));
      break;
    }
  }

  const declSection = topDecls.length ? `${topDecls.join("\n")}\n\n` : "";
  if (execLines.length === 0) {
    return {
      source:
        `${prefix}${declSection}${declPrefix} _doc_example () : Unit => ()\n`,
      isTestSuite: false,
      isTextHint: false,
    };
  }

  const lastIdx = execLines.length - 1;
  const lastTrim = execLines[lastIdx].trim();
  const isStmt =
    /^(?:let|for|if|handler|use|return|@panic|break|continue)\b/.test(
      lastTrim,
    ) || /:=/.test(lastTrim);

  if (execLines.length === 1 && !isStmt && !options.forceUnitReturn) {
    return {
      source:
        `${prefix}${declSection}${declPrefix} _doc_example () => ${lastTrim}\n`,
      isTestSuite: false,
      isTextHint,
    };
  }

  const indented = execLines.map((l) => (l.trim() ? `  ${l}` : ""));
  if (options.forceUnitReturn) {
    if (!isStmt) {
      indented[lastIdx] = `  let _doc_ignored = ${lastTrim}`;
    }
    indented.push("  return ()");
  } else if (!isStmt) {
    indented[lastIdx] = `  return ${lastTrim}`;
  } else if (!lastTrim.startsWith("return ")) {
    indented.push("  return ()");
  }

  return {
    source: `${prefix}${declSection}${declPrefix} _doc_example () =>\n${
      indented.join("\n")
    }\n`,
    isTestSuite: false,
    isTextHint,
  };
}

function bytesToBase64(bytes: Uint8Array): string {
  let bin = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

function formatF32Display(v: number): string {
  if (!Number.isFinite(v)) return String(v);
  const s = String(Math.fround(v));
  return !s.includes(".") && !s.includes("e") ? `${s}.0` : s;
}

function compareExpected(
  actualFormatted: string,
  actualRaw: unknown,
  resultType: ValueType,
  expected: string,
): boolean {
  const exp = expected.trim();
  if (actualFormatted === exp) return true;
  if (resultType === "F32" && typeof actualRaw === "number") {
    const expNum = Number(exp);
    if (Number.isFinite(expNum)) {
      return Math.abs(actualRaw - expNum) <=
        1e-4 * Math.max(1, Math.abs(expNum));
    }
  }
  if (resultType === "U32" && typeof actualRaw === "number") {
    const clean = exp.replaceAll("_", "");
    const expNum = Number(clean);
    if (Number.isInteger(expNum) && expNum === actualRaw) return true;
  }
  return false;
}

async function compileDocCodeBlock(
  compiler: string | URL,
  block: DocCodeBlock,
  mod: DocModule,
  context: DocProjectContext,
): Promise<{
  ok: boolean;
  wasm?: Uint8Array<ArrayBuffer>;
  isTestSuite: boolean;
  isTextHint: boolean;
  diagnostics: RawDiagnosticRecord[];
}> {
  const tmpDir = await Deno.makeTempDir({ prefix: "blot-doctest-" });
  try {
    const snippetPath = join(tmpDir, "example.blot");
    const wasmPath = join(tmpDir, "example.wasm");
    const modDir = dirname(mod.filename);
    const modStem = stripBlotExt(basename(mod.filename));
    const aliasImports: Record<string, string> = {
      ...context.imports,
      "__doc_mod__/": modDir,
    };
    const modSpec = mod.importPath.startsWith("std/")
      ? mod.importPath
      : `__doc_mod__/${modStem}`;

    const attempt = async (forceUnitReturn: boolean) => {
      const built = buildExampleSource(block, mod, modSpec, {
        forceUnitReturn,
        forCheckOnly: block.mode === "check" || block.mode === "no_run",
      });
      await Deno.writeTextFile(snippetPath, built.source);
      const isCheck = block.mode === "check" || block.mode === "no_run";
      const args = isCheck
        ? ["check-project", snippetPath]
        : ["build-project", snippetPath, wasmPath];
      if (!isCheck && built.isTestSuite) args.push("--test");
      args.push("--std-root", context.stdRoot);
      args.push("--prelude", context.prelude ?? "none");
      for (const [prefix, dir] of Object.entries(aliasImports)) {
        args.push("--alias", `${prefix}=${dir}`);
      }
      const res = await new Deno.Command(compiler, {
        args,
        stdout: "piped",
        stderr: "piped",
      }).output();
      const stdout = new TextDecoder().decode(res.stdout);
      const diagnostics: RawDiagnosticRecord[] = [];
      for (const line of stdout.split("\n")) {
        if (!line.trim()) continue;
        try {
          const rec = JSON.parse(line) as { kind?: string };
          if (rec.kind === "diagnostic") {
            diagnostics.push(rec as unknown as RawDiagnosticRecord);
          }
        } catch {
          // ignore
        }
      }
      if (!res.success) {
        return {
          ok: false,
          isTestSuite: built.isTestSuite,
          isTextHint: built.isTextHint,
          diagnostics,
        };
      }
      if (isCheck) {
        return {
          ok: true,
          isTestSuite: built.isTestSuite,
          isTextHint: built.isTextHint,
          diagnostics: [],
        };
      }
      const bytes = new Uint8Array(await Deno.readFile(wasmPath));
      return {
        ok: true,
        wasm: bytes,
        isTestSuite: built.isTestSuite,
        isTextHint: built.isTextHint,
        diagnostics: [],
      };
    };

    const first = await attempt(false);
    if (
      !first.ok && block.mode === "run" && block.expected === null &&
      first.diagnostics.some((d) => d.code === "entry_type")
    ) {
      return await attempt(true);
    }
    return first;
  } finally {
    await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
  }
}

/** Compile and run all doc examples (`blot doc --test`). */
export async function runDocTests(
  pkg: DocPackage,
  context: DocProjectContext,
  executable?: string | URL,
): Promise<DocTestReport> {
  let library: Awaited<ReturnType<typeof extractStandardLibrary>> | undefined;
  try {
    let activeContext = context;
    if (Deno.build.standalone && !(await pathExists(context.stdRoot))) {
      library = await extractStandardLibrary();
      activeContext = {
        ...context,
        stdRoot: library.path,
        prelude: context.prelude === null
          ? null
          : join(library.path, "prelude.blot"),
      };
    }
    const compiler = await resolveCompilerExecutable(executable);
    const all = collectAllCodeBlocks(pkg);
    const results: DocTestResult[] = [];
    let passed = 0;
    let failed = 0;
    let skipped = 0;

    for (const { block, mod } of all) {
      const t0 = performance.now();
      if (block.mode === "ignore" || block.mode === "other") {
        skipped++;
        results.push({
          id: block.id,
          moduleImportPath: mod.importPath,
          itemName: block.itemName,
          mode: block.mode,
          passed: true,
          skipped: true,
          durationMs: 0,
        });
        continue;
      }

      const compiled = await compileDocCodeBlock(
        compiler,
        block,
        mod,
        activeContext,
      );
      if (!compiled.ok) {
        failed++;
        const msg = compiled.diagnostics.length
          ? compiled.diagnostics.map((d) => `${d.code}: ${d.message}`).join(
            "; ",
          )
          : "Compilation failed";
        results.push({
          id: block.id,
          moduleImportPath: mod.importPath,
          itemName: block.itemName,
          mode: block.mode,
          passed: false,
          skipped: false,
          error: msg,
          durationMs: performance.now() - t0,
        });
        continue;
      }

      if (block.mode === "check" || block.mode === "no_run" || !compiled.wasm) {
        passed++;
        results.push({
          id: block.id,
          moduleImportPath: mod.importPath,
          itemName: block.itemName,
          mode: block.mode,
          passed: true,
          skipped: false,
          output: "checked",
          durationMs: performance.now() - t0,
        });
        continue;
      }

      // Execute compiled Wasm example
      try {
        const wasmMod = new WebAssembly.Module(compiled.wasm);
        const testsMeta = compiled.isTestSuite
          ? readTestMetadata(wasmMod)
          : undefined;
        const guest = await instantiateGuest(wasmMod);
        try {
          if (testsMeta && testsMeta.length > 0) {
            let subFailed = 0;
            const errs: string[] = [];
            for (const t of testsMeta) {
              try {
                guest.call(t.exportName, null);
                if (t.kind === "trap") {
                  subFailed++;
                  errs.push(`${t.displayName}: expected trap`);
                }
              } catch (err) {
                if (t.kind !== "trap") {
                  subFailed++;
                  const trap = guestTrapOf(err);
                  errs.push(
                    `${t.displayName}: ${
                      trap
                        ? trap.formatted
                        : (err instanceof Error ? err.message : String(err))
                    }`,
                  );
                }
              }
            }
            if (subFailed > 0) {
              failed++;
              results.push({
                id: block.id,
                moduleImportPath: mod.importPath,
                itemName: block.itemName,
                mode: block.mode,
                passed: false,
                skipped: false,
                error: errs.join("; "),
                durationMs: performance.now() - t0,
              });
            } else {
              passed++;
              results.push({
                id: block.id,
                moduleImportPath: mod.importPath,
                itemName: block.itemName,
                mode: block.mode,
                passed: true,
                skipped: false,
                output: `${testsMeta.length} passed`,
                durationMs: performance.now() - t0,
              });
            }
            continue;
          }

          const abi = readGuestAbi(wasmMod);
          const fn = abi.functions.find((f) => f.name === "_doc_example") ??
            abi.functions.find((f) => f.parameter === "Unit");
          if (!fn || typeof fn.result !== "string") {
            passed++;
            results.push({
              id: block.id,
              moduleImportPath: mod.importPath,
              itemName: block.itemName,
              mode: block.mode,
              passed: true,
              skipped: false,
              output: "compiled",
              durationMs: performance.now() - t0,
            });
            continue;
          }
          const rawVal = guest.call(fn.name, null);
          let formatted = "()";
          if (fn.result === "U32") formatted = String(rawVal);
          else if (fn.result === "Bool") formatted = rawVal ? "true" : "false";
          else if (fn.result === "F32") {
            formatted = formatF32Display(rawVal as number);
          } else if (fn.result === "Array U32") {
            const words = rawVal as Uint32Array;
            if (
              words.length >= 4 && words[0] === TEST_REPORT_MAGIC &&
              words[1] === TEST_REPORT_VERSION
            ) {
              const report = decodeTestReport(words);
              if (report.failed > 0) {
                failed++;
                results.push({
                  id: block.id,
                  moduleImportPath: mod.importPath,
                  itemName: block.itemName,
                  mode: block.mode,
                  passed: false,
                  skipped: false,
                  error: report.failures.map((f) => `${f.label}: ${f.message}`)
                    .join("; "),
                  durationMs: performance.now() - t0,
                });
                continue;
              }
              formatted = `${report.passed} passed`;
            } else if (compiled.isTextHint) {
              formatted = JSON.stringify(decodeText(words));
            } else {
              formatted = `#[${Array.from(words).join(", ")}]`;
            }
          } else if (fn.result === "Array F32") {
            const floats = rawVal as Float32Array;
            formatted = `#[${
              Array.from(floats).map(formatF32Display).join(", ")
            }]`;
          }

          if (
            block.expected !== null &&
            !compareExpected(formatted, rawVal, fn.result, block.expected)
          ) {
            failed++;
            results.push({
              id: block.id,
              moduleImportPath: mod.importPath,
              itemName: block.itemName,
              mode: block.mode,
              passed: false,
              skipped: false,
              output: formatted,
              error: `Expected ${block.expected}, got ${formatted}`,
              durationMs: performance.now() - t0,
            });
          } else {
            passed++;
            results.push({
              id: block.id,
              moduleImportPath: mod.importPath,
              itemName: block.itemName,
              mode: block.mode,
              passed: true,
              skipped: false,
              output: formatted,
              durationMs: performance.now() - t0,
            });
          }
        } finally {
          guest.dispose();
        }
      } catch (err) {
        failed++;
        const trap = guestTrapOf(err);
        results.push({
          id: block.id,
          moduleImportPath: mod.importPath,
          itemName: block.itemName,
          mode: block.mode,
          passed: false,
          skipped: false,
          error: trap
            ? trap.formatted
            : (err instanceof Error ? err.message : String(err)),
          durationMs: performance.now() - t0,
        });
      }
    }

    return { passed, failed, skipped, results };
  } finally {
    await library?.dispose();
  }
}

/** Precompile all runnable Blot doc examples to base64 ABI 8 Wasm for static HTML docs. */
export async function precompileDocExamples(
  pkg: DocPackage,
  context: DocProjectContext,
  executable?: string | URL,
): Promise<Map<string, PrecompiledDocExample>> {
  let library: Awaited<ReturnType<typeof extractStandardLibrary>> | undefined;
  try {
    let activeContext = context;
    if (Deno.build.standalone && !(await pathExists(context.stdRoot))) {
      library = await extractStandardLibrary();
      activeContext = {
        ...context,
        stdRoot: library.path,
        prelude: context.prelude === null
          ? null
          : join(library.path, "prelude.blot"),
      };
    }
    const compiler = await resolveCompilerExecutable(executable);
    const all = collectAllCodeBlocks(pkg);
    const map = new Map<string, PrecompiledDocExample>();
    for (const { block, mod } of all) {
      if (block.mode !== "run") continue;
      const compiled = await compileDocCodeBlock(
        compiler,
        block,
        mod,
        activeContext,
      );
      if (!compiled.ok || !compiled.wasm) {
        map.set(block.id, {
          id: block.id,
          wasmBase64: "",
          entry: null,
          resultType: null,
          isText: false,
          expected: block.expected,
          isTestSuite: false,
          error: compiled.diagnostics.map((d) =>
            `${d.code}: ${d.message}`
          ).join(
            "; ",
          ) || "Compilation failed",
        });
        continue;
      }
      const wasmMod = new WebAssembly.Module(compiled.wasm);
      const testsMeta = compiled.isTestSuite
        ? readTestMetadata(wasmMod)
        : undefined;
      const abi = readGuestAbi(wasmMod);
      const fn = abi.functions.find((f) => f.name === "_doc_example") ??
        abi.functions.find((f) => f.parameter === "Unit");
      if (!testsMeta?.length && (!fn || typeof fn.result !== "string")) {
        continue;
      }
      map.set(block.id, {
        id: block.id,
        wasmBase64: bytesToBase64(compiled.wasm),
        entry: fn?.name ?? null,
        resultType: typeof fn?.result === "string" ? fn.result : null,
        isText: compiled.isTextHint,
        expected: block.expected,
        isTestSuite: Boolean(testsMeta?.length),
        tests: testsMeta?.map((t) => ({
          exportName: t.exportName,
          displayName: t.displayName,
          kind: t.kind,
        })),
      });
    }
    return map;
  } finally {
    await library?.dispose();
  }
}

// ── Markdown, compact API & terminal renderers ──────────────────────────────

function renderModuleMarkdown(
  mod: DocModule,
  resolveLink: SymbolResolver,
  depthPrefix: string,
): string {
  const lines: string[] = [];
  lines.push(`# ${mod.importPath}`);
  lines.push("");
  if (mod.doc) {
    lines.push(rewriteMarkdownLinks(mod.doc, mod.id, resolveLink, depthPrefix));
    lines.push("");
  }

  if (mod.types.length > 0) {
    lines.push("## Types");
    lines.push("");
    for (const ty of mod.types) {
      const params = ty.params.length ? ` ${ty.params.join(" ")}` : "";
      let header = `type ${ty.name}${params}`;
      if (ty.kind === "opaque") header += " is opaque";
      else if (ty.kind === "alias" && ty.alias) header += ` = ${ty.alias}`;
      else header += " is data";
      lines.push(`### \`${ty.name}\` <a id="${ty.anchor}"></a>`);
      lines.push("");
      lines.push("```blot");
      lines.push(header);
      lines.push("```");
      lines.push("");
      if (ty.doc) {
        lines.push(
          rewriteMarkdownLinks(ty.doc, mod.id, resolveLink, depthPrefix),
        );
        lines.push("");
      }
      if (ty.opaque) {
        lines.push("_Opaque type: constructors and fields are private._");
        lines.push("");
      } else if (ty.constructors.length > 0) {
        for (const c of ty.constructors) {
          if (c.fields.length > 0) {
            lines.push(`- \`$${c.name}\``);
            for (const fld of c.fields) {
              const def = fld.hasDefault ? " _(default)_" : "";
              const fdoc = fld.doc
                ? ` — ${
                  rewriteMarkdownLinks(
                    fld.doc,
                    mod.id,
                    resolveLink,
                    depthPrefix,
                  )
                }`
                : "";
              lines.push(`  - \`${fld.name}: ${fld.type}\`${def}${fdoc}`);
            }
          } else {
            const pay = c.payload ? ` ${c.payload}` : "";
            const cdoc = c.doc ? ` — ${c.doc}` : "";
            lines.push(`- \`$${c.name}${pay}\`${cdoc}`);
          }
        }
        lines.push("");
      }
      for (const m of ty.methods) {
        lines.push(`#### \`${m.name}\` <a id="${m.anchor}"></a>`);
        lines.push("");
        lines.push("```blot");
        lines.push(m.signature);
        lines.push("```");
        lines.push("");
        if (m.doc) {
          lines.push(
            rewriteMarkdownLinks(m.doc, mod.id, resolveLink, depthPrefix),
          );
          lines.push("");
        }
      }
    }
  }

  if (mod.traits.length > 0) {
    lines.push("## Traits");
    lines.push("");
    for (const tr of mod.traits) {
      const params = tr.params.length ? ` ${tr.params.join(" ")}` : "";
      const wh = tr.where.length ? ` where { ${tr.where.join(", ")} }` : "";
      lines.push(`### \`${tr.name}\` <a id="${tr.anchor}"></a>`);
      lines.push("");
      lines.push("```blot");
      lines.push(`type ${tr.name}${params} is trait${wh}`);
      lines.push("```");
      lines.push("");
      if (tr.doc) {
        lines.push(
          rewriteMarkdownLinks(tr.doc, mod.id, resolveLink, depthPrefix),
        );
        lines.push("");
      }
      for (const m of tr.members) {
        lines.push(`- \`${m.name}${m.type ? `: ${m.type}` : ""}\` (${m.kind})`);
      }
      if (tr.members.length) lines.push("");
    }
  }

  if (mod.effects.length > 0) {
    lines.push("## Effects");
    lines.push("");
    for (const eff of mod.effects) {
      const params = eff.params.length ? ` ${eff.params.join(" ")}` : "";
      lines.push(`### \`${eff.name}\` <a id="${eff.anchor}"></a>`);
      lines.push("");
      lines.push("```blot");
      if (eff.callable && eff.operations.length === 1) {
        lines.push(
          `effect ${eff.name}${params}: ${eff.operations[0].parameter} -> ${
            eff.operations[0].result
          }`,
        );
      } else {
        lines.push(`type ${eff.name}${params} is effect`);
      }
      lines.push("```");
      lines.push("");
      if (eff.doc) {
        lines.push(
          rewriteMarkdownLinks(eff.doc, mod.id, resolveLink, depthPrefix),
        );
        lines.push("");
      }
      if (!eff.callable && eff.operations.length > 0) {
        for (const op of eff.operations) {
          lines.push(`- \`${op.name}: ${op.parameter} -> ${op.result}\``);
        }
        lines.push("");
      }
    }
  }

  if (mod.values.length > 0) {
    lines.push("## Functions & Values");
    lines.push("");
    for (const val of mod.values) {
      lines.push(`### \`${val.name}\` <a id="${val.anchor}"></a>`);
      lines.push("");
      lines.push("```blot");
      lines.push(val.signature);
      lines.push("```");
      lines.push("");
      if (val.doc) {
        lines.push(
          rewriteMarkdownLinks(val.doc, mod.id, resolveLink, depthPrefix),
        );
        lines.push("");
      }
    }
  }

  if (mod.implementations.length > 0) {
    lines.push("## Implementations");
    lines.push("");
    for (const imp of mod.implementations) {
      const head = imp.head.join(" ");
      const wh = imp.where.length ? ` where { ${imp.where.join(", ")} }` : "";
      lines.push(`- \`impl ${imp.contract}${head ? ` ${head}` : ""}${wh}\``);
    }
    lines.push("");
  }

  return lines.join("\n").trimEnd() + "\n";
}

/** Compact one-line-per-symbol API summary ideal for LLMs / agents and quick CLI lookup. */
export function renderCompactApi(pkg: DocPackage): string {
  const lines: string[] = [`# ${pkg.name} API`, ""];
  for (const mod of pkg.modules) {
    lines.push(`## ${mod.importPath}`);
    if (mod.doc) {
      const firstLine = mod.doc.split("\n").find((l) => l.trim());
      if (firstLine) lines.push(`// ${firstLine.trim()}`);
    }
    for (const ty of mod.types) {
      const params = ty.params.length ? ` ${ty.params.join(" ")}` : "";
      if (ty.kind === "opaque") {
        lines.push(`type ${ty.name}${params} is opaque`);
      } else if (ty.kind === "alias" && ty.alias) {
        lines.push(`type ${ty.name}${params} = ${ty.alias}`);
      } else {
        const ctors = ty.constructors.map((c) => {
          if (c.fields.length) {
            return `$${c.name} { ${
              c.fields.map((f) => `${f.name}: ${f.type}`).join(", ")
            } }`;
          }
          return c.payload ? `$${c.name} ${c.payload}` : `$${c.name}`;
        }).join(" | ");
        lines.push(
          `type ${ty.name}${params} is data${ctors ? ` = ${ctors}` : ""}`,
        );
      }
      for (const m of ty.methods) {
        lines.push(`  ${m.signature}`);
      }
    }
    for (const tr of mod.traits) {
      const params = tr.params.length ? ` ${tr.params.join(" ")}` : "";
      lines.push(`type ${tr.name}${params} is trait`);
    }
    for (const eff of mod.effects) {
      const params = eff.params.length ? ` ${eff.params.join(" ")}` : "";
      lines.push(`effect ${eff.name}${params}`);
    }
    for (const val of mod.values) {
      lines.push(val.signature);
    }
    lines.push("");
  }
  return lines.join("\n").trimEnd() + "\n";
}

export async function writeMarkdownDocs(
  pkg: DocPackage,
  resolveLink: SymbolResolver,
  outDir: string,
): Promise<string[]> {
  await Deno.mkdir(outDir, { recursive: true });
  const written: string[] = [];

  const indexLines = [`# ${pkg.name} Documentation`, "", "## Modules", ""];
  for (const mod of pkg.modules) {
    const first = mod.doc.split("\n").find((l) => l.trim())?.trim() ?? "";
    const suffix = first ? ` — ${first}` : "";
    indexLines.push(`- [\`${mod.importPath}\`](modules/${mod.id}.md)${suffix}`);
  }
  indexLines.push("");
  const indexPath = join(outDir, "INDEX.md");
  await Deno.writeTextFile(indexPath, indexLines.join("\n"));
  written.push(indexPath);

  const apiPath = join(outDir, "API.md");
  await Deno.writeTextFile(apiPath, renderCompactApi(pkg));
  written.push(apiPath);

  for (const mod of pkg.modules) {
    const modPath = join(outDir, "modules", `${mod.id}.md`);
    await Deno.mkdir(dirname(modPath), { recursive: true });
    const depth = mod.id.split("/").length;
    const prefix = "../".repeat(depth);
    await Deno.writeTextFile(
      modPath,
      renderModuleMarkdown(mod, resolveLink, prefix),
    );
    written.push(modPath);
  }
  return written;
}

export function searchDocPackage(
  pkg: DocPackage,
  query: string,
): Array<{
  module: string;
  kind: string;
  name: string;
  signature: string;
  doc: string;
}> {
  const q = query.trim().toLowerCase();
  const hits: Array<{
    score: number;
    module: string;
    kind: string;
    name: string;
    signature: string;
    doc: string;
  }> = [];
  const consider = (
    module: string,
    kind: string,
    name: string,
    signature: string,
    doc: string,
  ) => {
    const hay = `${name} ${module} ${signature} ${doc}`.toLowerCase();
    const idx = hay.indexOf(q);
    if (idx === -1) return;
    const lowerName = name.toLowerCase();
    const score = lowerName === q ? 0 : lowerName.startsWith(q) ? 1 : idx + 2;
    hits.push({ score, module, kind, name, signature, doc });
  };
  for (const mod of pkg.modules) {
    for (const ty of mod.types) {
      consider(
        mod.importPath,
        "type",
        ty.name,
        `type ${ty.name} is ${ty.kind}`,
        ty.doc,
      );
      for (const m of ty.methods) {
        consider(mod.importPath, m.kind, m.name, m.signature, m.doc);
      }
    }
    for (const tr of mod.traits) {
      consider(
        mod.importPath,
        "trait",
        tr.name,
        `type ${tr.name} is trait`,
        tr.doc,
      );
    }
    for (const eff of mod.effects) {
      consider(
        mod.importPath,
        "effect",
        eff.name,
        `effect ${eff.name}`,
        eff.doc,
      );
    }
    for (const val of mod.values) {
      consider(mod.importPath, val.kind, val.name, val.signature, val.doc);
    }
  }
  hits.sort((a, b) => a.score - b.score || (a.name < b.name ? -1 : 1));
  return hits.map(({ score: _s, ...rest }) => rest);
}

// ── CLI entry point (`blot doc`) ────────────────────────────────────────────

const docUsage = `Usage: blot doc [TARGET] [options]
Targets: std | std/<module> | <alias>[/<module>] | <dir> | <file.blot>
Options:
  --out DIR            Write static Markdown docs (INDEX.md, API.md, modules/*.md)
  --html               With --out DIR, write a static HTML site with live runnable Wasm examples
  --test               Compile and run Blot code examples in doc comments
  --check-links        Fail if any intra-doc symbol link [\`Symbol\`] is unresolved
  --search QUERY       Search symbols, signatures, and doc comments
  --compact            Print compact one-line-per-symbol API summary
  --json               Print machine-readable JSON documentation
  --include-private    Include private declarations
  --prelude PATH|none  Override prelude path
  --std-root DIR       Override stdlib directory
  --alias PREFIX=DIR   Add a module directory alias`;

export async function runDocCli(
  executable: string | URL | undefined,
  args: string[],
): Promise<number> {
  let target: string | undefined;
  let outDir: string | undefined;
  let html = false;
  let runTests = false;
  let checkLinks = false;
  let searchQuery: string | undefined;
  let compact = false;
  let json = false;
  let includePrivate = false;
  let stdRoot: string | undefined;
  let prelude: string | null | undefined;
  const imports: Record<string, string> = Object.create(null);

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help" || arg === "-h") {
      console.log(docUsage);
      return 0;
    }
    if (arg === "--html") {
      html = true;
      continue;
    }
    if (arg === "--test") {
      runTests = true;
      continue;
    }
    if (arg === "--check-links") {
      checkLinks = true;
      continue;
    }
    if (arg === "--compact") {
      compact = true;
      continue;
    }
    if (arg === "--json") {
      json = true;
      continue;
    }
    if (arg === "--include-private") {
      includePrivate = true;
      continue;
    }
    if (
      ["--out", "--search", "--prelude", "--std-root", "--alias"].includes(arg)
    ) {
      const value = args[++i];
      if (!value || value.startsWith("--")) {
        console.error(`Missing value for ${arg}`);
        return 2;
      }
      if (arg === "--out") outDir = value;
      else if (arg === "--search") searchQuery = value;
      else if (arg === "--std-root") stdRoot = value;
      else if (arg === "--prelude") prelude = value === "none" ? null : value;
      else if (arg === "--alias") {
        const sep = value.indexOf("=");
        const prefix = value.slice(0, sep);
        const dir = value.slice(sep + 1);
        if (sep < 1 || !prefix.endsWith("/") || !dir) {
          console.error("--alias must be PREFIX/=DIR");
          return 2;
        }
        imports[prefix] = dir;
      }
      continue;
    }
    if (arg.startsWith("-")) {
      console.error(`Unexpected argument: ${arg}\n${docUsage}`);
      return 2;
    }
    if (target) {
      console.error(`Unexpected positional argument: ${arg}\n${docUsage}`);
      return 2;
    }
    target = arg;
  }

  if (html && !outDir) {
    console.error("--html requires --out DIR");
    return 2;
  }

  let library: Awaited<ReturnType<typeof extractStandardLibrary>> | undefined;
  try {
    if (Deno.build.standalone && !stdRoot) {
      library = await extractStandardLibrary();
      stdRoot = library.path;
    }
    const { pkg, context, resolveLink } = await generateDocs({
      target,
      executable,
      stdRoot,
      prelude,
      imports: Object.keys(imports).length ? imports : undefined,
      includePrivate,
    });

    let exitCode = 0;

    if (checkLinks && pkg.brokenLinks.length > 0) {
      for (const broken of pkg.brokenLinks) {
        const where = broken.itemName
          ? `${broken.moduleId} (${broken.itemName})`
          : broken.moduleId;
        console.error(`broken doc link in ${where}: [\`${broken.target}\`]`);
      }
      exitCode = 1;
    }

    if (runTests) {
      const report = await runDocTests(pkg, context, executable);
      if (json) {
        console.log(JSON.stringify(report, null, 2));
      } else {
        for (const r of report.results) {
          const label = r.itemName
            ? `${r.moduleImportPath} · ${r.itemName}`
            : r.moduleImportPath;
          if (r.skipped) {
            console.log(`- [skip] ${label}`);
          } else if (r.passed) {
            console.log(
              `✓ ${label}${r.output ? ` (${r.output})` : ""} [${
                r.durationMs.toFixed(0)
              }ms]`,
            );
          } else {
            console.error(`✗ ${label}: ${r.error}`);
          }
        }
        console.log(
          `\nDoctests: ${report.passed} passed, ${report.failed} failed, ${report.skipped} skipped`,
        );
      }
      if (report.failed > 0) exitCode = 1;
      if (!outDir && !searchQuery) return exitCode;
    }

    if (searchQuery !== undefined) {
      const hits = searchDocPackage(pkg, searchQuery);
      if (json) {
        console.log(JSON.stringify(hits, null, 2));
      } else if (hits.length === 0) {
        console.log(`No symbols matching "${searchQuery}".`);
      } else {
        for (const hit of hits) {
          console.log(`${hit.module}  ${hit.signature}`);
          const first = hit.doc.split("\n").find((l) => l.trim());
          if (first) console.log(`  ${first.trim()}`);
        }
      }
      return exitCode;
    }

    if (outDir) {
      if (html) {
        const examples = await precompileDocExamples(pkg, context, executable);
        const { files, exampleCount } = await generateHtmlDocs(
          pkg,
          resolveLink,
          {
            outDir,
            examples,
          },
        );
        if (json) {
          console.log(JSON.stringify({ outDir, files, exampleCount }, null, 2));
        } else {
          console.log(
            `Wrote HTML docs to ${outDir} (${pkg.modules.length} modules, ${exampleCount} runnable Wasm examples, ${files.length} files)`,
          );
        }
      } else {
        const files = await writeMarkdownDocs(pkg, resolveLink, outDir);
        if (json) {
          console.log(JSON.stringify({ outDir, files }, null, 2));
        } else {
          console.log(
            `Wrote Markdown docs to ${outDir} (${pkg.modules.length} modules, ${files.length} files)`,
          );
        }
      }
      return exitCode;
    }

    if (json) {
      console.log(JSON.stringify(pkg, null, 2));
      return exitCode;
    }

    if (compact || pkg.modules.length > 1) {
      console.log(renderCompactApi(pkg));
    } else if (pkg.modules.length === 1) {
      console.log(renderModuleMarkdown(pkg.modules[0], resolveLink, ""));
    }

    // Print any compiler diagnostics on stderr if any module failed checking
    const allDiags = pkg.modules.flatMap((m) => m.diagnostics);
    if (allDiags.length > 0 && !json) {
      console.error(await formatDiagnosticReport(allDiags));
    }

    return exitCode;
  } finally {
    await library?.dispose();
  }
}
