# Private package-root source resolver

`source_resolver.goose` is an experimental host-side seam, not public K1
admission or an import graph. The trusted compiler host opens a package root
and binds its caller-supplied package identity to a retained root descriptor.
Reads accept a logical package-relative module name and return owned source and
identity bytes. They do not infer package authority from paths or cached hashes.
No integration with the public compiler or CLI is claimed.

On Linux with the required headers and kernel support, the C adapter uses
`openat2` relative to the held descriptor with `RESOLVE_BENEATH` and
`RESOLVE_NO_MAGICLINKS`. This rejects root escapes and magic links during the
kernel path walk, including races that replace a traversed directory with an
escaping symlink. Relative symlinks that stay beneath the root are supported.
The initial root path is a trusted host mapping, not an untrusted import. Its
final component must not be a symlink. Absolute symlinks are rejected by the
kernel even when they might refer back inside the root; this conservative
restriction is not a claim of complete K1 path compatibility. Missing Linux
support, `openat2` returning ENOSYS/EINVAL, and other path errors fail closed;
there is no weaker `open`/`realpath` fallback.

The root handle is compiler-owned and valid only until close. Do not copy it,
forge it, or close/read it concurrently; this experiment has no handle table,
generation checking or locking. A renamed root is still the original opened
directory, not the new pathname. Package-root mappings, import normalization,
duplicate aliases and cycles need higher-level management. The package root
itself must be trusted for hard-link and special-file policy; the adapter checks
that opened results are regular files but does not establish content origin
against hard links. Opening a hostile device can have effects before the
post-open regular-file check, so roots allowing arbitrary device nodes require
additional host restrictions.

A 16 MiB maximum is checked before allocation and throughout reading, with a
one-byte probe if the file grows. Reads and regular-file checks happen on the
opened descriptor. Data is collected in private C scratch; after a successful
read, a second stat and successful close, it is appended once to the local
Goose buffer. Allocation, read, close and detected growth errors do not append
partial source. Concurrent in-place mutation can defeat timestamp checks on
some filesystems; this is not a filesystem snapshot guarantee. Hosts requiring
one consistent revision must provide immutable source files or stronger
snapshot coordination. C scratch allocation errors are returned, but a Goose
builder allocation failure is not recoverable by this adapter.

The executable tests run the Goose wrapper at `-O0` and `-O2`, with regular,
empty, exact-limit and oversized inputs, internal and escaping symlinks,
traversal, malformed source bytes, directories and FIFO cases. A Linux
`renameat2(RENAME_EXCHANGE)` test repeatedly switches an in-root directory and
escaping symlink during resolution. A separate linked fault harness injects
C allocation, reallocation, mid-read, close and growth failures plus unsupported
or racing `openat2`; a simulated non-Linux build verifies fail-closed stubs.
The path-race test depends on `renameat2` availability and reports if skipped.
