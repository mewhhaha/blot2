/** Shared option validation without loading the JavaScript reference compiler. */
export function includesAnalysis(options: { readonly analysis?: boolean }): boolean {
  if (options.analysis === undefined) return true;
  if (typeof options.analysis !== "boolean") {
    throw new TypeError("analysis must be a boolean");
  }
  return options.analysis;
}
