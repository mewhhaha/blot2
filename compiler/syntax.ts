import {
  type CompactFrontendProgram,
  CpuFrontend,
} from "@mewhhaha/baba/runtime/webgpu";
import {
  createParser,
  type ParserInstance,
  type Token,
} from "../generated/wasm/mod.ts";
import schema from "../generated/wasm/cst-schema.json" with { type: "json" };

export type CstList = { readonly $: "Nil" } | {
  readonly $: "Con";
  readonly head: Cst;
  readonly tail: CstList;
};
export interface Cst {
  readonly $: "Cst";
  readonly kind: string;
  readonly field: string;
  readonly text: string;
  readonly offset: bigint;
  readonly children: CstList;
}

export interface PreparedSource {
  readonly source: string;
  readonly originalOffsets: readonly number[];
  readonly tokens: readonly Token[];
}

export class SourceError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly start: number,
    readonly end = start,
    readonly origin?: { readonly filename: string; readonly source: string },
  ) {
    super(message);
    this.name = "SourceError";
  }
}

const newline = "\uE000";
const indent = "\uE001";
const dedent = "\uE002";

export function layout(source: string, lexer: ParserInstance) {
  const reserved = source.search(/[\uE000-\uE002]/);
  if (reserved !== -1) {
    throw new SourceError(
      "reserved_layout",
      "Private layout markers cannot appear in source",
      reserved,
      reserved + 1,
    );
  }
  const lexed = lexer.lex(source, { preserveTrivia: true });
  const diagnostic = lexed.diagnostics[0];
  if (diagnostic) {
    throw new SourceError(
      diagnostic.code,
      diagnostic.message,
      diagnostic.span.start,
      diagnostic.span.end,
    );
  }
  const tokens: Token[] = [];
  for (let index = 0; index < lexed.tokenTape.length; index++) {
    const token = lexed.tokenTape.token(index);
    if (!token) throw new Error(`Baba omitted token ${index}`);
    if (token.channel === "main" && token.type !== "eof") tokens.push(token);
  }
  const insertions = new Map<number, string>();
  const frames = [{ indent: 0, depth: 0 }];
  let depth = 0;
  // Searching backward for an absent CR on every LF line is quadratic.
  // Index both terminators once, including mixed-ending sources.
  const lineStarts = [0];
  for (let position = 0; position < source.length; position++) {
    const code = source.charCodeAt(position);
    if (code === 10 || code === 13) lineStarts.push(position + 1);
  }
  const lineIndent = (token: Token) => {
    let low = 0;
    let high = lineStarts.length;
    while (low + 1 < high) {
      const middle = Math.floor((low + high) / 2);
      if (lineStarts[middle] <= token.span.start) low = middle;
      else high = middle;
    }
    const lineStart = lineStarts[low];
    const leading =
      /^[ \t]*/.exec(source.slice(lineStart, token.span.start))![0];
    if (leading.includes("\t")) {
      throw new SourceError(
        "layout_tab",
        "Use spaces for indentation",
        lineStart,
        token.span.start,
      );
    }
    return leading.length;
  };
  if (tokens.length && lineIndent(tokens[0]) !== 0) {
    throw new SourceError(
      "layout_indent",
      "Top-level declarations must start at column 1",
      tokens[0].span.start,
    );
  }
  for (let index = 0; index < tokens.length; index++) {
    const token = tokens[index];
    const previous = tokens[index - 1];
    const brokenLine = previous &&
      /[\r\n]/.test(source.slice(previous.span.end, token.span.start));
    if (
      [")", "]", "}"].includes(token.text) && frames.length > 1 &&
      frames.at(-1)!.depth === depth
    ) {
      let markers = newline;
      while (frames.length > 1 && frames.at(-1)!.depth === depth) {
        frames.pop();
        markers += dedent;
        if (frames.length > 1 && frames.at(-1)!.depth === depth) {
          markers += newline;
        }
      }
      insertions.set(token.span.start, markers);
    } else if (brokenLine) {
      const frame = frames.at(-1)!;
      const suite = previous.text === ":" || previous.text === "of";
      if (suite || depth === frame.depth) {
        const width = lineIndent(token);
        if (suite) {
          if (width <= lineIndent(previous)) {
            throw new SourceError(
              "layout_suite",
              `Expected an indented suite after '${previous.text}'`,
              token.span.start,
            );
          }
          insertions.set(token.span.start, newline + indent);
          frames.push({ indent: width, depth });
        } else if (width > frame.indent) {
          if (!["=>", "=", "<-"].includes(previous.text)) {
            throw new SourceError(
              "layout_indent",
              "Unexpected indentation; use parentheses for continued expressions",
              token.span.start,
            );
          }
        } else {
          let markers = newline;
          while (width < frames.at(-1)!.indent) {
            frames.pop();
            markers += dedent + newline;
          }
          if (width !== frames.at(-1)!.indent) {
            throw new SourceError(
              "layout_dedent",
              "Dedent must match an enclosing indentation level",
              token.span.start,
            );
          }
          insertions.set(token.span.start, markers);
        }
      }
    }
    if (["(", "[", "{"].includes(token.text)) depth++;
    if ([")", "]", "}"].includes(token.text)) depth--;
  }
  // End a trailing line comment before inserting the synthetic final newline.
  if (tokens.length) {
    insertions.set(
      source.length,
      "\n" + newline + (dedent + newline).repeat(frames.length - 1),
    );
  }
  const originalOffsets: number[] = [];
  const parts: string[] = [];
  let previousOffset = 0;
  for (const [offset, markers] of insertions) {
    parts.push(source.slice(previousOffset, offset), markers);
    for (let position = previousOffset; position < offset; position++) {
      originalOffsets.push(position);
    }
    for (let position = 0; position < markers.length; position++) {
      originalOffsets.push(offset);
    }
    previousOffset = offset;
  }
  parts.push(source.slice(previousOffset));
  for (let position = previousOffset; position <= source.length; position++) {
    originalOffsets.push(position);
  }
  return { source: parts.join(""), originalOffsets };
}

function materialize(
  frontend: CpuFrontend,
  program: CompactFrontendProgram,
  source: string,
  offsetAt: (position: number) => bigint,
) {
  const ruleNames = new Map(
    frontend.plan.islands.map((island) => [island.ruleId, island.ruleName]),
  );
  let count = 0;
  function node(id: number, field: string): Cst {
    count++;
    const base = id * 8;
    const kind = ruleNames.get(program.nodes[base]);
    if (!kind) throw new Error(`Unknown Baba rule ${program.nodes[base]}`);
    const start = program.nodes[base + 2];
    const edgeStart = program.nodes[base + 4];
    const edgeCount = program.nodes[base + 5];
    let children: CstList = { $: "Nil" };
    for (let index = edgeCount - 1; index >= 0; index--) {
      const edge = (edgeStart + index) * 4;
      const fieldId = program.edges[edge];
      const label = fieldId < 0 ? "" : schema.fields[fieldId];
      if (label === undefined) throw new Error(`Unknown Baba field ${fieldId}`);
      const category = program.edges[edge + 2];
      const target = program.edges[edge + 3];
      let child: Cst;
      if (category === 1) child = node(target, label);
      else if (category === 0) {
        count++;
        const token = target * 4;
        const from = program.tokens[token + 1];
        const to = program.tokens[token + 2];
        const identity = program.tokens[token + 3];
        const text = source.slice(from, to);
        child = {
          $: "Cst",
          kind: schema.tokens[identity] ?? text,
          text,
          field: label,
          offset: offsetAt(from),
          children: { $: "Nil" },
        };
      } else throw new Error(`Unknown Baba edge category ${category}`);
      children = { $: "Con", head: child, tail: children };
    }
    return {
      $: "Cst",
      kind,
      field,
      text: "",
      offset: offsetAt(start),
      children,
    };
  }
  const root = node(0, "");
  return { root, nodeCount: BigInt(count + 1) };
}

export async function createFrontend() {
  const [bytes, plan] = await Promise.all([
    Deno.readFile(new URL("../generated/wasm/parser.wasm", import.meta.url)),
    Deno.readFile(new URL("../generated/wasm/parser.plan", import.meta.url)),
  ]);
  const lexer = createParser({ bytes, plan });
  const parser = CpuFrontend.create(plan);
  function prepare(source: string): PreparedSource {
    const prepared = layout(source, lexer);
    const lexed = lexer.lex(prepared.source);
    const tokens: Token[] = [];
    for (let index = 0; index < lexed.tokenTape.length; index++) {
      const token = lexed.tokenTape.token(index)!;
      if (token.channel === "main" && token.type !== "eof") tokens.push(token);
    }
    return { ...prepared, tokens };
  }
  function parsePrepared(
    prepared: PreparedSource,
    options: {
      readonly start?: number;
      readonly end?: number;
      readonly tokenStart?: number;
      readonly tokenEnd?: number;
      readonly offsetAt?: (position: number) => bigint;
    } = {},
  ) {
    const start = options.start ?? 0;
    const end = options.end ?? prepared.source.length;
    const source = prepared.source.slice(start, end);
    // The compact runtime applies a signed-I32 policy to INTEGER tokens.
    // Replace only Baba-identified integers for parsing, retaining all source
    // text/spans for Bend's U32 interpretation and overflow diagnostics.
    const neutral = source.split("");
    for (
      let index = options.tokenStart ?? 0;
      index < (options.tokenEnd ?? prepared.tokens.length);
      index++
    ) {
      const token = prepared.tokens[index];
      if (token.type === "named" && token.kind === "INTEGER") {
        neutral.fill("0", token.span.start - start, token.span.end - start);
      }
    }
    const parsed = parser.ingest(neutral.join(""));
    if (!parsed.ok) {
      const diagnostic = parsed.diagnostics[0];
      if (!diagnostic) throw new Error("Baba failed without a diagnostic");
      const last = prepared.originalOffsets.at(-1)!;
      throw new SourceError(
        diagnostic.code,
        diagnostic.message,
        prepared.originalOffsets[start + diagnostic.start] ?? last,
        prepared.originalOffsets[start + diagnostic.end] ?? last,
      );
    }
    const offsetAt = options.offsetAt ??
      ((position: number) => BigInt(prepared.originalOffsets[position]));
    return materialize(
      parser,
      parsed.program,
      source,
      (position) => offsetAt(start + position),
    );
  }
  return {
    prepare,
    parsePrepared,
    parse(source: string) {
      return parsePrepared(prepare(source));
    },
    dispose() {
      lexer.dispose();
    },
  };
}
