import { resolve } from "node:path";
import { installPackages } from "./packages.ts";

const usage = `Usage: bpm init [DIRECTORY]
       bpm install [DIRECTORY] [--frozen] [--cache DIR]
       bpm update [DIRECTORY] [--cache DIR]`;

export async function runBpm(args: string[] = Deno.args): Promise<number> {
  const [command, ...rest] = args;
  if (command === "--help" || command === "-h") {
    console.log(usage);
    return 0;
  }
  if (!["init", "install", "update"].includes(command)) {
    console.error(usage);
    return 2;
  }
  let directory: string | undefined, cacheDirectory: string | undefined;
  let frozen = false;
  for (let at = 0; at < rest.length; at++) {
    const value = rest[at];
    if (value === "--frozen" && command === "install") frozen = true;
    else if (
      value === "--cache" && command !== "init" && rest[at + 1] &&
      !rest[at + 1].startsWith("--")
    ) cacheDirectory = rest[++at];
    else if (!directory && !value.startsWith("--")) directory = value;
    else {
      console.error(`Unexpected argument: ${value}\n${usage}`);
      return 2;
    }
  }
  directory = resolve(directory ?? Deno.cwd());
  try {
    if (command === "init") {
      await Deno.mkdir(directory, { recursive: true });
      await Deno.writeTextFile(
        `${directory}/blot.json`,
        '{\n  "dependencies": {}\n}\n',
        { createNew: true },
      );
      console.log(`${directory}/blot.json`);
      return 0;
    }
    const project = await installPackages(directory, {
      cacheDirectory,
      frozen,
      update: command === "update",
    });
    console.log(`${project.root}/blot.lock.json`);
    return 0;
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    return 1;
  }
}

if (import.meta.main) Deno.exitCode = await runBpm();
