import { createFrontend, type Cst } from "./syntax.ts";

/** A checked data declaration's source shape, used to emit ordinary Blot code. */
export interface DeriveShape {
  name: string;
  parameters: string[];
  constructors: {
    name: string;
    fields: { name: string; type: string }[];
    payload: "none" | "record" | "product" | "scalar";
  }[];
}

function children(node: Cst, field: string): Cst[] {
  return node.children.filter((child) => child.field === field);
}

function descendant(node: Cst, kind: string): Cst | undefined {
  if (node.kind === kind) return node;
  for (const child of node.children) {
    const found = descendant(child, kind);
    if (found) return found;
  }
}

function leaves(node: Cst): Cst[] {
  if (!node.children.length) return [node];
  return node.children.flatMap(leaves);
}

function sourceText(source: string, node: Cst): string {
  const tokens = leaves(node).filter((leaf) => leaf.text.length > 0);
  if (!tokens.length) return "";
  const first = Number(tokens[0].offset);
  const last = tokens.at(-1)!;
  return source.slice(first, Number(last.offset) + last.text.length);
}

function payloadKind(payload: Cst): "record" | "product" | "scalar" {
  let current = payload;
  while (current.children.length === 1) current = current.children[0];
  if (current.kind === "type_application") {
    current = children(current, "head")[0] ?? current;
    while (current.children.length === 1) current = current.children[0];
  }
  if (current.kind === "type_record") return "record";
  if (current.kind === "type_product") return "product";
  if (current.kind === "type_group" && children(current, "value").length > 1) {
    return "product";
  }
  return "scalar";
}

/** Extract opt-in derivation inputs from the same CST accepted by the editor. */
export async function dataShapes(source: string): Promise<DeriveShape[]> {
  const frontend = await createFrontend();
  try {
    const root = frontend.parse(source).root;
    const shapes: DeriveShape[] = [];
    for (const declaration of root.children) {
      const data = descendant(declaration, "data_type");
      if (!data) continue;
      const name = children(data, "name")[0]?.text;
      if (!name) continue;
      const parameters = children(data, "parameters").flatMap((parameter) =>
        leaves(parameter).filter((leaf) => leaf.kind === "IDENT")
          .map((leaf) => leaf.text)
      );
      const constructors = children(data, "constructors").map((constructor) => {
        const variant = children(constructor, "name")[0]?.text;
        if (!variant) throw new Error(`Unnamed constructor in ${name}`);
        const payload = children(constructor, "payload")[0];
        if (!payload) {
          return { name: variant, fields: [], payload: "none" as const };
        }
        const kind = payloadKind(payload);
        const product = kind === "product"
          ? descendant(payload, "type_product") ??
            descendant(payload, "type_group")
          : undefined;
        const fieldNodes = kind === "record"
          ? children(descendant(payload, "type_record")!, "fields")
          : kind === "product"
          ? children(product!, "elements").length
            ? children(product!, "elements")
            : children(product!, "value")
          : [payload];
        const fields = fieldNodes.map((field, index) => ({
          name: kind === "record"
            ? children(field, "name")[0]?.text ?? `_${index}`
            : String(index),
          type: sourceText(
            source,
            kind === "record" ? children(field, "value")[0] ?? field : field,
          ),
        }));
        return { name: variant, fields, payload: kind };
      });
      shapes.push({ name, parameters, constructors });
    }
    return shapes;
  } finally {
    frontend.dispose();
  }
}

function pattern(shape: DeriveShape["constructors"][number], side: string) {
  const head = `$${shape.name}`;
  if (shape.payload === "none") return head;
  if (shape.payload === "scalar") return `${head} ${side}0`;
  if (shape.payload === "product") {
    return `${head} (${shape.fields.map((_, i) => `${side}${i}`).join(", ")})`;
  }
  return `${head} { ${
    shape.fields.map((f, i) => `${f.name}: ${side}${i}`).join(", ")
  } }`;
}

function typeHead(shape: DeriveShape) {
  if (!shape.parameters.length) return shape.name;
  if (shape.parameters.length === 1) {
    return `(${shape.name} ${shape.parameters[0]})`;
  }
  return `(${shape.name} [${shape.parameters.join(", ")}])`;
}

function typeArgument(type: string): string {
  return /^[A-Za-z_][A-Za-z_0-9]*$/.test(type) ? type : `(${type})`;
}

function requirements(shape: DeriveShape, contract: string): string {
  const required = new Set(shape.parameters);
  for (const constructor of shape.constructors) {
    for (const field of constructor.fields) {
      let type = field.type;
      while (type.startsWith("Array ")) type = type.slice("Array ".length);
      if (
        shape.parameters.some((name) => new RegExp(`\\b${name}\\b`).test(type))
      ) required.add(type);
    }
  }
  return required.size
    ? ` where { ${
      [...required].map((type) => `${contract} ${typeArgument(type)}`).join(
        ", ",
      )
    } }`
    : "";
}

function formatField(type: string, value: string): string {
  if (!type.startsWith("Array ")) return `_derive_text.format ${value}`;
  const inner = type.slice("Array ".length);
  return `_derive_text.join "" #["[", _derive_text.join ", " (@array.generate ${value}.length (func index => return ${
    formatField(inner, `${value}[index]`)
  })), "]"]`;
}

/** Generate opt-in equality and debug formatting as overridable source. */
export function deriveEqualityAndDebug(
  shape: DeriveShape,
  operations: { equality?: boolean; debug?: boolean } = {},
): string {
  if (!shape.constructors.length) {
    throw new Error(`${shape.name} has no constructors`);
  }
  for (const constructor of shape.constructors) {
    for (const field of constructor.fields) {
      if (new RegExp(`\\b${shape.name}\\b`).test(field.type)) {
        throw new Error(
          `${shape.name}.${constructor.name}.${field.name}: recursive fields require handwritten operations`,
        );
      }
      if (field.type.includes("->")) {
        throw new Error(
          `${shape.name}.${constructor.name}.${field.name}: function field has no structural Eq, Format, or Codec operation`,
        );
      }
    }
  }
  const eqArms = shape.constructors.flatMap((constructor) => {
    const head = `  ${pattern(constructor, "l")}, ${
      pattern(constructor, "r")
    } =>`;
    if (!constructor.fields.length) return [`${head} true`];
    const lines = [`${head} do:`];
    constructor.fields.forEach((field, index) => {
      if (field.type.startsWith("Array ")) {
        lines.push(
          `    if l${index}.length != r${index}.length:`,
          `      break false`,
          `    let same${index} = true`,
          `    for index${index} in 0..l${index}.length:`,
          `      if Bool.not (_derive_eq.Eq.eq l${index}[index${index}] r${index}[index${index}]):`,
          `        same${index} := false`,
          `    if Bool.not same${index}:`,
          `      break false`,
        );
      } else {
        lines.push(
          `    if Bool.not (_derive_eq.Eq.eq l${index} r${index}):`,
          `      break false`,
        );
      }
    });
    lines.push(`    break true`);
    return lines;
  });
  const eq = [
    `const ${shape.name}.eq = func left => return func right => return case left, right of`,
    ...eqArms,
    `  _, _ => false`,
  ].join("\n");
  const parameter = shape.parameters.length === 0
    ? ""
    : shape.parameters.length === 1
    ? ` ${shape.parameters[0]}`
    : ` [${shape.parameters.join(", ")}]`;
  const requirement = requirements(shape, "_derive_text.Format");
  const equality =
    `impl ${shape.name}DerivedEquality${parameter} : _derive_eq.Eq ${
      typeHead(shape)
    }${
      requirements(shape, "_derive_eq.Eq")
    } = { const eq = func left => return func right => return ${shape.name}.eq left right }`;
  const formatArms = shape.constructors.map((constructor) => {
    const labels = constructor.fields.flatMap((field, index) => [
      JSON.stringify(`${index === 0 ? "(" : ", "}${field.name}=`),
      formatField(field.type, `v${index}`),
    ]);
    const pieces = [JSON.stringify(constructor.name), ...labels];
    if (labels.length) pieces.push(JSON.stringify(")"));
    return `    ${pattern(constructor, "v")} => _derive_text.join "" #[${
      pieces.join(", ")
    }]`;
  });
  const format = [
    `impl ${shape.name}DerivedFormat${parameter} : _derive_text.Format ${
      typeHead(shape)
    }${requirement} = {`,
    `  const format = func value => return case value of`,
    ...formatArms,
    `}`,
  ].join("\n");
  const equalitySource = operations.equality === false
    ? ""
    : `${eq}\n${equality}\n`;
  const debugSource = operations.debug === false ? "" : `${format}\n`;
  return equalitySource + debugSource;
}

export interface DeriveSchema {
  /** An application-owned format version. A changed version needs a migration. */
  version: number;
  variants: Record<string, { tag: number; fields: Record<string, number> }>;
}

function u32(value: number, label: string): number {
  if (!Number.isInteger(value) || value < 0 || value > 0xFFFFFFFF) {
    throw new Error(`${label} must be a U32`);
  }
  return value;
}

function checkedSchema(shape: DeriveShape, schema: DeriveSchema) {
  u32(schema.version, `${shape.name} schema version`);
  const tags = new Set<number>();
  for (const constructor of shape.constructors) {
    const variant = schema.variants[constructor.name];
    if (!variant) {
      throw new Error(
        `${shape.name}.${constructor.name}: missing variant schema`,
      );
    }
    const tag = u32(variant.tag, `${shape.name}.${constructor.name} tag`);
    if (tags.has(tag)) {
      throw new Error(`${shape.name}: duplicate variant tag ${tag}`);
    }
    tags.add(tag);
    const ids = new Set<number>();
    for (const field of constructor.fields) {
      const id = variant.fields[field.name];
      if (id === undefined) {
        throw new Error(
          `${shape.name}.${constructor.name}.${field.name}: missing field ID`,
        );
      }
      u32(id, `${shape.name}.${constructor.name}.${field.name} ID`);
      if (ids.has(id)) {
        throw new Error(
          `${shape.name}.${constructor.name}: duplicate field ID ${id}`,
        );
      }
      ids.add(id);
    }
    for (const field of Object.keys(variant.fields)) {
      if (!constructor.fields.some((item) => item.name === field)) {
        throw new Error(
          `${shape.name}.${constructor.name}.${field}: stale schema field`,
        );
      }
    }
  }
  for (const variant of Object.keys(schema.variants)) {
    if (!shape.constructors.some((item) => item.name === variant)) {
      throw new Error(`${shape.name}.${variant}: stale schema variant`);
    }
  }
}

/** Explicit scalar operations supplied by the owner of the Codec contract.
 * encode takes one scalar and returns one U32; decode returns Maybe scalar.
 * Both are checked with the rest of the emitted source by the native compiler.
 */
export interface CodecEmission {
  scalars?: Record<string, { encode: string; decode: string }>;
}

/** Emit strict framing directly into exact buffers; never rewrite emitted source. */
export function deriveCodec(
  shape: DeriveShape,
  schema: DeriveSchema,
  options: CodecEmission = {},
): string {
  for (const operation of Object.values(options.scalars ?? {})) {
    for (const name of [operation.encode, operation.decode]) {
      if (!/^[A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)*$/.test(name)) {
        throw new Error(`Invalid scalar codec operation: ${name}`);
      }
    }
  }
  for (const constructor of shape.constructors) {
    for (const field of constructor.fields) {
      if (new RegExp(`\\b${shape.name}\\b`).test(field.type)) {
        throw new Error(
          `${shape.name}.${constructor.name}.${field.name}: recursive fields require handwritten operations`,
        );
      }
      if (field.type.includes("->")) {
        throw new Error(
          `${shape.name}.${constructor.name}.${field.name}: function field has no structural Eq, Format, or Codec operation`,
        );
      }
    }
  }
  checkedSchema(shape, schema);
  const plans = shape.constructors.map((constructor) => {
    const variant = schema.variants[constructor.name];
    const fields = constructor.fields.map((field, index) => ({
      ...field,
      index,
      id: variant.fields[field.name],
      scalar: options.scalars?.[field.type],
    })).sort((a, b) => a.id - b.id);
    return {
      constructor,
      variant,
      fields,
      fixed: fields.every((field) => field.scalar),
    };
  });
  const encodeName = `_derive_${shape.name.toLowerCase()}_encode`;
  const encodeArms = plans.flatMap(
    ({ constructor, variant, fields, fixed }) => {
      const lines = [`  ${pattern(constructor, "v")} => do:`];
      if (fixed) {
        const words: (string | number)[] = [
          schema.version,
          variant.tag,
          fields.length,
        ];
        for (const f of fields) {
          words.push(f.id, 1, `${f.scalar!.encode} v${f.index}`);
        }
        lines.push(`    break #[${words.join(", ")}]`);
        return lines;
      }
      for (const field of fields) {
        if (field.type.startsWith("Array ")) {
          lines.push(
            `    let collected${field.index}: List U32 = [v${field.index}.length]`,
            `    for item${field.index} in v${field.index}:`,
            `      let item_words${field.index} = _derive_codec.encode item${field.index}`,
            `      collected${field.index} := [...self, item_words${field.index}.length]`,
            `      for word${field.index} in item_words${field.index}:`,
            `        collected${field.index} := [...self, word${field.index}]`,
            `    let payload${field.index} = Array.from_list collected${field.index}`,
          );
        } else {lines.push(
            `    let payload${field.index} = _derive_codec.encode v${field.index}`,
          );}
      }
      lines.push(
        `    let out = @array.fill (${
          [
            3 + 2 * fields.length,
            ...fields.map((f) => `payload${f.index}.length`),
          ].join(" + ")
        }) 0`,
        `    out[0] := ${schema.version}`,
        `    out[1] := ${variant.tag}`,
        `    out[2] := ${fields.length}`,
      );
      if (fields.length) lines.push("    let cursor = 3");
      fields.forEach((f, index) => {
        lines.push(
          `    out[cursor] := ${f.id}`,
          `    out[cursor + 1] := payload${f.index}.length`,
          `    for index in 0 .. payload${f.index}.length:`,
          `      out[cursor + 2 + index] := payload${f.index}[index]`,
        );
        if (index + 1 < fields.length) {
          lines.push(`    cursor := self + 2 + payload${f.index}.length`);
        }
      });
      lines.push("    break out");
      return lines;
    },
  );
  const parameter = shape.parameters.length === 0
    ? ""
    : shape.parameters.length === 1
    ? ` ${shape.parameters[0]}`
    : ` [${shape.parameters.join(", ")}]`;
  const requirement = requirements(shape, "_derive_codec.Codec");
  const encodeAnnotation = shape.parameters.length
    ? `: ${typeHead(shape)} -> Array U32${requirement}`
    : "";
  const decodeArms = plans.flatMap(
    ({ constructor, variant, fields, fixed }) => {
      const lines = [
        `    if tag == ${variant.tag}:`,
        `      if count != ${fields.length}:`,
        "        return $Nothing",
      ];
      if (fixed) {
        lines.push(
          `      if words.length != ${3 + fields.length * 3}:`,
          "        return $Nothing",
        );
      } else lines.push("      let cursor = 3");
      fields.forEach((field, position) => {
        if (fixed) {
          const offset = 3 + 3 * position;
          lines.push(
            `      if words[${offset}] != ${field.id} or words[${
              offset + 1
            }] != 1:`,
            "        return $Nothing",
            `      let $Some value${field.index} = ${
              field.scalar!.decode
            } words[${offset + 2}] else:`,
            "        return $Nothing",
          );
          return;
        }
        lines.push(
          "      if words.length - cursor < 2:",
          "        return $Nothing",
          `      if words[cursor] != ${field.id}:`,
          "        return $Nothing",
          `      let width${position} = words[cursor + 1]`,
          "      cursor := self + 2",
          `      if width${position} > words.length - cursor:`,
          "        return $Nothing",
          `      let payload${position} = @array.slice words cursor width${position}`,
          `      cursor := self + width${position}`,
        );
        if (field.type.startsWith("Array ")) {
          const element = field.type.slice("Array ".length);
          lines.push(
            `      if payload${position}.length == 0:`,
            "        return $Nothing",
            `      let element_count${field.index} = payload${position}[0]`,
            `      if element_count${field.index} > payload${position}.length - 1:`,
            "        return $Nothing",
            `      let cursor${field.index} = 1`,
            `      let elements${field.index}: List ${
              typeArgument(element)
            } = []`,
            `      for ignored${field.index} in 0..element_count${field.index}:`,
            `        if cursor${field.index} >= payload${position}.length:`,
            "          return $Nothing",
            `        let element_width${field.index} = payload${position}[cursor${field.index}]`,
            `        cursor${field.index} := self + 1`,
            `        if element_width${field.index} > payload${position}.length - cursor${field.index}:`,
            "          return $Nothing",
            `        let item_words${field.index} = @array.slice payload${position} cursor${field.index} element_width${field.index}`,
            `        let item_decoded${field.index}: Maybe ${
              typeArgument(element)
            } = _derive_codec.Codec.decode item_words${field.index}`,
            `        let $Some item${field.index} = item_decoded${field.index} else:`,
            "          return $Nothing",
            `        elements${field.index} := [...self, item${field.index}]`,
            `        cursor${field.index} := self + element_width${field.index}`,
            `      if cursor${field.index} != payload${position}.length:`,
            "        return $Nothing",
            `      let value${field.index} = Array.from_list elements${field.index}`,
          );
        } else {lines.push(
            `      let decoded${field.index}: Maybe ${
              typeArgument(field.type)
            } = _derive_codec.Codec.decode payload${position}`,
            `      let $Some value${field.index} = decoded${field.index} else:`,
            "        return $Nothing",
          );}
      });
      if (!fixed) {
        lines.push(
          "      if cursor != words.length:",
          "        return $Nothing",
        );
      }
      const values = constructor.fields.map((field, index) =>
        constructor.payload === "record"
          ? `${field.name}: value${index}`
          : `value${index}`
      );
      const constructed = constructor.payload === "none"
        ? `$${constructor.name}`
        : constructor.payload === "record"
        ? `$${constructor.name} { ${values.join(", ")} }`
        : constructor.payload === "product"
        ? `$${constructor.name} (${values.join(", ")})`
        : `$${constructor.name} ${values[0]}`;
      lines.push(`      return $Some (${constructed})`);
      return lines;
    },
  );
  return [
    `const ${encodeName}${encodeAnnotation} = func value => return case value of`,
    ...encodeArms,
    `impl ${shape.name}DerivedCodec${parameter} : _derive_codec.Codec ${
      typeHead(shape)
    }${requirement} = {`,
    `  const encode = func value => return ${encodeName} value,`,
    "  const decode = func words => return do:",
    `    if words.length < 3 or words[0] != ${schema.version}:`,
    "      return $Nothing",
    "    let tag = words[1]",
    "    let count = words[2]",
    ...decodeArms,
    "    break $Nothing",
    "}",
    "",
  ].join("\n");
}
