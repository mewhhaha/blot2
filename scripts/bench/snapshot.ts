import { resolve } from "node:path";
import { fileDigest } from "../compiler_gate_state.ts";

export async function snapshotFiles(
  root: string,
): Promise<Record<string, string>> {
  const files: Record<string, string> = {};
  async function visit(directory: string, prefix: string) {
    for await (const entry of Deno.readDir(directory)) {
      const name = prefix + entry.name;
      if (entry.isSymlink) {
        throw new Error(`Snapshot symlink is not a frozen input: ${name}`);
      }
      if (entry.isDirectory) {
        await visit(resolve(directory, entry.name), name + "/");
      } else if (entry.isFile && name !== "manifest.json") {
        files[name] = await fileDigest(resolve(directory, entry.name));
      }
    }
  }
  await visit(root, "");
  return Object.fromEntries(Object.entries(files).sort());
}
export async function verifySnapshotFiles(
  root: string,
  expected: Record<string, string>,
) {
  const actual = await snapshotFiles(root);
  const changes = [
    ...new Set([...Object.keys(expected), ...Object.keys(actual)]),
  ].filter((name) => expected[name] !== actual[name]);
  if (changes.length) {
    throw new Error(`Snapshot changed: ${changes.join(", ")}`);
  }
  return Object.keys(actual).length;
}
