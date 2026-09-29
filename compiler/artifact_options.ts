import type { ArtifactOptions } from "./host.ts";

/** Native-only entry points must not load the JavaScript compiler to validate
 * an option. Keep this behavior aligned with the legacy host API; the full
 * differential gate compares both successful results and option diagnostics. */
export function includesAnalysis(options: ArtifactOptions): boolean {
  if (options.analysis === undefined) return true;
  if (typeof options.analysis !== "boolean") {
    throw new TypeError("analysis must be a boolean");
  }
  return options.analysis;
}
