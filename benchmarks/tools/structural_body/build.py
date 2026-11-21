"""Build and fingerprint the standalone probe from an isolated source snapshot."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

here = Path(__file__).resolve().parent
root = here.parents[2]
work = root / "build/structural-body"
compiler = root / "compiler-goose"
toolchain = root / "build/goose-port/upstream-d5ae5bb"
goose = toolchain / "build-precision/goose"
clang = Path(shutil.which("clang")).resolve()
work.mkdir(parents=True, exist_ok=True)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_digest(path):
    value = hashlib.sha256()
    for file in sorted(path.rglob("*")):
        if file.is_file():
            value.update(file.relative_to(path).as_posix().encode() + b"\0")
            value.update(bytes.fromhex(digest(file)))
    return value.hexdigest()


with tempfile.TemporaryDirectory(dir=work) as temp:
    scratch = Path(temp)
    modules = scratch / "modules"
    native = scratch / "native"
    stdlib = scratch / "stdlib"
    shutil.copytree(compiler / "src", modules)
    shutil.copytree(compiler / "native", native)
    shutil.copytree(toolchain / "source-precision/stdlib", stdlib)
    inputs = ("probe.goose", "capture.c", "io.c", "instrument.patch")
    for name in inputs:
        shutil.copyfile(here / name, scratch / name)
    build_id = dict(modules=tree_digest(modules), native=tree_digest(native),
                    stdlib=tree_digest(stdlib), goose=digest(goose), clang=digest(clang),
                    clangVersion=subprocess.check_output([clang, "--version"], text=True).splitlines()[0],
                    harness={name: digest(scratch / name) for name in inputs})
    shutil.copyfile(scratch / "probe.goose", modules / "main.goose")
    with (scratch / "instrument.patch").open() as changes:
        subprocess.run(["patch", "--batch", "--fuzz=0", "-p1", "-d", modules / "direct"],
                       stdin=changes, check=True)
    flags = [clang, "-std=gnu11", "-D_GNU_SOURCE", "-O2", "-pthread"]
    build_id.update(cFlags=flags[1:], gooseFlags=["-O2"], buildScriptSha256=digest(Path(__file__)))
    commands = [
        [*flags, "-I", native, "-fPIC", "-shared", "-fvisibility=hidden", "-ffunction-sections",
         "-Wl,--gc-sections,-z,defs", scratch/"capture.c", "-ldl", "-o", scratch/"capture.so"],
        [goose, "--emit-runtime", scratch/"runtime.c"],
        [goose, "-O2", "--stdlib", stdlib, "-o", scratch/"probe.c", modules/"main.goose"],
        [*flags, scratch/"probe.c", scratch/"runtime.c", native/"platform.c", native/"check_queue.c",
         scratch/"io.c", "-lm", "-o", scratch/"probe"],
    ]
    with (work/"build-probe.log").open("w") as log:
        for command in commands:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=90, check=True)
    for name in ("probe", "capture.so"):
        build_id[name] = digest(scratch / name)
        (scratch / name).replace(work / name)
    (scratch/"identity.json").write_text(json.dumps(build_id, indent=2) + "\n")
    (scratch/"identity.json").replace(work/"build-identity.json")
