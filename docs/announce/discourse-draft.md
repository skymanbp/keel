# Discourse post draft (Haskell Discourse)

> Status: DRAFT, deferred by owner. The CI-PR gate no longer applies
> (upstream-PR work removed from scope 2026-08-18); if published later, cite
> the fork CI results (docs/p0/BUILD-REPORT.md) instead of a PR link.

**Title:** keel: a capability floor for Haskell data science (not a new dataframe)

**Body:**

This is not a new dataframe. The dataframe/sklearn/plotting tiers of Haskell
data science already exist, ship weekly, and belong to the DataHaskell
`dataframe` monorepo — keel builds beside that stack, never against it.

keel adds exactly three capabilities Haskell currently does not have, plus the
floor they stand on, with zero build-time native dependencies:

1. **ONNX Runtime inference under MIT** — train in PyTorch/scikit-learn, run
   the model in a Haskell service, on Windows, with GPU. (The one existing
   binding is AGPL-3.0-only and frozen at 0.1.0.0.)
2. **Inbound Apache Arrow** — the Arrow C Data + C Stream Interface in both
   directions. Haskell today has export-to-Python only; both prior import
   attempts died at 1 and 6 commits.
3. **BLAS/LAPACK that installs on Windows** — cblas/lapacke over OpenBLAS,
   resolved at *runtime* through a ~300-line dynamic loader, so
   `cabal install` can never fail on a missing C library.

First deliverable, before any library code: Windows + macOS CI donated to the
dataframe monorepo (PR: <LINK>), plus a published build report of the whole
dataframe stack on Windows 11. If the Windows thesis is wrong, we want to find
out at week 1, not week 30.

Repo: <REPO-LINK> (plan, research provenance with sources, and governance —
including the rule that gaps we find upstream are closed by PRs there, never by
rival packages here).
