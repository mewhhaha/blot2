import { CompilerError } from "./host.ts";
import {
  bendArray,
  bendList,
  type RawModule,
  result,
  structuralKey,
} from "./pipeline.ts";
import { declarationOffsets, type SourceCompilerOptions } from "./source.ts";
import { createFrontend, type Cst, SourceError } from "./syntax.ts";

interface Origin {
  readonly offset: number;
  readonly prelude: boolean;
}

function field(node: Cst, name: string): Cst | undefined {
  return bendArray(node.children).find((child) => child.field === name);
}

function spelling(node: Cst): string {
  return node.text + bendArray(node.children).map(spelling).join("");
}

// Allocation is declaration-local and retained for the session. Source byte
// offsets never become cache identities, lambda identities, or local names.
class SourceIdentities {
  #next = 1n;
  #owners = new Map<string, bigint[]>();

  normalize(root: Cst, prelude: boolean, origins: Map<bigint, Origin>): Cst {
    const children = bendArray(root.children).map((declaration) => {
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
          origins.set(identity, { offset: Number(node.offset), prelude });
        }
        return {
          ...node,
          offset: identity,
          children: bendList(bendArray(node.children).map(visit)),
        };
      };
      return visit(declaration);
    });
    return { ...root, offset: 0n, children: bendList(children) };
  }
}

interface Prelude {
  readonly module: RawModule;
  readonly scope: unknown;
}

interface SourcePlan {
  readonly prelude: RawModule;
  readonly scope: unknown;
  readonly declarations: Cst["children"];
}

export async function createSourceSession(options: SourceCompilerOptions) {
  const frontend = await createFrontend();
  const identities = new SourceIdentities();
  const preludeOrigins = new Map<bigint, Origin>();
  let preludeSource = "";
  let preludeOffsets: Map<string, number>;
  let prepared: Prelude;
  let preludeCount: bigint;
  try {
    preludeSource = options.prelude === "none" ? "" : await Deno.readTextFile(
      new URL("../std/prelude.blot", import.meta.url),
    );
    const parsed = frontend.parse(preludeSource);
    preludeOffsets = declarationOffsets(parsed.root);
    preludeCount = parsed.nodeCount;
    prepared = result<Prelude>(
      "lower.prepare_prelude",
      identities.normalize(parsed.root, true, preludeOrigins),
      preludeCount,
    );
  } catch (error) {
    frontend.dispose();
    if (error instanceof SourceError || error instanceof CompilerError) {
      const offset = error instanceof SourceError
        ? error.start
        : preludeOrigins.get(BigInt(
          error.subject.startsWith("offset:") ? error.subject.slice(7) : "0",
        ))?.offset ?? 0;
      throw new SourceError(
        error.code,
        error instanceof CompilerError ? error.detail : error.message,
        offset,
        offset,
        { filename: "std/prelude.blot", source: preludeSource },
      );
    }
    throw error;
  }
  let lowered = new Map<string, RawModule>();
  let previousScope: string | undefined;
  return {
    prepare(source: string) {
      const start = performance.now();
      const parsed = frontend.parse(source);
      const parsed_ms = performance.now() - start;
      const origins = new Map(preludeOrigins);
      const sourceOffsets = declarationOffsets(parsed.root);
      const root = identities.normalize(parsed.root, false, origins);
      const translate = (error: unknown): never => {
        if (!(error instanceof CompilerError)) throw error;
        const origin = error.subject.startsWith("offset:")
          ? origins.get(BigInt(error.subject.slice(7)))
          : undefined;
        const fromPrelude = origin?.prelude ||
          error.subject.startsWith("$prelude.") ||
          error.subject.startsWith("std/prelude::");
        const offset = origin?.offset ?? (fromPrelude
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
      };
      try {
        const lowerStart = performance.now();
        const plan = result<SourcePlan>("lower.prepare_source", root, prepared);
        const scopeKey = structuralKey(plan.scope);
        const reusable = scopeKey === previousScope
          ? lowered
          : new Map<string, RawModule>();
        const next = new Map<string, RawModule>();
        let declarations_lowered = 0;
        let declarations_reused = 0;
        const fragments = [plan.prelude];
        for (const declaration of bendArray(plan.declarations)) {
          const key = structuralKey(declaration);
          let fragment = reusable.get(key);
          if (fragment) {
            declarations_reused++;
          } else {
            fragment = result<RawModule>(
              "lower.lower_source_declaration",
              declaration,
              plan.scope,
              parsed.nodeCount + preludeCount,
            );
            declarations_lowered++;
          }
          next.set(key, fragment);
          fragments.push(fragment);
        }
        const module: RawModule = {
          $: "Module",
          constants: bendList(fragments.flatMap((m) => bendArray(m.constants))),
          functions: bendList(fragments.flatMap((m) => bendArray(m.functions))),
          descriptors: bendList(
            fragments.flatMap((m) => bendArray(m.descriptors)),
          ),
          data_types: bendList(
            fragments.flatMap((m) => bendArray(m.data_types)),
          ),
        };
        lowered = next;
        previousScope = scopeKey;
        return {
          module,
          translate,
          stats: {
            parsed_ms,
            lowered_ms: performance.now() - lowerStart,
            declarations_lowered,
            declarations_reused,
          },
        };
      } catch (error) {
        return translate(error);
      }
    },
    dispose() {
      frontend.dispose();
      lowered.clear();
    },
  };
}
