# Layout probes

These standalone probes are experiments, not compiler dependencies. Compile each
with the same OxCaml selected for the compiler:

```sh
ocamlopt local_cursor.ml -o /tmp/local-cursor && /tmp/local-cursor
ocamlopt mixed_word.ml -o /tmp/mixed-word && /tmp/mixed-word
```

The local cursor passes a strict zero-allocation check. The production decoder
keeps one private heap cursor per request rather than duplicating the parser for
stock OCaml; most decoding allocation is the immutable output tree.

The `int32#` character layout saves a box but rejects generic equality on the
mixed block. It is not substituted into the compiler. The retained `word32`
representation instead uses an unboxed, typed wrapper over a 63-bit native int,
with explicit 32-bit wrapping and independent scalar/bit-pattern tests. It
retains compatibility with ordinary polymorphic containers and equality.

See the parent `MEMORY_CONCURRENCY.md` for measurements and boundaries. These
small layout examples do not establish whole-compiler performance.
