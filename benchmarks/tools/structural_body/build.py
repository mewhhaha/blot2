"""Build the standalone replay probe against the checked-out direct backend."""
from pathlib import Path
import shutil
import subprocess

source = Path(__file__).resolve().parent
root = source.parents[2]
work = root / "build/structural-body"
compiler = root / "compiler-goose"
toolchain = root / "build/goose-port/upstream-d5ae5bb"
goose = toolchain / "build-precision/goose"
stdlib = toolchain / "source-precision/stdlib"
modules = work / "modules"
modules.mkdir(parents=True, exist_ok=True)

# Only the scratch copy of direct/ receives the instrumentation patch.
for path in (compiler / "src").iterdir():
    dest = modules / path.name
    if path.name == "direct":
        shutil.copytree(path, dest, dirs_exist_ok=True)
    elif path.name != "main.goose" and not dest.exists():
        dest.symlink_to(path)
shutil.copyfile(source / "probe.goose", modules / "main.goose")
with (source / "instrument.patch").open() as changes:
    subprocess.run(["patch", "--batch", "--fuzz=0", "-p1", "-d", modules/"direct"],
                   stdin=changes, check=True)
flags = ["clang", "-std=gnu11", "-D_GNU_SOURCE", "-O2", "-pthread"]
commands = [
    [*flags, "-I", compiler/"native", "-fPIC", "-shared", "-fvisibility=hidden",
     "-ffunction-sections", "-Wl,--gc-sections,-z,defs", source/"capture.c",
     "-ldl", "-o", work/"capture.so"],
    [goose, "--emit-runtime", work/"runtime.c"],
    [goose, "-O2", "--stdlib", stdlib, "-o", work/"probe.c", modules/"main.goose"],
    [*flags, work/"probe.c", work/"runtime.c", compiler/"native/platform.c",
     compiler/"native/check_queue.c", source/"io.c", "-lm", "-o", work/"probe"],
]
with (work/"build-probe.log").open("w") as log:
    for command in commands:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=90, check=True)
