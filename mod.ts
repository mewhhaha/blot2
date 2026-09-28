/** Blot source compiler and guest API for Deno applications. */
import {
  createNativeCompiler as startNativeCompiler,
  type NativeCompiler,
  type NativeCompilerOptions,
} from "./compiler/native.ts";
import { extractNativeCompiler } from "./compiler/packaged_native.ts";

export { createSourceCompiler } from "./compiler/source.ts";
export {
  createSourceProjectLoader,
  loadSourceProject,
} from "./compiler/source_project.ts";
export { instantiateGuest, readGuestAbi } from "./compiler/guest.ts";
export type { NativeCompilerOptions } from "./compiler/native.ts";
export type { NativeCompiler } from "./compiler/native.ts";
export type {
  ProjectOptions,
  SourceProject,
} from "./compiler/source_project.ts";
export type {
  AsyncHostCallback,
  Guest,
  GuestAbi,
  HostCallback,
} from "./compiler/guest.ts";

export const blotPackageRoot: URL = new URL("./", import.meta.url);
export const blotStdRoot: URL = new URL("./std/", import.meta.url);
export const blotNativeBinary: URL = new URL(
  "./generated/compiler/blotc-oxcaml",
  import.meta.url,
);
export const blotParserDirectory: URL = new URL(
  "./generated/wasm/",
  import.meta.url,
);

export async function createNativeCompiler(
  options: NativeCompilerOptions = {},
): Promise<NativeCompiler> {
  if (options.executable !== undefined) return startNativeCompiler(options);
  const native = await extractNativeCompiler();
  try {
    const compiler = await startNativeCompiler({
      ...options,
      executable: native.path,
    });
    return {
      ...compiler,
      async dispose() {
        try {
          await compiler.dispose();
        } finally {
          await native.dispose();
        }
      },
    };
  } catch (error) {
    await native.dispose();
    throw error;
  }
}
