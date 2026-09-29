#!/usr/bin/env python3
"""Build an exact source checkout's unmodified Bend JS modules for paired CI.

The production build remains scripts/build_compiler.ts. This benchmark helper
uses that same official release loader, sequentially so two comparison images
and three module builders do not compete for the runner's memory at once.
"""
from pathlib import Path
import os
import re
import subprocess
import sys
import urllib.request

root = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else Path(__file__).resolve().parents[1]
env = dict(os.environ, BEND_NO_TELEMETRY="1")

def run(args, **kwargs):
    return subprocess.run(args, cwd=root, env=env, check=True, **kwargs)

version = run(["bend", "version"], capture_output=True, text=True).stdout.strip()
match = re.fullmatch(r"bend (\d+\.\d+\.\d+(?:-[\w.-]+)?)", version, re.IGNORECASE)
if not match:
    raise RuntimeError(f"Unrecognized Bend release: {version}")
print(version, flush=True)
run(["bend", "PROOF.bend"])
output = root / "generated/compiler"
backend = output / f"bend-{match[1]}"
backend.mkdir(parents=True, exist_ok=True)
for name in ["main.ts", "bend.ts", "comp.ts", "safe.ts", "base.bend"]:
    with urllib.request.urlopen(
        f"https://raw.githubusercontent.com/bendlang/bend/v{match[1]}/bend2/{name}", timeout=120
    ) as response:
        (backend / name).write_bytes(response.read())
program = '''const { load } = await import(process.argv[1]);
const result = await load(process.argv[2], {}, () => {
  throw new Error("Bend loader did not recognize the compiler entry");
});
process.stdout.write(result.source);'''
for module, filename in [("main", "compiler"), ("native_session", "native_session"), ("native_output", "native_output")]:
    print(f"Building {filename}.js in {root}", flush=True)
    temporary = output / f".{filename}.js.tmp"
    try:
        with temporary.open("wb") as handle:
            run(["bun", "--eval", program, (backend / "main.ts").as_uri(),
                 (root / "compiler" / f"{module}.bend").as_uri()], stdout=handle)
        temporary.replace(output / f"{filename}.js")
    finally:
        temporary.unlink(missing_ok=True)
(output / "runtime-reference-version.txt").write_text(version + "\n")
