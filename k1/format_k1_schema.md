# Private K1 formatting experiment

`format_k1_formatter::format` accepts only whole sources that the private
tagged compiler can already check and emit: the U32/Bool scalar subset and the
original bounded U32 iteration subset. The newer mixed scalar/loop variant is
not yet formatted. It normalizes CRLF to LF and removes
trailing spaces/tabs from code-only lines. It preserves indentation, token
spellings, comment text including trailing spaces, blank-line content, and the
presence or absence of the final newline. This is not yet general pretty
printing or a formatter for the full K1 grammar; valid unsupported source is
rejected without output.

Before returning bytes it reparses both sources, rechecks both candidates,
compares significant tokens, typed nodes and binding identities, and requires
identical emitted test Wasm. For iteration, source-byte offsets may change;
function/loop transfer targets and binding scopes are compared by significant
token ordinal, not equal numeric offsets. Any invalid input or disagreement
returns a failure with no formatted bytes and never mutates the caller's input.
These checks establish this fixture's round-trip behavior, not full K1 grammar,
formatter or qualification laws. Work is unmetered and source limits are those
of the tagged compiler.

The existing `blot fmt` uses `compiler/format.ts` and the legacy frontend; this
experiment is not wired into that command. K1 editor support also remains open:
implement edition-aware grammar and highlighting in their source files (including
`grammar.baba` and `editor/tree-sitter-blot2/grammar.js` as appropriate),
regenerate rather than hand-edit parser artifacts, add K1 corpus/highlight and
formatter target-preservation tests, and run the corresponding parser/editor and
compiler gates. The existing tree-sitter grammar is deliberately permissive
highlighting, not the validating K1 parser.
