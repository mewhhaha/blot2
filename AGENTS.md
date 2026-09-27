# Bend

When using Bend:

- Use the latest released Bend. Check the installed version before each build
  batch, since the user may update it; keep the compiler, Base, and JavaScript
  loader on the same release throughout that batch.
- Run `bend guide` to learn it.
- Use `LAWS.bend` to keep important rules.
- Run `bend PROOF.bend` before committing.
- Parallelize the code whenever possible.

## Generated output and upstream issues

- Use Bend's generated output unchanged. Do not patch emitted C or JavaScript.
- Adapt Blot source or its host interfaces when integration changes are needed.
- Record suspected Bend bugs in `BUGS.md`, with the affected version, evidence,
  and a reproducer. Distinguish correctness bugs from performance limitations.
- File or comment on upstream issues only after the user's explicit approval.
