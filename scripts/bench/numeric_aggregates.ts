/** The same sixteen F32 lanes, represented structurally or nominally. */
export const numericShapes = [
  ["structural_nested", false, true],
  ["structural_flat", false, false],
  ["nominal_nested", true, true],
  ["nominal_flat", true, false],
] as const;

export function numericAggregateSources() {
  const axes = ["a", "b", "c", "d"], lanes = ["x", "y", "z", "w"];
  const fields = axes.flatMap((axis, i) =>
    lanes.map((lane, j) => ({ name: axis + lane, axis, lane, n: i * 4 + j }))
  );
  let shapes = "";
  let main = 'import * as shape from "./shapes"\n';
  main += "const apply = fn callback value => callback value\n";
  for (const [id, nominal, nested] of numericShapes) {
    const name = id === "nominal_nested" ? "Nested" : "Flat";
    const vector = "{x: F32, y: F32, z: F32, w: F32}";
    const structure = nested
      ? `{${axes.map((a) => `${a}: ${vector}`).join(", ")}}`
      : `{${fields.map((f) => `${f.name}: F32`).join(", ")}}`;
    if (nominal) {
      if (nested) shapes += `type Vector is data = #Vector ${vector}\n`;
      const body = nested
        ? `{${axes.map((a) => `${a}: Vector`).join(", ")}}`
        : structure;
      shapes += `type ${name} is data = #${name} ${body}\n`;
    }
    const payload = nested
      ? axes.map((a, i) =>
        `${a}: ${nominal ? "#Vector " : ""}{${
          lanes.map((l, j) => `${l}: seed + ${i * 4 + j}.0`).join(", ")
        }}`
      ).join(", ")
      : fields.map((f) => `${f.name}: seed + ${f.n}.0`).join(", ");
    const projections = fields.map((f) =>
      nested ? `value.${f.axis}.${f.lane}` : `value.${f.name}`
    );
    shapes += `const make_${id} = fn (seed: F32) => ${
      nominal ? "#" + name + " " : ""
    }{${payload}}\n`;
    shapes += `const read_${id} = fn (value: ${
      nominal ? name : structure
    }) => ${projections.join(" + ")}\n`;
    shapes += `const alternate_${id} = fn (value: ${
      nominal ? name : structure
    }) => read_${id} value\n`;
    shapes += `const wire_${id} = fn (value: ${
      nominal ? name : structure
    }) => #[${projections.join(", ")}]\n`;
    main +=
      `entry const direct_${id} = fn (seed: F32) => shape.read_${id} (shape.make_${id} seed)\n`;
    main +=
      `entry const callback_${id} = fn (seed: F32) => apply shape.read_${id} (shape.make_${id} seed)\n`;
    main += `entry const dynamic_${id} = fn (choice: Bool) => do:
  let read = if choice then shape.read_${id} else shape.alternate_${id}
  return read (shape.make_${id} 5.0)
`;
    main += `entry const array_${id} = fn (count: U32) => do:
  let values = @array.generate count (fn index => shape.make_${id} (@u32.to_f32 index))
  let total = 0.0
  for value in values:
    total := self + shape.read_${id} value
  return total
entry const snapshot_${id} = fn (count: U32) => do:
  let values = @array.generate count (fn index => shape.make_${id} (@u32.to_f32 index))
  let old = values
  values[0] := shape.make_${id} 1000.0
  return shape.read_${id} values[0] + shape.read_${id} old[0]
entry const wire_${id} = fn (seed: F32) => shape.wire_${id} (shape.make_${id} seed)
entry const stored_wire_${id} = fn (seed: F32) => do:
  let values = @array.fill 2 (shape.make_${id} seed)
  return shape.wire_${id} values[1]
entry const constant_${id} = fn () => do:
  let values = #[shape.make_${id} 0.0, shape.make_${id} 1.0]
  return shape.read_${id} values[1]
entry const nested_edit_${id} = fn (seed: F32) => do:
  let values = @array.fill 2 (shape.make_${id} 1.0)
  let old = values
  values[0].${nested ? "a.x" : "ax"} := seed
  return shape.read_${id} values[0] + shape.read_${id} old[0]
entry const list_${id} = fn (count: U32) => do:
  let values = @list.from_array (@array.generate count (fn index => shape.make_${id} (@u32.to_f32 index)))
  let old = values
  values := @list.concat [shape.make_${id} 1000.0] (@list.slice self 1 (count - 1))
  let copied = @array.from_list values
  let total = 0.0
  for value in copied:
    total := self + shape.read_${id} value
  return total + shape.read_${id} (@cursor.value (@list.cursor old))
`;
  }
  return { main, shapes };
}
