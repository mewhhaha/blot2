/** Convert JavaScript text to Blot's Unicode-scalar Array U32 host value. */
export function encodeText(value: string): Uint32Array {
  const scalars: number[] = [];
  for (const scalar of value) {
    const codepoint = scalar.codePointAt(0)!;
    if (codepoint >= 0xD800 && codepoint <= 0xDFFF) {
      throw new RangeError("Text contains an unpaired UTF-16 surrogate");
    }
    scalars.push(codepoint);
  }
  return Uint32Array.from(scalars);
}

/** Reject invalid external scalar values before constructing JavaScript text. */
export function decodeText(values: Iterable<number>): string {
  const scalars: string[] = [];
  for (const value of values) {
    if (
      !Number.isInteger(value) || value < 0 || value > 0x10FFFF ||
      (value >= 0xD800 && value <= 0xDFFF)
    ) {
      throw new RangeError(`Invalid Unicode scalar: ${value}`);
    }
    scalars.push(String.fromCodePoint(value));
  }
  return scalars.join("");
}
