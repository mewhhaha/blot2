import { readTypedHole, type TypedHoleDiagnostic } from "./type_diagnostics.ts";
import type { ZigProjectDiagnostic } from "./zig_project_client.ts";

export interface ZigProjectCompletionOptions {
  filename: string | URL;
  position: number;
  snapshot: number;
  sources?: Readonly<Record<string, string | null>>;
  signal?: AbortSignal;
}

/** Own every caller field before a query can wait behind another operation. */
export function captureCompletion(
  options: ZigProjectCompletionOptions,
  path: (value: string | URL) => string,
): ZigProjectCompletionOptions & { filename: string } {
  if (
    !options || typeof options !== "object" || Array.isArray(options) ||
    Object.keys(options).some((key) =>
      !["filename", "position", "snapshot", "sources", "signal"].includes(key)
    )
  ) throw new TypeError("Invalid completion options");
  if (
    options.signal !== undefined && !(options.signal instanceof AbortSignal)
  ) {
    throw new TypeError("Completion signal must be an AbortSignal");
  }
  for (const value of [options.position, options.snapshot]) {
    if (!Number.isInteger(value) || value < 0 || value > 0xffff_ffff) {
      throw new RangeError("Invalid completion position or snapshot");
    }
  }
  if (options.snapshot === 0) {
    throw new RangeError("Completion snapshot must be nonzero");
  }
  const filename = path(options.filename);
  if (new TextEncoder().encode(filename).length > 4096) {
    throw new RangeError("Completion filename exceeds 4096 bytes");
  }
  const sources: Record<string, string | null> = Object.create(null);
  if (options.sources !== undefined) {
    if (
      !options.sources || typeof options.sources !== "object" ||
      Array.isArray(options.sources)
    ) {
      throw new TypeError("Completion sources must be an object");
    }
    const entries = Object.entries(options.sources);
    if (entries.length > 4096) {
      throw new RangeError("Too many completion sources");
    }
    const encoder = new TextEncoder();
    let total = 0;
    for (const [raw, value] of entries) {
      const name = path(raw);
      if (Object.hasOwn(sources, name)) {
        throw new TypeError("Duplicate source path");
      }
      let size = 0;
      if (value !== null) {
        if (typeof value !== "string" || !value.isWellFormed()) {
          throw new TypeError("Invalid completion source");
        }
        size = encoder.encode(value).length;
      }
      total += size;
      if (size > 16 * 1024 * 1024 || total > 64 * 1024 * 1024) {
        throw new RangeError("Completion source budget exceeded");
      }
      sources[name] = value;
    }
  }
  return {
    filename,
    sources,
    position: options.position,
    snapshot: options.snapshot,
    signal: options.signal,
  };
}
export interface ZigProjectCompletionItem {
  label: string;
  insertText: string;
  kind:
    | "value"
    | "function"
    | "type"
    | "constructor"
    | "field"
    | "member"
    | "module";
  detail: string | null;
  match: "exact" | "compatible" | "unknown" | "incompatible";
}
type Echo = {
  revision: number;
  snapshot: number;
  filename: string;
  position: number;
};
export type ZigProjectCompletionResult =
  & Echo
  & (
    | {
      success: true;
      replace: { start: number; end: number };
      context: TypedHoleDiagnostic | null;
      items: ZigProjectCompletionItem[];
      truncated: boolean;
      diagnostics: ZigProjectDiagnostic[];
    }
    | { success: false; diagnostics: ZigProjectDiagnostic[] }
  );

export function readCompletion(
  metadata: Record<string, unknown>,
  echo: Echo,
  epoch: string,
  payload: Uint8Array,
  source: Uint8Array | undefined,
  readDiagnostic: (value: unknown) => ZigProjectDiagnostic,
  fail: (message: string) => never,
): ZigProjectCompletionResult {
  const encoder = new TextEncoder();
  const text = (
    value: unknown,
    limit: number,
    nullable = false,
  ): string | null => {
    if (nullable && value === null) return null;
    if (
      typeof value !== "string" || !value.isWellFormed() ||
      encoder.encode(value).length > limit
    ) return fail("Invalid completion text");
    return value;
  };
  const offset = (value: unknown): number => {
    if (
      !Number.isInteger(value) || (value as number) < 0 ||
      (value as number) > 0xffff_ffff
    ) return fail("Invalid completion offset");
    const index = value as number;
    if (
      source &&
      (index > source.length ||
        (index < source.length && (source[index] & 0xc0) === 0x80))
    ) return fail("Completion offset is outside the captured source");
    return index;
  };
  if (
    payload.length ||
    encoder.encode(JSON.stringify(metadata)).length > 256 * 1024 ||
    metadata.epoch !== epoch || metadata.revision !== echo.revision ||
    metadata.snapshot !== echo.snapshot ||
    metadata.filename !== echo.filename ||
    metadata.position !== echo.position ||
    typeof metadata.success !== "boolean" ||
    !Array.isArray(metadata.diagnostics) || metadata.diagnostics.length > 16
  ) return fail("Invalid completion response");
  const diagnostics = metadata.diagnostics.map(readDiagnostic);
  for (const diagnostic of diagnostics) {
    text(diagnostic.message, 1024);
    if (diagnostic.filename === echo.filename) {
      offset(diagnostic.start);
      offset(diagnostic.end);
    }
  }
  if (!metadata.success) {
    if (
      diagnostics.length !== 1 || diagnostics[0].stage !== "complete" ||
      ![
        "invalid_completion",
        "invalid_position",
        "missing_source",
        "source_limit",
        "duplicate_source",
        "completion_failed",
      ].includes(diagnostics[0].code) ||
      ["replace", "context", "items", "truncated"].some((field) =>
        field in metadata
      )
    ) return fail("Invalid failed completion response");
    return { ...echo, success: false, diagnostics };
  }
  const replace = metadata.replace;
  if (!replace || typeof replace !== "object" || Array.isArray(replace)) {
    return fail("Invalid completion replacement");
  }
  const range = replace as Record<string, unknown>;
  const start = offset(range.start), end = offset(range.end);
  if (
    start > end || start > echo.position || echo.position > end ||
    typeof metadata.truncated !== "boolean" || !Array.isArray(metadata.items) ||
    metadata.items.length > 128
  ) return fail("Invalid successful completion response");
  const kinds = [
    "value",
    "function",
    "type",
    "constructor",
    "field",
    "member",
    "module",
  ];
  const matches = ["exact", "compatible", "unknown", "incompatible"];
  const items = metadata.items.map((raw): ZigProjectCompletionItem => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      return fail("Invalid completion item");
    }
    const item = raw as Record<string, unknown>;
    if (
      !kinds.includes(item.kind as string) ||
      !matches.includes(item.match as string) ||
      Object.keys(item).length !== 5 ||
      !["label", "insertText", "kind", "detail", "match"].every((key) =>
        key in item
      )
    ) return fail("Invalid completion item enum or fields");
    const label = text(item.label, 256)!;
    const insertText = text(item.insertText, 256)!;
    if (
      !label || !insertText || label.includes("\0") || insertText.includes("\0")
    ) {
      return fail("Invalid completion name");
    }
    return {
      label,
      insertText,
      kind: item.kind as ZigProjectCompletionItem["kind"],
      detail: text(item.detail, 1024, true),
      match: item.match as ZigProjectCompletionItem["match"],
    };
  });
  let context: TypedHoleDiagnostic | null = null;
  if (metadata.context !== null) {
    try {
      context = readTypedHole(metadata.context);
    } catch {
      return fail("Invalid completion context");
    }
  }
  return {
    ...echo,
    success: true,
    replace: { start, end },
    context,
    items,
    truncated: metadata.truncated,
    diagnostics,
  };
}
