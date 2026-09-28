/** Blot's native Carp backend. No Bend or JavaScript compiler fallback is used.
 * The existing Baba/TypeScript source frontend and host APIs are shared. */
import { createNativeCompiler, type NativeCompilerOptions } from "./native.ts";
import { createNativeIncrementalCompiler } from "./native_incremental.ts";
import {
  createNativeProjectCompiler,
  type NativeProjectOptions,
} from "./native_project.ts";

export const carpExecutable = new URL(
  "../generated/carp-port/blotc-carp-native",
  import.meta.url,
);

export function createCarpCompiler(options: NativeCompilerOptions = {}) {
  return createNativeCompiler({
    ...options,
    executable: options.executable ?? carpExecutable,
  });
}

export function createCarpIncrementalCompiler(
  options: NativeCompilerOptions = {},
) {
  return createNativeIncrementalCompiler({
    ...options,
    executable: options.executable ?? carpExecutable,
  });
}

export function createCarpProjectCompiler(options: NativeProjectOptions = {}) {
  return createNativeProjectCompiler({
    ...options,
    executable: options.executable ?? carpExecutable,
  });
}
