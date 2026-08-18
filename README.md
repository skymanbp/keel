# keel

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

Gaps we find in the packages above are closed by upstream pull requests, never
by rival implementations.

## Status

Pre-release — currently in **P0**, the falsification phase of
[PLAN.md](PLAN.md): donate Windows + macOS CI to the dataframe monorepo and
prove the whole stack builds on Windows 11 before a line of library code is
written. Research provenance for every claim: [docs/research/](docs/research/).

## License

[MIT](LICENSE) — matching upstream `dataframe`, so code moves upstream without
relicensing friction.
