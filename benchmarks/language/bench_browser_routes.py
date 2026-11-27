"""Measure the Gdev route fixture once per browser animation frame."""
import argparse
import gzip
import hashlib
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chrome", required=True)
    parser.add_argument("--wasm", type=Path, required=True, help="compiled spark_routes.sq from the Gdev project")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    wasm = args.wasm.read_bytes()
    results = []
    with tempfile.TemporaryDirectory() as temp:
        scratch = Path(temp)
        bundle = scratch / "routes.js"
        subprocess.run(["deno", "bundle", "--platform", "browser", "--no-config",
                        ROOT / "benchmarks/language/browser_routes.js", "-o", bundle], check=True)
        files = {"/": ("text/html", b'<script type="module" src="/routes.js"></script>'),
                 "/routes.js": ("text/javascript", bundle.read_bytes()), "/routes.wasm": ("application/wasm", wasm)}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path not in files:
                    self.send_error(404)
                    return
                kind, data = files[self.path]
                self.send_response(200)
                self.send_header("Content-Type", kind)
                self.send_header("Cross-Origin-Opener-Policy", "same-origin")
                self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
                self.end_headers()
                self.wfile.write(data)

            def do_POST(self):
                if self.path != "/result":
                    self.send_error(404)
                    return
                results.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
                self.send_response(204)
                self.end_headers()

            def log_message(self, fmt, *values):
                pass

        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            # HTTP/1.0 and no browser preconnects for an unused socket.
            server.timeout = .5
            flags = ["--headless", "--disable-background-timer-throttling", "--disable-backgrounding-occluded-windows",
                     "--disable-renderer-backgrounding", "--disable-features=PreconnectToSearch"]
            cmd = [args.chrome, *flags, "--user-data-dir=" + str(scratch / "profile"),
                   f"http://127.0.0.1:{server.server_port}/"]
            with (scratch / "chrome.log").open("w+") as log:
                proc = subprocess.Popen(cmd, stdout=log, stderr=log)
                try:
                    end = time.monotonic() + 300
                    while not results and proc.poll() is None and time.monotonic() < end:
                        server.handle_request()
                    if not results:
                        log.seek(0)
                        raise RuntimeError("Browser produced no result. " + log.read()[-1500:])
                finally:
                    proc.terminate()
                    proc.wait(timeout=10)
        value = results[0]
        if "error" in value:
            raise RuntimeError(value)
        result = value["result"]
        result.update(wasmSha256=hashlib.sha256(wasm).hexdigest(), flags=flags,
                      chromeVersion=subprocess.check_output([args.chrome, "--version"], text=True).strip(),
                      affinity=sorted(os.sched_getaffinity(0)))
        with gzip.open(args.output, "wt") as f:
            json.dump(result, f, separators=(",", ":"))
        print(f"{len(result['runs'])} browser comparisons written to {args.output}")


if __name__ == "__main__":
    main()
