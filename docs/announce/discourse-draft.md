# Discourse post draft (Haskell Discourse)

> Status: DRAFT — publish only on owner's go-ahead. Suggested timing:
> right after the Hackage 0.1 batch lands, so readers can cabal-install
> the packages named here.
> Every claim in this draft is backed by CI runs on the public repo.

**Title:** keel: a capability floor for Haskell data science (not a new dataframe)

**Body:**

This is not a new dataframe. The dataframe/sklearn/plotting tiers of
Haskell data science already exist, ship weekly, and belong to the
DataHaskell `dataframe` monorepo — keel builds beside that stack, never
against it.

keel adds exactly three capabilities Haskell did not have, plus the
floor they stand on, with **zero build-time native dependencies** — and
all of it works today, verified in CI on Windows, Linux and macOS
(arm64) across GHC 9.10/9.12/9.14:

1. **ONNX Runtime inference under MIT** (`keel-onnx`) — train in
   scikit-learn/PyTorch, run the model in Haskell. The CI demo trains a
   LogisticRegression in sklearn, exports it with skl2onnx, executes it
   through keel, and compares against Python's own onnxruntime:
   agreement is 0.0 (the gate is 1e-6). (The one prior binding is
   AGPL-3.0-only and frozen.)
2. **Inbound Apache Arrow + DLPack** (`keel-abi`) — the Arrow C Data
   and C Stream Interfaces in both directions (Haskell previously had
   export-only), plus DLPack v1 tensors. Conformance is pyarrow and
   numpy loaded *in the same process*, round-tripping real data with
   ownership callbacks verified on both sides.
3. **BLAS/LAPACK that installs on Windows** (`keel-linalg`) — CBLAS +
   LAPACKE over a runtime-loaded OpenBLAS: solve, least squares, SVD,
   eigen, QR, Cholesky, inverse — every driver cross-checked against
   numpy/LAPACK to 1e-10 in CI. ILP64 builds and symbol-renamed wheels
   are refused instead of silently corrupting.

The floor: `keel-dyn` (runtime loading with a documented search policy)
and the `keel` umbrella — `keel setup` installs SHA-256-pinned official
OpenBLAS/ONNX Runtime archives into a per-user dir (CI itself installs
OpenBLAS on Windows this way, every run), and `keel doctor` tells you
exactly what resolved, what didn't, and the one command that fixes it.
The only contact with the dataframe stack is an explicit, honest
frame↔buffer copy (`Keel.Bridge`, over `dataframe-core` on Hackage).

Repo, tutorials, plan and research provenance:
https://github.com/skymanbp/keel

**Looking for a design partner:** if you have a real workload that needs
ONNX inference (or Arrow interchange) from Haskell, your constraints
before 1.0 are worth more than any amount of speculative API design —
open an issue or reply here.
