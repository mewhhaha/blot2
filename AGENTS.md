# Working on Blot

- This is a greenfield project. Breaking changes are welcome. Remove superseded
  APIs, implementations and compatibility scaffolding; do not retain legacy
  behavior for backward compatibility. Preserve useful requirements and
  evidence.
- The owner requests continuous checkpoints to `main`: commit and push coherent,
  checked batches as work progresses. Verify push success and report any
  failure; a local commit alone does not protect against losing the environment.
- Active source/generator migration is checkpointed, and the current reviewed
  compiler and host pass one real Gdev frame with an inspected PNG. Use
  `CONTINUE.md` for exact identities and remaining original-export/backend
  qualification; source inventory success is not whole-runtime qualification.
- Start with `CONTINUE.md` and `tasks/STORAGE_REWRITE.md`. Recheck real
  integration after semantic changes; historical evidence qualifies its exact
  candidate, not later revisions.
- Use the existing sibling checkouts `../pen`, `../ink` and `../gdev`. Preserve
  their checkpointed source and assets. Do not create a worktree unless asked.
- Current syntax uses `func`, explicit `return`, curried `->`, `$Constructor`,
  `true` / `false`, `and` / `or`, and `#[...]` array literals. Named owners,
  invocation-local borrows and explicit copies replace the old guest memory
  model. Preserve ABI 8 and session protocol 2. Language tasks are retired;
  copied-packet host workers remain.
- The compiler is written in Goose and lives in `compiler-goose/`; its README
  has the layout, the build, the generators and the tests. Deno hosts its
  client, formatter and Wasm guest API. The Zig compiler it was ported from
  was removed on 15 November 2026.
- Read `docs/language/guide.md` for language behavior and
  `docs/compiler/CONTRACT.md` for ownership rules. `docs/compiler/` describes
  the Zig compiler; the Goose modules keep the names of their Zig originals.
- The compiler's build needs clang, cmake, ninja and Python 3. Its first run
  also builds the patched Goose compiler (about two minutes).
  - `deno task build:compiler:dev` builds the debug compiler,
    `compiler-goose/build/blotc-goose-dev`, in about a minute and a half. Use
    it while developing.
  - `deno task build:compiler` builds the optimized compiler,
    `compiler-goose/build/blotc-goose`, in about seven minutes. Pen, the
    sibling checkouts and the tests' default path run this one.
- `deno task test:compiler:dev [FILES...]` builds the debug compiler and runs
  the named guest test files against it (three smoke files when none is named).
  `deno task test:guest` runs the guest and host suite against the optimized
  compiler as it is. `deno task test:compiler` is the full gate: the tooling's
  tests, the optimized build, the recorded references, the package and every
  guest and host test. Run it before committing compiler changes.
- The recorded references hold what the Zig compiler produced:
  `python3 compiler-goose/tools/test_fixtures.py` (187 programs: Wasm and
  records), `test_uniqueness.py` (lowering diagnostics) and `test_direct.py`
  (backend bytes). A deliberate change of behavior re-records them with
  `--record`; say so in the commit.
- After a module, a struct or a field is added or removed, regenerate the
  adapters as `compiler-goose/README.md` lists, then build.
- Keep semantic regression laws in the recorded references and in
  executed-Wasm tests.
- For the current integration frontier, use the tracked
  `scripts/integration/build_gdev.ts`, `report.py` and `run_pen.py` runners as
  described in `CONTINUE.md`. Run a coherent affected batch after a fix; reserve
  full qualification for the final candidate. Inspect the real PNG before
  claiming the frame milestone.
- Preserve uncommitted work.
- Keep `CONTINUE.md` focused on the current frontier, contracts and evidence.
  Use pinned Git history for superseded checkpoint narratives. Preserve task
  requirements and qualification records; document cleanup is not completion.
- Environment publication is separate and requires an explicit request.
- Do not patch generated output to fix compiler behavior; change the compiler or
  its inputs.
- File or comment on upstream issues only after the user's explicit approval.
