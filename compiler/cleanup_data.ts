/** Closed cleanup data uses copied values and producer-owned physical schemas.
 * No managed pointer, loan, callable, provider or cleanup token is exposed. */
export interface DataNode {
  readonly id: number;
  readonly tag:
    | "unit"
    | "boolean"
    | "u32"
    | "f32"
    | "product"
    | "record"
    | "array"
    | "list"
    | "nominal"
    | "opaque";
  readonly floating: boolean;
  readonly reference: boolean;
  readonly child: number;
  readonly row_words: number;
  readonly leaf_words: number;
  readonly children: readonly number[];
  readonly fields: readonly { readonly name: string; readonly child: number }[];
  readonly variants: readonly {
    readonly tag: number;
    readonly child: number;
  }[];
  readonly name: string;
}
export type DataValue =
  | null
  | boolean
  | number
  | string
  | Uint32Array
  | Float32Array
  | readonly DataValue[]
  | { readonly [key: string]: DataValue };
const keys =
  "id,tag,floating,reference,child,row_words,leaf_words,children,fields,variants,name";
const tags = new Set([
  "unit",
  "boolean",
  "u32",
  "f32",
  "product",
  "record",
  "array",
  "list",
  "nominal",
  "opaque",
]);
const uint = (value: unknown): value is number =>
  typeof value === "number" && Number.isInteger(value) && value >= 0 &&
  value <= 0xffffffff;
function fail(): never {
  throw new Error("Invalid closed cleanup data schema");
}
export function readDataSchemas(
  module: WebAssembly.Module,
): ReadonlyMap<number, DataNode> | undefined {
  const sections = WebAssembly.Module.customSections(
    module,
    "blot:cleanup_data",
  );
  if (sections.length === 0) return undefined;
  if (sections.length !== 1 || sections[0].byteLength > 1_048_576) fail();
  const text = new TextDecoder("utf-8", { fatal: true }).decode(sections[0]);
  const parsed = JSON.parse(text);
  if (
    !parsed || Object.keys(parsed).join(",") !== "version,nodes" ||
    parsed.version !== 1 || !Array.isArray(parsed.nodes) ||
    parsed.nodes.length === 0 || parsed.nodes.length > 4096 ||
    JSON.stringify(parsed) !== text
  ) fail();
  const nodes = new Map<number, DataNode>();
  let prior = 0;
  for (const node of parsed.nodes) {
    if (
      !node || Object.keys(node).join(",") !== keys || !uint(node.id) ||
      node.id <= prior || !tags.has(node.tag) ||
      typeof node.floating !== "boolean" ||
      typeof node.reference !== "boolean" || node.floating && node.reference ||
      !uint(node.child) || !uint(node.row_words) || node.row_words > 16 ||
      !uint(node.leaf_words) ||
      (node.tag === "list" && node.leaf_words !== 244 ||
        node.tag !== "list" && node.leaf_words !== 0) ||
      !Array.isArray(node.children) || !node.children.every(uint) ||
      !Array.isArray(node.fields) || !Array.isArray(node.variants) ||
      typeof node.name !== "string"
    ) fail();
    prior = node.id;
    const names = new Set<string>();
    for (const field of node.fields) {
      if (
        !field || Object.keys(field).join(",") !== "name,child" ||
        typeof field.name !== "string" || names.has(field.name) ||
        !uint(field.child) || field.child === 0
      ) fail();
      names.add(field.name);
      Object.freeze(field);
    }
    const variants = new Set<number>();
    for (const variant of node.variants) {
      if (
        !variant || Object.keys(variant).join(",") !== "tag,child" ||
        !uint(variant.tag) || variants.has(variant.tag) ||
        !uint(variant.child) || variant.child === 0
      ) fail();
      variants.add(variant.tag);
      Object.freeze(variant);
    }
    const sequence = node.tag === "array" || node.tag === "list";
    if (
      sequence !== (node.child !== 0) || !sequence && node.row_words !== 0 ||
      node.tag !== "product" && node.tag !== "nominal" &&
        node.tag !== "opaque" && node.children.length !== 0 ||
      node.tag !== "record" && node.fields.length !== 0 ||
      node.tag !== "nominal" && node.variants.length !== 0 ||
      (node.tag === "nominal" || node.tag === "opaque") !==
        (node.name.length !== 0)
    ) fail();
    if (
      ["unit", "boolean", "u32", "f32"].includes(node.tag) &&
      (node.reference || node.floating !== (node.tag === "f32"))
    ) fail();
    if (
      ["product", "record", "array", "list", "nominal"].includes(node.tag) &&
      (!node.reference || node.floating)
    ) fail();
    if (node.tag === "nominal" && node.variants.length === 0) fail();
    Object.freeze(node.children);
    Object.freeze(node.fields);
    Object.freeze(node.variants);
    nodes.set(node.id, Object.freeze(node));
  }
  for (const node of nodes.values()) {
    for (
      const child of [
        node.child,
        ...node.children,
        ...node.fields.map((field) => field.child),
        ...node.variants.map((variant) => variant.child),
      ]
    ) if (child !== 0 && !nodes.has(child)) fail();
    if (node.row_words !== 0) {
      const child = nodes.get(node.child)!;
      let fields: readonly number[] = child.children;
      if (child.tag === "record") {
        fields = child.fields.map((field) => field.child);
      }
      if (
        (child.tag !== "record" && child.tag !== "product") ||
        fields.length !== node.row_words || fields.some((field) =>
          nodes.get(field)!.reference
        )
      ) fail();
    }
  }
  return nodes;
}
/** Schema graphs are bounded separately from a copied value's traversal. */
export function validateDataRoots(
  nodes: ReadonlyMap<number, DataNode> | undefined,
  roots: readonly number[],
): void {
  if (!nodes) {
    if (roots.length !== 0) fail();
    return;
  }
  const seen = new Set<number>();
  const path: number[] = [];
  let budget = 65_536;
  const visit = (id: number, depth: number) => {
    if (--budget < 0 || depth >= 128 || !nodes.has(id)) fail();
    const cycle = path.indexOf(id);
    if (cycle >= 0) {
      if (!path.slice(cycle).some((id) => nodes.get(id)!.tag === "nominal")) {
        fail();
      }
      return;
    }
    if (seen.has(id)) return;
    seen.add(id);
    path.push(id);
    const node = nodes.get(id)!;
    if (node.child !== 0) visit(node.child, depth + 1);
    for (const child of node.children) visit(child, depth + 1);
    for (const field of node.fields) visit(field.child, depth + 1);
    for (const variant of node.variants) visit(variant.child, depth + 1);
    path.pop();
  };
  for (const root of roots) visit(root, 0);
  if (seen.size !== nodes.size) fail();
}
export function copyData(
  memory: WebAssembly.Memory,
  nodes: ReadonlyMap<number, DataNode>,
  root: number,
  word: number,
): DataValue {
  const view = new DataView(memory.buffer);
  const floatBits = new DataView(new ArrayBuffer(4));
  let budget = 65_536;
  const active = new Set<string>();
  function range(address: number, bytes: number): void {
    if (
      !uint(address) || address % 4 !== 0 || address < 4 || !uint(bytes) ||
      address > view.byteLength || bytes > view.byteLength - address
    ) throw new Error("Cleanup data lies outside guest memory");
  }
  function load(address: number): number {
    range(address, 4);
    return view.getUint32(address, true);
  }
  function block(address: number, bytes: number): void {
    range(address, bytes);
    // Constants and immutable empty collection descriptors live below 64 KiB.
    if (address < 65536) return;
    range(address - 32, 32);
    const requested = load(address - 28), flags = load(address - 24);
    if (
      requested < bytes || requested > view.byteLength - address ||
      (flags & 20) !== 4 || load(address - 16) === 0
    ) throw new Error("Cleanup data is not a live typed block");
  }
  function slot(address: number, index: number, reference: boolean): void {
    if (address < 65536) return;
    const flags = load(address - 24);
    let mask = load(address - 12);
    let bit = Math.min(index, 31);
    if ((flags & 1024) !== 0) {
      const words = load(mask);
      if (index >= words) {
        throw new Error("Cleanup data slot exceeds its shape");
      }
      mask = load(mask + 4 + Math.floor(index / 32) * 4);
      bit = index % 32;
    }
    if (((mask >>> bit) & 1) !== Number(reference)) {
      throw new Error("Cleanup data slot role differs from its schema");
    }
  }
  function scalar(node: DataNode, value: number): DataValue {
    if (node.tag === "unit") {
      if (value !== 0) throw new Error("Cleanup Unit is not canonical");
      return null;
    }
    if (node.tag === "boolean") {
      if (value > 1) throw new Error("Cleanup Bool is not canonical");
      return value === 1;
    }
    if (node.tag === "u32") return value;
    if (node.tag === "f32") {
      floatBits.setUint32(0, value, true);
      return floatBits.getFloat32(0, true);
    }
    return Object.freeze({ kind: "opaque", type: node.name });
  }
  function aggregate(
    node: DataNode,
    address: number,
    depth: number,
    inline = false,
  ): DataValue {
    const fields = node.fields;
    const children = node.children;
    let count = children.length;
    if (node.tag === "record") count = fields.length;
    if (count === 0) {
      if (address !== 0) {
        throw new Error("Cleanup empty data is not canonical");
      }
    } else if (!inline) block(address, count * 4);
    else range(address, count * 4);
    const result: DataValue[] = [];
    const record: Record<string, DataValue> = {};
    for (let index = 0; index < count; index++) {
      let child = children[index];
      if (node.tag === "record") child = fields[index].child;
      if (!inline) slot(address, index, nodes.get(child)!.reference);
      const value = copy(child, load(address + index * 4), depth + 1);
      if (node.tag === "record") {
        Object.defineProperty(record, fields[index].name, {
          value,
          enumerable: true,
        });
      } else result.push(value);
    }
    if (node.tag === "record") return Object.freeze(record);
    return Object.freeze(result);
  }
  function element(
    node: DataNode,
    address: number,
    depth: number,
    row: boolean,
  ): DataValue {
    if (row) {
      if (--budget < 0) throw new Error("Cleanup data copy limit");
      return aggregate(node, address, depth, true);
    }
    return copy(node.id, load(address), depth);
  }
  function copy(id: number, value: number, depth: number): DataValue {
    if (--budget < 0 || depth >= 128) {
      throw new Error("Cleanup data copy limit");
    }
    const node = nodes.get(id);
    if (!node) fail();
    value >>>= 0;
    if (!node.reference) return scalar(node, value);
    const key = `${id}:${value}`;
    if (active.has(key)) throw new Error("Cleanup data cycle");
    active.add(key);
    try {
      if (node.tag === "opaque") {
        if (value !== 0) block(value, 4);
        return Object.freeze({ kind: "opaque", type: node.name });
      }
      if (node.tag === "product" || node.tag === "record") {
        return aggregate(node, value, depth);
      }
      if (node.tag === "nominal") {
        block(value, 8);
        slot(value, 0, false);
        const tag = load(value);
        let variant: DataNode["variants"][number] | undefined;
        for (const candidate of node.variants) {
          if (--budget < 0) throw new Error("Cleanup variant copy limit");
          if (candidate.tag === tag) {
            variant = candidate;
            break;
          }
        }
        if (!variant) {
          throw new Error("Cleanup constructor differs from its schema");
        }
        slot(value, 1, nodes.get(variant.child)!.reference);
        return Object.freeze({
          family: node.name,
          tag,
          value: copy(variant.child, load(value + 4), depth + 1),
        });
      }
      const child = nodes.get(node.child)!;
      const words = Math.max(1, node.row_words);
      const values: DataValue[] = [];
      if (node.tag === "array") {
        block(value, 4);
        slot(value, 0, false);
        const length = load(value);
        if (
          length > budget ||
          length > (view.byteLength - value - 4) / (words * 4)
        ) throw new Error("Cleanup array copy limit");
        block(value, 4 + length * words * 4);
        for (let index = 0; index < length; index++) {
          if (words === 1 && node.row_words === 0) {
            slot(value, index + 1, child.reference);
          }
          values.push(
            element(
              child,
              value + 4 + index * words * 4,
              depth + 1,
              node.row_words !== 0,
            ),
          );
        }
        if (child.tag === "u32") return Uint32Array.from(values as number[]);
        if (child.tag === "f32") {
          const floats = new Float32Array(values.length);
          const bits = new DataView(floats.buffer);
          for (let index = 0; index < values.length; index++) {
            bits.setUint32(index * 4, load(value + 4 + index * 4), true);
          }
          return floats;
        }
        return Object.freeze(values);
      }
      if (node.tag !== "list") fail();
      block(value, 32);
      slot(value, 0, false);
      slot(value, 1, true);
      slot(value, 4, false);
      slot(value, 6, false);
      const length = load(value),
        scalarElements = load(value + 16),
        leafLimit = load(value + 24);
      let expectedScalar = 0;
      if (node.row_words !== 0) expectedScalar = words;
      else if (!child.reference) expectedScalar = 1;
      if (
        length % words !== 0 || length / words > budget ||
        scalarElements !== expectedScalar ||
        leafLimit !== node.leaf_words - node.leaf_words % words
      ) throw new Error("Cleanup list representation differs from its schema");
      const root = load(value + 4);
      const leafWords = node.leaf_words;
      const address = (node: number, index: number, steps: number): number => {
        if (--budget < 0 || steps >= 128 || node === 0) {
          throw new Error("Cleanup list copy limit");
        }
        block(node, 16);
        const height = load(node + 4),
          length = load(node + 8),
          capacity = load(node + 12);
        if (index >= length || height > 128) {
          throw new Error("Cleanup list node is invalid");
        }
        if (height === 0) {
          if (
            capacity < length || capacity > leafWords || length % words !== 0 ||
            index + words > length
          ) {
            throw new Error("Cleanup list leaf capacity is invalid");
          }
          block(node, 16 + capacity * 4);
          slot(node, index + 4, child.reference && words === 1);
          return node + 16 + index * 4;
        }
        block(node, 24);
        slot(node, 4, true);
        slot(node, 5, true);
        const left = load(node + 16), right = load(node + 20);
        block(left, 16);
        const split = load(left + 8);
        if (index < split) return address(left, index, steps + 1);
        return address(right, index - split, steps + 1);
      };
      for (let index = 0; index < length; index += words) {
        values.push(
          element(
            child,
            address(root, index, 0),
            depth + 1,
            node.row_words !== 0,
          ),
        );
      }
      return Object.freeze(values);
    } finally {
      active.delete(key);
    }
  }
  return copy(root, word, 0);
}
