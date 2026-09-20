// ImageScript's pinned Wasm entries avoid the native codec loaded by its npm entry.
import png from "imagescript/png";
import jpeg from "imagescript/jpeg";

function pixelCount(width: number, height: number): number {
  if (
    !Number.isSafeInteger(width) || width < 1 ||
    !Number.isSafeInteger(height) || height < 1 ||
    !Number.isSafeInteger(width * height * 4)
  ) {
    throw new RangeError(
      "texture dimensions must be positive, bounded integers",
    );
  }
  return width * height;
}

export async function decodeTexture(bytes: Uint8Array): Promise<{
  width: number;
  height: number;
  pixels: Uint8Array<ArrayBuffer>;
}> {
  if (
    bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 && bytes[3] === 71
  ) {
    const decoded = (await png.init()).decode(bytes);
    const count = pixelCount(decoded.width, decoded.height);
    if (decoded.framebuffer.length !== count * 4) {
      throw new TypeError("PNG decoder returned an incomplete RGBA image");
    }
    return {
      width: decoded.width,
      height: decoded.height,
      pixels: Uint8Array.from(decoded.framebuffer),
    };
  }
  if (bytes[0] !== 255 || bytes[1] !== 216) {
    throw new TypeError("texture must be PNG or JPEG");
  }
  const decoded = (await jpeg.init()).decode(bytes);
  const count = pixelCount(decoded.width, decoded.height);
  const channels = [1, 3, 4][decoded.format];
  if (channels === undefined) {
    throw new TypeError(`unsupported JPEG pixel format ${decoded.format}`);
  }
  const pixels = new Uint8Array(count * 4);
  const source: Uint8Array = decoded.buffer;
  if (source.length !== count * channels) {
    throw new TypeError("JPEG decoder returned an incomplete image");
  }
  for (let index = 0; index < count; index++) {
    const target = index * 4;
    switch (decoded.format) {
      case 0:
        pixels[target] =
          pixels[target + 1] =
          pixels[target + 2] =
            source[index];
        break;
      case 1:
        pixels.set(source.subarray(index * 3, index * 3 + 3), target);
        break;
      case 2: {
        const black = 1 - source[target + 3] / 255;
        for (let channel = 0; channel < 3; channel++) {
          pixels[target + channel] = Math.round(
            (255 - source[target + channel]) * black,
          );
        }
        break;
      }
      default:
        throw new TypeError(`unsupported JPEG pixel format ${decoded.format}`);
    }
    pixels[target + 3] = 255;
  }
  return { width: decoded.width, height: decoded.height, pixels };
}
