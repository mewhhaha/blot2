// Native API option validation must not load the JavaScript reference backend.
import type { ArtifactOptions } from "./host.ts";

/** Whether compile returns the analysis beside the Wasm bytes. */
export function includesAnalysis(options: ArtifactOptions): boolean {
  if (options.analysis === undefined) return true;
  if (typeof options.analysis !== "boolean") {
    throw new TypeError("analysis must be a boolean");
  }
  return options.analysis;
}
