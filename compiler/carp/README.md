# Carp compiler

The **full native semantic backend** now lives in [`port/`](port/README.md). It
adds the language features, guest ABI and native session behavior missing from
the original scalar experiment, while sharing the existing source frontend. It
is AOT-generated Carp, not an interpreter or a Bend runtime fallback.

```sh
python3 compiler/carp/port/build.py release
deno task blot:carp build examples/arrays.blot build/arrays.wasm
```

Use `compiler/carp.ts` for the normal, incremental and project APIs. The
original Bend commands are retained as independent implementations; defaults
have not been silently changed. See [`port/README.md`](port/README.md) for the
precise architecture, generation pins, test coverage and remaining host resource
limits.

The earlier hand-written scalar executable is preserved separately. Its build
commands, supported subset, and limitations are documented in
[SCALAR.md](SCALAR.md).
