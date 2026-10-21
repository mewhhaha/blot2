# Working on Blot

- Use Zig 0.17.0. Check `zig version` before each build batch.
- The compiler lives in `zig-native/`; Deno hosts its client, formatter and Wasm
  guest API.
- Read `compiler/guide.md` for language behavior and `zig-native/CONTRACT.md`
  for ownership rules.
- Always use Zig's native backend without LLVM (`-Dllvm=false`) for development
  builds and all native unit-test compilation, including the full gate. Use
  `deno task check:dev --area static-sharing` for a five-minute development
  cycle. It compiles the complete native inventory once, runs an explicit
  regression family with sampled allocation faults, guests and local checks. It
  reports full qualification as pending. An incomplete run is not a pass.
- Reserve LLVM (`-Dllvm=true`) for the actual final release compiler and release
  performance measurements. Use `deno task build:compiler` for releases; qualify
  the final candidate with `deno task test:compiler`.
- Keep semantic regression laws in Zig and executed-Wasm tests. Run
  `deno task test:compiler` before committing compiler changes.
- For a focused native test, run
  `zig build test -Doptimize=safe -Dllvm=false
  --prefix zig-out-native-dev -Dtest-filter="test name"`
  in `zig-native/`. The full compiler gate is still required before committing
  compiler changes.
- `check:dev` and the full gate both compile the complete native suite with
  `-Dllvm=false --prefix zig-out-native-dev`, catching generic mock/interface
  errors outside focused tests. Full native execution defaults to exhaustive
  allocation-failure sweeps; sampled development checks never replace it.
- The installed test binary supports `--test=EXACT_INVENTORY_NAME` and emits
  `BLOT_NATIVE_TEST` timing records. Prefer runtime selection over creating a
  separate large executable for each filter. Keep correctness boundary cases
  when reducing a slow fixture; measure per-test time before changing scale.
- Run `deno task lint:zig` (zig-analyzer from `$ZIG_ANALYZER` or
  `../zig-analyzer/zig-out/bin/zig-analyzer`). `zig-native/src` must stay at
  zero findings; CI enforces it.
- Preserve uncommitted work. Measure fresh builds and retained edits separately.
- Do not patch generated output to fix compiler behavior; change the compiler or
  its inputs.
- File or comment on upstream issues only after the user's explicit approval.
