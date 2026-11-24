// Original Ink operations. Expected streams below do not call compiler output.
const packing =
  `const pack = func (vectors: #[math.Vec4]) -> (draws: #[render.Draw]) -> (prefix: &[math.Vec4]): #[F32] => return do:
  let output: #[F32] = #[]
  @storage.push output (U32.to_f32 vectors.length)
  for value in vectors:
    @storage.push output value.x
    @storage.push output value.y
    @storage.push output value.z
    @storage.push output value.w
  @storage.push output (U32.to_f32 draws.length)
  for draw in draws:
    @storage.push output (U32.to_f32 draw.mesh)
    @storage.push output (U32.to_f32 draw.material)
    for lane in math.Mat4.lanes draw.matrix:
      @storage.push output lane
    case draw.parameters of
      $Nothing => @storage.push output 0.0
      $Some value => do:
        @storage.push output 1.0
        @storage.push output value.x
        @storage.push output value.y
        @storage.push output value.z
        @storage.push output value.w
    @storage.push output (U32.to_f32 draw.extra.count)
    for index in 0 .. draw.extra.count:
      let value = vectors[@u32.add draw.extra.start index]
      @storage.push output value.x
      @storage.push output value.y
      @storage.push output value.z
      @storage.push output value.w
  for value in prefix:
    @storage.push output value.x
    @storage.push output value.y
    @storage.push output value.z
    @storage.push output value.w
  return output
`;
export function ownedRenderSource(
  callers: number,
  operation: "owned" | "emit" = "owned",
): string {
  let source = `import * as render from "ink/render"
import * as math from "ink/math"
${packing}
entry const stream = func (input: U32) => return do:
  let access = render.empty_frame ()
  @storage.push access.vectors (math.vec4 (-1.0) (-0.0) 10.0 11.0)
  @storage.push access.vectors (math.vec4 (-2.0) 12.0 13.0 14.0)
`;
  for (let at = 0; at < callers; at++) {
    let parameters = "$Nothing";
    if (at % 2 === 0) {
      parameters = `$Some (math.vec4 (U32.to_f32 input) ${
        at + 1
      }.0 (-0.0) (-1.0))`;
    }
    source +=
      `  let extra_${at}: #[math.Vec4] = #[math.vec4 (U32.to_f32 input) ${
        at + 1
      }.0 2.0 (-0.0), math.vec4 ${at + 3}.0 4.0 5.0 6.0]
`;
    if (operation === "owned") {
      source +=
        `  access := render.push_extra ($render.Draw {mesh: ${
          at + 1
        }, material: ${
          at + 11
        }, matrix: math.Mat4.identity, parameters: ${parameters}, extra: render.no_span}) (&extra_${at}[0..2]) self
`;
    } else {
      source +=
        `  let (span_${at}, next_${at}) = render.store_vectors (&extra_${at}[0..2]) access
  let rows_${at}: #[render.Draw] = #[$render.Draw {mesh: ${
          at + 1
        }, material: ${
          at + 11
        }, matrix: math.Mat4.identity, parameters: ${parameters}, extra: span_${at}}]
  access := render.emit rows_${at} next_${at}
`;
    }
  }
  source += `  let prefix = &access.vectors[0..2]
  return pack access.vectors access.draws prefix
entry const overlap = func (input: U32) => return do:
  let seed: #[math.Vec4] = #[math.vec4 (U32.to_f32 input) 1.0 2.0 (-0.0), math.vec4 3.0 4.0 5.0 6.0, math.vec4 7.0 8.0 9.0 10.0]
  let access = render.empty_frame ()
  let (_, access) = render.store_vectors (&seed[0..3]) access
  access := render.push_extra ($render.Draw {mesh: 1, material: 2, matrix: math.Mat4.identity, parameters: $Some (math.vec4 (-0.0) 0.0 2.0 3.0), extra: render.no_span}) (&seed[0..2]) self
  access := render.push_extra ($render.Draw {mesh: 3, material: 4, matrix: math.Mat4.identity, parameters: $Nothing, extra: render.no_span}) (&seed[1..3]) self
  let prefix = &access.vectors[0..3]
  return pack access.vectors access.draws prefix
entry const self_rows = func (input: U32) => return do:
  let seed: #[math.Vec4] = #[math.vec4 (U32.to_f32 input) 1.0 2.0 (-0.0), math.vec4 3.0 4.0 5.0 6.0]
  let access = render.empty_frame ()
  access := render.push_extra ($render.Draw {mesh: 5, material: 6, matrix: math.Mat4.identity, parameters: $Nothing, extra: render.no_span}) (&seed[0..2]) self
  let snap1 = @storage.copy access.draws
  for draw in snap1:
    let extra = @storage.copy access.vectors
    access := render.push_extra draw (&extra[draw.extra.start..@u32.add draw.extra.start draw.extra.count]) self
  let snap2 = @storage.copy access.draws
  for draw in snap2:
    let extra = @storage.copy access.vectors
    access := render.push_extra draw (&extra[draw.extra.start..@u32.add draw.extra.start draw.extra.count]) self
  let prefix = &access.vectors[0..2]
  return pack access.vectors access.draws prefix
entry const empty_after_freeze = func (input: U32) => return do:
  let access = render.empty_frame ()
  let empty: #[render.Draw] = #[]
  access := render.emit empty self
  let frozen_vectors = freeze access.vectors
  let frozen_draws = freeze access.draws
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
    return pack([a, b, c, a, b, b, c], [
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
    vectors.push(...extra);
    const draw: Draw = { mesh: at + 1, material: at + 11, extra };
    if (at % 2 === 0) draw.parameters = [input, at + 1, -0, -1];
    draws.push(draw);
  }
  return pack(vectors, draws, prefix);
}
