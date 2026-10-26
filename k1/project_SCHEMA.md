# Private source-graph and revision fixture

This experiment reads a package-relative entry file and its transitive imports
through the existing descriptor-relative source resolver. It builds a bounded
source/import graph with exact logical paths, raw source bytes, import aliases
and independently re-recognized import preambles. It does not parse complete
module declarations or perform name/type/effect/proof/resource checking. A
successful graph is not a successful K1 compilation, checked artifact, project
server, cache receipt or artifact provenance certificate.

The producer accepts the fixed `import "path" as alias` preamble shape, with
imports before other tokens, and checks the whole file lexically. Duplicate
aliases, malformed/escaped path spellings, root escapes and cycles reject.
The loader is deliberately limited to 64 modules, 256 import edges, 64
explicit probes, 4,096 bytes per logical path, 512 KiB of path metadata and
16 MiB of combined source/probe bytes. Exceeding one of these private fixture
bounds declines this path; it is not a claim that the complete language rejects
that project. There is no complete C09 accounting or diagnostic catalogue here.

Each caller-supplied source-file probe records query kind, exact querying module,
original relative spelling, normalized target, positive/negative status, and
all observed positive source bytes. Import aliases are tied to exact source
spans. Comparison uses complete bytes and ordered records, never digest-only
authority. Only source-file probes are supported. They are explicitly supplied
by trusted caller code; the loader does not discover compiler declaration,
provider, static-value, type, ABI or negative-name dependencies, and its probe
set is not a complete K1 dependency query log.

A failed source read and the ENOENT-only negative probe are **separate syscalls**.
A concurrently changing filesystem can change between them: absence is only the
later probe's observation, not an atomic project snapshot or authoritative
negative dependency under concurrent mutation. All modules and probes are read
sequentially and can represent different filesystem moments. Even one file's
metadata checks cannot guarantee an immutable snapshot against a hostile writer.
The host must provide immutable files or stronger snapshot coordination before
these records can support compiler reuse. Errors other than a separately
observed ENOENT fail closed rather than becoming a negative observation.

The trusted host opens and exclusively owns the Root. It must not copy it,
close it, replace its descriptor, or use it concurrently during a graph/session
request. A revision session binds that held descriptor and exact package bytes;
a close followed by descriptor reuse could defeat this convention. The initial
package-root mapping, hard links, device nodes, absolute-symlink restriction and
Linux/openat2 fallback assumptions are described in `SOURCE_RESOLVER.md`.
The test harness skips Linux-only graph and race fixtures on other hosts, while
building and checking that both unsupported source adapters fail closed.

Every revision request rebuilds the graph and observations; unchanged graphs
are recognized by exact comparison but do not skip source reads or produce a
compilation speed claim. A changed graph is staged in an owned value before it
is appended and its generation becomes current. Invalid source/imports,
missing modules, I/O failures, cycles and explicit test interruptions preserve
the prior active generation. The append and generation update are not a
concurrent publication protocol, and process OOM/asynchronous cancellation
are not recoverable here. At the private eight-version cap, the caller gets a
fresh unretained graph and must not treat the prior revision as its result.
