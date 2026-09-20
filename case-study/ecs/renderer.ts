import { decodeTexture } from "./texture.ts";
import {
  createAssetStore,
  type Material,
  type Mesh,
  parseMaterial,
  parseMesh,
  resolveAssetPath,
} from "./asset_store.ts";
import type { GameEvent, PickHit, Point, RenderFrame } from "./protocol.ts";

type GpuAsset =
  | {
    readonly kind: "mesh";
    readonly vertices: GPUBuffer;
    readonly indices: GPUBuffer;
    readonly count: number;
    destroy(): void;
  }
  | { readonly kind: "material"; readonly material: Material; destroy(): void }
  | {
    readonly kind: "shader";
    readonly pipeline: GPURenderPipeline;
    destroy(): void;
  }
  | { readonly kind: "texture"; readonly texture: GPUTexture; destroy(): void };

export function validateFrame(frame: RenderFrame): void {
  for (
    const matrix of [
      frame.view,
      frame.projection,
      ...frame.draws.map((draw) => draw.transform),
    ]
  ) {
    if (
      matrix.length !== 16 ||
      [...matrix].some((value) =>
        !Number.isFinite(value) || !Number.isFinite(Math.fround(value))
      )
    ) {
      throw new RangeError(
        "render matrices must contain 16 finite float32 values",
      );
    }
  }
  for (
    const vector of [frame.ambient, frame.light_color, frame.light_direction]
  ) {
    if (
      [vector.x, vector.y, vector.z].some((value) =>
        !Number.isFinite(value) || !Number.isFinite(Math.fround(value))
      )
    ) {
      throw new RangeError(
        "render lighting must contain finite float32 values",
      );
    }
  }
  if (
    Math.hypot(
      frame.light_direction.x,
      frame.light_direction.y,
      frame.light_direction.z,
    ) < 1e-8
  ) throw new RangeError("light direction must be nonzero");
  if (
    [frame.clear.r, frame.clear.g, frame.clear.b, frame.clear.a].some((value) =>
      !Number.isFinite(value) || value < 0 || value > 1
    )
  ) throw new RangeError("clear color must have 0..1 channels");
  for (const draw of frame.draws) {
    if (draw.mesh.length === 0 || draw.material.length === 0) {
      throw new RangeError("draw must name a mesh and material");
    }
    if (
      draw.entity !== undefined &&
      (!Number.isInteger(draw.entity) || draw.entity < 0 ||
        draw.entity > 0xffffffff)
    ) throw new RangeError("draw entity must be a U32");
    normalMatrix(draw.transform);
    if (
      draw.transform[3] !== 0 || draw.transform[7] !== 0 ||
      draw.transform[11] !== 0 || draw.transform[15] !== 1
    ) throw new RangeError("draw transform must be affine");
  }
}

function normalMatrix(matrix: readonly number[]): number[] {
  const [a, b, c, , d, e, f, , g, h, i] = matrix;
  const determinant = a * (e * i - f * h) - d * (b * i - c * h) +
    g * (b * f - c * e);
  if (!Number.isFinite(determinant) || Math.abs(determinant) < 1e-12) {
    throw new RangeError("draw transform must be invertible");
  }
  const normal = [
    (e * i - f * h) / determinant,
    (f * g - d * i) / determinant,
    (d * h - e * g) / determinant,
    0,
    (c * h - b * i) / determinant,
    (a * i - c * g) / determinant,
    (b * g - a * h) / determinant,
    0,
    (b * f - c * e) / determinant,
    (c * d - a * f) / determinant,
    (a * e - b * d) / determinant,
    0,
    0,
    0,
    0,
    1,
  ];
  if (normal.some((value) => !Number.isFinite(Math.fround(value)))) {
    throw new RangeError("draw normal matrix exceeds float32 range");
  }
  return normal;
}

type Triple = readonly [number, number, number];
const subtract = (
  a: Triple,
  b: Triple,
): Triple => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const dot = (a: Triple, b: Triple): number =>
  a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a: Triple, b: Triple): Triple => [
  a[1] * b[2] - a[2] * b[1],
  a[2] * b[0] - a[0] * b[2],
  a[0] * b[1] - a[1] * b[0],
];

function multiply(a: readonly number[], b: readonly number[]): number[] {
  return Array.from({ length: 16 }, (_, index) => {
    const row = index % 4;
    const column = Math.floor(index / 4) * 4;
    return a[row] * b[column] + a[row + 4] * b[column + 1] +
      a[row + 8] * b[column + 2] + a[row + 12] * b[column + 3];
  });
}

function inverse(matrix: readonly number[]): number[] {
  const rows = Array.from({ length: 4 }, (_, row) => [
    ...Array.from({ length: 4 }, (_, column) => matrix[column * 4 + row]),
    ...Array.from({ length: 4 }, (_, column) => +(column === row)),
  ]);
  for (let column = 0; column < 4; column++) {
    let pivot = column;
    for (let row = column + 1; row < 4; row++) {
      if (Math.abs(rows[row][column]) > Math.abs(rows[pivot][column])) {
        pivot = row;
      }
    }
    [rows[pivot], rows[column]] = [rows[column], rows[pivot]];
    const divisor = rows[column][column];
    if (divisor === 0) {
      throw new RangeError("picking requires invertible camera matrices");
    }
    rows[column] = rows[column].map((value) => value / divisor);
    for (let row = 0; row < 4; row++) {
      if (row === column) continue;
      const factor = rows[row][column];
      rows[row] = rows[row].map((value, index) =>
        value - factor * rows[column][index]
      );
    }
  }
  const result = Array.from(
    { length: 16 },
    (_, index) => rows[index % 4][4 + Math.floor(index / 4)],
  );
  if (result.some((value) => !Number.isFinite(value))) {
    throw new RangeError("picking camera inverse is not finite");
  }
  return result;
}

function transform(matrix: readonly number[], point: Triple): Triple {
  const [x, y, z] = point;
  const w = matrix[3] * x + matrix[7] * y + matrix[11] * z + matrix[15];
  if (w === 0) throw new RangeError("picking point is at infinity");
  return [
    (matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12]) / w,
    (matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13]) / w,
    (matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14]) / w,
  ];
}

function triangleDistance(
  origin: Triple,
  direction: Triple,
  a: Triple,
  b: Triple,
  c: Triple,
): number | undefined {
  const ab = subtract(b, a);
  const ac = subtract(c, a);
  const p = cross(direction, ac);
  const determinant = dot(ab, p);
  // The GPU pipeline draws CCW front faces only. Degenerate/back faces miss.
  if (determinant <= 0) return;
  const t = subtract(origin, a);
  const u = dot(t, p) / determinant;
  if (u < 0 || u > 1) return;
  const q = cross(t, ab);
  const v = dot(direction, q) / determinant;
  if (v < 0 || u + v > 1) return;
  const distance = dot(ac, q) / determinant;
  return distance >= 0 && Number.isFinite(distance) ? distance : undefined;
}

export function createRenderer(options: {
  readonly device: GPUDevice;
  readonly format: GPUTextureFormat;
  readonly rootDirectory: string;
  readonly target: {
    size(): readonly [number, number];
    view(): GPUTextureView;
    present(): void;
  };
  readonly event: (event: GameEvent) => void;
}) {
  const { device } = options;
  const geometry = new WeakMap<GPUBuffer, Mesh>();
  const checkedGpu = async <T>(
    create: () => T,
    discard: (candidate: T) => void,
  ): Promise<T> => {
    device.pushErrorScope("out-of-memory");
    device.pushErrorScope("validation");
    let candidate: T | undefined;
    let failure: { error: unknown } | undefined;
    try {
      candidate = create();
    } catch (error) {
      failure = { error };
    }
    // Pop synchronously before yielding: concurrent asset loads share a device.
    const validation = device.popErrorScope();
    const allocation = device.popErrorScope();
    try {
      const errors = (await Promise.all([validation, allocation])).filter(
        (error) => error !== null,
      );
      if (failure !== undefined) throw failure.error;
      if (errors.length > 0) {
        throw new Error(errors.map((error) => error.message).join("\n"));
      }
      return candidate!;
    } catch (error) {
      if (candidate !== undefined) discard(candidate);
      throw error;
    }
  };
  const sceneLayout = device.createBindGroupLayout({
    entries: [{
      binding: 0,
      visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
      buffer: { type: "uniform", minBindingSize: 176 },
    }],
  });
  const drawLayout = device.createBindGroupLayout({
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
        buffer: {
          type: "uniform",
          hasDynamicOffset: true,
          minBindingSize: 160,
        },
      },
      { binding: 1, visibility: GPUShaderStage.FRAGMENT, texture: {} },
      { binding: 2, visibility: GPUShaderStage.FRAGMENT, sampler: {} },
    ],
  });
  const layout = device.createPipelineLayout({
    bindGroupLayouts: [sceneLayout, drawLayout],
  });
  const sceneUniform = device.createBuffer({
    size: 176,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  const sceneGroup = device.createBindGroup({
    layout: sceneLayout,
    entries: [{ binding: 0, resource: { buffer: sceneUniform } }],
  });
  const stride =
    Math.ceil(160 / device.limits.minUniformBufferOffsetAlignment) *
    device.limits.minUniformBufferOffsetAlignment;
  let capacity = 1;
  let drawUniform = device.createBuffer({
    size: stride,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  let groups = new WeakMap<GPUTexture, GPUBindGroup>();
  const sampler = device.createSampler({
    magFilter: "linear",
    minFilter: "linear",
    addressModeU: "repeat",
    addressModeV: "repeat",
  });
  const textureFrom = (
    width: number,
    height: number,
    pixels: Uint8Array<ArrayBuffer>,
  ): GPUTexture => {
    if (
      !Number.isSafeInteger(width) || width < 1 ||
      !Number.isSafeInteger(height) || height < 1 ||
      width > device.limits.maxTextureDimension2D ||
      height > device.limits.maxTextureDimension2D ||
      pixels.length !== width * height * 4
    ) throw new RangeError("texture exceeds device dimensions");
    const texture = device.createTexture({
      size: [width, height],
      format: "rgba8unorm-srgb",
      usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
    });
    try {
      device.queue.writeTexture({ texture }, pixels, {
        bytesPerRow: width * 4,
        rowsPerImage: height,
      }, [width, height]);
    } catch (error) {
      texture.destroy();
      throw error;
    }
    return texture;
  };
  const white = textureFrom(1, 1, new Uint8Array([255, 255, 255, 255]));
  const assets = createAssetStore<GpuAsset>({
    rootDirectory: options.rootDirectory,
    event: options.event,
    async prepare(kind, _key, bytes, requireAsset): Promise<GpuAsset> {
      switch (kind) {
        case "mesh": {
          const mesh = parseMesh(bytes);
          if (
            Math.max(mesh.vertices.byteLength, mesh.indices.byteLength) >
              device.limits.maxBufferSize
          ) throw new RangeError("mesh exceeds device buffer size");
          return await checkedGpu(() => {
            const vertices = device.createBuffer({
              size: mesh.vertices.byteLength,
              usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
            });
            let indices: GPUBuffer | undefined;
            try {
              indices = device.createBuffer({
                size: mesh.indices.byteLength,
                usage: GPUBufferUsage.INDEX | GPUBufferUsage.COPY_DST,
              });
              device.queue.writeBuffer(vertices, 0, mesh.vertices);
              device.queue.writeBuffer(indices, 0, mesh.indices);
            } catch (error) {
              vertices.destroy();
              indices?.destroy();
              throw error;
            }
            geometry.set(vertices, mesh);
            const indexBuffer = indices;
            return {
              kind,
              vertices,
              indices: indexBuffer,
              count: mesh.indices.length,
              destroy() {
                geometry.delete(vertices);
                vertices.destroy();
                indexBuffer.destroy();
              },
            };
          }, (candidate) => candidate.destroy());
        }
        case "material": {
          const material = parseMaterial(bytes);
          resolveAssetPath(options.rootDirectory, material.shader);
          if (material.texture !== null) {
            resolveAssetPath(options.rootDirectory, material.texture);
          }
          await Promise.all([
            requireAsset("shader", material.shader),
            ...(material.texture === null
              ? []
              : [requireAsset("texture", material.texture)]),
          ]);
          return { kind, material, destroy() {} };
        }
        case "shader": {
          const shader = await checkedGpu(
            () =>
              device.createShaderModule({
                code: new TextDecoder("utf-8", { fatal: true }).decode(bytes),
              }),
            () => {},
          );
          const compilation = await shader.getCompilationInfo();
          const errors = compilation.messages.filter((message) =>
            message.type === "error"
          );
          if (errors.length > 0) {
            throw new Error(
              errors.map((error) =>
                `${error.lineNum}:${error.linePos} ${error.message}`
              ).join("\n"),
            );
          }
          const pipeline = await device.createRenderPipelineAsync({
            layout,
            vertex: {
              module: shader,
              entryPoint: "vertex",
              buffers: [{
                arrayStride: 32,
                attributes: [
                  { format: "float32x3", offset: 0, shaderLocation: 0 },
                  { format: "float32x3", offset: 12, shaderLocation: 1 },
                  { format: "float32x2", offset: 24, shaderLocation: 2 },
                ],
              }],
            },
            fragment: {
              module: shader,
              entryPoint: "fragment",
              targets: [{ format: options.format }],
            },
            primitive: {
              topology: "triangle-list",
              cullMode: "back",
              frontFace: "ccw",
            },
            depthStencil: {
              format: "depth24plus",
              depthWriteEnabled: true,
              depthCompare: "less",
            },
          });
          return { kind, pipeline, destroy() {} };
        }
        case "texture": {
          const decoded = await decodeTexture(bytes);
          const texture = await checkedGpu(
            () => textureFrom(decoded.width, decoded.height, decoded.pixels),
            (candidate) => candidate.destroy(),
          );
          return {
            kind,
            texture,
            destroy() {
              texture.destroy();
            },
          };
        }
      }
    },
  });
  let depth: GPUTexture | undefined;
  let width = 0;
  let height = 0;
  let closing: Promise<void> | undefined;
  let closed = false;

  const targetSize = (): readonly [number, number] => {
    const size = options.target.size();
    if (
      size.length !== 2 ||
      [...size].some((dimension) =>
        !Number.isSafeInteger(dimension) || dimension < 0 ||
        dimension > device.limits.maxTextureDimension2D
      )
    ) throw new RangeError("render target dimensions exceed device limits");
    return [Math.max(1, size[0]), Math.max(1, size[1])];
  };
  const resize = (): void => {
    const [nextWidth, nextHeight] = targetSize();
    if (nextWidth === width && nextHeight === height) return;
    const next = device.createTexture({
      size: [nextWidth, nextHeight],
      format: "depth24plus",
      usage: GPUTextureUsage.RENDER_ATTACHMENT,
    });
    depth?.destroy();
    depth = next;
    width = nextWidth;
    height = nextHeight;
  };
  const checkFrame = (frame: RenderFrame): void => {
    if (closed) throw new Error("renderer is closed");
    validateFrame(frame);
    targetSize();
    const required = 2 ** Math.ceil(Math.log2(Math.max(1, frame.draws.length)));
    if (required * stride > device.limits.maxBufferSize) {
      throw new RangeError("draw list exceeds device buffer size");
    }
    for (const draw of frame.draws) {
      resolveAssetPath(options.rootDirectory, draw.mesh);
      resolveAssetPath(options.rootDirectory, draw.material);
    }
  };
  const unavailableAssets = (frame: RenderFrame): readonly string[] => {
    checkFrame(frame);
    const missing = new Set<string>();
    for (const draw of frame.draws) {
      const mesh = assets.get("mesh", draw.mesh);
      const selected = assets.get("material", draw.material);
      if (mesh?.kind !== "mesh") missing.add(`mesh ${draw.mesh}`);
      if (selected?.kind !== "material") {
        missing.add(`material ${draw.material}`);
        continue;
      }
      const { material } = selected;
      if (assets.get("shader", material.shader)?.kind !== "shader") {
        throw new Error("resident material lost its validated shader");
      }
      if (
        material.texture !== null &&
        assets.get("texture", material.texture)?.kind !== "texture"
      ) {
        throw new Error("resident material lost its validated texture");
      }
    }
    return [...missing];
  };

  return {
    assets,
    /** Starts missing loads without submitting or replacing the visible frame. */
    ready(frame: RenderFrame): boolean {
      return unavailableAssets(frame).length === 0;
    },
    /** One-shot initial preparation; failed new references require an asset edit. */
    async prepare(frame: RenderFrame): Promise<void> {
      if (unavailableAssets(frame).length === 0) return;
      await assets.idle();
      const missing = unavailableAssets(frame);
      if (missing.length > 0) {
        throw new Error(
          `Render frame has unavailable assets: ${missing.join(", ")}`,
        );
      }
    },
    submit(frame: RenderFrame): void {
      checkFrame(frame);
      resize();
      if (frame.draws.length > capacity) {
        const nextCapacity = 2 ** Math.ceil(Math.log2(frame.draws.length));
        const next = device.createBuffer({
          size: nextCapacity * stride,
          usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
        });
        drawUniform.destroy();
        drawUniform = next;
        capacity = nextCapacity;
        groups = new WeakMap();
      }
      const vector = (
        v: { x: number; y: number; z: number },
      ) => [v.x, v.y, v.z, 0];
      device.queue.writeBuffer(
        sceneUniform,
        0,
        new Float32Array([
          ...frame.view,
          ...frame.projection,
          ...vector(frame.ambient),
          ...vector(frame.light_direction),
          ...vector(frame.light_color),
        ]),
      );
      const encoder = device.createCommandEncoder();
      const pass = encoder.beginRenderPass({
        colorAttachments: [{
          view: options.target.view(),
          clearValue: frame.clear,
          loadOp: "clear",
          storeOp: "store",
        }],
        depthStencilAttachment: {
          view: depth!.createView(),
          depthClearValue: 1,
          depthLoadOp: "clear",
          depthStoreOp: "store",
        },
      });
      try {
        pass.setBindGroup(0, sceneGroup);
        for (const [index, draw] of frame.draws.entries()) {
          const mesh = assets.get("mesh", draw.mesh);
          const selected = assets.get("material", draw.material);
          if (mesh?.kind !== "mesh" || selected?.kind !== "material") continue;
          const { material } = selected;
          const shader = assets.get("shader", material.shader);
          const loadedTexture = material.texture === null
            ? undefined
            : assets.get("texture", material.texture);
          if (shader?.kind !== "shader") {
            throw new Error("resident material lost its validated shader");
          }
          let texture = white;
          if (material.texture !== null) {
            if (loadedTexture?.kind !== "texture") {
              throw new Error("resident material lost its validated texture");
            }
            texture = loadedTexture.texture;
          }
          let group = groups.get(texture);
          if (group === undefined) {
            group = device.createBindGroup({
              layout: drawLayout,
              entries: [
                { binding: 0, resource: { buffer: drawUniform, size: 160 } },
                { binding: 1, resource: texture.createView() },
                { binding: 2, resource: sampler },
              ],
            });
            groups.set(texture, group);
          }
          device.queue.writeBuffer(
            drawUniform,
            index * stride,
            new Float32Array([
              ...draw.transform,
              ...normalMatrix(draw.transform),
              ...material.color,
              material.lighting === "lit" ? 1 : 0,
              0,
              0,
              0,
            ]),
          );
          pass.setPipeline(shader.pipeline);
          pass.setBindGroup(1, group, [index * stride]);
          pass.setVertexBuffer(0, mesh.vertices);
          pass.setIndexBuffer(mesh.indices, "uint32");
          pass.drawIndexed(mesh.count);
        }
      } finally {
        pass.end();
      }
      device.queue.submit([encoder.finish()]);
      options.target.present();
    },
    pick(frame: RenderFrame, point: Point): PickHit | undefined {
      if (closed) throw new Error("renderer is closed");
      validateFrame(frame);
      if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) {
        throw new RangeError("picking requires a finite viewport point");
      }
      const [viewportWidth, viewportHeight] = targetSize();
      if (
        point.x < 0 || point.y < 0 ||
        point.x >= viewportWidth || point.y >= viewportHeight
      ) return;
      const camera = multiply(frame.projection, frame.view);
      const unproject = inverse(camera);
      const x = point.x / viewportWidth * 2 - 1;
      const y = 1 - point.y / viewportHeight * 2;
      const origin = transform(unproject, [x, y, 0]);
      // The halfway depth works for both finite and infinite far projections.
      const delta = subtract(transform(unproject, [x, y, 0.5]), origin);
      const length = Math.hypot(...delta);
      if (length === 0 || !Number.isFinite(length)) {
        throw new RangeError("picking ray is degenerate");
      }
      const direction: Triple = [
        delta[0] / length,
        delta[1] / length,
        delta[2] / length,
      ];
      let nearest: PickHit | undefined;
      for (const [draw_index, draw] of frame.draws.entries()) {
        const mesh = assets.get("mesh", draw.mesh);
        const material = assets.get("material", draw.material);
        if (mesh?.kind !== "mesh" || material?.kind !== "material") continue;
        if (assets.get("shader", material.material.shader)?.kind !== "shader") {
          continue;
        }
        const triangles = geometry.get(mesh.vertices);
        if (triangles === undefined) {
          throw new Error("resident mesh lost its geometry");
        }
        const vertex = (index: number): Triple =>
          transform(draw.transform, [
            triangles.vertices[index * 8],
            triangles.vertices[index * 8 + 1],
            triangles.vertices[index * 8 + 2],
          ]);
        for (let index = 0; index < triangles.indices.length; index += 3) {
          const distance = triangleDistance(
            origin,
            direction,
            vertex(triangles.indices[index]),
            vertex(triangles.indices[index + 1]),
            vertex(triangles.indices[index + 2]),
          );
          if (
            distance === undefined ||
            distance >= (nearest?.distance ?? Infinity)
          ) continue;
          const position: Triple = [
            origin[0] + direction[0] * distance,
            origin[1] + direction[1] * distance,
            origin[2] + direction[2] * distance,
          ];
          const depth = transform(camera, position)[2];
          // Depth is cleared to 1 and the pipeline uses a strict less test.
          if (depth < 0 || depth >= 1) continue;
          nearest = {
            ...(draw.entity === undefined ? {} : { entity: draw.entity }),
            draw_index,
            distance,
            position: { x: position[0], y: position[1], z: position[2] },
          };
        }
      }
      return nearest;
    },
    close(): Promise<void> {
      if (closing !== undefined) return closing;
      closed = true;
      closing = (async () => {
        try {
          await assets.close();
        } finally {
          depth?.destroy();
          white.destroy();
          sceneUniform.destroy();
          drawUniform.destroy();
          groups = new WeakMap();
        }
      })();
      return closing;
    },
  };
}
