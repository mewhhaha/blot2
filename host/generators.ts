import { basename, dirname, isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  type AssetContext,
  type AssetImport,
  type AssetImports,
  type AssetParser,
  tagAssetParser,
  tagStage0Error,
} from "./assets.ts";
import {
  type GuestTrapInfo,
  guestTrapOf,
  instantiateGuest,
  readGuestAbi,
} from "./guest.ts";
import { findCheckoutCompiler } from "./packaged_native.ts";
import { decodeText, encodeText } from "./text.ts";
import type { ZigProjectDiagnostic } from "./zig_project_client.ts";

export type BlotGeneratorPhase = "compile" | "execute" | "result";

export class BlotGeneratorError extends Error {
  readonly trap?: GuestTrapInfo;
  constructor(
    readonly phase: BlotGeneratorPhase,
    message: string,
    options?: ErrorOptions & { readonly trap?: GuestTrapInfo },
  ) {
    super(message, options);
    this.name = "BlotGeneratorError";
    if (options?.trap !== undefined) this.trap = options.trap;
    tagStage0Error(this, phase);
  }
}

export type BlotGeneratorInputMode = "bytes" | "text";

export interface BlotGeneratorReference {
  /** Nominal Blot type name for the host resource handle. */
  readonly type: string;
  /** Exported Blot constant name. */
  readonly export: string;
  readonly mediaType?: string;
}

type GeneratorCompilerOptions = {
  readonly executable?: string | URL;
  readonly prelude?: string | URL | null;
  readonly stdRoot?: string | URL | null;
  readonly imports?: Readonly<Record<string, string | URL>>;
};

export interface BlotGeneratorOptions extends GeneratorCompilerOptions {
  /** Path to the Stage 0 Blot entry file, relative to the working directory. */
  readonly generator: string | URL;
  /** Name of the generator function marked #entry. Defaults to generate. */
  readonly exportName?: string;
  /** Raw bytes by default, or strict UTF-8 decoded to Unicode scalars. */
  readonly inputMode?: BlotGeneratorInputMode;
  /** Publish the original input bytes as a host resource alongside the source. */
  readonly reference?: BlotGeneratorReference;
}

export interface BlotGeneratorRule {
  /** Virtual module path relative to the project root. */
  readonly module?: string;
  /** Input path relative to the project root. Required with module. */
  readonly input?: string;
  /** Single directory and suffix pattern, such as assets/*.wgsl. */
  readonly match?: string;
  readonly generator: string;
  readonly exportName?: string;
  readonly inputMode?: BlotGeneratorInputMode;
  readonly reference?: BlotGeneratorReference;
}

const std = new URL("../std/", import.meta.url);
const decoder = new TextDecoder("utf-8", { fatal: true });
const pathOf = (path: string | URL) =>
  resolve(path instanceof URL ? fileURLToPath(path) : path);

const valueName = /^[a-z_][A-Za-z0-9_]*$/;
const typeName = /^[A-Z][A-Za-z0-9_]*$/;
const reserved = new Set(
  "const let type data effect is func do use return break for ever continue in case of if then else as import self where and or true false _"
    .split(" "),
);
const builtinTypes = new Set(["Unit", "Bool", "U32", "F32", "Array"]);

function object(
  input: unknown,
  fields: string[],
  label: string,
): Record<string, unknown> {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new TypeError(`${label} must be an object`);
  }
  for (const key of Object.keys(input)) {
    if (!fields.includes(key)) {
      throw new TypeError(`${label}: unknown field ${key}`);
    }
  }
  return input as Record<string, unknown>;
}

function validateSettings(
  input: Record<string, unknown>,
  label: string,
): Pick<BlotGeneratorOptions, "exportName" | "inputMode" | "reference"> {
  const { exportName, inputMode } = input;
  if (
    exportName !== undefined &&
    (typeof exportName !== "string" || !valueName.test(exportName) ||
      reserved.has(exportName))
  ) {
    throw new TypeError(`${label}.exportName must be a Blot function name`);
  }
  if (
    inputMode !== undefined && inputMode !== "bytes" && inputMode !== "text"
  ) {
    throw new TypeError(`${label}.inputMode must be "bytes" or "text"`);
  }
  let reference: BlotGeneratorReference | undefined;
  if (input.reference !== undefined) {
    const ref = object(
      input.reference,
      ["type", "export", "mediaType"],
      `${label}.reference`,
    );
    const { type, export: name, mediaType } = ref;
    if (
      typeof type !== "string" || !typeName.test(type) ||
      builtinTypes.has(type) ||
      typeof name !== "string" || !valueName.test(name) || reserved.has(name)
    ) {
      throw new TypeError(
        `${label}.reference requires Blot type and constant names`,
      );
    }
    if (
      mediaType !== undefined &&
      (typeof mediaType !== "string" || !mediaType || mediaType.length > 256 ||
        /[\r\n\0]/.test(mediaType) || !mediaType.isWellFormed())
    ) {
      throw new TypeError(`${label}.reference.mediaType is invalid`);
    }
    reference = { type, export: name, mediaType };
  }
  return { exportName, inputMode, reference };
}

function inside(root: string, path: string): boolean {
  const rel = relative(root, path);
  return rel !== "" && rel !== ".." && !rel.startsWith("../") &&
    !isAbsolute(rel);
}

function relativePath(root: string, path: unknown, label: string): string {
  const invalid = () =>
    new TypeError(`${label} must be a relative path inside the project`);
  if (
    typeof path !== "string" || !path.trim() || !path.isWellFormed() ||
    /[\\\r\n\0]/.test(path) || /^[A-Za-z]:/.test(path) || isAbsolute(path)
  ) throw invalid();
  let depth = 0;
  for (const component of path.split("/")) {
    if (component === "..") depth--;
    else if (component && component !== ".") depth++;
    if (depth < 0) throw invalid();
  }
  if (!inside(root, resolve(root, path))) throw invalid();
  return path;
}

function plainPath(root: string, path: unknown, label: string): string {
  const result = relativePath(root, path, label);
  if (/[*?\[\]]/.test(result)) {
    throw new TypeError(`${label} must name one path`);
  }
  return result;
}

/** Validate manifest data and capture normalized settings shared with expansion. */
export function readGeneratorRules(
  value: unknown,
  root: string,
  label: string,
): BlotGeneratorRule[] {
  if (!Array.isArray(value) || value.length > 4096) {
    throw new TypeError(
      `${label} must be an array of up to 4096 generator rules`,
    );
  }
  return value.map((entry, index) => {
    const key = `${label}[${index}]`;
    const raw = object(entry, [
      "module",
      "input",
      "match",
      "generator",
      "exportName",
      "inputMode",
      "reference",
    ], key);
    const generator = plainPath(root, raw.generator, `${key}.generator`);
    if (!generator.endsWith(".blot")) {
      throw new TypeError(`${key}.generator must end in .blot`);
    }
    const settings = validateSettings(raw, key);
    if (raw.match === undefined) {
      return {
        generator,
        ...settings,
        module: plainPath(root, raw.module, `${key}.module`),
        input: plainPath(root, raw.input, `${key}.input`),
      };
    }
    if (raw.module !== undefined || raw.input !== undefined) {
      throw new TypeError(`${key} must use either match or module and input`);
    }
    const match = relativePath(root, raw.match, `${key}.match`);
    if (
      /[*?\[\]]/.test(dirname(match)) ||
      !/^\*\.[^*?\[\]]+$/.test(basename(match))
    ) {
      throw new TypeError(`${key}.match must have the form dir/*.ext`);
    }
    return { generator, ...settings, match };
  });
}

// Preserve the meaning of missing paths for overlays and validate every
// existing parent, including a symlink in the path to a virtual module.
async function projectPath(
  root: string,
  path: string,
  directory = false,
): Promise<string> {
  const parents: string[] = [];
  let current = path;
  while (true) {
    try {
      const canonical = await Deno.realPath(current);
      const target = resolve(canonical, ...parents);
      if (!inside(root, target) && !(directory && target === root)) {
        throw new Error(`Generator path escapes the project: ${path}`);
      }
      return target;
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
      const info = await Deno.lstat(current).catch((error) => {
        if (!(error instanceof Deno.errors.NotFound)) throw error;
      });
      if (info?.isSymlink) {
        throw new Error(`Unresolved generator symlink: ${current}`);
      }
      parents.unshift(basename(current));
      current = dirname(current);
    }
  }
}

/** Check explicit paths and glob directories against symlink escapes. */
export async function validateGeneratorRulePaths(
  root: string,
  rules: readonly BlotGeneratorRule[],
): Promise<void> {
  if (!rules.length) return;
  const base = await Deno.realPath(root);
  for (const { generator, module, input, match } of rules) {
    await projectPath(base, resolve(base, generator));
    if (match !== undefined) {
      await projectPath(base, resolve(base, dirname(match)), true);
    } else {
      const target = module!.endsWith(".blot") ? module! : module + ".blot";
      await projectPath(base, resolve(base, target));
      await projectPath(base, resolve(base, input!));
    }
  }
}

/** Expand project-relative rules to absolute asset mappings for any entry. */
export async function expandGeneratorRules(
  root: string | URL,
  rules: readonly BlotGeneratorRule[],
  options: GeneratorCompilerOptions = {},
): Promise<AssetImports> {
  const base = await Deno.realPath(pathOf(root));
  const assets: Record<string, AssetImport> = Object.create(null);
  const parsers = new Map<string, AssetParser>();
  let count = 0;
  for (const rule of readGeneratorRules(rules, base, "generators")) {
    const generator = await projectPath(base, resolve(base, rule.generator));
    const settings = {
      generator,
      exportName: rule.exportName ?? "generate",
      inputMode: rule.inputMode ?? "bytes",
      reference: rule.reference,
    } as const;
    const key = JSON.stringify(settings);
    let parser = parsers.get(key);
    if (!parser) {
      parser = createBlotGenerator({ ...options, ...settings });
      parsers.set(key, parser);
    }
    const add = async (module: string, input: string) => {
      const target = await projectPath(
        base,
        module.endsWith(".blot") ? module : module + ".blot",
      );
      const path = await projectPath(base, input);
      if (Object.hasOwn(assets, target)) {
        throw new Error(`Duplicate generator module: ${module}`);
      }
      if (++count > 4096) throw new RangeError("Too many generated modules");
      assets[target] = { path, parser };
    };
    if (rule.match !== undefined) {
      const directory = await projectPath(
        base,
        resolve(base, dirname(rule.match)),
        true,
      );
      const suffix = basename(rule.match).slice(1);
      const files: string[] = [];
      for await (const item of Deno.readDir(directory)) {
        if ((item.isFile || item.isSymlink) && item.name.endsWith(suffix)) {
          files.push(item.name);
        }
      }
      for (const file of files.sort()) {
        const input = resolve(directory, file);
        await add(input, input);
      }
    } else {
      await add(resolve(base, rule.module!), resolve(base, rule.input!));
    }
  }
  return assets;
}

type SourceToken = { text: string; start: number };

// Stage 0 only needs import paths and the selected entry marker. Skip line
// comments and keep quoted strings intact so embedded Blot is never scanned
// as generator code. The native compiler still checks all source syntax.
function scan(source: string): SourceToken[] {
  const tokens: SourceToken[] = [];
  for (
    const match of source.matchAll(
      /\/\/[^\r\n]*|"(?:[^"\\\r\n]|\\[^\r\n])*"?|[A-Za-z_][A-Za-z0-9_]*|[^ \t\r\n]/gu,
    )
  ) {
    const text = match[0];
    if (!text.startsWith("//")) {
      tokens.push({ text, start: match.index });
    }
  }
  return tokens;
}

function importPaths(source: string): string[] {
  const tokens = scan(source);
  const paths: string[] = [];
  for (let index = 0; index < tokens.length; index++) {
    const { text, start } = tokens[index];
    if (start > 0 && !/[\r\n]/.test(source[start - 1])) continue;
    const shape = tokens[index + 1]?.text;
    let from: number;
    if ((text === "import" || text === "export") && shape === "{") {
      from = tokens.findIndex((token, i) =>
        i > index + 1 && token.text === "}"
      ) + 1;
      if (from === 0) continue;
    } else if (text === "import" && shape === "*") {
      from = index + 4; // import * as alias from "path"
    } else continue;
    if (
      tokens[from]?.text !== "from" || !tokens[from + 1]?.text.startsWith('"')
    ) continue;
    const literal = tokens[from + 1].text;
    if (/^"(?:[^"\\\r\n]|\\[nrt"\\])*"$/.test(literal)) {
      paths.push(
        literal.slice(1, -1).replace(
          /\\([nrt"\\])/g,
          (_, code: string) =>
            code === "n"
              ? "\n"
              : code === "r"
              ? "\r"
              : code === "t"
              ? "\t"
              : code,
        ),
      );
    }
    index = from + 1;
  }
  return paths;
}

function resolveImport(
  file: string,
  specifier: string,
  aliases: readonly (readonly [string, string])[],
) {
  const match = aliases.find(([prefix]) => specifier.startsWith(prefix));
  const local = specifier.startsWith("./") || specifier.startsWith("../");
  if ((!local && !match) || /[?#]|%2f/i.test(specifier)) return;
  const prefix = local ? dirname(file) : match![1];
  try {
    const tail = decodeURIComponent(
      local ? specifier : specifier.slice(match![0].length),
    );
    if (tail.startsWith("/") || tail.includes("\0")) return;
    return resolve(prefix, tail.endsWith(".blot") ? tail : tail + ".blot");
  } catch {
    // Report malformed paths through the native compiler.
  }
}

type TrackedSource = { hash: string; imports: readonly string[] };
type Snapshot = {
  entry: string;
  sources: Record<string, string>;
  graph: ReadonlyMap<string, TrackedSource>;
  key: string;
};

async function snapshot(
  context: AssetContext,
  generator: string,
  prelude: string | null | undefined,
  aliases: readonly (readonly [string, string])[],
  previous: ReadonlyMap<string, TrackedSource> | undefined,
): Promise<Snapshot> {
  const paths = new Map<string, string>();
  const sources: Record<string, string> = Object.create(null);
  const graph = new Map<string, TrackedSource>();
  async function visit(path: string): Promise<string> {
    const existing = paths.get(path);
    if (existing !== undefined) return existing;
    const bytes = await context.read(path);
    // Keep lexical paths as dependencies, and traverse imports from the
    // canonical path just as the compiler does.
    const filename = await Deno.realPath(path).catch((error) => {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
      return path; // an assetSources overlay may supply a virtual Blot file
    });
    paths.set(path, filename);
    if (graph.has(filename)) return filename;
    const source = decoder.decode(bytes);
    const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))
      .toHex();
    const before = previous?.get(filename);
    const imports = before?.hash === hash
      ? before.imports
      : importPaths(source);
    sources[filename] = source;
    graph.set(filename, { hash, imports });
    for (const specifier of imports) {
      const imported = resolveImport(filename, specifier, aliases);
      if (imported !== undefined) await visit(imported);
    }
    return filename;
  }
  const entry = await visit(generator);
  if (prelude) await visit(prelude);
  return {
    entry,
    sources,
    graph,
    key: JSON.stringify([...graph].map(([name, { hash }]) => [name, hash])),
  };
}

type ExecutableGenerator = {
  module: WebAssembly.Module;
  name: string;
  record: boolean;
  result: boolean;
};

function diagnostics(errors: readonly ZigProjectDiagnostic[]): string {
  return errors.map(({ filename, code, message }) =>
    `${filename} [${code}] ${message}`
  ).join("\n");
}

async function compile(
  options: BlotGeneratorOptions,
  entry: string,
  captured: Snapshot,
  signal: AbortSignal | undefined,
): Promise<ExecutableGenerator> {
  const { createCompiler } = await import("../mod.ts");
  const executable = options.executable ?? await findCheckoutCompiler();
  const { prelude, stdRoot, imports } = options;
  const compiler = await createCompiler({
    prelude,
    stdRoot,
    imports,
    entry,
    executable,
  });
  const name = options.exportName ?? "generate";
  const field = options.inputMode === "text" ? "text" : "bytes";
  const unsupported =
    `Unsupported signature for generator ${name} in ${entry}. Expected #[U32] or { path: #[U32], ${field}: #[U32] } to #[U32] or Result [#[U32], #[U32]].`;
  function validate(
    bytes: Uint8Array<ArrayBuffer>,
    name: string,
    record: boolean,
    result: boolean,
  ) {
    const module = new WebAssembly.Module(bytes);
    const abi = readGuestAbi(module);
    const fn = abi.functions.find((fn) => fn.name === name);
    if (!fn) {
      throw new BlotGeneratorError(
        "compile",
        `Missing #entry function ${name} in generator ${entry}`,
      );
    }
    if (
      abi.version !== 8 || fn.parameter !== "Array U32" ||
      fn.result !== "Array U32"
    ) return;
    if (WebAssembly.Module.imports(module).length) {
      throw new BlotGeneratorError(
        "compile",
        `Generator ${entry} requires Wasm host imports; Stage 0 grants no capabilities`,
      );
    }
    return { module, name, record, result };
  }
  try {
    const initial = await compiler.build({ sources: captured.sources, signal });
    if (initial.success) {
      const direct = validate(initial.bytes, name, false, false);
      if (direct) return direct;
      throw new BlotGeneratorError("compile", unsupported);
    }
    if (
      !initial.diagnostics.length ||
      initial.diagnostics.some(({ code }) => code !== "entry_type")
    ) {
      throw new BlotGeneratorError(
        "compile",
        `Could not compile generator ${entry}:\n${
          diagnostics(initial.diagnostics)
        }`,
      );
    }

    // The installed ABI has numeric arrays, so lower the rich signature
    // inside Blot. The native checker verifies every argument/result shape.
    const filename = captured.entry;
    const original = captured.sources[filename];
    const tokens = scan(original);
    const marker = tokens.findIndex((token, i) =>
      token.text === "#" && tokens[i + 1]?.text === "entry" &&
      (tokens[i + 2]?.text === "private"
          ? tokens[i + 4]?.text
          : tokens[i + 3]?.text) === name
    );
    if (marker === -1) {
      throw new BlotGeneratorError(
        "compile",
        `Missing #entry function ${name} in generator ${entry}`,
      );
    }
    // Keep the declaration at column one after stripping the entry marker.
    const start = tokens[marker].start;
    const end = tokens[marker + 2].start;
    const source = original.slice(0, start) + original.slice(end);
    const usedNames = new Set(tokens.map((token) => token.text));
    let adapter = "_blot_stage0";
    while (usedNames.has(adapter)) adapter += "_";

    const recordFirst = initial.diagnostics[0].message.includes(
      "parameters of type record",
    );
    let loweringFailure: readonly ZigProjectDiagnostic[] | undefined;
    // Try the likely ABI adaptation first, with the checker deciding the
    // signature. The diagnostic wording is only an ordering hint.
    for (const record of recordFirst ? [true, false] : [false, true]) {
      for (const result of record ? [true, false] : [true]) {
        const annotation = result ? ": Result [#[U32], #[U32]]" : "";
        const unpack = record
          ? `  let path_size = packet[0]
  let offset = @u32.add path_size 1
  let path = @array.generate path_size (func i => return packet[(@u32.add i 1)])
  let input_values = @array.generate (@u32.sub packet.length offset) (func i => return packet[(@u32.add i offset)])
  let generated${annotation} = ${name} { path: path, ${field}: input_values }
`
          : `  let generated${annotation} = ${name} packet\n`;
        const pack = result
          ? `  return case generated of
    $Ok source => @array.concat #[0] source
    $Err message => @array.concat #[1] message
`
          : "  return generated\n";
        const built = await compiler.build({
          sources: {
            ...captured.sources,
            [filename]: source +
              `\n#entry func ${adapter} (packet: #[U32]): #[U32] =>\n` +
              unpack +
              pack,
          },
          signal,
        });
        if (built.success) {
          const adapted = validate(built.bytes, adapter, record, result);
          if (adapted) return adapted;
        } else if (
          !loweringFailure &&
          built.diagnostics.length > 0 &&
          built.diagnostics.every(({ stage }) =>
            stage !== "parse" && stage !== "check"
          )
        ) {
          loweringFailure = built.diagnostics;
        }
      }
    }
    if (loweringFailure) {
      throw new BlotGeneratorError(
        "compile",
        `Could not compile generator ${entry}:\n${
          diagnostics(loweringFailure)
        }`,
      );
    }
    throw new BlotGeneratorError(
      "compile",
      `${unsupported}\n${diagnostics(initial.diagnostics)}`,
    );
  } finally {
    await compiler.dispose();
  }
}

/** Compile a Blot asset parser once per source graph and run each input in a fresh guest. */
export function createBlotGenerator(
  options: BlotGeneratorOptions,
): AssetParser {
  const { exportName, inputMode, reference } = validateSettings(
    { ...options },
    "generator",
  );
  const generator = pathOf(options.generator);
  const capturedPath = (path: string | URL | null | undefined) =>
    path == null ? path : pathOf(path);
  const config: BlotGeneratorOptions = {
    generator,
    exportName,
    inputMode,
    reference,
    executable: options.executable === undefined
      ? undefined
      : pathOf(options.executable),
    prelude: capturedPath(options.prelude),
    stdRoot: capturedPath(options.stdRoot),
    imports: Object.fromEntries(
      Object.entries(options.imports ?? {}).map((
        [prefix, path],
      ) => [prefix, pathOf(path)]),
    ),
  };
  const aliases = Object.entries(config.imports ?? {}).map(([name, path]) =>
    [name, pathOf(path)] as const
  );
  const standard = config.stdRoot ??
    (config.stdRoot === undefined && !Deno.build.standalone ? std : null);
  if (standard !== null) aliases.unshift(["std/", pathOf(standard)]);
  aliases.sort(([a], [b]) => b.length - a.length);
  const prelude = config.prelude === undefined && !Deno.build.standalone
    ? pathOf(new URL("prelude.blot", std))
    : config.prelude as string | null | undefined;

  // Share in-flight compilation between assets while keeping at most one
  // compiled source graph per configuration.
  let cached: {
    key: string;
    graph: Snapshot["graph"];
    compiled: Promise<ExecutableGenerator>;
  } | undefined;
  const parser: AssetParser = async (context) => {
    let data: Uint32Array;
    if (inputMode === "text") {
      try {
        data = encodeText(decoder.decode(context.bytes));
      } catch (cause) {
        throw new BlotGeneratorError(
          "execute",
          `Expected UTF-8 text for generator input ${context.path}`,
          { cause },
        );
      }
    } else {
      data = Uint32Array.from(context.bytes);
    }
    let state: Snapshot;
    try {
      state = await snapshot(
        context,
        generator,
        prelude,
        aliases,
        cached?.graph,
      );
    } catch (cause) {
      if (cause instanceof BlotGeneratorError || context.signal?.aborted) {
        throw cause;
      }
      throw new BlotGeneratorError(
        "compile",
        cause instanceof Error ? cause.message : String(cause),
        { cause },
      );
    }
    context.signal?.throwIfAborted();
    if (cached?.key !== state.key) {
      const candidate = {
        key: state.key,
        graph: state.graph,
        compiled: compile(config, generator, state, context.signal),
      };
      cached = candidate;
      candidate.compiled.catch(() => {
        if (cached === candidate) cached = undefined;
      });
    }
    const compiled = await cached.compiled;
    context.signal?.throwIfAborted();
    let argument = data;
    if (compiled.record) {
      const path = encodeText(context.path);
      argument = new Uint32Array(1 + path.length + data.length);
      argument[0] = path.length;
      argument.set(path, 1);
      argument.set(data, 1 + path.length);
    }
    const guest = await instantiateGuest(compiled.module);
    let output: unknown;
    try {
      output = guest.call(compiled.name, argument);
    } catch (cause) {
      const trap = guestTrapOf(cause);
      const message = trap
        ? trap.formatted
        : cause instanceof Error
        ? cause.message
        : String(cause);
      const detail = cause instanceof WebAssembly.RuntimeError
        ? "trapped"
        : "failed";
      throw new BlotGeneratorError(
        "execute",
        `Blot generator ${
          exportName ?? "generate"
        } ${detail} for ${context.path}: ${message}`,
        { cause, ...(trap && { trap }) },
      );
    } finally {
      guest.dispose();
    }
    if (!(output instanceof Uint32Array)) {
      throw new BlotGeneratorError(
        "result",
        "Generator returned an invalid Text value",
      );
    }
    if (compiled.result && output[0] !== 0 && output[0] !== 1) {
      throw new BlotGeneratorError(
        "result",
        "Generator returned an invalid Result tag",
      );
    }
    let source: string;
    try {
      source = decodeText(compiled.result ? output.subarray(1) : output);
    } catch (cause) {
      throw new BlotGeneratorError(
        "result",
        cause instanceof Error ? cause.message : String(cause),
        { cause },
      );
    }
    if (compiled.result && output[0] === 1) {
      throw new BlotGeneratorError("result", source);
    }
    if (!reference) return { source };
    const ref = await context.reference(undefined, reference.mediaType);
    return {
      source,
      values: {
        [reference.export]: { type: { reference: reference.type }, value: ref },
      },
    };
  };
  return tagAssetParser(parser, { generator });
}
