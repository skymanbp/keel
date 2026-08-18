# Governance

These rules are release gates, not aspirations. They exist because the
documented failure mode of Haskell data-science projects is one exhausted
maintainer and an unbounded surface (see [PLAN.md](PLAN.md) §1.4).

## Scope

1. **The scope is frozen**: four capability packages (`keel-dyn`, `keel-abi`,
   `keel-onnx`, `keel-linalg`), one umbrella (`keel`), and upstream pull
   requests. The deferred list in [PLAN.md](PLAN.md) §5 is not a backlog — no
   deferred item is scheduled without explicit owner sign-off.
2. **Never fork what we can patch.** Gaps in upstream packages are closed by
   finished, tested PRs that close issues the maintainer already filed — never
   by rival packages, and never by design discussions posted as issues.

## Releases

3. **No package reaches 1.0 without two named maintainers.**
4. At 1.0, every package publishes an explicit stable/unstable module split and
   a deprecation policy: one minor release of warning, six months minimum.
5. Every package must be `cabal install`-able from Hackage on a clean Windows
   machine with no MSYS2 pacman step. A release that breaks this is pulled.

## Maintainers

| Package | Maintainers |
|---|---|
| all (pre-0.1) | Zhe Zhang (@skymanbp) |

Second maintainer seats are open — see [CONTRIBUTING.md](CONTRIBUTING.md).
