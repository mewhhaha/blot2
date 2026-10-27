/** Copy-only K1-WASM32-ABI1 host surface. Instances and memory never escape. */
const ABI = 0x4b310001;
const ABI_HASH = 'c28cdfcbe37be7dbe90acf944c4dad911981e88427e0d29a3a2404b354f0f42f';
const COUNTERS = ['backing_reservations', 'backing_successes', 'backing_failures', 'region_resets', 'region_releases', 'backing_live_bytes', 'backing_high_water_bytes', 'result_high_water_bytes', 'scratch_high_water_bytes', 'initialized_bytes', 'copied_bytes', 'source_calls', 'loop_iterations'];
type Plain = {
  kind: 'unit' | 'bool' | 'u32' | 'f32' | 'tuple' | 'record' | 'sum';
  size: number;
  fields?: { name: string; offset: number; type: Plain }[];
};
type Field = { name: string; offset: number; kind: 'plain' | 'view'; max_count?: number; type: Plain };
type Entry = { id: number; name: string; fields: Field[]; fixed_bytes: number; result_type: Plain; output_capacity: number };
type Manifest = {
  language: string; abi: string; abi_hash: string;
  memory: { pages: number; ingress: number; ingress_bytes: number; egress: number; egress_bytes: number };
  exports: Entry[];
  telemetry?: { version: number; word_export: string; counter_bits: number; counters: string[] };
};
export type CallResult =
  | { status: 'Ok'; items: unknown[] | { length: number } }
  | { status: 'OutputTooSmall'; requiredBytes: number }
  | { status: 'LanguageError'; detail: number }
  | { status: 'InvalidInput' | 'ReservationFailed' | 'Busy' | 'FrameLimit' | 'Poisoned' };
function require(ok: unknown, message: string): asserts ok {
  if (!ok) throw new TypeError(message);
}
function u32(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 0xffffffff;
}
function validateType(t: Plain, depth = 0): number {
  require(t && depth <= 32 && u32(t.size) && t.size <= 64, 'invalid Plain layout');
  if (t.kind === 'unit') { require(t.size === 0, 'invalid Unit size'); return 1; }
  if (['bool', 'u32', 'f32'].includes(t.kind)) { require(t.size === 4, 'invalid scalar size'); return 1; }
  require(['tuple', 'record', 'sum'].includes(t.kind) && Array.isArray(t.fields), 'invalid Plain kind');
  require(t.kind !== 'sum' || (t.fields.length >= 1 && t.fields.length <= 4), 'invalid sum');
  let extent = t.kind === 'sum' ? 4 : 0;
  let nodes = 1;
  const names = new Set<string>();
  for (const field of t.fields) {
    require(field && typeof field.name === 'string' && !names.has(field.name), 'invalid field name');
    names.add(field.name);
    require(field.offset === (t.kind === 'sum' ? 4 : extent), 'invalid field offset');
    nodes += validateType(field.type, depth + 1);
    extent = t.kind === 'sum' ? Math.max(extent, 4 + field.type.size) : extent + field.type.size;
  }
  require(extent === t.size && nodes <= 32, 'invalid Plain geometry');
  return nodes;
}
function validateManifest(m: Manifest) {
  require(m?.language === 'k1' && m.abi === 'K1-WASM32-ABI1' && m.abi_hash === ABI_HASH, 'incompatible K1 ABI');
  if (m.telemetry !== undefined) {
    const t = m.telemetry;
    require(t && t.version === 1 && t.word_export === 'blot.telemetry' && t.counter_bits === 64 && Array.isArray(t.counters) && t.counters.length === COUNTERS.length && t.counters.every((name, i) => name === COUNTERS[i]), 'invalid telemetry schema');
  }
  const g = m.memory;
  require(g && u32(g.pages) && g.pages > 0 && g.pages <= 16384, 'invalid memory size');
  for (const [offset, size] of [[g.ingress, g.ingress_bytes], [g.egress, g.egress_bytes]]) {
    require(u32(offset) && u32(size) && offset % 4 === 0 && size >= 32 && offset + size <= g.pages * 65536, 'invalid host window');
  }
  require(g.ingress + g.ingress_bytes <= g.egress || g.egress + g.egress_bytes <= g.ingress, 'overlapping host windows');
  require(Array.isArray(m.exports) && m.exports.length <= 4096, 'invalid export inventory');
  const names = new Set<string>(), ids = new Set<number>();
  for (const entry of m.exports) {
    require(u32(entry.id) && entry.id > 0 && !ids.has(entry.id) && typeof entry.name === 'string' && !names.has(entry.name), 'invalid export identity');
    names.add(entry.name); ids.add(entry.id);
    require(u32(entry.output_capacity) && Array.isArray(entry.fields) && entry.fields.length <= 64, 'invalid export fields');
    let offset = 0;
    const fields = new Set<string>();
    for (const field of entry.fields) {
      require(field && typeof field.name === 'string' && !fields.has(field.name) && field.offset === offset, 'invalid wire field');
      fields.add(field.name); validateType(field.type);
      require(field.kind === 'view' || field.kind === 'plain', 'invalid field kind');
      if (field.kind === 'view') require(u32(field.max_count), 'invalid input maximum');
      offset += field.kind === 'view' ? 8 : field.type.size;
    }
    require(entry.fixed_bytes === offset && offset <= g.ingress_bytes - 32, 'invalid descriptor extent');
    validateType(entry.result_type);
  }
}
function encode(t: Plain, value: unknown, bytes: DataView, at: number) {
  if (t.kind === 'unit') { require(value === null || value === undefined, 'Unit is null'); return; }
  if (t.kind === 'u32') { require(u32(value), 'expected U32'); bytes.setUint32(at, value, true); return; }
  if (t.kind === 'bool') { require(typeof value === 'boolean', 'expected Bool'); bytes.setUint32(at, value ? 1 : 0, true); return; }
  if (t.kind === 'f32') { require(typeof value === 'number', 'expected F32'); bytes.setFloat32(at, value, true); return; }
  if (t.kind === 'sum') {
    require(value && typeof value === 'object' && 'tag' in value, 'expected tagged sum');
    const tagged = value as { tag: string; value?: unknown };
    const tag = t.fields!.findIndex(field => field.name === tagged.tag);
    require(tag >= 0, 'unknown sum variant');
    bytes.setUint32(at, tag, true); encode(t.fields![tag].type, tagged.value, bytes, at + 4); return;
  }
  require(value && typeof value === 'object' && (t.kind !== 'tuple' || Array.isArray(value)), 'expected aggregate');
  for (const field of t.fields!) encode(field.type, (value as Record<string, unknown>)[field.name], bytes, at + field.offset);
}
function decode(t: Plain, bytes: DataView, at: number): unknown {
  if (t.kind === 'unit') return null;
  if (t.kind === 'u32') return bytes.getUint32(at, true);
  if (t.kind === 'f32') return bytes.getFloat32(at, true);
  if (t.kind === 'bool') { const value = bytes.getUint32(at, true); require(value <= 1, 'noncanonical Bool'); return value === 1; }
  if (t.kind === 'sum') {
    const tag = bytes.getUint32(at, true); require(tag < t.fields!.length, 'invalid sum tag');
    const field = t.fields![tag];
    for (let i = 4 + field.type.size; i < t.size; i++) require(bytes.getUint8(at + i) === 0, 'noncanonical sum padding');
    return { tag: field.name, value: decode(field.type, bytes, at + 4) };
  }
  if (t.kind === 'tuple') return t.fields!.map(field => decode(field.type, bytes, at + field.offset));
  const result: Record<string, unknown> = Object.create(null);
  for (const field of t.fields!) result[field.name] = decode(field.type, bytes, at + field.offset);
  return result;
}
export class Blot {
  #memory: WebAssembly.Memory;
  #call: (id: number, inputBytes: number, outputCapacity: number) => number;
  #manifest: Manifest;
  #poisoned = false;
  #busy = false;
  #telemetry?: (word: number) => number;
  private constructor(instance: WebAssembly.Instance, manifest: Manifest) {
    this.#memory = instance.exports.memory as WebAssembly.Memory;
    this.#call = instance.exports.blot_call as (id: number, inputBytes: number, outputCapacity: number) => number;
    this.#manifest = manifest;
    if (manifest.telemetry) {
      const getter = instance.exports[manifest.telemetry.word_export];
      require(typeof getter === 'function', 'missing telemetry getter');
      this.#telemetry = getter as (word: number) => number;
    }
    require(this.#memory instanceof WebAssembly.Memory && typeof this.#call === 'function', 'missing K1 bridge');
    require(this.#memory.buffer.byteLength === manifest.memory.pages * 65536, 'memory geometry mismatch');
  }
  static async load(wasm: BufferSource): Promise<Blot> {
    const module = await WebAssembly.compile(wasm);
    require(WebAssembly.Module.imports(module).length === 0, 'K1 modules cannot import host callbacks');
    const sections = WebAssembly.Module.customSections(module, 'blot.k1.manifest');
    require(sections.length === 1 && sections[0].byteLength <= 1048576, 'missing or oversized K1 manifest');
    const manifest = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(sections[0])) as Manifest;
    validateManifest(manifest);
    return new Blot(await WebAssembly.instantiate(module), manifest);
  }
  get exports(): string[] { return this.#manifest.exports.map(entry => entry.name); }
  get poisoned(): boolean { return this.#poisoned; }
  /** Diagnostic counters only; no memory, addresses or callable handles escape. */
  telemetry(): Readonly<Record<string, bigint>> | null {
    require(!this.#poisoned && !this.#busy, 'instance is unavailable');
    if (!this.#telemetry) return null;
    this.#busy = true;
    try {
      const result: Record<string, bigint> = Object.create(null);
      for (let i = 0; i < COUNTERS.length; i++) {
        const low = this.#telemetry(2 * i) >>> 0, high = this.#telemetry(2 * i + 1) >>> 0;
        result[COUNTERS[i]] = BigInt(low) | (BigInt(high) << 32n);
      }
      return Object.freeze(result);
    } catch (cause) { this.#poisoned = true; throw new TypeError('telemetry trapped; instance poisoned', { cause }); }
    finally { this.#busy = false; }
  }
  invoke(name: string, input: Record<string, unknown>, outputCapacity?: number): CallResult {
    if (this.#poisoned) return { status: 'Poisoned' };
    if (this.#busy) return { status: 'Busy' };
    this.#busy = true;
    let entered = false;
    try {
      const entry = this.#manifest.exports.find(entry => entry.name === name);
      if (!entry) return { status: 'InvalidInput' };
      const map = this.#manifest.memory;
      const capacity = outputCapacity ?? map.egress_bytes - 32;
      if (!u32(capacity) || capacity > map.egress_bytes - 32 || !input || typeof input !== 'object') return { status: 'InvalidInput' };
      // Read caller-owned fields once, under the reentry guard, before publishing.
      const values = entry.fields.map(field => input[field.name]);
      let size = entry.fixed_bytes;
      entry.fields.forEach((field, i) => {
        if (field.kind === 'view') {
          const value = values[i] as ArrayLike<unknown>;
          require((field.type.size === 0 && value && typeof value === 'object' && 'length' in value) || Array.isArray(value) || (ArrayBuffer.isView(value) && 'length' in value), 'expected input array');
          require(u32(value.length) && value.length <= field.max_count!, 'input exceeds declared maximum');
          size += value.length * field.type.size;
        }
      });
      require(size <= map.ingress_bytes - 32, 'input exceeds ingress window');
      const staged = new Uint8Array(32 + size);
      const wire = new DataView(staged.buffer);
      wire.setUint32(0, ABI, true); wire.setUint32(4, entry.id, true); wire.setUint32(12, size, true);
      let next = entry.fixed_bytes;
      entry.fields.forEach((field, i) => {
        const offset = 32 + field.offset;
        if (field.kind === 'plain') encode(field.type, values[i], wire, offset);
        else {
          const value = values[i] as ArrayLike<unknown>;
          wire.setUint32(offset, value.length, true); wire.setUint32(offset + 4, next, true);
          if (field.type.size !== 0) for (let j = 0; j < value.length; j++) encode(field.type, value[j], wire, 32 + next + j * field.type.size);
          next += value.length * field.type.size;
        }
      });
      new Uint8Array(this.#memory.buffer, map.ingress, staged.length).set(staged);
      entered = true;
      const status = this.#call(entry.id, staged.length, capacity);
      if (status === 4) return { status: 'Busy' }; // Busy deliberately leaves the old header intact.
      const result = new DataView(this.#memory.buffer, map.egress, map.egress_bytes);
      require(result.getUint32(0, true) === ABI && result.getUint32(4, true) === entry.id && result.getUint32(8, true) === status && result.getUint32(28, true) === 0, 'invalid bridge response');
      const payload = result.getUint32(12, true), required = result.getUint32(16, true), count = result.getUint32(20, true);
      if (status !== 0) {
        require(payload === 0 && (status === 2 || required === 0), 'error exposes payload');
        if (status === 2) return { status: 'OutputTooSmall', requiredBytes: required };
        if (status === 6) return { status: 'LanguageError', detail: result.getUint32(24, true) };
        const names = { 1: 'InvalidInput', 3: 'ReservationFailed', 5: 'FrameLimit' } as const;
        require(status in names, 'unknown bridge status'); return { status: names[status as keyof typeof names] };
      }
      require(payload <= capacity && payload === required && payload === 8 + count * entry.result_type.size && result.getUint32(32, true) === count && result.getUint32(36, true) === 8, 'invalid output extent');
      if (entry.result_type.size === 0) return { status: 'Ok', items: { length: count } };
      const items: unknown[] = [];
      for (let i = 0; i < count; i++) items.push(decode(entry.result_type, result, 40 + i * entry.result_type.size));
      return { status: 'Ok', items };
    } catch {
      if (entered) { this.#poisoned = true; return { status: 'Poisoned' }; }
      return { status: 'InvalidInput' };
    } finally { this.#busy = false; }
  }
}
