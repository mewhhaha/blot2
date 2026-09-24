import { bendArray, bendList } from "./bend_list.ts";
import { CompilerError } from "./diagnostics.ts";
import {
  originLookup,
  type OriginSegment,
  SourceIdentities,
} from "./incremental_frontend.ts";
import {
  declarationOffsets,
  type SourceCompilerOptions,
} from "./source_frontend.ts";
import type { SourceProject } from "./source_project.ts";
import { createFrontend, type Cst, SourceError } from "./syntax.ts";

const identityLimit = 0xFFFF_FFFF_FFFFn;

/** Stable module/declaration identities; physical locations belong to a revision. */
export async function createProjectFrontend(
  options: SourceCompilerOptions = {},
) {
  let nextIdentity = 1n;
  const allocate = () => {
    if (nextIdentity > identityLimit) {
      throw new RangeError("Project identity space exhausted");
    }
    return nextIdentity++;
  };
  const parser = await createFrontend();
  let preludeSource = "";
  const preludeOrigins: OriginSegment[] = [];
  let prelude: Cst;
  let preludeCount: bigint;
  let preludeNames: Map<string, number>;
  try {
    preludeSource = options.prelude === "none" ? "" : await Deno.readTextFile(
      new URL("../std/prelude.blot", import.meta.url),
    );
    const parsed = parser.parse(preludeSource);
    preludeCount = parsed.nodeCount;
    preludeNames = declarationOffsets(parsed.root);
    prelude = new SourceIdentities(1n, identityLimit, allocate)
      .normalize(parsed.root, true, preludeOrigins);
  } catch (error) {
    if (error instanceof SourceError) {
      throw new SourceError(error.code, error.message, error.start, error.end, {
        filename: "std/prelude.blot",
        source: preludeSource,
      });
    }
    throw error;
  } finally {
    parser.dispose();
  }
  const preludeOrigin = originLookup(preludeOrigins);
  const modules = new Map<
    string,
    { base: bigint; identities: SourceIdentities }
  >();
  let closed = false;
  function translatePrelude(error: unknown): never {
    if (!(error instanceof CompilerError)) throw error;
    const at = error.subject.startsWith("offset:")
      ? preludeOrigin(BigInt(error.subject.slice(7)))?.offset ?? 0
      : preludeNames.get(
        error.subject.replace(/^(\$prelude\.|std\/prelude::)/, ""),
      ) ?? 0;
    throw new SourceError(error.code, error.detail, at, at, {
      filename: "std/prelude.blot",
      source: preludeSource,
    });
  }
  return {
    prelude,
    preludeCount,
    translatePrelude,
    prepare(project: SourceProject) {
      if (closed) throw new Error("Project frontend is disposed");
      const origins = project.modules.map((module) => {
        // Module names participate in nominal identities and remain relative to
        // the entry. Include the filename so changing the project root is safe.
        const key = JSON.stringify([module.filename, module.name]);
        let stored = modules.get(key);
        if (!stored) {
          const base = allocate();
          stored = {
            base,
            identities: new SourceIdentities(
              1n,
              identityLimit,
              allocate,
            ),
          };
          modules.set(key, stored);
        }
        const segments: OriginSegment[] = [];
        const body = stored.identities.normalize(module.root, false, segments);
        return {
          module,
          base: stored.base,
          body,
          originAt: originLookup(segments),
          names: declarationOffsets(module.root),
        };
      });
      const root: Cst = {
        $: "Cst",
        kind: "source_project",
        field: "",
        text: project.entry,
        offset: 0n,
        children: bendList(origins.map(({ module, base, body }) => ({
          $: "Cst" as const,
          kind: "source_module",
          field: "modules",
          text: module.name,
          offset: base,
          children: bendList([{ ...body, field: "body", offset: base }]),
        }))),
      };
      return {
        root,
        nodeCount: project.modules.reduce(
          (count, module) => count + module.nodeCount + 2n,
          preludeCount,
        ),
        declarations: origins.flatMap(({ body }) =>
          bendArray(body.children).filter((node) =>
            node.field === "declarations"
          )
        ),
        translate(error: unknown): never {
          if (!(error instanceof CompilerError)) throw error;
          if (error.subject.startsWith("offset:")) {
            const identity = BigInt(error.subject.slice(7));
            if (preludeOrigin(identity)) {
              return translatePrelude(error);
            }
            const origin = origins.find((origin) =>
              origin.base === identity ||
              origin.originAt(identity) !== undefined
            );
            if (origin) {
              const at = origin.originAt(identity)?.offset ?? 0;
              throw new SourceError(error.code, error.detail, at, at, {
                filename: origin.module.filename,
                source: origin.module.source,
              });
            }
          }
          if (/^(\$prelude\.|std\/prelude::)/.test(error.subject)) {
            return translatePrelude(error);
          }
          for (const { module, names } of origins) {
            const prefix = module.name === project.entry
              ? ""
              : `$module[${module.name}].`;
            const name = error.subject.startsWith(`${module.name}::`)
              ? error.subject.slice(module.name.length + 2)
              : error.subject.startsWith(prefix)
              ? error.subject.slice(prefix.length)
              : undefined;
            const at = name === undefined ? undefined : names.get(name);
            if (at !== undefined) {
              throw new SourceError(error.code, error.detail, at, at, {
                filename: module.filename,
                source: module.source,
              });
            }
          }
          throw error;
        },
      };
    },
    dispose() {
      closed = true;
      modules.clear();
    },
  };
}
