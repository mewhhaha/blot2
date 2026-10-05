# Working on Blot

- Use Zig 0.17.0. Check `zig version` before each build batch.
- The compiler lives in `zig-native/`; Deno hosts its client, formatter and Wasm
  guest API.
- Read `compiler/guide.md` for language behavior and `zig-native/CONTRACT.md`
  for ownership rules.
- Use `deno task build:compiler` for release builds and
  `deno task build:compiler:dev` for incremental compiler development.
- Keep semantic regression laws in Zig and executed-Wasm tests. Run
  `deno task test:compiler` before committing compiler changes.
- Use `../zig-analyzer/zig-out/bin/zig-analyzer check zig-native/src` when
  available.
- Preserve uncommitted work. Measure fresh builds and retained edits separately.
- Do not patch generated output to fix compiler behavior; change the compiler or
  its inputs.
- File or comment on upstream issues only after the user's explicit approval.
