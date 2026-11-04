/** The editor protocol has its own framing and coordinate system. */
export interface Reader {
  read(bytes: Uint8Array): Promise<number | null>;
}
export interface Writer {
  write(bytes: Uint8Array): Promise<number>;
}
export class LspReader {
  #buffer = new Uint8Array(4096);
  #start = 0;
  #end = 0;
  constructor(private reader: Reader) {}
  async #byte(): Promise<number | null> {
    if (this.#start === this.#end) {
      const count = await this.reader.read(this.#buffer);
      if (count === null) return null;
      if (count === 0) return this.#byte();
      this.#start = 0;
      this.#end = count;
    }
    return this.#buffer[this.#start++];
  }
  async next(): Promise<Uint8Array | null> {
    const header: number[] = [];
    while (true) {
      const byte = await this.#byte();
      if (byte === null) {
        if (header.length === 0) return null;
        throw new Error("Truncated LSP header");
      }
      header.push(byte);
      if (header.length > 8192 || byte > 127) {
        throw new Error("Invalid LSP header");
      }
      if (header.slice(-4).join(",") === "13,10,13,10") break;
    }
    let length: number | undefined;
    for (
      const line of new TextDecoder().decode(Uint8Array.from(header)).trimEnd()
        .split("\r\n")
    ) {
      const colon = line.indexOf(":");
      if (colon < 1) throw new Error("Invalid LSP header field");
      if (line.slice(0, colon).toLowerCase() !== "content-length") continue;
      const value = line.slice(colon + 1).trim();
      if (length !== undefined || !/^\d+$/.test(value)) {
        throw new Error("Invalid LSP Content-Length");
      }
      length = Number(value);
    }
    if (
      length === undefined || !Number.isSafeInteger(length) ||
      length > 64 * 1024 * 1024
    ) {
      throw new Error("LSP body exceeds framing limit");
    }
    const body = new Uint8Array(length);
    let offset = 0;
    while (offset < length) {
      if (this.#start < this.#end) {
        const count = Math.min(length - offset, this.#end - this.#start);
        body.set(
          this.#buffer.subarray(this.#start, this.#start + count),
          offset,
        );
        offset += count;
        this.#start += count;
      } else {
        const count = await this.reader.read(body.subarray(offset));
        if (count === null) throw new Error("Truncated LSP body");
        offset += count;
      }
    }
    return body;
  }
}
export class LspWriter {
  #queue: Promise<void> = Promise.resolve();
  constructor(private writer: Writer) {}
  send(value: unknown): Promise<void> {
    const encoder = new TextEncoder();
    const body = encoder.encode(JSON.stringify(value));
    const header = encoder.encode(`Content-Length: ${body.length}\r\n\r\n`);
    const result = this.#queue.then(async () => {
      for (const bytes of [header, body]) {
        let offset = 0;
        while (offset < bytes.length) {
          offset += await this.writer.write(bytes.subarray(offset));
        }
      }
    });
    this.#queue = result.catch(() => {});
    return result;
  }
}
export type Position = { line: number; character: number };
export function byteOffset(text: string, position: Position): number {
  if (
    !position || !Number.isSafeInteger(position.line) ||
    !Number.isSafeInteger(position.character) || position.line < 0 ||
    position.character < 0
  ) {
    throw new TypeError("Invalid UTF-16 position");
  }
  let start = 0;
  for (let line = 0; line < position.line; line++) {
    const end = text.indexOf("\n", start);
    if (end < 0) throw new RangeError("Line is outside document");
    start = end + 1;
  }
  let end = text.indexOf("\n", start);
  if (end < 0) end = text.length;
  if (end > start && text[end - 1] === "\r") end--;
  const index = start + position.character;
  if (
    index > end ||
    (index > start && index < end && text.charCodeAt(index) >= 0xdc00 &&
      text.charCodeAt(index) <= 0xdfff)
  ) {
    throw new RangeError(
      "Character is outside document or splits a code point",
    );
  }
  return new TextEncoder().encode(text.slice(0, index)).length;
}
export function utf16Position(text: string, offset: number): Position {
  const bytes = new TextEncoder().encode(text);
  if (
    !Number.isInteger(offset) || offset < 0 || offset > bytes.length ||
    (offset < bytes.length && (bytes[offset] & 0xc0) === 0x80)
  ) {
    throw new RangeError("Invalid UTF-8 offset");
  }
  const prefix = new TextDecoder("utf-8", { fatal: true }).decode(
    bytes.subarray(0, offset),
  );
  const last = prefix.lastIndexOf("\n");
  let character = prefix.length - last - 1;
  if (prefix.endsWith("\r")) character--;
  return { line: prefix.split("\n").length - 1, character };
}
