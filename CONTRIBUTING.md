# Contributing

Thanks for considering it. This project is deliberately small — four capability
packages, one umbrella, and upstream PRs — and it stays that way
([GOVERNANCE.md](GOVERNANCE.md)). The best contributions are bite-sized and
self-contained.

## Good first issues

Issues labeled `good-first-issue` are scoped to be finishable in one sitting
without holding the whole architecture in your head: a named hazard test, a
doctor diagnostic, a docs page, a CI lane fix. We keep that label stocked —
if it is empty, open an issue asking for one.

## Ground rules

- **Zero build-time native dependencies.** No `extra-libraries`, no
  `pkg-config`, no cbits in shipped libraries (test-suite-only cbits are fine).
  Native code is loaded at runtime through `keel-dyn` or not at all.
- **Windows is a first-class target.** Every PR runs the windows-latest CI
  lane; "works on Linux" is half a review.
- `default-language: GHC2021` explicitly, in every stanza. No LinearTypes, no
  OverloadedRecordUpdate, no required Template Haskell, no typechecker plugins.
- Numerical claims are tested against the Python oracle job (SciPy / pyarrow /
  scikit-learn) — a kernel PR without an oracle test is not reviewable.
- New scope (a new package, a new subsystem) is not a PR — it is a discussion
  with the owner first. See the frozen-scope rule in GOVERNANCE.md.

## Upstream work counts

Contributions this project owes upstream (Windows CI for `dataframe`,
type-error quality, Arrow inbound) are tracked here but land as PRs on
[DataHaskell/dataframe](https://github.com/DataHaskell/dataframe). Helping land
one of those counts as contributing to keel.
