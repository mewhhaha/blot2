/** Blot's Zig project compiler and WebAssembly guest API. */
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { captureAssetImports } from "./compiler/assets.ts";
import {
  createZigProjectCompiler,
  type ZigProjectCompiler,
  type ZigProjectCompilerOptions,
} from "./compiler/zig_project_client.ts";
export type {
  DiagnosticRequirement,
  DiagnosticRequirementKind,
  DiagnosticSpan,
  DiagnosticType,
  DiagnosticTypeKind,
  TypedHoleDiagnostic,
} from "./compiler/type_diagnostics.ts";
import {
  extractNativeCompiler,
  extractStandardLibrary,
} from "./compiler/packaged_native.ts";

export { createZigProjectCompiler } from "./compiler/zig_project_client.ts";
export { jsonAssetParser } from "./compiler/assets.ts";
export type {
  AssetBuildStats,
  AssetContext,
  AssetDependency,
  AssetImport,
  AssetImports,
  AssetModule,
  AssetParser,
  AssetRecordType,
  AssetReference,
  AssetType,
  CompiledAsset,
} from "./compiler/assets.ts";
export type {
  ZigProjectBuildOptions,
  ZigProjectBuildResult,
  ZigProjectBuildStats,
  ZigProjectCompiler,
  ZigProjectCompilerOptions,
  ZigProjectDiagnostic,
} from "./compiler/zig_project_client.ts";
export {
  GuestError,
  instantiateGuest,
  readGuestAbi,
} from "./compiler/guest.ts";
export type {
  AsyncHostCallback,
  Guest,
  GuestAbi,
  HostCallback,
} from "./compiler/guest.ts";

export const blotStdRoot: URL = new URL("./std/", import.meta.url);
/** Include this payload when bundling the host into a desktop executable. */
export const blotCompilerBinary: URL = new URL(
  "./generated/compiler/blotc.gz",
  import.meta.url,
);
export type CompilerOptions = Omit<ZigProjectCompilerOptions, "executable"> & {
  executable?: string | URL;
};

/** Keep this compiler open across builds to reuse unchanged project work.
 * The packaged compiler and prelude are defaults; null disables the prelude. */
export async function createCompiler(
  options: CompilerOptions,
): Promise<ZigProjectCompiler> {
  const path = (value: string | URL): string =>
    resolve(value instanceof URL ? fileURLToPath(value) : value);
  if (options.checkpoint !== undefined) {
    if (!(options.checkpoint instanceof Uint8Array)) {
      throw new TypeError(
        "checkpoint must contain bytes from exportCheckpoint",
      );
    }
    if (
      options.checkpoint.length === 0 ||
      options.checkpoint.length > 63 * 1024 * 1024 - 8
    ) {
      throw new RangeError("Checkpoint payload exceeds protocol limits");
    }
  }
  // Capture paths before extracting the package or starting the child process.
  const captured = {
    ...options,
    assets: captureAssetImports(options.assets),
    checkpoint: options.checkpoint && new Uint8Array(options.checkpoint),
    entry: path(options.entry),
    prelude: options.prelude === null
      ? null
      : path(options.prelude ?? new URL("prelude.blot", blotStdRoot)),
    stdRoot: options.stdRoot === null
      ? null
      : path(options.stdRoot ?? blotStdRoot),
    dependencies: options.dependencies == null
      ? options.dependencies
      : path(options.dependencies),
    imports: options.imports &&
      Object.fromEntries(
        Object.entries(options.imports).map((
          [name, value],
        ) => [name, path(value)]),
      ),
    executable: options.executable === undefined
      ? undefined
      : path(options.executable),
  };
  const defaultPrelude = options.prelude === undefined;
  const defaultRoot = options.stdRoot === undefined;
  const embeddedLibrary = Deno.build.standalone &&
    (defaultPrelude || defaultRoot);
  if (captured.executable !== undefined && !embeddedLibrary) {
    return createZigProjectCompiler({
      ...captured,
      executable: captured.executable,
    });
  }
  let native: Awaited<ReturnType<typeof extractNativeCompiler>> | undefined;
  let library: Awaited<ReturnType<typeof extractStandardLibrary>> | undefined;
  let cleanup: Promise<void> | undefined;
  const remove = () =>
    cleanup ??= (async () => {
      try {
        await native?.dispose();
      } finally {
        await library?.dispose();
      }
    })();
  try {
    if (embeddedLibrary) {
      library = await extractStandardLibrary();
      if (defaultPrelude) {
        captured.prelude = resolve(library.path, "prelude.blot");
      }
      if (defaultRoot) captured.stdRoot = library.path;
    }
    if (captured.executable === undefined) {
      native = await extractNativeCompiler();
      captured.executable = native.path;
    }
    const compiler = await createZigProjectCompiler({
      ...captured,
      executable: captured.executable,
    });
    return {
      get pid() {
        return compiler.pid;
      },
      get compilerIdentity() {
        return compiler.compilerIdentity;
      },
      build: (buildOptions) => compiler.build(buildOptions),
      exportCheckpoint: () => compiler.exportCheckpoint(),
      async close() {
        try {
          await compiler.close();
        } finally {
          await remove();
        }
      },
      async dispose() {
        try {
          await compiler.dispose();
        } finally {
          await remove();
        }
      },
    };
  } catch (error) {
    await remove();
    throw error;
  }
}
