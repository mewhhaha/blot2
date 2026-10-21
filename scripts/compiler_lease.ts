import { resolve } from "node:path";
import process from "node:process";

/** Fail promptly instead of queuing a development cycle behind a long gate. */
export async function compilerLease(root: string) {
  const parent = resolve(root, ".zig-cache");
  const directory = resolve(parent, "compiler-check.lock");
  await Deno.mkdir(parent, { recursive: true });
  const ownerPath = resolve(directory, "owner.json");
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      await Deno.mkdir(directory);
      break;
    } catch (error) {
      if (!(error instanceof Deno.errors.AlreadyExists)) throw error;
      let owner: { pid: number; started: string } | undefined;
      let ownerText = "";
      try {
        ownerText = await Deno.readTextFile(ownerPath);
        owner = JSON.parse(ownerText);
      } catch { /* An owner still creating its lease is busy. */ }
      if (owner && attempt === 0) {
        try {
          process.kill(owner.pid, 0);
        } catch (cause) {
          if ((cause as NodeJS.ErrnoException).code === "ESRCH") {
            const digest = new Uint8Array(
              await crypto.subtle.digest(
                "SHA-256",
                new TextEncoder().encode(ownerText),
              ),
            );
            const id = [...digest].map((byte) =>
              byte.toString(16).padStart(2, "0")
            ).join("");
            try {
              // Keep this nonempty tombstone: a delayed contender cannot move a
              // new owner's directory over the old owner's existing tombstone.
              await Deno.rename(
                directory,
                resolve(parent, `compiler-check.stale-${id}`),
              );
              continue;
            } catch { /* Another contender recovered it first; report busy. */ }
          }
        }
      }
      throw new Error(
        `Compiler artifacts are busy${
          owner ? ` (PID ${owner.pid})` : ""
        }; no build was queued. Retry after the active check finishes.`,
      );
    }
  }
  await Deno.writeTextFile(
    ownerPath,
    JSON.stringify({ pid: Deno.pid, started: new Date().toISOString() }),
  );
  return {
    async [Symbol.asyncDispose]() {
      await Deno.remove(ownerPath);
      await Deno.remove(directory);
    },
  };
}
