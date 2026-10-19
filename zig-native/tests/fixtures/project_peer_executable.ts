import { fileURLToPath } from "node:url";

let executable: Promise<string> | undefined;
let completion: Promise<string> | undefined;

/** Cancellation tests use a native process whose startup fits the LSP budget. */
export function completionPeerExecutable(): Promise<string> {
  return completion ??= compileCompletionPeer();
}

async function compileCompletionPeer(): Promise<string> {
  const source = new URL(
    "../../../compiler/fixtures/completion_peer.zig",
    import.meta.url,
  );
  const version = await new Deno.Command("zig", {
    args: ["version"],
    stdout: "piped",
  }).output();
  if (!version.success) {
    throw new Error("Cannot identify Zig for the completion peer");
  }
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify([
      Deno.build.target,
      new TextDecoder().decode(version.stdout),
      await Deno.readTextFile(source),
      await Deno.readTextFile(new URL(import.meta.url)),
    ])),
  );
  const key = Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  const cache = fileURLToPath(
    new URL("../../../build/tests/completion-peer/", import.meta.url),
  );
  await Deno.mkdir(cache, { recursive: true });
  const output = `${cache}${key}${Deno.build.os === "windows" ? ".exe" : ""}`;
  try {
    if ((await Deno.stat(output)).isFile) return output;
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  const directory = await Deno.makeTempDir({ dir: cache });
  try {
    const temporary = `${directory}/peer${
      Deno.build.os === "windows" ? ".exe" : ""
    }`;
    const compiled = await new Deno.Command("zig", {
      args: [
        "build-exe",
        fileURLToPath(source),
        "-O",
        "fast",
        "-lc",
        ...(Deno.build.os === "linux" ? ["-fno-llvm"] : []),
        `-femit-bin=${temporary}`,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    if (!compiled.success) {
      throw new Error(new TextDecoder().decode(compiled.stderr));
    }
    await Deno.rename(temporary, output);
    return output;
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

/** Start the protocol mock directly, without deno run inside client deadlines. */
export function projectPeerExecutable(): Promise<string> {
  return executable ??= compilePeer();
}

async function compilePeer(): Promise<string> {
  const source = new URL("./zig_project_peer.ts", import.meta.url);
  const inputs = JSON.stringify([
    Deno.version,
    Deno.build.target,
    await Deno.readTextFile(source),
    await Deno.readTextFile(new URL(import.meta.url)),
  ]);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(inputs),
  );
  const key = Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  const cache = fileURLToPath(
    new URL("../../../build/tests/project-peer/", import.meta.url),
  );
  await Deno.mkdir(cache, { recursive: true });
  const suffix = Deno.build.os === "windows" ? ".exe" : "";
  const output = `${cache}${key}${suffix}`;
  try {
    if ((await Deno.stat(output)).isFile) return output;
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
  const directory = await Deno.makeTempDir({ dir: cache });
  try {
    const temporary = `${directory}/peer${suffix}`;
    const compiled = await new Deno.Command(Deno.execPath(), {
      args: [
        "compile",
        "--quiet",
        "--allow-all",
        "--output",
        temporary,
        fileURLToPath(source),
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    if (!compiled.success) {
      throw new Error(new TextDecoder().decode(compiled.stderr));
    }
    await Deno.rename(temporary, output);
    return output;
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}
