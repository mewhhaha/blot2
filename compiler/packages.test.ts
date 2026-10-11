import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { installPackages, resolveProject } from "./packages.ts";

async function git(root: string, ...args: string[]): Promise<string> {
  const result = await new Deno.Command("git", {
    args: ["-C", root, ...args],
    stdout: "piped",
    stderr: "piped",
  }).output();
  ok(result.success, new TextDecoder().decode(result.stderr));
  return new TextDecoder().decode(result.stdout).trim();
}
async function commit(root: string) {
  await git(root, "add", ".");
  await git(
    root,
    "-c",
    "user.name=BPM fixture",
    "-c",
    "user.email=bpm@example.invalid",
    "commit",
    "--quiet",
    "-m",
    "fixture",
  );
  return git(root, "rev-parse", "HEAD");
}
async function library(root: string, value = 42) {
  await Deno.mkdir(join(root, "src"), { recursive: true });
  await Deno.mkdir(join(root, "extra"), { recursive: true });
  await Deno.writeTextFile(join(root, "extra/value.blot"), "const extra = 1\n");
  await Deno.writeTextFile(
    join(root, "src/value.blot"),
    `const value = ${value}\n`,
  );
  await Deno.writeTextFile(
    join(root, "src/prelude.blot"),
    "const custom = 7\n",
  );
  await Deno.writeTextFile(
    join(root, "blot-workspace.yaml"),
    "exports:\n  .: ./src\n  extra: ./extra\nprelude: ./src/prelude.blot\n",
  );
}
async function repository(root: string) {
  await library(root);
  await git(root, "init", "--quiet", "--initial-branch=main");
  return commit(root);
}
async function app(root: string, dependencies: unknown, prelude?: string) {
  await Deno.mkdir(root, { recursive: true });
  const value: Record<string, unknown> = { dependencies };
  if (prelude) value.prelude = prelude;
  await Deno.writeTextFile(join(root, "blot.json"), JSON.stringify(value));
  return join(root, "src/main.blot");
}
async function temporary(test: (directory: string) => Promise<void>) {
  const directory = await Deno.makeTempDir();
  try {
    await test(directory);
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

Deno.test("Git packages pin moving refs, resolve offline and update only on request", () =>
  temporary(async (directory) => {
    const repo = join(directory, "repo"),
      root = join(directory, "app"),
      cacheDirectory = join(directory, "cache");
    const first = await repository(repo);
    const source = pathToFileURL(repo).href;
    const entry = await app(root, { math: `${source}#main` }, "math");
    const installed = await installPackages(root, { cacheDirectory });
    equal(
      await Deno.readTextFile(join(installed.imports["math/"], "value.blot")),
      "const value = 42\n",
    );
    ok(installed.imports["math/extra/"].endsWith("/extra"));
    ok(installed.prelude?.endsWith("/src/prelude.blot"));
    const originalLock = await Deno.readTextFile(join(root, "blot.lock.json"));
    equal(JSON.parse(originalLock).packages.math.revision, first);
    await Deno.writeTextFile(
      join(repo, "src/value.blot"),
      "const value = 43\n",
    );
    const second = await commit(repo);
    await installPackages(root, { cacheDirectory });
    equal(await Deno.readTextFile(join(root, "blot.lock.json")), originalLock);
    await Deno.rename(repo, `${repo}-offline`);
    try {
      const offline = await resolveProject(entry, { cacheDirectory });
      ok(offline);
      equal(
        await Deno.readTextFile(join(offline.imports["math/"], "value.blot")),
        "const value = 42\n",
      );
      await installPackages(root, { cacheDirectory, frozen: true });
    } finally {
      await Deno.rename(`${repo}-offline`, repo);
    }
    const updated = await installPackages(root, {
      cacheDirectory,
      update: true,
    });
    equal(
      JSON.parse(await Deno.readTextFile(join(root, "blot.lock.json"))).packages
        .math.revision,
      second,
    );
    equal(
      await Deno.readTextFile(join(updated.imports["math/"], "value.blot")),
      "const value = 43\n",
    );
  }));

Deno.test("SHA-256 repositories install by branch and restore exact frozen commits", () =>
  temporary(async (directory) => {
    const repo = join(directory, "repo"),
      root = join(directory, "app"),
      cacheDirectory = join(directory, "cache");
    await library(repo);
    await git(
      repo,
      "init",
      "--quiet",
      "--initial-branch=main",
      "--object-format=sha256",
    );
    const revision = await commit(repo);
    equal(revision.length, 64);
    const source = pathToFileURL(repo).href;
    const entry = await app(root, { math: `${source}#main` });
    await installPackages(root, { cacheDirectory });
    equal(
      JSON.parse(await Deno.readTextFile(join(root, "blot.lock.json"))).packages
        .math.revision,
      revision,
    );
    await Deno.rename(repo, `${repo}-offline`);
    ok(await resolveProject(entry, { cacheDirectory }));
    await Deno.rename(`${repo}-offline`, repo);
    await Deno.remove(cacheDirectory, { recursive: true });
    await installPackages(root, { cacheDirectory, frozen: true });
    await app(root, { math: `${source}#${revision}` });
    await installPackages(root, { cacheDirectory });
    equal(
      JSON.parse(await Deno.readTextFile(join(root, "blot.lock.json"))).packages
        .math.revision,
      revision,
    );
  }));

Deno.test("transitive packages share a pinned graph and reject conflicting global aliases", () =>
  temporary(async (directory) => {
    const leaf = join(directory, "leaf"),
      parent = join(directory, "parent"),
      root = join(directory, "app"),
      cacheDirectory = join(directory, "cache");
    await repository(leaf);
    await library(parent);
    await app(parent, { leaf: `${pathToFileURL(leaf).href}#main` });
    await git(parent, "init", "--quiet", "--initial-branch=main");
    await commit(parent);
    const entry = await app(root, {
      parent: `${pathToFileURL(parent).href}#main`,
    });
    const project = await installPackages(root, { cacheDirectory });
    ok(project.imports["parent/"] && project.imports["leaf/"]);
    equal(
      Object.keys(
        JSON.parse(await Deno.readTextFile(join(root, "blot.lock.json")))
          .packages,
      ),
      ["parent", "leaf"],
    );
    const lockPath = join(root, "blot.lock.json");
    const lock = JSON.parse(await Deno.readTextFile(lockPath));
    lock.packages = { leaf: lock.packages.leaf, parent: lock.packages.parent };
    await Deno.writeTextFile(lockPath, JSON.stringify(lock));
    await installPackages(root, { cacheDirectory, frozen: true });
    await Deno.rename(leaf, `${leaf}-offline`);
    await Deno.rename(parent, `${parent}-offline`);
    ok(await resolveProject(entry, { cacheDirectory }));
    const local = join(directory, "local");
    await library(local);
    await app(root, {
      parent: `${pathToFileURL(parent).href}#main`,
      leaf: { path: "../local" },
    });
    await rejects(
      () => resolveProject(entry, { cacheDirectory }),
      /Conflicting dependency leaf/,
    );
  }));

Deno.test("local workspaces stay live, enforce exports and do not inject a prelude", () =>
  temporary(async (directory) => {
    const root = join(directory, "app"), local = join(directory, "local");
    await library(local);
    const entry = await app(root, { local: { path: "../local" } });
    const initial = await resolveProject(entry);
    ok(initial);
    equal(initial.prelude, null);
    equal(initial.stdRoot, null);
    await Deno.writeTextFile(
      join(local, "src/value.blot"),
      "const value = 99\n",
    );
    const changed = await resolveProject(entry);
    equal(
      await Deno.readTextFile(join(changed!.imports["local/"], "value.blot")),
      "const value = 99\n",
    );
    await Deno.writeTextFile(
      join(local, "blot-workspace.yaml"),
      "exports:\n  .: ../app\n",
    );
    await rejects(() => resolveProject(entry), /escapes its workspace/);
    await Deno.symlink(root, join(local, "outside"));
    await Deno.writeTextFile(
      join(local, "blot-workspace.yaml"),
      "exports:\n  .: ./outside\n",
    );
    await rejects(() => resolveProject(entry), /escapes its workspace/);
    await Deno.writeTextFile(
      join(local, "blot-workspace.yaml"),
      "exports:\n  .: ./src\n  .: ./extra\n",
    );
    await rejects(() => resolveProject(entry));
    await Deno.remove(join(local, "blot-workspace.yaml"));
    await rejects(() => resolveProject(entry), /must declare its exports/);
  }));

Deno.test("cache modifications and ignored extra files cannot compile under a pinned lock", () =>
  temporary(async (directory) => {
    const repo = join(directory, "repo"),
      root = join(directory, "app"),
      cacheDirectory = join(directory, "cache");
    await repository(repo);
    await Deno.writeTextFile(join(repo, ".gitignore"), ".unexpected\n");
    await commit(repo);
    const entry = await app(root, { math: `${pathToFileURL(repo).href}#main` });
    const project = await installPackages(root, { cacheDirectory });
    const value = join(project.imports["math/"], "value.blot");
    await Deno.writeTextFile(value, "const value = 99\n");
    await rejects(
      () => resolveProject(entry, { cacheDirectory }),
      /Changed BPM checkout/,
    );
    await Deno.writeTextFile(value, "const value = 42\n");
    await Deno.writeTextFile(
      join(project.imports["math/"], "../.unexpected"),
      "untracked",
    );
    await rejects(
      () => resolveProject(entry, { cacheDirectory }),
      /Changed BPM checkout/,
    );
  }));

Deno.test("failed and frozen installs preserve the lock and clean unpublished downloads", () =>
  temporary(async (directory) => {
    const repo = join(directory, "repo"),
      root = join(directory, "app"),
      cacheDirectory = join(directory, "cache");
    await repository(repo);
    const source = pathToFileURL(repo).href;
    await app(root, { math: `${source}#main` });
    await rejects(
      () => installPackages(root, { cacheDirectory, frozen: true }),
      /run bpm install/,
    );
    await installPackages(root, { cacheDirectory });
    const lock = await Deno.readTextFile(join(root, "blot.lock.json"));
    await app(root, { math: `${source}#missing` });
    await rejects(
      () => installPackages(root, { cacheDirectory, frozen: true }),
      /run bpm install/,
    );
    equal(await Deno.readTextFile(join(root, "blot.lock.json")), lock);
    await app(root, { math: `${source}#main` });
    await Deno.remove(join(repo, "blot-workspace.yaml"));
    await commit(repo);
    await rejects(
      () => installPackages(root, { cacheDirectory, update: true }),
      /must declare its exports/,
    );
    equal(await Deno.readTextFile(join(root, "blot.lock.json")), lock);
    for await (const item of Deno.readDir(join(cacheDirectory, "packages"))) {
      ok(!item.name.startsWith(".install-"));
    }
  }));

Deno.test("downloaded packages cannot reach local dependencies outside their repository", () =>
  temporary(async (directory) => {
    const local = join(directory, "local"),
      repo = join(directory, "repo"),
      root = join(directory, "app"),
      cacheDirectory = join(directory, "cache");
    await library(local);
    await library(repo);
    await app(repo, { outside: { path: local } });
    await git(repo, "init", "--quiet", "--initial-branch=main");
    await commit(repo);
    await app(root, { remote: `${pathToFileURL(repo).href}#main` });
    await rejects(
      () => installPackages(root, { cacheDirectory }),
      /dependency escapes its repository/,
    );
    equal(
      await Deno.stat(join(root, "blot.lock.json")).catch(() => null),
      null,
    );
  }));
