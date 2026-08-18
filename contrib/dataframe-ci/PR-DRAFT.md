# PR draft — to DataHaskell/dataframe

**Title:** ci: add Windows + macOS lanes for the portable package subset

**Body:**

This adds a companion workflow (`ci-windows-macos.yml`) that builds and tests
your existing `cabal.project.ci` subset — the same project file
`haskell-ci.yml` is generated from — on `windows-latest` and `macos-14`.

Design choices, so review is quick:

- **Separate workflow file; `ci.yml` is untouched.** The ubuntu workflow keeps
  owning the libtorch path (`examples/setup_torch.sh`).
- **Reuses `cabal.project.ci` rather than inventing a target list** — that
  subset already excludes what cannot work on these runners (examples,
  dataframe-hasktorch, dataframe-arrow, dataframe-fusion) while covering
  core/parsing/operations/expr-serializer/csv(+th)/json/parquet(+th)/th/
  viz/learn/lazy/fastcsv and the meta package.
- **4 lanes** (2 GHC × 2 OS: 9.6.7 and 9.12.2, the ends of your tested range)
  to be gentle on runner minutes; trivially extendable to 9.8.4/9.10.3.
- `fail-fast: false` so a Windows-specific break doesn't hide a macOS result.

Context: I'm verifying/using the stack on Windows 11 and would like the
Windows story to be CI-enforced rather than anecdotal. I ran this workflow on
a fork first: <FORK-RUN-LINK — fill in after the fork run is green>.

**Pre-submission checklist (all must be true before opening the PR):**
- [ ] Workflow ran green (or with an honest, explained red) on our fork
- [x] Local Windows 11 build of the same targets recorded in
      docs/p0/BUILD-REPORT.md — PASS (cabal.project.ci rc=0 in 217s warm,
      GHC 9.12.4, upstream @ 3168069; sole first-run failure was MAX_PATH,
      proven environmental)
- [ ] Fork-run link filled into the body above
- [ ] Owner (Zhe Zhang) approved submission from their GitHub account
