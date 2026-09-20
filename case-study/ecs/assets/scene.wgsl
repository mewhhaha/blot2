struct Scene {
  view: mat4x4f,
  projection: mat4x4f,
  ambient: vec4f,
  light_direction: vec4f,
  light_color: vec4f,
};
struct Draw {
  model: mat4x4f,
  normal: mat4x4f,
  color: vec4f,
  settings: vec4f,
};
@group(0) @binding(0) var<uniform> scene: Scene;
@group(1) @binding(0) var<uniform> draw: Draw;
@group(1) @binding(1) var base_color: texture_2d<f32>;
@group(1) @binding(2) var base_sampler: sampler;
struct VertexInput {
  @location(0) position: vec3f,
  @location(1) normal: vec3f,
  @location(2) uv: vec2f,
};
struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) normal: vec3f,
  @location(1) uv: vec2f,
};
@vertex fn vertex(input: VertexInput) -> VertexOutput {
  var output: VertexOutput;
  output.position = scene.projection * scene.view * draw.model * vec4f(input.position, 1.0);
  output.normal = (draw.normal * vec4f(input.normal, 0.0)).xyz;
  output.uv = input.uv;
  return output;
}
@fragment fn fragment(input: VertexOutput) -> @location(0) vec4f {
  let texture_color = textureSample(base_color, base_sampler, input.uv).rgb;
  let diffuse = max(dot(normalize(input.normal), normalize(-scene.light_direction.xyz)), 0.0);
  let illumination = mix(vec3f(1.0), scene.ambient.xyz + scene.light_color.xyz * diffuse, draw.settings.x);
  return vec4f(draw.color.rgb * texture_color * illumination, 1.0);
}
