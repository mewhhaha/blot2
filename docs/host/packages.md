# spm

`spm` resolves Git packages into a shared cache. `squid.json` names dependencies;
each package declares its source exports in `squid-workspace.yaml`.

```sh
deno task spm init /path/to/app
deno task spm install /path/to/app
deno task squid build /path/to/app/main.sq
```

For development beside this checkout, use:

```json
{
  "dependencies": {
    "std": { "path": "../squid-lang" },
    "math": "github:your-org/math#v1.0.0"
  },
  "prelude": "std"
}
```

GitHub `owner/repo`, `github:owner/repo`, and Git HTTP, SSH, Git or file URLs
work. An optional `#branch`, `#tag` or `#commit` selects a revision; omission
selects the repository's HEAD. Local `path` dependencies resolve relative to
their declaring manifest and remain live.

The nearest `squid.json` above the entry file configures `squid check`, `build`
and `dependencies`. **Omitting `prelude` means no prelude.** `null` also
disables it. A selected prelude names a direct dependency whose workspace
declares that file. Explicit CLI prelude, standard-root and alias options
override project defaults. Projects without a manifest keep the existing CLI
defaults.

## Package exports

```yaml
name: math
exports:
  .: ./src
  geometry: ./geometry
prelude: ./src/prelude.sq
```

The optional name is descriptive. Exports map names to directories. With a
dependency named `math`, `.` provides `math/`; `geometry` provides
`math/geometry/`. Import `"math/vector"` to load `src/vector.sq`. The optional
prelude is a `.sq` file. This checkout exports `std/` through its default
directory and declares `std/prelude.sq` as its selectable prelude.

Exports must exist inside the workspace, including after symlink resolution.
Packages may have their own `squid.json` dependencies; downloaded packages' local
dependencies must stay inside their repository. One dependency name has one
source throughout the graph. Conflicting transitive names report an error; this
version does not select among competing versions.

## Revisions and cache

`spm install` writes `squid.lock.json` with exact Git commits. Later installs
preserve those commits. `spm update` explicitly resolves refs again. Commit the
lock file with the project. `spm install --frozen` requires an unchanged lock
and fetches missing pinned checkouts without changing it.

Builds resolve cached packages without fetching. Missing packages report
`spm install`; modified cached checkouts are rejected. Downloads publish through
temporary directories, and the lock changes only after the whole graph succeeds.
A failed install preserves the previous lock. Local packages are not copied or
pinned.

The cache defaults to `$XDG_CACHE_HOME/spm` or `$HOME/.cache/spm`.
`SPM_CACHE_DIR` selects another cache for both install and builds; install also
accepts `--cache DIR`. No package scripts run. Git performs repository access
using the user's normal Git authentication.

Hosts can resolve the same configuration explicitly:

```ts
import { createCompiler, resolveProject } from "@mewhhaha/squid";

const entry = "/path/to/app/main.sq";
const project = await resolveProject(entry);
const compiler = await createCompiler({ ...project, entry });
// Build and dispose through the ordinary compiler API.
```

Direct source:
`deno run --allow-read --allow-write --allow-run=git
--allow-env=HOME,XDG_CACHE_HOME,SPM_CACHE_DIR host/spm.ts …`.
The package exports the manager at `@mewhhaha/squid/spm` and its API at
`@mewhhaha/squid/packages`. YAML uses
[Deno's standard parser](https://jsr.io/@std/yaml).

## Qualification

Local milestone `2798ff9` passes twelve package/CLI laws, standalone public API
checks and the full compiler gate (844 guest/client laws). Tests use local Git
repositories and cover lock/update/frozen behavior, clean cache validation,
transitive exports, manifest errors and explicit/omitted preludes. A warm single
Git-package cache resolves in a 2.721 ms median over 31 runs (2.095–4.846 ms),
without network access. Raw package evidence is ignored under
`build/bench/joint-029-032-037-spm/`; no package was published.
