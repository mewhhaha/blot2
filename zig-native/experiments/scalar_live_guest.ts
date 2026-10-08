/** Experimental companion to scalar_live_patch.zig; accepts compiler-produced
 * stateless scalar images only. It is not the public heap/effect guest API. */
export interface ScalarLiveGuest {
  readonly exports: Readonly<Record<string, (value: number) => number>>;
  readonly identity: string;
  apply(bytes: Uint8Array<ArrayBuffer>): Promise<void>;
}
const hex = (bytes: Uint8Array) =>
  Array.from(bytes, (value) => value.toString(16).padStart(2, "0")).join("");

function manifest(module: WebAssembly.Module, kind: number): DataView {
  const sections = WebAssembly.Module.customSections(
    module,
    "blot:scalar-patch",
  );
  if (sections.length !== 1) throw new Error("Missing scalar patch manifest");
  const view = new DataView(sections[0]);
  if (
    view.byteLength < 2 || view.getUint8(0) !== 1 || view.getUint8(1) !== kind
  ) {
    throw new Error("Unsupported scalar patch manifest");
  }
  return view;
}
function key(view: DataView, at: number): string {
  return hex(new Uint8Array(view.buffer, view.byteOffset + at, 32));
}
function validatePatchSections(bytes: Uint8Array) {
  let offset = 8;
  const uint = () => {
    let value = 0;
    for (let shift = 0; shift < 35; shift += 7) {
      if (offset === bytes.length) throw new Error("Truncated patch section");
      const byte = bytes[offset++];
      if (shift === 28 && (byte & 0xf0)) {
        throw new Error("Invalid section length");
      }
      value += (byte & 0x7f) * 2 ** shift;
      if (!(byte & 0x80)) return value;
    }
    throw new Error("Invalid section length");
  };
  while (offset < bytes.length) {
    const section = bytes[offset++], length = uint();
    // No globals, memory, startup or element segments may publish anything
    // during instantiation. All state belongs to the host's existing table.
    if (
      ![0, 1, 2, 3, 7, 10].includes(section) || length > bytes.length - offset
    ) {
      throw new Error("Patch contains state or initialization");
    }
    offset += length;
  }
}

export async function instantiateScalarLiveGuest(
  bytes: Uint8Array<ArrayBuffer>,
): Promise<ScalarLiveGuest> {
  const module = await WebAssembly.compile(new Uint8Array(bytes));
  const initial = manifest(module, 0);
  if (initial.byteLength !== 38) {
    throw new Error("Invalid initial patch manifest");
  }
  let identity = key(initial, 2);
  const count = initial.getUint32(34, true);
  if (WebAssembly.Module.imports(module).length !== 0) {
    throw new Error("Scalar live image must be closed");
  }
  const instance = await WebAssembly.instantiate(module);
  const table = instance.exports["blot:patch:table"];
  if (!(table instanceof WebAssembly.Table) || count > table.length) {
    throw new Error("Missing scalar function table");
  }
  const exports: Record<string, (value: number) => number> = {};
  for (const [name, value] of Object.entries(instance.exports)) {
    if (name === "blot:patch:table") continue;
    if (typeof value !== "function") throw new Error("Image contains state");
    exports[name] = value as (value: number) => number;
  }
  let queue: Promise<void> = Promise.resolve();
  return {
    exports: Object.freeze(exports),
    get identity() {
      return identity;
    },
    apply(input) {
      const bytes = new Uint8Array(input);
      const next = queue.then(async () => {
        validatePatchSections(bytes);
        const compiled = await WebAssembly.compile(bytes);
        const view = manifest(compiled, 1);
        if (
          view.byteLength < 70 ||
          view.byteLength !== 70 + view.getUint32(66, true) * 4
        ) {
          throw new Error("Invalid patch slots");
        }
        if (key(view, 2) !== identity) throw new Error("Stale patch base");
        const nextIdentity = key(view, 34), slots: number[] = [];
        for (let at = 70; at < view.byteLength; at += 4) {
          const slot = view.getUint32(at, true);
          if (
            slot >= count || (slots.length && slot <= slots[slots.length - 1])
          ) {
            throw new Error("Invalid patch slot");
          }
          slots.push(slot);
        }
        const imports = WebAssembly.Module.imports(compiled);
        if (
          imports.length !== 1 || imports[0].kind !== "table" ||
          imports[0].module !== "blot:patch" || imports[0].name !== "table"
        ) {
          throw new Error("Invalid patch imports");
        }
        const declared = WebAssembly.Module.exports(compiled);
        if (
          declared.length !== slots.length ||
          declared.some((entry, index) =>
            entry.kind !== "function" || entry.name !== String(slots[index])
          )
        ) {
          throw new Error("Invalid patch exports");
        }
        // Compilation/instantiation can await, publication cannot. These closed
        // synchronous guests have no host imports or suspended/reentrant calls.
        const replacement = await WebAssembly.instantiate(compiled, {
          "blot:patch": { table },
        });
        const functions = slots.map((slot) => {
          const value = replacement.exports[String(slot)];
          if (typeof value !== "function") {
            throw new Error("Missing patch function");
          }
          return value;
        });
        const previous = slots.map((slot) => table.get(slot));
        try {
          for (let i = 0; i < slots.length; i++) {
            table.set(slots[i], functions[i]);
          }
        } catch (error) {
          for (let i = 0; i < slots.length; i++) {
            table.set(slots[i], previous[i]);
          }
          throw error;
        }
        identity = nextIdentity;
      });
      queue = next.catch(() => {});
      return next;
    },
  };
}
