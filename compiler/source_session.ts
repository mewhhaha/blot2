import {
  bendArray,
  bendList,
  invoke,
  type RawModule,
  result,
  structuralKey,
} from "./pipeline.ts";
import type { SourceCompilerOptions } from "./source_frontend.ts";
import type { Cst } from "./syntax.ts";
import { createIncrementalFrontend } from "./incremental_frontend.ts";
import { toBendCst } from "./bend_abi.ts";

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
  const frontend = await createIncrementalFrontend(options);
  let prepared: Prelude;
  try {
    prepared = result<Prelude>(
      "lower.prepare_prelude",
      toBendCst(frontend.prelude),
      frontend.preludeCount,
    );
  } catch (error) {
    frontend.dispose();
    return frontend.translatePrelude(error);
  }
  let lowered = new Map<string, RawModule>();
  let previousScope: string | undefined;
  return {
    prepare(source: string) {
      const parsed = frontend.prepare(source);
      try {
        const lowerStart = performance.now();
        const plan = result<SourcePlan>(
          "lower.prepare_source",
          toBendCst(parsed.root),
          prepared,
        );
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
              parsed.nodeCount,
            );
            declarations_lowered++;
          }
          next.set(key, fragment);
          fragments.push(fragment);
        }
        const module: RawModule = {
          $: "model.Module",
          constants: bendList(fragments.flatMap((m) => bendArray(m.constants))),
          functions: bendList(fragments.flatMap((m) => bendArray(m.functions))),
          operations: bendList(
            fragments.flatMap((m) => bendArray(m.operations)),
          ),
          data_types: bendList(
            fragments.flatMap((m) => bendArray(m.data_types)),
          ),
        };
        lowered = next;
        previousScope = scopeKey;
        const preparedModule = result<RawModule>(
          "effect_families.prepare",
          module,
        );
        return {
          module: result<RawModule>(
            "dispatch_resolution.prepare",
            preparedModule,
            "main",
            module.operations,
          ),
          // Export selection narrows the flags; entries are verified against
          // the final checked module.
          entries: invoke<unknown>("entry_points.entries", module),
          translate: parsed.translate,
          stats: {
            parsed_ms: parsed.parsed_ms,
            lowered_ms: performance.now() - lowerStart,
            declarations_lowered,
            declarations_reused,
          },
        };
      } catch (error) {
        return parsed.translate(error);
      }
    },
    dispose() {
      frontend.dispose();
      lowered.clear();
    },
  };
}
