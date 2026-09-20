import png from "imagescript/png-encode";

/** Copy the actual window surface before present(), then encode off the GPU. */
export function captureSurface(
  device: GPUDevice,
  texture: GPUTexture,
  path: string,
): Promise<void> {
  const { width, height, format } = texture;
  if (format !== "bgra8unorm" && format !== "rgba8unorm") {
    throw new Error(`Unsupported capture format ${format}`);
  }
  const bytesPerRow = Math.ceil(width * 4 / 256) * 256;
  const buffer = device.createBuffer({
    size: bytesPerRow * height,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ,
  });
  const encoder = device.createCommandEncoder();
  encoder.copyTextureToBuffer({ texture }, { buffer, bytesPerRow }, {
    width,
    height,
  });
  device.queue.submit([encoder.finish()]);
  return (async () => {
    try {
      await buffer.mapAsync(GPUMapMode.READ);
      const mapped = new Uint8Array(buffer.getMappedRange());
      const pixels = new Uint8Array(width * height * 4);
      for (let y = 0; y < height; y++) {
        pixels.set(
          mapped.subarray(y * bytesPerRow, y * bytesPerRow + width * 4),
          y * width * 4,
        );
      }
      if (format === "bgra8unorm") {
        for (let index = 0; index < pixels.length; index += 4) {
          [pixels[index], pixels[index + 2]] = [
            pixels[index + 2],
            pixels[index],
          ];
        }
      }
      buffer.unmap();
      await Deno.writeFile(
        path,
        await png.encode(pixels, { width, height, channels: 4, level: 1 }),
      );
    } finally {
      buffer.destroy();
    }
  })();
}
