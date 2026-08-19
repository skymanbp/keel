# Governance

These rules are release gates, not aspirations. They exist because the
documented failure mode of Haskell data-science projects is one exhausted
maintainer and an unbounded surface (see [PLAN.md](PLAN.md) §1.4).

## Scope

1. **The scope is frozen**: four capability packages (`keel-dyn`, `keel-abi`,
   `keel-onnx`, `keel-linalg`) and one umbrella (`keel`); dataframe is
   consumed as a Hackage dependency only. The deferred list in [PLAN.md](PLAN.md) §5 is not a backlog — no
   deferred item is scheduled without explicit owner sign-off.
2. **Never fork, never rival.** keel does not reimplement anything the
   dataframe stack provides. Upstream bugs we find are reported; fixing them
   is separate upstream-repo work outside this project's scope (owner
   decision, 2026-08-18).

## Releases

3. **No package reaches 1.0 without two named maintainers.**
4. At 1.0, every package publishes an explicit stable/unstable module split and
   a deprecation policy: one minor release of warning, six months minimum.
5. Every package must be `cabal install`-able from Hackage on a clean Windows
   machine with no MSYS2 pacman step. A release that breaks this is pulled.

## Maintainers

| Package | Maintainers |
|---|---|
| all (0.1.x) | Zhe Zhang (@skymanbp) |

Second maintainer seats are open — see [CONTRIBUTING.md](CONTRIBUTING.md).
