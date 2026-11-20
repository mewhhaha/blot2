"""Build a profile-guided Blot compiler with two ordinary release builds."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

COMPILER = Path(__file__).resolve().parents[1]
ROOT = COMPILER.parent
TRAINING = (
    "checked-grid/hills.blot",
    "goose/ports/custom_hash.blot",
    "goose/ports/sort_merge.blot",
    "idiomatic/expression_eval.blot",
    "goose/ports/mandelbrot.blot",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", required=True)
    parser.add_argument("--stdlib", required=True)
    parser.add_argument("--output", type=Path, default=COMPILER / "build/blotc-goose-pgo")
    args = parser.parse_args()
    profdata = shutil.which("llvm-profdata")
    if not profdata:
        parser.error("llvm-profdata from the Clang toolchain is required")

    # build.py writes the identity into its source tree. Keep both PGO passes
    # in a private tree so regular builds can run at the same time.
    (COMPILER / "build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=COMPILER / "build", prefix="pgo-") as work:
        work = Path(work)
        shutil.copytree(COMPILER / "src", work / "src")
        shutil.copytree(COMPILER / "native", work / "native")
        shutil.copy2(COMPILER / "build.py", work)
        build = [sys.executable, str(work / "build.py"), "--release",
                 "--goose", args.goose, "--stdlib", args.stdlib, "--cc", "clang",
                 "--stage-timeout", "600", "--total-timeout", "780"]
        trainer = work / "trainer"
        subprocess.run([*build, "--cflag=-O0", "--cflag=-fprofile-instr-generate",
                        "--output", trainer], check=True)
        profiles = []
        for index, source in enumerate(TRAINING):
            profile = work / f"train-{index}.profraw"
            result = subprocess.run(
                [trainer, "build-project", ROOT / "benchmarks" / source,
                 work / "training.wasm", "--std-root", ROOT / "std",
                 "--prelude", ROOT / "std/prelude.blot", "--frontend-workers", "1"],
                timeout=20, capture_output=True, text=True,
                env={**os.environ, "LLVM_PROFILE_FILE": str(profile)})
            if result.returncode:
                sys.exit(f"Training failed on {source}\n{result.stdout}{result.stderr}")
            profiles.append(profile)

        merged = work / "training.profdata"
        subprocess.run([profdata, "merge", "-o", merged, *profiles], check=True, timeout=30)
        # build.py fingerprints the C flags. Include the actual profile contents
        # in that identity without encoding the temporary directory's name.
        digest = hashlib.sha256(merged.read_bytes()).hexdigest()
        profile_name = f"{digest}.profdata"
        merged.rename(work / profile_name)
        print(f"Training profile SHA-256 {digest}", flush=True)
        subprocess.run([*build, f"--cflag=-fprofile-instr-use=../{profile_name}",
                        "--output", args.output.resolve()], check=True)


if __name__ == "__main__":
    main()
