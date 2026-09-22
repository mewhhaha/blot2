import { CompilerError } from "./diagnostics.ts";
import { bendArray, bendList } from "./bend_list.ts";
import { sourceDeclarationRanges } from "./source_ranges.ts";
import {
  declarationOffsets,
  type SourceCompilerOptions,
} from "./source_frontend.ts";
import {
  createFrontend,
  type Cst,
  declarationRanges,
  type PreparedSource,
  SourceError,
} from "./syntax.ts";

export interface IncrementalSyntaxStats {
  readonly source_reused: boolean;
  readonly islands_parsed: number;
  readonly islands_reused: number;
  readonly full_parses: number;
  readonly characters_lexed: number;
  readonly characters_reused: number;
}

interface OriginSegment {
  readonly offsets: ReadonlyMap<bigint, bigint>;
  readonly offsetAt: (offset: bigint) => number;
  readonly prelude: boolean;
}

interface Origin {
  readonly offset: number;
  readonly prelude: boolean;
}

function originLookup(segments: readonly OriginSegment[]) {
  const count = segments.reduce(
    (count, segment) => count + segment.offsets.size,
    0,
  );
  // Small eager indexes have better short-session latency. Avoid rebuilding
  // large per-node maps, where successful edits pay for unused diagnostics.
  if (count >= 8192) {
    return (identity: bigint) => sourceOrigin(segments, identity);
  }
  const indexed = new Map<bigint, Origin>();
  for (const segment of segments) {
    for (const [identity, offset] of segment.offsets) {
      indexed.set(identity, {
        offset: segment.offsetAt(offset),
        prelude: segment.prelude,
      });
    }
  }
  return (identity: bigint) => indexed.get(identity);
}

function sourceOrigin(segments: readonly OriginSegment[], identity: bigint) {
  // Duplicate declaration identities historically use the last source origin.
  for (let index = segments.length - 1; index >= 0; index--) {
    const segment = segments[index];
    const offset = segment.offsets.get(identity);
    if (offset !== undefined) {
      return { offset: segment.offsetAt(offset), prelude: segment.prelude };
    }
  }
}

function field(node: Cst, name: string): Cst | undefined {
  for (let cursor = node.children; cursor.$ === "Con"; cursor = cursor.tail) {
    if (cursor.head.field === name) return cursor.head;
  }
}

function spelling(node: Cst): string {
  const parts: string[] = [];
  const pending = [node];
  for (let next = pending.pop(); next; next = pending.pop()) {
    parts.push(next.text);
    const children = bendArray(next.children);
    for (let index = children.length - 1; index >= 0; index--) {
      pending.push(children[index]);
    }
  }
  return parts.join("");
}

function frozenList(children: readonly Cst[]): Cst["children"] {
  let list: Cst["children"] = Object.freeze({ $: "Nil" });
  for (let index = children.length - 1; index >= 0; index--) {
    list = Object.freeze({ $: "Con", head: children[index], tail: list });
  }
  return list;
}

// Declaration-local identities survive unrelated edits. Offsets remain in the
// origin map, not in cache keys, lambda identities, or resolved local names.
class SourceIdentities {
  #next = 1n;
  #owners = new Map<string, bigint[]>();
  #normalized = new WeakMap<Cst, {
    readonly declaration: Cst;
    readonly offsets: ReadonlyMap<bigint, bigint>;
  }>();

  normalize(
    root: Cst,
    prelude: boolean,
    origins: OriginSegment[],
    offsetAt = (offset: bigint) => Number(offset),
  ): Cst {
    const children = bendArray(root.children).map((declaration) => {
      const cached = this.#normalized.get(declaration);
      if (cached) {
        origins.push({ offsets: cached.offsets, offsetAt, prelude });
        return cached.declaration;
      }
      const value = field(declaration, "value") ?? declaration;
      const name = field(value, "name") ?? field(value, "operator");
      const owner = `${prelude}:${value.kind}:${spelling(name ?? value)}`;
      const identities = this.#owners.get(owner) ?? [];
      this.#owners.set(owner, identities);
      const offsets = new Map<bigint, bigint>();
      const sourceOffsets = new Map<bigint, bigint>();
      const visit = (node: Cst): Cst => {
        let identity = offsets.get(node.offset);
        if (identity === undefined) {
          const index = offsets.size;
          identity = identities[index] ??= this.#next++;
          if (identity > 0xFFFF_FFFF_FFFFn) {
            throw new RangeError(
              "Source identity space exhausted; restart session",
            );
          }
          offsets.set(node.offset, identity);
          sourceOffsets.set(identity, node.offset);
        }
        return Object.freeze({
          ...node,
          offset: identity,
          children: frozenList(bendArray(node.children).map(visit)),
        });
      };
      const normalized = visit(declaration);
      origins.push({ offsets: sourceOffsets, offsetAt, prelude });
      this.#normalized.set(declaration, {
        declaration: normalized,
        offsets: sourceOffsets,
      });
      return normalized;
    });
    return Object.freeze({
      ...root,
      offset: 0n,
      children: frozenList(children),
    });
  }
}

interface IslandRange {
  readonly start: number;
  readonly end: number;
  readonly key: string;
}

type ParsedIsland = ReturnType<
  Awaited<ReturnType<typeof createFrontend>>[
    "parse"
  ]
>;

// These are layout/delimiter boundaries, not a second grammar. Each island is
// still accepted by Baba as a complete program; ambiguous splits use a full
// parse. In particular, NEWLINE before INDENT starts a suite, not a declaration.
function islandRanges(prepared: PreparedSource): IslandRange[] | undefined {
  return declarationRanges(prepared)?.map(({ start, end }) => {
    const fingerprint: string[] = [];
    for (let index = start; index < end; index++) {
      const token = prepared.tokens[index];
      fingerprint.push(
        token.type === "named" ? token.kind : token.type,
        token.text,
      );
    }
    return { start, end, key: JSON.stringify(fingerprint) };
  });
}

function relativeTree(node: Cst, start: number): Cst {
  return {
    ...node,
    offset: node.offset - BigInt(start),
    children: bendList(
      bendArray(node.children).map((child) => relativeTree(child, start)),
    ),
  };
}

function treeCount(root: Cst): bigint {
  let count = 1n;
  const pending = [root];
  for (let node = pending.pop(); node; node = pending.pop()) {
    count++;
    for (let list = node.children; list.$ === "Con"; list = list.tail) {
      pending.push(list.head);
    }
  }
  return count;
}

export async function createIncrementalFrontend(
  options: SourceCompilerOptions = {},
) {
  const frontend = await createFrontend();
  const identities = new SourceIdentities();
  const preludeOrigins: OriginSegment[] = [];
  let preludeSource = "";
  let prelude: Cst;
  let preludeCount: bigint;
  let preludeOffsets: Map<string, number>;
  try {
    preludeSource = options.prelude === "none" ? "" : await Deno.readTextFile(
      new URL("../std/prelude.blot", import.meta.url),
    );
    const parsed = frontend.parse(preludeSource);
    preludeOffsets = declarationOffsets(parsed.root);
    preludeCount = parsed.nodeCount;
    prelude = identities.normalize(parsed.root, true, preludeOrigins);
  } catch (error) {
    frontend.dispose();
    if (error instanceof SourceError) {
      throw new SourceError(error.code, error.message, error.start, error.end, {
        filename: "std/prelude.blot",
        source: preludeSource,
      });
    }
    throw error;
  }

  function translate(
    error: unknown,
    originAt: (identity: bigint) => Origin | undefined,
    sourceOffsetAt: (name: string) => number | undefined,
    preludeOnly = false,
  ): never {
    if (!(error instanceof CompilerError)) throw error;
    const origin = error.subject.startsWith("offset:")
      ? originAt(BigInt(error.subject.slice(7)))
      : undefined;
    const fromPrelude = preludeOnly || origin?.prelude ||
      error.subject.startsWith("$prelude.") ||
      error.subject.startsWith("std/prelude::");
    const offset = origin?.offset ??
      (fromPrelude
        ? preludeOffsets.get(
          error.subject.replace(/^(\$prelude\.|std\/prelude::)/, ""),
        )
        : sourceOffsetAt(error.subject.replace(/^main::/, ""))) ??
      0;
    throw new SourceError(
      error.code,
      error.detail,
      offset,
      offset,
      fromPrelude
        ? { filename: "std/prelude.blot", source: preludeSource }
        : undefined,
    );
  }

  let islands = new Map<string, ParsedIsland>();
  function lex(source: string) {
    const prepared = frontend.prepare(source);
    let indexes: Map<number, number> | undefined;
    return {
      prepared,
      ranges: islandRanges(prepared),
      tokenIndex(position: number): bigint {
        if (prepared.tokens.length === 0) return 0n;
        indexes ??= new Map(
          prepared.tokens.map((token, index) => [token.span.start, index]),
        );
        const index = indexes.get(position);
        if (index === undefined) {
          throw new Error(`Baba CST offset ${position} is not a token start`);
        }
        return BigInt(index);
      },
    };
  }
  type LexedSource = ReturnType<typeof lex>;
  let lexedSources = new Map<string, LexedSource>();
  let closed = false;
  let previous: {
    readonly source: string;
    readonly root: Cst;
    readonly nodeCount: bigint;
    readonly islandCount: number;
    readonly translate: (error: unknown) => never;
  } | undefined;

  return {
    prelude,
    preludeCount,
    translatePrelude(error: unknown): never {
      return translate(
        error,
        originLookup(preludeOrigins),
        () => undefined,
        true,
      );
    },
    prepare(source: string) {
      if (closed) throw new Error("Incremental frontend is disposed");
      const start = performance.now();
      if (previous?.source === source) {
        return {
          root: previous.root,
          nodeCount: previous.nodeCount,
          translate: previous.translate,
          parsed_ms: performance.now() - start,
          syntax: {
            source_reused: true,
            islands_parsed: 0,
            islands_reused: previous.islandCount,
            full_parses: 0,
            characters_lexed: 0,
            characters_reused: source.length,
          } satisfies IncrementalSyntaxStats,
        };
      }
      const next = new Map<string, ParsedIsland>();
      const nextLexed = new Map<string, LexedSource>();
      let pieces: {
        readonly parsed: ParsedIsland;
        readonly prepared: PreparedSource;
        readonly start: number;
        readonly base: number;
      }[] = [];
      let islands_parsed = 0;
      let islands_reused = 0;
      let full_parses = 0;
      let characters_lexed = 0;
      let characters_reused = 0;
      const sourceRanges = previous
        ? sourceDeclarationRanges(source)
        : undefined;
      let useFullParse = sourceRanges === undefined;
      if (!useFullParse) {
        try {
          fragments: for (const fragment of sourceRanges!) {
            const text = source.slice(fragment.start, fragment.end);
            let lexed = lexedSources.get(text);
            if (lexed) characters_reused += text.length;
            else {
              characters_lexed += text.length;
              lexed = lex(text);
            }
            nextLexed.set(text, lexed);
            const { prepared, ranges } = lexed;
            if (!ranges) {
              useFullParse = true;
              break;
            }
            for (const range of ranges) {
              let parsed = islands.get(range.key);
              if (parsed) islands_reused++;
              else {
                parsed = frontend.parsePrepared(prepared, {
                  start: prepared.tokens[range.start].span.start,
                  end: prepared.tokens[range.end - 1].span.end,
                  tokenStart: range.start,
                  tokenEnd: range.end,
                  offsetAt: (position) =>
                    lexed.tokenIndex(position) - BigInt(range.start),
                });
                islands_parsed++;
              }
              // Imports must also obey the full program's import-before-value
              // order before this single-file API rejects unresolved modules.
              if (field(parsed.root, "imports")) {
                useFullParse = true;
                break fragments;
              }
              next.set(range.key, parsed);
              pieces.push({
                parsed,
                prepared,
                start: range.start,
                base: fragment.start,
              });
            }
          }
        } catch (error) {
          if (!(error instanceof SourceError)) throw error;
          // Attribute lines and malformed boundaries can be inseparable from
          // the next range. Only the complete grammar owns their diagnostics.
          useFullParse = true;
        }
      }
      if (useFullParse) {
        characters_lexed += source.length;
        const lexed = lex(source);
        const { prepared, ranges } = lexed;
        const offsetAt = lexed.tokenIndex;
        const parsed = frontend.parsePrepared(prepared, { offsetAt });
        const unresolved = field(parsed.root, "imports");
        if (unresolved) {
          const token = prepared.tokens[Number(unresolved.offset)];
          throw new SourceError(
            "module_loader_required",
            "compile a source project to resolve file imports",
            prepared.originalOffsets[token.span.start],
          );
        }
        const declarations = bendArray(parsed.root.children);
        full_parses = 1;
        islands_parsed = declarations.length;
        islands_reused = 0;
        pieces = [{ parsed, prepared, start: 0, base: 0 }];
        next.clear();
        if (
          ranges?.length === declarations.length &&
          ranges.every((range, index) =>
            declarations[index].offset === BigInt(range.start)
          )
        ) {
          pieces = ranges.map((range, index) => {
            const root = {
              ...parsed.root,
              offset: 0n,
              children: bendList([
                relativeTree(declarations[index], range.start),
              ]),
            };
            const part = { root, nodeCount: treeCount(root) };
            next.set(range.key, part);
            return { parsed: part, prepared, start: range.start, base: 0 };
          });
        }
      }
      const origins = [...preludeOrigins];
      const children: Cst[] = [];
      let nodeCount = 2n + preludeCount;
      for (const piece of pieces) {
        const normalized = identities.normalize(
          piece.parsed.root,
          false,
          origins,
          (index) => {
            const token = piece.prepared.tokens[Number(index) + piece.start];
            return piece.base +
              piece.prepared.originalOffsets[token.span.start];
          },
        );
        children.push(...bendArray(normalized.children));
        nodeCount += piece.parsed.nodeCount - 2n;
      }
      const root: Cst = Object.freeze({
        $: "Cst",
        kind: "program",
        field: "",
        text: "",
        offset: 0n,
        children: frozenList(children),
      });
      let declarationIdentities: ReadonlyMap<string, number> | undefined;
      const originAt = originLookup(origins);
      const sourceOffsetAt = (name: string) => {
        declarationIdentities ??= declarationOffsets(root);
        const identity = declarationIdentities.get(name);
        if (identity === undefined) return undefined;
        const origin = originAt(BigInt(identity));
        if (!origin) throw new Error(`Missing source origin for ${name}`);
        return origin.offset;
      };
      previous = {
        source,
        root,
        nodeCount,
        islandCount: children.length,
        translate: (error: unknown): never => {
          return translate(error, originAt, sourceOffsetAt);
        },
      };
      // Retain one syntactically valid revision, not a growing edit history.
      islands = next;
      lexedSources = nextLexed;
      return {
        root,
        nodeCount,
        translate: previous.translate,
        parsed_ms: performance.now() - start,
        syntax: {
          source_reused: false,
          islands_parsed,
          islands_reused,
          full_parses,
          characters_lexed,
          characters_reused,
        } satisfies IncrementalSyntaxStats,
      };
    },
    dispose() {
      closed = true;
      islands.clear();
      lexedSources.clear();
      previous = undefined;
      frontend.dispose();
    },
  };
}
