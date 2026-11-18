import { resolve } from "node:path";
import type { ZigProjectCompilerOptions } from "../../host/zig_project_client.ts";

/** Read the same aliases, generated assets and budgets used by Pen. */
export async function gdevProject(
  root: string,
  stdRoot: string,
  entry: string,
  executable?: string,
): Promise<
  ZigProjectCompilerOptions & {
    executable: string;
    entry: string;
    prelude: string;
  }
> {
  const project = JSON.parse(
    await Deno.readTextFile(resolve(root, "pen.json")),
  );
  const settings = project.compiler.settings;
  return {
    executable: resolve(
      executable ??
        resolve(root, project.plugins[project.compiler.plugin].run.blotc),
    ),
    entry: resolve(root, entry),
    stdRoot,
    prelude: resolve(stdRoot, "prelude.blot"),
    imports: Object.fromEntries(
      Object.entries(settings.imports).map((
        [name, path],
      ) => [name, resolve(root, path as string)]),
    ),
    nativeAssets: {
      roots: settings.nativeAssets.roots.map((path: string) =>
        resolve(root, path)
      ),
      imports: settings.nativeAssets.imports.map((
        item: Record<string, string>,
      ) => ({
        ...item,
        module: resolve(root, item.module),
        path: resolve(root, item.path),
      })),
    },
    inferenceBudget: settings.inferenceBudget,
    storage: settings.storage,
  };
}
