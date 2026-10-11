# Pending selection work

Task 097's remaining fixture exhausted inference while unrelated generic
callback operators were retried at each stage. An unresolved member/operator
receiver now sleeps on its type variable. The existing chronological queue wakes
it when that variable changes; rollback invalidates watches. Suspended checks,
known receivers and other pending kinds retain their existing scheduling. No
inference budget, language default or generic interface admission changes.

A proposed shortcut retaining closed callee graphs was rejected: it accepted an
invalid member call in an unused declaration and changed diagnostic locations.
The final implementation keeps all obligations and type graphs, and only removes
retries that cannot make progress.

## Qualification, 11 October 2026

Baseline: `5340ef2`. Implementation revision: `881c6ab`.

- The public 64-callback, 51-stage reduction drops from 974,824 to 269,363
  inference steps. Its 264,911 obligations, 913,566 type nodes, 545,242 effect
  rows and 13,077-byte Wasm are unchanged. A 100-stage case compiles at 994,808
  steps; 101 stages reject at the unchanged one-million-step module budget.
- A native regression at two depths fails the previous implementation's bound of
  two inference steps per appended obligation. Executed-Wasm laws preserve
  fresh/retained rejection agreement, zero live requested memory after CLI
  teardown, and recovery to the original bytes and result, 204.
- Five diagnostic probes, including unused invalid calls and private effects,
  preserve ordered JSON diagnostics exactly. All 13 public examples and all four
  synthetic workloads preserve Wasm bytes in fresh and retained phases.
- The current read-only gdev suite passes all 472 cases across 54 modules: 375
  executed exports (1,434 assertions), 91 expected traps and six expected
  rejections. The remaining blocked split-hauling module compiles and passes all
  12 exports and 25 assertions. The previously blocked app/sandbox cases now
  live in the regular suite. This qualifies the current checkout rather than
  assuming the original report's fixture count is unchanged.
- Frozen gdev output stays at 840,534 bytes, SHA-256
  `3158216b0b7cb072245d9aa149887a39bbadbc305430569ae3e033818e3edef0`.
  Edit/revert/rejection recovery also preserves the matching phase's bytes.

`deno task test:compiler` passes the full native suite and 690 guest/client
tests on Zig 0.17.0. The analyzer reports zero findings across 318 files,
including three unregistered native asset files under development.

Three alternating gdev pairs measure child CPU in milliseconds, with 10 ms
resolution. Concurrent LLVM compilation and variable host load prevent an
established general speedup. Baseline uses its archived compatible host client;
the candidate uses explicit protocol-version admission. Child CPU excludes both
hosts' work.

| Phase                 | Baseline min / median / max | Candidate min / median / max |
| --------------------- | --------------------------- | ---------------------------- |
| Fresh                 | 1390 / 1430 / 3470          | 1430 / 1600 / 1620           |
| Edit                  | 620 / 900 / 1160            | 650 / 700 / 710              |
| Revert                | 570 / 820 / 970             | 560 / 630 / 730              |
| Rejected              | 290 / 370 / 570             | 300 / 300 / 300              |
| No-op after rejection | 0 / 10 / 10                 | 0 / 0 / 10                   |
| Fresh edited          | 1370 / 2030 / 3280          | 1400 / 1400 / 1490           |

[Binary pins and public counters](qualification/pending-selections-pins.json)
and [paired samples](qualification/pending-selections-gdev.csv) distinguish the
measured executable from the final qualified executable. Their production code
is identical; adding a native test changed the source fingerprint. The final
pinned executable also compiles and executes the blocked fixture.

This removes waste counted against inference's work limit. It does not solve the
chain's quadratic obligation/type growth: requested allocation rises from about
813 MB to 832 MB at 51 stages, with peak live allocation rising from about 159
MB to 171 MB. Shared generic-body import remains a separate performance hill.
