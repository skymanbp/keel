# P0 build report — dataframe stack on Windows 11

Date: 2026-08-18 (UTC). Machine: Windows 11 Home 10.0.26200, x86_64.
Toolchain: GHC 9.12.4 (ghcup), cabal 3.16.1.0, Hackage index
2026-08-17T22:49:30Z. Upstream: DataHaskell/dataframe @ `3168069` (2026-08-13).

## Verdict

**The Windows thesis survives.** Both build paths pass; the only failure
encountered was an environment limit (Windows MAX_PATH), not upstream code.

| # | Path | Result | Wall | Notes |
|---|---|---|---|---|
| 1a | Source tree, `cabal build all --project-file=cabal.project.ci` | ❌ first run | 278s | died unpacking a *dependency* (aeson test file), see diagnosis |
| 1b | Same, with `--builddir=%LOCALAPPDATA%\kb` | ✅ **PASS** (rc=0) | 217s¹ | all cabal.project.ci packages incl. `synthesis`/`lazy-bench` exes linked |
| 2 | Hackage releases: `dataframe ==3.5.*` + `-parquet ==1.5.*` + `-learn ==2.4.*` + `-viz ==1.3.*` | ✅ **PASS** (rc=0) | 173s¹ | smoke exe ran: `keel p0 smoke ok` |

¹ Warm-store times: run 1a spent 278s populating the shared cabal store before
failing, and 1b/2 reused it. The combined first-encounter wall clock was
~7.5 min (278s + 173s). No run here is a clean cold-install benchmark.

`dataframe-core` compiled all 37 modules on the first attempt; zstd's bundled
C sources and `dataframe-fastcsv`'s cbits both built under GHC's clang
toolchain with no MSYS2 pacman step. Zero native-dependency installs were
needed at any point.

## Diagnosis of the 1a failure (proven, not guessed)

```
Error: [Cabal-7125] Failed to unpack aeson-2.3.1.0 …
  …\dist-newstyle\tmp\src-26992\aeson-2.3.1.0\tests\JSONTestSuite\test_parsing\
  n_object_lone_continuation_byte_in_key_and_trailing_comma.json:
  withFile: does not exist (The system cannot find the path specified.)
```

cabal unpacks dependency sdists under `<builddir>\tmp\`. The working directory
for run 1a sat 106 characters deep, and the failing file's full path is
**262 characters — over Windows' MAX_PATH of 260**. The control group proves
it: run 2's project directory is 10 characters shorter, putting the *same
file* at **252 characters**, and it unpacked fine. Relocating the build dir to
a 31-character base (`--builddir`) made run 1b pass with zero other changes.

## Implications

- **For the upstream CI PR:** GitHub's `windows-latest` workspace is
  `D:\a\dataframe\dataframe` (~24 chars) — the CI lanes will not hit this.
- **For real Windows users:** a deep clone path (OneDrive folders, nested
  project trees) can push cabal's unpack tmp over 260 chars and fail on *any*
  dependency shipping long test filenames. Worth one line in upstream's docs:
  clone shallow paths, or enable Windows long paths, or use `--builddir`.
- **For keel:** same line goes in our own docs; `keel doctor` gets a
  path-length check.

## Fork CI results (2026-08-18)

Workflow `CI (Windows + macOS)` (commit `6c0fe52` on fork `skymanbp/dataframe`,
atop upstream `3168069`), run 32095552668, matrix {windows-latest, macos-14} ×
GHC {9.6.7, 9.12.2}:

| Lane | Build | Test |
|---|---|---|
| macos-14 / 9.6.7 | ✅ | ✅ |
| macos-14 / 9.12.2 | ✅ | ✅ |
| windows-latest / 9.6.7 | ✅ | ❌ (same 3 cases as below) |
| windows-latest / 9.12.2 | ✅ | ❌ |

**Build is green on all four lanes.** The Windows test failures are an
identical set on both GHC versions — OS-determined, not compiler-determined —
and all three are genuine upstream Windows-portability bugs that Linux-only CI
structurally cannot catch:

1. `toCsv_roundTrip` (dataframe main suite, 2 errors): test hardcodes the Unix
   path `/tmp/dataframe_test_toCsv_roundtrip.csv` → `withFile: does not exist`
   on Windows. Mechanical fix (`getTemporaryDirectory`).
2. `fast_roundtrip_newlines`, `fast_roundtrip_quotes_and_newlines`
   (dataframe-fastcsv suite): CRLF newline handling — expected/actual differ by
   a few characters of width, consistent with text-mode `\r\n` translation
   colliding with byte-offset assumptions.
3. `typed_quote_spans_boundary` (main suite): quote spanning a chunk boundary,
   same newline/offset class.

Suites `learn-internal`, `packed-text` and `dataframe-parsing` pass on Windows.

**P0 gate reading:** the build half of the Windows thesis is confirmed on both
the local machine and CI; the discovered test failures are the strongest
possible argument *for* the Windows CI lanes. Upstream submission (PR/issues)
is **paused by owner decision (2026-08-18)** pending further instruction.

## Reproduction

Logs: `p0_build.log` (runs 1a + 2), `p0_source_rerun.log` (run 1b) — archived
from the session scratchpad. Smoke project: a fresh cabal executable depending
on the four Hackage releases above, `main = putStrLn "keel p0 smoke ok"` plus
imports forcing the closure. Fork CI evidence:
https://github.com/skymanbp/dataframe/actions/runs/32095552668
