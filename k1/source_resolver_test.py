#!/usr/bin/env python3
"""Executable source resolver confinement tests; no network or external state."""
import ctypes
import os
import pathlib
import subprocess
import sys
import tempfile
import threading

HERE = pathlib.Path(__file__).resolve().parent
LIMIT = 16 * 1024 * 1024
GOOSE = os.environ.get("GOOSE", "goose")

def build(source, output, level):
    subprocess.run([GOOSE, "build", f"-O{level}", "-o", str(output), str(HERE / source)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

def run(executable, root, path):
    return subprocess.run([str(executable), str(root), "pkg", path, "answer"],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)

def expect_error(result):
    assert result.returncode != 0 and result.stdout == b"", (result.returncode, len(result.stdout), result.stderr)

def race(executable, root, outside):
    # Exchange a real in-root directory and an escaping symlink atomically while
    # openat2 resolves the exact same module path. The only successful result
    # is the in-root marker; an outside marker is never acceptable.
    slot = root / "slot"
    slot.mkdir()
    (slot / "secret.blot").write_bytes(b"inside-race\n")
    swap = root / "slot-swap"
    swap.symlink_to("../outside", target_is_directory=True)
    libc = ctypes.CDLL(None, use_errno=True)
    exchange = getattr(libc, "renameat2", None)
    if exchange is None:
        return "renameat2 unavailable; race test skipped"
    exchange.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    exchange.restype = ctypes.c_int
    a, b = os.fsencode(slot), os.fsencode(swap)
    at_fdcwd, rename_exchange = -100, 2
    if exchange(at_fdcwd, a, at_fdcwd, b, rename_exchange) != 0:
        return f"renameat2 exchange unavailable (errno {ctypes.get_errno()}); race test skipped"
    stop = threading.Event()
    count = [1]
    errors = []
    def toggle():
        while not stop.is_set():
            if exchange(at_fdcwd, a, at_fdcwd, b, rename_exchange) != 0:
                errors.append(ctypes.get_errno()); return
            count[0] += 1
    worker = threading.Thread(target=toggle)
    worker.start()
    try:
        for _ in range(200):
            result = run(executable, root, "slot/secret.blot")
            if result.returncode == 0:
                assert result.stdout == b"inside-race\n", "path race escaped package root"
            else:
                assert result.stdout == b"", "partial source escaped on path race"
    finally:
        stop.set(); worker.join()
    assert not errors and count[0] > 1, (errors, count[0])
    return f"rename/symlink exchange checked across 200 reads ({count[0]} exchanges)"

def main():
    if sys.platform != "linux":
        print("source resolver race suite requires Linux; resolver is specified to fail closed elsewhere")
        return
    with tempfile.TemporaryDirectory(prefix="k1-source-resolver-") as tmp:
        tmp = pathlib.Path(tmp)
        root, outside = tmp / "root", tmp / "outside"
        root.mkdir(); outside.mkdir(); (root / "safe").mkdir()
        (root / "safe" / "main.blot").write_bytes(b"safe source\n")
        (root / "safe" / "big.blot").write_bytes(b"x" * 131073)
        (outside / "secret.blot").write_bytes(b"outside secret\n")
        (root / "inside-link.blot").symlink_to("safe/main.blot")
        (root / "outside-link.blot").symlink_to("../outside/secret.blot")
        (root / "outside-dir").symlink_to("../outside", target_is_directory=True)
        (root / "absolute-inside.blot").symlink_to(root / "safe" / "main.blot")
        (root / "broken.blot").symlink_to("missing.blot")
        (root / "bad-utf8.blot").write_bytes(b"\xff")
        (root / "empty.blot").write_bytes(b"")
        os.mkfifo(root / "fifo")
        with (root / "too-large.blot").open("wb") as f: f.truncate(LIMIT + 1)
        with (root / "exact-limit.blot").open("wb") as f: f.truncate(LIMIT)
        with (root / "growing.blot").open("wb") as f: f.truncate(LIMIT)
        root_link = tmp / "root-link"; root_link.symlink_to(root, target_is_directory=True)
        for level in (0, 2):
            fixture = tmp / f"fixture{level}"
            tests = tmp / f"resolver-test{level}"
            build("source_resolver_fixture.goose", fixture, level)
            build("source_resolver_test.goose", tests, level)
            probe = run(fixture, root, "safe/main.blot")
            if probe.returncode and b"source error 4" in probe.stderr:
                expect_error(probe)
                print("openat2 unavailable: resolver failed closed; Linux functional tests skipped")
                return
            assert probe.returncode == 0 and probe.stdout == b"safe source\n", probe.stderr
            test = subprocess.run([str(tests), str(root)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
            assert test.returncode == 0, (test.stdout, test.stderr)
            for path in ("outside-link.blot", "outside-dir/secret.blot", "absolute-inside.blot", "broken.blot",
                         "bad-utf8.blot", "fifo", "safe", "../outside/secret.blot", "/etc/passwd", "too-large.blot"):
                expect_error(run(fixture, root, path))
            inside = run(fixture, root, "inside-link.blot")
            assert inside.returncode == 0 and inside.stdout == b"safe source\n"
            empty = run(fixture, root, "empty.blot")
            assert empty.returncode == 0 and empty.stdout == b""
            expect_error(run(fixture, root_link, "safe/main.blot"))
            exact = run(fixture, root, "exact-limit.blot")
            assert exact.returncode == 0 and len(exact.stdout) == LIMIT and not any(exact.stdout), exact.stderr
        goose_home = pathlib.Path(os.environ["GOOSE_HOME"])
        headers = list((goose_home / "build" / "prog").glob("source_resolver_fixture-*/native/*/include/goose.h"))
        assert headers, "Goose native header was not produced by the fixture build"
        fault = tmp / "resolver-fault-test"
        compiler = os.environ.get("CC", "cc")
        subprocess.run([compiler, "-std=c11", "-I", str(headers[0].parent),
                        str(HERE / "source_resolver.c"), str(HERE / "source_resolver_fault_test.c"),
                        "-Wl,--wrap=malloc", "-Wl,--wrap=realloc", "-Wl,--wrap=read", "-Wl,--wrap=close", "-Wl,--wrap=syscall",
                        "-o", str(fault)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        fault_run = subprocess.run([str(fault), str(root)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        assert fault_run.returncode == 0, (fault_run.stdout, fault_run.stderr)
        print(fault_run.stdout.decode().strip())
        # Open the trusted root, rename it away, and put a different directory
        # at the original pathname. The held descriptor must retain authority
        # over the original root, not silently switch to the replacement.
        anchored = tmp / "anchored-root"; anchored.mkdir()
        (anchored / "main.blot").write_bytes(b"original\n")
        replacement = tmp / "replacement-root"; replacement.mkdir()
        (replacement / "main.blot").write_bytes(b"replacement\n")
        moved = tmp / "moved-root"
        anchor_test = tmp / "resolver-anchor-test"
        subprocess.run([compiler, "-std=c11", "-I", str(headers[0].parent),
                        str(HERE / "source_resolver.c"), str(HERE / "source_resolver_anchor_test.c"),
                        "-o", str(anchor_test)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        subprocess.run([str(anchor_test), str(anchored), str(moved), str(replacement)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert (moved / "main.blot").read_bytes() == b"original\n"
        assert (anchored / "main.blot").read_bytes() == b"replacement\n"
        unsupported = tmp / "resolver-unsupported-test"
        subprocess.run([compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-U__linux__",
                        "-I", str(headers[0].parent), str(HERE / "source_resolver.c"),
                        str(HERE / "source_resolver_unsupported_test.c"), "-o", str(unsupported)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        subprocess.run([str(unsupported)], check=True, timeout=10)
        print(race(tmp / "fixture2", root, outside))
        print("descriptor-relative source resolver tests passed at O0/O2")

if __name__ == "__main__":
    main()
