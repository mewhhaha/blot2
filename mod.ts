/** Blot's Zig project compiler and WebAssembly guest API. */
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { captureNativeAssets } from "./host/native_assets.ts";
import { captureAssetImports } from "./host/assets.ts";
import {
  createZigProjectCompiler,
  type ZigProjectCompiler,
  type ZigProjectCompilerOptions,
} from "./host/zig_project_client.ts";
export type {
  DiagnosticRequirement,
  DiagnosticRequirementKind,
  DiagnosticSpan,
  DiagnosticType,
  DiagnosticTypeKind,
  TypedHoleDiagnostic,
} from "./host/type_diagnostics.ts";
import {
  extractNativeCompiler,
  extractStandardLibrary,
} from "./host/packaged_native.ts";

export { createZigProjectCompiler } from "./host/zig_project_client.ts";
export { jsonAssetParser } from "./host/assets.ts";
export {
  BlotGeneratorError,
  type BlotGeneratorInputMode,
  type BlotGeneratorOptions,
  type BlotGeneratorPhase,
  type BlotGeneratorReference,
  type BlotGeneratorRule,
  createBlotGenerator,
  expandGeneratorRules,
} from "./host/generators.ts";
export { decodeText, encodeText } from "./host/text.ts";
export {
  buildSymbolResolver,
  type DocCodeBlock,
  type DocConstructor,
  type DocEffect,
  type DocEffectOperation,
  type DocField,
  type DocImplementation,
  type DocLinkRef,
  type DocModule,
  type DocPackage,
  type DocProjectContext,
  type DocTestReport,
  type DocTestResult,
  type DocTrait,
  type DocTraitMember,
  type DocType,
  type DocValue,
  formatBlotType,
  type GenerateDocOptions,
  generateDocs,
  precompileDocExamples,
  renderCompactApi,
  type ResolvedDocSymbol,
  runDocCli,
  runDocTests,
  searchDocPackage,
  type SymbolResolver,
  writeMarkdownDocs,
} from "./host/doc.ts";
export {
  DOC_RUNNER_JS,
  generateHtmlDocs,
  type HtmlDocOptions,
  type PrecompiledDocExample,
} from "./host/doc_html.ts";
export type {
  AssetBuildStats,
  AssetContext,
  AssetDependency,
  AssetDiagnostic,
  AssetImport,
  AssetImports,
  AssetModule,
  AssetParser,
  AssetRecordType,
  AssetReference,
  AssetType,
  CompiledAsset,
  Stage0Provenance,
} from "./host/assets.ts";
export type {
  NativeAssetImport,
  NativeAssetKind,
  NativeAssetOptions,
} from "./host/native_assets.ts";
export type {
  StorageBudgets,
  ZigProjectBuildOptions,
  ZigProjectBuildResult,
  ZigProjectBuildStats,
  ZigProjectCompiler,
  ZigProjectCompilerOptions,
  ZigProjectCompletionItem,
  ZigProjectCompletionOptions,
  ZigProjectCompletionResult,
  ZigProjectDiagnostic,
  ZigProjectSourceLocation,
} from "./host/zig_project_client.ts";
export {
  formatGuestTrap,
  GuestError,
  guestTrapOf,
  instantiateGuest,
  readGuestAbi,
  readTrapMetadata,
  TRAP_SITE_OFFSET,
} from "./host/guest.ts";
export type {
  AsyncHostCallback,
  Guest,
  GuestAbi,
  GuestTrapInfo,
  HostCallback,
  TrapKind,
  TrapMetadataEntry,
} from "./host/guest.ts";

export const blotStdRoot: URL = new URL("./std/", import.meta.url);
/** Include this payload when bundling the host into a desktop executable. */
export const blotCompilerBinary: URL = new URL(
  "./generated/compiler/blotc.gz",
  import.meta.url,
);
export type CompilerOptions = Omit<ZigProjectCompilerOptions, "executable"> & {
  executable?: string | URL;
};

/** Keep this compiler open across builds of one project.
 * The packaged compiler and prelude are defaults; null disables the prelude. */
export async function createCompiler(
  options: CompilerOptions,
): Promise<ZigProjectCompiler> {
  const path = (value: string | URL): string =>
    resolve(value instanceof URL ? fileURLToPath(value) : value);
  if (options.assets !== undefined && options.nativeAssets !== undefined) {
    throw new TypeError("assets and nativeAssets cannot be used together");
  }
  // Capture paths before extracting the package or starting the child process.
  const captured = {
    ...options,
    assets: captureAssetImports(options.assets),
    nativeAssets: captureNativeAssets(
      options.nativeAssets,
      path(options.entry),
    ),
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
      complete: (completionOptions) => compiler.complete(completionOptions),
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
export {
  installPackages,
  type PackageOptions,
  type PackageProject,
  type PackageTests,
  resolveProject,
} from "./host/packages.ts";
export {
  decodeTestReport,
  discoverTestModules,
  formatTestRunReport,
  readTestMetadata,
  runBlotTests,
  TEST_REPORT_MAGIC,
  TEST_REPORT_VERSION,
  type TestCaseResult,
  type TestFailure,
  type TestKind,
  type TestMetadata,
  type TestModule,
  type TestModuleKind,
  type TestModuleResult,
  type TestReport,
  type TestRunOptions,
  type TestRunReport,
} from "./host/test_runner.ts";
