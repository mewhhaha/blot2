/** Full-buffer completion, diagnostics, and quick-fix bridge. Native query graphs never enter editor state. */
import { dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { analyzeDiagnostic, type RawDiagnosticRecord } from "./diagnostics.ts";
import { expandGeneratorRules } from "./generators.ts";
import { resolveGeneratorProject } from "./packages.ts";
import {
  createZigProjectCompiler,
  type ZigProjectCompiler,
  type ZigProjectCompilerOptions,
  type ZigProjectDiagnostic,
} from "./zig_project_client.ts";
import {
  byteOffset,
  LspReader,
  LspWriter,
  type Position,
  utf16Position,
} from "./lsp_protocol.ts";

type Id = string | number | null;
type Document = { filename: string; text: string; version: number };
interface LspRange {
  start: Position;
  end: Position;
}
interface LspQuickFixData {
  title: string;
  range: LspRange;
  newText: string;
}
interface LspDiagnostic {
  range: LspRange;
  severity: number;
  code: string;
  source: string;
  message: string;
  relatedInformation?: Array<{
    location: { uri: string; range: LspRange };
    message: string;
  }>;
  data?: { blotQuickFixes: LspQuickFixData[] };
}
const utf8Encoder = new TextEncoder();
function safeUtf16Position(text: string, offset: number): Position {
  const bytes = utf8Encoder.encode(text);
  let clamped = Math.max(0, Math.min(bytes.length, Math.trunc(offset)));
  while (clamped > 0 && (bytes[clamped] & 0xc0) === 0x80) clamped--;
  return utf16Position(text, clamped);
}
function utf16Range(
  text: string,
  startByte: number,
  endByte: number,
): LspRange {
  const start = safeUtf16Position(text, startByte);
  const end = safeUtf16Position(text, Math.max(startByte, endByte));
  return { start, end };
}
function rangesOverlap(a: LspRange, b: LspRange): boolean {
  const cmp = (x: Position, y: Position) =>
    x.line !== y.line ? x.line - y.line : x.character - y.character;
  return cmp(a.start, b.end) <= 0 && cmp(b.start, a.end) <= 0;
}
function toLspDiagnostic(
  diag: ZigProjectDiagnostic,
  sourceText: string | undefined,
  uri: string,
): LspDiagnostic {
  const extended = diag as ZigProjectDiagnostic & Partial<RawDiagnosticRecord>;
  const raw: RawDiagnosticRecord = {
    filename: diag.filename,
    stage: diag.stage,
    code: diag.code,
    start: diag.start,
    end: diag.end,
    message: diag.message,
    offset_encoding: diag.offset_encoding,
    details: diag.details as RawDiagnosticRecord["details"],
    origin_kind: diag.blame?.kind,
    origin_start: diag.blame?.start,
    origin_end: diag.blame?.end,
    subject_start: diag.blame?.subjectStart,
    subject_end: diag.blame?.subjectEnd,
    holder_start: diag.blame?.holderStart,
    holder_end: diag.blame?.holderEnd,
    explanation: diag.explanation,
    contexts: diag.contexts,
    related: diag.related,
    provenance: extended.provenance,
    virtual_source: extended.virtual_source,
  };
  const effectiveSource = sourceText ?? extended.virtual_source;
  const analyzed = analyzeDiagnostic(raw, effectiveSource);
  const range = effectiveSource !== undefined
    ? utf16Range(
      effectiveSource,
      analyzed.primarySpan.startByte,
      analyzed.primarySpan.endByte,
    )
    : { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } };
  const lines = [analyzed.headline];
  if (extended.provenance) {
    lines.push(
      extended.provenance.generator
        ? `from ${extended.provenance.input} via ${extended.provenance.generator} (stage0 ${extended.provenance.phase})`
        : `from ${extended.provenance.input} (stage0 ${extended.provenance.phase})`,
    );
  }
  if (analyzed.fix) lines.push(`fix: ${analyzed.fix}`);
  lines.push(`doc: ${analyzed.docRef}`);
  const item: LspDiagnostic = {
    range,
    severity: 1,
    code: analyzed.canonicalCode,
    source: "blot",
    message: lines.join("\n"),
  };
  if (analyzed.secondarySpan && effectiveSource !== undefined) {
    item.relatedInformation = [
      {
        location: {
          uri,
          range: utf16Range(
            effectiveSource,
            analyzed.secondarySpan.startByte,
            analyzed.secondarySpan.endByte,
          ),
        },
        message: analyzed.secondarySpan.label,
      },
    ];
  }
  const safeQuickFixes = analyzed.quickFixes.filter(
    (qf) => qf.complete !== false,
  );
  if (safeQuickFixes.length > 0 && sourceText !== undefined) {
    item.data = {
      blotQuickFixes: safeQuickFixes.map((qf) => ({
        title: qf.title,
        range: utf16Range(sourceText, qf.startByte, qf.endByte),
        newText: qf.newText,
      })),
    };
  }
  return item;
}
class RpcError extends Error {
  constructor(readonly code: number, message: string) {
    super(message);
  }
}
function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new RpcError(-32602, "Expected an object");
  }
  return value as Record<string, unknown>;
}
function filename(uri: unknown): string {
  if (typeof uri !== "string") {
    throw new RpcError(-32602, "Expected a file URI");
  }
  try {
    const url = new URL(uri);
    if (url.protocol !== "file:" || url.search || url.hash) throw new Error();
    return fileURLToPath(url);
  } catch {
    throw new RpcError(-32602, "Expected a local file URI");
  }
}
function version(value: unknown): number {
  if (!Number.isSafeInteger(value)) {
    throw new RpcError(-32602, "Invalid document version");
  }
  return value as number;
}
function source(value: unknown): string {
  if (
    typeof value !== "string" || !value.isWellFormed() ||
    new TextEncoder().encode(value).length > 16 * 1024 * 1024
  ) {
    throw new RpcError(-32602, "Invalid document text");
  }
  return value;
}
export class CompletionBridge {
  #documents = new Map<string, Document>();
  #diagnosticsCache = new Map<
    string,
    { version: number; items: LspDiagnostic[] }
  >();
  #requests = new Map<Id, AbortController>();
  #snapshot = 0;
  #generation = 0;
  #child:
    | {
      compiler: ZigProjectCompiler;
      filename: string;
      generation: number;
      assetInputs?: ReadonlySet<string>;
    }
    | undefined;
  #projectChanged = false;
  #work: Promise<unknown> = Promise.resolve();
  #watchers: Deno.FsWatcher[] = [];
  #roots = new Set<string>();
  #initialized = false;
  #shutdown = false;
  #closed = false;
  constructor(
    private output: LspWriter,
    private options: Omit<ZigProjectCompilerOptions, "entry">,
    private exit: (code: number) => void = () => {},
  ) {}
  #invalidate() {
    if (++this.#snapshot > 0xffff_ffff) this.#snapshot = 1;
    for (const controller of this.#requests.values()) {
      controller.abort(new RpcError(-32801, "Document or query changed"));
    }
  }
  #watch(root: string) {
    root = resolve(root);
    if (this.#roots.has(root)) return;
    this.#roots.add(root);
    for (
      const [path, recursive] of [[root, true], [dirname(root), false]] as const
    ) {
      let watcher: Deno.FsWatcher;
      try {
        watcher = Deno.watchFs(path, { recursive });
      } catch (error) {
        console.error(`blot: cannot watch ${path}: ${error}`);
        continue;
      }
      this.#watchers.push(watcher);
      void (async () => {
        try {
          for await (const event of watcher) {
            const projectChanged = recursive &&
              event.paths.some((file) =>
                file.endsWith("/blot.json") || file.endsWith("/blot.lock.json")
              );
            const assetChanged = event.paths.some((file) =>
              this.#child?.assetInputs?.has(file)
            );
            const sourceChanged = event.paths.some((file) =>
              file === root || (recursive && file.endsWith(".blot"))
            );
            if (projectChanged) this.#projectChanged = true;
            if (
              projectChanged || assetChanged ||
              (sourceChanged && this.#child?.assetInputs)
            ) {
              this.#diagnosticsCache.clear();
            }
            if (projectChanged || assetChanged || sourceChanged) {
              this.#invalidate();
            }
          }
        } catch (error) {
          if (!this.#closed) console.error(`blot: watcher: ${error}`);
        }
      })();
    }
  }
  async #disposeChild() {
    const child = this.#child;
    this.#child = undefined;
    if (child) await child.compiler.dispose();
  }
  async #compilerFor(file: string, signal: AbortSignal, deadline?: number) {
    signal.throwIfAborted();
    if (this.#projectChanged || this.#child?.filename !== file) {
      this.#projectChanged = false;
      await this.#disposeChild();
    }
    signal.throwIfAborted();
    if (!this.#child) {
      const project = await resolveGeneratorProject(file);
      const options: ZigProjectCompilerOptions = {
        ...this.options,
        entry: file,
      };
      let assetInputs: Set<string> | undefined;
      if (project?.generators?.length) {
        options.prelude = project.prelude;
        options.stdRoot = project.stdRoot;
        options.imports = { ...project.imports, ...this.options.imports };
        options.assets = await expandGeneratorRules(
          project.root,
          project.generators,
          options,
        );
        assetInputs = new Set(
          Object.values(options.assets).map(({ path }) => path as string),
        );
        this.#watch(project.root);
      }
      signal.throwIfAborted();
      if (deadline !== undefined) {
        options.startupTimeoutMs = Math.max(
          1,
          Math.floor(deadline - performance.now()),
        );
      }
      const compiler = await createZigProjectCompiler(options);
      this.#child = {
        compiler,
        filename: file,
        generation: ++this.#generation,
        assetInputs,
      };
    }
    return this.#child;
  }
  #overlays(
    sources: Record<string, string>,
    assetInputs?: ReadonlySet<string>,
  ) {
    if (!assetInputs) return { sources };
    const blotSources: Record<string, string> = Object.create(null);
    const assetSources: Record<string, string> = Object.create(null);
    for (const [path, text] of Object.entries(sources)) {
      (assetInputs.has(path) ? assetSources : blotSources)[path] = text;
    }
    return { sources: blotSources, assetSources };
  }
  async dispose() {
    if (this.#closed) return;
    this.#closed = true;
    for (const controller of this.#requests.values()) {
      controller.abort(new RpcError(-32800, "Server closed"));
    }
    for (const watcher of this.#watchers) watcher.close();
    this.#watchers = [];
    await this.#disposeChild();
    await this.#work.catch(() => {});
    await this.#disposeChild();
  }
  async #complete(params: unknown, id: Id) {
    const request = object(params);
    const file = filename(object(request.textDocument).uri);
    const document = this.#documents.get(file);
    if (!document) throw new RpcError(-32602, "Document is not open");
    let position: number;
    try {
      position = byteOffset(document.text, request.position as Position);
    } catch (error) {
      throw new RpcError(-32602, String(error));
    }
    // A newer cursor query makes a held reply stale, even without a text edit.
    this.#invalidate();
    const snapshot = this.#snapshot;
    const sources = Object.fromEntries(
      [...this.#documents.values()].map((doc) => [doc.filename, doc.text]),
    );
    const controller = new AbortController();
    this.#requests.set(id, controller);
    const deadline = performance.now() + 250;
    const timer = setTimeout(
      () =>
        controller.abort(new RpcError(-32800, "Completion deadline exceeded")),
      250,
    );
    let abort!: () => void;
    const cancellation = new Promise<never>((_, reject) => {
      abort = () => reject(controller.signal.reason);
      controller.signal.addEventListener("abort", abort, { once: true });
    });
    const operation = this.#work.then(async () => {
      const child = await this.#compilerFor(file, controller.signal, deadline);
      try {
        controller.signal.throwIfAborted();
        const result = await child.compiler.complete({
          filename: file,
          position,
          snapshot,
          ...this.#overlays(sources, child.assetInputs),
          signal: controller.signal,
        });
        if (
          this.#child !== child || child.generation !== this.#generation ||
          this.#snapshot !== snapshot ||
          this.#documents.get(file) !== document ||
          result.snapshot !== snapshot || result.filename !== file ||
          result.position !== position || result.revision !== 0
        ) {
          throw new RpcError(-32801, "Completion result is stale");
        }
        if (!result.success) {
          throw new RpcError(-32603, result.diagnostics[0].message);
        }
        const kinds = {
          value: 6,
          function: 3,
          type: 7,
          constructor: 4,
          field: 5,
          member: 2,
          module: 9,
        };
        const range = {
          start: utf16Position(document.text, result.replace.start),
          end: utf16Position(document.text, result.replace.end),
        };
        // Helix filters against the word already at the caret. A semantic hole
        // has no candidate prefix, so keep its typed spelling only for filtering.
        const typed = new TextDecoder().decode(
          new TextEncoder().encode(document.text).subarray(
            result.replace.start,
            position,
          ),
        );
        let filterPrefix = "";
        if (typed.startsWith("@")) filterPrefix = typed.slice(1);
        return {
          isIncomplete: result.truncated,
          items: result.items.map((item, index) => ({
            label: item.label,
            kind: kinds[item.kind],
            detail: item.detail ?? undefined,
            insertTextFormat: 1,
            textEdit: { range, newText: item.insertText },
            filterText: filterPrefix + item.insertText.replace(/^#/, ""),
            sortText: String(index).padStart(3, "0"),
          })),
        };
      } catch (error) {
        if (controller.signal.aborted || !(error instanceof RpcError)) {
          await this.#disposeChild();
        }
        if (controller.signal.aborted) throw controller.signal.reason;
        throw error;
      }
    });
    this.#work = operation.catch(() => {});
    try {
      return await Promise.race([operation, cancellation]);
    } finally {
      clearTimeout(timer);
      controller.signal.removeEventListener("abort", abort);
      if (this.#requests.get(id) === controller) this.#requests.delete(id);
    }
  }
  async #diagnose(file: string, id: Id | null): Promise<LspDiagnostic[]> {
    const document = this.#documents.get(file);
    if (!document) return [];
    const cached = this.#diagnosticsCache.get(file);
    if (cached && cached.version === document.version) {
      return cached.items;
    }
    const sources = Object.fromEntries(
      [...this.#documents.values()].map((doc) => [doc.filename, doc.text]),
    );
    const controller = new AbortController();
    if (id !== null) this.#requests.set(id, controller);
    const operation = this.#work.then(async () => {
      const child = await this.#compilerFor(file, controller.signal);
      try {
        const result = await child.compiler.build({
          ...this.#overlays(sources, child.assetInputs),
          signal: controller.signal,
        });
        if (this.#documents.get(file) !== document) return [];
        const items: LspDiagnostic[] = [];
        if (!result.success) {
          for (const diag of result.diagnostics) {
            if (
              diag.code === "no_entry" ||
              diag.message.includes("exports nothing")
            ) {
              continue;
            }
            if (diag.filename !== file) continue;
            items.push(
              toLspDiagnostic(diag, document.text, pathToFileURL(file).href),
            );
          }
        }
        this.#diagnosticsCache.set(file, {
          version: document.version,
          items,
        });
        return items;
      } catch (error) {
        if (controller.signal.aborted) throw controller.signal.reason;
        await this.#disposeChild();
        throw error;
      }
    });
    this.#work = operation.catch(() => {});
    try {
      return await operation;
    } finally {
      if (id !== null && this.#requests.get(id) === controller) {
        this.#requests.delete(id);
      }
    }
  }
  async #codeActions(params: unknown, id: Id) {
    const request = object(params);
    const uri = object(request.textDocument).uri;
    const file = filename(uri);
    const document = this.#documents.get(file);
    if (!document) return [];
    const rangeObj = object(request.range);
    const reqRange: LspRange = {
      start: object(rangeObj.start) as unknown as Position,
      end: object(rangeObj.end) as unknown as Position,
    };
    const context = object(request.context);
    const passed = Array.isArray(context.diagnostics)
      ? context.diagnostics
      : [];
    const fixes: Array<{
      title: string;
      kind: string;
      isPreferred: boolean;
      diagnostics: unknown[];
      edit: {
        changes: Record<string, Array<{ range: LspRange; newText: string }>>;
      };
    }> = [];
    const seen = new Set<string>();
    const addFromDiagnostics = (diags: unknown[]) => {
      for (const d of diags) {
        if (!d || typeof d !== "object") continue;
        const diag = d as LspDiagnostic;
        const quickFixes = diag.data?.blotQuickFixes;
        if (!Array.isArray(quickFixes)) continue;
        if (diag.range && !rangesOverlap(diag.range, reqRange)) continue;
        for (let i = 0; i < quickFixes.length; i++) {
          const qf = quickFixes[i];
          const key =
            `${qf.title}:${qf.range.start.line}:${qf.range.start.character}:${qf.newText}`;
          if (seen.has(key)) continue;
          seen.add(key);
          fixes.push({
            title: qf.title,
            kind: "quickfix",
            isPreferred: i === 0,
            diagnostics: [diag],
            edit: {
              changes: {
                [uri as string]: [{ range: qf.range, newText: qf.newText }],
              },
            },
          });
        }
      }
    };
    addFromDiagnostics(passed);
    if (fixes.length === 0) {
      const fresh = await this.#diagnose(file, id);
      addFromDiagnostics(fresh);
    }
    return fixes;
  }
  async handle(raw: unknown): Promise<void> {
    let id: Id = null;
    let hasId = false;
    try {
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
        throw new RpcError(-32600, "Invalid JSON-RPC request");
      }
      const message = object(raw);
      hasId = Object.hasOwn(message, "id");
      if (hasId) {
        if (
          message.id !== null && typeof message.id !== "string" &&
          (typeof message.id !== "number" || !Number.isSafeInteger(message.id))
        ) throw new RpcError(-32600, "Invalid request ID");
        id = message.id as Id;
      }
      if (message.jsonrpc !== "2.0" || typeof message.method !== "string") {
        throw new RpcError(-32600, "Invalid JSON-RPC request");
      }
      const method = message.method;
      if (method === "exit") {
        const code = Number(!this.#shutdown);
        await this.dispose();
        this.exit(code);
        return;
      }
      if (method === "$/cancelRequest") {
        this.#requests.get(object(message.params).id as Id)?.abort(
          new RpcError(-32800, "Request cancelled"),
        );
        return;
      }
      if (
        !hasId &&
        ![
          "initialized",
          "textDocument/didOpen",
          "textDocument/didChange",
          "textDocument/didSave",
          "textDocument/didClose",
        ].includes(method)
      ) return;
      if (this.#shutdown) throw new RpcError(-32600, "Server is shut down");
      if (method === "initialize") {
        if (!hasId || this.#initialized) {
          throw new RpcError(-32600, "Invalid initialize request");
        }
        const params = object(message.params);
        const roots: unknown[] = [];
        if (Array.isArray(params.workspaceFolders)) {
          for (const folder of params.workspaceFolders) {
            roots.push(object(folder).uri);
          }
        } else if (params.rootUri !== null && params.rootUri !== undefined) {
          roots.push(params.rootUri);
        }
        for (const root of roots) this.#watch(filename(root));
        if (this.options.stdRoot) this.#watch(String(this.options.stdRoot));
        for (const root of Object.values(this.options.imports ?? {})) {
          this.#watch(String(root));
        }
        this.#initialized = true;
        await this.output.send({
          jsonrpc: "2.0",
          id,
          result: {
            capabilities: {
              positionEncoding: "utf-16",
              textDocumentSync: { openClose: true, change: 1, save: true },
              completionProvider: {
                resolveProvider: false,
                triggerCharacters: [".", "$"],
              },
              diagnosticProvider: {
                interFileDependencies: true,
                workspaceDiagnostics: false,
              },
              codeActionProvider: {
                codeActionKinds: ["quickfix"],
              },
            },
            serverInfo: { name: "blot" },
          },
        });
        return;
      }
      if (!this.#initialized) {
        throw new RpcError(-32002, "Server is not initialized");
      }
      if (method === "initialized") return;
      if (method === "shutdown") {
        if (!hasId) throw new RpcError(-32600, "Shutdown requires an ID");
        this.#shutdown = true;
        await this.dispose();
        await this.output.send({ jsonrpc: "2.0", id, result: null });
        return;
      }
      if (method.startsWith("textDocument/did")) {
        if (hasId) {
          throw new RpcError(-32600, "Document updates are notifications");
        }
        const params = object(message.params),
          textDocument = object(params.textDocument);
        const file = filename(textDocument.uri);
        if (method === "textDocument/didOpen") {
          const document = {
            filename: file,
            text: source(textDocument.text),
            version: version(textDocument.version),
          };
          this.#documents.set(file, document);
          this.#watch(dirname(file));
          this.#invalidate();
        } else if (method === "textDocument/didChange") {
          const previous = this.#documents.get(file);
          const next = version(textDocument.version);
          if (!previous) throw new RpcError(-32602, "Document is not open");
          if (next <= previous.version) {
            console.error("blot: ignored out-of-order document version");
            return;
          }
          if (
            !Array.isArray(params.contentChanges) ||
            params.contentChanges.length !== 1 ||
            Object.hasOwn(object(params.contentChanges[0]), "range")
          ) throw new RpcError(-32602, "Expected one full-text change");
          this.#documents.set(file, {
            filename: file,
            text: source(object(params.contentChanges[0]).text),
            version: next,
          });
          if (this.#child?.assetInputs?.has(file)) {
            this.#diagnosticsCache.clear();
          } else this.#diagnosticsCache.delete(file);
          this.#invalidate();
        } else if (method === "textDocument/didSave") {
          this.#diagnosticsCache.delete(file);
          const items = await this.#diagnose(file, null);
          const current = this.#documents.get(file);
          if (current) {
            await this.output.send({
              jsonrpc: "2.0",
              method: "textDocument/publishDiagnostics",
              params: {
                uri: textDocument.uri,
                version: current.version,
                diagnostics: items,
              },
            });
          }
        } else if (method === "textDocument/didClose") {
          this.#documents.delete(file);
          if (this.#child?.assetInputs?.has(file)) {
            this.#diagnosticsCache.clear();
          } else this.#diagnosticsCache.delete(file);
          this.#invalidate();
          if (this.#child?.filename === file) await this.#disposeChild();
        }
        return;
      }
      if (!hasId) return;
      if (method === "textDocument/diagnostic") {
        if (this.#requests.has(id)) {
          throw new RpcError(-32600, "Request ID is already pending");
        }
        const params = object(message.params);
        const file = filename(object(params.textDocument).uri);
        const items = await this.#diagnose(file, id);
        await this.output.send({
          jsonrpc: "2.0",
          id,
          result: { kind: "full", items },
        });
        return;
      }
      if (method === "textDocument/codeAction") {
        if (this.#requests.has(id)) {
          throw new RpcError(-32600, "Request ID is already pending");
        }
        const result = await this.#codeActions(message.params, id);
        await this.output.send({ jsonrpc: "2.0", id, result });
        return;
      }
      if (method !== "textDocument/completion") {
        throw new RpcError(-32601, "Method not found");
      }
      if (this.#requests.has(id)) {
        throw new RpcError(-32600, "Request ID is already pending");
      }
      const result = await this.#complete(message.params, id);
      await this.output.send({ jsonrpc: "2.0", id, result });
    } catch (error) {
      if (!hasId && error instanceof RpcError && error.code !== -32600) {
        console.error(`blot: ${error.message}`);
        return;
      }
      let code = -32603, message = String(error);
      if (error instanceof RpcError) {
        code = error.code;
        message = error.message;
      }
      await this.output.send({ jsonrpc: "2.0", id, error: { code, message } });
    }
  }
}
export function launchOptions(
  args: string[],
): Omit<ZigProjectCompilerOptions, "entry"> {
  const options: Omit<ZigProjectCompilerOptions, "entry"> = { executable: "" };
  const imports: Record<string, string> = {};
  for (let i = 0; i < args.length; i += 2) {
    const name = args[i], value = args[i + 1];
    if (!value) throw new Error(`Missing value for ${name}`);
    if (name === "--import") {
      const split = value.indexOf("=");
      if (
        split < 1 || !isAbsolute(value.slice(split + 1)) ||
        Object.hasOwn(imports, value.slice(0, split))
      ) throw new Error("Invalid import alias");
      imports[value.slice(0, split)] = value.slice(split + 1);
      continue;
    }
    if (
      !["--compiler", "--prelude", "--std-root"].includes(name) ||
      !isAbsolute(value)
    ) throw new Error("Expected absolute host/prelude/std paths");
    if (name === "--compiler") options.executable = value;
    if (name === "--prelude") options.prelude = value;
    if (name === "--std-root") options.stdRoot = value;
  }
  if (!options.executable) throw new Error("--compiler is required");
  options.imports = imports;
  if (!options.prelude) options.prelude = null;
  return options;
}
if (import.meta.main) {
  const writer = new LspWriter(Deno.stdout);
  const bridge = new CompletionBridge(
    writer,
    launchOptions(Deno.args),
    (code) => Deno.exit(code),
  );
  const reader = new LspReader(Deno.stdin);
  try {
    while (true) {
      const body = await reader.next();
      if (body === null) break;
      let message: unknown;
      try {
        message = JSON.parse(
          new TextDecoder("utf-8", { fatal: true }).decode(body),
        );
      } catch {
        await writer.send({
          jsonrpc: "2.0",
          id: null,
          error: { code: -32700, message: "Parse error" },
        });
        continue;
      }
      void bridge.handle(message).catch((error) =>
        console.error(`blot: ${error}`)
      );
    }
  } catch (error) {
    console.error(`blot: ${error}`);
    Deno.exitCode = 1;
  } finally {
    await bridge.dispose();
  }
}
