// Original Ink operations. Expected streams below do not call compiler output.
const frame = `  let settings: Array render.Settings = #[render.defaults]
  let solids: ResizeArray render.Solid = #[]
  let decals: ResizeArray render.Decal = #[]
  let sprites: ResizeArray render.Sprite = #[]
  let insets: ResizeArray render.Inset = #[]
  let fields: ResizeArray render.Field = #[]
  let poses: ResizeArray render.Pose = #[]
  let emitters: ResizeArray render.Emitter = #[]
  let extensions: ResizeArray render.Extension = #[]
  let updates: ResizeArray render.Instance = #[]
  let removed: ResizeArray U32 = #[]
  let access = $render.FrameAccess {settings, draws, solids, decals, sprites, insets, fields, poses, emitters, extensions, updates, removed}
`;
const packing =
  `const pack = func (vectors: ResizeArray math.Vec4) -> (draws: ResizeArray render.Draw) -> (prefix: &[math.Vec4]) => return do:
  let output: GrowArray F32 = #[]
  output.push (U32.to_f32 vectors.length)
  for value in vectors:
    output.push value.x
    output.push value.y
    output.push value.z
    output.push value.w
  output.push (U32.to_f32 draws.length)
  for draw in draws:
    output.push (U32.to_f32 draw.mesh)
    output.push (U32.to_f32 draw.material)
    for lane in math.Mat4.lanes draw.matrix:
      output.push lane
    case draw.parameters of
      $Nothing => output.push 0.0
      $Some value => do:
        output.push 1.0
        output.push value.x
        output.push value.y
        output.push value.z
        output.push value.w
    output.push (U32.to_f32 draw.extra.length)
    for value in draw.extra:
      output.push value.x
      output.push value.y
      output.push value.z
      output.push value.w
  for value in prefix:
    output.push value.x
    output.push value.y
    output.push value.z
    output.push value.w
  return @storage.freeze output
`;
export function ownedRenderSource(
  callers: number,
  operation: "owned" | "emit" = "owned",
): string {
  let source = `import * as render from "ink/render"
import * as math from "ink/math"
${packing}
entry const stream = func (input: U32) => return do:
  let vectors: ResizeArray math.Vec4 = #[math.vec4 (-1.0) (-0.0) 10.0 11.0, math.vec4 (-2.0) 12.0 13.0 14.0]
  let prefix = &vectors[0..2]
  let draws: ResizeArray render.Draw = #[]
${frame}`;
  for (let at = 0; at < callers; at++) {
    let parameters = "$Nothing";
    if (at % 2 === 0) {
      parameters = `$Some (math.vec4 (U32.to_f32 input) ${
        at + 1
      }.0 (-0.0) (-1.0))`;
    }
    let call = `render.emit_owned rows_${at} vectors access`;
    if (operation === "emit") call = `render.emit rows_${at} access`;
    source +=
      `  let extra_${at}: Array math.Vec4 = #[math.vec4 (U32.to_f32 input) ${
        at + 1
      }.0 2.0 (-0.0), math.vec4 ${at + 3}.0 4.0 5.0 6.0]
  let rows_${at}: Array render.Draw = #[$render.Draw {mesh: ${
        at + 1
      }, material: ${
        at + 11
      }, matrix: math.Mat4.identity, parameters: ${parameters}, extra: &extra_${at}[0..2]}]
  ${call}
`;
  }
  source += `  return pack vectors draws prefix
entry const overlap = func (input: U32) => return do:
  let vectors: ResizeArray math.Vec4 = #[math.vec4 (U32.to_f32 input) 1.0 2.0 (-0.0), math.vec4 3.0 4.0 5.0 6.0, math.vec4 7.0 8.0 9.0 10.0]
  let prefix = &vectors[0..3]
  let left = $render.Draw {mesh: 1, material: 2, matrix: math.Mat4.identity, parameters: $Some (math.vec4 (-0.0) 0.0 2.0 3.0), extra: &vectors[0..2]}
  let right = $render.Draw {mesh: 3, material: 4, matrix: math.Mat4.identity, parameters: $Nothing, extra: &vectors[1..3]}
  let first = render.store_draw left vectors
  let second = render.store_draw right vectors
  let copied = @array.generate first.extra.length (func index => return first.extra[index])
  @storage.push vectors copied[0]
  let draws: ResizeArray render.Draw = #[first, second]
  return pack vectors draws prefix
entry const self_rows = func (input: U32) => return do:
  let vectors: ResizeArray math.Vec4 = #[math.vec4 (U32.to_f32 input) 1.0 2.0 (-0.0), math.vec4 3.0 4.0 5.0 6.0]
  let prefix = &vectors[0..2]
  let draws: ResizeArray render.Draw = #[$render.Draw {mesh: 5, material: 6, matrix: math.Mat4.identity, parameters: $Nothing, extra: prefix}]
${frame}  render.emit_owned (&draws[0..1]) vectors access
  render.emit_owned (&draws[0..2]) vectors access
  return pack vectors draws prefix
entry const empty_after_freeze = func (input: U32) => return do:
  let vectors: ResizeArray math.Vec4 = #[]
  let draws: ResizeArray render.Draw = #[]
  let frozen_vectors = @storage.freeze vectors
  let frozen_draws = @storage.freeze draws
${frame}  let empty: Array render.Draw = #[]
  render.emit_owned empty vectors access
  return #[U32.to_f32 input, U32.to_f32 frozen_vectors.length, U32.to_f32 frozen_draws.length]
`;
  return source;
}
type Vector = readonly number[];
type Draw = {
  mesh: number;
  material: number;
  parameters?: Vector;
  extra: Vector[];
};
function pack(
  vectors: Vector[],
  draws: Draw[],
  prefix: Vector[],
): Float32Array<ArrayBuffer> {
  const result = [
    vectors.length,
    ...vectors.flatMap((value) => [...value]),
    draws.length,
  ];
  for (const draw of draws) {
    result.push(
      draw.mesh,
      draw.material,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
    );
    if (draw.parameters) result.push(1, ...draw.parameters);
    else result.push(0);
    result.push(
      draw.extra.length,
      ...draw.extra.flatMap((value) => [...value]),
    );
  }
  result.push(...prefix.flatMap((value) => [...value]));
  return new Float32Array(result);
}
export function expectedRenderStream(
  entry: string,
  callers: number,
  input: number,
  operation: "owned" | "emit" = "owned",
): Float32Array<ArrayBuffer> {
  if (entry === "empty_after_freeze") return new Float32Array([input, 0, 0]);
  const a = [input, 1, 2, -0];
  const b = [3, 4, 5, 6];
  if (entry === "overlap") {
    const c = [7, 8, 9, 10];
    return pack([a, b, c, a, b, b, c, a], [
      { mesh: 1, material: 2, parameters: [-0, 0, 2, 3], extra: [a, b] },
      { mesh: 3, material: 4, extra: [b, c] },
    ], [a, b, c]);
  }
  if (entry === "self_rows") {
    const draw: Draw = { mesh: 5, material: 6, extra: [a, b] };
    return pack([a, b, a, b, a, b, a, b], [draw, draw, draw, draw], [a, b]);
  }
  const prefix = [[-1, -0, 10, 11], [-2, 12, 13, 14]];
  const vectors: Vector[] = [...prefix];
  const draws = [];
  for (let at = 0; at < callers; at++) {
    const extra = [[input, at + 1, 2, -0], [at + 3, 4, 5, 6]];
    if (operation === "owned") vectors.push(...extra);
    const draw: Draw = { mesh: at + 1, material: at + 11, extra };
    if (at % 2 === 0) draw.parameters = [input, at + 1, -0, -1];
    draws.push(draw);
  }
  return pack(vectors, draws, prefix);
}
