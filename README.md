# keel

[![ci](https://github.com/skymanbp/keel/actions/workflows/ci.yml/badge.svg)](https://github.com/skymanbp/keel/actions/workflows/ci.yml)

**keel is not a new dataframe.**

keel is a native-capability and interop floor for Haskell data science. The
pandas/scikit-learn/plotting tiers of the Haskell ecosystem already exist and
ship weekly — they belong to the [DataHaskell `dataframe`
monorepo](https://github.com/DataHaskell/dataframe), and keel builds beside it,
never against it. keel adds only capability Haskell does not have at all, adds
it on Windows first, under MIT, with **zero build-time native dependencies**.

> A keel is laid first, defines the ship, and never becomes the ship.

## What keel provides

| Package | Capability |
|---|---|
| `keel-dyn` | Cross-platform *runtime* loading of native libraries (LoadLibraryW / dlopen) — the reason nothing below ever needs a C toolchain at `cabal install` time |
| `keel-abi` | Arrow C Data + C Stream Interface (both directions — inbound is new to Haskell) and DLPack tensor exchange |
| `keel-onnx` | ONNX Runtime **inference** bindings under MIT: train anywhere (PyTorch / scikit-learn), run in Haskell, on Windows, with GPU |
| `keel-linalg` | CBLAS + LAPACKE over OpenBLAS, resolved at runtime — BLAS that actually installs on Windows |
| `keel` | Umbrella + `keel doctor` (what resolved, what didn't, the one command that fixes it) + `keel setup` (checksum-pinned native runtimes) |

## What keel is NOT

- **Not a dataframe, not a CSV/Parquet reader, not a query engine** — use
  [`dataframe`](https://hackage.haskell.org/package/dataframe).
- **Not an ML library** — use
  [`dataframe-learn`](https://hackage.haskell.org/package/dataframe-learn).
- **Not a plotting library** — use
  [`dataframe-viz`](https://hackage.haskell.org/package/dataframe-viz).
- **Not an autodiff engine, not a neural-network trainer, not a GPU kernel
  library, not a numeric prelude.** Every prior Haskell DS project that started
  there died there.

keel never ships a rival implementation of anything the dataframe stack
provides. Upstream gaps and bugs we find are reported; fixing them is separate
upstream-repo work outside this project.

## Status

**v0.1.0.0 is on Hackage** —
[keel](https://hackage.haskell.org/package/keel) /
[keel-dyn](https://hackage.haskell.org/package/keel-dyn) /
[keel-abi](https://hackage.haskell.org/package/keel-abi) /
[keel-linalg](https://hackage.haskell.org/package/keel-linalg) /
[keel-onnx](https://hackage.haskell.org/package/keel-onnx) —
so `cabal install keel` works directly; the
[GitHub Release](https://github.com/skymanbp/keel/releases/tag/v0.1.0.0)
mirrors the sdists. **P0 (falsification) passed 2026-08-18**: the
dataframe stack builds on Windows 11 locally and on CI —
[docs/p0/BUILD-REPORT.md](docs/p0/BUILD-REPORT.md).

All five packages are implemented and green on the full CI matrix —
Windows, Linux and macOS (arm64) × GHC {9.10, 9.12, 9.14} — with the
conformance suites **required** (a skipped suite fails the build):
pyarrow round-trips the Arrow C Data and Stream Interfaces in both
directions in-process; numpy round-trips DLPack v1 tensors both ways;
every keel-linalg driver is cross-checked against numpy/LAPACK to 1e-10;
the headline demo — train in scikit-learn, export with skl2onnx, run in
Haskell — agrees with python's own onnxruntime to 1e-6; and CI installs
OpenBLAS on Windows through `keel setup blas` itself, end-to-end.
Start with the [tutorials](docs/tutorials/). Research provenance for every
claim: [docs/research/](docs/research/).

## License

[MIT](LICENSE) — matching upstream `dataframe`, keeping the licensing story
across the ecosystem uniform.
