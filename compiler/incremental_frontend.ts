import { CompilerError } from "./diagnostics.ts";
import { bendArray, bendList } from "./bend_list.ts";
import {
  declarationOffsets,
  type SourceCompilerOptions,
} from "./source_frontend.ts";
import {
  createFrontend,
  type Cst,
  type PreparedSource,
  SourceError,
} from "./syntax.ts";

export interface IncrementalSyntaxStats {
  readonly source_reused: boolean;
  readonly islands_parsed: number;
  readonly islands_reused: number;
  readonly full_parses: number;
}

interface Origin {
  readonly offset: number;
  readonly prelude: boolean;
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
    origins: Map<bigint, Origin>,
    offsetAt = (offset: bigint) => Number(offset),
  ): Cst {
    const children = bendArray(root.children).map((declaration) => {
      const cached = this.#normalized.get(declaration);
      if (cached) {
        for (const [offset, identity] of cached.offsets) {
          origins.set(identity, { offset: offsetAt(offset), prelude });
        }
        return cached.declaration;
      }
      const value = field(declaration, "value") ?? declaration;
      const name = field(value, "name") ?? field(value, "operator");
      const owner = `${prelude}:${value.kind}:${spelling(name ?? value)}`;
      const identities = this.#owners.get(owner) ?? [];
      this.#owners.set(owner, identities);
      const offsets = new Map<bigint, bigint>();
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
          origins.set(identity, { offset: offsetAt(node.offset), prelude });
        }
        return Object.freeze({
          ...node,
          offset: identity,
          children: frozenList(bendArray(node.children).map(visit)),
        });
      };
      const normalized = visit(declaration);
      this.#normalized.set(declaration, {
        declaration: normalized,
        offsets,
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
  const closers = new Map([
    ["(", ")"],
    ["[", "]"],
    ["{", "}"],
    ["\uE001", "\uE002"],
  ]);
  const closing = new Set(closers.values());
  const pending: string[] = [];
  const ranges: IslandRange[] = [];
  let start = 0;
  let fingerprint: string[] = [];
  for (let index = 0; index < prepared.tokens.length; index++) {
    const token = prepared.tokens[index];
    fingerprint.push(
      token.type === "named" ? token.kind : token.type,
      token.text,
    );
    const closer = closers.get(token.text);
    if (closer) pending.push(closer);
    else if (closing.has(token.text) && pending.pop() !== token.text) {
      return undefined;
    }
    if (
      token.text === "\uE000" && pending.length === 0 &&
      prepared.tokens[index + 1]?.text !== "\uE001"
    ) {
      ranges.push({ start, end: index + 1, key: JSON.stringify(fingerprint) });
      start = index + 1;
      fingerprint = [];
    }
  }
  return pending.length === 0 && start === prepared.tokens.length
    ? ranges
    : undefined;
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
  const preludeOrigins = new Map<bigint, Origin>();
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
    origins: ReadonlyMap<bigint, Origin>,
    sourceOffsets: ReadonlyMap<string, number>,
    preludeOnly = false,
  ): never {
    if (!(error instanceof CompilerError)) throw error;
    const origin = error.subject.startsWith("offset:")
      ? origins.get(BigInt(error.subject.slice(7)))
      : undefined;
    const fromPrelude = preludeOnly || origin?.prelude ||
      error.subject.startsWith("$prelude.") ||
      error.subject.startsWith("std/prelude::");
    const offset = origin?.offset ??
      (fromPrelude
        ? preludeOffsets.get(
          error.subject.replace(/^(\$prelude\.|std\/prelude::)/, ""),
        )
        : sourceOffsets.get(error.subject.replace(/^main::/, ""))) ??
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
      return translate(error, preludeOrigins, preludeOffsets, true);
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
          } satisfies IncrementalSyntaxStats,
        };
      }
      const prepared = frontend.prepare(source);
      const ranges = islandRanges(prepared);
      const tokenIndexes = new Map(
        prepared.tokens.map((token, index) => [token.span.start, index]),
      );
      const offsetAt = (position: number): bigint => {
        if (prepared.tokens.length === 0) return 0n;
        const index = tokenIndexes.get(position);
        if (index === undefined) {
          throw new Error(`Baba CST offset ${position} is not a token start`);
        }
        return BigInt(index);
      };
      const next = new Map<string, ParsedIsland>();
      let pieces: { readonly parsed: ParsedIsland; readonly start: number }[] =
        [];
      let islands_parsed = 0;
      let islands_reused = 0;
      let full_parses = 0;
      let useFullParse = previous === undefined || ranges === undefined;
      if (!useFullParse) {
        try {
          for (const range of ranges!) {
            let parsed = islands.get(range.key);
            if (parsed) islands_reused++;
            else {
              parsed = frontend.parsePrepared(prepared, {
                start: prepared.tokens[range.start].span.start,
                end: prepared.tokens[range.end - 1].span.end,
                tokenStart: range.start,
                tokenEnd: range.end,
                offsetAt: (position) =>
                  offsetAt(position) - BigInt(range.start),
              });
              islands_parsed++;
            }
            // Imports must also obey the full program's import-before-value
            // order before this single-file API rejects unresolved modules.
            if (field(parsed.root, "imports")) {
              useFullParse = true;
              break;
            }
            next.set(range.key, parsed);
            pieces.push({ parsed, start: range.start });
          }
        } catch (error) {
          if (!(error instanceof SourceError)) throw error;
          // Attribute lines and malformed boundaries can be inseparable from
          // the next range. Only the complete grammar owns their diagnostics.
          useFullParse = true;
        }
      }
      if (useFullParse) {
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
        pieces = [{ parsed, start: 0 }];
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
            return { parsed: part, start: range.start };
          });
        }
      }
      const origins = new Map(preludeOrigins);
      const children: Cst[] = [];
      let nodeCount = 2n + preludeCount;
      for (const piece of pieces) {
        const normalized = identities.normalize(
          piece.parsed.root,
          false,
          origins,
          (index) => {
            const token = prepared.tokens[Number(index) + piece.start];
            return prepared.originalOffsets[token.span.start];
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
      const sourceOffsets = new Map(
        [...declarationOffsets(root)].map(([name, identity]) => [
          name,
          origins.get(BigInt(identity))!.offset,
        ]),
      );
      previous = {
        source,
        root,
        nodeCount,
        islandCount: children.length,
        translate: (error: unknown): never => {
          return translate(error, origins, sourceOffsets);
        },
      };
      // Retain one syntactically valid revision, not a growing edit history.
      islands = next;
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
        } satisfies IncrementalSyntaxStats,
      };
    },
    dispose() {
      closed = true;
      islands.clear();
      previous = undefined;
      frontend.dispose();
    },
  };
}
